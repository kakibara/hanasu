using Hanasu.Core.Claude;
using Hanasu.Core.Gemini;
using Hanasu.Core.LocalLlm;
using Hanasu.Core.Settings;

namespace Hanasu.Core.Ai;

/// <summary>音声入力（整形・英訳）と会議（議事録）のどちらに使うか</summary>
public enum TextAiUse
{
    Dictation,
    Meeting,
}

/// <summary>
/// 設定から、文章の処理に使う AI のクライアントを作る。音声入力と会議で、AI とモデルを別々に選ぶ（REQ-COM-024）。
/// 認証情報がなければ null を返す（呼ぶ側で「未設定」と知らせる）。
/// </summary>
// 要件: REQ-COM-020, REQ-COM-024, REQ-COM-030
// 設計判断: DEC-COM-140
public static class TextAiFactory
{
    public static TextAiProvider ProviderFor(AppSettings settings, TextAiUse use) =>
        use == TextAiUse.Dictation ? settings.DictationAi : settings.MeetingAi;

    public static string ModelFor(AppSettings settings, TextAiUse use) =>
        use == TextAiUse.Dictation ? settings.DictationModel : settings.MinutesModel;

    /// <summary>AI の名前（知らせの文言に使う）</summary>
    public static string NameOf(TextAiProvider provider) => provider switch
    {
        TextAiProvider.Claude => "Claude",
        TextAiProvider.Local => "ローカル",
        _ => "Gemini",
    };

    /// <summary>認証情報がないときの文言</summary>
    public static string MissingCredentialsMessage(TextAiProvider provider) => provider switch
    {
        TextAiProvider.Claude => "Claude の API キーが設定されていません（メニュー → 設定 → AI）",
        TextAiProvider.Local => "ローカルの LLM のモデルがまだダウンロードされていません（メニュー → 設定 → AI）",
        _ => "Gemini の認証情報（API キーまたはサービスアカウント）が設定されていません（メニュー → 設定 → AI）",
    };

    /// <summary>使える状態でないときの理由（「〜ため、整形せずに入力しました」の前半）</summary>
    public static string NotReadyBecause(TextAiProvider provider) => provider == TextAiProvider.Local
        ? "ローカルの LLM のモデルがまだダウンロードされていないため"
        : $"{NameOf(provider)} の認証情報が未設定のため";

    /// <summary>ローカルのクライアント（モデルがまだダウンロードされていなければ null）</summary>
    public static LocalLlmClient? CreateLocal(AppSettings settings, TextAiUse use, TimeSpan timeout, LocalLlmServer? server = null)
    {
        server ??= LocalLlmServer.Shared;
        var model = LocalLlmModel.Find(use == TextAiUse.Dictation ? settings.LocalDictationModel : settings.LocalMeetingModel)
            ?? (use == TextAiUse.Dictation ? LocalLlmModel.DefaultDictation : LocalLlmModel.DefaultMeeting);
        if (!server.IsDownloaded(model)) return null;
        var minimum = LocalLlmClient.MinimumTimeout(use);
        return new LocalLlmClient(model, server) { Timeout = timeout > minimum ? timeout : minimum };
    }

    /// <summary>Claude のクライアント（API キーがなければ null）。キーは送るときに読む</summary>
    public static ClaudeClient? CreateClaude(SecretStore secrets, TimeSpan timeout, HttpClient? http = null) =>
        secrets.Has(SecretKind.ClaudeApiKey)
            ? new ClaudeClient(ct => secrets.GetAsync(SecretKind.ClaudeApiKey, ct), http) { Timeout = timeout }
            : null;

    /// <summary>Gemini のクライアント（認証情報がなければ null。サービスアカウントが読めなければ例外）</summary>
    public static GeminiClient? CreateGemini(AppSettings settings, SecretStore secrets, TimeSpan timeout, HttpClient? http = null) =>
        GeminiAuthResolver.Resolve(settings, secrets) is { } auth ? new GeminiClient(auth, http) { Timeout = timeout } : null;

    /// <summary>用途に合わせて作る</summary>
    public static ITextAiClient? Create(AppSettings settings, SecretStore secrets, TextAiUse use, TimeSpan timeout, HttpClient? http = null) =>
        ProviderFor(settings, use) switch
        {
            TextAiProvider.Claude => CreateClaude(secrets, timeout, http),
            TextAiProvider.Local => CreateLocal(settings, use, timeout),
            _ => CreateGemini(settings, secrets, timeout, http),
        };
}
