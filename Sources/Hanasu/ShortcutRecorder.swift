import AppKit
import Carbon.HIToolbox
import SwiftUI

// 設計判断: DEC-COM-018
/// 設定で変えられるショートカットの一覧（音声入力・翻訳・選択を声で編集・会議の記録・「ここ重要」・最後の結果をもう一度入力）。
/// 記録するときに、ほかのショートカットと同じキーになっていないかを確かめるために使う（Windows 版の SetHotKey と同じ）
enum ShortcutKind: CaseIterable {
    case dictation, translate, edit, meeting, highlight, repaste

    /// 設定画面での呼び名
    var title: String {
        switch self {
        case .dictation: "録音の開始／停止"
        case .translate: "翻訳して入力"
        case .edit: "選択を声で編集"
        case .meeting: "会議の記録の開始／停止"
        case .highlight: "「ここ重要」の印"
        case .repaste: "最後の結果をもう一度入力"
        }
    }

    /// 今の設定（各機能のストアから読む。DEC-COM-013）
    var current: HotKeyCombo {
        switch self {
        case .dictation: AppSettings.shared.hotKey
        case .translate: AppSettings.shared.translateHotKey
        case .edit: EditModeSettings.shared.hotKey
        case .meeting: AppSettings.shared.meetingHotKey
        case .highlight: MeetingNotesSettings.shared.highlightHotKey
        case .repaste: HistorySettings.shared.repasteHotKey
        }
    }

    /// combo が、kind 以外のショートカットと同じなら、そのショートカット
    static func conflict(_ combo: HotKeyCombo, excluding kind: ShortcutKind) -> ShortcutKind? {
        allCases.first { $0 != kind && $0.current == combo }
    }
}

// 設計判断: DEC-COM-010, DEC-COM-018
/// クリックしてからキーを押すと、そのショートカットを記録するボタン。
/// kind を渡すと、ほかのショートカットと同じキーは記録せず、どれと重なるかを下に出す。
struct ShortcutRecorder: View {
    @Binding var combo: HotKeyCombo
    var defaultCombo: HotKeyCombo = .default
    /// どのショートカットの欄か（重なりの確認に使う）。nil なら確認しない
    var kind: ShortcutKind? = nil
    var onBeginRecording: () -> Void = {}
    var onEndRecording: () -> Void = {}

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var conflictMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button(action: toggle) {
                    Text(isRecording ? "キーを押してください（Esc で取消）" : combo.displayString)
                        .frame(minWidth: 180)
                }
                .buttonStyle(.bordered)
                .tint(isRecording ? .accentColor : nil)
                if combo != defaultCombo {
                    Button("初期値に戻す") { apply(defaultCombo) }
                        .buttonStyle(.link)
                }
            }
            if let conflictMessage {
                Label(conflictMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear(perform: stop)
    }

    /// ほかのショートカットと重なっていなければ記録する。重なっていれば記録せず、どれと重なるかを出す
    private func apply(_ candidate: HotKeyCombo) {
        if let kind, let other = ShortcutKind.conflict(candidate, excluding: kind) {
            conflictMessage = "\(candidate.displayString) は「\(other.title)」のショートカットと同じです。別のキーを選んでください。"
            NSSound.beep()
            return
        }
        conflictMessage = nil
        combo = candidate
    }

    private func toggle() {
        isRecording ? stop() : start()
    }

    private func start() {
        isRecording = true
        onBeginRecording()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = Self.carbonModifiers(from: event.modifierFlags)
            if event.keyCode == UInt16(kVK_Escape), modifiers == 0 {
                stop()
                return nil
            }
            // 修飾キーなしの通常キーは文字入力を奪ってしまうので、ファンクションキー以外は受け付けない
            guard modifiers != 0 || Self.isFunctionKey(event.keyCode) else {
                NSSound.beep()
                return nil
            }
            apply(HotKeyCombo(keyCode: UInt32(event.keyCode), modifiers: modifiers))
            stop()
            return nil
        }
    }

    private func stop() {
        guard isRecording else { return }
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        onEndRecording()
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    private static func isFunctionKey(_ keyCode: UInt16) -> Bool {
        [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
         kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19]
            .contains(Int(keyCode))
    }
}
