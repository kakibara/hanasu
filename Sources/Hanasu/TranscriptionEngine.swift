@preconcurrency import AVFoundation
import Foundation

// 要件: REQ-COM-001
/// 文字起こしのエンジン。音声入力と会議の記録で別々に選べる（設定の「一般」→「文字起こし」）。
enum TranscriptionEngine: String, CaseIterable, Identifiable, Sendable {
    /// macOS の SpeechAnalyzer（細かい選択は RecognizerEngine）
    case apple
    /// WhisperKit で Mac の上で動かす（モデルは選んだときにダウンロードする）
    case whisper
    /// 録った音声を Gemini に送って文字起こしする
    case gemini

    var id: String { rawValue }

    var label: String {
        switch self {
        case .apple: "Mac 標準（SpeechAnalyzer）"
        case .whisper: "Whisper（この Mac の上で動かす）"
        // 設計判断: DEC-COM-033
        case .gemini: "Gemini（音声を Google に送る）"
        }
    }

    /// HUD などに出す短い名前
    var shortName: String {
        switch self {
        case .apple: "Mac 標準"
        case .whisper: "Whisper"
        case .gemini: "Gemini"
        }
    }

    /// 録音中に途中経過を出せるか。Whisper と Gemini は、録音を止めてからまとめて文字起こしする
    var isLive: Bool { self == .apple }
}

// 設計判断: DEC-COM-022
/// Whisper のモデル（WhisperKit の CoreML 版。https://huggingface.co/argmaxinc/whisperkit-coreml）
enum WhisperModel: String, CaseIterable, Identifiable, Sendable {
    case tiny
    case base
    case small
    case largeV3Turbo

    var id: String { rawValue }

    /// whisperkit-coreml のフォルダ名
    var variant: String {
        switch self {
        case .tiny: "openai_whisper-tiny"
        case .base: "openai_whisper-base"
        case .small: "openai_whisper-small"
        // large-v3-turbo（v20240930）を 626 MB に量子化したもの。M1 以降の Mac で動く
        case .largeV3Turbo: "openai_whisper-large-v3-v20240930_626MB"
        }
    }

    // 設計判断: DEC-COM-028
    /// ダウンロードの大きさの目安（バイト）。選ぶ前と、ダウンロードの途中・削除の確かめで見せる
    var approximateBytes: Int64 {
        switch self {
        case .tiny: 75_000_000
        case .base: 145_000_000
        case .small: 485_000_000
        case .largeV3Turbo: 630_000_000
        }
    }

    /// 「約 485 MB」のような表記
    var sizeLabel: String { "約 " + ByteCountFormatter.string(fromByteCount: approximateBytes, countStyle: .file) }

    var label: String {
        switch self {
        case .tiny: "tiny（\(sizeLabel)・速いが粗い）"
        case .base: "base（\(sizeLabel)）"
        case .small: "small（\(sizeLabel)・バランス）"
        case .largeV3Turbo: "large-v3-turbo（\(sizeLabel)・高精度）"
        }
    }
}

// MARK: - 音声の読み書き

/// Whisper と Gemini に渡す音声（16 kHz モノラルの Float）
enum TranscriptionAudio {
    static let sampleRate: Double = 16000
    static let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

    /// 音声ファイルを 16 kHz モノラルの Float に読み込む
    static func loadSamples(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let converter = BatchSampleConverter()
        var samples: [Float] = []
        samples.reserveCapacity(Int(Double(file.length) * sampleRate / file.processingFormat.sampleRate) + 1024)
        while file.framePosition < file.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16384) else { break }
            try file.read(into: buffer)
            if buffer.frameLength == 0 { break }
            samples += converter.convert(buffer)
        }
        return samples
    }

    /// Gemini に送る形にする。FLAC（可逆圧縮で WAV のおよそ半分）を使い、書けなければ WAV にする
    static func encodeForUpload(_ samples: ArraySlice<Float>) throws -> (data: Data, mimeType: String) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Hanasu-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        if let data = try? write(samples, to: dir.appendingPathComponent("audio.flac"), formatID: kAudioFormatFLAC) {
            return (data, "audio/flac")
        }
        return (try write(samples, to: dir.appendingPathComponent("audio.wav"), formatID: kAudioFormatLinearPCM), "audio/wav")
    }

    private static func write(_ samples: ArraySlice<Float>, to url: URL, formatID: AudioFormatID) throws -> Data {
        do {
            let file = try AVAudioFile(
                forWriting: url,
                settings: [
                    AVFormatIDKey: formatID,
                    AVSampleRateKey: sampleRate,
                    AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                ],
                commonFormat: .pcmFormatFloat32,
                interleaved: false)
            let chunk = 65536
            var index = samples.startIndex
            while index < samples.endIndex {
                let end = min(index + chunk, samples.endIndex)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(end - index)) else { break }
                buffer.frameLength = AVAudioFrameCount(end - index)
                samples[index..<end].withUnsafeBufferPointer { src in
                    buffer.floatChannelData![0].update(from: src.baseAddress!, count: src.count)
                }
                try file.write(from: buffer)
                index = end
            }
        }  // ここで file が解放され、閉じられる
        let data = try Data(contentsOf: url)
        guard data.count > 64 else { throw CocoaError(.fileWriteUnknown) }
        return data
    }

    /// 音量（RMS, 0〜1）
    static func rms<C: Collection>(_ samples: C) -> Float where C.Element == Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for v in samples { sum += v * v }
        return (sum / Float(samples.count)).squareRoot()
    }

    // 設計判断: DEC-MTG-008
    /// 長い音声を、だいたい length 秒ごとに分ける。区切りは目安の前 15 秒のうち、いちばん静かなところにする
    /// （語の途中で切らないため）。返すのは開始サンプルの位置。
    static func chunkStarts(_ samples: [Float], length: Double, searchWindow: Double = 15) -> [Int] {
        let target = Int(length * sampleRate)
        let search = Int(searchWindow * sampleRate)
        let window = Int(0.25 * sampleRate)
        var starts = [0]
        // 最後の区切りが短くなりすぎないよう、残りが目安＋探す幅より長いときだけ区切る
        while samples.count - starts.last! > target + search {
            let ideal = starts.last! + target
            var best = ideal
            var bestLevel = Float.greatestFiniteMagnitude
            var pos = ideal - search
            while pos + window <= ideal {
                let level = rms(samples[pos..<(pos + window)])
                if level < bestLevel {
                    bestLevel = level
                    best = pos + window / 2
                }
                pos += window / 2
            }
            starts.append(best)
        }
        return starts
    }
}

/// 任意の形式のバッファを 16 kHz モノラルの Float に変える。入力の形式が変わったら作り直す
final class BatchSampleConverter {
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?

    func convert(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let output = TranscriptionAudio.format
        if inputFormat != buffer.format {
            inputFormat = buffer.format
            converter = buffer.format == output ? nil : AVAudioConverter(from: buffer.format, to: output)
            converter?.downmix = true
            converter?.primeMethod = .none
        }
        guard let converter else { return Self.array(buffer) }
        let ratio = output.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let converted = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return [] }
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
        return error == nil ? Self.array(converted) : []
    }

    /// 変換済み（16 kHz モノラル Float）のバッファも返す。音声ファイルへの書き出しに使う
    func convertToBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let samples = convert(buffer)
        guard !samples.isEmpty,
              let out = AVAudioPCMBuffer(pcmFormat: TranscriptionAudio.format, frameCapacity: AVAudioFrameCount(samples.count))
        else { return nil }
        out.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { out.floatChannelData![0].update(from: $0.baseAddress!, count: $0.count) }
        return out
    }

    private static func array(_ buffer: AVAudioPCMBuffer) -> [Float] {
        guard let data = buffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: data, count: Int(buffer.frameLength)))
    }
}

// MARK: - まとめて文字起こしする

/// 時刻つきの区間（秒。音声の先頭を 0 とする）
struct TimedSegment: Hashable, Sendable {
    var start: Double
    var end: Double
    var text: String
    /// 語ごとの時刻（Whisper のみ。Gemini は区間だけ）
    var words: [TimedWord] = []
}

enum BatchTranscriptionError: LocalizedError {
    case whisperModelMissing(WhisperModel)
    case noCredentials
    case appleNotBatch

    var errorDescription: String? {
        switch self {
        case .whisperModelMissing(let model):
            "Whisper のモデル（\(model.rawValue)）がまだダウンロードされていません。設定の「一般」→「文字起こし」でダウンロードしてください"
        case .noCredentials:
            "Gemini で文字起こしするには、Gemini の認証情報（設定の「AI」）が必要です"
        case .appleNotBatch:
            "Mac 標準のエンジンは、まとめての文字起こしに使えません"
        }
    }
}

// 要件: REQ-COM-001
/// Whisper / Gemini で、録り終えた音声を文字に起こす。
enum BatchTranscriber {
    /// 音声入力用。全文だけを返す
    static func transcribeText(
        _ samples: [Float], engine: TranscriptionEngine, settings: AppSettings, hints: [String]
    ) async throws -> String {
        switch engine {
        case .apple:
            throw BatchTranscriptionError.appleNotBatch
        case .whisper:
            let segments = try await WhisperEngine.shared.transcribe(
                samples, model: settings.whisperModel, language: settings.whisperLanguage, hints: hints, wordTimestamps: false)
            return segments.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        case .gemini:
            guard let auth = try GeminiTranscriber.auth(settings: settings) else {
                throw BatchTranscriptionError.noCredentials
            }
            return try await GeminiTranscriber(auth: auth, model: settings.geminiTranscriptionModel)
                .transcribe(samples, localeIdentifier: settings.localeIdentifier, hints: hints)
        }
    }

    /// 会議用。時刻つきの区間を返す。progress には「何区切り目か」などの説明が渡る
    static func transcribeSegments(
        _ samples: [Float], engine: TranscriptionEngine, settings: AppSettings, hints: [String],
        progress: (@MainActor (String) -> Void)? = nil
    ) async throws -> [TimedSegment] {
        switch engine {
        case .apple:
            throw BatchTranscriptionError.appleNotBatch
        case .whisper:
            return try await WhisperEngine.shared.transcribe(
                samples, model: settings.whisperModel, language: settings.whisperLanguage, hints: hints, wordTimestamps: true)
        case .gemini:
            guard let auth = try GeminiTranscriber.auth(settings: settings) else {
                throw BatchTranscriptionError.noCredentials
            }
            return try await GeminiTranscriber(auth: auth, model: settings.geminiTranscriptionModel)
                .transcribeSegments(samples, localeIdentifier: settings.localeIdentifier, hints: hints, progress: progress)
        }
    }
}
