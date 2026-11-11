using System.Text.Json.Nodes;
using Hanasu.Core.Ai;
using Hanasu.Core.LocalLlm;
using Hanasu.Core.Settings;

namespace Hanasu.Core.Command;

// 要件: REQ-COM-186, REQ-COM-190, REQ-COM-191
// 設計判断: DEC-COM-185, DEC-COM-197
/// <summary>
/// hanasu doctor。使う AI と認証情報（値は出さない）・会議のフォルダ・PATH・MCP の登録のしかた。Mac 版 HanasuDoctorCommand の移植。
/// Windows の JSON は、管理者のポリシー（policies）がなく、install の形と credentials.*.source の値が Mac と違う（DEC-COM-197）
/// </summary>
public static class DoctorCommand
{
    public static HanasuExit Run(IReadOnlyList<string> arguments, CommandContext context)
    {
        var args = CommandArguments.Parse(arguments, ["--json", "--help", "-h"], MeetingsCommand.CommonOptions);
        if (CommandHelp.WantsHelp(args, "doctor", context)) return HanasuExit.Ok;
        var settings = context.Settings;
        var directory = MeetingsCommand.MeetingsDirectory(args, context);
        var (folderStatus, folderProblem) = FolderStatus(directory);
        var dictation = CommandAi.Choice(null, null, CommandAiUse.Dictation, settings);
        var meeting = CommandAi.Choice(null, null, CommandAiUse.Meeting, settings);
        var gemini = CommandAi.CredentialStatusOf(TextAiProvider.Gemini, context, read: true);
        var claude = CommandAi.CredentialStatusOf(TextAiProvider.Claude, context, read: true);
        var server = context.LocalServer ?? LocalLlmServer.Shared;
        var downloaded = LocalLlmModel.All.Where(server.IsDownloaded).Select(m => m.Id).ToList();
        var otherServer = context.OtherLocalServerRunning();
        var path = context.Platform?.PathStatus();
        var temporary = context.Platform?.IsRunningFromTemporaryFolder == true;

        if (args.Json)
        {
            static JsonObject Credential(CredentialStatus status) => new()
            {
                ["configured"] = status.Source is not null,
                ["source"] = status.Source,
                ["readable"] = status.Source is null ? null : status.Problem is null,
                ["problem"] = status.Problem,
            };
            static JsonObject Choice(AiChoice choice) => new() { ["provider"] = choice.ProviderName, ["model"] = choice.Model };
            var entries = new JsonArray();
            if (path?.Current is { } current) entries.Add(new JsonObject { ["path"] = current, ["state"] = "current" });
            foreach (var other in path?.Others ?? []) entries.Add(new JsonObject { ["path"] = other, ["state"] = "otherHanasu" });
            context.Console.Json(new JsonObject
            {
                ["version"] = context.Version,
                ["executable"] = context.ExecutablePath,
                ["meetingsDirectory"] = new JsonObject { ["path"] = directory, ["status"] = folderStatus, ["problem"] = folderProblem },
                ["ai"] = new JsonObject
                {
                    ["dictation"] = Choice(dictation),
                    ["meeting"] = Choice(meeting),
                    ["askPurpose"] = "meeting",
                },
                ["credentials"] = new JsonObject
                {
                    ["gemini"] = Credential(gemini),
                    ["claude"] = Credential(claude),
                    ["local"] = new JsonObject
                    {
                        ["downloadedModels"] = new JsonArray(downloaded.Select(id => (JsonNode)id).ToArray()),
                        ["otherProcessServerRunning"] = otherServer,
                    },
                    ["apple"] = new JsonObject { ["available"] = false, ["reason"] = Strings.Cmd_AppleUnavailable },
                },
                ["install"] = new JsonObject
                {
                    ["cliPath"] = context.ExecutablePath,
                    ["temporaryFolder"] = temporary,
                    ["onPath"] = path?.OnProcessPath ?? false,
                    ["pathEntries"] = entries,
                },
                ["mcp"] = new JsonObject
                {
                    ["command"] = context.ExecutablePath,
                    ["args"] = new JsonArray("mcp"),
                    ["claudeCode"] = CommandInstall.ClaudeCodeCommand(context.ExecutablePath),
                    ["claudeDesktop"] = JsonNode.Parse(CommandInstall.ClaudeDesktopJson(context.ExecutablePath)),
                },
            });
            return HanasuExit.Ok;
        }

        string CredentialLine(CredentialStatus status) =>
            status.Label is null ? Strings.Cmd_NotSet
            : status.Problem is { } problem ? string.Format(Strings.Cmd_CredentialUnreadable, status.Label, problem)
            : status.Source == "windowsHello" ? status.Label
            : string.Format(Strings.Cmd_CredentialReadable, status.Label);
        var folderLine = folderStatus switch
        {
            "readable" => string.Format(Strings.Cmd_CredentialReadable, directory),
            "missing" => string.Format(Strings.Cmd_FolderMissing, directory),
            _ => string.Format(Strings.Cmd_CredentialUnreadable, directory, folderProblem ?? ""),
        };
        var lines = new List<string> { $"hanasu {context.Version}", string.Format(Strings.Cmd_Executable, context.ExecutablePath) };
        // 要件: REQ-COM-190（W4）
        if (temporary) lines.Add("  " + Strings.Cmd_TemporaryFolder);
        // 要件: REQ-COM-191
        if (path is not null)
        {
            if (path.Current is null && path.Others.Count == 0) lines.Add(Strings.Cmd_PathNotOn);
            if (path.Current is { } current)
            {
                var line = string.Format(Strings.Cmd_PathOn, current);
                if (!path.OnProcessPath) line += " " + Strings.Cmd_NotOnShellPath;
                lines.Add(line);
            }
            lines.AddRange(path.Others.Select(o => string.Format(Strings.Cmd_PathOther, o)));
        }
        lines.Add(string.Format(Strings.Cmd_MeetingsFolder, folderLine));
        lines.Add(Strings.Cmd_AiHeading);
        lines.Add("  " + string.Format(Strings.Cmd_Pair, Strings.Cmd_PurposeDictation, "refine, edit") + ": "
            + string.Format(Strings.Cmd_Pair, TextAiFactory.NameOf(dictation.Provider), dictation.Model));
        lines.Add("  " + string.Format(Strings.Cmd_Pair, Strings.Cmd_PurposeMeeting, "ask") + ": "
            + string.Format(Strings.Cmd_Pair, TextAiFactory.NameOf(meeting.Provider), meeting.Model));
        lines.Add(Strings.Cmd_CredentialsHeading);
        lines.Add("  Gemini: " + CredentialLine(gemini));
        lines.Add("  Claude: " + CredentialLine(claude));
        lines.Add("  " + string.Format(Strings.Cmd_LocalModels, downloaded.Count == 0 ? Strings.Cmd_NoLocalModels : string.Join(" / ", downloaded)));
        if (otherServer) lines.Add("  " + Strings.Cmd_LocalInUse);
        // 要件: REQ-COM-189
        lines.Add("MCP:");
        lines.AddRange(CommandHelp.McpNotes(context.ExecutablePath).Select(l => "  " + l));
        lines.Add("  " + Strings.Cmd_DesktopConfig);
        lines.AddRange(CommandInstall.ClaudeDesktopJson(context.ExecutablePath).Split('\n').Select(l => "    " + l));
        context.Console.Out(lines);
        return HanasuExit.Ok;
    }

    /// <summary>会議のフォルダを読めるか（中身は数えない）。readable・missing・unreadable</summary>
    public static (string Status, string? Problem) FolderStatus(string directory)
    {
        if (!Directory.Exists(directory)) return ("missing", null);
        try
        {
            using var entries = Directory.EnumerateFileSystemEntries(directory).GetEnumerator();
            entries.MoveNext();
            return ("readable", null);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            return ("unreadable", e.Message);
        }
    }
}
