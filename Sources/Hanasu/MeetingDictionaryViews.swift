import SwiftUI

// 要件: REQ-DIC-072, REQ-DIC-074
// 設計判断: DEC-DIC-171
/// 会議ノートの詳細の上に置く「辞書」のメニュー。この会議から候補を探す・今の辞書を当て直す・認識したままの文に戻す
struct MeetingDictionaryMenu: View {
    let meeting: Meeting
    @ObservedObject var recorder: MeetingRecorder
    @State private var showingSheet = false
    /// 候補の画面を閉じたあとに出す知らせ（閉じ終わってから出す）
    @State private var pendingMessage: String?
    @State private var message: String?

    var body: some View {
        // 上のボタンの並びは窓の最小幅（詳細は約 640）で詰まるので、削除のボタンと同じくアイコンだけにし、名前はヘルプに出す
        Menu {
            Button(tr("この会議から辞書の候補を探す…")) { showingSheet = true }
            Button(tr("今の辞書をこの会議に当て直す")) {
                message = Self.message(recorder.applyDictionary(to: meeting), reverted: false)
            }
            Button(tr("この会議を認識したままの文に戻す")) {
                message = Self.message(recorder.revertDictionary(of: meeting), reverted: true)
            }
            .disabled(MeetingDictionary.replacedCount(meeting) == 0)
        } label: {
            Label(tr("辞書"), systemImage: "character.book.closed")
        }
        .labelStyle(.iconOnly)
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(tr("辞書"))
        .accessibilityLabel(tr("辞書"))
        .disabled(!recorder.canApplyDictionary(meeting))
        .sheet(isPresented: $showingSheet, onDismiss: {
            message = pendingMessage
            pendingMessage = nil
        }) {
            MeetingDictionarySheet(meeting: meeting, recorder: recorder, settings: .shared) { pendingMessage = $0 }
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") {}
        }
    }

    // 要件: REQ-DIC-074
    /// 当て直し・戻しの結果の知らせ
    static func message(_ result: Result<MeetingDictionary.Outcome, MeetingDictionaryError>, reverted: Bool) -> String {
        switch result {
        case .failure(let error):
            return error.message
        case .success(let outcome):
            if reverted { return tr("認識したままの文に戻し、%@ 件の発言が変わりました。", "\(outcome.changed)") }
            if outcome.changed > 0 { return tr("当て直して、%@ 件の発言が変わりました。", "\(outcome.changed)") }
            return tr("当て直しました。変わった発言はありませんでした（辞書で置き換えてある発言: %@ 件）。", "\(outcome.replaced)")
        }
    }
}

// 要件: REQ-DIC-072
// 設計判断: DEC-DIC-087, DEC-DIC-170, DEC-DIC-171
/// 会議 1 件から辞書の候補を探す画面（シート）。開いたらすぐ探し、選んだものだけを辞書に足す
struct MeetingDictionarySheet: View {
    enum Phase: Equatable {
        case searching
        case results([DictionaryCandidate])
        case failed(String)
    }

    let meeting: Meeting
    @ObservedObject var recorder: MeetingRecorder
    @ObservedObject var settings: AppSettings
    /// 追加して閉じたときの知らせ（閉じたあとでメニューが出す）
    var onFinish: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase
    @State private var selected: Set<UUID>
    @State private var applyToMeeting: Bool
    /// 文字起こしを切ったときの「最初の約 N 分」
    @State private var readMinutes: Int?
    @State private var model = ""
    @State private var task: Task<Void, Never>?
    /// 見た目の確認（--render-meeting-dictionary）では探さない
    private let preview: Bool

    init(meeting: Meeting, recorder: MeetingRecorder, settings: AppSettings,
         preview: (phase: Phase, selected: Set<UUID>, readMinutes: Int?)? = nil,
         onFinish: @escaping (String) -> Void) {
        self.meeting = meeting
        self.recorder = recorder
        self.settings = settings
        self.onFinish = onFinish
        self.preview = preview != nil
        _phase = State(initialValue: preview?.phase ?? .searching)
        _selected = State(initialValue: preview?.selected ?? [])
        _readMinutes = State(initialValue: preview?.readMinutes)
        // 既定は、新しい会議に当てる設定と同じ（DEC-DIC-171、REQ-DIC-072）
        _applyToMeeting = State(initialValue: settings.applyDictionaryToMeetings)
    }

    private var candidates: [DictionaryCandidate] {
        if case .results(let found) = phase { return found }
        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("この会議から辞書の候補を探す")).font(.headline)
            Text(meeting.title).foregroundStyle(.secondary).lineLimit(1)
            Divider()
            content
                .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
            if let readMinutes {
                Label(tr("会議が長いので、文字起こしの最初の約 %@ 分だけを読みました。", "\(readMinutes)"),
                      systemImage: "scissors")
                    .font(.caption).foregroundStyle(.orange)
            }
            Divider()
            Toggle(tr("この会議の文字起こしにも辞書を当てる"), isOn: $applyToMeeting)
                .toggleStyle(.checkbox)
            Text(tr("固有名詞や誤認識しやすい語を、この会議の文字起こしと議事録から AI が挙げます。選んだものだけを辞書に追加します。会議の中身は、設定の「AI」で会議に選んだ AI にだけ渡します（「ローカル」か「Apple」なら、この Mac の外には送りません）。"))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(tr("キャンセル"), role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button(tr("選んだ %@ 件を辞書に追加", "\(selected.count)"), action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 540)
        .onAppear { if !preview { search() } }
        .onDisappear { task?.cancel() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .searching:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(tr("探しています…"))
            }
        case .failed(let message):
            Text("⚠️ " + message).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
        case .results(let found) where found.isEmpty:
            Text(tr("新しい候補は見つかりませんでした。")).foregroundStyle(.secondary)
        case .results(let found):
            VStack(alignment: .leading, spacing: 6) {
                Text(model.isEmpty ? tr("追加したいものを選んでください。") : tr("追加したいものを選んでください（%@）。", model))
                    .font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(found) { candidate in
                            DictionaryCandidateRow(candidate: candidate, isOn: binding(for: candidate))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 320)
                .accessibilityLabel(tr("辞書の候補"))
            }
        }
    }

    private func binding(for candidate: DictionaryCandidate) -> Binding<Bool> {
        Binding(
            get: { selected.contains(candidate.id) },
            set: { if $0 { selected.insert(candidate.id) } else { selected.remove(candidate.id) } })
    }

    // 設計判断: DEC-DIC-170
    private func search() {
        // 一覧の最新の会議を読む（話者名や議事録を直した直後でも、それを材料にする）
        let source = recorder.meetings.first { $0.id == meeting.id } ?? meeting
        phase = .searching
        task = Task {
            do {
                // 要件: REQ-COM-032
                try await LocalModelDownloadPrompt.prepare(
                    for: .meeting, settings: settings, work: tr("辞書の候補探し"), whenSkipped: tr("候補は探しません"))
                // 辞書の候補探しは会議の記録を読む長い処理なので、会議の AI を使う（DEC-COM-040）
                let client = try TextAIClient.requireFromSettings(settings, for: .meeting)
                let existing = settings.userDictionary
                let material = DictionarySuggester.meetingMaterial(
                    source, budget: DictionarySuggester.budget(for: client, existing: existing))
                let modelName = settings.textModel(for: .meeting)
                let found = try await DictionarySuggester.suggest(
                    material: material.text, existing: existing, client: client, model: modelName)
                try Task.checkCancellation()
                model = modelName
                readMinutes = material.readMinutes
                phase = .results(found)
            } catch is CancellationError {
                // 閉じたので何もしない
            } catch {
                if !Task.isCancelled { phase = .failed(error.localizedDescription) }
            }
        }
    }

    private func cancel() {
        task?.cancel()
        dismiss()
    }

    // 設計判断: DEC-DIC-087, DEC-DIC-174
    private func add() {
        let chosen = candidates.filter { selected.contains($0.id) }
        guard !chosen.isEmpty else { return }
        task?.cancel()
        settings.dictionaryText = DictionarySuggester.appending(chosen, to: settings.dictionaryText)
        var messages = [tr("%@ 件を辞書に追加しました。", "\(chosen.count)")]
        if applyToMeeting {
            messages.append(MeetingDictionaryMenu.message(recorder.applyDictionary(to: meeting), reverted: false))
        }
        onFinish(messages.joined(separator: "\n"))
        dismiss()
    }
}
