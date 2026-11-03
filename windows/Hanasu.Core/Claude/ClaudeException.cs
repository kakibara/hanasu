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
        new(ClaudeErrorKind.MissingCredentials, "Claude の API キーが設定されていません（メニュー → 設定 → AI）");

    public static ClaudeException Timeout(TimeSpan timeout) =>
        new(ClaudeErrorKind.Timeout, $"Claude の応答が {timeout.TotalSeconds:0} 秒以内に返りませんでした");

    public static ClaudeException Refusal(string? category) =>
        new(ClaudeErrorKind.Refusal,
            "Claude が安全の判定でこの文章の処理を断りました" + (string.IsNullOrEmpty(category) ? "" : $"（{category}）")
            + "。別のモデル（設定 → AI）か Gemini で試してください", category: category);

    public static ClaudeException MaxTokens() =>
        new(ClaudeErrorKind.MaxTokens, "Claude の応答が長すぎて途中で切れました");

    public static ClaudeException EmptyResponse() =>
        new(ClaudeErrorKind.EmptyResponse, "Claude から結果が返りませんでした");

    /// <summary>HTTP の状態番号から、分かる文言にする。detail は API の error.message（短いものだけ）</summary>
    public static ClaudeException FromStatus(int status, string model, string? detail = null, Exception? inner = null)
    {
        var suffix = Short(detail) is { Length: > 0 } d ? $": {d}" : "";
        return status switch
        {
            401 => new(ClaudeErrorKind.Unauthorized,
                "Claude の API キーが正しくありません（401）。設定 → AI で、Claude Console で作ったキーを入れ直してください", status, inner: inner),
            403 => new(ClaudeErrorKind.Forbidden, $"この API キーでは Claude を使えません（403）{suffix}", status, inner: inner),
            404 => new(ClaudeErrorKind.NotFound, $"モデル {model} が見つからないか、この API キーでは使えません（404）", status, inner: inner),
            402 => new(ClaudeErrorKind.Billing, $"Claude API の支払いに問題があります（402）。Claude Console の請求の設定を確かめてください", status, inner: inner),
            429 => new(ClaudeErrorKind.RateLimited, "Claude API の利用の上限に達しました（429）。少し待ってから試してください", status, inner: inner),
            529 => new(ClaudeErrorKind.Overloaded, "Claude API が混み合っています（529）。少し待ってから試してください", status, inner: inner),
            >= 500 => new(ClaudeErrorKind.Server, $"Claude API でエラーが起きました（{status}）。少し待ってから試してください", status, inner: inner),
            _ => new(ClaudeErrorKind.BadRequest, $"Claude API がリクエストを受け付けませんでした（{status}）{suffix}", status, inner: inner),
        };
    }

    /// <summary>SDK の例外を分ける。分けられないものは null（呼ぶ側でそのまま投げる）</summary>
    public static ClaudeException? FromSdk(Exception e, string model) => e switch
    {
        ClaudeException c => c,
        AnthropicApiException api => FromStatus((int)api.StatusCode, model, ApiErrorMessage(api), api),
        AnthropicIOException io => new(ClaudeErrorKind.Network, "Claude API につながりませんでした。ネットワークを確かめてください", inner: io),
        HttpRequestException http => new(ClaudeErrorKind.Network, "Claude API につながりませんでした。ネットワークを確かめてください", inner: http),
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
