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
    // 要件: REQ-DIC-023
    // 設計判断: DEC-DIC-213
    /// 割り当てたカスタム文体（CustomStyle.id）。選んだときの preset は none（前の版で読んでも「なし」になる）。
    /// 組み込みのプリセットを選び直したら消す（selectPreset）
    var customStyleID: UUID?

    var id: String { bundleID }

    // 設計判断: DEC-DIC-213
    /// プロンプトに足すものがあるか（出力言語だけを決めたアプリでは false）。カスタム文体を割り当てていれば true
    var hasRules: Bool {
        preset != .none || customStyleID != nil || !rules.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // 要件: REQ-DIC-023
    // 設計判断: DEC-DIC-213
    /// 組み込みのプリセットを選ぶ（画面・hanasu refine --style）。カスタム文体の割り当ては外す
    mutating func selectPreset(_ preset: AppStylePreset) {
        self.preset = preset
        customStyleID = nil
    }

    /// カスタム文体を選ぶ。preset は none にする
    mutating func selectCustomStyle(_ id: UUID) {
        preset = .none
        customStyleID = id
    }

    // 要件: REQ-DIC-020, REQ-DIC-023
    // 設計判断: DEC-DIC-043, DEC-DIC-044, DEC-DIC-046, DEC-DIC-028, DEC-DIC-214
    /// `GeminiClient.userPrompt` に足す節。足すものがなければ nil。
    /// - appName: 入力先アプリ名を Gemini に伝える設定がオフなら nil（名前を出さない）
    /// - translation: 翻訳の言語（整形なら nil）。和訳は出力が日本語なので、整形と同じ日本語の文体ルールを使う
    /// - hasCommonRules: 共通の追加ルールがプロンプトに入っているか（入っていれば優先順位を書く）
    /// - japaneseOutput: 整形の出力を日本語に統一するか（REQ-DIC-082。和訳と同じく日本語の文体のルールにする）
    /// - customStyles: カスタム文体の一覧（customStyleID を引く。ふつうは保存したもの）
    func promptSection(appName: String?, translation: TranslationLanguage?, hasCommonRules: Bool, japaneseOutput: Bool = false,
                       customStyles: [CustomStyle]? = nil) -> String? {
        guard hasRules else { return nil }
        // 日本語以外に訳すときは、訳す先の言語向けのルールにする。出力が日本語（和訳・日本語に統一）なら、
        // プロンプトの言語によらず日本語の文体のルール（ja.json）にする
        let japanese = translation?.outputsJapanese ?? japaneseOutput
        let target = japanese ? nil : translation
        // 設計判断: DEC-DIC-214（カスタム文体は、出力の言語が学んだ言語と同じときだけ、プリセットのルールの代わりに渡す。名前は送らない）
        let outputLanguage = translation?.language ?? (japaneseOutput ? .ja : PromptLanguage.current)
        let customStyle = customStyleID.flatMap { id in (customStyles ?? CustomStyleStore.saved()).first { $0.id == id } }
        let styleRules: [String]
        if customStyleID != nil {
            if let customStyle, customStyle.promptLanguage == outputLanguage, !customStyle.rules.isEmpty {
                styleRules = customStyle.rules.map { "- \($0)" } + [Prompts.text("style.learnedGuard")]
            } else {
                styleRules = []
            }
        } else {
            let presetRules = target.map(preset.translationRules(for:)) ?? preset.refineRules(language: japanese ? .ja : .current)
            styleRules = presetRules.map { "- \($0)" }
        }
        let custom = rules.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !styleRules.isEmpty || !custom.isEmpty else { return nil }

        var lines: [String] = []
        if let appName, !appName.isEmpty {
            lines.append(Prompts.text("style.headerWithApp", ["app": appName]))
        } else {
            lines.append(Prompts.text("style.header"))
        }
        lines += styleRules
        if !custom.isEmpty {
            lines.append(Prompts.text(styleRules.isEmpty ? "style.custom" : "style.customOverridesPreset"))
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

// 要件: REQ-DIC-022, REQ-DIC-023
// 設計判断: DEC-DIC-213
/// 文章から学んだ文体（カスタム文体）。名前・言語・ルールだけを持ち、学んだ文章は持たない
struct CustomStyle: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var name: String
    /// 学んだ文章の言語（17 言語のコード。PromptLanguage.rawValue）
    var language: String
    /// 文体のルール（1 つ 1 要素）
    var rules: [String]

    init(id: UUID = UUID(), name: String, language: String, rules: [String]) {
        self.id = id
        self.name = name
        self.language = language
        self.rules = rules
    }

    var promptLanguage: PromptLanguage? { PromptLanguage(rawValue: language) }

    /// 言語の表示名（この画面の言語で）
    var languageLabel: String {
        promptLanguage.map { TranslationLanguage($0).label } ?? language
    }

    // 設計判断: DEC-DIC-213
    /// 保存できる上限
    static let maxRuleLines = 20
    static let maxRuleCharacters = 2_000

    /// 編集欄の文字列（1 行に 1 ルール）から、ルールの一覧にする（前後の空白を取り、空行を除く）
    static func rules(fromText text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    enum ValidationError: Error, Equatable {
        case emptyName
        case duplicateName
        case emptyRules
        case tooManyRules
        case rulesTooLong
        case unknownLanguage

        var message: String {
            switch self {
            case .emptyName: tr("名前を入れてください。")
            case .duplicateName: tr("同じ名前の文体があります。別の名前にしてください。")
            case .emptyRules: tr("ルールを 1 つ以上入れてください。")
            case .tooManyRules: tr("ルールは %@ 行までです。", String(CustomStyle.maxRuleLines))
            case .rulesTooLong: tr("ルールは全体で %@ 字までです。", String(CustomStyle.maxRuleCharacters))
            case .unknownLanguage: tr("言語を選んでください。")
            }
        }
    }

    // 要件: REQ-DIC-022
    // 設計判断: DEC-DIC-213
    /// 保存できるかを調べる。名前は前後の空白を取り、大文字小文字を区別せず、ほかのカスタム文体と組み込みのプリセットの表示名との重複を拒む
    static func validate(name: String, language: String, rules: [String], others: [CustomStyle]) -> ValidationError? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .emptyName }
        let key = trimmed.lowercased()
        let taken = others.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            + AppStylePreset.allCases.map { $0.label.lowercased() }
        if taken.contains(key) { return .duplicateName }
        guard PromptLanguage(rawValue: language) != nil else { return .unknownLanguage }
        guard !rules.isEmpty else { return .emptyRules }
        if rules.count > maxRuleLines { return .tooManyRules }
        if rules.reduce(0, { $0 + $1.unicodeScalars.count }) > maxRuleCharacters { return .rulesTooLong }
        return nil
    }
}

// 要件: REQ-DIC-022
// 設計判断: DEC-DIC-213
/// カスタム文体の一覧。UserDefaults の customAppStyles に JSON で保存する（アプリへの割り当ては AppStyleStore）
final class CustomStyleStore: ObservableObject {
    static let shared = CustomStyleStore()
    static let key = "customAppStyles"

    private let defaults: UserDefaults

    @Published var styles: [CustomStyle] { didSet { save() } }

    init(defaults: UserDefaults = SettingsDefaults.store) {
        self.defaults = defaults
        styles = Self.saved(in: defaults)
    }

    /// 保存してある一覧（音声入力の整形・hanasu refine で、ストアを作らずに読む）。読めなければ空
    static func saved(in defaults: UserDefaults = SettingsDefaults.store) -> [CustomStyle] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([CustomStyle].self, from: data)) ?? []
    }

    /// 名前の順（大文字小文字を区別しない）
    var sorted: [CustomStyle] {
        styles.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func style(id: UUID?) -> CustomStyle? {
        id.flatMap { id in styles.first { $0.id == id } }
    }

    /// 足すか、同じ ID なら置き換える
    func upsert(_ style: CustomStyle) {
        if let index = styles.firstIndex(where: { $0.id == style.id }) {
            styles[index] = style
        } else {
            styles.append(style)
        }
    }

    // 要件: REQ-DIC-022
    // 設計判断: DEC-DIC-213
    /// 消す。使っていたアプリの割り当ても外す（そのアプリは「なし」。追加ルールは残す）
    func delete(id: UUID, appStyles: AppStyleStore) {
        styles.removeAll { $0.id == id }
        appStyles.removeCustomStyle(id: id)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(styles) {
            defaults.set(data, forKey: Self.key)
        }
    }
}

// 要件: REQ-DIC-020
// 設計判断: DEC-DIC-040, DEC-DIC-047
/// アプリ別スタイルの一覧。UserDefaults に JSON で保存する（AppSettings とは別に持つ）。
final class AppStyleStore: ObservableObject {
    static let shared = AppStyleStore()

    // 設計判断: DEC-DIC-190
    /// 初期状態のプリセットの割り当て。固有名のアプリは Windows 版と共有のファイル（HanasuShared）から読み、
    /// 名前を訳す Mac だけのアプリ（メッセージ・メール）は、ここで訳して足す
    static var defaultStyles: [AppStyle] {
        var styles = HanasuShared.defaultAppStyles
        let messages = AppStyle(bundleID: "com.apple.MobileSMS", name: tr("メッセージ"), preset: .chat)
        let mail = AppStyle(bundleID: "com.apple.mail", name: tr("メール"), preset: .email)
        styles.insert(messages, at: (styles.firstIndex { $0.bundleID == "jp.naver.line.mac" }).map { $0 + 1 } ?? styles.count)
        styles.insert(mail, at: styles.firstIndex { $0.bundleID == "com.microsoft.Outlook" } ?? styles.count)
        return styles
    }

    private let defaults = SettingsDefaults.store

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

    // 設計判断: DEC-DIC-213
    /// 初期の割り当てに戻す。カスタム文体（CustomStyleStore）は消さない
    func resetToDefaults() {
        styles = Self.defaultStyles
    }

    /// そのカスタム文体を使っているアプリの数
    func count(usingCustomStyle id: UUID) -> Int {
        styles.filter { $0.customStyleID == id }.count
    }

    // 設計判断: DEC-DIC-213
    /// カスタム文体を消したとき、使っていたアプリの割り当てを外す
    func removeCustomStyle(id: UUID) {
        styles = Self.removingCustomStyle(id: id, from: styles)
    }

    static func removingCustomStyle(id: UUID, from styles: [AppStyle]) -> [AppStyle] {
        styles.map { style in
            var style = style
            if style.customStyleID == id { style.selectPreset(.none) }
            return style
        }
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
