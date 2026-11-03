using Hanasu.Core.Text;

namespace Hanasu.Core.Tests;

// Mac 版の UserDictionarySelfTest.swift と同じ振る舞いになっているかを確かめる
public class UserDictionaryTests
{
    [Fact]
    public void ParsesWordsRulesAndComments()
    {
        var d = new UserDictionary("Stockmark\nストックマーク => Stockmark\n# メモ\n\nえーにゅーす, エーニュース => Anews\nジェミニ＝＞Gemini\nはなす→Hanasu");
        Assert.Equal(7, d.Lines.Count);
        Assert.Equal(["Stockmark", "Anews", "Gemini", "Hanasu"], d.Spellings);
        Assert.Equal(4, d.Rules.Count);
        Assert.Equal(["えーにゅーす", "エーニュース"], d.Rules[1].Sources);
        Assert.Contains("えーにゅーす", d.ContextualStrings);
    }

    [Fact]
    public void TextRoundTripsKeepingComments()
    {
        var d = new UserDictionary("# コメント\nストックマーク=>Stockmark\n\nHanasu");
        Assert.Equal("# コメント\nストックマーク => Stockmark\n\nHanasu", d.Text);
    }

    [Theory]
    [InlineData("ストックマーク => Stockmark", "ストックマークの話", "Stockmarkの話")]
    // 全角・半角、大文字小文字、空白の有無は区別しない
    [InlineData("ストックマーク => Stockmark", "ｽﾄｯｸﾏｰｸの話", "Stockmarkの話")]
    [InlineData("vertex ai => Vertex AI", "ＶＥＲＴＥＸ　ＡＩを使う", "Vertex AIを使う")]
    [InlineData("vertex ai => Vertex AI", "vertexaiを使う", "Vertex AIを使う")]
    // 英数字の途中では置き換えない
    [InlineData("ai => AI", "OpenAIとaiの話", "OpenAIとAIの話")]
    // カタカナの途中では置き換えない
    [InlineData("マーク => Mark", "マークダウンとストックマークとマーク", "マークダウンとストックマークとMark")]
    // ひらがなとカタカナは区別する
    [InlineData("ストックマーク => Stockmark", "すとっくまーく", "すとっくまーく")]
    // 1 文字のルールは使わない
    [InlineData("字 => 時", "文字", "文字")]
    public void AppliesRules(string dictionary, string input, string expected)
    {
        Assert.Equal(expected, new UserDictionary(dictionary).Apply(input));
    }

    [Fact]
    public void PrefersLongerMatchAndDoesNotReapply()
    {
        var d = new UserDictionary("じぇみに => Gemini\nじぇみにふらっしゅ => Gemini Flash\nGemini => ジェミニ");
        Assert.Equal("Gemini Flashとジェミニ", d.Apply("じぇみにふらっしゅとGemini"));
    }

    [Fact]
    public void ReportsIssues()
    {
        var d = new UserDictionary("字 => 時\nえーにゅーす => Anews\nえーにゅーす => A News\nほげ => ");
        var issues = d.Issues;
        Assert.Contains("1 文字", issues[0]);
        Assert.Contains("上の行", issues[2]);
        Assert.Contains("空", issues[3]);
        Assert.False(issues.ContainsKey(1));
    }

    [Fact]
    public void LogsReplacements()
    {
        var (text, log) = new UserDictionary("ジェミニ => Gemini").ApplyWithLog("ジェミニとジ ェミニ");
        Assert.Equal("GeminiとGemini", text);
        Assert.Equal(2, log.Count);
        Assert.Equal("ジ ェミニ", log[1].Matched);
    }
}
