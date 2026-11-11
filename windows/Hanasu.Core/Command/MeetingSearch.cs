using System.Globalization;
using System.Text;
using Hanasu.Core.Meetings;

namespace Hanasu.Core.Command;

// 会議の横断検索。Mac 版 MeetingSearch.swift の MeetingSearchIndex.scan（索引を作らない検索）の移植。
// 決まり（検索の単位・一致の決まり・並び・抜粋）を変えるときは Mac 版も両方を直す（共有のテストデータで比べる。DEC-COM-192）。

/// <summary>ヒットした場所の種類</summary>
public enum SearchHitKind
{
    Title,
    Minutes,
    Transcript,
}

/// <summary>ヒットした 1 か所（タイトル・議事録の 1 行・文字起こしのまとまり 1 つ）</summary>
/// <param name="Line">議事録の行番号（0 始まり）</param>
/// <param name="Start">文字起こしの開始の秒</param>
/// <param name="SpeakerName">文字起こしの話者の表示の名前</param>
public sealed record SearchHit(SearchHitKind Kind, int Line, double Start, string SpeakerName, string BlockId, string Snippet)
{
    public double Order => Kind switch
    {
        SearchHitKind.Title => -2,
        SearchHitKind.Minutes => -1 + Line / 1_000_000.0,
        _ => Start,
    };
}

/// <summary>1 つの会議でヒットしたもの（Hits は上限まで、TotalHits は全部の数）</summary>
public sealed record SearchResult(Meeting Meeting, IReadOnlyList<SearchHit> Hits, int TotalHits);

// 要件: REQ-MTG-015, REQ-MTG-123
// 設計判断: DEC-MTG-051, DEC-MTG-121, DEC-MTG-123
public static class MeetingSearch
{
    /// <summary>半角カナ（U+FF61〜U+FF9F）の全角。濁点・半濁点は結合文字にして、あとの NFC でまとめる</summary>
    private const string HalfwidthKana =
        "。「」、・ヲァィゥェォャュョッーアイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワン\u3099\u309A";  // skip-tr（文字の対応表）

    /// <summary>全角の記号（U+FFE0〜U+FFE6）の半角</summary>
    private const string FullwidthSigns = "¢£¬¯¦¥₩";

    // 設計判断: DEC-MTG-051
    /// <summary>
    /// 大文字・小文字、全角・半角（英数字とカタカナ）の違いを無視するための変換。
    /// Swift の folding([.caseInsensitive, .widthInsensitive]) と precomposedStringWithCanonicalMapping にあたる
    /// </summary>
    public static string Fold(string text)
    {
        var sb = new StringBuilder(text.Length);
        foreach (var c in text)
        {
            if (c is >= '！' and <= '～') sb.Append((char)(c - 0xFEE0));
            else if (c == '　') sb.Append(' ');
            else if (c is >= '｡' and <= 'ﾟ') sb.Append(HalfwidthKana[c - 0xFF61]);
            else if (c is >= '￠' and <= '￦') sb.Append(FullwidthSigns[c - 0xFFE0]);
            else sb.Append(c);
        }
        return sb.ToString().Normalize(NormalizationForm.FormC).ToLowerInvariant();
    }

    /// <summary>検索語を空白（全角を含む）で分け、正規化する（重なりは除く）</summary>
    public static IReadOnlyList<string> Terms(string query)
    {
        var result = new List<string>();
        var sb = new StringBuilder();
        void Flush()
        {
            if (sb.Length > 0 && !result.Contains(sb.ToString())) result.Add(sb.ToString());
            sb.Clear();
        }
        foreach (var c in Fold(query))
        {
            if (char.IsWhiteSpace(c)) Flush();
            else sb.Append(c);
        }
        Flush();
        return result;
    }

    /// <summary>前後の空白（改行は含めない。Swift の .whitespaces）を除く</summary>
    public static string TrimSpaces(string text)
    {
        static bool IsSpace(char c) => c == '\t' || CharUnicodeInfo.GetUnicodeCategory(c) == UnicodeCategory.SpaceSeparator;
        var start = 0;
        var end = text.Length;
        while (start < end && IsSpace(text[start])) start++;
        while (end > start && IsSpace(text[end - 1])) end--;
        return text[start..end];
    }

    /// <summary>検索の単位（タイトル・議事録の行・文字起こしのまとまり）と、その文（前後の空白を除く。空は除く）</summary>
    public static IReadOnlyList<(SearchHit Location, string Text)> SearchUnits(Meeting meeting)
    {
        var result = new List<(SearchHit, string)>();
        void Add(SearchHit location, string text)
        {
            var trimmed = TrimSpaces(text);
            if (trimmed.Length > 0) result.Add((location, trimmed));
        }
        Add(new SearchHit(SearchHitKind.Title, 0, 0, "", "", ""), meeting.Title);
        if (meeting.Minutes is { } minutes)
        {
            var lines = minutes.Split('\n');
            for (var i = 0; i < lines.Length; i++) Add(new SearchHit(SearchHitKind.Minutes, i, 0, "", "", ""), StripMarkdown(lines[i]));
        }
        foreach (var block in meeting.MergedBlocks())
        {
            Add(new SearchHit(SearchHitKind.Transcript, 0, block.Start, meeting.DisplayName(block.Speaker), block.Id, ""), block.Text);
        }
        return result;
    }

    // 要件: REQ-MTG-123
    // 設計判断: DEC-MTG-123
    /// <summary>索引を作らずに 1 回だけ検索する（会議ごとに並べて調べる）。会議は新しい順</summary>
    public static IReadOnlyList<SearchResult> Scan(IReadOnlyList<Meeting> meetings, string query, int hitsPerMeeting = 20, int maxMeetings = 200)
    {
        var terms = Terms(query);
        if (terms.Count == 0) return Array.Empty<SearchResult>();
        var found = new SearchResult?[meetings.Count];
        Parallel.For(0, meetings.Count, index =>
        {
            var meeting = meetings[index];
            var hits = SearchUnits(meeting).Where(unit =>
            {
                var folded = Fold(unit.Text);
                return terms.All(t => folded.Contains(t, StringComparison.Ordinal));
            }).ToList();
            if (hits.Count == 0) return;
            var sorted = hits.OrderBy(h => h.Location.Order).ToList();
            found[index] = new SearchResult(meeting,
                sorted.Take(hitsPerMeeting).Select(h => h.Location with { Snippet = Snippet(h.Text, terms) }).ToList(),
                hits.Count);
        });
        return found.OfType<SearchResult>().OrderByDescending(r => r.Meeting.StartedAt).Take(maxMeetings).ToList();
    }

    /// <summary>議事録の行の先頭の Markdown 記号（見出し・箇条書き・チェックボックス）を除く</summary>
    public static string StripMarkdown(string line)
    {
        var text = TrimSpaces(line);
        foreach (var prefix in new[] { "- [ ] ", "- [x] ", "### ", "## ", "# ", "- ", "* " })
        {
            if (text.StartsWith(prefix, StringComparison.Ordinal))
            {
                text = text[prefix.Length..];
                break;
            }
        }
        return text.Replace("**", "", StringComparison.Ordinal);
    }

    // 設計判断: DEC-COM-192（数えるのは書記素。Swift の Character と同じ）
    /// <summary>最初にヒットした語の前後（書記素で radius 個ずつ）を切り出す</summary>
    public static string Snippet(string text, IReadOnlyList<string> terms, int radius = 32)
    {
        var elements = new List<string>();
        var enumerator = StringInfo.GetTextElementEnumerator(text);
        while (enumerator.MoveNext()) elements.Add(enumerator.GetTextElement());
        // 書記素ごとに畳んだ文と、その位置から書記素への対応
        var folded = new StringBuilder();
        var owner = new List<int>();
        for (var i = 0; i < elements.Count; i++)
        {
            var piece = Fold(elements[i]);
            folded.Append(piece);
            for (var k = 0; k < piece.Length; k++) owner.Add(i);
        }
        var foldedText = folded.ToString();
        foreach (var term in terms)
        {
            var at = foldedText.IndexOf(term, StringComparison.Ordinal);
            if (at < 0 || term.Length == 0) continue;
            var first = owner[at];
            var last = owner[at + term.Length - 1] + 1;
            var start = Math.Max(0, first - radius);
            var end = Math.Min(elements.Count, last + radius);
            return (start > 0 ? "…" : "") + string.Concat(elements.Skip(start).Take(end - start)) + (end < elements.Count ? "…" : "");
        }
        return string.Concat(elements.Take(radius * 2));
    }
}
