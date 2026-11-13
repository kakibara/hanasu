using System.Buffers.Binary;
using System.Text;

namespace Hanasu.Core.Meetings;

// 要件: REQ-MTG-128
// 設計判断: DEC-MTG-158
/// <summary>
/// 記録中に落ちた会議を、残った録音から作り直すときの決まり（Mac 版の MeetingRecovery と同じ）。
/// ボタンを出す条件・会議の長さ・終わっていないオフレコの閉じ方。ファイルを読むのは <see cref="ReadableAudioSeconds"/> だけ
/// </summary>
public static class MeetingRecovery
{
    /// <summary>meeting.json の AudioStartOffsets のキー（"me" / "others"）</summary>
    public static string OffsetKey(MeetingChannel channel) => channel == MeetingChannel.Me ? "me" : "others";

    // 要件: REQ-MTG-128
    // 設計判断: DEC-MTG-158
    /// <summary>
    /// 録音から作り直すボタンを出すか。発言が 0 件、読める録音（Windows の後処理が読む me.wav・others.wav）のうち 1 つ以上の長さが 0 より大きい、
    /// 状態が「記録中」「処理中」ではない、忙しくない（その会議を作り直し中・議事録を作り直し中、このアプリで記録・後処理・作り直しをしている）。
    /// 状態が「失敗」か「完了」かでは決めない
    /// </summary>
    /// <param name="readableAudioSeconds">チャンネルごとの、読める録音の長さ（秒）。読めない・ないチャンネルは入れないか 0</param>
    public static bool CanRecover(Meeting meeting, IReadOnlyDictionary<MeetingChannel, double> readableAudioSeconds, bool busy)
    {
        if (busy) return false;
        if (meeting.Status is MeetingStatus.Recording or MeetingStatus.Processing) return false;
        if (meeting.Utterances.Count > 0) return false;
        return readableAudioSeconds.Values.Any(seconds => seconds > 0);
    }

    // 要件: REQ-MTG-128
    /// <summary>会議の長さ = 残った録音の終わり（チャンネルごとの先頭のずれ＋長さの、大きいほう）。録音がなければ 0</summary>
    public static double Duration(IReadOnlyDictionary<string, double>? offsets, IReadOnlyDictionary<MeetingChannel, double> audioSeconds)
    {
        var end = 0.0;
        foreach (var (channel, seconds) in audioSeconds)
        {
            if (seconds <= 0) continue;
            var offset = offsets is not null && offsets.TryGetValue(OffsetKey(channel), out var o) ? o : 0;
            end = Math.Max(end, offset + seconds);
        }
        return end;
    }

    // 要件: REQ-MTG-128
    // 設計判断: DEC-MTG-094
    /// <summary>終わっていないオフレコの区間を、at（録音の終わり）で閉じる。閉じた区間があれば true</summary>
    public static bool CloseOpenOffRecord(List<OffRecordSpan>? spans, double at)
    {
        if (spans is null) return false;
        var closed = false;
        foreach (var span in spans.Where(s => s.End is null))
        {
            span.End = Math.Max(span.Start, at);
            closed = true;
        }
        return closed;
    }

    // 要件: REQ-MTG-128
    // 設計判断: DEC-MTG-159
    /// <summary>
    /// 録音（WavStreamWriter で書いた WAV）の、読める長さ（秒）。ヘッダーの長さの欄は見ず、ファイルの長さから計算する（落ちた WAV のヘッダーは古いため）。
    /// ない・WAV でない・読めないなら 0
    /// </summary>
    public static double WavSeconds(string path)
    {
        try
        {
            if (!File.Exists(path)) return 0;
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            const int headerLength = 44;
            if (stream.Length <= headerLength) return 0;
            Span<byte> header = stackalloc byte[headerLength];
            stream.ReadExactly(header);
            if (Encoding.ASCII.GetString(header[..4]) != "RIFF" || Encoding.ASCII.GetString(header[8..12]) != "WAVE"
                || Encoding.ASCII.GetString(header[12..16]) != "fmt " || Encoding.ASCII.GetString(header[36..40]) != "data")
            {
                return 0;
            }
            var rate = BinaryPrimitives.ReadInt32LittleEndian(header[24..]);
            var blockAlign = BinaryPrimitives.ReadInt16LittleEndian(header[32..]);
            if (rate <= 0 || blockAlign <= 0) return 0;
            return (stream.Length - headerLength) / blockAlign / (double)rate;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            return 0;
        }
    }

    // 要件: REQ-MTG-128
    /// <summary>会議の 2 つの録音（me.wav・others.wav）の読める長さ。m4a（Mac で記録した会議）は数えない</summary>
    public static Dictionary<MeetingChannel, double> ReadableAudioSeconds(MeetingStore store, Meeting meeting) => new()
    {
        [MeetingChannel.Me] = WavSeconds(store.AudioPath(meeting, MeetingChannel.Me)),
        [MeetingChannel.Others] = WavSeconds(store.AudioPath(meeting, MeetingChannel.Others)),
    };
}
