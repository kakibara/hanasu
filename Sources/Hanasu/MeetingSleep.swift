@preconcurrency import AVFoundation
import Foundation

// 要件: REQ-MTG-043
/// 記録中に Mac がスリープした時点。「スリープ前までで止める」を選んだら、ここで記録を切る
struct MeetingSleepPoint: Equatable {
    /// スリープした時計の時刻（確認に出す）
    let at: Date
    /// スリープした時点の経過時間（録音開始からの秒数。スリープしていた時間は除く。DEC-MTG-089）
    let elapsed: Double
    /// チャンネルごとの、スリープした時点で書き終えていた音声の終わり（録音開始からの秒数）。音声がまだなかったチャンネルは入らない
    let audioEnds: [MeetingChannel: Double]

    /// そのチャンネルを切る位置（音声の時間軸）。音声がまだなければ経過時間で切る
    func cutoff(for channel: MeetingChannel) -> Double {
        audioEnds[channel] ?? elapsed
    }
}

// 要件: REQ-MTG-043
// 設計判断: DEC-MTG-088
/// 「スリープ前までで止める」ときに、スリープより後に録った分を会議から除く
enum MeetingSleepCut {
    /// スリープより後に始まる発言を捨てる
    static func phrases(_ phrases: [TranscribedPhrase], before point: MeetingSleepPoint) -> [TranscribedPhrase] {
        phrases.filter { $0.start < point.cutoff(for: $0.channel) }
    }

    /// 会議の長さをスリープした時点までにし、それより後の「ここ重要」の印を消し、メモは時刻をスリープした時点にそろえる
    static func apply(to meeting: inout Meeting, point: MeetingSleepPoint) {
        meeting.duration = point.elapsed
        // 設計判断: DEC-MTG-094
        // スリープの後に始めたオフレコは消し、終わりはスリープした時点まで
        if let spans = meeting.offRecord {
            let kept = spans.filter { $0.start < point.elapsed }.map { span in
                var span = span
                span.end = min(span.end ?? point.elapsed, point.elapsed)
                return span
            }
            meeting.offRecord = kept.isEmpty ? nil : kept
        }
        guard let notes = meeting.notes else { return }
        meeting.notes = notes.compactMap { note in
            guard let time = note.time, time > point.elapsed else { return note }
            if note.kind == .highlight { return nil }
            var note = note
            note.time = point.elapsed
            return note
        }
    }

    /// 音声ファイルを、先頭から seconds 秒までに切り詰める（再エンコードしない）。もともと短ければ何もしない
    static func trimAudio(at url: URL, toSeconds seconds: Double) async throws {
        guard seconds > 0, FileManager.default.fileExists(atPath: url.path) else { return }
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, seconds < duration else { return }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw CocoaError(.fileWriteUnknown)
        }
        session.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: seconds, preferredTimescale: 48_000))
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".trim-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try await session.export(to: temporary, as: .m4a)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
    }
}
