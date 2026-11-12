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

    /// <param name="note">入れ替えの前に知らせること（動いている hanasu を終わらせる。REQ-REL-013）。なければ null</param>
    public UpdatePromptWindow(AppVersion current, ReleaseInfo release, bool canInstall, string? note = null)
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
        if (note is not null)
        {
            panel.Children.Add(new TextBlock
            {
                Text = note,
                Margin = new Thickness(0, 8, 0, 0),
                TextWrapping = TextWrapping.Wrap,
                FontWeight = FontWeights.SemiBold,
            });
        }

        // アプリの機能の節と Windows の項目だけ出す（全文は「リリースのページを開く」で読む）
        var notes = ReleaseNotesFormatter.Parse(ReleaseNotesFormatter.ForApp(release.Notes, ReleasePlatform.Windows));
        if (notes.Count > 0)
        {
            // 切り詰めずに全文を出し、長ければ欄の中でスクロールする（開いたときは先頭が見える）。
            // 読み取り専用の RichTextBox なので、選んでコピーできる。IsDocumentEnabled でリンクを押せる
            panel.Children.Add(new RichTextBox
            {
                Document = ReleaseNotesDocument(notes),
                IsReadOnly = true,
                IsDocumentEnabled = true,
                AcceptsReturn = false,
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
                MaxHeight = 320,
                Padding = new Thickness(6, 6, 6, 6),
                Margin = new Thickness(0, 10, 0, 0),
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
    /// 箇条書きは段落の左を「字下げ＋印の幅」だけ空け、1 行目だけ印の幅を戻す（TextIndent を負に）ので、折り返した行も本文の頭にそろう
    /// </summary>
    private static FlowDocument ReleaseNotesDocument(IReadOnlyList<ReleaseNotesBlock> blocks)
    {
        var document = new FlowDocument
        {
            PagePadding = new Thickness(0),
            FontFamily = SystemFonts.MessageFontFamily,
            FontSize = BodySize,
        };
        foreach (var block in blocks)
        {
            var paragraph = new Paragraph();
            if (block.Kind == ReleaseNotesBlockKind.Heading)
            {
                paragraph.FontWeight = FontWeights.Bold;
                paragraph.FontSize = block.HeadingLevel switch { 1 => BodySize + 4, 2 => BodySize + 2, _ => BodySize };
            }
            var spacing = document.Blocks.Count == 0 ? 0 : block.Kind switch
            {
                ReleaseNotesBlockKind.Heading => 12,
                ReleaseNotesBlockKind.Bullet or ReleaseNotesBlockKind.Numbered => block.AfterBlank ? 6 : 3,
                _ => block.AfterBlank ? 6 : 0,
            };
            var left = 0.0;
            if (block.Marker is not null)
            {
                left = block.Level * IndentPerLevel + MarkerWidth;
                paragraph.TextIndent = -MarkerWidth;
                // 印は幅を決めた箱に入れ、本文の頭を印の幅の位置にそろえる。下端を字の下端に合わせて、本文と同じ行の高さに置く
                paragraph.Inlines.Add(new InlineUIContainer(new TextBlock
                {
                    Text = block.Marker,
                    Width = MarkerWidth,
                    FontSize = BodySize,
                    Foreground = SystemColors.GrayTextBrush,
                })
                { BaselineAlignment = BaselineAlignment.TextBottom });
            }
            paragraph.Margin = new Thickness(left, spacing, 0, 0);
            foreach (var piece in block.Inlines) paragraph.Inlines.Add(MakeInline(piece));
            document.Blocks.Add(paragraph);
        }
        return document;
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
