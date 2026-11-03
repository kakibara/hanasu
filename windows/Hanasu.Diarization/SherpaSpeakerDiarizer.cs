using Hanasu.Core.Meetings;
using SherpaOnnx;

namespace Hanasu.Diarization;

/// <summary>話者分離に使うモデル 1 つ。</summary>
public sealed record DiarizationModelFile(string FileName, Uri DownloadUri, long ApproximateBytes, string Description);

/// <summary>
/// 話者分離のモデル（初めて使うときにダウンロードする）。置き場所は Whisper と同じ %LOCALAPPDATA%\Hanasu\Models の下の diarization。
/// - 区間の検出: pyannote segmentation-3.0 の ONNX 版（sherpa-onnx の作者が変換したもの。MIT）
/// - 話者の埋め込み: 3D-Speaker の CAM++（中国語・英語の大量の話者で学習。Apache-2.0）
/// </summary>
public sealed class DiarizationModels
{
    public static readonly DiarizationModelFile Segmentation = new(
        "pyannote-segmentation-3.0.onnx",
        new Uri("https://huggingface.co/csukuangfj/sherpa-onnx-pyannote-segmentation-3-0/resolve/main/model.onnx"),
        5_990_000, "話している区間の検出（pyannote segmentation-3.0）");

    public static readonly DiarizationModelFile Embedding = new(
        "3dspeaker_speech_campplus_sv_zh_en_16k-common_advanced.onnx",
        new Uri("https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/3dspeaker_speech_campplus_sv_zh_en_16k-common_advanced.onnx"),
        28_281_164, "話者の声の特徴（3D-Speaker CAM++）");

    public static IReadOnlyList<DiarizationModelFile> All { get; } = [Segmentation, Embedding];

    private static readonly SemaphoreSlim DownloadLock = new(1, 1);
    private readonly HttpClient http;

    public string Directory { get; }

    public DiarizationModels(string directory, HttpClient? http = null)
    {
        Directory = directory;
        this.http = http ?? new HttpClient { Timeout = TimeSpan.FromMinutes(10) };
    }

    public string PathFor(DiarizationModelFile model) => Path.Combine(Directory, model.FileName);

    public bool IsReady => All.All(m => File.Exists(PathFor(m)));

    /// <summary>なければダウンロードする（「.download」に書いてから名前を変える）。progress には「12/34 MB」のような文言を渡す</summary>
    public async Task EnsureDownloadedAsync(IProgress<string>? progress = null, CancellationToken cancellationToken = default)
    {
        await DownloadLock.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            System.IO.Directory.CreateDirectory(Directory);
            var missing = All.Where(m => !File.Exists(PathFor(m))).ToList();
            var total = missing.Sum(m => m.ApproximateBytes);
            long done = 0;
            foreach (var model in missing)
            {
                var path = PathFor(model);
                var temp = path + ".download";
                using (var response = await http.GetAsync(model.DownloadUri, HttpCompletionOption.ResponseHeadersRead, cancellationToken).ConfigureAwait(false))
                {
                    response.EnsureSuccessStatusCode();
                    await using var source = await response.Content.ReadAsStreamAsync(cancellationToken).ConfigureAwait(false);
                    await using var file = File.Create(temp);
                    var buffer = new byte[81920];
                    long lastReport = 0;
                    int read;
                    while ((read = await source.ReadAsync(buffer, cancellationToken).ConfigureAwait(false)) > 0)
                    {
                        await file.WriteAsync(buffer.AsMemory(0, read), cancellationToken).ConfigureAwait(false);
                        done += read;
                        if (done - lastReport > 2_000_000)
                        {
                            lastReport = done;
                            progress?.Report($"話者分離のモデルをダウンロードしています…（{done / 1_000_000} / {total / 1_000_000} MB）");
                        }
                    }
                }
                File.Move(temp, path, overwrite: true);
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
        progress?.Report("相手側の話者を分けています…");
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
            throw new InvalidOperationException($"話者分離のモデルの周波数が想定と違います（{diarizer.SampleRate} Hz）");
        }
        cancellationToken.ThrowIfCancellationRequested();
        var segments = diarizer.Process(samples);
        return segments
            .Select(s => new SpeakerTurn(s.Speaker.ToString(System.Globalization.CultureInfo.InvariantCulture), s.Start, s.End))
            .OrderBy(t => t.Start)
            .ToList();
    }
}
