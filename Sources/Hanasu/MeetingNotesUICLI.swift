@preconcurrency import AVFoundation
import AppKit
import SwiftUI

// 会議ノートの文書・引用・再生（2026-11-09 の作り直し）の確認用の CLI モード:
//   Hanasu --test-minutes-citations
//     議事録の根拠の時刻の印: プロンプトに指示が入る（17 言語）・印の取り出し・取り除き・無効の印・書き出しとリマインダーで消える・
//     縮めて送ったときに消える・アクションアイテムの読み取りが印に乱されない。AI も ~/Documents も使わない。失敗があれば終了コード 1
//   Hanasu --test-minutes-document
//     議事録の節の分け方（要約・アクションアイテムの節・本文）、検索の行の読み替え、一覧の日付のまとまり。失敗があれば終了コード 1
//   Hanasu --test-meeting-player
//     音声の重ね方（チャンネルのずれ・片方だけ・読めないファイル）、再生位置の発言、再生できないとき。一時フォルダの音声だけを使う
//   Hanasu --render-meeting-window <出力フォルダ> [--now "yyyy-MM-dd HH:mm"]
//     会議ノートのウインドウ（一覧・文書・後ろ側のパネル・再生のバー）を、最小の大きさと決まった状態で PNG にする（MeetingWindowRenderCLI）
// 確かめ方: REQ-MTG-050, REQ-MTG-051, REQ-MTG-052, REQ-MTG-053, REQ-MTG-054, REQ-MTG-055
@MainActor
enum MeetingNotesUICLI {
    static func runIfRequested(_ args: [String] = CommandLine.arguments) {
        if args.contains("--test-minutes-citations") { exit(testCitations() ? 0 : 1) }
        if args.contains("--test-minutes-document") { exit(testDocument() ? 0 : 1) }
        if args.contains("--test-meeting-player") {
            let ok = runAsync { await testPlayer() }
            exit(ok ? 0 : 1)
        }
        if let index = args.firstIndex(of: "--render-meeting-window"), index + 1 < args.count {
            var now: Date?
            if let n = args.firstIndex(of: "--now"), n + 1 < args.count {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.dateFormat = "yyyy-MM-dd HH:mm"
                now = f.date(from: args[n + 1])
            }
            do {
                let ok = try renderWindow(to: URL(fileURLWithPath: args[index + 1], isDirectory: true), now: now ?? Date(timeIntervalSince1970: 1_793_005_200))
                exit(ok ? 0 : 1)
            } catch {
                FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
                exit(1)
            }
        }
    }

    // MARK: - 会議ノートのウインドウを描く

    /// 引用・アクションアイテム・ここ重要・メモの入った架空の会議（MinutesSelectionCLI の会議に議事録を足したもの）
    static func sampleDocumentMeeting() -> Meeting {
        var meeting = MinutesSelectionCLI.sampleMeeting()
        meeting.title = "架空商事 定例（サンプル）"
        meeting.speakerNames = ["spk1": "田中", "spk2": "通訳"]
        meeting.minutes = """
        # 架空商事 定例（サンプル） — 議事録

        ## 概要
        リリースは 11 月 20 日で進め、社内への共有は来週中に行う [01:15]。価格は A 案・B 案の 2 案で比べる [07:00]。

        ## 話し合った内容
        ### リリース日程
        - 11 月 20 日で進めている（田中） [01:15]
        ### 価格
        - A 案は月 5 万円（言い直しあり） [07:20]
        - 根拠のない時刻の例 [59:00]

        ## 決定事項
        - リリース日は 11 月 20 日 [01:15]

        ## アクションアイテム
        - [ ] 見積もり（A 案・B 案）を先方に送る（担当: 田中 / 期限: 11/14 (金)）
        - [ ] 部長に価格の承認を取る（担当: 自分 / 期限: 11/12 (水)）

        ## 話者についてのメモ
        - 話者1: 田中さんと呼ばれている
        """
        meeting.actionItems = [
            ActionItem(owner: "田中", task: "見積もり（A 案・B 案）を先方に送る", due: "2026-11-14", at: "07:20"),
            ActionItem(owner: "自分", task: "部長に価格の承認を取る", due: "2026-11-12", reminderID: "r1", at: "07:00"),
        ]
        meeting.notes = [
            MeetingNote(kind: .highlight, time: 425, text: "価格の 2 案"),
            MeetingNote(kind: .note, time: 70, text: "リリース日を社内に共有する"),
        ]
        return meeting
    }

    // 確かめ方: REQ-MTG-050, REQ-MTG-051, REQ-MTG-052, REQ-MTG-053, REQ-MTG-054, REQ-MTG-007, REQ-MTG-028, REQ-MTG-029
    /// 会議ノートを PNG に描く。最小の大きさ（1040×560）で中身がはみ出さないかも確かめる（はみ出したら NG・終了コード 1）
    static func renderWindow(to dir: URL, now: Date) throws -> Bool {
        _ = NSApplication.shared
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // 描くあいだだけパネルの状態を決め、終わったら元に戻す（本物の設定を書き換えたままにしない）
        let defaults = UserDefaults.standard
        let savedShown = defaults.object(forKey: "meetingInspectorShown")
        let savedTab = defaults.object(forKey: "meetingInspectorTab")
        defer {
            defaults.set(savedShown, forKey: "meetingInspectorShown")
            defaults.set(savedTab, forKey: "meetingInspectorTab")
        }
        defaults.set(true, forKey: "meetingInspectorShown")
        defaults.set(MeetingInspectorTab.transcript.rawValue, forKey: "meetingInspectorTab")
        let meeting = sampleDocumentMeeting()
        var ok = true
        // 一覧の日付のまとまり（基準の日時から、今日・昨日・今週・先月の会議を置く）
        let day = 86_400.0
        var others: [Meeting] = []
        for (i, (offset, title)) in [(0.1, "1on1 佐藤さん"), (1.0, "架空工業 商談"), (2.2, "新機能のアイデア出し"),
                                     (9.0, "週次レビュー"), (40.0, "採用面談の振り返り")].enumerated() {
            var m = Meeting(id: "list-\(i)", title: title, startedAt: now.addingTimeInterval(-offset * day))
            m.duration = Double(1200 + i * 300)
            m.status = i == 4 ? .failed : .done
            others.append(m)
        }
        var selected = meeting
        selected.startedAt = now.addingTimeInterval(-3 * 3600)
        let recorder = MeetingRecorder()
        recorder.showMeetingsForRendering([selected] + others)
        let player = MeetingPlayer.shared

        // 0. 文書の部品の最小の幅（文書は左の一覧と後ろ側のパネルの間で 400 まで狭まる。それより広いものがあると、ウインドウからはみ出す）
        func minWidth(_ name: String, _ view: some View) {
            let hosting = NSHostingController(rootView: view)
            let width = hosting.sizeThatFits(in: CGSize(width: 1, height: 4000)).width
            print("最小の幅: \(name) \(Int(width))" + (width > MeetingDetailView.documentMinWidth ? " → NG: 400 より広い" : ""))
            if width > MeetingDetailView.documentMinWidth { ok = false }
        }
        player.showForRendering(meetingID: selected.id, channels: [.me, .others], time: 432, duration: selected.duration)
        minWidth("文書", MeetingDocumentView(meeting: selected, recorder: recorder, onFocusTranscript: { _ in }, onRegenerate: {}, onEditSpeakers: {}))
        minWidth("アクションアイテム", ActionItemsCard(meeting: selected, items: selected.resolvedActionItems, onJump: { _ in }, onReminders: {}))
        minWidth("ここ重要", HighlightContextsSection(meeting: selected) { _ in })
        minWidth("メモ", MeetingNotesSection(meeting: selected, recorder: recorder, readOnly: false))
        minWidth("帯", MeetingStatusBanners(meeting: { var m = selected; m.minutesOutdated = true; m.errorMessage = "失敗"; return m }(), recorder: recorder, processing: false, onRegenerate: {}))
        minWidth("再生のバー", MeetingPlayerBar(meeting: selected, recorder: recorder))
        minWidth("議事録の本文", MarkdownText(markdown: selected.minutes ?? "", citationLimit: selected.duration))
        do {
            let probe = MeetingRecorder()
            probe.showMeetingsForRendering([selected] + others)
            let hosting = NSHostingController(rootView: MeetingWindowView(recorder: probe, now: now, initialSelection: selected.id))
            print("最小の幅: ウインドウ全体（ツールバーなし） \(Int(hosting.sizeThatFits(in: CGSize(width: 1, height: 4000)).width))")
            let detailOnly = NSHostingController(rootView: MeetingDetailView(meeting: selected, recorder: probe, panel: MeetingPanelState()))
            print("最小の幅: 文書とツールバー（パネルなし） \(Int(detailOnly.sizeThatFits(in: CGSize(width: 1, height: 4000)).width))")
        }

        // 1. ウインドウ全体（最小の大きさと、ふつうの大きさ）
        player.showForRendering(meetingID: selected.id, channels: [.me, .others], time: 432, duration: selected.duration)
        ok = renderInWindow(MeetingWindowView(recorder: recorder, now: now, initialSelection: selected.id),
                            size: AppDelegate.meetingWindowMinSize, name: "window-min", dir: dir) && ok
        ok = renderInWindow(MeetingWindowView(recorder: recorder, now: now, initialSelection: selected.id),
                            size: AppDelegate.meetingWindowSize, name: "window", dir: dir) && ok
        // 2. 文書と後ろ側のパネル（文字起こし・AI チャット・発言を選ぶ）
        ok = renderInWindow(MeetingDetailView(meeting: selected, recorder: recorder, onDelete: {}),
                            size: NSSize(width: 1000, height: 760), name: "document", dir: dir) && ok
        ok = renderInWindow(MeetingDetailView(meeting: selected, recorder: recorder, initialTab: 4, onDelete: {}),
                            size: NSSize(width: 1000, height: 560), name: "chat", dir: dir) && ok
        var outdated = selected
        outdated.minutesOutdated = true
        outdated.errorMessage = "話者分離に失敗しました: モデルの読み込みに時間がかかりすぎたため、相手側を 1 人として続けました。ネットワークの状態を確かめてから、議事録を作り直してください。（詳しい理由: timeout after 120 seconds while loading the diarization model）"
        recorder.showMeetingsForRendering([outdated] + others)
        ok = renderInWindow(MeetingWindowView(recorder: recorder, now: now, initialSelection: outdated.id),
                            size: AppDelegate.meetingWindowMinSize, name: "banners-min", dir: dir) && ok
        ok = renderInWindow(MeetingDetailView(meeting: outdated, recorder: recorder, initialSelecting: true, onDelete: {}),
                            size: NSSize(width: 1240, height: 700), name: "selecting", dir: dir) && ok
        ok = renderInWindow(MeetingDetailView(meeting: outdated, recorder: recorder, initialSelecting: true, onDelete: {}),
                            size: AppDelegate.meetingWindowMinSize, name: "selecting-min", dir: dir) && ok
        ok = renderInWindow(MeetingWindowView(recorder: recorder, now: now, initialSelection: outdated.id,
                                              initialPanel: MeetingPanelState(tab: .transcript, selecting: true)),
                            size: AppDelegate.meetingWindowMinSize, name: "selecting-window-min", dir: dir) && ok
        ok = renderInWindow(MeetingWindowView(recorder: recorder, now: now, initialSelection: outdated.id,
                                              initialPanel: MeetingPanelState(tab: .transcript, selecting: true)),
                            size: AppDelegate.meetingWindowSize, name: "selecting-window", dir: dir) && ok
        ok = renderInWindow(MeetingWindowView(recorder: recorder, now: now, initialSelection: outdated.id,
                                              initialPanel: MeetingPanelState(tab: .transcript, selecting: true)),
                            size: NSSize(width: 1440, height: 800), name: "selecting-window-wide", dir: dir) && ok
        // 3. 作り直し中（帯・薄い議事録・再生のバーなし）
        recorder.showMeetingsForRendering([selected] + others)
        recorder.regeneratingID = selected.id
        ok = renderInWindow(MeetingDetailView(meeting: selected, recorder: recorder, onDelete: {}),
                            size: NSSize(width: 1000, height: 600), name: "regenerating", dir: dir) && ok
        recorder.regeneratingID = nil
        // 4. 音声がない・読めない会議の再生のバー
        player.showForRendering(meetingID: selected.id, channels: [.me], time: 0, duration: selected.duration)
        ok = renderInWindow(MeetingDetailView(meeting: selected, recorder: recorder, onDelete: {}),
                            size: NSSize(width: 1000, height: 560), name: "player-one-channel", dir: dir) && ok
        player.showForRendering(meetingID: selected.id, channels: [.me, .others], time: 0, duration: selected.duration, availability: .unreadable)
        ok = renderInWindow(MeetingDetailView(meeting: selected, recorder: recorder, onDelete: {}),
                            size: NSSize(width: 1000, height: 560), name: "player-unreadable", dir: dir) && ok
        player.stop()
        // 4b. 帯を積んだ文書（失敗と作り直しの促し）を単独で描く
        try MeetingNotesPreview.write(
            MeetingDocumentView(meeting: outdated, recorder: recorder, onFocusTranscript: { _ in }, onRegenerate: {}, onEditSpeakers: {})
                .frame(width: 640, height: 520),
            to: dir.appendingPathComponent("banners-document.png"))
        // 5. 「…」のメニューの中身（録音がある会議とない会議。REQ-MTG-055）
        try MeetingNotesPreview.write(
            VStack(alignment: .leading, spacing: 8) {
                MeetingMoreMenuItems(meeting: selected, recorder: recorder, onEditSpeakers: {}, onDelete: {},
                                     onDeleteAudio: {}, hasAudioOverride: true)
            }
            .padding().frame(width: 260),
            to: dir.appendingPathComponent("more-menu.png"))
        try MeetingNotesPreview.write(
            VStack(alignment: .leading, spacing: 8) {
                MeetingMoreMenuItems(meeting: selected, recorder: recorder, onEditSpeakers: {}, onDelete: {},
                                     onDeleteAudio: {}, hasAudioOverride: false)
            }
            .padding().frame(width: 260),
            to: dir.appendingPathComponent("more-menu-no-audio.png"))
        // 5b. 後ろ側のパネルと文書を単独で描く（ウインドウの中のガラスは画面の外では描けないため）
        player.showForRendering(meetingID: selected.id, channels: [.me, .others], time: 432, duration: selected.duration)
        try MeetingNotesPreview.write(
            MeetingInspector(meeting: selected, recorder: recorder, tab: .constant(.transcript),
                             focus: TranscriptFocus(target: .time(425)), selecting: .constant(false),
                             onRegenerate: {}, onChatJump: { _ in })
                .frame(width: 360, height: 760),
            to: dir.appendingPathComponent("inspector-transcript.png"))
        try MeetingNotesPreview.write(
            MeetingInspector(meeting: outdated, recorder: recorder, tab: .constant(.transcript), selecting: .constant(true),
                             onRegenerate: {}, onChatJump: { _ in })
                .frame(width: 520, height: 700),
            to: dir.appendingPathComponent("inspector-selecting.png"))
        try MeetingNotesPreview.write(
            MeetingDocumentView(meeting: selected, recorder: recorder, onFocusTranscript: { _ in }, onRegenerate: {}, onEditSpeakers: {})
                .safeAreaInset(edge: .bottom) { MeetingPlayerBar(meeting: selected, recorder: recorder) }
                .frame(width: 640, height: 1400),
            to: dir.appendingPathComponent("document-full.png"))
        player.stop()
        // 6. 記録を止めたあとの処理中（段階の帯・読むだけのメモ・記録中の文字起こし）
        var processing = selected
        processing.status = .processing
        processing.minutes = nil
        processing.actionItems = nil
        processing.utterances = []
        let lines: [MeetingRecorder.LiveLine] = [
            .init(channel: .me, start: 40, text: "では始めます。聞こえますか？"),
            .init(channel: .others, start: 75, text: "リリースは 11 月 20 日で進めています。"),
        ]
        let busy = MeetingRecorder()
        busy.showMeetingsForRendering(others)
        busy.showProcessingForRendering(processing, lines: lines, stages: [.transcribing, .diarizing, .minutes], stage: .diarizing,
                                        message: "話者を分けています…（初回はモデルをダウンロードします）")
        try MeetingNotesPreview.write(
            HStack(spacing: 0) {
                MeetingDocumentView(meeting: processing, recorder: busy, processing: true,
                                    onFocusTranscript: { _ in }, onRegenerate: {}, onEditSpeakers: {})
                Divider()
                MeetingDetailInspector(meeting: processing, recorder: busy, panel: MeetingPanelState(tab: .transcript), processing: true)
                    .frame(width: 360)
            }
            .frame(width: 1000, height: 640),
            to: dir.appendingPathComponent("processing-document.png"))
        ok = renderInWindow(MeetingWindowView(recorder: busy, now: now, initialSelection: processing.id),
                            size: AppDelegate.meetingWindowSize, name: "processing", dir: dir) && ok
        ok = renderInWindow(MeetingWindowView(recorder: busy, now: now, initialSelection: processing.id),
                            size: AppDelegate.meetingWindowMinSize, name: "processing-min", dir: dir) && ok
        // 7. 記録中（真ん中に文字起こし、後ろ側にメモ）
        let live = MeetingRecorder()
        live.showMeetingsForRendering(others)
        var recording = processing
        recording.status = .recording
        recording.notes = [MeetingNote(kind: .note, time: 65, text: "KPI の定義を先に揃える"),
                           MeetingNote(kind: .highlight, time: 225, text: "解約率 3% → 2%")]
        recording.startedAt = Date().addingTimeInterval(-420)
        live.showPreviewForRendering(recording, lines: lines, volatileOthers: "それで来週の定例までに")
        ok = renderInWindow(MeetingWindowView(recorder: live, now: now, initialSelection: recording.id),
                            size: AppDelegate.meetingWindowMinSize, name: "live-min", dir: dir) && ok
        // 7b. 記録中のツールバーの「録音を削除」をオンにした会議（REQ-MTG-010・054。最小の大きさで、はみ出しのメニューに隠れないか）
        recording.deleteAudioAfterTranscription = true
        live.showPreviewForRendering(recording, lines: lines, volatileOthers: "それで来週の定例までに")
        ok = renderInWindow(MeetingWindowView(recorder: live, now: now, initialSelection: recording.id),
                            size: AppDelegate.meetingWindowMinSize, name: "live-window-min", dir: dir) && ok
        ok = renderInWindow(MeetingWindowView(recorder: live, now: now, initialSelection: recording.id),
                            size: AppDelegate.meetingWindowSize, name: "live-window", dir: dir) && ok
        print("wrote: \(dir.path)")
        return ok
    }

    /// 本物の会議ノートと同じウインドウで描き、ツールバーを重ねて PNG にする。中身がウインドウからはみ出したら NG。
    /// 画面の外のウインドウで描くので、サイドバーと後ろ側のパネルのガラスは描けない（中身は単独の PNG で見る）
    private static func renderInWindow(_ view: some View, size: NSSize, name: String, dir: URL) -> Bool {
        let window = AppDelegate.makeMeetingWindow(rootView: view)
        window.setContentSize(size)
        window.appearance = NSAppearance(named: .aqua)
        window.orderBack(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        guard let content = window.contentView else { return false }
        let split = splitView(in: content)
        // 文書の見える幅 = ウインドウの幅 − 左の一覧 − 後ろ側のパネル（どちらも文書の上に重なる）。最小（400）を割っていないか
        let inner = split.flatMap { splitView(in: $0, skippingSelf: true) }
        let sidebarWidth = inner.flatMap { $0.arrangedSubviews.count >= 2 ? $0.arrangedSubviews.first?.frame.width : nil } ?? 0
        let inspectorWidth = split.flatMap { $0.arrangedSubviews.count >= 2 ? $0.arrangedSubviews.last?.frame.width : nil } ?? 0
        let documentWidth: CGFloat? = split == nil ? nil : content.bounds.width - sidebarWidth - inspectorWidth
        if let documentWidth { print("  文書の幅 \(Int(documentWidth))" + (documentWidth >= MeetingDetailView.documentMinWidth - 1 ? "" : " → NG: 400 より狭い")) }
        let fits = window.frame.width <= size.width + 1
            && (documentWidth.map { $0 >= MeetingDetailView.documentMinWidth - 1 } ?? true)
            && (split.map { $0.frame.height <= content.bounds.height + 1 && $0.frame.width <= content.bounds.width + 1 } ?? true)
        let splitSize = split.map { split in
            "\(Int(split.frame.width))×\(Int(split.frame.height))（列 " + split.arrangedSubviews.map { "\(Int($0.frame.width))" }.joined(separator: "+") + "）"
        } ?? "-"
        print("\(name): ウインドウの中身 \(Int(content.bounds.width))×\(Int(content.bounds.height))・左右の画面 \(splitSize)"
              + (fits ? "" : " → NG: 中身がウインドウからはみ出す"))
        if let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
            content.cacheDisplay(in: content.bounds, to: rep)
            let image = NSImage(size: content.bounds.size)
            image.addRepresentation(rep)
            // タイトルバー（ツールバー）を上に重ねる
            if let titlebar = window.standardWindowButton(.closeButton)?.superview?.superview,
               let barRep = titlebar.bitmapImageRepForCachingDisplay(in: titlebar.bounds) {
                titlebar.cacheDisplay(in: titlebar.bounds, to: barRep)
                let composed = NSImage(size: content.bounds.size)
                composed.lockFocus()
                rep.draw(in: NSRect(origin: .zero, size: content.bounds.size))
                let frame = titlebar.convert(titlebar.bounds, to: nil)
                barRep.draw(in: NSRect(x: frame.minX, y: content.bounds.height - frame.height, width: frame.width, height: frame.height))
                composed.unlockFocus()
                if let tiff = composed.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) {
                    try? bitmap.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
                }
            } else {
                try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
            }
        }
        window.close()
        return fits
    }

    private static func splitView(in content: NSView, skippingSelf: Bool = false) -> NSSplitView? {
        var views = skippingSelf ? content.subviews : [content]
        while !views.isEmpty {
            let view = views.removeFirst()
            if let split = view as? NSSplitView { return split }
            views.append(contentsOf: view.subviews)
        }
        return nil
    }

    /// 非同期の確かめを、メインのランループを回しながら待つ
    private static func runAsync(_ body: @escaping @MainActor () async -> Bool) -> Bool {
        var result: Bool?
        Task { @MainActor in result = await body() }
        while result == nil { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        return result ?? false
    }

    private final class Checker {
        var failures = 0
        func check(_ ok: Bool, _ label: String) {
            print((ok ? "OK  " : "NG  ") + label)
            if !ok { failures += 1 }
        }
    }

    // MARK: - 引用

    // 確かめ方: REQ-MTG-052
    static func testCitations() -> Bool {
        let c = Checker()
        // 印の取り出し
        let marks = MinutesCitation.marks(in: "- 価格は 2 案で比べる [07:00] [1:02:34]")
        c.check(marks.map(\.label) == ["07:00", "1:02:34"] && marks.map(\.seconds) == [420, 3754], "印を前から読む（mm:ss と h:mm:ss）")
        c.check(MinutesCitation.marks(in: "決まった［12:34］").count == 1, "全角の［］も読む")
        c.check(MinutesCitation.marks(in: "[12:34](hanasu-time://754)").isEmpty, "Markdown のリンクは印にしない")
        // 取り除き
        c.check(MinutesCitation.strip("- 価格は 2 案で比べる [07:00] [1:02:34]\n- 次［00:10］") == "- 価格は 2 案で比べる\n- 次",
                "取り除くと、前の空白も行末の空白も残らない")
        c.check(MinutesCitation.strip("変えない [リンク](https://example.com)") == "変えない [リンク](https://example.com)", "ほかのかっこは変えない")
        c.check(MinutesCitation.strip("改行する  \n- 次 [00:10]") == "改行する  \n- 次", "印のない行の末尾の空白（Markdown の改行）は残す")
        // 無効の印
        c.check(MinutesCitation.isValid(1500, duration: 1500) && MinutesCitation.isValid(1501, duration: 1500),
                "会議の長さ（+1 秒）までの印は押せる")
        c.check(!MinutesCitation.isValid(1502, duration: 1500), "会議の長さを 1 秒より多く超える印は押せない")
        // プロンプト（17 言語）
        for language in PromptLanguage.allCases {
            let text = Prompts.text("minutes.citations", language: language)
            c.check(text.contains("[12:34]") && text.contains("[1:02:34]") && text.contains("\"at\": \"12:34\""),
                    "引用の指示が \(language.rawValue) にある")
        }
        let instruction = MinutesPrompt.systemInstruction(template: .auto, customPrompt: nil)
        let citations = MinutesPrompt.citationsInstruction
        if let action = instruction.range(of: "<action_items>"), let cite = instruction.range(of: citations),
           let names = instruction.range(of: MinutesPrompt.speakerNamesInstruction) {
            c.check(action.lowerBound < cite.lowerBound && cite.lowerBound < names.lowerBound,
                    "引用の指示は、アクションアイテムの指示のあと・話者の名前の指示の前（Windows 版と同じ組み立て）")
        } else {
            c.check(false, "議事録の指示に引用の指示が入る")
        }
        // 応答の読み取り
        let response = """
        ## 概要
        - リリースは 11 月 20 日 [01:15]

        ## アクションアイテム
        {{ACTION_ITEMS}}

        <action_items>
        [{"owner": "田中", "task": "見積を送る [07:12]", "due": "2026-11-14", "due_note": "14 日まで", "at": "07:12"},
         {"owner": "自分", "task": "承認を取る", "at": "作り話"}]
        </action_items>
        """
        let result = MinutesPrompt.parse(response, title: "定例", language: .ja)
        c.check(result.actionItems.first?.task == "見積を送る" && result.actionItems.first?.at == "07:12",
                "アクションアイテムの at を読み、やることから印を外す")
        c.check(result.actionItems.count == 2 && result.actionItems[1].at == nil, "時刻として読めない at は捨てる")
        let oddAt = MinutesPrompt.decodeItems(#"[{"task": "A", "at": ["03:10", "12:34"]}, {"task": "B", "at": 754}, {"task": "C", "at": "01:00"}]"#)
        c.check(oddAt?.map(\.task) == ["A", "B", "C"] && oddAt?.map(\.at) == [nil, nil, "01:00"],
                "at が文字列でない（配列・数）ときは時刻だけを捨て、アクションアイテムは残す（Windows と同じ）")
        c.check(result.markdown.contains("[01:15]"), "議事録の本文（minutes.md に残るもの）には印を残す")
        let parsed = ActionItem.parse(fromMarkdown: "## アクションアイテム\n- [ ] 見積を送る（担当: 田中 / 期限: 11/14 (金)） [07:12]")
        c.check(parsed.first?.task == "見積を送る" && parsed.first?.owner == "田中" && parsed.first?.at == "07:12",
                "チェックボックスの行からの読み取りが、行末の印に乱されない（DEC-MTG-064）")
        let stripped = MinutesCitation.stripped(result)
        c.check(!stripped.markdown.contains("[01:15]") && stripped.actionItems.allSatisfy { $0.at == nil },
                "縮めて送ったときは、議事録とアクションアイテムから印を外す")
        // 書き出し
        var meeting = Meeting(id: "cite", title: "定例", startedAt: Date(timeIntervalSince1970: 1_793_000_000))
        meeting.duration = 1500
        meeting.minutes = result.markdown
        meeting.actionItems = result.actionItems
        let slack = MeetingExport.slack(meeting) ?? ""
        c.check(!slack.contains("[01:15]") && slack.contains("リリースは 11 月 20 日"), "Slack 向けには印を入れない")
        let text = MeetingExport.plainText(fromMarkdown: MinutesCitation.strip(meeting.minutes ?? ""))
        c.check(!text.contains("[01:15]"), "テキストの書き出しには印を入れない")
        // 縮めて送ったときの報告
        let report = LongInputReport()
        LongInputReport.$current.withValue(report) { LongInputReport.current?.markShortened() }
        c.check(report.shortened && LongInputReport.current == nil, "縮めたことは、議事録を作る間だけ報告に残る")
        return finish(c)
    }

    // MARK: - 文書と一覧

    // 確かめ方: REQ-MTG-050, REQ-MTG-051
    static func testDocument() -> Bool {
        let c = Checker()
        let minutes = """
        # 定例 — 議事録

        ## 概要
        リリースは 11 月 20 日 [01:15]

        ## 話し合った内容
        ### 価格
        - 2 案で比べる

        ## アクションアイテム
        - [ ] 見積を送る（担当: 田中）
        - [ ] 承認を取る（担当: 自分）

        ## 話者についてのメモ
        - 話者1: 田中さん
        """
        let doc = MinutesDocument(markdown: minutes, hidesActionSection: true)
        c.check(doc.titleLine == 0, "先頭のタイトルは文書に出さない")
        c.check(doc.summary.first?.text == "## 概要" && doc.summary.count == 2, "最初の節を要約にする")
        c.check(!doc.body.contains { $0.text.contains("アクションアイテム") || $0.text.contains("見積を送る") },
                "カードを出すときは、アクションアイテムの節を本文に出さない")
        c.check(doc.body.first?.text == "## 話し合った内容" && doc.body.last?.text == "- 話者1: 田中さん", "残りの節は本文に、元の順で出す")
        c.check(doc.summary.first?.number == 2, "行番号は議事録の中の番号のまま（検索の飛び先）")
        let actionLine = minutes.components(separatedBy: "\n").firstIndex(of: "- [ ] 承認を取る（担当: 自分）") ?? -1
        let headingLine = minutes.components(separatedBy: "\n").firstIndex(of: "## アクションアイテム") ?? -1
        c.check(doc.actionRow(forLine: actionLine) == 1 && doc.actionRow(forLine: headingLine) == 0,
                "外した節の行は、カードの同じ順番の行へ読み替える")
        c.check(doc.actionRow(forLine: 2) == nil, "外していない行は読み替えない")
        let kept = MinutesDocument(markdown: minutes, hidesActionSection: false)
        c.check(kept.body.contains { $0.text == "## アクションアイテム" }, "カードが 0 件なら、アクションアイテムの節を本文に出す")
        let english = MinutesDocument(markdown: "# T — Minutes\n\n## Summary\nok\n\n## Action items\n- [ ] a", hidesActionSection: true)
        c.check(english.body.isEmpty && english.summary.count == 2, "ほかの言語のアクションアイテムの見出しも外す")
        let noSections = MinutesDocument(markdown: "# T\nただの文", hidesActionSection: true)
        c.check(noSections.summary.isEmpty && noSections.body.map(\.text) == ["ただの文"], "節がなければ要約を出さず、本文に出す")

        // 一覧の日付のまとまり（基準: 2026-11-11（水）12:00、週は月曜始まり）
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        calendar.firstWeekday = 2
        func date(_ s: String) -> Date {
            let f = DateFormatter()
            f.calendar = calendar
            f.timeZone = calendar.timeZone
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd HH:mm"
            return f.date(from: s)!
        }
        let now = date("2026-11-11 12:00")
        let meetings = [("a", "2026-11-11 09:00"), ("b", "2026-11-10 15:00"), ("c", "2026-11-09 10:00"),
                        ("d", "2026-11-04 10:00"), ("e", "2026-10-20 10:00"), ("f", "2026-09-02 10:00"), ("g", "2026-10-02 10:00")]
            .map { Meeting(id: $0.0, title: $0.0, startedAt: date($0.1)) }
        let groups = MeetingListGrouping.groups(meetings, now: now, calendar: calendar, locale: Locale(identifier: "ja_JP"))
        c.check(groups.map(\.id) == ["today", "yesterday", "thisWeek", "lastWeek", "month-2026-10", "month-2026-9"],
                "今日・昨日・今週・先週・月ごとに分ける（\(groups.map(\.id))）")
        c.check(groups.first(where: { $0.id == "month-2026-10" })?.meetings.map(\.id) == ["e", "g"], "まとまりの中は新しい順")
        c.check(groups.last?.title.contains("9") == true, "月の見出しは言語の書き方（\(groups.last?.title ?? "")）")
        var sundayStart = calendar
        sundayStart.firstWeekday = 1
        let sunday = MeetingListGrouping.groups([Meeting(id: "s", title: "s", startedAt: date("2026-11-08 10:00"))],
                                                now: now, calendar: sundayStart)
        c.check(sunday.first?.id == "thisWeek", "週の始まりは地域の設定に従う（日曜始まりなら 11/8 は今週）")
        return finish(c)
    }

    // MARK: - 再生

    // 確かめ方: REQ-MTG-053
    static func testPlayer() async -> Bool {
        let c = Checker()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hanasu-player-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let me = dir.appendingPathComponent("me.m4a")
        let others = dir.appendingPathComponent("others.m4a")
        let broken = dir.appendingPathComponent("broken.m4a")
        do {
            try writeTone(to: me, seconds: 3)
            try writeTone(to: others, seconds: 2)
            try Data("not audio".utf8).write(to: broken)
        } catch {
            c.check(false, "確かめ用の音声を書けた: \(error.localizedDescription)")
            return finish(c)
        }
        do {
            let built = try await MeetingPlayer.makeComposition(urls: [.me: me, .others: others], offsets: [.me: 0.2, .others: 1.5])
            c.check(built.trackIDs.count == 2 && built.composition.tracks(withMediaType: .audio).count == 2, "2 つのチャンネルを別のトラックに重ねる")
            c.check(abs(built.duration - 3.5) < 0.15, "ずれた分だけ後ろに置く（長さ \(String(format: "%.2f", built.duration)) ≒ 3.5）")
            let range = built.composition.tracks(withMediaType: .audio).compactMap { $0.segments.first { !$0.isEmpty }?.timeMapping.target.start.seconds }
            c.check(range.contains { abs($0 - 1.5) < 0.01 } && range.contains { abs($0 - 0.2) < 0.01 }, "チャンネルごとのずれで始まる（\(range)）")
        } catch {
            c.check(false, "2 つの音声を重ねられる: \(error.localizedDescription)")
        }
        do {
            let built = try await MeetingPlayer.makeComposition(urls: [.others: others], offsets: [:])
            c.check(built.trackIDs.keys.sorted { $0.rawValue < $1.rawValue } == [.others], "片方だけでも再生できる")
        } catch {
            c.check(false, "片方だけでも再生できる: \(error.localizedDescription)")
        }
        do {
            _ = try await MeetingPlayer.makeComposition(urls: [.me: broken], offsets: [:])
            c.check(false, "読めない音声は失敗にする")
        } catch {
            c.check(true, "読めない音声は失敗にする（\(error.localizedDescription)）")
        }
        // ずれ（meeting.json の audioStartOffsets。古い会議は 0）
        var meeting = Meeting(id: "p", title: "p", startedAt: Date())
        c.check(MeetingPlayer.offsets(for: meeting) == [.me: 0, .others: 0], "ずれのない古い会議は 0 として扱う")
        meeting.audioStartOffsets = ["me": 0.12, "others": 0.31]
        let data = (try? JSONEncoder().encode(meeting)) ?? Data()
        let decoded = try? JSONDecoder().decode(Meeting.self, from: data)
        c.check(decoded.map(MeetingPlayer.offsets(for:)) == [.me: 0.12, .others: 0.31], "ずれを meeting.json に残して読む（Windows と同じキー）")
        // 再生位置の発言（0.25 秒ごとに見るので、発言の開始から 0.5 秒以内に強調が移る）
        let starts: [Double] = [0, 4.0, 9.5]
        c.check(MeetingPlayer.blockIndex(at: 3.99, starts: starts) == 0 && MeetingPlayer.blockIndex(at: 4.0, starts: starts) == 1,
                "発言が始まった時刻から、その発言を再生位置にする")
        let lag = stride(from: 0.0, to: 20, by: MeetingPlayer.tick).first { $0 >= 9.5 }.map { $0 - 9.5 } ?? 1
        c.check(MeetingPlayer.tick <= 0.25 && lag <= 0.5, "再生位置を見る間隔は 0.25 秒（強調の遅れ \(lag) 秒 ≦ 0.5）")
        c.check(MeetingPlayer.blockIndex(at: -1, starts: starts) == nil, "どの発言も始まっていなければ強調しない")
        // 再生できないとき
        c.check(MeetingPlayer.blockReason(recording: true, dictating: false) != nil, "会議の記録中は再生できない")
        c.check(MeetingPlayer.blockReason(recording: false, dictating: true) != nil, "音声入力中は再生できない")
        c.check(MeetingPlayer.blockReason(recording: false, dictating: false) == nil, "どちらでもなければ再生できる")
        return finish(c)
    }

    /// 確かめ用の音声（AAC 16kHz モノラル、記録と同じ形）
    private static func writeTone(to url: URL, seconds: Double) throws {
        let rate = 16_000.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(rate * seconds)) else { return }
        buffer.frameLength = buffer.frameCapacity
        if let samples = buffer.floatChannelData?[0] {
            for i in 0..<Int(buffer.frameLength) { samples[i] = Float(sin(2 * Double.pi * 440 * Double(i) / rate) * 0.2) }
        }
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        try file.write(from: buffer)
    }

    private static func finish(_ c: Checker) -> Bool {
        print(c.failures == 0 ? "すべて OK" : "NG が \(c.failures) 件")
        return c.failures == 0
    }
}

// MARK: - 確認用の描き出しの組み合わせ

/// 確認用の描き出し（画面の外の NSHostingView）で、文書と後ろ側のパネルを横に並べて描く（inspector は使わない）
struct MeetingDetailPreview: View {
    let meeting: Meeting
    @ObservedObject var recorder: MeetingRecorder
    var jump: MeetingJump?
    @StateObject private var panel: MeetingPanelState

    /// initialTab: 4 なら AI チャット、ほかは文字起こし
    init(meeting: Meeting, recorder: MeetingRecorder, jump: MeetingJump? = nil, initialTab: Int? = nil,
         initialSelecting: Bool = false, onDelete: (() -> Void)? = nil) {
        self.meeting = meeting
        self.recorder = recorder
        self.jump = jump
        _panel = StateObject(wrappedValue: MeetingPanelState(tab: initialTab.map { $0 == 4 ? .chat : .transcript },
                                                             selecting: initialSelecting))
    }

    var body: some View {
        HStack(spacing: 0) {
            MeetingDetailView(meeting: meeting, recorder: recorder, panel: panel, jump: jump, embedsInspector: false, onDelete: {})
            Divider()
            MeetingDetailInspector(meeting: meeting, recorder: recorder, panel: panel, highlight: jump?.terms ?? [])
                .frame(width: 360)
                .onAppear {
                    if let jump, case .transcript(let blockID, _, _) = jump.location {
                        panel.focus = TranscriptFocus(target: .block(blockID))
                    }
                }
        }
    }
}

/// 確認用の描き出しで、記録中の文字起こしと後ろ側のパネル（メモ｜AI チャット）を横に並べて描く
struct LivePreview: View {
    @ObservedObject var recorder: MeetingRecorder
    @StateObject private var panel = MeetingPanelState()

    var body: some View {
        HStack(spacing: 0) {
            LiveTranscriptView(recorder: recorder, timeJump: panel.liveTimeJump)
            Divider()
            LiveInspector(recorder: recorder, panel: panel).frame(width: 340)
        }
    }
}
