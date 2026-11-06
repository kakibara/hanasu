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

    // 設計判断: DEC-MTG-044
    static func text(from notes: [MeetingNote]) -> String {
        notes.map(\.line).joined(separator: "\n")
    }

    // 設計判断: DEC-MTG-044
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

    // 設計判断: DEC-MTG-043
    /// notes.md の中身
    func notesMarkdown() -> String {
        tr("# %@ — メモ\n\n%@\n", "\(title)", "\(notesText)")
    }

    // 要件: REQ-MTG-012
    // 設計判断: DEC-MTG-047
    /// 記録中に「ここ重要」の印を取り消せる時間（秒）。押し間違いのやり直しのため。それより古い印は記録のあとに「メモ」タブで消す
    static let highlightUndoSeconds: Double = 10

    /// 今取り消せる印（付けてから 10 秒以内のうち、いちばん新しいもの）。elapsed は録音開始からの秒数
    func undoableHighlight(at elapsed: Double) -> MeetingNote? {
        highlights
            .filter { h in h.time.map { elapsed - $0 >= 0 && elapsed - $0 <= Self.highlightUndoSeconds } ?? false }
            .max { ($0.time ?? 0) < ($1.time ?? 0) }
    }

    /// 「ここ重要」の印の前後で、強調する範囲（印を押すのは大事な発言を聞いた後なので、前を長めにとる）
    static let highlightLeadTime: Double = 30
    static let highlightTrailTime: Double = 15

    // 要件: REQ-MTG-012
    // 設計判断: DEC-MTG-041, DEC-MTG-049
    /// 「ここ重要」の印ごとの、前後の発言（議事録で重要として扱うのと同じ 30 秒前〜15 秒後）。時刻の順
    func highlightContexts() -> [(note: MeetingNote, blocks: [Utterance])] {
        let blocks = mergedBlocks()
        return highlights.compactMap { h -> (note: MeetingNote, blocks: [Utterance])? in
            guard let t = h.time else { return nil }
            let near = blocks.filter { $0.start <= t + Self.highlightTrailTime && t - Self.highlightLeadTime <= $0.end }
            return (h, near)
        }
        .sorted { ($0.note.time ?? 0) < ($1.note.time ?? 0) }
    }

    // 設計判断: DEC-MTG-041
    /// 発言が「ここ重要」の印の前後に入るか
    func isNearHighlight(_ block: Utterance) -> Bool {
        highlights.contains { h in
            guard let t = h.time else { return false }
            return block.start <= t + Self.highlightTrailTime && t - Self.highlightLeadTime <= block.end
        }
    }

    // 要件: REQ-MTG-013
    /// Gemini に渡す文字起こし。印の前後の発言の行頭に ★ を付ける。
    func transcriptForPromptMarkingHighlights() -> String {
        let language = PromptLanguage.current
        return mergedBlocks()
            .map { "\(isNearHighlight($0) ? "★ " : "")[\(Self.clock($0.start))] \(promptName(for: $0.speaker, language: language)): \($0.text)" }
            .joined(separator: "\n")
    }

    // 要件: REQ-MTG-013
    // 設計判断: DEC-MTG-045
    /// Gemini に渡すメモ（なければ nil）。時刻のないメモは [--:--] にする。
    func notesForPrompt() -> String? {
        let notes = allNotes
        guard !notes.isEmpty else { return nil }
        return notes.map { note in
            let time = note.time.map { "[\(Self.clock($0))]" } ?? "[--:--]"
            switch note.kind {
            case .note: return "\(time) \(note.text)"
            case .highlight: return "\(time) \(Prompts.text("minutes.notes.highlight"))\(note.text.isEmpty ? "" : ": \(note.text)")"
            }
        }
        .joined(separator: "\n")
    }
}

extension MeetingProcessor {
    /// メモか印がある会議だけ、議事録の指示に足す
    // 要件: REQ-COM-061
    static var notesInstruction: String { Prompts.text("minutes.notes") }
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

// 要件: REQ-MTG-012
// 設計判断: DEC-MTG-042
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
            registrationError = tr("ショートカット %@ を登録できませんでした（ほかのショートカットと重なっている可能性があります）", "\(combo.displayString)")
            appLog.error("highlight hot key registration failed")
        }
    }
}
