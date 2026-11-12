using System.Diagnostics;
using System.Text.Json;

namespace Hanasu.Core.LocalLlm;

// 要件: REQ-COM-187
// 設計判断: DEC-COM-184
/// <summary>
/// llama-server を起動したプロセスごとの記録（%LOCALAPPDATA%\Hanasu\llm-server-&lt;持ち主の pid&gt;.json）。Mac 版の server-&lt;pid&gt;.pid と同じ考え。
/// hanasu は、ほかの生きている持ち主のサーバーが動いていれば、自分のサーバーを起動しない（モデルを二重に読み込まない）
/// </summary>
public static class LocalLlmServerRecords
{
    public sealed record Record(string File, int ServerPid, string Executable, int Owner);

    public static string Directory { get; set; } = Settings.HanasuPaths.LocalDataDirectory;

    private static string FileFor(int owner) => Path.Combine(Directory, $"llm-server-{owner}.json");

    public static void Write(int serverPid, string executable)
    {
        try
        {
            System.IO.Directory.CreateDirectory(Directory);
            var owner = Environment.ProcessId;
            File.WriteAllText(FileFor(owner), JsonSerializer.Serialize(new { serverPid, executable, owner }));
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
    }

    public static void Remove()
    {
        try { File.Delete(FileFor(Environment.ProcessId)); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
    }

    public static IReadOnlyList<Record> Records()
    {
        if (!System.IO.Directory.Exists(Directory)) return Array.Empty<Record>();
        var result = new List<Record>();
        foreach (var file in System.IO.Directory.GetFiles(Directory, "llm-server-*.json"))
        {
            try
            {
                using var json = JsonDocument.Parse(IO.SharedFile.ReadAllText(file));
                var root = json.RootElement;
                result.Add(new Record(file, root.GetProperty("serverPid").GetInt32(), root.GetProperty("executable").GetString() ?? "",
                    root.GetProperty("owner").GetInt32()));
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException or KeyNotFoundException or InvalidOperationException) { }
        }
        return result;
    }

    /// <summary>ほかのプロセス（アプリや別の hanasu）が起動したサーバーが動いているか</summary>
    public static bool OtherProcessServerRunning() =>
        Records().Any(r => r.Owner != Environment.ProcessId && IsAlive(r.Owner, null) && IsAlive(r.ServerPid, r.Executable));

    /// <summary>pid のプロセスが動いているか。executable があれば、その実行ファイルとして動いているかも見る（pid は使い回されるので）</summary>
    public static bool IsAlive(int pid, string? executable)
    {
        try
        {
            using var process = Process.GetProcessById(pid);
            if (process.HasExited) return false;
            if (executable is null) return true;
            var path = process.MainModule?.FileName;
            return path is null || string.Equals(Path.GetFullPath(path), Path.GetFullPath(executable), StringComparison.OrdinalIgnoreCase);
        }
        catch (ArgumentException) { return false; }
        catch (Exception e) when (e is InvalidOperationException or System.ComponentModel.Win32Exception or NotSupportedException)
        {
            // 管理者として動いているなど、パスを読めないときは動いているとみなす（二重に読み込むよりよい）
            return true;
        }
    }
}
