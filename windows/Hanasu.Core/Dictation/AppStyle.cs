using Hanasu.Core.Ai;

namespace Hanasu.Core.Dictation;

// 入力先アプリに合わせた文体（Mac 版 AppStyles.swift の AppStylePreset・AppStyle の移植）。
// Windows のアプリにはアプリ別の文体の設定がないので、hanasu refine の --style・--app だけが使う（決定 5。DEC-DIC-190）。

// 設計判断: DEC-DIC-040, DEC-DIC-041, DEC-DIC-042
/// <summary>文体のひな形</summary>
public enum AppStylePreset
{
    None,
    Chat,
    Email,
    DocumentPolite,
    DocumentPlain,
}

public static class AppStylePresets
{
    /// <summary>プロンプトのキーに使う名前（Mac 版の rawValue と同じ）</summary>
    public static string RawValue(this AppStylePreset preset) => preset switch
    {
        AppStylePreset.Chat => "chat",
        AppStylePreset.Email => "email",
        AppStylePreset.DocumentPolite => "documentPolite",
        AppStylePreset.DocumentPlain => "documentPlain",
        _ => "none",
    };

    public static AppStylePreset? FromRawValue(string? raw) =>
        Enum.GetValues<AppStylePreset>().Cast<AppStylePreset?>().FirstOrDefault(p => p!.Value.RawValue() == raw);

    /// <summary>--style の値（none・chat・email・document-polite・document-plain）</summary>
    public static AppStylePreset? FromCommandValue(string raw) => raw.ToLowerInvariant() switch
    {
        "none" => AppStylePreset.None,
        "chat" => AppStylePreset.Chat,
        "email" => AppStylePreset.Email,
        "document-polite" => AppStylePreset.DocumentPolite,
        "document-plain" => AppStylePreset.DocumentPlain,
        _ => null,
    };

    // 要件: REQ-COM-061
    /// <summary>話した言語で整えるときのルール（style.&lt;プリセット&gt;.refine）</summary>
    public static IReadOnlyList<string> RefineRules(this AppStylePreset preset) =>
        preset == AppStylePreset.None ? Array.Empty<string>() : Prompts.List($"style.{preset.RawValue()}.refine");

    // 要件: REQ-COM-061
    /// <summary>日本語以外に訳すときのルール。英訳は style.&lt;プリセット&gt;.translation、ほかの言語は translationOther</summary>
    public static IReadOnlyList<string> TranslationRules(this AppStylePreset preset, TranslationLanguage language)
    {
        var suffix = language == TranslationLanguage.English ? "translation" : "translationOther";
        return preset switch
        {
            AppStylePreset.None => Array.Empty<string>(),
            AppStylePreset.Chat or AppStylePreset.Email => Prompts.List($"style.{preset.RawValue()}.{suffix}"),
            _ => Prompts.List($"style.document.{suffix}"),
        };
    }
}

/// <summary>1 つのアプリの整形スタイル</summary>
/// <param name="Id">Mac の bundle ID か、Windows の exe の名前</param>
/// <param name="Name">アプリ名（AI に送る）</param>
/// <param name="Rules">このアプリ用の追加ルール（Windows の hanasu では使わない）</param>
public sealed record AppStyle(string Id, string Name, AppStylePreset Preset, string Rules = "")
{
    /// <summary>プロンプトに足すものがあるか</summary>
    public bool HasRules => Preset != AppStylePreset.None || Rules.Trim().Length > 0;

    // 要件: REQ-DIC-020
    // 設計判断: DEC-DIC-043, DEC-DIC-044, DEC-DIC-046, DEC-DIC-028
    /// <summary>
    /// 整形・翻訳の user content に足す節（Mac 版 AppStyle.promptSection と同じ組み立て）。足すものがなければ null。
    /// appName: アプリ名を AI に伝える設定がオフなら null。translation: 翻訳の言語（整形なら null）。
    /// hasCommonRules: 共通の追加ルールがプロンプトに入っているか（入っていれば優先順位を書く）
    /// </summary>
    public string? PromptSection(string? appName, TranslationLanguage? translation, bool hasCommonRules)
    {
        if (!HasRules) return null;
        // 日本語以外に訳すときは、訳す先の言語向けのルールにする（和訳は整形と同じ日本語のルール）
        TranslationLanguage? target = translation is { } t && t != TranslationLanguage.Japanese ? t : null;
        var presetRules = target is { } language ? Preset.TranslationRules(language) : Preset.RefineRules();
        var custom = Rules.Trim();
        var lines = new List<string>
        {
            string.IsNullOrEmpty(appName) ? Prompts.Text("style.header") : Prompts.Text("style.headerWithApp", ("app", appName)),
        };
        lines.AddRange(presetRules.Select(r => $"- {r}"));
        if (custom.Length > 0)
        {
            lines.Add(Prompts.Text(presetRules.Count == 0 ? "style.custom" : "style.customOverridesPreset"));
            lines.AddRange(custom.Split(['\n', '\r'], StringSplitOptions.RemoveEmptyEntries).Select(l => $"  {l}"));
            if (target is { } other)
            {
                lines.Add(other == TranslationLanguage.English
                    ? Prompts.Text("style.customTranslationNote")
                    : Prompts.Text("style.customTranslationNoteOther", ("language", other.NameIn(PromptLanguage.Current))));
            }
        }
        // system instruction の「口調を保つ」と食い違うので、どちらを優先するかを書いておく
        var overridden = Prompts.Text(translation is not null ? "style.overrides.translation" : "style.overrides.refine");
        lines.Add(Prompts.Text("style.priority", ("overridden", overridden)));
        if (hasCommonRules) lines.Add(Prompts.Text("style.priorityOverCommonRules"));
        return string.Join("\n", lines);
    }
}
