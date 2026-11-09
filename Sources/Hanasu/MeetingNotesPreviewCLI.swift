import AppKit
import Combine
import SwiftUI

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

        try write(LivePreview(recorder: recorder).frame(width: 1020, height: 520),
                  to: directory.appendingPathComponent("live.png"))
        var done = meeting
        done.status = .done
        try write(MeetingNotesEditor(meeting: done, recorder: recorder).frame(width: 940, height: 320),
                  to: directory.appendingPathComponent("notes-editor.png"))
        try write(MeetingCaptionView(recorder: recorder).frame(width: 940, height: 130)
                      .environment(\.colorScheme, .dark).background(Color.black.opacity(0.85)),
                  to: directory.appendingPathComponent("caption.png"))
        try write(Form { MeetingNotesSettingsSection() }.formStyle(.grouped).frame(width: 940, height: 220),
                  to: directory.appendingPathComponent("settings.png"))
        // 付けたばかりの印があるとき（「取り消す」が出る）
        var recent = meeting
        recent.notes?.append(MeetingNote(kind: .highlight, time: 750, text: ""))
        recorder.showPreviewForRendering(recent, lines: lines)
        try write(LivePreview(recorder: recorder).frame(width: 1020, height: 520),
                  to: directory.appendingPathComponent("live-undo.png"))
        try write(MeetingCaptionView(recorder: recorder).frame(width: 940, height: 130)
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
