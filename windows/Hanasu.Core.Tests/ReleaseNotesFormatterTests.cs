using Hanasu.Core.Update;

namespace Hanasu.Core.Tests;

// 確かめ方: REQ-REL-010, REQ-REL-011
// 設計判断: DEC-REL-027
public class ReleaseNotesFormatterTests
{
    private static ReleaseNotesInline Plain(string text) => new(text, ReleaseNotesStyle.None);

    [Fact]
    public void HeadingsBulletsNumbersAndParagraphs()
    {
        var blocks = ReleaseNotesFormatter.Parse("## 改善\n\n- **太字**の項目\n1. 番号\n\nふつうの文");
        Assert.Equal(4, blocks.Count);

        Assert.Equal(ReleaseNotesBlockKind.Heading, blocks[0].Kind);
        Assert.Equal(2, blocks[0].HeadingLevel);
        Assert.Equal("改善", blocks[0].PlainText);
        Assert.Null(blocks[0].Marker);

        Assert.Equal(ReleaseNotesBlockKind.Bullet, blocks[1].Kind);
        Assert.Equal("•", blocks[1].Marker);
        Assert.True(blocks[1].AfterBlank);
        Assert.Equal([new ReleaseNotesInline("太字", ReleaseNotesStyle.Bold), Plain("の項目")], blocks[1].Inlines);

        Assert.Equal(ReleaseNotesBlockKind.Numbered, blocks[2].Kind);
        Assert.Equal("1.", blocks[2].Marker);
        Assert.False(blocks[2].AfterBlank);
        Assert.Equal("番号", blocks[2].PlainText);

        Assert.Equal(ReleaseNotesBlockKind.Paragraph, blocks[3].Kind);
        Assert.True(blocks[3].AfterBlank);
        Assert.Equal("ふつうの文", blocks[3].PlainText);
    }

    [Fact]
    public void NumbersAreKeptAsWritten()
    {
        var blocks = ReleaseNotesFormatter.Parse("3) 三つめ\n10. 十番め");
        Assert.Equal(["3.", "10."], blocks.Select(b => b.Marker));
        Assert.Equal(["三つめ", "十番め"], blocks.Select(b => b.PlainText));
    }

    [Fact]
    public void NestedItemsAreIndented()
    {
        var blocks = ReleaseNotesFormatter.Parse("- 上\n  - 下\n    * さらに下\n\t+ タブ");
        Assert.Equal([0, 1, 2, 2], blocks.Select(b => b.Level));
        Assert.All(blocks, b => Assert.Equal("•", b.Marker));
    }

    [Fact]
    public void HtmlCommentsAreHidden()
    {
        var blocks = ReleaseNotesFormatter.Parse("<!-- release-notes -->\n## 新しい機能\n\n<!--\n- テンプレートの説明\n-->\n- 本当の項目 <!-- 補足 -->\n<!-- /release-notes -->");
        Assert.Equal(["新しい機能", "本当の項目"], blocks.Select(b => b.PlainText));
    }

    [Fact]
    public void NotAHeadingOrBulletWithoutSpace()
    {
        var blocks = ReleaseNotesFormatter.Parse("#タグ\n-1 度\n2.5 倍");
        Assert.All(blocks, b => Assert.Equal(ReleaseNotesBlockKind.Paragraph, b.Kind));
        Assert.Equal(["#タグ", "-1 度", "2.5 倍"], blocks.Select(b => b.PlainText));
    }

    [Fact]
    public void InlineStyles()
    {
        Assert.Equal(
            [Plain("a "), new("b", ReleaseNotesStyle.Italic), Plain(" "), new("c", ReleaseNotesStyle.Bold), Plain(" "),
             new("d", ReleaseNotesStyle.Bold | ReleaseNotesStyle.Italic), Plain(" "), new("e", ReleaseNotesStyle.Code)],
            ReleaseNotesFormatter.ParseInline("a *b* **c** ***d*** `e`"));
        Assert.Equal(
            [new("x ", ReleaseNotesStyle.Bold), new("y", ReleaseNotesStyle.Bold | ReleaseNotesStyle.Italic), new(" z", ReleaseNotesStyle.Bold)],
            ReleaseNotesFormatter.ParseInline("__x _y_ z__"));
    }

    [Fact]
    public void CodeIsNotInterpreted()
    {
        Assert.Equal([Plain("設定 "), new("**not bold**", ReleaseNotesStyle.Code)], ReleaseNotesFormatter.ParseInline("設定 `**not bold**`"));
        Assert.Equal([new("a`b", ReleaseNotesStyle.Code)], ReleaseNotesFormatter.ParseInline("`` a`b ``"));
    }

    [Theory]
    [InlineData("snake_case_name")]
    [InlineData("2 * 3 * 4")]
    [InlineData("**閉じていない")]
    [InlineData("`閉じていない")]
    [InlineData("[リンクでない]")]
    public void UnmatchedMarksStayAsText(string text)
    {
        Assert.Equal([Plain(text)], ReleaseNotesFormatter.ParseInline(text));
    }

    [Fact]
    public void EscapedMarksAreText()
    {
        Assert.Equal([Plain("*星* と [角]")], ReleaseNotesFormatter.ParseInline(@"\*星\* と \[角]"));
    }

    [Fact]
    public void LinksKeepTheirLabelAndOnlyHttpIsClickable()
    {
        var inlines = ReleaseNotesFormatter.ParseInline("[ページ](https://github.com/kakibara/hanasu \"題\") と [**太い**](https://example.com/a)");
        Assert.Equal("ページ と 太い", string.Concat(inlines.Select(i => i.Text)));
        Assert.Equal(new Uri("https://github.com/kakibara/hanasu"), inlines[0].Link);
        Assert.Equal(new ReleaseNotesInline("太い", ReleaseNotesStyle.Bold, new Uri("https://example.com/a")), inlines[2]);

        var unsafeLinks = ReleaseNotesFormatter.ParseInline("[開く](file:///C:/Windows/System32/calc.exe) [相対](docs/a.md)");
        Assert.Equal([Plain("開く 相対")], unsafeLinks);
    }

    [Fact]
    public void WindowsLineEndingsAndHeadingClosingHashes()
    {
        var blocks = ReleaseNotesFormatter.Parse("# 題 #\r\n- 項目\r\n");
        Assert.Equal(["題", "項目"], blocks.Select(b => b.PlainText));
        Assert.Equal(1, blocks[0].HeadingLevel);
    }

    [Theory]
    [InlineData("## Swift と C#", "Swift と C#")]
    [InlineData("## 見出し ##", "見出し")]
    [InlineData("### F# と C# ###", "F# と C#")]
    [InlineData("## 番号 #5", "番号 #5")]
    public void OnlyClosingHashesAfterASpaceAreRemoved(string line, string expected)
    {
        var block = Assert.Single(ReleaseNotesFormatter.Parse(line));
        Assert.Equal(ReleaseNotesBlockKind.Heading, block.Kind);
        Assert.Equal(expected, block.PlainText);
    }

    [Fact]
    public void ReleaseTemplateShowsOnlyHeadings()
    {
        // docs/releases/TEMPLATE.md をそのまま出しても、コメント（書き方の説明）は出ない
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null && !File.Exists(Path.Combine(dir.FullName, "docs", "releases", "TEMPLATE.md"))) dir = dir.Parent;
        Assert.NotNull(dir);
        var path = Path.Combine(dir.FullName, "docs", "releases", "TEMPLATE.md");
        var blocks = ReleaseNotesFormatter.Parse(File.ReadAllText(path));
        Assert.NotEmpty(blocks);
        Assert.All(blocks, b => Assert.Equal(ReleaseNotesBlockKind.Heading, b.Kind));
    }
}
