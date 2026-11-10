import Darwin
import Foundation

// 利用者向けの `hanasu mcp`（計画は docs/plans/cli.md の段階 3）。stdio の MCP サーバー。
// ツールの中身は HanasuMCPTools.swift。名前が CLI.swift で終わらないので、訳の検査の対象になる。

// 要件: REQ-COM-189
// 設計判断: DEC-COM-186
/// 改行で区切った JSON-RPC を stdin から読み、stdout（起動時に複製した番号）に書く。
/// MCP の 2026-07-28（server/discover と、リクエストごとの _meta の版）と、それより前の版（initialize）の両方に応える
final class HanasuMCPServer: @unchecked Sendable {
    static let modernVersion = "2026-07-28"
    /// initialize で取り決める版（新しい順）
    static let legacyVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
    static let versionKey = "io.modelcontextprotocol/protocolVersion"
    static let serverInfoKey = "io.modelcontextprotocol/serverInfo"
    /// tools/list の結果を使い回してよい時間（ask_meetings の説明は設定の AI で変わるので短め）
    static let toolsTTLMilliseconds = 60_000

    let tools: HanasuMCPTools
    private let output: FileHandle
    private let lock = NSLock()
    private var running: [String: Task<Void, Never>] = [:]

    init(tools: HanasuMCPTools, output: FileHandle) {
        self.tools = tools
        self.output = output
    }

    // MARK: - コマンド

    static func run(_ arguments: [String]) async throws -> HanasuExit {
        let args = try HanasuArguments.parse(
            arguments, flags: ["--help", "-h"], options: HanasuMeetingsCommand.commonOptions.union(HanasuAI.options))
        if args.flags.contains("--help") || args.flags.contains("-h") {
            HanasuOutput.out(HanasuHelp.section(for: "mcp") ?? HanasuHelp.full())
            return .ok
        }
        if let extra = args.positionals.first {
            throw HanasuTextInput.usage(tr("知らない引数です: %@", extra))
        }
        // 要件: REQ-COM-189
        if HanasuPolicy.mcpDisabled {
            throw HanasuCommandError(
                exit: .denied,
                message: tr("管理者のポリシーで、hanasu mcp は使えないようにされています（%@）。", HanasuPolicy.Key.disableMCP.rawValue))
        }
        // --ai に知らない名前があれば、ここで使い方の誤りにする（ask_meetings で初めて分かるのでは遅い）
        _ = try HanasuAI.choice(args, for: .meeting, settings: AppSettings.shared)

        // 設計判断: DEC-COM-186
        // 本当の stdout を複製し、1 番は stderr に付け替える。どこかのコードや子プロセスが stdout に書いても、接続を壊さない
        let saved = dup(STDOUT_FILENO)
        guard saved >= 0 else { throw HanasuCommandError(exit: .failure, message: String(cString: strerror(errno))) }
        dup2(STDERR_FILENO, STDOUT_FILENO)
        let server = HanasuMCPServer(
            tools: HanasuMCPTools(directory: HanasuMeetingsCommand.meetingsDirectory(args), aiArguments: args),
            output: FileHandle(fileDescriptor: saved, closeOnDealloc: false))
        HanasuOutput.err(tr("hanasu mcp: MCP サーバーとして動いています。標準入力が閉じると終わります。"))
        await server.serve(input: FileHandle.standardInput)
        return .ok
    }

    // MARK: - 読み書き

    /// stdin が閉じるまで 1 行ずつ処理し、処理中のリクエストが終わるのを待って返る。
    /// 行の区切りは \n だけ（U+2028 などで切らない）
    func serve(input: FileHandle) async {
        let lines = AsyncStream<Data> { continuation in
            Thread.detachNewThread {
                var buffer = Data()
                while true {
                    let chunk = input.availableData
                    if chunk.isEmpty { break }
                    buffer.append(chunk)
                    while let newline = buffer.firstIndex(of: 0x0A) {
                        continuation.yield(buffer[buffer.startIndex..<newline])
                        buffer.removeSubrange(buffer.startIndex...newline)
                    }
                }
                if !buffer.isEmpty { continuation.yield(buffer) }
                continuation.finish()
            }
        }
        for await line in lines { receive(Data(line)) }
        while let task = lock.withLock({ running.values.first }) { await task.value }
    }

    func receive(_ line: Data) {
        let trimmed = String(decoding: line, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let message = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) else {
            write(Self.error(id: NSNull(), code: -32700, message: "Parse error"))
            return
        }
        if let batch = message as? [Any] {
            // 2025-03-26 のまとめたリクエスト。1 つずつ処理して、応答を配列で返す
            guard !batch.isEmpty else {
                write(Self.error(id: NSNull(), code: -32600, message: "Invalid Request"))
                return
            }
            start("batch-\(UUID().uuidString)") {
                var responses: [Any] = []
                for item in batch {
                    if let response = await self.handle(item) { responses.append(response) }
                }
                if !responses.isEmpty { self.write(responses) }
            }
            return
        }
        guard let object = message as? [String: Any] else {
            write(Self.error(id: NSNull(), code: -32600, message: "Invalid Request"))
            return
        }
        // 取り消しは、処理中のリクエストを止めるだけで、応答は返さない
        if object["method"] as? String == "notifications/cancelled" {
            if let requestID = (object["params"] as? [String: Any])?["requestId"] {
                cancel(Self.key(for: requestID))
            }
            return
        }
        let key = object["id"].map(Self.key(for:)) ?? "notification-\(UUID().uuidString)"
        start(key) {
            let response = await self.handle(object)
            if !Task.isCancelled, let response { self.write(response) }
        }
    }

    /// 処理を始めて、終わるまで running に置く。登録はロックの中で行うので、Task の後片付け（ロックを待つ）は必ず登録のあとになる。
    /// 先に終わった Task が running に残ると、stdin が閉じたあとの待ちが終わらなくなる
    private func start(_ key: String, _ body: @escaping @Sendable () async -> Void) {
        lock.withLock {
            running[key] = Task {
                await body()
                self.lock.withLock { _ = self.running.removeValue(forKey: key) }
            }
        }
    }

    private func cancel(_ key: String) {
        lock.withLock { running.removeValue(forKey: key) }?.cancel()
    }

    private static func key(for id: Any) -> String { "id-\(id)" }

    /// 1 行に 1 つのメッセージ。U+2028・U+2029 も、行の区切りと取り違えられないよう \u の形にする
    func write(_ message: Any) {
        guard let data = try? JSONSerialization.data(withJSONObject: message, options: [.sortedKeys, .withoutEscapingSlashes]) else { return }
        var text = String(decoding: data, as: UTF8.self)
        text = text.replacingOccurrences(of: "\u{2028}", with: "\\u2028").replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        lock.withLock { output.write(Data((text + "\n").utf8)) }
    }

    // MARK: - メッセージ

    /// 応答（通知と、クライアントからの応答には nil）
    func handle(_ message: Any) async -> [String: Any]? {
        guard let object = message as? [String: Any] else {
            return Self.error(id: NSNull(), code: -32600, message: "Invalid Request")
        }
        let id = object["id"]
        guard let method = object["method"] as? String else {
            // クライアントからの応答（こちらからはリクエストを送らないので、捨てる）。id もなければ形の誤り
            return id == nil ? Self.error(id: NSNull(), code: -32600, message: "Invalid Request") : nil
        }
        let isNotification = id == nil
        func reply(_ result: [String: Any]) -> [String: Any]? {
            isNotification ? nil : ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result]
        }
        func fail(_ code: Int, _ text: String, data: Any? = nil) -> [String: Any]? {
            isNotification ? nil : Self.error(id: id ?? NSNull(), code: code, message: text, data: data)
        }

        let rawParams = object["params"]
        if let rawParams, !(rawParams is [String: Any]) { return fail(-32602, "Invalid params: params must be an object") }
        let params = rawParams as? [String: Any] ?? [:]
        // 2026-07-28: リクエストごとに _meta で版を名乗る
        let requested = (params["_meta"] as? [String: Any])?[Self.versionKey] as? String
        if let requested, requested != Self.modernVersion {
            return fail(-32022, "Unsupported protocol version",
                        data: ["supported": [Self.modernVersion], "requested": requested])
        }
        let modern = requested != nil
        func complete(_ result: [String: Any]) -> [String: Any]? {
            guard modern else { return reply(result) }
            var result = result
            result["resultType"] = "complete"
            var meta = result["_meta"] as? [String: Any] ?? [:]
            meta[Self.serverInfoKey] = Self.serverInfo
            result["_meta"] = meta
            return reply(result)
        }

        switch method {
        case "initialize":
            let asked = params["protocolVersion"] as? String ?? ""
            let version = Self.legacyVersions.contains(asked) ? asked : Self.legacyVersions[0]
            return reply([
                "protocolVersion": version,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": Self.serverInfo,
                "instructions": HanasuMCPTools.instructions,
            ])
        case "server/discover":
            return complete([
                "supportedVersions": [Self.modernVersion],
                "capabilities": ["tools": ["listChanged": false]],
                "instructions": HanasuMCPTools.instructions,
                "ttlMs": Self.toolsTTLMilliseconds,
                "cacheScope": "private",
            ])
        case "ping":
            return complete([:])
        case "tools/list":
            var result: [String: Any] = ["tools": tools.definitions()]
            if modern {
                result["ttlMs"] = Self.toolsTTLMilliseconds
                result["cacheScope"] = "private"
            }
            return complete(result)
        case "tools/call":
            guard let name = params["name"] as? String, !name.isEmpty else {
                return fail(-32602, "Invalid params: missing tool name")
            }
            let rawArguments = params["arguments"]
            if let rawArguments, !(rawArguments is [String: Any]), !(rawArguments is NSNull) {
                return fail(-32602, "Invalid params: arguments must be an object")
            }
            guard tools.has(name) else { return fail(-32602, "Unknown tool: \(name)") }
            return complete(await tools.call(name, arguments: rawArguments as? [String: Any] ?? [:]))
        default:
            if method.hasPrefix("notifications/") { return nil }
            return fail(-32601, "Method not found: \(method)")
        }
    }

    static var serverInfo: [String: Any] {
        ["name": "hanasu", "title": "Hanasu", "version": HanasuCommand.version]
    }

    static func error(id: Any, code: Int, message: String, data: Any? = nil) -> [String: Any] {
        var error: [String: Any] = ["code": code, "message": message]
        if let data { error["data"] = data }
        return ["jsonrpc": "2.0", "id": id, "error": error]
    }
}
