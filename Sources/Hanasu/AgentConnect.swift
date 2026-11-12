import AppKit
import Darwin
import Foundation

// 設定の「AI アプリにつなぐ」の中身（計画は docs/plans/agent-connect.md）。
// Claude Desktop・ChatGPT（Codex）・Claude Code の設定に、hanasu の MCP のサーバーを足す・外す。
// 決まり（見分け方・JSON と TOML の書き換え）を変えるときは、Windows 版 windows/Hanasu.Core/Command/AgentConnect.cs も直す
// （共有のテストデータ common/testdata/connect/cases.json で比べる）。画面は CommandLineSettingsView.swift の AgentConnectSection。

// 要件: REQ-COM-194
enum AgentConnect {
    // MARK: - 状態と結果

    /// 設定ファイルを書き換えられない理由
    enum Problem: Error, Equatable {
        case invalidJSON
        case unexpectedShape
        case tomlUnsupported
        case io(String)

        /// 共有のテストデータでの名前
        var code: String {
            switch self {
            case .invalidJSON: "invalidJSON"
            case .unexpectedShape: "unexpectedShape"
            case .tomlUnsupported: "tomlUnsupported"
            case .io: "io"
            }
        }
    }

    /// 登録の状態。other・foreign は、今の登録の command
    enum State: Equatable {
        case connected
        case notConnected
        case other(String)
        case foreign(String)
        case unreadable(Problem)

        var code: String {
            switch self {
            case .connected: "connected"
            case .notConnected: "notConnected"
            case .other: "other"
            case .foreign: "foreign"
            case .unreadable(let problem): "unreadable:\(problem.code)"
            }
        }

        /// 外せる Hanasu の項目があるか
        var removable: Bool {
            switch self {
            case .connected, .other: true
            default: false
            }
        }
    }

    /// 書き換えの結果（ファイルの中身だけを扱う。書くのは呼んだ側）
    enum Edit: Equatable {
        case written(String)
        case unchanged
        case needsOverwrite
        case unreadable(Problem)
        case nothing

        var code: String {
            switch self {
            case .written: "written"
            case .unchanged: "unchanged"
            case .needsOverwrite: "needsOverwrite"
            case .unreadable: "unreadable"
            case .nothing: "nothing"
            }
        }
    }

    // MARK: - Hanasu の項目の見分け方

    enum Owner: String {
        case current, other, foreign
    }

    // 設計判断: DEC-COM-203
    /// Hanasu の実行ファイルの形か（Mac は Hanasu.app の中の実行ファイル、Windows は cli\hanasu.exe）
    static func isHanasuExecutable(_ path: String, windows: Bool) -> Bool {
        if windows {
            return path.replacingOccurrences(of: "/", with: "\\").lowercased().hasSuffix("\\cli\\hanasu.exe")
        }
        return path.hasSuffix("/Hanasu.app/Contents/MacOS/Hanasu")
    }

    /// 登録の command が、このアプリ・別の場所の Hanasu・Hanasu のものでない、のどれか。
    /// resolve は、シンボリックリンク（PATH に入れた hanasu など）をたどる
    static func owner(of command: String, executable: String, windows: Bool,
                      resolve: (String) -> String = { $0 }) -> Owner {
        func normalized(_ path: String) -> String {
            let resolved = resolve(path)
            return windows ? resolved.replacingOccurrences(of: "/", with: "\\").lowercased() : resolved
        }
        let target = normalized(command)
        if target == normalized(executable) { return .current }
        return isHanasuExecutable(target, windows: windows) ? .other : .foreign
    }

    /// 絶対パスだけ、シンボリックリンクをたどる（素の hanasu は PATH で探すので、Hanasu のものとは見なさない）
    static func resolveLink(_ path: String) -> String {
        guard path.hasPrefix("/") else { return path }
        return URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    // MARK: - Claude Desktop の起動の引数

    // 設計判断: DEC-COM-202
    /// 起動の引数の --user-data-dir（なければ nil = 既定の場所）
    static func userDataDirectory(arguments: [String]) -> String? {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument.hasPrefix("--user-data-dir=") {
                return unquote(String(argument.dropFirst("--user-data-dir=".count)))
            }
            if argument == "--user-data-dir", index + 1 < arguments.count {
                return unquote(arguments[index + 1])
            }
            index += 1
        }
        return nil
    }

    private static func unquote(_ text: String) -> String {
        if text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") { return String(text.dropFirst().dropLast()) }
        return text
    }

    // MARK: - JSON（claude_desktop_config.json と ~/.claude.json）

    // 設計判断: DEC-COM-200, DEC-COM-204
    enum ConfigJSON {
        static func parse(_ text: String?) -> Result<[String: Any], Problem> {
            // 先頭の BOM は読み飛ばす（書くときは付けない）
            let text = text.map { $0.unicodeScalars.first == "\u{FEFF}" ? String($0.unicodeScalars.dropFirst()) : $0 }
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .success([:]) }
            guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed]) else {
                return .failure(.invalidJSON)
            }
            guard let root = object as? [String: Any] else { return .failure(.unexpectedShape) }
            if let servers = root["mcpServers"], !(servers is [String: Any]) { return .failure(.unexpectedShape) }
            return .success(root)
        }

        static func state(_ text: String?, executable: String, windows: Bool,
                          resolve: (String) -> String = { $0 }) -> State {
            switch parse(text) {
            case .failure(let problem): return .unreadable(problem)
            case .success(let root): return state(root: root, executable: executable, windows: windows, resolve: resolve)
            }
        }

        private static func state(root: [String: Any], executable: String, windows: Bool, resolve: (String) -> String) -> State {
            guard let entry = (root["mcpServers"] as? [String: Any])?["hanasu"] else { return .notConnected }
            guard let command = (entry as? [String: Any])?["command"] as? String else { return .foreign("?") }
            switch owner(of: command, executable: executable, windows: windows, resolve: resolve) {
            case .current: return .connected
            case .other: return .other(command)
            case .foreign: return .foreign(command)
            }
        }

        static func connect(_ text: String?, executable: String, windows: Bool, overwrite: Bool,
                            resolve: (String) -> String = { $0 }) -> Edit {
            var root: [String: Any]
            switch parse(text) {
            case .failure(let problem): return .unreadable(problem)
            case .success(let value): root = value
            }
            var servers = root["mcpServers"] as? [String: Any] ?? [:]
            var entry: [String: Any]
            switch state(root: root, executable: executable, windows: windows, resolve: resolve) {
            case .connected: return .unchanged
            case .foreign:
                guard overwrite else { return .needsOverwrite }
                entry = [:]
            case .other:
                // 利用者が足したキー（env など）は残す
                entry = servers["hanasu"] as? [String: Any] ?? [:]
            default:
                entry = [:]
            }
            entry["command"] = executable
            entry["args"] = ["mcp"]
            servers["hanasu"] = entry
            root["mcpServers"] = servers
            return .written(render(root))
        }

        static func disconnect(_ text: String?, executable: String, windows: Bool,
                               resolve: (String) -> String = { $0 }) -> Edit {
            switch parse(text) {
            case .failure(let problem): return .unreadable(problem)
            case .success(var root):
                guard state(root: root, executable: executable, windows: windows, resolve: resolve).removable else { return .nothing }
                var servers = root["mcpServers"] as? [String: Any] ?? [:]
                servers.removeValue(forKey: "hanasu")
                root["mcpServers"] = servers
                return .written(render(root))
            }
        }

        /// ~/.claude.json の projects の中に、そのフォルダだけの hanasu の登録があるか（DEC-COM-204）
        static func hasProjectEntry(_ text: String?) -> Bool {
            guard case .success(let root) = parse(text), let projects = root["projects"] as? [String: Any] else { return false }
            return projects.values.contains { (($0 as? [String: Any])?["mcpServers"] as? [String: Any])?["hanasu"] != nil }
        }

        static func render(_ root: [String: Any]) -> String {
            let data = (try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
            return String(decoding: data, as: UTF8.self) + "\n"
        }
    }

    // MARK: - TOML（~/.codex/config.toml）

    // 設計判断: DEC-COM-201
    /// TOML を全部は読まず、[mcp_servers.hanasu] の表だけを行で扱う
    enum ConfigTOML {
        static let marker = "# Added by Hanasu"

        private enum Kind {
            case blank, comment, header([String]), arrayHeader([String]), key([String]), continuation
        }

        private struct Scan {
            var raw: [String]          // 改行（\n）を除いた行。\r は残す
            var kinds: [Kind]
            var depthAfter: [Int]      // その行のあとに閉じていない [ と { の数
            var trailingNewline: Bool
            var crlf: Bool
            var unsupported: Bool
            /// 先頭に BOM（U+FEFF）があったか（書くときも付ける）
            var bom = false

            func content(_ index: Int) -> String {
                let line = raw[index]
                return line.hasSuffix("\r") ? String(line.dropLast()) : line
            }
        }

        private struct Table {
            var path: [String]
            var header: Int
            var end: Int  // 次の見出しの行（なければ行の数）
        }

        private static func scan(_ text: String?) -> Scan {
            var text = text ?? ""
            let bom = text.unicodeScalars.first == "\u{FEFF}"
            if bom { text.unicodeScalars.removeFirst() }
            var raw = text.components(separatedBy: "\n")
            // hasSuffix("\n") は、CRLF（\r\n を 1 つの文字として扱う）で終わる文字列では false になるので、バイトで見る
            let trailingNewline = text.utf8.last == UInt8(ascii: "\n")
            if trailingNewline || text.isEmpty { raw.removeLast() }
            var result = Scan(raw: raw, kinds: [], depthAfter: [], trailingNewline: trailingNewline,
                              crlf: text.contains("\r\n"), unsupported: text.contains("\"\"\"") || text.contains("'''"),
                              bom: bom)
            var depth = 0
            var table: [String] = []
            for index in raw.indices {
                let content = result.content(index)
                let trimmed = content.trimmingCharacters(in: .whitespaces)
                if depth > 0 {
                    depth += bracketDelta(content)
                    result.kinds.append(.continuation)
                } else if trimmed.isEmpty {
                    result.kinds.append(.blank)
                } else if trimmed.hasPrefix("#") {
                    result.kinds.append(.comment)
                } else if trimmed.hasPrefix("[[") {
                    let path = headerPath(trimmed, array: true) ?? []
                    if path.first == "mcp_servers" || path.isEmpty { result.unsupported = true }
                    result.kinds.append(.arrayHeader(path))
                    table = path
                } else if trimmed.hasPrefix("[") {
                    guard let path = headerPath(trimmed, array: false) else {
                        result.unsupported = true
                        result.kinds.append(.header([]))
                        continue
                    }
                    result.kinds.append(.header(path))
                    table = path
                } else {
                    let (key, value) = splitKey(content)
                    let path = key.map(keyPath) ?? []
                    // mcp_servers を見出し以外で作っているファイルは扱わない
                    if (table.isEmpty && path.first == "mcp_servers") || table == ["mcp_servers"] { result.unsupported = true }
                    result.kinds.append(.key(path))
                    depth = max(0, bracketDelta(value ?? ""))
                }
                result.depthAfter.append(depth)
            }
            return result
        }

        /// [ a . "b" ] # コメント → ["a", "b"]。形が崩れていれば nil
        private static func headerPath(_ trimmed: String, array: Bool) -> [String]? {
            let open = array ? 2 : 1
            var inner = ""
            var quote: Character?
            var closed = false
            var rest = Substring(trimmed.dropFirst(open))
            while let character = rest.first {
                rest = rest.dropFirst()
                if let q = quote {
                    inner.append(character)
                    if character == "\\", q == "\"", let next = rest.first {
                        inner.append(next)
                        rest = rest.dropFirst()
                    } else if character == q {
                        quote = nil
                    }
                } else if character == "\"" || character == "'" {
                    quote = character
                    inner.append(character)
                } else if character == "]" {
                    if array {
                        guard rest.first == "]" else { return nil }
                        rest = rest.dropFirst()
                    }
                    closed = true
                    break
                } else {
                    inner.append(character)
                }
            }
            guard closed else { return nil }
            let after = rest.trimmingCharacters(in: .whitespaces)
            guard after.isEmpty || after.hasPrefix("#") else { return nil }
            let path = keyPath(inner)
            return path.contains(where: \.isEmpty) ? nil : path
        }

        /// a . "b.c" . 'd' → ["a", "b.c", "d"]
        private static func keyPath(_ key: String) -> [String] {
            var parts: [String] = []
            var current = ""
            var quote: Character?
            var quoted = false
            var iterator = key.makeIterator()
            while let character = iterator.next() {
                if let q = quote {
                    if character == "\\", q == "\"", let next = iterator.next() {
                        current.append(next == "\"" ? "\"" : next == "\\" ? "\\" : next)
                    } else if character == q {
                        quote = nil
                    } else {
                        current.append(character)
                    }
                } else if character == "\"" || character == "'" {
                    quote = character
                    quoted = true
                    current = current.trimmingCharacters(in: .whitespaces)
                } else if character == "." {
                    parts.append(quoted ? current : current.trimmingCharacters(in: .whitespaces))
                    current = ""
                    quoted = false
                } else if !(character == " " || character == "\t") || !quoted {
                    current.append(character)
                }
            }
            parts.append(quoted ? current : current.trimmingCharacters(in: .whitespaces))
            return parts
        }

        /// key = value の、引用の外の最初の = で分ける
        private static func splitKey(_ line: String) -> (key: String?, value: String?) {
            var quote: Character?
            for (offset, character) in line.enumerated() {
                if let q = quote {
                    if character == q { quote = nil }
                } else if character == "\"" || character == "'" {
                    quote = character
                } else if character == "=" {
                    let index = line.index(line.startIndex, offsetBy: offset)
                    return (String(line[..<index]), String(line[line.index(after: index)...]))
                }
            }
            return (nil, nil)
        }

        /// 文字列とコメントの外の [ { と ] } の差
        private static func bracketDelta(_ text: String) -> Int {
            var depth = 0
            var quote: Character?
            var escaped = false
            for character in text {
                if let q = quote {
                    if escaped { escaped = false }
                    else if character == "\\", q == "\"" { escaped = true }
                    else if character == q { quote = nil }
                } else if character == "\"" || character == "'" {
                    quote = character
                } else if character == "#" {
                    break
                } else if character == "[" || character == "{" {
                    depth += 1
                } else if character == "]" || character == "}" {
                    depth -= 1
                }
            }
            return depth
        }

        private static func tables(_ scan: Scan) -> [Table] {
            var result: [Table] = []
            for (index, kind) in scan.kinds.enumerated() {
                switch kind {
                case .header(let path), .arrayHeader(let path):
                    if !result.isEmpty { result[result.count - 1].end = index }
                    result.append(Table(path: path, header: index, end: scan.raw.count))
                default: break
                }
            }
            return result
        }

        private static func isHanasu(_ path: [String]) -> Bool {
            path.count >= 2 && path[0] == "mcp_servers" && path[1] == "hanasu"
        }

        /// Hanasu の表の見出し・command の行・args の行と、command の値。扱えなければ nil
        private struct HanasuTable {
            var table: Table
            var commandLine: Int?
            var argsLine: Int?
            var command: String?
        }

        private static func hanasuTable(_ scan: Scan) -> (found: HanasuTable?, supported: Bool) {
            let all = tables(scan)
            let mains = all.filter { $0.path == ["mcp_servers", "hanasu"] }
            if scan.unsupported || mains.count > 1 { return (nil, false) }
            guard let main = mains.first else {
                // 下の表だけがある（hanasu の表を暗に作っている）ものは扱わない
                return (nil, !all.contains { isHanasu($0.path) })
            }
            var found = HanasuTable(table: main)
            for index in (main.header + 1)..<main.end {
                guard case .key(let path) = scan.kinds[index] else { continue }
                if path == ["command"] {
                    if scan.depthAfter[index] > 0 { return (nil, false) }
                    found.commandLine = index
                    found.command = parseString(splitKey(scan.content(index)).value ?? "")
                } else if path == ["args"] {
                    if scan.depthAfter[index] > 0 { return (nil, false) }
                    found.argsLine = index
                }
            }
            return (found, true)
        }

        /// TOML の 1 行の文字列（基本・リテラル）を読む。後ろのコメントは許す
        static func parseString(_ value: String) -> String? {
            let text = value.trimmingCharacters(in: .whitespaces)
            guard let first = text.first, first == "\"" || first == "'" else { return nil }
            var result = ""
            var iterator = text.dropFirst().makeIterator()
            while let character = iterator.next() {
                if character == first {
                    var tail = ""
                    while let rest = iterator.next() { tail.append(rest) }
                    let trimmed = tail.trimmingCharacters(in: .whitespaces)
                    return trimmed.isEmpty || trimmed.hasPrefix("#") ? result : nil
                }
                if first == "\"", character == "\\" {
                    guard let escape = iterator.next() else { return nil }
                    switch escape {
                    case "\\": result.append("\\")
                    case "\"": result.append("\"")
                    case "b": result.append("\u{08}")
                    case "t": result.append("\t")
                    case "n": result.append("\n")
                    case "f": result.append("\u{0C}")
                    case "r": result.append("\r")
                    case "u", "U":
                        var hex = ""
                        for _ in 0..<(escape == "u" ? 4 : 8) { if let h = iterator.next() { hex.append(h) } }
                        guard let value = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(value) else { return nil }
                        result.unicodeScalars.append(scalar)
                    default: return nil
                    }
                } else {
                    result.append(character)
                }
            }
            return nil
        }

        /// TOML の基本文字列（"…"）にする
        static func quote(_ text: String) -> String {
            var result = "\""
            for scalar in text.unicodeScalars {
                switch scalar {
                case "\\": result += "\\\\"
                case "\"": result += "\\\""
                case "\u{08}": result += "\\b"
                case "\t": result += "\\t"
                case "\n": result += "\\n"
                case "\u{0C}": result += "\\f"
                case "\r": result += "\\r"
                default:
                    if scalar.value < 0x20 || scalar.value == 0x7F {
                        result += String(format: "\\u%04X", scalar.value)
                    } else {
                        result.unicodeScalars.append(scalar)
                    }
                }
            }
            return result + "\""
        }

        static func state(_ text: String?, executable: String, windows: Bool,
                          resolve: (String) -> String = { $0 }) -> State {
            let scan = scan(text)
            let (found, supported) = hanasuTable(scan)
            guard supported else { return .unreadable(.tomlUnsupported) }
            guard let found else { return .notConnected }
            guard let command = found.command else { return .foreign("?") }
            switch owner(of: command, executable: executable, windows: windows, resolve: resolve) {
            case .current: return .connected
            case .other: return .other(command)
            case .foreign: return .foreign(command)
            }
        }

        static func connect(_ text: String?, executable: String, windows: Bool, overwrite: Bool,
                            resolve: (String) -> String = { $0 }) -> Edit {
            var scan = scan(text)
            switch state(text, executable: executable, windows: windows, resolve: resolve) {
            case .unreadable(let problem): return .unreadable(problem)
            case .connected: return .unchanged
            case .foreign:
                guard overwrite else { return .needsOverwrite }
                removeHanasu(&scan)
                return .written(append(scan, executable: executable))
            case .notConnected:
                return .written(append(scan, executable: executable))
            case .other:
                guard let found = hanasuTable(scan).found else { return .unreadable(.tomlUnsupported) }
                let end = scan.crlf ? "\r" : ""
                /// 書き換える行は、元の行の終わり（\r があるか）と字下げを保つ
                func line(_ text: String, replacing index: Int) -> String {
                    let content = scan.content(index)
                    let indent = String(content.prefix { $0 == " " || $0 == "\t" })
                    return indent + text + (scan.raw[index].hasSuffix("\r") ? "\r" : "")
                }
                let command = "command = \(quote(executable))"
                let args = "args = [\"mcp\"]"
                if let commandLine = found.commandLine {
                    scan.raw[commandLine] = line(command, replacing: commandLine)
                    if let argsLine = found.argsLine {
                        scan.raw[argsLine] = line(args, replacing: argsLine)
                    } else {
                        let indent = String(scan.content(commandLine).prefix { $0 == " " || $0 == "\t" })
                        insert(&scan, [indent + args + end], at: commandLine + 1)
                    }
                } else {
                    insert(&scan, [command + end, args + end], at: found.table.header + 1)
                }
                return .written(join(scan))
            }
        }

        static func disconnect(_ text: String?, executable: String, windows: Bool,
                               resolve: (String) -> String = { $0 }) -> Edit {
            var scan = scan(text)
            let state = state(text, executable: executable, windows: windows, resolve: resolve)
            if case .unreadable(let problem) = state { return .unreadable(problem) }
            guard state.removable else { return .nothing }
            removeHanasu(&scan)
            return .written(join(scan))
        }

        /// Hanasu の表（下の表も）を消す。表の見出しから最後のキーの行まで（後ろの空行と、次の表の前のコメントは残す）。
        /// 印の行は表と一緒に消す。ファイルの終わりまで消したら前の空行を 1 つ、前が空行（かファイルの始め）で後ろも空行なら後ろの空行を 1 つ消す
        private static func removeHanasu(_ scan: inout Scan) {
            var regions: [ClosedRange<Int>] = []
            for table in tables(scan) where isHanasu(table.path) {
                var last = table.header
                for index in table.header..<table.end {
                    switch scan.kinds[index] {
                    case .blank, .comment: continue
                    default: last = index
                    }
                }
                var start = table.header
                if table.path.count == 2, start > 0, scan.content(start - 1).trimmingCharacters(in: .whitespaces) == marker {
                    start -= 1
                }
                regions.append(start...last)
            }
            var lines = scan.raw
            func blank(_ index: Int) -> Bool { lines[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            for region in regions.sorted(by: { $0.lowerBound > $1.lowerBound }) {
                lines.removeSubrange(region)
                let start = region.lowerBound
                if start >= lines.count {
                    if start > 0, blank(start - 1) { lines.remove(at: start - 1) }
                } else if (start == 0 || blank(start - 1)), blank(start) {
                    lines.remove(at: start)
                }
            }
            scan.raw = lines
        }

        /// 行を足す。ファイルの終わり（改行のない最後の行のあと）に足すときは、最後の行を改行で終える
        private static func insert(_ scan: inout Scan, _ lines: [String], at index: Int) {
            if index >= scan.raw.count, !scan.trailingNewline, let last = scan.raw.last {
                if scan.crlf, !last.hasSuffix("\r") { scan.raw[scan.raw.count - 1] = last + "\r" }
                scan.trailingNewline = true
            }
            scan.raw.insert(contentsOf: lines, at: min(index, scan.raw.count))
        }

        private static func append(_ scan: Scan, executable: String) -> String {
            var scan = scan
            let end = scan.crlf ? "\r" : ""
            if scan.crlf, !scan.trailingNewline, let last = scan.raw.last, !last.hasSuffix("\r") {
                scan.raw[scan.raw.count - 1] = last + "\r"
            }
            if let last = scan.raw.last, !last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                scan.raw.append(end)
            }
            for line in [marker, "[mcp_servers.hanasu]", "command = \(quote(executable))", "args = [\"mcp\"]", "tool_timeout_sec = 300"] {
                scan.raw.append(line + end)
            }
            scan.trailingNewline = true
            return join(scan)
        }

        private static func join(_ scan: Scan) -> String {
            let body = scan.raw.isEmpty ? "" : scan.raw.joined(separator: "\n") + (scan.trailingNewline ? "\n" : "")
            return (scan.bom ? "\u{FEFF}" : "") + body
        }
    }

    // MARK: - ファイルを読み書きする

    /// 設定ファイルを読む。なければ nil
    static func read(_ file: URL) -> Result<String?, Problem> {
        let real = file.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: real.path) else { return .success(nil) }
        do {
            let data = try Data(contentsOf: real)
            // String(data:encoding:) は先頭の BOM を消すので、残す（config.toml を 1 バイトも変えずに書き戻すため。Windows 版と同じ）
            let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
            let hasBOM = data.starts(with: bom)
            guard let text = String(data: hasBOM ? data.dropFirst(3) : data, encoding: .utf8) else { return .failure(.io("UTF-8")) }
            return .success(hasBOM ? "\u{FEFF}" + text : text)
        } catch {
            return .failure(.io(error.localizedDescription))
        }
    }

    static let backupSuffix = ".hanasu-backup"

    /// 書く前の写しを元と同じ権限で残し、一時ファイルに書いて置き換え、本体の権限をそろえ、読み直して確かめる。
    /// シンボリックリンクなら、リンクは残してリンク先を書き換える
    static func write(_ text: String, to file: URL) throws {
        let fm = FileManager.default
        let real = file.resolvingSymlinksInPath()
        // 行き先のないシンボリックリンクは、たどれずに同じパスが返る。リンクを普通のファイルで置き換えないよう、書かない
        if (try? fm.destinationOfSymbolicLink(atPath: file.path)) != nil, !fm.fileExists(atPath: real.path) {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: real.path])
        }
        var permissions = mode_t(0o600)
        let backup = real.deletingLastPathComponent().appendingPathComponent(real.lastPathComponent + backupSuffix)
        let existed = fm.fileExists(atPath: real.path)
        if existed {
            if let mode = (try? fm.attributesOfItem(atPath: real.path))?[.posixPermissions] as? NSNumber {
                permissions = mode_t(mode.uint16Value)
            }
            try? fm.removeItem(at: backup)
            try fm.copyItem(at: real, to: backup)
        } else {
            try fm.createDirectory(at: real.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        // 一時ファイルは、はじめから元の権限（新しいファイルは 0600。ほかのサーバーの鍵が入りうる）で作り、置き換える
        let temp = real.deletingLastPathComponent().appendingPathComponent(".\(real.lastPathComponent).\(UUID().uuidString).tmp")
        let descriptor = open(temp.path, O_WRONLY | O_CREAT | O_EXCL, permissions)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let data = Data(text.utf8)
        let written = data.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, data.count) }
        fchmod(descriptor, permissions)
        fsync(descriptor)
        close(descriptor)
        guard written == data.count, rename(temp.path, real.path) == 0 else {
            let code = POSIXErrorCode(rawValue: errno) ?? .EIO
            try? fm.removeItem(at: temp)
            throw POSIXError(code)
        }
        let back = (try? Data(contentsOf: real)) ?? Data()
        if back != data {
            try? fm.removeItem(at: real)
            if existed { try? fm.copyItem(at: backup, to: real) }
            throw CocoaError(.fileWriteUnknown)
        }
    }

    // MARK: - 行（画面の 1 行）

    enum Target: Hashable {
        /// Claude Desktop の設定の場所（~/Library/Application Support/Claude など）
        case claudeDesktop(URL)
        case codex
        case claudeCode
    }

    struct Row: Identifiable {
        var target: Target
        /// 書く設定ファイル
        var file: URL
        /// アプリ（か設定の場所）が見つかったか（DEC-COM-205）
        var found: Bool
        /// 動いていて書けないか（DEC-COM-202）
        var running: Bool
        var state: State
        /// Claude Code の claude の場所（なければ ~/.claude.json に直接書く）
        var claudePath: String?
        /// ~/.claude.json にフォルダだけの登録もあるか
        var projectEntry = false

        var id: Target { target }
        var isDefaultClaude: Bool {
            if case .claudeDesktop(let dir) = target { return dir.lastPathComponent == "Claude" }
            return false
        }
    }

    /// 結果（画面で文にする）
    enum Outcome: Equatable {
        case done
        case unchanged
        case nothing
        case needsOverwrite(String)
        case running
        case unreadable(Problem)
        case failed(String)
        case timedOut
    }

    // MARK: - 環境（テストと画面の描画で差し替える）

    struct ProcessOutput: Equatable {
        var status: Int32
        var stdout: String
        var stderr: String
        var timedOut = false
    }

    struct Environment {
        var home: URL
        /// ~/Library/Application Support
        var applicationSupport: URL
        /// 動いている Claude Desktop の起動の引数（読めなければ nil）
        var claudeDesktopArguments: () -> [[String]?]
        var isChatGPTRunning: () -> Bool
        var isClaudeCodeRunning: () -> Bool
        /// バンドル ID のアプリが入っているか
        var isInstalled: (String) -> Bool
        var findClaude: () -> String?
        /// claude を動かす（バックグラウンドで呼ぶ）
        var runClaude: (_ claude: String, _ arguments: [String], _ timeout: TimeInterval) -> ProcessOutput

        static let claudeDesktopBundleID = "com.anthropic.claudefordesktop"
        static let chatGPTBundleIDs = ["com.openai.codex", "com.openai.chat"]

        static var live: Environment {
            let home = FileManager.default.homeDirectoryForCurrentUser
            return Environment(
                home: home,
                applicationSupport: home.appendingPathComponent("Library/Application Support", isDirectory: true),
                claudeDesktopArguments: {
                    NSRunningApplication.runningApplications(withBundleIdentifier: claudeDesktopBundleID)
                        .map { processArguments($0.processIdentifier) }
                },
                isChatGPTRunning: {
                    chatGPTBundleIDs.contains { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }
                },
                isClaudeCodeRunning: { isProcessRunning(named: "claude") },
                isInstalled: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil },
                findClaude: { ClaudeCLI.find(home: home) },
                runClaude: { claude, arguments, timeout in ClaudeCLI.run(claude, arguments, timeout: timeout, home: home) }
            )
        }
    }

    // MARK: - 行を集める

    /// 画面に出す行（Claude Desktop は設定の場所ごと）
    static func rows(env: Environment, executable: String) -> [Row] {
        let resolve: (String) -> String = resolveLink
        var rows: [Row] = []

        // Claude Desktop（DEC-COM-200・202・205）
        let running = runningClaudeDirectories(env)
        var locations = claudeDesktopLocations(env.applicationSupport)
        let installed = env.isInstalled(Environment.claudeDesktopBundleID)
        if locations.isEmpty { locations = [env.applicationSupport.appendingPathComponent("Claude", isDirectory: true)] }
        for dir in locations {
            let file = dir.appendingPathComponent("claude_desktop_config.json")
            let found = installed || FileManager.default.fileExists(atPath: dir.path)
            let state: State = switch read(file) {
            case .failure(let problem): .unreadable(problem)
            case .success(let text): ConfigJSON.state(text, executable: executable, windows: false, resolve: resolve)
            }
            let isRunning = running.all || running.directories.contains(dir.standardizedFileURL.path)
            rows.append(Row(target: .claudeDesktop(dir), file: file, found: found, running: isRunning, state: state))
        }

        // ChatGPT（Codex）
        let codexDir = env.home.appendingPathComponent(".codex", isDirectory: true)
        let codexFile = codexDir.appendingPathComponent("config.toml")
        let codexFound = FileManager.default.fileExists(atPath: codexDir.path)
            || Environment.chatGPTBundleIDs.contains(where: env.isInstalled)
        let codexState: State = switch read(codexFile) {
        case .failure(let problem): .unreadable(problem)
        case .success(let text): ConfigTOML.state(text, executable: executable, windows: false, resolve: resolve)
        }
        rows.append(Row(target: .codex, file: codexFile, found: codexFound, running: env.isChatGPTRunning(), state: codexState))

        // Claude Code（DEC-COM-204）
        let claudeFile = env.home.appendingPathComponent(".claude.json")
        let claude = env.findClaude()
        var projectEntry = false
        let codeState: State
        switch read(claudeFile) {
        case .failure(let problem): codeState = .unreadable(problem)
        case .success(let text):
            codeState = ConfigJSON.state(text, executable: executable, windows: false, resolve: resolve)
            projectEntry = ConfigJSON.hasProjectEntry(text)
        }
        // claude があれば Claude Code が書くので、動いていても構わない
        let codeRunning = claude == nil && env.isClaudeCodeRunning()
        rows.append(Row(target: .claudeCode, file: claudeFile, found: true, running: codeRunning, state: codeState,
                        claudePath: claude, projectEntry: projectEntry))
        return rows
    }

    // 設計判断: DEC-COM-200
    /// Claude と Claude- で始まるフォルダ（Claude 以外は設定ファイルのあるもの。deploymentMode のあるものは除く）
    static func claudeDesktopLocations(_ applicationSupport: URL) -> [URL] {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: applicationSupport.path)) ?? []
        let others = names.filter { $0.hasPrefix("Claude-") }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let ordered: [String] = (names.contains("Claude") ? ["Claude"] : []) + others
        return ordered.compactMap { name -> URL? in
            let dir = applicationSupport.appendingPathComponent(name, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
            let file = dir.appendingPathComponent("claude_desktop_config.json")
            if !fm.fileExists(atPath: file.path) { return name == "Claude" ? dir : nil }
            if case .success(let text) = read(file), case .success(let root) = ConfigJSON.parse(text), root["deploymentMode"] != nil {
                return nil
            }
            return dir
        }
    }

    // 設計判断: DEC-COM-202
    /// 動いている Claude Desktop が使っている設定の場所。引数を読めないものがあれば all
    static func runningClaudeDirectories(_ env: Environment) -> (all: Bool, directories: Set<String>) {
        var directories: Set<String> = []
        for arguments in env.claudeDesktopArguments() {
            guard let arguments else { return (true, []) }
            let path = userDataDirectory(arguments: arguments)
                ?? env.applicationSupport.appendingPathComponent("Claude", isDirectory: true).path
            directories.insert(URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path)
        }
        return (false, directories)
    }

    // MARK: - つなぐ・外す

    /// 確かめのあとで呼ぶ（バックグラウンドで）。overwrite は、Hanasu のものでない hanasu を置き換えてよいか
    static func connect(_ row: Row, env: Environment, executable: String, overwrite: Bool) -> Outcome {
        if case .claudeCode = row.target, let claude = row.claudePath {
            return ClaudeCLI.connect(claude: claude, file: row.file, env: env, executable: executable, overwrite: overwrite)
        }
        return change(row, env: env) { text in
            switch row.target {
            case .codex: ConfigTOML.connect(text, executable: executable, windows: false, overwrite: overwrite, resolve: resolveLink)
            default: ConfigJSON.connect(text, executable: executable, windows: false, overwrite: overwrite, resolve: resolveLink)
            }
        }
    }

    static func disconnect(_ row: Row, env: Environment, executable: String) -> Outcome {
        if case .claudeCode = row.target, let claude = row.claudePath {
            return ClaudeCLI.disconnect(claude: claude, file: row.file, env: env, executable: executable)
        }
        return change(row, env: env) { text in
            switch row.target {
            case .codex: ConfigTOML.disconnect(text, executable: executable, windows: false, resolve: resolveLink)
            default: ConfigJSON.disconnect(text, executable: executable, windows: false, resolve: resolveLink)
            }
        }
    }

    /// 今そのアプリが動いていて書けないか（押したときに確かめ直す）。Claude Code は claude に任せるときは見ない
    static func isRunning(_ row: Row, env: Environment) -> Bool {
        switch row.target {
        case .claudeDesktop(let dir):
            let running = runningClaudeDirectories(env)
            return running.all || running.directories.contains(dir.standardizedFileURL.path)
        case .codex: return env.isChatGPTRunning()
        case .claudeCode: return row.claudePath == nil && env.isClaudeCodeRunning()
        }
    }

    private static func change(_ row: Row, env: Environment, edit: (String?) -> Edit) -> Outcome {
        // 押したときにもう一度確かめる（画面を開いたあとで起動したかもしれない）
        if isRunning(row, env: env) { return .running }
        let text: String?
        switch read(row.file) {
        case .failure(let problem): return .unreadable(problem)
        case .success(let value): text = value
        }
        switch edit(text) {
        case .written(let newText):
            do {
                try write(newText, to: row.file)
                return .done
            } catch {
                return .failed(error.localizedDescription)
            }
        case .unchanged: return .unchanged
        case .nothing: return .nothing
        case .unreadable(let problem): return .unreadable(problem)
        case .needsOverwrite:
            if case .foreign(let command) = ConfigJSON.state(text, executable: "", windows: false) { return .needsOverwrite(command) }
            if case .foreign(let command) = ConfigTOML.state(text, executable: "", windows: false) { return .needsOverwrite(command) }
            return .needsOverwrite("?")
        }
    }

    // MARK: - Claude Code の claude

    // 設計判断: DEC-COM-204
    enum ClaudeCLI {
        static let timeout: TimeInterval = 30

        static func connect(claude: String, file: URL, env: Environment, executable: String, overwrite: Bool) -> Outcome {
            let text: String?
            switch read(file) {
            case .failure(let problem): return .unreadable(problem)
            case .success(let value): text = value
            }
            var root: [String: Any] = [:]
            if case .success(let value) = ConfigJSON.parse(text) { root = value }
            let entry = (root["mcpServers"] as? [String: Any])?["hanasu"]
            // 入れ直せるのはオブジェクトのときだけ（null や文字列を JSONSerialization に渡すと落ちる）
            let previous = entry as? [String: Any]
            switch ConfigJSON.state(text, executable: executable, windows: false, resolve: resolveLink) {
            case .connected: return .unchanged
            case .foreign(let command) where !overwrite: return .needsOverwrite(command)
            case .unreadable(let problem): return .unreadable(problem)
            default: break
            }
            // 全部で 30 秒まで（remove・add・入れ直しの合計）
            let deadline = Date().addingTimeInterval(timeout)
            func remaining() -> TimeInterval { max(1, deadline.timeIntervalSinceNow) }
            // claude mcp add は同じ名前があると失敗するので、先に外す
            if entry != nil {
                let removed = env.runClaude(claude, ["mcp", "remove", "--scope", "user", "hanasu"], remaining())
                if removed.timedOut { return .timedOut }
                if removed.status != 0 { return .failed(message(removed)) }
            }
            let added = env.runClaude(claude, ["mcp", "add", "--scope", "user", "hanasu", "--", executable, "mcp"], remaining())
            if added.status == 0, !added.timedOut { return .done }
            var reasons = added.timedOut ? [] : [message(added)]
            // 足せなかったら、前の項目を入れ直す。入れ直せなかったら、そのことも出す
            if let previous, let data = try? JSONSerialization.data(withJSONObject: previous, options: [.withoutEscapingSlashes]) {
                let restored = env.runClaude(claude, ["mcp", "add-json", "--scope", "user", "hanasu", String(decoding: data, as: UTF8.self)], remaining())
                if restored.timedOut { reasons.append("claude mcp add-json: timeout") }
                else if restored.status != 0 { reasons.append("claude mcp add-json: " + message(restored)) }
            }
            if added.timedOut, reasons.isEmpty { return .timedOut }
            return .failed(reasons.joined(separator: "\n"))
        }

        static func disconnect(claude: String, file: URL, env: Environment, executable: String) -> Outcome {
            let text: String?
            switch read(file) {
            case .failure(let problem): return .unreadable(problem)
            case .success(let value): text = value
            }
            guard ConfigJSON.state(text, executable: executable, windows: false, resolve: resolveLink).removable else { return .nothing }
            let removed = env.runClaude(claude, ["mcp", "remove", "--scope", "user", "hanasu"], timeout)
            if removed.timedOut { return .timedOut }
            return removed.status == 0 ? .done : .failed(message(removed))
        }

        private static func message(_ output: ProcessOutput) -> String {
            let text = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? output.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : text
        }

        /// claude を探す。よくある場所、Claude Desktop に入っているもの、ログインシェルの順
        static func find(home: URL) -> String? {
            let fm = FileManager.default
            let fixed = [
                home.appendingPathComponent(".local/bin/claude").path,
                "/opt/homebrew/bin/claude",
                "/usr/local/bin/claude",
                home.appendingPathComponent(".claude/local/claude").path,
            ]
            if let path = fixed.first(where: { fm.isExecutableFile(atPath: $0) }) { return path }
            if let bundled = bundled(home: home) { return bundled }
            let output = runProcess(HanasuInstall.loginShellPath, ["-l", "-c", "command -v claude"], timeout: 5, path: nil)
            let line = output.stdout.split(separator: "\n").map(String.init).last { $0.hasPrefix("/") }
            if let line, !output.timedOut, fm.isExecutableFile(atPath: line) { return line }
            return nil
        }

        /// Claude Desktop に入っている Claude Code（いちばん新しい版）
        static func bundled(home: URL) -> String? {
            let fm = FileManager.default
            let root = home.appendingPathComponent("Library/Application Support/Claude/claude-code", isDirectory: true)
            let versions = ((try? fm.contentsOfDirectory(atPath: root.path)) ?? [])
                .filter { $0.first?.isNumber == true }
                .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            for version in versions {
                let dir = root.appendingPathComponent(version, isDirectory: true)
                for hash in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] {
                    let path = dir.appendingPathComponent(hash).appendingPathComponent("claude.app/Contents/MacOS/claude").path
                    if fm.isExecutableFile(atPath: path) { return path }
                }
            }
            return nil
        }

        /// 見つけた claude のフォルダを PATH の先に足して動かす（npm の claude は #!/usr/bin/env node なので、node を見つけられるように）
        /// 作業フォルダはホーム（Finder から開いたアプリは / で動くので、/ をプロジェクトとして記録させない）
        static func run(_ claude: String, _ arguments: [String], timeout: TimeInterval, home: URL) -> ProcessOutput {
            let dir = URL(fileURLWithPath: claude).deletingLastPathComponent().path
            let resolvedDir = URL(fileURLWithPath: claude).resolvingSymlinksInPath().deletingLastPathComponent().path
            return runProcess(claude, arguments, timeout: timeout,
                              path: [dir, resolvedDir, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"].joined(separator: ":"),
                              directory: home)
        }
    }

    /// 子プロセスを動かし、timeout 秒で打ち切る
    static func runProcess(_ executable: String, _ arguments: [String], timeout: TimeInterval, path: String?,
                           directory: URL? = nil) -> ProcessOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let directory { process.currentDirectoryURL = directory }
        var environment = ProcessInfo.processInfo.environment
        if let path { environment["PATH"] = path }
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() } catch {
            return ProcessOutput(status: -1, stdout: "", stderr: error.localizedDescription)
        }
        // パイプがいっぱいで止まらないように、並べて読む
        /// 読み終えた出力（読むスレッドと取り出すスレッドがぶつからないよう、鍵をかける）
        final class Output: @unchecked Sendable {
            private let lock = NSLock()
            private var values: [Int: Data] = [:]
            func set(_ index: Int, _ data: Data) { lock.lock(); values[index] = data; lock.unlock() }
            func get(_ index: Int) -> Data { lock.lock(); defer { lock.unlock() }; return values[index] ?? Data() }
        }
        let output = Output()
        let group = DispatchGroup()
        for (index, pipe) in [out, err].enumerated() {
            group.enter()
            DispatchQueue.global().async { output.set(index, pipe.fileHandleForReading.readDataToEndOfFile()); group.leave() }
        }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = done.wait(timeout: .now() + 2)
            _ = group.wait(timeout: .now() + 2)
            return ProcessOutput(status: -1, stdout: "", stderr: "", timedOut: true)
        }
        // 孫プロセスがパイプを持ったままだと読み終わらない。そのときは、そこまでに読めた分だけを使う
        _ = group.wait(timeout: .now() + 5)
        return ProcessOutput(status: process.terminationStatus,
                             stdout: String(decoding: output.get(0), as: UTF8.self), stderr: String(decoding: output.get(1), as: UTF8.self))
    }

    // MARK: - プロセス

    /// プロセスの起動の引数（KERN_PROCARGS2）。読めなければ nil
    static func processArguments(_ pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        // 実行ファイルのパスと、その後ろの 0 を飛ばす
        while index < size, buffer[index] != 0 { index += 1 }
        while index < size, buffer[index] == 0 { index += 1 }
        var arguments: [String] = []
        while arguments.count < argc, index < size {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            arguments.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return arguments.count == Int(argc) ? arguments : nil
    }

    /// その名前のプロセスが動いているか（Claude Code の claude）
    static func isProcessRunning(named name: String) -> Bool {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return false }
        var pids = [pid_t](repeating: 0, count: Int(count) * 2)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard filled > 0 else { return false }
        var nameBuffer = [CChar](repeating: 0, count: 256)
        for pid in pids.prefix(Int(filled)) where pid > 0 {
            if proc_name(pid, &nameBuffer, UInt32(nameBuffer.count)) > 0, String(cString: nameBuffer) == name { return true }
        }
        return false
    }
}
