import AppKit
import SwiftUI

// MARK: - 記録中のオフレコ

// 要件: REQ-MTG-046
// 設計判断: DEC-MTG-094
/// 記録中の画面の上に置く「オフレコ」のボタン。押すとオフレコを始め、もう一度押すと終える
struct LiveOffRecordButton: View {
    @ObservedObject var recorder: MeetingRecorder

    var body: some View {
        let open = recorder.openOffRecord != nil
        Button {
            recorder.toggleOffRecord()
        } label: {
            Label(open ? tr("オフレコを終える") : tr("オフレコ"), systemImage: open ? "eye" : "eye.slash")
        }
        .tint(open ? .purple : nil)
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(recorder.state != .recording)
        .help(open ? tr("オフレコを終えて、ここからの発言をまた議事録に使う") : tr("ここからの発言を、議事録と AI チャットに使わない（録音は続けます）"))
    }
}

// 要件: REQ-MTG-046
/// オフレコ中に記録中の画面の上に出す帯
struct LiveOffRecordBanner: View {
    @ObservedObject var recorder: MeetingRecorder

    var body: some View {
        if let span = recorder.openOffRecord {
            Label(tr("オフレコ中（%@ から）。この間の発言は、議事録と AI チャットに使いません。", Meeting.clock(span.start)),
                  systemImage: "eye.slash")
                .font(.callout)
                .foregroundStyle(.purple)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(Color.purple.opacity(0.08))
        }
    }
}

// MARK: - 会議ノートの文字起こし

// 要件: REQ-MTG-044, REQ-MTG-045, REQ-MTG-046
// 設計判断: DEC-MTG-092, DEC-MTG-093
/// 文字起こしの上の帯: 議事録に使う発言の数・範囲・除いた話者・オフレコの区間と、選ぶモードの切り替え
struct TranscriptSelectionBar: View {
    let meeting: Meeting
    @ObservedObject var recorder: MeetingRecorder
    @Binding var selecting: Bool
    var onRegenerate: () -> Void

    var body: some View {
        let blocks = meeting.displayBlocks()
        let editable = recorder.canEditMinutesSelection(meeting)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(tr("議事録に使う発言: %@ / %@", "\(blocks.filter(\.use.isUsed).count)", "\(blocks.count)"))
                    .font(.callout.weight(.medium))
                if meeting.minutesFrom != nil || meeting.minutesTo != nil {
                    chip(tr("範囲: %@ 〜 %@", meeting.minutesFrom.map(Meeting.clock) ?? tr("最初"), meeting.minutesTo.map(Meeting.clock) ?? tr("最後")),
                         help: tr("範囲を解除する")) {
                        recorder.changeMinutesSelection(meeting) { $0.setMinutesRange(from: .some(nil), to: .some(nil)) }
                    }
                }
                Spacer()
                Toggle(tr("議事録に使う発言を選ぶ"), isOn: $selecting)
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .help(tr("発言ごとにチェックボックスを出します。Shift を押しながら押すと、前に押した発言からまとめて切り替えます"))
                if meeting.hasMinutesSelection {
                    Button(tr("すべて元に戻す")) {
                        recorder.changeMinutesSelection(meeting) { $0.clearMinutesSelection() }
                    }
                    .controlSize(.small)
                    .help(tr("範囲・除いた発言・除いた話者・オフレコをすべて解除して、全部の発言を議事録に使う"))
                }
            }
            let speakers = meeting.excludedSpeakers ?? []
            let spans = meeting.offRecord ?? []
            if !speakers.isEmpty || !spans.isEmpty {
                HStack(spacing: 6) {
                    ForEach(speakers, id: \.self) { speaker in
                        chip(tr("除いた話者: %@", meeting.displayName(for: speaker)), help: tr("この話者の発言を議事録に戻す")) {
                            recorder.changeMinutesSelection(meeting) { $0.setSpeakerExcluded(speaker, excluded: false) }
                        }
                    }
                    ForEach(spans) { span in
                        chip(tr("オフレコ %@ 〜 %@", Meeting.clock(span.start), span.end.map(Meeting.clock) ?? tr("最後")),
                             help: tr("オフレコを解除して、この間の発言を議事録に使う")) {
                            recorder.changeMinutesSelection(meeting) { $0.removeOffRecord(span.id) }
                        }
                    }
                }
            }
            if meeting.minutesOutdated == true {
                MinutesOutdatedNotice(meeting: meeting, recorder: recorder, onRegenerate: onRegenerate)
            } else if !meeting.hasMinutesSelection, !selecting {
                Text(tr("発言を右クリックすると、議事録から除いたり、議事録に使う範囲（最初と最後）を決めたりできます。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(!editable)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func chip(_ text: String, help: String, remove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(text).font(.caption)
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(help)
            .accessibilityLabel(help)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.secondary.opacity(0.12)))
    }
}

// 要件: REQ-MTG-045
// 設計判断: DEC-MTG-092
/// 議事録に使う発言を変えたあと、まだ作り直していないことの知らせ
struct MinutesOutdatedNotice: View {
    let meeting: Meeting
    @ObservedObject var recorder: MeetingRecorder
    var onRegenerate: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Label(tr("議事録に使う発言を変えました。作り直すと反映されます。"), systemImage: "arrow.triangle.2.circlepath")
                .font(.callout)
                .foregroundStyle(.orange)
            Button(tr("議事録を作り直す"), action: onRegenerate)
                .controlSize(.small)
                // 設計判断: DEC-MTG-091（使う発言がなければ作らない）
                .disabled(recorder.state != .idle || meeting.usedUtterances.isEmpty)
        }
    }
}

// 要件: REQ-MTG-044, REQ-MTG-045, REQ-MTG-046
// 設計判断: DEC-MTG-093
/// 会議ノートの文字起こしの 1 行。選ぶモードならチェックボックス、マウスを載せると右端に「…」のメニュー（右クリックと同じ中身）を出す
struct TranscriptDisplayRow: View {
    let meeting: Meeting
    let blocks: [TranscriptDisplayBlock]
    let index: Int
    @ObservedObject var recorder: MeetingRecorder
    var selecting: Bool
    @Binding var anchor: Int?
    var highlight: [String] = []
    var focused = false
    @State private var hovering = false

    var body: some View {
        let item = blocks[index]
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if selecting {
                TranscriptUseCheckbox(meeting: meeting, blocks: blocks, index: index, recorder: recorder, anchor: $anchor)
            }
            TranscriptLine(time: item.block.start, speaker: meeting.displayName(for: item.block.speaker),
                           color: MeetingDetailView.color(for: item.block.speaker, in: meeting), text: item.block.text,
                           highlight: highlight, focused: focused, use: item.use)
            Menu {
                TranscriptLineMenu(meeting: meeting, block: item, recorder: recorder)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .opacity(hovering ? 1 : 0)
            .help(tr("議事録に使うかを変える"))
            .accessibilityLabel(tr("議事録に使うかを変える"))
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu { TranscriptLineMenu(meeting: meeting, block: item, recorder: recorder) }
    }
}

/// 文字起こしの発言の右クリック（と「…」）のメニュー
struct TranscriptLineMenu: View {
    let meeting: Meeting
    let block: TranscriptDisplayBlock
    @ObservedObject var recorder: MeetingRecorder

    var body: some View {
        let editable = recorder.canEditMinutesSelection(meeting)
        Group {
            switch block.use {
            case .used:
                Button(tr("議事録から除く")) { change { $0.setExcluded(block.members, excluded: true) } }
            case .excluded:
                Button(tr("議事録に戻す")) { change { $0.include(block.members) } }
            case .outsideRange:
                Button(tr("議事録に使う（範囲を広げる）")) { change { $0.include(block.members) } }
            case .offRecord:
                if let span = meeting.offRecord?.first(where: { $0.contains(block.block.start) }) {
                    Button(tr("このオフレコを解除する（%@ 〜 %@）", Meeting.clock(span.start), span.end.map(Meeting.clock) ?? tr("最後"))) {
                        change { $0.removeOffRecord(span.id) }
                    }
                }
            case .speakerExcluded:
                EmptyView()
            }
            Divider()
            Button(tr("ここから議事録に使う")) { change { $0.setMinutesRange(from: .some(block.block.start)) } }
            Button(tr("ここまで議事録に使う")) { change { $0.setMinutesRange(to: .some(block.lastStart)) } }
            Divider()
            let name = meeting.displayName(for: block.block.speaker)
            if meeting.excludedSpeakers?.contains(block.block.speaker) == true {
                Button(tr("「%@」の発言を議事録に戻す", name)) { change { $0.setSpeakerExcluded(block.block.speaker, excluded: false) } }
            } else {
                Button(tr("「%@」の発言をすべて除く", name)) { change { $0.setSpeakerExcluded(block.block.speaker, excluded: true) } }
            }
        }
        .disabled(!editable)
    }

    private func change(_ edit: @escaping (inout Meeting) -> Void) {
        recorder.changeMinutesSelection(meeting, edit)
    }
}

// 要件: REQ-MTG-045
// 設計判断: DEC-MTG-093
/// 「議事録に使う発言を選ぶ」のときの、発言ごとのチェックボックス。Shift を押しながら押すと、前に押した発言からまとめて切り替える
struct TranscriptUseCheckbox: View {
    let meeting: Meeting
    let blocks: [TranscriptDisplayBlock]
    let index: Int
    @ObservedObject var recorder: MeetingRecorder
    /// 前に押した発言の位置
    @Binding var anchor: Int?

    var body: some View {
        let block = blocks[index]
        // 話者・オフレコで除いた発言は、ここでは変えない（帯か右クリックで解除する）
        let fixed = block.use == .speakerExcluded || block.use == .offRecord
        Toggle("", isOn: Binding(get: { block.use.isUsed }, set: { set($0) }))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(fixed || !recorder.canEditMinutesSelection(meeting))
            .help(fixed ? block.use.label : tr("議事録に使う"))
            .accessibilityLabel(tr("議事録に使う"))
    }

    private func set(_ used: Bool) {
        var range = index...index
        if NSEvent.modifierFlags.contains(.shift), let anchor, anchor < blocks.count {
            range = min(anchor, index)...max(anchor, index)
        }
        let targets = blocks[range].filter { $0.use != .speakerExcluded && $0.use != .offRecord }
        let ids = targets.flatMap(\.members)
        recorder.changeMinutesSelection(meeting) { m in
            if used { m.include(ids) } else { m.setExcluded(ids, excluded: true) }
        }
        anchor = index
    }
}
