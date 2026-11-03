using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Threading;
using Hanasu.Core.Dictation;
using Hanasu.Windows.Native;

namespace Hanasu.Windows.Views;

/// <summary>
/// 画面の下に出る小さな状態表示（Mac 版の HUDPanel）。
/// WS_EX_NOACTIVATE で、前面に出てもクリックされても入力先アプリのフォーカスを奪わない。
/// 「日本語 / English」「取消」「■ 停止」を押せる準備中・録音中だけクリックを受け取り、それ以外は WS_EX_TRANSPARENT でマウスを素通しする。
/// IHud のメソッドはどのスレッドから呼んでもよい（UI スレッドに回す）。
/// </summary>
public partial class HudWindow : Window, IHud
{
    private readonly DispatcherTimer elapsedTimer;
    private readonly DispatcherTimer hideTimer;
    private HudState state = HudState.Recording;
    private string transcript = "";
    private bool translating;
    private DateTime startedAt = DateTime.Now;
    private IntPtr hwnd;

    public event EventHandler<bool>? LanguageSelected;
    public event EventHandler? StopRequested;
    public event EventHandler? CancelRequested;

    public HudWindow()
    {
        InitializeComponent();
        elapsedTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(250) };
        elapsedTimer.Tick += (_, _) => ElapsedText.Text = HudText.Elapsed(DateTime.Now - startedAt);
        hideTimer = new DispatcherTimer();
        hideTimer.Tick += (_, _) =>
        {
            hideTimer.Stop();
            Hide();
        };
        SourceInitialized += OnSourceInitialized;
        DpiChanged += (_, _) => PlaceAtBottom();
    }

    private void OnSourceInitialized(object? sender, EventArgs e)
    {
        hwnd = new WindowInteropHelper(this).Handle;
        var style = NativeMethods.GetWindowLongPtr(hwnd, NativeMethods.GWL_EXSTYLE).ToInt64();
        style |= NativeMethods.WS_EX_NOACTIVATE | NativeMethods.WS_EX_TOOLWINDOW | NativeMethods.WS_EX_TOPMOST;
        NativeMethods.SetWindowLongPtr(hwnd, NativeMethods.GWL_EXSTYLE, new IntPtr(style));
        HwndSource.FromHwnd(hwnd)?.AddHook(WndProc);
    }

    private static IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        // クリックされてもアクティブにならない
        if (msg == NativeMethods.WM_MOUSEACTIVATE)
        {
            handled = true;
            return new IntPtr(NativeMethods.MA_NOACTIVATE);
        }
        return IntPtr.Zero;
    }

    public void Show(HudState newState) => OnUi(() =>
    {
        hideTimer.Stop();
        if (newState.Phase == HudPhase.Recording && state.Phase != HudPhase.Recording) startedAt = DateTime.Now;
        state = newState;
        Render();
        if (!IsVisible)
        {
            base.Show();  // ShowActivated=False なので前面アプリのフォーカスは動かない
        }
        SetClickThrough(!HudText.CanChooseLanguage(state.Phase));
        PlaceAtBottom();
        if (HudText.AutoHideDelay(newState.Phase) is { } delay)
        {
            hideTimer.Interval = delay;
            hideTimer.Start();
        }
    });

    public void UpdateTranscript(string text) => OnUi(() =>
    {
        transcript = text;
        DetailText.Text = HudText.Detail(state, transcript) ?? "";
    });

    public void SetTranslating(bool value) => OnUi(() =>
    {
        translating = value;
        RenderLanguage();
    });

    private void Render()
    {
        TitleText.Text = HudText.Title(state);
        var detail = HudText.Detail(state, transcript);
        DetailText.Text = detail ?? "";
        DetailText.Visibility = detail is null ? Visibility.Collapsed : Visibility.Visible;

        RecordingDot.Visibility = state.Phase == HudPhase.Recording ? Visibility.Visible : Visibility.Collapsed;
        Spinner.Visibility = state.Phase is HudPhase.Preparing or HudPhase.Processing ? Visibility.Visible : Visibility.Collapsed;
        DoneMark.Visibility = state.Phase == HudPhase.Done ? Visibility.Visible : Visibility.Collapsed;
        ErrorMark.Visibility = state.Phase == HudPhase.Error ? Visibility.Visible : Visibility.Collapsed;

        var recording = state.Phase == HudPhase.Recording;
        ElapsedText.Visibility = recording ? Visibility.Visible : Visibility.Collapsed;
        StopButton.Visibility = CancelButton.Visibility =
            HudText.ShowsRecordingControls(state.Phase) ? Visibility.Visible : Visibility.Collapsed;
        if (recording)
        {
            ElapsedText.Text = HudText.Elapsed(DateTime.Now - startedAt);
            elapsedTimer.Start();
        }
        else
        {
            elapsedTimer.Stop();
        }
        RenderLanguage();
        SetClickThrough(!HudText.CanChooseLanguage(state.Phase));
    }

    private void RenderLanguage()
    {
        LanguageSwitch.Visibility = HudText.CanChooseLanguage(state.Phase) ? Visibility.Visible : Visibility.Collapsed;
        JapaneseButton.Tag = translating ? null : "selected";
        EnglishButton.Tag = translating ? "selected" : null;
    }

    private void OnJapaneseClick(object sender, RoutedEventArgs e) => LanguageSelected?.Invoke(this, false);

    private void OnEnglishClick(object sender, RoutedEventArgs e) => LanguageSelected?.Invoke(this, true);

    private void OnStopClick(object sender, RoutedEventArgs e) => StopRequested?.Invoke(this, EventArgs.Empty);

    private void OnCancelClick(object sender, RoutedEventArgs e) => CancelRequested?.Invoke(this, EventArgs.Empty);

    /// <summary>言語を選べる間だけクリックを受け取る</summary>
    private void SetClickThrough(bool clickThrough)
    {
        if (hwnd == IntPtr.Zero) return;
        var style = NativeMethods.GetWindowLongPtr(hwnd, NativeMethods.GWL_EXSTYLE).ToInt64();
        style = clickThrough ? style | NativeMethods.WS_EX_TRANSPARENT : style & ~(long)NativeMethods.WS_EX_TRANSPARENT;
        NativeMethods.SetWindowLongPtr(hwnd, NativeMethods.GWL_EXSTYLE, new IntPtr(style));
    }

    /// <summary>マウスのある画面の、作業領域の下端から少し上の中央に置く（位置は物理ピクセルで決める）</summary>
    private void PlaceAtBottom()
    {
        if (hwnd == IntPtr.Zero) return;
        var screen = System.Windows.Forms.Screen.FromPoint(System.Windows.Forms.Cursor.Position);
        var area = screen.WorkingArea;
        var scale = DpiOf(area) / 96.0;
        var width = (int)Math.Round(Width * scale);
        var height = (int)Math.Round(Height * scale);
        var x = area.Left + (area.Width - width) / 2;
        var y = area.Bottom - height - (int)Math.Round(56 * scale);
        NativeMethods.SetWindowPos(hwnd, NativeMethods.HWND_TOPMOST, x, y, 0, 0, NativeMethods.SWP_NOSIZE | NativeMethods.SWP_NOACTIVATE);
    }

    private static uint DpiOf(System.Drawing.Rectangle area)
    {
        var monitor = MonitorFromPoint(new POINT { X = area.Left + area.Width / 2, Y = area.Top + area.Height / 2 }, 2 /* MONITOR_DEFAULTTONEAREST */);
        return GetDpiForMonitor(monitor, 0 /* MDT_EFFECTIVE_DPI */, out var dpiX, out _) == 0 ? dpiX : 96;
    }

    private void OnUi(Action action)
    {
        if (Dispatcher.CheckAccess()) action();
        else Dispatcher.BeginInvoke(action);
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
