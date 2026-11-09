using System.Text.RegularExpressions;

namespace Hanasu.Core.Ai;

/// <summary>
/// プロンプトに埋め込む、ユーザーの文章（文字起こし・メモ）の下ごしらえ。
/// 文章の中に「&lt;/transcript&gt;」などの区切りのタグがあると、区切りの外に指示を書けてしまうので、
/// 区切りに使うタグだけを全角の山かっこに置き換える（見た目の意味は変わらない）。Gemini と Claude の両方に効く。
/// </summary>
// 設計判断: DEC-COM-142, DEC-DIC-170
// 辞書の候補（DictionarySuggester）の材料を囲む `<material>` も対象にする。
public static partial class PromptText
{
    [GeneratedRegex(@"<\s*(/?)\s*(transcript|user_notes|action_items|speaker_names|material)\s*>", RegexOptions.IgnoreCase)]
    private static partial Regex DelimiterTag();

    public static string NeutralizeDelimiters(string text) =>
        DelimiterTag().Replace(text, m => $"＜{m.Groups[1].Value}{m.Groups[2].Value}＞");
}
