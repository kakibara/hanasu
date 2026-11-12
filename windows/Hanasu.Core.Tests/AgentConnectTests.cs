using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Nodes;
using Hanasu.Core.Command;
using static Hanasu.Core.Command.AgentConnect;

namespace Hanasu.Core.Tests;

// 「AI アプリにつなぐ」のテスト。共有のテストデータ common/testdata/connect/cases.json（Mac の --test-hanasu-command と同じもの）と、
// ファイルの書き方（写し・権限・シンボリックリンク・読み直し）・行の集め方・claude の呼び方（Mac の AgentConnectSelfTest.swift と同じ筋書き）を確かめる。
// 確かめ方: REQ-COM-194
// 設計判断: DEC-COM-200, DEC-COM-201, DEC-COM-202, DEC-COM-203, DEC-COM-204, DEC-COM-205
public class AgentConnectTests : IDisposable
{
    private readonly string root = Path.Combine(Path.GetTempPath(), "hanasu-connect-" + Guid.NewGuid().ToString("N"));

    public AgentConnectTests() => Directory.CreateDirectory(root);

    public void Dispose()
    {
        try
        {
            Directory.Delete(root, recursive: true);
        }
        catch (IOException)
        {
        }
    }

    // ---- 共有のテストデータ ----

    private static JsonArray Cases()
    {
        for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir is not null; dir = dir.Parent)
        {
            var file = Path.Combine(dir.FullName, "common", "testdata", "connect", "cases.json");
            if (File.Exists(file)) return JsonNode.Parse(File.ReadAllText(file))!["cases"]!.AsArray();
        }
        throw new DirectoryNotFoundException("common/testdata/connect");
    }

    public static IEnumerable<object[]> CaseNames() => Cases().Select((c, i) => new object[] { i, c!["name"]!.GetValue<string>() });

    [Theory]
    [MemberData(nameof(CaseNames))]
    public void SharedCase(int index, string name)
    {
        var item = Cases()[index]!.AsObject();
        Assert.Equal(name, item["name"]!.GetValue<string>());
        var expect = item["expect"]!.AsObject();
        var windows = item["windows"]?.GetValue<bool>() ?? false;
        var executable = item["executable"]?.GetValue<string>() ?? "";
        switch (item["kind"]!.GetValue<string>())
        {
            case "owner":
                Assert.Equal(expect["owner"]!.GetValue<string>(), OwnerOf(item["command"]!.GetValue<string>(), executable, windows).Code());
                return;
            case "dataDir":
                var arguments = item["arguments"]!.AsArray().Select(a => a!.GetValue<string>()).ToList();
                Assert.Equal(expect["dataDir"]?.GetValue<string>(), UserDataDirectory(arguments));
                return;
            case "json" or "toml":
                break;
            default:
                Assert.Fail("知らない kind");
                return;
        }
        var isJson = item["kind"]!.GetValue<string>() == "json";
        var before = item["before"]?.GetValue<string>();
        var state = isJson ? ConfigJson.StateOf(before, executable, windows) : ConfigToml.StateOf(before, executable, windows);
        if (expect["stateBefore"] is { } stateBefore) Assert.Equal(stateBefore.GetValue<string>(), state.Code);
        if (expect["projectEntry"] is { } projectEntry) Assert.Equal(projectEntry.GetValue<bool>(), ConfigJson.HasProjectEntry(before));
        var overwrite = item["overwrite"]?.GetValue<bool>() ?? false;
        Edit edit;
        switch (item["action"]?.GetValue<string>())
        {
            case "connect":
                edit = isJson
                    ? ConfigJson.Connect(before, executable, windows, overwrite)
                    : ConfigToml.Connect(before, executable, windows, overwrite);
                break;
            case "disconnect":
                edit = isJson
                    ? ConfigJson.Disconnect(before, executable, windows)
                    : ConfigToml.Disconnect(before, executable, windows);
                break;
            default:
                return;
        }
        if (expect["result"] is { } result) Assert.Equal(result.GetValue<string>(), edit.Code);
        if (edit.Kind != EditKind.Written) return;
        var after = edit.Text!;
        if (isJson)
        {
            Assert.True(JsonEqual(JsonNode.Parse(after), expect["after"]), $"中身 {after}");
        }
        else
        {
            Assert.Equal(expect["after"]!.GetValue<string>(), after);
        }
        if (expect["stateAfter"] is { } stateAfter)
        {
            var again = isJson ? ConfigJson.StateOf(after, executable, windows) : ConfigToml.StateOf(after, executable, windows);
            Assert.Equal(stateAfter.GetValue<string>(), again.Code);
        }
    }

    /// <summary>JSON を値で比べる（キーの並びは見ない）</summary>
    private static bool JsonEqual(JsonNode? left, JsonNode? right)
    {
        switch (left, right)
        {
            case (null, null):
                return true;
            case (JsonObject l, JsonObject r):
                return l.Count == r.Count && l.All(p => r.TryGetPropertyValue(p.Key, out var value) && JsonEqual(p.Value, value));
            case (JsonArray l, JsonArray r):
                return l.Count == r.Count && l.Zip(r).All(p => JsonEqual(p.First, p.Second));
            case (JsonValue l, JsonValue r):
                var kind = l.GetValueKind();
                if (kind != r.GetValueKind()) return false;
                return kind switch
                {
                    JsonValueKind.String => l.GetValue<string>() == r.GetValue<string>(),
                    JsonValueKind.Number => l.GetValue<decimal>() == r.GetValue<decimal>(),
                    _ => true,
                };
            default:
                return false;
        }
    }

    [Fact]
    public void JsonKeepsOtherKeysInOrderAndRejectsDuplicateKeys()
    {
        const string exe = @"C:\Hanasu\cli\hanasu.exe";
        var edit = ConfigJson.Connect("{\"preferences\": {\"a\": 1}, \"mcpServers\": {\"x\": {\"command\": \"npx\"}}, \"z\": true}", exe, true, false);
        var text = edit.Text!;
        Assert.True(text.IndexOf("\"preferences\"", StringComparison.Ordinal) < text.IndexOf("\"mcpServers\"", StringComparison.Ordinal));
        Assert.True(text.IndexOf("\"x\"", StringComparison.Ordinal) < text.IndexOf("\"hanasu\"", StringComparison.Ordinal));
        Assert.Contains(@"C:\\Hanasu\\cli\\hanasu.exe", text);
        Assert.EndsWith("\n", text);
        // 同じキーが 2 つある JSON は、どちらの値で書くか決められないので読めないとする
        Assert.Equal("unreadable:invalidJSON", ConfigJson.StateOf("{\"a\": 1, \"a\": 2}", exe, true).Code);
        Assert.Equal("unreadable:unexpectedShape", ConfigJson.StateOf("null", exe, true).Code);
    }

    [Fact]
    public void TomlQuoteAndParseRoundTrip()
    {
        foreach (var text in new[] { @"C:\Program Files\Hanasu\cli\hanasu.exe", "a\"b\\c", "tab\there", "\u0001\u007f", "日本語 😀" })
        {
            Assert.Equal(text, ConfigToml.ParseString(ConfigToml.Quote(text)));
        }
        Assert.Equal("x", ConfigToml.ParseString("'x' # comment"));
        Assert.Null(ConfigToml.ParseString("\"x\" y"));
        Assert.Equal("é", ConfigToml.ParseString("\"\\u00E9\""));
        Assert.Null(ConfigToml.ParseString("\"\\uD800\""));
    }

    // ---- Windows のコマンドライン ----

    [Fact]
    public void SplitCommandLine()
    {
        Assert.Equal(["C:\\Program Files\\Claude\\Claude.exe", "--user-data-dir=C:\\Users\\me\\AppData\\Roaming\\Claude-Work"],
            WindowsCommandLine.Split("\"C:\\Program Files\\Claude\\Claude.exe\" --user-data-dir=\"C:\\Users\\me\\AppData\\Roaming\\Claude-Work\""));
        Assert.Equal(["Claude.exe", "--user-data-dir", "C:\\a b\\"], WindowsCommandLine.Split("Claude.exe --user-data-dir \"C:\\a b\\\\\""));
        Assert.Equal(["x", "a\"b", "c\\\\d"], WindowsCommandLine.Split("x a\\\"b c\\\\d"));
        Assert.Equal(["x", "say \"hi\""], WindowsCommandLine.Split("x \"say \"\"hi\"\"\""));
        Assert.Empty(WindowsCommandLine.Split("   "));
        var arguments = WindowsCommandLine.Split("C:\\Users\\me\\AppData\\Local\\AnthropicClaude\\app-1.0\\claude.exe --user-data-dir=\"D:\\Claude-X\"");
        Assert.Equal("D:\\Claude-X", UserDataDirectory(arguments));
        Assert.True(IsClaudeDesktopExecutable(arguments[0]));
        Assert.False(IsElectronChild(arguments));
        Assert.True(IsElectronChild(WindowsCommandLine.Split("Claude.exe --type=renderer --user-data-dir=x")));
        Assert.True(IsClaudeDesktopExecutable(@"C:\Program Files\WindowsApps\Claude_1.0.0.0_x64__abc\app\Claude.exe"));
        Assert.False(IsClaudeDesktopExecutable(@"C:\Users\me\.local\bin\claude.exe"));
        Assert.True(IsChatGPTExecutable(@"C:\Program Files\WindowsApps\OpenAI.ChatGPT-Desktop_1.0_x64__abc\app\ChatGPT.exe"));
        Assert.False(IsChatGPTExecutable(@"C:\Users\me\AppData\Roaming\npm\codex.cmd"));
    }

    [Fact]
    public void CmdArgumentsEscapeTwice()
    {
        Assert.Equal("/d /s /c \"\"C:\\Users\\me\\AppData\\Roaming\\npm\\claude.cmd\" ^^^\"mcp^^^\" ^^^\"remove^^^\"\"",
            WindowsCommandLine.CmdArguments(@"C:\Users\me\AppData\Roaming\npm\claude.cmd", ["mcp", "remove"]));
        // node が読む形: {"a":"b & c"} → "{\"a\":\"b & c\"}"（cmd の特別な文字は ^^^ で）
        var json = WindowsCommandLine.CmdArguments(@"C:\npm\claude.cmd", ["{\"a\":\"b & c\"}"])!;
        Assert.EndsWith("^^^\"{\\^^^\"a\\^^^\":\\^^^\"b^^^ ^^^&^^^ c\\^^^\"}^^^\"\"", json);
        // 末尾の \ は 2 つにする（閉じる " を \" と読まれないように）
        Assert.Contains("^^^\"C:\\\\^^^\"", WindowsCommandLine.CmdArguments(@"C:\npm\claude.cmd", ["C:\\"]));
        Assert.Null(WindowsCommandLine.CmdArguments(@"C:\a&b\claude.cmd", ["mcp"]));
        Assert.Null(WindowsCommandLine.CmdArguments(@"C:\npm\claude.cmd", ["a\nb"]));
        Assert.False(ClaudeCli.IsSafeCmdPath(@"C:\100%\claude.cmd"));
        Assert.True(ClaudeCli.IsSafeCmdPath(@"C:\Users\Taro Yamada\AppData\Roaming\npm\claude.cmd"));
    }

    // ---- ファイルの書き方 ----

    [Fact]
    public void WriteKeepsBackupAndMode()
    {
        var file = Path.Combine(root, "config.toml");
        File.WriteAllText(file, "a = 1\n");
        if (!OperatingSystem.IsWindows()) File.SetUnixFileMode(file, UnixFileMode.UserRead | UnixFileMode.UserWrite);
        AgentConnect.Write("a = 2\n", file);
        var backup = file + BackupSuffix;
        Assert.Equal("a = 2\n", File.ReadAllText(file));
        Assert.Equal("a = 1\n", File.ReadAllText(backup));
        if (!OperatingSystem.IsWindows())
        {
            Assert.Equal(UnixFileMode.UserRead | UnixFileMode.UserWrite, File.GetUnixFileMode(file));
            Assert.Equal(UnixFileMode.UserRead | UnixFileMode.UserWrite, File.GetUnixFileMode(backup));
        }
        // 前の写しは上書きする
        AgentConnect.Write("a = 3\n", file);
        Assert.Equal("a = 2\n", File.ReadAllText(backup));
        // 一時ファイルは残さない
        Assert.Equal(["config.toml", "config.toml" + BackupSuffix], Directory.GetFiles(root).Select(Path.GetFileName).Order(StringComparer.Ordinal));
    }

    [Fact]
    public void WriteCreatesPrivateFile()
    {
        var file = Path.Combine(root, "new", "claude_desktop_config.json");
        AgentConnect.Write("{}\n", file);
        Assert.Equal("{}\n", File.ReadAllText(file));
        Assert.False(File.Exists(file + BackupSuffix));
        if (!OperatingSystem.IsWindows()) Assert.Equal(UnixFileMode.UserRead | UnixFileMode.UserWrite, File.GetUnixFileMode(file));
    }

    [Fact]
    public void WriteFollowsSymbolicLink()
    {
        var real = Path.Combine(root, "dotfiles", "real.toml");
        Directory.CreateDirectory(Path.GetDirectoryName(real)!);
        File.WriteAllText(real, "b = 1\n");
        var link = Path.Combine(root, "link.toml");
        try
        {
            File.CreateSymbolicLink(link, real);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            // シンボリックリンクを作る権限がない Windows では確かめられない
            return;
        }
        AgentConnect.Write("b = 2\n", link);
        Assert.NotNull(new FileInfo(link).LinkTarget);
        Assert.Equal("b = 2\n", File.ReadAllText(real));
        Assert.True(File.Exists(real + BackupSuffix));
        Assert.Equal("b = 2\n", Read(link).Text);
    }

    [Fact]
    public void WriteRestoresBackupWhenReadBackDiffers()
    {
        var file = Path.Combine(root, "config.toml");
        File.WriteAllText(file, "a = 1\n");
        // 対になっていないサロゲートは UTF-8 で書けない（読み直すと違う）
        Assert.Throws<IOException>(() => AgentConnect.Write("a = \uD800\n", file));
        Assert.Equal("a = 1\n", File.ReadAllText(file));
    }

    [Fact]
    public void ReadReportsInvalidUtf8()
    {
        var file = Path.Combine(root, "bad.json");
        File.WriteAllBytes(file, [0x7B, 0xFF, 0x7D]);
        Assert.Equal(ProblemKind.Io, Read(file).Problem?.Kind);
        var missing = Read(Path.Combine(root, "missing.json"));
        Assert.Null(missing.Text);
        Assert.Null(missing.Problem);
    }

    // ---- 行を集める ----

    private const string Exe = @"C:\Program Files\Hanasu\cli\hanasu.exe";

    private sealed class FakeEnvironment(string home) : IAgentEnvironment
    {
        public string Home { get; } = home;
        public string AppData { get; } = Path.Combine(home, "AppData", "Roaming");
        public string LocalAppData { get; } = Path.Combine(home, "AppData", "Local");
        public List<IReadOnlyList<string>?> DesktopArguments { get; init; } = [];
        public bool ChatGPTRunning { get; init; }
        public bool ClaudeRunning { get; init; }
        public string? Claude { get; init; }
        public Func<string, IReadOnlyList<string>, AgentProcessOutput> Run { get; init; } = (_, _) => new AgentProcessOutput(0, "", "");

        public IReadOnlyList<IReadOnlyList<string>?> ClaudeDesktopArguments() => DesktopArguments;
        public bool IsChatGPTRunning() => ChatGPTRunning;
        public bool IsClaudeCodeRunning() => ClaudeRunning;
        public string? FindClaude() => Claude;
        public AgentProcessOutput RunClaude(string claude, IReadOnlyList<string> arguments) => Run(claude, arguments);
    }

    [Fact]
    public void Rows()
    {
        var home = Path.Combine(root, "home");
        var env = new FakeEnvironment(home);
        Directory.CreateDirectory(env.AppData);

        // 何もないとき: Claude Desktop と ChatGPT は見つからない。Claude Code は押せる（DEC-COM-205）
        var rows = AgentConnect.Rows(env, Exe);
        Assert.Equal(3, rows.Count);
        Assert.False(rows[0].Found);
        Assert.False(rows[1].Found);
        Assert.True(rows[2].Found);
        Assert.Null(rows[2].ClaudePath);

        // Claude Desktop の場所ごとの行。deploymentMode のあるものと、設定のない Claude- の場所は出さない（DEC-COM-200・202）
        foreach (var (name, text) in new (string, string?)[] { ("Claude", "{\"preferences\": {}}"), ("Claude-Personal", "{}"), ("Claude-3p", "{\"deploymentMode\": \"1p\"}"), ("Claude-Empty", null) })
        {
            var dir = Path.Combine(env.AppData, name);
            Directory.CreateDirectory(dir);
            if (text is not null) File.WriteAllText(Path.Combine(dir, "claude_desktop_config.json"), text);
        }
        var personal = Path.Combine(env.AppData, "Claude-Personal");
        rows = AgentConnect.Rows(new FakeEnvironment(home) { DesktopArguments = [[@"C:\Users\me\AppData\Local\AnthropicClaude\app-1.0\claude.exe"]] }, Exe);
        var desktop = rows.Where(r => r.Target.Kind == TargetKind.ClaudeDesktop).ToList();
        Assert.Equal(["Claude", "Claude-Personal"], desktop.Select(r => Path.GetFileName(r.Target.Directory!)));
        Assert.Equal([true, false], desktop.Select(r => r.Running));
        Assert.True(desktop[0].IsDefaultClaude);
        Assert.False(desktop[1].IsDefaultClaude);
        rows = AgentConnect.Rows(new FakeEnvironment(home) { DesktopArguments = [["Claude.exe", "--user-data-dir=" + personal + Path.DirectorySeparatorChar]] }, Exe);
        Assert.Equal([false, true], rows.Take(2).Select(r => r.Running));
        rows = AgentConnect.Rows(new FakeEnvironment(home) { DesktopArguments = [null] }, Exe);
        Assert.True(rows.Take(2).All(r => r.Running));

        // つなぐ・外す（動いていれば書かない）
        var row = rows[0];
        Assert.Equal(Outcome.Running, Connect(row, new FakeEnvironment(home) { DesktopArguments = [null] }, Exe, false));
        Assert.Equal(Outcome.Done, Connect(row, env, Exe, false));
        rows = AgentConnect.Rows(env, Exe);
        Assert.Equal(State.Connected, rows[0].State);
        Assert.Contains("\"preferences\"", File.ReadAllText(row.File));
        Assert.Equal(Outcome.Unchanged, Connect(rows[0], env, Exe, false));
        Assert.Equal(Outcome.Done, Disconnect(rows[0], env, Exe));
        Assert.Equal(State.NotConnected, AgentConnect.Rows(env, Exe)[0].State);
        Assert.Equal(Outcome.Nothing, Disconnect(rows[0], env, Exe));

        // ChatGPT（Codex）: 動いていれば書かない。%USERPROFILE%\.codex があれば見つかる
        Directory.CreateDirectory(Path.Combine(home, ".codex"));
        var chatGPT = new FakeEnvironment(home) { ChatGPTRunning = true };
        var codex = AgentConnect.Rows(chatGPT, Exe).Single(r => r.Target.Kind == TargetKind.Codex);
        Assert.True(codex.Found);
        Assert.True(codex.Running);
        Assert.Equal(Outcome.Running, Connect(codex, chatGPT, Exe, false));
        Assert.Equal(Outcome.Done, Connect(codex, env, Exe, false));
        Assert.Equal(State.Connected, ConfigToml.StateOf(File.ReadAllText(codex.File), Exe, true));

        // Claude Code（claude がない）: .claude.json に直接書く。claude が動いていれば書かない
        var code = AgentConnect.Rows(env, Exe).Single(r => r.Target.Kind == TargetKind.ClaudeCode);
        Assert.Equal(Outcome.Running, Connect(code, new FakeEnvironment(home) { ClaudeRunning = true }, Exe, false));
        Assert.Equal(Outcome.Done, Connect(code, env, Exe, false));
        Assert.Equal(State.Connected, AgentConnect.Rows(env, Exe).Single(r => r.Target.Kind == TargetKind.ClaudeCode).State);

        // 壊れた設定は書かずに理由を返す
        File.WriteAllText(Path.Combine(env.AppData, "Claude", "claude_desktop_config.json"), "{");
        row = AgentConnect.Rows(env, Exe)[0];
        Assert.Equal("unreadable:invalidJSON", row.State.Code);
        Assert.Equal(Outcome.UnreadableFile(Problem.InvalidJson), Connect(row, env, Exe, false));
        Assert.Equal("{", File.ReadAllText(row.File));

        // Hanasu のものでない hanasu は確かめる
        File.WriteAllText(row.File, "{\"mcpServers\": {\"hanasu\": {\"command\": \"npx\"}}}");
        row = AgentConnect.Rows(env, Exe)[0];
        Assert.Equal(Outcome.NeedsOverwrite("npx"), Connect(row, env, Exe, false));
        Assert.Equal(Outcome.Done, Connect(row, env, Exe, true));
    }

    [Fact]
    public void StoreVersionReplacesDefaultLocation()
    {
        var home = Path.Combine(root, "store");
        var env = new FakeEnvironment(home);
        Directory.CreateDirectory(Path.Combine(env.AppData, "Claude"));
        var store = Path.Combine(env.LocalAppData, "Packages", "Claude_pzs8sxrjxfjjc", "LocalCache", "Roaming", "Claude");
        Directory.CreateDirectory(store);
        Assert.Equal([store], ClaudeDesktopLocations(env.AppData, env.LocalAppData));
        var rows = AgentConnect.Rows(new FakeEnvironment(home) { DesktopArguments = [["Claude.exe"]] }, Exe);
        Assert.Equal(store, rows[0].Target.Directory);
        Assert.True(rows[0].IsDefaultClaude);
        Assert.True(rows[0].Running);
    }

    [Fact]
    public void BundledClaudePicksNewestVersion()
    {
        var dir = Path.Combine(root, "claude-code");
        foreach (var version in new[] { "1.2.9", "1.2.10", "latest" })
        {
            var exe = Path.Combine(dir, version, "abc", "claude.exe");
            Directory.CreateDirectory(Path.GetDirectoryName(exe)!);
            File.WriteAllText(exe, "");
        }
        Assert.Equal(Path.Combine(dir, "1.2.10", "abc", "claude.exe"), ClaudeCli.Bundled(dir));
        Assert.Null(ClaudeCli.Bundled(Path.Combine(root, "missing")));
    }

    // ---- claude の呼び方 ----

    /// <summary>本物の claude と同じく、同じ名前があれば add は失敗し、なければ remove は失敗する偽物</summary>
    private sealed class FakeClaude(string file)
    {
        public List<IReadOnlyList<string>> Calls { get; } = [];
        public bool FailAdd { get; set; }
        public bool Hang { get; set; }

        public AgentProcessOutput Run(string claude, IReadOnlyList<string> arguments)
        {
            Calls.Add(arguments);
            if (Hang) return new AgentProcessOutput(-1, "", "", TimedOut: true);
            var rootNode = File.Exists(file) ? JsonNode.Parse(File.ReadAllText(file))!.AsObject() : new JsonObject();
            if (rootNode["mcpServers"] is not JsonObject servers)
            {
                servers = new JsonObject();
                rootNode["mcpServers"] = servers;
            }
            switch (string.Join(' ', arguments.Take(2)))
            {
                case "mcp add":
                    if (servers.ContainsKey("hanasu")) return new AgentProcessOutput(1, "", "MCP server hanasu already exists in user config");
                    if (FailAdd) return new AgentProcessOutput(1, "", "boom");
                    servers["hanasu"] = new JsonObject { ["command"] = arguments[^2], ["args"] = new JsonArray("mcp") };
                    break;
                case "mcp add-json":
                    servers["hanasu"] = JsonNode.Parse(arguments[^1]);
                    break;
                case "mcp remove":
                    if (!servers.ContainsKey("hanasu")) return new AgentProcessOutput(1, "", "No user-scoped MCP server found with name: hanasu");
                    servers.Remove("hanasu");
                    break;
            }
            File.WriteAllText(file, rootNode.ToJsonString());
            return new AgentProcessOutput(0, "", "");
        }
    }

    [Fact]
    public void ClaudeCommand()
    {
        const string old = @"D:\Old\Hanasu\cli\hanasu.exe";
        var home = Path.Combine(root, "cli");
        Directory.CreateDirectory(home);
        var claudeJson = Path.Combine(home, ".claude.json");
        var fake = new FakeClaude(claudeJson);
        var env = new FakeEnvironment(home) { ClaudeRunning = true, Claude = @"C:\fake\claude.exe", Run = fake.Run };
        Row Row() => AgentConnect.Rows(env, Exe).Single(r => r.Target.Kind == TargetKind.ClaudeCode);

        // つなぐ（claude があれば、Claude Code が動いていても claude に任せる）
        Assert.False(Row().Running);
        Assert.Equal(Outcome.Done, Connect(Row(), env, Exe, false));
        Assert.Equal(["mcp", "add", "--scope", "user", "hanasu", "--", Exe, "mcp"], fake.Calls[^1]);
        Assert.Equal(State.Connected, Row().State);

        // 別の場所の Hanasu: remove してから add
        File.WriteAllText(claudeJson, JsonSerializer.Serialize(new { mcpServers = new { hanasu = new { command = old, args = new[] { "mcp" } } } }));
        fake.Calls.Clear();
        Assert.Equal(State.OtherHanasu(old), Row().State);
        Assert.Equal(Outcome.Done, Connect(Row(), env, Exe, false));
        Assert.Equal(["mcp remove", "mcp add"], fake.Calls.Select(c => string.Join(' ', c.Take(2))));
        Assert.Equal(State.Connected, Row().State);

        // Hanasu のものでない: 確かめる。add が失敗したら前の項目を入れ直す
        File.WriteAllText(claudeJson, "{\"mcpServers\": {\"hanasu\": {\"command\": \"npx\", \"args\": [\"x\"]}}}");
        Assert.Equal(Outcome.NeedsOverwrite("npx"), Connect(Row(), env, Exe, false));
        fake.FailAdd = true;
        Assert.Equal(Outcome.Failed("boom"), Connect(Row(), env, Exe, true));
        Assert.Equal(State.ForeignEntry("npx"), Row().State);
        Assert.Equal("x", JsonNode.Parse(File.ReadAllText(claudeJson))!["mcpServers"]!["hanasu"]!["args"]![0]!.GetValue<string>());
        fake.FailAdd = false;

        // 打ち切り
        fake.Hang = true;
        Assert.Equal(Outcome.TimedOut, Connect(Row(), env, Exe, true));
        fake.Hang = false;

        // 外す
        File.WriteAllText(claudeJson, JsonSerializer.Serialize(new Dictionary<string, object>
        {
            ["mcpServers"] = new { hanasu = new { command = Exe, args = new[] { "mcp" } } },
            ["projects"] = new Dictionary<string, object> { ["C:/x"] = new { mcpServers = new { hanasu = new { } } } },
        }));
        Assert.True(Row().ProjectEntry);
        Assert.Equal(Outcome.Done, Disconnect(Row(), env, Exe));
        Assert.Equal(State.NotConnected, Row().State);
        fake.Calls.Clear();
        Assert.Equal(Outcome.Nothing, Disconnect(Row(), env, Exe));
        Assert.Empty(fake.Calls);
    }

    [Fact]
    public void RunProcessTimesOut()
    {
        var info = OperatingSystem.IsWindows()
            ? new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "cmd.exe"), "/d /c ping -n 6 127.0.0.1 > nul")
            : new ProcessStartInfo("/bin/sleep", "5");
        var watch = Stopwatch.StartNew();
        var output = RunProcess(info, TimeSpan.FromSeconds(0.5));
        Assert.True(output.TimedOut);
        Assert.True(watch.Elapsed < TimeSpan.FromSeconds(4));

        var echo = OperatingSystem.IsWindows()
            ? new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "cmd.exe"), "/d /c echo hi")
            : new ProcessStartInfo("/bin/echo", "hi");
        var done = RunProcess(echo, TimeSpan.FromSeconds(10));
        Assert.False(done.TimedOut);
        Assert.Equal(0, done.Status);
        Assert.Equal("hi", done.Stdout.Trim());
    }
}
