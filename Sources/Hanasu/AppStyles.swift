import AppKit
import Combine

// 設計判断: DEC-DIC-040, DEC-DIC-041, DEC-DIC-042
/// 入力先アプリに合わせた文体のひな形。アプリにはどれか 1 つを割り当てる。
enum AppStylePreset: String, Codable, CaseIterable, Identifiable {
    case none
    case chat
    case email
    case documentPolite
    case documentPlain

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: tr("なし")
        case .chat: tr("チャット")
        case .email: tr("メール")
        case .documentPolite: tr("文書（です・ます）")
        case .documentPlain: tr("文書（である）")
        }
    }

    /// 設定画面に出す短い説明
    var summary: String {
        switch self {
        case .none: tr("プリセットを使わない（このアプリ用の追加ルールだけを使う）")
        case .chat: tr("くだけた短い文。段落は作らない")
        case .email: tr("丁寧な文体（です・ます調）。まとまりごとに段落を分ける")
        case .documentPolite: tr("書き言葉の です・ます調 に統一し、段落を分ける")
        case .documentPlain: tr("書き言葉の である調 に統一し、段落を分ける")
        }
    }

    // 要件: REQ-COM-061
    /// 話した言語で整えるときのルール（文面は Resources/Prompts/<言語>.json の style.<プリセット>.refine）。
    /// 出力が日本語（和訳・整形の「日本語に統一」）なら、language に .ja を渡して日本語の文体のルールにする（DEC-DIC-028）
    func refineRules(language: PromptLanguage = .current) -> [String] {
        self == .none ? [] : Prompts.list("style.\(rawValue).refine", language: language)
    }

    // 要件: REQ-COM-061
    /// 日本語以外に訳すときのルール。日本語の語尾の違い（です・ます／である）は区別しない。
    /// 英訳は英語向けの style.<プリセット>.translation、ほかの言語は言語を名指ししない style.<プリセット>.translationOther
    func translationRules(for language: TranslationLanguage) -> [String] {
        let suffix = language == .english ? "translation" : "translationOther"
        switch self {
        case .none: return []
        case .chat, .email: return Prompts.list("style.\(rawValue).\(suffix)")
        case .documentPolite, .documentPlain: return Prompts.list("style.document.\(suffix)")
        }
    }
}

// 要件: REQ-DIC-021, REQ-DIC-013
// 設計判断: DEC-DIC-153
/// アプリごとの既定の出力言語。「話した言語」か、翻訳の言語（TranslationLanguage.allCases。対応言語の一覧から作る）のどれか
enum AppOutputLanguage: Hashable, Codable, Identifiable {
    case asSpoken
    case translate(TranslationLanguage)

    static var allCases: [AppOutputLanguage] { [.asSpoken] + TranslationLanguage.allCases.map(AppOutputLanguage.translate) }

    // 設計判断: DEC-DIC-153
    /// 保存する値。今までの値（話した言語は "japanese"、English は "english"、日本語は "translateJapanese"）はそのまま、
    /// ほかの言語は "translate:<言語のコード>"
    var rawValue: String {
        switch self {
        case .asSpoken: "japanese"
        case .translate(.english): "english"
        case .translate(.japanese): "translateJapanese"
        case .translate(let language): "translate:\(language.language.rawValue)"
        }
    }

    /// 保存した値から戻す。知らない値（新しい版で足した言語など）は「話した言語」にする（アプリ別の設定全体を読めなくしない）
    init(rawValue: String) {
        switch rawValue {
        case "english": self = .translate(.english)
        case "translateJapanese": self = .translate(.japanese)
        default:
            if rawValue.hasPrefix("translate:"), let language = PromptLanguage(rawValue: String(rawValue.dropFirst("translate:".count))) {
                self = .translate(TranslationLanguage(language))
            } else {
                self = .asSpoken
            }
        }
    }

    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var id: String { rawValue }
    var label: String {
        translation?.label ?? tr("話した言語")
    }

    /// 翻訳して始める言語。「話した言語」なら nil
    var translation: TranslationLanguage? {
        switch self {
        case .asSpoken: nil
        case .translate(let language): language
        }
    }
}

/// 1 つのアプリ（bundle ID）の整形スタイル
struct AppStyle: Codable, Identifiable, Equatable {
    var bundleID: String
    /// 表示名。アプリが見つからないときにも使う
    var name: String
    var preset: AppStylePreset
    /// このアプリ用の追加ルール（Gemini に渡す）
    var rules: String = ""
    var outputLanguage: AppOutputLanguage = .asSpoken

    var id: String { bundleID }

    /// プロンプトに足すものがあるか（出力言語だけを決めたアプリでは false）
    var hasRules: Bool {
        preset != .none || !rules.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // 要件: REQ-DIC-020
    // 設計判断: DEC-DIC-043, DEC-DIC-044, DEC-DIC-046, DEC-DIC-028
    /// `GeminiClient.userPrompt` に足す節。足すものがなければ nil。
    /// - appName: 入力先アプリ名を Gemini に伝える設定がオフなら nil（名前を出さない）
    /// - translation: 翻訳の言語（整形なら nil）。和訳は出力が日本語なので、整形と同じ日本語の文体ルールを使う
    /// - hasCommonRules: 共通の追加ルールがプロンプトに入っているか（入っていれば優先順位を書く）
    /// - japaneseOutput: 整形の出力を日本語に統一するか（REQ-DIC-082。和訳と同じく日本語の文体のルールにする）
    func promptSection(appName: String?, translation: TranslationLanguage?, hasCommonRules: Bool, japaneseOutput: Bool = false) -> String? {
        guard hasRules else { return nil }
        // 日本語以外に訳すときは、訳す先の言語向けのルールにする。出力が日本語（和訳・日本語に統一）なら、
        // プロンプトの言語によらず日本語の文体のルール（ja.json）にする
        let japanese = translation?.outputsJapanese ?? japaneseOutput
        let target = japanese ? nil : translation
        let presetRules = target.map(preset.translationRules(for:)) ?? preset.refineRules(language: japanese ? .ja : .current)
        let custom = rules.trimmingCharacters(in: .whitespacesAndNewlines)

        var lines: [String] = []
        if let appName, !appName.isEmpty {
            lines.append(Prompts.text("style.headerWithApp", ["app": appName]))
        } else {
            lines.append(Prompts.text("style.header"))
        }
        lines += presetRules.map { "- \($0)" }
        if !custom.isEmpty {
            lines.append(Prompts.text(presetRules.isEmpty ? "style.custom" : "style.customOverridesPreset"))
            lines += custom.split(whereSeparator: \.isNewline).map { "  \($0)" }
            if let target {
                lines.append(target == .english
                    ? Prompts.text("style.customTranslationNote")
                    : Prompts.text("style.customTranslationNoteOther", ["language": target.nameInPromptLanguage]))
            }
        }
        // system instruction の「口調を保つ」と食い違うので、どちらを優先するかを書いておく
        let overridden = Prompts.text(translation != nil ? "style.overrides.translation" : "style.overrides.refine")
        lines.append(Prompts.text("style.priority", ["overridden": overridden]))
        if hasCommonRules {
            lines.append(Prompts.text("style.priorityOverCommonRules"))
        }
        return lines.joined(separator: "\n")
    }
}

// 要件: REQ-DIC-020
// 設計判断: DEC-DIC-040, DEC-DIC-047
/// アプリ別スタイルの一覧。UserDefaults に JSON で保存する（AppSettings とは別に持つ）。
final class AppStyleStore: ObservableObject {
    static let shared = AppStyleStore()

    /// 初期状態のプリセットの割り当て
    static let defaultStyles: [AppStyle] = [
        // チャット
        AppStyle(bundleID: "com.tinyspeck.slackmacgap", name: "Slack", preset: .chat),
        AppStyle(bundleID: "com.microsoft.teams2", name: "Microsoft Teams", preset: .chat),
        AppStyle(bundleID: "com.microsoft.teams", name: "Microsoft Teams (classic)", preset: .chat),
        AppStyle(bundleID: "com.hnc.Discord", name: "Discord", preset: .chat),
        AppStyle(bundleID: "jp.naver.line.mac", name: "LINE", preset: .chat),
        AppStyle(bundleID: "com.apple.MobileSMS", name: tr("メッセージ"), preset: .chat),
        // メール
        AppStyle(bundleID: "com.apple.mail", name: tr("メール"), preset: .email),
        AppStyle(bundleID: "com.microsoft.Outlook", name: "Microsoft Outlook", preset: .email),
        AppStyle(bundleID: "com.readdle.SparkDesktop", name: "Spark", preset: .email),
        AppStyle(bundleID: "com.readdle.smartemail-Mac", name: "Spark (classic)", preset: .email),
        // 文書
        AppStyle(bundleID: "com.apple.iWork.Pages", name: "Pages", preset: .documentPolite),
        AppStyle(bundleID: "com.microsoft.Word", name: "Microsoft Word", preset: .documentPolite),
        AppStyle(bundleID: "notion.id", name: "Notion", preset: .documentPolite),
    ]

    private let defaults = UserDefaults.standard

    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: Keys.enabled) } }
    @Published var styles: [AppStyle] { didSet { save() } }

    private init() {
        defaults.register(defaults: [Keys.enabled: true])
        enabled = defaults.bool(forKey: Keys.enabled)
        if let data = defaults.data(forKey: Keys.styles),
           let decoded = try? JSONDecoder().decode([AppStyle].self, from: data)
        {
            styles = decoded
        } else {
            styles = Self.defaultStyles
        }
    }

    /// 入力先アプリのスタイル。オフのとき・登録がないときは nil
    func style(forBundleID bundleID: String?) -> AppStyle? {
        guard enabled, let bundleID else { return nil }
        return styles.first { $0.bundleID == bundleID }
    }

    /// アプリを追加する。登録済みなら何もしない
    func add(bundleID: String, name: String) {
        guard !styles.contains(where: { $0.bundleID == bundleID }) else { return }
        styles.append(AppStyle(bundleID: bundleID, name: name, preset: .none))
    }

    func resetToDefaults() {
        styles = Self.defaultStyles
    }

    private func save() {
        if let data = try? JSONEncoder().encode(styles) {
            defaults.set(data, forKey: Keys.styles)
        }
    }

    private enum Keys {
        static let enabled = "appStylesEnabled"
        static let styles = "appStyles"
    }
}

/// CLI の `--app <bundle id>` から、アプリ名とスタイルを得る（main.swift の --refine-text 用）
func cliAppStyle(args: [String]) -> (name: String?, style: AppStyle?) {
    guard let index = args.firstIndex(of: "--app"), args.indices.contains(index + 1) else { return (nil, nil) }
    let bundleID = args[index + 1]
    let style = AppStyleStore.shared.style(forBundleID: bundleID)
    let name = style?.name
        ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { FileManager.default.displayName(atPath: $0.path) }
        ?? bundleID
    return (name, style)
}
