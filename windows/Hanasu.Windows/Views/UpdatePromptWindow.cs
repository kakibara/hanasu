using System.Windows;
using System.Windows.Controls;
using Hanasu.Core.Update;
using Hanasu.Windows.Services;

namespace Hanasu.Windows.Views;

/// <summary>更新の確認で選べるもの</summary>
internal enum UpdateChoice
{
    /// <summary>アップデートする（インストールできないときは、リリースのページを開く）</summary>
    Update,
    /// <summary>あとで（次の起動でまた知らせる）</summary>
    Later,
    /// <summary>この版をスキップ（起動時には、この版を知らせない）</summary>
    Skip,
}

/// <summary>
/// 「Hanasu 1.6.0 があります（今は 1.5.0）」の確認。アップデート / あとで / この版をスキップ から選ぶ。
/// ウインドウを閉じたときは「あとで」と同じ。リリースのページへのリンクと、リリースの本文を付ける。
/// </summary>
// 設計判断: DEC-REL-022
internal sealed class UpdatePromptWindow : Window
{
    public UpdateChoice Choice { get; private set; } = UpdateChoice.Later;

    public UpdatePromptWindow(AppVersion current, ReleaseInfo release, bool canInstall)
    {
        Title = "Hanasu のアップデート";
        SizeToContent = SizeToContent.Height;
        Width = 460;
        MaxHeight = 560;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        ShowInTaskbar = true;
        Topmost = true;

        var panel = new StackPanel { Margin = new Thickness(16) };
        panel.Children.Add(new TextBlock
        {
            Text = $"Hanasu {release.Version} があります（今は {current}）",
            FontSize = 16,
            FontWeight = FontWeights.SemiBold,
            TextWrapping = TextWrapping.Wrap,
        });
        panel.Children.Add(new TextBlock
        {
            Text = canInstall
                ? "「アップデート」を押すと、新しい版をダウンロードして入れ替え、Hanasu を起動し直します。"
                : "この版は、アプリの中からは入れられません。リリースのページから入れてください。",
            Margin = new Thickness(0, 8, 0, 0),
            TextWrapping = TextWrapping.Wrap,
        });

        var notes = release.Notes.Trim();
        if (notes.Length > 0)
        {
            if (notes.Length > 800) notes = notes[..800] + "…";
            panel.Children.Add(new TextBox
            {
                Text = notes,
                IsReadOnly = true,
                TextWrapping = TextWrapping.Wrap,
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                MaxHeight = 220,
                Margin = new Thickness(0, 10, 0, 0),
            });
        }

        var link = new Button
        {
            Content = "リリースのページを開く",
            HorizontalAlignment = HorizontalAlignment.Left,
            Padding = new Thickness(8, 3, 8, 3),
            Margin = new Thickness(0, 10, 0, 0),
        };
        link.Click += (_, _) => Shell.Open(release.ReleaseUrl.AbsoluteUri);
        panel.Children.Add(link);

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 16, 0, 0) };
        buttons.Children.Add(MakeButton(canInstall ? "アップデート" : "ページを開く", UpdateChoice.Update, isDefault: true));
        buttons.Children.Add(MakeButton("あとで", UpdateChoice.Later, isCancel: true));
        buttons.Children.Add(MakeButton("この版をスキップ", UpdateChoice.Skip));
        panel.Children.Add(buttons);
        Content = panel;
    }

    private Button MakeButton(string text, UpdateChoice choice, bool isDefault = false, bool isCancel = false)
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
            Choice = choice;
            DialogResult = true;
        };
        return button;
    }
}
