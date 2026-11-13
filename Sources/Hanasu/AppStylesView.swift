import AppKit
import SwiftUI
import UniformTypeIdentifiers

// 設計判断: DEC-DIC-047
/// 設定画面の「アプリ別」。入力先アプリごとに、文体のプリセット・追加ルール・既定の出力言語を決める。
struct AppStylesTab: View {
    @ObservedObject var store = AppStyleStore.shared
    @ObservedObject var customStore = CustomStyleStore.shared
    /// 追加ルールの欄を開いているアプリ
    @State private var expandedID: String?
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section {
                Toggle(tr("入力先アプリに合わせて文体を変える"), isOn: $store.enabled)
            } footer: {
                Text(tr("録音を始めたときに前面にあるアプリで決まります。「辞書・ルール」の追加ルールと食い違うときは、アプリ別のルールを優先します。出力言語を English にしたアプリでは、画面下の表示が English で始まります（そこで切り替えればそちらが優先）。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                if store.styles.isEmpty {
                    Text(tr("アプリが登録されていません")).foregroundStyle(.secondary)
                }
                ForEach($store.styles) { $style in
                    AppStyleRow(
                        style: $style,
                        customStyles: customStore.sorted,
                        expanded: expandedID == style.id,
                        onToggleExpanded: { expandedID = expandedID == style.id ? nil : style.id },
                        onDelete: { delete(style.id) })
                }
            } header: {
                HStack {
                    Text(tr("アプリ"))
                    Spacer()
                    addMenu
                    Button(tr("初期設定に戻す…")) { confirmReset = true }
                    .controlSize(.small)
                }
            }
            .disabled(!store.enabled)
            Section(tr("プリセット")) {
                ForEach(AppStylePreset.allCases.filter { $0 != .none }) { preset in
                    LabeledContent(preset.label) {
                        Text(preset.summary).foregroundStyle(.secondary)
                    }
                }
            }
            .font(.caption)
            // 要件: REQ-DIC-022
            CustomStylesSection(customStore: customStore)
        }
        .formStyle(.grouped)
        .confirmationDialog(tr("アプリ別の設定を初期設定に戻しますか？"), isPresented: $confirmReset) {
            Button(tr("初期設定に戻す"), role: .destructive) {
                expandedID = nil
                store.resetToDefaults()
            }
        } message: {
            // 設計判断: DEC-DIC-213（カスタム文体は消さない）
            Text(tr("追加したアプリと、アプリごとの追加ルールが消えます。カスタム文体は消えません。元に戻せません。"))
        }
    }

    private var addMenu: some View {
        Menu {
            Section(tr("実行中のアプリ")) {
                ForEach(runningApps, id: \.bundleID) { app in
                    Button(app.name) { add(bundleID: app.bundleID, name: app.name) }
                }
            }
            Divider()
            Button(tr("アプリケーションを選ぶ…"), action: chooseApplications)
        } label: {
            Label(tr("追加"), systemImage: "plus")
        }
        .controlSize(.small)
        .fixedSize()
    }

    /// 実行中の普通のアプリ（Dock に出るもの）のうち、まだ登録していないもの
    private var runningApps: [(bundleID: String, name: String)] {
        let registered = Set(store.styles.map(\.bundleID))
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> (bundleID: String, name: String)? in
                guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier,
                      !registered.contains(id), seen.insert(id).inserted else { return nil }
                return (id, app.localizedName ?? id)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func add(bundleID: String, name: String) {
        store.add(bundleID: bundleID, name: name)
        expandedID = bundleID
    }

    private func delete(_ id: String) {
        if expandedID == id { expandedID = nil }
        store.styles.removeAll { $0.id == id }
    }

    private func chooseApplications() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = tr("追加")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let id = Bundle(url: url)?.bundleIdentifier else { continue }
            add(bundleID: id, name: AppIconCache.displayName(of: url))
        }
    }
}

/// プリセットの選択欄の項目（組み込みのプリセットか、カスタム文体）
private enum StyleChoice: Hashable {
    case preset(AppStylePreset)
    case custom(UUID)
}

private struct AppStyleRow: View {
    @Binding var style: AppStyle
    var customStyles: [CustomStyle]
    var expanded: Bool
    var onToggleExpanded: () -> Void
    var onDelete: () -> Void

    /// 選択欄の値。見つからないカスタム文体（消した・ほかの版で保存した）は「なし」として出す
    private var choice: Binding<StyleChoice> {
        Binding(
            get: {
                if let id = style.customStyleID, customStyles.contains(where: { $0.id == id }) { return .custom(id) }
                return .preset(style.preset)
            },
            set: { value in
                switch value {
                case .preset(let preset): style.selectPreset(preset)
                case .custom(let id): style.selectCustomStyle(id)
                }
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(nsImage: AppIconCache.icon(for: style.bundleID))
                    .resizable()
                    .frame(width: 20, height: 20)
                Text(style.name)
                    .lineLimit(1)
                    .help(style.bundleID)
                Spacer()
                // 要件: REQ-DIC-023
                // 設計判断: DEC-DIC-213, DEC-DIC-215（組み込みのあとに区切りを入れてカスタム文体を並べる。組み込みを選んだら割り当てを外す）
                Picker(tr("プリセット"), selection: choice) {
                    ForEach(AppStylePreset.allCases) { Text($0.label).tag(StyleChoice.preset($0)) }
                    if !customStyles.isEmpty {
                        Divider()
                        ForEach(customStyles) { Text($0.name).tag(StyleChoice.custom($0.id)) }
                    }
                }
                .labelsHidden()
                .frame(width: 150)
                Picker(tr("出力言語"), selection: $style.outputLanguage) {
                    ForEach(AppOutputLanguage.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .frame(width: 140)
                Button(action: onToggleExpanded) {
                    Image(systemName: style.rules.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          ? "text.badge.plus" : "text.badge.checkmark")
                }
                .buttonStyle(.borderless)
                .help(tr("このアプリ用の追加ルール"))
                .accessibilityLabel(tr("このアプリ用の追加ルール"))
                .accessibilityValue(expanded ? tr("開いています") : tr("閉じています"))
                Button(action: onDelete) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help(tr("一覧から外す"))
                .accessibilityLabel(tr("%@ を一覧から外す", "\(style.name)"))
            }
            if expanded {
                Text(tr("このアプリ用の追加ルール（プリセットより優先）"))
                    .font(.caption)
                TextField(tr("このアプリ用の追加ルール"), text: $style.rules,
                          prompt: Text(tr("例: 絵文字は使わない／箇条書きにしない")), axis: .vertical)
                    .labelsHidden()
                    .multilineTextAlignment(.leading)
                    .lineLimit(2...5)
                    .textFieldStyle(.roundedBorder)
                Text(style.bundleID)
                    .font(.caption).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

/// アプリのアイコンと表示名。LaunchServices を毎回引かないように覚えておく
@MainActor
enum AppIconCache {
    private static var icons: [String: NSImage] = [:]

    static func icon(for bundleID: String) -> NSImage {
        if let cached = icons[bundleID] { return cached }
        let image: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            image = NSWorkspace.shared.icon(for: .applicationBundle)
        }
        icons[bundleID] = image
        return image
    }

    static func displayName(of appURL: URL) -> String {
        let name = FileManager.default.displayName(atPath: appURL.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}

/// 設定の「アプリ別」を画像にする（見た目の確認用）。main.swift の --render-app-styles から呼ぶ
@MainActor
func renderAppStylesPNG(to url: URL, expandedFirst: Bool) {
    _ = NSApplication.shared
    let view = AppStylesTab(initialExpandedID: expandedFirst ? AppStyleStore.shared.styles.first?.id : nil)
        .frame(width: 560, height: 460)
        .background(Color(nsColor: .windowBackgroundColor))
    let hosting = NSHostingView(rootView: view)
    hosting.frame = NSRect(x: 0, y: 0, width: 560, height: 460)
    let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = hosting
    hosting.layoutSubtreeIfNeeded()
    // Form の中身は次の描画で並ぶので、少しだけ回してから描く
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print("wrote")
    }
}

extension AppStylesTab {
    /// 確認用に、追加ルール欄を開いた状態で作る
    init(initialExpandedID: String?, customStore: CustomStyleStore = .shared) {
        _expandedID = State(initialValue: initialExpandedID)
        self.customStore = customStore
    }
}
