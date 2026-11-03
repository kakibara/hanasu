using System.Text;
using System.Text.Json.Nodes;
using Hanasu.Core.Settings;

namespace Hanasu.Core.Tests;

/// <summary>API キーの保存（secrets.json・DPAPI・Windows Hello・PR #19 の形からの移行）。DPAPI と Windows Hello は偽物</summary>
public class SecretStoreTests
{
    private const string ClaudeKey = "sk-ant-api03-test-key-not-real-WXYZ";
    private const string GeminiKey = "AIza-test-key-not-real-0123456789";

    // 確かめ方: REQ-COM-021
    [Fact]
    public async Task StoresEncryptedAndShowsOnlyTheTail()
    {
        var store = TestKeys.Secrets();
        Assert.False(store.Has(SecretKind.ClaudeApiKey));
        Assert.Equal("未設定", store.Describe(SecretKind.ClaudeApiKey).Describe());

        await store.SetAsync(SecretKind.ClaudeApiKey, $"  {ClaudeKey}\n");
        var file = File.ReadAllText(store.Path);
        Assert.DoesNotContain(ClaudeKey, file);
        Assert.DoesNotContain("not-real", file);
        Assert.Equal(ClaudeKey, await store.GetAsync(SecretKind.ClaudeApiKey));
        var info = store.Describe(SecretKind.ClaudeApiKey);
        Assert.Equal("WXYZ", info.Hint);
        Assert.Equal(SecretProtection.Dpapi, info.Protection);
        Assert.Contains("…WXYZ", info.Describe());
        Assert.Null(await store.GetAsync(SecretKind.GeminiApiKey));

        await store.SetAsync(SecretKind.ClaudeApiKey, null);
        Assert.False(store.Has(SecretKind.ClaudeApiKey));
        Assert.Null(await store.GetAsync(SecretKind.ClaudeApiKey));
    }

    [Fact]
    public async Task AnotherUserCannotRead()
    {
        var dir = TestKeys.TempDirectory();
        await TestKeys.Secrets(dir).SetAsync(SecretKind.ClaudeApiKey, ClaudeKey);
        var other = TestKeys.Secrets(dir, user: "mallory");
        Assert.True(other.Has(SecretKind.ClaudeApiKey));
        var e = await Assert.ThrowsAsync<SecretAccessException>(() => other.GetAsync(SecretKind.ClaudeApiKey));
        Assert.Contains("読めません", e.Message);
        // 読めなくても消さない
        Assert.True(TestKeys.Secrets(dir).Has(SecretKind.ClaudeApiKey));
    }

    [Fact]
    public async Task KindsDoNotShareEntropy()
    {
        var dir = TestKeys.TempDirectory();
        var store = TestKeys.Secrets(dir);
        await store.SetAsync(SecretKind.GeminiApiKey, GeminiKey);
        // Gemini の値を Claude の場所に写しても、Claude の値としては読めない
        var json = JsonNode.Parse(File.ReadAllText(store.Path))!;
        json["entries"]!["claudeApiKey"] = json["entries"]!["geminiApiKey"]!.DeepClone();
        File.WriteAllText(store.Path, json.ToJsonString());
        await Assert.ThrowsAsync<SecretAccessException>(() => store.GetAsync(SecretKind.ClaudeApiKey));
    }

    // 確かめ方: REQ-COM-021
    [Fact]
    public async Task LegacyGeminiKeyIsMovedWithoutLosingIt()
    {
        var dir = TestKeys.TempDirectory();
        var settingsPath = Path.Combine(dir, "settings.json");
        // PR #19 までの形: settings.json の protectedApiKey に、DPAPI（エントロピーは Hanasu.Windows.GeminiApiKey）の Base64
        var dpapi = new FakeDpapi();
        var legacy = Convert.ToBase64String(dpapi.Protect(Encoding.UTF8.GetBytes(GeminiKey), SecretStore.LegacyEntropy));
        File.WriteAllText(settingsPath, $$"""{"protectedApiKey": "{{legacy}}", "model": "gemini-3.8-flash"}""");

        var secrets = TestKeys.Secrets(dir);
        var service = new SettingsService(new SettingsStore(settingsPath), secrets);
        Assert.Equal("", service.Current.ProtectedApiKey);
        Assert.DoesNotContain(legacy, File.ReadAllText(settingsPath));
        Assert.Equal("gemini-3.8-flash", service.Current.Model);
        Assert.Equal(GeminiKey, await secrets.GetAsync(SecretKind.GeminiApiKey));
        Assert.Equal(SecretProtection.DpapiLegacy, secrets.Describe(SecretKind.GeminiApiKey).Protection);
        Assert.Equal("6789", secrets.Describe(SecretKind.GeminiApiKey).Hint);
        Assert.NotNull(Gemini.GeminiAuthResolver.Resolve(service.Current, secrets));
    }

    [Fact]
    public async Task UnreadableLegacyKeyIsStillMovedVerbatim()
    {
        var dir = TestKeys.TempDirectory();
        var settingsPath = Path.Combine(dir, "settings.json");
        // 別のユーザーで暗号化した値（このユーザーでは読めない）
        var legacy = Convert.ToBase64String(new FakeDpapi("bob").Protect(Encoding.UTF8.GetBytes(GeminiKey), SecretStore.LegacyEntropy));
        File.WriteAllText(settingsPath, $$"""{"protectedApiKey": "{{legacy}}"}""");
        var secrets = TestKeys.Secrets(dir);
        _ = new SettingsService(new SettingsStore(settingsPath), secrets);
        Assert.True(secrets.Has(SecretKind.GeminiApiKey));
        Assert.Null(secrets.Describe(SecretKind.GeminiApiKey).Hint);
        await Assert.ThrowsAsync<SecretAccessException>(() => secrets.GetAsync(SecretKind.GeminiApiKey));
        // bob なら読める（値はそのまま残っている）
        var asBob = TestKeys.Secrets(dir, user: "bob");
        Assert.Equal(GeminiKey, await asBob.GetAsync(SecretKind.GeminiApiKey));
    }

    [Fact]
    public async Task ExistingNewKeyWinsOverLegacy()
    {
        var dir = TestKeys.TempDirectory();
        var secrets = TestKeys.Secrets(dir);
        await secrets.SetAsync(SecretKind.GeminiApiKey, GeminiKey);
        Assert.True(secrets.MigrateLegacy("bm90LWEta2V5"));
        Assert.Equal(GeminiKey, await secrets.GetAsync(SecretKind.GeminiApiKey));
    }

    // 確かめ方: REQ-COM-021
    [Fact]
    public async Task WindowsHelloProtectionAsksOncePerUnlock()
    {
        var hello = new FakePresenceKey();
        var dir = TestKeys.TempDirectory();
        var store = TestKeys.Secrets(dir, hello);
        await store.SetAsync(SecretKind.ClaudeApiKey, ClaudeKey);
        await store.SetAsync(SecretKind.GeminiApiKey, GeminiKey);

        await store.ChangeProtectionAsync(SecretProtection.WindowsHello);
        // 切り替えのときは、同じ値が出るかを確かめるため 2 回
        Assert.Equal(2, hello.Prompts);
        Assert.Equal(SecretProtection.WindowsHello, store.PreferredProtection);
        Assert.Equal(SecretProtection.WindowsHello, store.Describe(SecretKind.ClaudeApiKey).Protection);
        Assert.Equal("WXYZ", store.Describe(SecretKind.ClaudeApiKey).Hint);

        Assert.Equal(ClaudeKey, await store.GetAsync(SecretKind.ClaudeApiKey));
        Assert.Equal(GeminiKey, await store.GetAsync(SecretKind.GeminiApiKey));
        Assert.Equal(2, hello.Prompts);

        // 画面のロックで鍵を忘れ、次に使うときにまた確認する
        store.Lock();
        Assert.Equal(ClaudeKey, await store.GetAsync(SecretKind.ClaudeApiKey));
        Assert.Equal(3, hello.Prompts);

        // 起動し直しても（新しいインスタンス）、同じ鍵で読める
        var again = TestKeys.Secrets(dir, hello);
        Assert.Equal(ClaudeKey, await again.GetAsync(SecretKind.ClaudeApiKey));

        // DPAPI に戻すと、確認なしで読める
        await again.ChangeProtectionAsync(SecretProtection.Dpapi);
        var prompts = hello.Prompts;
        Assert.Equal(ClaudeKey, await TestKeys.Secrets(dir, hello).GetAsync(SecretKind.ClaudeApiKey));
        Assert.Equal(prompts, hello.Prompts);
    }

    [Fact]
    public async Task HelloIsNotUsedWhenItCannotReproduceTheKey()
    {
        var hello = new FakePresenceKey { Deterministic = false };
        var store = TestKeys.Secrets(presence: hello);
        await store.SetAsync(SecretKind.ClaudeApiKey, ClaudeKey);
        await Assert.ThrowsAsync<SecretAccessException>(() => store.ChangeProtectionAsync(SecretProtection.WindowsHello));
        Assert.Equal(SecretProtection.Dpapi, store.PreferredProtection);
        Assert.Equal(SecretProtection.Dpapi, store.Describe(SecretKind.ClaudeApiKey).Protection);
        Assert.Equal(ClaudeKey, await store.GetAsync(SecretKind.ClaudeApiKey));
    }

    [Fact]
    public async Task RefusedHelloKeepsTheValue()
    {
        var hello = new FakePresenceKey();
        var dir = TestKeys.TempDirectory();
        var store = TestKeys.Secrets(dir, hello);
        await store.SetAsync(SecretKind.ClaudeApiKey, ClaudeKey);
        await store.ChangeProtectionAsync(SecretProtection.WindowsHello);
        store.Lock();
        hello.Refuse = true;
        await Assert.ThrowsAsync<SecretAccessException>(() => store.GetAsync(SecretKind.ClaudeApiKey));
        Assert.True(store.Has(SecretKind.ClaudeApiKey));
        hello.Refuse = false;
        Assert.Equal(ClaudeKey, await store.GetAsync(SecretKind.ClaudeApiKey));

        // Windows Hello のない PC（別の PC に secrets.json を写した など）では読めない
        var noHello = TestKeys.Secrets(dir);
        await Assert.ThrowsAsync<SecretAccessException>(() => noHello.GetAsync(SecretKind.ClaudeApiKey));
    }

    [Fact]
    public async Task ClientsReadTheKeyOnlyWhenSending()
    {
        var store = TestKeys.Secrets();
        await store.SetAsync(SecretKind.ClaudeApiKey, ClaudeKey);
        var client = Ai.TextAiFactory.CreateClaude(store, TimeSpan.FromSeconds(1))!;
        // 作ったあとにキーを変えると、次の送信は新しいキーで行う（キーを持ち続けない）
        await store.SetAsync(SecretKind.ClaudeApiKey, null);
        var e = await Assert.ThrowsAsync<Claude.ClaudeException>(() => client.GenerateTextAsync(Ai.TextPurpose.Refine, "s", "u", "claude-haiku-5-5"));
        Assert.Equal(Claude.ClaudeErrorKind.MissingCredentials, e.Kind);
    }
}
