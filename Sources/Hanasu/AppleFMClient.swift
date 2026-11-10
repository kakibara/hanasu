import Foundation
import Security

// 要件: REQ-COM-031
// 設計判断: DEC-COM-071
/// Apple の Foundation Models の CLI（`fm`。macOS 27 から入っている）が使えるか。
/// macOS 27 以上で、Apple が署名した /usr/bin/fm があるときだけ使う（同じ名前の別のプログラムに文章を渡さない）。
/// 確認用に、環境変数 HANASU_FM_PATH で別の実行ファイルを指定でき、そのときは macOS の版と署名を見ない
enum AppleFMAvailability: Equatable {
    case available(URL)
    case unsupportedOS(String)
    case notFound
    case untrustedSignature(String)

    static let systemPath = "/usr/bin/fm"

    var executableURL: URL? {
        if case .available(let url) = self { return url }
        return nil
    }

    /// 使えないときの理由（設定の欄と知らせに出す）
    var reason: String? {
        switch self {
        case .available: nil
        case .unsupportedOS(let version): tr("Apple の Foundation Models の CLI（fm）は macOS 27 以降で使えます（この Mac は macOS %@）", "\(version)")
        case .notFound: tr("Apple の Foundation Models の CLI（%@）が見つかりません", "\(Self.systemPath)")
        case .untrustedSignature(let path): tr("%@ が Apple の署名ではないため、使いません", "\(path)")
        }
    }

    static func check() -> AppleFMAvailability {
        if let override = ProcessInfo.processInfo.environment["HANASU_FM_PATH"], !override.isEmpty {
            let url = URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
            return FileManager.default.isExecutableFile(atPath: url.path) ? .available(url) : .notFound
        }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        guard os.majorVersion >= 27 else {
            return .unsupportedOS("\(os.majorVersion).\(os.minorVersion)")
        }
        let url = URL(fileURLWithPath: systemPath)
        guard FileManager.default.isExecutableFile(atPath: url.path) else { return .notFound }
        return isSignedByApple(url) ? .available(url) : .untrustedSignature(url.path)
    }

    /// コードの署名が Apple のもの（要件 anchor apple）か
    static func isSignedByApple(_ url: URL) -> Bool {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString("anchor apple" as CFString, [], &requirement) == errSecSuccess, let requirement
        else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), requirement) == errSecSuccess
    }
}

enum AppleFMError: LocalizedError {
    case unavailable(String)
    case failed(status: Int32, message: String)
    case timedOut(TimeInterval)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): reason
        case .failed(let status, let message):
            Self.licenseHint(message)
                ?? tr("Apple の Foundation Models（fm）がエラーで終わりました（終了コード %@）", "\(status)") + (message.isEmpty ? "" : "\n" + message)
        case .timedOut(let seconds): tr("Apple の Foundation Models（fm）が %@ 秒以内に応答しませんでした", "\(Int(seconds))")
        case .emptyResponse: tr("Apple の Foundation Models（fm）から結果が返りませんでした")
        }
    }

    /// 利用条件への同意がまだのとき（fm はすべてのコマンドを断る。未確認）の案内
    private static func licenseHint(_ message: String) -> String? {
        let lower = message.lowercased()
        guard lower.contains("license") || lower.contains("terms") else { return nil }
        return tr("Apple の Foundation Models（fm）の利用条件にまだ同意していないようです。ターミナルで sudo fm license を実行してから、もう一度試してください\n") + message
    }
}

// 要件: REQ-COM-031
// 設計判断: DEC-COM-070, DEC-COM-072, DEC-COM-073
/// Apple の Foundation Models の CLI（`fm respond`）に文章を送る。プロンプトは Gemini・Claude・ローカルと同じものを使う。
/// 端末の中のモデルだけを使う（--model pcc は付けない）。文脈に入らない入力は LongInputFitter で縮めてから送る
struct AppleFMClient {
    var executableURL: URL
    var timeout: TimeInterval

    /// 履歴・知らせに出すモデルの名前（端末の中のモデル。DEC-COM-072）
    static let modelName = "apple-on-device"

    /// 文脈の長さ（コミュニティの文書の値。Apple の文書では未確認）
    static let contextLength = 8_192

    /// 用途ごとの最短の待ち時間
    static func minimumTimeout(for purpose: TextAIPurpose) -> TimeInterval {
        purpose == .dictation ? 60 : 600
    }

    static func maxOutputTokens(_ purpose: LocalLLMClient.Purpose) -> Int {
        purpose == .short ? 1_536 : 2_048
    }

    /// 設定で使えるときのクライアント。使えなければ nil
    static func fromSystem(timeout: TimeInterval) -> AppleFMClient? {
        AppleFMAvailability.check().executableURL.map { AppleFMClient(executableURL: $0, timeout: timeout) }
    }

    // 設計判断: DEC-COM-072
    /// `fm respond` の引数。入力は引数で渡す（標準入力で渡せるかは未確認。DEC-COM-070）
    static func arguments(instructions: String, prompt: String) -> [String] {
        ["respond", "--instructions", instructions, prompt]
    }

    // 設計判断: DEC-COM-073
    /// トークン数の見積もり。漢字・かな・全角は 1 文字 1 トークン、ほかは 3 文字で 1 トークン（多めに見積もる）
    static func estimateTokens(_ text: String) -> Int {
        var wide = 0, narrow = 0
        for scalar in text.unicodeScalars {
            if scalar.value >= 0x2E80 { wide += 1 } else { narrow += 1 }
        }
        return wide + (narrow + 2) / 3
    }

    func generate(system rawSystem: String, userText rawUserText: String, purpose: LocalLLMClient.Purpose) async throws -> String {
        let maxOutput = Self.maxOutputTokens(purpose)
        // 要件: REQ-DIC-041
        // 設計判断: DEC-DIC-184
        // 入りきらないときは、文字起こしを要約させる前に、スクリーンショットの文字を外す
        let (system, userText) = try await ScreenOCRBudget.fit(
            system: rawSystem, userText: rawUserText, contextLength: Self.contextLength, maxOutputTokens: maxOutput,
            countTokens: { Self.estimateTokens($0) })
        let fitter = LongInputFitter(
            contextLength: Self.contextLength, maxOutputTokens: maxOutput,
            countTokens: { Self.estimateTokens($0) },
            summarize: { part, index, total in
                try await respond(instructions: LongInputFitter.partInstruction(index: index, total: total),
                                  prompt: LongInputFitter.partUserText(part))
            })
        let fitted = try await fitter.fit(system: system, userText: userText)
        if fitted != userText {
            appLog.notice("apple fm input was shortened: \(userText.count) -> \(fitted.count) chars")
        }
        return try await respond(instructions: system, prompt: fitted)
    }

    /// `fm respond` を 1 回動かし、標準出力を返す
    func respond(instructions: String, prompt: String) async throws -> String {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = Self.arguments(instructions: instructions, prompt: prompt)
        process.standardInput = FileHandle.nullDevice
        let output = Pipe(), error = Pipe()
        process.standardOutput = output
        process.standardError = error
        let collected = CollectedOutput()
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil } else { collected.appendOutput(data) }
        }
        error.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil } else { collected.appendError(data) }
        }
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            let once = ResumeOnce(continuation)
            process.terminationHandler = { once.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                once.resume(throwing: error)
                return
            }
            let timeout = timeout
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard process.isRunning else { return }
                process.terminate()
                once.resume(throwing: AppleFMError.timedOut(timeout))
            }
        }
        // 終わったあとに届く残りを読み切る
        output.fileHandleForReading.readabilityHandler = nil
        error.fileHandleForReading.readabilityHandler = nil
        collected.appendOutput(output.fileHandleForReading.readDataToEndOfFile())
        collected.appendError(error.fileHandleForReading.readDataToEndOfFile())
        guard status == 0 else {
            throw AppleFMError.failed(status: status, message: collected.errorTail(lines: 6))
        }
        let text = collected.outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AppleFMError.emptyResponse }
        return text
    }
}

/// 子プロセスの出力をためる（読み取りは別のスレッドから届く）
private final class CollectedOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var output = Data()
    private var error = Data()

    func appendOutput(_ data: Data) { lock.withLock { output.append(data) } }
    func appendError(_ data: Data) {
        lock.withLock {
            error.append(data)
            if error.count > 16 << 10 { error.removeFirst(error.count - (16 << 10)) }
        }
    }

    var outputText: String { lock.withLock { String(decoding: output, as: UTF8.self) } }

    func errorTail(lines: Int) -> String {
        let text = lock.withLock { String(decoding: error, as: UTF8.self) }
        return text.split(separator: "\n").suffix(lines).joined(separator: "\n")
    }
}

/// continuation を 1 回だけ再開する（終了と時間切れのどちらが先でもよいように）
private final class ResumeOnce<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) { self.continuation = continuation }

    private func take() -> CheckedContinuation<T, Error>? {
        lock.withLock {
            let c = continuation
            continuation = nil
            return c
        }
    }

    func resume(returning value: T) { take()?.resume(returning: value) }
    func resume(throwing error: Error) { take()?.resume(throwing: error) }
}
