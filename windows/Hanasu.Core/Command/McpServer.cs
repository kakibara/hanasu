using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;
using Hanasu.Core.Ai;
using Hanasu.Core.Settings;

namespace Hanasu.Core.Command;

// 要件: REQ-COM-189
// 設計判断: DEC-COM-186
/// <summary>
/// hanasu mcp。改行で区切った JSON-RPC を stdin から読み、本当の stdout に書く（exe が stdout を stderr に付け替える。WD6）。
/// MCP の 2026-07-28（server/discover と、リクエストごとの _meta の版）と、それより前の版（initialize）の両方に応える。Mac 版 HanasuMCPServer の移植
/// </summary>
public sealed class McpServer
{
    public const string ModernVersion = "2026-07-28";
    /// <summary>initialize で取り決める版（新しい順）</summary>
    public static readonly string[] LegacyVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"];
    public const string VersionKey = "io.modelcontextprotocol/protocolVersion";
    public const string ServerInfoKey = "io.modelcontextprotocol/serverInfo";
    /// <summary>tools/list の結果を使い回してよい時間（ask_meetings の説明は設定の AI で変わるので短め）</summary>
    public const int ToolsTtlMilliseconds = 60_000;

    private readonly McpTools tools;
    private readonly CommandContext context;
    private readonly object gate = new();
    private readonly Dictionary<string, (Task Task, CancellationTokenSource Cancel)> running = new(StringComparer.Ordinal);

    public McpServer(McpTools tools, CommandContext context)
    {
        this.tools = tools;
        this.context = context;
    }

    public static async Task<HanasuExit> RunAsync(IReadOnlyList<string> arguments, CommandContext context)
    {
        var args = CommandArguments.Parse(arguments, ["--help", "-h"], [.. MeetingsCommand.CommonOptions, .. CommandAi.Options]);
        if (CommandHelp.WantsHelp(args, "mcp", context)) return HanasuExit.Ok;
        if (args.Positionals.Count > 0) throw CommandException.Usage(string.Format(Strings.Cmd_UnknownArgument, args.Positionals[0]));
        // --ai に知らない名前があれば、ここで使い方の誤りにする（ask_meetings で初めて分かるのでは遅い）
        CommandAi.Choice(args, CommandAi.AskUse, context.Settings);
        var server = new McpServer(new McpTools(MeetingsCommand.MeetingsDirectory(args, context), args.Value("--ai"), args.Value("--model"), context), context);
        context.Console.Err(Strings.Cmd_McpRunning);
        await server.ServeAsync().ConfigureAwait(false);
        return HanasuExit.Ok;
    }

    /// <summary>stdin が閉じるまで 1 行ずつ処理し、処理中のリクエストが終わるのを待って返る</summary>
    public async Task ServeAsync()
    {
        while (await context.Console.ReadProtocolLineAsync(CancellationToken.None).ConfigureAwait(false) is { } line)
        {
            Receive(line);
        }
        while (true)
        {
            Task? next;
            lock (gate) next = running.Values.Select(r => r.Task).FirstOrDefault();
            if (next is null) break;
            try { await next.ConfigureAwait(false); } catch (OperationCanceledException) { }
        }
    }

    public void Receive(string line)
    {
        var trimmed = line.Trim();
        if (trimmed.Length == 0) return;
        JsonNode? message;
        try
        {
            message = JsonNode.Parse(trimmed);
        }
        catch (JsonException)
        {
            Write(Error(null, -32700, "Parse error"));
            return;
        }
        if (message is JsonArray batch)
        {
            // 2025-03-26 のまとめたリクエスト。1 つずつ処理して、応答を配列で返す
            if (batch.Count == 0)
            {
                Write(Error(null, -32600, "Invalid Request"));
                return;
            }
            Start("batch-" + Guid.NewGuid(), async token =>
            {
                var responses = new JsonArray();
                foreach (var item in batch.ToList())
                {
                    if (await HandleAsync(item?.DeepClone(), token).ConfigureAwait(false) is { } response) responses.Add(response);
                }
                if (responses.Count > 0) Write(responses);
            });
            return;
        }
        if (message is not JsonObject json)
        {
            Write(Error(null, -32600, "Invalid Request"));
            return;
        }
        // 取り消しは、処理中のリクエストを止めるだけで、応答は返さない
        if (json["method"]?.GetValueKind() == JsonValueKind.String && json["method"]!.GetValue<string>() == "notifications/cancelled")
        {
            if (json["params"] is JsonObject p && p["requestId"] is { } requestId) Cancel(Key(requestId));
            return;
        }
        var key = json["id"] is { } id ? Key(id) : "notification-" + Guid.NewGuid();
        Start(key, async token =>
        {
            var response = await HandleAsync(json, token).ConfigureAwait(false);
            if (!token.IsCancellationRequested && response is not null) Write(response);
        });
    }

    /// <summary>処理を始めて、終わるまで running に置く。登録はロックの中で行う（先に終わった処理が残らないように）</summary>
    private void Start(string key, Func<CancellationToken, Task> body)
    {
        lock (gate)
        {
            var cancel = new CancellationTokenSource();
            var task = Task.Run(async () =>
            {
                try { await body(cancel.Token).ConfigureAwait(false); }
                finally
                {
                    lock (gate) running.Remove(key);
                }
            });
            running[key] = (task, cancel);
        }
    }

    private void Cancel(string key)
    {
        lock (gate)
        {
            if (running.TryGetValue(key, out var entry)) entry.Cancel.Cancel();
        }
    }

    private static string Key(JsonNode id) => "id-" + id.ToJsonString();

    /// <summary>1 行に 1 つのメッセージ。U+2028・U+2029 も \u の形にする（行の区切りと取り違えられないように）</summary>
    private void Write(JsonNode message)
    {
        var text = CommandJson.Serialize(message).Replace("\u2028", "\\u2028", StringComparison.Ordinal).Replace("\u2029", "\\u2029", StringComparison.Ordinal);
        lock (gate) context.Console.WriteProtocolLine(text);
    }

    /// <summary>応答（通知と、クライアントからの応答には null）</summary>
    public async Task<JsonObject?> HandleAsync(JsonNode? message, CancellationToken cancellationToken)
    {
        if (message is not JsonObject json) return Error(null, -32600, "Invalid Request");
        var id = json["id"]?.DeepClone();
        var hasId = json.ContainsKey("id");
        if (json["method"] is not JsonValue methodValue || methodValue.GetValueKind() != JsonValueKind.String)
        {
            // クライアントからの応答（こちらからはリクエストを送らないので、捨てる）。id もなければ形の誤り
            return hasId ? null : Error(null, -32600, "Invalid Request");
        }
        var method = methodValue.GetValue<string>();
        var isNotification = !hasId;
        JsonObject? Reply(JsonObject result) => isNotification ? null : new JsonObject { ["jsonrpc"] = "2.0", ["id"] = id?.DeepClone(), ["result"] = result };
        JsonObject? Fail(int code, string text, JsonNode? data = null) => isNotification ? null : Error(id?.DeepClone(), code, text, data);

        if (json["params"] is { } rawParams && rawParams is not JsonObject) return Fail(-32602, "Invalid params: params must be an object");
        var parameters = json["params"] as JsonObject ?? new JsonObject();
        // 2026-07-28: リクエストごとに _meta で版を名乗る
        var requested = (parameters["_meta"] as JsonObject)?[VersionKey] is JsonValue v && v.GetValueKind() == JsonValueKind.String ? v.GetValue<string>() : null;
        if (requested is not null && requested != ModernVersion)
        {
            return Fail(-32022, "Unsupported protocol version", new JsonObject
            {
                ["supported"] = new JsonArray(ModernVersion),
                ["requested"] = requested,
            });
        }
        var modern = requested is not null;
        JsonObject? Complete(JsonObject result)
        {
            if (!modern) return Reply(result);
            result["resultType"] = "complete";
            var meta = result["_meta"] as JsonObject ?? new JsonObject();
            meta[ServerInfoKey] = ServerInfo(context.Version);
            result["_meta"] = meta;
            return Reply(result);
        }

        switch (method)
        {
            case "initialize":
                var asked = parameters["protocolVersion"] is JsonValue pv && pv.GetValueKind() == JsonValueKind.String ? pv.GetValue<string>() : "";
                return Reply(new JsonObject
                {
                    ["protocolVersion"] = LegacyVersions.Contains(asked) ? asked : LegacyVersions[0],
                    ["capabilities"] = new JsonObject { ["tools"] = new JsonObject { ["listChanged"] = false } },
                    ["serverInfo"] = ServerInfo(context.Version),
                    ["instructions"] = McpTools.Instructions(context.Device),
                });
            case "server/discover":
                return Complete(new JsonObject
                {
                    ["supportedVersions"] = new JsonArray(ModernVersion),
                    ["capabilities"] = new JsonObject { ["tools"] = new JsonObject { ["listChanged"] = false } },
                    ["instructions"] = McpTools.Instructions(context.Device),
                    ["ttlMs"] = ToolsTtlMilliseconds,
                    ["cacheScope"] = "private",
                });
            case "ping":
                return Complete(new JsonObject());
            case "tools/list":
                var list = new JsonObject { ["tools"] = tools.Definitions() };
                if (modern)
                {
                    list["ttlMs"] = ToolsTtlMilliseconds;
                    list["cacheScope"] = "private";
                }
                return Complete(list);
            case "tools/call":
                if (parameters["name"] is not JsonValue nameValue || nameValue.GetValueKind() != JsonValueKind.String || nameValue.GetValue<string>().Length == 0)
                {
                    return Fail(-32602, "Invalid params: missing tool name");
                }
                var name = nameValue.GetValue<string>();
                var rawArguments = parameters["arguments"];
                if (rawArguments is not null && rawArguments is not JsonObject) return Fail(-32602, "Invalid params: arguments must be an object");
                if (!McpTools.Has(name)) return Fail(-32602, $"Unknown tool: {name}");
                return Complete(await tools.CallAsync(name, rawArguments as JsonObject ?? new JsonObject(), cancellationToken).ConfigureAwait(false));
            default:
                return method.StartsWith("notifications/", StringComparison.Ordinal) ? null : Fail(-32601, $"Method not found: {method}");
        }
    }

    public static JsonObject ServerInfo(string version) => new() { ["name"] = "hanasu", ["title"] = "Hanasu", ["version"] = version };

    public static JsonObject Error(JsonNode? id, int code, string message, JsonNode? data = null)
    {
        var error = new JsonObject { ["code"] = code, ["message"] = message };
        if (data is not null) error["data"] = data;
        return new JsonObject { ["jsonrpc"] = "2.0", ["id"] = id, ["error"] = error };
    }
}

// 要件: REQ-MTG-127
// 設計判断: DEC-MTG-125, DEC-MTG-121, DEC-COM-187, DEC-COM-191
/// <summary>
/// hanasu mcp のツール。名前・説明・引数の説明・注釈・決まり文句は外への約束なので英語で固定し、文は Mac 版と共有のファイルから読む。
/// エラーの理由のうち、コマンドと共通の処理から来るものは表示の言語
/// </summary>
public sealed class McpTools(string directory, string? ai, string? model, CommandContext context)
{
    /// <summary>文字起こしと議事録を、1 回の結果でここまでにする（JSON にした長さ）</summary>
    public const int MaxCharacters = 20_000;
    public const int HitsPerMeeting = 5;

    public static readonly string[] Names = ["list_meetings", "get_meeting", "search_meetings", "ask_meetings", "list_action_items"];

    public static bool Has(string name) => Names.Contains(name);

    public static string Instructions(string device) => SharedText.Text("mcp.instructions", device);
    public string Notice => SharedText.Text("mcp.notice", context.Device);

    private string Property(string name) => SharedText.Text($"mcp.properties.{name}", context.Device);
    private string Title(string name) => SharedText.Text($"mcp.tools.{name}.title", context.Device);
    private string Description(string name, params (string, string)[] args) => SharedText.Text($"mcp.tools.{name}.description", context.Device, args);

    public JsonArray Definitions() => new(Names.Select(n => (JsonNode)Definition(n)).ToArray());

    private JsonObject PeriodProperties() => new()
    {
        ["since"] = new JsonObject { ["type"] = "string", ["description"] = Property("since") },
        ["until"] = new JsonObject { ["type"] = "string", ["description"] = Property("until") },
    };

    private JsonObject Paging(int defaultLimit, int maxLimit) => new()
    {
        ["limit"] = new JsonObject { ["type"] = "integer", ["minimum"] = 1, ["maximum"] = maxLimit, ["default"] = defaultLimit, ["description"] = Property("limit") },
        ["offset"] = new JsonObject { ["type"] = "integer", ["minimum"] = 0, ["default"] = 0, ["description"] = Property("offset") },
    };

    private static JsonObject Merge(params JsonObject[] parts)
    {
        var result = new JsonObject();
        foreach (var part in parts)
        {
            foreach (var (key, value) in part.ToList()) result.TryAdd(key, value?.DeepClone());
        }
        return result;
    }

    private static JsonObject Schema(JsonObject properties, params string[] required)
    {
        var schema = new JsonObject { ["type"] = "object", ["properties"] = properties, ["additionalProperties"] = false };
        if (required.Length > 0) schema["required"] = new JsonArray(required.Select(r => (JsonNode)r).ToArray());
        return schema;
    }

    private static JsonObject Annotations(string title, bool openWorld) => new()
    {
        ["title"] = title,
        ["readOnlyHint"] = true,
        ["destructiveHint"] = false,
        ["idempotentHint"] = !openWorld,
        ["openWorldHint"] = openWorld,
    };

    private JsonObject Definition(string name)
    {
        var description = Description(name);
        JsonObject schema;
        var openWorld = false;
        switch (name)
        {
            case "list_meetings":
                schema = Schema(Merge(PeriodProperties(), Paging(20, 100)));
                break;
            case "get_meeting":
                description = Description(name, ("maxCharacters", MaxCharacters.ToString(CultureInfo.InvariantCulture)));
                schema = Schema(new JsonObject
                {
                    ["meeting"] = new JsonObject { ["type"] = "string", ["description"] = Property("meeting") },
                    ["include"] = new JsonObject
                    {
                        ["type"] = "array",
                        ["uniqueItems"] = true,
                        ["items"] = new JsonObject { ["type"] = "string", ["enum"] = new JsonArray("minutes", "actionItems", "notes", "transcript") },
                        ["default"] = new JsonArray("minutes", "actionItems"),
                        ["description"] = Property("include"),
                    },
                    ["transcriptFrom"] = new JsonObject { ["type"] = "number", ["minimum"] = 0, ["description"] = Property("transcriptFrom") },
                    ["transcriptTo"] = new JsonObject { ["type"] = "number", ["minimum"] = 0, ["description"] = Property("transcriptTo") },
                }, "meeting");
                break;
            case "search_meetings":
                description = Description(name, ("hitsPerMeeting", HitsPerMeeting.ToString(CultureInfo.InvariantCulture)));
                schema = Schema(Merge(new JsonObject { ["query"] = new JsonObject { ["type"] = "string", ["description"] = Property("query") } },
                    PeriodProperties(), Paging(10, 50)), "query");
                break;
            case "ask_meetings":
                AiChoice? choice = null;
                try { choice = CommandAi.Choice(ai, model, CommandAi.AskUse, context.Settings); } catch (CommandException) { }
                openWorld = choice is null || choice.Provider != TextAiProvider.Local;
                var destination = choice is null ? SharedText.Text("mcp.destinations.unknown", context.Device)
                    : SharedText.Text($"mcp.destinations.{choice.ProviderName}", context.Device, ("model", choice.Model));
                description = Description(name, ("destination", destination));
                schema = Schema(Merge(new JsonObject { ["question"] = new JsonObject { ["type"] = "string", ["description"] = Property("question") } },
                    PeriodProperties()), "question");
                break;
            default:
                schema = Schema(Merge(new JsonObject { ["owner"] = new JsonObject { ["type"] = "string", ["description"] = Property("owner") } },
                    PeriodProperties(), Paging(50, 200)));
                break;
        }
        return new JsonObject
        {
            ["name"] = name,
            ["title"] = Title(name),
            ["description"] = description,
            ["inputSchema"] = schema,
            ["annotations"] = Annotations(Title(name), openWorld),
        };
    }

    /// <summary>引数の値の誤り（モデルが直してやり直せるよう、ツールの結果の isError で返す。SEP-1303）</summary>
    private sealed class ArgumentProblem(string message) : Exception(message);

    public async Task<JsonObject> CallAsync(string name, JsonObject arguments, CancellationToken cancellationToken)
    {
        try
        {
            var allowed = ((Definition(name)["inputSchema"] as JsonObject)?["properties"] as JsonObject)?.Select(p => p.Key).Order(StringComparer.Ordinal).ToList() ?? [];
            if (arguments.Select(p => p.Key).Order(StringComparer.Ordinal).FirstOrDefault(k => !allowed.Contains(k)) is { } unknown)
            {
                throw new ArgumentProblem($"Unknown argument: {unknown}. Allowed: {string.Join(", ", allowed)}.");
            }
            var payload = name switch
            {
                "list_meetings" => ListMeetings(arguments),
                "get_meeting" => GetMeeting(arguments),
                "search_meetings" => SearchMeetings(arguments),
                "ask_meetings" => await AskMeetingsAsync(arguments, cancellationToken).ConfigureAwait(false),
                _ => ListActionItems(arguments),
            };
            return Success(payload);
        }
        catch (ArgumentProblem e)
        {
            return Failure("Invalid arguments: " + e.Message);
        }
        catch (CommandException e)
        {
            return Failure(string.Join("\n", new[] { e.Message }.Concat(e.Details)));
        }
        catch (Exception e) when (e is not OperationCanceledException)
        {
            return Failure(e.Message);
        }
    }

    public JsonObject Success(JsonObject payload)
    {
        payload["schemaVersion"] = CommandJson.SchemaVersion;
        payload["notice"] = Notice;
        return new JsonObject
        {
            ["content"] = new JsonArray(new JsonObject { ["type"] = "text", ["text"] = CommandJson.Serialize(payload) }),
            ["isError"] = false,
        };
    }

    public static JsonObject Failure(string message) => new()
    {
        ["content"] = new JsonArray(new JsonObject { ["type"] = "text", ["text"] = message }),
        ["isError"] = true,
    };

    // MARK: - ツール

    private JsonObject ListMeetings(JsonObject arguments)
    {
        var period = Period(arguments);
        var loaded = MeetingsCommand.Load(directory);
        var meetings = loaded.Meetings.Where(m => period.Contains(m.StartedAt)).ToList();
        var json = Page(meetings, arguments, 20, 100, "meetings", m => MeetingsCommand.Summary(m, context));
        json["unreadableMeetingCount"] = loaded.Unreadable.Count;
        return json;
    }

    private JsonObject GetMeeting(JsonObject arguments)
    {
        if (String(arguments, "meeting") is not { Length: > 0 } reference) throw new ArgumentProblem("meeting is required.");
        var include = new HashSet<string>(["minutes", "actionItems"], StringComparer.Ordinal);
        if (arguments["include"] is { } raw)
        {
            if (raw is not JsonArray list || list.Any(i => i is not JsonValue v || v.GetValueKind() != JsonValueKind.String))
            {
                throw new ArgumentProblem("include must be an array of strings.");
            }
            string[] known = ["minutes", "actionItems", "notes", "transcript"];
            var parts = list.Select(i => i!.GetValue<string>()).ToList();
            if (parts.FirstOrDefault(p => !known.Contains(p)) is { } unknown)
            {
                throw new ArgumentProblem($"include has an unknown part: {unknown}. Use minutes, actionItems, notes or transcript.");
            }
            include = parts.ToHashSet(StringComparer.Ordinal);
        }
        var from = Number(arguments, "transcriptFrom") ?? 0;
        var to = Number(arguments, "transcriptTo") ?? double.PositiveInfinity;
        if (from >= to) throw new ArgumentProblem("transcriptFrom must be less than transcriptTo.");

        var meeting = MeetingsCommand.Resolve(reference, MeetingsCommand.Load(directory), context);
        var json = MeetingsCommand.MeetingJson(meeting, include.Contains("minutes"), null, include.Contains("notes"), include.Contains("actionItems"), context);
        if (meeting.Minutes is { } minutes && include.Contains("minutes") && TextElements.Count(minutes) > MaxCharacters)
        {
            json["minutes"] = TextElements.Prefix(minutes, MaxCharacters);
            json["minutesTruncated"] = true;
        }
        if (include.Contains("transcript"))
        {
            // 設計判断: DEC-MTG-125
            var blocks = MeetingsCommand.TranscriptBlocks(meeting).Where(b => b.Start >= from && b.Start < to).ToList();
            var entries = new JsonArray();
            var used = 0;
            double? next = null;
            foreach (var block in blocks)
            {
                var entry = MeetingsCommand.TranscriptEntryJson(meeting, block);
                // JSON にした長さを、バイトではなく文字で数える
                var length = TextElements.Count(CommandJson.Serialize(entry));
                if (entries.Count > 0 && used + length > MaxCharacters)
                {
                    next = block.Start;
                    break;
                }
                used += length;
                entries.Add(entry);
            }
            json["transcript"] = entries;
            json["omittedUtteranceCount"] = meeting.Utterances.Count - meeting.UsedUtterances.Count;
            json["transcriptRange"] = new JsonObject
            {
                ["from"] = CommandJson.Seconds(from),
                ["to"] = double.IsFinite(to) ? CommandJson.Seconds(to) : null,
            };
            json["transcriptTruncated"] = next is not null;
            json["transcriptNextFrom"] = next is { } n ? CommandJson.Seconds(n) : null;
        }
        return new JsonObject { ["meeting"] = json };
    }

    private JsonObject SearchMeetings(JsonObject arguments)
    {
        if (String(arguments, "query") is not { } query || MeetingSearch.Terms(query).Count == 0) throw new ArgumentProblem("query is required.");
        var period = Period(arguments);
        var loaded = MeetingsCommand.Load(directory);
        var meetings = loaded.Meetings.Where(m => period.Contains(m.StartedAt)).Select(m => m.WithUsedUtterancesOnly()).ToList();
        // 設計判断: DEC-MTG-121
        var results = MeetingSearch.Scan(meetings, query, hitsPerMeeting: HitsPerMeeting);
        var json = Page(results, arguments, 10, 50, "results", r => MeetingsCommand.SearchResultJson(r, context));
        json["query"] = query;
        json["unreadableMeetingCount"] = loaded.Unreadable.Count;
        return json;
    }

    private async Task<JsonObject> AskMeetingsAsync(JsonObject arguments, CancellationToken cancellationToken)
    {
        if (String(arguments, "question")?.Trim() is not { Length: > 0 } question) throw new ArgumentProblem("question is required.");
        var period = Period(arguments);
        var choice = CommandAi.Choice(ai, model, CommandAi.AskUse, context.Settings);
        var client = CommandAi.MakeClient(choice, TextPurpose.Ask, TimeSpan.FromSeconds(180), context);
        var loaded = MeetingsCommand.Load(directory);
        var outcome = await AiCommands.AskAsync(question, period, choice, client, loaded.Meetings, false, context, cancellationToken).ConfigureAwait(false);
        outcome.Json["unreadableMeetingCount"] = loaded.Unreadable.Count;
        return outcome.Json;
    }

    private JsonObject ListActionItems(JsonObject arguments)
    {
        var period = Period(arguments);
        var loaded = MeetingsCommand.Load(directory);
        var items = MeetingsCommand.ActionItems(loaded.Meetings, period, String(arguments, "owner"));
        var json = Page(items, arguments, 50, 200, "actionItems", e => MeetingsCommand.ActionItemJson(e, context));
        json["unreadableMeetingCount"] = loaded.Unreadable.Count;
        return json;
    }

    // MARK: - 引数

    private static string? String(JsonObject arguments, string key)
    {
        var value = arguments[key];
        if (value is null) return null;
        if (value is not JsonValue v || v.GetValueKind() != JsonValueKind.String) throw new ArgumentProblem($"{key} must be a string.");
        return v.GetValue<string>();
    }

    private static double? Number(JsonObject arguments, string key)
    {
        var value = arguments[key];
        if (value is null) return null;
        if (value is not JsonValue v || v.GetValueKind() != JsonValueKind.Number || v.GetValue<double>() < 0)
        {
            throw new ArgumentProblem($"{key} must be a number of seconds (0 or more).");
        }
        return v.GetValue<double>();
    }

    private static int Integer(JsonObject arguments, string key, int defaultValue, int min, int max)
    {
        var value = arguments[key];
        if (value is null) return defaultValue;
        if (value is JsonValue v && v.GetValueKind() == JsonValueKind.Number)
        {
            var number = v.GetValue<double>();
            if (number == Math.Round(number) && number >= min && number <= max) return (int)number;
        }
        throw new ArgumentProblem($"{key} must be an integer from {min} to {max}.");
    }

    private CommandPeriod Period(JsonObject arguments)
    {
        var since = String(arguments, "since");
        var until = String(arguments, "until");
        CommandPeriod period;
        try
        {
            period = CommandPeriod.From(since, until, context);
        }
        catch (CommandException)
        {
            throw new ArgumentProblem("since/until must be 7d, 24h, 2w (back from now), a date such as 2026-11-01, or an ISO 8601 date-time.");
        }
        if (period.Since is { } start && period.Until is { } end && start >= end) throw new ArgumentProblem("since must be before until.");
        return period;
    }

    private static JsonObject Page<T>(IReadOnlyList<T> all, JsonObject arguments, int defaultLimit, int maxLimit, string key, Func<T, JsonObject> transform)
    {
        var limit = Integer(arguments, "limit", defaultLimit, 1, maxLimit);
        var offset = Integer(arguments, "offset", 0, 0, int.MaxValue);
        var slice = all.Skip(offset).Take(limit).ToList();
        int? next = offset + slice.Count < all.Count ? offset + slice.Count : null;
        return new JsonObject
        {
            [key] = new JsonArray(slice.Select(i => (JsonNode)transform(i)).ToArray()),
            ["total"] = all.Count,
            ["offset"] = offset,
            ["nextOffset"] = next,
        };
    }
}
