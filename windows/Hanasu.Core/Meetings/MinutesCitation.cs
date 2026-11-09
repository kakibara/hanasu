using System.Text.RegularExpressions;

namespace Hanasu.Core.Meetings;

// 要件: REQ-MTG-052
// 設計判断: DEC-MTG-134
/// <summary>
/// 議事録の要点の行末に AI が付ける、根拠の発言の時刻の印（<c>[12:34]</c>・<c>[1:02:34]</c>、全角の［］も）。
/// Windows 版は印を押せないので、議事録の表示とコピーで取り除く。Mac 版の MinutesCitation.swift と同じ決まり（両方を直す）
/// </summary>
public static class MinutesCitation
{
    /// <summary>印の形。Markdown のリンク（<c>[12:34](…)</c>）は印として扱わない</summary>
    public const string Pattern = @"[\[［](\d{1,2}:\d{2}(?::\d{2})?)[\]］](?!\()";

    private static readonly Regex MarkRegex = new(Pattern, RegexOptions.CultureInvariant);
    // 取り除くときは、前の空白ごと消す
    private static readonly Regex StripRegex = new(@"[ \t　]*" + Pattern, RegexOptions.CultureInvariant);

    /// <summary>行の中の印（見た目の文字と秒数）を、前から順に返す</summary>
    public static List<(string Label, double Seconds)> Marks(string text)
    {
        var result = new List<(string, double)>();
        foreach (Match m in MarkRegex.Matches(text))
        {
            if (MeetingNote.ParseClock(m.Groups[1].Value) is { } seconds) result.Add((m.Groups[1].Value, seconds));
        }
        return result;
    }

    /// <summary>印を取り除いた文。印のあった行だけ末尾の空白も整える（Markdown の行末の空白 2 つの改行を、ほかの行で消さない）</summary>
    public static string Strip(string text)
    {
        if (!StripRegex.IsMatch(text)) return text;
        return string.Join("\n", text.Split('\n').Select(line =>
        {
            var stripped = StripRegex.Replace(line, "");
            return stripped == line ? line : stripped.TrimEnd(' ', '\t');
        }));
    }

    /// <summary>アクションアイテムの at（"12:34"）を、時刻として読めるときだけ整えて返す</summary>
    public static string? CleanAt(string? at)
    {
        var inner = at?.Trim().Trim('[', ']', '［', '］', ' ');
        return string.IsNullOrEmpty(inner) || MeetingNote.ParseClock(inner) is null ? null : inner;
    }

    /// <summary>議事録の結果から印を取り除く（文字起こしを縮めて送ったとき。DEC-COM-065）</summary>
    public static MinutesResult Stripped(MinutesResult result)
    {
        foreach (var item in result.ActionItems) item.At = null;
        return result with { Markdown = Strip(result.Markdown) };
    }
}

// 要件: REQ-MTG-052
// 設計判断: DEC-COM-065, DEC-MTG-134
/// <summary>
/// 長い入力を縮めて送ったか（LongInputFitter が書く）。議事録を作る間だけ AsyncLocal で渡し、
/// 文字起こしを縮めた（根拠の時刻が確かでなくなった）ときは、議事録から時刻の印を取り除く。Mac 版の LongInputReport と同じ
/// </summary>
public sealed class LongInputReport
{
    private int shortened;

    public bool Shortened => Volatile.Read(ref shortened) != 0;

    public void MarkShortened() => Interlocked.Exchange(ref shortened, 1);

    public static readonly AsyncLocal<LongInputReport?> Current = new();
}
