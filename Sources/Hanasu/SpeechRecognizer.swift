@preconcurrency import AVFoundation
import Foundation
import Speech

enum SpeechRecognizerError: LocalizedError {
    case unsupportedLocale(String)
    case noAudioFormat
    case noInputDevice
    case alreadyRunning

    var errorDescription: String? {
        switch self {
        case .unsupportedLocale(let id): "この言語（\(id)）は音声認識に対応していません"
        case .noAudioFormat: "音声認識モデルに合う音声形式が見つかりません"
        case .noInputDevice: "マイクが見つかりません"
        case .alreadyRunning: "すでに録音中です"
        }
    }
}

// 要件: REQ-COM-002
// 設計判断: DEC-DIC-001
/// macOS 26 の SpeechAnalyzer で、マイク音声をオンデバイスで文字に起こす。
@MainActor
final class SpeechRecognizer {
    /// 確定済み＋途中のテキスト（HUD 表示用）
    var onPartialText: ((String) -> Void)?
    /// 音声モデルのダウンロード進捗（0...1）
    var onAssetDownloadProgress: ((Double) -> Void)?
    /// 録音中の音量（0〜1。Whisper / Gemini で録っているときだけ、HUD の音量の目安に使う）
    var onLevel: ((Float) -> Void)?
    /// 録音を止めたあと、まとめて文字起こしを始めたとき（Whisper / Gemini）
    var onBatchTranscriptionStarted: ((TranscriptionEngine) -> Void)?
    /// 直近の stop() で文字起こしに失敗したときの理由（Whisper / Gemini）
    private(set) var lastError: String?

    private var audioEngine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzerFormat: AVAudioFormat?
    private var resultsTask: Task<Void, Never>?
    private var finalizedText = ""
    private var volatileText = ""
    /// 録音を残すときの書き出し先（履歴の「音声も残す」）
    private var audioWriter: DictationAudioWriter?

    /// Whisper / Gemini で録っている間の状態。録音を止めてからまとめて文字起こしする
    private var batch: BatchCapture?

    var isRunning: Bool { analyzer != nil || batch != nil }

    /// - Parameter transcription: 文字起こしのエンジン。Mac 標準以外では、engine（SpeechAnalyzer のモジュール）は使わない
    /// - Parameter inputDeviceUID: 使うマイクの UID。空ならシステムの設定に従う
    func start(localeIdentifier: String, engine: RecognizerEngine, contextualStrings: [String],
               audioFileURL: URL? = nil, transcription: TranscriptionEngine = .apple,
               inputDeviceUID: String = "") async throws {
        guard analyzer == nil, batch == nil else { throw SpeechRecognizerError.alreadyRunning }
        finalizedText = ""
        volatileText = ""
        lastError = nil
        if transcription != .apple {
            try startBatch(engine: transcription, hints: contextualStrings, audioFileURL: audioFileURL,
                           inputDeviceUID: inputDeviceUID)
            return
        }

        let (module, results) = try await makeModule(localeIdentifier: localeIdentifier, engine: engine)
        try await ensureAssetsInstalled(for: module)

        let (audioEngine, inputFormat) = try Self.makeInputEngine(uid: inputDeviceUID)
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [module], considering: inputFormat)
        else { throw SpeechRecognizerError.noAudioFormat }

        let analyzer = SpeechAnalyzer(modules: [module])
        if !contextualStrings.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = contextualStrings
            // 語彙ヒントに対応しないモジュールもあるので、失敗しても続ける
            try? await analyzer.setContext(context)
        }
        try await analyzer.prepareToAnalyze(in: analyzerFormat)

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        resultsTask = Task { [weak self] in
            do {
                for try await (text, isFinal) in results {
                    self?.receive(text: text, isFinal: isFinal)
                }
            } catch {
                appLog.error("speech results error: \(String(describing: error), privacy: .public)")
            }
        }
        try await analyzer.start(inputSequence: stream)

        // 録音を残せなくても、音声入力は続ける
        let writer = audioFileURL.flatMap { try? DictationAudioWriter(url: $0, format: analyzerFormat) }
        let tap = Self.makeTapBlock(from: inputFormat, to: analyzerFormat, continuation: continuation, writer: writer)
        audioEngine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat, block: tap)
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            audioEngine.inputNode.removeTap(onBus: 0)
            writer?.close()
            continuation.finish()
            await analyzer.cancelAndFinishNow()
            resultsTask?.cancel()
            resultsTask = nil
            throw error
        }

        self.audioEngine = audioEngine
        self.analyzer = analyzer
        self.inputContinuation = continuation
        self.analyzerFormat = analyzerFormat
        self.audioWriter = writer
    }

    // 要件: REQ-DIC-140
    // 設計判断: DEC-DIC-141
    /// 録音中にマイクを切り替える。それまでの音声と認識の途中経過はそのまま続く。
    /// 選んだマイクを動かせなければシステムの設定のマイクに戻し、それもだめならエラーにする。
    func switchInput(to uid: String) throws {
        if let batch {
            try batch.switchInput(to: uid)
            return
        }
        guard let audioEngine, let continuation = inputContinuation, let analyzerFormat else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        self.audioEngine = nil
        let writer = audioWriter
        let makeTap = { (format: AVAudioFormat) in
            Self.makeTapBlock(from: format, to: analyzerFormat, continuation: continuation, writer: writer)
        }
        self.audioEngine = try Self.startInputWithFallback(uid: uid, makeTap: makeTap)
    }

    // 設計判断: DEC-DIC-003
    /// 録音を止め、残りの音声を確定させてから全文を返す。
    func stop() async -> String {
        if batch != nil { return await stopBatch() }
        guard let analyzer else { return "" }
        stopAudio()
        do {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            appLog.error("finalize error: \(String(describing: error), privacy: .public)")
        }
        await resultsTask?.value
        let text = (finalizedText + volatileText).trimmingCharacters(in: .whitespacesAndNewlines)
        reset()
        return text
    }

    func cancel() async {
        if let batch {
            batch.stopAudio()
            self.batch = nil
            return
        }
        guard let analyzer else { return }
        stopAudio()
        await analyzer.cancelAndFinishNow()
        resultsTask?.cancel()
        reset()
    }

    /// 音声ファイルを文字に起こす（動作確認用。マイクの代わりにファイルを同じ経路へ流す）
    func transcribeFile(at url: URL, localeIdentifier: String, engine: RecognizerEngine) async throws -> String {
        finalizedText = ""
        volatileText = ""
        let (module, results) = try await makeModule(localeIdentifier: localeIdentifier, engine: engine)
        try await ensureAssetsInstalled(for: module)

        let file = try AVAudioFile(forReading: url)
        let inputFormat = file.processingFormat
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [module], considering: inputFormat)
        else { throw SpeechRecognizerError.noAudioFormat }

        let analyzer = SpeechAnalyzer(modules: [module])
        try await analyzer.prepareToAnalyze(in: analyzerFormat)
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let resultsTask = Task { [weak self] in
            do {
                for try await (text, isFinal) in results { self?.receive(text: text, isFinal: isFinal) }
            } catch {
                appLog.error("speech results error: \(String(describing: error), privacy: .public)")
            }
        }
        try await analyzer.start(inputSequence: stream)

        let tap = Self.makeTapBlock(from: inputFormat, to: analyzerFormat, continuation: continuation)
        let time = AVAudioTime(sampleTime: 0, atRate: inputFormat.sampleRate)
        while file.framePosition < file.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 4096) else { break }
            try file.read(into: buffer)
            if buffer.frameLength == 0 { break }
            tap(buffer, time)
        }
        Self.yieldSilence(to: continuation, format: analyzerFormat)
        continuation.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        await resultsTask.value
        return (finalizedText + volatileText).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Whisper / Gemini（録音を止めてからまとめて文字起こしする）

    // 設計判断: DEC-DIC-100, DEC-DIC-102
    private func startBatch(engine: TranscriptionEngine, hints: [String], audioFileURL: URL?, inputDeviceUID: String) throws {
        let settings = AppSettings.shared
        switch engine {
        case .whisper:
            let model = settings.whisperModel
            guard WhisperModelStore.isDownloaded(model) else {
                // まだなら、ここでダウンロードを始めておく
                WhisperModelStore.shared.ensureDownloaded(model)
                throw BatchTranscriptionError.whisperModelMissing(model)
            }
            // 録音している間に読み込んでおくと、止めてからの待ち時間が短くなる
            Task.detached { await WhisperEngine.shared.preload(model) }
        case .gemini:
            guard try GeminiTranscriber.auth(settings: settings) != nil else { throw BatchTranscriptionError.noCredentials }
        case .apple:
            break
        }
        let capture = BatchCapture(engine: engine, hints: hints)
        try capture.start(inputDeviceUID: inputDeviceUID, audioFileURL: audioFileURL) { [weak self] level in self?.onLevel?(level) }
        batch = capture
    }

    // 設計判断: DEC-DIC-100
    private func stopBatch() async -> String {
        guard let batch else { return "" }
        self.batch = nil
        let samples = batch.stopAudio()
        // 0.3 秒に満たないものは、押し間違いとみなす
        guard Double(samples.count) / TranscriptionAudio.sampleRate >= 0.3 else { return "" }
        onBatchTranscriptionStarted?(batch.engine)
        let started = Date()
        do {
            let text = try await BatchTranscriber.transcribeText(
                samples, engine: batch.engine, settings: AppSettings.shared, hints: batch.hints)
            appLog.notice("batch transcription (\(batch.engine.rawValue, privacy: .public)): \(text.count) chars in \(Date().timeIntervalSince(started), format: .fixed(precision: 1))s")
            return text
        } catch {
            appLog.error("batch transcription failed: \(String(describing: error), privacy: .public)")
            lastError = "\(batch.engine.shortName) で文字起こしできませんでした: \(error.localizedDescription)"
            return ""
        }
    }

    // MARK: - マイク

    // 設計判断: DEC-DIC-140, DEC-MTG-004
    /// 選んだマイク（空ならシステムの設定）を入力にしたエンジンと、タップに使う形式。
    /// 選んだマイクがつながっていなければ、システムの設定のマイクになる（MeetingRecorder.makeMicEngine）。
    nonisolated static func makeInputEngine(uid: String) throws -> (AVAudioEngine, AVAudioFormat) {
        let engine = MeetingRecorder.makeMicEngine(inputDeviceUID: uid)
        // 機器を指定すると outputFormat は前の機器のままなので、機器側の実際の形式を使う。
        // 指定しないときは、これまでどおり outputFormat を使う
        let format = uid.isEmpty ? engine.inputNode.outputFormat(forBus: 0) : engine.inputNode.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw SpeechRecognizerError.noInputDevice }
        return (engine, format)
    }

    /// 選んだマイクでタップを付けて動かす
    nonisolated static func startInput(uid: String, makeTap: (AVAudioFormat) -> AVAudioNodeTapBlock) throws -> AVAudioEngine {
        let (engine, format) = try makeInputEngine(uid: uid)
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format, block: makeTap(format))
        engine.prepare()
        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            throw error
        }
        appLog.notice("dictation mic: \(uid.isEmpty ? "system" : uid, privacy: .public) \(format.sampleRate, privacy: .public)Hz \(format.channelCount)ch")
        return engine
    }

    // 設計判断: DEC-DIC-141
    /// 録音の途中で切り替えるとき。選んだマイクを動かせなければ、システムの設定のマイクでやり直す
    nonisolated static func startInputWithFallback(uid: String, makeTap: (AVAudioFormat) -> AVAudioNodeTapBlock) throws -> AVAudioEngine {
        do {
            return try startInput(uid: uid, makeTap: makeTap)
        } catch where !uid.isEmpty {
            appLog.error("dictation mic switch failed (\(uid, privacy: .public)): \(String(describing: error), privacy: .public); falling back to system")
            return try startInput(uid: "", makeTap: makeTap)
        }
    }

    // MARK: - Private

    private func stopAudio() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioWriter?.close()
        audioWriter = nil
        if let continuation = inputContinuation, let format = analyzerFormat {
            // 末尾に無音を足すと、言い終わり直後に止めても最後の語まで確定しやすい
            Self.yieldSilence(to: continuation, format: format)
        }
        inputContinuation?.finish()
    }

    // 設計判断: DEC-DIC-003
    private nonisolated static func yieldSilence(
        to continuation: AsyncStream<AnalyzerInput>.Continuation, format: AVAudioFormat, seconds: Double = 0.6
    ) {
        let frames = AVAudioFrameCount(format.sampleRate * seconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        buffer.frameLength = frames
        for audioBuffer in UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList) {
            if let data = audioBuffer.mData { memset(data, 0, Int(audioBuffer.mDataByteSize)) }
        }
        continuation.yield(AnalyzerInput(buffer: buffer))
    }

    private func reset() {
        audioEngine = nil
        analyzer = nil
        inputContinuation = nil
        analyzerFormat = nil
        resultsTask = nil
    }

    private func receive(text: String, isFinal: Bool) {
        if isFinal {
            finalizedText += text
            volatileText = ""
        } else {
            volatileText = text
        }
        onPartialText?(finalizedText + volatileText)
    }

    /// 選んだエンジンの SpeechModule と、(テキスト, 確定か) の結果ストリームを作る。
    private func makeModule(localeIdentifier: String, engine: RecognizerEngine) async throws
        -> (any SpeechModule, AsyncThrowingStream<(String, Bool), Error>)
    {
        let requested = Locale(identifier: localeIdentifier)
        switch engine {
        case .dictation:
            guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: requested) else {
                throw SpeechRecognizerError.unsupportedLocale(localeIdentifier)
            }
            let transcriber = DictationTranscriber(
                locale: locale,
                contentHints: [],
                transcriptionOptions: [.punctuation],
                reportingOptions: [.volatileResults],
                attributeOptions: [])
            return (transcriber, Self.map(transcriber.results) { (String($0.text.characters), $0.isFinal) })
        case .speech:
            guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else {
                throw SpeechRecognizerError.unsupportedLocale(localeIdentifier)
            }
            let transcriber = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults],
                attributeOptions: [])
            return (transcriber, Self.map(transcriber.results) { (String($0.text.characters), $0.isFinal) })
        }
    }

    private nonisolated static func map<S: AsyncSequence & Sendable>(
        _ sequence: S, _ transform: @escaping @Sendable (S.Element) -> (String, Bool)
    ) -> AsyncThrowingStream<(String, Bool), Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await element in sequence {
                        continuation.yield(transform(element))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func ensureAssetsInstalled(for module: any SpeechModule) async throws {
        if await AssetInventory.status(forModules: [module]) == .installed { return }
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) else {
            return  // インストール済み
        }
        onAssetDownloadProgress?(0)
        let progress = request.progress
        let observation = progress.observe(\.fractionCompleted) { [weak self] p, _ in
            let fraction = p.fractionCompleted
            Task { @MainActor in self?.onAssetDownloadProgress?(fraction) }
        }
        defer { observation.invalidate() }
        try await request.downloadAndInstall()
    }

    /// オーディオスレッドで呼ばれるタップ。MainActor に触れないよう static で作る。
    private nonisolated static func makeTapBlock(
        from inputFormat: AVAudioFormat,
        to outputFormat: AVAudioFormat,
        continuation: AsyncStream<AnalyzerInput>.Continuation,
        writer: DictationAudioWriter? = nil
    ) -> AVAudioNodeTapBlock {
        let converter = inputFormat == outputFormat ? nil : AVAudioConverter(from: inputFormat, to: outputFormat)
        converter?.primeMethod = .none
        return { buffer, _ in
            guard let converter else {
                writer?.write(buffer)
                continuation.yield(AnalyzerInput(buffer: buffer))
                return
            }
            let ratio = outputFormat.sampleRate / inputFormat.sampleRate
            let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
            guard let converted = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }
            var consumed = false
            var error: NSError?
            converter.convert(to: converted, error: &error) { _, status in
                if consumed {
                    status.pointee = .noDataNow
                    return nil
                }
                consumed = true
                status.pointee = .haveData
                return buffer
            }
            if error == nil, converted.frameLength > 0 {
                writer?.write(converted)
                continuation.yield(AnalyzerInput(buffer: converted))
            }
        }
    }
}

/// Whisper / Gemini 用に、マイクの音声を 16 kHz モノラルでためておく。音量は 0.1 秒ごとに知らせる
@MainActor
private final class BatchCapture {
    let engine: TranscriptionEngine
    let hints: [String]
    private var audioEngine: AVAudioEngine?
    private let box = SampleBox()
    private var writer: DictationAudioWriter?
    private var levelTimer: Timer?

    init(engine: TranscriptionEngine, hints: [String]) {
        self.engine = engine
        self.hints = hints
    }

    func start(inputDeviceUID: String, audioFileURL: URL?, onLevel: @escaping (Float) -> Void) throws {
        // 録音を残せなくても、音声入力は続ける
        let writer = audioFileURL.flatMap { try? DictationAudioWriter(url: $0, format: TranscriptionAudio.format) }
        do {
            audioEngine = try SpeechRecognizer.startInput(uid: inputDeviceUID, makeTap: makeTap(writer: writer))
        } catch {
            writer?.close()
            throw error
        }
        self.writer = writer
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [box] _ in
            let level = box.level
            MainActor.assumeIsolated { onLevel(level) }
        }
    }

    // 設計判断: DEC-DIC-141
    /// 録音中にマイクを切り替える。ためた音声と書き出し中のファイルは続けて使う
    func switchInput(to uid: String) throws {
        stopEngine()
        audioEngine = try SpeechRecognizer.startInputWithFallback(uid: uid, makeTap: makeTap(writer: writer))
    }

    /// 16 kHz モノラルに変換してためるタップ。機器ごとに形式が違うので、変換器はタップごとに作る
    private func makeTap(writer: DictationAudioWriter?) -> (AVAudioFormat) -> AVAudioNodeTapBlock {
        let box = self.box
        return { _ in
            let converter = BatchSampleConverter()
            return { buffer, _ in
                guard let converted = converter.convertToBuffer(buffer) else { return }
                writer?.write(converted)
                box.append(converted)
            }
        }
    }

    private func stopEngine() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
    }

    /// 録音を止め、ためた音声を返す
    @discardableResult
    func stopAudio() -> [Float] {
        levelTimer?.invalidate()
        levelTimer = nil
        stopEngine()
        writer?.close()
        writer = nil
        return box.samples
    }
}

/// オーディオスレッドから音声を足していく入れ物
private final class SampleBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _samples: [Float] = []
    private var _level: Float = 0

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let chunk = UnsafeBufferPointer(start: data, count: Int(buffer.frameLength))
        let rms = TranscriptionAudio.rms(chunk)
        lock.withLock {
            _samples.append(contentsOf: chunk)
            _level = rms
        }
    }

    var samples: [Float] { lock.withLock { _samples } }
    var level: Float { lock.withLock { _level } }
}
