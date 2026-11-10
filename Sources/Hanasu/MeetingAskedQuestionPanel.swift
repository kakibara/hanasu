import AppKit
import Combine
import SwiftUI

// 設計判断: DEC-MTG-096, DEC-MTG-099
/// キーウインドウにもメインのウインドウにもならないパネル。押しても、会議ツールなど前面のアプリのキー入力を奪わない
/// （.nonactivatingPanel が防ぐのはアプリのアクティブ化だけで、.titled のパネルはそのままだとキーウインドウになる）
final class NonKeyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// 要件: REQ-MTG-047
// 設計判断: DEC-MTG-096
/// 「何を聞かれた？」の答えを出す前面のパネル。アプリをアクティブにせず、キーウインドウにならず、画面の取り込み（共有）から外す
@MainActor
final class MeetingAskedQuestionPanel {
    static let shared = MeetingAskedQuestionPanel()

    static let size = NSSize(width: 480, height: 360)
    private static let autosaveName = "HanasuAskedQuestion"

    private var panel: NSPanel?
    private var closingByApp = false
    private var cancellables: Set<AnyCancellable> = []

    var isShown: Bool { panel?.isVisible ?? false }

    func show() {
        if panel == nil {
            let panel = NonKeyPanel(
                contentRect: NSRect(origin: .zero, size: Self.size),
                styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel, .hudWindow],
                backing: .buffered, defer: false)
            panel.title = tr("何を聞かれた？")
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            // 要件: REQ-MTG-047（共有の相手に映らないようにする。取り込み方によっては映る）
            panel.sharingType = .none
            panel.minSize = NSSize(width: 360, height: 220)
            panel.contentView = FirstMouseHostingView(rootView: MeetingAskedQuestionView(model: .shared))
            panel.setFrameAutosaveName(Self.autosaveName)
            // 設計判断: DEC-COM-017
            // 初回は、字幕が出ていればそのすぐ上、なければマウスのある画面の下の中央。2 回目からは前に置いた位置
            if !panel.setFrameUsingName(Self.autosaveName) {
                panel.setFrame(Self.initialFrame(), display: false)
            }
            NotificationCenter.default.publisher(for: NSWindow.willCloseNotification, object: panel)
                .sink { [weak self] _ in
                    guard let self, !self.closingByApp else { return }
                    MeetingAskedQuestion.shared.dismiss()
                }
                .store(in: &cancellables)
            self.panel = panel
        }
        panel?.orderFrontRegardless()
    }

    func close() {
        closingByApp = true
        panel?.close()
        closingByApp = false
    }

    private static func initialFrame() -> NSRect {
        if let caption = MeetingCaptionPanel.shared.frame,
           let screen = NSScreen.screens.first(where: { $0.frame.intersects(caption) }) {
            let visible = screen.visibleFrame
            var origin = NSPoint(x: caption.midX - size.width / 2, y: caption.maxY + 8)
            origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
            origin.y = min(origin.y, visible.maxY - size.height)
            return NSRect(origin: origin, size: size)
        }
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSRect(x: visible.midX - size.width / 2, y: visible.minY + 40, width: size.width, height: size.height)
    }
}

// 要件: REQ-MTG-047
// 設計判断: DEC-MTG-096
/// 「何を聞かれた？」のパネルの中身: 見出し、相手の直近の発言（AI を待たずに出す）、AI の答え、ボタン
struct MeetingAskedQuestionView: View {
    @ObservedObject var model: MeetingAskedQuestion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let request = model.request {
                if let notice = request.notice {
                    Label(notice, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if case .unavailable = request.phase {} else {
                    recentOthers(request.recentOthers)
                    Divider()
                }
                ScrollView {
                    phaseView(request.phase)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
                footer(request)
            } else {
                Spacer()
            }
        }
        .padding(12)
        .frame(minWidth: 360, minHeight: 200)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.fill.questionmark")
                .foregroundStyle(.purple)
            Text(tr("何を聞かれた？")).font(.headline)
            if let at = model.request?.at, model.request?.meetingID.isEmpty == false {
                Text(tr("%@ の時点", "\(Meeting.clock(at))"))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func recentOthers(_ lines: [MeetingChat.Line]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tr("直近の相手の発言")).font(.caption.bold()).foregroundStyle(.secondary)
            if lines.isEmpty {
                Text(tr("まだ相手の発言がありません")).font(.callout).foregroundStyle(.secondary)
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Meeting.clock(line.time))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    // 長い発言は最後のほう（質問のあることが多い）を見せる
                    Text(line.text)
                        .font(.callout)
                        .lineLimit(2)
                        .truncationMode(.head)
                }
            }
        }
    }

    @ViewBuilder
    private func phaseView(_ phase: MeetingAskedQuestion.Phase) -> some View {
        switch phase {
        case .running:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(tr("直前に聞かれたことを探しています…"))
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button(tr("やめる")) { model.cancel() }
                    .controlSize(.small)
            }
        case .answered(let text):
            VStack(alignment: .leading, spacing: 4) {
                Label("AI", systemImage: "sparkles")
                    .font(.caption.bold())
                    .foregroundStyle(.purple)
                // 時刻は押せない（文字のまま）。元の発言は「チャットで続ける」から確かめる
                MarkdownText(markdown: text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        case .unavailable(let message):
            Label(message, systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func footer(_ request: MeetingAskedQuestion.Request) -> some View {
        HStack(spacing: 8) {
            if !request.meetingID.isEmpty {
                Button {
                    model.continueInChat()
                } label: {
                    Label(tr("チャットで続ける"), systemImage: "bubble.left.and.text.bubble.right")
                }
                .help(tr("会議ノートの AI チャットを開いて、続けて質問する"))
            }
            Spacer()
            if Self.showsRetry(request.phase) {
                Button(tr("もう一度")) { model.retry() }
                    .disabled(!model.recording)
                    .help(tr("今の時点までの会話で、もう一度探す"))
            }
            Button(tr("閉じる")) { MeetingAskedQuestionPanel.shared.close(); model.dismiss() }
        }
        .controlSize(.small)
    }

    /// 「もう一度」を出すのは、答えが出たか失敗したとき
    private static func showsRetry(_ phase: MeetingAskedQuestion.Phase) -> Bool {
        switch phase {
        case .answered, .failed: true
        case .running, .unavailable: false
        }
    }
}

// MARK: - 記録中だけのショートカット

// 設計判断: DEC-MTG-042, DEC-MTG-097
/// 会議の記録中だけ登録するグローバルショートカット（ふだんはほかのアプリのキーを奪わない）。
/// 「ここ重要」と「何を聞かれた？」で使う
@MainActor
class MeetingRecordingHotKey: ObservableObject {
    /// 登録できなかったとき（ほかのアプリと重なっているなど）の説明
    @Published private(set) var registrationError: String?

    private let hotKeys = HotKeyManager()
    private var hotKeyID: UInt32?
    private var handler: (() -> Void)?
    private var suspended = false
    private var cancellables: Set<AnyCancellable> = []
    private let isEnabled: () -> Bool
    private let combo: () -> HotKeyCombo
    private let logName: String

    init(isEnabled: @escaping () -> Bool, combo: @escaping () -> HotKeyCombo,
         changes: AnyPublisher<Void, Never>, logName: String) {
        self.isEnabled = isEnabled
        self.combo = combo
        self.logName = logName
        changes
            .sink { [weak self] _ in DispatchQueue.main.async { self?.refresh() } }
            .store(in: &cancellables)
    }

    /// 記録の開始時に呼ぶ
    func activate(_ handler: @escaping () -> Void) {
        self.handler = handler
        refresh()
    }

    /// 記録の停止時に呼ぶ
    func deactivate() {
        handler = nil
        refresh()
    }

    // 設計判断: DEC-COM-012
    /// 設定画面でショートカットを記録している間は外す
    func suspend() {
        suspended = true
        refresh()
    }

    func resume() {
        suspended = false
        refresh()
    }

    private func refresh() {
        if let hotKeyID { hotKeys.unregister(hotKeyID) }
        hotKeyID = nil
        registrationError = nil
        guard handler != nil, !suspended, isEnabled() else { return }
        let combo = combo()
        hotKeyID = hotKeys.register(combo) { [weak self] event in
            guard event == .pressed else { return }
            MainActor.assumeIsolated { self?.handler?() }
        }
        if hotKeyID == nil {
            registrationError = tr("ショートカット %@ を登録できませんでした（ほかのショートカットと重なっている可能性があります）", "\(combo.displayString)")
            appLog.error("\(self.logName, privacy: .public) hot key registration failed")
        }
    }
}

// 要件: REQ-MTG-047
// 設計判断: DEC-MTG-097
/// 「何を聞かれた？」のグローバルショートカット。会議の記録中だけ登録する
@MainActor
final class MeetingAskedHotKey: MeetingRecordingHotKey {
    static let shared = MeetingAskedHotKey()

    private init() {
        let settings = MeetingNotesSettings.shared
        super.init(
            isEnabled: { settings.askedHotKeyEnabled },
            combo: { settings.askedHotKey },
            changes: Publishers.Merge(
                settings.$askedHotKey.removeDuplicates().dropFirst().map { _ in () },
                settings.$askedHotKeyEnabled.removeDuplicates().dropFirst().map { _ in () })
                .eraseToAnyPublisher(),
            logName: "asked")
    }
}

// 要件: REQ-MTG-047
// 設計判断: DEC-MTG-097
/// 設定の「会議」に置く、「何を聞かれた？」のショートカットの設定
struct MeetingAskedSettingsSection: View {
    @ObservedObject private var settings = MeetingNotesSettings.shared
    @ObservedObject private var hotKey = MeetingAskedHotKey.shared
    var onBeginShortcutRecording: () -> Void = {}
    var onEndShortcutRecording: () -> Void = {}

    var body: some View {
        Section {
            Toggle(tr("記録中に「何を聞かれた？」のショートカットを使う"), isOn: $settings.askedHotKeyEnabled)
            LabeledContent(tr("「何を聞かれた？」")) {
                ShortcutRecorder(
                    combo: $settings.askedHotKey,
                    defaultCombo: MeetingNotesSettings.defaultAskedHotKey,
                    kind: .asked,
                    onBeginRecording: onBeginShortcutRecording,
                    onEndRecording: onEndShortcutRecording)
            }
            .disabled(!settings.askedHotKeyEnabled)
            if settings.askedHotKeyEnabled, let error = hotKey.registrationError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text(tr("会議中の AI チャット"))
        } footer: {
            Text(tr("会議ツールを前面にしたまま、字幕の「何を聞かれた？」かこのショートカットで、直前に聞かれたことと背景を AI がまとめて前面のパネルに出します（直近 10 分の会話を、設定の「AI」で会議に選んだ AI に送ります）。ショートカットは記録中だけ有効です。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
