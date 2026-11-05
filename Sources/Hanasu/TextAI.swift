import Foundation

// 要件: REQ-COM-020, REQ-COM-030, REQ-COM-031
// 設計判断: DEC-COM-040
/// 整形などの文章の処理に使う AI。文字起こしのエンジン（OS 標準 / Whisper / Gemini）とは別に選ぶ
enum TextAIProvider: String, CaseIterable, Identifiable {
    case gemini
    case claude
    /// 端末の中で動く小型の LLM（llama.cpp）
    case local
    /// Apple の Foundation Models の CLI（fm。macOS 27 から）
    case appleFM = "apple"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .gemini: tr("%@（%@）", "Gemini", "Google")
        case .claude: tr("%@（%@）", "Claude", "Anthropic")
        case .local: tr("ローカル（この Mac の中）")
        case .appleFM: tr("%@（%@）", "Apple", "Foundation Models")
        }
    }
    var name: String {
        switch self {
        case .gemini: "Gemini"
        case .claude: "Claude"
        case .local: tr("ローカル")
        case .appleFM: "Apple"
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
        case .dictation: tr("音声入力")
        case .meeting: tr("会議")
        }
    }
}

enum TextAIError: LocalizedError {
    case missingCredentials(TextAIProvider)

    var errorDescription: String? {
        switch self {
        case .missingCredentials(.gemini): tr("Gemini の認証情報（API キーまたはサービスアカウント）が設定されていません（設定 →「AI」）")
        case .missingCredentials(.claude): tr("Claude の API キーが設定されていません（設定 →「AI」）")
        case .missingCredentials(.local): tr("ローカルの LLM のモデルがまだダウンロードされていません（設定 →「AI」でダウンロードしてください）")
        case .missingCredentials(.appleFM): AppleFMAvailability.check().reason ?? tr("Apple の Foundation Models（fm）を使えません")
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
        case local(LocalLLMClient)
        case appleFM(AppleFMClient)
    }

    var backend: Backend

    var provider: TextAIProvider {
        switch backend {
        case .gemini: .gemini
        case .claude: .claude
        case .local: .local
        case .appleFM: .appleFM
        }
    }

    /// 1 回のリクエストを待つ秒数
    var timeout: TimeInterval {
        get {
            switch backend {
            case .gemini(let client): client.timeout
            case .claude(let client): client.timeout
            case .local(let client): client.timeout
            case .appleFM(let client): client.timeout
            }
        }
        set {
            switch backend {
            case .gemini(var client): client.timeout = newValue; backend = .gemini(client)
            case .claude(var client): client.timeout = newValue; backend = .claude(client)
            case .local(var client): client.timeout = max(newValue, client.timeout); backend = .local(client)
            case .appleFM(var client): client.timeout = max(newValue, client.timeout); backend = .appleFM(client)
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
        case .local:
            // 要件: REQ-COM-030
            let model = settings.localModel(for: purpose)
            // 認証情報の「未設定」ではないので、何が足りないかを知らせる
            guard LocalLLMStore.isDownloaded(model) else { throw LocalLLMServer.Failure.modelNotDownloaded(model) }
            return TextAIClient(.local(LocalLLMClient(
                model: model, timeout: max(timeout, LocalLLMClient.minimumTimeout(for: purpose)))))
        case .appleFM:
            // 要件: REQ-COM-031
            // 設計判断: DEC-COM-071
            let availability = AppleFMAvailability.check()
            guard let url = availability.executableURL else { throw AppleFMError.unavailable(availability.reason ?? "") }
            return TextAIClient(.appleFM(AppleFMClient(
                executableURL: url, timeout: max(timeout, AppleFMClient.minimumTimeout(for: purpose)))))
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
        case .local(let client):
            let prompt = GeminiClient.refinePrompt(request)
            let output = try await client.generate(system: prompt.system, userText: prompt.user, purpose: .short)
            return LocalLLMClient.cleanUpRewrite(output, input: request.transcript)
        case .appleFM(let client):
            let prompt = GeminiClient.refinePrompt(request)
            let output = try await client.generate(system: prompt.system, userText: prompt.user, purpose: .short)
            return LocalLLMClient.cleanUpRewrite(output, input: request.transcript)
        }
    }

    // 要件: REQ-DIC-010, REQ-DIC-013
    func translate(_ request: GeminiClient.Request, to language: TranslationLanguage) async throws -> String {
        switch backend {
        case .gemini(let client):
            return try await client.translate(request, to: language)
        case .claude(let client):
            let prompt = GeminiClient.translationPrompt(request, to: language)
            return try await client.generate(system: prompt.system, userText: prompt.user, model: request.model, effort: .low)
        case .local(let client):
            let prompt = GeminiClient.translationPrompt(request, to: language)
            let output = try await client.generate(system: prompt.system, userText: prompt.user, purpose: .short)
            return LocalLLMClient.cleanUpRewrite(output, input: request.transcript)
        case .appleFM(let client):
            let prompt = GeminiClient.translationPrompt(request, to: language)
            let output = try await client.generate(system: prompt.system, userText: prompt.user, purpose: .short)
            return LocalLLMClient.cleanUpRewrite(output, input: request.transcript)
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
        case .local(let client):
            let output = try await client.generate(
                system: GeminiClient.editInstruction, userText: GeminiClient.editPrompt(for: request), purpose: .short)
            return GeminiClient.stripCodeFence(output, selection: request.selection)
        case .appleFM(let client):
            let output = try await client.generate(
                system: GeminiClient.editInstruction, userText: GeminiClient.editPrompt(for: request), purpose: .short)
            return GeminiClient.stripCodeFence(output, selection: request.selection)
        }
    }

    // MARK: - そのほか（辞書の候補・議事録・会議への質問）

    // 設計判断: DEC-COM-043
    /// テキストを 1 回送り、応答の本文を返す。effort は Claude のときだけ使う（Gemini はモデル名から thinkingLevel を決める）。
    /// ローカルでは effort で出力の上限を決める（low は整形などの短い処理、medium は議事録・会議への質問）
    func generate(systemInstruction: String, userText: String, model: String,
                  effort: ClaudeClient.Effort = .low) async throws -> String {
        switch backend {
        case .gemini(let client):
            return try await client.generate(systemInstruction: systemInstruction, userText: userText, model: model)
        case .claude(let client):
            return try await client.generate(system: systemInstruction, userText: userText, model: model, effort: effort)
        case .local(let client):
            return try await client.generate(system: systemInstruction, userText: userText, purpose: effort == .low ? .short : .long)
        case .appleFM(let client):
            return try await client.generate(system: systemInstruction, userText: userText, purpose: effort == .low ? .short : .long)
        }
    }
}

// MARK: - CLI での確認用

extension TextAIClient {
    /// CLI の確認で使うクライアント。`--ai gemini|claude` で AI を選ぶ（省くと設定のまま）。
    /// - Claude: 環境変数 ANTHROPIC_API_KEY → 設定（キーチェーン）の順
    /// - Gemini: 環境変数 GEMINI_SERVICE_ACCOUNT_JSON → 設定 → 環境変数 GEMINI_API_KEY の順（これまでどおり）
    /// - ローカル: `--model <id>`（gemma-4-e4b / lfm2.5-1.2b-jp / sarashina2.2-3b / qwen3.5-4b）か設定のモデル。ダウンロード済みであること
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
        case .local:
            let id = cliModel(args: args, settings: settings, for: purpose)
            guard let model = LocalLLMModel(rawValue: id) else {
                throw LocalLLMServer.Failure.unknownModel(id)
            }
            guard LocalLLMStore.isDownloaded(model) else { throw LocalLLMServer.Failure.modelNotDownloaded(model) }
            return TextAIClient(.local(LocalLLMClient(model: model, timeout: max(timeout, LocalLLMClient.minimumTimeout(for: purpose)))))
        case .appleFM:
            // 確認用に HANASU_FM_PATH で偽の fm を指定できる（AppleFMAvailability）
            let availability = AppleFMAvailability.check()
            guard let url = availability.executableURL else { throw AppleFMError.unavailable(availability.reason ?? "") }
            return TextAIClient(.appleFM(AppleFMClient(executableURL: url, timeout: max(timeout, AppleFMClient.minimumTimeout(for: purpose)))))
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
        case (_, .local): return settings.localModel(for: purpose).rawValue
        case (_, .appleFM): return AppleFMClient.modelName
        }
    }
}
