using System.Buffers;
using System.Text;

namespace Hanasu.Core.Text;

// 設計判断: DEC-COM-174
/// <summary>
/// 文のかけら（認識の区切り・続く発言・Whisper の区間）をつなぐときに、あいだに空白を入れるかの決まり。
/// 日本語・中国語は語のあいだに空白を書かないので入れず、英語・韓国語など空白で語を区切る言語では 1 つ入れる。
/// Mac 版の TextSpacing（Sources/Hanasu/TextSpacing.swift）と同じ決まり（両方を直す）
/// </summary>
public static class TextSpacing
{
    // 閉じる記号・句読点の前、開く記号の後には入れない
    private const string NoSpaceBefore = ".,!?;:%)]}…'’”»";  // skip-tr（照らし合わせに使う記号）
    private const string NoSpaceAfter = "([{‘“«¿¡";  // skip-tr（照らし合わせに使う記号）

    /// <summary>a と b をつなぐ。境目に空白がなく、どちらの側も空白を書かない文字（漢字・かな・全角の記号）でなければ空白を 1 つ入れる</summary>
    public static string Join(string a, string b) => NeedsSpace(a, b) ? a + " " + b : a + b;

    /// <summary>並びをつなぐ（空のかけらは飛ばす）</summary>
    public static string Join(IEnumerable<string> pieces) =>
        pieces.Aggregate("", (joined, piece) => piece.Length == 0 ? joined : Join(joined, piece));

    public static bool NeedsSpace(string a, string b)
    {
        if (string.IsNullOrEmpty(a) || string.IsNullOrEmpty(b)) return false;
        if (Rune.DecodeLastFromUtf16(a, out var last, out _) != OperationStatus.Done) return false;
        if (Rune.DecodeFromUtf16(b, out var first, out _) != OperationStatus.Done) return false;
        if (Rune.IsWhiteSpace(last) || Rune.IsWhiteSpace(first)) return false;
        if (WritesWithoutSpaces(last.Value) || WritesWithoutSpaces(first.Value)) return false;
        if (first.IsBmp && NoSpaceBefore.Contains((char)first.Value)) return false;
        if (last.IsBmp && NoSpaceAfter.Contains((char)last.Value)) return false;
        return true;
    }

    /// <summary>
    /// 語のあいだに空白を書かない文字（漢字・ひらがな・カタカナ・注音・CJK の記号・全角の形）。ハングルは空白で区切るので含めない
    /// </summary>
    public static bool WritesWithoutSpaces(int scalar) => scalar is
        >= 0x2E80 and <= 0x2FFF  // 部首
        or >= 0x3000 and <= 0x30FF  // CJK の記号・句読点、ひらがな、カタカナ
        or >= 0x3100 and <= 0x312F or >= 0x31A0 and <= 0x31FF  // 注音、カタカナの拡張
        or >= 0x3400 and <= 0x4DBF or >= 0x4E00 and <= 0x9FFF or >= 0xF900 and <= 0xFAFF  // 漢字
        or >= 0xFE30 and <= 0xFE4F  // CJK の互換の形
        or >= 0xFF00 and <= 0xFFEF  // 全角・半角の形
        or >= 0x20000 and <= 0x3FFFF;  // 漢字の拡張
}
