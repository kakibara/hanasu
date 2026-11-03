import CoreAudio
import Foundation

/// Mac のオーディオ機器（スピーカー・マイク）
struct AudioDevice: Identifiable, Hashable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let inputChannels: Int
    let outputChannels: Int
}

// 設計判断: DEC-MTG-019
enum AudioDevices {
    static func all() -> [AudioDevice] {
        var address = Self.address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard let uid = string(id, kAudioDevicePropertyDeviceUID), let name = string(id, kAudioObjectPropertyName) else { return nil }
            // 自分で作った集約デバイスは一覧に出さない
            if name.hasPrefix("Hanasu ") { return nil }
            return AudioDevice(id: id, uid: uid, name: name,
                               inputChannels: channels(id, kAudioObjectPropertyScopeInput),
                               outputChannels: channels(id, kAudioObjectPropertyScopeOutput))
        }
    }

    static var outputs: [AudioDevice] { all().filter { $0.outputChannels > 0 } }
    static var inputs: [AudioDevice] { all().filter { $0.inputChannels > 0 } }

    static func device(uid: String) -> AudioDevice? {
        all().first { $0.uid == uid }
    }

    static func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioObjectID? {
        var address = Self.address(selector)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    static var defaultOutputUID: String? {
        defaultDevice(kAudioHardwarePropertyDefaultOutputDevice).flatMap { string($0, kAudioDevicePropertyDeviceUID) }
    }

    /// 集約デバイスの時計の元にする出力機器。内蔵スピーカーがあればそれ（Bluetooth のように
    /// 通話中にサンプリングレートが変わらない）、なければ既定の出力。
    static var preferredClockOutputUID: String? {
        outputs.first { $0.uid == "BuiltInSpeakerDevice" }?.uid ?? defaultOutputUID
    }

    static func nominalSampleRate(_ device: AudioObjectID) -> Double? {
        var address = Self.address(kAudioDevicePropertyNominalSampleRate)
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &rate) == noErr && rate > 0 ? rate : nil
    }

    // MARK: - Private

    static func address(_ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func channels(_ device: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Int {
        var address = address(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        let list = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, list) == noErr else { return 0 }
        return UnsafeMutableAudioBufferListPointer(list).reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
