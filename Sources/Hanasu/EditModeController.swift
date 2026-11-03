import AppKit
import Carbon.HIToolbox
import Combine

// 要件: REQ-DIC-050
/// 選択中の文章を、声の指示で書き換える（Wispr Flow の Command Mode にあたる）。
/// ホットキー → 選択文の読み取り → 指示の録音・文字起こし → Gemini で書き換え → 選択範囲に貼り付け、の流れを管理する。
/// 録音・HUD・ホットキーは音声入力（DictationController）とは別に持ち、同時には動かさない。
@MainActor
final class EditModeController {
    typealias State = DictationController.State

    private(set) var state: State = .idle {
        didSet { onStateChange?(state) }
    }
    var onStateChange: ((State) -> Void)?
    /// ショートカットの登録に失敗したとき（他アプリと衝突など）
    var onHotKeyRegistrationFailed: ((HotKeyCombo) -> Void)?

    private let settings = AppSettings.shared
    private let editSettings = EditModeSettings.shared
    private let dictation: DictationController
    private let hotKeys = HotKeyManager()
    private let recognizer = SpeechRecognizer()
    private let hud = HUDController()
    private var hotKeyID: UInt32?
    private var escapeHotKeyID: UInt32?
    private var stopRequested = false
    private var cancelRequested = false
    /// 準備中に選択がないとわかったとき、準備が終わってから出すエラー
    private var pendingFailure: String?
    private var client: TextAIClient?
    private var targetAppName: String?
    private var selectionTask: Task<String?, Never>?
    private var cancellables: Set<AnyCancellable> = []

    // 設計判断: DEC-DIC-035
    init(dictation: DictationController) {
        self.dictation = dictation
        hud.model.editBadge = ""
        hud.model.onStop = { [weak self] in self?.stopFromHUD() }
        hud.model.onCancel = { [weak self] in self?.cancel() }
        recognizer.onPartialText = { [weak self] text in
            self?.hud.updateTranscript(text)
        }
        recognizer.onAssetDownloadProgress = { [weak self] fraction in
            self?.hud.show(.preparing("日本語の音声モデルをダウンロード中… \(Int(fraction * 100))%"))
        }
        recognizer.onLevel = { [weak self] level in
            self?.hud.model.level = level
        }
        recognizer.onBatchTranscriptionStarted = { [weak self] _ in
            self?.hud.model.transcribing = true
        }
        // 編集中は音声入力を始めない（マイクと HUD を取り合わないため）
        dictation.canStart = { [weak self] in self?.state == .idle }
        // 初回の登録は、呼び出し元が onHotKeyRegistrationFailed を設定し終えてから行う
        editSettings.$hotKey
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] combo in self?.registerHotKey(combo) }
            .store(in: &cancellables)
    }

    var hotKey: HotKeyCombo { editSettings.hotKey }

    /// メニューバーに出す文言
    var menuTitle: String {
        switch state {
        case .idle: "選択を声で編集"
        case .preparing, .recording: "編集の指示を止めて書き換え"
        case .processing: "書き換え中…"
        }
    }

    // MARK: - ホットキー

    /// ショートカット記録中は一時的に外す（記録したいキーを横取りしないため）
    func suspendHotKey() {
        if let hotKeyID { hotKeys.unregister(hotKeyID) }
        hotKeyID = nil
    }

    func resumeHotKey() {
        registerHotKey(editSettings.hotKey)
    }

    private func registerHotKey(_ combo: HotKeyCombo) {
        if let hotKeyID { hotKeys.unregister(hotKeyID) }
        hotKeyID = hotKeys.register(combo) { [weak self] event in
            self?.handleHotKey(event)
        }
        if hotKeyID == nil {
            onHotKeyRegistrationFailed?(combo)
        }
    }

    /// 録音モード（トグル／押している間だけ）は音声入力と同じ設定に従う
    private func handleHotKey(_ event: HotKeyManager.Event) {
        switch (settings.recordingMode, event, state) {
        case (_, .pressed, .idle):
            start()
        case (.toggle, .pressed, .recording), (.pushToTalk, .released, .recording):
            Task { await finish() }
        case (.toggle, .pressed, .preparing), (.pushToTalk, .released, .preparing):
            stopRequested = true
        default:
            break
        }
    }

    private func setEscapeHotKey(enabled: Bool) {
        if enabled, escapeHotKeyID == nil {
            escapeHotKeyID = hotKeys.register(HotKeyCombo(keyCode: UInt32(kVK_Escape), modifiers: 0)) { [weak self] event in
                if event == .pressed { self?.cancel() }
            }
        } else if !enabled, let id = escapeHotKeyID {
            hotKeys.unregister(id)
            escapeHotKeyID = nil
        }
    }

    // MARK: - 操作

    // 要件: REQ-DIC-012
    /// HUD の「停止」。ショートカットをもう一度押したときと同じく、録音を止めて書き換える
    func stopFromHUD() {
        switch state {
        case .recording: Task { await finish() }
        case .preparing: stopRequested = true
        case .idle, .processing: break
        }
    }

    func toggleFromMenu() {
        switch state {
        case .idle: start()
        case .recording: Task { await finish() }
        case .preparing: stopRequested = true
        case .processing: break
        }
    }

    // 設計判断: DEC-DIC-032
    func start() {
        guard state == .idle, dictation.state == .idle else { return }
        // 前に貼り付けられずに残した結果の表示は、次の録音を始めたら閉じる（DEC-DIC-094）。
        // 表示がキーウインドウのままだと、選択の写し取り（⌘C）がそちらへ行ってしまうので、読み取りの前に閉じる
        PasteFallbackPanel.shared.close()
        // 選択の読み取り（アクセシビリティ API・⌘C）にも貼り付け（⌘V）にも要る
        guard Permissions.isAccessibilityTrusted(prompt: false) else {
            fail("選択を声で編集するには、アクセシビリティの許可が必要です（選択した文章の読み取りと貼り付けに使います）。")
            _ = Permissions.isAccessibilityTrusted(prompt: true)
            return
        }
        do {
            // キーそのものは持たない（Claude は送るときにキーチェーンから読む）
            guard let client = try TextAIClient.fromSettings(settings, for: .dictation, timeout: 60) else {
                let provider = settings.aiProvider(for: .dictation)
                fail("\(provider.name) の認証情報が未設定のため、選択を声で編集できません（メニュー → 設定 →「AI」）。")
                return
            }
            self.client = client
        } catch {
            fail(error.localizedDescription)
            return
        }

        let app = NSWorkspace.shared.frontmostApplication
        targetAppName = app?.localizedName
        state = .preparing
        stopRequested = false
        cancelRequested = false
        pendingFailure = nil
        hud.model.editBadge = "選択を読み取り中…"
        // Whisper / Gemini は録音を止めてからまとめて文字起こしするので、HUD の出しかたを変える
        hud.model.batchEngine = settings.dictationEngine.isLive ? nil : settings.dictationEngine
        hud.show(.preparing("準備中…"))
        setEscapeHotKey(enabled: true)

        // 選択の読み取りは録音と並行して進める。⌘C で写し取るときは、ショートカットの修飾キーが離されるまで待つため
        let pid = app?.processIdentifier
        let task = Task { () -> String? in
            if let text = SelectionReader.readViaAccessibility(pid: pid) { return text }
            appLog.notice("edit: selection not available via accessibility, falling back to copy")
            return await SelectionReader.readViaCopy()
        }
        selectionTask = task
        Task {
            let text = await task.value
            selectionResolved(text, task: task)
        }

        Task {
            do {
                try await Permissions.ensureRecordingPermissions(speechRecognition: settings.dictationEngine == .apple)
                try await recognizer.start(
                    localeIdentifier: settings.localeIdentifier,
                    engine: settings.engine,
                    contextualStrings: settings.dictionaryWords,
                    transcription: settings.dictationEngine)
            } catch {
                selectionTask?.cancel()
                fail(error.localizedDescription)
                return
            }
            if cancelRequested {
                await recognizer.cancel()
                if let pendingFailure { fail(pendingFailure) } else { finishCancelled() }
                return
            }
            state = .recording
            playSound("Tink")
            hud.show(.recording)
            if stopRequested {
                await finish()
            }
        }
    }

    /// 選択を読み終えたとき。選択がなければ、録音を待たずに終える
    private func selectionResolved(_ text: String?, task: Task<String?, Never>) {
        guard selectionTask == task else { return }  // 取り消し済みか、次の編集が始まっている
        if let error = Self.selectionError(text) {
            abort(error)
            return
        }
        hud.model.editBadge = "選択 \(text?.count ?? 0) 文字"
    }

    // 設計判断: DEC-DIC-032
    static func selectionError(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "文章が選択されていません。書き換えたい文章を選択してから、もう一度押してください。"
        }
        if text.count > EditModeSettings.maxSelectionLength {
            return "選択が長すぎます（\(text.count) 文字）。\(EditModeSettings.maxSelectionLength) 文字以内にしてください。"
        }
        return nil
    }

    func cancel() {
        switch state {
        case .preparing:
            cancelRequested = true
        case .recording:
            state = .processing  // 取り消しの間に止める操作が来ても、書き換えに進まないように
            Task {
                await recognizer.cancel()
                finishCancelled()
            }
        default:
            break
        }
    }

    /// 録音中・準備中に、続けられないとわかったとき
    private func abort(_ message: String) {
        switch state {
        case .preparing:
            cancelRequested = true
            pendingFailure = message
        case .recording:
            state = .processing
            Task {
                await recognizer.cancel()
                fail(message)
            }
        default:
            break  // 書き換え中なら finish の中で同じ判定をする
        }
    }

    private func finishCancelled() {
        endSession()
        hud.show(.done("取り消しました"))
    }

    private func fail(_ message: String) {
        endSession()
        playSound("Basso")
        hud.show(.error(message))
    }

    private func endSession() {
        state = .idle
        selectionTask?.cancel()
        selectionTask = nil
        client = nil
        setEscapeHotKey(enabled: false)
    }

    // 要件: REQ-DIC-080
    // 設計判断: DEC-DIC-036, DEC-DIC-096
    func finish() async {
        guard state == .recording else { return }
        state = .processing
        setEscapeHotKey(enabled: false)
        playSound("Pop")
        hud.show(.processing)

        let instruction = await recognizer.stop()
        hud.model.transcribing = false
        appLog.notice("edit: instruction \(instruction.count) chars")
        hud.updateTranscript(instruction)
        // 押している間だけ録音するモードでは、ここで初めて ⌘C で選択を写し取ることがある
        let selection = await selectionTask?.value ?? nil
        if let error = Self.selectionError(selection) {
            fail(error)
            return
        }
        guard let selection, let client else {
            fail("AI の認証情報を読み込めませんでした。")
            return
        }
        hud.model.editBadge = "選択 \(selection.count) 文字"
        guard !instruction.isEmpty else {
            fail(recognizer.lastError.map { "\($0)。選択した文章はそのままです。" } ?? "指示が聞き取れませんでした。選択した文章はそのままです。")
            return
        }

        let output: String
        do {
            // 長い選択の書き換えは整形より時間がかかるので、60 秒待つ（start で作ったクライアント）
            output = try await client.editSelection(GeminiClient.EditRequest(
                selection: selection,
                instruction: instruction,
                model: settings.textModel(for: .dictation),
                appName: settings.sendAppName ? targetAppName : nil,
                dictionary: settings.dictionaryWords))
            appLog.notice("edit: rewritten by \(self.settings.textModel(for: .dictation), privacy: .public): \(selection.count) → \(output.count) chars")
        } catch {
            appLog.error("edit failed: \(error.localizedDescription, privacy: .public)")
            fail("\(error.localizedDescription)\n選択した文章はそのままです。")
            return
        }

        // 選択範囲が残っていれば、⌘V で置き換わる
        let outcome = await TextInserter.insert(output)
        endSession()
        switch outcome {
        case .copiedOnly:
            hud.show(.error("アクセシビリティが許可されていないため、書き換えた文章をクリップボードにコピーしました。⌘V で貼り付けてください。"))
        case .notPasted(let clipboardKept):
            // 編集の結果は履歴に残らない（DEC-DIC-036）ので、ここで失わないよう全文を残す
            hud.hide()
            PasteFallbackPanel.shared.show(text: output, subject: .edit, clipboardKept: clipboardKept)
        case .pasted:
            hud.show(.done("書き換えました（⌘Z で元に戻せます）"))
        }
    }

    private func playSound(_ name: String) {
        guard settings.playSounds else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }
}
