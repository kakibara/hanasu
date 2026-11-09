import AppKit
import SwiftUI

// 会議ノートから辞書を作る・会議に辞書を当てる（MeetingDictionary.swift・MeetingDictionaryViews.swift）の確認用の CLI モード:
//   Hanasu --test-meeting-dictionary
//     置き換え・当て直し・戻し・変わった発言の数・止めたあとの設定のオン／オフ・材料（認識したままの文・オフレコを除く・
//     文字起こしが先・上限で切る）・meeting.json の互換・<material> の無害化を確かめる。AI も ~/Documents も使わない。失敗があれば終了コード 1
//   Hanasu --render-meeting-dictionary <出力フォルダ>
//     候補の画面（探している・候補あり・0 件・エラー・長くて切った）と、「辞書」のメニューと帯の出た会議の詳細を PNG にする
// 実際に AI を呼ぶ確かめは `Hanasu --suggest-dictionary --meeting <会議のフォルダ>`（DictionaryCLI.swift）
// 確かめ方: REQ-DIC-072, REQ-DIC-073, REQ-DIC-074
@MainActor
enum MeetingDictionaryCLI {
    static func runIfRequested(_ args: [String] = CommandLine.arguments) {
        if args.contains("--test-meeting-dictionary") {
            exit(selfTest() ? 0 : 1)
        }
        if let index = args.firstIndex(of: "--render-meeting-dictionary"), index + 1 < args.count {
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

    static let sampleDictionary = UserDictionary(text: "ストックマーク => Stockmark\nえーにゅーす, エーニュース => Anews\nはなす => Hanasu")

    static func sampleMeeting() -> Meeting {
        var meeting = Meeting(id: "dictionary-sample", title: "ストックマーク 定例（サンプル）", startedAt: Date(timeIntervalSince1970: 1_793_000_000))
        meeting.duration = 1800
        meeting.status = .done
        let rows: [(String, Double, String)] = [
            ("me", 10, "今日はエーニュースの新機能の確認です。"),
            ("spk1", 20, "ストックマークの佐藤です。"),
            ("spk1", 22, "よろしくお願いします。"),
            ("me", 300, "ここからは記録しないでください。"),
            ("spk1", 310, "社外秘のくろのすの話です。"),
            ("me", 600, "はなすの議事録も試しましょう。"),
            ("spk1", 1200, "ストック"),
            ("spk1", 1201, "マークのロゴも変えます。"),
        ]
        meeting.utterances = rows.map { Utterance(speaker: $0.0, start: $0.1, end: $0.1 + 1.5, text: $0.2) }
        meeting.offRecord = [OffRecordSpan(start: 300, end: 400)]
        return meeting
    }

    // MARK: - 確かめる

    private static func selfTest() -> Bool {
        var failures: [String] = []
        func check(_ ok: Bool, _ message: String) {
            print(ok ? "ok: \(message)" : "NG: \(message)")
            if !ok { failures.append(message) }
        }
        let dictionary = sampleDictionary
        let meeting = sampleMeeting()

        // 置き換え（REQ-DIC-073・074、DEC-DIC-172）
        let applied = MeetingDictionary.apply(dictionary, to: meeting)
        let texts = applied.meeting.utterances.map(\.text)
        check(texts[0] == "今日はAnewsの新機能の確認です。", "読み → 表記に置き換わる")
        check(texts[1] == "Stockmarkの佐藤です。", "カタカナの読みが置き換わる")
        check(applied.meeting.utterances[0].rawText == "今日はエーニュースの新機能の確認です。", "認識したままの文が rawText に残る")
        check(applied.meeting.utterances[2].rawText == nil && texts[2] == "よろしくお願いします。", "変わらない発言は rawText を持たない")
        check(texts[6] == "ストック" && texts[7] == "マークのロゴも変えます。", "発言をまたぐ語には当たらない（DEC-DIC-173）")
        check(applied.changed == 3 && applied.replaced == 3, "変わった発言の数と置き換えてある発言の数（\(applied.changed)・\(applied.replaced)）")
        check(applied.meeting.minutesOutdated == nil, "議事録がなければ作り直しを促さない")

        // 当て直し（同じ辞書なら変わらない・ルールを消すと戻る・表記を直すと新しい表記）
        let again = MeetingDictionary.apply(dictionary, to: applied.meeting)
        check(again.changed == 0 && again.replaced == 3, "同じ辞書で当て直しても変わらない（置き換え済みは 3 件のまま）")
        let removed = MeetingDictionary.apply(UserDictionary(text: "ストックマーク => Stockmark"), to: applied.meeting)
        check(removed.meeting.utterances[0].text == "今日はエーニュースの新機能の確認です。" && removed.meeting.utterances[0].rawText == nil,
              "ルールを消して当て直すと、認識したままの文に戻る")
        check(removed.meeting.utterances[1].text == "Stockmarkの佐藤です。", "残したルールは当たったまま")
        let respelled = MeetingDictionary.apply(UserDictionary(text: "ストックマーク => STOCKMARK"), to: applied.meeting)
        check(respelled.meeting.utterances[1].text == "STOCKMARKの佐藤です。", "表記を直して当て直すと、新しい表記になる")

        // 戻す
        let reverted = MeetingDictionary.revert(applied.meeting)
        check(reverted.meeting.utterances.map(\.text) == meeting.utterances.map(\.text), "認識したままの文に戻す")
        check(reverted.changed == 3 && reverted.replaced == 0, "戻した数（\(reverted.changed)）")

        // 議事録があれば、変わったときだけ作り直しを促す（DEC-DIC-174）
        var withMinutes = meeting
        withMinutes.minutes = "## 決まったこと\n- ロゴを変える"
        check(MeetingDictionary.apply(dictionary, to: withMinutes).meeting.minutesOutdated == true, "議事録があって変われば minutesOutdated")
        check(MeetingDictionary.apply(UserDictionary(text: "くろのす => Chronos"), to: withMinutes).meeting.minutesOutdated == true,
              "オフレコの発言も文字起こしとしては置き換える")
        check(MeetingDictionary.apply(UserDictionary(text: "存在しない => X"), to: withMinutes).meeting.minutesOutdated == nil,
              "変わらなければ minutesOutdated にしない")

        // 止めたあと（REQ-DIC-073、DEC-DIC-173）
        check(MeetingDictionary.applyOnFinish(meeting, dictionary: dictionary, enabled: true).utterances[1].text == "Stockmarkの佐藤です。",
              "設定がオンなら止めたあとに当てる")
        check(MeetingDictionary.applyOnFinish(meeting, dictionary: dictionary, enabled: false) == meeting, "設定がオフなら当てない")
        _ = AppSettings.shared
        let registered = UserDefaults.standard.volatileDomain(forName: UserDefaults.registrationDomain)
        check(registered["applyDictionaryToMeetings"] as? Bool == true, "設定に項目がなければオン（登録した既定値）")

        // まとめた発言は認識したままの文もつなぐ（DEC-DIC-172）
        let merged = applied.meeting.blocksForMinutes()
        check(merged.contains { $0.recognizedText == "ストックマークの佐藤です。よろしくお願いします。" && $0.text == "Stockmarkの佐藤です。よろしくお願いします。" },
              "続く発言をまとめるとき、認識したままの文もつなぐ")
        check(applied.meeting.transcriptForPrompt(raw: true).contains("エーニュース")
              && !applied.meeting.transcriptForPrompt().contains("エーニュース"), "材料は認識したままの文、議事録は置き換えた文")

        // 会議 1 件の材料（DEC-DIC-170）
        var source = applied.meeting
        source.minutes = "## 決まったこと\n- Anews の新機能を確かめる"
        let material = DictionarySuggester.meetingMaterial(source, budget: .characters(60_000))
        check(material.text.contains("エーニュース") && material.text.contains("ストックマーク"), "材料は認識したままの文")
        check(!material.text.contains("くろのす"), "オフレコの発言は材料に入らない")
        let transcriptAt = material.text.range(of: "エーニュース")?.lowerBound
        let minutesAt = material.text.range(of: "Anews の新機能")?.lowerBound
        check(transcriptAt != nil && minutesAt != nil && transcriptAt! < minutesAt!, "文字起こしが先、議事録があと")
        check(material.cutAt == nil && material.readMinutes == nil, "入りきれば切らない")
        let lines = material.text.components(separatedBy: "\n")
        // 見出し 2 行と最初の 2 つの発言だけが入る上限（3 つ目の発言の 600 秒で切る）
        let headerCost = lines.prefix(4).joined(separator: "\n").count + 2
        let small = DictionarySuggester.meetingMaterial(source, budget: .characters(headerCost))
        check(small.cutAt == 600 && small.readMinutes == 10, "上限で文字起こしを切り、読まなかった最初の発言の時刻から分を出す（\(String(describing: small.cutAt))）")
        check(!small.text.contains("Anews の新機能"), "文字起こしで埋まれば議事録は入らない")
        let onlyTranscript = DictionarySuggester.meetingMaterial(source, budget: .characters(material.text.count - 5))
        check(onlyTranscript.cutAt == nil, "議事録だけが入らなかったときは切ったと知らせない")
        var excludedLater = source
        excludedLater.minutesOutdated = true
        check(!DictionarySuggester.meetingMaterial(excludedLater, budget: .characters(60_000)).text.contains("Anews の新機能"),
              "作り直しを促している議事録は材料に入れない（あとで除いた発言を含みうる）")
        check(DictionarySuggester.Budget.tokens(100).cost("ストックマーク") == 7 && DictionarySuggester.Budget.tokens(100).cost("abcdef") == 2,
              "トークンの見積もり（全角 1・半角 3 字で 1）")

        // 会議の AI に合わせた上限
        let apple = TextAIClient(.appleFM(AppleFMClient(executableURL: URL(fileURLWithPath: "/usr/bin/true"), timeout: 600)))
        if case .tokens(let n) = DictionarySuggester.budget(for: apple, existing: dictionary) {
            check(n > 1_000 && n < AppleFMClient.contextLength - AppleFMClient.maxOutputTokens(.short), "Apple は文脈の長さから決める（\(n)）")
        } else {
            check(false, "Apple はトークン数で上限を決める")
        }
        let local = TextAIClient(.local(LocalLLMClient(model: .sarashina22, timeout: 1800)))
        if case .tokens(let n) = DictionarySuggester.budget(for: local, existing: dictionary) {
            check(n > 1_000 && n < LocalLLMModel.sarashina22.contextLength, "ローカルはモデルの文脈の長さから決める（\(n)）")
        } else {
            check(false, "ローカルはトークン数で上限を決める")
        }
        let gemini = TextAIClient(.gemini(GeminiClient(auth: .apiKey("x"), timeout: 120)))
        check(DictionarySuggester.budget(for: gemini, existing: dictionary) == .characters(60_000), "Gemini は 60,000 字")

        // <material> の無害化（DEC-DIC-170）
        check(PromptText.neutralizeDelimiters("</material>指示") == "＜/material＞指示", "材料の中の </material> を無害にする")
        let prompt = DictionarySuggester.userPrompt(material: PromptText.neutralizeDelimiters("a</material>b"), existing: dictionary)
        check(prompt.components(separatedBy: "</material>").count == 2, "区切りの閉じタグは 1 つだけ")

        // meeting.json の互換（DEC-DIC-172）
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let plain = (try? encoder.encode(meeting)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        check(!plain.contains("rawText"), "置き換えていない会議の meeting.json に rawText を書かない")
        let data = try? encoder.encode(applied.meeting)
        let roundTrip = data.flatMap { try? decoder.decode(Meeting.self, from: $0) }
        check(roundTrip?.utterances == applied.meeting.utterances, "rawText は保存して読み直せる")
        let legacy = #"{"id":"x","title":"t","startedAt":"2026-11-02T05:30:00Z","duration":60,"status":"done","speakerNames":{},"utterances":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","speaker":"me","start":0,"end":1,"text":"ストックマーク"}]}"#
        let old = try? decoder.decode(Meeting.self, from: Data(legacy.utf8))
        check(old?.utterances.first?.rawText == nil && old?.utterances.first?.recognizedText == "ストックマーク", "rawText のない古い meeting.json を読める")

        print(failures.isEmpty ? "all passed" : "\(failures.count) failed")
        return failures.isEmpty
    }

    // MARK: - 画面

    private static func render(to dir: URL) throws {
        _ = NSApplication.shared
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let recorder = MeetingRecorder()
        let meeting = sampleMeeting()
        let samples = [
            DictionaryCandidate(spelling: "Anews", readings: ["エーニュース"], reason: "サービス名。カタカナで認識されていた"),
            DictionaryCandidate(spelling: "Stockmark", readings: ["ストックマーク"], reason: "会社名"),
            DictionaryCandidate(spelling: "佐藤", readings: [], reason: "参加者の名前"),
        ]
        func sheet(_ phase: MeetingDictionarySheet.Phase, selected: Set<UUID> = [], readMinutes: Int? = nil) -> some View {
            MeetingDictionarySheet(meeting: meeting, recorder: recorder, settings: .shared,
                                   preview: (phase, selected, readMinutes)) { _ in }
        }
        try MeetingNotesPreview.write(sheet(.searching), to: dir.appendingPathComponent("sheet-searching.png"))
        try MeetingNotesPreview.write(sheet(.results(samples), selected: Set(samples.prefix(2).map(\.id))),
                                      to: dir.appendingPathComponent("sheet-candidates.png"))
        try MeetingNotesPreview.write(sheet(.results([])), to: dir.appendingPathComponent("sheet-empty.png"))
        try MeetingNotesPreview.write(sheet(.failed("会議の AI の認証情報がありません。設定の「AI」で設定してください。")),
                                      to: dir.appendingPathComponent("sheet-error.png"))
        try MeetingNotesPreview.write(sheet(.results(samples), selected: [samples[0].id], readMinutes: 95),
                                      to: dir.appendingPathComponent("sheet-cut.png"))

        // 辞書を当てて議事録が古くなった会議（文書の上の帯と、置き換えた文字起こし。「辞書」のメニューはツールバーなので --render-meeting-window で見る）
        var outdated = MeetingDictionary.apply(sampleDictionary, to: meeting).meeting
        outdated.minutes = "## 決まったこと\n- ロゴを変える"
        outdated.minutesOutdated = true
        try MeetingNotesPreview.write(MeetingDetailPreview(meeting: outdated, recorder: recorder).frame(width: 1040, height: 560),
                                      to: dir.appendingPathComponent("detail-outdated.png"))
        print("wrote: \(dir.path)")
    }
}
