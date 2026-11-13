using Hanasu.Core.Audio;
using Hanasu.Core.Ai;
using Hanasu.Core.Gemini;
using Hanasu.Core.Settings;
using Hanasu.Core.Text;
using Hanasu.Core.Transcription;

namespace Hanasu.Core.Meetings;

/// <summary>後処理の結果。Warnings は会議は作れたが知らせたいこと（話者分離に失敗した、など）</summary>
public sealed record MeetingProcessResult(Meeting Meeting, IReadOnlyList<string> Warnings);

/// <summary>
/// 記録のあとの処理: チャンネルごとの文字起こし → 相手側の話者分離 → 話者の割り当て（回り込みの除去）→ 議事録 → 保存。
/// アプリ（MeetingController）と確認用の CLI（meeting-files）で同じものを使う。Mac 版 MeetingRecorder の後処理にあたる。
/// </summary>
public sealed class MeetingPostProcessor
{
    public required MeetingStore Store { get; init; }
    public required ISegmentTranscriber Transcriber { get; init; }
    public required TranscriptionContext Context { get; init; }
    /// <summary>null なら話者分離をしない（相手側は全部「相手」）</summary>
    public ISpeakerDiarizer? Diarizer { get; init; }
    /// <summary>議事録を作るクライアント（会議の AI。Gemini か Claude）。認証情報がなければ null を返す。null（関数ごと）なら議事録を作らない</summary>
    public Func<ITextGenerator?>? MinutesClient { get; init; }
    /// <summary>会議の AI の名前（知らせの文言に使う）</summary>
    public TextAiProvider MinutesProvider { get; init; } = TextAiProvider.Gemini;
    public string MinutesModel { get; init; } = "gemini-3.8-flash";
    public Action<string>? Log { get; init; }
    // 要件: REQ-DIC-073
    // 設計判断: DEC-DIC-173
    /// <summary>確定した発言に当てる辞書。null なら当てない</summary>
    public UserDictionary? Dictionary { get; init; }
    /// <summary>設定の「文字起こしに辞書の置き換えルールを当てる」</summary>
    public bool ApplyDictionary { get; init; }

    public async Task<MeetingProcessResult> ProcessAsync(Meeting meeting, IProgress<string>? progress = null,
        CancellationToken cancellationToken = default)
    {
        var warnings = new List<string>();
        var failures = new List<string>();
        var failedChannels = new List<MeetingChannel>();
        meeting.Status = MeetingStatus.Processing;
        meeting.ErrorMessage = null;
        // 失敗がなくても空の配列を書く（キーがないのは、この機能より前の会議だけにする。DEC-MTG-142）
        meeting.TranscriptionFailedChannels = new List<MeetingChannel>();
        Store.Save(meeting);

        var offsets = meeting.AudioStartOffsets ?? new Dictionary<string, double>();
        var (me, _) = await TranscribeChannelAsync(meeting, MeetingChannel.Me, offsets.GetValueOrDefault("me"), failures, failedChannels, progress, cancellationToken)
            .ConfigureAwait(false);
        var (others, othersSamples) = await TranscribeChannelAsync(meeting, MeetingChannel.Others, offsets.GetValueOrDefault("others"), failures, failedChannels, progress, cancellationToken)
            .ConfigureAwait(false);

        IReadOnlyList<SpeakerTurn> turns = Array.Empty<SpeakerTurn>();
        if (Diarizer is not null && others.Count > 0 && othersSamples is not null)
        {
            progress?.Report(Strings.Meeting_Diarizing);
            try
            {
                var offset = offsets.GetValueOrDefault("others");
                turns = (await Diarizer.DiarizeAsync(othersSamples, progress, cancellationToken).ConfigureAwait(false))
                    .Select(t => t with { Start = t.Start + offset, End = t.End + offset })
                    .ToList();
                Log?.Invoke($"diarization: {turns.Count} turns, {turns.Select(t => t.SpeakerId).Distinct().Count()} speakers");
            }
            catch (Exception e) when (e is not OperationCanceledException)
            {
                // 話者分離に失敗しても、相手側を「相手」1 人として続ける（Mac 版と同じ）
                // 設計判断: DEC-MTG-104（作れなかったときの手がかりを、知らせには出さずログにだけ書く）
                var diagnostics = e.Data["hanasu.diagnostics"] is string d ? $" ({d})" : "";
                Log?.Invoke($"diarization failed: {e.GetType().Name}: {e.Message}{diagnostics}");
                warnings.Add(string.Format(Strings.Meeting_DiarizationFailed, e.Message));
            }
        }
        othersSamples = null;

        meeting.Utterances = MeetingProcessor.BuildUtterances(me, others, turns);
        // 要件: REQ-DIC-073
        // 設計判断: DEC-DIC-173
        // 確定した発言に、議事録を作る前に辞書の置き換えルールを当てる（記録中の発言には当てない）
        MeetingDictionary.ApplyOnFinish(meeting, Dictionary, ApplyDictionary);
        var errors = new List<string>();
        // 要件: REQ-MTG-010
        // 設計判断: DEC-MTG-009, DEC-MTG-140, DEC-MTG-142
        // 失敗したチャンネルは、消す設定かどうかに関わらず書く。「音声ファイルは残しています」はエラーの文に入れない（表示のときに決める）
        if (failures.Count > 0)
        {
            errors.Add(string.Join("\n", failures));
            meeting.TranscriptionFailedChannels = failedChannels;
        }
        Store.Save(meeting);

        // 設計判断: DEC-MTG-091（使う発言がなければ議事録を作らない）
        if (MinutesClient is not null && meeting.UsedUtterances.Count > 0)
        {
            ITextGenerator? client = null;
            string? authError = null;
            try
            {
                client = MinutesClient();
            }
            catch (ServiceAccountException e)
            {
                authError = string.Format(Strings.Meeting_MinutesFailed, e.Message);
            }
            if (client is null)
            {
                errors.Add(authError ?? string.Format(Strings.Meeting_MinutesNotCreated, TextAiFactory.NotReadyBecause(MinutesProvider)));
            }
            else
            {
                progress?.Report(string.Format(Strings.Meeting_MakingMinutes, client.ProviderName));
                try
                {
                    var result = await MeetingProcessor.MakeMinutesAsync(meeting, client, MinutesModel, cancellationToken).ConfigureAwait(false);
                    // 要件: REQ-MTG-027
                    meeting.ApplyMinutes(result);
                }
                catch (TextAiException e)
                {
                    Log?.Invoke($"minutes failed: {e.GetType().Name}");
                    errors.Add(string.Format(Strings.Meeting_MinutesFailed, e.Message));
                }
            }
        }

        // 両方のチャンネルとも文字起こしに失敗したときだけ「失敗」。片方でも残れば、注意を添えて「完了」
        meeting.Status = failures.Count >= 2 && meeting.Utterances.Count == 0 ? MeetingStatus.Failed : MeetingStatus.Done;
        meeting.ErrorMessage = errors.Count == 0 ? null : string.Join("\n", errors);
        Store.Save(meeting);

        // 要件: REQ-MTG-010
        // 設計判断: DEC-MTG-139, DEC-MTG-142
        // 設定ではなく会議の値と文字起こしの状態で決める（文字起こしがそろっていなければ残す）。保存期間の削除はここでは行わない（DEC-MTG-143）
        if (MeetingAudioPolicy.ShouldDeleteAfterProcessing(meeting))
        {
            var failed = Store.DeleteAudio(meeting);
            Log?.Invoke(failed.Count == 0 ? "meeting audio deleted after processing" : $"meeting audio delete failed: {failed.Count} files");
        }
        return new MeetingProcessResult(meeting, warnings);
    }

    private async Task<(List<TranscribedPhrase> Phrases, float[]? Samples)> TranscribeChannelAsync(Meeting meeting, MeetingChannel channel,
        double offset, List<string> failures, List<MeetingChannel> failedChannels, IProgress<string>? progress, CancellationToken cancellationToken)
    {
        var path = Store.AudioPath(meeting, channel);
        var label = channel == MeetingChannel.Me ? Strings.Speaker_Me : Strings.Speaker_Others;
        if (!File.Exists(path)) return (new(), null);
        try
        {
            var samples = await Task.Run(() => WavFile.DecodeTo16kMono(File.ReadAllBytes(path)), cancellationToken).ConfigureAwait(false);
            // ほぼ無音のチャンネル（相手がいない、マイクを切っていた）は送らない
            if (MeetingAudio.IsNearlySilent(samples)) return (new(), null);
            progress?.Report(string.Format(Strings.Meeting_TranscribingChannel, Transcriber.DisplayName, label));
            var inner = progress is null ? null : new InlineProgress<string>(p => progress.Report(string.Format(Strings.Meeting_TranscribingChannelProgress, Transcriber.DisplayName, label, p)));
            IReadOnlyList<TimedSegment> segments = await Transcriber.TranscribeSegmentsAsync(samples, Context, inner, cancellationToken).ConfigureAwait(false);
            segments = MeetingAudio.SnapToSpeech(segments, samples);
            Log?.Invoke($"transcribed {channel}: {segments.Count} segments");
            return (MeetingProcessor.Phrases(segments, channel, offset), samples);
        }
        catch (Exception e) when (e is TranscriptionException or InvalidDataException or IOException)
        {
            Log?.Invoke($"transcription failed ({channel}): {e.GetType().Name}");
            failures.Add(string.Format(Strings.Meeting_ChannelTranscriptionFailed, label, e.Message));
            failedChannels.Add(channel);
            return (new(), null);
        }
    }
}
