using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using Hanasu.Core.Meetings;
using Hanasu.Core.Update;

namespace Hanasu.Windows.Views;

/// <summary>
/// アップデートの zip のダウンロードの進み具合。見出し・バー・「45% (12 MB / 27 MB)」・「中止」。
/// ダウンロードが終わると、展開の間はバーを不定にし、「中止」を押せなくする。
/// 前面に固定せず、最小化できる。閉じる操作は、ダウンロード中なら「中止」と同じで、展開の間は取り消す
/// </summary>
// 要件: REQ-REL-012
// 設計判断: DEC-REL-028
internal sealed class UpdateProgressWindow : Window
{
    private readonly ProgressBar bar;
    private readonly TextBlock status;
    private readonly Button cancel;
    private bool preparing;
    private bool closingByCode;
    private bool closed;

    /// <summary>「中止」（か、ダウンロード中に閉じる操作）を選んだ。1 回だけ</summary>
    public event EventHandler? CancelRequested;
    private bool cancelRaised;

    public UpdateProgressWindow(AppVersion version, long total)
    {
        Title = Strings.Update_Downloading;
        SizeToContent = SizeToContent.Height;
        Width = 420;
        ResizeMode = ResizeMode.CanMinimize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        ShowInTaskbar = true;

        var panel = new StackPanel { Margin = new Thickness(16) };
        panel.Children.Add(new TextBlock
        {
            Text = string.Format(Strings.Update_DownloadingHeading, version),
            FontSize = 14,
            FontWeight = FontWeights.SemiBold,
            TextWrapping = TextWrapping.Wrap,
        });
        bar = new ProgressBar { Minimum = 0, Maximum = 1, Height = 8, Margin = new Thickness(0, 12, 0, 0) };
        panel.Children.Add(bar);
        status = new TextBlock
        {
            Margin = new Thickness(0, 6, 0, 0),
            Foreground = SystemColors.GrayTextBrush,
            TextWrapping = TextWrapping.Wrap,
        };
        // 数字の幅がそろい、増えても字が揺れないように
        Typography.SetNumeralAlignment(status, FontNumeralAlignment.Tabular);
        panel.Children.Add(status);
        cancel = new Button
        {
            Content = Strings.Update_Cancel,
            IsCancel = true,
            MinWidth = 80,
            Padding = new Thickness(12, 3, 12, 3),
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(0, 16, 0, 0),
        };
        cancel.Click += (_, _) => RaiseCancel();
        panel.Children.Add(cancel);
        Content = panel;
        SetProgress(0, total);
    }

    /// <summary>落とした量を出す（UI のスレッドから呼ぶ）</summary>
    public void SetProgress(long received, long total)
    {
        if (preparing) return;
        bar.Value = UpdateDownloadProgress.Fraction(received, total);
        status.Text = string.Format(Strings.Update_Progress,
            UpdateDownloadProgress.Percent(received, total),
            MeetingAudioCleanup.FormatSize(Math.Clamp(received, 0, Math.Max(0, total))),
            MeetingAudioCleanup.FormatSize(total));
    }

    /// <summary>ダウンロードが終わり、展開しているところにする（「中止」は押せない）</summary>
    public void SetPreparing()
    {
        preparing = true;
        bar.IsIndeterminate = true;
        status.Text = Strings.Update_PreparingBody;
        cancel.IsEnabled = false;
    }

    /// <summary>コードから閉じる（どの終わり方でも呼ぶ。2 回呼んでもよい）</summary>
    public void CloseForGood()
    {
        if (closed) return;
        closingByCode = true;
        Close();
    }

    protected override void OnClosed(EventArgs e)
    {
        closed = true;
        base.OnClosed(e);
    }

    protected override void OnClosing(CancelEventArgs e)
    {
        if (!closingByCode)
        {
            // 閉じる操作は、ダウンロード中なら「中止」と同じ。展開の間は数秒で終わるので閉じさせない
            e.Cancel = true;
            if (!preparing) RaiseCancel();
        }
        base.OnClosing(e);
    }

    private void RaiseCancel()
    {
        if (cancelRaised || preparing) return;
        cancelRaised = true;
        cancel.IsEnabled = false;
        CancelRequested?.Invoke(this, EventArgs.Empty);
    }
}
