@preconcurrency import AVFoundation
import Foundation
import Speech

// 要件: REQ-MTG-002, REQ-MTG-003, REQ-MTG-023
// 設計判断: DEC-MTG-005
/// 会議の 1 チャンネル（自分／相手）分の音声を、文字起こししながら音声ファイルにも書き出す。
/// append はオーディオスレッドなど任意のスレッドから呼んでよい（内部のキューで順番に処理する）。
final class ChannelTranscriber: @unchecked Sendable {
    let channel: MeetingChannel
    /// 確定した発話（メインスレッドで呼ばれる）
    var onPhrase: (@MainActor (TranscribedPhrase) -> Void)?
    /// 途中結果（メインスレッドで呼ばれる）
    var onVolatile: (@MainActor (String) -> Void)?

    private let queue: DispatchQueue
    private let inputFormat: AVAudioFormat
    private let fileURL: URL?
    /// このチャンネルの音声が、録音開始から何秒後に始まったか
    private var timeOffset: Double?
    private let meetingStart: Date
    /// false なら文字起こしはせず、音声ファイルに書き出すだけ（Whisper / Gemini では記録のあとにまとめて文字起こしする）
    let live: Bool

    private var analyzer: SpeechAnalyzer?
    private var analyzerFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?
    private let levelLock = NSLock()
    private var _level: Float = 0
    private var _lastSoundAt: Date?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var file: AVAudioFile?
    private var phrases: [TranscribedPhrase] = []
    /// 書いた（文字起こしに渡した）音声の長さ（秒）
    private var writtenSeconds: Double = 0

    /// - Parameter fixedTimeOffset: 録音開始からのずれが分かっている場合（ファイル入力など）に指定する
    init(channel: MeetingChannel, inputFormat: AVAudioFormat, fileURL: URL?, meetingStart: Date, fixedTimeOffset: Double? = nil,
         live: Bool = true) {
        self.channel = channel
        self.live = live
        self.inputFormat = inputFormat
        self.fileURL = fileURL
        self.meetingStart = meetingStart
        self.timeOffset = fixedTimeOffset
        self.queue = DispatchQueue(label: "Hanasu.ChannelTranscriber.\(channel.rawValue)")
    }

    /// モデルの準備と解析の開始。append より前に呼ぶ。
    func prepare(localeIdentifier: String, contextualStrings: [String]) async throws {
        guard live else {
            // 書き出すだけ。あとで読み直す Whisper / Gemini に合わせて 16 kHz モノラルにする
            let format = TranscriptionAudio.format
            file = try fileURL.map { try Self.makeFile(url: $0, format: format) }
            queue.sync { self.analyzerFormat = format }
            return
        }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: localeIdentifier)) else {
            throw SpeechRecognizerError.unsupportedLocale(localeIdentifier)
        }
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange])
        try await SpeechAssets.ensureInstalled(for: transcriber)

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber], considering: inputFormat)
        else { throw SpeechRecognizerError.noAudioFormat }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        if !contextualStrings.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = contextualStrings
            try? await analyzer.setContext(context)
        }
        try await analyzer.prepareToAnalyze(in: format)

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let channel = self.channel
        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard let self else { return }
                    if result.isFinal {
                        self.receiveFinal(result.text, range: result.range)
                    } else {
                        let text = String(result.text.characters)
                        let onVolatile = self.onVolatile
                        await MainActor.run { onVolatile?(text) }
                    }
                }
            } catch {
                appLog.error("meeting \(channel.rawValue, privacy: .public) results error: \(String(describing: error), privacy: .public)")
            }
        }
        try await analyzer.start(inputSequence: stream)

        if let fileURL {
            file = try Self.makeFile(url: fileURL, format: format)
        }

        queue.sync {
            self.analyzer = analyzer
            self.analyzerFormat = format
            self.continuation = continuation
        }
    }

    private static func makeFile(url: URL, format: AVAudioFormat) throws -> AVAudioFile {
        try AVAudioFile(
            forWriting: url,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount,
                AVEncoderBitRateKey: 32000,
            ],
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved)
    }

    /// このチャンネルの音声（音声ファイルの先頭）が、録音開始から何秒後に始まったか。
    /// 記録のあとに音声ファイルから文字起こしするとき、時刻をそろえるのに使う
    var audioStartOffset: Double { queue.sync { timeOffset ?? 0 } }

    // 設計判断: DEC-MTG-088
    /// ここまでに書いた音声の終わりが、録音開始からの時刻で何秒か（音声の時間軸。スリープの時間は入らない）。
    /// まだ音声が届いていなければ nil
    var audioEnd: Double? { queue.sync { timeOffset.map { $0 + writtenSeconds } } }

    // 設計判断: DEC-MTG-006
    func append(_ buffer: AVAudioPCMBuffer) {
        queue.async { [self] in
            guard live ? continuation != nil : file != nil,
                  let analyzerFormat, let converted = convert(buffer, to: analyzerFormat) else { return }
            if timeOffset == nil {
                let duration = Double(buffer.frameLength) / buffer.format.sampleRate
                timeOffset = max(0, Date().timeIntervalSince(meetingStart) - duration)
            }
            do {
                try file?.write(from: converted)
            } catch {
                appLog.error("meeting audio write error: \(error.localizedDescription, privacy: .public)")
            }
            writtenSeconds += Double(converted.frameLength) / converted.format.sampleRate
            measureLevel(converted)
            continuation?.yield(AnalyzerInput(buffer: converted))
        }
    }

    /// 直近のバッファの音量（0〜1。RMS）
    var level: Float { levelLock.withLock { _level } }
    /// 最後に音（無音でない入力）があった時刻。まだ一度もなければ nil
    var lastSoundAt: Date? { levelLock.withLock { _lastSoundAt } }

    private func measureLevel(_ buffer: AVAudioPCMBuffer) {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        var sum: Float = 0
        if let data = buffer.floatChannelData?[0] {
            for i in 0..<frames { sum += data[i] * data[i] }
        } else if let data = buffer.int16ChannelData?[0] {
            for i in 0..<frames { let v = Float(data[i]) / 32768; sum += v * v }
        } else {
            return
        }
        let rms = (sum / Float(frames)).squareRoot()
        levelLock.withLock {
            _level = rms
            if rms > 0.003 { _lastSoundAt = Date() }  // 約 -50 dBFS より大きければ音あり
        }
    }

    /// 入力を締め切り、残りの音声を確定させて、全発話を返す。
    func finish() async -> [TranscribedPhrase] {
        let analyzer: SpeechAnalyzer? = queue.sync {
            if let continuation, let analyzerFormat {
                continuation.yield(AnalyzerInput(buffer: Self.silence(format: analyzerFormat, seconds: 0.6)))
                continuation.finish()
            }
            continuation = nil
            file = nil  // 解放でファイルを閉じる
            return self.analyzer
        }
        if let analyzer {
            do {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            } catch {
                appLog.error("meeting finalize error: \(String(describing: error), privacy: .public)")
            }
        }
        await resultsTask?.value
        return queue.sync { phrases }
    }

    func cancel() async {
        let analyzer: SpeechAnalyzer? = queue.sync {
            continuation?.finish()
            continuation = nil
            file = nil
            return self.analyzer
        }
        await analyzer?.cancelAndFinishNow()
        resultsTask?.cancel()
    }

    // MARK: - Private

    private func receiveFinal(_ text: AttributedString, range: CMTimeRange) {
        var words: [TimedWord] = []
        let offset = queue.sync { timeOffset ?? 0 }
        for run in text.runs {
            let piece = String(text[run.range].characters)
            guard !piece.isEmpty else { continue }
            if let timeRange = run.audioTimeRange, timeRange.isValid {
                words.append(TimedWord(
                    text: piece,
                    start: offset + timeRange.start.seconds,
                    end: offset + timeRange.end.seconds))
            } else if var last = words.popLast() {
                // 時刻のない部分（句読点など）は直前の語にくっつける
                last.text += piece
                words.append(last)
            } else {
                words.append(TimedWord(text: piece, start: offset + range.start.seconds, end: offset + range.start.seconds))
            }
        }
        let plain = String(text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plain.isEmpty else { return }
        let phrase = TranscribedPhrase(
            channel: channel,
            start: words.first?.start ?? offset + range.start.seconds,
            end: words.last?.end ?? offset + range.end.seconds,
            text: plain,
            words: words)
        queue.sync { phrases.append(phrase) }
        let onPhrase = self.onPhrase
        Task { @MainActor in onPhrase?(phrase) }
    }

    private func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        // 入力の形式が変わったら（機器の切り替えなど）変換器を作り直す
        if converterInputFormat != buffer.format {
            converterInputFormat = buffer.format
            converter = buffer.format == format ? nil : AVAudioConverter(from: buffer.format, to: format)
            converter?.primeMethod = .none
            // 書き出すだけのときは、相手側（ステレオのことが多い）を左右まとめてモノラルにする
            if !live { converter?.downmix = true }
        }
        guard let converter else { return buffer }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil && output.frameLength > 0 ? output : nil
    }

    static func silence(format: AVAudioFormat, seconds: Double) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(format.sampleRate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for audioBuffer in UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList) {
            if let data = audioBuffer.mData { memset(data, 0, Int(audioBuffer.mDataByteSize)) }
        }
        return buffer
    }
}

// 設計判断: DEC-DIC-004
/// オンデバイス音声モデルの準備（未インストールならダウンロード）
enum SpeechAssets {
    static func ensureInstalled(for module: any SpeechModule, progress: (@Sendable (Double) -> Void)? = nil) async throws {
        if await AssetInventory.status(forModules: [module]) == .installed { return }
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) else { return }
        progress?(0)
        let observation = request.progress.observe(\.fractionCompleted) { p, _ in progress?(p.fractionCompleted) }
        defer { observation.invalidate() }
        try await request.downloadAndInstall()
    }
}
