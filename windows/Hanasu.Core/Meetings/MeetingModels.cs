using System.Globalization;
using System.Text.Json.Serialization;

namespace Hanasu.Core.Meetings;

// 会議の記録のデータ。Mac 版の MeetingModels.swift / MeetingNotes.swift / MinutesTemplate.swift（ActionItem）の移植。
// meeting.json は Mac 版と同じ形にして、Mac で作った会議をそのまま読めるようにする（MeetingJson）。
// 形（キーの名前・値の書き方）を変えるときは、Mac 版の Swift の型も両方を直す。

/// <summary>録音のチャンネル。マイクが「自分」、システム音声（WASAPI ループバック）が「相手」</summary>
public enum MeetingChannel
{
    Me,
    Others,
}

/// <summary>時刻つきの語。時刻は録音開始を 0 秒とした秒数</summary>
public sealed record TimedWord(string Text, double Start, double End);

/// <summary>文字起こしの 1 区間（だいたい一区切りの発話）。時刻は録音開始を 0 秒とした秒数</summary>
public sealed record TranscribedPhrase(MeetingChannel Channel, double Start, double End, string Text, IReadOnlyList<TimedWord> Words);

/// <summary>話者が決まった発言</summary>
public sealed class Utterance
{
    /// <summary>Swift の UUID と同じ大文字の形</summary>
    public string Id { get; set; } = MeetingIds.New();
    /// <summary>話者キー: "me" / "others" / "spk1", "spk2", ... / "room1", ...</summary>
    public string Speaker { get; set; } = "";
    public double Start { get; set; }
    public double End { get; set; }
    public string Text { get; set; } = "";

    public Utterance() { }

    public Utterance(string speaker, double start, double end, string text)
    {
        Speaker = speaker;
        Start = start;
        End = end;
        Text = text;
    }

    public Utterance Copy() => (Utterance)MemberwiseClone();
}

// JSON では小文字（"recording" など）。MeetingJson の設定で camelCase にする
public enum MeetingStatus
{
    Recording,
    Processing,
    Done,
    Failed,
}

// JSON では "note" / "highlight"
public enum MeetingNoteKind
{
    /// <summary>ユーザーが書いたメモ</summary>
    Note,
    /// <summary>「ここ重要」の印（text は空でもよい）</summary>
    Highlight,
}

/// <summary>記録中（または記録後）にユーザーが書いたメモ 1 行、または「ここ重要」の印 1 つ</summary>
public sealed class MeetingNote
{
    public string Id { get; set; } = MeetingIds.New();
    public MeetingNoteKind Kind { get; set; }
    /// <summary>録音開始からの秒数。記録後に時刻なしで書き足したメモは null</summary>
    public double? Time { get; set; }
    public string Text { get; set; } = "";

    public MeetingNote() { }

    public MeetingNote(MeetingNoteKind kind, double? time, string text)
    {
        Kind = kind;
        Time = time;
        Text = text;
    }

    // テキスト形式（会議ノートの「メモ」タブ・notes.md・CLI の --notes）。1 行が 1 件:
    //   [12:34] メモの本文
    //   [12:40] ★ 印に付けた説明（説明なしなら「[12:40] ★」だけ）
    //   時刻のないメモ

    [JsonIgnore]
    public string Line
    {
        get
        {
            var parts = new List<string>();
            if (Time is { } t) parts.Add($"[{Meeting.Clock(t)}]");
            if (Kind == MeetingNoteKind.Highlight) parts.Add("★");
            if (Text.Length > 0) parts.Add(Text);
            return string.Join(" ", parts);
        }
    }

    public static string ToText(IEnumerable<MeetingNote> notes) => string.Join("\n", notes.Select(n => n.Line));

    /// <summary>テキストを読み取る。空行は無視する</summary>
    public static List<MeetingNote> Parse(string text)
    {
        var result = new List<MeetingNote>();
        foreach (var raw in text.ReplaceLineEndings("\n").Split('\n'))
        {
            var rest = raw.Trim(' ', '\t');
            if (rest.Length == 0) continue;
            double? time = null;
            if (rest.StartsWith('[') && rest.IndexOf(']') is var close and > 0 && ParseClock(rest[1..close]) is { } seconds)
            {
                time = seconds;
                rest = rest[(close + 1)..].TrimStart(' ', '　');
            }
            var kind = MeetingNoteKind.Note;
            if (rest.StartsWith('★') || rest.StartsWith('☆'))
            {
                kind = MeetingNoteKind.Highlight;
                rest = rest[1..].TrimStart(' ', '　');
            }
            var body = rest.Trim(' ', '\t');
            if (kind == MeetingNoteKind.Note && body.Length == 0) continue;
            result.Add(new MeetingNote(kind, time, body));
        }
        return result;
    }

    /// <summary>"mm:ss" か "h:mm:ss" を秒にする</summary>
    public static double? ParseClock(string s)
    {
        var parts = s.Split(':');
        if (parts.Length is < 2 or > 3) return null;
        var total = 0;
        foreach (var p in parts)
        {
            if (!int.TryParse(p.Trim(), NumberStyles.None, CultureInfo.InvariantCulture, out var n) || n < 0) return null;
            total = total * 60 + n;
        }
        return total;
    }
}

/// <summary>議事録から取り出したアクションアイテム（担当・内容・期限）</summary>
public sealed class ActionItem
{
    public string Id { get; set; } = MeetingIds.New();
    /// <summary>担当者（文字起こしの話者名）。分からなければ null</summary>
    public string? Owner { get; set; }
    /// <summary>やること</summary>
    public string Task { get; set; } = "";
    /// <summary>期限の日付（yyyy-MM-dd）。日付に直せなかったときは null</summary>
    public string? Due { get; set; }
    /// <summary>期限について話された言い方（「来週中」など）</summary>
    public string? DueNote { get; set; }
    /// <summary>Mac 版でリマインダーに登録したときの識別子（Windows 版では使わないが、読み書きで落とさない）</summary>
    [JsonPropertyName("reminderID")]
    public string? ReminderId { get; set; }

    [JsonIgnore]
    public DateTime? DueDate =>
        Due is not null && DateTime.TryParseExact(Due, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var d) ? d : null;

    /// <summary>表示用の期限（日付が決まっていれば「11/14 (金)」、なければ話された言い方）</summary>
    [JsonIgnore]
    public string? DueDisplay
    {
        get
        {
            if (DueDate is { } d) return $"{d.Month}/{d.Day} ({Meeting.JapaneseWeekday(d)})";
            return string.IsNullOrEmpty(DueNote) ? null : DueNote;
        }
    }

    /// <summary>議事録に書く 1 行（<c>- [ ] 内容（担当: 〇〇 / 期限: 11/14 (金)）</c>）</summary>
    [JsonIgnore]
    public string MarkdownLine
    {
        get
        {
            var notes = new List<string>();
            if (!string.IsNullOrEmpty(Owner)) notes.Add($"担当: {Owner}");
            if (DueDisplay is { } due) notes.Add($"期限: {due}");
            return $"- [ ] {Task}" + (notes.Count == 0 ? "" : $"（{string.Join(" / ", notes)}）");
        }
    }

    /// <summary>
    /// Markdown の議事録のチェックボックスの行から取り出す（JSON が壊れていたとき・古い議事録用）。
    /// 「TODO」「アクション」「次のステップ」を含む見出しの下の <c>- [ ] 内容（担当: 〇〇 / 期限: △△）</c> を読む。
    /// Mac 版 ActionItem.parse(fromMarkdown:) と同じ（両方を直す）
    /// </summary>
    public static List<ActionItem> ParseFromMarkdown(string markdown)
    {
        var items = new List<ActionItem>();
        var inSection = false;
        foreach (var raw in markdown.Split('\n'))
        {
            var line = raw.Trim(' ', '\t', '\r');
            if (line.StartsWith("## ", StringComparison.Ordinal))
            {
                var heading = line[3..];
                inSection = new[] { "TODO", "ToDo", "アクション", "次のステップ" }.Any(heading.Contains);
                continue;
            }
            if (!inSection || !(line.StartsWith("- [ ] ", StringComparison.Ordinal) || line.StartsWith("- [x] ", StringComparison.Ordinal))) continue;
            var task = line[6..].Trim();
            string? owner = null, dueNote = null;
            if (task.Length > 0 && task[^1] is '）' or ')' && task.LastIndexOfAny(['（', '(']) is var open and >= 0)
            {
                var inner = task[(open + 1)..^1];
                var recognized = false;
                foreach (var part in inner.Split('/', '／'))
                {
                    var pair = part.Split([':', '：'], 2);
                    if (pair.Length != 2) continue;
                    var key = pair[0].Trim();
                    var value = pair[1].Trim();
                    var unknown = value.Length == 0 || value is "不明" or "なし" or "未定" or "-" || value.StartsWith("分かれば", StringComparison.Ordinal);
                    if (key == "担当") { recognized = true; owner = unknown ? null : value; }
                    if (key == "期限") { recognized = true; dueNote = unknown ? null : value; }
                }
                if (recognized) task = task[..open].Trim();
            }
            if (task.Length == 0 || task == "なし") continue;
            items.Add(new ActionItem { Owner = owner, Task = task, DueNote = dueNote });
        }
        return items;
    }
}

/// <summary>会議 1 つ。保存先のフォルダ名が Id</summary>
public sealed class Meeting
{
    public string Id { get; set; } = "";
    public string Title { get; set; } = "";
    public DateTimeOffset StartedAt { get; set; }
    public double Duration { get; set; }
    public MeetingStatus Status { get; set; } = MeetingStatus.Recording;
    /// <summary>話者キー → 表示名</summary>
    public Dictionary<string, string> SpeakerNames { get; set; } = new();
    public List<Utterance> Utterances { get; set; } = new();
    public string? Minutes { get; set; }
    public string? ErrorMessage { get; set; }
    /// <summary>議事録の型（<see cref="MinutesTemplate"/> の RawValue）。null は「自動」</summary>
    [JsonPropertyName("minutesTemplate")]
    public string? MinutesTemplateId { get; set; }
    /// <summary>型が「カスタム」のときの指示</summary>
    public string? CustomMinutesPrompt { get; set; }
    /// <summary>議事録から取り出したアクションアイテム。null はこの機能より前に作った議事録</summary>
    public List<ActionItem>? ActionItems { get; set; }
    /// <summary>メモと「ここ重要」の印。古い会議にはないので省略可</summary>
    public List<MeetingNote>? Notes { get; set; }
    /// <summary>
    /// Windows 版だけが書く: チャンネル（"me" / "others"）の音声が録音開始から何秒後に始まったか。
    /// 音声を文字起こしし直すときに使う。Mac 版は知らないキーを読み飛ばすので、互換性は崩れない
    /// </summary>
    public Dictionary<string, double>? AudioStartOffsets { get; set; }

    public string DisplayName(string speaker)
    {
        if (SpeakerNames.TryGetValue(speaker, out var name) && name.Length > 0) return name;
        switch (speaker)
        {
            case "me": return "自分";
            case "others": return "相手";
        }
        if (speaker.StartsWith("spk", StringComparison.Ordinal) && int.TryParse(speaker[3..], out var n)) return $"話者{n}";
        if (speaker.StartsWith("room", StringComparison.Ordinal) && int.TryParse(speaker[4..], out var r)) return $"同席者{r}";
        return speaker;
    }

    /// <summary>登場順の話者キー</summary>
    [JsonIgnore]
    public IReadOnlyList<string> Speakers
    {
        get
        {
            var seen = new List<string>();
            foreach (var u in Utterances) if (!seen.Contains(u.Speaker)) seen.Add(u.Speaker);
            return seen;
        }
    }

    /// <summary>同じ話者が間を空けずに続く発言をまとめる</summary>
    public List<Utterance> MergedBlocks(double maxGap = 2.0)
    {
        var blocks = new List<Utterance>();
        foreach (var u in Utterances.OrderBy(u => u.Start))
        {
            if (blocks.Count > 0 && blocks[^1] is var last && last.Speaker == u.Speaker && u.Start - last.End <= maxGap)
            {
                last.Text += u.Text;
                last.End = Math.Max(last.End, u.End);
            }
            else
            {
                blocks.Add(u.Copy());
            }
        }
        return blocks;
    }

    /// <summary>文字起こしの Markdown（transcript.md）</summary>
    public string TranscriptMarkdown()
    {
        var lines = new List<string> { $"# {Title} — 文字起こし", "", $"- 日時: {FormatDate(StartedAt)}", $"- 長さ: {Clock(Duration)}", "" };
        foreach (var block in MergedBlocks())
        {
            lines.Add($"**[{Clock(block.Start)}] {DisplayName(block.Speaker)}**: {block.Text}");
            lines.Add("");
        }
        return string.Join("\n", lines);
    }

    /// <summary>Gemini に渡す文字起こし（1 発言 1 行）</summary>
    public string TranscriptForPrompt() =>
        string.Join("\n", MergedBlocks().Select(b => $"[{Clock(b.Start)}] {DisplayName(b.Speaker)}: {b.Text}"));

    // MARK: - メモと印（Mac 版 MeetingNotes.swift の Meeting の拡張）

    [JsonIgnore]
    public IReadOnlyList<MeetingNote> AllNotes => Notes ?? (IReadOnlyList<MeetingNote>)Array.Empty<MeetingNote>();

    [JsonIgnore]
    public IEnumerable<MeetingNote> Highlights => AllNotes.Where(n => n.Kind == MeetingNoteKind.Highlight);

    [JsonIgnore]
    public string NotesText => MeetingNote.ToText(AllNotes);

    // 要件: REQ-MTG-012
    // 設計判断: DEC-MTG-047
    /// <summary>記録中に「ここ重要」の印を取り消せる時間（秒）。押し間違いのやり直しのため。それより古い印は記録のあとに「メモ」タブで消す</summary>
    public const double HighlightUndoSeconds = 10;

    /// <summary>今取り消せる印（付けてから 10 秒以内のうち、いちばん新しいもの）。elapsed は録音開始からの秒数。なければ null</summary>
    public MeetingNote? UndoableHighlight(double elapsed) =>
        Highlights.Where(h => h.Time is { } t && elapsed - t >= 0 && elapsed - t <= HighlightUndoSeconds)
            .OrderByDescending(h => h.Time)
            .FirstOrDefault();

    public string NotesMarkdown() => $"# {Title} — メモ\n\n{NotesText}\n";

    /// <summary>「ここ重要」の印の前後で強調する範囲（印を押すのは大事な発言を聞いた後なので、前を長めにとる）</summary>
    public const double HighlightLeadTime = 30;
    public const double HighlightTrailTime = 15;

    public bool IsNearHighlight(Utterance block) =>
        Highlights.Any(h => h.Time is { } t && block.Start <= t + HighlightTrailTime && t - HighlightLeadTime <= block.End);

    /// <summary>Gemini に渡す文字起こし。印の前後の発言の行頭に ★ を付ける</summary>
    public string TranscriptForPromptMarkingHighlights() =>
        string.Join("\n", MergedBlocks().Select(b => $"{(IsNearHighlight(b) ? "★ " : "")}[{Clock(b.Start)}] {DisplayName(b.Speaker)}: {b.Text}"));

    /// <summary>Gemini に渡すメモ（なければ null）。時刻のないメモは [--:--] にする</summary>
    public string? NotesForPrompt()
    {
        if (AllNotes.Count == 0) return null;
        return string.Join("\n", AllNotes.Select(n =>
        {
            var time = n.Time is { } t ? $"[{Clock(t)}]" : "[--:--]";
            return n.Kind == MeetingNoteKind.Note
                ? $"{time} {n.Text}"
                : $"{time} ★ここ重要{(n.Text.Length == 0 ? "" : $": {n.Text}")}";
        }));
    }

    // MARK: - 議事録の型

    [JsonIgnore]
    public MinutesTemplate Template => MinutesTemplates.FromRawValue(MinutesTemplateId) ?? MinutesTemplate.Auto;

    /// <summary>アクションアイテム。古い議事録は Markdown から読み取る</summary>
    [JsonIgnore]
    public IReadOnlyList<ActionItem> ResolvedActionItems =>
        ActionItems ?? (Minutes is null ? new List<ActionItem>() : ActionItem.ParseFromMarkdown(Minutes));

    // MARK: - 書式

    /// <summary>"mm:ss"（1 時間以上は "h:mm:ss"）</summary>
    public static string Clock(double seconds)
    {
        var s = Math.Max(0, (int)Math.Floor(seconds));
        return s >= 3600 ? $"{s / 3600}:{s / 60 % 60:00}:{s % 60:00}" : $"{s / 60:00}:{s % 60:00}";
    }

    /// <summary>"2026/11/03 (火) 14:30"（Mac 版の Meeting.dateFormatter と同じ形。端末の時刻で出す）</summary>
    public static string FormatDate(DateTimeOffset date)
    {
        var local = date.ToLocalTime();
        return $"{local:yyyy/MM/dd} ({JapaneseWeekday(local.DateTime)}) {local:HH:mm}";
    }

    public static string JapaneseWeekday(DateTime date) => "日月火水木金土"[(int)date.DayOfWeek].ToString();
}

internal static class MeetingIds
{
    /// <summary>Swift の UUID().uuidString と同じ大文字の形</summary>
    public static string New() => Guid.NewGuid().ToString("D").ToUpperInvariant();
}
