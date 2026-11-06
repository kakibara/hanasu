namespace Hanasu.Core.Meetings;

// 要件: REQ-MTG-043
/// <summary>記録中に PC がスリープした時点。「スリープ前までで止める」を選んだら、ここで記録を切る</summary>
/// <param name="Elapsed">スリープした時点の、録音開始からの秒数（スリープしていた時間は数えない。DEC-MTG-111）</param>
/// <param name="At">スリープした時計の時刻（確認に出す）</param>
public sealed record MeetingSleepPoint(double Elapsed, DateTimeOffset At);

// 要件: REQ-MTG-043
// 設計判断: DEC-MTG-088, DEC-MTG-111
/// <summary>「スリープ前までで止める」ときに、スリープより後の分を会議から除く（Mac 版の MeetingSleepCut と同じ決まり）</summary>
public static class MeetingSleepCut
{
    /// <summary>
    /// 会議の長さをスリープした時点までにし、それより後の「ここ重要」の印を消し、メモは時刻をスリープした時点にそろえる。
    /// オフレコの区間は、スリープの後に始めたものを消し、終わりをスリープした時点までにする
    /// </summary>
    public static void Apply(Meeting meeting, MeetingSleepPoint point)
    {
        meeting.Duration = point.Elapsed;
        // 要件: REQ-MTG-046
        // 設計判断: DEC-MTG-094
        // スリープの後に始めたオフレコは消し、終わりはスリープした時点まで
        if (meeting.OffRecord is { } spans)
        {
            spans.RemoveAll(s => s.Start >= point.Elapsed);
            foreach (var span in spans) span.End = Math.Min(span.End ?? point.Elapsed, point.Elapsed);
            if (spans.Count == 0) meeting.OffRecord = null;
        }
        if (meeting.Notes is null) return;
        meeting.Notes.RemoveAll(n => n.Kind == MeetingNoteKind.Highlight && n.Time > point.Elapsed);
        foreach (var note in meeting.Notes)
        {
            if (note.Time > point.Elapsed) note.Time = point.Elapsed;
        }
    }
}
