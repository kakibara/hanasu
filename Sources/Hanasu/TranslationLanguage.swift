import Foundation

// 要件: REQ-DIC-013
// 設計判断: DEC-DIC-027
/// 翻訳して入力するときの言語。対応言語（PromptLanguage の 17 言語）のどれにでも訳せる。
/// 言語の一覧はここに書かず PromptLanguage から作るので、対応言語を足せば翻訳の言語にも出る。
/// 並び（allCases の順。PromptLanguage の順で English → 日本語 → …）は HUD・メニュー・履歴・設定に出す順
struct TranslationLanguage: Hashable, Identifiable, Sendable, Codable {
    let language: PromptLanguage

    init(_ language: PromptLanguage) {
        self.language = language
    }

    static let english = TranslationLanguage(.en)
    static let japanese = TranslationLanguage(.ja)

    static var allCases: [TranslationLanguage] { PromptLanguage.allCases.map(TranslationLanguage.init) }

    // 設計判断: DEC-DIC-027
    /// 保存する値。English と日本語は今までの値（english / japanese）のまま、ほかは言語のコード（zh-CN、ko など）
    var rawValue: String {
        switch language {
        case .en: "english"
        case .ja: "japanese"
        default: language.rawValue
        }
    }

    /// 保存した値から戻す。知らない値なら nil
    init?(rawValue: String) {
        switch rawValue {
        case "english": self = .english
        case "japanese": self = .japanese
        default:
            guard let language = PromptLanguage(rawValue: rawValue) else { return nil }
            self.init(language)
        }
    }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        guard let language = TranslationLanguage(rawValue: value) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "unknown translation language: \(value)"))
        }
        self = language
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var id: String { rawValue }

    // 設計判断: DEC-DIC-150
    /// HUD の切り替えやアプリ別の出力言語に出す名前。その言語での言語名（English、日本語、한국어、Español …）なので、表示の言語によらない。
    /// 文面は Resources/Prompts/<その言語>.json の languageName.<その言語>
    var label: String {
        let name = Prompts.text("languageName.\(language.rawValue)", language: language)
        return name.prefix(1).uppercased(with: language.locale) + name.dropFirst()
    }

    /// 表示の言語での言語名（「英語」「韓国語」など。Resources/Prompts/<表示の言語>.json の languageName.<その言語>）
    var nameInUILanguage: String {
        Prompts.text("languageName.\(language.rawValue)", language: UILanguage.current)
    }

    /// プロンプトの言語での言語名（翻訳のプロンプトに書く）
    var nameInPromptLanguage: String {
        Prompts.text("languageName.\(language.rawValue)")
    }

    /// 設定で、その言語での言語名の下に添える、表示の言語での名前。同じ（表示の言語そのもの）なら nil
    var subtitleInUILanguage: String? {
        let name = nameInUILanguage
        return label.compare(name, options: .caseInsensitive) == .orderedSame ? nil : name
    }

    /// 「英訳」「和訳」「韓国語訳」
    var verb: String {
        switch self {
        case .english: tr("英訳")
        case .japanese: tr("和訳")
        default: tr("%@訳", nameInUILanguage)
        }
    }

    /// 処理中の HUD の見出し
    var processingTitle: String {
        switch self {
        case .english: tr("AI で英語に翻訳しています…")
        case .japanese: tr("AI で日本語に翻訳しています…")
        default: tr("AI で%@に翻訳しています…", nameInUILanguage)
        }
    }

    // 設計判断: DEC-DIC-022, DEC-DIC-028
    /// 訳した結果が日本語か。日本語なら、整形と同じ日本語向けのルール（共通の追加ルール・アプリ別の整形のルール・画面の文脈の整形の指示）を使う
    var outputsJapanese: Bool { self == .japanese }

    /// 設定の並びにそろえ、重複と空を直す（空なら English だけ）
    static func normalized(_ languages: [TranslationLanguage]) -> [TranslationLanguage] {
        let picked = allCases.filter(languages.contains)
        return picked.isEmpty ? [.english] : picked
    }

    /// 選んだ言語が 1 つならその言語の動詞、2 つ以上なら「翻訳」（メニュー・設定の項目名）
    static func menuVerb(for languages: [TranslationLanguage]) -> String {
        languages.count == 1 ? languages[0].verb : tr("翻訳")
    }

    /// CLI の `--translate-to <言語>`（`--translate` だけなら English）。どちらもなければ nil
    static func cli(_ args: [String]) -> TranslationLanguage? {
        if let index = args.firstIndex(of: "--translate-to"), args.indices.contains(index + 1) {
            return cliCode(args[index + 1])
        }
        return args.contains("--translate") ? .english : nil
    }

    /// 言語のコード（en、ja、zh-CN、ko …。english / japanese と、ja-JP のような地域付きも受け付ける）。CLI の `--languages en,ko` にも使う
    static func cliCode(_ code: String) -> TranslationLanguage? {
        if let language = TranslationLanguage(rawValue: code.lowercased()) { return language }
        return PromptLanguage(rawValue: code).map(TranslationLanguage.init)
            ?? PromptLanguage.supported(localeIdentifier: code).map(TranslationLanguage.init)
    }
}
