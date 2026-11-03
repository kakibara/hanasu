import AppKit
import Combine

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
        case .none: "なし"
        case .chat: "チャット"
        case .email: "メール"
        case .documentPolite: "文書（です・ます）"
        case .documentPlain: "文書（である）"
        }
    }

    /// 設定画面に出す短い説明
    var summary: String {
        switch self {
        case .none: "プリセットを使わない（このアプリ用の追加ルールだけを使う）"
        case .chat: "くだけた短い文。段落は作らない"
        case .email: "丁寧な文体（です・ます調）。まとまりごとに段落を分ける"
        case .documentPolite: "書き言葉の です・ます調 に統一し、段落を分ける"
        case .documentPlain: "書き言葉の である調 に統一し、段落を分ける"
        }
    }

    /// 日本語に整えるときのルール
    var refineRules: [String] {
        switch self {
        case .none:
            []
        case .chat:
            [
                "チャットのメッセージとして、くだけた短い文にする。硬い書き言葉（〜いたします、〜でございます、〜である 等）は使わない",
                "敬語（です・ます）で話している場合は、丁寧語は残したまま、堅苦しくない言い方にする",
                "つなぎの言葉や前置き（〜なんですけど、ちょっと、あの 等）は、意味が変わらなければ削って短くする。用件や情報は省かない",
                "例: 「来週のリリースなんですけど、ちょっと確認したいことがあって」→「来週のリリース、確認したいことがあって」",
                "段落は作らず、話題が変わるところだけ改行する",
            ]
        case .email:
            [
                "メールの本文として、丁寧な書き言葉（です・ます調、相手への依頼は敬語）にする",
                "くだけた言い方・話し言葉は、意味を変えずにビジネスメールにふさわしい言い方に直す（例: 〜なんですけど → 〜ですが、ちょっと → 少し、〜してもらってもいいですか → 〜していただけますでしょうか）",
                "宛名・挨拶・本題・お願い・結びなど、内容のまとまりごとに空行を入れて段落を分ける",
                "話していない宛名・挨拶・署名は足さない",
            ]
        case .documentPolite:
            [
                "文書として、書き言葉の です・ます調 に統一する。話し言葉の言い回しも書き言葉にする（例: 〜なんですけど → 〜ですが、ちょっと → 少し、〜って → 〜という）",
                "内容のまとまりごとに空行を入れて段落を分ける",
            ]
        case .documentPlain:
            [
                "文書として、書き言葉の である調（だ・である）に統一する。話し言葉の言い回しも書き言葉にする（例: 〜なんですけど → 〜だが、ちょっと → 少し、〜って → 〜という）",
                "内容のまとまりごとに空行を入れて段落を分ける",
            ]
        }
    }

    /// 英訳するときのルール。日本語の語尾の違い（です・ます／である）は英語では区別しない
    var translationRules: [String] {
        switch self {
        case .none:
            []
        case .chat:
            [
                "チャット向けの、カジュアルで短い英語にする（丁寧に話していても、堅すぎない丁寧さにとどめる）",
                "前置きや同じことの繰り返しは削って簡潔にする。ただし用件や情報は省かない",
                "段落は作らず、話題が変わるところだけ改行する",
            ]
        case .email:
            [
                "丁寧でプロフェッショナルな英語のメール文にする",
                "内容のまとまりごとに空行を入れて段落を分ける",
                "話していない宛名・挨拶・署名は足さない",
            ]
        case .documentPolite, .documentPlain:
            [
                "文書向けの、書き言葉の自然な英語にする",
                "内容のまとまりごとに空行を入れて段落を分ける",
            ]
        }
    }
}

/// アプリごとの既定の出力言語
enum AppOutputLanguage: String, Codable, CaseIterable, Identifiable {
    case japanese
    case english

    var id: String { rawValue }
    var label: String {
        switch self {
        case .japanese: "日本語"
        case .english: "English"
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
    var outputLanguage: AppOutputLanguage = .japanese

    var id: String { bundleID }

    /// プロンプトに足すものがあるか（出力言語だけを決めたアプリでは false）
    var hasRules: Bool {
        preset != .none || !rules.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// `GeminiClient.userPrompt` に足す節。足すものがなければ nil。
    /// - appName: 入力先アプリ名を Gemini に伝える設定がオフなら nil（名前を出さない）
    /// - hasCommonRules: 共通の追加ルールがプロンプトに入っているか（入っていれば優先順位を書く）
    func promptSection(appName: String?, translating: Bool, hasCommonRules: Bool) -> String? {
        guard hasRules else { return nil }
        let presetRules = translating ? preset.translationRules : preset.refineRules
        let custom = rules.trimmingCharacters(in: .whitespacesAndNewlines)

        var lines: [String] = []
        if let appName, !appName.isEmpty {
            lines.append("入力先アプリ向けの文体ルール（\(appName)）:")
        } else {
            lines.append("入力先アプリ向けの文体ルール:")
        }
        lines += presetRules.map { "- \($0)" }
        if !custom.isEmpty {
            lines.append(presetRules.isEmpty ? "- このアプリ用の追加ルール:" : "- このアプリ用の追加ルール（上の項目と食い違うときはこちらを優先）:")
            lines += custom.split(whereSeparator: \.isNewline).map { "  \($0)" }
            if translating {
                lines.append("  （日本語の語尾や敬語についてのルールは、英語の丁寧さの度合いとして読み替える）")
            }
        }
        // system instruction の「口調を保つ」と食い違うので、どちらを優先するかを書いておく
        let overridden = translating ? "「口調と丁寧さを保つ」" : "「口調を変えない」「言葉は変えない」"
        lines.append("- この文体ルールは、\(overridden)より優先する。語尾・言い回し・改行は変えてよいが、話した内容（事実・用件・意図）は変えない")
        if hasCommonRules {
            lines.append("- 上の「追加ルール」とこの文体ルールが食い違うときは、この文体ルールを優先する")
        }
        return lines.joined(separator: "\n")
    }
}

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
        AppStyle(bundleID: "com.apple.MobileSMS", name: "メッセージ", preset: .chat),
        // メール
        AppStyle(bundleID: "com.apple.mail", name: "メール", preset: .email),
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
