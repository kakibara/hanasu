import Foundation

// 設計判断: DEC-DIC-086
/// ユーザー辞書の置き換えの確認（`Hanasu --test-dictionary`）。
/// このパッケージは Command Line Tools だけでビルドするので XCTest / Swift Testing が使えない。
/// そのため、確認する例をここに並べ、CLI から実行して結果を表示する。
enum UserDictionarySelfTest {
    struct Case {
        var name: String
        var dictionary: String
        var input: String
        var expected: String
    }

    static let cases: [Case] = [
        // 今までの書き方（語だけ）は置き換えない
        Case(name: "語だけの行は置き換えない", dictionary: "Stockmark\nVertex AI", input: "すとっくまーくとばーてっくす", expected: "すとっくまーくとばーてっくす"),
        Case(name: "基本の置き換え", dictionary: "ストックマーク => Stockmark", input: "ストックマークの資料です。", expected: "Stockmarkの資料です。"),
        Case(name: "読みを複数書ける", dictionary: "えーにゅーす, エーニュース、エイニュース => Anews",
             input: "えーにゅーすとエーニュースとエイニュース", expected: "AnewsとAnewsとAnews"),
        Case(name: "ひらがなの読みは助詞が続いても効く", dictionary: "えーにゅーす => Anews", input: "えーにゅーすを使う", expected: "Anewsを使う"),
        Case(name: "全角の矢印", dictionary: "ストックマーク ＝＞ Stockmark\nえーにゅーす → Anews", input: "ストックマークのえーにゅーす", expected: "StockmarkのAnews"),
        // 大文字小文字・全角半角
        Case(name: "大文字小文字を区別しない", dictionary: "anews => Anews", input: "ANEWS と anews と Anews", expected: "Anews と Anews と Anews"),
        Case(name: "全角英数字を半角と同じに扱う", dictionary: "anews => Anews\ngpt4 => GPT-4", input: "ＡＮＥＷＳとＧＰＴ４", expected: "AnewsとGPT-4"),
        Case(name: "半角カタカナを全角と同じに扱う", dictionary: "ストックマーク => Stockmark", input: "ｽﾄｯｸﾏｰｸです", expected: "Stockmarkです"),
        Case(name: "ひらがなとカタカナは区別する", dictionary: "ストックマーク => Stockmark", input: "すとっくまーく", expected: "すとっくまーく"),
        // 空白
        Case(name: "空白の有無を区別しない（文中の空白）", dictionary: "ストックマーク => Stockmark", input: "ストック マークの話", expected: "Stockmarkの話"),
        Case(name: "空白の有無を区別しない（読みの空白）", dictionary: "vertex ai => Vertex AI", input: "VertexAIとvertex　ai", expected: "Vertex AIとVertex AI"),
        // 誤爆を防ぐ
        Case(name: "英字は単語の途中で置き換えない", dictionary: "ai => AI", input: "OpenAIとmaintainとaiとAI活用", expected: "OpenAIとmaintainとAIとAI活用"),
        Case(name: "英字の後ろ側の境界", dictionary: "gpt => GPT", input: "gptsとchatgptとgpt", expected: "gptsとchatgptとGPT"),
        Case(name: "カタカナは語の途中で置き換えない", dictionary: "マーク => Mark", input: "マークダウンとストックマークとマークを付ける", expected: "マークダウンとストックマークとMarkを付ける"),
        Case(name: "中黒と括弧は境界になる", dictionary: "マーク => Mark", input: "「マーク」・マーク", expected: "「Mark」・Mark"),
        Case(name: "1 文字の読みは使わない", dictionary: "株 => カブ", input: "株式会社", expected: "株式会社"),
        Case(name: "長い読みを優先する", dictionary: "ストック => Stock\nストックマーク => Stockmark", input: "ストックマークとストック", expected: "StockmarkとStock"),
        Case(name: "同じ読みは上の行を使う", dictionary: "ストックマーク => Stockmark\nストックマーク => STOCKMARK", input: "ストックマーク", expected: "Stockmark"),
        Case(name: "置き換えた結果に重ねて当てない", dictionary: "えーあい => AI系\nai系 => X", input: "えーあい", expected: "AI系"),
        Case(name: "表記の大文字小文字を直す（同じ語のルール）", dictionary: "stockmark => Stockmark", input: "stockmarkとSTOCKMARKとStockmark", expected: "StockmarkとStockmarkとStockmark"),
        // 書き方の扱い
        Case(name: "コメントと空行は無視する", dictionary: "# 社名\n\nストックマーク => Stockmark", input: "ストックマーク", expected: "Stockmark"),
        Case(name: "表記が空のルールは使わない", dictionary: "ストックマーク =>", input: "ストックマーク", expected: "ストックマーク"),
        Case(name: "漢字の誤認識", dictionary: "穴ニュース => Anews", input: "穴ニュースを見た", expected: "Anewsを見た"),
    ]

    /// すべての例を実行して結果を表示し、失敗した数を返す
    static func run() -> Int {
        var failures = 0
        for c in cases {
            let output = UserDictionary(text: c.dictionary).apply(to: c.input)
            let ok = output == c.expected
            if !ok { failures += 1 }
            print("\(ok ? "OK  " : "FAIL") \(c.name)")
            if !ok { print("     入力: \(c.input)\n     期待: \(c.expected)\n     結果: \(output)") }
        }
        failures += checkLists()
        print("\(cases.count + 1 - failures)/\(cases.count + 1) 件 OK")
        return failures
    }

    /// 語の一覧・語彙ヒント・注意の確認
    private static func checkLists() -> Int {
        let dictionary = UserDictionary(text: """
            Hanasu
            ストックマーク, すとっくまーく => Stockmark
            # メモ
            Stockmark
            株 => カブ
            えーにゅーす =>
            ストックマーク => STOCKMARK
            """)
        var problems: [String] = []
        if dictionary.spellings != ["Hanasu", "Stockmark", "カブ", "STOCKMARK"] {
            problems.append("spellings: \(dictionary.spellings)")
        }
        if dictionary.contextualStrings != ["Hanasu", "Stockmark", "カブ", "STOCKMARK", "ストックマーク", "すとっくまーく"] {
            problems.append("contextualStrings: \(dictionary.contextualStrings)")
        }
        if dictionary.rules != [UserDictionary.Rule(sources: ["ストックマーク", "すとっくまーく"], target: "Stockmark")] {
            problems.append("rules: \(dictionary.rules)")
        }
        if Set(dictionary.issues.keys) != [4, 5, 6] {
            problems.append("issues: \(dictionary.issues)")
        }
        // 書き出すと元の文字に戻る（表で編集してもコメントが消えない）
        let text = "# メモ\nストックマーク => Stockmark\n\nHanasu"
        if UserDictionary(text: text).text != text {
            problems.append("text の往復: \(UserDictionary(text: text).text)")
        }
        print("\(problems.isEmpty ? "OK  " : "FAIL") 語の一覧・語彙ヒント・注意・書き出し")
        for p in problems { print("     \(p)") }
        return problems.isEmpty ? 0 : 1
    }
}
