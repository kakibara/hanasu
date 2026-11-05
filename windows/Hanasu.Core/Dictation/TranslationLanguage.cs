using System.Text.Json;
using System.Text.Json.Serialization;

namespace Hanasu.Core.Dictation;

// 要件: REQ-DIC-013
// 設計判断: DEC-DIC-027
/// <summary>翻訳して入力するときの言語（Mac 版の TranslationLanguage と同じ）。並び（TranslationLanguages.All）は HUD・メニュー・設定に出す順</summary>
public enum TranslationLanguage { English, Japanese }

public static class TranslationLanguages
{
    /// <summary>すべての翻訳の言語（English → 日本語）</summary>
    public static IReadOnlyList<TranslationLanguage> All { get; } = [TranslationLanguage.English, TranslationLanguage.Japanese];

    /// <summary>HUD の切り替えに出す名前（その言語での言語名なので、表示の言語によらない）</summary>
    public static string Label(this TranslationLanguage language) => language switch
    {
        TranslationLanguage.Japanese => "日本語",
        _ => "English",
    };

    /// <summary>設定のチェックボックスに出す名前</summary>
    public static string SettingsLabel(this TranslationLanguage language) => language switch
    {
        TranslationLanguage.Japanese => Strings.TranslationLanguage_Japanese,
        _ => Strings.TranslationLanguage_English,
    };

    /// <summary>「英訳」「和訳」（履歴のモードの名前）</summary>
    public static string Verb(this TranslationLanguage language) => language switch
    {
        TranslationLanguage.Japanese => Strings.Translation_ToJapanese,
        _ => Strings.Translation_ToEnglish,
    };

    /// <summary>この言語に翻訳して入力したときの HUD の知らせ（「英訳して入力しました」）</summary>
    public static string DoneMessage(this TranslationLanguage language) => language switch
    {
        TranslationLanguage.Japanese => Strings.Hud_TranslatedToJapanese,
        _ => Strings.Hud_TranslatedToEnglish,
    };

    /// <summary>この言語に翻訳して入力するモード</summary>
    public static DictationMode ToMode(this TranslationLanguage language) => language switch
    {
        TranslationLanguage.Japanese => DictationMode.TranslateToJapanese,
        _ => DictationMode.TranslateToEnglish,
    };

    /// <summary>モードの翻訳の言語（整形なら null）</summary>
    public static TranslationLanguage? Translation(this DictationMode mode) => mode switch
    {
        DictationMode.TranslateToEnglish => TranslationLanguage.English,
        DictationMode.TranslateToJapanese => TranslationLanguage.Japanese,
        _ => null,
    };

    /// <summary>設定の並びにそろえ、重複・知らない値・空を直す（空なら English だけ）</summary>
    public static TranslationLanguage[] Normalize(IEnumerable<TranslationLanguage>? languages)
    {
        var set = languages?.ToHashSet() ?? [];
        var picked = All.Where(set.Contains).ToArray();
        return picked.Length == 0 ? [TranslationLanguage.English] : picked;
    }

    /// <summary>メニューの項目名。選んだ言語が 1 つなら「英訳して入力」「和訳して入力」、2 つ以上なら「翻訳して入力」</summary>
    public static string MenuTitle(IReadOnlyList<TranslationLanguage> languages) =>
        languages.Count != 1 ? Strings.Translation_MenuTitle
        : languages[0] == TranslationLanguage.Japanese ? Strings.Translation_MenuTitle_Japanese
        : Strings.Translation_MenuTitle_English;
}

/// <summary>
/// settings.json の TranslationLanguages を読み書きする。知らない値は捨てる（設定のファイル全体を読めなくしない）。DEC-DIC-027
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
                && Enum.TryParse<TranslationLanguage>(reader.GetString(), ignoreCase: true, out var language)
                && Enum.IsDefined(language))
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
        foreach (var language in value) writer.WriteStringValue(language.ToString());
        writer.WriteEndArray();
    }
}
