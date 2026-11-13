import AppKit
import SwiftUI

// 確かめ方: REQ-DIC-070, REQ-DIC-071, REQ-DIC-072, REQ-DIC-075
/// ユーザー辞書まわりの動作確認用の CLI モード:
///
///     Hanasu --apply-dictionary <文> [--dictionary <辞書ファイル>]
///         置き換えルールを当てた結果と、どこを置き換えたかを表示する
///     Hanasu --test-dictionary
///         置き換えの規則の確認（UserDictionarySelfTest）を実行する。失敗があれば終了コード 1
///     Hanasu --suggest-dictionary [--from-file <テキスト> | --meeting <会議のフォルダ>] [--dictionary <辞書ファイル>] [--model <id>]
///         辞書の候補を会議の AI に挙げてもらう。--from-file があればそのファイルを音声入力の結果として使い、
///         --meeting があればその会議 1 件（会議ノートの「この会議から辞書の候補を探す」と同じ材料。REQ-DIC-072）を使い、
///         どちらもなければ会議の記録（新しい順に 5 件）を使う
///     Hanasu --suggest-dictionary --screen | --screen-text <OCR の行のファイル> [--dictionary <辞書ファイル>] [--ai …] [--model <id>]
///         画面から辞書の候補を探す（REQ-DIC-075）。--screen はアプリと同じフィルタで今の画面を撮って読む（画面収録の許可が要る）。
///         --screen-text はファイルの 1 行を OCR の 1 行として使う。送る材料と、候補を `読み => 表記` の行で出す
///     Hanasu --render-dictionary-settings <出力.png> [--dictionary <辞書ファイル>]
///         設定画面の辞書の欄を画像にする（見た目の確認用）
///
/// --dictionary を省くと設定の辞書を使う。--refine-text にも --dictionary を付けられる。
enum DictionaryCLI {
    static let modes = ["--apply-dictionary", "--test-dictionary", "--suggest-dictionary", "--render-dictionary-settings"]

    static func handles(_ args: [String]) -> Bool {
        modes.contains(where: args.contains)
    }

    @MainActor
    static func run(_ args: [String]) -> Never {
        do {
            let dictionary = try Self.dictionary(from: args)
            if let text = value(after: "--apply-dictionary", in: args) {
                let (output, replacements) = dictionary.applyWithLog(to: text)
                print(output)
                for r in replacements { print("  \(r.matched) → \(r.target)") }
                if replacements.isEmpty { print("  （置き換えなし。ルール \(dictionary.rules.count) 件）") }
                exit(0)
            }
            if args.contains("--test-dictionary") {
                exit(UserDictionarySelfTest.run() == 0 ? 0 : 1)
            }
            if let path = value(after: "--render-dictionary-settings", in: args) {
                try render(dictionary: dictionary, to: URL(fileURLWithPath: path))
                print("wrote")
                exit(0)
            }
            if args.contains("--suggest-dictionary") {
                Task { @MainActor in
                    do {
                        try await suggest(args, dictionary: dictionary)
                        exit(0)
                    } catch {
                        fail(error)
                    }
                }
                RunLoop.main.run()
            }
        } catch {
            fail(error)
        }
        exit(2)
    }

    private static func fail(_ error: Error) -> Never {
        FileHandle.standardError.write(Data("error: \(error.localizedDescription) (\(error))\n".utf8))
        exit(1)
    }

    private static func value(after flag: String, in args: [String]) -> String? {
        args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
    }

    /// --dictionary <ファイル> があればその辞書、なければ設定の辞書（--refine-text でも使う）
    @MainActor
    static func dictionary(from args: [String]) throws -> UserDictionary {
        if let path = value(after: "--dictionary", in: args) {
            return UserDictionary(text: try String(contentsOfFile: path, encoding: .utf8))
        }
        return AppSettings.shared.userDictionary
    }

    @MainActor
    private static func suggest(_ args: [String], dictionary: UserDictionary) async throws {
        let settings = AppSettings.shared
        // 要件: REQ-DIC-075（--meeting・--from-file と同じく、ここで分ける。後ろに置くと最近の会議が送られる）
        if args.contains("--screen") || args.contains("--screen-text") {
            try await suggestFromScreen(args, dictionary: dictionary)
            return
        }
        if let folder = value(after: "--meeting", in: args) {
            try await suggestFromMeeting(URL(fileURLWithPath: folder, isDirectory: true), args: args, dictionary: dictionary)
            return
        }
        var corpus = DictionarySuggester.Corpus()
        if let path = value(after: "--from-file", in: args) {
            let lines = try String(contentsOfFile: path, encoding: .utf8)
                .split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
            corpus.dictations = lines.map { RecentDictations.Entry(raw: $0, output: $0) }
        } else {
            corpus.meetings = DictionarySuggester.recentMeetings()
        }
        guard !corpus.isEmpty else { throw GeminiError.emptyResponse(reason: "材料がありません") }
        // 辞書の候補探しは会議の AI を使う。--ai gemini|claude で変えられる（TextAIClient.cli）
        let client = try TextAIClient.cli(args: args, settings: settings, for: .meeting, timeout: 120)
        let model = TextAIClient.cliModel(args: args, settings: settings, for: .meeting)
        let started = Date()
        let candidates = try await DictionarySuggester.suggest(
            corpus: corpus, existing: dictionary, client: client, model: model)
        print(String(format: "[候補 %@ %.1fs] 音声入力 %d 件 / 会議 %d 件 → %d 件", model, Date().timeIntervalSince(started),
                     corpus.dictations.count, corpus.meetings.count, candidates.count))
        for c in candidates {
            print("\(c.entry.line)\t# \(c.reason)")
        }
    }

    // 要件: REQ-DIC-075
    // 設計判断: DEC-DIC-237
    /// 画面から候補を探す（候補の画面と同じ材料・上限・絞り込み）
    @MainActor
    private static func suggestFromScreen(_ args: [String], dictionary: UserDictionary) async throws {
        let settings = AppSettings.shared
        let lines: [ScreenTextLine]
        var displays = 1
        if let path = value(after: "--screen-text", in: args) {
            lines = try String(contentsOfFile: path, encoding: .utf8)
                .split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
                .enumerated().map { ScreenTextLine(text: $1, display: 0, inTarget: false, y: Double($0) * 20, x: 0) }
        } else {
            let request = ScreenSnapshotReader.Request(
                targetPID: nil, excludedApps: ScreenContextSettings.shared.excludedApps,
                languages: ScreenSnapshotReader.languages(localeIdentifier: settings.localeIdentifier))
            let shots = try await ScreenSnapshotReader.captureAll(request)
            displays = shots.count
            lines = try await ScreenSnapshotReader.recognizeAll(shots, languages: request.languages)
        }
        let client = try TextAIClient.cli(args: args, settings: settings, for: .meeting, timeout: 120)
        let model = TextAIClient.cliModel(args: args, settings: settings, for: .meeting)
        let material = DictionarySuggester.screenMaterial(
            lines, budget: DictionarySuggester.budget(for: client, existing: dictionary, instruction: DictionarySuggester.screenInstruction))
        guard !material.isEmpty else { throw GeminiError.emptyResponse(reason: "画面から文字を読み取れませんでした") }
        print("[材料] \(displays) 画面 / 語 \(material.terms.count) 個 / 行 \(material.lines.count) 行 / \(material.text.count) 文字\(material.truncated ? "（一部を外した）" : "")")
        print(material.text)
        print("---")
        let started = Date()
        let candidates = try await DictionarySuggester.suggestFromScreen(material, existing: dictionary, client: client, model: model)
        print(String(format: "[候補 %@ %.1fs] → %d 件", model, Date().timeIntervalSince(started), candidates.count))
        for c in candidates {
            print("\(c.entry.line)\t# \(c.reason)")
        }
    }

    // 要件: REQ-DIC-072
    /// 会議 1 件から候補を探す（会議ノートの候補の画面と同じ材料・上限）。材料の中身は出さず、長さと切ったかだけを出す
    @MainActor
    private static func suggestFromMeeting(_ folder: URL, args: [String], dictionary: UserDictionary) async throws {
        let settings = AppSettings.shared
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let meeting = try decoder.decode(Meeting.self, from: Data(contentsOf: folder.appendingPathComponent("meeting.json")))
        let client = try TextAIClient.cli(args: args, settings: settings, for: .meeting, timeout: 120)
        let model = TextAIClient.cliModel(args: args, settings: settings, for: .meeting)
        let budget = DictionarySuggester.budget(for: client, existing: dictionary)
        let material = DictionarySuggester.meetingMaterial(meeting, budget: budget)
        print("材料: \(material.text.count) 字（上限 \(budget)）" + (material.readMinutes.map { " / 文字起こしの最初の約 \($0) 分まで" } ?? " / 全部"))
        let started = Date()
        let candidates = try await DictionarySuggester.suggest(material: material.text, existing: dictionary, client: client, model: model)
        print(String(format: "[候補 %@ %.1fs] → %d 件", model, Date().timeIntervalSince(started), candidates.count))
        for c in candidates {
            print("\(c.entry.line)\t# \(c.reason)")
        }
    }

    @MainActor
    private static func render(dictionary: UserDictionary, to url: URL) throws {
        _ = NSApplication.shared
        struct Preview: View {
            @State var text: String
            var candidates: [DictionaryCandidate]
            var body: some View {
                Form {
                    DictionaryEditorSection(text: $text)
                    DictionarySuggestionSection(
                        settings: AppSettings.shared, candidates: candidates,
                        selected: Set(candidates.prefix(1).map(\.id)))
                }
                .formStyle(.grouped)
            }
        }
        let samples = [
            DictionaryCandidate(spelling: "Anews", readings: ["エーニュース"], reason: "サービス名。カタカナで認識されていた"),
            DictionaryCandidate(spelling: "SpeechAnalyzer", readings: [], reason: "API 名"),
        ]
        let hosting = NSHostingView(rootView: Preview(text: dictionary.text, candidates: samples).frame(width: 560, height: 820))
        hosting.frame = NSRect(x: 0, y: 0, width: 560, height: 820)
        // TextField などは AppKit の部品なので、画面外のウインドウに置いて描く
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        // onAppear で表を読み込むので、1 回 RunLoop を回してから描く
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
