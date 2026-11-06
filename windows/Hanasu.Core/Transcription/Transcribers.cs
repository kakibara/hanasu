using Hanasu.Core.Audio;

namespace Hanasu.Core.Transcription;

/// <summary>文字起こしを始めるときに渡すもの。</summary>
public sealed record TranscriptionContext(
    string LocaleIdentifier,
    /// <summary>認識のヒントにする語（ユーザー辞書の表記と読み）</summary>
    IReadOnlyList<string> ContextualStrings,
    /// <summary>マイクの ID。空なら既定のマイク（Windows 標準のエンジンは常に既定のマイク）</summary>
    string MicrophoneDeviceId);

/// <summary>
/// 文字起こしが始められない・失敗したとき。Message は HUD にそのまま出す。
/// HelpUri があれば、直し方のページ（ms-settings: など）を開く。
/// </summary>
public sealed class TranscriptionException(string message, string? helpUri = null, Exception? inner = null) : Exception(message, inner)
{
    public string? HelpUri { get; } = helpUri;
}

/// <summary>
/// 音声入力の 1 回分の文字起こし。録音から確定まで。
/// Windows 標準のエンジンは話している間に結果を出す（PartialTextChanged）。Whisper と Gemini は録り終えてからまとめて出す。
/// </summary>
public interface IDictationTranscriber : IAsyncDisposable
{
    /// <summary>途中経過（確定した分＋認識中の分）。どのスレッドから来るかは決めない</summary>
    event EventHandler<string>? PartialTextChanged;

    /// <summary>録音を止めてから結果が出るまでに HUD に出す文言（例:「Whisper で文字起こししています…」）。null なら出さない</summary>
    string? FinishingMessage { get; }

    // 設計判断: DEC-DIC-144
    /// <summary>録音が上限（AudioFormat.MaxDictationRecording）に達したとき。受け取った側は録音を止めて、ここまでの音声を処理する。どのスレッドから来るかは決めない</summary>
    event EventHandler? RecordingLimitReached { add { } remove { } }

    Task StartAsync(TranscriptionContext context, CancellationToken cancellationToken = default);

    /// <summary>録音を止め、確定した文字起こしを返す</summary>
    Task<string> StopAsync(CancellationToken cancellationToken = default);

    /// <summary>録音を止め、結果を捨てる</summary>
    Task CancelAsync();
}

/// <summary>
/// マイクから 16 kHz・モノラルの音声を録る。音声入力（Whisper / Gemini）と会議の記録で共通に使う。
/// </summary>
public interface IAudioRecorder : IAsyncDisposable
{
    /// <summary>16 kHz・モノラルに変換した音声が届くたびに呼ぶ（会議の記録で、録りながら処理するため）</summary>
    event EventHandler<float[]>? SamplesAvailable;

    /// <summary>録音が思わぬ理由で止まったとき（マイクが抜かれたなど）</summary>
    event EventHandler<Exception>? Faulted;

    // 設計判断: DEC-DIC-144
    /// <summary>メモリに溜める録音が上限（AudioFormat.MaxDictationRecording）に達したとき（それ以降の音声は溜めない）</summary>
    event EventHandler? LimitReached { add { } remove { } }

    Task StartAsync(string deviceId, CancellationToken cancellationToken = default);

    /// <summary>録音を止め、始めてからの音声をすべて返す</summary>
    Task<float[]> StopAsync();
}

/// <summary>録り終えた音声（16 kHz・モノラル）をまとめて文字起こしする。Whisper と Gemini。</summary>
public interface IBatchTranscriber
{
    /// <summary>HUD に出す名前（「Whisper」「Gemini」）</summary>
    string DisplayName { get; }

    /// <summary>録音を始める前に、使えるかを確かめる（モデルがない・認証がないなら TranscriptionException）。モデルの読み込みもここで始めてよい</summary>
    Task PrepareAsync(TranscriptionContext context, CancellationToken cancellationToken = default);

    Task<string> TranscribeAsync(float[] samples, TranscriptionContext context, CancellationToken cancellationToken = default);
}

/// <summary>録音してから、止めた後にまとめて文字起こしする（Whisper / Gemini 用）。</summary>
public sealed class RecordThenTranscribe : IDictationTranscriber
{
    private readonly IAudioRecorder recorder;
    private readonly IBatchTranscriber transcriber;
    private TranscriptionContext? context;
    private Task? prepareTask;
    private bool recording;

    public RecordThenTranscribe(IAudioRecorder recorder, IBatchTranscriber transcriber)
    {
        this.recorder = recorder;
        this.transcriber = transcriber;
    }

    // 録り終えてからまとめて出すので、途中経過はない
    public event EventHandler<string>? PartialTextChanged { add { } remove { } }

    public string? FinishingMessage => string.Format(Strings.Transcribing_With, transcriber.DisplayName);

    public event EventHandler? RecordingLimitReached;

    public async Task StartAsync(TranscriptionContext context, CancellationToken cancellationToken = default)
    {
        this.context = context;
        // 使えるかどうかは録音を始める前に確かめる（話し終えてからモデルがないとわかると、話した内容が無駄になる）
        prepareTask = transcriber.PrepareAsync(context, cancellationToken);
        if (prepareTask.IsCompleted) await prepareTask.ConfigureAwait(false);
        recorder.LimitReached += OnLimitReached;
        try
        {
            await recorder.StartAsync(context.MicrophoneDeviceId, cancellationToken).ConfigureAwait(false);
        }
        catch
        {
            recorder.LimitReached -= OnLimitReached;
            throw;
        }
        recording = true;
    }

    private void OnLimitReached(object? sender, EventArgs e) => RecordingLimitReached?.Invoke(this, EventArgs.Empty);

    public async Task<string> StopAsync(CancellationToken cancellationToken = default)
    {
        if (!recording || context is null) return "";
        recording = false;
        recorder.LimitReached -= OnLimitReached;
        var samples = await recorder.StopAsync().ConfigureAwait(false);
        if (prepareTask is not null) await prepareTask.ConfigureAwait(false);
        if (AudioAnalysis.IsSilent(samples)) return "";
        return (await transcriber.TranscribeAsync(samples, context, cancellationToken).ConfigureAwait(false)).Trim();
    }

    public async Task CancelAsync()
    {
        if (!recording) return;
        recording = false;
        recorder.LimitReached -= OnLimitReached;
        await recorder.StopAsync().ConfigureAwait(false);
    }

    public async ValueTask DisposeAsync()
    {
        if (recording) await CancelAsync().ConfigureAwait(false);
        await recorder.DisposeAsync().ConfigureAwait(false);
    }
}

/// <summary>録った音声を Gemini に inline data で送って文字起こしする。</summary>
public sealed class GeminiBatchTranscriber : IBatchTranscriber
{
    // 設計判断: DEC-DIC-145
    /// <summary>inline data は 1 回 20 MB まで。Base64 で 4/3 倍になるので、16 kHz・16 bit の WAV は約 7 分が限界。余裕を見て 5 分ごとに分けて送る</summary>
    public static readonly TimeSpan ChunkDuration = TimeSpan.FromMinutes(5);

    private readonly Func<Gemini.GeminiClient?> clientFactory;
    private readonly Func<string> model;
    private readonly Func<IReadOnlyList<string>> dictionary;
    private Gemini.GeminiClient? client;

    /// <param name="clientFactory">認証情報がなければ null を返す</param>
    public GeminiBatchTranscriber(Func<Gemini.GeminiClient?> clientFactory, Func<string> model, Func<IReadOnlyList<string>> dictionary)
    {
        this.clientFactory = clientFactory;
        this.model = model;
        this.dictionary = dictionary;
    }

    public string DisplayName => "Gemini";

    public Task PrepareAsync(TranscriptionContext context, CancellationToken cancellationToken = default)
    {
        try
        {
            client = clientFactory();
        }
        catch (Exception e) when (e is Gemini.ServiceAccountException)
        {
            throw new TranscriptionException(e.Message, inner: e);
        }
        if (client is null)
        {
            throw new TranscriptionException(Strings.Transcription_GeminiNotConfigured);
        }
        return Task.CompletedTask;
    }

    public async Task<string> TranscribeAsync(float[] samples, TranscriptionContext context, CancellationToken cancellationToken = default)
    {
        if (client is null) await PrepareAsync(context, cancellationToken).ConfigureAwait(false);
        // 長い録音は、いちばん静かなところで 5 分ごとに分けて順に送り、つなげる（20 MB の上限を超えないため）
        var starts = Meetings.MeetingAudio.ChunkStarts(samples, ChunkDuration.TotalSeconds);
        var parts = new List<string>();
        try
        {
            for (var i = 0; i < starts.Count; i++)
            {
                var end = i + 1 < starts.Count ? starts[i + 1] : samples.Length;
                var wav = WavFile.Encode(samples.AsSpan(starts[i], end - starts[i]));
                var text = await client!.TranscribeAudioAsync(wav, "audio/wav", model(), dictionary(), cancellationToken).ConfigureAwait(false);
                if (!string.IsNullOrWhiteSpace(text)) parts.Add(text.Trim());
            }
        }
        catch (Ai.TextAiException e)
        {
            throw new TranscriptionException(string.Format(Strings.Transcription_GeminiFailed, e.Message), inner: e);
        }
        return string.Join("\n", parts);
    }
}
