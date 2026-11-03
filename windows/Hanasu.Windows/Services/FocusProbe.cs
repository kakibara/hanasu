using System.Text;
using System.Windows.Automation;
using Hanasu.Core.Dictation;
using Hanasu.Windows.Native;

namespace Hanasu.Windows.Services;

/// <summary>
/// 貼り付ける直前に、前面のウインドウとフォーカスの様子を集める（判定は Core の PasteTargetJudge）。
/// - Win32: GetForegroundWindow のクラス名と、そのスレッドの GetGUIThreadInfo（hwndFocus / hwndCaret）
/// - UI Automation: FocusedElement の ControlType と ValuePattern.IsReadOnly
/// UI Automation はほかのプロセスに問い合わせるので、別のスレッドで動かし、400 ms で打ち切る（応答しないアプリで貼り付けを待たせない）。
/// システムのキャレットがあれば入力欄と分かるので、UI Automation は調べない。結果で判定が変わりうるとき
/// （デスクトップ・タスクバー・エクスプローラー・フォーカスがない）のほかも調べない（PasteTargetJudge.NeedsAutomation）。
/// 読み取り専用の Win32 の入力欄は、フォーカスのあるウインドウのスタイル（ES_READONLY）で見る。
/// </summary>
// 要件: REQ-DIC-080
// 設計判断: DEC-DIC-120, DEC-DIC-124
internal static class FocusProbe
{
    private static readonly TimeSpan AutomationTimeout = TimeSpan.FromMilliseconds(400);

    public static async Task<FocusSnapshot> CaptureAsync(IntPtr foreground)
    {
        if (foreground == IntPtr.Zero) return new FocusSnapshot(HasForegroundWindow: false);
        var className = ClassNameOf(foreground);

        bool? hasFocus = null, hasCaret = null;
        var focusWindow = IntPtr.Zero;
        var thread = NativeMethods.GetWindowThreadProcessId(foreground, out _);
        var info = new NativeMethods.GUITHREADINFO { cbSize = (uint)System.Runtime.InteropServices.Marshal.SizeOf<NativeMethods.GUITHREADINFO>() };
        if (thread != 0 && NativeMethods.GetGUIThreadInfo(thread, ref info))
        {
            focusWindow = info.hwndFocus;
            hasFocus = info.hwndFocus != IntPtr.Zero;
            hasCaret = info.hwndCaret != IntPtr.Zero;
        }
        // 読み取り専用の Win32 の入力欄（プロパティのダイアログなど）は、キャレットを出していても貼っても入らない。スタイルを読むだけなので待たない
        if (focusWindow != IntPtr.Zero && PasteTargetJudge.IsWin32EditClass(ClassNameOf(focusWindow))
            && ((long)NativeMethods.GetWindowLongPtr(focusWindow, NativeMethods.GWL_STYLE) & NativeMethods.ES_READONLY) != 0)
        {
            return new FocusSnapshot(true, className, hasFocus, hasCaret, FocusedControlKind.Edit, IsReadOnly: true);
        }
        if (hasCaret == true) return new FocusSnapshot(true, className, hasFocus, hasCaret);
        // ブラウザ・Electron などは、UI Automation が何を返しても貼るので問い合わせない（待ち時間と、Chromium のアクセシビリティを有効にさせないため）
        if (!PasteTargetJudge.NeedsAutomation(className, hasFocus)) return new FocusSnapshot(true, className, hasFocus, hasCaret);

        var (control, readOnly) = await QueryAutomationAsync();
        return new FocusSnapshot(true, className, hasFocus, hasCaret, control, readOnly);
    }

    private static async Task<(FocusedControlKind Control, bool? ReadOnly)> QueryAutomationAsync()
    {
        // UI スレッドで待つと、Hanasu 自身のウインドウにフォーカスがあるとき（設定画面など）に、問い合わせが UI スレッドに戻れず止まる。
        // スレッドプール（MTA）で動かし、UI スレッドは await で空けておく
        var query = Task.Run(() =>
        {
            try
            {
                var element = AutomationElement.FocusedElement;
                if (element is null) return (FocusedControlKind.Unknown, (bool?)null);
                var type = element.Current.ControlType;
                var kind = type == ControlType.Edit ? FocusedControlKind.Edit
                    : type == ControlType.Document ? FocusedControlKind.Document
                    : FocusedControlKind.Other;
                bool? readOnly = element.TryGetCurrentPattern(ValuePattern.Pattern, out var pattern) && pattern is ValuePattern value
                    ? value.Current.IsReadOnly
                    : null;
                return (kind, readOnly);
            }
            catch (Exception e)
            {
                // 要素が消えた・権限がない・応答しない など。分からないものとして扱う（判定は貼り付けの側に倒れる）
                AppLog.Write($"focus probe: UI Automation failed: {e.GetType().Name}");
                return (FocusedControlKind.Unknown, (bool?)null);
            }
        });
        var finished = await Task.WhenAny(query, Task.Delay(AutomationTimeout));
        if (finished != query)
        {
            AppLog.Write("focus probe: UI Automation timed out");
            return (FocusedControlKind.Unknown, null);
        }
        return await query;
    }

    private static string ClassNameOf(IntPtr hwnd)
    {
        var name = new StringBuilder(256);
        NativeMethods.GetClassName(hwnd, name, name.Capacity);
        return name.ToString();
    }
}
