import Foundation

// 要件: REQ-MTG-050
// 設計判断: DEC-MTG-133
/// 会議ノートの文書に出すための、議事録の Markdown の分け方。
/// 先頭のタイトル（`# …`）は出さず、最初の `## ` の節を「要約」として先頭に、残りの節を本文にする。
/// アクションアイテムをカードで出すときは、その見出しの節を本文から外す（`minutes` の文字列は変えない）
struct MinutesDocument {
    /// 議事録の 1 行（行番号は議事録の Markdown の中の番号。検索の飛び先と同じ）
    struct Line: Identifiable, Hashable {
        let number: Int
        let text: String
        var id: Int { number }
    }

    /// 要約の節（見出しの行を含む）。最初の `## ` の節がなければ空
    private(set) var summary: [Line] = []
    /// 本文（要約・タイトル・外したアクションアイテムの節を除いた行）
    private(set) var body: [Line] = []
    /// 本文から外したアクションアイテムの節の行（見出しを含む）
    private(set) var hiddenActionSection: [Line] = []
    /// 先頭のタイトルの行の番号
    private(set) var titleLine: Int?

    /// - Parameter hidesActionSection: アクションアイテムをカードで出すか（カードが 1 件以上あるとき）
    init(markdown: String, hidesActionSection: Bool) {
        let lines = markdown.components(separatedBy: "\n").enumerated().map { Line(number: $0.offset, text: $0.element) }
        var sections: [[Line]] = []
        var preamble: [Line] = []
        for line in lines {
            let trimmed = line.text.trimmingCharacters(in: .whitespaces)
            if titleLine == nil, sections.isEmpty, trimmed.hasPrefix("# ") {
                titleLine = line.number
                continue
            }
            if trimmed.hasPrefix("## ") {
                sections.append([line])
            } else if sections.isEmpty {
                preamble.append(line)
            } else {
                sections[sections.count - 1].append(line)
            }
        }
        body = Self.trimmed(preamble)
        for (index, section) in sections.enumerated() {
            let heading = section[0].text.trimmingCharacters(in: .whitespaces).dropFirst(3)
            if hidesActionSection, ActionItem.isActionHeading(heading) {
                hiddenActionSection += section
            } else if index == 0 {
                summary = Self.trimmed(section)
            } else {
                body += section
            }
        }
        body = Self.trimmed(body)
    }

    /// 前後の空行を除く
    private static func trimmed(_ lines: [Line]) -> [Line] {
        var lines = lines
        while let first = lines.first, first.text.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeFirst() }
        while let last = lines.last, last.text.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        return lines
    }

    // 設計判断: DEC-MTG-133
    /// 検索でヒットした行が、外したアクションアイテムの節の中なら、カードの何行目へ移るか（節の見出しなら 0）。
    /// 節の外なら nil。チェックボックスの行を数えて、カードの同じ順番の行にする
    func actionRow(forLine number: Int) -> Int? {
        guard hiddenActionSection.contains(where: { $0.number == number }) else { return nil }
        let count = hiddenActionSection.filter { line in
            let trimmed = line.text.trimmingCharacters(in: .whitespaces)
            return line.number <= number && (trimmed.hasPrefix("- [ ] ") || trimmed.hasPrefix("- [x] "))
        }.count
        return max(0, count - 1)
    }
}

// 要件: REQ-MTG-054
// 設計判断: DEC-MTG-136
/// 記録のあとの処理の段階
enum MeetingProcessingStage: String, CaseIterable {
    /// 音声ファイルから文字起こしする（Whisper / Gemini のときだけ）
    case transcribing
    /// 話者を区別する
    case diarizing
    /// 議事録を作る
    case minutes

    var title: String {
        switch self {
        case .transcribing: tr("文字起こし")
        case .diarizing: tr("話者の区別")
        case .minutes: tr("議事録")
        }
    }
}

// 要件: REQ-MTG-051
// 設計判断: DEC-MTG-138
/// 会議の一覧の日付のまとまり（今日・昨日・今週・先週・それより前は月ごと）
enum MeetingListGrouping {
    struct Group: Identifiable, Equatable {
        let id: String
        let title: String
        var meetings: [Meeting]

        static func == (a: Group, b: Group) -> Bool {
            a.id == b.id && a.title == b.title && a.meetings.map(\.id) == b.meetings.map(\.id)
        }
    }

    /// 開始の新しい順に並べ、まとまりに分ける。週の始まりは calendar の firstWeekday（言語と地域の設定）に任せる
    static func groups(_ meetings: [Meeting], now: Date = Date(), calendar: Calendar = .current,
                       locale: Locale = UILanguage.locale) -> [Group] {
        let sorted = meetings.sorted { $0.startedAt > $1.startedAt }
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        let lastWeek = calendar.date(byAdding: .day, value: -7, to: thisWeek) ?? thisWeek
        let monthFormatter = DateFormatter()
        monthFormatter.locale = locale
        monthFormatter.calendar = calendar
        monthFormatter.setLocalizedDateFormatFromTemplate("yMMMM")

        var groups: [Group] = []
        for meeting in sorted {
            let date = meeting.startedAt
            let key: String
            let title: String
            if date >= today {
                (key, title) = ("today", tr("今日"))
            } else if date >= yesterday {
                (key, title) = ("yesterday", tr("昨日"))
            } else if date >= thisWeek {
                (key, title) = ("thisWeek", tr("今週"))
            } else if date >= lastWeek {
                (key, title) = ("lastWeek", tr("先週"))
            } else {
                let parts = calendar.dateComponents([.year, .month], from: date)
                key = "month-\(parts.year ?? 0)-\(parts.month ?? 0)"
                title = monthFormatter.string(from: date)
            }
            if groups.last?.id == key {
                groups[groups.count - 1].meetings.append(meeting)
            } else {
                groups.append(Group(id: key, title: title, meetings: [meeting]))
            }
        }
        return groups
    }
}
