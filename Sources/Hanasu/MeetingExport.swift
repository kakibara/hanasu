import AppKit
import UniformTypeIdentifiers

// 要件: REQ-MTG-019
/// 会議ノートの書き出し（Markdown・Slack 向け・テキスト）。
enum MeetingExport {
    enum FileFormat: String, CaseIterable {
        case markdown = "md"
        case text = "txt"

        var title: String { self == .markdown ? "Markdown" : tr("テキスト") }
    }

    // MARK: - Slack 向け（mrkdwn）

    // 設計判断: DEC-MTG-065
    /// Slack に貼る要約。議事録を mrkdwn に直し、見出しの「話者についてのメモ」（推測の内部メモ）は除く。
    /// 貼り付けて送る前提なので、`&` `<` `>` のエスケープ（API 用）はしない。
    static func slack(_ meeting: Meeting) -> String? {
        guard let minutes = meeting.minutes else { return nil }
        var lines = ["*\(meeting.title)*",
                     tr("%@・%@", Meeting.dateFormatter.string(from: meeting.startedAt), Meeting.clock(meeting.duration))]
        lines.append(contentsOf: slackBody(fromMarkdown: minutes))
        // 空行の連続をまとめる
        var result: [String] = []
        for line in lines where !(line.isEmpty && (result.last?.isEmpty ?? true)) { result.append(line) }
        return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func slackBody(fromMarkdown markdown: String) -> [String] {
        var lines: [String] = []
        var skipping = false
        for raw in markdown.components(separatedBy: "\n") {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") { continue }  // タイトル（上で書いた）
            if trimmed.hasPrefix("## ") {
                // 要件: REQ-COM-061（議事録はそのときのプロンプトの言語なので、どの言語の見出しでも外す）
                skipping = Prompts.allTexts("minutes.speakerNotesHeading").contains { trimmed.contains($0) }
                if skipping { continue }
                lines.append("")
                lines.append("*\(stripInline(String(trimmed.dropFirst(3))))*")
                continue
            }
            if skipping { continue }
            if trimmed.hasPrefix("### ") {
                lines.append("*\(stripInline(String(trimmed.dropFirst(4))))*")
                continue
            }
            let level = raw.prefix { $0 == " " }.count / 2
            let indent = String(repeating: "    ", count: level)
            if let (mark, rest) = listItem(trimmed) {
                let bullet: String
                switch mark {
                case .unchecked: bullet = "☐"
                case .checked: bullet = "☑"
                case .bullet: bullet = level == 0 ? "•" : "◦"
                }
                lines.append("\(indent)\(bullet) \(slackInline(rest))")
            } else {
                lines.append(slackInline(trimmed))
            }
        }
        return lines
    }

    /// 斜体 `*x*`（太字の `**` は先に置き換えておく）
    private static let italicPattern = #"(?<!\*)\*(?![\s\*])(.+?)(?<![\s\*])\*(?!\*)"#

    // 設計判断: DEC-MTG-065
    /// 行内の Markdown を mrkdwn に直す。太字 `**x**` → `*x*`、リンク `[t](u)` → `<u|t>`、斜体は記号を外す。
    /// Slack の太字は前後が空白でないと効かないので、日本語の文中では前後に空白を入れる。
    static func slackInline(_ text: String) -> String {
        var s = replace(text, pattern: #"\[([^\]]+)\]\((https?://[^)\s]+)\)"#, with: "<$2|$1>")
        s = replace(s, pattern: #"\*\*(.+?)\*\*|__(.+?)__"#, with: "\u{1}$1$2\u{1}")
        // 斜体は日本語の文中では効かず読みにくいので、記号を外すだけにする
        s = replace(s, pattern: italicPattern, with: "$1")
        // 開きの印の前・閉じの印の後に空白を入れる
        var out = ""
        var open = true
        let chars = Array(s)
        for (i, c) in chars.enumerated() {
            if c == "\u{1}" {
                if open, let prev = out.last, !prev.isWhitespace { out.append(" ") }
                out.append("*")
                if !open, i + 1 < chars.count, !chars[i + 1].isWhitespace, !chars[i + 1].isPunctuation { out.append(" ") }
                open.toggle()
            } else {
                out.append(c)
            }
        }
        return out
    }

    // MARK: - テキスト

    // 設計判断: DEC-MTG-066
    /// Markdown の記号を外した読みやすいテキスト（メールや社内システムに貼る用）
    static func plainText(fromMarkdown markdown: String) -> String {
        var lines: [String] = []
        for raw in markdown.components(separatedBy: "\n") {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            let level = raw.prefix { $0 == " " }.count / 2
            let indent = String(repeating: "  ", count: level)
            if trimmed.hasPrefix("# ") {
                let title = stripInline(String(trimmed.dropFirst(2)))
                lines.append(title)
                lines.append(String(repeating: "=", count: min(40, title.count * 2)))
            } else if trimmed.hasPrefix("## ") {
                lines.append(tr("【%@】", stripInline(String(trimmed.dropFirst(3)))))
            } else if trimmed.hasPrefix("### ") {
                lines.append("■ \(stripInline(String(trimmed.dropFirst(4))))")
            } else if let (mark, rest) = listItem(trimmed) {
                let bullet = switch mark {
                case .unchecked: "□"
                case .checked: "☑"
                case .bullet: tr("・")
                }
                lines.append("\(indent)\(bullet)\(bullet == "・" ? "" : " ")\(stripInline(rest))")
            } else {
                lines.append(stripInline(trimmed))
            }
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    /// 太字・斜体・コード・リンクの記号を外す
    static func stripInline(_ text: String) -> String {
        var s = replace(text, pattern: #"\[([^\]]+)\]\(([^)\s]+)\)"#, with: "$1 ($2)")
        s = replace(s, pattern: #"\*\*(.+?)\*\*|__(.+?)__"#, with: "$1$2")
        s = replace(s, pattern: italicPattern, with: "$1")
        s = replace(s, pattern: #"`([^`]+)`"#, with: "$1")
        return s
    }

    // MARK: - ファイルに保存

    static func suggestedFileName(for meeting: Meeting, transcript: Bool, format: FileFormat) -> String {
        let base = meeting.title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return "\(base) \(transcript ? tr("文字起こし") : tr("議事録")).\(format.rawValue)"
    }

    static func fileContents(_ markdown: String, format: FileFormat) -> String {
        format == .markdown ? markdown : plainText(fromMarkdown: markdown)
    }

    /// 保存先を聞いて書き出す
    @MainActor
    static func save(_ markdown: String, suggestedName: String, format: FileFormat) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [UTType(filenameExtension: format.rawValue) ?? .plainText]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try fileContents(markdown, format: format).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    // MARK: - Private

    private enum ListMark { case unchecked, checked, bullet }

    private static func listItem(_ trimmed: String) -> (ListMark, String)? {
        if trimmed.hasPrefix("- [ ] ") { return (.unchecked, String(trimmed.dropFirst(6))) }
        if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") { return (.checked, String(trimmed.dropFirst(6))) }
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") { return (.bullet, String(trimmed.dropFirst(2))) }
        return nil
    }

    private static func replace(_ text: String, pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }
}
