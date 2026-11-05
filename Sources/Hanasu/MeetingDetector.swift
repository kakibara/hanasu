import AppKit
import Combine
import CoreAudio
import Foundation

// 会議の自動検出: 会議アプリがマイクを使い始めたら「会議を記録しますか？」と提案する。
// 記録は必ずユーザーがボタンを押してから始める（自動では始めない）。

// 設計判断: DEC-MTG-031
/// 検出の対象にする会議アプリ
enum MeetingApp: String, CaseIterable, Identifiable {
    case zoom, teams, slack, webex, facetime
    case chrome, safari, arc, edge

    var id: String { rawValue }

    var label: String {
        switch self {
        case .zoom: "Zoom"
        case .teams: "Microsoft Teams"
        case .slack: tr("Slack（ハドル）")
        case .webex: "Webex"
        case .facetime: "FaceTime"
        case .chrome: "Google Chrome"
        case .safari: "Safari"
        case .arc: "Arc"
        case .edge: "Microsoft Edge"
        }
    }

    /// ブラウザは会議（Google Meet など）かどうかまでは分からないので、「かもしれない」と扱う
    var isBrowser: Bool {
        switch self {
        case .chrome, .safari, .arc, .edge: true
        default: false
        }
    }

    /// アプリの bundle ID の先頭。ヘルパー（com.google.Chrome.helper など）も同じ先頭で当たる
    var bundlePrefixes: [String] {
        switch self {
        case .zoom: ["us.zoom."]
        case .teams: ["com.microsoft.teams"]
        case .slack: ["com.tinyspeck.slackmacgap"]
        case .webex: ["com.cisco.webex", "cisco-systems.spark", "com.webex."]
        // FaceTime の通話の音声は avconferenced（システムのデーモン）が扱う
        case .facetime: ["com.apple.facetime", "com.apple.avconferenced"]
        case .chrome: ["com.google.chrome"]
        // Safari のマイクは WebKit の GPU プロセスが扱う（ほかの WebKit を使うアプリと区別できない）
        case .safari: ["com.apple.safari", "com.apple.webkit.gpu"]
        case .arc: ["company.thebrowser."]
        case .edge: ["com.microsoft.edgemac"]
        }
    }

    /// アイコンを出すためのアプリ本体の bundle ID
    var mainBundleID: String {
        switch self {
        case .zoom: "us.zoom.xos"
        case .teams: "com.microsoft.teams2"
        case .slack: "com.tinyspeck.slackmacgap"
        case .webex: "Cisco-Systems.Spark"
        case .facetime: "com.apple.FaceTime"
        case .chrome: "com.google.Chrome"
        case .safari: "com.apple.Safari"
        case .arc: "company.thebrowser.Browser"
        case .edge: "com.microsoft.edgemac"
        }
    }

    static func matching(_ bundleIDs: [String]) -> MeetingApp? {
        let lowered = bundleIDs.map { $0.lowercased() }.filter { !$0.isEmpty }
        return allCases.first { app in
            app.bundlePrefixes.contains { prefix in lowered.contains { $0.hasPrefix(prefix) } }
        }
    }
}

// 設計判断: DEC-MTG-034
/// 自動検出の設定。共有の AppSettings を大きく変えないよう、ここに分けて持つ
final class MeetingDetectionSettings: ObservableObject {
    static let shared = MeetingDetectionSettings()

    private let defaults = UserDefaults.standard

    /// 会議アプリがマイクを使い始めたら記録を提案する
    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: Keys.enabled) } }
    /// 提案しないアプリ（rawValue）。新しく対象を足したときに既定で入るよう、外したものを持つ
    @Published var disabledApps: Set<String> {
        didSet { defaults.set(disabledApps.sorted(), forKey: Keys.disabledApps) }
    }

    func isEnabled(_ app: MeetingApp) -> Bool { !disabledApps.contains(app.rawValue) }

    func setEnabled(_ app: MeetingApp, _ on: Bool) {
        if on { disabledApps.remove(app.rawValue) } else { disabledApps.insert(app.rawValue) }
    }

    private init() {
        // 既定はオン。提案するだけで勝手に録音はしないうえ、記録の始め忘れを防ぐのが目的なので
        defaults.register(defaults: [Keys.enabled: true, Keys.disabledApps: [String]()])
        enabled = defaults.bool(forKey: Keys.enabled)
        disabledApps = Set(defaults.stringArray(forKey: Keys.disabledApps) ?? [])
    }

    private enum Keys {
        static let enabled = "meetingAutoDetect"
        static let disabledApps = "meetingAutoDetectDisabledApps"
    }
}

// MARK: - Core Audio のプロセスオブジェクト

/// Core Audio に登録されているプロセス（オーディオを使っている／使ったことのあるアプリ）
struct AudioProcessInfo: Hashable {
    let id: AudioObjectID
    let pid: pid_t
    /// プロセス自身の bundle ID（ヘルパーなら com.google.Chrome.helper など）
    let bundleID: String
    /// そのプロセスを含むアプリ本体（いちばん外側の .app）の bundle ID
    let appBundleID: String?
    let isRunningInput: Bool
    let isRunningOutput: Bool

    var meetingApp: MeetingApp? { MeetingApp.matching([bundleID, appBundleID ?? ""]) }
}

enum AudioProcesses {
    static func objectIDs() -> [AudioObjectID] {
        var address = AudioDevices.address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    static func all() -> [AudioProcessInfo] {
        objectIDs().compactMap(info)
    }

    static func info(_ id: AudioObjectID) -> AudioProcessInfo? {
        guard let pid = pid(id) else { return nil }
        return AudioProcessInfo(
            id: id, pid: pid, bundleID: bundleID(id) ?? "", appBundleID: appBundleID(pid: pid),
            isRunningInput: flag(id, kAudioProcessPropertyIsRunningInput),
            isRunningOutput: flag(id, kAudioProcessPropertyIsRunningOutput))
    }

    static func pid(_ id: AudioObjectID) -> pid_t? {
        var address = AudioDevices.address(kAudioProcessPropertyPID)
        var pid: pid_t = -1
        var size = UInt32(MemoryLayout<pid_t>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &pid) == noErr && pid > 0 ? pid : nil
    }

    static func bundleID(_ id: AudioObjectID) -> String? {
        var address = AudioDevices.address(kAudioProcessPropertyBundleID)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    /// UInt32 の真偽値のプロパティ（プロセスにも機器にも使う）
    static func flag(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool {
        var address = AudioDevices.address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr && value != 0
    }

    // 設計判断: DEC-MTG-031
    /// 実行ファイルのパスから、いちばん外側の .app の bundle ID を求める。
    /// Chrome や Slack はマイクをヘルパー（…/Google Chrome.app/…/Google Chrome Helper.app）で使うので、本体に戻す。
    static func appBundleID(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = String(cString: buffer)
        guard let range = path.range(of: ".app/") else { return nil }
        let appPath = String(path[..<range.lowerBound]) + ".app"
        return Bundle(path: appPath)?.bundleIdentifier
    }
}

// MARK: - 検出

// 要件: REQ-MTG-009
// 設計判断: DEC-MTG-030
/// 会議アプリのマイクの使用を見張る。
/// 基本は Core Audio のプロパティリスナーで、変化があったときだけ読む（マイクを誰も使っていない間は CPU を使わない）。
/// - システムオブジェクトの kAudioHardwarePropertyProcessObjectList: プロセスが増えた・減った
/// - 会議アプリのプロセスごとの kAudioProcessPropertyIsRunning（と IsRunningInput）: 音声の入出力を始めた・止めた
/// - 入力機器ごとの kAudioDevicePropertyDeviceIsRunningSomewhere: どこかのアプリがマイクを使い始めた・止めた
///
/// macOS 26 で試したところ、IsRunningInput / IsRunningOutput の変化はリスナーに届かず、IsRunning だけが届いた。
/// IsRunning は「入力か出力のどちらか」なので、すでに音を鳴らしているブラウザがマイクを使い始めても変わらない。
/// そこで、マイクがどこかで使われている間だけ（入力機器の IsRunningSomewhere が 1 の間だけ）数秒おきに読み直す。
@MainActor
final class MeetingDetector {
    /// マイクが使われている間に読み直す間隔
    static let pollInterval: TimeInterval = 3

    /// マイクを使っている会議アプリ（設定で外したものも含む）が変わったとき
    var onChange: ((Set<MeetingApp>) -> Void)?
    private(set) var activeApps: Set<MeetingApp> = []

    private var systemListener: AudioObjectPropertyListenerBlock?
    private var processListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var processApps: [AudioObjectID: MeetingApp] = [:]
    private var deviceListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    /// 会議アプリでないと分かったプロセス（毎回パスを調べ直さない）
    private var ignored: Set<AudioObjectID> = []
    private var pollTimer: Timer?
    private let ownPID = getpid()

    private static let systemSelectors = [kAudioHardwarePropertyProcessObjectList, kAudioHardwarePropertyDevices]
    private static let processSelectors = [kAudioProcessPropertyIsRunning, kAudioProcessPropertyIsRunningInput]

    var isRunning: Bool { systemListener != nil }
    /// CLI の確認用。Core Audio を見ず、simulate(_:) で渡した状態を使う
    private let simulated: Bool

    init(simulated: Bool = false) {
        self.simulated = simulated
    }

    /// CLI の確認用: マイクを使っている会議アプリを外から与える
    func simulate(_ apps: Set<MeetingApp>) {
        guard simulated, apps != activeApps else { return }
        activeApps = apps
        onChange?(apps)
    }

    func start() {
        guard systemListener == nil, !simulated else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.sync() }
        }
        for selector in Self.systemSelectors {
            var address = AudioDevices.address(selector)
            let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
            if status != noErr { appLog.error("meeting detector: listener failed \(status)") }
        }
        systemListener = listener
        sync()
        appLog.notice("meeting detector started")
    }

    func stop() {
        if let systemListener {
            for selector in Self.systemSelectors {
                var address = AudioDevices.address(selector)
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, systemListener)
            }
        }
        systemListener = nil
        for id in Array(processListeners.keys) { removeProcessListener(id) }
        for (id, listener) in deviceListeners {
            var address = AudioDevices.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
            AudioObjectRemovePropertyListenerBlock(id, &address, .main, listener)
        }
        deviceListeners = [:]
        processApps = [:]
        ignored = []
        if !simulated { update() }
    }

    /// プロセスと入力機器の一覧に合わせて、リスナーを付け外しする
    private func sync() {
        syncDevices()
        let ids = Set(AudioProcesses.objectIDs())
        for id in processListeners.keys where !ids.contains(id) { removeProcessListener(id) }
        ignored.formIntersection(ids)
        for id in ids where processListeners[id] == nil && !ignored.contains(id) {
            guard let pid = AudioProcesses.pid(id), pid != ownPID,  // Hanasu 自身（音声入力・会議の記録）は除く
                  let app = MeetingApp.matching([AudioProcesses.bundleID(id) ?? "", AudioProcesses.appBundleID(pid: pid) ?? ""])
            else {
                ignored.insert(id)
                continue
            }
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.update() }
            }
            for selector in Self.processSelectors {
                var address = AudioDevices.address(selector)
                AudioObjectAddPropertyListenerBlock(id, &address, .main, listener)
            }
            processListeners[id] = listener
            processApps[id] = app
        }
        update()
    }

    private func syncDevices() {
        let inputs = Set(AudioDevices.inputs.map(\.id))
        for (id, listener) in deviceListeners where !inputs.contains(id) {
            var address = AudioDevices.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
            AudioObjectRemovePropertyListenerBlock(id, &address, .main, listener)
            deviceListeners[id] = nil
        }
        for id in inputs where deviceListeners[id] == nil {
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.update() }
            }
            var address = AudioDevices.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
            if AudioObjectAddPropertyListenerBlock(id, &address, .main, listener) == noErr {
                deviceListeners[id] = listener
            }
        }
    }

    private func removeProcessListener(_ id: AudioObjectID) {
        if let listener = processListeners.removeValue(forKey: id) {
            for selector in Self.processSelectors {
                var address = AudioDevices.address(selector)
                AudioObjectRemovePropertyListenerBlock(id, &address, .main, listener)
            }
        }
        processApps[id] = nil
    }

    private func update() {
        let active = Set(processApps.compactMap { id, app in
            AudioProcesses.flag(id, kAudioProcessPropertyIsRunningInput) ? app : nil
        })
        updatePolling()
        guard active != activeApps else { return }
        appLog.notice("meeting detector: mic in use by \(active.map(\.rawValue).sorted().joined(separator: ","), privacy: .public)")
        activeApps = active
        onChange?(active)
    }

    /// マイクがどこかで使われている間だけ、数秒おきに読み直す
    private func updatePolling() {
        let micInUse = isRunning && deviceListeners.keys.contains {
            AudioProcesses.flag($0, kAudioDevicePropertyDeviceIsRunningSomewhere)
        }
        if micInUse, pollTimer == nil {
            let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            }
            timer.tolerance = 1
            RunLoop.main.add(timer, forMode: .common)
            pollTimer = timer
        } else if !micInUse, let pollTimer {
            pollTimer.invalidate()
            self.pollTimer = nil
        }
    }
}

// MARK: - 提案

// 要件: REQ-MTG-009
/// 検出結果と記録の状態から、記録の開始・停止を提案する
@MainActor
final class MeetingAutoDetect {
    // 設計判断: DEC-MTG-032
    struct Timing {
        /// マイクを使い始めてから提案するまで（一瞬だけマイクを確かめるアプリで出さないため）
        var startDelay: TimeInterval = 3
        /// マイクを止めてから停止を提案するまで（ミュートや機器の切り替えで一時的に止まることがあるため）
        var stopDelay: TimeInterval = 15
        /// 「今回はしない」を、マイクを止めてからどれだけ覚えておくか
        var declineGrace: TimeInterval = 60
    }

    /// 提案を出した・消したとき（CLI の確認用）
    var onSuggestionChange: ((MeetingSuggestionPanel.Suggestion?) -> Void)?

    private let timing: Timing
    private let currentState: () -> MeetingRecorder.State
    private let recordingStartedAt: () -> Date?
    private let startRecording: () -> Void
    private let stopRecording: () -> Void
    private let settings = MeetingDetectionSettings.shared
    let detector: MeetingDetector
    let panel = MeetingSuggestionPanel()
    private var cancellables: Set<AnyCancellable> = []

    private var startTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    private var declined: Set<MeetingApp> = []
    private var declineExpiry: [MeetingApp: Task<Void, Never>] = [:]
    /// 記録中にマイクを使っていた会議アプリ（すべて止まったら停止を提案する）
    private var seenWhileRecording: Set<MeetingApp> = []
    private var lastState: MeetingRecorder.State = .idle

    /// - Parameter startRecording: 「記録する」を押したとき（会議ノートを開いて記録を始める）
    convenience init(recorder: MeetingRecorder, startRecording: @escaping () -> Void) {
        self.init(
            state: recorder.$state.eraseToAnyPublisher(),
            currentState: { [unowned recorder] in recorder.state },
            recordingStartedAt: { [unowned recorder] in recorder.current?.startedAt },
            startRecording: startRecording,
            stopRecording: { [unowned recorder] in if recorder.state == .recording { recorder.toggle() } })
    }

    init(detector: MeetingDetector? = nil,
         state: AnyPublisher<MeetingRecorder.State, Never>,
         currentState: @escaping () -> MeetingRecorder.State,
         recordingStartedAt: @escaping () -> Date?,
         startRecording: @escaping () -> Void,
         stopRecording: @escaping () -> Void,
         timing: Timing = Timing())
    {
        self.detector = detector ?? MeetingDetector()
        self.currentState = currentState
        self.recordingStartedAt = recordingStartedAt
        self.startRecording = startRecording
        self.stopRecording = stopRecording
        self.timing = timing
        self.detector.onChange = { [weak self] _ in self?.evaluate() }
        panel.onAction = { [weak self] action in self?.handle(action) }

        settings.$enabled
            .removeDuplicates()
            .sink { [weak self] on in
                guard let self else { return }
                if on { self.detector.start() } else { self.detector.stop(); self.reset() }
            }
            .store(in: &cancellables)
        settings.$disabledApps
            .dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.evaluate() } }
            .store(in: &cancellables)
        state
            .removeDuplicates()
            .sink { [weak self] state in DispatchQueue.main.async { self?.recorderStateChanged(state) } }
            .store(in: &cancellables)
    }

    /// 設定でオンにしている対象のうち、マイクを使っているもの
    private var activeTargets: Set<MeetingApp> {
        detector.activeApps.filter(settings.isEnabled)
    }

    private func recorderStateChanged(_ state: MeetingRecorder.State) {
        defer { lastState = state }
        // 記録を終えた（または始められなかった）とき、まだマイクを使っている会議アプリには改めて聞かない
        if state == .idle, lastState != .idle {
            declined.formUnion(detector.activeApps)
        }
        switch state {
        case .starting, .recording:
            // 準備中（数秒かかる）にマイクを止めたアプリも、停止を提案する対象にする
            seenWhileRecording.formUnion(activeTargets)
        case .idle, .processing:
            seenWhileRecording = []
            stopTask?.cancel()
            stopTask = nil
            if panel.kind == .stop { hidePanel() }
        }
        if state != .idle, panel.kind == .start { hidePanel() }
        evaluate()
    }

    // 設計判断: DEC-MTG-032
    private func evaluate() {
        let active = activeTargets
        // マイクを止めたアプリの「今回はしない」は、しばらくしてから忘れる
        for app in declined where !detector.activeApps.contains(app) && declineExpiry[app] == nil {
            declineExpiry[app] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(self?.timing.declineGrace ?? 0))
                guard !Task.isCancelled else { return }
                self?.declined.remove(app)
                self?.declineExpiry[app] = nil
            }
        }
        for app in detector.activeApps where declineExpiry[app] != nil {
            declineExpiry.removeValue(forKey: app)?.cancel()
        }

        switch currentState() {
        case .idle:
            let candidates = active.subtracting(declined)
            if candidates.isEmpty {
                startTask?.cancel()
                startTask = nil
                if panel.kind == .start { hidePanel() }
            } else if startTask == nil, panel.kind != .start {
                startTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(self?.timing.startDelay ?? 0))
                    guard !Task.isCancelled, let self else { return }
                    self.startTask = nil
                    let apps = self.activeTargets.subtracting(self.declined)
                    guard self.settings.enabled, self.currentState() == .idle, let app = Self.preferred(apps) else { return }
                    self.show(.start(app))
                }
            }
        case .recording:
            seenWhileRecording.formUnion(active)
            if !active.isEmpty {
                stopTask?.cancel()
                stopTask = nil
                if panel.kind == .stop { hidePanel() }
            } else if let app = Self.preferred(seenWhileRecording), stopTask == nil, panel.kind != .stop {
                stopTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(self?.timing.stopDelay ?? 0))
                    guard !Task.isCancelled, let self else { return }
                    self.stopTask = nil
                    guard self.currentState() == .recording, self.activeTargets.isEmpty else { return }
                    self.show(.stop(app, startedAt: self.recordingStartedAt() ?? Date()))
                }
            }
        case .starting:
            seenWhileRecording.formUnion(active)
        case .processing:
            break
        }
    }

    private func handle(_ action: MeetingSuggestionPanel.Action) {
        let shown = panel.suggestion
        hidePanel()
        switch (action, shown) {
        case (.accept, .start(let app)?):
            guard currentState() == .idle else { break }
            seenWhileRecording.insert(app)
            startRecording()
        case (.dismiss, .start(let app)?):
            // 今回の会議では聞かない（マイクを止めてしばらくたつまで）
            declined.formUnion(detector.activeApps)
            declined.insert(app)
        case (.accept, .stop?):
            if currentState() == .recording { stopRecording() }
        case (.dismiss, .stop?):
            // 記録を続ける。また会議アプリがマイクを使って止めるまでは聞かない
            seenWhileRecording = []
        case (_, nil):
            break
        }
    }

    private func reset() {
        startTask?.cancel()
        stopTask?.cancel()
        startTask = nil
        stopTask = nil
        declineExpiry.values.forEach { $0.cancel() }
        declineExpiry = [:]
        declined = []
        seenWhileRecording = []
        hidePanel()
    }

    private func show(_ suggestion: MeetingSuggestionPanel.Suggestion) {
        panel.show(suggestion)
        onSuggestionChange?(suggestion)
    }

    private func hidePanel() {
        guard panel.suggestion != nil else { return }
        panel.hide()
        onSuggestionChange?(nil)
    }

    /// 複数のアプリが同時にマイクを使っているときは、専用の会議アプリを優先して名前を出す
    private static func preferred(_ apps: Set<MeetingApp>) -> MeetingApp? {
        MeetingApp.allCases.first { apps.contains($0) }
    }
}
