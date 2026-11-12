using System.IO;
using System.Runtime.InteropServices;
using Hanasu.Core.Settings;
using Hanasu.Windows.Native;

namespace Hanasu.Windows.Services;

// 要件: REQ-COM-022
/// <summary>Windows に特有の守り（起動の最初に呼ぶもの、入力先の確かめ）。</summary>
internal static class WindowsSecurity
{
    /// <summary>
    /// ウインドウのプロセスが、Hanasu より高い整合性レベル（管理者として実行など）で動いているか。
    /// そういうウインドウには SendInput のキーが届かない（UIPI）が、SendInput は成功を返すので、送る前に確かめる。
    /// 調べられないとき（トークンを開けない＝ほぼ高い権限）も true にする。
    /// </summary>
    // 設計判断: DEC-COM-149
    public static bool IsHigherIntegrity(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero) return false;
        NativeMethods.GetWindowThreadProcessId(hwnd, out var pid);
        if (pid == 0) return false;
        var own = IntegrityOf(NativeMethods.GetCurrentProcess(), closeProcess: false);
        var process = NativeMethods.OpenProcess(NativeMethods.PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
        if (process == IntPtr.Zero) return true;
        var target = IntegrityOf(process, closeProcess: true);
        if (own is null) return false;
        return target is null || target > own;
    }

    private static uint? IntegrityOf(IntPtr process, bool closeProcess)
    {
        var token = IntPtr.Zero;
        var buffer = IntPtr.Zero;
        try
        {
            if (!NativeMethods.OpenProcessToken(process, NativeMethods.TOKEN_QUERY, out token)) return null;
            NativeMethods.GetTokenInformation(token, NativeMethods.TokenIntegrityLevel, IntPtr.Zero, 0, out var length);
            if (length == 0) return null;
            buffer = Marshal.AllocHGlobal((int)length);
            if (!NativeMethods.GetTokenInformation(token, NativeMethods.TokenIntegrityLevel, buffer, length, out _)) return null;
            // TOKEN_MANDATORY_LABEL の先頭は SID_AND_ATTRIBUTES（Sid のポインタ）。整合性レベルは SID の最後のサブオーソリティ
            var sid = Marshal.ReadIntPtr(buffer);
            var count = Marshal.ReadByte(NativeMethods.GetSidSubAuthorityCount(sid));
            if (count == 0) return null;
            return (uint)Marshal.ReadInt32(NativeMethods.GetSidSubAuthority(sid, (uint)(count - 1)));
        }
        finally
        {
            if (buffer != IntPtr.Zero) Marshal.FreeHGlobal(buffer);
            if (token != IntPtr.Zero) NativeMethods.CloseHandle(token);
            if (closeProcess) NativeMethods.CloseHandle(process);
        }
    }
}
