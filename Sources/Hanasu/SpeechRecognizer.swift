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

/// macOS 26 の SpeechAnalyzer で、マイク音声をオンデバイスで文字に起こす。
@MainActor
final class SpeechRecognizer {
    /// 確定済み＋途中のテキスト（HUD 表示用）
    var onPartialText: ((String) -> Void)?
    /// 音声モデルのダウンロード進捗（0...1）
    var onAssetDownloadProgress: ((Double) -> Void)?

    private var audioEngine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzerFormat: AVAudioFormat?
    private var resultsTask: Task<Void, Never>?
    private var finalizedText = ""
    private var volatileText = ""

    var isRunning: Bool { analyzer != nil }

    func start(localeIdentifier: String, engine: RecognizerEngine, contextualStrings: [String]) async throws {
        guard analyzer == nil else { throw SpeechRecognizerError.alreadyRunning }
        finalizedText = ""
        volatileText = ""

        let (module, results) = try await makeModule(localeIdentifier: localeIdentifier, engine: engine)
        try await ensureAssetsInstalled(for: module)

        let audioEngine = AVAudioEngine()
        let inputFormat = audioEngine.inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw SpeechRecognizerError.noInputDevice
        }
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

        let tap = Self.makeTapBlock(from: inputFormat, to: analyzerFormat, continuation: continuation)
        audioEngine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat, block: tap)
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            audioEngine.inputNode.removeTap(onBus: 0)
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
    }

    /// 録音を止め、残りの音声を確定させてから全文を返す。
    func stop() async -> String {
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

    // MARK: - Private

    private func stopAudio() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        if let continuation = inputContinuation, let format = analyzerFormat {
            // 末尾に無音を足すと、言い終わり直後に止めても最後の語まで確定しやすい
            Self.yieldSilence(to: continuation, format: format)
        }
        inputContinuation?.finish()
    }

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
        continuation: AsyncStream<AnalyzerInput>.Continuation
    ) -> AVAudioNodeTapBlock {
        let converter = inputFormat == outputFormat ? nil : AVAudioConverter(from: inputFormat, to: outputFormat)
        converter?.primeMethod = .none
        return { buffer, _ in
            guard let converter else {
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
                continuation.yield(AnalyzerInput(buffer: converted))
            }
        }
    }
}
