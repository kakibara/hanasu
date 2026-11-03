using System.Text.Json.Serialization;

namespace Hanasu.Core.Settings;

/// <summary>RegisterHotKey の修飾キー（MOD_ALT など）と同じ値</summary>
[Flags]
public enum HotKeyModifiers
{
    None = 0,
    Alt = 0x1,
    Control = 0x2,
    Shift = 0x4,
    Win = 0x8,
}

/// <summary>
/// グローバルショートカット。Windows の仮想キーコード（VK_*）と修飾キーで持つ。
/// 既定は Ctrl+Alt+Space（音声入力）と Ctrl+Alt+Shift+Space（英訳）。
/// Alt+Space は Windows のウインドウメニュー、Win+H は Windows の音声入力、Win+Space は入力言語の切り替えなので避けた。
/// </summary>
public sealed record HotKeyCombo(HotKeyModifiers Modifiers, int VirtualKey)
{
    public const int VkSpace = 0x20;
    public const int VkEscape = 0x1B;

    public static HotKeyCombo DefaultDictation { get; } = new(HotKeyModifiers.Control | HotKeyModifiers.Alt, VkSpace);
    public static HotKeyCombo DefaultTranslate { get; } = new(HotKeyModifiers.Control | HotKeyModifiers.Alt | HotKeyModifiers.Shift, VkSpace);
    /// <summary>
    /// 会議の記録の開始／停止。Ctrl + Alt + Shift + M（Mac 版の ⌃⌥⌘ M にあたる）。
    /// Teams のミュート（Ctrl + Shift + M）や Zoom（Alt + M など）と重ならないよう、修飾キーを 3 つにした
    /// </summary>
    public static HotKeyCombo DefaultMeeting { get; } = new(HotKeyModifiers.Control | HotKeyModifiers.Alt | HotKeyModifiers.Shift, 0x4D);
    /// <summary>「ここ重要」の印。Ctrl + Alt + Shift + H（Mac 版の ⌃⌥⌘ H にあたる）。記録中だけ登録する</summary>
    public static HotKeyCombo DefaultHighlight { get; } = new(HotKeyModifiers.Control | HotKeyModifiers.Alt | HotKeyModifiers.Shift, 0x48);

    [JsonIgnore]
    public string DisplayString
    {
        get
        {
            var parts = new List<string>();
            if (Modifiers.HasFlag(HotKeyModifiers.Control)) parts.Add("Ctrl");
            if (Modifiers.HasFlag(HotKeyModifiers.Win)) parts.Add("Win");
            if (Modifiers.HasFlag(HotKeyModifiers.Alt)) parts.Add("Alt");
            if (Modifiers.HasFlag(HotKeyModifiers.Shift)) parts.Add("Shift");
            parts.Add(KeyNames.Name(VirtualKey));
            return string.Join(" + ", parts);
        }
    }

    public override string ToString() => DisplayString;

    /// <summary>修飾キー自身の仮想キーコード（Shift / Ctrl / Alt / Win。左右の区別つきも含む）</summary>
    public static bool IsModifierKey(int vk) => vk is 0x10 or 0x11 or 0x12 or 0x5B or 0x5C or >= 0xA0 and <= 0xA5;

    /// <summary>ショートカットとして使えないときは理由を返す（使えるなら null）</summary>
    public string? Validate()
    {
        if (VirtualKey <= 0 || IsModifierKey(VirtualKey)) return "修飾キーのほかに、キーを 1 つ押してください";
        if (VirtualKey == VkEscape) return "Esc は録音の取り消しに使うので、ショートカットにできません";
        var isFunctionKey = VirtualKey is >= 0x70 and <= 0x87;  // F1〜F24
        if (Modifiers == HotKeyModifiers.None && !isFunctionKey)
        {
            return "Ctrl・Alt・Shift・Win のどれかと組み合わせてください（F1〜F24 は単独でも使えます）";
        }
        if (Modifiers == HotKeyModifiers.Shift && !isFunctionKey) return "Shift だけの組み合わせは文字の入力とぶつかるので使えません";
        foreach (var (combo, reason) in ReservedCombos)
        {
            if (combo == this) return $"{DisplayString} は {reason}に使われているので避けてください";
        }
        return null;
    }

    /// <summary>Windows や日本語入力が使っている組み合わせ</summary>
    public static readonly IReadOnlyList<(HotKeyCombo Combo, string Reason)> ReservedCombos =
    [
        (new(HotKeyModifiers.Alt, VkSpace), "Windows のウインドウメニュー"),
        (new(HotKeyModifiers.Win, 0x48), "Windows の音声入力（Win + H）"),
        (new(HotKeyModifiers.Win, VkSpace), "入力言語の切り替え"),
        (new(HotKeyModifiers.Control, VkSpace), "日本語入力のオン／オフ（IME によって）"),
        (new(HotKeyModifiers.Shift, VkSpace), "全角／半角スペースの入力"),
        (new(HotKeyModifiers.Alt, 0x09), "ウインドウの切り替え"),
        (new(HotKeyModifiers.Alt, 0x73), "ウインドウを閉じる操作"),
        (new(HotKeyModifiers.Win, 0x4C), "画面のロック"),
        (new(HotKeyModifiers.Win, 0x44), "デスクトップの表示"),
    ];
}

/// <summary>仮想キーコードの表示名</summary>
public static class KeyNames
{
    public static string Name(int vk) => vk switch
    {
        0x08 => "Backspace",
        0x09 => "Tab",
        0x0D => "Enter",
        0x13 => "Pause",
        0x1B => "Esc",
        0x20 => "Space",
        0x21 => "PageUp",
        0x22 => "PageDown",
        0x23 => "End",
        0x24 => "Home",
        0x25 => "←",
        0x26 => "↑",
        0x27 => "→",
        0x28 => "↓",
        0x2C => "PrintScreen",
        0x2D => "Insert",
        0x2E => "Delete",
        >= 0x30 and <= 0x39 => ((char)vk).ToString(),
        >= 0x41 and <= 0x5A => ((char)vk).ToString(),
        >= 0x60 and <= 0x69 => $"Num{vk - 0x60}",
        0x6A => "Num*",
        0x6B => "Num+",
        0x6D => "Num-",
        0x6E => "Num.",
        0x6F => "Num/",
        >= 0x70 and <= 0x87 => $"F{vk - 0x6F}",
        0x1C => "変換",
        0x1D => "無変換",
        0xBA => ":",
        0xBB => ";",
        0xBC => ",",
        0xBD => "-",
        0xBE => ".",
        0xBF => "/",
        0xC0 => "@",
        0xDB => "[",
        0xDC => "\\",
        0xDD => "]",
        0xDE => "^",
        0xE2 => "\\（ろ）",
        _ => $"キー 0x{vk:X2}",
    };
}
