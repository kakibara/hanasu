using System.Text.RegularExpressions;

namespace Hanasu.Core;

/// <summary>
/// ログに書く文字列から、API キー・トークンに見えるものを伏せる。キーをログに出さない作りにしたうえでの、念のための守り。
/// - Anthropic の API キー（sk-ant-…）、Google の API キー（AIza…）、OAuth のアクセストークン（ya29.…）、Bearer の値、x-api-key の値
/// </summary>
// 設計判断: DEC-COM-147
public static partial class SecretRedactor
{
    [GeneratedRegex(@"sk-ant-[A-Za-z0-9_\-]{8,}|AIza[0-9A-Za-z_\-]{20,}|ya29\.[0-9A-Za-z_\-\.]{10,}", RegexOptions.CultureInvariant)]
    private static partial Regex KeyLike();

    [GeneratedRegex(@"(?i)(bearer\s+|x-api-key[""']?\s*[:=]\s*[""']?|x-goog-api-key[""']?\s*[:=]\s*[""']?)[^\s""',;]+", RegexOptions.CultureInvariant)]
    private static partial Regex HeaderValue();

    public static string Redact(string text)
    {
        if (string.IsNullOrEmpty(text)) return text;
        text = KeyLike().Replace(text, "***");
        return HeaderValue().Replace(text, m => m.Groups[1].Value + "***");
    }

    /// <summary>画面・CLI に出すときの伏せ字（末尾 4 文字だけ残す）</summary>
    public static string Mask(string? secret) =>
        string.IsNullOrEmpty(secret) ? "" : secret.Length >= 12 ? $"***{secret[^4..]}" : "***";
}
