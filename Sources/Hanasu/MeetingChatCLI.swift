import AppKit
import Foundation
import SwiftUI

// 会議の AI チャットの確認用の CLI モード:
//   Hanasu --test-meeting-chat
//     プロンプトの組み立て（記録中の時点・確定前の発言・メモ・それまでの会話・長さの上限）・答えの時刻のリンク・
//     メモへの変換を、決めた例で確かめる（AI は呼ばない）。失敗があれば終了コード 1。
//   Hanasu --chat-meeting <会議のフォルダ> --ask <質問> [--quick <よく使う質問の id>] [--ask ...] [--at <mm:ss>] [--live]
//          [--pending <相手の途中の発言>] [--show-prompt] [--ai gemini|claude|local|apple] [--model <id>]
//     保存した会議について、質問を書いた順に送って会話する（2 つめからは、前のやりとりを踏まえて答える）。
//     --quick はよく使う質問の文面で聞く（asked は「何を聞かれた？」と同じく、直近 10 分だけを会話なしで渡す）。
//     --at を付けると、その時刻までの文字起こしとメモだけを「記録中」として渡す（記録中のチャットの再現）。
//     --live を付けると、記録中と同じ形にする（話者はチャンネルから「自分／相手」、発言ごとに --at で切る）。
//     --pending は、相手の確定前の途中結果として --at の時点に足す。かかった秒数も出す。
//   Hanasu --render-meeting-chat <出力フォルダ>
//     架空の会議で、記録中の右側の AI チャット（会話の前・会話のあと）と、記録のあとの「AI チャット」タブを PNG にする
// 認証は --ask-meetings と同じ順に探す（TextAIClient.cli）。
// 確かめ方: REQ-MTG-040, REQ-MTG-041, REQ-MTG-047
enum MeetingChatCLI {
    @MainActor
    static func runIfRequested(_ args: [String] = CommandLine.arguments) {
        func value(after flag: String) -> String? {
            args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        }

        if args.contains("--test-meeting-chat") {
            Task { @MainActor in
                // 確かめ方: REQ-MTG-047
                let results = MeetingChat.selfTest() + MeetingChat.askedSelfTest() + (await MeetingAskedQuestion.selfTest())
                results.forEach { print($0) }
                exit(results.allSatisfy { $0.hasPrefix("OK") } ? 0 : 1)
            }
            RunLoop.main.run()
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
        // --ask と --quick を書いた順に送る
        var questions: [MeetingChat.QuickPrompt] = []
        for index in args.indices where args.indices.contains(index + 1) {
            if args[index] == "--ask" {
                questions.append(MeetingChat.QuickPrompt(id: "", label: args[index + 1], symbol: "", question: args[index + 1]))
            } else if args[index] == "--quick" {
                guard let quick = MeetingChat.quickPrompts.first(where: { $0.id == args[index + 1] }) else {
                    fail("--quick は \(MeetingChat.quickPrompts.map(\.id).joined(separator: " / ")) のどれかです: \(args[index + 1])")
                }
                questions.append(quick)
            }
        }
        guard !questions.isEmpty else { fail("--ask <質問> か --quick <id> を 1 つ以上付けてください") }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: folder).appendingPathComponent("meeting.json")),
              let meeting = try? decoder.decode(Meeting.self, from: data) else {
            fail("会議を読めませんでした（meeting.json のあるフォルダを渡してください）: \(folder)")
        }

        var material = MeetingChat.material(for: meeting)
        var notesForAsked = meeting.allNotes
        if args.contains("--live") {
            // 記録中と同じ形: 話者はチャンネルから「自分／相手」、発言ごとに切る、オフレコの発言は渡さない
            let at = value(after: "--at").flatMap(MeetingNote.parseClock) ?? meeting.duration
            notesForAsked = meeting.allNotes.filter { ($0.time ?? .infinity) <= at }
            var cut = meeting
            cut.notes = notesForAsked
            material = MeetingChat.Material(
                title: meeting.title, startedAt: meeting.startedAt, live: true, elapsed: at,
                lines: meeting.utterances.filter { $0.start <= at && !meeting.isOffRecord(at: $0.start) }
                    .sorted { $0.start < $1.start }
                    .map { MeetingChat.Line(time: $0.start, speaker: Meeting.promptLabel(for: $0.speaker == "me" ? "me" : "others"),
                                            text: $0.text) },
                notes: cut.notesForPrompt())
            if let pending = value(after: "--pending") {
                material.pending = [MeetingChat.Line(time: at, speaker: Meeting.promptLabel(for: "others"), text: pending)]
            }
        } else if let atText = value(after: "--at") {
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
                for quick in questions {
                    let started = Date()
                    let question = quick.question
                    // 要件: REQ-MTG-047（「何を聞かれた？」は直近 10 分だけを、会話なしで渡す。DEC-MTG-095）
                    let result = quick.isAsked
                        ? try await MeetingChat.reply(question: question,
                                                      material: MeetingChat.askedMaterial(from: material, notes: notesForAsked),
                                                      history: [], client: client, model: model)
                        : try await MeetingChat.reply(question: question, material: material, history: history,
                                                      client: client, model: model)
                    if args.contains("--show-prompt") { print("\n----- プロンプト -----\n\(result.prompt.text)\n---------------------") }
                    print("\n> \(quick.isAsked ? quick.label : question)")
                    print(String(format: "[答え %@ %.1fs・プロンプト %d 文字・それまでの会話 %d 件]", model,
                                 Date().timeIntervalSince(started), result.prompt.text.count,
                                 MeetingChat.answeredTurns(history).count))
                    print(result.text)
                    history.append(MeetingChat.Message(role: .user, text: question, label: quick.isAsked ? quick.label : nil))
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
        try MeetingNotesPreview.write(LivePreview(recorder: recorder).frame(width: 1240, height: 620),
                                      to: directory.appendingPathComponent("live-chat-empty.png"))
        chat.setMessagesForPreview(sampleConversation, draft: "価格表の更新はいつまで？")
        try MeetingNotesPreview.write(LivePreview(recorder: recorder).frame(width: 1240, height: 620),
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
        try MeetingNotesPreview.write(MeetingDetailPreview(meeting: done, recorder: recorder, initialTab: 4).frame(width: 1140, height: 620),
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

extension MeetingChat {
    // MARK: - 確認用

    // 確かめ方: REQ-MTG-047
    /// 「何を聞かれた？」で渡す記録の切り方・相手の直近の発言・よく使う質問の出し分けを確かめる（AI は呼ばない）
    static func askedSelfTest() -> [String] {
        var results: [String] = []
        func check(_ name: String, _ ok: Bool) { results.append("\(ok ? "OK" : "NG") \(name)") }
        let me = Meeting.promptLabel(for: "me"), others = Meeting.promptLabel(for: "others")
        // 0 秒から 30 秒ごとに 40 発言（〜19:30）。今は 20:00
        let lines = (0..<40).map { Line(time: Double($0 * 30), speaker: $0 % 2 == 0 ? me : others, text: "発言\($0)") }
        let material = Material(title: "定例", startedAt: Date(timeIntervalSince1970: 0), live: true, elapsed: 1_200,
                                lines: lines, pending: [Line(time: 1_200, speaker: others, text: "どう思いますか")])
        let notes = [MeetingNote(kind: .note, time: 60, text: "古いメモ"), MeetingNote(kind: .highlight, time: 900, text: "新しい印"),
                     MeetingNote(kind: .note, time: nil, text: "時刻なし")]
        let asked = askedMaterial(from: material, notes: notes)
        check("直近 10 分の発言だけを渡す", asked.lines.first?.time == 600 && asked.lines.count == 20 && asked.omittedBeforeWindow == 20)
        check("確定前の途中結果も渡す", asked.pending.map(\.text) == ["どう思いますか"])
        check("直近 10 分のメモと印だけを渡す", asked.notes?.contains("新しい印") == true && asked.notes?.contains("古いメモ") == false
              && asked.notes?.contains("時刻なし") == false)
        let prompt = MeetingChat.prompt(question: askedPrompt.question, material: asked, history: [])
        check("省いた前の発言の数を書く", prompt.text.contains(Prompts.text("chat.transcript.recentOnly", ["minutes": "10", "count": "20"])))
        check("<pending_transcript> に質問が入る", prompt.text.contains("<pending_transcript>\n[20:00] \(others): どう思いますか"))
        let recent = recentOthers(in: material)
        check("相手の直近の発言 3 つ（確定前を最後に）", recent.map(\.text) == ["発言37", "発言39", "どう思いますか"])
        check("相手の発言がなければ空", recentOthers(in: Material(title: "", startedAt: Date(), live: true, elapsed: 0,
                                                                 lines: [Line(time: 0, speaker: me, text: "a")])).isEmpty)
        check("「何を聞かれた？」は記録中だけ先頭に出す", quickPrompts(live: true).first?.isAsked == true
              && !quickPrompts(live: false).contains { $0.isAsked } && quickPrompts(live: false).count == quickPrompts.count - 1)
        check("「何を聞かれた？」の文面がある", !askedPrompt.question.isEmpty && askedPrompt.question != "chat.quick.asked")
        return results
    }

    // 確かめ方: REQ-MTG-040, REQ-MTG-041
    /// プロンプトの組み立て・時刻のリンク・メモへの変換を確かめる（AI は呼ばない）。結果の行を返す
    static func selfTest() -> [String] {
        var results: [String] = []
        func check(_ name: String, _ ok: Bool) { results.append("\(ok ? "OK" : "NG") \(name)") }

        let lines = (0..<10).map { Line(time: Double($0 * 30), speaker: $0 % 2 == 0 ? "自分" : "相手", text: "発言\($0)") }
        let material = Material(title: "定例 \"週次\"", startedAt: Date(timeIntervalSince1970: 0), live: true, elapsed: 305,
                                lines: lines, pending: [Line(time: 305, speaker: "相手", text: "途中")],
                                notes: "[01:00] メモ")
        let history: [Message] = [
            Message(role: .user, text: "最初の質問"),
            Message(role: .assistant, text: "最初の答え"),
            Message(role: .user, text: "失敗した質問"),
        ]
        let prompt = MeetingChat.prompt(question: "今の質問", material: material, history: history)
        check("記録中の時点を書く", prompt.text.contains("status=\"記録中（録音開始から 05:05 の時点）\""))
        check("文字起こしを全部渡す", prompt.text.contains("[04:30] 相手: 発言9") && prompt.omittedLines == 0)
        check("確定前の発言を分けて渡す", prompt.text.contains("<pending_transcript>\n[05:05] 相手: 途中"))
        check("メモを渡す", prompt.text.contains("<user_notes>\n[01:00] メモ"))
        check("それまでの会話を渡す", prompt.text.contains("<user>\n最初の質問\n</user>\n<assistant>\n最初の答え\n</assistant>"))
        check("答えのない質問は渡さない", !prompt.text.contains("失敗した質問"))
        check("今の質問は最後", prompt.text.hasSuffix("<question>\n今の質問\n</question>"))
        check("タイトルの引用符を置き換える", prompt.text.contains("title=\"定例 '週次'\""))

        var small = Options()
        small.maxTranscriptCharacters = 40
        let truncated = MeetingChat.prompt(question: "q", material: material, history: [], options: small)
        check("上限を超えたら古い発言を省く", truncated.omittedLines > 0 && truncated.text.contains("[04:30] 相手: 発言9")
              && !truncated.text.contains("[00:00] 自分: 発言0") && truncated.text.contains("最初の \(truncated.omittedLines) 発言は省略"))
        check("会話がなければ <conversation> を付けない", !truncated.text.contains("<conversation>"))

        var limited = Options()
        limited.maxHistoryMessages = 2
        let many = (0..<6).map { Message(role: $0 % 2 == 0 ? .user : .assistant, text: "やりとり\($0)") }
        let recent = MeetingChat.prompt(question: "q", material: material, history: many, options: limited)
        check("会話は新しいものだけ渡す", recent.text.contains("やりとり4") && recent.text.contains("やりとり5") && !recent.text.contains("やりとり3"))

        var batch = material
        batch.lines = []
        batch.pending = []
        batch.batchEngineName = "Whisper"
        check("記録中に文字起こしがないエンジンを知らせる", MeetingChat.prompt(question: "q", material: batch, history: []).text
              .contains("記録を止めたあとに Whisper で行う"))

        let linked = linkingTimes(in: "決定 [12:34]、補足 ［1:02:03］、リンク済み [05:00](https://example.com)")
        check("時刻をリンクにする", linked.contains("[12:34](hanasu-time://754)") && linked.contains("[1:02:03](hanasu-time://3723)"))
        check("リンク済みの [ ] はそのまま", linked.contains("[05:00](https://example.com)"))
        check("リンクから秒数を読む", URL(string: "hanasu-time://754").flatMap(seconds(from:)) == 754
              && URL(string: "https://example.com").flatMap(seconds(from:)) == nil)

        check("時刻の発言を探す", lineIndex(at: 95, starts: [0, 30, 60, 90, 120]) == 3
              && lineIndex(at: 5, starts: [10, 20]) == 0 && lineIndex(at: 59.5, starts: [0, 60]) == 1
              && lineIndex(at: 10, starts: []) == nil)

        let note = noteText(from: "## 決まったこと\n- **リリースは 11/20** [12:34]\n- 価格表は佐藤さん\n")
        check("答えをメモの 1 行にする", note == "AI: 決まったこと / リリースは 11/20 [12:34] / 価格表は佐藤さん")
        check("メモの長さを抑える", noteText(from: String(repeating: "あ", count: 1000), limit: 50).count == 51)
        return results
    }
}

// MARK: - 「何を聞かれた？」の確認用

extension MeetingAskedQuestion {
    // 確かめ方: REQ-MTG-047
    /// 使えるかの決まり・会話への入れ方・待たずに聞くこと・やめた／会話を消したときを確かめる（AI は呼ばない）。結果の行を返す
    static func selfTest() async -> [String] {
        var results: [String] = []
        func check(_ name: String, _ ok: Bool) { results.append("\(ok ? "OK" : "NG") \(name)") }

        check("記録中でなければ使えない", unavailableReason(recording: false, batchEngineName: nil) != nil)
        check("Whisper / Gemini では使えない", unavailableReason(recording: true, batchEngineName: "Whisper")?.contains("Whisper") == true)
        check("Mac 標準で記録中なら使える", unavailableReason(recording: true, batchEngineName: nil) == nil)

        let asked = MeetingAskedQuestion()
        let material = MeetingChat.Material(
            title: "定例", startedAt: Date(timeIntervalSince1970: 0), live: true, elapsed: 700,
            lines: [MeetingChat.Line(time: 650, speaker: Meeting.promptLabel(for: "others"), text: "どう思いますか？")])

        // ウインドウのチャットで答えを待っている質問の前に入る
        let model = MeetingChatModel(meetingID: "self-test")
        model.setMessagesForPreview([MeetingChat.Message(role: .user, text: "要約して")])
        var sentPrompt = ""
        asked.reply = { prompt in
            sentPrompt = prompt.text
            try await Task.sleep(for: .milliseconds(30))
            return "聞かれたこと: 意見 [10:50]"
        }
        asked.start(material: material, meetingID: "self-test", origin: .chat, notice: nil, model: model)
        check("押してすぐは作っている途中", asked.isRunning(for: "self-test"))
        try? await Task.sleep(for: .milliseconds(200))
        check("答えが出る", asked.request?.phase == .answered("聞かれたこと: 意見 [10:50]"))
        check("会話を渡さない", !sentPrompt.contains("<conversation>")
              && sentPrompt.contains(PromptText.neutralizeDelimiters(Prompts.text("chat.quick.asked"))))
        let texts = model.messages.map { $0.label ?? $0.text }
        check("待っている質問の前に、組で入る", texts == ["何を聞かれた？", "聞かれたこと: 意見 [10:50]", "要約して"])
        check("会話の中の文面は AI に渡す文", model.messages.first?.text == Prompts.text("chat.quick.asked"))

        // 会話を消したら入れない
        let cleared = MeetingChatModel(meetingID: "self-test-2")
        asked.start(material: material, meetingID: "self-test-2", origin: .chat, notice: nil, model: cleared)
        cleared.clear()
        try? await Task.sleep(for: .milliseconds(200))
        check("押したあとに会話を消したら入れない", cleared.messages.isEmpty)

        // やめたら入れない
        let cancelled = MeetingChatModel(meetingID: "self-test-3")
        asked.start(material: material, meetingID: "self-test-3", origin: .panel, notice: nil, model: cancelled)
        asked.cancel()
        try? await Task.sleep(for: .milliseconds(200))
        check("やめたら入れない", cancelled.messages.isEmpty && asked.request?.phase != .running)
        MeetingAskedQuestionPanel.shared.close()

        // 失敗したら入れない
        let failed = MeetingChatModel(meetingID: "self-test-4")
        asked.reply = { _ in throw NSError(domain: "test", code: 1) }
        asked.start(material: material, meetingID: "self-test-4", origin: .chat, notice: nil, model: failed)
        try? await Task.sleep(for: .milliseconds(100))
        check("失敗したら入れず、チャットに理由を出す", failed.messages.isEmpty && asked.failure(for: "self-test-4") != nil)
        return results
    }
}
