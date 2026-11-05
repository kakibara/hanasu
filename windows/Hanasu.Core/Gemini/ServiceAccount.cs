using System.Collections.Concurrent;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Hanasu.Core.Gemini;

public sealed class ServiceAccountException : Exception
{
    public ServiceAccountException(string message, Exception? inner = null) : base(message, inner) { }
}

/// <summary>Google Cloud のサービスアカウント鍵（JSON）。</summary>
public sealed record ServiceAccountCredentials(string ProjectId, string ClientEmail, string PrivateKey, string TokenUri)
{
    public static ServiceAccountCredentials Load(string path)
    {
        var expanded = Environment.ExpandEnvironmentVariables(path.Trim().Trim('"'));
        if (expanded.StartsWith('~'))
        {
            expanded = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), expanded.TrimStart('~', '/', '\\'));
        }
        if (!File.Exists(expanded))
        {
            throw new ServiceAccountException($"サービスアカウントの JSON が見つかりません: {path}");
        }
        return Parse(File.ReadAllText(expanded));
    }

    public static ServiceAccountCredentials Parse(string json)
    {
        try
        {
            var raw = JsonSerializer.Deserialize<RawKey>(json);
            if (raw is null || string.IsNullOrEmpty(raw.ProjectId) || string.IsNullOrEmpty(raw.ClientEmail) || string.IsNullOrEmpty(raw.PrivateKey))
            {
                throw new ServiceAccountException("サービスアカウントの JSON を読み取れません");
            }
            var tokenUri = string.IsNullOrEmpty(raw.TokenUri) ? "https://oauth2.googleapis.com/token" : raw.TokenUri;
            // 署名した JWT（鍵の代わりになる）を送る先なので、Mac 版の isTrustedTokenURL と同じく Google のトークンの窓口に限る（DEC-COM-053）。
            // 古い鍵ファイルは https://accounts.google.com/o/oauth2/token を書いている
            if (!IsTrustedTokenUri(tokenUri))
            {
                throw new ServiceAccountException(
                    $"サービスアカウントの token_uri（{tokenUri}）が Google のトークンの窓口（oauth2.googleapis.com）ではないため、使いません");
            }
            return new ServiceAccountCredentials(raw.ProjectId, raw.ClientEmail, raw.PrivateKey, tokenUri);
        }
        catch (JsonException e)
        {
            throw new ServiceAccountException("サービスアカウントの JSON を読み取れません", e);
        }
    }

    // 設計判断: DEC-COM-053
    internal static bool IsTrustedTokenUri(string tokenUri) =>
        Uri.TryCreate(tokenUri, UriKind.Absolute, out var uri)
        && uri.Scheme == Uri.UriSchemeHttps
        && uri.Host is "oauth2.googleapis.com" or "accounts.google.com"
        && uri.IsDefaultPort && string.IsNullOrEmpty(uri.UserInfo);

    private sealed class RawKey
    {
        [JsonPropertyName("project_id")] public string? ProjectId { get; set; }
        [JsonPropertyName("client_email")] public string? ClientEmail { get; set; }
        [JsonPropertyName("private_key")] public string? PrivateKey { get; set; }
        [JsonPropertyName("token_uri")] public string? TokenUri { get; set; }
    }

    // 秘密鍵をログや例外に出さない
    public override string ToString() => $"ServiceAccountCredentials {{ ProjectId = {ProjectId}, ClientEmail = {ClientEmail} }}";
}

/// <summary>
/// サービスアカウント鍵で署名した JWT（RS256）を OAuth のアクセストークンに交換し、期限の 1 分前まで使い回す。
/// Mac 版の ServiceAccountTokenProvider と同じ流れ。署名は .NET の RSA で行う（PKCS#8 の PEM をそのまま読める）。
/// </summary>
public sealed class ServiceAccountTokenProvider
{
    public const string Scope = "https://www.googleapis.com/auth/cloud-platform";

    public static ServiceAccountTokenProvider Shared { get; } = new(SafeHttp.Create(TimeSpan.FromSeconds(30)));

    private readonly HttpClient http;
    private readonly Func<DateTimeOffset> now;
    private readonly ConcurrentDictionary<string, (string Token, DateTimeOffset ExpiresAt)> cache = new();

    public ServiceAccountTokenProvider(HttpClient http, Func<DateTimeOffset>? now = null)
    {
        this.http = http;
        this.now = now ?? (() => DateTimeOffset.UtcNow);
    }

    public async Task<string> GetAccessTokenAsync(ServiceAccountCredentials credentials, CancellationToken cancellationToken = default)
    {
        if (cache.TryGetValue(credentials.ClientEmail, out var cached) && cached.ExpiresAt - now() > TimeSpan.FromSeconds(60))
        {
            return cached.Token;
        }
        var assertion = MakeJwt(credentials, now());
        using var request = new HttpRequestMessage(HttpMethod.Post, credentials.TokenUri)
        {
            Content = new FormUrlEncodedContent(new Dictionary<string, string>
            {
                ["grant_type"] = "urn:ietf:params:oauth:grant-type:jwt-bearer",
                ["assertion"] = assertion,
            }),
        };
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(15));
        HttpResponseMessage response;
        try
        {
            response = await http.SendAsync(request, timeout.Token).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw new ServiceAccountException("アクセストークンの取得がタイムアウトしました");
        }
        using (response)
        {
            var body = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
            TokenResponse? token = null;
            if (response.IsSuccessStatusCode)
            {
                try { token = JsonSerializer.Deserialize<TokenResponse>(body); } catch (JsonException) { }
            }
            if (token?.AccessToken is not { Length: > 0 } accessToken)
            {
                throw new ServiceAccountException($"アクセストークンの取得に失敗しました（{(int)response.StatusCode}）: {body}");
            }
            cache[credentials.ClientEmail] = (accessToken, now().AddSeconds(token.ExpiresIn));
            return accessToken;
        }
    }

    private sealed class TokenResponse
    {
        [JsonPropertyName("access_token")] public string? AccessToken { get; set; }
        [JsonPropertyName("expires_in")] public int ExpiresIn { get; set; }
    }

    /// <summary>RS256 の JWT を作る（テストから署名を確かめられるよう internal にしている）</summary>
    internal static string MakeJwt(ServiceAccountCredentials credentials, DateTimeOffset issuedAt)
    {
        var iat = issuedAt.ToUnixTimeSeconds();
        var header = """{"alg":"RS256","typ":"JWT"}""";
        var claims = JsonSerializer.Serialize(new Dictionary<string, object>
        {
            ["iss"] = credentials.ClientEmail,
            ["scope"] = Scope,
            ["aud"] = credentials.TokenUri,
            ["iat"] = iat,
            ["exp"] = iat + 3600,
        });
        var signingInput = Base64Url(Encoding.UTF8.GetBytes(header)) + "." + Base64Url(Encoding.UTF8.GetBytes(claims));

        using var rsa = RSA.Create();
        try
        {
            // JSON の private_key は "-----BEGIN PRIVATE KEY-----"（PKCS#8）。PKCS#1 の PEM も読める
            rsa.ImportFromPem(credentials.PrivateKey.Replace("\\n", "\n"));
        }
        catch (Exception e) when (e is ArgumentException or CryptographicException)
        {
            throw new ServiceAccountException("サービスアカウントの秘密鍵を読み取れません", e);
        }
        byte[] signature;
        try
        {
            signature = rsa.SignData(Encoding.ASCII.GetBytes(signingInput), HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        }
        catch (CryptographicException e)
        {
            throw new ServiceAccountException($"アクセストークン用の署名に失敗しました: {e.Message}", e);
        }
        return signingInput + "." + Base64Url(signature);
    }

    internal static string Base64Url(byte[] data) =>
        Convert.ToBase64String(data).TrimEnd('=').Replace('+', '-').Replace('/', '_');
}
