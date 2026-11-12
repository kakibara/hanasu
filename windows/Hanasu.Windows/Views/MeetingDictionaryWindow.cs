using System.Net.Http;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;
using Hanasu.Core.Ai;
using Hanasu.Core.Meetings;
using Hanasu.Core.Text;

namespace Hanasu.Windows.Views;

// 要件: REQ-DIC-072
// 設計判断: DEC-DIC-087, DEC-DIC-170, DEC-DIC-171
/// <summary>
/// 会議 1 件から辞書の候補を探すダイアログ（Mac 版の MeetingDictionarySheet にあたる）。開いたらすぐ探し、選んだものだけを辞書に足す。
/// 閉じたら AI の呼び出しを止め、辞書も会議も変えない。追加したら ResultMessage に知らせを入れて閉じる。
/// </summary>
internal sealed class MeetingDictionaryWindow : Window
{
    private readonly AppHost host;
    private readonly MeetingController meetings;
    private readonly Meeting meeting;
    private readonly CancellationTokenSource cancellation = new();
    private readonly TextBlock status = new() { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 8, 0, 0) };
    private readonly StackPanel list = new();
    private readonly TextBlock cutNote = new() { TextWrapping = TextWrapping.Wrap, Foreground = Brushes.DarkOrange, Visibility = Visibility.Collapsed, Margin = new Thickness(0, 6, 0, 0) };
    private readonly CheckBox applyToMeeting = new() { Content = Strings.Meeting_Dictionary_ApplyToMeeting, Margin = new Thickness(0, 10, 0, 0) };
    private readonly Button addButton = new() { Padding = new Thickness(12, 4, 12, 4), Margin = new Thickness(8, 0, 0, 0), IsDefault = true, IsEnabled = false };
    private readonly List<(CheckBox Box, DictionaryCandidate Candidate)> rows = new();

    /// <summary>追加して閉じたときの知らせ（会議ノートが出す）</summary>
    public string? ResultMessage { get; private set; }

    public MeetingDictionaryWindow(AppHost host, MeetingController meetings, Meeting meeting)
    {
        this.host = host;
        this.meetings = meetings;
        this.meeting = meeting;
        Title = Strings.Meeting_Dictionary_Title;
        SizeToContent = SizeToContent.Height;
        Width = 520;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        ShowInTaskbar = false;

        var panel = new StackPanel { Margin = new Thickness(16) };
        panel.Children.Add(new TextBlock { Text = Strings.Meeting_Dictionary_Title, FontSize = 16, FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap });
        panel.Children.Add(new TextBlock { Text = meeting.Title, Foreground = SystemColors.GrayTextBrush, TextTrimming = TextTrimming.CharacterEllipsis, Margin = new Thickness(0, 4, 0, 0) });
        status.Text = Strings.Meeting_Dictionary_Searching;
        panel.Children.Add(status);
        var scroll = new ScrollViewer { Content = list, MaxHeight = 320, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Margin = new Thickness(0, 6, 0, 0) };
        AutomationProperties.SetName(scroll, Strings.Meeting_Dictionary_ListName);
        panel.Children.Add(scroll);
        panel.Children.Add(cutNote);
        // 既定は、新しい会議に当てる設定と同じ（REQ-DIC-072）
        applyToMeeting.IsChecked = host.Settings.Current.ApplyDictionaryToMeetings;
        panel.Children.Add(applyToMeeting);
        panel.Children.Add(new TextBlock
        {
            Text = Strings.Meeting_Dictionary_Note,
            TextWrapping = TextWrapping.Wrap,
            Foreground = SystemColors.GrayTextBrush,
            FontSize = 11,
            Margin = new Thickness(0, 6, 0, 0),
        });

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 16, 0, 0) };
        var cancel = new Button { Content = Strings.Meeting_Dictionary_Cancel, Padding = new Thickness(12, 4, 12, 4), IsCancel = true };
        buttons.Children.Add(cancel);
        UpdateAddButton();
        addButton.Click += (_, _) => Add();
        buttons.Children.Add(addButton);
        panel.Children.Add(buttons);
        Content = panel;

        Loaded += async (_, _) => await SearchAsync();
        Closed += (_, _) => cancellation.Cancel();
    }

    // 設計判断: DEC-DIC-170
    private async Task SearchAsync()
    {
        var settings = host.Settings.Current;
        var client = host.CreateTextAi(settings, TextAiUse.Meeting);
        if (client is null)
        {
            status.Text = "⚠️ " + TextAiFactory.NotReadyBecause(settings.MeetingAi);
            return;
        }
        var existing = settings.UserDictionary;
        var material = DictionarySuggester.MaterialFor(meeting, DictionarySuggester.BudgetFor(client, existing));
        try
        {
            var found = await DictionarySuggester.SuggestAsync(material.Text, existing, client, settings.MinutesModel, cancellation.Token);
            if (cancellation.IsCancellationRequested) return;
            ShowCandidates(found, settings.MinutesModel);
            if (material.ReadMinutes is { } minutes)
            {
                cutNote.Text = string.Format(Strings.Meeting_Dictionary_Cut, minutes);
                cutNote.Visibility = Visibility.Visible;
            }
        }
        catch (OperationCanceledException) when (cancellation.IsCancellationRequested)
        {
            // 閉じたので何もしない
        }
        catch (Exception e)
        {
            // どんな失敗でも「探しています…」のまま止めず、理由を出す（REQ-DIC-072）
            status.Text = "⚠️ " + e.Message;
        }
    }

    private void ShowCandidates(IReadOnlyList<DictionaryCandidate> found, string model)
    {
        list.Children.Clear();
        rows.Clear();
        status.Text = found.Count == 0 ? Strings.Meeting_Dictionary_NoCandidates : string.Format(Strings.Meeting_Dictionary_Choose, model);
        foreach (var candidate in found)
        {
            var content = new StackPanel();
            content.Children.Add(new TextBlock
            {
                Text = candidate.Readings.Count == 0 ? candidate.Spelling : $"{string.Join(Strings.ListSeparator, candidate.Readings)} → {candidate.Spelling}",
                TextWrapping = TextWrapping.Wrap,
            });
            if (candidate.Reason.Length > 0)
            {
                content.Children.Add(new TextBlock { Text = candidate.Reason, TextWrapping = TextWrapping.Wrap, Foreground = SystemColors.GrayTextBrush, FontSize = 11 });
            }
            var box = new CheckBox { Content = content, Margin = new Thickness(0, 4, 0, 4) };
            box.Checked += (_, _) => UpdateAddButton();
            box.Unchecked += (_, _) => UpdateAddButton();
            rows.Add((box, candidate));
            list.Children.Add(box);
        }
    }

    private void UpdateAddButton()
    {
        var count = rows.Count(r => r.Box.IsChecked == true);
        addButton.Content = string.Format(Strings.Meeting_Dictionary_Add, count);
        addButton.IsEnabled = count > 0;
    }

    // 設計判断: DEC-DIC-087, DEC-DIC-174
    private void Add()
    {
        var chosen = rows.Where(r => r.Box.IsChecked == true).Select(r => r.Candidate).ToList();
        if (chosen.Count == 0) return;
        cancellation.Cancel();
        var messages = new List<string>();
        var error = host.Settings.Update(s => s.DictionaryText = DictionarySuggester.Appending(chosen, s.DictionaryText));
        messages.Add(error is null ? string.Format(Strings.Meeting_Dictionary_Added, chosen.Count) : string.Format(Strings.Meeting_SaveFailed, error.Message));
        if (error is null && applyToMeeting.IsChecked == true)
        {
            messages.Add(ApplyMessage(meetings, meeting, revert: false));
        }
        ResultMessage = string.Join("\n", messages);
        DialogResult = true;
    }

    // 要件: REQ-DIC-074
    /// <summary>今の辞書を会議に当て直す（revert なら認識したままの文に戻す）。結果の知らせを返す</summary>
    public static string ApplyMessage(MeetingController meetings, Meeting meeting, bool revert)
    {
        try
        {
            if (revert)
            {
                var reverted = meetings.RevertDictionary(meeting);
                return string.Format(Strings.Meeting_Dictionary_Reverted, reverted.Changed);
            }
            var outcome = meetings.ApplyDictionary(meeting);
            return outcome.Changed > 0
                ? string.Format(Strings.Meeting_Dictionary_Applied, outcome.Changed)
                : string.Format(Strings.Meeting_Dictionary_AppliedNone, outcome.Replaced);
        }
        catch (MeetingDictionaryException e)
        {
            return e.Message;
        }
    }
}
