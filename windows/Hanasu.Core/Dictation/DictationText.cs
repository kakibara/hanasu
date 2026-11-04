using Hanasu.Core.Ai;
using Hanasu.Core.Gemini;
using Hanasu.Core.Settings;

namespace Hanasu.Core.Dictation;

/// <summary>録音を始めたショートカットで決まる。整形して日本語で入力するか、英語に翻訳して入力するか</summary>
public enum DictationMode { Refine, TranslateToEnglish }

public enum ProcessStatus
{
    /// <summary>AI（Gemini か Claude）で整形（英訳）した</summary>
    Succeeded,
    /// <summary>整形をオフにしていたので、辞書だけ当てた</summary>
    RefineOff,
    /// <summary>認証情報がないので、原文を入力した</summary>
    NoCredentials,
    /// <summary>AI が失敗したので、原文を入力した</summary>
    AiFailed,
}

/// <summary>整形の結果。Warning があれば HUD でエラーとして知らせる（入力はする）。</summary>
public sealed record ProcessOutcome(string Output, ProcessStatus Status, string? Warning = null);

/// <summary>
/// 認識結果に辞書を当て、AI（設定の「音声入力の AI」。Gemini か Claude）で整形（または英訳）する。
/// 失敗したら原文を返して知らせる（話した内容を失わない）。
/// Mac 版の DictationController.finishDictation の中ほどにあたる（スニペット・アプリ別スタイル・画面の文脈は Windows 版にはない）。
/// </summary>
public sealed class DictationTextProcessor
{
    private readonly Func<AppSettings, IDictationRefiner?> refinerFactory;

    /// <param name="refinerFactory">設定から、音声入力の AI のクライアントを作る。認証情報がなければ null。サービスアカウントが読めなければ例外</param>
    public DictationTextProcessor(Func<AppSettings, IDictationRefiner?> refinerFactory)
    {
        this.refinerFactory = refinerFactory;
    }

    /// <summary>AI に送るか（英訳は AI でしかできないので、整形をオフにしていても送る）</summary>
    public static bool UsesGemini(AppSettings settings, DictationMode mode) =>
        settings.RefineWithGemini || mode == DictationMode.TranslateToEnglish;

    public async Task<ProcessOutcome> ProcessAsync(string raw, DictationMode mode, string? appName, AppSettings settings,
        CancellationToken cancellationToken = default)
    {
        var dictionary = settings.UserDictionary;
        // ユーザー辞書の置き換えルールを決定的に当てる（Gemini で整形しないときも効く）
        var corrected = dictionary.Apply(raw);
        if (!UsesGemini(settings, mode)) return new ProcessOutcome(corrected, ProcessStatus.RefineOff);

        var translating = mode == DictationMode.TranslateToEnglish;
        var verb = translating ? "翻訳" : "整形";
        try
        {
            var refiner = refinerFactory(settings);
            if (refiner is null)
            {
                return new ProcessOutcome(corrected, ProcessStatus.NoCredentials,
                    $"{TextAiFactory.NotReadyBecause(settings.DictationAi)}、{verb}せずに入力しました（メニュー → 設定 → AI）。");
            }
            var request = new RefineRequest
            {
                Transcript = corrected,
                Model = settings.DictationModel,
                AppName = settings.SendAppName ? appName : null,
                Dictionary = dictionary.Spellings,
                ExtraInstructions = settings.ExtraInstructions,
                DictionaryRules = dictionary.Rules,
                // 要件: REQ-DIC-082
                OutputLanguage = settings.RefineOutputLanguage,
            };
            var output = translating
                ? await refiner.TranslateToEnglishAsync(request, cancellationToken).ConfigureAwait(false)
                : await refiner.RefineAsync(request, cancellationToken).ConfigureAwait(false);
            return new ProcessOutcome(output, ProcessStatus.Succeeded);
        }
        catch (Exception e) when (e is TextAiException or ServiceAccountException or HttpRequestException)
        {
            return new ProcessOutcome(corrected, ProcessStatus.AiFailed, $"{e.Message}\n{verb}前の文章を入力しました。");
        }
    }
}
