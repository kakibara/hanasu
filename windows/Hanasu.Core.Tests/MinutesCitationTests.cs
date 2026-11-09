using Hanasu.Core.Ai;
using Hanasu.Core.LocalLlm;
using Hanasu.Core.Meetings;

namespace Hanasu.Core.Tests;

// 確かめ方: REQ-MTG-052
/// <summary>議事録の根拠の時刻の印（DEC-MTG-134）。Mac 版の --test-minutes-citations と同じことを確かめる</summary>
public class MinutesCitationTests
{
    [Fact]
    public void MarksAreReadInOrder()
    {
        var marks = MinutesCitation.Marks("- 価格は 2 案で比べる [07:00] [1:02:34]");
        Assert.Equal(new[] { "07:00", "1:02:34" }, marks.Select(m => m.Label));
        Assert.Equal(new[] { 420.0, 3754.0 }, marks.Select(m => m.Seconds));
        // 全角の［］も読む。Markdown のリンクは印にしない
        Assert.Single(MinutesCitation.Marks("決まった［12:34］"));
        Assert.Empty(MinutesCitation.Marks("[12:34](hanasu-time://754)"));
    }

    [Fact]
    public void StripRemovesMarksAndTrailingSpaces()
    {
        Assert.Equal("- 価格は 2 案で比べる\n- 次", MinutesCitation.Strip("- 価格は 2 案で比べる [07:00] [1:02:34]\n- 次［00:10］"));
        Assert.Equal("変えない [リンク](https://example.com)", MinutesCitation.Strip("変えない [リンク](https://example.com)"));
        Assert.Equal("時刻 [12:34](hanasu-time://754)", MinutesCitation.Strip("時刻 [12:34](hanasu-time://754)"));
    }

    [Fact]
    public void InstructionAsksForCitationsAfterActionItems()
    {
        var instruction = MinutesPrompt.SystemInstruction(MinutesTemplate.Auto, null);
        var citations = Prompts.Text("minutes.citations", PromptLanguage.Current);
        Assert.Contains("[12:34]", citations);
        Assert.Contains(citations, instruction);
        // アクションアイテムの指示のあと、話者の名前の指示の前（Mac 版と同じ組み立て。DEC-COM-102）
        Assert.True(instruction.IndexOf("<action_items>", StringComparison.Ordinal) < instruction.IndexOf(citations, StringComparison.Ordinal));
        Assert.True(instruction.IndexOf(citations, StringComparison.Ordinal) < instruction.IndexOf(MinutesPrompt.SpeakerNamesInstruction, StringComparison.Ordinal));
    }

    [Fact]
    public void ActionItemsKeepAtAndDropMarksFromTasks()
    {
        const string response = """
            ## 概要
            - リリースは 11 月 20 日 [01:15]

            ## アクションアイテム
            {{ACTION_ITEMS}}

            <action_items>
            [{"owner": "田中", "task": "見積を送る [07:12]", "due": "2026-11-14", "due_note": "14 日まで", "at": "07:12"},
             {"owner": "自分", "task": "承認を取る", "at": "作り話"}]
            </action_items>
            """;
        var result = MinutesPrompt.Parse(response, "定例", PromptLanguage.Ja);
        Assert.Equal("見積を送る", result.ActionItems[0].Task);
        Assert.Equal("07:12", result.ActionItems[0].At);
        Assert.Null(result.ActionItems[1].At);
        Assert.Contains("[01:15]", result.Markdown);

        // JSON が壊れていたときの読み取り（DEC-MTG-064）も、行末の印に乱されない
        var parsed = ActionItem.ParseFromMarkdown("## アクションアイテム\n- [ ] 見積を送る（担当: 田中 / 期限: 11/14 (金)） [07:12]");
        Assert.Equal("見積を送る", parsed[0].Task);
        Assert.Equal("田中", parsed[0].Owner);
        Assert.Equal("07:12", parsed[0].At);
    }

    [Fact]
    public void AtAndAudioOffsetsSurviveJsonRoundTrip()
    {
        var meeting = new Meeting
        {
            Id = "2026-11-09 1000",
            Title = "定例",
            StartedAt = new DateTimeOffset(2026, 11, 9, 1, 0, 0, TimeSpan.Zero),
            ActionItems = new() { new ActionItem { Task = "見積を送る", At = "07:12" } },
            AudioStartOffsets = new() { ["me"] = 0.12, ["others"] = 0.31 },
        };
        var json = MeetingJson.Serialize(meeting);
        Assert.Contains("\"at\": \"07:12\"", json);
        var read = MeetingJson.Deserialize(json);
        Assert.Equal("07:12", read.ActionItems![0].At);
        Assert.Equal(0.31, read.AudioStartOffsets!["others"]);
    }

    private sealed class ShorteningGenerator(string response) : ITextGenerator
    {
        public string ProviderName => "テスト";

        public Task<string> GenerateTextAsync(TextPurpose purpose, string systemInstruction, string userText, string model,
            CancellationToken cancellationToken = default)
        {
            // ローカルの AI が文字起こしを縮めて送ったときと同じく、報告に印を付ける
            LongInputReport.Current.Value?.MarkShortened();
            return Task.FromResult(response);
        }
    }

    [Fact]
    public async Task MarksAreDroppedWhenTheTranscriptWasShortened()
    {
        var meeting = new Meeting { Id = "x", Title = "定例", StartedAt = DateTimeOffset.UnixEpoch };
        meeting.Utterances.Add(new Utterance { Speaker = "me", Start = 1, End = 2, Text = "こんにちは" });
        var generator = new ShorteningGenerator("## 概要\n- 挨拶した [00:01]\n\n## アクションアイテム\n{{ACTION_ITEMS}}\n<action_items>[{\"task\": \"連絡する\", \"at\": \"00:01\"}]</action_items>");
        var result = await MeetingProcessor.MakeMinutesAsync(meeting, generator, "model");
        Assert.DoesNotContain("[00:01]", result.Markdown);
        Assert.Null(result.ActionItems[0].At);
        Assert.Null(LongInputReport.Current.Value);
    }
}
