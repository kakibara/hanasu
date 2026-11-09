import Foundation

// 要件: REQ-DIC-073, REQ-DIC-074
// 設計判断: DEC-DIC-172
/// 会議の文字起こしに辞書の置き換えルールを当てる・認識したままの文に戻す。
/// 置き換えは発言ごとに、認識したままの文（rawText。なければ text）から当てる。text が変わったときだけ rawText を残す。
enum MeetingDictionary {
    /// 当てた（戻した）結果
    struct Outcome: Equatable {
        var meeting: Meeting
        /// 当てる前と比べて text が変わった発言の数
        var changed: Int
        /// 辞書で置き換えてある（rawText のある）発言の数
        var replaced: Int
    }

    /// 発言に今の辞書を当てる（認識したままの文から）
    static func apply(_ dictionary: UserDictionary, to utterance: Utterance) -> Utterance {
        var u = utterance
        let recognized = utterance.recognizedText
        let text = dictionary.apply(to: recognized)
        u.text = text
        u.rawText = text == recognized ? nil : recognized
        return u
    }

    /// 会議のすべての発言に今の辞書を当てる
    static func apply(_ dictionary: UserDictionary, to meeting: Meeting) -> Outcome {
        rewrite(meeting) { apply(dictionary, to: $0) }
    }

    /// 会議のすべての発言を、認識したままの文に戻す
    static func revert(_ meeting: Meeting) -> Outcome {
        rewrite(meeting) { u in
            var u = u
            u.text = u.recognizedText
            u.rawText = nil
            return u
        }
    }

    // 要件: REQ-DIC-073
    // 設計判断: DEC-DIC-173
    /// 記録を止めて文字起こしが確定した直後に呼ぶ。設定がオフなら何もしない
    static func applyOnFinish(_ meeting: Meeting, dictionary: UserDictionary, enabled: Bool) -> Meeting {
        guard enabled, !dictionary.rules.isEmpty else { return meeting }
        return apply(dictionary, to: meeting).meeting
    }

    /// 辞書で置き換えてある発言の数
    static func replacedCount(_ meeting: Meeting) -> Int {
        meeting.utterances.filter { $0.rawText != nil }.count
    }

    // 設計判断: DEC-DIC-174
    /// 発言を書き換え、変わった数を数える。変わって議事録があれば、作り直しを促す
    private static func rewrite(_ meeting: Meeting, _ change: (Utterance) -> Utterance) -> Outcome {
        var updated = meeting
        var changed = 0
        updated.utterances = meeting.utterances.map { u in
            let new = change(u)
            if new.text != u.text { changed += 1 }
            return new
        }
        if changed > 0, updated.minutes != nil { updated.minutesOutdated = true }
        return Outcome(meeting: updated, changed: changed, replaced: replacedCount(updated))
    }
}

// 要件: REQ-DIC-074
/// 会議に辞書を当て直せなかった理由
enum MeetingDictionaryError: Error, Equatable {
    /// 記録中・後処理中・議事録の作り直し中か、使う発言がない
    case busy
    /// 会議のフォルダがない（消した）
    case missing
    case saveFailed(String)

    var message: String {
        let reason: String
        switch self {
        case .busy: reason = tr("記録中・処理中か、議事録を作り直しているところか、議事録に使う発言がありません。")
        case .missing: reason = tr("会議のフォルダが見つかりません。")
        case .saveFailed(let detail): reason = detail
        }
        return tr("この会議を変えられませんでした: %@", reason)
    }
}
