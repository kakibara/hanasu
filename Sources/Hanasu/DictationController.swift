import AppKit
import Carbon.HIToolbox
import Combine
import os

let appLog = Logger(subsystem: "dev.mactypeless.Hanasu", category: "dictation")

/// ホットキー → 録音 → 文字起こし → Gemini 整形（または英訳） → 入力、の流れを管理する。
@MainActor
final class DictationController {
    enum State { case idle, preparing, recording, processing }
    /// 録音を始めたショートカットで決まる。整形して日本語で入力するか、英語に翻訳して入力するか
    enum Mode { case refine, translateToEnglish }

    struct HistoryEntry {
        let date: Date
        let raw: String
        let output: String
        let mode: Mode
    }

    private(set) var state: State = .idle {
        didSet { onStateChange?(state) }
    }
    private(set) var mode: Mode = .refine
    private(set) var history: [HistoryEntry] = []
    var onStateChange: ((State) -> Void)?
    /// ショートカットの登録に失敗したとき（他アプリと衝突など）
    var onHotKeyRegistrationFailed: ((HotKeyCombo) -> Void)?

    private let settings = AppSettings.shared
    private let hotKeys = HotKeyManager()
    private let recognizer = SpeechRecognizer()
    private let hud = HUDController()
    private var mainHotKeyID: UInt32?
    private var translateHotKeyID: UInt32?
    private var escapeHotKeyID: UInt32?
    private var stopRequested = false
    private var cancelRequested = false
    private var targetAppName: String?
    private var screenContextCapture: ScreenContextCapture?
    private var cancellables: Set<AnyCancellable> = []

    init() {
        recognizer.onPartialText = { [weak self] text in
            self?.hud.updateTranscript(text)
        }
        recognizer.onAssetDownloadProgress = { [weak self] fraction in
            self?.hud.show(.preparing("日本語の音声モデルをダウンロード中… \(Int(fraction * 100))%"))
        }
        hud.model.onSelectTranslating = { [weak self] translating in
            self?.selectOutputLanguage(translating: translating)
        }
        settings.$hotKey
            .removeDuplicates()
            .sink { [weak self] combo in self?.registerHotKey(combo, mode: .refine) }
            .store(in: &cancellables)
        settings.$translateHotKey
            .removeDuplicates()
            .sink { [weak self] combo in self?.registerHotKey(combo, mode: .translateToEnglish) }
            .store(in: &cancellables)
    }

    // MARK: - ホットキー

    /// ショートカット記録中は一時的に外す（記録したいキーを横取りしないため）
    func suspendHotKey() {
        for id in [mainHotKeyID, translateHotKeyID].compactMap({ $0 }) { hotKeys.unregister(id) }
        mainHotKeyID = nil
        translateHotKeyID = nil
    }

    func resumeHotKey() {
        registerHotKey(settings.hotKey, mode: .refine)
        registerHotKey(settings.translateHotKey, mode: .translateToEnglish)
    }

    private func registerHotKey(_ combo: HotKeyCombo, mode: Mode) {
        let previous = mode == .refine ? mainHotKeyID : translateHotKeyID
        if let previous { hotKeys.unregister(previous) }
        let id = hotKeys.register(combo) { [weak self] event in
            self?.handleHotKey(event, mode: mode)
        }
        switch mode {
        case .refine: mainHotKeyID = id
        case .translateToEnglish: translateHotKeyID = id
        }
        if id == nil {
            onHotKeyRegistrationFailed?(combo)
        }
    }

    /// 開始はショートカットごとのモードで。録音中はどちらのショートカットでも止まる
    private func handleHotKey(_ event: HotKeyManager.Event, mode: Mode) {
        switch (settings.recordingMode, event, state) {
        case (_, .pressed, .idle):
            startDictation(mode: mode)
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

    /// 録音中に HUD で出力の言語を切り替える。止めた時点の選択で、整形するか英訳するかが決まる
    func selectOutputLanguage(translating: Bool) {
        guard state == .preparing || state == .recording else { return }
        mode = translating ? .translateToEnglish : .refine
        hud.model.translating = translating
    }

    func toggleFromMenu(mode: Mode = .refine) {
        switch state {
        case .idle: startDictation(mode: mode)
        case .recording: Task { await finishDictation() }
        case .preparing: stopRequested = true
        case .processing: break
        }
    }

    func startDictation(mode: Mode = .refine) {
        guard state == .idle else { return }
        self.mode = mode
        state = .preparing
        stopRequested = false
        cancelRequested = false
        targetAppName = NSWorkspace.shared.frontmostApplication?.localizedName
        screenContextCapture = ScreenContextCapture.begin()
        hud.model.translating = mode == .translateToEnglish
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
        let translating = mode == .translateToEnglish
        // 英訳は Gemini でしかできないので、整形をオフにしていても Gemini に送る
        if settings.refineWithGemini || translating {
            let verb = translating ? "翻訳" : "整形"
            do {
                if let auth = try GeminiClient.authFromSettings(settings) {
                    let client = GeminiClient(auth: auth)
                    let request = GeminiClient.Request(
                        transcript: raw,
                        model: settings.model,
                        appName: settings.sendAppName ? targetAppName : nil,
                        dictionary: settings.dictionaryWords,
                        extraInstructions: settings.extraInstructions,
                        screenContext: await screenContextCapture?.result())
                    output = translating ? try await client.translateToEnglish(request) : try await client.refine(request)
                    appLog.notice("\(translating ? "translated" : "refined", privacy: .public) by \(self.settings.model, privacy: .public): \(output.count) chars")
                } else {
                    appLog.notice("\(verb, privacy: .public) skipped: no credentials (mode=\(self.settings.authMode.rawValue, privacy: .public))")
                    warning = "Gemini の認証情報が未設定のため、\(verb)せずに入力しました（メニュー → 設定）。"
                }
            } catch {
                appLog.error("\(verb, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                warning = "\(error.localizedDescription)\n\(verb)前の文章を入力しました。"
            }
        }

        let outcome = await TextInserter.insert(output)
        appLog.notice("insert outcome: \(String(describing: outcome), privacy: .public), frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-", privacy: .public)")
        history.insert(HistoryEntry(date: Date(), raw: raw, output: output, mode: mode), at: 0)
        if history.count > 10 { history.removeLast(history.count - 10) }
        state = .idle

        switch (outcome, warning) {
        case (.copiedOnly, _):
            hud.show(.error("アクセシビリティが許可されていないため、クリップボードにコピーしました。⌘V で貼り付けてください。設定でオンになっている場合は、一覧から Hanasu を削除（−）して追加し直してください。"))
            _ = Permissions.isAccessibilityTrusted(prompt: true)
        case (.pasted, let warning?):
            hud.show(.error(warning))
        case (.pasted, nil):
            hud.show(.done(translating ? "英訳して入力しました" : "入力しました"))
        }
    }

    private func playSound(_ name: String) {
        guard settings.playSounds else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }
}
