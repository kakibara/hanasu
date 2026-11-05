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
    @State private var draft = ""
    /// 今の行を書き始めた時刻（録音開始からの秒数）
    @State private var draftStartedAt: Double?
    @FocusState private var focused: Bool

    private var notes: [MeetingNote] { recorder.current?.allNotes ?? [] }
    private var isRecording: Bool { recorder.state == .recording }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if let mode {
                    LiveSidePanelModePicker(mode: mode)
                } else {
                    Text("メモ").font(.headline)
                }
                Spacer()
                LiveHighlightControls(recorder: recorder, onHighlight: highlight)
            }
            .padding([.horizontal, .top])
            HighlightUndoButton(recorder: recorder)
                .padding(.horizontal)
                .padding(.top, 4)
            if settings.highlightHotKeyEnabled {
                Text(hotKey.registrationError ?? "「ここ重要」は \(settings.highlightHotKey.displayString) でも付けられます（ほかのアプリを使っていても可）")
                    .font(.caption)
                    .foregroundStyle(hotKey.registrationError == nil ? Color.secondary : Color.orange)
                    .padding(.horizontal)
                    .padding(.top, 4)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if notes.isEmpty {
                            Text("気になったことを書くと、議事録で優先して取り上げます。")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(notes) { note in
                            NoteRow(note: note)
                                .contextMenu {
                                    // 印は付けてから 10 秒以内だけ取り消せる（DEC-MTG-047）。それより古い印は記録のあとに「メモ」タブで消す
                                    if note.kind == .note {
                                        Button("削除", role: .destructive) { recorder.removeNote(id: note.id) }
                                    } else if recorder.undoableHighlight?.id == note.id {
                                        Button("取り消す", role: .destructive) { recorder.undoHighlight(id: note.id) }
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
                TextField("メモを入力して ↩", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit(submit)
                    .onChange(of: draft) { old, new in
                        // 書き始めた時刻を、その行の時刻にする（聞いてから書き終えるまでの遅れを除く）
                        if old.isEmpty, !new.isEmpty { draftStartedAt = recorder.elapsed }
                        if new.isEmpty { draftStartedAt = nil }
                    }
                Text("書き始めた時刻つきで保存します。入力中に「ここ重要」を押すと、その文を印の説明にします。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .disabled(!isRecording)
            .padding()
        }
    }

    private func submit() {
        recorder.addNote(draft, at: draftStartedAt)
        draft = ""
        draftStartedAt = nil
        focused = true
    }

    private func highlight() {
        recorder.addHighlight(draft)
        draft = ""
        draftStartedAt = nil
    }
}

// 要件: REQ-MTG-012, REQ-MTG-014
/// 記録中の画面の右側の上に出す、字幕の切り替えと「ここ重要」のボタン（「メモ」と「AI チャット」のどちらでも出す）
struct LiveHighlightControls: View {
    @ObservedObject var recorder: MeetingRecorder
    /// 「ここ重要」を押したとき。nil なら説明なしで今の時刻に印を付ける（メモ欄では、書きかけの文を印の説明にする）
    var onHighlight: (() -> Void)?
    @ObservedObject private var settings = MeetingNotesSettings.shared
    @ObservedObject private var caption = MeetingCaptionPanel.shared

    var body: some View {
        HStack(spacing: 8) {
            Button {
                caption.toggle(recorder: recorder)
            } label: {
                Image(systemName: caption.isShown ? "captions.bubble.fill" : "captions.bubble")
            }
            .help("字幕をほかのアプリの前面に表示する")
            Button {
                if let onHighlight { onHighlight() } else { recorder.addHighlight() }
            } label: {
                Label("ここ重要", systemImage: "star.fill")
            }
            .tint(.yellow)
            .buttonStyle(.borderedProminent)
            .help(highlightHelp)
        }
        .disabled(recorder.state != .recording)
    }

    private var highlightHelp: String {
        settings.highlightHotKeyEnabled ? "今の時刻に印を付ける（\(settings.highlightHotKey.displayString)）" : "今の時刻に印を付ける"
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
                        Label("取り消す", systemImage: "arrow.uturn.backward")
                    } else {
                        Label("★ を取り消す（あと \(remaining) 秒）", systemImage: "arrow.uturn.backward")
                    }
                }
                .help("付けてから 10 秒のあいだは、押し間違えた印を取り消せます")
            }
        }
    }
}

private struct NoteRow: View {
    let note: MeetingNote

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(note.time.map(Meeting.clock) ?? "--:--")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            if note.kind == .highlight {
                Image(systemName: "star.fill").foregroundStyle(.yellow)
                Text(note.text.isEmpty ? "ここ重要" : note.text)
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

    private var changed: Bool { text != meeting.notesText }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("1 行に 1 つ書きます。「[12:34] 内容」で時刻（録音開始から）を、「★」で「ここ重要」の印を表します。時刻のない行も書けます。議事録を作るとき、メモと印の前後の発言を優先して反映します。")
                .font(.caption)
                .foregroundStyle(.secondary)
                // 設計判断: DEC-MTG-048
                // 高さを中身に合わせて固定しない（fixedSize にすると、左右に並べる画面が細い幅で最小の高さを測ったとき
                // 1 文字ずつ折り返した高さを求め、会議ノートの中身がウインドウより縦に大きくなって、上下が画面の外に出る）
                .lineLimit(3)
            // 設計判断: DEC-MTG-048
            // テキスト欄は、メモの行数にかかわらず残りの高さに収めて中でスクロールする（最小の高さを決めないと、
            // 全行ぶんの高さを求めて会議ノートの上のタブの切り替えを押し出す）
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120, maxHeight: .infinity)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            HStack {
                let count = MeetingNote.parse(text)
                Text("メモ \(count.filter { $0.kind == .note }.count) 件・印 \(count.filter { $0.kind == .highlight }.count) 件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("元に戻す") { text = meeting.notesText }
                    .disabled(!changed)
                Button("保存") { recorder.updateNotes(meeting, notes: MeetingNote.parse(text)) }
                    .disabled(!changed)
                Button("保存して議事録を作り直す") {
                    let updated = recorder.updateNotes(meeting, notes: MeetingNote.parse(text))
                    Task { await recorder.regenerateMinutes(updated) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(recorder.state != .idle || meeting.utterances.isEmpty)
            }
        }
        .padding()
        .onAppear { text = meeting.notesText }
        .onChange(of: meeting.id) { text = meeting.notesText }
    }
}

/// 設定の「会議」タブに置く、「ここ重要」のショートカットの設定
struct MeetingNotesSettingsSection: View {
    @ObservedObject private var settings = MeetingNotesSettings.shared
    var onBeginShortcutRecording: () -> Void = {}
    var onEndShortcutRecording: () -> Void = {}

    var body: some View {
        Section {
            Toggle("記録中に「ここ重要」のショートカットを使う", isOn: $settings.highlightHotKeyEnabled)
            LabeledContent("「ここ重要」の印") {
                ShortcutRecorder(
                    combo: $settings.highlightHotKey,
                    defaultCombo: MeetingNotesSettings.defaultHighlightHotKey,
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
            Text("会議中のメモ")
        } footer: {
            Text("会議ノートの記録中の画面でメモを書いたり「ここ重要」の印を付けたりすると、議事録で優先して取り上げます。ショートカットは記録中だけ有効になり、ほかのアプリを使っていても印を付けられます。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - 前面に出す字幕

// 要件: REQ-MTG-014
// 設計判断: DEC-MTG-046
/// 記録中の文字起こしを、会議ツールなどほかのアプリの前面に小さく出す字幕ウインドウ
@MainActor
final class MeetingCaptionPanel: ObservableObject {
    static let shared = MeetingCaptionPanel()

    @Published private(set) var isShown = false

    private var panel: NSPanel?
    private var cancellables: Set<AnyCancellable> = []

    func toggle(recorder: MeetingRecorder) {
        isShown ? close() : show(recorder: recorder)
    }

    func show(recorder: MeetingRecorder) {
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 130),
                styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel, .hudWindow],
                backing: .buffered, defer: false)
            panel.title = "Hanasu 字幕"
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: MeetingCaptionView(recorder: recorder))
            panel.setFrameAutosaveName("HanasuMeetingCaption")
            if !panel.setFrameUsingName("HanasuMeetingCaption"), let screen = NSScreen.main {
                // 初回は画面の下の中央
                let frame = screen.visibleFrame
                panel.setFrameOrigin(NSPoint(x: frame.midX - 280, y: frame.minY + 40))
            }
            NotificationCenter.default.publisher(for: NSWindow.willCloseNotification, object: panel)
                .sink { [weak self] _ in self?.isShown = false }
                .store(in: &cancellables)
            // 記録が終わったら閉じる
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
        panel?.close()
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
                    row(speaker: line.channel == .me ? "自分" : "相手", text: line.text,
                        color: line.channel == .me ? .accentColor : .orange)
                }
                if !recorder.volatileOthers.isEmpty {
                    row(speaker: "相手", text: recorder.volatileOthers, color: .orange).opacity(0.6)
                }
                if !recorder.volatileMe.isEmpty {
                    row(speaker: "自分", text: recorder.volatileMe, color: .accentColor).opacity(0.6)
                }
                if let engine = recorder.batchEngine {
                    Text("記録を止めたあとに \(engine.shortName) で文字起こしします").foregroundStyle(.secondary)
                } else if recorder.liveLines.isEmpty, recorder.volatileMe.isEmpty, recorder.volatileOthers.isEmpty {
                    Text("話し始めると、ここに文字起こしが出ます").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            VStack(spacing: 4) {
                Button { recorder.addHighlight() } label: {
                    Image(systemName: "star.fill")
                }
                .tint(.yellow)
                .buttonStyle(.borderedProminent)
                .help("ここ重要")
                .disabled(recorder.state != .recording)
                HighlightUndoButton(recorder: recorder, compact: true)
                    .font(.caption)
            }
        }
        .font(.title3)
        .padding(12)
        .frame(minWidth: 320, minHeight: 80)
    }

    private func row(speaker: String, text: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(speaker).bold().foregroundStyle(color)
            // 長い発言は最後のほう（いま話している部分）を見せる
            Text(text).lineLimit(2).truncationMode(.head)
        }
    }
}

// MARK: - 見た目の確認用の描き出し

/// `Hanasu --render-meeting-notes <出力フォルダ>`: 架空の会議で、記録中の画面・メモの編集・字幕を PNG にする
enum MeetingNotesPreview {
    @MainActor
    static func render(to directory: URL) throws {
        _ = NSApplication.shared
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var meeting = Meeting(id: "preview", title: "週次定例（サンプル）", startedAt: Date().addingTimeInterval(-754))
        meeting.notes = [
            MeetingNote(kind: .note, time: 65, text: "リリースは 11/20 で確定？"),
            MeetingNote(kind: .highlight, time: 312, text: ""),
            MeetingNote(kind: .note, time: 420, text: "価格表の更新 → 佐藤さん"),
            MeetingNote(kind: .highlight, time: 690, text: "β版の対象を 3 社に絞る"),
        ]
        let lines: [MeetingRecorder.LiveLine] = [
            .init(channel: .others, start: 640, text: "β版はまず 3 社に絞って出したいと思っています。"),
            .init(channel: .me, start: 652, text: "3 社だとどこを想定していますか？"),
            .init(channel: .others, start: 660, text: "既存のお客さまのうち、利用頻度が高いところからです。"),
            .init(channel: .me, start: 701, text: "分かりました。選び方の基準を来週までにまとめましょう。"),
        ]
        let recorder = MeetingRecorder()
        recorder.showPreviewForRendering(meeting, lines: lines, volatileOthers: "そうですね、基準は利用頻度と")

        try write(LiveTranscriptView(recorder: recorder).frame(width: 640, height: 520),
                  to: directory.appendingPathComponent("live.png"))
        var done = meeting
        done.status = .done
        try write(MeetingNotesEditor(meeting: done, recorder: recorder).frame(width: 560, height: 320),
                  to: directory.appendingPathComponent("notes-editor.png"))
        try write(MeetingCaptionView(recorder: recorder).frame(width: 560, height: 130)
                      .environment(\.colorScheme, .dark).background(Color.black.opacity(0.85)),
                  to: directory.appendingPathComponent("caption.png"))
        try write(Form { MeetingNotesSettingsSection() }.formStyle(.grouped).frame(width: 560, height: 220),
                  to: directory.appendingPathComponent("settings.png"))
        // 付けたばかりの印があるとき（「取り消す」が出る）
        var recent = meeting
        recent.notes?.append(MeetingNote(kind: .highlight, time: 750, text: ""))
        recorder.showPreviewForRendering(recent, lines: lines)
        try write(LiveTranscriptView(recorder: recorder).frame(width: 640, height: 520),
                  to: directory.appendingPathComponent("live-undo.png"))
        try write(MeetingCaptionView(recorder: recorder).frame(width: 560, height: 130)
                      .environment(\.colorScheme, .dark).background(Color.black.opacity(0.85)),
                  to: directory.appendingPathComponent("caption-undo.png"))
        checkHighlightUndo(recorder: recorder)
        checkCompatibility()
    }

    // 確かめ方: REQ-MTG-012
    /// 「ここ重要」の取り消し（DEC-MTG-047）の確認。結果だけ出す
    @MainActor
    private static func checkHighlightUndo(recorder: MeetingRecorder) {
        var results: [String] = []
        func check(_ name: String, _ ok: Bool) { results.append("\(ok ? "OK" : "NG") \(name)") }
        let meeting = Meeting(id: "u", title: "t", startedAt: Date(), notes: [
            MeetingNote(kind: .highlight, time: 100, text: ""),
            MeetingNote(kind: .highlight, time: 115, text: "新しい"),
            MeetingNote(kind: .note, time: 118, text: "メモ"),
        ])
        check("10 秒以内のいちばん新しい印", meeting.undoableHighlight(at: 118)?.text == "新しい")
        check("ちょうど 10 秒まで", meeting.undoableHighlight(at: 125)?.text == "新しい")
        check("10 秒を過ぎたら取り消せない", meeting.undoableHighlight(at: 125.1) == nil)
        check("古い印は取り消せない", meeting.undoableHighlight(at: 130) == nil)
        check("時刻のない印は対象外", Meeting(id: "v", title: "t", startedAt: Date(),
                                          notes: [MeetingNote(kind: .highlight, time: nil, text: "")]).undoableHighlight(at: 0) == nil)
        // 記録中のプレビュー（750 秒の印、今は約 754 秒）で「取り消す」が出る。取り消しそのものは保存を伴うので、ここでは呼ばない
        check("記録中のプレビューで取り消せる印がある", recorder.undoableHighlight?.time == 750)
        print("ここ重要の取り消し: " + results.joined(separator: " / "))
    }

    /// 後方互換とテキスト形式の確認（中身は出さず、件数と結果だけ出す）
    @MainActor
    private static func checkCompatibility() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // メモ機能より前の meeting.json（notes がない）
        let legacy = #"{"id":"x","title":"t","startedAt":"2026-11-02T05:30:00Z","duration":60,"status":"done","speakerNames":{},"utterances":[]}"#
        let old = try? decoder.decode(Meeting.self, from: Data(legacy.utf8))
        print("古い形式の meeting.json: \(old != nil && old?.notes == nil ? "読めた（メモなし）" : "読めなかった")")
        // テキスト形式の往復
        let text = "[01:05] メモ\n[05:12] ★\n[1:02:03] ★ 説明\n時刻なし"
        let parsed = MeetingNote.parse(text)
        print("テキスト形式の往復: \(MeetingNote.text(from: parsed) == text ? "一致" : "不一致: \(MeetingNote.text(from: parsed))")")
        // 手元の会議がすべて読めるか
        let dirs = (try? FileManager.default.contentsOfDirectory(at: MeetingStore.baseDirectory, includingPropertiesForKeys: nil)) ?? []
        let withJSON = dirs.filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("meeting.json").path) }.count
        print("手元の会議: meeting.json \(withJSON) 件中 \(MeetingStore.loadAll().count) 件を読めた")
    }

    @MainActor
    static func write<V: View>(_ view: V, to url: URL) throws {
        let hosting = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        // TextField などは AppKit の部品なので、画面外のウインドウに置いて描く
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])?.write(to: url)
        print("wrote \(url.path)")
    }
}
