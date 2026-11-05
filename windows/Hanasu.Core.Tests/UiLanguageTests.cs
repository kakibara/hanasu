using System.Globalization;
using System.Reflection;
using System.Resources;
using System.Runtime.CompilerServices;
using Hanasu.Core.Ai;
using Hanasu.Core.Dictation;
using Hanasu.Core.Meetings;
using Hanasu.Core.Properties;
using Hanasu.Core.Settings;

namespace Hanasu.Core.Tests;

/// <summary>
/// テストの表示の言語（UI のカルチャ）を日本語に固定する。既存のテストは日本語の文言（Strings.ja.resx。多言語化の前と同じ文）を見ているので、
/// マシンの言語（CI は英語）に左右されないようにする。英語などを見るテストは With で、そのテストのスレッドだけ変える
/// </summary>
internal static class UiCultureFixture
{
    [ModuleInitializer]
    internal static void UseJapanese()
    {
        var ja = CultureInfo.GetCultureInfo("ja-JP");
        CultureInfo.DefaultThreadCurrentUICulture = ja;
        CultureInfo.CurrentUICulture = ja;
    }

    /// <summary>action の間だけ、このスレッドの UI のカルチャを変える</summary>
    public static T With<T>(string culture, Func<T> action)
    {
        var before = CultureInfo.CurrentUICulture;
        CultureInfo.CurrentUICulture = CultureInfo.GetCultureInfo(culture);
        try
        {
            return action();
        }
        finally
        {
            CultureInfo.CurrentUICulture = before;
        }
    }
}

// 確かめ方: REQ-COM-060
public class UiLanguageTests
{
    [Theory]
    [InlineData("ja-JP", "ja-JP")]
    [InlineData("ja", "ja")]
    [InlineData("en-US", "en-US")]
    [InlineData("en-GB", "en-GB")]
    [InlineData("de-AT", "de-AT")]
    [InlineData("ko-KR", "ko-KR")]
    [InlineData("zh-CN", "zh-CN")]
    [InlineData("zh-SG", "zh-CN")]
    [InlineData("zh-Hans", "zh-CN")]
    [InlineData("zh-TW", "zh-TW")]
    [InlineData("zh-HK", "zh-TW")]
    [InlineData("zh-MO", "zh-TW")]
    [InlineData("zh-Hant", "zh-TW")]
    [InlineData("pt-PT", "pt-BR")]
    [InlineData("pt-BR", "pt-BR")]
    [InlineData("ar-SA", "ar-SA")]
    [InlineData("hi-IN", "hi-IN")]
    [InlineData("id-ID", "id-ID")]
    [InlineData("sv-SE", "en")]
    [InlineData("nl-NL", "en")]
    [InlineData("", "en")]
    public void SystemCultureResolvesToOneOfTheSupportedLanguages(string system, string expected) =>
        Assert.Equal(expected, UiLanguage.Resolve(CultureInfo.GetCultureInfo(system)).Name);

    [Theory]
    [InlineData("ja-JP", "ja")]
    [InlineData("zh_HK", "zh-TW")]
    [InlineData("pt-PT", "pt-BR")]
    [InlineData("in-ID", "id")]
    [InlineData("sv-SE", null)]
    [InlineData("", null)]
    public void SupportedOrNullDoesNotFallBackToEnglish(string identifier, string? expected) =>
        Assert.Equal(expected, PromptLanguage.SupportedOrNull(identifier)?.Code);

    [Fact]
    public void ResolvedCulturesAreTheSupportedLanguages()
    {
        // 17 言語のどれに寄せても、PromptLanguage の対応言語のどれかになる
        foreach (var language in PromptLanguage.All)
        {
            var resolved = UiLanguage.Resolve(CultureInfo.GetCultureInfo(language.Code));
            Assert.Equal(language, PromptLanguage.SupportedOrNull(resolved.Name));
        }
    }

    // 確かめ方: REQ-COM-060
    /// <summary>16 言語のサテライトがどれも読め、英語に落ちない（地域つきのカルチャから親をたどっても）</summary>
    [Theory]
    [InlineData("ja-JP")]
    [InlineData("zh-CN")]
    [InlineData("zh-TW")]
    [InlineData("zh-HK")]
    [InlineData("ko-KR")]
    [InlineData("es-ES")]
    [InlineData("fr-FR")]
    [InlineData("de-DE")]
    [InlineData("it-IT")]
    [InlineData("pt-BR")]
    [InlineData("ru-RU")]
    [InlineData("tr-TR")]
    [InlineData("vi-VN")]
    [InlineData("id-ID")]
    [InlineData("pl-PL")]
    [InlineData("ar-SA")]
    [InlineData("hi-IN")]
    public void EverySupportedLanguageHasItsOwnText(string culture)
    {
        var text = UiCultureFixture.With(culture, () => Strings.Hud_Recording);
        Assert.False(string.IsNullOrWhiteSpace(text));
        Assert.NotEqual("Recording", text);
    }

    // 確かめ方: REQ-COM-060
    /// <summary>ar-SA の既定の暦（ウンム・アル＝クラー暦）でも、履歴の日の見出しはグレゴリオ暦で書く（Meeting.FormatDate とそろえる）</summary>
    [Fact]
    public void DayLabelUsesGregorianCalendarForArabic()
    {
        var now = new DateTimeOffset(2026, 11, 10, 12, 0, 0, TimeSpan.Zero);
        var label = UiCultureFixture.With("ar-SA", () => DictationHistoryStore.DayLabel(new DateTimeOffset(2026, 11, 2, 12, 0, 0, TimeSpan.Zero), now));
        Assert.DoesNotContain("جمادى", label);
        Assert.Contains("نوفمبر", label);
        // 年が違うときだけ年を付ける（暦がずれると、同じ年でも年が付いてしまう）
        Assert.DoesNotContain("2026", label);
        Assert.DoesNotContain("1448", label);
    }

    [Fact]
    public void NeutralResourcesAreEnglish()
    {
        Assert.Equal("en", typeof(Strings).Assembly.GetCustomAttribute<NeutralResourcesLanguageAttribute>()?.CultureName);
        Assert.Equal("Recording", UiCultureFixture.With("en-US", () => Strings.Hud_Recording));
        // 対応していない言語（訳がまだない言語も）は英語
        Assert.Equal("Recording", UiCultureFixture.With("sv-SE", () => Strings.Hud_Recording));
        Assert.Equal("Recording", UiCultureFixture.With("en", () => Strings.Hud_Recording));
    }

    [Fact]
    public void JapaneseResourcesKeepTheOriginalText()
    {
        Assert.Equal("録音中", UiCultureFixture.With("ja-JP", () => Strings.Hud_Recording));
        Assert.Equal("録音中", UiCultureFixture.With("ja", () => Strings.Hud_Recording));
        Assert.Equal("{0} で整えています…", Strings.ResourceManager.GetString(nameof(Strings.Hud_Refining), CultureInfo.GetCultureInfo("ja")));
    }

    [Theory]
    [InlineData("zh-CN", "zh-Hans")]
    [InlineData("zh-SG", "zh-Hans")]
    [InlineData("zh-TW", "zh-Hant")]
    [InlineData("zh-HK", "zh-Hant")]
    [InlineData("zh-MO", "zh-Hant")]
    public void ChineseCulturesFallBackToTheScriptFolders(string culture, string satellite)
    {
        // 中国語の訳は Strings.zh-Hans.resx・Strings.zh-Hant.resx に置く（scripts/i18n-resx.py）。.NET はカルチャの親をたどってそこを読む
        var chain = new List<string>();
        for (var c = CultureInfo.GetCultureInfo(culture); !string.IsNullOrEmpty(c.Name); c = c.Parent) chain.Add(c.Name);
        Assert.Contains(satellite, chain);
    }

    [Fact]
    public void MessagesFollowTheUiLanguage()
    {
        Assert.Equal("Translated to English and typed", UiCultureFixture.With("en", () => TranslationLanguage.English.DoneMessage()));
        Assert.Equal("英訳して入力しました", UiCultureFixture.With("ja", () => TranslationLanguage.English.DoneMessage()));
        Assert.Equal("Translate and Type",
            UiCultureFixture.With("en", () => TranslationLanguages.MenuTitle([TranslationLanguage.English, TranslationLanguage.Japanese])));
        Assert.Equal("和訳して入力", UiCultureFixture.With("ja", () => TranslationLanguages.MenuTitle([TranslationLanguage.Japanese])));
        Assert.Equal("Gemini credentials aren't set, so the text was typed without refining (menu → Settings → AI).",
            UiCultureFixture.With("en", () => string.Format(Strings.Dictation_NoAi_Refine, TextAiFactory.NotReadyBecause(TextAiProvider.Gemini))));
        Assert.Equal("Gemini の認証情報が未設定のため、整形せずに入力しました（メニュー → 設定 → AI）。",
            UiCultureFixture.With("ja", () => string.Format(Strings.Dictation_NoAi_Refine, TextAiFactory.NotReadyBecause(TextAiProvider.Gemini))));
    }

    [Fact]
    public void DayLabelsUseTheUiLanguage()
    {
        var now = new DateTimeOffset(2026, 11, 4, 12, 0, 0, TimeZoneInfo.Local.GetUtcOffset(new DateTime(2026, 11, 4)));
        Assert.Equal("Yesterday", UiCultureFixture.With("en", () => DictationHistoryStore.DayLabel(now.AddDays(-1), now)));
        Assert.Equal("Mon, Nov 2", UiCultureFixture.With("en-US", () => DictationHistoryStore.DayLabel(now.AddDays(-2), now)));
        Assert.Equal("Tue, Nov 4, 2025", UiCultureFixture.With("en-US", () => DictationHistoryStore.DayLabel(now.AddYears(-1), now)));
    }

    [Fact]
    public void MeetingLabelsUseTheUiLanguage()
    {
        var meeting = new Meeting();
        Assert.Equal("Me", UiCultureFixture.With("en", () => meeting.DisplayName("me")));
        Assert.Equal("Speaker 2", UiCultureFixture.With("en", () => meeting.DisplayName("spk2")));
        Assert.Equal("話者2", UiCultureFixture.With("ja", () => meeting.DisplayName("spk2")));
        var date = new DateTimeOffset(2026, 11, 3, 14, 30, 0, TimeZoneInfo.Local.GetUtcOffset(new DateTime(2026, 11, 3)));
        Assert.Equal("2026/11/03 (Tue) 14:30", UiCultureFixture.With("en", () => Meeting.FormatDate(date)));
        Assert.Equal("2026/11/03 (火) 14:30", UiCultureFixture.With("ja", () => Meeting.FormatDate(date)));
    }

    [Theory]
    [InlineData("議事録を作れませんでした: 429", true)]
    [InlineData("Couldn't create the minutes: 429", true)]
    [InlineData("Gemini の認証情報が未設定のため、議事録は作っていません（メニュー → 設定 → AI）。", true)]
    [InlineData("Claude credentials aren't set, so no minutes were created (menu → Settings → AI).", true)]
    [InlineData("相手側の話者を分けられませんでした", false)]
    [InlineData("", false)]
    public void MinutesErrorsAreRecognizedInJapaneseAndEnglish(string message, bool expected) =>
        Assert.Equal(expected, UiCultureFixture.With("en", () => MeetingController.IsMinutesError(message)));

    /// <summary>議事録を作り直せたら、議事録のエラーの行だけを消し、文字起こしの失敗などほかの行は残す</summary>
    [Fact]
    public void OnlyMinutesErrorLinesAreRemoved()
    {
        var joined = "自分の音声を文字起こしできませんでした: x\n音声ファイルは残しています。\nGemini の認証情報が未設定のため、議事録は作っていません（メニュー → 設定 → AI）。";
        Assert.Equal("自分の音声を文字起こしできませんでした: x\n音声ファイルは残しています。", MeetingController.WithoutMinutesErrors(joined));
        Assert.Null(MeetingController.WithoutMinutesErrors("議事録を作れませんでした: 429"));
        Assert.Null(MeetingController.WithoutMinutesErrors(null));
    }
}

// 確かめ方: REQ-COM-004
public class TranscriptionLocaleTests
{
    [Theory]
    [InlineData("ja-JP", "ja-JP")]
    [InlineData("ja", "ja-JP")]
    [InlineData("en-US", "en-US")]
    [InlineData("en-GB", "en-GB")]
    [InlineData("en-JP", "en-US")]
    [InlineData("en-AU", "en-US")]
    [InlineData("zh-Hans-CN", "zh-CN")]
    [InlineData("zh-SG", "zh-CN")]
    [InlineData("zh-Hant-TW", "zh-TW")]
    [InlineData("zh-HK", "zh-TW")]
    [InlineData("ko-KR", "ko-KR")]
    [InlineData("fr-CA", "fr-FR")]
    [InlineData("de-AT", "de-DE")]
    [InlineData("es-MX", "es-ES")]
    [InlineData("it-IT", "it-IT")]
    [InlineData("pt-PT", "pt-BR")]
    [InlineData("sv-SE", "sv-SE")]
    [InlineData("ru-RU", "ru-RU")]
    [InlineData("", "ja-JP")]
    public void NearestTranscriptionLocale(string identifier, string expected) =>
        Assert.Equal(expected, TranscriptionLocales.Nearest(identifier));

    [Theory]
    [InlineData("en-US", "en-US")]
    [InlineData("de-CH", "de-DE")]
    [InlineData("ja-JP", "ja-JP")]
    [InlineData("", "en-US")]
    public void SystemDefaultFollowsTheDisplayLanguage(string system, string expected) =>
        Assert.Equal(expected, TranscriptionLocales.SystemDefaultFor(system));

    [Fact]
    public void NewSettingsFollowTheSystemLanguage()
    {
        var store = new SettingsStore(Path.Combine(TestKeys.TempDirectory(), "settings.json"), () => "en-US");
        Assert.Equal("en-US", store.Load().LocaleIdentifier);
    }

    [Fact]
    public void SavedSettingsKeepTheirLanguage()
    {
        var path = Path.Combine(TestKeys.TempDirectory(), "settings.json");
        new SettingsStore(path, () => "ja-JP").Save(new AppSettings { LocaleIdentifier = "ja-JP" });
        // システムの言語が英語になっても、保存してある言語は変えない
        Assert.Equal("ja-JP", new SettingsStore(path, () => "en-US").Load().LocaleIdentifier);
        // 前の版の設定に言語の項目がなければ、前の版の既定の ja-JP
        File.WriteAllText(path, "{ \"model\": \"gemini-3.5-flash-lite\" }");
        Assert.Equal("ja-JP", new SettingsStore(path, () => "en-US").Load().LocaleIdentifier);
    }
}
