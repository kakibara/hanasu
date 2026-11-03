import AppKit
import SwiftUI

/// Claude API・キーチェーン・設定の「AI」タブの確認用の CLI モード:
///   Hanasu --claude-test [--model <id>]
///       「接続を試す」と同じ確認（GET /v1/models/{model}）。キーは ANTHROPIC_API_KEY → 設定（キーチェーン）の順
///   Hanasu --keychain-selftest [--keep]
///       名前を変えた一時的な項目（dev.mactypeless.Hanasu.selftest-…）で、保存・末尾 4 文字・読み出し・ACL・削除を確かめる。
///       --keep を付けると項目を残し、サービス名を表示する（別のプログラムから読めるかを試すため）
///   Hanasu --keychain-selftest-delete <サービス名>
///       --keep で残した一時的な項目を消す（selftest- を含む名前だけ）
///   Hanasu --render-ai-settings <出力.png> [--claude]
///       設定の「AI」タブを画像にする。--claude で、音声入力は Gemini・会議は Claude の見た目にする
@MainActor
enum ClaudeCLI {
    static func runIfRequested() {
        let args = CommandLine.arguments
        if args.contains("--claude-test") {
            run { try await testConnection(args: args) }
        }
        if args.contains("--keychain-selftest") {
            exit(keychainSelfTest(keep: args.contains("--keep")) ? 0 : 1)
        }
        if let service = value(after: "--keychain-selftest-delete", in: args) {
            guard service.hasPrefix(Keychain.defaultService + ".selftest-") else {
                print("selftest- の項目だけを消せます")
                exit(1)
            }
            for item in Keychain.Item.allCases { Keychain.delete(item, service: service) }
            print("消しました: \(service)")
            exit(0)
        }
        if let output = value(after: "--render-ai-settings", in: args) {
            renderSettings(to: URL(fileURLWithPath: output), claude: args.contains("--claude"))
        }
    }

    private static func run(_ body: @escaping @MainActor () async throws -> Void) -> Never {
        Task { @MainActor in
            do {
                try await body()
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
                exit(1)
            }
        }
        RunLoop.main.run()
        exit(0)
    }

    // 確かめ方: REQ-COM-020
    private static func testConnection(args: [String]) async throws {
        let settings = AppSettings.shared
        let model = value(after: "--model", in: args) ?? settings.claudeModel
        let env = ProcessInfo.processInfo.environment
        let client: ClaudeClient
        if let key = env["ANTHROPIC_API_KEY"], !key.isEmpty {
            print("キー: 環境変数 ANTHROPIC_API_KEY（\(ClaudeClient.redacted(key))）")
            client = ClaudeClient(apiKey: { key })
        } else {
            print("キー: 設定（キーチェーン）\(Keychain.hint(.claudeAPIKey) ?? "（未設定）")")
            client = ClaudeClient(apiKey: { try Keychain.load(.claudeAPIKey) })
        }
        let started = Date()
        try await client.testConnection(model: model)
        print(String(format: "接続できました（%@ を使えます、%.1f 秒）", model, Date().timeIntervalSince(started)))
    }

    // 確かめ方: REQ-COM-021
    private static func keychainSelfTest(keep: Bool) -> Bool {
        let service = Keychain.defaultService + ".selftest-" + String(UUID().uuidString.prefix(8)).lowercased()
        let item = Keychain.Item.claudeAPIKey
        let fakeKey = "sk-ant-selftest-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        var failures = 0
        func expect(_ ok: Bool, _ label: String) {
            print("\(ok ? "OK" : "NG")  \(label)")
            if !ok { failures += 1 }
        }
        print("サービス名: \(service)")
        expect(!Keychain.exists(item, service: service), "保存する前は項目がない")
        expect(Keychain.save(item, key: fakeKey, service: service), "保存できる")
        expect(Keychain.exists(item, service: service), "保存したあとは項目がある（中身を読まずに分かる）")
        expect(Keychain.hint(item, service: service) == "…" + fakeKey.suffix(4), "末尾 4 文字だけを属性から読める: \(Keychain.hint(item, service: service) ?? "-")")
        do {
            expect(try Keychain.load(item, service: service) == fakeKey, "Hanasu 自身は確認なしで読める")
        } catch {
            expect(false, "読めない: \(error.localizedDescription)")
        }
        expect(Keychain.requiresPassphraseForOtherApps(item, service: service), "ほかのアプリが読もうとするとパスワードを求める ACL で保存された")
        print("ACL:")
        for line in Keychain.describeAccess(item, service: service) { print("  \(line)") }
        if keep {
            print("項目を残しました。消すには: --keychain-selftest-delete \(service)")
        } else {
            expect(Keychain.delete(item, service: service), "削除できる")
            expect(!Keychain.exists(item, service: service), "削除したあとは項目がない")
        }
        print(failures == 0 ? "すべて OK" : "\(failures) 件が NG")
        return failures == 0
    }

    // 確かめ方: REQ-COM-020, REQ-COM-024
    private static func renderSettings(to url: URL, claude: Bool) -> Never {
        _ = NSApplication.shared
        let settings = AppSettings.shared
        let saved = (settings.dictationAIProvider, settings.meetingAIProvider)
        if claude {
            settings.dictationAIProvider = .gemini
            settings.meetingAIProvider = .claude
        }
        let view = AISettingsTab(settings: settings)
            .frame(width: 560, height: 2600)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        // Form の中のスクロールを先頭に戻してから描く（そのままだと途中から描かれる）
        func scrollToTop(_ view: NSView) {
            if let scroll = view as? NSScrollView, let document = scroll.documentView {
                document.scroll(NSPoint(x: 0, y: document.isFlipped ? 0 : document.bounds.height))
            }
            view.subviews.forEach(scrollToTop)
        }
        scrollToTop(hosting)
        hosting.layoutSubtreeIfNeeded()
        if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            print("wrote")
        }
        settings.dictationAIProvider = saved.0
        settings.meetingAIProvider = saved.1
        exit(0)
    }

    private static func value(after flag: String, in args: [String]) -> String? {
        args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
    }
}
