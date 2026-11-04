import Combine
import CryptoKit
import Foundation

// 要件: REQ-COM-030
// 設計判断: DEC-COM-062
/// ローカルの LLM のモデル（GGUF）のダウンロード・削除と、その状態。設定画面に出す。
/// 保存先: ~/Library/Application Support/Hanasu/Models/llm（環境変数 HANASU_MODELS_DIR があれば <dir>/llm。確認用）。
/// 1. https の huggingface.co から「.download」の名前に取る（リダイレクト先の CDN も https だけ）
/// 2. 大きさと SHA-256 を、LocalLLMModel に決めておいた値と比べる。違えば消して使わない
/// 3. 合っていたら本来の名前に変える（途中のファイルは使わない）
@MainActor
final class LocalLLMStore: ObservableObject {
    static let shared = LocalLLMStore()

    enum Status: Equatable {
        case notDownloaded
        /// fraction は 0〜1。nil はハッシュを確かめているところ
        case downloading(fraction: Double?)
        case downloaded
        case failed(String)
    }

    enum Failure: LocalizedError {
        case notAllowed(String)
        case sizeMismatch(expected: Int64, actual: Int64)
        case hashMismatch
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .notAllowed(let host): "決めた場所以外からはダウンロードしません（\(host)）"
            case .sizeMismatch(let expected, let actual): "ダウンロードしたモデルの大きさが想定と違います（\(actual) バイト、想定は \(expected) バイト）"
            case .hashMismatch: "ダウンロードしたモデルのハッシュ（SHA-256）が想定と違うので、使いません"
            case .http(let status): "モデルをダウンロードできませんでした（HTTP \(status)）"
            }
        }
    }

    @Published private(set) var statuses: [LocalLLMModel: Status] = [:]
    private var tasks: [LocalLLMModel: Task<Void, Never>] = [:]

    nonisolated static var directory: URL {
        if let dir = ProcessInfo.processInfo.environment["HANASU_MODELS_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: (dir as NSString).expandingTildeInPath, isDirectory: true)
                .appendingPathComponent("llm", isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hanasu/Models/llm", isDirectory: true)
    }

    nonisolated static func fileURL(_ model: LocalLLMModel) -> URL {
        directory.appendingPathComponent(model.fileName)
    }

    /// 確かめ終えたファイルがあるか（ハッシュは置くときに確かめてあるので、ここでは大きさだけ見る）
    nonisolated static func isDownloaded(_ model: LocalLLMModel) -> Bool {
        let size = (try? FileManager.default.attributesOfItem(atPath: fileURL(model).path)[.size] as? Int64) ?? nil
        return size == model.byteCount
    }

    private init() {
        for model in LocalLLMModel.allCases {
            statuses[model] = Self.isDownloaded(model) ? .downloaded : .notDownloaded
        }
    }

    func status(_ model: LocalLLMModel) -> Status { statuses[model] ?? .notDownloaded }

    /// まだなければダウンロードを始める。終わるまで待つときは await する
    @discardableResult
    func ensureDownloaded(_ model: LocalLLMModel) -> Task<Void, Never>? {
        if Self.isDownloaded(model) {
            statuses[model] = .downloaded
            return nil
        }
        if let task = tasks[model] { return task }
        statuses[model] = .downloading(fraction: 0)
        let task = Task { [weak self] in
            do {
                try await Self.download(model) { fraction in
                    Task { @MainActor in
                        guard let self, case .downloading = self.status(model) else { return }
                        self.statuses[model] = .downloading(fraction: fraction)
                    }
                }
                self?.statuses[model] = .downloaded
                appLog.notice("local llm downloaded: \(model.rawValue, privacy: .public)")
            } catch {
                let cancelled = Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled
                if !cancelled { appLog.error("local llm download failed: \(String(describing: error), privacy: .public)") }
                self?.statuses[model] = cancelled ? .notDownloaded : .failed(error.localizedDescription)
            }
            self?.tasks[model] = nil
        }
        tasks[model] = task
        return task
    }

    func cancelDownload(_ model: LocalLLMModel) {
        tasks[model]?.cancel()
    }

    func delete(_ model: LocalLLMModel) {
        tasks[model]?.cancel()
        Task { await LocalLLMServer.shared.stop(ifServing: model) }
        try? FileManager.default.removeItem(at: Self.fileURL(model))
        statuses[model] = .notDownloaded
    }

    /// 設定画面を PNG に描き出す確認用に、ダウンロード中の見た目にする（CLI の --render-ai-settings --local・
    /// --render-local-model-download）。fraction が nil ならハッシュを確かめているところ
    func showDownloadingForRendering(_ model: LocalLLMModel, fraction: Double?) {
        statuses[model] = .downloading(fraction: fraction)
    }

    // MARK: - ダウンロード

    nonisolated static func download(_ model: LocalLLMModel, progress: @escaping @Sendable (Double?) -> Void) async throws {
        let url = model.downloadURL
        guard url.scheme == "https", url.host == "huggingface.co" else { throw Failure.notAllowed(url.host ?? "?") }
        let directory = Self.directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let partial = directory.appendingPathComponent(model.fileName + ".download")
        try? FileManager.default.removeItem(at: partial)
        do {
            let delegate = DownloadDelegate(expectedBytes: model.byteCount, destination: partial, progress: progress)
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            try await withTaskCancellationHandler {
                try await delegate.run(request)
            } onCancel: {
                delegate.cancel()
            }
            try Task.checkCancellation()
            progress(nil)
            let size = (try FileManager.default.attributesOfItem(atPath: partial.path)[.size] as? Int64) ?? -1
            guard size == model.byteCount else { throw Failure.sizeMismatch(expected: model.byteCount, actual: size) }
            guard try sha256(of: partial) == model.sha256 else { throw Failure.hashMismatch }
            let final = fileURL(model)
            try? FileManager.default.removeItem(at: final)
            try FileManager.default.moveItem(at: partial, to: final)
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
    }

    nonisolated static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 8 << 20), !chunk.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// 1 つのファイルを取る。進み具合を返し、想定より大きくなったら止める。
    /// リダイレクト（Hugging Face の CDN）には https のときだけ従う。中身はハッシュで確かめる
    private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let expectedBytes: Int64
        let destination: URL
        let progress: @Sendable (Double?) -> Void
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, Error>?
        private var session: URLSession?
        private var failure: Error?

        init(expectedBytes: Int64, destination: URL, progress: @escaping @Sendable (Double?) -> Void) {
            self.expectedBytes = expectedBytes
            self.destination = destination
            self.progress = progress
        }

        func run(_ request: URLRequest) async throws {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
            configuration.timeoutIntervalForRequest = 60
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.withLock {
                    self.continuation = continuation
                    self.session = session
                }
                session.downloadTask(with: request).resume()
            }
        }

        func cancel() {
            lock.withLock { session }?.invalidateAndCancel()
        }

        private func finish(_ error: Error?) {
            let continuation = lock.withLock {
                let c = self.continuation
                self.continuation = nil
                return c
            }
            if let error { continuation?.resume(throwing: error) } else { continuation?.resume() }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? {
            request.url?.scheme == "https" ? request : nil
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            // 想定より大きいものを書き続けない（ディスクを埋められないように）
            if totalBytesWritten > expectedBytes {
                lock.withLock { failure = Failure.sizeMismatch(expected: expectedBytes, actual: totalBytesWritten) }
                downloadTask.cancel()
                return
            }
            progress(Double(totalBytesWritten) / Double(expectedBytes))
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                lock.withLock { failure = Failure.http(http.statusCode) }
                return
            }
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: location, to: destination)
            } catch {
                lock.withLock { failure = error }
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            let stored = lock.withLock { failure }
            finish(stored ?? error)
            session.finishTasksAndInvalidate()
        }
    }
}
