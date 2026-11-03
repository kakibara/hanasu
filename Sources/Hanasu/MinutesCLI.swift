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
//   Hanasu --render-minutes-ui <出力フォルダ> [--meeting-json <meeting.json>]
//     議事録の型の選択欄・会議ノートの詳細・リマインダー登録・カスタムの指示の画面を PNG にする（見た目の確認用）。
// --meeting-files にも --template / --custom-prompt を付けられる。
// 確かめ方: REQ-MTG-006, REQ-MTG-007, REQ-MTG-017, REQ-MTG-018, REQ-MTG-019
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
        meeting.minutes = result.markdown
        meeting.actionItems = result.actionItems
        print(String(format: "[議事録 %@ 型=%@ %.1fs 発言 %d 件]", model, meeting.template.title,
                     Date().timeIntervalSince(started), meeting.utterances.count))
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

        let detail = MeetingDetailView(meeting: meeting, recorder: recorder)
            .frame(width: 600, height: 640)
            .defaultAppStorage(defaults)
        try render(detail, to: dir.appendingPathComponent("detail.png"))

        let reminders = ReminderExportSheet(meeting: meeting, recorder: recorder)
        try render(reminders, to: dir.appendingPathComponent("reminders-sheet.png"))

        let custom = CustomMinutesPromptSheet(prompt: MinutesTemplateStore.defaultCustomPrompt, actionLabel: "作り直す") { _ in }
        try render(custom, to: dir.appendingPathComponent("custom-prompt-sheet.png"))
        print("wrote: \(dir.path)")
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
        if text.contains("<action_items>") || text.contains(MinutesPrompt.placeholder) {
            // Gemini の応答そのもの（応答の読み取りの確認用）
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
