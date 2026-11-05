import AppKit
import SwiftUI

// 要件: REQ-MTG-009
// 設計判断: DEC-MTG-033
/// 「会議を記録しますか？」「記録を止めますか？」を出す、前面に出ないパネル（画面の右上）。
/// 会議アプリのフォーカスを奪わないよう nonactivatingPanel にし、1 回のクリックでボタンが押せるようにする。
@MainActor
final class MeetingSuggestionPanel {
    enum Suggestion: Equatable {
        /// 会議アプリがマイクを使い始めた
        case start(MeetingApp)
        /// 記録中に、会議アプリがマイクを止めた
        case stop(MeetingApp, startedAt: Date)

        var kind: Kind {
            switch self {
            case .start: .start
            case .stop: .stop
            }
        }
    }

    enum Kind { case start, stop }
    enum Action { case accept, dismiss }

    /// 返事がないまま出し続けない。時間がたったら「今回はしない」「続ける」として閉じる
    static let timeout: TimeInterval = 120

    var onAction: ((Action) -> Void)?
    /// CLI の確認用。画面に出さず、音も鳴らさない
    var isHeadless = false
    private(set) var suggestion: Suggestion?
    var kind: Kind? { suggestion?.kind }

    private let model = MeetingSuggestionModel()
    private let panel: NSPanel
    private var timeoutTask: Task<Void, Never>?

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: MeetingSuggestionView.width, height: 100),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // 全画面の会議アプリの上にも出す
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let hosting = SuggestionHostingView(rootView: MeetingSuggestionView(model: model) { [weak self] action in
            self?.onAction?(action)
        })
        hosting.sizingOptions = []
        panel.contentView = hosting
    }

    func show(_ suggestion: Suggestion) {
        self.suggestion = suggestion
        model.suggestion = suggestion
        resize()
        position()
        if !isHeadless {
            panel.orderFrontRegardless()
            if AppSettings.shared.playSounds { NSSound(named: "Glass")?.play() }
        }
        appLog.notice("meeting suggestion shown: \(String(describing: suggestion), privacy: .public)")

        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.timeout))
            guard !Task.isCancelled, let self, self.suggestion == suggestion else { return }
            self.onAction?(.dismiss)
        }
    }

    func hide() {
        timeoutTask?.cancel()
        timeoutTask = nil
        suggestion = nil
        panel.orderOut(nil)
        // 設計判断: DEC-COM-016
        // 「記録を止めますか？」の経過時間（TimelineView）が、隠したパネルの中で動き続けないよう中身も消す
        model.suggestion = nil
    }

    /// 見た目の確認用に、提案を PNG にする（画面には出さない）
    func snapshotPNG(_ suggestion: Suggestion) -> Data? {
        model.suggestion = suggestion
        resize()
        guard let view = panel.contentView else { return nil }
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    private func resize() {
        guard let view = panel.contentView else { return }
        // 表示用のビューは大きさを自分で決めない設定（sizingOptions = []）なので、同じ内容の別のビューで測る
        let size = NSHostingView(rootView: MeetingSuggestionView(model: model) { _ in }).fittingSize
        panel.setContentSize(NSSize(width: MeetingSuggestionView.width, height: max(60, size.height)))
        view.frame = NSRect(origin: .zero, size: panel.frame.size)
    }

    /// 通知と同じく、メインの画面の右上に出す
    private func position() {
        guard let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.maxX - size.width - 16, y: visible.maxY - size.height - 12))
    }
}

@MainActor
final class MeetingSuggestionModel: ObservableObject {
    @Published var suggestion: MeetingSuggestionPanel.Suggestion?
}

/// 前面にないパネルでも、1 回のクリックでボタンが押せるようにする
private final class SuggestionHostingView: NSHostingView<MeetingSuggestionView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct MeetingSuggestionView: View {
    static let width: CGFloat = 360

    @ObservedObject var model: MeetingSuggestionModel
    var onAction: (MeetingSuggestionPanel.Action) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .semibold))
                detail
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                switch model.suggestion {
                case .start?:
                    Text(tr("録音する前に、参加者の了承を得てください。"))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                case .stop(_, let startedAt)?:
                    TimelineView(.periodic(from: startedAt, by: 1)) { context in
                        Text(tr("記録中 %@", "\(Meeting.clock(context.date.timeIntervalSince(startedAt)))"))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                case nil:
                    EmptyView()
                }
                HStack(spacing: 8) {
                    Spacer()
                    button(secondaryLabel, prominent: false) { onAction(.dismiss) }
                    button(primaryLabel, prominent: true) { onAction(.accept) }
                }
                .padding(.top, 6)
            }
        }
        .padding(14)
        .frame(width: Self.width, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12)))
    }

    private var app: MeetingApp? {
        switch model.suggestion {
        case .start(let app)?, .stop(let app, _)?: app
        case nil: nil
        }
    }

    private var title: String {
        model.suggestion?.kind == .stop ? tr("記録を止めますか？") : tr("会議を記録しますか？")
    }

    @ViewBuilder private var detail: some View {
        switch model.suggestion {
        case .start(let app)?:
            Text(app.isBrowser
                 ? tr("%@ がマイクを使い始めました。ブラウザの会議（Google Meet など）かもしれません。", "\(app.label)")
                 : tr("%@ がマイクを使い始めました。", "\(app.label)"))
        case .stop(let app, _)?:
            Text(tr("%@ がマイクを使い終えました。止めると議事録を作ります。", "\(app.label)"))
        case nil:
            EmptyView()
        }
    }

    private var primaryLabel: String { model.suggestion?.kind == .stop ? tr("記録を止める") : tr("記録する") }
    private var secondaryLabel: String { model.suggestion?.kind == .stop ? tr("続ける") : tr("今回はしない") }

    private var icon: some View {
        ZStack(alignment: .bottomTrailing) {
            if let image = app.flatMap(Self.appIcon) {
                Image(nsImage: image).resizable().frame(width: 40, height: 40)
            } else {
                Image(systemName: "person.2.wave.2")
                    .font(.system(size: 22))
                    .frame(width: 40, height: 40)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            Image(systemName: model.suggestion?.kind == .stop ? "stop.circle.fill" : "record.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(.white, .red)
                .background(Circle().fill(.background).padding(1))
                .offset(x: 4, y: 4)
        }
    }

    /// 前面にないパネルでも押せるよう、AppKit の部品ではなくボタンで作る（HUD と同じ）
    private func button(_ label: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: prominent ? .semibold : .regular))
                .foregroundStyle(prominent ? Color.white : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(prominent ? AnyShapeStyle(primaryColor) : AnyShapeStyle(.quaternary), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var primaryColor: Color { model.suggestion?.kind == .stop ? .red : .accentColor }

    private static func appIcon(_ app: MeetingApp) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.mainBundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
