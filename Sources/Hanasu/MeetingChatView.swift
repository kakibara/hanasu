import AppKit
import SwiftUI

// 要件: REQ-MTG-041
// 設計判断: DEC-MTG-085, DEC-MTG-086
/// 会議 1 件分の AI チャットの状態。会話はアプリを終了するまでメモリにだけ持ち、ファイルには保存しない
@MainActor
final class MeetingChatModel: ObservableObject {
    let meetingID: String
    @Published var draft = ""
    @Published private(set) var messages: [MeetingChat.Message] = []
    @Published private(set) var running = false
    @Published private(set) var error: String?
    /// 「メモに残す」で残した答え
    @Published private(set) var savedToNotes: Set<UUID> = []
    /// 入力欄にフォーカスを移す（⌘J）
    @Published private(set) var focusRequest = UUID()

    private var task: Task<Void, Never>?
    /// 送っている質問（取り消し・やり直しのため）
    private var pending: (token: UUID, question: String)?

    init(meetingID: String) {
        self.meetingID = meetingID
    }

    var lastQuestionFailed: Bool { error != nil && messages.last?.role == .user }

    /// 質問を送る。material は送る時点の記録
    func send(_ text: String, material: MeetingChat.Material) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !running else { return }
        // 前に失敗した質問は、会話から外す（答えのない質問を残さない）
        if lastQuestionFailed { messages.removeLast() }
        let history = messages
        messages.append(MeetingChat.Message(role: .user, text: question))
        if draft.trimmingCharacters(in: .whitespacesAndNewlines) == question { draft = "" }
        error = nil
        running = true
        let token = UUID()
        pending = (token, question)
        task = Task { [weak self] in
            do {
                let settings = AppSettings.shared
                let client = try TextAIClient.requireFromSettings(settings, for: .meeting, timeout: 120)
                let result = try await MeetingChat.reply(question: question, material: material, history: history,
                                                         client: client, model: settings.textModel(for: .meeting))
                guard let self, self.pending?.token == token else { return }
                self.messages.append(MeetingChat.Message(role: .assistant, text: result.text,
                                                         coveredUntil: result.prompt.coveredUntil,
                                                         lineCount: result.prompt.lineCount))
                self.finish()
            } catch {
                guard let self, self.pending?.token == token else { return }
                self.error = "答えを作れませんでした: \(error.localizedDescription)"
                self.finish()
            }
        }
    }

    /// 送っている質問をやめ、質問を入力欄に戻す（直して送り直せるように）
    func cancel() {
        guard let pending else { return }
        task?.cancel()
        if messages.last?.role == .user { messages.removeLast() }
        if draft.isEmpty { draft = pending.question }
        error = nil
        finish()
    }

    /// 失敗した質問を、もう一度送る
    func retry(material: MeetingChat.Material) {
        guard lastQuestionFailed, let question = messages.last?.text else { return }
        send(question, material: material)
    }

    /// 会話を消して、新しく始める
    func clear() {
        task?.cancel()
        messages = []
        error = nil
        savedToNotes = []
        finish()
    }

    func markSaved(_ id: UUID) { savedToNotes.insert(id) }

    /// 確認用: AI を呼ばずに会話を入れる（--render-meeting-chat）
    func setMessagesForPreview(_ messages: [MeetingChat.Message], draft: String = "") {
        self.messages = messages
        self.draft = draft
    }
    func requestFocus() { focusRequest = UUID() }

    private func finish() {
        running = false
        pending = nil
        task = nil
    }
}

// 設計判断: DEC-MTG-086
/// 会議ごとの AI チャット。記録中の画面と会議ノートの「AI チャット」タブで、同じ会話を続けるために共有する
@MainActor
final class MeetingChatStore {
    static let shared = MeetingChatStore()
    private var models: [String: MeetingChatModel] = [:]

    func model(for meetingID: String) -> MeetingChatModel {
        if let model = models[meetingID] { return model }
        let model = MeetingChatModel(meetingID: meetingID)
        models[meetingID] = model
        return model
    }

    /// 会議を消したとき
    func remove(_ meetingID: String) {
        models[meetingID]?.clear()
        models[meetingID] = nil
    }
}

// MARK: - チャットの画面

// 要件: REQ-MTG-040, REQ-MTG-041
// 設計判断: DEC-MTG-083, DEC-MTG-084, DEC-MTG-085
/// 会議の AI チャット。記録中は右側のパネル、記録のあとは会議ノートの「AI チャット」タブに出す
struct MeetingChatView: View {
    @ObservedObject var model: MeetingChatModel
    /// 送る時点の記録を作る。nil なら送れない
    var material: () -> MeetingChat.Material?
    /// 記録中か（説明の文言を変える）
    var live: Bool
    /// 記録中は文字起こししないエンジン（Whisper / Gemini）の名前
    var batchEngineName: String?
    /// 答えの中の時刻を押したとき（録音開始からの秒数）
    var onJump: (Double) -> Void
    /// 答えをメモに残す（引数は答えと、質問した時点）。nil ならボタンを出さない
    var onSaveNote: ((MeetingChat.Message) -> Void)?

    @ObservedObject private var settings = AppSettings.shared
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if let batchEngineName, live {
                            Label("記録中の文字起こしがないため（\(batchEngineName)）、メモと印だけをもとに答えます。",
                                  systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if model.messages.isEmpty, !model.running {
                            emptyState
                        }
                        ForEach(model.messages) { message in
                            MeetingChatMessageRow(
                                message: message, saved: model.savedToNotes.contains(message.id),
                                onJump: onJump,
                                onSaveNote: saveAction(for: message))
                                .id(message.id)
                        }
                        if model.running {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text(live ? "ここまでの記録を読んでいます…" : "記録を読んでいます…")
                                    .font(.callout).foregroundStyle(.secondary)
                                Spacer()
                                Button("止める") { model.cancel() }
                                    .controlSize(.small)
                            }
                        }
                        if let error = model.error {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(error, systemImage: "exclamationmark.triangle.fill")
                                    .font(.callout)
                                    .foregroundStyle(.orange)
                                    .textSelection(.enabled)
                                if model.lastQuestionFailed {
                                    Button("もう一度") {
                                        if let current = material() { model.retry(material: current) }
                                    }
                                        .controlSize(.small)
                                }
                            }
                        }
                        Color.clear.frame(height: 1).id("chat-bottom")
                    }
                    .padding(12)
                }
                .onChange(of: model.messages.count) { scrollToBottom(proxy) }
                .onChange(of: model.running) { scrollToBottom(proxy) }
                .onAppear { proxy.scrollTo("chat-bottom", anchor: .bottom) }
            }
            Divider()
            if !model.messages.isEmpty {
                quickPromptChips
            }
            inputArea
        }
        .onChange(of: model.focusRequest) { inputFocused = true }
    }

    // MARK: 部品

    /// 会話を始める前: 何ができるかと、1 回押すだけの質問
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(live ? "ここまでの会話について AI に聞けます" : "この会議について AI に聞けます", systemImage: "sparkles")
                .font(.headline)
            Text(live
                 ? "聞き逃した話の確認や、決まったことの整理に。続けて質問すると、前のやりとりを踏まえて答えます。"
                 : "文字起こしとメモをもとに答えます。続けて質問すると、前のやりとりを踏まえて答えます。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(MeetingChat.quickPrompts) { prompt in
                    Button { send(prompt.question) } label: {
                        Label(prompt.label, systemImage: prompt.symbol)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(MeetingChatSuggestionButtonStyle())
                    .disabled(model.running)
                }
            }
            .padding(.top, 2)
        }
    }

    /// 会話のあと: 入力欄の上に、よく使う質問を小さく並べる
    private var quickPromptChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(MeetingChat.quickPrompts) { prompt in
                    Button { send(prompt.question) } label: {
                        Label(prompt.label, systemImage: prompt.symbol)
                            .font(.caption)
                    }
                    .buttonStyle(MeetingChatChipButtonStyle())
                    .disabled(model.running)
                    .help(prompt.question)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
        }
    }

    private var inputArea: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 6) {
                TextField(live ? "ここまでの会話について質問（↩ で送信）" : "この会議について質問（↩ で送信）",
                          text: $model.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .onSubmit { send(model.draft) }
                if model.running {
                    Button { model.cancel() } label: {
                        Image(systemName: "stop.circle.fill").font(.title2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("答えを待つのをやめる")
                } else {
                    Button { send(model.draft) } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
                    .disabled(!canSend)
                    .help("送信（↩）")
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(inputFocused ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.3)))
            HStack(spacing: 6) {
                Text(privacyNote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if !model.messages.isEmpty {
                    Button("新しい会話") { model.clear() }
                        .buttonStyle(.link)
                        .font(.caption)
                        .help("今の会話を消して、新しく始める")
                }
            }
        }
        .padding(10)
    }

    // 設計判断: DEC-MTG-085
    private var privacyNote: String {
        let provider = settings.aiProvider(for: .meeting).name
        return "文字起こしとメモを \(provider)（\(settings.textModel(for: .meeting))）に送ります。会話は保存しません。"
    }

    private var canSend: Bool {
        !model.running && !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send(_ text: String) {
        guard let current = material() else { return }
        model.send(text, material: current)
        inputFocused = true
    }

    /// 「メモに残す」のボタンの動作。残せないときは nil
    private func saveAction(for message: MeetingChat.Message) -> (() -> Void)? {
        guard let onSaveNote else { return nil }
        let model = self.model
        return {
            onSaveNote(message)
            model.markSaved(message.id)
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))  // 行ができてから
            withAnimation { proxy.scrollTo("chat-bottom", anchor: .bottom) }
        }
    }
}

/// 会話の 1 件。質問は右に吹き出し、答えは左に Markdown で出し、時刻を押すと文字起こしのその位置へ移る
private struct MeetingChatMessageRow: View {
    let message: MeetingChat.Message
    let saved: Bool
    var onJump: (Double) -> Void
    var onSaveNote: (() -> Void)?
    @State private var copied = false

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 32)
                Text(message.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(0.16)))
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 6) {
                Label("AI", systemImage: "sparkles")
                    .font(.caption.bold())
                    .foregroundStyle(.purple)
                MarkdownText(markdown: MeetingChat.linkingTimes(in: message.text))
                    .environment(\.openURL, OpenURLAction { url in
                        guard let seconds = MeetingChat.seconds(from: url) else { return .systemAction }
                        onJump(seconds)
                        return .handled
                    })
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    if let covered = message.coveredUntil {
                        Text("\(Meeting.clock(covered)) までの記録から")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .help("答えを作ったときに渡した記録の範囲（発言 \(message.lineCount ?? 0) 件）")
                    }
                    Spacer(minLength: 0)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.text, forType: .string)
                        copied = true
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(1.5))
                            copied = false
                        }
                    } label: {
                        Label(copied ? "コピーしました" : "コピー", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .help("答えをコピーする")
                    if let onSaveNote {
                        Button(action: onSaveNote) {
                            Label(saved ? "メモに残しました" : "メモに残す",
                                  systemImage: saved ? "checkmark" : "note.text.badge.plus")
                        }
                        .disabled(saved)
                        .help("この答えをメモに足す（議事録で優先して取り上げます）")
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .labelStyle(.titleAndIcon)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08)))
        }
    }
}

/// 会話を始める前の、よく使う質問のボタン
private struct MeetingChatSuggestionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SuggestionLabel(configuration: configuration)
    }

    private struct SuggestionLabel: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.22 : 0.1)))
                .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
        }
    }
}

/// 入力欄の上の、小さな質問のボタン
private struct MeetingChatChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ChipLabel(configuration: configuration)
    }

    private struct ChipLabel: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.secondary.opacity(configuration.isPressed ? 0.25 : 0.12)))
                .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
        }
    }
}

// MARK: - 記録中の画面の右側

// 設計判断: DEC-MTG-080
/// 記録中の画面の右側に出すもの
enum LiveSidePanelMode: String {
    case notes
    case chat
}

// 要件: REQ-MTG-040
// 設計判断: DEC-MTG-080
/// 記録中の画面の右側: 「メモ」と「AI チャット」を切り替える。文字起こしは左に出したまま
struct LiveSidePanel: View {
    @ObservedObject var recorder: MeetingRecorder
    @ObservedObject var chat: MeetingChatModel
    @Binding var mode: LiveSidePanelMode
    /// 答えの中の時刻を押したとき
    var onJump: (Double) -> Void

    var body: some View {
        Group {
            switch mode {
            case .notes:
                LiveNotesPanel(recorder: recorder, mode: $mode)
            case .chat:
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        LiveSidePanelModePicker(mode: $mode)
                        Spacer()
                        LiveHighlightControls(recorder: recorder)
                    }
                    .padding([.horizontal, .top])
                    HighlightUndoButton(recorder: recorder)
                        .padding(.horizontal)
                        .padding(.top, 4)
                    MeetingChatView(
                        model: chat,
                        material: { MeetingChat.liveMaterial(recorder: recorder) },
                        live: true,
                        batchEngineName: recorder.batchEngine?.shortName,
                        onJump: onJump,
                        onSaveNote: saveNote)
                }
            }
        }
        // ⌘J で AI チャットへ（入力欄にフォーカス）
        .background {
            Button("") {
                mode = .chat
                chat.requestFocus()
            }
            .keyboardShortcut("j", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
    }
}

extension LiveSidePanel {
    // 設計判断: DEC-MTG-085
    /// 答えをメモに残す（質問した時刻のメモにする）。記録中だけ
    fileprivate var saveNote: ((MeetingChat.Message) -> Void)? {
        guard recorder.state == .recording else { return nil }
        let recorder = self.recorder
        return { message in
            recorder.addNote(MeetingChat.noteText(from: message.text), at: message.coveredUntil)
        }
    }
}

/// 右側の「メモ」「AI チャット」の切り替え
struct LiveSidePanelModePicker: View {
    @Binding var mode: LiveSidePanelMode

    var body: some View {
        Picker("", selection: $mode) {
            Text("メモ").tag(LiveSidePanelMode.notes)
            Text("AI チャット").tag(LiveSidePanelMode.chat)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help("メモと AI チャットを切り替える（AI チャットは ⌘J）")
    }
}
