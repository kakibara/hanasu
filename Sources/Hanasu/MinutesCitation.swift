import Foundation

// 要件: REQ-MTG-052
// 設計判断: DEC-MTG-134
/// 議事録の要点の行末に AI が付ける、根拠の発言の時刻の印（`[12:34]`・`[1:02:34]`、全角の［］も）。
/// 会議ノートでは押すと文字起こしのその発言へ移り、書き出しでは取り除く。Windows 版の MinutesCitation.cs と同じ決まり（両方を直す）
enum MinutesCitation {
    /// 印の形。Markdown のリンク（`[12:34](…)`）は印として扱わない（AI チャットの時刻のリンクと同じ規則。DEC-MTG-084）
    static let pattern = "[\\[［](\\d{1,2}:\\d{2}(?::\\d{2})?)[\\]］](?!\\()"
    /// 取り除くときは、前の空白ごと消す
    private static let stripPattern = "[ \\t\u{3000}]*" + pattern

    private static let regex = try! NSRegularExpression(pattern: pattern)
    private static let stripRegex = try! NSRegularExpression(pattern: stripPattern)

    /// 行の中の印（見た目の文字と秒数）
    struct Mark: Equatable {
        var label: String
        var seconds: Double
        /// 行の中の位置（印のかっこを含む）
        var range: Range<String.Index>
    }

    /// 行の中の印を、前から順に取り出す
    static func marks(in text: String) -> [Mark] {
        regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let whole = Range(match.range, in: text), let clock = Range(match.range(at: 1), in: text),
                  let seconds = MeetingNote.parseClock(text[clock]) else { return nil }
            return Mark(label: String(text[clock]), seconds: seconds, range: whole)
        }
    }

    /// 印を取り除いた文（書き出し・リマインダー・アクションアイテムの読み取り用）。各行の末尾の空白も整える
    static func strip(_ text: String) -> String {
        let stripped = stripRegex.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        guard stripped != text else { return text }
        return stripped.components(separatedBy: "\n")
            .map { line in
                var line = line
                while line.last == " " || line.last == "\t" { line.removeLast() }
                return line
            }
            .joined(separator: "\n")
    }

    /// 印が有効か（押せるか）。会議の長さを 1 秒より多く超える時刻は、作り話の時刻として無効にする
    static func isValid(_ seconds: Double, duration: Double) -> Bool {
        seconds >= 0 && seconds <= duration + 1
    }

    /// アクションアイテムの `at`（"12:34"）の秒数
    static func seconds(of label: String?) -> Double? {
        guard let label = label?.trimmingCharacters(in: .whitespaces), !label.isEmpty else { return nil }
        let inner = label.trimmingCharacters(in: CharacterSet(charactersIn: "[]［］"))
        return MeetingNote.parseClock(Substring(inner))
    }

    /// 議事録の結果から印を取り除く（要点にまとめて作ったとき。DEC-COM-065）
    static func stripped(_ result: MinutesResult) -> MinutesResult {
        var result = result
        result.markdown = strip(result.markdown)
        result.actionItems = result.actionItems.map { item in
            var item = item
            item.at = nil
            return item
        }
        return result
    }
}

// 要件: REQ-MTG-052
// 設計判断: DEC-COM-065, DEC-MTG-134
/// 長い入力を縮めて送ったか（LongInputFitter が書く）。議事録を作る間だけ TaskLocal で渡し、
/// 文字起こしを要点にまとめた（根拠の時刻がなくなった）ときは、議事録から時刻の印を取り除く
final class LongInputReport: @unchecked Sendable {
    private let lock = NSLock()
    private var _shortened = false

    var shortened: Bool {
        lock.lock(); defer { lock.unlock() }
        return _shortened
    }

    func markShortened() {
        lock.lock(); _shortened = true; lock.unlock()
    }

    @TaskLocal static var current: LongInputReport?
}
