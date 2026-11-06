namespace Hanasu.Core.Transcription;

/// <summary>Whisper の ggml モデル 1 つ。Bytes と Sha256 は Hugging Face の LFS の値（ダウンロードしたものと比べる）</summary>
public sealed record WhisperModelInfo(string Id, string FileName, long Bytes, string Sha256, string Description)
{

    public long ApproximateBytes => Bytes;

    /// <summary>whisper.cpp の作者が Hugging Face で配っているモデル</summary>
    public Uri DownloadUri => new($"https://huggingface.co/ggerganov/whisper.cpp/resolve/main/{FileName}");

    public string SizeLabel => ApproximateBytes >= 1_000_000_000
        ? $"{ApproximateBytes / 1_000_000_000.0:0.0} GB"
        : $"{ApproximateBytes / 1_000_000.0:0} MB";

    public string Label => string.Format(Strings.WhisperModel_Label, Id, SizeLabel, Description);
}

public static class WhisperModelCatalog
{
    // 説明は表示の言語（起動のときに決めた UI のカルチャで、初めて使うときに読む。REQ-COM-060）
    public static readonly IReadOnlyList<WhisperModelInfo> Models =
    [
        new("tiny", "ggml-tiny.bin", 77_691_713, "be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21",
            Strings.WhisperModel_Tiny),
        new("base", "ggml-base.bin", 147_951_465, "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe",
            Strings.WhisperModel_Base),
        new("small", "ggml-small.bin", 487_601_967, "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b",
            Strings.WhisperModel_Small),
        new("medium", "ggml-medium.bin", 1_533_763_059, "6c14d5adee5f86394037b4e4e8b59f1673b6cee10e3cf0b11bbdbee79c156208",
            Strings.WhisperModel_Medium),
        new("large-v3-turbo-q5_0", "ggml-large-v3-turbo-q5_0.bin", 574_041_195, "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2",
            Strings.WhisperModel_LargeTurboQ5),
        new("large-v3-turbo", "ggml-large-v3-turbo.bin", 1_624_555_275, "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69",
            Strings.WhisperModel_LargeTurbo),
    ];

    public static WhisperModelInfo? Find(string? id) =>
        Models.FirstOrDefault(m => string.Equals(m.Id, id, StringComparison.OrdinalIgnoreCase));
}

public enum WhisperModelStatus { NotDownloaded, Downloading, Downloaded, Failed }

public sealed record WhisperModelState(WhisperModelInfo Model, WhisperModelStatus Status, double Progress = 0, string? Error = null);

/// <summary>
/// Whisper のモデルのダウンロード・取り消し・削除。保存先は <c>%LOCALAPPDATA%\Hanasu\Models</c>。
/// ダウンロード中は「.download」の名前で書き、大きさと SHA-256 を確かめてから名前を変える（ModelDownload）。
/// 会議の記録でも同じモデルを使う。
/// </summary>
// 設計判断: DEC-COM-146
public sealed class WhisperModelManager
{
    private readonly HttpClient http;
    private readonly object gate = new();
    private readonly Dictionary<string, (CancellationTokenSource Cts, double Progress)> downloads = new();
    private readonly Dictionary<string, string> failures = new();

    public string Directory { get; }

    /// <summary>状態が変わったとき（進み具合も含む）。どのスレッドから来るかは決めない</summary>
    public event EventHandler<WhisperModelState>? StateChanged;

    public WhisperModelManager(string directory, HttpClient? http = null)
    {
        Directory = directory;
        this.http = http ?? SafeHttp.CreateForDownloads();
    }

    /// <summary>どれかのモデルをダウンロード中か（アップデートの入れ替え前の確認に使う）</summary>
    public bool IsAnyDownloading { get { lock (gate) return downloads.Count > 0; } }

    public string PathFor(WhisperModelInfo model) => Path.Combine(Directory, model.FileName);

    /// <summary>置いてあり、大きさが合っているか（ハッシュはダウンロードのときに確かめている。毎回は計算しない）</summary>
    public bool IsDownloaded(WhisperModelInfo model)
    {
        var info = new FileInfo(PathFor(model));
        return info.Exists && info.Length == model.Bytes;
    }

    public WhisperModelState StateOf(WhisperModelInfo model)
    {
        lock (gate)
        {
            if (downloads.TryGetValue(model.Id, out var d)) return new(model, WhisperModelStatus.Downloading, d.Progress);
            if (IsDownloaded(model)) return new(model, WhisperModelStatus.Downloaded, 1);
            if (failures.TryGetValue(model.Id, out var error)) return new(model, WhisperModelStatus.Failed, 0, error);
            return new(model, WhisperModelStatus.NotDownloaded);
        }
    }

    /// <summary>ダウンロードを始める（もうあれば何もしない）。終わるか失敗するまで待つ Task を返す</summary>
    public Task DownloadAsync(WhisperModelInfo model)
    {
        CancellationTokenSource cts;
        lock (gate)
        {
            if (downloads.ContainsKey(model.Id) || IsDownloaded(model)) return Task.CompletedTask;
            cts = new CancellationTokenSource();
            downloads[model.Id] = (cts, 0);
            failures.Remove(model.Id);
        }
        Raise(model);
        return Task.Run(() => RunDownloadAsync(model, cts));
    }

    public void CancelDownload(WhisperModelInfo model)
    {
        lock (gate)
        {
            if (downloads.TryGetValue(model.Id, out var d)) d.Cts.Cancel();
        }
    }

    /// <summary>ダウンロードしたモデルを消す</summary>
    public void Delete(WhisperModelInfo model)
    {
        CancelDownload(model);
        var path = PathFor(model);
        if (File.Exists(path)) File.Delete(path);
        lock (gate) failures.Remove(model.Id);
        Raise(model);
    }

    private async Task RunDownloadAsync(WhisperModelInfo model, CancellationTokenSource cts)
    {
        try
        {
            System.IO.Directory.CreateDirectory(Directory);
            var lastReported = -1.0;
            await ModelDownload.DownloadVerifiedAsync(http, model.DownloadUri, PathFor(model), model.Sha256, model.Bytes, (received, total) =>
            {
                var progress = total > 0 ? Math.Min(1.0, (double)received / total) : 0;
                if (progress - lastReported < 0.005) return;
                lastReported = progress;
                lock (gate) downloads[model.Id] = (cts, progress);
                Raise(model);
            }, cts.Token).ConfigureAwait(false);
        }
        catch (Exception e)
        {
            if (e is not OperationCanceledException)
            {
                lock (gate) failures[model.Id] = e.Message;
            }
        }
        finally
        {
            lock (gate) downloads.Remove(model.Id);
            cts.Dispose();
            Raise(model);
        }
    }

    private void Raise(WhisperModelInfo model) => StateChanged?.Invoke(this, StateOf(model));
}
