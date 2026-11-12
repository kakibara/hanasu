namespace Hanasu.Core.Command;

// 要件: REQ-COM-180, REQ-COM-181, REQ-COM-182, REQ-COM-183
/// <summary>
/// hanasu コマンドの振り分け（Mac 版 HanasuCommand.run の移植）。会議のファイルを書き換えず、アプリの起動時の処理も通らない
/// </summary>
public static class HanasuCommand
{
    /// <summary>引数（実行ファイルの名前を除く）を実行し、終了コードを返す</summary>
    public static async Task<HanasuExit> RunAsync(IReadOnlyList<string> arguments, CommandContext context)
    {
        // 要件: REQ-COM-061（プロンプトの言語は設定の文字起こしの言語）
        Ai.PromptLanguage.UseSettings(context.Settings.LocaleIdentifier);
        try
        {
            if (arguments.Count == 0)
            {
                context.Console.Out(CommandHelp.Full(context));
                return HanasuExit.Ok;
            }
            var command = arguments[0];
            var rest = arguments.Skip(1).ToList();
            switch (command)
            {
                case "help":
                    context.Console.Out((rest.Count > 0 ? CommandHelp.Section(rest[0], context) : null) ?? CommandHelp.Full(context));
                    return HanasuExit.Ok;
                case "--help" or "-h":
                    context.Console.Out(CommandHelp.Full(context));
                    return HanasuExit.Ok;
                case "--version":
                    context.Console.Out("hanasu " + context.Version);
                    return HanasuExit.Ok;
                case "meetings":
                    return await MeetingsCommand.RunMeetingsAsync(rest, context).ConfigureAwait(false);
                case "actions":
                    return MeetingsCommand.Actions(rest, context);
                case "ask":
                    return await AiCommands.AskAsync(rest, context).ConfigureAwait(false);
                case "refine":
                    return await AiCommands.RefineAsync(rest, context).ConfigureAwait(false);
                case "edit":
                    return await AiCommands.EditAsync(rest, context).ConfigureAwait(false);
                case "dict":
                    return AiCommands.Dict(rest, context);
                case "doctor":
                    return DoctorCommand.Run(rest, context);
                case "mcp":
                    return await McpServer.RunAsync(rest, context).ConfigureAwait(false);
                default:
                    throw new CommandException(HanasuExit.Usage, string.Format(Strings.Cmd_UnknownCommand, command), [Strings.Cmd_SeeHelp]);
            }
        }
        catch (CommandException e)
        {
            context.Console.Error(e);
            return e.Exit;
        }
        catch (Exception e) when (e is not OutOfMemoryException)
        {
            context.Console.Err("hanasu: " + e.Message);
            return HanasuExit.Failure;
        }
    }
}
