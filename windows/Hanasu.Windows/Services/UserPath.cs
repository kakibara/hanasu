using System.Runtime.InteropServices;
using Hanasu.Core.Command;
using Microsoft.Win32;

namespace Hanasu.Windows.Services;

// 要件: REQ-COM-191
// 設計判断: DEC-COM-199
/// <summary>
/// ユーザーの PATH（HKCU\Environment の Path）に、hanasu の cli フォルダを足す・外す。管理者の権限は要らない。
/// %…% を広げずに読み、値の型（REG_EXPAND_SZ か REG_SZ）は今のまま書く。書いたら WM_SETTINGCHANGE で知らせる
/// </summary>
internal static partial class UserPath
{
    private const string Key = "Environment";
    private const string Name = "Path";

    public static string? Read()
    {
        using var key = Registry.CurrentUser.OpenSubKey(Key);
        return key?.GetValue(Name, null, RegistryValueOptions.DoNotExpandEnvironmentNames) as string;
    }

    public static void Add(string directory) => Write(CommandPath.Add(Read(), directory));

    public static void Remove(string directory) => Write(CommandPath.Remove(Read(), directory));

    private static void Write(string value)
    {
        using (var key = Registry.CurrentUser.CreateSubKey(Key, writable: true))
        {
            var kind = key.GetValueNames().Contains(Name, StringComparer.OrdinalIgnoreCase) ? key.GetValueKind(Name) : RegistryValueKind.ExpandString;
            key.SetValue(Name, value, kind is RegistryValueKind.String or RegistryValueKind.ExpandString ? kind : RegistryValueKind.ExpandString);
        }
        // 新しく起動するターミナル（エクスプローラーが作るもの）が、新しい PATH を読むように知らせる
        SendMessageTimeoutW(new IntPtr(0xFFFF), 0x001A, IntPtr.Zero, "Environment", 0x0002, 5000, out _);
    }

    [LibraryImport("user32.dll", StringMarshalling = StringMarshalling.Utf16, SetLastError = true)]
    private static partial IntPtr SendMessageTimeoutW(IntPtr hWnd, uint msg, IntPtr wParam, string lParam, uint flags, uint timeout, out IntPtr result);
}
