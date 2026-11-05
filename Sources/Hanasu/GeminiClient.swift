import Foundation

enum GeminiError: LocalizedError {
    case missingAPIKey
    case http(status: Int, message: String)
    case emptyResponse(reason: String?)
    case invalidResponse
    case invalidLocation(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: tr("Gemini の認証情報（API キーまたはサービスアカウント）が設定されていません")
        case .http(let status, let message): tr("Gemini API エラー（%@）: %@", "\(status)", "\(message)")
        case .emptyResponse(let reason): tr("Gemini から結果が返りませんでした") + (reason.map { "（\($0)）" } ?? "")
        case .invalidResponse: tr("Gemini の応答を読み取れませんでした")
        case .invalidLocation(let location): tr("Vertex AI のリージョン「%@」は使えません（英小文字・数字・ハイフンだけ。例: global、us-central1）", "\(location)")
        }
    }
}

/// 音声認識の結果を Gemini で自然な文章に整える（出力の言語は設定の「整形の言語」に従う。REQ-DIC-082）か、翻訳の言語（英語・日本語）に翻訳する。
struct GeminiClient {
    struct Request {
        var transcript: String
        var model: String
        var appName: String?
        var dictionary: [String]
        var extraInstructions: String
        /// ユーザー辞書の置き換えルール（認識結果には先に当ててあるが、近い音の語も直せるよう Gemini にも渡す）
        var dictionaryRules: [UserDictionary.Rule] = []
        /// 入力先アプリ別の文体ルール（AppStyles.swift）。nil なら使わない
        var appStyle: AppStyle? = nil
        /// 録音を始めたときの画面の文脈（設定でオンのときだけ）
        var screenContext: ScreenContext? = nil
        // 要件: REQ-DIC-082
        /// 整形の出力の言語（設定の「整形の言語」）
        var outputLanguage: RefineOutputLanguage = .asSpoken
    }

    // 要件: REQ-DIC-082
    /// 整形の出力の言語。既定は話した言語（英語は英語のまま残し、日本語に訳さない）
    enum RefineOutputLanguage: String, CaseIterable, Identifiable {
        case asSpoken
        case japanese

        var id: String { rawValue }

        var label: String {
            switch self {
            case .asSpoken: tr("話した言語")
            case .japanese: tr("日本語に統一")
            }
        }

        // 要件: REQ-COM-061
        // 設計判断: DEC-COM-102（Windows 版の GeminiPrompts.LanguageInstruction と同じ文面。どちらも Prompts の JSON を読む）
        var instruction: String {
            switch self {
            case .asSpoken: Prompts.text("refine.outputLanguage.asSpoken")
            case .japanese: Prompts.text("refine.outputLanguage.japanese")
            }
        }
    }

    // 設計判断: DEC-COM-001
    enum Auth {
        /// Google AI Studio の API キー（generativelanguage.googleapis.com）
        case apiKey(String)
        /// Google Cloud のサービスアカウント（Vertex AI, aiplatform.googleapis.com）
        case serviceAccount(ServiceAccountCredentials, location: String)
    }

    var auth: Auth
    // 設計判断: DEC-DIC-010
    var timeout: TimeInterval = 15

    // 設計判断: DEC-COM-001
    /// 設定から認証方法を決める。必要な情報が揃っていなければ nil。
    static func authFromSettings(_ settings: AppSettings) throws -> Auth? {
        switch settings.authMode {
        case .apiKey:
            return try Keychain.load(.geminiAPIKey).map(Auth.apiKey)
        case .serviceAccount:
            let path = settings.serviceAccountPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { return nil }
            return .serviceAccount(try ServiceAccountCredentials.load(path: path), location: settings.vertexLocation)
        }
    }

    // 要件: REQ-DIC-003, REQ-COM-061
    // 設計判断: DEC-DIC-005, DEC-DIC-006
    /// 整形の指示（文面は Resources/Prompts/<言語>.json の refine.system）
    static var systemInstruction: String { Prompts.text("refine.system") }

    // 要件: REQ-DIC-010, REQ-COM-061
    // 設計判断: DEC-DIC-024
    static var translationInstruction: String { Prompts.text("translate.english.system") }

    // 要件: REQ-DIC-013, REQ-COM-061
    // 設計判断: DEC-DIC-028（Windows 版の GeminiPrompts.JapaneseTranslationInstruction と同じ文面。どちらも Prompts の JSON を読む）
    static var japaneseTranslationInstruction: String { Prompts.text("translate.japanese.system") }

    // 設計判断: DEC-COM-006
    static func thinkingLevel(for model: String) -> String {
        model.contains("lite") ? "minimal" : "low"
    }

    // 設計判断: DEC-DIC-007, DEC-DIC-008, DEC-DIC-009, DEC-DIC-084
    static func userPrompt(for request: Request, translation: TranslationLanguage? = nil) -> String {
        var lines: [String] = []
        if let appName = request.appName, !appName.isEmpty {
            lines.append(Prompts.text("user.appName", ["app": appName]))
        }
        if !request.dictionary.isEmpty {
            lines.append(Prompts.text("user.dictionary", ["words": request.dictionary.joined(separator: ", ")]))
        }
        if !request.dictionaryRules.isEmpty {
            let separator = Prompts.text("user.dictionaryRuleSeparator")
            let rules = request.dictionaryRules.map { "- \($0.sources.joined(separator: separator)) → \($0.target)" }
            lines.append(Prompts.text("user.dictionaryRules") + "\n" + rules.joined(separator: "\n"))
        }
        let extra = request.extraInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty {
            lines.append(Prompts.text("user.extraRules") + "\n" + extra)
        }
        if let section = request.appStyle?.promptSection(appName: request.appName, translation: translation, hasCommonRules: !extra.isEmpty) {
            lines.append(section)
        }
        if let block = request.screenContext?.promptBlock() {
            lines.append(block)
        }
        lines.append("<transcript>\n\(request.transcript)\n</transcript>")
        return lines.joined(separator: "\n")
    }

    // 要件: REQ-DIC-003
    func refine(_ request: Request) async throws -> String {
        let prompt = Self.refinePrompt(request)
        return try await generate(systemInstruction: prompt.system, userText: prompt.user, model: request.model)
    }

    // 要件: REQ-DIC-003
    // 設計判断: DEC-COM-047
    /// 整形のシステムプロンプトと user content。Claude でも同じ文面を使う（TextAIClient）
    static func refinePrompt(_ request: Request) -> (system: String, user: String) {
        // 要件: REQ-DIC-082
        (systemInstruction + "\n\n" + request.outputLanguage.instruction
            + ScreenContext.instruction(for: request.screenContext, translation: nil),
         userPrompt(for: request))
    }

    // 要件: REQ-DIC-010, REQ-DIC-013
    func translate(_ request: Request, to language: TranslationLanguage) async throws -> String {
        let prompt = Self.translationPrompt(request, to: language)
        return try await generate(systemInstruction: prompt.system, userText: prompt.user, model: request.model)
    }

    // 要件: REQ-DIC-010, REQ-DIC-013
    // 設計判断: DEC-DIC-022, DEC-DIC-023, DEC-DIC-028, DEC-COM-047
    /// 話した内容を翻訳するときのプロンプト。
    /// 英訳: 追加の整形ルールは日本語の文体向けなので使わない。アプリ別の文体ルールは、英訳向けのルールに切り替えて使う。
    /// 和訳: 出力が日本語なので、追加の整形ルールとアプリ別の日本語の文体ルールをそのまま使う。
    static func translationPrompt(_ request: Request, to language: TranslationLanguage) -> (system: String, user: String) {
        var request = request
        switch language {
        case .english:
            request.extraInstructions = ""
            return (translationInstruction + ScreenContext.instruction(for: request.screenContext, translation: .english),
                    userPrompt(for: request, translation: .english))
        case .japanese:
            return (japaneseTranslationInstruction + ScreenContext.instruction(for: request.screenContext, translation: .japanese),
                    userPrompt(for: request, translation: .japanese))
        }
    }

    /// テキストを 1 回送り、応答の本文を返す。thinkingLevel を省くとモデル名から決める。
    func generate(systemInstruction: String, userText: String, model rawModel: String, thinkingLevel: String? = nil) async throws -> String {
        try await generate(systemInstruction: systemInstruction, parts: [["text": userText]], model: rawModel, thinkingLevel: thinkingLevel)
    }

    // 設計判断: DEC-COM-001, DEC-COM-007
    /// user content のパート（テキストのほか、inline data の音声など）を送る。
    /// responseSchema を渡すと JSON で返させる（GeminiTranscriber.swift の会議の文字起こし）
    func generate(systemInstruction: String, parts: [[String: Any]], model rawModel: String, thinkingLevel: String? = nil,
                  responseSchema: [String: Any]? = nil) async throws -> String {
        let model = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let escapedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model

        var generationConfig: [String: Any] = [
            "responseMimeType": responseSchema == nil ? "text/plain" : "application/json",
            "thinkingConfig": ["thinkingLevel": thinkingLevel ?? Self.thinkingLevel(for: model)],
        ]
        if let responseSchema { generationConfig["responseSchema"] = responseSchema }
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": systemInstruction]]],
            "contents": [["role": "user", "parts": parts]],
            "generationConfig": generationConfig,
        ]

        var urlRequest: URLRequest
        switch auth {
        case .apiKey(let apiKey):
            guard !apiKey.isEmpty else { throw GeminiError.missingAPIKey }
            let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(escapedModel):generateContent")!
            urlRequest = URLRequest(url: url, timeoutInterval: timeout)
            urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        case .serviceAccount(let credentials, let location):
            // 設計判断: DEC-COM-053
            // リージョンはホスト名に入るので、英小文字・数字・ハイフンだけを受け付ける（別のホストに向けられないように）
            guard Self.isValidLocation(location) else { throw GeminiError.invalidLocation(location) }
            // global 以外のリージョンはホスト名にリージョンが付く
            let host = location == "global" ? "aiplatform.googleapis.com" : "\(location)-aiplatform.googleapis.com"
            let url = URL(string: "https://\(host)/v1/projects/\(credentials.projectID)/locations/\(location)/publishers/google/models/\(escapedModel):generateContent")!
            let token = try await ServiceAccountTokenProvider.shared.accessToken(for: credentials)
            urlRequest = URLRequest(url: url, timeoutInterval: timeout)
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        // 設計判断: DEC-COM-044
        let (data, response) = try await SecureHTTP.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw GeminiError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let decoded = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
            let message = decoded?.error.message ?? String(data: data, encoding: .utf8) ?? ""
            throw GeminiError.http(status: http.statusCode, message: message)
        }

        let decoded = try JSONDecoder().decode(GenerateContentResponse.self, from: data)
        guard let candidate = decoded.candidates?.first else {
            throw GeminiError.emptyResponse(reason: decoded.promptFeedback?.blockReason)
        }
        // thought: true のパートは思考の要約なので除く
        let text = (candidate.content?.parts ?? [])
            .filter { $0.thought != true }
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw GeminiError.emptyResponse(reason: candidate.finishReason) }
        return text
    }

    // 設計判断: DEC-COM-053
    static func isValidLocation(_ location: String) -> Bool {
        !location.isEmpty && location.count <= 40
            && location.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
    }

    private struct GenerateContentResponse: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable {
                    var text: String?
                    var thought: Bool?
                }
                var parts: [Part]?
            }
            var content: Content?
            var finishReason: String?
        }
        struct PromptFeedback: Decodable {
            var blockReason: String?
        }
        var candidates: [Candidate]?
        var promptFeedback: PromptFeedback?
    }

    private struct ErrorEnvelope: Decodable {
        struct Body: Decodable { var message: String }
        var error: Body
    }
}
