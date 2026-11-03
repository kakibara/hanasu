import FluidAudio
import Foundation

// 要件: REQ-MTG-004, REQ-MTG-023
// 設計判断: DEC-MTG-010
/// FluidAudio（pyannote speaker-diarization-community-1 の CoreML 版）による、Mac 上での話者分離。
/// モデルは初回に Hugging Face からダウンロードされ、以後はキャッシュを使う。
final class FluidAudioDiarizer: SpeakerDiarizer {
    private var manager: OfflineDiarizerManager?

    func diarize(audioURL: URL) async throws -> [SpeakerTurn] {
        let manager = try await preparedManager()
        let started = Date()
        let result = try await manager.process(audioURL)
        appLog.notice("diarized \(result.segments.count) segments in \(Date().timeIntervalSince(started), format: .fixed(precision: 1))s")
        return result.segments.map {
            SpeakerTurn(speakerId: $0.speakerId, start: Double($0.startTimeSeconds), end: Double($0.endTimeSeconds))
        }
    }

    private func preparedManager() async throws -> OfflineDiarizerManager {
        if let manager { return manager }
        let manager = OfflineDiarizerManager(config: .default)
        let started = Date()
        try await manager.prepareModels()
        appLog.notice("diarizer models ready in \(Date().timeIntervalSince(started), format: .fixed(precision: 1))s")
        self.manager = manager
        return manager
    }
}
