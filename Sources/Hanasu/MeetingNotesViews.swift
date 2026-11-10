import AppKit
import Combine
import SwiftUI

// 要件: REQ-MTG-011
// 設計判断: DEC-MTG-040, DEC-MTG-042
/// 記録中の画面の右側: メモ欄と「ここ重要」ボタン。
struct LiveNotesPanel: View {
    @ObservedObject var recorder: MeetingRecorder
    /// 右側の「メモ」「AI チャット」の切り替え（LiveSidePanel）。nil なら見出しに「メモ」とだけ出す
    var mode: Binding<LiveSidePanelMode>?
    @ObservedObject private var settings = MeetingNotesSettings.shared
    @ObservedObject private var hotKey = MeetingHighlightHotKey.shared
    // 要件: REQ-MTG-047（「何を聞かれた？」のショートカットを登録できなかったときも、記録中に知らせる）
    @ObservedObject private var askedHotKey = MeetingAskedHotKey.shared
    @FocusState private var focused: Bool

    private var notes: [MeetingNote] { recorder.current?.allNotes ?? [] }
    private var isRecording: Bool { recorder.state == .recording }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if let mode {
                    LiveSidePanelModePicker(mode: mode)
                } else {
                    Text(tr("メモ")).font(.headline)
                }
                Spacer()
                LiveHighlightControls(recorder: recorder, onHighlight: highlight)
            }
            .padding([.horizontal, .top])
            HighlightUndoButton(recorder: recorder)
                .padding(.horizontal)
                .padding(.top, 4)
            if settings.highlightHotKeyEnabled {
                Text(hotKey.registrationError ?? tr("「ここ重要」は %@ でも付けられます（ほかのアプリを使っていても可）", "\(settings.highlightHotKey.displayString)"))
                    .font(.caption)
                    .foregroundStyle(hotKey.registrationError == nil ? Color.secondary : Color.orange)
                    .padding(.horizontal)
                    .padding(.top, 4)
            }
            if settings.askedHotKeyEnabled, let error = askedHotKey.registrationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.orange)
                    .padding(.horizontal)
                    .padding(.top, 4)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if notes.isEmpty {
                            Text(tr("気になったことを書くと、議事録で優先して取り上げます。"))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(notes) { note in
                            NoteRow(note: note)
                                .contextMenu {
                                    // 印は付けてから 10 秒以内だけ取り消せる（DEC-MTG-047）。それより古い印は記録のあとに「メモ」タブで消す
                                    if note.kind == .note {
                                        Button(tr("削除"), role: .destructive) { recorder.removeNote(id: note.id) }
                                    } else if recorder.undoableHighlight?.id == note.id {
                                        Button(tr("取り消す"), role: .destructive) { recorder.undoHighlight(id: note.id) }
                                    }
                                }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding()
                }
                .onChange(of: notes.count) { proxy.scrollTo("bottom") }
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                // 要件: REQ-MTG-054
                // 設計判断: DEC-MTG-136（書きかけの文は recorder に持ち、記録を止めるときに確定する）
                TextField(tr("メモを入力して ↩"), text: $recorder.noteDraft, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit(submit)
                    .onChange(of: recorder.noteDraft) { old, new in
                        // 書き始めた時刻を、その行の時刻にする（聞いてから書き終えるまでの遅れを除く）
                        if old.isEmpty, !new.isEmpty { recorder.noteDraftStartedAt = recorder.elapsed }
                        if new.isEmpty { recorder.noteDraftStartedAt = nil }
                    }
                Text(tr("書き始めた時刻つきで保存します。入力中に「ここ重要」を押すと、その文を印の説明にします。"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .disabled(!isRecording)
            .padding()
        }
    }

    private func submit() {
        recorder.commitNoteDraft()
        focused = true
    }

    private func highlight() {
        recorder.addHighlight(recorder.noteDraft)
        recorder.noteDraft = ""
        recorder.noteDraftStartedAt = nil
    }
}

// 要件: REQ-MTG-014
/// 記録中のツールバーの、字幕の切り替え
struct MeetingCaptionToggle: View {
    @ObservedObject var recorder: MeetingRecorder
    @ObservedObject private var caption = MeetingCaptionPanel.shared

    var body: some View {
        Button {
            caption.toggle(recorder: recorder)
        } label: {
            Label(tr("字幕"), systemImage: caption.isShown ? "captions.bubble.fill" : "captions.bubble")
        }
        .disabled(recorder.state != .recording)
        .help(tr("字幕をほかのアプリの前面に表示する"))
        .accessibilityLabel(tr("字幕を前面に表示"))
        .accessibilityValue(caption.isShown ? tr("オン") : tr("オフ"))
    }
}

// 要件: REQ-MTG-012
// 設計判断: DEC-MTG-080（「メモ」と「AI チャット」のどちらを選んでいても、パネルの上に出す）
/// 記録中の後ろ側のパネルの上に出す「ここ重要」のボタン
struct LiveHighlightControls: View {
    @ObservedObject var recorder: MeetingRecorder
    /// 「ここ重要」を押したとき。nil なら説明なしで今の時刻に印を付ける（メモ欄では、書きかけの文を印の説明にする）
    var onHighlight: (() -> Void)?
    @ObservedObject private var settings = MeetingNotesSettings.shared

    var body: some View {
        HStack(spacing: 8) {
            // 設計判断: DEC-MTG-075（黄色の上は白ではなく黒の文字にする）
            Button {
                if let onHighlight { onHighlight() } else { recorder.addHighlight() }
            } label: {
                Label(tr("ここ重要"), systemImage: "star.fill")
                    .foregroundStyle(.black)
            }
            .tint(.yellow)
            .buttonStyle(.borderedProminent)
            .help(highlightHelp)
        }
        .disabled(recorder.state != .recording)
    }

    private var highlightHelp: String {
        settings.highlightHotKeyEnabled ? tr("今の時刻に印を付ける（%@）", "\(settings.highlightHotKey.displayString)") : tr("今の時刻に印を付ける")
    }
}

// 要件: REQ-MTG-012
// 設計判断: DEC-MTG-047
/// 付けてから 10 秒以内の「ここ重要」の印があるあいだだけ出る「取り消す」ボタン（残りの秒数つき）
struct HighlightUndoButton: View {
    @ObservedObject var recorder: MeetingRecorder
    var compact = false

    // 設計判断: DEC-COM-016
    // 記録中だけ時計を動かす。メモ欄と字幕のパネルは、閉じても記録していなくても残るので、
    // 常に動かすと 0.5 秒ごとの描き直しが続く
    var body: some View {
        if recorder.state == .recording {
            timeline
        }
    }

    private var timeline: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            if let note = recorder.undoableHighlight, let time = note.time {
                let remaining = max(1, Int((Meeting.highlightUndoSeconds - (recorder.elapsed - time)).rounded(.up)))
                Button {
                    recorder.undoHighlight(id: note.id)
                } label: {
                    if compact {
                        Label(tr("取り消す"), systemImage: "arrow.uturn.backward")
                    } else {
                        Label(tr("★ を取り消す（あと %@ 秒）", "\(remaining)"), systemImage: "arrow.uturn.backward")
                    }
                }
                .help(tr("付けてから 10 秒のあいだは、押し間違えた印を取り消せます"))
            }
        }
    }
}

struct NoteRow: View {
    let note: MeetingNote

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(note.time.map(Meeting.clock) ?? "--:--")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            if note.kind == .highlight {
                Image(systemName: "star.fill").foregroundStyle(.yellow)
                Text(note.text.isEmpty ? tr("ここ重要") : note.text)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(note.text).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .textSelection(.enabled)
    }
}

// 要件: REQ-MTG-013
/// 会議ノートの「メモ」タブ: 記録後にメモを書き直し、議事録を作り直す。
struct MeetingNotesEditor: View {
    let meeting: Meeting
    @ObservedObject var recorder: MeetingRecorder
    @State private var text = ""
    /// 「保存して議事録を作り直す」の確かめ（今の議事録があるときだけ出す。DEC-MTG-072）
    @State private var confirmRegenerate = false

    private var changed: Bool { text != meeting.notesText }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("1 行に 1 つ書きます。「[12:34] 内容」で時刻（録音開始から）を、「★」で「ここ重要」の印を表します。時刻のない行も書けます。議事録を作るとき、メモと印の前後の発言を優先して反映します。"))
                .font(.caption)
                .foregroundStyle(.secondary)
                // 設計判断: DEC-MTG-048
                // 高さを中身に合わせて固定しない（fixedSize にすると、左右に並べる画面が細い幅で最小の高さを測ったとき
                // 1 文字ずつ折り返した高さを求め、会議ノートの中身がウインドウより縦に大きくなって、上下が画面の外に出る）
                .lineLimit(3)
            // 設計判断: DEC-MTG-048
            // テキスト欄は、メモの行数にかかわらず最小 120・最大 360 の高さに収めて中でスクロールする
            // （高さを決めないと、全行ぶんの高さを求めて会議ノートの中身を押し出す）
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120, maxHeight: 360)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            // 文書の幅が狭いときは折り返す（ボタンは縮まないので、1 行に並べると文書の最小の幅を押し広げる）
            FlowLayout(spacing: 8) {
                let count = MeetingNote.parse(text)
                Text(tr("メモ %@ 件・印 %@ 件", "\(count.filter { $0.kind == .note }.count)", "\(count.filter { $0.kind == .highlight }.count)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 8)
                Button(tr("元に戻す")) { text = meeting.notesText }
                    .disabled(!changed)
                Button(tr("保存")) { recorder.updateNotes(meeting, notes: MeetingNote.parse(text)) }
                    .disabled(!changed)
                // 設計判断: DEC-MTG-072
                Button(tr("保存して議事録を作り直す")) {
                    if meeting.minutes == nil { saveAndRegenerate() } else { confirmRegenerate = true }
                }
                .buttonStyle(.borderedProminent)
                .disabled(recorder.state != .idle || meeting.utterances.isEmpty)
                .confirmationDialog(tr("メモを保存して、議事録を作り直しますか？"), isPresented: $confirmRegenerate) {
                    Button(tr("作り直す"), action: saveAndRegenerate)
                    Button(tr("キャンセル"), role: .cancel) {}
                } message: {
                    Text(tr("今の議事録とアクションアイテムは、メモを反映したものに置き換わります。"))
                }
            }
        }
        .onAppear { text = meeting.notesText }
        .onChange(of: meeting.id) { text = meeting.notesText }
    }

    private func saveAndRegenerate() {
        let updated = recorder.updateNotes(meeting, notes: MeetingNote.parse(text))
        Task { await recorder.regenerateMinutes(updated) }
    }
}

/// 設定の「会議」に置く、「ここ重要」のショートカットの設定
struct MeetingNotesSettingsSection: View {
    @ObservedObject private var settings = MeetingNotesSettings.shared
    var onBeginShortcutRecording: () -> Void = {}
    var onEndShortcutRecording: () -> Void = {}

    var body: some View {
        Section {
            Toggle(tr("記録中に「ここ重要」のショートカットを使う"), isOn: $settings.highlightHotKeyEnabled)
            LabeledContent(tr("「ここ重要」の印")) {
                ShortcutRecorder(
                    combo: $settings.highlightHotKey,
                    defaultCombo: MeetingNotesSettings.defaultHighlightHotKey,
                    kind: .highlight,
                    onBeginRecording: {
                        MeetingHighlightHotKey.shared.suspend()
                        onBeginShortcutRecording()
                    },
                    onEndRecording: {
                        MeetingHighlightHotKey.shared.resume()
                        onEndShortcutRecording()
                    })
            }
            .disabled(!settings.highlightHotKeyEnabled)
        } header: {
            Text(tr("会議中のメモ"))
        } footer: {
            Text(tr("会議ノートの記録中の画面でメモを書いたり「ここ重要」の印を付けたりすると、議事録で優先して取り上げます。ショートカットは記録中だけ有効になり、ほかのアプリを使っていても印を付けられます。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - 前面に出す字幕

// 要件: REQ-MTG-014
// 設計判断: DEC-MTG-046, DEC-MTG-099
/// 記録中の文字起こしを、会議ツールなどほかのアプリの前面に小さく出す字幕ウインドウ。
/// キーウインドウにならない（ボタンを押しても、会議ツールのキー入力を奪わない）。
/// ユーザーが出したか閉じたかを覚え、出したまま記録を終えたら、次の記録の開始で出す
@MainActor
final class MeetingCaptionPanel: ObservableObject {
    static let shared = MeetingCaptionPanel()

    @Published private(set) var isShown = false

    private var panel: NSPanel?
    private var closingByApp = false
    private var cancellables: Set<AnyCancellable> = []

    // 要件: REQ-MTG-014
    // 設計判断: DEC-MTG-099
    private static let shownKey = "meetingCaptionShown"
    /// ユーザーが最後に字幕を出したままにしていたか（記録が終わって閉じたときは変えない）
    static var rememberedShown: Bool {
        get { UserDefaults.standard.bool(forKey: shownKey) }
        set { UserDefaults.standard.set(newValue, forKey: shownKey) }
    }

    /// 字幕の位置と大きさ（出していなければ nil）
    var frame: NSRect? { isShown ? panel?.frame : nil }

    /// ツールバーの「字幕」: 出す・閉じるを切り替えて、覚える
    func toggle(recorder: MeetingRecorder) {
        if isShown {
            close()
            Self.rememberedShown = false
        } else {
            show(recorder: recorder)
            Self.rememberedShown = true
        }
    }

    func show(recorder: MeetingRecorder) {
        if panel == nil {
            let panel = NonKeyPanel(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 130),
                styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel, .hudWindow],
                backing: .buffered, defer: false)
            panel.title = tr("Hanasu 字幕")
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.contentView = FirstMouseHostingView(rootView: MeetingCaptionView(recorder: recorder))
            panel.setFrameAutosaveName("HanasuMeetingCaption")
            // 設計判断: DEC-COM-017
            // 初回はマウスのある画面の下の中央（HUD と同じ）。2 回目からは前に置いた位置
            if !panel.setFrameUsingName("HanasuMeetingCaption"),
               let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
                let frame = screen.visibleFrame
                panel.setFrameOrigin(NSPoint(x: frame.midX - 280, y: frame.minY + 40))
            }
            NotificationCenter.default.publisher(for: NSWindow.willCloseNotification, object: panel)
                .sink { [weak self] _ in
                    guard let self else { return }
                    self.isShown = false
                    // パネルの閉じるボタンで閉じたら、次の記録では出さない
                    if !self.closingByApp { Self.rememberedShown = false }
                }
                .store(in: &cancellables)
            // 記録が終わったら閉じる（覚えている「出す」は変えない）
            recorder.$state
                .sink { [weak self] state in
                    if state == .idle { DispatchQueue.main.async { self?.close() } }
                }
                .store(in: &cancellables)
            self.panel = panel
        }
        panel?.orderFrontRegardless()
        isShown = true
    }

    func close() {
        closingByApp = true
        panel?.close()
        closingByApp = false
        isShown = false
    }
}

// 要件: REQ-MTG-014
/// 字幕の中身: 直近の発言と、確定前の途中結果
struct MeetingCaptionView: View {
    @ObservedObject var recorder: MeetingRecorder

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(recorder.liveLines.suffix(2)) { line in
                    row(speaker: line.channel == .me ? tr("自分") : tr("相手"), text: line.text,
                        color: line.channel == .me ? .accentColor : .orange)
                }
                if !recorder.volatileOthers.isEmpty {
                    row(speaker: tr("相手"), text: recorder.volatileOthers, color: .orange).opacity(0.6)
                }
                if !recorder.volatileMe.isEmpty {
                    row(speaker: tr("自分"), text: recorder.volatileMe, color: .accentColor).opacity(0.6)
                }
                if let engine = recorder.batchEngine {
                    Text(tr("記録を止めたあとに %@ で文字起こしします", "\(engine.shortName)")).foregroundStyle(.secondary)
                } else if recorder.liveLines.isEmpty, recorder.volatileMe.isEmpty, recorder.volatileOthers.isEmpty {
                    Text(tr("話し始めると、ここに文字起こしが出ます")).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            VStack(spacing: 4) {
                // 要件: REQ-MTG-047
                // 設計判断: DEC-MTG-099
                Button {
                    MeetingAskedQuestion.shared.ask(recorder: recorder, origin: .panel)
                } label: {
                    Label(tr("何を聞かれた？"), systemImage: "person.fill.questionmark")
                        .font(.callout)
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)
                .help(askedHelp)
                .disabled(recorder.state != .recording || recorder.batchEngine != nil)
                // 設計判断: DEC-MTG-075
                Button { recorder.addHighlight() } label: {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.black)
                }
                .tint(.yellow)
                .buttonStyle(.borderedProminent)
                .help(tr("ここ重要"))
                .accessibilityLabel(tr("ここ重要"))
                .disabled(recorder.state != .recording)
                HighlightUndoButton(recorder: recorder, compact: true)
                    .font(.caption)
            }
        }
        .font(.title3)
        .padding(12)
        .frame(minWidth: 320, minHeight: 80)
    }

    private var askedHelp: String {
        if let engine = recorder.batchEngine { return MeetingAskedQuestion.unavailableMessage(engine: engine.shortName) }
        return MeetingAskedQuestion.helpText
    }

    private func row(speaker: String, text: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(speaker).bold().foregroundStyle(color)
            // 長い発言は最後のほう（いま話している部分）を見せる
            Text(text).lineLimit(2).truncationMode(.head)
        }
    }
}
