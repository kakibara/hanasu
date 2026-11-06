import AppKit
import ApplicationServices
import Carbon.HIToolbox

// 要件: REQ-DIC-004
// 設計判断: DEC-DIC-013
/// クリップボード経由で、最前面アプリのカーソル位置にテキストを入力する。
@MainActor
enum TextInserter {
    enum Outcome {
        case pasted
        /// アクセシビリティ権限がないため、クリップボードへのコピーだけ行った
        case copiedOnly
        /// 入力できる場所がないと分かったので、貼り付けなかった（呼び出し元が結果を表示する）。
        /// clipboardKept は、結果をクリップボードに入れたままにしたか（設定の「入力できる場所がないとき」）
        case notPasted(clipboardKept: Bool)
        /// ⌘V を送ったが、時間内に貼り付け先がクリップボードを読まなかった（入力先がずれたなど）。
        /// clipboardKept は、結果をクリップボードに残せたか（待つ間にユーザーが別のものをコピーしたら false）
        case unconfirmed(clipboardKept: Bool)
    }

    /// ⌘V を送ってから、貼り付け先がクリップボードを読むのを待つ上限
    static let readTimeout: Duration = .milliseconds(1500)
    /// ⌘V を送ってから元のクリップボードに戻すまでの最短の間（読まれたあとも、ほかの形式を読み終えるのを待つ）
    static let minimumRestoreDelay: Duration = .milliseconds(400)

    /// クリップボード履歴アプリに記録しないよう求める印（nspasteboard.org の慣習）
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    // 要件: REQ-DIC-080, REQ-DIC-081
    // 設計判断: DEC-DIC-014, DEC-DIC-091, DEC-DIC-095
    static func insert(_ text: String) async -> Outcome {
        let pasteboard = NSPasteboard.general

        let trusted = Permissions.isAccessibilityTrusted(prompt: false)
        appLog.notice("accessibility trusted: \(trusted, privacy: .public)")
        guard trusted else {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return .copiedOnly
        }

        // 入力できる場所がないとはっきり分かったときだけ、貼り付けずに返す。分からないときは今までどおり貼り付ける
        let target = await PasteTargetProbe.check()
        appLog.notice("paste target: \(target.decision.rawValue, privacy: .public) — \(target.reason, privacy: .public) app=\(target.snapshot.bundleID ?? "-", privacy: .public)")
        guard target.decision.shouldPaste else {
            let keep = PasteFallbackSettings.shared.clipboard == .keepResult
            if keep {
                // ⌘V で貼るだけで済むよう、元に戻さずに置いておく。履歴アプリに残りにくくする印は、貼り付けのときと同じく付ける
                pasteboard.clearContents()
                pasteboard.writeObjects([transientItem(text)])
            }
            return .notPasted(clipboardKept: keep)
        }

        // 要件: REQ-DIC-083
        // 設計判断: DEC-DIC-098
        // 文字は遅延して渡す（読まれたときに provider が呼ばれる）。読まれたかで、貼り付けが届いたかを確かめる
        let saved = snapshot(of: pasteboard)
        let provider = PasteDataProvider(text: text)
        pasteboard.clearContents()
        pasteboard.writeObjects([transientItem(provider: provider)])
        let ourChangeCount = pasteboard.changeCount

        // ホットキーの修飾キーを離しきる前に ⌘V を送ると、⌥⌘V などになってしまうので少し待つ
        await waitForModifierRelease()
        sendCommandV()

        let clock = ContinuousClock()
        let sent = clock.now
        await waitForRead(provider, on: pasteboard, changeCount: ourChangeCount)
        guard pasteboard.changeCount == ourChangeCount else {
            // 待つ間にユーザーがコピーした。そのままにする
            return provider.delivered ? .pasted : .unconfirmed(clipboardKept: false)
        }
        guard provider.delivered else {
            // 貼り付け先が読まなかった。元に戻さず、結果を（遅延ではなく）そのまま置き直して、⌘V で貼れるようにする
            appLog.notice("paste not confirmed: the target did not read the clipboard")
            pasteboard.clearContents()
            pasteboard.writeObjects([transientItem(text)])
            return .unconfirmed(clipboardKept: true)
        }
        // 貼り付け先アプリがクリップボードを読み終えるのを待ってから元に戻す
        let elapsed = clock.now - sent
        if elapsed < minimumRestoreDelay {
            try? await Task.sleep(for: minimumRestoreDelay - elapsed)
        }
        if pasteboard.changeCount == ourChangeCount {
            restore(saved, to: pasteboard)
        }
        return .pasted
    }

    // 設計判断: DEC-DIC-098
    /// 貼り付け先が読むのを待つ。読まれた・時間切れ・ほかのものがコピーされた、のどれかで返る
    static func waitForRead(_ provider: PasteDataProvider, on pasteboard: NSPasteboard, changeCount: Int,
                            timeout: Duration = readTimeout) async {
        let clock = ContinuousClock()
        let start = clock.now
        while !provider.delivered, clock.now - start < timeout, pasteboard.changeCount == changeCount {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// 貼り付けが届いたか確かめられなかったときの案内（HUD に出す）
    static func unconfirmedMessage(clipboardKept: Bool, subject: String = tr("結果")) -> String {
        clipboardKept
            ? tr("貼り付け先が受け取らなかったようです。%@をクリップボードに入れたので、入力したい場所で ⌘V を押してください。", "\(subject)")
            : tr("貼り付け先が受け取らなかったようです。%@は「最近の結果」から取り出せます。", "\(subject)")
    }

    /// クリップボード履歴アプリに記録しないよう印を付けた項目
    private static func transientItem(_ text: String) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setString("", forType: transientType)
        item.setString("", forType: concealedType)
        return item
    }

    /// 文字は読まれたときに渡す項目（印は同じ）
    static func transientItem(provider: PasteDataProvider) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setDataProvider(provider, forTypes: [.string])
        item.setString("", forType: transientType)
        item.setString("", forType: concealedType)
        return item
    }

    private static func snapshot(of pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { original in
            let copy = NSPasteboardItem()
            for type in original.types {
                if let data = original.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    private static func restore(_ items: [NSPasteboardItem], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }

    private static func waitForModifierRelease() async {
        let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        for _ in 0..<40 {  // 最大 2 秒
            if NSEvent.modifierFlags.intersection(relevant).isEmpty { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private static func sendCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyCode = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

// 設計判断: DEC-DIC-098
/// 貼り付けの文字を、読まれたときに渡す。読まれたかどうか（delivered）で、貼り付け先に届いたかを見る。
/// 呼ばれるのはメインスレッド（貼り付け先からの求めはメインのランループに届く）
final class PasteDataProvider: NSObject, NSPasteboardItemDataProvider {
    let text: String
    private(set) var delivered = false

    init(text: String) {
        self.text = text
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        item.setString(text, forType: type)
        delivered = true
    }

    func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) {}
}
