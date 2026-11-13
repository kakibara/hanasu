import AppKit
import SwiftUI
import UniformTypeIdentifiers

// 要件: REQ-DIC-022
// 設計判断: DEC-DIC-215
/// 設定の「アプリ別」の「カスタム文体」の節。一覧と「文章から学ぶ…」「編集…」「削除…」
struct CustomStylesSection: View {
    @ObservedObject var customStore: CustomStyleStore
    @ObservedObject var appStore = AppStyleStore.shared
    @State private var sheet: StyleLearningSheet.Mode?
    @State private var deleting: CustomStyle?

    var body: some View {
        Section {
            if customStore.styles.isEmpty {
                Text(tr("まだありません。「文章から学ぶ…」で、自分の文章から文体を作れます。"))
                    .foregroundStyle(.secondary)
            }
            ForEach(customStore.sorted) { style in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(style.name).lineLimit(1)
                        Text(tr("%@・ルール %@ 個", style.languageLabel, String(style.rules.count)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(tr("編集…")) { sheet = .edit(style) }
                        .controlSize(.small)
                    Button(tr("削除…")) { deleting = style }
                        .controlSize(.small)
                }
            }
        } header: {
            HStack {
                Text(tr("カスタム文体"))
                Spacer()
                Button(tr("文章から学ぶ…")) { sheet = .learn }
                    .controlSize(.small)
            }
        } footer: {
            Text(tr("自分の文章から学んだ文体です。上の「アプリ」でプリセットとして選べます。出力の言語が学んだ文章の言語と同じときだけ使います。"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .sheet(item: $sheet) { mode in
            StyleLearningSheet(mode: mode, store: customStore)
        }
        .confirmationDialog(tr("「%@」を削除しますか？", deleting?.name ?? ""), isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button(tr("削除"), role: .destructive) {
                if let deleting { customStore.delete(id: deleting.id, appStyles: appStore) }
                deleting = nil
            }
        } message: {
            let count = deleting.map { appStore.count(usingCustomStyle: $0.id) } ?? 0
            Text(count > 0
                ? tr("この文体を使っている %@ 個のアプリは「なし」に戻ります。元に戻せません。", String(count))
                : tr("元に戻せません。"))
        }
    }
}

// 要件: REQ-DIC-022
// 設計判断: DEC-DIC-210, DEC-DIC-211, DEC-DIC-212, DEC-DIC-215
/// 文章から文体を学ぶシート（「編集…」では名前・言語・ルールの欄だけを出す）。
/// 入れた文章は保存しない（シートを閉じると消える）。学んでいる間に閉じたら、AI への要求を取り消す
struct StyleLearningSheet: View {
    enum Mode: Identifiable {
        case learn
        case edit(CustomStyle)

        var id: String {
            switch self {
            case .learn: "learn"
            case .edit(let style): style.id.uuidString
            }
        }
    }

    let mode: Mode
    @ObservedObject var store: CustomStyleStore
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var inputMessage: String?
    @State private var budget: DictionarySuggester.Budget?
    @State private var learnTask: Task<Void, Never>?
    @State private var learnError: String?
    @State private var learned = false
    @State private var name = ""
    @State private var language = PromptLanguage.current
    @State private var rulesText = ""
    @State private var saveError: String?

    init(mode: Mode, store: CustomStyleStore, initialText: String = "", initialLearned: LearnedStyle? = nil) {
        self.mode = mode
        self.store = store
        _text = State(initialValue: initialText)
        if case .edit(let style) = mode {
            _name = State(initialValue: style.name)
            _language = State(initialValue: style.promptLanguage ?? .current)
            _rulesText = State(initialValue: style.rules.joined(separator: "\n"))
        } else if let initialLearned {
            _learned = State(initialValue: true)
            _name = State(initialValue: initialLearned.name)
            _language = State(initialValue: initialLearned.language)
            _rulesText = State(initialValue: initialLearned.rules.joined(separator: "\n"))
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var isLearning: Bool { learnTask != nil }
    private var characters: Int { StyleLearner.count(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
    private var material: StyleLearner.Material? { budget.map { StyleLearner.material(text, budget: $0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isEditing ? tr("カスタム文体を編集") : tr("文章から文体を学ぶ"))
                .font(.headline)
            if !isEditing {
                learnSection
                if learned { Divider() }
            }
            if isEditing || learned {
                resultSection
            }
            if let saveError {
                Text(saveError).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button(tr("キャンセル")) { close() }
                    .keyboardShortcut(.cancelAction)
                Button(tr("保存")) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!(isEditing || learned) || isLearning)
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear { budget = (try? TextAIClient.requireFromSettings(settings, for: .meeting)).map(StyleLearner.budget(for:)) ?? .characters(StyleLearner.characterLimit) }
        .onDisappear { learnTask?.cancel() }
    }

    @ViewBuilder private var learnSection: some View {
        Text(tr("自分で書いた文章（報告書・メールなど）を貼り付けるか、ファイル（Word・テキスト・Markdown）を選んでください。文章は「議事録」の AI に送って文体を読み取るだけで、保存しません。"))
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        TextEditor(text: $text)
            .font(.body)
            .frame(height: 160)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.4)))
            .disabled(isLearning)
            .accessibilityLabel(tr("文体を学ぶ文章"))
            .onChange(of: text) { _, newValue in limitInput(newValue) }
        HStack {
            Button(tr("ファイルを選ぶ…"), action: chooseFiles)
                .disabled(isLearning)
            Spacer()
            Text(countLabel).font(.caption).foregroundStyle(.secondary)
        }
        if let inputMessage {
            Text(inputMessage).font(.caption).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        HStack(spacing: 8) {
            Button(tr("文体を学ぶ"), action: learn)
                .disabled(characters < StyleLearner.minimumCharacters || isLearning)
            if isLearning {
                ProgressView().controlSize(.small)
                Text(tr("学んでいます…")).font(.caption)
                Button(tr("やめる")) { cancelLearning() }
                    .controlSize(.small)
            } else if characters < StyleLearner.minimumCharacters {
                Text(tr("%@ 字以上入れてください。", String(StyleLearner.minimumCharacters)))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        if let learnError {
            Text(learnError).font(.caption).foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var resultSection: some View {
        HStack {
            Text(tr("名前"))
            TextField(tr("名前"), text: $name)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
        }
        Picker(tr("言語"), selection: $language) {
            ForEach(PromptLanguage.allCases, id: \.self) { Text(TranslationLanguage($0).label).tag($0) }
        }
        Text(tr("文体のルール（1 行に 1 つ）"))
            .font(.caption)
        TextEditor(text: $rulesText)
            .font(.body)
            .frame(height: 140)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.4)))
            .accessibilityLabel(tr("文体のルール（1 行に 1 つ）"))
        Text(tr("保存の前にルールを読んで、要らないもの・内容を足すもの（挨拶を入れる など）は消してください。出力の言語が「言語」と同じときだけ使います。"))
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var countLabel: String {
        let total = tr("%@ 字", String(characters))
        guard let material, material.truncated else { return total }
        return total + "  " + tr("（先頭の %@ 字を使います）", String(material.usedCharacters))
    }

    // 設計判断: DEC-DIC-212（入力欄に入れるのは 100,000 字まで）
    private func limitInput(_ value: String) {
        guard StyleLearner.count(value) > StyleLearner.inputLimit else { return }
        text = StyleLearner.prefix(value, characters: StyleLearner.inputLimit)
        inputMessage = tr("入力欄には %@ 字まで入れられます。超えた分は入れていません。", String(StyleLearner.inputLimit))
    }

    // 設計判断: DEC-DIC-211
    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = StyleSourceReader.extensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = tr("読み込む")
        guard panel.runModal() == .OK else { return }
        var messages: [String] = []
        var added: [String] = []
        for url in panel.urls {
            switch StyleSourceReader.read(url) {
            case .success(let body): added.append(body)
            case .failure(let error): messages.append(tr("%@: %@", url.lastPathComponent, error.message))
            }
        }
        if !added.isEmpty {
            let joined = added.joined(separator: "\n\n")
            text = text.isEmpty ? joined : text + "\n\n" + joined
        }
        inputMessage = messages.isEmpty ? nil : messages.joined(separator: "\n")
        // 上限を超えたら limitInput が知らせる
        limitInput(text)
    }

    // 要件: REQ-DIC-022
    private func learn() {
        learnError = nil
        saveError = nil
        let source = text
        let model = settings.textModel(for: .meeting)
        learnTask = Task {
            defer { learnTask = nil }
            do {
                // 文体を学ぶのは長い文章を読む分析なので、議事録の AI を使う（DEC-DIC-210）
                let client = try TextAIClient.requireFromSettings(settings, for: .meeting)
                let style = try await StyleLearner.learn(text: source, client: client, model: model)
                guard !Task.isCancelled else { return }
                name = style.name
                language = style.language
                rulesText = style.rules.joined(separator: "\n")
                learned = true
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                learnError = "⚠️ " + error.localizedDescription
            }
        }
    }

    private func cancelLearning() {
        learnTask?.cancel()
        learnTask = nil
    }

    // 要件: REQ-DIC-022
    // 設計判断: DEC-DIC-213
    private func save() {
        let rules = CustomStyle.rules(fromText: rulesText)
        let id: UUID
        if case .edit(let style) = mode { id = style.id } else { id = UUID() }
        let others = store.styles.filter { $0.id != id }
        if let error = CustomStyle.validate(name: name, language: language.rawValue, rules: rules, others: others) {
            saveError = error.message
            return
        }
        store.upsert(CustomStyle(id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), language: language.rawValue, rules: rules))
        close()
    }

    private func close() {
        learnTask?.cancel()
        dismiss()
    }
}
