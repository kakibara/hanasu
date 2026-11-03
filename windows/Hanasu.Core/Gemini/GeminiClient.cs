using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Hanasu.Core.Gemini;

/// <summary>Gemini の認証方法。</summary>
public abstract record GeminiAuth
{
    /// <summary>Google AI Studio の API キー（generativelanguage.googleapis.com）</summary>
    public sealed record ApiKey(string Key) : GeminiAuth
    {
        public override string ToString() => "GeminiAuth.ApiKey { Key = *** }";
    }

    /// <summary>Google Cloud のサービスアカウント（Vertex AI, aiplatform.googleapis.com）</summary>
    public sealed record ServiceAccount(ServiceAccountCredentials Credentials, string Location = "global") : GeminiAuth;
}

/// <summary>generateContent に送る 1 つのパート（テキストか、inline data の音声など）。</summary>
public abstract record GeminiPart
{
    public sealed record Text(string Value) : GeminiPart;
    public sealed record InlineData(string MimeType, byte[] Data) : GeminiPart;
}

/// <summary>音声入力の整形・英訳。テストや会議の記録から差し替えられるよう、インターフェイスにしておく。</summary>
public interface IDictationRefiner
{
    Task<string> RefineAsync(RefineRequest request, CancellationToken cancellationToken = default);
    Task<string> TranslateToEnglishAsync(RefineRequest request, CancellationToken cancellationToken = default);
}

/// <summary>
/// Gemini の REST（generateContent）を直接呼ぶ。SDK は使わない（Mac 版と同じ。リクエストは 1 種類だけのため）。
/// 会議の記録（議事録・長い音声の文字起こし）からも GenerateAsync を使う。
/// </summary>
public sealed class GeminiClient : IDictationRefiner
{
    private static readonly HttpClient SharedHttp = new() { Timeout = System.Threading.Timeout.InfiniteTimeSpan };

    private readonly GeminiAuth auth;
    private readonly HttpClient http;
    private readonly ServiceAccountTokenProvider tokenProvider;

    /// <summary>1 回の呼び出しの待ち時間の上限。音声入力は 15 秒（Mac 版と同じ）</summary>
    public TimeSpan Timeout { get; init; } = TimeSpan.FromSeconds(15);

    public GeminiClient(GeminiAuth auth, HttpClient? http = null, ServiceAccountTokenProvider? tokenProvider = null)
    {
        this.auth = auth;
        this.http = http ?? SharedHttp;
        this.tokenProvider = tokenProvider ?? ServiceAccountTokenProvider.Shared;
    }

    public Task<string> RefineAsync(RefineRequest request, CancellationToken cancellationToken = default) =>
        GenerateAsync(GeminiPrompts.SystemInstruction, [new GeminiPart.Text(GeminiPrompts.UserPrompt(request))], request.Model,
            cancellationToken: cancellationToken);

    /// <summary>話した内容を英語に翻訳する。追加の整形ルールは日本語の文体向けなので使わない。</summary>
    public Task<string> TranslateToEnglishAsync(RefineRequest request, CancellationToken cancellationToken = default) =>
        GenerateAsync(GeminiPrompts.TranslationInstruction, [new GeminiPart.Text(GeminiPrompts.UserPrompt(request, translating: true))], request.Model,
            cancellationToken: cancellationToken);

    /// <summary>音声（WAV など）を inline data で送り、文字起こしだけをさせる。話し声がなければ空文字を返す。</summary>
    public async Task<string> TranscribeAudioAsync(byte[] audio, string mimeType, string model, IReadOnlyList<string> dictionary,
        CancellationToken cancellationToken = default)
    {
        try
        {
            return await GenerateAsync(GeminiPrompts.TranscriptionInstruction,
                [new GeminiPart.Text(GeminiPrompts.TranscriptionPrompt(dictionary)), new GeminiPart.InlineData(mimeType, audio)],
                model, cancellationToken: cancellationToken).ConfigureAwait(false);
        }
        catch (GeminiException e) when (e.Kind == GeminiErrorKind.EmptyResponse && e.Reason is null or "STOP")
        {
            return "";
        }
    }

    /// <summary>1 回送り、応答の本文を返す。thinkingLevel を省くとモデル名から決める。</summary>
    public async Task<string> GenerateAsync(string systemInstruction, IReadOnlyList<GeminiPart> parts, string model,
        string? thinkingLevel = null, string responseMimeType = "text/plain", CancellationToken cancellationToken = default)
    {
        model = model.Trim();
        var body = BuildRequestBody(systemInstruction, parts, model, thinkingLevel, responseMimeType);
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(Timeout);
        try
        {
            using var request = await BuildHttpRequestAsync(model, body, timeout.Token).ConfigureAwait(false);
            using var response = await http.SendAsync(request, timeout.Token).ConfigureAwait(false);
            var text = await response.Content.ReadAsStringAsync(timeout.Token).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
            {
                throw GeminiException.Http((int)response.StatusCode, ErrorMessage(text));
            }
            return ParseResponseText(text);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw GeminiException.Timeout(Timeout);
        }
    }

    internal async Task<HttpRequestMessage> BuildHttpRequestAsync(string model, string body, CancellationToken cancellationToken)
    {
        var escapedModel = Uri.EscapeDataString(model);
        HttpRequestMessage request;
        switch (auth)
        {
            case GeminiAuth.ApiKey { Key: var key }:
                if (string.IsNullOrWhiteSpace(key)) throw GeminiException.MissingCredentials();
                // URL のクエリにキーを載せない
                request = new HttpRequestMessage(HttpMethod.Post,
                    $"https://generativelanguage.googleapis.com/v1beta/models/{escapedModel}:generateContent");
                request.Headers.Add("x-goog-api-key", key.Trim());
                break;
            case GeminiAuth.ServiceAccount { Credentials: var credentials, Location: var location }:
                location = string.IsNullOrWhiteSpace(location) ? "global" : location.Trim();
                // global 以外のリージョンはホスト名にリージョンが付く
                var host = location == "global" ? "aiplatform.googleapis.com" : $"{location}-aiplatform.googleapis.com";
                request = new HttpRequestMessage(HttpMethod.Post,
                    $"https://{host}/v1/projects/{Uri.EscapeDataString(credentials.ProjectId)}/locations/{Uri.EscapeDataString(location)}/publishers/google/models/{escapedModel}:generateContent");
                var token = await tokenProvider.GetAccessTokenAsync(credentials, cancellationToken).ConfigureAwait(false);
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
                break;
            default:
                throw GeminiException.MissingCredentials();
        }
        request.Content = new StringContent(body, Encoding.UTF8, "application/json");
        return request;
    }

    internal static string BuildRequestBody(string systemInstruction, IReadOnlyList<GeminiPart> parts, string model,
        string? thinkingLevel, string responseMimeType = "text/plain")
    {
        var partNodes = new JsonArray();
        foreach (var part in parts)
        {
            partNodes.Add(part switch
            {
                GeminiPart.Text t => new JsonObject { ["text"] = t.Value },
                GeminiPart.InlineData d => new JsonObject
                {
                    ["inlineData"] = new JsonObject { ["mimeType"] = d.MimeType, ["data"] = Convert.ToBase64String(d.Data) },
                },
                _ => throw new ArgumentException("未知のパート", nameof(parts)),
            });
        }
        // temperature などのサンプリングパラメータは非推奨になったため送らない（Mac 版と同じ）
        var root = new JsonObject
        {
            ["systemInstruction"] = new JsonObject { ["parts"] = new JsonArray(new JsonObject { ["text"] = systemInstruction }) },
            ["contents"] = new JsonArray(new JsonObject { ["role"] = "user", ["parts"] = partNodes }),
            ["generationConfig"] = new JsonObject
            {
                ["responseMimeType"] = responseMimeType,
                ["thinkingConfig"] = new JsonObject { ["thinkingLevel"] = thinkingLevel ?? GeminiPrompts.ThinkingLevel(model) },
            },
        };
        return root.ToJsonString();
    }

    /// <summary>candidates[0].content.parts[].text をつなぐ。thought: true のパートは思考の要約なので除く。</summary>
    internal static string ParseResponseText(string json)
    {
        JsonNode? root;
        try { root = JsonNode.Parse(json); }
        catch (JsonException e) { throw GeminiException.InvalidResponse(e); }
        if (root is not JsonObject obj) throw GeminiException.InvalidResponse();

        var candidate = (obj["candidates"] as JsonArray)?.FirstOrDefault() as JsonObject;
        if (candidate is null)
        {
            throw GeminiException.EmptyResponse(obj["promptFeedback"]?["blockReason"]?.GetValue<string>());
        }
        var sb = new StringBuilder();
        if (candidate["content"]?["parts"] is JsonArray parts)
        {
            foreach (var part in parts.OfType<JsonObject>())
            {
                if (part["thought"] is JsonValue thought && thought.TryGetValue<bool>(out var isThought) && isThought) continue;
                if (part["text"] is JsonValue text && text.TryGetValue<string>(out var s)) sb.Append(s);
            }
        }
        var result = sb.ToString().Trim();
        if (result.Length == 0)
        {
            throw GeminiException.EmptyResponse(candidate["finishReason"]?.GetValue<string>());
        }
        return result;
    }

    private static string ErrorMessage(string body)
    {
        try
        {
            if (JsonNode.Parse(body)?["error"]?["message"] is JsonValue message && message.TryGetValue<string>(out var s)) return s;
        }
        catch (JsonException) { }
        return body.Length > 500 ? body[..500] : body;
    }
}
