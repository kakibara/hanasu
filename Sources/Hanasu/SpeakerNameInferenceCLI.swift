import Foundation

// 話者の名前の推測の確認用の CLI モード:
//   Hanasu --test-speaker-names
//     議事録の応答の <speaker_names> の読み取り・名前の検査・名前のない話者への当てはめ・議事録とアクションアイテムの
//     ラベルの置き換え・meeting.json の inferredSpeakers を、決めた例で確かめる（AI は呼ばない）。失敗があれば終了コード 1。
//   実際の AI で確かめるときは --minutes-from-transcript（MinutesCLI.swift）。推測した名前も表示する。
// 確かめ方: REQ-MTG-027
enum SpeakerNameInferenceCLI {
    static func runIfRequested(_ args: [String] = CommandLine.arguments) {
        guard args.contains("--test-speaker-names") else { return }
        exit(selfTest() ? 0 : 1)
    }

    static func selfTest() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
            print("\(ok ? "OK  " : "NG  ") \(name)\(ok ? "" : " — \(detail())")")
            if !ok { failures += 1 }
        }

        // 1. 応答の読み取り（<speaker_names> は <action_items> のあとに来る）
        let response = """
        ## 概要
        話者1と話者10が予算を話した。相手側の確認を待つ。
        ## アクションアイテム
        {{ACTION_ITEMS}}
        ## 話者についてのメモ
        話者1: 田中さんと呼ばれている

        <action_items>
        [{"owner": "話者1", "task": "見積もりを送る", "due": null, "due_note": "来週中"},
         {"owner": "相手", "task": "社内で確認する", "due": null, "due_note": null},
         {"owner": "話者10さん", "task": "資料を直す", "due": null, "due_note": null}]
        </action_items>

        ```json
        <speaker_names>
        {"話者1": "田中さん", "話者2": "山田", "話者10": " 高橋 ", "自分": "榊原", "相手": "佐藤様", "話者9": "伊藤", "同席者1": "話者1"}
        </speaker_names>
        ```
        """
        var result = MinutesPrompt.parse(response, title: "定例")
        check("読み取り: 名前が 7 つ", result.speakerNames.count == 7, "\(result.speakerNames)")
        check("読み取り: 本文に <speaker_names> が残らない", !result.markdown.contains("speaker_names") && !result.markdown.contains("```"), result.markdown)
        check("読み取り: アクションアイテムは 3 件", result.actionItems.count == 3, "\(result.actionItems.count)")
        let (body, none) = SpeakerNameInference.extract(from: "## 概要\nなし")
        check("読み取り: <speaker_names> がなければ空", none.isEmpty && body == "## 概要\nなし")
        check("読み取り: 壊れた JSON は空", SpeakerNameInference.extract(from: "<speaker_names>{話者1: 田中</speaker_names>").names.isEmpty)

        // 2. 名前の検査
        let cleanCases: [(String, String?)] = [
            ("田中さん", "田中"), (" 佐藤様 ", "佐藤"), ("鈴木くん", "鈴木"), ("Alice", "Alice"), ("山本先生", "山本先生"),
            ("話者1", nil), ("同席者2", nil), ("相手", nil), ("自分", nil), ("不明", nil), ("", nil), ("  ", nil),
            ("田中\n佐藤", nil), (String(repeating: "あ", count: 21), nil), (String(repeating: "あ", count: 20), String(repeating: "あ", count: 20)),
        ]
        for (raw, expected) in cleanCases {
            let actual = SpeakerNameInference.cleanName(raw)
            check("名前の検査: \(raw.debugDescription) → \(expected ?? "nil")", actual == expected, "\(actual ?? "nil")")
        }

        // 3. 当てはめ（名前のない話者だけ。「自分」と、名前の付いた話者は変えない）
        var meeting = Meeting(id: "t", title: "定例", startedAt: Date(timeIntervalSince1970: 1_793_000_000))
        meeting.utterances = ["me", "spk1", "spk2", "spk10", "others"].enumerated().map {
            Utterance(speaker: $0.element, start: Double($0.offset * 10), end: Double($0.offset * 10 + 5), text: "発言\($0.offset)")
        }
        meeting.speakerNames = ["spk2": "鈴木"]
        let applied = SpeakerNameInference.apply(result.speakerNames, to: &meeting, minutes: &result)
        check("当てはめ: spk1 = 田中", meeting.speakerNames["spk1"] == "田中", "\(meeting.speakerNames)")
        check("当てはめ: spk10 = 高橋（「話者10」と「話者1」を取り違えない）", meeting.speakerNames["spk10"] == "高橋", "\(meeting.speakerNames)")
        check("当てはめ: others = 佐藤", meeting.speakerNames["others"] == "佐藤", "\(meeting.speakerNames)")
        check("当てはめ: ユーザーが付けた spk2 = 鈴木 は上書きしない", meeting.speakerNames["spk2"] == "鈴木")
        check("当てはめ: 自分（me）には付けない", meeting.speakerNames["me"] == nil)
        check("当てはめ: 付けたのは 3 人", applied.count == 3, "\(applied)")
        check("当てはめ: 推測の印", Set(meeting.inferredSpeakers ?? []) == ["spk1", "spk10", "others"], "\(meeting.inferredSpeakers ?? [])")
        check("当てはめ: 表示名", meeting.displayName(for: "spk1") == "田中" && meeting.isInferredName("spk1") && !meeting.isInferredName("spk2"))

        // 4. 議事録とアクションアイテムの置き換え
        check("置き換え: 本文の「話者1」「話者10」", result.markdown.contains("田中と高橋が予算を話した"), result.markdown)
        check("置き換え: 本文の「相手」（ふつうの言葉）は変えない", result.markdown.contains("相手側の確認"), result.markdown)
        check("置き換え: 話者についてのメモ", result.markdown.contains("田中: 田中さんと呼ばれている"), result.markdown)
        check("置き換え: 担当", result.actionItems.map { $0.owner ?? "-" } == ["田中", "佐藤", "高橋さん"], "\(result.actionItems.map { $0.owner ?? "-" })")
        check("置き換え: 「話者1」は「話者12」の中を変えない",
              SpeakerNameInference.replaceLabel("話者1", with: "田中", in: "話者1・話者12・話者１") == "田中・話者12・話者１")

        // 5. 手で直すと推測の印を外す。同じ名前のままなら外さない
        var renamed = meeting
        renamed.renameSpeaker("spk10", to: "高橋")
        check("手で直す: 同じ名前なら推測のまま", renamed.isInferredName("spk10"))
        renamed.renameSpeaker("spk1", to: "田中太郎")
        check("手で直す: 直すと推測の印を外す", !renamed.isInferredName("spk1") && renamed.speakerNames["spk1"] == "田中太郎")
        renamed.renameSpeaker("others", to: "")
        check("手で直す: 消すと既定の表示に戻り、印も外す", renamed.displayName(for: "others") == "相手" && !(renamed.inferredSpeakers ?? []).contains("others"))

        // 6. 2 回目（作り直し）: 名前の付いた話者はもう対象にしない
        var again = MinutesResult(markdown: "田中", actionItems: [], speakerNames: ["話者1": "別の人"])
        var second = meeting
        check("作り直し: 付いた名前は変えない", SpeakerNameInference.apply(again.speakerNames, to: &second, minutes: &again).isEmpty
              && second.speakerNames["spk1"] == "田中")

        // 7. meeting.json
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? encoder.encode(meeting), let json = String(data: data, encoding: .utf8),
           let decoded = try? decoder.decode(Meeting.self, from: data) {
            check("meeting.json: inferredSpeakers を書く", json.contains("\"inferredSpeakers\""), json)
            check("meeting.json: 読み直せる", Set(decoded.inferredSpeakers ?? []) == ["spk1", "spk10", "others"])
        } else {
            check("meeting.json: 書いて読み直せる", false)
        }
        var plain = Meeting(id: "p", title: "p", startedAt: Date(timeIntervalSince1970: 1_793_000_000))
        plain.speakerNames = ["spk1": "田中"]
        if let data = try? encoder.encode(plain), let json = String(data: data, encoding: .utf8) {
            check("meeting.json: 推測がなければキーを書かない（前の版と同じ形）", !json.contains("inferredSpeakers"), json)
        }
        let legacy = #"{"id":"x","title":"t","startedAt":"2026-11-02T05:30:00Z","duration":60,"status":"done","speakerNames":{"spk1":"田中"},"utterances":[]}"#
        let old = try? decoder.decode(Meeting.self, from: Data(legacy.utf8))
        check("meeting.json: 前の版のファイルを読める", old != nil && old?.inferredSpeakers == nil && old?.isInferredName("spk1") == false)

        // 8. 指示の文面（Windows 版と同じ）
        check("指示: 議事録の指示に <speaker_names> がある",
              MinutesPrompt.systemInstruction(template: .auto, customPrompt: nil).hasSuffix(MinutesPrompt.speakerNamesInstruction))

        print(failures == 0 ? "\nすべて合格" : "\n\(failures) 件の失敗")
        return failures == 0
    }
}
