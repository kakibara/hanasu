import AppKit
import SwiftUI

// 会議の横断検索・質問の確認用の CLI モード:
//   Hanasu --search-meetings <語> [--meetings-dir <フォルダ>]
//   Hanasu --ask-meetings <質問> [--meetings-dir <フォルダ>] [--limit <会議数>] [--model <id>] [--show-context]
//   Hanasu --write-sample-meetings <フォルダ>       架空の会議データを書き出す（確認・テスト用）
//   Hanasu --render-meeting-search <出力.png> [--ask]  架空のデータで検索（--ask なら質問）の画面を画像にする
// 会議のフォルダの既定は ~/Documents/Hanasu/Meetings。認証は --refine-text と同じ順に探す。
enum MeetingSearchCLI {
    @MainActor
    static func runIfRequested(_ args: [String]) {
        func value(after flag: String) -> String? {
            args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        }

        if let dir = value(after: "--write-sample-meetings") {
            do {
                try writeSamples(to: URL(fileURLWithPath: dir))
                print("架空の会議を \(sampleMeetings().count) 件書き出しました: \(dir)")
                exit(0)
            } catch {
                fail(error)
            }
        }

        if let output = value(after: "--render-meeting-search") {
            render(to: URL(fileURLWithPath: output), ask: args.contains("--ask"))
            exit(0)
        }

        let query = value(after: "--search-meetings")
        let question = value(after: "--ask-meetings")
        guard query != nil || question != nil else { return }
        let meetings = loadMeetings(in: value(after: "--meetings-dir").map { URL(fileURLWithPath: $0) } ?? MeetingStore.baseDirectory)

        Task { @MainActor in
            do {
                let index = MeetingSearchIndex()
                let started = Date()
                await index.update(meetings)
                print(String(format: "[索引] 会議 %d 件 %.2fs", meetings.count, Date().timeIntervalSince(started)))

                if let query {
                    let searchStarted = Date()
                    let results = await index.search(query)
                    print(String(format: "[検索] %d 件の会議・%d か所 %.3fs", results.count,
                                 results.reduce(0) { $0 + $1.totalHits }, Date().timeIntervalSince(searchStarted)))
                    for result in results {
                        print("\n## \(Meeting.dateFormatter.string(from: result.startedAt)) \(result.title)（\(result.totalHits) 件）")
                        for hit in result.hits {
                            let place: String
                            switch hit.location {
                            case .title: place = "タイトル"
                            case .minutes(let line): place = "議事録 \(line + 1) 行目"
                            case .transcript(_, let start, let speaker): place = "\(Meeting.clock(start)) \(speaker)"
                            }
                            print("- [\(place)] \(hit.snippet)")
                        }
                    }
                }

                if let question {
                    let settings = AppSettings.shared
                    var options = MeetingAsk.Options()
                    if let limit = value(after: "--limit").flatMap(Int.init) { options.maxMeetings = limit }
                    let model = value(after: "--model") ?? settings.meetingMinutesModel
                    let context = await MeetingAsk.gatherContext(question: question, meetings: meetings, index: index, options: options)
                    print("[質問] 検索語: \(context.keywords.joined(separator: ", "))"
                          + (context.period.map { "  期間: \($0.start.formatted()) 〜 \($0.end.formatted())" } ?? ""))
                    print("[渡す会議] \(context.sources.count) 件・\(context.prompt.count) 文字")
                    for source in context.sources {
                        print("- \(source.label)\(source.matched ? "" : "（直近）")")
                    }
                    if args.contains("--show-context") { print(context.prompt) }
                    let askStarted = Date()
                    let answer = try await MeetingAsk.ask(question: question, meetings: meetings, index: index,
                                                          client: GeminiClient(auth: try auth(), timeout: 180),
                                                          model: model, options: options)
                    print(String(format: "\n[答え %@ %.1fs] 引用された会議 %d 件", model, Date().timeIntervalSince(askStarted), answer.cited.count))
                    print(answer.text)
                }
                exit(0)
            } catch {
                fail(error)
            }
        }
        RunLoop.main.run()
    }

    private static func fail(_ error: Error) -> Never {
        FileHandle.standardError.write(Data("error: \(error.localizedDescription) (\(error))\n".utf8))
        exit(1)
    }

    @MainActor
    private static func auth() throws -> GeminiClient.Auth {
        let settings = AppSettings.shared
        let env = ProcessInfo.processInfo.environment
        if let path = env["GEMINI_SERVICE_ACCOUNT_JSON"] {
            return .serviceAccount(try ServiceAccountCredentials.load(path: path), location: settings.vertexLocation)
        }
        return try GeminiClient.authFromSettings(settings) ?? .apiKey(env["GEMINI_API_KEY"] ?? "")
    }

    /// `MeetingStore.loadAll()` と同じ読み方で、指定したフォルダから会議を読む
    static func loadMeetings(in base: URL) -> [Meeting] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let dirs = (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? []
        return dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("meeting.json")) else { return nil }
            return try? decoder.decode(Meeting.self, from: data)
        }
        .sorted { $0.startedAt > $1.startedAt }
    }

    // MARK: - 架空のデータ

    private static func writeSamples(to base: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        for meeting in sampleMeetings() {
            let dir = base.appendingPathComponent(meeting.id, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try encoder.encode(meeting).write(to: dir.appendingPathComponent("meeting.json"), options: .atomic)
        }
    }

    /// 確認用の架空の会議（今日を基準に、今週・先週・先月の会議を作る）
    static func sampleMeetings(now: Date = Date()) -> [Meeting] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        let thisMonday = calendar.dateInterval(of: .weekOfYear, for: now)!.start
        func date(daysFromMonday days: Int, hour: Int) -> Date {
            calendar.date(byAdding: .hour, value: hour, to: calendar.date(byAdding: .day, value: days, to: thisMonday)!)!
        }
        func meeting(_ id: String, _ title: String, _ start: Date, _ lines: [(String, String)], minutes: String?,
                     names: [String: String] = [:]) -> Meeting {
            var m = Meeting(id: id, title: title, startedAt: start)
            m.status = .done
            m.speakerNames = names
            var t = 3.0
            m.utterances = lines.map { speaker, text in
                defer { t += Double(text.count) * 0.18 + 2.5 }
                return Utterance(speaker: speaker, start: t, end: t + Double(text.count) * 0.18, text: text)
            }
            m.duration = t + 5
            m.minutes = minutes
            return m
        }

        let weekly = meeting("sample-weekly-last", "週次定例（プロダクト）", date(daysFromMonday: -7 + 1, hour: 10), [
            ("me", "では週次定例を始めます。まず料金プランの件からお願いします。"),
            ("spk1", "新しい料金プランは、スタンダードとチームの2つに絞る案で進めています。"),
            ("spk2", "チームプランの価格は月額 4,800 円にする方向で、営業とも合意が取れました。"),
            ("me", "了解です。リリース日はどうしますか？"),
            ("spk1", "料金プランのリリースは12月1日でいきましょう。告知は2週間前に出します。"),
            ("spk2", "ヘルプページの更新は私が担当します。来週の水曜までに下書きを出します。"),
            ("me", "ありがとうございます。次に、問い合わせ対応のフローについてです。"),
            ("spk1", "問い合わせフォームに カテゴリ の選択肢を追加して、一次回答を自動化したいです。"),
            ("me", "それはいいですね。来週までに選択肢の案を出してもらえますか。"),
        ], minutes: """
        # 週次定例（プロダクト） — 議事録

        ## 概要
        新しい料金プランの内容とリリース日、問い合わせ対応フローの改善について話し合った。

        ## 話し合った内容
        ### 料金プラン
        - プランはスタンダードとチームの 2 つに絞る
        - チームプランは月額 4,800 円（営業と合意済み）

        ## 決定事項
        - 料金プランのリリースは 12 月 1 日。告知は 2 週間前
        - 問い合わせフォームにカテゴリの選択肢を追加する

        ## TODO
        - [ ] ヘルプページの更新の下書き（担当: 山田さん / 期限: 来週水曜）
        - [ ] 問い合わせカテゴリの案を出す（担当: 佐藤さん / 期限: 来週）
        """, names: ["spk1": "佐藤さん", "spk2": "山田さん"])

        let design = meeting("sample-design-this", "デザインレビュー", date(daysFromMonday: 1, hour: 15), [
            ("me", "今日は設定画面のデザインを見ていきます。"),
            ("spk1", "料金プランの比較表を設定画面からも開けるようにしました。"),
            ("me", "比較表の文字が少し小さいので、もう一段大きくしましょう。"),
            ("spk1", "わかりました。ダークモードでのコントラストも確認しておきます。"),
        ], minutes: nil, names: ["spk1": "鈴木さん"])

        let retro = meeting("sample-retro-last-month", "月次ふりかえり", calendar.date(byAdding: .month, value: -1, to: date(daysFromMonday: 0, hour: 17))!, [
            ("me", "先月のふりかえりをします。良かった点からどうぞ。"),
            ("spk1", "問い合わせの返信が平均で半日早くなりました。"),
            ("spk2", "一方で、リリース前のテストが足りず、不具合が2件出ました。"),
            ("me", "次回からはリリース前日にテストの時間を確保しましょう。"),
        ], minutes: """
        # 月次ふりかえり — 議事録

        ## 概要
        問い合わせ対応の改善と、リリース前のテスト不足について振り返った。

        ## 決定事項
        - リリース前日にテストの時間を確保する
        """)
        return [design, weekly, retro]
    }

    // MARK: - 画面の確認

    /// 架空のデータで、検索結果と飛び先（または質問の画面）を描く
    @MainActor
    private static func render(to url: URL, ask: Bool) {
        _ = NSApplication.shared
        let meetings = sampleMeetings()
        let search = MeetingSearchModel()
        let query = "料金プラン"
        let semaphore = DispatchSemaphore(value: 0)
        var results: [MeetingSearchResult] = []
        let index = search.index
        Task.detached {
            await index.update(meetings)
            results = await index.search(query)
            semaphore.signal()
        }
        semaphore.wait()
        search.query = query
        search.setResultsForPreview(results)

        let recorder = MeetingRecorder()
        let detail: AnyView
        if ask {
            let model = MeetingAskModel()
            let sources = [
                MeetingAsk.Source(number: 1, meetingID: meetings[1].id, title: meetings[1].title, startedAt: meetings[1].startedAt, matched: true),
                MeetingAsk.Source(number: 2, meetingID: meetings[0].id, title: meetings[0].title, startedAt: meetings[0].startedAt, matched: true),
                MeetingAsk.Source(number: 3, meetingID: meetings[2].id, title: meetings[2].title, startedAt: meetings[2].startedAt, matched: false),
            ]
            let d = Meeting.dateFormatter
            let text = """
            先週の定例では、次のことが決まりました［M1: \(d.string(from: meetings[1].startedAt)) \(meetings[1].title)］。

            - 料金プランのリリースは **12 月 1 日**。告知は 2 週間前に出す
            - 問い合わせフォームにカテゴリの選択肢を追加する

            ## 根拠
            - M1: \(d.string(from: meetings[1].startedAt)) \(meetings[1].title)
            """
            model.setAnswerForPreview(question: "先週の定例で何が決まった？", answer: MeetingAsk.Answer(
                text: text, sources: sources, cited: MeetingAsk.cited(in: text, sources: sources), keywords: ["定例"]))
            detail = AnyView(MeetingAskView(model: model, meetings: meetings, index: index) { _ in })
        } else {
            let target = results.first { $0.meetingID == meetings[1].id }?.hits.first {
                if case .transcript = $0.location { return true }
                return false
            }
            let jump = target.map { MeetingJump(meetingID: $0.meetingID, location: $0.location, terms: [query]) }
            detail = AnyView(MeetingDetailView(meeting: meetings[1], recorder: recorder, jump: jump))
        }
        let selectedHit = ask ? nil : results.first { $0.meetingID == meetings[1].id }?.hits.first {
            if case .transcript = $0.location { return true }
            return false
        }?.id

        let view = HStack(spacing: 0) {
            VStack(spacing: 0) {
                MeetingSearchField(model: search) {}
                MeetingSearchResultsList(model: search, selectedHitID: selectedHit) { _, _ in }
            }
            .frame(width: 300)
            Divider()
            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 1000, height: 640)
        .background(Color(nsColor: .windowBackgroundColor))

        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 1000, height: 640)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        // スクロールや非同期の更新が終わるまで少し回す
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        hosting.layoutSubtreeIfNeeded()
        if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            print("wrote")
        }
    }
}
