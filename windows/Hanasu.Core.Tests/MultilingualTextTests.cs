using Hanasu.Core.Ai;
using Hanasu.Core.Dictation;
using Hanasu.Core.Gemini;
using Hanasu.Core.Meetings;
using Hanasu.Core.Settings;
using Hanasu.Core.Text;
using Hanasu.Whisper;

namespace Hanasu.Core.Tests;

/// <summary>
/// 日本語・英語を前提にしていたところを、17 言語で正しく動くように直した分（日本語の結果は変えない）。
/// プロンプトの言語を変えるテストがあるので PromptLanguageCollection に入れる
/// </summary>
[Collection(PromptLanguageCollection.Name)]
public class MultilingualTextTests
{
    // 設計判断: DEC-COM-174
    [Theory]
    [InlineData("Hello", "world", "Hello world")]
    [InlineData("今日は", "晴れです", "今日は晴れです")]
    [InlineData("Gemini", "の話", "Geminiの話")]
    [InlineData("検索", "API", "検索API")]
    [InlineData("안녕하세요", "반갑습니다", "안녕하세요 반갑습니다")]
    [InlineData("Hello ", "world", "Hello world")]
    [InlineData("Hello", " world", "Hello world")]
    [InlineData("Hello", ".", "Hello.")]
    [InlineData("Hello", "?", "Hello?")]
    [InlineData("Hello", "。", "Hello。")]
    [InlineData("¿", "Qué", "¿Qué")]
    [InlineData("(", "note", "(note")]
    [InlineData("Привет", "мир", "Привет мир")]
    [InlineData("", "world", "world")]
    [InlineData("Hello", "", "Hello")]
    public void JoinsPiecesWithSpacesOnlyWhereWordsAreSpaced(string a, string b, string expected) =>
        Assert.Equal(expected, TextSpacing.Join(a, b));

    [Fact]
    public void JoinsListsSkippingEmptyPieces()
    {
        Assert.Equal("One two three", TextSpacing.Join(["One", "", "two", "three"]));
        Assert.Equal("一つ目。二つ目。", TextSpacing.Join(["一つ目。", "二つ目。"]));
    }

    // 設計判断: DEC-COM-174
    [Fact]
    public void JoinedUtterancesKeepWordsApart()
    {
        var english = new Utterance("spk1", 0, 1, "Thanks for coming") { RawText = "thanks for coming" };
        Meeting.JoinInto(english, new Utterance("spk1", 1, 2, "Let's start"));
        Assert.Equal("Thanks for coming Let's start", english.Text);
        Assert.Equal("thanks for coming Let's start", english.RawText);
        Assert.Equal(2, english.End);

        var japanese = new Utterance("spk1", 0, 1, "ありがとうございます。");
        Meeting.JoinInto(japanese, new Utterance("spk1", 1, 2, "始めましょう"));
        Assert.Equal("ありがとうございます。始めましょう", japanese.Text);
        Assert.Null(japanese.RawText);
    }

    // 設計判断: DEC-COM-174
    [Fact]
    public void SplittingKeepsSpacesBetweenEnglishWords()
    {
        // Whisper の語（トークン）は、語の前の空白を含む。つないだときに区間の文に戻る
        var words = new List<TimedWord> { new("Thanks", 0, 0.5), new(" for", 0.5, 1.0), new(" coming", 1.0, 2.0), new(" bye", 3.1, 3.4) };
        var turns = new List<SpeakerTurn> { new("A", 0, 3.0), new("B", 3.0, 3.5) };
        var split = MeetingProcessor.Split(words, turns);
        Assert.Equal(["Thanks for coming", "bye"], split.Select(u => u.Text));

        // 端の短いかけら（「bye」）を前の人にまとめても、あいだの空白は消えない
        var phrase = new TranscribedPhrase(MeetingChannel.Others, 0, 3.4, "Thanks for coming bye", words);
        var utterances = MeetingProcessor.BuildUtterances([], [phrase], turns);
        Assert.Equal(["Thanks for coming bye"], utterances.Select(u => u.Text));

        // 日本語（トークンが語の途中で切れる「Gem」「ini」）は、今までどおり空白を入れずにつなぐ
        var japanese = new List<TimedWord> { new("Gem", 0, 0.3), new("ini", 0.3, 0.6), new("の", 0.6, 0.8), new("話です", 0.8, 1.5) };
        Assert.Equal(["Geminiの話です"], MeetingProcessor.Split(japanese, [new SpeakerTurn("A", 0, 2)]).Select(u => u.Text));
    }

    // 設計判断: DEC-COM-174
    [Fact]
    public void WhisperWordsKeepLeadingSpaces()
    {
        // 英語のトークンは語の前に空白がある。捨てると、つないだ文字が区間の文と合わず語が空になっていた
        var tokens = new List<(string, double, double)>
        {
            ("[_BEG_]", 0, 0), (" Hello", 0, 0.5), (" world", 0.5, 1.0), (".", 1.0, 1.1), ("[_TT_55]", 1.1, 1.1),
        };
        var (text, words) = WhisperBatchTranscriber.Words("Hello world.", tokens, 0, 1.1);
        Assert.Equal("Hello world.", text);
        Assert.Equal(["Hello", " world", "."], words.Select(w => w.Text));
        Assert.Equal((0.5, 1.0), (words[1].Start, words[1].End));

        // 注釈のあとの空白は、注釈と一緒に除く
        var annotated = new List<(string, double, double)> { (" (", 0, 0.1), ("music", 0.1, 0.5), (")", 0.5, 0.6), (" Good", 0.6, 1.0), (" morning", 1.0, 1.5) };
        var (cleaned, annotatedWords) = WhisperBatchTranscriber.Words("(music) Good morning", annotated, 0, 1.5);
        Assert.Equal("Good morning", cleaned);
        Assert.Equal(["Good", " morning"], annotatedWords.Select(w => w.Text));
    }

    // 設計判断: DEC-COM-026
    [Theory]
    [InlineData("Thank you for watching!", true)]
    [InlineData("thanks for watching.", true)]
    [InlineData("Спасибо за просмотр.", true)]
    [InlineData("시청해주셔서 감사합니다.", true)]
    [InlineData("谢谢观看", true)]
    [InlineData("¡Gracias por ver!", true)]
    [InlineData("Untertitel im Auftrag des ZDF, 2021", true)]
    [InlineData("Субтитры сделал DimaTorzok", true)]
    [InlineData("Subtitles by the Amara.org community", true)]
    [InlineData("(Musik)", true)]
    [InlineData("[Applause]", true)]
    [InlineData("*risas*", true)]
    [InlineData("[音楽]", true)]
    [InlineData("チャンネル登録お願いします。", true)]
    [InlineData("Thank you for the update", false)]
    [InlineData("音楽の話をしましょう", false)]
    [InlineData("Gracias por venir", false)]
    public void FiltersHallucinationsInEveryLanguage(string segment, bool expected) =>
        Assert.Equal(expected, WhisperText.IsHallucination(segment));

    // 設計判断: DEC-COM-024
    [Fact]
    public void WhisperPromptUsesTheSeparatorOfTheLanguage()
    {
        Assert.Equal("Hanasu、Gemini", WhisperBatchTranscriber.WhisperPrompt(["Hanasu", "Gemini"], PromptLanguage.Ja));
        Assert.Equal("Hanasu, Gemini", WhisperBatchTranscriber.WhisperPrompt(["Hanasu", "Gemini"], PromptLanguage.En));
        // 言語を省くと今のプロンプトの言語
        PromptLanguageFixture.With(PromptLanguage.Es, () =>
            Assert.Equal("Hanasu, Gemini", WhisperBatchTranscriber.WhisperPrompt(["Hanasu", "Gemini"])));
        var words = Enumerable.Range(0, 100).Select(i => $"term{i:000}").ToArray();
        Assert.True(WhisperBatchTranscriber.WhisperPrompt(words, PromptLanguage.En).Length <= 130);
    }

    // 設計判断: DEC-DIC-082
    [Theory]
    [InlineData("кот => Кот", "котлета и кот", "котлета и Кот")]
    [InlineData("muller => Müller", "mullerérie muller", "mullerérie Müller")]
    [InlineData("스톡마크 => Stockmark", "스톡마크에서 일해요", "Stockmark에서 일해요")]
    // 日本語は今までどおり
    [InlineData("ストックマーク => Stockmark", "ストックマークの話", "Stockmarkの話")]
    [InlineData("ai => AI", "OpenAIとaiの話", "OpenAIとAIの話")]
    public void ReplacesOnlyWholeWordsInSpacedScripts(string dictionary, string input, string expected) =>
        Assert.Equal(expected, new UserDictionary(dictionary).Apply(input));

    // 設計判断: DEC-COM-073
    [Fact]
    public void EstimatesNonAsciiTextAsOneTokenPerCharacter()
    {
        Assert.Equal(6, DictionarySuggester.EstimateTokens("привет"));
        Assert.Equal(5, DictionarySuggester.EstimateTokens("مرحبا"));
        Assert.Equal(7, DictionarySuggester.EstimateTokens("ストックマーク"));
        Assert.Equal(2, DictionarySuggester.EstimateTokens("abcdef"));
        // ASCII の 3 文字（1 トークン）と é（1 トークン）
        Assert.Equal(2, DictionarySuggester.EstimateTokens("café"));
    }

    // 設計判断: DEC-DIC-023, DEC-DIC-028
    [Fact]
    public void ExtraRulesGoToJapaneseTranslationOnlyForJapaneseSpeakers()
    {
        var request = new RefineRequest { Transcript = "테스트", Model = "m", ExtraInstructions = "합니다체로 통일" };
        // 日本語の利用者（今までどおり）: 整形と和訳で使う
        Assert.True(TranslationLanguage.Japanese.KeepsExtraRules);
        Assert.Contains("합니다체로 통일", GeminiPrompts.UserPrompt(request, TranslationLanguage.Japanese));
        Assert.Contains("합니다체로 통일", GeminiPrompts.UserPrompt(request));
        Assert.DoesNotContain("합니다체로 통일", GeminiPrompts.UserPrompt(request, TranslationLanguage.English));

        // 韓国語の利用者: 整形では使い、和訳では使わない（韓国語の文体のルールを日本語の出力に付けない）
        PromptLanguageFixture.With(PromptLanguage.Ko, () =>
        {
            Assert.False(TranslationLanguage.Japanese.KeepsExtraRules);
            Assert.DoesNotContain("합니다체로 통일", GeminiPrompts.UserPrompt(request, TranslationLanguage.Japanese));
            Assert.Contains("합니다체로 통일", GeminiPrompts.UserPrompt(request));
        });
    }

    // 設計判断: DEC-MTG-061
    [Fact]
    public void CustomMinutesPromptDefaultFollowsTheCurrentLanguage()
    {
        var japaneseDefault = Prompts.Text("minutes.customDefault", PromptLanguage.Ja);
        var englishDefault = Prompts.Text("minutes.customDefault", PromptLanguage.En);
        Assert.NotEqual(japaneseDefault, englishDefault);

        // 既定は保存しない
        Assert.Equal("", new AppSettings().MeetingCustomMinutesPrompt);
        // 日本語の利用者は今までどおり日本語の既定
        Assert.Equal(japaneseDefault, MinutesTemplates.CustomPromptOrDefault(""));
        Assert.Equal(japaneseDefault, MinutesTemplates.CustomPromptOrDefault(japaneseDefault));

        PromptLanguageFixture.With(PromptLanguage.En, () =>
        {
            Assert.Equal(englishDefault, MinutesTemplates.CustomPromptOrDefault(""));
            Assert.Equal(englishDefault, MinutesTemplates.CustomPromptOrDefault(null));
            // 前の版が保存した日本語の既定は、既定として扱う
            Assert.Equal(englishDefault, MinutesTemplates.CustomPromptOrDefault(japaneseDefault));
            Assert.Equal(englishDefault, MinutesTemplates.CustomPromptOrDefault(japaneseDefault.ReplaceLineEndings("\r\n") + "\n"));
            // 書き換えたものはそのまま
            Assert.Equal("Focus on decisions", MinutesTemplates.CustomPromptOrDefault("Focus on decisions"));
            // 既定のままなら保存しない
            Assert.Equal("", MinutesTemplates.CustomPromptToStore(englishDefault));
            Assert.Equal("Focus on decisions", MinutesTemplates.CustomPromptToStore("Focus on decisions"));
        });

        // 設定を読み込むときに、保存されていた日本語の既定を空にする
        var stored = new AppSettings { MeetingCustomMinutesPrompt = japaneseDefault };
        SettingsStore.Normalize(stored);
        Assert.Equal("", stored.MeetingCustomMinutesPrompt);
        var edited = new AppSettings { MeetingCustomMinutesPrompt = "決定事項を中心に" };
        SettingsStore.Normalize(edited);
        Assert.Equal("決定事項を中心に", edited.MeetingCustomMinutesPrompt);
    }

    // 設計判断: DEC-COM-104
    [Fact]
    public void SpeechRecognitionFallsBackToAnotherRegionOfTheSameLanguage()
    {
        string[] installed = ["es-ES", "en-US", "en-GB", "zh-CN", "zh-TW", "ja-JP"];
        Assert.Equal("ja-JP", TranscriptionLocales.SpeechRecognitionLanguage("ja-JP", [], installed));
        Assert.Equal("en-US", TranscriptionLocales.SpeechRecognitionLanguage("EN-us", [], installed));
        Assert.Equal("es-ES", TranscriptionLocales.SpeechRecognitionLanguage("es-MX", ["es-MX"], installed));
        // 表示の言語にあるものを先に使う
        Assert.Equal("en-GB", TranscriptionLocales.SpeechRecognitionLanguage("en-AU", ["fr-FR", "en-GB"], installed));
        Assert.Equal("en-US", TranscriptionLocales.SpeechRecognitionLanguage("en-AU", ["fr-FR"], installed));
        // 中国語は簡体字と繁体字をそろえる
        Assert.Equal("zh-TW", TranscriptionLocales.SpeechRecognitionLanguage("zh-HK", [], installed));
        Assert.Equal("zh-CN", TranscriptionLocales.SpeechRecognitionLanguage("zh-SG", [], installed));
        Assert.Null(TranscriptionLocales.SpeechRecognitionLanguage("zh-HK", [], ["zh-CN"]));
        // 言語コードが同じものがなければ null（今までどおりエラー）
        Assert.Null(TranscriptionLocales.SpeechRecognitionLanguage("ko-KR", ["ko-KR"], installed));
    }

    // 要件: REQ-COM-060
    [Fact]
    public void HistoryDetailDateUsesTheDisplayCulture()
    {
        var date = new DateTimeOffset(2026, 11, 3, 9, 5, 7, TimeSpan.Zero);
        var local = date.ToLocalTime();
        // 日本語は今までの形のまま
        Assert.Equal(local.ToString("yyyy/MM/dd HH:mm:ss", System.Globalization.CultureInfo.GetCultureInfo("ja-JP")), DictationHistoryStore.DetailDateLabel(date));
        var english = UiCultureFixture.With("en-US", () => DictationHistoryStore.DetailDateLabel(date));
        Assert.Contains(local.ToString("ss"), english);
        Assert.Contains(local.Year.ToString(), english);
    }
}
