import AppKit
import ApplicationServices

// MARK: - 判定（純粋な関数）

/// 貼り付けの直前に読んだ、キーボードのフォーカスの様子。AX で読んだ値だけを持ち、判定は PasteTargetJudge が行う
struct PasteFocusSnapshot: Equatable, Sendable {
    /// AX の問い合わせの結果。「ない」と答えた（kAXErrorNoValue）のと、答えが返らなかった（タイムアウトなど）を分ける
    enum Read: String, Equatable, Sendable {
        case found
        case none
        case failed
    }

    /// フォーカスのあるアプリが分かったか
    var hasApp = true
    var bundleID: String?
    /// Electron 製のアプリ（Slack・VS Code など）か。アプリの中に Electron Framework があるかで見る
    var isElectron = false
    /// フォーカスのあるウインドウ（kAXFocusedWindow）
    var window: Read = .found
    /// フォーカスのある要素（kAXFocusedUIElement）
    var element: Read = .found
    var role: String?
    var subrole: String?
    /// AXValue を書き換えられるか（AXUIElementIsAttributeSettable）
    var valueSettable = false
    /// 選択範囲（カーソル位置）を持つか（kAXSelectedTextRange）
    var hasSelectedTextRange = false
    /// Web の編集できる領域の中か（WebKit・Chromium の AXEditableAncestor）
    var hasEditableAncestor = false
}

enum PasteTargetDecision: String, Sendable {
    /// 入力欄にフォーカスがある。貼り付ける
    case paste
    /// 入力できる場所がないとはっきり分かった。貼り付けずに結果を表示する
    case show
    /// 分からない。今までどおり貼り付ける
    case unknown

    var shouldPaste: Bool { self != .show }
}

// 要件: REQ-DIC-080
// 設計判断: DEC-DIC-091, DEC-DIC-092, DEC-DIC-097
/// フォーカスの様子から、貼り付けるか・結果を表示するかを決める。
/// 誤って表示に回すより貼り付けを試す方を優先し、「入力できる場所がない」とはっきり分かるときだけ .show にする。
enum PasteTargetJudge {
    static let finderBundleID = "com.apple.finder"

    /// 文字を入れる欄の役割
    static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
    static let textSubroles: Set<String> = ["AXSearchField", "AXSecureTextField"]

    /// 値が文字ではない部品。AXValue を書き換えられても（スライダー・チェックボックスなど）入力欄とはみなさない
    static let controlRoles: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXDisclosureTriangle",
        "AXSlider", "AXIncrementor", "AXScrollBar", "AXSplitter", "AXColorWell", "AXLevelIndicator",
        "AXProgressIndicator", "AXValueIndicator",
    ]

    /// フォーカスがあっても、貼り付けても何も入らないとはっきりしている役割。
    /// 一覧・表（AXList・AXTable・AXOutline）は入れない。Excel・Numbers の表や Keynote の画面は、選んだまま ⌘V で貼れるため
    static let nonTextRoles: Set<String> = controlRoles.union([
        "AXImage", "AXLink", "AXStaticText", "AXWebArea", "AXMenuBar", "AXMenuBarItem", "AXTabGroup", "AXToolbar",
    ])

    // 設計判断: DEC-DIC-097
    /// AXWebArea（Web ページの入力欄の外）にフォーカスがあると言い切れるアプリ。Web の中身の AX をいつも出す Safari だけ
    static let webAreaTrustedBundleIDs: Set<String> = ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]

    static func decide(_ s: PasteFocusSnapshot) -> (decision: PasteTargetDecision, reason: String) {
        guard s.hasApp else { return (.unknown, "フォーカスのあるアプリが分からない") }
        let isFinder = s.bundleID == finderBundleID

        switch s.element {
        case .failed:
            return (.unknown, "フォーカスのある要素を読めなかった")
        case .none:
            if isFinder { return (.show, "Finder（デスクトップ）にフォーカスがある") }
            if s.window == .none { return (.show, "前面のアプリにウインドウがない") }
            // ウインドウはあるのに要素がない: 自前で描くアプリ（ターミナルなど）や、AX を出していない Electron がありうる
            return (.unknown, s.window == .found ? "ウインドウはあるが、フォーカスのある要素がない" : "ウインドウがあるか分からず、フォーカスのある要素もない")
        case .found:
            break
        }

        let role = s.role ?? ""
        if textRoles.contains(role) || textSubroles.contains(s.subrole ?? "") {
            return (.paste, "入力欄（\(describe(s))）")
        }
        if s.hasEditableAncestor {
            return (.paste, "Web の編集できる領域（\(describe(s))）")
        }
        if !controlRoles.contains(role), s.valueSettable || s.hasSelectedTextRange {
            return (.paste, "文字を持つ要素（\(describe(s))）")
        }
        // Electron は AX の出しかたがアプリごとにまちまちで、何も選んでいなくても ⌘V を入力欄へ回すアプリもある
        if s.isElectron { return (.unknown, "Electron 製のアプリ（\(describe(s))）") }
        // Chromium（Chrome・Edge・Arc など）は支援技術に頼まれるまで Web の中身を出さないので、入力欄にフォーカスがあっても
        // AXWebArea が返り続けることがある。Safari のほかでは、AXWebArea だけでは入力欄の外と決めない
        if role == "AXWebArea", !webAreaTrustedBundleIDs.contains(s.bundleID ?? "") {
            return (.unknown, "Safari のほかの Web の領域（\(describe(s))）")
        }
        if isFinder { return (.show, "Finder のファイルの一覧など（\(describe(s))）") }
        if nonTextRoles.contains(role) { return (.show, "文字を入れられない要素（\(describe(s))）") }
        return (.unknown, "入力欄かどうか分からない要素（\(describe(s))）")
    }

    private static func describe(_ s: PasteFocusSnapshot) -> String {
        [s.role, s.subrole].compactMap { $0 }.joined(separator: "/").nonEmpty ?? "役割不明"
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

// MARK: - 読み取り（Accessibility API）

// 要件: REQ-DIC-080
// 設計判断: DEC-DIC-091, DEC-DIC-093
enum PasteTargetProbe {
    /// AX の 1 回の呼び出しで待つ秒数。応答しないアプリで固まらないようにする（画面の文脈と同じ）
    static let messagingTimeout: Float = 0.2
    /// 「表示する」と出たときに読み直すまでの間。Chromium は支援技術に聞かれてから AX の木を作るので、最初の 1 回は入力欄が見えないことがある
    static let recheckDelay: Duration = .milliseconds(150)

    struct Result: Sendable {
        var snapshot: PasteFocusSnapshot
        var decision: PasteTargetDecision
        var reason: String
    }

    /// 今のフォーカスで判定する。「表示する」と出たら少し待って読み直し、2 回とも同じときだけ表示に回す
    @MainActor
    static func check() async -> Result {
        let first = await read()
        guard first.decision == .show else { return first }
        try? await Task.sleep(for: recheckDelay)
        return await read()
    }

    @MainActor
    static func read() async -> Result {
        let fallbackPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let (pid, partial) = await Task.detached(priority: .userInitiated) {
            readFocus(fallbackPID: fallbackPID)
        }.value
        var snapshot = partial
        if let pid, let app = NSRunningApplication(processIdentifier: pid) {
            snapshot.bundleID = app.bundleIdentifier
            snapshot.isElectron = isElectron(app.bundleURL)
        }
        let (decision, reason) = PasteTargetJudge.decide(snapshot)
        return Result(snapshot: snapshot, decision: decision, reason: reason)
    }

    static func isElectron(_ bundleURL: URL?) -> Bool {
        guard let bundleURL else { return false }
        let framework = bundleURL.appendingPathComponent("Contents/Frameworks/Electron Framework.framework")
        return FileManager.default.fileExists(atPath: framework.path)
    }

    /// AX でフォーカスを読む（同期で呼ぶので、メインスレッド以外から呼ぶ）。
    /// キーボードのフォーカスは、前面のアプリではなく Spotlight などの別のプロセスのパネルにあることがあるので、
    /// まずシステム全体のフォーカスのあるアプリを聞き、取れなければ前面のアプリを使う
    static func readFocus(fallbackPID: pid_t?) -> (pid_t?, PasteFocusSnapshot) {
        var snapshot = PasteFocusSnapshot()
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, messagingTimeout)
        var app: AXUIElement?
        if case .found(let element) = copyElement(systemWide, kAXFocusedApplicationAttribute) {
            app = element
        } else if let fallbackPID {
            app = AXUIElementCreateApplication(fallbackPID)
        }
        guard let app else {
            snapshot.hasApp = false
            return (nil, snapshot)
        }
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        var pid: pid_t = 0
        let appPID: pid_t? = AXUIElementGetPid(app, &pid) == .success ? pid : fallbackPID

        snapshot.window = copyElement(app, kAXFocusedWindowAttribute).read
        let focused = copyElement(app, kAXFocusedUIElementAttribute)
        snapshot.element = focused.read
        guard case .found(let element) = focused else { return (appPID, snapshot) }
        AXUIElementSetMessagingTimeout(element, messagingTimeout)

        snapshot.role = copy(element, kAXRoleAttribute) as? String
        snapshot.subrole = copy(element, kAXSubroleAttribute) as? String
        var settable: DarwinBoolean = false
        snapshot.valueSettable = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success
            && settable.boolValue
        snapshot.hasSelectedTextRange = copy(element, kAXSelectedTextRangeAttribute) != nil
        snapshot.hasEditableAncestor = copy(element, "AXEditableAncestor") != nil
        return (appPID, snapshot)
    }

    // MARK: AX の小さな補助

    private enum ElementRead {
        case found(AXUIElement)
        case none
        case failed

        var read: PasteFocusSnapshot.Read {
            switch self {
            case .found: .found
            case .none: .none
            case .failed: .failed
            }
        }
    }

    private static func copyElement(_ element: AXUIElement, _ attribute: String) -> ElementRead {
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(element, attribute as CFString, &value) {
        case .success:
            guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return .none }
            return .found(value as! AXUIElement)
        case .noValue:
            return .none
        default:
            return .failed
        }
    }

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }
}

// MARK: - 設定

// 要件: REQ-DIC-081
// 設計判断: DEC-DIC-095
/// 入力できる場所がないとき、クリップボードをどうするか
enum PasteFallbackClipboard: String, CaseIterable, Identifiable {
    /// 結果をクリップボードに入れたままにする（⌘V で貼るだけで済む）
    case keepResult
    /// クリップボードは元のまま。表示からコピーする
    case restore

    var id: String { rawValue }
    var label: String {
        switch self {
        case .keepResult: "クリップボードにも入れておく（⌘V で貼り付けるだけで済む）"
        case .restore: "表示だけにする（クリップボードは元のまま。表示からコピーする）"
        }
    }
}

/// 入力できる場所がないときの設定。ほかの機能の設定（AppSettings）とは分けて持つ（DEC-COM-013）
final class PasteFallbackSettings: ObservableObject {
    static let shared = PasteFallbackSettings()

    private let defaults = UserDefaults.standard

    @Published var clipboard: PasteFallbackClipboard {
        didSet { defaults.set(clipboard.rawValue, forKey: Keys.clipboard) }
    }

    // 要件: REQ-DIC-084
    // 設計判断: DEC-DIC-099
    /// 貼り付けが届いたか確かめられなかったとき、音声入力の履歴を開く（既定はオフ）
    @Published var openHistoryWhenUnconfirmed: Bool {
        didSet { defaults.set(openHistoryWhenUnconfirmed, forKey: Keys.openHistoryWhenUnconfirmed) }
    }

    private init() {
        defaults.register(defaults: [
            Keys.clipboard: PasteFallbackClipboard.keepResult.rawValue,
            Keys.openHistoryWhenUnconfirmed: false,
        ])
        clipboard = PasteFallbackClipboard(rawValue: defaults.string(forKey: Keys.clipboard) ?? "") ?? .keepResult
        openHistoryWhenUnconfirmed = defaults.bool(forKey: Keys.openHistoryWhenUnconfirmed)
    }

    private enum Keys {
        static let clipboard = "pasteFallbackClipboard"
        static let openHistoryWhenUnconfirmed = "pasteUnconfirmedOpenHistory"
    }
}
