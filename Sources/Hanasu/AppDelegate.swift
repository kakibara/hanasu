import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var controller: DictationController!
    private var historyUI: DictationHistoryUI!
    private var editController: EditModeController!
    private var settingsWindow: NSWindow?
    private var meetingWindow: NSWindow?
    private let meetingRecorder: MeetingRecorder = {
        MeetingStore.markInterruptedMeetings()
        return MeetingRecorder()
    }()
    private let meetingHotKeys = HotKeyManager()
    private var meetingHotKeyID: UInt32?
    private var meetingAutoDetect: MeetingAutoDetect?
    // 要件: REQ-COM-050, REQ-COM-051
    private let onboarding = OnboardingWindowController()
    private var cancellables: Set<AnyCancellable> = []

    // 設計判断: DEC-COM-008, DEC-COM-009, DEC-COM-093
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 設計判断: DEC-COM-090
        // メニューバーのアイコンなど、AppKit が設定に書くものを作る前に、初めての起動かを確かめる
        let showsOnboarding = OnboardingState.shouldShowOnLaunch()
        // 設計判断: DEC-COM-063
        // 前回落ちたときに残ったローカルの LLM のサーバーを止める
        LocalLLMServer.cleanUpStaleServer()
        controller = DictationController()
        historyUI = DictationHistoryUI(
            isDictationBusy: { [weak self] in self?.controller.state != .idle },
            onHotKeyRegistrationFailed: { [weak self] combo in
                self?.showAlert("ショートカット \(combo.displayString) を登録できませんでした", "設定の「履歴」で別のキーを選んでください。")
            })
        NSApp.mainMenu = makeMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        applyPresence(AppPresenceSettings.shared.presence, isLaunching: true)
        AppPresenceSettings.shared.$presence
            .dropFirst()
            .removeDuplicates()
            // @Published は値が変わる前に流れるので、変わったあと（updateIcon が新しい値を読める）に当てる
            .receive(on: DispatchQueue.main)
            .sink { [weak self] presence in self?.applyPresence(presence, isLaunching: false) }
            .store(in: &cancellables)
        updateIcon(for: .idle)

        controller.onStateChange = { [weak self] state in self?.updateIcon(for: state) }
        controller.onOpenHistory = { [weak self] id in self?.historyUI.openWindow(selecting: id) }
        editController = EditModeController(dictation: controller)
        editController.onStateChange = { [weak self] state in
            guard let self else { return }
            self.updateIcon(for: state == .idle ? self.controller.state : state)
        }
        editController.onHotKeyRegistrationFailed = { [weak self] combo in
            self?.showAlert(
                "ショートカット \(combo.displayString) を登録できませんでした",
                "他のアプリやシステムのショートカットと重なっている可能性があります。設定で「選択を声で編集」に別のキーを選んでください。")
        }
        meetingRecorder.onStateChange = { [weak self] _ in
            guard let self else { return }
            self.updateIcon(for: self.controller.state)
        }
        AppSettings.shared.$meetingHotKey
            .removeDuplicates()
            .sink { [weak self] combo in self?.registerMeetingHotKey(combo) }
            .store(in: &cancellables)
        // 会議アプリがマイクを使い始めたら記録を提案する（記録はユーザーが押してから）
        meetingAutoDetect = MeetingAutoDetect(recorder: meetingRecorder) { [weak self] in self?.toggleMeeting() }
        // 要件: REQ-MTG-034
        meetingRecorder.titleSourceApps = { [weak self] in self?.meetingAutoDetect?.titleSourceApps ?? [] }
        controller.onHotKeyRegistrationFailed = { [weak self] combo in
            self?.showAlert(
                "ショートカット \(combo.displayString) を登録できませんでした",
                "他のアプリやシステムのショートカットと重なっている可能性があります。設定で別のキーを選んでください。")
        }

        // 要件: REQ-COM-050, REQ-COM-051
        // 設計判断: DEC-COM-093
        // 初めての起動では、設定画面と許可のダイアログの代わりにオンボーディングを出す（許可はその最後のページで求める）
        if showsOnboarding {
            openOnboarding()
            return
        }
        // メニューバーのアイコンが隠れていても設定に辿り着けるよう、起動時は設定画面を開く
        openSettings()
        // 自動入力（⌘V の送信）にはアクセシビリティ権限が要る
        _ = Permissions.isAccessibilityTrusted(prompt: true)
    }

    // MARK: - アイコンの表示（メニューバー / Dock）

    // 要件: REQ-COM-040
    // 設計判断: DEC-COM-080
    /// メニューバーのアイコンと Dock のアイコンを、設定どおりに出し入れする
    private func applyPresence(_ presence: AppPresence, isLaunching: Bool) {
        statusItem.isVisible = presence.showsMenuBar
        if NSApp.activationPolicy() != presence.activationPolicy {
            NSApp.setActivationPolicy(presence.activationPolicy)
            // .accessory に変えた直後はアプリが後ろに回り、設定画面が他のアプリの裏に隠れる。
            // .regular に変えた直後は、前に出し直さないとメニューバーに Hanasu のメニューが出ないことがある
            if !isLaunching {
                DispatchQueue.main.async { [weak self] in
                    NSApp.activate()
                    self?.settingsWindow?.makeKeyAndOrderFront(nil)
                }
            }
        }
        updateIcon(for: controller.state)
    }

    // 要件: REQ-MTG-026
    // 設計判断: DEC-DIC-017, DEC-COM-081
    private func updateIcon(for state: DictationController.State) {
        // メニューバーに出さないときは、録音中・記録中を Dock のアイコンの印で示す
        let recording = state == .recording || meetingRecorder.state == .recording
        NSApp.dockTile.badgeLabel = !AppPresenceSettings.shared.presence.showsMenuBar && recording ? "●" : nil
        guard let button = statusItem.button else { return }
        var (symbol, tint): (String, NSColor?) = switch state {
        case .idle: ("mic", nil)
        case .preparing: ("mic.badge.ellipsis", nil)
        case .recording: ("mic.fill", .systemRed)
        case .processing: ("ellipsis.circle", nil)
        }
        // 音声入力をしていない間は、会議の記録の状態を出す
        if state == .idle {
            switch meetingRecorder.state {
            case .recording: (symbol, tint) = ("record.circle.fill", .systemRed)
            case .starting, .processing: (symbol, tint) = ("waveform.badge.ellipsis", nil)
            case .idle: break
            }
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Hanasu")
        image?.isTemplate = tint == nil
        button.image = image
        button.contentTintColor = tint
    }

    // MARK: - Menu

    // 要件: REQ-MTG-026
    func menuNeedsUpdate(_ menu: NSMenu) {
        populateMenu(menu, forDock: false)
    }

    // 要件: REQ-MTG-026, REQ-COM-040
    // 設計判断: DEC-COM-081
    /// メニューバーのメニュー（「Dock だけ」のときは Dock のメニューにも使う。Dock には終了が元からあるので省く）
    private func populateMenu(_ menu: NSMenu, forDock: Bool) {
        menu.removeAllItems()
        let settings = AppSettings.shared

        let toggleTitle: String = switch controller.state {
        case .idle: "録音を開始"
        case .preparing, .recording: "録音を停止して入力"
        case .processing: "整形中…"
        }
        let toggle = NSMenuItem(title: "\(toggleTitle)　\(settings.hotKey.displayString)",
                                action: #selector(toggleDictation), keyEquivalent: "")
        toggle.isEnabled = controller.state != .processing
        menu.addItem(toggle)
        if controller.state == .idle {
            // 設計判断: DEC-DIC-027
            let verb = TranslationLanguage.menuVerb(for: settings.translationLanguages)
            menu.addItem(NSMenuItem(title: "\(verb)して入力を開始　\(settings.translateHotKey.displayString)",
                                    action: #selector(toggleTranslation), keyEquivalent: ""))
            let editItem = NSMenuItem(title: "\(editController.menuTitle)　\(editController.hotKey.displayString)",
                                      action: #selector(toggleEditMode), keyEquivalent: "")
            editItem.isEnabled = editController.state != .processing
            menu.addItem(editItem)
        }
        menu.addItem(.separator())

        let meetingTitle: String
        switch meetingRecorder.state {
        case .idle: meetingTitle = "会議の記録を開始"
        case .starting: meetingTitle = "会議の記録を準備中…"
        case .recording:
            let elapsed = meetingRecorder.current.map { Date().timeIntervalSince($0.startedAt) } ?? 0
            meetingTitle = "会議の記録を停止（\(Meeting.clock(elapsed))）"
        case .processing(let message): meetingTitle = message
        }
        let meetingItem = NSMenuItem(title: "\(meetingTitle)　\(settings.meetingHotKey.displayString)",
                                     action: #selector(toggleMeeting), keyEquivalent: "")
        meetingItem.isEnabled = meetingRecorder.state == .idle || meetingRecorder.state == .recording
        menu.addItem(meetingItem)
        menu.addItem(NSMenuItem(title: "会議ノートを開く…", action: #selector(openMeetingWindow), keyEquivalent: ""))
        menu.addItem(.separator())

        let historyItem = NSMenuItem(title: "最近の結果", action: nil, keyEquivalent: "")
        historyItem.submenu = historyUI.makeRecentResultsMenu()
        menu.addItem(historyItem)
        menu.addItem(NSMenuItem(title: "履歴を開く…", action: #selector(openHistoryWindow), keyEquivalent: ""))

        let trusted = Permissions.isAccessibilityTrusted(prompt: false)
        let axItem = NSMenuItem(
            title: trusted ? "自動入力: 有効（アクセシビリティ許可済み）" : "自動入力: 無効 — アクセシビリティを許可…",
            action: trusted ? nil : #selector(openAccessibilitySettings), keyEquivalent: "")
        axItem.isEnabled = !trusted
        menu.addItem(axItem)

        menu.addItem(.separator())
        // 設計判断: DEC-COM-091
        menu.addItem(NSMenuItem(title: "Hanasu の使い方…", action: #selector(openOnboarding), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "設定…", action: #selector(openSettings), keyEquivalent: forDock ? "" : ","))
        if !forDock {
            menu.addItem(NSMenuItem(title: "Hanasu を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        }
        for item in menu.items where item.action != nil && item.action != #selector(NSApplication.terminate(_:)) {
            item.target = self
        }
    }

    // MARK: - Dock

    // 設計判断: DEC-COM-009
    /// Dock や Finder でアイコンをクリックしたら、設定画面を前に出す
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // 設計判断: DEC-COM-093
        // オンボーディングの途中なら、設定画面ではなくオンボーディングを前に出す
        if onboarding.isVisible {
            onboarding.show()
            return true
        }
        openSettings()
        return true
    }

    // 要件: REQ-COM-040
    // 設計判断: DEC-COM-081
    /// Dock のアイコンを右クリックしたときのメニュー
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        // メニューバーにアイコンを出さないときは、メニューバーのメニューと同じ操作を Dock から使えるようにする
        if !AppPresenceSettings.shared.presence.showsMenuBar {
            populateMenu(menu, forDock: true)
            return menu
        }
        let meeting = NSMenuItem(
            title: meetingRecorder.state == .recording ? "会議の記録を停止" : "会議の記録を開始",
            action: #selector(toggleMeeting), keyEquivalent: "")
        meeting.isEnabled = meetingRecorder.state == .idle || meetingRecorder.state == .recording
        menu.addItem(meeting)
        menu.addItem(NSMenuItem(title: "会議ノートを開く", action: #selector(openMeetingWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "設定…", action: #selector(openSettings), keyEquivalent: ""))
        for item in menu.items { item.target = self }
        return menu
    }

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Hanasu について", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        // 設計判断: DEC-COM-091
        appMenu.addItem(withTitle: "Hanasu の使い方…", action: #selector(openOnboarding), keyEquivalent: "").target = self
        appMenu.addItem(withTitle: "設定…", action: #selector(openSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hanasu を隠す", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "ほかを隠す", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
            .keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "すべてを表示", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hanasu を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(withTitle: "Hanasu", action: nil, keyEquivalent: "").submenu = appMenu

        let meetingMenu = NSMenu(title: "会議")
        meetingMenu.addItem(withTitle: "記録の開始／停止", action: #selector(toggleMeeting), keyEquivalent: "").target = self
        meetingMenu.addItem(withTitle: "会議ノートを開く", action: #selector(openMeetingWindow), keyEquivalent: "").target = self
        main.addItem(withTitle: "会議", action: nil, keyEquivalent: "").submenu = meetingMenu

        // テキスト欄でのコピー＆ペーストなどに必要
        let editMenu = NSMenu(title: "編集")
        editMenu.addItem(withTitle: "取り消す", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "やり直す", action: Selector(("redo:")), keyEquivalent: "z")
            .keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "カット", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "コピー", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "ペースト", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "すべてを選択", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(withTitle: "編集", action: nil, keyEquivalent: "").submenu = editMenu

        let windowMenu = NSMenu(title: "ウインドウ")
        windowMenu.addItem(withTitle: "しまう", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "閉じる", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(withTitle: "ウインドウ", action: nil, keyEquivalent: "").submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        return main
    }

    // MARK: - 会議

    @objc private func toggleMeeting() {
        if meetingRecorder.state == .idle { openMeetingWindow() }
        meetingRecorder.toggle()
    }

    static let meetingWindowSize = NSSize(width: 980, height: 640)
    /// MeetingWindowView の .frame(minWidth: 900, minHeight: 520) と同じ
    static let meetingWindowMinSize = NSSize(width: 900, height: 520)

    // 要件: REQ-MTG-007
    // 設計判断: DEC-MTG-048
    /// 会議ノートのウインドウ（確認用の CLI でも同じものを作る）
    static func makeMeetingWindow(rootView: some View) -> NSWindow {
        let hosting = NSHostingController(rootView: rootView)
        // ウインドウの大きさを中身に合わせない（最小の大きさは下の contentMinSize で決める）。
        // 合わせると、「メモ」タブのテキスト欄がメモの行数ぶんの高さを最小として求め、ウインドウが画面より縦に伸びて、
        // タイトルとタブの切り替えが画面の外に出て、議事録・文字起こしに戻れなくなっていた
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        window.title = "Hanasu 会議ノート"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.contentMinSize = meetingWindowMinSize
        window.setContentSize(meetingWindowSize)
        window.isReleasedWhenClosed = false
        return window
    }

    @objc private func openMeetingWindow() {
        if meetingWindow == nil {
            let window = Self.makeMeetingWindow(rootView: MeetingWindowView(recorder: meetingRecorder))
            window.setFrameAutosaveName("HanasuMeetingWindow")
            window.center()
            meetingWindow = window
        }
        meetingRecorder.reloadMeetings()
        NSApp.activate()
        meetingWindow?.makeKeyAndOrderFront(nil)
    }

    // 要件: REQ-MTG-001
    private func registerMeetingHotKey(_ combo: HotKeyCombo) {
        if let id = meetingHotKeyID { meetingHotKeys.unregister(id) }
        meetingHotKeyID = meetingHotKeys.register(combo) { [weak self] event in
            if event == .pressed { self?.toggleMeeting() }
        }
        if meetingHotKeyID == nil {
            showAlert("ショートカット \(combo.displayString) を登録できませんでした", "設定の「会議」で別のキーを選んでください。")
        }
    }

    @objc private func openAccessibilitySettings() {
        Permissions.openPrivacySettings("Privacy_Accessibility")
    }

    @objc private func toggleDictation() {
        controller.toggleFromMenu()
    }

    @objc private func toggleTranslation() {
        controller.toggleFromMenu(mode: controller.primaryTranslateMode)
    }

    @objc private func openHistoryWindow() {
        historyUI.openWindow()
    }

    @objc private func toggleEditMode() {
        editController.toggleFromMenu()
    }

    // 要件: REQ-COM-051
    // 設計判断: DEC-COM-091
    @objc private func openOnboarding() {
        onboarding.show()
    }

    // 設計判断: DEC-COM-151
    /// 設定のウインドウ。左にサイドバーを置き、大きさを変えられるようにする。
    /// 大きさを中身に合わせない（会議ノートと同じ。合わせると、中身の長い項目を開いたときにウインドウが縦に伸びる）
    static func makeSettingsWindow(rootView: some View) -> NSWindow {
        let hosting = NSHostingController(rootView: rootView)
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        window.title = "Hanasu 設定"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.contentMinSize = settingsWindowMinSize
        window.setContentSize(settingsWindowSize)
        window.isReleasedWhenClosed = false
        return window
    }

    static let settingsWindowSize = NSSize(width: 780, height: 600)
    static let settingsWindowMinSize = NSSize(width: 700, height: 480)

    // 設計判断: DEC-COM-012
    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(
                onOpenMeetingNotes: { [weak self] in self?.openMeetingWindow() },
                onBeginShortcutRecording: { [weak self] in
                    guard let self else { return }
                    self.controller.suspendHotKey()
                    self.historyUI.suspendHotKey()
                    self.editController.suspendHotKey()
                    if let id = self.meetingHotKeyID { self.meetingHotKeys.unregister(id) }
                    self.meetingHotKeyID = nil
                },
                onEndShortcutRecording: { [weak self] in
                    guard let self else { return }
                    self.controller.resumeHotKey()
                    self.historyUI.resumeHotKey()
                    self.editController.resumeHotKey()
                    self.registerMeetingHotKey(AppSettings.shared.meetingHotKey)
                },
                onOpenHistory: { [weak self] in self?.historyUI.openWindow() })
            let window = Self.makeSettingsWindow(rootView: view)
            window.center()
            window.setFrameAutosaveName("HanasuSettingsWindow")
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func showAlert(_ message: String, _ info: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        NSApp.activate()
        alert.runModal()
    }
}
