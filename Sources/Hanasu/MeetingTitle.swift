import AppKit
import ApplicationServices
import Foundation

// 要件: REQ-MTG-034
// 設計判断: DEC-MTG-035
/// 会議アプリのウインドウのタイトルから、会議の名前を取り出す（Teams・Google Meet・Webex）。
/// 画面収録の許可は使わず、アクセシビリティ（音声入力の貼り付けと同じ許可）でウインドウのタイトルだけを読む。
/// 会議の名前と言い切れないとき（チャットの画面・会議コードだけのタイトルなど）は nil を返し、今までどおりの日時のタイトルにする。
enum MeetingTitle {
    static let maxLength = 100

    /// 会議の名前ではない見出し（Teams の画面名など）。小文字で比べる
    private static let generic: Set<String> = [
        "microsoft teams", "teams", "chat", "calendar", "activity", "calls", "files", "apps", "communities",
        "meet", "google meet", "webex", "home", "new meeting", "meeting", "meetings", "join", "lobby",
        "チャット", "カレンダー", "アクティビティ", "通話", "ファイル", "アプリ", "チーム",
    ]

    private static let dash = #"[-–—]"#
    private static let browserSuffix = #"\s+"# + dash + #"\s+(Google Chrome|Microsoft Edge|Arc|Safari)(\s+"# + dash + #"\s+.*)?$"#
    private static let teamsSuffix = #"\s*[|｜]\s*Microsoft Teams$"#
    private static let meetSuffix = #"\s*"# + dash + #"\s*Google Meet$"#
    private static let meetPrefix = #"^Meet\s*"# + dash + #"\s*"#
    private static let webexSuffix = #"\s*[|｜-]\s*Webex$"#
    private static let meetCode = #"^[a-z]{3}-[a-z]{4}-[a-z]{3}$"#

    /// ウインドウのタイトル 1 つから会議の名前を取り出す。会議の名前と言い切れなければ nil
    static func extract(from raw: String, app: MeetingApp) -> String? {
        var title = normalize(raw)
        if app.isBrowser { title = removing(browserSuffix, from: title) ?? title }
        let patterns: [String]
        switch app {
        case .teams: patterns = [teamsSuffix]
        case .webex: patterns = [webexSuffix]
        case .chrome, .safari, .arc, .edge: patterns = [teamsSuffix, meetSuffix, meetPrefix, webexSuffix]
        // ウインドウのタイトルに会議の名前が出ないアプリ
        case .zoom, .slack, .facetime: return nil
        }
        for pattern in patterns {
            guard let head = removing(pattern, from: title) else { continue }
            return validated(head)
        }
        return nil
    }

    /// 与えられたアプリ（優先順）のウインドウを前面から順に見て、最初に見つかった会議の名前を返す。
    /// アクセシビリティが許可されていないときは nil
    static func detect(apps: [MeetingApp]) async -> String? {
        guard !apps.isEmpty else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> String? in
            guard Permissions.isAccessibilityTrusted(prompt: false) else { return nil }
            for app in apps {
                for window in windowTitles(of: app) {
                    if let title = extract(from: window, app: app) { return title }
                }
            }
            return nil
        }.value
    }

    private static func windowTitles(of app: MeetingApp) -> [String] {
        let running = NSWorkspace.shared.runningApplications.filter { running in
            guard let id = running.bundleIdentifier?.lowercased() else { return false }
            return app.bundlePrefixes.contains { id.hasPrefix($0) }
        }
        var titles: [String] = []
        for process in running {
            let element = AXUIElementCreateApplication(process.processIdentifier)
            // 固まったアプリに引きずられないよう、待つのは短くする
            AXUIElementSetMessagingTimeout(element, 0.5)
            // 前面（フォーカス・メイン）のウインドウを先に。kAXWindowsAttribute の並びは前から順とは限らない
            var windows: [AXUIElement] = []
            for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
                var focused: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, attribute as CFString, &focused) == .success,
                   let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
                    windows.append(focused as! AXUIElement)
                }
            }
            var all: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &all) == .success,
               let list = all as? [AXUIElement] {
                windows.append(contentsOf: list)
            }
            for window in windows {
                var name: CFTypeRef?
                if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &name) == .success,
                   let name = name as? String, !name.isEmpty {
                    titles.append(name)
                }
            }
        }
        return titles
    }

    /// 改行などを空白にし、前後と重なった空白を整える
    private static func normalize(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// pattern に当たる部分を除いた文字列。当たらなければ nil
    private static func removing(_ pattern: String, from text: String) -> String? {
        guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        var result = text
        result.removeSubrange(range)
        return normalize(result)
    }

    private static func validated(_ head: String) -> String? {
        let title = normalize(head)
        guard !title.isEmpty else { return nil }
        if title.range(of: meetCode, options: [.regularExpression, .caseInsensitive]) != nil { return nil }
        let parts = title.split(whereSeparator: { $0 == "|" || $0 == "｜" }).map {
            $0.trimmingCharacters(in: .whitespaces).lowercased()
        }
        if parts.contains(where: generic.contains) { return nil }
        return String(title.prefix(maxLength))
    }
}
