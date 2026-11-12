using Hanasu.Core.Settings;
using Hanasu.Core.Text;
using Hanasu.Core.Transcription;
using Windows.Globalization;
using Windows.Media.SpeechRecognition;
using Windows.System.UserProfile;

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
    private string finals = "";
    private SpeechRecognizer? recognizer;
    private TaskCompletionSource<SpeechRecognitionResultStatus>? completed;
    private string hypothesis = "";
    /// <summary>認識の区切りをつなぐときの言語（DEC-COM-174。日本語・中国語は空白を入れない）</summary>
    private string spacingLocale = "";
    private bool running;

    public event EventHandler<string>? PartialTextChanged;

    public string? FinishingMessage => null;

    public async Task StartAsync(TranscriptionContext context, CancellationToken cancellationToken = default)
    {
        var requested = new Language(string.IsNullOrEmpty(context.LocaleIdentifier) ? "ja-JP" : context.LocaleIdentifier);
        spacingLocale = requested.LanguageTag;
        // 設計判断: DEC-COM-104
        // 文字起こしの言語がちょうど入っていなければ、表示の言語・入っている言語のうち言語コードが同じもの（地域の違うもの）を使う
        var installed = SpeechRecognizer.SupportedTopicLanguages.Select(l => l.LanguageTag).ToList();
        var preferred = GlobalizationPreferences.Languages.Append(SpeechRecognizer.SystemSpeechLanguage?.LanguageTag ?? "");
        if (TranscriptionLocales.SpeechRecognitionLanguage(requested.LanguageTag, preferred, installed) is not { } tag)
        {
            throw new TranscriptionException(
                string.Format(Strings.Speech_LanguageNotInstalled, requested.DisplayName),
                "ms-settings:regionlanguage");
        }
        var language = new Language(tag);

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
        lock (gate) return finals.Trim();
    }

    private void OnHypothesis(SpeechRecognizer sender, SpeechRecognitionHypothesisGeneratedEventArgs args)
    {
        string text;
        lock (gate)
        {
            hypothesis = args.Hypothesis.Text;
            // 設計判断: DEC-COM-174（確定した区切りと途中経過のあいだも、英語などでは語がくっつかないようにする）
            text = TextSpacing.Join(finals, hypothesis, spacingLocale);
        }
        PartialTextChanged?.Invoke(this, text);
    }

    private void OnResult(SpeechContinuousRecognitionSession sender, SpeechContinuousRecognitionResultGeneratedEventArgs args)
    {
        if (args.Result.Status != SpeechRecognitionResultStatus.Success || args.Result.Confidence == SpeechRecognitionConfidence.Rejected) return;
        string text;
        lock (gate)
        {
            // 設計判断: DEC-COM-174（確定した区切りの先頭に空白がなくても、英語などで語がくっつかないようにする）
            finals = TextSpacing.Join(finals, args.Result.Text, spacingLocale);
            hypothesis = "";
            text = finals;
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
            new TranscriptionException(Strings.Speech_LanguageNotSupported),
        SpeechRecognitionResultStatus.MicrophoneUnavailable =>
            new TranscriptionException(Strings.Speech_MicUnavailable, "ms-settings:sound"),
        SpeechRecognitionResultStatus.NetworkFailure =>
            new TranscriptionException(Strings.Speech_NetworkFailure),
        _ => new TranscriptionException(string.Format(Strings.Speech_StartFailed, status)),
    };

    private static TranscriptionException Translate(Exception e)
    {
        var hr = (uint)e.HResult;
        if (hr == PrivacyPolicyNotAccepted)
        {
            return new TranscriptionException(
                Strings.Speech_OnlineRecognitionOff,
                "ms-settings:privacy-speech", e);
        }
        if (e is UnauthorizedAccessException || hr == 0x80070005)
        {
            return new TranscriptionException(
                Strings.Mic_AccessDenied,
                "ms-settings:privacy-microphone", e);
        }
        return new TranscriptionException(string.Format(Strings.Speech_Error, e.Message), inner: e);
    }
}
