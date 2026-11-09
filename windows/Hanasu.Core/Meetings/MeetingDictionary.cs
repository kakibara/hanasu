using Hanasu.Core.Text;

namespace Hanasu.Core.Meetings;

/// <summary>当てた（戻した）結果。Changed は当てる前と比べて Text が変わった発言の数、Replaced は辞書で置き換えてある発言の数</summary>
public sealed record MeetingDictionaryOutcome(int Changed, int Replaced);

// 要件: REQ-DIC-073, REQ-DIC-074
// 設計判断: DEC-DIC-172
/// <summary>
/// 会議の文字起こしに辞書の置き換えルールを当てる・認識したままの文に戻す（Mac 版 MeetingDictionary.swift の移植）。
/// 置き換えは発言ごとに、認識したままの文（RawText。なければ Text）から当てる。Text が変わったときだけ RawText を残す。
/// </summary>
public static class MeetingDictionary
{
    /// <summary>発言に今の辞書を当てた写しを返す（認識したままの文から）</summary>
    public static Utterance Apply(UserDictionary dictionary, Utterance utterance)
    {
        var u = utterance.Copy();
        var recognized = utterance.RecognizedText;
        var text = dictionary.Apply(recognized);
        u.Text = text;
        u.RawText = text == recognized ? null : recognized;
        return u;
    }

    /// <summary>会議のすべての発言に今の辞書を当てる（meeting を書き換える）</summary>
    public static MeetingDictionaryOutcome Apply(UserDictionary dictionary, Meeting meeting) =>
        Rewrite(meeting, u => Apply(dictionary, u));

    /// <summary>会議のすべての発言を、認識したままの文に戻す（meeting を書き換える）</summary>
    public static MeetingDictionaryOutcome Revert(Meeting meeting) =>
        Rewrite(meeting, u =>
        {
            var copy = u.Copy();
            copy.Text = u.RecognizedText;
            copy.RawText = null;
            return copy;
        });

    // 要件: REQ-DIC-073
    // 設計判断: DEC-DIC-173
    /// <summary>記録を止めて文字起こしが確定した直後に呼ぶ。設定がオフなら何もしない</summary>
    public static void ApplyOnFinish(Meeting meeting, UserDictionary? dictionary, bool enabled)
    {
        if (!enabled || dictionary is null || dictionary.Rules.Count == 0) return;
        Apply(dictionary, meeting);
    }

    /// <summary>辞書で置き換えてある発言の数</summary>
    public static int ReplacedCount(Meeting meeting) => meeting.Utterances.Count(u => u.RawText != null);

    // 設計判断: DEC-DIC-174
    /// <summary>発言を書き換え、変わった数を数える。変わって議事録があれば、作り直しを促す</summary>
    private static MeetingDictionaryOutcome Rewrite(Meeting meeting, Func<Utterance, Utterance> change)
    {
        var changed = 0;
        meeting.Utterances = meeting.Utterances.Select(u =>
        {
            var updated = change(u);
            if (updated.Text != u.Text) changed++;
            return updated;
        }).ToList();
        if (changed > 0 && meeting.Minutes != null) meeting.MinutesOutdated = true;
        return new MeetingDictionaryOutcome(changed, ReplacedCount(meeting));
    }
}

// 要件: REQ-DIC-074
/// <summary>会議に辞書を当て直せなかった。Message は「この会議を変えられませんでした: 〜」の形で、そのまま知らせに出せる</summary>
public sealed class MeetingDictionaryException(string reason, Exception? inner = null)
    : Exception(string.Format(Hanasu.Core.Properties.Strings.Meeting_Dictionary_Failed, reason), inner);
