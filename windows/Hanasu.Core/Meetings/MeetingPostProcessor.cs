using Hanasu.Core.Audio;
using Hanasu.Core.Gemini;
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
    /// <summary>議事録を作るクライアント。認証情報がなければ null を返す。null（関数ごと）なら議事録を作らない</summary>
    public Func<GeminiClient?>? MinutesClient { get; init; }
    public string MinutesModel { get; init; } = "gemini-3.8-flash";
    /// <summary>false なら、処理のあとで音声ファイルを消す（文字起こしに失敗したチャンネルがあれば残す）</summary>
    public bool KeepAudio { get; init; } = true;
    public Action<string>? Log { get; init; }

    public async Task<MeetingProcessResult> ProcessAsync(Meeting meeting, IProgress<string>? progress = null,
        CancellationToken cancellationToken = default)
    {
        var warnings = new List<string>();
        var failures = new List<string>();
        meeting.Status = MeetingStatus.Processing;
        meeting.ErrorMessage = null;
        Store.Save(meeting);

        var offsets = meeting.AudioStartOffsets ?? new Dictionary<string, double>();
        var (me, _) = await TranscribeChannelAsync(meeting, MeetingChannel.Me, offsets.GetValueOrDefault("me"), failures, progress, cancellationToken)
            .ConfigureAwait(false);
        var (others, othersSamples) = await TranscribeChannelAsync(meeting, MeetingChannel.Others, offsets.GetValueOrDefault("others"), failures, progress, cancellationToken)
            .ConfigureAwait(false);

        IReadOnlyList<SpeakerTurn> turns = Array.Empty<SpeakerTurn>();
        if (Diarizer is not null && others.Count > 0 && othersSamples is not null)
        {
            progress?.Report("相手側の話者を分けています…");
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
                Log?.Invoke($"diarization failed: {e.GetType().Name}: {e.Message}");
                warnings.Add($"相手側の話者を分けられなかったので、「相手」1 人としてまとめました（{e.Message}）");
            }
        }
        othersSamples = null;

        meeting.Utterances = MeetingProcessor.BuildUtterances(me, others, turns);
        var errors = new List<string>();
        if (failures.Count > 0)
        {
            errors.Add(string.Join("\n", failures) + "\n音声ファイルは残しています。");
        }
        Store.Save(meeting);

        if (MinutesClient is not null && meeting.Utterances.Count > 0)
        {
            GeminiClient? client = null;
            string? authError = null;
            try
            {
                client = MinutesClient();
            }
            catch (ServiceAccountException e)
            {
                authError = $"議事録を作れませんでした: {e.Message}";
            }
            if (client is null)
            {
                errors.Add(authError ?? "Gemini の認証情報が設定されていないため、議事録は作っていません（メニュー → 設定 → Gemini）。");
            }
            else
            {
                progress?.Report("Gemini で議事録を作っています…");
                try
                {
                    var result = await MeetingProcessor.MakeMinutesAsync(meeting, client, MinutesModel, cancellationToken).ConfigureAwait(false);
                    meeting.Minutes = result.Markdown;
                    meeting.ActionItems = result.ActionItems;
                }
                catch (GeminiException e)
                {
                    Log?.Invoke($"minutes failed: {e.Kind}");
                    errors.Add($"議事録を作れませんでした: {e.Message}");
                }
            }
        }

        // 両方のチャンネルとも文字起こしに失敗したときだけ「失敗」。片方でも残れば、注意を添えて「完了」
        meeting.Status = failures.Count >= 2 && meeting.Utterances.Count == 0 ? MeetingStatus.Failed : MeetingStatus.Done;
        meeting.ErrorMessage = errors.Count == 0 ? null : string.Join("\n", errors);
        Store.Save(meeting);

        if (!KeepAudio && failures.Count == 0) Store.DeleteAudio(meeting);
        return new MeetingProcessResult(meeting, warnings);
    }

    private async Task<(List<TranscribedPhrase> Phrases, float[]? Samples)> TranscribeChannelAsync(Meeting meeting, MeetingChannel channel,
        double offset, List<string> failures, IProgress<string>? progress, CancellationToken cancellationToken)
    {
        var path = Store.AudioPath(meeting, channel);
        var label = channel == MeetingChannel.Me ? "自分" : "相手";
        if (!File.Exists(path)) return (new(), null);
        try
        {
            var samples = await Task.Run(() => WavFile.DecodeTo16kMono(File.ReadAllBytes(path)), cancellationToken).ConfigureAwait(false);
            // ほぼ無音のチャンネル（相手がいない、マイクを切っていた）は送らない
            if (MeetingAudio.IsNearlySilent(samples)) return (new(), null);
            progress?.Report($"{Transcriber.DisplayName} で文字起こししています…（{label}）");
            var inner = progress is null ? null : new InlineProgress<string>(p => progress.Report($"{Transcriber.DisplayName} で文字起こししています…（{label} {p}）"));
            IReadOnlyList<TimedSegment> segments = await Transcriber.TranscribeSegmentsAsync(samples, Context, inner, cancellationToken).ConfigureAwait(false);
            segments = MeetingAudio.SnapToSpeech(segments, samples);
            Log?.Invoke($"transcribed {channel}: {segments.Count} segments");
            return (MeetingProcessor.Phrases(segments, channel, offset), samples);
        }
        catch (Exception e) when (e is TranscriptionException or InvalidDataException or IOException)
        {
            Log?.Invoke($"transcription failed ({channel}): {e.GetType().Name}");
            failures.Add($"{label}の音声を文字起こしできませんでした: {e.Message}");
            return (new(), null);
        }
    }
}
