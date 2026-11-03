namespace Hanasu.Core.Ai;

/// <summary>文章の処理の種類。種類ごとに、考える量（effort）と出力の上限を変える</summary>
public enum TextPurpose
{
    /// <summary>音声入力の整形</summary>
    Refine,
    /// <summary>音声入力の英訳</summary>
    Translate,
    /// <summary>会議の議事録</summary>
    Minutes,
}

/// <summary>
/// 文章の処理（整形・英訳・議事録）に使う AI。Gemini と Claude の両方がこれを満たす。
/// 音声の文字起こしは含めない（Claude は音声を受け付けないため。Gemini の文字起こしは GeminiClient を直接使う）。
/// </summary>
// 設計判断: DEC-COM-140
public interface ITextGenerator
{
    /// <summary>設定画面や知らせに出す名前（「Gemini」「Claude」）</summary>
    string ProviderName { get; }

    /// <summary>システムの指示と、ユーザーの文章 1 つを送り、応答の本文を返す</summary>
    Task<string> GenerateTextAsync(TextPurpose purpose, string systemInstruction, string userText, string model,
        CancellationToken cancellationToken = default);
}

/// <summary>音声入力の整形・英訳と、議事録の両方に使えるクライアント（GeminiClient・ClaudeClient）</summary>
public interface ITextAiClient : Gemini.IDictationRefiner, ITextGenerator
{
}

/// <summary>
/// AI の呼び出しの失敗の共通の親。Message はそのまま HUD・会議ノートに出せる日本語にする。
/// Message に API キー・送った文章・応答の中身を入れない（ログにも出るため）。
/// </summary>
public abstract class TextAiException : Exception
{
    protected TextAiException(string message, Exception? inner = null) : base(message, inner) { }

    /// <summary>認証情報が正しくない・ない（設定を直さない限り、やり直しても通らない）</summary>
    public abstract bool IsCredentialProblem { get; }
}
