import AppKit
import SwiftUI

// 議事録のテンプレートと書き出しの確認用の CLI モード:
//   Hanasu --minutes-from-transcript <文字起こし.txt> [--template auto|regular|oneOnOne|sales|brainstorm|custom]
//          [--custom-prompt <指示>] [--title <会議名>] [--date "yyyy-MM-dd HH:mm"] [--model <id>] [--save-json <meeting.json>]
//     文字起こし（1 行 1 発言、「[00:12] 話者: 発言」か「話者: 発言」）から議事録を作り、
//     議事録・アクションアイテム・Slack 向け・テキストの書き出しを表示する。会議ノート（~/Documents）には保存しない。
//   Hanasu --export-minutes <meeting.json | minutes.md>
//     Gemini を呼ばずに、保存済みの議事録の書き出し（Slack 向け・テキスト・アクションアイテム）を表示する。
//     .md が <action_items> を含む Gemini の応答そのものなら、応答の読み取りから行う。
//   Hanasu --test-saved-templates
//     名前付きテンプレートの保存・名前の重複の拒否・複製・削除・記録への適用・プロンプトへの反映を、
//     専用の UserDefaults で確かめる（本物の設定は変えない）。失敗があれば終了コード 1。
//   Hanasu --render-minutes-ui <出力フォルダ> [--meeting-json <meeting.json>]
//     議事録の型の選択欄（保存したテンプレート入りも）・テンプレートの管理・会議ノートの詳細・リマインダー登録・カスタムの指示の画面を PNG にする（見た目の確認用）。
// --meeting-files にも --template / --custom-prompt を付けられる。
// 確かめ方: REQ-MTG-006, REQ-MTG-007, REQ-MTG-017, REQ-MTG-018, REQ-MTG-019, REQ-MTG-027, REQ-MTG-028, REQ-MTG-029, REQ-MTG-042
@MainActor
enum MinutesCLI {
    static func runIfRequested(_ args: [String] = CommandLine.arguments) {
        if let path = value(after: "--minutes-from-transcript", in: args) {
            Task { @MainActor in
                do {
                    try await minutesFromTranscript(path: path, args: args)
                    exit(0)
                } catch {
                    FileHandle.standardError.write(Data("error: \(error.localizedDescription) (\(error))\n".utf8))
                    exit(1)
                }
            }
            RunLoop.main.run()
        }
        if args.contains("--test-saved-templates") {
            exit(savedTemplatesSelfTest() ? 0 : 1)
        }
        if let path = value(after: "--export-minutes", in: args) {
            do {
                let meeting = try loadMeeting(path: path)
                printExports(meeting)
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
                exit(1)
            }
        }
        if let dir = value(after: "--render-minutes-ui", in: args) {
            do {
                let meeting = try value(after: "--meeting-json", in: args).map(loadMeeting(path:)) ?? sampleMeeting()
                try renderUI(meeting: meeting, to: URL(fileURLWithPath: dir, isDirectory: true))
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
                exit(1)
            }
        }
    }

    /// --template / --custom-prompt を会議に付ける（--meeting-files 用）
    static func applyTemplateArguments(_ args: [String], to meeting: inout Meeting) {
        if let id = value(after: "--template", in: args) {
            guard let template = MinutesTemplate(rawValue: id) else {
                FileHandle.standardError.write(Data("unknown template: \(id)（\(MinutesTemplate.allCases.map(\.rawValue).joined(separator: ", "))）\n".utf8))
                exit(2)
            }
            meeting.minutesTemplate = template.rawValue
        }
        if let prompt = value(after: "--custom-prompt", in: args) {
            meeting.minutesTemplate = MinutesTemplate.custom.rawValue
            meeting.customMinutesPrompt = prompt
        }
    }

    // MARK: - 名前付きテンプレート

    // 確かめ方: REQ-MTG-042
    /// 名前付きテンプレートの保存まわりを、専用の UserDefaults で確かめる。全部通れば true
    private static func savedTemplatesSelfTest() -> Bool {
        let suite = "dev.mactypeless.Hanasu.saved-templates-selftest"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        var failures = 0
        func check(_ ok: Bool, _ what: String) {
            print((ok ? "OK  " : "NG  ") + what)
            if !ok { failures += 1 }
        }
        typealias Store = SavedMinutesTemplateStore

        var list = Store.load(defaults)
        check(list.isEmpty, "最初は 1 つもない")

        check(Store.add(name: "  営業定例  ", instructions: "## 数字\n## 課題", to: &list) == nil, "名前を付けて追加できる")
        check(list.first?.name == "営業定例", "名前の前後の空白は取る")
        check(Store.add(name: "営業定例", instructions: "x", to: &list) == .duplicateName, "同じ名前は追加できない")
        check(Store.add(name: "営業定例 ", instructions: "x", to: &list) == .duplicateName, "空白だけ違う名前も重複")
        check(Store.add(name: "", instructions: "x", to: &list) == .emptyName, "名前が空は追加できない")
        check(Store.add(name: "採用面接", instructions: "  \n", to: &list) == .emptyInstructions, "指示が空は追加できない")
        check(Store.add(name: "採用面接", instructions: "## 評価\n## 懸念", to: &list) == nil, "2 つ目を追加できる")
        check(list.count == 2, "2 つある")

        Store.save(list, to: defaults)
        let reloaded = Store.load(defaults)
        check(reloaded == list, "保存して読み直すと同じ（UserDefaults の JSON）")

        let first = reloaded[0], second = reloaded[1]
        var edited = reloaded
        check(Store.update(id: first.id, name: "採用面接", instructions: "y", in: &edited) == .duplicateName,
              "ほかと同じ名前には直せない")
        check(Store.update(id: first.id, name: "営業定例", instructions: "## 変更後", in: &edited) == nil
              && edited[0].instructions == "## 変更後", "自分の名前のままなら指示を直せる")
        check(Store.update(id: first.id, name: "営業定例 週次", instructions: "## 変更後", in: &edited) == nil
              && edited[0].name == "営業定例 週次", "名前を直せる")

        var duplicated = reloaded
        let copyID = Store.duplicate(id: first.id, in: &duplicated)
        check(duplicated.count == 3 && duplicated[1].id == copyID && duplicated[1].name == "営業定例 2"
              && duplicated[1].instructions == first.instructions, "複製は「名前 2」で、元の下に入る")

        // 記録への適用
        defaults.set(Store.selection(for: second), forKey: MinutesTemplateStore.templateKey)
        var meeting = Meeting(id: "t", title: "t", startedAt: Date())
        MinutesTemplateStore.apply(to: &meeting, defaults: defaults)
        check(meeting.template == .custom && meeting.customMinutesPrompt == second.instructions
              && meeting.minutesTemplateName == "採用面接" && meeting.templateTitle == "採用面接",
              "保存したテンプレートを選ぶと、会議に型（カスタム）・指示・名前が付く")

        let system = MinutesPrompt.systemInstruction(template: meeting.template, customPrompt: meeting.customMinutesPrompt)
        check(system.contains("<user_template>\n\(second.instructions)\n</user_template>") && system.contains(MinutesPrompt.placeholder),
              "議事録の指示にテンプレートの指示が入り、アクションアイテムの目印も付く")

        // この会議に写した指示は、あとでテンプレートを直しても変わらない
        var changed = reloaded
        _ = Store.update(id: second.id, name: "採用面接", instructions: "## 別の指示", in: &changed)
        check(meeting.customMinutesPrompt == second.instructions, "あとでテンプレートを直しても、記録済みの会議は変わらない")

        // meeting.json に残り、読み直せる
        if let data = try? JSONEncoder().encode(meeting), let back = try? JSONDecoder().decode(Meeting.self, from: data) {
            check(back.minutesTemplateName == "採用面接" && back.customMinutesPrompt == second.instructions, "meeting.json に名前と指示が残る")
        } else {
            check(false, "meeting.json に書いて読み直せる")
        }
        // 名前のない古い会議
        var old = Meeting(id: "o", title: "o", startedAt: Date())
        old.minutesTemplate = MinutesTemplate.custom.rawValue
        check(old.templateTitle == "カスタム", "名前のない古いカスタムの会議は「カスタム」と出す")

        // 削除・選んでいたテンプレートが消えたとき
        Store.save(Store.load(defaults).filter { $0.id != second.id }, to: defaults)
        var after = Meeting(id: "a", title: "a", startedAt: Date())
        MinutesTemplateStore.apply(to: &after, defaults: defaults)
        check(after.template == .auto && after.customMinutesPrompt == nil && after.minutesTemplateName == nil,
              "選んでいたテンプレートを消すと、次の記録は「自動」になる")

        // 組み込みの型を選んだとき
        defaults.set(MinutesTemplate.sales.rawValue, forKey: MinutesTemplateStore.templateKey)
        var builtin = Meeting(id: "b", title: "b", startedAt: Date())
        MinutesTemplateStore.apply(to: &builtin, defaults: defaults)
        check(builtin.template == .sales && builtin.minutesTemplateName == nil, "組み込みの型は今まで通り")

        // 壊れた JSON
        defaults.set("{broken", forKey: Store.listKey)
        check(Store.load(defaults).isEmpty, "保存した JSON が壊れていても、空として読む")

        print(failures == 0 ? "saved-templates-selftest: 全部 OK" : "saved-templates-selftest: \(failures) 件 NG")
        return failures == 0
    }

    // MARK: - 文字起こしから議事録

    private static func minutesFromTranscript(path: String, args: [String]) async throws {
        let text = try String(contentsOfFile: path, encoding: .utf8)
        var meeting = Meeting(id: "cli", title: value(after: "--title", in: args)
                              ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
                              startedAt: value(after: "--date", in: args).flatMap(parseDate) ?? Date())
        meeting.utterances = parseTranscript(text)
        meeting.duration = (meeting.utterances.last?.end ?? 0) + 5
        meeting.status = .done
        applyTemplateArguments(args, to: &meeting)

        let settings = AppSettings.shared
        let model = TextAIClient.cliModel(args: args, settings: settings, for: .meeting)
        let started = Date()
        let client = try TextAIClient.cli(args: args, settings: settings, for: .meeting, timeout: 300)
        let result = try await MeetingProcessor.makeMinutes(for: meeting, client: client, model: model)
        meeting.applyMinutes(result)
        print(String(format: "[議事録 %@ 型=%@ %.1fs 発言 %d 件]", model, meeting.template.title,
                     Date().timeIntervalSince(started), meeting.utterances.count))
        // 要件: REQ-MTG-027
        let inferred = (meeting.inferredSpeakers ?? []).map { "\($0)=\(meeting.speakerNames[$0] ?? "")" }
        print("[推測した話者の名前] 応答: \(result.speakerNames.isEmpty ? "なし" : result.speakerNames.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))"
              + " / 付けた: \(inferred.isEmpty ? "なし" : inferred.joined(separator: ", "))")
        printExports(meeting)
        if let out = value(after: "--save-json", in: args) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(meeting).write(to: URL(fileURLWithPath: out))
            print("保存: \(out)")
        }
    }

    private static func printExports(_ meeting: Meeting) {
        print("===== 議事録（Markdown） =====")
        print(meeting.minutes ?? "(なし)")
        print("===== アクションアイテム（構造化） =====")
        for item in meeting.resolvedActionItems {
            print("- 担当: \(item.owner ?? "-") | 内容: \(item.task) | 期限: \(item.due ?? "-") | 期限の言い方: \(item.dueNote ?? "-")")
        }
        print("===== Slack 向け =====")
        print(MeetingExport.slack(meeting) ?? "(議事録なし)")
        print("===== テキスト（.txt） =====")
        print(MeetingExport.plainText(fromMarkdown: meeting.minutes ?? meeting.transcriptMarkdown()))
        print("===== リマインダーのメモ（1 件目） =====")
        if let first = meeting.resolvedActionItems.first {
            print("タイトル: \(first.task)\n期限: \(first.dueDate.map { ActionItem.isoFormatter.string(from: $0) } ?? "なし")\n\(ReminderExporter.notes(for: first, meeting: meeting))")
        }
    }

    /// 「[00:12] 話者: 発言」または「話者: 発言」の行を発言にする
    static func parseTranscript(_ text: String) -> [Utterance] {
        var result: [Utterance] = []
        var clock = 0.0
        let timed = try? NSRegularExpression(pattern: #"^\[(?:(\d+):)?(\d+):(\d+)\]\s*(.+?)\s*[:：]\s*(.+)$"#)
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            var speaker: String
            var body: String
            let ns = line as NSString
            if let m = timed?.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                func group(_ i: Int) -> String? { m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i)) }
                clock = Double(Int(group(1) ?? "0")! * 3600 + Int(group(2)!)! * 60 + Int(group(3)!)!)
                speaker = group(4)!
                body = group(5)!
            } else if let colon = line.firstIndex(where: { $0 == ":" || $0 == "：" }) {
                speaker = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                body = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                clock += 8
            } else {
                continue
            }
            result.append(Utterance(speaker: speakerKey(speaker), start: clock, end: clock + 6, text: body))
        }
        return result
    }

    private static func speakerKey(_ name: String) -> String {
        if name == "自分" { return "me" }
        if name == "相手" { return "others" }
        if name.hasPrefix("話者"), let n = Int(name.dropFirst(2)) { return "spk\(n)" }
        if name.hasPrefix("同席者"), let n = Int(name.dropFirst(3)) { return "room\(n)" }
        return name
    }

    // MARK: - 画面の描き出し

    private static func renderUI(meeting: Meeting, to dir: URL) throws {
        _ = NSApplication.shared
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // 本物の設定（UserDefaults）を書き換えないよう、描き出し用の入れ物を使う
        let suite = "dev.mactypeless.Hanasu.render-preview"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(MinutesTemplate.sales.rawValue, forKey: MinutesTemplateStore.templateKey)
        defer { defaults.removePersistentDomain(forName: suite) }
        let recorder = MeetingRecorder()

        let panel = VStack(spacing: 10) {
            MeetingDevicePickers(compact: true)
            MinutesTemplatePicker()
            Button {} label: { Label("会議の記録を開始", systemImage: "record.circle").frame(maxWidth: .infinity) }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
        }
        .padding(10)
        .frame(width: 260)
        .defaultAppStorage(defaults)
        try render(panel, to: dir.appendingPathComponent("record-panel.png"))

        defaults.set(MinutesTemplate.custom.rawValue, forKey: MinutesTemplateStore.templateKey)
        let customPanel = VStack(spacing: 10) { MinutesTemplatePicker() }
            .padding(10).frame(width: 260).defaultAppStorage(defaults)
        try render(customPanel, to: dir.appendingPathComponent("record-panel-custom.png"))

        let detail = MeetingDetailView(meeting: meeting, recorder: recorder, onDelete: {})
            .frame(width: 600, height: 640)
            .defaultAppStorage(defaults)
        try render(detail, to: dir.appendingPathComponent("detail.png"))
        // 確かめ方: REQ-MTG-013
        // 議事録を作り直している途中（上に「作り直しています」と出て、今の議事録は薄く出る）
        recorder.regeneratingID = meeting.id
        let regenerating = MeetingDetailView(meeting: meeting, recorder: recorder)
            .frame(width: 600, height: 640)
            .defaultAppStorage(defaults)
        try render(regenerating, to: dir.appendingPathComponent("detail-regenerating.png"))
        recorder.regeneratingID = nil
        // 「メモ」タブ（長いメモでも、上のタブの切り替えが見えたままか）
        var noted = meeting
        // 型を書いておく（三項演算子を重ねると、リリースの最適化ビルドで型の推論が時間切れになる）
        noted.notes = (0..<60).map { (i: Int) -> MeetingNote in
            let isHighlight = i % 7 == 3
            let kind: MeetingNote.Kind = isHighlight ? .highlight : .note
            let text = isHighlight ? "" : "メモ \(i + 1)"
            return MeetingNote(kind: kind, time: Double(i * 40), text: text)
        }
        let notesTab = MeetingDetailView(meeting: noted, recorder: recorder, initialTab: 2)
            .frame(width: 600, height: 640)
            .defaultAppStorage(defaults)
        try render(notesTab, to: dir.appendingPathComponent("detail-notes.png"))
        checkWindowHeight(meeting: noted, recorder: recorder, dir: dir)
        // 「ここ重要」タブ（印の前後の発言）
        var marked = meeting
        let times = marked.mergedBlocks().map(\.start)
        if let first = times.first, let last = times.last {
            marked.notes = [
                MeetingNote(kind: .highlight, time: times[min(2, times.count - 1)] + 5, text: "価格の条件"),
                MeetingNote(kind: .note, time: first, text: "メモは出さない"),
                MeetingNote(kind: .highlight, time: last + 3, text: ""),
            ]
        }
        print("ここ重要の前後: " + marked.highlightContexts().map { "\(Meeting.clock($0.note.time ?? 0)) の前後 \($0.blocks.count) 発言" }
            .joined(separator: " / "))
        let highlightsTab = MeetingDetailView(meeting: marked, recorder: recorder, initialTab: 3)
            .frame(width: 600, height: 640)
            .defaultAppStorage(defaults)
        try render(highlightsTab, to: dir.appendingPathComponent("detail-highlights.png"))

        let reminders = ReminderExportSheet(meeting: meeting, recorder: recorder)
        try render(reminders, to: dir.appendingPathComponent("reminders-sheet.png"))

        let custom = CustomMinutesPromptSheet(prompt: MinutesTemplateStore.defaultCustomPrompt, actionLabel: "作り直す") { _ in }
        try render(custom, to: dir.appendingPathComponent("custom-prompt-sheet.png"))

        // 要件: REQ-MTG-042
        // 保存したテンプレートを入れた選択欄と、管理のシート
        var samples: [SavedMinutesTemplate] = []
        _ = SavedMinutesTemplateStore.add(name: "営業定例", instructions: "## 数字の共有\n## 課題\n## 来週やること", to: &samples)
        _ = SavedMinutesTemplateStore.add(name: "採用面接", instructions: "## 候補者の印象\n## 評価\n## 懸念", to: &samples)
        defaults.set(SavedMinutesTemplateStore.encode(samples), forKey: SavedMinutesTemplateStore.listKey)
        defaults.set(SavedMinutesTemplateStore.selection(for: samples[0]), forKey: MinutesTemplateStore.templateKey)
        let savedPanel = VStack(spacing: 10) { MinutesTemplatePicker() }
            .padding(10).frame(width: 260).defaultAppStorage(defaults)
        try render(savedPanel, to: dir.appendingPathComponent("record-panel-saved.png"))
        let manager = MinutesTemplateManagerSheet().defaultAppStorage(defaults)
        try render(manager, to: dir.appendingPathComponent("template-manager-sheet.png"))
        print("wrote: \(dir.path)")
    }

    // 確かめ方: REQ-MTG-007
    /// 会議ノートのウインドウで「メモ」タブを開いても、ウインドウが縦に伸びず、中身もウインドウからはみ出さない
    /// （タイトルとタブが画面の外に出ない）か。window-tab<番号>.png に、そのときのウインドウの中身を描き出す
    private static func checkWindowHeight(meeting: Meeting, recorder: MeetingRecorder, dir: URL) {
        for tab in [0, 1, 2] {
            // 本物の会議ノートと同じく、左に一覧・右に詳細の画面を並べて開く
            let window = AppDelegate.makeMeetingWindow(rootView: NavigationSplitView {
                List { Text("会議") }
                    .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            } detail: {
                MeetingDetailView(meeting: meeting, recorder: recorder, initialTab: tab, onDelete: {})
            })
            window.appearance = NSAppearance(named: .aqua)
            window.orderBack(nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            let height = window.frame.height
            let contentHeight = window.contentView?.bounds.height ?? 0
            let splitHeight = window.contentView.flatMap(splitView(in:))?.frame.height ?? 0
            let fits = splitHeight <= contentHeight + 1
            print("会議ノートのウインドウの高さ（タブ \(tab)）: \(Int(height))（開いたときは \(Int(AppDelegate.meetingWindowSize.height)) 前後）"
                  + "・中身の高さ \(Int(splitHeight))／ウインドウの中身 \(Int(contentHeight))"
                  + (fits ? "" : " → NG: 中身がはみ出し、タイトルとタブが画面の外に出る"))
            if let content = window.contentView, let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                content.cacheDisplay(in: content.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("window-tab\(tab).png"))
            }
            window.close()
        }
    }

    /// 左右に並べる画面（NavigationSplitView）の中身の NSSplitView
    private static func splitView(in view: NSView) -> NSSplitView? {
        if let split = view as? NSSplitView { return split }
        for sub in view.subviews { if let found = splitView(in: sub) { return found } }
        return nil
    }

    private static func render(_ view: some View, to url: URL) throws {
        // メニュー型の Picker などは AppKit の部品なので、画面外のウインドウに置いて描く
        let hosting = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        // onAppear などを反映させる
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// 描き出し用の架空の会議
    private static func sampleMeeting() -> Meeting {
        var meeting = Meeting(id: "sample", title: "架空商事 打ち合わせ", startedAt: Date(timeIntervalSince1970: 1_793_000_000))
        meeting.duration = 1820
        meeting.status = .done
        meeting.minutesTemplate = MinutesTemplate.sales.rawValue
        meeting.utterances = parseTranscript("""
        [00:05] 自分: 本日はお時間ありがとうございます。
        [00:12] 話者1: よろしくお願いします。
        """)
        meeting.actionItems = [
            ActionItem(owner: "自分", task: "見積書を送る", due: "2026-11-06", dueNote: "今週金曜"),
            ActionItem(owner: "話者1", task: "社内で導入の可否を確認する", dueNote: "来週中"),
            ActionItem(task: "次回の打ち合わせの日程を決める"),
        ]
        meeting.minutes = """
        # 架空商事 打ち合わせ — 議事録

        ## 概要
        架空商事の議事録作成の手間について伺い、Hanasu の会議記録を提案した。

        ## 顧客の課題
        - 会議のたびに **議事録の作成に 30 分** かかっている

        ## 次のアクション
        \(meeting.actionItems!.map(\.markdownLine).joined(separator: "\n"))
        """
        return meeting
    }

    // MARK: - 共通

    private static func loadMeeting(path: String) throws -> Meeting {
        let url = URL(fileURLWithPath: path)
        if url.pathExtension == "json" {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Meeting.self, from: Data(contentsOf: url))
        }
        var meeting = Meeting(id: "cli", title: url.deletingPathExtension().lastPathComponent, startedAt: Date())
        let text = try String(contentsOf: url, encoding: .utf8)
        if text.contains("<action_items>") || text.contains(MinutesPrompt.placeholder) || MinutesPrompt.inlineItems(in: text) != nil {
            // AI の応答そのもの（応答の読み取りの確認用。本文の中に JSON を書いた小さいモデルの応答も）
            let result = MinutesPrompt.parse(text, title: meeting.title)
            meeting.minutes = result.markdown
            meeting.actionItems = result.actionItems
        } else {
            meeting.minutes = text
        }
        return meeting
    }

    private static func parseDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s)
    }

    private static func value(after flag: String, in args: [String]) -> String? {
        args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
    }
}
