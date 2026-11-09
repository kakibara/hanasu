import SwiftUI

// 要件: REQ-MTG-053
// 設計判断: DEC-MTG-135
/// 文書の下の再生のバー: 再生・15 秒戻る/進む・時刻・位置（話者の区間と「ここ重要」の印つき）・速さ・自分/相手の消音。
/// 音声ファイルがない会議・記録中や処理中の会議では出さない
struct MeetingPlayerBar: View {
    let meeting: Meeting
    @ObservedObject var recorder: MeetingRecorder
    /// 記録を止めたあとの処理中・作り直し中（再生しない）
    var busy = false
    @ObservedObject private var player = MeetingPlayer.shared

    var body: some View {
        Group {
            if !busy, player.meetingID == meeting.id, player.availability != .none {
                content
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
        .onAppear {
            sync()
            player.installSpaceKey()
        }
        .onChange(of: meeting.id) { sync() }
        .onChange(of: busy) { sync() }
        .onChange(of: recorder.state) {
            if recorder.state == .recording || recorder.state == .starting { player.pause() }
        }
        .onDisappear {
            if player.meetingID == meeting.id { player.stop() }
        }
    }

    /// 選んだ会議の音声を読み込む（処理中・作り直し中は手放す）
    private func sync() {
        if busy {
            if player.meetingID == meeting.id { player.stop() }
        } else {
            player.load(meeting)
        }
    }

    private var blockReason: String? {
        MeetingPlayer.blockReason(recording: recorder.state == .recording || recorder.state == .starting,
                                  dictating: player.dictationActive)
    }

    @ViewBuilder
    private var content: some View {
        switch player.availability {
        case .unreadable:
            Label(tr("この音声は再生できません"), systemImage: "speaker.slash")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(tr("音声を読み込んでいます…")).font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
        case .ready, .none:
            VStack(alignment: .leading, spacing: 4) {
                controls
                if let reason = blockReason {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                } else if let missing = missingChannelNote {
                    Text(missing).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// 幅が足りないとき（最小の大きさで後ろ側のパネルを出しているときなど）は、時刻を外し、速さと消音をメニューにまとめる
    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                transport
                timeLabel
                MeetingScrubber(meeting: meeting, time: player.currentTime, duration: player.duration) { player.seek(to: $0) }
                    .frame(minWidth: 140)
                rateMenu
                muteToggles
            }
            HStack(spacing: 8) {
                transport
                MeetingScrubber(meeting: meeting, time: player.currentTime, duration: player.duration) { player.seek(to: $0) }
                compactMenu
            }
        }
        .buttonStyle(.borderless)
        .disabled(blockReason != nil)
    }

    private var transport: some View {
        HStack(spacing: 8) {
            Button { player.skip(by: -15) } label: { Image(systemName: "gobackward.15") }
                .help(tr("15 秒戻る"))
                .accessibilityLabel(tr("15 秒戻る"))
            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 18)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .help(player.isPlaying ? tr("一時停止（スペース）") : tr("再生（スペース）"))
            .accessibilityLabel(player.isPlaying ? tr("一時停止") : tr("再生"))
            Button { player.skip(by: 15) } label: { Image(systemName: "goforward.15") }
                .help(tr("15 秒進む"))
                .accessibilityLabel(tr("15 秒進む"))
        }
        .fixedSize()
    }

    private var timeLabel: some View {
        Text("\(Meeting.clock(player.currentTime)) / \(Meeting.clock(player.duration))")
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
            .fixedSize()
    }

    private var rateMenu: some View {
        Menu {
            rateItems
        } label: {
            Text(Self.rateLabel(player.rate)).font(.callout.monospacedDigit())
        }
        .menuStyle(.button)
        .fixedSize()
        .help(tr("再生の速さ"))
    }

    @ViewBuilder private var rateItems: some View {
        ForEach(MeetingPlayer.rates, id: \.self) { rate in
            Button {
                player.rate = rate
            } label: {
                if player.rate == rate { Label(Self.rateLabel(rate), systemImage: "checkmark") } else { Text(Self.rateLabel(rate)) }
            }
        }
    }

    /// 狭いときのメニュー（時刻・速さ・消音）
    private var compactMenu: some View {
        Menu {
            Text("\(Meeting.clock(player.currentTime)) / \(Meeting.clock(player.duration))")
            Section(tr("再生の速さ")) { rateItems }
            Section(tr("聞く声")) {
                ForEach([(MeetingChannel.me, tr("自分")), (MeetingChannel.others, tr("相手"))], id: \.0) { channel, title in
                    Toggle(title, isOn: Binding(get: { !player.muted.contains(channel) }, set: { on in
                        if on { player.muted.remove(channel) } else { player.muted.insert(channel) }
                    }))
                    .disabled(!player.channels.contains(channel))
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(tr("再生の速さと、聞く声"))
        .accessibilityLabel(tr("再生の速さと、聞く声"))
    }

    // 設計判断: DEC-MTG-135（イヤホンなしの会議で相手の声が二重に聞こえるときに、片方を消す）
    private var muteToggles: some View {
        HStack(spacing: 2) {
            muteToggle(.me, title: tr("自分"))
            muteToggle(.others, title: tr("相手"))
        }
        .padding(2)
        .background(Capsule().fill(Color.secondary.opacity(0.12)))
    }

    private func muteToggle(_ channel: MeetingChannel, title: String) -> some View {
        let present = player.channels.contains(channel)
        let on = present && !player.muted.contains(channel)
        return Button {
            if player.muted.contains(channel) { player.muted.remove(channel) } else { player.muted.insert(channel) }
        } label: {
            Text(title)
                .font(.caption.weight(.medium))
                .strikethrough(!on)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(on ? Color(nsColor: .controlBackgroundColor) : Color.clear))
                .foregroundStyle(on ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
        .disabled(!present)
        .help(present ? (on ? tr("%@の声を消す", title) : tr("%@の声を出す", title)) : tr("%@の音声はありません", title))
        .accessibilityLabel(tr("%@の声", title))
        .accessibilityValue(present ? (on ? tr("オン") : tr("オフ")) : tr("なし"))
    }

    private var missingChannelNote: String? {
        if !player.channels.contains(.others), player.channels.contains(.me) { return tr("%@の音声はありません", tr("相手")) }
        if !player.channels.contains(.me), player.channels.contains(.others) { return tr("%@の音声はありません", tr("自分")) }
        return nil
    }

    static func rateLabel(_ rate: Float) -> String {
        rate == rate.rounded() ? "\(Int(rate))×" : String(format: "%g×", rate)
    }
}

// 要件: REQ-MTG-053
/// 再生の位置。話者ごとの色で話した区間と、「ここ重要」の印の位置を出す。ドラッグか押した所へ移る
struct MeetingScrubber: View {
    let meeting: Meeting
    let time: Double
    let duration: Double
    var onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18)).frame(height: 6)
                // 話者の区間
                ForEach(meeting.mergedBlocks()) { block in
                    Rectangle()
                        .fill(MeetingSpeakerColor.color(for: block.speaker, in: meeting).opacity(0.85))
                        .frame(width: max(1, width * CGFloat((block.end - block.start) / safeDuration)), height: 6)
                        .offset(x: width * CGFloat(block.start / safeDuration))
                }
                .mask(Capsule().frame(height: 6))
                // 「ここ重要」の印
                ForEach(meeting.allNotes.filter { $0.kind == .highlight && $0.time != nil }) { note in
                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.yellow)
                        .offset(x: width * CGFloat((note.time ?? 0) / safeDuration) - 4, y: -9)
                }
                Circle()
                    .fill(Color.white)
                    .shadow(radius: 1.5)
                    .frame(width: 14, height: 14)
                    .offset(x: width * CGFloat(min(time, safeDuration) / safeDuration) - 7)
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                onSeek(Double(max(0, min(value.location.x, width)) / width) * safeDuration)
            })
        }
        .frame(minWidth: 80, maxWidth: .infinity)
        .frame(height: 22)
        .accessibilityRepresentation {
            Slider(value: Binding(get: { time }, set: onSeek), in: 0...safeDuration) {
                Text(tr("再生位置"))
            }
        }
    }

    private var safeDuration: Double { max(1, duration) }
}
