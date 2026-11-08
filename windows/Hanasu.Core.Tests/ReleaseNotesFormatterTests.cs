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

    private static string ReleaseDoc(string name)
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null && !File.Exists(Path.Combine(dir.FullName, "docs", "releases", name))) dir = dir.Parent;
        Assert.NotNull(dir);
        return File.ReadAllText(Path.Combine(dir.FullName, "docs", "releases", name));
    }

    [Fact]
    public void ReleaseTemplateShowsOnlyHeadings()
    {
        // docs/releases/TEMPLATE.md をそのまま出しても、コメント（書き方の説明）は出ない
        var blocks = ReleaseNotesFormatter.Parse(ReleaseDoc("TEMPLATE.md"));
        Assert.NotEmpty(blocks);
        Assert.All(blocks, b => Assert.Equal(ReleaseNotesBlockKind.Heading, b.Kind));
    }

    // MARK: - アプリに出す分だけにする

    [Fact]
    public void ForAppKeepsOnlyAppSectionsAndWindowsItems()
    {
        var notes = ReleaseNotesFormatter.ForApp(ReleaseDoc("v2.0.1.md"), ReleasePlatform.Windows);
        var blocks = ReleaseNotesFormatter.Parse(notes);
        var headings = blocks.Where(b => b.Kind == ReleaseNotesBlockKind.Heading).Select(b => b.PlainText).ToList();
        // 「不具合の修正」は（Mac）の項目だけなので、見出しごと消える
        Assert.Equal(["ハイライト", "改善"], headings);
        Assert.DoesNotContain("気をつけること", notes);
        Assert.DoesNotContain("アップデートのしかた", notes);
        Assert.DoesNotContain("（Mac）", notes);
        Assert.DoesNotContain("韓国語", notes);
        var bullet = Assert.Single(blocks, b => b.Kind == ReleaseNotesBlockKind.Bullet);
        Assert.StartsWith("設定の「AI」の選択肢を", bullet.PlainText);
        Assert.EndsWith("選んでいた AI はそのままです。", bullet.PlainText);
    }

    [Fact]
    public void ForAppOnMacKeepsMacItems()
    {
        var notes = ReleaseNotesFormatter.ForApp(ReleaseDoc("v2.0.1.md"), ReleasePlatform.Mac);
        Assert.Contains("## 不具合の修正", notes);
        Assert.Contains("画面全体が崩れていました。", notes);
        Assert.DoesNotContain("（Mac", notes);
        Assert.DoesNotContain("気をつけること", notes);
    }

    [Fact]
    public void ForAppWithoutAppSectionsKeepsEverything()
    {
        const string notes = "## 変更\n\n- Mac だけの項目（Mac）\n\n## 気をつけること\n\n- 注意";
        Assert.Equal(notes, ReleaseNotesFormatter.ForApp(notes, ReleasePlatform.Windows));
    }

    [Fact]
    public void ForAppDropsDeeperLinesUnderOtherPlatformItems()
    {
        const string notes = """
            前置きの文。

            ## 新しい機能

            - **会議**: 録れるようになりました (Mac)
              - 細かい点
                - さらに細かい点
            - 共通の項目 ( Mac/Windows ).
              - 共通の細かい点
            ### 小見出し
            - Windows の項目（Windows）

            ## その他

            - 出さない
            """;
        Assert.Equal(
            "前置きの文。\n\n## 新しい機能\n\n- 共通の項目.\n  - 共通の細かい点\n### 小見出し\n- Windows の項目",
            ReleaseNotesFormatter.ForApp(notes, ReleasePlatform.Windows));
    }

    /// <summary>Mac の見本（AppUpdateCLI.selfTest の「ダイアログに出す分に絞る」）と同じ本文</summary>
    private const string SharedSample = """
        ## ハイライト

        設定の直しの版です。

        ## 改善

        - 両方の直し（Mac / Windows）。
        - Windows だけの直し（Windows）。
          - その続き
        - Mac だけの直し（Mac）。

        ## 不具合の修正

        - Windows だけの不具合（Windows）。

        ## 気をつけること

        - 実機ではまだ確かめていません。

        ## アップデートのしかた

        下のインストールの手順のとおりに入れ替えてください。
        """;

    [Fact]
    public void ForAppMatchesTheMacSample()
    {
        Assert.Equal("## ハイライト\n\n設定の直しの版です。\n\n## 改善\n\n- 両方の直し。\n- Mac だけの直し。",
            ReleaseNotesFormatter.ForApp(SharedSample, ReleasePlatform.Mac));
        Assert.Equal("## ハイライト\n\n設定の直しの版です。\n\n## 改善\n\n- 両方の直し。\n- Windows だけの直し。\n  - その続き\n\n## 不具合の修正\n\n- Windows だけの不具合。",
            ReleaseNotesFormatter.ForApp(SharedSample, ReleasePlatform.Windows));
        Assert.Equal("## What's Changed\n- a（Mac）", ReleaseNotesFormatter.ForApp("## What's Changed\n- a（Mac）", ReleasePlatform.Windows));
    }

    [Fact]
    public void ForAppKeepsDroppingDeeperLinesAcrossBlankLines()
    {
        const string notes = "## 改善\n\n- Mac の項目（Mac）\n\n  - 続きの段落\n- 共通（Mac / Windows）";
        Assert.Equal("## 改善\n\n- 共通", ReleaseNotesFormatter.ForApp(notes, ReleasePlatform.Windows));
    }
}
