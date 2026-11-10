import Foundation

enum ClaudeError: LocalizedError {
    case missingAPIKey
    /// 401: キーが正しくない（取り消された・打ち間違い）
    case unauthorized
    case http(status: Int, type: String?, message: String)
    /// 安全のための判定で断られた（stop_reason: "refusal"）
    case refusal(category: String?)
    /// max_tokens で応答が切れた
    case truncated
    case emptyResponse
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            tr("Claude の API キーが設定されていません（設定 →「AI」）")
        case .unauthorized:
            tr("Claude の API キーが正しくありません（401）。設定 →「AI」でキーを入れ直してください")
        case .http(let status, let type, let message):
            Self.describe(status: status, type: type, message: message)
        case .refusal(let category):
            tr("Claude が安全のための判定で応答を断りました") + (category.map { tr("（%@）", $0) } ?? "")
        case .truncated:
            tr("Claude の応答が長さの上限（max_tokens）で切れたため、使いませんでした")
        case .emptyResponse:
            tr("Claude から結果が返りませんでした")
        case .invalidResponse:
            tr("Claude の応答を読み取れませんでした")
        }
    }

    // 設計判断: DEC-COM-046
    private static func describe(status: Int, type: String?, message: String) -> String {
        let detail = message.isEmpty ? "" : ": \(message)"
        switch status {
        case 400: return tr("Claude API がリクエストを受け付けませんでした（400）%@", "\(detail)")
        case 402: return tr("Claude API の支払いの設定に問題があります（402）。Anthropic の Console を確かめてください")
        case 403: return tr("この API キーでは許可されていない操作です（403）%@", "\(detail)")
        case 404: return tr("Claude のモデルが見つからないか、この API キーでは使えません（404）%@", "\(detail)")
        case 413: return tr("Claude に送る文章が長すぎます（413）")
        case 429: return tr("Claude API の利用の上限に達しました（429）。しばらく待ってから試してください")
        case 529: return tr("Claude API が混み合っています（529）。しばらく待ってから試してください")
        case 500..<600: return tr("Claude API でエラーが起きました（%@）%@", "\(status)", "\(detail)")
        default: return tr("Claude API エラー（%@%@）%@", "\(status)", "\(type.map { " \($0)" } ?? "")", "\(detail)")
        }
    }
}

// 要件: REQ-COM-020
// 設計判断: DEC-COM-041
/// Claude API（Anthropic の Messages API）を REST で呼ぶ。Swift の公式 SDK はないので URLSession で送る。
/// 音声は送らない（文字起こしには使わない）。文章の処理（整形・英訳・選択の編集・辞書の候補・議事録・会議への質問）だけに使う。
struct ClaudeClient {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let apiVersion = "2026-10-21"
    /// refusal のとき、server-side で別のモデルに切り替えてもらう（`fallbacks: "default"` の形）
    static let fallbackBeta = "server-side-fallback-2026-07-01"

    // 要件: REQ-COM-023
    // 設計判断: DEC-COM-042
    enum Model: String, CaseIterable, Identifiable {
        case haiku = "claude-haiku-5-5"
        case sonnet = "claude-sonnet-5-5"
        case opus = "claude-opus-5-5"

        /// 音声入力（整形・英訳・選択の編集）の既定。待ち時間が短いもの
        static let defaultDictation = Model.haiku
        /// 会議（議事録・辞書の候補）の既定。長い記録をまとめる
        static let defaultMeeting = Model.sonnet
        // 要件: REQ-COM-023, REQ-COM-025
        // 設計判断: DEC-COM-171
        /// AI チャット・質問の既定。対話なので待ち時間が短いもの
        static let defaultChat = Model.haiku

        /// 送り先のメニューに出す短い名前（製品名なので訳さない）
        var shortName: String {
            switch self {
            case .haiku: "Haiku 5.5"
            case .sonnet: "Sonnet 5.5"
            case .opus: "Opus 5.5"
            }
        }

        var id: String { rawValue }
        var label: String {
            switch self {
            case .haiku: tr("Claude Haiku 5.5（速い・安い。音声入力と AI チャット・質問の既定）")
            case .sonnet: tr("Claude Sonnet 5.5（会議の既定）")
            case .opus: tr("Claude Opus 5.5（いちばん賢い・遅い）")
            }
        }

        // 設計判断: DEC-COM-045
        /// server-side fallback があるか。Haiku 5.5 にはない（fallbacks を付けると 400 か、断られたまま）
        var supportsServerSideFallback: Bool { self != .haiku }
    }

    // 設計判断: DEC-COM-043
    /// 考える量（output_config.effort）。thinking は送らない（3 つのモデルとも adaptive が既定で、
    /// Opus 5.5 は無効にできず、Sonnet 5.5 は disabled が 400 になるため）。考える量は effort だけで決める
    enum Effort: String {
        /// 整形・英訳・選択の編集・辞書の候補
        case low
        /// 議事録・会議への質問
        case medium

        /// thinking も max_tokens に数えられるので、返ってくる文章より大きめに取る
        var maxTokens: Int {
            switch self {
            case .low: 8192
            case .medium: 32000
            }
        }

        /// 1 回のリクエストを待つ最短の秒数。議事録は streaming を使わずに待つので、出力が長くても切れないだけ取る
        var minimumTimeout: TimeInterval {
            switch self {
            case .low: 0
            case .medium: 600
            }
        }
    }

    // 設計判断: DEC-COM-049
    /// API キーは持たず、送るたびに読む（キーチェーンか、CLI では環境変数）
    var apiKey: () throws -> String?
    var timeout: TimeInterval = 15

    // 設計判断: DEC-COM-049
    /// 設定（キーチェーン）のキーを使う。キーがまだ入っていなければ nil
    static func fromKeychain(timeout: TimeInterval = 15) -> ClaudeClient? {
        guard Keychain.exists(.claudeAPIKey) else { return nil }
        return ClaudeClient(apiKey: { try Keychain.load(.claudeAPIKey) }, timeout: timeout)
    }

    // MARK: - リクエストの組み立て

    // 設計判断: DEC-COM-043, DEC-COM-045, DEC-COM-047
    /// Messages API の本文。temperature / top_p / top_k（この版の API では 400）と assistant の prefill は送らない。
    /// システムプロンプトは固定の文面なので、cache_control を付けてプロンプトキャッシュを効かせる
    /// （最小のトークン数＝512 に満たなければ、エラーにはならず、キャッシュされないだけ）
    static func requestBody(system: String, userText: String, model: String, effort: Effort) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": effort.maxTokens,
            "system": [["type": "text", "text": system, "cache_control": ["type": "ephemeral"]]],
            "messages": [["role": "user", "content": userText]],
            "output_config": ["effort": effort.rawValue],
        ]
        if Model(rawValue: model)?.supportsServerSideFallback == true {
            body["fallbacks"] = "default"
        }
        return body
    }

    static func headers(apiKey: String, model: String) -> [String: String] {
        var headers = [
            "x-api-key": apiKey,
            "anthropic-version": apiVersion,
            "content-type": "application/json",
        ]
        if Model(rawValue: model)?.supportsServerSideFallback == true {
            headers["anthropic-beta"] = fallbackBeta
        }
        return headers
    }

    // 要件: REQ-COM-021
    /// 表示用に、キーを伏せる（先頭の「sk-ant-」と末尾 4 文字だけ残す）
    static func redacted(_ key: String) -> String {
        guard key.count > 12 else { return tr("（伏せた %@ 文字）", "\(key.count)") }
        let prefix = key.hasPrefix("sk-ant-") ? "sk-ant-" : ""
        return tr("%@…%@（伏せた %@ 文字）", "\(prefix)", "\(key.suffix(4))", "\(key.count)")
    }

    /// 送る内容の確認用（CLI の --show-request）。キーの値は伏せる
    static func describeRequest(system: String, userText: String, model: String, effort: Effort, apiKey: String?) -> String {
        let body = requestBody(system: system, userText: userText, model: model, effort: effort)
        let json = (try? JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]))
            .map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        let shownKey = apiKey.map(redacted) ?? tr("（未設定）")
        let headerLines = headers(apiKey: shownKey, model: model).sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
        return (["POST \(endpoint.absoluteString)"] + headerLines + ["", json]).joined(separator: "\n")
    }

    // MARK: - 送る

    /// テキストを 1 回送り、応答の本文（text のブロック）を返す
    func generate(system: String, userText: String, model rawModel: String, effort: Effort) async throws -> String {
        let model = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = Self.requestBody(system: system, userText: userText, model: model, effort: effort)
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let data = try await send(model: model) { key in
            var request = URLRequest(url: Self.endpoint, timeoutInterval: max(timeout, effort.minimumTimeout))
            request.httpMethod = "POST"
            for (name, value) in Self.headers(apiKey: key, model: model) { request.setValue(value, forHTTPHeaderField: name) }
            request.httpBody = bodyData
            return request
        }
        return try Self.parseMessage(data)
    }

    // 設計判断: DEC-COM-050
    /// 「接続を試す」: GET /v1/models/{model}。キーが正しいことと、そのモデルを使えることを、トークンを使わずに確かめる
    func testConnection(model rawModel: String) async throws {
        let model = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let escaped = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? model
        let url = URL(string: "https://api.anthropic.com/v1/models/\(escaped)")!
        _ = try await send(model: model) { key in
            var request = URLRequest(url: url, timeoutInterval: timeout)
            request.httpMethod = "GET"
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
            return request
        }
    }

    // 設計判断: DEC-COM-046
    /// 429 と 5xx（529 を含む）だけ、retry-after を見て 2 回までやり直す。待ち時間が長すぎるときはやり直さない。
    /// 400 / 401 / 403 / 404 などはやり直さない
    private func send(model: String, makeRequest: (String) -> URLRequest) async throws -> Data {
        let maxRetries = 2
        var attempt = 0
        while true {
            // キーは送るたびに読み、この関数の外には持ち出さない
            guard let key = try apiKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
                throw ClaudeError.missingAPIKey
            }
            let (data, response) = try await SecureHTTP.data(for: makeRequest(key))
            guard let http = response as? HTTPURLResponse else { throw ClaudeError.invalidResponse }
            if (200..<300).contains(http.statusCode) { return data }

            let error = Self.error(status: http.statusCode, data: data)
            let retryable = http.statusCode == 429 || (500..<600).contains(http.statusCode)
            guard retryable, attempt < maxRetries,
                  let wait = Self.retryDelay(retryAfter: http.value(forHTTPHeaderField: "retry-after"), attempt: attempt,
                                             limit: min(10, timeout / 2))
            else { throw error }
            attempt += 1
            appLog.notice("claude: \(http.statusCode, privacy: .public) → \(wait, format: .fixed(precision: 1), privacy: .public)s 待ってやり直す（\(attempt, privacy: .public) 回目）")
            try await Task.sleep(for: .seconds(wait))
        }
    }

    /// retry-after（秒）があればそれ、なければ 1 秒・2 秒。limit を超えるならやり直さない（nil）
    static func retryDelay(retryAfter: String?, attempt: Int, limit: TimeInterval) -> TimeInterval? {
        let wait = retryAfter.flatMap { TimeInterval($0.trimmingCharacters(in: .whitespaces)) } ?? pow(2, Double(attempt))
        return wait <= limit ? max(0, wait) : nil
    }

    static func error(status: Int, data: Data) -> ClaudeError {
        if status == 401 { return .unauthorized }
        let decoded = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
        return .http(status: status, type: decoded?.error.type, message: decoded?.error.message ?? "")
    }

    // 設計判断: DEC-COM-045
    /// 応答を読む。stop_reason を先に見る（refusal は中身が空か途中まで、max_tokens は途中で切れている）。
    /// 本文は type が text のブロックだけをつなぐ（thinking や fallback のブロックは除く）
    static func parseMessage(_ data: Data) throws -> String {
        guard let message = try? JSONDecoder().decode(MessageResponse.self, from: data) else { throw ClaudeError.invalidResponse }
        switch message.stop_reason {
        case "refusal":
            throw ClaudeError.refusal(category: message.stop_details?.category)
        case "max_tokens":
            throw ClaudeError.truncated
        default:
            break
        }
        let text = (message.content ?? [])
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ClaudeError.emptyResponse }
        return text
    }

    private struct MessageResponse: Decodable {
        struct Block: Decodable {
            var type: String
            var text: String?
        }
        struct StopDetails: Decodable {
            var category: String?
        }
        var content: [Block]?
        var stop_reason: String?
        var stop_details: StopDetails?
    }

    private struct ErrorEnvelope: Decodable {
        struct Body: Decodable {
            var type: String?
            var message: String?
        }
        var error: Body
    }
}
