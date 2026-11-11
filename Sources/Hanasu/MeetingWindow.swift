import AppKit
import SwiftUI

// 要件: REQ-MTG-007, REQ-MTG-050, REQ-MTG-051
// 設計判断: DEC-MTG-130
/// 会議ノート: 左に会議の一覧、真ん中に文書（記録中は文字起こし）、後ろ側のパネルに文字起こし・AI チャット（記録中はメモ・AI チャット）。
struct MeetingWindowView: View {
    @ObservedObject var recorder: MeetingRecorder
    /// 一覧の日付のまとまりの基準の日時（確認用の描き出しで固定する。nil なら今）
    var now: Date?
    @State private var selection: String?
    @StateObject private var search = MeetingSearchModel()

    /// initialPanel は確認用の描き出し（CLI）で、発言を選んでいる状態などから描くため
    init(recorder: MeetingRecorder, now: Date? = nil, initialSelection: String? = nil, initialPanel: MeetingPanelState? = nil) {
        self.recorder = recorder
        self.now = now
        _selection = State(initialValue: initialSelection)
        _panel = StateObject(wrappedValue: initialPanel ?? MeetingPanelState())
    }

    @StateObject private var ask = MeetingAskModel()
    /// 検索結果から開いたときの飛び先
    @State private var jump: MeetingJump?
    @State private var showingAsk = false
    /// 削除を確かめている会議
    @State private var pendingDelete: Meeting?
    @State private var deleteError: String?
    /// 録音の削除を確かめている会議と、録音の大きさ（REQ-MTG-055）
    @State private var pendingAudioDelete: (meeting: Meeting, size: Int64)?
    @StateObject private var panel: MeetingPanelState
    @AppStorage("meetingInspectorShown") private var inspectorShown = true

    var body: some View {
        // 修飾子が多いと型の推論が時間切れになるので、分割の画面と後ろ側のパネルは splitView、
        // 一覧・選択・通知を受けるところは observedSplitView に分ける
        observedSplitView
        // 要件: REQ-MTG-028
        // 設計判断: DEC-MTG-022
        .confirmationDialog(pendingDelete.map { tr("「%@」を削除しますか？", "\($0.title)") } ?? "",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            presenting: pendingDelete) { meeting in
            Button(tr("ゴミ箱に入れる"), role: .destructive) { delete(meeting) }
            Button(tr("キャンセル"), role: .cancel) {}
        } message: { _ in
            Text(tr("議事録・文字起こし・メモ・音声をまとめてゴミ箱に移します。ゴミ箱から戻せます。"))
        }
        // 要件: REQ-MTG-055
        // 設計判断: DEC-MTG-140, DEC-MTG-142
        .confirmationDialog(pendingAudioDelete.map { MeetingAudioDeleteText.title(for: $0.meeting) } ?? "",
                            isPresented: Binding(get: { pendingAudioDelete != nil }, set: { if !$0 { pendingAudioDelete = nil } })) {
            Button(tr("削除"), role: .destructive) { deleteAudio() }
            Button(tr("キャンセル"), role: .cancel) {}
        } message: {
            Text(pendingAudioDelete.map { MeetingAudioDeleteText.message(for: $0.meeting, size: $0.size) } ?? "")
        }
        .alert(tr("削除できませんでした"), isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK") {}
        } message: {
            Text(deleteError ?? "")
        }
    }

    /// 一覧・検索・選択の変化と、通知（チャットで続ける・ウインドウを閉じる）を受ける
    private var observedSplitView: some View {
        splitView
        .onReceive(recorder.$meetings) { search.update($0) }
        // 要件: REQ-MTG-049（式が長いと型の推論が時間切れになるので、関数に分ける）
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification), perform: resetAskRoute)
        // 要件: REQ-MTG-047（「チャットで続ける」。式が長いと型の推論が時間切れになるので、関数に分ける）
        .onReceive(MeetingAskedQuestion.shared.$openChatRequest.compactMap { $0 }, perform: openChat)
        .onChange(of: search.isActive) { _, active in
            if !active { jump = nil }  // 検索をやめたら、検索語の色も消す
        }
        .onChange(of: selection) { _, newID in
            if newID != nil { showingAsk = false }
            if newID != jump?.meetingID { jump = nil }
            panel.reset()
        }
        // 設計判断: DEC-MTG-070
        // 記録を始めたら、その会議を選ぶ。処理（記録のあとの処理・議事録の作り直し）が終わっても選び直さない。
        // 記録中の会議と保存した会議は同じ ID なので、記録のあとも選んだ会議のまま、議事録が出る
        .onChange(of: recorder.current?.id) { _, newID in
            if let newID { selection = newID }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if showingAsk {
            MeetingAskView(model: ask, meetings: recorder.meetings, index: search.index) { id in
                showingAsk = false
                selection = id
                jump = nil
            }
        } else if let id = selection, let current = recorder.current, id == current.id {
            if isLive {
                // 要件: REQ-MTG-054
                LiveMeetingView(recorder: recorder, panel: panel)
            } else {
                // 要件: REQ-MTG-054
                // 記録を止めたあとの処理中: 同じ会議のまま、文書（議事録を作成中）にする
                MeetingDetailView(meeting: current, recorder: recorder, panel: panel, processing: true)
            }
        } else if let meeting = selectedMeeting {
            MeetingDetailView(meeting: meeting, recorder: recorder, panel: panel, jump: jump?.meetingID == meeting.id ? jump : nil,
                              onDelete: { confirmDelete(meeting.id) }, onDeleteAudio: { confirmDeleteAudio(meeting.id) })
        } else {
            ContentUnavailableView(tr("会議を選んでください"), systemImage: "waveform",
                                   description: Text(tr("下のボタンか %@ で記録を始められます。", "\(AppSettings.shared.meetingHotKey.displayString)")))
        }
    }

    private var isLive: Bool { recorder.state == .recording || recorder.state == .starting }

    /// 左の一覧・真ん中・後ろ側のパネル
    private var splitView: some View {
        NavigationSplitView {
            // 検索欄・一覧・記録の欄を縦に積む。safeAreaInset で重ねると、一覧が欄の裏に回り込んで透けて見える
            VStack(spacing: 0) {
                MeetingSearchField(model: search) {
                    showingAsk = true
                    selection = nil
                }
                sidebarList
                    .frame(maxHeight: .infinity)
                Divider()
                RecordButton(recorder: recorder)
                    .padding(12)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            detail
        }
        // 設計判断: DEC-MTG-130（後ろ側のパネルは NavigationSplitView に付ける）
        .inspector(isPresented: inspectorBinding) {
            inspector
        }
    }

    // 要件: REQ-MTG-047
    // 設計判断: DEC-MTG-096
    /// 「チャットで続ける」: その会議を選び、後ろ側のパネルを出して AI チャットにし、入力欄にフォーカスを移す
    // 要件: REQ-MTG-049
    // 設計判断: DEC-MTG-150（ウインドウは閉じても残すので、閉じる通知で会議に質問の送り先を既定に戻す）
    private func resetAskRoute(_ note: Notification) {
        guard (note.object as? NSWindow)?.identifier == MeetingPlayer.windowIdentifier else { return }
        ask.override = nil
    }

    private func openChat(_ request: MeetingAskedQuestion.OpenChatRequest) {
        MeetingAskedQuestion.shared.consumeOpenChatRequest(request.id)
        showingAsk = false
        selection = request.meetingID
        inspectorShown = true
        panel.tab = .chat
        UserDefaults.standard.set(LiveSidePanelMode.chat.rawValue, forKey: "meetingLiveSidePanel")
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))  // パネルができてから
            MeetingChatStore.shared.model(for: request.meetingID).requestFocus()
        }
    }

    private var selectedMeeting: Meeting? {
        guard let id = selection else { return nil }
        return recorder.meetings.first { $0.id == id }
    }

    /// 「質問」を開いている間と、会議を選んでいない間は、後ろ側のパネルを出さない
    private var inspectorBinding: Binding<Bool> {
        Binding(get: { inspectorShown && !showingAsk && selection != nil }, set: { inspectorShown = $0 })
    }

    @ViewBuilder
    private var inspector: some View {
        if let id = selection, let current = recorder.current, id == current.id {
            if isLive {
                LiveInspector(recorder: recorder, panel: panel)
            } else {
                MeetingDetailInspector(meeting: current, recorder: recorder, panel: panel, processing: true)
            }
        } else if let meeting = selectedMeeting {
            MeetingDetailInspector(meeting: meeting, recorder: recorder, panel: panel,
                                   highlight: jump?.meetingID == meeting.id ? jump?.terms ?? [] : [])
        }
    }

    /// 会議をゴミ箱に移し、一覧の次の会議（なければ前の会議）を選ぶ
    private func delete(_ meeting: Meeting) {
        let list = MeetingListGrouping.groups(recorder.meetings.filter { $0.id != recorder.current?.id }, now: now ?? Date())
            .flatMap(\.meetings)
        let index = list.firstIndex { $0.id == meeting.id }
        let wasLoaded = MeetingPlayer.shared.meetingID == meeting.id
        if wasLoaded { MeetingPlayer.shared.stop() }
        do {
            try recorder.delete(meeting)
        } catch {
            // 消せなかったら、再生のバーを戻す
            if wasLoaded { MeetingPlayer.shared.load(meeting) }
            deleteError = error.localizedDescription
            return
        }
        MeetingChatStore.shared.remove(meeting.id)
        guard selection == meeting.id || jump?.meetingID == meeting.id else { return }
        jump = nil
        if let index {
            let rest = list.filter { $0.id != meeting.id }
            selection = rest.isEmpty ? nil : rest[min(index, rest.count - 1)].id
        } else {
            selection = nil
        }
    }

    /// 一覧の右クリック・⌫・ツールバーの「…」から削除を確かめる
    private func confirmDelete(_ id: String?) {
        guard let id, let meeting = recorder.meetings.first(where: { $0.id == id }), recorder.canDelete(meeting) else { return }
        pendingDelete = meeting
    }

    // 要件: REQ-MTG-055
    /// 一覧の右クリック・ツールバーの「…」から、録音の削除を確かめる
    private func confirmDeleteAudio(_ id: String?) {
        guard let id, let meeting = recorder.meetings.first(where: { $0.id == id }), recorder.canDeleteAudio(meeting) else { return }
        pendingAudioDelete = (meeting, MeetingStore.audioSize(for: meeting))
    }

    // 要件: REQ-MTG-055
    // 設計判断: DEC-MTG-140（会議は選んだまま。再生のバーは recorder.deleteAudio が止めて読み直す）
    private func deleteAudio() {
        guard let meeting = pendingAudioDelete?.meeting else { return }
        pendingAudioDelete = nil
        let failures = recorder.deleteAudio([meeting])
        if !failures.isEmpty { deleteError = MeetingAudioDeleteText.failureMessage(failures) }
    }

    // 要件: REQ-MTG-051
    // 設計判断: DEC-MTG-138
    /// 左の一覧（検索中は検索結果）。記録中・今日・昨日・今週・先週・月ごとにまとめる
    @ViewBuilder
    private var sidebarList: some View {
        if search.isActive {
            MeetingSearchResultsList(model: search, selectedHitID: selectedHitID) { id, hit in
                showingAsk = false
                selection = id
                jump = MeetingJump(meetingID: id, location: hit?.location, terms: search.terms)
            }
        } else {
            List(selection: $selection) {
                if let current = recorder.current {
                    Section(tr("記録中")) {
                        MeetingRow(meeting: current, live: recorder.state != .idle, busy: isProcessing, style: .time).tag(current.id)
                    }
                }
                ForEach(MeetingListGrouping.groups(recorder.meetings.filter { $0.id != recorder.current?.id }, now: now ?? Date())) { group in
                    Section(group.title) {
                        ForEach(group.meetings) { meeting in
                            MeetingRow(meeting: meeting, live: false, busy: meeting.id == recorder.regeneratingID,
                                       style: MeetingRow.Style(group: group.id))
                                .tag(meeting.id)
                                .contextMenu {
                                    // 要件: REQ-MTG-055, REQ-MTG-056
                                    Button(tr("録音を削除…")) { confirmDeleteAudio(meeting.id) }
                                        .disabled(!recorder.canDeleteAudio(meeting))
                                    Button(tr("録音の管理…")) { MeetingAudioManagerWindow.show() }
                                    Divider()
                                    Button(tr("削除…"), role: .destructive) { confirmDelete(meeting.id) }
                                        .disabled(!recorder.canDelete(meeting))
                                }
                        }
                    }
                }
            }
            .onDeleteCommand { confirmDelete(selection) }
        }
    }

    private var isProcessing: Bool {
        if case .processing = recorder.state { return true }
        return false
    }

    private var selectedHitID: String? {
        guard let jump, let location = jump.location else { return nil }
        return MeetingSearchHit(meetingID: jump.meetingID, location: location, snippet: "").id
    }
}

// MARK: - 一覧の行

// 要件: REQ-MTG-051
struct MeetingRow: View {
    /// 2 行目の日時の書き方（今日・昨日は時刻、今週・先週は曜日と時刻、それより前は日付）
    enum Style {
        case time, weekday, date

        init(group: String) {
            switch group {
            case "today", "yesterday": self = .time
            case "thisWeek", "lastWeek": self = .weekday
            default: self = .date
            }
        }

        var template: String {
            switch self {
            case .time: "jm"
            case .weekday: "EEEjm"
            case .date: "MMMdjm"
            }
        }
    }

    let meeting: Meeting
    let live: Bool
    /// 議事録を作っている（記録のあとの処理か、作り直し）
    var busy = false
    var style: Style = .date

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if busy {
                    // 要件: REQ-MTG-013
                    ProgressView().controlSize(.mini).help(tr("議事録を作っています"))
                        .accessibilityLabel(tr("議事録を作っています"))
                } else if live {
                    Image(systemName: "record.circle.fill").foregroundStyle(.red)
                        .accessibilityLabel(tr("記録中"))
                }
                Text(meeting.title).lineLimit(1)
            }
            HStack(spacing: 4) {
                Text(Self.formatter(style).string(from: meeting.startedAt))
                if meeting.duration > 0 { Text("· " + MeetingFormat.length(meeting.duration)) }
                if busy { Text("· " + tr("議事録を作成中")) }
                if meeting.status == .failed { Text("· " + tr("失敗")).foregroundStyle(.orange) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    private static var formatters: [Style: DateFormatter] = [:]

    private static func formatter(_ style: Style) -> DateFormatter {
        if let formatter = formatters[style] { return formatter }
        let formatter = DateFormatter()
        formatter.locale = UILanguage.locale
        formatter.setLocalizedDateFormatFromTemplate(style.template)
        formatters[style] = formatter
        return formatter
    }
}

// MARK: - 記録のボタン

// 要件: REQ-MTG-001, REQ-MTG-051
/// 一覧の下: 「会議の記録を開始」（記録中は「記録を停止」）と、今の設定の 1 行（押すと設定のパネル）
private struct RecordButton: View {
    @ObservedObject var recorder: MeetingRecorder
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var devices = AudioDeviceList.shared
    @AppStorage(MinutesTemplateStore.templateKey) private var templateID = MinutesTemplate.auto.rawValue
    @AppStorage(SavedMinutesTemplateStore.listKey) private var savedJSON = ""
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 8) {
            switch recorder.state {
            case .idle:
                Button { recorder.toggle() } label: {
                    Label(tr("会議の記録を開始"), systemImage: "record.circle").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            case .starting:
                ProgressView(tr("準備中…")).controlSize(.small)
            case .recording:
                Button { recorder.toggle() } label: {
                    Label(tr("記録を停止"), systemImage: "stop.circle.fill").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(.red)
            case .processing(let message):
                ProgressView(message).controlSize(.small)
            }
            // 設計判断: DEC-MTG-019, DEC-MTG-061
            Button { showingSettings = true } label: {
                HStack(spacing: 4) {
                    Text(summary).lineLimit(1).truncationMode(.middle)
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(tr("記録する機器・議事録の型・録音の扱いを変える（次の記録から）"))
            .accessibilityLabel(tr("記録の設定"))
            .accessibilityValue(summary)
            .popover(isPresented: $showingSettings, arrowEdge: .top) {
                RecordSettingsPopover(recorder: recorder)
            }
            if let error = recorder.lastError {
                Text(error).font(.caption).foregroundStyle(.orange).lineLimit(3)
                    .help(error)
                    .textSelection(.enabled)
            }
        }
    }

    /// 「定例 · Mac 全体の音 · システムのマイク」
    private var summary: String {
        let saved = SavedMinutesTemplateStore.decode(savedJSON)
        let template = SavedMinutesTemplateStore.template(forSelection: templateID, in: saved)?.name
            ?? (MinutesTemplate(rawValue: templateID) ?? .auto).title
        let output = settings.meetingOutputDeviceUID.isEmpty ? tr("Mac 全体の音")
            : devices.outputs.first { $0.uid == settings.meetingOutputDeviceUID }?.name ?? tr("（接続されていない機器）")
        let input = settings.meetingInputDeviceUID.isEmpty ? tr("システムのマイク")
            : devices.inputs.first { $0.uid == settings.meetingInputDeviceUID }?.name ?? tr("（接続されていない機器）")
        // 要件: REQ-MTG-051, REQ-MTG-010（録音を消すのがオンなら足す。記録中・処理中は記録中の会議の値）
        let deletesAudio = recorder.current.map { $0.deleteAudioAfterTranscription == true } ?? !settings.keepMeetingAudio
        return ([template, output, input] + (deletesAudio ? [tr("録音は削除")] : [])).joined(separator: " · ")
    }
}

// 要件: REQ-MTG-051, REQ-MTG-017, REQ-MTG-042
/// 記録の設定のパネル: スピーカー・マイク・議事録の型（記録中・処理中は変えられない。次の記録から）
private struct RecordSettingsPopover: View {
    @ObservedObject var recorder: MeetingRecorder
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("記録の設定")).font(.headline)
            MeetingDevicePickers(compact: true)
            MinutesTemplatePicker()
            // 要件: REQ-MTG-010, REQ-MTG-051
            // 設計判断: DEC-MTG-139（次の記録からの既定。記録中の会議の分は、記録中のツールバーで変える）
            Toggle(tr("文字起こしのあとに録音を削除する"),
                   isOn: Binding(get: { !settings.keepMeetingAudio }, set: { settings.keepMeetingAudio = !$0 }))
            if recorder.state != .idle {
                Text(tr("記録中は変えられません。次の記録から使います。"))
                    .font(.caption).foregroundStyle(.secondary)
                if recorder.state == .recording {
                    Text(tr("この会議の録音の扱いは、記録中のツールバーで変えられます。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .disabled(recorder.state != .idle)
        .padding()
        .frame(width: 300)
    }
}

// MARK: - 記録した会議

// 要件: REQ-MTG-050
// 設計判断: DEC-MTG-130
/// 真ん中（文書・記録中の文字起こし）と後ろ側のパネルで分け合う状態。後ろ側のパネルは会議ノートのウインドウの
/// NavigationSplitView に付ける（真ん中の画面に付けると、左の一覧の幅を 2 回数えた最小の幅になり、最小の大きさで中身がはみ出す）
@MainActor
final class MeetingPanelState: ObservableObject {
    @Published var tab: MeetingInspectorTab {
        didSet { UserDefaults.standard.set(tab.rawValue, forKey: "meetingInspectorTab") }
    }
    @Published var focus: TranscriptFocus?
    /// 議事録に使う発言を選んでいる（DEC-MTG-137）
    @Published var selecting: Bool
    /// 「議事録を作り直す」の確かめ（今の議事録があるときだけ出す。DEC-MTG-072）
    @Published var confirmRegenerate = false
    /// 記録中に AI チャットの答えの時刻を押したときの飛び先
    @Published var liveTimeJump: LiveTranscriptView.TimeJump?

    init(tab: MeetingInspectorTab? = nil, selecting: Bool = false) {
        self.tab = tab ?? UserDefaults.standard.string(forKey: "meetingInspectorTab").flatMap(MeetingInspectorTab.init(rawValue:)) ?? .transcript
        self.selecting = selecting
    }


    /// 別の会議を選んだとき
    func reset() {
        focus = nil
        selecting = false
        confirmRegenerate = false
    }
}

// 要件: REQ-MTG-050, REQ-MTG-052, REQ-MTG-053
// 設計判断: DEC-MTG-130, DEC-MTG-131, DEC-MTG-137
/// 記録した会議の画面: 真ん中の文書（下に再生のバー）とツールバーの操作。後ろ側のパネル（文字起こし・AI チャット）は
/// 会議ノートのウインドウが付ける（embedsInspector が true なら自分で付ける。確認用の描き出し（CLI）が単独で描くとき）。
/// 記録を止めたあとの処理中（processing）も同じ画面にする
struct MeetingDetailView: View {
    let meeting: Meeting
    @ObservedObject var recorder: MeetingRecorder
    @ObservedObject var panel: MeetingPanelState
    var processing = false
    /// 検索結果から開いたときの飛び先（議事録の行は文書へ、発言は後ろ側のパネルへ）
    var jump: MeetingJump?
    var embedsInspector = true
    /// 削除の確かめを出す（会議ノートのウインドウが持つ）。nil なら削除を出さない
    var onDelete: (() -> Void)?
    /// 録音の削除の確かめを出す（REQ-MTG-055）。nil なら出さない
    var onDeleteAudio: (() -> Void)?
    @AppStorage("meetingInspectorShown") private var inspectorShown = true
    @State private var editingSpeakers = false

    /// 文書の最小の幅（DEC-MTG-130）。文書に minWidth は付けず、ウインドウの最小の大きさで確保する
    static let documentMinWidth: CGFloat = 400

    init(meeting: Meeting, recorder: MeetingRecorder, panel: MeetingPanelState, processing: Bool = false,
         jump: MeetingJump? = nil, embedsInspector: Bool = false, onDelete: (() -> Void)? = nil, onDeleteAudio: (() -> Void)? = nil) {
        self.meeting = meeting
        self.recorder = recorder
        self.panel = panel
        self.processing = processing
        self.jump = jump
        self.embedsInspector = embedsInspector
        self.onDelete = onDelete
        self.onDeleteAudio = onDeleteAudio
    }

    /// 確認用の描き出し（CLI）: 後ろ側のパネルも自分で付ける。initialTab が 4 なら AI チャット、ほかは文字起こし。
    /// initialSelecting なら、文字起こしのチェックボックスを出した状態で開く
    init(meeting: Meeting, recorder: MeetingRecorder, processing: Bool = false, jump: MeetingJump? = nil,
         initialTab: Int? = nil, initialSelecting: Bool = false, onDelete: (() -> Void)? = nil) {
        self.init(meeting: meeting, recorder: recorder,
                  panel: MeetingPanelState(tab: initialTab.map { $0 == 4 ? .chat : .transcript }, selecting: initialSelecting),
                  processing: processing, jump: jump, embedsInspector: true, onDelete: onDelete)
    }

    var body: some View {
        withDialogs(withInspector(document))
            .toolbar { toolbar }
            .onAppear { applyJump(jump) }
            .onChange(of: jump) { _, newJump in applyJump(newJump) }
    }

    /// 真ん中の文書と、下の再生のバー
    private var document: some View {
        MeetingDocumentView(meeting: meeting, recorder: recorder, processing: processing, jump: jump,
                            onFocusTranscript: focusTranscript, onRegenerate: requestRegenerate,
                            onEditSpeakers: { editingSpeakers = true })
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // 要件: REQ-MTG-053
                MeetingPlayerBar(meeting: meeting, recorder: recorder, busy: processing || recorder.regeneratingID == meeting.id)
            }
            // 左右に並べる画面が、文書の理想の幅（議事録の長い行の幅）を最小の幅として求めないようにする
            .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity)
    }

    @ViewBuilder
    private func withInspector(_ content: some View) -> some View {
        if embedsInspector {
            content.inspector(isPresented: $inspectorShown) {
                MeetingDetailInspector(meeting: meeting, recorder: recorder, panel: panel, processing: processing,
                                       highlight: jump?.terms ?? [])
            }
        } else {
            content
        }
    }

    private func withDialogs(_ content: some View) -> some View {
        content
            // 設計判断: DEC-MTG-072
            .confirmationDialog(tr("議事録を作り直しますか？"), isPresented: $panel.confirmRegenerate) {
                Button(tr("作り直す")) { Task { await recorder.regenerateMinutes(meeting) } }
                Button(tr("キャンセル"), role: .cancel) {}
            } message: {
                Text(tr("今の議事録とアクションアイテムは置き換わります。"))
            }
            .sheet(isPresented: $editingSpeakers) {
                SpeakerNamesSheet(meeting: meeting, recorder: recorder)
            }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        // 設計判断: DEC-MTG-131
        ToolbarItemGroup(placement: .primaryAction) {
            MinutesTemplateMenu(meeting: meeting, recorder: recorder)
            Button(action: requestRegenerate) {
                Label(tr("議事録を作り直す"), systemImage: "arrow.clockwise")
            }
            .help(tr("議事録を作り直す"))
            .disabled(processing || recorder.state != .idle || meeting.usedUtterances.isEmpty)
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItemGroup(placement: .primaryAction) {
            // 要件: REQ-DIC-072, REQ-DIC-074
            MeetingDictionaryMenu(meeting: meeting, recorder: recorder)
                .disabled(processing)
            MeetingExportMenu(meeting: meeting, recorder: recorder)
                .disabled(processing)
            MeetingMoreMenu(meeting: meeting, recorder: recorder, processing: processing,
                            onEditSpeakers: { editingSpeakers = true }, onDelete: onDelete, onDeleteAudio: onDeleteAudio)
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) {
            InspectorToggle(shown: $inspectorShown)
        }
    }

    private func requestRegenerate() {
        MeetingDetailView.requestRegenerate(meeting, recorder: recorder, panel: panel, processing: processing)
    }

    // 設計判断: DEC-MTG-072
    /// 議事録を作り直す。今の議事録があるときだけ確かめる（置き換わるため）。まだないときは、そのまま作る
    static func requestRegenerate(_ meeting: Meeting, recorder: MeetingRecorder, panel: MeetingPanelState, processing: Bool) {
        guard recorder.state == .idle, !processing else { return }
        if meeting.minutes == nil {
            Task { await recorder.regenerateMinutes(meeting) }
        } else {
            panel.confirmRegenerate = true
        }
    }

    // 要件: REQ-MTG-052
    // 設計判断: DEC-MTG-084
    /// 文字起こしのその位置へ（パネルが隠れていれば出し、文字起こしに切り替える）
    private func focusTranscript(_ target: TranscriptFocus.Target) {
        inspectorShown = true
        panel.tab = .transcript
        panel.focus = TranscriptFocus(target: target)
    }

    /// 検索でヒットした発言は、後ろ側のパネルで移る（議事録の行は文書が移る）
    private func applyJump(_ jump: MeetingJump?) {
        guard let jump, jump.meetingID == meeting.id, case .transcript(let blockID, _, _) = jump.location else { return }
        focusTranscript(.block(blockID))
    }
}

// 要件: REQ-MTG-050
// 設計判断: DEC-MTG-130, DEC-MTG-137
/// 記録した会議の後ろ側のパネル（幅の決まりつき）
struct MeetingDetailInspector: View {
    let meeting: Meeting
    @ObservedObject var recorder: MeetingRecorder
    @ObservedObject var panel: MeetingPanelState
    var processing = false
    var highlight: [String] = []
    @AppStorage("meetingInspectorShown") private var inspectorShown = true

    var body: some View {
        MeetingInspector(meeting: meeting, recorder: recorder, tab: $panel.tab, focus: panel.focus, selecting: $panel.selecting,
                         highlight: highlight, processing: processing,
                         onRegenerate: {
                             MeetingDetailView.requestRegenerate(meeting, recorder: recorder, panel: panel, processing: processing)
                         },
                         onChatJump: { seconds in
                             panel.tab = .transcript
                             panel.focus = TranscriptFocus(target: .time(seconds))
                         })
            // 設計判断: DEC-MTG-130, DEC-MTG-137（発言を選ぶ間も幅は変えない。広げたいときはドラッグで広げる）
            .inspectorColumnWidth(min: 300, ideal: 360, max: 560)
    }
}

// 要件: REQ-MTG-008, REQ-MTG-028, REQ-MTG-055, REQ-MTG-056
// 設計判断: DEC-MTG-131, DEC-MTG-022
/// ツールバーの「…」: 話者名・Finder で表示・録音を削除・録音の管理・削除
struct MeetingMoreMenu: View {
    let meeting: Meeting
    @ObservedObject var recorder: MeetingRecorder
    var processing = false
    var onEditSpeakers: () -> Void
    var onDelete: (() -> Void)?
    var onDeleteAudio: (() -> Void)?

    var body: some View {
        Menu {
            MeetingMoreMenuItems(meeting: meeting, recorder: recorder, processing: processing,
                                 onEditSpeakers: onEditSpeakers, onDelete: onDelete, onDeleteAudio: onDeleteAudio)
        } label: {
            Label(tr("その他"), systemImage: "ellipsis")
        }
        .help(tr("話者名・Finder で表示・録音・削除"))
    }
}

/// 「…」のメニューの中身（確認用の描き出しでも並べる）
struct MeetingMoreMenuItems: View {
    let meeting: Meeting
    @ObservedObject var recorder: MeetingRecorder
    var processing = false
    var onEditSpeakers: () -> Void
    var onDelete: (() -> Void)?
    var onDeleteAudio: (() -> Void)?
    /// 確認用の描き出しで、録音があるかを差し替える（nil ならファイルで決める）
    var hasAudioOverride: Bool?

    var body: some View {
        Button(tr("話者名…"), action: onEditSpeakers)
            .disabled(processing || meeting.speakers.isEmpty)
        Button(tr("Finder で表示")) {
            NSWorkspace.shared.activateFileViewerSelecting([MeetingStore.directory(for: meeting)])
        }
        if let onDeleteAudio {
            Divider()
            // 要件: REQ-MTG-055
            // 設計判断: DEC-MTG-140（録音があるかはファイルで決め、消したら recorder.audioRevision で描き直す）
            let _ = recorder.audioRevision
            let reason = hasAudioOverride.map { $0 ? nil : tr("この会議には録音が残っていません") }
                ?? (processing ? tr("記録中・処理中は録音を削除できません") : MeetingAudioDeleteText.disabledReason(meeting, recorder: recorder))
            Button(tr("録音を削除…"), action: onDeleteAudio)
                .disabled(reason != nil)
                .help(reason ?? tr("この会議の録音だけを削除する（議事録・文字起こしは残る）"))
            // 要件: REQ-MTG-056
            Button(tr("録音の管理…")) { MeetingAudioManagerWindow.show() }
        }
        if let onDelete {
            Divider()
            // 要件: REQ-MTG-028
            Button(tr("削除…"), role: .destructive, action: onDelete)
                .disabled(!recorder.canDelete(meeting))
                .help(recorder.canDelete(meeting) ? tr("この会議をゴミ箱に入れる") : tr("議事録を作り直している間は削除できません"))
        }
    }
}

// 設計判断: DEC-MTG-130
/// 後ろ側のパネルの表示の切り替え（⌥⌘I）
struct InspectorToggle: View {
    @Binding var shown: Bool

    var body: some View {
        Button { shown.toggle() } label: {
            Label(shown ? tr("インスペクタを隠す") : tr("インスペクタを表示"), systemImage: "sidebar.trailing")
        }
        .keyboardShortcut("i", modifiers: [.command, .option])
        .help(shown ? tr("インスペクタを隠す（⌥⌘I）") : tr("インスペクタを表示（⌥⌘I）"))
    }
}

// MARK: - 記録中

// 要件: REQ-MTG-003, REQ-MTG-040, REQ-MTG-054
// 設計判断: DEC-MTG-080, DEC-MTG-130
/// 記録中の画面: 真ん中に文字起こし、後ろ側のパネルに「メモ｜AI チャット」、ツールバーに記録中の印・音量・オフレコ・字幕
struct LiveMeetingView: View {
    @ObservedObject var recorder: MeetingRecorder
    @ObservedObject var panel: MeetingPanelState
    /// 確認用の描き出しで単独で描くときは、後ろ側のパネルも自分で付ける
    var embedsInspector = false
    @AppStorage("meetingInspectorShown") private var inspectorShown = true

    var body: some View {
        content
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    LiveRecordingPill(recorder: recorder)
                    LiveLevelMeters(recorder: recorder)
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    // 要件: REQ-MTG-046
                    LiveOffRecordButton(recorder: recorder)
                    // 要件: REQ-MTG-014
                    MeetingCaptionToggle(recorder: recorder)
                    // 要件: REQ-MTG-010, REQ-MTG-054
                    LiveDeleteAudioToggle(recorder: recorder)
                }
                ToolbarSpacer(.fixed, placement: .primaryAction)
                ToolbarItem(placement: .primaryAction) {
                    InspectorToggle(shown: $inspectorShown)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if embedsInspector {
            LiveTranscriptView(recorder: recorder, timeJump: panel.liveTimeJump)
                .inspector(isPresented: $inspectorShown) { LiveInspector(recorder: recorder, panel: panel) }
        } else {
            LiveTranscriptView(recorder: recorder, timeJump: panel.liveTimeJump)
        }
    }
}

// 要件: REQ-MTG-040
// 設計判断: DEC-MTG-080
/// 記録中の後ろ側のパネル（メモ｜AI チャット）
struct LiveInspector: View {
    @ObservedObject var recorder: MeetingRecorder
    @ObservedObject var panel: MeetingPanelState
    /// 右側に出すもの（メモか AI チャット）。次の記録でも同じものを出す
    @AppStorage("meetingLiveSidePanel") private var sideMode: LiveSidePanelMode = .notes

    var body: some View {
        Group {
            if let id = recorder.current?.id {
                LiveSidePanel(recorder: recorder, chat: MeetingChatStore.shared.model(for: id), mode: $sideMode) { seconds in
                    panel.liveTimeJump = LiveTranscriptView.TimeJump(seconds: seconds)
                }
            } else {
                LiveNotesPanel(recorder: recorder)
            }
        }
        .inspectorColumnWidth(min: 300, ideal: 340, max: 520)
    }
}

/// ツールバーの「● 記録中 07:00」
struct LiveRecordingPill: View {
    @ObservedObject var recorder: MeetingRecorder

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "record.circle.fill").foregroundStyle(.red)
            Text(tr("記録中")).fontWeight(.semibold)
            if let start = recorder.current?.startedAt {
                // 設計判断: DEC-MTG-089（スリープしていた時間は数えない）
                TimelineView(.periodic(from: start, by: 1)) { _ in
                    Text(Meeting.clock(recorder.elapsed))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 8)
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

/// ツールバーの自分と相手の音量
struct LiveLevelMeters: View {
    // 設計判断: DEC-MTG-151（0.25 秒ごとに変わる音量は、これだけが見る）
    @ObservedObject private var signals: MeetingLiveSignals

    init(recorder: MeetingRecorder) {
        signals = recorder.signals
    }

    var body: some View {
        HStack(spacing: 12) {
            LevelMeter(label: tr("自分"), level: signals.meLevel, color: .accentColor)
            LevelMeter(label: tr("相手"), level: signals.othersLevel, color: .orange)
        }
        .padding(.horizontal, 6)
        .fixedSize()
    }
}

// 要件: REQ-MTG-003
// 設計判断: DEC-MTG-151（話すたびに変わる途中結果は、これだけが見る）
/// 記録中の文字起こしの末尾の、確定前の途中結果（薄く出す）
struct LiveVolatileLines: View {
    @ObservedObject var signals: MeetingLiveSignals

    var body: some View {
        if !signals.volatileOthers.isEmpty {
            TranscriptLine(time: nil, speaker: tr("相手"), color: .orange, text: signals.volatileOthers)
                .opacity(0.5)
        }
        if !signals.volatileMe.isEmpty {
            TranscriptLine(time: nil, speaker: tr("自分"), color: .accentColor, text: signals.volatileMe)
                .opacity(0.5)
        }
    }
}

// 設計判断: DEC-MTG-151
/// まだ確定した発言がないときの案内。途中結果が出たら消す
struct LiveTranscriptPlaceholder: View {
    @ObservedObject var signals: MeetingLiveSignals

    var body: some View {
        if signals.volatileIsEmpty {
            Text(tr("話し始めると、ここに文字起こしが出ます"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

// 要件: REQ-MTG-003, REQ-MTG-054
/// 記録中の真ん中: 見出し、警告とオフレコの帯、リアルタイムの文字起こし
struct LiveTranscriptView: View {
    @ObservedObject var recorder: MeetingRecorder
    /// AI チャットの答えの時刻を押したときの飛び先
    var timeJump: TimeJump?
    /// 新しい発言が来たら下までスクロールするか（AI チャットの答えの時刻から前の発言へ移ったら止める）
    @State private var followLatest = true
    /// AI チャットの答えの時刻から移った発言
    @State private var focusedLine: UUID?

    /// 答えの時刻を押したときの飛び先（同じ時刻をもう一度押しても移るように、押すたびに token を変える）
    struct TimeJump: Equatable {
        var seconds: Double
        var token = UUID()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(recorder.current?.title ?? "")
                    .font(.title2.bold())
                    .lineLimit(1)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 10)
            // 要件: REQ-MTG-054
            // 設計判断: DEC-MTG-132, DEC-MTG-020（音が入らないチャンネルの警告とオフレコ中の知らせは、文字起こしの上の帯）
            if !recorder.warnings.isEmpty || recorder.openOffRecord != nil {
                VStack(spacing: 8) {
                    ForEach(recorder.warnings.prefix(2), id: \.self) { warning in
                        StatusBanner(style: .warning, systemImage: "exclamationmark.triangle.fill", title: warning)
                    }
                    LiveOffRecordBanner(recorder: recorder)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 10)
            }
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if let engine = recorder.batchEngine {
                            // Whisper / Gemini では、記録中は文字起こししない
                            Label(tr("文字起こしは、記録を止めたあとに %@ で行います。記録中はここに文字が出ません。", "\(engine.shortName)"),
                                  systemImage: "waveform")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else if recorder.liveLines.isEmpty {
                            LiveTranscriptPlaceholder(signals: recorder.signals)
                        }
                        ForEach(recorder.liveLines) { line in
                            TranscriptLine(time: line.start, speaker: line.channel == .me ? tr("自分") : tr("相手"),
                                           color: line.channel == .me ? .accentColor : .orange, text: line.text,
                                           focused: line.id == focusedLine,
                                           use: recorder.current?.isOffRecord(at: line.start) == true ? .offRecord : .used)
                                .id(line.id)
                        }
                        LiveVolatileLines(signals: recorder.signals)
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .font(.body)
                    .textSelection(.enabled)
                }
                .onChange(of: recorder.liveLines.count) {
                    if followLatest { proxy.scrollTo("bottom") }
                }
                // 新しい記録では、また下までスクロールする
                .onChange(of: recorder.current?.id) {
                    followLatest = true
                    focusedLine = nil
                }
                // 設計判断: DEC-MTG-084
                // AI チャットの答えの時刻を押したら、その時刻の発言へ移り、新しい発言が来ても下へ戻らない
                .onChange(of: timeJump) { _, jump in
                    guard let jump, let index = MeetingChat.lineIndex(
                        at: jump.seconds, starts: recorder.liveLines.map(\.start)) else { return }
                    let id = recorder.liveLines[index].id
                    followLatest = false
                    focusedLine = id
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                }
                .overlay(alignment: .bottom) {
                    if !followLatest {
                        Button {
                            followLatest = true
                            focusedLine = nil
                            withAnimation { proxy.scrollTo("bottom") }
                        } label: {
                            Label(tr("最新の発言へ"), systemImage: "arrow.down")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .clipShape(Capsule())
                        .padding(.bottom, 10)
                        .shadow(radius: 2)
                    }
                }
            }
        }
    }

    private var subtitle: String {
        let start = recorder.current.map { Meeting.dateFormatter.string(from: $0.startedAt) } ?? ""
        return tr("%@ から · 話者の区別（話者1・話者2…）は記録を止めたあとに行います", start)
    }
}

/// 音量の簡易メーター（RMS を dB にして 0〜1 に並べる）
private struct LevelMeter: View {
    let label: String
    let level: Float
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(color).frame(width: geo.size.width * normalized)
                }
            }
            .frame(width: 56, height: 6)
            .animation(.linear(duration: 0.2), value: normalized)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("%@の音量", "\(label)"))
        .accessibilityValue("\(Int(normalized * 100))%")
    }

    private var normalized: CGFloat {
        guard level > 0 else { return 0 }
        let db = 20 * log10(Double(level))  // -60 dB 〜 0 dB を 0〜1 に
        return CGFloat(min(1, max(0, (db + 60) / 60)))
    }
}
