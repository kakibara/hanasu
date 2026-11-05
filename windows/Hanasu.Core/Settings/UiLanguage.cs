using System.Globalization;
using Hanasu.Core.Ai;

namespace Hanasu.Core.Settings;

// 要件: REQ-COM-060
// 設計判断: DEC-COM-167
/// <summary>
/// 表示の言語（UI の文字列。Properties/Strings.resx と各言語の Strings.&lt;カルチャ&gt;.resx）。
/// Windows の表示の言語（CultureInfo.CurrentUICulture）が対応言語（REQ-COM-061 と同じ 17 言語）のどれかならその言語、どれでもなければ英語にする。
/// 起動のとき、ウインドウを作る前に Apply を 1 回呼ぶ
/// </summary>
public static class UiLanguage
{
    private static string? systemCultureName;

    /// <summary>Apply で置き換える前の、Windows の表示の言語の名前（"ja-JP"、"sv-SE" など）。Apply の前は今の UI のカルチャ</summary>
    public static string SystemCultureName => systemCultureName ?? CultureInfo.CurrentUICulture.Name;

    /// <summary>
    /// 表示に使うカルチャを決める。カルチャとその親をたどり、対応言語に当たればそれを使う。
    /// 中国語は繁体字（Hant）か台湾・香港・マカオなら zh-TW、それ以外は zh-CN、ポルトガル語は pt-BR に寄せる（訳がその地域のものなので）。
    /// ほかの言語は、地域つきのカルチャ（ja-JP・en-GB など）をそのまま使う。どれでもなければ英語（en）
    /// </summary>
    public static CultureInfo Resolve(CultureInfo system)
    {
        for (var c = system; !string.IsNullOrEmpty(c.Name); c = c.Parent)
        {
            if (PromptLanguage.SupportedOrNull(c.Name) is not { } language) continue;
            // 中国語とポルトガル語は、訳の地域のカルチャにする（zh-HK → zh-TW、zh-SG → zh-CN、pt-PT → pt-BR）
            if (language == PromptLanguage.ZhCN || language == PromptLanguage.ZhTW || language == PromptLanguage.PtBR)
            {
                return CultureInfo.GetCultureInfo(language.Code);
            }
            return c;
        }
        return CultureInfo.GetCultureInfo("en");
    }

    /// <summary>
    /// Windows の表示の言語から表示のカルチャを決め、このプロセスの UI のカルチャ（今のスレッドと、これから作るスレッド）にする。
    /// 決める前の言語は SystemCultureName に残す（文字起こしの言語の初期値に使う。REQ-COM-004）
    /// </summary>
    public static CultureInfo Apply()
    {
        var system = CultureInfo.CurrentUICulture;
        systemCultureName ??= system.Name;
        var resolved = Resolve(system);
        CultureInfo.DefaultThreadCurrentUICulture = resolved;
        CultureInfo.CurrentUICulture = resolved;
        return resolved;
    }
}
