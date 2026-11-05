@preconcurrency import AVFoundation
import CoreAudio
import Foundation

enum SystemAudioTapError: LocalizedError {
    case coreAudio(String, OSStatus)
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        // 設計判断: DEC-MTG-074（許可の状態は API で取れないので、失敗したときに確かめる場所を添える）
        case .coreAudio(let call, let status):
            "システム音声を取得できませんでした（\(call): \(status)）。システム設定 → プライバシーとセキュリティ → 画面収録とシステムオーディオ録音 で Hanasu が許可されているか確かめてください。"
        case .unsupportedFormat: "システム音声の形式を読み取れませんでした"
        }
    }
}

// 要件: REQ-MTG-002, REQ-MTG-020
/// Core Audio Process Tap で、Mac が再生している音（自分のアプリ以外）を受け取る。
/// タップを集約デバイスに入れ、その入力として IOProc でバッファを受け取る。
final class SystemAudioTap {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var formatBox: FormatBox?
    private var rateListener: AudioObjectPropertyListenerBlock?
    private(set) var format: AVAudioFormat?

    // 設計判断: DEC-MTG-002
    /// - Parameter outputDeviceUID: 録音するスピーカー。nil なら Mac 全体の音（自分以外のアプリすべて）。
    /// handler はオーディオスレッドで呼ばれる。渡すバッファはコピー済みなので保持してよい。
    func start(outputDeviceUID: String? = nil, handler: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        stop()

        let excluded = Self.processObject(for: getpid()).map { [$0] } ?? []
        let description: CATapDescription
        let mainUID: String
        if let outputDeviceUID {
            description = CATapDescription(excludingProcesses: excluded, deviceUID: outputDeviceUID, stream: 0)
            description.isMono = true
            mainUID = outputDeviceUID
        } else {
            description = CATapDescription(monoGlobalTapButExcludeProcesses: excluded)
            // Mac 全体の音を録るときは、集約デバイスの時計の元（主デバイス）に内蔵スピーカーを使う。
            // 既定の出力が Bluetooth イヤホン（通話中は 16kHz）だと、届くデータは 16kHz なのに
            // 形式は 48kHz と報告され、3 倍速の聞き取れない音になるため。
            // 全体のタップなので、どの機器から出ている音も録れることは変わらない。
            guard let uid = AudioDevices.preferredClockOutputUID else {
                throw SystemAudioTapError.coreAudio("kAudioHardwarePropertyDefaultOutputDevice", -1)
            }
            mainUID = uid
        }
        description.uuid = UUID()
        description.name = "Hanasu Meeting Tap"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var tap = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateProcessTap(description, &tap), "AudioHardwareCreateProcessTap")
        tapID = tap

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Hanasu Meeting Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: mainUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: mainUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        var aggregateDevice = AudioObjectID(kAudioObjectUnknown)
        do {
            try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateDevice),
                      "AudioHardwareCreateAggregateDevice")
            aggregateID = aggregateDevice

            // タップが報告する形式（kAudioTapPropertyFormat）は 48kHz でも、集約デバイスの時計は
            // 主デバイス（Bluetooth イヤホンなら 16kHz など）に合うので、実際に届く入力の形式を使う
            let format = try Self.inputFormat(of: aggregateDevice, tap: tap)
            self.format = format
            appLog.notice("system audio tap: \(format.sampleRate, privacy: .public)Hz \(format.channelCount)ch device=\(outputDeviceUID ?? "all", privacy: .public) clock=\(mainUID, privacy: .public)")
            let currentFormat = FormatBox(format)
            formatBox = currentFormat
            // 録音中にサンプリングレートが変わったら（Bluetooth の切り替えなど）形式を読み直す
            var rateAddress = AudioDevices.address(kAudioDevicePropertyNominalSampleRate)
            let listener: AudioObjectPropertyListenerBlock = { _, _ in
                if let updated = try? Self.inputFormat(of: aggregateDevice, tap: tap) {
                    currentFormat.value = updated
                    appLog.notice("system audio tap format changed: \(updated.sampleRate, privacy: .public)Hz")
                }
            }
            AudioObjectAddPropertyListenerBlock(aggregateDevice, &rateAddress, nil, listener)
            rateListener = listener

            var procID: AudioDeviceIOProcID?
            let meter = RateMeter()
            try check(AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateDevice, nil) { now, inputData, _, _, _ in
                // 実際に届く速さを測り、形式の値と食い違えば測った値に合わせる（念のための安全策）
                if let frames = Self.frameCount(inputData, format: currentFormat.value),
                   let measured = meter.add(frames: frames, hostTime: now.pointee.mHostTime),
                   abs(measured - currentFormat.value.sampleRate) / currentFormat.value.sampleRate > 0.1,
                   let corrected = Self.format(currentFormat.value, sampleRate: measured)
                {
                    appLog.notice("system audio tap rate corrected: \(currentFormat.value.sampleRate, privacy: .public)Hz -> \(measured, privacy: .public)Hz")
                    currentFormat.value = corrected
                }
                guard let copy = Self.copyBuffer(inputData, format: currentFormat.value) else { return }
                handler(copy)
            }, "AudioDeviceCreateIOProcIDWithBlock")
            ioProcID = procID
            try check(AudioDeviceStart(aggregateDevice, procID), "AudioDeviceStart")
        } catch {
            stop()
            throw error
        }
    }

    // 設計判断: DEC-MTG-003
    /// 集約デバイスの入力（＝タップ）の実際の形式
    private static func inputFormat(of device: AudioObjectID, tap: AudioObjectID) throws -> AVAudioFormat {
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioDevices.address(kAudioDevicePropertyStreamFormat, scope: kAudioObjectPropertyScopeInput)
        if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &asbd) != noErr || asbd.mSampleRate <= 0 {
            // 取れなければタップの形式に、集約デバイスのサンプリングレートを当てはめる
            address = AudioDevices.address(kAudioTapPropertyFormat)
            size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            let status = AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &asbd)
            guard status == noErr else { throw SystemAudioTapError.coreAudio("kAudioTapPropertyFormat", status) }
            if let rate = AudioDevices.nominalSampleRate(device) { asbd.mSampleRate = rate }
        }
        guard let format = AVAudioFormat(streamDescription: &asbd) else { throw SystemAudioTapError.unsupportedFormat }
        return format
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown, let rateListener {
            var rateAddress = AudioDevices.address(kAudioDevicePropertyNominalSampleRate)
            AudioObjectRemovePropertyListenerBlock(aggregateID, &rateAddress, nil, rateListener)
        }
        rateListener = nil
        if aggregateID != kAudioObjectUnknown {
            if let ioProcID {
                AudioDeviceStop(aggregateID, ioProcID)
                AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        ioProcID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    deinit { stop() }

    // MARK: - Helpers

    private func check(_ status: OSStatus, _ call: String) throws {
        guard status == noErr else { throw SystemAudioTapError.coreAudio(call, status) }
    }

    /// バッファのフレーム数（バイト数から数えるので、サンプリングレートの値に左右されない）
    private static func frameCount(_ list: UnsafePointer<AudioBufferList>, format: AVAudioFormat) -> Int? {
        let bytesPerFrame = Int(format.streamDescription.pointee.mBytesPerFrame)
        guard bytesPerFrame > 0, list.pointee.mNumberBuffers > 0 else { return nil }
        return Int(list.pointee.mBuffers.mDataByteSize) / bytesPerFrame
    }

    private static func format(_ format: AVAudioFormat, sampleRate: Double) -> AVAudioFormat? {
        var asbd = format.streamDescription.pointee
        asbd.mSampleRate = sampleRate
        return AVAudioFormat(streamDescription: &asbd)
    }

    /// IOProc のバッファはコールバックの間しか有効でないので、自前のバッファに写す。
    private static func copyBuffer(_ source: UnsafePointer<AudioBufferList>, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let view = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: source, deallocator: nil),
              view.frameLength > 0,
              let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: view.frameLength)
        else { return nil }
        copy.frameLength = view.frameLength
        let from = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: view.audioBufferList))
        let to = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (src, dst) in zip(from, to) {
            guard let srcData = src.mData, let dstData = dst.mData else { continue }
            memcpy(dstData, srcData, Int(min(src.mDataByteSize, dst.mDataByteSize)))
        }
        return copy
    }

    static func processObject(for pid: pid_t) -> AudioObjectID? {
        var address = AudioDevices.address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var qualifier = pid
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address,
            UInt32(MemoryLayout<pid_t>.size), &qualifier, &size, &object)
        return status == noErr && object != kAudioObjectUnknown ? object : nil
    }
}

/// IOProc（オーディオスレッド）と形式の変更通知の間で、現在の形式を受け渡す入れ物
private final class FormatBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: AVAudioFormat
    init(_ value: AVAudioFormat) { _value = value }
    var value: AVAudioFormat {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

// 設計判断: DEC-MTG-003
/// IOProc に届くフレーム数と経過時間から、実際のサンプリングレートを測る（オーディオスレッドだけで使う）
private final class RateMeter: @unchecked Sendable {
    private static let standardRates: [Double] = [8000, 11025, 16000, 22050, 24000, 32000, 44100, 48000, 88200, 96000]
    private var startHostTime: UInt64 = 0
    private var frames = 0

    /// 1 秒ぶん以上たまったら、いちばん近い標準のサンプリングレートを返して数え直す
    func add(frames count: Int, hostTime: UInt64) -> Double? {
        guard hostTime > 0 else { return nil }
        if startHostTime == 0 {
            startHostTime = hostTime
            frames = 0
            return nil
        }
        frames += count
        let seconds = Double(AudioConvertHostTimeToNanos(hostTime) - AudioConvertHostTimeToNanos(startHostTime)) / 1e9
        guard seconds >= 1 else { return nil }
        let rate = Double(frames) / seconds
        startHostTime = hostTime
        frames = 0
        return Self.standardRates.min { abs($0 - rate) < abs($1 - rate) }
    }
}
