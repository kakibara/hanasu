using System.Text.Json;
using System.Text.Encodings.Web;

namespace Hanasu.Core.Command;

/// <summary>ヘルプ。オプションの名前とコマンドは訳さず、説明だけを表示の言語にする（Mac 版 HanasuHelp の移植）</summary>
public static class CommandHelp
{
    public static bool WantsHelp(CommandArguments args, string section, CommandContext context)
    {
        if (!args.WantsHelp) return false;
        context.Console.Out(Section(section, context) ?? Full(context));
        return true;
    }

    public static string Full(CommandContext context)
    {
        var lines = new List<string> { Strings.Cmd_HelpTitle, "", Strings.Cmd_HelpUsage };
        lines.AddRange(MeetingsUsage.Concat(ActionsUsage).Concat(AskUsage).Concat(RefineUsage).Concat(EditUsage)
            .Concat(DictUsage).Concat(McpUsage).Concat(DoctorUsage));
        lines.AddRange(new[]
        {
            "  hanasu help [meetings|actions|ask|refine|edit|dict|mcp|doctor]",
            "  hanasu help agent",
            "      " + Strings.Cmd_HelpAgent,
            "  hanasu --version",
            "",
        });
        lines.AddRange(CommonNotes.Concat(AiNotes).Append(Strings.Cmd_NoteEncoding));
        return string.Join("\n", lines);
    }

    public static string? Section(string command, CommandContext context)
    {
        if (command == "agent") return AgentGuide(context.ExecutablePath, context.Device);
        IEnumerable<string> usage;
        IEnumerable<string> notes = CommonNotes;
        switch (command)
        {
            case "meetings": usage = MeetingsUsage; break;
            case "actions": usage = ActionsUsage; break;
            case "ask": usage = AskUsage; notes = CommonNotes.Concat(AiNotes); break;
            case "refine": usage = RefineUsage; notes = AiNotes; break;
            case "edit": usage = EditUsage; notes = AiNotes; break;
            case "dict": usage = DictUsage; notes = []; break;
            case "doctor": usage = DoctorUsage; notes = []; break;
            case "mcp": usage = McpUsage; notes = McpNotes(context.ExecutablePath); break;
            default: return null;
        }
        return string.Join("\n", new[] { Strings.Cmd_HelpUsage }.Concat(usage).Concat(notes));
    }

    private static string Period => Strings.Cmd_PhPeriod;
    private static string Count => Strings.Cmd_PhCount;
    private static string Text => Strings.Cmd_PhText;
    private static string Ai => $"[--ai <AI>] [--model {Strings.Cmd_PhModel}]";

    private static string[] MeetingsUsage =>
    [
        $"  hanasu meetings list [--since {Period}] [--until {Period}] [--limit {Count}] [--json]",
        "      " + Strings.Cmd_HelpList,
        $"  hanasu meetings show {Strings.Cmd_PhMeeting} [--transcript | --notes | --actions | --all] [--json]",
        "      " + Strings.Cmd_HelpShow,
        $"  hanasu meetings search {Strings.Cmd_PhWord}... [--since {Period}] [--until {Period}] [--limit {Count}] [--json]",
        "      " + Strings.Cmd_HelpSearch,
    ];

    private static string[] ActionsUsage =>
    [
        $"  hanasu actions [--since {Period}] [--until {Period}] [--owner {Strings.Cmd_PhName}] [--limit {Count}] [--json]",
        "      " + Strings.Cmd_HelpActions,
    ];

    private static string[] AskUsage =>
    [
        $"  hanasu ask {Strings.Cmd_PhQuestion} [--since {Period}] [--until {Period}] {Ai} [--show-prompt] [--json]",
        "      " + Strings.Cmd_HelpAsk,
    ];

    private static string[] RefineUsage =>
    [
        $"  hanasu refine [{Text}] [--app <exe>] [--style {Strings.Cmd_PhStyle}] [--translate {Strings.Cmd_PhLanguage}] {Ai} [--fallback-raw] [--show-prompt] [--json]",
        "      " + Strings.Cmd_HelpRefine,
    ];

    private static string[] EditUsage =>
    [
        $"  hanasu edit {Strings.Cmd_PhInstruction} [{Text}] {Ai} [--fallback-raw] [--show-prompt] [--json]",
        "      " + Strings.Cmd_HelpEdit,
    ];

    private static string[] DictUsage =>
    [
        $"  hanasu dict apply [{Text}] [--json]",
        "      " + Strings.Cmd_HelpDict,
    ];

    private static string[] McpUsage =>
    [
        $"  hanasu mcp [--meetings-dir {Strings.Cmd_PhFolder}] [--ai <AI>] [--model {Strings.Cmd_PhModel}]",
        "      " + Strings.Cmd_HelpMcp,
    ];

    private static string[] DoctorUsage =>
    [
        "  hanasu doctor [--json]",
        "      " + Strings.Cmd_HelpDoctor,
    ];

    // 要件: REQ-COM-189
    /// <summary>MCP で会議の中身がどこへ渡るかと、登録のしかた</summary>
    public static IReadOnlyList<string> McpNotes(string executable) =>
    [
        Strings.Cmd_McpNoteData,
        Strings.Cmd_McpNoteTools,
        string.Format(Strings.Cmd_McpNoteClaudeCode, CommandInstall.ClaudeCodeCommand(executable)),
        Strings.Cmd_McpNoteDesktop,
    ];

    private static string[] CommonNotes =>
    [
        Strings.Cmd_NoteMeeting,
        Strings.Cmd_NotePeriod,
        Strings.Cmd_NoteJson,
        Strings.Cmd_NoteExit,
    ];

    private static string[] AiNotes =>
    [
        Strings.Cmd_NoteAi,
        Strings.Cmd_NoteAiFailure,
        Strings.Cmd_NoteLocal,
        // 要件: REQ-COM-186（W3）
        Strings.Cmd_NoteHello,
    ];

    // 要件: REQ-COM-193
    // 設計判断: DEC-COM-187, DEC-COM-191
    /// <summary>
    /// MCP を登録できないときに、エージェント（CLAUDE.md など）に貼る説明。英語で固定し、文の枠は Mac 版と共有のファイル。
    /// コマンドは PowerShell の書き方（&amp; "…"）にし、Git Bash と cmd の書き方を添える
    /// </summary>
    public static string AgentGuide(string executable, string device = "this PC")
    {
        var run = $"& \"{executable}\"";
        var lines = SharedText.Lines("agentGuide.lines", device, ("executable", executable), ("run", run))
            .Concat(SharedText.Lines("agentGuide.windowsLines", device, ("executable", executable), ("posixExecutable", CommandInstall.PosixPath(executable))));
        return string.Join("\n", lines);
    }
}

// 要件: REQ-COM-190, REQ-COM-193
// 設計判断: DEC-COM-188
/// <summary>MCP の登録の文（設定画面の「コマンドと MCP」と doctor で同じものを出す）</summary>
public static class CommandInstall
{
    /// <summary>
    /// Claude Code に登録するコマンド。PowerShell（5.1・7）・cmd のどちらでもそのまま動くよう、-- は付けない
    /// （Windows PowerShell 5.1 は外のコマンドに渡す -- を取り除くため。mcp は - で始まらないので要らない）。
    /// --scope user で、どのフォルダの Claude Code からも使える（REQ-COM-194）
    /// </summary>
    public static string ClaudeCodeCommand(string executable) => $"claude mcp add --scope user hanasu \"{executable}\" mcp";

    /// <summary>Claude Desktop の設定（claude_desktop_config.json）の mcpServers に足す形。\ を含むパスもそのまま貼れる JSON</summary>
    public static string ClaudeDesktopJson(string executable)
    {
        var command = JsonSerializer.Serialize(executable, new JsonSerializerOptions { Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping });
        return "{\n  \"mcpServers\": {\n    \"hanasu\": {\n      \"command\": " + command + ",\n      \"args\": [\"mcp\"]\n    }\n  }\n}";
    }

    /// <summary>Git Bash などの POSIX のシェルでの書き方（C:\a b\hanasu.exe → '/c/a b/hanasu.exe'）</summary>
    public static string PosixPath(string executable)
    {
        var path = executable.Replace('\\', '/');
        if (path.Length >= 2 && path[1] == ':') path = "/" + char.ToLowerInvariant(path[0]) + path[2..];
        return "'" + path.Replace("'", "'\\''") + "'";
    }
}
