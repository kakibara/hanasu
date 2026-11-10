import Foundation

// 要件: REQ-MTG-010
// 設計判断: DEC-MTG-139, DEC-MTG-142
/// 会議ごとに録音を消すかの決め方（記録を始めたときに設定から写し、後処理はこの値で決める）
enum MeetingAudioPolicy {
    /// 記録を始めるときに、設定の既定を会議へ写す
    static func apply(to meeting: inout Meeting, deleteAfterTranscription: Bool) {
        meeting.deleteAudioAfterTranscription = deleteAfterTranscription ? true : nil
    }

    @MainActor
    static func apply(to meeting: inout Meeting, settings: AppSettings = .shared) {
        apply(to: &meeting, deleteAfterTranscription: !settings.keepMeetingAudio)
    }

    /// 後処理の最後に録音を消すか。会議の値がオンで、文字起こしがすべてそろっているときだけ消す（設定は見ない）
    static func shouldDeleteAfterProcessing(_ meeting: Meeting) -> Bool {
        meeting.deleteAudioAfterTranscription == true && MeetingAudioCleanup.transcriptState(of: meeting) == .complete
    }
}

// 設計判断: DEC-MTG-142
/// 会議の文字起こしがどこまであるか
enum MeetingTranscriptState: Equatable {
    /// すべてのチャンネルの文字起こしがある
    case complete
    /// 一部のチャンネルの文字起こしがない（failedChannels が空なら、どれが欠けたかは分からない）
    case partial(failedChannels: [MeetingChannel])
    /// 文字起こしがない（発言が 0 件）
    case none
}

/// 録音が残っている会議 1 件（録音の管理の一覧の 1 行）
struct MeetingAudioEntry: Identifiable, Equatable {
    var meeting: Meeting
    var size: Int64
    var state: MeetingTranscriptState
    var id: String { meeting.id }
}

// 要件: REQ-MTG-055, REQ-MTG-056, REQ-MTG-057
// 設計判断: DEC-MTG-140, DEC-MTG-141, DEC-MTG-142, DEC-MTG-143
/// 録音を消す対象の選び方と、消し方。会議のフォルダ・今の日時を受け取る純粋な関数にして、
/// 自己テスト（--test-meeting-audio）が本物の保存先を触らずに確かめられるようにする
enum MeetingAudioCleanup {
    /// 録音のファイル名。Mac と Windows で同じ会議のフォルダを開けるので、どちらの形式も対象にする（DEC-MTG-108）
    static let audioFileNames = ["me.m4a", "others.m4a", "me.wav", "others.wav"]
    /// 保存期間の選択肢（日。0 は無期限）。音声入力の履歴（HistorySettings.dayOptions）にそろえる
    static let retentionOptions = [0, 7, 30, 90, 365]
    /// 「30 日より前の録音を削除」の日数
    static let olderThanDays = 30

    static func transcriptState(of meeting: Meeting) -> MeetingTranscriptState {
        if meeting.utterances.isEmpty { return .none }
        let failed = meeting.transcriptionFailedChannels ?? []
        if !failed.isEmpty || meeting.status == .failed { return .partial(failedChannels: failed) }
        // この機能より前の会議（キーがない）は、一部のチャンネルだけ失敗してもエラーの文に書くだけだった。
        // エラーの文があれば、どのチャンネルが欠けたかは分からないが「一部」として録音を守る（文言では見分けない）
        if meeting.transcriptionFailedChannels == nil && meeting.errorMessage != nil { return .partial(failedChannels: []) }
        return .complete
    }

    /// 会議の帯に「音声ファイルは残しています」を出すか（エラーの文には書かず、表示のときに決める。DEC-MTG-140）
    static func showsAudioKept(_ meeting: Meeting, hasAudio: Bool) -> Bool {
        guard hasAudio, meeting.status == .done || meeting.status == .failed else { return false }
        return transcriptState(of: meeting) != .complete || meeting.status == .failed
    }

    // MARK: - ファイル

    static func audioFiles(in directory: URL) -> [URL] {
        audioFileNames.map { directory.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func audioSize(in directory: URL) -> Int64 {
        audioFiles(in: directory).reduce(0) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + Int64(size)
        }
    }

    /// 録音のファイルを完全に消す（ゴミ箱に入れない）。もうないファイルは消せたものとして扱う。
    /// - Returns: 消せなかったファイルと理由
    @discardableResult
    static func deleteAudio(in directory: URL) -> [(file: String, reason: String)] {
        var failures: [(String, String)] = []
        for name in audioFileNames {
            let url = directory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                try FileManager.default.removeItem(at: url)
            } catch CocoaError.fileNoSuchFile {
                continue
            } catch {
                failures.append((name, error.localizedDescription))
            }
        }
        return failures
    }

    // MARK: - 対象の選び方

    /// 録音が残っている会議を新しい順に並べる。記録中・処理中の会議（currentID）は並べない
    static func entries(_ meetings: [Meeting], excluding currentID: String?, directory: (Meeting) -> URL) -> [MeetingAudioEntry] {
        meetings
            .filter { $0.id != currentID && $0.status != .recording && $0.status != .processing }
            .compactMap { meeting in
                let dir = directory(meeting)
                guard !audioFiles(in: dir).isEmpty else { return nil }
                return MeetingAudioEntry(meeting: meeting, size: audioSize(in: dir), state: transcriptState(of: meeting))
            }
            .sorted { $0.meeting.startedAt > $1.meeting.startedAt }
    }

    /// まとめて消すとき（30 日より前・すべて・保存期間）の対象と、文字起こしがそろっていないので外したもの。
    /// days が nil ならすべて。記録を始めた日時が now から days×24 時間より前の会議を選ぶ
    static func bulkTargets(_ entries: [MeetingAudioEntry], olderThan days: Int?, now: Date)
        -> (targets: [MeetingAudioEntry], skipped: [MeetingAudioEntry])
    {
        let matched = entries.filter { entry in
            guard let days else { return true }
            return entry.meeting.startedAt < now.addingTimeInterval(-Double(days) * 24 * 3600)
        }
        return (matched.filter { $0.state == .complete }, matched.filter { $0.state != .complete })
    }

    /// 保存期間を過ぎた録音（retentionDays が 0 なら無期限で、何も選ばない）
    static func expired(_ entries: [MeetingAudioEntry], retentionDays: Int, now: Date) -> (targets: [MeetingAudioEntry], skipped: [MeetingAudioEntry]) {
        guard retentionDays > 0 else { return ([], []) }
        return bulkTargets(entries, olderThan: retentionDays, now: now)
    }

    static func totalSize(_ entries: [MeetingAudioEntry]) -> Int64 {
        entries.reduce(0) { $0 + $1.size }
    }

    static func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// 要件: REQ-MTG-055
extension MeetingStore {
    static func audioFiles(for meeting: Meeting) -> [URL] { MeetingAudioCleanup.audioFiles(in: directory(for: meeting)) }
    static func hasAudio(_ meeting: Meeting) -> Bool { !audioFiles(for: meeting).isEmpty }
    static func audioSize(for meeting: Meeting) -> Int64 { MeetingAudioCleanup.audioSize(in: directory(for: meeting)) }
    static func deleteAudio(for meeting: Meeting) -> [(file: String, reason: String)] {
        MeetingAudioCleanup.deleteAudio(in: directory(for: meeting))
    }
}
