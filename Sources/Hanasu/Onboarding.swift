import AppKit
import AVFoundation
import SwiftUI

// MARK: - 状態

// 要件: REQ-COM-051
// 設計判断: DEC-COM-090
/// オンボーディングを終えたかどうか（UserDefaults の onboardingCompletedVersion）
enum OnboardingState {
    /// 内容を大きく変えて、もう一度見せたいときに上げる
    static let currentVersion = 1
    private static let key = "onboardingCompletedVersion"

    static var isCompleted: Bool {
        UserDefaults.standard.integer(forKey: key) >= currentVersion
    }

    static func markCompleted() {
        UserDefaults.standard.set(currentVersion, forKey: key)
    }

    /// 起動時に出すか。以前から使っている人（Hanasu の設定が保存されている）には出さず、終わったことにする。
    /// AppKit が書くキー（ウインドウやメニューバーのアイコンの位置など）より前に呼ぶ
    static func shouldShowOnLaunch() -> Bool {
        if isCompleted { return false }
        if hasSavedSettings {
            markCompleted()
            return false
        }
        return true
    }

    /// Hanasu の設定が 1 つでも保存されているか。システムが書くキー（NS…・Apple…）と、
    /// AppSettings が最初に書く AI の既定の印（DEC-COM-068）は数えない
    private static var hasSavedSettings: Bool {
        let values = UserDefaults.standard.persistentDomain(forName: AppSettings.defaultsDomainName) ?? [:]
        return AppSettings.hasSavedSettings(values, ignoring: [Self.key])
    }
}

// MARK: - ページとモデル

// 要件: REQ-COM-051
// 設計判断: DEC-COM-092
enum OnboardingPage: Int, CaseIterable, Identifiable {
    case welcome
    case ai
    case dictation
    case meeting
    case words
    case tips
    case permissions

    var id: Int { rawValue }

    /// 確認用の CLI のファイル名・--page の値
    var cliName: String {
        switch self {
        case .welcome: "welcome"
        case .ai: "ai"
        case .dictation: "dictation"
        case .meeting: "meeting"
        case .words: "words"
        case .tips: "tips"
        case .permissions: "permissions"
        }
    }
}

@MainActor
final class OnboardingModel: ObservableObject {
    @Published var page: OnboardingPage = .welcome
    /// AI のページで選んだ AI。そのページで押すまでは nil（今の設定の値には印を付けない）
    @Published var chosenAI: TextAIProvider?
    var onFinish: () -> Void = {}

    let settings: AppSettings

    init(settings: AppSettings = .shared) {
        self.settings = settings
    }

    // 要件: REQ-COM-050
    // 設計判断: DEC-COM-092
    /// 既定の AI を選ぶ。音声入力と会議の両方をその AI にし、その場で保存する。
    /// ローカル（Gemma）なら、両方のモデルを Gemma 4 E4B にする（ダウンロードは 1 つで済む）。
    /// Gemini・Claude のモデルは各 AI の既定のまま。ダウンロードはここでは始めない（DEC-COM-094）
    func chooseDefaultAI(_ provider: TextAIProvider) {
        chosenAI = provider
        settings.dictationAIProvider = provider
        settings.meetingAIProvider = provider
        if provider == .local {
            settings.localDictationModel = OnboardingAIChoice.gemmaModel
            settings.localMeetingModel = OnboardingAIChoice.gemmaModel
        }
    }

    /// AI のページでは、選ぶまで先に進めない
    var canGoNext: Bool { page != .ai || chosenAI != nil }
    var isLastPage: Bool { page == OnboardingPage.allCases.last }

    // 要件: REQ-COM-050
    // 設計判断: DEC-COM-094
    /// AI のページで Gemma を選び、まだダウンロードしていない（途中でもない）とき。「次へ」が「ダウンロードして次へ」になる
    var startsGemmaDownloadOnNext: Bool {
        guard page == .ai, chosenAI == .local else { return false }
        switch LocalLLMStore.shared.status(OnboardingAIChoice.gemmaModel) {
        case .notDownloaded, .failed: return true
        case .downloading, .downloaded: return false
        }
    }

    func next() {
        guard canGoNext else { return }
        // 設計判断: DEC-COM-094
        // ダウンロードを始めて、終わるのを待たずに次のページへ進む
        if startsGemmaDownloadOnNext { LocalLLMStore.shared.ensureDownloaded(OnboardingAIChoice.gemmaModel) }
        if let next = OnboardingPage(rawValue: page.rawValue + 1) { page = next } else { onFinish() }
    }

    func back() {
        if let previous = OnboardingPage(rawValue: page.rawValue - 1) { page = previous }
    }

    /// 最初のページからやり直す（メニューから開き直したとき）
    func restart() {
        page = .welcome
        chosenAI = nil
    }
}

// MARK: - 画面

// 要件: REQ-COM-050, REQ-COM-051
// 設計判断: DEC-COM-092
struct OnboardingView: View {
    static let size = NSSize(width: 640, height: 600)

    @ObservedObject var model: OnboardingModel
    /// 「ダウンロードして次へ」の出し分けのため、Gemma のダウンロードの状態を見る
    @ObservedObject private var store = LocalLLMStore.shared

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.page {
                case .welcome: OnboardingWelcomePage()
                case .ai: OnboardingAIPage(model: model, settings: model.settings)
                case .dictation: OnboardingDictationPage(settings: model.settings)
                case .meeting: OnboardingMeetingPage(settings: model.settings)
                case .words: OnboardingWordsPage()
                case .tips: OnboardingTipsPage(settings: model.settings)
                case .permissions: OnboardingPermissionsPage(settings: model.settings)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Divider()
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var footer: some View {
        HStack {
            Button(tr("戻る")) { model.back() }
                .opacity(model.page == .welcome ? 0 : 1)
                .disabled(model.page == .welcome)
            Spacer()
            HStack(spacing: 7) {
                ForEach(OnboardingPage.allCases) { page in
                    Circle()
                        .fill(page == model.page ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityLabel(tr("%@ ページ中 %@ ページ目", "\(OnboardingPage.allCases.count)", "\(model.page.rawValue + 1)"))
            Spacer()
            Button(model.isLastPage ? tr("はじめる") : model.startsGemmaDownloadOnNext ? tr("ダウンロードして次へ") : tr("次へ")) { model.next() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canGoNext)
        }
        .controlSize(.large)
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }
}

/// ページの見出し
private struct OnboardingHeader: View {
    var symbol: String
    var title: String
    var subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .resizable()
                .scaledToFit()
                .fontWeight(.medium)
                .foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 34)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title2.bold())
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 14)
    }
}

/// 機能の説明の 1 行（アイコン・名前・説明・ショートカット）
private struct OnboardingFeatureRow: View {
    var symbol: String
    var title: String
    var detail: String
    var shortcut: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title).font(.headline)
                    if let shortcut { OnboardingKeyCap(text: shortcut) }
                }
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

/// ショートカットのキーの表示
private struct OnboardingKeyCap: View {
    var text: String

    var body: some View {
        Text(text.trimmingCharacters(in: .whitespaces))
            .font(.callout.monospaced().weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.14)))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.secondary.opacity(0.3)))
    }
}

/// 説明の行を並べるページの本文
private struct OnboardingFeatureList<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { content }
                .padding(.horizontal, 32)
                .padding(.bottom, 20)
        }
    }
}

// MARK: ようこそ

private struct OnboardingWelcomePage: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.6)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 96, height: 96)
                Image(systemName: "waveform")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(spacing: 6) {
                Text(tr("Hanasu へようこそ")).font(.largeTitle.bold())
                Text(tr("話すだけで、整った文章をカーソルの場所に入力します。\n会議を記録して、文字起こしと議事録も作ります。"))
                    .font(.title3).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 12) {
                OnboardingFeatureRow(symbol: "sparkles", title: tr("まず、使う AI を選びます"),
                                     detail: tr("話した内容を整える・翻訳する・議事録をまとめるのに使います。"))
                OnboardingFeatureRow(symbol: "book", title: tr("次に、主な機能と設定の Tips を紹介します"),
                                     detail: tr("1 分ほどで終わります。あとからメニューの「Hanasu の使い方…」でいつでも開けます。"))
            }
            .padding(.horizontal, 90)
            .padding(.top, 8)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 20)
    }
}

// MARK: 使う AI を選ぶ

// 要件: REQ-COM-050
// 設計判断: DEC-COM-092
/// AI のページのカード。Gemma（ローカル）がおすすめ（既定）
enum OnboardingAIChoice: CaseIterable, Identifiable {
    case gemma
    case gemini
    case claude
    case appleFM

    /// おすすめのローカルのモデル
    static let gemmaModel = LocalLLMModel.gemma4E4B

    var id: Self { self }

    var provider: TextAIProvider {
        switch self {
        case .gemma: .local
        case .gemini: .gemini
        case .claude: .claude
        case .appleFM: .appleFM
        }
    }

    var title: String {
        switch self {
        case .gemma: Self.gemmaModel.name
        case .gemini: TextAIProvider.gemini.label
        case .claude: TextAIProvider.claude.label
        case .appleFM: TextAIProvider.appleFM.label
        }
    }

    var isRecommended: Bool { self == .gemma }

    var tagline: String {
        switch self {
        case .gemma: tr("この Mac の中で動く Google の Gemma。無料で、議事録もまとめやすい")
        case .gemini: tr("速くて安い。モデルは自由に指定できます")
        case .claude: tr("文章の仕上がりがていねい。Haiku・Sonnet・Opus から選べます")
        case .appleFM: tr("macOS 27 の Apple Intelligence のモデル。無料")
        }
    }

    var sendsText: Bool { self == .gemini || self == .claude }

    var privacy: String {
        switch self {
        case .gemini: tr("文章を Google に送ります")
        case .claude: tr("文章を Anthropic に送ります（音声は送りません）")
        case .gemma, .appleFM: tr("文章をネットに送りません")
        }
    }

    var requirement: String {
        switch self {
        case .gemma: tr("要るもの: ダウンロード（%@。このあとすぐ）", "\(Self.gemmaModel.sizeLabel)")
        case .gemini: tr("要るもの: API キーかサービスアカウント")
        case .claude: tr("要るもの: API キー（Claude Console）")
        case .appleFM: tr("要るもの: macOS 27 と Apple Intelligence")
        }
    }
}

// 要件: REQ-COM-050
// 設計判断: DEC-COM-092
struct OnboardingAIPage: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var settings: AppSettings
    private let appleFM = AppleFMAvailability.check()

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeader(
                symbol: "sparkles", title: tr("使う AI を選ぶ"),
                subtitle: tr("話した内容を整える・翻訳する・議事録をまとめるのに使う AI です。おすすめは、この Mac の中で動く Gemma です。あとから設定の「AI」タブで変えられます。"))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(OnboardingAIChoice.allCases) { choice in
                    card(choice)
                }
            }
            .padding(.horizontal, 28)
            if let chosen = model.chosenAI {
                preparation(for: chosen)
            } else {
                Text(tr("どれか 1 つを選ぶと、次へ進めます。"))
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(.top, 18)
                Spacer(minLength: 0)
            }
        }
    }

    private func card(_ choice: OnboardingAIChoice) -> some View {
        let selected = model.chosenAI == choice.provider
        let unavailable = choice == .appleFM ? appleFM.reason : nil
        return Button {
            model.chooseDefaultAI(choice.provider)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(choice.title).font(.headline)
                    if choice.isRecommended {
                        Text(tr("おすすめ"))
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor))
                    }
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                }
                Text(choice.tagline).font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Label(choice.privacy, systemImage: choice.sendsText ? "network" : "lock.laptopcomputer")
                    .font(.caption).foregroundStyle(.secondary)
                Label(unavailable == nil ? choice.requirement : tr("この Mac では使えません（macOS 27 から）"),
                      systemImage: unavailable == nil ? (choice == .gemma ? "arrow.down.circle" : "key") : "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(unavailable == nil ? Color.secondary : Color.orange)
                    .lineLimit(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .help(unavailable ?? "")
        // 設計判断: DEC-COM-092
        // Apple の Foundation Models が使えない Mac（macOS 27 より前など）では選べない
        .disabled(unavailable != nil)
        .opacity(unavailable == nil ? 1 : 0.55)
    }

    /// 選んだ AI の準備の欄（Gemini・Claude・Apple は設定の「AI」タブと同じ部品）
    @ViewBuilder private func preparation(for provider: TextAIProvider) -> some View {
        Form {
            switch provider {
            case .gemini:
                GeminiAuthSection(settings: settings)
            case .claude:
                ClaudeKeySection(settings: settings)
            case .local:
                OnboardingGemmaDownload()
            case .appleFM:
                Section(tr("Apple の Foundation Models")) { AppleFMChoice() }
            }
            Text(provider == .local
                 ? tr("音声入力だけ小さく速いモデル（LFM2.5）にするなどは、このあとの「設定の Tips」か、設定 →「AI」で選べます。")
                 : tr("準備はあとからでもできます（設定 →「AI」）。"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

// 要件: REQ-COM-050
// 設計判断: DEC-COM-094
/// Gemma のダウンロードの欄。ボタンで始め、進み具合と中止を出す（設定の「AI」タブと同じ LocalLLMStore を使う）
struct OnboardingGemmaDownload: View {
    @ObservedObject var store = LocalLLMStore.shared
    private let model = OnboardingAIChoice.gemmaModel
    /// 「メモリ 16 GB 以上向け」（LocalLLMModel.summary）より少ないか
    private let hasLittleMemory = ProcessInfo.processInfo.physicalMemory < 16 * 1024 * 1024 * 1024

    var body: some View {
        Section {
            switch store.status(model) {
            case .notDownloaded:
                HStack {
                    Text(tr("まだダウンロードしていません。「ダウンロードして次へ」でも始められます。"))
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button(tr("ダウンロード（%@）", "\(model.sizeLabel)")) { store.ensureDownloaded(model) }
                }
            case .downloading(let fraction):
                HStack {
                    if let fraction {
                        ProgressView(value: fraction)
                        Text("\(Int(fraction * 100))%").font(.callout).monospacedDigit()
                    } else {
                        ProgressView().controlSize(.small)
                        Text(tr("確かめています…")).font(.callout)
                    }
                    Button(tr("中止")) { store.cancelDownload(model) }
                }
                Text(tr("ダウンロードは、次のページへ進んでも、このウインドウを閉じても続きます。"))
                    .font(.caption).foregroundStyle(.secondary)
            case .downloaded:
                Label(tr("ダウンロード済み。すぐに使えます"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed(let message):
                HStack {
                    Text("⚠️ \(message)").font(.callout).foregroundStyle(.red)
                    Spacer()
                    Button(tr("もう一度")) { store.ensureDownloaded(model) }
                }
            }
            if hasLittleMemory {
                Label(tr("この Mac のメモリは 16 GB より少ないので、Gemma は遅いかもしれません。そのときは設定 →「AI」で小さいモデルか、ほかの AI に変えてください。"),
                      systemImage: "memorychip")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack(spacing: 4) {
                Text("\(model.summary)。\(model.licenseNote)")
                Link(tr("ライセンス"), destination: model.licenseURL)
            }
            .font(.caption).foregroundStyle(.secondary)
        } header: {
            Text(tr("%@ をダウンロードする（音声入力と会議の両方で使います）", "\(model.name)"))
        }
    }
}

// MARK: 音声入力

private struct OnboardingDictationPage: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var editSettings = EditModeSettings.shared
    @ObservedObject var historySettings = HistorySettings.shared

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeader(symbol: "mic", title: tr("音声入力"),
                             subtitle: tr("どのアプリでも、カーソルのある場所に、話した内容を整えて入力します。"))
            OnboardingFeatureList {
                OnboardingFeatureRow(
                    symbol: "mic.fill", title: tr("話して入力"), detail: tr("入力したい場所で押して話し、もう一度押す（画面下の表示の「■ 停止」でも）と、AI が整えた文章を入力します。Esc で取り消し。押している間だけ録音する使い方も選べます。"),
                    shortcut: settings.hotKey.displayString)
                OnboardingFeatureRow(
                    symbol: "globe", title: tr("翻訳して入力"),
                    detail: tr("話した内容を%@して入力します。録音中に画面下の表示で言語を選んでも切り替えられます。", "\(TranslationLanguage.menuVerb(for: settings.translationLanguages))"),
                    shortcut: settings.translateHotKey.displayString)
                OnboardingFeatureRow(
                    symbol: "wand.and.stars", title: tr("選択を声で編集"),
                    detail: tr("文章を選んで押し、「もっと丁寧に」「箇条書きにして」「英語にして」のように話してもう一度押すと、書き換えた文章で置き換えます。"),
                    shortcut: editSettings.hotKey.displayString)
                OnboardingFeatureRow(
                    symbol: "arrow.uturn.backward", title: tr("最後の結果をもう一度入力"),
                    detail: tr("入力先がずれて結果が消えたときは、入れたい場所で押します。メニューの「最近の結果」からコピーもできます。"),
                    shortcut: historySettings.repasteHotKey.displayString)
                OnboardingFeatureRow(
                    symbol: "menubar.arrow.up.rectangle", title: tr("メニューからも"),
                    detail: tr("メニューバーの Hanasu のアイコンから、どれも始められます。録音中はアイコンが赤くなります。"))
            }
        }
    }
}

// MARK: 会議の記録

private struct OnboardingMeetingPage: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var notesSettings = MeetingNotesSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeader(symbol: "person.2.wave.2", title: tr("会議の記録"),
                             subtitle: tr("Meet・Zoom・Teams・Slack ハドルなどの会議を録って、文字起こしと議事録を作ります。"))
            OnboardingFeatureList {
                OnboardingFeatureRow(
                    symbol: "record.circle", title: tr("記録の開始／停止"),
                    detail: tr("マイクを「自分」、Mac で鳴っている音を「相手」として録ります。イヤホンがおすすめです。記録は「書類」フォルダの Hanasu/Meetings に保存します。"),
                    shortcut: settings.meetingHotKey.displayString)
                OnboardingFeatureRow(
                    symbol: "bell.badge", title: tr("会議の自動検出"),
                    detail: tr("会議のアプリがマイクを使い始めると「記録しますか？」と提案します。勝手には録りません。"))
                OnboardingFeatureRow(
                    symbol: "star", title: tr("メモと「ここ重要」"),
                    detail: tr("記録中に会議ノートへメモを書いたり、重要なところに印を付けたりすると、議事録がそこを優先してまとめます。"),
                    shortcut: notesSettings.highlightHotKey.displayString)
                OnboardingFeatureRow(
                    symbol: "doc.text", title: tr("議事録の型と書き出し"),
                    detail: tr("定例・1on1・商談などの型を選べます。アクションアイテムは Markdown・Slack 向けのコピー・リマインダーに書き出せます。"))
                OnboardingFeatureRow(
                    symbol: "magnifyingglass", title: tr("過去の会議を検索・質問"),
                    detail: tr("会議ノートで過去の会議を横断して検索し（⌘F）、「先週の定例で何が決まった？」と質問すると、根拠の会議を引いて答えます。"))
            }
        }
    }
}

// MARK: 履歴・辞書・スニペット

private struct OnboardingWordsPage: View {
    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeader(symbol: "character.book.closed", title: tr("履歴・辞書・スニペット"),
                             subtitle: tr("使うほど、あなたの言葉に合わせて入力できるようになります。"))
            OnboardingFeatureList {
                OnboardingFeatureRow(
                    symbol: "clock.arrow.circlepath", title: tr("履歴"),
                    detail: tr("結果と元の文字起こしを残し、検索・コピーできます。整形に失敗した文は、原文から整え直せます（メニュー →「履歴を開く…」）。"))
                OnboardingFeatureRow(
                    symbol: "character.book.closed", title: tr("辞書と置き換えルール"),
                    detail: tr("人の名前や社内の用語を登録すると、認識と整形に効きます。「じぇみに → Gemini」のような置き換えルールも書け、会議の記録から候補を挙げてもらうこともできます（設定 →「辞書・ルール」）。"))
                OnboardingFeatureRow(
                    symbol: "text.badge.plus", title: tr("スニペット"),
                    detail: tr("「メールの署名」と話すだけで、登録した定型文をそのまま入力します（設定 →「スニペット」）。"))
                OnboardingFeatureRow(
                    symbol: "square.grid.2x2", title: tr("アプリ別の文体"),
                    detail: tr("Slack ならくだけた短い文、メールなら丁寧な文のように、入力先のアプリに合わせて文体を変えます。アプリごとに出力の言語も決められます（設定 →「アプリ別」）。"))
            }
        }
    }
}

// MARK: 設定の Tips

// 要件: REQ-COM-051
// 設計判断: DEC-COM-092
/// 設定の Tips。AI とモデルは、この画面の中で選べる（設定の「AI」タブと同じ部品）
struct OnboardingTipsPage: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeader(symbol: "lightbulb", title: tr("設定の Tips"),
                             subtitle: tr("よく変える設定です。AI とモデルは、ここで選べます。"))
            Form {
                Section {
                    AIChoiceRow(settings: settings, purpose: .dictation)
                    AIChoiceRow(settings: settings, purpose: .meeting)
                } header: {
                    Text(tr("AI とモデルを選べる（設定 →「AI」）"))
                } footer: {
                    Text(tr("音声入力は速いモデル、会議は賢いモデル、のように分けられます。選ぶとすぐに保存します。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(tr("ほかの Tips")) {
                    tip("mic", tr("マイクを選べる"),
                        tr("設定 →「一般」→「マイク」。録音中の画面下の表示のマイクのボタンでも切り替えられます。"))
                    tip("waveform", tr("文字起こしのエンジンを選べる"),
                        tr("Mac 標準（既定）・Whisper（Mac の中で動かす）・Gemini（音声を送る）から、音声入力と会議で別々に選べます（設定 →「一般」）。"))
                    tip("keyboard", tr("ショートカットを変えられる"),
                        tr("ほかのアプリと重なるときは、設定の「一般」「会議」「履歴」で別のキーにできます。"))
                    tip("globe", tr("翻訳する言語を足せる"),
                        tr("設定 →「一般」→「翻訳する言語」で日本語も選ぶと、英語で話して日本語で入力できます。"))
                    tip("text.viewfinder", tr("画面の文脈を参考にできる"),
                        tr("設定 →「AI」でオンにすると、画面にある名前の表記に合わせて整えます（既定はオフ）。"))
                    tip("menubar.rectangle", tr("アイコンを出す場所"),
                        tr("メニューバー・Dock・両方から選べます（設定 →「一般」→「アイコンの表示」）。"))
                }
            }
            .formStyle(.grouped)
        }
    }

    private func tip(_ symbol: String, _ title: String, _ detail: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(Color.accentColor)
        }
    }
}

// MARK: 許可と準備

// 要件: REQ-COM-051
// 設計判断: DEC-COM-093
/// 最後のページ。自動入力（アクセシビリティ）と録音（マイク・音声認識）の許可を、ここで求める
struct OnboardingPermissionsPage: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store = LocalLLMStore.shared
    @State private var refresh = 0

    private var usesGemma: Bool {
        TextAIPurpose.allCases.contains {
            settings.aiProvider(for: $0) == .local && settings.localModel(for: $0) == OnboardingAIChoice.gemmaModel
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeader(symbol: "checkmark.shield", title: tr("最後に、許可をお願いします"),
                             subtitle: tr("Hanasu が動くのに要る許可です。あとから設定の「権限」タブでもできます。"))
            Form {
                Section {
                    row(title: tr("アクセシビリティ"),
                        detail: tr("整えた文章を ⌘V で入力するのに要ります。システム設定で Hanasu をオンにしてください。"),
                        granted: Permissions.isAccessibilityTrusted(prompt: false),
                        actionTitle: tr("許可する…")) {
                        if !Permissions.isAccessibilityTrusted(prompt: true) {
                            Permissions.openPrivacySettings("Privacy_Accessibility")
                        }
                    }
                    row(title: tr("マイク"),
                        detail: tr("話した声を録るのに要ります。"),
                        granted: Permissions.microphoneStatus == .authorized,
                        actionTitle: Permissions.microphoneStatus == .notDetermined ? tr("許可する") : tr("開く…")) {
                        if Permissions.microphoneStatus == .notDetermined {
                            Task {
                                _ = await AVCaptureDevice.requestAccess(for: .audio)
                                refresh += 1
                            }
                        } else {
                            Permissions.openPrivacySettings("Privacy_Microphone")
                        }
                    }
                    row(title: tr("音声認識"),
                        detail: tr("文字起こしのエンジンが Mac 標準のときに要ります。"),
                        granted: Permissions.speechStatus == .authorized,
                        actionTitle: Permissions.speechStatus == .notDetermined ? tr("許可する") : tr("開く…")) {
                        if Permissions.speechStatus == .notDetermined {
                            Task {
                                try? await Permissions.ensureRecordingPermissions(speechRecognition: true)
                                refresh += 1
                            }
                        } else {
                            Permissions.openPrivacySettings("Privacy_SpeechRecognition")
                        }
                    }
                }
                Section(tr("準備ができたら")) {
                    LabeledContent(tr("使う AI")) {
                        Text(aiSummary).foregroundStyle(.secondary)
                    }
                    // 要件: REQ-COM-050
                    // 設計判断: DEC-COM-094
                    if usesGemma, store.status(OnboardingAIChoice.gemmaModel) != .downloaded {
                        OnboardingGemmaDownloadStatus(store: store)
                    }
                    Label(tr("「はじめる」を押したら、入力したい場所で %@ を押して話してみてください。", "\(settings.hotKey.displayString)"),
                          systemImage: "mic.fill")
                    Label(tr("この説明は、メニューの「Hanasu の使い方…」でいつでも開けます。"), systemImage: "book")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .id(refresh)
        }
        // システム設定で許可して戻ってきたら、表示を新しくする
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh += 1
        }
    }

    private var aiSummary: String {
        func label(_ purpose: TextAIPurpose) -> String {
            let provider = settings.aiProvider(for: purpose)
            let model = provider == .local ? settings.localModel(for: purpose).name : settings.textModel(for: purpose)
            return tr("%@（%@）", provider.name, model)
        }
        return tr("音声入力 %@・会議 %@", "\(label(.dictation))", "\(label(.meeting))")
    }

    private func row(title: String, detail: String, granted: Bool, actionTitle: String,
                     action: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                .font(.title3)
                .foregroundStyle(granted ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if granted {
                Text(tr("許可済み")).foregroundStyle(.secondary)
            } else {
                Button(actionTitle, action: action)
            }
        }
    }
}

/// 最後のページの、Gemma のダウンロードの進み具合（終わっていないときだけ出す）
private struct OnboardingGemmaDownloadStatus: View {
    @ObservedObject var store: LocalLLMStore
    private let model = OnboardingAIChoice.gemmaModel

    var body: some View {
        LabeledContent(tr("%@ のダウンロード", "\(model.name)")) {
            switch store.status(model) {
            case .downloading(let fraction):
                HStack {
                    if let fraction {
                        ProgressView(value: fraction).frame(width: 140)
                        Text("\(Int(fraction * 100))%").monospacedDigit()
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
            case .failed:
                Button(tr("もう一度")) { store.ensureDownloaded(model) }
            case .notDownloaded:
                Button(tr("ダウンロード（%@）", "\(model.sizeLabel)")) { store.ensureDownloaded(model) }
            case .downloaded:
                Text(tr("済み"))
            }
        }
    }
}

// MARK: - ウインドウ

// 要件: REQ-COM-051
// 設計判断: DEC-COM-090, DEC-COM-091
/// オンボーディングのウインドウ。閉じたら（「はじめる」でも）終わったことにする
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let model = OnboardingModel()

    var isVisible: Bool { window?.isVisible ?? false }

    /// 開く。閉じていたら最初のページから始める
    func show() {
        if window == nil {
            let window = Self.makeWindow(model: model)
            window.delegate = self
            window.center()
            self.window = window
            model.onFinish = { [weak self] in self?.window?.close() }
        }
        if !isVisible { model.restart() }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        OnboardingState.markCompleted()
    }

    /// 確認用の CLI でも同じものを作る
    static func makeWindow(model: OnboardingModel) -> NSWindow {
        let hosting = NSHostingController(rootView: OnboardingView(model: model))
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        window.title = tr("Hanasu の使い方")
        window.styleMask = [.titled, .closable]
        window.setContentSize(OnboardingView.size)
        window.isReleasedWhenClosed = false
        return window
    }
}

// MARK: - 確認用の CLI

// 確かめ方: REQ-COM-050, REQ-COM-051
//   Hanasu --render-onboarding <出力フォルダ> [--page welcome|ai|dictation|meeting|words|tips|permissions]
//          [--ai gemini|claude|local|apple] [--downloading] [--dark]
//     オンボーディングの各ページを <出力フォルダ>/<番号>-<ページ>.png に書き出す（--page でそのページだけ）。
//     --ai を付けると、その AI を選んだあとの見た目（AI のページの準備の欄など）になる。設定は終わったら元に戻す。
//     --downloading で、Gemma（--ai local）のダウンロード中の見た目にする（ダウンロードはしない）
@MainActor
enum OnboardingCLI {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--render-onboarding"), args.indices.contains(index + 1) else { return }
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: args[index + 1])
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pages: [OnboardingPage] = value(after: "--page", in: args)
            .map { name in OnboardingPage.allCases.filter { $0.cliName == name } } ?? OnboardingPage.allCases
        if pages.isEmpty {
            FileHandle.standardError.write(Data("error: --page は \(OnboardingPage.allCases.map(\.cliName).joined(separator: "|"))\n".utf8))
            exit(1)
        }
        let chosen = value(after: "--ai", in: args).flatMap(TextAIProvider.init(rawValue:))
        let settings = AppSettings.shared
        let saved = (settings.dictationAIProvider, settings.meetingAIProvider)
        let savedLocal = (settings.localDictationModel, settings.localMeetingModel)
        if args.contains("--downloading") {
            LocalLLMStore.shared.showDownloadingForRendering(OnboardingAIChoice.gemmaModel, fraction: 0.42)
        }
        for page in pages {
            let model = OnboardingModel()
            model.page = page
            // 選んだあとの見た目にする（準備の欄は設定の AI を読むので、設定にも当てる。終わったら戻す）
            if let chosen { model.chooseDefaultAI(chosen) }
            let url = directory.appendingPathComponent(String(format: "%02d-%@.png", page.rawValue + 1, page.cliName))
            render(OnboardingView(model: model), to: url, dark: args.contains("--dark"))
            print("wrote \(url.path)")
        }
        settings.dictationAIProvider = saved.0
        settings.meetingAIProvider = saved.1
        settings.localDictationModel = savedLocal.0
        settings.localMeetingModel = savedLocal.1
        exit(0)
    }

    private static func render(_ view: OnboardingView, to url: URL, dark: Bool) {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: OnboardingView.size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        // Form の中のスクロールを先頭に戻してから描く（そのままだと途中から描かれる）
        func scrollToTop(_ view: NSView) {
            if let scroll = view as? NSScrollView, let document = scroll.documentView {
                document.scroll(NSPoint(x: 0, y: document.isFlipped ? 0 : document.bounds.height))
            }
            view.subviews.forEach(scrollToTop)
        }
        scrollToTop(hosting)
        hosting.layoutSubtreeIfNeeded()
        if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
    }

    private static func value(after flag: String, in args: [String]) -> String? {
        args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
    }
}
