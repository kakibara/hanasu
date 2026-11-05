import AppKit
import Foundation
import SwiftUI

// 会議の AI チャットの確認用の CLI モード:
//   Hanasu --test-meeting-chat
//     プロンプトの組み立て（記録中の時点・確定前の発言・メモ・それまでの会話・長さの上限）・答えの時刻のリンク・
//     メモへの変換を、決めた例で確かめる（AI は呼ばない）。失敗があれば終了コード 1。
//   Hanasu --chat-meeting <会議のフォルダ> --ask <質問> [--ask <続けての質問> ...] [--at <mm:ss>] [--show-prompt]
//          [--ai gemini|claude|local|apple] [--model <id>]
//     保存した会議について、質問を順に送って会話する（2 つめからは、前のやりとりを踏まえて答える）。
//     --at を付けると、その時刻までの文字起こしとメモだけを「記録中」として渡す（記録中のチャットの再現）。
//   Hanasu --render-meeting-chat <出力フォルダ>
//     架空の会議で、記録中の右側の AI チャット（会話の前・会話のあと）と、記録のあとの「AI チャット」タブを PNG にする
// 認証は --ask-meetings と同じ順に探す（TextAIClient.cli）。
// 確かめ方: REQ-MTG-040, REQ-MTG-041
enum MeetingChatCLI {
    @MainActor
    static func runIfRequested(_ args: [String] = CommandLine.arguments) {
        func value(after flag: String) -> String? {
            args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        }

        if args.contains("--test-meeting-chat") {
            let results = MeetingChat.selfTest()
            results.forEach { print($0) }
            exit(results.allSatisfy { $0.hasPrefix("OK") } ? 0 : 1)
        }

        if let dir = value(after: "--render-meeting-chat") {
            do {
                try MeetingChatPreview.render(to: URL(fileURLWithPath: dir))
                exit(0)
            } catch {
                fail(error.localizedDescription)
            }
        }

        guard let folder = value(after: "--chat-meeting") else { return }
        let questions = args.indices.filter { args[$0] == "--ask" && args.indices.contains($0 + 1) }.map { args[$0 + 1] }
        guard !questions.isEmpty else { fail("--ask <質問> を 1 つ以上付けてください") }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: folder).appendingPathComponent("meeting.json")),
              let meeting = try? decoder.decode(Meeting.self, from: data) else {
            fail("会議を読めませんでした（meeting.json のあるフォルダを渡してください）: \(folder)")
        }

        var material = MeetingChat.material(for: meeting)
        if let atText = value(after: "--at") {
            guard let at = MeetingNote.parseClock(atText) else { fail("--at は mm:ss か h:mm:ss で書いてください: \(atText)") }
            // その時刻まで記録した、記録中の会議として渡す
            var cut = meeting
            cut.notes = meeting.notes?.filter { ($0.time ?? .infinity) <= at }
            material = MeetingChat.material(for: cut)
            material.live = true
            material.elapsed = at
            material.lines = material.lines.filter { $0.time <= at }
        }

        let prepared = material
        Task { @MainActor in
            let material = prepared
            do {
                let settings = AppSettings.shared
                let client = try TextAIClient.cli(args: args, settings: settings, for: .meeting, timeout: 180)
                let model = TextAIClient.cliModel(args: args, settings: settings, for: .meeting)
                print("[会議] \(meeting.title)・発言 \(material.lines.count) 件"
                      + (material.live ? "（\(Meeting.clock(material.elapsed)) まで。記録中として渡す）" : ""))
                var history: [MeetingChat.Message] = []
                for question in questions {
                    let started = Date()
                    let result = try await MeetingChat.reply(question: question, material: material, history: history,
                                                             client: client, model: model)
                    if args.contains("--show-prompt") { print("\n----- プロンプト -----\n\(result.prompt.text)\n---------------------") }
                    print("\n> \(question)")
                    print(String(format: "[答え %@ %.1fs・プロンプト %d 文字・それまでの会話 %d 件]", model,
                                 Date().timeIntervalSince(started), result.prompt.text.count,
                                 MeetingChat.answeredTurns(history).count))
                    print(result.text)
                    history.append(MeetingChat.Message(role: .user, text: question))
                    history.append(MeetingChat.Message(role: .assistant, text: result.text,
                                                       coveredUntil: result.prompt.coveredUntil, lineCount: result.prompt.lineCount))
                }
                exit(0)
            } catch {
                fail("\(error.localizedDescription) (\(error))")
            }
        }
        RunLoop.main.run()
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("error: \(message)\n".utf8))
        exit(1)
    }
}

/// 見た目の確認用の描き出し（--render-meeting-chat）
enum MeetingChatPreview {
    @MainActor
    static func render(to directory: URL) throws {
        _ = NSApplication.shared
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var meeting = Meeting(id: "preview-chat", title: "週次定例（サンプル）", startedAt: Date().addingTimeInterval(-754))
        meeting.notes = [
            MeetingNote(kind: .note, time: 65, text: "リリースは 11/20 で確定？"),
            MeetingNote(kind: .highlight, time: 690, text: "β版の対象を 3 社に絞る"),
        ]
        let lines: [MeetingRecorder.LiveLine] = [
            .init(channel: .others, start: 612, text: "リリース日は 11 月 20 日で確定とします。"),
            .init(channel: .me, start: 630, text: "了解です。価格表の更新は佐藤さんにお願いできますか？"),
            .init(channel: .others, start: 640, text: "β版はまず 3 社に絞って出したいと思っています。"),
            .init(channel: .me, start: 652, text: "3 社だとどこを想定していますか？"),
            .init(channel: .others, start: 660, text: "既存のお客さまのうち、利用頻度が高いところからです。"),
            .init(channel: .me, start: 701, text: "分かりました。選び方の基準を来週までにまとめましょう。"),
        ]
        let recorder = MeetingRecorder()
        recorder.showPreviewForRendering(meeting, lines: lines, volatileOthers: "そうですね、基準は利用頻度と")

        // 右側を AI チャットにして描く（ユーザーの設定は描いたあとに戻す）
        let key = "meetingLiveSidePanel"
        let previous = UserDefaults.standard.string(forKey: key)
        UserDefaults.standard.set(LiveSidePanelMode.chat.rawValue, forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }

        let chat = MeetingChatStore.shared.model(for: meeting.id)
        try MeetingNotesPreview.write(LiveTranscriptView(recorder: recorder).frame(width: 860, height: 620),
                                      to: directory.appendingPathComponent("live-chat-empty.png"))
        chat.setMessagesForPreview(sampleConversation, draft: "価格表の更新はいつまで？")
        try MeetingNotesPreview.write(LiveTranscriptView(recorder: recorder).frame(width: 860, height: 620),
                                      to: directory.appendingPathComponent("live-chat.png"))

        // 記録のあとの「AI チャット」タブ
        var done = meeting
        done.id = "preview-chat-done"
        done.status = .done
        done.duration = 1_800
        done.utterances = lines.map {
            Utterance(speaker: $0.channel == .me ? "me" : "spk1", start: $0.start, end: $0.start + 8, text: $0.text)
        }
        done.speakerNames = ["spk1": "田中"]
        MeetingChatStore.shared.model(for: done.id).setMessagesForPreview(sampleConversation)
        try MeetingNotesPreview.write(MeetingDetailView(meeting: done, recorder: recorder, initialTab: 4).frame(width: 760, height: 620),
                                      to: directory.appendingPathComponent("detail-chat.png"))
    }

    private static let sampleConversation: [MeetingChat.Message] = [
        MeetingChat.Message(role: .user, text: "ここまでに決まったことと、誰が何をするか（宿題・TODO）を箇条書きで挙げてください。"),
        MeetingChat.Message(role: .assistant, text: """
        **決まったこと**
        - リリースは 11 月 20 日 [10:12]
        - β版はまず 3 社に絞る [10:40]

        **宿題**
        - 価格表の更新: 佐藤さん（依頼中・未確定）[10:30]
        - 3 社の選び方の基準をまとめる: 自分（来週まで）[11:41]
        """, coveredUntil: 745, lineCount: 6),
        MeetingChat.Message(role: .user, text: "3 社の候補は具体的に出ていた？"),
        MeetingChat.Message(role: .assistant, text: """
        具体的な社名は出ていません。「既存のお客さまのうち、利用頻度が高いところから」という方針だけです [11:00]。
        候補を聞くなら「利用頻度の目安（例: 週何回以上）はありますか？」が使えます。
        """, coveredUntil: 752, lineCount: 6),
    ]
}
