using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;
using Hanasu.Core.Audio;
using Hanasu.Core.Gemini;
using Hanasu.Core.Transcription;

namespace Hanasu.Core.Meetings;

/// <summary>時刻つきの文字起こしの 1 区間。時刻は渡した音声の先頭を 0 秒とした秒数。Words が空なら、区間全体を 1 語として扱う</summary>
public sealed record TimedSegment(double Start, double End, string Text, IReadOnlyList<TimedWord> Words)
{
    public TimedSegment(double start, double end, string text) : this(start, end, text, Array.Empty<TimedWord>()) { }
}

/// <summary>
/// 会議の 1 チャンネル分の音声を、時刻つきの区間にして文字起こしする（記録のあとにまとめて）。Whisper と Gemini。
/// Mac 版 MeetingBatchTranscription / BatchTranscriber.transcribeSegments にあたる。
/// </summary>
public interface ISegmentTranscriber
{
    /// <summary>進み具合に出す名前（「Whisper」「Gemini」）</summary>
    string DisplayName { get; }

    /// <summary>記録を始める前に、使えるかを確かめる（モデルがない・認証がないなら TranscriptionException）</summary>
    Task PrepareAsync(TranscriptionContext context, CancellationToken cancellationToken = default);

    /// <param name="progress">進み具合（「（3/12）」「45%」など、括弧の中に入れる短い文言）</param>
    Task<IReadOnlyList<TimedSegment>> TranscribeSegmentsAsync(float[] samples, TranscriptionContext context,
        IProgress<string>? progress = null, CancellationToken cancellationToken = default);
}

/// <summary>会議の音声の区切り方。</summary>
public static class MeetingAudio
{
    /// <summary>ほぼ無音のチャンネル（相手がいない、マイクを切っていた）は文字起こしに送らない。Mac 版と同じしきい値</summary>
    public static bool IsNearlySilent(ReadOnlySpan<float> samples) => samples.Length == 0 || Rms(samples) <= 0.0003;

    public static double Rms(ReadOnlySpan<float> samples)
    {
        if (samples.Length == 0) return 0;
        double sum = 0;
        foreach (var x in samples) sum += x * x;
        return Math.Sqrt(sum / samples.Length);
    }

    /// <summary>
    /// 区間と語の時刻を、実際に声のあるところへ寄せる。Whisper は無音のあとの区間・語の始まりを、無音の始まりにしがち
    /// （相手のチャンネルは自分が話している間ずっと無音なので、ずれが大きい）。始まりが無音の中にある語は、その後の最初の
    /// 声のあるところ（30 ms ごとの RMS が約 -50 dBFS 以上）まで動かす。語の順番は崩さない。
    /// </summary>
    public static List<TimedSegment> SnapToSpeech(IReadOnlyList<TimedSegment> segments, ReadOnlySpan<float> samples, double threshold = 0.003)
    {
        var frame = AudioFormat.SampleRate * 30 / 1000;
        var voiced = new bool[(samples.Length + frame - 1) / frame];
        for (var i = 0; i < voiced.Length; i++)
        {
            var start = i * frame;
            voiced[i] = Rms(samples.Slice(start, Math.Min(frame, samples.Length - start))) >= threshold;
        }
        double NextVoiced(double from, double limit)
        {
            for (var i = Math.Max(0, (int)(from * 1000 / 30)); i < voiced.Length && i * 0.03 <= limit; i++)
            {
                if (voiced[i]) return Math.Max(from, i * 0.03);
            }
            return from;
        }
        var result = new List<TimedSegment>();
        foreach (var segment in segments)
        {
            var words = new List<TimedWord>();
            var floor = segment.Start;
            foreach (var w in segment.Words)
            {
                var start = NextVoiced(Math.Max(w.Start, floor), segment.End);
                var end = Math.Max(w.End, Math.Min(start + Math.Max(0.1, Math.Min(w.End - w.Start, 0.6)), segment.End));
                words.Add(w with { Start = start, End = end });
                floor = start;
            }
            var segStart = words.Count > 0 ? words[0].Start : NextVoiced(segment.Start, segment.End);
            result.Add(segment with { Start = Math.Min(segStart, segment.End), Words = words });
        }
        return result;
    }

    /// <summary>
    /// 長い音声を length 秒ごとに分けるときの、各区切りの先頭（サンプルの位置）。
    /// 語の途中で切らないよう、目安の位置の前 search 秒のうち、いちばん静かな 100 ms のところで切る（Mac 版と同じ）
    /// </summary>
    public static List<int> ChunkStarts(ReadOnlySpan<float> samples, double length, double search = 15)
    {
        var starts = new List<int> { 0 };
        var chunk = (int)(length * AudioFormat.SampleRate);
        var window = AudioFormat.SampleRate / 10;
        var searchSamples = (int)(Math.Min(search, length / 2) * AudioFormat.SampleRate);
        var position = 0;
        while (samples.Length - position > chunk)
        {
            var target = position + chunk;
            var from = Math.Max(position + window, target - searchSamples);
            var best = target;
            var bestRms = double.MaxValue;
            for (var s = from; s + window <= target; s += window / 2)
            {
                var rms = Rms(samples.Slice(s, window));
                if (rms < bestRms)
                {
                    bestRms = rms;
                    best = s + window / 2;
                }
            }
            starts.Add(best);
            position = best;
        }
        return starts;
    }
}

/// <summary>
/// 会議の音声を Gemini に送り、時刻つきの区間（JSON）で文字起こしさせる。Mac 版 GeminiTranscriber の会議用の部分の移植。
/// 長い音声は 5 分ごとに分け（最大 3 つを並行して送る）、区切りの開始時刻を足して全体の時刻にする。
/// </summary>
public sealed class GeminiSegmentTranscriber : ISegmentTranscriber
{
    /// <summary>1 区切りの長さ（秒）。環境変数 HANASU_GEMINI_CHUNK_SECONDS で変えられる（区切りの確認用、Mac 版と同じ）</summary>
    public static double ChunkSeconds =>
        double.TryParse(Environment.GetEnvironmentVariable("HANASU_GEMINI_CHUNK_SECONDS"), NumberStyles.Float, CultureInfo.InvariantCulture, out var s) && s > 10 ? s : 300;

    public const int MaxConcurrentRequests = 3;

    private readonly Func<GeminiClient?> clientFactory;
    private readonly Func<string> model;
    private GeminiClient? client;

    /// <param name="clientFactory">認証情報がなければ null を返す。タイムアウトは長め（300 秒）にしたものを渡す</param>
    public GeminiSegmentTranscriber(Func<GeminiClient?> clientFactory, Func<string> model)
    {
        this.clientFactory = clientFactory;
        this.model = model;
    }

    public string DisplayName => "Gemini";

    public Task PrepareAsync(TranscriptionContext context, CancellationToken cancellationToken = default)
    {
        try
        {
            client = clientFactory();
        }
        catch (ServiceAccountException e)
        {
            throw new TranscriptionException(e.Message, inner: e);
        }
        if (client is null)
        {
            throw new TranscriptionException(Strings.Meeting_GeminiNotConfigured);
        }
        return Task.CompletedTask;
    }

    // 要件: REQ-COM-061
    /// <summary>会議の書き起こしの指示（transcribe.meeting.system。Mac 版 GeminiTranscriber.meetingInstruction と同じキー）</summary>
    public static string Instruction(string localeIdentifier) =>
        Ai.Prompts.Text("transcribe.meeting.system", ("languageNote", LanguageNote(localeIdentifier)));

    // 要件: REQ-COM-061
    /// <summary>応答の形（Mac 版 meetingSchema と同じ。区間の時刻の説明はプロンプトの言語）</summary>
    public static JsonNode Schema()
    {
        JsonNode Time(string key) => new JsonObject { ["type"] = "STRING", ["description"] = Ai.Prompts.Text(key) };
        return new JsonObject
        {
            ["type"] = "OBJECT",
            ["properties"] = new JsonObject
            {
                ["segments"] = new JsonObject
                {
                    ["type"] = "ARRAY",
                    ["items"] = new JsonObject
                    {
                        ["type"] = "OBJECT",
                        ["properties"] = new JsonObject
                        {
                            ["start"] = Time("transcribe.schema.start"),
                            ["end"] = Time("transcribe.schema.end"),
                            ["text"] = new JsonObject { ["type"] = "STRING" },
                        },
                        ["required"] = new JsonArray("start", "end", "text"),
                    },
                },
            },
            ["required"] = new JsonArray("segments"),
        };
    }

    public async Task<IReadOnlyList<TimedSegment>> TranscribeSegmentsAsync(float[] samples, TranscriptionContext context,
        IProgress<string>? progress = null, CancellationToken cancellationToken = default)
    {
        if (samples.Length == 0) return Array.Empty<TimedSegment>();
        if (client is null) await PrepareAsync(context, cancellationToken).ConfigureAwait(false);
        var starts = MeetingAudio.ChunkStarts(samples, ChunkSeconds);
        var ranges = starts.Select((s, i) => (Start: s, End: i + 1 < starts.Count ? starts[i + 1] : samples.Length)).ToList();
        var total = ranges.Count;
        var instruction = Instruction(context.LocaleIdentifier);
        var schema = Schema();
        var language = Ai.PromptLanguage.Current;
        var modelId = model();
        var done = 0;
        progress?.Report($"0/{total}");

        var results = new IReadOnlyList<TimedSegment>[total];
        using var throttle = new SemaphoreSlim(MaxConcurrentRequests);
        var tasks = ranges.Select(async (range, index) =>
        {
            await throttle.WaitAsync(cancellationToken).ConfigureAwait(false);
            try
            {
                var offset = range.Start / (double)AudioFormat.SampleRate;
                var duration = (range.End - range.Start) / (double)AudioFormat.SampleRate;
                // 無音だけの区切りは送らない
                if (MeetingAudio.Rms(samples.AsSpan(range.Start, range.End - range.Start)) < 0.0005)
                {
                    results[index] = Array.Empty<TimedSegment>();
                }
                else
                {
                    var wav = WavFile.Encode(samples.AsSpan(range.Start, range.End - range.Start));
                    // 要件: REQ-COM-061
                    var note = total > 1
                        ? Ai.Prompts.Text("transcribe.meeting.chunkUser", language,
                            ("index", (index + 1).ToString(CultureInfo.InvariantCulture)),
                            ("total", total.ToString(CultureInfo.InvariantCulture)),
                            ("start", string.Create(CultureInfo.InvariantCulture, $"{(int)offset / 60}:{(int)offset % 60:00}")))
                        : Ai.Prompts.Text("transcribe.meeting.user", language);
                    string json;
                    try
                    {
                        json = await client!.GenerateAsync(instruction,
                            [new GeminiPart.InlineData("audio/wav", wav), new GeminiPart.Text(Note(note, context.ContextualStrings, language))],
                            modelId, cancellationToken: cancellationToken, responseSchema: schema).ConfigureAwait(false);
                    }
                    catch (GeminiException e) when (e.Kind == GeminiErrorKind.EmptyResponse && e.Reason is null or "STOP")
                    {
                        json = """{"segments":[]}""";
                    }
                    if (Environment.GetEnvironmentVariable("HANASU_DEBUG") is not null)
                    {
                        Console.Error.WriteLine($"gemini chunk {index + 1}/{total} {offset:0.0}-{offset + duration:0.0}s: {json}");
                    }
                    results[index] = ParseSegments(json, duration)
                        .Select(s => s with { Start = s.Start + offset, End = s.End + offset })
                        .ToList();
                }
                progress?.Report($"{Interlocked.Increment(ref done)}/{total}");
            }
            catch (Ai.TextAiException e)
            {
                throw new TranscriptionException(string.Format(Strings.Transcription_GeminiFailed, e.Message), inner: e);
            }
            finally
            {
                throttle.Release();
            }
        }).ToList();
        await Task.WhenAll(tasks).ConfigureAwait(false);
        return results.SelectMany(r => r).ToList();
    }

    /// <summary>JSON の応答を区間にする。時刻は区切りの長さに収め、終わりが始まりより前にならないようにする</summary>
    public static List<TimedSegment> ParseSegments(string json, double duration)
    {
        JsonElement root;
        try
        {
            root = JsonDocument.Parse(json).RootElement;
        }
        catch (JsonException e)
        {
            throw GeminiException.InvalidResponse(e);
        }
        if (root.ValueKind != JsonValueKind.Object || !root.TryGetProperty("segments", out var segments) || segments.ValueKind != JsonValueKind.Array)
        {
            throw GeminiException.InvalidResponse();
        }
        var result = new List<TimedSegment>();
        var previousEnd = 0.0;
        foreach (var segment in segments.EnumerateArray())
        {
            string? Str(string name) => segment.ValueKind == JsonValueKind.Object && segment.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;
            var text = Str("text")?.Trim() ?? "";
            if (text.Length == 0 || ParseTime(Str("start") ?? "") is not { } rawStart) continue;
            var start = Math.Clamp(rawStart, 0, duration);
            var end = ParseTime(Str("end") ?? "") is { } e ? Math.Clamp(e, start, duration) : start;
            if (end <= start) end = Math.Min(start + 1, duration);
            // 時刻が前後したときは、直前の区間の終わりにそろえる
            if (start < previousEnd - 5)
            {
                start = previousEnd;
                end = Math.Max(end, start);
            }
            previousEnd = end;
            result.Add(new TimedSegment(start, end, text));
        }
        return result;
    }

    /// <summary>"MM:SS.s" / "HH:MM:SS" / "83.4" を秒にする</summary>
    public static double? ParseTime(string value)
    {
        var parts = value.Trim().Split(':');
        double total = 0;
        foreach (var p in parts)
        {
            if (!double.TryParse(p, NumberStyles.Float, CultureInfo.InvariantCulture, out var n)) return null;
            total = total * 60 + n;
        }
        return total;
    }

    // 要件: REQ-COM-061
    /// <summary>添える文に、ユーザー辞書の語を足す（語の区切りはプロンプトの言語の区切り。日本語は「、」）</summary>
    private static string Note(string note, IReadOnlyList<string> hints, Ai.PromptLanguage language)
    {
        var words = hints.Where(h => h.Length > 0).Distinct().ToList();
        return words.Count == 0 ? note : note + "\n" + Ai.Prompts.Text("transcribe.dictionary", language, ("words", string.Join(Ai.Prompts.Text("user.dictionaryRuleSeparator", language), words)));
    }

    // 要件: REQ-COM-061
    /// <summary>
    /// 「音声はおもに〇〇です」の一文（transcribe.languageNote）。言語の名前は、文字起こしの言語を対応言語に寄せたもの（languageName.*）を、
    /// プロンプトの言語で書く。Mac 版は Locale の名前（「日本語（日本）」）を使うが、Windows 版は JSON の名前を使う
    /// </summary>
    internal static string LanguageNote(string localeIdentifier)
    {
        var language = Ai.PromptLanguage.Current;
        var spoken = Ai.PromptLanguage.FromLocaleIdentifier(localeIdentifier);
        var name = Ai.Prompts.Text("languageName." + spoken.Code, language);
        return Ai.Prompts.Text("transcribe.languageNote", language, ("language", name));
    }
}
