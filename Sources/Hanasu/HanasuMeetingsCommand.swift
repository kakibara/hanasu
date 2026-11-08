import Foundation

// `hanasu meetings …` と `hanasu actions`。会議の記録を読むだけで、書き換えず、外に送らない（AI を使わない）。
// 共通の部分（終了コード・出力・引数）は HanasuCommand.swift。

enum HanasuMeetingsCommand {
    static let commonFlags: Set<String> = ["--json", "--help", "-h"]
    static let commonOptions: Set<String> = ["--meetings-dir"]

    static func runMeetings(_ arguments: [String]) async throws -> HanasuExit {
        guard let sub = arguments.first else {
            // 使い方の誤りなので、使い方は stderr に出す
            HanasuOutput.err(HanasuHelp.section(for: "meetings") ?? "")
            return .usage
        }
        if ["--help", "-h"].contains(sub) {
            HanasuOutput.out(HanasuHelp.section(for: "meetings") ?? "")
            return .ok
        }
        let rest = Array(arguments.dropFirst())
        switch sub {
        case "list": return try list(rest)
        case "show": return try show(rest)
        case "search": return try await search(rest)
        default:
            throw HanasuCommandError(exit: .usage, message: tr("知らないコマンドです: %@", "meetings \(sub)"),
                                     details: [tr("使い方は hanasu help で表示できます。")])
        }
    }

    // MARK: - list

    // 要件: REQ-MTG-120
    static func list(_ arguments: [String]) throws -> HanasuExit {
        let args = try HanasuArguments.parse(arguments, flags: commonFlags, options: commonOptions.union(["--since", "--until", "--limit"]))
        if wantsHelp(args, "meetings") { return .ok }
        try noPositionals(args)
        let period = try HanasuPeriod(args)
        var meetings = try load(args).filter { period.contains($0.startedAt) }
        if let limit = try args.int("--limit") { meetings = Array(meetings.prefix(limit)) }
        if args.flags.contains("--json") {
            try HanasuOutput.json(["meetings": meetings.map(summaryJSON)])
        } else {
            if meetings.isEmpty { HanasuOutput.err(tr("会議はありません。")) }
            for meeting in meetings { HanasuOutput.out(summaryLine(meeting)) }
        }
        return .ok
    }

    // MARK: - show

    // 要件: REQ-MTG-121
    static func show(_ arguments: [String]) throws -> HanasuExit {
        let parts = ["--transcript", "--notes", "--actions", "--all"]
        let args = try HanasuArguments.parse(arguments, flags: commonFlags.union(parts), options: commonOptions)
        if wantsHelp(args, "meetings") { return .ok }
        guard args.positionals.count == 1 else {
            throw HanasuCommandError(exit: .usage, message: tr("会議を 1 つ指定してください（例: hanasu meetings show latest）。"))
        }
        let meeting = try resolve(args.positionals[0], in: try load(args))
        let all = args.flags.contains("--all")
        let chosen = Set(parts).intersection(args.flags)
        // 何も選ばなければ議事録。--all ならすべて
        let wantsMinutes = all || chosen.isEmpty
        let wantsTranscript = all || args.flags.contains("--transcript")
        let wantsNotes = all || args.flags.contains("--notes")
        let wantsActions = all || args.flags.contains("--actions")

        if args.flags.contains("--json") {
            var object = summaryJSON(meeting)
            object["speakers"] = meeting.speakers.map { speakerJSON(meeting, $0) }
            if wantsMinutes {
                object["minutes"] = HanasuJSON.optional(meeting.minutes)
                object["minutesOutdated"] = meeting.minutesOutdated == true
            }
            if wantsTranscript {
                object["transcript"] = transcriptBlocks(meeting).map { block -> [String: Any] in
                    ["start": HanasuJSON.seconds(block.start), "end": HanasuJSON.seconds(block.end),
                     "speaker": block.speaker, "speakerName": meeting.displayName(for: block.speaker), "text": block.text]
                }
                object["omittedUtteranceCount"] = meeting.utterances.count - meeting.usedUtterances.count
            }
            if wantsNotes {
                object["notes"] = meeting.allNotes.map { note -> [String: Any] in
                    ["kind": note.kind.rawValue, "time": HanasuJSON.optional(note.time.map(HanasuJSON.seconds)), "text": note.text]
                }
            }
            if wantsActions {
                object["actionItems"] = (meeting.actionItems ?? []).map(actionJSON)
            }
            try HanasuOutput.json(["meeting": object])
            return .ok
        }

        var sections: [String] = []
        if meeting.status != .done {
            HanasuOutput.err(tr("この会議は「%@」です。保存されている分だけを出します。", statusLabel(meeting.status)))
        }
        if wantsMinutes {
            if let minutes = meeting.minutes, !minutes.isEmpty {
                if meeting.minutesOutdated == true {
                    HanasuOutput.err(tr("議事録は、使う発言を変えたあとに作り直されていません。"))
                }
                sections.append(minutes)
            } else {
                HanasuOutput.err(tr("この会議には議事録がありません。"))
            }
        }
        if wantsTranscript { sections.append(transcriptText(meeting)) }
        if wantsNotes {
            if meeting.allNotes.isEmpty {
                HanasuOutput.err(tr("この会議にはメモがありません。"))
            } else {
                sections.append(meeting.notesMarkdown())
            }
        }
        if wantsActions {
            let items = meeting.actionItems ?? []
            if items.isEmpty {
                HanasuOutput.err(tr("この会議にはアクションアイテムがありません。"))
            } else {
                sections.append(([tr("# %@ — アクションアイテム", meeting.title), ""]
                                 + items.map { $0.markdownLine(language: UILanguage.current) }).joined(separator: "\n"))
            }
        }
        if !sections.isEmpty { HanasuOutput.out(sections.joined(separator: "\n\n")) }
        return .ok
    }

    // MARK: - search

    // 要件: REQ-MTG-123
    // 設計判断: DEC-MTG-121
    static func search(_ arguments: [String]) async throws -> HanasuExit {
        let args = try HanasuArguments.parse(arguments, flags: commonFlags, options: commonOptions.union(["--since", "--until", "--limit"]))
        if wantsHelp(args, "meetings") { return .ok }
        let query = args.positionals.joined(separator: " ")
        guard !MeetingSearchIndex.terms(of: query).isEmpty else {
            throw HanasuCommandError(exit: .usage, message: tr("検索する語を指定してください（例: hanasu meetings search 予算）。"))
        }
        let period = try HanasuPeriod(args)
        let meetings = try load(args).filter { period.contains($0.startedAt) }
        let byID = Dictionary(meetings.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // 議事録に使わない発言（除外・オフレコ・範囲外）は、外に出さないので索引に入れない
        var results = MeetingSearchIndex.scan(meetings.map(\.withUsedUtterancesOnly), query: query)
        if let limit = try args.int("--limit") { results = Array(results.prefix(limit)) }

        if args.flags.contains("--json") {
            try HanasuOutput.json(["query": query, "results": results.compactMap { result -> [String: Any]? in
                guard let meeting = byID[result.meetingID] else { return nil }
                return ["meeting": summaryJSON(meeting), "totalHits": result.totalHits, "hits": result.hits.map(hitJSON)]
            }])
            return .ok
        }
        if results.isEmpty { HanasuOutput.err(tr("見つかりませんでした。")) }
        var lines: [String] = []
        for result in results {
            guard let meeting = byID[result.meetingID] else { continue }
            lines.append(summaryLine(meeting) + "  " + tr("ヒット %@ 件", "\(result.totalHits)"))
            for hit in result.hits { lines.append("    " + hitLine(hit)) }
        }
        if !lines.isEmpty { HanasuOutput.out(lines.joined(separator: "\n")) }
        return .ok
    }

    // MARK: - actions

    // 要件: REQ-MTG-124
    static func runActions(_ arguments: [String]) async throws -> HanasuExit {
        let args = try HanasuArguments.parse(arguments, flags: commonFlags, options: commonOptions.union(["--since", "--until", "--owner", "--limit"]))
        if wantsHelp(args, "actions") { return .ok }
        try noPositionals(args)
        let period = try HanasuPeriod(args)
        let owner = args.values["--owner"].map(MeetingSearchIndex.fold)
        var items: [(Meeting, ActionItem)] = []
        for meeting in try load(args) where period.contains(meeting.startedAt) {
            for item in meeting.actionItems ?? [] {
                if let owner, !MeetingSearchIndex.fold(item.owner ?? "").contains(owner) { continue }
                items.append((meeting, item))
            }
        }
        if let limit = try args.int("--limit") { items = Array(items.prefix(limit)) }
        if args.flags.contains("--json") {
            try HanasuOutput.json(["actionItems": items.map { meeting, item in
                var object = actionJSON(item)
                object["meeting"] = summaryJSON(meeting, brief: true)
                return object
            }])
            return .ok
        }
        if items.isEmpty { HanasuOutput.err(tr("アクションアイテムはありません。")) }
        var lines: [String] = []
        var current: String?
        for (meeting, item) in items {
            if current != meeting.id {
                if current != nil { lines.append("") }
                lines.append("\(meeting.slug)  \(Meeting.dateFormatter.string(from: meeting.startedAt))  \(meeting.title)")
                current = meeting.id
            }
            lines.append("  " + item.markdownLine(language: UILanguage.current))
        }
        if !lines.isEmpty { HanasuOutput.out(lines.joined(separator: "\n")) }
        return .ok
    }

    // MARK: - 会議を読む

    // 要件: REQ-MTG-125
    /// 会議のフォルダ。--meetings-dir → 環境変数 HANASU_MEETINGS_DIR → アプリの保存先
    static func meetingsDirectory(_ args: HanasuArguments) -> URL {
        if let value = args.values["--meetings-dir"], !value.isEmpty {
            return URL(fileURLWithPath: (value as NSString).expandingTildeInPath, isDirectory: true)
        }
        if let value = ProcessInfo.processInfo.environment["HANASU_MEETINGS_DIR"], !value.isEmpty {
            return URL(fileURLWithPath: (value as NSString).expandingTildeInPath, isDirectory: true)
        }
        return MeetingStore.baseDirectory
    }

    // 要件: REQ-COM-185
    /// 会議をすべて読む（新しい順）。フォルダを読む権限がなければ、終了コード 5 と、何を許可すればよいかを出す
    static func load(_ args: HanasuArguments) throws -> [Meeting] {
        let directory = meetingsDirectory(args)
        do {
            return try MeetingStore.loadAll(in: directory)
        } catch {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].standardizedFileURL.path
            var details: [String] = []
            if directory.standardizedFileURL.path.hasPrefix(documents) {
                details.append(tr("「システム設定」→「プライバシーとセキュリティ」→「ファイルとフォルダ」で、このコマンドを実行しているアプリ（ターミナルや AI エージェントのアプリ）に「書類」フォルダへのアクセスを許可してください。"))
            } else {
                details.append(tr("そのフォルダがあり、このユーザーで読めるかを確かめてください。"))
            }
            details.append(error.localizedDescription)
            throw HanasuCommandError(exit: .denied, message: tr("会議のフォルダを読めません: %@", directory.path), details: details)
        }
    }

    // 要件: REQ-MTG-122
    // 設計判断: DEC-MTG-120
    /// 会議の指定（ID・空白を _ にした ID・latest・日付）を 1 つの会議に決める
    static func resolve(_ reference: String, in meetings: [Meeting]) throws -> Meeting {
        if reference == "latest" {
            guard let index = meetings.firstIndex(where: { $0.status == .done }) else {
                throw HanasuCommandError(exit: .notFound, message: tr("完了した会議がありません。"))
            }
            let newer = meetings[..<index]
            if !newer.isEmpty {
                HanasuOutput.err(tr("これより新しい会議が %@ 件あります（記録中・処理中・失敗）: %@", "\(newer.count)",
                                    newer.map(\.slug).joined(separator: ", ")))
            }
            return meetings[index]
        }
        let slug = Meeting.slug(of: reference)
        if let meeting = meetings.first(where: { $0.slug == slug }) { return meeting }
        if HanasuPeriod.isDate(reference) {
            let matches = meetings.filter { HanasuPeriod.dayString($0.startedAt) == reference }
            if matches.count == 1 { return matches[0] }
            if matches.count > 1 {
                throw HanasuCommandError(
                    exit: .notFound, message: tr("%@ の会議が %@ 件あります。ID で指定してください。", reference, "\(matches.count)"),
                    details: matches.map(summaryLine))
            }
        }
        throw HanasuCommandError(exit: .notFound, message: tr("会議が見つかりません: %@", reference),
                                 details: [tr("会議の一覧は hanasu meetings list で表示できます。")])
    }

    // MARK: - 出力の形

    // 設計判断: DEC-MTG-120
    static func summaryJSON(_ meeting: Meeting) -> [String: Any] { summaryJSON(meeting, brief: false) }

    static func summaryJSON(_ meeting: Meeting, brief: Bool) -> [String: Any] {
        var object: [String: Any] = [
            "id": meeting.id, "slug": meeting.slug, "title": meeting.title,
            "startedAt": HanasuJSON.date(meeting.startedAt),
        ]
        if brief { return object }
        object["durationSeconds"] = Int(meeting.duration.rounded())
        object["status"] = meeting.status.rawValue
        object["hasMinutes"] = !(meeting.minutes ?? "").isEmpty
        // nil は、アクションアイテムを取り出す機能より前に作った議事録
        object["actionItemCount"] = HanasuJSON.optional(meeting.actionItems?.count)
        return object
    }

    static func speakerJSON(_ meeting: Meeting, _ key: String) -> [String: Any] {
        ["key": key, "name": meeting.displayName(for: key), "inferred": meeting.inferredSpeakers?.contains(key) == true]
    }

    static func actionJSON(_ item: ActionItem) -> [String: Any] {
        ["id": item.id.uuidString, "task": item.task, "owner": HanasuJSON.optional(item.owner),
         "due": HanasuJSON.optional(item.due), "dueNote": HanasuJSON.optional(item.dueNote)]
    }

    static func hitJSON(_ hit: MeetingSearchHit) -> [String: Any] {
        switch hit.location {
        case .title: return ["kind": "title", "text": hit.snippet]
        case .minutes(let line): return ["kind": "minutes", "line": line + 1, "text": hit.snippet]
        case .transcript(_, let start, let speaker):
            return ["kind": "transcript", "start": HanasuJSON.seconds(start), "speakerName": speaker, "text": hit.snippet]
        }
    }

    static func hitLine(_ hit: MeetingSearchHit) -> String {
        switch hit.location {
        case .title: return tr("タイトル: %@", hit.snippet)
        case .minutes(let line): return tr("議事録 %@ 行目: %@", "\(line + 1)", hit.snippet)
        case .transcript(_, let start, let speaker): return "[\(Meeting.clock(start))] \(speaker): \(hit.snippet)"
        }
    }

    /// 一覧の 1 行（ID・日時・長さ・タイトル・状態・議事録・アクションアイテムの数）
    static func summaryLine(_ meeting: Meeting) -> String {
        var parts = [meeting.slug, Meeting.dateFormatter.string(from: meeting.startedAt), Meeting.clock(meeting.duration), meeting.title]
        if meeting.status != .done { parts.append("[\(statusLabel(meeting.status))]") }
        if (meeting.minutes ?? "").isEmpty { parts.append(tr("議事録なし")) }
        if let count = meeting.actionItems?.count, count > 0 { parts.append(tr("アクション %@ 件", "\(count)")) }
        return parts.joined(separator: "  ")
    }

    static func statusLabel(_ status: Meeting.Status) -> String {
        switch status {
        case .recording: tr("記録中")
        case .processing: tr("処理中")
        case .done: tr("完了")
        case .failed: tr("失敗")
        }
    }

    // 要件: REQ-MTG-121
    // 設計判断: DEC-MTG-091
    /// 出す文字起こし（議事録に使う発言だけ。transcript.md と同じ）
    static func transcriptBlocks(_ meeting: Meeting) -> [Utterance] {
        meeting.blocksForMinutes()
    }

    /// 文字起こしの Markdown。AI が推測した話者名には印を付ける
    static func transcriptText(_ meeting: Meeting) -> String {
        var lines = [tr("# %@ — 文字起こし", meeting.title), "",
                     tr("- 日時: %@", Meeting.dateFormatter.string(from: meeting.startedAt)),
                     tr("- 長さ: %@", Meeting.clock(meeting.duration))]
        let omitted = meeting.utterances.count - meeting.usedUtterances.count
        if omitted > 0 { lines.append(tr("- 議事録に使わない発言（%@ 件）は含めていません", "\(omitted)")) }
        lines.append("")
        for block in transcriptBlocks(meeting) {
            lines.append("**[\(Meeting.clock(block.start))] \(speakerLabel(meeting, block.speaker))**: \(block.text)")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    // 要件: REQ-MTG-121
    static func speakerLabel(_ meeting: Meeting, _ key: String) -> String {
        let name = meeting.displayName(for: key)
        return meeting.inferredSpeakers?.contains(key) == true ? tr("%@（推測）", name) : name
    }

    // MARK: - 小さな決まり

    private static func wantsHelp(_ args: HanasuArguments, _ section: String) -> Bool {
        guard args.flags.contains("--help") || args.flags.contains("-h") else { return false }
        HanasuOutput.out(HanasuHelp.section(for: section) ?? HanasuHelp.full())
        return true
    }

    private static func noPositionals(_ args: HanasuArguments) throws {
        if let extra = args.positionals.first {
            throw HanasuCommandError(exit: .usage, message: tr("余分な引数です: %@", extra),
                                     details: [tr("使い方は hanasu help で表示できます。")])
        }
    }
}

extension Meeting {
    // 設計判断: DEC-MTG-120
    /// コマンドで指定しやすい ID（フォルダ名の空白を _ にしたもの。例: 2026-11-02_1312）
    var slug: String { Self.slug(of: id) }

    static func slug(of reference: String) -> String {
        reference.replacingOccurrences(of: " ", with: "_")
    }

    /// 議事録に使う発言だけを残した写し（hanasu コマンドで、除いた発言を外に出さないため）
    var withUsedUtterancesOnly: Meeting {
        var copy = self
        copy.utterances = usedUtterances
        return copy
    }
}

// 要件: REQ-MTG-120
// 設計判断: DEC-MTG-122
/// --since / --until。7d・24h・2w（今からさかのぼる）か、日付（2026-11-01）か、日時（ISO 8601）
struct HanasuPeriod {
    var since: Date?
    /// この時刻より前（含まない）
    var until: Date?

    init(_ args: HanasuArguments, now: Date = Date()) throws {
        since = try args.values["--since"].map { try Self.parse($0, option: "--since", endOfDay: false, now: now) }
        until = try args.values["--until"].map { try Self.parse($0, option: "--until", endOfDay: true, now: now) }
    }

    func contains(_ date: Date) -> Bool {
        if let since, date < since { return false }
        if let until, date >= until { return false }
        return true
    }

    /// endOfDay なら、日付はその日の終わり（翌日の 0 時）を指す（--until 2026-11-05 は 5 日を含む）
    static func parse(_ raw: String, option: String, endOfDay: Bool, now: Date) throws -> Date {
        let value = raw.trimmingCharacters(in: .whitespaces)
        if let unit = value.last, let n = Int(value.dropLast()), n >= 0 {
            let seconds: Double? = switch unit {
            case "h": 3600
            case "d": 86400
            case "w": 7 * 86400
            default: nil
            }
            if let seconds { return now.addingTimeInterval(-Double(n) * seconds) }
        }
        if isDate(value), let day = dayFormatter.date(from: value) {
            return endOfDay ? Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day : day
        }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: value) { return date }
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm"] {
            local.dateFormat = format
            if let date = local.date(from: value) { return date }
        }
        throw HanasuCommandError(exit: .usage, message: tr("%@ の値を読めません: %@", option, raw),
                                 details: [tr("期間の指定: 7d・24h・2w（今からさかのぼる）、日付（例: 2026-11-01）")])
    }

    static func isDate(_ value: String) -> Bool {
        value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }

    /// その日時の、この Mac の時間帯での日付（yyyy-MM-dd）
    static func dayString(_ date: Date) -> String { dayFormatter.string(from: date) }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
