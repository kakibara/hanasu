using System.Net;
using System.Text.Json.Nodes;
using Hanasu.Core.Audio;
using Hanasu.Core.Gemini;
using Hanasu.Core.Meetings;
using Hanasu.Core.Settings;
using Hanasu.Core.Transcription;
using Hanasu.Whisper;

namespace Hanasu.Core.Tests;

public class MeetingJsonTests
{
    /// <summary>Mac 版（Swift の JSONEncoder: prettyPrinted・sortedKeys・iso8601）が書く meeting.json と同じ形の架空の会議</summary>
    internal const string MacMeetingJson = """
        {
          "actionItems" : [
            {
              "due" : "2026-11-13",
              "dueNote" : "来週の金曜",
              "id" : "0B7F3C4E-1D2A-4F5B-9C8D-7E6F5A4B3C2D",
              "owner" : "話者1",
              "reminderID" : "x-apple-reminder://ABC",
              "task" : "見積もりを送る"
            },
            {
              "id" : "1C8E4D5F-2E3B-4A6C-8D9E-8F7A6B5C4D3E",
              "task" : "議題を共有する"
            }
          ],
          "customMinutesPrompt" : "## 概要\n## 決まったこと",
          "duration" : 1234.5,
          "id" : "2026-11-03 1430",
          "minutes" : "# 定例 — 議事録\n\n## 概要\nテスト",
          "minutesTemplate" : "oneOnOne",
          "notes" : [
            {
              "id" : "2D9F5E6A-3F4C-4B7D-9E0F-9A8B7C6D5E4F",
              "kind" : "note",
              "text" : "価格は来週",
              "time" : 65
            },
            {
              "id" : "3E0A6F7B-4A5D-4C8E-8F1A-0B9C8D7E6F5A",
              "kind" : "highlight",
              "text" : "",
              "time" : 120.25
            },
            {
              "id" : "4F1B7A8C-5B6E-4D9F-9A2B-1C0D9E8F7A6B",
              "kind" : "note",
              "text" : "あとで書いたメモ"
            }
          ],
          "speakerNames" : {
            "spk1" : "田中さん"
          },
          "startedAt" : "2026-11-03T05:30:00Z",
          "status" : "done",
          "title" : "定例",
          "utterances" : [
            {
              "end" : 3.5,
              "id" : "5A2C8B9D-6C7F-4E0A-8B3C-2D1E0F9A8B7C",
              "speaker" : "me",
              "start" : 0.25,
              "text" : "始めます。"
            },
            {
              "end" : 8,
              "id" : "6B3D9C0E-7D8A-4F1B-9C4D-3E2F1A0B9C8D",
              "speaker" : "spk1",
              "start" : 4,
              "text" : "よろしくお願いします。"
            },
            {
              "end" : 10,
              "id" : "7C4E0D1F-8E9B-4A2C-8D5E-4F3A2B1C0D9E",
              "speaker" : "room1",
              "start" : 9,
              "text" : "同じ部屋から。"
            }
          ]
        }
        """;

    [Fact]
    public void ReadsMeetingWrittenByMac()
    {
        var m = MeetingJson.Deserialize(MacMeetingJson);
        Assert.Equal("2026-11-03 1430", m.Id);
        Assert.Equal(new DateTimeOffset(2026, 11, 3, 5, 30, 0, TimeSpan.Zero), m.StartedAt);
        Assert.Equal(1234.5, m.Duration);
        Assert.Equal(MeetingStatus.Done, m.Status);
        Assert.Equal(MinutesTemplate.OneOnOne, m.Template);
        Assert.Equal("田中さん", m.DisplayName("spk1"));
        Assert.Equal("自分", m.DisplayName("me"));
        Assert.Equal("同席者1", m.DisplayName("room1"));
        Assert.Equal(["me", "spk1", "room1"], m.Speakers);
        Assert.Equal(3, m.Notes!.Count);
        Assert.Equal(MeetingNoteKind.Highlight, m.Notes[1].Kind);
        Assert.Null(m.Notes[2].Time);
        Assert.Equal("x-apple-reminder://ABC", m.ActionItems![0].ReminderId);
        Assert.Null(m.ActionItems[1].Owner);
        Assert.Null(m.AudioStartOffsets);
    }

    [Fact]
    public void WritesTheSameShapeAsMac()
    {
        var m = MeetingJson.Deserialize(MacMeetingJson);
        var json = MeetingJson.Serialize(m);
        var node = JsonNode.Parse(json)!.AsObject();
        // 秒までの UTC（Swift の .iso8601 は小数の秒を読めない）
        Assert.Equal("2026-11-03T05:30:00Z", node["startedAt"]!.GetValue<string>());
        Assert.Equal("done", node["status"]!.GetValue<string>());
        Assert.Equal("oneOnOne", node["minutesTemplate"]!.GetValue<string>());
        Assert.Equal("highlight", node["notes"]![1]!["kind"]!.GetValue<string>());
        Assert.Equal("x-apple-reminder://ABC", node["actionItems"]![0]!["reminderID"]!.GetValue<string>());
        // null は書かない（Swift の Optional は省略）。必須のキーは必ず書く
        Assert.False(node["actionItems"]![1]!.AsObject().ContainsKey("owner"));
        Assert.False(node.ContainsKey("errorMessage"));
        foreach (var key in new[] { "id", "title", "startedAt", "duration", "status", "speakerNames", "utterances" }) Assert.True(node.ContainsKey(key), key);
        foreach (var key in new[] { "id", "speaker", "start", "end", "text" }) Assert.True(node["utterances"]![0]!.AsObject().ContainsKey(key), key);
        Assert.Contains("田中さん", json);  // 日本語をエスケープしない

        // 読み直して同じになる
        var again = MeetingJson.Deserialize(json);
        Assert.Equal(MeetingJson.Serialize(again), json);
    }

    [Fact]
    public void NewMeetingIdsAndUuidsMatchMac()
    {
        var dir = TestKeys.TempDirectory();
        var store = new MeetingStore(dir);
        var date = new DateTimeOffset(2026, 11, 3, 14, 30, 12, 345, TimeSpan.FromHours(9));
        var a = store.NewMeeting(date);
        var b = store.NewMeeting(date);
        Assert.Equal(date.ToLocalTime().ToString("yyyy-MM-dd HHmm"), a.Id);
        Assert.Equal(a.Id + " (2)", b.Id);
        Assert.Equal(0, a.StartedAt.Millisecond);
        Assert.StartsWith("会議 ", a.Title);
        var u = new Utterance("me", 0, 1, "x");
        Assert.Matches("^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$", u.Id);
    }

    [Fact]
    public void SavesFilesLikeMac()
    {
        var dir = TestKeys.TempDirectory();
        var store = new MeetingStore(dir);
        var m = MeetingJson.Deserialize(MacMeetingJson);
        store.Save(m);
        var folder = Path.Combine(dir, m.Id);
        Assert.True(File.Exists(Path.Combine(folder, "meeting.json")));
        Assert.StartsWith("# 定例 — 文字起こし", File.ReadAllText(Path.Combine(folder, "transcript.md")));
        Assert.Contains("**[00:04] 田中さん**: よろしくお願いします。", File.ReadAllText(Path.Combine(folder, "transcript.md")));
        Assert.Equal(m.Minutes, File.ReadAllText(Path.Combine(folder, "minutes.md")));
        Assert.Contains("[01:05] 価格は来週", File.ReadAllText(Path.Combine(folder, "notes.md")));

        m.Notes = null;
        store.Save(m);
        Assert.False(File.Exists(Path.Combine(folder, "notes.md")));
        var loaded = Assert.Single(store.LoadAll());
        Assert.Equal(m.Id, loaded.Id);
    }

    [Fact]
    public void MarksInterruptedMeetingsAsFailed()
    {
        var store = new MeetingStore(TestKeys.TempDirectory());
        var m = store.NewMeeting(DateTimeOffset.Now);
        m.Status = MeetingStatus.Recording;
        store.Save(m);
        store.MarkInterruptedMeetings();
        var loaded = store.Load(m.Id)!;
        Assert.Equal(MeetingStatus.Failed, loaded.Status);
        Assert.Contains("me.wav", loaded.ErrorMessage);
    }
}

public class MeetingTextTests
{
    [Fact]
    public void NotesRoundTrip()
    {
        var notes = MeetingNote.Parse("[12:34] 本文\n\n[1:02:03] ★ 説明\n[00:10]★\n時刻なし\n[ab] 時刻ではない");
        Assert.Equal(5, notes.Count);
        Assert.Equal((MeetingNoteKind.Note, 754.0, "本文"), (notes[0].Kind, notes[0].Time!.Value, notes[0].Text));
        Assert.Equal((MeetingNoteKind.Highlight, 3723.0, "説明"), (notes[1].Kind, notes[1].Time!.Value, notes[1].Text));
        Assert.Equal("[00:10] ★", notes[2].Line);
        Assert.Null(notes[3].Time);
        Assert.Equal("[ab] 時刻ではない", notes[4].Text);
        Assert.Equal("[12:34] 本文\n[1:02:03] ★ 説明\n[00:10] ★\n時刻なし\n[ab] 時刻ではない", MeetingNote.ToText(notes));
    }

    [Fact]
    public void PromptMarksHighlightsAndNotes()
    {
        var m = new Meeting
        {
            Title = "定例",
            StartedAt = new DateTimeOffset(2026, 11, 3, 5, 30, 0, TimeSpan.Zero),
            Duration = 200,
            Utterances = [new("me", 0, 5, "最初。"), new("spk1", 80, 85, "大事な話。"), new("me", 150, 152, "最後。")],
            Notes = [new(MeetingNoteKind.Highlight, 100, ""), new(MeetingNoteKind.Note, null, "あとで")],
        };
        var text = MinutesPrompt.UserText(m);
        Assert.Contains("[00:00] 自分: 最初。", text);
        Assert.Contains("★ [01:20] 話者1: 大事な話。", text);
        Assert.Contains("<user_notes>\n[01:40] ★ここ重要\n[--:--] あとで\n</user_notes>", text);
        Assert.Contains(MinutesPrompt.NotesInstruction, MinutesPrompt.FullInstruction(m));
        m.Notes = null;
        Assert.DoesNotContain("<user_notes>", MinutesPrompt.UserText(m));
        Assert.DoesNotContain("★", MinutesPrompt.UserText(m));
        Assert.DoesNotContain(MinutesPrompt.NotesInstruction, MinutesPrompt.FullInstruction(m));
    }

    [Fact]
    public void MergedBlocksJoinSameSpeaker()
    {
        var m = new Meeting { Utterances = [new("me", 0, 1, "あ"), new("me", 2, 3, "い"), new("me", 9, 10, "う"), new("spk1", 11, 12, "え")] };
        var blocks = m.MergedBlocks();
        Assert.Equal(["あい", "う", "え"], blocks.Select(b => b.Text));
        Assert.Equal("あ", m.Utterances[0].Text);  // 元の発言は変えない
        Assert.Equal("1:00:00", Meeting.Clock(3600));
        Assert.Equal("59:59", Meeting.Clock(3599.9));
    }

    [Theory]
    [InlineData(MinutesTemplate.Auto, "## 話し合った内容", "## アクションアイテム")]
    [InlineData(MinutesTemplate.Regular, "## 次回までに確認すること", "## アクションアイテム")]
    [InlineData(MinutesTemplate.Sales, "## 予算・時期・決裁", "## 次のアクション")]
    [InlineData(MinutesTemplate.Brainstorm, "## 有望なアイデア", "## 次のステップ")]
    public void InstructionUsesTemplateSections(MinutesTemplate template, string section, string actionHeading)
    {
        var instruction = MinutesPrompt.SystemInstruction(template, null);
        Assert.Contains(section, instruction);
        Assert.Contains($"{actionHeading}\n{MinutesPrompt.Placeholder}", instruction);
        Assert.Contains("<action_items>", instruction);
        Assert.Contains("[{\"owner\": \"担当者\"", instruction);
    }

    [Fact]
    public void CustomTemplateWrapsUserInstruction()
    {
        var instruction = MinutesPrompt.SystemInstruction(MinutesTemplate.Custom, "## 決まったこと");
        Assert.Contains("<user_template>\n## 決まったこと\n</user_template>", instruction);
        Assert.DoesNotContain("## 話し合った内容", instruction);
        // 指示が空なら「自動」と同じ構成
        Assert.Contains("## 話し合った内容", MinutesPrompt.SystemInstruction(MinutesTemplate.Custom, "  "));
        Assert.Equal("oneOnOne", MinutesTemplate.OneOnOne.RawValue());
        Assert.Equal(MinutesTemplate.Sales, MinutesTemplates.FromRawValue("sales"));
        Assert.Null(MinutesTemplates.FromRawValue("unknown"));
    }

    [Fact]
    public void ParsesMinutesAndActionItems()
    {
        var response = """
            ## 概要
            テスト

            ## アクションアイテム
            {{ACTION_ITEMS}}

            ## 話者についてのメモ
            なし

            ```xml
            <action_items>
            ```json
            [{"owner": "話者1", "task": "見積もりを送る", "due": "2026-11-13", "due_note": null},
             {"owner": null, "task": "議題を共有する", "due": "来週中", "due_note": null},
             {"owner": "自分", "task": "  ", "due": null, "due_note": null}]
            ```
            </action_items>
            ```
            """;
        var result = MinutesPrompt.Parse(response, "定例");
        Assert.Equal(2, result.ActionItems.Count);
        Assert.Equal("2026-11-13", result.ActionItems[0].Due);
        Assert.Null(result.ActionItems[1].Due);
        Assert.Equal("来週中", result.ActionItems[1].DueNote);
        Assert.StartsWith("# 定例 — 議事録\n\n## 概要", result.Markdown);
        Assert.Contains("- [ ] 見積もりを送る（担当: 話者1 / 期限: 11/13 (金)）\n- [ ] 議題を共有する（期限: 来週中）", result.Markdown);
        Assert.DoesNotContain("action_items", result.Markdown);
        Assert.DoesNotContain("```", result.Markdown);
    }

    [Fact]
    public void BrokenActionItemsFallBackToMarkdown()
    {
        var result = MinutesPrompt.Parse("## TODO\n- [ ] 資料を直す（担当: 自分 / 期限: 不明）\n- [ ] なし\n\n<action_items>\n[{broken\n</action_items>", "x");
        var item = Assert.Single(result.ActionItems);
        Assert.Equal(("資料を直す", "自分", (string?)null), (item.Task, item.Owner, item.DueNote));

        var placeholder = MinutesPrompt.Parse("## アクションアイテム\n{{ACTION_ITEMS}}\n<action_items>[{</action_items>", "x");
        Assert.Contains("読み取れませんでした", placeholder.Markdown);
        Assert.Contains("なし", MinutesPrompt.Parse("## アクションアイテム\n{{ACTION_ITEMS}}\n<action_items>[]</action_items>", "x").Markdown);
    }
}

public class MeetingProcessorTests
{
    private static TranscribedPhrase Phrase(MeetingChannel channel, params (string Text, double Start, double End)[] words) =>
        new(channel, words[0].Start, words[^1].End, string.Concat(words.Select(w => w.Text)), words.Select(w => new TimedWord(w.Text, w.Start, w.End)).ToList());

    [Fact]
    public void SplitsOthersBySpeakerTurns()
    {
        var others = new[] { Phrase(MeetingChannel.Others, ("こんにちは", 10, 11), ("田中です", 11, 12), ("佐藤です", 13, 14), ("よろしく", 14, 15)) };
        var turns = new[] { new SpeakerTurn("7", 9.5, 12.2), new SpeakerTurn("3", 12.8, 15.5) };
        var me = new[] { Phrase(MeetingChannel.Me, ("始めます", 1, 2)) };
        var result = MeetingProcessor.BuildUtterances(me, others, turns);
        Assert.Equal([("me", "始めます"), ("spk1", "こんにちは田中です"), ("spk2", "佐藤ですよろしく")], result.Select(u => (u.Speaker, u.Text)));
    }

    [Fact]
    public void WithoutTurnsOthersIsOnePerson()
    {
        var result = MeetingProcessor.BuildUtterances([], [Phrase(MeetingChannel.Others, ("はい", 1, 2))], []);
        Assert.Equal("others", Assert.Single(result).Speaker);
    }

    [Fact]
    public void RemovesLongEchoButKeepsShortFragments()
    {
        var others = new[] { Phrase(MeetingChannel.Others, ("来週の定例は金曜日に変更します", 10, 13)) };
        var me = new[]
        {
            // スピーカーから回り込んだ相手の声
            Phrase(MeetingChannel.Me, ("来週の定例は金曜日に変更します", 10.1, 13.1)),
            // 相手と重なるが、短い自分の相づち
            Phrase(MeetingChannel.Me, ("します", 12.9, 13.2)),
            Phrase(MeetingChannel.Me, ("了解しました", 20, 21)),
        };
        var result = MeetingProcessor.BuildUtterances(me, others, []);
        Assert.Equal(["others:来週の定例は金曜日に変更します", "me:します", "me:了解しました"], result.Select(u => $"{u.Speaker}:{u.Text}"));
    }

    [Fact]
    public void AbsorbsShortEdgesIntoNeighbor()
    {
        var pieces = new List<Utterance> { new("a", 0, 5, "よろしくお願いします。検索は"), new("b", 5, 5.2, "でした。") };
        var merged = MeetingProcessor.AbsorbShortEdges(pieces);
        Assert.Equal(("a", "よろしくお願いします。検索はでした。"), (Assert.Single(merged).Speaker, merged[0].Text));
        var kept = MeetingProcessor.AbsorbShortEdges([new("a", 0, 3, "長い発言です"), new("b", 3, 6, "別の人の長い発言")]);
        Assert.Equal(2, kept.Count);
    }

    [Fact]
    public void SpeakerInGapPrefersNextAfterPause()
    {
        var turns = new[] { new SpeakerTurn("A", 0, 5), new SpeakerTurn("B", 6, 10) };
        Assert.Equal("A", MeetingProcessor.SpeakerAt(3, null, turns));
        Assert.Equal("B", MeetingProcessor.SpeakerAt(5.6, 5.5, turns));
        Assert.Equal("A", MeetingProcessor.SpeakerAt(5.2, 5.1, turns));
        Assert.Equal("B", MeetingProcessor.SpeakerAt(12, null, turns));
        Assert.Equal("others", MeetingProcessor.SpeakerAt(1, null, []));
    }

    [Fact]
    public void PhrasesAddChannelOffset()
    {
        var phrases = MeetingProcessor.Phrases([new TimedSegment(1, 2, "はい"), new TimedSegment(3, 4, "いいえ", [new TimedWord("いい", 3, 3.5), new TimedWord("え", 3.5, 4)])],
            MeetingChannel.Others, 1.5);
        Assert.Equal((2.5, 3.5), (phrases[0].Start, phrases[0].End));
        Assert.Equal(("はい", 2.5), (phrases[0].Words.Single().Text, phrases[0].Words[0].Start));
        Assert.Equal(5.0, phrases[1].Words[1].Start);
    }
}

public class MeetingAudioTests
{
    private static float[] Tone(double seconds, double amplitude = 0.3) =>
        Enumerable.Range(0, (int)(seconds * AudioFormat.SampleRate)).Select(i => (float)(Math.Sin(i * 0.1) * amplitude)).ToArray();

    [Fact]
    public void TimelineFillsLoopbackGaps()
    {
        var t = new ChannelTimeline();
        Assert.Equal(0, t.Advance(1.1, 1600));  // 最初の音: 1.0 秒から
        Assert.Equal(1.0, t.StartOffset!.Value, 3);
        Assert.Equal(0, t.Advance(1.21, 1600));  // ゆらぎは埋めない
        var silence = t.Advance(5.2, 1600);  // 何も鳴っていなかった約 3.9 秒
        Assert.InRange(silence / 16000.0, 3.8, 4.0);
        Assert.Equal(5.2 - 1.0, t.WrittenSeconds, 1);
    }

    [Fact]
    public void WavStreamWriterWritesReadableWav()
    {
        var path = Path.Combine(TestKeys.TempDirectory(), "me.wav");
        using (var writer = new WavStreamWriter(path))
        {
            writer.Write(Tone(1));
            writer.WriteSilence(8000);
            Assert.Equal(24000, writer.SampleCount);
        }
        var (samples, rate) = WavFile.Decode(File.ReadAllBytes(path));
        Assert.Equal(16000, rate);
        Assert.Equal(24000, samples.Length);
        Assert.Equal(0, samples[^1]);
    }

    [Fact]
    public void ChunksCutAtQuietPoint()
    {
        // 9 秒の音、0.5 秒の無音、9 秒の音 → 10 秒ごとに分けると、無音のところで切れる
        var samples = Tone(9).Concat(new float[8000]).Concat(Tone(9)).ToArray();
        var starts = MeetingAudio.ChunkStarts(samples, 10, search: 3);
        Assert.Equal(2, starts.Count);
        Assert.InRange(starts[1] / 16000.0, 9.0, 9.5);
        Assert.Single(MeetingAudio.ChunkStarts(Tone(5), 10));
        Assert.True(MeetingAudio.IsNearlySilent(new float[16000]));
        Assert.False(MeetingAudio.IsNearlySilent(Tone(1)));
    }

    [Fact]
    public void SnapMovesWordsOutOfLeadingSilence()
    {
        // 0〜3 秒は無音、3〜5 秒に声
        var samples = new float[48000].Concat(Tone(2)).ToArray();
        var segment = new TimedSegment(0, 5, "よろしくお願いします", [new TimedWord("よろしく", 0.5, 2.0), new TimedWord("お願いします", 3.5, 4.8)]);
        var snapped = Assert.Single(MeetingAudio.SnapToSpeech([segment], samples));
        Assert.InRange(snapped.Start, 2.95, 3.05);
        Assert.InRange(snapped.Words[0].Start, 2.95, 3.05);
        Assert.True(snapped.Words[0].End > snapped.Words[0].Start);
        Assert.Equal(3.5, snapped.Words[1].Start);
    }
}

public class GeminiSegmentTranscriberTests
{
    [Fact]
    public void ParsesSegmentsAndClampsTimes()
    {
        var json = """{"segments":[{"start":"00:01.5","end":"00:03.0","text":" はい "},{"start":"x","end":"1","text":"捨てる"},{"start":"00:09.0","end":"00:08.0","text":"逆"},{"start":"00:02.0","end":"00:30.0","text":"戻る"},{"start":"00:04","end":"00:05","text":""}]}""";
        var segments = GeminiSegmentTranscriber.ParseSegments(json, duration: 10);
        Assert.Equal(3, segments.Count);
        Assert.Equal((1.5, 3.0, "はい"), (segments[0].Start, segments[0].End, segments[0].Text));
        Assert.Equal((9.0, 10.0), (segments[1].Start, segments[1].End));
        Assert.Equal((10.0, 10.0), (segments[2].Start, segments[2].End));  // 前の区間より 5 秒以上戻ったので、直前の終わりにそろえる
        Assert.Equal(83.4, GeminiSegmentTranscriber.ParseTime("01:23.4")!.Value, 3);
        Assert.Equal(3723, GeminiSegmentTranscriber.ParseTime("1:02:03"));
        Assert.Equal(12.5, GeminiSegmentTranscriber.ParseTime("12.5"));
        Assert.Throws<GeminiException>(() => GeminiSegmentTranscriber.ParseSegments("[]", 10));
    }

    [Fact]
    public async Task SendsAudioWithSchemaAndShiftsTimes()
    {
        var handler = new FakeHandler((_, _) => FakeHandler.Json(FakeHandler.TextResponse("""{"segments":[{"start":"00:00.5","end":"00:01.5","text":"はい"}]}""")));
        var client = new GeminiClient(new GeminiAuth.ApiKey("test-key"), new HttpClient(handler));
        var transcriber = new GeminiSegmentTranscriber(() => client, () => "gemini-test");
        var samples = Enumerable.Range(0, 32000).Select(i => (float)Math.Sin(i * 0.05) * 0.2f).ToArray();
        var progress = new List<string>();
        var segments = await transcriber.TranscribeSegmentsAsync(samples, new TranscriptionContext("ja-JP", ["Hanasu"], ""), new InlineProgress<string>(progress.Add));
        Assert.Equal("はい", Assert.Single(segments).Text);
        var body = JsonNode.Parse(Assert.Single(handler.Requests).Body!)!;
        Assert.Equal("application/json", body["generationConfig"]!["responseMimeType"]!.GetValue<string>());
        Assert.Equal("ARRAY", body["generationConfig"]!["responseSchema"]!["properties"]!["segments"]!["type"]!.GetValue<string>());
        Assert.Equal("audio/wav", body["contents"]![0]!["parts"]![0]!["inlineData"]!["mimeType"]!.GetValue<string>());
        Assert.Contains("ユーザー辞書: Hanasu", body["contents"]![0]!["parts"]![1]!["text"]!.GetValue<string>());
        Assert.Contains("時刻つきの区間", body["systemInstruction"]!["parts"]![0]!["text"]!.GetValue<string>());
        Assert.Equal(["0/1", "1/1"], progress);
    }

    [Fact]
    public async Task MissingCredentialsFailBeforeRecording()
    {
        var transcriber = new GeminiSegmentTranscriber(() => null, () => "m");
        await Assert.ThrowsAsync<TranscriptionException>(() => transcriber.PrepareAsync(new TranscriptionContext("ja-JP", [], "")));
    }
}

public class WhisperWordTests
{
    [Fact]
    public void JoinsBrokenTokensAndRemovesAnnotations()
    {
        // 「検索」が 4 つの文字化けトークンに割れた例（Whisper.net は 1 文字の途中のトークンを U+FFFD にする）
        var tokens = new List<(string, double, double)>
        {
            ("[_BEG_]", 0, 0), ("(", 0, 0.2), ("字", 0.2, 0.5), ("幕", 0.5, 0.8), (")", 0.8, 1.0), (" ", 1, 1),
            ("今日は", 1.0, 1.5), ("\uFFFD", 1.5, 1.6), ("\uFFFD", 1.6, 1.7), ("\uFFFD", 1.7, 1.8), ("\uFFFD", 1.8, 2.0), ("です", 2.0, 2.4), ("。", 2.4, 2.4), ("[_TT_120]", 2.4, 2.4),
        };
        var (text, words) = WhisperBatchTranscriber.Words("(字幕) 今日は検索です。", tokens, 0, 2.4);
        Assert.Equal("今日は検索です。", text);
        Assert.Equal(["今日は", "検索", "です", "。"], words.Select(w => w.Text));
        Assert.Equal((1.5, 2.0), (words[1].Start, words[1].End));
    }

    [Fact]
    public void FallsBackWhenTokensDoNotMatch()
    {
        var (text, words) = WhisperBatchTranscriber.Words("こんにちは", [("さようなら", 0, 1)], 0, 1);
        Assert.Equal("こんにちは", text);
        Assert.Empty(words);
        Assert.Equal("ご視聴ありがとう", WhisperText.RemoveAnnotations("（拍手）ご視聴ありがとう"));
    }
}

public class MeetingSettingsTests
{
    [Fact]
    public void NormalizesMeetingSettings()
    {
        var s = new AppSettings { MeetingEngine = TranscriptionEngine.Windows, MeetingHotKey = HotKeyCombo.DefaultDictation, MeetingMinutesTemplate = "nope", MeetingMinutesModel = " " };
        SettingsStore.Normalize(s);
        Assert.Equal(TranscriptionEngine.Whisper, s.MeetingEngine);
        Assert.Equal(HotKeyCombo.DefaultMeeting, s.MeetingHotKey);
        Assert.Equal(HotKeyCombo.DefaultHighlight, s.HighlightHotKey);
        Assert.Equal("auto", s.MeetingMinutesTemplate);
        Assert.Equal("gemini-3.8-flash", s.MeetingMinutesModel);
        Assert.Null(HotKeyCombo.DefaultMeeting.Validate());
        Assert.Equal("Ctrl + Alt + Shift + M", HotKeyCombo.DefaultMeeting.DisplayString);
    }

    [Fact]
    public void MeetingSettingsSurviveSaveAndLoad()
    {
        var store = new SettingsStore(Path.Combine(TestKeys.TempDirectory(), "settings.json"));
        var s = new AppSettings { MeetingEngine = TranscriptionEngine.Gemini, KeepMeetingAudio = false, MeetingsDirectory = @"D:\会議", MeetingMinutesTemplate = "sales" };
        store.Save(s);
        var loaded = store.Load();
        Assert.Equal((TranscriptionEngine.Gemini, false, @"D:\会議", "sales"), (loaded.MeetingEngine, loaded.KeepMeetingAudio, loaded.MeetingsDirectory, loaded.MeetingMinutesTemplate));
    }
}

// 確かめ方: REQ-MTG-012
public class HighlightContextTests
{
    [Fact]
    public void ListsTheConversationAroundEachHighlight()
    {
        var meeting = new Meeting
        {
            Utterances =
            [
                new Utterance("me", 10, 14, "最初の話"),
                new Utterance("spk1", 75, 80, "価格は 3 割引きで"),
                new Utterance("me", 100, 104, "それで進めましょう"),
                new Utterance("spk1", 200, 205, "関係ない話"),
            ],
            Notes =
            [
                new MeetingNote(MeetingNoteKind.Highlight, 105, ""),
                new MeetingNote(MeetingNoteKind.Note, 106, "メモは出さない"),
                new MeetingNote(MeetingNoteKind.Highlight, 12, "最初"),
                new MeetingNote(MeetingNoteKind.Highlight, null, "時刻なし"),
            ],
            SpeakerNames = { ["spk1"] = "田中" },
        };
        var contexts = meeting.HighlightContexts();
        // 時刻の順。時刻のない印は出さない
        Assert.Equal([12.0, 105.0], contexts.Select(c => c.Note.Time!.Value));
        Assert.Equal(["最初の話"], contexts[0].Blocks.Select(b => b.Text));
        // 30 秒前（75 秒）〜15 秒後（120 秒）にかかる発言
        Assert.Equal(["価格は 3 割引きで", "それで進めましょう"], contexts[1].Blocks.Select(b => b.Text));

        var text = meeting.HighlightContextText();
        Assert.StartsWith("★ 00:12  最初\n    [00:10] 自分: 最初の話", text);
        Assert.Contains("★ 01:45  ここ重要\n    [01:15] 田中: 価格は 3 割引きで\n    [01:40] 自分: それで進めましょう", text);
        Assert.DoesNotContain("関係ない話", text);
        Assert.DoesNotContain("メモは出さない", text);
    }

    [Fact]
    public void ExplainsWhenThereAreNoHighlights()
    {
        Assert.StartsWith("「ここ重要」の印はありません", new Meeting().HighlightContextText());
        var lonely = new Meeting { Notes = [new MeetingNote(MeetingNoteKind.Highlight, 600, "")] };
        Assert.Contains("この前後（30 秒前〜15 秒後）の発言はありません", lonely.HighlightContextText());
    }
}

// 確かめ方: REQ-MTG-012
public class HighlightUndoTests
{
    private static Meeting WithNotes(params MeetingNote[] notes) => new() { Notes = notes.ToList() };

    [Fact]
    public void LatestHighlightWithinTenSecondsCanBeUndone()
    {
        var old = new MeetingNote(MeetingNoteKind.Highlight, 100, "");
        var recent = new MeetingNote(MeetingNoteKind.Highlight, 115, "大事");
        var note = new MeetingNote(MeetingNoteKind.Note, 118, "メモは対象外");
        var meeting = WithNotes(old, recent, note);
        Assert.Same(recent, meeting.UndoableHighlight(118));
        // ちょうど 10 秒までは取り消せる
        Assert.Same(recent, meeting.UndoableHighlight(125));
        Assert.Null(meeting.UndoableHighlight(125.1));
        // 古い印は、新しい印が時間切れになっても取り消せない
        Assert.Null(meeting.UndoableHighlight(130));
    }

    [Fact]
    public void NotesAndHighlightsWithoutTimeAreNotUndoable()
    {
        var meeting = WithNotes(new MeetingNote(MeetingNoteKind.Note, 5, "メモ"), new MeetingNote(MeetingNoteKind.Highlight, null, "記録後"));
        Assert.Null(meeting.UndoableHighlight(6));
        Assert.Null(new Meeting().UndoableHighlight(0));
    }
}

public class MeetingControllerTests
{
    private sealed class FakeRecorder(MeetingChannel channel, float[] audio, double offset, bool failStart = false) : IMeetingChannelRecorder
    {
        private string? path;
        public MeetingChannel Channel => channel;
        public double? StartOffset { get; private set; }
        public double Level => 0;
        public bool Stopped { get; private set; }
        public event EventHandler<Exception>? Faulted { add { } remove { } }

        public Task StartAsync(string wavPath, Func<double> elapsed, CancellationToken cancellationToken = default)
        {
            if (failStart) throw new TranscriptionException("録音できません");
            path = wavPath;
            return Task.CompletedTask;
        }

        public Task StopAsync()
        {
            using (var writer = new WavStreamWriter(path!)) writer.Write(audio);
            StartOffset = offset;
            Stopped = true;
            return Task.CompletedTask;
        }

        public ValueTask DisposeAsync() => ValueTask.CompletedTask;
    }

    private sealed class FakeTranscriber(bool failPrepare = false) : ISegmentTranscriber
    {
        public string DisplayName => "Fake";
        public List<string> Contexts { get; } = new();

        public Task PrepareAsync(TranscriptionContext context, CancellationToken cancellationToken = default) =>
            failPrepare ? throw new TranscriptionException("モデルがありません") : Task.CompletedTask;

        public Task<IReadOnlyList<TimedSegment>> TranscribeSegmentsAsync(float[] samples, TranscriptionContext context,
            IProgress<string>? progress = null, CancellationToken cancellationToken = default)
        {
            // 大きい音（自分）と小さい音（相手）で返す文を変える
            var loud = MeetingAudio.Rms(samples) > 0.1;
            return Task.FromResult<IReadOnlyList<TimedSegment>>([new TimedSegment(0.2, 0.8, loud ? "自分の発言" : "相手の発言")]);
        }
    }

    private sealed class FakeDiarizer : ISpeakerDiarizer
    {
        public Task<IReadOnlyList<SpeakerTurn>> DiarizeAsync(float[] samples, IProgress<string>? progress = null, CancellationToken cancellationToken = default) =>
            Task.FromResult<IReadOnlyList<SpeakerTurn>>([new SpeakerTurn("0", 0, 1)]);
    }

    private static float[] Tone(double amplitude) => Enumerable.Range(0, 16000).Select(i => (float)(Math.Sin(i * 0.1) * amplitude)).ToArray();

    private static (MeetingController Controller, AppSettings Settings, List<MeetingNotice> Notices) Make(
        bool failMic = false, bool failLoopback = false, bool failPrepare = false, Func<AppSettings, GeminiClient?>? minutes = null)
    {
        var settings = new AppSettings { MeetingsDirectory = TestKeys.TempDirectory(), MeetingMinutesTemplate = "regular" };
        var controller = new MeetingController(new MeetingServices
        {
            Settings = () => settings,
            CreateMicRecorder = _ => new FakeRecorder(MeetingChannel.Me, Tone(0.5), 0.1, failMic),
            CreateLoopbackRecorder = _ => new FakeRecorder(MeetingChannel.Others, Tone(0.05), 2.0, failLoopback),
            CreateTranscriber = _ => new FakeTranscriber(failPrepare),
            CreateDiarizer = _ => new FakeDiarizer(),
            CreateMinutesClient = minutes ?? (_ => null),
        });
        var notices = new List<MeetingNotice>();
        controller.Notice += (_, n) => notices.Add(n);
        return (controller, settings, notices);
    }

    [Fact]
    public async Task RecordsAndProcessesMeeting()
    {
        var (controller, settings, notices) = Make();
        var states = new List<MeetingState>();
        controller.StateChanged += (_, s) => states.Add(s);
        await controller.StartAsync();
        Assert.Equal(MeetingState.Recording, controller.State);
        var meeting = controller.Current!;
        Assert.Equal("regular", meeting.MinutesTemplateId);
        controller.AddNote("  メモ  ", 1.5);
        controller.AddHighlight("大事");
        controller.AddNote("   ", null);
        await controller.StopAsync();

        Assert.Equal([MeetingState.Starting, MeetingState.Recording, MeetingState.Processing, MeetingState.Idle], states);
        var saved = controller.Store(settings).Load(meeting.Id)!;
        Assert.Equal(MeetingStatus.Done, saved.Status);
        Assert.Equal([("me", "自分の発言", 0.3), ("spk1", "相手の発言", 2.2)], saved.Utterances.Select(u => (u.Speaker, u.Text, Math.Round(u.Start, 1))));
        Assert.Equal(2.0, saved.AudioStartOffsets!["others"]);
        Assert.Equal(["メモ", "大事"], saved.Notes!.Select(n => n.Text));
        Assert.Equal(MeetingNoteKind.Highlight, saved.Notes![1].Kind);
        // 認証情報がないので議事録は作らず、理由を残す
        Assert.Null(saved.Minutes);
        Assert.Contains("認証情報", saved.ErrorMessage);
        Assert.True(File.Exists(controller.Store(settings).AudioPath(saved, MeetingChannel.Me)));
        Assert.Contains(notices, n => n.Title.StartsWith("会議の記録"));
    }

    // 確かめ方: REQ-MTG-012
    [Fact]
    public async Task UndoesARecentHighlightWhileRecording()
    {
        var (controller, settings, _) = Make();
        await controller.StartAsync();
        var meeting = controller.Current!;
        controller.AddNote("メモ", 0);
        controller.AddHighlight("押し間違い");
        var undoable = Assert.IsType<MeetingNote>(controller.UndoableHighlight);
        Assert.Equal("押し間違い", undoable.Text);
        // メモや知らない ID は消さない
        Assert.False(controller.UndoHighlight(meeting.Notes![0].Id));
        Assert.False(controller.UndoHighlight("unknown"));
        Assert.True(controller.UndoHighlight(undoable.Id));
        Assert.Null(controller.UndoableHighlight);
        Assert.Equal(["メモ"], controller.Store(settings).Load(meeting.Id)!.Notes!.Select(n => n.Text));
        await controller.StopAsync();
        // 記録中でなければ取り消せない
        Assert.Null(controller.UndoableHighlight);
        Assert.False(controller.UndoHighlight(undoable.Id));
    }

    [Fact]
    public async Task DeletesAudioWhenNotKept()
    {
        var (controller, settings, _) = Make();
        settings.KeepMeetingAudio = false;
        settings.MakeMeetingMinutes = false;
        await controller.StartAsync();
        var meeting = controller.Current!;
        await controller.StopAsync();
        var saved = controller.Store(settings).Load(meeting.Id)!;
        Assert.Null(saved.ErrorMessage);
        Assert.False(File.Exists(controller.Store(settings).AudioPath(saved, MeetingChannel.Me)));
    }

    [Fact]
    public async Task MakesMinutesWithGemini()
    {
        var handler = new FakeHandler((_, _) => FakeHandler.Json(FakeHandler.TextResponse("## 概要\nテスト\n\n## アクションアイテム\n{{ACTION_ITEMS}}\n<action_items>[{\"owner\":\"自分\",\"task\":\"送る\"}]</action_items>")));
        var (controller, settings, _) = Make(minutes: _ => new GeminiClient(new GeminiAuth.ApiKey("k"), new HttpClient(handler)));
        await controller.StartAsync();
        var meeting = controller.Current!;
        await controller.StopAsync();
        var saved = controller.Store(settings).Load(meeting.Id)!;
        Assert.Contains("- [ ] 送る（担当: 自分）", saved.Minutes);
        Assert.Equal("送る", Assert.Single(saved.ActionItems!).Task);
        var body = JsonNode.Parse(Assert.Single(handler.Requests).Body!)!;
        Assert.Contains("gemini-3.8-flash", Assert.Single(handler.Requests).Request.RequestUri!.ToString());
        Assert.Contains("## 進捗", body["systemInstruction"]!["parts"]![0]!["text"]!.GetValue<string>());  // 「定例」の型
        Assert.Contains("[00:00] 自分: 自分の発言", body["contents"]![0]!["parts"]![0]!["text"]!.GetValue<string>());

        // 型を変えて作り直す
        await controller.RegenerateMinutesAsync(saved, MinutesTemplate.Sales);
        Assert.Equal("sales", controller.Store(settings).Load(meeting.Id)!.MinutesTemplateId);
    }

    [Fact]
    public async Task DoesNotStartWhenTranscriberIsNotReady()
    {
        var (controller, settings, notices) = Make(failPrepare: true);
        await controller.StartAsync();
        Assert.Equal(MeetingState.Idle, controller.State);
        Assert.Empty(controller.Store(settings).LoadAll());
        Assert.Contains("モデルがありません", Assert.Single(notices).Message);
    }

    [Fact]
    public async Task ContinuesWithMicWhenLoopbackFails()
    {
        var (controller, _, notices) = Make(failLoopback: true);
        await controller.StartAsync();
        Assert.Equal(MeetingState.Recording, controller.State);
        Assert.Contains(notices, n => n.Title.Contains("PC の音"));
        await controller.StopAsync();
        Assert.Equal(MeetingState.Idle, controller.State);
    }

    [Fact]
    public async Task FailedMicMarksMeetingFailed()
    {
        var (controller, settings, notices) = Make(failMic: true);
        await controller.StartAsync();
        Assert.Equal(MeetingState.Idle, controller.State);
        Assert.Equal(MeetingStatus.Failed, Assert.Single(controller.Store(settings).LoadAll()).Status);
        Assert.Contains("録音できません", notices.Last().Message);
    }

    [Fact]
    public async Task DoesNotStartWhileDictating()
    {
        var (controller, _, notices) = Make();
        controller.CanStart = () => false;
        await controller.StartAsync();
        Assert.Equal(MeetingState.Idle, controller.State);
        Assert.Single(notices);
    }
}
