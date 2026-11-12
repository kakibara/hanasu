using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Management;
using System.Runtime.InteropServices;
using System.Text;
using Hanasu.Core.Command;
using Hanasu.Windows.Native;

namespace Hanasu.Windows.Services;

// 要件: REQ-COM-194
// 設計判断: DEC-COM-202, DEC-COM-204
/// <summary>
/// 「AI アプリにつなぐ」が見る、この PC の環境。動いている Claude Desktop（とその起動の引数）・ChatGPT（Codex）のアプリ・Claude Code と、
/// claude コマンドの場所と動かし方。決まり（引数の読み分け・実行ファイルの見分け）は Core の AgentConnect にあり、ここはプロセスを読むだけ
/// </summary>
internal sealed class AgentApps : IAgentEnvironment
{
    public string Home { get; } = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
    public string AppData { get; } = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
    public string LocalAppData { get; } = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);

    /// <summary>
    /// 動いている Claude Desktop の起動の引数。Claude.exe のうち、実行ファイルが AnthropicClaude か WindowsApps\Claude_ の下にあるもの
    /// （名前だけでは Claude Code の claude.exe と見分けられない）。Electron の子プロセス（--type=…）は見ない。引数を読めなければ null
    /// </summary>
    public IReadOnlyList<IReadOnlyList<string>?> ClaudeDesktopArguments()
    {
        var result = new List<IReadOnlyList<string>?>();
        var processes = ClaudeProcesses();
        if (processes.Count == 0) return result;
        var commandLines = CommandLines("claude.exe");
        foreach (var (id, path) in processes)
        {
            string? commandLine = null;
            commandLines?.TryGetValue(id, out commandLine);
            var arguments = commandLine is null ? null : AgentConnect.WindowsCommandLine.Split(commandLine);
            // 実行ファイルのパスを読めなければ、引数の先頭で見分ける。どちらも読めなければ、Claude Desktop かもしれないとする
            var executable = path ?? arguments?.FirstOrDefault();
            if (executable is not null && !AgentConnect.IsClaudeDesktopExecutable(executable)) continue;
            if (arguments is null)
            {
                result.Add(null);
                continue;
            }
            if (AgentConnect.IsElectronChild(arguments)) continue;
            result.Add(arguments);
        }
        return result;
    }

    /// <summary>ChatGPT（Codex）のアプリ（実行ファイルが WindowsApps\OpenAI. の下にあるもの）が動いているか</summary>
    public bool IsChatGPTRunning()
    {
        foreach (var process in SafeProcesses(Process.GetProcesses))
        {
            using (process)
            {
                if (AgentConnect.IsChatGPTExecutable(ProcessPath(process.Id))) return true;
            }
        }
        return false;
    }

    /// <summary>Claude Code（claude.exe のうち Claude Desktop でないもの）が動いているか</summary>
    public bool IsClaudeCodeRunning() =>
        ClaudeProcesses().Any(p => !AgentConnect.IsClaudeDesktopExecutable(p.Path));

    // 設計判断: DEC-COM-204
    /// <summary>
    /// claude を探す。%USERPROFILE%\.local\bin\claude.exe、Claude Desktop に入っている Claude Code（いちばん新しい版）、
    /// npm の %APPDATA%\npm\claude.cmd（cmd で動かせるパスのときだけ）、なければ where.exe claude（5 秒まで）
    /// </summary>
    public string? FindClaude()
    {
        var local = Path.Combine(Home, ".local", "bin", "claude.exe");
        if (File.Exists(local)) return local;
        foreach (var claudeDirectory in new[] { Path.Combine(AppData, "Claude"), AgentConnect.StoreClaudeDirectory(LocalAppData) })
        {
            if (claudeDirectory is not null && AgentConnect.ClaudeCli.Bundled(Path.Combine(claudeDirectory, "claude-code")) is { } bundled) return bundled;
        }
        var npm = Path.Combine(AppData, "npm", "claude.cmd");
        if (File.Exists(npm) && AgentConnect.ClaudeCli.IsSafeCmdPath(npm)) return npm;
        var where = AgentConnect.RunProcess(new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "where.exe")) { ArgumentList = { "claude" } },
            TimeSpan.FromSeconds(5));
        if (where.TimedOut || where.Status != 0) return null;
        return where.Stdout.Split('\n', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries)
            .FirstOrDefault(line => File.Exists(line) && (line.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)
                || (line.EndsWith(".cmd", StringComparison.OrdinalIgnoreCase) && AgentConnect.ClaudeCli.IsSafeCmdPath(line))));
    }

    /// <summary>claude を動かす（バックグラウンドで呼ぶ）。.exe は直接、.cmd は cmd /c で。30 秒で打ち切る</summary>
    public AgentProcessOutput RunClaude(string claude, IReadOnlyList<string> arguments)
    {
        ProcessStartInfo info;
        if (claude.EndsWith(".cmd", StringComparison.OrdinalIgnoreCase) || claude.EndsWith(".bat", StringComparison.OrdinalIgnoreCase))
        {
            if (AgentConnect.WindowsCommandLine.CmdArguments(claude, arguments) is not { } commandLine)
            {
                return new AgentProcessOutput(-1, "", claude);
            }
            info = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "cmd.exe"), commandLine);
        }
        else
        {
            info = new ProcessStartInfo(claude);
            foreach (var argument in arguments) info.ArgumentList.Add(argument);
        }
        // どのフォルダで動かしても --scope user の登録は同じ。アプリのフォルダをプロジェクトと見なされないよう、ホームで動かす
        info.WorkingDirectory = Home;
        return AgentConnect.RunProcess(info, AgentConnect.ClaudeCli.Timeout);
    }

    // ---- プロセス ----

    /// <summary>名前が claude（Windows は大文字・小文字を区別しないので Claude.exe も）のプロセスの番号と、実行ファイルのパス（読めなければ null）</summary>
    private static List<(int Id, string? Path)> ClaudeProcesses()
    {
        var result = new List<(int, string?)>();
        foreach (var process in SafeProcesses(() => Process.GetProcessesByName("claude")))
        {
            using (process) result.Add((process.Id, ProcessPath(process.Id)));
        }
        return result;
    }

    private static Process[] SafeProcesses(Func<Process[]> list)
    {
        try
        {
            return list();
        }
        catch (Exception e) when (e is InvalidOperationException or Win32Exception or NotSupportedException)
        {
            AppLog.Write($"agent apps: processes not listed: {e.Message}");
            return [];
        }
    }

    /// <summary>その名前のプロセスの起動のコマンドライン（WMI の Win32_Process.CommandLine）。WMI を使えなければ null</summary>
    private static Dictionary<int, string?>? CommandLines(string name)
    {
        try
        {
            var query = new SelectQuery("Win32_Process", $"Name = '{name.Replace("'", "''")}'", ["ProcessId", "CommandLine"]);
            using var searcher = new ManagementObjectSearcher(query) { Options = { Timeout = TimeSpan.FromSeconds(5) } };
            var result = new Dictionary<int, string?>();
            using var items = searcher.Get();
            foreach (var item in items)
            {
                using (item)
                {
                    result[Convert.ToInt32(item["ProcessId"], System.Globalization.CultureInfo.InvariantCulture)] = item["CommandLine"] as string;
                }
            }
            return result;
        }
        catch (Exception e) when (e is ManagementException or COMException or UnauthorizedAccessException or InvalidCastException or FormatException or OverflowException)
        {
            AppLog.Write($"agent apps: command lines not read: {e.Message}");
            return null;
        }
    }

    /// <summary>管理者として動いているプロセスでも読めるよう、PROCESS_QUERY_LIMITED_INFORMATION で開く</summary>
    private static string? ProcessPath(int id)
    {
        var handle = NativeMethods.OpenProcess(NativeMethods.PROCESS_QUERY_LIMITED_INFORMATION, false, (uint)id);
        if (handle == IntPtr.Zero) return null;
        try
        {
            var buffer = new StringBuilder(1024);
            var size = (uint)buffer.Capacity;
            return NativeMethods.QueryFullProcessImageName(handle, 0, buffer, ref size) ? buffer.ToString() : null;
        }
        finally
        {
            NativeMethods.CloseHandle(handle);
        }
    }
}
