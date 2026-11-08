using System.Text.Json;
using Hanasu.Core.Ai;
using Hanasu.Core.Dictation;
using Hanasu.Core.Gemini;
using Hanasu.Core.Settings;

namespace Hanasu.Core.Tests;

// 確かめ方: REQ-DIC-013
/// <summary>翻訳の言語を 17 言語に広げたところ（DEC-DIC-027・DEC-DIC-029・DEC-DIC-150〜152）</summary>
public class TranslationLanguageTests
{
    private static readonly TranslationLanguage Korean = TranslationLanguage.Of(PromptLanguage.Ko);
    private static readonly TranslationLanguage Spanish = TranslationLanguage.Of(PromptLanguage.Es);

    // 設計判断: DEC-DIC-150
    [Fact]
    public void AllFollowsPromptLanguageOrder()
    {
        Assert.Equal(PromptLanguage.All, TranslationLanguages.All.Select(l => l.Language));
        Assert.Equal(TranslationLanguage.English, TranslationLanguages.All[0]);
        Assert.Equal(TranslationLanguage.Japanese, TranslationLanguages.All[1]);
        // default は English として扱う
        Assert.Equal(TranslationLanguage.English, default(TranslationLanguage));
        // 並びは All の順にそろう
        Assert.Equal([TranslationLanguage.English, TranslationLanguage.Japanese, Korean, Spanish],
            TranslationLanguages.Normalize([Spanish, Korean, TranslationLanguage.Japanese, TranslationLanguage.English, Korean]));
    }

    // 設計判断: DEC-DIC-027
    [Fact]
    public void SettingsKeepOldValuesAndStoreOtherLanguagesByCode()
    {
        var path = Path.Combine(TestKeys.TempDirectory(), "settings.json");
        var store = new SettingsStore(path);
        // 今までの値（English・Japanese）と新しい言語のコード、知らない値
        File.WriteAllText(path, "{ \"translationLanguages\": [\"ko\", \"Japanese\", \"Klingon\", \"English\", \"zh-cn\"] }");
        var loaded = store.Load();
        Assert.Equal([TranslationLanguage.English, TranslationLanguage.Japanese, TranslationLanguage.Of(PromptLanguage.ZhCN), Korean],
            loaded.TranslationLanguages);

        store.Save(loaded);
        var json = File.ReadAllText(path);
        using var document = JsonDocument.Parse(json);
        var stored = document.RootElement.GetProperty("translationLanguages").EnumerateArray().Select(e => e.GetString()!).ToArray();
        Assert.Equal(["English", "Japanese", "zh-CN", "ko"], stored);
        Assert.Equal(loaded.TranslationLanguages, store.Load().TranslationLanguages);

        // 新しい言語だけを選んだときは、それが「翻訳して入力」の言語
        File.WriteAllText(path, "{ \"translationLanguages\": [\"ko\"] }");
        Assert.Equal(Korean, store.Load().PrimaryTranslationLanguage);
    }

    [Fact]
    public void StoredValuesAndCliCodesAreReadCaseInsensitively()
    {
        Assert.Equal(TranslationLanguage.English, TranslationLanguage.FromStoredValue("english"));
        Assert.Equal(TranslationLanguage.English, TranslationLanguage.FromStoredValue("EN"));
        Assert.Equal(TranslationLanguage.Japanese, TranslationLanguage.FromStoredValue("Japanese"));
        Assert.Equal(TranslationLanguage.Japanese, TranslationLanguage.FromStoredValue("ja"));
        Assert.Equal(TranslationLanguage.Of(PromptLanguage.PtBR), TranslationLanguage.FromStoredValue("PT-br"));
        Assert.Null(TranslationLanguage.FromStoredValue("sv"));
        Assert.Null(TranslationLanguage.FromStoredValue(""));
        Assert.Null(TranslationLanguage.FromStoredValue(null));
        Assert.Equal("English", TranslationLanguage.English.StoredValue);
        Assert.Equal("Japanese", TranslationLanguage.Japanese.StoredValue);
        Assert.Equal("ko", Korean.StoredValue);
    }

    // 設計判断: DEC-DIC-029
    [Fact]
    public void HistoryModesKeepOldValuesAndStoreOtherLanguagesWithPrefix()
    {
        var dir = TestKeys.TempDirectory();
        var store = new DictationHistoryStore(dir, () => new DateTimeOffset(2026, 11, 4, 12, 0, 0, TimeSpan.Zero));
        store.Record("a", "A", DictationMode.Refine, ProcessStatus.Succeeded, date: new DateTimeOffset(2026, 11, 4, 11, 0, 0, TimeSpan.Zero));
        store.Record("b", "B", DictationMode.TranslateToEnglish, ProcessStatus.Succeeded, date: new DateTimeOffset(2026, 11, 4, 11, 1, 0, TimeSpan.Zero));
        store.Record("c", "C", DictationMode.TranslateToJapanese, ProcessStatus.Succeeded, date: new DateTimeOffset(2026, 11, 4, 11, 2, 0, TimeSpan.Zero));
        store.Record("d", "D", DictationMode.Translate(Korean), ProcessStatus.Succeeded, date: new DateTimeOffset(2026, 11, 4, 11, 3, 0, TimeSpan.Zero));
        var path = Path.Combine(dir, "history.json");
        using (var document = JsonDocument.Parse(File.ReadAllText(path)))
        {
            var modes = document.RootElement.GetProperty("entries").EnumerateArray().Select(e => e.GetProperty("mode").GetString()!).ToArray();
            Assert.Equal(["translate:ko", "translateJapanese", "translate", "refine"], modes);
        }
        var reloaded = new DictationHistoryStore(dir, () => new DateTimeOffset(2026, 11, 4, 12, 0, 0, TimeSpan.Zero));
        reloaded.Load();
        Assert.Equal([HistoryMode.Of(Korean), HistoryMode.TranslateJapanese, HistoryMode.Translate, HistoryMode.Refine],
            reloaded.Entries.Select(e => e.Mode));
        Assert.Equal(Korean, reloaded.Entries[0].Mode.Translation);
        Assert.Equal("韓国語訳", DictationHistoryEntry.ModeLabel(reloaded.Entries[0].Mode));
        Assert.Equal("To Korean", UiCultureFixture.With("en", () => DictationHistoryEntry.ModeLabel(reloaded.Entries[0].Mode)));
    }

    // 設計判断: DEC-DIC-029
    [Fact]
    public void UnknownHistoryModesDoNotBreakLoading()
    {
        var dir = TestKeys.TempDirectory();
        File.WriteAllText(Path.Combine(dir, "history.json"), """
            {
              "entries": [
                { "id": "A", "date": "2026-11-04T11:03:00Z", "raw": "r", "output": "o", "mode": "summarize", "status": "succeeded" },
                { "id": "B", "date": "2026-11-04T11:02:00Z", "raw": "r", "output": "o", "mode": "translate:xx", "status": "succeeded" },
                { "id": "C", "date": "2026-11-04T11:01:00Z", "raw": "r", "output": "o", "mode": "Translate", "status": "succeeded" },
                { "id": "D", "date": "2026-11-04T11:00:00Z", "raw": "r", "output": "o", "mode": 2, "status": "succeeded" }
              ],
              "version": 1
            }
            """);
        var store = new DictationHistoryStore(dir, () => new DateTimeOffset(2026, 11, 4, 12, 0, 0, TimeSpan.Zero));
        store.Load();
        Assert.Null(store.LastError);
        Assert.Equal(4, store.Entries.Count);
        // 知らない値は、そのまま持って書き戻す（翻訳の言語はない）
        Assert.Equal("summarize", store.Entries[0].Mode.Value);
        Assert.Null(store.Entries[0].Mode.Translation);
        Assert.Equal("translate:xx", store.Entries[1].Mode.Value);
        Assert.Null(store.Entries[1].Mode.Translation);
        Assert.Equal(HistoryMode.Translate, store.Entries[2].Mode);
        Assert.Equal(HistoryMode.TranslateJapanese, store.Entries[3].Mode);
    }

    [Fact]
    public void DictationModeDefaultIsRefine()
    {
        Assert.Equal(DictationMode.Refine, default(DictationMode));
        Assert.Null(DictationMode.Refine.Translation);
        Assert.Equal(TranslationLanguage.English, DictationMode.TranslateToEnglish.Translation);
        Assert.Equal(DictationMode.TranslateToJapanese, TranslationLanguage.Japanese.ToMode());
        Assert.Equal(Korean, Korean.ToMode().Translation);
        Assert.NotEqual(DictationMode.TranslateToEnglish, Korean.ToMode());
    }

    // 設計判断: DEC-DIC-151
    [Fact]
    public void OtherLanguagesUseTheGenericPromptAndDropExtraRules()
    {
        var request = new RefineRequest { Transcript = "テスト", Model = "m", ExtraInstructions = "です・ます調に統一" };
        // プロンプトの言語（テストでは日本語）で書いた言語の名前を埋める
        var instruction = GeminiPrompts.TranslationSystemInstruction(Korean);
        Assert.Equal(Prompts.Text("translate.other.system", PromptLanguage.Ja, ("language", "韓国語")), instruction);
        Assert.Contains("韓国語", instruction);
        Assert.DoesNotContain("${language}", instruction);
        Assert.NotEqual(GeminiPrompts.TranslationInstruction, instruction);
        Assert.NotEqual(GeminiPrompts.JapaneseTranslationInstruction, instruction);
        // 追加ルールは日本語の文体向けなので、整形と和訳だけで使う
        Assert.Equal("<transcript>\nテスト\n</transcript>", GeminiPrompts.UserPrompt(request, Korean));
        Assert.Contains("追加ルール", GeminiPrompts.UserPrompt(request, TranslationLanguage.Japanese));
        Assert.Contains("追加ルール", GeminiPrompts.UserPrompt(request));
    }

    // 設計判断: DEC-DIC-150
    [Fact]
    public void LabelsUseTheLanguageItselfAndTheUiLanguage()
    {
        // HUD の名前はその言語で書き、先頭を大文字にする
        Assert.Equal("English", TranslationLanguage.English.Label());
        Assert.Equal("日本語", TranslationLanguage.Japanese.Label());
        Assert.Equal("한국어", Korean.Label());
        Assert.Equal("Español", Spanish.Label());
        // 設定は、表示の言語での名前が違えば括弧で添える
        Assert.Equal("English（英語）", TranslationLanguage.English.SettingsLabel());
        Assert.Equal("日本語", TranslationLanguage.Japanese.SettingsLabel());
        Assert.Equal("한국어（韓国語）", Korean.SettingsLabel());
        Assert.Equal("English", UiCultureFixture.With("en", () => TranslationLanguage.English.SettingsLabel()));
        Assert.Equal("Español", UiCultureFixture.With("es", () => Spanish.SettingsLabel()));
        Assert.Equal("한국어 (Korean)", UiCultureFixture.With("en", () => Korean.SettingsLabel()));
        // 文の中では、表示の言語での名前を埋める（英語と日本語は今までの文言のまま）
        Assert.Equal("英訳", TranslationLanguage.English.Verb());
        Assert.Equal("韓国語訳", Korean.Verb());
        Assert.Equal("韓国語訳して入力しました", Korean.DoneMessage());
        Assert.Equal("Translated to Korean and typed", UiCultureFixture.With("en", () => Korean.DoneMessage()));
        Assert.Equal("韓国語訳して入力", TranslationLanguages.MenuTitle([Korean]));
        Assert.Equal("翻訳して入力", TranslationLanguages.MenuTitle([TranslationLanguage.English, Korean]));
        Assert.Equal("Gemini で韓国語に翻訳しています…", HudText.ProcessingTitle(Korean));
        Assert.Equal("Translating into Korean with Claude…", UiCultureFixture.With("en", () => HudText.ProcessingTitle(Korean, "Claude")));
    }

    // 設計判断: DEC-DIC-152
    [Fact]
    public void HudShowsTwoLanguageButtonsAndAnOverflowFromThreeLanguages()
    {
        var two = new[] { TranslationLanguage.English, TranslationLanguage.Japanese };
        AssertButtons(two, false, HudText.LanguageButtons(null, two));

        var many = new[] { TranslationLanguage.English, TranslationLanguage.Japanese, Korean, Spanish };
        // 話した言語・先頭の 2 つを選んでいるときは、先頭の 2 つ
        AssertButtons(two, true, HudText.LanguageButtons(null, many));
        AssertButtons(two, true, HudText.LanguageButtons(TranslationLanguage.Japanese, many));
        // 後ろの言語を選んでいるときも、それを出す（並びは choices の順）
        AssertButtons([TranslationLanguage.English, Spanish], true, HudText.LanguageButtons(Spanish, many));
        AssertButtons([TranslationLanguage.English, Korean], true,
            HudText.LanguageButtons(Korean, new[] { TranslationLanguage.English, TranslationLanguage.Japanese, Korean }));
    }

    private static void AssertButtons(TranslationLanguage[] buttons, bool overflow, (IReadOnlyList<TranslationLanguage> Buttons, bool Overflow) actual)
    {
        Assert.Equal(buttons, actual.Buttons);
        Assert.Equal(overflow, actual.Overflow);
    }
}
