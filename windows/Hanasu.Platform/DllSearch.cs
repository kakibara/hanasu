using System.Runtime.InteropServices;

namespace Hanasu.Platform;

// 要件: REQ-COM-022
/// <summary>起動の最初に呼ぶ守り（アプリと hanasu コマンドの両方）。</summary>
public static class DllSearch
{
    /// <summary>
    /// DLL を探す場所を、exe のフォルダ・System32・AddDllDirectory で足したフォルダに絞る（作業フォルダと PATH を外す）。
    /// Whisper のネイティブライブラリ（runtimes/win-*/）はそのフォルダを足しておく（依存の ggml-*.dll をそこから読むため）。
    /// exe が起動するときに読む DLL（静的なインポート）には効かない（起動したあとの LoadLibrary に効く）。
    /// </summary>
    // 設計判断: DEC-COM-148
    public static void Harden()
    {
        try
        {
            // SetDllDirectory("") は、作業フォルダを探索から外す（古い Windows でも効く）
            PlatformNative.SetDllDirectoryW("");
            if (!PlatformNative.SetDefaultDllDirectories(PlatformNative.LOAD_LIBRARY_SEARCH_APPLICATION_DIR
                    | PlatformNative.LOAD_LIBRARY_SEARCH_SYSTEM32 | PlatformNative.LOAD_LIBRARY_SEARCH_USER_DIRS))
            {
                AppLog.Write($"SetDefaultDllDirectories failed: {Marshal.GetLastWin32Error()}");
            }
            var runtimes = Path.Combine(AppContext.BaseDirectory, "runtimes", RuntimeInformation.ProcessArchitecture == Architecture.Arm64 ? "win-arm64" : "win-x64");
            if (Directory.Exists(runtimes) && PlatformNative.AddDllDirectory(runtimes) == IntPtr.Zero)
            {
                AppLog.Write($"AddDllDirectory failed: {Marshal.GetLastWin32Error()}");
            }
        }
        catch (Exception e) when (e is EntryPointNotFoundException or DllNotFoundException)
        {
            AppLog.Write($"dll search hardening unavailable: {e.GetType().Name}");
        }
    }
}
