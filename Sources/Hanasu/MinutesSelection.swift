import Foundation

// 要件: REQ-MTG-046
// 設計判断: DEC-MTG-094
/// 記録中に「オフレコ」にした区間（記録の経過時間の秒）。end が nil なら、まだオフレコ中か、記録の終わりまで
struct OffRecordSpan: Codable, Hashable, Identifiable {
    var id = UUID()
    var start: Double
    var end: Double?

    func contains(_ time: Double) -> Bool {
        start <= time && time < (end ?? .infinity)
    }
}

// 要件: REQ-MTG-044, REQ-MTG-045, REQ-MTG-046
/// 発言を議事録に使うか。使わないなら、その理由（文字起こしに添える）
enum MinutesUse: Equatable {
    case used
    /// 議事録から除いた（発言ごと）
    case excluded
    /// オフレコの区間の中
    case offRecord
    /// 除いた話者の発言
    case speakerExcluded
    /// 範囲（最初と最後）の外
    case outsideRange

    var isUsed: Bool { self == .used }

    /// 文字起こしに添える短い理由
    var label: String {
        switch self {
        case .used: ""
        case .excluded: tr("除外")
        case .offRecord: tr("オフレコ")
        case .speakerExcluded: tr("話者を除外")
        case .outsideRange: tr("範囲外")
        }
    }
}

/// 文字起こしに出す発言のまとまり。使う発言と使わない発言はまとめない
struct TranscriptDisplayBlock: Identifiable, Hashable {
    /// まとめた発言（ID は先頭の発言の ID）
    var block: Utterance
    /// まとめた発言の ID
    var members: [UUID]
    /// まとめた最後の発言の開始時刻（「ここまで議事録に使う」で、この発言まで入れるため）
    var lastStart: Double
    var use: MinutesUse
    var id: UUID { block.id }
}

// 要件: REQ-MTG-044, REQ-MTG-045, REQ-MTG-046
// 設計判断: DEC-MTG-090
extension Meeting {
    /// 発言を議事録に使うか。発言ごとの除外 → オフレコ → 話者 → 範囲 の順に理由を見る
    func minutesUse(of utterance: Utterance) -> MinutesUse {
        if excludedUtterances?.contains(utterance.id) == true { return .excluded }
        if isOffRecord(at: utterance.start) { return .offRecord }
        if excludedSpeakers?.contains(utterance.speaker) == true { return .speakerExcluded }
        if let minutesFrom, utterance.start < minutesFrom { return .outsideRange }
        if let minutesTo, utterance.start > minutesTo { return .outsideRange }
        return .used
    }

    /// その時刻がオフレコの区間の中か
    func isOffRecord(at time: Double) -> Bool {
        offRecord?.contains { $0.contains(time) } == true
    }

    /// 議事録に使う発言（時刻の順）
    var usedUtterances: [Utterance] {
        utterances.filter { minutesUse(of: $0).isUsed }.sorted { $0.start < $1.start }
    }

    /// 議事録の選び方（範囲・除外・オフレコ）を何か設定しているか
    var hasMinutesSelection: Bool {
        minutesFrom != nil || minutesTo != nil || !(excludedUtterances ?? []).isEmpty
            || !(excludedSpeakers ?? []).isEmpty || !(offRecord ?? []).isEmpty
    }

    // 設計判断: DEC-MTG-090
    /// 文字起こしに出すまとまり。mergedBlocks と同じく同じ話者の続く発言をまとめるが、使う・使わないが変わるところでは分ける
    /// （そのため、mergedBlocks の区切りは必ずここでも区切りになり、検索の飛び先の ID がそのまま使える）
    func displayBlocks(maxGap: Double = 2.0) -> [TranscriptDisplayBlock] {
        var blocks: [TranscriptDisplayBlock] = []
        for u in utterances.sorted(by: { $0.start < $1.start }) {
            let use = minutesUse(of: u)
            if var last = blocks.last, last.block.speaker == u.speaker, u.start - last.block.end <= maxGap, last.use == use {
                last.block = Self.joinUtterances(last.block, u)
                last.members.append(u.id)
                last.lastStart = u.start
                blocks[blocks.count - 1] = last
            } else {
                blocks.append(TranscriptDisplayBlock(block: u, members: [u.id], lastStart: u.start, use: use))
            }
        }
        return blocks
    }

    // 設計判断: DEC-MTG-091
    /// 議事録・AI に渡す発言のまとまり（使う発言だけ）
    func blocksForMinutes() -> [Utterance] {
        displayBlocks().filter(\.use.isUsed).map(\.block)
    }

    // MARK: - 変える

    /// 発言を除く・戻す
    mutating func setExcluded(_ ids: [UUID], excluded: Bool) {
        var set = excludedUtterances ?? []
        if excluded {
            for id in ids where !set.contains(id) { set.append(id) }
        } else {
            set.removeAll { ids.contains($0) }
        }
        excludedUtterances = set.isEmpty ? nil : set
        minutesOutdated = true
    }

    /// 話者の発言をすべて除く・戻す
    mutating func setSpeakerExcluded(_ speaker: String, excluded: Bool) {
        var set = excludedSpeakers ?? []
        if excluded {
            if !set.contains(speaker) { set.append(speaker) }
        } else {
            set.removeAll { $0 == speaker }
        }
        excludedSpeakers = set.isEmpty ? nil : set
        minutesOutdated = true
    }

    /// 発言を「使う」にする。発言ごとの除外を外し、範囲の外なら範囲を広げる（話者・オフレコで除いていれば使えない）
    mutating func include(_ ids: [UUID]) {
        setExcluded(ids, excluded: false)
        let starts = utterances.filter { ids.contains($0.id) }.map(\.start)
        if let first = starts.min(), let from = minutesFrom, first < from { minutesFrom = first }
        if let last = starts.max(), let to = minutesTo, last > to { minutesTo = last }
    }

    /// 議事録に使う範囲を変える（nil で端まで）。最初が最後より後になったら、もう一方を外す
    mutating func setMinutesRange(from: Double?? = .none, to: Double?? = .none) {
        if case .some(let value) = from {
            minutesFrom = value
            if let value, let minutesTo, minutesTo < value { self.minutesTo = nil }
        }
        if case .some(let value) = to {
            minutesTo = value
            if let value, let minutesFrom, minutesFrom > value { self.minutesFrom = nil }
        }
        minutesOutdated = true
    }

    /// オフレコの区間を消す（その間の発言をまた使う）
    mutating func removeOffRecord(_ id: OffRecordSpan.ID) {
        offRecord?.removeAll { $0.id == id }
        if offRecord?.isEmpty == true { offRecord = nil }
        minutesOutdated = true
    }

    /// 議事録の選び方をすべて元に戻す
    mutating func clearMinutesSelection() {
        minutesFrom = nil
        minutesTo = nil
        excludedUtterances = nil
        excludedSpeakers = nil
        offRecord = nil
        minutesOutdated = true
    }
}
