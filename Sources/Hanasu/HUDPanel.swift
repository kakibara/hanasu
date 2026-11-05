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
    // 設計判断: DEC-COM-016
    /// パネルを画面に出している間だけ true。隠している間（一度も出していない間も）は中身を描かない
    @Published var isShown = false
    @Published var transcript = ""
    @Published var startedAt = Date()
    // 要件: REQ-DIC-013
    /// 翻訳して入力するときの言語（整形なら nil）
    @Published var translation: TranslationLanguage?
    /// HUD の切り替えに「話した言語」と並べて出す翻訳の言語（設定で選んだもの）
    @Published var translationChoices: [TranslationLanguage] = [.english]
    /// HUD の「話した言語／English／日本語」を押したとき（nil は話した言語）。録音を止めた時点の選択で出力の言語が決まる
    var onSelectTranslation: ((TranslationLanguage?) -> Void)?
    // 要件: REQ-DIC-012
    // 設計判断: DEC-DIC-101
    /// 選択を声で編集しているときの補足（「選択 120 文字」など）。nil なら通常の音声入力
    @Published var editBadge: String?
    /// 録音を止めてからまとめて文字起こしするエンジン（Whisper / Gemini）。nil なら Mac 標準（途中経過が出る）
    @Published var batchEngine: TranscriptionEngine?
    // 要件: REQ-DIC-014
    /// 録音中の音量（RMS、0〜1）。どのエンジンでも、2 行目に音量の目安として出す
    @Published var level: Float = 0
    /// まとめての文字起こしをしている間は true（「Whisper で文字起こししています…」）
    @Published var transcribing = false
    /// HUD の「停止」を押したとき（ショートカットをもう一度押したときと同じく、録音を止めて入力する）
    var onStop: (() -> Void)?
    /// HUD の「取消」を押したとき（Esc と同じ）
    var onCancel: (() -> Void)?
    // 要件: REQ-DIC-140
    /// HUD のマイクのメニューでマイクを選んだとき（UID。空ならシステムの設定）
    var onSelectMicrophone: ((String) -> Void)?

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
        model.isShown = true
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
            guard !Task.isCancelled, let self else { return }
            self.panel.orderOut(nil)
            // 設計判断: DEC-COM-016
            // 隠したパネルの中でも、経過時間（TimelineView）・点滅（symbolEffect）・スピナーは動き続けて CPU を使うので、中身を外す
            self.model.isShown = false
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

    // 設計判断: DEC-COM-016
    var body: some View {
        if model.isShown { content }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 1 行目は、Whisper / Gemini で「話した言語／English」を出しても省略・折り返しなしで収まる間隔にする
            HStack(spacing: 6) {
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
                    LanguageSwitch(selection: model.translation, choices: model.translationChoices) { model.onSelectTranslation?($0) }
                }
                Spacer()
                if model.phase == .recording {
                    TimelineView(.periodic(from: model.startedAt, by: 1)) { context in
                        Text(elapsed(at: context.date))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                    Button { model.onCancel?() } label: {
                        Text(tr("取消")).font(.system(size: 11)).foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .help(tr("録音を取り消します（Esc）"))
                    StopButton { model.onStop?() }
                }
            }
            if let detail {
                HStack(alignment: .top, spacing: 8) {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        // 認識中の文字は末尾（いま話したところ）を残し、案内の文は頭から読めるようにする
                        .truncationMode(model.transcript.isEmpty ? .tail : .head)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if model.phase == .recording {
                        // 要件: REQ-DIC-014
                        // 設計判断: DEC-DIC-143
                        // 声がマイクに届いているかを、どのエンジンでも音量で示す（マイクのボタンの隣）
                        LevelMeter(level: model.level)
                            .padding(.top, 1)
                        microphoneButton
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 440, height: 112, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12)))
    }

    // 要件: REQ-DIC-140
    // 設計判断: DEC-DIC-142
    /// 録音中だけ、2 行目の右端にマイクのボタンを出す（1 行目は言語の切り替えと停止・取消でいっぱいのため）
    private var microphoneButton: some View {
        MicrophoneButton { uid in model.onSelectMicrophone?(uid) }
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
            (model.editBadge == nil ? tr("録音中") : tr("編集モード")) + (model.batchEngine.map { "（\($0.shortName)）" } ?? "")
        case .processing:
            if model.transcribing, let engine = model.batchEngine { tr("%@ で文字起こししています…", "\(engine.shortName)") }
            else if model.editBadge != nil { tr("AI で書き換えています…") }
            else if let translation = model.translation { translation.processingTitle }
            else { tr("AI で整えています…") }
        case .done(let message): message
        case .error: tr("エラー")
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
            // 設計判断: DEC-DIC-101
            // 途中経過が出ないエンジンでは、止めてから文字起こしすることを書いておく
            else if let engine = model.batchEngine {
                model.editBadge != nil
                    ? tr("指示を話してください。止めてから %@ で文字起こしします", "\(engine.shortName)")
                    : tr("止めてから %@ で文字起こしします（録音中は文字が出ません）", "\(engine.shortName)")
            }
            else if model.editBadge != nil { tr("指示を話してください（例: もっと丁寧に／箇条書きにして／英語にして）") }
            else { tr("話してください…") }
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
                Text(tr("停止")).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Color.red.opacity(0.85), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(tr("録音を止めて入力します（ショートカットをもう一度押すのと同じ）"))
    }
}

// 要件: REQ-DIC-140
// 設計判断: DEC-DIC-142
/// 録音中にマイクを選ぶボタン。押すと、つながっているマイクの一覧をメニューで出す
private struct MicrophoneButton: View {
    var onSelect: (String) -> Void

    var body: some View {
        Button {
            DictationMicrophoneMenu.popUp(selected: AppSettings.shared.dictationInputDeviceUID, onSelect: onSelect)
        } label: {
            HStack(spacing: 1) {
                Image(systemName: "mic").font(.system(size: 11))
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(tr("音声入力で使うマイクを切り替えます"))
    }
}

// 要件: REQ-DIC-011, REQ-DIC-013
// 設計判断: DEC-DIC-027
/// 出力の言語を選ぶ小さな切り替え（話した言語と、設定で選んだ翻訳の言語）。前面にないパネルでも押せるよう、AppKit の部品ではなくボタンで作る
private struct LanguageSwitch: View {
    var selection: TranslationLanguage?
    var choices: [TranslationLanguage]
    var onSelect: (TranslationLanguage?) -> Void

    var body: some View {
        HStack(spacing: 2) {
            option(tr("話した言語"), selected: selection == nil) { onSelect(nil) }
            ForEach(choices) { language in
                option(language.label, selected: selection == language) { onSelect(language) }
            }
        }
        .padding(2)
        .background(.quaternary, in: Capsule())
        // 1 行目が詰まっても折り返さない（詰まったら、左の見出しのほうを省略する）
        .fixedSize()
        .help(tr("録音を止めたときに選んでいる言語で入力します（話した言語は整形の言語の設定に従い、")
            + choices.map { tr("%@ は%@", "\($0.label)", "\($0.verb)") }.joined(separator: "、") + "）")
    }

    private func option(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.white : Color.secondary)
                .padding(.horizontal, choices.count > 1 ? 6 : 7)
                .padding(.vertical, 3)
                .background(selected ? Color.accentColor : Color.clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// 要件: REQ-DIC-014
// 設計判断: DEC-DIC-143, DEC-DIC-101
/// 録音中の音量の目安。RMS を dB にして、-60〜-10 dB を 12 本のバーに割り当てる
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
