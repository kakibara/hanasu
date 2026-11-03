import Foundation

/// 検索でヒットした 1 か所（会議のタイトル・議事録の 1 行・文字起こしの 1 発言）
struct MeetingSearchHit: Identifiable, Hashable {
    enum Location: Hashable {
        case title
        /// 議事録の行番号（minutes を "\n" で分けたときの 0 始まりの番号）
        case minutes(line: Int)
        /// 文字起こしの発言（`Meeting.mergedBlocks()` の 1 つ。ID は先頭の発言の ID）
        case transcript(blockID: UUID, start: Double, speaker: String)
    }

    var meetingID: String
    var location: Location
    /// ヒットした語の前後を切り出した表示用の文
    var snippet: String

    var id: String {
        switch location {
        case .title: "\(meetingID)#title"
        case .minutes(let line): "\(meetingID)#m\(line)"
        case .transcript(let blockID, _, _): "\(meetingID)#t\(blockID.uuidString)"
        }
    }
}

/// 1 つの会議でヒットしたもの
struct MeetingSearchResult: Identifiable, Hashable {
    var meetingID: String
    var title: String
    var startedAt: Date
    var hits: [MeetingSearchHit]
    /// 表示を省いた分も含めたヒット数
    var totalHits: Int

    var id: String { meetingID }
}

// 要件: REQ-MTG-015
// 設計判断: DEC-MTG-050
/// 会議の横断検索の索引。
///
/// 日本語は単語の区切りがないので、文字の 2-gram（隣り合う 2 文字）ごとに「その 2 文字を含む箇所」を引けるようにしておき、
/// 検索語の 2-gram のうち候補がいちばん少ないものから候補を絞って、最後に本当に含むかを確かめる。
/// 会議の一覧（`MeetingRecorder.meetings`）はもともと全件をメモリに読み込んでいるので、索引もメモリに持つ。
/// 会議が変わったら、その会議の分だけ作り直す（変わったかどうかは会議全体のハッシュで判断する）。
actor MeetingSearchIndex {
    private struct Unit {
        var meetingID: String
        var location: MeetingSearchHit.Location
        var original: String
        var folded: String
        var alive = true
    }

    private struct MeetingEntry {
        var fingerprint: Int
        var unitIDs: [Int]
        var title: String
        var startedAt: Date
    }

    private var units: [Unit] = []
    private var postings: [UInt64: [Int32]] = [:]
    private var entries: [String: MeetingEntry] = [:]
    private var deadCount = 0

    /// 会議の一覧に合わせて索引を更新する。変わっていない会議は作り直さない。
    func update(_ meetings: [Meeting]) {
        var seen = Set<String>()
        for meeting in meetings {
            seen.insert(meeting.id)
            if let entry = entries[meeting.id], entry.fingerprint == meeting.hashValue { continue }
            removeMeeting(meeting.id)
            addMeetingUnits(meeting)
        }
        for id in entries.keys where !seen.contains(id) { removeMeeting(id) }
        // 消した箇所が半分を超えたら詰め直す
        if deadCount > 1000, deadCount * 2 > units.count { compact() }
    }

    var meetingCount: Int { entries.count }

    // 設計判断: DEC-MTG-051
    /// 検索語（空白区切りは AND）を含む箇所を、会議ごとにまとめて返す。会議は新しい順。
    /// - Parameter hitsPerMeeting: 1 つの会議から返す箇所の上限（totalHits には全件の数が入る）
    func search(_ query: String, hitsPerMeeting: Int = 20, maxMeetings: Int = 200) -> [MeetingSearchResult] {
        let terms = Self.terms(of: query)
        guard !terms.isEmpty else { return [] }

        var byMeeting: [String: [Int]] = [:]
        for unitID in candidates(for: terms) {
            let unit = units[unitID]
            guard unit.alive, terms.allSatisfy({ unit.folded.contains($0) }) else { continue }
            byMeeting[unit.meetingID, default: []].append(unitID)
        }

        let results = byMeeting.compactMap { meetingID, unitIDs -> MeetingSearchResult? in
            guard let entry = entries[meetingID] else { return nil }
            // タイトル → 議事録 → 文字起こし（時刻順）の順に並べる
            let sorted = unitIDs.sorted { Self.order(units[$0].location) < Self.order(units[$1].location) }
            let hits = sorted.prefix(hitsPerMeeting).map { id in
                MeetingSearchHit(meetingID: meetingID, location: units[id].location,
                                 snippet: Self.snippet(units[id].original, terms: terms))
            }
            return MeetingSearchResult(meetingID: meetingID, title: entry.title, startedAt: entry.startedAt,
                                       hits: Array(hits), totalHits: unitIDs.count)
        }
        return Array(results.sorted { $0.startedAt > $1.startedAt }.prefix(maxMeetings))
    }

    // MARK: - 正規化

    // 設計判断: DEC-MTG-051
    /// 大文字・小文字、全角・半角（英数字とカタカナ）の違いを無視するための変換
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
            .precomposedStringWithCanonicalMapping
    }

    /// 検索語を空白（全角を含む）で分け、正規化する
    static func terms(of query: String) -> [String] {
        var result: [String] = []
        for part in fold(query).split(whereSeparator: { $0.isWhitespace }) {
            let term = String(part)
            if !term.isEmpty, !result.contains(term) { result.append(term) }
        }
        return result
    }

    // MARK: - Private

    private func addMeetingUnits(_ meeting: Meeting) {
        var ids: [Int] = []
        func add(_ location: MeetingSearchHit.Location, _ text: String) {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            let id = units.count
            let folded = Self.fold(trimmed)
            units.append(Unit(meetingID: meeting.id, location: location, original: trimmed, folded: folded))
            for key in Self.bigramKeys(folded) { postings[key, default: []].append(Int32(id)) }
            ids.append(id)
        }
        add(.title, meeting.title)
        if let minutes = meeting.minutes {
            for (line, text) in minutes.components(separatedBy: "\n").enumerated() {
                add(.minutes(line: line), Self.stripMarkdown(text))
            }
        }
        for block in meeting.mergedBlocks() {
            add(.transcript(blockID: block.id, start: block.start, speaker: meeting.displayName(for: block.speaker)), block.text)
        }
        entries[meeting.id] = MeetingEntry(fingerprint: meeting.hashValue, unitIDs: ids,
                                           title: meeting.title, startedAt: meeting.startedAt)
    }

    private func removeMeeting(_ id: String) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        for unitID in entry.unitIDs where units[unitID].alive {
            units[unitID].alive = false
            units[unitID].original = ""
            units[unitID].folded = ""
            deadCount += 1
        }
    }

    /// 消した箇所を除いて作り直す
    private func compact() {
        let live = units.filter(\.alive)
        units = []
        postings = [:]
        deadCount = 0
        var newIDs: [String: [Int]] = [:]
        for unit in live {
            let id = units.count
            units.append(unit)
            for key in Self.bigramKeys(unit.folded) { postings[key, default: []].append(Int32(id)) }
            newIDs[unit.meetingID, default: []].append(id)
        }
        for (meetingID, ids) in newIDs { entries[meetingID]?.unitIDs = ids }
    }

    /// 候補の箇所。各検索語の 2-gram のうち、含む箇所がいちばん少ないものを使う。
    /// 1 文字だけの検索語しかないときは全件を候補にする。
    private func candidates(for terms: [String]) -> [Int] {
        var best: [Int32]?
        for term in terms {
            for key in Self.bigramKeys(term) {
                let list = postings[key] ?? []
                if best == nil || list.count < best!.count { best = list }
                if list.isEmpty { return [] }
            }
        }
        if let best { return best.map(Int.init) }
        return Array(units.indices)
    }

    private static func bigramKeys(_ folded: String) -> Set<UInt64> {
        let scalars = folded.unicodeScalars.map(\.value)
        guard scalars.count >= 2 else { return [] }
        var keys = Set<UInt64>()
        keys.reserveCapacity(scalars.count)
        for i in 0..<(scalars.count - 1) {
            keys.insert(UInt64(scalars[i]) << 32 | UInt64(scalars[i + 1]))
        }
        return keys
    }

    private static func order(_ location: MeetingSearchHit.Location) -> Double {
        switch location {
        case .title: -2
        case .minutes(let line): -1 + Double(line) / 1_000_000
        case .transcript(_, let start, _): start
        }
    }

    /// 議事録の行の先頭の Markdown 記号（見出し・箇条書き・チェックボックス）を除く
    static func stripMarkdown(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespaces)
        for prefix in ["- [ ] ", "- [x] ", "### ", "## ", "# ", "- ", "* "] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
            break
        }
        return text.replacingOccurrences(of: "**", with: "")
    }

    /// 最初にヒットした語の前後を切り出す
    static func snippet(_ text: String, terms: [String], radius: Int = 32) -> String {
        let options: String.CompareOptions = [.caseInsensitive, .widthInsensitive]
        guard let range = terms.lazy.compactMap({ text.range(of: $0, options: options) }).first else {
            return String(text.prefix(radius * 2))
        }
        let start = text.index(range.lowerBound, offsetBy: -radius, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: radius, limitedBy: text.endIndex) ?? text.endIndex
        return (start > text.startIndex ? "…" : "") + text[start..<end] + (end < text.endIndex ? "…" : "")
    }
}
