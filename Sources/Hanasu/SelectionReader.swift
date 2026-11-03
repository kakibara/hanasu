import AppKit
import ApplicationServices
import Carbon.HIToolbox

// 要件: REQ-DIC-050
// 設計判断: DEC-DIC-031
/// 最前面アプリで選択中の文章を読み取る（選択を声で編集するモード用）。
/// まずアクセシビリティ API で読み、読めないアプリでは ⌘C で写し取って読む。どちらもアクセシビリティ権限が要る。
@MainActor
enum SelectionReader {
    /// アクセシビリティ API（フォーカス中の要素の kAXSelectedTextAttribute）で読む。読めない・空なら nil。
    static func readViaAccessibility(pid: pid_t?) -> String? {
        // アプリの要素から辿る方が確実なので先に試し、だめならシステム全体の要素から辿る
        var roots: [AXUIElement] = []
        if let pid { roots.append(AXUIElementCreateApplication(pid)) }
        roots.append(AXUIElementCreateSystemWide())
        for root in roots {
            // 応答しないアプリで待たされないよう、短めに切る
            AXUIElementSetMessagingTimeout(root, 0.3)
            guard let focused = copyAttribute(root, kAXFocusedUIElementAttribute),
                  CFGetTypeID(focused) == AXUIElementGetTypeID()
            else { continue }
            let element = focused as! AXUIElement
            // パスワード欄は読まない
            if copyAttribute(element, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole as String { return nil }
            if let text = copyAttribute(element, kAXSelectedTextAttribute) as? String, !text.isEmpty {
                return text
            }
        }
        return nil
    }

    /// ⌘C を送って選択を写し取り、クリップボードの元の中身を戻す。何もコピーされなければ nil。
    /// ショートカットの修飾キーを押したままだと ⌥⌘C などになってしまうので、離されるまで待ってから送る。
    static func readViaCopy() async -> String? {
        await waitForModifierRelease()
        guard !Task.isCancelled else { return nil }

        let pasteboard = NSPasteboard.general
        let saved = snapshot(of: pasteboard)
        let before = pasteboard.changeCount
        sendCommandC()

        // ⌘C を送った後は、取り消されても必ずクリップボードを戻すので、取り消しに反応しない待ち方をする
        var changed = false
        for _ in 0..<25 {  // 最大 1 秒
            await sleepIgnoringCancellation(milliseconds: 40)
            if pasteboard.changeCount != before {
                changed = true
                break
            }
        }
        guard changed else { return nil }
        // 書き込みが続いていることがあるので少し待ってから読む
        await sleepIgnoringCancellation(milliseconds: 30)
        let text = pasteboard.string(forType: .string)
        restore(saved, to: pasteboard)
        return text
    }

    private static func copyAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    // 以下の 3 つは TextInserter と同じ考え方（TextInserter は変えずに、ここに持つ）

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

    /// 押している間だけ録音するモードでは録音の終わりまで離されないので、上限を設けずに待つ（取り消されたら抜ける）
    private static func waitForModifierRelease() async {
        let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        while !NSEvent.modifierFlags.intersection(relevant).isEmpty, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(30))
        }
    }

    private static func sleepIgnoringCancellation(milliseconds: Int) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(milliseconds)) { continuation.resume() }
        }
    }

    private static func sendCommandC() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyCode = CGKeyCode(kVK_ANSI_C)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
