@preconcurrency import AVFoundation
import Foundation

// 要件: REQ-MTG-128
// 設計判断: DEC-MTG-158
/// 記録中に落ちた会議を録音から作り直すときの決まり（作り直すボタンを出すか・会議の長さ・終わっていないオフレコの閉じ方）。
/// Windows 版の MeetingRecovery（windows/Hanasu.Core/Meetings/MeetingRecovery.cs）と同じ決まり
enum MeetingRecovery {
    /// 作り直すボタンを出すか。発言が 0 件で、開ける録音（長さが 0 より大きい）が 1 つ以上あり、記録中・処理中でなく、
    /// アプリが記録・後処理・作り直しをしていないとき。状態（失敗・完了）では決めない
    /// - Parameter readableAudioSeconds: チャンネルごとの、開けた録音の長さ（秒）。開けないチャンネルは入れない
    static func canRecover(_ meeting: Meeting, readableAudioSeconds: [MeetingChannel: Double], busy: Bool) -> Bool {
        guard !busy, meeting.utterances.isEmpty else { return false }
        guard meeting.status != .recording, meeting.status != .processing else { return false }
        return readableAudioSeconds.values.contains { $0 > 0 }
    }

    /// 会議の長さ: 残った録音の終わり（先頭のずれ＋長さ）の大きいほう
    static func duration(offsets: [MeetingChannel: Double], audioSeconds: [MeetingChannel: Double]) -> Double {
        audioSeconds.map { (offsets[$0.key] ?? 0) + $0.value }.max() ?? 0
    }

    /// 終わっていないオフレコの区間を、録音の終わりで閉じる
    static func closeOpenOffRecord(_ spans: [OffRecordSpan]?, at end: Double) -> [OffRecordSpan]? {
        spans?.map { span in
            var span = span
            if span.end == nil { span.end = max(span.start, end) }
            return span
        }
    }

    /// 作り直しのあとの状態: 発言が 0 件で、両方のチャンネルとも文字起こしできなければ「失敗」（作り直すボタンをまた出す）。
    /// それ以外は「完了」（片方だけ失敗したときも、記録を止めたあとと同じく「完了」でエラーの文に書く）
    static func statusAfterRecovery(_ meeting: Meeting) -> Meeting.Status {
        let failed = Set(meeting.transcriptionFailedChannels ?? [])
        return meeting.utterances.isEmpty && failed.isSuperset(of: [MeetingChannel.me, .others]) ? .failed : .done
    }

    /// 記録中に保存した、チャンネルごとの先頭のずれ（ないチャンネルは 0）
    static func offsets(of meeting: Meeting) -> [MeetingChannel: Double] {
        var result: [MeetingChannel: Double] = [:]
        for channel in [MeetingChannel.me, .others] {
            result[channel] = meeting.audioStartOffsets?[channel.rawValue] ?? 0
        }
        return result
    }

    /// 作り直しを始めるときの会議: エラーの文を消し、長さと終わっていないオフレコを録音から直し、処理中にする
    static func prepared(_ meeting: Meeting, audioSeconds: [MeetingChannel: Double]) -> Meeting {
        var meeting = meeting
        meeting.errorMessage = nil
        meeting.duration = duration(offsets: offsets(of: meeting), audioSeconds: audioSeconds)
        meeting.offRecord = closeOpenOffRecord(meeting.offRecord, at: meeting.duration)
        meeting.status = .processing
        return meeting
    }

    // MARK: - 開ける録音

    /// 録音のファイルを開いて、長さ（秒）を測る。開けないか長さが 0 なら nil
    static func readableSeconds(of url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let seconds = Double(file.length) / file.processingFormat.sampleRate
        return seconds > 0 ? seconds : nil
    }

    private struct CacheKey: Hashable {
        let path: String
        let modified: Date?
        let size: Int?
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache: [CacheKey: Double?] = [:]

    /// 会議のチャンネルごとの、開ける録音の長さ（秒）。Mac が読む me.m4a・others.m4a だけを見る。
    /// 帯を描くたびに開かないよう、ファイルの更新日時と大きさごとに覚えておく
    static func readableAudioSeconds(of meeting: Meeting) -> [MeetingChannel: Double] {
        readableAudioSeconds(in: MeetingStore.directory(for: meeting))
    }

    /// 会議のフォルダの、チャンネルごとの開ける録音の長さ（秒）。ほかの OS の録音（me.wav など）は見ない
    static func readableAudioSeconds(in directory: URL) -> [MeetingChannel: Double] {
        var result: [MeetingChannel: Double] = [:]
        for channel in [MeetingChannel.me, .others] {
            let url = directory.appendingPathComponent(channel == .me ? "me.m4a" : "others.m4a")
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { continue }
            let key = CacheKey(path: url.path, modified: attributes[.modificationDate] as? Date,
                               size: (attributes[.size] as? NSNumber)?.intValue)
            let cached: Double?? = cacheLock.withLock { cache[key] }
            let seconds: Double?
            if let cached {
                seconds = cached
            } else {
                seconds = readableSeconds(of: url)
                cacheLock.withLock { cache[key] = seconds }
            }
            if let seconds { result[channel] = seconds }
        }
        return result
    }
}
