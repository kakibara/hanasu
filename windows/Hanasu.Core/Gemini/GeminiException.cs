using Hanasu.Core.Ai;

namespace Hanasu.Core.Gemini;

public enum GeminiErrorKind
{
    MissingCredentials,
    Http,
    EmptyResponse,
    InvalidResponse,
    Timeout,
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

    public override bool IsCredentialProblem => Kind == GeminiErrorKind.MissingCredentials || StatusCode is 401 or 403;

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
}
