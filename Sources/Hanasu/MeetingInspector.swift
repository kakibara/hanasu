import AppKit
import SwiftUI

// 要件: REQ-MTG-050
// 設計判断: DEC-MTG-130
/// 会議ノートの後ろ側のパネルに出すもの（記録のあと）
enum MeetingInspectorTab: String {
    case transcript
    case chat
}

// 要件: REQ-MTG-050, REQ-MTG-041
// 設計判断: DEC-MTG-130, DEC-MTG-086
/// 記録した会議の後ろ側のパネル: 「文字起こし｜AI チャット」
struct MeetingInspector: View {
    let meeting: Meeting
    @ObservedObject var recorder: MeetingRecorder
    @Binding var tab: MeetingInspectorTab
    var focus: TranscriptFocus?
    @Binding var selecting: Bool
    /// 色を付ける検索語
    var highlight: [String] = []
    /// 記録を止めたあとの処理中（文字起こしは記録中のものを出す）
    var processing = false
    var onRegenerate: () -> Void
    /// AI チャットの答えの時刻を押したとき
    var onChatJump: (Double) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text(tr("文字起こし")).tag(MeetingInspectorTab.transcript)
                Text(tr("AI チャット")).tag(MeetingInspectorTab.chat)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            switch tab {
            case .transcript:
                MeetingTranscriptPanel(meeting: meeting, recorder: recorder, focus: focus, selecting: $selecting,
                                       highlight: highlight, processing: processing, onRegenerate: onRegenerate)
            case .chat:
                // 設計判断: DEC-MTG-086
                // 記録中に始めた会話を、記録のあとも確定した文字起こしで続ける
                MeetingChatView(
                    model: MeetingChatStore.shared.model(for: meeting.id),
                    material: { MeetingChat.material(for: meeting) },
                    live: false,
                    onJump: onChatJump,
                    onSaveNote: saveChatAnswerToNotes)
            }
        }
        // ⌘J で AI チャットへ
        .background {
            Button("") {
                tab = .chat
                MeetingChatStore.shared.model(for: meeting.id).requestFocus()
            }
            .keyboardShortcut("j", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
    }

    // 設計判断: DEC-MTG-085
    /// AI チャットの答えを、時刻なしのメモ（記録のあとに書き足したメモ）として足す。処理中・作り直し中は足さない
    private var saveChatAnswerToNotes: ((MeetingChat.Message) -> Void)? {
        guard meeting.status != .processing, recorder.current?.id != meeting.id, recorder.regeneratingID != meeting.id else { return nil }
        let recorder = self.recorder
        let id = meeting.id
        return { message in
            guard let latest = recorder.meetings.first(where: { $0.id == id }) else { return }
            recorder.updateNotes(latest, notes: latest.allNotes + [
                MeetingNote(kind: .note, time: nil, text: MeetingChat.noteText(from: message.text)),
            ])
        }
    }
}

// 要件: REQ-MTG-044, REQ-MTG-045, REQ-MTG-046, REQ-MTG-052, REQ-MTG-053
// 設計判断: DEC-MTG-137, DEC-MTG-084
/// 後ろ側のパネルの文字起こし。根拠の時刻・検索・ここ重要から移った発言と、再生位置の発言に色を付ける。
/// 再生中は再生位置の発言が見えるように動かし、手でスクロールしたら止める（「再生位置へ」で戻る）
struct MeetingTranscriptPanel: View {
    let meeting: Meeting
    @ObservedObject var recorder: MeetingRecorder
    var focus: TranscriptFocus?
    @Binding var selecting: Bool
    var highlight: [String] = []
    var processing = false
    var onRegenerate: () -> Void
    @ObservedObject private var player = MeetingPlayer.shared
    @State private var focusedID: UUID?
    @State private var selectionAnchor: Int?
    @State private var following = true

    var body: some View {
        let blocks = meeting.displayBlocks()
        VStack(spacing: 0) {
            if !blocks.isEmpty {
                TranscriptSelectionBar(meeting: meeting, recorder: recorder, selecting: $selecting, onRegenerate: onRegenerate)
                Divider()
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if blocks.isEmpty {
                            emptyState
                        }
                        ForEach(Array(blocks.enumerated()), id: \.element.id) { index, item in
                            TranscriptDisplayRow(meeting: meeting, blocks: blocks, index: index, recorder: recorder,
                                                 selecting: selecting, anchor: $selectionAnchor, highlight: highlight,
                                                 focused: item.id == focusedID, playing: item.id == playingID(blocks),
                                                 onPlay: canPlay ? { player.play(from: item.block.start) } : nil)
                                .id(item.id)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .textSelection(.enabled)
                }
                .onScrollPhaseChange { _, phase in
                    // 手でスクロールしたら、再生位置を追うのをやめる
                    if phase == .interacting, player.isPlaying { following = false }
                }
                .onAppear { apply(focus, blocks: blocks, proxy: proxy) }
                .onChange(of: focus) { _, newFocus in apply(newFocus, blocks: blocks, proxy: proxy) }
                .onChange(of: playingID(blocks)) { _, id in
                    guard let id, following, player.isPlaying else { return }
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                }
                .onChange(of: player.isPlaying) { _, playing in if playing { following = true } }
                .overlay(alignment: .bottom) {
                    if player.isPlaying, !following, let id = playingID(blocks) {
                        Button {
                            following = true
                            withAnimation { proxy.scrollTo(id, anchor: .center) }
                        } label: {
                            Label(tr("再生位置へ"), systemImage: "waveform")
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
        .onChange(of: meeting.id) {
            focusedID = nil
            selectionAnchor = nil
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if processing, !recorder.liveLines.isEmpty {
            // 話者の区別が終わるまでは、記録中の文字起こしを出す
            Text(tr("話者の区別が終わると、名前と色が付きます"))
                .font(.caption).foregroundStyle(.secondary)
                .padding(.bottom, 4)
            ForEach(recorder.liveLines) { line in
                TranscriptLine(time: line.start, speaker: line.channel == .me ? tr("自分") : tr("相手"),
                               color: line.channel == .me ? .accentColor : .orange, text: line.text, compact: true)
            }
        } else {
            Text(processing ? tr("記録のあとの処理が終わると、ここに文字起こしが出ます。") : tr("文字起こしはありません。"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        }
    }

    /// この会議を再生できるか（文字起こしの時刻を押すと、そこから再生する）
    private var canPlay: Bool {
        player.meetingID == meeting.id && player.availability == .ready
            && MeetingPlayer.blockReason(recording: recorder.state == .recording, dictating: player.dictationActive) == nil
    }

    // 要件: REQ-MTG-053
    private func playingID(_ blocks: [TranscriptDisplayBlock]) -> UUID? {
        guard player.meetingID == meeting.id, player.isPlaying || player.currentTime > 0,
              let index = MeetingPlayer.blockIndex(at: player.currentTime, starts: blocks.map(\.block.start)) else { return nil }
        return blocks[index].id
    }

    // 設計判断: DEC-MTG-084
    private func apply(_ focus: TranscriptFocus?, blocks: [TranscriptDisplayBlock], proxy: ScrollViewProxy) {
        guard let focus else { return }
        let id: UUID?
        switch focus.target {
        case .block(let blockID):
            // まとめた発言の ID か、その中の発言の ID
            id = blocks.first { $0.id == blockID || $0.members.contains(blockID) }?.id ?? blockID
        case .time(let seconds):
            id = MeetingChat.lineIndex(at: seconds, starts: blocks.map(\.block.start)).map { blocks[$0].id }
            // 再生中なら、その位置へ移る（再生していなければ再生は始めない）
            if player.meetingID == meeting.id, player.isPlaying { player.seek(to: seconds) }
        }
        guard let id else { return }
        focusedID = id
        following = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))  // 中身ができてから
            withAnimation { proxy.scrollTo(id, anchor: .center) }
        }
    }
}

// MARK: - 文字起こしの 1 行

struct TranscriptLine: View {
    let time: Double?
    let speaker: String
    let color: Color
    let text: String
    var highlight: [String] = []
    var focused = false
    // 要件: REQ-MTG-045
    // 設計判断: DEC-MTG-091
    /// 議事録に使うか。使わない発言は薄く出し（除外とオフレコは取り消し線も）、理由を添える
    var use: MinutesUse = .used
    /// 後ろ側のパネル向けに、話者と時刻を上の行に、発言を下に出す
    var compact = false
    // 要件: REQ-MTG-053
    /// 再生位置の発言
    var playing = false
    /// 時刻を押したとき（そこから再生する）。nil なら押せない
    var onPlay: (() -> Void)?

    var body: some View {
        Group {
            if compact {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        speakerLabel
                        timeLabel
                        if playing {
                            Text(tr("再生中"))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                        }
                        Spacer(minLength: 0)
                        reason
                    }
                    textView
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    timeLabel.frame(width: 52, alignment: .trailing)
                    speakerLabel.frame(width: 72, alignment: .leading)
                    textView
                    reason
                }
            }
        }
        .padding(.horizontal, compact ? 8 : 0)
        .padding(.vertical, compact ? 6 : 0)
        .opacity(use.isUsed ? 1 : 0.45)
        .background(background)
        .accessibilityElement(children: .combine)
        .accessibilityValue(use.isUsed ? (playing ? tr("再生中") : "") : tr("議事録に使わない（%@）", use.label))
    }

    @ViewBuilder private var background: some View {
        if focused {
            RoundedRectangle(cornerRadius: 8).fill(Color.yellow.opacity(0.18)).padding(compact ? 0 : -4)
        } else if playing {
            RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.1)).padding(compact ? 0 : -4)
        }
    }

    private var speakerLabel: some View {
        Text(speaker)
            .font(compact ? .caption.bold() : .callout.bold())
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
            .help(speaker)
    }

    @ViewBuilder private var timeLabel: some View {
        let label = Text(time.map(Meeting.clock) ?? "")
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
        if let onPlay, time != nil {
            Button(action: onPlay) { label }
                .buttonStyle(.plain)
                .help(tr("ここから再生する"))
                .accessibilityLabel(tr("%@ から再生", time.map(Meeting.clock) ?? ""))
        } else {
            label
        }
    }

    private var textView: some View {
        Text(MeetingSearchHighlight.apply(AttributedString(text), terms: highlight))
            .strikethrough(use == .excluded || use == .offRecord)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var reason: some View {
        if !use.isUsed {
            Text(use.label)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 折り返して並べる

/// 小さな部品（範囲・除いた話者・オフレコのカプセルなど）を、幅に合わせて折り返して並べる
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
