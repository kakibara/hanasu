using System.Globalization;
using Hanasu.Core.Settings;

namespace Hanasu.Core.Meetings;

// 会議の録音を消すときの決まり（Mac 版 MeetingAudioCleanup.swift と同じ考え）。
// どれも、会議の配列・会議のフォルダの親（保存先）・今の日時を受け取る関数にし、テストは一時フォルダで確かめる（DEC-MTG-141）。

/// <summary>消せなかった録音のファイル 1 つ</summary>
public sealed record MeetingAudioDeleteFailure(string MeetingId, string Path, string Message);

/// <summary>録音をまとめて消した結果。Deleted は録音を全部消せた会議の数</summary>
public sealed record MeetingAudioDeletion(int Deleted, IReadOnlyList<MeetingAudioDeleteFailure> Failures)
{
    /// <summary>消せなかったファイルがあった会議の数</summary>
    public int FailedMeetings => Failures.Select(f => f.MeetingId).Distinct().Count();
}

// 要件: REQ-MTG-010, REQ-MTG-055, REQ-MTG-056, REQ-MTG-057
// 設計判断: DEC-MTG-142
/// <summary>会議の文字起こしの状態</summary>
public enum MeetingTranscriptState
{
    /// <summary>すべてのチャンネルの文字起こしがある</summary>
    Complete,
    /// <summary>発言はあるが、文字起こしに失敗したチャンネルがある（か、状態が「失敗」）</summary>
    Partial,
    /// <summary>発言が 0 件</summary>
    None,
}

/// <summary>録音が残っている会議 1 つ（録音の管理の一覧の 1 行）</summary>
public sealed record MeetingAudioEntry(Meeting Meeting, IReadOnlyList<string> Files, long Size, MeetingTranscriptState State)
{
    /// <summary>まとめて消す（30 日より前・すべて・保存期間・後処理の自動の削除）対象にしてよいか</summary>
    public bool IsComplete => State == MeetingTranscriptState.Complete;
}

// 要件: REQ-MTG-010
// 設計判断: DEC-MTG-139, DEC-MTG-142
/// <summary>文字起こしのあとに録音を消すかの決まり</summary>
public static class MeetingAudioPolicy
{
    /// <summary>
    /// 記録を始めるときに、設定（KeepMeetingAudio。画面では裏返しの「文字起こしのあとに録音を削除する」）を会議に写す。
    /// 消すときだけ true を書く
    /// </summary>
    public static void Apply(Meeting meeting, AppSettings settings) =>
        meeting.DeleteAudioAfterTranscription = settings.KeepMeetingAudio ? null : true;

    /// <summary>
    /// 後処理のあとに録音を消すか。設定は見ず、会議の値と文字起こしの状態で決める。
    /// 文字起こしがそろっていない（失敗したチャンネルがある・発言が 0 件・状態が「失敗」）なら消さない
    /// </summary>
    public static bool ShouldDeleteAfterProcessing(Meeting meeting) =>
        meeting.DeleteAudioAfterTranscription == true
        && meeting.Status != MeetingStatus.Failed
        && MeetingAudioCleanup.TranscriptState(meeting) == MeetingTranscriptState.Complete;
}

// 要件: REQ-MTG-055, REQ-MTG-056, REQ-MTG-057
// 設計判断: DEC-MTG-141, DEC-MTG-142, DEC-MTG-143
/// <summary>あとから録音を消すときの、対象の選び方</summary>
public static class MeetingAudioCleanup
{
    /// <summary>「30 日より前の録音を削除…」の日数</summary>
    public const int OlderThanDays = 30;

    /// <summary>会議の文字起こしの状態（DEC-MTG-142）</summary>
    public static MeetingTranscriptState TranscriptState(Meeting meeting)
    {
        if (meeting.Utterances.Count == 0) return MeetingTranscriptState.None;
        if (meeting.TranscriptionFailedChannels is { Count: > 0 } || meeting.Status == MeetingStatus.Failed) return MeetingTranscriptState.Partial;
        return MeetingTranscriptState.Complete;
    }

    /// <summary>
    /// 録音が残っている会議（新しい順）。記録中・処理中の会議（currentId と、状態が記録中・処理中のもの）は並べない。
    /// baseDirectory は会議のフォルダの親（MeetingStore.BaseDirectory）
    /// </summary>
    public static List<MeetingAudioEntry> Entries(IEnumerable<Meeting> meetings, string baseDirectory, string? currentId = null)
    {
        var result = new List<MeetingAudioEntry>();
        foreach (var meeting in meetings.OrderByDescending(m => m.StartedAt))
        {
            if (meeting.Id == currentId || meeting.Status is MeetingStatus.Recording or MeetingStatus.Processing) continue;
            var files = MeetingStore.AudioFilesIn(Path.Combine(baseDirectory, meeting.Id));
            if (files.Count == 0) continue;
            result.Add(new MeetingAudioEntry(meeting, files, MeetingStore.SizeOf(files), TranscriptState(meeting)));
        }
        return result;
    }

    /// <summary>記録を始めた日時が、今から days×24 時間より前か</summary>
    public static bool IsOlderThan(MeetingAudioEntry entry, int days, DateTimeOffset now) =>
        entry.Meeting.StartedAt < now - TimeSpan.FromDays(days);

    /// <summary>「N 日より前の録音を削除…」で消す会議（文字起こしがそろっているものだけ）</summary>
    public static List<MeetingAudioEntry> OlderThan(IEnumerable<MeetingAudioEntry> entries, int days, DateTimeOffset now) =>
        entries.Where(e => e.IsComplete && IsOlderThan(e, days, now)).ToList();

    /// <summary>「N 日より前」に当てはまるが、文字起こしがそろっていないので残す会議</summary>
    public static List<MeetingAudioEntry> SkippedOlderThan(IEnumerable<MeetingAudioEntry> entries, int days, DateTimeOffset now) =>
        entries.Where(e => !e.IsComplete && IsOlderThan(e, days, now)).ToList();

    /// <summary>「すべての録音を削除…」で消す会議（文字起こしがそろっているものだけ）</summary>
    public static List<MeetingAudioEntry> All(IEnumerable<MeetingAudioEntry> entries) => entries.Where(e => e.IsComplete).ToList();

    /// <summary>「すべて」で、文字起こしがそろっていないので残す会議</summary>
    public static List<MeetingAudioEntry> SkippedAll(IEnumerable<MeetingAudioEntry> entries) => entries.Where(e => !e.IsComplete).ToList();

    // 要件: REQ-MTG-057
    // 設計判断: DEC-MTG-143
    /// <summary>保存期間（日。0 以下は無期限）を過ぎた会議。無期限なら空</summary>
    public static List<MeetingAudioEntry> Expired(IEnumerable<MeetingAudioEntry> entries, int retentionDays, DateTimeOffset now) =>
        retentionDays <= 0 ? new() : OlderThan(entries, retentionDays, now);

    /// <summary>大きさの合計</summary>
    public static long TotalSize(IEnumerable<MeetingAudioEntry> entries) => entries.Sum(e => e.Size);

    // 設計判断: DEC-MTG-141
    /// <summary>
    /// 大きさの表示（「12 KB」「115 MB」「1.4 GB」）。1000 で区切り（Mac の ByteCountFormatter のファイルの数え方と同じ）、
    /// 数の書き方は今の表示の言語（culture を渡さなければ Strings.Culture か CurrentUICulture）。0 より大きければ 1 KB 以上で出す
    /// </summary>
    public static string FormatSize(long bytes, CultureInfo? culture = null)
    {
        culture ??= Strings.Culture ?? CultureInfo.CurrentUICulture;
        const double kb = 1000, mb = kb * 1000, gb = mb * 1000;
        string Number(double value) => value.ToString(value < 10 ? "0.#" : "0", culture);
        if (bytes <= 0) return "0 KB";
        if (bytes < mb) return $"{Math.Max(1, Math.Round(bytes / kb)).ToString("0", culture)} KB";
        if (bytes < gb) return $"{Number(bytes / mb)} MB";
        return $"{Number(bytes / gb)} GB";
    }
}
