import Foundation

// 要件: REQ-MTG-017
// 設計判断: DEC-MTG-060
/// 議事録の型（テンプレート）。型ごとに、Gemini に渡す見出しの構成と書き方の指示を持つ。
enum MinutesTemplate: String, CaseIterable, Identifiable, Codable {
    /// 会議の種類を決めずにまとめる（従来の議事録）
    case auto
    /// 定例・進捗確認
    case regular
    case oneOnOne
    /// 顧客との打ち合わせ
    case sales
    case brainstorm
    /// ユーザーが書いた指示に従う
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: tr("自動")
        case .regular: tr("定例")
        case .oneOnOne: "1on1"
        case .sales: tr("商談")
        case .brainstorm: tr("ブレスト")
        case .custom: tr("カスタム")
        }
    }

    var systemImage: String {
        switch self {
        case .auto: "wand.and.stars"
        case .regular: "calendar"
        case .oneOnOne: "person.2"
        case .sales: "briefcase"
        case .brainstorm: "lightbulb"
        case .custom: "slider.horizontal.3"
        }
    }

    /// 選ぶときに出す短い説明
    var summary: String {
        switch self {
        case .auto: tr("概要・話し合った内容・決定事項・アクションアイテム")
        case .regular: tr("進捗・報告・課題・決定事項・アクションアイテム")
        case .oneOnOne: tr("近況・相談・フィードバック・合意・アクションアイテム")
        case .sales: tr("顧客の課題・提案内容・反応・懸念・次のアクション")
        case .brainstorm: tr("出たアイデア・有望な案・論点・次のステップ")
        case .custom: tr("自分で書いた指示に従う")
        }
    }

    // 要件: REQ-COM-061
    /// アクションアイテムの見出し（Markdown の「## 」のあと。プロンプトの言語で書く）
    var actionHeading: String {
        switch self {
        case .sales: Prompts.text("minutes.actionHeading.sales")
        case .brainstorm: Prompts.text("minutes.actionHeading.brainstorm")
        default: Prompts.text("minutes.actionHeading")
        }
    }

    // 要件: REQ-COM-061
    /// 会議の種類についての説明（どこに注目してまとめるか）
    fileprivate var guidance: String {
        switch self {
        case .auto, .custom: ""
        default: Prompts.text("minutes.guidance.\(rawValue)")
        }
    }

    // 要件: REQ-COM-061
    /// 議事録の本文の見出しの構成（アクションアイテムと話者のメモは共通なので含めない）
    fileprivate var sections: String {
        Prompts.text("minutes.sections.\(self == .custom ? MinutesTemplate.auto.rawValue : rawValue)")
    }
}

// 要件: REQ-MTG-018
// 設計判断: DEC-MTG-063
/// 議事録から取り出したアクションアイテム（担当・内容・期限）
struct ActionItem: Codable, Hashable, Identifiable {
    var id = UUID()
    /// 担当者（文字起こしの話者名）。分からなければ nil
    var owner: String?
    /// やること
    var task: String
    /// 期限の日付（yyyy-MM-dd）。会議の日付から日付を決められなかったときは nil
    var due: String?
    /// 期限について話された言い方（「来週中」など）
    var dueNote: String?
    /// 登録したリマインダーの識別子（二重登録を避ける）
    var reminderID: String?

    var dueDate: Date? {
        due.flatMap { Self.isoFormatter.date(from: $0) }
    }

    /// 表示用の期限（日付が決まっていれば「11/14 (金)」、なければ話された言い方）
    var dueDisplay: String? {
        if let dueDate { return Self.shortFormatter.string(from: dueDate) }
        if let dueNote, !dueNote.isEmpty { return dueNote }
        return nil
    }

    // 要件: REQ-COM-061
    /// 議事録に書く 1 行（`- [ ] 内容（担当: 〇〇 / 期限: 11/14 (金)）`）。「担当」「期限」と日付はプロンプトの言語で書く
    var markdownLine: String { markdownLine(language: .current) }

    // 要件: REQ-COM-061
    /// 議事録を作ったときのプロンプトの言語で書く（作っている間に設定の言語が変わっても、議事録の中でそろえる）
    func markdownLine(language: PromptLanguage) -> String {
        var notes: [String] = []
        if let owner, !owner.isEmpty { notes.append(Prompts.text("minutes.item.owner", language: language) + ": \(owner)") }
        let due: String? = dueDate.map { date in
            let f = DateFormatter()
            f.locale = language.locale
            f.dateFormat = Prompts.text("minutes.item.dueDateFormat", language: language)
            return f.string(from: date)
        } ?? dueNote.flatMap { $0.isEmpty ? nil : $0 }
        if let due { notes.append(Prompts.text("minutes.item.due", language: language) + ": \(due)") }
        guard !notes.isEmpty else { return "- [ ] \(task)" }
        return "- [ ] \(task)" + Prompts.text("minutes.item.details", ["details": notes.joined(separator: " / ")], language: language)
    }

    static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let shortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = UILanguage.locale
        f.dateFormat = "M/d (E)"
        return f
    }()

    // 要件: REQ-COM-061
    /// 議事録の言語はそのときのプロンプトの言語なので、読むときはすべての言語の言い方を受け付ける。
    /// 前から使っている日本語の語は見出しに含まれていればよいが、各言語の見出しは見出しの全体と一致したときだけにする
    /// （「## Задачи клиента」のような別の見出しを、アクションアイテムの節と取り違えないように）
    static let legacyActionHeadingWords = ["TODO", "ToDo", "アクション", "次のステップ"]  // skip-tr（前の版の議事録の見出し）
    static var actionHeadings: [String] {
        ["minutes.actionHeading", "minutes.actionHeading.sales", "minutes.actionHeading.brainstorm"].flatMap(Prompts.allTexts)
    }

    static func isActionHeading(_ heading: Substring) -> Bool {
        let trimmed = heading.trimmingCharacters(in: .whitespaces)
        return legacyActionHeadingWords.contains { trimmed.contains($0) }
            || actionHeadings.contains { $0.compare(trimmed, options: .caseInsensitive) == .orderedSame }
    }
    static var ownerKeys: [String] { Prompts.allTexts("minutes.item.owner") }
    static var dueKeys: [String] { Prompts.allTexts("minutes.item.due") }
    static var noneWords: [String] { Prompts.allTexts("minutes.result.none") }

    // 設計判断: DEC-MTG-064
    /// Markdown の議事録のチェックボックスの行から取り出す（この機能より前に作った議事録や、JSON が壊れていたとき用）。
    /// 「TODO」「アクション」「次のステップ」を含む見出しの下の `- [ ] 内容（担当: 〇〇 / 期限: △△）` を読む。
    static func parse(fromMarkdown markdown: String) -> [ActionItem] {
        var items: [ActionItem] = []
        var inSection = false
        for raw in markdown.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                let heading = line.dropFirst(3)
                inSection = isActionHeading(heading)
                continue
            }
            guard inSection, line.hasPrefix("- [ ] ") || line.hasPrefix("- [x] ") else { continue }
            var task = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            var owner: String?
            var dueNote: String?
            // 末尾の（担当: … / 期限: …）。期限には「11/14 (金)」のようにかっこや / が入るので、
            // 「担当」「期限」の言葉で始まるかっこを探し、中を「 / 」で分ける
            if let close = task.last, close == "）" || close == ")",  // skip-tr（照らし合わせ・区切りに使う記号）
               let open = detailsOpening(in: task) {
                let inner = String(task[task.index(after: open)..<task.index(before: task.endIndex)])
                var recognized = false
                for part in inner.components(separatedBy: " / ").flatMap({ $0.components(separatedBy: "／") }) {
                    let pair = part.split(maxSplits: 1, whereSeparator: { $0 == ":" || $0 == "：" })  // skip-tr（照らし合わせ・区切りに使う記号）
                    guard pair.count == 2 else { continue }
                    let key = pair[0].trimmingCharacters(in: .whitespaces)
                    let value = pair[1].trimmingCharacters(in: .whitespaces)
                    let unknown = value.isEmpty || ["不明", "未定", "-"].contains(value) || noneWords.contains(value) || value.hasPrefix("分かれば")  // skip-tr（言語の決まりに使う語。FUT-014）
                    if ownerKeys.contains(key) { recognized = true; owner = unknown ? nil : value }
                    if dueKeys.contains(key) { recognized = true; dueNote = unknown ? nil : value }
                }
                if recognized { task = String(task[..<open]).trimmingCharacters(in: .whitespaces) }
            }
            guard !task.isEmpty, !noneWords.contains(task) else { continue }
            items.append(ActionItem(owner: owner, task: task, dueNote: dueNote))
        }
        return items
    }

    /// 「（担当: …」「(Owner: …」のように、担当か期限の言葉とコロンで始まるかっこの位置
    static func detailsOpening(in task: String) -> String.Index? {
        let keys = ownerKeys + dueKeys
        var index = task.startIndex
        while index < task.endIndex {
            if task[index] == "（" || task[index] == "(" {  // skip-tr（照らし合わせ・区切りに使う記号）
                let after = task[task.index(after: index)...].drop { $0 == " " }
                let startsWithKey = keys.contains { key in
                    guard after.hasPrefix(key) else { return false }
                    let rest = after.dropFirst(key.count).drop { $0 == " " }
                    return rest.first == ":" || rest.first == "："  // skip-tr（照らし合わせ・区切りに使う記号）
                }
                if startsWithKey { return index }
            }
            index = task.index(after: index)
        }
        return nil
    }
}

extension Meeting {
    /// 議事録の型（保存されていなければ「自動」）
    var template: MinutesTemplate {
        minutesTemplate.flatMap(MinutesTemplate.init(rawValue:)) ?? .auto
    }

    /// 書き出し・リマインダー用のアクションアイテム。古い議事録は Markdown から読み取る。
    var resolvedActionItems: [ActionItem] {
        actionItems ?? minutes.map(ActionItem.parse(fromMarkdown:)) ?? []
    }
}

// 設計判断: DEC-MTG-061
/// 記録を始める前に選んだ議事録の型と、カスタムの指示（UserDefaults）。
/// 会議ノートの左下の選択欄（@AppStorage）と同じキーを使う。
enum MinutesTemplateStore {
    static let templateKey = "meetingMinutesTemplate"
    static let customPromptKey = "meetingCustomMinutesPrompt"

    // 要件: REQ-COM-061
    /// カスタムの指示の例（プロンプトの言語）
    static var defaultCustomPrompt: String { Prompts.text("minutes.customDefault") }

    static var selected: MinutesTemplate {
        UserDefaults.standard.string(forKey: templateKey).flatMap(MinutesTemplate.init(rawValue:)) ?? .auto
    }

    static var customPrompt: String {
        UserDefaults.standard.string(forKey: customPromptKey) ?? defaultCustomPrompt
    }

    /// 新しく記録する会議に、今選んでいる型を付ける
    static func apply(to meeting: inout Meeting) {
        meeting.minutesTemplate = selected.rawValue
        meeting.customMinutesPrompt = selected == .custom ? customPrompt : nil
    }
}

/// 議事録の作成結果
struct MinutesResult {
    var markdown: String
    var actionItems: [ActionItem]
    /// 応答の <speaker_names> で分かった話者の名前（表示ラベル「話者1」など → 名前）。当てはめは SpeakerNameInference
    var speakerNames: [String: String] = [:]
    // 要件: REQ-COM-061
    /// 議事録を作ったときのプロンプトの言語（応答の中のラベル「Speaker 1」などを、この言語で読む）
    var language: PromptLanguage = .current
}

// 要件: REQ-MTG-006
/// 議事録のプロンプトの組み立てと、応答の読み取り。
enum MinutesPrompt {
    /// アクションアイテムの見出しの下に Gemini が置く目印。アプリが一覧に置き換える。
    static let placeholder = "{{ACTION_ITEMS}}"

    // 要件: REQ-COM-061
    // 設計判断: DEC-MTG-014
    static func systemInstruction(template: MinutesTemplate, customPrompt: String?) -> String {
        var parts: [String] = [Prompts.text("minutes.intro")]
        if !template.guidance.isEmpty { parts.append(template.guidance) }

        let common = Prompts.text("minutes.common", [
            "actionHeading": template.actionHeading,
            "placeholder": placeholder,
            "speakerNotesHeading": Prompts.text("minutes.speakerNotesHeading"),
        ])
        let custom = customPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if template == .custom, !custom.isEmpty {
            parts.append(Prompts.text("minutes.custom", ["custom": custom, "common": common]))
        } else {
            parts.append(Prompts.text("minutes.format", ["sections": template.sections, "common": common]))
        }
        parts.append(Prompts.text("minutes.actionItems", ["actionHeading": template.actionHeading, "placeholder": placeholder]))
        parts.append(speakerNamesInstruction)
        return parts.joined(separator: "\n\n")
    }

    // 要件: REQ-MTG-027, REQ-COM-061
    // 設計判断: DEC-MTG-068
    /// 話者の名前を <speaker_names> で出させる指示（Windows 版 MinutesPrompt.SpeakerNamesInstruction と同じ文面。どちらも Prompts の JSON を読む）
    static var speakerNamesInstruction: String { Prompts.text("minutes.speakerNames") }

    // 設計判断: DEC-COM-054
    static func userText(for meeting: Meeting) -> String {
        // メモか印があれば <user_notes> を足し、印の前後の発言に ★ を付ける（MeetingNotes.swift）。
        // 文字起こし・メモの中の区切りのタグは無害にしてから埋め込む（プロンプトインジェクションの対策。DEC-COM-054）
        let userNotes = meeting.notesForPrompt().map(PromptText.neutralizeDelimiters)
        let transcript = PromptText.neutralizeDelimiters(
            userNotes == nil ? meeting.transcriptForPrompt() : meeting.transcriptForPromptMarkingHighlights())
        let notesBlock = userNotes.map { "\n<user_notes>\n\($0)\n</user_notes>\n" } ?? ""
        let date = PromptLanguage.current.dateFormatter.string(from: meeting.startedAt)
        return """
        \(Prompts.text("minutes.user.meeting", ["title": meeting.title]))
        \(Prompts.text("minutes.user.date", ["date": date, "duration": Meeting.clock(meeting.duration)]))
        \(notesBlock)
        <transcript>
        \(transcript)
        </transcript>
        """
    }

    // 要件: REQ-MTG-018
    // 設計判断: DEC-MTG-062
    /// Gemini の応答を、議事録の Markdown と構造化したアクションアイテムに分ける。
    static func parse(_ response: String, title: String, language: PromptLanguage = .current) -> MinutesResult {
        // 話者の名前（<speaker_names>）を先に取り出す。<action_items> は後ろから探すので、残っていると本文に混ざる
        let (withoutNames, speakerNames) = SpeakerNameInference.extract(from: response)
        var body = withoutNames
        var items: [ActionItem]?
        if let open = body.range(of: "<action_items>", options: .backwards) {
            let rest = body[open.upperBound...]
            let close = rest.range(of: "</action_items>")
            var json = String(close.map { rest[..<$0.lowerBound] } ?? rest)
            json = json.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
            items = decodeItems(json)
            body.removeSubrange(open.lowerBound..<(close?.upperBound ?? body.endIndex))
            // <action_items> をコードブロックで囲んで返したときの残り
            body = body.trimmingCharacters(in: .whitespacesAndNewlines)
            while let fence = ["```xml", "```json", "```"].first(where: body.hasSuffix) {
                body = String(body.dropLast(fence.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        // 小さいモデル（ローカル）は <action_items> を使わず、本文の中に JSON の配列をそのまま書くことがある。
        // 読めれば、その場所を一覧に置き換える
        if items == nil, let inline = inlineItems(in: body) {
            items = inline.items
            let list = inline.items.isEmpty ? Prompts.text("minutes.result.none", language: language) : inline.items.map { $0.markdownLine(language: language) }.joined(separator: "\n")
            body.replaceSubrange(inline.range, with: list)
        }

        let resolved = items ?? ActionItem.parse(fromMarkdown: body)
        if body.contains(placeholder) {
            let list = items == nil
                ? Prompts.text("minutes.result.unreadable", language: language)
                : (resolved.isEmpty ? Prompts.text("minutes.result.none", language: language) : resolved.map { $0.markdownLine(language: language) }.joined(separator: "\n"))
            body = body.replacingOccurrences(of: placeholder, with: list)
        }
        return MinutesResult(markdown: "# " + Prompts.text("minutes.result.title", ["title": title], language: language) + "\n\n\(body)\n",
                             actionItems: resolved, speakerNames: speakerNames, language: language)
    }

    private struct RawItem: Decodable {
        var owner: String?
        var task: String?
        var due: String?
        var due_note: String?
    }

    // 設計判断: DEC-MTG-062
    /// 本文の中の、アクションアイテムの JSON の配列（`[{` から `}]` まで）。読めなければ nil
    static func inlineItems(in body: String) -> (range: Range<String.Index>, items: [ActionItem])? {
        guard let start = body.range(of: "[{"), let end = body.range(of: "}]", options: .backwards),
              start.lowerBound < end.upperBound else { return nil }
        let range = start.lowerBound..<end.upperBound
        guard let items = decodeItems(String(body[range])) else { return nil }
        return (range, items)
    }

    // 設計判断: DEC-MTG-062
    static func decodeItems(_ json: String) -> [ActionItem]? {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let raw = try? JSONDecoder().decode([RawItem].self, from: data) else { return nil }
        func clean(_ s: String?) -> String? {
            let t = s?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return t.isEmpty || t == "null" ? nil : t
        }
        return raw.compactMap { r in
            guard let task = clean(r.task) else { return nil }
            // 日付として読めないものは「言い方」の方に回す
            var due = clean(r.due)
            var note = clean(r.due_note)
            if let d = due, ActionItem.isoFormatter.date(from: d) == nil {
                if note == nil { note = d }
                due = nil
            }
            return ActionItem(owner: clean(r.owner), task: task, due: due, dueNote: note)
        }
    }
}
