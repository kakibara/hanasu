import SwiftUI

// 設計判断: DEC-DIC-090
/// 設定画面の「ユーザー辞書」の欄。表で 1 行ずつ編集するか、テキストでまとめて編集する。
/// 保存先は今までどおり設定の dictionaryText（1 行 1 項目の文字列）だけにして、表はその見せ方を変えるだけにする。
struct DictionaryEditorSection: View {
    @Binding var text: String
    @State private var editsAsText = false
    @State private var rows: [Row] = []
    /// 表から書き戻した文字列。これと違う変更が来たら（テキスト欄や候補の追加）、表を読み直す
    @State private var lastWritten: String?

    init(text: Binding<String>) {
        _text = text
    }

    /// 表の 1 行。コメントと空行も、並びを保つために持っておく（表には出さない）
    struct Row: Identifiable, Equatable {
        let id = UUID()
        var reading = ""
        var spelling = ""
        /// コメント・空行のときの元の文字列
        var other: String?
        /// 読み込んだときの行。編集していなければ書き戻すときもそのまま使う（書き方の揺れを勝手に直さない）
        var original: (reading: String, spelling: String, line: String)?

        static func == (a: Row, b: Row) -> Bool {
            a.id == b.id && a.reading == b.reading && a.spelling == b.spelling && a.other == b.other
        }

        var line: String {
            if let other { return other }
            if let original, original.reading == reading, original.spelling == spelling { return original.line }
            return UserDictionary.Entry(reading: reading, spelling: spelling).line
        }
    }

    var body: some View {
        Section {
            if editsAsText {
                TextEditor(text: $text)
                    .font(.body.monospaced())
                    .frame(minHeight: 140)
            } else {
                table
            }
        } header: {
            HStack {
                Text(tr("ユーザー辞書"))
                Spacer()
                Picker(tr("編集のしかた"), selection: $editsAsText) {
                    Text(tr("表")).tag(false)
                    Text(tr("テキスト")).tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("「読み・誤認識」を書くと、文字起こしの結果のその部分を「正しい表記」に置き換えます（AI で整形しないときも効きます）。空にすると語だけを登録し、音声認識と AI のヒントにします。"))
                Text(tr("英字の大文字小文字・全角半角・空白の有無は区別しません。英字やカタカナの語の途中では置き換えません（例: 「マーク」は「マークダウン」の中では置き換えない）。テキストでは「ストックマーク => Stockmark」のように書き、読みは「,」で区切って複数書けます。"))
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { reload() }
        .onChange(of: text) { _, newValue in
            if newValue != lastWritten { reload() }
        }
        .onChange(of: rows) { _, _ in
            let newText = rows.map(\.line).joined(separator: "\n")
            lastWritten = newText
            if newText != text { text = newText }
        }
    }

    @ViewBuilder
    private var table: some View {
        let issues = UserDictionary(text: rows.map(\.line).joined(separator: "\n")).issues
        HStack {
            Text(tr("読み・誤認識（空なら語だけ）")).frame(maxWidth: .infinity, alignment: .leading)
            Text(tr("正しい表記")).frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: 44, height: 1)
        }
        .font(.caption).foregroundStyle(.secondary)
        ForEach($rows) { $row in
            if row.other == nil {
                HStack(spacing: 6) {
                    TextField(tr("読み・誤認識"), text: $row.reading, prompt: Text(tr("（語だけ）")))
                        .labelsHidden()
                    Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                    TextField(tr("正しい表記"), text: $row.spelling, prompt: Text(tr("正しい表記")))
                        .labelsHidden()
                    Group {
                        if let index = rows.firstIndex(where: { $0.id == row.id }), let issue = issues[index] {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)  // 黄は白い背景で見えにくい（DEC-MTG-075 と同じ考え）
                                .help(issue)
                                .accessibilityLabel(issue)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: 16)
                    Button {
                        rows.removeAll { $0.id == row.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help(tr("この行を削除"))
                    .accessibilityLabel(tr("この行を削除"))
                }
            }
        }
        if rows.allSatisfy({ $0.other != nil }) {
            Text(tr("まだ登録がありません。「行を追加」か、下の「候補を探す」から追加できます。"))
                .font(.callout).foregroundStyle(.secondary)
        }
        Button {
            // 末尾の空行の後ろに足すと空行を挟むので、空行は新しい行で置き換える
            if let last = rows.last, let other = last.other, other.trimmingCharacters(in: .whitespaces).isEmpty {
                rows.removeLast()
            }
            rows.append(Row())
        } label: {
            Label(tr("行を追加"), systemImage: "plus")
        }
        .buttonStyle(.borderless)
    }

    private func reload() {
        lastWritten = text
        rows = UserDictionary(text: text).lines.map { line in
            switch line {
            case .entry(let entry):
                Row(reading: entry.reading, spelling: entry.spelling,
                    original: (entry.reading, entry.spelling, entry.line))
            case .other(let raw):
                Row(other: raw)
            }
        }
    }
}

// 要件: REQ-DIC-071, REQ-DIC-072
/// 辞書の候補の 1 行（チェックボックス・`読み → 表記`・理由）。設定の欄と会議ノートの候補の画面で同じ見た目にする（DEC-DIC-171）
struct DictionaryCandidateRow: View {
    let candidate: DictionaryCandidate
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(candidate.readings.isEmpty
                 ? candidate.spelling
                 : "\(candidate.readings.joined(separator: "、")) → \(candidate.spelling)")
            if !candidate.reason.isEmpty { Text(candidate.reason) }
        }
        .toggleStyle(.checkbox)
    }
}

// 要件: REQ-DIC-071
// 設計判断: DEC-DIC-087
/// 設定画面の「辞書の候補」の欄。ボタンを押したときだけ、過去の音声入力の結果と会議の記録を Gemini に送って候補を挙げてもらう。
struct DictionarySuggestionSection: View {
    @ObservedObject var settings: AppSettings
    @State private var includeDictations = true
    @State private var includeMeetings = true
    @State private var meetingCount = 0
    @State private var isSearching = false
    @State private var message: String?
    @State private var candidates: [DictionaryCandidate]
    @State private var selected: Set<UUID>

    /// candidates と selected は、見た目の確認（--render-dictionary-settings）で候補を並べるときだけ渡す
    init(settings: AppSettings, candidates: [DictionaryCandidate] = [], selected: Set<UUID> = []) {
        self.settings = settings
        _candidates = State(initialValue: candidates)
        _selected = State(initialValue: selected)
    }

    var body: some View {
        Section {
            Toggle(tr("音声入力の結果（今回の起動後の %@ 件）", "\(RecentDictations.entries.count)"), isOn: $includeDictations)
            Toggle(tr("会議の文字起こしと議事録（新しい順に %@ 件）", "\(meetingCount)"), isOn: $includeMeetings)
            HStack {
                Button(isSearching ? tr("探しています…") : tr("候補を探す"), action: search)
                    .disabled(isSearching || (!includeDictations && !includeMeetings))
                if isSearching { ProgressView().controlSize(.small) }
                Spacer()
                if !candidates.isEmpty {
                    Button(tr("選んだ %@ 件を辞書に追加", "\(selected.count)"), action: addSelected)
                        .disabled(selected.isEmpty)
                }
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(candidates) { candidate in
                DictionaryCandidateRow(candidate: candidate, isOn: binding(for: candidate))
            }
        } header: {
            Text(tr("辞書の候補を探す"))
        } footer: {
            Text(tr("固有名詞や誤認識しやすい語を AI が挙げます。選んだものだけを辞書に追加し、自動では追加しません。会議の中身は、設定の「AI」で会議に選んだ AI にだけ渡します（「ローカル」か「Apple」なら、この Mac の外には送りません）。音声入力の結果はメモリ上だけにあり、アプリを終了すると消えます。"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { meetingCount = DictionarySuggester.recentMeetings().count }
    }

    private func binding(for candidate: DictionaryCandidate) -> Binding<Bool> {
        Binding(
            get: { selected.contains(candidate.id) },
            set: { if $0 { selected.insert(candidate.id) } else { selected.remove(candidate.id) } })
    }

    private func search() {
        let corpus = DictionarySuggester.corpus(includeDictations: includeDictations, includeMeetings: includeMeetings)
        meetingCount = DictionarySuggester.recentMeetings().count
        guard !corpus.isEmpty else {
            message = tr("材料がありません。音声入力をするか、会議を記録してからもう一度試してください。")
            return
        }
        isSearching = true
        message = nil
        candidates = []
        selected = []
        let existing = settings.userDictionary
        let model = settings.textModel(for: .meeting)
        Task {
            do {
                // 辞書の候補探しは会議の記録を読む長い処理なので、会議の AI を使う（DEC-COM-040）
                let client = try TextAIClient.requireFromSettings(settings, for: .meeting)
                let found = try await DictionarySuggester.suggest(
                    corpus: corpus, existing: existing, client: client, model: model)
                candidates = found
                message = found.isEmpty ? tr("新しい候補は見つかりませんでした。") : tr("追加したいものを選んでください（%@）。", "\(model)")
            } catch {
                message = "⚠️ " + error.localizedDescription
            }
            isSearching = false
        }
    }

    private func addSelected() {
        let chosen = candidates.filter { selected.contains($0.id) }
        settings.dictionaryText = DictionarySuggester.appending(chosen, to: settings.dictionaryText)
        candidates.removeAll { selected.contains($0.id) }
        selected = []
        message = tr("%@ 件を辞書に追加しました。", "\(chosen.count)")
    }
}
