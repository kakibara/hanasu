import Foundation

// 確かめ方: REQ-COM-061
/// AI に送るプロンプトを、決まった見本の入力で組み立てて全部表示する（訳の確かめ用。AI は呼ばない）。
///   Hanasu --show-prompts [--prompt-language <言語>]   言語を省くと設定の文字起こしの言語
enum PromptsCLI {
    static func run() {
        var request = GeminiClient.Request(
            transcript: "えーと、明日の会議なんですけど、資料はジェミニで作ったやつを使います。",
            model: "gemini-3.5-flash-lite",
            appName: "Slack",
            dictionary: ["Hanasu", "Gemini"],
            extraInstructions: "語尾は「です」にする",
            dictionaryRules: [UserDictionary.Rule(sources: ["ジェミニ", "ジェミナイ"], target: "Gemini")],
            appStyle: AppStyle(bundleID: "com.tinyspeck.slackmacgap", name: "Slack", preset: .chat, rules: "絵文字は使わない"),
            screenContext: ScreenContext(
                appName: "Slack", windowTitle: "#general", textBefore: "明日の会議の件です。",
                // 要件: REQ-DIC-041
                ocr: ScreenOCR(terms: ["J3", "Gemini", "資料"], lines: ["J3 の資料（第 2 版）"])))
        func section(_ title: String, _ body: String) {
            print("===== \(title)")
            print(body)
        }
        func pair(_ title: String, _ prompt: (system: String, user: String)) {
            section("\(title) / system", prompt.system)
            section("\(title) / user", prompt.user)
        }

        // 音声入力の整形・翻訳
        for language in GeminiClient.RefineOutputLanguage.allCases {
            request.outputLanguage = language
            pair("refine \(language.rawValue)", GeminiClient.refinePrompt(request))
        }
        request.outputLanguage = .asSpoken
        // 翻訳は、専用の指示がある English・日本語と、共通の指示（translate.other.system）を使う言語の例として韓国語を出す
        let shownTranslations: [TranslationLanguage] = [.english, .japanese, TranslationLanguage(.ko)]
        for language in shownTranslations {
            pair("translate \(language.rawValue)", GeminiClient.translationPrompt(request, to: language))
        }
        var plain = request
        plain.appName = nil
        plain.appStyle = nil
        plain.screenContext = nil
        plain.extraInstructions = ""
        pair("refine plain", GeminiClient.refinePrompt(plain))
        for language in shownTranslations {
            pair("translate plain \(language.rawValue)", GeminiClient.translationPrompt(plain, to: language))
        }

        // アプリ別の文体
        for preset in AppStylePreset.allCases {
            for rules in ["", "絵文字は使わない"] {
                let style = AppStyle(bundleID: "x", name: "X", preset: preset, rules: rules)
                for translation in [nil] + shownTranslations.map(Optional.some) {
                    for common in [false, true] {
                        let text = style.promptSection(appName: common ? "X" : nil, translation: translation, hasCommonRules: common)
                        section("style \(preset.rawValue) rules=\(!rules.isEmpty) translation=\(translation?.rawValue ?? "nil") common=\(common)",
                                text ?? "(nil)")
                    }
                }
            }
        }

        // 選択を声で編集
        section("edit / system", GeminiClient.editInstruction)
        section("edit / user", GeminiClient.editPrompt(
            for: GeminiClient.EditRequest(selection: "明日は休みます。", instruction: "もっと丁寧に", model: "m", appName: "Mail", dictionary: ["Hanasu"]),
            nonce: "0123456789ab"))

        // 文字起こし（Gemini）
        section("transcribe dictation", GeminiTranscriber.dictationInstruction(localeIdentifier: "ja-JP"))
        section("transcribe meeting", GeminiTranscriber.meetingInstruction(localeIdentifier: "ja-JP"))

        // 会議
        var meeting = Meeting(id: "x", title: "定例", startedAt: Date(timeIntervalSince1970: 1_793_000_000))
        meeting.duration = 1_800
        meeting.utterances = [
            Utterance(speaker: "me", start: 0, end: 3, text: "では始めます。"),
            Utterance(speaker: "spk1", start: 4, end: 8, text: "田中です。よろしくお願いします。"),
            Utterance(speaker: "room1", start: 9, end: 12, text: "資料は来週の金曜までに送ります。"),
            Utterance(speaker: "others", start: 13, end: 15, text: "はい。"),
        ]
        for template in MinutesTemplate.allCases {
            section("minutes \(template.rawValue)", MinutesPrompt.systemInstruction(
                template: template, customPrompt: template == .custom ? MinutesTemplateStore.defaultCustomPrompt : nil))
        }
        section("minutes user", MinutesPrompt.userText(for: meeting))
        meeting.notes = [MeetingNote(kind: .note, time: 5, text: "予算の話"), MeetingNote(kind: .highlight, time: 10, text: "")]
        section("minutes user with notes", MinutesPrompt.userText(for: meeting))
        section("minutes notes instruction", MeetingProcessor.notesInstruction)
        section("minutes parse", MinutesPrompt.parse("""
            ## 概要
            定例の会議。

            ## アクションアイテム
            {{ACTION_ITEMS}}
            <action_items>
            [{"owner": "話者1", "task": "資料を送る", "due": null, "due_note": "来週の金曜"}]
            </action_items>
            <speaker_names>
            {"話者1": "田中"}
            </speaker_names>
            """, title: "定例").markdown)
        section("minutes parse empty", MinutesPrompt.parse("## アクションアイテム\n{{ACTION_ITEMS}}\n<action_items>\n[]\n</action_items>", title: "定例").markdown)
        section("minutes parse unreadable", MinutesPrompt.parse("## アクションアイテム\n{{ACTION_ITEMS}}", title: "定例").markdown)
        section("long input part", LongInputFitter.partInstruction(index: 2, total: 5))
        section("long input notes", LongInputFitter.summarizedNote + "|" + LongInputFitter.omittedNote)
        section("ask", MeetingAsk.instruction)
        section("dictionary suggest", DictionarySuggester.instruction)
        section("dictionary suggest user", DictionarySuggester.userPrompt(material: "（材料）", existing: UserDictionary(text: "")))
        section("dictionary corpus", DictionarySuggester.Corpus(meetings: [meeting]).promptText())

        // 会議の AI チャット
        section("chat / system", MeetingChat.instruction)
        let chatMaterial = MeetingChat.material(for: meeting)
        let now = Date(timeIntervalSince1970: 1_793_001_000)
        let history = [MeetingChat.Message(role: .user, text: "決まったことは？"), MeetingChat.Message(role: .assistant, text: String(repeating: "あ", count: 20))]
        section("chat / user done", MeetingChat.prompt(question: "誰が資料を送る？", material: chatMaterial, history: history,
                                                       options: .init(maxHistoryMessageCharacters: 10), now: now).text)
        var live = chatMaterial
        live.live = true
        live.elapsed = 75
        live.pending = [MeetingChat.Line(time: 75, speaker: Meeting.promptLabel(for: "others"), text: "えーと")]
        section("chat / user live", MeetingChat.prompt(question: "今の話は？", material: live, history: [],
                                                       options: .init(maxTranscriptCharacters: 40), now: now).text)
        live.lines = []
        live.batchEngineName = "Whisper"
        section("chat / user live batch", MeetingChat.prompt(question: "今の話は？", material: live, history: [], now: now).text)
        live.batchEngineName = nil
        section("chat / user empty", MeetingChat.prompt(question: "今の話は？", material: live, history: [], now: now).text)
        section("chat / quick", MeetingChat.quickPrompts.map { "\($0.id): \($0.question)" }.joined(separator: "\n"))
    }
}
