using System.Text;
using System.Text.RegularExpressions;

namespace Hanasu.Core.Update;

/// <summary>リリース文を絞り込むときの OS</summary>
public enum ReleasePlatform
{
    Mac,
    Windows,
}

/// <summary>リリース文の 1 行（ブロック）の種類</summary>
public enum ReleaseNotesBlockKind
{
    /// <summary>見出し（# から ######）</summary>
    Heading,
    /// <summary>箇条書き（- * +）</summary>
    Bullet,
    /// <summary>番号付きの箇条書き（1. 1)）</summary>
    Numbered,
    /// <summary>ふつうの文</summary>
    Paragraph,
}

/// <summary>行の中の字の形</summary>
[Flags]
public enum ReleaseNotesStyle
{
    None = 0,
    Bold = 1,
    Italic = 2,
    Code = 4,
}

/// <summary>同じ形の字のまとまり。Link は http / https のときだけ入る</summary>
public sealed record ReleaseNotesInline(string Text, ReleaseNotesStyle Style, Uri? Link = null);

/// <summary>
/// 画面に出す 1 行。Marker は箇条書きの印（「•」か「1.」）で、印のあとを字下げして折り返す。
/// Level は字下げの深さ（行頭の空白 2 つで 1 段）。AfterBlank は前に空行があったか（間を空ける量を決める）
/// </summary>
public sealed record ReleaseNotesBlock(
    ReleaseNotesBlockKind Kind,
    int HeadingLevel,
    int Level,
    string? Marker,
    IReadOnlyList<ReleaseNotesInline> Inlines,
    bool AfterBlank)
{
    /// <summary>字の形を除いた文（テストとログ用）</summary>
    public string PlainText => string.Concat(Inlines.Select(i => i.Text));
}

/// <summary>
/// リリース文（Markdown）を、新しい版を知らせる画面に出す形（行と字の形）にする（Mac の ReleaseNotesFormatter と同じ考え）。
/// 使うのは、リリース文の書き方（docs/releases/TEMPLATE.md）に出てくるもの: 見出し・箇条書き・番号付きの箇条書き・太字・斜体・コード・リンク。
/// 表やコードのブロックは使わないので、そのまま 1 行ずつ出す。HTML のコメントは出さない。
/// </summary>
// 設計判断: DEC-REL-027
public static partial class ReleaseNotesFormatter
{
    [GeneratedRegex("<!--.*?(-->|$)", RegexOptions.Singleline)]
    private static partial Regex HtmlComment();

    /// <summary>アプリの中で出す節（リリース文の書き方 docs/releases/TEMPLATE.md の見出し）</summary>
    private static readonly HashSet<string> AppSections = ["ハイライト", "新しい機能", "改善", "不具合の修正"]; // skip-tr（リリース文の見出しを探す語）

    /// <summary>行の終わりの OS の印（「（Mac）」「(Windows)」「（Mac / Windows）」。あとに「。」か「.」が続いてもよい）</summary>
    [GeneratedRegex(@"\s*[（(]\s*(Mac|Windows)\s*(?:/\s*(Mac|Windows)\s*)?[）)](\s*[。.])?\s*$")]
    private static partial Regex PlatformMark();

    /// <summary>
    /// 更新の知らせに出す分だけにする。出す節は「ハイライト」「新しい機能」「改善」「不具合の修正」だけで、ほかの節は見出しごと除く
    /// （最初の「## 」より前の文は残す。「### 」は節の区切りにしない）。4 つの見出しがどれもなければ、絞らずに全部返す。
    /// 行の終わりの OS の印がこの OS を含まない行は、その下の一段深い行ごと除き、残す行の印は外す。中身がなくなった節は見出しも除く。
    /// 全文はリリースのページで読む
    /// </summary>
    public static string ForApp(string notes, ReleasePlatform platform)
    {
        var lines = HtmlComment().Replace(notes.Replace("\r\n", "\n").Replace('\r', '\n'), "").Split('\n');
        // 節に分ける。Heading が null なのは最初の「## 」より前
        var sections = new List<(string? Heading, List<string> Body)> { (null, []) };
        foreach (var line in lines)
        {
            if (line.StartsWith("## ", StringComparison.Ordinal)) sections.Add((line, []));
            else sections[^1].Body.Add(line);
        }
        bool IsAppSection(string heading) => AppSections.Contains(HeadingText(heading[3..]));
        if (!sections.Any(s => s.Heading is not null && IsAppSection(s.Heading))) return notes.Trim();

        var wanted = platform == ReleasePlatform.Mac ? "Mac" : "Windows";
        var output = new List<string>();
        foreach (var (heading, body) in sections)
        {
            if (heading is not null && !IsAppSection(heading)) continue;
            var kept = new List<string>();
            int? skipDeeperThan = null;
            foreach (var line in body)
            {
                var indent = IndentOf(line);
                if (skipDeeperThan is { } limit)
                {
                    if (line.Trim().Length > 0 && indent > limit) continue;
                    skipDeeperThan = null;
                }
                var mark = PlatformMark().Match(line);
                if (!mark.Success)
                {
                    kept.Add(line);
                    continue;
                }
                var forThis = string.Equals(mark.Groups[1].Value, wanted, StringComparison.OrdinalIgnoreCase)
                    || string.Equals(mark.Groups[2].Value, wanted, StringComparison.OrdinalIgnoreCase);
                if (!forThis)
                {
                    skipDeeperThan = indent;
                    continue;
                }
                kept.Add(line[..mark.Index] + mark.Groups[3].Value.Trim());
            }
            if (heading is not null && kept.All(l => l.Trim().Length == 0)) continue;
            if (heading is not null) output.Add(heading);
            output.AddRange(kept);
        }
        // 空行が 3 つ以上続かないようにする
        return Regex.Replace(string.Join("\n", output), "\n{3,}", "\n\n").Trim();
    }

    private static int IndentOf(string line)
    {
        var indent = 0;
        foreach (var c in line)
        {
            if (c == ' ') indent += 1;
            else if (c == '\t') indent += 4;
            else break;
        }
        return indent;
    }

    public static IReadOnlyList<ReleaseNotesBlock> Parse(string markdown)
    {
        var blocks = new List<ReleaseNotesBlock>();
        var previousWasBlank = true;
        // HTML のコメント（release-notes の印や、テンプレートの説明。数行にわたるものも）は出さない。閉じていなければ終わりまで
        var text = HtmlComment().Replace(markdown.Replace("\r\n", "\n").Replace('\r', '\n'), "");
        foreach (var rawLine in text.Split('\n'))
        {
            var line = rawLine.Trim();
            if (line.Length == 0)
            {
                previousWasBlank = true;
                continue;
            }
            blocks.Add(ParseBlock(rawLine, line, previousWasBlank));
            previousWasBlank = false;
        }
        return blocks;
    }

    private static ReleaseNotesBlock ParseBlock(string rawLine, string line, bool afterBlank)
    {
        var level = IndentOf(rawLine) / 2;

        var hashes = line.TakeWhile(c => c == '#').Count();
        if (hashes is >= 1 and <= 6 && hashes < line.Length && char.IsWhiteSpace(line[hashes]))
        {
            return new ReleaseNotesBlock(ReleaseNotesBlockKind.Heading, hashes, 0, null,
                ParseInline(HeadingText(line[(hashes + 1)..])), afterBlank);
        }
        if (line.Length >= 2 && line[0] is '-' or '*' or '+' && char.IsWhiteSpace(line[1]))
        {
            return new ReleaseNotesBlock(ReleaseNotesBlockKind.Bullet, 0, level, "•", ParseInline(line[2..].Trim()), afterBlank);
        }
        var digits = line.TakeWhile(char.IsAsciiDigit).Count();
        if (digits is >= 1 and <= 9 && digits + 1 < line.Length && line[digits] is '.' or ')' && char.IsWhiteSpace(line[digits + 1]))
        {
            // 印は行の中の解釈に通さない。番号は書いてあるままにする
            return new ReleaseNotesBlock(ReleaseNotesBlockKind.Numbered, 0, level, line[..digits] + ".",
                ParseInline(line[(digits + 2)..].Trim()), afterBlank);
        }
        return new ReleaseNotesBlock(ReleaseNotesBlockKind.Paragraph, 0, 0, null, ParseInline(line), afterBlank);
    }

    /// <summary>
    /// 見出しの中身。閉じの # の並びは、前に空白があるとき（か、中身が # だけのとき）だけ削る（CommonMark と同じ。「C#」の # は残す）
    /// </summary>
    private static string HeadingText(string rest)
    {
        var text = rest.Trim();
        var end = text.Length;
        while (end > 0 && text[end - 1] == '#') end--;
        if (end == text.Length) return text;
        if (end == 0) return "";
        return char.IsWhiteSpace(text[end - 1]) ? text[..end].TrimEnd() : text;
    }

    /// <summary>行の中の Markdown（太字・斜体・コード・リンク・\ のエスケープ）を、字の形のまとまりにする。閉じていない記号はそのまま出す</summary>
    public static IReadOnlyList<ReleaseNotesInline> ParseInline(string text)
    {
        var output = new List<ReleaseNotesInline>();
        ParseInline(text, ReleaseNotesStyle.None, null, output);
        // 隣り合う同じ形のまとまりはつなぐ
        var merged = new List<ReleaseNotesInline>();
        foreach (var piece in output)
        {
            if (piece.Text.Length == 0) continue;
            if (merged.Count > 0 && merged[^1].Style == piece.Style && merged[^1].Link == piece.Link)
                merged[^1] = merged[^1] with { Text = merged[^1].Text + piece.Text };
            else
                merged.Add(piece);
        }
        return merged;
    }

    private static void ParseInline(string s, ReleaseNotesStyle style, Uri? link, List<ReleaseNotesInline> output)
    {
        var buffer = new StringBuilder();
        void Flush()
        {
            if (buffer.Length == 0) return;
            output.Add(new ReleaseNotesInline(buffer.ToString(), style, link));
            buffer.Clear();
        }

        var i = 0;
        while (i < s.Length)
        {
            var c = s[i];
            if (c == '\\' && i + 1 < s.Length && IsAsciiPunctuation(s[i + 1]))
            {
                buffer.Append(s[i + 1]);
                i += 2;
                continue;
            }
            if (c == '`')
            {
                var run = CountRun(s, i, '`');
                var close = FindBacktickClose(s, i + run, run);
                if (close >= 0)
                {
                    Flush();
                    var code = s[(i + run)..close];
                    if (code.Length >= 2 && code[0] == ' ' && code[^1] == ' ' && code.Trim().Length > 0) code = code[1..^1];
                    output.Add(new ReleaseNotesInline(code, style | ReleaseNotesStyle.Code, link));
                    i = close + run;
                    continue;
                }
                buffer.Append(s, i, run);
                i += run;
                continue;
            }
            if (c == '[' && link is null && TryParseLink(s, i, out var label, out var target, out var end))
            {
                Flush();
                ParseInline(label, style, AllowedLink(target), output);
                i = end;
                continue;
            }
            if (c is '*' or '_')
            {
                var run = CountRun(s, i, c);
                var width = Math.Min(run, 3);
                var close = FindEmphasisClose(s, i, run, width, c);
                if (close >= 0)
                {
                    Flush();
                    var added = width switch
                    {
                        1 => ReleaseNotesStyle.Italic,
                        2 => ReleaseNotesStyle.Bold,
                        _ => ReleaseNotesStyle.Bold | ReleaseNotesStyle.Italic,
                    };
                    // 4 つ以上並んでいれば、余りは字として出す
                    if (run > width) output.Add(new ReleaseNotesInline(new string(c, run - width), style, link));
                    ParseInline(s[(i + run)..close], style | added, link, output);
                    i = close + width;
                    continue;
                }
                buffer.Append(s, i, run);
                i += run;
                continue;
            }
            buffer.Append(c);
            i++;
        }
        Flush();
    }

    private static bool IsAsciiPunctuation(char c) => c < 128 && (char.IsPunctuation(c) || char.IsSymbol(c));

    private static int CountRun(string s, int start, char c)
    {
        var end = start;
        while (end < s.Length && s[end] == c) end++;
        return end - start;
    }

    private static int FindBacktickClose(string s, int from, int run)
    {
        var i = from;
        while (i < s.Length)
        {
            if (s[i] != '`')
            {
                i++;
                continue;
            }
            var n = CountRun(s, i, '`');
            if (n == run) return i;
            i += n;
        }
        return -1;
    }

    /// <summary>
    /// 強調を閉じる記号の位置。開く記号の直後と閉じる記号の直前は空白でない。
    /// _ は単語の途中（snake_case など）では強調にしない
    /// </summary>
    private static int FindEmphasisClose(string s, int open, int run, int width, char c)
    {
        var contentStart = open + run;
        if (contentStart >= s.Length || char.IsWhiteSpace(s[contentStart])) return -1;
        if (c == '_' && open > 0 && char.IsLetterOrDigit(s[open - 1])) return -1;
        var i = contentStart + 1;
        while (i < s.Length)
        {
            if (s[i] == '\\')
            {
                i += 2;
                continue;
            }
            if (s[i] == '`')
            {
                var bt = CountRun(s, i, '`');
                var btClose = FindBacktickClose(s, i + bt, bt);
                i = btClose >= 0 ? btClose + bt : i + bt;
                continue;
            }
            if (s[i] != c)
            {
                i++;
                continue;
            }
            var n = CountRun(s, i, c);
            var after = i + n;
            var okBefore = !char.IsWhiteSpace(s[i - 1]);
            var okAfter = c != '_' || after >= s.Length || !char.IsLetterOrDigit(s[after]);
            if (n == width && okBefore && okAfter) return i;
            i += n;
        }
        return -1;
    }

    /// <summary>[字](URL) を読む。URL のあとの "題" は無視する</summary>
    private static bool TryParseLink(string s, int open, out string label, out string target, out int end)
    {
        label = target = "";
        end = open;
        var depth = 0;
        var close = -1;
        for (var i = open; i < s.Length; i++)
        {
            if (s[i] == '\\')
            {
                i++;
                continue;
            }
            if (s[i] == '[') depth++;
            else if (s[i] == ']' && --depth == 0)
            {
                close = i;
                break;
            }
        }
        if (close < 0 || close + 1 >= s.Length || s[close + 1] != '(') return false;
        var paren = s.IndexOf(')', close + 2);
        if (paren < 0) return false;
        label = s[(open + 1)..close];
        var inside = s[(close + 2)..paren].Trim();
        var space = inside.IndexOfAny([' ', '\t']);
        target = (space >= 0 ? inside[..space] : inside).Trim('<', '>');
        end = paren + 1;
        return true;
    }

    /// <summary>押して開くのは http / https だけ（ほかは字だけ出す）</summary>
    private static Uri? AllowedLink(string target) =>
        Uri.TryCreate(target, UriKind.Absolute, out var uri) && (uri.Scheme == Uri.UriSchemeHttps || uri.Scheme == Uri.UriSchemeHttp)
            ? uri
            : null;
}
