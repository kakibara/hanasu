using Hanasu.Core.Gemini;

namespace Hanasu.Core.Meetings;

/// <summary>話者分離の結果の 1 区間（時刻は録音開始を 0 秒とした秒数）</summary>
public sealed record SpeakerTurn(string SpeakerId, double Start, double End);

/// <summary>相手側の音声を話者ごとの区間に分ける部品。失敗したら例外を投げる（呼ぶ側で「相手」1 人として扱う）</summary>
public interface ISpeakerDiarizer
{
    /// <summary>16 kHz・モノラルの音声を分ける。返す時刻は音声の先頭を 0 秒とした秒数</summary>
    Task<IReadOnlyList<SpeakerTurn>> DiarizeAsync(float[] samples, IProgress<string>? progress = null, CancellationToken cancellationToken = default);
}

/// <summary>
/// 録音の後処理: 話者の割り当て、回り込みの除去、議事録の作成。Mac 版 MeetingProcessor.swift の移植（手順を変えるときは両方を直す）。
/// </summary>
public static class MeetingProcessor
{
    /// <summary>
    /// 自分と相手の発話から、話者つきの発言を作る。
    /// turns は相手側の話者分離の結果。空なら相手側は "others" 1 人として扱う。
    /// </summary>
    public static List<Utterance> BuildUtterances(IReadOnlyList<TranscribedPhrase> me, IReadOnlyList<TranscribedPhrase> others,
        IReadOnlyList<SpeakerTurn> turns)
    {
        var theirs = new List<Utterance>();
        if (turns.Count == 0)
        {
            theirs.AddRange(others.Select(p => new Utterance("others", p.Start, p.End, p.Text)));
        }
        else
        {
            foreach (var phrase in others) theirs.AddRange(AbsorbShortEdges(Split(WordsOf(phrase), turns)));
            theirs = RenumberSpeakers(theirs);
        }

        var mine = new List<Utterance>();
        foreach (var group in RemoveEcho(me, others))
        {
            var text = string.Concat(group.Select(w => w.Text)).Trim();
            mine.Add(new Utterance("me", group[0].Start, group[^1].End, text));
        }
        return mine.Concat(theirs).OrderBy(u => u.Start).ToList();
    }

    private static IReadOnlyList<TimedWord> WordsOf(TranscribedPhrase phrase) =>
        phrase.Words.Count == 0 ? [new TimedWord(phrase.Text, phrase.Start, phrase.End)] : phrase.Words;

    /// <summary>語を話者へ割り当て、同じ話者が続く語をまとめる</summary>
    public static List<Utterance> Split(IReadOnlyList<TimedWord> words, IReadOnlyList<SpeakerTurn> turns)
    {
        var result = new List<Utterance>();
        foreach (var word in words)
        {
            // 無音のあとの語は無音の分まで長くなるので、語の終わり寄りの時刻で話者を決める
            var coreStart = Math.Max(word.Start, word.End - 0.4);
            var speaker = SpeakerAt((coreStart + word.End) / 2, coreStart, turns);
            if (result.Count > 0 && result[^1].Speaker == speaker)
            {
                result[^1].Text += word.Text;
                result[^1].End = word.End;
            }
            else
            {
                result.Add(new Utterance(speaker, word.Start, word.End, word.Text));
            }
        }
        foreach (var u in result) u.Text = u.Text.Trim(' ');
        return result.Where(u => u.Text.Length > 0).ToList();
    }

    /// <summary>
    /// 1 つの発話を話者で分けたとき、端に残った短いかけら（1 秒未満で 4 文字以下）を隣にまとめる（Windows 版で足したもの）。
    /// Whisper の語の時刻は実際より少し遅れることがあり、話者が変わるところで、前の人の最後の語（「でした。」など）が
    /// 次の人に付きやすいため。Whisper の区間は間（ま）で切れるので、1 区間の端の短いかけらは、たいてい隣と同じ人
    /// </summary>
    public static List<Utterance> AbsorbShortEdges(List<Utterance> pieces)
    {
        static bool IsShort(Utterance u) => u.End - u.Start < 1.0 && u.Text.Count(c => !char.IsPunctuation(c) && !char.IsWhiteSpace(c)) <= 4;
        while (pieces.Count > 1 && IsShort(pieces[0]))
        {
            pieces[1].Text = pieces[0].Text + pieces[1].Text;
            pieces[1].Start = pieces[0].Start;
            pieces.RemoveAt(0);
        }
        while (pieces.Count > 1 && IsShort(pieces[^1]))
        {
            pieces[^2].Text += pieces[^1].Text;
            pieces[^2].End = pieces[^1].End;
            pieces.RemoveAt(pieces.Count - 1);
        }
        return pieces;
    }

    /// <summary>
    /// その時刻を含む区間の話者。区間と区間のすき間にある語は、前の区間の終わりから間があいて
    /// 始まっていれば次の話者（話者分離は話し始めの検出が遅れがち）、そうでなければ前の話者とする
    /// </summary>
    public static string SpeakerAt(double time, double? wordStart, IReadOnlyList<SpeakerTurn> turns, double pause = 0.3)
    {
        if (turns.FirstOrDefault(t => t.Start <= time && time <= t.End) is { } hit) return hit.SpeakerId;
        var previous = turns.Where(t => t.End < time).MaxBy(t => t.End);
        var next = turns.Where(t => t.Start > time).MinBy(t => t.Start);
        return (previous, next) switch
        {
            ({ } p, { } n) => (wordStart ?? time) - p.End > pause ? n.SpeakerId : p.SpeakerId,
            ({ } p, null) => p.SpeakerId,
            (null, { } n) => n.SpeakerId,
            _ => "others",
        };
    }

    /// <summary>話者分離の ID（"0" など）を、登場順に spk1, spk2, ... に付け直す</summary>
    public static List<Utterance> RenumberSpeakers(IEnumerable<Utterance> utterances)
    {
        var mapping = new Dictionary<string, string>();
        var result = new List<Utterance>();
        foreach (var u in utterances.OrderBy(u => u.Start))
        {
            if (!mapping.TryGetValue(u.Speaker, out var key))
            {
                key = $"spk{mapping.Count + 1}";
                mapping[u.Speaker] = key;
            }
            var copy = u.Copy();
            copy.Speaker = key;
            result.Add(copy);
        }
        return result;
    }

    /// <summary>
    /// スピーカーの音がマイクに回り込んで「自分」として二重に記録された部分を除き、残った語のまとまりを返す。
    /// 自分の発話を語ごとに「相手が話している時間と重なるか」で区切り、重なる部分の文字が
    /// その時間の相手の発言とよく似ていれば回り込みとみなして捨てる
    /// </summary>
    public static List<List<TimedWord>> RemoveEcho(IReadOnlyList<TranscribedPhrase> mine, IReadOnlyList<TranscribedPhrase> theirs,
        double margin = 0.3, double threshold = 0.5)
    {
        var theirWords = theirs.SelectMany(WordsOf).ToList();
        // 無音のあとの最初の語は、無音の分まで長い時間が付くことがあるので、語の終わり寄りだけで判定する
        static (double Start, double End) Core(TimedWord w) => (Math.Max(w.Start, w.End - 0.4), w.End);
        bool OverlapsTheirSpeech(TimedWord w)
        {
            var m = Core(w);
            return theirWords.Any(t =>
            {
                var c = Core(t);
                return c.Start - margin <= m.End && m.Start <= c.End + margin;
            });
        }
        string TheirText(double start, double end) =>
            string.Concat(theirs.Where(p => p.Start - 1.5 <= end && start <= p.End + 1.5).Select(p => p.Text));

        var result = new List<List<TimedWord>>();
        foreach (var phrase in mine)
        {
            // 重なる／重ならないが同じ語の連続でまとめる
            var groups = new List<(bool Overlap, List<TimedWord> Words)>();
            foreach (var word in WordsOf(phrase))
            {
                var overlap = OverlapsTheirSpeech(word);
                if (groups.Count > 0 && groups[^1].Overlap == overlap) groups[^1].Words.Add(word);
                else groups.Add((overlap, [word]));
            }
            foreach (var (overlap, words) in groups)
            {
                var text = string.Concat(words.Select(w => w.Text)).Trim();
                if (words.Count == 0 || text.Length == 0) continue;
                // 回り込み。短いかけら（6 文字未満）は「ます」「ありますか」などがたまたま似るだけのことが多いので、消さない
                // （Windows 版で足した条件。Whisper の語の時刻がずれて、重なって見えることがあるため）
                if (overlap && text.Count(c => !char.IsPunctuation(c) && !char.IsWhiteSpace(c)) >= MinEchoCharacters
                    && Similarity(text, TheirText(words[0].Start, words[^1].End)) >= threshold) continue;
                // 句読点だけの断片は直前の自分の発言にくっつける
                if (text.All(c => char.IsPunctuation(c) || char.IsWhiteSpace(c)))
                {
                    if (result.Count > 0 && result[^1].Count > 0)
                    {
                        var last = result[^1][^1];
                        result[^1][^1] = last with { Text = last.Text + text };
                    }
                    continue;
                }
                result.Add(words);
            }
        }
        return result;
    }

    /// <summary>回り込みとみなす「自分」のかけらの最小の文字数</summary>
    public const int MinEchoCharacters = 6;

    /// <summary>文字 bigram の包含率（a の bigram のうち b にも含まれる割合）</summary>
    public static double Similarity(string a, string b)
    {
        static List<string> Bigrams(string s)
        {
            var chars = s.Where(c => !char.IsWhiteSpace(c) && !char.IsPunctuation(c)).ToArray();
            if (chars.Length < 2) return chars.Select(c => c.ToString()).ToList();
            return Enumerable.Range(0, chars.Length - 1).Select(i => new string(chars, i, 2)).ToList();
        }
        var ga = Bigrams(a);
        if (ga.Count == 0) return 0;
        var gb = Bigrams(b).ToHashSet();
        return (double)ga.Count(gb.Contains) / ga.Count;
    }

    /// <summary>区間を、録音開始からの時刻の発話にする。語の時刻がない（Gemini）ときは、区間全体を 1 語として持つ</summary>
    public static List<TranscribedPhrase> Phrases(IEnumerable<TimedSegment> segments, MeetingChannel channel, double offset) =>
        segments.Select(s =>
        {
            var words = s.Words.Count == 0 ? [new TimedWord(s.Text, s.Start, s.End)] : s.Words;
            return new TranscribedPhrase(channel, offset + s.Start, offset + s.End, s.Text,
                words.Select(w => new TimedWord(w.Text, offset + w.Start, offset + w.End)).ToList());
        }).ToList();

    // MARK: - 議事録

    /// <summary>議事録を作る。見出しの構成は会議の型で決まる。メモか印があれば、それを優先するよう指示を足す</summary>
    public static async Task<MinutesResult> MakeMinutesAsync(Meeting meeting, GeminiClient client, string model,
        CancellationToken cancellationToken = default)
    {
        var body = await client.GenerateAsync(MinutesPrompt.FullInstruction(meeting), [new GeminiPart.Text(MinutesPrompt.UserText(meeting))],
            model, cancellationToken: cancellationToken).ConfigureAwait(false);
        return MinutesPrompt.Parse(body, meeting.Title);
    }
}
