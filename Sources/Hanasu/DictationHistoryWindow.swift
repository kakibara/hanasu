import AppKit
import Combine
import SwiftUI

/// 音声入力の履歴ウインドウ、メニューの「最近の結果」、「最後の結果をもう一度入力」のショートカットを受け持つ。
@MainActor
final class DictationHistoryUI: NSObject {
    private let injectedStore: DictationHistoryStore?
    // 設計判断: DEC-DIC-070
    /// 使うときに初めて `shared` を取る（起動時に履歴の読み込みでメインを止めない。先読みは `DictationHistoryStore.preloadShared`）
    private var store: DictationHistoryStore { injectedStore ?? .shared }
    private let isDictationBusy: () -> Bool
    private let onHotKeyRegistrationFailed: (HotKeyCombo) -> Void
    private let hotKeys = HotKeyManager()
    private var hotKeyID: UInt32?
    private var window: NSWindow?
    private lazy var hud = HUDController()
    /// メニューに出している項目（タグの番号と対応）
    private var menuEntries: [DictationHistoryEntry] = []
    private var cancellables: Set<AnyCancellable> = []

    init(store: DictationHistoryStore? = nil,
         isDictationBusy: @escaping () -> Bool,
         onHotKeyRegistrationFailed: @escaping (HotKeyCombo) -> Void)
    {
        injectedStore = store
        self.isDictationBusy = isDictationBusy
        self.onHotKeyRegistrationFailed = onHotKeyRegistrationFailed
        super.init()
        HistorySettings.shared.$repasteHotKey
            .removeDuplicates()
            .sink { [weak self] combo in self?.registerHotKey(combo) }
            .store(in: &cancellables)
    }

    // MARK: - ショートカット

    func suspendHotKey() {
        if let hotKeyID { hotKeys.unregister(hotKeyID) }
        hotKeyID = nil
    }

    func resumeHotKey() {
        registerHotKey(HistorySettings.shared.repasteHotKey)
    }

    // 設計判断: DEC-DIC-077
    private func registerHotKey(_ combo: HotKeyCombo) {
        suspendHotKey()
        hotKeyID = hotKeys.register(combo) { [weak self] event in
            if event == .pressed { self?.repasteLast() }
        }
        if hotKeyID == nil { onHotKeyRegistrationFailed(combo) }
    }

    // 要件: REQ-DIC-062, REQ-DIC-080, REQ-DIC-083, REQ-DIC-084
    // 設計判断: DEC-DIC-077, DEC-DIC-096
    /// 最後の結果を、いま前面にあるアプリへもう一度入力する
    @objc func repasteLast() {
        guard !isDictationBusy() else { return }
        guard let last = store.entries.first else {
            NSSound.beep()
            hud.show(.error("まだ音声入力の結果がありません"))
            return
        }
        Task {
            // 結果を残す表示がキーウインドウのままだと、⌘V がそちらへ行ってしまう。閉じて、フォーカスが戻るのを少し待つ
            if PasteFallbackPanel.shared.isVisible {
                PasteFallbackPanel.shared.close()
                try? await Task.sleep(for: .milliseconds(100))
            }
            switch await TextInserter.insert(last.output) {
            case .pasted:
                hud.show(.done("最後の結果をもう一度入力しました"))
            case .copiedOnly:
                hud.show(.error("アクセシビリティが許可されていないため、クリップボードにコピーしました。⌘V で貼り付けてください。"))
            case .notPasted(let clipboardKept):
                PasteFallbackPanel.shared.show(text: last.output, subject: .result, clipboardKept: clipboardKept)
            case .unconfirmed(let clipboardKept):
                hud.show(.error(TextInserter.unconfirmedMessage(clipboardKept: clipboardKept)))
                if PasteFallbackSettings.shared.openHistoryWhenUnconfirmed {
                    openWindow(selecting: last.id)
                }
            }
        }
    }

    // MARK: - メニュー

    // 要件: REQ-DIC-008
    // 設計判断: DEC-DIC-078
    /// メニューバーの「最近の結果」の中身（履歴の新しい順に 10 件）
    func makeRecentResultsMenu() -> NSMenu {
        let menu = NSMenu()
        menuEntries = Array(store.entries.prefix(10))
        let repaste = NSMenuItem(
            title: "最後の結果をもう一度入力　\(HistorySettings.shared.repasteHotKey.displayString)",
            action: menuEntries.isEmpty ? nil : #selector(repasteLast), keyEquivalent: "")
        menu.addItem(repaste)
        menu.addItem(.separator())
        if menuEntries.isEmpty {
            menu.addItem(withTitle: "（まだありません）", action: nil, keyEquivalent: "")
        }
        for (index, entry) in menuEntries.enumerated() {
            let text = entry.output.replacingOccurrences(of: "\n", with: " ")
            let mark = entry.status.isFailure ? "⚠︎ " : ""
            let item = NSMenuItem(title: mark + String(text.prefix(40)) + (text.count > 40 ? "…" : ""),
                                  action: #selector(copyEntry(_:)), keyEquivalent: "")
            item.tag = index
            let label = entry.status.isUnrefined ? "結果（\(entry.status.label)）" : (entry.mode.translation?.verb ?? "整形後")
            item.toolTip = "\(label):\n\(entry.output)\n\n認識結果:\n\(entry.raw)"
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "すべての履歴を開く…", action: #selector(openWindowFromMenu), keyEquivalent: ""))
        for item in menu.items where item.action != nil { item.target = self }
        return menu
    }

    @objc private func copyEntry(_ sender: NSMenuItem) {
        guard menuEntries.indices.contains(sender.tag) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(menuEntries[sender.tag].output, forType: .string)
    }

    @objc private func openWindowFromMenu() {
        openWindow()
    }

    // MARK: - ウインドウ

    // 要件: REQ-DIC-084
    // 設計判断: DEC-DIC-099
    /// 履歴のウインドウを開く。selecting を渡すと、検索と絞り込みを外してその項目を選んだ状態で開く
    func openWindow(selecting id: UUID? = nil) {
        if let id, let window {
            let frame = window.frame
            window.contentViewController = NSHostingController(rootView: DictationHistoryView(store: store, selection: id))
            window.setFrame(frame, display: false)
        }
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: DictationHistoryView(store: store, selection: id)))
            window.title = "Hanasu 音声入力の履歴"
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            window.setContentSize(NSSize(width: 900, height: 580))
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("HanasuHistoryWindow")
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - 履歴ウインドウ

// 設計判断: DEC-DIC-079
enum DictationHistoryFilter: String, CaseIterable, Identifiable {
    case all
    case unrefined

    var id: String { rawValue }
    var label: String { self == .all ? "すべて" : "失敗・未整形" }
}

// 要件: REQ-DIC-060
// 設計判断: DEC-DIC-079
struct DictationHistoryView: View {
    @ObservedObject var store: DictationHistoryStore
    @State var selection: UUID?
    @State private var query = ""
    @State private var filter: DictationHistoryFilter = .all
    /// 削除の確認を待っている 1 件（設計判断: DEC-DIC-079）
    @State private var pendingDelete: UUID?

    init(store: DictationHistoryStore, selection: UUID? = nil, query: String = "") {
        self.store = store
        _selection = State(initialValue: selection)
        _query = State(initialValue: query)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 320)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 460)
        .confirmationDialog("この履歴を削除しますか？", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
        ) {
            Button("削除", role: .destructive) {
                if let id = pendingDelete { store.delete([id]) }
                pendingDelete = nil
            }
        } message: {
            Text("元に戻せません。")
        }
    }

    private var filtered: [DictationHistoryEntry] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return store.entries.filter { entry in
            if filter == .unrefined, !entry.status.isUnrefined { return false }
            return words.allSatisfy { word in
                entry.output.localizedStandardContains(word) || entry.raw.localizedStandardContains(word)
                    || (entry.appName?.localizedStandardContains(word) ?? false)
            }
        }
    }

    /// 日ごとにまとめる
    private var groups: [(day: Date, entries: [DictationHistoryEntry])] {
        let calendar = Calendar.current
        var result: [(day: Date, entries: [DictationHistoryEntry])] = []
        for entry in filtered {
            let day = calendar.startOfDay(for: entry.date)
            if result.last?.day == day {
                result[result.count - 1].entries.append(entry)
            } else {
                result.append((day, [entry]))
            }
        }
        return result
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("結果・原文・アプリ名で検索", text: $query)
                    .textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("検索語を消す")
                        .accessibilityLabel("検索語を消す")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
            .padding([.horizontal, .top], 10)
            Picker("表示", selection: $filter) {
                ForEach(DictationHistoryFilter.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)
            List(selection: $selection) {
                ForEach(groups, id: \.day) { group in
                    Section(Self.dayTitle(group.day)) {
                        ForEach(group.entries) { entry in
                            DictationHistoryRow(entry: entry)
                                .tag(entry.id)
                                .contextMenu { rowMenu(entry) }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .onDeleteCommand {
                if let selection { pendingDelete = selection }
            }
            Divider()
            HStack {
                Text(query.isEmpty && filter == .all ? "\(store.entries.count) 件" : "\(filtered.count) / \(store.entries.count) 件")
                Spacer()
                if let error = store.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .help(error)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder private func rowMenu(_ entry: DictationHistoryEntry) -> some View {
        Button("結果をコピー") { Self.copy(entry.output) }
        Button("原文をコピー") { Self.copy(entry.raw) }
        Divider()
        Button("削除", role: .destructive) { pendingDelete = entry.id }
    }

    @ViewBuilder private var detail: some View {
        if let selection, let entry = store.entries.first(where: { $0.id == selection }) {
            DictationHistoryDetail(entry: entry, store: store, onDelete: { pendingDelete = entry.id })
                .id(entry.id)
        } else {
            ContentUnavailableView(
                store.entries.isEmpty ? "まだ履歴がありません" : "履歴を選んでください",
                systemImage: "clock.arrow.circlepath",
                description: Text("音声入力の結果と文字起こしの原文がここに残ります。整形に失敗した文も、原文から整え直せます。"))
        }
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "今日" }
        if calendar.isDateInYesterday(day) { return "昨日" }
        return dayFormatter.string(from: day)
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy/MM/dd (E)"
        return f
    }()

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "HH:mm"
        return f
    }()

    static let fullFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy/MM/dd (E) HH:mm:ss"
        return f
    }()
}

// 要件: REQ-DIC-061
/// 失敗・未整形の印
struct DictationHistoryStatusMark: View {
    let status: DictationHistoryEntry.Status

    var body: some View {
        switch status {
        case .succeeded:
            EmptyView()
        case .geminiFailed, .noCredentials:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help(status.label)
        case .refineOff:
            Image(systemName: "text.badge.xmark")
                .foregroundStyle(.secondary)
                .help(status.label)
        }
    }
}

private struct DictationHistoryRow: View {
    let entry: DictationHistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                DictationHistoryStatusMark(status: entry.status)
                Text(entry.output.replacingOccurrences(of: "\n", with: " "))
                    .lineLimit(2)
            }
            HStack(spacing: 6) {
                Text(DictationHistoryView.timeFormatter.string(from: entry.date))
                if let app = entry.appName { Text(app).lineLimit(1) }
                if let translation = entry.mode.translation { Tag(text: translation.verb, color: .blue) }
                if entry.status.isFailure { Tag(text: entry.status == .geminiFailed ? "失敗" : "未整形", color: .orange) }
                if entry.status == .refineOff { Tag(text: "未整形", color: .secondary) }
                if entry.audioFileName != nil { Image(systemName: "waveform") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct Tag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .overlay(Capsule().strokeBorder(color.opacity(0.6)))
    }
}

// 設計判断: DEC-DIC-029
private struct DictationHistoryDetail: View {
    let entry: DictationHistoryEntry
    @ObservedObject var store: DictationHistoryStore
    let onDelete: () -> Void
    @ObservedObject private var settings = AppSettings.shared
    @State private var retrying: DictationHistoryEntry.Mode?
    @State private var message: (text: String, isError: Bool)?
    @State private var sound: NSSound?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if entry.status.isUnrefined { statusCallout }
                TextSection(title: outputTitle, text: entry.output) {
                    DictationHistoryView.copy(entry.output)
                    message = ("結果をクリップボードにコピーしました", false)
                }
                TextSection(title: "文字起こしの原文", text: entry.raw) {
                    DictationHistoryView.copy(entry.raw)
                    message = ("原文をクリップボードにコピーしました", false)
                }
                retrySection
                if let url = store.audioURL(for: entry) { audioSection(url) }
                Divider()
                HStack {
                    Spacer()
                    Button("この履歴を削除", role: .destructive, action: onDelete)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onDisappear { sound?.stop() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(DictationHistoryView.fullFormatter.string(from: entry.date)).font(.headline)
                Spacer()
                DictationHistoryStatusMark(status: entry.status)
                Text(entry.status.label).font(.callout).foregroundStyle(entry.status.isFailure ? .orange : .secondary)
            }
            HStack(spacing: 12) {
                Label(entry.appName ?? "（不明）", systemImage: "macwindow")
                Label(entry.mode.label, systemImage: entry.mode.translation != nil ? "globe" : "text.badge.checkmark")
                if let model = entry.model { Label(model, systemImage: "sparkles") }
                if let retried = entry.retriedAt {
                    Text("\(DictationHistoryView.fullFormatter.string(from: retried)) にやり直し")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var statusCallout: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch entry.status {
            case .geminiFailed:
                Text("AI での\(entry.mode.label)に失敗したため、原文のまま入力しました。")
            case .noCredentials:
                Text("AI の認証情報が未設定だったため、原文のまま入力しました。")
            case .refineOff:
                Text("「AI で整える」がオフだったため、原文のまま入力しました。")
            case .succeeded:
                EmptyView()
            }
            if let error = entry.errorMessage {
                Text(error).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .font(.callout)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((entry.status.isFailure ? Color.orange : Color.secondary).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 8))
    }

    private var outputTitle: String {
        if entry.status.isUnrefined { return "結果（原文のまま）" }
        return entry.mode.translation.map { "結果（\($0.verb)）" } ?? "結果（整形後）"
    }

    private var retrySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button { retry(.refine) } label: { Label("整形し直す", systemImage: "wand.and.stars") }
                ForEach(retryTranslations) { language in
                    Button { retry(.init(translation: language)) } label: { Label("\(language.verb)し直す", systemImage: "globe") }
                }
                if let retrying {
                    ProgressView().controlSize(.small)
                    Text("AI で\(retrying.label)しています…").font(.caption).foregroundStyle(.secondary)
                }
            }
            .disabled(retrying != nil)
            Text("原文を AI（音声入力に選んだ Gemini か Claude）に送り直します。結果はこの履歴に上書きし、クリップボードにもコピーします。")
                .font(.caption).foregroundStyle(.secondary)
            if let message {
                Label(message.text, systemImage: message.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(message.isError ? .orange : .green)
                    .textSelection(.enabled)
            }
        }
    }

    /// 「…し直す」に出す翻訳の言語。設定で選んだ言語と、この項目のモードの言語
    private var retryTranslations: [TranslationLanguage] {
        TranslationLanguage.normalized(settings.translationLanguages + [entry.mode.translation].compactMap { $0 })
    }

    private func audioSection(_ url: URL) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform").foregroundStyle(.secondary)
            Text("録音").font(.subheadline.weight(.semibold))
            Button("再生") {
                sound?.stop()
                sound = NSSound(contentsOf: url, byReference: true)
                sound?.play()
            }
            Button("停止") { sound?.stop() }
            Button("Finder で表示") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
    }

    private func retry(_ mode: DictationHistoryEntry.Mode) {
        retrying = mode
        message = nil
        Task {
            do {
                let updated = try await store.retry(entry.id, mode: mode)
                DictationHistoryView.copy(updated.output)
                message = ("\(mode.label)し直して、クリップボードにコピーしました", false)
            } catch {
                message = (error.localizedDescription, true)
            }
            retrying = nil
        }
    }
}

private struct TextSection: View {
    let title: String
    let text: String
    var onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Button("コピー", action: onCopy).controlSize(.small)
            }
            Text(text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
        }
    }
}

// MARK: - 設定画面の「履歴」タブ

struct HistorySettingsTab: View {
    @ObservedObject var settings = HistorySettings.shared
    @ObservedObject var store: DictationHistoryStore
    var onOpenHistory: () -> Void
    var onBeginShortcutRecording: () -> Void
    var onEndShortcutRecording: () -> Void
    @State private var confirmDeleteAll = false

    init(store: DictationHistoryStore? = nil,
         onOpenHistory: @escaping () -> Void,
         onBeginShortcutRecording: @escaping () -> Void,
         onEndShortcutRecording: @escaping () -> Void)
    {
        self.store = store ?? .shared
        self.onOpenHistory = onOpenHistory
        self.onBeginShortcutRecording = onBeginShortcutRecording
        self.onEndShortcutRecording = onEndShortcutRecording
    }

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false  // 「Zero KB」ではなく「0 KB」にする
        return f
    }()

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("音声入力の結果と文字起こしの原文（\(store.entries.count) 件）")
                    Spacer()
                    Button("履歴を開く", action: onOpenHistory)
                }
            }
            Section {
                LabeledContent("最後の結果をもう一度入力") {
                    ShortcutRecorder(
                        combo: $settings.repasteHotKey,
                        defaultCombo: .defaultRepaste,
                        onBeginRecording: onBeginShortcutRecording,
                        onEndRecording: onEndShortcutRecording)
                }
            } footer: {
                Text("入力先がずれて結果が消えたときに、いま前面にあるアプリへ最後の結果を入力し直します。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("履歴をファイルに保存する", isOn: $settings.enabled)
                Picker("残す件数", selection: $settings.maxCount) {
                    ForEach(HistorySettings.countOptions, id: \.self) { Text("\($0) 件").tag($0) }
                }
                .disabled(!settings.enabled)
                Picker("残す期間", selection: $settings.maxDays) {
                    ForEach(HistorySettings.dayOptions, id: \.self) { days in
                        Text(days == 0 ? "無期限" : "\(days) 日").tag(days)
                    }
                }
                .disabled(!settings.enabled)
                Toggle(isOn: $settings.keepAudio) {
                    Text("録音した音声も残す")
                    Text("m4a（32 kbps）で 1 分あたり約 0.25 MB。履歴と一緒に、件数・期間の上限で消えます。")
                }
                .disabled(!settings.enabled)
            } header: {
                Text("保存")
            } footer: {
                Text(settings.enabled
                     ? "保存先: ~/Library/Application Support/Hanasu/History（本人だけが読めるファイル）。上限を超えたものは古い順に消えます。"
                     : "保存しない間も、直近 \(DictationHistoryStore.transientLimit) 件はアプリを終了するまでメニューと再入力に使えます。保存済みの履歴は残るので、消すには下の「すべて削除」を使ってください。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                let usage = store.audioUsage()
                LabeledContent("録音の使用量") {
                    Text("\(Self.byteFormatter.string(fromByteCount: usage.bytes))（\(usage.count) 件）")
                }
                HStack {
                    Button("録音だけをすべて削除") { store.deleteAllAudio() }
                        .disabled(usage.count == 0)
                    Spacer()
                    Button("履歴をすべて削除…", role: .destructive) { confirmDeleteAll = true }
                        .disabled(store.entries.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("音声入力の履歴をすべて削除しますか？", isPresented: $confirmDeleteAll) {
            Button("すべて削除", role: .destructive) { store.deleteAll() }
        } message: {
            Text("\(store.entries.count) 件の履歴と、残している録音を削除します。元に戻せません。")
        }
    }
}
