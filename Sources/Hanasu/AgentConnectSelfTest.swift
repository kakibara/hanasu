import Foundation

// 「AI アプリにつなぐ」の自己テスト（.build/debug/Hanasu --test-hanasu-command の中で動く）。
// 共有のテストデータ common/testdata/connect/cases.json（Windows の AgentConnectTests と同じもの）と、
// ファイルの書き方（写し・権限・シンボリックリンク）・行の集め方・claude の呼び方を確かめる。
// 確かめ方: REQ-COM-194
// 設計判断: DEC-COM-200, DEC-COM-201, DEC-COM-202, DEC-COM-203, DEC-COM-204, DEC-COM-205
enum AgentConnectSelfTest {
    static var casesFile: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("common/testdata/connect/cases.json")
    }

    static func run(root: URL, check: (Bool, String) -> Void) {
        runSharedCases(check: check)
        runFileTests(root: root, check: check)
        runRowTests(root: root, check: check)
        runClaudeCLITests(root: root, check: check)
    }

    // MARK: - 共有のテストデータ

    static func runSharedCases(check: (Bool, String) -> Void) {
        guard let data = try? Data(contentsOf: casesFile),
              let doc = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cases = doc["cases"] as? [[String: Any]] else {
            check(false, "共有のテストデータを読めない（\(casesFile.path)。リポジトリのフォルダで動かす）")
            return
        }
        var failed: [String] = []
        for item in cases {
            let name = item["name"] as? String ?? "?"
            let expect = item["expect"] as? [String: Any] ?? [:]
            let windows = item["windows"] as? Bool ?? false
            let executable = item["executable"] as? String ?? ""
            switch item["kind"] as? String {
            case "owner":
                let owner = AgentConnect.owner(of: item["command"] as? String ?? "", executable: executable, windows: windows)
                if owner.rawValue != expect["owner"] as? String { failed.append("\(name): \(owner.rawValue)") }
            case "dataDir":
                let dir = AgentConnect.userDataDirectory(arguments: item["arguments"] as? [String] ?? [])
                if dir != expect["dataDir"] as? String { failed.append("\(name): \(dir ?? "nil")") }
            case "json", "toml":
                let isJSON = item["kind"] as? String == "json"
                let before = item["before"] as? String
                let state = isJSON
                    ? AgentConnect.ConfigJSON.state(before, executable: executable, windows: windows)
                    : AgentConnect.ConfigTOML.state(before, executable: executable, windows: windows)
                if let expected = expect["stateBefore"] as? String, state.code != expected {
                    failed.append("\(name): 状態 \(state.code)")
                    continue
                }
                if let projectEntry = expect["projectEntry"] as? Bool, AgentConnect.ConfigJSON.hasProjectEntry(before) != projectEntry {
                    failed.append("\(name): projectEntry")
                }
                let overwrite = item["overwrite"] as? Bool ?? false
                let edit: AgentConnect.Edit
                switch item["action"] as? String {
                case "connect":
                    edit = isJSON
                        ? AgentConnect.ConfigJSON.connect(before, executable: executable, windows: windows, overwrite: overwrite)
                        : AgentConnect.ConfigTOML.connect(before, executable: executable, windows: windows, overwrite: overwrite)
                case "disconnect":
                    edit = isJSON
                        ? AgentConnect.ConfigJSON.disconnect(before, executable: executable, windows: windows)
                        : AgentConnect.ConfigTOML.disconnect(before, executable: executable, windows: windows)
                default:
                    continue
                }
                if let result = expect["result"] as? String, edit.code != result {
                    failed.append("\(name): 結果 \(edit.code)")
                    continue
                }
                guard case .written(let after) = edit else { continue }
                if isJSON {
                    let actual = try? JSONSerialization.jsonObject(with: Data(after.utf8))
                    if !jsonEqual(actual, expect["after"]) { failed.append("\(name): 中身 \(after)") }
                } else if after != expect["after"] as? String {
                    failed.append("\(name): 中身 \(after.debugDescription)")
                }
                if let stateAfter = expect["stateAfter"] as? String {
                    let again = isJSON
                        ? AgentConnect.ConfigJSON.state(after, executable: executable, windows: windows)
                        : AgentConnect.ConfigTOML.state(after, executable: executable, windows: windows)
                    if again.code != stateAfter { failed.append("\(name): 書いたあとの状態 \(again.code)") }
                }
            default:
                failed.append("\(name): 知らない kind")
            }
        }
        check(failed.isEmpty, "共有のテストデータ（\(cases.count) 件）の決まりどおり" + (failed.isEmpty ? "" : "\n      " + failed.joined(separator: "\n      ")))
    }

    private static func jsonEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case (let l as [String: Any], let r as [String: Any]):
            return l.count == r.count && l.allSatisfy { jsonEqual($0.value, r[$0.key]) }
        case (let l as [Any], let r as [Any]):
            return l.count == r.count && zip(l, r).allSatisfy { jsonEqual($0, $1) }
        case (let l as NSNumber, let r as NSNumber): return l == r
        case (let l as String, let r as String): return l == r
        case (is NSNull, is NSNull): return true
        default: return false
        }
    }

    // MARK: - ファイルの書き方

    static func runFileTests(root: URL, check: (Bool, String) -> Void) {
        let fm = FileManager.default
        let dir = root.appendingPathComponent("connect-files", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        // 権限を保ち、元と同じ権限の写しを残す
        let file = dir.appendingPathComponent("config.toml")
        try? Data("a = 1\n".utf8).write(to: file)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let wrote = (try? AgentConnect.write("a = 2\n", to: file)) != nil
        let backup = dir.appendingPathComponent("config.toml" + AgentConnect.backupSuffix)
        func mode(_ url: URL) -> Int { ((try? fm.attributesOfItem(atPath: url.path))?[.posixPermissions] as? NSNumber)?.intValue ?? -1 }
        check(wrote && (try? String(contentsOf: file, encoding: .utf8)) == "a = 2\n"
              && (try? String(contentsOf: backup, encoding: .utf8)) == "a = 1\n"
              && mode(file) == 0o600 && mode(backup) == 0o600,
              "書く前の写しを残し、本体と写しの権限は元の 0600 のまま")

        // シンボリックリンクは残し、リンク先を書き換える
        let real = dir.appendingPathComponent("dotfiles/real.toml")
        try? fm.createDirectory(at: real.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data("b = 1\n".utf8).write(to: real)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: real.path)
        let link = dir.appendingPathComponent("link.toml")
        try? fm.createSymbolicLink(at: link, withDestinationURL: real)
        let linked = (try? AgentConnect.write("b = 2\n", to: link)) != nil
        let isLink = (try? fm.destinationOfSymbolicLink(atPath: link.path)) != nil
        check(linked && isLink && (try? String(contentsOf: real, encoding: .utf8)) == "b = 2\n" && mode(real) == 0o600,
              "設定ファイルがシンボリックリンクなら、リンクを残してリンク先を書き換える（権限も保つ）")

        // 行き先のないシンボリックリンクは、普通のファイルで置き換えずに失敗する
        let dangling = dir.appendingPathComponent("dangling.toml")
        try? fm.createSymbolicLink(atPath: dangling.path, withDestinationPath: dir.appendingPathComponent("nowhere/real.toml").path)
        let refused = (try? AgentConnect.write("c = 1\n", to: dangling)) == nil
        check(refused && (try? fm.destinationOfSymbolicLink(atPath: dangling.path)) != nil,
              "行き先のないシンボリックリンクは書かず、リンクを残す")

        // BOM 付きのファイルは、読んで書き戻しても BOM が残る（config.toml を 1 バイトも変えない）
        let bomFile = dir.appendingPathComponent("bom.toml")
        try? Data([0xEF, 0xBB, 0xBF] + Array("model = \"x\"\n".utf8)).write(to: bomFile)
        if case .success(let text) = AgentConnect.read(bomFile),
           case .written(let added) = AgentConnect.ConfigTOML.connect(text, executable: "/Applications/Hanasu.app/Contents/MacOS/Hanasu", windows: false, overwrite: false),
           (try? AgentConnect.write(added, to: bomFile)) != nil,
           case .success(let again) = AgentConnect.read(bomFile),
           case .written(let removed) = AgentConnect.ConfigTOML.disconnect(again, executable: "/Applications/Hanasu.app/Contents/MacOS/Hanasu", windows: false),
           (try? AgentConnect.write(removed, to: bomFile)) != nil {
            check((try? Data(contentsOf: bomFile)) == Data([0xEF, 0xBB, 0xBF] + Array("model = \"x\"\n".utf8)),
                  "BOM 付きの config.toml は、つないで外すと元のバイトに戻る")
        } else {
            check(false, "BOM 付きの config.toml は、つないで外すと元のバイトに戻る")
        }

        // 新しく作るファイルは 0600
        let fresh = dir.appendingPathComponent("new/claude_desktop_config.json")
        let created = (try? AgentConnect.write("{}\n", to: fresh)) != nil
        check(created && mode(fresh) == 0o600, "新しく作る設定ファイルは本人だけが読める（0600）")
    }

    // MARK: - 行を集める

    static func fakeEnvironment(home: URL, desktopArguments: [[String]?] = [], chatGPTRunning: Bool = false,
                                claudeRunning: Bool = false, installed: Set<String> = [], claude: String? = nil,
                                runClaude: @escaping (String, [String], TimeInterval) -> AgentConnect.ProcessOutput = { _, _, _ in .init(status: 0, stdout: "", stderr: "") })
        -> AgentConnect.Environment {
        AgentConnect.Environment(
            home: home,
            applicationSupport: home.appendingPathComponent("Library/Application Support", isDirectory: true),
            claudeDesktopArguments: { desktopArguments },
            isChatGPTRunning: { chatGPTRunning },
            isClaudeCodeRunning: { claudeRunning },
            isInstalled: { installed.contains($0) },
            findClaude: { claude },
            runClaude: runClaude)
    }

    static func runRowTests(root: URL, check: (Bool, String) -> Void) {
        let fm = FileManager.default
        let exe = "/Applications/Hanasu.app/Contents/MacOS/Hanasu"
        let home = root.appendingPathComponent("connect-home", isDirectory: true)
        let support = home.appendingPathComponent("Library/Application Support", isDirectory: true)

        // 何もないとき: Claude Desktop と ChatGPT は見つからない。Claude Code は押せる
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        var rows = AgentConnect.rows(env: fakeEnvironment(home: home), executable: exe)
        check(rows.count == 3 && !rows[0].found && !rows[1].found && rows[2].found && rows[2].claudePath == nil,
              "アプリが見つからなければ Claude Desktop と ChatGPT は押せない。Claude Code は claude がなくても押せる（DEC-COM-205）")

        // Claude Desktop の場所ごとの行。deploymentMode のあるものは出さない
        for (name, text) in [("Claude", "{\"preferences\": {}}"), ("Claude-Personal", "{}"), ("Claude-3p", "{\"deploymentMode\": \"1p\"}"), ("Claude-Empty", nil)] {
            let dir = support.appendingPathComponent(name, isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            if let text { try? Data(text.utf8).write(to: dir.appendingPathComponent("claude_desktop_config.json")) }
        }
        let personal = support.appendingPathComponent("Claude-Personal").path
        rows = AgentConnect.rows(env: fakeEnvironment(home: home, desktopArguments: [["/Applications/Claude.app/Contents/MacOS/Claude"]]), executable: exe)
        let desktop = rows.compactMap { row -> (String, Bool)? in
            if case .claudeDesktop(let dir) = row.target { return (dir.lastPathComponent, row.running) }
            return nil
        }
        check(desktop.map(\.0) == ["Claude", "Claude-Personal"] && desktop.map(\.1) == [true, false],
              "Claude Desktop は場所ごとの行（Claude-3p と設定のない場所は出さない）。引数なしで動いているのは既定の Claude（DEC-COM-200・202）")
        rows = AgentConnect.rows(env: fakeEnvironment(home: home, desktopArguments: [["Claude", "--user-data-dir=\(personal)"]]), executable: exe)
        check(rows.prefix(2).map(\.running) == [false, true], "--user-data-dir で動いている場所だけを、動いているとする")
        rows = AgentConnect.rows(env: fakeEnvironment(home: home, desktopArguments: [nil]), executable: exe)
        check(rows.prefix(2).allSatisfy(\.running), "引数を読めない Claude Desktop があれば、どの場所も動いているとする")

        // つなぐ・外す（動いていれば書かない）
        let row = rows[0]
        check(AgentConnect.connect(row, env: fakeEnvironment(home: home, desktopArguments: [nil]), executable: exe, overwrite: false) == .running,
              "Claude Desktop が動いていれば書かない（DEC-COM-202）")
        let env = fakeEnvironment(home: home)
        let connected = AgentConnect.connect(row, env: env, executable: exe, overwrite: false)
        rows = AgentConnect.rows(env: env, executable: exe)
        let text = (try? String(contentsOf: row.file, encoding: .utf8)) ?? ""
        check(connected == .done && rows[0].state == .connected && text.contains("\"preferences\""),
              "Claude Desktop につなぐと、ほかのキーを残して hanasu を足す")
        check(AgentConnect.disconnect(rows[0], env: env, executable: exe) == .done
              && AgentConnect.rows(env: env, executable: exe)[0].state == .notConnected, "外すと、つないでいない状態に戻る")

        // ChatGPT（Codex）: 動いていれば書かない。~/.codex があれば見つかる
        let codexDir = home.appendingPathComponent(".codex", isDirectory: true)
        try? fm.createDirectory(at: codexDir, withIntermediateDirectories: true)
        rows = AgentConnect.rows(env: fakeEnvironment(home: home, chatGPTRunning: true), executable: exe)
        let codex = rows.first { $0.target == .codex }!
        check(codex.found && codex.running
              && AgentConnect.connect(codex, env: fakeEnvironment(home: home, chatGPTRunning: true), executable: exe, overwrite: false) == .running,
              "ChatGPT（Codex）のアプリが動いていれば config.toml に書かない")
        check(AgentConnect.connect(codex, env: env, executable: exe, overwrite: false) == .done
              && AgentConnect.ConfigTOML.state(try? String(contentsOf: codex.file, encoding: .utf8), executable: exe, windows: false) == .connected,
              "ChatGPT（Codex）につなぐと config.toml に Hanasu の表ができる")

        // Claude Code（claude がない）: ~/.claude.json に直接書く。claude が動いていれば書かない
        let code = AgentConnect.rows(env: env, executable: exe).first { $0.target == .claudeCode }!
        check(AgentConnect.connect(code, env: fakeEnvironment(home: home, claudeRunning: true), executable: exe, overwrite: false) == .running,
              "claude がなく、Claude Code のプロセスが動いていれば ~/.claude.json に書かない")
        check(AgentConnect.connect(code, env: env, executable: exe, overwrite: false) == .done
              && AgentConnect.rows(env: env, executable: exe).first { $0.target == .claudeCode }?.state == .connected,
              "claude がなければ ~/.claude.json の mcpServers に直接書く（Claude Code を入れる前につなげる）")
    }

    // MARK: - claude の呼び方

    static func runClaudeCLITests(root: URL, check: (Bool, String) -> Void) {
        let fm = FileManager.default
        let exe = "/Applications/Hanasu.app/Contents/MacOS/Hanasu"
        let old = "/Users/me/Downloads/Hanasu.app/Contents/MacOS/Hanasu"
        let home = root.appendingPathComponent("connect-cli", isDirectory: true)
        try? fm.createDirectory(at: home, withIntermediateDirectories: true)
        let claudeJSON = home.appendingPathComponent(".claude.json")

        /// 本物の claude と同じく、同じ名前があれば add は失敗し、なければ remove は失敗する偽物
        final class FakeClaude: @unchecked Sendable {
            var calls: [[String]] = []
            var failAdd = false
            var hang = false
            let file: URL
            init(file: URL) { self.file = file }
            func run(_ claude: String, _ arguments: [String], _ timeout: TimeInterval) -> AgentConnect.ProcessOutput {
                calls.append(arguments)
                if hang { return .init(status: -1, stdout: "", stderr: "", timedOut: true) }
                var root = (try? JSONSerialization.jsonObject(with: Data(contentsOf: file))) as? [String: Any] ?? [:]
                var servers = root["mcpServers"] as? [String: Any] ?? [:]
                switch arguments.prefix(2).joined(separator: " ") {
                case "mcp add":
                    if servers["hanasu"] != nil { return .init(status: 1, stdout: "", stderr: "MCP server hanasu already exists in user config") }
                    if failAdd { return .init(status: 1, stdout: "", stderr: "boom") }
                    servers["hanasu"] = ["command": arguments[arguments.count - 2], "args": ["mcp"]]
                case "mcp add-json":
                    servers["hanasu"] = try? JSONSerialization.jsonObject(with: Data(arguments.last!.utf8))
                case "mcp remove":
                    if servers["hanasu"] == nil { return .init(status: 1, stdout: "", stderr: "No user-scoped MCP server found with name: hanasu") }
                    servers.removeValue(forKey: "hanasu")
                default: break
                }
                root["mcpServers"] = servers
                try? JSONSerialization.data(withJSONObject: root).write(to: file)
                return .init(status: 0, stdout: "", stderr: "")
            }
        }
        let fake = FakeClaude(file: claudeJSON)
        let env = fakeEnvironment(home: home, claudeRunning: true, claude: "/fake/claude", runClaude: fake.run)
        func row() -> AgentConnect.Row { AgentConnect.rows(env: env, executable: exe).first { $0.target == .claudeCode }! }

        check(!AgentConnect.isRunning(row(), env: env), "claude に任せる Claude Code の行は、Claude Code が動いていても書ける")
        // つなぐ（claude があれば、Claude Code が動いていても claude に任せる）
        check(AgentConnect.connect(row(), env: env, executable: exe, overwrite: false) == .done
              && fake.calls.last == ["mcp", "add", "--scope", "user", "hanasu", "--", exe, "mcp"] && row().state == .connected,
              "claude があれば claude mcp add --scope user で登録する")

        // 別の場所の Hanasu: remove してから add
        try? Data("{\"mcpServers\": {\"hanasu\": {\"command\": \"\(old)\", \"args\": [\"mcp\"]}}}".utf8).write(to: claudeJSON)
        fake.calls = []
        check(row().state == .other(old) && AgentConnect.connect(row(), env: env, executable: exe, overwrite: false) == .done
              && fake.calls.map { $0.prefix(2).joined(separator: " ") } == ["mcp remove", "mcp add"] && row().state == .connected,
              "別の場所の Hanasu は、外してから足す（claude mcp add は同じ名前があると失敗する）")

        // Hanasu のものでない: 確かめる。add が失敗したら前の項目を入れ直す
        try? Data("{\"mcpServers\": {\"hanasu\": {\"command\": \"npx\", \"args\": [\"x\"]}}}".utf8).write(to: claudeJSON)
        check(AgentConnect.connect(row(), env: env, executable: exe, overwrite: false) == .needsOverwrite("npx"),
              "Hanasu のものでない hanasu は、置き換えてよいか確かめる")
        fake.failAdd = true
        let failed = AgentConnect.connect(row(), env: env, executable: exe, overwrite: true)
        check(failed == .failed("boom") && row().state == .foreign("npx"), "足すのに失敗したら、前の項目を元どおりに入れ直す")
        fake.failAdd = false

        // 前の項目がオブジェクトでない（null）とき、足すのに失敗しても落ちない
        try? Data("{\"mcpServers\": {\"hanasu\": null}}".utf8).write(to: claudeJSON)
        fake.failAdd = true
        check(AgentConnect.connect(row(), env: env, executable: exe, overwrite: true) == .failed("boom"),
              "前の hanasu が null でも、足すのに失敗したときに落ちない（入れ直しは、オブジェクトのときだけ）")
        fake.failAdd = false

        // 打ち切り
        fake.hang = true
        check(AgentConnect.connect(row(), env: env, executable: exe, overwrite: true) == .timedOut, "claude が終わらなければ打ち切ったことを返す")
        fake.hang = false

        // 外す
        try? Data("{\"mcpServers\": {\"hanasu\": {\"command\": \"\(exe)\", \"args\": [\"mcp\"]}}, \"projects\": {\"/x\": {\"mcpServers\": {\"hanasu\": {}}}}}".utf8).write(to: claudeJSON)
        check(row().projectEntry && AgentConnect.disconnect(row(), env: env, executable: exe) == .done && row().state == .notConnected,
              "claude mcp remove で外す。フォルダだけの登録があることを見分ける")
        check(AgentConnect.disconnect(row(), env: env, executable: exe) == .nothing, "つないでいなければ外すものがない（claude を動かさない）")

        // 本物の runProcess の打ち切り
        let slow = AgentConnect.runProcess("/bin/sleep", ["5"], timeout: 0.5, path: nil)
        check(slow.timedOut, "子プロセスが時間内に終わらなければ打ち切る")
    }
}

// 確認用の CLI モード（実機で「AI アプリにつなぐ」を確かめる。設定画面のボタンと同じ処理で、本物の設定ファイルを書き換える）:
//   Hanasu --agent-connect-list                         行（番号・名前・設定ファイル・状態・見つかったか・動いているか）を出す
//   Hanasu --agent-connect <番号> connect|disconnect [--overwrite]
// 要件: REQ-COM-194
enum AgentConnectCLI {
    static func runIfRequested() {
        let args = CommandLine.arguments
        if args.contains("--agent-connect-list") {
            list()
            exit(0)
        }
        guard let index = args.firstIndex(of: "--agent-connect"), args.indices.contains(index + 2),
              let number = Int(args[index + 1]) else { return }
        let env = AgentConnect.Environment.live
        let rows = AgentConnect.rows(env: env, executable: HanasuInstall.executablePath)
        guard rows.indices.contains(number) else {
            FileHandle.standardError.write(Data("error: 行の番号は 0〜\(rows.count - 1)\n".utf8))
            exit(1)
        }
        let row = rows[number]
        let outcome: AgentConnect.Outcome = switch args[index + 2] {
        case "connect": AgentConnect.connect(row, env: env, executable: HanasuInstall.executablePath, overwrite: args.contains("--overwrite"))
        case "disconnect": AgentConnect.disconnect(row, env: env, executable: HanasuInstall.executablePath)
        default: .failed("connect か disconnect")
        }
        print("\(outcome)")
        list()
        exit(outcome == .done || outcome == .unchanged || outcome == .nothing ? 0 : 1)
    }

    private static func list() {
        let rows = AgentConnect.rows(env: .live, executable: HanasuInstall.executablePath)
        for (number, row) in rows.enumerated() {
            print("\(number)\t\(row.target)\t\(row.file.path)\t\(row.state)\tfound=\(row.found)\trunning=\(row.running)\tclaude=\(row.claudePath ?? "-")\tprojectEntry=\(row.projectEntry)")
        }
    }
}
