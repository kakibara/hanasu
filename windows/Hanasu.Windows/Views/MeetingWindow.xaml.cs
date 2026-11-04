using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Threading;
using Hanasu.Core.Meetings;
using Hanasu.Core.Settings;
using Hanasu.Windows.Services;

namespace Hanasu.Windows.Views;

/// <summary>
/// 会議ノート（Mac 版の MeetingWindow にあたる）。左に記録中の表示・会議の一覧・記録の開始、右に選んだ会議の議事録・文字起こし・メモ。
/// 話者名の変更、議事録の作り直し（型の選び直し）、Markdown のコピー、エクスプローラーで開く ができる。
/// 記録中は経過時間・停止ボタン・メモ欄・「ここ重要」ボタンを出す。
/// </summary>
public partial class MeetingWindow : Window
{
    /// <summary>一覧の 1 行</summary>
    private sealed record MeetingRow(Meeting Meeting, string Title, string Detail);

    private readonly AppHost host;
    private readonly MeetingController meetings;
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromMilliseconds(250) };
    private Meeting? selected;
    private bool loading;
    /// <summary>記録中のメモ欄を書き始めた時刻（メモの時刻はこれにする）</summary>
    private double? noteStartedAt;

    internal MeetingWindow(AppHost host)
    {
        this.host = host;
        meetings = host.Meetings;
        InitializeComponent();
        loading = true;
        LoadDevices();
        foreach (var t in MinutesTemplates.All)
        {
            NextTemplateCombo.Items.Add(new ComboBoxItem { Content = $"{t.Title()} — {t.Summary()}", Tag = t });
            TemplateCombo.Items.Add(new ComboBoxItem { Content = t.Title(), Tag = t });
        }
        var s = host.Settings.Current;
        NextTemplateCombo.SelectedItem = NextTemplateCombo.Items.OfType<ComboBoxItem>()
            .First(i => (MinutesTemplate)i.Tag == (MinutesTemplates.FromRawValue(s.MeetingMinutesTemplate) ?? MinutesTemplate.Auto));
        CustomPromptBox.Text = s.MeetingCustomMinutesPrompt;
        loading = false;
        UpdateNextTemplate();

        meetings.StateChanged += OnStateChanged;
        meetings.MeetingChanged += OnMeetingChanged;
        meetings.ProgressChanged += OnProgressChanged;
        timer.Tick += (_, _) => UpdateLive();
        Closed += (_, _) =>
        {
            timer.Stop();
            meetings.StateChanged -= OnStateChanged;
            meetings.MeetingChanged -= OnMeetingChanged;
            meetings.ProgressChanged -= OnProgressChanged;
        };
        ReloadList(meetings.Current?.Id);
        UpdateState();
    }

    // MARK: - 一覧

    private void ReloadList(string? selectId = null)
    {
        selectId ??= selected?.Id;
        var store = meetings.Store(host.Settings.Current);
        var all = store.LoadAll();
        // 記録中・処理中の会議はメモリ上のものを使う（ファイルより新しい）
        if (meetings.Current is { } current)
        {
            all.RemoveAll(m => m.Id == current.Id);
            all.Insert(0, current);
        }
        var rows = all.Select(m => new MeetingRow(m, m.Title, Detail(m))).ToList();
        loading = true;
        MeetingList.ItemsSource = rows;
        MeetingList.SelectedItem = rows.FirstOrDefault(r => r.Meeting.Id == selectId);
        loading = false;
        if (MeetingList.SelectedItem is MeetingRow row) Show(row.Meeting);
        else if (selected is not null && rows.All(r => r.Meeting.Id != selected.Id)) Show(null);
    }

    private static string Detail(Meeting m)
    {
        var status = m.Status switch
        {
            MeetingStatus.Recording => "● 記録中",
            MeetingStatus.Processing => "処理中",
            MeetingStatus.Failed => "失敗",
            _ => m.ErrorMessage is null ? "" : "注意あり",
        };
        return $"{Meeting.FormatDate(m.StartedAt)}・{Meeting.Clock(m.Duration)}{(status.Length > 0 ? "・" + status : "")}";
    }

    private void OnMeetingSelected(object sender, SelectionChangedEventArgs e)
    {
        if (loading) return;
        Show((MeetingList.SelectedItem as MeetingRow)?.Meeting);
    }

    // MARK: - 選んだ会議

    private bool IsLive(Meeting? m) => m is not null && meetings.Current?.Id == m.Id;

    private void Show(Meeting? m)
    {
        selected = m;
        EmptyText.Visibility = m is null ? Visibility.Visible : Visibility.Collapsed;
        DetailPanel.Visibility = m is null ? Visibility.Collapsed : Visibility.Visible;
        if (m is null) return;
        loading = true;
        TitleBox.Text = m.Title;
        MeetingInfo.Text = $"{Meeting.FormatDate(m.StartedAt)}・{Meeting.Clock(m.Duration)}・保存先: {Path.Combine(meetings.Store(host.Settings.Current).BaseDirectory, m.Id)}";
        TemplateCombo.SelectedItem = TemplateCombo.Items.OfType<ComboBoxItem>().First(i => (MinutesTemplate)i.Tag == m.Template);
        loading = false;
        ErrorText.Text = m.ErrorMessage ?? "";
        ErrorText.Visibility = m.ErrorMessage is null ? Visibility.Collapsed : Visibility.Visible;
        MinutesBox.Text = m.Minutes ?? (m.Status switch
        {
            MeetingStatus.Recording => "記録を止めると、文字起こしのあとに議事録を作ります。",
            MeetingStatus.Processing => "処理中です…",
            _ => "議事録はまだありません。「議事録を作り直す」で作れます（設定 → AI の「会議」の AI の設定が要ります）。",
        });
        TranscriptBox.Text = m.Utterances.Count == 0
            ? (IsLive(m) ? "文字起こしは、記録を止めたあとに行います。" : "文字起こしはありません。")
            : m.TranscriptMarkdown();
        if (!NotesBox.IsKeyboardFocused) NotesBox.Text = m.NotesText;
        HighlightsBox.Text = m.HighlightContextText();
        BuildSpeakerEditors(m);

        var live = IsLive(m);
        var busy = live || m.Status is MeetingStatus.Recording or MeetingStatus.Processing;
        RecordingPanel.Visibility = live && meetings.State == MeetingState.Recording ? Visibility.Visible : Visibility.Collapsed;
        RegenerateButton.IsEnabled = TemplateCombo.IsEnabled = SaveNotesAndRegenerateButton.IsEnabled = !busy && m.Utterances.Count > 0;
        RecordingNote.Text = $"文字起こしは、記録を止めたあとに {(host.Settings.Current.MeetingEngine == TranscriptionEngine.Gemini ? "Gemini" : "Whisper")} で行います（会議中の PC の負担を減らすため）。";
        UpdateLiveNotes();
    }

    private void BuildSpeakerEditors(Meeting m)
    {
        SpeakersPanel.Children.Clear();
        var speakers = m.Speakers;
        SpeakersLabel.Visibility = speakers.Count == 0 ? Visibility.Collapsed : Visibility.Visible;
        foreach (var speaker in speakers)
        {
            var defaultName = new Meeting().DisplayName(speaker);
            // 要件: REQ-MTG-027
            // 設計判断: DEC-MTG-069
            var inferred = m.IsInferredName(speaker);
            var box = new TextBox
            {
                Width = 120,
                Padding = new Thickness(4, 2, 4, 2),
                Text = m.DisplayName(speaker),
                ToolTip = inferred ? $"{defaultName} の名前（会話から推測しました。違っていたら直してください）" : $"{defaultName} の名前",
            };
            box.LostFocus += (_, _) => RenameSpeaker(m, speaker, box.Text.Trim(), defaultName);
            box.KeyDown += (_, e) =>
            {
                if (e.Key == Key.Enter) RenameSpeaker(m, speaker, box.Text.Trim(), defaultName);
            };
            var panel = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 2, 12, 2) };
            panel.Children.Add(new TextBlock { Text = defaultName + ":", VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 4, 0), FontSize = 12 });
            panel.Children.Add(box);
            if (inferred)
            {
                panel.Children.Add(new TextBlock { Text = "推測", Foreground = System.Windows.Media.Brushes.DarkOrange, FontSize = 11, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(4, 0, 0, 0) });
            }
            SpeakersPanel.Children.Add(panel);
        }
    }

    private void RenameSpeaker(Meeting m, string speaker, string name, string defaultName)
    {
        if (!m.RenameSpeaker(speaker, name == defaultName ? "" : name)) return;
        SaveSelected(m, "話者名を保存しました");
        TranscriptBox.Text = m.TranscriptMarkdown();
        HighlightsBox.Text = m.HighlightContextText();
        // 推測の印を外したので、欄を作り直す
        BuildSpeakerEditors(m);
    }

    private void OnTitleChanged(object sender, RoutedEventArgs e)
    {
        if (selected is not { } m || loading) return;
        var title = TitleBox.Text.Trim();
        if (title.Length == 0 || title == m.Title) return;
        m.Title = title;
        SaveSelected(m, "題名を保存しました");
    }

    private void SaveSelected(Meeting m, string message)
    {
        try
        {
            meetings.Save(m);
            ActionStatus.Text = message;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            ActionStatus.Text = $"保存できませんでした: {ex.Message}";
        }
    }

    // MARK: - 議事録

    private void OnRegenerateClick(object sender, RoutedEventArgs e)
    {
        if (selected is { } m) _ = RegenerateAsync(m, null);
    }

    private void OnTemplateChanged(object sender, SelectionChangedEventArgs e)
    {
        if (loading || selected is not { } m || TemplateCombo.SelectedItem is not ComboBoxItem { Tag: MinutesTemplate t } || t == m.Template) return;
        if (MessageBox.Show(this, $"議事録の型を「{t.Title()}」にして、議事録を作り直しますか？", "Hanasu", MessageBoxButton.OKCancel, MessageBoxImage.Question) != MessageBoxResult.OK)
        {
            Show(m);
            return;
        }
        _ = RegenerateAsync(m, t);
    }

    private async Task RegenerateAsync(Meeting m, MinutesTemplate? template)
    {
        RegenerateButton.IsEnabled = TemplateCombo.IsEnabled = SaveNotesAndRegenerateButton.IsEnabled = false;
        ActionStatus.Text = $"{Core.Ai.TextAiFactory.NameOf(host.Settings.Current.MeetingAi)} で議事録を作っています…";
        var started = Stopwatch.StartNew();
        try
        {
            await meetings.RegenerateMinutesAsync(m, template);
            ActionStatus.Text = $"議事録を作り直しました（{started.Elapsed.TotalSeconds:0} 秒）";
            Tabs.SelectedIndex = 0;
        }
        catch (Exception ex) when (ex is Core.Ai.TextAiException or Core.Gemini.ServiceAccountException or IOException)
        {
            // 失敗したときは、型も議事録も元のまま
            ActionStatus.Text = $"議事録を作れませんでした: {ex.Message}";
        }
        finally
        {
            Show(m);
        }
    }

    private void OnCopyClick(object sender, RoutedEventArgs e)
    {
        if (selected is not { } m) return;
        var (text, label) = Tabs.SelectedIndex switch
        {
            1 => (m.TranscriptMarkdown(), "文字起こし"),
            2 => (m.NotesMarkdown(), "メモ"),
            _ => (m.Minutes ?? "", "議事録"),
        };
        if (text.Length == 0)
        {
            ActionStatus.Text = $"{label}がありません";
            return;
        }
        try
        {
            Clipboard.SetText(text);
            ActionStatus.Text = $"{label}を Markdown でコピーしました";
        }
        catch (System.Runtime.InteropServices.ExternalException ex)
        {
            ActionStatus.Text = $"コピーできませんでした: {ex.Message}";
        }
    }

    private void OnOpenFolderClick(object sender, RoutedEventArgs e)
    {
        if (selected is not { } m) return;
        var dir = Path.Combine(meetings.Store(host.Settings.Current).BaseDirectory, m.Id);
        if (!Directory.Exists(dir)) return;
        Process.Start(new ProcessStartInfo("explorer.exe", $"\"{dir}\"") { UseShellExecute = true });
    }

    // MARK: - メモ（記録のあと）

    private void OnSaveNotesClick(object sender, RoutedEventArgs e) => SaveNotes(regenerate: false);

    private void OnSaveNotesAndRegenerateClick(object sender, RoutedEventArgs e) => SaveNotes(regenerate: true);

    private void SaveNotes(bool regenerate)
    {
        if (selected is not { } m) return;
        if (IsLive(m))
        {
            ActionStatus.Text = "記録中は、上のメモ欄から足してください（このタブでの編集は記録のあとにできます）";
            return;
        }
        var notes = MeetingNote.Parse(NotesBox.Text);
        m.Notes = notes.Count == 0 ? null : notes;
        SaveSelected(m, "メモを保存しました");
        if (regenerate) _ = RegenerateAsync(m, null);
        else Show(m);
    }

    // MARK: - 記録中

    private void OnStartClick(object sender, RoutedEventArgs e) => _ = meetings.StartAsync();

    private void OnStopClick(object sender, RoutedEventArgs e) => _ = meetings.StopAsync();

    private void OnNoteInputChanged(object sender, TextChangedEventArgs e)
    {
        // 書き始めた時刻を覚える（聞いてから書き終えるまでの遅れで、メモの時刻が後ろにずれないように）
        if (NoteInput.Text.Length == 0) noteStartedAt = null;
        else noteStartedAt ??= meetings.ElapsedSeconds;
    }

    private void OnNoteInputKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Enter || e.IsRepeat) return;
        e.Handled = true;
        AddNote();
    }

    private void OnAddNoteClick(object sender, RoutedEventArgs e) => AddNote();

    private void AddNote()
    {
        meetings.AddNote(NoteInput.Text, noteStartedAt);
        NoteInput.Clear();
        noteStartedAt = null;
    }

    private void OnHighlightClick(object sender, RoutedEventArgs e)
    {
        meetings.AddHighlight(NoteInput.Text);
        NoteInput.Clear();
        noteStartedAt = null;
    }

    private void OnUndoHighlightClick(object sender, RoutedEventArgs e)
    {
        if (meetings.UndoableHighlight is { } note) meetings.UndoHighlight(note.Id);
        UpdateUndoHighlight();
    }

    /// <summary>付けてから 10 秒以内の印があれば「取り消す」と残りの秒数を出す（タイマーで毎回更新する）</summary>
    private void UpdateUndoHighlight()
    {
        if (meetings.UndoableHighlight is { Time: { } time })
        {
            var remaining = (int)Math.Ceiling(Meeting.HighlightUndoSeconds - (meetings.ElapsedSeconds - time));
            UndoHighlightButton.Content = $"★ を取り消す（あと {Math.Max(1, remaining)} 秒）";
            UndoHighlightButton.Visibility = Visibility.Visible;
        }
        else
        {
            UndoHighlightButton.Visibility = Visibility.Collapsed;
        }
    }

    private void UpdateLiveNotes()
    {
        LiveNotes.Text = IsLive(selected) ? string.Join("\n", selected!.AllNotes.TakeLast(8).Select(n => n.Line)) : "";
    }

    private void UpdateLive()
    {
        if (meetings.State == MeetingState.Recording)
        {
            LiveElapsed.Text = Meeting.Clock(meetings.ElapsedSeconds);
            MicLevel.Value = meetings.MicLevel;
            OutputLevel.Value = meetings.LoopbackLevel;
        }
        UpdateUndoHighlight();
    }

    // MARK: - 状態

    private void OnStateChanged(object? sender, MeetingState state) => Dispatcher.BeginInvoke(UpdateState);

    private void OnProgressChanged(object? sender, string message) => Dispatcher.BeginInvoke(() => LiveProgress.Text = message);

    private void OnMeetingChanged(object? sender, Meeting m) => Dispatcher.BeginInvoke(() =>
    {
        if (selected?.Id == m.Id && IsLive(m))
        {
            UpdateLiveNotes();
            return;
        }
        ReloadList(m.Id == meetings.Current?.Id || selected is null ? m.Id : null);
    });

    private void UpdateState()
    {
        var state = meetings.State;
        LiveBox.Visibility = state is MeetingState.Recording or MeetingState.Processing or MeetingState.Starting ? Visibility.Visible : Visibility.Collapsed;
        LiveTitle.Text = state switch
        {
            MeetingState.Starting => "記録を始めています…",
            MeetingState.Processing => "記録のあとの処理中",
            _ => "● 記録中",
        };
        StopButton.Visibility = state == MeetingState.Recording ? Visibility.Visible : Visibility.Collapsed;
        LiveProgress.Text = state == MeetingState.Processing ? meetings.ProgressMessage ?? "" : $"{host.Settings.Current.MeetingHotKey.DisplayString} でも止められます";
        StartButton.IsEnabled = state == MeetingState.Idle;
        MicCombo.IsEnabled = OutputCombo.IsEnabled = NextTemplateCombo.IsEnabled = CustomPromptBox.IsEnabled = state == MeetingState.Idle;
        StartNote.Text = state == MeetingState.Idle
            ? $"{host.Settings.Current.MeetingHotKey.DisplayString} でも始められます。録音することを相手に伝えてから始めてください。"
            : "";
        if (state == MeetingState.Recording) timer.Start();
        else timer.Stop();
        UpdateUndoHighlight();
        UpdateLive();
        ReloadList(meetings.Current?.Id);
    }

    // MARK: - 録音する機器と型（記録を始める前に選ぶ）

    private void LoadDevices()
    {
        var s = host.Settings.Current;
        var mics = new List<MicrophoneInfo> { new("", "Windows の既定のマイク") };
        mics.AddRange(WasapiRecorder.ListMicrophones());
        if (s.MeetingMicrophoneDeviceId.Length > 0 && mics.All(m => m.Id != s.MeetingMicrophoneDeviceId)) mics.Add(new(s.MeetingMicrophoneDeviceId, "（前に選んだマイク・今はつながっていません）"));
        MicCombo.ItemsSource = mics;
        MicCombo.DisplayMemberPath = nameof(MicrophoneInfo.Name);
        MicCombo.SelectedItem = mics.First(m => m.Id == s.MeetingMicrophoneDeviceId);

        var outputs = new List<OutputDeviceInfo> { new("", "Windows の既定の出力") };
        outputs.AddRange(MeetingChannelRecorder.ListOutputs());
        if (s.MeetingOutputDeviceId.Length > 0 && outputs.All(o => o.Id != s.MeetingOutputDeviceId)) outputs.Add(new(s.MeetingOutputDeviceId, "（前に選んだ出力・今はつながっていません）"));
        OutputCombo.ItemsSource = outputs;
        OutputCombo.DisplayMemberPath = nameof(OutputDeviceInfo.Name);
        OutputCombo.SelectedItem = outputs.First(o => o.Id == s.MeetingOutputDeviceId);
    }

    private void OnMicChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!loading && MicCombo.SelectedItem is MicrophoneInfo mic) host.Settings.Update(s => s.MeetingMicrophoneDeviceId = mic.Id);
    }

    private void OnOutputChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!loading && OutputCombo.SelectedItem is OutputDeviceInfo output) host.Settings.Update(s => s.MeetingOutputDeviceId = output.Id);
    }

    private void OnNextTemplateChanged(object sender, SelectionChangedEventArgs e)
    {
        if (loading || NextTemplateCombo.SelectedItem is not ComboBoxItem { Tag: MinutesTemplate t }) return;
        host.Settings.Update(s => s.MeetingMinutesTemplate = t.RawValue());
        UpdateNextTemplate();
    }

    private void UpdateNextTemplate()
    {
        var custom = NextTemplateCombo.SelectedItem is ComboBoxItem { Tag: MinutesTemplate.Custom };
        CustomPromptBox.Visibility = custom ? Visibility.Visible : Visibility.Collapsed;
    }

    private void OnCustomPromptChanged(object sender, RoutedEventArgs e)
    {
        var text = CustomPromptBox.Text;
        host.Settings.Update(s => s.MeetingCustomMinutesPrompt = text);
    }
}
