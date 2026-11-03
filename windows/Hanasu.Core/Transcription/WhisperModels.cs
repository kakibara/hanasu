namespace Hanasu.Core.Transcription;

/// <summary>Whisper の ggml モデル 1 つ。</summary>
public sealed record WhisperModelInfo(string Id, string FileName, long ApproximateBytes, string Description)
{
    /// <summary>whisper.cpp の作者が Hugging Face で配っているモデル</summary>
    public Uri DownloadUri => new($"https://huggingface.co/ggerganov/whisper.cpp/resolve/main/{FileName}");

    public string SizeLabel => ApproximateBytes >= 1_000_000_000
        ? $"{ApproximateBytes / 1_000_000_000.0:0.0} GB"
        : $"{ApproximateBytes / 1_000_000.0:0} MB";

    public string Label => $"{Id}（{SizeLabel}）— {Description}";
}

public static class WhisperModelCatalog
{
    public static readonly IReadOnlyList<WhisperModelInfo> Models =
    [
        new("tiny", "ggml-tiny.bin", 77_691_713, "いちばん小さい。日本語の精度は低い（動作確認向け）"),
        new("base", "ggml-base.bin", 147_951_465, "小さい。日本語の精度は低め"),
        new("small", "ggml-small.bin", 487_601_967, "普段使いの目安。速さと精度のつり合いがよい"),
        new("medium", "ggml-medium.bin", 1_533_763_059, "精度が高い。速い CPU 向け"),
        new("large-v3-turbo-q5_0", "ggml-large-v3-turbo-q5_0.bin", 574_041_195, "高精度・量子化で小さめ。速い CPU 向け"),
        new("large-v3-turbo", "ggml-large-v3-turbo.bin", 1_624_555_275, "高精度。速い CPU 向け"),
    ];

    public static WhisperModelInfo? Find(string? id) =>
        Models.FirstOrDefault(m => string.Equals(m.Id, id, StringComparison.OrdinalIgnoreCase));
}

public enum WhisperModelStatus { NotDownloaded, Downloading, Downloaded, Failed }

public sealed record WhisperModelState(WhisperModelInfo Model, WhisperModelStatus Status, double Progress = 0, string? Error = null);

/// <summary>
/// Whisper のモデルのダウンロード・取り消し・削除。保存先は <c>%LOCALAPPDATA%\Hanasu\Models</c>。
/// ダウンロード中は「.download」の名前で書き、終わってから名前を変える（途中のファイルを使わないため）。
/// 会議の記録でも同じモデルを使う。
/// </summary>
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
        this.http = http ?? new HttpClient { Timeout = System.Threading.Timeout.InfiniteTimeSpan };
    }

    public string PathFor(WhisperModelInfo model) => Path.Combine(Directory, model.FileName);

    public bool IsDownloaded(WhisperModelInfo model) => File.Exists(PathFor(model));

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
        var final = PathFor(model);
        var partial = final + ".download";
        try
        {
            System.IO.Directory.CreateDirectory(Directory);
            using var response = await http.GetAsync(model.DownloadUri, HttpCompletionOption.ResponseHeadersRead, cts.Token).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
            {
                throw new HttpRequestException($"ダウンロードに失敗しました（HTTP {(int)response.StatusCode}）");
            }
            var total = response.Content.Headers.ContentLength ?? model.ApproximateBytes;
            await using (var source = await response.Content.ReadAsStreamAsync(cts.Token).ConfigureAwait(false))
            await using (var target = new FileStream(partial, FileMode.Create, FileAccess.Write, FileShare.None, 1 << 16, useAsync: true))
            {
                var buffer = new byte[1 << 16];
                long received = 0;
                var lastReported = -1.0;
                int read;
                while ((read = await source.ReadAsync(buffer, cts.Token).ConfigureAwait(false)) > 0)
                {
                    await target.WriteAsync(buffer.AsMemory(0, read), cts.Token).ConfigureAwait(false);
                    received += read;
                    var progress = total > 0 ? Math.Min(1.0, (double)received / total) : 0;
                    if (progress - lastReported >= 0.005)
                    {
                        lastReported = progress;
                        lock (gate) downloads[model.Id] = (cts, progress);
                        Raise(model);
                    }
                }
                if (response.Content.Headers.ContentLength is long expected && received != expected)
                {
                    throw new IOException("ダウンロードが途中で切れました");
                }
            }
            File.Move(partial, final, overwrite: true);
        }
        catch (Exception e)
        {
            TryDelete(partial);
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

    private static void TryDelete(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); } catch (IOException) { } catch (UnauthorizedAccessException) { }
    }

    private void Raise(WhisperModelInfo model) => StateChanged?.Invoke(this, StateOf(model));
}
