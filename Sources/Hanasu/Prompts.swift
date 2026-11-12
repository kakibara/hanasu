import Foundation
import os

// 要件: REQ-COM-061
// 設計判断: DEC-COM-161
/// AI へのプロンプトの言語。文字起こしの言語（設定の「言語」。REQ-COM-004）から決める。
/// 対応言語（README と同じ 17 言語）にないときは英語。Windows 版の PromptLanguage と同じ決まり（両方を直す）
enum PromptLanguage: String, CaseIterable, Sendable {
    case en, ja
    case zhCN = "zh-CN"
    case zhTW = "zh-TW"
    case ko, es, fr, de, it
    case ptBR = "pt-BR"
    case ru, tr, vi, id, pl, ar, hi

    // 設計判断: DEC-COM-161
    /// 言語の識別子（ja-JP、zh-Hant-TW、pt_PT など）を、対応言語のどれかに寄せる。
    /// 中国語は繁体字（Hant）か台湾・香港・マカオなら zh-TW、それ以外は zh-CN。ポルトガル語は pt-BR。どれでもなければ英語
    static func from(localeIdentifier: String) -> PromptLanguage {
        supported(localeIdentifier: localeIdentifier) ?? .en
    }

    /// 対応言語のどれかに寄せる。どれでもなければ nil
    static func supported(localeIdentifier: String) -> PromptLanguage? {
        let trimmed = localeIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "_", with: "-")
        let language = Locale.Language(identifier: trimmed)
        guard let code = language.languageCode?.identifier.lowercased() else { return nil }
        switch code {
        case "zh":
            let script = language.script?.identifier
            let region = language.region?.identifier
            return script == "Hant" || ["TW", "HK", "MO"].contains(region ?? "") ? .zhTW : .zhCN
        case "pt": return .ptBR
        case "in": return .id
        default: return PromptLanguage(rawValue: code)
        }
    }

    /// CLI で一時的に変える（--prompt-language）。self-test は日本語に固定する
    nonisolated(unsafe) static var override: PromptLanguage?

    /// いまのプロンプトの言語（設定の文字起こしの言語。保存されていなければシステムの言語）
    static var current: PromptLanguage {
        if let override { return override }
        let stored = SettingsDefaults.store.string(forKey: "localeIdentifier")
        return from(localeIdentifier: stored ?? AppSettings.systemLocaleIdentifier)
    }

    /// 日付の曜日や言語名を、この言語で書くためのロケール
    var locale: Locale {
        Locale(identifier: self == .ja ? "ja_JP" : rawValue)
    }

    /// プロンプトに書く日時（「2026/11/02 (月) 14:30」の形。曜日はこの言語で）
    var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = "yyyy/MM/dd (E) HH:mm"
        return f
    }

    /// CLI の引数（--prompt-language <言語>）。省くと設定の文字起こしの言語。対応していない言語を書いたら止める
    /// （黙って英語にすると、確かめたつもりの言語と違うプロンプトを見てしまうため）
    static func cli(_ args: [String]) -> PromptLanguage? {
        guard let index = args.firstIndex(of: "--prompt-language") else { return nil }
        let value = args.indices.contains(index + 1) ? args[index + 1] : ""
        if let language = PromptLanguage(rawValue: value) ?? supported(localeIdentifier: value) { return language }
        FileHandle.standardError.write(Data("error: --prompt-language は \(allCases.map(\.rawValue).joined(separator: "|")) のどれか（\(value) は対応していない）\n".utf8))
        exit(2)
    }
}

// 設計判断: DEC-COM-160
/// AI へのプロンプトの文面。言語ごとの JSON（Sources/Hanasu/Resources/Prompts/<言語>.json）から読む。
/// Windows 版も同じファイルを埋め込んで読むので、Mac と Windows で同じ文面になる（DEC-COM-102）。
/// 値は文字列か、1 行 1 要素の配列（`list` で読むものは 1 項目 1 要素）。`${name}` は引数で埋める。
enum Prompts {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var tables: [PromptLanguage: [String: Any]] = [:]

    /// キーの文面。その言語になければ英語、英語にもなければ日本語を使う（漏れは scripts/check-i18n.py が見つける）
    static func text(_ key: String, _ args: [String: String] = [:], language: PromptLanguage = .current) -> String {
        let value = lookup(key, language: language)
        let joined: String
        if let lines = value as? [String] {
            joined = lines.joined(separator: "\n")
        } else {
            joined = value as? String ?? ""
        }
        return fill(joined, args)
    }

    /// 項目の一覧（アプリ別の文体のルールなど）
    static func list(_ key: String, language: PromptLanguage = .current) -> [String] {
        let value = lookup(key, language: language)
        if let items = value as? [String] { return items }
        if let item = value as? String { return [item] }
        return []
    }

    /// すべての言語での文面（古い議事録や、ほかの言語で作った議事録を読むときに使う）
    static func allTexts(_ key: String) -> [String] {
        var seen: [String] = []
        for language in PromptLanguage.allCases {
            let text = text(key, language: language)
            if !text.isEmpty, !seen.contains(text) { seen.append(text) }
        }
        return seen
    }

    /// `${name}` を引数で埋める。1 回だけ走査するので、埋めた値の中の `${…}` はそのまま残る
    static func fill(_ template: String, _ args: [String: String]) -> String {
        guard !args.isEmpty, template.contains("${") else { return template }
        var result = ""
        var rest = template[...]
        while let open = rest.range(of: "${") {
            result += rest[..<open.lowerBound]
            guard let close = rest[open.upperBound...].firstIndex(of: "}") else {
                rest = rest[open.lowerBound...]
                break
            }
            let name = String(rest[open.upperBound..<close])
            result += args[name] ?? "${\(name)}"
            rest = rest[rest.index(after: close)...]
        }
        return result + rest
    }

    private static func lookup(_ key: String, language: PromptLanguage) -> Any? {
        for candidate in [language, .en, .ja] {
            if let value = table(candidate)[key] { return value }
        }
        appLog.error("prompt key not found: \(key, privacy: .public)")
        assertionFailure("プロンプトのキーがありません: \(key)")
        return nil
    }

    private static func table(_ language: PromptLanguage) -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        if let table = tables[language] { return table }
        var table: [String: Any] = [:]
        if let url = HanasuResources.url(forResource: language.rawValue, withExtension: "json", subdirectory: "Prompts"),
           let data = try? Data(contentsOf: url),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            table = object
        } else {
            appLog.error("prompts not found: \(language.rawValue, privacy: .public)")
        }
        tables[language] = table
        return table
    }
}

// 設計判断: DEC-COM-160
/// SwiftPM のリソースのバンドル（Hanasu_Hanasu.bundle）。
/// SwiftPM が作る Bundle.module は、.app の外（ビルドしたマシンのパス）も見に行き、見つからないと止まるので使わない。
/// .app では Contents/Resources に、`swift build` の実行ファイルでは隣にある（scripts/build-app.sh が .app に入れる）
enum HanasuResources {
    static let bundleName = "Hanasu_Hanasu.bundle"

    static let bundle: Bundle? = {
        let bases = [Bundle.main.resourceURL, Bundle.main.bundleURL, Bundle.main.executableURL?.deletingLastPathComponent()]
        for base in bases.compactMap({ $0 }) {
            let url = base.appendingPathComponent(bundleName)
            if FileManager.default.fileExists(atPath: url.path), let bundle = Bundle(url: url) { return bundle }
        }
        return nil
    }()

    static func url(forResource name: String, withExtension ext: String, subdirectory: String) -> URL? {
        guard let bundle else { return nil }
        // SwiftPM のバンドルは Contents/Resources を持たない平らな形のことがあるので、両方を見る
        for base in [bundle.resourceURL, bundle.bundleURL].compactMap({ $0 }) {
            let url = base.appendingPathComponent(subdirectory).appendingPathComponent("\(name).\(ext)")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }
}
