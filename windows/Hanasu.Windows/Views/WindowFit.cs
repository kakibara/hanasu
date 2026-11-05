using System.Windows;

namespace Hanasu.Windows.Views;

/// <summary>ウインドウの大きさを、画面の作業領域に収める</summary>
internal static class WindowFit
{
    /// <summary>
    /// XAML の既定の高さ・幅が作業領域より大きいとき（1366×768 で 125% など）、下のボタンが画面の外に出ないように縮める。
    /// 最小の大きさ（MinWidth / MinHeight）はそのまま。
    /// </summary>
    public static void ClampToWorkArea(Window window, double margin = 24)
    {
        var area = SystemParameters.WorkArea;
        if (!double.IsNaN(window.Height) && window.Height > area.Height - margin)
            window.Height = Math.Max(window.MinHeight, area.Height - margin);
        if (!double.IsNaN(window.Width) && window.Width > area.Width - margin)
            window.Width = Math.Max(window.MinWidth, area.Width - margin);
    }
}
