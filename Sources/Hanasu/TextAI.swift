import Foundation

// 要件: REQ-COM-020
// 設計判断: DEC-COM-040
/// 整形などの文章の処理に使う AI。文字起こしのエンジン（OS 標準 / Whisper / Gemini）とは別に選ぶ
enum TextAIProvider: String, CaseIterable, Identifiable {
    case gemini
    case claude

    var id: String { rawValue }
    var label: String {
        switch self {
        case .gemini: "Gemini（Google）"
        case .claude: "Claude（Anthropic）"
        }
    }
    var name: String {
        switch self {
        case .gemini: "Gemini"
        case .claude: "Claude"
        }
    }
}

// 要件: REQ-COM-024
// 設計判断: DEC-COM-040
/// AI とモデルを別々に選ぶ用途
enum TextAIPurpose: String, CaseIterable, Identifiable {
    /// 音声入力: 整形・英訳・選択の編集
    case dictation
    /// 会議: 議事録（作り直しを含む）・会議への質問。辞書の候補探しもこちら（会議の記録を読む長い処理なので）
    case meeting

    var id: String { rawValue }
    var label: String {
        switch self {
        case .dictation: "音声入力"
        case .meeting: "会議"
        }
    }
}

enum TextAIError: LocalizedError {
    case missingCredentials(TextAIProvider)

    var errorDescription: String? {
        switch self {
        case .missingCredentials(.gemini): "Gemini の認証情報（API キーまたはサービスアカウント）が設定されていません（設定 →「AI」）"
        case .missingCredentials(.claude): "Claude の API キーが設定されていません（設定 →「AI」）"
        }
    }
}

// 要件: REQ-COM-020
// 設計判断: DEC-COM-040, DEC-COM-047
/// 整形・英訳・選択の編集・辞書の候補・議事録・会議への質問を、設定で選んだ AI に送る。
/// プロンプトの文面は Gemini と同じもの（GeminiClient の static）を使い、送り先だけを変える。
struct TextAIClient {
    enum Backend {
        case gemini(GeminiClient)
        case claude(ClaudeClient)
    }

    var backend: Backend

    var provider: TextAIProvider {
        switch backend {
        case .gemini: .gemini
        case .claude: .claude
        }
    }

    /// 1 回のリクエストを待つ秒数
    var timeout: TimeInterval {
        get {
            switch backend {
            case .gemini(let client): client.timeout
            case .claude(let client): client.timeout
            }
        }
        set {
            switch backend {
            case .gemini(var client): client.timeout = newValue; backend = .gemini(client)
            case .claude(var client): client.timeout = newValue; backend = .claude(client)
            }
        }
    }

    init(_ backend: Backend) { self.backend = backend }

    /// 設定でその用途に選んだ AI のクライアント。認証情報がまだなければ nil
    static func fromSettings(_ settings: AppSettings, for purpose: TextAIPurpose, timeout: TimeInterval = 15) throws -> TextAIClient? {
        switch settings.aiProvider(for: purpose) {
        case .gemini:
            return try GeminiClient.authFromSettings(settings).map { TextAIClient(.gemini(GeminiClient(auth: $0, timeout: timeout))) }
        case .claude:
            return ClaudeClient.fromKeychain(timeout: timeout).map { TextAIClient(.claude($0)) }
        }
    }

    /// fromSettings と同じ。認証情報がなければ、分かる文言のエラーにする
    static func requireFromSettings(_ settings: AppSettings, for purpose: TextAIPurpose, timeout: TimeInterval = 15) throws -> TextAIClient {
        guard let client = try fromSettings(settings, for: purpose, timeout: timeout) else {
            throw TextAIError.missingCredentials(settings.aiProvider(for: purpose))
        }
        return client
    }

    // MARK: - 音声入力

    // 要件: REQ-DIC-003
    func refine(_ request: GeminiClient.Request) async throws -> String {
        switch backend {
        case .gemini(let client):
            return try await client.refine(request)
        case .claude(let client):
            let prompt = GeminiClient.refinePrompt(request)
            return try await client.generate(system: prompt.system, userText: prompt.user, model: request.model, effort: .low)
        }
    }

    // 要件: REQ-DIC-010
    func translateToEnglish(_ request: GeminiClient.Request) async throws -> String {
        switch backend {
        case .gemini(let client):
            return try await client.translateToEnglish(request)
        case .claude(let client):
            let prompt = GeminiClient.translationPrompt(request)
            return try await client.generate(system: prompt.system, userText: prompt.user, model: request.model, effort: .low)
        }
    }

    // 要件: REQ-DIC-050
    func editSelection(_ request: GeminiClient.EditRequest) async throws -> String {
        switch backend {
        case .gemini(let client):
            return try await client.editSelection(request)
        case .claude(let client):
            let output = try await client.generate(
                system: GeminiClient.editInstruction, userText: GeminiClient.editPrompt(for: request),
                model: request.model, effort: .low)
            return GeminiClient.stripCodeFence(output, selection: request.selection)
        }
    }

    // MARK: - そのほか（辞書の候補・議事録・会議への質問）

    // 設計判断: DEC-COM-043
    /// テキストを 1 回送り、応答の本文を返す。effort は Claude のときだけ使う（Gemini はモデル名から thinkingLevel を決める）
    func generate(systemInstruction: String, userText: String, model: String,
                  effort: ClaudeClient.Effort = .low) async throws -> String {
        switch backend {
        case .gemini(let client):
            return try await client.generate(systemInstruction: systemInstruction, userText: userText, model: model)
        case .claude(let client):
            return try await client.generate(system: systemInstruction, userText: userText, model: model, effort: effort)
        }
    }
}

// MARK: - CLI での確認用

extension TextAIClient {
    /// CLI の確認で使うクライアント。`--ai gemini|claude` で AI を選ぶ（省くと設定のまま）。
    /// - Claude: 環境変数 ANTHROPIC_API_KEY → 設定（キーチェーン）の順
    /// - Gemini: 環境変数 GEMINI_SERVICE_ACCOUNT_JSON → 設定 → 環境変数 GEMINI_API_KEY の順（これまでどおり）
    static func cli(args: [String], settings: AppSettings, for purpose: TextAIPurpose, timeout: TimeInterval = 15) throws -> TextAIClient {
        let env = ProcessInfo.processInfo.environment
        switch cliProvider(args: args, settings: settings, for: purpose) {
        case .claude:
            if let key = env["ANTHROPIC_API_KEY"], !key.isEmpty {
                return TextAIClient(.claude(ClaudeClient(apiKey: { key }, timeout: timeout)))
            }
            return TextAIClient(.claude(ClaudeClient(apiKey: { try Keychain.load(.claudeAPIKey) }, timeout: timeout)))
        case .gemini:
            let auth: GeminiClient.Auth
            if let path = env["GEMINI_SERVICE_ACCOUNT_JSON"], !path.isEmpty {
                auth = .serviceAccount(try ServiceAccountCredentials.load(path: path), location: settings.vertexLocation)
            } else {
                auth = try GeminiClient.authFromSettings(settings) ?? .apiKey(env["GEMINI_API_KEY"] ?? "")
            }
            return TextAIClient(.gemini(GeminiClient(auth: auth, timeout: timeout)))
        }
    }

    static func cliProvider(args: [String], settings: AppSettings, for purpose: TextAIPurpose) -> TextAIProvider {
        args.firstIndex(of: "--ai").flatMap { args.indices.contains($0 + 1) ? TextAIProvider(rawValue: args[$0 + 1]) : nil }
            ?? settings.aiProvider(for: purpose)
    }

    /// `--model` があればそれ、なければその用途で選んだ AI の設定のモデル
    static func cliModel(args: [String], settings: AppSettings, for purpose: TextAIPurpose) -> String {
        if let model = args.firstIndex(of: "--model").flatMap({ args.indices.contains($0 + 1) ? args[$0 + 1] : nil }) {
            return model
        }
        switch (purpose, cliProvider(args: args, settings: settings, for: purpose)) {
        case (.dictation, .claude): return settings.claudeModel
        case (.dictation, .gemini): return settings.model
        case (.meeting, .claude): return settings.claudeMinutesModel
        case (.meeting, .gemini): return settings.meetingMinutesModel
        }
    }
}
