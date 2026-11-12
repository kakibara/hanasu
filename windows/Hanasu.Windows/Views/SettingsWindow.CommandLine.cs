using System.IO;
using System.Windows;
using System.Windows.Controls;
using Hanasu.Core.Command;
using Hanasu.Windows.Services;

namespace Hanasu.Windows.Views;

// 要件: REQ-COM-190, REQ-COM-191, REQ-COM-193, REQ-COM-194
// 設計判断: DEC-COM-199, DEC-COM-188, DEC-COM-187
/// <summary>
/// 設定の「コマンドと MCP」（W4）。AI アプリにつなぐ（Claude Desktop・ChatGPT（Codex）・Claude Code の設定に hanasu の MCP を足す・外す）、
/// cli\hanasu.exe の絶対パス、ユーザーの PATH に入れる・外す、Claude Code・Claude Desktop への登録の文、エージェントへの説明を出す。
/// cli\hanasu.exe がないときと、一時フォルダ（zip の中など）で動いているときは、つなぐ・PATH・コピーのボタンを使えなくする
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
        connectUsable = usable;
        RefreshCommandPathStatus();
        RefreshConnectRows();
    }

    // ---- AI アプリにつなぐ ----

    // 要件: REQ-COM-194
    // 設計判断: DEC-COM-200, DEC-COM-202, DEC-COM-204, DEC-COM-205
    private readonly AgentApps agentApps = new();
    private IReadOnlyList<AgentConnect.Row> connectRows = [];
    /// <summary>読み込みの番号（最後に始めた読み込みの結果だけを出す）</summary>
    private int connectGeneration;
    /// <summary>書いている・claude を動かしているあいだはボタンを押せなくする</summary>
    private bool connectBusy;
    /// <summary>cli\hanasu.exe があり、一時フォルダで動いていない（「つなぐ…」を押せる）</summary>
    private bool connectUsable;

    /// <summary>行を読み直す（設定ファイルを読み、動いているアプリを見るので UI スレッドの外で）</summary>
    private async void RefreshConnectRows()
    {
        var mine = ++connectGeneration;
        var exe = CommandExecutable;
        IReadOnlyList<AgentConnect.Row> rows;
        try
        {
            rows = await Task.Run(() => AgentConnect.Rows(agentApps, exe));
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or System.Security.SecurityException or InvalidOperationException)
        {
            AppLog.Write($"agent apps: rows not read: {e.Message}");
            return;
        }
        if (mine != connectGeneration) return;
        connectRows = rows;
        RenderConnectRows();
    }

    private void RenderConnectRows()
    {
        ConnectRowsPanel.Children.Clear();
        var note = (Style)FindResource("Note");
        foreach (var row in connectRows)
        {
            var panel = new StackPanel { Margin = new Thickness(0, 6, 0, 6) };
            panel.Children.Add(new TextBlock { Text = ConnectTitle(row), FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap });
            panel.Children.Add(new TextBlock { Text = row.File, Style = note, FontFamily = new System.Windows.Media.FontFamily("Consolas") });
            panel.Children.Add(new TextBlock { Text = ConnectStateText(row), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 3, 0, 0) });
            foreach (var line in ConnectNotes(row)) panel.Children.Add(new TextBlock { Text = line, Style = note });
            var buttons = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 6, 0, 0) };
            var connect = new Button { Content = Strings.Settings_Connect_Connect, IsEnabled = !connectBusy && connectUsable && row.Found };
            connect.Click += (_, _) => OnConnectAgent(row);
            var disconnect = new Button { Content = Strings.Settings_Connect_Disconnect, IsEnabled = !connectBusy && row.State.Removable };
            disconnect.Click += (_, _) => OnDisconnectAgent(row);
            buttons.Children.Add(connect);
            buttons.Children.Add(disconnect);
            panel.Children.Add(buttons);
            ConnectRowsPanel.Children.Add(panel);
        }
    }

    private static string ConnectTitle(AgentConnect.Row row) => row.Target.Kind switch
    {
        AgentConnect.TargetKind.ClaudeDesktop => row.IsDefaultClaude
            ? "Claude Desktop"
            : string.Format(Strings.Settings_Connect_TitleDesktopFolder, Path.GetFileName(row.Target.Directory)),
        AgentConnect.TargetKind.Codex => Strings.Settings_Connect_TitleCodex,
        _ => Strings.Settings_Connect_TitleClaudeCode,
    };

    /// <summary>文の中で呼ぶアプリの名前</summary>
    private static string ConnectAppName(AgentConnect.Row row) => row.Target.Kind switch
    {
        AgentConnect.TargetKind.ClaudeDesktop => "Claude Desktop",
        AgentConnect.TargetKind.Codex => "ChatGPT",
        _ => "Claude Code",
    };

    private static string ConnectStateText(AgentConnect.Row row)
    {
        if (!row.Found) return string.Format(Strings.Settings_Connect_StateNotFound, ConnectAppName(row));
        return row.State.Kind switch
        {
            AgentConnect.StateKind.Connected => Strings.Settings_Connect_StateConnected,
            AgentConnect.StateKind.NotConnected => Strings.Settings_Connect_StateNotConnected,
            AgentConnect.StateKind.Other => Strings.Settings_Connect_StateOther,
            AgentConnect.StateKind.Foreign => string.Format(Strings.Settings_Connect_StateForeign, row.State.Command),
            _ => string.Format(Strings.Settings_Connect_StateUnreadable, ConnectProblemText(row.State.Problem!)),
        };
    }

    private static string ConnectProblemText(AgentConnect.Problem problem) => problem.Kind switch
    {
        AgentConnect.ProblemKind.InvalidJson => Strings.Settings_Connect_ProblemInvalidJson,
        AgentConnect.ProblemKind.UnexpectedShape => Strings.Settings_Connect_ProblemUnexpectedShape,
        AgentConnect.ProblemKind.TomlUnsupported => Strings.Settings_Connect_ProblemTomlUnsupported,
        _ => problem.Detail,
    };

    private static IEnumerable<string> ConnectNotes(AgentConnect.Row row)
    {
        // 書き換えられないときは、手で足す内容（REQ-COM-190 のコピーの欄）を案内する
        if (row.Found && row.State.Kind == AgentConnect.StateKind.Unreadable) yield return Strings.Settings_Connect_NoteManual;
        // ChatGPT のふつうのチャットは、今は手元の MCP のツールを使えない（openai/codex#38162）
        if (row.Target.Kind == AgentConnect.TargetKind.Codex) yield return Strings.Settings_Connect_NoteChatGPT;
        if (row.Target.Kind != AgentConnect.TargetKind.ClaudeCode) yield break;
        if (row.ClaudePath is null) yield return Strings.Settings_Connect_NoteClaudeMissing;
        if (row.ProjectEntry) yield return Strings.Settings_Connect_NoteProjectEntry;
    }

    private void ShowConnectResult(string? text)
    {
        ConnectResultText.Text = text ?? "";
        ConnectResultText.Visibility = text is null ? Visibility.Collapsed : Visibility.Visible;
    }

    private async void OnConnectAgent(AgentConnect.Row row)
    {
        ShowConnectResult(null);
        // 動いているあいだは書かない（DEC-COM-202）。確かめる前に知らせる
        if (row.Running)
        {
            ShowConnectResult(string.Format(Strings.Settings_Connect_Running, ConnectAppName(row)));
            return;
        }
        var title = string.Format(Strings.Settings_Connect_ConfirmTitle, ConnectAppName(row));
        var body = row.Target.Kind == AgentConnect.TargetKind.ClaudeCode && row.ClaudePath is not null
            ? Strings.Settings_Connect_ConfirmCli
            : string.Format(Strings.Settings_Connect_ConfirmFile, Path.GetFileName(row.File) + AgentConnect.BackupSuffix, row.File);
        var overwrite = row.State.Kind == AgentConnect.StateKind.Foreign;
        if (overwrite) body = string.Format(Strings.Settings_Connect_ConfirmForeign, row.State.Command) + "\n\n" + body;
        if (!Confirm(body, title)) return;
        var exe = CommandExecutable;
        AgentConnect.Outcome? outcome = await RunConnect(() => AgentConnect.Connect(row, agentApps, exe, overwrite));
        // 画面を開いたあとで、Hanasu のものでない hanasu が足されていた
        if (outcome.Kind == AgentConnect.OutcomeKind.NeedsOverwrite)
        {
            if (Confirm(string.Format(Strings.Settings_Connect_ConfirmForeign, outcome.Detail), title))
            {
                outcome = await RunConnect(() => AgentConnect.Connect(row, agentApps, exe, overwrite: true));
            }
            else
            {
                outcome = null;
            }
        }
        if (outcome is not null) ShowConnectResult(ConnectOutcomeText(row, outcome, connecting: true));
        RefreshConnectRows();
    }

    private async void OnDisconnectAgent(AgentConnect.Row row)
    {
        ShowConnectResult(null);
        if (row.Running)
        {
            ShowConnectResult(string.Format(Strings.Settings_Connect_Running, ConnectAppName(row)));
            return;
        }
        if (!Confirm(Strings.Settings_Connect_DisconnectBody, string.Format(Strings.Settings_Connect_DisconnectTitle, ConnectAppName(row)))) return;
        var exe = CommandExecutable;
        var outcome = await RunConnect(() => AgentConnect.Disconnect(row, agentApps, exe));
        ShowConnectResult(ConnectOutcomeText(row, outcome, connecting: false));
        RefreshConnectRows();
    }

    private bool Confirm(string body, string title) =>
        MessageBox.Show(this, body, title, MessageBoxButton.OKCancel, MessageBoxImage.Question, MessageBoxResult.Cancel) == MessageBoxResult.OK;

    /// <summary>書く・claude を動かすのは UI スレッドの外で。そのあいだはボタンを押せなくし、登録中であることを出す</summary>
    private async Task<AgentConnect.Outcome> RunConnect(Func<AgentConnect.Outcome> action)
    {
        connectBusy = true;
        ConnectBusyText.Visibility = Visibility.Visible;
        RenderConnectRows();
        try
        {
            return await Task.Run(action);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or System.Security.SecurityException or InvalidOperationException)
        {
            return AgentConnect.Outcome.Failed(e.Message);
        }
        finally
        {
            connectBusy = false;
            ConnectBusyText.Visibility = Visibility.Collapsed;
            RenderConnectRows();
        }
    }

    private static string ConnectOutcomeText(AgentConnect.Row row, AgentConnect.Outcome outcome, bool connecting) => outcome.Kind switch
    {
        AgentConnect.OutcomeKind.Done when !connecting => string.Format(Strings.Settings_Connect_Removed, ConnectAppName(row)),
        AgentConnect.OutcomeKind.Done when row.Target.Kind == AgentConnect.TargetKind.ClaudeCode => Strings.Settings_Connect_DoneCli,
        AgentConnect.OutcomeKind.Done => string.Format(Strings.Settings_Connect_Done, ConnectAppName(row)),
        AgentConnect.OutcomeKind.Unchanged => Strings.Settings_Connect_AlreadyConnected,
        AgentConnect.OutcomeKind.Nothing => Strings.Settings_Connect_NothingToRemove,
        AgentConnect.OutcomeKind.NeedsOverwrite => string.Format(Strings.Settings_Connect_StateForeign, outcome.Detail),
        AgentConnect.OutcomeKind.Running => string.Format(Strings.Settings_Connect_Running, ConnectAppName(row)),
        AgentConnect.OutcomeKind.Unreadable => string.Format(Strings.Settings_Connect_StateUnreadable, ConnectProblemText(outcome.Problem!)) + "\n" + Strings.Settings_Connect_NoteManual,
        AgentConnect.OutcomeKind.TimedOut => Strings.Settings_Connect_TimedOut,
        _ => string.Format(Strings.Settings_Connect_WriteFailed, outcome.Detail),
    };

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
