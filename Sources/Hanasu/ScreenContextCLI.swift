import AppKit
import SwiftUI

// 画面の文脈の動作確認用の CLI モード:
//   Hanasu --dump-context [秒] [--json]
//     指定の秒数（既定 3 秒）待ってから、前面アプリの文脈を読んで表示する。--json で JSON だけを出す（--context に渡せる）
//   Hanasu --refine-text <文章> --context <文脈ファイル> [--translate] [--ai …] [--model <id>] [--show-prompt]
//     文脈なしと文脈ありで整形（または英訳）して並べる。文脈ファイルは --dump-context --json の出力か、
//     ただのテキスト（カーソルより前の文章として扱う）。JSON に "ocrText"（OCR で読んだ文字そのまま。行ごとに改行）を書くと、
//     アプリと同じ並べ方・上限でスクリーンショットの文字にする（"ocr": {"terms": […], "lines": […]} で直接も書ける）。
//     --show-prompt で、文脈ありのときに AI に送る system と user を出す
//   Hanasu --render-screen-context-settings <出力.png> [--enabled] [--screenshot] [--denied] [--meeting]
//     設定画面の「画面の文脈」の欄を画像にする（--screenshot でスクリーンショットをオン、--denied で画面収録の許可がない見た目、
//     --meeting で会議の記録中の見た目）
//   Hanasu --test-screen-ocr
//     スクリーンショットの文字の自己テスト（語の一覧・並べ方・上限・使うかの判定・<screen_ocr>・文脈に入らないときに外すこと）
//   Hanasu --dump-screen-ocr [秒] [--ai …]
//     指定の秒数（既定 3 秒）待ってから、アプリと同じフィルタで全部の画面を撮って読み、AI に渡す文字を表示する（画面収録の許可が要る）
// 確かめ方: REQ-DIC-040
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
        // 確かめ方: REQ-DIC-041, REQ-DIC-042
        if args.contains("--test-screen-ocr") {
            Task { @MainActor in
                exit(await ScreenSnapshotSelfTest.run() ? 0 : 1)
            }
            RunLoop.main.run()
        }
        // 確かめ方: REQ-DIC-041
        if let index = args.firstIndex(of: "--dump-screen-ocr") {
            let seconds = args.indices.contains(index + 1) ? Double(args[index + 1]) ?? 3 : 3
            Task { @MainActor in
                await dumpScreenOCR(after: seconds, args: args)
                exit(0)
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
        var context = (try? JSONDecoder().decode(ScreenContext.self, from: data))
            ?? ScreenContext(textBefore: String(decoding: data, as: UTF8.self))

        let settings = AppSettings.shared
        let model = TextAIClient.cliModel(args: args, settings: settings, for: .dictation)
        let translation = TranslationLanguage.cli(args)
        // 要件: REQ-DIC-041
        // "ocrText" があれば、アプリと同じ並べ方・上限（--ai の AI の上限）でスクリーンショットの文字にする
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let raw = object["ocrText"] as? String {
            let provider = TextAIClient.cliProvider(args: args, settings: settings, for: .dictation)
            let localModel = LocalLLMModel(rawValue: model) ?? settings.localModel(for: .dictation)
            let lines = raw.split(whereSeparator: \.isNewline).enumerated().map {
                ScreenTextLine(text: String($0.element), display: 0, inTarget: false, y: Double($0.offset) * 20, x: 0)
            }
            let limit = ScreenSnapshotLayout.limit(provider: provider, localModel: localModel)
            context.ocr = ScreenSnapshotLayout.layout(lines, limit: limit)
            print("スクリーンショットの文字: \(provider.name) の上限 \(limit) 文字 → 語 \(context.ocr?.terms.count ?? 0)・行 \(context.ocr?.lines.count ?? 0)・\(context.ocr?.characterCount ?? 0) 文字")
        }

        print("--- 文脈 ---")
        print(context.promptBlock() ?? "（画面の文脈なし）")
        print(context.ocrBlock() ?? "（スクリーンショットの文字なし）")
        let client = try TextAIClient.cli(args: args, settings: settings, for: .dictation)
        for (label, screenContext) in [("文脈なし", nil), ("文脈あり", context)] as [(String, ScreenContext?)] {
            let request = GeminiClient.Request(
                transcript: raw, model: model, appName: context.appName,
                dictionary: settings.dictionaryWords, extraInstructions: settings.extraInstructions,
                screenContext: screenContext,
                // 要件: REQ-DIC-082
                outputLanguage: settings.refineOutputLanguage)
            if screenContext != nil, args.contains("--show-prompt") {
                let prompt = translation.map { GeminiClient.translationPrompt(request, to: $0) } ?? GeminiClient.refinePrompt(request)
                print("--- system ---\n\(prompt.system)\n--- user ---\n\(prompt.user)\n---")
            }
            let started = Date()
            let output = if let translation { try await client.translate(request, to: translation) } else { try await client.refine(request) }
            print(String(format: "[%@ %@ %@ %.1fs] %@", label, translation?.verb ?? "整形", model, Date().timeIntervalSince(started), output))
        }
    }

    // MARK: --dump-screen-ocr

    // 要件: REQ-DIC-041
    // 設計判断: DEC-DIC-181, DEC-DIC-182
    /// アプリと同じフィルタ（Hanasu.app・除外アプリ・いつも除くもの）で撮って読み、AI に渡す文字を出す
    @MainActor
    private static func dumpScreenOCR(after seconds: Double, args: [String]) async {
        print("\(seconds) 秒後に画面を撮ります…")
        try? await Task.sleep(for: .seconds(seconds))
        print("画面収録の許可: \(ScreenRecordingPermission.isGranted ? "あり" : "なし（このプロセスを起動したアプリに許可が必要です）")")
        let settings = AppSettings.shared
        let target = NSWorkspace.shared.frontmostApplication
        let provider = TextAIClient.cliProvider(args: args, settings: settings, for: .dictation)
        let limit = ScreenSnapshotLayout.limit(provider: provider, localModel: settings.localModel(for: .dictation))
        let request = ScreenSnapshotReader.Request(
            targetPID: target?.processIdentifier, excludedApps: ScreenContextSettings.shared.excludedApps,
            languages: ScreenSnapshotReader.languages(localeIdentifier: settings.localeIdentifier))
        print("入力先とみなすアプリ: \(target?.localizedName ?? "-")（\(target?.bundleIdentifier ?? "-")）")
        let started = Date()
        do {
            let lines = try await ScreenSnapshotReader.read(request)
            let elapsed = Date().timeIntervalSince(started)
            let ocr = ScreenSnapshotLayout.layout(lines, limit: limit)
            print("読んだ行: \(lines.count)（画面 \(Set(lines.map(\.display)).count) つ、入力先のウインドウの中 \(lines.filter(\.inTarget).count) 行）")
            print(String(format: "撮影と読み取り: %.2f 秒", elapsed))
            print("AI に渡す（\(provider.name) の上限 \(limit) 文字）: 語 \(ocr.terms.count)・行 \(ocr.lines.count)・\(ocr.characterCount) 文字")
            var context = ScreenContext()
            context.ocr = ocr
            print(context.ocrBlock() ?? "（渡すものなし）")
        } catch {
            print("読めませんでした: \(error.localizedDescription)")
        }
    }

    // MARK: --render-screen-context-settings

    @MainActor
    private static func renderSettings(to url: URL) -> Never {
        _ = NSApplication.shared
        let settings = ScreenContextSettings.shared
        // --enabled でオンの見た目を描く（保存されている設定は描いたあとに戻す）
        let saved = (settings.enabled, settings.useScreenshot)
        if CommandLine.arguments.contains("--enabled") { settings.enabled = true }
        // 要件: REQ-DIC-042
        // --screenshot でスクリーンショットをオン、--denied で画面収録の許可がない見た目、--meeting で会議の記録中
        if CommandLine.arguments.contains("--screenshot") { settings.useScreenshot = true }
        settings.meetingInProgress = CommandLine.arguments.contains("--meeting")
        let view = Form {
            ScreenContextSettingsSection(settings: settings, previewScreenRecordingDenied: CommandLine.arguments.contains("--denied"))
        }
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
        (settings.enabled, settings.useScreenshot) = saved
        exit(0)
    }
}
