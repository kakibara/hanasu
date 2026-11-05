using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using Hanasu.Windows.Native;

namespace Hanasu.Windows.Views;

/// <summary>ウインドウの大きさと最初の位置を、マウスのある画面の作業領域に合わせる</summary>
// 設計判断: DEC-COM-017
internal static class WindowFit
{
    /// <summary>
    /// 設定・会議ノート・履歴のウインドウを、マウスのある画面の作業領域に収めて、その中央に出す。
    /// XAML の <c>WindowStartupLocation="CenterScreen"</c> はメインの画面に出すので、2 台目の画面で使っていても
    /// メインの画面に開いてしまう。HUD（<see cref="HudWindow"/> の PlaceAtBottom）と同じく、マウスのある画面に出す。
    /// 画面ごとに DPI が違うので、位置は物理ピクセルで決め、ハンドルができた時点（SourceInitialized。見える前）で置く。
    /// 大きさは、XAML の既定の高さ・幅がその画面の作業領域より大きいとき（1366×768 で 125% など）、下のボタンが
    /// 画面の外に出ないように縮める。最小の大きさ（MinWidth / MinHeight）はそのまま。
    /// コンストラクタ（InitializeComponent のあと、Show の前）で呼ぶ。2 回目以降に前に出すときは、前の位置のまま。
    /// </summary>
    public static void FitToMouseScreen(Window window, double margin = 24)
    {
        var screen = System.Windows.Forms.Screen.FromPoint(System.Windows.Forms.Cursor.Position);
        var area = screen.WorkingArea;  // 物理ピクセル
        var scale = DpiOf(area) / 96.0;
        var areaWidth = area.Width / scale;
        var areaHeight = area.Height / scale;
        if (!double.IsNaN(window.Height) && window.Height > areaHeight - margin)
            window.Height = Math.Max(window.MinHeight, areaHeight - margin);
        if (!double.IsNaN(window.Width) && window.Width > areaWidth - margin)
            window.Width = Math.Max(window.MinWidth, areaWidth - margin);

        window.WindowStartupLocation = WindowStartupLocation.Manual;
        window.SourceInitialized += (_, _) =>
        {
            var hwnd = new WindowInteropHelper(window).Handle;
            if (hwnd == IntPtr.Zero) return;
            // 置き先の画面の DPI で大きさを物理ピクセルにし、作業領域の中央に置く（大きさは変えない。別の DPI の画面へ
            // 移ると WPF が WM_DPICHANGED で大きさを合わせ直す）
            var width = (int)Math.Round(window.Width * scale);
            var height = (int)Math.Round(window.Height * scale);
            var x = area.Left + Math.Max(0, (area.Width - width) / 2);
            var y = area.Top + Math.Max(0, (area.Height - height) / 2);
            NativeMethods.SetWindowPos(hwnd, IntPtr.Zero, x, y, 0, 0, NativeMethods.SWP_NOSIZE | NativeMethods.SWP_NOZORDER | NativeMethods.SWP_NOACTIVATE);
        };
    }

    /// <summary>その領域の中央にある画面の DPI（HudWindow.DpiOf と同じ）</summary>
    private static uint DpiOf(System.Drawing.Rectangle area)
    {
        var monitor = MonitorFromPoint(new POINT { X = area.Left + area.Width / 2, Y = area.Top + area.Height / 2 }, 2 /* MONITOR_DEFAULTTONEAREST */);
        return GetDpiForMonitor(monitor, 0 /* MDT_EFFECTIVE_DPI */, out var dpiX, out _) == 0 ? dpiX : 96;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT
    {
        public int X;
        public int Y;
    }

    [DllImport("user32.dll")]
    private static extern IntPtr MonitorFromPoint(POINT pt, uint flags);

    [DllImport("shcore.dll")]
    private static extern int GetDpiForMonitor(IntPtr monitor, int dpiType, out uint dpiX, out uint dpiY);
}
