using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace Hanasu.Core.Text;

// 画面から辞書の候補を探す（REQ-DIC-075）の、撮る・読む部分を除いた純粋な部分。
// Mac 版の ScreenSnapshotLayout（ScreenSnapshot.swift）の terms・layout の移植と、Windows の OCR の単語のつなぎ方、既定の除外のプロセスの一覧。
// 例は common/testdata/logic/screen-terms.json に置き、Mac と Windows の両方のテストで回す（DEC-DIC-234・237）。

/// <summary>
/// OCR で読んだ 1 行（Mac 版の ScreenTextLine）。Display は何番目の画面か、InTarget は入力先のウインドウの中か
/// （画面から辞書の候補を探すときは入力先がないので、いつも false）。Y・X は行の位置（並べ方にだけ使う）
/// </summary>
public sealed record ScreenTextLine(string Text, int Display, bool InTarget, double Y, double X);

/// <summary>行から作った語の一覧と行（Mac 版の ScreenOCR）</summary>
public sealed record ScreenOcr(IReadOnlyList<string> Terms, IReadOnlyList<string> Lines)
{
    public static ScreenOcr Empty { get; } = new([], []);
    public bool IsEmpty => Terms.Count == 0 && Lines.Count == 0;
}

// 要件: REQ-DIC-075
// 設計判断: DEC-DIC-183, DEC-DIC-234
public static class ScreenDictionary
{
    /// <summary>上限のうち、語の一覧に先に使う割合（Mac 版の termShare）</summary>
    public const double TermShare = 0.6;

    /// <summary>
    /// 文字数（Mac の String.count と同じく、書記素のまとまりで数える）。結合文字・サロゲートペアを 1 文字と数える
    /// </summary>
    public static int Length(string text) => text.Length == 0 ? 0 : new StringInfo(text).LengthInTextElements;

    // 設計判断: DEC-DIC-183
    /// <summary>行から、語の一覧と行を作り、上限（文字数）に収める（Mac 版 ScreenSnapshotLayout.layout の移植）</summary>
    public static ScreenOcr Layout(IEnumerable<ScreenTextLine> lines, int limit)
    {
        if (limit <= 0) return ScreenOcr.Empty;
        // 画面ごとに上から下・左から右。入力先のウインドウの外を先に、中をあとに
        var sorted = lines.Where(l => Length(l.Text.Trim(' ', '\t')) >= 2).ToList();
        sorted.Sort((a, b) =>
        {
            if (a.InTarget != b.InTarget) return a.InTarget ? 1 : -1;
            if (a.Display != b.Display) return a.Display.CompareTo(b.Display);
            if (Math.Abs(a.Y - b.Y) > 4) return a.Y.CompareTo(b.Y);
            return a.X.CompareTo(b.X);
        });
        var seenLines = new HashSet<string>(StringComparer.Ordinal);
        var uniqueLines = sorted.Where(l => seenLines.Add(l.Text)).ToList();

        // 語の一覧: 画面と「外／中」ごとの組に分け、組を順にめぐって 1 語ずつ取る（どの画面の語も落ちにくいように）
        var groups = new List<List<string>>();
        var groupIndex = new Dictionary<(bool, int), int>();
        foreach (var line in uniqueLines)
        {
            var key = (line.InTarget, line.Display);
            if (!groupIndex.TryGetValue(key, out var index))
            {
                groups.Add([]);
                index = groups.Count - 1;
                groupIndex[key] = index;
            }
            groups[index].AddRange(Terms(line.Text));
        }
        var orderedTerms = new List<string>();
        var seenTerms = new HashSet<string>(StringComparer.Ordinal);
        var cursor = new int[groups.Count];
        var remaining = groups.Sum(g => g.Count);
        while (remaining > 0)
        {
            for (var g = 0; g < groups.Count; g++)
            {
                if (cursor[g] >= groups[g].Count) continue;
                var term = groups[g][cursor[g]];
                cursor[g]++;
                remaining--;
                if (seenTerms.Add(term.ToLowerInvariant())) orderedTerms.Add(term);
            }
        }

        var terms = new List<string>();
        var kept = new List<string>();
        var used = 0;
        var nextTerm = 0;
        void TakeTerms(int budget)
        {
            while (nextTerm < orderedTerms.Count)
            {
                var term = orderedTerms[nextTerm];
                var cost = Length(term) + (terms.Count == 0 ? 0 : 2);
                if (used + cost > budget) break;
                terms.Add(term);
                used += cost;
                nextTerm++;
            }
        }
        TakeTerms((int)(limit * TermShare));
        foreach (var line in uniqueLines)
        {
            var cost = Length(line.Text) + (kept.Count == 0 ? 0 : 1);
            // 行の途中では切らない。入らない行は飛ばして、短い行を入れる
            if (used + cost <= limit)
            {
                kept.Add(line.Text);
                used += cost;
            }
        }
        // 行で使い切らなかった分は、残りの語に回す
        TakeTerms(limit);
        return new ScreenOcr(terms, kept);
    }

    // 設計判断: DEC-DIC-234
    // Mac の正規表現は ICU の \p{Han}・\p{Hiragana}・\p{Katakana} と集合の引き算（--）で書いている。.NET は文字種（スクリプト）の
    // \p{…} がないので、文字の範囲を書き下ろし、.NET の集合の引き算（[…-[…]]）で除く。
    // 漢字（CJK 部首・々〆〇・蘇州数字・統合漢字と拡張 A・互換漢字）、ひらがな、カタカナ（・ー ヽヾ を含む）・カタカナの拡張・
    // 囲みカタカナ・CJK 互換のカタカナ、全角・半角の形（Mac の \x{FF00}-\x{FFEF}）
    private const string JapaneseScript =
        @"\u2E80-\u2FDF\u3005-\u3007\u3021-\u3029\u3038-\u303B\u3041-\u3096\u309D-\u309F\u30A1-\u30FF\u31F0-\u31FF\u32D0-\u32FE\u3300-\u3357\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF\uFF00-\uFFEF";
    // 漢字の範囲（Mac の [\p{Han}々〆ヶ]）。拡張 B 以降（U+20000〜）は .NET の正規表現ではサロゲートペアなので、別に書く
    private const string HanBmp = @"\u2E80-\u2FDF\u3005-\u3007\u3021-\u3029\u3038-\u303B\u30F6\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF";
    private const string HanSupplementary = @"[\uD840-\uD887][\uDC00-\uDFFF]";

    private static readonly Regex[] TermPatterns =
    [
        // 空白で語を区切る文字の語（J3・v2.1・Kubernetes・C++・Müller・Иванов・김예린 など。アクセント付きの文字・
        // キリル文字・ハングル・アラビア文字・デーヴァナーガリーを含む）。漢字・かなは下の 2 つで取る。数字だけのものは下で除く
        new($@"[\p{{L}}\p{{N}}-[{JapaneseScript}]][\p{{L}}\p{{M}}\p{{N}}._+#/\x2D-[{JapaneseScript}]]*[\p{{L}}\p{{M}}\p{{N}}+#-[{JapaneseScript}]]",
            RegexOptions.CultureInvariant),
        // カタカナの語（2 文字以上）
        new(@"[\u30A1-\u30FA][\u30A1-\u30FA\u30FC\u30FB]+", RegexOptions.CultureInvariant),
        // 漢字の並び（2 文字以上）
        new($@"(?:[{HanBmp}]|{HanSupplementary}){{2,}}", RegexOptions.CultureInvariant),
    ];

    /// <summary>1 行から、表記の候補になる語を出てきた順に取り出す（Mac 版 ScreenSnapshotLayout.terms の移植）</summary>
    public static IReadOnlyList<string> Terms(string text)
    {
        var found = new List<(int Index, string Term)>();
        foreach (var pattern in TermPatterns)
        {
            foreach (Match match in pattern.Matches(text))
            {
                // 数字と記号だけ（日付・時刻・金額など）は表記の候補にならない
                if (!match.Value.EnumerateRunes().Any(Rune.IsLetter)) continue;
                found.Add((match.Index, match.Value));
            }
        }
        return found.OrderBy(f => f.Index).Select(f => f.Term).ToList();
    }

    // 設計判断: DEC-DIC-234
    /// <summary>
    /// Windows の OCR（Windows.Media.Ocr）が返した単語をつないで 1 行にする。両側が漢字・ひらがな・カタカナ・「ー」の単語は空白なしで、
    /// ほかは空白でつなぐ（日本語・中国語の行は 1 文字ずつ空白で区切った単語で返ることへの対策）
    /// </summary>
    public static string JoinOcrWords(IEnumerable<string> words)
    {
        var builder = new StringBuilder();
        foreach (var raw in words)
        {
            var word = raw.Trim();
            if (word.Length == 0) continue;
            if (builder.Length > 0)
            {
                var before = Rune.DecodeLastFromUtf16(builder.ToString(), out var last, out _) == System.Buffers.OperationStatus.Done ? last : default;
                var after = Rune.DecodeFromUtf16(word, out var first, out _) == System.Buffers.OperationStatus.Done ? first : default;
                if (!(IsCjkJoining(before) && IsCjkJoining(after))) builder.Append(' ');
            }
            builder.Append(word);
        }
        return builder.ToString();
    }

    /// <summary>空白なしでつなぐ文字（漢字・ひらがな・カタカナ・「ー」）</summary>
    private static bool IsCjkJoining(Rune rune)
    {
        var v = rune.Value;
        return v is >= 0x3005 and <= 0x3007            // 々〆〇
            or >= 0x3021 and <= 0x3029                 // 蘇州数字
            or >= 0x3041 and <= 0x309F                 // ひらがな
            or >= 0x30A0 and <= 0x30FF                 // カタカナ（ー・を含む）
            or >= 0x31F0 and <= 0x31FF                 // カタカナの拡張
            or >= 0x3400 and <= 0x4DBF                 // 統合漢字の拡張 A
            or >= 0x4E00 and <= 0x9FFF                 // 統合漢字
            or >= 0xF900 and <= 0xFAFF                 // 互換漢字
            or >= 0xFF66 and <= 0xFF9F                 // 半角カタカナ
            or >= 0x20000 and <= 0x323AF;              // 統合漢字の拡張 B 以降
    }

    // 設計判断: DEC-DIC-235
    /// <summary>
    /// Windows で、読む前に塗りつぶすウインドウのプロセス（exe の名前から拡張子を除いたもの。大文字と小文字を区別しない）。固定で、設定の欄はない。
    /// パスワード管理・通知・認証のダイアログ・ロック画面（2FA のコードやパスワードを会議の AI に送らないため）
    /// </summary>
    public static IReadOnlySet<string> WindowsExcludedProcesses { get; } = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        // パスワード管理
        "KeePass", "KeePassXC", "1Password", "Bitwarden", "Dashlane", "Keeper", "Enpass", "LastPass", "NordPass", "RoboForm", "ProtonPass",
        // 通知のトースト（とスマホ連携）
        "ShellExperienceHost", "PhoneExperienceHost",
        // 認証のダイアログ（資格情報・Windows Hello）
        "CredentialUIBroker",
        // ロック画面
        "LockApp",
    };

    /// <summary>exe の名前かパス（"keepassxc.exe"・"C:\…\KeePassXC.exe"・"KeePassXC"）が既定の除外の一覧にあるか</summary>
    public static bool IsExcludedProcess(string? exe)
    {
        if (string.IsNullOrWhiteSpace(exe)) return false;
        // Windows のパス（\）を、Windows 以外で動かすテストでも区切れるように、どちらの区切りも見る
        var name = exe.Trim();
        name = name[(name.LastIndexOfAny(['\\', '/']) + 1)..];
        if (name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)) name = name[..^4];
        return WindowsExcludedProcesses.Contains(name);
    }

    /// <summary>
    /// 1 行 1 つの OCR の行のテキスト（確かめ方の CLI の入力）から行を作る。空の行は飛ばし、上から順に並ぶ位置を付ける
    /// </summary>
    public static IReadOnlyList<ScreenTextLine> LinesFromText(string text) =>
        text.Replace("\r\n", "\n").Split('\n')
            .Select(l => l.TrimEnd('\r'))
            .Where(l => l.Trim().Length > 0)
            .Select((l, i) => new ScreenTextLine(l, 0, false, i * 20, 0))
            .ToList();

    // 設計判断: DEC-DIC-234
    /// <summary>
    /// 文字起こしの言語（"ja-JP"・"zh-TW" など）に合う OCR の言語を、使える言語（"ja"・"en-US"・"zh-Hans-CN" など）から選ぶ。なければ null。
    /// 同じタグ → 同じ言語（中国語は簡体字・繁体字も合わせる）の順
    /// </summary>
    public static string? MatchOcrLanguage(string wanted, IEnumerable<string> available)
    {
        var list = available.ToList();
        var exact = list.FirstOrDefault(a => string.Equals(a, wanted, StringComparison.OrdinalIgnoreCase));
        if (exact is not null) return exact;
        var (language, script) = LanguageAndScript(wanted);
        return list.FirstOrDefault(a =>
        {
            var (l, s) = LanguageAndScript(a);
            return l == language && (script is null || s is null || s == script);
        });
    }

    /// <summary>言語のタグの、言語（小文字）と、中国語の書き方（Hans・Hant。分からなければ null）</summary>
    private static (string Language, string? Script) LanguageAndScript(string tag)
    {
        var parts = tag.Replace('_', '-').Split('-', StringSplitOptions.RemoveEmptyEntries);
        var language = parts.Length > 0 ? parts[0].ToLowerInvariant() : "";
        if (language != "zh") return (language, null);
        foreach (var part in parts.Skip(1))
        {
            switch (part.ToUpperInvariant())
            {
                case "HANS" or "CN" or "SG": return (language, "Hans");
                case "HANT" or "TW" or "HK" or "MO": return (language, "Hant");
            }
        }
        return (language, null);
    }
}
