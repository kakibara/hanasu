import AppKit
import SwiftUI

/// 会議ノートの検索欄の状態。索引は会議の一覧が変わるたびに、変わった会議の分だけ作り直す。
@MainActor
final class MeetingSearchModel: ObservableObject {
    @Published var query = "" {
        didSet { if query != oldValue { scheduleSearch() } }
    }
    @Published private(set) var results: [MeetingSearchResult] = []
    @Published private(set) var searching = false

    let index = MeetingSearchIndex()
    private var searchTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?

    var isActive: Bool { !MeetingSearchIndex.terms(of: query).isEmpty }
    var terms: [String] { MeetingSearchIndex.terms(of: query) }

    func update(_ meetings: [Meeting]) {
        let previous = updateTask
        updateTask = Task {
            await previous?.value
            await index.update(meetings)
            // 開いている検索結果も新しい内容で出し直す
            if isActive { scheduleSearch(delay: .zero) }
        }
    }

    private func scheduleSearch(delay: Duration = .milliseconds(150)) {
        searchTask?.cancel()
        let query = query
        guard isActive else {
            results = []
            searching = false
            return
        }
        searching = true
        searchTask = Task {
            try? await Task.sleep(for: delay)  // 打っている途中は待つ
            guard !Task.isCancelled else { return }
            await updateTask?.value
            let found = await index.search(query)
            guard !Task.isCancelled else { return }
            results = found
            searching = false
        }
    }

    /// 確認用: 検索を待たずに結果を入れる
    func setResultsForPreview(_ results: [MeetingSearchResult]) {
        self.results = results
        searching = false
    }
}

/// 検索結果から会議を開くときの飛び先
struct MeetingJump: Equatable {
    var meetingID: String
    var location: MeetingSearchHit.Location?
    var terms: [String]
    /// 同じ箇所をもう一度選んだときにも飛ぶように、選ぶたびに変える
    var token = UUID()
}

/// 会議への質問（Ask）の状態
@MainActor
final class MeetingAskModel: ObservableObject {
    @Published var question = ""
    @Published private(set) var answer: MeetingAsk.Answer?
    @Published private(set) var running = false
    @Published private(set) var error: String?
    private var lastQuestion = ""

    func ask(meetings: [Meeting], index: MeetingSearchIndex) {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !running else { return }
        running = true
        error = nil
        answer = nil
        lastQuestion = question
        Task {
            defer { running = false }
            do {
                let settings = AppSettings.shared
                guard let auth = try GeminiClient.authFromSettings(settings) else { throw GeminiError.missingAPIKey }
                await index.update(meetings)
                answer = try await MeetingAsk.ask(
                    question: question, meetings: meetings, index: index,
                    client: GeminiClient(auth: auth, timeout: 180), model: settings.meetingMinutesModel)
            } catch {
                self.error = "答えを作れませんでした: \(error.localizedDescription)"
            }
        }
    }

    var answeredQuestion: String { lastQuestion }

    /// 確認用: Gemini を呼ばずに答えを入れる
    func setAnswerForPreview(question: String, answer: MeetingAsk.Answer) {
        self.question = question
        lastQuestion = question
        self.answer = answer
    }
}

// MARK: - 検索欄

/// サイドバーの上に置く検索欄と、質問を開くボタン
struct MeetingSearchField: View {
    @ObservedObject var model: MeetingSearchModel
    var onAsk: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("会議を検索", text: $model.query)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onExitCommand { model.query = "" }
                if !model.query.isEmpty {
                    Button { model.query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("検索をやめる")
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary.opacity(0.6)))
            Button(action: onAsk) {
                Image(systemName: "sparkles")
            }
            .help("過去の会議について Gemini に質問する")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        // ⌘F で検索欄へ
        .background {
            Button("") { focused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - 検索結果

// 要件: REQ-MTG-015
/// 検索でヒットした会議と箇所の一覧。箇所を選ぶと、その会議のその位置に飛ぶ。
struct MeetingSearchResultsList: View {
    @ObservedObject var model: MeetingSearchModel
    var selectedHitID: String?
    var onOpen: (String, MeetingSearchHit?) -> Void

    var body: some View {
        List {
            if model.results.isEmpty {
                Text(model.searching ? "検索しています…" : "見つかりませんでした")
                    .foregroundStyle(.secondary)
            } else {
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(model.results) { result in
                Section {
                    ForEach(result.hits) { hit in
                        Button { onOpen(result.meetingID, hit) } label: {
                            MeetingSearchHitRow(hit: hit, terms: model.terms)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(selectedHitID == hit.id ? Color.accentColor.opacity(0.18) : Color.clear)
                    }
                    if result.totalHits > result.hits.count {
                        Text("ほか \(result.totalHits - result.hits.count) 件").font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Button { onOpen(result.meetingID, nil) } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(result.title).font(.callout.bold()).foregroundStyle(.primary).lineLimit(1)
                            Text("\(Meeting.dateFormatter.string(from: result.startedAt))・\(result.totalHits) 件")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var summary: String {
        "\(model.results.count) 件の会議・\(model.results.reduce(0) { $0 + $1.totalHits }) か所"
    }
}

private struct MeetingSearchHitRow: View {
    let hit: MeetingSearchHit
    let terms: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                switch hit.location {
                case .title:
                    Label("タイトル", systemImage: "textformat")
                case .minutes:
                    Label("議事録", systemImage: "doc.text")
                case .transcript(_, let start, let speaker):
                    Label("\(Meeting.clock(start)) \(speaker)", systemImage: "text.bubble")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
            Text(MeetingSearchHighlight.apply(AttributedString(hit.snippet), terms: terms))
                .font(.callout)
                .lineLimit(3)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 検索語に色を付ける
enum MeetingSearchHighlight {
    static func apply(_ text: AttributedString, terms: [String]) -> AttributedString {
        var text = text
        for term in terms where !term.isEmpty {
            var searchStart = text.startIndex
            while searchStart < text.endIndex,
                  let range = text[searchStart...].range(of: term, options: [.caseInsensitive, .widthInsensitive]) {
                text[range].backgroundColor = Color.yellow.opacity(0.45)
                searchStart = range.upperBound
            }
        }
        return text
    }
}

// MARK: - 質問

// 要件: REQ-MTG-016
/// 過去の会議について Gemini に質問する画面
struct MeetingAskView: View {
    @ObservedObject var model: MeetingAskModel
    var meetings: [Meeting]
    var index: MeetingSearchIndex
    var onOpen: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Label("会議に質問", systemImage: "sparkles").font(.title2.bold())
                Text("検索でヒットした会議と直近の会議の議事録（なければ文字起こし）を Gemini に渡して答えさせます。会議の内容は Gemini にだけ送ります。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField("例: 先週の定例で何が決まった？", text: $model.question)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { model.ask(meetings: meetings, index: index) }
                    Button("質問") { model.ask(meetings: meetings, index: index) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.running || model.question.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if model.running {
                        ProgressView("会議の記録を集めて答えを作っています…").controlSize(.small)
                    }
                    if let error = model.error {
                        Text(error).foregroundStyle(.orange)
                    }
                    if let answer = model.answer {
                        Text(model.answeredQuestion).font(.headline)
                        MarkdownText(markdown: answer.text)
                            .textSelection(.enabled)
                        sources(answer)
                    } else if !model.running, model.error == nil {
                        Text("会議の記録から答えます。「先週」「昨日」「11月2日」のように期間を書くと、その期間の会議に絞ります。")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
        }
    }

    @ViewBuilder private func sources(_ answer: MeetingAsk.Answer) -> some View {
        if !answer.sources.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("渡した会議（\(answer.sources.count) 件）").font(.caption.bold()).foregroundStyle(.secondary)
                ForEach(answer.sources) { source in
                    Button { onOpen(source.meetingID) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: answer.cited.contains(source) ? "quote.bubble.fill" : "doc.text")
                                .foregroundStyle(answer.cited.contains(source) ? Color.accentColor : .secondary)
                            Text(source.label)
                            if answer.cited.contains(source) { Text("引用").font(.caption).foregroundStyle(Color.accentColor) }
                            if !source.matched { Text("直近").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    .buttonStyle(.link)
                }
                if !answer.keywords.isEmpty {
                    Text("検索した語: \(answer.keywords.joined(separator: "、"))").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
