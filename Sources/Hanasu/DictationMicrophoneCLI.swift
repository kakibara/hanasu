@preconcurrency import AVFoundation
import AppKit
import SwiftUI

// 音声入力のマイクの確認:
//   Hanasu --list-dictation-microphones              HUD のメニュー・設定に出る選択肢（✓ が今の選択）
//   Hanasu --render-dictation-mic-settings <出力.png>  設定の「一般」タブの「マイク」欄を PNG にする
//   Hanasu --test-dictation-mic-switch [秒]           つながっているマイクへ順に切り替えて、それぞれ音声が届くかを数える
//                                                     （録音中の切り替えと同じ関数を使う。マイクの許可が要る）
//   Hanasu --test-dictation-level [秒] [--engine apple|whisper|gemini]
//                                                     音声入力と同じ経路で録音し、HUD に渡る音量（0.1 秒ごと）を数える
//                                                     （既定は 3 秒・Mac 標準。マイクの許可が要る。話しかけると最大が上がる）
// -dictationInputDeviceUID <UID> は UserDefaults の引数で、その回だけ選択を上書きする（保存しない）。
// 確かめ方: REQ-DIC-140, REQ-DIC-014
@MainActor
enum DictationMicrophoneCLI {
    static func runIfRequested() {
        let args = CommandLine.arguments
        if args.contains("--list-dictation-microphones") {
            let selected = AppSettings.shared.dictationInputDeviceUID
            for option in DictationMicrophones.options(selected: selected, inputs: AudioDevices.inputs) {
                print("\(option.uid == selected ? "✓" : " ") \(option.title)\t\(option.uid.isEmpty ? "-" : option.uid)")
            }
            exit(0)
        }
        if let index = args.firstIndex(of: "--render-dictation-mic-settings"), args.indices.contains(index + 1) {
            renderSettings(to: URL(fileURLWithPath: args[index + 1]))
            exit(0)
        }
        if let index = args.firstIndex(of: "--test-dictation-mic-switch") {
            let seconds = args.indices.contains(index + 1) ? Double(args[index + 1]) ?? 0.6 : 0.6
            exit(testSwitch(seconds: seconds) ? 0 : 1)
        }
        if let index = args.firstIndex(of: "--test-dictation-level") {
            let seconds = args.indices.contains(index + 1) ? Double(args[index + 1]) ?? 3 : 3
            let (engine, _) = TranscriptionEngineCLI.parseEngine(args)
            Task { @MainActor in exit(await testLevel(seconds: seconds, transcription: engine) ? 0 : 1) }
            RunLoop.main.run()
        }
    }

    // 確かめ方: REQ-DIC-014
    /// 音声入力と同じく SpeechRecognizer で録音し、onLevel に届いた音量を数える。1 回も届かなければ false
    private static func testLevel(seconds: Double, transcription: TranscriptionEngine) async -> Bool {
        let settings = AppSettings.shared
        let recognizer = SpeechRecognizer()
        var levels: [Float] = []
        recognizer.onLevel = { levels.append($0) }
        do {
            try await recognizer.start(localeIdentifier: settings.localeIdentifier, engine: settings.engine,
                                       contextualStrings: [], transcription: transcription,
                                       inputDeviceUID: settings.dictationInputDeviceUID)
        } catch {
            print("✗ 録音を始められません: \(error.localizedDescription)")
            return false
        }
        try? await Task.sleep(for: .seconds(seconds))
        await recognizer.cancel()
        let peak = levels.max() ?? 0
        let db = 20 * log10(max(Double(peak), 1e-6))
        print(String(format: "%@ %@: 音量 %d 回 / 最大 %.4f（%.1f dB）",
                     levels.isEmpty ? "✗" : "✓", transcription.shortName, levels.count, peak, db))
        return !levels.isEmpty
    }

    /// 設定の「一般」タブの「マイク」欄を PNG にする
    private static func renderSettings(to url: URL) {
        _ = NSApplication.shared
        let view = Form {
            Section {
                DictationMicrophonePicker()
            } header: {
                Text("マイク")
            } footer: {
                Text("音声入力と「選択を声で編集」で使うマイク。録音中の画面（HUD）のマイクのボタンからも切り替えられます。会議の記録のマイクは「会議」タブで選びます。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 160)
        .background(Color(nsColor: .windowBackgroundColor))
        // メニュー型の Picker は AppKit の部品なので、画面外のウインドウに置いて描く
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 560, height: 160)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            print("wrote \(url.path)")
        }
    }

    /// システムの設定 → つながっている各マイク → つながっていない UID の順に、録音を止めずに切り替える。
    /// どれかで切り替えに失敗したら false
    private static func testSwitch(seconds: Double) -> Bool {
        let counter = FrameCounter()
        let makeTap = { (format: AVAudioFormat) -> AVAudioNodeTapBlock in
            counter.reset(format: format)
            return { buffer, _ in counter.add(buffer) }
        }
        let targets = [""] + AudioDevices.inputs.map(\.uid) + ["Hanasu-test-missing-device"]
        var engine: AVAudioEngine?
        var ok = true
        for uid in targets {
            engine?.inputNode.removeTap(onBus: 0)
            engine?.stop()
            do {
                engine = try SpeechRecognizer.startInputWithFallback(uid: uid, makeTap: makeTap)
            } catch {
                print("✗ \(uid.isEmpty ? "（システムの設定）" : uid): \(error.localizedDescription)")
                ok = false
                engine = nil
                continue
            }
            RunLoop.main.run(until: Date().addingTimeInterval(seconds))
            let (frames, peak, format) = counter.snapshot
            print(String(format: "%@ %@: %@ %d フレーム / 最大 %.4f",
                         frames > 0 ? "✓" : "?", uid.isEmpty ? "（システムの設定）" : uid,
                         format.map { "\(Int($0.sampleRate))Hz \($0.channelCount)ch" } ?? "-", frames, peak))
        }
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        return ok
    }
}

/// オーディオスレッドから届いたフレーム数と最大の振幅を数える
private final class FrameCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var frames = 0
    private var peak: Float = 0
    private var format: AVAudioFormat?

    func reset(format: AVAudioFormat) {
        lock.withLock {
            frames = 0
            peak = 0
            self.format = format
        }
    }

    func add(_ buffer: AVAudioPCMBuffer) {
        var bufferPeak: Float = 0
        if let data = buffer.floatChannelData?[0] {
            for i in 0..<Int(buffer.frameLength) { bufferPeak = max(bufferPeak, abs(data[i])) }
        }
        lock.withLock {
            frames += Int(buffer.frameLength)
            peak = max(peak, bufferPeak)
        }
    }

    var snapshot: (Int, Float, AVAudioFormat?) { lock.withLock { (frames, peak, format) } }
}
