using System.Text.Json.Nodes;
using Hanasu.Core.Ai;
using Hanasu.Core.Command;
using Hanasu.Core.Dictation;
using Hanasu.Core.Gemini;
using Hanasu.Core.Meetings;

namespace Hanasu.Core.Tests;

/// <summary>hanasu コマンドの、共有のテストデータでは比べない振る舞い（終了コード・失敗・MCP の手順）</summary>
[Collection(PromptLanguageCollection.Name)]
public class CommandTests
{
    private static async Task<(HanasuExit Exit, FakeConsole Console)> Run(string[] args, FakeAi? ai = null, string? stdin = null, string? meetings = null)
    {
        var console = new FakeConsole(stdin);
        var exit = await HanasuCommand.RunAsync(args, CommandTestData.Context(console, ai, meetings));
        return (exit, console);
    }

    // 確かめ方: REQ-COM-182
    [Fact]
    public async Task ExitCodesMatchMac()
    {
        Assert.Equal(HanasuExit.Ok, (await Run(["--version"])).Exit);
        Assert.Equal(HanasuExit.Usage, (await Run(["nope"])).Exit);
        Assert.Equal(HanasuExit.Usage, (await Run(["meetings", "list", "--limit", "0"])).Exit);
        Assert.Equal(HanasuExit.Usage, (await Run(["meetings", "list", "--bogus"])).Exit);
        Assert.Equal(HanasuExit.NotFound, (await Run(["meetings", "show", "2020-01-01_0000"])).Exit);
        // 日付で 2 件当たれば 4 で、候補を stderr に出す
        var ambiguous = await Run(["meetings", "show", "2026-10-02"]);
        Assert.Equal(HanasuExit.NotFound, ambiguous.Exit);
        Assert.Contains("2026-10-02_1000", ambiguous.Console.Stderr.ToString());
        Assert.Empty(ambiguous.Console.Stdout.ToString());
        Assert.Equal(HanasuExit.Usage, (await Run(["meetings", "list", "--since", "yesterday"])).Exit);
    }

    // 確かめ方: REQ-COM-186（Windows に apple はない）
    [Fact]
    public async Task AppleIsUsageError()
    {
        var result = await Run(["refine", "テスト", "--ai", "apple"]);
        Assert.Equal(HanasuExit.Usage, result.Exit);
        Assert.Contains("Windows", result.Console.Stderr.ToString());
        Assert.Equal(HanasuExit.Usage, (await Run(["refine", "テスト", "--ai", "gpt"])).Exit);
    }

    // 確かめ方: REQ-COM-186, REQ-COM-182（認証情報がなければ 3、stdout には何も出さない）
    [Fact]
    public async Task MissingCredentialsExitThree()
    {
        var result = await Run(["refine", "テスト", "--ai", "claude"]);
        Assert.Equal(HanasuExit.Credentials, result.Exit);
        Assert.Empty(result.Console.Stdout.ToString());
    }

    // 確かめ方: REQ-DIC-160, REQ-DIC-161（AI が失敗したら 1 で何も出さない。--fallback-raw なら原文）
    [Fact]
    public async Task FailureAndFallback()
    {
        var ai = new FakeAi("x") { Failure = new InvalidOperationException("boom") };
        var failed = await Run(["refine", "えーと明日です"], ai);
        Assert.Equal(HanasuExit.Failure, failed.Exit);
        Assert.Empty(failed.Console.Stdout.ToString());
        var fallback = await Run(["refine", "えーと明日です", "--fallback-raw", "--json"], ai);
        Assert.Equal(HanasuExit.Ok, fallback.Exit);
        var json = JsonNode.Parse(fallback.Console.Stdout.ToString())!;
        Assert.True(json["fallback"]!.GetValue<bool>());
        Assert.Equal("えーと明日です", json["text"]!.GetValue<string>());
    }

    // 確かめ方: REQ-DIC-160（文章は引数か stdin のどちらか。両方・どちらもなしは 2）
    [Fact]
    public async Task TextInput()
    {
        var ai = new FakeAi("整えた文章です。");
        var piped = await Run(["refine"], ai, stdin: "えーと、明日です\n");
        Assert.Equal(HanasuExit.Ok, piped.Exit);
        Assert.Equal("整えた文章です。\n", piped.Console.Stdout.ToString());
        Assert.Contains("えーと、明日です", ai.LastUser);
        Assert.Equal(HanasuExit.Usage, (await Run(["refine", "引数"], ai, stdin: "パイプ")).Exit);
        Assert.Equal(HanasuExit.Usage, (await Run(["refine"], ai)).Exit);
        Assert.Equal(HanasuExit.Usage, (await Run(["refine"], ai, stdin: "   ")).Exit);
        Assert.Equal(HanasuExit.Usage, (await Run(["refine", new string('あ', CommandTextInput.MaxLength + 1)], ai)).Exit);
    }

    // 確かめ方: REQ-DIC-161（書き換えは Edit の用途で送り、コードブロックは外す）
    [Fact]
    public async Task EditUsesEditPurpose()
    {
        var ai = new FakeAi("```\nご丁寧に\n```");
        var result = await Run(["edit", "丁寧に", "明日です"], ai);
        Assert.Equal(TextPurpose.Edit, ai.LastPurpose);
        Assert.Equal("ご丁寧に\n", result.Console.Stdout.ToString());
    }

    // 確かめ方: REQ-MTG-126（ask は Ask の用途で送る。期間に会議がなければ送らずに 4）
    [Fact]
    public async Task AskUsesAskPurposeAndStopsWithoutMeetings()
    {
        var ai = new FakeAi("答え（M1: 予算の定例）");
        var answered = await Run(["ask", "予算"], ai);
        Assert.Equal(HanasuExit.Ok, answered.Exit);
        Assert.Equal(TextPurpose.Ask, ai.LastPurpose);
        Assert.Contains("* M1  2026-10-01_0900", answered.Console.Stdout.ToString());
        var none = new FakeAi("x");
        var empty = await Run(["ask", "予算", "--since", "2026-12-01"], none);
        Assert.Equal(HanasuExit.NotFound, empty.Exit);
        Assert.Null(none.LastPurpose);
    }

    // 確かめ方: REQ-MTG-120, REQ-COM-185（DEC-MTG-153。読めない会議を数え、指定した会議が読めなければ 5）
    [Fact]
    public async Task UnreadableMeetingsAreCounted()
    {
        var dir = TestKeys.TempDirectory();
        foreach (var source in Directory.GetDirectories(Path.Combine(CommandTestData.Directory, "meetings")))
        {
            var target = Path.Combine(dir, Path.GetFileName(source));
            Directory.CreateDirectory(target);
            File.Copy(Path.Combine(source, "meeting.json"), Path.Combine(target, "meeting.json"));
        }
        // 読み書きを共有しない開き方で開いたままにする（.NET は Mac・Linux でも、共有しない開き方を守る）
        var locked = Path.Combine(dir, "2026-09-01 0900");
        Directory.CreateDirectory(locked);
        File.WriteAllText(Path.Combine(locked, "meeting.json"), "{}");
        using var holder = new FileStream(Path.Combine(locked, "meeting.json"), FileMode.Open, FileAccess.ReadWrite, FileShare.None);
        Directory.CreateDirectory(Path.Combine(dir, "broken"));
        File.WriteAllText(Path.Combine(dir, "broken", "meeting.json"), "{");

        var list = await Run(["meetings", "list", "--json"], meetings: dir);
        var json = JsonNode.Parse(list.Console.Stdout.ToString())!;
        Assert.Equal(4, json["meetings"]!.AsArray().Count);
        Assert.Equal(1, json["unreadableMeetingCount"]!.GetValue<int>());
        Assert.Equal(HanasuExit.Denied, (await Run(["meetings", "show", "2026-09-01_0900"], meetings: dir)).Exit);
        var text = await Run(["meetings", "list"], meetings: dir);
        Assert.Equal(HanasuExit.Ok, text.Exit);
        Assert.Contains(dir, text.Console.Stderr.ToString());
    }

    // 確かめ方: REQ-MTG-120（ほかの OS でも数え方を確かめる）
    [Fact]
    public void LoadedMeetingsReportResolvesUnreadableAsDenied()
    {
        var loaded = new LoadedMeetings(Array.Empty<Meeting>(), ["2026-09-01 0900"], "/x");
        var context = CommandTestData.Context(new FakeConsole());
        var error = Assert.Throws<CommandException>(() => MeetingsCommand.Resolve("2026-09-01_0900", loaded, context));
        Assert.Equal(HanasuExit.Denied, error.Exit);
        var console = new FakeConsole();
        loaded.WarnIfUnreadable(console);
        Assert.Contains("/x", console.Stderr.ToString());
    }

    // 確かめ方: REQ-COM-183（どのコマンドも会議を書き換えない）
    [Fact]
    public async Task CommandsDoNotWriteMeetings()
    {
        var dir = Path.Combine(CommandTestData.Directory, "meetings");
        var before = Directory.GetFiles(dir, "*", SearchOption.AllDirectories).ToDictionary(f => f, File.ReadAllBytes);
        var ai = new FakeAi("x");
        foreach (var args in new[] { new[] { "meetings", "list" }, ["meetings", "show", "latest", "--all"], ["meetings", "search", "予算"], ["actions"], ["ask", "予算"] })
        {
            await Run(args, ai);
        }
        var after = Directory.GetFiles(dir, "*", SearchOption.AllDirectories);
        Assert.Equal(before.Keys.Order(), after.Order());
        foreach (var file in after) Assert.Equal(before[file], File.ReadAllBytes(file));
    }

    // 確かめ方: REQ-DIC-160（DEC-DIC-190。--app の exe の名前は大文字小文字を区別しない。一覧になければ名前だけ）
    [Fact]
    public void AppStylesByExeName()
    {
        Assert.Equal(AppStylePreset.Chat, SharedText.StyleForApp("Slack.EXE").Preset);
        Assert.Equal("Slack", SharedText.StyleForApp("slack").Name);
        Assert.Equal(AppStylePreset.Email, SharedText.StyleForApp("olk.exe").Preset);
        var unknown = SharedText.StyleForApp(@"C:\Tools\MyEditor.exe");
        Assert.Equal(AppStylePreset.None, unknown.Preset);
        Assert.Equal("MyEditor", unknown.Name);
        Assert.False(unknown.HasRules);
    }

    // 確かめ方: REQ-COM-190, REQ-COM-193（登録の文は PowerShell・cmd でそのまま動き、JSON は正しい）
    [Fact]
    public void RegistrationText()
    {
        const string exe = @"C:\Users\Taro Yamada\AppData\Local\Hanasu\cli\hanasu.exe";
        Assert.Equal($"claude mcp add hanasu \"{exe}\" mcp", CommandInstall.ClaudeCodeCommand(exe));
        var json = JsonNode.Parse(CommandInstall.ClaudeDesktopJson(exe))!;
        Assert.Equal(exe, json["mcpServers"]!["hanasu"]!["command"]!.GetValue<string>());
        Assert.Equal("'/c/Users/Taro Yamada/AppData/Local/Hanasu/cli/hanasu.exe'", CommandInstall.PosixPath(exe));
        var guide = CommandHelp.AgentGuide(exe);
        Assert.Contains($"& \"{exe}\" meetings list", guide);
        Assert.Contains("this PC", guide);
        Assert.Contains("[Console]::OutputEncoding", guide);
    }

    // 確かめ方: REQ-COM-189（新旧の版の手順・エラーの番号）
    [Fact]
    public async Task McpProtocol()
    {
        var console = new FakeConsole();
        var context = CommandTestData.Context(console);
        var server = new McpServer(new McpTools(Path.Combine(CommandTestData.Directory, "meetings"), null, null, context), context);
        async Task<JsonObject?> Send(string json) => await server.HandleAsync(JsonNode.Parse(json), CancellationToken.None);

        var init = await Send("""{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}""");
        Assert.Equal("2025-06-18", init!["result"]!["protocolVersion"]!.GetValue<string>());
        Assert.Contains("this PC", init["result"]!["instructions"]!.GetValue<string>());
        var unknownVersion = await Send("""{"jsonrpc":"2.0","id":2,"method":"initialize","params":{"protocolVersion":"1999-01-01"}}""");
        Assert.Equal(McpServer.LegacyVersions[0], unknownVersion!["result"]!["protocolVersion"]!.GetValue<string>());
        var discover = await Send("""{"jsonrpc":"2.0","id":3,"method":"server/discover","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28"}}}""");
        Assert.Equal("complete", discover!["result"]!["resultType"]!.GetValue<string>());
        var badVersion = await Send("""{"jsonrpc":"2.0","id":4,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2030-01-01"}}}""");
        Assert.Equal(-32022, badVersion!["error"]!["code"]!.GetValue<int>());
        Assert.Equal(-32601, (await Send("""{"jsonrpc":"2.0","id":5,"method":"nope"}"""))!["error"]!["code"]!.GetValue<int>());
        Assert.Equal(-32602, (await Send("""{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"nope"}}"""))!["error"]!["code"]!.GetValue<int>());
        Assert.Equal(-32602, (await Send("""{"jsonrpc":"2.0","id":7,"method":"tools/call","params":[]}"""))!["error"]!["code"]!.GetValue<int>());
        Assert.Null(await Send("""{"jsonrpc":"2.0","method":"notifications/initialized"}"""));
        var tools = (await Send("""{"jsonrpc":"2.0","id":8,"method":"tools/list"}"""))!["result"]!["tools"]!.AsArray();
        Assert.Equal(McpTools.Names, tools.Select(t => t!["name"]!.GetValue<string>()));
        var unknownArgument = await Send("""{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"list_meetings","arguments":{"bogus":1}}}""");
        Assert.True(unknownArgument!["result"]!["isError"]!.GetValue<bool>());

        // 読めない行・まとめたリクエスト（stdout の各行は JSON-RPC）
        var lines = new FakeConsole(protocolInput: ["{", """[{"jsonrpc":"2.0","id":10,"method":"ping"},{"jsonrpc":"2.0","id":11,"method":"ping"}]""", ""]);
        var lineContext = CommandTestData.Context(lines);
        await new McpServer(new McpTools(Path.Combine(CommandTestData.Directory, "meetings"), null, null, lineContext), lineContext).ServeAsync();
        Assert.Equal(2, lines.ProtocolOutput.Count);
        Assert.Equal(-32700, JsonNode.Parse(lines.ProtocolOutput[0])!["error"]!["code"]!.GetValue<int>());
        Assert.Equal(2, JsonNode.Parse(lines.ProtocolOutput[1])!.AsArray().Count);
        Assert.Empty(lines.Stdout.ToString());
    }

    // 確かめ方: REQ-MTG-123（DEC-COM-192。抜粋は書記素で数える）
    [Fact]
    public void SnippetCountsGraphemes()
    {
        var text = new string('あ', 40) + "👨‍👩‍👧予算" + new string('い', 40);
        var snippet = MeetingSearch.Snippet(text, MeetingSearch.Terms("予算"), radius: 2);
        Assert.Equal("…あ👨‍👩‍👧予算いい…", snippet);
        Assert.Equal("abc", MeetingSearch.Fold("ＡＢＣ"));
        Assert.Equal("ガイド", MeetingSearch.Fold("ｶﾞｲﾄﾞ"));
    }

    // 確かめ方: REQ-MTG-126（DEC-MTG-154。検索語は文字の種類の切れ目で分ける）
    [Fact]
    public void KeywordsSplitByCharacterKind()
    {
        Assert.Equal(["料金プラン", "料金", "プラン"], MeetingAsk.Keywords("料金プランはどうなった"));
        Assert.Equal(["予算"], MeetingAsk.Keywords("先週の会議で予算は何？"));
        Assert.Equal(["budget"], MeetingAsk.Keywords("Budget の件"));
    }
}
