using System.Text.Json;
using Hanasu.Core.Ai;
using Hanasu.Core.LocalLlm;
using Hanasu.Core.Meetings;
using Hanasu.Core.Properties;

namespace Hanasu.Core.Text;

/// <summary>AI が挙げた辞書の候補。Readings が空なら語だけを登録する</summary>
public sealed record DictionaryCandidate(string Spelling, IReadOnlyList<string> Readings, string Reason)
{
    public UserDictionary.Entry Entry => new(string.Join(", ", Readings), Spelling);
}

/// <summary>辞書の候補を探せなかった（応答を読めない）</summary>
public sealed class DictionarySuggestionException(string message, Exception? inner = null) : Exception(message, inner);

// 要件: REQ-DIC-072
/// <summary>
/// 会議 1 件の文字起こしと議事録から、会議の AI に辞書の候補を挙げてもらう（Mac 版 DictionarySuggester.swift の会議 1 件の部分の移植）。
/// 会議ノートのボタンを押したときだけ動く。候補は自動では辞書に追加しない（DEC-DIC-087）。
/// </summary>
public static class DictionarySuggester
{
    // 設計判断: DEC-DIC-170
    /// <summary>材料の長さの上限。Gemini・Claude は字数、ローカルは見積もったトークン数</summary>
    public sealed record Budget(bool IsTokens, int Limit)
    {
        public int Cost(string text) => IsTokens ? EstimateTokens(text) : text.Length;
    }

    /// <summary>Gemini・Claude に送る材料の上限（Mac 版の設定の欄の全体の上限と同じ）</summary>
    public const int CharacterLimit = 60_000;

    // 設計判断: DEC-COM-073
    /// <summary>
    /// トークン数の見積もり（Mac 版 AppleFMClient.estimateTokens と同じ）。ASCII の文字は 3 文字で 1 トークン、
    /// それ以外（漢字・かな・ハングル・キリル文字・アラビア文字・デーヴァナーガリー・アクセント付きの文字など）は 1 文字 1 トークン（多めに見積もる）
    /// </summary>
    public static int EstimateTokens(string text)
    {
        int wide = 0, narrow = 0;
        foreach (var rune in text.EnumerateRunes())
        {
            if (rune.IsAscii) narrow++; else wide++;
        }
        return wide + (narrow + 2) / 3;
    }

    // 要件: REQ-COM-061
    public static string Instruction => Prompts.Text("dictionarySuggest.system");

    public static string UserPrompt(string material, UserDictionary existing)
    {
        var words = existing.Spellings.Concat(existing.Rules.SelectMany(r => r.Sources)).ToList();
        var existingText = Prompts.Text("dictionarySuggest.existing",
            ("words", words.Count == 0 ? Prompts.Text("dictionarySuggest.none") : string.Join(", ", words)));
        return $"{existingText}\n\n<material>\n{material}\n</material>";
    }

    // 設計判断: DEC-DIC-170
    /// <summary>
    /// 会議の AI に合わせた上限。ローカルは、文脈の長さから出力・system instruction・既存の辞書・余白の分を引く。
    /// 見積もりは多めなので、LongInputFitter が黙って後ろを省くことはない
    /// </summary>
    public static Budget BudgetFor(ITextGenerator client, UserDictionary existing)
    {
        if (client is not LocalLlmClient local) return new Budget(false, CharacterLimit);
        var frame = EstimateTokens(Instruction + UserPrompt("", existing)) + LongInputFitter.Margin;
        return new Budget(true, Math.Max(0, local.Model.ContextLength - local.Model.MaxOutputTokens(longOutput: true) - frame));
    }

    /// <summary>会議 1 件の材料。CutAt は、文字起こしを途中で切ったときの、読まなかった最初の発言の開始時刻（秒）</summary>
    public sealed record MeetingMaterial(string Text, double? CutAt)
    {
        /// <summary>「最初の約 N 分」の N（切ったときだけ）</summary>
        public int? ReadMinutes => CutAt is { } at ? Math.Max(1, (int)Math.Round(at / 60, MidpointRounding.AwayFromZero)) : null;
    }

    // 要件: REQ-DIC-072, REQ-MTG-045, REQ-MTG-046
    // 設計判断: DEC-DIC-170
    /// <summary>
    /// 会議 1 件の材料。議事録に使う発言（オフレコと除いた発言は入らない）を認識したままの文で先に並べ、
    /// 議事録の本文は残りに入る分だけ入れる（作り直しを促している議事録は入れない）
    /// </summary>
    public static MeetingMaterial MaterialFor(Meeting meeting, Budget budget)
    {
        var language = PromptLanguage.Current;
        var parts = new List<string>
        {
            Prompts.Text("dictionarySuggest.meetingHeader", ("title", meeting.Title)),
            Prompts.Text("dictionarySuggest.transcriptHeader"),
        };
        var used = budget.Cost(string.Join("\n", parts) + "\n");
        double? cutAt = null;
        foreach (var block in meeting.BlocksForMinutes())
        {
            var line = $"[{Meeting.Clock(block.Start)}] {meeting.PromptName(block.Speaker, language)}: {block.RecognizedText}";
            var cost = budget.Cost(line + "\n");
            if (used + cost > budget.Limit)
            {
                cutAt = block.Start;
                break;
            }
            parts.Add(line);
            used += cost;
        }
        // 作り直しを促している議事録は、あとで除いた発言の中身を含みうるので入れない
        if (!string.IsNullOrEmpty(meeting.Minutes) && meeting.MinutesOutdated != true)
        {
            var header = Prompts.Text("dictionarySuggest.minutesHeader");
            var minuteLines = new List<string>();
            var minutesUsed = budget.Cost("\n" + header + "\n");
            foreach (var line in meeting.Minutes.Split('\n'))
            {
                var cost = budget.Cost(line + "\n");
                if (used + minutesUsed + cost > budget.Limit) break;
                minuteLines.Add(line);
                minutesUsed += cost;
            }
            if (minuteLines.Any(l => l.Trim().Length > 0))
            {
                parts.Add("");
                parts.Add(header);
                parts.AddRange(minuteLines);
            }
        }
        return new MeetingMaterial(string.Join("\n", parts), cutAt);
    }

    // 設計判断: DEC-DIC-088, DEC-DIC-170
    /// <summary>材料を送って候補を受け取り、絞り込む。材料の区切りのタグは先に無害にし、絞り込みも無害にした材料で照らし合わせる</summary>
    public static async Task<IReadOnlyList<DictionaryCandidate>> SuggestAsync(string material, UserDictionary existing,
        ITextGenerator client, string model, CancellationToken cancellationToken = default)
    {
        var safe = PromptText.NeutralizeDelimiters(material);
        var text = await client.GenerateTextAsync(TextPurpose.Minutes, Instruction, UserPrompt(safe, existing), model, cancellationToken)
            .ConfigureAwait(false);
        return Filter(Parse(text), existing, safe);
    }

    /// <summary>AI の応答（JSON）を読む。コードブロックで囲まれていても読めるよう、最初の { から最後の } までを使う</summary>
    public static IReadOnlyList<DictionaryCandidate> Parse(string text)
    {
        var start = text.IndexOf('{');
        var end = text.LastIndexOf('}');
        if (start < 0 || end <= start) throw new DictionarySuggestionException(Strings.DictionarySuggest_InvalidResponse);
        try
        {
            using var document = JsonDocument.Parse(text[start..(end + 1)]);
            var list = new List<DictionaryCandidate>();
            foreach (var item in document.RootElement.GetProperty("candidates").EnumerateArray())
            {
                var spelling = item.TryGetProperty("spelling", out var s) && s.ValueKind == JsonValueKind.String ? s.GetString()!.Trim() : "";
                var readings = item.TryGetProperty("readings", out var r) && r.ValueKind == JsonValueKind.Array
                    ? r.EnumerateArray().Where(x => x.ValueKind == JsonValueKind.String).Select(x => x.GetString()!.Trim()).ToList()
                    : new List<string>();
                var reason = item.TryGetProperty("reason", out var why) && why.ValueKind == JsonValueKind.String ? why.GetString()! : "";
                list.Add(new DictionaryCandidate(spelling, readings, reason));
            }
            return list;
        }
        catch (Exception e) when (e is JsonException or KeyNotFoundException or InvalidOperationException)
        {
            throw new DictionarySuggestionException(Strings.DictionarySuggest_InvalidResponse, e);
        }
    }

    // 設計判断: DEC-DIC-089
    /// <summary>辞書にすでにあるもの・置き換えに使えない読み・材料に出てこないもの（AI の思い込み）を除く</summary>
    public static IReadOnlyList<DictionaryCandidate> Filter(IReadOnlyList<DictionaryCandidate> candidates, UserDictionary existing, string material)
    {
        static string Key(string s) => string.Concat(UserDictionary.MatchKey(s));
        var materialKey = Key(material);
        var existingSpellings = existing.Spellings.Select(Key).ToHashSet();
        var usedSources = existing.Rules.SelectMany(r => r.Sources).Select(Key).ToHashSet();
        var seenSpellings = new HashSet<string>();
        var result = new List<DictionaryCandidate>();
        foreach (var candidate in candidates)
        {
            var spellingKey = Key(candidate.Spelling);
            if (spellingKey.Length == 0 || seenSpellings.Contains(spellingKey)) continue;
            var readings = new List<string>();
            foreach (var reading in candidate.Readings)
            {
                var k = Key(reading);
                // 読みが表記と同じ・短すぎる・ほかのルールで使っている、ものは除く。区切り文字も入れない
                if (k == spellingKey || UserDictionary.MatchKey(reading).Length < UserDictionary.MinimumSourceLength
                    || usedSources.Contains(k) || !materialKey.Contains(k, StringComparison.Ordinal)
                    || reading.IndexOfAny(UserDictionary.SourceSeparators) >= 0
                    || UserDictionary.Arrows.Any(a => reading.Contains(a, StringComparison.Ordinal))) continue;
                usedSources.Add(k);
                readings.Add(reading);
            }
            // 表記がすでに辞書にあり、新しい読みもないなら足すものがない
            if (existingSpellings.Contains(spellingKey) && readings.Count == 0) continue;
            // 読みも表記も材料に出てこないものは、AI が作った語なので除く
            if (readings.Count == 0 && !materialKey.Contains(spellingKey, StringComparison.Ordinal)) continue;
            seenSpellings.Add(spellingKey);
            result.Add(candidate with { Readings = readings });
        }
        return result;
    }

    // 設計判断: DEC-DIC-087
    /// <summary>選んだ候補を辞書の末尾に足した文字列を返す</summary>
    public static string Appending(IReadOnlyList<DictionaryCandidate> candidates, string text)
    {
        if (candidates.Count == 0) return text;
        if (text.Length > 0 && !text.EndsWith('\n')) text += "\n";
        return text + string.Join("\n", candidates.Select(c => c.Entry.LineText));
    }
}
