import AppKit
import SwiftUI

// 要件: REQ-DIC-080
// 設計判断: DEC-DIC-094
/// 入力できる場所がなくて貼り付けなかった結果を、全文表示して残すパネル（画面の下部中央）。
/// 自動では閉じない。「閉じる」・Esc・⌘W か、次に録音を始めたときに閉じる。
/// アプリを前面に出さない nonactivatingPanel のまま、キーウインドウになって Esc・⌘C・文字の選択を受け取る。
@MainActor
final class PasteFallbackPanel {
    static let shared = PasteFallbackPanel()

    /// 何を表示しているか（見出しの言葉が変わる）
    enum Subject {
        /// 音声入力の結果・もう一度入力した結果
        case result
        /// 選択を声で編集した結果
        case edit

        var noun: String {
            switch self {
            case .result: "結果"
            case .edit: "書き換えた文章"
            }
        }
    }

    static let width: CGFloat = 480
    /// 文章の欄の高さの上限。これより長い文章はスクロールで読む
    static let maxTextHeight: CGFloat = 260
    static let minTextHeight: CGFloat = 32
    static let textFont = NSFont.systemFont(ofSize: 13)
    static let textInset = NSSize(width: 8, height: 6)

    private let model = PasteFallbackModel()
    private let panel: KeyablePanel

    var isVisible: Bool { panel.isVisible }

    private init() {
        panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 200),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        model.onCopy = { [weak self] in self?.copyAll() }
        model.onClose = { [weak self] in self?.close() }
        panel.onEscape = { [weak self] in self?.close() }
        panel.onCopyAll = { [weak self] in self?.copyAll() }
        let hosting = FallbackHostingView(rootView: PasteFallbackView(model: model))
        hosting.sizingOptions = []
        panel.contentView = hosting
    }

    // 設計判断: DEC-DIC-094, DEC-DIC-095
    /// 結果を表示する。clipboardKept は、結果をクリップボードにも入れたか（案内の文が変わる）
    func show(text: String, subject: Subject, clipboardKept: Bool, warning: String? = nil, headless: Bool = false) {
        model.text = text
        model.subject = subject
        model.clipboardKept = clipboardKept
        model.warning = warning
        model.copied = false
        model.textHeight = Self.textHeight(for: text)
        resize()
        position()
        guard !headless else { return }
        // アプリは前面に出さない。キーウインドウにだけして、Esc・⌘C・選択を受け取る
        panel.makeKeyAndOrderFront(nil)
        appLog.notice("paste fallback panel shown: \(text.count) chars, clipboardKept=\(clipboardKept, privacy: .public)")
    }

    func close() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        // 表示していた文章をメモリに残し続けない
        model.text = ""
    }

    /// 見た目の確認用に、今の表示を PNG にする（画面には出さない）
    func snapshotPNG() -> Data? {
        guard let view = panel.contentView else { return nil }
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    /// 「コピー」ボタン・選択していないときの ⌘C。利用者が自分でコピーするので、ふつうのコピーにする（「最近の結果」と同じ）
    private func copyAll() {
        guard !model.text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.text, forType: .string)
        model.copied = true
    }

    private func resize() {
        guard let view = panel.contentView else { return }
        // 表示用のビューは大きさを自分で決めない設定（sizingOptions = []）なので、同じ内容の別のビューで測る
        let size = NSHostingView(rootView: PasteFallbackView(model: model)).fittingSize
        panel.setContentSize(NSSize(width: Self.width, height: max(120, size.height)))
        view.frame = NSRect(origin: .zero, size: panel.frame.size)
    }

    /// HUD と同じく、マウスのある画面の下部中央に出す（HUD は隠してから出す）
    private func position() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 72))
    }

    /// 文章の欄の高さ。折り返したときの高さを測り、上限を超えたらスクロールにする
    static func textHeight(for text: String) -> CGFloat {
        let contentWidth = width - 32 - textInset.width * 2 - 10  // 左右の余白とスクローラーのぶん
        let storage = NSTextStorage(string: text.isEmpty ? " " : text, attributes: [.font: textFont])
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: contentWidth, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 5
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        let height = ceil(layout.usedRect(for: container).height) + textInset.height * 2
        return min(max(height, minTextHeight), maxTextHeight)
    }
}

@MainActor
final class PasteFallbackModel: ObservableObject {
    @Published var text = ""
    @Published var subject: PasteFallbackPanel.Subject = .result
    @Published var clipboardKept = true
    @Published var warning: String?
    @Published var copied = false
    @Published var textHeight: CGFloat = PasteFallbackPanel.minTextHeight
    var onCopy: (() -> Void)?
    var onClose: (() -> Void)?
}

/// 枠なしのパネルは既定ではキーウインドウになれないので、なれるようにする。Esc・⌘W・⌘C・⌘A はここで受ける
/// （アプリが前面にないので、メニューのショートカットに頼らない）
private final class KeyablePanel: NSPanel {
    var onEscape: (() -> Void)?
    var onCopyAll: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let key = event.charactersIgnoringModifiers?.lowercased()
            if event.keyCode == 53, flags.isEmpty {  // Esc
                onEscape?()
                return
            }
            if flags == .command {
                switch key {
                case "w":
                    onEscape?()
                    return
                case "c":
                    if let textView = firstResponder as? NSTextView, textView.selectedRange().length > 0 {
                        textView.copy(nil)
                    } else {
                        onCopyAll?()
                    }
                    return
                case "a":
                    if let textView = contentView.flatMap(Self.findTextView) {
                        makeFirstResponder(textView)
                        textView.selectAll(nil)
                    }
                    return
                default:
                    break
                }
            }
        }
        super.sendEvent(event)
    }

    private static func findTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView { return textView }
        for subview in view.subviews {
            if let found = findTextView(in: subview) { return found }
        }
        return nil
    }
}

/// 前面にないパネルでも、1 回のクリックでボタンが押せるようにする
private final class FallbackHostingView: NSHostingView<PasteFallbackView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// 前面にないパネルでも、1 回のクリックで文字を選び始められるようにする
private final class FirstMouseTextView: NSTextView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct PasteFallbackView: View {
    @ObservedObject var model: PasteFallbackModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard").foregroundStyle(.orange)
                Text("入力できる場所が見つからないため、貼り付けていません")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(guidance)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let warning = model.warning, !warning.isEmpty {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SelectableText(text: model.text)
                .frame(height: model.textHeight)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.secondary.opacity(0.25)))
            HStack(spacing: 8) {
                Text("\(model.text.count) 文字")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                if model.copied {
                    Label("コピーしました", systemImage: "checkmark")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                }
                Button("コピー") { model.onCopy?() }
                    .help("文章をすべてクリップボードにコピーします（⌘C。一部を選んでいるときは、その部分）")
                Button("閉じる") { model.onClose?() }
                    .help("この表示を閉じます（Esc）。次に録音を始めたときも閉じます")
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: PasteFallbackPanel.width, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12)))
    }

    private var guidance: String {
        let noun = model.subject.noun
        return model.clipboardKept
            ? "\(noun)はクリップボードにも入っています。入力したい場所をクリックして ⌘V で貼り付けてください。"
            : "\(noun)を選んでコピーするか「コピー」を押してから、入力したい場所に貼り付けてください。"
    }
}

/// 選択できる（編集はできない）文章の欄。長い文章はスクロールで読む
private struct SelectableText: NSViewRepresentable {
    var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        let textView = FirstMouseTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.font = PasteFallbackPanel.textFont
        textView.textColor = .labelColor
        textView.textContainerInset = PasteFallbackPanel.textInset
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 5
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
        textView.font = PasteFallbackPanel.textFont
        textView.textColor = .labelColor
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scrollToBeginningOfDocument(nil)
    }
}

// MARK: - 設定画面の欄

// 要件: REQ-DIC-081
// 設計判断: DEC-DIC-095
/// 設定の「一般」に置く「入力できる場所がないとき」の欄
struct PasteFallbackSettingsSection: View {
    @ObservedObject var settings = PasteFallbackSettings.shared

    var body: some View {
        Section {
            Picker("クリップボード", selection: $settings.clipboard) {
                ForEach(PasteFallbackClipboard.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.radioGroup)
        } header: {
            Text("入力できる場所がないとき")
        } footer: {
            Text("デスクトップや Finder の一覧が前面にある・ボタンやリンクを選んでいる・Web ページの入力欄の外をクリックしたあとなど、入力欄にカーソルがないと分かったときは、貼り付けずに結果を画面に表示します。表示は「閉じる」か Esc で閉じるか、次に録音を始めるまで残ります。分からないときは、これまでどおり貼り付けます。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// 要件: REQ-DIC-083, REQ-DIC-084
// 設計判断: DEC-DIC-099
/// 設定の「一般」の「貼り付けが届かなかったとき」の欄
struct PasteUnconfirmedSettingsSection: View {
    @ObservedObject var settings = PasteFallbackSettings.shared

    var body: some View {
        Section {
            Toggle("音声入力の履歴を開く", isOn: $settings.openHistoryWhenUnconfirmed)
        } header: {
            Text("貼り付けが届かなかったとき")
        } footer: {
            Text("録音中に別のウインドウへ移ったなどで、⌘V を送っても貼り付け先が受け取らなかったときは、最新の結果をクリップボードに入れたままにします。入力したい場所で ⌘V を押せば貼れます。オンにすると、あわせて履歴のウインドウを開き、最新の結果を選んだ状態にします。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
