using System.Text;
using System.Text.Json.Nodes;
using Hanasu.Core.Command;
using Hanasu.Core.LocalLlm;
using Hanasu.Core.Settings;
using Hanasu.Core.Update;

namespace Hanasu.Core.Tests;

/// <summary>確認が終わらない Windows Hello（取り消されるまで待つ）</summary>
internal sealed class HangingPresenceKey : IUserPresenceKey
{
    public bool Canceled { get; private set; }
    public Task<bool> IsAvailableAsync() => Task.FromResult(true);

    public async Task<byte[]> DeriveKeyAsync(bool create, CancellationToken cancellationToken)
    {
        try
        {
            await Task.Delay(Timeout.Infinite, cancellationToken);
        }
        catch (OperationCanceledException)
        {
            Canceled = true;
            throw;
        }
        return [];
    }
}

/// <summary>hanasu の Windows だけの部品のうち、Mac でも確かめられるもの（W3・W4・WD4・WD9）</summary>
[Collection(PromptLanguageCollection.Name)]
public class CommandPlatformTests
{
    // 確かめ方: REQ-COM-186（W3。画面のないセッションでは確認を出さず、時間切れは理由を添えて 3）
    [Fact]
    public async Task PresenceGuardRefusesWithoutDesktopAndTimesOut()
    {
        var inner = new FakePresenceKey();
        var noDesktop = new GuardedPresenceKey(inner, () => false, TimeSpan.FromSeconds(60));
        await Assert.ThrowsAsync<SecretAccessException>(() => noDesktop.DeriveKeyAsync(false, CancellationToken.None));
        Assert.Equal(0, inner.Prompts);

        var hanging = new HangingPresenceKey();
        var timed = new GuardedPresenceKey(hanging, () => true, TimeSpan.FromMilliseconds(50));
        var error = await Assert.ThrowsAsync<SecretAccessException>(() => timed.DeriveKeyAsync(false, CancellationToken.None));
        Assert.True(error.IsCredentialProblem);
        await Task.Delay(50);
        Assert.True(hanging.Canceled);

        Assert.Equal(32, (await new GuardedPresenceKey(inner, () => true, TimeSpan.FromSeconds(5)).DeriveKeyAsync(true, CancellationToken.None)).Length);
        Assert.False(GuardedPresenceKey.DesktopAvailable(new Dictionary<string, string> { ["SSH_CONNECTION"] = "1 2 3 4" }));
    }

    // 確かめ方: REQ-COM-186（W3。取り消したら 3。ロックのあとは、また確認を出す。DEC-COM-144）
    [Fact]
    public async Task HelloKeysPromptAgainAfterLock()
    {
        var presence = new FakePresenceKey();
        var secrets = TestKeys.Secrets(presence: new GuardedPresenceKey(presence, () => true, TimeSpan.FromSeconds(5)));
        await secrets.ChangeProtectionAsync(SecretProtection.WindowsHello);
        await secrets.SetAsync(SecretKind.ClaudeApiKey, "sk-ant-api03-test-0000000000000000");
        var prompts = presence.Prompts;
        await secrets.GetAsync(SecretKind.ClaudeApiKey);
        Assert.Equal(prompts, presence.Prompts);
        secrets.Lock();
        await secrets.GetAsync(SecretKind.ClaudeApiKey);
        Assert.Equal(prompts + 1, presence.Prompts);

        presence.Refuse = true;
        secrets.Lock();
        var console = new FakeConsole();
        var context = CommandTestData.Context(console) is var c ? new CommandContext
        {
            Settings = c.Settings,
            Console = console,
            Secrets = secrets,
            Environment = c.Environment,
        } : null!;
        var exit = await HanasuCommand.RunAsync(["refine", "テスト", "--ai", "claude"], context);
        Assert.Equal(HanasuExit.Credentials, exit);
        Assert.Empty(console.Stdout.ToString());
    }

    // 確かめ方: REQ-COM-186（DEC-COM-185・197。doctor は Windows Hello のキーを読まずに、守り方だけを出す）
    [Fact]
    public async Task DoctorDoesNotReadHelloKeys()
    {
        var presence = new FakePresenceKey();
        var secrets = TestKeys.Secrets(presence: presence);
        await secrets.ChangeProtectionAsync(SecretProtection.WindowsHello);
        await secrets.SetAsync(SecretKind.ClaudeApiKey, "sk-ant-api03-test-0000000000000000");
        secrets.Lock();
        var prompts = presence.Prompts;
        var console = new FakeConsole();
        var baseContext = CommandTestData.Context(console);
        var exit = await HanasuCommand.RunAsync(["doctor", "--json"], new CommandContext
        {
            Settings = baseContext.Settings,
            Console = console,
            Secrets = secrets,
            Environment = baseContext.Environment,
            ExecutablePath = baseContext.ExecutablePath,
        });
        Assert.Equal(HanasuExit.Ok, exit);
        Assert.Equal(prompts, presence.Prompts);
        var json = JsonNode.Parse(console.Stdout.ToString())!;
        Assert.Equal("windowsHello", json["credentials"]!["claude"]!["source"]!.GetValue<string>());
        Assert.False(json["credentials"]!["apple"]!["available"]!.GetValue<bool>());
        Assert.Equal("meeting", json["ai"]!["askPurpose"]!.GetValue<string>());
        Assert.Null(json["policies"]);
        Assert.DoesNotContain("sk-ant-api03", console.Stdout.ToString());
    }

    // 確かめ方: REQ-COM-180（WD9。BOM を外し、UTF-8 として正しくなければコンソールのコードページで読み直す）
    [Fact]
    public void InputDecoding()
    {
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
        var shiftJis = Encoding.GetEncoding(932);
        Assert.Equal("日本語", CommandEncoding.DecodeInput([0xEF, 0xBB, 0xBF, .. Encoding.UTF8.GetBytes("日本語")], shiftJis));
        Assert.Equal("日本語", CommandEncoding.DecodeInput(shiftJis.GetBytes("日本語"), shiftJis));
        Assert.Equal("abc\n", Encoding.UTF8.GetString(CommandEncoding.EncodeOutput("abc\n")));
        Assert.False(CommandEncoding.EncodeOutput("あ").AsSpan().StartsWith(new byte[] { 0xEF, 0xBB, 0xBF }));
    }

    // 確かめ方: REQ-COM-191（WD7。足す・外すのは cli の項目だけで、ほかの項目の書き方は変えない）
    [Fact]
    public void PathEntries()
    {
        static string Expand(string s) => s.Replace("%LOCALAPPDATA%", @"C:\Users\a\AppData\Local", StringComparison.OrdinalIgnoreCase);
        const string cli = @"C:\Users\a\AppData\Local\Hanasu\cli";
        const string original = @"%USERPROFILE%\bin;C:\Tools;";
        var added = CommandPath.Add(original, cli, Expand);
        Assert.Equal(original + cli, added);
        Assert.Equal(added, CommandPath.Add(added, cli + @"\", Expand));
        // 外すと、足したときに補った ; は残らない（ほかの項目と並びは変えない）
        Assert.Equal(@"%USERPROFILE%\bin;C:\Tools", CommandPath.Remove(added, cli, Expand));
        Assert.Equal(cli, CommandPath.Add("", cli, Expand));
        Assert.Equal(@"C:\a;C:\b", CommandPath.Remove(@"C:\a;%LOCALAPPDATA%\Hanasu\cli;C:\b", cli, Expand));

        var status = CommandPath.Status(@"C:\Old\Hanasu\cli;C:\Gone\cli;%LOCALAPPDATA%\Hanasu\cli;C:\Tools\cli", cli,
            processPath: @"C:\Windows", recorded: @"C:\Gone\cli", fileExists: p => p == @"C:\Old\Hanasu\Hanasu.exe", Expand);
        Assert.Equal(@"%LOCALAPPDATA%\Hanasu\cli", status.Current);
        Assert.Equal([@"C:\Old\Hanasu\cli", @"C:\Gone\cli"], status.Others);
        Assert.False(status.OnProcessPath);
        Assert.True(CommandPath.IsTemporary(@"C:\Users\a\AppData\Local\Temp\Temp1_Hanasu.zip\Hanasu\Hanasu.exe", @"C:\Users\a\AppData\Local\Temp\"));
        Assert.False(CommandPath.IsTemporary(@"C:\Users\a\AppData\Local\Hanasu\Hanasu.exe", @"C:\Users\a\AppData\Local\Temp\"));
    }

    // 確かめ方: REQ-COM-187（WD4。自分の記録・持ち主が終わった記録は「ほかのプロセスのサーバー」に数えない）
    [Fact]
    public void ServerRecords()
    {
        var dir = TestKeys.TempDirectory();
        var saved = LocalLlmServerRecords.Directory;
        try
        {
            LocalLlmServerRecords.Directory = dir;
            Assert.False(LocalLlmServerRecords.OtherProcessServerRunning());
            LocalLlmServerRecords.Write(Environment.ProcessId, Environment.ProcessPath ?? "");
            Assert.Single(LocalLlmServerRecords.Records());
            Assert.False(LocalLlmServerRecords.OtherProcessServerRunning());
            File.WriteAllText(Path.Combine(dir, "llm-server-999999.json"),
                $$"""{"serverPid":{{Environment.ProcessId}},"executable":"x","owner":999999}""");
            Assert.False(LocalLlmServerRecords.OtherProcessServerRunning());
            LocalLlmServerRecords.Remove();
            Assert.Single(LocalLlmServerRecords.Records());
        }
        finally
        {
            LocalLlmServerRecords.Directory = saved;
        }
    }

    // 確かめ方: REQ-COM-187（ほかのプロセスがローカルの AI を使っていれば、起動せずに 1）
    [Fact]
    public async Task LocalInUseExitsOne()
    {
        var console = new FakeConsole();
        var baseContext = CommandTestData.Context(console);
        var exit = await HanasuCommand.RunAsync(["refine", "テスト", "--ai", "local"], new CommandContext
        {
            Settings = baseContext.Settings,
            Console = console,
            Environment = baseContext.Environment,
            OtherLocalServerRunning = () => true,
        });
        Assert.Equal(HanasuExit.Failure, exit);
        Assert.Contains("--ai", console.Stderr.ToString());
    }

    // 確かめ方: REQ-REL-013（DEC-REL-031。このインストールの hanasu と、パスを読めない hanasu を数える）
    [Fact]
    public void RunningCommandsAreClassified()
    {
        var cli = Path.Combine(TestKeys.TempDirectory(), "cli", "hanasu.exe");
        var count = RunningCommands.Classify([cli, cli.ToUpperInvariant() == cli ? cli : cli, null, Path.Combine(TestKeys.TempDirectory(), "hanasu.exe")], cli);
        Assert.Equal(2, count.Ours);
        Assert.Equal(1, count.Unknown);
        Assert.Equal(3, count.Total);
    }

    // 確かめ方: REQ-REL-013（DEC-REL-031。入れ替えのスクリプトは、名前を変える前に cli の hanasu を探し直して終わらせ、改名できなければ印に理由を足す）
    [Fact]
    public void SwapScriptStopsCommandsBeforeRename()
    {
        var script = UpdateSwapScript.Text;
        var stop = script.IndexOf("Get-Process -Name 'hanasu'", StringComparison.Ordinal);
        var rename = script.IndexOf("[System.IO.Directory]::Move($Install, $Old)", StringComparison.Ordinal);
        Assert.True(stop > 0 && rename > stop);
        Assert.Contains("$Cli", script);
        Assert.Contains("'rename-failed'", script);
        Assert.Contains("[string]$Pending", script);
    }
}
