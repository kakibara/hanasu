import Carbon.HIToolbox
import Combine
import Foundation

/// 記録中（または記録後）にユーザーが書いたメモ 1 行、または「ここ重要」の印 1 つ。
struct MeetingNote: Codable, Hashable, Identifiable {
    enum Kind: String, Codable {
        /// ユーザーが書いたメモ
        case note
        /// 「ここ重要」の印（text は空でもよい）
        case highlight
    }

    var id = UUID()
    var kind: Kind
    /// 録音開始からの秒数。記録後に時刻なしで書き足したメモは nil
    var time: Double?
    var text: String

    // MARK: - テキスト形式
    // 会議ノートでの編集、notes.md、CLI の --notes で使う形式。1 行が 1 件:
    //   [12:34] メモの本文
    //   [12:40] ★ 印に付けた説明（説明なしなら「[12:40] ★」だけ）
    //   時刻のないメモ

    /// 1 行分のテキスト
    var line: String {
        var parts: [String] = []
        if let time { parts.append("[\(Meeting.clock(time))]") }
        if kind == .highlight { parts.append("★") }
        if !text.isEmpty { parts.append(text) }
        return parts.joined(separator: " ")
    }

    static func text(from notes: [MeetingNote]) -> String {
        notes.map(\.line).joined(separator: "\n")
    }

    /// テキストを読み取る。空行は無視する。
    static func parse(_ text: String) -> [MeetingNote] {
        text.components(separatedBy: .newlines).compactMap { raw in
            var rest = Substring(raw.trimmingCharacters(in: .whitespaces))
            guard !rest.isEmpty else { return nil }
            var time: Double?
            if rest.hasPrefix("["), let close = rest.firstIndex(of: "]"),
               let seconds = parseClock(rest[rest.index(after: rest.startIndex)..<close]) {
                time = seconds
                rest = rest[rest.index(after: close)...].drop { $0 == " " || $0 == "\u{3000}" }
            }
            var kind = Kind.note
            if rest.hasPrefix("★") || rest.hasPrefix("☆") {
                kind = .highlight
                rest = rest.dropFirst().drop { $0 == " " || $0 == "\u{3000}" }
            }
            let body = String(rest).trimmingCharacters(in: .whitespaces)
            if kind == .note, body.isEmpty { return nil }
            return MeetingNote(kind: kind, time: time, text: body)
        }
    }

    /// "mm:ss" か "h:mm:ss" を秒にする
    static func parseClock<S: StringProtocol>(_ s: S) -> Double? {
        let parts = s.split(separator: ":").map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard (2...3).contains(parts.count), parts.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        return Double(parts.reduce(0) { $0 * 60 + $1! })
    }
}

// MARK: - 議事録への反映

extension Meeting {
    /// メモと印（古い会議では空）
    var allNotes: [MeetingNote] { notes ?? [] }
    var highlights: [MeetingNote] { allNotes.filter { $0.kind == .highlight } }

    /// 会議ノートで編集するテキスト
    var notesText: String { MeetingNote.text(from: allNotes) }

    /// notes.md の中身
    func notesMarkdown() -> String {
        "# \(title) — メモ\n\n\(notesText)\n"
    }

    /// 「ここ重要」の印の前後で、強調する範囲（印を押すのは大事な発言を聞いた後なので、前を長めにとる）
    static let highlightLeadTime: Double = 30
    static let highlightTrailTime: Double = 15

    /// 発言が「ここ重要」の印の前後に入るか
    func isNearHighlight(_ block: Utterance) -> Bool {
        highlights.contains { h in
            guard let t = h.time else { return false }
            return block.start <= t + Self.highlightTrailTime && t - Self.highlightLeadTime <= block.end
        }
    }

    /// Gemini に渡す文字起こし。印の前後の発言の行頭に ★ を付ける。
    func transcriptForPromptMarkingHighlights() -> String {
        mergedBlocks()
            .map { "\(isNearHighlight($0) ? "★ " : "")[\(Self.clock($0.start))] \(displayName(for: $0.speaker)): \($0.text)" }
            .joined(separator: "\n")
    }

    /// Gemini に渡すメモ（なければ nil）。時刻のないメモは [--:--] にする。
    func notesForPrompt() -> String? {
        let notes = allNotes
        guard !notes.isEmpty else { return nil }
        return notes.map { note in
            let time = note.time.map { "[\(Self.clock($0))]" } ?? "[--:--]"
            switch note.kind {
            case .note: return "\(time) \(note.text)"
            case .highlight: return "\(time) ★ここ重要\(note.text.isEmpty ? "" : ": \(note.text)")"
            }
        }
        .joined(separator: "\n")
    }
}

extension MeetingProcessor {
    /// メモか印がある会議だけ、議事録の指示に足す
    static let notesInstruction = """
    # 本人のメモと「ここ重要」の印について
    入力の <user_notes> は、記録している本人（「自分」）が会議中に書いたメモと、「ここ重要」の印を付けた時刻です。
    [時刻] は録音開始からの経過時間で、文字起こしの時刻と同じものさしです（[--:--] は会議の後に書き足したメモ）。
    - 本人のメモは、本人が大事だと考えた点です。どの見出しでも、メモに書かれた点を優先して取り上げ、
      文字起こしの該当箇所（メモの時刻と、その少し前）の発言で中身を補ってください。
    - メモにしかない情報（文字起こしにない補足や本人の考え）も落とさず、「（メモより）」と添えて反映してください。
    - 文字起こしの行頭の「★」は、本人が「ここ重要」の印を付けた時刻の前後の発言です。その話題は省略せず詳しめにまとめ、
      決定事項や TODO が含まれていれば必ず拾ってください。
    - 印が 1 つ以上あるときは「## 概要」の次に「## 重要とした箇所」を置き、印ごとに「- [時刻] 内容（誰が何を言ったか）」の形で書いてください。
      印がないときは、この見出しは作らないでください。
    - メモは略語や走り書きのことがあります。文字起こしと照らして、読みやすく直して構いません。
    """
}

// MARK: - 設定（「ここ重要」のショートカット）

/// 会議中のメモの設定。共有の AppSettings とは別に UserDefaults へ保存する。
final class MeetingNotesSettings: ObservableObject {
    static let shared = MeetingNotesSettings()

    static let defaultHighlightHotKey = HotKeyCombo(
        keyCode: UInt32(kVK_ANSI_H), modifiers: UInt32(controlKey | optionKey | cmdKey))

    private let defaults = UserDefaults.standard

    /// 記録中だけ「ここ重要」のショートカットを有効にする
    @Published var highlightHotKeyEnabled: Bool {
        didSet { defaults.set(highlightHotKeyEnabled, forKey: Keys.enabled) }
    }
    @Published var highlightHotKey: HotKeyCombo {
        didSet {
            defaults.set(Int(highlightHotKey.keyCode), forKey: Keys.code)
            defaults.set(Int(highlightHotKey.modifiers), forKey: Keys.modifiers)
        }
    }

    private init() {
        defaults.register(defaults: [
            Keys.enabled: true,
            Keys.code: Int(Self.defaultHighlightHotKey.keyCode),
            Keys.modifiers: Int(Self.defaultHighlightHotKey.modifiers),
        ])
        highlightHotKeyEnabled = defaults.bool(forKey: Keys.enabled)
        highlightHotKey = HotKeyCombo(
            keyCode: UInt32(defaults.integer(forKey: Keys.code)),
            modifiers: UInt32(defaults.integer(forKey: Keys.modifiers)))
    }

    private enum Keys {
        static let enabled = "meetingHighlightHotKeyEnabled"
        static let code = "meetingHighlightHotKeyCode"
        static let modifiers = "meetingHighlightHotKeyModifiers"
    }
}

/// 「ここ重要」のグローバルショートカット。会議の記録中だけ登録する（ほかのアプリのキーを普段は奪わない）。
@MainActor
final class MeetingHighlightHotKey: ObservableObject {
    static let shared = MeetingHighlightHotKey()

    /// 登録できなかったとき（ほかのアプリと重なっているなど）の説明
    @Published private(set) var registrationError: String?

    private let hotKeys = HotKeyManager()
    private var hotKeyID: UInt32?
    private var handler: (() -> Void)?
    private var suspended = false
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        let settings = MeetingNotesSettings.shared
        settings.$highlightHotKey.removeDuplicates().dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.refresh() } }
            .store(in: &cancellables)
        settings.$highlightHotKeyEnabled.removeDuplicates().dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.refresh() } }
            .store(in: &cancellables)
    }

    /// 記録の開始時に呼ぶ
    func activate(_ handler: @escaping () -> Void) {
        self.handler = handler
        refresh()
    }

    /// 記録の停止時に呼ぶ
    func deactivate() {
        handler = nil
        refresh()
    }

    /// 設定画面でショートカットを記録している間は外す
    func suspend() {
        suspended = true
        refresh()
    }

    func resume() {
        suspended = false
        refresh()
    }

    private func refresh() {
        if let hotKeyID { hotKeys.unregister(hotKeyID) }
        hotKeyID = nil
        registrationError = nil
        let settings = MeetingNotesSettings.shared
        guard handler != nil, !suspended, settings.highlightHotKeyEnabled else { return }
        let combo = settings.highlightHotKey
        hotKeyID = hotKeys.register(combo) { [weak self] event in
            guard event == .pressed else { return }
            MainActor.assumeIsolated { self?.handler?() }
        }
        if hotKeyID == nil {
            registrationError = "ショートカット \(combo.displayString) を登録できませんでした（ほかのショートカットと重なっている可能性があります）"
            appLog.error("highlight hot key registration failed")
        }
    }
}
