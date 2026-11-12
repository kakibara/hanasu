using System.Text.Json.Nodes;
using Hanasu.Core.Ai;
using Hanasu.Core.Dictation;
using Hanasu.Core.Gemini;
using Hanasu.Core.Meetings;

namespace Hanasu.Core.Command;

// 要件: REQ-DIC-160, REQ-DIC-161, REQ-DIC-162
// 設計判断: DEC-DIC-160
/// <summary>整える文章の受け取り方。位置の引数か stdin のどちらか</summary>
public static class CommandTextInput
{
    /// <summary>選択を声で編集と同じ上限（Mac 版 EditModeSettings.maxSelectionLength）</summary>
    public const int MaxLength = 10_000;

    public static string Read(IReadOnlyList<string> positionals, ICommandConsole console)
    {
        if (positionals.Count > 0)
        {
            if (console.PendingStdin() is { } piped && piped.Trim().Length > 0) throw CommandException.Usage(Strings.Cmd_TextBoth);
            return Validated(string.Join(" ", positionals));
        }
        // 端末で入力を待つと、エージェントやスクリプトから呼んだときに止まったままになる
        if (console.StdinKind != StdinKind.Redirected) throw CommandException.Usage(Strings.Cmd_TextMissing);
        return Validated(console.ReadAllStdin());
    }

    public static string Validated(string text)
    {
        var trimmed = text.Trim();
        if (trimmed.Length == 0) throw CommandException.Usage(Strings.Cmd_TextEmpty);
        var count = TextElements.Count(trimmed);
        if (count > MaxLength) throw CommandException.Usage(string.Format(Strings.Cmd_TextTooLong, count, MaxLength));
        return trimmed;
    }
}

/// <summary>hanasu ask・refine・edit・dict apply。Mac 版 HanasuAICommands の移植</summary>
public static class AiCommands
{
    private static readonly string[] CommonFlags = ["--json", "--help", "-h"];

    /// <summary>--show-prompt: AI に送る内容を stderr に出す（stdout は結果だけ）</summary>
    private static void ShowPrompt(ICommandConsole console, string system, string user) =>
        console.Err($"----- system -----\n{system}\n----- user -----\n{user}\n------------------");

    // MARK: - ask

    // 要件: REQ-MTG-126
    // 設計判断: DEC-MTG-124, DEC-MTG-121, DEC-COM-190
    public static async Task<HanasuExit> AskAsync(IReadOnlyList<string> arguments, CommandContext context)
    {
        var args = CommandArguments.Parse(arguments, [.. CommonFlags, "--show-prompt"],
            [.. MeetingsCommand.CommonOptions, .. CommandAi.Options, "--since", "--until"]);
        if (CommandHelp.WantsHelp(args, "ask", context)) return HanasuExit.Ok;
        var question = string.Join(" ", args.Positionals).Trim();
        if (question.Length == 0) throw CommandException.Usage(Strings.Cmd_SpecifyQuestion);
        var period = CommandPeriod.From(args, context);
        CheckPeriod(period);

        var choice = CommandAi.Choice(args, CommandAi.AskUse, context.Settings);
        var client = CommandAi.MakeClient(choice, TextPurpose.Ask, TimeSpan.FromSeconds(180), context);
        var loaded = MeetingsCommand.Load(args, context);
        var outcome = await AskAsync(question, period, choice, client, loaded.Meetings, args.Has("--show-prompt"), context).ConfigureAwait(false);
        if (args.Json)
        {
            outcome.Json["unreadableMeetingCount"] = loaded.Unreadable.Count;
            context.Console.Json(outcome.Json);
            return HanasuExit.Ok;
        }
        var lines = new List<string> { outcome.Answer.Text, "", Strings.Cmd_AskSources };
        var cited = outcome.Answer.Cited.Select(s => s.Meeting.Id).ToHashSet(StringComparer.Ordinal);
        foreach (var source in outcome.Answer.Sources)
        {
            var mark = cited.Contains(source.Meeting.Id) ? "*" : " ";
            lines.Add($"  {mark} M{source.Number}  {source.Meeting.Slug}  {source.Meeting.Title}");
        }
        context.Console.Out(lines);
        return HanasuExit.Ok;
    }

    private static void CheckPeriod(CommandPeriod period)
    {
        if (period.Since is { } since && period.Until is { } until && since >= until) throw CommandException.Usage(Strings.Cmd_SinceBeforeUntil);
    }

    /// <summary>ask の結果（hanasu ask と MCP の ask_meetings で同じ）</summary>
    public sealed record AskOutcome(AskAnswer Answer, JsonObject Json);

    // 要件: REQ-MTG-126, REQ-MTG-127
    // 設計判断: DEC-MTG-124, DEC-MTG-121
    public static async Task<AskOutcome> AskAsync(string question, CommandPeriod period, AiChoice choice, ITextGenerator client,
        IReadOnlyList<Meeting> allMeetings, bool printPrompt, CommandContext context, CancellationToken cancellationToken = default)
    {
        CheckPeriod(period);
        // 議事録に使わない発言（除いた発言・オフレコ）は送らない
        var meetings = allMeetings.Select(m => m.WithUsedUtterancesOnly()).ToList();
        var options = new MeetingAsk.Options();
        if (period.IsSpecified)
        {
            // 期間は終わりを含むので、--until の時刻（含まない）の直前までにする
            options = options with
            {
                Period = new AskInterval(period.Since ?? DateTimeOffset.MinValue,
                    (period.Until ?? DateTimeOffset.MaxValue.AddSeconds(-1)).AddMilliseconds(-1)),
            };
        }
        var now = context.CurrentTime;
        var gathered = MeetingAsk.GatherContext(question, meetings, options, now, context.TimeZone);
        if (gathered.Sources.Count == 0) throw new CommandException(HanasuExit.NotFound, Strings.Cmd_NoAskMeetings);
        if (printPrompt) ShowPrompt(context.Console, MeetingAsk.Instruction, gathered.Prompt);

        string text;
        try
        {
            text = await client.GenerateTextAsync(TextPurpose.Ask, MeetingAsk.Instruction, gathered.Prompt, choice.Model, cancellationToken)
                .ConfigureAwait(false);
        }
        catch (Exception e)
        {
            throw CommandAi.Mapped(e);
        }
        var answer = new AskAnswer(text, gathered.Sources, MeetingAsk.Cited(text, gathered.Sources), gathered.Keywords);
        var cited = answer.Cited.Select(s => s.Meeting.Id).ToHashSet(StringComparer.Ordinal);
        JsonNode? periodJson = null;
        if (period.IsSpecified)
        {
            periodJson = new JsonObject
            {
                ["source"] = "option",
                ["since"] = period.Since is { } s ? CommandJson.Date(s, context.TimeZone) : null,
                ["until"] = period.Until is { } u ? CommandJson.Date(u, context.TimeZone) : null,
            };
        }
        else if (gathered.Period is { } derived)
        {
            periodJson = new JsonObject
            {
                ["source"] = "question",
                ["since"] = CommandJson.Date(derived.Start, context.TimeZone),
                ["until"] = CommandJson.Date(derived.End, context.TimeZone),
            };
        }
        var json = new JsonObject
        {
            ["question"] = question,
            ["answer"] = text,
            ["ai"] = new JsonObject { ["provider"] = choice.ProviderName, ["model"] = choice.Model },
            ["keywords"] = new JsonArray(answer.Keywords.Select(k => (JsonNode)k).ToArray()),
            ["period"] = periodJson,
            ["sources"] = new JsonArray(answer.Sources.Select(source => (JsonNode)new JsonObject
            {
                ["ref"] = $"M{source.Number}",
                ["cited"] = cited.Contains(source.Meeting.Id),
                ["matched"] = source.Matched,
                ["meeting"] = MeetingsCommand.Summary(source.Meeting, context, brief: true),
            }).ToArray()),
        };
        return new AskOutcome(answer, json);
    }

    // MARK: - refine

    // 要件: REQ-DIC-160, REQ-DIC-003, REQ-DIC-070, REQ-DIC-082, REQ-DIC-020, REQ-DIC-021, REQ-DIC-013
    // 設計判断: DEC-DIC-160, DEC-DIC-161, DEC-DIC-190
    /// <summary>音声入力と同じ整形（翻訳）。音声入力の履歴には残さない</summary>
    public static async Task<HanasuExit> RefineAsync(IReadOnlyList<string> arguments, CommandContext context)
    {
        var args = CommandArguments.Parse(arguments, [.. CommonFlags, "--show-prompt", "--fallback-raw"],
            [.. CommandAi.Options, "--app", "--style", "--translate"]);
        if (CommandHelp.WantsHelp(args, "refine", context)) return HanasuExit.Ok;

        // 引数の誤りは、文章を読む前に知らせる
        AppStylePreset? preset = null;
        if (args.Value("--style") is { } rawStyle)
        {
            preset = AppStylePresets.FromCommandValue(rawStyle) ?? throw CommandException.Usage(string.Format(Strings.Cmd_UnknownStyle, rawStyle));
        }
        TranslationLanguage? translation = null;
        if (args.Value("--translate") is { } code)
        {
            translation = TranslationCode(code) ?? throw CommandException.Usage(string.Format(Strings.Cmd_UnknownLanguage, code));
        }
        var choice = CommandAi.Choice(args, CommandAiUse.Dictation, context.Settings);
        var raw = CommandTextInput.Read(args.Positionals, context.Console);

        var settings = context.Settings;
        // --app: そのアプリ向けの既定の文体。--style: プリセットを直接選ぶ（--app の文体より優先）
        var app = args.Value("--app") is { } exe ? SharedText.StyleForApp(exe) : null;
        var style = app;
        if (preset is { } chosen) style = (style ?? new AppStyle("", "", chosen)) with { Preset = chosen };
        // 音声入力と同じく、置き換えルールを当ててから送る
        var corrected = settings.UserDictionary.Apply(raw);
        var request = new RefineRequest
        {
            Transcript = corrected,
            Model = choice.Model,
            AppName = settings.SendAppName && app is not null ? app.Name : null,
            Dictionary = settings.DictionaryWords,
            ExtraInstructions = settings.ExtraInstructions,
            DictionaryRules = settings.UserDictionary.Rules,
            AppStyle = style,
            OutputLanguage = settings.RefineOutputLanguage,
        };
        if (args.Has("--show-prompt"))
        {
            if (translation is { } target) ShowPrompt(context.Console, GeminiPrompts.TranslationSystemInstruction(target), GeminiPrompts.UserPrompt(request, target));
            else ShowPrompt(context.Console, GeminiPrompts.SystemInstruction(request.OutputLanguage), GeminiPrompts.UserPrompt(request));
        }

        string output;
        var fallback = false;
        try
        {
            var client = CommandAi.MakeClient(choice, translation is null ? TextPurpose.Refine : TextPurpose.Translate, TimeSpan.FromSeconds(60), context);
            output = translation is { } target
                ? await client.TranslateAsync(request, target).ConfigureAwait(false)
                : await client.RefineAsync(request).ConfigureAwait(false);
        }
        catch (Exception e)
        {
            output = FallbackOrThrow(e, args, corrected, context.Console);
            fallback = true;
        }
        Emit(output, args, context.Console, new JsonObject
        {
            ["ai"] = new JsonObject { ["provider"] = choice.ProviderName, ["model"] = choice.Model },
            ["fallback"] = fallback,
            ["translation"] = translation?.Code,
        });
        return HanasuExit.Ok;
    }

    /// <summary>--translate の言語のコード（en・ja・zh-CN など。english / japanese と、ja-JP のような地域付きも受け付ける）</summary>
    public static TranslationLanguage? TranslationCode(string code)
    {
        switch (code.Trim().ToLowerInvariant())
        {
            case "english": return TranslationLanguage.English;
            case "japanese": return TranslationLanguage.Japanese;
        }
        return (PromptLanguage.FromCode(code) ?? PromptLanguage.SupportedOrNull(code)) is { } language ? TranslationLanguage.Of(language) : null;
    }

    // MARK: - edit

    // 要件: REQ-DIC-161, REQ-DIC-050
    // 設計判断: DEC-DIC-160, DEC-DIC-161, DEC-DIC-033, DEC-DIC-034
    public static async Task<HanasuExit> EditAsync(IReadOnlyList<string> arguments, CommandContext context)
    {
        var args = CommandArguments.Parse(arguments, [.. CommonFlags, "--show-prompt", "--fallback-raw"], CommandAi.Options);
        if (CommandHelp.WantsHelp(args, "edit", context)) return HanasuExit.Ok;
        var instruction = args.Positionals.FirstOrDefault()?.Trim();
        if (string.IsNullOrEmpty(instruction)) throw CommandException.Usage(Strings.Cmd_SpecifyInstruction);
        var choice = CommandAi.Choice(args, CommandAiUse.Dictation, context.Settings);
        var selection = CommandTextInput.Read(args.Positionals.Skip(1).ToList(), context.Console);

        var nonce = context.Nonce ?? EditPrompt.MakeNonce();
        var user = EditPrompt.UserText(selection, instruction, appName: null, context.Settings.DictionaryWords, nonce);
        if (args.Has("--show-prompt")) ShowPrompt(context.Console, EditPrompt.Instruction, user);

        string output;
        var fallback = false;
        try
        {
            var client = CommandAi.MakeClient(choice, TextPurpose.Edit, TimeSpan.FromSeconds(60), context);
            output = EditPrompt.StripCodeFence(
                await client.GenerateTextAsync(TextPurpose.Edit, EditPrompt.Instruction, user, choice.Model).ConfigureAwait(false), selection);
        }
        catch (Exception e)
        {
            output = FallbackOrThrow(e, args, selection, context.Console);
            fallback = true;
        }
        Emit(output, args, context.Console, new JsonObject
        {
            ["ai"] = new JsonObject { ["provider"] = choice.ProviderName, ["model"] = choice.Model },
            ["fallback"] = fallback,
        });
        return HanasuExit.Ok;
    }

    // MARK: - dict apply

    // 要件: REQ-DIC-162, REQ-DIC-070
    /// <summary>辞書の置き換えルールだけを当てる。AI には何も送らない</summary>
    public static HanasuExit Dict(IReadOnlyList<string> arguments, CommandContext context)
    {
        if (arguments.Count == 0)
        {
            context.Console.Err(CommandHelp.Section("dict", context) ?? CommandHelp.Full(context));
            return HanasuExit.Usage;
        }
        if (arguments[0] is "--help" or "-h")
        {
            context.Console.Out(CommandHelp.Section("dict", context) ?? CommandHelp.Full(context));
            return HanasuExit.Ok;
        }
        if (arguments[0] != "apply") throw CommandException.Usage(string.Format(Strings.Cmd_UnknownCommand, "dict " + arguments[0]));
        var args = CommandArguments.Parse(arguments.Skip(1).ToList(), CommonFlags, []);
        if (CommandHelp.WantsHelp(args, "dict", context)) return HanasuExit.Ok;
        var text = CommandTextInput.Read(args.Positionals, context.Console);
        Emit(context.Settings.UserDictionary.Apply(text), args, context.Console, new JsonObject());
        return HanasuExit.Ok;
    }

    // MARK: - 共通

    // 設計判断: DEC-DIC-161
    /// <summary>
    /// AI が失敗したとき。--fallback-raw なら原文を返し（理由は stderr）、なければ誤りを投げる（stdout には何も出さない）。
    /// 使い方の誤りは、--fallback-raw でも止める
    /// </summary>
    private static string FallbackOrThrow(Exception error, CommandArguments args, string original, ICommandConsole console)
    {
        var mapped = CommandAi.Mapped(error);
        if (!args.Has("--fallback-raw") || mapped.Exit is not (HanasuExit.Failure or HanasuExit.Credentials)) throw mapped;
        console.Error(mapped);
        console.Err("hanasu: " + Strings.Cmd_FallbackRaw);
        return original;
    }

    private static void Emit(string text, CommandArguments args, ICommandConsole console, JsonObject extra)
    {
        if (args.Json)
        {
            extra["text"] = text;
            console.Json(extra);
        }
        else
        {
            console.Out(text);
        }
    }
}

// 要件: REQ-DIC-050, REQ-COM-061
// 設計判断: DEC-DIC-033, DEC-DIC-034
/// <summary>選択の書き換えのプロンプト（Mac 版 GeminiClient+Edit.swift の移植。文面は edit.*）</summary>
public static class EditPrompt
{
    public static string Instruction => Prompts.Text("edit.system");

    /// <summary>選択文と指示を、毎回変わる名前のタグで囲む（選択文の中に閉じタグを書いて抜け出す手口を防ぐ）</summary>
    public static string UserText(string selection, string instruction, string? appName, IReadOnlyList<string> dictionary, string nonce)
    {
        var selectionTag = $"selection_{nonce}";
        var instructionTag = $"instruction_{nonce}";
        string Sanitize(string text) => new[] { selectionTag, instructionTag }.Aggregate(text,
            (t, tag) => t.Replace($"<{tag}>", "", StringComparison.Ordinal).Replace($"</{tag}>", "", StringComparison.Ordinal));
        var lines = new List<string>();
        if (!string.IsNullOrEmpty(appName)) lines.Add(Prompts.Text("edit.user.appName", ("app", appName)));
        if (dictionary.Count > 0) lines.Add(Prompts.Text("edit.user.dictionary", ("words", string.Join(", ", dictionary))));
        lines.Add($"<{selectionTag}>\n{Sanitize(selection)}\n</{selectionTag}>");
        lines.Add($"<{instructionTag}>\n{Sanitize(instruction)}\n</{instructionTag}>");
        // 最後にもう一度、従うのは指示だけだと念を押す
        lines.Add(Prompts.Text("edit.user.reminder", ("instructionTag", instructionTag), ("selectionTag", selectionTag)));
        return string.Join("\n", lines);
    }

    public static string MakeNonce() => Guid.NewGuid().ToString("N")[..12];

    /// <summary>指示に反してコードブロックで囲んで返されたときは外す（選択文自体がコードブロックなら外さない）</summary>
    public static string StripCodeFence(string output, string selection)
    {
        if (!output.StartsWith("```", StringComparison.Ordinal) || !output.EndsWith("```", StringComparison.Ordinal)
            || TextElements.Count(output) <= 6 || selection.Trim().StartsWith("```", StringComparison.Ordinal)) return output;
        var lines = output.Split('\n').ToList();
        if (lines.Count < 3) return output;
        lines.RemoveAt(0);
        lines.RemoveAt(lines.Count - 1);
        return string.Join("\n", lines).Trim();
    }
}
