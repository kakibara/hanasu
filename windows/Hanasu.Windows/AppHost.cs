using System.IO;
using System.Windows;
using Hanasu.Core.Dictation;
using Hanasu.Core.Gemini;
using Hanasu.Core.Settings;
using Hanasu.Core.Transcription;
using Hanasu.Whisper;
using Hanasu.Windows.Services;
using Hanasu.Windows.Views;

namespace Hanasu.Windows;

/// <summary>
/// 部品を組み立てて、ホットキー・タスクトレイ・設定画面をつなぐ。
/// 会議の記録を足すときも、ここで MeetingController などを作り、同じ SettingsService・WhisperModelManager・HUD の作りを使う。
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
    private int? dictationHotKeyId;
    private int? translateHotKeyId;
    private int? escapeHotKeyId;
    private bool hotKeysSuspended;

    public SettingsService Settings { get; }
    public WhisperModelManager WhisperModels { get; } = new(HanasuPaths.ModelsDirectory);
    public RecentResults Recent { get; } = new();
    public DictationController Dictation { get; }

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
    }

    public void Start()
    {
        AppLog.Write($"start {typeof(AppHost).Assembly.GetName().Version}");
        tray = new TrayIcon(this);
        Dictation.StateChanged += (_, state) => tray?.UpdateState(state);
        Recent.Changed += (_, _) => app.Dispatcher.BeginInvoke(() => tray?.UpdateRecent());
        Settings.Changed += OnSettingsChanged;
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
        dictationHotKeyId = translateHotKeyId = null;
        if (hotKeysSuspended) return;
        var s = Settings.Current;
        dictationHotKeyId = hotKeys.Register(s.HotKey, kind => Dictation.HandleHotKey(kind, DictationMode.Refine));
        translateHotKeyId = hotKeys.Register(s.TranslateHotKey, kind => Dictation.HandleHotKey(kind, DictationMode.TranslateToEnglish));
        var failed = new List<string>();
        if (dictationHotKeyId is null) failed.Add(s.HotKey.DisplayString);
        if (translateHotKeyId is null) failed.Add(s.TranslateHotKey.DisplayString);
        if (failed.Count > 0)
        {
            AppLog.Write($"hotkey registration failed: {string.Join(", ", failed)}");
            tray?.ShowBalloon("ショートカットを登録できませんでした",
                $"{string.Join("、", failed)} はほかのアプリが使っています。設定 → 一般 で別のキーにしてください。", warning: true);
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
        if (e.Before.HotKey != e.After.HotKey || e.Before.TranslateHotKey != e.After.TranslateHotKey)
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
