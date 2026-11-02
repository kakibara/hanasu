import AppKit
import Carbon.HIToolbox
import SwiftUI

/// クリックしてからキーを押すと、そのショートカットを記録するボタン。
struct ShortcutRecorder: View {
    @Binding var combo: HotKeyCombo
    var defaultCombo: HotKeyCombo = .default
    var onBeginRecording: () -> Void = {}
    var onEndRecording: () -> Void = {}

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Button(action: toggle) {
                Text(isRecording ? "キーを押してください（Esc で取消）" : combo.displayString)
                    .frame(minWidth: 180)
            }
            .buttonStyle(.bordered)
            .tint(isRecording ? .accentColor : nil)
            if combo != defaultCombo {
                Button("初期値に戻す") { combo = defaultCombo }
                    .buttonStyle(.link)
            }
        }
        .onDisappear(perform: stop)
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
            combo = HotKeyCombo(keyCode: UInt32(event.keyCode), modifiers: modifiers)
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
