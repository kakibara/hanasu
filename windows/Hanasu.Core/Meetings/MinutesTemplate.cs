using System.Text.Json;
using Hanasu.Core.Ai;

namespace Hanasu.Core.Meetings;

// 議事録の型（テンプレート）とプロンプト。Mac 版 MinutesTemplate.swift と MeetingNotes.swift の移植。
// ★ プロンプトの文面は、Mac 版と共有の言語ごとの JSON（Sources/Hanasu/Resources/Prompts/<言語>.json の minutes.*）から読む。
//   組み立て方（どのキーをどの順に並べるか）は Mac 版と同じにする（両方を直す）。

/// <summary>議事録の型。型ごとに、Gemini に渡す見出しの構成と書き方の指示を持つ</summary>
public enum MinutesTemplate
{
    /// <summary>会議の種類を決めずにまとめる（従来の議事録）</summary>
    Auto,
    /// <summary>定例・進捗確認</summary>
    Regular,
    OneOnOne,
    /// <summary>顧客との打ち合わせ</summary>
    Sales,
    Brainstorm,
    /// <summary>ユーザーが書いた指示に従う</summary>
    Custom,
}

public static class MinutesTemplates
{
    public static readonly IReadOnlyList<MinutesTemplate> All =
        [MinutesTemplate.Auto, MinutesTemplate.Regular, MinutesTemplate.OneOnOne, MinutesTemplate.Sales, MinutesTemplate.Brainstorm, MinutesTemplate.Custom];

    /// <summary>meeting.json に書く値（Mac 版の rawValue と同じ）</summary>
    public static string RawValue(this MinutesTemplate t) => t switch
    {
        MinutesTemplate.Regular => "regular",
        MinutesTemplate.OneOnOne => "oneOnOne",
        MinutesTemplate.Sales => "sales",
        MinutesTemplate.Brainstorm => "brainstorm",
        MinutesTemplate.Custom => "custom",
        _ => "auto",
    };

    public static MinutesTemplate? FromRawValue(string? raw) => All.Cast<MinutesTemplate?>().FirstOrDefault(t => t!.Value.RawValue() == raw);

    public static string Title(this MinutesTemplate t) => t switch
    {
        MinutesTemplate.Regular => "定例",
        MinutesTemplate.OneOnOne => "1on1",
        MinutesTemplate.Sales => "商談",
        MinutesTemplate.Brainstorm => "ブレスト",
        MinutesTemplate.Custom => "カスタム",
        _ => "自動",
    };

    /// <summary>選ぶときに出す短い説明</summary>
    public static string Summary(this MinutesTemplate t) => t switch
    {
        MinutesTemplate.Regular => "進捗・報告・課題・決定事項・アクションアイテム",
        MinutesTemplate.OneOnOne => "近況・相談・フィードバック・合意・アクションアイテム",
        MinutesTemplate.Sales => "顧客の課題・提案内容・反応・懸念・次のアクション",
        MinutesTemplate.Brainstorm => "出たアイデア・有望な案・論点・次のステップ",
        MinutesTemplate.Custom => "自分で書いた指示に従う",
        _ => "概要・話し合った内容・決定事項・アクションアイテム",
    };

    // 要件: REQ-COM-061
    /// <summary>アクションアイテムの見出し（Markdown の「## 」のあと。プロンプトの言語で書く）</summary>
    public static string ActionHeading(this MinutesTemplate t, PromptLanguage? language = null) => t switch
    {
        MinutesTemplate.Sales => Prompts.Text("minutes.actionHeading.sales", language),
        MinutesTemplate.Brainstorm => Prompts.Text("minutes.actionHeading.brainstorm", language),
        _ => Prompts.Text("minutes.actionHeading", language),
    };

    // 要件: REQ-COM-061
    /// <summary>会議の種類についての説明（どこに注目してまとめるか）。minutes.guidance.&lt;型&gt;</summary>
    internal static string Guidance(this MinutesTemplate t, PromptLanguage? language = null) => t switch
    {
        MinutesTemplate.Auto or MinutesTemplate.Custom => "",
        _ => Prompts.Text("minutes.guidance." + t.RawValue(), language),
    };

    // 要件: REQ-COM-061
    /// <summary>議事録の本文の見出しの構成（アクションアイテムと話者のメモは共通なので含めない）。minutes.sections.&lt;型&gt;（カスタムは自動と同じ）</summary>
    internal static string Sections(this MinutesTemplate t, PromptLanguage? language = null) =>
        Prompts.Text("minutes.sections." + (t == MinutesTemplate.Custom ? MinutesTemplate.Auto : t).RawValue(), language);

    // 要件: REQ-COM-061
    /// <summary>「カスタム」の初期の指示（minutes.customDefault。Mac 版 MinutesTemplateStore.defaultCustomPrompt と同じキー）</summary>
    public static string DefaultCustomPrompt => Prompts.Text("minutes.customDefault");
}

/// <summary>議事録の作成結果</summary>
public sealed record MinutesResult(string Markdown, List<ActionItem> ActionItems)
{
    /// <summary>応答の &lt;speaker_names&gt; で分かった話者の名前（表示ラベル「話者1」など → 名前）。当てはめは SpeakerNameInference</summary>
    public Dictionary<string, string> SpeakerNames { get; init; } = new();
    // 要件: REQ-COM-061
    /// <summary>議事録を作ったときのプロンプトの言語（応答の中のラベル「Speaker 1」などを、この言語で読む）</summary>
    public PromptLanguage Language { get; init; } = PromptLanguage.Current;
}

/// <summary>議事録のプロンプトの組み立てと、応答の読み取り。Mac 版 MinutesPrompt と同じ組み立てで、文面は共有の JSON から読む（組み立てを変えるときは両方を直す）</summary>
public static class MinutesPrompt
{
    /// <summary>アクションアイテムの見出しの下に Gemini が置く目印。アプリが一覧に置き換える</summary>
    public const string Placeholder = "{{ACTION_ITEMS}}";

    // 要件: REQ-COM-061
    /// <summary>議事録の指示。Mac 版 MinutesPrompt.systemInstruction と同じ組み立て（minutes.intro・guidance・format か custom・actionItems・speakerNames）</summary>
    public static string SystemInstruction(MinutesTemplate template, string? customPrompt)
    {
        var language = PromptLanguage.Current;
        var parts = new List<string> { Prompts.Text("minutes.intro", language) };
        var guidance = template.Guidance(language);
        if (guidance.Length > 0) parts.Add(guidance);

        var actionHeading = template.ActionHeading(language);
        var common = Prompts.Text("minutes.common", language,
            ("actionHeading", actionHeading),
            ("placeholder", Placeholder),
            ("speakerNotesHeading", Prompts.Text("minutes.speakerNotesHeading", language)));
        var custom = customPrompt?.Trim() ?? "";
        if (template == MinutesTemplate.Custom && custom.Length > 0)
        {
            parts.Add(Prompts.Text("minutes.custom", language, ("custom", custom), ("common", common)));
        }
        else
        {
            parts.Add(Prompts.Text("minutes.format", language, ("sections", template.Sections(language)), ("common", common)));
        }
        parts.Add(Prompts.Text("minutes.actionItems", language, ("actionHeading", actionHeading), ("placeholder", Placeholder)));
        parts.Add(SpeakerNamesInstruction);
        return string.Join("\n\n", parts);
    }

    // 要件: REQ-MTG-027, REQ-COM-061
    // 設計判断: DEC-MTG-068
    /// <summary>話者の名前を &lt;speaker_names&gt; で出させる指示（minutes.speakerNames。Mac 版 MinutesPrompt.speakerNamesInstruction と同じキー）</summary>
    public static string SpeakerNamesInstruction => Prompts.Text("minutes.speakerNames");

    // 要件: REQ-COM-061
    /// <summary>メモか印がある会議だけ、議事録の指示に足す（minutes.notes。Mac 版 MeetingProcessor.notesInstruction と同じキー）</summary>
    public static string NotesInstruction => Prompts.Text("minutes.notes");

    /// <summary>議事録の指示（型の指示に、メモがあればメモの扱いを足したもの）</summary>
    public static string FullInstruction(Meeting meeting)
    {
        var instruction = SystemInstruction(meeting.Template, meeting.CustomMinutesPrompt);
        if (meeting.NotesForPrompt() is not null) instruction += "\n" + NotesInstruction;
        return instruction;
    }

    public static string UserText(Meeting meeting)
    {
        // メモか印があれば <user_notes> を足し、印の前後の発言に ★ を付ける
        // 文字起こしとメモの中の区切りのタグは無害にしてから埋め込む（プロンプトインジェクションの対策。Windows 版で足した）
        var userNotes = meeting.NotesForPrompt() is { } n ? Ai.PromptText.NeutralizeDelimiters(n) : null;
        var transcript = Ai.PromptText.NeutralizeDelimiters(
            userNotes is null ? meeting.TranscriptForPrompt() : meeting.TranscriptForPromptMarkingHighlights());
        var notesBlock = userNotes is null ? "" : $"\n<user_notes>\n{userNotes}\n</user_notes>\n";
        // 要件: REQ-COM-061（会議名と日時の行はプロンプトの言語。日時の曜日もその言語で書く）
        var language = PromptLanguage.Current;
        var meetingLine = Prompts.Text("minutes.user.meeting", language, ("title", meeting.Title));
        var dateLine = Prompts.Text("minutes.user.date", language,
            ("date", Meeting.FormatDate(meeting.StartedAt, language)), ("duration", Meeting.Clock(meeting.Duration)));
        return $"""
            {meetingLine}
            {dateLine}
            {notesBlock}
            <transcript>
            {transcript}
            </transcript>
            """;
    }

    /// <summary>AI（Gemini・Claude）の応答を、議事録の Markdown と構造化したアクションアイテムに分ける</summary>
    public static MinutesResult Parse(string response, string title, PromptLanguage? language = null)
    {
        var lang = language ?? PromptLanguage.Current;
        // 話者の名前（<speaker_names>）を先に取り出す。<action_items> は後ろから探すので、残っていると本文に混ざる
        var (body, speakerNames) = SpeakerNameInference.Extract(response);
        List<ActionItem>? items = null;
        var open = body.LastIndexOf("<action_items>", StringComparison.Ordinal);
        if (open >= 0)
        {
            var restStart = open + "<action_items>".Length;
            var close = body.IndexOf("</action_items>", restStart, StringComparison.Ordinal);
            var json = close >= 0 ? body[restStart..close] : body[restStart..];
            json = json.Replace("```json", "").Replace("```", "");
            items = DecodeItems(json);
            body = body[..open] + (close >= 0 ? body[(close + "</action_items>".Length)..] : "");
            // <action_items> をコードブロックで囲んで返したときの残り
            body = body.Trim();
            while (new[] { "```xml", "```json", "```" }.FirstOrDefault(f => body.EndsWith(f, StringComparison.Ordinal)) is { } fence)
            {
                body = body[..^fence.Length].Trim();
            }
        }
        body = body.Trim();
        // 小さいモデル（ローカル）は <action_items> を使わず、本文の中に JSON の配列をそのまま書くことがある。
        // 読めれば、その場所を一覧に置き換える（Mac 版と同じ。両方を直す）
        if (items is null && InlineItems(body) is { } inline)
        {
            items = inline.Items;
            var list = inline.Items.Count == 0 ? Prompts.Text("minutes.result.none", lang) : string.Join("\n", inline.Items.Select(i => i.MarkdownLineIn(lang)));
            body = body[..inline.Start] + list + body[inline.End..];
        }

        var resolved = items ?? ActionItem.ParseFromMarkdown(body);
        if (body.Contains(Placeholder, StringComparison.Ordinal))
        {
            var list = items is null
                ? Prompts.Text("minutes.result.unreadable", lang)
                : (resolved.Count == 0 ? Prompts.Text("minutes.result.none", lang) : string.Join("\n", resolved.Select(i => i.MarkdownLineIn(lang))));
            body = body.Replace(Placeholder, list, StringComparison.Ordinal);
        }
        // 要件: REQ-COM-061（議事録のタイトルと「なし」などは、プロンプトの言語で書く）
        return new MinutesResult($"# {Prompts.Text("minutes.result.title", lang, ("title", title))}\n\n{body}\n", resolved) { SpeakerNames = speakerNames, Language = lang };
    }

    /// <summary>本文の中の、アクションアイテムの JSON の配列（[{ から }] まで）。読めなければ null</summary>
    internal static (int Start, int End, List<ActionItem> Items)? InlineItems(string body)
    {
        var start = body.IndexOf("[{", StringComparison.Ordinal);
        var end = body.LastIndexOf("}]", StringComparison.Ordinal);
        if (start < 0 || end < start) return null;
        end += 2;
        return DecodeItems(body[start..end]) is { } items ? (start, end, items) : null;
    }

    internal static List<ActionItem>? DecodeItems(string json)
    {
        JsonElement root;
        try
        {
            root = JsonDocument.Parse(json.Trim()).RootElement;
        }
        catch (JsonException)
        {
            return null;
        }
        if (root.ValueKind != JsonValueKind.Array) return null;
        static string? Clean(JsonElement e, string name)
        {
            if (!e.TryGetProperty(name, out var v) || v.ValueKind != JsonValueKind.String) return null;
            var t = v.GetString()!.Trim();
            return t.Length == 0 || t == "null" ? null : t;
        }
        var result = new List<ActionItem>();
        foreach (var r in root.EnumerateArray())
        {
            if (r.ValueKind != JsonValueKind.Object || Clean(r, "task") is not { } task) continue;
            // 日付として読めないものは「言い方」の方に回す
            var due = Clean(r, "due");
            var note = Clean(r, "due_note");
            var item = new ActionItem { Owner = Clean(r, "owner"), Task = task, Due = due, DueNote = note };
            if (due is not null && item.DueDate is null)
            {
                item.DueNote ??= due;
                item.Due = null;
            }
            result.Add(item);
        }
        return result;
    }
}
