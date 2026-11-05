using System.Text.Json;
using System.Text.RegularExpressions;

namespace Hanasu.Core.Meetings;

/// <summary>
/// 議事録の応答の &lt;speaker_names&gt; から、会話で分かった話者の名前を読み、名前のない話者に付ける。
/// 名前を付けた話者は Meeting.InferredSpeakers に入れ、議事録の本文とアクションアイテムの担当の「話者1」なども名前に置き換える。
/// Mac 版の SpeakerNameInference（Sources/Hanasu/SpeakerNameInference.swift）と同じ決まり（両方を直す）。ラベルの文面は共有の JSON の speaker.*。
/// </summary>
// 要件: REQ-MTG-027
// 設計判断: DEC-MTG-068, DEC-MTG-069
public static partial class SpeakerNameInference
{
    public const string OpenTag = "<speaker_names>";
    public const string CloseTag = "</speaker_names>";
    public const int MaxLength = 20;

    /// <summary>名前の末尾から外す敬称（長いものから見る）</summary>
    public static readonly IReadOnlyList<string> Honorifics = ["ちゃん", "さん", "さま", "くん", "様", "君", "氏"];  // skip-tr（言語の決まりに使う語。FUT-014）

    private static readonly HashSet<string> NotNames = new(StringComparer.OrdinalIgnoreCase) { "自分", "相手", "不明", "なし", "null", "unknown" };  // skip-tr（言語の決まりに使う語。FUT-014）

    [GeneratedRegex(@"^(話者|同席者)[0-9０-９]+$")]  // skip-tr（言語の決まりに使う語。FUT-014）
    private static partial Regex LabelPattern();

    /// <summary>応答から &lt;speaker_names&gt; を取り出して本文から消す。表示ラベル（「話者1」など）→ 名前。読めなければ空</summary>
    public static (string Body, Dictionary<string, string> Names) Extract(string response)
    {
        var names = new Dictionary<string, string>();
        var open = response.LastIndexOf(OpenTag, StringComparison.Ordinal);
        if (open < 0) return (response, names);
        var restStart = open + OpenTag.Length;
        var close = response.IndexOf(CloseTag, restStart, StringComparison.Ordinal);
        var json = (close >= 0 ? response[restStart..close] : response[restStart..]).Replace("```json", "").Replace("```", "");
        var body = response[..open] + (close >= 0 ? response[(close + CloseTag.Length)..] : "");
        // <speaker_names> をコードブロックで囲んで返したときの残り
        body = body.Trim();
        while (new[] { "```xml", "```json", "```" }.FirstOrDefault(f => body.EndsWith(f, StringComparison.Ordinal)) is { } fence)
        {
            body = body[..^fence.Length].Trim();
        }
        try
        {
            var root = JsonDocument.Parse(json.Trim()).RootElement;
            if (root.ValueKind == JsonValueKind.Object)
            {
                foreach (var p in root.EnumerateObject())
                {
                    if (p.Value.ValueKind == JsonValueKind.String) names[p.Name.Trim()] = p.Value.GetString()!;
                }
            }
        }
        catch (JsonException)
        {
            // 読めなければ名前は付けない（議事録はそのまま使う）
        }
        return (body, names);
    }

    /// <summary>名前として使える形にする。使えなければ null（空・長すぎる・改行や制御文字・「話者1」などのラベルそのもの）</summary>
    public static string? CleanName(string raw)
    {
        var name = raw.Trim();
        if (Honorifics.FirstOrDefault(h => name.EndsWith(h, StringComparison.Ordinal) && name.Length > h.Length) is { } honorific)
        {
            name = name[..^honorific.Length].Trim();
        }
        if (name.Length == 0 || new System.Globalization.StringInfo(name).LengthInTextElements > MaxLength) return null;
        if (name.Any(char.IsControl) || IsPlaceholder(name)) return null;
        return name;
    }

    // 要件: REQ-COM-061
    /// <summary>
    /// 名前ではない値（「自分」「相手」「話者1」「同席者1」と、分からないことを表す言葉）。
    /// ラベルはプロンプトの言語で書くので、すべての言語のラベル（speaker.*）と「なし」（minutes.result.none）も名前ではないものとして扱う（Mac 版と同じ）
    /// </summary>
    public static bool IsPlaceholder(string name)
    {
        if (NotNames.Contains(name) || LabelPattern().IsMatch(name)) return true;
        if (Ai.Prompts.AllTexts("speaker.me").Concat(Ai.Prompts.AllTexts("speaker.others")).Concat(Ai.Prompts.AllTexts("minutes.result.none"))
            .Any(t => string.Equals(t, name, StringComparison.OrdinalIgnoreCase)))
        {
            return true;
        }
        return Ai.Prompts.AllTexts("speaker.remote").Concat(Ai.Prompts.AllTexts("speaker.room")).Any(template =>
        {
            var pattern = "^" + Regex.Escape(template).Replace(Regex.Escape("${n}"), "[0-9０-９]+", StringComparison.Ordinal) + "$";
            return Regex.IsMatch(name, pattern, RegexOptions.IgnoreCase);
        });
    }

    /// <summary>
    /// 名前のない話者（「自分」を除く）に、応答の名前を付ける。付けた話者キー → 名前を返す。
    /// 議事録の本文とアクションアイテムの担当の中のラベルも、付けた名前に置き換えた結果を返す
    /// </summary>
    public static (MinutesResult Minutes, Dictionary<string, string> Applied) Apply(IReadOnlyDictionary<string, string> names, Meeting meeting, MinutesResult minutes)
    {
        var applied = new Dictionary<string, string>();
        if (names.Count == 0) return (minutes, applied);
        var labelToKey = new Dictionary<string, string>();
        foreach (var key in meeting.Speakers)
        {
            // 要件: REQ-COM-061（応答のラベルは、プロンプトに書いたラベルと同じ言語）
            if (key != "me" && meeting.SpeakerNames.GetValueOrDefault(key, "").Length == 0) labelToKey[meeting.PromptName(key)] = key;
        }
        var matches = new List<(string Key, string Label, string Name)>();
        foreach (var label in names.Keys.Order(StringComparer.Ordinal))
        {
            if (labelToKey.TryGetValue(label, out var key) && CleanName(names[label]) is { } name) matches.Add((key, label, name));
        }
        if (matches.Count == 0) return (minutes, applied);

        var markdown = minutes.Markdown;
        var items = minutes.ActionItems;
        var inferred = meeting.InferredSpeakers ?? new List<string>();
        foreach (var (key, label, name) in matches)
        {
            meeting.SpeakerNames[key] = name;
            if (!inferred.Contains(key)) inferred.Add(key);
            applied[key] = name;
            // 「相手」はふつうの言葉でもあるので、本文は置き換えない（担当がちょうど「相手」のときだけ）
            if (key != "others") markdown = ReplaceLabel(label, name, markdown);
            foreach (var item in items)
            {
                if (item.Owner is not { } owner) continue;
                item.Owner = owner == label ? name : key == "others" ? owner : ReplaceLabel(label, name, owner);
            }
        }
        meeting.InferredSpeakers = inferred;
        return (minutes with { Markdown = markdown }, applied);
    }

    /// <summary>「話者1」を名前に置き換える。「話者10」の「話者1」は置き換えない（後ろに数字が続くときは別の話者）</summary>
    public static string ReplaceLabel(string label, string name, string text) =>
        Regex.Replace(text, Regex.Escape(label) + "(?![0-9０-９])", name.Replace("$", "$$"));
}
