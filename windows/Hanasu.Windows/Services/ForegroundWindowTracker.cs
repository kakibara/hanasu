using System.Diagnostics;
using System.IO;
using System.Text;
using Hanasu.Windows.Native;

namespace Hanasu.Windows.Services;

/// <summary>
/// 前面のウインドウを見張り、Hanasu とタスクバー以外で最後に前面にあったウインドウを覚えておく。
/// タスクトレイのメニューから音声入力を始めると前面がタスクバーに移るので、そのウインドウを前面に戻してから録音を始める。
/// </summary>
internal sealed class ForegroundWindowTracker : IDisposable
{
    private static readonly HashSet<string> ShellClasses = new(StringComparer.OrdinalIgnoreCase)
    {
        "Shell_TrayWnd", "Shell_SecondaryTrayWnd", "NotifyIconOverflowWindow", "TopLevelWindowForOverflowXamlIsland",
        "Windows.UI.Core.CoreWindow", "XamlExplorerHostIslandWindow",
    };

    private readonly NativeMethods.WinEventDelegate callback;
    private readonly IntPtr hook;
    private readonly uint ownProcessId = (uint)Environment.ProcessId;

    public IntPtr LastExternalWindow { get; private set; }

    public ForegroundWindowTracker()
    {
        // デリゲートが GC に回収されないよう、フィールドで持つ
        callback = OnForegroundChanged;
        hook = NativeMethods.SetWinEventHook(NativeMethods.EVENT_SYSTEM_FOREGROUND, NativeMethods.EVENT_SYSTEM_FOREGROUND,
            IntPtr.Zero, callback, 0, 0, NativeMethods.WINEVENT_OUTOFCONTEXT);
        Remember(NativeMethods.GetForegroundWindow());
    }

    /// <summary>覚えているウインドウを前面に戻す（Hanasu が前面のときだけ許される）</summary>
    public void RestoreLastExternalWindow()
    {
        if (LastExternalWindow != IntPtr.Zero && NativeMethods.IsWindow(LastExternalWindow))
        {
            NativeMethods.SetForegroundWindow(LastExternalWindow);
        }
    }

    /// <summary>今の前面ウインドウのアプリ名（入力先として Gemini に伝える）。Hanasu かタスクバーなら、最後に前面だったアプリ</summary>
    public string? ForegroundAppName()
    {
        var hwnd = NativeMethods.GetForegroundWindow();
        if (!IsExternal(hwnd)) hwnd = LastExternalWindow;
        return hwnd == IntPtr.Zero ? null : AppNameOf(hwnd);
    }

    // 要件: REQ-DIC-020
    // 設計判断: DEC-DIC-216
    /// <summary>
    /// 今の前面ウインドウの exe の名前（小文字。"slack.exe" など）。ForegroundAppName と同じウインドウの選び方。
    /// ストアアプリ（ApplicationFrameHost.exe）のときもそのまま返す（引かないのは Core の AppStyleLookup.Find）
    /// </summary>
    public string? ForegroundAppExe()
    {
        var hwnd = NativeMethods.GetForegroundWindow();
        if (!IsExternal(hwnd)) hwnd = LastExternalWindow;
        return hwnd == IntPtr.Zero ? null : ExeOf(hwnd);
    }

    /// <summary>ウインドウのプロセスの exe のファイル名（小文字）。取れなければ null</summary>
    internal static string? ExeOf(IntPtr hwnd)
    {
        NativeMethods.GetWindowThreadProcessId(hwnd, out var pid);
        if (pid == 0) return null;
        if (ProcessPath(pid) is { } path) return Path.GetFileName(path).ToLowerInvariant();
        try
        {
            using var process = Process.GetProcessById((int)pid);
            return (process.ProcessName + ".exe").ToLowerInvariant();
        }
        catch (ArgumentException)
        {
            return null;
        }
    }

    private void OnForegroundChanged(IntPtr hWinEventHook, uint eventType, IntPtr hwnd, int idObject, int idChild, uint thread, uint time) =>
        Remember(hwnd);

    private void Remember(IntPtr hwnd)
    {
        if (IsExternal(hwnd)) LastExternalWindow = hwnd;
    }

    private bool IsExternal(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero) return false;
        NativeMethods.GetWindowThreadProcessId(hwnd, out var pid);
        if (pid == ownProcessId) return false;
        var className = new StringBuilder(256);
        NativeMethods.GetClassName(hwnd, className, className.Capacity);
        return !ShellClasses.Contains(className.ToString());
    }

    /// <summary>実行ファイルの説明（「Slack」「Google Chrome」など）。取れなければプロセス名</summary>
    internal static string? AppNameOf(IntPtr hwnd)
    {
        NativeMethods.GetWindowThreadProcessId(hwnd, out var pid);
        if (pid == 0) return null;
        var path = ProcessPath(pid);
        // ストアアプリは ApplicationFrameHost の中で動くので、ウインドウのタイトルを使う
        if (path is not null && Path.GetFileName(path).Equals("ApplicationFrameHost.exe", StringComparison.OrdinalIgnoreCase))
        {
            var title = new StringBuilder(256);
            NativeMethods.GetWindowText(hwnd, title, title.Capacity);
            return title.Length > 0 ? title.ToString() : null;
        }
        if (path is not null)
        {
            try
            {
                var description = FileVersionInfo.GetVersionInfo(path).FileDescription?.Trim();
                if (!string.IsNullOrEmpty(description)) return description;
            }
            catch (FileNotFoundException) { }
            return Path.GetFileNameWithoutExtension(path);
        }
        try
        {
            using var process = Process.GetProcessById((int)pid);
            return process.ProcessName;
        }
        catch (ArgumentException)
        {
            return null;
        }
    }

    /// <summary>管理者として動いているアプリでも読めるよう、PROCESS_QUERY_LIMITED_INFORMATION で開く</summary>
    internal static string? ProcessPath(uint pid)
    {
        var handle = NativeMethods.OpenProcess(NativeMethods.PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
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

    public void Dispose()
    {
        if (hook != IntPtr.Zero) NativeMethods.UnhookWinEvent(hook);
    }
}
