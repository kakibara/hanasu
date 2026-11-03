using System.Text;
using Hanasu.Core.Meetings;
using Hanasu.Core.Transcription;
using Whisper.net;

namespace Hanasu.Whisper;

/// <summary>
/// Whisper（whisper.cpp を Whisper.net 経由で使う）で、録り終えた音声をまとめて文字起こしする。
/// モデルの読み込みは重いので、一度読んだ WhisperFactory を使い回す（会議の記録からも同じものを使える）。
/// 会議の記録では、時刻つきの区間（語の時刻つき）で返す（ISegmentTranscriber）。
/// </summary>
public sealed class WhisperBatchTranscriber : IBatchTranscriber, ISegmentTranscriber
{
    private static readonly SemaphoreSlim LoadLock = new(1, 1);
    private static (string Path, WhisperFactory Factory)? cachedFactory;

    private readonly Func<string> modelPath;
    private readonly Func<string> modelLabel;
    private Task<WhisperFactory>? loading;

    /// <param name="modelPath">使うモデルのファイル</param>
    /// <param name="modelLabel">見つからないときの案内に出すモデル名</param>
    public WhisperBatchTranscriber(Func<string> modelPath, Func<string> modelLabel)
    {
        this.modelPath = modelPath;
        this.modelLabel = modelLabel;
    }

    public string DisplayName => "Whisper";

    public Task PrepareAsync(TranscriptionContext context, CancellationToken cancellationToken = default)
    {
        var path = modelPath();
        if (!File.Exists(path))
        {
            throw new TranscriptionException(
                $"Whisper のモデル（{modelLabel()}）がまだダウンロードされていません。メニュー → 設定 → 一般 でダウンロードしてください。");
        }
        // 読み込みは録音と並行して進める
        loading = Task.Run(() => LoadFactoryAsync(path, cancellationToken), cancellationToken);
        return Task.CompletedTask;
    }

    public async Task<string> TranscribeAsync(float[] samples, TranscriptionContext context, CancellationToken cancellationToken = default)
    {
        var factory = await LoadedFactoryAsync(context, cancellationToken).ConfigureAwait(false);
        return await TranscribeWithAsync(factory, samples, context, cancellationToken).ConfigureAwait(false);
    }

    public async Task<IReadOnlyList<TimedSegment>> TranscribeSegmentsAsync(float[] samples, TranscriptionContext context,
        IProgress<string>? progress = null, CancellationToken cancellationToken = default)
    {
        var factory = await LoadedFactoryAsync(context, cancellationToken).ConfigureAwait(false);
        return await TranscribeSegmentsWithAsync(factory, samples, context, progress, cancellationToken).ConfigureAwait(false);
    }

    private async Task<WhisperFactory> LoadedFactoryAsync(TranscriptionContext context, CancellationToken cancellationToken)
    {
        if (loading is null) await PrepareAsync(context, cancellationToken).ConfigureAwait(false);
        WhisperFactory factory;
        try
        {
            factory = await loading!.ConfigureAwait(false);
        }
        catch (Exception e) when (e is DllNotFoundException or TypeInitializationException or BadImageFormatException)
        {
            // whisper.dll が読めない: Visual C++ ランタイムがない、CPU が AVX2 に対応していない、など
            throw new TranscriptionException(
                "Whisper を動かせませんでした。Microsoft Visual C++ 再頒布可能パッケージ（2015〜2022, x64）を入れてから、もう一度試してください。" +
                $"（{e.GetBaseException().Message}）", inner: e);
        }
        catch (Exception e) when (e is not OperationCanceledException and not TranscriptionException)
        {
            throw new TranscriptionException($"Whisper のモデルを読み込めませんでした: {e.Message}", inner: e);
        }
        return factory;
    }

    /// <summary>
    /// 会議用。区間ごとに時刻と、語（トークン）ごとの時刻を返す。語の時刻は話者の割り当てに使う（1 区間に複数の話者が混ざっても分けられる）。
    /// 日本語のトークンは 1 文字の途中で切れることがあるので、つなげて文字にならないトークンは次とまとめる。
    /// </summary>
    public static async Task<IReadOnlyList<TimedSegment>> TranscribeSegmentsWithAsync(WhisperFactory factory, float[] samples,
        TranscriptionContext context, IProgress<string>? progress = null, CancellationToken cancellationToken = default)
    {
        var language = context.LocaleIdentifier.Split('-', '_')[0].ToLowerInvariant();
        var builder = factory.CreateBuilder()
            .WithLanguage(string.IsNullOrEmpty(language) ? "ja" : language)
            .WithThreads(Math.Clamp(Environment.ProcessorCount - 1, 1, 8))
            .WithTokenTimestamps();
        if (progress is not null) builder = builder.WithProgressHandler(percent => progress.Report($"{percent}%"));
        var prompt = WhisperPrompt(context.ContextualStrings);
        if (prompt.Length > 0) builder = builder.WithPrompt(prompt);

        await using var processor = builder.Build();
        var result = new List<TimedSegment>();
        await foreach (var segment in processor.ProcessAsync(samples, cancellationToken).ConfigureAwait(false))
        {
            var text = segment.Text.Trim();
            if (WhisperText.IsHallucination(text)) continue;
            // トークンの時刻（t0/t1、10 ms 単位）。whisper.cpp の DTW の時刻も試したが、長い音声で途中から文字起こしが止まったので使わない
            var tokens = segment.Tokens.Select(t => (t.Text ?? "", t.Start / 100.0, t.End / 100.0)).ToList();
            var (cleaned, words) = Words(text, tokens, segment.Start.TotalSeconds, segment.End.TotalSeconds);
            if (Environment.GetEnvironmentVariable("HANASU_DEBUG") is not null)
            {
                Console.Error.WriteLine($"whisper segment {segment.Start.TotalSeconds:0.00}-{segment.End.TotalSeconds:0.00} {text}");
                Console.Error.WriteLine("  words: " + string.Join(" | ", words.Select(w => $"{w.Text}@{w.Start:0.00}-{w.End:0.00}")));
            }
            if (cleaned.Length == 0) continue;
            result.Add(new TimedSegment(segment.Start.TotalSeconds, segment.End.TotalSeconds, cleaned, words));
        }
        return result;
    }

    /// <summary>
    /// トークンを、区間の文字に合わせて語にする。日本語のトークンは 1 文字の途中で切れることがあり、Whisper.net はその断片を
    /// U+FFFD（文字化け）にして渡すので、前後の読めるトークンの位置から、その間の文字をまとめて 1 語にする。
    /// 「(字幕)」のような括弧書きの注釈（Whisper が無音や雑音に書きがちなもの）は、文字からも語からも除く。
    /// 合わせられなければ語は空（区間を 1 語として扱う）。
    /// </summary>
    internal static (string Text, List<TimedWord> Words) Words(string text, IReadOnlyList<(string Text, double Start, double End)> tokens,
        double segmentStart, double segmentEnd)
    {
        var annotations = WhisperText.AnnotationRanges(text);
        var cleaned = WhisperText.RemoveAnnotations(text);
        var spans = new List<(int From, int To, double Start, double End)>();
        var cursor = 0;
        double? pendingStart = null;
        double pendingEnd = 0;
        var aligned = true;
        foreach (var (raw, start, end) in tokens)
        {
            if (raw.StartsWith("[_", StringComparison.Ordinal)) continue;  // [_BEG_]・[_TT_123] などの特別なトークン
            if (raw.Contains('\uFFFD'))
            {
                pendingStart ??= start;
                pendingEnd = end;
                continue;
            }
            var token = raw.Trim();
            if (token.Length == 0) continue;
            var index = text.IndexOf(token, cursor, StringComparison.Ordinal);
            if (index < 0)
            {
                aligned = false;
                break;
            }
            if (index > cursor)
            {
                // 間の文字（文字化けしたトークンの分）
                spans.Add((cursor, index, pendingStart ?? start, pendingStart is null ? start : pendingEnd));
            }
            pendingStart = null;
            spans.Add((index, index + token.Length, start, end));
            cursor = index + token.Length;
        }
        if (aligned && cursor < text.Length) spans.Add((cursor, text.Length, pendingStart ?? segmentEnd, pendingStart is null ? segmentEnd : pendingEnd));
        if (!aligned) return (cleaned, new List<TimedWord>());

        var words = new List<TimedWord>();
        foreach (var (from, to, start, end) in spans)
        {
            // 注釈の中の文字は除く
            var chars = Enumerable.Range(from, to - from).Where(i => !annotations.Any(a => a.Start <= i && i < a.End)).Select(i => text[i]).ToArray();
            var word = new string(chars);
            if (word.Trim().Length == 0) continue;
            var s = Math.Clamp(start, segmentStart, segmentEnd);
            var e = Math.Clamp(Math.Max(end, s), s, segmentEnd);
            words.Add(new TimedWord(word, s, e));
        }
        // つないだ文字が区間の文字（注釈を除いたもの）と合わなければ、区間を 1 語として扱う
        if (string.Concat(words.Select(w => w.Text)).Trim() != cleaned) words.Clear();
        return (cleaned, words);
    }

    /// <summary>読み込み済みのモデルで文字起こしする（CLI やテストからも使う）</summary>
    public static async Task<string> TranscribeWithAsync(WhisperFactory factory, float[] samples, TranscriptionContext context,
        CancellationToken cancellationToken = default)
    {
        var language = context.LocaleIdentifier.Split('-', '_')[0].ToLowerInvariant();
        var builder = factory.CreateBuilder()
            .WithLanguage(string.IsNullOrEmpty(language) ? "ja" : language)
            .WithThreads(Math.Clamp(Environment.ProcessorCount - 1, 1, 8));
        // 辞書の語をプロンプトに入れると、固有名詞の表記が辞書に寄る
        var prompt = WhisperPrompt(context.ContextualStrings);
        if (prompt.Length > 0) builder = builder.WithPrompt(prompt);

        await using var processor = builder.Build();
        var sb = new StringBuilder();
        await foreach (var segment in processor.ProcessAsync(samples, cancellationToken).ConfigureAwait(false))
        {
            if (!WhisperText.IsHallucination(segment.Text)) sb.Append(WhisperText.RemoveAnnotations(segment.Text.Trim()));
        }
        return sb.ToString().Trim();
    }

    /// <summary>プロンプトは短くする（長いと Whisper がプロンプトの文をそのまま書くことがある）</summary>
    internal static string WhisperPrompt(IReadOnlyList<string> words)
    {
        var picked = new List<string>();
        var length = 0;
        foreach (var w in words)
        {
            if (length + w.Length > 120) break;
            picked.Add(w);
            length += w.Length + 1;
        }
        return string.Join("、", picked);
    }

    private static async Task<WhisperFactory> LoadFactoryAsync(string path, CancellationToken cancellationToken)
    {
        await LoadLock.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            if (cachedFactory is { } cached && cached.Path == path) return cached.Factory;
            cachedFactory?.Factory.Dispose();
            cachedFactory = null;
            var factory = WhisperFactory.FromPath(path);
            cachedFactory = (path, factory);
            return factory;
        }
        finally
        {
            LoadLock.Release();
        }
    }

    /// <summary>読み込んだモデルを手放す（モデルを削除する前に呼ぶ）</summary>
    public static void ReleaseCachedModel()
    {
        LoadLock.Wait();
        try
        {
            cachedFactory?.Factory.Dispose();
            cachedFactory = null;
        }
        finally
        {
            LoadLock.Release();
        }
    }
}

/// <summary>Whisper の出力の後始末。</summary>
public static class WhisperText
{
    /// <summary>無音や雑音に Whisper が書きがちな決まり文句（YouTube の字幕から覚えたもの）</summary>
    private static readonly string[] Hallucinations =
    [
        "ご視聴ありがとうございました",
        "ご視聴ありがとうございました。",
        "最後までご視聴いただきありがとうございました",
        "チャンネル登録よろしくお願いします",
        "[音楽]",
        "(音楽)",
        "[BLANK_AUDIO]",
    ];

    private static readonly System.Text.RegularExpressions.Regex Annotation = new(@"[\(（\[［][^\)）\]］]{1,10}[\)）\]］]\s*");

    /// <summary>「(字幕)」「（拍手）」「[音楽]」のような括弧書きの注釈の位置</summary>
    public static List<(int Start, int End)> AnnotationRanges(string text) =>
        Annotation.Matches(text).Select(m => (m.Index, m.Index + m.Length)).ToList();

    /// <summary>括弧書きの注釈を除く（Whisper は無音や雑音に注釈を書くことがある。話した言葉ではないので会議の記録には残さない）</summary>
    public static string RemoveAnnotations(string text) => Annotation.Replace(text, "").Trim();

    public static bool IsHallucination(string segment)
    {
        var s = segment.Trim().Trim('。', '!', '！');
        if (s.Length == 0) return true;
        return Hallucinations.Any(h => string.Equals(h.Trim('。'), s, StringComparison.OrdinalIgnoreCase));
    }
}
