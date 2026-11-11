using System.Globalization;
using System.Text.Json.Nodes;
using Hanasu.Core.Meetings;

namespace Hanasu.Core.Command;

// 要件: REQ-MTG-120, REQ-COM-185
// 設計判断: DEC-MTG-153
/// <summary>読んだ会議と、meeting.json があるのに開けない・読めなかった会議のフォルダの名前</summary>
public sealed record LoadedMeetings(IReadOnlyList<Meeting> Meetings, IReadOnlyList<string> Unreadable, string Directory)
{
    /// <summary>文の出力のとき、読めない会議があれば stderr に 1 行出す（終了コードは変えない）</summary>
    public void WarnIfUnreadable(ICommandConsole console)
    {
        if (Unreadable.Count == 0) return;
        console.Err(string.Format(Strings.Cmd_UnreadableCount, Unreadable.Count, Directory) + " " + Strings.Cmd_UnreadableAdvice);
    }
}

/// <summary>hanasu meetings …・hanasu actions。会議の記録を読むだけで、書き換えず、外に送らない。Mac 版 HanasuMeetingsCommand の移植</summary>
public static class MeetingsCommand
{
    public static readonly string[] CommonFlags = ["--json", "--help", "-h"];
    public static readonly string[] CommonOptions = ["--meetings-dir"];

    public static Task<HanasuExit> RunMeetingsAsync(IReadOnlyList<string> arguments, CommandContext context)
    {
        if (arguments.Count == 0)
        {
            // 使い方の誤りなので、使い方は stderr に出す
            context.Console.Err(CommandHelp.Section("meetings", context) ?? "");
            return Task.FromResult(HanasuExit.Usage);
        }
        var sub = arguments[0];
        if (sub is "--help" or "-h")
        {
            context.Console.Out(CommandHelp.Section("meetings", context) ?? "");
            return Task.FromResult(HanasuExit.Ok);
        }
        var rest = arguments.Skip(1).ToList();
        return Task.FromResult(sub switch
        {
            "list" => List(rest, context),
            "show" => Show(rest, context),
            "search" => Search(rest, context),
            _ => throw new CommandException(HanasuExit.Usage, string.Format(Strings.Cmd_UnknownCommand, "meetings " + sub), [Strings.Cmd_SeeHelp]),
        });
    }

    // 要件: REQ-MTG-120
    public static HanasuExit List(IReadOnlyList<string> arguments, CommandContext context)
    {
        var args = CommandArguments.Parse(arguments, CommonFlags, [.. CommonOptions, "--since", "--until", "--limit"]);
        if (CommandHelp.WantsHelp(args, "meetings", context)) return HanasuExit.Ok;
        args.NoPositionals();
        var period = CommandPeriod.From(args, context);
        var loaded = Load(args, context, includeUtterances: false);
        IEnumerable<Meeting> meetings = loaded.Meetings.Where(m => period.Contains(m.StartedAt));
        if (args.PositiveInt("--limit") is { } limit) meetings = meetings.Take(limit);
        var list = meetings.ToList();
        if (args.Json)
        {
            context.Console.Json(new JsonObject
            {
                ["meetings"] = new JsonArray(list.Select(m => (JsonNode)Summary(m, context)).ToArray()),
                ["unreadableMeetingCount"] = loaded.Unreadable.Count,
            });
            return HanasuExit.Ok;
        }
        if (list.Count == 0) context.Console.Err(Strings.Cmd_NoMeetings);
        foreach (var meeting in list) context.Console.Out(SummaryLine(meeting, context));
        return HanasuExit.Ok;
    }

    // 要件: REQ-MTG-121
    public static HanasuExit Show(IReadOnlyList<string> arguments, CommandContext context)
    {
        string[] parts = ["--transcript", "--notes", "--actions", "--all"];
        var args = CommandArguments.Parse(arguments, [.. CommonFlags, .. parts], CommonOptions);
        if (CommandHelp.WantsHelp(args, "meetings", context)) return HanasuExit.Ok;
        if (args.Positionals.Count != 1) throw new CommandException(HanasuExit.Usage, Strings.Cmd_SpecifyOneMeeting);
        var meeting = ResolveFull(args.Positionals[0], Load(args, context, includeUtterances: false), context);
        var all = args.Has("--all");
        var chosen = parts.Where(args.Has).ToList();
        // 何も選ばなければ議事録。--all ならすべて
        var wantsMinutes = all || chosen.Count == 0;
        var wantsTranscript = all || args.Has("--transcript");
        var wantsNotes = all || args.Has("--notes");
        var wantsActions = all || args.Has("--actions");
        if (args.Json)
        {
            context.Console.Json(new JsonObject
            {
                ["meeting"] = MeetingJson(meeting, wantsMinutes, wantsTranscript ? TranscriptBlocks(meeting) : null, wantsNotes, wantsActions, context),
            });
            return HanasuExit.Ok;
        }

        var sections = new List<string>();
        if (meeting.Status != MeetingStatus.Done) context.Console.Err(string.Format(Strings.Cmd_MeetingStatusPartial, StatusLabel(meeting.Status)));
        if (wantsMinutes)
        {
            if (!string.IsNullOrEmpty(meeting.Minutes))
            {
                if (meeting.MinutesOutdated == true) context.Console.Err(Strings.Cmd_MinutesOutdated);
                sections.Add(meeting.Minutes);
            }
            else
            {
                context.Console.Err(Strings.Cmd_NoMinutes);
            }
        }
        if (wantsTranscript) sections.Add(TranscriptText(meeting, context));
        if (wantsNotes)
        {
            if (meeting.AllNotes.Count == 0) context.Console.Err(Strings.Cmd_NoNotes);
            else sections.Add(meeting.NotesMarkdown());
        }
        if (wantsActions)
        {
            var items = meeting.ActionItems ?? new List<ActionItem>();
            if (items.Count == 0) context.Console.Err(Strings.Cmd_NoActions);
            else sections.Add(string.Join("\n", new[] { string.Format(Strings.Cmd_ActionsHeading, meeting.Title), "" }
                .Concat(items.Select(i => i.MarkdownLineIn(Meeting.DisplayLanguage)))));
        }
        if (sections.Count > 0) context.Console.Out(string.Join("\n\n", sections));
        return HanasuExit.Ok;
    }

    // 要件: REQ-MTG-123
    // 設計判断: DEC-MTG-121
    public static HanasuExit Search(IReadOnlyList<string> arguments, CommandContext context)
    {
        var args = CommandArguments.Parse(arguments, CommonFlags, [.. CommonOptions, "--since", "--until", "--limit"]);
        if (CommandHelp.WantsHelp(args, "meetings", context)) return HanasuExit.Ok;
        var query = string.Join(" ", args.Positionals);
        if (MeetingSearch.Terms(query).Count == 0) throw new CommandException(HanasuExit.Usage, Strings.Cmd_SpecifySearchWords);
        var period = CommandPeriod.From(args, context);
        var loaded = Load(args, context);
        var meetings = loaded.Meetings.Where(m => period.Contains(m.StartedAt)).ToList();
        // 議事録に使わない発言（除外・オフレコ・範囲外）は、外に出さないので検索しない
        IEnumerable<SearchResult> results = MeetingSearch.Scan(meetings.Select(m => m.WithUsedUtterancesOnly()).ToList(), query);
        if (args.PositiveInt("--limit") is { } limit) results = results.Take(limit);
        var list = results.ToList();
        if (args.Json)
        {
            context.Console.Json(new JsonObject
            {
                ["query"] = query,
                ["results"] = new JsonArray(list.Select(r => (JsonNode)SearchResultJson(r, context)).ToArray()),
                ["unreadableMeetingCount"] = loaded.Unreadable.Count,
            });
            return HanasuExit.Ok;
        }
        if (list.Count == 0) context.Console.Err(Strings.Cmd_NoSearchResults);
        var lines = new List<string>();
        foreach (var result in list)
        {
            lines.Add(SummaryLine(result.Meeting, context) + "  " + string.Format(Strings.Cmd_Hits, result.TotalHits));
            lines.AddRange(result.Hits.Select(h => "    " + HitLine(h)));
        }
        if (lines.Count > 0) context.Console.Out(lines);
        return HanasuExit.Ok;
    }

    // 要件: REQ-MTG-124
    public static HanasuExit Actions(IReadOnlyList<string> arguments, CommandContext context)
    {
        var args = CommandArguments.Parse(arguments, CommonFlags, [.. CommonOptions, "--since", "--until", "--owner", "--limit"]);
        if (CommandHelp.WantsHelp(args, "actions", context)) return HanasuExit.Ok;
        args.NoPositionals();
        var period = CommandPeriod.From(args, context);
        var loaded = Load(args, context, includeUtterances: false);
        IEnumerable<(Meeting Meeting, ActionItem Item)> items = ActionItems(loaded.Meetings, period, args.Value("--owner"));
        if (args.PositiveInt("--limit") is { } limit) items = items.Take(limit);
        var list = items.ToList();
        if (args.Json)
        {
            context.Console.Json(new JsonObject
            {
                ["actionItems"] = new JsonArray(list.Select(e => (JsonNode)ActionItemJson(e, context)).ToArray()),
                ["unreadableMeetingCount"] = loaded.Unreadable.Count,
            });
            return HanasuExit.Ok;
        }
        if (list.Count == 0) context.Console.Err(Strings.Cmd_NoActionItems);
        var lines = new List<string>();
        string? current = null;
        foreach (var (meeting, item) in list)
        {
            if (current != meeting.Id)
            {
                if (current is not null) lines.Add("");
                lines.Add($"{meeting.Slug}  {FormatDate(meeting.StartedAt, context)}  {meeting.Title}");
                current = meeting.Id;
            }
            lines.Add("  " + item.MarkdownLineIn(Meeting.DisplayLanguage));
        }
        if (lines.Count > 0) context.Console.Out(lines);
        return HanasuExit.Ok;
    }

    // MARK: - JSON（--json と MCP のツールで同じ形にする）

    // 要件: REQ-MTG-121, REQ-MTG-127
    /// <summary>1 つの会議。transcript は出す発言（null なら文字起こしを出さない）</summary>
    public static JsonObject MeetingJson(Meeting meeting, bool minutes, IReadOnlyList<Utterance>? transcript, bool notes, bool actions, CommandContext context)
    {
        var json = Summary(meeting, context);
        json["speakers"] = new JsonArray(meeting.Speakers.Select(k => (JsonNode)SpeakerJson(meeting, k)).ToArray());
        if (minutes)
        {
            json["minutes"] = CommandJson.Optional(meeting.Minutes);
            json["minutesOutdated"] = meeting.MinutesOutdated == true;
        }
        if (transcript is not null)
        {
            json["transcript"] = new JsonArray(transcript.Select(b => (JsonNode)TranscriptEntryJson(meeting, b)).ToArray());
            json["omittedUtteranceCount"] = meeting.Utterances.Count - meeting.UsedUtterances.Count;
        }
        if (notes)
        {
            json["notes"] = new JsonArray(meeting.AllNotes.Select(n => (JsonNode)new JsonObject
            {
                ["kind"] = n.Kind == MeetingNoteKind.Highlight ? "highlight" : "note",
                ["time"] = n.Time is { } t ? CommandJson.Seconds(t) : null,
                ["text"] = n.Text,
            }).ToArray());
        }
        if (actions) json["actionItems"] = new JsonArray((meeting.ActionItems ?? new List<ActionItem>()).Select(i => (JsonNode)ActionJson(i)).ToArray());
        return json;
    }

    public static JsonObject TranscriptEntryJson(Meeting meeting, Utterance block) => new()
    {
        ["start"] = CommandJson.Seconds(block.Start),
        ["end"] = CommandJson.Seconds(block.End),
        ["speaker"] = block.Speaker,
        ["speakerName"] = meeting.DisplayName(block.Speaker),
        ["text"] = block.Text,
    };

    // 要件: REQ-MTG-123, REQ-MTG-127
    public static JsonObject SearchResultJson(SearchResult result, CommandContext context) => new()
    {
        ["meeting"] = Summary(result.Meeting, context),
        ["totalHits"] = result.TotalHits,
        ["hits"] = new JsonArray(result.Hits.Select(h => (JsonNode)HitJson(h)).ToArray()),
    };

    // 要件: REQ-MTG-124, REQ-MTG-127
    /// <summary>会議をまたいだアクションアイテム（新しい会議から）。owner は担当の名前の一部（大文字・小文字と全角・半角を区別しない）</summary>
    public static IReadOnlyList<(Meeting Meeting, ActionItem Item)> ActionItems(IEnumerable<Meeting> meetings, CommandPeriod period, string? owner)
    {
        var folded = owner is null ? null : MeetingSearch.Fold(owner);
        var items = new List<(Meeting, ActionItem)>();
        foreach (var meeting in meetings.Where(m => period.Contains(m.StartedAt)))
        {
            foreach (var item in meeting.ActionItems ?? new List<ActionItem>())
            {
                if (folded is not null && !MeetingSearch.Fold(item.Owner ?? "").Contains(folded, StringComparison.Ordinal)) continue;
                items.Add((meeting, item));
            }
        }
        return items;
    }

    public static JsonObject ActionItemJson((Meeting Meeting, ActionItem Item) entry, CommandContext context)
    {
        var json = ActionJson(entry.Item);
        json["meeting"] = Summary(entry.Meeting, context, brief: true);
        return json;
    }

    // 設計判断: DEC-MTG-120
    public static JsonObject Summary(Meeting meeting, CommandContext context, bool brief = false)
    {
        var json = new JsonObject
        {
            ["id"] = meeting.Id,
            ["slug"] = meeting.Slug,
            ["title"] = meeting.Title,
            ["startedAt"] = CommandJson.Date(meeting.StartedAt, context.TimeZone),
        };
        if (brief) return json;
        json["durationSeconds"] = (long)Math.Round(meeting.Duration, MidpointRounding.AwayFromZero);
        json["status"] = meeting.Status switch
        {
            MeetingStatus.Recording => "recording",
            MeetingStatus.Processing => "processing",
            MeetingStatus.Failed => "failed",
            _ => "done",
        };
        json["hasMinutes"] = !string.IsNullOrEmpty(meeting.Minutes);
        // null は、アクションアイテムを取り出す機能より前に作った議事録
        json["actionItemCount"] = meeting.ActionItems is { } list ? list.Count : null;
        return json;
    }

    public static JsonObject SpeakerJson(Meeting meeting, string key) => new()
    {
        ["key"] = key,
        ["name"] = meeting.DisplayName(key),
        ["inferred"] = meeting.InferredSpeakers?.Contains(key) == true,
    };

    public static JsonObject ActionJson(ActionItem item) => new()
    {
        ["id"] = item.Id,
        ["task"] = item.Task,
        ["owner"] = CommandJson.Optional(item.Owner),
        ["due"] = CommandJson.Optional(item.Due),
        ["dueNote"] = CommandJson.Optional(item.DueNote),
    };

    public static JsonObject HitJson(SearchHit hit) => hit.Kind switch
    {
        SearchHitKind.Title => new JsonObject { ["kind"] = "title", ["text"] = hit.Snippet },
        SearchHitKind.Minutes => new JsonObject { ["kind"] = "minutes", ["line"] = hit.Line + 1, ["text"] = hit.Snippet },
        _ => new JsonObject
        {
            ["kind"] = "transcript",
            ["start"] = CommandJson.Seconds(hit.Start),
            ["speakerName"] = hit.SpeakerName,
            ["text"] = hit.Snippet,
        },
    };

    // MARK: - 会議を読む

    // 要件: REQ-MTG-125
    /// <summary>会議のフォルダ。--meetings-dir → 環境変数 HANASU_MEETINGS_DIR → アプリの保存先</summary>
    public static string MeetingsDirectory(CommandArguments args, CommandContext context) =>
        args.Value("--meetings-dir") is { Length: > 0 } value ? ExpandHome(value)
        : context.Env("HANASU_MEETINGS_DIR") is { } env ? ExpandHome(env)
        : context.DefaultMeetingsDirectory;

    private static string ExpandHome(string path) =>
        path.StartsWith('~') ? System.Environment.GetFolderPath(System.Environment.SpecialFolder.UserProfile) + path[1..] : path;

    // 要件: REQ-COM-185
    /// <summary>会議をすべて読む（新しい順）。文の出力では、読めない会議があればその数を stderr に出す</summary>
    public static LoadedMeetings Load(CommandArguments args, CommandContext context, bool includeUtterances = true)
    {
        var loaded = Load(MeetingsDirectory(args, context), includeUtterances);
        if (!args.Json) loaded.WarnIfUnreadable(context.Console);
        return loaded;
    }

    /// <summary>フォルダを読む権限がなければ、終了コード 5 と、確かめることを出す</summary>
    /// <param name="includeUtterances">false なら発言を読み飛ばす（一覧・アクションアイテム・会議の指定。DEC-MTG-123）</param>
    public static LoadedMeetings Load(string directory, bool includeUtterances = true)
    {
        try
        {
            var report = new MeetingStore(directory).LoadAllReporting(includeUtterances);
            return new LoadedMeetings(report.Meetings, report.Unreadable, directory);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            throw new CommandException(HanasuExit.Denied, string.Format(Strings.Cmd_CannotReadFolder, directory),
                [Strings.Cmd_FolderCheck, e.Message]);
        }
    }

    // 要件: REQ-MTG-122, REQ-MTG-120
    // 設計判断: DEC-MTG-120, DEC-MTG-153
    /// <summary>会議の指定（ID・空白を _ にした ID・latest・日付）を 1 つの会議に決める。読めない会議を指していれば 5</summary>
    public static Meeting Resolve(string reference, LoadedMeetings loaded, CommandContext context)
    {
        try
        {
            return Resolve(reference, loaded.Meetings, context);
        }
        catch (CommandException e) when (e.Exit == HanasuExit.NotFound
            && loaded.Unreadable.Any(name => name == reference || Meeting.SlugOf(name) == reference))
        {
            throw new CommandException(HanasuExit.Denied, string.Format(Strings.Cmd_CannotReadMeeting, reference), [Strings.Cmd_UnreadableAdvice]);
        }
    }

    /// <summary>発言を読み飛ばして読んだ会議の一覧から 1 つに決め、その会議だけを発言ごと読み直す</summary>
    public static Meeting ResolveFull(string reference, LoadedMeetings summaries, CommandContext context)
    {
        var summary = Resolve(reference, summaries, context);
        try
        {
            return new MeetingStore(summaries.Directory).Load(summary.Id)
                ?? throw new CommandException(HanasuExit.Denied, string.Format(Strings.Cmd_CannotReadMeeting, reference), [Strings.Cmd_UnreadableAdvice]);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            throw new CommandException(HanasuExit.Denied, string.Format(Strings.Cmd_CannotReadMeeting, reference), [Strings.Cmd_UnreadableAdvice, e.Message]);
        }
    }

    public static Meeting Resolve(string reference, IReadOnlyList<Meeting> meetings, CommandContext context)
    {
        if (reference == "latest")
        {
            var index = meetings.ToList().FindIndex(m => m.Status == MeetingStatus.Done);
            if (index < 0) throw new CommandException(HanasuExit.NotFound, Strings.Cmd_NoDoneMeeting);
            if (index > 0)
            {
                context.Console.Err(string.Format(Strings.Cmd_NewerMeetings, index, string.Join(", ", meetings.Take(index).Select(m => m.Slug))));
            }
            return meetings[index];
        }
        var slug = Meeting.SlugOf(reference);
        if (meetings.FirstOrDefault(m => m.Slug == slug) is { } exact) return exact;
        if (CommandPeriod.IsDate(reference))
        {
            var matches = meetings.Where(m => CommandPeriod.DayString(m.StartedAt, context.TimeZone) == reference).ToList();
            if (matches.Count == 1) return matches[0];
            if (matches.Count > 1)
            {
                throw new CommandException(HanasuExit.NotFound, string.Format(Strings.Cmd_AmbiguousDate, reference, matches.Count),
                    matches.Select(m => SummaryLine(m, context)).ToList());
            }
        }
        throw new CommandException(HanasuExit.NotFound, string.Format(Strings.Cmd_MeetingNotFound, reference), [Strings.Cmd_SeeMeetingsList]);
    }

    // MARK: - 文の出力

    /// <summary>一覧の 1 行（ID・日時・長さ・タイトル・状態・議事録・アクションアイテムの数）</summary>
    public static string SummaryLine(Meeting meeting, CommandContext context)
    {
        var parts = new List<string> { meeting.Slug, FormatDate(meeting.StartedAt, context), Meeting.Clock(meeting.Duration), meeting.Title };
        if (meeting.Status != MeetingStatus.Done) parts.Add($"[{StatusLabel(meeting.Status)}]");
        if (string.IsNullOrEmpty(meeting.Minutes)) parts.Add(Strings.Cmd_NoMinutesShort);
        if (meeting.ActionItems is { Count: > 0 } items) parts.Add(string.Format(Strings.Cmd_ActionCount, items.Count));
        return string.Join("  ", parts);
    }

    /// <summary>画面に出す日時（"2026/11/03 (火) 14:30"。曜日は表示の言語、その時差で）</summary>
    public static string FormatDate(DateTimeOffset date, CommandContext context) =>
        Meeting.DisplayLanguage.FormatDate(TimeZoneInfo.ConvertTime(date, context.TimeZone).DateTime, "yyyy/MM/dd (E) HH:mm");

    public static string StatusLabel(MeetingStatus status) => status switch
    {
        MeetingStatus.Recording => Strings.Cmd_StatusRecording,
        MeetingStatus.Processing => Strings.Cmd_StatusProcessing,
        MeetingStatus.Failed => Strings.Cmd_StatusFailed,
        _ => Strings.Cmd_StatusDone,
    };

    public static string HitLine(SearchHit hit) => hit.Kind switch
    {
        SearchHitKind.Title => string.Format(Strings.Cmd_HitTitle, hit.Snippet),
        SearchHitKind.Minutes => string.Format(Strings.Cmd_HitMinutes, hit.Line + 1, hit.Snippet),
        _ => $"[{Meeting.Clock(hit.Start)}] {hit.SpeakerName}: {hit.Snippet}",
    };

    // 要件: REQ-MTG-121
    // 設計判断: DEC-MTG-091
    /// <summary>出す文字起こし（議事録に使う発言だけ。transcript.md と同じ）</summary>
    public static IReadOnlyList<Utterance> TranscriptBlocks(Meeting meeting) => meeting.BlocksForMinutes();

    /// <summary>文字起こしの Markdown。AI が推測した話者名には印を付ける</summary>
    public static string TranscriptText(Meeting meeting, CommandContext context)
    {
        var lines = new List<string>
        {
            string.Format(Strings.Cmd_TranscriptHeading, meeting.Title), "",
            string.Format(Strings.Cmd_TranscriptDate, FormatDate(meeting.StartedAt, context)),
            string.Format(Strings.Cmd_TranscriptLength, Meeting.Clock(meeting.Duration)),
        };
        var omitted = meeting.Utterances.Count - meeting.UsedUtterances.Count;
        if (omitted > 0) lines.Add(string.Format(Strings.Cmd_TranscriptOmitted, omitted));
        lines.Add("");
        foreach (var block in TranscriptBlocks(meeting))
        {
            lines.Add($"**[{Meeting.Clock(block.Start)}] {SpeakerLabel(meeting, block.Speaker)}**: {block.Text}");
            lines.Add("");
        }
        return string.Join("\n", lines);
    }

    public static string SpeakerLabel(Meeting meeting, string key)
    {
        var name = meeting.DisplayName(key);
        return meeting.InferredSpeakers?.Contains(key) == true ? string.Format(Strings.Cmd_InferredName, name) : name;
    }
}
