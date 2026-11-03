import AppKit
import Combine
import SwiftUI
import CoreAudio
import Foundation

/// 会議の自動検出を確かめるための CLI モード（main.swift から呼ぶ）
@MainActor
enum MeetingDetectorCLI {
    /// --list-audio-processes: 今 Core Audio にいるプロセスの一覧（bundle ID、入力中か・出力中か、会議アプリか）
    static func listProcesses() {
        let processes = AudioProcesses.all().sorted { ($0.isRunningInput ? 0 : 1, $0.bundleID) < ($1.isRunningInput ? 0 : 1, $1.bundleID) }
        print("PID\t入力\t出力\t会議アプリ\tbundle ID（アプリ本体）")
        for p in processes { print(line(p)) }
        let active = Set(processes.filter { $0.isRunningInput && $0.pid != getpid() }.compactMap(\.meetingApp))
        print("プロセス \(processes.count) 件 / マイクを使っている会議アプリ: "
              + (active.isEmpty ? "なし" : MeetingApp.allCases.filter(active.contains).map(\.label).joined(separator: ", ")))
    }

    /// --watch-audio-processes: プロパティリスナーで変化を待ち、変わったときだけ表示する（Ctrl-C で終了）
    static func watch() {
        setlinebuf(stdout)  // パイプに流しても 1 行ずつ出す
        let watcher = ProcessWatcher()
        watcher.start()
        let detector = MeetingDetector()
        detector.onChange = { apps in
            print("\(timestamp()) [検出] マイクを使っている会議アプリ: "
                  + (apps.isEmpty ? "なし" : MeetingApp.allCases.filter(apps.contains).map(\.label).joined(separator: ", ")))
        }
        detector.start()
        print("\(timestamp()) 監視を始めました（Ctrl-C で終了）")
        withExtendedLifetime((watcher, detector)) { RunLoop.main.run() }
    }

    /// --render-meeting-suggestion <png> [--stop] [--app <zoom|chrome|…>]: 提案のパネルを PNG にする
    static func renderSuggestion(to path: String, args: [String]) {
        _ = NSApplication.shared
        let appName = args.firstIndex(of: "--app").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        let app = appName.flatMap(MeetingApp.init(rawValue:)) ?? .zoom
        let suggestion: MeetingSuggestionPanel.Suggestion = args.contains("--stop")
            ? .stop(app, startedAt: Date().addingTimeInterval(-(32 * 60 + 15)))
            : .start(app)
        let panel = MeetingSuggestionPanel()
        if let data = panel.snapshotPNG(suggestion) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("wrote")
        }
    }

    /// --simulate-meeting-detection: 検出と記録の状態を台本どおりに動かし、提案が出る・消える時刻を表示する。
    /// 待ち時間は短くしてある（開始の提案 0.5 秒、停止の提案 1 秒、「今回はしない」を忘れるまで 2 秒）。
    static func simulate() {
        setlinebuf(stdout)
        _ = NSApplication.shared
        // App Nap でタイマーがまとめられて時刻がずれないようにする
        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "simulation")
        let state = CurrentValueSubject<MeetingRecorder.State, Never>(.idle)
        var startedAt: Date?
        let detector = MeetingDetector(simulated: true)
        let auto = MeetingAutoDetect(
            detector: detector,
            state: state.eraseToAnyPublisher(),
            currentState: { state.value },
            recordingStartedAt: { startedAt },
            startRecording: {
                print("  → 記録を開始")
                state.send(.starting)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { startedAt = Date(); state.send(.recording) }
            },
            stopRecording: {
                print("  → 記録を停止")
                state.send(.processing("議事録を作っています…"))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { state.send(.idle) }
            },
            timing: .init(startDelay: 0.5, stopDelay: 1, declineGrace: 2))
        auto.panel.isHeadless = true
        let began = Date()
        func stamp() -> String { String(format: "%5.2fs", Date().timeIntervalSince(began)) }
        auto.onSuggestionChange = { suggestion in
            switch suggestion {
            case .start(let app)?: print("\(stamp()) [提案] 会議を記録しますか？（\(app.label)）")
            case .stop(let app, _)?: print("\(stamp()) [提案] 記録を止めますか？（\(app.label)）")
            case nil: print("\(stamp()) [提案] 消えた")
            }
        }

        typealias Step = (TimeInterval, String, () -> Void)
        let press: (MeetingSuggestionPanel.Action) -> Void = { action in auto.panel.onAction?(action) }
        let steps: [Step] = [
            (0.0, "Zoom がマイクを使い始める", { detector.simulate([.zoom]) }),
            (1.5, "「今回はしない」を押す", { press(.dismiss) }),
            (2.0, "Zoom がマイクを止める（ミュートなど）", { detector.simulate([]) }),
            (2.6, "Zoom がまたマイクを使う（止めてから 2 秒以内なので聞かない）", { detector.simulate([.zoom]) }),
            (3.5, "Zoom がマイクを止める", { detector.simulate([]) }),
            (6.5, "Chrome がマイクを使い始める", { detector.simulate([.chrome]) }),
            (8.0, "「記録する」を押す", { press(.accept) }),
            (8.5, "Chrome がマイクを止める", { detector.simulate([]) }),
            (10.5, "「記録を止める」を押す", { press(.accept) }),
            (11.5, "ショートカットで記録を始める（Zoom はマイクを使用中）", {
                detector.simulate([.zoom]); startedAt = Date(); state.send(.recording)
            }),
            (12.0, "Zoom がマイクを止める", { detector.simulate([]) }),
            (12.5, "Zoom がまたマイクを使う（停止の提案は出る前に取り消す）", { detector.simulate([.zoom]) }),
            (13.0, "Zoom がマイクを止める", { detector.simulate([]) }),
            (15.0, "「続ける」を押す", { press(.dismiss) }),
            (15.5, "Zoom がマイクを使う", { detector.simulate([.zoom]) }),
            (16.5, "ショートカットで記録を止める（Zoom はマイクを使用中）", {
                state.send(.processing("…"))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { state.send(.idle) }
            }),
            (18.0, "Teams もマイクを使い始める", { detector.simulate([.zoom, .teams]) }),
            (19.5, "終了", { exit(0) }),
        ]
        // DispatchQueue.asyncAfter は待ち時間に比例して遅れてよいことになっているので、時刻を指定した Timer を使う
        for (time, label, action) in steps {
            let timer = Timer(fire: began.addingTimeInterval(time), interval: 0, repeats: false) { _ in
                print("\(stamp()) \(label)")
                action()
            }
            timer.tolerance = 0
            RunLoop.main.add(timer, forMode: .common)
        }
        withExtendedLifetime((auto, activity)) { RunLoop.main.run() }
    }

    /// --render-meeting-detection-settings <png>: 設定の「会議の自動検出」欄を PNG にする
    static func renderSettings(to path: String) {
        _ = NSApplication.shared
        let view = Form { MeetingDetectionSettingsSection() }
            .formStyle(.grouped)
            .frame(width: 560, height: 440)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 560, height: 440)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            print("wrote")
        }
    }

    fileprivate static func line(_ p: AudioProcessInfo) -> String {
        let app = p.appBundleID.flatMap { $0 == p.bundleID ? nil : $0 }
        return "\(p.pid)\t\(p.isRunningInput ? "●" : "-")\t\(p.isRunningOutput ? "●" : "-")"
            + "\t\(p.meetingApp?.rawValue ?? (p.pid == getpid() ? "(Hanasu)" : "-"))"
            + "\t\(p.bundleID.isEmpty ? "(なし)" : p.bundleID)\(app.map { "（\($0)）" } ?? "")"
    }

    fileprivate static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
}

/// すべてのプロセスの入力中・出力中の変化を表示する（リスナーが届くかの確認用）
@MainActor
private final class ProcessWatcher {
    private var last: [AudioObjectID: AudioProcessInfo] = [:]
    private var listeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private static let selectors = [kAudioProcessPropertyIsRunning, kAudioProcessPropertyIsRunningInput, kAudioProcessPropertyIsRunningOutput]

    func start() {
        var address = AudioDevices.address(kAudioHardwarePropertyProcessObjectList)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.sync() }
        }
        for p in AudioProcesses.all() { last[p.id] = p }
        sync()
    }

    private func sync() {
        let ids = Set(AudioProcesses.objectIDs())
        for (id, p) in last where !ids.contains(id) {
            print("\(MeetingDetectorCLI.timestamp()) [減] \(MeetingDetectorCLI.line(p))")
            last[id] = nil
            listeners[id] = nil
        }
        for id in ids where listeners[id] == nil {
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.refresh(id) }
            }
            for selector in Self.selectors {
                var address = AudioDevices.address(selector)
                AudioObjectAddPropertyListenerBlock(id, &address, .main, listener)
            }
            listeners[id] = listener
            if last[id] == nil, let p = AudioProcesses.info(id) {
                print("\(MeetingDetectorCLI.timestamp()) [増] \(MeetingDetectorCLI.line(p))")
                last[id] = p
            }
        }
    }

    private func refresh(_ id: AudioObjectID) {
        guard let p = AudioProcesses.info(id), p != last[id] else { return }
        print("\(MeetingDetectorCLI.timestamp()) [変] \(MeetingDetectorCLI.line(p))")
        last[id] = p
    }
}
