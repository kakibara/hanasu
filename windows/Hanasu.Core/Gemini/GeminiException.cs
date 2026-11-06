using Hanasu.Core.Ai;

namespace Hanasu.Core.Gemini;

public enum GeminiErrorKind
{
    MissingCredentials,
    Http,
    EmptyResponse,
    InvalidResponse,
    Timeout,
    /// <summary>Vertex AI のリージョンの設定が、ホスト名に入れられる形ではない（設定を直すまで通らない）</summary>
    InvalidLocation,
    /// <summary>「接続を試す」で、認証が通らなかった（400 API_KEY_INVALID / 401 / 403）</summary>
    InvalidCredentials,
    /// <summary>「接続を試す」で、モデルが見つからなかった（404）</summary>
    ModelUnavailable,
}

/// <summary>Gemini の呼び出しの失敗。Message はそのまま HUD に出せる日本語にする。</summary>
public sealed class GeminiException : TextAiException
{
    public GeminiErrorKind Kind { get; }
    public int? StatusCode { get; }
    /// <summary>EmptyResponse のときの理由（finishReason / blockReason）</summary>
    public string? Reason { get; }

    private GeminiException(GeminiErrorKind kind, string message, int? status = null, string? reason = null, Exception? inner = null)
        : base(message, inner)
    {
        Kind = kind;
        StatusCode = status;
        Reason = reason;
    }

    public override bool IsCredentialProblem =>
        Kind is GeminiErrorKind.MissingCredentials or GeminiErrorKind.InvalidLocation or GeminiErrorKind.InvalidCredentials
        || StatusCode is 401 or 403;

    // 設計判断: DEC-COM-143
    /// <summary>「接続を試す」の文言（Mac 版の GeminiError.invalidCredentials / modelUnavailable と同じ）</summary>
    public static GeminiException InvalidCredentials(int status) =>
        new(GeminiErrorKind.InvalidCredentials, string.Format(Strings.Gemini_InvalidCredentials, status), status);

    public static GeminiException ModelUnavailable(string model) =>
        new(GeminiErrorKind.ModelUnavailable, string.Format(Strings.Gemini_ModelUnavailable, model), 404);

    public static GeminiException MissingCredentials() =>
        new(GeminiErrorKind.MissingCredentials, Strings.Gemini_MissingCredentials);

    public static GeminiException Http(int status, string message) =>
        new(GeminiErrorKind.Http, string.Format(Strings.Gemini_Http, status, message), status);

    public static GeminiException EmptyResponse(string? reason) =>
        new(GeminiErrorKind.EmptyResponse, reason is null ? Strings.Gemini_EmptyResponse : string.Format(Strings.Gemini_EmptyResponseWithReason, reason), reason: reason);

    public static GeminiException InvalidResponse(Exception? inner = null) =>
        new(GeminiErrorKind.InvalidResponse, Strings.Gemini_InvalidResponse, inner: inner);

    public static GeminiException Timeout(TimeSpan timeout) =>
        new(GeminiErrorKind.Timeout, string.Format(Strings.Gemini_Timeout, timeout.TotalSeconds.ToString("0")));

    /// <summary>Mac 版の GeminiError.invalidLocation と同じ文言</summary>
    public static GeminiException InvalidLocation(string location) =>
        new(GeminiErrorKind.InvalidLocation, string.Format(Strings.Gemini_InvalidLocation, location));
}
