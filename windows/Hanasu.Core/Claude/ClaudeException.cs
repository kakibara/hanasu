using Anthropic.Exceptions;
using Hanasu.Core.Ai;

namespace Hanasu.Core.Claude;

public enum ClaudeErrorKind
{
    /// <summary>API キーが保存されていない（または読めない）</summary>
    MissingCredentials,
    /// <summary>401: API キーが正しくない</summary>
    Unauthorized,
    /// <summary>403: このキーでは使えない</summary>
    Forbidden,
    /// <summary>404: モデルがない・このキーでは使えない</summary>
    NotFound,
    /// <summary>400・413 など、送った内容の問題</summary>
    BadRequest,
    /// <summary>402: 支払いの問題</summary>
    Billing,
    /// <summary>429: 使いすぎ（SDK がやり直したうえで、まだ通らない）</summary>
    RateLimited,
    /// <summary>529: 混み合っている（SDK がやり直したうえで、まだ通らない）</summary>
    Overloaded,
    /// <summary>500 番台</summary>
    Server,
    /// <summary>つながらない</summary>
    Network,
    Timeout,
    /// <summary>stop_reason が refusal（安全の判定で断られた）</summary>
    Refusal,
    /// <summary>stop_reason が max_tokens（途中で切れた）</summary>
    MaxTokens,
    /// <summary>本文が空</summary>
    EmptyResponse,
}

/// <summary>
/// Claude の呼び出しの失敗。Message はそのまま HUD・設定画面に出せる日本語にする。
/// SDK の例外の Message（応答の本文が入ることがある）は、そのまま外に出さず、API が返した短い説明だけを添える。
/// </summary>
// 設計判断: DEC-COM-143
public sealed class ClaudeException : TextAiException
{
    public ClaudeErrorKind Kind { get; }
    public int? StatusCode { get; }
    /// <summary>Refusal のときの stop_details.category（cyber など。null のこともある）</summary>
    public string? RefusalCategory { get; }

    private ClaudeException(ClaudeErrorKind kind, string message, int? status = null, string? category = null, Exception? inner = null)
        : base(message, inner)
    {
        Kind = kind;
        StatusCode = status;
        RefusalCategory = category;
    }

    public override bool IsCredentialProblem => Kind is ClaudeErrorKind.MissingCredentials or ClaudeErrorKind.Unauthorized or ClaudeErrorKind.Forbidden;

    /// <summary>やり直せば通るかもしれない（SDK のやり直しのあとでも、時間をおけば）</summary>
    public bool IsTransient => Kind is ClaudeErrorKind.RateLimited or ClaudeErrorKind.Overloaded or ClaudeErrorKind.Server
        or ClaudeErrorKind.Network or ClaudeErrorKind.Timeout;

    public static ClaudeException MissingCredentials() =>
        new(ClaudeErrorKind.MissingCredentials, Strings.Claude_MissingCredentials);

    public static ClaudeException Timeout(TimeSpan timeout) =>
        new(ClaudeErrorKind.Timeout, string.Format(Strings.Claude_Timeout, timeout.TotalSeconds.ToString("0")));

    public static ClaudeException Refusal(string? category) =>
        new(ClaudeErrorKind.Refusal,
            string.IsNullOrEmpty(category) ? Strings.Claude_Refusal : string.Format(Strings.Claude_RefusalWithCategory, category), category: category);

    public static ClaudeException MaxTokens() =>
        new(ClaudeErrorKind.MaxTokens, Strings.Claude_MaxTokens);

    public static ClaudeException EmptyResponse() =>
        new(ClaudeErrorKind.EmptyResponse, Strings.Claude_EmptyResponse);

    /// <summary>HTTP の状態番号から、分かる文言にする。detail は API の error.message（短いものだけ）</summary>
    public static ClaudeException FromStatus(int status, string model, string? detail = null, Exception? inner = null)
    {
        var suffix = Short(detail) is { Length: > 0 } d ? $": {d}" : "";
        return status switch
        {
            401 => new(ClaudeErrorKind.Unauthorized,
                Strings.Claude_Unauthorized, status, inner: inner),
            403 => new(ClaudeErrorKind.Forbidden, Strings.Claude_Forbidden + suffix, status, inner: inner),
            404 => new(ClaudeErrorKind.NotFound, string.Format(Strings.Claude_NotFound, model), status, inner: inner),
            402 => new(ClaudeErrorKind.Billing, Strings.Claude_Billing, status, inner: inner),
            429 => new(ClaudeErrorKind.RateLimited, Strings.Claude_RateLimited, status, inner: inner),
            529 => new(ClaudeErrorKind.Overloaded, Strings.Claude_Overloaded, status, inner: inner),
            >= 500 => new(ClaudeErrorKind.Server, string.Format(Strings.Claude_Server, status), status, inner: inner),
            _ => new(ClaudeErrorKind.BadRequest, string.Format(Strings.Claude_BadRequest, status) + suffix, status, inner: inner),
        };
    }

    /// <summary>SDK の例外を分ける。分けられないものは null（呼ぶ側でそのまま投げる）</summary>
    public static ClaudeException? FromSdk(Exception e, string model) => e switch
    {
        ClaudeException c => c,
        AnthropicApiException api => FromStatus((int)api.StatusCode, model, ApiErrorMessage(api), api),
        AnthropicIOException io => new(ClaudeErrorKind.Network, Strings.Claude_Network, inner: io),
        HttpRequestException http => new(ClaudeErrorKind.Network, Strings.Claude_Network, inner: http),
        _ => null,
    };

    /// <summary>応答の本文（JSON）から error.message だけを取り出す</summary>
    internal static string? ApiErrorMessage(AnthropicApiException e)
    {
        try
        {
            var body = e.ResponseBody;
            if (string.IsNullOrEmpty(body)) return null;
            using var doc = System.Text.Json.JsonDocument.Parse(body);
            return doc.RootElement.TryGetProperty("error", out var error) && error.TryGetProperty("message", out var message)
                ? message.GetString()
                : null;
        }
        catch (System.Text.Json.JsonException)
        {
            return null;
        }
    }

    private static string? Short(string? s) => s is null ? null : (s.Length > 200 ? s[..200] + "…" : s);
}
