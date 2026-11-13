import AppKit
import SwiftUI

// 確かめ方: REQ-DIC-022, REQ-DIC-023
/// 文章から文体を学ぶ機能（カスタム文体）の確認用の CLI モード:
///
///     Hanasu --test-custom-styles
///         ファイルの読み込み（共有の common/testdata/style/cases.json）・AI の答えの読み取り・長さの上限・名前とルールの検査・
///         プロンプトの節の組み立て・割り当ての外し方を確かめる（AI には送らない）。失敗があれば終了コード 1。リポジトリのルートで動かす
///     Hanasu --learn-style --from-file <ファイル> [--ai gemini|claude|local|apple] [--model <id>] [--save] [--assign <bundle ID>]
///         ファイルを読んで、実際の AI（議事録の AI）で文体を学ぶ。--save でカスタム文体として保存し、--assign でそのアプリに割り当てる
///         （設定を汚さないよう、HANASU_TEST_DEFAULTS_SUITE=<suite> を付けて動かす）
///     Hanasu --render-style-learning <出力フォルダ>
///         学ぶシート（学ぶ前・学んだあと）・編集のシート・「アプリ別」タブを PNG にする（見た目の確認用）
enum StyleLearningCLI {
    @MainActor
    static func runIfRequested() {
        let args = CommandLine.arguments
        if args.contains("--test-custom-styles") {
            exit(StyleLearningSelfTest.run() == 0 ? 0 : 1)
        }
        if args.contains("--learn-style") {
            Task { @MainActor in
                do {
                    try await learn(args)
                    exit(0)
                } catch {
                    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
                    exit(1)
                }
            }
            RunLoop.main.run()
        }
        if let index = args.firstIndex(of: "--render-style-learning"), args.indices.contains(index + 1) {
            render(to: URL(fileURLWithPath: args[index + 1], isDirectory: true))
            exit(0)
        }
    }

    private static func value(after flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }

    // 要件: REQ-DIC-022
    @MainActor
    private static func learn(_ args: [String]) async throws {
        guard let path = value(after: "--from-file", in: args) else {
            FileHandle.standardError.write(Data("usage: Hanasu --learn-style --from-file <ファイル> [--ai …] [--model …] [--save] [--assign <bundle ID>]\n".utf8))
            exit(2)
        }
        let url = URL(fileURLWithPath: path)
        let text: String
        switch StyleSourceReader.read(url) {
        case .success(let body): text = body
        case .failure(let error):
            FileHandle.standardError.write(Data("error: \(url.lastPathComponent): \(error.message)\n".utf8))
            exit(2)
        }
        let settings = AppSettings.shared
        let client = try TextAIClient.cli(args: args, settings: settings, for: .meeting, timeout: StyleLearner.timeout)
        let model = TextAIClient.cliModel(args: args, settings: settings, for: .meeting)
        let material = StyleLearner.material(text, budget: StyleLearner.budget(for: client))
        print("材料: \(material.usedCharacters) 字 / \(material.totalCharacters) 字（上限 \(StyleLearner.budget(for: client))）")
        let started = Date()
        let style = try await StyleLearner.learn(text: text, client: client, model: model)
        print(String(format: "[文体 %@ %.1fs]", model, Date().timeIntervalSince(started)))
        print("名前: \(style.name)")
        print("言語: \(style.language.rawValue)")
        for rule in style.rules { print("- \(rule)") }
        guard args.contains("--save") else { return }
        let store = CustomStyleStore.shared
        var name = style.name.isEmpty ? url.deletingPathExtension().lastPathComponent : style.name
        while CustomStyle.validate(name: name, language: style.language.rawValue, rules: style.rules, others: store.styles) == .duplicateName {
            name += "+"
        }
        let saved = CustomStyle(name: name, language: style.language.rawValue, rules: style.rules)
        if let error = CustomStyle.validate(name: saved.name, language: saved.language, rules: saved.rules, others: store.styles) {
            throw NSError(domain: "Hanasu", code: 1, userInfo: [NSLocalizedDescriptionKey: error.message])
        }
        store.upsert(saved)
        print("保存しました: \(saved.name)（\(saved.id.uuidString)）")
        if let bundleID = value(after: "--assign", in: args) {
            let apps = AppStyleStore.shared
            if !apps.styles.contains(where: { $0.bundleID == bundleID }) {
                apps.add(bundleID: bundleID, name: bundleID)
            }
            if let index = apps.styles.firstIndex(where: { $0.bundleID == bundleID }) {
                apps.styles[index].selectCustomStyle(saved.id)
            }
            print("割り当てました: \(bundleID)")
        }
    }

    // 要件: REQ-DIC-022
    // 設計判断: DEC-DIC-215
    @MainActor
    private static func render(to directory: URL) {
        _ = NSApplication.shared
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // 見本は使い捨ての suite に置く（設定のカスタム文体を変えない）
        let suiteName = "dev.mactypeless.Hanasu.render-styles-\(ProcessInfo.processInfo.processIdentifier)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }
        let store = CustomStyleStore(defaults: suite)
        let sample = CustomStyle(name: tr("報告書（である調）"), language: PromptLanguage.current.rawValue, rules: sampleRules)
        store.styles = [sample, CustomStyle(name: "Casual English", language: "en", rules: ["Use short, casual sentences", "Use contractions"])]
        let learned = LearnedStyle(name: sample.name, language: PromptLanguage.current, rules: sampleRules)

        func write(_ view: some View, _ name: String, size: NSSize) {
            let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height)
                .background(Color(nsColor: .windowBackgroundColor)))
            hosting.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
                hosting.cacheDisplay(in: hosting.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name))
                print("wrote \(name)")
            }
        }
        write(StyleLearningSheet(mode: .learn, store: store, initialText: sampleText), "learn.png", size: NSSize(width: 560, height: 420))
        write(StyleLearningSheet(mode: .learn, store: store, initialText: sampleText, initialLearned: learned),
              "learned.png", size: NSSize(width: 560, height: 760))
        write(StyleLearningSheet(mode: .edit(sample), store: store), "edit.png", size: NSSize(width: 560, height: 420))
        write(AppStylesTab(initialExpandedID: nil, customStore: store), "app-styles.png", size: NSSize(width: 560, height: 1500))
    }

    private static var sampleRules: [String] {
        [tr("文末は である調 にそろえる（例: 〜なんですけど → 〜だが）"), tr("読点は「，」を使う"), tr("一文は短めにし、結論を先に書く")]
    }

    private static var sampleText: String {
        String(repeating: tr("本報告では，音声入力の整形にかかる時間を調べた結果をまとめる。"), count: 6)
    }
}

// 確かめ方: REQ-DIC-022, REQ-DIC-023
/// --test-custom-styles の中身
@MainActor
enum StyleLearningSelfTest {
    private static var failures = 0

    private static func check(_ ok: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
        if ok {
            print("ok   \(name)")
        } else {
            failures += 1
            let extra = detail()
            print("FAIL \(name)" + (extra.isEmpty ? "" : "\n     \(extra)"))
        }
    }

    static func run() -> Int {
        failures = 0
        reading()
        parsing()
        lengths()
        validation()
        assignment()
        prompts()
        print(failures == 0 ? "すべて通りました" : "\(failures) 件失敗")
        return failures
    }

    // 設計判断: DEC-DIC-211
    private static func reading() {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("common/testdata/style")
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("cases.json")),
              let spec = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cases = spec["cases"] as? [[String: Any]] else {
            check(false, "共有のテストデータ（common/testdata/style/cases.json）を読む", "リポジトリのルートで動かす")
            return
        }
        for item in cases {
            guard let file = item["file"] as? String else { continue }
            let result = StyleSourceReader.read(directory.appendingPathComponent("reading").appendingPathComponent(file))
            if let expected = item["text"] as? String {
                let actual = try? result.get()
                check(actual == expected, "読む: \(file)", "期待 \(expected.debugDescription)\n     実際 \(String(describing: actual).debugDescription)")
            } else if let error = item["error"] as? String {
                var actual = "成功"
                if case .failure(let e) = result { actual = e.code }
                check(actual == error, "読めない: \(file) → \(error)", "実際 \(actual)")
            }
        }
        // 20 MB を超えるファイル
        let big = FileManager.default.temporaryDirectory.appendingPathComponent("hanasu-style-\(UUID().uuidString).txt")
        FileManager.default.createFile(atPath: big.path, contents: Data(count: StyleSourceReader.maxFileBytes + 1))
        defer { try? FileManager.default.removeItem(at: big) }
        check(StyleSourceReader.read(big) == .failure(.tooLarge), "20 MB を超えるファイルは読まない")
        let limit = FileManager.default.temporaryDirectory.appendingPathComponent("hanasu-style-\(UUID().uuidString).txt")
        FileManager.default.createFile(atPath: limit.path, contents: Data(repeating: 0x61, count: StyleSourceReader.maxFileBytes))
        defer { try? FileManager.default.removeItem(at: limit) }
        check((try? StyleSourceReader.read(limit).get())?.utf8.count == StyleSourceReader.maxFileBytes, "ちょうど 20 MB は読む")
    }

    // 設計判断: DEC-DIC-210
    private static func parsing() {
        let ok = try? StyleLearner.parse("```json\n{\"name\": \" 報告書 \", \"language\": \"ja\", \"rules\": [\" ルール1 \", \"\", \"ルール2\"]}\n```")
        check(ok == LearnedStyle(name: "報告書", language: .ja, rules: ["ルール1", "ルール2"]), "コードブロックの JSON を読み、空のルールを除く", "\(String(describing: ok))")
        let many = (1...13).map { "\"r\($0)\"" }.joined(separator: ",")
        check((try? StyleLearner.parse("{\"name\":\"x\",\"language\":\"en\",\"rules\":[\(many)]}"))?.rules.count == 12, "ルールは 12 個まで")
        check((try? StyleLearner.parse("{\"name\":\"x\",\"language\":\"ZH-cn\",\"rules\":[\"a\"]}"))?.language == .zhCN, "言語のコードは大文字小文字を区別しない")
        func error(_ text: String) -> StyleLearningError? {
            do { _ = try StyleLearner.parse(text); return nil } catch { return error as? StyleLearningError }
        }
        check(error("{\"name\":\"x\",\"language\":\"ja\",\"rules\":[]}") == .invalidResponse, "ルールが空なら失敗")
        check(error("{\"name\":\"x\",\"language\":\"ja\",\"rules\":[\"  \"]}") == .invalidResponse, "空白だけのルールしかなければ失敗")
        check(error("ルールは次のとおりです") == .invalidResponse, "JSON でなければ失敗")
        check(error("{\"name\":\"x\",\"language\":\"xx\",\"rules\":[\"a\"]}") == .unknownLanguage("xx"), "17 言語のどれでもなければ失敗")
        check(error("{\"name\":\"x\",\"rules\":[\"a\"]}") == .unknownLanguage(""), "言語がなければ失敗")
        check(StyleLearner.instruction.contains("en, ja, zh-CN, zh-TW, ko, es, fr, de, it, pt-BR, ru, tr, vi, id, pl, ar, hi"), "指示に 17 言語のコードを並べる")
        check(StyleLearner.userPrompt(material: "本文").contains("<material>\n本文\n</material>"), "材料を <material> で囲む")
    }

    // 設計判断: DEC-DIC-212
    private static func lengths() {
        check(StyleLearner.count("𠮷野家") == 3, "サロゲートペアの字も 1 字と数える")
        check(StyleLearner.count("e\u{301}") == 2, "結合文字はスカラー値で数える（Windows の Rune と同じ）")
        let text = "  " + String(repeating: "あ", count: 40_000) + "\n"
        let m = StyleLearner.material(text, budget: .characters(StyleLearner.characterLimit))
        check(m.totalCharacters == 40_000 && m.usedCharacters == 30_000 && m.truncated, "Gemini・Claude は先頭の 30,000 字", "\(m.totalCharacters) / \(m.usedCharacters)")
        let short = StyleLearner.material(" 短い文 ", budget: .characters(StyleLearner.characterLimit))
        check(short.text == "短い文" && !short.truncated, "前後の空白を除く")
        let tokens = StyleLearner.material(text, budget: .tokens(1_000))
        check(AppleFMClient.estimateTokens(tokens.text) <= 1_000 && tokens.usedCharacters > 0 && tokens.truncated,
              "ローカル・Apple はトークンの上限に入る分だけ", "\(tokens.usedCharacters) 字 \(AppleFMClient.estimateTokens(tokens.text))")
        let bigger = StyleLearner.material(text, budget: .tokens(1_000))
        let plusOne = StyleLearner.prefix(text.trimmingCharacters(in: .whitespacesAndNewlines), characters: bigger.usedCharacters + 1)
        check(AppleFMClient.estimateTokens(plusOne) > 1_000, "トークンの上限いっぱいまで使う")
        check(StyleLearner.minimumCharacters == 100 && StyleLearner.inputLimit == 100_000, "下限 100 字・入力欄 100,000 字")
    }

    // 設計判断: DEC-DIC-213
    private static func validation() {
        let others = [CustomStyle(name: " 報告書 ", language: "ja", rules: ["a"])]
        check(CustomStyle.validate(name: "  ", language: "ja", rules: ["a"], others: []) == .emptyName, "名前が空なら保存しない")
        check(CustomStyle.validate(name: "報告書", language: "ja", rules: ["a"], others: others) == .duplicateName, "同じ名前（前後の空白を除く）は保存しない")
        check(CustomStyle.validate(name: "casual", language: "en", rules: ["a"],
                                   others: [CustomStyle(name: "Casual", language: "en", rules: ["a"])]) == .duplicateName, "大文字小文字を区別しない")
        check(CustomStyle.validate(name: AppStylePreset.chat.label, language: "ja", rules: ["a"], others: []) == .duplicateName, "組み込みのプリセットの名前も使えない")
        check(CustomStyle.validate(name: "x", language: "ja", rules: [], others: []) == .emptyRules, "ルールが空なら保存しない")
        check(CustomStyle.validate(name: "x", language: "xx", rules: ["a"], others: []) == .unknownLanguage, "知らない言語は保存しない")
        check(CustomStyle.validate(name: "x", language: "ja", rules: Array(repeating: "a", count: 21), others: []) == .tooManyRules, "ルールは 20 行まで")
        check(CustomStyle.validate(name: "x", language: "ja", rules: Array(repeating: "a", count: 20), others: []) == nil, "20 行は保存できる")
        check(CustomStyle.validate(name: "x", language: "ja", rules: [String(repeating: "あ", count: 2_001)], others: []) == .rulesTooLong, "ルールは 2,000 字まで")
        check(CustomStyle.validate(name: "x", language: "ja", rules: [String(repeating: "あ", count: 2_000)], others: []) == nil, "2,000 字は保存できる")
        check(CustomStyle.rules(fromText: " 一つ目 \n\n二つ目\r\n  ") == ["一つ目", "二つ目"], "1 行 1 ルールに分け、空行を除く")

        // 保存と読み直し（使い捨ての suite）
        let suiteName = "dev.mactypeless.Hanasu.selftest-styles-\(ProcessInfo.processInfo.processIdentifier)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }
        let store = CustomStyleStore(defaults: suite)
        let style = CustomStyle(name: "報告書", language: "ja", rules: ["a", "b"])
        store.upsert(style)
        check(CustomStyleStore(defaults: suite).styles == [style], "保存したカスタム文体を読み直せる")
        var edited = style
        edited.rules = ["c"]
        store.upsert(edited)
        check(CustomStyleStore.saved(in: suite) == [edited], "同じ ID は置き換える")
    }

    // 設計判断: DEC-DIC-213
    private static func assignment() {
        let id = UUID()
        var style = AppStyle(bundleID: "a", name: "A", preset: .chat)
        style.selectCustomStyle(id)
        check(style.preset == .none && style.customStyleID == id && style.hasRules, "カスタム文体を選ぶと preset は none、hasRules は true")
        style.selectPreset(.email)
        check(style.preset == .email && style.customStyleID == nil, "組み込みのプリセットを選ぶと割り当てを外す（--style も同じ）")
        style.selectCustomStyle(id)
        style.rules = "絵文字は使わない"
        let removed = AppStyleStore.removingCustomStyle(id: id, from: [style, AppStyle(bundleID: "b", name: "B", preset: .chat)])
        check(removed[0].customStyleID == nil && removed[0].preset == .none && removed[0].rules == "絵文字は使わない" && removed[1].preset == .chat,
              "カスタム文体を消すと、使っていたアプリは「なし」（追加ルールは残る）")
        check(AppStyleStore.defaultStyles.allSatisfy { $0.customStyleID == nil }, "初期の割り当てにカスタム文体はない（初期設定に戻すと割り当てだけが戻る）")
        let old = Data(#"[{"bundleID":"x","name":"X","preset":"chat","rules":"","outputLanguage":"japanese"}]"#.utf8)
        check((try? JSONDecoder().decode([AppStyle].self, from: old))?.first?.customStyleID == nil, "前の版の設定（customStyleID なし）を読める")
        if let data = try? JSONEncoder().encode([style]), let decoded = try? JSONDecoder().decode([AppStyle].self, from: data) {
            check(decoded == [style], "割り当てを保存して読み直せる")
        } else {
            check(false, "割り当てを保存して読み直せる")
        }
    }

    // 要件: REQ-DIC-023
    // 設計判断: DEC-DIC-214
    private static func prompts() {
        let ja = CustomStyle(name: "秘密の名前", language: "ja", rules: ["文末は である調", "読点は「，」"])
        let en = CustomStyle(name: "Secret Name", language: "en", rules: ["Use contractions"])
        let all = [ja, en]
        let guardLine = Prompts.text("style.learnedGuard")
        var style = AppStyle(bundleID: "x", name: "X", preset: .none)
        style.selectCustomStyle(ja.id)

        let refine = style.promptSection(appName: "Word", translation: nil, hasCommonRules: false, customStyles: all) ?? ""
        check(refine.contains("- 文末は である調\n- 読点は「，」\n" + guardLine), "整形: カスタム文体のルールと歯止めの行を並べる", refine)
        check(!refine.contains("秘密の名前"), "カスタム文体の名前は送らない")
        check(refine.contains(Prompts.text("style.headerWithApp", ["app": "Word"])), "アプリ名を送る設定なら見出しにアプリ名")
        check(!refine.contains(Prompts.list("style.chat.refine").first ?? "-"), "組み込みのプリセットのルールは入らない")
        let noApp = style.promptSection(appName: nil, translation: nil, hasCommonRules: true, customStyles: all) ?? ""
        check(noApp.hasPrefix(Prompts.text("style.header")) && noApp.contains(Prompts.text("style.priorityOverCommonRules")),
              "アプリ名を送らない設定では見出しに名前を入れない・共通ルールとの優先順位を書く", noApp)

        check(style.promptSection(appName: "Word", translation: .english, hasCommonRules: false, customStyles: all) == nil,
              "英訳では日本語のカスタム文体を使わない（足すものがなければ節を出さない）")
        check(style.promptSection(appName: "Word", translation: .japanese, hasCommonRules: false, customStyles: all)?.contains(guardLine) == true,
              "和訳では日本語のカスタム文体を使う")
        style.rules = "絵文字は使わない"
        let english = style.promptSection(appName: "Word", translation: .english, hasCommonRules: false, customStyles: all) ?? ""
        check(english.contains(Prompts.text("style.custom")) && english.contains("  絵文字は使わない") && !english.contains("である調"),
              "言語が違えばカスタム文体は入らず、アプリの追加ルールは入る", english)
        check(english.contains(Prompts.text("style.customTranslationNote")), "アプリの追加ルールには今までどおり読み替えの注記を付ける")
        let both = style.promptSection(appName: "Word", translation: nil, hasCommonRules: false, customStyles: all) ?? ""
        check(both.contains(guardLine + "\n" + Prompts.text("style.customOverridesPreset")), "カスタム文体のあとにアプリの追加ルール（こちらを優先）", both)

        var englishStyle = AppStyle(bundleID: "x", name: "X", preset: .none)
        englishStyle.selectCustomStyle(en.id)
        let matched = englishStyle.promptSection(appName: nil, translation: .english, hasCommonRules: false, customStyles: all) ?? ""
        check(matched.contains("- Use contractions\n" + guardLine) && !matched.contains(Prompts.text("style.customTranslationNote")),
              "英訳では英語のカスタム文体を使い、読み替えの注記は付けない", matched)
        check(englishStyle.promptSection(appName: nil, translation: nil, hasCommonRules: false, customStyles: all) == nil,
              "日本語の整形では英語のカスタム文体を使わない")
        check(englishStyle.promptSection(appName: nil, translation: TranslationLanguage(.ko), hasCommonRules: false, customStyles: all) == nil,
              "韓国語への翻訳では英語のカスタム文体を使わない")

        // 整形の出力の言語は文字起こしの言語（話した言語のまま・統一のどちらでも。DEC-DIC-200）
        let saved = PromptLanguage.override
        PromptLanguage.override = .en
        check(englishStyle.promptSection(appName: nil, translation: nil, hasCommonRules: false, customStyles: all) != nil,
              "文字起こしの言語が English なら、整形で英語のカスタム文体を使う")
        check(style.promptSection(appName: nil, translation: nil, hasCommonRules: false, customStyles: all)?.contains("である調") == false,
              "文字起こしの言語が English なら、整形で日本語のカスタム文体を使わない")
        PromptLanguage.override = saved

        var unknown = AppStyle(bundleID: "x", name: "X", preset: .none)
        unknown.selectCustomStyle(UUID())
        check(unknown.hasRules && unknown.promptSection(appName: "X", translation: nil, hasCommonRules: false, customStyles: all) == nil,
              "見つからないカスタム文体は「なし」として扱う")
    }
}
