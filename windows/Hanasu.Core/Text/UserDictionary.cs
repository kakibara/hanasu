using System.Globalization;
using System.Text;

namespace Hanasu.Core.Text;

/// <summary>
/// ユーザー辞書。設定の辞書テキスト（1 行 1 項目）を読み、語と置き換えルールに分ける。Mac 版の UserDictionary.swift の移植。
/// </summary>
/// <remarks>
/// 書き方:
/// <code>
///     Stockmark                              … 語だけ。認識のヒントと Gemini に渡す
///     ストックマーク => Stockmark               … 置き換えルール。左の読み・誤認識を右の表記にする
///     えーにゅーす, エーニュース => Anews        … 左は「,」「、」で区切って複数書ける
///     # メモ                                  … 「#」で始まる行は無視する
/// </code>
/// 矢印は <c>=&gt;</c> のほか、全角の <c>＝＞</c> と <c>→</c> も使える。
///
/// 置き換えの規則（<see cref="Apply"/>）:
/// - 英字の大文字小文字、全角と半角（ＡＢＣ／ABC、ｽﾄｯｸ／ストック）、空白の有無は区別せずに探す。置き換えた後は右に書いた表記そのものになる。
/// - ひらがなとカタカナは区別する。
/// - 部分一致による誤爆を防ぐため、次の場合は置き換えない。
///   - 左が英数字で始まる（終わる）とき、直前（直後）も英数字（例: ai =&gt; AI は OpenAI の中では効かない）
///   - 左がカタカナで始まる（終わる）とき、直前（直後）もカタカナか「ー」
///   - 左が 1 文字だけのルール
/// - 同じ位置に当てはまるルールが複数あれば、左が長いものを使う。長さも同じなら上の行を使う。
/// - 左から右へ 1 回だけ置き換える。置き換えた後の文字に、ほかのルールを重ねて当てない。
///
/// 文字の単位は書記素（Swift の Character と同じ。.NET の StringInfo のテキスト要素）で数える。
/// </remarks>
public sealed class UserDictionary
{
    /// <summary>辞書の 1 行。語も置き換えルールも Entry で表し、コメントと空行はそのまま残す。</summary>
    public abstract record Line
    {
        public sealed record EntryLine(Entry Entry) : Line;
        /// <summary>空行・コメント（書かれたまま保つ）</summary>
        public sealed record Other(string Raw) : Line;
    }

    public sealed record Entry(string Reading, string Spelling)
    {
        /// <summary>左を区切った読みの一覧</summary>
        public IReadOnlyList<string> Sources =>
            Reading.Split(SourceSeparators).Select(s => s.Trim()).Where(s => s.Length > 0).ToArray();

        public bool IsRule => Sources.Count > 0;

        /// <summary>辞書の 1 行として書き出す</summary>
        public string LineText
        {
            get
            {
                var reading = Reading.Trim();
                var spelling = Spelling.Trim();
                return reading.Length == 0 ? spelling : $"{reading} => {spelling}";
            }
        }
    }

    /// <summary>実際に置き換えに使うルール</summary>
    public sealed record Rule(IReadOnlyList<string> Sources, string Target)
    {
        public bool Equals(Rule? other) => other is not null && Target == other.Target && Sources.SequenceEqual(other.Sources);
        public override int GetHashCode() => HashCode.Combine(Target, Sources.Count);
    }

    public sealed record Replacement(string Matched, string Target);

    public static readonly string[] Arrows = ["=>", "＝＞", "→"];
    public static readonly char[] SourceSeparators = [',', '、', '，'];
    /// <summary>これより短い読みは誤爆しやすいので使わない</summary>
    public const int MinimumSourceLength = 2;

    public IReadOnlyList<Line> Lines { get; }

    public UserDictionary(string text)
    {
        Lines = text.Replace("\r\n", "\n").Split('\n', '\r').Select(ParseLine).ToArray();
    }

    public UserDictionary(IEnumerable<Line> lines)
    {
        Lines = lines.ToArray();
    }

    public static Line ParseLine(string raw)
    {
        var line = raw.Trim();
        if (line.Length == 0 || line.StartsWith('#')) return new Line.Other(raw);
        // いちばん左にある矢印で分ける
        int bestIndex = -1;
        string? bestArrow = null;
        foreach (var arrow in Arrows)
        {
            var index = line.IndexOf(arrow, StringComparison.Ordinal);
            if (index >= 0 && (bestIndex < 0 || index < bestIndex))
            {
                bestIndex = index;
                bestArrow = arrow;
            }
        }
        if (bestArrow is null) return new Line.EntryLine(new Entry("", line));
        return new Line.EntryLine(new Entry(line[..bestIndex].Trim(), line[(bestIndex + bestArrow.Length)..].Trim()));
    }

    public string Text => string.Join("\n", Lines.Select(l => l switch
    {
        Line.EntryLine e => e.Entry.LineText,
        Line.Other o => o.Raw,
        _ => "",
    }));

    public IReadOnlyList<Entry> Entries => Lines.OfType<Line.EntryLine>().Select(l => l.Entry).ToArray();

    // MARK: - 使う側に渡すもの

    /// <summary>置き換えに使うルール（問題のある読みは除く）</summary>
    public IReadOnlyList<Rule> Rules
    {
        get
        {
            var seen = new HashSet<string>(StringComparer.Ordinal);
            var rules = new List<Rule>();
            foreach (var entry in Entries.Where(e => e.IsRule))
            {
                var target = entry.Spelling.Trim();
                if (target.Length == 0) continue;
                var sources = entry.Sources.Where(source =>
                {
                    var key = MatchKey(source);
                    if (key.Length < MinimumSourceLength) return false;
                    return seen.Add(string.Concat(key));
                }).ToArray();
                if (sources.Length > 0) rules.Add(new Rule(sources, target));
            }
            return rules;
        }
    }

    /// <summary>正しい表記の一覧（語だけの行と、ルールの右側）。Gemini の「ユーザー辞書」に渡す</summary>
    public IReadOnlyList<string> Spellings =>
        Unique(Entries.Select(e => e.Spelling.Trim()).Where(s => s.Length > 0));

    /// <summary>音声認識の語彙ヒントに渡す語。正しい表記に加えて、ルールの読みも渡す</summary>
    public IReadOnlyList<string> ContextualStrings =>
        Unique(Spellings.Concat(Rules.SelectMany(r => r.Sources)));

    /// <summary>行ごとの注意（設定画面に出す）。キーは Lines の添字</summary>
    public IReadOnlyDictionary<int, string> Issues
    {
        get
        {
            var result = new Dictionary<int, string>();
            var seen = new HashSet<string>(StringComparer.Ordinal);
            for (var index = 0; index < Lines.Count; index++)
            {
                if (Lines[index] is not Line.EntryLine { Entry: var entry } || !entry.IsRule) continue;
                if (entry.Spelling.Trim().Length == 0)
                {
                    result[index] = Strings.Dictionary_EmptySpelling;
                    continue;
                }
                var notes = new List<string>();
                foreach (var source in entry.Sources)
                {
                    var key = MatchKey(source);
                    if (key.Length < MinimumSourceLength)
                    {
                        notes.Add(string.Format(Strings.Dictionary_SourceTooShort, source));
                    }
                    else if (!seen.Add(string.Concat(key)))
                    {
                        notes.Add(string.Format(Strings.Dictionary_SourceDuplicate, source));
                    }
                }
                if (notes.Count > 0) result[index] = string.Join("\n", notes);
            }
            return result;
        }
    }

    // MARK: - 置き換え

    public string Apply(string text) => ApplyWithLog(text).Text;

    private sealed record Pattern(string[] Key, string Target, CharClass First, CharClass Last);

    /// <summary>置き換えた結果と、どこをどう置き換えたか</summary>
    public (string Text, IReadOnlyList<Replacement> Replacements) ApplyWithLog(string text)
    {
        var rules = Rules;
        if (rules.Count == 0 || text.Length == 0) return (text, Array.Empty<Replacement>());

        // 照合用の型: 読み（空白を除いて畳んだ文字列）→ 表記。先頭の文字ごとに、長い順に並べる
        var patterns = new Dictionary<string, List<Pattern>>(StringComparer.Ordinal);
        foreach (var rule in rules)
        {
            foreach (var source in rule.Sources)
            {
                var key = MatchKey(source);
                if (key.Length == 0) continue;
                if (!patterns.TryGetValue(key[0], out var list)) patterns[key[0]] = list = new List<Pattern>();
                list.Add(new Pattern(key, rule.Target, ClassOf(key[0]), ClassOf(key[^1])));
            }
        }
        foreach (var k in patterns.Keys.ToArray())
        {
            // 長い順。長さが同じなら書いた順（OrderByDescending は安定）
            patterns[k] = patterns[k].OrderByDescending(p => p.Key.Length).ToList();
        }

        var chars = Graphemes(text);
        // 空白を除いて畳んだ文字の並びと、それぞれが元の何文字目から来たか
        var units = new List<string>();
        var unitOrigin = new List<int>();
        var firstUnit = Enumerable.Repeat(-1, chars.Length).ToArray();
        // 前後の文字の種類（境界の判定用）。元の文字を畳んだものの先頭・末尾で見る
        var headClass = new CharClass[chars.Length];
        var tailClass = new CharClass[chars.Length];
        for (var i = 0; i < chars.Length; i++)
        {
            var folded = Fold(chars[i]);
            headClass[i] = folded.Length > 0 ? ClassOf(folded[0]) : CharClass.Other;
            tailClass[i] = folded.Length > 0 ? ClassOf(folded[^1]) : CharClass.Other;
            if (IsWhitespace(chars[i]) || folded.Length == 0) continue;
            firstUnit[i] = units.Count;
            foreach (var f in folded)
            {
                units.Add(f);
                unitOrigin.Add(i);
            }
        }

        var output = new StringBuilder();
        var replacements = new List<Replacement>();
        var pos = 0;
        while (pos < chars.Length)
        {
            var u = firstUnit[pos];
            if (u >= 0 && patterns.TryGetValue(units[u], out var candidates))
            {
                int? matchedEnd = null;
                var matchedTarget = "";
                foreach (var pattern in candidates)
                {
                    var end = u + pattern.Key.Length;
                    if (end > units.Count || !KeyEquals(units, u, pattern.Key)) continue;
                    var lastChar = unitOrigin[end - 1];
                    // 元の 1 文字が畳んで複数になった途中で切れていないか
                    if (end < units.Count && unitOrigin[end] == lastChar) continue;
                    // 語の境界
                    if (pos > 0 && Joins(tailClass[pos - 1], pattern.First)) continue;
                    if (lastChar + 1 < chars.Length && Joins(pattern.Last, headClass[lastChar + 1])) continue;
                    matchedEnd = lastChar + 1;
                    matchedTarget = pattern.Target;
                    break;
                }
                if (matchedEnd is int endIndex)
                {
                    output.Append(matchedTarget);
                    replacements.Add(new Replacement(string.Concat(chars[pos..endIndex]), matchedTarget));
                    pos = endIndex;
                    continue;
                }
            }
            output.Append(chars[pos]);
            pos++;
        }
        return (output.ToString(), replacements);
    }

    private static bool KeyEquals(List<string> units, int start, string[] key)
    {
        for (var j = 0; j < key.Length; j++)
        {
            if (!string.Equals(units[start + j], key[j], StringComparison.Ordinal)) return false;
        }
        return true;
    }

    // MARK: - 文字の扱い

    public enum CharClass { Latin, Katakana, Other }

    /// <summary>文字列を書記素（テキスト要素）に分ける</summary>
    public static string[] Graphemes(string s)
    {
        var result = new List<string>(s.Length);
        var e = StringInfo.GetTextElementEnumerator(s);
        while (e.MoveNext()) result.Add(e.GetTextElement());
        return result.ToArray();
    }

    /// <summary>大文字小文字・全角半角を区別しないように畳む（Swift の folding(.caseInsensitive, .widthInsensitive) にあたる）</summary>
    public static string[] Fold(string grapheme)
    {
        var sb = new StringBuilder(grapheme.Length);
        var needsNormalize = false;
        foreach (var c in grapheme)
        {
            if (c >= '！' && c <= '～') sb.Append((char)(c - 0xFEE0));  // 全角英数・記号 → 半角
            else if (c == '　') sb.Append(' ');
            else
            {
                if (c >= '｡' && c <= '￯') needsNormalize = true;  // 半角カナなど
                sb.Append(c);
            }
        }
        var s = sb.ToString();
        if (needsNormalize) s = s.Normalize(NormalizationForm.FormKC);  // ｶﾞ → ガ
        return Graphemes(s.ToLowerInvariant());
    }

    /// <summary>照合に使う形（畳んで、空白を除く）</summary>
    public static string[] MatchKey(string s) =>
        Graphemes(s).Where(g => !IsWhitespace(g)).SelectMany(Fold).ToArray();

    public static bool IsWhitespace(string grapheme) => grapheme.Length > 0 && grapheme.All(char.IsWhiteSpace);

    public static CharClass ClassOf(string grapheme)
    {
        if (grapheme.Length == 1 && grapheme[0] < 0x80 && char.IsLetterOrDigit(grapheme[0])) return CharClass.Latin;
        if (grapheme.Length == 0 || !Rune.TryGetRuneAt(grapheme, 0, out var rune)) return CharClass.Other;
        var scalar = rune.Value;
        // 「・」(30FB) は区切りとして扱う
        return scalar is >= 0x30A1 and <= 0x30FA or >= 0x30FC and <= 0x30FE or >= 0x31F0 and <= 0x31FF
            ? CharClass.Katakana
            : CharClass.Other;
    }

    /// <summary>2 つの文字が同じ語の一部としてつながるか（英数字どうし、カタカナどうし）</summary>
    public static bool Joins(CharClass a, CharClass b) => a == b && a != CharClass.Other;

    private static IReadOnlyList<string> Unique(IEnumerable<string> items)
    {
        var seen = new HashSet<string>(StringComparer.Ordinal);
        return items.Where(seen.Add).ToArray();
    }
}
