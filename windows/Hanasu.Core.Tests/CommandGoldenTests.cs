using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Hanasu.Core.Ai;
using Hanasu.Core.Command;
using Hanasu.Core.Dictation;
using Hanasu.Core.Gemini;
using Hanasu.Core.Settings;

namespace Hanasu.Core.Tests;

/// <summary>コマンドの入出力を文字列にためる（stdin は渡した文字列か、なし）</summary>
internal sealed class FakeConsole(string? stdin = null, IEnumerable<string>? protocolInput = null) : ICommandConsole
{
    private readonly Queue<string> protocol = new(protocolInput ?? []);
    public StringBuilder Stdout { get; } = new();
    public StringBuilder Stderr { get; } = new();
    public List<string> ProtocolOutput { get; } = new();

    public void Out(string text) => Stdout.Append(text.EndsWith('\n') ? text : text + "\n");
    public void Err(string text) => Stderr.Append(text).Append('\n');
    public StdinKind StdinKind => stdin is null ? StdinKind.None : StdinKind.Redirected;
    public string ReadAllStdin() => stdin ?? "";
    public string? PendingStdin() => stdin;
    public Task<string?> ReadProtocolLineAsync(CancellationToken cancellationToken) => Task.FromResult(protocol.TryDequeue(out var line) ? line : null);
    public void WriteProtocolLine(string line)
    {
        lock (ProtocolOutput) ProtocolOutput.Add(line);
    }
}

/// <summary>決めた答えを返すだけの AI（何も送らない）。最後に受け取った内容を残す</summary>
internal sealed class FakeAi(string answer) : ITextAiClient
{
    public string ProviderName => "fake";
    public string? LastSystem { get; private set; }
    public string? LastUser { get; private set; }
    public TextPurpose? LastPurpose { get; private set; }
    public Exception? Failure { get; set; }

    public Task<string> GenerateTextAsync(TextPurpose purpose, string systemInstruction, string userText, string model, CancellationToken cancellationToken = default)
    {
        LastPurpose = purpose;
        LastSystem = systemInstruction;
        LastUser = userText;
        return Failure is { } e ? Task.FromException<string>(e) : Task.FromResult(answer);
    }

    public Task<string> RefineAsync(RefineRequest request, CancellationToken cancellationToken = default) =>
        GenerateTextAsync(TextPurpose.Refine, GeminiPrompts.SystemInstruction(request.OutputLanguage), GeminiPrompts.UserPrompt(request), request.Model, cancellationToken);

    public Task<string> TranslateAsync(RefineRequest request, TranslationLanguage language, CancellationToken cancellationToken = default) =>
        GenerateTextAsync(TextPurpose.Translate, GeminiPrompts.TranslationSystemInstruction(language), GeminiPrompts.UserPrompt(request, language), request.Model, cancellationToken);
}

/// <summary>共有のテストデータ（common/testdata/cli）を読む</summary>
internal static class CommandTestData
{
    public static string Directory
    {
        get
        {
            for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir is not null; dir = dir.Parent)
            {
                var candidate = Path.Combine(dir.FullName, "common", "testdata", "cli");
                if (File.Exists(Path.Combine(candidate, "cases.json"))) return candidate;
            }
            throw new DirectoryNotFoundException("common/testdata/cli");
        }
    }

    public static JsonObject Read(string name) => JsonNode.Parse(File.ReadAllText(Path.Combine(Directory, name)))!.AsObject();

    public static AppSettings Settings()
    {
        var json = Read("settings.json");
        return new AppSettings
        {
            LocaleIdentifier = json["localeIdentifier"]!.GetValue<string>(),
            DictionaryText = json["dictionaryText"]!.GetValue<string>(),
            ExtraInstructions = json["extraInstructions"]!.GetValue<string>(),
            SendAppName = json["sendAppName"]!.GetValue<bool>(),
            DictationAi = TextAiProvider.Gemini,
            MeetingAi = TextAiProvider.Gemini,
            // 要件: REQ-DIC-023（Mac の customAppStyles・appStyles を、Windows の CustomStyles・AppStyles に移す。アプリは exe で引く）
            CustomStyles = (json["customAppStyles"]?.AsArray() ?? []).Select(c => new CustomStyle
            {
                Id = Guid.Parse(c!["id"]!.GetValue<string>()),
                Name = c["name"]!.GetValue<string>(),
                Language = c["language"]!.GetValue<string>(),
                Rules = c["rules"]!.AsArray().Select(r => r!.GetValue<string>()).ToList(),
            }).ToList(),
            AppStyles = json["appStyles"]?.AsArray().Select(a => new AppStyleSetting
            {
                Exe = a!["exe"]!.GetValue<string>(),
                Name = a["name"]!.GetValue<string>(),
                Preset = a["preset"]!.GetValue<string>(),
                Rules = a["rules"]?.GetValue<string>() ?? "",
                CustomStyleId = a["customStyleID"] is { } id ? Guid.Parse(id.GetValue<string>()) : null,
            }).ToList(),
        };
    }

    public static CommandContext Context(FakeConsole console, FakeAi? ai = null, string? meetingsDirectory = null)
    {
        var spec = Read("cases.json");
        return new CommandContext
        {
            Settings = Settings(),
            Console = console,
            Now = () => DateTimeOffset.Parse(spec["now"]!.GetValue<string>()),
            TimeZone = TimeZoneInfo.FindSystemTimeZoneById(spec["timeZone"]!.GetValue<string>()),
            Environment = new Dictionary<string, string> { ["HANASU_MEETINGS_DIR"] = meetingsDirectory ?? Path.Combine(Directory, "meetings") },
            Nonce = spec["nonce"]!.GetValue<string>(),
            ClientFactory = ai is null ? null : (_, _, _) => ai,
            ExecutablePath = @"C:\Users\test\AppData\Local\Hanasu\cli\hanasu.exe",
            Version = "test",
        };
    }
}

// 確かめ方: REQ-COM-180, REQ-COM-181, REQ-MTG-120, REQ-MTG-121, REQ-MTG-123, REQ-MTG-124, REQ-MTG-126, REQ-MTG-127, REQ-DIC-160, REQ-DIC-161, REQ-DIC-162
// 設計判断: DEC-COM-192
/// <summary>Mac と同じコマンドを動かし、Mac が書いた期待する出力（expected.json）と同じかを比べる</summary>
[Collection(PromptLanguageCollection.Name)]
public class CommandGoldenTests
{
    public static IEnumerable<object[]> Cases() =>
        CommandTestData.Read("cases.json")["cases"]!.AsArray().Select(c => new object[] { c!["name"]!.GetValue<string>() });

    [Theory]
    [MemberData(nameof(Cases))]
    public async Task SameAsMac(string name)
    {
        var spec = CommandTestData.Read("cases.json");
        var item = spec["cases"]!.AsArray().First(c => c!["name"]!.GetValue<string>() == name)!.AsObject();
        var compare = item["compare"]!.GetValue<string>();
        var ai = new FakeAi(spec["fakeAnswer"]!.GetValue<string>());
        var console = new FakeConsole();
        var context = CommandTestData.Context(console, item["ai"]?.GetValue<bool>() == true ? ai : null);
        var actual = new JsonObject();
        if (item["mcp"] is JsonObject call)
        {
            var server = new McpServer(new McpTools(Path.Combine(CommandTestData.Directory, "meetings"), null, null, context), context);
            var response = await server.HandleAsync(new JsonObject
            {
                ["jsonrpc"] = "2.0",
                ["id"] = 2,
                ["method"] = "tools/call",
                ["params"] = call.DeepClone(),
            }, CancellationToken.None);
            var result = response!["result"]!.AsObject();
            var isError = result["isError"]!.GetValue<bool>();
            actual["isError"] = isError;
            if (compare == "mcp")
            {
                var text = result["content"]![0]!["text"]!.GetValue<string>();
                try { actual["result"] = JsonNode.Parse(text); } catch (JsonException) { actual["result"] = text; }
            }
        }
        else
        {
            var args = item["args"]!.AsArray().Select(a => a is JsonObject o ? o["windows"]!.GetValue<string>() : a!.GetValue<string>()).ToList();
            var exit = await HanasuCommand.RunAsync(args, context);
            actual["exit"] = (int)exit;
            if (compare.Contains("json")) actual["json"] = JsonNode.Parse(console.Stdout.ToString());
            if (compare.Contains("prompt")) actual["prompt"] = Prompt(console.Stderr.ToString());
        }
        var ignore = spec["ignoreKeys"]!.AsArray().Select(k => k!.GetValue<string>()).ToHashSet();
        var replace = spec["replace"]!.AsObject().ToDictionary(p => p.Key, p => p.Value!.GetValue<string>());
        var expected = CommandTestData.Read("expected.json")[name];
        var expectedText = CommandJson.Serialize(Normalize(expected, [], []), indented: true);
        var actualText = CommandJson.Serialize(Normalize(actual, ignore, replace), indented: true);
        // 食い違いを調べるとき: 環境変数 HANASU_GOLDEN_DUMP のフォルダに、両方を書く
        if (expectedText != actualText && Environment.GetEnvironmentVariable("HANASU_GOLDEN_DUMP") is { Length: > 0 } dump)
        {
            File.WriteAllText(Path.Combine(dump, name + ".expected.json"), expectedText);
            File.WriteAllText(Path.Combine(dump, name + ".actual.json"), actualText);
        }
        Assert.Equal(expectedText, actualText);
    }

    private static string? Prompt(string stderr)
    {
        const string start = "----- system -----\n";
        var i = stderr.IndexOf(start, StringComparison.Ordinal);
        if (i < 0) return null;
        var j = stderr.IndexOf("\n------------------", i + start.Length, StringComparison.Ordinal);
        return j < 0 ? null : stderr[(i + start.Length)..j];
    }

    private static JsonNode? Normalize(JsonNode? node, HashSet<string> ignore, Dictionary<string, string> replace) => node switch
    {
        JsonObject o => new JsonObject(o.Where(p => !ignore.Contains(p.Key)).Select(p => KeyValuePair.Create(p.Key, Normalize(p.Value, ignore, replace)))),
        JsonArray a => new JsonArray(a.Select(n => Normalize(n, ignore, replace)).ToArray()),
        JsonValue v when v.GetValueKind() == JsonValueKind.String =>
            replace.Aggregate(v.GetValue<string>(), (text, r) => text.Replace(r.Key, r.Value, StringComparison.Ordinal)).Normalize(NormalizationForm.FormC),
        JsonValue v when v.GetValueKind() == JsonValueKind.Number => JsonValue.Create(double.Parse(v.ToJsonString(), System.Globalization.CultureInfo.InvariantCulture)),
        _ => node?.DeepClone(),
    };
}
