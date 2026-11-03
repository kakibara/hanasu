import AppKit
import SwiftUI

/// ユーザー辞書まわりの動作確認用の CLI モード:
///
///     Hanasu --apply-dictionary <文> [--dictionary <辞書ファイル>]
///         置き換えルールを当てた結果と、どこを置き換えたかを表示する
///     Hanasu --test-dictionary
///         置き換えの規則の確認（UserDictionarySelfTest）を実行する。失敗があれば終了コード 1
///     Hanasu --suggest-dictionary [--from-file <テキスト>] [--dictionary <辞書ファイル>] [--model <id>]
///         辞書の候補を Gemini に挙げてもらう。--from-file があればそのファイルを音声入力の結果として使い、
///         なければ会議の記録（新しい順に 5 件）を使う
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
        var corpus = DictionarySuggester.Corpus()
        if let path = value(after: "--from-file", in: args) {
            let lines = try String(contentsOfFile: path, encoding: .utf8)
                .split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
            corpus.dictations = lines.map { RecentDictations.Entry(raw: $0, output: $0) }
        } else {
            corpus.meetings = DictionarySuggester.recentMeetings()
        }
        guard !corpus.isEmpty else { throw GeminiError.emptyResponse(reason: "材料がありません") }
        let env = ProcessInfo.processInfo.environment
        let auth: GeminiClient.Auth
        if let path = env["GEMINI_SERVICE_ACCOUNT_JSON"] {
            auth = .serviceAccount(try ServiceAccountCredentials.load(path: path), location: settings.vertexLocation)
        } else {
            auth = try GeminiClient.authFromSettings(settings) ?? .apiKey(env["GEMINI_API_KEY"] ?? "")
        }
        let model = value(after: "--model", in: args) ?? settings.meetingMinutesModel
        let started = Date()
        let candidates = try await DictionarySuggester.suggest(
            corpus: corpus, existing: dictionary, client: GeminiClient(auth: auth), model: model)
        print(String(format: "[候補 %@ %.1fs] 音声入力 %d 件 / 会議 %d 件 → %d 件", model, Date().timeIntervalSince(started),
                     corpus.dictations.count, corpus.meetings.count, candidates.count))
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
