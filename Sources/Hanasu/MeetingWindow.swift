import AppKit
import SwiftUI

// 要件: REQ-MTG-007
/// 会議ノート: 記録した会議の一覧と、議事録・文字起こしの表示。
struct MeetingWindowView: View {
    @ObservedObject var recorder: MeetingRecorder
    @State private var selection: String?
    @StateObject private var search = MeetingSearchModel()
    @StateObject private var ask = MeetingAskModel()
    /// 検索結果から開いたときの飛び先
    @State private var jump: MeetingJump?
    @State private var showingAsk = false
    /// 削除を確かめている会議
    @State private var pendingDelete: Meeting?
    @State private var deleteError: String?

    var body: some View {
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
                    .padding(10)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            if showingAsk {
                MeetingAskView(model: ask, meetings: recorder.meetings, index: search.index) { id in
                    showingAsk = false
                    selection = id
                    jump = nil
                }
            } else if let id = selection, id == recorder.current?.id {
                LiveTranscriptView(recorder: recorder)
            } else if let id = selection, let meeting = recorder.meetings.first(where: { $0.id == id }) {
                MeetingDetailView(meeting: meeting, recorder: recorder, jump: jump?.meetingID == id ? jump : nil,
                                  onDelete: { pendingDelete = meeting })
            } else {
                ContentUnavailableView("会議を選んでください", systemImage: "waveform",
                                       description: Text("下のボタンか ⌃⌥⌘M で記録を始められます。"))
            }
        }
        .frame(minWidth: 900, minHeight: 520)
        .onReceive(recorder.$meetings) { search.update($0) }
        .onChange(of: search.isActive) { _, active in
            if !active { jump = nil }  // 検索をやめたら、検索語の色も消す
        }
        .onChange(of: selection) { _, newID in
            if newID != nil { showingAsk = false }
            if newID != jump?.meetingID { jump = nil }
        }
        // 設計判断: DEC-MTG-070
        // 記録を始めたら、その会議を選ぶ。処理（記録のあとの処理・議事録の作り直し）が終わっても選び直さない。
        // 記録中の会議と保存した会議は同じ ID なので、記録のあとも選んだ会議のまま、議事録が出る
        .onChange(of: recorder.current?.id) { _, newID in
            if let newID { selection = newID }
        }
        // 要件: REQ-MTG-028
        // 設計判断: DEC-MTG-022
        .confirmationDialog(pendingDelete.map { "「\($0.title)」を削除しますか？" } ?? "",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            presenting: pendingDelete) { meeting in
            Button("ゴミ箱に入れる", role: .destructive) { delete(meeting) }
            Button("キャンセル", role: .cancel) {}
        } message: { _ in
            Text("議事録・文字起こし・メモ・音声をまとめてゴミ箱に移します。ゴミ箱から戻せます。")
        }
        .alert("削除できませんでした", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK") {}
        } message: {
            Text(deleteError ?? "")
        }
    }

    /// 会議をゴミ箱に移し、一覧の次の会議（なければ前の会議）を選ぶ
    private func delete(_ meeting: Meeting) {
        let list = recorder.meetings.filter { $0.id != recorder.current?.id }
        let index = list.firstIndex { $0.id == meeting.id }
        do {
            try recorder.delete(meeting)
        } catch {
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

    /// 一覧の右クリック・⌫ から削除を確かめる
    private func confirmDelete(_ id: String?) {
        guard let id, let meeting = recorder.meetings.first(where: { $0.id == id }), recorder.canDelete(meeting) else { return }
        pendingDelete = meeting
    }

    /// 左の一覧（検索中は検索結果）
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
                    Section("記録中") {
                        MeetingRow(meeting: current, live: true, busy: isProcessing).tag(current.id)
                    }
                }
                Section("会議") {
                    ForEach(recorder.meetings.filter { $0.id != recorder.current?.id }) { meeting in
                        MeetingRow(meeting: meeting, live: false, busy: meeting.id == recorder.regeneratingID)
                            .tag(meeting.id)
                            .contextMenu {
                                Button("削除…", role: .destructive) { confirmDelete(meeting.id) }
                                    .disabled(!recorder.canDelete(meeting))
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

private struct MeetingRow: View {
    let meeting: Meeting
    let live: Bool
    /// 議事録を作っている（記録のあとの処理か、作り直し）
    var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if busy {
                    // 要件: REQ-MTG-013
                    ProgressView().controlSize(.mini).help("議事録を作っています")
                } else if live {
                    Image(systemName: "record.circle.fill").foregroundStyle(.red)
                }
                Text(meeting.title).lineLimit(1)
            }
            HStack(spacing: 6) {
                Text(Meeting.dateFormatter.string(from: meeting.startedAt))
                if meeting.duration > 0 { Text(Meeting.clock(meeting.duration)) }
                if meeting.status == .failed { Text("失敗").foregroundStyle(.orange) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct RecordButton: View {
    @ObservedObject var recorder: MeetingRecorder

    var body: some View {
        VStack(spacing: 10) {
            // 録音する機器（記録中は変えられない。次の記録から反映）
            MeetingDevicePickers(compact: true)
                .disabled(recorder.state != .idle)
            MinutesTemplatePicker()
                .disabled(recorder.state != .idle)
            switch recorder.state {
            case .idle:
                Button { recorder.toggle() } label: {
                    Label("会議の記録を開始", systemImage: "record.circle").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            case .starting:
                ProgressView("準備中…").controlSize(.small)
            case .recording:
                Button { recorder.toggle() } label: {
                    Label("記録を停止", systemImage: "stop.circle.fill").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(.red)
            case .processing(let message):
                ProgressView(message).controlSize(.small)
            }
            if let error = recorder.lastError {
                Text(error).font(.caption).foregroundStyle(.orange).lineLimit(3)
            }
        }
    }
}

// 要件: REQ-MTG-003
struct LiveTranscriptView: View {
    @ObservedObject var recorder: MeetingRecorder
    // 設計判断: DEC-MTG-080
    /// 右側に出すもの（メモか AI チャット）。次の記録でも同じものを出す
    @AppStorage("meetingLiveSidePanel") private var sideMode: LiveSidePanelMode = .notes
    /// 新しい発言が来たら下までスクロールするか（AI チャットの答えの時刻から前の発言へ移ったら止める）
    @State private var followLatest = true
    /// AI チャットの答えの時刻から移った発言
    @State private var focusedLine: UUID?
    @State private var timeJump: TimeJump?

    /// 答えの時刻を押したときの飛び先（同じ時刻をもう一度押しても移るように、押すたびに token を変える）
    struct TimeJump: Equatable {
        var seconds: Double
        var token = UUID()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "record.circle.fill").foregroundStyle(.red)
                Text("記録中").font(.headline)
                if let start = recorder.current?.startedAt {
                    TimelineView(.periodic(from: start, by: 1)) { context in
                        Text(Meeting.clock(context.date.timeIntervalSince(start)))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                LevelMeter(label: "自分", level: recorder.meLevel, color: .accentColor)
                LevelMeter(label: "相手", level: recorder.othersLevel, color: .orange)
            }
            .padding([.horizontal, .top])
            VStack(alignment: .leading, spacing: 4) {
                ForEach(recorder.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text("話者の区別（話者1・話者2…）は記録の停止後に行います")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding([.horizontal, .bottom])
            .padding(.top, 6)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if let engine = recorder.batchEngine {
                            // Whisper / Gemini では、記録中は文字起こししない
                            Label("文字起こしは、記録を止めたあとに \(engine.shortName) で行います。記録中はここに文字が出ません。",
                                  systemImage: "waveform")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(recorder.liveLines) { line in
                            TranscriptLine(time: line.start, speaker: line.channel == .me ? "自分" : "相手",
                                           color: line.channel == .me ? .accentColor : .orange, text: line.text,
                                           focused: line.id == focusedLine)
                                .id(line.id)
                        }
                        if !recorder.volatileOthers.isEmpty {
                            TranscriptLine(time: nil, speaker: "相手", color: .orange, text: recorder.volatileOthers)
                                .opacity(0.5)
                        }
                        if !recorder.volatileMe.isEmpty {
                            TranscriptLine(time: nil, speaker: "自分", color: .accentColor, text: recorder.volatileMe)
                                .opacity(0.5)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding()
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
                            Label("最新の発言へ", systemImage: "arrow.down")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .clipShape(Capsule())
                        .padding(.bottom, 10)
                        .shadow(radius: 2)
                    }
                }
            }
            .safeAreaInset(edge: .trailing, spacing: 0) {
                // メモと「ここ重要」（MeetingNotesViews.swift）と、AI チャット（MeetingChatView.swift）
                HStack(spacing: 0) {
                    Divider()
                    if let id = recorder.current?.id {
                        LiveSidePanel(recorder: recorder, chat: MeetingChatStore.shared.model(for: id), mode: $sideMode) { seconds in
                            timeJump = TimeJump(seconds: seconds)
                        }
                        .frame(width: 320)
                    } else {
                        LiveNotesPanel(recorder: recorder).frame(width: 320)
                    }
                }
            }
        }
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
            .frame(width: 70, height: 6)
            .animation(.linear(duration: 0.2), value: normalized)
        }
    }

    private var normalized: CGFloat {
        guard level > 0 else { return 0 }
        let db = 20 * log10(Double(level))  // -60 dB 〜 0 dB を 0〜1 に
        return CGFloat(min(1, max(0, (db + 60) / 60)))
    }
}

// 要件: REQ-MTG-007
struct MeetingDetailView: View {
    let meeting: Meeting
    @ObservedObject var recorder: MeetingRecorder
    /// 検索結果から開いたときの飛び先（その位置までスクロールし、検索語に色を付ける）
    var jump: MeetingJump?
    /// 削除の確かめを出す（会議ノートのウインドウが持つ）。nil なら削除のボタンを出さない
    var onDelete: (() -> Void)?
    @State private var tab: Int
    @State private var title = ""
    @FocusState private var titleFocused: Bool
    @State private var editingSpeakers = false
    /// 「ここ重要」タブから「文字起こしで見る」で開いた発言（AI チャットの答えの時刻から開いた発言も）
    @State private var focusedFromHighlight: UUID?
    /// AI チャットの答えの時刻を押したとき、文字起こしのタブを開いてから移る時刻
    @State private var pendingTimeJump: Double?

    /// initialTab は確認用の描き出し（CLI）で、最初に開くタブを決めるため（0 議事録・1 文字起こし・2 メモ・3 ここ重要・4 AI チャット）
    init(meeting: Meeting, recorder: MeetingRecorder, jump: MeetingJump? = nil, initialTab: Int = 0,
         onDelete: (() -> Void)? = nil) {
        self.meeting = meeting
        self.recorder = recorder
        self.jump = jump
        self.onDelete = onDelete
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                EditableTitleField(title: $title, focused: $titleFocused,
                                   onCommit: { commitTitle(for: meeting.id) },
                                   onCancel: { title = meeting.title })
                HStack(spacing: 12) {
                    Text("\(Meeting.dateFormatter.string(from: meeting.startedAt))・\(Meeting.clock(meeting.duration))")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("話者名…") { editingSpeakers = true }
                        .disabled(meeting.speakers.isEmpty)
                    Button("議事録を作り直す") { Task { await recorder.regenerateMinutes(meeting) } }
                        .disabled(recorder.state != .idle || meeting.utterances.isEmpty)
                    MeetingExportMenu(meeting: meeting, recorder: recorder, showingTranscript: tab == 1)
                    Button("Finder で表示") {
                        NSWorkspace.shared.activateFileViewerSelecting([MeetingStore.directory(for: meeting)])
                    }
                    // 要件: REQ-MTG-028
                    if let onDelete {
                        Button(role: .destructive, action: onDelete) {
                            Label("削除…", systemImage: "trash")
                        }
                        .labelStyle(.iconOnly)
                        .help(recorder.canDelete(meeting) ? "この会議をゴミ箱に入れる" : "議事録を作り直している間は削除できません")
                        .disabled(!recorder.canDelete(meeting))
                    }
                }
                if regenerating {
                    // 要件: REQ-MTG-013
                    // 設計判断: DEC-MTG-070
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(regeneratingMessage)
                        if meeting.minutes != nil {
                            Text("終わるまで、今の議事録を出しています。").foregroundStyle(.secondary)
                        }
                    }
                    .font(.callout)
                } else if let error = meeting.errorMessage {
                    HStack {
                        Text(error).font(.caption).foregroundStyle(.orange)
                        if meeting.minutes == nil, recorder.state == .idle {
                            Button("議事録を作り直す") { Task { await recorder.regenerateMinutes(meeting) } }
                                .controlSize(.small)
                        }
                    }
                }
                HStack {
                    Picker("", selection: $tab) {
                        Text("議事録").tag(0)
                        Text("文字起こし").tag(1)
                        Text("メモ").tag(2)
                        Text("ここ重要").tag(3)
                        Text("AI チャット").tag(4)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 500)
                    Spacer()
                    MinutesTemplateMenu(meeting: meeting, recorder: recorder)
                }
            }
            .padding()
            Divider()
            if tab == 2 {
                MeetingNotesEditor(meeting: meeting, recorder: recorder)
            } else if tab == 4 {
                // 設計判断: DEC-MTG-086
                // 記録中に始めた会話を、記録のあとも確定した文字起こしで続ける
                MeetingChatView(
                    model: MeetingChatStore.shared.model(for: meeting.id),
                    material: { MeetingChat.material(for: meeting) },
                    live: false,
                    onJump: { seconds in
                        pendingTimeJump = seconds
                        tab = 1
                    },
                    onSaveNote: saveChatAnswerToNotes)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        Group {
                            if tab == 0 {
                                if let minutes = meeting.minutes {
                                    MarkdownText(markdown: minutes, highlight: jump?.terms ?? [], focusedLine: focusedMinutesLine)
                                        .opacity(regenerating ? 0.5 : 1)
                                } else {
                                    Text(meeting.status == .processing || regenerating ? "議事録を作成中です…" : "議事録はありません。")
                                        .foregroundStyle(.secondary)
                                }
                            } else if tab == 3 {
                                HighlightContextsView(meeting: meeting) { blockID in
                                    // 文字起こしのタブで、その発言の位置を開く
                                    focusedFromHighlight = blockID
                                    tab = 1
                                    Task { @MainActor in
                                        try? await Task.sleep(for: .milliseconds(80))  // タブの中身ができてから
                                        withAnimation { proxy.scrollTo(blockID, anchor: .center) }
                                    }
                                }
                            } else {
                                LazyVStack(alignment: .leading, spacing: 10) {
                                    ForEach(meeting.mergedBlocks()) { block in
                                        TranscriptLine(time: block.start, speaker: meeting.displayName(for: block.speaker),
                                                       color: Self.color(for: block.speaker, in: meeting), text: block.text,
                                                       highlight: jump?.terms ?? [],
                                                       focused: block.id == focusedBlockID || block.id == focusedFromHighlight)
                                            .id(block.id)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                    }
                    .onAppear {
                        scroll(to: jump, proxy: proxy)
                        scrollToPendingTime(proxy)
                    }
                    .onChange(of: jump) { _, newJump in scroll(to: newJump, proxy: proxy) }
                }
            }
        }
        .onAppear { title = meeting.title }
        .onChange(of: meeting.id) { oldID, _ in
            // 書きかけのタイトルは、元の会議に保存してから切り替える
            if titleFocused { commitTitle(for: oldID) }
            title = meeting.title
            focusedFromHighlight = nil
        }
        .onChange(of: meeting.title) { _, newTitle in
            if !titleFocused { title = newTitle }
        }
        // 「メモ」「ここ重要」「AI チャット」タブを開いているときに検索の結果を選んだら、飛び先のタブに切り替える（表示されたらスクロールする）
        .onChange(of: jump) { _, newJump in
            guard tab >= 2, let location = newJump?.location else { return }
            switch location {
            case .title: break
            case .minutes: tab = 0
            case .transcript: tab = 1
            }
        }
        .sheet(isPresented: $editingSpeakers) {
            SpeakerNamesSheet(meeting: meeting, recorder: recorder)
        }
    }

    /// この会議の議事録を作り直している
    private var regenerating: Bool { recorder.regeneratingID == meeting.id }

    private var regeneratingMessage: String {
        if case .processing(let message) = recorder.state { return message }
        return "議事録を作り直しています…"
    }

    // 要件: REQ-MTG-029
    // 設計判断: DEC-MTG-024
    /// 書き換えたタイトルを保存する。空なら元に戻す。id で会議を引き直す（別の会議を選んだ直後でも、元の会議に保存する）
    private func commitTitle(for id: String) {
        guard let target = recorder.meetings.first(where: { $0.id == id }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            if id == meeting.id { title = target.title }
            return
        }
        if trimmed != title, id == meeting.id { title = trimmed }
        guard trimmed != target.title else { return }
        recorder.rename(target, title: trimmed)
    }

    private var focusedBlockID: UUID? {
        if case .transcript(let blockID, _, _) = jump?.location { return blockID }
        return nil
    }

    private var focusedMinutesLine: Int? {
        if case .minutes(let line) = jump?.location { return line }
        return nil
    }

    /// 検索でヒットした位置へ移る（議事録の行なら議事録タブ、発言なら文字起こしタブ）
    private func scroll(to jump: MeetingJump?, proxy: ScrollViewProxy) {
        guard let jump, jump.meetingID == meeting.id, let location = jump.location else { return }
        switch location {
        case .title: return
        case .minutes(let line):
            tab = 0
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(80))  // タブの中身ができてから
                withAnimation { proxy.scrollTo(MarkdownText.lineID(line), anchor: .center) }
            }
        case .transcript(let blockID, _, _):
            tab = 1
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(80))
                withAnimation { proxy.scrollTo(blockID, anchor: .center) }
            }
        }
    }

    // 設計判断: DEC-MTG-084
    /// AI チャットの答えの時刻から、文字起こしのその時刻の発言へ移る
    private func scrollToPendingTime(_ proxy: ScrollViewProxy) {
        guard let seconds = pendingTimeJump else { return }
        pendingTimeJump = nil
        let blocks = meeting.mergedBlocks()
        guard let index = MeetingChat.lineIndex(at: seconds, starts: blocks.map(\.start)) else { return }
        let id = blocks[index].id
        focusedFromHighlight = id
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))  // タブの中身ができてから
            withAnimation { proxy.scrollTo(id, anchor: .center) }
        }
    }

    // 設計判断: DEC-MTG-085
    /// AI チャットの答えを、時刻なしのメモ（記録のあとに書き足したメモ）として足す。処理中・作り直し中は足さない
    private var saveChatAnswerToNotes: ((MeetingChat.Message) -> Void)? {
        guard meeting.status != .processing, recorder.current?.id != meeting.id, !regenerating else { return nil }
        let recorder = self.recorder
        let id = meeting.id
        return { message in
            guard let latest = recorder.meetings.first(where: { $0.id == id }) else { return }
            recorder.updateNotes(latest, notes: latest.allNotes + [
                MeetingNote(kind: .note, time: nil, text: MeetingChat.noteText(from: message.text)),
            ])
        }
    }

    static func color(for speaker: String, in meeting: Meeting) -> Color {
        if speaker == "me" { return .accentColor }
        let palette: [Color] = [.orange, .green, .purple, .pink, .teal, .brown, .indigo, .mint]
        let index = meeting.speakers.filter { $0 != "me" }.firstIndex(of: speaker) ?? 0
        return palette[index % palette.count]
    }
}

// 要件: REQ-MTG-012
// 設計判断: DEC-MTG-049
/// 会議ノートの「ここ重要」タブ: 印ごとに、前後の発言（30 秒前〜15 秒後）をまとめて出す。
/// 「文字起こしで見る」で、文字起こしのタブのその位置へ移る
// 要件: REQ-MTG-029
// 設計判断: DEC-MTG-024
/// 会議のタイトルの欄。書き換えられると見てわかるように、いつも薄い枠と鉛筆の印を出す
/// （マウスを載せると枠を濃く、編集中はアクセントの色にする）。Enter・フォーカスが外れたときに保存し、Esc でやめる
struct EditableTitleField: View {
    @Binding var title: String
    var focused: FocusState<Bool>.Binding
    var onCommit: () -> Void
    var onCancel: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            TextField("タイトル", text: $title)
                .font(.title2.bold())
                .textFieldStyle(.plain)
                .focused(focused)
                .onSubmit { focused.wrappedValue = false }
                .onExitCommand {
                    onCancel()
                    focused.wrappedValue = false
                }
            Image(systemName: "pencil")
                .font(.body.weight(.medium))
                .foregroundStyle(focused.wrappedValue ? Color.accentColor : .secondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6)
            .fill(Color.primary.opacity(hovering && !focused.wrappedValue ? 0.05 : 0)))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .strokeBorder(focused.wrappedValue ? Color.accentColor : Color.secondary.opacity(hovering ? 0.6 : 0.3),
                          lineWidth: focused.wrappedValue ? 2 : 1))
        .contentShape(Rectangle())
        .onTapGesture { focused.wrappedValue = true }
        .onHover { hovering = $0 }
        .padding(.horizontal, -8)  // 文字の左端を、下の日時の行とそろえる
        .onChange(of: focused.wrappedValue) { _, isFocused in
            if !isFocused { onCommit() }
        }
        // ウインドウを開いたときに、最初の入力欄としてフォーカスが入り、編集中の見た目で全選択されるのを防ぐ（クリックしたときだけ編集する）
        .task {
            try? await Task.sleep(for: .milliseconds(50))
            if focused.wrappedValue, !hovering { focused.wrappedValue = false }
        }
        .help("クリックしてタイトルを変更")
        .accessibilityHint("タイトルを変更できます")
    }
}

private struct HighlightContextsView: View {
    let meeting: Meeting
    var openInTranscript: (UUID) -> Void

    var body: some View {
        let contexts = meeting.highlightContexts()
        LazyVStack(alignment: .leading, spacing: 18) {
            if contexts.isEmpty {
                Text("「ここ重要」の印はありません。記録中に「★ ここ重要」かショートカットで付けると、ここに前後の会話をまとめて出します。")
                    .foregroundStyle(.secondary)
            }
            ForEach(contexts, id: \.note.id) { context in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                        Text(context.note.time.map(Meeting.clock) ?? "--:--")
                            .font(.system(.body, design: .monospaced))
                        Text(context.note.text.isEmpty ? "ここ重要" : context.note.text).fontWeight(.semibold)
                        Spacer()
                        if let first = context.blocks.first {
                            Button("文字起こしで見る") { openInTranscript(first.id) }
                                .controlSize(.small)
                        }
                    }
                    if context.blocks.isEmpty {
                        Text("この前後（30 秒前〜15 秒後）の発言はありません").font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(context.blocks) { block in
                        TranscriptLine(time: block.start, speaker: meeting.displayName(for: block.speaker),
                                       color: MeetingDetailView.color(for: block.speaker, in: meeting), text: block.text)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.yellow.opacity(0.08)))
            }
        }
    }
}

private struct SpeakerNamesSheet: View {
    let meeting: Meeting
    @ObservedObject var recorder: MeetingRecorder
    @Environment(\.dismiss) private var dismiss
    @State private var names: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("話者名").font(.headline)
            Text("議事録の「話者についてのメモ」も参考にしてください。「推測」は、議事録を作るときに会話から推測して付けた名前です。変更は文字起こしに反映されます（議事録は作り直すと反映されます）。")
                .font(.caption).foregroundStyle(.secondary)
            Form {
                ForEach(meeting.speakers, id: \.self) { speaker in
                    HStack {
                        TextField(Meeting(id: "", title: "", startedAt: Date()).displayName(for: speaker),
                                  text: Binding(get: { names[speaker] ?? "" }, set: { names[speaker] = $0 }))
                        // 要件: REQ-MTG-027
                        // 設計判断: DEC-MTG-069
                        if meeting.isInferredName(speaker), names[speaker] == meeting.speakerNames[speaker] {
                            Text("推測")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .help("会話から推測した名前です。違っていたら直してください")
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("キャンセル") { dismiss() }
                Button("保存") {
                    // 変えた話者だけを、まとめて保存する（推測の印は、直した話者だけ外す）
                    recorder.renameSpeakers(meeting, names: names.filter { $0.value != (meeting.speakerNames[$0.key] ?? "") })
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 380)
        .onAppear { names = meeting.speakerNames }
    }
}

private struct TranscriptLine: View {
    let time: Double?
    let speaker: String
    let color: Color
    let text: String
    var highlight: [String] = []
    var focused = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(time.map(Meeting.clock) ?? "")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
            Text(speaker)
                .font(.callout.bold())
                .foregroundStyle(color)
                .frame(width: 72, alignment: .leading)
            Text(MeetingSearchHighlight.apply(AttributedString(text), terms: highlight))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(focused ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.12)).padding(-4) : nil)
    }
}

/// 議事録用の簡易 Markdown 表示（見出し・箇条書き・チェックボックス・強調）
struct MarkdownText: View {
    let markdown: String
    /// 色を付ける検索語
    var highlight: [String] = []
    /// 検索でヒットした行（背景を付ける）
    var focusedLine: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(markdown.components(separatedBy: "\n").enumerated()), id: \.offset) { offset, line in
                lineView(line)
                    .background(offset == focusedLine ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.12)).padding(-4) : nil)
                    .id(Self.lineID(offset))
            }
        }
    }

    static func lineID(_ line: Int) -> String { "minutes-line-\(line)" }

    @ViewBuilder private func lineView(_ line: String) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let indent = CGFloat(line.prefix { $0 == " " }.count / 2) * 16
        if trimmed.isEmpty {
            Spacer().frame(height: 4)
        } else if trimmed.hasPrefix("### ") {
            inline(String(trimmed.dropFirst(4))).font(.headline).padding(.top, 4)
        } else if trimmed.hasPrefix("## ") {
            inline(String(trimmed.dropFirst(3))).font(.title3.bold()).padding(.top, 8)
        } else if trimmed.hasPrefix("# ") {
            inline(String(trimmed.dropFirst(2))).font(.title2.bold())
        } else if trimmed.hasPrefix("- [ ] ") || trimmed.hasPrefix("- [x] ") {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: trimmed.hasPrefix("- [x] ") ? "checkmark.square" : "square")
                inline(String(trimmed.dropFirst(6)))
            }
            .padding(.leading, indent)
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            HStack(alignment: .firstTextBaseline) {
                Text("•")
                inline(String(trimmed.dropFirst(2)))
            }
            .padding(.leading, indent)
        } else {
            inline(trimmed)
        }
    }

    private func inline(_ text: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(MeetingSearchHighlight.apply(attributed, terms: highlight))
        }
        return Text(MeetingSearchHighlight.apply(AttributedString(text), terms: highlight))
    }
}
