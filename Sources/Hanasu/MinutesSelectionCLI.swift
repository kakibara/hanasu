import AppKit
import SwiftUI

// 議事録に使う発言の選び方（範囲・除外・オフレコ。MinutesSelection.swift）の確認用の CLI モード:
//   Hanasu --test-minutes-selection
//     使う・使わないの決まり、表示のまとまり、AI に渡す文字起こし・書き出し、meeting.json の読み書き、
//     スリープでの切り詰めとオフレコを確かめる。AI も ~/Documents も使わない。失敗があれば終了コード 1
//   Hanasu --render-minutes-selection <出力フォルダ>
//     文字起こしの帯・チェックボックス・使わない発言の見た目、議事録の「作り直すと反映」、記録中のオフレコを PNG にする
// 確かめ方: REQ-MTG-044, REQ-MTG-045, REQ-MTG-046
@MainActor
enum MinutesSelectionCLI {
    static func runIfRequested(_ args: [String] = CommandLine.arguments) {
        if args.contains("--test-minutes-selection") {
            exit(selfTest() ? 0 : 1)
        }
        if let index = args.firstIndex(of: "--render-minutes-selection"), index + 1 < args.count {
            do {
                try render(to: URL(fileURLWithPath: args[index + 1], isDirectory: true))
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
                exit(1)
            }
        }
    }

    // MARK: - 架空の会議

    /// 前後の雑談・接続確認・オフレコ・通訳を含む架空の会議
    static func sampleMeeting() -> Meeting {
        var meeting = Meeting(id: "selection-sample", title: "架空商事 定例（サンプル）", startedAt: Date(timeIntervalSince1970: 1_793_000_000))
        meeting.duration = 1500
        meeting.status = .done
        let rows: [(String, Double, String)] = [
            ("me", 2, "週末どこか行きました？"),
            ("spk1", 8, "キャンプに行ってました。"),
            ("me", 40, "では始めます。聞こえますか？"),
            ("spk1", 45, "聞こえています。画面も見えています。"),
            ("me", 60, "今日はリリース日程と価格の確認です。"),
            ("spk1", 75, "リリースは 11 月 20 日で進めています。"),
            ("spk2", 90, "（通訳）The release is on November 20."),
            ("spk1", 300, "ここから人事の話なので、記録に残さないでください。"),
            ("spk1", 320, "来月、佐藤さんが異動になります。"),
            ("me", 420, "価格は 2 案で比べましょう。"),
            ("spk1", 440, "A 案は月 3 万円、すみません 5 万円です。"),
            ("me", 1400, "では今日はここまでにします。"),
            ("spk1", 1450, "次の会議の準備をしましょうか。"),
        ]
        meeting.utterances = rows.map { Utterance(speaker: $0.0, start: $0.1, end: $0.1 + 4, text: $0.2) }
        return meeting
    }

    // MARK: - 確かめる

    private static func selfTest() -> Bool {
        var failures: [String] = []
        func check(_ ok: Bool, _ message: String) {
            print(ok ? "ok: \(message)" : "NG: \(message)")
            if !ok { failures.append(message) }
        }
        let base = sampleMeeting()
        func id(at start: Double) -> UUID { base.utterances.first { $0.start == start }!.id }
        func texts(_ blocks: [Utterance]) -> [String] { blocks.map(\.text) }

        // 何も選んでいなければ、今までと同じ（mergedBlocks と同じまとまり）
        check(base.blocksForMinutes() == base.mergedBlocks(), "何も選ばなければ mergedBlocks と同じ")
        check(base.minutesOutdated == nil && !base.hasMinutesSelection, "最初は選び方なし")

        var m = base
        m.setMinutesRange(from: .some(40))
        m.setMinutesRange(to: .some(1400))
        m.setExcluded([id(at: 440)], excluded: true)
        m.setSpeakerExcluded("spk2", excluded: true)
        m.offRecord = [OffRecordSpan(start: 300, end: 400)]
        check(m.minutesOutdated == true, "選び方を変えたら minutesOutdated")
        check(m.minutesUse(of: m.utterances[0]) == .outsideRange, "範囲の前は範囲外")
        check(m.minutesUse(of: m.utterances[12]) == .outsideRange, "範囲の後は範囲外")
        check(m.minutesUse(of: m.utterances[6]) == .speakerExcluded, "除いた話者")
        check(m.minutesUse(of: m.utterances[7]) == .offRecord && m.minutesUse(of: m.utterances[8]) == .offRecord, "オフレコの区間")
        check(m.minutesUse(of: m.utterances[10]) == .excluded, "除いた発言")
        // 除いた発言はどの理由より先に出す
        var both = m
        both.setExcluded([id(at: 320)], excluded: true)
        check(both.minutesUse(of: both.utterances[8]) == .excluded, "除外はオフレコより先")

        let used = texts(m.blocksForMinutes())
        check(used == ["では始めます。聞こえますか？", "聞こえています。画面も見えています。", "今日はリリース日程と価格の確認です。",
                       "リリースは 11 月 20 日で進めています。", "価格は 2 案で比べましょう。", "では今日はここまでにします。"],
              "使う発言だけを渡す: \(used)")
        let prompt = m.transcriptForPrompt()
        check(!prompt.contains("異動") && !prompt.contains("キャンプ") && !prompt.contains("通訳") && !prompt.contains("3 万円"),
              "AI に渡す文字起こしに使わない発言が入らない")
        check(!m.transcriptForPromptMarkingHighlights().contains("異動"), "印つきの文字起こしにも入らない")
        let markdown = m.transcriptMarkdown()
        check(!markdown.contains("異動") && markdown.contains("（7 件）"), "書き出しは使う発言だけで、除いた件数を書く")
        let chat = MeetingChat.material(for: m).lines.map(\.text)
        check(!chat.contains { $0.contains("異動") }, "AI チャットに使わない発言を渡さない")

        // 表示のまとまり: 同じ話者が続いても、使う・使わないが変わるところで分ける
        var split = base
        split.utterances = [
            Utterance(speaker: "me", start: 0, end: 1, text: "A"),
            Utterance(speaker: "me", start: 1.5, end: 2.5, text: "B"),
            Utterance(speaker: "me", start: 3, end: 4, text: "C"),
        ]
        check(split.displayBlocks().count == 1, "使い方が同じならまとめる")
        split.setExcluded([split.utterances[1].id], excluded: true)
        let shown = split.displayBlocks()
        check(shown.map(\.block.text) == ["A", "B", "C"] && shown.map(\.use) == [.used, .excluded, .used], "変わるところで分ける")
        check(texts(split.blocksForMinutes()) == ["A", "C"], "使わない発言をまたいでまとめない")

        // 「ここまで」はまとまりの最後の発言まで入れる
        var merged = split
        merged.clearMinutesSelection()
        let block = merged.displayBlocks()[0]
        merged.setMinutesRange(to: .some(block.lastStart))
        check(merged.usedUtterances.count == 3, "「ここまで」でまとまりの全部が入る")

        // 範囲の外の発言を使うと、範囲を広げる。最初が最後より後になったら、もう一方を外す
        var widen = base
        widen.setMinutesRange(from: .some(60))
        widen.include([id(at: 40)])
        check(widen.minutesFrom == 40, "範囲の外を使うと範囲を広げる")
        widen.setMinutesRange(to: .some(20))
        check(widen.minutesTo == 20 && widen.minutesFrom == nil, "最後が最初より前なら最初を外す")

        // 話者・オフレコの解除と、すべて元に戻す
        var restore = m
        restore.setSpeakerExcluded("spk2", excluded: false)
        restore.removeOffRecord(restore.offRecord![0].id)
        check(restore.excludedSpeakers == nil && restore.offRecord == nil, "話者とオフレコを解除できる")
        restore.clearMinutesSelection()
        check(!restore.hasMinutesSelection && restore.usedUtterances.count == base.utterances.count, "すべて元に戻す")

        // meeting.json の読み書き（キーと、古い会議の読み込み）
        do {
            let data = try JSONEncoder().encode(m)
            let json = String(decoding: data, as: UTF8.self)
            check(["\"minutesFrom\"", "\"minutesTo\"", "\"excludedUtterances\"", "\"excludedSpeakers\"", "\"offRecord\"", "\"minutesOutdated\""]
                .allSatisfy(json.contains), "meeting.json のキー")
            let decoded = try JSONDecoder().decode(Meeting.self, from: data)
            check(decoded.blocksForMinutes() == m.blocksForMinutes() && decoded.offRecord == m.offRecord, "読み直しても同じ")
            let old = try JSONEncoder().encode(base)
            check(try JSONDecoder().decode(Meeting.self, from: old).hasMinutesSelection == false, "古い会議は選び方なしで読める")
        } catch {
            check(false, "meeting.json の読み書き: \(error)")
        }

        // スリープ前までで止めたら、スリープの後のオフレコは消し、終わりをそろえる
        var slept = base
        slept.offRecord = [OffRecordSpan(start: 100, end: nil), OffRecordSpan(start: 900, end: 950)]
        MeetingSleepCut.apply(to: &slept, point: MeetingSleepPoint(at: Date(), elapsed: 500, audioEnds: [:]))
        check(slept.offRecord?.count == 1 && slept.offRecord?[0].end == 500, "スリープで切ったらオフレコもそろえる")

        print(failures.isEmpty ? "all passed" : "\(failures.count) failed")
        return failures.isEmpty
    }

    // MARK: - 画面

    private static func render(to dir: URL) throws {
        _ = NSApplication.shared
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let recorder = MeetingRecorder()
        var meeting = sampleMeeting()
        meeting.minutes = "## 決まったこと\n- リリースは 11 月 20 日"
        meeting.speakerNames = ["spk1": "田中", "spk2": "通訳"]

        // 何も選んでいないとき（使い方の案内）
        try MeetingNotesPreview.write(MeetingDetailView(meeting: meeting, recorder: recorder, initialTab: 1).frame(width: 720, height: 560),
                                      to: dir.appendingPathComponent("transcript-plain.png"))
        // 範囲・除外・話者・オフレコを選んだあと（作り直すと反映）
        let first = meeting.utterances
        meeting.setMinutesRange(from: .some(40))
        meeting.setMinutesRange(to: .some(1400))
        meeting.setExcluded([first[10].id], excluded: true)
        meeting.setSpeakerExcluded("spk2", excluded: true)
        meeting.offRecord = [OffRecordSpan(start: 300, end: 400)]
        try MeetingNotesPreview.write(MeetingDetailView(meeting: meeting, recorder: recorder, initialTab: 1).frame(width: 720, height: 600),
                                      to: dir.appendingPathComponent("transcript-selected.png"))
        try MeetingNotesPreview.write(
            MeetingDetailView(meeting: meeting, recorder: recorder, initialTab: 1, initialSelecting: true).frame(width: 720, height: 600),
            to: dir.appendingPathComponent("transcript-selecting.png"))
        try MeetingNotesPreview.write(MeetingDetailView(meeting: meeting, recorder: recorder, initialTab: 0).frame(width: 720, height: 360),
                                      to: dir.appendingPathComponent("minutes-outdated.png"))

        // 記録中のオフレコ
        var live = Meeting(id: "live", title: "週次定例（サンプル）", startedAt: Date().addingTimeInterval(-420))
        live.offRecord = [OffRecordSpan(start: 300, end: nil)]
        let lines: [MeetingRecorder.LiveLine] = [
            .init(channel: .others, start: 250, text: "リリースは 11 月 20 日で進めています。"),
            .init(channel: .others, start: 310, text: "ここからは記録に残さないでください。"),
            .init(channel: .me, start: 330, text: "分かりました。"),
        ]
        recorder.showPreviewForRendering(live, lines: lines)
        try MeetingNotesPreview.write(LiveTranscriptView(recorder: recorder).frame(width: 760, height: 420),
                                      to: dir.appendingPathComponent("live-offrecord.png"))
        print("wrote: \(dir.path)")
    }
}
