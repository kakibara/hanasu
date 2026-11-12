using Hanasu.Core.Command;
using Hanasu.Core.Settings;
using Microsoft.Win32;

namespace Hanasu.Command;

// 要件: REQ-COM-191, REQ-COM-190
// 設計判断: DEC-COM-199
/// <summary>doctor に出す PATH の状態（ユーザーの PATH は HKCU\Environment の Path。%…% を広げずに読む）と、一時フォルダで動いているか</summary>
internal sealed class WindowsCommandPlatform(string cliDirectory, string executable, AppSettings settings) : ICommandPlatform
{
    public PathStatus PathStatus()
    {
        string? userPath;
        using (var key = Registry.CurrentUser.OpenSubKey("Environment"))
        {
            userPath = key?.GetValue("Path", null, RegistryValueOptions.DoNotExpandEnvironmentNames) as string;
        }
        return CommandPath.Status(userPath, cliDirectory, System.Environment.GetEnvironmentVariable("PATH"),
            settings.CommandPathEntry, File.Exists);
    }

    public bool IsRunningFromTemporaryFolder => CommandPath.IsTemporary(executable, Path.GetTempPath());
}
