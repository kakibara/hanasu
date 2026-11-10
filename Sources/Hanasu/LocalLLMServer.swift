import Darwin
import Foundation
import Security

// 要件: REQ-COM-030
// 設計判断: DEC-COM-060, DEC-COM-063
/// 同梱した llama.cpp の llama-server を、ローカルの LLM を使うときだけ子プロセスで動かす。
/// - 127.0.0.1 の空いたポートで、起動のたびに作る API キー（環境変数 LLAMA_API_KEY）を付けて起動する
/// - 最後の処理から 5 分たつと止める。モデルを変えたら起動し直す。アプリ（CLI も）を終えるときに止める
/// - 前回落ちたときに残ったサーバーは、記録（server.pid）を見て次の起動時に止める
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
        /// 違うモデルの処理が終わるのを待ちきれなかった（DEC-COM-172）
        case busy

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
            case .busy:
                tr("ほかの処理（議事録の作成など）が終わらないため、ローカルの AI を使えませんでした")
            }
        }
    }

    private var process: Process?
    private var model: LocalLLMModel?
    private var endpoint: Endpoint?
    // 設計判断: DEC-COM-172
    private var gate = LocalLLMGate()
    private var lastUsed = Date()
    /// 確かめるとき（--test-local-llm-wait）だけ: llama-server を起こさずに、起動したことにする
    private let fakeLaunch: (@Sendable (LocalLLMModel) async throws -> Endpoint)?
    /// 待っている処理が、進めるかを見直す間隔
    private let pollInterval: Duration
    /// 確かめる用: サーバーを起動した回数
    private(set) var launchCount = 0

    init(fakeLaunch: (@Sendable (LocalLLMModel) async throws -> Endpoint)? = nil,
         pollInterval: Duration = .milliseconds(500)) {
        self.fakeLaunch = fakeLaunch
        self.pollInterval = pollInterval
    }
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

    /// 処理を 1 つ始める。そのモデルでサーバーが動いていなければ起動する。終わったら finishRequest を呼ぶ。
    /// waitsForOtherModel が真なら、違うモデルを使っている処理が終わるまで deadline まで待つ（DEC-COM-172）。
    /// 偽（音声入力）なら今までどおり、処理中でも止めて起動し直す
    func beginRequest(_ model: LocalLLMModel, waitsForOtherModel: Bool = false, deadline: Date? = nil) async throws -> Endpoint {
        let ticket = UUID()
        gate.enqueue(ticket)
        while true {
            switch gate.decision(for: ticket, model: model, serving: servingModel, waitsForOtherModel: waitsForOtherModel) {
            case .proceed, .start:
                gate.admit(ticket)
                do {
                    let endpoint = try await ensureRunning(model)
                    lastUsed = Date()
                    return endpoint
                } catch {
                    gate.finish()
                    throw error
                }
            case .wait:
                if let deadline, Date() >= deadline {
                    gate.leave(ticket)
                    throw Failure.busy
                }
                do {
                    try await Task.sleep(for: pollInterval)
                } catch {
                    gate.leave(ticket)
                    throw error
                }
            }
        }
    }

    func finishRequest() {
        gate.finish()
        lastUsed = Date()
        scheduleIdleStop()
    }

    /// そのモデルの処理を今送ると、ほかの処理が終わるのを待つことになるか
    func wouldWait(for model: LocalLLMModel, waitsForOtherModel: Bool) -> Bool {
        gate.wouldWait(for: model, serving: servingModel, waitsForOtherModel: waitsForOtherModel)
    }

    /// 使える状態で動いているモデル（起動中は nil）
    private var servingModel: LocalLLMModel? {
        guard endpoint != nil, fakeLaunch != nil || process?.isRunning == true else { return nil }
        return model
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
        if let fakeLaunch {
            if self.model == model, let endpoint { return endpoint }
            stop()
            self.model = model
            launchCount += 1
            let endpoint = try await fakeLaunch(model)
            self.endpoint = endpoint
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
        launchCount += 1
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
        // 設計判断: DEC-COM-172（待っている処理があるときも止めない）
        guard gate.isIdle, Date().timeIntervalSince(lastUsed) >= Self.idleSeconds - 1, process != nil else { return }
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

    private static func setRunningPID(_ pid: pid_t?) {
        pidLock.withLock { runningPID = pid }
    }

    /// アプリ・CLI を終えるときに呼ぶ（atexit・applicationWillTerminate）。actor を待たずに止める
    nonisolated static func terminateRunningServer() {
        guard let pid = pidLock.withLock({ runningPID }) else { return }
        kill(pid, SIGTERM)
        try? FileManager.default.removeItem(at: pidFile)
    }

    nonisolated static var pidFile: URL {
        LocalLLMStore.directory.appendingPathComponent("server.pid")
    }

    private static func writePIDFile(pid: pid_t, executable: URL) {
        try? FileManager.default.createDirectory(at: LocalLLMStore.directory, withIntermediateDirectories: true)
        try? "\(pid)\n\(executable.resolvingSymlinksInPath().path)\n".write(to: pidFile, atomically: true, encoding: .utf8)
    }

    /// 前回落ちたときに残った llama-server を止める。記録した pid のプロセスが、記録した実行ファイルのときだけ止める
    /// （pid は使い回されるので、別のプロセスを止めないため）
    nonisolated static func cleanUpStaleServer() {
        guard let text = try? String(contentsOf: pidFile, encoding: .utf8) else { return }
        let lines = text.split(separator: "\n").map(String.init)
        defer { try? FileManager.default.removeItem(at: pidFile) }
        guard lines.count >= 2, let pid = pid_t(lines[0]), pid > 0 else { return }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return }
        let path = String(cString: buffer)
        if URL(fileURLWithPath: path).resolvingSymlinksInPath().path == lines[1] {
            kill(pid, SIGTERM)
            appLog.notice("stopped stale local llm server pid=\(pid)")
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
