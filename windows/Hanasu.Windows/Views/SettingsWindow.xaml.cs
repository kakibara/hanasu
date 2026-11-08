using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Hanasu.Core.Ai;
using Hanasu.Core.Claude;
using Hanasu.Core.Dictation;
using Hanasu.Core.Gemini;
using Hanasu.Core.LocalLlm;
using Hanasu.Core.Meetings;
using Hanasu.Core.Settings;
using Hanasu.Core.Text;
using Hanasu.Core.Transcription;
using Hanasu.Whisper;
using Hanasu.Windows.Services;
using Microsoft.Win32;

namespace Hanasu.Windows.Views;

/// <summary>
/// 設定画面（一般 / AI / 会議 / 履歴 / 辞書・ルール）。変更はその場で SettingsService に書き、すぐ保存する（Mac 版と同じ）。
/// AI タブでは、音声入力と会議の AI とモデルを別々に選び（REQ-COM-024）、Gemini の認証と Claude の API キーを設定する。
/// API キーは入力欄をマスクし、保存したあとは末尾 4 文字だけを見せる（REQ-COM-021）。
/// </summary>
// 要件: REQ-COM-020, REQ-COM-021, REQ-COM-024
// 設計判断: DEC-COM-140, DEC-COM-144
public partial class SettingsWindow : Window
{
    private readonly AppHost host;
    private readonly SettingsService settings;
    private bool loading = true;

    internal SettingsWindow(AppHost host)
    {
        this.host = host;
        settings = host.Settings;
        InitializeComponent();
        WindowFit.FitToMouseScreen(this);
        LoadValues();
        loading = false;

        DictationHotKeyBox.Recorded += (_, combo) => SetHotKey(combo, translate: false);
        TranslateHotKeyBox.Recorded += (_, combo) => SetHotKey(combo, translate: true);
        MeetingHotKeyBox.Recorded += (_, combo) => SetMeetingHotKey(combo, highlight: false);
        HighlightHotKeyBox.Recorded += (_, combo) => SetMeetingHotKey(combo, highlight: true);
        foreach (var box in new[] { DictationHotKeyBox, TranslateHotKeyBox, MeetingHotKeyBox, HighlightHotKeyBox })
        {
            box.RecordingChanged += (_, recording) => host.SuspendHotKeys(recording);
        }
        host.WhisperModels.StateChanged += OnWhisperStateChanged;
        host.LocalLlmModels.StateChanged += OnLocalModelStateChanged;
        host.Secrets.Changed += OnSecretChanged;
        Closed += (_, _) =>
        {
            host.WhisperModels.StateChanged -= OnWhisperStateChanged;
            host.LocalLlmModels.StateChanged -= OnLocalModelStateChanged;
            host.Secrets.Changed -= OnSecretChanged;
            // 入力欄に残ったキーを消す
            ApiKeyBox.Clear();
            ClaudeKeyBox.Clear();
            host.SuspendHotKeys(false);
        };
    }

    private void LoadValues()
    {
        var s = settings.Current;
        DictationHotKeyBox.Combo = s.HotKey;
        TranslateHotKeyBox.Combo = s.TranslateHotKey;
        BuildTranslationLanguageChecks(s.TranslationLanguages);
        UpdateTranslationControls(s.TranslationLanguages);
        ToggleModeRadio.IsChecked = s.RecordingMode == RecordingMode.Toggle;
        PushToTalkRadio.IsChecked = s.RecordingMode == RecordingMode.PushToTalk;
        EngineCombo.SelectedItem = EngineCombo.Items.OfType<ComboBoxItem>().First(i => (string)i.Tag == s.Engine.ToString());

        WhisperModelCombo.ItemsSource = WhisperModelCatalog.Models;
        WhisperModelCombo.DisplayMemberPath = nameof(WhisperModelInfo.Label);
        WhisperModelCombo.SelectedItem = WhisperModelCatalog.Find(s.WhisperModel);
        WhisperFolderNote.Text = string.Format(Strings.Meeting_SavedIn, host.WhisperModels.Directory);

        var microphones = new List<MicrophoneInfo> { new("", Strings.Device_DefaultMic) };
        microphones.AddRange(WasapiRecorder.ListMicrophones());
        if (s.MicrophoneDeviceId.Length > 0 && microphones.All(m => m.Id != s.MicrophoneDeviceId))
        {
            microphones.Add(new MicrophoneInfo(s.MicrophoneDeviceId, Strings.Device_MissingMic));
        }
        MicrophoneCombo.ItemsSource = microphones;
        MicrophoneCombo.DisplayMemberPath = nameof(MicrophoneInfo.Name);
        MicrophoneCombo.SelectedItem = microphones.First(m => m.Id == s.MicrophoneDeviceId);
        PlaySoundsCheck.IsChecked = s.PlaySounds;
        CheckForUpdatesCheck.IsChecked = s.CheckForUpdatesOnLaunch;
        VersionText.Text = $"Hanasu {host.Updates.CurrentVersion}";
        FallbackKeepRadio.IsChecked = s.PasteFallbackClipboard == PasteFallbackClipboard.KeepResult;
        FallbackRestoreRadio.IsChecked = s.PasteFallbackClipboard == PasteFallbackClipboard.RestoreOriginal;

        RefineCheck.IsChecked = s.RefineWithGemini;
        // 要件: REQ-DIC-082
        RefineLanguageCombo.SelectedItem = RefineLanguageCombo.Items.OfType<ComboBoxItem>().First(i => (string)i.Tag == s.RefineOutputLanguage.ToString());
        RefineLanguageCombo.IsEnabled = s.RefineWithGemini;
        ApiKeyRadio.IsChecked = s.AuthMode == GeminiAuthMode.ApiKey;
        ServiceAccountRadio.IsChecked = s.AuthMode == GeminiAuthMode.ServiceAccount;
        ServiceAccountPathBox.Text = s.ServiceAccountPath;
        VertexLocationBox.Text = s.VertexLocation;
        ModelCombo.ItemsSource = AppSettings.SuggestedModels;
        ModelCombo.Text = s.Model;
        ClaudeModelCombo.ItemsSource = ClaudeModels.All;
        ClaudeModelCombo.DisplayMemberPath = nameof(ClaudeModelInfo.Label);
        ClaudeModelCombo.SelectedItem = ClaudeModels.Find(s.ClaudeModel);
        ClaudeMinutesModelCombo.ItemsSource = ClaudeModels.All;
        ClaudeMinutesModelCombo.DisplayMemberPath = nameof(ClaudeModelInfo.Label);
        ClaudeMinutesModelCombo.SelectedItem = ClaudeModels.Find(s.ClaudeMinutesModel);
        LocalModelCombo.ItemsSource = LocalLlmModel.All;
        LocalModelCombo.DisplayMemberPath = nameof(LocalLlmModel.Label);
        LocalModelCombo.SelectedItem = LocalLlmModel.Find(s.LocalDictationModel);
        LocalMinutesModelCombo.ItemsSource = LocalLlmModel.All;
        LocalMinutesModelCombo.DisplayMemberPath = nameof(LocalLlmModel.Label);
        LocalMinutesModelCombo.SelectedItem = LocalLlmModel.Find(s.LocalMeetingModel);
        DictationAiCombo.SelectedItem = DictationAiCombo.Items.OfType<ComboBoxItem>().First(i => (string)i.Tag == s.DictationAi.ToString());
        MeetingAiCombo.SelectedItem = MeetingAiCombo.Items.OfType<ComboBoxItem>().First(i => (string)i.Tag == s.MeetingAi.ToString());
        SendAppNameCheck.IsChecked = s.SendAppName;

        MeetingHotKeyBox.Combo = s.MeetingHotKey;
        HighlightHotKeyBox.Combo = s.HighlightHotKey;
        HighlightHotKeyCheck.IsChecked = s.HighlightHotKeyEnabled;
        MeetingEngineCombo.SelectedItem = MeetingEngineCombo.Items.OfType<ComboBoxItem>().FirstOrDefault(i => (string)i.Tag == s.MeetingEngine.ToString())
            ?? MeetingEngineCombo.Items[0];
        DiarizeCheck.IsChecked = s.DiarizeOthers;
        MakeMinutesCheck.IsChecked = s.MakeMeetingMinutes;
        MinutesModelCombo.ItemsSource = AppSettings.SuggestedModels;
        MinutesModelCombo.Text = s.MeetingMinutesModel;
        KeepAudioCheck.IsChecked = s.KeepMeetingAudio;
        MeetingsDirBox.Text = new MeetingStore(s.MeetingsDirectory).BaseDirectory;
        UpdateMeetingEngineNote(s.MeetingEngine);

        HistoryEnabledCheck.IsChecked = s.HistoryEnabled;
        HistoryDaysCombo.ItemsSource = LimitItems(HistoryPolicy.DayOptions, s.HistoryMaxDays, HistoryPolicy.DaysLabel);
        HistoryDaysCombo.SelectedItem = ((List<ComboBoxItem>)HistoryDaysCombo.ItemsSource).First(i => (int)i.Tag == s.HistoryMaxDays);
        HistoryCountCombo.ItemsSource = LimitItems(HistoryPolicy.CountOptions, s.HistoryMaxCount, n => string.Format(Strings.Settings_EntryCount, n.ToString("N0")));
        HistoryCountCombo.SelectedItem = ((List<ComboBoxItem>)HistoryCountCombo.ItemsSource).First(i => (int)i.Tag == s.HistoryMaxCount);
        UpdateHistoryStatus();

        DictionaryBox.Text = s.DictionaryText;
        ExtraInstructionsBox.Text = s.ExtraInstructions;

        UpdateEnginePanels(s.Engine);
        UpdateAuthPanels(s.AuthMode);
        UpdateAiPanels();
        UpdateApiKeyStatus();
        UpdateClaudeKeyStatus();
        _ = UpdateHelloAsync();
        UpdateWhisperControls();
        UpdateDictionaryIssues();
    }

    private void Save(Action<AppSettings> mutate)
    {
        if (loading) return;
        var error = settings.Update(mutate);
        SaveStatus.Text = error is null ? Strings.Settings_Saved : string.Format(Strings.Meeting_SaveFailed, error.Message);
    }

    // MARK: - 一般

    // 設計判断: DEC-COM-018
    /// <summary>
    /// combo が、self 以外のショートカットと同じなら、その説明（「… は「会議の記録」のショートカットと同じです…」）。重なっていなければ null。
    /// Mac 版の ShortcutKind.conflict と同じ考え
    /// </summary>
    /// <summary>ほかのショートカットと同じなら、その知らせ（self は自分の種類: dictation / translate / meeting / highlight）</summary>
    private string? ConflictingShortcut(HotKeyCombo combo, string self)
    {
        var s = settings.Current;
        var all = new (string Id, string Name, HotKeyCombo Combo)[]
        {
            ("dictation", Strings.Settings_Dictation, s.HotKey), ("translate", Strings.Settings_TranslateAndType, s.TranslateHotKey),
            ("meeting", Strings.Settings_MeetingRecordingName, s.MeetingHotKey), ("highlight", Strings.Settings_HighlightMark, s.HighlightHotKey),
        };
        var other = all.FirstOrDefault(x => x.Id != self && x.Combo == combo);
        return other.Id is null ? null : string.Format(Strings.Settings_HotKeyConflict, combo.DisplayString, other.Name);
    }

    private void SetHotKey(HotKeyCombo combo, bool translate)
    {
        var problem = combo.Validate() ?? ConflictingShortcut(combo, translate ? "translate" : "dictation");
        if (problem is not null)
        {
            HotKeyError.Text = problem;
            HotKeyError.Visibility = Visibility.Visible;
            return;
        }
        HotKeyError.Visibility = Visibility.Collapsed;
        Save(s =>
        {
            if (translate) s.TranslateHotKey = combo;
            else s.HotKey = combo;
        });
        (translate ? TranslateHotKeyBox : DictationHotKeyBox).Combo = combo;
    }

    private void OnResetDictationHotKey(object sender, RoutedEventArgs e) => SetHotKey(HotKeyCombo.DefaultDictation, translate: false);

    private void OnResetTranslateHotKey(object sender, RoutedEventArgs e) => SetHotKey(HotKeyCombo.DefaultTranslate, translate: true);

    private void OnRecordingModeChanged(object sender, RoutedEventArgs e) =>
        Save(s => s.RecordingMode = PushToTalkRadio.IsChecked == true ? RecordingMode.PushToTalk : RecordingMode.Toggle);

    private void OnEngineChanged(object sender, SelectionChangedEventArgs e)
    {
        if (EngineCombo.SelectedItem is not ComboBoxItem { Tag: string tag } || !Enum.TryParse<TranscriptionEngine>(tag, out var engine)) return;
        Save(s => s.Engine = engine);
        UpdateEnginePanels(engine);
        UpdateAiPanels();
        // Whisper を選んだ時点で、モデルがなければダウンロードを始める
        if (!loading && engine == TranscriptionEngine.Whisper) StartWhisperDownloadIfNeeded();
    }

    private void UpdateEnginePanels(TranscriptionEngine engine)
    {
        WindowsEnginePanel.Visibility = engine == TranscriptionEngine.Windows ? Visibility.Visible : Visibility.Collapsed;
        WhisperEnginePanel.Visibility = engine == TranscriptionEngine.Whisper ? Visibility.Visible : Visibility.Collapsed;
        GeminiEnginePanel.Visibility = engine == TranscriptionEngine.Gemini ? Visibility.Visible : Visibility.Collapsed;
        MicrophoneCombo.IsEnabled = engine != TranscriptionEngine.Windows;
        MicrophoneNote.Text = engine == TranscriptionEngine.Windows
            ? Strings.Settings_MicNote_Windows
            : Strings.Settings_MicNote_Selected;
    }

    private void OnMicrophoneChanged(object sender, SelectionChangedEventArgs e)
    {
        if (MicrophoneCombo.SelectedItem is MicrophoneInfo mic) Save(s => s.MicrophoneDeviceId = mic.Id);
    }

    private void OnPlaySoundsChanged(object sender, RoutedEventArgs e) => Save(s => s.PlaySounds = PlaySoundsCheck.IsChecked == true);

    // 要件: REQ-REL-010
    private void OnCheckForUpdatesChanged(object sender, RoutedEventArgs e) => Save(s => s.CheckForUpdatesOnLaunch = CheckForUpdatesCheck.IsChecked == true);

    // 要件: REQ-REL-011
    private async void OnCheckForUpdatesNow(object sender, RoutedEventArgs e) => await host.Updates.CheckManuallyAsync();

    // 要件: REQ-DIC-081
    private void OnPasteFallbackChanged(object sender, RoutedEventArgs e) =>
        Save(s => s.PasteFallbackClipboard = FallbackRestoreRadio.IsChecked == true ? PasteFallbackClipboard.RestoreOriginal : PasteFallbackClipboard.KeepResult);

    private void OnOpenMicrophonePrivacy(object sender, RoutedEventArgs e) => Shell.Open("ms-settings:privacy-microphone");

    private void OnOpenSpeechPrivacy(object sender, RoutedEventArgs e) => Shell.Open("ms-settings:privacy-speech");

    private void OnOpenLanguageSettings(object sender, RoutedEventArgs e) => Shell.Open("ms-settings:regionlanguage");

    private void OnOpenLogs(object sender, RoutedEventArgs e) => OpenFolder(AppLog.Directory);

    private void OnOpenSettingsFolder(object sender, RoutedEventArgs e) => OpenFolder(HanasuPaths.SettingsDirectory);

    private void OnOpenModelsFolder(object sender, RoutedEventArgs e) => OpenFolder(host.WhisperModels.Directory);

    // MARK: - 履歴

    /// <summary>選択肢の一覧。設定ファイルを手で書き換えた値など、選択肢にない値も出す</summary>
    private static List<ComboBoxItem> LimitItems(IReadOnlyList<int> options, int current, Func<int, string> label)
    {
        var values = options.Contains(current) ? options : options.Append(current);
        return values.Select(v => new ComboBoxItem { Content = label(v), Tag = v }).ToList();
    }

    // 要件: REQ-DIC-063
    // 設計判断: DEC-DIC-073, DEC-DIC-074
    private void OnHistoryEnabledChanged(object sender, RoutedEventArgs e)
    {
        Save(s => s.HistoryEnabled = HistoryEnabledCheck.IsChecked == true);
        UpdateHistoryStatus();
    }

    private void OnHistoryLimitChanged(object sender, SelectionChangedEventArgs e)
    {
        if (HistoryDaysCombo.SelectedItem is not ComboBoxItem days || HistoryCountCombo.SelectedItem is not ComboBoxItem count) return;
        Save(s =>
        {
            s.HistoryMaxDays = (int)days.Tag;
            s.HistoryMaxCount = (int)count.Tag;
        });
        UpdateHistoryStatus();
    }

    private void OnOpenHistory(object sender, RoutedEventArgs e) => host.ShowHistory();

    private void OnOpenHistoryFolder(object sender, RoutedEventArgs e) => OpenFolder(host.History.Directory);

    private void OnDeleteAllHistory(object sender, RoutedEventArgs e)
    {
        var count = host.History.Entries.Count;
        if (count == 0) return;
        if (MessageBox.Show(this, string.Format(Strings.History_ConfirmDeleteAll, count), "Hanasu",
                MessageBoxButton.OKCancel, MessageBoxImage.Warning, MessageBoxResult.Cancel) != MessageBoxResult.OK) return;
        host.History.DeleteAll();
        UpdateHistoryStatus();
    }

    private void UpdateHistoryStatus() =>
        HistoryStatus.Text = string.Format(Strings.Settings_HistoryStatus, host.History.Entries.Count, host.History.FilePath);

    private static void OpenFolder(string path)
    {
        Directory.CreateDirectory(path);
        Process.Start(new ProcessStartInfo("explorer.exe", $"\"{path}\"") { UseShellExecute = true });
    }

    // MARK: - Whisper のモデル

    private WhisperModelInfo? SelectedWhisperModel => WhisperModelCombo.SelectedItem as WhisperModelInfo;

    private void OnWhisperModelChanged(object sender, SelectionChangedEventArgs e)
    {
        if (SelectedWhisperModel is not { } model) return;
        Save(s => s.WhisperModel = model.Id);
        UpdateWhisperControls();
        // モデルを選んだ時点でダウンロードする
        if (!loading) StartWhisperDownloadIfNeeded();
    }

    private void StartWhisperDownloadIfNeeded()
    {
        if (SelectedWhisperModel is { } model && host.WhisperModels.StateOf(model).Status is WhisperModelStatus.NotDownloaded or WhisperModelStatus.Failed)
        {
            _ = host.WhisperModels.DownloadAsync(model);
        }
    }

    private void OnWhisperDownload(object sender, RoutedEventArgs e) => StartWhisperDownloadIfNeeded();

    private void OnWhisperCancel(object sender, RoutedEventArgs e)
    {
        if (SelectedWhisperModel is { } model) host.WhisperModels.CancelDownload(model);
    }

    private void OnWhisperDelete(object sender, RoutedEventArgs e)
    {
        if (SelectedWhisperModel is not { } model) return;
        if (MessageBox.Show(this, string.Format(Strings.Settings_ConfirmDeleteWhisper, model.Id, model.SizeLabel), "Hanasu",
                MessageBoxButton.OKCancel, MessageBoxImage.Question, MessageBoxResult.Cancel) != MessageBoxResult.OK) return;
        try
        {
            // 読み込み中のモデルはファイルを開いているので、先に手放す
            WhisperBatchTranscriber.ReleaseCachedModel();
            host.WhisperModels.Delete(model);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            WhisperStatus.Text = string.Format(Strings.DeleteFailed, ex.Message);
        }
    }

    private void OnWhisperStateChanged(object? sender, WhisperModelState state) =>
        Dispatcher.BeginInvoke(() =>
        {
            if (state.Model == SelectedWhisperModel) UpdateWhisperControls();
        });

    private void UpdateWhisperControls()
    {
        if (SelectedWhisperModel is not { } model) return;
        var state = host.WhisperModels.StateOf(model);
        WhisperDownloadButton.Visibility = state.Status is WhisperModelStatus.NotDownloaded or WhisperModelStatus.Failed ? Visibility.Visible : Visibility.Collapsed;
        WhisperCancelButton.Visibility = state.Status == WhisperModelStatus.Downloading ? Visibility.Visible : Visibility.Collapsed;
        WhisperDeleteButton.Visibility = state.Status == WhisperModelStatus.Downloaded ? Visibility.Visible : Visibility.Collapsed;
        WhisperProgress.Visibility = state.Status == WhisperModelStatus.Downloading ? Visibility.Visible : Visibility.Collapsed;
        WhisperProgress.Value = state.Progress;
        // 設計判断: DEC-COM-028（大きさを先に見せる。Mac 版と同じ）
        WhisperDownloadButton.Content = string.Format(Strings.Settings_DownloadWithSize, model.SizeLabel);
        WhisperStatus.Text = state.Status switch
        {
            WhisperModelStatus.Downloading => string.Format(Strings.Settings_DownloadingWithSize, state.Progress.ToString("P0"), model.SizeLabel),
            WhisperModelStatus.Downloaded => Strings.Settings_Downloaded,
            WhisperModelStatus.Failed => string.Format(Strings.Settings_DownloadFailed, state.Error),
            _ => Strings.Settings_NotDownloaded,
        };
    }

    // MARK: - AI（音声入力と会議で別々に選ぶ）

    private static TextAiProvider? ProviderOf(ComboBox combo) =>
        combo.SelectedItem is ComboBoxItem { Tag: string tag } && Enum.TryParse<TextAiProvider>(tag, out var p) ? p : null;

    private void OnDictationAiChanged(object sender, SelectionChangedEventArgs e)
    {
        if (ProviderOf(DictationAiCombo) is not { } provider) return;
        Save(s => s.DictationAi = provider);
        UpdateAiPanels();
    }

    private void OnMeetingAiChanged(object sender, SelectionChangedEventArgs e)
    {
        if (ProviderOf(MeetingAiCombo) is not { } provider) return;
        Save(s => s.MeetingAi = provider);
        UpdateAiPanels();
    }

    private void OnClaudeModelChanged(object sender, SelectionChangedEventArgs e)
    {
        if (ClaudeModelCombo.SelectedItem is ClaudeModelInfo model) Save(s => s.ClaudeModel = model.Id);
    }

    private void OnClaudeMinutesModelChanged(object sender, SelectionChangedEventArgs e)
    {
        if (ClaudeMinutesModelCombo.SelectedItem is ClaudeModelInfo model) Save(s => s.ClaudeMinutesModel = model.Id);
        UpdateAiPanels();
    }

    // MARK: - ローカルの LLM（REQ-COM-030）

    private void OnLocalModelChanged(object sender, SelectionChangedEventArgs e)
    {
        if (LocalModelCombo.SelectedItem is LocalLlmModel model) Save(s => s.LocalDictationModel = model.Id);
        UpdateAiPanels();
    }

    private void OnLocalMinutesModelChanged(object sender, SelectionChangedEventArgs e)
    {
        if (LocalMinutesModelCombo.SelectedItem is LocalLlmModel model) Save(s => s.LocalMeetingModel = model.Id);
        UpdateAiPanels();
    }

    private static LocalLlmModel? LocalModelOf(object sender) => (sender as FrameworkElement)?.Tag is string id ? LocalLlmModel.Find(id) : null;

    private void OnLocalDownload(object sender, RoutedEventArgs e)
    {
        if (LocalModelOf(sender) is { } model) _ = host.LocalLlmModels.DownloadAsync(model);
    }

    private void OnLocalCancel(object sender, RoutedEventArgs e)
    {
        if (LocalModelOf(sender) is { } model) host.LocalLlmModels.CancelDownload(model);
    }

    private void OnLocalDelete(object sender, RoutedEventArgs e)
    {
        if (LocalModelOf(sender) is not { } model) return;
        if (MessageBox.Show(this, string.Format(Strings.Settings_ConfirmDeleteLocal, model.Name, model.SizeLabel), "Hanasu",
                MessageBoxButton.OKCancel, MessageBoxImage.Question, MessageBoxResult.Cancel) != MessageBoxResult.OK) return;
        try
        {
            host.LocalLlmModels.Delete(model);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            MessageBox.Show(this, string.Format(Strings.DeleteFailed, ex.Message), "Hanasu");
        }
    }

    private void OnLocalModelStateChanged(object? sender, LocalLlmModelState state) =>
        Dispatcher.BeginInvoke(() => { UpdateLocalModelList(); UpdateAiPanels(); });

    /// <summary>設定画面の 1 行（モデル・状態・ライセンス）</summary>
    private sealed record LocalModelRow(string Id, string Title, string Status, string License, Brush LicenseBrush, double Progress,
        Visibility DownloadVisibility, Visibility CancelVisibility, Visibility DeleteVisibility);

    // 設計判断: DEC-COM-066
    private void UpdateLocalModelList()
    {
        LocalModelList.ItemsSource = LocalLlmModel.All.Select(model =>
        {
            var state = host.LocalLlmModels.StateOf(model);
            static Visibility Show(bool on) => on ? Visibility.Visible : Visibility.Collapsed;
            var status = state.Status switch
            {
                LocalLlmModelStatus.Downloading => string.Format(Strings.Settings_Downloading, state.Progress.ToString("P0")),
                LocalLlmModelStatus.Downloaded => Strings.Settings_Downloaded,
                LocalLlmModelStatus.Failed => string.Format(Strings.Settings_DownloadFailed, state.Error),
                _ => Strings.Settings_NotDownloaded,
            };
            return new LocalModelRow(model.Id, model.Label, $"{status}　{model.Summary}", $"{model.LicenseNote}（{model.LicenseUrl}）",
                model == LocalLlmModel.Lfm25JP ? Brushes.DarkOrange : Brushes.Gray, state.Progress,
                Show(state.Status is LocalLlmModelStatus.NotDownloaded or LocalLlmModelStatus.Failed),
                Show(state.Status == LocalLlmModelStatus.Downloading),
                Show(state.Status == LocalLlmModelStatus.Downloaded));
        }).ToList();
    }

    /// <summary>選んだ AI のモデルの欄だけを出し、認証情報が足りなければ知らせる</summary>
    private void UpdateAiPanels()
    {
        if (ModelCombo is null || MinutesAiNote is null) return;
        var s = settings.Current;
        ModelCombo.Visibility = s.DictationAi == TextAiProvider.Gemini ? Visibility.Visible : Visibility.Collapsed;
        ClaudeModelCombo.Visibility = s.DictationAi == TextAiProvider.Claude ? Visibility.Visible : Visibility.Collapsed;
        MinutesModelCombo.Visibility = s.MeetingAi == TextAiProvider.Gemini ? Visibility.Visible : Visibility.Collapsed;
        ClaudeMinutesModelCombo.Visibility = s.MeetingAi == TextAiProvider.Claude ? Visibility.Visible : Visibility.Collapsed;
        LocalModelCombo.Visibility = s.DictationAi == TextAiProvider.Local ? Visibility.Visible : Visibility.Collapsed;
        LocalMinutesModelCombo.Visibility = s.MeetingAi == TextAiProvider.Local ? Visibility.Visible : Visibility.Collapsed;
        var localUsed = s.DictationAi == TextAiProvider.Local || s.MeetingAi == TextAiProvider.Local;
        LocalLlmPanel.Visibility = localUsed ? Visibility.Visible : Visibility.Collapsed;
        if (localUsed) UpdateLocalModelList();
        MinutesAiNote.Text = string.Format(Strings.Settings_MinutesAiNote, TextAiFactory.NameOf(s.MeetingAi), s.MinutesModel);

        var missing = new List<string>();
        var claudeNeeded = s.DictationAi == TextAiProvider.Claude || s.MeetingAi == TextAiProvider.Claude;
        var geminiNeeded = s.DictationAi == TextAiProvider.Gemini || s.MeetingAi == TextAiProvider.Gemini
            || s.Engine == TranscriptionEngine.Gemini || s.MeetingEngine == TranscriptionEngine.Gemini;
        if (claudeNeeded && !host.Secrets.Has(SecretKind.ClaudeApiKey)) missing.Add(Strings.Settings_ClaudeApiKey);
        foreach (var model in new[]
                 {
                     s.DictationAi == TextAiProvider.Local ? LocalLlmModel.Find(s.LocalDictationModel) : null,
                     s.MeetingAi == TextAiProvider.Local ? LocalLlmModel.Find(s.LocalMeetingModel) : null,
                 }.OfType<LocalLlmModel>().Distinct())
        {
            if (host.LocalLlmModels.StateOf(model).Status != LocalLlmModelStatus.Downloaded) missing.Add(string.Format(Strings.Settings_Missing_LocalModel, model.Name));
        }
        if (geminiNeeded && (s.AuthMode == GeminiAuthMode.ApiKey ? !host.Secrets.Has(SecretKind.GeminiApiKey) : s.ServiceAccountPath.Trim().Length == 0))
        {
            missing.Add(Strings.Settings_Missing_GeminiCredentials);
        }
        AiCredentialNote.Text = missing.Count == 0 ? "" : string.Format(Strings.Settings_MissingNote, string.Join(Strings.Separator, missing));
        AiCredentialNote.Visibility = missing.Count == 0 ? Visibility.Collapsed : Visibility.Visible;
    }

    private void OnRefineChanged(object sender, RoutedEventArgs e)
    {
        var on = RefineCheck.IsChecked == true;
        Save(s => s.RefineWithGemini = on);
        // 要件: REQ-DIC-082（整形がオフのときは、整形の言語を選べない）
        if (RefineLanguageCombo is not null) RefineLanguageCombo.IsEnabled = on;
    }

    // 要件: REQ-DIC-082
    private void OnRefineLanguageChanged(object sender, SelectionChangedEventArgs e)
    {
        if (RefineLanguageCombo.SelectedItem is not ComboBoxItem { Tag: string tag } || !Enum.TryParse<RefineOutputLanguage>(tag, out var language)) return;
        Save(s => s.RefineOutputLanguage = language);
    }

    // MARK: - Gemini の認証

    private void OnAuthModeChanged(object sender, RoutedEventArgs e)
    {
        var mode = ServiceAccountRadio.IsChecked == true ? GeminiAuthMode.ServiceAccount : GeminiAuthMode.ApiKey;
        Save(s => s.AuthMode = mode);
        UpdateAuthPanels(mode);
        UpdateAiPanels();
    }

    private void UpdateAuthPanels(GeminiAuthMode mode)
    {
        ApiKeyPanel.Visibility = mode == GeminiAuthMode.ApiKey ? Visibility.Visible : Visibility.Collapsed;
        ServiceAccountPanel.Visibility = mode == GeminiAuthMode.ServiceAccount ? Visibility.Visible : Visibility.Collapsed;
    }

    private void OnSaveApiKey(object sender, RoutedEventArgs e) => _ = SaveKeyAsync(SecretKind.GeminiApiKey, ApiKeyBox, ApiKeyStatus);

    private void OnDeleteApiKey(object sender, RoutedEventArgs e)
    {
        if (!ConfirmDeleteKey("Gemini")) return;
        _ = DeleteKeyAsync(SecretKind.GeminiApiKey, ApiKeyBox, ApiKeyStatus);
    }

    private bool ConfirmDeleteKey(string name) =>
        MessageBox.Show(this, string.Format(Strings.Settings_ConfirmDeleteKey, name), "Hanasu",
            MessageBoxButton.OKCancel, MessageBoxImage.Question, MessageBoxResult.Cancel) == MessageBoxResult.OK;

    private void UpdateApiKeyStatus() => ApiKeyStatus.Text = host.Secrets.Describe(SecretKind.GeminiApiKey).Describe();

    // 設計判断: DEC-COM-143
    /// <summary>
    /// Gemini の「接続を試す」（Claude の OnCheckClaude と同じ）。API キーの入力欄にキーがあればそのキーで（保存はしない）、
    /// なければ設定の認証（保存したキーかサービスアカウント）で、音声入力の Gemini のモデルの情報を取る
    /// </summary>
    private async void OnCheckGemini(object sender, RoutedEventArgs e)
    {
        var s = settings.Current;
        var apiKeyMode = s.AuthMode == GeminiAuthMode.ApiKey;
        var typed = apiKeyMode ? ApiKeyBox.Password.Trim() : "";
        var status = apiKeyMode ? ApiKeyStatus : ServiceAccountStatus;
        var model = s.Model;
        GeminiCheckButton.IsEnabled = GeminiCheckServiceAccountButton.IsEnabled = false;
        status.Text = apiKeyMode ? Strings.Settings_ConnectingGemini : Strings.Settings_ConnectingVertex;
        try
        {
            GeminiAuth auth = typed.Length > 0
                ? new GeminiAuth.ApiKey(typed)
                : GeminiAuthResolver.Resolve(s, host.Secrets) ?? throw GeminiException.MissingCredentials();
            await new GeminiClient(auth).CheckAsync(model);
            status.Text = typed.Length > 0
                ? string.Format(Strings.Settings_ConnectedUnsavedKey, model)
                : string.Format(Strings.Settings_ConnectedModel, model, apiKeyMode ? host.Secrets.Describe(SecretKind.GeminiApiKey).Describe() : "").TrimEnd();
        }
        catch (Exception ex) when (ex is TextAiException or ServiceAccountException or HttpRequestException or IOException)
        {
            status.Text = ex.Message;
        }
        finally
        {
            GeminiCheckButton.IsEnabled = GeminiCheckServiceAccountButton.IsEnabled = true;
        }
    }

    // MARK: - Claude の API キー

    private void OnSaveClaudeKey(object sender, RoutedEventArgs e) => _ = SaveKeyAsync(SecretKind.ClaudeApiKey, ClaudeKeyBox, ClaudeKeyStatus);

    private void OnDeleteClaudeKey(object sender, RoutedEventArgs e)
    {
        if (!ConfirmDeleteKey("Claude")) return;
        _ = DeleteKeyAsync(SecretKind.ClaudeApiKey, ClaudeKeyBox, ClaudeKeyStatus);
    }

    private void UpdateClaudeKeyStatus() => ClaudeKeyStatus.Text = host.Secrets.Describe(SecretKind.ClaudeApiKey).Describe();

    /// <summary>入力欄のキーを保存して、欄を空にする（保存したキーは画面に戻さない）</summary>
    private async Task SaveKeyAsync(SecretKind kind, PasswordBox box, TextBlock status)
    {
        var value = box.Password.Trim();
        if (value.Length == 0)
        {
            status.Text = Strings.Settings_EnterApiKey;
            return;
        }
        if (kind == SecretKind.ClaudeApiKey && !value.StartsWith("sk-ant-", StringComparison.Ordinal))
        {
            status.Text = Strings.Settings_ClaudeKeyPrefix;
            return;
        }
        try
        {
            await host.Secrets.SetAsync(kind, value);
            box.Clear();
            status.Text = host.Secrets.Describe(kind).Describe();
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or SecretAccessException or System.Security.Cryptography.CryptographicException)
        {
            status.Text = string.Format(Strings.Meeting_SaveFailed, ex.Message);
        }
        UpdateAiPanels();
    }

    private async Task DeleteKeyAsync(SecretKind kind, PasswordBox box, TextBlock status)
    {
        box.Clear();
        try
        {
            await host.Secrets.SetAsync(kind, null);
            status.Text = host.Secrets.Describe(kind).Describe();
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            status.Text = string.Format(Strings.DeleteFailed, ex.Message);
        }
        UpdateAiPanels();
    }

    private void OnSecretChanged(object? sender, SecretKind kind) => Dispatcher.BeginInvoke(() =>
    {
        UpdateApiKeyStatus();
        UpdateClaudeKeyStatus();
        UpdateAiPanels();
    });

    /// <summary>「接続を試す」。入力欄にキーがあればそのキーで（保存はしない）、なければ保存したキーで、モデルの情報を取る</summary>
    private async void OnCheckClaude(object sender, RoutedEventArgs e)
    {
        var typed = ClaudeKeyBox.Password.Trim();
        var model = settings.Current.ClaudeModel;
        ClaudeCheckButton.IsEnabled = false;
        ClaudeKeyStatus.Text = Strings.Settings_ClaudeConnecting;
        try
        {
            var client = typed.Length > 0
                ? new ClaudeClient(typed)
                : TextAiFactory.CreateClaude(host.Secrets, TimeSpan.FromSeconds(15)) ?? throw ClaudeException.MissingCredentials();
            await client.CheckAsync(model);
            ClaudeKeyStatus.Text = string.Format(typed.Length > 0 ? Strings.Settings_ClaudeConnectedUnsaved : Strings.Settings_ClaudeConnected, model)
                + (typed.Length > 0 ? "" : host.Secrets.Describe(SecretKind.ClaudeApiKey).Describe());
        }
        catch (TextAiException ex)
        {
            ClaudeKeyStatus.Text = ex.Message;
        }
        finally
        {
            ClaudeCheckButton.IsEnabled = true;
        }
    }

    // MARK: - API キーの保護（Windows Hello）

    private async Task UpdateHelloAsync()
    {
        var available = await host.Secrets.IsPresenceAvailableAsync();
        var on = host.Secrets.PreferredProtection == SecretProtection.WindowsHello;
        var wasLoading = loading;
        loading = true;
        HelloCheck.IsChecked = on;
        loading = wasLoading;
        HelloCheck.IsEnabled = available || on;
        HelloStatus.Text = available
            ? (on ? Strings.Settings_Hello_On : Strings.Settings_Hello_Off)
            : Strings.Settings_Hello_Unavailable;
    }

    private async void OnHelloChanged(object sender, RoutedEventArgs e)
    {
        if (loading) return;
        var want = HelloCheck.IsChecked == true ? SecretProtection.WindowsHello : SecretProtection.Dpapi;
        if (want == host.Secrets.PreferredProtection) return;
        HelloCheck.IsEnabled = false;
        HelloStatus.Text = want == SecretProtection.WindowsHello
            ? Strings.Settings_Hello_Enabling
            : Strings.Settings_Hello_Disabling;
        try
        {
            await host.Secrets.ChangeProtectionAsync(want);
        }
        catch (Exception ex) when (ex is SecretAccessException or IOException or UnauthorizedAccessException)
        {
            HelloStatus.Text = string.Format(Strings.Settings_Hello_SwitchFailed, ex.Message);
            await UpdateHelloAsync();
            HelloStatus.Text = string.Format(Strings.Settings_Hello_SwitchFailed, ex.Message);
            return;
        }
        await UpdateHelloAsync();
    }

    private void OnBrowseServiceAccount(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog { Filter = Strings.Settings_ServiceAccountFilter, Title = Strings.Settings_ServiceAccountDialogTitle };
        if (dialog.ShowDialog(this) != true) return;
        ServiceAccountPathBox.Text = dialog.FileName;
        OnServiceAccountPathChanged(sender, e);
    }

    private void OnServiceAccountPathChanged(object sender, RoutedEventArgs e)
    {
        Save(s => s.ServiceAccountPath = ServiceAccountPathBox.Text.Trim());
        UpdateAiPanels();
    }

    private void OnVertexLocationChanged(object sender, RoutedEventArgs e)
    {
        var location = VertexLocationBox.Text.Trim();
        Save(s => s.VertexLocation = location.Length == 0 ? "global" : location);
    }

    private void OnModelChanged(object sender, RoutedEventArgs e)
    {
        var model = ModelCombo.Text.Trim();
        if (model.Length > 0) Save(s => s.Model = model);
    }

    private void OnModelSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (ModelCombo.SelectedItem is string model) Save(s => s.Model = model);
    }

    private void OnSendAppNameChanged(object sender, RoutedEventArgs e) => Save(s => s.SendAppName = SendAppNameCheck.IsChecked == true);

    private void OnTrialRefine(object sender, RoutedEventArgs e) => _ = RunTrialAsync(DictationMode.Refine);

    // 要件: REQ-DIC-013
    /// <summary>翻訳の言語のチェックボックス（TranslationLanguages.All の順。Tag は言語）</summary>
    private readonly List<CheckBox> translationChecks = new();

    /// <summary>「…を試す」の翻訳のボタン（選んだ翻訳の言語ごと）</summary>
    private readonly List<Button> trialTranslateButtons = new();

    // 要件: REQ-DIC-013
    // 設計判断: DEC-DIC-150
    /// <summary>翻訳の言語のチェックボックスを、TranslationLanguages.All から作る（言語の一覧はここに書かない）</summary>
    private void BuildTranslationLanguageChecks(IReadOnlyList<TranslationLanguage> selected)
    {
        TranslationLanguagesPanel.Children.Clear();
        translationChecks.Clear();
        foreach (var language in TranslationLanguages.All)
        {
            var check = new CheckBox
            {
                Content = language.SettingsLabel(),
                Tag = language,
                IsChecked = selected.Contains(language),
                Margin = new Thickness(0, 4, 16, 0),
            };
            check.Checked += OnTranslationLanguageChanged;
            check.Unchecked += OnTranslationLanguageChanged;
            translationChecks.Add(check);
            TranslationLanguagesPanel.Children.Add(check);
        }
    }

    // 要件: REQ-DIC-013
    // 設計判断: DEC-DIC-027
    /// <summary>翻訳する言語のチェック。最後の 1 つは外せない</summary>
    private void OnTranslationLanguageChanged(object sender, RoutedEventArgs e)
    {
        if (loading) return;
        var picked = translationChecks.Where(c => c.IsChecked == true).Select(c => (TranslationLanguage)c.Tag).ToList();
        if (picked.Count == 0)
        {
            ((CheckBox)sender).IsChecked = true;
            return;
        }
        var languages = TranslationLanguages.Normalize(picked);
        Save(s => s.TranslationLanguages = languages);
        UpdateTranslationControls(languages);
    }

    /// <summary>最後の 1 つのチェックを押せなくし、「…を試す」の翻訳のボタンを選んだ言語の分だけ作る</summary>
    private void UpdateTranslationControls(IReadOnlyList<TranslationLanguage> languages)
    {
        var onlyOne = languages.Count == 1;
        foreach (var check in translationChecks)
        {
            check.IsEnabled = !(onlyOne && languages[0] == (TranslationLanguage)check.Tag);
        }
        foreach (var button in trialTranslateButtons) TrialButtonsPanel.Children.Remove(button);
        trialTranslateButtons.Clear();
        var index = TrialButtonsPanel.Children.IndexOf(TrialRefineButton) + 1;
        foreach (var language in languages)
        {
            var button = new Button { Content = TrialButtonLabel(language), Margin = new Thickness(0, 0, 8, 4) };
            button.Click += (_, _) => _ = RunTrialAsync(language.ToMode());
            trialTranslateButtons.Add(button);
            TrialButtonsPanel.Children.Insert(index++, button);
        }
    }

    /// <summary>「英訳を試す」「和訳を試す」「韓国語訳を試す」</summary>
    private static string TrialButtonLabel(TranslationLanguage language) =>
        language == TranslationLanguage.English ? Strings.Settings_TryEnglish
        : language == TranslationLanguage.Japanese ? Strings.Settings_TryJapanese
        : string.Format(Strings.Settings_TryOther, language.NameInUiLanguage());

    private void SetTrialButtonsEnabled(bool enabled)
    {
        TrialRefineButton.IsEnabled = enabled;
        foreach (var button in trialTranslateButtons) button.IsEnabled = enabled;
    }

    /// <summary>今の設定で 1 回整形（翻訳）してみる。音声入力と同じ流れ（辞書 → 音声入力の AI）を通す</summary>
    private async Task RunTrialAsync(DictationMode mode)
    {
        // 入力中の欄の値を先に保存する
        OnModelChanged(this, new RoutedEventArgs());
        OnServiceAccountPathChanged(this, new RoutedEventArgs());
        var s = settings.Current;
        s.RefineWithGemini = true;
        SetTrialButtonsEnabled(false);
        TrialStatus.Text = mode == DictationMode.Refine ? Strings.Settings_TrialRefining : Strings.Settings_TrialTranslating;
        var started = Stopwatch.StartNew();
        try
        {
            var processor = new DictationTextProcessor(x => host.CreateTextAi(x, TextAiUse.Dictation));
            var outcome = await processor.ProcessAsync(TrialInput.Text, mode, Strings.Settings_TrialAppName, s);
            TrialOutput.Text = outcome.Output;
            TrialStatus.Text = outcome.Warning is null
                ? string.Format(Strings.Settings_TrialDone, TextAiFactory.NameOf(s.DictationAi), s.DictationModel, started.Elapsed.TotalSeconds.ToString("0.0"))
                : outcome.Warning.ReplaceLineEndings(" ");
        }
        finally
        {
            SetTrialButtonsEnabled(true);
        }
    }

    // MARK: - 会議

    private void SetMeetingHotKey(HotKeyCombo combo, bool highlight)
    {
        var problem = combo.Validate() ?? ConflictingShortcut(combo, highlight ? "highlight" : "meeting");
        if (problem is not null)
        {
            MeetingHotKeyError.Text = problem;
            MeetingHotKeyError.Visibility = Visibility.Visible;
            return;
        }
        MeetingHotKeyError.Visibility = Visibility.Collapsed;
        Save(x =>
        {
            if (highlight) x.HighlightHotKey = combo;
            else x.MeetingHotKey = combo;
        });
        (highlight ? HighlightHotKeyBox : MeetingHotKeyBox).Combo = combo;
    }

    private void OnResetMeetingHotKey(object sender, RoutedEventArgs e) => SetMeetingHotKey(HotKeyCombo.DefaultMeeting, highlight: false);

    private void OnResetHighlightHotKey(object sender, RoutedEventArgs e) => SetMeetingHotKey(HotKeyCombo.DefaultHighlight, highlight: true);

    private void OnHighlightHotKeyEnabledChanged(object sender, RoutedEventArgs e) => Save(s => s.HighlightHotKeyEnabled = HighlightHotKeyCheck.IsChecked == true);

    private void OnMeetingEngineChanged(object sender, SelectionChangedEventArgs e)
    {
        if (MeetingEngineCombo.SelectedItem is not ComboBoxItem { Tag: string tag } || !Enum.TryParse<TranscriptionEngine>(tag, out var engine)) return;
        Save(s => s.MeetingEngine = engine);
        UpdateMeetingEngineNote(engine);
        UpdateAiPanels();
        if (!loading && engine == TranscriptionEngine.Whisper) StartWhisperDownloadIfNeeded();
    }

    private void UpdateMeetingEngineNote(TranscriptionEngine engine)
    {
        if (engine == TranscriptionEngine.Gemini)
        {
            MeetingEngineNote.Text = Strings.Settings_MeetingEngine_GeminiNote;
            return;
        }
        var model = WhisperModelCatalog.Find(settings.Current.WhisperModel);
        var ready = model is not null && host.WhisperModels.IsDownloaded(model);
        MeetingEngineNote.Text = string.Format(Strings.Settings_MeetingEngine_WhisperNote, model?.Id) + (ready ? "" : Strings.Settings_MeetingEngine_WhisperMissing);
    }

    private void OnDiarizeChanged(object sender, RoutedEventArgs e) => Save(s => s.DiarizeOthers = DiarizeCheck.IsChecked == true);

    private void OnMakeMinutesChanged(object sender, RoutedEventArgs e) => Save(s => s.MakeMeetingMinutes = MakeMinutesCheck.IsChecked == true);

    private void OnMinutesModelChanged(object sender, RoutedEventArgs e)
    {
        var model = MinutesModelCombo.Text.Trim();
        if (model.Length > 0) Save(s => s.MeetingMinutesModel = model);
        UpdateAiPanels();
    }

    private void OnMinutesModelSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (MinutesModelCombo.SelectedItem is string model) Save(s => s.MeetingMinutesModel = model);
        UpdateAiPanels();
    }

    private void OnKeepAudioChanged(object sender, RoutedEventArgs e) => Save(s => s.KeepMeetingAudio = KeepAudioCheck.IsChecked == true);

    private void OnBrowseMeetingsFolder(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog { Title = Strings.Settings_MeetingsFolderDialogTitle, InitialDirectory = MeetingsDirBox.Text };
        if (dialog.ShowDialog(this) != true) return;
        Save(s => s.MeetingsDirectory = dialog.FolderName);
        MeetingsDirBox.Text = dialog.FolderName;
    }

    private void OnResetMeetingsFolder(object sender, RoutedEventArgs e)
    {
        Save(s => s.MeetingsDirectory = "");
        MeetingsDirBox.Text = MeetingStore.DefaultBaseDirectory;
    }

    private void OnOpenMeetingsFolder(object sender, RoutedEventArgs e) => OpenFolder(MeetingsDirBox.Text);

    // MARK: - 辞書・ルール

    private void OnDictionaryChanged(object sender, TextChangedEventArgs e)
    {
        Save(s => s.DictionaryText = DictionaryBox.Text);
        UpdateDictionaryIssues();
        OnDictionaryTrialChanged(sender, e);
    }

    private void UpdateDictionaryIssues()
    {
        var issues = new UserDictionary(DictionaryBox.Text).Issues;
        DictionaryIssues.Visibility = issues.Count == 0 ? Visibility.Collapsed : Visibility.Visible;
        DictionaryIssues.Text = string.Join("\n", issues.OrderBy(p => p.Key).Select(p => string.Format(Strings.Settings_DictionaryLineIssue, p.Key + 1, p.Value.ReplaceLineEndings(" ／ "))));
    }

    private void OnDictionaryTrialChanged(object sender, TextChangedEventArgs e)
    {
        if (DictionaryTrialBox is null || DictionaryTrialResult is null) return;
        var input = DictionaryTrialBox.Text;
        if (input.Length == 0)
        {
            DictionaryTrialResult.Text = "";
            return;
        }
        var (text, replacements) = new UserDictionary(DictionaryBox.Text).ApplyWithLog(input);
        DictionaryTrialResult.Text = replacements.Count == 0
            ? Strings.Settings_NoReplacements
            : string.Format(Strings.Settings_ReplacementResult, text, string.Join(Strings.ListSeparator, replacements.Select(r => $"{r.Matched} → {r.Target}")));
    }

    private void OnExtraInstructionsChanged(object sender, TextChangedEventArgs e) => Save(s => s.ExtraInstructions = ExtraInstructionsBox.Text);

    private void OnCloseClick(object sender, RoutedEventArgs e) => Close();
}
