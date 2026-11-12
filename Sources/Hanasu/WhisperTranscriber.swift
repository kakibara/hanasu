import Combine
import Foundation
import WhisperKit

// 設計判断: DEC-COM-023
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

    // 要件: REQ-COM-003
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

// 設計判断: DEC-COM-021
/// 読み込んだ Whisper のモデルを持っておき、文字起こしする。読み込みは数秒かかるので使い回す
actor WhisperEngine {
    static let shared = WhisperEngine()

    private var loaded: (model: WhisperModel, kit: WhisperKit)?

    // 設計判断: DEC-COM-026
    /// 無音のときなどに Whisper が出しがちな決まり文句（動画の字幕から覚えたもの）。区間の全体がこれなら捨てる。
    /// 文字起こしの言語によらず、17 言語のものをすべて見る。照らすときは大文字小文字と前後の句読点を無視する。
    /// Windows 版の `WhisperText.Hallucinations` と同じ並び（両方を直す）
    static let hallucinations: Set<String> = Set([
        "ご視聴ありがとうございました", "最後までご視聴いただきありがとうございました",  // skip-tr（Whisper の出力と照らす語。UI ではない）
        "チャンネル登録よろしくお願いします", "チャンネル登録お願いします",  // skip-tr（Whisper の出力と照らす語。UI ではない）
        "thank you for watching", "thanks for watching", "please subscribe to my channel",  // skip-tr（Whisper の出力と照らす語。UI ではない）
        "谢谢观看", "感谢观看", "謝謝觀看", "感謝觀看", "请不吝点赞 订阅 转发 打赏支持明镜与点点栏目",  // skip-tr（Whisper の出力と照らす語。UI ではない）
        "시청해주셔서 감사합니다", "시청해 주셔서 감사합니다", "구독과 좋아요 부탁드립니다",  // skip-tr（Whisper の出力と照らす語。UI ではない）
        "gracias por ver", "gracias por ver el video", "merci d'avoir regardé", "vielen dank fürs zuschauen",  // skip-tr（Whisper の出力と照らす語。UI ではない）
        "grazie per la visione", "obrigado por assistir", "спасибо за просмотр", "продолжение следует",  // skip-tr（Whisper の出力と照らす語。UI ではない）
        "izlediğiniz için teşekkür ederim", "cảm ơn các bạn đã theo dõi", "terima kasih telah menonton",  // skip-tr（Whisper の出力と照らす語。UI ではない）
        "dzięki za obejrzenie", "شكرا للمشاهدة", "देखने के लिए धन्यवाद",  // skip-tr（Whisper の出力と照らす語。UI ではない）
    ].map(noiseKey))

    /// この語で始まる区間も決まり文句として捨てる（字幕の作り手の名前や年が続くもの）。「amara.org」を含む区間も捨てる
    static let hallucinationPrefixes = [
        "untertitel im auftrag des zdf", "untertitelung des zdf", "untertitelung im auftrag des zdf",  // skip-tr（Whisper の出力と照らす語。UI ではない）
        "субтитры сделал", "субтитры создавал", "редактор субтитров",  // skip-tr（Whisper の出力と照らす語。UI ではない）
        "字幕由", "字幕製作", "字幕制作",  // skip-tr（Whisper の出力と照らす語。UI ではない）
    ]

    /// 無音や雑音のところに付く「(音楽)」「[拍手]」のような注記。かっこを外してこれだけなら捨てる（17 言語。大文字小文字を無視する）
    static let soundTags: Set<String> = Set([
        "音楽", "拍手", "笑", "笑い", "bgm", "music", "applause", "laughter", "silence", "blank_audio",  // skip-tr（Whisper の出力と照らす語。UI ではない）
        "音乐", "音樂", "掌声", "掌聲", "笑声", "笑聲", "음악", "박수", "웃음",  // skip-tr（Whisper の出力と照らす語。UI ではない）
        "música", "musique", "musik", "musica", "музыка", "müzik", "âm nhạc", "muzyka", "موسيقى", "संगीत",  // skip-tr（Whisper の出力と照らす語。UI ではない）
        "aplausos", "applaudissements", "applaus", "applausi", "аплодисменты", "alkış", "vỗ tay", "tepuk tangan", "brawa", "تصفيق", "तालियाँ",  // skip-tr（Whisper の出力と照らす語。UI ではない）
        "risas", "rires", "lachen", "risate", "risos", "смех", "gülüşler", "tiếng cười", "tertawa", "śmiech", "ضحك", "हँसी",  // skip-tr（Whisper の出力と照らす語。UI ではない）
    ])

    /// 照らすための形（小文字にし、前後の空白と句読点を外す）
    static func noiseKey(_ text: String) -> String {
        folded(text).trimmingCharacters(in: CharacterSet(charactersIn: " 　。.、,!！?？…♪〜~¡¿").union(.whitespacesAndNewlines))  // skip-tr（照らし合わせ・区切りに使う記号）
    }

    /// 小文字にそろえる。トルコ語の「İ」は lowercased() だと「i」と結合文字の 2 つになり、一覧の「i」と合わないので先に「i」にする
    /// （Windows の WhisperText.Fold と同じ）
    static func folded(_ text: String) -> String {
        text.replacingOccurrences(of: "İ", with: "i").lowercased()  // skip-tr（照らし合わせに使う文字）
    }

    // 設計判断: DEC-COM-026
    static func isNoise(_ text: String) -> Bool {
        let key = noiseKey(text)
        if hallucinations.contains(key) || key.contains("amara.org") { return true }
        if hallucinationPrefixes.contains(where: key.hasPrefix) { return true }
        let stripped = folded(text).trimmingCharacters(in: CharacterSet(charactersIn: "()（）[]［］【】♪〜~ 　。.、*").union(.whitespacesAndNewlines))  // skip-tr（照らし合わせ・区切りに使う記号）
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

    // 設計判断: DEC-COM-027
    /// 前もって読み込んでおく（録音を始めたときに呼ぶと、止めてからの待ち時間が短くなる）
    func preload(_ model: WhisperModel) async {
        guard WhisperModelStore.isDownloaded(model) else { return }
        _ = try? await load(model)
    }

    // 設計判断: DEC-COM-025, DEC-COM-026
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
        // 区切りをまとめて渡すと、WhisperKit が並行して処理する。長い会議で音声のコピーが全体の大きさになるのを避けるため、
        // 一度に渡すのは 16 区切りまでにする
        var results: [Result<[TranscriptionResult], Swift.Error>] = []
        results.reserveCapacity(chunks.count)
        for batchStart in stride(from: 0, to: chunks.count, by: 16) {
            try Task.checkCancellation()
            let arrays = chunks[batchStart..<min(batchStart + 16, chunks.count)].map { Array(samples[$0]) }
            var batch = await kit.transcribeWithResults(audioArrays: arrays, decodeOptions: options)
            for i in batch.indices where i < arrays.count {
                // 声があるのに何も返らないことがたまにある（小さいモデルで多い）ので、1 回だけやり直す
                let empty = (try? batch[i].get())?.allSatisfy { $0.segments.allSatisfy { $0.text.trimmingCharacters(in: .whitespaces).isEmpty } } ?? true
                if empty, TranscriptionAudio.rms(arrays[i]) > 0.003 {
                    appLog.notice("whisper chunk \(batchStart + i) returned nothing; retrying once")
                    batch[i] = await kit.transcribeWithResults(audioArrays: [arrays[i]], decodeOptions: options).first ?? batch[i]
                }
            }
            results.append(contentsOf: batch)
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

    // 設計判断: DEC-COM-024
    /// 辞書の語から、Whisper に渡す前置きを作る（長すぎると認識に影響するので 30 語まで）。
    /// 区切りは文字起こしの言語の読点（日本語は「、」、英語は「, 」。前置きの書き方は認識の文体に効くため）
    static func prompt(from hints: [String], language: PromptLanguage = .current) -> String? {
        let words = Array(NSOrderedSet(array: hints.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
            .compactMap { $0 as? String }.prefix(30))
        return words.isEmpty ? nil : words.joined(separator: Prompts.text("user.dictionaryRuleSeparator", language: language))
    }
}
