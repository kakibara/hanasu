using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using Hanasu.Core.Dictation;
using Hanasu.Windows.Native;

namespace Hanasu.Windows.Services;

/// <summary>
/// クリップボードに入れて Ctrl+V を SendInput で送り、カーソル位置に入力する（Mac 版の TextInserter と同じ流れ）。
/// 1. 今のクリップボードを形式ごとに退避する
/// 2. 文章を置く。クリップボードの履歴（Win+V）やクラウド同期に残らないよう、除外の印を付ける
/// 3. ホットキーの修飾キーが離されるのを待って、Ctrl+V を送る
/// 4. 少し待ってから、退避したクリップボードを戻す（その間にユーザーがコピーしていたら戻さない）
/// UI スレッド（STA）から呼ぶ。
/// </summary>
internal sealed class ClipboardTextInserter : ITextInserter
{
    /// <summary>貼り付け先がクリップボードを読み終えるまで待つ時間</summary>
    private static readonly TimeSpan RestoreDelay = TimeSpan.FromMilliseconds(500);

    public async Task<InsertOutcome> InsertAsync(string text)
    {
        var saved = Snapshot();
        if (!await TrySetTextAsync(text)) return InsertOutcome.CopiedOnly;
        var ourSequence = NativeMethods.GetClipboardSequenceNumber();

        // 修飾キーを押したまま Ctrl+V を送ると Ctrl+Alt+V などになってしまうので、離されるまで待つ
        await WaitForModifierReleaseAsync();
        if (!SendCtrlV())
        {
            // 管理者として動いているアプリなどには送れない（UIPI）。クリップボードには残す
            return InsertOutcome.CopiedOnly;
        }

        await Task.Delay(RestoreDelay);
        if (NativeMethods.GetClipboardSequenceNumber() == ourSequence)
        {
            await RestoreAsync(saved);
        }
        return InsertOutcome.Pasted;
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
