import Foundation

// 設計判断: DEC-DIC-088
/// このセッションで入力した音声入力の結果（辞書の候補を探す材料）。
/// メモリ上だけに持ち、ファイルには保存しない（「最近の結果」と同じ扱い）。
@MainActor
enum RecentDictations {
    struct Entry {
        /// 音声認識の結果（置き換えルールを当てる前）
        var raw: String
        /// 実際に入力した文章（置き換え・整形の後）
        var output: String
    }

    static let limit = 50
    private(set) static var entries: [Entry] = []

    static func record(raw: String, output: String) {
        entries.insert(Entry(raw: raw, output: output), at: 0)
        if entries.count > limit { entries.removeLast(entries.count - limit) }
    }
}

/// Gemini が挙げた辞書の候補
struct DictionaryCandidate: Identifiable, Hashable {
    var id = UUID()
    /// 正しい表記
    var spelling: String
    /// 認識されていた形（読み・誤認識）。空なら語だけを登録する
    var readings: [String]
    /// 候補に挙げた理由
    var reason: String

    var entry: UserDictionary.Entry {
        UserDictionary.Entry(reading: readings.joined(separator: ", "), spelling: spelling)
    }
}

// 要件: REQ-DIC-071
/// 過去の音声入力の結果と会議の記録から、Gemini に辞書の候補を挙げてもらう。
/// 設定画面のボタンを押したときだけ動く。候補は自動では辞書に追加しない。
enum DictionarySuggester {
    /// 候補を探す材料
    struct Corpus {
        var dictations: [RecentDictations.Entry] = []
        var meetings: [Meeting] = []

        var isEmpty: Bool { dictations.isEmpty && meetings.isEmpty }

        /// Gemini に渡す本文。長すぎると時間と費用がかかるので、会議 1 件・全体それぞれの長さを抑える
        func promptText(perMeetingLimit: Int = 15_000, totalLimit: Int = 60_000) -> String {
            var parts: [String] = []
            if !dictations.isEmpty {
                let lines = dictations.map { Prompts.text("dictionarySuggest.dictation", ["raw": $0.raw, "output": $0.output]) }
                parts.append(Prompts.text("dictionarySuggest.dictationsHeader") + "\n" + lines.joined(separator: "\n"))
            }
            for meeting in meetings {
                // 設計判断: DEC-DIC-088（会議の文字起こしは、辞書で置き換える前の認識したままの文で送る）
                var text = Prompts.text("dictionarySuggest.meetingHeader", ["title": meeting.title]) + "\n"
                    + Prompts.text("dictionarySuggest.transcriptHeader") + "\n" + meeting.transcriptForPrompt(raw: true)
                if let minutes = meeting.minutes, !minutes.isEmpty {
                    text += "\n" + Prompts.text("dictionarySuggest.minutesHeader") + "\n" + minutes
                }
                parts.append(String(text.prefix(perMeetingLimit)))
            }
            return String(parts.joined(separator: "\n\n").prefix(totalLimit))
        }
    }

    static let meetingLimit = 5

    // 設計判断: DEC-DIC-088
    /// 設定画面から使う材料を集める
    @MainActor
    static func corpus(includeDictations: Bool, includeMeetings: Bool) -> Corpus {
        Corpus(
            dictations: includeDictations ? RecentDictations.entries : [],
            meetings: includeMeetings ? recentMeetings() : [])
    }

    /// 文字起こしのある会議を新しい順に
    static func recentMeetings(limit: Int = meetingLimit) -> [Meeting] {
        Array(MeetingStore.loadAll().filter { !$0.utterances.isEmpty }.prefix(limit))
    }

    // 要件: REQ-COM-061
    static var instruction: String { Prompts.text("dictionarySuggest.system") }

    static func userPrompt(material: String, existing: UserDictionary) -> String {
        let existingWords = existing.spellings + existing.rules.flatMap(\.sources)
        return """
        \(Prompts.text("dictionarySuggest.existing", ["words": existingWords.isEmpty ? Prompts.text("dictionarySuggest.none") : existingWords.joined(separator: ", ")]))

        <material>
        \(material)
        </material>
        """
    }

    // 設計判断: DEC-DIC-088
    static func suggest(corpus: Corpus, existing: UserDictionary, client: TextAIClient, model: String) async throws -> [DictionaryCandidate] {
        try await suggest(material: corpus.promptText(), existing: existing, client: client, model: model)
    }

    // 設計判断: DEC-DIC-088, DEC-DIC-170
    /// 材料を送って候補を受け取り、絞り込む。材料の区切りのタグは先に無害にし、絞り込みも無害にした材料で照らし合わせる
    static func suggest(material: String, existing: UserDictionary, client: TextAIClient, model: String) async throws -> [DictionaryCandidate] {
        var client = client
        // 会議の記録は長いので、整形（15 秒）より長く待つ
        client.timeout = 120
        let material = PromptText.neutralizeDelimiters(material)
        let text = try await client.generate(
            systemInstruction: instruction,
            userText: userPrompt(material: material, existing: existing),
            model: model)
        return filter(try parse(text), existing: existing, material: material)
    }

    /// Gemini の応答（JSON）を読む。コードブロックで囲まれていても読めるよう、最初の { から最後の } までを使う
    static func parse(_ text: String) throws -> [DictionaryCandidate] {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else {
            throw GeminiError.invalidResponse
        }
        struct Envelope: Decodable {
            struct Item: Decodable {
                var spelling: String
                var readings: [String]?
                var reason: String?
            }
            var candidates: [Item]
        }
        let envelope = try JSONDecoder().decode(Envelope.self, from: Data(text[start...end].utf8))
        return envelope.candidates.map {
            DictionaryCandidate(
                spelling: $0.spelling.trimmingCharacters(in: .whitespacesAndNewlines),
                readings: ($0.readings ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) },
                reason: $0.reason ?? "")
        }
    }

    // 設計判断: DEC-DIC-089, DEC-DIC-231
    /// 辞書にすでにあるもの・置き換えに使えない読み・材料に出てこないもの（Gemini の思い込み）を除く。
    /// 画面からの候補（REQ-DIC-075）では、読みは推測なので材料と照らし合わせず（readingsMustAppear: false）、
    /// 表記は読みの有無によらず照らし合わせる（requireSpellingInMaterial: true）。読みの長さと数も絞る
    static func filter(_ candidates: [DictionaryCandidate], existing: UserDictionary, material: String,
                       readingsMustAppear: Bool = true, requireSpellingInMaterial: Bool = false,
                       maxReadings: Int? = nil, maxReadingLength: Int? = nil) -> [DictionaryCandidate] {
        let key = { (s: String) in String(UserDictionary.matchKey(s)) }
        let materialKey = key(material)
        let existingSpellings = Set(existing.spellings.map(key))
        var usedSources = Set(existing.rules.flatMap(\.sources).map(key))
        var seenSpellings = Set<String>()
        var result: [DictionaryCandidate] = []
        for var candidate in candidates {
            let spellingKey = key(candidate.spelling)
            guard !spellingKey.isEmpty, !seenSpellings.contains(spellingKey) else { continue }
            // 表記が材料に出てこないものは、AI が作った語なので除く（画面からの候補では、読みがあっても除く）
            if requireSpellingInMaterial, !materialKey.contains(spellingKey) { continue }
            var kept: [String] = []
            for reading in candidate.readings {
                if let maxReadings, kept.count >= maxReadings { break }
                let k = key(reading)
                // 読みが表記と同じ・短すぎる・長すぎる・ほかのルールで使っている、ものは除く。区切り文字も入れない
                guard k != spellingKey, k.count >= UserDictionary.minimumSourceLength, !usedSources.contains(k),
                      maxReadingLength.map({ reading.count <= $0 }) ?? true,
                      !readingsMustAppear || materialKey.contains(k),
                      !reading.contains(where: { UserDictionary.sourceSeparators.contains($0) }),
                      !UserDictionary.arrows.contains(where: { reading.contains($0) })
                else { continue }
                usedSources.insert(k)
                kept.append(reading)
            }
            candidate.readings = kept
            // 表記がすでに辞書にあり、新しい読みもないなら足すものがない
            if existingSpellings.contains(spellingKey), candidate.readings.isEmpty { continue }
            // 読みも表記も材料に出てこないものは、Gemini が作った語なので除く
            if candidate.readings.isEmpty, !materialKey.contains(spellingKey) { continue }
            seenSpellings.insert(spellingKey)
            result.append(candidate)
        }
        return result
    }

    // MARK: - 会議 1 件（会議ノートから。REQ-DIC-072）

    // 要件: REQ-DIC-072
    // 設計判断: DEC-DIC-170
    /// 材料の長さの上限。Gemini・Claude は字数、ローカル・Apple は見積もったトークン数
    enum Budget: Equatable {
        case characters(Int)
        case tokens(Int)

        func cost(_ text: String) -> Int {
            switch self {
            case .characters: text.count
            case .tokens: AppleFMClient.estimateTokens(text)
            }
        }

        var limit: Int {
            switch self {
            case .characters(let n), .tokens(let n): n
            }
        }
    }

    /// Gemini・Claude に送る材料の上限（設定の欄の全体の上限と同じ）
    static let characterLimit = 60_000

    // 設計判断: DEC-DIC-170
    /// 会議の AI に合わせた上限。ローカル・Apple は、文脈の長さから出力・system instruction・既存の辞書・余白の分を引く。
    /// 見積もりは多めなので（DEC-COM-073）、AI の側で黙って後ろを省かれない
    static func budget(for client: TextAIClient, existing: UserDictionary, instruction: String = instruction) -> Budget {
        let frame = AppleFMClient.estimateTokens(instruction + userPrompt(material: "", existing: existing)) + LongInputFitter.margin
        switch client.backend {
        case .gemini, .claude:
            return .characters(characterLimit)
        case .local(let local):
            return .tokens(max(0, local.model.contextLength - local.maxOutputTokens(.short) - frame))
        case .appleFM:
            return .tokens(max(0, AppleFMClient.contextLength - AppleFMClient.maxOutputTokens(.short) - frame))
        }
    }

    /// 会議 1 件の材料
    struct MeetingMaterial: Equatable {
        var text: String
        /// 文字起こしを途中で切ったとき、読まなかった最初の発言の開始時刻（秒）。全部読んだなら nil
        var cutAt: Double?

        /// 「最初の約 N 分」の N（切ったときだけ）
        var readMinutes: Int? {
            cutAt.map { max(1, Int(($0 / 60).rounded())) }
        }
    }

    // 要件: REQ-DIC-072, REQ-MTG-045, REQ-MTG-046
    // 設計判断: DEC-DIC-170
    /// 会議 1 件の材料。議事録に使う発言（オフレコと除いた発言は入らない）を認識したままの文で先に並べ、議事録の本文は残りに入る分だけ入れる（作り直しを促している議事録は入れない）
    static func meetingMaterial(_ meeting: Meeting, budget: Budget) -> MeetingMaterial {
        let language = PromptLanguage.current
        var parts = [Prompts.text("dictionarySuggest.meetingHeader", ["title": meeting.title]),
                     Prompts.text("dictionarySuggest.transcriptHeader")]
        var used = budget.cost(parts.joined(separator: "\n") + "\n")
        var cutAt: Double?
        for block in meeting.blocksForMinutes() {
            let line = "[\(Meeting.clock(block.start))] \(meeting.promptName(for: block.speaker, language: language)): \(block.recognizedText)"
            let cost = budget.cost(line + "\n")
            if used + cost > budget.limit {
                cutAt = block.start
                break
            }
            parts.append(line)
            used += cost
        }
        // 作り直しを促している議事録は、あとで除いた発言の中身を含みうるので入れない
        if let minutes = meeting.minutes, !minutes.isEmpty, meeting.minutesOutdated != true {
            let header = Prompts.text("dictionarySuggest.minutesHeader")
            var minuteLines: [String] = []
            var minutesUsed = budget.cost("\n" + header + "\n")
            for line in minutes.components(separatedBy: "\n") {
                let cost = budget.cost(line + "\n")
                if used + minutesUsed + cost > budget.limit { break }
                minuteLines.append(line)
                minutesUsed += cost
            }
            if minuteLines.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                parts.append("")
                parts.append(header)
                parts.append(contentsOf: minuteLines)
            }
        }
        return MeetingMaterial(text: parts.joined(separator: "\n"), cutAt: cutAt)
    }

    // MARK: - 画面から（REQ-DIC-075）

    // 要件: REQ-DIC-075
    // 設計判断: DEC-DIC-231
    /// 画面の文字から作った、AI に送る材料。候補の画面はこれをそのまま見せ、同じものを送る
    struct ScreenMaterial: Equatable, Sendable {
        var terms: [String] = []
        var lines: [String] = []
        /// 上限に入りきらず、語か行を外したか
        var truncated = false

        var isEmpty: Bool { terms.isEmpty && lines.isEmpty }

        /// AI に送る本文（見出しと、語は「, 」でつなぎ、行は改行でつなぐ）
        var text: String {
            var parts: [String] = []
            if !terms.isEmpty {
                parts.append(Prompts.text("dictionarySuggest.screenTermsHeader") + "\n" + terms.joined(separator: ", "))
            }
            if !lines.isEmpty {
                parts.append(Prompts.text("dictionarySuggest.screenLinesHeader") + "\n" + lines.joined(separator: "\n"))
            }
            return parts.joined(separator: "\n\n")
        }
    }

    static var screenInstruction: String { Prompts.text("dictionarySuggest.screenSystem") }
    /// 画面からの候補の読みの上限（1 候補あたりの数・1 つの長さ）
    static let screenMaxReadings = 4
    static let screenMaxReadingLength = 20

    // 要件: REQ-DIC-075
    // 設計判断: DEC-DIC-231
    /// OCR の行から材料を作る。語の一覧を先に、残りに行を、上限まで詰める（`ScreenSnapshotLayout.layout` の並べ方を使う）
    static func screenMaterial(_ lines: [ScreenTextLine], budget: Budget) -> ScreenMaterial {
        // 並べ方だけを使うので、layout では上限をかけない
        let ocr = ScreenSnapshotLayout.layout(lines, limit: 10_000_000)
        return screenMaterial(ocr, budget: budget)
    }

    static func screenMaterial(_ ocr: ScreenOCR, budget: Budget) -> ScreenMaterial {
        var material = ScreenMaterial()
        let termsHeader = Prompts.text("dictionarySuggest.screenTermsHeader")
        let linesHeader = Prompts.text("dictionarySuggest.screenLinesHeader")
        var used = budget.cost(termsHeader + "\n" + "\n\n" + linesHeader + "\n")
        for term in ocr.terms {
            let cost = budget.cost(term + ", ")
            if used + cost > budget.limit {
                material.truncated = true
                break
            }
            material.terms.append(term)
            used += cost
        }
        for line in ocr.lines {
            let cost = budget.cost(line + "\n")
            // 行の途中では切らない。入らない行は飛ばして、短い行を入れる
            if used + cost > budget.limit {
                material.truncated = true
                continue
            }
            material.lines.append(line)
            used += cost
        }
        return material
    }

    // 要件: REQ-DIC-075
    // 設計判断: DEC-DIC-231
    /// 画面の材料を送って候補を受け取り、絞り込む（読みは推測を許し、表記はいつも材料と照らし合わせる）
    static func suggestFromScreen(_ material: ScreenMaterial, existing: UserDictionary, client: TextAIClient, model: String) async throws -> [DictionaryCandidate] {
        var client = client
        client.timeout = 120
        let text = PromptText.neutralizeDelimiters(material.text)
        let response = try await client.generate(
            systemInstruction: screenInstruction,
            userText: userPrompt(material: text, existing: existing),
            model: model)
        return filterFromScreen(try parse(response), existing: existing, material: text)
    }

    /// 画面からの候補の絞り込み（`suggestFromScreen` と確かめ方の CLI で同じものを使う）
    static func filterFromScreen(_ candidates: [DictionaryCandidate], existing: UserDictionary, material: String) -> [DictionaryCandidate] {
        filter(candidates, existing: existing, material: material,
               readingsMustAppear: false, requireSpellingInMaterial: true,
               maxReadings: screenMaxReadings, maxReadingLength: screenMaxReadingLength)
    }

    // 設計判断: DEC-DIC-231
    /// 読みをすべて外した候補のうち、表記がもう辞書にあるものを除く（足しても同じ表記の行が重なるだけのため）
    static func droppingRegistered(_ candidates: [DictionaryCandidate], existing: UserDictionary) -> [DictionaryCandidate] {
        let key = { (s: String) in String(UserDictionary.matchKey(s)) }
        let registered = Set(existing.spellings.map(key))
        return candidates.filter { !$0.readings.isEmpty || !registered.contains(key($0.spelling)) }
    }

    // 設計判断: DEC-DIC-087
    /// 選んだ候補を辞書の末尾に足した文字列を返す
    static func appending(_ candidates: [DictionaryCandidate], to text: String) -> String {
        guard !candidates.isEmpty else { return text }
        var text = text
        if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
        return text + candidates.map(\.entry.line).joined(separator: "\n")
    }
}
