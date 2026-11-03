import Foundation

enum MeetingChannel: String, Codable {
    /// マイク（自分）
    case me
    /// システム音声（相手側）
    case others
}

/// 時刻つきの語。時刻は録音開始を 0 秒とした秒数。
struct TimedWord: Codable, Hashable {
    var text: String
    var start: Double
    var end: Double
}

/// 音声認識の確定結果 1 つ分（だいたい一区切りの発話）
struct TranscribedPhrase: Codable, Hashable {
    var channel: MeetingChannel
    var start: Double
    var end: Double
    var text: String
    var words: [TimedWord]
}

/// 話者が決まった発言
struct Utterance: Codable, Hashable, Identifiable {
    var id = UUID()
    /// 話者キー: "me" / "others" / "spk1", "spk2", ...
    var speaker: String
    var start: Double
    var end: Double
    var text: String
}

// 設計判断: DEC-MTG-017
struct Meeting: Codable, Identifiable, Hashable {
    enum Status: String, Codable {
        case recording, processing, done, failed
    }

    /// 保存フォルダ名
    var id: String
    var title: String
    var startedAt: Date
    var duration: Double = 0
    var status: Status = .recording
    /// 話者キー → 表示名
    var speakerNames: [String: String] = [:]
    var utterances: [Utterance] = []
    var minutes: String?
    var errorMessage: String?
    /// 議事録の型（MinutesTemplate の rawValue）。nil は「自動」
    var minutesTemplate: String?
    /// 型が「カスタム」のときの指示
    var customMinutesPrompt: String?
    /// 議事録から取り出したアクションアイテム。nil はこの機能より前に作った議事録
    var actionItems: [ActionItem]?
    /// ユーザーのメモと「ここ重要」の印（MeetingNotes.swift）。古い会議の meeting.json にはないので省略可にする
    var notes: [MeetingNote]?

    // 要件: REQ-MTG-008
    func displayName(for speaker: String) -> String {
        if let name = speakerNames[speaker], !name.isEmpty { return name }
        switch speaker {
        case "me": return "自分"
        case "others": return "相手"
        default:
            if speaker.hasPrefix("spk"), let n = Int(speaker.dropFirst(3)) { return "話者\(n)" }
            if speaker.hasPrefix("room"), let n = Int(speaker.dropFirst(4)) { return "同席者\(n)" }
            return speaker
        }
    }

    /// 登場順の話者キー
    var speakers: [String] {
        var seen: [String] = []
        for u in utterances where !seen.contains(u.speaker) { seen.append(u.speaker) }
        return seen
    }

    // 要件: REQ-MTG-005
    /// 文字起こしの Markdown。同じ話者が間を空けずに続く発言はまとめる。
    func transcriptMarkdown() -> String {
        var lines = ["# \(title) — 文字起こし", "", "- 日時: \(Self.dateFormatter.string(from: startedAt))", "- 長さ: \(Self.clock(duration))", ""]
        for block in mergedBlocks() {
            lines.append("**[\(Self.clock(block.start))] \(displayName(for: block.speaker))**: \(block.text)")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// Gemini に渡す文字起こし（1 発言 1 行）
    func transcriptForPrompt() -> String {
        mergedBlocks()
            .map { "[\(Self.clock($0.start))] \(displayName(for: $0.speaker)): \($0.text)" }
            .joined(separator: "\n")
    }

    func mergedBlocks(maxGap: Double = 2.0) -> [Utterance] {
        var blocks: [Utterance] = []
        for u in utterances.sorted(by: { $0.start < $1.start }) {
            if var last = blocks.last, last.speaker == u.speaker, u.start - last.end <= maxGap {
                last.text += u.text
                last.end = max(last.end, u.end)
                blocks[blocks.count - 1] = last
            } else {
                blocks.append(u)
            }
        }
        return blocks
    }

    static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%02d:%02d", s / 60, s % 60)
    }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy/MM/dd (E) HH:mm"
        return f
    }()
}

// 要件: REQ-MTG-025
/// 会議の記録を ~/Documents/Hanasu/Meetings/<会議>/ に保存する。
enum MeetingStore {
    static var baseDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hanasu/Meetings", isDirectory: true)
    }

    static func directory(for meeting: Meeting) -> URL {
        baseDirectory.appendingPathComponent(meeting.id, isDirectory: true)
    }

    static func newMeeting(at date: Date = Date()) throws -> Meeting {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HHmm"
        var id = f.string(from: date)
        var suffix = 2
        while FileManager.default.fileExists(atPath: baseDirectory.appendingPathComponent(id).path) {
            id = f.string(from: date) + " (\(suffix))"
            suffix += 1
        }
        let meeting = Meeting(id: id, title: "会議 \(Meeting.dateFormatter.string(from: date))", startedAt: date)
        try FileManager.default.createDirectory(at: directory(for: meeting), withIntermediateDirectories: true)
        return meeting
    }

    // 要件: REQ-MTG-005
    // 設計判断: DEC-MTG-017
    static func save(_ meeting: Meeting) throws {
        let dir = directory(for: meeting)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(meeting).write(to: dir.appendingPathComponent("meeting.json"), options: .atomic)
        try meeting.transcriptMarkdown().write(to: dir.appendingPathComponent("transcript.md"), atomically: true, encoding: .utf8)
        if let minutes = meeting.minutes {
            try minutes.write(to: dir.appendingPathComponent("minutes.md"), atomically: true, encoding: .utf8)
        }
        let notesURL = dir.appendingPathComponent("notes.md")
        if meeting.allNotes.isEmpty {
            try? FileManager.default.removeItem(at: notesURL)
        } else {
            try meeting.notesMarkdown().write(to: notesURL, atomically: true, encoding: .utf8)
        }
    }

    // 設計判断: DEC-MTG-018
    /// アプリが落ちたり終了したりして「記録中」「処理中」のまま残った会議を「失敗」にする（起動時に 1 回呼ぶ）
    static func markInterruptedMeetings() {
        for var meeting in loadAll() where meeting.status == .recording || meeting.status == .processing {
            meeting.status = .failed
            meeting.errorMessage = "記録の途中でアプリが終了しました。音声ファイル（me.m4a / others.m4a）は途中まで残っている場合があります。"
            try? save(meeting)
        }
    }

    static func loadAll() -> [Meeting] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let dirs = (try? FileManager.default.contentsOfDirectory(at: baseDirectory, includingPropertiesForKeys: nil)) ?? []
        return dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("meeting.json")) else { return nil }
            return try? decoder.decode(Meeting.self, from: data)
        }
        .sorted { $0.startedAt > $1.startedAt }
    }

    static func audioURL(for meeting: Meeting, channel: MeetingChannel) -> URL {
        directory(for: meeting).appendingPathComponent(channel == .me ? "me.m4a" : "others.m4a")
    }
}
