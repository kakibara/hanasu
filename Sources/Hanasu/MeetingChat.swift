import Foundation

// 要件: REQ-MTG-040, REQ-MTG-041
/// 会議の AI チャット: その時点までの文字起こし・メモ・印と、それまでの会話を AI に渡して答えさせる。
/// 記録中はライブの文字起こし（確定前の途中結果も）を、記録のあとは確定した文字起こしを使う。
/// 会議の内容を送る先は、設定の「AI」で会議に選んだ AI だけ。
enum MeetingChat {
    /// 会話の 1 件
    struct Message: Identifiable, Hashable {
        enum Role: String {
            case user, assistant
        }

        var id = UUID()
        var role: Role
        var text: String
        /// 答えのとき: 渡した記録の終わり（録音開始からの秒数）
        var coveredUntil: Double?
        /// 答えのとき: 渡した発言の数
        var lineCount: Int?
    }

    /// 文字起こしの 1 行
    struct Line: Hashable {
        var time: Double
        var speaker: String
        var text: String

        var formatted: String { "[\(Meeting.clock(time))] \(speaker): \(text)" }
    }

    /// AI に渡す会議の記録（送る時点のもの）
    struct Material {
        var title: String
        var startedAt: Date
        /// 記録中（または記録のあとの処理中）か
        var live: Bool
        /// 記録中なら録音開始からの経過秒数、記録のあとなら会議の長さ
        var elapsed: Double
        var lines: [Line]
        /// 確定前の途中結果（記録中だけ）
        var pending: [Line] = []
        /// 本人のメモと「ここ重要」の印（Meeting.notesForPrompt の形）
        var notes: String?
        /// 記録中は文字起こししないエンジン（Whisper / Gemini）の名前。Mac 標準なら nil
        var batchEngineName: String?
    }

    // 設計判断: DEC-MTG-082
    struct Options {
        /// 文字起こしの合計の上限（文字数）。超えたら古い発言から省く
        var maxTranscriptCharacters = 120_000
        /// 渡す、それまでの会話の件数（質問と答えを合わせて）
        var maxHistoryMessages = 20
        /// 渡す、それまでの会話 1 件の上限（文字数）
        var maxHistoryMessageCharacters = 3_000
    }

    struct Prompt {
        var text: String
        /// 渡した記録の終わり（録音開始からの秒数）
        var coveredUntil: Double
        /// 渡した発言の数（確定前を含まない）
        var lineCount: Int
        /// 上限のために省いた古い発言の数
        var omittedLines: Int
    }

    // MARK: - 記録を集める

    /// 記録中の会議の、今の記録。記録中の会議がなければ nil
    @MainActor
    static func liveMaterial(recorder: MeetingRecorder) -> Material? {
        guard let meeting = recorder.current else { return nil }
        let lines = recorder.liveLines.map {
            Line(time: $0.start, speaker: Meeting.promptLabel(for: $0.channel == .me ? "me" : "others"), text: $0.text)
        }
        let elapsed = meeting.duration > 0 ? meeting.duration : recorder.elapsed
        var pending: [Line] = []
        if !recorder.volatileOthers.isEmpty { pending.append(Line(time: elapsed, speaker: Meeting.promptLabel(for: "others"), text: recorder.volatileOthers)) }
        if !recorder.volatileMe.isEmpty { pending.append(Line(time: elapsed, speaker: Meeting.promptLabel(for: "me"), text: recorder.volatileMe)) }
        return Material(title: meeting.title, startedAt: meeting.startedAt, live: true, elapsed: elapsed,
                        lines: lines, pending: pending, notes: meeting.notesForPrompt(),
                        batchEngineName: recorder.batchEngine?.shortName)
    }

    /// 記録のあとの会議の記録（確定した文字起こしと、付け替えた話者名）
    static func material(for meeting: Meeting) -> Material {
        let lines = meeting.mergedBlocks().map {
            Line(time: $0.start, speaker: meeting.promptName(for: $0.speaker), text: $0.text)
        }
        return Material(title: meeting.title, startedAt: meeting.startedAt, live: false, elapsed: meeting.duration,
                        lines: lines, notes: meeting.notesForPrompt())
    }

    // MARK: - プロンプト

    // 設計判断: DEC-MTG-081
    // 要件: REQ-COM-061
    /// 文面は Resources/Prompts/<言語>.json の chat.system
    static var instruction: String { Prompts.text("chat.system") }

    // 設計判断: DEC-MTG-081, DEC-MTG-082, DEC-COM-054
    /// AI に渡す本文を作る。記録は送る時点のものを毎回渡し、それまでの会話は <conversation> に入れる。
    /// 答えのない質問（失敗・取り消し）は会話に入れない
    static func prompt(question: String, material: Material, history: [Message],
                       options: Options = Options(), now: Date = Date()) -> Prompt {
        // 文字起こしは新しい発言を残す（会議中の質問は直近の話についてが多いため）
        var kept: [String] = []
        var used = 0
        for line in material.lines.reversed() {
            let text = line.formatted
            if used + text.count > options.maxTranscriptCharacters, !kept.isEmpty { break }
            kept.append(text)
            used += text.count
        }
        kept.reverse()
        let omitted = material.lines.count - kept.count

        var transcript: [String] = []
        if omitted > 0 { transcript.append(Prompts.text("chat.transcript.omitted", ["count": "\(omitted)"])) }
        if kept.isEmpty {
            if let engine = material.batchEngineName, material.live {
                transcript.append(Prompts.text("chat.transcript.afterRecording", ["engine": engine]))
            } else {
                transcript.append(Prompts.text("chat.transcript.empty"))
            }
        }
        transcript += kept

        let status = material.live
            ? Prompts.text("chat.status.live", ["elapsed": Meeting.clock(material.elapsed)])
            : Prompts.text("chat.status.done", ["duration": Meeting.clock(material.elapsed)])
        var sections = ["""
        <transcript>
        \(PromptText.neutralizeDelimiters(transcript.joined(separator: "\n")))
        </transcript>
        """]
        if !material.pending.isEmpty {
            sections.append("<pending_transcript>\n\(PromptText.neutralizeDelimiters(material.pending.map(\.formatted).joined(separator: "\n")))\n</pending_transcript>")
        }
        if let notes = material.notes, !notes.isEmpty {
            sections.append("<user_notes>\n\(PromptText.neutralizeDelimiters(notes))\n</user_notes>")
        }
        let title = material.title.replacingOccurrences(of: "\"", with: "'")
        // 要件: REQ-COM-061（日時の曜日はプロンプトの言語で書く）
        let dateFormatter = PromptLanguage.current.dateFormatter
        var text = """
        \(Prompts.text("chat.now", ["date": dateFormatter.string(from: now)]))

        <meeting title="\(title)" date="\(dateFormatter.string(from: material.startedAt))" status="\(status)">
        \(sections.joined(separator: "\n"))
        </meeting>
        """

        let turns = answeredTurns(history).suffix(options.maxHistoryMessages)
        if !turns.isEmpty {
            let body = turns.map { message -> String in
                var content = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if content.count > options.maxHistoryMessageCharacters {
                    content = String(content.prefix(options.maxHistoryMessageCharacters)) + Prompts.text("chat.history.omitted")
                }
                return "<\(message.role.rawValue)>\n\(PromptText.neutralizeDelimiters(content))\n</\(message.role.rawValue)>"
            }
            text += "\n\n<conversation>\n\(body.joined(separator: "\n"))\n</conversation>"
        }
        text += "\n\n<question>\n\(PromptText.neutralizeDelimiters(question))\n</question>"
        return Prompt(text: text, coveredUntil: material.elapsed, lineCount: material.lines.count, omittedLines: omitted)
    }

    /// 答えの付いた質問と、その答えだけを残す
    static func answeredTurns(_ history: [Message]) -> [Message] {
        var result: [Message] = []
        for (i, message) in history.enumerated() where message.role == .user {
            guard history.indices.contains(i + 1), history[i + 1].role == .assistant else { continue }
            result.append(message)
            result.append(history[i + 1])
        }
        return result
    }

    // MARK: - AI に聞く

    // 設計判断: DEC-MTG-081
    /// 質問を送り、答えを返す。会議中は速さを優先して effort は low にする
    static func reply(question: String, material: Material, history: [Message], client: TextAIClient,
                      model: String, options: Options = Options()) async throws -> (text: String, prompt: Prompt) {
        let prompt = MeetingChat.prompt(question: question, material: material, history: history, options: options)
        let text = try await client.generate(systemInstruction: instruction, userText: prompt.text, model: model, effort: .low)
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), prompt)
    }

    // MARK: - よく使う質問

    // 設計判断: DEC-MTG-083
    struct QuickPrompt: Identifiable, Hashable {
        var id: String
        var label: String
        var symbol: String
        var question: String
    }

    // 設計判断: DEC-MTG-083
    /// 1 回押すだけで送れる質問（会議中に、打つ手間をかけずに聞けるように）
    // 要件: REQ-COM-061
    /// 送る質問の文面はプロンプトの言語（chat.quick.<id>）
    static var quickPrompts: [QuickPrompt] {
        [
            QuickPrompt(id: "summary", label: tr("ここまでを要約"), symbol: "text.alignleft", question: Prompts.text("chat.quick.summary")),
            QuickPrompt(id: "recent", label: tr("直近 5 分の話"), symbol: "clock.arrow.circlepath", question: Prompts.text("chat.quick.recent")),
            QuickPrompt(id: "decisions", label: tr("決まったこと・宿題"), symbol: "checklist", question: Prompts.text("chat.quick.decisions")),
            QuickPrompt(id: "explain", label: tr("今の話を分かりやすく"), symbol: "lightbulb", question: Prompts.text("chat.quick.explain")),
            QuickPrompt(id: "questions", label: tr("聞いておくとよいこと"), symbol: "questionmark.bubble", question: Prompts.text("chat.quick.questions")),
        ]
    }

    // MARK: - 答えの中の時刻

    // 設計判断: DEC-MTG-084
    /// 時刻のリンクの URL のスキーム（hanasu-time://<秒>）。アプリの外には出さない
    static let timeLinkScheme = "hanasu-time"

    // 設計判断: DEC-MTG-084
    /// 答えの中の [12:34]（全角の［］も）を、押すと文字起こしのその時刻へ移る Markdown のリンクにする
    static func linkingTimes(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "[\\[［](\\d{1,2}:\\d{2}(?::\\d{2})?)[\\]］](?!\\()") else { return text }
        var result = text
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard let whole = Range(match.range, in: result), let clock = Range(match.range(at: 1), in: result),
                  let seconds = MeetingNote.parseClock(result[clock]) else { continue }
            let label = String(result[clock])
            result.replaceSubrange(whole, with: "[\(label)](\(timeLinkScheme)://\(Int(seconds)))")
        }
        return result
    }

    // 設計判断: DEC-MTG-084
    /// 時刻のリンクの飛び先: その時刻に話していた発言（その時刻までに始まった最後の発言。なければ最初の発言）。
    /// starts は発言の開始時刻（時刻の順）。答えの時刻は秒を切り捨てているので、1 秒の幅を見る
    static func lineIndex(at seconds: Double, starts: [Double]) -> Int? {
        guard !starts.isEmpty else { return nil }
        return starts.lastIndex { $0 <= seconds + 1 } ?? 0
    }

    /// 時刻のリンクの秒数。時刻のリンクでなければ nil
    static func seconds(from url: URL) -> Double? {
        guard url.scheme == timeLinkScheme, let host = url.host else { return nil }
        return Double(host)
    }

    // MARK: - メモに残す

    // 設計判断: DEC-MTG-085
    /// 答えをメモの 1 行にする（メモはテキストの形式で 1 行 1 件なので、改行と Markdown の記号を除く）
    static func noteText(from answer: String, limit: Int = 600) -> String {
        let parts = answer.components(separatedBy: .newlines).compactMap { raw -> String? in
            var line = raw.trimmingCharacters(in: .whitespaces)
            for prefix in ["- [ ] ", "- [x] ", "### ", "## ", "# ", "- ", "* ", "・"] where line.hasPrefix(prefix) {
                line = String(line.dropFirst(prefix.count))
                break
            }
            line = line.replacingOccurrences(of: "**", with: "")
            line = line.trimmingCharacters(in: .whitespaces)
            return line.isEmpty ? nil : line
        }
        var text = "AI: " + parts.joined(separator: " / ")
        if text.count > limit { text = String(text.prefix(limit)) + "…" }
        return text
    }
}
