import AppKit
import SwiftUI

// 確認用の CLI モード:
//   Hanasu --render-settings <出力フォルダ> [--pane general|ai|words|appStyles|snippets|meeting|history|commandLine|permissions] [--dark]
//                            [--connect-fixture all|empty]
//     設定のウインドウ（左のサイドバーと右の項目）を、項目ごとに settings-<項目>.png に描き出す。
//     --pane で 1 つだけにできる。設定の値は変えない（前に開いていた項目の記録も変えない）。
//     「AI アプリにつなぐ」は、本物のホームを読まずに架空の状態を描く（--connect-fixture。既定は all）
enum SettingsCLI {
    @MainActor
    static func render(to dir: URL, panes: [SettingsPane], dark: Bool) {
        _ = NSApplication.shared
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // 要件: REQ-MTG-056（残っている録音の件数と合計は、本物の保存先を数えずに固定する）
        SettingsRenderOverrides.meetingAudioEntries = MeetingAudioManagerRender.sampleEntries()
        for pane in panes {
            let view = SettingsView(onOpenMeetingNotes: {}, onBeginShortcutRecording: {}, onEndShortcutRecording: {},
                                    initialPane: pane)
            let window = AppDelegate.makeSettingsWindow(rootView: view)
            if pane == .commandLine {
                // 「AI アプリにつなぐ」の下の節（PATH・MCP のコピー）まで写るように、縦に長く描く（UX-183・UX-195）
                window.setContentSize(NSSize(width: AppDelegate.settingsWindowSize.width, height: 2700))
            }
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
        var fixture = "all"
        if let index = args.firstIndex(of: "--connect-fixture"), args.indices.contains(index + 1) { fixture = args[index + 1] }
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("hanasu-connect-fixture-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        SettingsRenderOverrides.agentConnect = AgentConnectFixture.make(fixture, home: home)
        render(to: URL(fileURLWithPath: args[outputIndex]), panes: panes, dark: args.contains("--dark"))
    }
}

// 要件: REQ-COM-194
/// 「AI アプリにつなぐ」を描くための架空のホーム（UX-195）
enum AgentConnectFixture {
    static let executable = "/Applications/Hanasu.app/Contents/MacOS/Hanasu"

    /// all: つないでいる・別の場所・Hanasu のものでない・読めない・claude がない（フォルダだけの登録もある）。
    /// empty: Claude Desktop と ChatGPT が見つからず、claude はある
    static func make(_ name: String, home: URL) -> (environment: AgentConnect.Environment, executable: String) {
        let fm = FileManager.default
        let support = home.appendingPathComponent("Library/Application Support", isDirectory: true)
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        func write(_ text: String, _ path: String) {
            let url = home.appendingPathComponent(path)
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(text.utf8).write(to: url)
        }
        var installed: Set<String> = []
        var claude: String? = "/usr/local/bin/claude"
        if name != "empty" {
            installed = [AgentConnect.Environment.claudeDesktopBundleID]
            claude = nil
            let config = "Library/Application Support/%@/claude_desktop_config.json"
            write(#"{"mcpServers": {"hanasu": {"command": "\#(executable)", "args": ["mcp"]}}}"#, String(format: config, "Claude"))
            write(#"{"mcpServers": {"hanasu": {"command": "/Users/me/Downloads/Hanasu.app/Contents/MacOS/Hanasu", "args": ["mcp"]}}}"#,
                  String(format: config, "Claude-Personal"))
            write(#"{"mcpServers": {"hanasu": {"command": "npx", "args": ["hanasu-server"]}}}"#, String(format: config, "Claude-Work"))
            write("mcp_servers = { other = { command = \"x\" } }\n", ".codex/config.toml")
            write(#"{"projects": {"/Users/me/work": {"mcpServers": {"hanasu": {}}}}}"#, ".claude.json")
        }
        let environment = AgentConnectSelfTest.fakeEnvironment(home: home, installed: installed, claude: claude)
        return (environment, executable)
    }
}
