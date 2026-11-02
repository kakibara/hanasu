import AppKit
import Carbon.HIToolbox
import Combine
import os

let appLog = Logger(subsystem: "dev.mactypeless.Hanasu", category: "dictation")

/// ホットキー → 録音 → 文字起こし → Gemini 整形 → 入力、の流れを管理する。
@MainActor
final class DictationController {
    enum State { case idle, preparing, recording, processing }

    struct HistoryEntry {
        let date: Date
        let raw: String
        let output: String
    }

    private(set) var state: State = .idle {
        didSet { onStateChange?(state) }
    }
    private(set) var history: [HistoryEntry] = []
    var onStateChange: ((State) -> Void)?
    /// ショートカットの登録に失敗したとき（他アプリと衝突など）
    var onHotKeyRegistrationFailed: ((HotKeyCombo) -> Void)?

    private let settings = AppSettings.shared
    private let hotKeys = HotKeyManager()
    private let recognizer = SpeechRecognizer()
    private let hud = HUDController()
    private var mainHotKeyID: UInt32?
    private var escapeHotKeyID: UInt32?
    private var stopRequested = false
    private var cancelRequested = false
    private var targetAppName: String?
    private var cancellables: Set<AnyCancellable> = []

    init() {
        recognizer.onPartialText = { [weak self] text in
            self?.hud.updateTranscript(text)
        }
        recognizer.onAssetDownloadProgress = { [weak self] fraction in
            self?.hud.show(.preparing("日本語の音声モデルをダウンロード中… \(Int(fraction * 100))%"))
        }
        settings.$hotKey
            .removeDuplicates()
            .sink { [weak self] combo in self?.registerMainHotKey(combo) }
            .store(in: &cancellables)
    }

    // MARK: - ホットキー

    /// ショートカット記録中は一時的に外す（記録したいキーを横取りしないため）
    func suspendHotKey() {
        if let id = mainHotKeyID { hotKeys.unregister(id) }
        mainHotKeyID = nil
    }

    func resumeHotKey() {
        registerMainHotKey(settings.hotKey)
    }

    private func registerMainHotKey(_ combo: HotKeyCombo) {
        if let id = mainHotKeyID { hotKeys.unregister(id) }
        mainHotKeyID = hotKeys.register(combo) { [weak self] event in
            self?.handleHotKey(event)
        }
        if mainHotKeyID == nil {
            onHotKeyRegistrationFailed?(combo)
        }
    }

    private func handleHotKey(_ event: HotKeyManager.Event) {
        switch (settings.recordingMode, event, state) {
        case (_, .pressed, .idle):
            startDictation()
        case (.toggle, .pressed, .recording), (.pushToTalk, .released, .recording):
            Task { await finishDictation() }
        case (.toggle, .pressed, .preparing), (.pushToTalk, .released, .preparing):
            stopRequested = true
        default:
            break
        }
    }

    private func setEscapeHotKey(enabled: Bool) {
        if enabled, escapeHotKeyID == nil {
            escapeHotKeyID = hotKeys.register(HotKeyCombo(keyCode: UInt32(kVK_Escape), modifiers: 0)) { [weak self] event in
                if event == .pressed { self?.cancelDictation() }
            }
        } else if !enabled, let id = escapeHotKeyID {
            hotKeys.unregister(id)
            escapeHotKeyID = nil
        }
    }

    // MARK: - 操作

    func toggleFromMenu() {
        switch state {
        case .idle: startDictation()
        case .recording: Task { await finishDictation() }
        case .preparing: stopRequested = true
        case .processing: break
        }
    }

    func startDictation() {
        guard state == .idle else { return }
        state = .preparing
        stopRequested = false
        cancelRequested = false
        targetAppName = NSWorkspace.shared.frontmostApplication?.localizedName
        hud.show(.preparing("準備中…"))
        setEscapeHotKey(enabled: true)

        Task {
            do {
                try await Permissions.ensureRecordingPermissions()
                try await recognizer.start(
                    localeIdentifier: settings.localeIdentifier,
                    engine: settings.engine,
                    contextualStrings: settings.dictionaryWords)
            } catch {
                fail(error.localizedDescription)
                return
            }
            if cancelRequested {
                await recognizer.cancel()
                finishCancelled()
                return
            }
            state = .recording
            playSound("Tink")
            hud.show(.recording)
            if stopRequested {
                await finishDictation()
            }
        }
    }

    func cancelDictation() {
        switch state {
        case .preparing:
            cancelRequested = true
        case .recording:
            Task {
                await recognizer.cancel()
                finishCancelled()
            }
        default:
            break
        }
    }

    private func finishCancelled() {
        state = .idle
        setEscapeHotKey(enabled: false)
        hud.show(.done("取り消しました"))
    }

    private func fail(_ message: String) {
        state = .idle
        setEscapeHotKey(enabled: false)
        playSound("Basso")
        hud.show(.error(message))
    }

    func finishDictation() async {
        guard state == .recording else { return }
        state = .processing
        setEscapeHotKey(enabled: false)
        playSound("Pop")
        hud.show(.processing)

        let raw = await recognizer.stop()
        appLog.notice("recognized \(raw.count) chars")
        hud.updateTranscript(raw)
        guard !raw.isEmpty else {
            fail("音声が認識されませんでした")
            return
        }

        var output = raw
        var warning: String?
        if settings.refineWithGemini {
            do {
                if let auth = try GeminiClient.authFromSettings(settings) {
                    output = try await GeminiClient(auth: auth).refine(.init(
                        transcript: raw,
                        model: settings.model,
                        appName: settings.sendAppName ? targetAppName : nil,
                        dictionary: settings.dictionaryWords,
                        extraInstructions: settings.extraInstructions))
                    appLog.notice("refined by \(self.settings.model, privacy: .public): \(output.count) chars")
                } else {
                    appLog.notice("refine skipped: no credentials (mode=\(self.settings.authMode.rawValue, privacy: .public))")
                    warning = "Gemini の認証情報が未設定のため、整形せずに入力しました（メニュー → 設定）。"
                }
            } catch {
                appLog.error("refine failed: \(error.localizedDescription, privacy: .public)")
                warning = "\(error.localizedDescription)\n整形前の文章を入力しました。"
            }
        }

        let outcome = await TextInserter.insert(output)
        appLog.notice("insert outcome: \(String(describing: outcome), privacy: .public), frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-", privacy: .public)")
        history.insert(HistoryEntry(date: Date(), raw: raw, output: output), at: 0)
        if history.count > 10 { history.removeLast(history.count - 10) }
        state = .idle

        switch (outcome, warning) {
        case (.copiedOnly, _):
            hud.show(.error("アクセシビリティが許可されていないため、クリップボードにコピーしました。⌘V で貼り付けてください。設定でオンになっている場合は、一覧から Hanasu を削除（−）して追加し直してください。"))
            _ = Permissions.isAccessibilityTrusted(prompt: true)
        case (.pasted, let warning?):
            hud.show(.error(warning))
        case (.pasted, nil):
            hud.show(.done("入力しました"))
        }
    }

    private func playSound(_ name: String) {
        guard settings.playSounds else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }
}
