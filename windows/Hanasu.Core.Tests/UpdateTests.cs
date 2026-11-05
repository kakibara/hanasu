using System.IO.Compression;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using Hanasu.Core.Settings;
using Hanasu.Core.Update;

namespace Hanasu.Core.Tests;

// 確かめ方: REQ-REL-010, REQ-REL-011
public class UpdateTests
{
    private const string Sha = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

    /// <summary>本物の応答（releases/latest）の形に合わせた小さな JSON</summary>
    private static string ReleaseJson(string tag = "v1.5.0", bool draft = false, bool prerelease = false, string? digest = "sha256:" + Sha,
        string? assetName = null, string downloadUrl = "https://github.com/kakibara/hanasu/releases/download/v1.5.0/Hanasu-1.5.0-Windows-x64.zip")
    {
        var digestPart = digest is null ? "" : $"\"digest\": \"{digest}\",";
        return $$"""
        {
          "tag_name": "{{tag}}",
          "html_url": "https://github.com/kakibara/hanasu/releases/tag/{{tag}}",
          "draft": {{(draft ? "true" : "false")}},
          "prerelease": {{(prerelease ? "true" : "false")}},
          "body": "## 変更\n- 例",
          "assets": [
            { "name": "Hanasu-1.5.0-macOS.zip", "browser_download_url": "https://github.com/kakibara/hanasu/releases/download/v1.5.0/Hanasu-1.5.0-macOS.zip", "size": 111, "digest": "sha256:{{Sha}}" },
            { "name": "{{assetName ?? "Hanasu-1.5.0-Windows-x64.zip"}}", "browser_download_url": "{{downloadUrl}}", "size": 222, {{digestPart}} "content_type": "application/zip" }
          ]
        }
        """;
    }

    // MARK: - 版

    [Theory]
    [InlineData("1.6.0", "1.6.0")]
    [InlineData("v1.6.0", "1.6.0")]
    [InlineData("1.6", "1.6.0")]
    [InlineData(" V2.0.1 ", "2.0.1")]
    public void ParsesVersions(string text, string expected) => Assert.Equal(expected, AppVersion.Parse(text)!.ToString());

    [Theory]
    [InlineData("")]
    [InlineData(null)]
    [InlineData("abc")]
    [InlineData("1.x.0")]
    [InlineData("1..0")]
    [InlineData("1.6.0-beta")]
    [InlineData("-1.0.0")]
    [InlineData("1.2.3.4.5")]
    [InlineData("v")]
    public void UnparsableVersionIsNull(string? text) => Assert.Null(AppVersion.Parse(text));

    [Fact]
    public void ComparesNumerically()
    {
        Assert.True(AppVersion.Parse("1.10.0")! > AppVersion.Parse("1.9.0")!);
        Assert.True(AppVersion.Parse("2.0.0")! > AppVersion.Parse("1.99.99")!);
        Assert.True(AppVersion.Parse("1.6.1")! > AppVersion.Parse("v1.6")!);
        Assert.Equal(AppVersion.Parse("1.6"), AppVersion.Parse("v1.6.0"));
        Assert.Equal(AppVersion.Parse("1.6")!.GetHashCode(), AppVersion.Parse("1.6.0")!.GetHashCode());
        Assert.Equal(new AppVersion[] { AppVersion.Parse("1.9.0")!, AppVersion.Parse("1.10.0")! },
            new[] { AppVersion.Parse("1.10.0")!, AppVersion.Parse("1.9.0")! }.OrderBy(v => v));
    }

    [Fact]
    public void AssemblyVersionConverts() => Assert.Equal("1.5.0", AppVersion.FromVersion(new Version(1, 5, 0, 0)).ToString());

    // MARK: - 応答の読み取り

    [Fact]
    public void ParsesLatestRelease()
    {
        var release = ReleaseParser.Parse(ReleaseJson())!;
        Assert.Equal("1.5.0", release.Version.ToString());
        Assert.Equal("v1.5.0", release.Tag);
        Assert.Equal("https://github.com/kakibara/hanasu/releases/tag/v1.5.0", release.ReleaseUrl.ToString());
        Assert.Contains("変更", release.Notes);
        var asset = release.Asset!;
        Assert.Equal("Hanasu-1.5.0-Windows-x64.zip", asset.Name);
        Assert.Equal(222, asset.Size);
        Assert.Equal(Sha.ToUpperInvariant(), asset.Sha256);
    }

    [Fact]
    public void SelectsOnlyTheWindowsZipOfThatVersion()
    {
        // Mac の zip しかない・名前が違う・版が違うときは、zip なし
        Assert.Null(ReleaseParser.Parse(ReleaseJson(assetName: "Hanasu-1.5.0-Windows-arm64.zip"))!.Asset);
        Assert.Null(ReleaseParser.Parse(ReleaseJson(assetName: "Hanasu-1.4.0-Windows-x64.zip"))!.Asset);
        Assert.Equal("Hanasu-1.5.0-Windows-x64.zip", ReleaseParser.AssetNameFor("v1.5.0"));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("md5:abc")]
    [InlineData("sha256:1234")]
    public void MissingOrBadDigestMeansNoInstaller(string? digest)
    {
        var release = ReleaseParser.Parse(ReleaseJson(digest: digest))!;
        Assert.Null(release.Asset);
        var result = UpdateChecker.Evaluate(release, AppVersion.Parse("1.0.0")!);
        Assert.Equal(UpdateCheckKind.AvailableWithoutInstaller, result.Kind);
        Assert.True(result.HasUpdate);
    }

    [Fact]
    public void AssetOutsideGitHubHostsIsNotInstallable()
    {
        Assert.Null(ReleaseParser.Parse(ReleaseJson(downloadUrl: "https://evil.example.com/Hanasu-1.5.0-Windows-x64.zip"))!.Asset);
        Assert.Null(ReleaseParser.Parse(ReleaseJson(downloadUrl: "http://github.com/kakibara/hanasu/releases/download/v1.5.0/Hanasu-1.5.0-Windows-x64.zip"))!.Asset);
    }

    [Fact]
    public void DraftAndPrereleaseAreIgnored()
    {
        Assert.Null(ReleaseParser.Parse(ReleaseJson(draft: true)));
        Assert.Null(ReleaseParser.Parse(ReleaseJson(prerelease: true)));
        Assert.Equal(UpdateCheckKind.UpToDate, UpdateChecker.Evaluate(null, AppVersion.Parse("1.0.0")!).Kind);
    }

    [Fact]
    public void BadTagOrJson()
    {
        Assert.Null(ReleaseParser.Parse(ReleaseJson(tag: "nightly")));
        Assert.Throws<UpdateException>(() => ReleaseParser.Parse("{ not json"));
    }

    [Fact]
    public void EvaluateComparesWithCurrent()
    {
        var release = ReleaseParser.Parse(ReleaseJson())!;
        Assert.Equal(UpdateCheckKind.Available, UpdateChecker.Evaluate(release, AppVersion.Parse("1.4.9")!).Kind);
        Assert.Equal(UpdateCheckKind.UpToDate, UpdateChecker.Evaluate(release, AppVersion.Parse("1.5.0")!).Kind);
        Assert.Equal(UpdateCheckKind.UpToDate, UpdateChecker.Evaluate(release, AppVersion.Parse("1.6.0")!).Kind);
    }

    // MARK: - 知らせるかの判断

    [Fact]
    public void LaunchCheckHidesSkippedVersionButManualDoesNot()
    {
        var release = ReleaseParser.Parse(ReleaseJson())!;
        var result = UpdateChecker.Evaluate(release, AppVersion.Parse("1.4.0")!);
        Assert.True(UpdateChecker.ShouldPrompt(result, "", manual: false));
        Assert.False(UpdateChecker.ShouldPrompt(result, "1.5.0", manual: false));
        Assert.False(UpdateChecker.ShouldPrompt(result, "v1.5", manual: false));
        // スキップしたのが古い版なら、もっと新しい版は知らせる
        Assert.True(UpdateChecker.ShouldPrompt(result, "1.4.5", manual: false));
        Assert.True(UpdateChecker.ShouldPrompt(result, "1.5.0", manual: true));
        Assert.True(UpdateChecker.ShouldPrompt(result, "壊れた値", manual: false));
        var upToDate = UpdateChecker.Evaluate(release, AppVersion.Parse("1.5.0")!);
        Assert.False(UpdateChecker.ShouldPrompt(upToDate, "", manual: true));
    }

    [Fact]
    public void SettingsDefaults()
    {
        var s = new AppSettings();
        Assert.True(s.CheckForUpdatesOnLaunch);
        Assert.Equal("", s.SkippedUpdateVersion);
        s.SkippedUpdateVersion = "1.5.0";
        s.CheckForUpdatesOnLaunch = false;
        var clone = s.Clone();
        Assert.Equal("1.5.0", clone.SkippedUpdateVersion);
        Assert.False(clone.CheckForUpdatesOnLaunch);
    }

    // MARK: - ホスト

    [Theory]
    [InlineData("https://github.com/kakibara/hanasu/releases/download/v1/a.zip", true)]
    [InlineData("https://api.github.com/repos/kakibara/hanasu/releases/latest", true)]
    [InlineData("https://objects.githubusercontent.com/x", true)]
    [InlineData("https://release-assets.githubusercontent.com/x", true)]
    [InlineData("https://foo.githubusercontent.com/x", true)]
    [InlineData("https://GitHub.com/x", true)]
    [InlineData("http://github.com/x", false)]
    [InlineData("https://githubusercontent.com.evil.example/x", false)]
    [InlineData("https://evilgithubusercontent.com/x", false)]
    [InlineData("https://github.com.evil.example/x", false)]
    [InlineData("https://user:pw@github.com/x", false)]
    [InlineData("https://example.com/x", false)]
    public void HostAllowList(string url, bool allowed) => Assert.Equal(allowed, UpdateHosts.IsAllowed(new Uri(url)));

    [Fact]
    public void ApiUrlIsFixed() => Assert.Equal("https://api.github.com/repos/kakibara/hanasu/releases/latest", UpdateHosts.LatestReleaseApi.ToString());

    // MARK: - ダウンロード

    private sealed class StubHandler(Func<HttpRequestMessage, HttpResponseMessage> respond) : HttpMessageHandler
    {
        public int Calls;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Calls++;
            var response = respond(request);
            response.RequestMessage ??= request;
            return Task.FromResult(response);
        }
    }

    private static UpdateAsset AssetFor(byte[] data, string url = "https://github.com/kakibara/hanasu/releases/download/v1.5.0/Hanasu-1.5.0-Windows-x64.zip") =>
        new("Hanasu-1.5.0-Windows-x64.zip", new Uri(url), data.Length, Convert.ToHexString(SHA256.HashData(data)));

    [Fact]
    public async Task DownloadsAndVerifies()
    {
        var data = Encoding.UTF8.GetBytes("zip body");
        using var http = new HttpClient(new StubHandler(_ => new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(data) }));
        var path = Path.Combine(TestKeys.TempDirectory(), "update.zip");
        await UpdateChecker.DownloadAsync(http, AssetFor(data), path, null, CancellationToken.None);
        Assert.Equal(data, await File.ReadAllBytesAsync(path));
        Assert.False(File.Exists(path + ".download"));
    }

    [Fact]
    public async Task HashMismatchOrTooLargeIsRejectedAndCleanedUp()
    {
        var data = Encoding.UTF8.GetBytes("zip body");
        var path = Path.Combine(TestKeys.TempDirectory(), "update.zip");
        using var tampered = new HttpClient(new StubHandler(_ => new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(Encoding.UTF8.GetBytes("zip BODY")) }));
        await Assert.ThrowsAsync<ModelVerificationException>(() => UpdateChecker.DownloadAsync(tampered, AssetFor(data), path, null, CancellationToken.None));
        using var larger = new HttpClient(new StubHandler(_ => new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(Encoding.UTF8.GetBytes("zip body plus")) }));
        await Assert.ThrowsAsync<ModelVerificationException>(() => UpdateChecker.DownloadAsync(larger, AssetFor(data), path, null, CancellationToken.None));
        Assert.False(File.Exists(path));
        Assert.False(File.Exists(path + ".download"));
    }

    [Fact]
    public async Task RejectsDisallowedStartHostWithoutRequest()
    {
        var data = new byte[] { 1, 2, 3 };
        var handler = new StubHandler(_ => new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(data) });
        using var http = new HttpClient(handler);
        var path = Path.Combine(TestKeys.TempDirectory(), "update.zip");
        await Assert.ThrowsAsync<ModelVerificationException>(() => UpdateChecker.DownloadAsync(http, AssetFor(data, "https://example.com/a.zip"), path, null, CancellationToken.None));
        Assert.Equal(0, handler.Calls);
    }

    [Fact]
    public async Task RejectsRedirectToDisallowedHost()
    {
        var data = new byte[] { 1, 2, 3 };
        using var http = new HttpClient(new StubHandler(request => new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new ByteArrayContent(data),
            // リダイレクトのあと、最終の URL が別のホストだったことにする
            RequestMessage = new HttpRequestMessage(HttpMethod.Get, "https://example.com/a.zip"),
        }));
        var path = Path.Combine(TestKeys.TempDirectory(), "update.zip");
        await Assert.ThrowsAsync<ModelVerificationException>(() => UpdateChecker.DownloadAsync(http, AssetFor(data), path, null, CancellationToken.None));
        Assert.False(File.Exists(path));
    }

    // MARK: - zip の展開

    private static string MakeZip(params (string Name, string Content)[] entries)
    {
        var path = Path.Combine(TestKeys.TempDirectory(), "pkg.zip");
        using var archive = ZipFile.Open(path, ZipArchiveMode.Create);
        foreach (var (name, content) in entries)
        {
            var entry = archive.CreateEntry(name);
            using var writer = new StreamWriter(entry.Open());
            writer.Write(content);
        }
        return path;
    }

    [Fact]
    public void ExtractsPackage()
    {
        var zip = MakeZip(("Hanasu/Hanasu.exe", "exe"), ("Hanasu/llama/server.txt", "x"));
        var staging = Path.Combine(TestKeys.TempDirectory(), "staging");
        var staged = UpdatePackage.Extract(zip, staging);
        Assert.True(File.Exists(Path.Combine(staged, "Hanasu.exe")));
        Assert.True(File.Exists(Path.Combine(staged, "llama", "server.txt")));
    }

    [Fact]
    public void RejectsPathTraversalAndWrongLayout()
    {
        var staging = Path.Combine(TestKeys.TempDirectory(), "staging");
        Assert.Throws<UpdateException>(() => UpdatePackage.Extract(MakeZip(("Hanasu/Hanasu.exe", "x"), ("../evil.txt", "x")), staging));
        Assert.False(File.Exists(Path.Combine(Path.GetDirectoryName(staging)!, "evil.txt")));
        Assert.Throws<UpdateException>(() => UpdatePackage.Extract(MakeZip(("Other/Hanasu.exe", "x")), Path.Combine(TestKeys.TempDirectory(), "s2")));
    }

    // MARK: - 入れ替えてよいフォルダか

    private static string Make(string root, params string[] files)
    {
        foreach (var f in files)
        {
            var path = Path.Combine(root, f);
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(path, "x");
        }
        Directory.CreateDirectory(root);
        return root;
    }

    [Fact]
    public void DedicatedFolderHasNoForeignEntries()
    {
        var staged = Make(Path.Combine(TestKeys.TempDirectory(), "new"), "Hanasu.exe", "Hanasu.Core.dll", "llama/server.txt", "ja/x.resources.dll");
        // 古い版にだけあった dll / pdb は、外のものではない。名前の大文字小文字は問わない
        var install = Make(Path.Combine(TestKeys.TempDirectory(), "cur"), "HANASU.EXE", "Hanasu.Core.dll", "Old.dll", "Old.pdb", "llama/server.txt");
        Assert.Empty(UpdatePackage.FindForeignEntries(install, staged));
    }

    [Fact]
    public void ForeignFilesAndFoldersAreReported()
    {
        var staged = Make(Path.Combine(TestKeys.TempDirectory(), "new"), "Hanasu.exe", "llama/server.txt");
        var install = Make(Path.Combine(TestKeys.TempDirectory(), "cur"), "Hanasu.exe", "memo.txt", "report.docx", "Photos/a.jpg", "tool.exe");
        Directory.CreateDirectory(Path.Combine(install, "EmptyFolder"));
        Assert.Equal(new[] { "EmptyFolder", "memo.txt", "Photos", "report.docx", "tool.exe" }, UpdatePackage.FindForeignEntries(install, staged));
    }

    [Fact]
    public void ADirectoryNamedLikeADllIsForeign()
    {
        var staged = Make(Path.Combine(TestKeys.TempDirectory(), "new"), "Hanasu.exe");
        var install = Make(Path.Combine(TestKeys.TempDirectory(), "cur"), "Hanasu.exe", "stuff.dll/inner.txt");
        Assert.Equal(new[] { "stuff.dll" }, UpdatePackage.FindForeignEntries(install, staged));
    }

    // MARK: - リリース本文の取り出し

    private const string RealBody =
        "<!-- release-notes -->\n## ハイライト\n- 音声入力が速くなりました\n<!-- /release-notes -->\n\n## What's Changed\n* PR by @someone\n\n## インストール\n- Windows: zip を展開";

    [Fact]
    public void NotesAreTheTextBetweenMarkers()
    {
        Assert.Equal("## ハイライト\n- 音声入力が速くなりました", ReleaseParser.ExtractNotes(RealBody));
        var json = System.Text.Json.JsonSerializer.Serialize(new { tag_name = "v1.5.0", body = RealBody });
        Assert.Equal("## ハイライト\n- 音声入力が速くなりました", ReleaseParser.Parse(json)!.Notes);
    }

    [Fact]
    public void NotesFallBackToTextBeforeInstallHeading()
    {
        Assert.Equal("## 変更\n- 例", ReleaseParser.ExtractNotes("\n## 変更\n- 例\n\n## インストール\n手順"));
        Assert.Equal("## 変更\n- 例", ReleaseParser.ExtractNotes("## 変更\n- 例\n"));
        // 終わりの印がないときも、本文全体は出さない
        Assert.Equal("a", ReleaseParser.ExtractNotes("a\n## インストール\nb"));
        Assert.Equal("", ReleaseParser.ExtractNotes(""));
    }
}
