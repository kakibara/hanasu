import AppKit
import SwiftUI

// 要件: REQ-COM-040
// 設計判断: DEC-COM-080
/// Hanasu のアイコンを出す場所。Dock にはいつも出し、メニューバーにも出すかを選ぶ
/// （「メニューバーだけ」は 2026-11-12 になくした）
enum AppPresence: String, CaseIterable, Identifiable {
    case dock
    case both

    var id: String { rawValue }
    var label: String {
        switch self {
        case .dock: tr("Dock だけ")
        case .both: tr("メニューバーと Dock の両方")
        }
    }

    var showsMenuBar: Bool { self == .both }

    // 設計判断: DEC-COM-080
    /// 保存されている値（なければ nil）を読み替える。`dock` / `both` 以外（前の版の `menuBar`・分からない値）は `both`。
    /// 値が保存されていて、それが `dock` / `both` 以外のときだけ書き戻す（保存されていないときに書くと、
    /// 新しく入れた人が「以前から使っている人」と見なされてオンボーディングが出なくなる。DEC-COM-090）
    static func resolve(stored: String?) -> (presence: AppPresence, needsWriteBack: Bool) {
        guard let stored else { return (.both, false) }
        if let presence = AppPresence(rawValue: stored) { return (presence, false) }
        return (.both, true)
    }
}

// 設計判断: DEC-COM-013, DEC-COM-080
final class AppPresenceSettings: ObservableObject {
    static let shared = AppPresenceSettings()

    private let defaults = UserDefaults.standard
    private static let key = "appPresence"

    @Published var presence: AppPresence { didSet { defaults.set(presence.rawValue, forKey: Self.key) } }

    private init() {
        // 登録した既定値と区別するため、保存されている値は persistentDomain から読む
        let stored = defaults.persistentDomain(forName: AppSettings.defaultsDomainName)?[Self.key] as? String
        let (resolved, needsWriteBack) = AppPresence.resolve(stored: stored)
        presence = resolved
        if needsWriteBack { defaults.set(resolved.rawValue, forKey: Self.key) }
    }
}

// 要件: REQ-COM-040
/// 設定の「一般」の「アイコンの表示」の欄
struct AppPresenceSettingsSection: View {
    @ObservedObject var settings = AppPresenceSettings.shared

    var body: some View {
        Section {
            Picker(tr("アイコンを出す場所"), selection: $settings.presence) {
                ForEach(AppPresence.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.radioGroup)
        } header: {
            Text(tr("アイコンの表示"))
        } footer: {
            Text(tr("Dock のアイコンはいつも出ます。選ぶとすぐ切り替わります。「Dock だけ」では、Dock のアイコンを右クリックするとメニューバーと同じメニューが出て、録音中はアイコンに ● が付きます。設定画面は、メニューバーのアイコンか Dock のアイコンを右クリックしたメニューの「設定…」から開きます。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// 確かめ方: REQ-COM-040
//   Hanasu --render-presence-settings <出力.png>
//     設定の「一般」の「アイコンの表示」の欄を画像にする
//   Hanasu --presence-migration
//     保存されている値の読み替え（前の版の menuBar → both など）を確かめる。違えば終了コード 1
@MainActor
enum AppPresenceCLI {
    static func runIfRequested() {
        if CommandLine.arguments.contains("--presence-migration") { runMigrationTest() }
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

    // 確かめ方: REQ-COM-040
    private static func runMigrationTest() {
        let cases: [(String?, AppPresence, Bool)] = [
            (nil, .both, false),
            ("both", .both, false),
            ("dock", .dock, false),
            ("menuBar", .both, true),
            ("", .both, true),
            ("unknown", .both, true),
        ]
        var failed = false
        for (stored, presence, writeBack) in cases {
            let result = AppPresence.resolve(stored: stored)
            let ok = result.presence == presence && result.needsWriteBack == writeBack
            if !ok { failed = true }
            print("\(ok ? "OK" : "NG") \(stored.map { "\"\($0)\"" } ?? "nil") -> \(result.presence.rawValue) 書き戻し: \(result.needsWriteBack)")
        }
        print(failed ? "失敗" : "すべて OK")
        exit(failed ? 1 : 0)
    }
}
