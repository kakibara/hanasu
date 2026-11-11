using System.IO;
using System.Windows;
using System.Windows.Controls;
using Hanasu.Core.Command;
using Hanasu.Windows.Services;

namespace Hanasu.Windows.Views;

// 要件: REQ-COM-190, REQ-COM-191, REQ-COM-193
// 設計判断: DEC-COM-199, DEC-COM-188, DEC-COM-187
/// <summary>
/// 設定の「コマンドと MCP」（W4）。cli\hanasu.exe の絶対パス、ユーザーの PATH に入れる・外す、Claude Code・Claude Desktop への登録の文、
/// エージェントへの説明を出す。cli\hanasu.exe がないときと、一時フォルダ（zip の中など）で動いているときは、PATH とコピーのボタンを使えなくする
/// </summary>
public partial class SettingsWindow
{
    private string CommandDirectory => Path.Combine(Path.TrimEndingDirectorySeparator(AppContext.BaseDirectory), "cli");
    private string CommandExecutable => Path.Combine(CommandDirectory, "hanasu.exe");

    private void LoadCommandLineTab()
    {
        var exe = CommandExecutable;
        CommandExecutableBox.Text = exe;
        CommandClaudeCodeBox.Text = CommandInstall.ClaudeCodeCommand(exe);
        CommandDesktopBox.Text = CommandInstall.ClaudeDesktopJson(exe);
        CommandGuideBox.Text = CommandHelp.AgentGuide(exe);
        string? warning = null;
        if (CommandPath.IsTemporary(exe, Path.GetTempPath())) warning = Strings.Settings_Cmd_Temporary;
        else if (!File.Exists(exe)) warning = Strings.Settings_Cmd_Missing;
        CommandWarning.Text = warning ?? "";
        CommandWarning.Visibility = warning is null ? Visibility.Collapsed : Visibility.Visible;
        var usable = warning is null;
        foreach (var button in new[] { CommandCopyExecutable, CommandCopyClaudeCode, CommandCopyDesktop, CommandCopyGuide, CommandPathAddButton })
        {
            button.IsEnabled = usable;
        }
        RefreshCommandPathStatus();
    }

    private void RefreshCommandPathStatus()
    {
        PathStatus status;
        try
        {
            status = CommandPath.Status(UserPath.Read(), CommandDirectory, Environment.GetEnvironmentVariable("PATH"),
                settings.Current.CommandPathEntry, File.Exists);
        }
        catch (Exception e) when (e is System.Security.SecurityException or UnauthorizedAccessException or IOException)
        {
            CommandPathStatus.Text = e.Message;
            return;
        }
        var lines = new List<string> { status.Current is { } current ? string.Format(Strings.Settings_Cmd_OnPath, current) : Strings.Settings_Cmd_NotOnPath };
        lines.AddRange(status.Others.Select(o => string.Format(Strings.Settings_Cmd_OtherHanasu, o)));
        CommandPathStatus.Text = string.Join("\n", lines);
        // 外すのは、cli\hanasu.exe がないときもできるようにする（前の場所の項目を消すため）
        CommandPathRemoveButton.IsEnabled = status.Current is not null || status.Others.Count > 0;
    }

    private void OnCommandPathAdd(object sender, RoutedEventArgs e)
    {
        try
        {
            var status = CommandPath.Status(UserPath.Read(), CommandDirectory, null, settings.Current.CommandPathEntry, File.Exists);
            // 別の場所の Hanasu の項目は、入れ直すときに外す（新しい場所だけにする）
            foreach (var other in status.Others) UserPath.Remove(other);
            UserPath.Add(CommandDirectory);
            var error = settings.Update(s => s.CommandPathEntry = CommandDirectory);
            if (error is not null) AppLog.Write($"command path not recorded: {error.Message}");
            CommandPathResult.Text = Strings.Settings_Cmd_Added;
        }
        catch (Exception ex) when (ex is System.Security.SecurityException or UnauthorizedAccessException or IOException)
        {
            CommandPathResult.Text = string.Format(Strings.Settings_Cmd_AddFailed, ex.Message);
        }
        RefreshCommandPathStatus();
    }

    private void OnCommandPathRemove(object sender, RoutedEventArgs e)
    {
        try
        {
            var status = CommandPath.Status(UserPath.Read(), CommandDirectory, null, settings.Current.CommandPathEntry, File.Exists);
            if (status.Current is not null) UserPath.Remove(CommandDirectory);
            foreach (var other in status.Others) UserPath.Remove(other);
            var error = settings.Update(s => s.CommandPathEntry = null);
            if (error is not null) AppLog.Write($"command path not recorded: {error.Message}");
            CommandPathResult.Text = Strings.Settings_Cmd_Removed;
        }
        catch (Exception ex) when (ex is System.Security.SecurityException or UnauthorizedAccessException or IOException)
        {
            CommandPathResult.Text = string.Format(Strings.Settings_Cmd_RemoveFailed, ex.Message);
        }
        RefreshCommandPathStatus();
    }

    private void OnCopyCommandText(object sender, RoutedEventArgs e)
    {
        if (sender is not Button button) return;
        var text = button.Tag switch
        {
            "claudeCode" => CommandClaudeCodeBox.Text,
            "claudeDesktop" => CommandDesktopBox.Text,
            "agentGuide" => CommandGuideBox.Text,
            _ => CommandExecutableBox.Text,
        };
        try
        {
            Clipboard.SetText(text);
            var original = button.Content;
            button.Content = Strings.Settings_Cmd_Copied;
            var timer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(1.5) };
            timer.Tick += (_, _) =>
            {
                timer.Stop();
                button.Content = original;
            };
            timer.Start();
        }
        catch (System.Runtime.InteropServices.COMException ex)
        {
            AppLog.Write($"copy failed: {ex.Message}");
        }
    }

    private void OnToggleAgentGuide(object sender, RoutedEventArgs e)
    {
        var show = CommandGuideBox.Visibility != Visibility.Visible;
        CommandGuideBox.Visibility = show ? Visibility.Visible : Visibility.Collapsed;
        CommandGuideToggle.Content = show ? Strings.Settings_Cmd_HideGuide : Strings.Settings_Cmd_ShowGuide;
    }
}
