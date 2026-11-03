using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using Hanasu.Core.Dictation;
using Hanasu.Core.Gemini;
using Hanasu.Core.Settings;
using Hanasu.Core.Text;
using Hanasu.Core.Transcription;
using Hanasu.Whisper;
using Hanasu.Windows.Services;
using Microsoft.Win32;

namespace Hanasu.Windows.Views;

/// <summary>
/// 設定画面（一般 / Gemini / 辞書・ルール）。変更はその場で SettingsService に書き、すぐ保存する（Mac 版と同じ）。
/// </summary>
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
        LoadValues();
        loading = false;

        DictationHotKeyBox.Recorded += (_, combo) => SetHotKey(combo, translate: false);
        TranslateHotKeyBox.Recorded += (_, combo) => SetHotKey(combo, translate: true);
        DictationHotKeyBox.RecordingChanged += (_, recording) => host.SuspendHotKeys(recording);
        TranslateHotKeyBox.RecordingChanged += (_, recording) => host.SuspendHotKeys(recording);
        host.WhisperModels.StateChanged += OnWhisperStateChanged;
        Closed += (_, _) =>
        {
            host.WhisperModels.StateChanged -= OnWhisperStateChanged;
            host.SuspendHotKeys(false);
        };
    }

    private void LoadValues()
    {
        var s = settings.Current;
        DictationHotKeyBox.Combo = s.HotKey;
        TranslateHotKeyBox.Combo = s.TranslateHotKey;
        ToggleModeRadio.IsChecked = s.RecordingMode == RecordingMode.Toggle;
        PushToTalkRadio.IsChecked = s.RecordingMode == RecordingMode.PushToTalk;
        EngineCombo.SelectedItem = EngineCombo.Items.OfType<ComboBoxItem>().First(i => (string)i.Tag == s.Engine.ToString());

        WhisperModelCombo.ItemsSource = WhisperModelCatalog.Models;
        WhisperModelCombo.DisplayMemberPath = nameof(WhisperModelInfo.Label);
        WhisperModelCombo.SelectedItem = WhisperModelCatalog.Find(s.WhisperModel);
        WhisperFolderNote.Text = $"保存先: {host.WhisperModels.Directory}";

        var microphones = new List<MicrophoneInfo> { new("", "Windows の既定のマイク") };
        microphones.AddRange(WasapiRecorder.ListMicrophones());
        if (s.MicrophoneDeviceId.Length > 0 && microphones.All(m => m.Id != s.MicrophoneDeviceId))
        {
            microphones.Add(new MicrophoneInfo(s.MicrophoneDeviceId, "（前に選んだマイク・今はつながっていません）"));
        }
        MicrophoneCombo.ItemsSource = microphones;
        MicrophoneCombo.DisplayMemberPath = nameof(MicrophoneInfo.Name);
        MicrophoneCombo.SelectedItem = microphones.First(m => m.Id == s.MicrophoneDeviceId);
        PlaySoundsCheck.IsChecked = s.PlaySounds;

        RefineCheck.IsChecked = s.RefineWithGemini;
        ApiKeyRadio.IsChecked = s.AuthMode == GeminiAuthMode.ApiKey;
        ServiceAccountRadio.IsChecked = s.AuthMode == GeminiAuthMode.ServiceAccount;
        ServiceAccountPathBox.Text = s.ServiceAccountPath;
        VertexLocationBox.Text = s.VertexLocation;
        ModelCombo.ItemsSource = AppSettings.SuggestedModels;
        ModelCombo.Text = s.Model;
        SendAppNameCheck.IsChecked = s.SendAppName;

        DictionaryBox.Text = s.DictionaryText;
        ExtraInstructionsBox.Text = s.ExtraInstructions;

        UpdateEnginePanels(s.Engine);
        UpdateAuthPanels(s.AuthMode);
        UpdateApiKeyStatus();
        UpdateWhisperControls();
        UpdateDictionaryIssues();
    }

    private void Save(Action<AppSettings> mutate)
    {
        if (loading) return;
        var error = settings.Update(mutate);
        SaveStatus.Text = error is null ? "保存しました" : $"保存できませんでした: {error.Message}";
    }

    // MARK: - 一般

    private void SetHotKey(HotKeyCombo combo, bool translate)
    {
        var problem = combo.Validate();
        var other = translate ? settings.Current.HotKey : settings.Current.TranslateHotKey;
        if (problem is null && combo == other) problem = "もう一方のショートカットと同じです";
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
            ? "Windows 標準のエンジンは、Windows の既定のマイクを使います（Windows の設定 → システム → サウンド で変えられます）。"
            : "Whisper と Gemini は、ここで選んだマイクで録音します（16 kHz・モノラルに変換）。";
    }

    private void OnMicrophoneChanged(object sender, SelectionChangedEventArgs e)
    {
        if (MicrophoneCombo.SelectedItem is MicrophoneInfo mic) Save(s => s.MicrophoneDeviceId = mic.Id);
    }

    private void OnPlaySoundsChanged(object sender, RoutedEventArgs e) => Save(s => s.PlaySounds = PlaySoundsCheck.IsChecked == true);

    private void OnOpenSpeechPrivacy(object sender, RoutedEventArgs e) => Shell.Open("ms-settings:privacy-speech");

    private void OnOpenLanguageSettings(object sender, RoutedEventArgs e) => Shell.Open("ms-settings:regionlanguage");

    private void OnOpenLogs(object sender, RoutedEventArgs e) => OpenFolder(AppLog.Directory);

    private void OnOpenSettingsFolder(object sender, RoutedEventArgs e) => OpenFolder(HanasuPaths.SettingsDirectory);

    private void OnOpenModelsFolder(object sender, RoutedEventArgs e) => OpenFolder(host.WhisperModels.Directory);

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
        if (MessageBox.Show(this, $"Whisper のモデル {model.Id}（{model.SizeLabel}）を削除しますか？", "Hanasu",
                MessageBoxButton.OKCancel, MessageBoxImage.Question) != MessageBoxResult.OK) return;
        try
        {
            // 読み込み中のモデルはファイルを開いているので、先に手放す
            WhisperBatchTranscriber.ReleaseCachedModel();
            host.WhisperModels.Delete(model);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            WhisperStatus.Text = $"削除できませんでした: {ex.Message}";
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
        WhisperStatus.Text = state.Status switch
        {
            WhisperModelStatus.Downloading => $"ダウンロード中… {state.Progress:P0}",
            WhisperModelStatus.Downloaded => "ダウンロード済み",
            WhisperModelStatus.Failed => $"失敗しました: {state.Error}",
            _ => "まだダウンロードしていません",
        };
    }

    // MARK: - Gemini

    private void OnRefineChanged(object sender, RoutedEventArgs e) => Save(s => s.RefineWithGemini = RefineCheck.IsChecked == true);

    private void OnAuthModeChanged(object sender, RoutedEventArgs e)
    {
        var mode = ServiceAccountRadio.IsChecked == true ? GeminiAuthMode.ServiceAccount : GeminiAuthMode.ApiKey;
        Save(s => s.AuthMode = mode);
        UpdateAuthPanels(mode);
    }

    private void UpdateAuthPanels(GeminiAuthMode mode)
    {
        ApiKeyPanel.Visibility = mode == GeminiAuthMode.ApiKey ? Visibility.Visible : Visibility.Collapsed;
        ServiceAccountPanel.Visibility = mode == GeminiAuthMode.ServiceAccount ? Visibility.Visible : Visibility.Collapsed;
    }

    private void OnSaveApiKey(object sender, RoutedEventArgs e)
    {
        if (ApiKeyBox.Password.Trim().Length == 0)
        {
            ApiKeyStatus.Text = "API キーを入力してください";
            return;
        }
        var error = settings.SetApiKey(ApiKeyBox.Password);
        ApiKeyBox.Clear();
        UpdateApiKeyStatus(error);
    }

    private void OnDeleteApiKey(object sender, RoutedEventArgs e)
    {
        var error = settings.SetApiKey(null);
        ApiKeyBox.Clear();
        UpdateApiKeyStatus(error);
    }

    private void UpdateApiKeyStatus(Exception? error = null)
    {
        if (error is not null)
        {
            ApiKeyStatus.Text = $"保存できませんでした: {error.Message}";
            return;
        }
        var key = settings.LoadApiKey();
        ApiKeyStatus.Text = key is null
            ? (settings.Current.ProtectedApiKey.Length > 0 ? "保存したキーを読めません（別のユーザーで保存した可能性があります）。もう一度保存してください。" : "未設定")
            : $"保存済み（…{key[^Math.Min(4, key.Length)..]}）";
    }

    private void OnBrowseServiceAccount(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog { Filter = "サービスアカウントの鍵 (*.json)|*.json|すべてのファイル (*.*)|*.*", Title = "サービスアカウントの鍵（JSON）を選ぶ" };
        if (dialog.ShowDialog(this) != true) return;
        ServiceAccountPathBox.Text = dialog.FileName;
        OnServiceAccountPathChanged(sender, e);
    }

    private void OnServiceAccountPathChanged(object sender, RoutedEventArgs e) => Save(s => s.ServiceAccountPath = ServiceAccountPathBox.Text.Trim());

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

    private void OnTrialTranslate(object sender, RoutedEventArgs e) => _ = RunTrialAsync(DictationMode.TranslateToEnglish);

    /// <summary>今の設定で 1 回整形（英訳）してみる。音声入力と同じ流れ（辞書 → Gemini）を通す</summary>
    private async Task RunTrialAsync(DictationMode mode)
    {
        // 入力中の欄の値を先に保存する
        OnModelChanged(this, new RoutedEventArgs());
        OnServiceAccountPathChanged(this, new RoutedEventArgs());
        var s = settings.Current;
        s.RefineWithGemini = true;
        TrialRefineButton.IsEnabled = TrialTranslateButton.IsEnabled = false;
        TrialStatus.Text = mode == DictationMode.Refine ? "整えています…" : "翻訳しています…";
        var started = Stopwatch.StartNew();
        try
        {
            var processor = new DictationTextProcessor(x => host.CreateGeminiClient(x));
            var outcome = await processor.ProcessAsync(TrialInput.Text, mode, "Hanasu の設定画面", s);
            TrialOutput.Text = outcome.Output;
            TrialStatus.Text = outcome.Warning is null
                ? $"{s.Model} で {started.Elapsed.TotalSeconds:0.0} 秒"
                : outcome.Warning.ReplaceLineEndings(" ");
        }
        finally
        {
            TrialRefineButton.IsEnabled = TrialTranslateButton.IsEnabled = true;
        }
    }

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
        DictionaryIssues.Text = string.Join("\n", issues.OrderBy(p => p.Key).Select(p => $"{p.Key + 1} 行目: {p.Value.ReplaceLineEndings(" ／ ")}"));
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
            ? "置き換えはありません"
            : $"→ {text}（{string.Join("、", replacements.Select(r => $"{r.Matched} → {r.Target}"))}）";
    }

    private void OnExtraInstructionsChanged(object sender, TextChangedEventArgs e) => Save(s => s.ExtraInstructions = ExtraInstructionsBox.Text);

    private void OnCloseClick(object sender, RoutedEventArgs e) => Close();
}
