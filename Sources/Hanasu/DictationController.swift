import AppKit
import Carbon.HIToolbox
import Combine
import os

let appLog = Logger(subsystem: "dev.mactypeless.Hanasu", category: "dictation")

/// ホットキー → 録音 → 文字起こし → Gemini 整形（または翻訳） → 入力、の流れを管理する。
@MainActor
final class DictationController {
    enum State { case idle, preparing, recording, processing }
    // 要件: REQ-DIC-010, REQ-DIC-013
    /// 録音を始めたショートカットで決まる。整形して話した言語で入力するか、翻訳の言語に翻訳して入力するか
    enum Mode: Equatable {
        case refine
        case translate(TranslationLanguage)

        var translation: TranslationLanguage? {
            if case .translate(let language) = self { return language }
            return nil
        }
    }

    private(set) var state: State = .idle {
        didSet { onStateChange?(state) }
    }
    private(set) var mode: Mode = .refine
    var onStateChange: ((State) -> Void)?
    /// ショートカットの登録に失敗したとき（他アプリと衝突など）
    var onHotKeyRegistrationFailed: ((HotKeyCombo) -> Void)?
    // 設計判断: DEC-DIC-035
    /// ほかの録音（選択を声で編集）が動いている間は false を返す
    var canStart: () -> Bool = { true }
    // 要件: REQ-DIC-084
    /// 貼り付けが届いたか確かめられなかったとき（設定がオンなら）、その結果の履歴を開く
    var onOpenHistory: ((UUID) -> Void)?

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
    /// 履歴に残す録音の保存先（「音声も残す」がオンのとき）
    private var pendingAudioURL: URL?
    /// 録音を始めたときの前面アプリのスタイル（アプリ別の設定がなければ nil）
    private var targetAppStyle: AppStyle?
    private var screenContextCapture: ScreenContextCapture?
    private var cancellables: Set<AnyCancellable> = []

    // 要件: REQ-DIC-002
    init() {
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
        hud.model.onSelectTranslation = { [weak self] translation in
            self?.selectOutputLanguage(translation)
        }
        hud.model.onStop = { [weak self] in self?.stopFromHUD() }
        hud.model.onCancel = { [weak self] in self?.cancelDictation() }
        hud.model.onSelectMicrophone = { [weak self] uid in self?.selectMicrophone(uid) }
        settings.$hotKey
            .removeDuplicates()
            .sink { [weak self] combo in self?.registerHotKey(combo, translating: false) }
            .store(in: &cancellables)
        settings.$translateHotKey
            .removeDuplicates()
            .sink { [weak self] combo in self?.registerHotKey(combo, translating: true) }
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
        registerHotKey(settings.hotKey, translating: false)
        registerHotKey(settings.translateHotKey, translating: true)
    }

    private func registerHotKey(_ combo: HotKeyCombo, translating: Bool) {
        let previous = translating ? translateHotKeyID : mainHotKeyID
        if let previous { hotKeys.unregister(previous) }
        let id = hotKeys.register(combo) { [weak self] event in
            guard let self else { return }
            // 設計判断: DEC-DIC-027
            // 翻訳の言語は押したときの設定で決める（設定を変えても登録し直さなくてよい）
            self.handleHotKey(event, mode: translating ? .translate(self.settings.primaryTranslationLanguage) : .refine)
        }
        if translating {
            translateHotKeyID = id
        } else {
            mainHotKeyID = id
        }
        if id == nil {
            onHotKeyRegistrationFailed?(combo)
        }
    }

    // 要件: REQ-DIC-001, REQ-DIC-006
    // 設計判断: DEC-DIC-012, DEC-DIC-020
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

    // 要件: REQ-DIC-005
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

    // 要件: REQ-DIC-011, REQ-DIC-013
    /// 録音中に HUD で出力の言語を切り替える。止めた時点の選択で、整形するか、どの言語に翻訳するかが決まる
    func selectOutputLanguage(_ translation: TranslationLanguage?) {
        guard state == .preparing || state == .recording else { return }
        mode = translation.map(Mode.translate) ?? .refine
        hud.model.translation = translation
    }

    /// 翻訳して入力するときの言語。メニューから始めるとき用（ショートカットと同じく、選んだ言語のうち最初）
    var primaryTranslateMode: Mode { .translate(settings.primaryTranslationLanguage) }

    // 要件: REQ-DIC-140
    // 設計判断: DEC-DIC-141
    /// HUD でマイクを選んだとき。次の録音でも使うよう設定に残し、録音中ならそのマイクに切り替える
    func selectMicrophone(_ uid: String) {
        settings.dictationInputDeviceUID = uid
        guard state == .recording else { return }
        do {
            try recognizer.switchInput(to: uid)
        } catch {
            state = .processing  // 取り消しの間に止める操作が来ても、入力に進まないように
            Task {
                await recognizer.cancel()
                fail("マイクを切り替えられませんでした: \(error.localizedDescription)")
            }
        }
    }

    // 要件: REQ-DIC-012
    // 設計判断: DEC-DIC-026
    /// HUD の「停止」。ショートカットをもう一度押したときと同じく、録音を止めて入力する
    func stopFromHUD() {
        switch state {
        case .recording: Task { await finishDictation() }
        case .preparing: stopRequested = true
        case .idle, .processing: break
        }
    }

    func toggleFromMenu(mode: Mode = .refine) {
        switch state {
        case .idle: startDictation(mode: mode)
        case .recording: Task { await finishDictation() }
        case .preparing: stopRequested = true
        case .processing: break
        }
    }

    // 要件: REQ-DIC-020, REQ-DIC-021
    // 設計判断: DEC-DIC-045, DEC-DIC-027
    func startDictation(mode: Mode = .refine) {
        guard state == .idle, canStart() else { return }
        // 前に貼り付けられずに残した結果の表示は、次の録音を始めたら閉じる（DEC-DIC-094）
        PasteFallbackPanel.shared.close()
        self.mode = mode
        state = .preparing
        stopRequested = false
        cancelRequested = false
        targetAppName = NSWorkspace.shared.frontmostApplication?.localizedName
        targetAppStyle = AppStyleStore.shared.style(forBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        // 既定の出力言語が English（日本語）のアプリでは、その言語への翻訳から始める。HUD で切り替えればそちらが優先される
        if mode == .refine, let translation = targetAppStyle?.outputLanguage.translation {
            self.mode = .translate(translation)
        }
        screenContextCapture = ScreenContextCapture.begin()
        pendingAudioURL = DictationHistoryStore.shared.newAudioURL()
        // HUD には「話した言語」と設定で選んだ翻訳の言語を出す（アプリ別の既定で選んでいない言語から始めたときは、それも出す）
        hud.model.translationChoices = TranslationLanguage.normalized(settings.translationLanguages + [self.mode.translation].compactMap { $0 })
        hud.model.translation = self.mode.translation
        // Whisper / Gemini は録音を止めてからまとめて文字起こしするので、HUD の出しかたを変える
        hud.model.batchEngine = settings.dictationEngine.isLive ? nil : settings.dictationEngine
        hud.show(.preparing("準備中…"))
        setEscapeHotKey(enabled: true)

        Task {
            do {
                try await Permissions.ensureRecordingPermissions(speechRecognition: settings.dictationEngine == .apple)
                try await recognizer.start(
                    localeIdentifier: settings.localeIdentifier,
                    engine: settings.engine,
                    contextualStrings: settings.userDictionary.contextualStrings + SnippetStore.shared.triggerPhrases,
                    audioFileURL: pendingAudioURL,
                    transcription: settings.dictationEngine,
                    inputDeviceUID: settings.dictationInputDeviceUID)
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

    // 要件: REQ-DIC-005
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
        DictationHistoryStore.shared.discardAudio(pendingAudioURL)
        pendingAudioURL = nil
        setEscapeHotKey(enabled: false)
        hud.show(.done("取り消しました"))
    }

    private func fail(_ message: String) {
        state = .idle
        DictationHistoryStore.shared.discardAudio(pendingAudioURL)
        pendingAudioURL = nil
        setEscapeHotKey(enabled: false)
        playSound("Basso")
        hud.show(.error(message))
    }

    // 要件: REQ-DIC-007, REQ-DIC-070, REQ-DIC-080, REQ-DIC-083, REQ-DIC-084
    // 設計判断: DEC-DIC-014, DEC-DIC-015, DEC-DIC-021, DEC-DIC-052, DEC-DIC-072, DEC-DIC-094, DEC-DIC-099
    func finishDictation() async {
        guard state == .recording else { return }
        state = .processing
        setEscapeHotKey(enabled: false)
        playSound("Pop")
        hud.show(.processing)

        let raw = await recognizer.stop()
        hud.model.transcribing = false
        appLog.notice("recognized \(raw.count) chars")
        hud.updateTranscript(raw)
        guard !raw.isEmpty else {
            fail(recognizer.lastError ?? "音声が認識されませんでした")
            return
        }

        // ユーザー辞書の置き換えルールを決定的に当てる（Gemini で整形しないときも効く）
        let corrected = settings.userDictionary.apply(to: raw)
        // スニペット: 起動フレーズと一致した部分は、Gemini を通さず登録した本文に置き換える（Snippets.swift）。照合は辞書を当てたあとの文で行う
        let snippetMatch = SnippetMatcher.match(corrected, snippets: SnippetStore.shared.snippets)
        if let snippetMatch {
            appLog.notice("snippet matched: \(snippetMatch.snippets.count) snippets, whole=\(snippetMatch.isWholeUtterance)")
        }
        var output = snippetMatch?.assembledWithoutConversion ?? corrected
        var warning: String?
        var historyStatus: DictationHistoryEntry.Status = .refineOff
        var historyError: String?
        let translation = mode.translation
        // 翻訳は AI でしかできないので、整形をオフにしていても AI（Gemini か Claude）に送る。全体がスニペットなら呼ばない
        if settings.refineWithGemini || translation != nil, snippetMatch?.isWholeUtterance != true {
            let verb = translation != nil ? "翻訳" : "整形"
            do {
                // 要件: REQ-COM-032
                // 設計判断: DEC-COM-069
                // ローカルのモデルがまだなければ、ダウンロードするか尋ね、終わるのを待つ。ダイアログで前面が変わるので、入力先を前に戻してから続ける
                try await LocalModelDownloadPrompt.prepare(
                    for: .dictation, settings: settings, work: verb, whenSkipped: "\(verb)前の文章を入力します",
                    restoreFrontmostApp: true)
                // 要件: REQ-COM-020, REQ-COM-024
                if let client = try TextAIClient.fromSettings(settings, for: .dictation) {
                    let model = settings.textModel(for: .dictation)
                    let request = GeminiClient.Request(
                        transcript: output,
                        model: model,
                        appName: settings.sendAppName ? targetAppName : nil,
                        dictionary: settings.dictionaryWords,
                        extraInstructions: settings.extraInstructions,
                        dictionaryRules: settings.userDictionary.rules,
                        appStyle: targetAppStyle,
                        screenContext: await screenContextCapture?.result(),
                        outputLanguage: settings.refineOutputLanguage)
                    // スニペットがあれば、その前後の文だけを整形（翻訳）してつなぐ。本文は送らない
                    let convert: @Sendable (String) async throws -> String = { text in
                        var request = request
                        request.transcript = text
                        if let translation { return try await client.translate(request, to: translation) }
                        return try await client.refine(request)
                    }
                    if let snippetMatch {
                        output = try await snippetMatch.assemble(convert: convert)
                    } else {
                        output = try await convert(corrected)
                    }
                    historyStatus = .succeeded
                    appLog.notice("\(translation.map { "translated (\($0.rawValue))" } ?? "refined", privacy: .public) by \(model, privacy: .public): \(output.count) chars")
                } else {
                    let provider = settings.aiProvider(for: .dictation)
                    appLog.notice("\(verb, privacy: .public) skipped: no credentials (ai=\(provider.rawValue, privacy: .public))")
                    warning = "\(provider.name) の認証情報が未設定のため、\(verb)せずに入力しました（メニュー → 設定 →「AI」）。"
                    historyStatus = .noCredentials
                }
            } catch {
                appLog.error("\(verb, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                warning = "\(error.localizedDescription)\n\(verb)前の文章を入力しました。"
                historyStatus = .geminiFailed
                historyError = error.localizedDescription
            }
        }

        // 入力先がずれても取り戻せるよう、貼り付けの前に履歴へ残す
        let entry = DictationHistoryStore.shared.record(
            raw: raw, output: output, mode: .init(mode), appName: targetAppName, status: historyStatus,
            errorMessage: historyError, model: historyStatus == .succeeded ? settings.textModel(for: .dictation) : nil,
            audioURL: pendingAudioURL)
        pendingAudioURL = nil
        let outcome = await TextInserter.insert(output)
        appLog.notice("insert outcome: \(String(describing: outcome), privacy: .public), frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-", privacy: .public)")
        RecentDictations.record(raw: raw, output: output)
        state = .idle

        switch (outcome, warning) {
        case (.copiedOnly, _):
            hud.show(.error("アクセシビリティが許可されていないため、クリップボードにコピーしました。⌘V で貼り付けてください。設定でオンになっている場合は、一覧から Hanasu を削除（−）して追加し直してください。"))
            _ = Permissions.isAccessibilityTrusted(prompt: true)
        case (.notPasted(let clipboardKept), _):
            // 入力できる場所がない。HUD の代わりに、自動では閉じないパネルで全文を残す（整形の失敗などの知らせも載せる）
            hud.hide()
            PasteFallbackPanel.shared.show(text: output, subject: .result, clipboardKept: clipboardKept, warning: warning)
        case (.unconfirmed(let clipboardKept), _):
            // 入力先がずれたなどで、貼り付け先が受け取らなかった。最新の結果をクリップボードに残してある
            hud.show(.error(TextInserter.unconfirmedMessage(clipboardKept: clipboardKept)))
            if PasteFallbackSettings.shared.openHistoryWhenUnconfirmed {
                onOpenHistory?(entry.id)
            }
        case (.pasted, let warning?):
            hud.show(.error(warning))
        case (.pasted, nil):
            hud.show(.done(snippetMatch?.hudMessage ?? (translation.map { "\($0.verb)して入力しました" } ?? "入力しました")))
        }
    }

    // 設計判断: DEC-DIC-018
    private func playSound(_ name: String) {
        guard settings.playSounds else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }
}
