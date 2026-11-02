import AppKit
import SwiftUI

@MainActor
final class HUDModel: ObservableObject {
    enum Phase: Equatable {
        case preparing(String)
        case recording
        case processing
        case done(String)
        case error(String)
    }

    @Published var phase: Phase = .recording
    @Published var transcript = ""
    @Published var startedAt = Date()
}

/// 画面下部に出る小さな状態表示。入力先アプリのフォーカスを奪わない。
@MainActor
final class HUDController {
    let model = HUDModel()
    private let panel: NSPanel
    private var hideTask: Task<Void, Never>?

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 112),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let hosting = NSHostingView(rootView: HUDView(model: model))
        hosting.sizingOptions = []
        panel.contentView = hosting
    }

    func show(_ phase: HUDModel.Phase) {
        hideTask?.cancel()
        if case .preparing = phase {
            model.transcript = ""
        }
        if phase == .recording {
            model.startedAt = Date()
        }
        model.phase = phase
        position()
        panel.orderFrontRegardless()

        switch phase {
        case .done: hide(after: 1.2)
        case .error: hide(after: 4)
        default: break
        }
    }

    func updateTranscript(_ text: String) {
        model.transcript = text
    }

    func hide(after delay: TimeInterval = 0) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            self?.panel.orderOut(nil)
        }
    }

    private func position() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 72))
    }
}

private struct HUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                statusIcon
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer()
                if model.phase == .recording {
                    TimelineView(.periodic(from: model.startedAt, by: 1)) { context in
                        Text(elapsed(at: context.date))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Text("Esc で取消").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            if let detail {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 440, height: 112, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12)))
    }

    @ViewBuilder private var statusIcon: some View {
        switch model.phase {
        case .recording:
            Image(systemName: "record.circle.fill")
                .foregroundStyle(.red)
                .symbolEffect(.pulse)
        case .preparing, .processing:
            ProgressView().controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    private var title: String {
        switch model.phase {
        case .preparing(let message): message
        case .recording: "録音中"
        case .processing: "Gemini で整えています…"
        case .done(let message): message
        case .error: "エラー"
        }
    }

    private var detail: String? {
        switch model.phase {
        case .recording: model.transcript.isEmpty ? "話してください…" : model.transcript
        case .processing: model.transcript.isEmpty ? nil : model.transcript
        case .error(let message): message
        case .preparing, .done: nil
        }
    }

    private func elapsed(at date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(model.startedAt)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
