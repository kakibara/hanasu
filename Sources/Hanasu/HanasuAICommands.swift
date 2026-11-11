import Darwin
import Foundation

// 利用者向けの hanasu の AI を使うコマンド（ask・refine・edit）と、辞書だけを当てる dict apply（計画は docs/plans/cli.md の段階 2）。
// 名前が CLI.swift で終わらないので、訳の検査（check-i18n.py）の対象になる。

// 要件: REQ-COM-186, REQ-COM-188
// 設計判断: DEC-COM-185
/// AI の選び方（設定・--ai・--model）と、送る前の確かめ（ポリシー・認証情報・ローカルのサーバー）
enum HanasuAI {
    static let options: Set<String> = ["--ai", "--model"]

    // 要件: REQ-COM-186, REQ-MTG-126
    // 設計判断: DEC-COM-190
    /// hanasu ask・ask_meetings の AI の用途。「AI チャット・質問」を自分で保存した人はそれ、ほかは会議の AI
    /// （既定のままの「AI チャット・質問」はローカルで、hanasu はアプリのローカルの AI のサーバーを共有できないため）
    static func askPurpose(_ settings: AppSettings) -> TextAIPurpose {
        settings.isChatAIProviderSaved ? .chat : .meeting
    }

    struct Choice {
        var provider: TextAIProvider
        var model: String

        var json: [String: Any] { ["provider": provider.rawValue, "model": model] }
    }

    /// --ai・--model があればそれ、なければその用途の設定の AI とモデル
    static func choice(_ args: HanasuArguments, for purpose: TextAIPurpose, settings: AppSettings) throws -> Choice {
        var legacy: [String] = []
        if let raw = args.values["--ai"] {
            guard let provider = TextAIProvider(rawValue: raw.lowercased()) else {
                throw HanasuCommandError(
                    exit: .usage, message: tr("--ai に知らない AI を指定しました: %@", raw),
                    details: [tr("使える値: %@", TextAIProvider.allCases.map(\.rawValue).joined(separator: " / "))])
            }
            legacy += ["--ai", provider.rawValue]
        }
        if let model = args.values["--model"], !model.isEmpty { legacy += ["--model", model] }
        return Choice(provider: TextAIClient.cliProvider(args: legacy, settings: settings, for: purpose),
                      model: TextAIClient.cliModel(args: legacy, settings: settings, for: purpose))
    }

    /// ポリシー・認証情報・ローカルのサーバーを確かめてから、クライアントを作る（まだ何も送らない）
    static func makeClient(_ choice: Choice, for purpose: TextAIPurpose, settings: AppSettings,
                           timeout: TimeInterval) throws -> TextAIClient {
        // 要件: REQ-COM-188
        if let allowed = HanasuPolicy.allowedAIProviders, !allowed.contains(choice.provider.rawValue) {
            throw HanasuCommandError(
                exit: .denied,
                message: tr("管理者のポリシーで、%@ は使えないようにされています（%@）。", choice.provider.name,
                            HanasuPolicy.Key.allowedAIProviders.rawValue),
                details: [allowed.isEmpty ? tr("使える AI はありません。") : tr("使える AI: %@", allowed.joined(separator: " / "))])
        }
        switch choice.provider {
        case .local:
            // 要件: REQ-COM-187
            // 設計判断: DEC-COM-184
            if LocalLLMServer.otherProcessServerRunning() {
                throw HanasuCommandError(
                    exit: .failure, message: tr("Hanasu のアプリがローカルの AI を使っています。"),
                    details: [tr("アプリを終了するか、--ai でほかの AI を選んでください（同じモデルを二重に読み込まないため）。")])
            }
            guard let model = LocalLLMModel(rawValue: choice.model) else {
                throw HanasuCommandError(exit: .usage, message: LocalLLMServer.Failure.unknownModel(choice.model).localizedDescription)
            }
            guard LocalLLMStore.isDownloaded(model) else {
                throw credentials(LocalLLMServer.Failure.modelNotDownloaded(model).localizedDescription)
            }
            guard LocalLLMServer.executableURL != nil else {
                throw credentials(LocalLLMServer.Failure.serverNotFound.localizedDescription)
            }
        case .appleFM:
            let availability = AppleFMAvailability.check()
            if availability.executableURL == nil { throw credentials(availability.reason ?? "") }
        case .gemini, .claude:
            if credentialStatus(choice.provider, settings: settings, read: false).source == nil {
                throw credentials(TextAIError.missingCredentials(choice.provider).localizedDescription)
            }
        }
        do {
            return try TextAIClient.cli(args: ["--ai", choice.provider.rawValue, "--model", choice.model],
                                        settings: settings, for: purpose, timeout: timeout)
        } catch {
            throw mapped(error)
        }
    }

    static func credentials(_ message: String) -> HanasuCommandError {
        HanasuCommandError(exit: .credentials, message: message)
    }

    // 要件: REQ-COM-182
    /// AI の処理の誤りを、終了コードの分かれる誤りにする（認証情報・モデルがなければ 3、知らないモデルは 2、ほかは 1）
    static func mapped(_ error: Error) -> HanasuCommandError {
        if let error = error as? HanasuCommandError { return error }
        switch error {
        case is KeychainError, is TextAIError, is ServiceAccountError:
            return credentials(error.localizedDescription)
        case let failure as LocalLLMServer.Failure:
            switch failure {
            case .unknownModel: return HanasuCommandError(exit: .usage, message: failure.localizedDescription)
            case .modelNotDownloaded, .serverNotFound: return credentials(failure.localizedDescription)
            default: break
            }
        case AppleFMError.unavailable(let reason):
            return credentials(reason)
        default:
            break
        }
        return HanasuCommandError(exit: .failure, message: tr("AI で処理できませんでした: %@", error.localizedDescription))
    }

    /// 認証情報の置き場所。値は持たない
    struct CredentialStatus {
        /// 見つかった置き場所（JSON の値。keychain・serviceAccount・env:<名前>）。なければ nil
        var source: String?
        /// 表示の言語での置き場所
        var label: String?
        /// read のとき、読めなかった理由
        var problem: String?
    }

    /// Claude・Gemini の認証情報を、TextAIClient.cli と同じ順に探す。read なら実際に読んで（値は捨てる）、読めるかを確かめる。
    /// read でなければ、キーチェーンは項目の有無だけを見る（確認のダイアログを出さない）
    static func credentialStatus(_ provider: TextAIProvider, settings: AppSettings, read: Bool) -> CredentialStatus {
        let env = ProcessInfo.processInfo.environment
        func envSet(_ name: String) -> Bool { !(env[name] ?? "").isEmpty }
        func environment(_ name: String) -> CredentialStatus {
            CredentialStatus(source: "env:\(name)", label: tr("環境変数 %@", name))
        }
        func keychain(_ item: Keychain.Item) -> CredentialStatus? {
            guard Keychain.exists(item) else { return nil }
            var status = CredentialStatus(source: "keychain", label: tr("キーチェーン"))
            if read {
                do {
                    if try Keychain.load(item) == nil { return nil }
                } catch {
                    status.problem = error.localizedDescription
                }
            }
            return status
        }
        switch provider {
        case .claude:
            if envSet("ANTHROPIC_API_KEY") { return environment("ANTHROPIC_API_KEY") }
            return keychain(.claudeAPIKey) ?? CredentialStatus()
        case .gemini:
            if envSet("GEMINI_SERVICE_ACCOUNT_JSON") { return environment("GEMINI_SERVICE_ACCOUNT_JSON") }
            switch settings.authMode {
            case .apiKey:
                if let status = keychain(.geminiAPIKey) { return status }
            case .serviceAccount:
                let path = settings.serviceAccountPath.trimmingCharacters(in: .whitespacesAndNewlines)
                if !path.isEmpty {
                    var status = CredentialStatus(source: "serviceAccount", label: tr("サービスアカウント（%@）", path))
                    if read, !FileManager.default.isReadableFile(atPath: (path as NSString).expandingTildeInPath) {
                        status.problem = tr("ファイルを読めません: %@", path)
                    }
                    return status
                }
            }
            if envSet("GEMINI_API_KEY") { return environment("GEMINI_API_KEY") }
            return CredentialStatus()
        case .local, .appleFM:
            return CredentialStatus()
        }
    }
}

// 要件: REQ-DIC-160, REQ-DIC-161, REQ-DIC-162
// 設計判断: DEC-DIC-160
/// 整える文章の受け取り方。位置の引数か stdin のどちらか
enum HanasuTextInput {
    /// 選択を声で編集と同じ上限
    static var maxLength: Int { EditModeSettings.maxSelectionLength }

    static func read(_ positionals: [String]) throws -> String {
        if !positionals.isEmpty {
            if let piped = pendingStandardInput(), !piped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw usage(tr("文章は、引数か標準入力のどちらかで渡してください（両方は使えません）。"))
            }
            return try validated(positionals.joined(separator: " "))
        }
        // 端末で入力を待つと、エージェントやスクリプトから呼んだときに止まったままになる
        if isatty(STDIN_FILENO) != 0 {
            throw usage(tr("文章を、引数か標準入力（パイプ）で渡してください。"))
        }
        let data = FileHandle.standardInput.readDataToEndOfFile()
        return try validated(String(decoding: data, as: UTF8.self))
    }

    static func validated(_ text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw usage(tr("文章が空です。")) }
        guard trimmed.count <= maxLength else {
            throw usage(tr("文章が長すぎます（%@ 文字）。%@ 文字以内にしてください。", "\(trimmed.count)", "\(maxLength)"))
        }
        return trimmed
    }

    /// 引数があるときに、stdin にも文章が来ているか。パイプ・ファイルからのときだけ、待たずに読める分を見る
    /// （端末と /dev/null は見ない。開いたまま何も書かないパイプは、来ていないとみなす）
    private static func pendingStandardInput() -> String? {
        var info = stat()
        guard fstat(STDIN_FILENO, &info) == 0 else { return nil }
        let type = info.st_mode & S_IFMT
        if type == S_IFREG {
            return info.st_size > 0 ? String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self) : nil
        }
        guard type == S_IFIFO || type == S_IFSOCK else { return nil }
        var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        guard poll(&descriptor, 1, 0) > 0, descriptor.revents & Int16(POLLIN) != 0 else { return nil }
        return String(decoding: FileHandle.standardInput.availableData, as: UTF8.self)
    }

    static func usage(_ message: String) -> HanasuCommandError {
        HanasuCommandError(exit: .usage, message: message, details: [tr("使い方は hanasu help で表示できます。")])
    }

    /// --style の値（AppStylePreset の 5 つ。document-polite のように - でつなぐ）
    static func preset(_ raw: String) -> AppStylePreset? {
        switch raw.lowercased() {
        // Optional を返すので、.none だと nil になる（プリセットの「なし」は AppStylePreset.none と書く）
        case "none": AppStylePreset.none
        case "chat": .chat
        case "email": .email
        case "document-polite": .documentPolite
        case "document-plain": .documentPlain
        default: nil
        }
    }
}

enum HanasuAICommands {
    private static let commonFlags: Set<String> = ["--json", "--help", "-h"]

    private static func wantsHelp(_ args: HanasuArguments, _ section: String) -> Bool {
        guard args.flags.contains("--help") || args.flags.contains("-h") else { return false }
        HanasuOutput.out(HanasuHelp.section(for: section) ?? HanasuHelp.full())
        return true
    }

    /// --show-prompt: AI に送る内容を stderr に出す（stdout は結果だけ）
    private static func showPrompt(system: String, user: String) {
        HanasuOutput.err("----- system -----\n\(system)\n----- user -----\n\(user)\n------------------")
    }

    // MARK: - ask

    // 要件: REQ-MTG-126
    // 設計判断: DEC-MTG-124, DEC-MTG-121
    static func runAsk(_ arguments: [String]) async throws -> HanasuExit {
        let args = try HanasuArguments.parse(
            arguments, flags: commonFlags.union(["--show-prompt"]),
            options: HanasuMeetingsCommand.commonOptions.union(HanasuAI.options).union(["--since", "--until"]))
        if wantsHelp(args, "ask") { return .ok }
        let question = args.positionals.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { throw HanasuTextInput.usage(tr("質問を指定してください。")) }
        let period = try HanasuPeriod(args)
        if let since = period.since, let until = period.until, since >= until {
            throw HanasuTextInput.usage(tr("--since は --until より前にしてください。"))
        }

        let settings = AppSettings.shared
        let purpose = HanasuAI.askPurpose(settings)
        let choice = try HanasuAI.choice(args, for: purpose, settings: settings)
        let client = try HanasuAI.makeClient(choice, for: purpose, settings: settings, timeout: 180)
        let loaded = try HanasuMeetingsCommand.load(args)
        let outcome = try await ask(question: question, period: period, choice: choice, client: client,
                                    meetings: loaded.meetings, printPrompt: args.flags.contains("--show-prompt"))
        if args.flags.contains("--json") {
            var json = outcome.json
            json["unreadableMeetingCount"] = loaded.unreadable.count
            try HanasuOutput.json(json)
            return .ok
        }
        let answer = outcome.answer
        let byID = outcome.byID
        let cited = outcome.cited
        var lines = [answer.text, "", tr("AI に渡した会議（* は答えで引用したもの）:")]
        for source in answer.sources {
            let mark = cited.contains(source.meetingID) ? "*" : " "
            let slug = byID[source.meetingID]?.slug ?? Meeting.slug(of: source.meetingID)
            lines.append("  \(mark) M\(source.number)  \(slug)  \(source.title)")
        }
        HanasuOutput.out(lines.joined(separator: "\n"))
        return .ok
    }

    /// ask の結果（hanasu ask と MCP の ask_meetings で同じ）
    struct AskOutcome {
        var answer: MeetingAsk.Answer
        var json: [String: Any]
        var byID: [String: Meeting]
        var cited: Set<String>
    }

    // 要件: REQ-MTG-126, REQ-MTG-127
    // 設計判断: DEC-MTG-124, DEC-MTG-121
    static func ask(question: String, period: HanasuPeriod, choice: HanasuAI.Choice, client: TextAIClient,
                    meetings allMeetings: [Meeting], printPrompt: Bool) async throws -> AskOutcome {
        if let since = period.since, let until = period.until, since >= until {
            throw HanasuTextInput.usage(tr("--since は --until より前にしてください。"))
        }
        // 議事録に使わない発言（除いた発言・オフレコ）は送らない
        let meetings = allMeetings.map(\.withUsedUtterancesOnly)
        var options = MeetingAsk.Options()
        if period.isSpecified {
            // DateInterval は終わりを含むので、--until の時刻（含まない）の直前までにする
            let end = (period.until ?? .distantFuture).addingTimeInterval(-0.001)
            options.period = DateInterval(start: period.since ?? .distantPast, end: end)
        }
        let context = await MeetingAsk.gatherContext(
            question: question, meetings: meetings,
            search: { MeetingSearchIndex.scan(meetings, query: $0, hitsPerMeeting: 50) }, options: options)
        guard !context.sources.isEmpty else {
            throw HanasuCommandError(exit: .notFound, message: tr("質問に使える会議の記録がありません。"))
        }
        if printPrompt { showPrompt(system: MeetingAsk.instruction, user: context.prompt) }

        let answer: MeetingAsk.Answer
        do {
            answer = try await MeetingAsk.answer(context, client: client, model: choice.model)
        } catch {
            throw HanasuAI.mapped(error)
        }
        let byID = Dictionary(meetings.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let cited = Set(answer.cited.map(\.meetingID))
        var periodJSON: Any = NSNull()
        if period.isSpecified {
            periodJSON = ["source": "option", "since": HanasuJSON.optional(period.since.map(HanasuJSON.date)),
                          "until": HanasuJSON.optional(period.until.map(HanasuJSON.date))]
        } else if let derived = context.period {
            periodJSON = ["source": "question", "since": HanasuJSON.date(derived.start), "until": HanasuJSON.date(derived.end)]
        }
        let json: [String: Any] = [
            "question": question,
            "answer": answer.text,
            "ai": choice.json,
            "keywords": answer.keywords,
            "period": periodJSON,
            "sources": answer.sources.compactMap { source -> [String: Any]? in
                guard let meeting = byID[source.meetingID] else { return nil }
                return ["ref": "M\(source.number)", "cited": cited.contains(source.meetingID), "matched": source.matched,
                        "meeting": HanasuMeetingsCommand.summaryJSON(meeting, brief: true)]
            },
        ]
        return AskOutcome(answer: answer, json: json, byID: byID, cited: cited)
    }

    // MARK: - refine

    // 要件: REQ-DIC-160, REQ-DIC-003, REQ-DIC-070, REQ-DIC-082, REQ-DIC-020, REQ-DIC-021, REQ-DIC-013
    // 設計判断: DEC-DIC-160, DEC-DIC-161
    /// 音声入力と同じ整形（翻訳）。音声入力の履歴（DictationHistoryStore）には残さない
    static func runRefine(_ arguments: [String]) async throws -> HanasuExit {
        let args = try HanasuArguments.parse(
            arguments, flags: commonFlags.union(["--show-prompt", "--fallback-raw"]),
            options: HanasuAI.options.union(["--app", "--style", "--translate"]))
        if wantsHelp(args, "refine") { return .ok }

        // 引数の誤りは、文章を読む前に知らせる
        var preset: AppStylePreset?
        if let raw = args.values["--style"] {
            guard let value = HanasuTextInput.preset(raw) else {
                throw HanasuTextInput.usage(tr("--style に知らない文体を指定しました: %@", raw))
            }
            preset = value
        }
        var requestedTranslation: TranslationLanguage?
        if let code = args.values["--translate"] {
            guard let language = TranslationLanguage.cliCode(code) else {
                throw HanasuTextInput.usage(tr("--translate に知らない言語を指定しました: %@", code))
            }
            requestedTranslation = language
        }
        let raw = try HanasuTextInput.read(args.positionals)

        let settings = AppSettings.shared
        let choice = try HanasuAI.choice(args, for: .dictation, settings: settings)
        // --app: そのアプリ向けの文体と既定の出力言語。--style: プリセットを直接選ぶ（--app の文体より優先）
        let app = args.values["--app"].map { cliAppStyle(args: ["--app", $0]) } ?? (name: nil, style: nil)
        var style = app.style
        if let preset {
            style = style ?? AppStyle(bundleID: args.values["--app"] ?? "", name: app.name ?? "", preset: preset)
            style?.preset = preset
        }
        let translation = requestedTranslation ?? style?.outputLanguage.translation
        // 音声入力と同じく、置き換えルールを当ててから送る
        let corrected = settings.userDictionary.apply(to: raw)
        let request = GeminiClient.Request(
            transcript: corrected, model: choice.model,
            appName: settings.sendAppName ? app.name : nil,
            dictionary: settings.dictionaryWords, extraInstructions: settings.extraInstructions,
            dictionaryRules: settings.userDictionary.rules, appStyle: style,
            outputLanguage: settings.refineOutputLanguage)
        if args.flags.contains("--show-prompt") {
            let prompt = translation.map { GeminiClient.translationPrompt(request, to: $0) } ?? GeminiClient.refinePrompt(request)
            showPrompt(system: prompt.system, user: prompt.user)
        }

        let output: String
        var fallback = false
        do {
            let client = try HanasuAI.makeClient(choice, for: .dictation, settings: settings, timeout: 60)
            if let translation {
                output = try await client.translate(request, to: translation)
            } else {
                output = try await client.refine(request)
            }
        } catch {
            output = try fallbackOrThrow(error, args: args, original: corrected)
            fallback = true
        }
        try emit(output, args: args, extra: [
            "ai": choice.json, "fallback": fallback,
            "translation": HanasuJSON.optional(translation?.language.rawValue),
        ])
        return .ok
    }

    // MARK: - edit

    // 要件: REQ-DIC-161, REQ-DIC-050
    // 設計判断: DEC-DIC-160, DEC-DIC-161
    static func runEdit(_ arguments: [String]) async throws -> HanasuExit {
        let args = try HanasuArguments.parse(
            arguments, flags: commonFlags.union(["--show-prompt", "--fallback-raw"]), options: HanasuAI.options)
        if wantsHelp(args, "edit") { return .ok }
        guard let instruction = args.positionals.first?.trimmingCharacters(in: .whitespacesAndNewlines), !instruction.isEmpty else {
            throw HanasuTextInput.usage(tr("書き換えの指示を指定してください。"))
        }
        let selection = try HanasuTextInput.read(Array(args.positionals.dropFirst()))

        let settings = AppSettings.shared
        let choice = try HanasuAI.choice(args, for: .dictation, settings: settings)
        let request = GeminiClient.EditRequest(
            selection: selection, instruction: instruction, model: choice.model,
            appName: nil, dictionary: settings.dictionaryWords)
        if args.flags.contains("--show-prompt") {
            showPrompt(system: GeminiClient.editInstruction, user: GeminiClient.editPrompt(for: request))
        }

        let output: String
        var fallback = false
        do {
            let client = try HanasuAI.makeClient(choice, for: .dictation, settings: settings, timeout: 60)
            output = try await client.editSelection(request)
        } catch {
            output = try fallbackOrThrow(error, args: args, original: selection)
            fallback = true
        }
        try emit(output, args: args, extra: ["ai": choice.json, "fallback": fallback])
        return .ok
    }

    // MARK: - dict apply

    // 要件: REQ-DIC-162, REQ-DIC-070
    /// 辞書の置き換えルールだけを当てる。AI には何も送らない
    static func runDict(_ arguments: [String]) throws -> HanasuExit {
        guard let sub = arguments.first else {
            HanasuOutput.err(HanasuHelp.section(for: "dict") ?? HanasuHelp.full())
            return .usage
        }
        if sub == "--help" || sub == "-h" {
            HanasuOutput.out(HanasuHelp.section(for: "dict") ?? HanasuHelp.full())
            return .ok
        }
        guard sub == "apply" else {
            throw HanasuTextInput.usage(tr("知らないコマンドです: %@", "dict \(sub)"))
        }
        let args = try HanasuArguments.parse(Array(arguments.dropFirst()), flags: commonFlags, options: [])
        if wantsHelp(args, "dict") { return .ok }
        let text = try HanasuTextInput.read(args.positionals)
        try emit(AppSettings.shared.userDictionary.apply(to: text), args: args, extra: [:])
        return .ok
    }

    // MARK: - 共通

    // 設計判断: DEC-DIC-161
    /// AI が失敗したとき。--fallback-raw なら原文を返し（理由は stderr）、なければ誤りを投げる（stdout には何も出さない）。
    /// 使い方の誤りとポリシーで止めたときは、--fallback-raw でも止める
    private static func fallbackOrThrow(_ error: Error, args: HanasuArguments, original: String) throws -> String {
        let mapped = HanasuAI.mapped(error)
        guard args.flags.contains("--fallback-raw"), mapped.exit == .failure || mapped.exit == .credentials else { throw mapped }
        HanasuOutput.err("hanasu: " + mapped.message)
        for line in mapped.details { HanasuOutput.err("  " + line) }
        HanasuOutput.err("hanasu: " + tr("整えられなかったので、整える前の文章を出します（--fallback-raw）。"))
        return original
    }

    private static func emit(_ text: String, args: HanasuArguments, extra: [String: Any]) throws {
        if args.flags.contains("--json") {
            try HanasuOutput.json(extra.merging(["text": text]) { _, new in new })
        } else {
            HanasuOutput.out(text)
        }
    }
}
