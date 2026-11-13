using System.Text.Json.Serialization;
using Hanasu.Core.Ai;
using Hanasu.Core.Settings;

namespace Hanasu.Core.Dictation;

// 入力先アプリに合わせた文体（Mac 版 AppStyles.swift の AppStylePreset・AppStyle・CustomStyle の移植）。
// アプリの音声入力（設定の「アプリ別」。AppStyleLookup.Find で前面のアプリの exe の名前から引く）と、
// hanasu refine の --style・--app が使う（REQ-DIC-020・160、DEC-DIC-190・216）。

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

    // 要件: REQ-DIC-020
    /// <summary>画面に出す名前（Mac 版の AppStylePreset.label と同じ）。カスタム文体の名前の重複の検査にも使う（DEC-DIC-213）</summary>
    public static string Label(this AppStylePreset preset) => preset switch
    {
        AppStylePreset.Chat => Strings.AppStyle_Preset_Chat,
        AppStylePreset.Email => Strings.AppStyle_Preset_Email,
        AppStylePreset.DocumentPolite => Strings.AppStyle_Preset_DocumentPolite,
        AppStylePreset.DocumentPlain => Strings.AppStyle_Preset_DocumentPlain,
        _ => Strings.AppStyle_Preset_None,
    };

    // 要件: REQ-COM-061
    /// <summary>話した言語で整えるときのルール（style.&lt;プリセット&gt;.refine）</summary>
    /// <remarks>出力が日本語（和訳・整形の「日本語に統一」）なら language に Ja を渡して日本語の文体のルールにする（DEC-DIC-028。Mac と同じ）</remarks>
    public static IReadOnlyList<string> RefineRules(this AppStylePreset preset, PromptLanguage? language = null) =>
        preset == AppStylePreset.None ? Array.Empty<string>() : Prompts.List($"style.{preset.RawValue()}.refine", language);

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

/// <summary>1 つのアプリの整形スタイル（設定の行 AppStyleSetting を、カスタム文体まで解決したもの）</summary>
/// <param name="Id">Mac の bundle ID か、Windows の exe の名前</param>
/// <param name="Name">アプリ名（AI に送る）</param>
/// <param name="Rules">このアプリ用の追加ルール</param>
/// <param name="Custom">割り当てたカスタム文体（REQ-DIC-023）。割り当てていない・見つからないときは null。あるときの Preset は None</param>
public sealed record AppStyle(string Id, string Name, AppStylePreset Preset, string Rules = "", CustomStyle? Custom = null)
{
    // 設計判断: DEC-DIC-213
    /// <summary>プロンプトに足すものがあるか。カスタム文体を割り当てていれば true</summary>
    public bool HasRules => Preset != AppStylePreset.None || Custom is not null || Rules.Trim().Length > 0;

    // 要件: REQ-DIC-020, REQ-DIC-023
    // 設計判断: DEC-DIC-043, DEC-DIC-044, DEC-DIC-046, DEC-DIC-028, DEC-DIC-214
    /// <summary>
    /// 整形・翻訳の user content に足す節（Mac 版 AppStyle.promptSection と一字一句同じ組み立て）。足すものがなければ null。
    /// appName: アプリ名を AI に伝える設定がオフなら null。translation: 翻訳の言語（整形なら null）。
    /// hasCommonRules: 共通の追加ルールがプロンプトに入っているか（入っていれば優先順位を書く）。
    /// japaneseOutput: 整形の出力を日本語に統一するか（REQ-DIC-082。和訳と同じく日本語の文体のルールにする）
    /// </summary>
    public string? PromptSection(string? appName, TranslationLanguage? translation, bool hasCommonRules, bool japaneseOutput = false)
    {
        if (!HasRules) return null;
        // 日本語以外に訳すときは、訳す先の言語向けのルールにする。出力が日本語（和訳・日本語に統一）なら、
        // プロンプトの言語によらず日本語の文体のルール（ja.json）にする（Mac 版と同じ）
        var japanese = translation is { } tl ? tl.OutputsJapanese : japaneseOutput;
        TranslationLanguage? target = japanese ? null : translation;
        // 設計判断: DEC-DIC-214（カスタム文体は、出力の言語が学んだ言語と同じときだけ、プリセットのルールの代わりに渡す。名前は送らない）
        var outputLanguage = translation?.Language ?? (japaneseOutput ? PromptLanguage.Ja : PromptLanguage.Current);
        List<string> styleRules;
        if (Custom is { } learned)
        {
            styleRules = learned.PromptLanguage == outputLanguage && learned.Rules.Count > 0
                ? [.. learned.Rules.Select(r => $"- {r}"), Prompts.Text("style.learnedGuard")]
                : [];
        }
        else
        {
            var presetRules = target is { } language ? Preset.TranslationRules(language) : Preset.RefineRules(japanese ? PromptLanguage.Ja : null);
            styleRules = presetRules.Select(r => $"- {r}").ToList();
        }
        var custom = Rules.Trim();
        if (styleRules.Count == 0 && custom.Length == 0) return null;
        var lines = new List<string>
        {
            string.IsNullOrEmpty(appName) ? Prompts.Text("style.header") : Prompts.Text("style.headerWithApp", ("app", appName)),
        };
        lines.AddRange(styleRules);
        if (custom.Length > 0)
        {
            lines.Add(Prompts.Text(styleRules.Count == 0 ? "style.custom" : "style.customOverridesPreset"));
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

// 要件: REQ-DIC-022, REQ-DIC-023
// 設計判断: DEC-DIC-213
/// <summary>
/// 文章から学んだ文体（カスタム文体）。名前・言語・ルールだけを持ち、学んだ文章は持たない（Mac 版の CustomStyle と同じ）。
/// settings.json の customStyles に入る（AppSettings.CustomStyles）
/// </summary>
public sealed record CustomStyle
{
    public Guid Id { get; init; } = Guid.NewGuid();
    public string Name { get; init; } = "";
    /// <summary>学んだ文章の言語（17 言語のコード。PromptLanguage.Code）</summary>
    public string Language { get; init; } = "";
    /// <summary>文体のルール（1 つ 1 要素）</summary>
    public IReadOnlyList<string> Rules { get; init; } = [];

    /// <summary>言語（17 言語のどれでもなければ null）</summary>
    [JsonIgnore]
    public PromptLanguage? PromptLanguage => Ai.PromptLanguage.FromCode(Language);

    /// <summary>ルールは中身で比べる（読み込み直したものと同じかを見られるように）</summary>
    public bool Equals(CustomStyle? other) =>
        other is not null && Id == other.Id && Name == other.Name && Language == other.Language && Rules.SequenceEqual(other.Rules);

    public override int GetHashCode() => HashCode.Combine(Id, Name, Language, Rules.Count);
}

/// <summary>カスタム文体を保存できない理由</summary>
public enum CustomStyleProblem
{
    EmptyName,
    DuplicateName,
    UnknownLanguage,
    EmptyRules,
    TooManyRules,
    RulesTooLong,
}

// 要件: REQ-DIC-022
// 設計判断: DEC-DIC-213
/// <summary>カスタム文体の名前とルールの検査、編集欄との変換、設定の中での足し・消し（Mac 版の CustomStyle.validate・CustomStyleStore）</summary>
public static class CustomStyleRules
{
    /// <summary>保存できるルールの行数の上限</summary>
    public const int MaxRuleLines = 20;
    /// <summary>保存できるルールの字数（Unicode のスカラー値）の上限</summary>
    public const int MaxRuleCharacters = 2_000;

    /// <summary>編集欄の文字列（1 行に 1 ルール）から、ルールの一覧にする（前後の空白を取り、空行を除く）</summary>
    public static IReadOnlyList<string> FromText(string text) =>
        text.Split(['\n', '\r'], StringSplitOptions.None).Select(l => l.Trim()).Where(l => l.Length > 0).ToList();

    /// <summary>ルールの一覧を編集欄の文字列にする</summary>
    public static string ToText(IEnumerable<string> rules) => string.Join("\n", rules);

    /// <summary>ルールの字数の合計（Unicode のスカラー値。改行は数えない）</summary>
    public static int CharacterCount(IEnumerable<string> rules) => rules.Sum(r => r.EnumerateRunes().Count());

    /// <summary>
    /// 保存できるかを調べる（Mac 版と同じ順に見る）。名前は前後の空白を取り、大文字小文字を区別せず、
    /// ほかのカスタム文体（others。編集しているもの自身は除いて渡す）と組み込みのプリセットの表示名（今の表示の言語）との重複を拒む
    /// </summary>
    public static CustomStyleProblem? Validate(string name, string language, IReadOnlyList<string> rules, IEnumerable<CustomStyle> others)
    {
        var trimmed = name.Trim();
        if (trimmed.Length == 0) return CustomStyleProblem.EmptyName;
        var taken = others.Select(o => o.Name.Trim()).Concat(Enum.GetValues<AppStylePreset>().Select(p => p.Label()));
        if (taken.Any(t => string.Equals(t, trimmed, StringComparison.OrdinalIgnoreCase))) return CustomStyleProblem.DuplicateName;
        if (Ai.PromptLanguage.FromCode(language) is null) return CustomStyleProblem.UnknownLanguage;
        if (rules.Count == 0) return CustomStyleProblem.EmptyRules;
        if (rules.Count > MaxRuleLines) return CustomStyleProblem.TooManyRules;
        if (CharacterCount(rules) > MaxRuleCharacters) return CustomStyleProblem.RulesTooLong;
        return null;
    }

    /// <summary>保存できない理由の文（画面に出す）</summary>
    public static string Message(this CustomStyleProblem problem) => problem switch
    {
        CustomStyleProblem.EmptyName => Strings.CustomStyle_EmptyName,
        CustomStyleProblem.DuplicateName => Strings.CustomStyle_DuplicateName,
        CustomStyleProblem.UnknownLanguage => Strings.CustomStyle_UnknownLanguage,
        CustomStyleProblem.EmptyRules => Strings.CustomStyle_EmptyRules,
        CustomStyleProblem.TooManyRules => string.Format(Strings.CustomStyle_TooManyRules, MaxRuleLines),
        _ => string.Format(Strings.CustomStyle_RulesTooLong, MaxRuleCharacters),
    };

    /// <summary>名前の順（大文字小文字を区別しない）に並べる（プリセットの選択欄・一覧の順）</summary>
    public static IReadOnlyList<CustomStyle> Sorted(IEnumerable<CustomStyle> styles) =>
        styles.OrderBy(s => s.Name, StringComparer.CurrentCultureIgnoreCase).ToList();

    /// <summary>足すか、同じ ID なら置き換える。名前は前後の空白を取って入れる</summary>
    public static void Upsert(AppSettings settings, CustomStyle style)
    {
        style = style with { Name = style.Name.Trim() };
        var list = settings.CustomStyles.ToList();
        var index = list.FindIndex(s => s.Id == style.Id);
        if (index >= 0) list[index] = style;
        else list.Add(style);
        settings.CustomStyles = list;
    }

    /// <summary>そのカスタム文体を使っているアプリの数（消すときの確認に出す）</summary>
    public static int UsageCount(AppSettings settings, Guid id) => settings.EffectiveAppStyles.Count(a => a.CustomStyleId == id);

    // 要件: REQ-DIC-022
    // 設計判断: DEC-DIC-213
    /// <summary>消す。使っていたアプリの割り当ても外す（そのアプリは「なし」。追加ルールは残す）</summary>
    public static void Delete(AppSettings settings, Guid id)
    {
        settings.CustomStyles = settings.CustomStyles.Where(s => s.Id != id).ToList();
        if (settings.AppStyles is { } apps)
        {
            settings.AppStyles = apps.Select(a => a.CustomStyleId == id ? a.WithPreset(AppStylePreset.None) : a).ToList();
        }
    }
}

// 要件: REQ-DIC-020, REQ-DIC-023
// 設計判断: DEC-DIC-216, DEC-DIC-190
/// <summary>前面のアプリの exe の名前から、設定の「アプリ別」の文体を引く（純粋な関数。音声入力と hanasu refine --app が使う）</summary>
public static class AppStyleLookup
{
    /// <summary>ストアアプリはどれもこの exe の中で動くので、見分けられない（引かない）</summary>
    public const string StoreAppHost = "applicationframehost.exe";

    /// <summary>exe の名前をそろえる。パスならファイル名だけ、拡張子がなければ .exe を足し、小文字にする（SharedText.StyleForApp と同じ）</summary>
    public static string NormalizeExe(string exe)
    {
        var trimmed = exe.Trim();
        var name = trimmed[(trimmed.LastIndexOfAny(['\\', '/']) + 1)..];
        var withExe = name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) ? name : name + ".exe";
        return withExe.ToLowerInvariant();
    }

    /// <summary>
    /// その exe のアプリの文体。スイッチがオフ・exe がない・ストアアプリ・一覧にないときは null。
    /// 一覧は設定の AppStyles（未設定なら既定の一覧 AppStyleSetting.Defaults）。割り当てたカスタム文体が見つからなければ「なし」として扱う
    /// </summary>
    public static AppStyle? Find(AppSettings settings, string? exe)
    {
        if (!settings.AppStylesEnabled || string.IsNullOrWhiteSpace(exe)) return null;
        var name = NormalizeExe(exe);
        if (name == StoreAppHost) return null;
        var entry = settings.EffectiveAppStyles.FirstOrDefault(a => a.Exe.Trim().Length > 0 && NormalizeExe(a.Exe) == name);
        return entry?.Resolve(settings.CustomStyles);
    }
}
