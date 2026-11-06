import Carbon.HIToolbox
import SwiftUI

extension HotKeyCombo {
    /// 選択を声で編集する。⌥⌘ Space は macOS の「Finder の検索ウインドウを表示」と、⌃⌥ Space は入力ソースの切り替えと重なるので避け、
    /// 会議の記録（⌃⌥⌘ M）と同じ修飾キーに Edit の E を合わせた
    static let defaultEdit = HotKeyCombo(
        keyCode: UInt32(kVK_ANSI_E), modifiers: UInt32(controlKey | optionKey | cmdKey))
}

// 設計判断: DEC-DIC-030
/// 選択を声で編集するモードの設定。ほかの機能の設定（AppSettings）とは分けて持つ。
final class EditModeSettings: ObservableObject {
    static let shared = EditModeSettings()

    private let defaults = UserDefaults.standard

    @Published var hotKey: HotKeyCombo {
        didSet {
            defaults.set(Int(hotKey.keyCode), forKey: Keys.hotKeyCode)
            defaults.set(Int(hotKey.modifiers), forKey: Keys.hotKeyModifiers)
        }
    }

    /// 一度に書き換えられる選択の長さ。長すぎると Gemini の待ち時間が延び、貼り付けの失敗時に失うものも大きい
    static let maxSelectionLength = 10_000

    private init() {
        defaults.register(defaults: [
            Keys.hotKeyCode: Int(HotKeyCombo.defaultEdit.keyCode),
            Keys.hotKeyModifiers: Int(HotKeyCombo.defaultEdit.modifiers),
        ])
        hotKey = HotKeyCombo(
            keyCode: UInt32(defaults.integer(forKey: Keys.hotKeyCode)),
            modifiers: UInt32(defaults.integer(forKey: Keys.hotKeyModifiers)))
    }

    private enum Keys {
        static let hotKeyCode = "editHotKeyCode"
        static let hotKeyModifiers = "editHotKeyModifiers"
    }
}

/// 設定画面の「ショートカット」に置く行
struct EditModeShortcutRow: View {
    @ObservedObject var settings = EditModeSettings.shared
    var onBeginRecording: () -> Void
    var onEndRecording: () -> Void

    var body: some View {
        LabeledContent(tr("選択を声で編集")) {
            ShortcutRecorder(
                combo: $settings.hotKey,
                defaultCombo: .defaultEdit,
                kind: .edit,
                onBeginRecording: onBeginRecording,
                onEndRecording: onEndRecording)
        }
        Text(tr("文章を選択してから押し、「もっと丁寧に」「箇条書きにして」「英語にして」のように話すと、AI（設定の「AI」で音声入力に選んだもの）が書き換えて選択範囲に貼り付けます（Gemini か Claude なら認証情報、「ローカル」ならモデルのダウンロードが必要です）。"))
            .font(.caption).foregroundStyle(.secondary)
    }
}
