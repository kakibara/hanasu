using System.Text;
using Hanasu.Core.Transcription;
using Whisper.net;

namespace Hanasu.Whisper;

/// <summary>
/// Whisper（whisper.cpp を Whisper.net 経由で使う）で、録り終えた音声をまとめて文字起こしする。
/// モデルの読み込みは重いので、一度読んだ WhisperFactory を使い回す（会議の記録からも同じものを使える）。
/// </summary>
public sealed class WhisperBatchTranscriber : IBatchTranscriber
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
        return await TranscribeWithAsync(factory, samples, context, cancellationToken).ConfigureAwait(false);
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
            if (!WhisperText.IsHallucination(segment.Text)) sb.Append(segment.Text.Trim());
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

    public static bool IsHallucination(string segment)
    {
        var s = segment.Trim().Trim('。', '!', '！');
        if (s.Length == 0) return true;
        return Hallucinations.Any(h => string.Equals(h.Trim('。'), s, StringComparison.OrdinalIgnoreCase));
    }
}
