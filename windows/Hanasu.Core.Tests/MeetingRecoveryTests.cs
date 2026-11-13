using System.Buffers.Binary;
using Hanasu.Core.Audio;
using Hanasu.Core.Meetings;
using Hanasu.Core.Settings;
using Hanasu.Core.Transcription;

namespace Hanasu.Core.Tests;

// 確かめ方: REQ-MTG-128
// 設計判断: DEC-MTG-157, DEC-MTG-158, DEC-MTG-159
/// <summary>
/// 記録中に落ちた会議を、残った録音から作り直すこと（WAV のヘッダーの直し・ボタンを出す条件・長さとオフレコ・先頭のずれの保存・作り直しの流れ）。
/// どれも一時フォルダの中だけで確かめる
/// </summary>
public class MeetingRecoveryTests
{
    // MARK: - 偽物

    /// <summary>始めたときから先頭のずれが分かる録音機（StartOffset はテストから変えられる）。止めたときに audio を書く</summary>
    private sealed class LiveRecorder(MeetingChannel channel, float[] audio, double? offset) : IMeetingChannelRecorder
    {
        private string? path;
        public MeetingChannel Channel => channel;
        public double? StartOffset { get; set; } = offset;
        public double Level => 0;
        public event EventHandler<Exception>? Faulted { add { } remove { } }

        public Task StartAsync(string wavPath, Func<double> elapsed, CancellationToken cancellationToken = default)
        {
            path = wavPath;
            return Task.CompletedTask;
        }

        public Task StopAsync()
        {
            using (var writer = new WavStreamWriter(path!)) writer.Write(audio);
            return Task.CompletedTask;
        }

        public ValueTask DisposeAsync() => ValueTask.CompletedTask;
    }

    /// <summary>大きい音は「自分の発言」、小さい音は「相手の発言」。fail ならどのチャンネルも失敗。gate を渡すと、それが開くまで返さない</summary>
    private sealed class FakeTranscriber(bool fail = false, bool failPrepare = false, Task? gate = null, TaskCompletionSource? entered = null) : ISegmentTranscriber
    {
        public string DisplayName => "Fake";

        public Task PrepareAsync(TranscriptionContext context, CancellationToken cancellationToken = default) =>
            failPrepare ? throw new TranscriptionException("モデルがありません") : Task.CompletedTask;

        public async Task<IReadOnlyList<TimedSegment>> TranscribeSegmentsAsync(float[] samples, TranscriptionContext context,
            IProgress<string>? progress = null, CancellationToken cancellationToken = default)
        {
            entered?.TrySetResult();
            if (gate is not null) await gate;
            if (fail) throw new TranscriptionException("文字起こしできませんでした");
            var loud = MeetingAudio.Rms(samples) > 0.1;
            return [new TimedSegment(0.2, 0.8, loud ? "自分の発言" : "相手の発言")];
        }
    }

    private static float[] Tone(double amplitude, double seconds = 1) =>
        Enumerable.Range(0, (int)(16000 * seconds)).Select(i => (float)(Math.Sin(i * 0.1) * amplitude)).ToArray();

    private static (MeetingController Controller, AppSettings Settings, List<MeetingNotice> Notices) MakeController(
        Func<ISegmentTranscriber>? transcriber = null, LiveRecorder? mic = null, LiveRecorder? loopback = null)
    {
        var settings = new AppSettings { MeetingsDirectory = TestKeys.TempDirectory(), MakeMeetingMinutes = false };
        var controller = new MeetingController(new MeetingServices
        {
            Settings = () => settings,
            CreateMicRecorder = _ => mic ?? new LiveRecorder(MeetingChannel.Me, Tone(0.5), 0.1),
            CreateLoopbackRecorder = _ => loopback ?? new LiveRecorder(MeetingChannel.Others, Tone(0.05), 2.0),
            CreateTranscriber = _ => transcriber?.Invoke() ?? new FakeTranscriber(),
            CreateMinutesClient = _ => null,
        });
        var notices = new List<MeetingNotice>();
        controller.Notice += (_, n) => notices.Add(n);
        return (controller, settings, notices);
    }

    /// <summary>WAV のヘッダーの長さ（RIFF と data）を dataLength にする（落ちて古いまま残ったヘッダーのまね）</summary>
    private static void SetHeaderLength(string path, int dataLength)
    {
        var bytes = File.ReadAllBytes(path);
        BinaryPrimitives.WriteInt32LittleEndian(bytes.AsSpan(4), 36 + dataLength);
        BinaryPrimitives.WriteInt32LittleEndian(bytes.AsSpan(40), dataLength);
        File.WriteAllBytes(path, bytes);
    }

    /// <summary>
    /// 記録中に落ちて起動し直したあとの会議を置く: 状態は「失敗」（記録の途中で終了）、発言 0 件、長さ 0、
    /// 記録中に保存した先頭のずれ、メモ、終わっていないオフレコ、「録音を削除」がオン。
    /// 自分の録音（0.1 秒後から 1 秒）はヘッダーが古く（半分）、相手の録音（2 秒後から 3 秒）はヘッダーの長さが 0
    /// </summary>
    private static Meeting PlaceCrashedMeeting(MeetingStore store)
    {
        var meeting = store.NewMeeting(DateTimeOffset.Now);
        meeting.Status = MeetingStatus.Failed;
        meeting.ErrorMessage = Core.Properties.Strings.Meeting_Interrupted;
        meeting.AudioStartOffsets = new Dictionary<string, double> { ["me"] = 0.1, ["others"] = 2.0 };
        meeting.Notes = [new MeetingNote(MeetingNoteKind.Note, 0.4, "メモ"), new MeetingNote(MeetingNoteKind.Highlight, 0.6, "大事")];
        meeting.OffRecord = [new OffRecordSpan(0.2, 0.3), new OffRecordSpan(0.5)];
        meeting.DeleteAudioAfterTranscription = true;
        store.Save(meeting);
        var me = store.AudioPath(meeting, MeetingChannel.Me);
        File.WriteAllBytes(me, WavFile.Encode(Tone(0.5)));
        SetHeaderLength(me, 16000);
        var others = store.AudioPath(meeting, MeetingChannel.Others);
        File.WriteAllBytes(others, WavFile.Encode(Tone(0.05, 3)));
        SetHeaderLength(others, 0);
        return meeting;
    }

    // MARK: - WAV のヘッダーを直す（DEC-MTG-159）

    [Fact]
    public void RepairHeaderFixesZeroAndStaleLengths()
    {
        var dir = TestKeys.TempDirectory();
        foreach (var stale in new[] { 0, 8000 })
        {
            var path = Path.Combine(dir, $"stale{stale}.wav");
            File.WriteAllBytes(path, WavFile.Encode(Tone(0.5)));
            SetHeaderLength(path, stale);
            // 直す前は、ヘッダーの長さまでしか読めない
            Assert.Equal(stale / 2, WavFile.Decode(File.ReadAllBytes(path)).Samples.Length);
            Assert.True(WavStreamWriter.RepairHeader(path));
            var (samples, rate) = WavFile.Decode(File.ReadAllBytes(path));
            Assert.Equal((16000, 16000), (samples.Length, rate));
            Assert.Equal(WavFile.Encode(Tone(0.5)), File.ReadAllBytes(path));
        }
    }

    [Fact]
    public void RepairHeaderLeavesCorrectHeaderAlone()
    {
        var path = Path.Combine(TestKeys.TempDirectory(), "ok.wav");
        using (var writer = new WavStreamWriter(path)) writer.Write(Tone(0.5));
        var before = File.ReadAllBytes(path);
        var written = File.GetLastWriteTimeUtc(path);
        Assert.False(WavStreamWriter.RepairHeader(path));
        Assert.Equal(before, File.ReadAllBytes(path));
        Assert.Equal(written, File.GetLastWriteTimeUtc(path));
        // 書きかけの半端な 1 バイトは数えない（2 バイト単位に切り下げ）
        File.AppendAllText(path, "x");
        Assert.False(WavStreamWriter.RepairHeader(path));
        Assert.Equal(16000, WavFile.Decode(File.ReadAllBytes(path)).Samples.Length);
        // ないファイルは何もしない
        Assert.False(WavStreamWriter.RepairHeader(Path.Combine(TestKeys.TempDirectory(), "none.wav")));
    }

    [Fact]
    public void WavSecondsIgnoresTheHeaderLength()
    {
        var dir = TestKeys.TempDirectory();
        var path = Path.Combine(dir, "me.wav");
        File.WriteAllBytes(path, WavFile.Encode(Tone(0.5, 1.5)));
        SetHeaderLength(path, 0);
        Assert.Equal(1.5, MeetingRecovery.WavSeconds(path), 6);
        // 空の WAV・WAV でないファイル・ないファイルは 0
        var empty = Path.Combine(dir, "empty.wav");
        using (new WavStreamWriter(empty)) { }
        Assert.Equal(0, MeetingRecovery.WavSeconds(empty));
        var notWav = Path.Combine(dir, "me.m4a");
        File.WriteAllBytes(notWav, new byte[1024]);
        Assert.Equal(0, MeetingRecovery.WavSeconds(notWav));
        Assert.Equal(0, MeetingRecovery.WavSeconds(Path.Combine(dir, "none.wav")));
    }

    // MARK: - ボタンを出す条件・長さ・オフレコ（DEC-MTG-158）

    [Fact]
    public void CanRecoverOnlyWithoutUtterancesAndWithReadableAudio()
    {
        var audio = new Dictionary<MeetingChannel, double> { [MeetingChannel.Me] = 12.5 };
        var none = new Dictionary<MeetingChannel, double>();
        var zero = new Dictionary<MeetingChannel, double> { [MeetingChannel.Me] = 0, [MeetingChannel.Others] = 0 };
        // 状態（失敗・完了）では決めない
        Assert.True(MeetingRecovery.CanRecover(new Meeting { Status = MeetingStatus.Failed }, audio, busy: false));
        Assert.True(MeetingRecovery.CanRecover(new Meeting { Status = MeetingStatus.Done }, audio, busy: false));
        // 読める録音がない・長さ 0 なら出さない
        Assert.False(MeetingRecovery.CanRecover(new Meeting { Status = MeetingStatus.Failed }, none, busy: false));
        Assert.False(MeetingRecovery.CanRecover(new Meeting { Status = MeetingStatus.Failed }, zero, busy: false));
        // 発言がある・記録中・処理中・忙しいなら出さない
        var withUtterance = new Meeting { Status = MeetingStatus.Failed, Utterances = [new Utterance("me", 0, 1, "こんにちは")] };
        Assert.False(MeetingRecovery.CanRecover(withUtterance, audio, busy: false));
        Assert.False(MeetingRecovery.CanRecover(new Meeting { Status = MeetingStatus.Recording }, audio, busy: false));
        Assert.False(MeetingRecovery.CanRecover(new Meeting { Status = MeetingStatus.Processing }, audio, busy: false));
        Assert.False(MeetingRecovery.CanRecover(new Meeting { Status = MeetingStatus.Failed }, audio, busy: true));
    }

    [Fact]
    public void ReadableAudioCountsOnlyNonEmptyWavFiles()
    {
        var store = new MeetingStore(TestKeys.TempDirectory());
        // Mac で記録した会議（m4a だけ）は読めない
        var mac = store.NewMeeting(DateTimeOffset.Now);
        mac.Status = MeetingStatus.Failed;
        File.WriteAllBytes(Path.Combine(store.DirectoryOf(mac), "me.m4a"), new byte[2048]);
        Assert.False(MeetingRecovery.CanRecover(mac, MeetingRecovery.ReadableAudioSeconds(store, mac), busy: false));
        // 記録を始める途中で失敗した会議（ヘッダーだけの WAV）
        var empty = store.NewMeeting(DateTimeOffset.Now.AddMinutes(1));
        empty.Status = MeetingStatus.Failed;
        using (new WavStreamWriter(store.AudioPath(empty, MeetingChannel.Me))) { }
        Assert.False(MeetingRecovery.CanRecover(empty, MeetingRecovery.ReadableAudioSeconds(store, empty), busy: false));
        // 片方だけでも読める WAV があれば出す
        var crashed = store.NewMeeting(DateTimeOffset.Now.AddMinutes(2));
        crashed.Status = MeetingStatus.Failed;
        File.WriteAllBytes(store.AudioPath(crashed, MeetingChannel.Others), WavFile.Encode(Tone(0.05)));
        var seconds = MeetingRecovery.ReadableAudioSeconds(store, crashed);
        Assert.Equal((0.0, 1.0), (seconds[MeetingChannel.Me], seconds[MeetingChannel.Others]));
        Assert.True(MeetingRecovery.CanRecover(crashed, seconds, busy: false));
    }

    [Fact]
    public void DurationIsTheLatestEndOfTheRecordings()
    {
        var audio = new Dictionary<MeetingChannel, double> { [MeetingChannel.Me] = 10, [MeetingChannel.Others] = 7 };
        Assert.Equal(10, MeetingRecovery.Duration(null, audio));
        Assert.Equal(12, MeetingRecovery.Duration(new Dictionary<string, double> { ["me"] = 0.5, ["others"] = 5 }, audio));
        Assert.Equal(10.5, MeetingRecovery.Duration(new Dictionary<string, double> { ["me"] = 0.5 }, audio));
        // 長さ 0 のチャンネルは、ずれがあっても数えない
        Assert.Equal(0, MeetingRecovery.Duration(new Dictionary<string, double> { ["others"] = 5 }, new Dictionary<MeetingChannel, double> { [MeetingChannel.Others] = 0 }));
    }

    [Fact]
    public void ClosesOnlyOpenOffRecordSpans()
    {
        var spans = new List<OffRecordSpan> { new(1, 2), new(3), new(20) };
        Assert.True(MeetingRecovery.CloseOpenOffRecord(spans, 10));
        Assert.Equal([(1.0, (double?)2.0), (3.0, 10.0), (20.0, 20.0)], spans.Select(s => (s.Start, s.End)));
        Assert.False(MeetingRecovery.CloseOpenOffRecord(spans, 11));
        Assert.False(MeetingRecovery.CloseOpenOffRecord(null, 11));
    }

    // MARK: - 先頭のずれを記録中に保存する（DEC-MTG-157）

    [Fact]
    public async Task PersistsStartOffsetsWhileRecording()
    {
        var mic = new LiveRecorder(MeetingChannel.Me, Tone(0.5), 0.1);
        var loopback = new LiveRecorder(MeetingChannel.Others, Tone(0.05), null);
        var (controller, settings, _) = MakeController(mic: mic, loopback: loopback);
        var store = controller.Store(settings);
        // 記録していなければ何もしない
        controller.PersistStartOffsetsIfKnown();
        await controller.StartAsync();
        var meeting = controller.Current!;
        Assert.Null(store.Load(meeting.Id)!.AudioStartOffsets);

        controller.PersistStartOffsetsIfKnown();
        Assert.Equal(new Dictionary<string, double> { ["me"] = 0.1 }, store.Load(meeting.Id)!.AudioStartOffsets);
        // 相手の音が届いてずれが分かったら、それも保存する。保存したずれは変えない
        loopback.StartOffset = 2.5;
        mic.StartOffset = 9;
        controller.PersistStartOffsetsIfKnown();
        Assert.Equal(new Dictionary<string, double> { ["me"] = 0.1, ["others"] = 2.5 }, store.Load(meeting.Id)!.AudioStartOffsets);

        await controller.StopAsync();
        Assert.Equal(MeetingState.Idle, controller.State);
    }

    // MARK: - 録音から作り直す（DEC-MTG-158）

    [Fact]
    public async Task RecoversCrashedMeetingFromAudio()
    {
        var (controller, settings, _) = MakeController();
        var store = controller.Store(settings);
        var meeting = PlaceCrashedMeeting(store);
        Assert.True(controller.CanRecoverFromAudio(meeting));
        var stages = new List<string>();

        Assert.True(await controller.RecoverFromAudioAsync(meeting, new InlineProgress<string>(stages.Add)));

        var saved = store.Load(meeting.Id)!;
        Assert.Equal(MeetingStatus.Done, saved.Status);
        // 「記録の途中で…」は消える（議事録を作らない設定なので、ほかの問題もない）
        Assert.Null(saved.ErrorMessage);
        // ヘッダーを直したので、相手の録音（ヘッダーの長さ 0）も文字起こしする。時刻は保存した先頭のずれでそろう
        Assert.Equal([("me", "自分の発言", 0.3), ("others", "相手の発言", 2.2)], saved.Utterances.Select(u => (u.Speaker, u.Text, Math.Round(u.Start, 1))));
        // 長さは残った録音の終わり（相手: 2 秒 + 3 秒）。終わっていないオフレコはそこで閉じる
        Assert.Equal(5.0, saved.Duration, 3);
        Assert.Equal([(0.2, (double?)0.3), (0.5, 5.0)], saved.OffRecord!.Select(s => (s.Start, s.End)));
        Assert.Equal(["メモ", "大事"], saved.Notes!.Select(n => n.Text));
        // 「文字起こしのあとに録音を削除」がオンでも、作り直した会議の録音は消さない
        Assert.True(saved.DeleteAudioAfterTranscription);
        Assert.True(File.Exists(store.AudioPath(saved, MeetingChannel.Me)));
        Assert.True(File.Exists(store.AudioPath(saved, MeetingChannel.Others)));
        Assert.Equal(16000 * 3, WavFile.Decode(File.ReadAllBytes(store.AudioPath(saved, MeetingChannel.Others))).Samples.Length);
        Assert.Contains(stages, s => s.Contains("Fake"));
        // 発言ができたので、もうボタンは出さない。Current と State は変えない
        Assert.False(controller.CanRecoverFromAudio(saved));
        Assert.Null(controller.Current);
        Assert.Equal(MeetingState.Idle, controller.State);
        Assert.False(controller.IsRecovering(meeting.Id));
    }

    [Fact]
    public async Task BothChannelsFailingKeepsTheMeetingFailedAndRecoverable()
    {
        var (controller, settings, _) = MakeController(() => new FakeTranscriber(fail: true));
        var store = controller.Store(settings);
        var meeting = PlaceCrashedMeeting(store);

        Assert.True(await controller.RecoverFromAudioAsync(meeting));

        var saved = store.Load(meeting.Id)!;
        Assert.Equal(MeetingStatus.Failed, saved.Status);
        Assert.Empty(saved.Utterances);
        Assert.Contains("文字起こしできませんでした", saved.ErrorMessage);
        Assert.DoesNotContain(Core.Properties.Strings.Meeting_Interrupted, saved.ErrorMessage);
        Assert.Equal([MeetingChannel.Me, MeetingChannel.Others], saved.TranscriptionFailedChannels);
        // もう一度押せる。録音も残る
        Assert.True(controller.CanRecoverFromAudio(saved));
        Assert.True(File.Exists(store.AudioPath(saved, MeetingChannel.Me)));
    }

    [Fact]
    public async Task EngineNotReadyLeavesTheMeetingUnchanged()
    {
        var (controller, settings, _) = MakeController(() => new FakeTranscriber(failPrepare: true));
        var store = controller.Store(settings);
        var meeting = PlaceCrashedMeeting(store);
        var meBefore = File.ReadAllBytes(store.AudioPath(meeting, MeetingChannel.Me));

        var e = await Assert.ThrowsAsync<TranscriptionException>(() => controller.RecoverFromAudioAsync(meeting));
        Assert.Equal("モデルがありません", e.Message);

        var saved = store.Load(meeting.Id)!;
        Assert.Equal((MeetingStatus.Failed, Core.Properties.Strings.Meeting_Interrupted, 0.0), (saved.Status, saved.ErrorMessage, saved.Duration));
        Assert.Null(saved.OffRecord![1].End);
        Assert.Equal(meBefore, File.ReadAllBytes(store.AudioPath(meeting, MeetingChannel.Me)));
        Assert.False(controller.IsRecovering(meeting.Id));
        Assert.True(controller.CanRecoverFromAudio(saved));
    }

    [Fact]
    public async Task CannotStartRecordingWhileRecovering()
    {
        var gate = new TaskCompletionSource();
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var (controller, settings, notices) = MakeController(() => new FakeTranscriber(gate: gate.Task, entered: entered));
        var store = controller.Store(settings);
        var meeting = PlaceCrashedMeeting(store);
        var other = PlaceCrashedMeeting(store);

        var recovering = controller.RecoverFromAudioAsync(meeting);
        await entered.Task.WaitAsync(TimeSpan.FromSeconds(10));
        Assert.True(controller.IsRecovering(meeting.Id));
        Assert.True(controller.IsRecovering());
        // 作り直している間は: 記録を始めない（理由を知らせる）・消させない・ほかの会議も作り直さない
        await controller.StartAsync();
        Assert.Equal(MeetingState.Idle, controller.State);
        Assert.Null(controller.Current);
        Assert.Contains(notices, n => n.Message == Core.Properties.Strings.Meeting_RecoveringCannotStart);
        Assert.False(controller.CanDelete(meeting));
        Assert.False(controller.CanRecoverFromAudio(meeting));
        Assert.False(controller.CanRecoverFromAudio(other));
        Assert.False(await controller.RecoverFromAudioAsync(other));

        gate.SetResult();
        Assert.True(await recovering.WaitAsync(TimeSpan.FromSeconds(10)));
        Assert.False(controller.IsRecovering());
        Assert.Equal(MeetingStatus.Done, store.Load(meeting.Id)!.Status);
        // 終わったら記録を始められる
        await controller.StartAsync();
        Assert.Equal(MeetingState.Recording, controller.State);
        await controller.StopAsync();
    }
}
