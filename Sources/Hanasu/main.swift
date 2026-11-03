import AppKit
import AVFoundation
import SwiftUI

// 動作確認用の CLI モード:
//   Hanasu --transcribe-file <音声ファイル> [--engine apple|whisper|gemini|dictation|speech] [--refine [--translate] [--model <id>]]
//   （Whisper / Gemini の確認の詳細は TranscriptionEngineCLI.swift）
//   Hanasu --refine-text <文章> [--translate] [--model <id>] [--app <bundle id>] [--show-prompt] [--dictionary <辞書ファイル>]
// --refine を付けると Gemini 整形も行い、--translate を付けると整形の代わりに英訳する。
// --app を付けると、そのアプリ向けの文体ルール（設定の「アプリ別」）で整形する。既定の出力言語が English なら英訳する。
// --show-prompt を付けると、Gemini に送る user content も表示する。
// 認証は GEMINI_SERVICE_ACCOUNT_JSON（サービスアカウント JSON のパス）、設定画面の認証情報、GEMINI_API_KEY の順に使う。
@MainActor
func cliRefine(_ raw: String, args: [String]) async throws {
    let settings = AppSettings.shared
    let env = ProcessInfo.processInfo.environment
    let auth: GeminiClient.Auth
    if let path = env["GEMINI_SERVICE_ACCOUNT_JSON"] {
        auth = .serviceAccount(try ServiceAccountCredentials.load(path: path), location: settings.vertexLocation)
    } else {
        auth = try GeminiClient.authFromSettings(settings) ?? .apiKey(env["GEMINI_API_KEY"] ?? "")
    }
    let model = args.firstIndex(of: "--model").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? settings.model
    let app = cliAppStyle(args: args)
    let translate = args.contains("--translate") || app.style?.outputLanguage == .english
    let client = GeminiClient(auth: auth)
    // 音声入力と同じく、置き換えルールを当ててから送る（--dictionary <ファイル> で辞書を差し替えられる）
    let dictionary = try DictionaryCLI.dictionary(from: args)
    let request = GeminiClient.Request(
        transcript: dictionary.apply(to: raw), model: model, appName: app.name,
        dictionary: dictionary.spellings, extraInstructions: settings.extraInstructions,
        dictionaryRules: dictionary.rules, appStyle: app.style)
    if args.contains("--show-prompt") {
        var shown = request
        if translate { shown.extraInstructions = "" }  // translateToEnglish と同じく、英訳では共通の追加ルールを外す
        print(GeminiClient.userPrompt(for: shown, translating: translate))
    }
    let started = Date()
    let output = translate ? try await client.translateToEnglish(request) : try await client.refine(request)
    print(String(format: "[%@ %@ %.1fs] %@", translate ? "英訳" : "整形", model, Date().timeIntervalSince(started), output))
}

// 文字起こしのエンジンの確認（--download-whisper / --render-engine-settings）。TranscriptionEngineCLI.swift
MainActor.assumeIsolated { TranscriptionEngineCLI.runIfRequested() }
// 選択を声で編集するモードの確認（--edit-text / --render-edit-hud / --render-edit-settings）。中身は EditModeCLI.swift
MainActor.assumeIsolated { EditModeCLI.runIfRequested() }
// 画面の文脈の確認（--dump-context、--refine-text … --context）。該当しなければ何もしない
MainActor.assumeIsolated { ScreenContextCLI.runIfRequested() }
// ユーザー辞書の確認（--apply-dictionary / --test-dictionary / --suggest-dictionary / --render-dictionary-settings）。
// 使い方は DictionaryCLI.swift を参照
if DictionaryCLI.handles(CommandLine.arguments) {
    MainActor.assumeIsolated { DictionaryCLI.run(CommandLine.arguments) }
}

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
if CommandLine.arguments.contains("--list-audio-processes") {
    MainActor.assumeIsolated { MeetingDetectorCLI.listProcesses() }
    exit(0)
}
if CommandLine.arguments.contains("--watch-audio-processes") {
    MainActor.assumeIsolated { MeetingDetectorCLI.watch() }
}
if CommandLine.arguments.contains("--simulate-meeting-detection") {
    MainActor.assumeIsolated { MeetingDetectorCLI.simulate() }
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

// 設定の「アプリ別」タブを画像にする（見た目の確認用）:  Hanasu --render-app-styles <出力.png> [--expanded]
if let index = CommandLine.arguments.firstIndex(of: "--render-app-styles"),
   CommandLine.arguments.indices.contains(index + 1)
{
    MainActor.assumeIsolated {
        renderAppStylesPNG(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]),
                           expandedFirst: CommandLine.arguments.contains("--expanded"))
    }
    exit(0)
}

// 音声入力の HUD を画像にする（見た目の確認用）:  Hanasu --render-hud <出力.png> [--translate] [--engine whisper|gemini [--processing]]
// --engine whisper|gemini は、録音を止めてからまとめて文字起こしするときの見た目（音量の目安）。--processing で文字起こし中
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
        hud.model.translating = CommandLine.arguments.contains("--translate")
        try? hud.snapshotPNG()?.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        print("wrote")
    }
    exit(0)
}

// 会議記録の後処理の確認:
//   Hanasu --meeting-files <自分の音声> <相手の音声> [--engine apple|whisper|gemini] [--template <型>] [--custom-prompt <指示>] [--notes <メモのテキスト>]
// --engine whisper|gemini では、記録中と同じく音声を書き出すだけにして、記録のあとの文字起こしを行う。
// 2 つのファイルを「自分」「相手」のチャンネルとして文字起こしし、話者の割り当て → 議事録 → 保存まで行う。
// --notes には、会議中のメモと「ここ重要」の印を、会議ノートの「メモ」タブと同じ形式（[12:34] 内容 / [12:40] ★）で渡す。
if let index = CommandLine.arguments.firstIndex(of: "--meeting-files"),
   CommandLine.arguments.indices.contains(index + 2)
{
    let args = CommandLine.arguments
    let files = [URL(fileURLWithPath: args[index + 1]), URL(fileURLWithPath: args[index + 2])]
    Task { @MainActor in
        do {
            let settings = AppSettings.shared
            var meeting = try MeetingStore.newMeeting()
            meeting.title = "テスト会議（\(files[1].deletingPathExtension().lastPathComponent)）"
            MinutesCLI.applyTemplateArguments(args, to: &meeting)
            if let notesIndex = args.firstIndex(of: "--notes"), args.indices.contains(notesIndex + 1) {
                meeting.notes = MeetingNote.parse(try String(contentsOfFile: args[notesIndex + 1], encoding: .utf8))
                print("メモ: \(meeting.notes?.count ?? 0) 件\n\(meeting.notesForPrompt() ?? "")")
            }
            var phrases: [MeetingChannel: [TranscribedPhrase]] = [:]
            let (transcription, _) = TranscriptionEngineCLI.parseEngine(args)
            if transcription == .whisper { try await TranscriptionEngineCLI.ensureWhisperModel(settings.whisperModel) }
            let recorder = MeetingRecorder()
            let started = Date()
            for (channel, url) in zip([MeetingChannel.me, .others], files) {
                let file = try AVAudioFile(forReading: url)
                let transcriber = ChannelTranscriber(
                    channel: channel, inputFormat: file.processingFormat,
                    fileURL: MeetingStore.audioURL(for: meeting, channel: channel),
                    meetingStart: meeting.startedAt, fixedTimeOffset: 0, live: transcription.isLive)
                try await transcriber.prepare(localeIdentifier: settings.localeIdentifier, contextualStrings: settings.userDictionary.contextualStrings)
                while file.framePosition < file.length {
                    guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8192) else { break }
                    try file.read(into: buffer)
                    if buffer.frameLength == 0 { break }
                    transcriber.append(buffer)
                }
                phrases[channel] = await transcriber.finish()
                meeting.duration = max(meeting.duration, Double(file.length) / file.processingFormat.sampleRate)
            }
            var keepAudio = false
            if !transcription.isLive {
                recorder.onStateChange = { state in if case .processing(let message) = state { print(message) } }
                let result = await recorder.transcribeRecordedAudio(meeting, engine: transcription, offsets: [.me: 0, .others: 0])
                phrases = [.me: result.me, .others: result.others]
                if let error = result.error { print("⚠️ \(error)"); meeting.errorMessage = error; keepAudio = true }
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
            let result = await recorder.process(meeting, me: phrases[.me] ?? [], others: phrases[.others] ?? [], keepAudio: keepAudio)
            print(result.transcriptMarkdown())
            print(String(format: "[議事録 %@ %.1fs]", settings.meetingMinutesModel, Date().timeIntervalSince(minutesStarted)))
            print(result.minutes ?? result.errorMessage ?? "(なし)")
            print("保存先: \(MeetingStore.directory(for: result).path)")
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription) (\(error))\n".utf8))
            exit(1)
        }
    }
    RunLoop.main.run()
}

// スニペットの照合の確認:  Hanasu --match-snippet <文字起こし> [--snippets <JSON>] [--refine [--translate]]（SnippetsCLI.swift）
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

// 設定画面の「スニペット」タブを画像にする:  Hanasu --render-snippets-settings <出力.png> [--empty]
if let index = CommandLine.arguments.firstIndex(of: "--render-snippets-settings"),
   CommandLine.arguments.indices.contains(index + 1)
{
    MainActor.assumeIsolated {
        SnippetsCLI.renderSettings(to: CommandLine.arguments[index + 1], empty: CommandLine.arguments.contains("--empty"))
    }
    exit(0)
}

// 会議中のメモの画面を画像にする（見た目の確認用）:  Hanasu --render-meeting-notes <出力フォルダ>
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

// 会議の横断検索・質問の確認（--search-meetings / --ask-meetings など。MeetingSearchCLI.swift）
MainActor.assumeIsolated { MeetingSearchCLI.runIfRequested(CommandLine.arguments) }

// 議事録のテンプレートと書き出しの確認（MinutesCLI.swift）
MainActor.assumeIsolated { MinutesCLI.runIfRequested() }

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
