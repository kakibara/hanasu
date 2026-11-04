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

    var body: some View {
        NavigationSplitView {
            Group {
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
                                MeetingRow(meeting: current, live: true).tag(current.id)
                            }
                        }
                        Section("会議") {
                            ForEach(recorder.meetings.filter { $0.id != recorder.current?.id }) { meeting in
                                MeetingRow(meeting: meeting, live: false).tag(meeting.id)
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                MeetingSearchField(model: search) {
                    showingAsk = true
                    selection = nil
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            .safeAreaInset(edge: .bottom) {
                RecordButton(recorder: recorder)
                    .padding(10)
            }
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
                MeetingDetailView(meeting: meeting, recorder: recorder, jump: jump?.meetingID == id ? jump : nil)
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
        .onChange(of: recorder.current?.id) { _, newID in
            if let newID { selection = newID }
        }
        .onChange(of: recorder.state) { old, new in
            // 処理が終わったら、その会議を選んだままにする
            if new == .idle, case .processing = old, let first = recorder.meetings.first { selection = first.id }
        }
    }

    private var selectedHitID: String? {
        guard let jump, let location = jump.location else { return nil }
        return MeetingSearchHit(meetingID: jump.meetingID, location: location, snippet: "").id
    }
}

private struct MeetingRow: View {
    let meeting: Meeting
    let live: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if live { Image(systemName: "record.circle.fill").foregroundStyle(.red) }
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
                                           color: line.channel == .me ? .accentColor : .orange, text: line.text)
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
                .onChange(of: recorder.liveLines.count) { proxy.scrollTo("bottom") }
            }
            .safeAreaInset(edge: .trailing, spacing: 0) {
                // メモと「ここ重要」（MeetingNotesViews.swift）
                HStack(spacing: 0) {
                    Divider()
                    LiveNotesPanel(recorder: recorder).frame(width: 280)
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
    @State private var tab = 0
    @State private var title = ""
    @State private var editingSpeakers = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("タイトル", text: $title)
                    .font(.title2.bold())
                    .textFieldStyle(.plain)
                    .onSubmit { recorder.rename(meeting, title: title) }
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
                }
                if let error = meeting.errorMessage {
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
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 300)
                    Spacer()
                    MinutesTemplateMenu(meeting: meeting, recorder: recorder)
                }
            }
            .padding()
            Divider()
            if tab == 2 {
                MeetingNotesEditor(meeting: meeting, recorder: recorder)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        Group {
                            if tab == 0 {
                                if let minutes = meeting.minutes {
                                    MarkdownText(markdown: minutes, highlight: jump?.terms ?? [], focusedLine: focusedMinutesLine)
                                } else {
                                    Text(meeting.status == .processing ? "議事録を作成中です…" : "議事録はありません。")
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                LazyVStack(alignment: .leading, spacing: 10) {
                                    ForEach(meeting.mergedBlocks()) { block in
                                        TranscriptLine(time: block.start, speaker: meeting.displayName(for: block.speaker),
                                                       color: Self.color(for: block.speaker, in: meeting), text: block.text,
                                                       highlight: jump?.terms ?? [], focused: block.id == focusedBlockID)
                                            .id(block.id)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                    }
                    .onAppear { scroll(to: jump, proxy: proxy) }
                    .onChange(of: jump) { _, newJump in scroll(to: newJump, proxy: proxy) }
                }
            }
        }
        .onAppear { title = meeting.title }
        .onChange(of: meeting.id) { title = meeting.title }
        // 「メモ」タブを開いているときに検索の結果を選んだら、飛び先のタブに切り替える（表示されたらスクロールする）
        .onChange(of: jump) { _, newJump in
            guard tab == 2, let location = newJump?.location else { return }
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

    static func color(for speaker: String, in meeting: Meeting) -> Color {
        if speaker == "me" { return .accentColor }
        let palette: [Color] = [.orange, .green, .purple, .pink, .teal, .brown, .indigo, .mint]
        let index = meeting.speakers.filter { $0 != "me" }.firstIndex(of: speaker) ?? 0
        return palette[index % palette.count]
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
