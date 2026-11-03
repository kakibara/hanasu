using System.IO;
using System.Windows;
using Hanasu.Core.Dictation;
using Hanasu.Core.Gemini;
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
    private int? meetingHotKeyId;
    private int? highlightHotKeyId;
    private int? dictationHotKeyId;
    private int? translateHotKeyId;
    private int? escapeHotKeyId;
    private bool hotKeysSuspended;

    public SettingsService Settings { get; }
    public WhisperModelManager WhisperModels { get; } = new(HanasuPaths.ModelsDirectory);
    public RecentResults Recent { get; } = new();
    public DictationController Dictation { get; }
    public MeetingController Meetings { get; }

    public AppHost(Application app)
    {
        this.app = app;
        var store = new SettingsStore();
        firstRun = !File.Exists(store.Path);
        Settings = new SettingsService(store, new DpapiSecretProtector());
        Dictation = new DictationController(new DictationServices
        {
            Settings = () => Settings.Current,
            CreateTranscriber = CreateTranscriber,
            Processor = new DictationTextProcessor(s => CreateGeminiClient(s)),
            Inserter = inserter,
            Hud = hud,
            Recent = Recent,
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
            // 議事録は長い（1 時間の会議で数万文字）ので、待ち時間を長めにする
            CreateMinutesClient = s => CreateGeminiClient(s, TimeSpan.FromSeconds(180)),
            Log = AppLog.Write,
        });
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
        tray = new TrayIcon(this);
        Dictation.StateChanged += (_, state) => tray?.UpdateState(state);
        Recent.Changed += (_, _) => app.Dispatcher.BeginInvoke(() => tray?.UpdateRecent());
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
            $"{Settings.Current.HotKey.DisplayString} で音声入力、{Settings.Current.TranslateHotKey.DisplayString} で英訳して入力します。");
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

    /// <summary>設定から Gemini のクライアントを作る。認証情報がなければ null</summary>
    public GeminiClient? CreateGeminiClient(AppSettings settings, TimeSpan? timeout = null)
    {
        var auth = GeminiAuthResolver.Resolve(settings, Settings.Protector);
        return auth is null ? null : new GeminiClient(auth) { Timeout = timeout ?? TimeSpan.FromSeconds(15) };
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
        translateHotKeyId = hotKeys.Register(s.TranslateHotKey, kind => Dictation.HandleHotKey(kind, DictationMode.TranslateToEnglish));
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
                "Hanasu", MessageBoxButton.OKCancel, MessageBoxImage.Warning) != MessageBoxResult.OK)
        {
            return;
        }
        Dictation.Cancel();
        app.Shutdown();
    }

    public void Dispose()
    {
        tray?.Dispose();
        hotKeys.Dispose();
        foreground.Dispose();
        hud.Close();
        WhisperBatchTranscriber.ReleaseCachedModel();
    }
}
