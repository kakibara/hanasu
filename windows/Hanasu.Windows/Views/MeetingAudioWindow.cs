using System.IO;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;
using Hanasu.Core.Meetings;

namespace Hanasu.Windows.Views;

// 要件: REQ-MTG-056
// 設計判断: DEC-MTG-140, DEC-MTG-141, DEC-MTG-142
/// <summary>
/// 録音の管理（Mac 版の MeetingAudioManagerView にあたる）。録音が残っている会議を新しい順に並べ、選んだ会議・30 日より前・すべての録音を消す。
/// 記録中・処理中の会議は並べない。「30 日より前」「すべて」は文字起こしがそろっていない会議を含めない（選べば消せる）。
/// 消すのは録音だけで、完全に消す（ごみ箱に入れない）。開いている間に会議が変わったら読み直す。
/// </summary>
internal sealed class MeetingAudioWindow : Window
{
    private readonly AppHost host;
    private readonly MeetingController meetings;
    private readonly TextBlock summary = new() { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 4, 0, 0) };
    private readonly StackPanel list = new();
    private readonly TextBlock empty = new()
    {
        Text = Strings.MeetingAudio_Empty,
        Foreground = SystemColors.GrayTextBrush,
        HorizontalAlignment = HorizontalAlignment.Center,
        VerticalAlignment = VerticalAlignment.Center,
        TextWrapping = TextWrapping.Wrap,
        Margin = new Thickness(12),
        Visibility = Visibility.Collapsed,
    };
    private readonly TextBlock status = new() { TextWrapping = TextWrapping.Wrap, Foreground = SystemColors.GrayTextBrush, Margin = new Thickness(0, 6, 0, 0) };
    private readonly Button deleteSelected = MakeButton(Strings.MeetingAudio_DeleteSelected);
    private readonly Button deleteOlder = MakeButton(string.Format(Strings.MeetingAudio_DeleteOlder, MeetingAudioCleanup.OlderThanDays));
    private readonly Button deleteAll = MakeButton(Strings.MeetingAudio_DeleteAll);
    private readonly List<(CheckBox Box, MeetingAudioEntry Entry)> rows = new();
    private List<MeetingAudioEntry> entries = new();
    /// <summary>読み込みの番号。最後に始めた読み込みの結果だけを使う</summary>
    private int generation;

    public MeetingAudioWindow(AppHost host)
    {
        this.host = host;
        meetings = host.Meetings;
        Title = Strings.MeetingAudio_Title;
        Width = 620;
        Height = 540;
        MinWidth = 480;
        MinHeight = 360;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        ShowInTaskbar = false;
        FontFamily = new FontFamily("Yu Gothic UI, Meiryo UI, Segoe UI");
        FontSize = 13;

        var root = new DockPanel { Margin = new Thickness(16) };

        var header = new StackPanel();
        header.Children.Add(new TextBlock { Text = Strings.MeetingAudio_Title, FontSize = 16, FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap });
        header.Children.Add(summary);
        DockPanel.SetDock(header, Dock.Top);
        root.Children.Add(header);

        var footer = new StackPanel { Margin = new Thickness(0, 10, 0, 0) };
        var buttons = new WrapPanel();
        deleteSelected.Click += (_, _) => DeleteSelected();
        deleteOlder.Click += (_, _) => DeleteOlder();
        deleteAll.Click += (_, _) => DeleteAll();
        buttons.Children.Add(deleteSelected);
        buttons.Children.Add(deleteOlder);
        buttons.Children.Add(deleteAll);
        var bottom = new DockPanel();
        var close = new Button { Content = Strings.Close, Padding = new Thickness(12, 4, 12, 4), IsCancel = true, VerticalAlignment = VerticalAlignment.Top };
        close.Click += (_, _) => Close();
        DockPanel.SetDock(close, Dock.Right);
        bottom.Children.Add(close);
        bottom.Children.Add(buttons);
        footer.Children.Add(bottom);
        footer.Children.Add(status);
        footer.Children.Add(new TextBlock
        {
            Text = Strings.MeetingAudio_SyncNote,
            TextWrapping = TextWrapping.Wrap,
            Foreground = SystemColors.GrayTextBrush,
            FontSize = 11.5,
            Margin = new Thickness(0, 8, 0, 0),
        });
        DockPanel.SetDock(footer, Dock.Bottom);
        root.Children.Add(footer);

        var scroll = new ScrollViewer { Content = list, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
        AutomationProperties.SetName(scroll, Strings.MeetingAudio_List_A11y);
        var listArea = new Border
        {
            BorderBrush = SystemColors.ActiveBorderBrush,
            BorderThickness = new Thickness(1),
            Margin = new Thickness(0, 10, 0, 0),
            Child = new Grid { Children = { scroll, empty } },
        };
        root.Children.Add(listArea);
        Content = root;
        UpdateButtons();

        meetings.MeetingChanged += OnMeetingsChanged;
        meetings.AudioDeleted += OnAudioDeleted;
        meetings.StateChanged += OnStateChanged;
        Loaded += (_, _) => Reload();
        Closed += (_, _) =>
        {
            generation++;
            meetings.MeetingChanged -= OnMeetingsChanged;
            meetings.AudioDeleted -= OnAudioDeleted;
            meetings.StateChanged -= OnStateChanged;
        };
    }

    private static Button MakeButton(string text) =>
        new() { Content = text, Padding = new Thickness(10, 4, 10, 4), Margin = new Thickness(0, 0, 6, 6), MinHeight = 26 };

    private void OnMeetingsChanged(object? sender, Meeting meeting) => Dispatcher.BeginInvoke(Reload);

    private void OnAudioDeleted(object? sender, IReadOnlyList<Meeting> deleted) => Dispatcher.BeginInvoke(Reload);

    private void OnStateChanged(object? sender, MeetingState state) => Dispatcher.BeginInvoke(Reload);

    // MARK: - 一覧

    /// <summary>録音が残っている会議を読み直す（meeting.json の読み込みは UI スレッドの外で）。選んでいた会議の印は残す</summary>
    private async void Reload()
    {
        var mine = ++generation;
        var store = meetings.Store(host.Settings.Current);
        var currentId = meetings.Current?.Id;
        List<MeetingAudioEntry> loaded;
        try
        {
            loaded = await Task.Run(() => MeetingAudioCleanup.Entries(store.LoadAll(), store.BaseDirectory, currentId));
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            if (mine == generation) status.Text = $"{Strings.Meeting_ListLoadFailed} {e.Message}";
            return;
        }
        if (mine != generation) return;
        var checkedIds = rows.Where(r => r.Box.IsChecked == true).Select(r => r.Entry.Meeting.Id).ToHashSet();
        entries = loaded;
        rows.Clear();
        list.Children.Clear();
        foreach (var entry in entries) AddRow(entry, checkedIds.Contains(entry.Meeting.Id));
        empty.Visibility = entries.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        UpdateSummary();
        UpdateButtons();
    }

    private void AddRow(MeetingAudioEntry entry, bool isChecked)
    {
        var meeting = entry.Meeting;
        var content = new StackPanel();
        content.Children.Add(new TextBlock { Text = meeting.Title, FontWeight = FontWeights.SemiBold, TextTrimming = TextTrimming.CharacterEllipsis });
        var detail = new StackPanel { Orientation = Orientation.Horizontal };
        detail.Children.Add(new TextBlock
        {
            Text = $"{Meeting.FormatDate(meeting.StartedAt)}{Strings.Separator}{MeetingAudioCleanup.FormatSize(entry.Size)}",
            Foreground = SystemColors.GrayTextBrush,
            FontSize = 11.5,
        });
        // 設計判断: DEC-MTG-142（文字起こしがそろっていない会議に印を付ける）
        if (Marker(entry.State) is { } marker)
        {
            detail.Children.Add(new TextBlock
            {
                Text = marker,
                Foreground = Brushes.DarkOrange,
                FontSize = 11.5,
                FontWeight = FontWeights.SemiBold,
                Margin = new Thickness(8, 0, 0, 0),
            });
        }
        content.Children.Add(detail);
        var box = new CheckBox { Content = content, IsChecked = isChecked, Margin = new Thickness(8, 5, 8, 5), VerticalContentAlignment = VerticalAlignment.Top };
        AutomationProperties.SetName(box, Marker(entry.State) is { } m ? $"{meeting.Title}{Strings.Separator}{m}" : meeting.Title);
        box.Checked += (_, _) => UpdateButtons();
        box.Unchecked += (_, _) => UpdateButtons();
        rows.Add((box, entry));
        list.Children.Add(box);
    }

    /// <summary>文字起こしの状態の印。そろっていれば null</summary>
    private static string? Marker(MeetingTranscriptState state) => state switch
    {
        MeetingTranscriptState.None => Strings.MeetingAudio_NoTranscript,
        MeetingTranscriptState.Partial => Strings.MeetingAudio_PartialTranscript,
        _ => null,
    };

    private void UpdateSummary()
    {
        var text = string.Format(Strings.MeetingAudio_Summary, entries.Count, MeetingAudioCleanup.FormatSize(MeetingAudioCleanup.TotalSize(entries)));
        var incomplete = entries.Count(e => !e.IsComplete);
        if (incomplete > 0) text += " " + string.Format(Strings.Settings_AudioStatusIncomplete, incomplete);
        summary.Text = text;
    }

    private void UpdateButtons()
    {
        var now = DateTimeOffset.Now;
        deleteSelected.IsEnabled = rows.Any(r => r.Box.IsChecked == true);
        deleteOlder.IsEnabled = MeetingAudioCleanup.OlderThan(entries, MeetingAudioCleanup.OlderThanDays, now).Count > 0;
        deleteAll.IsEnabled = MeetingAudioCleanup.All(entries).Count > 0;
    }

    // MARK: - 消す

    private void DeleteSelected()
    {
        var targets = rows.Where(r => r.Box.IsChecked == true).Select(r => r.Entry).ToList();
        if (targets.Count == 0) return;
        // 選んだ中に文字起こしがそろっていない会議があれば、その件数を書く
        var marked = targets.Count(e => !e.IsComplete);
        ConfirmAndDelete(targets, marked == 0 ? null : string.Format(Strings.MeetingAudio_ConfirmMarked, marked));
    }

    private void DeleteOlder()
    {
        var now = DateTimeOffset.Now;
        ConfirmAndDelete(MeetingAudioCleanup.OlderThan(entries, MeetingAudioCleanup.OlderThanDays, now),
            SkippedNote(MeetingAudioCleanup.SkippedOlderThan(entries, MeetingAudioCleanup.OlderThanDays, now)));
    }

    private void DeleteAll() =>
        ConfirmAndDelete(MeetingAudioCleanup.All(entries), SkippedNote(MeetingAudioCleanup.SkippedAll(entries)));

    /// <summary>「30 日より前」「すべて」で外した会議の件数と大きさ。なければ null</summary>
    private static string? SkippedNote(IReadOnlyCollection<MeetingAudioEntry> skipped) =>
        skipped.Count == 0 ? null : string.Format(Strings.MeetingAudio_ConfirmSkipped, skipped.Count, MeetingAudioCleanup.FormatSize(MeetingAudioCleanup.TotalSize(skipped)));

    /// <summary>件数・合計の大きさ・（あれば）注意・「元に戻せません」を書いたダイアログで確かめてから消す</summary>
    private void ConfirmAndDelete(IReadOnlyCollection<MeetingAudioEntry> targets, string? note)
    {
        if (targets.Count == 0) return;
        var message = string.Format(Strings.MeetingAudio_Confirm, targets.Count, MeetingAudioCleanup.FormatSize(MeetingAudioCleanup.TotalSize(targets)));
        if (note is not null) message += "\n\n" + note;
        message += "\n\n" + Strings.Audio_CannotUndo;
        if (MessageBox.Show(this, message, Strings.MeetingAudio_Title, MessageBoxButton.OKCancel, MessageBoxImage.Warning, MessageBoxResult.Cancel)
            != MessageBoxResult.OK)
        {
            return;
        }
        var result = meetings.DeleteAudio(targets.Select(e => e.Meeting));
        status.Text = string.Format(Strings.MeetingAudio_Deleted, result.Deleted);
        if (result.Failures.Count > 0)
        {
            MessageBox.Show(this, string.Format(Strings.MeetingAudio_DeleteFailed, result.FailedMeetings)
                    + "\n\n" + string.Join("\n", result.Failures.Take(10).Select(f => $"{Path.GetFileName(f.Path)}: {f.Message}")),
                Strings.MeetingAudio_Title, MessageBoxButton.OK, MessageBoxImage.Error);
        }
        // 消したものの印は外す（消せなかった会議は一覧に残る）
        foreach (var row in rows.Where(r => targets.Contains(r.Entry))) row.Box.IsChecked = false;
        Reload();
    }
}
