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
        new(GeminiErrorKind.MissingCredentials, "Gemini の認証情報（API キーまたはサービスアカウント）が設定されていません");

    public static GeminiException Http(int status, string message) =>
        new(GeminiErrorKind.Http, $"Gemini API エラー（{status}）: {message}", status);

    public static GeminiException EmptyResponse(string? reason) =>
        new(GeminiErrorKind.EmptyResponse, "Gemini から結果が返りませんでした" + (reason is null ? "" : $"（{reason}）"), reason: reason);

    public static GeminiException InvalidResponse(Exception? inner = null) =>
        new(GeminiErrorKind.InvalidResponse, "Gemini の応答を読み取れませんでした", inner: inner);

    public static GeminiException Timeout(TimeSpan timeout) =>
        new(GeminiErrorKind.Timeout, $"Gemini の応答が {timeout.TotalSeconds:0} 秒以内に返りませんでした");
}
