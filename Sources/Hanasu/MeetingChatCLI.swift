import AppKit
import Foundation
import SwiftUI

// 会議の AI チャットの確認用の CLI モード:
//   Hanasu --test-meeting-chat
//     プロンプトの組み立て（記録中の時点・確定前の発言・メモ・それまでの会話・長さの上限）・答えの時刻のリンク・
//     メモへの変換を、決めた例で確かめる（AI は呼ばない）。失敗があれば終了コード 1。
//   Hanasu --chat-meeting <会議のフォルダ> --ask <質問> [--ask <続けての質問> ...] [--at <mm:ss>] [--show-prompt]
//          [--ai gemini|claude|local|apple] [--model <id>] [--show-target]
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
            let results = MeetingChat.selfTest() + MeetingChatRouteTest.run()
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
                // 要件: REQ-COM-025（AI チャットは「AI チャット・質問」の AI とモデル）
                // 確かめ方: REQ-COM-025
                if TextAIClient.printTargetIfRequested(args: args, settings: settings, for: .chat) { exit(0) }
                let client = try TextAIClient.cli(args: args, settings: settings, for: .chat, timeout: 180)
                let model = TextAIClient.cliModel(args: args, settings: settings, for: .chat)
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

        // 要件: REQ-MTG-048（送り先は、この Mac の設定に左右されないよう決めて描く。設定は描いたあとに戻す）
        let settings = AppSettings.shared
        let savedChat = (settings.chatAIProvider, settings.claudeChatModel, settings.localChatModel)
        defer {
            settings.chatAIProvider = savedChat.0
            settings.claudeChatModel = savedChat.1
            settings.localChatModel = savedChat.2
        }
        settings.chatAIProvider = .claude
        settings.claudeChatModel = ClaudeClient.Model.defaultChat.rawValue
        let ready = AIRoute.Availability(claude: true, gemini: true, downloadedLocalModels: [.gemma4E4B], appleFMReason: nil)

        let chat = MeetingChatStore.shared.model(for: meeting.id)
        chat.setAvailabilityForPreview(ready)
        try MeetingNotesPreview.write(LivePreview(recorder: recorder).frame(width: 1240, height: 620),
                                      to: directory.appendingPathComponent("live-chat-empty.png"))
        chat.setMessagesForPreview(sampleConversation, draft: "価格表の更新はいつまで？")
        try MeetingNotesPreview.write(LivePreview(recorder: recorder).frame(width: 1240, height: 620),
                                      to: directory.appendingPathComponent("live-chat.png"))
        // 既定（Claude Haiku）から Opus に切り替えた会話
        chat.override = TextAIChoice(provider: .claude, model: ClaudeClient.Model.opus.rawValue)
        try MeetingNotesPreview.write(LivePreview(recorder: recorder).frame(width: 1240, height: 620),
                                      to: directory.appendingPathComponent("live-chat-switched.png"))
        chat.override = nil
        // 既定（ローカル Gemma）がまだダウンロードされていない
        settings.chatAIProvider = .local
        settings.localChatModel = .gemma4E4B
        var unavailableMeeting = meeting
        unavailableMeeting.id = "preview-chat-unavailable"
        MeetingChatStore.shared.model(for: unavailableMeeting.id).setAvailabilityForPreview(
            AIRoute.Availability(claude: true, gemini: false, downloadedLocalModels: [], appleFMReason: "macOS 27"))
        recorder.showPreviewForRendering(unavailableMeeting, lines: lines, volatileOthers: "")
        try MeetingNotesPreview.write(LivePreview(recorder: recorder).frame(width: 1240, height: 620),
                                      to: directory.appendingPathComponent("live-chat-unavailable.png"))
        settings.chatAIProvider = .claude
        recorder.showPreviewForRendering(meeting, lines: lines, volatileOthers: "そうですね、基準は利用頻度と")

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
        MeetingChatStore.shared.model(for: done.id).setAvailabilityForPreview(ready)
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
        """, coveredUntil: 745, lineCount: 6, modelLabel: "Claude · Haiku 5.5"),
        MeetingChat.Message(role: .user, text: "3 社の候補は具体的に出ていた？"),
        MeetingChat.Message(role: .assistant, text: """
        具体的な社名は出ていません。「既存のお客さまのうち、利用頻度が高いところから」という方針だけです [11:00]。
        候補を聞くなら「利用頻度の目安（例: 週何回以上）はありますか？」が使えます。
        """, coveredUntil: 752, lineCount: 6, modelLabel: "Claude · Haiku 5.5"),
    ]
}

extension MeetingChat {
    // MARK: - 確認用

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

// 確かめ方: REQ-MTG-048, REQ-MTG-049
/// 送り先の切り替え（既定・切り替え・使えないものの判定・一覧）を確かめる（AI は呼ばない）
@MainActor
enum MeetingChatRouteTest {
    static func run() -> [String] {
        var results: [String] = []
        func check(_ name: String, _ ok: Bool) { results.append("\(ok ? "OK" : "NG") \(name)") }
        let name = "dev.mactypeless.Hanasu.test-meeting-chat.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults, domainName: name)
        settings.chatAIProvider = .claude
        settings.claudeChatModel = "claude-haiku-5-5"
        settings.geminiChatModel = "gemini-custom-x"

        let chat = MeetingChatModel(meetingID: "route-a")
        check("切り替えていなければ、設定の AI チャット・質問に送る",
              chat.effectiveChoice(settings: settings) == TextAIChoice(provider: .claude, model: "claude-haiku-5-5"))
        chat.override = TextAIChoice(provider: .local, model: "qwen3.5-4b")
        check("切り替えたら、その AI とモデルに送る", chat.effectiveChoice(settings: settings) == TextAIChoice(provider: .local, model: "qwen3.5-4b"))
        chat.clear()
        check("「新しい会話」では切り替えを戻さない", chat.override != nil)
        check("別の会議は既定で始まる", MeetingChatModel(meetingID: "route-b").effectiveChoice(settings: settings).provider == .claude)
        let ask = MeetingAskModel()
        check("会議に質問も、切り替えていなければ設定の AI チャット・質問", ask.effectiveChoice(settings: settings) == settings.aiChoice(for: .chat))

        let none = AIRoute.Availability(claude: false, gemini: false, downloadedLocalModels: [.gemma4E4B], appleFMReason: "macOS 27 以降")
        check("Claude のキーがなければ選べない", none.unavailableReason(TextAIChoice(provider: .claude, model: "claude-opus-5-5")) != nil)
        check("Gemini の認証がなければ選べない", none.unavailableReason(TextAIChoice(provider: .gemini, model: "gemini-3.8-flash")) != nil)
        check("ダウンロードしたローカルのモデルは選べる", none.unavailableReason(TextAIChoice(provider: .local, model: "gemma-4-e4b")) == nil)
        check("ダウンロードしていないローカルのモデルは選べない", none.unavailableReason(TextAIChoice(provider: .local, model: "qwen3.5-4b")) != nil)
        check("Apple の fm が使えなければ選べない", none.unavailableReason(TextAIChoice(provider: .appleFM, model: AppleFMClient.modelName)) != nil)
        check("選べない項目は理由を文字に入れる",
              AIRoute.itemTitle(TextAIChoice(provider: .claude, model: "claude-opus-5-5"), reason: "API キーが未設定").contains("API キーが未設定"))

        let sections = AIRoute.sections(settings: settings)
        check("一覧は ローカル・Apple・Gemini・Claude の順", sections.map(\.provider) == [.local, .appleFM, .gemini, .claude])
        check("ローカルは 4 つ、Claude は 3 つ", sections[0].choices.count == LocalLLMModel.allCases.count && sections[3].choices.count == 3)
        check("Gemini は候補と、設定にある一覧にないモデル",
              sections[2].choices.map(\.model) == AppSettings.suggestedModels + ["gemini-custom-x"])
        return results
    }
}
