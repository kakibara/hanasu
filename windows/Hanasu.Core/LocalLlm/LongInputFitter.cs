namespace Hanasu.Core.LocalLlm;

/// <summary>
/// 文脈に入らない入力を縮める。トークン数は数える関数（llama-server の /tokenize）で、要点のまとめは summarize で行う。
/// - 入るならそのまま
/// - &lt;transcript&gt; が 1 つだけなら（議事録）、文字起こしを入る大きさの部分に分けて部分ごとの要点にし、中身を置き換える（3 回まで）
/// - それ以外は、入る長さまで後ろを省く
/// Mac 版の LongInputFitter（LocalLLMClient.swift）と同じ考え（両方を直す。文面は共有の JSON の longInput.*）
/// </summary>
// 要件: REQ-COM-030
// 設計判断: DEC-COM-065
public sealed class LongInputFitter(
    int contextLength,
    int maxOutputTokens,
    Func<string, CancellationToken, Task<int>> countTokens,
    Func<string, int, int, CancellationToken, Task<string>> summarize)
{
    /// <summary>チャットのテンプレートで足される分と、数え方のずれの余白</summary>
    public const int Margin = 256;
    public const int MaxRounds = 3;
    // 要件: REQ-COM-061
    /// <summary>省いたときに末尾に付ける一文（longInput.omitted）</summary>
    public static string OmittedNote => "\n" + Ai.Prompts.Text("longInput.omitted");
    /// <summary>部分ごとの要点に置き換えたときに先頭に付ける一文（longInput.summarized）</summary>
    public static string SummarizedNote => Ai.Prompts.Text("longInput.summarized") + "\n";

    // 要件: REQ-COM-061
    /// <summary>部分の要点を作らせる指示（longInput.part。Mac 版 LongInputFitter.partInstruction と同じキー）</summary>
    public static string PartInstruction(int index, int total) =>
        Ai.Prompts.Text("longInput.part", ("index", index.ToString(System.Globalization.CultureInfo.InvariantCulture)),
            ("total", total.ToString(System.Globalization.CultureInfo.InvariantCulture)));

    public static string PartUserText(string part) => $"<transcript_part>\n{part}\n</transcript_part>";

    /// <summary>部分の要点の出力の上限</summary>
    public static int PartOutputTokens(int contextLength) => Math.Min(1024, contextLength / 8);

    public async Task<string> FitAsync(string system, string userText, CancellationToken ct = default)
    {
        var available = contextLength - maxOutputTokens - Margin - await countTokens(system, ct).ConfigureAwait(false);
        if (available <= 0) return "";
        if (await countTokens(userText, ct).ConfigureAwait(false) <= available) return userText;
        // 要件: REQ-MTG-052（縮めて送ると、議事録の根拠の時刻が確かでなくなる）
        Meetings.LongInputReport.Current.Value?.MarkShortened();

        if (SplitTranscript(userText) is { } parts)
        {
            var frame = await countTokens(parts.Prefix + SummarizedNote + parts.Suffix, ct).ConfigureAwait(false);
            var room = available - frame;
            if (room > 0)
            {
                var body = parts.Transcript;
                for (var round = 0; round < MaxRounds; round++)
                {
                    if (await countTokens(body, ct).ConfigureAwait(false) <= room) break;
                    body = await SummarizeInPartsAsync(body, ct).ConfigureAwait(false);
                }
                body = await TruncateAsync(body, room, "", ct).ConfigureAwait(false);
                return parts.Prefix + SummarizedNote + body + parts.Suffix;
            }
        }
        return await TruncateAsync(userText, available, OmittedNote, ct).ConfigureAwait(false);
    }

    /// <summary>&lt;transcript&gt; と &lt;/transcript&gt; が 1 つずつあれば、前・中身・後に分ける</summary>
    public static (string Prefix, string Transcript, string Suffix)? SplitTranscript(string text)
    {
        const string open = "<transcript>", close = "</transcript>";
        var start = text.IndexOf(open, StringComparison.Ordinal);
        var end = text.IndexOf(close, StringComparison.Ordinal);
        if (start < 0 || end < 0 || start + open.Length > end) return null;
        if (text.IndexOf(open, start + 1, StringComparison.Ordinal) >= 0 || text.IndexOf(close, end + 1, StringComparison.Ordinal) >= 0) return null;
        var inner = text[(start + open.Length)..end].Trim('\r', '\n');
        return (text[..(start + open.Length)] + "\n", inner, "\n" + text[end..]);
    }

    private async Task<string> SummarizeInPartsAsync(string body, CancellationToken ct)
    {
        var instruction = await countTokens(PartInstruction(99, 99) + PartUserText(""), ct).ConfigureAwait(false);
        var budget = Math.Max(256, contextLength - PartOutputTokens(contextLength) - Margin - instruction);
        var chunks = await SplitAsync(body, budget, ct).ConfigureAwait(false);
        var notes = new List<string>();
        for (var i = 0; i < chunks.Count; i++)
        {
            ct.ThrowIfCancellationRequested();
            notes.Add(await summarize(chunks[i], i + 1, chunks.Count, ct).ConfigureAwait(false));
        }
        return string.Join("\n", notes);
    }

    /// <summary>行の切れ目で、maxTokens に入る部分に分ける。文字数とトークン数の比で見積もり、入らなかった部分は半分に分ける</summary>
    public async Task<List<string>> SplitAsync(string text, int maxTokens, CancellationToken ct = default)
    {
        var total = Math.Max(1, await countTokens(text, ct).ConfigureAwait(false));
        var charsPerToken = (double)text.Length / total;
        var targetChars = Math.Max(1, (int)(maxTokens * charsPerToken * 0.9));
        var chunks = new List<string>();
        var current = new List<string>();
        var currentChars = 0;
        foreach (var line in text.Split('\n'))
        {
            if (currentChars + line.Length > targetChars && current.Count > 0)
            {
                chunks.Add(string.Join("\n", current));
                current.Clear();
                currentChars = 0;
            }
            current.Add(line);
            currentChars += line.Length + 1;
        }
        if (current.Count > 0) chunks.Add(string.Join("\n", current));

        var result = new List<string>();
        foreach (var chunk in chunks) result.AddRange(await EnsureFitsAsync(chunk, maxTokens, 0, ct).ConfigureAwait(false));
        return result;
    }

    private async Task<List<string>> EnsureFitsAsync(string chunk, int maxTokens, int depth, CancellationToken ct)
    {
        if (depth >= 6 || await countTokens(chunk, ct).ConfigureAwait(false) <= maxTokens) return [chunk];
        // 1 行が長すぎるときは、文字の位置で半分にする（サロゲートペアの途中では切らない）
        var lines = chunk.Split('\n');
        string first, second;
        if (lines.Length >= 2)
        {
            var middle = lines.Length / 2;
            first = string.Join("\n", lines[..middle]);
            second = string.Join("\n", lines[middle..]);
        }
        else
        {
            var middle = chunk.Length / 2;
            if (middle > 0 && char.IsLowSurrogate(chunk[middle])) middle--;
            first = chunk[..middle];
            second = chunk[middle..];
        }
        var result = await EnsureFitsAsync(first, maxTokens, depth + 1, ct).ConfigureAwait(false);
        result.AddRange(await EnsureFitsAsync(second, maxTokens, depth + 1, ct).ConfigureAwait(false));
        return result;
    }

    /// <summary>入る長さまで後ろを省く</summary>
    public async Task<string> TruncateAsync(string text, int maxTokens, string note, CancellationToken ct = default)
    {
        var tokens = await countTokens(text, ct).ConfigureAwait(false);
        if (tokens <= maxTokens) return text;
        var noteTokens = note.Length == 0 ? 0 : await countTokens(note, ct).ConfigureAwait(false);
        var limit = Math.Max(1, maxTokens - noteTokens);
        var keep = text.Length;
        for (var i = 0; i < 8; i++)
        {
            keep = Math.Max(1, (int)((double)keep * limit / Math.Max(tokens, 1) * 0.95));
            if (keep < text.Length && char.IsLowSurrogate(text[keep])) keep--;
            var candidate = text[..keep];
            tokens = await countTokens(candidate, ct).ConfigureAwait(false);
            if (tokens <= limit) return candidate + note;
        }
        return text[..(keep / 2)] + note;
    }
}
