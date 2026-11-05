using System.Globalization;
using System.Text;
using System.Text.Json;

namespace Hanasu.Core.Ai;

// 要件: REQ-COM-061
// 設計判断: DEC-COM-161
/// <summary>
/// AI へのプロンプトの言語。文字起こしの言語（設定の LocaleIdentifier。REQ-COM-004）から決める。
/// 対応言語（README と同じ 17 言語）にないときは英語。Mac 版の PromptLanguage（Sources/Hanasu/Prompts.swift）と同じ決まり（両方を直す）
/// </summary>
public sealed class PromptLanguage
{
    public static readonly PromptLanguage En = new("en");
    public static readonly PromptLanguage Ja = new("ja");
    public static readonly PromptLanguage ZhCN = new("zh-CN");
    public static readonly PromptLanguage ZhTW = new("zh-TW");
    public static readonly PromptLanguage Ko = new("ko");
    public static readonly PromptLanguage Es = new("es");
    public static readonly PromptLanguage Fr = new("fr");
    public static readonly PromptLanguage De = new("de");
    public static readonly PromptLanguage It = new("it");
    public static readonly PromptLanguage PtBR = new("pt-BR");
    public static readonly PromptLanguage Ru = new("ru");
    public static readonly PromptLanguage Tr = new("tr");
    public static readonly PromptLanguage Vi = new("vi");
    public static readonly PromptLanguage Id = new("id");
    public static readonly PromptLanguage Pl = new("pl");
    public static readonly PromptLanguage Ar = new("ar");
    public static readonly PromptLanguage Hi = new("hi");

    /// <summary>対応言語（Mac 版の PromptLanguage.allCases と scripts/check-i18n.py の LANGUAGES と同じ並び）</summary>
    public static readonly IReadOnlyList<PromptLanguage> All = [En, Ja, ZhCN, ZhTW, Ko, Es, Fr, De, It, PtBR, Ru, Tr, Vi, Id, Pl, Ar, Hi];

    /// <summary>JSON のファイル名と同じ言語の名前（"ja"、"zh-TW" など）</summary>
    public string Code { get; }

    private CultureInfo? culture;

    private PromptLanguage(string code) => Code = code;

    public override string ToString() => Code;

    /// <summary>"ja"、"zh-TW" など、対応言語の名前から。大文字と小文字は区別しない。なければ null</summary>
    public static PromptLanguage? FromCode(string? code) =>
        All.FirstOrDefault(l => string.Equals(l.Code, code?.Trim(), StringComparison.OrdinalIgnoreCase));

    // 設計判断: DEC-COM-161
    /// <summary>
    /// 言語の識別子（ja-JP、zh-Hant-TW、pt_PT など）を、対応言語のどれかに寄せる。
    /// 中国語は繁体字（Hant）か台湾・香港・マカオなら zh-TW、それ以外は zh-CN。ポルトガル語は pt-BR。どれでもなければ英語
    /// </summary>
    public static PromptLanguage FromLocaleIdentifier(string? localeIdentifier)
    {
        var parts = (localeIdentifier ?? "").Trim().Replace('_', '-').Split('-', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length == 0) return En;
        var code = parts[0].ToLowerInvariant();
        switch (code)
        {
            case "zh":
                var subtags = parts.Skip(1).Select(p => p.ToUpperInvariant()).ToList();
                return subtags.Contains("HANT") || subtags.Any(p => p is "TW" or "HK" or "MO") ? ZhTW : ZhCN;
            case "pt":
                return PtBR;
            case "in":
                return Id;
            default:
                return All.FirstOrDefault(l => l.Code == code) ?? En;
        }
    }

    private static volatile PromptLanguage? overrideLanguage;
    // 設定の既定の言語（ja-JP）と同じ
    private static volatile PromptLanguage settingsLanguage = Ja;

    /// <summary>CLI（--prompt-language）とテストで一時的に変える。null なら設定の言語</summary>
    public static PromptLanguage? Override
    {
        get => overrideLanguage;
        set => overrideLanguage = value;
    }

    /// <summary>いまのプロンプトの言語（設定の文字起こしの言語）</summary>
    public static PromptLanguage Current => overrideLanguage ?? settingsLanguage;

    /// <summary>設定の文字起こしの言語を反映する。SettingsService が、読み込んだときと設定を変えたときに呼ぶ</summary>
    public static void UseSettings(string? localeIdentifier) => settingsLanguage = FromLocaleIdentifier(localeIdentifier);

    /// <summary>日付の曜日や月の名前を、この言語で書くためのカルチャ（暦はグレゴリオ暦にそろえる）</summary>
    public CultureInfo Culture => culture ??= MakeCulture(this == Ja ? "ja-JP" : Code);

    private static CultureInfo MakeCulture(string name)
    {
        try
        {
            var c = (CultureInfo)CultureInfo.GetCultureInfo(name).Clone();
            if (c.DateTimeFormat.Calendar is not GregorianCalendar && c.OptionalCalendars.OfType<GregorianCalendar>().FirstOrDefault() is { } gregorian)
            {
                c.DateTimeFormat.Calendar = gregorian;
            }
            return CultureInfo.ReadOnly(c);
        }
        catch (CultureNotFoundException)
        {
            return CultureInfo.InvariantCulture;
        }
    }

    /// <summary>日時を、Mac 版の DateFormatter と同じ書式（"M/d (E)" などの Unicode の書式）で、この言語で書く</summary>
    public string FormatDate(DateTime date, string pattern) => date.ToString(DotNetDateFormat(pattern), Culture);

    /// <summary>
    /// Unicode（Mac の DateFormatter）の日付の書式を、.NET の書式に直す。使うのは y・M・d・E・H・h・m・s・a と '…' だけ。
    /// それ以外の文字はそのまま書く（.NET では「/」「:」がカルチャの区切りになるので、エスケープする）
    /// </summary>
    internal static string DotNetDateFormat(string pattern)
    {
        var sb = new StringBuilder();
        var i = 0;
        while (i < pattern.Length)
        {
            var c = pattern[i];
            if (c == '\'')
            {
                // '' は「'」そのもの。'…' の中はそのまま書く（中の '' も「'」）
                if (i + 1 < pattern.Length && pattern[i + 1] == '\'')
                {
                    sb.Append("\\'");
                    i += 2;
                    continue;
                }
                i++;
                while (i < pattern.Length)
                {
                    if (pattern[i] == '\'')
                    {
                        if (i + 1 < pattern.Length && pattern[i + 1] == '\'')
                        {
                            sb.Append("\\'");
                            i += 2;
                            continue;
                        }
                        i++;
                        break;
                    }
                    sb.Append('\\').Append(pattern[i]);
                    i++;
                }
                continue;
            }
            if (char.IsAsciiLetter(c))
            {
                var j = i;
                while (j < pattern.Length && pattern[j] == c) j++;
                var n = j - i;
                sb.Append(c switch
                {
                    'E' or 'c' => n >= 4 ? "dddd" : "ddd",
                    'y' => n == 2 ? "yy" : "yyyy",
                    'M' or 'L' => new string('M', Math.Min(n, 4)),
                    'd' or 'H' or 'h' or 'm' or 's' => new string(c, Math.Min(n, 2)),
                    'a' => "tt",
                    _ => string.Concat(Enumerable.Repeat("\\" + c, n)),
                });
                i = j;
                continue;
            }
            sb.Append('\\').Append(c);
            i++;
        }
        return sb.ToString();
    }
}

// 要件: REQ-COM-061
// 設計判断: DEC-COM-160
/// <summary>
/// AI へのプロンプトの文面。言語ごとの JSON（Sources/Hanasu/Resources/Prompts/&lt;言語&gt;.json）を、Mac 版と共有する。
/// Hanasu.Core.dll に埋め込んで読む（Hanasu.Core.csproj。写しは置かない）ので、Mac と Windows で同じ文面になる（DEC-COM-102）。
/// 値は文字列か、1 行 1 要素の配列（List で読むものは 1 項目 1 要素）。${name} は引数で埋める。
/// </summary>
public static class Prompts
{
    /// <summary>埋め込んだ JSON のリソース名の先頭（Hanasu.Core.csproj の LogicalName と同じ）</summary>
    public const string ResourcePrefix = "Hanasu.Prompts.";

    private static readonly Dictionary<PromptLanguage, Lazy<IReadOnlyDictionary<string, string[]>>> Tables =
        PromptLanguage.All.ToDictionary(l => l, l => new Lazy<IReadOnlyDictionary<string, string[]>>(() => Load(l), LazyThreadSafetyMode.ExecutionAndPublication));

    /// <summary>キーの文面（language を省くといまの言語）。その言語になければ英語、英語にもなければ日本語を使う</summary>
    public static string Text(string key, params (string Name, string Value)[] args) => Text(key, null, args);

    /// <summary>キーの文面。その言語になければ英語、英語にもなければ日本語を使う（漏れは scripts/check-i18n.py が見つける）</summary>
    public static string Text(string key, PromptLanguage? language, params (string Name, string Value)[] args)
    {
        var text = string.Join("\n", Lookup(key, language ?? PromptLanguage.Current));
        return args.Length == 0 ? text : Fill(text, args.ToDictionary(a => a.Name, a => a.Value));
    }

    /// <summary>項目の一覧</summary>
    public static IReadOnlyList<string> List(string key, PromptLanguage? language = null) => Lookup(key, language ?? PromptLanguage.Current);

    /// <summary>すべての言語での文面（ほかの言語で作った議事録や、古い議事録を読むときに使う）</summary>
    public static IReadOnlyList<string> AllTexts(string key)
    {
        var seen = new List<string>();
        foreach (var language in PromptLanguage.All)
        {
            var text = Text(key, language);
            if (text.Length > 0 && !seen.Contains(text)) seen.Add(text);
        }
        return seen;
    }

    /// <summary>その言語の JSON にあるキー（"_" で始まる説明は除く）。テスト用</summary>
    public static IReadOnlyList<string> Keys(PromptLanguage language) => Tables[language].Value.Keys.ToList();

    /// <summary>その言語の JSON が埋め込まれているか</summary>
    public static bool HasCatalog(PromptLanguage language) => Tables[language].Value.Count > 0;

    /// <summary>${name} を引数で埋める。1 回だけ走査するので、埋めた値の中の ${…} はそのまま残る（Mac 版の Prompts.fill と同じ）</summary>
    public static string Fill(string template, IReadOnlyDictionary<string, string> args)
    {
        if (args.Count == 0 || !template.Contains("${", StringComparison.Ordinal)) return template;
        var sb = new StringBuilder();
        var position = 0;
        while (true)
        {
            var open = template.IndexOf("${", position, StringComparison.Ordinal);
            if (open < 0) break;
            sb.Append(template, position, open - position);
            var close = template.IndexOf('}', open + 2);
            if (close < 0)
            {
                position = open;
                break;
            }
            var name = template[(open + 2)..close];
            sb.Append(args.TryGetValue(name, out var value) ? value : "${" + name + "}");
            position = close + 1;
        }
        return sb.Append(template, position, template.Length - position).ToString();
    }

    private static string[] Lookup(string key, PromptLanguage language)
    {
        foreach (var candidate in new[] { language, PromptLanguage.En, PromptLanguage.Ja })
        {
            if (Tables[candidate].Value.TryGetValue(key, out var value)) return value;
        }
        throw new KeyNotFoundException($"プロンプトのキーがありません: {key}");
    }

    private static IReadOnlyDictionary<string, string[]> Load(PromptLanguage language)
    {
        var table = new Dictionary<string, string[]>();
        using var stream = typeof(Prompts).Assembly.GetManifestResourceStream(ResourcePrefix + language.Code + ".json");
        if (stream is null) return table;
        using var document = JsonDocument.Parse(stream);
        foreach (var property in document.RootElement.EnumerateObject())
        {
            if (property.Name.StartsWith('_')) continue;
            table[property.Name] = property.Value.ValueKind switch
            {
                JsonValueKind.String => [property.Value.GetString()!],
                JsonValueKind.Array => property.Value.EnumerateArray().Select(e => e.GetString() ?? "").ToArray(),
                _ => [],
            };
        }
        return table;
    }
}
