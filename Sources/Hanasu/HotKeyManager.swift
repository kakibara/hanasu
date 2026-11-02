import Carbon.HIToolbox
import Foundation

/// Carbon の RegisterEventHotKey でグローバルショートカットを扱う。
/// アクセシビリティ権限なしで、押下と解放の両方を受け取れる。
final class HotKeyManager {
    enum Event { case pressed, released }

    private struct Registration {
        let ref: EventHotKeyRef
        let handler: (Event) -> Void
    }

    private static let signature: OSType = 0x484E_5355  // 'HNSU'
    private var registrations: [UInt32: Registration] = [:]
    /// ID はインスタンスをまたいで重ならないようにする（ハンドラはどのインスタンスにも届き、ID で見分けるため）
    private static var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    init() {
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            return manager.handle(event)
        }, types.count, &types, selfPtr, &eventHandler)
    }

    deinit {
        for id in registrations.keys { unregister(id) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    /// 登録に成功すれば ID を返す。他のアプリと衝突している場合などは nil。
    @discardableResult
    func register(_ combo: HotKeyCombo, handler: @escaping (Event) -> Void) -> UInt32? {
        let id = Self.nextID
        Self.nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode, combo.modifiers,
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return nil }
        registrations[id] = Registration(ref: ref, handler: handler)
        return id
    }

    func unregister(_ id: UInt32) {
        guard let reg = registrations.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(reg.ref)
    }

    private func handle(_ event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
            nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
        guard status == noErr, hotKeyID.signature == Self.signature,
              let reg = registrations[hotKeyID.id]
        else { return OSStatus(eventNotHandledErr) }
        let kind: Event = GetEventKind(event) == UInt32(kEventHotKeyPressed) ? .pressed : .released
        reg.handler(kind)
        return noErr
    }
}
