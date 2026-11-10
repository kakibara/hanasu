import AppKit
import SwiftUI

// 確認用の CLI モード:
//   Hanasu --render-settings <出力フォルダ> [--pane general|ai|words|appStyles|snippets|meeting|history|commandLine|permissions] [--dark]
//     設定のウインドウ（左のサイドバーと右の項目）を、項目ごとに settings-<項目>.png に描き出す。
//     --pane で 1 つだけにできる。設定の値は変えない（前に開いていた項目の記録も変えない）
enum SettingsCLI {
    @MainActor
    static func render(to dir: URL, panes: [SettingsPane], dark: Bool) {
        _ = NSApplication.shared
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for pane in panes {
            let view = SettingsView(onOpenMeetingNotes: {}, onBeginShortcutRecording: {}, onEndShortcutRecording: {},
                                    initialPane: pane)
            let window = AppDelegate.makeSettingsWindow(rootView: view)
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.orderBack(nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.8))
            let url = dir.appendingPathComponent("settings-\(pane.rawValue).png")
            if let content = window.contentView, let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                content.cacheDisplay(in: content.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
                print("wrote: \(url.path)")
            }
            window.close()
        }
    }

    @MainActor
    static func run(_ args: [String], outputIndex: Int) {
        var panes = SettingsPane.allCases
        if let index = args.firstIndex(of: "--pane"), args.indices.contains(index + 1) {
            guard let pane = SettingsPane(rawValue: args[index + 1]) else {
                let names = SettingsPane.allCases.map(\.rawValue).joined(separator: " / ")
                FileHandle.standardError.write(Data("error: --pane は \(names) のどれか\n".utf8))
                exit(1)
            }
            panes = [pane]
        }
        render(to: URL(fileURLWithPath: args[outputIndex]), panes: panes, dark: args.contains("--dark"))
    }
}
