import Darwin
import Foundation
import Security

// 要件: REQ-COM-030, REQ-COM-187
// 設計判断: DEC-COM-060, DEC-COM-063, DEC-COM-184
/// 同梱した llama.cpp の llama-server を、ローカルの LLM を使うときだけ子プロセスで動かす。
/// - 127.0.0.1 の空いたポートで、起動のたびに作る API キー（環境変数 LLAMA_API_KEY）を付けて起動する
/// - 最後の処理から 5 分たつと止める。モデルを変えたら起動し直す。アプリ（CLI も）を終えるときに止める
/// - 記録は起動したプロセスごとのファイル（server-<持ち主の pid>.pid）。前回落ちたときに残ったサーバーは、
///   持ち主が終わっている記録を見て、アプリの次の起動時に止める（動いているほかのプロセスのサーバーは止めない）
actor LocalLLMServer {
    static let shared = LocalLLMServer()

    /// 使わなくなってから止めるまでの秒数
    static let idleSeconds: TimeInterval = 300
    /// モデルの読み込みを待つ最大の秒数（Gemma 4 E4B は 4.6 GB を読む）
    static let startupTimeout: TimeInterval = 180

    struct Endpoint: Sendable {
        var baseURL: URL
        var apiKey: String
    }

    enum Failure: LocalizedError {
        case serverNotFound
        case unknownModel(String)
        case modelNotDownloaded(LocalLLMModel)
        case exited(status: Int32, log: String)
        case startupTimedOut

        var errorDescription: String? {
            switch self {
            case .serverNotFound:
                tr("ローカルの LLM を動かす llama-server が見つかりません（アプリを入れ直すか、環境変数 HANASU_LLAMA_SERVER でパスを指定してください）")
            case .unknownModel(let id):
                tr("ローカルのモデル「%@」はありません（%@）", "\(id)", "\(LocalLLMModel.allCases.map(\.rawValue).joined(separator: " / "))")
            case .modelNotDownloaded(let model):
                tr("ローカルのモデル「%@」がまだダウンロードされていません（設定 →「AI」でダウンロードしてください）", "\(model.name)")
            case .exited(let status, let log):
                tr("ローカルの LLM が起動できませんでした（終了コード %@）", "\(status)") + (log.isEmpty ? "" : "\n" + log)
            case .startupTimedOut:
                tr("ローカルの LLM の起動が %@ 秒たっても終わりませんでした", "\(Int(LocalLLMServer.startupTimeout))")
            }
        }
    }

    private var process: Process?
    private var model: LocalLLMModel?
    private var endpoint: Endpoint?
    private var activeRequests = 0
    private var lastUsed = Date()
    private var idleTask: Task<Void, Never>?
    private let stderrTail = OutputTail()

    // MARK: - 使う側

    // 設計判断: DEC-COM-061
    /// llama-server の場所: 環境変数 HANASU_LLAMA_SERVER → アプリの Contents/Resources/llama → 開発中の build/llama-cpp/macos-arm64
    static var executableURL: URL? {
        var candidates: [URL] = []
        if let path = ProcessInfo.processInfo.environment["HANASU_LLAMA_SERVER"], !path.isEmpty {
            candidates.append(URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
        }
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("llama/llama-server"))
        }
        candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("build/llama-cpp/macos-arm64/llama-server"))
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// 処理を 1 つ始める。そのモデルでサーバーが動いていなければ起動する。終わったら finishRequest を呼ぶ
    func beginRequest(_ model: LocalLLMModel) async throws -> Endpoint {
        activeRequests += 1
        do {
            let endpoint = try await ensureRunning(model)
            lastUsed = Date()
            return endpoint
        } catch {
            activeRequests -= 1
            throw error
        }
    }

    func finishRequest() {
        activeRequests = max(0, activeRequests - 1)
        lastUsed = Date()
        scheduleIdleStop()
    }

    /// そのモデルを動かしていれば止める（モデルを消すとき）
    func stop(ifServing model: LocalLLMModel) {
        if self.model == model { stop() }
    }

    func stop() {
        idleTask?.cancel()
        idleTask = nil
        if let process, process.isRunning {
            process.terminate()
            let pid = process.processIdentifier
            // 3 秒で終わらなければ強制的に止める
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
            }
        }
        process = nil
        model = nil
        endpoint = nil
        Self.setRunningPID(nil)
        try? FileManager.default.removeItem(at: Self.pidFile)
    }

    // MARK: - 起動

    private func ensureRunning(_ model: LocalLLMModel) async throws -> Endpoint {
        if let process, process.isRunning, self.model == model, let endpoint {
            return endpoint
        }
        stop()
        guard let executable = Self.executableURL else { throw Failure.serverNotFound }
        guard LocalLLMStore.isDownloaded(model) else { throw Failure.modelNotDownloaded(model) }

        let port = try Self.freePort()
        let apiKey = Self.randomKey()
        let process = Process()
        process.executableURL = executable
        process.arguments = Self.arguments(model: model, port: port)
        var environment = ProcessInfo.processInfo.environment
        // Hanasu を起動したときの環境に LLAMA_ARG_* があっても使わない（決めた引数だけで動かす）。
        // CLI が環境変数で受け取るほかの API キーは、llama-server には要らないので渡さない（自己署名のときは
        // ライブラリの検証を外したプロセスなので、要らない秘密を持たせない）
        for key in environment.keys where key.hasPrefix("LLAMA_ARG_") || Self.secretEnvironmentKeys.contains(key) {
            environment[key] = nil
        }
        environment["LLAMA_API_KEY"] = apiKey
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let errorPipe = Pipe()
        process.standardError = errorPipe
        let tail = stderrTail
        tail.reset()
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil } else { tail.append(data) }
        }
        try process.run()
        self.process = process
        self.model = model
        Self.setRunningPID(process.processIdentifier)
        Self.writePIDFile(pid: process.processIdentifier, executable: executable)
        appLog.notice("local llm server started: \(model.rawValue, privacy: .public) port=\(port)")

        let endpoint = Endpoint(baseURL: URL(string: "http://127.0.0.1:\(port)")!, apiKey: apiKey)
        let deadline = Date().addingTimeInterval(Self.startupTimeout)
        while true {
            if !process.isRunning {
                let status = process.terminationStatus
                stop()
                throw Failure.exited(status: status, log: tail.lastLines(8))
            }
            if await Self.isHealthy(endpoint) { break }
            if Date() > deadline {
                stop()
                throw Failure.startupTimedOut
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        self.endpoint = endpoint
        return endpoint
    }

    /// 子プロセスに渡さない環境変数（Hanasu の CLI が環境変数で受け取る、ほかのサービスの秘密）
    static let secretEnvironmentKeys: Set<String> = [
        "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "GEMINI_API_KEY", "GOOGLE_API_KEY",
        "GEMINI_SERVICE_ACCOUNT_JSON", "GOOGLE_APPLICATION_CREDENTIALS", "HF_TOKEN",
    ]

    static func arguments(model: LocalLLMModel, port: Int) -> [String] {
        [
            "--model", LocalLLMStore.fileURL(model).path,
            // キーなしで読める /models に、モデルのファイルのパス（ユーザー名を含む）ではなく id を出させる
            "--alias", model.rawValue,
            "--host", "127.0.0.1",
            "--port", String(port),
            "--ctx-size", String(model.contextLength),
            "--parallel", "1",
            "--n-gpu-layers", "99",
            "--jinja",
            "--reasoning", "off",
            "--no-webui",
        ]
    }

    private func scheduleIdleStop() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.idleSeconds))
            guard !Task.isCancelled else { return }
            await self?.stopIfIdle()
        }
    }

    private func stopIfIdle() {
        guard activeRequests == 0, Date().timeIntervalSince(lastUsed) >= Self.idleSeconds - 1, process != nil else { return }
        appLog.notice("local llm server stopped (idle)")
        stop()
    }

    private static func isHealthy(_ endpoint: Endpoint) async -> Bool {
        var request = URLRequest(url: endpoint.baseURL.appendingPathComponent("health"))
        request.timeoutInterval = 2
        guard let (_, response) = try? await LocalLLMClient.session.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }

    /// 127.0.0.1 で OS に空いたポートを選ばせる
    static func freePort() throws -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EMFILE) }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, length) == 0 && getsockname(fd, $0, &length) == 0 }
        }
        guard bound else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EADDRINUSE) }
        return Int(UInt16(bigEndian: address.sin_port))
    }

    static func randomKey() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - 終了時・前回の残り

    private static let pidLock = NSLock()
    nonisolated(unsafe) private static var runningPID: pid_t?

    /// シグナルのハンドラーから読む pid（ロックを使わない）
    nonisolated(unsafe) private static var signalPID: pid_t = 0

    private static func setRunningPID(_ pid: pid_t?) {
        pidLock.withLock { runningPID = pid }
        signalPID = pid ?? 0
    }

    /// シグナルのハンドラーから呼ぶ。ロックとファイルの操作をせずに、動いているサーバーを止める
    nonisolated static func killRunningServerFromSignal() {
        let pid = signalPID
        if pid > 0 { kill(pid, SIGTERM) }
    }

    /// アプリ・CLI を終えるときに呼ぶ（atexit・applicationWillTerminate）。actor を待たずに止める
    nonisolated static func terminateRunningServer() {
        guard let pid = pidLock.withLock({ runningPID }) else { return }
        kill(pid, SIGTERM)
        try? FileManager.default.removeItem(at: pidFile)
    }

    /// このプロセスの記録（server-<自分の pid>.pid）
    nonisolated static var pidFile: URL {
        LocalLLMStore.directory.appendingPathComponent("server-\(getpid()).pid")
    }

    /// 今までの版が書いた 1 つだけの記録（持ち主が分からない）
    nonisolated static var legacyPIDFile: URL {
        LocalLLMStore.directory.appendingPathComponent("server.pid")
    }

    private static func writePIDFile(pid: pid_t, executable: URL) {
        try? FileManager.default.createDirectory(at: LocalLLMStore.directory, withIntermediateDirectories: true)
        try? "\(pid)\n\(executable.resolvingSymlinksInPath().path)\n\(getpid())\n".write(to: pidFile, atomically: true, encoding: .utf8)
    }

    // 設計判断: DEC-COM-184
    /// 記録 1 つ。owner は記録を書いたプロセス（今までの server.pid では nil）
    struct Record {
        var file: URL
        var serverPID: pid_t
        var executablePath: String
        var owner: pid_t?

        /// 記録した pid のプロセスが、記録した実行ファイルとして動いているか（pid は使い回されるので、パスも見る）
        var serverIsRunning: Bool {
            var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
            guard serverPID > 0, proc_pidpath(serverPID, &buffer, UInt32(buffer.count)) > 0 else { return false }
            return URL(fileURLWithPath: String(cString: buffer)).resolvingSymlinksInPath().path == executablePath
        }

        /// 持ち主のプロセスが動いているか。持ち主が分からなければ false
        var ownerIsRunning: Bool {
            guard let owner, owner > 0 else { return false }
            return kill(owner, 0) == 0 || errno == EPERM
        }
    }

    nonisolated static func records() -> [Record] {
        let files = ((try? FileManager.default.contentsOfDirectory(at: LocalLLMStore.directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent == "server.pid" || ($0.lastPathComponent.hasPrefix("server-") && $0.pathExtension == "pid") }
        return files.compactMap { file in
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
            let lines = text.split(separator: "\n").map(String.init)
            guard lines.count >= 2, let pid = pid_t(lines[0]) else { return nil }
            return Record(file: file, serverPID: pid, executablePath: lines[1], owner: lines.count >= 3 ? pid_t(lines[2]) : nil)
        }
    }

    // 要件: REQ-COM-187
    /// ほかのプロセス（アプリや別の hanasu）が起動したサーバーが動いているか。hanasu は、動いていれば自分のサーバーを起動しない
    nonisolated static func otherProcessServerRunning() -> Bool {
        records().contains { record in
            record.owner != getpid() && (record.owner == nil || record.ownerIsRunning) && record.serverIsRunning
        }
    }

    /// 前回落ちたときに残った llama-server を止める（アプリの起動時）。持ち主が終わっている記録のサーバーだけを、
    /// 記録した実行ファイルのときだけ止める（pid は使い回されるので、別のプロセスを止めないため）。
    /// 動いているほかのプロセス（hanasu コマンドなど）の記録には触らない
    nonisolated static func cleanUpStaleServer() {
        for record in records() where record.owner != getpid() {
            if record.ownerIsRunning { continue }
            if record.serverIsRunning {
                kill(record.serverPID, SIGTERM)
                appLog.notice("stopped stale local llm server pid=\(record.serverPID)")
            }
            try? FileManager.default.removeItem(at: record.file)
        }
    }
}

/// llama-server の標準エラーの最後の部分（起動に失敗したときに理由を出すため。ファイルには残さない）
private final class OutputTail: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func reset() { lock.withLock { data.removeAll() } }

    func append(_ chunk: Data) {
        lock.withLock {
            data.append(chunk)
            if data.count > 16 << 10 { data.removeFirst(data.count - (16 << 10)) }
        }
    }

    func lastLines(_ count: Int) -> String {
        let text = lock.withLock { String(decoding: data, as: UTF8.self) }
        return text.split(separator: "\n").suffix(count).joined(separator: "\n")
    }
}
