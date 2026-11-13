@preconcurrency import AVFoundation
import Foundation
import Speech

// 要件: REQ-MTG-002, REQ-MTG-003, REQ-MTG-023, REQ-MTG-128
// 設計判断: DEC-MTG-005, DEC-MTG-152, DEC-MTG-156
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
    private let realtimeAudio: Bool

    private var analyzer: SpeechAnalyzer?
    private var analyzerFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?
    private let levelLock = NSLock()
    private var _level: Float = 0
    private var _lastSoundAt: Date?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    // 設計判断: DEC-MTG-156
    /// 録音の書き出し。閉じたら nil（書き出しの失敗を読むための参照は levelLock の _writer に残す）
    private var file: MeetingAudioWriter?
    private var _writer: MeetingAudioWriter?
    // 設計判断: DEC-MTG-157
    private var _knownStartOffset: Double?
    // 設計判断: DEC-MTG-158
    /// 文字起こしの結果（途中結果を含む）が、このチャンネルの音声のどこまで進んだか（秒）
    private var _analyzedSeconds: Double = 0
    private var phrases: [TranscribedPhrase] = []
    /// 書いた（文字起こしに渡した）音声の長さ（秒）
    private var writtenSeconds: Double = 0
    // 設計判断: DEC-MTG-152
    /// 文字起こしに渡す前にためている音声（analyzerChunkSeconds たまったら渡す）
    private var pendingInput: AVAudioPCMBuffer?
    /// 文字起こしに 1 回で渡す音声の長さ（秒）。SpeechAnalyzer は渡した回数ぶんの記録を最後まで持つので、
    /// 約 10 ms ごとに届くバッファをそのまま渡さず、まとめて回数を減らす
    static let analyzerChunkSeconds = 0.2

    /// - Parameter fixedTimeOffset: 録音開始からのずれが分かっている場合（ファイル入力など）に指定する
    /// - Parameter realtimeAudio: 実時間の音か（記録中）。ファイルから流すときは false（録音の書き出しが追いつくのを待つ。DEC-MTG-156）
    init(channel: MeetingChannel, inputFormat: AVAudioFormat, fileURL: URL?, meetingStart: Date, fixedTimeOffset: Double? = nil,
         live: Bool = true, realtimeAudio: Bool = true) {
        self.channel = channel
        self.live = live
        self.realtimeAudio = realtimeAudio
        self.inputFormat = inputFormat
        self.fileURL = fileURL
        self.meetingStart = meetingStart
        self.timeOffset = fixedTimeOffset
        self._knownStartOffset = fixedTimeOffset
        self.queue = DispatchQueue(label: "Hanasu.ChannelTranscriber.\(channel.rawValue)")
    }

    /// モデルの準備と解析の開始。append より前に呼ぶ。
    func prepare(localeIdentifier: String, contextualStrings: [String]) async throws {
        guard live else {
            // 書き出すだけ。あとで読み直す Whisper / Gemini に合わせて 16 kHz モノラルにする
            let format = TranscriptionAudio.format
            let writer = try fileURL.map { try MeetingAudioWriter(url: $0, format: format, realtime: realtimeAudio) }
            levelLock.withLock { _writer = writer }
            queue.sync {
                self.file = writer
                self.analyzerFormat = format
            }
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
                    let reached = max(result.range.end.seconds, result.resultsFinalizationTime.seconds)
                    if reached.isFinite { self.levelLock.withLock { self._analyzedSeconds = max(self._analyzedSeconds, reached) } }
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
                // 要件: REQ-MTG-010
                // 設計判断: DEC-MTG-009（認識が途中で止まったチャンネルは、録音を消さない。取り消しは数えない）
                if !(error is CancellationError) { self?.markRecognitionFailed() }
            }
        }
        try await analyzer.start(inputSequence: stream)

        let writer = try fileURL.map { try MeetingAudioWriter(url: $0, format: format, realtime: realtimeAudio) }
        levelLock.withLock { _writer = writer }

        queue.sync {
            self.file = writer
            self.analyzer = analyzer
            self.analyzerFormat = format
            self.continuation = continuation
        }
    }

    /// このチャンネルの音声（音声ファイルの先頭）が、録音開始から何秒後に始まったか。
    /// 記録のあとに音声ファイルから文字起こしするとき、時刻をそろえるのに使う
    var audioStartOffset: Double { queue.sync { timeOffset ?? 0 } }

    // 要件: REQ-MTG-128
    // 設計判断: DEC-MTG-157
    /// 先頭のずれが分かっていればその値（まだ音が届いていなければ nil）。queue を待たずに読める（メインスレッドの記録中の保存で使う）
    var knownStartOffset: Double? { levelLock.withLock { _knownStartOffset } }

    // 要件: REQ-MTG-128
    // 設計判断: DEC-MTG-156
    /// 記録中に録音の一部を書けなかった（ディスクがいっぱいなど）
    var audioWriteFailed: Bool { levelLock.withLock { _writer }?.failure != nil }

    // 要件: REQ-MTG-010
    // 設計判断: DEC-MTG-009
    /// 記録中に認識の結果のストリームがエラーで止まった（取り消しを除く）。止めるときの締めのエラーは数えない
    var recognitionFailed: Bool { queue.sync { failed } }
    private var failed = false
    private func markRecognitionFailed() { queue.sync { failed = true } }

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
                let offset = max(0, Date().timeIntervalSince(meetingStart) - duration)
                timeOffset = offset
                levelLock.withLock { _knownStartOffset = offset }
            }
            // 設計判断: DEC-MTG-156（写して書き出しのキューに渡すだけ。ここでは待たない）
            file?.append(converted)
            writtenSeconds += Double(converted.frameLength) / converted.format.sampleRate
            measureLevel(converted)
            enqueueForAnalyzer(converted)
        }
    }

    // 設計判断: DEC-MTG-152
    /// 文字起こしに渡す音声を analyzerChunkSeconds ずつにまとめて渡す（queue の上で呼ぶ）。
    /// 音声の順番と長さは変えないので、時刻はまとめないときと同じ
    private func enqueueForAnalyzer(_ buffer: AVAudioPCMBuffer) {
        guard let continuation else { return }
        if let pendingInput, !Self.appendFrames(of: buffer, to: pendingInput) {
            // 入らない（形式が変わった・容量が足りない）ときは、たまった分を先に渡す
            flushPendingInput()
        }
        if pendingInput == nil {
            guard let fresh = AVAudioPCMBuffer(pcmFormat: buffer.format,
                                               frameCapacity: Self.chunkFrames(buffer.format) + buffer.frameLength),
                  Self.appendFrames(of: buffer, to: fresh)
            else {
                continuation.yield(AnalyzerInput(buffer: buffer))
                return
            }
            pendingInput = fresh
        }
        if let pendingInput, pendingInput.frameLength >= Self.chunkFrames(pendingInput.format) {
            flushPendingInput()
        }
    }

    /// ためている音声を文字起こしに渡す（queue の上で呼ぶ）
    private func flushPendingInput() {
        if let pendingInput, pendingInput.frameLength > 0 {
            continuation?.yield(AnalyzerInput(buffer: pendingInput))
        }
        pendingInput = nil
    }

    private static func chunkFrames(_ format: AVAudioFormat) -> AVAudioFrameCount {
        AVAudioFrameCount((format.sampleRate * analyzerChunkSeconds).rounded(.up))
    }

    /// buffer の音声を target の末尾に写す。形式が違うか、入りきらなければ false（target は変えない）
    static func appendFrames(of buffer: AVAudioPCMBuffer, to target: AVAudioPCMBuffer) -> Bool {
        guard buffer.format == target.format,
              target.frameLength + buffer.frameLength <= target.frameCapacity else { return false }
        let bytesPerFrame = Int(target.format.streamDescription.pointee.mBytesPerFrame)
        guard bytesPerFrame > 0 else { return false }
        let from = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
        let to = UnsafeMutableAudioBufferListPointer(target.mutableAudioBufferList)
        guard from.count == to.count else { return false }
        let offset = Int(target.frameLength) * bytesPerFrame
        let length = Int(buffer.frameLength) * bytesPerFrame
        for (src, dst) in zip(from, to) {
            guard let srcData = src.mData, let dstData = dst.mData else { return false }
            memcpy(dstData.advanced(by: offset), srcData, length)
        }
        target.frameLength += buffer.frameLength
        for index in 0..<to.count { to[index].mDataByteSize = UInt32(Int(target.frameLength) * bytesPerFrame) }
        return true
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
            flushPendingInput()
            if let continuation, let analyzerFormat {
                continuation.yield(AnalyzerInput(buffer: Self.silence(format: analyzerFormat, seconds: 0.6)))
                continuation.finish()
            }
            continuation = nil
            return self.analyzer
        }
        await closeAudioFile()
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

    // 要件: REQ-MTG-128
    // 設計判断: DEC-MTG-158
    /// 音声ファイルを文字起こしに流して、全発話を返す（録音から作り直すときと、--meeting-files で使う）。
    /// 文字起こし（SpeechAnalyzer）は渡した音を自分の中にためるので、ファイルを一度に流すと長い録音ではメモリを使い切る。
    /// 10 秒ぶん流すごとに、文字起こしが 30 秒ぶんより後ろにいれば追いつくのを待つ（無音の間は結果が出ず進み具合が分からないので、
    /// 進まないまま 0.5 秒たったら続ける）。読んでいる途中で読めなくなったら（落ちた録音の終わりなど）、そこまでを使う
    /// - Parameters:
    ///   - offset: 音声ファイルの先頭が、録音開始から何秒後か
    ///   - live: false なら文字起こしせず、writingTo に書き出すだけ（Whisper / Gemini はあとでファイルから文字起こしする）
    ///   - writingTo: 流した音を書き出す録音のファイル（nil なら書かない）
    /// - Returns: 発話・認識が途中で止まったか・流した音の長さ（秒）
    static func transcribe(file url: URL, channel: MeetingChannel, offset: Double, live: Bool, writingTo: URL? = nil,
                           localeIdentifier: String, contextualStrings: [String])
        async throws -> (phrases: [TranscribedPhrase], recognitionFailed: Bool, seconds: Double)
    {
        let file = try AVAudioFile(forReading: url)
        let transcriber = ChannelTranscriber(
            channel: channel, inputFormat: file.processingFormat, fileURL: writingTo,
            meetingStart: Date(), fixedTimeOffset: offset, live: live, realtimeAudio: false)
        try await transcriber.prepare(localeIdentifier: localeIdentifier, contextualStrings: contextualStrings)
        var fed = 0.0
        var lastWait = 0.0
        while file.framePosition < file.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8192) else { break }
            do {
                try file.read(into: buffer)
            } catch {
                appLog.error("meeting audio read stopped (\(channel.rawValue, privacy: .public)) at \(fed, privacy: .public)s: \(error.localizedDescription, privacy: .public)")
                break
            }
            if buffer.frameLength == 0 { break }
            transcriber.append(buffer)
            fed += Double(buffer.frameLength) / buffer.format.sampleRate
            if live, fed - lastWait >= 10 {
                await transcriber.waitForAnalyzer(window: 30, stallTimeout: 0.5)
                lastWait = fed
            }
        }
        let phrases = await transcriber.finish()
        return (phrases, transcriber.recognitionFailed, fed)
    }

    /// 文字起こしの進み具合が、渡した音の window 秒前より後ろにいれば、追いつくまで待つ。進まないまま stallTimeout 秒たったらやめる
    private func waitForAnalyzer(window: Double, stallTimeout: Double) async {
        var lastProgress = -1.0
        var lastChange = Date()
        while true {
            let (fed, analyzer) = queue.sync { (writtenSeconds, self.analyzer) }
            var progress = levelLock.withLock { _analyzedSeconds }
            if let range = await analyzer?.volatileRange, range.start.seconds.isFinite {
                progress = max(progress, range.start.seconds)
            }
            if progress >= fed - window { return }
            if progress != lastProgress {
                lastProgress = progress
                lastChange = Date()
            } else if Date().timeIntervalSince(lastChange) > stallTimeout {
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    // 要件: REQ-MTG-128
    // 設計判断: DEC-MTG-156, DEC-MTG-160
    /// 録音のファイルを閉じる（それまでに渡した音を書き終えてから。待つのは最大 5 秒）。文字起こしは止めない。
    /// 2 回目からは何もしない。アプリを終えるときにも呼ぶ
    func closeAudioFile() async {
        let writer: MeetingAudioWriter? = queue.sync {
            defer { file = nil }
            return file
        }
        await writer?.finish()
    }

    func cancel() async {
        let analyzer: SpeechAnalyzer? = queue.sync {
            pendingInput = nil
            continuation?.finish()
            continuation = nil
            return self.analyzer
        }
        await closeAudioFile()
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
