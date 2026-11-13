import Darwin
import Foundation
import Security

// 要件: REQ-COM-030, REQ-COM-187, REQ-COM-033
// 設計判断: DEC-COM-060, DEC-COM-063, DEC-COM-184, DEC-COM-110
/// 同梱した llama.cpp の llama-server を、ローカルの LLM を使うときだけ子プロセスで動かす。
/// - 127.0.0.1 の空いたポートで、起動のたびに作る API キー（環境変数 LLAMA_API_KEY）を付けて起動する
/// - 最後の処理から 5 分たつと止める（音声入力の録音中の先読みの保持があれば止めない）。モデルを変えたら起動し直す。アプリ（CLI も）を終えるときに止める
/// - 音声入力の録音が始まったら、裏で先に起動しておける（prewarm）
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
    // 設計判断: DEC-COM-110
    /// 起動している途中のモデル（/health が通るまで）。同じモデルを求めた処理は、起動し直さずにこの起動を待つ
    private var launchingModel: LocalLLMModel?
    /// 起動を始めるたびに増やす。待っている処理が、自分の待った起動かを見分ける
    private var launchGeneration = 0
    /// 起動に失敗したときの理由（その起動を待っていた処理に同じ失敗を返す）
    private var lastLaunchFailure: (generation: Int, error: any Error)?
    /// 音声入力・選択の編集の録音中の先読みの保持。1 つでもあれば、5 分たっても止めない
    private var warmHolds: Set<UUID> = []

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
        // 待ち始めたら真、待ちを抜けたら（進んだ・期限・取り消しのどれでも）偽を、見ている画面に知らせる
        let observer = Self.waitObserver
        var notifiedWaiting = false
        defer { if notifiedWaiting { observer?(false) } }
        while true {
            switch gate.decision(for: ticket, model: model, serving: servingModel, waitsForOtherModel: waitsForOtherModel) {
            case .proceed, .start:
                gate.admit(ticket)
                if notifiedWaiting {
                    notifiedWaiting = false
                    observer?(false)
                }
                do {
                    let endpoint = try await ensureRunning(model)
                    lastUsed = Date()
                    return endpoint
                } catch {
                    gate.finish()
                    throw error
                }
            case .wait:
                if !notifiedWaiting {
                    notifiedWaiting = true
                    observer?(true)
                }
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

    // 要件: REQ-COM-033
    // 設計判断: DEC-COM-110
    /// 音声入力・選択の編集の録音が始まったときに、そのモデルを裏で起動しておく（結果は待たない）。
    /// ほかの処理が違うモデルを使っている・待っているときは何もしないで nil を返す（その処理を止めない）。
    /// そうでなければ録音中の保持を付けてその ID を返す。録音を止めた・取り消した・失敗したら releaseWarmHold で外す
    func prewarm(_ model: LocalLLMModel) -> UUID? {
        let current = launchingModel ?? servingModel
        if !gate.isIdle, current != model {
            appLog.notice("local llm prewarm skipped: \(model.rawValue, privacy: .public) (other model in use)")
            return nil
        }
        let hold = UUID()
        warmHolds.insert(hold)
        lastUsed = Date()
        if current == model { return hold }
        // 起動している間は、使っている処理に数える（起動の途中に来たほかのモデルの処理は、起動が終わるまで待つ）
        gate.beginPrewarm()
        Task {
            do {
                _ = try await ensureRunning(model)
            } catch {
                appLog.error("local llm prewarm failed: \(error.localizedDescription, privacy: .public)")
            }
            gate.finish()
            lastUsed = Date()
            scheduleIdleStop()
        }
        return hold
    }

    /// 録音中の保持を外す。そこから 5 分使わなければ止める
    func releaseWarmHold(_ hold: UUID) {
        guard warmHolds.remove(hold) != nil else { return }
        lastUsed = Date()
        scheduleIdleStop()
    }

    /// そのモデルの処理を今送ると、ほかの処理が終わるのを待つことになるか
    func wouldWait(for model: LocalLLMModel, waitsForOtherModel: Bool) -> Bool {
        gate.wouldWait(for: model, serving: servingModel, waitsForOtherModel: waitsForOtherModel)
    }

    /// beginRequest が、ほかの処理の終わりを待ち始めた（真）・待ちを抜けた（偽）ことを知らせる先。
    /// 呼び出す側のタスクに付ける（observingWait）ので、間に挟まる AI の呼び出しの層を変えずに届く
    @TaskLocal static var waitObserver: (@Sendable (Bool) -> Void)?

    // 設計判断: DEC-COM-172
    /// body の中で始めたローカルの AI の処理が、ほかの処理の終わりを待っている間だけ、
    /// onChange に真を渡す（抜けたら偽）。onChange はメインスレッドで、起きた順に呼ぶ
    nonisolated static func observingWait<T>(_ onChange: @escaping @MainActor @Sendable (Bool) -> Void,
                                             _ body: () async throws -> T) async rethrows -> T {
        try await $waitObserver.withValue({ waiting in
            DispatchQueue.main.async { MainActor.assumeIsolated { onChange(waiting) } }
        }, operation: body)
    }

    /// 使える状態で動いているモデル（起動中は nil）。確かめる用にも読む
    var servingModel: LocalLLMModel? {
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

    // 設計判断: DEC-COM-110
    private func ensureRunning(_ model: LocalLLMModel) async throws -> Endpoint {
        if let endpoint, servingModel == model {
            return endpoint
        }
        // 同じモデルを起動している途中なら、起動し直さずにその起動を待つ（先読みの途中に録音を止めたときなど）
        if launchingModel == model {
            let generation = launchGeneration
            while launchingModel == model, launchGeneration == generation {
                try await Task.sleep(for: .milliseconds(100))
            }
            if let endpoint, servingModel == model { return endpoint }
            if let failure = lastLaunchFailure, failure.generation == generation { throw failure.error }
            // 起動した処理が取り消されたなどで、終わりが分からない。起動し直す
        }
        stop()
        launchGeneration += 1
        let generation = launchGeneration
        launchingModel = model
        lastLaunchFailure = nil
        defer { if launchGeneration == generation { launchingModel = nil } }
        do {
            return try await launch(model, generation: generation)
        } catch {
            if launchGeneration == generation { lastLaunchFailure = (generation, error) }
            throw error
        }
    }

    /// 起動して /health が通るまで待つ。途中で止められた（stop・ほかのモデルの起動）ら失敗にし、後から来たサーバーは止めない
    private func launch(_ model: LocalLLMModel, generation: Int) async throws -> Endpoint {
        let started = Date()
        if let fakeLaunch {
            self.model = model
            launchCount += 1
            let endpoint = try await fakeLaunch(model)
            guard launchGeneration == generation, self.model == model else {
                throw Failure.exited(status: SIGTERM, log: "")
            }
            self.endpoint = endpoint
            return endpoint
        }
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
        // 片付け（stop）は、このループが起動したプロセスが今のものと同じときだけ（割り込んで起動したほかのサーバーを止めない）
        func isCurrent() -> Bool { self.process === process && launchGeneration == generation }
        while true {
            if !process.isRunning || !isCurrent() {
                let status = process.isRunning ? SIGTERM : process.terminationStatus
                if isCurrent() { stop() }
                throw Failure.exited(status: status, log: tail.lastLines(8))
            }
            if await Self.isHealthy(endpoint) { break }
            if Date() > deadline {
                if isCurrent() { stop() }
                throw Failure.startupTimedOut
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        guard isCurrent() else { throw Failure.exited(status: SIGTERM, log: "") }
        self.endpoint = endpoint
        appLog.notice("local llm server ready: \(model.rawValue, privacy: .public) \(String(format: "%.1f", Date().timeIntervalSince(started)), privacy: .public)s")
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
        guard process != nil, shouldStopForIdle(now: Date()) else { return }
        appLog.notice("local llm server stopped (idle)")
        stop()
    }

    // 設計判断: DEC-COM-172（待っている処理があるときも止めない）、DEC-COM-110（録音中の先読みの保持があるときも止めない）
    /// 5 分使っていないとして止めてよいか。確かめる用に、時刻を渡して呼べる
    func shouldStopForIdle(now: Date) -> Bool {
        gate.isIdle && warmHolds.isEmpty && now.timeIntervalSince(lastUsed) >= Self.idleSeconds - 1
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
