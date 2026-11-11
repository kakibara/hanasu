import AppKit
import Combine
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
    // 要件: REQ-MTG-048
    // 設計判断: DEC-MTG-150
    /// この会議の会話だけ、既定から切り替えた送り先。nil なら既定（設定の「AI チャット・質問」）。
    /// 「新しい会話」では戻さず、アプリを終了するか会議を消すまで残す
    @Published var override: TextAIChoice?
    /// 送り先が使えるか（画面が出たとき・設定が変わったとき・ウインドウが前に出たとき・送る前に見直す）
    @Published private(set) var availability: AIRoute.Availability?
    /// Apple の fm の判定（署名を確かめるので、1 回だけ）
    private var appleFMReason: String??
    // 設計判断: DEC-COM-172
    /// ローカルの AI で、ほかの処理が終わるのを待っている
    @Published private(set) var waitingForOtherModel = false
    // 設計判断: DEC-MTG-098
    /// 会話の世代。「新しい会話」で増やす（押したあとに会話を消したら、「何を聞かれた？」の答えを入れないため）
    private(set) var generation = 0

    private var task: Task<Void, Never>?
    /// 送っている質問（取り消し・やり直しのため）
    private var pending: (token: UUID, question: String)?

    init(meetingID: String) {
        self.meetingID = meetingID
    }

    var lastQuestionFailed: Bool { error != nil && messages.last?.role == .user }

    /// 次の質問を送る先
    func effectiveChoice(settings: AppSettings) -> TextAIChoice {
        override ?? settings.aiChoice(for: .chat)
    }

    /// 送り先が使えるかを見直す。Apple の判定は最初の 1 回だけ
    func refreshAvailability(settings: AppSettings) {
        guard !availabilityFixedForPreview else { return }
        if appleFMReason == nil { appleFMReason = .some(AIRoute.appleFMReason()) }
        availability = AIRoute.availability(settings: settings, appleFMReason: appleFMReason ?? nil)
    }

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
        // 要件: REQ-COM-025, REQ-MTG-048
        // 設計判断: DEC-MTG-081, DEC-MTG-150
        let settings = AppSettings.shared
        refreshAvailability(settings: settings)
        let choice = effectiveChoice(settings: settings)
        task = Task { [weak self] in
            do {
                let client = try TextAIClient.require(choice, settings: settings, for: .chat, timeout: 120)
                // 設計判断: DEC-COM-172（実際に待っている間だけ「待っています」と出す）
                let result = try await LocalLLMServer.observingWait({ [weak self] waiting in
                    guard let self, self.pending?.token == token else { return }
                    self.waitingForOtherModel = waiting
                }) {
                    try await MeetingChat.reply(question: question, material: material, history: history,
                                                client: client, model: choice.model)
                }
                guard let self, self.pending?.token == token else { return }
                self.messages.append(MeetingChat.Message(role: .assistant, text: result.text,
                                                         coveredUntil: result.prompt.coveredUntil,
                                                         lineCount: result.prompt.lineCount,
                                                         modelLabel: choice.label))
                self.finish()
            } catch {
                guard let self, self.pending?.token == token else { return }
                self.error = tr("答えを作れませんでした: %@", "\(error.localizedDescription)")
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
        generation += 1
        messages = []
        error = nil
        savedToNotes = []
        finish()
    }

    func markSaved(_ id: UUID) { savedToNotes.insert(id) }

    // 要件: REQ-MTG-047
    // 設計判断: DEC-MTG-098
    /// 答えの付いた質問と答えの組を足す（「何を聞かれた？」はウインドウのチャットを待たずに聞き、答えが出てから入れる）。
    /// 答えを待っている（か失敗した）質問があれば、その前に入れる。generation が今と違えば（会話を消したあとなら）入れない
    @discardableResult
    func insertAnsweredTurn(question: MeetingChat.Message, answer: MeetingChat.Message, generation: Int) -> Bool {
        guard generation == self.generation else { return false }
        let unanswered = messages.last?.role == .user
        let index = unanswered ? messages.count - 1 : messages.count
        messages.insert(contentsOf: [question, answer], at: index)
        return true
    }

    /// 確認用: AI を呼ばずに会話を入れる（--render-meeting-chat）
    func setMessagesForPreview(_ messages: [MeetingChat.Message], draft: String = "") {
        self.messages = messages
        self.draft = draft
    }
    func requestFocus() { focusRequest = UUID() }
    /// 確認用: 送り先が使えるかを決めて描く（--render-meeting-chat）
    func setAvailabilityForPreview(_ availability: AIRoute.Availability) {
        self.availability = availability
        availabilityFixedForPreview = true
    }
    private var availabilityFixedForPreview = false

    private func finish() {
        running = false
        waitingForOtherModel = false
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
    // 要件: REQ-MTG-047
    /// 「何を聞かれた？」を押したとき（記録中だけ。MeetingAskedQuestion に渡す）。nil なら押せない
    var onAsked: (() -> Void)?
    @ObservedObject private var asked = MeetingAskedQuestion.shared

    @ObservedObject private var settings = AppSettings.shared
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if let batchEngineName, live {
                            Label(tr("記録中の文字起こしがないため（%@）、メモと印だけをもとに答えます。", "\(batchEngineName)"),
                                  systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let unavailable = defaultUnavailableReason {
                            AIRouteUnavailableNotice(defaultChoice: settings.aiChoice(for: .chat), reason: unavailable)
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
                        // 要件: REQ-MTG-047
                        if asked.isRunning(for: model.meetingID) {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text(tr("直前に聞かれたことを探しています…"))
                                    .font(.callout).foregroundStyle(.secondary)
                                Spacer()
                                Button(tr("止める")) { asked.cancel() }
                                    .controlSize(.small)
                            }
                        }
                        if live, let notice = asked.notice(for: model.meetingID, generation: model.generation) {
                            Label(notice, systemImage: "exclamationmark.triangle.fill")
                                .font(.callout)
                                .foregroundStyle(.orange)
                        }
                        if live, let failure = asked.failure(for: model.meetingID, generation: model.generation) {
                            Label(failure, systemImage: "exclamationmark.triangle.fill")
                                .font(.callout)
                                .foregroundStyle(.orange)
                                .textSelection(.enabled)
                        }
                        if model.running {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text(model.waitingForOtherModel
                                     ? tr("ほかの処理が終わるのを待っています…")
                                     : (live ? tr("ここまでの記録を読んでいます…") : tr("記録を読んでいます…")))
                                    .font(.callout).foregroundStyle(.secondary)
                                Spacer()
                                Button(tr("止める")) { model.cancel() }
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
                                    Button(tr("もう一度")) {
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
        // 設計判断: DEC-MTG-150（使えるかは、画面が出たとき・設定が変わったとき・ウインドウが前に出たとき・送る前に見直す）
        .onAppear { model.refreshAvailability(settings: settings) }
        .onReceive(AIRoute.availabilityRefreshes(settings: settings)) { _ in
            model.refreshAvailability(settings: settings)
        }
    }

    // 要件: REQ-COM-025
    /// 既定のまま送ると使えないときの理由（切り替えていれば出さない）
    private var defaultUnavailableReason: String? {
        guard model.override == nil, let availability = model.availability else { return nil }
        return availability.unavailableReason(settings.aiChoice(for: .chat))
    }

    // MARK: 部品

    /// 会話を始める前: 何ができるかと、1 回押すだけの質問
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(live ? tr("ここまでの会話について AI に聞けます") : tr("この会議について AI に聞けます"), systemImage: "sparkles")
                .font(.headline)
            Text(live
                 ? tr("聞き逃した話の確認や、決まったことの整理に。続けて質問すると、前のやりとりを踏まえて答えます。")
                 : tr("文字起こしとメモをもとに答えます。続けて質問すると、前のやりとりを踏まえて答えます。"))
                .font(.callout)
                .foregroundStyle(.secondary)
                // 設計判断: DEC-MTG-048（後ろ側のパネルは幅が変わるので、fixedSize にせず行数で抑える）
                .lineLimit(4)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(MeetingChat.quickPrompts(live: live)) { prompt in
                    Button { tap(prompt) } label: {
                        Label(prompt.label, systemImage: prompt.symbol)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(MeetingChatSuggestionButtonStyle())
                    .disabled(!enabled(prompt))
                    .help(help(for: prompt))
                }
            }
            .padding(.top, 2)
        }
    }

    /// 会話のあと: 入力欄の上に、よく使う質問を小さく並べる
    private var quickPromptChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(MeetingChat.quickPrompts(live: live)) { prompt in
                    Button { tap(prompt) } label: {
                        Label(prompt.label, systemImage: prompt.symbol)
                            .font(.caption)
                    }
                    .buttonStyle(MeetingChatChipButtonStyle())
                    .disabled(!enabled(prompt))
                    .help(help(for: prompt))
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
        }
    }

    private var inputArea: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 6) {
                TextField(live ? tr("ここまでの会話について質問（↩ で送信）") : tr("この会議について質問（↩ で送信）"),
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
                    .help(tr("答えを待つのをやめる"))
                } else {
                    Button { send(model.draft) } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
                    .disabled(!canSend)
                    .help(tr("送信（↩）"))
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(inputFocused ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.3)))
            HStack(spacing: 6) {
                // 要件: REQ-MTG-048
                if let availability = model.availability {
                    AIRouteMenu(defaultChoice: settings.aiChoice(for: .chat), override: $model.override,
                                availability: availability, settings: settings, disabled: model.running)
                }
                Spacer(minLength: 4)
                if !model.messages.isEmpty {
                    Button(tr("新しい会話")) { model.clear() }
                        .buttonStyle(.link)
                        .font(.caption)
                        .help(tr("今の会話を消して、新しく始める"))
                }
            }
            Text(privacyNote)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(10)
    }

    // 要件: REQ-MTG-048
    // 設計判断: DEC-MTG-085
    private var privacyNote: String {
        model.effectiveChoice(settings: settings).sendsOutside
            ? tr("文字起こしとメモをこの AI に送ります。会話は保存しません。")
            : tr("この Mac の外には送りません。会話は保存しません。")
    }

    private var canSend: Bool {
        !model.running && !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // 要件: REQ-MTG-047
    /// よく使う質問を押したとき。「何を聞かれた？」はウインドウのチャットを待たずに聞く（DEC-MTG-098）
    private func tap(_ prompt: MeetingChat.QuickPrompt) {
        if prompt.isAsked { onAsked?() } else { send(prompt.question) }
    }

    private func enabled(_ prompt: MeetingChat.QuickPrompt) -> Bool {
        prompt.isAsked ? onAsked != nil && !asked.isRunning(for: model.meetingID) : !model.running
    }

    private func help(for prompt: MeetingChat.QuickPrompt) -> String {
        guard prompt.isAsked else { return prompt.question }
        if let batchEngineName { return MeetingAskedQuestion.unavailableMessage(engine: batchEngineName) }
        return MeetingAskedQuestion.helpText
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
                Text(message.label ?? message.text)
                    .textSelection(.enabled)
                    .help(message.label == nil ? "" : message.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(0.16)))
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Label("AI", systemImage: "sparkles")
                        .font(.caption.bold())
                        .foregroundStyle(.purple)
                    // 要件: REQ-MTG-048（その答えを作った AI とモデル）
                    if let modelLabel = message.modelLabel {
                        Text(modelLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                MarkdownText(markdown: MeetingChat.linkingTimes(in: message.text))
                    .environment(\.openURL, OpenURLAction { url in
                        guard let seconds = MeetingChat.seconds(from: url) else { return .systemAction }
                        onJump(seconds)
                        return .handled
                    })
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    if let covered = message.coveredUntil {
                        Text(tr("%@ までの記録から", "\(Meeting.clock(covered))"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .help(tr("答えを作ったときに渡した記録の範囲（発言 %@ 件）", "\(message.lineCount ?? 0)"))
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
                        Label(copied ? tr("コピーしました") : tr("コピー"), systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .help(tr("答えをコピーする"))
                    if let onSaveNote {
                        Button(action: onSaveNote) {
                            Label(saved ? tr("メモに残しました") : tr("メモに残す"),
                                  systemImage: saved ? "checkmark" : "note.text.badge.plus")
                        }
                        .disabled(saved)
                        .help(tr("この答えをメモに足す（議事録で優先して取り上げます）"))
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
                        onSaveNote: saveNote,
                        // 要件: REQ-MTG-047
                        onAsked: recorder.state == .recording && recorder.batchEngine == nil
                            ? { [recorder] in MeetingAskedQuestion.shared.ask(recorder: recorder, origin: .chat) } : nil)
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
            Text(tr("メモ")).tag(LiveSidePanelMode.notes)
            Text(tr("AI チャット")).tag(LiveSidePanelMode.chat)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help(tr("メモと AI チャットを切り替える（AI チャットは ⌘J）"))
    }
}
