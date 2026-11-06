import CoreAudio
import SwiftUI

/// オーディオ機器の一覧。イヤホンの抜き差しなどで機器が増減したら自動で更新する。
@MainActor
final class AudioDeviceList: ObservableObject {
    static let shared = AudioDeviceList()

    @Published private(set) var outputs: [AudioDevice] = []
    @Published private(set) var inputs: [AudioDevice] = []

    private init() {
        reload()
        var address = AudioDevices.address(kAudioHardwarePropertyDevices)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { _, _ in
            MainActor.assumeIsolated { AudioDeviceList.shared.reload() }
        }
    }

    func reload() {
        outputs = AudioDevices.outputs
        inputs = AudioDevices.inputs
    }
}

// 設計判断: DEC-MTG-019
/// 会議で録音するスピーカーとマイクの選択（設定画面と会議ノートで共用）
struct MeetingDevicePickers: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var devices = AudioDeviceList.shared
    /// 会議ノートの左下のような狭い場所向け（見出しを上に置く）
    var compact = false

    var body: some View {
        if compact {
            VStack(alignment: .leading, spacing: 6) {
                labeled(tr("スピーカー"), systemImage: "speaker.wave.2") { outputPicker.labelsHidden() }
                labeled(tr("マイク"), systemImage: "mic") { inputPicker.labelsHidden() }
            }
        } else {
            outputPicker
            inputPicker
        }
    }

    private var outputPicker: some View {
        Picker(tr("録音するスピーカー"), selection: $settings.meetingOutputDeviceUID) {
            Text(tr("Mac 全体の音（おすすめ）")).tag("")
            ForEach(devices.outputs) { Text($0.name).tag($0.uid) }
            if isMissing(settings.meetingOutputDeviceUID, in: devices.outputs) {
                Text(tr("（接続されていない機器）")).tag(settings.meetingOutputDeviceUID)
            }
        }
    }

    private var inputPicker: some View {
        Picker(tr("録音するマイク"), selection: $settings.meetingInputDeviceUID) {
            Text(tr("システムの設定に従う")).tag("")
            ForEach(devices.inputs) { Text($0.name).tag($0.uid) }
            if isMissing(settings.meetingInputDeviceUID, in: devices.inputs) {
                Text(tr("（接続されていない機器）")).tag(settings.meetingInputDeviceUID)
            }
        }
    }

    private func isMissing(_ uid: String, in list: [AudioDevice]) -> Bool {
        !uid.isEmpty && !list.contains { $0.uid == uid }
    }

    private func labeled(_ title: String, systemImage: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
