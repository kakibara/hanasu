using System.Net;
using System.Security.Cryptography;
using System.Text;
using Hanasu.Core.Gemini;
using Hanasu.Core.Settings;

namespace Hanasu.Core.Tests;

/// <summary>HTTP の応答を差し替える（ネットワークに出ない）</summary>
internal sealed class FakeHandler(Func<HttpRequestMessage, string?, HttpResponseMessage> respond) : HttpMessageHandler
{
    public List<(HttpRequestMessage Request, string? Body)> Requests { get; } = new();

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var body = request.Content is null ? null : await request.Content.ReadAsStringAsync(cancellationToken);
        Requests.Add((request, body));
        return respond(request, body);
    }

    public static HttpResponseMessage Json(string json, HttpStatusCode status = HttpStatusCode.OK) =>
        new(status) { Content = new StringContent(json, Encoding.UTF8, "application/json") };

    public static string TextResponse(string text) =>
        $$"""{"candidates":[{"content":{"parts":[{"text":{{System.Text.Json.JsonSerializer.Serialize(text)}}}]},"finishReason":"STOP"}]}""";
}

/// <summary>テスト用の暗号化（逆さにするだけ）</summary>
internal sealed class ReversingProtector : ISecretProtector
{
    public string Protect(string plaintext) => "p:" + new string(plaintext.Reverse().ToArray());
    public string? Unprotect(string protectedText) =>
        protectedText.StartsWith("p:") ? new string(protectedText[2..].Reverse().ToArray()) : null;
}

internal static class TestKeys
{
    /// <summary>テストのたびに作る架空のサービスアカウント鍵</summary>
    public static (ServiceAccountCredentials Credentials, RSA Rsa) MakeServiceAccount(string tokenUri = "https://oauth2.example.test/token")
    {
        var rsa = RSA.Create(2048);
        var pem = rsa.ExportPkcs8PrivateKeyPem();
        var json = System.Text.Json.JsonSerializer.Serialize(new Dictionary<string, string>
        {
            ["type"] = "service_account",
            ["project_id"] = "example-project",
            ["client_email"] = "hanasu-test@example-project.iam.gserviceaccount.com",
            ["private_key"] = pem,
            ["token_uri"] = tokenUri,
        });
        return (ServiceAccountCredentials.Parse(json), rsa);
    }

    public static string TempDirectory()
    {
        var dir = Path.Combine(Path.GetTempPath(), "hanasu-tests-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        return dir;
    }
}
