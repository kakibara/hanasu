import AppKit
import AVFoundation
import SwiftUI

// 動作確認用の CLI モード:
//   Hanasu --transcribe-file <音声ファイル> [--engine apple|whisper|gemini|dictation|speech] [--refine [--translate] [--model <id>]]
//   （Whisper / Gemini の確認の詳細は TranscriptionEngineCLI.swift）
//   Hanasu --refine-text <文章> [--translate | --translate-to en|ja] [--ai gemini|claude|local] [--model <id>] [--app <bundle id>] [--show-prompt] [--show-request] [--dictionary <辞書ファイル>]
// --refine を付けると AI での整形も行い、--translate を付けると整形の代わりに英訳する（--translate-to ja なら日本語に訳す）。
// --app を付けると、そのアプリ向けの文体ルール（設定の「アプリ別」）で整形する。既定の出力言語が English（日本語）なら、その言語に訳す。
// --show-prompt を付けると、AI に送る user content も表示する。
// --ai gemini|claude|local で AI を選ぶ（省くと設定の「音声入力」の AI）。--model で、その AI のモデルを変える（local は LocalLLMModel の id）。
// --show-request を付けると、Claude に送るリクエスト（ヘッダーと JSON。キーの値は伏せる）を表示し、送らずに終える。
// 認証: Gemini は GEMINI_SERVICE_ACCOUNT_JSON（サービスアカウント JSON のパス）、設定画面の認証情報、GEMINI_API_KEY の順。
//       Claude は ANTHROPIC_API_KEY、設定（キーチェーン）の順。
@MainActor
func cliRefine(_ raw: String, args: [String]) async throws {
    let settings = AppSettings.shared
    let model = TextAIClient.cliModel(args: args, settings: settings, for: .dictation)
    let app = cliAppStyle(args: args)
    // 確かめ方: REQ-DIC-013
    // --translate（英訳）/ --translate-to <言語のコード（en、ja、ko …）>。アプリ別の既定の出力言語が翻訳なら、その言語に翻訳する
    let translation = TranslationLanguage.cli(args) ?? app.style?.outputLanguage.translation
    // 音声入力と同じく、置き換えルールを当ててから送る（--dictionary <ファイル> で辞書を差し替えられる）
    let dictionary = try DictionaryCLI.dictionary(from: args)
    let request = GeminiClient.Request(
        transcript: dictionary.apply(to: raw), model: model, appName: app.name,
        dictionary: dictionary.spellings, extraInstructions: settings.extraInstructions,
        dictionaryRules: dictionary.rules, appStyle: app.style,
        // 要件: REQ-DIC-082
        outputLanguage: settings.refineOutputLanguage)
    if args.contains("--show-prompt") {
        var shown = request
        if let translation, !translation.keepsExtraRules { shown.extraInstructions = "" }  // translationPrompt と同じく、和訳（プロンプトの言語が日本語）のほかの翻訳では共通の追加ルールを外す
        print(GeminiClient.userPrompt(for: shown, translation: translation))
    }
    // 確かめ方: REQ-COM-020
    if args.contains("--show-request") {
        let prompt = translation.map { GeminiClient.translationPrompt(request, to: $0) } ?? GeminiClient.refinePrompt(request)
        let env = ProcessInfo.processInfo.environment
        let key = env["ANTHROPIC_API_KEY"].flatMap { $0.isEmpty ? nil : $0 } ?? (try? Keychain.load(.claudeAPIKey)) ?? nil
        print(ClaudeClient.describeRequest(system: prompt.system, userText: prompt.user, model: model, effort: .low, apiKey: key))
        return
    }
    let client = try TextAIClient.cli(args: args, settings: settings, for: .dictation)
    let started = Date()
    let output = if let translation { try await client.translate(request, to: translation) } else { try await client.refine(request) }
    print(String(format: "[%@ %@ %@ %.1fs] %@", translation?.verb ?? "整形", client.provider.name, model, Date().timeIntervalSince(started), output))
}

// 要件: REQ-COM-180, REQ-COM-183
// 設計判断: DEC-COM-180
// 利用者向けの hanasu コマンド（hanasu meetings list など。HanasuCommand.swift）。サブコマンドにも -- のオプションが付くので、
// 下の「-- で始まる引数があれば表示の言語を日本語にする」判定とプロンプトの言語の読み取りより前に振り分ける。
// アプリ（AppDelegate）は起動しないので、起動時の処理（記録中の会議を「失敗」にする）も通らない
if HanasuCommand.handles(CommandLine.arguments) {
    HanasuCommand.main(CommandLine.arguments)
}

// 設計判断: DEC-COM-063
// アプリ・CLI を終えるとき（exit も NSApp の終了も）に、起動したローカルの LLM のサーバーを止める
// 要件: REQ-COM-061
// CLI では --prompt-language <言語>（en、zh-CN など）でプロンプトの言語を変えられる（省くと設定の文字起こしの言語）
PromptLanguage.override = PromptLanguage.cli(CommandLine.arguments)
// 要件: REQ-COM-060
// 設計判断: DEC-COM-166
// 開発用の CLI（-- で始まる引数があるとき）の出力は訳さないので、表示の言語は日本語にする。
// --ui-language <言語> で変えられる（画面を PNG にする CLI で、ほかの言語の見た目を確かめるとき）。対応していない言語なら止める
let cliFlags = CommandLine.arguments.dropFirst().filter { $0.hasPrefix("--") }
if let index = CommandLine.arguments.firstIndex(of: "--ui-language") {
    let value = CommandLine.arguments.indices.contains(index + 1) ? CommandLine.arguments[index + 1] : ""
    guard let language = PromptLanguage(rawValue: value) ?? PromptLanguage.supported(localeIdentifier: value) else {
        FileHandle.standardError.write(Data("error: --ui-language は \(PromptLanguage.allCases.map(\.rawValue).joined(separator: "|")) のどれか（\(value) は対応していない）\n".utf8))
        exit(2)
    }
    UILanguage.override = language
} else if !cliFlags.isEmpty {
    UILanguage.override = .ja
}
// 自己テストが確かめるプロンプトは日本語のもの（--test-… / --…-test… / --…selftest。-- で始まる引数だけを見る）
if cliFlags.contains(where: { $0.hasPrefix("--test-") || $0.contains("-test") || $0.hasSuffix("selftest") }) {
    PromptLanguage.override = PromptLanguage.override ?? .ja
}

atexit { LocalLLMServer.terminateRunningServer() }
// アップデートの確認（--update-selftest / --check-update / --verify-update / --download-update / --render-update-progress）。AppUpdateCLI.swift の AppUpdateCLI
MainActor.assumeIsolated { AppUpdateCLI.runIfRequested() }
// ローカルの LLM の確認（--local-llm-list / --local-llm-download / --local-llm-delete / --local-llm-test-fit）。LocalLLMCLI.swift
MainActor.assumeIsolated { LocalLLMCLI.runIfRequested() }
// AI の用途とローカルの LLM の順番の確認（--test-ai-purposes / --test-local-llm-wait）。AIPurposeCLI.swift
MainActor.assumeIsolated { AIPurposeCLI.runIfRequested() }

// 文字起こしのエンジンの確認（--download-whisper / --render-engine-settings）。TranscriptionEngineCLI.swift
MainActor.assumeIsolated { TranscriptionEngineCLI.runIfRequested() }
// 音声入力のマイクの確認（--list-dictation-microphones / --render-dictation-mic-settings / --test-dictation-mic-switch）。DictationMicrophoneCLI.swift
MainActor.assumeIsolated { DictationMicrophoneCLI.runIfRequested() }
// 「AI アプリにつなぐ」の実機の確認（--agent-connect-list / --agent-connect <番号> connect|disconnect）。AgentConnectSelfTest.swift の AgentConnectCLI
MainActor.assumeIsolated { AgentConnectCLI.runIfRequested() }
// Claude API・キーチェーン・設定の「AI」の確認（--claude-test / --keychain-selftest / --render-ai-settings）。ClaudeCLI.swift
MainActor.assumeIsolated { ClaudeCLI.runIfRequested() }
// 選択を声で編集するモードの確認（--edit-text / --render-edit-hud / --render-edit-settings）。中身は EditModeCLI.swift
MainActor.assumeIsolated { EditModeCLI.runIfRequested() }
// 画面の文脈の確認（--dump-context、--refine-text … --context）。該当しなければ何もしない
MainActor.assumeIsolated { ScreenContextCLI.runIfRequested() }
// 入力できる場所がないときの確認（--test-paste-target / --probe-paste-target / --render-paste-fallback[-settings]）。PasteFallbackCLI.swift
MainActor.assumeIsolated { PasteFallbackCLI.runIfRequested() }
// 翻訳する言語の設定の確認（--render-translation-settings）。TranslationSettingsView.swift
MainActor.assumeIsolated { TranslationSettingsCLI.runIfRequested() }
// ユーザー辞書の確認（--apply-dictionary / --test-dictionary / --suggest-dictionary / --render-dictionary-settings）。
// 使い方は DictionaryCLI.swift を参照
if DictionaryCLI.handles(CommandLine.arguments) {
    MainActor.assumeIsolated { DictionaryCLI.run(CommandLine.arguments) }
}

// 確かめ方: REQ-COM-061
// AI に送るプロンプトを全部表示する（PromptsCLI.swift。--prompt-language <言語> でその言語）
if CommandLine.arguments.contains("--show-prompts") {
    MainActor.assumeIsolated { PromptsCLI.run() }
    exit(0)
}

// 確かめ方: REQ-DIC-003, REQ-DIC-010, REQ-DIC-020, REQ-DIC-021, REQ-COM-020
if let index = CommandLine.arguments.firstIndex(of: "--refine-text"),
   CommandLine.arguments.indices.contains(index + 1)
{
    let args = CommandLine.arguments
    Task { @MainActor in
        do {
            try await cliRefine(args[index + 1], args: args)
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription) (\(error))\n".utf8))
            exit(1)
        }
    }
    RunLoop.main.run()
}

// 確かめ方: REQ-COM-001
if let index = CommandLine.arguments.firstIndex(of: "--transcribe-file"),
   CommandLine.arguments.indices.contains(index + 1)
{
    let args = CommandLine.arguments
    let url = URL(fileURLWithPath: args[index + 1])
    Task { @MainActor in
        do {
            let settings = AppSettings.shared
            let (transcription, engine) = TranscriptionEngineCLI.parseEngine(args)
            let raw: String
            let started = Date()
            if transcription == .apple {
                let recognizer = SpeechRecognizer()
                recognizer.onAssetDownloadProgress = { print(String(format: "downloading model… %.0f%%", $0 * 100)) }
                raw = try await recognizer.transcribeFile(at: url, localeIdentifier: settings.localeIdentifier, engine: engine)
            } else {
                raw = try await TranscriptionEngineCLI.transcribeFile(url, engine: transcription)
            }
            let label = transcription == .apple ? engine.rawValue
                : transcription == .whisper ? "whisper \(settings.whisperModel.rawValue)" : "gemini \(settings.geminiTranscriptionModel)"
            print(String(format: "[認識 %@ %.1fs] %@", label, Date().timeIntervalSince(started), raw))
            if args.contains("--refine") {
                try await cliRefine(raw, args: args)
            }
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription) (\(error))\n".utf8))
            exit(1)
        }
    }
    RunLoop.main.run()
}

// オーディオ機器の一覧:  Hanasu --list-audio-devices
// 確かめ方: REQ-MTG-002
if CommandLine.arguments.contains("--list-audio-devices") {
    for device in AudioDevices.all() {
        print("\(device.name)\t入力 \(device.inputChannels)ch / 出力 \(device.outputChannels)ch"
              + "\t\(AudioDevices.nominalSampleRate(device.id).map { "\(Int($0))Hz" } ?? "-")\t\(device.uid)")
    }
    print("既定の出力: \(AudioDevices.defaultOutputUID ?? "-")")
    // 会議の記録と同じ方法でマイクのエンジンを作り、形式を読めるか確かめる
    for uid in [""] + AudioDevices.inputs.map(\.uid) {
        let engine = MeetingRecorder.makeMicEngine(inputDeviceUID: uid)
        let format = engine.inputNode.inputFormat(forBus: 0)
        print("マイク \(uid.isEmpty ? "（システムの設定）" : uid): \(Int(format.sampleRate))Hz \(format.channelCount)ch")
    }
    exit(0)
}

// 会議の自動検出の確認:
//   Hanasu --list-audio-processes      オーディオを使っているプロセスの一覧（bundle ID、入力中・出力中）
//   Hanasu --watch-audio-processes     変化を待って表示する（Ctrl-C で終了）
//   Hanasu --render-meeting-suggestion <出力.png> [--stop] [--app zoom|teams|slack|webex|facetime|chrome|safari|arc|edge]
//   Hanasu --simulate-meeting-detection  検出と記録の状態を台本どおりに動かし、提案の出かたを確かめる
//   Hanasu --render-meeting-detection-settings <出力.png>  設定の「会議の自動検出」欄
//   Hanasu --check-meeting-title       ウインドウのタイトルから会議の名前を取り出す規則の確認
//   Hanasu --detect-meeting-title      今開いている会議アプリから会議の名前を読む（アクセシビリティの許可が要る）
if CommandLine.arguments.contains("--list-audio-processes") {
    MainActor.assumeIsolated { MeetingDetectorCLI.listProcesses() }
    exit(0)
}
if CommandLine.arguments.contains("--watch-audio-processes") {
    MainActor.assumeIsolated { MeetingDetectorCLI.watch() }
}
// 確かめ方: REQ-MTG-009
if CommandLine.arguments.contains("--simulate-meeting-detection") {
    MainActor.assumeIsolated { MeetingDetectorCLI.simulate() }
}
if CommandLine.arguments.contains("--check-meeting-title") {
    MainActor.assumeIsolated { MeetingDetectorCLI.checkTitles() }
}
if CommandLine.arguments.contains("--detect-meeting-title") {
    MainActor.assumeIsolated { MeetingDetectorCLI.detectTitleNow() }
}
if let index = CommandLine.arguments.firstIndex(of: "--render-meeting-suggestion"),
   CommandLine.arguments.indices.contains(index + 1)
{
    MainActor.assumeIsolated { MeetingDetectorCLI.renderSuggestion(to: CommandLine.arguments[index + 1], args: CommandLine.arguments) }
    exit(0)
}
if let index = CommandLine.arguments.firstIndex(of: "--render-meeting-detection-settings"),
   CommandLine.arguments.indices.contains(index + 1)
{
    MainActor.assumeIsolated { MeetingDetectorCLI.renderSettings(to: CommandLine.arguments[index + 1]) }
    exit(0)
}

// 会議ノートの機器の選択欄を画像にする（見た目の確認用）:  Hanasu --render-device-pickers <出力.png>
if let index = CommandLine.arguments.firstIndex(of: "--render-device-pickers"),
   CommandLine.arguments.indices.contains(index + 1)
{
    MainActor.assumeIsolated {
        _ = NSApplication.shared
        let view = VStack(spacing: 10) {
            MeetingDevicePickers(compact: true)
            Button {} label: { Label("会議の記録を開始", systemImage: "record.circle").frame(maxWidth: .infinity) }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
        }
        .padding(10)
        .frame(width: 260)
        .background(Color(nsColor: .windowBackgroundColor))
        // メニュー型の Picker は AppKit の部品なので、画面外のウインドウに置いて描く
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            print("wrote")
        }
    }
    exit(0)
}

// 設定のウインドウを項目ごとに画像にする（見た目の確認用）:
//   Hanasu --render-settings <出力フォルダ> [--pane <項目>] [--dark]。SettingsCLI.swift
if let index = CommandLine.arguments.firstIndex(of: "--render-settings"),
   CommandLine.arguments.indices.contains(index + 1)
{
    MainActor.assumeIsolated {
        SettingsCLI.run(CommandLine.arguments, outputIndex: index + 1)
    }
    exit(0)
}

// 設定の「アプリ別」を画像にする（見た目の確認用）:  Hanasu --render-app-styles <出力.png> [--expanded]
// 確かめ方: REQ-DIC-020
if let index = CommandLine.arguments.firstIndex(of: "--render-app-styles"),
   CommandLine.arguments.indices.contains(index + 1)
{
    MainActor.assumeIsolated {
        renderAppStylesPNG(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]),
                           expandedFirst: CommandLine.arguments.contains("--expanded"))
    }
    exit(0)
}

// 音声入力の HUD を画像にする（見た目の確認用）:  Hanasu --render-hud <出力.png> [--translate | --translate-to en|ja] [--languages en,ja] [--engine whisper|gemini [--processing]] [--screenshot on|off|inactive]
// --engine whisper|gemini は、録音を止めてからまとめて文字起こしするときの見た目（音量の目安）。--processing で文字起こし中
// --screenshot は、画面収録を許可しているときのスクリーンショットのボタン（inactive は「この録音では使われない」見た目）
// 確かめ方: REQ-DIC-002, REQ-DIC-011, REQ-DIC-012, REQ-DIC-042
if let index = CommandLine.arguments.firstIndex(of: "--render-hud"),
   CommandLine.arguments.indices.contains(index + 1)
{
    MainActor.assumeIsolated {
        _ = NSApplication.shared
        let hud = HUDController()
        let (engine, _) = TranscriptionEngineCLI.parseEngine(CommandLine.arguments)
        hud.model.batchEngine = engine.isLive ? nil : engine
        if engine.isLive || CommandLine.arguments.contains("--processing") {
            hud.updateTranscript("明日の会議なんですけど、資料は Google スライドで作ったものを使います")
        }
        hud.model.transcribing = CommandLine.arguments.contains("--processing")
        hud.show(CommandLine.arguments.contains("--processing") ? .processing : .recording)
        hud.model.level = 0.05
        // 確かめ方: REQ-DIC-011, REQ-DIC-013
        // --translate / --translate-to en|ja で選んでいる言語、--languages en,ja で設定で選んだ翻訳の言語
        hud.model.translation = TranslationLanguage.cli(CommandLine.arguments)
        if let index = CommandLine.arguments.firstIndex(of: "--languages"), CommandLine.arguments.indices.contains(index + 1) {
            hud.model.translationChoices = TranslationLanguage.normalized(
                CommandLine.arguments[index + 1].split(separator: ",").compactMap { TranslationLanguage.cliCode(String($0)) })
        }
        // 要件: REQ-DIC-042
        if let index = CommandLine.arguments.firstIndex(of: "--screenshot"), CommandLine.arguments.indices.contains(index + 1) {
            switch CommandLine.arguments[index + 1] {
            case "on": hud.model.screenshot = .init(on: true)
            case "off": hud.model.screenshot = .init(on: false)
            case "inactive": hud.model.screenshot = .init(on: true, inactiveReason: ScreenSnapshotPolicy.InactiveReason.refineOff.message)
            default: break
            }
        }
        try? hud.snapshotPNG()?.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        print("wrote")
    }
    exit(0)
}

// 会議記録の後処理の確認:
//   Hanasu --meeting-files <自分の音声> <相手の音声> [--engine apple|whisper|gemini] [--template <型>] [--custom-prompt <指示>] [--notes <メモのテキスト>]
//          [--dictionary <辞書ファイル>] [--no-meeting-dictionary] [--delete-audio]
// --delete-audio で、この会議の録音を後処理のあとに消す（付けなければ設定の既定。REQ-MTG-010）。
// --engine whisper|gemini では、記録中と同じく音声を書き出すだけにして、記録のあとの文字起こしを行う。
// 2 つのファイルを「自分」「相手」のチャンネルとして文字起こしし、話者の割り当て → 議事録 → 保存まで行う。
// --notes には、会議中のメモと「ここ重要」の印を、会議ノートの「メモ」タブと同じ形式（[12:34] 内容 / [12:40] ★）で渡す。
// --dictionary で辞書を、--no-meeting-dictionary で「文字起こしに辞書の置き換えルールを当てる」のオフを、設定を書き換えずに試せる（DEC-DIC-173）。
// 確かめ方: REQ-MTG-004, REQ-MTG-005, REQ-MTG-010, REQ-MTG-011, REQ-MTG-012, REQ-MTG-013, REQ-MTG-025, REQ-DIC-073
if let index = CommandLine.arguments.firstIndex(of: "--meeting-files"),
   CommandLine.arguments.indices.contains(index + 2)
{
    let args = CommandLine.arguments
    let files = [URL(fileURLWithPath: args[index + 1]), URL(fileURLWithPath: args[index + 2])]
    Task { @MainActor in
        do {
            let settings = AppSettings.shared
            let dictionary = try DictionaryCLI.dictionary(from: args)
            var meeting = try MeetingStore.newMeeting()
            meeting.title = "テスト会議（\(files[1].deletingPathExtension().lastPathComponent)）"
            MinutesCLI.applyTemplateArguments(args, to: &meeting)
            // 要件: REQ-MTG-010
            MeetingAudioPolicy.apply(to: &meeting, settings: settings)
            if args.contains("--delete-audio") { MeetingAudioPolicy.apply(to: &meeting, deleteAfterTranscription: true) }
            if let notesIndex = args.firstIndex(of: "--notes"), args.indices.contains(notesIndex + 1) {
                meeting.notes = MeetingNote.parse(try String(contentsOfFile: args[notesIndex + 1], encoding: .utf8))
                print("メモ: \(meeting.notes?.count ?? 0) 件\n\(meeting.notesForPrompt() ?? "")")
            }
            var phrases: [MeetingChannel: [TranscribedPhrase]] = [:]
            let (transcription, _) = TranscriptionEngineCLI.parseEngine(args)
            if transcription == .whisper { try await TranscriptionEngineCLI.ensureWhisperModel(settings.whisperModel) }
            let recorder = MeetingRecorder()
            let started = Date()
            var liveFailed: [MeetingChannel] = []
            for (channel, url) in zip([MeetingChannel.me, .others], files) {
                // 設計判断: DEC-MTG-158（録音から作り直すときと同じ流し方。長い録音でもメモリに積まない）
                let result = try await ChannelTranscriber.transcribe(
                    file: url, channel: channel, offset: 0, live: transcription.isLive,
                    writingTo: MeetingStore.audioURL(for: meeting, channel: channel),
                    localeIdentifier: settings.localeIdentifier, contextualStrings: dictionary.contextualStrings)
                phrases[channel] = result.phrases
                // 設計判断: DEC-MTG-142（失敗がなくても空の配列を書く）
                if result.recognitionFailed { liveFailed.append(channel) }
                meeting.duration = max(meeting.duration, result.seconds)
            }
            meeting.transcriptionFailedChannels = liveFailed
            if !transcription.isLive {
                recorder.onStateChange = { state in if case .processing(let message) = state { print(message) } }
                let result = await recorder.transcribeRecordedAudio(meeting, engine: transcription, offsets: [.me: 0, .others: 0])
                phrases = [.me: result.me, .others: result.others]
                if let error = result.error { print("⚠️ \(error)"); meeting.errorMessage = error }
                // 設計判断: DEC-MTG-142
                meeting.transcriptionFailedChannels = result.failedChannels
            }
            if ProcessInfo.processInfo.environment["HANASU_DEBUG"] != nil {
                for p in (phrases[.me] ?? []) + (phrases[.others] ?? []) {
                    print("\(p.channel.rawValue) [\(String(format: "%.2f-%.2f", p.start, p.end))] " +
                          p.words.map { "\($0.text)@\(String(format: "%.2f-%.2f", $0.start, $0.end))" }.joined(separator: " "))
                }
            }
            print(String(format: "[文字起こし %.1fs] 自分 %d 件 / 相手 %d 件", Date().timeIntervalSince(started),
                         phrases[.me]?.count ?? 0, phrases[.others]?.count ?? 0))
            let minutesStarted = Date()
            let result = await recorder.process(meeting, me: phrases[.me] ?? [], others: phrases[.others] ?? [],
                                                dictionary: dictionary, applyDictionary: !args.contains("--no-meeting-dictionary"))
            print("辞書の置き換え: \(args.contains("--no-meeting-dictionary") ? "オフ" : "オン") / 置き換えた発言 \(MeetingDictionary.replacedCount(result)) 件")
            print(result.transcriptMarkdown())
            print(String(format: "[議事録 %@ %@ %.1fs]", settings.aiProvider(for: .meeting).name, settings.textModel(for: .meeting),
                         Date().timeIntervalSince(minutesStarted)))
            print(result.minutes ?? result.errorMessage ?? "(なし)")
            print("保存先: \(MeetingStore.directory(for: result).path)")
            print("録音: \(MeetingStore.hasAudio(result) ? "残した" : "消した")（この会議の値: \(result.deleteAudioAfterTranscription == true ? "文字起こしのあとに削除" : "残す")）")
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription) (\(error))\n".utf8))
            exit(1)
        }
    }
    RunLoop.main.run()
}

// スニペットの照合の確認:  Hanasu --match-snippet <文字起こし> [--snippets <JSON>] [--refine [--translate]]（SnippetsCLI.swift）
// 確かめ方: REQ-DIC-030
if let index = CommandLine.arguments.firstIndex(of: "--match-snippet"),
   CommandLine.arguments.indices.contains(index + 1)
{
    let args = CommandLine.arguments
    Task { @MainActor in
        do {
            try await SnippetsCLI.matchSnippet(args[index + 1], args: args)
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription) (\(error))\n".utf8))
            exit(1)
        }
    }
    RunLoop.main.run()
}

// 設定画面の「スニペット」を画像にする:  Hanasu --render-snippets-settings <出力.png> [--empty]
if let index = CommandLine.arguments.firstIndex(of: "--render-snippets-settings"),
   CommandLine.arguments.indices.contains(index + 1)
{
    MainActor.assumeIsolated {
        SnippetsCLI.renderSettings(to: CommandLine.arguments[index + 1], empty: CommandLine.arguments.contains("--empty"))
    }
    exit(0)
}

// 会議中のメモの画面を画像にする（見た目の確認用）:  Hanasu --render-meeting-notes <出力フォルダ>
// 確かめ方: REQ-MTG-003, REQ-MTG-011, REQ-MTG-014
if let index = CommandLine.arguments.firstIndex(of: "--render-meeting-notes"),
   CommandLine.arguments.indices.contains(index + 1)
{
    MainActor.assumeIsolated {
        do {
            try MeetingNotesPreview.render(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
    exit(0)
}

// 音声入力の履歴の確認（--render-history / --history-check）。中身は DictationHistoryCLI.swift
MainActor.assumeIsolated { DictationHistoryCLI.runIfRequested() }

// 利用者向けの hanasu コマンドの確認（--test-hanasu-command / --bench-hanasu-command。HanasuCommandCLI.swift）
HanasuCommandCLI.runIfRequested()

// 会議の横断検索・質問の確認（--search-meetings / --ask-meetings など。MeetingSearchCLI.swift）
MainActor.assumeIsolated { MeetingSearchCLI.runIfRequested(CommandLine.arguments) }

// 会議の AI チャットの確認（--test-meeting-chat / --chat-meeting / --render-meeting-chat。MeetingChatCLI.swift）
MainActor.assumeIsolated { MeetingChatCLI.runIfRequested() }

// 記録中のスリープでの切り詰めの確認（--test-meeting-sleep-cut。MeetingSleepCLI.swift）
MeetingSleepCLI.runSelfTestIfRequested()
// 議事録に使う発言の選び方の確認（--test-minutes-selection / --render-minutes-selection。MinutesSelectionCLI.swift）
MainActor.assumeIsolated { MinutesSelectionCLI.runIfRequested() }
// 会議ノートの文書・引用・再生の確認（--test-minutes-citations / --test-minutes-document / --test-meeting-player / --render-meeting-window。MeetingNotesUICLI.swift）
MainActor.assumeIsolated { MeetingNotesUICLI.runIfRequested() }
// 記録中に落ちた会議を録音から戻す機能の確認（--test-meeting-audio-crash / --test-meeting-recovery / --meeting-recover-files。MeetingRecoveryCLI.swift）
MeetingRecoveryCLI.runIfRequested()
// 会議の録音を消す機能の確認（--test-meeting-audio / --render-meeting-audio-manager。MeetingAudioCLI.swift）
MainActor.assumeIsolated { MeetingAudioCLI.runIfRequested() }
// 会議ノートから辞書を作る・会議に辞書を当てるの確認（--test-meeting-dictionary / --render-meeting-dictionary。MeetingDictionaryCLI.swift）
MainActor.assumeIsolated { MeetingDictionaryCLI.runIfRequested() }
// 議事録のテンプレートと書き出しの確認（MinutesCLI.swift）
MainActor.assumeIsolated { MinutesCLI.runIfRequested() }
// 話者の名前の推測の確認（SpeakerNameInferenceCLI.swift）
SpeakerNameInferenceCLI.runIfRequested()
// アイコンの表示の設定欄と、保存値の読み替えの確認（--render-presence-settings / --presence-migration。AppPresence.swift）
MainActor.assumeIsolated { AppPresenceCLI.runIfRequested() }
// オンボーディングの各ページの確認（--render-onboarding <出力フォルダ>）。Onboarding.swift
MainActor.assumeIsolated { OnboardingCLI.runIfRequested() }

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // 要件: REQ-COM-040
    // 設計判断: DEC-COM-008, DEC-COM-080
    // Dock にはいつも出す（メニューバーにも出すかは AppDelegate.applyPresence で当てる）。
    // ここで AppPresenceSettings に触らない（オンボーディングの判定より先に設定を書かないように。DEC-COM-090）
    app.setActivationPolicy(.regular)
    app.run()
}
