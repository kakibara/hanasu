import Foundation
import os

// 要件: REQ-COM-060
// 設計判断: DEC-COM-165, DEC-COM-166
/// 表示の言語（UI の文字列）。システムの言語（優先する言語の並び）のうち、対応している最初の言語。
/// どれにも対応していなければ英語。AI へのプロンプトの言語（PromptLanguage。文字起こしの言語で決まる）とは別に決まる
enum UILanguage {
    nonisolated(unsafe) static var override: PromptLanguage?

    /// CLI の --ui-language か self-test が決めた言語。なければシステムの言語から決めたもの
    static var current: PromptLanguage { override ?? system }

    private static let system: PromptLanguage = resolve(Locale.preferredLanguages)

    /// 優先する言語の並びから、対応している最初の言語を選ぶ（なければ英語）
    static func resolve(_ preferred: [String]) -> PromptLanguage {
        for identifier in preferred {
            if let language = PromptLanguage.supported(localeIdentifier: identifier) { return language }
        }
        return .en
    }

    /// 日付・数の書式に使うロケール
    static var locale: Locale { current.locale }
}

// 要件: REQ-COM-060
// 設計判断: DEC-COM-165
/// UI の文字列。キーは日本語の原文で、訳は Sources/Hanasu/Resources/Localizable.xcstrings（String Catalog）にある。
/// Xcode の xcstringstool がなくてもビルドできるよう、カタログの JSON を起動後に一度だけ読む。
/// 補間は `%@`（引数は文字列にして渡す）。訳では `%1$@` のように順番を変えてよい
func tr(_ key: String, _ args: CVarArg...) -> String {
    let format = L10n.lookup(key, language: UILanguage.current)
    guard !args.isEmpty else { return format }
    return String(format: format, locale: UILanguage.locale, arguments: args)
}

enum L10n {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var catalog: [String: [String: String]]?

    static func lookup(_ key: String, language: PromptLanguage) -> String {
        if language == .ja { return key }
        let strings = load()
        guard let entry = strings[key] else { return key }
        return entry[language.rawValue] ?? entry["en"] ?? key
    }

    /// キー → (言語 → 訳)
    static func load() -> [String: [String: String]] {
        lock.lock()
        defer { lock.unlock() }
        if let catalog { return catalog }
        var result: [String: [String: String]] = [:]
        if let url = HanasuResources.url(forResource: "Localizable", withExtension: "xcstrings", subdirectory: ""),
           let data = try? Data(contentsOf: url),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let strings = object["strings"] as? [String: Any] {
            for (key, value) in strings {
                guard let localizations = (value as? [String: Any])?["localizations"] as? [String: Any] else { continue }
                var entry: [String: String] = [:]
                for (language, unit) in localizations {
                    if let value = ((unit as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String {
                        entry[language] = value
                    }
                }
                result[key] = entry
            }
        } else {
            appLog.error("Localizable.xcstrings not found")
        }
        catalog = result
        return result
    }
}
