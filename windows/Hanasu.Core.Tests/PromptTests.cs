using System.Runtime.CompilerServices;
using System.Text.Json;
using Hanasu.Core.Ai;
using Hanasu.Core.Gemini;
using Hanasu.Core.LocalLlm;
using Hanasu.Core.Meetings;
using Hanasu.Core.Settings;

namespace Hanasu.Core.Tests;

/// <summary>
/// テストのプロンプトの言語を日本語に固定する（既存のテストは日本語の文面を見ているので、設定やマシンの言語に左右されないように）。
/// 言語を変えるテストは PromptLanguageCollection に入れ、ほかのテストと並行に走らせない
/// </summary>
internal static class PromptLanguageFixture
{
    [ModuleInitializer]
    internal static void UseJapanese() => PromptLanguage.Override = PromptLanguage.Ja;

    /// <summary>action の間だけ言語を変える（終わったら日本語に戻す）</summary>
    public static void With(PromptLanguage? language, Action action)
    {
        PromptLanguage.Override = language;
        try
        {
            action();
        }
        finally
        {
            PromptLanguage.Override = PromptLanguage.Ja;
        }
    }
}

[CollectionDefinition(Name, DisableParallelization = true)]
public sealed class PromptLanguageCollection
{
    public const string Name = "PromptLanguage";
}

/// <summary>Mac 版と共有の、言語ごとのプロンプトの JSON（Sources/Hanasu/Resources/Prompts/）</summary>
internal static class SharedCatalog
{
    /// <summary>リポジトリの JSON のフォルダ（リポジトリの外で動かしたときは null）</summary>
    public static string? Directory()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null && !System.IO.Directory.Exists(Path.Combine(dir.FullName, "Sources", "Hanasu", "Resources", "Prompts"))) dir = dir.Parent;
        return dir is null ? null : Path.Combine(dir.FullName, "Sources", "Hanasu", "Resources", "Prompts");
    }

    /// <summary>JSON のキーの文面（配列は改行でつなぐ）</summary>
    public static string? Text(string language, string key)
    {
        if (Directory() is not { } dir) return null;
        using var document = JsonDocument.Parse(File.ReadAllText(Path.Combine(dir, language + ".json")));
        var value = document.RootElement.GetProperty(key);
        return value.ValueKind == JsonValueKind.Array
            ? string.Join("\n", value.EnumerateArray().Select(e => e.GetString()))
            : value.GetString();
    }
}

// 確かめ方: REQ-COM-061
public class PromptCatalogTests
{
    [Fact]
    public void EveryEmbeddedCatalogHasAllKeysOfJapanese()
    {
        // 英語と日本語は必ずある。ほかの言語は、埋め込まれていれば日本語と同じキーがそろっているか
        Assert.True(Prompts.HasCatalog(PromptLanguage.Ja));
        Assert.True(Prompts.HasCatalog(PromptLanguage.En));
        var reference = Prompts.Keys(PromptLanguage.Ja);
        Assert.Contains("refine.system", reference);
        foreach (var language in PromptLanguage.All.Where(Prompts.HasCatalog))
        {
            var missing = reference.Except(Prompts.Keys(language)).ToList();
            Assert.True(missing.Count == 0, $"{language.Code}.json にないキー: {string.Join(", ", missing)}");
        }
    }

    [Fact]
    public void EveryCatalogInTheRepositoryIsEmbedded()
    {
        // リポジトリにある JSON は、どれも埋め込まれていて、対応言語のどれか（csproj のワイルドカードの漏れがないか）
        if (SharedCatalog.Directory() is not { } dir) return;
        foreach (var file in System.IO.Directory.GetFiles(dir, "*.json"))
        {
            var code = Path.GetFileNameWithoutExtension(file);
            var language = PromptLanguage.FromCode(code);
            Assert.True(language is not null, $"対応言語にない JSON: {code}");
            Assert.True(Prompts.HasCatalog(language!), $"埋め込まれていない: {code}");
        }
    }

    [Fact]
    public void WindowsReadsTheSameTextAsTheMacVersion()
    {
        // GeminiPrompts の日本語の整形の指示は、ja.json の refine.system（Mac 版の GeminiClient.systemInstruction と同じキー）そのもの
        Assert.Equal(Prompts.Text("refine.system", PromptLanguage.Ja), GeminiPrompts.BaseSystemInstruction);
        if (SharedCatalog.Text("ja", "refine.system") is not { } mac) return;
        // Windows のランナーは CRLF で取り出すことがあるので、改行をそろえて比べる
        Assert.Equal(mac.ReplaceLineEndings("\n"), GeminiPrompts.BaseSystemInstruction.ReplaceLineEndings("\n"));
        Assert.StartsWith(mac.ReplaceLineEndings("\n") + "\n\n", GeminiPrompts.SystemInstruction().ReplaceLineEndings("\n"));
    }

    [Theory]
    [InlineData("ja-JP", "ja")]
    [InlineData("ja", "ja")]
    [InlineData("en-GB", "en")]
    [InlineData("en_US", "en")]
    [InlineData("zh-Hant-HK", "zh-TW")]
    [InlineData("zh-TW", "zh-TW")]
    [InlineData("zh_HK", "zh-TW")]
    [InlineData("zh-Hans-CN", "zh-CN")]
    [InlineData("zh-SG", "zh-CN")]
    [InlineData("zh", "zh-CN")]
    [InlineData("pt-PT", "pt-BR")]
    [InlineData("pt-BR", "pt-BR")]
    [InlineData("in-ID", "id")]
    [InlineData("ko-KR", "ko")]
    [InlineData("xx", "en")]
    [InlineData("", "en")]
    public void LocaleIdentifierMapsToASupportedLanguage(string identifier, string expected) =>
        Assert.Equal(expected, PromptLanguage.FromLocaleIdentifier(identifier).Code);

    [Fact]
    public void FillReplacesOnceAndKeepsUnknownNames()
    {
        var args = new Dictionary<string, string> { ["a"] = "${b}", ["b"] = "x" };
        Assert.Equal("${b}-x-${c}-${", Prompts.Fill("${a}-${b}-${c}-${", args));
        Assert.Equal("no args", Prompts.Fill("no args", args));
    }

    [Fact]
    public void LanguageNamesAndDatesAreWrittenInThePromptLanguage()
    {
        Assert.Equal("日本語", Prompts.Text("languageName.ja", PromptLanguage.Ja));
        Assert.Equal("Japanese", Prompts.Text("languageName.ja", PromptLanguage.En));
        var date = new DateTime(2026, 11, 13, 9, 5, 0);
        Assert.Equal("11/13 (金)", PromptLanguage.Ja.FormatDate(date, "M/d (E)"));
        Assert.Equal("Nov 13 (Fri)", PromptLanguage.En.FormatDate(date, "MMM d (E)"));
        Assert.Equal("2026/11/13 (Fri) 09:05", PromptLanguage.En.FormatDate(date, "yyyy/MM/dd (E) HH:mm"));
        // 「/」はカルチャの日付の区切りにしない
        Assert.Equal("13/11", PromptLanguage.De.FormatDate(date, "dd/MM"));
        Assert.Equal("13.11. o'clock", PromptLanguage.De.FormatDate(date, "dd.MM. 'o''clock'"));
    }
}

// 確かめ方: REQ-COM-061
[Collection(PromptLanguageCollection.Name)]
public class EnglishPromptTests
{
    [Fact]
    public void SettingsChangeThePromptLanguage()
    {
        // 設定の文字起こしの言語が、プロンプトの言語になる（Override がないとき）
        Assert.Equal(PromptLanguage.Ja, PromptLanguage.Current);
        var path = Path.Combine(Path.GetTempPath(), $"hanasu-prompt-{Guid.NewGuid():N}.json");
        try
        {
            File.WriteAllText(path, """{"localeIdentifier": "en-US"}""");
            var settings = new SettingsService(new SettingsStore(path), new SecretStore(Path.Combine(Path.GetTempPath(), $"hanasu-secrets-{Guid.NewGuid():N}.json"), new FakeDpapi()));
            Assert.Equal(PromptLanguage.Ja, PromptLanguage.Current);  // テストは日本語に固定してある
            PromptLanguageFixture.With(null, () =>
            {
                Assert.Equal(PromptLanguage.En, PromptLanguage.Current);
                settings.Update(s => s.LocaleIdentifier = "zh-Hant-TW");
                Assert.Equal(PromptLanguage.ZhTW, PromptLanguage.Current);
                settings.Update(s => s.LocaleIdentifier = "ja-JP");
                Assert.Equal(PromptLanguage.Ja, PromptLanguage.Current);
            });
        }
        finally
        {
            File.Delete(path);
        }
    }
    [Fact]
    public void RefinePromptsAreInEnglish() => PromptLanguageFixture.With(PromptLanguage.En, () =>
    {
        Assert.Equal(Prompts.Text("refine.system", PromptLanguage.En), GeminiPrompts.BaseSystemInstruction);
        Assert.DoesNotContain("あなたは", GeminiPrompts.SystemInstruction());
        Assert.EndsWith(Prompts.Text("refine.outputLanguage.asSpoken", PromptLanguage.En), GeminiPrompts.SystemInstruction());
        var request = new RefineRequest { Transcript = "hello", Model = "m", AppName = "Slack", Dictionary = ["Hanasu"], ExtraInstructions = "Be brief" };
        var user = GeminiPrompts.UserPrompt(request);
        Assert.Contains("User dictionary: Hanasu", user);
        Assert.Contains("Additional rules:\nBe brief", user);
        Assert.DoesNotContain("入力先アプリ", user);
        Assert.Contains("mainly in English", GeminiPrompts.TranscriptionInstruction);
        Assert.Equal("Transcribe the attached audio.", GeminiPrompts.TranscriptionPrompt([]));
    });

    [Fact]
    public void MinutesPromptsAreInEnglish() => PromptLanguageFixture.With(PromptLanguage.En, () =>
    {
        var instruction = MinutesPrompt.SystemInstruction(MinutesTemplate.Sales, null);
        Assert.StartsWith(Prompts.Text("minutes.intro", PromptLanguage.En), instruction);
        Assert.Contains("## Next actions\n" + MinutesPrompt.Placeholder, instruction);
        Assert.Contains("## Notes on speakers", instruction);
        Assert.DoesNotContain("議事録", instruction);
        var meeting = new Meeting
        {
            Title = "Weekly",
            StartedAt = new DateTimeOffset(2026, 11, 3, 5, 30, 0, TimeSpan.Zero),
            Duration = 60,
            Utterances = [new("me", 0, 5, "Hi."), new("spk1", 10, 15, "Hello."), new("room2", 20, 21, "Yes.")],
        };
        var user = MinutesPrompt.UserText(meeting);
        Assert.Contains("Meeting: Weekly", user);
        Assert.Contains("[00:00] Me: Hi.", user);
        Assert.Contains("[00:10] Speaker 1: Hello.", user);
        Assert.Contains("[00:20] Room 2: Yes.", user);
        Assert.Contains("mainly in English", GeminiSegmentTranscriber.Instruction("en-US"));
        Assert.Contains("(The rest was omitted", LongInputFitter.OmittedNote);

        // 応答の読み取り: 英語の見出し・担当・期限と「None」
        var result = MinutesPrompt.Parse("## Summary\nx\n## Next actions\n{{ACTION_ITEMS}}\n<action_items>\n[{\"owner\": \"Speaker 1\", \"task\": \"Send the quote\", \"due\": \"2026-11-14\"}]\n</action_items>", "Weekly");
        Assert.StartsWith("# Weekly — Minutes\n", result.Markdown);
        Assert.Contains("- [ ] Send the quote (Owner: Speaker 1 / Due: Nov 14 (Sat))", result.Markdown);
        Assert.Contains("None", MinutesPrompt.Parse("## Action items\n{{ACTION_ITEMS}}\n<action_items>[]</action_items>", "x").Markdown);
    });

    [Fact]
    public void SpeakerLabelsOfEveryLanguageAreNotNames() => PromptLanguageFixture.With(PromptLanguage.En, () =>
    {
        Assert.True(SpeakerNameInference.IsPlaceholder("Speaker 1"));
        Assert.True(SpeakerNameInference.IsPlaceholder("room 12"));
        Assert.True(SpeakerNameInference.IsPlaceholder("Me"));
        Assert.True(SpeakerNameInference.IsPlaceholder("None"));
        Assert.True(SpeakerNameInference.IsPlaceholder("話者1"));
        Assert.False(SpeakerNameInference.IsPlaceholder("Tanaka"));
        // 英語のラベルで名前を返したときも、話者に当てはめる
        var meeting = new Meeting { Utterances = [new("me", 0, 1, "a"), new("spk1", 2, 3, "b")] };
        var minutes = MinutesPrompt.Parse("## Summary\nSpeaker 1 said b.\n<action_items>[]</action_items>\n<speaker_names>{\"Speaker 1\": \"Tanaka\"}</speaker_names>", "t");
        meeting.ApplyMinutes(minutes);
        Assert.Equal("Tanaka", meeting.SpeakerNames["spk1"]);
        Assert.Contains("Tanaka said b.", meeting.Minutes);
    });

    [Fact]
    public void MarkdownOfAnyLanguageIsParsed()
    {
        // 議事録はそのときのプロンプトの言語なので、日本語の設定でも英語の議事録を読める（逆も）
        var items = ActionItem.ParseFromMarkdown("## Action items\n- [ ] Fix the slides (Owner: Me / Due: None)\n- [ ] None\n## 次のアクション\n- [ ] 見積もりを送る（担当: 話者1 / 期限: 来週）");
        Assert.Equal(2, items.Count);
        Assert.Equal(("Fix the slides", "Me", (string?)null), (items[0].Task, items[0].Owner, items[0].DueNote));
        Assert.Equal(("見積もりを送る", "話者1", "来週"), (items[1].Task, items[1].Owner, items[1].DueNote));
    }
}

// 確かめ方: REQ-COM-061
/// <summary>議事録を読むときに、言語ごとのラベルや見出しを取り違えないこと（レビューの指摘）</summary>
[Collection(PromptLanguageCollection.Name)]
public class MinutesLanguageReadingTests
{
    [Fact]
    public void OtherLanguagesLabelsAreRealNames()
    {
        // トルコ語の「自分」は Ben、インドネシア語は Saya。英語の議事録では、どちらも実際の名前として残す
        Assert.Equal("Ben", SpeakerNameInference.CleanName("Ben", PromptLanguage.En));
        Assert.Equal("Saya", SpeakerNameInference.CleanName("Saya", PromptLanguage.En));
        Assert.Null(SpeakerNameInference.CleanName("Me", PromptLanguage.En));
        Assert.Null(SpeakerNameInference.CleanName("Speaker 2", PromptLanguage.En));
        Assert.Null(SpeakerNameInference.CleanName("Ben", PromptLanguage.FromCode("tr")));
        // 前からの日本語のラベルは、どの言語でも名前ではない
        Assert.Null(SpeakerNameInference.CleanName("話者1", PromptLanguage.En));
    }

    [Fact]
    public void ResponseIsReadInTheLanguageOfTheRequest()
    {
        // 作っている間に設定が日本語に変わっても、英語で送った議事録は英語のラベルで読む
        var result = MinutesPrompt.Parse("## Action items\n{{ACTION_ITEMS}}\n<action_items>\n[]\n</action_items>", "Weekly", PromptLanguage.En);
        Assert.Equal(PromptLanguage.En, result.Language);
        Assert.Contains("None", result.Markdown);
        Assert.StartsWith("# Weekly — Minutes", result.Markdown);
    }

    [Fact]
    public void HeadingThatOnlyContainsTheActionHeadingIsNotTheActionSection()
    {
        // ロシア語の「Задачи」（アクションアイテム）を含む「Задачи клиента」（顧客の課題）は、アクションアイテムの節ではない
        var markdown = "## Задачи клиента\n- [ ] не задача\n## Задачи\n- [ ] задача";
        var items = ActionItem.ParseFromMarkdown(markdown);
        Assert.Equal(["задача"], items.Select(i => i.Task));
        // 前からの日本語の見出しは、含まれていればよい
        Assert.Single(ActionItem.ParseFromMarkdown("## アクションアイテム（今週）\n- [ ] 資料を送る"));
    }

    [Fact]
    public void DueDatesWithParenthesesAndSlashesAreRead()
    {
        // 期限の「11/14 (金)」の / と () があっても、担当と期限を読める
        var ja = ActionItem.ParseFromMarkdown("## アクションアイテム\n- [ ] 資料を送る（担当: 田中 / 期限: 11/14 (金)）").Single();
        Assert.Equal(("資料を送る", "田中", "11/14 (金)"), (ja.Task, ja.Owner, ja.DueNote));
        var en = ActionItem.ParseFromMarkdown("## Action items\n- [ ] Send the deck (to the team) (Owner: Tanaka / Due: Nov 14 (Fri))").Single();
        Assert.Equal(("Send the deck (to the team)", "Tanaka", "Nov 14 (Fri)"), (en.Task, en.Owner, en.DueNote));
        // 書いたものを読み戻せる（pt-BR の d/M (E)）
        var line = new ActionItem { Owner = "Silva", Task = "Enviar", Due = "2026-11-14" }.MarkdownLineIn(PromptLanguage.PtBR);
        var back = ActionItem.ParseFromMarkdown("## " + Prompts.Text("minutes.actionHeading", PromptLanguage.PtBR) + "\n" + line).Single();
        Assert.Equal(("Enviar", "Silva"), (back.Task, back.Owner));
        Assert.NotNull(back.DueNote);
    }

    [Fact]
    public void UnsupportedTranscriptionLanguageIsWrittenAsIs()
    {
        // 対応言語にない文字起こしの言語（sv-SE）は、英語と書かずに識別子のまま書く
        Assert.Contains("sv-SE", GeminiSegmentTranscriber.LanguageNote("sv-SE"));
        Assert.Contains("sv-SE", GeminiPrompts.TranscriptionInstructionFor(PromptLanguage.En, "sv-SE"));
        Assert.Contains("日本語", GeminiPrompts.TranscriptionInstructionFor(PromptLanguage.Ja, "ja-JP"));
    }
}
