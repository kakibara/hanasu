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
    }

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

        let saved = snapshot(of: pasteboard)
        pasteboard.clearContents()
        pasteboard.writeObjects([transientItem(text)])
        let ourChangeCount = pasteboard.changeCount

        // ホットキーの修飾キーを離しきる前に ⌘V を送ると、⌥⌘V などになってしまうので少し待つ
        await waitForModifierRelease()
        sendCommandV()

        // 貼り付け先アプリがクリップボードを読み終えるのを待ってから元に戻す
        try? await Task.sleep(for: .milliseconds(400))
        if pasteboard.changeCount == ourChangeCount {
            restore(saved, to: pasteboard)
        }
        return .pasted
    }

    /// クリップボード履歴アプリに記録しないよう印を付けた項目
    private static func transientItem(_ text: String) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
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
