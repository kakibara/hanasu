using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Media;
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
/// ウインドウを閉じたときは「あとで」と同じ。リリースのページへのリンクと、リリースの本文（整えて全文。DEC-REL-027）を付ける。
/// </summary>
// 設計判断: DEC-REL-022
internal sealed class UpdatePromptWindow : Window
{
    public UpdateChoice Choice { get; private set; } = UpdateChoice.Later;

    public UpdatePromptWindow(AppVersion current, ReleaseInfo release, bool canInstall)
    {
        Title = Strings.UpdatePrompt_Title;
        SizeToContent = SizeToContent.Height;
        Width = 460;
        MaxHeight = 680;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        ShowInTaskbar = true;
        Topmost = true;

        var panel = new StackPanel { Margin = new Thickness(16) };
        panel.Children.Add(new TextBlock
        {
            Text = string.Format(Strings.UpdatePrompt_Available, release.Version, current),
            FontSize = 16,
            FontWeight = FontWeights.SemiBold,
            TextWrapping = TextWrapping.Wrap,
        });
        panel.Children.Add(new TextBlock
        {
            Text = canInstall
                ? Strings.UpdatePrompt_CanInstall
                : Strings.UpdatePrompt_CannotInstall,
            Margin = new Thickness(0, 8, 0, 0),
            TextWrapping = TextWrapping.Wrap,
        });

        var notes = ReleaseNotesFormatter.Parse(release.Notes);
        if (notes.Count > 0)
        {
            // 切り詰めずに全文を出し、長ければスクロールする（開いたときは先頭が見える）
            panel.Children.Add(new Border
            {
                BorderBrush = SystemColors.ActiveBorderBrush,
                BorderThickness = new Thickness(1),
                Margin = new Thickness(0, 10, 0, 0),
                Child = new ScrollViewer
                {
                    Content = ReleaseNotesView(notes),
                    VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                    HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
                    MaxHeight = 320,
                    Padding = new Thickness(10, 8, 10, 8),
                },
            });
        }

        var link = new Button
        {
            Content = Strings.UpdatePrompt_OpenReleasePage,
            HorizontalAlignment = HorizontalAlignment.Left,
            Padding = new Thickness(8, 3, 8, 3),
            Margin = new Thickness(0, 10, 0, 0),
        };
        link.Click += (_, _) => Shell.Open(release.ReleaseUrl.AbsoluteUri);
        panel.Children.Add(link);

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 16, 0, 0) };
        buttons.Children.Add(MakeButton(canInstall ? Strings.UpdatePrompt_Update : Strings.UpdatePrompt_OpenPage, UpdateChoice.Update, isDefault: true));
        buttons.Children.Add(MakeButton(Strings.UpdatePrompt_Later, UpdateChoice.Later, isCancel: true));
        buttons.Children.Add(MakeButton(Strings.UpdatePrompt_Skip, UpdateChoice.Skip));
        panel.Children.Add(buttons);
        Content = panel;
    }

    private const double BodySize = 13;
    private const double IndentPerLevel = 14;
    private const double MarkerWidth = 16;

    // 設計判断: DEC-REL-027
    /// <summary>
    /// リリース文を、見出しは太い大きめの字、箇条書きは印のあとを字下げして折り返し、太字・斜体・コード・リンクは字の形にして並べる。
    /// 印と本文を別の列に置くので、折り返した行も本文の頭にそろう
    /// </summary>
    private static StackPanel ReleaseNotesView(IReadOnlyList<ReleaseNotesBlock> blocks)
    {
        var stack = new StackPanel();
        foreach (var block in blocks)
        {
            var text = new TextBlock { TextWrapping = TextWrapping.Wrap, FontSize = BodySize };
            if (block.Kind == ReleaseNotesBlockKind.Heading)
            {
                text.FontWeight = FontWeights.Bold;
                text.FontSize = block.HeadingLevel switch { 1 => BodySize + 4, 2 => BodySize + 2, _ => BodySize };
            }
            foreach (var piece in block.Inlines) text.Inlines.Add(MakeInline(piece));

            var spacing = stack.Children.Count == 0 ? 0 : block.Kind switch
            {
                ReleaseNotesBlockKind.Heading => 12,
                ReleaseNotesBlockKind.Bullet or ReleaseNotesBlockKind.Numbered => block.AfterBlank ? 6 : 3,
                _ => block.AfterBlank ? 6 : 0,
            };
            if (block.Marker is null)
            {
                text.Margin = new Thickness(0, spacing, 0, 0);
                stack.Children.Add(text);
                continue;
            }
            var row = new Grid { Margin = new Thickness(block.Level * IndentPerLevel, spacing, 0, 0) };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(MarkerWidth) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var marker = new TextBlock { Text = block.Marker, FontSize = BodySize, Foreground = SystemColors.GrayTextBrush };
            Grid.SetColumn(marker, 0);
            Grid.SetColumn(text, 1);
            row.Children.Add(marker);
            row.Children.Add(text);
            stack.Children.Add(row);
        }
        return stack;
    }

    private static Inline MakeInline(ReleaseNotesInline piece)
    {
        var run = new Run(piece.Text);
        if (piece.Style.HasFlag(ReleaseNotesStyle.Bold)) run.FontWeight = FontWeights.Bold;
        if (piece.Style.HasFlag(ReleaseNotesStyle.Italic)) run.FontStyle = FontStyles.Italic;
        if (piece.Style.HasFlag(ReleaseNotesStyle.Code))
        {
            run.FontFamily = new FontFamily("Consolas, Courier New");
            run.FontSize = BodySize - 1;
        }
        if (piece.Link is not { } uri) return run;
        // Core が http / https だけを渡す
        var link = new Hyperlink(run) { NavigateUri = uri, ToolTip = uri.AbsoluteUri };
        link.Click += (_, _) => Shell.Open(uri.AbsoluteUri);
        return link;
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
