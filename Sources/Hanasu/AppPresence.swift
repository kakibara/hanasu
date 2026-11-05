import AppKit
import SwiftUI

// 要件: REQ-COM-040
// 設計判断: DEC-COM-080
/// Hanasu のアイコンを出す場所（メニューバー / Dock / 両方）
enum AppPresence: String, CaseIterable, Identifiable {
    case menuBar
    case dock
    case both

    var id: String { rawValue }
    var label: String {
        switch self {
        case .menuBar: "メニューバーだけ"
        case .dock: "Dock だけ"
        case .both: "メニューバーと Dock の両方"
        }
    }

    var showsMenuBar: Bool { self != .dock }
    var showsDock: Bool { self != .menuBar }

    /// Dock に出すなら .regular、出さないなら .accessory（Dock と ⌘Tab に出ない）
    var activationPolicy: NSApplication.ActivationPolicy { showsDock ? .regular : .accessory }
}

// 設計判断: DEC-COM-013, DEC-COM-080
final class AppPresenceSettings: ObservableObject {
    static let shared = AppPresenceSettings()

    private let defaults = UserDefaults.standard
    private static let key = "appPresence"

    @Published var presence: AppPresence { didSet { defaults.set(presence.rawValue, forKey: Self.key) } }

    private init() {
        defaults.register(defaults: [Self.key: AppPresence.both.rawValue])
        presence = AppPresence(rawValue: defaults.string(forKey: Self.key) ?? "") ?? .both
    }
}

// 要件: REQ-COM-040
/// 設定の「一般」の「アイコンの表示」の欄
struct AppPresenceSettingsSection: View {
    @ObservedObject var settings = AppPresenceSettings.shared

    var body: some View {
        Section {
            Picker("アイコンを出す場所", selection: $settings.presence) {
                ForEach(AppPresence.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.radioGroup)
        } header: {
            Text("アイコンの表示")
        } footer: {
            Text("「メニューバーだけ」では Dock と ⌘Tab に出ません。「Dock だけ」では、Dock のアイコンを右クリックするとメニューバーと同じメニューが出て、録音中はアイコンに ● が付きます。どの場合も、Finder から Hanasu をもう一度開くと設定画面が出ます。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// 確かめ方: REQ-COM-040
//   Hanasu --render-presence-settings <出力.png>
//     設定の「一般」の「アイコンの表示」の欄を画像にする
@MainActor
enum AppPresenceCLI {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--render-presence-settings"), args.indices.contains(index + 1) else { return }
        _ = NSApplication.shared
        let size = NSSize(width: 560, height: 200)
        let view = Form { AppPresenceSettingsSection() }
            .formStyle(.grouped)
            .frame(width: size.width, height: size.height)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)
        if let rep { hosting.cacheDisplay(in: hosting.bounds, to: rep) }
        let url = URL(fileURLWithPath: args[index + 1])
        guard let data = rep?.representation(using: .png, properties: [:]), (try? data.write(to: url)) != nil else {
            FileHandle.standardError.write(Data("error: 画像を書き出せませんでした\n".utf8))
            exit(1)
        }
        print("wrote \(url.path)")
        exit(0)
    }
}
