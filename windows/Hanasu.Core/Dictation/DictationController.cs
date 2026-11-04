using Hanasu.Core.Settings;
using Hanasu.Core.Transcription;

namespace Hanasu.Core.Dictation;

public enum DictationState { Idle, Preparing, Recording, Processing }

public enum HotKeyEventKind { Pressed, Released }

/// <summary>入力の結果。貼り付けなかったときは、その理由と、クリップボードに結果の文章が入っているか</summary>
public sealed record InsertOutcome(NotPastedReason? NotPasted = null, bool ClipboardHasText = false)
{
    /// <summary>貼り付けた</summary>
    public static InsertOutcome Pasted { get; } = new();

    /// <summary>貼り付けなかった（入力できる場所がない・権限の高いウインドウ・送れなかった など）</summary>
    public static InsertOutcome NotPastedBecause(NotPastedReason reason, bool clipboardHasText) => new(reason, clipboardHasText);

    public bool WasPasted => NotPasted is null;
}

/// <summary>カーソル位置へテキストを入力する（Windows ではクリップボード + Ctrl+V）。</summary>
public interface ITextInserter
{
    /// <param name="fallback">貼り付けられないと分かったとき、結果をクリップボードに入れたままにするか（REQ-DIC-081）</param>
    Task<InsertOutcome> InsertAsync(string text, PasteFallbackClipboard fallback);
}

public enum SoundCue { Start, Stop, Error }

/// <summary>音声入力の流れが使う、OS 側の部品。</summary>
public sealed class DictationServices
{
    public required Func<AppSettings> Settings { get; init; }
    /// <summary>設定のエンジンに合わせて、1 回分の文字起こしを作る</summary>
    public required Func<AppSettings, IDictationTranscriber> CreateTranscriber { get; init; }
    public required DictationTextProcessor Processor { get; init; }
    public required ITextInserter Inserter { get; init; }
    public required IHud Hud { get; init; }
    /// <summary>音声入力の履歴（貼り付けの前に残す。タスクトレイの「最近の結果」もここから出す）</summary>
    public required DictationHistoryStore History { get; init; }
    /// <summary>今の前面アプリの名前（入力先として AI に伝える）</summary>
    public Func<string?> ForegroundAppName { get; init; } = () => null;
    /// <summary>録音中だけ Esc を取り消しのショートカットとして登録する</summary>
    public Action<bool> SetEscapeHotKeyEnabled { get; init; } = _ => { };
    public Action<SoundCue> PlaySound { get; init; } = _ => { };
    /// <summary>直し方のページ（ms-settings: など）を開く</summary>
    public Action<string> OpenHelp { get; init; } = _ => { };
    public Action<string> Log { get; init; } = _ => { };
}

/// <summary>
/// ホットキー → 録音 → 文字起こし → Gemini 整形（または英訳） → 入力、の流れを管理する。Mac 版の DictationController の移植。
/// UI スレッドから呼ぶ（await の続きも UI スレッドに戻る前提）。OS に依存する部分は DictationServices で受け取る。
/// </summary>
/// <remarks>
/// 状態遷移:
/// idle ──hotkey──▶ preparing ──(マイク開始)──▶ recording
/// recording ──hotkey(トグル) / 解放(押している間)──▶ processing ──(Gemini→入力)──▶ idle
/// recording ──Esc──▶ idle（何もしない）
/// preparing / recording ──エラー──▶ idle（HUD でエラー表示）
/// processing 中の hotkey は無視
/// </remarks>
public sealed class DictationController
{
    private readonly DictationServices services;
    private DictationState state = DictationState.Idle;
    private IDictationTranscriber? transcriber;
    private bool stopRequested;
    private bool cancelRequested;
    private string? targetAppName;

    public DictationController(DictationServices services)
    {
        this.services = services;
        services.Hud.LanguageSelected += (_, translation) => SelectOutputLanguage(translation);
        services.Hud.StopRequested += (_, _) => RequestStop();
        services.Hud.CancelRequested += (_, _) => Cancel();
    }

    public DictationState State
    {
        get => state;
        private set
        {
            if (state == value) return;
            state = value;
            StateChanged?.Invoke(this, value);
        }
    }

    public DictationMode Mode { get; private set; } = DictationMode.Refine;

    public event EventHandler<DictationState>? StateChanged;

    /// <summary>ほかの録音（会議の記録など）が動いている間は false を返す</summary>
    public Func<bool> CanStart { get; set; } = () => true;

    /// <summary>開始はショートカットごとのモードで。録音中はどちらのショートカットでも止まる</summary>
    public void HandleHotKey(HotKeyEventKind kind, DictationMode mode)
    {
        var recordingMode = services.Settings().RecordingMode;
        switch (kind, State)
        {
            case (HotKeyEventKind.Pressed, DictationState.Idle):
                _ = StartAsync(mode);
                break;
            case (HotKeyEventKind.Pressed, DictationState.Recording) when recordingMode == RecordingMode.Toggle:
            case (HotKeyEventKind.Released, DictationState.Recording) when recordingMode == RecordingMode.PushToTalk:
                _ = FinishAsync();
                break;
            case (HotKeyEventKind.Pressed, DictationState.Preparing) when recordingMode == RecordingMode.Toggle:
            case (HotKeyEventKind.Released, DictationState.Preparing) when recordingMode == RecordingMode.PushToTalk:
                stopRequested = true;
                break;
        }
    }

    /// <summary>メニューから。止まっていれば始め、録音中なら止める</summary>
    public void ToggleFromMenu(DictationMode mode = DictationMode.Refine)
    {
        switch (State)
        {
            case DictationState.Idle: _ = StartAsync(mode); break;
            case DictationState.Recording: _ = FinishAsync(); break;
            case DictationState.Preparing: stopRequested = true; break;
        }
    }

    /// <summary>HUD の「■ 停止」。ショートカットをもう一度押したのと同じく、止めて文字起こしし、入力まで進める</summary>
    public void RequestStop()
    {
        switch (State)
        {
            case DictationState.Recording: _ = FinishAsync(); break;
            case DictationState.Preparing: stopRequested = true; break;
        }
    }

    // 要件: REQ-DIC-011, REQ-DIC-013
    /// <summary>録音中に HUD で出力の言語を切り替える。止めた時点の選択で、整形するか、どの言語に翻訳するかが決まる</summary>
    public void SelectOutputLanguage(TranslationLanguage? translation)
    {
        if (State is not (DictationState.Preparing or DictationState.Recording)) return;
        Mode = translation?.ToMode() ?? DictationMode.Refine;
        services.Hud.SetLanguages(translation, languageChoices);
    }

    // 設計判断: DEC-DIC-027
    /// <summary>「翻訳して入力」のショートカット・メニューで始めるモード（設定で選んだ翻訳の言語のうち最初）</summary>
    public DictationMode PrimaryTranslateMode => services.Settings().PrimaryTranslationLanguage.ToMode();

    /// <summary>HUD に並べる翻訳の言語（録音を始めたときの設定）</summary>
    private IReadOnlyList<TranslationLanguage> languageChoices = [TranslationLanguage.English];

    public async Task StartAsync(DictationMode mode = DictationMode.Refine)
    {
        if (State != DictationState.Idle || !CanStart()) return;
        Mode = mode;
        State = DictationState.Preparing;
        stopRequested = false;
        cancelRequested = false;
        targetAppName = services.ForegroundAppName();
        // HUD には「話した言語」と設定で選んだ翻訳の言語を出す（設定にない言語で始めたときは、それも出す）
        languageChoices = TranslationLanguages.Normalize(services.Settings().TranslationLanguages.Concat(mode.Translation() is { } l ? new[] { l } : Array.Empty<TranslationLanguage>()));
        services.Hud.SetLanguages(mode.Translation(), languageChoices);
        services.Hud.UpdateTranscript("");
        services.Hud.Show(HudState.Preparing("準備中…"));
        services.SetEscapeHotKeyEnabled(true);

        var settings = services.Settings();
        try
        {
            transcriber = services.CreateTranscriber(settings);
            transcriber.PartialTextChanged += OnPartialText;
            var context = new TranscriptionContext(settings.LocaleIdentifier, settings.UserDictionary.ContextualStrings, settings.MicrophoneDeviceId);
            await transcriber.StartAsync(context);
        }
        catch (Exception e)
        {
            await DisposeTranscriberAsync();
            Fail(e);
            return;
        }
        if (cancelRequested)
        {
            await CancelTranscriberAsync();
            FinishCancelled();
            return;
        }
        State = DictationState.Recording;
        services.PlaySound(SoundCue.Start);
        services.Hud.Show(HudState.Recording);
        if (stopRequested) await FinishAsync();
    }

    public void Cancel()
    {
        switch (State)
        {
            case DictationState.Preparing:
                cancelRequested = true;
                break;
            case DictationState.Recording:
                _ = CancelRecordingAsync();
                break;
        }
    }

    private async Task CancelRecordingAsync()
    {
        // 取り消しの途中でホットキーが来ても始め直さないよう、先に状態を変える
        State = DictationState.Processing;
        await CancelTranscriberAsync();
        FinishCancelled();
    }

    public async Task FinishAsync()
    {
        if (State != DictationState.Recording || transcriber is null) return;
        State = DictationState.Processing;
        services.SetEscapeHotKeyEnabled(false);
        services.PlaySound(SoundCue.Stop);
        var settings = services.Settings();
        var usesGemini = DictationTextProcessor.UsesGemini(settings, Mode);
        services.Hud.Show(HudState.Processing(transcriber.FinishingMessage
            ?? (usesGemini ? HudText.ProcessingTitle(Mode.Translation(), Ai.TextAiFactory.NameOf(settings.DictationAi)) : "仕上げています…")));

        string raw;
        try
        {
            raw = (await transcriber.StopAsync()).Trim();
        }
        catch (Exception e)
        {
            await DisposeTranscriberAsync();
            Fail(e);
            return;
        }
        await DisposeTranscriberAsync();
        services.Log($"recognized {raw.Length} chars");
        services.Hud.UpdateTranscript(raw);
        if (raw.Length == 0)
        {
            Fail("音声が認識されませんでした");
            return;
        }

        if (usesGemini) services.Hud.Show(HudState.Processing(HudText.ProcessingTitle(Mode.Translation(), Ai.TextAiFactory.NameOf(settings.DictationAi))));
        var outcome = await services.Processor.ProcessAsync(raw, Mode, targetAppName, settings);
        services.Log($"process: {outcome.Status}, {outcome.Output.Length} chars");
        // 入力先がずれても取り戻せるよう、貼り付けの前に残す
        // 要件: REQ-DIC-060
        // 設計判断: DEC-DIC-072
        services.History.Record(raw, outcome.Output, Mode, outcome.Status, targetAppName,
            errorMessage: outcome.Status is ProcessStatus.AiFailed or ProcessStatus.NoCredentials ? outcome.Warning : null,
            model: usesGemini ? Ai.TextAiFactory.ModelFor(settings, Ai.TextAiUse.Dictation) : null);
        InsertOutcome inserted;
        try
        {
            inserted = await services.Inserter.InsertAsync(outcome.Output, settings.PasteFallbackClipboard);
        }
        catch (Exception e)
        {
            // 入力の途中で失敗しても、結果は画面に残す（クリップボードに入っているかは分からないので、入っていないものとして案内する）
            services.Log($"insert failed: {e}");
            inserted = InsertOutcome.NotPastedBecause(NotPastedReason.Failed, clipboardHasText: false);
        }
        State = DictationState.Idle;

        if (inserted.NotPasted is { } reason)
        {
            ShowUnpasted(outcome, reason, inserted.ClipboardHasText);
        }
        else if (outcome.Warning is not null)
        {
            services.PlaySound(SoundCue.Error);
            services.Hud.Show(HudState.Error(outcome.Warning));
        }
        else
        {
            services.Hud.Show(HudState.Done(Mode.Translation() is { } translation ? $"{translation.Verb()}して入力しました" : "入力しました"));
        }
    }

    /// <summary>
    /// 貼り付けなかったときは、結果の全文を HUD に残す（自動では閉じない。次に音声入力を始めると閉じる）。
    /// 権限の高いウインドウ・送れなかったときも、入力できる場所がないときと同じ表示にそろえる（DEC-DIC-123）
    /// </summary>
    // 要件: REQ-DIC-080
    // 設計判断: DEC-DIC-121, DEC-DIC-123
    private void ShowUnpasted(ProcessOutcome outcome, NotPastedReason reason, bool clipboardHasText)
    {
        services.Log($"not pasted: {reason}, clipboard has text: {clipboardHasText}");
        if (outcome.Warning is not null) services.PlaySound(SoundCue.Error);
        services.Hud.Show(HudState.Unpasted(outcome.Output, reason, clipboardHasText, outcome.Warning));
    }

    private void OnPartialText(object? sender, string text) => services.Hud.UpdateTranscript(text);

    private void FinishCancelled()
    {
        State = DictationState.Idle;
        services.SetEscapeHotKeyEnabled(false);
        services.Hud.Show(HudState.Done("取り消しました"));
    }

    private void Fail(Exception e)
    {
        services.Log($"failed: {e}");
        if (e is TranscriptionException { HelpUri: { } uri }) services.OpenHelp(uri);
        Fail(e.Message);
    }

    private void Fail(string message)
    {
        State = DictationState.Idle;
        services.SetEscapeHotKeyEnabled(false);
        services.PlaySound(SoundCue.Error);
        services.Hud.Show(HudState.Error(message));
    }

    private async Task CancelTranscriberAsync()
    {
        if (transcriber is null) return;
        try { await transcriber.CancelAsync(); }
        catch (Exception e) { services.Log($"cancel failed: {e.Message}"); }
        await DisposeTranscriberAsync();
    }

    private async Task DisposeTranscriberAsync()
    {
        var t = transcriber;
        transcriber = null;
        if (t is null) return;
        t.PartialTextChanged -= OnPartialText;
        try { await t.DisposeAsync(); }
        catch (Exception e) { services.Log($"dispose failed: {e.Message}"); }
    }
}
