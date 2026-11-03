using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using Hanasu.Core.Dictation;
using Hanasu.Core.Settings;
using Hanasu.Windows.Native;

namespace Hanasu.Windows.Services;

/// <summary>
/// クリップボードに入れて Ctrl+V を SendInput で送り、カーソル位置に入力する（Mac 版の TextInserter と同じ流れ）。
/// 1. ホットキーの修飾キーが離されるのを待つ
/// 2. 貼り付け先を確かめる。権限の高いウインドウ（UIPI）や、入力できる場所がない（FocusProbe → PasteTargetJudge）なら送らない。
///    そのときは設定（PasteFallbackClipboard）に従い、結果をクリップボードに入れたままにするか、クリップボードに触らずに返す（REQ-DIC-080・081）
/// 3. 今のクリップボードを形式ごとに退避し、文章を置く。クリップボードの履歴（Win+V）やクラウド同期に残らないよう、除外の印を付ける（DEC-COM-149）
/// 4. Ctrl+V を送り、少し待ってから、退避したクリップボードを戻す（その間にユーザーがコピーしていたら戻さない）
/// UI スレッド（STA）から呼ぶ。
/// </summary>
// 要件: REQ-DIC-080, REQ-DIC-081
// 設計判断: DEC-COM-149, DEC-DIC-111, DEC-DIC-122, DEC-DIC-123
internal sealed class ClipboardTextInserter : ITextInserter
{
    /// <summary>貼り付け先がクリップボードを読み終えるまで待つ時間</summary>
    private static readonly TimeSpan RestoreDelay = TimeSpan.FromMilliseconds(500);

    public async Task<InsertOutcome> InsertAsync(string text, PasteFallbackClipboard fallback)
    {
        // 修飾キーを押したまま Ctrl+V を送ると Ctrl+Alt+V などになってしまうので、離されるまで待つ
        await WaitForModifierReleaseAsync();

        if (await BlockedReasonAsync() is { } reason)
        {
            // 送らない。結果は HUD に残す。設定で「クリップボードにも入れておく」なら、印を付けて置いたままにする（戻さない）
            if (fallback == PasteFallbackClipboard.RestoreOriginal) return InsertOutcome.NotPastedBecause(reason, clipboardHasText: false);
            var copied = await TrySetTextAsync(text);
            return InsertOutcome.NotPastedBecause(reason, clipboardHasText: copied);
        }

        var saved = Snapshot();
        if (!await TrySetTextAsync(text)) return InsertOutcome.NotPastedBecause(NotPastedReason.ClipboardUnavailable, clipboardHasText: false);
        var ourSequence = NativeMethods.GetClipboardSequenceNumber();
        if (!SendCtrlV())
        {
            // ほかの理由で送れなかった（入力がほかに奪われている など）
            if (fallback == PasteFallbackClipboard.KeepResult) return InsertOutcome.NotPastedBecause(NotPastedReason.SendFailed, clipboardHasText: true);
            if (NativeMethods.GetClipboardSequenceNumber() == ourSequence) await RestoreAsync(saved);
            return InsertOutcome.NotPastedBecause(NotPastedReason.SendFailed, clipboardHasText: false);
        }

        await Task.Delay(RestoreDelay);
        if (NativeMethods.GetClipboardSequenceNumber() == ourSequence)
        {
            await RestoreAsync(saved);
        }
        return InsertOutcome.Pasted;
    }

    /// <summary>Ctrl+V を送ってはいけない（送っても入らない）理由。送ってよければ null</summary>
    private static async Task<NotPastedReason?> BlockedReasonAsync()
    {
        var foreground = NativeMethods.GetForegroundWindow();
        // 管理者として動いているアプリなど、Hanasu より権限の高いウインドウにはキーが届かない（UIPI）。
        // SendInput は成功を返してしまうので、先に確かめる（DEC-COM-149）
        if (WindowsSecurity.IsHigherIntegrity(foreground)) return NotPastedReason.HigherIntegrity;

        var decision = PasteTargetJudge.Judge(await FocusProbe.CaptureAsync(foreground));
        // 根拠（クラス名・種類）だけを書く。文章の中身は書かない
        AppLog.Write($"paste target: {(decision.CanPaste ? "paste" : decision.Reason.ToString())} ({decision.Basis})");
        return decision.CanPaste ? null : decision.Reason;
    }

    /// <summary>今のクリップボードの中身を、読める形式だけ写し取る</summary>
    private static DataObject? Snapshot()
    {
        try
        {
            var current = Clipboard.GetDataObject();
            if (current is null) return null;
            var copy = new DataObject();
            foreach (var format in current.GetFormats(autoConvert: false))
            {
                try
                {
                    var data = current.GetData(format, autoConvert: false);
                    if (data is not null) copy.SetData(format, data);
                }
                catch (Exception e) when (e is COMException or OutOfMemoryException or ExternalException or ArgumentException)
                {
                    // 遅延描画や独自形式など、読めない形式は諦める
                }
            }
            return copy.GetFormats().Length == 0 ? null : copy;
        }
        catch (ExternalException)
        {
            return null;
        }
    }

    private static async Task<bool> TrySetTextAsync(string text)
    {
        var data = new DataObject();
        data.SetText(text, TextDataFormat.UnicodeText);
        // クリップボードの履歴・クラウドのクリップボード・クリップボード監視アプリに残さないための印
        data.SetData("ExcludeClipboardContentFromMonitorProcessing", new MemoryStream(new byte[] { 0, 0, 0, 0 }));
        data.SetData("CanIncludeInClipboardHistory", new MemoryStream(BitConverter.GetBytes(0)));
        data.SetData("CanUploadToCloudClipboard", new MemoryStream(BitConverter.GetBytes(0)));
        return await RetryAsync(() => Clipboard.SetDataObject(data, copy: true));
    }

    private static async Task RestoreAsync(DataObject? saved)
    {
        await RetryAsync(() =>
        {
            if (saved is null) Clipboard.Clear();
            else Clipboard.SetDataObject(saved, copy: true);
        });
    }

    /// <summary>ほかのアプリがクリップボードを開いていると失敗するので、少し待ってやり直す</summary>
    private static async Task<bool> RetryAsync(Action action)
    {
        for (var attempt = 0; attempt < 10; attempt++)
        {
            try
            {
                action();
                return true;
            }
            catch (ExternalException)
            {
                await Task.Delay(50);
            }
        }
        return false;
    }

    private static async Task WaitForModifierReleaseAsync()
    {
        int[] modifiers = [NativeMethods.VK_CONTROL, NativeMethods.VK_MENU, NativeMethods.VK_SHIFT, NativeMethods.VK_LWIN, NativeMethods.VK_RWIN];
        for (var i = 0; i < 40; i++)  // 最大 2 秒
        {
            if (!modifiers.Any(NativeMethods.IsKeyDown)) return;
            await Task.Delay(50);
        }
    }

    private static bool SendCtrlV()
    {
        NativeMethods.INPUT[] inputs =
        [
            NativeMethods.KeyInput(NativeMethods.VK_CONTROL, up: false),
            NativeMethods.KeyInput(NativeMethods.VK_V, up: false),
            NativeMethods.KeyInput(NativeMethods.VK_V, up: true),
            NativeMethods.KeyInput(NativeMethods.VK_CONTROL, up: true),
        ];
        var sent = NativeMethods.SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<NativeMethods.INPUT>());
        return sent == inputs.Length;
    }
}
