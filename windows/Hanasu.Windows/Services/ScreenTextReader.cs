using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.WindowsRuntime;
using System.Windows.Interop;
using Hanasu.Core.Text;
using Hanasu.Windows.Native;
using Windows.Globalization;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using Forms = System.Windows.Forms;

namespace Hanasu.Windows.Services;

// 画面から辞書の候補を探す（REQ-DIC-075）の、撮る・読む部分（Mac 版の ScreenSnapshotReader.captureAll・recognizeAll にあたる）。
// 撮る（CaptureAll）と読む（RecognizeAsync）を分ける。撮り終えてから候補の画面を開き、そのあとで読むため（DEC-DIC-234）。
// 画像はディスクに書かず、読み終えたら ScreenCapture.Dispose で捨てる。ログには数と時間と言語だけを出し、読んだ文字は出さない。

/// <summary>撮った画面 1 枚。Bounds は画面全体（仮想スクリーン）の物理ピクセルの座標</summary>
internal sealed class CapturedScreen(int index, Rectangle bounds, Bitmap image) : IDisposable
{
    /// <summary>何番目の画面か（メインの画面が 0）</summary>
    public int Index { get; } = index;
    public Rectangle Bounds { get; } = bounds;
    public Bitmap Image { get; } = image;

    public void Dispose() => Image.Dispose();
}

/// <summary>1 回に撮ったすべての画面。読み終えたら Dispose する（画像はメモリの上だけに置く）</summary>
internal sealed class ScreenCapture(IReadOnlyList<CapturedScreen> screens) : IDisposable
{
    public IReadOnlyList<CapturedScreen> Screens { get; } = screens;

    public void Dispose()
    {
        foreach (var screen in Screens) screen.Dispose();
    }
}

/// <summary>
/// 読んだ結果。LanguageTag・LanguageName は使った OCR の言語、WantedLanguageName は文字起こしの言語の名前。
/// Fallback は、文字起こしの言語の OCR がなく、ほかの言語で読んだか（画面で知らせる）
/// </summary>
internal sealed record ScreenTextResult(
    IReadOnlyList<ScreenTextLine> Lines, int Displays, string LanguageTag, string LanguageName, string WantedLanguageName, bool Fallback);

/// <summary>撮れない・読めないときの理由（Message はそのまま画面に出せる文言）</summary>
internal sealed class ScreenTextException(string message, Exception? inner = null) : Exception(message, inner);

// 要件: REQ-DIC-075
// 設計判断: DEC-DIC-234, DEC-DIC-235
internal static partial class ScreenTextReader
{
    /// <summary>OcrEngine.MaxImageDimension を超える画像を分けるときの、となりのタイルとの重なり（px。行が切れて読めないのを防ぐ）</summary>
    public const int TileOverlap = 100;

    // MARK: - 撮る

    // 設計判断: DEC-DIC-234, DEC-DIC-235
    /// <summary>
    /// すべてのモニターを、GDI の BitBlt（Graphics.CopyFromScreen）で物理ピクセルのまま撮る（アプリは PerMonitorV2）。
    /// 撮る前に、開いている Hanasu のウインドウをキャプチャから外し（WDA_EXCLUDEFROMCAPTURE）、撮り終えたら元に戻す
    /// （戻さないと、画面の共有で Hanasu のウインドウが見えなくなるため）。
    /// 既定の除外のアプリ（ScreenDictionary.WindowsExcludedProcesses）のウインドウの枠は、撮った画像の上で黒く塗る。
    /// UI のスレッドで呼ぶ（Application.Current.Windows を見るため）。撮れなければ ScreenTextException
    /// </summary>
    public static ScreenCapture CaptureAll()
    {
        var started = Stopwatch.StartNew();
        var restore = ExcludeOwnWindows();
        var shots = new List<CapturedScreen>();
        try
        {
            var masks = ExcludedWindowBounds();
            // メインの画面を先に、ほかは左から（Mac の NSScreen.screens と同じく、メインが 0 番）
            var screens = Forms.Screen.AllScreens
                .OrderByDescending(s => s.Primary).ThenBy(s => s.Bounds.Left).ThenBy(s => s.Bounds.Top).ToList();
            foreach (var screen in screens)
            {
                var bounds = screen.Bounds;  // PerMonitorV2 なので物理ピクセル
                if (bounds.Width <= 0 || bounds.Height <= 0) continue;
                var shot = new CapturedScreen(shots.Count, bounds, new Bitmap(bounds.Width, bounds.Height, PixelFormat.Format32bppArgb));
                shots.Add(shot);
                using var graphics = Graphics.FromImage(shot.Image);
                graphics.CopyFromScreen(bounds.Left, bounds.Top, 0, 0, bounds.Size, CopyPixelOperation.SourceCopy | CopyPixelOperation.CaptureBlt);
                // 設計判断: DEC-DIC-235（ほかのウインドウの下に隠れている部分まで塗ってよい。多く除く側に倒す）
                foreach (var mask in masks)
                {
                    var area = Rectangle.Intersect(mask, bounds);
                    if (area.IsEmpty) continue;
                    area.Offset(-bounds.Left, -bounds.Top);
                    graphics.FillRectangle(Brushes.Black, area);
                }
            }
            if (shots.Count == 0) throw new ScreenTextException(Strings.ScreenDictionary_NoScreens);
            AppLog.Write($"screen text: captured {shots.Count} displays, masked {masks.Count} windows, {started.Elapsed.TotalSeconds:F2}s");
            return new ScreenCapture(shots);
        }
        catch (Exception e) when (e is Win32Exception or ExternalException or ArgumentException or OutOfMemoryException or InvalidOperationException)
        {
            foreach (var shot in shots) shot.Dispose();
            AppLog.Write($"screen text: capture failed ({e.GetType().Name}: {e.Message})");
            throw new ScreenTextException(string.Format(Strings.ScreenDictionary_CaptureFailed, e.Message), e);
        }
        catch
        {
            foreach (var shot in shots) shot.Dispose();
            throw;
        }
        finally
        {
            restore();
        }
    }

    // 設計判断: DEC-DIC-234
    /// <summary>開いている Hanasu のウインドウに WDA_EXCLUDEFROMCAPTURE を立てる。戻すための処理を返す</summary>
    private static Action ExcludeOwnWindows()
    {
        var changed = new List<(IntPtr Handle, uint Before)>();
        if (System.Windows.Application.Current is { } app)
        {
            foreach (System.Windows.Window window in app.Windows)
            {
                var handle = new WindowInteropHelper(window).Handle;
                if (handle == IntPtr.Zero) continue;
                if (!GetWindowDisplayAffinity(handle, out var before)) before = WDA_NONE;
                if (before == WDA_EXCLUDEFROMCAPTURE) continue;
                if (SetWindowDisplayAffinity(handle, WDA_EXCLUDEFROMCAPTURE)) changed.Add((handle, before));
                else AppLog.Write($"screen text: SetWindowDisplayAffinity failed ({Marshal.GetLastPInvokeError()})");
            }
        }
        // 立てたものが次の合成に入るのを待ってから撮る
        if (changed.Count > 0) DwmFlush();
        return () =>
        {
            foreach (var (handle, before) in changed)
            {
                if (IsWindow(handle)) SetWindowDisplayAffinity(handle, before);
            }
        };
    }

    // 設計判断: DEC-DIC-235
    /// <summary>
    /// 見えていて・最小化されておらず・cloaked でなく・大きさが 0 でないトップレベルのウインドウのうち、
    /// プロセスの exe が既定の除外の一覧にあるものの枠（DWMWA_EXTENDED_FRAME_BOUNDS。物理ピクセル）
    /// </summary>
    private static List<Rectangle> ExcludedWindowBounds()
    {
        var result = new List<Rectangle>();
        var excludedByProcess = new Dictionary<uint, bool>();
        EnumWindowsProc callback = (hwnd, _) =>
        {
            if (!IsWindowVisible(hwnd) || IsIconic(hwnd)) return true;
            // ShellExperienceHost はスタートメニューなど隠れた（cloaked の）ウインドウも持つ。見ないと画面の大きな範囲を塗ってしまう
            if (DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, out int cloaked, sizeof(int)) == 0 && cloaked != 0) return true;
            if (DwmGetWindowAttribute(hwnd, DWMWA_EXTENDED_FRAME_BOUNDS, out NativeMethods.RECT frame, Marshal.SizeOf<NativeMethods.RECT>()) != 0)
                return true;
            var bounds = Rectangle.FromLTRB(frame.Left, frame.Top, frame.Right, frame.Bottom);
            if (bounds.Width <= 0 || bounds.Height <= 0) return true;
            NativeMethods.GetWindowThreadProcessId(hwnd, out var pid);
            if (pid == 0) return true;
            if (!excludedByProcess.TryGetValue(pid, out var excluded))
            {
                excluded = ScreenDictionary.IsExcludedProcess(ProcessExe(pid));
                excludedByProcess[pid] = excluded;
            }
            if (excluded) result.Add(bounds);
            return true;
        };
        EnumWindows(callback, IntPtr.Zero);
        GC.KeepAlive(callback);
        return result;
    }

    /// <summary>プロセスの exe のパスか名前。取れなければ null</summary>
    private static string? ProcessExe(uint pid)
    {
        if (ForegroundWindowTracker.ProcessPath(pid) is { } path) return path;
        // 管理者で動くプロセスなどはパスを読めない。名前はプロセスの一覧から取れる
        try
        {
            using var process = Process.GetProcessById((int)pid);
            return process.ProcessName;
        }
        catch (Exception e) when (e is ArgumentException or InvalidOperationException)
        {
            return null;
        }
    }

    // MARK: - 読む

    // 設計判断: DEC-DIC-234
    /// <summary>
    /// 撮った画面を Windows.Media.Ocr で読む。言語は、文字起こしの言語（localeIdentifier）の OCR があればそれ、
    /// なければユーザーのプロファイルの言語、なければ英語。どの言語の OCR もなければ ScreenTextException。
    /// MaxImageDimension を超える画像は重なりを持たせたタイルに分けて読み、同じ画面の同じ文字列の行は 1 つにする。
    /// capture は呼んだ側が読み終えてから Dispose する
    /// </summary>
    public static async Task<ScreenTextResult> RecognizeAsync(ScreenCapture capture, string localeIdentifier, CancellationToken cancellationToken)
    {
        var started = Stopwatch.StartNew();
        var engine = CreateEngine(localeIdentifier);
        var tag = engine.RecognizerLanguage.LanguageTag;
        // 使った言語が文字起こしの言語に合わなければ、ほかの言語に落ちた
        var fallback = ScreenDictionary.MatchOcrLanguage(localeIdentifier, [tag]) is null;
        var maxDimension = (int)Math.Max(OcrEngine.MaxImageDimension, (uint)TileOverlap * 2 + 1);
        var lines = new List<ScreenTextLine>();
        foreach (var shot in capture.Screens)
        {
            var seen = new HashSet<string>(StringComparer.Ordinal);
            foreach (var tile in Tiles(shot.Image.Width, shot.Image.Height, maxDimension, TileOverlap))
            {
                cancellationToken.ThrowIfCancellationRequested();
                using var bitmap = ToSoftwareBitmap(shot.Image, tile);
                // 1 枚の OCR は途中で止めない（止めると、まだ使っている SoftwareBitmap を閉じてしまう）。止めるのはタイルの合間
                var result = await engine.RecognizeAsync(bitmap).AsTask().ConfigureAwait(false);
                foreach (var line in result.Lines)
                {
                    var words = line.Words;
                    if (words.Count == 0) continue;
                    var text = ScreenDictionary.JoinOcrWords(words.Select(w => w.Text));
                    if (text.Length == 0 || !seen.Add(text)) continue;
                    var x = words.Min(w => w.BoundingRect.X);
                    var y = words.Min(w => w.BoundingRect.Y);
                    // 位置は画面全体（仮想スクリーン）の座標。入力先はないので InTarget はいつも false
                    lines.Add(new ScreenTextLine(text, shot.Index, false, shot.Bounds.Top + tile.Top + y, shot.Bounds.Left + tile.Left + x));
                }
            }
        }
        AppLog.Write($"screen text: read {capture.Screens.Count} displays, {lines.Count} lines, {started.Elapsed.TotalSeconds:F2}s, ocr={tag}, fallback={fallback}");
        return new ScreenTextResult(lines, capture.Screens.Count, tag, LanguageName(tag), LanguageName(localeIdentifier), fallback);
    }

    // 設計判断: DEC-DIC-234
    /// <summary>文字起こしの言語 → ユーザーのプロファイルの言語 → 英語（en-US）の順に、OCR のエンジンを作る</summary>
    private static OcrEngine CreateEngine(string localeIdentifier)
    {
        var available = OcrEngine.AvailableRecognizerLanguages.Select(l => l.LanguageTag).ToList();
        if (ScreenDictionary.MatchOcrLanguage(localeIdentifier, available) is { } tag && TryCreate(tag) is { } wanted) return wanted;
        if (OcrEngine.TryCreateFromUserProfileLanguages() is { } profile) return profile;
        if (TryCreate("en-US") is { } english) return english;
        AppLog.Write($"screen text: no OCR language (available: {available.Count})");
        throw new ScreenTextException(Strings.ScreenDictionary_NoOcr);
    }

    private static OcrEngine? TryCreate(string tag)
    {
        try
        {
            return OcrEngine.TryCreateFromLanguage(new Language(tag));
        }
        catch (ArgumentException)
        {
            return null;
        }
    }

    /// <summary>言語の表示の名前（Windows の表示の言語で）。分からなければタグのまま</summary>
    private static string LanguageName(string tag)
    {
        try
        {
            return new Language(tag).DisplayName;
        }
        catch (ArgumentException)
        {
            return tag;
        }
    }

    /// <summary>
    /// width × height の画像を、1 辺が max 以下のタイルに分ける（となりと overlap だけ重ねる）。収まれば画像全体の 1 つ
    /// </summary>
    internal static IEnumerable<Rectangle> Tiles(int width, int height, int max, int overlap)
    {
        static List<(int Start, int Length)> Spans(int total, int max, int overlap)
        {
            var spans = new List<(int, int)>();
            if (total <= max) return [(0, total)];
            var step = Math.Max(1, max - overlap);
            for (var start = 0; ; start += step)
            {
                var length = Math.Min(max, total - start);
                spans.Add((start, length));
                if (start + length >= total) break;
            }
            return spans;
        }
        foreach (var (top, tileHeight) in Spans(height, max, overlap))
        {
            foreach (var (left, tileWidth) in Spans(width, max, overlap))
            {
                yield return new Rectangle(left, top, tileWidth, tileHeight);
            }
        }
    }

    /// <summary>撮った画像の一部を、OCR に渡す SoftwareBitmap（BGRA8）に写す。ディスクには書かない</summary>
    private static SoftwareBitmap ToSoftwareBitmap(Bitmap image, Rectangle area)
    {
        var data = image.LockBits(area, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        try
        {
            // Format32bppArgb のメモリの並びは B, G, R, A（BitmapPixelFormat.Bgra8 と同じ）
            var rowBytes = area.Width * 4;
            var bytes = new byte[rowBytes * area.Height];
            for (var row = 0; row < area.Height; row++)
            {
                Marshal.Copy(data.Scan0 + row * data.Stride, bytes, row * rowBytes, rowBytes);
            }
            return SoftwareBitmap.CreateCopyFromBuffer(bytes.AsBuffer(), BitmapPixelFormat.Bgra8, area.Width, area.Height, BitmapAlphaMode.Premultiplied);
        }
        finally
        {
            image.UnlockBits(data);
        }
    }

    // MARK: - Win32

    private const uint WDA_NONE = 0x00;
    /// <summary>キャプチャから外す（Windows 10 2004 = 10.0.19041 から。DEC-DIC-234）</summary>
    private const uint WDA_EXCLUDEFROMCAPTURE = 0x11;
    private const int DWMWA_EXTENDED_FRAME_BOUNDS = 9;
    private const int DWMWA_CLOAKED = 14;

    private delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool IsWindowVisible(IntPtr hwnd);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool IsIconic(IntPtr hwnd);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool IsWindow(IntPtr hwnd);

    [LibraryImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool SetWindowDisplayAffinity(IntPtr hwnd, uint affinity);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GetWindowDisplayAffinity(IntPtr hwnd, out uint affinity);

    [LibraryImport("dwmapi.dll")]
    private static partial int DwmGetWindowAttribute(IntPtr hwnd, int attribute, out int value, int size);

    [LibraryImport("dwmapi.dll")]
    private static partial int DwmGetWindowAttribute(IntPtr hwnd, int attribute, out NativeMethods.RECT value, int size);

    [LibraryImport("dwmapi.dll")]
    private static partial int DwmFlush();
}
