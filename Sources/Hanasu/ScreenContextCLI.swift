import AppKit
import SwiftUI

// 画面の文脈の動作確認用の CLI モード:
//   Hanasu --dump-context [秒] [--json]
//     指定の秒数（既定 3 秒）待ってから、前面アプリの文脈を読んで表示する。--json で JSON だけを出す（--context に渡せる）
//   Hanasu --refine-text <文章> --context <文脈ファイル> [--translate] [--model <id>]
//     文脈なしと文脈ありで整形（または英訳）して並べる。文脈ファイルは --dump-context --json の出力か、
//     ただのテキスト（カーソルより前の文章として扱う）
//   Hanasu --render-screen-context-settings <出力.png>
//     設定画面の「画面の文脈」の欄を画像にする
enum ScreenContextCLI {
    @MainActor
    static func runIfRequested() {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--dump-context") {
            let seconds = args.indices.contains(index + 1) ? Double(args[index + 1]) ?? 3 : 3
            dumpContext(after: seconds, json: args.contains("--json"))
        }
        if let index = args.firstIndex(of: "--refine-text"), args.indices.contains(index + 1),
           let contextIndex = args.firstIndex(of: "--context"), args.indices.contains(contextIndex + 1)
        {
            let text = args[index + 1]
            let path = args[contextIndex + 1]
            Task { @MainActor in
                do {
                    try await compareRefine(text, contextPath: path, args: args)
                    exit(0)
                } catch {
                    FileHandle.standardError.write(Data("error: \(error.localizedDescription) (\(error))\n".utf8))
                    exit(1)
                }
            }
            RunLoop.main.run()
        }
        if let index = args.firstIndex(of: "--render-screen-context-settings"), args.indices.contains(index + 1) {
            renderSettings(to: URL(fileURLWithPath: args[index + 1]))
        }
    }

    // MARK: --dump-context

    @MainActor
    private static func dumpContext(after seconds: Double, json: Bool) -> Never {
        _ = NSApplication.shared
        if !json {
            print(String(format: "%.0f 秒後に前面アプリの文脈を読みます。読みたいアプリの入力欄をクリックしてください…", seconds))
        }
        // 前面アプリの切り替えの通知を受け取れるよう、待つ間もメインのランループを回す
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        guard let target = ScreenContextReader.frontmostTarget() else {
            print("前面アプリを取得できませんでした")
            exit(1)
        }
        let settings = ScreenContextSettings.shared
        if settings.isExcluded(bundleID: target.bundleID, appName: target.appName) {
            print("\(target.appName ?? "-")（\(target.bundleID ?? "-")）は除外するアプリに入っているので読みません")
            exit(0)
        }
        let started = Date()
        let context = ScreenContextReader.read(target)
        let elapsed = Date().timeIntervalSince(started)

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            if let data = try? encoder.encode(context) { print(String(decoding: data, as: UTF8.self)) }
            for note in context.notes { FileHandle.standardError.write(Data("メモ: \(note)\n".utf8)) }
            exit(0)
        }
        print("アクセシビリティの許可: \(AXIsProcessTrusted() ? "あり" : "なし（このプロセスを起動したアプリに許可が必要です）")")
        print("アプリ: \(target.appName ?? "-")（\(target.bundleID ?? "-")）")
        print("ウインドウ: \(context.windowTitle ?? "（取れず）")")
        print("フォーカス: \(context.focusedRole ?? "（取れず）")")
        print("カーソルより前（\(context.textBefore?.count ?? 0) 文字\(context.cursorUnknown == true ? "、カーソル位置は不明" : "")）:")
        print(context.textBefore ?? "")
        print("カーソルより後（\(context.textAfter?.count ?? 0) 文字）:")
        print(context.textAfter ?? "")
        for note in context.notes { print("メモ: \(note)") }
        print(String(format: "読み取り: %.2f 秒", elapsed))
        print("--- Gemini に渡すブロック ---")
        print(context.promptBlock() ?? "（渡すものなし）")
        print("設定: \(settings.enabled ? "オン" : "オフ（アプリではまだ送りません）")")
        exit(0)
    }

    // MARK: --refine-text … --context

    @MainActor
    private static func compareRefine(_ raw: String, contextPath: String, args: [String]) async throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: (contextPath as NSString).expandingTildeInPath))
        let context = (try? JSONDecoder().decode(ScreenContext.self, from: data))
            ?? ScreenContext(textBefore: String(decoding: data, as: UTF8.self))

        let settings = AppSettings.shared
        let env = ProcessInfo.processInfo.environment
        let auth: GeminiClient.Auth
        if let path = env["GEMINI_SERVICE_ACCOUNT_JSON"] {
            auth = .serviceAccount(try ServiceAccountCredentials.load(path: path), location: settings.vertexLocation)
        } else {
            auth = try GeminiClient.authFromSettings(settings) ?? .apiKey(env["GEMINI_API_KEY"] ?? "")
        }
        let model = args.firstIndex(of: "--model").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? settings.model
        let translate = args.contains("--translate")
        let client = GeminiClient(auth: auth)

        print("--- 文脈 ---")
        print(context.promptBlock() ?? "（渡すものなし）")
        for (label, screenContext) in [("文脈なし", nil), ("文脈あり", context)] as [(String, ScreenContext?)] {
            let request = GeminiClient.Request(
                transcript: raw, model: model, appName: context.appName,
                dictionary: settings.dictionaryWords, extraInstructions: settings.extraInstructions,
                screenContext: screenContext)
            let started = Date()
            let output = translate ? try await client.translateToEnglish(request) : try await client.refine(request)
            print(String(format: "[%@ %@ %@ %.1fs] %@", label, translate ? "英訳" : "整形", model, Date().timeIntervalSince(started), output))
        }
    }

    // MARK: --render-screen-context-settings

    @MainActor
    private static func renderSettings(to url: URL) -> Never {
        _ = NSApplication.shared
        let settings = ScreenContextSettings.shared
        // --enabled でオンの見た目を描く（保存されている設定は描いたあとに戻す）
        let saved = settings.enabled
        if CommandLine.arguments.contains("--enabled") { settings.enabled = true }
        let view = Form { ScreenContextSettingsSection(settings: settings) }
            .formStyle(.grouped)
            .frame(width: 560, height: 420)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            print("wrote")
        }
        settings.enabled = saved
        exit(0)
    }
}
