using System.IO;
using System.Windows;
using Hanasu.Core.Ai;
using Hanasu.Core.Claude;
using Hanasu.Core.Dictation;
using Hanasu.Core.Gemini;
using Hanasu.Core.LocalLlm;
using Hanasu.Core.Meetings;
using Hanasu.Core.Settings;
using Hanasu.Core.Transcription;
using Hanasu.Diarization;
using Hanasu.Whisper;
using Hanasu.Windows.Services;
using Hanasu.Windows.Views;

namespace Hanasu.Windows;

/// <summary>
/// 部品を組み立てて、ホットキー・タスクトレイ・設定画面をつなぐ。
/// 会議の記録（MeetingController）もここで作り、同じ SettingsService・WhisperModelManager・Gemini の認証を使う。
/// 音声入力と会議の記録は同時に動かさない（CanStart で互いに止める）。
/// </summary>
internal sealed class AppHost : IDisposable
{
    private readonly Application app;
    private readonly bool firstRun;
    private readonly HotKeyService hotKeys = new();
    private readonly ForegroundWindowTracker foreground = new();
    private readonly SoundService sounds = new();
    private readonly ClipboardTextInserter inserter = new();
    private readonly HudWindow hud = new();
    private TrayIcon? tray;
    private SettingsWindow? settingsWindow;
    private MeetingWindow? meetingWindow;
    private HistoryWindow? historyWindow;
    private int? meetingHotKeyId;
    private int? highlightHotKeyId;
    private int? dictationHotKeyId;
    private int? translateHotKeyId;
    private int? escapeHotKeyId;
    private bool hotKeysSuspended;

    public SettingsService Settings { get; }
    public SecretStore Secrets { get; }
    public WhisperModelManager WhisperModels { get; } = new(HanasuPaths.ModelsDirectory);
    /// <summary>音声入力の履歴（%LOCALAPPDATA%\Hanasu\History\history.json。REQ-DIC-060）</summary>
    public DictationHistoryStore History { get; } = new(DictationHistoryStore.DefaultDirectory);
    // 要件: REQ-COM-030
    /// <summary>ローカルの LLM のモデル（ダウンロード・削除）。サーバーは LocalLlmServer.Shared を使う</summary>
    public LocalLlmModelManager LocalLlmModels { get; } = new(LocalLlmServer.Shared);
    public DictationController Dictation { get; }
    public MeetingController Meetings { get; }

    public AppHost(Application app)
    {
        this.app = app;
        var store = new SettingsStore();
        firstRun = !File.Exists(store.Path);
        // API キーは settings.json ではなく %LOCALAPPDATA%\Hanasu\secrets.json に、DPAPI か Windows Hello で暗号化して置く（DEC-COM-144）
        Secrets = new SecretStore(SecretStore.DefaultPath, new DpapiDataProtector(), new WindowsHelloKey());
        Settings = new SettingsService(store, Secrets);
        History.ApplyPolicy(Settings.Current.HistoryPolicy);
        History.Load();
        if (History.LastError is { } historyError) AppLog.Write($"history: {historyError}");
        Dictation = new DictationController(new DictationServices
        {
            Settings = () => Settings.Current,
            CreateTranscriber = CreateTranscriber,
            Processor = new DictationTextProcessor(s => CreateTextAi(s, TextAiUse.Dictation)),
            Inserter = inserter,
            Hud = hud,
            History = History,
            ForegroundAppName = foreground.ForegroundAppName,
            SetEscapeHotKeyEnabled = SetEscapeHotKey,
            PlaySound = cue =>
            {
                if (Settings.Current.PlaySounds) sounds.Play(cue);
            },
            OpenHelp = Shell.Open,
            Log = AppLog.Write,
        });
        Meetings = new MeetingController(new MeetingServices
        {
            Settings = () => Settings.Current,
            CreateMicRecorder = s => new MeetingChannelRecorder(MeetingChannel.Me, s.MeetingMicrophoneDeviceId),
            CreateLoopbackRecorder = s => new MeetingChannelRecorder(MeetingChannel.Others, s.MeetingOutputDeviceId),
            CreateTranscriber = CreateMeetingTranscriber,
            CreateDiarizer = s => s.DiarizeOthers ? new SherpaSpeakerDiarizer(new DiarizationModels(Path.Combine(HanasuPaths.ModelsDirectory, "diarization"))) : null,
            // 議事録は長い（1 時間の会議で数万文字）ので、待ち時間を長めにする（Claude は出力の上限も大きいので 5 分）
            CreateMinutesClient = s => CreateTextAi(s, TextAiUse.Meeting),
            Log = AppLog.Write,
        });
        // 貼り付けなかった結果の表示を、文章を選ぶために前面に出したあとは、入力先だったウインドウにフォーカスを返す
        hud.RestoreFocus = foreground.RestoreLastExternalWindow;
        Dictation.CanStart = () => Meetings.State == MeetingState.Idle;
        Meetings.CanStart = () => Dictation.State == Core.Dictation.DictationState.Idle;
    }

    /// <summary>会議の文字起こしのエンジン（記録のあとにチャンネルごとにまとめて文字起こしする）</summary>
    private ISegmentTranscriber CreateMeetingTranscriber(AppSettings settings)
    {
        if (settings.MeetingEngine == TranscriptionEngine.Gemini)
        {
            // 5 分の区切りを送るので、待ち時間は長めにする（Mac 版と同じ 300 秒）
            return new GeminiSegmentTranscriber(() => CreateGeminiClient(settings, TimeSpan.FromSeconds(300)), () => settings.Model);
        }
        var model = WhisperModelCatalog.Find(settings.WhisperModel) ?? WhisperModelCatalog.Find("small")!;
        return new WhisperBatchTranscriber(() => WhisperModels.PathFor(model), () => model.Id);
    }

    public void Start()
    {
        AppLog.Write($"start {typeof(AppHost).Assembly.GetName().Version}");
        // 設計判断: DEC-COM-063
        // ローカルの LLM のサーバーは、Hanasu と一緒に終わるジョブオブジェクトに入れる
        LocalLlmServer.Shared.ProcessStarted = ChildProcessJob.Assign;
        LocalLlmServer.Shared.Log = AppLog.Write;
        // Windows Hello の鍵は、画面のロック・スリープでメモリから消す（次に使うときにまた確認する）
        Microsoft.Win32.SystemEvents.SessionSwitch += OnSessionSwitch;
        Microsoft.Win32.SystemEvents.PowerModeChanged += OnPowerModeChanged;
        tray = new TrayIcon(this);
        Dictation.StateChanged += (_, state) => app.Dispatcher.BeginInvoke(() => tray?.UpdateState(state));
        History.Changed += (_, _) => app.Dispatcher.BeginInvoke(() => tray?.UpdateRecent());
        Settings.Changed += OnSettingsChanged;
        Meetings.StateChanged += (_, state) => app.Dispatcher.BeginInvoke(() =>
        {
            tray?.UpdateMeetingState(state);
            RegisterHighlightHotKey();
        });
        Meetings.Notice += (_, notice) => app.Dispatcher.BeginInvoke(() => tray?.ShowBalloon(notice.Title, notice.Message, notice.IsWarning));
        try
        {
            // 前回、記録中・処理中のまま終わった会議を「失敗」にする
            Meetings.Store(Settings.Current).MarkInterruptedMeetings();
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            AppLog.Write($"mark interrupted meetings failed: {e.Message}");
        }
        RegisterHotKeys();
        tray.ShowBalloon("Hanasu を起動しました",
            $"{Settings.Current.HotKey.DisplayString} で音声入力、{Settings.Current.TranslateHotKey.DisplayString} で{TranslationLanguages.MenuVerb(Settings.Current.TranslationLanguages)}して入力します。");
        if (firstRun) ShowSettings();
    }

    // MARK: - 文字起こしと Gemini

    /// <summary>設定のエンジンに合わせて、1 回分の文字起こしを作る</summary>
    private IDictationTranscriber CreateTranscriber(AppSettings settings)
    {
        switch (settings.Engine)
        {
            case TranscriptionEngine.Whisper:
                var model = WhisperModelCatalog.Find(settings.WhisperModel) ?? WhisperModelCatalog.Find("small")!;
                return new RecordThenTranscribe(new WasapiRecorder(),
                    new WhisperBatchTranscriber(() => WhisperModels.PathFor(model), () => model.Id));
            case TranscriptionEngine.Gemini:
                return new RecordThenTranscribe(new WasapiRecorder(),
                    new GeminiBatchTranscriber(() => CreateGeminiClient(settings, TimeSpan.FromSeconds(60)), () => settings.Model, () => settings.DictionaryWords));
            default:
                return new WindowsSpeechTranscriber();
        }
    }

    /// <summary>設定から Gemini のクライアントを作る（音声の文字起こしに使う）。認証情報がなければ null</summary>
    public GeminiClient? CreateGeminiClient(AppSettings settings, TimeSpan? timeout = null) =>
        TextAiFactory.CreateGemini(settings, Secrets, timeout ?? TimeSpan.FromSeconds(15));

    /// <summary>
    /// 文章の処理（整形・英訳・議事録）に使う AI を、用途ごとの設定（REQ-COM-024）で作る。認証情報がなければ null。
    /// 待ち時間は、音声入力が 15 秒、議事録が Gemini 180 秒・Claude 300 秒
    /// </summary>
    public ITextAiClient? CreateTextAi(AppSettings settings, TextAiUse use)
    {
        var provider = TextAiFactory.ProviderFor(settings, use);
        // ローカルは、モデルの読み込みを含めてもっと長く待つ（LocalLlmClient.MinimumTimeout。DEC-COM-064）
        var timeout = use == TextAiUse.Dictation ? TimeSpan.FromSeconds(15)
            : provider == TextAiProvider.Claude ? TimeSpan.FromSeconds(300) : TimeSpan.FromSeconds(180);
        return TextAiFactory.Create(settings, Secrets, use, timeout);
    }

    // MARK: - ホットキー

    private void RegisterHotKeys()
    {
        hotKeys.Unregister(dictationHotKeyId);
        hotKeys.Unregister(translateHotKeyId);
        hotKeys.Unregister(meetingHotKeyId);
        dictationHotKeyId = translateHotKeyId = meetingHotKeyId = null;
        RegisterHighlightHotKey();
        if (hotKeysSuspended) return;
        var s = Settings.Current;
        dictationHotKeyId = hotKeys.Register(s.HotKey, kind => Dictation.HandleHotKey(kind, DictationMode.Refine));
        // 設計判断: DEC-DIC-027（翻訳の言語は押したときの設定で決める）
        translateHotKeyId = hotKeys.Register(s.TranslateHotKey, kind => Dictation.HandleHotKey(kind, Dictation.PrimaryTranslateMode));
        meetingHotKeyId = hotKeys.Register(s.MeetingHotKey, kind =>
        {
            if (kind == HotKeyEventKind.Pressed) _ = Meetings.ToggleAsync();
        });
        var failed = new List<string>();
        if (dictationHotKeyId is null) failed.Add(s.HotKey.DisplayString);
        if (translateHotKeyId is null) failed.Add(s.TranslateHotKey.DisplayString);
        if (meetingHotKeyId is null) failed.Add(s.MeetingHotKey.DisplayString);
        if (failed.Count > 0)
        {
            AppLog.Write($"hotkey registration failed: {string.Join(", ", failed)}");
            tray?.ShowBalloon("ショートカットを登録できませんでした",
                $"{string.Join("、", failed)} はほかのアプリが使っています。設定 → 一般 で別のキーにしてください。", warning: true);
        }
    }

    /// <summary>「ここ重要」のショートカットは記録中だけ登録する（ほかのアプリのキーを普段は奪わない。Mac 版と同じ）</summary>
    private void RegisterHighlightHotKey()
    {
        hotKeys.Unregister(highlightHotKeyId);
        highlightHotKeyId = null;
        var s = Settings.Current;
        if (hotKeysSuspended || !s.HighlightHotKeyEnabled || Meetings.State != MeetingState.Recording) return;
        highlightHotKeyId = hotKeys.Register(s.HighlightHotKey, kind =>
        {
            if (kind == HotKeyEventKind.Pressed) Meetings.AddHighlight();
        });
        if (highlightHotKeyId is null)
        {
            tray?.ShowBalloon("「ここ重要」のショートカットを登録できませんでした",
                $"{s.HighlightHotKey.DisplayString} はほかのアプリが使っています。会議ノートの「★ ここ重要」ボタンを使うか、設定 → 会議 で別のキーにしてください。", warning: true);
        }
    }

    /// <summary>設定画面でショートカットを記録している間は外す（記録したいキーを横取りしないため）</summary>
    public void SuspendHotKeys(bool suspend)
    {
        hotKeysSuspended = suspend;
        RegisterHotKeys();
    }

    /// <summary>録音中だけ Esc を取り消しに使う</summary>
    private void SetEscapeHotKey(bool enabled)
    {
        void Apply()
        {
            if (enabled && escapeHotKeyId is null)
            {
                escapeHotKeyId = hotKeys.Register(new HotKeyCombo(HotKeyModifiers.None, HotKeyCombo.VkEscape), kind =>
                {
                    if (kind == HotKeyEventKind.Pressed) Dictation.Cancel();
                });
            }
            else if (!enabled && escapeHotKeyId is not null)
            {
                hotKeys.Unregister(escapeHotKeyId);
                escapeHotKeyId = null;
            }
        }
        if (app.Dispatcher.CheckAccess()) Apply();
        else app.Dispatcher.Invoke(Apply);
    }

    private void OnSettingsChanged(object? sender, SettingsChangedEventArgs e)
    {
        // 履歴の上限を縮めたら、その場で古いものを消す（DEC-DIC-073）
        if (e.Before.HistoryPolicy != e.After.HistoryPolicy) History.ApplyPolicy(e.After.HistoryPolicy);
        if (e.Before.HotKey != e.After.HotKey || e.Before.TranslateHotKey != e.After.TranslateHotKey
            || e.Before.MeetingHotKey != e.After.MeetingHotKey || e.Before.HighlightHotKey != e.After.HighlightHotKey
            || e.Before.HighlightHotKeyEnabled != e.After.HighlightHotKeyEnabled)
        {
            app.Dispatcher.BeginInvoke(() =>
            {
                RegisterHotKeys();
                tray?.UpdateMenuLabels();
            });
        }
        // メニューの「英訳して入力」「和訳して入力」「翻訳して入力」を設定に合わせる（REQ-DIC-013）
        else if (!e.Before.TranslationLanguages.SequenceEqual(e.After.TranslationLanguages))
        {
            app.Dispatcher.BeginInvoke(() => tray?.UpdateMenuLabels());
        }
    }

    // MARK: - メニューから

    /// <summary>タスクトレイのメニューから始める。メニューを開くと前面がタスクバーに移るので、元のアプリを前面に戻してから録音する</summary>
    public async void StartFromMenu(DictationMode mode)
    {
        if (Dictation.State == Core.Dictation.DictationState.Idle)
        {
            foreground.RestoreLastExternalWindow();
            await Task.Delay(150);
        }
        Dictation.ToggleFromMenu(mode);
    }

    public void ShowSettings()
    {
        if (settingsWindow is null)
        {
            settingsWindow = new SettingsWindow(this);
            settingsWindow.Closed += (_, _) => settingsWindow = null;
            settingsWindow.Show();
        }
        if (settingsWindow.WindowState == WindowState.Minimized) settingsWindow.WindowState = WindowState.Normal;
        settingsWindow.Activate();
    }

    public void ShowMeetings()
    {
        if (meetingWindow is null)
        {
            meetingWindow = new MeetingWindow(this);
            meetingWindow.Closed += (_, _) => meetingWindow = null;
            meetingWindow.Show();
        }
        if (meetingWindow.WindowState == WindowState.Minimized) meetingWindow.WindowState = WindowState.Normal;
        meetingWindow.Activate();
    }

    public void ShowHistory()
    {
        if (historyWindow is null)
        {
            historyWindow = new HistoryWindow(this);
            historyWindow.Closed += (_, _) => historyWindow = null;
            historyWindow.Show();
        }
        if (historyWindow.WindowState == WindowState.Minimized) historyWindow.WindowState = WindowState.Normal;
        historyWindow.Activate();
    }

    /// <summary>タスクトレイのメニューから会議の記録を始める・止める</summary>
    public void ToggleMeetingFromMenu() => _ = Meetings.ToggleAsync();

    public void CopyToClipboard(string text)
    {
        try
        {
            Clipboard.SetText(text);
            tray?.ShowBalloon("コピーしました", text.Length > 80 ? text[..80] + "…" : text);
        }
        catch (System.Runtime.InteropServices.ExternalException e)
        {
            AppLog.Write($"copy failed: {e.Message}");
        }
    }

    public void Quit()
    {
        if (Meetings.State != MeetingState.Idle
            && MessageBox.Show("会議の記録中（または記録のあとの処理中）です。終了すると、この会議の文字起こしと議事録は作られません（音声ファイルは残ります）。終了しますか？",
                "Hanasu", MessageBoxButton.OKCancel, MessageBoxImage.Warning, MessageBoxResult.Cancel) != MessageBoxResult.OK)
        {
            return;
        }
        Dictation.Cancel();
        app.Shutdown();
    }

    private void OnSessionSwitch(object? sender, Microsoft.Win32.SessionSwitchEventArgs e)
    {
        if (e.Reason is Microsoft.Win32.SessionSwitchReason.SessionLock or Microsoft.Win32.SessionSwitchReason.SessionLogoff
            or Microsoft.Win32.SessionSwitchReason.ConsoleDisconnect or Microsoft.Win32.SessionSwitchReason.RemoteDisconnect)
        {
            Secrets.Lock();
        }
    }

    private void OnPowerModeChanged(object? sender, Microsoft.Win32.PowerModeChangedEventArgs e)
    {
        if (e.Mode == Microsoft.Win32.PowerModes.Suspend) Secrets.Lock();
    }

    public void Dispose()
    {
        Microsoft.Win32.SystemEvents.SessionSwitch -= OnSessionSwitch;
        Microsoft.Win32.SystemEvents.PowerModeChanged -= OnPowerModeChanged;
        Secrets.Lock();
        tray?.Dispose();
        hotKeys.Dispose();
        foreground.Dispose();
        hud.Close();
        WhisperBatchTranscriber.ReleaseCachedModel();
        LocalLlmServer.Shared.Stop();
    }
}
