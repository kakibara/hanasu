import Combine
import Foundation
import WhisperKit

/// Whisper のモデルのダウンロード・削除と、その状態。設定画面に出す。
/// 保存先: ~/Library/Application Support/Hanasu/Models/whisper（環境変数 HANASU_MODELS_DIR で変えられる。確認用）
@MainActor
final class WhisperModelStore: ObservableObject {
    static let shared = WhisperModelStore()

    enum Status: Equatable {
        case notDownloaded
        /// fraction は 0〜1。nil は準備中（初回の最適化など、進み具合がわからないとき）
        case downloading(fraction: Double?)
        case downloaded
        case failed(String)
    }

    @Published private(set) var statuses: [WhisperModel: Status] = [:]
    private var tasks: [WhisperModel: Task<Void, Never>] = [:]

    /// WhisperKit の downloadBase。モデルは models/argmaxinc/whisperkit-coreml/<variant>、
    /// トークナイザーは models/openai/whisper-<種類> に入る
    nonisolated static var baseDirectory: URL {
        if let dir = ProcessInfo.processInfo.environment["HANASU_MODELS_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: (dir as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hanasu/Models/whisper", isDirectory: true)
    }

    nonisolated static func modelFolder(_ model: WhisperModel) -> URL {
        baseDirectory.appendingPathComponent("models/argmaxinc/whisperkit-coreml/\(model.variant)", isDirectory: true)
    }

    /// ダウンロードと最初の読み込みが終わったときに置く印。途中で止まったものを使わないため
    nonisolated private static func completeMarker(_ model: WhisperModel) -> URL {
        modelFolder(model).appendingPathComponent(".hanasu-complete")
    }

    nonisolated static func isDownloaded(_ model: WhisperModel) -> Bool {
        FileManager.default.fileExists(atPath: completeMarker(model).path)
    }

    private init() {
        for model in WhisperModel.allCases {
            statuses[model] = Self.isDownloaded(model) ? .downloaded : .notDownloaded
        }
    }

    func status(_ model: WhisperModel) -> Status { statuses[model] ?? .notDownloaded }

    /// ディスク上の大きさ（バイト）
    func diskUsage(_ model: WhisperModel) -> Int64? {
        guard Self.isDownloaded(model),
              let enumerator = FileManager.default.enumerator(
                  at: Self.modelFolder(model), includingPropertiesForKeys: [.totalFileAllocatedSizeKey])
        else { return nil }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            total += Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
        return total
    }

    /// まだなければダウンロードを始める。終わるまで待つときは await する
    @discardableResult
    func ensureDownloaded(_ model: WhisperModel) -> Task<Void, Never>? {
        if Self.isDownloaded(model) { return nil }
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
                appLog.notice("whisper model downloaded: \(model.variant, privacy: .public)")
            } catch is CancellationError {
                Self.removeFiles(model)
                self?.statuses[model] = .notDownloaded
            } catch {
                appLog.error("whisper download failed: \(String(describing: error), privacy: .public)")
                // 取り消したときは URLError(.cancelled) などで返ってくることもある
                if Task.isCancelled {
                    Self.removeFiles(model)
                    self?.statuses[model] = .notDownloaded
                } else {
                    self?.statuses[model] = .failed(error.localizedDescription)
                }
            }
            self?.tasks[model] = nil
        }
        tasks[model] = task
        return task
    }

    /// 設定画面を PNG に描き出す確認用に、ダウンロード中の見た目にする（CLI の --render-engine-settings）
    func showDownloadingForRendering(_ model: WhisperModel, fraction: Double) {
        statuses[model] = .downloading(fraction: fraction)
    }

    func cancelDownload(_ model: WhisperModel) {
        tasks[model]?.cancel()
    }

    func delete(_ model: WhisperModel) {
        tasks[model]?.cancel()
        Task { await WhisperEngine.shared.unload(model) }
        Self.removeFiles(model)
        statuses[model] = .notDownloaded
    }

    nonisolated private static func removeFiles(_ model: WhisperModel) {
        try? FileManager.default.removeItem(at: modelFolder(model))
    }

    /// モデルとトークナイザーを取ってきて、一度読み込む（CoreML の最適化を済ませておくと、初回の文字起こしが速い）
    nonisolated static func download(_ model: WhisperModel, progress: @escaping @Sendable (Double?) -> Void) async throws {
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        let folder = try await WhisperKit.download(
            variant: model.variant, downloadBase: baseDirectory,
            progressCallback: { p in progress(p.fractionCompleted) })
        try Task.checkCancellation()
        progress(nil)
        _ = try await WhisperEngine.shared.load(model, folder: folder)
        try Task.checkCancellation()
        FileManager.default.createFile(atPath: completeMarker(model).path, contents: Data())
    }
}

/// 読み込んだ Whisper のモデルを持っておき、文字起こしする。読み込みは数秒かかるので使い回す
actor WhisperEngine {
    static let shared = WhisperEngine()

    private var loaded: (model: WhisperModel, kit: WhisperKit)?

    /// 無音のときなどに Whisper が出しがちな決まり文句。区間の全体がこれなら捨てる
    static let hallucinations: Set<String> = [
        "ご視聴ありがとうございました", "ご視聴ありがとうございました。",
        "最後までご視聴いただきありがとうございました", "最後までご視聴いただきありがとうございました。",
        "チャンネル登録よろしくお願いします", "チャンネル登録よろしくお願いします。",
        "チャンネル登録お願いします", "チャンネル登録お願いします。",
    ]

    /// 無音や雑音のところに付く「(音楽)」「[拍手]」のような注記。かっこを外してこれだけなら捨てる
    static let soundTags: Set<String> = ["音楽", "拍手", "笑", "笑い", "BGM", "music", "Music", "MUSIC", "applause", "laughter"]

    static func isNoise(_ text: String) -> Bool {
        if hallucinations.contains(text) { return true }
        let stripped = text.trimmingCharacters(in: CharacterSet(charactersIn: "()（）[]［］【】♪〜~ 　。.、"))
        return stripped.isEmpty || soundTags.contains(stripped)
    }

    func load(_ model: WhisperModel, folder: URL? = nil) async throws -> WhisperKit {
        if let loaded, loaded.model == model { return loaded.kit }
        let folder = folder ?? WhisperModelStore.modelFolder(model)
        guard FileManager.default.fileExists(atPath: folder.path) else {
            throw BatchTranscriptionError.whisperModelMissing(model)
        }
        if let previous = loaded?.kit { await previous.unloadModels() }
        loaded = nil
        let config = WhisperKitConfig(
            model: model.variant,
            downloadBase: WhisperModelStore.baseDirectory,
            modelFolder: folder.path,
            tokenizerFolder: WhisperModelStore.baseDirectory,
            verbose: false,
            logLevel: .error,
            prewarm: false,
            load: true,
            download: false)
        let kit = try await WhisperKit(config)
        loaded = (model, kit)
        return kit
    }

    func unload(_ model: WhisperModel) async {
        guard let loaded, loaded.model == model else { return }
        await loaded.kit.unloadModels()
        self.loaded = nil
    }

    /// 前もって読み込んでおく（録音を始めたときに呼ぶと、止めてからの待ち時間が短くなる）
    func preload(_ model: WhisperModel) async {
        guard WhisperModelStore.isDownloaded(model) else { return }
        _ = try? await load(model)
    }

    /// 16 kHz モノラルの音声を文字に起こす。時刻は音声の先頭からの秒数
    func transcribe(_ samples: [Float], model: WhisperModel, language: String, hints: [String],
                    wordTimestamps: Bool) async throws -> [TimedSegment] {
        guard WhisperModelStore.isDownloaded(model) else { throw BatchTranscriptionError.whisperModelMissing(model) }
        let kit = try await load(model)
        var options = DecodingOptions(
            task: .transcribe,
            language: language,
            temperatureFallbackCount: 3,
            usePrefillPrompt: true,
            detectLanguage: false,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            wordTimestamps: wordTimestamps,
            // 区切りは自分で行う（下の chunks）。WhisperKit の VAD での区切りは、長い音声で区間の時刻がずれたり
            // 区間が抜けたりすることがあったため
            chunkingStrategy: ChunkingStrategy.none)
        if let tokenizer = kit.tokenizer, let prompt = Self.prompt(from: hints) {
            // 辞書の語を「前の文脈」として渡すと、その表記で書きやすくなる
            let tokens = tokenizer.encode(text: " " + prompt).filter { $0 < tokenizer.specialTokens.specialTokenBegin }
            if !tokens.isEmpty { options.promptTokens = Array(tokens.prefix(120)) }
        }

        // Whisper は 30 秒ずつ処理するので、20〜30 秒ごとに、いちばん静かなところで区切る。無音だけの区切りは飛ばす
        let starts = TranscriptionAudio.chunkStarts(samples, length: 25, searchWindow: 5)
        let chunks = starts.indices
            .map { i in starts[i]..<(i + 1 < starts.count ? starts[i + 1] : samples.count) }
            .filter { TranscriptionAudio.rms(samples[$0]) > 0.0005 }
        guard !chunks.isEmpty else { return [] }
        // 区切りをまとめて渡すと、WhisperKit が並行して処理する
        let arrays = chunks.map { Array(samples[$0]) }
        var results = await kit.transcribeWithResults(audioArrays: arrays, decodeOptions: options)
        for i in results.indices {
            // 声があるのに何も返らないことがたまにある（小さいモデルで多い）ので、1 回だけやり直す
            let empty = (try? results[i].get())?.allSatisfy { $0.segments.allSatisfy { $0.text.trimmingCharacters(in: .whitespaces).isEmpty } } ?? true
            if empty, TranscriptionAudio.rms(arrays[i]) > 0.003 {
                appLog.notice("whisper chunk \(i) returned nothing; retrying once")
                results[i] = await kit.transcribeWithResults(audioArrays: [arrays[i]], decodeOptions: options).first ?? results[i]
            }
        }

        let debug = ProcessInfo.processInfo.environment["HANASU_DEBUG"] != nil
        if debug {
            print("whisper prompt: \(options.promptTokens?.count ?? 0) tokens, chunks: " + chunks.map { String(format: "%.1f-%.1f", Double($0.lowerBound) / 16000, Double($0.upperBound) / 16000) }.joined(separator: " "))
        }
        var segments: [TimedSegment] = []
        for (range, result) in zip(chunks, results) {
            let offset = Double(range.lowerBound) / TranscriptionAudio.sampleRate
            let duration = Double(range.count) / TranscriptionAudio.sampleRate
            let transcribed: [TranscriptionResult]
            do {
                transcribed = try result.get()
            } catch {
                // 1 つの区切りが失敗したら全体を失敗にする（抜けたまま議事録を作らないため）
                throw error
            }
            for segment in transcribed.flatMap(\.segments) {
                let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if debug {
                    print(String(format: "whisper [%.2f-%.2f] noSpeech=%.2f logprob=%.2f %@",
                                 offset + Double(segment.start), offset + Double(segment.end),
                                 segment.noSpeechProb, segment.avgLogprob, text))
                }
                // 区切りの長さを超えた時刻の区間は、末尾の無音に付いた幻の区間なので捨てる
                guard !text.isEmpty, !Self.isNoise(text), Double(segment.start) < duration else { continue }
                // 語の前の空白（英語など）は残す。会議の後処理では語をそのままつないで発言にする
                let words = (segment.words ?? []).compactMap { w -> TimedWord? in
                    w.word.trimmingCharacters(in: .whitespaces).isEmpty
                        ? nil : TimedWord(text: w.word, start: offset + Double(w.start), end: offset + Double(w.end))
                }
                segments.append(TimedSegment(
                    start: offset + Double(segment.start), end: offset + min(Double(segment.end), duration),
                    text: text, words: words))
            }
        }
        return segments.sorted { $0.start < $1.start }
    }

    /// 辞書の語から、Whisper に渡す前置きを作る（長すぎると認識に影響するので 30 語まで）
    static func prompt(from hints: [String]) -> String? {
        let words = Array(NSOrderedSet(array: hints.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
            .compactMap { $0 as? String }.prefix(30))
        return words.isEmpty ? nil : words.joined(separator: "、")
    }
}
