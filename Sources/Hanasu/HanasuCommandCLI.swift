import CryptoKit
import Foundation

// 利用者向けの hanasu コマンド（HanasuCommand.swift・HanasuMeetingsCommand.swift）の確認:
//   Hanasu --test-hanasu-command           架空の会議を一時フォルダに作り、本物の実行ファイルをコマンドとして呼んで確かめる
//   Hanasu --bench-hanasu-command [件数]   架空の会議（既定 1,000 件）で、list / show / search / actions の時間を測る
// 確かめ方: REQ-COM-180, REQ-COM-181, REQ-COM-182, REQ-COM-183, REQ-COM-184, REQ-COM-185
// 確かめ方: REQ-MTG-120, REQ-MTG-121, REQ-MTG-122, REQ-MTG-123, REQ-MTG-124, REQ-MTG-125
enum HanasuCommandCLI {
    static func runIfRequested() {
        let args = CommandLine.arguments
        if args.contains("--test-hanasu-command") {
            runSelfTest()
        }
        if let index = args.firstIndex(of: "--bench-hanasu-command") {
            let count = args.indices.contains(index + 1) ? Int(args[index + 1]) ?? 1000 : 1000
            runBenchmark(count: count)
        }
    }

    // MARK: - 自己テスト

    private static var failures = 0

    private static func check(_ condition: Bool, _ label: String) {
        print("\(condition ? "OK  " : "NG  ") \(label)")
        if !condition { failures += 1 }
    }

    struct Result {
        var status: Int32
        var stdout: String
        var stderr: String
        var json: [String: Any]? {
            (try? JSONSerialization.jsonObject(with: Data(stdout.utf8))) as? [String: Any]
        }
    }

    /// 実行ファイルを子プロセスとして呼ぶ（表示の言語は日本語に固定する）
    static func call(_ executable: URL, _ arguments: [String], environment: [String: String] = [:], language: String = "ja") -> Result {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments + ["-AppleLanguages", "(\(language))"]
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "HANASU_MEETINGS_DIR")
        for (key, value) in environment { env[key] = value }
        process.environment = env
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return Result(status: -1, stdout: "", stderr: "\(error)") }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(status: process.terminationStatus, stdout: String(decoding: outData, as: UTF8.self),
                      stderr: String(decoding: errData, as: UTF8.self))
    }

    static var executable: URL {
        Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
    }

    private static func date(_ text: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: text)!
    }

    private static func write(_ meeting: Meeting, to base: URL) throws {
        let dir = base.appendingPathComponent(meeting.id, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(meeting).write(to: dir.appendingPathComponent("meeting.json"))
    }

    /// 会議のフォルダの meeting.json ごとのハッシュ（コマンドが書き換えていないことを確かめる）
    private static func fingerprints(_ base: URL) -> [String: String] {
        var result: [String: String] = [:]
        let dirs = (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? []
        for dir in dirs {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("meeting.json")) else { continue }
            result[dir.lastPathComponent] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        return result
    }

    static func makeFixtures(in base: URL) throws {
        let excluded = Utterance(speaker: "me", start: 20, end: 22, text: "ひみつのことばはりんご")
        var first = Meeting(id: "2026-10-01 0900", title: "予算の定例", startedAt: date("2026-10-01 09:00"))
        first.duration = 1800
        first.status = .done
        first.speakerNames = ["spk1": "田中"]
        first.inferredSpeakers = ["spk1"]
        first.utterances = [
            Utterance(speaker: "me", start: 1, end: 5, text: "来期の予算の話をします"),
            Utterance(speaker: "spk1", start: 10, end: 14, text: "田中です、了解しました"),
            excluded,
            Utterance(speaker: "spk1", start: 40, end: 44, text: "ここからはオフレコの雑談です"),
            Utterance(speaker: "me", start: 60, end: 64, text: "では予算案をまとめます"),
        ]
        first.excludedUtterances = [excluded.id]
        first.offRecord = [OffRecordSpan(start: 35, end: 50)]
        first.minutes = "# 予算の定例 — 議事録\n\n## 概要\n- 来期の予算案をまとめる"
        first.actionItems = [ActionItem(owner: "田中", task: "予算案の下書きを書く", due: "2026-10-08", dueNote: "来週中")]
        first.notes = [MeetingNote(kind: .note, time: 12, text: "数字を確認")]

        var second = Meeting(id: "2026-10-02 1000", title: "採用の相談", startedAt: date("2026-10-02 10:00"))
        second.status = .done
        second.minutes = "# 採用の相談 — 議事録"
        second.actionItems = [ActionItem(owner: "佐藤", task: "候補者に連絡する")]
        var third = Meeting(id: "2026-10-02 1500", title: "週次の振り返り", startedAt: date("2026-10-02 15:00"))
        third.status = .done
        third.minutes = "# 週次の振り返り — 議事録"
        var fourth = Meeting(id: "2026-10-03 1100", title: "記録中の会議", startedAt: date("2026-10-03 11:00"))
        fourth.status = .processing
        for meeting in [first, second, third, fourth] { try write(meeting, to: base) }
        // 壊れた meeting.json は飛ばす
        let broken = base.appendingPathComponent("broken", isDirectory: true)
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: broken.appendingPathComponent("meeting.json"))
    }

    static func runSelfTest() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("hanasu-command-test-\(UUID().uuidString)", isDirectory: true)
        let base = root.appendingPathComponent("Meetings", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        do { try makeFixtures(in: base) } catch {
            print("NG   架空の会議を作れない: \(error)")
            exit(1)
        }
        let before = fingerprints(base)
        let exe = executable
        let dir = ["--meetings-dir", base.path]

        // 振り分け（REQ-COM-180）
        check(HanasuCommand.handles(["/x/Hanasu", "meetings", "list"]), "Hanasu meetings はコマンドとして扱う")
        check(!HanasuCommand.handles(["/x/Hanasu", "--test-hanasu-command"]), "開発用の -- のフラグはコマンドとして扱わない")
        check(!HanasuCommand.handles(["/x/Hanasu"]), "引数なしの Hanasu はアプリを起動する")
        check(HanasuCommand.handles(["/usr/local/bin/hanasu"]), "hanasu という名前で呼ばれたら、引数なしでもコマンド")
        let version = call(exe, ["--version"])
        check(version.status == 0 && version.stdout.hasPrefix("hanasu "), "--version は版を出して 0（\(version.stdout.trimmingCharacters(in: .newlines))）")
        let help = call(exe, ["help"])
        check(help.status == 0 && help.stdout.contains("hanasu meetings list"), "help は使い方を stdout に出す")

        // 一覧（REQ-MTG-120）と JSON の形（REQ-COM-181）
        let list = call(exe, ["meetings", "list", "--json"] + dir)
        let meetings = list.json?["meetings"] as? [[String: Any]] ?? []
        check(list.status == 0 && list.stderr.isEmpty, "meetings list --json は 0 で、stderr に何も出さない（\(list.stderr)）")
        check(list.json?["schemaVersion"] as? Int == 1, "JSON に schemaVersion: 1 がある")
        check(meetings.compactMap { $0["slug"] as? String } == ["2026-10-03_1100", "2026-10-02_1500", "2026-10-02_1000", "2026-10-01_0900"],
              "新しい順に 4 件（壊れた meeting.json は飛ばす）")
        check(meetings.last?["startedAt"] as? String == HanasuJSON.date(date("2026-10-01 09:00")), "日時は時差の付いた ISO 8601")
        check(meetings.last?["durationSeconds"] as? Int == 1800 && meetings.last?["actionItemCount"] as? Int == 1, "長さは秒、アクションアイテムの数")
        check(meetings.first?["status"] as? String == "processing", "処理中の会議にも状態を付けて出す（REQ-MTG-120）")
        let ranged = call(exe, ["meetings", "list", "--json", "--since", "2026-10-02", "--until", "2026-10-02"] + dir)
        check((ranged.json?["meetings"] as? [[String: Any]])?.count == 2, "--since / --until の日付は、その日を含む")
        let limited = call(exe, ["meetings", "list", "--json", "--limit", "1"] + dir)
        check((limited.json?["meetings"] as? [[String: Any]])?.count == 1, "--limit で件数を絞る")
        let text = call(exe, ["meetings", "list"] + dir)
        check(text.stdout.contains("2026-10-01_0900") && text.stdout.contains("[処理中]"), "文字の一覧に ID と状態が出る")

        // 会議の指定（REQ-MTG-122）
        let latest = call(exe, ["meetings", "show", "latest", "--json"] + dir)
        check((latest.json?["meeting"] as? [String: Any])?["slug"] as? String == "2026-10-02_1500", "latest は完了した会議のうち最新")
        check(latest.stderr.contains("2026-10-03_1100"), "latest より新しい処理中の会議を stderr で知らせる")
        let ambiguous = call(exe, ["meetings", "show", "2026-10-02"] + dir)
        check(ambiguous.status == 4 && ambiguous.stdout.isEmpty && ambiguous.stderr.contains("2026-10-02_1000"), "日付で 2 件当たれば 4 で、候補を stderr に出す")
        let byDate = call(exe, ["meetings", "show", "2026-10-01", "--json"] + dir)
        check(byDate.status == 0, "日付で 1 件に決まれば、その会議")
        let bySpace = call(exe, ["meetings", "show", "2026-10-01 0900", "--json"] + dir)
        let bySlug = call(exe, ["meetings", "show", "2026-10-01_0900", "--json"] + dir)
        check(bySpace.status == 0 && bySlug.status == 0, "フォルダ名（空白あり）でも、空白を _ にした形でも指定できる")
        let missing = call(exe, ["meetings", "show", "2020-01-01_0000"] + dir)
        check(missing.status == 4, "ない会議は 4")

        // 中身（REQ-MTG-121）
        let all = call(exe, ["meetings", "show", "2026-10-01_0900", "--all", "--json"] + dir)
        let meeting = all.json?["meeting"] as? [String: Any] ?? [:]
        let transcript = meeting["transcript"] as? [[String: Any]] ?? []
        let texts = transcript.compactMap { $0["text"] as? String }.joined()
        check(!transcript.isEmpty && !texts.contains("ひみつ") && !texts.contains("オフレコ"), "文字起こしに、除いた発言とオフレコの発言を出さない")
        check(meeting["omittedUtteranceCount"] as? Int == 2, "出さなかった発言の数を出す")
        let speakers = meeting["speakers"] as? [[String: Any]] ?? []
        check(speakers.contains { $0["key"] as? String == "spk1" && $0["name"] as? String == "田中" && $0["inferred"] as? Bool == true },
              "話者はキーと名前と、推測かどうか")
        check((meeting["actionItems"] as? [[String: Any]])?.first?["due"] as? String == "2026-10-08", "アクションアイテムの期限")
        check((meeting["notes"] as? [[String: Any]])?.first?["text"] as? String == "数字を確認", "メモ")
        check(meeting["minutes"] is String, "--all には議事録も入る")
        let minutesOnly = call(exe, ["meetings", "show", "2026-10-01_0900", "--json"] + dir)
        let minutesMeeting = minutesOnly.json?["meeting"] as? [String: Any] ?? [:]
        check(minutesMeeting["minutes"] is String && minutesMeeting["transcript"] == nil, "既定は議事録だけ")
        let transcriptText = call(exe, ["meetings", "show", "2026-10-01_0900", "--transcript"] + dir)
        check(transcriptText.stdout.contains("田中（推測）") && !transcriptText.stdout.contains("ひみつ"), "文字の文字起こしで、推測した名前に印を付ける")

        // 検索（REQ-MTG-123）
        let found = call(exe, ["meetings", "search", "予算", "--json"] + dir)
        let results = found.json?["results"] as? [[String: Any]] ?? []
        check(results.count == 1 && (results.first?["totalHits"] as? Int ?? 0) >= 2, "会議を横断して検索する")
        let secret = call(exe, ["meetings", "search", "ひみつのことば", "--json"] + dir)
        let offRecord = call(exe, ["meetings", "search", "オフレコの雑談", "--json"] + dir)
        check((secret.json?["results"] as? [Any])?.isEmpty == true && (offRecord.json?["results"] as? [Any])?.isEmpty == true,
              "除いた発言・オフレコの発言は検索に出さない（DEC-MTG-121）")
        let noQuery = call(exe, ["meetings", "search"] + dir)
        check(noQuery.status == 2, "検索する語がなければ 2")

        // アクションアイテム（REQ-MTG-124）
        let actions = call(exe, ["actions", "--owner", "田中", "--json"] + dir)
        let items = actions.json?["actionItems"] as? [[String: Any]] ?? []
        check(items.count == 1 && (items.first?["meeting"] as? [String: Any])?["slug"] as? String == "2026-10-01_0900",
              "--owner で担当を絞り、会議の ID を付ける")
        let allActions = call(exe, ["actions", "--json"] + dir)
        check((allActions.json?["actionItems"] as? [Any])?.count == 2, "会議をまたいで並べる")

        // 会議のフォルダ（REQ-MTG-125）
        let env = call(exe, ["meetings", "list", "--json"], environment: ["HANASU_MEETINGS_DIR": base.path])
        check((env.json?["meetings"] as? [Any])?.count == 4, "環境変数 HANASU_MEETINGS_DIR で会議のフォルダを変えられる")
        let none = call(exe, ["meetings", "list", "--json", "--meetings-dir", root.appendingPathComponent("none").path])
        check(none.status == 0 && (none.json?["meetings"] as? [Any])?.isEmpty == true, "フォルダがなければ、会議がないだけ（0）")

        // 権限がない（REQ-COM-185）
        let locked = root.appendingPathComponent("Locked", isDirectory: true)
        try? fm.createDirectory(at: locked, withIntermediateDirectories: true)
        try? fm.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        let denied = call(exe, ["meetings", "list", "--meetings-dir", locked.path])
        check(denied.status == 5 && denied.stdout.isEmpty && denied.stderr.contains(locked.path), "フォルダを読めなければ 5 と、どこを読めないか")
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path)

        // 使い方の誤り（REQ-COM-182）
        let badOption = call(exe, ["meetings", "list", "--bogus"] + dir)
        check(badOption.status == 2 && badOption.stdout.isEmpty, "知らないオプションは 2 で、stdout に何も出さない")
        let badPeriod = call(exe, ["meetings", "list", "--since", "yesterday"] + dir)
        check(badPeriod.status == 2, "読めない期間は 2")
        let bareMeetings = call(exe, ["meetings"] + dir)
        check(bareMeetings.status == 2 && bareMeetings.stdout.isEmpty, "meetings だけなら 2 で、使い方は stderr")

        // hanasu という名前で呼ぶ（シンボリックリンク）
        let link = root.appendingPathComponent("hanasu")
        try? fm.createSymbolicLink(at: link, withDestinationURL: exe)
        let bare = call(link, [])
        check(bare.status == 0 && bare.stdout.contains("hanasu meetings list"), "hanasu だけなら使い方を出して 0（アプリを起動しない）")
        let unknown = call(link, ["foo"])
        check(unknown.status == 2, "hanasu foo は 2")
        let viaLink = call(link, ["meetings", "list", "--json"] + dir)
        check((viaLink.json?["meetings"] as? [Any])?.count == 4, "シンボリックリンク経由でも動く")

        // シンボリックリンクから起動しても、.app の版・訳を読める（DEC-COM-183）
        let app = root.appendingPathComponent("Test.app/Contents", isDirectory: true)
        let resources = exe.deletingLastPathComponent().appendingPathComponent(HanasuResources.bundleName)
        do {
            try fm.createDirectory(at: app.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
            try fm.createDirectory(at: app.appendingPathComponent("Resources"), withIntermediateDirectories: true)
            try fm.copyItem(at: exe, to: app.appendingPathComponent("MacOS/Hanasu"))
            if fm.fileExists(atPath: resources.path) {
                try fm.copyItem(at: resources, to: app.appendingPathComponent("Resources/\(HanasuResources.bundleName)"))
            }
            let plist: [String: Any] = ["CFBundleExecutable": "Hanasu", "CFBundleIdentifier": "dev.mactypeless.Hanasu",
                                        "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "0.0.0-selftest"]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: app.appendingPathComponent("Info.plist"))
            let appLink = root.appendingPathComponent("bin/hanasu")
            try fm.createDirectory(at: appLink.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createSymbolicLink(at: appLink, withDestinationURL: app.appendingPathComponent("MacOS/Hanasu"))
            let linked = call(appLink, ["--version"])
            check(linked.stdout.trimmingCharacters(in: .newlines) == "hanasu 0.0.0-selftest", "シンボリックリンクから起動しても、.app の Info.plist を読む（\(linked.stdout.trimmingCharacters(in: .newlines))）")
            let english = call(appLink, ["meetings", "show", "nothing"] + dir, language: "en")
            check(english.status == 4 && !english.stderr.isEmpty && english.stderr.range(of: "[ぁ-んァ-ヶ]", options: .regularExpression) == nil,
                  "シンボリックリンクから起動しても、表示の言語に訳す（\(english.stderr.split(separator: "\n").first ?? "")）")
        } catch {
            check(false, "テスト用の .app を作れない: \(error)")
        }

        // 書き換えない（REQ-COM-183）
        check(fingerprints(base) == before, "どのコマンドも meeting.json を書き換えない（処理中の会議も「失敗」にしない）")

        // 管理者のポリシー（REQ-COM-184）
        HanasuPolicy.testValues = [HanasuPolicy.Key.disableCLI.rawValue: true]
        let policyCode = runSync { await HanasuCommand.run(["meetings", "list", "--meetings-dir", base.path]) }
        check(policyCode == .denied, "DisableCLI のポリシーがあれば 5")
        HanasuPolicy.testValues = [HanasuPolicy.Key.disableCLI.rawValue: false]
        check(!HanasuPolicy.cliDisabled, "DisableCLI が false なら使える")
        HanasuPolicy.testValues = nil

        // 索引を作らない検索（DEC-MTG-123）は、アプリの索引の検索と同じ結果になる
        let samples = MeetingSearchCLI.sampleMeetings() + ((try? MeetingStore.loadAll(in: base)) ?? [])
        let index = MeetingSearchIndex()
        let sameResults = runSync {
            await index.update(samples)
            var same = true
            for query in ["予算", "資料 確認", "ＡＢＣ", "abc", "の", "田中", "ひみつ", "見つからない語"] {
                let indexed = await index.search(query)
                if indexed != MeetingSearchIndex.scan(samples, query: query) { same = false }
            }
            return same
        }
        check(sameResults, "索引を作らない検索は、アプリの索引の検索と同じ結果（架空の会議 \(samples.count) 件）")

        // 期間の読み取り
        let now = date("2026-11-08 12:00")
        let sevenDays = try? HanasuPeriod.parse("7d", option: "--since", endOfDay: false, now: now)
        check(sevenDays == now.addingTimeInterval(-7 * 86400), "7d は 7 日前")
        let untilDay = try? HanasuPeriod.parse("2026-11-05", option: "--until", endOfDay: true, now: now)
        check(untilDay == date("2026-11-06 00:00"), "--until の日付は翌日の 0 時より前")

        print(failures == 0 ? "すべて OK" : "NG が \(failures) 件")
        exit(failures == 0 ? 0 : 1)
    }

    private static func runSync<T: Sendable>(_ body: @escaping @Sendable () async -> T) -> T {
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: T?
        Task.detached {
            result = await body()
            semaphore.signal()
        }
        semaphore.wait()
        return result!
    }

    // MARK: - 速さ

    /// 1 時間ほどの会議（発言 600・議事録 3,000 字）を count 件作り、コマンドの時間を測る（目安は 2 秒以内。docs/plans/cli.md の 4.4）
    static func runBenchmark(count: Int) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("hanasu-command-bench-\(UUID().uuidString)", isDirectory: true)
        let base = root.appendingPathComponent("Meetings", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let start = date("2024-01-01 09:00")
        let sentence = "今日は来期の計画について、予算と人員の配分を中心に話し合いを進めたいと思います"
        let minutes = (0..<60).map { "- 議事録の行 \($0)：\(sentence)" }.joined(separator: "\n")
        print("\(count) 件の会議を作っています…")
        for i in 0..<count {
            let at = start.addingTimeInterval(Double(i) * 86400 / 3)
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd HHmm"
            var meeting = Meeting(id: f.string(from: at) + " \(i)", title: "会議 \(i)", startedAt: at)
            meeting.status = .done
            meeting.duration = 3600
            meeting.minutes = minutes
            meeting.actionItems = [ActionItem(owner: "田中", task: "資料をまとめる \(i)")]
            meeting.utterances = (0..<600).map { (n: Int) -> Utterance in
                let speaker: String = n % 3 == 0 ? "me" : "spk\(n % 3)"
                let at = Double(n) * 6
                return Utterance(speaker: speaker, start: at, end: at + 5, text: "\(sentence) \(n)")
            }
            if i == count / 2 { meeting.utterances[10].text = "めずらしいことばオルトラン" }
            try? write(meeting, to: base)
        }
        let size = (fm.enumerator(at: base, includingPropertiesForKeys: [.fileSizeKey])?.allObjects as? [URL] ?? [])
            .compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }.reduce(0, +)
        print(String(format: "合計 %.0f MB", Double(size) / 1_000_000))
        let dir = ["--meetings-dir", base.path]
        // 索引を作らない検索（DEC-MTG-123）と、アプリの索引の検索の結果と時間を比べる
        let loaded = (try? MeetingStore.loadAll(in: base)) ?? []
        let index = MeetingSearchIndex()
        for query in ["オルトラン", "予算 人員"] {
            let started = Date()
            let indexed = runSync { await index.update(loaded); return await index.search(query) }
            let indexTime = Date().timeIntervalSince(started)
            let scanStarted = Date()
            let scanned = MeetingSearchIndex.scan(loaded, query: query)
            print(String(format: "検索「%@」: 索引 %.2f 秒（作る時間を含む）、索引なし %.2f 秒、結果は%@", query, indexTime,
                         Date().timeIntervalSince(scanStarted), indexed == scanned ? "同じ" : "違う（NG）"))
        }
        for arguments in [["meetings", "list", "--json"], ["meetings", "list", "--limit", "10"],
                          ["meetings", "show", "latest", "--all", "--json"], ["meetings", "search", "オルトラン", "--json"],
                          ["actions", "--json"]] {
            let started = Date()
            let result = call(executable, arguments + dir)
            print(String(format: "%5.2f 秒  終了コード %d  %@", Date().timeIntervalSince(started), result.status, arguments.joined(separator: " ")))
        }
        exit(0)
    }
}
