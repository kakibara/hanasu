import AppKit
import Combine
import SwiftUI

// MARK: - 確かめるダイアログの文

// 要件: REQ-MTG-055, REQ-MTG-056
// 設計判断: DEC-MTG-142
/// 録音を消す前のダイアログの文。残るものを文字起こしの状態で書き分ける
enum MeetingAudioDeleteText {
    static func title(for meeting: Meeting) -> String {
        tr("「%@」の録音を削除しますか？", meeting.title)
    }

    static func message(for meeting: Meeting, size: Int64) -> String {
        [tr("録音（%@）を完全に削除します。", MeetingAudioCleanup.formatSize(size)),
         remains(MeetingAudioCleanup.transcriptState(of: meeting)),
         tr("元に戻せません。")].joined(separator: "\n")
    }

    static func remains(_ state: MeetingTranscriptState) -> String {
        switch state {
        case .complete:
            return tr("議事録・文字起こし・メモは残ります。")
        case .partial(let failed) where failed == [.me]:
            return tr("自分の文字起こしはありません。その分の会話の記録は残りません。")
        case .partial(let failed) where failed == [.others]:
            return tr("相手の文字起こしはありません。その分の会話の記録は残りません。")
        case .partial:
            return tr("文字起こしが欠けている部分があります。その分の会話の記録は残りません。")
        case .none:
            return tr("この会議には文字起こしがありません。録音を消すと、会話の記録は残りません。")
        }
    }

    /// 押せないときのヘルプ
    @MainActor
    static func disabledReason(_ meeting: Meeting, recorder: MeetingRecorder) -> String? {
        if meeting.id == recorder.current?.id { return tr("記録中・処理中は録音を削除できません") }
        if !MeetingStore.hasAudio(meeting) { return tr("この会議には録音が残っていません") }
        return nil
    }

    static func failureMessage(_ failures: [(title: String, file: String, reason: String)]) -> String {
        failures.map { "\($0.title) — \($0.file): \($0.reason)" }.joined(separator: "\n")
    }
}

// MARK: - 記録中の切り替え

// 要件: REQ-MTG-010, REQ-MTG-054
// 設計判断: DEC-MTG-139
/// 記録中のツールバー: この会議の録音を、文字起こしのあとに削除するか（既定の設定は変えない）
struct LiveDeleteAudioToggle: View {
    @ObservedObject var recorder: MeetingRecorder

    var body: some View {
        let on = recorder.current?.deleteAudioAfterTranscription == true
        Toggle(isOn: Binding(get: { on }, set: { recorder.setDeleteAudioAfterTranscription($0) })) {
            Label(tr("録音を削除"), systemImage: on ? "trash.fill" : "trash")
        }
        .toggleStyle(.button)
        .tint(on ? .orange : nil)
        .disabled(recorder.state != .recording)
        .help(on ? tr("この会議の録音は、文字起こしのあとに削除します（押すと残す）")
                 : tr("この会議の録音は残します（押すと、文字起こしのあとに削除）"))
        .accessibilityLabel(tr("この会議の録音を文字起こしのあとに削除"))
    }
}

// MARK: - 録音の管理

// 要件: REQ-MTG-056
// 設計判断: DEC-MTG-141
@MainActor
final class MeetingAudioManagerModel: ObservableObject {
    @Published var entries: [MeetingAudioEntry] = []
    @Published var selected: Set<String> = []
    @Published var loaded = false
    var now: () -> Date = { Date() }
    private var generation = 0

    func reload(recorder: MeetingRecorder) {
        generation += 1
        let token = generation
        let meetings = recorder.meetings
        let currentID = recorder.current?.id
        Task {
            let entries = await Task.detached(priority: .userInitiated) {
                MeetingAudioCleanup.entries(meetings, excluding: currentID, directory: MeetingStore.directory(for:))
            }.value
            guard token == generation else { return }
            // 同じ結果なら入れない（描き直し → 数え直し、の輪にしない）
            if self.entries != entries { self.entries = entries }
            let kept = selected.intersection(entries.map(\.id))
            if kept != selected { selected = kept }
            if !loaded { loaded = true }
        }
    }

    var selectedEntries: [MeetingAudioEntry] { entries.filter { selected.contains($0.id) } }
    var older: (targets: [MeetingAudioEntry], skipped: [MeetingAudioEntry]) {
        MeetingAudioCleanup.bulkTargets(entries, olderThan: MeetingAudioCleanup.olderThanDays, now: now())
    }
    var all: (targets: [MeetingAudioEntry], skipped: [MeetingAudioEntry]) {
        MeetingAudioCleanup.bulkTargets(entries, olderThan: nil, now: now())
    }
}

/// 録音の管理で、確かめている削除
struct MeetingAudioPendingDeletion: Identifiable {
    enum Kind { case selected, older, all }
    let kind: Kind
    let targets: [MeetingAudioEntry]
    let skipped: [MeetingAudioEntry]
    var id: Kind { kind }

    var title: String {
        switch kind {
        case .selected: tr("選んだ %@ 件の録音を削除しますか？", "\(targets.count)")
        case .older: tr("30 日より前の %@ 件の録音を削除しますか？", "\(targets.count)")
        case .all: tr("すべての録音（%@ 件）を削除しますか？", "\(targets.count)")
        }
    }

    var message: String {
        var lines = [tr("合計 %@ の録音を完全に削除します。議事録・文字起こし・メモは残ります。",
                        MeetingAudioCleanup.formatSize(MeetingAudioCleanup.totalSize(targets)))]
        let incomplete = targets.filter { $0.state != .complete }
        if !incomplete.isEmpty {
            lines.append(tr("このうち %@ 件は文字起こしが欠けているため、その分の会話の記録は残りません。", "\(incomplete.count)"))
        }
        if !skipped.isEmpty {
            lines.append(tr("文字起こしが欠けている %@ 件（%@）は残します。選んで消せます。",
                            "\(skipped.count)", MeetingAudioCleanup.formatSize(MeetingAudioCleanup.totalSize(skipped))))
        }
        lines.append(tr("元に戻せません。"))
        return lines.joined(separator: "\n")
    }
}

// 要件: REQ-MTG-056
// 設計判断: DEC-MTG-141, DEC-MTG-142
/// 録音の管理の画面: 録音が残る会議の一覧と、選んで・30 日より前・すべての削除
struct MeetingAudioManagerView: View {
    @ObservedObject var recorder: MeetingRecorder
    @ObservedObject var model: MeetingAudioManagerModel
    /// 確認用の描き出しでは読み込まない（model に入れた会議を出す）
    var loadsFromRecorder = true
    @State private var pending: MeetingAudioPendingDeletion?
    @State private var failureMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            Divider()
            list
            Divider()
            footer
                .padding(16)
        }
        .frame(minWidth: 560, minHeight: 420)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { if loadsFromRecorder { model.reload(recorder: recorder) } }
        .onReceive(recorder.$meetings) { _ in if loadsFromRecorder { model.reload(recorder: recorder) } }
        .onChange(of: recorder.audioRevision) { if loadsFromRecorder { model.reload(recorder: recorder) } }
        .onChange(of: recorder.current?.id) { if loadsFromRecorder { model.reload(recorder: recorder) } }
        .confirmationDialog(pending?.title ?? "", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            presenting: pending) { deletion in
            Button(tr("削除"), role: .destructive) { delete(deletion) }
            Button(tr("キャンセル"), role: .cancel) {}
        } message: { deletion in
            Text(deletion.message)
        }
        .alert(tr("削除できなかった録音があります"), isPresented: Binding(get: { failureMessage != nil }, set: { if !$0 { failureMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(failureMessage ?? "")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("録音の管理")).font(.headline)
                Text(summary).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var summary: String {
        guard model.loaded else { return tr("録音を数えています…") }
        return MeetingAudioSummary.text(model.entries)
    }

    @ViewBuilder
    private var list: some View {
        if model.loaded, model.entries.isEmpty {
            ContentUnavailableView(tr("録音はありません"), systemImage: "waveform",
                                   description: Text(tr("録音が残っている会議はありません。")))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(model.entries) { entry in
                MeetingAudioEntryRow(entry: entry, selected: Binding(
                    get: { model.selected.contains(entry.id) },
                    set: { on in if on { model.selected.insert(entry.id) } else { model.selected.remove(entry.id) } }))
            }
            .listStyle(.inset)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button(tr("選んだ録音を削除…")) {
                    pending = MeetingAudioPendingDeletion(kind: .selected, targets: model.selectedEntries, skipped: [])
                }
                .disabled(model.selected.isEmpty)
                Spacer()
                Button(tr("30 日より前の録音を削除…")) {
                    let older = model.older
                    pending = MeetingAudioPendingDeletion(kind: .older, targets: older.targets, skipped: older.skipped)
                }
                .disabled(model.older.targets.isEmpty)
                Button(tr("すべての録音を削除…")) {
                    let all = model.all
                    pending = MeetingAudioPendingDeletion(kind: .all, targets: all.targets, skipped: all.skipped)
                }
                .disabled(model.all.targets.isEmpty)
            }
            Text(tr("「30 日より前」と「すべて」では、文字起こしが欠けている会議の録音は消しません。保存先を iCloud Drive などで同期している場合は、同期先の削除済みの項目にしばらく残ることがあります。"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
    }

    private func delete(_ deletion: MeetingAudioPendingDeletion) {
        let failures = recorder.deleteAudio(deletion.targets.map(\.meeting))
        model.selected.subtract(deletion.targets.map(\.id))
        if !failures.isEmpty {
            failureMessage = tr("%@ 件のファイルを削除できませんでした。", "\(failures.count)") + "\n" + MeetingAudioDeleteText.failureMessage(failures)
        }
        model.reload(recorder: recorder)
    }
}

/// 録音の管理の 1 行
struct MeetingAudioEntryRow: View {
    let entry: MeetingAudioEntry
    @Binding var selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Toggle(isOn: $selected) { EmptyView() }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .accessibilityLabel(entry.meeting.title)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.meeting.title).lineLimit(1).truncationMode(.tail)
                Text(entry.meeting.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let badge {
                Text(badge)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.18), in: Capsule())
                    .foregroundStyle(.orange)
                    .help(MeetingAudioDeleteText.remains(entry.state))
            }
            Text(MeetingAudioCleanup.formatSize(entry.size))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 64, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .onTapGesture { selected.toggle() }
    }

    private var badge: String? {
        switch entry.state {
        case .complete: nil
        case .partial: tr("一部の文字起こしなし")
        case .none: tr("文字起こしなし")
        }
    }
}

/// 「12 件・1.4 GB（うち 2 件は文字起こしが欠けています）」
enum MeetingAudioSummary {
    static func text(_ entries: [MeetingAudioEntry]) -> String {
        guard !entries.isEmpty else { return tr("録音はありません") }
        var text = tr("%@ 件・%@", "\(entries.count)", MeetingAudioCleanup.formatSize(MeetingAudioCleanup.totalSize(entries)))
        let incomplete = entries.filter { $0.state != .complete }.count
        if incomplete > 0 { text += tr("（うち %@ 件は文字起こしが欠けています）", "\(incomplete)") }
        return text
    }
}

// MARK: - ウインドウ

// 要件: REQ-MTG-056
// 設計判断: DEC-MTG-141
/// 録音の管理のウインドウ。設定と会議ノートのメニューから開く（AppDelegate が recorder を渡す）
@MainActor
enum MeetingAudioManagerWindow {
    static weak var recorder: MeetingRecorder?
    private static var window: NSWindow?
    private static let model = MeetingAudioManagerModel()

    static func show() {
        guard let recorder else { return }
        if let window {
            model.reload(recorder: recorder)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: MeetingAudioManagerView(recorder: recorder, model: model))
        let window = NSWindow(contentViewController: hosting)
        window.title = tr("録音の管理")
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 640, height: 520))
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - 設定の行

// 要件: REQ-MTG-010, REQ-MTG-056, REQ-MTG-057
// 設計判断: DEC-MTG-139, DEC-MTG-143
/// 設定「会議」の録音の項目: 文字起こしのあとに削除・残す期間・件数と「録音を管理…」
struct MeetingAudioSettingsRows: View {
    @ObservedObject var settings: AppSettings
    /// 確認用の描き出しでは、件数と合計を固定する
    var fixedEntries: [MeetingAudioEntry]?
    @State private var entries: [MeetingAudioEntry] = []
    @State private var pendingRetention: Int?
    @State private var pendingTargets: (targets: [MeetingAudioEntry], skipped: [MeetingAudioEntry]) = ([], [])

    var body: some View {
        Toggle(isOn: Binding(get: { !settings.keepMeetingAudio }, set: { settings.keepMeetingAudio = !$0 })) {
            Text(tr("文字起こしのあとに録音を削除する"))
            Text(tr("記録のたびの既定です。会議ノートの記録の設定と、記録中のツールバーで、会議ごとに変えられます。文字起こしが欠けた会議の録音は残します。"))
        }
        Picker(selection: Binding(get: { settings.meetingAudioRetentionDays }, set: { requestRetention($0) })) {
            ForEach(MeetingAudioCleanup.retentionOptions, id: \.self) { days in
                Text(days == 0 ? tr("無期限") : tr("%@ 日", "\(days)")).tag(days)
            }
        } label: {
            Text(tr("録音を残す期間"))
            Text(tr("過ぎた録音は、起動時と記録のあとに自動で削除します。会議ごとに「残す」にした録音も消えます。文字起こしが欠けた会議の録音は消しません。"))
        }
        LabeledContent {
            Button(tr("録音を管理…")) { MeetingAudioManagerWindow.show() }
                .disabled(fixedEntries != nil)
        } label: {
            Text(tr("残っている録音"))
            Text(MeetingAudioSummary.text(fixedEntries ?? entries))
        }
        .onAppear(perform: reload)
        .onReceive(recorderMeetings) { _ in reload() }
        .confirmationDialog(retentionTitle, isPresented: Binding(get: { pendingRetention != nil }, set: { if !$0 { pendingRetention = nil } })) {
            Button(tr("変更して削除"), role: .destructive) { applyRetention() }
            Button(tr("キャンセル"), role: .cancel) { pendingRetention = nil }
        } message: {
            Text(retentionMessage)
        }
    }

    private var recorderMeetings: AnyPublisher<Int, Never> {
        guard let recorder = MeetingAudioManagerWindow.recorder else { return Empty().eraseToAnyPublisher() }
        return recorder.$audioRevision.combineLatest(recorder.$meetings).map { $0.0 }.eraseToAnyPublisher()
    }

    private func reload() {
        guard fixedEntries == nil, let recorder = MeetingAudioManagerWindow.recorder else { return }
        let meetings = recorder.meetings
        let currentID = recorder.current?.id
        Task {
            let loaded = await Task.detached(priority: .utility) {
                MeetingAudioCleanup.entries(meetings, excluding: currentID, directory: MeetingStore.directory(for:))
            }.value
            // 同じ結果なら入れない。recorderMeetings は描くたびに作り直すので、つなぎ直した直後に今の値が届いても、描き直しと数え直しの輪にしない
            if loaded != entries { entries = loaded }
        }
    }

    // 設計判断: DEC-MTG-143（期間を短くして、今すぐ消える録音があるときだけ確かめる）
    private func requestRetention(_ days: Int) {
        // 裏で数え終える前でも確かめを飛ばさないよう、その場で数え直す
        let current = MeetingAudioManagerWindow.recorder.map {
            MeetingAudioCleanup.entries($0.meetings, excluding: $0.current?.id, directory: MeetingStore.directory(for:))
        } ?? entries
        let targets = MeetingAudioCleanup.expired(current, retentionDays: days, now: Date())
        if days == 0 || targets.targets.isEmpty || fixedEntries != nil {
            settings.meetingAudioRetentionDays = days
            return
        }
        pendingTargets = targets
        pendingRetention = days
    }

    private func applyRetention() {
        guard let days = pendingRetention else { return }
        settings.meetingAudioRetentionDays = days
        pendingRetention = nil
        MeetingAudioManagerWindow.recorder?.deleteAudio(pendingTargets.targets.map(\.meeting))
    }

    private var retentionTitle: String {
        tr("%@ 件の録音がすぐに削除されます", "\(pendingTargets.targets.count)")
    }

    private var retentionMessage: String {
        var lines = [tr("残す期間を %@ 日にすると、それより前の録音（合計 %@）を完全に削除します。議事録・文字起こし・メモは残ります。",
                        "\(pendingRetention ?? 0)", MeetingAudioCleanup.formatSize(MeetingAudioCleanup.totalSize(pendingTargets.targets)))]
        if !pendingTargets.skipped.isEmpty {
            lines.append(tr("文字起こしが欠けている %@ 件（%@）は残します。選んで消せます。", "\(pendingTargets.skipped.count)",
                            MeetingAudioCleanup.formatSize(MeetingAudioCleanup.totalSize(pendingTargets.skipped))))
        }
        lines.append(tr("元に戻せません。"))
        return lines.joined(separator: "\n")
    }
}

// MARK: - 確認用の描き出し

/// 設定の描き出し（--render-settings）で、残っている録音の件数と合計を固定する（本物の保存先を数えない）
@MainActor
enum SettingsRenderOverrides {
    static var meetingAudioEntries: [MeetingAudioEntry]?
}

@MainActor
enum MeetingAudioManagerRender {
    /// 架空の会議で、録音の管理の画面を PNG にする（manager.png、manager-empty.png）
    static func render(to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let now = MeetingAudioCLI.now
        let model = MeetingAudioManagerModel()
        model.now = { now }
        model.entries = sampleEntries()
        model.selected = ["a"]
        model.loaded = true
        let recorder = MeetingRecorder()
        recorder.showMeetingsForRendering([])
        try write(MeetingAudioManagerView(recorder: recorder, model: model, loadsFromRecorder: false),
                  size: NSSize(width: 640, height: 520), to: dir.appendingPathComponent("manager.png"))
        let empty = MeetingAudioManagerModel()
        empty.loaded = true
        try write(MeetingAudioManagerView(recorder: recorder, model: empty, loadsFromRecorder: false),
                  size: NSSize(width: 640, height: 520), to: dir.appendingPathComponent("manager-empty.png"))
        print("描き出し: \(dir.path)")
    }

    /// 架空の会議 5 件（そろった会議・一部が欠けた会議・文字起こしのない会議）
    static func sampleEntries() -> [MeetingAudioEntry] {
        func entry(_ id: String, _ title: String, daysAgo: Double, size: Int64, utterances: Int = 2,
                   status: Meeting.Status = .done, failed: [MeetingChannel]? = nil) -> MeetingAudioEntry {
            var meeting = MeetingAudioCLI.meeting(id, daysAgo: daysAgo, utterances: utterances, status: status, failed: failed)
            meeting.title = title
            return MeetingAudioEntry(meeting: meeting, size: size, state: MeetingAudioCleanup.transcriptState(of: meeting))
        }
        return [
            entry("a", tr("週次定例"), daysAgo: 1, size: 18_400_000),
            entry("b", tr("顧客ヒアリング"), daysAgo: 12, size: 52_300_000),
            entry("c", tr("採用面談"), daysAgo: 35, size: 31_000_000, failed: [.others]),
            entry("d", tr("全社会議"), daysAgo: 48, size: 230_500_000),
            entry("e", tr("記録の途中で終わった会議"), daysAgo: 70, size: 9_800_000, utterances: 0, status: .failed),
        ]
    }

    private static func write(_ view: some View, size: NSSize, to url: URL) throws {
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = .windowBackgroundColor
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
