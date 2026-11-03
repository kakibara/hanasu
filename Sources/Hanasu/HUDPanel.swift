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
    /// 英訳モードで録音しているか
    @Published var translating = false
    /// HUD の「日本語／English」を押したとき。録音を止めた時点の選択で出力の言語が決まる
    var onSelectTranslating: ((Bool) -> Void)?
    // 要件: REQ-DIC-012
    // 設計判断: DEC-DIC-101
    /// 選択を声で編集しているときの補足（「選択 120 文字」など）。nil なら通常の音声入力
    @Published var editBadge: String?
    /// 録音を止めてからまとめて文字起こしするエンジン（Whisper / Gemini）。nil なら Mac 標準（途中経過が出る）
    @Published var batchEngine: TranscriptionEngine?
    /// 録音中の音量（0〜1。batchEngine があるときの音量の目安）
    @Published var level: Float = 0
    /// まとめての文字起こしをしている間は true（「Whisper で文字起こししています…」）
    @Published var transcribing = false
    /// HUD の「停止」を押したとき（ショートカットをもう一度押したときと同じく、録音を止めて入力する）
    var onStop: (() -> Void)?
    /// HUD の「取消」を押したとき（Esc と同じ）
    var onCancel: (() -> Void)?

    /// 準備中と録音中は、出力の言語を選べる
    var canChooseLanguage: Bool {
        switch phase {
        // 編集モードでは、出力の言語は話した指示で決まる
        case .preparing, .recording: editBadge == nil
        default: false
        }
    }

    // 設計判断: DEC-DIC-025
    /// 準備中と録音中は、ボタン（言語の切り替え・停止・取消）のクリックを受け取る
    var acceptsClicks: Bool {
        switch phase {
        case .preparing, .recording: true
        default: false
        }
    }
}

// 設計判断: DEC-DIC-025
/// 前面にないパネルでも、1 回のクリックでボタンが押せるようにする
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// 要件: REQ-DIC-002
// 設計判断: DEC-DIC-016
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
        let hosting = FirstMouseHostingView(rootView: HUDView(model: model))
        hosting.sizingOptions = []
        panel.contentView = hosting
    }

    func show(_ phase: HUDModel.Phase) {
        hideTask?.cancel()
        if case .preparing = phase {
            model.transcript = ""
            model.level = 0
            model.transcribing = false
        }
        if phase == .recording {
            model.startedAt = Date()
        }
        model.phase = phase
        // ボタンを押せる間だけクリックを受け取る。パネルは前面に出ないので、入力先のフォーカスは動かない
        panel.ignoresMouseEvents = !model.acceptsClicks
        position()
        panel.orderFrontRegardless()

        switch phase {
        case .done: hide(after: 1.2)
        case .error: hide(after: 4)
        default: break
        }
    }

    /// 見た目の確認用に、今の表示を PNG にする
    func snapshotPNG() -> Data? {
        guard let view = panel.contentView else { return nil }
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
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
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                if let editBadge {
                    Text(editBadge)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                if model.canChooseLanguage {
                    LanguageSwitch(translating: model.translating) { model.onSelectTranslating?($0) }
                }
                Spacer()
                if model.phase == .recording {
                    TimelineView(.periodic(from: model.startedAt, by: 1)) { context in
                        Text(elapsed(at: context.date))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Button { model.onCancel?() } label: {
                        Text("取消").font(.system(size: 11)).foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("録音を取り消します（Esc）")
                    StopButton { model.onStop?() }
                }
            }
            if model.phase == .recording, let engine = model.batchEngine, model.transcript.isEmpty {
                // 途中経過が出ないエンジンでは、声が届いているかを音量で示す
                HStack(spacing: 8) {
                    LevelMeter(level: model.level)
                    Text(model.editBadge != nil
                         ? "指示を話してください。止めてから \(engine.shortName) で文字起こしします"
                         : "止めてから \(engine.shortName) で文字起こしします（録音中は文字が出ません）")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } else if let detail {
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
        case .recording:
            (model.editBadge == nil ? "録音中" : "編集モード") + (model.batchEngine.map { "（\($0.shortName)）" } ?? "")
        case .processing:
            if model.transcribing, let engine = model.batchEngine { "\(engine.shortName) で文字起こししています…" }
            else if model.editBadge != nil { "Gemini で書き換えています…" }
            else if model.translating { "Gemini で英語に翻訳しています…" }
            else { "Gemini で整えています…" }
        case .done(let message): message
        case .error: "エラー"
        }
    }

    /// 編集モードの補足は、作業中（準備・録音・書き換え）だけ出す
    private var editBadge: String? {
        guard let badge = model.editBadge, !badge.isEmpty else { return nil }
        switch model.phase {
        case .preparing, .recording, .processing: return badge
        case .done, .error: return nil
        }
    }

    private var detail: String? {
        switch model.phase {
        case .recording:
            if !model.transcript.isEmpty { model.transcript }
            else if model.editBadge != nil { "指示を話してください（例: もっと丁寧に／箇条書きにして／英語にして）" }
            else { "話してください…" }
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

// 設計判断: DEC-DIC-026
/// 録音を止めて入力するボタン。前面にないパネルでも押せるよう、AppKit の部品ではなくボタンで作る
private struct StopButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "stop.fill").font(.system(size: 9))
                Text("停止").font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Color.red.opacity(0.85), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("録音を止めて入力します（ショートカットをもう一度押すのと同じ）")
    }
}

// 要件: REQ-DIC-011
/// 出力の言語を選ぶ小さな切り替え。前面にないパネルでも押せるよう、AppKit の部品ではなくボタンで作る
private struct LanguageSwitch: View {
    var translating: Bool
    var onSelect: (Bool) -> Void

    var body: some View {
        HStack(spacing: 2) {
            option("日本語", selected: !translating) { onSelect(false) }
            option("English", selected: translating) { onSelect(true) }
        }
        .padding(2)
        .background(.quaternary, in: Capsule())
        .help("録音を止めたときに選んでいる言語で入力します")
    }

    private func option(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.white : Color.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(selected ? Color.accentColor : Color.clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// 設計判断: DEC-DIC-101
/// 音量の目安（Whisper / Gemini で録っているとき）。RMS を dB にして、-60〜-10 dB を 0〜1 に割り当てる
private struct LevelMeter: View {
    var level: Float

    var body: some View {
        let db = 20 * log10(max(Double(level), 1e-6))
        let fraction = min(max((db + 60) / 50, 0), 1)
        HStack(spacing: 2) {
            ForEach(0..<12, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Double(i) / 12 < fraction ? Color.green : Color.secondary.opacity(0.25))
                    .frame(width: 4, height: 6 + CGFloat(i) * 0.8)
            }
        }
        .frame(height: 16, alignment: .bottom)
        .animation(.easeOut(duration: 0.1), value: fraction)
    }
}
