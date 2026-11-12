using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;
using Hanasu.Core.Ai;
using Hanasu.Core.Settings;

namespace Hanasu.Core.Dictation;

// 要件: REQ-DIC-013
// 設計判断: DEC-DIC-027, DEC-DIC-150
/// <summary>
/// 翻訳して入力するときの言語（Mac 版の TranslationLanguage と同じ）。対応言語（PromptLanguage.All。17 言語）のどれか。
/// 言語の一覧は PromptLanguage.All だけに書く（ここに別の一覧を持たない。言語を足せば翻訳の言語にも出る）。
/// default は English として扱う
/// </summary>
public readonly record struct TranslationLanguage
{
    private readonly PromptLanguage? language;

    private TranslationLanguage(PromptLanguage language) => this.language = language;

    public static TranslationLanguage English { get; } = new(PromptLanguage.En);
    public static TranslationLanguage Japanese { get; } = new(PromptLanguage.Ja);

    /// <summary>対応言語から</summary>
    public static TranslationLanguage Of(PromptLanguage language) => new(language);

    /// <summary>対応言語（プロンプトの JSON の言語と同じもの）</summary>
    public PromptLanguage Language => language ?? PromptLanguage.En;

    /// <summary>"en"、"zh-CN" など</summary>
    public string Code => Language.Code;

    public bool Equals(TranslationLanguage other) => Language == other.Language;

    public override int GetHashCode() => Language.GetHashCode();

    public override string ToString() => Code;

    /// <summary>
    /// settings.json に書く値。English と Japanese は今までの値（"English"・"Japanese"）のまま、ほかの言語は言語のコード（"zh-CN"、"ko" など）。DEC-DIC-027
    /// </summary>
    public string StoredValue => this == English ? "English" : this == Japanese ? "Japanese" : Code;

    /// <summary>
    /// settings.json の値・CLI の引数から。"English"・"Japanese"（今までの値）と言語のコード（"en"、"zh-CN" など）を、大文字と小文字を区別せずに読む。知らない値は null
    /// </summary>
    public static TranslationLanguage? FromStoredValue(string? value)
    {
        var trimmed = value?.Trim();
        if (string.Equals(trimmed, "English", StringComparison.OrdinalIgnoreCase)) return English;
        if (string.Equals(trimmed, "Japanese", StringComparison.OrdinalIgnoreCase)) return Japanese;
        return PromptLanguage.FromCode(trimmed) is { } language ? Of(language) : null;
    }

    // 設計判断: DEC-DIC-022, DEC-DIC-028
    /// <summary>訳した結果が日本語か（Mac 版の TranslationLanguage.outputsJapanese と同じ）</summary>
    public bool OutputsJapanese => this == Japanese;

    // 設計判断: DEC-DIC-023, DEC-DIC-028
    /// <summary>
    /// 共通の追加ルールを使うか。追加ルールは話す人の言語の文体向けに書くもの（日本語の利用者なら日本語）なので、
    /// 和訳で、しかもプロンプトの言語が日本語のときだけ使う（韓国語で話す人の追加ルールを、日本語の出力には付けない）。
    /// Mac 版の TranslationLanguage.keepsExtraRules と同じ決まり（両方を直す）
    /// </summary>
    public bool KeepsExtraRules => OutputsJapanese && PromptLanguage.Current == PromptLanguage.Ja;

    // 設計判断: DEC-DIC-150
    /// <summary>この言語の名前を、言語 in で書いたもの（プロンプトの JSON の languageName.&lt;コード&gt;）</summary>
    public string NameIn(PromptLanguage @in) => Prompts.Text("languageName." + Code, @in);
}

// 設計判断: DEC-DIC-150
public static class TranslationLanguages
{
    /// <summary>すべての翻訳の言語。並びは PromptLanguage.All と同じ（English → 日本語 → …）で、HUD・メニュー・設定に出す順</summary>
    public static IReadOnlyList<TranslationLanguage> All { get; } = PromptLanguage.All.Select(TranslationLanguage.Of).ToArray();

    /// <summary>HUD の切り替えに出す名前。その言語で書いた言語名（"English"、"日本語"、"Español"）なので、表示の言語によらない</summary>
    public static string Label(this TranslationLanguage language) =>
        CapitalizeFirst(language.NameIn(language.Language), language.Language.Culture);

    /// <summary>この言語の名前を、表示の言語で書いたもの（"韓国語"、"Korean"）。文の中に埋めるので、先頭を大文字にしない</summary>
    public static string NameInUiLanguage(this TranslationLanguage language) => language.NameIn(UiLanguage.PromptLanguage);

    /// <summary>設定のチェックボックスに出す名前。その言語での名前に、表示の言語での名前が違えば括弧で添える（"English（英語）"、"日本語"）</summary>
    public static string SettingsLabel(this TranslationLanguage language)
    {
        var label = language.Label();
        var name = language.NameInUiLanguage();
        return string.Compare(label, name, CultureInfo.CurrentUICulture, CompareOptions.IgnoreCase) == 0
            ? label
            : string.Format(Strings.TranslationLanguage_WithName, label, name);
    }

    /// <summary>「英訳」「和訳」「韓国語訳」（履歴のモードの名前）</summary>
    public static string Verb(this TranslationLanguage language) =>
        language == TranslationLanguage.English ? Strings.Translation_ToEnglish
        : language == TranslationLanguage.Japanese ? Strings.Translation_ToJapanese
        : string.Format(Strings.Translation_ToOther, language.NameInUiLanguage());

    /// <summary>この言語に翻訳して入力したときの HUD の知らせ（「英訳して入力しました」）</summary>
    public static string DoneMessage(this TranslationLanguage language) =>
        language == TranslationLanguage.English ? Strings.Hud_TranslatedToEnglish
        : language == TranslationLanguage.Japanese ? Strings.Hud_TranslatedToJapanese
        : string.Format(Strings.Hud_TranslatedToOther, language.NameInUiLanguage());

    /// <summary>この言語に翻訳して入力するモード</summary>
    public static DictationMode ToMode(this TranslationLanguage language) => DictationMode.Translate(language);

    /// <summary>設定の並びにそろえ、重複・知らない値・空を直す（空なら English だけ）</summary>
    public static TranslationLanguage[] Normalize(IEnumerable<TranslationLanguage>? languages)
    {
        var set = languages?.ToHashSet() ?? [];
        var picked = All.Where(set.Contains).ToArray();
        return picked.Length == 0 ? [TranslationLanguage.English] : picked;
    }

    /// <summary>メニューの項目名。選んだ言語が 1 つなら「英訳して入力」「和訳して入力」「韓国語訳して入力」、2 つ以上なら「翻訳して入力」</summary>
    public static string MenuTitle(IReadOnlyList<TranslationLanguage> languages) =>
        languages.Count != 1 ? Strings.Translation_MenuTitle
        : languages[0] == TranslationLanguage.English ? Strings.Translation_MenuTitle_English
        : languages[0] == TranslationLanguage.Japanese ? Strings.Translation_MenuTitle_Japanese
        : string.Format(Strings.Translation_MenuTitle_Other, languages[0].NameInUiLanguage());

    /// <summary>先頭の 1 文字を、その言語の決まりで大文字にする（"español" → "Español"、"tiếng Việt" → "Tiếng Việt"）</summary>
    private static string CapitalizeFirst(string text, CultureInfo culture) =>
        text.Length == 0 ? text : culture.TextInfo.ToUpper(text[0]) + text[1..];
}

/// <summary>
/// settings.json の TranslationLanguages を読み書きする。English・Japanese は今までの値のまま、ほかの言語はコードで書く。
/// 知らない値は捨てる（設定のファイル全体を読めなくしない）。DEC-DIC-027
/// </summary>
public sealed class TranslationLanguagesJsonConverter : JsonConverter<TranslationLanguage[]>
{
    public override TranslationLanguage[] Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        var values = new List<TranslationLanguage>();
        if (reader.TokenType != JsonTokenType.StartArray)
        {
            reader.Skip();
            return [];
        }
        while (reader.Read() && reader.TokenType != JsonTokenType.EndArray)
        {
            if (reader.TokenType == JsonTokenType.String
                && TranslationLanguage.FromStoredValue(reader.GetString()) is { } language)
            {
                values.Add(language);
            }
            else
            {
                reader.Skip();
            }
        }
        return values.ToArray();
    }

    public override void Write(Utf8JsonWriter writer, TranslationLanguage[] value, JsonSerializerOptions options)
    {
        writer.WriteStartArray();
        foreach (var language in value) writer.WriteStringValue(language.StoredValue);
        writer.WriteEndArray();
    }
}
