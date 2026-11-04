import Carbon.HIToolbox
import Foundation

// 要件: REQ-DIC-006
enum RecordingMode: String, CaseIterable, Identifiable {
    case toggle
    case pushToTalk

    var id: String { rawValue }
    var label: String {
        switch self {
        case .toggle: "押すたびに開始／停止（トグル）"
        case .pushToTalk: "押している間だけ録音"
        }
    }
}

enum GeminiAuthMode: String, CaseIterable, Identifiable {
    case apiKey
    case serviceAccount

    var id: String { rawValue }
    var label: String {
        switch self {
        case .apiKey: "API キー（Google AI Studio）"
        case .serviceAccount: "サービスアカウント（Vertex AI）"
        }
    }
}

// 設計判断: DEC-DIC-002
enum RecognizerEngine: String, CaseIterable, Identifiable {
    case dictation
    case speech

    var id: String { rawValue }
    var label: String {
        switch self {
        case .dictation: "DictationTranscriber（システムの音声入力と同系統）"
        case .speech: "SpeechTranscriber（新しい汎用モデル・推奨）"
        }
    }
}

/// グローバルショートカット。Carbon の仮想キーコードと修飾キーで持つ。
struct HotKeyCombo: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32  // cmdKey / optionKey / controlKey / shiftKey の組み合わせ

    // 設計判断: DEC-DIC-011
    static let `default` = HotKeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))
    // 設計判断: DEC-DIC-020
    static let defaultTranslate = HotKeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey | shiftKey))
    // 設計判断: DEC-MTG-021
    static let defaultMeeting = HotKeyCombo(
        keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(controlKey | optionKey | cmdKey))

    var displayString: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + " " + KeyNames.name(for: keyCode)
    }
}

enum KeyNames {
    static func name(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Escape: return "Esc"
        case kVK_Delete: return "⌫"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default: return characterName(for: keyCode) ?? "Key\(keyCode)"
        }
    }

    /// 現在のキーボードレイアウトでのキーの文字を得る。
    private static func characterName(for keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> String? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeyState: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState, chars.count, &length, &chars)
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: length).uppercased()
        }
    }
}

// 設計判断: DEC-COM-013
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // 設計判断: DEC-COM-005
    static let suggestedModels = ["gemini-3.5-flash-lite", "gemini-3.8-flash", "gemini-flash-latest"]

    private let defaults = UserDefaults.standard

    @Published var model: String { didSet { defaults.set(model, forKey: Keys.model) } }
    // 要件: REQ-COM-020, REQ-COM-024
    // 設計判断: DEC-COM-040
    /// 音声入力（整形・英訳・選択の編集）に使う AI（Gemini か Claude）。文字起こしのエンジンとは別
    @Published var dictationAIProvider: TextAIProvider { didSet { defaults.set(dictationAIProvider.rawValue, forKey: Keys.dictationAIProvider) } }
    /// 会議（議事録・会議への質問・辞書の候補）に使う AI
    @Published var meetingAIProvider: TextAIProvider { didSet { defaults.set(meetingAIProvider.rawValue, forKey: Keys.meetingAIProvider) } }
    /// Claude を選んだときの、音声入力のモデル
    @Published var claudeModel: String { didSet { defaults.set(claudeModel, forKey: Keys.claudeModel) } }
    /// Claude を選んだときの、会議のモデル
    @Published var claudeMinutesModel: String { didSet { defaults.set(claudeMinutesModel, forKey: Keys.claudeMinutesModel) } }
    // 要件: REQ-COM-030
    // 設計判断: DEC-COM-067
    /// ローカルを選んだときの、音声入力のモデル（LocalLLMModel の rawValue）
    @Published var localDictationModel: LocalLLMModel { didSet { defaults.set(localDictationModel.rawValue, forKey: Keys.localDictationModel) } }
    /// ローカルを選んだときの、会議のモデル
    @Published var localMeetingModel: LocalLLMModel { didSet { defaults.set(localMeetingModel.rawValue, forKey: Keys.localMeetingModel) } }
    @Published var authMode: GeminiAuthMode { didSet { defaults.set(authMode.rawValue, forKey: Keys.authMode) } }
    @Published var serviceAccountPath: String { didSet { defaults.set(serviceAccountPath, forKey: Keys.serviceAccountPath) } }
    @Published var vertexLocation: String { didSet { defaults.set(vertexLocation, forKey: Keys.vertexLocation) } }
    @Published var hotKey: HotKeyCombo {
        didSet {
            defaults.set(Int(hotKey.keyCode), forKey: Keys.hotKeyCode)
            defaults.set(Int(hotKey.modifiers), forKey: Keys.hotKeyModifiers)
        }
    }
    /// 話した内容を英語に翻訳して入力するショートカット
    @Published var translateHotKey: HotKeyCombo {
        didSet {
            defaults.set(Int(translateHotKey.keyCode), forKey: Keys.translateHotKeyCode)
            defaults.set(Int(translateHotKey.modifiers), forKey: Keys.translateHotKeyModifiers)
        }
    }
    // 要件: REQ-COM-001
    // 設計判断: DEC-COM-020
    // 設計判断: DEC-COM-032
    @Published var recordingMode: RecordingMode { didSet { defaults.set(recordingMode.rawValue, forKey: Keys.recordingMode) } }
    /// Mac 標準のエンジンを選んだときの、SpeechAnalyzer のモジュール
    @Published var engine: RecognizerEngine { didSet { defaults.set(engine.rawValue, forKey: Keys.engine) } }
    /// 音声入力（と選択を声で編集）の文字起こしのエンジン
    @Published var dictationEngine: TranscriptionEngine { didSet { defaults.set(dictationEngine.rawValue, forKey: Keys.dictationEngine) } }
    /// 会議の記録の文字起こしのエンジン
    @Published var meetingEngine: TranscriptionEngine { didSet { defaults.set(meetingEngine.rawValue, forKey: Keys.meetingEngine) } }
    /// Whisper のモデル（音声入力と会議で共通）
    @Published var whisperModel: WhisperModel { didSet { defaults.set(whisperModel.rawValue, forKey: Keys.whisperModel) } }
    /// Gemini で文字起こしするときのモデル（整形のモデルとは別）
    @Published var geminiTranscriptionModel: String { didSet { defaults.set(geminiTranscriptionModel, forKey: Keys.geminiTranscriptionModel) } }
    @Published var localeIdentifier: String { didSet { defaults.set(localeIdentifier, forKey: Keys.locale) } }
    @Published var refineWithGemini: Bool { didSet { defaults.set(refineWithGemini, forKey: Keys.refine) } }
    @Published var extraInstructions: String { didSet { defaults.set(extraInstructions, forKey: Keys.extraInstructions) } }
    @Published var dictionaryText: String { didSet { defaults.set(dictionaryText, forKey: Keys.dictionary) } }
    @Published var playSounds: Bool { didSet { defaults.set(playSounds, forKey: Keys.sounds) } }
    @Published var sendAppName: Bool { didSet { defaults.set(sendAppName, forKey: Keys.sendAppName) } }
    @Published var meetingHotKey: HotKeyCombo {
        didSet {
            defaults.set(Int(meetingHotKey.keyCode), forKey: Keys.meetingHotKeyCode)
            defaults.set(Int(meetingHotKey.modifiers), forKey: Keys.meetingHotKeyModifiers)
        }
    }
    @Published var meetingMinutesModel: String { didSet { defaults.set(meetingMinutesModel, forKey: Keys.meetingMinutesModel) } }
    @Published var keepMeetingAudio: Bool { didSet { defaults.set(keepMeetingAudio, forKey: Keys.keepMeetingAudio) } }
    @Published var makeMeetingMinutes: Bool { didSet { defaults.set(makeMeetingMinutes, forKey: Keys.makeMeetingMinutes) } }
    /// 会議で録音するスピーカー（出力機器）の UID。空なら Mac 全体の音
    @Published var meetingOutputDeviceUID: String { didSet { defaults.set(meetingOutputDeviceUID, forKey: Keys.meetingOutputDeviceUID) } }
    /// マイク側も話者分離する（会議室などで 1 つのマイクを複数人で使うとき）
    @Published var diarizeMicChannel: Bool { didSet { defaults.set(diarizeMicChannel, forKey: Keys.diarizeMicChannel) } }
    /// 会議で録音するマイクの UID。空ならシステムの設定に従う
    @Published var meetingInputDeviceUID: String { didSet { defaults.set(meetingInputDeviceUID, forKey: Keys.meetingInputDeviceUID) } }

    // 設計判断: DEC-COM-024
    /// Whisper に渡す言語コード（設定の言語 ja-JP → ja）。読めなければ日本語にする
    var whisperLanguage: String {
        Locale(identifier: localeIdentifier).language.languageCode?.identifier ?? "ja"
    }

    // 要件: REQ-COM-024
    // 設計判断: DEC-COM-040
    func aiProvider(for purpose: TextAIPurpose) -> TextAIProvider {
        purpose == .dictation ? dictationAIProvider : meetingAIProvider
    }

    /// 用途ごとの、選んだ AI のモデル（Gemini の音声入力は model、会議は meetingMinutesModel）
    func textModel(for purpose: TextAIPurpose) -> String {
        switch (purpose, aiProvider(for: purpose)) {
        case (.dictation, .gemini): model
        case (.dictation, .claude): claudeModel
        case (.meeting, .gemini): meetingMinutesModel
        case (.meeting, .claude): claudeMinutesModel
        case (_, .local): localModel(for: purpose).rawValue
        case (_, .appleFM): AppleFMClient.modelName
        }
    }

    // 要件: REQ-COM-030
    /// 用途ごとの、ローカルのモデル
    func localModel(for purpose: TextAIPurpose) -> LocalLLMModel {
        purpose == .dictation ? localDictationModel : localMeetingModel
    }

    /// ユーザー辞書の正しい表記の一覧（語だけの行と、置き換えルールの右側）。書き方は UserDictionary を参照
    var dictionaryWords: [String] {
        userDictionary.spellings
    }

    private init() {
        defaults.register(defaults: [
            Keys.model: Self.suggestedModels[0],
            Keys.authMode: GeminiAuthMode.apiKey.rawValue,
            // 設計判断: DEC-COM-040
            Keys.dictationAIProvider: TextAIProvider.gemini.rawValue,
            Keys.meetingAIProvider: TextAIProvider.gemini.rawValue,
            // 要件: REQ-COM-023
            Keys.claudeModel: ClaudeClient.Model.defaultDictation.rawValue,
            Keys.claudeMinutesModel: ClaudeClient.Model.defaultMeeting.rawValue,
            // 設計判断: DEC-COM-067
            Keys.localDictationModel: LocalLLMModel.defaultDictation.rawValue,
            Keys.localMeetingModel: LocalLLMModel.defaultMeeting.rawValue,
            // ターミナルから起動した場合は環境変数のパスを初期値にする
            Keys.serviceAccountPath: ProcessInfo.processInfo.environment["GEMINI_SERVICE_ACCOUNT_JSON"] ?? "",
            // 設計判断: DEC-COM-004
            Keys.vertexLocation: "global",
            Keys.hotKeyCode: Int(HotKeyCombo.default.keyCode),
            Keys.hotKeyModifiers: Int(HotKeyCombo.default.modifiers),
            Keys.translateHotKeyCode: Int(HotKeyCombo.defaultTranslate.keyCode),
            Keys.translateHotKeyModifiers: Int(HotKeyCombo.defaultTranslate.modifiers),
            Keys.recordingMode: RecordingMode.toggle.rawValue,
            // 設計判断: DEC-DIC-002
            Keys.engine: RecognizerEngine.speech.rawValue,
            // 要件: REQ-COM-002
            Keys.dictationEngine: TranscriptionEngine.apple.rawValue,
            Keys.meetingEngine: TranscriptionEngine.apple.rawValue,
            // 設計判断: DEC-COM-022
            Keys.whisperModel: WhisperModel.small.rawValue,
            Keys.geminiTranscriptionModel: Self.suggestedModels[0],
            Keys.locale: "ja-JP",
            Keys.refine: true,
            Keys.extraInstructions: "",
            Keys.dictionary: "",
            Keys.sounds: true,
            Keys.sendAppName: true,
            Keys.meetingHotKeyCode: Int(HotKeyCombo.defaultMeeting.keyCode),
            Keys.meetingHotKeyModifiers: Int(HotKeyCombo.defaultMeeting.modifiers),
            // 設計判断: DEC-MTG-014
            Keys.meetingMinutesModel: "gemini-3.8-flash",
            // 設計判断: DEC-MTG-016
            Keys.keepMeetingAudio: true,
            Keys.makeMeetingMinutes: true,
            Keys.meetingOutputDeviceUID: "",
            Keys.meetingInputDeviceUID: "",
            Keys.diarizeMicChannel: false,
        ])
        model = defaults.string(forKey: Keys.model)!
        authMode = GeminiAuthMode(rawValue: defaults.string(forKey: Keys.authMode)!) ?? .apiKey
        dictationAIProvider = TextAIProvider(rawValue: defaults.string(forKey: Keys.dictationAIProvider)!) ?? .gemini
        meetingAIProvider = TextAIProvider(rawValue: defaults.string(forKey: Keys.meetingAIProvider)!) ?? .gemini
        claudeModel = defaults.string(forKey: Keys.claudeModel)!
        claudeMinutesModel = defaults.string(forKey: Keys.claudeMinutesModel)!
        localDictationModel = LocalLLMModel(rawValue: defaults.string(forKey: Keys.localDictationModel)!) ?? .defaultDictation
        localMeetingModel = LocalLLMModel(rawValue: defaults.string(forKey: Keys.localMeetingModel)!) ?? .defaultMeeting
        serviceAccountPath = defaults.string(forKey: Keys.serviceAccountPath)!
        vertexLocation = defaults.string(forKey: Keys.vertexLocation)!
        hotKey = HotKeyCombo(
            keyCode: UInt32(defaults.integer(forKey: Keys.hotKeyCode)),
            modifiers: UInt32(defaults.integer(forKey: Keys.hotKeyModifiers)))
        translateHotKey = HotKeyCombo(
            keyCode: UInt32(defaults.integer(forKey: Keys.translateHotKeyCode)),
            modifiers: UInt32(defaults.integer(forKey: Keys.translateHotKeyModifiers)))
        recordingMode = RecordingMode(rawValue: defaults.string(forKey: Keys.recordingMode)!) ?? .toggle
        engine = RecognizerEngine(rawValue: defaults.string(forKey: Keys.engine)!) ?? .speech
        dictationEngine = TranscriptionEngine(rawValue: defaults.string(forKey: Keys.dictationEngine)!) ?? .apple
        meetingEngine = TranscriptionEngine(rawValue: defaults.string(forKey: Keys.meetingEngine)!) ?? .apple
        whisperModel = WhisperModel(rawValue: defaults.string(forKey: Keys.whisperModel)!) ?? .small
        geminiTranscriptionModel = defaults.string(forKey: Keys.geminiTranscriptionModel)!
        localeIdentifier = defaults.string(forKey: Keys.locale)!
        refineWithGemini = defaults.bool(forKey: Keys.refine)
        extraInstructions = defaults.string(forKey: Keys.extraInstructions)!
        dictionaryText = defaults.string(forKey: Keys.dictionary)!
        playSounds = defaults.bool(forKey: Keys.sounds)
        sendAppName = defaults.bool(forKey: Keys.sendAppName)
        meetingHotKey = HotKeyCombo(
            keyCode: UInt32(defaults.integer(forKey: Keys.meetingHotKeyCode)),
            modifiers: UInt32(defaults.integer(forKey: Keys.meetingHotKeyModifiers)))
        meetingMinutesModel = defaults.string(forKey: Keys.meetingMinutesModel)!
        keepMeetingAudio = defaults.bool(forKey: Keys.keepMeetingAudio)
        makeMeetingMinutes = defaults.bool(forKey: Keys.makeMeetingMinutes)
        meetingOutputDeviceUID = defaults.string(forKey: Keys.meetingOutputDeviceUID)!
        meetingInputDeviceUID = defaults.string(forKey: Keys.meetingInputDeviceUID)!
        diarizeMicChannel = defaults.bool(forKey: Keys.diarizeMicChannel)
    }

    private enum Keys {
        static let model = "geminiModel"
        static let authMode = "geminiAuthMode"
        static let dictationAIProvider = "dictationTextAIProvider"
        static let meetingAIProvider = "meetingTextAIProvider"
        static let claudeModel = "claudeModel"
        static let claudeMinutesModel = "claudeMinutesModel"
        static let localDictationModel = "localDictationModel"
        static let localMeetingModel = "localMeetingModel"
        static let serviceAccountPath = "serviceAccountPath"
        static let vertexLocation = "vertexLocation"
        static let hotKeyCode = "hotKeyCode"
        static let hotKeyModifiers = "hotKeyModifiers"
        static let translateHotKeyCode = "translateHotKeyCode"
        static let translateHotKeyModifiers = "translateHotKeyModifiers"
        static let recordingMode = "recordingMode"
        static let engine = "recognizerEngine"
        static let dictationEngine = "dictationTranscriptionEngine"
        static let meetingEngine = "meetingTranscriptionEngine"
        static let whisperModel = "whisperModel"
        static let geminiTranscriptionModel = "geminiTranscriptionModel"
        static let locale = "localeIdentifier"
        static let refine = "refineWithGemini"
        static let extraInstructions = "extraInstructions"
        static let dictionary = "dictionaryText"
        static let sounds = "playSounds"
        static let sendAppName = "sendAppName"
        static let meetingHotKeyCode = "meetingHotKeyCode"
        static let meetingHotKeyModifiers = "meetingHotKeyModifiers"
        static let meetingMinutesModel = "meetingMinutesModel"
        static let keepMeetingAudio = "keepMeetingAudio"
        static let makeMeetingMinutes = "makeMeetingMinutes"
        static let meetingOutputDeviceUID = "meetingOutputDeviceUID"
        static let meetingInputDeviceUID = "meetingInputDeviceUID"
        static let diarizeMicChannel = "diarizeMicChannel"
    }
}
