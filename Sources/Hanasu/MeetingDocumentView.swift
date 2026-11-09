import AppKit
import SwiftUI

// 要件: REQ-MTG-050
// 設計判断: DEC-MTG-133
/// 会議ノートの真ん中の文書: 見出し・状態の帯・要約・アクションアイテム・議事録の本文・ここ重要・メモ。
/// 文字起こしと AI チャットは後ろ側のパネル（MeetingInspector）に出す
struct MeetingDocumentView: View {
    let meeting: Meeting
    @ObservedObject var recorder: MeetingRecorder
    /// 記録を止めたあとの処理中（議事録を作成中）
    var processing = false
    /// 検索結果から開いたときの飛び先（議事録の行・タイトル）
    var jump: MeetingJump?
    /// 根拠の時刻の印・「前後の会話を見る」を押したとき（文字起こしのその位置へ）
    var onFocusTranscript: (TranscriptFocus.Target) -> Void
    var onRegenerate: () -> Void
    var onEditSpeakers: () -> Void
    @State private var title = ""
    @FocusState private var titleFocused: Bool
    @State private var showingReminders = false

    var body: some View {
        let actionItems = meeting.resolvedActionItems
        let document = MinutesDocument(markdown: meeting.minutes ?? "", hidesActionSection: !actionItems.isEmpty)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    MeetingStatusBanners(meeting: meeting, recorder: recorder, processing: processing, onRegenerate: onRegenerate)
                    if meeting.minutes != nil {
                        minutes(document, actionItems: actionItems)
                            .opacity(regenerating ? 0.5 : 1)
                    } else if processing || regenerating {
                        MinutesSkeleton()
                    } else {
                        emptyMinutes
                    }
                    // 要件: REQ-MTG-012
                    // 設計判断: DEC-MTG-049
                    // 処理中は発言がまだないので出さない
                    if !processing, !meeting.highlightContexts().isEmpty {
                        HighlightContextsSection(meeting: meeting) { onFocusTranscript(.block($0)) }
                    }
                    // 要件: REQ-MTG-013
                    MeetingNotesSection(meeting: meeting, recorder: recorder, readOnly: processing)
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
                .textSelection(.enabled)
            }
            .onAppear { scroll(to: jump, document: document, proxy: proxy) }
            .onChange(of: jump) { _, newJump in scroll(to: newJump, document: document, proxy: proxy) }
        }
        // 要件: REQ-MTG-052
        // 設計判断: DEC-MTG-084, DEC-MTG-134（議事録の根拠の時刻の印は hanasu-time:// のリンク）
        .environment(\.openURL, OpenURLAction { url in
            guard let seconds = MeetingChat.seconds(from: url) else { return .systemAction }
            onFocusTranscript(.time(seconds))
            return .handled
        })
        .onAppear { title = meeting.title }
        .onChange(of: meeting.id) { oldID, _ in
            // 書きかけのタイトルは、元の会議に保存してから切り替える
            if titleFocused { commitTitle(for: oldID) }
            title = meeting.title
        }
        .onChange(of: meeting.title) { _, newTitle in
            if !titleFocused { title = newTitle }
        }
        .sheet(isPresented: $showingReminders) {
            ReminderExportSheet(meeting: meeting, recorder: recorder)
        }
    }

    private var regenerating: Bool { recorder.regeneratingID == meeting.id }

    // MARK: - 見出し

    // 要件: REQ-MTG-029
    // 設計判断: DEC-MTG-024, DEC-MTG-131
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            EditableTitleField(title: $title, focused: $titleFocused,
                               onCommit: { commitTitle(for: meeting.id) },
                               onCancel: { title = meeting.title })
                .disabled(processing)
            HStack(spacing: 12) {
                Text(MeetingFormat.dateAndLength(of: meeting))
                    .foregroundStyle(.secondary)
                if !meeting.speakers.isEmpty {
                    MeetingParticipantsButton(meeting: meeting, action: onEditSpeakers)
                        .disabled(processing)
                }
            }
            .font(.callout)
        }
    }

    // MARK: - 議事録

    @ViewBuilder
    private func minutes(_ document: MinutesDocument, actionItems: [ActionItem]) -> some View {
        let limit = meeting.duration
        if !document.summary.isEmpty {
            MarkdownText(lines: document.summary, highlight: jump?.terms ?? [], focusedLine: focusedMinutesLine, citationLimit: limit)
        }
        if !actionItems.isEmpty {
            ActionItemsCard(meeting: meeting, items: actionItems,
                            heading: document.hiddenActionSection.first.map { String($0.text.trimmingCharacters(in: .whitespaces).dropFirst(3)) },
                            focusedRow: focusedMinutesLine.flatMap(document.actionRow(forLine:)),
                            onJump: { onFocusTranscript(.time($0)) },
                            onReminders: { showingReminders = true })
        }
        if !document.body.isEmpty {
            MarkdownText(lines: document.body, highlight: jump?.terms ?? [], focusedLine: focusedMinutesLine, citationLimit: limit)
        }
    }

    private var emptyMinutes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("議事録はありません。"))
                .foregroundStyle(.secondary)
            if !meeting.usedUtterances.isEmpty, recorder.state == .idle {
                Button(tr("議事録を作る"), action: onRegenerate)
            }
        }
    }

    private var focusedMinutesLine: Int? {
        if case .minutes(let line) = jump?.location { return line }
        return nil
    }

    // 要件: REQ-MTG-015, REQ-MTG-050
    // 設計判断: DEC-MTG-133
    /// 検索でヒットした議事録の行へ移る（外したアクションアイテムの節の行は、カードの同じ順番の行へ）
    private func scroll(to jump: MeetingJump?, document: MinutesDocument, proxy: ScrollViewProxy) {
        guard let jump, jump.meetingID == meeting.id, case .minutes(let line) = jump.location else { return }
        let target: AnyHashable = document.actionRow(forLine: line).map { AnyHashable(ActionItemsCard.rowID($0)) }
            ?? AnyHashable(MarkdownText.lineID(line))
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))  // 中身ができてから
            withAnimation { proxy.scrollTo(target, anchor: .center) }
        }
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
}

/// 文字起こしのどこへ移るか（押すたびに token を変えて、同じ所をもう一度押しても移るようにする）
struct TranscriptFocus: Equatable {
    enum Target: Equatable {
        /// その時刻（1 秒の幅を見る）までに始まった最後の発言
        case time(Double)
        /// まとめた発言の ID
        case block(UUID)
    }

    var target: Target
    var token = UUID()
}

// MARK: - 書き方

/// 会議ノートの日時・長さの書き方（表示の言語に合わせる）
enum MeetingFormat {
    // 設計判断: DEC-MTG-131
    /// 「2026/10/26 (月) 16:33 · 25 分」。長さは時刻と見間違えないように「分」で書く
    static func dateAndLength(of meeting: Meeting) -> String {
        let date = Meeting.dateFormatter.string(from: meeting.startedAt)
        guard meeting.duration > 0 else { return date }
        return tr("%@ · %@", date, length(meeting.duration))
    }

    static func length(_ seconds: Double) -> String {
        let formatter = DateComponentsFormatter()
        var calendar = Calendar.current
        calendar.locale = UILanguage.locale
        formatter.calendar = calendar
        formatter.unitsStyle = .short
        formatter.allowedUnits = seconds < 60 ? [.second] : [.hour, .minute]
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: max(1, seconds.rounded())) ?? Meeting.clock(seconds)
    }
}

// MARK: - 参加者

// 要件: REQ-MTG-008
// 設計判断: DEC-MTG-131
/// 見出しの下の参加者（話者の色の丸と名前）。押すと話者名のシートを開く
struct MeetingParticipantsButton: View {
    let meeting: Meeting
    var action: () -> Void

    var body: some View {
        let speakers = meeting.speakers
        Button(action: action) {
            HStack(spacing: 8) {
                HStack(spacing: -6) {
                    ForEach(speakers.prefix(5), id: \.self) { speaker in
                        let name = meeting.displayName(for: speaker)
                        Text(String(name.prefix(1)))
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(MeetingSpeakerColor.color(for: speaker, in: meeting)))
                            .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
                    }
                }
                Text(speakers.map { meeting.displayName(for: $0) }.joined(separator: tr("・")))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.leading, 4)
            .padding(.trailing, 10)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.secondary.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .help(tr("話者名を変える"))
        .accessibilityLabel(tr("話者名を変える"))
    }
}

/// 話者の色（自分はアクセントの色、ほかは順に）
enum MeetingSpeakerColor {
    static func color(for speaker: String, in meeting: Meeting) -> Color {
        if speaker == "me" { return .accentColor }
        let palette: [Color] = [.orange, .green, .purple, .pink, .teal, .brown, .indigo, .mint]
        let index = meeting.speakers.filter { $0 != "me" }.firstIndex(of: speaker) ?? 0
        return palette[index % palette.count]
    }
}

// MARK: - 状態の帯

// 要件: REQ-MTG-013, REQ-MTG-045, REQ-MTG-054
// 設計判断: DEC-MTG-132, DEC-MTG-136
/// 文書の上の帯（進行中・失敗・古い議事録）。同時に起きたときは優先の高い 2 本まで出す
struct MeetingStatusBanners: View {
    let meeting: Meeting
    @ObservedObject var recorder: MeetingRecorder
    var processing: Bool
    var onRegenerate: () -> Void
    @ObservedObject private var dismissals = MeetingBannerDismissals.shared
    @State private var showingDetail = false

    var body: some View {
        let banners = items
        if !banners.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(banners.prefix(2), id: \.self) { kind in
                    banner(kind)
                }
            }
        }
    }

    private enum Kind: Hashable {
        case processing, regenerating, error(String), outdated
    }

    private var items: [Kind] {
        var list: [Kind] = []
        if processing { list.append(.processing) }
        if recorder.regeneratingID == meeting.id { list.append(.regenerating) }
        if let error = meeting.errorMessage, !processing, !dismissals.isDismissed(meeting.id, error) { list.append(.error(error)) }
        if meeting.minutesOutdated == true, meeting.minutes != nil, recorder.regeneratingID != meeting.id { list.append(.outdated) }
        return list
    }

    @ViewBuilder
    private func banner(_ kind: Kind) -> some View {
        switch kind {
        case .processing:
            StatusBanner(style: .progress, systemImage: nil, title: tr("議事録を作成中")) {
                ProcessingStagesView(stages: recorder.processingStages, current: recorder.processingStage,
                                     message: processingMessage)
            }
        case .regenerating:
            StatusBanner(style: .progress, systemImage: nil, title: regeneratingMessage,
                         subtitle: meeting.minutes != nil ? tr("終わるまで、今の議事録を出しています。") : nil)
        case .error(let message):
            StatusBanner(style: .error, systemImage: "exclamationmark.triangle.fill", title: message, lineLimit: 2) {
                HStack(spacing: 8) {
                    Button(tr("詳しく")) { showingDetail = true }
                        .popover(isPresented: $showingDetail) {
                            ScrollView {
                                Text(message)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding()
                            }
                            .frame(width: 420, height: 200)
                        }
                    if meeting.minutes == nil, recorder.state == .idle, !meeting.usedUtterances.isEmpty {
                        Button(tr("議事録を作り直す"), action: onRegenerate)
                    }
                    Button(tr("閉じる")) { dismissals.dismiss(meeting.id, message) }
                }
                .controlSize(.small)
            }
        case .outdated:
            // 設計判断: DEC-MTG-092
            StatusBanner(style: .warning, systemImage: "arrow.triangle.2.circlepath",
                         title: tr("文字起こしか、議事録に使う発言を変えました。作り直すと反映されます。")) {
                Button(tr("議事録を作り直す"), action: onRegenerate)
                    .controlSize(.small)
                    // 設計判断: DEC-MTG-091（使う発言がなければ作らない）
                    .disabled(recorder.state != .idle || meeting.usedUtterances.isEmpty)
            }
        }
    }

    private var processingMessage: String? {
        if case .processing(let message) = recorder.state { return message }
        return nil
    }

    private var regeneratingMessage: String {
        if case .processing(let message) = recorder.state { return message }
        return tr("議事録を作り直しています…")
    }
}

/// 失敗の帯を閉じた会議（アプリを終えるまで）
@MainActor
final class MeetingBannerDismissals: ObservableObject {
    static let shared = MeetingBannerDismissals()
    @Published private var dismissed: Set<String> = []

    func isDismissed(_ meetingID: String, _ message: String) -> Bool { dismissed.contains(meetingID + "\u{1F}" + message) }
    func dismiss(_ meetingID: String, _ message: String) { dismissed.insert(meetingID + "\u{1F}" + message) }
}

/// 1 本の帯。種類ごとに色と印を変え、右端（か下）に次にすることを置く
struct StatusBanner<Actions: View>: View {
    enum Style {
        case progress, warning, error, offRecord

        var tint: Color {
            switch self {
            case .progress: .accentColor
            case .warning: .orange
            case .error: .red
            case .offRecord: .purple
            }
        }
    }

    var style: Style
    /// nil なら回る印
    var systemImage: String?
    var title: String
    var subtitle: String?
    var lineLimit: Int?
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage).foregroundStyle(style.tint)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: 18)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                // 設計判断: DEC-MTG-048（fixedSize にしない。細い幅で測ったときに縦に伸びて、ウインドウの中身を押し出す）
                Text(title)
                    .font(.callout.weight(.medium))
                    .lineLimit(lineLimit ?? 4)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                actions()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(style.tint.opacity(0.09)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(style.tint.opacity(0.25)))
        .accessibilityElement(children: .contain)
    }
}

extension StatusBanner where Actions == EmptyView {
    init(style: Style, systemImage: String?, title: String, subtitle: String? = nil, lineLimit: Int? = nil) {
        self.init(style: style, systemImage: systemImage, title: title, subtitle: subtitle, lineLimit: lineLimit) { EmptyView() }
    }
}

// 要件: REQ-MTG-054
// 設計判断: DEC-MTG-136
/// 処理の段階（文字起こし → 話者の区別 → 議事録）のどこまで進んだか
struct ProcessingStagesView: View {
    let stages: [MeetingProcessingStage]
    let current: MeetingProcessingStage?
    var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ForEach(Array(stages.enumerated()), id: \.element) { index, stage in
                    if index > 0 {
                        Rectangle().fill(Color.secondary.opacity(0.3)).frame(width: 18, height: 1)
                            .accessibilityHidden(true)
                    }
                    let state = state(of: stage)
                    HStack(spacing: 4) {
                        Image(systemName: state == .done ? "checkmark.circle.fill" : (state == .current ? "circle.dotted.circle" : "circle"))
                            .foregroundStyle(state == .done ? Color.green : (state == .current ? Color.accentColor : Color.secondary))
                        Text(stage.title)
                            .fontWeight(state == .current ? .semibold : .regular)
                            .foregroundStyle(state == .pending ? Color.secondary : Color.primary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(state == .done ? tr("済み") : (state == .current ? tr("処理中") : tr("これから")))
                }
            }
            .font(.caption)
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private enum StageState { case done, current, pending }

    private func state(of stage: MeetingProcessingStage) -> StageState {
        guard let current, let currentIndex = stages.firstIndex(of: current),
              let index = stages.firstIndex(of: stage) else { return .pending }
        return index < currentIndex ? .done : (index == currentIndex ? .current : .pending)
    }
}

/// 議事録を作っている間の、議事録の骨組み
private struct MinutesSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach([0.3, 0.95, 0.8, 0.0, 0.2, 1.0, 0.9, 0.6], id: \.self) { width in
                if width == 0 {
                    Spacer().frame(height: 6)
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.12))
                        .frame(height: 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .scaleEffect(x: width, anchor: .leading)
                }
            }
        }
        .accessibilityLabel(tr("議事録を作成中です…"))
    }
}

// MARK: - アクションアイテム

// 要件: REQ-MTG-018, REQ-MTG-050, REQ-MTG-052
// 設計判断: DEC-MTG-133
/// 文書の先頭のアクションアイテムのカード（やること・担当・期限・根拠の時刻の印）
struct ActionItemsCard: View {
    let meeting: Meeting
    let items: [ActionItem]
    /// 議事録の見出し（型によって「次のアクション」など）。なければ「アクションアイテム」
    var heading: String?
    var focusedRow: Int?
    var onJump: (Double) -> Void
    var onReminders: () -> Void

    static func rowID(_ index: Int) -> String { "action-row-\(index)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(heading ?? tr("アクションアイテム")).font(.headline)
                Text("\(items.count)")
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                Spacer()
                Button(tr("リマインダーに登録…"), action: onReminders)
                    .buttonStyle(.link)
            }
            .padding(.bottom, 6)
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Divider()
                row(item)
                    .padding(.vertical, 8)
                    .background(index == focusedRow ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.12)).padding(.horizontal, -6) : nil)
                    .id(Self.rowID(index))
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.18)))
    }

    private func row(_ item: ActionItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            // 四角のチェックボックスは使わない（完了のチェックに見えて押したくなる）。リマインダーに登録済みならベルの印
            Image(systemName: item.reminderID == nil ? "circle.fill" : "bell.fill")
                .font(item.reminderID == nil ? .system(size: 5) : .caption)
                .foregroundStyle(item.reminderID == nil ? Color.secondary : Color.accentColor)
                .frame(width: 14)
                .help(item.reminderID == nil ? "" : tr("リマインダーに登録済み"))
                .accessibilityLabel(item.reminderID == nil ? "" : tr("リマインダーに登録済み"))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.task)
                let details = [item.owner.map { tr("担当 %@", $0) }, item.dueDisplay.map { tr("期限 %@", $0) }].compactMap { $0 }
                if !details.isEmpty {
                    Text(details.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let at = item.at, let seconds = MinutesCitation.seconds(of: at) {
                CitationChip(label: at, seconds: seconds, valid: MinutesCitation.isValid(seconds, duration: meeting.duration)) {
                    onJump(seconds)
                }
            }
        }
    }
}

// 要件: REQ-MTG-052
// 設計判断: DEC-MTG-134
/// 根拠の時刻の印（押すと文字起こしのその発言へ）。会議の長さを超える時刻は薄く、押せない
struct CitationChip: View {
    let label: String
    let seconds: Double
    var valid = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.monospacedDigit())
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.secondary.opacity(valid ? 0.15 : 0.06)))
                .foregroundStyle(valid ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .disabled(!valid)
        .help(valid ? tr("文字起こしの %@ の発言へ", label) : tr("会議の長さを超える時刻です（根拠の発言はありません）"))
        .accessibilityLabel(tr("根拠の発言 %@", label))
    }
}

// MARK: - ここ重要

// 要件: REQ-MTG-012
// 設計判断: DEC-MTG-049
/// 文書の「ここ重要」の欄: 印ごとに、前後の発言（30 秒前〜15 秒後）をまとめて出す。
/// 「前後の会話を見る」で、後ろ側のパネルの文字起こしのその位置へ移る
struct HighlightContextsSection: View {
    let meeting: Meeting
    var openInTranscript: (UUID) -> Void

    var body: some View {
        let contexts = meeting.highlightContexts()
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("ここ重要")).font(.headline)
            ForEach(contexts, id: \.note.id) { context in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                        Text(context.note.time.map(Meeting.clock) ?? "--:--")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(context.note.text.isEmpty ? tr("ここ重要") : context.note.text).fontWeight(.semibold)
                        Spacer()
                        if let first = context.blocks.first {
                            Button(tr("前後の会話を見る")) { openInTranscript(first.id) }
                                .controlSize(.small)
                        }
                    }
                    if context.blocks.isEmpty {
                        Text(tr("この前後（30 秒前〜15 秒後）の発言はありません")).font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(context.blocks) { block in
                        TranscriptLine(time: block.start, speaker: meeting.displayName(for: block.speaker),
                                       color: MeetingSpeakerColor.color(for: block.speaker, in: meeting), text: block.text)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.yellow.opacity(0.1)))
            }
        }
    }
}

// MARK: - メモ

// 要件: REQ-MTG-011, REQ-MTG-013
// 設計判断: DEC-MTG-136
/// 文書のメモの欄。処理の間は読むだけ（処理の結果で上書きされないように）
struct MeetingNotesSection: View {
    let meeting: Meeting
    @ObservedObject var recorder: MeetingRecorder
    var readOnly: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(tr("メモ")).font(.headline)
                if readOnly {
                    Text(tr("議事録ができたら書き足せます")).font(.caption).foregroundStyle(.secondary)
                }
            }
            if readOnly {
                let notes = meeting.allNotes
                if notes.isEmpty {
                    Text(tr("メモはありません。")).font(.callout).foregroundStyle(.secondary)
                }
                ForEach(notes) { NoteRow(note: $0) }
            } else {
                MeetingNotesEditor(meeting: meeting, recorder: recorder)
            }
        }
    }
}

// MARK: - タイトルの欄

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
            TextField(tr("タイトル"), text: $title)
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
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(Color.primary.opacity(hovering && !focused.wrappedValue ? 0.05 : 0)))
        .overlay(RoundedRectangle(cornerRadius: 8)
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
        .help(tr("クリックしてタイトルを変更"))
        .accessibilityHint(tr("タイトルを変更できます"))
    }
}

// MARK: - 議事録の Markdown

// 要件: REQ-MTG-052
/// 議事録用の簡易 Markdown 表示（見出し・箇条書き・チェックボックス・強調）。
/// citationLimit を渡すと、行末の根拠の時刻の印を押せる小さな印にする（会議の長さを超える時刻は押せない印）
struct MarkdownText: View {
    let lines: [MinutesDocument.Line]
    /// 色を付ける検索語
    var highlight: [String] = []
    /// 検索でヒットした行（背景を付ける）
    var focusedLine: Int?
    /// 会議の長さ（秒）。nil なら印を変えない
    var citationLimit: Double?

    init(lines: [MinutesDocument.Line], highlight: [String] = [], focusedLine: Int? = nil, citationLimit: Double? = nil) {
        self.lines = lines
        self.highlight = highlight
        self.focusedLine = focusedLine
        self.citationLimit = citationLimit
    }

    init(markdown: String, highlight: [String] = [], focusedLine: Int? = nil, citationLimit: Double? = nil) {
        self.init(lines: markdown.components(separatedBy: "\n").enumerated().map { MinutesDocument.Line(number: $0.offset, text: $0.element) },
                  highlight: highlight, focusedLine: focusedLine, citationLimit: citationLimit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(lines) { line in
                lineView(line.text)
                    .background(line.number == focusedLine ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.12)).padding(-4) : nil)
                    .id(Self.lineID(line.number))
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
        var attributed = (try? AttributedString(
            markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
        attributed = MeetingSearchHighlight.apply(attributed, terms: highlight)
        if let citationLimit { attributed = Self.decorateCitations(attributed, limit: citationLimit) }
        return Text(attributed)
    }

    // 要件: REQ-MTG-052
    // 設計判断: DEC-MTG-134
    /// 行の中の [12:34] を、押せる小さな印（hanasu-time:// のリンク）にする。会議の長さを超える時刻は押せない薄い印にする
    static func decorateCitations(_ attributed: AttributedString, limit: Double) -> AttributedString {
        var result = attributed
        let plain = String(attributed.characters)
        for mark in MinutesCitation.marks(in: plain).reversed() {
            let lower = plain.distance(from: plain.startIndex, to: mark.range.lowerBound)
            let upper = plain.distance(from: plain.startIndex, to: mark.range.upperBound)
            let start = result.characters.index(result.startIndex, offsetBy: lower)
            let end = result.characters.index(result.startIndex, offsetBy: upper)
            // 前の文と印の間で行が分かれないよう、語をつなぐ記号と、改行しない細い空白で囲む
            var chip = AttributedString("\u{2060}\u{202F}\(mark.label)\u{202F}")
            chip.font = .caption.monospacedDigit()
            chip.backgroundColor = Color.secondary.opacity(0.15)
            if MinutesCitation.isValid(mark.seconds, duration: limit) {
                chip.link = URL(string: "\(MeetingChat.timeLinkScheme)://\(Int(mark.seconds))")
            } else {
                chip.foregroundColor = .secondary
                chip.strikethroughStyle = .single
            }
            result.replaceSubrange(start..<end, with: chip)
        }
        return result
    }
}

// MARK: - 話者名のシート

// 要件: REQ-MTG-008
struct SpeakerNamesSheet: View {
    let meeting: Meeting
    @ObservedObject var recorder: MeetingRecorder
    @Environment(\.dismiss) private var dismiss
    @State private var names: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("話者名")).font(.headline)
            Text(tr("議事録の「話者についてのメモ」も参考にしてください。「推測」は、議事録を作るときに会話から推測して付けた名前です。変更は文字起こしに反映されます（議事録は作り直すと反映されます）。"))
                .font(.caption).foregroundStyle(.secondary)
            Form {
                ForEach(meeting.speakers, id: \.self) { speaker in
                    HStack {
                        TextField(Meeting(id: "", title: "", startedAt: Date()).displayName(for: speaker),
                                  text: Binding(get: { names[speaker] ?? "" }, set: { names[speaker] = $0 }))
                        // 要件: REQ-MTG-027
                        // 設計判断: DEC-MTG-069
                        if meeting.isInferredName(speaker), names[speaker] == meeting.speakerNames[speaker] {
                            Text(tr("推測"))
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .help(tr("会話から推測した名前です。違っていたら直してください"))
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button(tr("キャンセル")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(tr("保存")) {
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
