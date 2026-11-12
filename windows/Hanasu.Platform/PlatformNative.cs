using System.Runtime.InteropServices;

// このアセンブリの P/Invoke は System32 からだけ読む（exe の隣や作業フォルダに置かれた同名の DLL を読まない）
// 設計判断: DEC-COM-148
[assembly: DefaultDllImportSearchPaths(DllImportSearchPath.System32)]

namespace Hanasu.Platform;

/// <summary>Hanasu.Platform が使う Win32 API の宣言（Hanasu.Windows の NativeMethods から、ここで使うものだけを写した）</summary>
internal static partial class PlatformNative
{
    // DLL の探索の場所（SetDefaultDllDirectories）
    public const uint LOAD_LIBRARY_SEARCH_APPLICATION_DIR = 0x00000200;
    public const uint LOAD_LIBRARY_SEARCH_USER_DIRS = 0x00000400;
    public const uint LOAD_LIBRARY_SEARCH_SYSTEM32 = 0x00000800;

    [LibraryImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static partial bool SetDefaultDllDirectories(uint directoryFlags);

    [LibraryImport("kernel32.dll", SetLastError = true, StringMarshalling = StringMarshalling.Utf16)]
    public static partial IntPtr AddDllDirectory(string newDirectory);

    [LibraryImport("kernel32.dll", SetLastError = true, StringMarshalling = StringMarshalling.Utf16)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static partial bool SetDllDirectoryW(string lpPathName);

    [LibraryImport("user32.dll", StringMarshalling = StringMarshalling.Utf16)]
    public static partial IntPtr FindWindowW(string? lpClassName, string? lpWindowName);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static partial bool SetForegroundWindow(IntPtr hWnd);

    [LibraryImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static partial bool CloseHandle(IntPtr handle);
}
