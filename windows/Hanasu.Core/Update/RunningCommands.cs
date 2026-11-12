using System.Diagnostics;

namespace Hanasu.Core.Update;

// 要件: REQ-REL-013
// 設計判断: DEC-REL-031
/// <summary>アップデートの前に、このインストールの cli\hanasu.exe で動いているプロセス（MCP のサーバー・実行中のコマンド）を数える</summary>
public static class RunningCommands
{
    /// <param name="Ours">このインストールの hanasu.exe と分かったもの</param>
    /// <param name="Unknown">パスを読めなかった hanasu（管理者として動いているなど。終わらせられないかもしれない）</param>
    public sealed record Count(int Ours, int Unknown)
    {
        public int Total => Ours + Unknown;
    }

    /// <summary>名前が hanasu のプロセスのパス（読めなければ null）を、cliExecutable と比べて数える</summary>
    public static Count Classify(IEnumerable<string?> paths, string cliExecutable)
    {
        var ours = 0;
        var unknown = 0;
        foreach (var path in paths)
        {
            if (path is null) unknown++;
            else if (string.Equals(Path.GetFullPath(path), Path.GetFullPath(cliExecutable), StringComparison.OrdinalIgnoreCase)) ours++;
        }
        return new Count(ours, unknown);
    }

    public static Count Scan(string cliExecutable)
    {
        var paths = new List<string?>();
        foreach (var process in Process.GetProcessesByName("hanasu"))
        {
            using (process)
            {
                try { paths.Add(process.MainModule?.FileName); }
                catch (Exception e) when (e is System.ComponentModel.Win32Exception or InvalidOperationException or NotSupportedException) { paths.Add(null); }
            }
        }
        return Classify(paths, cliExecutable);
    }
}
