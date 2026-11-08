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
/// 記録中は経過時間・停止ボタン・メモ欄・「ここ重要」ボタン・「オフレコ」ボタンを出す。
/// 文字起こしのタブは発言ごとの一覧で、議事録に使う発言を選べる（DEC-MTG-112）。
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
    /// <summary>文字起こしの一覧に出している会議の ID（同じ会議を出し直すときは、スクロールの位置と選んだ発言を保つ）</summary>
    private string? transcriptShownId;
    /// <summary>最後にチェックボックスを押した発言のまとまりの、先頭の発言の ID（Shift で、ここからまとめて切り替える）</summary>
    private string? lastCheckedId;

    internal MeetingWindow(AppHost host)
    {
        this.host = host;
        meetings = host.Meetings;
        InitializeComponent();
        WindowFit.FitToMouseScreen(this);
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
            reloadGeneration++; // 閉じたあとに読み終えた一覧は出さない
            timer.Stop();
            meetings.StateChanged -= OnStateChanged;
            meetings.MeetingChanged -= OnMeetingChanged;
            meetings.ProgressChanged -= OnProgressChanged;
        };
        ReloadList(meetings.Current?.Id);
        UpdateState();
    }

    // MARK: - 一覧

    /// <summary>一覧の読み込みの番号。最後に始めた読み込みの結果だけを使う（DEC-MTG-071）</summary>
    private int reloadGeneration;

    // 設計判断: DEC-MTG-071
    /// <summary>
    /// 一覧を読み直す。全会議の meeting.json の読み込みと解析は UI スレッドの外で行い、結果だけを UI スレッドで出す。
    /// 読み終えるまでは前の一覧を出したままにする。続けて呼ばれたら、最後の呼び出しの結果だけを使う
    /// </summary>
    private async void ReloadList(string? selectId = null)
    {
        var generation = ++reloadGeneration;
        var store = meetings.Store(host.Settings.Current);
        List<Meeting> all;
        try
        {
            all = await Task.Run(() => store.LoadAll());
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            // 読めなかったら前の一覧のままにする（最初の読み込みなら、読み込み中の案内を失敗の案内に変える）
            if (MeetingList.Items.Count == 0) ListEmptyText.Text = Strings.Meeting_ListLoadFailed;
            return;
        }
        if (generation != reloadGeneration) return;
        selectId ??= selected?.Id;
        // 記録中・処理中の会議はメモリ上のものを使う（ファイルより新しい）
        if (meetings.Current is { } current)
        {
            all.RemoveAll(m => m.Id == current.Id);
            all.Insert(0, current);
        }
        var rows = all.Select(m => new MeetingRow(m, m.Title, Detail(m))).ToList();
        loading = true;
        MeetingList.ItemsSource = rows;
        // 設計判断: DEC-MTG-073（読み終えてから 0 件のときだけ出す。読み込み中に「まだありません」と見せない）
        ListEmptyText.Text = Strings.Meeting_ListEmpty;
        ListEmptyText.Visibility = rows.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        MeetingList.SelectedItem = rows.FirstOrDefault(r => r.Meeting.Id == selectId);
        loading = false;
        if (MeetingList.SelectedItem is MeetingRow row) Show(row.Meeting);
        else if (selected is not null && rows.All(r => r.Meeting.Id != selected.Id)) Show(null);
    }

    private static string Detail(Meeting m)
    {
        var status = m.Status switch
        {
            MeetingStatus.Recording => Strings.Meeting_Recording,
            MeetingStatus.Processing => Strings.Meeting_Status_Processing,
            MeetingStatus.Failed => Strings.Meeting_Status_Failed,
            _ => m.ErrorMessage is null ? "" : Strings.Meeting_Status_Warning,
        };
        return $"{Meeting.FormatDate(m.StartedAt)}{Strings.Separator}{Meeting.Clock(m.Duration)}{(status.Length > 0 ? Strings.Separator + status : "")}";
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
        MeetingInfo.Text = $"{Meeting.FormatDate(m.StartedAt)}{Strings.Separator}{Meeting.Clock(m.Duration)}{Strings.Separator}"
            + string.Format(Strings.Meeting_SavedIn, Path.Combine(meetings.Store(host.Settings.Current).BaseDirectory, m.Id));
        TemplateCombo.SelectedItem = TemplateCombo.Items.OfType<ComboBoxItem>().First(i => (MinutesTemplate)i.Tag == m.Template);
        loading = false;
        ErrorText.Text = m.ErrorMessage ?? "";
        ErrorText.Visibility = m.ErrorMessage is null ? Visibility.Collapsed : Visibility.Visible;
        MinutesBox.Text = m.Minutes ?? (m.Status switch
        {
            MeetingStatus.Recording => Strings.Meeting_MinutesAfterRecording,
            MeetingStatus.Processing => Strings.Meeting_Processing,
            _ => Strings.Meeting_NoMinutesYet,
        });
        ShowTranscript(m);
        if (!NotesBox.IsKeyboardFocused) NotesBox.Text = m.NotesText;
        HighlightsBox.Text = m.HighlightContextText();
        BuildSpeakerEditors(m);

        var live = IsLive(m);
        var busy = live || m.Status is MeetingStatus.Recording or MeetingStatus.Processing;
        RecordingPanel.Visibility = live && meetings.State == MeetingState.Recording ? Visibility.Visible : Visibility.Collapsed;
        RegenerateButton.IsEnabled = TemplateCombo.IsEnabled = SaveNotesAndRegenerateButton.IsEnabled = !busy && m.UsedUtterances.Count > 0;
        // 設計判断: DEC-MTG-092
        MinutesOutdatedPanel.Visibility = m.MinutesOutdated == true ? Visibility.Visible : Visibility.Collapsed;
        MinutesOutdatedRegenerateButton.IsEnabled = TranscriptOutdatedRegenerateButton.IsEnabled = RegenerateButton.IsEnabled;
        DeleteButton.IsEnabled = !busy && meetings.CanDelete(m);
        RecordingNote.Text = string.Format(Strings.Meeting_RecordingNote, host.Settings.Current.MeetingEngine == TranscriptionEngine.Gemini ? "Gemini" : "Whisper");
        UpdateLiveNotes();
        UpdateOffRecord();
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
                ToolTip = inferred ? string.Format(Strings.Meeting_SpeakerName_Inferred_Tip, defaultName) : string.Format(Strings.Meeting_SpeakerName_Tip, defaultName),
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
                panel.Children.Add(new TextBlock { Text = Strings.Meeting_Inferred, Foreground = System.Windows.Media.Brushes.DarkOrange, FontSize = 11, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(4, 0, 0, 0) });
            }
            SpeakersPanel.Children.Add(panel);
        }
    }

    private void RenameSpeaker(Meeting m, string speaker, string name, string defaultName)
    {
        if (!m.RenameSpeaker(speaker, name == defaultName ? "" : name)) return;
        SaveSelected(m, Strings.Meeting_SpeakerNamesSaved);
        ShowTranscript(m);
        HighlightsBox.Text = m.HighlightContextText();
        // 推測の印を外したので、欄を作り直す
        BuildSpeakerEditors(m);
    }

    // 要件: REQ-MTG-029
    // 設計判断: DEC-MTG-024
    private void OnTitleChanged(object sender, RoutedEventArgs e) => CommitTitle();

    private void CommitTitle()
    {
        if (selected is not { } m || loading) return;
        var title = TitleBox.Text.Trim();
        if (title.Length == 0)
        {
            // 空にしたときは元に戻す
            TitleBox.Text = m.Title;
            return;
        }
        if (title != TitleBox.Text) TitleBox.Text = title;
        if (title == m.Title) return;
        m.Title = title;
        SaveSelected(m, Strings.Meeting_TitleSaved);
    }

    private void OnTitleKeyDown(object sender, KeyEventArgs e)
    {
        if (selected is not { } m) return;
        if (e.Key == Key.Enter)
        {
            e.Handled = true;
            CommitTitle();
            TitleBox.SelectAll();
        }
        else if (e.Key == Key.Escape)
        {
            e.Handled = true;
            TitleBox.Text = m.Title;
            TitleBox.SelectAll();
        }
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
            ActionStatus.Text = string.Format(Strings.Meeting_SaveFailed, ex.Message);
        }
    }

    // MARK: - 文字起こし（議事録に使う発言を選ぶ）

    /// <summary>文字起こしの一覧の 1 行（同じ話者の続く発言のまとまり 1 つ）</summary>
    private sealed class TranscriptRow
    {
        public required TranscriptDisplayBlock Block { get; init; }
        public required string Time { get; init; }
        public required string Speaker { get; init; }
        public required string Text { get; init; }
        public required string Reason { get; init; }
        public required bool CanToggle { get; init; }
        public required string CheckTip { get; init; }
        public bool IsUsed => Block.IsUsed;
        public Visibility ReasonVisibility => Reason.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
        // 設計判断: DEC-MTG-091（使わない発言は薄く、除いた発言とオフレコは取り消し線も）
        public double Opacity => Block.IsUsed ? 1.0 : 0.45;
        public TextDecorationCollection? Decorations =>
            Block.Use is MinutesUse.Excluded or MinutesUse.OffRecord ? TextDecorations.Strikethrough : null;
        /// <summary>コピーするときの 1 行（表示どおり）</summary>
        public string Line => $"[{Time}] {Speaker}: {Text}";
    }

    // 要件: REQ-MTG-045
    /// <summary>使わない発言に添える短い理由</summary>
    private static string ReasonLabel(MinutesUse use) => use switch
    {
        MinutesUse.Excluded => Strings.Meeting_Use_Excluded,
        MinutesUse.OffRecord => Strings.Meeting_Use_OffRecord,
        MinutesUse.SpeakerExcluded => Strings.Meeting_Use_SpeakerExcluded,
        MinutesUse.OutsideRange => Strings.Meeting_Use_OutsideRange,
        _ => "",
    };

    /// <summary>チェックボックスで切り替えられる発言か（話者・オフレコで除いた発言は、帯のボタンで戻す）</summary>
    private static bool IsToggleable(MinutesUse use) => use is MinutesUse.Used or MinutesUse.Excluded or MinutesUse.OutsideRange;

    private bool CanEditSelection(Meeting m) => meetings.CanEditMinutesSelection(m);

    // 要件: REQ-MTG-044, REQ-MTG-045, REQ-MTG-046
    // 設計判断: DEC-MTG-091, DEC-MTG-112
    /// <summary>文字起こしの一覧と上の帯を出す。同じ会議を出し直すときは、スクロールの位置と選んだ発言を保つ</summary>
    private void ShowTranscript(Meeting m)
    {
        if (m.Utterances.Count == 0)
        {
            TranscriptEmptyText.Text = IsLive(m) ? Strings.Meeting_TranscriptAfterRecording : Strings.Meeting_NoTranscriptYet;
            TranscriptEmptyText.Visibility = Visibility.Visible;
            SelectionBar.Visibility = Visibility.Collapsed;
            TranscriptList.Visibility = Visibility.Collapsed;
            TranscriptList.ItemsSource = null;
            transcriptShownId = m.Id;
            return;
        }
        TranscriptEmptyText.Visibility = Visibility.Collapsed;
        SelectionBar.Visibility = Visibility.Visible;
        TranscriptList.Visibility = Visibility.Visible;

        var canEdit = CanEditSelection(m);
        var same = transcriptShownId == m.Id;
        var scroll = same ? TranscriptScrollViewer()?.VerticalOffset : null;
        var selectedIds = same ? TranscriptList.SelectedItems.OfType<TranscriptRow>().SelectMany(r => r.Block.Members).ToHashSet() : new HashSet<string>();
        if (!same) lastCheckedId = null;
        transcriptShownId = m.Id;

        var rows = m.DisplayBlocks().Select(b => new TranscriptRow
        {
            Block = b,
            Time = Meeting.Clock(b.Block.Start),
            Speaker = m.DisplayName(b.Block.Speaker),
            Text = b.Block.Text,
            Reason = ReasonLabel(b.Use),
            CanToggle = canEdit && IsToggleable(b.Use),
            CheckTip = IsToggleable(b.Use) ? Strings.Meeting_UseForMinutes : string.Format(Strings.Meeting_UseForMinutes_Locked, ReasonLabel(b.Use)),
        }).ToList();
        TranscriptList.ItemsSource = rows;
        foreach (var row in rows.Where(r => r.Block.Members.Any(selectedIds.Contains))) TranscriptList.SelectedItems.Add(row);
        if (scroll is { } offset)
        {
            // 一覧を入れ替えると先頭に戻るので、並べ終えてから元の位置に戻す
            Dispatcher.BeginInvoke(DispatcherPriority.Loaded, () => TranscriptScrollViewer()?.ScrollToVerticalOffset(offset));
        }

        UpdateSelectionBar(m, canEdit);
    }

    private ScrollViewer? TranscriptScrollViewer() => FindScrollViewer(TranscriptList);

    private static ScrollViewer? FindScrollViewer(DependencyObject parent)
    {
        for (var i = 0; i < System.Windows.Media.VisualTreeHelper.GetChildrenCount(parent); i++)
        {
            var child = System.Windows.Media.VisualTreeHelper.GetChild(parent, i);
            if (child is ScrollViewer viewer) return viewer;
            if (FindScrollViewer(child) is { } found) return found;
        }
        return null;
    }

    // 要件: REQ-MTG-044, REQ-MTG-045, REQ-MTG-046
    // 設計判断: DEC-MTG-092, DEC-MTG-112
    /// <summary>上の帯: 使う発言の数・範囲・除いた話者・オフレコの区間（それぞれ解除のボタン）・すべて元に戻す・作り直しの案内</summary>
    private void UpdateSelectionBar(Meeting m, bool canEdit)
    {
        UsedCountText.Text = string.Format(Strings.Meeting_Selection_Count, m.UsedUtterances.Count, m.Utterances.Count);
        ResetSelectionButton.Visibility = m.HasMinutesSelection ? Visibility.Visible : Visibility.Collapsed;
        ResetSelectionButton.IsEnabled = canEdit;
        TranscriptOutdatedPanel.Visibility = m.MinutesOutdated == true ? Visibility.Visible : Visibility.Collapsed;

        SelectionChips.Children.Clear();
        if (m.MinutesFrom is not null || m.MinutesTo is not null)
        {
            var from = m.MinutesFrom is { } f ? Meeting.Clock(f) : Strings.Meeting_Selection_RangeStart;
            var to = m.MinutesTo is { } t ? Meeting.Clock(t) : Strings.Meeting_Selection_RangeEnd;
            AddChip(string.Format(Strings.Meeting_Selection_Range, from, to), Strings.Meeting_Selection_Clear, canEdit, x =>
            {
                x.SetMinutesFrom(null);
                x.SetMinutesTo(null);
            });
        }
        foreach (var speaker in m.ExcludedSpeakers ?? [])
        {
            AddChip(string.Format(Strings.Meeting_Selection_ExcludedSpeaker, m.DisplayName(speaker)), Strings.Meeting_Selection_Restore, canEdit,
                x => x.SetSpeakerExcluded(speaker, excluded: false));
        }
        foreach (var span in m.OffRecord ?? [])
        {
            var id = span.Id;
            AddChip(string.Format(Strings.Meeting_Selection_OffRecord, Meeting.Clock(span.Start), Meeting.Clock(span.End ?? m.Duration)),
                Strings.Meeting_Selection_Clear, canEdit, x => x.RemoveOffRecord(id));
        }
        SelectionChips.Visibility = SelectionChips.Children.Count == 0 ? Visibility.Collapsed : Visibility.Visible;
    }

    private void AddChip(string text, string buttonText, bool canEdit, Action<Meeting> change)
    {
        var panel = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 2, 14, 2) };
        panel.Children.Add(new TextBlock { Text = text, VerticalAlignment = VerticalAlignment.Center, FontSize = 12 });
        var button = new Button { Content = buttonText, Style = (Style)FindResource("ChipButton"), IsEnabled = canEdit };
        button.Click += (_, _) => ChangeSelection(change);
        panel.Children.Add(button);
        SelectionChips.Children.Add(panel);
    }

    // 要件: REQ-MTG-044, REQ-MTG-045, REQ-MTG-046
    // 設計判断: DEC-MTG-090, DEC-MTG-092
    /// <summary>選んだ会議の、議事録に使う発言の選び方を変えて保存する（議事録は作り直さない）</summary>
    private void ChangeSelection(Action<Meeting> change)
    {
        if (selected is not { } m) return;
        try
        {
            if (!meetings.ChangeMinutesSelection(m, change)) return;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            ActionStatus.Text = string.Format(Strings.Meeting_SaveFailed, ex.Message);
        }
        ShowTranscript(m);
        MinutesOutdatedPanel.Visibility = m.MinutesOutdated == true ? Visibility.Visible : Visibility.Collapsed;
    }

    private void OnResetSelectionClick(object sender, RoutedEventArgs e) => ChangeSelection(x => x.ClearMinutesSelection());

    // 要件: REQ-MTG-045
    // 設計判断: DEC-MTG-112
    /// <summary>チェックボックス（オンが使う）。Shift を押しながらなら、前に押した発言からこの発言までを同じ状態にする</summary>
    private void OnUseCheckClick(object sender, RoutedEventArgs e)
    {
        if (sender is not CheckBox { DataContext: TranscriptRow row } box || TranscriptList.ItemsSource is not List<TranscriptRow> rows) return;
        var use = box.IsChecked == true;
        var targets = new List<TranscriptRow> { row };
        var index = rows.IndexOf(row);
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Shift) && lastCheckedId is { } anchorId
            && rows.FindIndex(r => r.Block.Members.Contains(anchorId)) is var anchor and >= 0 && index >= 0)
        {
            targets = rows.GetRange(Math.Min(anchor, index), Math.Abs(anchor - index) + 1);
        }
        lastCheckedId = row.Block.Id;
        SetUse(targets, use);
    }

    /// <summary>発言のまとまりを使う・使わないにする（話者・オフレコで除いたものは変えない）</summary>
    private void SetUse(IEnumerable<TranscriptRow> rows, bool use)
    {
        var ids = rows.Where(r => IsToggleable(r.Block.Use)).SelectMany(r => r.Block.Members).ToList();
        if (ids.Count == 0) return;
        ChangeSelection(x =>
        {
            if (use) x.Include(ids);
            else x.SetExcluded(ids, excluded: true);
        });
    }

    /// <summary>右クリックのメニューの対象（選んだ発言。時刻の順）</summary>
    private List<TranscriptRow> MenuTargets() => TranscriptList.SelectedItems.OfType<TranscriptRow>().OrderBy(r => r.Block.Block.Start).ToList();

    // 要件: REQ-MTG-044, REQ-MTG-045
    // 設計判断: DEC-MTG-112
    private void OnTranscriptMenuOpened(object sender, RoutedEventArgs e)
    {
        var targets = MenuTargets();
        var canEdit = selected is { } m && CanEditSelection(m) && targets.Count > 0;
        var toggleable = targets.Where(r => IsToggleable(r.Block.Use)).ToList();
        ExcludeMenuItem.Visibility = toggleable.Any(r => r.IsUsed) || toggleable.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        IncludeMenuItem.Visibility = toggleable.Any(r => !r.IsUsed) ? Visibility.Visible : Visibility.Collapsed;
        ExcludeMenuItem.IsEnabled = IncludeMenuItem.IsEnabled = canEdit && toggleable.Count > 0;
        FromHereMenuItem.IsEnabled = ToHereMenuItem.IsEnabled = canEdit;
        if (targets.Count > 0 && selected is { } meeting)
        {
            // 右クリックした（最初に選んだ）発言の話者
            var speaker = targets[0].Block.Block.Speaker;
            var excluded = meeting.ExcludedSpeakers?.Contains(speaker) == true;
            // 話者名の「_」がアクセスキーにならないように重ねる
            SpeakerMenuItem.Header = string.Format(excluded ? Strings.Meeting_Menu_IncludeSpeaker : Strings.Meeting_Menu_ExcludeSpeaker,
                meeting.DisplayName(speaker).Replace("_", "__"));
            SpeakerMenuItem.Tag = speaker;
            SpeakerMenuItem.Visibility = Visibility.Visible;
        }
        else
        {
            SpeakerMenuItem.Visibility = Visibility.Collapsed;
        }
        SpeakerMenuItem.IsEnabled = canEdit;
        CopyRowsMenuItem.IsEnabled = targets.Count > 0;
    }

    private void OnExcludeMenuClick(object sender, RoutedEventArgs e) => SetUse(MenuTargets(), use: false);

    private void OnIncludeMenuClick(object sender, RoutedEventArgs e) => SetUse(MenuTargets(), use: true);

    // 要件: REQ-MTG-044
    private void OnFromHereMenuClick(object sender, RoutedEventArgs e)
    {
        if (MenuTargets() is [var first, ..]) ChangeSelection(x => x.SetMinutesFrom(first.Block.Block.Start));
    }

    // 要件: REQ-MTG-044
    private void OnToHereMenuClick(object sender, RoutedEventArgs e)
    {
        // まとめた最後の発言まで入れる
        if (MenuTargets() is [.., var last]) ChangeSelection(x => x.SetMinutesTo(last.Block.LastStart));
    }

    // 要件: REQ-MTG-045
    private void OnSpeakerMenuClick(object sender, RoutedEventArgs e)
    {
        if (SpeakerMenuItem.Tag is not string speaker || selected is not { } m) return;
        var excluded = m.ExcludedSpeakers?.Contains(speaker) == true;
        ChangeSelection(x => x.SetSpeakerExcluded(speaker, excluded: !excluded));
    }

    // 設計判断: DEC-MTG-112
    /// <summary>選んだ発言を、表示どおり 1 行 1 発言でコピーする（使う発言・使わない発言とも）</summary>
    private void CopyRows()
    {
        var rows = MenuTargets();
        if (rows.Count == 0) return;
        try
        {
            Clipboard.SetText(string.Join(Environment.NewLine, rows.Select(r => r.Line)));
            ActionStatus.Text = string.Format(Strings.Meeting_CopiedUtterances, rows.Count);
        }
        catch (System.Runtime.InteropServices.ExternalException ex)
        {
            ActionStatus.Text = string.Format(Strings.CopyFailed, ex.Message);
        }
    }

    private void OnCopyRowsExecuted(object sender, ExecutedRoutedEventArgs e) => CopyRows();

    private void OnCopyRowsCanExecute(object sender, CanExecuteRoutedEventArgs e)
    {
        e.CanExecute = TranscriptList.SelectedItems.Count > 0;
        e.Handled = true;
    }

    private void OnCopyRowsMenuClick(object sender, RoutedEventArgs e) => CopyRows();

    // MARK: - 議事録

    private void OnRegenerateClick(object sender, RoutedEventArgs e)
    {
        if (selected is { } m && ConfirmRegenerate(m, Strings.Meeting_ConfirmRegenerateQuestion)) _ = RegenerateAsync(m, null);
    }

    // 設計判断: DEC-MTG-072
    /// <summary>
    /// 議事録を作り直す前の確かめ。今の議事録があるときだけ尋ねる（置き換わるため。既定のボタンはキャンセル。DEC-DIC-079）。
    /// まだ議事録がないときは尋ねずに true
    /// </summary>
    private bool ConfirmRegenerate(Meeting m, string question) =>
        m.Minutes is null
        || MessageBox.Show(this, string.Format(Strings.Meeting_RegenerateWillReplace, question), "Hanasu",
            MessageBoxButton.OKCancel, MessageBoxImage.Question, MessageBoxResult.Cancel) == MessageBoxResult.OK;

    private void OnTemplateChanged(object sender, SelectionChangedEventArgs e)
    {
        if (loading || selected is not { } m || TemplateCombo.SelectedItem is not ComboBoxItem { Tag: MinutesTemplate t } || t == m.Template) return;
        // 設計判断: DEC-MTG-072（既定のボタンはキャンセル）
        if (MessageBox.Show(this, string.Format(Strings.Meeting_ConfirmRegenerate, t.Title()), "Hanasu",
                MessageBoxButton.OKCancel, MessageBoxImage.Question, MessageBoxResult.Cancel) != MessageBoxResult.OK)
        {
            Show(m);
            return;
        }
        _ = RegenerateAsync(m, t);
    }

    private async Task RegenerateAsync(Meeting m, MinutesTemplate? template)
    {
        RegenerateButton.IsEnabled = TemplateCombo.IsEnabled = SaveNotesAndRegenerateButton.IsEnabled = DeleteButton.IsEnabled = false;
        // 作り直している間は、議事録に使う発言を変えさせない（CanEditMinutesSelection）
        MinutesOutdatedRegenerateButton.IsEnabled = TranscriptOutdatedRegenerateButton.IsEnabled = false;
        ActionStatus.Text = string.Format(Core.Properties.Strings.Meeting_MakingMinutes, Core.Ai.TextAiFactory.NameOf(host.Settings.Current.MeetingAi));
        var started = Stopwatch.StartNew();
        try
        {
            // 作り直しの印は呼んだときに付くので、そのあとで一覧を出し直すと選べなくなる
            var regenerating = meetings.RegenerateMinutesAsync(m, template);
            if (selected?.Id == m.Id) ShowTranscript(m);
            await regenerating;
            ActionStatus.Text = string.Format(Strings.Meeting_Regenerated, started.Elapsed.TotalSeconds.ToString("0"));
            Tabs.SelectedIndex = 0;
        }
        catch (Exception ex) when (ex is Core.Ai.TextAiException or Core.Gemini.ServiceAccountException or IOException)
        {
            // 失敗したときは、型も議事録も元のまま
            ActionStatus.Text = string.Format(Core.Properties.Strings.Meeting_MinutesFailed, ex.Message);
        }
        finally
        {
            Show(m);
        }
    }

    private void OnCopyClick(object sender, RoutedEventArgs e)
    {
        if (selected is not { } m) return;
        var (text, empty, copied) = Tabs.SelectedIndex switch
        {
            1 => (m.TranscriptMarkdown(), Strings.Meeting_NoTranscript, Strings.Meeting_CopiedTranscript),
            2 => (m.HighlightContextText(), Strings.Meeting_NoHighlights, Strings.Meeting_CopiedHighlights),
            3 => (m.NotesMarkdown(), Strings.Meeting_NoNotes, Strings.Meeting_CopiedNotes),
            _ => (m.Minutes ?? "", Strings.Meeting_NoMinutes, Strings.Meeting_CopiedMinutes),
        };
        if (text.Length == 0)
        {
            ActionStatus.Text = empty;
            return;
        }
        try
        {
            Clipboard.SetText(text);
            ActionStatus.Text = copied;
        }
        catch (System.Runtime.InteropServices.ExternalException ex)
        {
            ActionStatus.Text = string.Format(Strings.CopyFailed, ex.Message);
        }
    }

    private void OnOpenFolderClick(object sender, RoutedEventArgs e)
    {
        if (selected is not { } m) return;
        var dir = Path.Combine(meetings.Store(host.Settings.Current).BaseDirectory, m.Id);
        if (!Directory.Exists(dir))
        {
            ActionStatus.Text = Strings.Meeting_FolderNotFound;
            return;
        }
        Process.Start(new ProcessStartInfo("explorer.exe", $"\"{dir}\"") { UseShellExecute = true });
    }

    // MARK: - 削除

    // 要件: REQ-MTG-028
    // 設計判断: DEC-MTG-022
    private void OnDeleteClick(object sender, RoutedEventArgs e) => ConfirmDelete();

    private void OnMeetingListKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Delete) return;
        e.Handled = true;
        ConfirmDelete();
    }

    private void OnMeetingListMenuOpened(object sender, RoutedEventArgs e) =>
        DeleteMenuItem.IsEnabled = MeetingList.SelectedItem is MeetingRow row && CanDelete(row.Meeting);

    private bool CanDelete(Meeting m) =>
        meetings.CanDelete(m) && m.Status is not (MeetingStatus.Recording or MeetingStatus.Processing);

    /// <summary>選んだ会議を、確かめてからごみ箱に移し、一覧の次の会議を選ぶ</summary>
    private void ConfirmDelete()
    {
        if (MeetingList.SelectedItem is not MeetingRow row || !CanDelete(row.Meeting)) return;
        var m = row.Meeting;
        if (MessageBox.Show(this,
                string.Format(Strings.Meeting_ConfirmDelete, m.Title),
                Strings.Meeting_ConfirmDelete_Title, MessageBoxButton.OKCancel, MessageBoxImage.Warning, MessageBoxResult.Cancel) != MessageBoxResult.OK)
        {
            return;
        }
        var rows = MeetingList.ItemsSource.OfType<MeetingRow>().ToList();
        var index = rows.IndexOf(row);
        try
        {
            meetings.Delete(m, dir => Microsoft.VisualBasic.FileIO.FileSystem.DeleteDirectory(
                dir, Microsoft.VisualBasic.FileIO.UIOption.OnlyErrorDialogs, Microsoft.VisualBasic.FileIO.RecycleOption.SendToRecycleBin));
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or InvalidOperationException or OperationCanceledException)
        {
            MessageBox.Show(this, string.Format(Strings.DeleteFailed, ex.Message), "Hanasu", MessageBoxButton.OK, MessageBoxImage.Error);
            return;
        }
        var rest = rows.Where(r => r.Meeting.Id != m.Id).ToList();
        var next = rest.Count == 0 ? null : rest[Math.Min(index, rest.Count - 1)].Meeting;
        selected = null;
        ReloadList(next?.Id);
        if (next is null) Show(null);
        ActionStatus.Text = string.Format(Strings.Meeting_MovedToRecycleBin, m.Title);
    }

    // MARK: - メモ（記録のあと）

    private void OnSaveNotesClick(object sender, RoutedEventArgs e) => SaveNotes(regenerate: false);

    private void OnSaveNotesAndRegenerateClick(object sender, RoutedEventArgs e) => SaveNotes(regenerate: true);

    private void SaveNotes(bool regenerate)
    {
        if (selected is not { } m) return;
        if (IsLive(m))
        {
            ActionStatus.Text = Strings.Meeting_NotesWhileRecording;
            return;
        }
        // 設計判断: DEC-MTG-072（確かめてから保存する。キャンセルなら保存もしない）
        if (regenerate && !ConfirmRegenerate(m, Strings.Meeting_ConfirmSaveNotesAndRegenerate)) return;
        var notes = MeetingNote.Parse(NotesBox.Text);
        m.Notes = notes.Count == 0 ? null : notes;
        SaveSelected(m, Strings.Meeting_NotesSaved);
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

    // 要件: REQ-MTG-046
    // 設計判断: DEC-MTG-094
    private void OnOffRecordClick(object sender, RoutedEventArgs e)
    {
        meetings.ToggleOffRecord();
        UpdateOffRecord();
    }

    // 要件: REQ-MTG-046
    /// <summary>オフレコ中なら、ボタンを「オフレコを終える」にし、「オフレコ中（12:34 から）」を出す</summary>
    private void UpdateOffRecord()
    {
        if (meetings.OpenOffRecord is { } open)
        {
            OffRecordButton.Content = Strings.Meeting_OffRecordEnd;
            OffRecordStatus.Text = string.Format(Strings.Meeting_OffRecordActive, Meeting.Clock(open.Start));
            OffRecordStatus.Visibility = Visibility.Visible;
        }
        else
        {
            OffRecordButton.Content = Strings.Meeting_OffRecord;
            OffRecordStatus.Visibility = Visibility.Collapsed;
        }
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
            UndoHighlightButton.Content = string.Format(Strings.Meeting_UndoHighlight, Math.Max(1, remaining));
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
        UpdateOffRecord();
    }

    // MARK: - 状態

    private void OnStateChanged(object? sender, MeetingState state) => Dispatcher.BeginInvoke(UpdateState);

    private void OnProgressChanged(object? sender, string message) => Dispatcher.BeginInvoke(() => LiveProgress.Text = message);

    private void OnMeetingChanged(object? sender, Meeting m) => Dispatcher.BeginInvoke(() =>
    {
        if (selected?.Id == m.Id && IsLive(m))
        {
            UpdateLiveNotes();
            UpdateOffRecord();
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
            MeetingState.Starting => Strings.Meeting_Starting,
            MeetingState.Processing => Strings.Meeting_PostProcessing,
            _ => Strings.Meeting_Recording,
        };
        StopButton.Visibility = state == MeetingState.Recording ? Visibility.Visible : Visibility.Collapsed;
        LiveProgress.Text = state == MeetingState.Processing ? meetings.ProgressMessage ?? "" : string.Format(Strings.Meeting_StopHint, host.Settings.Current.MeetingHotKey.DisplayString);
        StartButton.IsEnabled = state == MeetingState.Idle;
        MicCombo.IsEnabled = OutputCombo.IsEnabled = NextTemplateCombo.IsEnabled = CustomPromptBox.IsEnabled = state == MeetingState.Idle;
        StartNote.Text = state == MeetingState.Idle
            ? string.Format(Strings.Meeting_StartHint, host.Settings.Current.MeetingHotKey.DisplayString)
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
        var mics = new List<MicrophoneInfo> { new("", Strings.Device_DefaultMic) };
        mics.AddRange(WasapiRecorder.ListMicrophones());
        if (s.MeetingMicrophoneDeviceId.Length > 0 && mics.All(m => m.Id != s.MeetingMicrophoneDeviceId)) mics.Add(new(s.MeetingMicrophoneDeviceId, Strings.Device_MissingMic));
        MicCombo.ItemsSource = mics;
        MicCombo.DisplayMemberPath = nameof(MicrophoneInfo.Name);
        MicCombo.SelectedItem = mics.First(m => m.Id == s.MeetingMicrophoneDeviceId);

        var outputs = new List<OutputDeviceInfo> { new("", Strings.Device_DefaultOutput) };
        outputs.AddRange(MeetingChannelRecorder.ListOutputs());
        if (s.MeetingOutputDeviceId.Length > 0 && outputs.All(o => o.Id != s.MeetingOutputDeviceId)) outputs.Add(new(s.MeetingOutputDeviceId, Strings.Device_MissingOutput));
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
