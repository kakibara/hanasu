import AppKit
import SwiftUI

// 確かめ方: REQ-DIC-050, REQ-DIC-012
/// 選択を声で編集するモードの、動作確認用の CLI モード:
///   Hanasu --edit-text <選択文> <指示> [--model <id>]   選択文を指示どおりに Gemini で書き換えて表示する
///   Hanasu --render-edit-hud <出力.png> [--processing]  編集モードの HUD を画像にする
///   Hanasu --render-edit-settings <出力.png>            設定画面に足した行を画像にする
/// 認証は --refine-text と同じく、GEMINI_SERVICE_ACCOUNT_JSON、設定画面の認証情報、GEMINI_API_KEY の順に使う。
@MainActor
enum EditModeCLI {
    static func runIfRequested() {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--edit-text"), args.indices.contains(index + 2) {
            let selection = args[index + 1]
            let instruction = args[index + 2]
            Task { @MainActor in
                do {
                    try await edit(selection: selection, instruction: instruction, args: args)
                    exit(0)
                } catch {
                    FileHandle.standardError.write(Data("error: \(error.localizedDescription) (\(error))\n".utf8))
                    exit(1)
                }
            }
            RunLoop.main.run()
        }
        if let index = args.firstIndex(of: "--render-edit-hud"), args.indices.contains(index + 1) {
            _ = NSApplication.shared
            let hud = HUDController()
            hud.model.editBadge = "選択 120 文字"
            if args.contains("--processing") {
                hud.show(.processing)
            } else {
                hud.show(.recording)
            }
            hud.updateTranscript("もっと丁寧な言い方にして")
            try? hud.snapshotPNG()?.write(to: URL(fileURLWithPath: args[index + 1]))
            print("wrote")
            exit(0)
        }
        if let index = args.firstIndex(of: "--render-edit-settings"), args.indices.contains(index + 1) {
            _ = NSApplication.shared
            let view = Form {
                Section("ショートカット") {
                    EditModeShortcutRow(onBeginRecording: {}, onEndRecording: {})
                }
            }
            .formStyle(.grouped)
            .frame(width: 560, height: 200)
            let hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(x: 0, y: 0, width: 560, height: 200)
            let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
                hosting.cacheDisplay(in: hosting.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[index + 1]))
                print("wrote")
            }
            exit(0)
        }
    }

    private static func edit(selection: String, instruction: String, args: [String]) async throws {
        let settings = AppSettings.shared
        let env = ProcessInfo.processInfo.environment
        let auth: GeminiClient.Auth
        if let path = env["GEMINI_SERVICE_ACCOUNT_JSON"] {
            auth = .serviceAccount(try ServiceAccountCredentials.load(path: path), location: settings.vertexLocation)
        } else {
            auth = try GeminiClient.authFromSettings(settings) ?? .apiKey(env["GEMINI_API_KEY"] ?? "")
        }
        let model = args.firstIndex(of: "--model").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? settings.model
        if let error = EditModeController.selectionError(selection) {
            print("[選択エラー] \(error)")
            return
        }
        var client = GeminiClient(auth: auth)
        client.timeout = 60
        let started = Date()
        let output = try await client.editSelection(GeminiClient.EditRequest(
            selection: selection, instruction: instruction, model: model,
            appName: nil, dictionary: settings.dictionaryWords))
        print(String(format: "[編集 %@ %.1fs]\n%@", model, Date().timeIntervalSince(started), output))
    }
}
