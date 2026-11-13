import Foundation

// 共有のテストデータ（common/testdata/cli）で、Mac と Windows の hanasu の出力をそろえる（計画は docs/plans/cli-windows.md の WD3）。
//   Hanasu --write-cli-golden   … cases.json のコマンドを動かし、expected.json を書く（リポジトリのルートで動かす）
//   Hanasu --test-hanasu-command の中で、expected.json と比べる
// Windows 版は windows/Hanasu.Core.Tests/CommandGoldenTests.cs が、同じ cases.json を動かして同じ expected.json と比べる。

// 確かめ方: REQ-COM-180, REQ-COM-181, REQ-MTG-120, REQ-MTG-121, REQ-MTG-123, REQ-MTG-124, REQ-MTG-126, REQ-MTG-127, REQ-DIC-160, REQ-DIC-161, REQ-DIC-162, REQ-DIC-023
// 設計判断: DEC-COM-192
enum HanasuGoldenCLI {
    static var directory: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("common/testdata/cli", isDirectory: true)
    }

    /// cases.json を動かす。write なら expected.json を書き、そうでなければ比べて、合わなかった件数を返す
    static func run(write: Bool, report: (Bool, String) -> Void) -> Int {
        let fm = FileManager.default
        guard let casesData = try? Data(contentsOf: directory.appendingPathComponent("cases.json")),
              let spec = try? JSONSerialization.jsonObject(with: casesData) as? [String: Any],
              let cases = spec["cases"] as? [[String: Any]] else {
            report(false, "共有のテストデータ（\(directory.path)/cases.json）を読めない（リポジトリのルートで動かす）")
            return 1
        }
        let settingsData = (try? Data(contentsOf: directory.appendingPathComponent("settings.json"))) ?? Data()
        let settings = (try? JSONSerialization.jsonObject(with: settingsData) as? [String: Any]) ?? [:]
        let ignoreKeys = Set(spec["ignoreKeys"] as? [String] ?? [])
        let replace = spec["replace"] as? [String: String] ?? [:]

        // 設定は使い捨ての suite に入れ、子プロセスに渡す（作った人の辞書や設定を混ぜない）
        let suiteName = "dev.mactypeless.Hanasu.golden-\(ProcessInfo.processInfo.processIdentifier)"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)
        // 配列（アプリ別の文体・カスタム文体）は、アプリが読む形（JSON のデータ）にして入れる
        for (key, value) in settings where !key.hasPrefix("_") {
            if value is [Any], let data = try? JSONSerialization.data(withJSONObject: value) {
                suite.set(data, forKey: key)
            } else {
                suite.set(value, forKey: key)
            }
        }
        suite.synchronize()
        defer { suite.removePersistentDomain(forName: suiteName) }

        // 偽の fm（--ai apple）。決めた答えを返すだけで、何も送らない
        let root = fm.temporaryDirectory.appendingPathComponent("hanasu-golden-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let fake = root.appendingPathComponent("fm")
        try? Data("#!/bin/sh\nprintf '%s\\n' \"$FAKE_FM_OUTPUT\"\n".utf8).write(to: fake)
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)

        let env: [String: String] = [
            "TZ": spec["timeZone"] as? String ?? "Asia/Tokyo",
            "HANASU_TEST_DEFAULTS_SUITE": suiteName,
            "HANASU_TEST_NOW": spec["now"] as? String ?? "",
            "HANASU_TEST_NONCE": spec["nonce"] as? String ?? "",
            "HANASU_MEETINGS_DIR": directory.appendingPathComponent("meetings").path,
            "HANASU_FM_PATH": fake.path, "FAKE_FM_OUTPUT": spec["fakeAnswer"] as? String ?? "",
            "ANTHROPIC_API_KEY": "", "GEMINI_API_KEY": "", "GEMINI_SERVICE_ACCOUNT_JSON": "",
        ]
        let expectedURL = directory.appendingPathComponent("expected.json")
        let expected = ((try? Data(contentsOf: expectedURL)).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
        var results: [String: Any] = [:]
        var failures = 0
        let exe = HanasuCommandCLI.executable

        for item in cases {
            guard let name = item["name"] as? String, let compare = item["compare"] as? String else { continue }
            var actual: [String: Any] = [:]
            if let call = item["mcp"] as? [String: Any] {
                let requests = [
                    ["jsonrpc": "2.0", "id": 1, "method": "initialize",
                     "params": ["protocolVersion": "2025-06-18", "capabilities": [:], "clientInfo": ["name": "golden", "version": "1"]]],
                    ["jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": call],
                ].map { String(decoding: try! JSONSerialization.data(withJSONObject: $0), as: UTF8.self) }.joined(separator: "\n") + "\n"
                let result = HanasuCommandCLI.call(exe, ["mcp"], environment: env, stdin: requests)
                let response = result.stdout.split(separator: "\n").compactMap {
                    try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
                }.first { ($0["id"] as? Int) == 2 }
                let toolResult = response?["result"] as? [String: Any] ?? [:]
                let isError = toolResult["isError"] as? Bool ?? true
                actual["isError"] = isError
                if compare == "mcp" {
                    let text = ((toolResult["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
                    actual["result"] = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) ?? text
                }
            } else {
                var args: [String] = []
                for arg in item["args"] as? [Any] ?? [] {
                    if let text = arg as? String { args.append(text) } else if let text = (arg as? [String: Any])?["mac"] as? String { args.append(text) }
                }
                if item["ai"] as? Bool == true { args += ["--ai", "apple"] }
                let result = HanasuCommandCLI.call(exe, args, environment: env)
                actual["exit"] = Int(result.status)
                if compare.contains("json") {
                    actual["json"] = (try? JSONSerialization.jsonObject(with: Data(result.stdout.utf8))) ?? NSNull()
                }
                if compare.contains("prompt") { actual["prompt"] = prompt(in: result.stderr) ?? NSNull() }
            }
            let normalized = normalize(actual, ignoreKeys: ignoreKeys, replace: replace)
            results[name] = normalized
            if !write {
                let same = canonical(normalized) == canonical(expected[name] ?? NSNull())
                report(same, "共有のテストデータの \(name) が、期待する出力（expected.json）と同じ")
                if !same { failures += 1 }
            }
        }
        if write {
            var object: [String: Any] = results
            object["_comment"] = "Hanasu --write-cli-golden が書いた期待する出力（手で直さない）。比べないキーと置き換えは cases.json の ignoreKeys・replace"
            if let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
                try? (data + Data("\n".utf8)).write(to: expectedURL)
                report(true, "expected.json を書いた（\(results.count) 件）")
            }
        }
        return failures
    }

    /// --show-prompt が stderr に出した、送る内容（system と user）
    static func prompt(in stderr: String) -> String? {
        guard let start = stderr.range(of: "----- system -----\n"),
              let end = stderr.range(of: "\n------------------", range: start.upperBound..<stderr.endIndex) else { return nil }
        return String(stderr[start.upperBound..<end.lowerBound])
    }

    /// 比べないキーを除き、OS で違う語を置き換え、文字を合成済みの形（NFC）にそろえる
    /// （Foundation の Process は、子プロセスに渡す引数を分解した形にするため）
    static func normalize(_ value: Any, ignoreKeys: Set<String>, replace: [String: String]) -> Any {
        switch value {
        case let object as [String: Any]:
            var result: [String: Any] = [:]
            for (key, item) in object where !ignoreKeys.contains(key) {
                result[key] = normalize(item, ignoreKeys: ignoreKeys, replace: replace)
            }
            return result
        case let array as [Any]:
            return array.map { normalize($0, ignoreKeys: ignoreKeys, replace: replace) }
        case let text as String:
            return replace.reduce(text) { $0.replacingOccurrences(of: $1.key, with: $1.value) }.precomposedStringWithCanonicalMapping
        default:
            return value
        }
    }

    static func canonical(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject([value]),
              let data = try? JSONSerialization.data(withJSONObject: [value], options: [.sortedKeys, .withoutEscapingSlashes]) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
