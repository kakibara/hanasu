import Foundation

/// 整形の言語（REQ-DIC-082）の確認用 CLI（AI は呼ばない）
///   Hanasu --test-refine-language
///       保存値の読み方、表示の言語とプロンプトの言語の組み合わせごとの「〈利用者の言語〉に統一」の名前、
///       統一の指示がプロンプトの言語の JSON の文面と同じことを確かめる。名前は標準出力にも出す
enum RefineLanguageCLI {
    // 確かめ方: REQ-DIC-082
    static func runIfRequested(_ args: [String] = CommandLine.arguments) {
        guard args.contains("--test-refine-language") else { return }
        exit(test() ? 0 : 1)
    }

    private final class Checker {
        var failures = 0
        func check(_ name: String, _ condition: Bool) {
            print("\(condition ? "OK  " : "FAIL") \(name)")
            if !condition { failures += 1 }
        }
    }

    private static func test() -> Bool {
        let checker = Checker()
        let check = checker.check
        typealias Language = GeminiClient.RefineOutputLanguage
        let savedUI = UILanguage.override
        let savedPrompt = PromptLanguage.override
        defer {
            UILanguage.override = savedUI
            PromptLanguage.override = savedPrompt
        }

        // 設計判断: DEC-DIC-201（保存値は前の版の japanese のまま。知らない値は話した言語）
        check("保存値 japanese は「統一する」", Language(rawValue: "japanese") == .unified)
        check("保存値 asSpoken は「話した言語」", Language(rawValue: "asSpoken") == .asSpoken)
        check("知らない保存値は読めない（設定の読み込みで「話した言語」にする）", Language(rawValue: "xyz") == nil)
        check("「統一する」を保存すると japanese", Language.unified.rawValue == "japanese")

        // 要件: REQ-DIC-082（名前は、プロンプトの言語の名前を表示の言語で書いたもの）
        let names: [(ui: PromptLanguage, prompt: PromptLanguage, expected: String)] = [
            (.ja, .ja, "日本語に統一"),
            (.ko, .ko, "한국어로 통일"),
            (.en, .ja, "Always Japanese"),
            (.ja, .en, "英語に統一"),
        ]
        for (ui, prompt, expected) in names {
            UILanguage.override = ui
            PromptLanguage.override = prompt
            let label = Language.unified.label
            check("表示 \(ui.rawValue)・プロンプト \(prompt.rawValue) の名前は「\(expected)」（\(label)）", label == expected)
        }
        // 17 言語の表示で、プロンプトの言語と同じときの名前（訳の見た目を確かめる）
        for language in PromptLanguage.allCases {
            UILanguage.override = language
            PromptLanguage.override = language
            let label = Language.unified.label
            print("     \(language.rawValue): \(Language.asSpoken.label) / \(label)")
            check("\(language.rawValue) の名前に言語名が入る", label.contains(TranslationLanguage(language).nameInUILanguage))
        }

        // 設計判断: DEC-DIC-200（統一の指示は、プロンプトの言語の JSON の refine.outputLanguage.unified）
        for language in PromptLanguage.allCases {
            PromptLanguage.override = language
            check("\(language.rawValue) の統一の指示は \(language.rawValue).json の文面",
                  Language.unified.instruction == Prompts.text("refine.outputLanguage.unified", language: language))
        }
        // 対応言語にない文字起こしの言語は、英語に統一する（REQ-COM-061）
        check("対応言語にない文字起こしの言語（sv-SE）のプロンプトの言語は英語", PromptLanguage.from(localeIdentifier: "sv-SE") == .en)

        print(checker.failures == 0 ? "すべて OK" : "\(checker.failures) 件の失敗")
        return checker.failures == 0
    }
}
