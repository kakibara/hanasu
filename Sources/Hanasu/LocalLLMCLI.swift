import AppKit
import Foundation
import SwiftUI

/// ローカルの LLM の確認用の CLI モード:
///   Hanasu --local-llm-list
///       モデルの一覧（大きさ・ダウンロード済みか・置き場所）と、使う llama-server の場所
///   Hanasu --local-llm-download <id | all>
///       モデルをダウンロードし、大きさと SHA-256 を確かめる（設定の「ダウンロード」と同じ）
///   Hanasu --local-llm-delete <id>
///   Hanasu --local-llm-test-fit
///       長い入力の縮め方（LongInputFitter）を、文字数で数える偽のトークン数で確かめる。失敗があれば終了コード 1
///   Hanasu --render-local-model-download <出力.png> [--model <id>] [--fraction 0.42 | --verifying]
///       整形の前にモデルがないとき出す、ダウンロードの進み具合のウインドウの見た目（ダウンロードはしない）
///   Hanasu --test-ai-defaults
///       AI の既定（ローカル）と、以前から使っている人を Gemini のままにする引き継ぎを、使い捨ての UserDefaults で確かめる
///   Hanasu --apple-fm-status
///       Apple の Foundation Models の CLI（fm）が使えるか、使えなければ理由（macOS の版・見つからない・Apple の署名でない）
/// 整形・議事録は、ほかの CLI に `--ai local [--model <id>]` か `--ai apple` を付けて確かめる（--refine-text、--minutes-from-transcript など）。
/// `--ai apple` は、環境変数 HANASU_FM_PATH で偽の fm を指定すると macOS 26 でも動く（渡す引数と長い会議の分け方の確認用）。
// 確かめ方: REQ-COM-030, REQ-COM-031
@MainActor
enum LocalLLMCLI {
    static func runIfRequested(_ args: [String] = CommandLine.arguments) {
        if args.contains("--local-llm-list") {
            list()
            exit(0)
        }
        if let id = value(after: "--local-llm-download", in: args) {
            Task { @MainActor in
                do {
                    let models = id == "all" ? LocalLLMModel.allCases : [try model(id)]
                    for model in models { try await download(model) }
                    exit(0)
                } catch {
                    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
                    exit(1)
                }
            }
            RunLoop.main.run()
        }
        if let id = value(after: "--local-llm-delete", in: args) {
            do {
                let model = try model(id)
                try? FileManager.default.removeItem(at: LocalLLMStore.fileURL(model))
                print("消しました: \(LocalLLMStore.fileURL(model).path)")
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
                exit(1)
            }
        }
        // 確かめ方: REQ-COM-032
        if let output = value(after: "--render-local-model-download", in: args) {
            renderDownloadWindow(
                to: URL(fileURLWithPath: output),
                model: value(after: "--model", in: args).flatMap(LocalLLMModel.init(rawValue:)) ?? .recommended,
                fraction: args.contains("--verifying") ? nil : (value(after: "--fraction", in: args).flatMap(Double.init) ?? 0.42))
        }
        // 確かめ方: REQ-COM-024
        if args.contains("--test-ai-defaults") {
            exit(testAIDefaults() ? 0 : 1)
        }
        if args.contains("--apple-fm-status") {
            let os = ProcessInfo.processInfo.operatingSystemVersion
            let availability = AppleFMAvailability.check()
            print("macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
            if let url = availability.executableURL {
                print("使えます: \(url.path)\(ProcessInfo.processInfo.environment["HANASU_FM_PATH"] == nil ? "" : "（HANASU_FM_PATH。版と署名は見ていません）")")
            } else {
                print("使えません: \(availability.reason ?? "")")
            }
            print("文脈 \(AppleFMClient.contextLength) トークン（未確認の値）。例の見積もり: 「明日の会議の資料です。」= \(AppleFMClient.estimateTokens("明日の会議の資料です。")) トークン、\"Hello, world\" = \(AppleFMClient.estimateTokens("Hello, world")) トークン")
            exit(availability.executableURL == nil ? 1 : 0)
        }
        if args.contains("--local-llm-test-fit") {
            Task { @MainActor in
                exit(await testFit() ? 0 : 1)
            }
            RunLoop.main.run()
        }
    }

    private static func list() {
        for model in LocalLLMModel.allCases {
            let mark = LocalLLMStore.isDownloaded(model) ? "✓" : "-"
            print("\(mark) \(model.rawValue.padding(toLength: 16, withPad: " ", startingAt: 0)) \(model.name)  \(model.sizeLabel)  文脈 \(model.contextLength)  \(model.license)")
        }
        print("置き場所: \(LocalLLMStore.directory.path)")
        print("llama-server: \(LocalLLMServer.executableURL?.path ?? "見つかりません（HANASU_LLAMA_SERVER で指定できます）")")
    }

    private static func download(_ model: LocalLLMModel) async throws {
        if LocalLLMStore.isDownloaded(model) {
            print("ダウンロード済み: \(model.rawValue)")
            return
        }
        print("ダウンロード: \(model.downloadURL.absoluteString)（\(model.sizeLabel)）")
        let started = Date()
        let last = LastPrinted()
        try await LocalLLMStore.download(model) { fraction in
            guard let fraction else {
                print("SHA-256 を確かめています…")
                return
            }
            let percent = Int(fraction * 100)
            if last.advance(to: percent / 10) { print("  \(percent)%") }
        }
        print(String(format: "確かめました: %@（%.0f 秒）", LocalLLMStore.fileURL(model).path, Date().timeIntervalSince(started)))
    }

    private final class LastPrinted: @unchecked Sendable {
        private let lock = NSLock()
        private var step = -1
        func advance(to value: Int) -> Bool {
            lock.withLock {
                guard value > step else { return false }
                step = value
                return true
            }
        }
    }

    // MARK: - モデルがないときのダウンロードのウインドウ・AI の既定

    private static func renderDownloadWindow(to url: URL, model: LocalLLMModel, fraction: Double?) -> Never {
        _ = NSApplication.shared
        LocalLLMStore.shared.showDownloadingForRendering(model, fraction: fraction)
        let hosting = NSHostingView(rootView: LocalModelDownloadView(model: model, work: "整形")
            .background(Color(nsColor: .windowBackgroundColor)))
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { exit(1) }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        do {
            try rep.representation(using: .png, properties: [:])?.write(to: url)
            print("書き出しました: \(url.path)")
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    /// 使い捨ての UserDefaults で、新しく使い始めた人・以前から使っている人・2 回目の起動の AI の選択を確かめる
    private static func testAIDefaults() -> Bool {
        var failures = 0
        func check(_ name: String, _ condition: Bool) {
            print("\(condition ? "OK  " : "FAIL") \(name)")
            if !condition { failures += 1 }
        }
        func fresh() -> (UserDefaults, String) {
            let name = "dev.mactypeless.Hanasu.test-ai-defaults.\(UUID().uuidString)"
            return (UserDefaults(suiteName: name)!, name)
        }

        // 1. 新しく使い始めた人: 何も書かない（既定のローカルに従う）。印だけ書く
        do {
            let (defaults, name) = fresh()
            defer { defaults.removePersistentDomain(forName: name) }
            AppSettings.preserveAIProviderForExistingUsers(defaults, domainName: name)
            check("新しく使い始めた人の音声入力の AI は保存しない", defaults.string(forKey: "dictationTextAIProvider") == nil)
            check("新しく使い始めた人の会議の AI は保存しない", defaults.string(forKey: "meetingTextAIProvider") == nil)
            check("印を書く", defaults.object(forKey: AppSettings.aiProviderDefaultsVersionKey) != nil)
            check("印だけでは「設定が保存されている」と数えない",
                  !AppSettings.hasSavedSettings(defaults.persistentDomain(forName: name) ?? [:]))
            // 2 回目の起動（オンボーディングを閉じて、何かの設定を保存したあと）でも Gemini を書かない
            defaults.set(true, forKey: "playSounds")
            AppSettings.preserveAIProviderForExistingUsers(defaults, domainName: name)
            check("2 回目の起動でも AI は保存しない", defaults.string(forKey: "dictationTextAIProvider") == nil)
        }
        // 2. 以前から使っている人（AI を選んでいない）: Gemini を書く
        do {
            let (defaults, name) = fresh()
            defer { defaults.removePersistentDomain(forName: name) }
            defaults.set("ja-JP", forKey: "localeIdentifier")
            defaults.set(true, forKey: "NSSomeSystemKey")
            AppSettings.preserveAIProviderForExistingUsers(defaults, domainName: name)
            check("以前から使っている人の音声入力は Gemini のまま", defaults.string(forKey: "dictationTextAIProvider") == "gemini")
            check("以前から使っている人の会議は Gemini のまま", defaults.string(forKey: "meetingTextAIProvider") == "gemini")
        }
        // 3. 以前から使っていて、片方を選んでいる人: 選んだほうは変えない
        do {
            let (defaults, name) = fresh()
            defer { defaults.removePersistentDomain(forName: name) }
            defaults.set("claude", forKey: "meetingTextAIProvider")
            AppSettings.preserveAIProviderForExistingUsers(defaults, domainName: name)
            check("選んでいない音声入力は Gemini", defaults.string(forKey: "dictationTextAIProvider") == "gemini")
            check("選んだ会議（Claude）は変えない", defaults.string(forKey: "meetingTextAIProvider") == "claude")
        }
        // 4. システムのキーだけがある（初回の起動で AppKit が先に書いた）: 新しく使い始めた人として扱う
        do {
            let (defaults, name) = fresh()
            defer { defaults.removePersistentDomain(forName: name) }
            defaults.set(true, forKey: "NSWindow Frame Hanasu")
            defaults.set(1, forKey: "AppleSomething")
            AppSettings.preserveAIProviderForExistingUsers(defaults, domainName: name)
            check("システムのキーだけなら AI は保存しない", defaults.string(forKey: "dictationTextAIProvider") == nil)
        }
        print(failures == 0 ? "すべて OK" : "\(failures) 件が NG")
        return failures == 0
    }

    private static func model(_ id: String) throws -> LocalLLMModel {
        guard let model = LocalLLMModel(rawValue: id) else { throw LocalLLMServer.Failure.unknownModel(id) }
        return model
    }

    // MARK: - 長い入力の縮め方

    /// 2 文字を 1 トークンと数える偽の数え方で、LongInputFitter の分け方・まとめ方・省き方を確かめる
    private static func testFit() async -> Bool {
        var failures = 0
        func check(_ name: String, _ condition: Bool) {
            print("\(condition ? "OK  " : "FAIL") \(name)")
            if !condition { failures += 1 }
        }
        let count: (String) async throws -> Int = { ($0.count + 1) / 2 }
        let summarizedParts = Counter()
        func fitter(context: Int, output: Int) -> LongInputFitter {
            LongInputFitter(contextLength: context, maxOutputTokens: output, countTokens: count) { part, index, total in
                summarizedParts.add()
                // 部分の 1 行目だけを要点として返す（10 分の 1 くらいに縮む）
                return "- 部分 \(index)/\(total): " + String(part.split(separator: "\n").first?.prefix(40) ?? "")
            }
        }
        do {
            // 1. 入るならそのまま
            let short = "<transcript>\n[00:01] 自分: こんにちは\n</transcript>"
            check("入る入力はそのまま", try await fitter(context: 4096, output: 1024).fit(system: "指示", userText: short) == short)

            // 2. 議事録（<transcript> が 1 つ）は部分ごとの要点に置き換える
            let lines = (0..<600).map { String(format: "[%02d:%02d] 話者%d: ", $0 / 60, $0 % 60, $0 % 3 + 1) + String(repeating: "議題について話しました。", count: 4) }
            let header = "会議: 定例\n日時: 2026/11/04\n\n<user_notes>\nメモ\n</user_notes>\n\n"
            let long = header + "<transcript>\n" + lines.joined(separator: "\n") + "\n</transcript>"
            let f = fitter(context: 8192, output: 3072)
            let fitted = try await f.fit(system: "議事録の指示", userText: long)
            let tokens = try await count("議事録の指示") + count(fitted)
            check("議事録は文脈に入る（\(tokens) ≤ \(8192 - 3072 - LongInputFitter.margin)）", tokens <= 8192 - 3072 - LongInputFitter.margin)
            check("議事録は要点に置き換える（\(summarizedParts.value) 部分）", fitted.contains(LongInputFitter.summarizedNote) && summarizedParts.value >= 2)
            check("メモと見出しは残す", fitted.hasPrefix(header + "<transcript>\n") && fitted.hasSuffix("\n</transcript>"))
            check("部分は時刻の順", fitted.range(of: "部分 1/").map { a in fitted.range(of: "部分 2/").map { a.lowerBound < $0.lowerBound } ?? false } ?? false)

            // 3. <transcript> のない長い入力（会議への質問など）は後ろを省く
            let question = "質問: 先週の定例で何が決まった？\n" + String(repeating: "<meeting>記録</meeting>\n", count: 2000)
            let cut = try await fitter(context: 4096, output: 1024).fit(system: "質問の指示", userText: question)
            let cutTokens = try await count("質問の指示") + count(cut)
            check("ほかの入力は後ろを省く（\(cutTokens) ≤ \(4096 - 1024 - LongInputFitter.margin)）",
                  cut.hasSuffix(LongInputFitter.omittedNote) && cutTokens <= 4096 - 1024 - LongInputFitter.margin && cut.hasPrefix("質問: 先週"))

            // 4. <transcript> が 2 つある入力（会議への質問で複数の会議）は分けずに省く
            let two = "<transcript>\n" + String(repeating: "あ", count: 20000) + "\n</transcript>\n<transcript>\nい\n</transcript>"
            check("<transcript> が 2 つなら分けない", LongInputFitter.splitTranscript(two) == nil)

            // 5. 1 行がとても長くても、部分の大きさに入るよう分ける
            let oneLine = String(repeating: "長い発言", count: 5000)
            let chunks = try await fitter(context: 2048, output: 512).split(oneLine, maxTokens: 500)
            var allFit = true
            for chunk in chunks where try await count(chunk) > 500 { allFit = false }
            check("1 行が長くても分ける（\(chunks.count) 部分）", chunks.count >= 2 && allFit && chunks.joined() == oneLine)
        } catch {
            check("例外: \(error)", false)
        }
        print(failures == 0 ? "すべて合格" : "\(failures) 件の失敗")
        return failures == 0
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func add() { lock.withLock { count += 1 } }
        var value: Int { lock.withLock { count } }
    }

    private static func value(after flag: String, in args: [String]) -> String? {
        args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
    }
}
