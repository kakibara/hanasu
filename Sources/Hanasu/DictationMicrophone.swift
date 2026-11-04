import AppKit
import CoreAudio
import SwiftUI

// 要件: REQ-DIC-140
// 設計判断: DEC-DIC-140
/// 音声入力で使うマイクの選択肢（設定の「一般」と HUD のメニューで共用）
enum DictationMicrophones {
    struct Option: Equatable {
        /// 空ならシステムの設定に従う
        let uid: String
        let title: String
    }

    /// 「システムの設定に従う（今の既定のマイク）」、つながっているマイク、選んだまま外れているマイク、の順
    static func options(selected: String, inputs: [AudioDevice]) -> [Option] {
        var result = [Option(uid: "", title: systemTitle)]
        result += inputs.map { Option(uid: $0.uid, title: $0.name) }
        if !selected.isEmpty, !inputs.contains(where: { $0.uid == selected }) {
            result.append(Option(uid: selected, title: "（接続されていない機器）"))
        }
        return result
    }

    static var systemTitle: String {
        defaultInputName.map { "システムの設定に従う（\($0)）" } ?? "システムの設定に従う"
    }

    /// 今のシステムの既定の入力機器の名前
    static var defaultInputName: String? {
        guard let id = AudioDevices.defaultDevice(kAudioHardwarePropertyDefaultInputDevice) else { return nil }
        return AudioDevices.all().first { $0.id == id }?.name
    }
}

// 要件: REQ-DIC-140
/// 設定の「一般」タブの、音声入力で使うマイクの選択
struct DictationMicrophonePicker: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var devices = AudioDeviceList.shared

    var body: some View {
        Picker("マイク", selection: $settings.dictationInputDeviceUID) {
            ForEach(DictationMicrophones.options(selected: settings.dictationInputDeviceUID, inputs: devices.inputs),
                    id: \.uid) { Text($0.title).tag($0.uid) }
        }
    }
}

// 要件: REQ-DIC-140
// 設計判断: DEC-DIC-142
/// HUD のマイクのボタンから出すメニュー。前面にないパネルからでも出せるよう、NSMenu を画面の座標に出す
@MainActor
final class DictationMicrophoneMenu: NSObject {
    /// メニューを閉じるまで、項目の送り先を持っておく
    private static var current: DictationMicrophoneMenu?
    private let onSelect: (String) -> Void

    private init(onSelect: @escaping (String) -> Void) {
        self.onSelect = onSelect
    }

    static func popUp(selected: String, onSelect: @escaping (String) -> Void) {
        let handler = DictationMicrophoneMenu(onSelect: onSelect)
        current = handler
        let menu = NSMenu()
        menu.autoenablesItems = false
        let header = NSMenuItem(title: "音声入力で使うマイク", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for (index, option) in DictationMicrophones.options(selected: selected, inputs: AudioDevices.inputs).enumerated() {
            let item = NSMenuItem(title: option.title, action: #selector(choose(_:)), keyEquivalent: "")
            item.target = handler
            item.representedObject = option.uid
            item.state = option.uid == selected ? .on : .off
            menu.addItem(item)
            if index == 0 { menu.addItem(.separator()) }
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func choose(_ item: NSMenuItem) {
        guard let uid = item.representedObject as? String else { return }
        onSelect(uid)
        Self.current = nil
    }
}
