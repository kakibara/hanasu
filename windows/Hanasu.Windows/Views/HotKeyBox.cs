using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using Hanasu.Core.Settings;

namespace Hanasu.Windows.Views;

/// <summary>
/// ショートカットを記録する欄。クリックしてからキーを押すと、その組み合わせを記録する。
/// 記録している間はアプリのホットキーを外す（RecordingChanged で知らせる）。
/// </summary>
public sealed class HotKeyBox : TextBox
{
    private HotKeyCombo? combo;

    /// <summary>新しい組み合わせが押されたとき</summary>
    public event EventHandler<HotKeyCombo>? Recorded;

    /// <summary>記録を始めた（true）・やめた（false）</summary>
    public event EventHandler<bool>? RecordingChanged;

    public HotKeyBox()
    {
        IsReadOnly = true;
        IsReadOnlyCaretVisible = false;
        Cursor = Cursors.Hand;
        MinWidth = 220;
        Padding = new Thickness(6, 3, 6, 3);
        InputMethod.SetIsInputMethodEnabled(this, false);
    }

    public HotKeyCombo? Combo
    {
        get => combo;
        set
        {
            combo = value;
            if (!IsKeyboardFocused) Text = value?.DisplayString ?? "";
        }
    }

    protected override void OnGotKeyboardFocus(KeyboardFocusChangedEventArgs e)
    {
        base.OnGotKeyboardFocus(e);
        Text = "キーを押してください（Esc でやめる）…";
        RecordingChanged?.Invoke(this, true);
    }

    protected override void OnLostKeyboardFocus(KeyboardFocusChangedEventArgs e)
    {
        base.OnLostKeyboardFocus(e);
        Text = combo?.DisplayString ?? "";
        RecordingChanged?.Invoke(this, false);
    }

    protected override void OnPreviewKeyDown(KeyEventArgs e)
    {
        e.Handled = true;
        var key = e.Key switch
        {
            Key.System => e.SystemKey,          // Alt を押しているとき
            Key.ImeProcessed => e.ImeProcessedKey,
            _ => e.Key,
        };
        if (key == Key.Escape && Keyboard.Modifiers == ModifierKeys.None)
        {
            MoveFocusAway();
            return;
        }
        var modifiers = HotKeyModifiers.None;
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Control)) modifiers |= HotKeyModifiers.Control;
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Alt)) modifiers |= HotKeyModifiers.Alt;
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Shift)) modifiers |= HotKeyModifiers.Shift;
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Windows)) modifiers |= HotKeyModifiers.Win;
        var vk = KeyInterop.VirtualKeyFromKey(key);
        if (HotKeyCombo.IsModifierKey(vk))
        {
            // 修飾キーだけのうちは、押している組み合わせを見せて待つ
            Text = new HotKeyCombo(modifiers, 0).DisplayString.Replace("キー 0x00", "…");
            return;
        }
        var recorded = new HotKeyCombo(modifiers, vk);
        Recorded?.Invoke(this, recorded);
        MoveFocusAway();
    }

    private void MoveFocusAway()
    {
        // フォーカスを外して記録を終える（親のウインドウに戻す）
        var scope = FocusManager.GetFocusScope(this);
        FocusManager.SetFocusedElement(scope, null);
        Keyboard.ClearFocus();
    }
}
