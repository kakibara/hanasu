import Foundation

/// ローカルの LLM の確認用の CLI モード:
///   Hanasu --local-llm-list
///       モデルの一覧（大きさ・ダウンロード済みか・置き場所）と、使う llama-server の場所
///   Hanasu --local-llm-download <id | all>
///       モデルをダウンロードし、大きさと SHA-256 を確かめる（設定の「ダウンロード」と同じ）
///   Hanasu --local-llm-delete <id>
///   Hanasu --local-llm-test-fit
///       長い入力の縮め方（LongInputFitter）を、文字数で数える偽のトークン数で確かめる。失敗があれば終了コード 1
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
