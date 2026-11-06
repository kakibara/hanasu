using System.Text.Json.Serialization;

namespace Hanasu.Core.Meetings;

// 議事録に使う発言の選び方（範囲・発言ごとの除外・話者ごとの除外・オフレコ）。Mac 版 MinutesSelection.swift の移植。
// 決まりを変えるときは Mac 版も両方を直す（どちらで選んでも同じ結果にする。DEC-MTG-108）。

// 要件: REQ-MTG-046
// 設計判断: DEC-MTG-094
/// <summary>記録中に「オフレコ」にした区間（記録の経過時間の秒）。End が null なら、まだオフレコ中か、記録の終わりまで</summary>
public sealed class OffRecordSpan
{
    /// <summary>Swift の UUID と同じ大文字の形</summary>
    public string Id { get; set; } = MeetingIds.New();
    public double Start { get; set; }
    public double? End { get; set; }

    public OffRecordSpan() { }

    public OffRecordSpan(double start, double? end = null)
    {
        Start = start;
        End = end;
    }

    public bool Contains(double time) => Start <= time && time < (End ?? double.PositiveInfinity);
}

// 要件: REQ-MTG-044, REQ-MTG-045, REQ-MTG-046
/// <summary>発言を議事録に使うか。使わないなら、その理由（文字起こしに添える）</summary>
public enum MinutesUse
{
    Used,
    /// <summary>議事録から除いた（発言ごと）</summary>
    Excluded,
    /// <summary>オフレコの区間の中</summary>
    OffRecord,
    /// <summary>除いた話者の発言</summary>
    SpeakerExcluded,
    /// <summary>範囲（最初と最後）の外</summary>
    OutsideRange,
}

/// <summary>文字起こしに出す発言のまとまり。使う発言と使わない発言はまとめない</summary>
/// <param name="Block">まとめた発言（ID は先頭の発言の ID）</param>
/// <param name="Members">まとめた発言の ID</param>
/// <param name="LastStart">まとめた最後の発言の開始時刻（「ここまで議事録に使う」で、この発言まで入れるため）</param>
/// <param name="Use">議事録に使うか</param>
public sealed record TranscriptDisplayBlock(Utterance Block, IReadOnlyList<string> Members, double LastStart, MinutesUse Use)
{
    public string Id => Block.Id;
    public bool IsUsed => Use == MinutesUse.Used;
}

// 要件: REQ-MTG-044, REQ-MTG-045, REQ-MTG-046
// 設計判断: DEC-MTG-090
public sealed partial class Meeting
{
    /// <summary>発言を議事録に使うか。発言ごとの除外 → オフレコ → 話者 → 範囲 の順に理由を見る</summary>
    public MinutesUse MinutesUseOf(Utterance utterance)
    {
        if (ExcludedUtterances?.Contains(utterance.Id) == true) return MinutesUse.Excluded;
        if (IsOffRecord(utterance.Start)) return MinutesUse.OffRecord;
        if (ExcludedSpeakers?.Contains(utterance.Speaker) == true) return MinutesUse.SpeakerExcluded;
        if (MinutesFrom is { } from && utterance.Start < from) return MinutesUse.OutsideRange;
        if (MinutesTo is { } to && utterance.Start > to) return MinutesUse.OutsideRange;
        return MinutesUse.Used;
    }

    /// <summary>その時刻がオフレコの区間の中か</summary>
    public bool IsOffRecord(double time) => OffRecord?.Any(s => s.Contains(time)) == true;

    /// <summary>議事録に使う発言（時刻の順）</summary>
    [JsonIgnore]
    public IReadOnlyList<Utterance> UsedUtterances =>
        Utterances.Where(u => MinutesUseOf(u) == MinutesUse.Used).OrderBy(u => u.Start).ToList();

    /// <summary>議事録の選び方（範囲・除外・オフレコ）を何か設定しているか</summary>
    [JsonIgnore]
    public bool HasMinutesSelection =>
        MinutesFrom is not null || MinutesTo is not null || ExcludedUtterances is { Count: > 0 }
        || ExcludedSpeakers is { Count: > 0 } || OffRecord is { Count: > 0 };

    // 設計判断: DEC-MTG-090
    /// <summary>
    /// 文字起こしに出すまとまり。MergedBlocks と同じく同じ話者の続く発言をまとめるが、使う・使わないが変わるところでは分ける
    /// （そのため、MergedBlocks の区切りは必ずここでも区切りになる）。元の発言は変えない
    /// </summary>
    public List<TranscriptDisplayBlock> DisplayBlocks(double maxGap = 2.0)
    {
        var blocks = new List<TranscriptDisplayBlock>();
        foreach (var u in Utterances.OrderBy(u => u.Start))
        {
            var use = MinutesUseOf(u);
            if (blocks.Count > 0 && blocks[^1] is var last && last.Block.Speaker == u.Speaker && u.Start - last.Block.End <= maxGap && last.Use == use)
            {
                last.Block.Text += u.Text;
                last.Block.End = Math.Max(last.Block.End, u.End);
                blocks[^1] = last with { Members = [.. last.Members, u.Id], LastStart = u.Start };
            }
            else
            {
                blocks.Add(new TranscriptDisplayBlock(u.Copy(), [u.Id], u.Start, use));
            }
        }
        return blocks;
    }

    // 設計判断: DEC-MTG-091
    /// <summary>議事録・AI・書き出しに渡す発言のまとまり（使う発言だけ）</summary>
    public List<Utterance> BlocksForMinutes() => DisplayBlocks().Where(b => b.IsUsed).Select(b => b.Block).ToList();

    // MARK: - 変える（どれも MinutesOutdated を true にする。DEC-MTG-092）

    /// <summary>発言を除く・戻す</summary>
    public void SetExcluded(IEnumerable<string> ids, bool excluded)
    {
        var list = ExcludedUtterances ?? new List<string>();
        var targets = ids.ToList();
        if (excluded)
        {
            foreach (var id in targets) if (!list.Contains(id)) list.Add(id);
        }
        else
        {
            list.RemoveAll(targets.Contains);
        }
        ExcludedUtterances = list.Count == 0 ? null : list;
        MinutesOutdated = true;
    }

    /// <summary>話者の発言をすべて除く・戻す</summary>
    public void SetSpeakerExcluded(string speaker, bool excluded)
    {
        var list = ExcludedSpeakers ?? new List<string>();
        if (excluded)
        {
            if (!list.Contains(speaker)) list.Add(speaker);
        }
        else
        {
            list.Remove(speaker);
        }
        ExcludedSpeakers = list.Count == 0 ? null : list;
        MinutesOutdated = true;
    }

    /// <summary>発言を「使う」にする。発言ごとの除外を外し、範囲の外なら範囲を広げる（話者・オフレコで除いていれば使えない）</summary>
    public void Include(IEnumerable<string> ids)
    {
        var targets = ids.ToList();
        SetExcluded(targets, excluded: false);
        var starts = Utterances.Where(u => targets.Contains(u.Id)).Select(u => u.Start).ToList();
        if (starts.Count == 0) return;
        if (MinutesFrom is { } from && starts.Min() < from) MinutesFrom = starts.Min();
        if (MinutesTo is { } to && starts.Max() > to) MinutesTo = starts.Max();
    }

    /// <summary>議事録に使う範囲の最初を変える（null で端から）。最後より後になったら、最後を外す</summary>
    public void SetMinutesFrom(double? from)
    {
        MinutesFrom = from;
        if (from is { } value && MinutesTo is { } to && to < value) MinutesTo = null;
        MinutesOutdated = true;
    }

    /// <summary>議事録に使う範囲の最後を変える（null で端まで）。最初より前になったら、最初を外す</summary>
    public void SetMinutesTo(double? to)
    {
        MinutesTo = to;
        if (to is { } value && MinutesFrom is { } from && from > value) MinutesFrom = null;
        MinutesOutdated = true;
    }

    /// <summary>オフレコの区間を消す（その間の発言をまた使う）</summary>
    public void RemoveOffRecord(string id)
    {
        OffRecord?.RemoveAll(s => s.Id == id);
        if (OffRecord is { Count: 0 }) OffRecord = null;
        MinutesOutdated = true;
    }

    /// <summary>議事録の選び方をすべて元に戻す</summary>
    public void ClearMinutesSelection()
    {
        MinutesFrom = null;
        MinutesTo = null;
        ExcludedUtterances = null;
        ExcludedSpeakers = null;
        OffRecord = null;
        MinutesOutdated = true;
    }
}
