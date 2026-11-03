using System.Text;
using Hanasu.Core.Transcription;
using Windows.Globalization;
using Windows.Media.SpeechRecognition;

namespace Hanasu.Windows.Services;

/// <summary>
/// Windows 標準の音声認識（Windows.Media.SpeechRecognition の連続認識・ディクテーション）。
/// 話している間に途中経過（HypothesisGenerated）を出し、区切りごとに確定（ResultGenerated）する。
/// </summary>
/// <remarks>
/// - マイクは Windows の既定のマイクを使う（この API には録音デバイスを渡せない）。
/// - ディクテーションは Microsoft のオンライン音声認識を使うので、Windows の設定で「オンライン音声認識」をオンにする必要がある。
/// - 日本語の音声認識（言語パックの音声機能）が入っていないと使えない。
/// </remarks>
internal sealed class WindowsSpeechTranscriber : IDictationTranscriber
{
    /// <summary>SPERR_SPEECH_PRIVACY_POLICY_NOT_ACCEPTED（オンライン音声認識がオフ）</summary>
    private const uint PrivacyPolicyNotAccepted = 0x80045509;

    private readonly object gate = new();
    private readonly StringBuilder finals = new();
    private SpeechRecognizer? recognizer;
    private TaskCompletionSource<SpeechRecognitionResultStatus>? completed;
    private string hypothesis = "";
    private bool running;

    public event EventHandler<string>? PartialTextChanged;

    public string? FinishingMessage => null;

    public async Task StartAsync(TranscriptionContext context, CancellationToken cancellationToken = default)
    {
        var language = new Language(string.IsNullOrEmpty(context.LocaleIdentifier) ? "ja-JP" : context.LocaleIdentifier);
        if (!SpeechRecognizer.SupportedTopicLanguages.Any(l => string.Equals(l.LanguageTag, language.LanguageTag, StringComparison.OrdinalIgnoreCase)))
        {
            throw new TranscriptionException(
                $"Windows に {language.DisplayName} の音声認識が入っていません。Windows の設定 → 時刻と言語 → 言語と地域 で {language.DisplayName} の「…」→「言語のオプション」から音声認識を追加してください。" +
                "または、設定で文字起こしのエンジンを Whisper か Gemini にしてください。",
                "ms-settings:regionlanguage");
        }

        try
        {
            recognizer = new SpeechRecognizer(language);
            recognizer.Constraints.Add(new SpeechRecognitionTopicConstraint(SpeechRecognitionScenario.Dictation, "dictation"));
            var compilation = await recognizer.CompileConstraintsAsync().AsTask(cancellationToken).ConfigureAwait(false);
            if (compilation.Status != SpeechRecognitionResultStatus.Success)
            {
                throw StatusError(compilation.Status);
            }
            // 既定では数秒の無音で止まってしまうので、長めにする（止めるのはショートカット）
            recognizer.Timeouts.InitialSilenceTimeout = TimeSpan.FromSeconds(60);
            recognizer.Timeouts.EndSilenceTimeout = TimeSpan.FromSeconds(1.2);
            recognizer.ContinuousRecognitionSession.AutoStopSilenceTimeout = TimeSpan.FromMinutes(10);
            recognizer.HypothesisGenerated += OnHypothesis;
            recognizer.ContinuousRecognitionSession.ResultGenerated += OnResult;
            recognizer.ContinuousRecognitionSession.Completed += OnCompleted;
            completed = new TaskCompletionSource<SpeechRecognitionResultStatus>(TaskCreationOptions.RunContinuationsAsynchronously);
            await recognizer.ContinuousRecognitionSession.StartAsync().AsTask(cancellationToken).ConfigureAwait(false);
            running = true;
        }
        catch (Exception e) when (e is not TranscriptionException and not OperationCanceledException)
        {
            throw Translate(e);
        }
    }

    public async Task<string> StopAsync(CancellationToken cancellationToken = default)
    {
        if (recognizer is null || !running) return Text();
        running = false;
        try
        {
            // StopAsync は話し途中の分を確定させてから終わる
            await recognizer.ContinuousRecognitionSession.StopAsync().AsTask(cancellationToken).ConfigureAwait(false);
            if (completed is not null) await Task.WhenAny(completed.Task, Task.Delay(3000, cancellationToken)).ConfigureAwait(false);
        }
        catch (Exception e) when (e is not OperationCanceledException)
        {
            // 止めるときの失敗は、確定した分があればそれを使う
            if (Text().Length == 0) throw Translate(e);
        }
        lock (gate)
        {
            // 確定しなかった最後の途中経過も捨てない
            if (finals.Length == 0 && hypothesis.Length > 0) return hypothesis;
        }
        return Text();
    }

    public async Task CancelAsync()
    {
        if (recognizer is null || !running) return;
        running = false;
        try { await recognizer.ContinuousRecognitionSession.CancelAsync(); }
        catch (Exception) { /* 取り消しの失敗は無視する */ }
    }

    public async ValueTask DisposeAsync()
    {
        if (running) await CancelAsync().ConfigureAwait(false);
        if (recognizer is not null)
        {
            recognizer.HypothesisGenerated -= OnHypothesis;
            recognizer.ContinuousRecognitionSession.ResultGenerated -= OnResult;
            recognizer.ContinuousRecognitionSession.Completed -= OnCompleted;
            recognizer.Dispose();
            recognizer = null;
        }
    }

    private string Text()
    {
        lock (gate) return finals.ToString().Trim();
    }

    private void OnHypothesis(SpeechRecognizer sender, SpeechRecognitionHypothesisGeneratedEventArgs args)
    {
        string text;
        lock (gate)
        {
            hypothesis = args.Hypothesis.Text;
            text = finals + hypothesis;
        }
        PartialTextChanged?.Invoke(this, text);
    }

    private void OnResult(SpeechContinuousRecognitionSession sender, SpeechContinuousRecognitionResultGeneratedEventArgs args)
    {
        if (args.Result.Status != SpeechRecognitionResultStatus.Success || args.Result.Confidence == SpeechRecognitionConfidence.Rejected) return;
        string text;
        lock (gate)
        {
            finals.Append(args.Result.Text);
            hypothesis = "";
            text = finals.ToString();
        }
        PartialTextChanged?.Invoke(this, text);
    }

    private void OnCompleted(SpeechContinuousRecognitionSession sender, SpeechContinuousRecognitionCompletedEventArgs args)
    {
        completed?.TrySetResult(args.Status);
    }

    private static TranscriptionException StatusError(SpeechRecognitionResultStatus status) => status switch
    {
        SpeechRecognitionResultStatus.TopicLanguageNotSupported or SpeechRecognitionResultStatus.GrammarLanguageMismatch =>
            new TranscriptionException("Windows のディクテーションが日本語に対応していません。設定で文字起こしのエンジンを Whisper か Gemini にしてください。"),
        SpeechRecognitionResultStatus.MicrophoneUnavailable =>
            new TranscriptionException("マイクを使えません。Windows の既定のマイクを確かめてください。", "ms-settings:sound"),
        SpeechRecognitionResultStatus.NetworkFailure =>
            new TranscriptionException("Windows の音声認識がネットワークにつながりませんでした。インターネット接続を確かめてください。"),
        _ => new TranscriptionException($"Windows の音声認識を始められませんでした（{status}）。"),
    };

    private static TranscriptionException Translate(Exception e)
    {
        var hr = (uint)e.HResult;
        if (hr == PrivacyPolicyNotAccepted)
        {
            return new TranscriptionException(
                "Windows の音声認識を使うには、Windows の設定 → プライバシーとセキュリティ → 音声認識 で「オンライン音声認識」をオンにしてください。" +
                "オンにしたくない場合は、設定で文字起こしのエンジンを Whisper にしてください。",
                "ms-settings:privacy-speech", e);
        }
        if (e is UnauthorizedAccessException || hr == 0x80070005)
        {
            return new TranscriptionException(
                "マイクの使用が許可されていません。Windows の設定 → プライバシーとセキュリティ → マイク で「デスクトップ アプリがマイクにアクセスできるようにする」をオンにしてください。",
                "ms-settings:privacy-microphone", e);
        }
        return new TranscriptionException($"Windows の音声認識でエラーが起きました: {e.Message}", inner: e);
    }
}
