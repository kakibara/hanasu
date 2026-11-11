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
        let recorder = MeetingRecorder()
        // 要件: REQ-MTG-057
        // 設計判断: DEC-MTG-143（起動時に、会議を「失敗」にしたあとで、保存期間を過ぎた録音を消す）
        recorder.pruneExpiredAudio()
        // 要件: REQ-MTG-056（設定と会議ノートのメニューから、録音の管理を開けるように）
        MeetingAudioManagerWindow.recorder = recorder
        return recorder
    }()
    private let meetingHotKeys = HotKeyManager()
    private var meetingHotKeyID: UInt32?
    private var meetingAutoDetect: MeetingAutoDetect?
    // 要件: REQ-COM-050, REQ-COM-051
    private let onboarding = OnboardingWindowController()
    // 要件: REQ-REL-010, REQ-REL-011
    private let updater = AppUpdater()
    private var cancellables: Set<AnyCancellable> = []

    // 設計判断: DEC-COM-008, DEC-COM-009, DEC-COM-093
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 設計判断: DEC-COM-090
        // メニューバーのアイコンなど、AppKit が設定に書くものを作る前に、初めての起動かを確かめる
        let showsOnboarding = OnboardingState.shouldShowOnLaunch()
        // 設計判断: DEC-COM-063
        // 前回落ちたときに残ったローカルの LLM のサーバーを止める
        LocalLLMServer.cleanUpStaleServer()
        // 設計判断: DEC-DIC-070
        // 音声入力の履歴は裏で先に読んでおく（先に使われたら、そこで同期で読む）
        DictationHistoryStore.preloadShared()
        controller = DictationController()
        historyUI = DictationHistoryUI(
            isDictationBusy: { [weak self] in self?.controller.state != .idle },
            onHotKeyRegistrationFailed: { [weak self] combo in
                self?.showAlert(tr("ショートカット %@ を登録できませんでした", "\(combo.displayString)"), tr("設定の「履歴」で別のキーを選んでください。"))
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
                tr("ショートカット %@ を登録できませんでした", "\(combo.displayString)"),
                tr("他のアプリやシステムのショートカットと重なっている可能性があります。設定で「選択を声で編集」に別のキーを選んでください。"))
        }
        meetingRecorder.onStateChange = { [weak self] _ in
            guard let self else { return }
            self.updateIcon(for: self.controller.state)
            // 設計判断: DEC-DIC-189
            // 会議の記録中は、設定の欄で画面収録の許可を求めない（macOS の「終了して再度開く」で記録が切れないように）
            ScreenContextSettings.shared.meetingInProgress = self.meetingRecorder.state != .idle
        }
        AppSettings.shared.$meetingHotKey
            .removeDuplicates()
            .sink { [weak self] combo in self?.registerMeetingHotKey(combo) }
            .store(in: &cancellables)
        // 会議アプリがマイクを使い始めたら記録を提案する（記録はユーザーが押してから）
        meetingAutoDetect = MeetingAutoDetect(recorder: meetingRecorder) { [weak self] in self?.toggleMeeting() }
        // 要件: REQ-MTG-034
        meetingRecorder.titleSourceApps = { [weak self] in self?.meetingAutoDetect?.titleSourceApps ?? [] }
        // 要件: REQ-MTG-047
        // 設計判断: DEC-MTG-096（「チャットで続ける」で会議ノートを前に出す）
        MeetingAskedQuestion.shared.openMeetingWindow = { [weak self] in self?.openMeetingWindow() }
        controller.onHotKeyRegistrationFailed = { [weak self] combo in
            self?.showAlert(
                tr("ショートカット %@ を登録できませんでした", "\(combo.displayString)"),
                tr("他のアプリやシステムのショートカットと重なっている可能性があります。設定で別のキーを選んでください。"))
        }

        // 設計判断: DEC-REL-023
        // 録音・会議の記録・議事録の作り直し・ローカルのモデルのダウンロードの間は入れ替えない（終えると途中で切れる）
        updater.isBusy = { [weak self] in
            guard let self else { return false }
            let downloading = LocalLLMModel.allCases.contains {
                if case .downloading = LocalLLMStore.shared.status($0) { return true }
                return false
            } || WhisperModel.allCases.contains {
                if case .downloading = WhisperModelStore.shared.status($0) { return true }
                return false
            }
            return self.controller.state != .idle || self.editController.state != .idle || self.meetingRecorder.state != .idle
                || self.meetingRecorder.regeneratingID != nil || downloading
        }
        // 設計判断: DEC-REL-026
        // 前の起動で始めた入れ替えができていなければ知らせる
        updater.reportPreviousAttempt()

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
        // 要件: REQ-REL-010
        // 設計判断: DEC-REL-024
        // 初めての起動（上のオンボーディング）では確かめない
        updater.checkOnLaunch()
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
        case .idle: tr("録音を開始")
        case .preparing, .recording: tr("録音を停止して入力")
        case .processing: tr("整形中…")
        }
        let toggle = NSMenuItem(title: "\(toggleTitle)　\(settings.hotKey.displayString)",
                                action: #selector(toggleDictation), keyEquivalent: "")
        toggle.isEnabled = controller.state != .processing
        menu.addItem(toggle)
        if controller.state == .idle {
            // 設計判断: DEC-DIC-027
            let verb = TranslationLanguage.menuVerb(for: settings.translationLanguages)
            menu.addItem(NSMenuItem(title: tr("%@して入力を開始　%@", "\(verb)", "\(settings.translateHotKey.displayString)"),
                                    action: #selector(toggleTranslation), keyEquivalent: ""))
            let editItem = NSMenuItem(title: "\(editController.menuTitle)　\(editController.hotKey.displayString)",
                                      action: #selector(toggleEditMode), keyEquivalent: "")
            editItem.isEnabled = editController.state != .processing
            menu.addItem(editItem)
        }
        menu.addItem(.separator())

        let meetingTitle: String
        switch meetingRecorder.state {
        case .idle: meetingTitle = tr("会議の記録を開始")
        case .starting: meetingTitle = tr("会議の記録を準備中…")
        case .recording:
            let elapsed = meetingRecorder.current.map { Date().timeIntervalSince($0.startedAt) } ?? 0
            meetingTitle = tr("会議の記録を停止（%@）", "\(Meeting.clock(elapsed))")
        case .processing(let message): meetingTitle = message
        }
        let meetingItem = NSMenuItem(title: "\(meetingTitle)　\(settings.meetingHotKey.displayString)",
                                     action: #selector(toggleMeeting), keyEquivalent: "")
        meetingItem.isEnabled = meetingRecorder.state == .idle || meetingRecorder.state == .recording
        menu.addItem(meetingItem)
        menu.addItem(NSMenuItem(title: tr("会議ノートを開く…"), action: #selector(openMeetingWindow), keyEquivalent: ""))
        menu.addItem(.separator())

        let historyItem = NSMenuItem(title: tr("最近の結果"), action: nil, keyEquivalent: "")
        historyItem.submenu = historyUI.makeRecentResultsMenu()
        menu.addItem(historyItem)
        menu.addItem(NSMenuItem(title: tr("履歴を開く…"), action: #selector(openHistoryWindow), keyEquivalent: ""))

        let trusted = Permissions.isAccessibilityTrusted(prompt: false)
        let axItem = NSMenuItem(
            title: trusted ? tr("自動入力: 有効（アクセシビリティ許可済み）") : tr("自動入力: 無効 — アクセシビリティを許可…"),
            action: trusted ? nil : #selector(openAccessibilitySettings), keyEquivalent: "")
        axItem.isEnabled = !trusted
        menu.addItem(axItem)

        menu.addItem(.separator())
        // 設計判断: DEC-COM-091
        menu.addItem(NSMenuItem(title: tr("Hanasu の使い方…"), action: #selector(openOnboarding), keyEquivalent: ""))
        // 要件: REQ-REL-011
        menu.addItem(NSMenuItem(title: tr("アップデートを確認…"), action: #selector(checkForUpdates), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: tr("設定…"), action: #selector(openSettings), keyEquivalent: forDock ? "" : ","))
        if !forDock {
            menu.addItem(NSMenuItem(title: tr("Hanasu を終了"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
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
            title: meetingRecorder.state == .recording ? tr("会議の記録を停止") : tr("会議の記録を開始"),
            action: #selector(toggleMeeting), keyEquivalent: "")
        meeting.isEnabled = meetingRecorder.state == .idle || meetingRecorder.state == .recording
        menu.addItem(meeting)
        menu.addItem(NSMenuItem(title: tr("会議ノートを開く"), action: #selector(openMeetingWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: tr("設定…"), action: #selector(openSettings), keyEquivalent: ""))
        for item in menu.items { item.target = self }
        return menu
    }

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: tr("Hanasu について"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        // 要件: REQ-REL-011
        appMenu.addItem(withTitle: tr("アップデートを確認…"), action: #selector(checkForUpdates), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        // 設計判断: DEC-COM-091
        appMenu.addItem(withTitle: tr("Hanasu の使い方…"), action: #selector(openOnboarding), keyEquivalent: "").target = self
        appMenu.addItem(withTitle: tr("設定…"), action: #selector(openSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: tr("Hanasu を隠す"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: tr("ほかを隠す"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
            .keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: tr("すべてを表示"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: tr("Hanasu を終了"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(withTitle: "Hanasu", action: nil, keyEquivalent: "").submenu = appMenu

        let meetingMenu = NSMenu(title: tr("会議"))
        meetingMenu.addItem(withTitle: tr("記録の開始／停止"), action: #selector(toggleMeeting), keyEquivalent: "").target = self
        meetingMenu.addItem(withTitle: tr("会議ノートを開く"), action: #selector(openMeetingWindow), keyEquivalent: "").target = self
        main.addItem(withTitle: tr("会議"), action: nil, keyEquivalent: "").submenu = meetingMenu

        // テキスト欄でのコピー＆ペーストなどに必要
        let editMenu = NSMenu(title: tr("編集"))
        editMenu.addItem(withTitle: tr("取り消す"), action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: tr("やり直す"), action: Selector(("redo:")), keyEquivalent: "z")
            .keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: tr("カット"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: tr("コピー"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: tr("ペースト"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: tr("すべてを選択"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(withTitle: tr("編集"), action: nil, keyEquivalent: "").submenu = editMenu

        let windowMenu = NSMenu(title: tr("ウインドウ"))
        windowMenu.addItem(withTitle: tr("しまう"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: tr("閉じる"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(withTitle: tr("ウインドウ"), action: nil, keyEquivalent: "").submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        return main
    }

    // MARK: - 会議

    @objc private func toggleMeeting() {
        if meetingRecorder.state == .idle { openMeetingWindow() }
        meetingRecorder.toggle()
    }

    static let meetingWindowSize = NSSize(width: 1240, height: 760)
    // 設計判断: DEC-MTG-130
    /// 会議ノートの最小の大きさ（一覧 260 ＋ 文書 400 ＋ 後ろ側のパネル 360 ＋ 区切り）
    static let meetingWindowMinSize = NSSize(width: 1040, height: 560)

    // 要件: REQ-MTG-007
    // 設計判断: DEC-MTG-048
    /// 会議ノートのウインドウ（確認用の CLI でも同じものを作る）
    static func makeMeetingWindow(rootView: some View) -> NSWindow {
        let hosting = NSHostingController(rootView: rootView)
        // ウインドウの大きさを中身に合わせない（最小の大きさは下の contentMinSize で決める）。
        // 合わせると、「メモ」タブのテキスト欄がメモの行数ぶんの高さを最小として求め、ウインドウが画面より縦に伸びて、
        // タイトルとタブの切り替えが画面の外に出て、議事録・文字起こしに戻れなくなっていた
        hosting.sizingOptions = []
        // 設計判断: DEC-MTG-130（SwiftUI のツールバーをウインドウのツールバーにする）
        hosting.sceneBridgingOptions = [.toolbars]
        let window = NSWindow(contentViewController: hosting)
        window.title = tr("Hanasu 会議ノート")
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.titleVisibility = .hidden
        // 要件: REQ-MTG-053（スペースキーで再生・一時停止するウインドウの目印）
        window.identifier = MeetingPlayer.windowIdentifier
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
            // 要件: REQ-MTG-053（ウインドウを閉じたら再生を止める。ウインドウは閉じても残すので、中のビューの onDisappear は呼ばれない）
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
                MainActor.assumeIsolated { MeetingPlayer.shared.pause() }
            }
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
            showAlert(tr("ショートカット %@ を登録できませんでした", "\(combo.displayString)"), tr("設定の「会議」で別のキーを選んでください。"))
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

    // 要件: REQ-REL-011
    @objc private func checkForUpdates() {
        updater.checkManually()
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
        window.title = tr("Hanasu 設定")
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
                    // 設計判断: DEC-COM-012, DEC-MTG-097（記録中だけのショートカットも外す）
                    MeetingHighlightHotKey.shared.suspend()
                    MeetingAskedHotKey.shared.suspend()
                },
                onEndShortcutRecording: { [weak self] in
                    guard let self else { return }
                    self.controller.resumeHotKey()
                    self.historyUI.resumeHotKey()
                    self.editController.resumeHotKey()
                    self.registerMeetingHotKey(AppSettings.shared.meetingHotKey)
                    MeetingHighlightHotKey.shared.resume()
                    MeetingAskedHotKey.shared.resume()
                },
                onOpenHistory: { [weak self] in self?.historyUI.openWindow() },
                onCheckForUpdates: { [weak self] in self?.updater.checkManually() })
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
