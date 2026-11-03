import Foundation

/// 会議の記録のあとに、チャンネル（自分 / 相手）ごとの音声ファイルを Whisper / Gemini で文字起こしする。
/// 結果は Mac 標準のライブ文字起こしと同じ TranscribedPhrase にして、既存の後処理（話者分離と時刻による割り当て）に渡す。
enum MeetingBatchTranscription {
    /// - Parameter offset: このチャンネルの音声が、録音開始から何秒後に始まったか（ChannelTranscriber.audioStartOffset）
    @MainActor
    static func transcribe(audioURL: URL, channel: MeetingChannel, offset: Double, engine: TranscriptionEngine,
                           settings: AppSettings, progress: ((String) -> Void)? = nil) async throws -> [TranscribedPhrase] {
        guard FileManager.default.fileExists(atPath: audioURL.path) else { return [] }
        let samples = try await Task.detached { try TranscriptionAudio.loadSamples(from: audioURL) }.value
        // ほぼ無音のチャンネル（相手がいない、マイクを切っていた）は送らない
        guard !samples.isEmpty, TranscriptionAudio.rms(samples) > 0.0003 else { return [] }
        let label = channel == .me ? "自分" : "相手"
        progress?("\(engine.shortName) で文字起こししています…（\(label)）")
        let segments = try await BatchTranscriber.transcribeSegments(
            samples, engine: engine, settings: settings, hints: settings.userDictionary.contextualStrings,
            progress: { message in progress?(message.replacingOccurrences(of: "…（", with: "…（\(label) ")) })
        return phrases(from: segments, channel: channel, offset: offset)
    }

    // 設計判断: DEC-MTG-006
    /// 区間を、録音開始からの時刻の発話にする。語の時刻がない（Gemini）ときは、区間全体を 1 語として持つ
    static func phrases(from segments: [TimedSegment], channel: MeetingChannel, offset: Double) -> [TranscribedPhrase] {
        segments.map { segment in
            let words = segment.words.isEmpty
                ? [TimedWord(text: segment.text, start: segment.start, end: segment.end)]
                : segment.words
            return TranscribedPhrase(
                channel: channel,
                start: offset + segment.start,
                end: offset + segment.end,
                text: segment.text,
                words: words.map { TimedWord(text: $0.text, start: offset + $0.start, end: offset + $0.end) })
        }
    }
}
