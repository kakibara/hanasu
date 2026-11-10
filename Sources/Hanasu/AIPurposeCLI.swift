import Foundation

/// AI の用途と、ローカルの LLM の順番の確認用 CLI（AI もサーバーも呼ばない）
///   Hanasu --test-ai-purposes
///       使い捨ての UserDefaults で、音声入力・会議・AI チャット・質問の AI とモデル（既定と、変えたとき）を確かめる
///   Hanasu --test-local-llm-wait
///       llama-server を起こさずに、違うモデルの処理を待つ・同じモデルは通す・音声入力は待たない・期限・取り消しを確かめる
@MainActor
enum AIPurposeCLI {
    static func runIfRequested(_ args: [String] = CommandLine.arguments) {
        // 確かめ方: REQ-COM-025
        if args.contains("--test-ai-purposes") {
            exit(testPurposes() ? 0 : 1)
        }
        // 確かめ方: REQ-COM-025
        if args.contains("--test-local-llm-wait") {
            Task { @MainActor in
                let ok = await testLocalWait()
                exit(ok ? 0 : 1)
            }
            RunLoop.main.run()
        }
    }

    private final class Checker {
        var failures = 0
        func check(_ name: String, _ condition: Bool) {
            print("\(condition ? "OK  " : "FAIL") \(name)")
            if !condition { failures += 1 }
        }
    }

    // MARK: - 用途ごとの AI とモデル

    private static func testPurposes() -> Bool {
        let c = Checker()
        func fresh() -> (UserDefaults, String) {
            let name = "dev.mactypeless.Hanasu.test-ai-purposes.\(UUID().uuidString)"
            return (UserDefaults(suiteName: name)!, name)
        }

        // 1. 新しく使い始めた人: AI チャット・質問は、独立した既定（ローカルの Gemma）
        do {
            let (defaults, name) = fresh()
            defer { defaults.removePersistentDomain(forName: name) }
            let settings = AppSettings(defaults: defaults, domainName: name)
            c.check("AI チャット・質問の既定の AI はローカル", settings.aiProvider(for: .chat) == .local)
            c.check("AI チャット・質問の既定のローカルのモデルは Gemma 4 E4B", settings.textModel(for: .chat) == LocalLLMModel.gemma4E4B.rawValue)
            c.check("AI チャット・質問で Claude を選んだときの既定は Haiku 5.5", settings.claudeChatModel == "claude-haiku-5-5")
            c.check("AI チャット・質問で Gemini を選んだときの既定は gemini-3.8-flash", settings.geminiChatModel == "gemini-3.8-flash")
            c.check("会議で Claude を選んだときの既定は Sonnet 5.5 のまま", settings.claudeMinutesModel == "claude-sonnet-5-5")
            c.check("新しい項目の既定だけでは「設定が保存されている」と数えない（オンボーディングが出る）",
                    !AppSettings.hasSavedSettings(defaults.persistentDomain(forName: name) ?? [:]))
        }
        // 2. 以前から使っている人（会議を Claude にしていた）: 会議の値を写さない
        do {
            let (defaults, name) = fresh()
            defer { defaults.removePersistentDomain(forName: name) }
            defaults.set("claude", forKey: "meetingTextAIProvider")
            defaults.set("claude-opus-5-5", forKey: "claudeMinutesModel")
            let settings = AppSettings(defaults: defaults, domainName: name)
            c.check("以前から使っている人も、AI チャット・質問はローカル（会議を写さない）", settings.aiProvider(for: .chat) == .local)
            c.check("会議は Claude のまま", settings.aiProvider(for: .meeting) == .claude && settings.textModel(for: .meeting) == "claude-opus-5-5")
            c.check("AI チャット・質問の Claude のモデルは会議を写さない", settings.claudeChatModel == "claude-haiku-5-5")
        }
        // 3. 会議 = Claude Sonnet、AI チャット・質問 = Claude Haiku: 議事録とチャット・質問で送り先が分かれる
        do {
            let (defaults, name) = fresh()
            defer { defaults.removePersistentDomain(forName: name) }
            let settings = AppSettings(defaults: defaults, domainName: name)
            settings.dictationAIProvider = .gemini
            settings.meetingAIProvider = .claude
            settings.claudeMinutesModel = "claude-sonnet-5-5"
            settings.chatAIProvider = .claude
            settings.claudeChatModel = "claude-haiku-5-5"
            c.check("議事録は Sonnet", settings.aiChoice(for: .meeting) == TextAIChoice(provider: .claude, model: "claude-sonnet-5-5"))
            c.check("AI チャット・質問は Haiku", settings.aiChoice(for: .chat) == TextAIChoice(provider: .claude, model: "claude-haiku-5-5"))
            c.check("音声入力は Gemini の音声入力のモデル", settings.aiChoice(for: .dictation) == TextAIChoice(provider: .gemini, model: settings.model))
            // 保存したものを読み直しても同じ
            let reloaded = AppSettings(defaults: defaults, domainName: name)
            c.check("保存して読み直しても同じ", reloaded.aiChoice(for: .chat) == settings.aiChoice(for: .chat)
                    && reloaded.aiChoice(for: .meeting) == settings.aiChoice(for: .meeting))
            // CLI のモデル選び（--ai で AI を変えたとき、その用途のモデル）
            c.check("CLI: --ai claude の AI チャット・質問は claudeChatModel",
                    TextAIClient.cliModel(args: ["--ai", "claude"], settings: settings, for: .chat) == "claude-haiku-5-5")
            c.check("CLI: --ai claude の議事録は claudeMinutesModel",
                    TextAIClient.cliModel(args: ["--ai", "claude"], settings: settings, for: .meeting) == "claude-sonnet-5-5")
        }
        // 4. Gemini とローカル: 用途ごとのモデル
        do {
            let (defaults, name) = fresh()
            defer { defaults.removePersistentDomain(forName: name) }
            let settings = AppSettings(defaults: defaults, domainName: name)
            settings.meetingAIProvider = .gemini
            settings.meetingMinutesModel = "gemini-3.5-flash-lite"
            settings.chatAIProvider = .gemini
            settings.geminiChatModel = "gemini-flash-latest"
            c.check("Gemini: 議事録は meetingMinutesModel、チャット・質問は geminiChatModel",
                    settings.textModel(for: .meeting) == "gemini-3.5-flash-lite" && settings.textModel(for: .chat) == "gemini-flash-latest")
            settings.chatAIProvider = .local
            settings.localChatModel = .qwen35
            settings.meetingAIProvider = .local
            settings.localMeetingModel = .gemma4E4B
            c.check("ローカル: 議事録とチャット・質問で別のモデル",
                    settings.textModel(for: .chat) == LocalLLMModel.qwen35.rawValue && settings.textModel(for: .meeting) == LocalLLMModel.gemma4E4B.rawValue)
            settings.chatAIProvider = .appleFM
            c.check("Apple: モデルは fm の名前", settings.textModel(for: .chat) == AppleFMClient.modelName)
        }
        // 5. 用途による違い
        c.check("待ち時間は、AI チャット・質問も会議と同じ長いほう",
                LocalLLMClient.minimumTimeout(for: .chat) == LocalLLMClient.minimumTimeout(for: .meeting)
                && AppleFMClient.minimumTimeout(for: .chat) == AppleFMClient.minimumTimeout(for: .meeting))
        c.check("ローカルの切り替えを待つのは、会議と AI チャット・質問だけ（音声入力は待たない）",
                !LocalLLMClient.waitsForOtherModel(.dictation) && LocalLLMClient.waitsForOtherModel(.meeting)
                && LocalLLMClient.waitsForOtherModel(.chat))
        c.check("設定画面の並びは 音声入力・会議・AI チャット・質問", TextAIPurpose.allCases == [.dictation, .meeting, .chat])
        // 6. 送り先の表示
        c.check("表示: Claude · Haiku 5.5", TextAIChoice(provider: .claude, model: "claude-haiku-5-5").modelName == "Haiku 5.5")
        c.check("表示: ローカルはモデルの名前", TextAIChoice(provider: .local, model: "gemma-4-e4b").modelName == LocalLLMModel.gemma4E4B.name)
        c.check("外に送るのは Gemini と Claude だけ",
                TextAIChoice(provider: .claude, model: "x").sendsOutside && TextAIChoice(provider: .gemini, model: "x").sendsOutside
                && !TextAIChoice(provider: .local, model: "x").sendsOutside && !TextAIChoice(provider: .appleFM, model: "x").sendsOutside)

        print(c.failures == 0 ? "すべて OK" : "\(c.failures) 件が NG")
        return c.failures == 0
    }

    // MARK: - ローカルの LLM の順番

    private static func testLocalWait() async -> Bool {
        let c = Checker()

        // 判断だけ（LocalLLMGate）
        do {
            var gate = LocalLLMGate()
            let a = UUID(), b = UUID(), d = UUID()
            gate.enqueue(a)
            c.check("動いていなければ、先頭の処理が起動する", gate.decision(for: a, model: .gemma4E4B, serving: nil, waitsForOtherModel: true) == .start)
            gate.admit(a)
            gate.enqueue(b)
            c.check("違うモデルが使われている間は待つ", gate.decision(for: b, model: .qwen35, serving: .gemma4E4B, waitsForOtherModel: true) == .wait)
            c.check("同じモデルならそのまま使う", gate.decision(for: b, model: .gemma4E4B, serving: .gemma4E4B, waitsForOtherModel: true) == .proceed)
            gate.enqueue(d)
            c.check("音声入力は待たずに起動し直す", gate.decision(for: d, model: .lfm25JP, serving: .gemma4E4B, waitsForOtherModel: false) == .start)
            gate.leave(d)
            gate.finish()
            c.check("使っている処理が終われば、先頭の待ちが起動する", gate.decision(for: b, model: .qwen35, serving: .gemma4E4B, waitsForOtherModel: true) == .start)
            c.check("送る前の「待つか」", gate.wouldWait(for: .qwen35, serving: .gemma4E4B, waitsForOtherModel: true)
                    && !gate.wouldWait(for: .qwen35, serving: .gemma4E4B, waitsForOtherModel: false))
        }

        // サーバー（起動は偽）
        let endpoint = LocalLLMServer.Endpoint(baseURL: URL(string: "http://127.0.0.1:9")!, apiKey: "test")
        func makeServer() -> LocalLLMServer {
            LocalLLMServer(fakeLaunch: { _ in
                try await Task.sleep(for: .milliseconds(30))
                return endpoint
            }, pollInterval: .milliseconds(20))
        }
        final class Flag: @unchecked Sendable {
            private let lock = NSLock()
            private var value = false
            func set() { lock.withLock { value = true } }
            var isSet: Bool { lock.withLock { value } }
        }

        // 1. 議事録（Gemma）の間に、チャット（Qwen）と質問（Qwen）が来る: 議事録が終わるまで待ち、止まり合わずに 1 回の起動で両方が進む
        do {
            let server = makeServer()
            _ = try? await server.beginRequest(.gemma4E4B, waitsForOtherModel: true)
            let chatDone = Flag(), askDone = Flag()
            let chat = Task { _ = try? await server.beginRequest(.qwen35, waitsForOtherModel: true); chatDone.set() }
            let ask = Task { _ = try? await server.beginRequest(.qwen35, waitsForOtherModel: true); askDone.set() }
            try? await Task.sleep(for: .milliseconds(200))
            c.check("議事録の間は、違うモデルのチャットと質問が待つ", !chatDone.isSet && !askDone.isSet)
            c.check("送る前の「待つか」が真になる", await server.wouldWait(for: .qwen35, waitsForOtherModel: true))
            await server.finishRequest()
            _ = await chat.value
            _ = await ask.value
            c.check("議事録が終わると、待っていた 2 つが止まり合わずに進む", chatDone.isSet && askDone.isSet)
            let launches = await server.launchCount
            c.check("同じモデルを待っていた 2 つは、起動し直さずに通る（起動は 2 回）", launches == 2)
            await server.finishRequest()
            await server.finishRequest()
        }
        // 2. 音声入力は待たない
        do {
            let server = makeServer()
            _ = try? await server.beginRequest(.gemma4E4B, waitsForOtherModel: true)
            let started = Date()
            _ = try? await server.beginRequest(.lfm25JP, waitsForOtherModel: false)
            let elapsed = Date().timeIntervalSince(started)
            let launches = await server.launchCount
            c.check("音声入力は、ほかの処理の間でもすぐに起動し直す", elapsed < 0.5 && launches == 2)
        }
        // 3. 期限を過ぎたら失敗する
        do {
            let server = makeServer()
            _ = try? await server.beginRequest(.gemma4E4B, waitsForOtherModel: true)
            var busy = false
            do {
                _ = try await server.beginRequest(.qwen35, waitsForOtherModel: true, deadline: Date().addingTimeInterval(0.2))
            } catch LocalLLMServer.Failure.busy {
                busy = true
            } catch {}
            c.check("待ちの期限を過ぎたら「ほかの処理が終わらない」で失敗する", busy)
            await server.finishRequest()
            c.check("期限で抜けた処理は並びに残らない", !(await server.wouldWait(for: .qwen35, waitsForOtherModel: true)))
        }
        // 4. 取り消し（「止める」）で抜ける
        do {
            let server = makeServer()
            _ = try? await server.beginRequest(.gemma4E4B, waitsForOtherModel: true)
            let waiting = Task { () -> Bool in
                do {
                    _ = try await server.beginRequest(.qwen35, waitsForOtherModel: true)
                    return false
                } catch is CancellationError {
                    return true
                } catch {
                    return false
                }
            }
            try? await Task.sleep(for: .milliseconds(100))
            waiting.cancel()
            c.check("取り消すと待つのをやめる", await waiting.value)
            await server.finishRequest()
            c.check("取り消した処理は並びに残らない", !(await server.wouldWait(for: .qwen35, waitsForOtherModel: true)))
        }

        print(c.failures == 0 ? "すべて OK" : "\(c.failures) 件が NG")
        return c.failures == 0
    }
}
