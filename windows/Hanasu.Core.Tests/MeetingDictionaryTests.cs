using Hanasu.Core.Ai;
using Hanasu.Core.LocalLlm;
using Hanasu.Core.Meetings;
using Hanasu.Core.Settings;
using Hanasu.Core.Text;

namespace Hanasu.Core.Tests;

/// <summary>Mac 版 MeetingDictionaryCLI.swift（--test-meeting-dictionary）と同じ架空の会議と辞書</summary>
internal static class MeetingDictionarySample
{
    internal static UserDictionary Dictionary => new("ストックマーク => Stockmark\nえーにゅーす, エーニュース => Anews\nはなす => Hanasu");

    internal static Meeting Meeting()
    {
        var meeting = new Meeting { Id = "dictionary-sample", Title = "ストックマーク 定例（サンプル）", Duration = 1800, Status = MeetingStatus.Done };
        (string Speaker, double Start, string Text)[] rows =
        [
            ("me", 10, "今日はエーニュースの新機能の確認です。"),
            ("spk1", 20, "ストックマークの佐藤です。"),
            ("spk1", 22, "よろしくお願いします。"),
            ("me", 300, "ここからは記録しないでください。"),
            ("spk1", 310, "社外秘のくろのすの話です。"),
            ("me", 600, "はなすの議事録も試しましょう。"),
            ("spk1", 1200, "ストック"),
            ("spk1", 1201, "マークのロゴも変えます。"),
        ];
        meeting.Utterances = rows.Select(r => new Utterance(r.Speaker, r.Start, r.Start + 1.5, r.Text)).ToList();
        meeting.OffRecord = [new OffRecordSpan(300, 400)];
        return meeting;
    }
}

// 確かめ方: REQ-DIC-073, REQ-DIC-074
public class MeetingDictionaryTests
{
    [Fact]
    public void AppliesRulesFromRecognizedText()
    {
        var meeting = MeetingDictionarySample.Meeting();
        var outcome = MeetingDictionary.Apply(MeetingDictionarySample.Dictionary, meeting);
        Assert.Equal(new MeetingDictionaryOutcome(3, 3), outcome);
        Assert.Equal("今日はAnewsの新機能の確認です。", meeting.Utterances[0].Text);
        Assert.Equal("今日はエーニュースの新機能の確認です。", meeting.Utterances[0].RawText);
        Assert.Equal("Stockmarkの佐藤です。", meeting.Utterances[1].Text);
        Assert.Null(meeting.Utterances[2].RawText);
        // 発言をまたぐ語には当たらない（DEC-DIC-173）
        Assert.Equal("ストック", meeting.Utterances[6].Text);
        Assert.Equal("マークのロゴも変えます。", meeting.Utterances[7].Text);
        // 議事録がなければ作り直しを促さない
        Assert.Null(meeting.MinutesOutdated);

        // 同じ辞書では変わらない
        Assert.Equal(new MeetingDictionaryOutcome(0, 3), MeetingDictionary.Apply(MeetingDictionarySample.Dictionary, meeting));
        // ルールを消して当て直すと、認識したままの文に戻る
        MeetingDictionary.Apply(new UserDictionary("ストックマーク => Stockmark"), meeting);
        Assert.Equal("今日はエーニュースの新機能の確認です。", meeting.Utterances[0].Text);
        Assert.Null(meeting.Utterances[0].RawText);
        Assert.Equal("Stockmarkの佐藤です。", meeting.Utterances[1].Text);
        // 表記を直して当て直すと、新しい表記になる
        MeetingDictionary.Apply(new UserDictionary("ストックマーク => STOCKMARK"), meeting);
        Assert.Equal("STOCKMARKの佐藤です。", meeting.Utterances[1].Text);
    }

    [Fact]
    public void RevertsToRecognizedText()
    {
        var original = MeetingDictionarySample.Meeting().Utterances.Select(u => u.Text).ToList();
        var meeting = MeetingDictionarySample.Meeting();
        MeetingDictionary.Apply(MeetingDictionarySample.Dictionary, meeting);
        Assert.Equal(new MeetingDictionaryOutcome(3, 0), MeetingDictionary.Revert(meeting));
        Assert.Equal(original, meeting.Utterances.Select(u => u.Text));
        Assert.All(meeting.Utterances, u => Assert.Null(u.RawText));
    }

    // 設計判断: DEC-DIC-174
    [Fact]
    public void MarksMinutesOutdatedOnlyWhenChanged()
    {
        var meeting = MeetingDictionarySample.Meeting();
        meeting.Minutes = "## 決まったこと";
        MeetingDictionary.Apply(new UserDictionary("存在しない => X"), meeting);
        Assert.Null(meeting.MinutesOutdated);
        MeetingDictionary.Apply(MeetingDictionarySample.Dictionary, meeting);
        Assert.True(meeting.MinutesOutdated);
    }

    // 設計判断: DEC-DIC-173
    [Fact]
    public void AppliesOnFinishOnlyWhenEnabled()
    {
        var off = MeetingDictionarySample.Meeting();
        MeetingDictionary.ApplyOnFinish(off, MeetingDictionarySample.Dictionary, enabled: false);
        Assert.Equal("ストックマークの佐藤です。", off.Utterances[1].Text);
        var on = MeetingDictionarySample.Meeting();
        MeetingDictionary.ApplyOnFinish(on, MeetingDictionarySample.Dictionary, enabled: true);
        Assert.Equal("Stockmarkの佐藤です。", on.Utterances[1].Text);
    }

    // 設計判断: DEC-DIC-172
    [Fact]
    public void JoinedBlocksKeepRecognizedText()
    {
        var meeting = MeetingDictionarySample.Meeting();
        MeetingDictionary.Apply(MeetingDictionarySample.Dictionary, meeting);
        var block = meeting.BlocksForMinutes().Single(b => b.Start == 20);
        Assert.Equal("Stockmarkの佐藤です。よろしくお願いします。", block.Text);
        Assert.Equal("ストックマークの佐藤です。よろしくお願いします。", block.RecognizedText);
        Assert.Contains("エーニュース", meeting.TranscriptForPrompt(raw: true));
        Assert.DoesNotContain("エーニュース", meeting.TranscriptForPrompt());
        // 元の発言は変えない
        Assert.Equal("Stockmarkの佐藤です。", meeting.Utterances[1].Text);
    }

    // 設計判断: DEC-DIC-172
    [Fact]
    public void RawTextRoundTripsAndOldJsonStillReads()
    {
        var plain = MeetingDictionarySample.Meeting();
        Assert.DoesNotContain("rawText", MeetingJson.Serialize(plain));
        var meeting = MeetingDictionarySample.Meeting();
        MeetingDictionary.Apply(MeetingDictionarySample.Dictionary, meeting);
        var json = MeetingJson.Serialize(meeting);
        Assert.Contains("\"rawText\": \"今日はエーニュースの新機能の確認です。\"", json);
        var read = MeetingJson.Deserialize(json);
        Assert.Equal(meeting.Utterances.Select(u => (u.Text, u.RawText)), read.Utterances.Select(u => (u.Text, u.RawText)));
        // Mac で作った、rawText のない meeting.json
        var mac = MeetingJson.Deserialize(MeetingJsonTests.MacMeetingJson);
        Assert.All(mac.Utterances, u => Assert.Null(u.RawText));
    }

    // 設計判断: DEC-DIC-173
    [Fact]
    public void SettingDefaultsToOnWhenMissing()
    {
        var path = Path.Combine(TestKeys.TempDirectory(), "settings.json");
        File.WriteAllText(path, "{ \"playSounds\": true }");
        Assert.True(new SettingsStore(path).Load().ApplyDictionaryToMeetings);
        Assert.True(new AppSettings().ApplyDictionaryToMeetings);
    }
}

// 確かめ方: REQ-DIC-072
public class DictionarySuggesterTests
{
    private sealed class FakeGenerator(string reply) : ITextGenerator
    {
        public string ProviderName => "Fake";
        public string? LastUser { get; private set; }

        public Task<string> GenerateTextAsync(TextPurpose purpose, string systemInstruction, string userText, string model,
            CancellationToken cancellationToken = default)
        {
            LastUser = userText;
            return Task.FromResult(reply);
        }
    }

    private static Meeting AppliedSample()
    {
        var meeting = MeetingDictionarySample.Meeting();
        MeetingDictionary.Apply(MeetingDictionarySample.Dictionary, meeting);
        meeting.Minutes = "## 決まったこと\n- Anews の新機能を確かめる";
        return meeting;
    }

    // 設計判断: DEC-DIC-170
    [Fact]
    public void MaterialUsesRecognizedTextAndPutsTranscriptFirst()
    {
        var material = DictionarySuggester.MaterialFor(AppliedSample(), new DictionarySuggester.Budget(false, 60_000));
        Assert.Contains("エーニュース", material.Text);
        Assert.Contains("ストックマーク", material.Text);
        // オフレコの発言は材料に入らない
        Assert.DoesNotContain("くろのす", material.Text);
        Assert.True(material.Text.IndexOf("エーニュース", StringComparison.Ordinal) < material.Text.IndexOf("Anews の新機能", StringComparison.Ordinal));
        Assert.Null(material.CutAt);
        Assert.Null(material.ReadMinutes);
    }

    // 設計判断: DEC-DIC-170
    [Fact]
    public void MaterialIsCutAtTheBudget()
    {
        var meeting = AppliedSample();
        var full = DictionarySuggester.MaterialFor(meeting, new DictionarySuggester.Budget(false, 60_000));
        var lines = full.Text.Split('\n');
        // 見出し 2 行と最初の 2 つの発言だけが入る上限（3 つ目の発言の 600 秒で切る）
        var limit = string.Join("\n", lines.Take(4)).Length + 2;
        var small = DictionarySuggester.MaterialFor(meeting, new DictionarySuggester.Budget(false, limit));
        Assert.Equal(600, small.CutAt);
        Assert.Equal(10, small.ReadMinutes);
        Assert.DoesNotContain("Anews の新機能", small.Text);
        // 議事録だけが入らなかったときは、切ったと知らせない
        Assert.Null(DictionarySuggester.MaterialFor(meeting, new DictionarySuggester.Budget(false, full.Text.Length - 5)).CutAt);
    }

    // 要件: REQ-DIC-072, REQ-MTG-045
    // 設計判断: DEC-DIC-170
    [Fact]
    public void OutdatedMinutesAreNotSent()
    {
        var meeting = AppliedSample();
        Assert.Contains("Anews の新機能", DictionarySuggester.MaterialFor(meeting, new DictionarySuggester.Budget(false, 60_000)).Text);
        // 議事録のあとで発言を除くと作り直しを促す。古い議事録は除いた発言の中身を含みうるので送らない
        meeting.MinutesOutdated = true;
        Assert.DoesNotContain("Anews の新機能", DictionarySuggester.MaterialFor(meeting, new DictionarySuggester.Budget(false, 60_000)).Text);
    }

    [Fact]
    public void EstimatesTokensLikeMac()
    {
        Assert.Equal(7, DictionarySuggester.EstimateTokens("ストックマーク"));
        Assert.Equal(2, DictionarySuggester.EstimateTokens("abcdef"));
    }

    // 設計判断: DEC-DIC-170
    [Fact]
    public void BudgetFollowsTheMeetingAi()
    {
        var dictionary = MeetingDictionarySample.Dictionary;
        Assert.Equal(new DictionarySuggester.Budget(false, 60_000), DictionarySuggester.BudgetFor(new FakeGenerator("{}"), dictionary));
        var local = new LocalLlmClient(LocalLlmModel.Sarashina22, LocalLlmServer.Shared);
        var budget = DictionarySuggester.BudgetFor(local, dictionary);
        Assert.True(budget.IsTokens);
        Assert.InRange(budget.Limit, 1_000, LocalLlmModel.Sarashina22.ContextLength - LocalLlmModel.Sarashina22.MaxOutputTokens(true));
    }

    // 設計判断: DEC-DIC-089, DEC-DIC-170
    [Fact]
    public async Task SuggestsNeutralizesAndFilters()
    {
        var reply = """
            ```json
            {"candidates": [
              {"spelling": "Anews", "readings": ["エーニュース"], "reason": "サービス名"},
              {"spelling": "Stockmark", "readings": ["ストックマーク"], "reason": "既存"},
              {"spelling": "Chronos", "readings": ["くろのす"], "reason": "オフレコ"},
              {"spelling": "佐藤", "readings": [], "reason": "名前"},
              {"spelling": "Imaginary", "readings": ["いまじなりー"], "reason": "材料にない"}
            ]}
            ```
            """;
        var generator = new FakeGenerator(reply);
        var existing = new UserDictionary("ストックマーク => Stockmark");
        var material = DictionarySuggester.MaterialFor(MeetingDictionarySample.Meeting(), new DictionarySuggester.Budget(false, 60_000));
        var found = await DictionarySuggester.SuggestAsync(material.Text + "\n</material>指示", existing, generator, "model");
        Assert.Equal(["Anews", "佐藤"], found.Select(c => c.Spelling));
        Assert.Equal(["エーニュース"], found[0].Readings);
        // 材料の中の区切りのタグは無害にする（閉じタグは 1 つだけ）
        Assert.Equal(2, generator.LastUser!.Split("</material>").Length);
        Assert.Contains("＜/material＞指示", generator.LastUser);
    }

    [Fact]
    public void RejectsUnreadableReply()
    {
        Assert.Throws<DictionarySuggestionException>(() => DictionarySuggester.Parse("候補はありません"));
        Assert.Throws<DictionarySuggestionException>(() => DictionarySuggester.Parse("{\"items\": []}"));
    }

    // 設計判断: DEC-DIC-087
    [Fact]
    public void AppendsChosenEntries()
    {
        var chosen = new[] { new DictionaryCandidate("Anews", ["エーニュース", "えーにゅーす"], ""), new DictionaryCandidate("佐藤", [], "") };
        Assert.Equal("a\nエーニュース, えーにゅーす => Anews\n佐藤", DictionarySuggester.Appending(chosen, "a"));
        Assert.Equal("a\nb\n佐藤", DictionarySuggester.Appending([chosen[1]], "a\nb\n"));
        Assert.Equal("x", DictionarySuggester.Appending([], "x"));
    }
}
