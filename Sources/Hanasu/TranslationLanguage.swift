import Foundation

// 要件: REQ-DIC-013
// 設計判断: DEC-DIC-027
/// 翻訳して入力するときの言語。並び（allCases の順）は HUD・メニュー・履歴・設定に出す順
enum TranslationLanguage: String, CaseIterable, Codable, Identifiable {
    case english
    case japanese

    var id: String { rawValue }

    /// HUD の切り替えに出す名前
    var label: String {
        switch self {
        case .english: "English"
        case .japanese: "日本語"
        }
    }

    /// 設定のトグルに出す名前
    var settingsLabel: String {
        switch self {
        case .english: "English（英語）"
        case .japanese: "日本語"
        }
    }

    /// 「英訳」「和訳」
    var verb: String {
        switch self {
        case .english: "英訳"
        case .japanese: "和訳"
        }
    }

    /// 処理中の HUD の見出し
    var processingTitle: String {
        switch self {
        case .english: "AI で英語に翻訳しています…"
        case .japanese: "AI で日本語に翻訳しています…"
        }
    }

    /// 設定の並びにそろえ、重複と空を直す（空なら English だけ）
    static func normalized(_ languages: [TranslationLanguage]) -> [TranslationLanguage] {
        let picked = allCases.filter(languages.contains)
        return picked.isEmpty ? [.english] : picked
    }

    /// 選んだ言語が 1 つならその言語の動詞、2 つ以上なら「翻訳」（メニュー・設定の項目名）
    static func menuVerb(for languages: [TranslationLanguage]) -> String {
        languages.count == 1 ? languages[0].verb : "翻訳"
    }

    /// CLI の `--translate-to en|ja`（`--translate` だけなら English）。どちらもなければ nil
    static func cli(_ args: [String]) -> TranslationLanguage? {
        if let index = args.firstIndex(of: "--translate-to"), args.indices.contains(index + 1) {
            return cliCode(args[index + 1])
        }
        return args.contains("--translate") ? .english : nil
    }

    /// `en` / `ja`（english / japanese も受け付ける）。CLI の `--languages en,ja` にも使う
    static func cliCode(_ code: String) -> TranslationLanguage? {
        switch code.lowercased() {
        case "en", "english": .english
        case "ja", "japanese": .japanese
        default: nil
        }
    }
}
