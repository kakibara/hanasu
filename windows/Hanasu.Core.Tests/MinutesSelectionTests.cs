using System.Text.Json.Nodes;
using Hanasu.Core.Meetings;

namespace Hanasu.Core.Tests;

// 確かめ方: REQ-MTG-044, REQ-MTG-045
public class MinutesSelectionTests
{
    /// <summary>自分・話者1 が交互に話す会議（ID は順に U1〜U6）</summary>
    private static Meeting Sample() => new()
    {
        Title = "定例",
        StartedAt = new DateTimeOffset(2026, 11, 3, 5, 30, 0, TimeSpan.Zero),
        Duration = 100,
        Utterances =
        [
            new("me", 0, 1, "雑談。") { Id = "U1" },
            new("me", 2, 3, "始めます。") { Id = "U2" },
            new("spk1", 10, 12, "議題は二つ。") { Id = "U3" },
            new("spk1", 13, 14, "一つ目。") { Id = "U4" },
            new("me", 20, 22, "まとめます。") { Id = "U5" },
            new("me", 60, 62, "次の会議の話。") { Id = "U6" },
        ],
    };

    // 設計判断: DEC-MTG-090
    [Fact]
    public void UseFollowsThePrecedenceOfReasons()
    {
        var m = Sample();
        Assert.All(m.Utterances, u => Assert.Equal(MinutesUse.Used, m.MinutesUseOf(u)));
        Assert.False(m.HasMinutesSelection);

        m.MinutesFrom = 2;
        m.MinutesTo = 20;
        Assert.Equal(MinutesUse.OutsideRange, m.MinutesUseOf(m.Utterances[0]));
        Assert.Equal(MinutesUse.Used, m.MinutesUseOf(m.Utterances[1]));  // 最初と同じ時刻は範囲の中
        Assert.Equal(MinutesUse.Used, m.MinutesUseOf(m.Utterances[4]));  // 最後と同じ時刻も範囲の中
        Assert.Equal(MinutesUse.OutsideRange, m.MinutesUseOf(m.Utterances[5]));

        // 話者 → オフレコ → 発言ごと の順に、理由が範囲より先に立つ
        m.ExcludedSpeakers = ["me"];
        Assert.Equal(MinutesUse.SpeakerExcluded, m.MinutesUseOf(m.Utterances[0]));
        m.OffRecord = [new OffRecordSpan(0, 2)];
        Assert.Equal(MinutesUse.OffRecord, m.MinutesUseOf(m.Utterances[0]));
        Assert.Equal(MinutesUse.SpeakerExcluded, m.MinutesUseOf(m.Utterances[1]));  // 終わりの時刻はオフレコの外
        m.ExcludedUtterances = ["U1"];
        Assert.Equal(MinutesUse.Excluded, m.MinutesUseOf(m.Utterances[0]));
        Assert.True(m.HasMinutesSelection);
        Assert.Equal(["U3", "U4"], m.UsedUtterances.Select(u => u.Id));

        // 終わりのないオフレコは、記録の終わりまで
        Assert.True(new Meeting { OffRecord = [new OffRecordSpan(50)] }.IsOffRecord(1e6));
    }

    // 設計判断: DEC-MTG-090
    [Fact]
    public void DisplayBlocksDoNotMergeAcrossAChangeOfUse()
    {
        var m = Sample();
        Assert.Equal(["雑談。始めます。", "議題は二つ。一つ目。", "まとめます。", "次の会議の話。"], m.DisplayBlocks().Select(b => b.Block.Text));

        m.SetExcluded(["U1"], excluded: true);
        var blocks = m.DisplayBlocks();
        Assert.Equal(["雑談。", "始めます。", "議題は二つ。一つ目。", "まとめます。", "次の会議の話。"], blocks.Select(b => b.Block.Text));
        Assert.Equal([MinutesUse.Excluded, MinutesUse.Used, MinutesUse.Used, MinutesUse.Used, MinutesUse.Used], blocks.Select(b => b.Use));
        // まとめた発言の ID と、最後の発言の開始時刻を持つ。ID は先頭の発言の ID
        Assert.Equal(["U3", "U4"], blocks[2].Members);
        Assert.Equal("U3", blocks[2].Id);
        Assert.Equal(13, blocks[2].LastStart);
        Assert.Equal(14, blocks[2].Block.End);
        // 元の発言は変えない
        Assert.Equal("議題は二つ。", m.Utterances[2].Text);
        // MergedBlocks の区切りは、必ずここでも区切りになる
        Assert.Equal(m.MergedBlocks().Count, Sample().DisplayBlocks().Count);
    }

    // 設計判断: DEC-MTG-091
    [Fact]
    public void PromptsAndExportsUseOnlyUsedUtterances()
    {
        var m = Sample();
        m.SetMinutesTo(20);
        m.SetExcluded(["U4"], excluded: true);
        Assert.Equal(["雑談。始めます。", "議題は二つ。", "まとめます。"], m.BlocksForMinutes().Select(b => b.Text));

        var prompt = m.TranscriptForPrompt();
        Assert.Contains("[00:10] 話者1: 議題は二つ。", prompt);
        Assert.DoesNotContain("一つ目。", prompt);
        Assert.DoesNotContain("次の会議の話。", prompt);
        m.Notes = [new MeetingNote(MeetingNoteKind.Highlight, 12, "")];
        Assert.DoesNotContain("一つ目。", m.TranscriptForPromptMarkingHighlights());
        Assert.DoesNotContain("一つ目。", MinutesPrompt.UserText(m));

        // 書き出し（transcript.md・コピー）は使う発言だけで、除いた数を 1 行書く
        var markdown = m.TranscriptMarkdown();
        Assert.DoesNotContain("一つ目。", markdown);
        Assert.DoesNotContain("次の会議の話。", markdown);
        Assert.Contains("- 議事録に使わない発言（2 件）は含めていません\n", markdown);
        Assert.DoesNotContain("議事録に使わない発言", Sample().TranscriptMarkdown());
    }

    // 設計判断: DEC-MTG-090, DEC-MTG-092
    [Fact]
    public void MutatorsChangeTheSelectionAndMarkMinutesOutdated()
    {
        var m = Sample();
        m.SetExcluded(["U2", "U3"], excluded: true);
        m.SetExcluded(["U2"], excluded: true);  // 重ねて除いても 1 つ
        Assert.Equal(["U2", "U3"], m.ExcludedUtterances);
        Assert.True(m.MinutesOutdated);
        m.SetExcluded(["U2", "U3"], excluded: false);
        Assert.Null(m.ExcludedUtterances);

        m.SetSpeakerExcluded("spk1", excluded: true);
        Assert.Equal(["spk1"], m.ExcludedSpeakers);
        m.SetSpeakerExcluded("spk1", excluded: false);
        Assert.Null(m.ExcludedSpeakers);

        // 最初が最後より後になったら、もう一方を外す
        m.SetMinutesFrom(10);
        m.SetMinutesTo(20);
        Assert.Equal((10.0, 20.0), (m.MinutesFrom!.Value, m.MinutesTo!.Value));
        m.SetMinutesFrom(30);
        Assert.Null(m.MinutesTo);
        m.SetMinutesTo(5);
        Assert.Null(m.MinutesFrom);

        // 使うにすると、除外を外し、範囲の外なら範囲を広げる
        m.SetMinutesFrom(10);
        m.SetMinutesTo(20);
        m.SetExcluded(["U5"], excluded: true);
        m.Include(["U2", "U5", "U6"]);
        Assert.Null(m.ExcludedUtterances);
        Assert.Equal((2.0, 60.0), (m.MinutesFrom!.Value, m.MinutesTo!.Value));
        Assert.All(m.Utterances.Skip(1), u => Assert.Equal(MinutesUse.Used, m.MinutesUseOf(u)));

        m.OffRecord = [new OffRecordSpan(0, 5) { Id = "S1" }, new OffRecordSpan(50, 70) { Id = "S2" }];
        m.MinutesOutdated = null;
        m.RemoveOffRecord("S1");
        Assert.Equal(["S2"], m.OffRecord!.Select(s => s.Id));
        Assert.True(m.MinutesOutdated);
        m.RemoveOffRecord("S2");
        Assert.Null(m.OffRecord);

        m.SetSpeakerExcluded("me", excluded: true);
        m.ClearMinutesSelection();
        Assert.False(m.HasMinutesSelection);
        Assert.True(m.MinutesOutdated);
    }

    // 設計判断: DEC-MTG-090（Mac 版と同じキー。DEC-MTG-108）
    [Fact]
    public void ReadsAndWritesTheSelectionKeysLikeMac()
    {
        // Mac 版が書く形（sortedKeys。UUID は大文字、終わりのないオフレコは end を書かない）
        var json = JsonNode.Parse(MeetingJsonTests.MacMeetingJson)!.AsObject();
        json["excludedSpeakers"] = new JsonArray("room1");
        json["excludedUtterances"] = new JsonArray("6B3D9C0E-7D8A-4F1B-9C4D-3E2F1A0B9C8D");
        json["minutesFrom"] = 0.25;
        json["minutesOutdated"] = true;
        json["minutesTo"] = 9;
        json["offRecord"] = new JsonArray(
            new JsonObject { ["end"] = 5.5, ["id"] = "8D5F1E2A-9FAC-4B3D-9E6F-5A4B3C2D1E0F", ["start"] = 3 },
            new JsonObject { ["id"] = "9E6A2F3B-0ABD-4C4E-8F7A-6B5C4D3E2F1A", ["start"] = 1000 });
        var m = MeetingJson.Deserialize(json.ToJsonString());
        Assert.Equal(0.25, m.MinutesFrom);
        Assert.Equal(9, m.MinutesTo);
        Assert.True(m.MinutesOutdated);
        Assert.Equal(["room1"], m.ExcludedSpeakers);
        Assert.Equal(["6B3D9C0E-7D8A-4F1B-9C4D-3E2F1A0B9C8D"], m.ExcludedUtterances);
        Assert.Equal(2, m.OffRecord!.Count);
        Assert.Equal((3.0, 5.5), (m.OffRecord[0].Start, m.OffRecord[0].End!.Value));
        Assert.Null(m.OffRecord[1].End);
        // 「よろしくお願いします。」（4 秒）は除外とオフレコの両方に当たるが、理由は除外
        Assert.Equal(MinutesUse.Excluded, m.MinutesUseOf(m.Utterances[1]));
        Assert.Equal(MinutesUse.SpeakerExcluded, m.MinutesUseOf(m.Utterances[2]));
        Assert.Equal(["5A2C8B9D-6C7F-4E0A-8B3C-2D1E0F9A8B7C"], m.UsedUtterances.Select(u => u.Id));

        var written = JsonNode.Parse(MeetingJson.Serialize(m))!.AsObject();
        foreach (var key in new[] { "minutesFrom", "minutesTo", "excludedUtterances", "excludedSpeakers", "offRecord", "minutesOutdated" })
        {
            Assert.True(written.ContainsKey(key), key);
        }
        Assert.Equal("8D5F1E2A-9FAC-4B3D-9E6F-5A4B3C2D1E0F", written["offRecord"]![0]!["id"]!.GetValue<string>());
        Assert.False(written["offRecord"]![1]!.AsObject().ContainsKey("end"));
        Assert.Equal(MeetingJson.Serialize(MeetingJson.Deserialize(written.ToJsonString())), MeetingJson.Serialize(m));

        // 選び方のない会議は、どのキーも書かない（null は書かない）
        var plain = JsonNode.Parse(MeetingJson.Serialize(MeetingJson.Deserialize(MeetingJsonTests.MacMeetingJson)))!.AsObject();
        foreach (var key in new[] { "minutesFrom", "minutesTo", "excludedUtterances", "excludedSpeakers", "offRecord", "minutesOutdated" })
        {
            Assert.False(plain.ContainsKey(key), key);
        }
        // 新しく作ったオフレコの ID は、Swift の UUID と同じ大文字の形
        var id = new OffRecordSpan(1).Id;
        Assert.Equal(id.ToUpperInvariant(), id);
        Assert.True(Guid.TryParse(id, out _));
    }
}

// 確かめ方: REQ-MTG-046
public class OffRecordTests
{
    // 設計判断: DEC-MTG-094
    [Fact]
    public void SleepCutDropsLaterSpansAndClampsEnds()
    {
        var m = new Meeting
        {
            Duration = 500,
            OffRecord =
            [
                new OffRecordSpan(10, 20) { Id = "A" },
                new OffRecordSpan(90, 200) { Id = "B" },
                new OffRecordSpan(150) { Id = "C" },
                new OffRecordSpan(100) { Id = "D" },
            ],
        };
        MeetingSleepCut.Apply(m, new MeetingSleepPoint(100, DateTimeOffset.Now));
        Assert.Equal(100, m.Duration);
        // スリープの後（と同じ時刻）に始めた区間は消し、終わりはスリープした時点まで
        Assert.Equal([("A", 10.0, 20.0), ("B", 90.0, 100.0)], m.OffRecord!.Select(s => (s.Id, s.Start, s.End!.Value)));

        var later = new Meeting { OffRecord = [new OffRecordSpan(120)] };
        MeetingSleepCut.Apply(later, new MeetingSleepPoint(100, DateTimeOffset.Now));
        Assert.Null(later.OffRecord);
    }
}
