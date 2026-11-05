import SwiftUI

// 要件: REQ-DIC-030
/// 設定画面の「スニペット」タブ。左に一覧、右に選んだスニペットの編集欄。
struct SnippetsSettingsView: View {
    @ObservedObject var store: SnippetStore
    @State private var selection: Snippet.ID?
    @State private var confirmRemove = false

    init(store: SnippetStore = .shared, initialSelection: Snippet.ID? = nil) {
        self.store = store
        _selection = State(initialValue: initialSelection ?? store.snippets.first?.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("決まった言葉（起動フレーズ）だけを話すと、登録した文章をそのまま入力します。本文は Gemini に送らず、翻訳して入力するときも訳しません。")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 12) {
                list
                    .frame(width: 170)
                editor
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            Text("文の途中でも、「よろしくお願いします、メールの署名」のように読点や間で区切って言えば、その部分だけを本文に置き換え、残りを整えます。区切らずに言った「住所を教えて」の「住所」などは置き換えません。")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .confirmationDialog("選んだスニペットを削除しますか？", isPresented: $confirmRemove) {
            Button("削除", role: .destructive) { removeSelected() }
        } message: {
            Text("起動フレーズと本文が消えます。元に戻せません。")
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(store.snippets) { snippet in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snippet.displayName.isEmpty ? "（起動フレーズなし）" : snippet.displayName)
                            .lineLimit(1)
                            .foregroundStyle(snippet.displayName.isEmpty ? .secondary : .primary)
                        Text(firstLine(of: snippet.body))
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .tag(snippet.id)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: false))
            HStack(spacing: 0) {
                Button(action: add) { Image(systemName: "plus").frame(width: 22, height: 18) }
                    .help("スニペットを追加")
                    .accessibilityLabel("スニペットを追加")
                Divider().frame(height: 16)
                Button(action: requestRemove) { Image(systemName: "minus").frame(width: 22, height: 18) }
                    .disabled(selection == nil)
                    .help("選んだスニペットを削除")
                    .accessibilityLabel("選んだスニペットを削除")
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(.vertical, 3)
            .padding(.horizontal, 4)
            .background(.quaternary.opacity(0.4))
        }
    }

    @ViewBuilder private var editor: some View {
        if let id = selection, let snippet = store.snippets.first(where: { $0.id == id }) {
            VStack(alignment: .leading, spacing: 6) {
                Text("起動フレーズ").font(.headline)
                TextField("例: メールの署名", text: binding(id, \.trigger))
                    .textFieldStyle(.roundedBorder)
                Text("「、」で区切ると、別の言い方も登録できます（例: 会議URL、会議のリンク）。")
                    .font(.caption).foregroundStyle(.secondary)
                if !snippet.phrases.isEmpty {
                    Text("照合する形: " + snippet.phrases.map(SnippetMatcher.normalize).joined(separator: " / "))
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.tail)
                        .help("空白・句読点を除き、カタカナはひらがなに、英字は小文字にそろえて照合します。話したときの末尾の「です」なども除きます。")
                }
                Text("本文").font(.headline).padding(.top, 6)
                TextEditor(text: binding(id, \.body))
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                    .frame(minHeight: 110, maxHeight: .infinity)
                if let problem = problem(of: snippet) {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        } else {
            ContentUnavailableView {
                Label("スニペットがありません", systemImage: "text.badge.plus")
            } description: {
                Text("＋ で追加し、起動フレーズと本文を\n入力してください。\n例: メールの署名、自己紹介、住所、会議URL")
            }
        }
    }

    private func binding(_ id: Snippet.ID, _ keyPath: WritableKeyPath<Snippet, String>) -> Binding<String> {
        Binding(
            get: { store.snippets.first(where: { $0.id == id })?[keyPath: keyPath] ?? "" },
            set: { value in
                if let index = store.snippets.firstIndex(where: { $0.id == id }) {
                    store.snippets[index][keyPath: keyPath] = value
                }
            })
    }

    /// 使えない・紛らわしい設定の知らせ
    private func problem(of snippet: Snippet) -> String? {
        if snippet.phrases.allSatisfy({ SnippetMatcher.normalize($0).isEmpty }) {
            return "起動フレーズを入力してください。"
        }
        if snippet.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "本文が空のあいだは使われません。"
        }
        let mine = Set(snippet.phrases.map(SnippetMatcher.normalize))
        if let earlier = store.snippets.prefix(while: { $0.id != snippet.id })
            .first(where: { !mine.isDisjoint(with: $0.phrases.map(SnippetMatcher.normalize)) })
        {
            return "『\(earlier.displayName)』と同じ起動フレーズがあります。一覧で上にある方が使われます。"
        }
        return nil
    }

    private func firstLine(of text: String) -> String {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty && $0 != "--" }) ?? ""
    }

    private func add() {
        let snippet = Snippet(trigger: "", body: "")
        store.snippets.append(snippet)
        selection = snippet.id
    }

    /// 中身のあるスニペットは確かめてから消す（空のものはそのまま消す）
    private func requestRemove() {
        guard let id = selection, let snippet = store.snippets.first(where: { $0.id == id }) else { return }
        if snippet.trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && snippet.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            removeSelected()
        } else {
            confirmRemove = true
        }
    }

    private func removeSelected() {
        guard let id = selection, let index = store.snippets.firstIndex(where: { $0.id == id }) else { return }
        store.snippets.remove(at: index)
        selection = store.snippets.indices.contains(index) ? store.snippets[index].id : store.snippets.last?.id
    }
}
