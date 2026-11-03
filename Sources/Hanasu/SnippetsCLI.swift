import AppKit
import SwiftUI

// スニペットの動作確認用の CLI モード（main.swift から呼ぶ）:
//   Hanasu --match-snippet <文字起こし> [--snippets <JSON>] [--refine [--translate] [--model <id>]]
//     正規化の結果と、一致したスニペット、入力される文章を出す。
//     スニペットは --snippets の JSON（[{"trigger": "...", "body": "..."}]）、設定に登録したもの、例、の順に使う。
//     --refine を付けると、スニペットの前後の文を Gemini で整形（--translate なら英訳）してつなぐ。
//   Hanasu --render-snippets-settings <出力.png> [--empty]
//     設定画面の「スニペット」タブを例のスニペットで画像にする。--empty で空の状態を描く。
@MainActor
enum SnippetsCLI {
    static func matchSnippet(_ transcript: String, args: [String]) async throws {
        let (snippets, source) = try loadSnippets(args: args)
        print("スニペット（\(source)）:")
        for snippet in snippets {
            print("  『\(snippet.displayName)』 照合する形: \(snippet.phrases.map(SnippetMatcher.normalize).joined(separator: " / "))")
        }
        print("入力: \(transcript)")
        print("正規化: \(SnippetMatcher.candidates(transcript).joined(separator: " / "))")

        guard let match = SnippetMatcher.match(transcript, snippets: snippets) else {
            print("結果: 一致なし（ふだんどおり Gemini で整形します）")
            return
        }
        print("結果: \(match.isWholeUtterance ? "全体が一致（Gemini を呼ばない）" : "部分一致（前後の文だけを整形する）")")
        for part in match.parts {
            switch part {
            case .text(let text): print("  [文] \(text)")
            case .snippet(let snippet): print("  [スニペット『\(snippet.displayName)』]")
            }
        }
        print("HUD: \(match.hudMessage)")
        print("--- 入力される文章（整形なし） ---")
        print(match.assembledWithoutConversion)

        guard args.contains("--refine"), !match.isWholeUtterance else { return }
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
        let request = GeminiClient.Request(
            transcript: "", model: model, appName: nil,
            dictionary: settings.dictionaryWords, extraInstructions: settings.extraInstructions)
        let started = Date()
        let output = try await match.assemble { text in
            var request = request
            request.transcript = text
            return translate ? try await client.translateToEnglish(request) : try await client.refine(request)
        }
        print(String(format: "--- 入力される文章（%@ %@ %.1fs） ---", translate ? "英訳" : "整形", model, Date().timeIntervalSince(started)))
        print(output)
    }

    private static func loadSnippets(args: [String]) throws -> ([Snippet], String) {
        if let index = args.firstIndex(of: "--snippets"), args.indices.contains(index + 1) {
            let data = try Data(contentsOf: URL(fileURLWithPath: args[index + 1]))
            return (try JSONDecoder().decode([Snippet].self, from: data), args[index + 1])
        }
        if !SnippetStore.shared.snippets.isEmpty {
            return (SnippetStore.shared.snippets, "設定に登録したもの")
        }
        return (SnippetStore.samples, "例")
    }

    static func renderSettings(to path: String, empty: Bool) {
        _ = NSApplication.shared
        let store = SnippetStore(snippets: empty ? [] : SnippetStore.samples)
        let view = SnippetsSettingsView(store: store)
            // 設定画面（560×460 の TabView）のタブの中身とほぼ同じ大きさ
            .frame(width: 560, height: 400)
            .background(Color(nsColor: .windowBackgroundColor))
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 560, height: 400)
        // List や TextEditor は AppKit の部品なので、画面外のウインドウに置いて描く
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        hosting.layoutSubtreeIfNeeded()
        if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            print("wrote")
        }
    }
}
