using System.Globalization;
using System.Text.Json.Serialization;
using Hanasu.Core.Ai;

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
    // 要件: REQ-DIC-073, REQ-DIC-074
    // 設計判断: DEC-DIC-172
    /// <summary>辞書の置き換えで Text が変わったときの、認識したままの文。変わっていなければ null（meeting.json に書かない）</summary>
    public string? RawText { get; set; }

    /// <summary>認識したままの文（置き換えていなければ Text）</summary>
    [JsonIgnore]
    public string RecognizedText => RawText ?? Text;

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
    // 要件: REQ-MTG-052
    // 設計判断: DEC-MTG-134, DEC-MTG-108
    /// <summary>根拠の発言の時刻（"12:34"）。Mac 版の会議ノートで押すと文字起こしのその発言へ移る。Windows 版では使わないが、読み書きで落とさない</summary>
    public string? At { get; set; }

    [JsonIgnore]
    public DateTime? DueDate =>
        Due is not null && DateTime.TryParseExact(Due, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var d) ? d : null;

    // 要件: REQ-COM-060
    /// <summary>表示用の期限（日付が決まっていれば「11/14 (金)」、なければ話された言い方）。曜日は表示の言語で書く</summary>
    [JsonIgnore]
    public string? DueDisplay
    {
        get
        {
            if (DueDate is { } d) return Meeting.DisplayLanguage.FormatDate(d, "M/d (E)");
            return string.IsNullOrEmpty(DueNote) ? null : DueNote;
        }
    }

    // 要件: REQ-COM-061
    /// <summary>
    /// 議事録に書く 1 行（<c>- [ ] 内容（担当: 〇〇 / 期限: 11/14 (金)）</c>）。「担当」「期限」と日付はプロンプトの言語で書く
    /// （minutes.item.*。Mac 版 ActionItem.markdownLine と同じキー）
    /// </summary>
    [JsonIgnore]
    public string MarkdownLine => MarkdownLineIn(PromptLanguage.Current);

    // 要件: REQ-COM-061
    /// <summary>議事録を作ったときのプロンプトの言語で書く（作っている間に設定の言語が変わっても、議事録の中でそろえる）</summary>
    public string MarkdownLineIn(PromptLanguage language)
    {
        {
            var notes = new List<string>();
            if (!string.IsNullOrEmpty(Owner)) notes.Add($"{Prompts.Text("minutes.item.owner", language)}: {Owner}");
            var due = DueDate is { } d
                ? language.FormatDate(d, Prompts.Text("minutes.item.dueDateFormat", language))
                : string.IsNullOrEmpty(DueNote) ? null : DueNote;
            if (due is not null) notes.Add($"{Prompts.Text("minutes.item.due", language)}: {due}");
            if (notes.Count == 0) return $"- [ ] {Task}";
            return $"- [ ] {Task}" + Prompts.Text("minutes.item.details", language, ("details", string.Join(" / ", notes)));
        }
    }

    // 要件: REQ-COM-061
    /// <summary>
    /// 議事録の言語はそのときのプロンプトの言語なので、読むときはすべての言語の言い方を受け付ける（Mac 版と同じ）。
    /// 前から使っている日本語の語は見出しに含まれていればよいが、各言語の見出しは見出しの全体と一致したときだけにする
    /// （「## Задачи клиента」のような別の見出しを、アクションアイテムの節と取り違えないように）
    /// </summary>
    internal static readonly string[] LegacyActionHeadingWords = ["TODO", "ToDo", "アクション", "次のステップ"];  // skip-tr（前の版の議事録の見出し）
    internal static IReadOnlyList<string> ActionHeadings =>
        new[] { "minutes.actionHeading", "minutes.actionHeading.sales", "minutes.actionHeading.brainstorm" }.SelectMany(Prompts.AllTexts).ToList();

    internal static bool IsActionHeading(string heading)
    {
        var trimmed = heading.Trim();
        return LegacyActionHeadingWords.Any(w => trimmed.Contains(w, StringComparison.Ordinal))
            || ActionHeadings.Any(h => string.Equals(h, trimmed, StringComparison.OrdinalIgnoreCase));
    }

    /// <summary>「（担当: …」「(Owner: …」のように、担当か期限の言葉とコロンで始まるかっこの位置。なければ -1</summary>
    internal static int DetailsOpening(string task, IReadOnlyList<string> keys)
    {
        for (var i = 0; i < task.Length; i++)
        {
            if (task[i] is not ('（' or '(')) continue;
            var after = task[(i + 1)..].TrimStart(' ');
            foreach (var key in keys)
            {
                if (!after.StartsWith(key, StringComparison.Ordinal)) continue;
                var rest = after[key.Length..].TrimStart(' ');
                if (rest.Length > 0 && rest[0] is ':' or '：') return i;
            }
        }
        return -1;
    }
    internal static IReadOnlyList<string> OwnerKeys => Prompts.AllTexts("minutes.item.owner");
    internal static IReadOnlyList<string> DueKeys => Prompts.AllTexts("minutes.item.due");
    internal static IReadOnlyList<string> NoneWords => Prompts.AllTexts("minutes.result.none");

    /// <summary>
    /// Markdown の議事録のチェックボックスの行から取り出す（JSON が壊れていたとき・古い議事録用）。
    /// 「TODO」「アクション」「次のステップ」（とすべての言語のアクションアイテムの見出し）を含む見出しの下の
    /// <c>- [ ] 内容（担当: 〇〇 / 期限: △△）</c> を読む。Mac 版 ActionItem.parse(fromMarkdown:) と同じ（両方を直す）
    /// </summary>
    public static List<ActionItem> ParseFromMarkdown(string markdown)
    {
        var ownerKeys = OwnerKeys;
        var dueKeys = DueKeys;
        var noneWords = NoneWords;
        var items = new List<ActionItem>();
        var inSection = false;
        foreach (var raw in markdown.Split('\n'))
        {
            var line = raw.Trim(' ', '\t', '\r');
            if (line.StartsWith("## ", StringComparison.Ordinal))
            {
                var heading = line[3..];
                inSection = IsActionHeading(heading);
                continue;
            }
            if (!inSection || !(line.StartsWith("- [ ] ", StringComparison.Ordinal) || line.StartsWith("- [x] ", StringComparison.Ordinal))) continue;
            // 設計判断: DEC-MTG-064, DEC-MTG-134（行末の時刻の印は、担当・期限のかっこの読み取りの前に外し、根拠の時刻にする）
            var at = MinutesCitation.Marks(line[6..]) is { Count: > 0 } marks ? marks[^1].Label : null;
            var task = MinutesCitation.Strip(line[6..]).Trim();
            string? owner = null, dueNote = null;
            // 期限には「11/14 (金)」のようにかっこや / が入るので、「担当」「期限」の言葉で始まるかっこを探し、中を「 / 」で分ける
            if (task.Length > 0 && task[^1] is '）' or ')' && DetailsOpening(task, ownerKeys.Concat(dueKeys).ToList()) is var open and >= 0)
            {
                var inner = task[(open + 1)..^1];
                var recognized = false;
                foreach (var part in inner.Split(" / ").SelectMany(p => p.Split('／')))
                {
                    var pair = part.Split([':', '：'], 2);
                    if (pair.Length != 2) continue;
                    var key = pair[0].Trim();
                    var value = pair[1].Trim();
                    var unknown = value.Length == 0 || value is "不明" or "未定" or "-" || noneWords.Contains(value) || value.StartsWith("分かれば", StringComparison.Ordinal);  // skip-tr（議事録を読むときの語）
                    if (ownerKeys.Contains(key)) { recognized = true; owner = unknown ? null : value; }
                    if (dueKeys.Contains(key)) { recognized = true; dueNote = unknown ? null : value; }
                }
                if (recognized) task = task[..open].Trim();
            }
            if (task.Length == 0 || noneWords.Contains(task)) continue;
            items.Add(new ActionItem { Owner = owner, Task = task, DueNote = dueNote, At = at });
        }
        return items;
    }
}

/// <summary>会議 1 つ。保存先のフォルダ名が Id（議事録に使う発言の選び方は MinutesSelection.cs）</summary>
public sealed partial class Meeting
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
    // 設計判断: DEC-MTG-076
    /// <summary>Mac 版で保存したテンプレートで作った会議のテンプレート名。Windows 版では使わないが、書き直しても落とさない</summary>
    public string? MinutesTemplateName { get; set; }
    /// <summary>議事録から取り出したアクションアイテム。null はこの機能より前に作った議事録</summary>
    public List<ActionItem>? ActionItems { get; set; }
    /// <summary>メモと「ここ重要」の印。古い会議にはないので省略可</summary>
    public List<MeetingNote>? Notes { get; set; }
    /// <summary>
    /// チャンネル（"me" / "others"）の音声が録音開始から何秒後に始まったか。
    /// 音声を文字起こしし直すときに使う。Mac 版も書いて読む（再生で 2 つのチャンネルを並べる。DEC-MTG-135）
    /// </summary>
    public Dictionary<string, double>? AudioStartOffsets { get; set; }
    /// <summary>会話から推測して名前を付けた話者キー（SpeakerNameInference）。ユーザーが直すと外す。古い会議にはないので省略可（Mac 版と同じキー）</summary>
    // 設計判断: DEC-MTG-069
    public List<string>? InferredSpeakers { get; set; }
    // 要件: REQ-MTG-044, REQ-MTG-045, REQ-MTG-046
    // 設計判断: DEC-MTG-090
    /// <summary>議事録に使う範囲（発言の開始時刻の秒）。null は端まで（MinutesSelection.cs。Mac 版と同じキー）</summary>
    public double? MinutesFrom { get; set; }
    public double? MinutesTo { get; set; }
    /// <summary>議事録から除いた発言の ID</summary>
    public List<string>? ExcludedUtterances { get; set; }
    /// <summary>議事録から除いた話者キー</summary>
    public List<string>? ExcludedSpeakers { get; set; }
    /// <summary>記録中に「オフレコ」にした区間</summary>
    public List<OffRecordSpan>? OffRecord { get; set; }
    // 設計判断: DEC-MTG-092
    /// <summary>議事録に使う発言を変えたあと、議事録をまだ作り直していない</summary>
    public bool? MinutesOutdated { get; set; }

    /// <summary>議事録の結果を入れる。応答で分かった話者の名前も、名前のない話者に付ける</summary>
    // 要件: REQ-MTG-027
    public void ApplyMinutes(MinutesResult result)
    {
        var (minutes, _) = SpeakerNameInference.Apply(result.SpeakerNames, this, result);
        Minutes = minutes.Markdown;
        ActionItems = minutes.ActionItems;
    }

    /// <summary>話者名を手で付け替える。推測で付けた名前を直したら（消したときも）、推測の印を外す。変わったら true</summary>
    // 要件: REQ-MTG-008
    // 設計判断: DEC-MTG-069
    public bool RenameSpeaker(string speaker, string name)
    {
        var next = name.Trim();
        if (SpeakerNames.GetValueOrDefault(speaker, "") == next) return false;
        if (next.Length == 0) SpeakerNames.Remove(speaker);
        else SpeakerNames[speaker] = next;
        InferredSpeakers?.Remove(speaker);
        if (InferredSpeakers is { Count: 0 }) InferredSpeakers = null;
        return true;
    }

    /// <summary>会話から推測して付けた名前か</summary>
    public bool IsInferredName(string speaker) =>
        InferredSpeakers?.Contains(speaker) == true && SpeakerNames.GetValueOrDefault(speaker, "").Length > 0;

    public string DisplayName(string speaker)
    {
        if (SpeakerNames.TryGetValue(speaker, out var name) && name.Length > 0) return name;
        switch (speaker)
        {
            case "me": return Strings.Speaker_Me;
            case "others": return Strings.Speaker_Others;
        }
        if (speaker.StartsWith("spk", StringComparison.Ordinal) && int.TryParse(speaker[3..], out var n)) return string.Format(Strings.Speaker_Remote, n);
        if (speaker.StartsWith("room", StringComparison.Ordinal) && int.TryParse(speaker[4..], out var r)) return string.Format(Strings.Speaker_Room, r);
        return speaker;
    }

    // 要件: REQ-COM-061
    /// <summary>プロンプトに書く話者名。名前を付けていれば名前、なければプロンプトの言語のラベル（「自分」「話者1」など）</summary>
    public string PromptName(string speaker, PromptLanguage? language = null) =>
        SpeakerNames.TryGetValue(speaker, out var name) && name.Length > 0 ? name : PromptLabel(speaker, language);

    // 要件: REQ-COM-061
    /// <summary>名前のない話者の、プロンプトの言語のラベル（speaker.*。Mac 版 Meeting.promptLabel と同じキー）</summary>
    public static string PromptLabel(string speaker, PromptLanguage? language = null)
    {
        switch (speaker)
        {
            case "me": return Prompts.Text("speaker.me", language);
            case "others": return Prompts.Text("speaker.others", language);
        }
        if (speaker.StartsWith("spk", StringComparison.Ordinal) && int.TryParse(speaker[3..], out var n)) return Prompts.Text("speaker.remote", language, ("n", n.ToString(CultureInfo.InvariantCulture)));
        if (speaker.StartsWith("room", StringComparison.Ordinal) && int.TryParse(speaker[4..], out var r)) return Prompts.Text("speaker.room", language, ("n", r.ToString(CultureInfo.InvariantCulture)));
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
                JoinInto(last, u);
            }
            else
            {
                blocks.Add(u.Copy());
            }
        }
        return blocks;
    }

    /// <summary>文字起こしの Markdown（transcript.md・コピー）。議事録に使う発言だけを書く</summary>
    public string TranscriptMarkdown()
    {
        var lines = new List<string>
        {
            string.Format(Strings.Transcript_Heading, Title), "",
            string.Format(Strings.Transcript_Date, FormatDate(StartedAt)),
            string.Format(Strings.Transcript_Duration, Clock(Duration)), "",
        };
        // 要件: REQ-MTG-045
        // 設計判断: DEC-MTG-091
        var unused = Utterances.Count - UsedUtterances.Count;
        if (unused > 0) lines.Insert(lines.Count - 1, string.Format(Strings.Transcript_UnusedOmitted, unused));
        foreach (var block in BlocksForMinutes())
        {
            lines.Add($"**[{Clock(block.Start)}] {DisplayName(block.Speaker)}**: {block.Text}");
            lines.Add("");
        }
        return string.Join("\n", lines);
    }

    // 設計判断: DEC-DIC-172
    /// <summary>続く発言をつなぐ（into を書き換える）。どちらかを辞書で置き換えていれば、認識したままの文もつなぐ（Text だけをつなぐと読みが消える）</summary>
    public static void JoinInto(Utterance into, Utterance next)
    {
        if (into.RawText != null || next.RawText != null) into.RawText = into.RecognizedText + next.RecognizedText;
        into.Text += next.Text;
        into.End = Math.Max(into.End, next.End);
    }

    // 要件: REQ-COM-061
    /// <summary>
    /// Gemini に渡す文字起こし（1 発言 1 行。話者名はプロンプトの言語）。議事録に使う発言だけ。
    /// raw が true なら、辞書で置き換える前の認識したままの文で並べる（辞書の候補の材料。DEC-DIC-088・172）
    /// </summary>
    public string TranscriptForPrompt(bool raw = false)
    {
        var language = PromptLanguage.Current;
        // 設計判断: DEC-MTG-091
        return string.Join("\n", BlocksForMinutes().Select(b => $"[{Clock(b.Start)}] {PromptName(b.Speaker, language)}: {(raw ? b.RecognizedText : b.Text)}"));
    }

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

    public string NotesMarkdown() => string.Format(Strings.Notes_Heading, Title) + $"\n\n{NotesText}\n";

    /// <summary>「ここ重要」の印の前後で強調する範囲（印を押すのは大事な発言を聞いた後なので、前を長めにとる）</summary>
    public const double HighlightLeadTime = 30;
    public const double HighlightTrailTime = 15;

    // 要件: REQ-MTG-012
    // 設計判断: DEC-MTG-041, DEC-MTG-049
    /// <summary>「ここ重要」の印ごとの、前後の発言（議事録で重要として扱うのと同じ 30 秒前〜15 秒後）。時刻の順</summary>
    public IReadOnlyList<(MeetingNote Note, IReadOnlyList<Utterance> Blocks)> HighlightContexts()
    {
        var blocks = MergedBlocks();
        return Highlights.Where(h => h.Time is not null).OrderBy(h => h.Time)
            .Select(h =>
            {
                var t = h.Time!.Value;
                IReadOnlyList<Utterance> near = blocks.Where(b => b.Start <= t + HighlightTrailTime && t - HighlightLeadTime <= b.End).ToList();
                return (h, near);
            })
            .ToList();
    }

    /// <summary>会議ノートの「ここ重要」タブに出す文章（印ごとに見出しと前後の発言）</summary>
    public string HighlightContextText()
    {
        var contexts = HighlightContexts();
        if (contexts.Count == 0)
        {
            return Strings.Highlights_None;
        }
        var lines = new List<string>();
        foreach (var (note, blocks) in contexts)
        {
            if (lines.Count > 0) lines.Add("");
            lines.Add($"★ {Clock(note.Time ?? 0)}  {(note.Text.Length == 0 ? Strings.Highlight_Default : note.Text)}");
            if (blocks.Count == 0) lines.Add("    " + Strings.Highlights_NoUtterances);
            lines.AddRange(blocks.Select(b => $"    [{Clock(b.Start)}] {DisplayName(b.Speaker)}: {b.Text}"));
        }
        return string.Join("\n", lines);
    }

    public bool IsNearHighlight(Utterance block) =>
        Highlights.Any(h => h.Time is { } t && block.Start <= t + HighlightTrailTime && t - HighlightLeadTime <= block.End);

    // 要件: REQ-COM-061
    /// <summary>Gemini に渡す文字起こし。印の前後の発言の行頭に ★ を付ける（話者名はプロンプトの言語）</summary>
    public string TranscriptForPromptMarkingHighlights()
    {
        var language = PromptLanguage.Current;
        // 設計判断: DEC-MTG-091
        return string.Join("\n", BlocksForMinutes().Select(b => $"{(IsNearHighlight(b) ? "★ " : "")}[{Clock(b.Start)}] {PromptName(b.Speaker, language)}: {b.Text}"));
    }

    // 要件: REQ-COM-061
    /// <summary>Gemini に渡すメモ（なければ null）。時刻のないメモは [--:--] にする。印は minutes.notes.highlight（「★ここ重要」）</summary>
    public string? NotesForPrompt()
    {
        if (AllNotes.Count == 0) return null;
        var highlight = Prompts.Text("minutes.notes.highlight");
        return string.Join("\n", AllNotes.Select(n =>
        {
            var time = n.Time is { } t ? $"[{Clock(t)}]" : "[--:--]";
            return n.Kind == MeetingNoteKind.Note
                ? $"{time} {n.Text}"
                : $"{time} {highlight}{(n.Text.Length == 0 ? "" : $": {n.Text}")}";
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

    // 要件: REQ-COM-060
    /// <summary>"2026/11/03 (火) 14:30"（Mac 版の Meeting.dateFormatter と同じ形。端末の時刻で出す。曜日は表示の言語で書く）</summary>
    public static string FormatDate(DateTimeOffset date) =>
        DisplayLanguage.FormatDate(date.ToLocalTime().DateTime, "yyyy/MM/dd (E) HH:mm");

    // 要件: REQ-COM-060
    /// <summary>画面に出す日付の曜日を書く言語（表示の言語。起動のときに UiLanguage.Apply で 17 言語のどれかにしてある）</summary>
    internal static PromptLanguage DisplayLanguage => PromptLanguage.FromLocaleIdentifier(CultureInfo.CurrentUICulture.Name);

    // 要件: REQ-COM-061
    /// <summary>プロンプトに書く日時（"2026/11/03 (火) 14:30" の形。曜日はプロンプトの言語で。Mac 版 PromptLanguage.dateFormatter と同じ書式）</summary>
    public static string FormatDate(DateTimeOffset date, PromptLanguage language) =>
        language.FormatDate(date.ToLocalTime().DateTime, "yyyy/MM/dd (E) HH:mm");

}

internal static class MeetingIds
{
    /// <summary>Swift の UUID().uuidString と同じ大文字の形</summary>
    public static string New() => Guid.NewGuid().ToString("D").ToUpperInvariant();
}
