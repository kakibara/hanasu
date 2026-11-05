import Foundation

enum GeminiError: LocalizedError {
    case missingAPIKey
    case http(status: Int, message: String)
    case emptyResponse(reason: String?)
    case invalidResponse
    case invalidLocation(String)
    /// 「接続を試す」で、認証が通らなかった（400 API_KEY_INVALID / 401 / 403）
    case invalidCredentials(status: Int)
    /// 「接続を試す」で、モデルが見つからなかった（404）
    case modelUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Gemini の認証情報（API キーまたはサービスアカウント）が設定されていません"
        case .invalidCredentials(let status): "API キー（またはサービスアカウント）が正しくないか、Gemini API を使う権限がありません（\(status)）"
        case .modelUnavailable(let model): "モデル「\(model)」が見つからないか、この認証では使えません"
        case .http(let status, let message): "Gemini API エラー（\(status)）: \(message)"
        case .emptyResponse(let reason): "Gemini から結果が返りませんでした" + (reason.map { "（\($0)）" } ?? "")
        case .invalidResponse: "Gemini の応答を読み取れませんでした"
        case .invalidLocation(let location): "Vertex AI のリージョン「\(location)」は使えません（英小文字・数字・ハイフンだけ。例: global、us-central1）"
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
            case .asSpoken: "話した言語"
            case .japanese: "日本語に統一"
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

    // 設計判断: DEC-DIC-007, DEC-DIC-008, DEC-DIC-009, DEC-DIC-084, DEC-COM-054
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
        // 認識結果の中の区切りのタグは無害にしてから埋め込む（プロンプトインジェクションの対策。DEC-COM-054）
        lines.append("<transcript>\n\(PromptText.neutralizeDelimiters(request.transcript))\n</transcript>")
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
            // project_id は鍵ファイルの値なので、パスの区切りにならないよう（壊れた値で URL が作れず落ちないよう）エスケープする
            let escapedProject = credentials.projectID.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? credentials.projectID
            let url = URL(string: "https://\(host)/v1/projects/\(escapedProject)/locations/\(location)/publishers/google/models/\(escapedModel):generateContent")!
            let token = try await ServiceAccountTokenProvider.shared.accessToken(for: credentials)
            urlRequest = URLRequest(url: url, timeoutInterval: timeout)
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        // 設計判断: DEC-COM-044, DEC-COM-055
        // 429 / 503 と一時的な通信の失敗だけ、2 回までやり直す。全体で timeout の半分を超えるなら、やり直さない
        let startedAt = Date()
        var attempt = 0
        var received: (Data, HTTPURLResponse)
        while true {
            do {
                let (data, response) = try await SecureHTTP.data(for: urlRequest)
                guard let http = response as? HTTPURLResponse else { throw GeminiError.invalidResponse }
                received = (data, http)
            } catch let error as URLError where Self.isTransientNetworkError(error) {
                guard let wait = Self.retryDelay(attempt: attempt, elapsed: Date().timeIntervalSince(startedAt), timeout: timeout)
                else { throw error }
                attempt += 1
                try await Task.sleep(for: .seconds(wait))
                urlRequest.timeoutInterval = max(1, timeout - Date().timeIntervalSince(startedAt))
                continue
            }
            let status = received.1.statusCode
            guard status == 429 || status == 503,
                  let wait = Self.retryDelay(attempt: attempt, elapsed: Date().timeIntervalSince(startedAt), timeout: timeout)
            else { break }
            attempt += 1
            try await Task.sleep(for: .seconds(wait))
            urlRequest.timeoutInterval = max(1, timeout - Date().timeIntervalSince(startedAt))
        }
        let (data, http) = received
        guard (200..<300).contains(http.statusCode) else {
            let decoded = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
            // 文言は HUD と履歴に出るので、JSON でない応答（HTML のエラーページなど）は先頭だけにする（Windows 版と同じ 500 文字）
            let message = String((decoded?.error.message ?? String(data: data, encoding: .utf8) ?? "").prefix(500))
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

    // 設計判断: DEC-COM-050
    /// 「接続を試す」: モデルの情報を GET で取る（トークンを使わない。Claude の testConnection と同じ考え）。
    /// API キーは generativelanguage の GET /v1beta/models/{model}、サービスアカウントは Vertex AI の
    /// GET /v1/publishers/google/models/{model}（アクセストークンが取れることも確かめられる）。
    /// 認証が通らなければ 400（API_KEY_INVALID）/ 401 / 403、モデルがなければ 404 が返る。やり直しはしない
    func testConnection(model rawModel: String) async throws {
        let model = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let escapedModel = model.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? model
        var urlRequest: URLRequest
        switch auth {
        case .apiKey(let apiKey):
            guard !apiKey.isEmpty else { throw GeminiError.missingAPIKey }
            let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(escapedModel)")!
            urlRequest = URLRequest(url: url, timeoutInterval: timeout)
            urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        case .serviceAccount(let credentials, let location):
            // 設計判断: DEC-COM-053（generate と同じ検査）
            guard Self.isValidLocation(location) else { throw GeminiError.invalidLocation(location) }
            let host = location == "global" ? "aiplatform.googleapis.com" : "\(location)-aiplatform.googleapis.com"
            let token = try await ServiceAccountTokenProvider.shared.accessToken(for: credentials)
            let url = URL(string: "https://\(host)/v1/publishers/google/models/\(escapedModel)")!
            urlRequest = URLRequest(url: url, timeoutInterval: timeout)
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.httpMethod = "GET"
        let (data, response) = try await SecureHTTP.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw GeminiError.invalidResponse }
        switch http.statusCode {
        case 200..<300: return
        case 400, 401, 403: throw GeminiError.invalidCredentials(status: http.statusCode)
        case 404: throw GeminiError.modelUnavailable(model)
        default:
            let decoded = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
            let message = String((decoded?.error.message ?? String(data: data, encoding: .utf8) ?? "").prefix(500))
            throw GeminiError.http(status: http.statusCode, message: message)
        }
    }

    // 設計判断: DEC-COM-055
    /// やり直すまでの待ち（0.5 秒・1 秒）。最大 2 回まで。ここまでにかかった時間と待ちの合計が timeout の半分を超えるなら nil（やり直さない）
    static func retryDelay(attempt: Int, elapsed: TimeInterval, timeout: TimeInterval) -> TimeInterval? {
        guard attempt < 2 else { return nil }
        let wait = 0.5 * pow(2, Double(attempt))
        return elapsed + wait <= timeout / 2 ? wait : nil
    }

    // 設計判断: DEC-COM-055
    /// 一時的な通信の失敗（接続が切れた・つながらない・名前が引けない）。タイムアウトは予算を使い切っているのでやり直さない
    static func isTransientNetworkError(_ error: URLError) -> Bool {
        [.networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed].contains(error.code)
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
