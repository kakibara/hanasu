import Foundation

// `hanasu mcp` のツール（計画は docs/plans/cli.md の M7・M10・M13）。
// 設計判断: DEC-COM-187
// ツールの名前・説明・引数の説明・注釈・決まり文句は、外のエージェントの AI が読む外への約束なので、英語で固定する
// （「AI へのプロンプトは 17 言語」の例外。ユーザーの合意 2026-11-08）。エラーの理由のうち、コマンドと共通の処理から来るものは表示の言語。

// 要件: REQ-MTG-127
// 設計判断: DEC-MTG-125, DEC-MTG-121
struct HanasuMCPTools {
    /// 会議のフォルダ（--meetings-dir・HANASU_MEETINGS_DIR・アプリの保存先）
    var directory: URL
    /// --ai・--model（ask_meetings で使う）
    var aiArguments: HanasuArguments

    /// 文字起こしと議事録を、1 回の結果でここまでにする（JSON にした長さ）
    static let maxCharacters = 20_000
    static let hitsPerMeeting = 5

    // 設計判断: DEC-COM-191（文は Windows 版と共有のファイル）
    static var notice: String { HanasuShared.text("mcp.notice") }

    static var instructions: String { HanasuShared.text("mcp.instructions") }

    private static func property(_ name: String) -> String { HanasuShared.text("mcp.properties.\(name)") }
    private static func title(_ name: Name) -> String { HanasuShared.text("mcp.tools.\(name.rawValue).title") }
    private static func description(_ name: Name, _ args: [String: String] = [:]) -> String {
        HanasuShared.text("mcp.tools.\(name.rawValue).description", args)
    }

    enum Name: String, CaseIterable {
        case listMeetings = "list_meetings"
        case getMeeting = "get_meeting"
        case searchMeetings = "search_meetings"
        case askMeetings = "ask_meetings"
        case listActionItems = "list_action_items"
    }

    /// ポリシーで止めた ask_meetings は一覧に出さない
    var available: [Name] {
        Name.allCases.filter { $0 != .askMeetings || !HanasuPolicy.mcpAskMeetingsDisabled }
    }

    func has(_ name: String) -> Bool { Name(rawValue: name) != nil }

    // MARK: - 一覧

    func definitions() -> [[String: Any]] {
        available.map(definition)
    }

    private static var periodProperties: [String: Any] {
        ["since": ["type": "string", "description": property("since")],
         "until": ["type": "string", "description": property("until")]]
    }

    private static func paging(defaultLimit: Int, maxLimit: Int) -> [String: Any] {
        [
            "limit": ["type": "integer", "minimum": 1, "maximum": maxLimit, "default": defaultLimit,
                      "description": property("limit")],
            "offset": ["type": "integer", "minimum": 0, "default": 0,
                       "description": property("offset")],
        ]
    }

    private static func schema(_ properties: [String: Any], required: [String] = []) -> [String: Any] {
        var schema: [String: Any] = ["type": "object", "properties": properties, "additionalProperties": false]
        if !required.isEmpty { schema["required"] = required }
        return schema
    }

    private static func annotations(title: String, openWorld: Bool) -> [String: Any] {
        ["title": title, "readOnlyHint": true, "destructiveHint": false, "idempotentHint": !openWorld, "openWorldHint": openWorld]
    }

    private static var meetingProperty: [String: Any] {
        ["type": "string", "description": property("meeting")]
    }

    private func definition(_ name: Name) -> [String: Any] {
        switch name {
        case .listMeetings:
            return [
                "name": name.rawValue, "title": Self.title(name),
                "description": Self.description(name),
                "inputSchema": Self.schema(Self.periodProperties.merging(Self.paging(defaultLimit: 20, maxLimit: 100)) { a, _ in a }),
                "annotations": Self.annotations(title: Self.title(name), openWorld: false),
            ]
        case .getMeeting:
            return [
                "name": name.rawValue, "title": Self.title(name),
                "description": Self.description(name, ["maxCharacters": "\(Self.maxCharacters)"]),
                "inputSchema": Self.schema([
                    "meeting": Self.meetingProperty,
                    "include": ["type": "array", "uniqueItems": true,
                                "items": ["type": "string", "enum": ["minutes", "actionItems", "notes", "transcript"]],
                                "default": ["minutes", "actionItems"],
                                "description": Self.property("include")],
                    "transcriptFrom": ["type": "number", "minimum": 0, "description": Self.property("transcriptFrom")],
                    "transcriptTo": ["type": "number", "minimum": 0, "description": Self.property("transcriptTo")],
                ], required: ["meeting"]),
                "annotations": Self.annotations(title: Self.title(name), openWorld: false),
            ]
        case .searchMeetings:
            return [
                "name": name.rawValue, "title": Self.title(name),
                "description": Self.description(name, ["hitsPerMeeting": "\(Self.hitsPerMeeting)"]),
                "inputSchema": Self.schema(["query": ["type": "string", "description": Self.property("query")]]
                    .merging(Self.periodProperties) { a, _ in a }
                    .merging(Self.paging(defaultLimit: 10, maxLimit: 50)) { a, _ in a }, required: ["query"]),
                "annotations": Self.annotations(title: Self.title(name), openWorld: false),
            ]
        case .askMeetings:
            let choice = try? HanasuAI.choice(aiArguments, for: HanasuAI.askPurpose(AppSettings.shared), settings: AppSettings.shared)
            let external = choice.map { $0.provider == .gemini || $0.provider == .claude } ?? true
            let destination = choice.map { HanasuShared.text("mcp.destinations.\($0.provider.rawValue)", ["model": $0.model]) }
                ?? HanasuShared.text("mcp.destinations.unknown")
            return [
                "name": name.rawValue, "title": Self.title(name),
                "description": Self.description(name, ["destination": destination]),
                "inputSchema": Self.schema(["question": ["type": "string", "description": Self.property("question")]]
                    .merging(Self.periodProperties) { a, _ in a }, required: ["question"]),
                "annotations": Self.annotations(title: Self.title(name), openWorld: external),
            ]
        case .listActionItems:
            return [
                "name": name.rawValue, "title": Self.title(name),
                "description": Self.description(name),
                "inputSchema": Self.schema(["owner": ["type": "string", "description": Self.property("owner")]]
                    .merging(Self.periodProperties) { a, _ in a }
                    .merging(Self.paging(defaultLimit: 50, maxLimit: 200)) { a, _ in a }),
                "annotations": Self.annotations(title: Self.title(name), openWorld: false),
            ]
        }
    }

    // MARK: - 呼び出し

    /// 引数の値の誤り（モデルが直してやり直せるよう、ツールの結果の isError で返す。SEP-1303）
    struct ArgumentError: Error {
        var message: String
    }

    func call(_ rawName: String, arguments: [String: Any]) async -> [String: Any] {
        guard let name = Name(rawValue: rawName) else { return Self.failure("Unknown tool: \(rawName)") }
        do {
            let schema = definition(name)["inputSchema"] as? [String: Any]
            let allowed = Set(((schema?["properties"] as? [String: Any]) ?? [:]).keys)
            if let unknown = arguments.keys.sorted().first(where: { !allowed.contains($0) }) {
                throw ArgumentError(message: "Unknown argument: \(unknown). Allowed: \(allowed.sorted().joined(separator: ", ")).")
            }
            let payload: [String: Any]
            switch name {
            case .listMeetings: payload = try listMeetings(arguments)
            case .getMeeting: payload = try getMeeting(arguments)
            case .searchMeetings: payload = try searchMeetings(arguments)
            case .askMeetings: payload = try await askMeetings(arguments)
            case .listActionItems: payload = try listActionItems(arguments)
            }
            return Self.success(payload)
        } catch let error as ArgumentError {
            return Self.failure("Invalid arguments: " + error.message)
        } catch let error as HanasuCommandError {
            return Self.failure(([error.message] + error.details).joined(separator: "\n"))
        } catch {
            return Self.failure(error.localizedDescription)
        }
    }

    static func success(_ payload: [String: Any]) -> [String: Any] {
        var object = payload
        object["schemaVersion"] = HanasuJSON.schemaVersion
        object["notice"] = notice
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return ["content": [["type": "text", "text": String(decoding: data, as: UTF8.self)]], "isError": false]
    }

    static func failure(_ message: String) -> [String: Any] {
        ["content": [["type": "text", "text": message]], "isError": true]
    }

    // MARK: - ツール

    private func listMeetings(_ arguments: [String: Any]) throws -> [String: Any] {
        let period = try Self.period(arguments)
        let loaded = try HanasuMeetingsCommand.load(directory: directory)
        let meetings = loaded.meetings.filter { period.contains($0.startedAt) }
        let page = try Self.page(meetings, arguments, defaultLimit: 20, maxLimit: 100)
        var object = page.json(key: "meetings", total: meetings.count, HanasuMeetingsCommand.summaryJSON)
        object["unreadableMeetingCount"] = loaded.unreadable.count
        return object
    }

    private func getMeeting(_ arguments: [String: Any]) throws -> [String: Any] {
        guard let reference = try Self.string(arguments, "meeting"), !reference.isEmpty else {
            throw ArgumentError(message: "meeting is required.")
        }
        var include: Set<String> = ["minutes", "actionItems"]
        if let raw = arguments["include"] {
            guard let list = raw as? [String] else { throw ArgumentError(message: "include must be an array of strings.") }
            let known: Set<String> = ["minutes", "actionItems", "notes", "transcript"]
            if let unknown = list.first(where: { !known.contains($0) }) {
                throw ArgumentError(message: "include has an unknown part: \(unknown). Use minutes, actionItems, notes or transcript.")
            }
            include = Set(list)
        }
        let from = try Self.number(arguments, "transcriptFrom") ?? 0
        let to = try Self.number(arguments, "transcriptTo") ?? .infinity
        guard from < to else { throw ArgumentError(message: "transcriptFrom must be less than transcriptTo.") }

        let meeting = try HanasuMeetingsCommand.resolve(reference, in: try HanasuMeetingsCommand.load(directory: directory))
        var object = HanasuMeetingsCommand.meetingJSON(meeting, minutes: include.contains("minutes"), transcript: nil,
                                                        notes: include.contains("notes"), actions: include.contains("actionItems"))
        if let minutes = meeting.minutes, include.contains("minutes"), minutes.count > Self.maxCharacters {
            object["minutes"] = String(minutes.prefix(Self.maxCharacters))
            object["minutesTruncated"] = true
        }
        if include.contains("transcript") {
            // 設計判断: DEC-MTG-125
            let blocks = HanasuMeetingsCommand.transcriptBlocks(meeting).filter { $0.start >= from && $0.start < to }
            var entries: [[String: Any]] = []
            var used = 0
            var next: Double?
            for block in blocks {
                let entry = HanasuMeetingsCommand.transcriptEntryJSON(meeting, block)
                // JSON にした長さを、バイトではなく文字で数える（日本語は UTF-8 で 1 文字 3 バイト）
                let characters = String(decoding: (try? JSONSerialization.data(withJSONObject: entry)) ?? Data(), as: UTF8.self).count
                if !entries.isEmpty, used + characters > Self.maxCharacters {
                    next = block.start
                    break
                }
                used += characters
                entries.append(entry)
            }
            object["transcript"] = entries
            object["omittedUtteranceCount"] = meeting.utterances.count - meeting.usedUtterances.count
            object["transcriptRange"] = ["from": HanasuJSON.seconds(from), "to": to.isFinite ? HanasuJSON.seconds(to) as Any : NSNull()]
            object["transcriptTruncated"] = next != nil
            object["transcriptNextFrom"] = HanasuJSON.optional(next.map(HanasuJSON.seconds))
        }
        return ["meeting": object]
    }

    private func searchMeetings(_ arguments: [String: Any]) throws -> [String: Any] {
        guard let query = try Self.string(arguments, "query"), !MeetingSearchIndex.terms(of: query).isEmpty else {
            throw ArgumentError(message: "query is required.")
        }
        let period = try Self.period(arguments)
        let loaded = try HanasuMeetingsCommand.load(directory: directory)
        let meetings = loaded.meetings.filter { period.contains($0.startedAt) }
        let byID = Dictionary(meetings.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // 設計判断: DEC-MTG-121
        let results = MeetingSearchIndex.scan(meetings.map(\.withUsedUtterancesOnly), query: query, hitsPerMeeting: Self.hitsPerMeeting)
        let page = try Self.page(results, arguments, defaultLimit: 10, maxLimit: 50)
        var object = page.json(key: "results", total: results.count) { HanasuMeetingsCommand.searchResultJSON($0, byID: byID) ?? [:] }
        object["query"] = query
        object["unreadableMeetingCount"] = loaded.unreadable.count
        return object
    }

    private func askMeetings(_ arguments: [String: Any]) async throws -> [String: Any] {
        // 要件: REQ-MTG-127
        if HanasuPolicy.mcpAskMeetingsDisabled {
            throw HanasuCommandError(
                exit: .denied,
                message: tr("管理者のポリシーで、MCP の ask_meetings は使えないようにされています（%@）。",
                            HanasuPolicy.Key.disableMCPAskMeetings.rawValue))
        }
        guard let question = try Self.string(arguments, "question")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !question.isEmpty else {
            throw ArgumentError(message: "question is required.")
        }
        let period = try Self.period(arguments)
        let settings = AppSettings.shared
        let purpose = HanasuAI.askPurpose(settings)
        let choice = try HanasuAI.choice(aiArguments, for: purpose, settings: settings)
        let client = try HanasuAI.makeClient(choice, for: purpose, settings: settings, timeout: 180)
        let loaded = try HanasuMeetingsCommand.load(directory: directory)
        let outcome = try await HanasuAICommands.ask(
            question: question, period: period, choice: choice, client: client,
            meetings: loaded.meetings, printPrompt: false)
        var json = outcome.json
        json["unreadableMeetingCount"] = loaded.unreadable.count
        return json
    }

    private func listActionItems(_ arguments: [String: Any]) throws -> [String: Any] {
        let period = try Self.period(arguments)
        let loaded = try HanasuMeetingsCommand.load(directory: directory)
        let items = HanasuMeetingsCommand.actionItems(in: loaded.meetings, period: period,
                                                      owner: try Self.string(arguments, "owner"))
        let page = try Self.page(items, arguments, defaultLimit: 50, maxLimit: 200)
        var object = page.json(key: "actionItems", total: items.count, HanasuMeetingsCommand.actionItemJSON)
        object["unreadableMeetingCount"] = loaded.unreadable.count
        return object
    }

    // MARK: - 引数

    private static func string(_ arguments: [String: Any], _ key: String) throws -> String? {
        guard let value = arguments[key], !(value is NSNull) else { return nil }
        guard let string = value as? String else { throw ArgumentError(message: "\(key) must be a string.") }
        return string
    }

    private static func number(_ arguments: [String: Any], _ key: String) throws -> Double? {
        guard let value = arguments[key], !(value is NSNull) else { return nil }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue >= 0 else {
            throw ArgumentError(message: "\(key) must be a number of seconds (0 or more).")
        }
        return number.doubleValue
    }

    private static func integer(_ arguments: [String: Any], _ key: String, default value: Int, range: ClosedRange<Int>) throws -> Int {
        guard let raw = arguments[key], !(raw is NSNull) else { return value }
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue == number.doubleValue.rounded(), range.contains(number.intValue) else {
            throw ArgumentError(message: "\(key) must be an integer from \(range.lowerBound) to \(range.upperBound).")
        }
        return number.intValue
    }

    private static func period(_ arguments: [String: Any]) throws -> HanasuPeriod {
        let since = try string(arguments, "since")
        let until = try string(arguments, "until")
        do {
            let period = try HanasuPeriod(since: since, until: until)
            if let start = period.since, let end = period.until, start >= end {
                throw ArgumentError(message: "since must be before until.")
            }
            return period
        } catch let error as ArgumentError {
            throw error
        } catch {
            throw ArgumentError(message: "since/until must be 7d, 24h, 2w (back from now), a date such as 2026-11-01, or an ISO 8601 date-time.")
        }
    }

    struct Page<Item> {
        var items: [Item]
        var offset: Int
        var nextOffset: Int?

        func json(key: String, total: Int, _ transform: (Item) -> [String: Any]) -> [String: Any] {
            [key: items.map(transform), "total": total, "offset": offset, "nextOffset": HanasuJSON.optional(nextOffset)]
        }
    }

    private static func page<Item>(_ all: [Item], _ arguments: [String: Any], defaultLimit: Int, maxLimit: Int) throws -> Page<Item> {
        let limit = try integer(arguments, "limit", default: defaultLimit, range: 1...maxLimit)
        let offset = try integer(arguments, "offset", default: 0, range: 0...Int(Int32.max))
        let slice = Array(all.dropFirst(offset).prefix(limit))
        let next = offset + slice.count < all.count ? offset + slice.count : nil
        return Page(items: slice, offset: offset, nextOffset: next)
    }
}
