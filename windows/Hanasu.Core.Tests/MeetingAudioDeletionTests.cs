using System.Globalization;
using Hanasu.Core.Audio;
using Hanasu.Core.Meetings;
using Hanasu.Core.Settings;
using Hanasu.Core.Transcription;

namespace Hanasu.Core.Tests;

// 確かめ方: REQ-MTG-010, REQ-MTG-055, REQ-MTG-056, REQ-MTG-057
// 設計判断: DEC-MTG-139, DEC-MTG-140, DEC-MTG-141, DEC-MTG-142, DEC-MTG-143
/// <summary>
/// 会議の録音を消すこと（会議ごとの自動の削除・あとからの削除・録音の管理の対象の選び方・保存期間）。
/// どれも一時フォルダの中だけで確かめる（本物の保存先には触らない）
/// </summary>
public class MeetingAudioDeletionTests
{
    // MARK: - 偽物

    private sealed class FakeRecorder(MeetingChannel channel, float[] audio) : IMeetingChannelRecorder
    {
        private string? path;
        public MeetingChannel Channel => channel;
        public double? StartOffset { get; private set; }
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
            StartOffset = 0;
            return Task.CompletedTask;
        }

        public ValueTask DisposeAsync() => ValueTask.CompletedTask;
    }

    /// <summary>failChannel の音（大きい音 = 自分、小さい音 = 相手）で失敗する。empty なら何も返さない</summary>
    private sealed class FakeTranscriber(MeetingChannel? failChannel = null, bool empty = false) : ISegmentTranscriber
    {
        public string DisplayName => "Fake";

        public Task PrepareAsync(TranscriptionContext context, CancellationToken cancellationToken = default) => Task.CompletedTask;

        public Task<IReadOnlyList<TimedSegment>> TranscribeSegmentsAsync(float[] samples, TranscriptionContext context,
            IProgress<string>? progress = null, CancellationToken cancellationToken = default)
        {
            var channel = MeetingAudio.Rms(samples) > 0.1 ? MeetingChannel.Me : MeetingChannel.Others;
            if (channel == failChannel) throw new TranscriptionException("文字起こしできませんでした");
            if (empty) return Task.FromResult<IReadOnlyList<TimedSegment>>([]);
            return Task.FromResult<IReadOnlyList<TimedSegment>>([new TimedSegment(0.2, 0.8, channel == MeetingChannel.Me ? "自分の発言" : "相手の発言")]);
        }
    }

    private static float[] Tone(double amplitude) => Enumerable.Range(0, 16000).Select(i => (float)(Math.Sin(i * 0.1) * amplitude)).ToArray();

    private static readonly DateTimeOffset Now = new(2026, 11, 10, 3, 0, 0, TimeSpan.Zero);

    private static (MeetingController Controller, AppSettings Settings) MakeController(
        Func<ISegmentTranscriber>? transcriber = null, Func<DateTimeOffset>? now = null)
    {
        var settings = new AppSettings { MeetingsDirectory = TestKeys.TempDirectory(), MakeMeetingMinutes = false };
        var controller = new MeetingController(new MeetingServices
        {
            Settings = () => settings,
            CreateMicRecorder = _ => new FakeRecorder(MeetingChannel.Me, Tone(0.5)),
            CreateLoopbackRecorder = _ => new FakeRecorder(MeetingChannel.Others, Tone(0.05)),
            CreateTranscriber = _ => transcriber?.Invoke() ?? new FakeTranscriber(),
            CreateMinutesClient = _ => null,
            Now = now ?? (() => DateTimeOffset.Now),
        });
        return (controller, settings);
    }

    /// <summary>保存先に会議を置く（音声のファイルは names のもの。中身は 1 KB）</summary>
    private static Meeting PlaceMeeting(MeetingStore store, DateTimeOffset startedAt, int utterances = 1, MeetingStatus status = MeetingStatus.Done,
        List<MeetingChannel>? failed = null, params string[] names)
    {
        var meeting = store.NewMeeting(startedAt);
        meeting.Status = status;
        meeting.TranscriptionFailedChannels = failed;
        meeting.Utterances = Enumerable.Range(0, utterances).Select(i => new Utterance("me", i, i + 1, $"発言{i}")).ToList();
        store.Save(meeting);
        foreach (var name in names.Length == 0 ? new[] { MeetingStore.MeAudioFile, MeetingStore.OthersAudioFile } : names)
        {
            File.WriteAllBytes(Path.Combine(store.DirectoryOf(meeting), name), new byte[1000]);
        }
        return meeting;
    }

    // MARK: - 会議ごとの値（REQ-MTG-010）

    [Fact]
    public async Task CopiesSettingToMeetingWhenRecordingStarts()
    {
        var (controller, settings) = MakeController();
        settings.KeepMeetingAudio = false;
        await controller.StartAsync();
        var meeting = controller.Current!;
        Assert.True(meeting.DeleteAudioAfterTranscription);
        var json = File.ReadAllText(Path.Combine(controller.Store(settings).DirectoryOf(meeting), "meeting.json"));
        Assert.Contains("\"deleteAudioAfterTranscription\": true", json);
        await controller.StopAsync();

        // 残す設定なら会議に書かない（true のときだけ書く）
        settings.KeepMeetingAudio = true;
        await controller.StartAsync();
        var kept = controller.Current!;
        Assert.Null(kept.DeleteAudioAfterTranscription);
        Assert.DoesNotContain("deleteAudioAfterTranscription", File.ReadAllText(Path.Combine(controller.Store(settings).DirectoryOf(kept), "meeting.json")));
        await controller.StopAsync();
    }

    [Fact]
    public async Task MeetingValueDecidesEvenIfSettingChangesWhileRecording()
    {
        var (controller, settings) = MakeController();
        settings.KeepMeetingAudio = false;
        await controller.StartAsync();
        var meeting = controller.Current!;
        // 記録中に既定を「残す」に変えても、この会議は消す
        settings.KeepMeetingAudio = true;
        await controller.StopAsync();
        var store = controller.Store(settings);
        Assert.False(store.HasAudio(meeting));
        var saved = store.Load(meeting.Id)!;
        Assert.Null(saved.ErrorMessage);
        Assert.True(File.Exists(Path.Combine(store.DirectoryOf(meeting), "transcript.md")));
        Assert.True(File.Exists(Path.Combine(store.DirectoryOf(meeting), "meeting.json")));

        // 逆に、既定が「削除」でも会議の値が「残す」なら残す
        settings.KeepMeetingAudio = false;
        await controller.StartAsync();
        var other = controller.Current!;
        settings.KeepMeetingAudio = true;
        Assert.True(controller.SetDeleteAudioAfterTranscription(false));
        settings.KeepMeetingAudio = false;
        await controller.StopAsync();
        Assert.True(store.HasAudio(other));
        Assert.Null(store.Load(other.Id)!.DeleteAudioAfterTranscription);
    }

    [Fact]
    public async Task ChangesOnlyTheRecordingMeetingAndOnlyWhileRecording()
    {
        var (controller, settings) = MakeController();
        // 記録中でなければ変えない
        Assert.False(controller.SetDeleteAudioAfterTranscription(true));
        await controller.StartAsync();
        var meeting = controller.Current!;
        var changed = 0;
        controller.MeetingChanged += (_, _) => changed++;
        Assert.True(controller.SetDeleteAudioAfterTranscription(true));
        Assert.Equal(1, changed);
        // 既定（設定）は変わらない
        Assert.True(settings.KeepMeetingAudio);
        Assert.True(controller.Store(settings).Load(meeting.Id)!.DeleteAudioAfterTranscription);
        await controller.StopAsync();
        Assert.False(controller.Store(settings).HasAudio(meeting));
        // 処理のあとは変えられない
        Assert.False(controller.SetDeleteAudioAfterTranscription(false));
    }

    [Fact]
    public async Task KeepsAudioWhenAChannelFailed()
    {
        var (controller, settings) = MakeController(() => new FakeTranscriber(failChannel: MeetingChannel.Others));
        settings.KeepMeetingAudio = false;
        await controller.StartAsync();
        var meeting = controller.Current!;
        await controller.StopAsync();
        var store = controller.Store(settings);
        var saved = store.Load(meeting.Id)!;
        Assert.True(store.HasAudio(saved));
        Assert.Equal([MeetingChannel.Others], saved.TranscriptionFailedChannels);
        Assert.Equal(MeetingTranscriptState.Partial, MeetingAudioCleanup.TranscriptState(saved));
        Assert.Contains("\"transcriptionFailedChannels\": [\n    \"others\"\n  ]", File.ReadAllText(Path.Combine(store.DirectoryOf(saved), "meeting.json")).ReplaceLineEndings("\n"));
        // 「音声ファイルは残しています」はエラーの文に入れない（表示のときに決める。DEC-MTG-140）
        Assert.DoesNotContain(Core.Properties.Strings.Meeting_AudioKept, saved.ErrorMessage);
        Assert.Contains("文字起こしできませんでした", saved.ErrorMessage);
    }

    [Fact]
    public async Task WritesFailedChannelsEvenWhenKeepingAudio()
    {
        var (controller, settings) = MakeController(() => new FakeTranscriber(failChannel: MeetingChannel.Me));
        await controller.StartAsync();
        var meeting = controller.Current!;
        await controller.StopAsync();
        Assert.Equal([MeetingChannel.Me], controller.Store(settings).Load(meeting.Id)!.TranscriptionFailedChannels);
    }

    [Fact]
    public async Task KeepsAudioWhenThereAreNoUtterances()
    {
        var (controller, settings) = MakeController(() => new FakeTranscriber(empty: true));
        settings.KeepMeetingAudio = false;
        await controller.StartAsync();
        var meeting = controller.Current!;
        await controller.StopAsync();
        var store = controller.Store(settings);
        var saved = store.Load(meeting.Id)!;
        Assert.Empty(saved.Utterances);
        Assert.Null(saved.TranscriptionFailedChannels);
        Assert.Equal(MeetingTranscriptState.None, MeetingAudioCleanup.TranscriptState(saved));
        Assert.True(store.HasAudio(saved));
    }

    [Fact]
    public void PolicyUsesMeetingValueAndTranscriptState()
    {
        var meeting = new Meeting { Status = MeetingStatus.Done, Utterances = [new Utterance("me", 0, 1, "a")] };
        Assert.False(MeetingAudioPolicy.ShouldDeleteAfterProcessing(meeting));
        MeetingAudioPolicy.Apply(meeting, new AppSettings { KeepMeetingAudio = false });
        Assert.True(MeetingAudioPolicy.ShouldDeleteAfterProcessing(meeting));
        meeting.TranscriptionFailedChannels = [MeetingChannel.Me];
        Assert.False(MeetingAudioPolicy.ShouldDeleteAfterProcessing(meeting));
        meeting.TranscriptionFailedChannels = null;
        meeting.Status = MeetingStatus.Failed;
        Assert.False(MeetingAudioPolicy.ShouldDeleteAfterProcessing(meeting));
        meeting.Status = MeetingStatus.Done;
        meeting.Utterances = [];
        Assert.False(MeetingAudioPolicy.ShouldDeleteAfterProcessing(meeting));
        MeetingAudioPolicy.Apply(meeting, new AppSettings { KeepMeetingAudio = true });
        Assert.Null(meeting.DeleteAudioAfterTranscription);
    }

    [Fact]
    public void TranscriptStateHasThreeKinds()
    {
        var one = new List<Utterance> { new("me", 0, 1, "a") };
        Assert.Equal(MeetingTranscriptState.Complete, MeetingAudioCleanup.TranscriptState(new Meeting { Status = MeetingStatus.Done, Utterances = one }));
        Assert.Equal(MeetingTranscriptState.Partial, MeetingAudioCleanup.TranscriptState(new Meeting { Status = MeetingStatus.Done, Utterances = one, TranscriptionFailedChannels = [MeetingChannel.Others] }));
        Assert.Equal(MeetingTranscriptState.Partial, MeetingAudioCleanup.TranscriptState(new Meeting { Status = MeetingStatus.Failed, Utterances = one }));
        Assert.Equal(MeetingTranscriptState.None, MeetingAudioCleanup.TranscriptState(new Meeting { Status = MeetingStatus.Failed }));
        Assert.Equal(MeetingTranscriptState.None, MeetingAudioCleanup.TranscriptState(new Meeting { Status = MeetingStatus.Done }));
    }

    [Fact]
    public void InterruptedMeetingsKeepAudioWithoutMentioningItInTheError()
    {
        var store = new MeetingStore(TestKeys.TempDirectory());
        var meeting = PlaceMeeting(store, Now, utterances: 0, status: MeetingStatus.Recording);
        meeting.DeleteAudioAfterTranscription = true;
        store.Save(meeting);
        store.MarkInterruptedMeetings();
        var saved = store.Load(meeting.Id)!;
        Assert.Equal(MeetingStatus.Failed, saved.Status);
        Assert.DoesNotContain("me.wav", saved.ErrorMessage);
        Assert.True(store.HasAudio(saved));
    }

    // MARK: - あとから消す（REQ-MTG-055）

    [Fact]
    public void DeletesOnlyTheFourAudioFiles()
    {
        var store = new MeetingStore(TestKeys.TempDirectory());
        var meeting = PlaceMeeting(store, Now, names: ["me.m4a", "others.m4a", "me.wav", "others.wav"]);
        meeting.Notes = [new MeetingNote(MeetingNoteKind.Note, 1, "メモ")];
        meeting.Minutes = "## 概要";
        store.Save(meeting);
        var dir = store.DirectoryOf(meeting);
        File.WriteAllText(Path.Combine(dir, "other.wav.bak"), "x");
        Assert.Equal(4, store.AudioFiles(meeting).Count);
        Assert.Equal(4000, store.AudioSize(meeting));

        Assert.Empty(store.DeleteAudio(meeting));
        Assert.Empty(store.AudioFiles(meeting));
        Assert.False(store.HasAudio(meeting));
        foreach (var kept in new[] { "meeting.json", "transcript.md", "minutes.md", "notes.md", "other.wav.bak" })
        {
            Assert.True(File.Exists(Path.Combine(dir, kept)), kept);
        }
        // もうないファイルは消せたものとして扱う
        Assert.Empty(store.DeleteAudio(meeting));
        // meeting.json は書き換えない
        Assert.Equal("## 概要", store.Load(meeting.Id)!.Minutes);
    }

    [Fact]
    public void ReportsFilesThatCouldNotBeDeleted()
    {
        var store = new MeetingStore(TestKeys.TempDirectory());
        var meeting = PlaceMeeting(store, Now);
        var dir = store.DirectoryOf(meeting);
        var locked = Path.Combine(dir, MeetingStore.MeAudioFile);
        if (OperatingSystem.IsWindows())
        {
            using var stream = new FileStream(locked, FileMode.Open, FileAccess.Read, FileShare.None);
            var failures = store.DeleteAudio(meeting);
            Assert.Equal(locked, Assert.Single(failures).Path);
        }
        else
        {
            // フォルダを読むだけにすると、中のファイルを消せない
            File.SetUnixFileMode(dir, UnixFileMode.UserRead | UnixFileMode.UserExecute);
            try
            {
                var failures = store.DeleteAudio(meeting);
                Assert.Equal(2, failures.Count);
                Assert.All(failures, f => Assert.Equal(meeting.Id, f.MeetingId));
            }
            finally
            {
                File.SetUnixFileMode(dir, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
            }
        }
        // 残ったファイルはそのまま
        Assert.True(File.Exists(locked));
    }

    [Fact]
    public async Task DoesNotDeleteAudioOfTheRecordingMeeting()
    {
        var (controller, settings) = MakeController();
        await controller.StartAsync();
        var meeting = controller.Current!;
        Assert.False(controller.CanDeleteAudio(meeting));
        var deleted = new List<Meeting>();
        controller.AudioDeleted += (_, list) => deleted.AddRange(list);
        Assert.Equal(0, controller.DeleteAudio([meeting]).Deleted);
        Assert.Empty(deleted);
        await controller.StopAsync();

        var store = controller.Store(settings);
        var saved = store.Load(meeting.Id)!;
        Assert.True(store.HasAudio(saved));
        Assert.True(controller.CanDeleteAudio(saved));
        var result = controller.DeleteAudio([saved]);
        Assert.Equal(1, result.Deleted);
        Assert.Empty(result.Failures);
        Assert.Equal([saved.Id], deleted.Select(m => m.Id));
        Assert.False(store.HasAudio(saved));
        // 状態が記録中・処理中の会議（ほかで処理している会議など）も消さない
        Assert.False(controller.CanDeleteAudio(new Meeting { Id = "x", Status = MeetingStatus.Processing }));
    }

    // MARK: - 録音の管理（REQ-MTG-056）

    [Fact]
    public void ListsMeetingsWithAudioNewestFirstExcludingCurrent()
    {
        var store = new MeetingStore(TestKeys.TempDirectory());
        var old = PlaceMeeting(store, Now.AddDays(-40));
        var recent = PlaceMeeting(store, Now.AddDays(-1));
        var noAudio = store.NewMeeting(Now.AddDays(-2));
        noAudio.Status = MeetingStatus.Done;
        store.Save(noAudio);
        var current = PlaceMeeting(store, Now, status: MeetingStatus.Done);
        var processing = PlaceMeeting(store, Now.AddHours(-1), status: MeetingStatus.Processing);

        var entries = MeetingAudioCleanup.Entries(store.LoadAll(), store.BaseDirectory, current.Id);
        Assert.Equal([recent.Id, old.Id], entries.Select(e => e.Meeting.Id));
        Assert.Equal(2000, entries[0].Size);
        Assert.Equal(4000, MeetingAudioCleanup.TotalSize(entries));
        Assert.DoesNotContain(entries, e => e.Meeting.Id == processing.Id);
    }

    [Fact]
    public void OlderThan30DaysUsesThe30x24HourBoundary()
    {
        var store = new MeetingStore(TestKeys.TempDirectory());
        var justOver = PlaceMeeting(store, Now - TimeSpan.FromDays(30) - TimeSpan.FromSeconds(1));
        var exactly = PlaceMeeting(store, Now - TimeSpan.FromDays(30));
        var under = PlaceMeeting(store, Now - TimeSpan.FromDays(29));
        var entries = MeetingAudioCleanup.Entries(store.LoadAll(), store.BaseDirectory);
        Assert.Equal([justOver.Id], MeetingAudioCleanup.OlderThan(entries, MeetingAudioCleanup.OlderThanDays, Now).Select(e => e.Meeting.Id));
        Assert.Equal(3, MeetingAudioCleanup.All(entries).Count);
        Assert.Contains(exactly.Id, entries.Select(e => e.Meeting.Id));
        Assert.Contains(under.Id, entries.Select(e => e.Meeting.Id));
    }

    [Fact]
    public void BulkDeletionSkipsMeetingsWithIncompleteTranscripts()
    {
        var store = new MeetingStore(TestKeys.TempDirectory());
        var complete = PlaceMeeting(store, Now.AddDays(-60));
        var partial = PlaceMeeting(store, Now.AddDays(-50), failed: [MeetingChannel.Others]);
        var none = PlaceMeeting(store, Now.AddDays(-45), utterances: 0, status: MeetingStatus.Failed);
        var recentPartial = PlaceMeeting(store, Now.AddDays(-1), status: MeetingStatus.Failed);
        var entries = MeetingAudioCleanup.Entries(store.LoadAll(), store.BaseDirectory);

        Assert.Equal([complete.Id], MeetingAudioCleanup.OlderThan(entries, 30, Now).Select(e => e.Meeting.Id));
        Assert.Equal([none.Id, partial.Id], MeetingAudioCleanup.SkippedOlderThan(entries, 30, Now).Select(e => e.Meeting.Id));
        Assert.Equal([complete.Id], MeetingAudioCleanup.All(entries).Select(e => e.Meeting.Id));
        Assert.Equal([recentPartial.Id, none.Id, partial.Id], MeetingAudioCleanup.SkippedAll(entries).Select(e => e.Meeting.Id));
        Assert.Equal(MeetingTranscriptState.None, entries.Single(e => e.Meeting.Id == none.Id).State);
        Assert.Equal(MeetingTranscriptState.Partial, entries.Single(e => e.Meeting.Id == partial.Id).State);
    }

    [Fact]
    public void SelectedDeletionDeletesOnlyThoseMeetings()
    {
        var (controller, settings) = MakeController();
        var store = controller.Store(settings);
        var a = PlaceMeeting(store, Now.AddDays(-3));
        var b = PlaceMeeting(store, Now.AddDays(-2), utterances: 0);
        var c = PlaceMeeting(store, Now.AddDays(-1));
        // 選んで消すときは、文字起こしがない会議も消せる（ダイアログで確かめたあと）
        var result = controller.DeleteAudio([a, b]);
        Assert.Equal(2, result.Deleted);
        Assert.False(store.HasAudio(a));
        Assert.False(store.HasAudio(b));
        Assert.True(store.HasAudio(c));
    }

    [Fact]
    public void FormatsSizesInTheUiCulture()
    {
        var en = CultureInfo.GetCultureInfo("en");
        Assert.Equal("0 KB", MeetingAudioCleanup.FormatSize(0, en));
        Assert.Equal("1 KB", MeetingAudioCleanup.FormatSize(200, en));
        Assert.Equal("12 KB", MeetingAudioCleanup.FormatSize(12_300, en));
        Assert.Equal("115 MB", MeetingAudioCleanup.FormatSize(115_200_000, en));
        Assert.Equal("1.4 GB", MeetingAudioCleanup.FormatSize(1_400_000_000, en));
        Assert.Equal("1,4 GB", MeetingAudioCleanup.FormatSize(1_400_000_000, CultureInfo.GetCultureInfo("de")));
    }

    // MARK: - 保存期間（REQ-MTG-057）

    [Theory]
    [InlineData(7)]
    [InlineData(30)]
    [InlineData(90)]
    [InlineData(365)]
    public void ExpiredUsesTheRetentionDays(int days)
    {
        var store = new MeetingStore(TestKeys.TempDirectory());
        var expired = PlaceMeeting(store, Now - TimeSpan.FromDays(days) - TimeSpan.FromMinutes(1));
        PlaceMeeting(store, Now - TimeSpan.FromDays(days) + TimeSpan.FromMinutes(1));
        PlaceMeeting(store, Now - TimeSpan.FromDays(days + 10), failed: [MeetingChannel.Me]);
        var entries = MeetingAudioCleanup.Entries(store.LoadAll(), store.BaseDirectory);
        Assert.Equal([expired.Id], MeetingAudioCleanup.Expired(entries, days, Now).Select(e => e.Meeting.Id));
        // 無期限は消さない
        Assert.Empty(MeetingAudioCleanup.Expired(entries, 0, Now));
    }

    [Fact]
    public async Task PrunesExpiredAudioAfterProcessing()
    {
        var (controller, settings) = MakeController(now: () => Now);
        settings.MeetingAudioRetentionDays = 30;
        var store = controller.Store(settings);
        var old = PlaceMeeting(store, Now.AddDays(-31));
        // 会議ごとに「残す」にした会議も、保存期間は効く
        old.DeleteAudioAfterTranscription = null;
        store.Save(old);
        var oldPartial = PlaceMeeting(store, Now.AddDays(-40), failed: [MeetingChannel.Others]);
        var recent = PlaceMeeting(store, Now.AddDays(-10));
        var pruned = new List<Meeting>();
        controller.AudioDeleted += (_, list) => pruned.AddRange(list);

        await controller.StartAsync();
        var meeting = controller.Current!;
        // 記録中には消さない（後処理のあと）
        Assert.True(store.HasAudio(old));
        await controller.StopAsync();

        Assert.False(store.HasAudio(old));
        Assert.True(store.HasAudio(oldPartial));
        Assert.True(store.HasAudio(recent));
        Assert.True(store.HasAudio(meeting));
        Assert.Equal([old.Id], pruned.Select(m => m.Id));
    }

    [Fact]
    public void PruneDoesNothingWhenUnlimited()
    {
        var (controller, settings) = MakeController(now: () => Now);
        var store = controller.Store(settings);
        var old = PlaceMeeting(store, Now.AddDays(-400));
        Assert.Equal(0, controller.PruneExpiredAudio().Deleted);
        Assert.True(store.HasAudio(old));
        settings.MeetingAudioRetentionDays = 365;
        Assert.Equal(1, controller.PruneExpiredAudio().Deleted);
        Assert.False(store.HasAudio(old));
    }

    // MARK: - 保存と読み込み

    [Fact]
    public void NewKeysSurviveJsonRoundTrip()
    {
        var meeting = new Meeting
        {
            Id = "x",
            Title = "会議",
            StartedAt = Now,
            Status = MeetingStatus.Done,
            DeleteAudioAfterTranscription = true,
            TranscriptionFailedChannels = [MeetingChannel.Me, MeetingChannel.Others],
        };
        var json = MeetingJson.Serialize(meeting);
        Assert.Contains("\"deleteAudioAfterTranscription\": true", json);
        Assert.Contains("\"me\"", json);
        Assert.Contains("\"others\"", json);
        var loaded = MeetingJson.Deserialize(json);
        Assert.True(loaded.DeleteAudioAfterTranscription);
        Assert.Equal([MeetingChannel.Me, MeetingChannel.Others], loaded.TranscriptionFailedChannels);

        // Mac 版の書き方（sortedKeys・スペースつきのコロン）も読める。ないときは null
        var mac = MeetingJson.Deserialize(MeetingJsonTests.MacMeetingJson.Replace("\"actionItems\" : [", "\"deleteAudioAfterTranscription\" : true,\n  \"transcriptionFailedChannels\" : [\"others\"],\n  \"actionItems\" : ["));
        Assert.True(mac.DeleteAudioAfterTranscription);
        Assert.Equal([MeetingChannel.Others], mac.TranscriptionFailedChannels);
        var plain = MeetingJson.Deserialize(MeetingJsonTests.MacMeetingJson);
        Assert.Null(plain.DeleteAudioAfterTranscription);
        Assert.Null(plain.TranscriptionFailedChannels);
        Assert.DoesNotContain("transcriptionFailedChannels", MeetingJson.Serialize(plain));
    }

    [Fact]
    public void RetentionSettingSurvivesSaveAndLoad()
    {
        Assert.True(new AppSettings().KeepMeetingAudio);
        Assert.Equal(0, new AppSettings().MeetingAudioRetentionDays);
        var store = new SettingsStore(Path.Combine(TestKeys.TempDirectory(), "settings.json"));
        store.Save(new AppSettings { KeepMeetingAudio = false, MeetingAudioRetentionDays = 90 });
        var loaded = store.Load();
        Assert.False(loaded.KeepMeetingAudio);
        Assert.Equal(90, loaded.MeetingAudioRetentionDays);
        var negative = new AppSettings { MeetingAudioRetentionDays = -5 };
        SettingsStore.Normalize(negative);
        Assert.Equal(0, negative.MeetingAudioRetentionDays);
    }
}
