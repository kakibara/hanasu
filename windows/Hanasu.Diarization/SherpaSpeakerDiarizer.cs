using Hanasu.Core.Meetings;
using Hanasu.Core.Properties;
using SherpaOnnx;

namespace Hanasu.Diarization;

/// <summary>話者分離に使うモデル 1 つ。Bytes と Sha256 は Hugging Face の LFS の値（ダウンロードしたものと比べる）</summary>
public sealed record DiarizationModelFile(string FileName, Uri DownloadUri, long Bytes, string Sha256, string Description);

/// <summary>
/// 話者分離のモデル（初めて使うときにダウンロードする）。置き場所は Whisper と同じ %LOCALAPPDATA%\Hanasu\Models の下の diarization。
/// - 区間の検出: pyannote segmentation-3.0 の ONNX 版（sherpa-onnx の作者が変換したもの。MIT）
/// - 話者の埋め込み: 3D-Speaker の CAM++（中国語・英語の大量の話者で学習。Apache-2.0）。
///   sherpa-onnx の GitHub のリリースと同じファイル（同じ名前・同じ大きさ）を、ハッシュが公開されている Hugging Face から取る
/// </summary>
// 設計判断: DEC-COM-146
public sealed class DiarizationModels
{
    public static readonly DiarizationModelFile Segmentation = new(
        "pyannote-segmentation-3.0.onnx",
        new Uri("https://huggingface.co/csukuangfj/sherpa-onnx-pyannote-segmentation-3-0/resolve/main/model.onnx"),
        5_992_913, "220ad67ca923bef2fa91f2390c786097bf305bceb5e261d4af67b38e938e1079", "話している区間の検出（pyannote segmentation-3.0）");  // skip-tr（画面に出さないモデルの説明）

    public static readonly DiarizationModelFile Embedding = new(
        "3dspeaker_speech_campplus_sv_zh_en_16k-common_advanced.onnx",
        new Uri("https://huggingface.co/csukuangfj/speaker-embedding-models/resolve/main/3dspeaker_speech_campplus_sv_zh_en_16k-common_advanced.onnx"),
        28_281_164, "aa3cfc16963a10586a9393f5035d6d6b57e98d358b347f80c2a30bf4f00ceba2", "話者の声の特徴（3D-Speaker CAM++）");  // skip-tr（画面に出さないモデルの説明）

    public static IReadOnlyList<DiarizationModelFile> All { get; } = [Segmentation, Embedding];

    private static readonly SemaphoreSlim DownloadLock = new(1, 1);
    private readonly HttpClient http;

    public string Directory { get; }

    public DiarizationModels(string directory, HttpClient? http = null)
    {
        Directory = directory;
        this.http = http ?? Hanasu.Core.SafeHttp.CreateForDownloads(TimeSpan.FromMinutes(10));
    }

    public string PathFor(DiarizationModelFile model) => Path.Combine(Directory, model.FileName);

    /// <summary>すべて置いてあり、大きさが合っているか（ハッシュはダウンロードのときに確かめている）</summary>
    public bool IsReady => All.All(m => new FileInfo(PathFor(m)) is { Exists: true } f && f.Length == m.Bytes);

    /// <summary>なければダウンロードする（「.download」に書いてから名前を変える）。progress には「12/34 MB」のような文言を渡す</summary>
    public async Task EnsureDownloadedAsync(IProgress<string>? progress = null, CancellationToken cancellationToken = default)
    {
        await DownloadLock.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            System.IO.Directory.CreateDirectory(Directory);
            var missing = All.Where(m => !(new FileInfo(PathFor(m)) is { Exists: true } f && f.Length == m.Bytes)).ToList();
            var total = missing.Sum(m => m.Bytes);
            long done = 0;
            foreach (var model in missing)
            {
                long lastReport = 0;
                await Hanasu.Core.ModelDownload.DownloadVerifiedAsync(http, model.DownloadUri, PathFor(model), model.Sha256, model.Bytes, (received, _) =>
                {
                    var sum = done + received;
                    if (sum - lastReport <= 2_000_000) return;
                    lastReport = sum;
                    progress?.Report(string.Format(Strings.Diarization_Downloading, sum / 1_000_000, total / 1_000_000));
                }, cancellationToken).ConfigureAwait(false);
                done += model.Bytes;
            }
        }
        finally
        {
            DownloadLock.Release();
        }
    }
}

/// <summary>
/// sherpa-onnx（ONNX Runtime）で相手側の音声の話者を分ける。会議全体を 1 回で処理するので、話者番号が最後まで一貫する。
/// 話者の数は決めず、声の特徴の近さ（Threshold）でまとめる。
/// </summary>
public sealed class SherpaSpeakerDiarizer : ISpeakerDiarizer
{
    /// <summary>
    /// クラスタリングのしきい値（コサイン距離）。小さいほど話者を細かく分ける。sherpa-onnx の既定は 0.5。
    /// 合成音声の会話（README の確認）で、別の声が 1 人にまとまらず、同じ声が 2 人に割れない値を選んだ。環境変数 HANASU_DIARIZATION_THRESHOLD で変えられる
    /// </summary>
    public static float Threshold =>
        float.TryParse(Environment.GetEnvironmentVariable("HANASU_DIARIZATION_THRESHOLD"), System.Globalization.NumberStyles.Float,
            System.Globalization.CultureInfo.InvariantCulture, out var t) && t > 0 ? t : 0.5f;

    private readonly DiarizationModels models;

    public SherpaSpeakerDiarizer(DiarizationModels models)
    {
        this.models = models;
    }

    public async Task<IReadOnlyList<SpeakerTurn>> DiarizeAsync(float[] samples, IProgress<string>? progress = null,
        CancellationToken cancellationToken = default)
    {
        if (!models.IsReady) await models.EnsureDownloadedAsync(progress, cancellationToken).ConfigureAwait(false);
        progress?.Report(Strings.Meeting_Diarizing);
        return await Task.Run(() => Diarize(samples, cancellationToken), cancellationToken).ConfigureAwait(false);
    }

    private IReadOnlyList<SpeakerTurn> Diarize(float[] samples, CancellationToken cancellationToken)
    {
        var config = new OfflineSpeakerDiarizationConfig();
        config.Segmentation.Pyannote.Model = models.PathFor(DiarizationModels.Segmentation);
        config.Segmentation.NumThreads = Math.Clamp(Environment.ProcessorCount / 2, 1, 4);
        config.Embedding.Model = models.PathFor(DiarizationModels.Embedding);
        config.Embedding.NumThreads = Math.Clamp(Environment.ProcessorCount / 2, 1, 4);
        config.Clustering.NumClusters = -1;
        config.Clustering.Threshold = Threshold;
        config.MinDurationOn = 0.3f;
        config.MinDurationOff = 0.5f;
        using var diarizer = new OfflineSpeakerDiarization(config);
        if (diarizer.SampleRate != Core.Audio.AudioFormat.SampleRate)
        {
            throw new InvalidOperationException(string.Format(Strings.Diarization_SampleRateMismatch, diarizer.SampleRate));
        }
        cancellationToken.ThrowIfCancellationRequested();
        var segments = diarizer.Process(samples);
        return segments
            .Select(s => new SpeakerTurn(s.Speaker.ToString(System.Globalization.CultureInfo.InvariantCulture), s.Start, s.End))
            .OrderBy(t => t.Start)
            .ToList();
    }
}
