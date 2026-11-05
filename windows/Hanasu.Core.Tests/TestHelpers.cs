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

/// <summary>
/// テスト用の DPAPI。エントロピーと「ユーザー」を混ぜて XOR するだけ（違うエントロピー・違うユーザーでは読めない）
/// </summary>
internal sealed class FakeDpapi(string user = "alice") : IDataProtector
{
    private static readonly byte[] Magic = "DPAPI"u8.ToArray();

    public byte[] Protect(byte[] data, byte[] entropy)
    {
        var pad = Pad(entropy, data.Length);
        return Magic.Concat(SHA256.HashData(entropy.Concat(Encoding.UTF8.GetBytes(user)).ToArray()).Take(4))
            .Concat(data.Select((b, i) => (byte)(b ^ pad[i]))).ToArray();
    }

    public byte[]? Unprotect(byte[] data, byte[] entropy)
    {
        if (data.Length < 9 || !data.AsSpan(0, 5).SequenceEqual(Magic)) return null;
        var check = SHA256.HashData(entropy.Concat(Encoding.UTF8.GetBytes(user)).ToArray()).Take(4).ToArray();
        if (!data.AsSpan(5, 4).SequenceEqual(check)) return null;
        var body = data[9..];
        var pad = Pad(entropy, body.Length);
        return body.Select((b, i) => (byte)(b ^ pad[i])).ToArray();
    }

    private byte[] Pad(byte[] entropy, int length)
    {
        var seed = SHA256.HashData(entropy.Concat(Encoding.UTF8.GetBytes(user)).ToArray());
        return Enumerable.Range(0, length).Select(i => seed[i % seed.Length]).ToArray();
    }
}

/// <summary>テスト用の Windows Hello。確認の回数を数える。deterministic が false なら、毎回違う鍵を返す（壊れた実装のまね）</summary>
internal sealed class FakePresenceKey : IUserPresenceKey
{
    private byte[]? key;
    public bool Available { get; set; } = true;
    public bool Deterministic { get; set; } = true;
    public bool Refuse { get; set; }
    public int Prompts { get; private set; }

    public Task<bool> IsAvailableAsync() => Task.FromResult(Available);

    public Task<byte[]> DeriveKeyAsync(bool create, CancellationToken cancellationToken)
    {
        Prompts++;
        if (Refuse) throw new SecretAccessException("Windows Hello の確認が取り消されました");
        if (key is null)
        {
            if (!create) throw new SecretAccessException("鍵がない");
            key = RandomNumberGenerator.GetBytes(32);
        }
        return Task.FromResult(Deterministic ? (byte[])key.Clone() : RandomNumberGenerator.GetBytes(32));
    }
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
        });
        // Parse は token_uri を Google の窓口に限る（DEC-COM-053）ので、テスト用の偽の窓口は Parse のあとで差し込む
        return (ServiceAccountCredentials.Parse(json) with { TokenUri = tokenUri }, rsa);
    }

    public static SecretStore Secrets(string? dir = null, IUserPresenceKey? presence = null, string user = "alice") =>
        new(Path.Combine(dir ?? TempDirectory(), "secrets.json"), new FakeDpapi(user), presence);

    public static string TempDirectory()
    {
        var dir = Path.Combine(Path.GetTempPath(), "hanasu-tests-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        return dir;
    }
}
