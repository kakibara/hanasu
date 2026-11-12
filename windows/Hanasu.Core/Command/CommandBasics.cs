using System.Globalization;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace Hanasu.Core.Command;

// 利用者向けの hanasu コマンド（Windows の cli\hanasu.exe）の中身。Mac 版 HanasuCommand.swift などの移植。
// 計画は docs/plans/cli-windows.md、作りは docs/design/cli.md の「Windows」。exe（Hanasu.Command）はここを呼ぶだけ。
// 時計・時差・出力・AI のクライアントは CommandContext で渡す（テストで固定・差し替えるため）。

// 要件: REQ-COM-182
/// <summary>終了コード（Mac 版と同じ値）</summary>
public enum HanasuExit
{
    Ok = 0,
    /// <summary>失敗（AI の失敗など）</summary>
    Failure = 1,
    /// <summary>使い方の誤り</summary>
    Usage = 2,
    /// <summary>認証情報・モデルがない</summary>
    Credentials = 3,
    /// <summary>会議が見つからない・1 つに決まらない</summary>
    NotFound = 4,
    /// <summary>会議のフォルダを読む権限がない</summary>
    Denied = 5,
}

/// <summary>コマンドを止める誤り。Message は stderr に出し、Details はその下に 1 行ずつ出す</summary>
public sealed class CommandException(HanasuExit exit, string message, IReadOnlyList<string>? details = null) : Exception(message)
{
    public HanasuExit Exit { get; } = exit;
    public IReadOnlyList<string> Details { get; } = details ?? Array.Empty<string>();

    public static CommandException Usage(string message) => new(HanasuExit.Usage, message, [Strings.Cmd_SeeHelp]);
}

/// <summary>標準入力がつながっている先</summary>
public enum StdinKind
{
    /// <summary>端末（打つのを待つ）</summary>
    Terminal,
    /// <summary>パイプ・ファイル</summary>
    Redirected,
    /// <summary>何もつながっていない</summary>
    None,
}

// 要件: REQ-COM-181
/// <summary>
/// コマンドの入出力。stdout には結果だけ、途中経過・警告・エラーは stderr。
/// exe は、コンソールなら UTF-16 で、パイプ・ファイルなら UTF-8（BOM なし・改行は \n）で書く（DEC-COM-195）。テストは文字列にためる
/// </summary>
public interface ICommandConsole
{
    void Out(string text);
    void Err(string text);
    StdinKind StdinKind { get; }
    /// <summary>標準入力を終わりまで読む</summary>
    string ReadAllStdin();
    /// <summary>引数があるときに、標準入力にも文章が来ているか（パイプ・ファイルで、待たずに読める分）。なければ null</summary>
    string? PendingStdin();
    /// <summary>MCP の 1 行を読む（\n で区切る。U+2028 では切らない）。閉じたら null</summary>
    Task<string?> ReadProtocolLineAsync(CancellationToken cancellationToken);
    /// <summary>MCP のメッセージ 1 行を、本当の stdout に書く（DEC-COM-186 と同じ守り方。WD6）</summary>
    void WriteProtocolLine(string line);
}

/// <summary>出力の決まり</summary>
public static class CommandOutput
{
    public static void Out(this ICommandConsole console, IEnumerable<string> lines) => console.Out(string.Join("\n", lines));

    // 要件: REQ-COM-181
    // 設計判断: DEC-COM-181
    /// <summary>--json の出力。版（schemaVersion）を付け、キーを並べる</summary>
    public static void Json(this ICommandConsole console, JsonObject json)
    {
        json["schemaVersion"] = CommandJson.SchemaVersion;
        console.Out(CommandJson.Serialize(json, indented: true));
    }

    public static void Error(this ICommandConsole console, CommandException error)
    {
        console.Err("hanasu: " + error.Message);
        foreach (var line in error.Details) console.Err("  " + line);
    }
}

// 設計判断: DEC-COM-181
public static class CommandJson
{
    /// <summary>項目を消したり意味を変えたりするときに上げる（足すだけなら上げない）</summary>
    public const int SchemaVersion = 1;

    private static readonly JsonSerializerOptions Indented = new()
    {
        WriteIndented = true,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    private static readonly JsonSerializerOptions Compact = new()
    {
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    /// <summary>キーを並べて書く（Mac 版の sortedKeys と同じ並び）</summary>
    public static string Serialize(JsonNode? node, bool indented = false) =>
        (Sorted(node)?.ToJsonString(indented ? Indented : Compact)) ?? "null";

    private static JsonNode? Sorted(JsonNode? node) => node switch
    {
        JsonObject o => new JsonObject(o.OrderBy(p => p.Key, StringComparer.Ordinal)
            .Select(p => KeyValuePair.Create(p.Key, Sorted(p.Value)))),
        JsonArray a => new JsonArray(a.Select(Sorted).ToArray()),
        null => null,
        _ => JsonNode.Parse(node.ToJsonString()),
    };

    // 要件: REQ-COM-181
    /// <summary>ISO 8601 で、時差を付ける（例: 2026-11-02T13:12:00+09:00。時差が 0 なら Z。Mac の ISO8601DateFormatter と同じ）</summary>
    public static string Date(DateTimeOffset date, TimeZoneInfo zone)
    {
        var local = TimeZoneInfo.ConvertTime(date, zone);
        var text = local.ToString("yyyy-MM-dd'T'HH:mm:ss", CultureInfo.InvariantCulture);
        return local.Offset == TimeSpan.Zero ? text + "Z" : text + local.ToString("zzz", CultureInfo.InvariantCulture);
    }

    /// <summary>秒を小数 2 桁までにする</summary>
    public static double Seconds(double value) => Math.Round(value * 100, MidpointRounding.AwayFromZero) / 100;

    public static JsonNode? Optional(string? value) => value is null ? null : JsonValue.Create(value);
}

// 要件: REQ-COM-182
/// <summary>コマンドの引数（位置の引数・値のない旗・値のあるオプション）。Mac 版 HanasuArguments と同じ読み方</summary>
public sealed class CommandArguments
{
    public List<string> Positionals { get; } = new();
    public HashSet<string> Flags { get; } = new(StringComparer.Ordinal);
    public Dictionary<string, string> Values { get; } = new(StringComparer.Ordinal);

    public bool Has(string flag) => Flags.Contains(flag);
    public string? Value(string name) => Values.TryGetValue(name, out var v) ? v : null;
    public bool Json => Has("--json");
    public bool WantsHelp => Has("--help") || Has("-h");

    /// <param name="flags">値を取らないオプション（--json など）</param>
    /// <param name="options">値を取るオプション（--limit 10 か --limit=10）</param>
    public static CommandArguments Parse(IReadOnlyList<string> arguments, IEnumerable<string> flags, IEnumerable<string> options)
    {
        var flagSet = flags.ToHashSet(StringComparer.Ordinal);
        var optionSet = options.ToHashSet(StringComparer.Ordinal);
        var result = new CommandArguments();
        var onlyPositionals = false;
        for (var index = 0; index < arguments.Count;)
        {
            var argument = arguments[index++];
            if (onlyPositionals || !argument.StartsWith('-') || argument == "-")
            {
                result.Positionals.Add(argument);
                continue;
            }
            if (argument == "--")
            {
                onlyPositionals = true;
                continue;
            }
            var equals = argument.IndexOf('=');
            var name = equals >= 0 ? argument[..equals] : argument;
            string? inline = equals >= 0 ? argument[(equals + 1)..] : null;
            if (flagSet.Contains(name) && inline is null)
            {
                result.Flags.Add(name);
            }
            else if (optionSet.Contains(name))
            {
                if (inline is not null) result.Values[name] = inline;
                else if (index < arguments.Count) result.Values[name] = arguments[index++];
                else throw new CommandException(HanasuExit.Usage, string.Format(Strings.Cmd_NeedsValue, name));
            }
            else
            {
                throw new CommandException(HanasuExit.Usage, string.Format(Strings.Cmd_UnknownOption, argument), [Strings.Cmd_SeeHelp]);
            }
        }
        return result;
    }

    /// <summary>1 以上の整数のオプション（なければ null）</summary>
    public int? PositiveInt(string name)
    {
        if (Value(name) is not { } raw) return null;
        if (!int.TryParse(raw, NumberStyles.None, CultureInfo.InvariantCulture, out var value) || value <= 0)
        {
            throw new CommandException(HanasuExit.Usage, string.Format(Strings.Cmd_NeedsPositiveInt, name, raw));
        }
        return value;
    }

    public void NoPositionals()
    {
        if (Positionals.Count > 0)
        {
            throw new CommandException(HanasuExit.Usage, string.Format(Strings.Cmd_ExtraArgument, Positionals[0]), [Strings.Cmd_SeeHelp]);
        }
    }
}

// 要件: REQ-MTG-120
// 設計判断: DEC-MTG-122
/// <summary>--since / --until。7d・24h・2w（今からさかのぼる）か、日付（2026-11-01。その時差での 0 時）か、日時（ISO 8601）</summary>
public sealed partial class CommandPeriod
{
    public DateTimeOffset? Since { get; init; }
    /// <summary>この時刻より前（含まない）</summary>
    public DateTimeOffset? Until { get; init; }

    public bool IsSpecified => Since is not null || Until is not null;

    public bool Contains(DateTimeOffset date) =>
        (Since is not { } since || date >= since) && (Until is not { } until || date < until);

    public static CommandPeriod From(CommandArguments args, CommandContext context) =>
        From(args.Value("--since"), args.Value("--until"), context);

    public static CommandPeriod From(string? since, string? until, CommandContext context) => new()
    {
        Since = since is null ? null : Parse(since, "--since", endOfDay: false, context.Now(), context.TimeZone),
        Until = until is null ? null : Parse(until, "--until", endOfDay: true, context.Now(), context.TimeZone),
    };

    /// <summary>endOfDay なら、日付はその日の終わり（翌日の 0 時）を指す（--until 2026-11-05 は 5 日を含む）</summary>
    public static DateTimeOffset Parse(string raw, string option, bool endOfDay, DateTimeOffset now, TimeZoneInfo zone)
    {
        var value = raw.Trim();
        if (value.Length >= 2 && int.TryParse(value[..^1], NumberStyles.None, CultureInfo.InvariantCulture, out var n))
        {
            double? seconds = value[^1] switch { 'h' => 3600, 'd' => 86400, 'w' => 7 * 86400, _ => null };
            if (seconds is { } s) return now.AddSeconds(-n * s);
        }
        if (IsDate(value) && DateTime.TryParseExact(value, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var day))
        {
            return StartOfDay(endOfDay ? day.AddDays(1) : day, zone);
        }
        if (DateTimeOffset.TryParseExact(value, ["yyyy-MM-dd'T'HH:mm:ssK", "yyyy-MM-dd'T'HH:mm:ss.FFFFFFFK"],
                CultureInfo.InvariantCulture, DateTimeStyles.None, out var iso) && HasOffset(value))
        {
            return iso;
        }
        foreach (var format in new[] { "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm" })
        {
            if (DateTime.TryParseExact(value, format, CultureInfo.InvariantCulture, DateTimeStyles.None, out var local))
            {
                return new DateTimeOffset(local, zone.GetUtcOffset(local));
            }
        }
        throw new CommandException(HanasuExit.Usage, string.Format(Strings.Cmd_CannotParseValue, option, raw), [Strings.Cmd_NotePeriod]);
    }

    private static bool HasOffset(string value) => value.EndsWith('Z') || OffsetPattern().IsMatch(value);

    public static bool IsDate(string value) => DatePattern().IsMatch(value);

    /// <summary>その日の 0 時（その時差で）</summary>
    public static DateTimeOffset StartOfDay(DateTime day, TimeZoneInfo zone)
    {
        var midnight = day.Date;
        return new DateTimeOffset(midnight, zone.GetUtcOffset(midnight));
    }

    /// <summary>その日時の、その時差での日付（yyyy-MM-dd）</summary>
    public static string DayString(DateTimeOffset date, TimeZoneInfo zone) =>
        TimeZoneInfo.ConvertTime(date, zone).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);

    [GeneratedRegex(@"^\d{4}-\d{2}-\d{2}$")]
    private static partial Regex DatePattern();

    [GeneratedRegex(@"[+-]\d{2}:?\d{2}$")]
    private static partial Regex OffsetPattern();
}

/// <summary>書記素（.NET のテキスト要素。Swift の Character と同じ単位）で数える・切る</summary>
public static class TextElements
{
    public static int Count(string text) => new StringInfo(text).LengthInTextElements;

    public static string Prefix(string text, int count)
    {
        var info = new StringInfo(text);
        return count >= info.LengthInTextElements ? text : info.SubstringByTextElements(0, count);
    }
}
