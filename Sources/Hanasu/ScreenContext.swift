import AppKit
import ApplicationServices
import os

/// 録音を始めたときの画面の文脈。Gemini に「参考情報」として渡し、固有名詞の表記・文体・話の流れを合わせる。
/// 読み取った文章はメモリ上だけに置き、ファイルやログには残さない。
struct ScreenContext: Sendable, Codable, Equatable {
    var appName: String?
    var bundleID: String?
    var windowTitle: String?
    /// フォーカスしている要素の役割（AXTextArea など）。確認用で、Gemini には送らない
    var focusedRole: String?
    /// 入力欄のカーソル（選択範囲）より前の文章
    var textBefore: String?
    /// 入力欄のカーソル（選択範囲）より後の文章。Mail の返信では、ここに引用された元のメールが入る
    var textAfter: String?
    /// カーソル位置が取れず、入力欄の文章の末尾を textBefore に入れたとき true
    var cursorUnknown: Bool?
    /// 読み取れなかった理由など。確認用で、Gemini には送らない
    var notes: [String] = []

    private enum CodingKeys: String, CodingKey {
        case appName, bundleID, windowTitle, focusedRole, textBefore, textAfter, cursorUnknown
    }

    /// Gemini に渡す材料（タイトルか入力欄の文章）があるか
    var hasContent: Bool {
        [windowTitle, textBefore, textAfter].contains { !($0 ?? "").isEmpty }
    }
}

// MARK: - プロンプト

extension ScreenContext {
    // 要件: REQ-DIC-040
    // 設計判断: DEC-DIC-065
    /// user content に入れるブロック。渡すものがなければ nil。
    /// アプリ名は従来どおり「入力先アプリ」の行で送る（オフにできる）ので、ここには入れない。
    func promptBlock() -> String? {
        guard hasContent else { return nil }
        var lines = ["<screen_context>"]
        if let windowTitle, !windowTitle.isEmpty {
            lines.append("<window_title>\(Self.escape(windowTitle))</window_title>")
        }
        if let textBefore, !textBefore.isEmpty {
            let tag = cursorUnknown == true ? "field_text" : "before_cursor"
            lines.append("<\(tag)>\n\(Self.escape(textBefore))\n</\(tag)>")
        }
        if let textAfter, !textAfter.isEmpty {
            lines.append("<after_cursor>\n\(Self.escape(textAfter))\n</after_cursor>")
        }
        lines.append("</screen_context>")
        return lines.joined(separator: "\n")
    }

    // 設計判断: DEC-DIC-065
    /// 画面の文字に含まれる "<" を全角にして、タグを閉じたり <transcript> を偽装したりできないようにする
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "<", with: "＜")
    }

    // 設計判断: DEC-DIC-065, DEC-DIC-066
    /// 文脈を渡すときに system instruction の末尾へ足す文。渡さないときは空文字。
    // 設計判断: DEC-DIC-028
    /// 和訳は出力が日本語なので、整形と同じ指示を使う
    static func instruction(for context: ScreenContext?, translation: TranslationLanguage?) -> String {
        guard context?.promptBlock() != nil else { return "" }
        return translation == .english ? translationInstruction : refineInstruction
    }

    // 要件: REQ-COM-061
    /// 文面は Resources/Prompts/<言語>.json の screen.*
    static var refineInstruction: String {
        "\n\n" + Prompts.text("screen.title") + "\n" + Prompts.text("screen.common") + "\n" + Prompts.text("screen.refine")
    }

    static var translationInstruction: String {
        "\n\n" + Prompts.text("screen.title") + "\n" + Prompts.text("screen.common") + "\n" + Prompts.text("screen.translation")
    }
}

// MARK: - 設定

// 設計判断: DEC-DIC-060
/// 画面の文脈の設定。ほかの設定と同じく UserDefaults に保存する（Settings.swift を大きく変えないよう分けている）
final class ScreenContextSettings: ObservableObject {
    static let shared = ScreenContextSettings()

    /// 既定で除外するアプリ。パスワードマネージャーなど、画面に秘密が出るアプリ
    static let defaultExcludedApps = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.apple.Passwords",
        "com.apple.keychainaccess",
        "org.keepassxc.keepassxc",
        "Dashlane",
        "Enpass",
        "LastPass",
    ]

    private let defaults = UserDefaults.standard

    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: Keys.enabled) } }
    /// 除外するアプリ（バンドル ID かアプリ名を 1 行に 1 つ）
    @Published var excludedAppsText: String { didSet { defaults.set(excludedAppsText, forKey: Keys.excludedApps) } }

    var excludedApps: [String] {
        excludedAppsText.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // 設計判断: DEC-DIC-063
    func isExcluded(bundleID: String?, appName: String?) -> Bool {
        let candidates = [bundleID, appName].compactMap { $0?.lowercased() }
        return excludedApps.contains { candidates.contains($0.lowercased()) }
    }

    private init() {
        defaults.register(defaults: [
            Keys.enabled: false,
            Keys.excludedApps: Self.defaultExcludedApps.joined(separator: "\n"),
        ])
        enabled = defaults.bool(forKey: Keys.enabled)
        excludedAppsText = defaults.string(forKey: Keys.excludedApps)!
    }

    private enum Keys {
        static let enabled = "screenContextEnabled"
        static let excludedApps = "screenContextExcludedApps"
    }
}

// MARK: - 読み取り（Accessibility API）

// 要件: REQ-DIC-040
enum ScreenContextReader {
    /// カーソルの前後それぞれで読む文字数
    static let maxChars = 500
    /// AX の 1 回の呼び出しで待つ秒数。応答しないアプリで固まらないようにする
    static let messagingTimeout: Float = 0.2

    struct Target: Sendable {
        var pid: pid_t
        var appName: String?
        var bundleID: String?
    }

    @MainActor
    static func frontmostTarget() -> Target? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return Target(pid: app.processIdentifier, appName: app.localizedName, bundleID: app.bundleIdentifier)
    }

    // 設計判断: DEC-DIC-061, DEC-DIC-062, DEC-DIC-063, DEC-DIC-067
    /// 前面アプリの文脈を読む。AX を同期で呼ぶので、メインスレッド以外から呼ぶ。
    static func read(_ target: Target, maxChars: Int = maxChars) -> ScreenContext {
        var context = ScreenContext(appName: target.appName, bundleID: target.bundleID)
        guard AXIsProcessTrusted() else {
            context.notes.append("アクセシビリティの許可がないため、ウインドウと入力欄を読めません")
            return context
        }
        let app = AXUIElementCreateApplication(target.pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)

        if let window = element(app, kAXFocusedWindowAttribute) {
            AXUIElementSetMessagingTimeout(window, messagingTimeout)
            context.windowTitle = string(window, kAXTitleAttribute).map { String($0.prefix(200)) }
        }

        var focused = element(app, kAXFocusedUIElementAttribute)
        if focused == nil || !isTextElement(focused!) {
            // Electron 製のアプリ（Slack・VS Code など）は、支援技術から頼まれるまで中身を公開しない。
            // Electron が用意している AXManualAccessibility を立てて、もう一度だけ読む
            if AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue) == .success {
                focused = element(app, kAXFocusedUIElementAttribute) ?? focused
            }
        }
        guard let focused else {
            context.notes.append("フォーカスしている要素を取れませんでした")
            return context
        }
        AXUIElementSetMessagingTimeout(focused, messagingTimeout)

        let role = string(focused, kAXRoleAttribute)
        let subrole = string(focused, kAXSubroleAttribute)
        context.focusedRole = [role, subrole].compactMap { $0 }.joined(separator: "/")
        // パスワード欄は中身を読まない
        if role == "AXSecureTextField" || subrole == (kAXSecureTextFieldSubrole as String) {
            context.notes.append("パスワード欄なので入力欄の文章は読みません")
            return context
        }

        readText(of: focused, into: &context, maxChars: maxChars)
        if context.textBefore == nil, context.textAfter == nil {
            context.notes.append("入力欄の文章を取れませんでした（\(context.focusedRole ?? "役割不明")）")
        }
        return context
    }

    private static func readText(of element: AXUIElement, into context: inout ScreenContext, maxChars: Int) {
        guard let selection = range(element, kAXSelectedTextRangeAttribute) else {
            // カーソル位置が取れない入力欄は、文章の末尾だけを使う
            if let value = string(element, kAXValueAttribute), !value.isEmpty {
                context.textBefore = clean(String(value.suffix(maxChars)))
                context.cursorUnknown = true
            }
            return
        }
        let total = int(element, kAXNumberOfCharactersAttribute)
        let beforeStart = max(0, selection.location - maxChars)
        let beforeRange = CFRange(location: beforeStart, length: selection.location - beforeStart)
        let afterStart = selection.location + selection.length
        let afterLength = total.map { max(0, min(maxChars, $0 - afterStart)) } ?? maxChars
        let afterRange = CFRange(location: afterStart, length: afterLength)

        // まず範囲を指定して読む（長い文書でも全文を受け取らずに済む）。だめなら全文から切り出す
        var before = beforeRange.length > 0 ? string(element, forRange: beforeRange) : ""
        var after = afterRange.length > 0 ? string(element, forRange: afterRange) : ""
        if before == nil || after == nil, let value = string(element, kAXValueAttribute) {
            let ns = value as NSString
            before = before ?? substring(ns, beforeRange)
            after = after ?? substring(ns, afterRange)
        }
        context.textBefore = before.flatMap(clean)
        context.textAfter = after.flatMap(clean)
    }

    /// 空白だけなら nil。AX が返すオブジェクト置換文字（画像など）は除く
    private static func clean(_ text: String) -> String? {
        let cleaned = text.replacingOccurrences(of: "\u{FFFC}", with: "")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : cleaned
    }

    private static func substring(_ ns: NSString, _ range: CFRange) -> String? {
        let start = min(max(0, range.location), ns.length)
        let end = min(start + max(0, range.length), ns.length)
        guard end > start else { return nil }
        // サロゲートペアや結合文字の途中で切らない
        let safe = ns.rangeOfComposedCharacterSequences(for: NSRange(location: start, length: end - start))
        return ns.substring(with: safe)
    }

    private static func isTextElement(_ element: AXUIElement) -> Bool {
        range(element, kAXSelectedTextRangeAttribute) != nil || string(element, kAXValueAttribute) != nil
    }

    // MARK: AX の小さな補助

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copy(element, attribute) as? String
    }

    private static func int(_ element: AXUIElement, _ attribute: String) -> Int? {
        (copy(element, attribute) as? NSNumber)?.intValue
    }

    private static func range(_ element: AXUIElement, _ attribute: String) -> CFRange? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range
    }

    private static func string(_ element: AXUIElement, forRange range: CFRange) -> String? {
        var range = range
        guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXStringForRangeParameterizedAttribute as CFString, parameter, &value) == .success
        else { return nil }
        return value as? String
    }
}

// MARK: - 録音中の非同期の読み取り

// 要件: REQ-DIC-040
// 設計判断: DEC-DIC-064
/// 録音の開始と並行して文脈を読み、止めたときに結果を受け取る。
/// 読み取りは別スレッドで行うので、録音の開始は待たせない。
final class ScreenContextCapture: Sendable {
    private let state = OSAllocatedUnfairLock<ScreenContext??>(initialState: nil)

    /// 設定がオンで、前面アプリが除外されていなければ読み取りを始める
    @MainActor
    static func begin(settings: ScreenContextSettings = .shared) -> ScreenContextCapture? {
        guard settings.enabled, let target = ScreenContextReader.frontmostTarget() else { return nil }
        // 自分自身（設定画面など）と除外アプリは読まない
        if target.pid == ProcessInfo.processInfo.processIdentifier
            || settings.isExcluded(bundleID: target.bundleID, appName: target.appName)
        {
            return nil
        }
        let capture = ScreenContextCapture()
        Task.detached(priority: .userInitiated) {
            let started = Date()
            let context = ScreenContextReader.read(target)
            capture.state.withLock { $0 = .some(context) }
            appLog.notice("screen context: title=\(context.windowTitle?.count ?? 0, privacy: .public) before=\(context.textBefore?.count ?? 0, privacy: .public) after=\(context.textAfter?.count ?? 0, privacy: .public) chars, role=\(context.focusedRole ?? "-", privacy: .public), \(Date().timeIntervalSince(started), format: .fixed(precision: 2), privacy: .public)s")
        }
        return capture
    }

    /// 読み終わっていれば結果を返す。まだなら少しだけ待ち、間に合わなければ文脈なしで進める
    func result(waitingUpTo timeout: Duration = .milliseconds(300)) async -> ScreenContext? {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while true {
            if let done = state.withLock({ $0 }) { return done }
            if ContinuousClock.now >= deadline {
                appLog.notice("screen context: timed out")
                return nil
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}
