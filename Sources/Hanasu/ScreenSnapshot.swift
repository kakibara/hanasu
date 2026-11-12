import AppKit
import CoreGraphics
@preconcurrency import ScreenCaptureKit
import Vision
import os

// 画面のスクリーンショットの文字（REQ-DIC-041・042）。
// すべての画面を撮って Mac の中で OCR し、表記の参考になる「語の一覧」と「行」を、音声入力の AI に渡す。
// 画像は OCR が終わったら捨て、読み取った文字はメモリの上だけに置く（DEC-DIC-187）。

// MARK: - 読み取った文字

// 要件: REQ-DIC-041
// 設計判断: DEC-DIC-183
/// AI に渡す、スクリーンショットから読み取った文字。語の一覧（表記の候補）と、画面の行
struct ScreenOCR: Sendable, Codable, Equatable {
    var terms: [String] = []
    var lines: [String] = []

    var isEmpty: Bool { terms.isEmpty && lines.isEmpty }
    /// 渡す文字数（語は「, 」でつなぎ、行は改行でつなぐ）
    var characterCount: Int {
        terms.joined(separator: ", ").count + lines.joined(separator: "\n").count
    }
}

/// OCR で読んだ 1 行。座標は画面全体（すべての画面をまとめた点の座標。左上が原点）
struct ScreenTextLine: Sendable, Equatable {
    var text: String
    /// 何番目の画面か（SCShareableContent の displays の順）
    var display: Int
    /// 行の中心が、入力先のウインドウの中にあるか
    var inTarget: Bool
    var y: Double
    var x: Double
}

// MARK: - 並べ方と上限（純粋な関数）

// 要件: REQ-DIC-041
// 設計判断: DEC-DIC-183, DEC-DIC-184
enum ScreenSnapshotLayout {
    /// 上限のうち、語の一覧に先に使う割合
    static let termShare = 0.6

    // 設計判断: DEC-DIC-184
    /// AI ごとの文字数の上限。クラウドは 4,000、文脈 32K のローカルは 1,000、文脈 8K（Sarashina2.2・Apple の fm）は 500
    static func limit(provider: TextAIProvider, localModel: LocalLLMModel) -> Int {
        switch provider {
        case .gemini, .claude: 4_000
        case .appleFM: 500
        case .local: localModel.contextLength <= 8_192 ? 500 : 1_000
        }
    }

    /// 行から、語の一覧と行を作り、上限に収める
    static func layout(_ lines: [ScreenTextLine], limit: Int) -> ScreenOCR {
        guard limit > 0 else { return ScreenOCR() }
        // 画面ごとに上から下・左から右。入力先のウインドウの外を先に、中をあとに
        let sorted = lines
            .filter { $0.text.trimmingCharacters(in: .whitespaces).count >= 2 }
            .sorted { a, b in
                if a.inTarget != b.inTarget { return !a.inTarget }
                if a.display != b.display { return a.display < b.display }
                if abs(a.y - b.y) > 4 { return a.y < b.y }
                return a.x < b.x
            }
        var seenLines = Set<String>()
        let uniqueLines = sorted.filter { seenLines.insert($0.text).inserted }

        // 語の一覧: 画面と「外／中」ごとの組に分け、組を順にめぐって 1 語ずつ取る（どの画面の語も落ちにくいように）
        var groups: [[String]] = []
        var groupIndex: [String: Int] = [:]
        for line in uniqueLines {
            let key = "\(line.inTarget)-\(line.display)"
            let index = groupIndex[key] ?? {
                groups.append([])
                groupIndex[key] = groups.count - 1
                return groups.count - 1
            }()
            groups[index].append(contentsOf: terms(in: line.text))
        }
        var orderedTerms: [String] = []
        var seenTerms = Set<String>()
        var cursor = Array(repeating: 0, count: groups.count)
        var remaining = groups.reduce(0) { $0 + $1.count }
        while remaining > 0 {
            for g in groups.indices where cursor[g] < groups[g].count {
                let term = groups[g][cursor[g]]
                cursor[g] += 1
                remaining -= 1
                if seenTerms.insert(term.lowercased()).inserted { orderedTerms.append(term) }
            }
        }

        var result = ScreenOCR()
        var used = 0
        var nextTerm = 0
        func takeTerms(upTo budget: Int) {
            while nextTerm < orderedTerms.count {
                let term = orderedTerms[nextTerm]
                let cost = term.count + (result.terms.isEmpty ? 0 : 2)
                if used + cost > budget { break }
                result.terms.append(term)
                used += cost
                nextTerm += 1
            }
        }
        takeTerms(upTo: Int(Double(limit) * termShare))
        for line in uniqueLines {
            let cost = line.text.count + (result.lines.isEmpty ? 0 : 1)
            // 行の途中では切らない。入らない行は飛ばして、短い行を入れる
            if used + cost <= limit {
                result.lines.append(line.text)
                used += cost
            }
        }
        // 行で使い切らなかった分は、残りの語に回す
        takeTerms(upTo: limit)
        return result
    }

    private static let termPatterns: [NSRegularExpression] = [
        // 空白で語を区切る文字の語（J3・v2.1・Kubernetes・C++・Müller・Иванов・김예린 など。アクセント付きの文字・
        // キリル文字・ハングル・アラビア文字・デーヴァナーガリーを含む）。漢字・かなは下の 2 つで取る。数字だけのものは下で除く
        #"[[\p{L}\p{N}]--[\p{Han}\p{Hiragana}\p{Katakana}ー々〆ヶ・\x{FF00}-\x{FFEF}]][[\p{L}\p{M}\p{N}._+#/\-]--[\p{Han}\p{Hiragana}\p{Katakana}ー々〆ヶ・\x{FF00}-\x{FFEF}]]*[[\p{L}\p{M}\p{N}+#]--[\p{Han}\p{Hiragana}\p{Katakana}ー々〆ヶ・\x{FF00}-\x{FFEF}]]"#,  // skip-tr
        // カタカナの語（2 文字以上）
        #"[ァ-ヺ][ァ-ヺー・]+"#,  // skip-tr
        // 漢字の並び（2 文字以上）
        #"[\p{Han}々〆ヶ]{2,}"#,  // skip-tr
    ].map { try! NSRegularExpression(pattern: $0) }

    /// 1 行から、表記の候補になる語を出てきた順に取り出す
    static func terms(in text: String) -> [String] {
        let ns = text as NSString
        var found: [(location: Int, term: String)] = []
        for pattern in termPatterns {
            for match in pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let term = ns.substring(with: match.range)
                // 数字と記号だけ（日付・時刻・金額など）は表記の候補にならない
                guard term.contains(where: { $0.isLetter }) else { continue }
                found.append((match.range.location, term))
            }
        }
        return found.sorted { $0.location < $1.location }.map(\.term)
    }
}

// MARK: - 使うかどうか（純粋な関数）

// 要件: REQ-DIC-041, REQ-DIC-042
// 設計判断: DEC-DIC-188
enum ScreenSnapshotPolicy {
    /// この録音で使われない理由
    enum InactiveReason: Equatable {
        /// 整形がオフで、翻訳もしない（AI を呼ばない）
        case refineOff
        /// 入力先のアプリが除外アプリ
        case excludedApp
        /// 音声入力の AI の認証情報がない
        case noCredentials

        var message: String {
            switch self {
            case .refineOff: tr("整形がオフなので、この録音では使われません（翻訳の言語を選ぶと使われます）")
            case .excludedApp: tr("入力先のアプリが除外アプリなので、この録音では使われません")
            case .noCredentials: tr("音声入力整形の AI の認証情報がないので、この録音では使われません")
            }
        }
    }

    static func inactiveReason(refineEnabled: Bool, translating: Bool, targetExcluded: Bool, hasCredentials: Bool) -> InactiveReason? {
        if targetExcluded { return .excludedApp }
        if !refineEnabled && !translating { return .refineOff }
        if !hasCredentials { return .noCredentials }
        return nil
    }

    /// 撮る（止めたときに使う）か。許可があり、ボタンがオンで、使われない理由がないとき
    static func shouldUse(permitted: Bool, buttonOn: Bool, inactive: InactiveReason?) -> Bool {
        permitted && buttonOn && inactive == nil
    }
}

// MARK: - 文脈に入らないときに外す（純粋な関数）

// 要件: REQ-DIC-041
// 設計判断: DEC-DIC-184
/// 文脈の小さいローカルの AI・fm で、入力が入りきらないとき、文字起こしを要約させる前に `<screen_ocr>` と、その注意を外す
enum ScreenOCRBudget {
    static func fit(system: String, userText: String, contextLength: Int, maxOutputTokens: Int,
                    countTokens: (String) async throws -> Int) async throws -> (system: String, userText: String) {
        guard let range = blockRange(in: userText) else { return (system, userText) }
        let available = contextLength - maxOutputTokens - LongInputFitter.margin
        if try await countTokens(system) + countTokens(userText) <= available { return (system, userText) }
        var user = userText
        user.removeSubrange(range)
        let instruction = ScreenContext.ocrInstruction
        let trimmedSystem = system.replacingOccurrences(of: instruction, with: "")
        appLog.notice("screen ocr: dropped to fit the context")
        return (trimmedSystem, user)
    }

    /// `<screen_ocr>` から `</screen_ocr>` と後ろの改行まで
    static func blockRange(in text: String) -> Range<String.Index>? {
        guard let start = text.range(of: "<screen_ocr>"),
              let end = text.range(of: "</screen_ocr>", range: start.upperBound..<text.endIndex)
        else { return nil }
        var upper = end.upperBound
        if upper < text.endIndex, text[upper] == "\n" { upper = text.index(after: upper) }
        return start.lowerBound..<upper
    }
}

// MARK: - 除くアプリ

// 要件: REQ-DIC-041
// 設計判断: DEC-DIC-181, DEC-DIC-182
enum ScreenSnapshotFilter {
    /// 設定によらず、いつも写さないもの（秘密が出るシステムの部分と、ノイズになる Dock）
    static let alwaysExcluded: Set<String> = [
        "com.apple.notificationcenterui",
        "com.apple.SecurityAgent",
        "com.apple.loginwindow",
        "com.apple.controlcenter",
        "com.apple.AutoFillPanelService",
        "com.apple.Safari.AutoFill",
        "com.apple.dock",
    ]
    /// Hanasu.app のバンドル ID（CLI で動かすときも、起動中の Hanasu.app の HUD・設定を写さない）
    static let hanasuBundleID = "dev.mactypeless.Hanasu"

    /// 写さないアプリか。excluded は除外アプリの設定（バンドル ID かアプリ名）
    static func isExcluded(bundleID: String?, appName: String?, pid: pid_t, excluded: [String]) -> Bool {
        if pid == ProcessInfo.processInfo.processIdentifier { return true }
        if let bundleID {
            if bundleID == hanasuBundleID || bundleID == Bundle.main.bundleIdentifier || alwaysExcluded.contains(bundleID) { return true }
        }
        let candidates = [bundleID, appName].compactMap { $0?.lowercased() }
        return excluded.contains { candidates.contains($0.lowercased()) }
    }
}

// MARK: - 画面収録の許可

// 要件: REQ-DIC-042
// 設計判断: DEC-DIC-189
enum ScreenRecordingPermission {
    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// macOS の許可のダイアログを出す。出ないとき（以前に拒否した）は false が返る
    @discardableResult
    static func request() -> Bool { CGRequestScreenCaptureAccess() }
}

// MARK: - 撮る・読む

// 要件: REQ-DIC-041
// 設計判断: DEC-DIC-181, DEC-DIC-183, DEC-DIC-187
enum ScreenSnapshotReader {
    struct Request: Sendable {
        /// 入力先のアプリ（録音を始めたときの前面のアプリ）
        var targetPID: pid_t?
        /// 除外アプリの設定（バンドル ID かアプリ名）
        var excludedApps: [String]
        /// OCR の言語（BCP 47）
        var languages: [String]
    }

    enum Failure: LocalizedError {
        case notPermitted
        var errorDescription: String? { tr("画面収録の許可がありません") }
    }

    /// すべての画面を撮って読み、行を返す。画像はこの中で捨てる
    static func read(_ request: Request) async throws -> [ScreenTextLine] {
        guard ScreenRecordingPermission.isGranted else { throw Failure.notPermitted }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let excluded = content.applications.filter {
            ScreenSnapshotFilter.isExcluded(bundleID: $0.bundleIdentifier, appName: $0.applicationName,
                                            pid: $0.processID, excluded: request.excludedApps)
        }
        let targetFrame = request.targetPID.flatMap { pid in
            content.windows.first { $0.owningApplication?.processID == pid && $0.isOnScreen && $0.windowLayer == 0 }?.frame
        }
        let displays = content.displays
        return try await withThrowingTaskGroup(of: [ScreenTextLine].self) { group in
            for (index, display) in displays.enumerated() {
                group.addTask {
                    let image = try await capture(display, excluding: excluded)
                    return try await recognize(image, displayFrame: display.frame, displayIndex: index,
                                               targetFrame: targetFrame, languages: request.languages)
                }
            }
            var lines: [ScreenTextLine] = []
            for try await part in group { lines += part }
            return lines
        }
    }

    /// 1 つの画面を、点の 2 倍の解像度で撮る（DEC-DIC-181）
    static func capture(_ display: SCDisplay, excluding apps: [SCRunningApplication]) async throws -> CGImage {
        let filter = SCContentFilter(display: display, excludingApplications: apps, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = display.width * 2
        configuration.height = display.height * 2
        configuration.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    /// 画像の文字を読む。座標を画面全体の点の座標に直し、入力先のウインドウの中かを決める
    static func recognize(_ image: CGImage, displayFrame: CGRect, displayIndex: Int, targetFrame: CGRect?,
                          languages: [String]) async throws -> [ScreenTextLine] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages.map { Locale.Language(identifier: $0) }
        let observations = try await request.perform(on: image)
        return observations.compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            // Vision の座標は 0〜1 で左下が原点。画面の点の座標（左上が原点）に直す
            let box = observation.boundingBox.cgRect
            let center = CGPoint(x: displayFrame.minX + box.midX * displayFrame.width,
                                 y: displayFrame.minY + (1 - box.midY) * displayFrame.height)
            return ScreenTextLine(text: text, display: displayIndex,
                                  inTarget: targetFrame?.contains(center) ?? false, y: center.y, x: center.x)
        }
    }

    /// OCR の言語。文字起こしの言語と英語。Vision が読める言語（`supported`）の中から選ぶ
    /// （Vision の中国語は zh-Hans・zh-Hant なので、zh-CN・zh-TW を書くと合わない。読めない言語を渡すと読み取りがまるごと失敗する）。
    /// 文字起こしの言語を読めなければ英語だけ
    static func languages(localeIdentifier: String, supported: [Locale.Language] = RecognizeTextRequest().supportedRecognitionLanguages) -> [String] {
        func pick(_ identifier: String) -> String? {
            let wanted = Locale.Language(identifier: identifier.replacingOccurrences(of: "_", with: "-"))
            guard let code = wanted.languageCode else { return nil }
            let sameCode = supported.filter { $0.languageCode == code }
            let script = wanted.maximalIdentifier.split(separator: "-").dropFirst().first.map(String.init)
            let match = sameCode.first { $0.maximalIdentifier.split(separator: "-").dropFirst().first.map(String.init) == script
                && $0.region == wanted.region } ?? sameCode.first {
                    $0.maximalIdentifier.split(separator: "-").dropFirst().first.map(String.init) == script
                } ?? sameCode.first
            return match.map { $0.minimalIdentifier }
        }
        var result: [String] = []
        if let own = pick(localeIdentifier) { result.append(own) }
        if !result.contains(where: { $0.lowercased().hasPrefix("en") }) { result.append(pick("en-US") ?? "en-US") }
        return result
    }
}

// MARK: - 録音中の非同期の読み取り

// 要件: REQ-DIC-041
// 設計判断: DEC-DIC-185, DEC-DIC-187
/// 録音と並べて撮って読み、止めたときに結果を受け取る。取り消せる
final class ScreenSnapshotCapture: Sendable {
    private struct State {
        var result: ScreenOCR??
        var task: Task<Void, Never>?
    }
    private let state = OSAllocatedUnfairLock(initialState: State(result: nil, task: nil))

    static func begin(_ request: ScreenSnapshotReader.Request, limit: Int) -> ScreenSnapshotCapture {
        let capture = ScreenSnapshotCapture()
        let task = Task.detached(priority: .userInitiated) {
            let started = Date()
            var ocr: ScreenOCR?
            do {
                let lines = try await ScreenSnapshotReader.read(request)
                ocr = ScreenSnapshotLayout.layout(lines, limit: limit)
                if let ocr {
                    appLog.notice("screen ocr: read \(lines.count, privacy: .public) lines -> terms=\(ocr.terms.count, privacy: .public) lines=\(ocr.lines.count, privacy: .public) chars=\(ocr.characterCount, privacy: .public), \(Date().timeIntervalSince(started), format: .fixed(precision: 2), privacy: .public)s")
                }
            } catch is CancellationError {
                return
            } catch {
                appLog.notice("screen ocr: failed (\(error.localizedDescription, privacy: .public))")
            }
            if Task.isCancelled { return }
            let finished = ocr.flatMap { $0.isEmpty ? nil : $0 }
            capture.state.withLock { $0.result = .some(finished) }
        }
        capture.state.withLock { $0.task = task }
        return capture
    }

    /// 作業を止めて、結果を捨てる
    func cancel() {
        state.withLock { state in
            state.task?.cancel()
            state.task = nil
            state.result = .some(nil)
        }
    }

    /// 読み終わっていれば結果を返す。まだなら少しだけ待ち、間に合わなければ nil（文字なしで進める）
    func result(waitingUpTo timeout: Duration = .seconds(2)) async -> ScreenOCR? {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while true {
            if let done = state.withLock({ $0.result }) { return done }
            if ContinuousClock.now >= deadline {
                appLog.notice("screen ocr: timed out")
                cancel()
                return nil
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}
