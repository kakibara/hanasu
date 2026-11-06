namespace Hanasu.Core.Settings;

// 要件: REQ-COM-004
/// <summary>
/// 文字起こしの言語（設定の LocaleIdentifier）の候補と、初期値。Mac 版の AppSettings.transcriptionLocaleIdentifiers・
/// nearestTranscriptionLocale と同じ決まり（両方を直す）
/// </summary>
public static class TranscriptionLocales
{
    /// <summary>文字起こしの言語の候補（Mac 版の一覧と同じ並び）</summary>
    public static readonly IReadOnlyList<string> Identifiers =
        ["ja-JP", "en-US", "en-GB", "zh-CN", "zh-TW", "ko-KR", "fr-FR", "de-DE", "es-ES", "it-IT", "pt-BR"];

    /// <summary>
    /// 一覧にない言語を、言語コードが同じ一覧の項目に寄せる（en-JP → en-US、zh-Hans-CN → zh-CN、zh-Hant-TW → zh-TW。ja-JP はそのまま）。
    /// 言語コードが同じ項目がなければ、そのまま返す（sv-SE → sv-SE）。空なら ja-JP（Mac 版と同じ）
    /// </summary>
    public static string Nearest(string? identifier)
    {
        var trimmed = (identifier ?? "").Trim().Replace('_', '-');
        if (trimmed.Length == 0) return "ja-JP";
        if (Identifiers.FirstOrDefault(i => string.Equals(i, trimmed, StringComparison.OrdinalIgnoreCase)) is { } exact) return exact;
        var parts = trimmed.Split('-', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length == 0) return trimmed;
        var code = parts[0].ToLowerInvariant();
        if (code == "zh")
        {
            var subtags = parts.Skip(1).Select(p => p.ToUpperInvariant()).ToList();
            return subtags.Contains("HANT") || subtags.Any(p => p is "TW" or "HK" or "MO") ? "zh-TW" : "zh-CN";
        }
        return Identifiers.FirstOrDefault(i => i.Split('-')[0] == code) ?? trimmed;
    }

    /// <summary>
    /// 設定がまだないときの文字起こしの言語。Windows の表示の言語（UiLanguage.Apply で置き換える前のもの）を一覧に寄せる。
    /// 表示の言語が分からなければ en-US
    /// </summary>
    public static string SystemDefault => SystemDefaultFor(UiLanguage.SystemCultureName);

    internal static string SystemDefaultFor(string? systemCultureName) =>
        string.IsNullOrWhiteSpace(systemCultureName) ? "en-US" : Nearest(systemCultureName);
}
