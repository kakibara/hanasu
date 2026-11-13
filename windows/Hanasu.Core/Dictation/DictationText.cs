using Hanasu.Core.Ai;
using Hanasu.Core.Gemini;
using Hanasu.Core.Settings;

namespace Hanasu.Core.Dictation;

// 要件: REQ-DIC-010, REQ-DIC-013
/// <summary>
/// 録音を始めたショートカットで決まる。整形して話した言語で入力するか、翻訳の言語（TranslationLanguages.All のどれか）に翻訳して入力するか。
/// Translation が null なら整形。default は Refine（省略できる引数に default と書ける）
/// </summary>
public readonly record struct DictationMode(TranslationLanguage? Translation)
{
    public static DictationMode Refine => default;
    public static DictationMode TranslateToEnglish => new(TranslationLanguage.English);
    public static DictationMode TranslateToJapanese => new(TranslationLanguage.Japanese);

    /// <summary>この言語に翻訳して入力するモード</summary>
    public static DictationMode Translate(TranslationLanguage language) => new(language);

    public override string ToString() => Translation is { } language ? "Translate:" + language.Code : "Refine";
}

public enum ProcessStatus
{
    /// <summary>AI（Gemini か Claude）で整形（翻訳）した</summary>
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
/// 認識結果に辞書を当て、AI（設定の「音声入力の AI」。Gemini か Claude）で整形（または翻訳）する。
/// 失敗したら原文を返して知らせる（話した内容を失わない）。
/// Mac 版の DictationController.finishDictation の中ほどにあたる（スニペット・画面の文脈・アプリごとの既定の出力言語は Windows 版にはない）。
/// 入力先アプリの文体（設定の「アプリ別」）は、録音を始めたときの前面のアプリの exe の名前で引く（REQ-DIC-020、DEC-DIC-216）。
/// </summary>
public sealed class DictationTextProcessor
{
    private readonly Func<AppSettings, IDictationRefiner?> refinerFactory;

    /// <param name="refinerFactory">設定から、音声入力の AI のクライアントを作る。認証情報がなければ null。サービスアカウントが読めなければ例外</param>
    public DictationTextProcessor(Func<AppSettings, IDictationRefiner?> refinerFactory)
    {
        this.refinerFactory = refinerFactory;
    }

    /// <summary>AI に送るか（翻訳は AI でしかできないので、整形をオフにしていても送る）</summary>
    public static bool UsesGemini(AppSettings settings, DictationMode mode) =>
        settings.RefineWithGemini || mode.Translation is not null;

    /// <param name="appName">入力先アプリの名前（アプリ名を送る設定がオフなら送らない）</param>
    /// <param name="appExe">入力先アプリの exe の名前（設定の「アプリ別」の文体を引く。アプリ名を送らない設定でも引く）</param>
    public async Task<ProcessOutcome> ProcessAsync(string raw, DictationMode mode, string? appName, AppSettings settings,
        string? appExe = null, CancellationToken cancellationToken = default)
    {
        var dictionary = settings.UserDictionary;
        // ユーザー辞書の置き換えルールを決定的に当てる（Gemini で整形しないときも効く）
        var corrected = dictionary.Apply(raw);
        if (!UsesGemini(settings, mode)) return new ProcessOutcome(corrected, ProcessStatus.RefineOff);

        var translation = mode.Translation;
        try
        {
            var refiner = refinerFactory(settings);
            if (refiner is null)
            {
                return new ProcessOutcome(corrected, ProcessStatus.NoCredentials,
                    string.Format(translation is not null ? Strings.Dictation_NoAi_Translate : Strings.Dictation_NoAi_Refine, TextAiFactory.NotReadyBecause(settings.DictationAi)));
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
                // 要件: REQ-DIC-020, REQ-DIC-023
                // 設計判断: DEC-DIC-216, DEC-DIC-046（アプリ名を送らない設定でも文体のルールは渡す。見出しにアプリ名を入れないのは AppName が null になることで決まる）
                AppStyle = AppStyleLookup.Find(settings, appExe),
            };
            var output = translation is { } language
                ? await refiner.TranslateAsync(request, language, cancellationToken).ConfigureAwait(false)
                : await refiner.RefineAsync(request, cancellationToken).ConfigureAwait(false);
            return new ProcessOutcome(output, ProcessStatus.Succeeded);
        }
        catch (Exception e) when (e is TextAiException or ServiceAccountException or HttpRequestException)
        {
            return new ProcessOutcome(corrected, ProcessStatus.AiFailed, e.Message + "\n" + (translation is not null ? Strings.Dictation_AiFailed_Translate : Strings.Dictation_AiFailed_Refine));
        }
    }
}
