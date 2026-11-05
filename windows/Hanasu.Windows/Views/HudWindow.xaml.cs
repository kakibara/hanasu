using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Threading;
using Hanasu.Core.Dictation;
using Hanasu.Windows.Native;

namespace Hanasu.Windows.Views;

/// <summary>
/// 画面の下に出る小さな状態表示（Mac 版の HUDPanel）。
/// WS_EX_NOACTIVATE で、前面に出てもクリックされても入力先アプリのフォーカスを奪わない。
/// 「話した言語 / English / 日本語」「取消」「■ 停止」を押せる準備中・録音中だけクリックを受け取り、それ以外は WS_EX_TRANSPARENT でマウスを素通しする。
/// 貼り付けなかったとき（HudPhase.Unpasted）は、広げて結果の全文・「コピー」「閉じる」を出し、自動では閉じない。
/// 文章をクリックしたときだけ前面に出して（文字の選択・Ctrl+C・Esc のため）、閉じるときに元のウインドウへフォーカスを返す。
/// IHud のメソッドはどのスレッドから呼んでもよい（UI スレッドに回す）。
/// </summary>
// 要件: REQ-DIC-080
// 設計判断: DEC-DIC-112, DEC-DIC-121
public partial class HudWindow : Window, IHud
{
    private const double NormalWidth = 500;
    private const double NormalHeight = 136;
    private const double UnpastedWidth = 600;
    private const double UnpastedHeight = 330;

    private readonly DispatcherTimer elapsedTimer;
    private readonly DispatcherTimer hideTimer;
    private HudState state = HudState.Recording;
    private string transcript = "";
    private TranslationLanguage? translation;
    private IReadOnlyList<TranslationLanguage> translationChoices = [TranslationLanguage.English];
    private DateTime startedAt = DateTime.Now;
    private IntPtr hwnd;
    /// <summary>結果の文章をクリックして、前面に出している（WS_EX_NOACTIVATE を外している）</summary>
    private bool activatedForSelection;
    private readonly DispatcherTimer copyFeedbackTimer;

    public event EventHandler<TranslationLanguage?>? LanguageSelected;
    public event EventHandler? StopRequested;
    public event EventHandler? CancelRequested;

    /// <summary>結果の表示を前面に出したあと、入力先だったウインドウにフォーカスを返す（AppHost が ForegroundWindowTracker につなぐ）</summary>
    public Action? RestoreFocus { get; set; }

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
        copyFeedbackTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1.5) };
        copyFeedbackTimer.Tick += (_, _) =>
        {
            copyFeedbackTimer.Stop();
            CopyButtonText.Text = Strings.Hud_Copy;
        };
        SourceInitialized += OnSourceInitialized;
        DpiChanged += (_, _) => PlaceAtBottom();
        // ほかのウインドウをクリックしたら、また前面に出ない作りに戻す
        Deactivated += (_, _) => SetActivatable(false);
        PreviewKeyDown += OnPreviewKeyDown;
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
        // 結果の表示を前面に出したまま次の音声入力が始まったら、入力先のウインドウにフォーカスを返す
        if (newState.Phase != HudPhase.Unpasted) ReturnFocus();
        if (newState.Phase == HudPhase.Recording && state.Phase != HudPhase.Recording) startedAt = DateTime.Now;
        state = newState;
        var unpasted = state.Phase == HudPhase.Unpasted;
        Width = unpasted ? UnpastedWidth : NormalWidth;
        Height = unpasted ? UnpastedHeight : NormalHeight;
        Render();
        if (!IsVisible)
        {
            base.Show();  // ShowActivated=False なので前面アプリのフォーカスは動かない
        }
        SetClickThrough(!HudText.AcceptsClicks(state.Phase));
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

    // 要件: REQ-DIC-011, REQ-DIC-013
    public void SetLanguages(TranslationLanguage? selected, IReadOnlyList<TranslationLanguage> choices) => OnUi(() =>
    {
        translation = selected;
        translationChoices = choices;
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
        ErrorMark.Visibility = state.Phase is HudPhase.Error or HudPhase.Unpasted ? Visibility.Visible : Visibility.Collapsed;

        var unpasted = state.Phase == HudPhase.Unpasted;
        TitleText.MaxWidth = unpasted ? 400 : 190;
        DetailText.MaxHeight = unpasted ? 70 : 52;
        ResultBox.Visibility = CopyButton.Visibility = CloseButton.Visibility = unpasted ? Visibility.Visible : Visibility.Collapsed;
        if (unpasted)
        {
            ResultBox.Text = state.ResultText ?? "";
            ResultBox.ScrollToHome();
            copyFeedbackTimer.Stop();
            CopyButtonText.Text = Strings.Hud_Copy;
        }
        else
        {
            // 前の結果を画面に残さない
            ResultBox.Clear();
        }

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
        SetClickThrough(!HudText.AcceptsClicks(state.Phase));
    }

    private void RenderLanguage()
    {
        LanguageSwitch.Visibility = HudText.CanChooseLanguage(state.Phase) ? Visibility.Visible : Visibility.Collapsed;
        SpokenLanguageButton.Tag = translation is null ? "selected" : null;
        foreach (var (button, language) in new[] { (EnglishButton, TranslationLanguage.English), (JapaneseButton, TranslationLanguage.Japanese) })
        {
            button.Visibility = translationChoices.Contains(language) ? Visibility.Visible : Visibility.Collapsed;
            button.Tag = translation == language ? "selected" : null;
        }
    }

    private void OnSpokenLanguageClick(object sender, RoutedEventArgs e) => LanguageSelected?.Invoke(this, null);

    private void OnEnglishClick(object sender, RoutedEventArgs e) => LanguageSelected?.Invoke(this, TranslationLanguage.English);

    private void OnJapaneseClick(object sender, RoutedEventArgs e) => LanguageSelected?.Invoke(this, TranslationLanguage.Japanese);

    private void OnStopClick(object sender, RoutedEventArgs e) => StopRequested?.Invoke(this, EventArgs.Empty);

    private void OnCancelClick(object sender, RoutedEventArgs e) => CancelRequested?.Invoke(this, EventArgs.Empty);

    private void OnCopyClick(object sender, RoutedEventArgs e)
    {
        // ユーザーが自分でコピーする操作なので、履歴に残さない印は付けない（DEC-COM-149）
        CopyButtonText.Text = TryCopy(state.ResultText ?? "") ? Strings.Copied : Strings.Hud_CopyFailed;
        copyFeedbackTimer.Stop();
        copyFeedbackTimer.Start();
    }

    private void OnCloseClick(object sender, RoutedEventArgs e) => CloseUnpasted();

    private void OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        // 前面に出ているとき（文章をクリックしたあと）だけ、キーが届く
        if (e.Key == Key.Escape && state.Phase == HudPhase.Unpasted)
        {
            e.Handled = true;
            CloseUnpasted();
        }
    }

    /// <summary>文章を選べるよう、クリックしたときだけ前面に出す（ボタンは前面に出さずに押せる）</summary>
    private void OnResultMouseDown(object sender, MouseButtonEventArgs e)
    {
        if (state.Phase != HudPhase.Unpasted || IsActive) return;
        SetActivatable(true);
        Activate();
        ResultBox.Focus();
    }

    private void CloseUnpasted()
    {
        ReturnFocus();
        Hide();
        ResultBox.Clear();
    }

    /// <summary>前面に出していたら、入力先だったウインドウにフォーカスを返し、前面に出ない作りに戻す</summary>
    private void ReturnFocus()
    {
        var wasActive = activatedForSelection && IsActive;
        SetActivatable(false);
        if (wasActive) RestoreFocus?.Invoke();
    }

    /// <summary>WS_EX_NOACTIVATE を外す（true）・付け直す（false）</summary>
    private void SetActivatable(bool activatable)
    {
        activatedForSelection = activatable;
        if (hwnd == IntPtr.Zero) return;
        var style = NativeMethods.GetWindowLongPtr(hwnd, NativeMethods.GWL_EXSTYLE).ToInt64();
        style = activatable ? style & ~(long)NativeMethods.WS_EX_NOACTIVATE : style | NativeMethods.WS_EX_NOACTIVATE;
        NativeMethods.SetWindowLongPtr(hwnd, NativeMethods.GWL_EXSTYLE, new IntPtr(style));
    }

    /// <summary>ほかのアプリがクリップボードを開いていると失敗するので、少し待ってやり直す</summary>
    private static bool TryCopy(string text)
    {
        for (var attempt = 0; attempt < 5; attempt++)
        {
            try
            {
                Clipboard.SetDataObject(new DataObject(DataFormats.UnicodeText, text), copy: true);
                return true;
            }
            catch (ExternalException)
            {
                Thread.Sleep(50);
            }
        }
        return false;
    }

    /// <summary>クリックを受け取る間（HudText.AcceptsClicks）だけ、マウスを素通しにしない</summary>
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
