using System.Windows;
using System.Windows.Controls;

namespace Hanasu.Windows.Views;

// 要件: REQ-MTG-043
// 設計判断: DEC-MTG-111
/// <summary>
/// 会議の記録中にスリープして戻ったときの確認。「スリープ前までで止める」（既定）か「記録を続ける」を選ぶ。
/// ウインドウを閉じたときは、録った音声を失わない「記録を続ける」と同じ。
/// </summary>
internal sealed class SleepPromptWindow : Window
{
    public bool StopAtSleep { get; private set; }

    public SleepPromptWindow(DateTimeOffset sleptAt)
    {
        Title = Strings.SleepPrompt_Title;
        SizeToContent = SizeToContent.Height;
        Width = 460;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        ShowInTaskbar = true;
        Topmost = true;

        var panel = new StackPanel { Margin = new Thickness(16) };
        panel.Children.Add(new TextBlock
        {
            Text = Strings.SleepPrompt_Heading,
            FontSize = 16,
            FontWeight = FontWeights.SemiBold,
            TextWrapping = TextWrapping.Wrap,
        });
        panel.Children.Add(new TextBlock
        {
            Text = string.Format(Strings.SleepPrompt_Body, sleptAt.ToLocalTime().ToString("t")),
            Margin = new Thickness(0, 8, 0, 0),
            TextWrapping = TextWrapping.Wrap,
        });

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 16, 0, 0) };
        buttons.Children.Add(MakeButton(Strings.SleepPrompt_Stop, stop: true, isDefault: true));
        buttons.Children.Add(MakeButton(Strings.SleepPrompt_Continue, stop: false, isCancel: true));
        panel.Children.Add(buttons);
        Content = panel;
    }

    private Button MakeButton(string text, bool stop, bool isDefault = false, bool isCancel = false)
    {
        var button = new Button
        {
            Content = text,
            Padding = new Thickness(12, 4, 12, 4),
            Margin = new Thickness(8, 0, 0, 0),
            IsDefault = isDefault,
            IsCancel = isCancel,
        };
        button.Click += (_, _) =>
        {
            StopAtSleep = stop;
            DialogResult = true;
        };
        return button;
    }
}
