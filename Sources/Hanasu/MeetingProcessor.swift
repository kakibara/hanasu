import Foundation

/// 話者分離の結果の 1 区間
struct SpeakerTurn: Hashable {
    var speakerId: String
    var start: Double
    var end: Double
}

// 設計判断: DEC-MTG-010
/// 相手側の音声ファイルを話者ごとの区間に分ける部品。実装を差し替えられるようにしておく。
protocol SpeakerDiarizer {
    func diarize(audioURL: URL) async throws -> [SpeakerTurn]
}

/// 話者分離をしない（相手側は全部「相手」になる）
struct NoSpeakerDiarizer: SpeakerDiarizer {
    func diarize(audioURL: URL) async throws -> [SpeakerTurn] { [] }
}

/// 録音の後処理: 話者の割り当て、回り込みの除去、議事録の作成。
enum MeetingProcessor {
    // 要件: REQ-MTG-004
    /// 自分と相手の発話から、話者つきの発言を作る。
    /// - Parameters:
    ///   - turns: 相手側の話者分離の結果。空なら相手側は "others" 1 人として扱う。
    ///   - micTurns: マイク側の話者分離の結果（会議室などで 1 つのマイクを複数人で使うとき）。
    ///     空ならマイク側は全部「自分」。あれば、いちばん長く話している人を「自分」、ほかを同席者にする。
    static func buildUtterances(me: [TranscribedPhrase], others: [TranscribedPhrase], turns: [SpeakerTurn],
                                micTurns: [SpeakerTurn] = []) -> [Utterance] {
        var theirs: [Utterance] = []
        if turns.isEmpty {
            theirs = others.map { Utterance(speaker: "others", start: $0.start, end: $0.end, text: $0.text) }
        } else {
            for phrase in others {
                theirs += split(words(of: phrase), by: turns)
            }
            theirs = renumberSpeakers(theirs)
        }

        let mineGroups = removeEcho(from: me, comparedTo: others)
        var mine: [Utterance]
        if micTurns.isEmpty {
            mine = mineGroups.compactMap { group in
                guard let first = group.first, let last = group.last else { return nil }
                let text = group.map(\.text).joined().trimmingCharacters(in: .whitespaces)
                return Utterance(speaker: "me", start: first.start, end: last.end, text: text)
            }
        } else {
            mine = labelMicSpeakers(mineGroups.flatMap { split($0, by: micTurns) }, turns: micTurns)
        }
        return (mine + theirs).sorted { $0.start < $1.start }
    }

    private static func words(of phrase: TranscribedPhrase) -> [TimedWord] {
        phrase.words.isEmpty ? [TimedWord(text: phrase.text, start: phrase.start, end: phrase.end)] : phrase.words
    }

    // 設計判断: DEC-MTG-011
    /// マイク側の話者分離の ID を付け直す。話した時間がいちばん長い人を「自分」（me）、
    /// ほかを登場順に同席者（room1, room2, ...）にする。
    static func labelMicSpeakers(_ utterances: [Utterance], turns: [SpeakerTurn]) -> [Utterance] {
        var talkTime: [String: Double] = [:]
        for turn in turns { talkTime[turn.speakerId, default: 0] += turn.end - turn.start }
        let main = talkTime.max { $0.value < $1.value }?.key
        var mapping: [String: String] = [:]
        return utterances.sorted { $0.start < $1.start }.map { u in
            var u = u
            if mapping[u.speaker] == nil {
                let rooms = mapping.values.filter { $0.hasPrefix("room") }.count
                mapping[u.speaker] = u.speaker == main ? "me" : "room\(rooms + 1)"
            }
            u.speaker = mapping[u.speaker]!
            return u
        }
    }

    // 設計判断: DEC-MTG-012
    /// 語を話者へ割り当て、同じ話者が続く語をまとめる。
    static func split(_ words: [TimedWord], by turns: [SpeakerTurn]) -> [Utterance] {
        var result: [Utterance] = []
        for word in words {
            // 無音のあとの語は無音の分まで長くなるので、語の終わり寄りの時刻で話者を決める
            let coreStart = max(word.start, word.end - 0.4)
            let speaker = speaker(at: (coreStart + word.end) / 2, wordStart: coreStart, in: turns)
            if var last = result.last, last.speaker == speaker {
                // 語は 1 つの区間の中のもので、語の前の空白（英語など）を持つのでそのままつなぐ。Whisper の語はトークンなので
                // 語の途中（「Gem」「ini」）で切れることがあり、空白を足すと崩れる。区間どうしは joinUtterances でつなぐ（DEC-COM-174）
                last.text += word.text
                last.end = word.end
                result[result.count - 1] = last
            } else {
                result.append(Utterance(speaker: speaker, start: word.start, end: word.end, text: word.text))
            }
        }
        return result.map { var u = $0; u.text = u.text.trimmingCharacters(in: .whitespaces); return u }
            .filter { !$0.text.isEmpty }
    }

    // 設計判断: DEC-MTG-012
    /// その時刻を含む区間の話者。区間と区間のすき間にある語は、前の区間の終わりから間があいて
    /// 始まっていれば次の話者（話者分離は話し始めの検出が遅れがち）、そうでなければ前の話者とする。
    static func speaker(at time: Double, wordStart: Double? = nil, in turns: [SpeakerTurn], pause: Double = 0.3) -> String {
        if let hit = turns.first(where: { $0.start <= time && time <= $0.end }) {
            return hit.speakerId
        }
        let previous = turns.filter { $0.end < time }.max { $0.end < $1.end }
        let next = turns.filter { $0.start > time }.min { $0.start < $1.start }
        switch (previous, next) {
        case let (p?, n?):
            return (wordStart ?? time) - p.end > pause ? n.speakerId : p.speakerId
        case let (p?, nil): return p.speakerId
        case let (nil, n?): return n.speakerId
        case (nil, nil): return "others"
        }
    }

    // 設計判断: DEC-MTG-012
    /// 話者分離の ID（"S1" など）を、登場順に spk1, spk2, ... に付け直す。
    static func renumberSpeakers(_ utterances: [Utterance]) -> [Utterance] {
        var mapping: [String: String] = [:]
        return utterances.sorted { $0.start < $1.start }.map { u in
            var u = u
            if mapping[u.speaker] == nil { mapping[u.speaker] = "spk\(mapping.count + 1)" }
            u.speaker = mapping[u.speaker]!
            return u
        }
    }

    // 設計判断: DEC-MTG-013
    /// スピーカーの音がマイクに回り込んで「自分」として二重に記録された部分を除き、残った語のまとまりを返す。
    /// 自分の発話を語ごとに「相手が話している時間と重なるか」で区切り、重なる部分の文字が
    /// その時間の相手の発言とよく似ていれば回り込みとみなして捨てる。
    static func removeEcho(from mine: [TranscribedPhrase], comparedTo theirs: [TranscribedPhrase],
                           margin: Double = 0.3, threshold: Double = 0.5) -> [[TimedWord]] {
        let theirWords = theirs.flatMap { $0.words.isEmpty ? [TimedWord(text: $0.text, start: $0.start, end: $0.end)] : $0.words }
        // 無音のあとの最初の語は、無音の分まで長い時間が付くことがあるので、語の終わり寄りだけで判定する
        func core(_ w: TimedWord) -> (start: Double, end: Double) { (max(w.start, w.end - 0.4), w.end) }
        func overlapsTheirSpeech(_ w: TimedWord) -> Bool {
            let mine = core(w)
            return theirWords.contains {
                let their = core($0)
                return their.start - margin <= mine.end && mine.start <= their.end + margin
            }
        }
        func theirText(from start: Double, to end: Double) -> String {
            theirs.filter { $0.start - 1.5 <= end && start <= $0.end + 1.5 }.map(\.text).joined()
        }

        var result: [[TimedWord]] = []
        for phrase in mine {
            let words = words(of: phrase)
            // 重なる／重ならないが同じ語の連続でまとめる
            var groups: [(overlap: Bool, words: [TimedWord])] = []
            for word in words {
                let overlap = overlapsTheirSpeech(word)
                if let last = groups.last, last.overlap == overlap {
                    groups[groups.count - 1].words.append(word)
                } else {
                    groups.append((overlap, [word]))
                }
            }
            for group in groups {
                let text = group.words.map(\.text).joined().trimmingCharacters(in: .whitespaces)
                guard let first = group.words.first, let last = group.words.last, !text.isEmpty else { continue }
                if group.overlap, similarity(text, theirText(from: first.start, to: last.end)) >= threshold {
                    continue  // 回り込み
                }
                // 句読点だけの断片は直前の自分の発言にくっつける
                if text.allSatisfy({ $0.isPunctuation || $0.isWhitespace }) {
                    if var prev = result.last, var lastWord = prev.popLast() {
                        lastWord.text = TextSpacing.join(lastWord.text, text)
                        prev.append(lastWord)
                        result[result.count - 1] = prev
                    }
                    continue
                }
                result.append(group.words)
            }
        }
        return result
    }

    /// 文字 bigram の包含率（a の bigram のうち b にも含まれる割合）
    static func similarity(_ a: String, _ b: String) -> Double {
        func bigrams(_ s: String) -> [String] {
            let chars = Array(s.filter { !$0.isWhitespace && !$0.isPunctuation })
            guard chars.count >= 2 else { return chars.map(String.init) }
            return (0..<chars.count - 1).map { String(chars[$0...$0 + 1]) }
        }
        let ga = bigrams(a)
        guard !ga.isEmpty else { return 0 }
        let gb = Set(bigrams(b))
        return Double(ga.filter(gb.contains).count) / Double(ga.count)
    }

    // MARK: - 議事録

    // 要件: REQ-MTG-006
    /// 議事録を作る。見出しの構成は会議の型（meeting.template）で決まる（MinutesTemplate.swift）。
    /// メモか印があれば、それを優先するよう指示を足す（MeetingNotes.swift）。
    static func makeMinutes(for meeting: Meeting, client: TextAIClient, model: String) async throws -> MinutesResult {
        // 要件: REQ-COM-061（応答は、送ったときのプロンプトの言語で読む。作っている間に設定が変わってもずれないように）
        let language = PromptLanguage.current
        var instruction = MinutesPrompt.systemInstruction(template: meeting.template, customPrompt: meeting.customMinutesPrompt)
        if meeting.notesForPrompt() != nil { instruction += "\n" + notesInstruction }
        // 要件: REQ-MTG-052
        // 設計判断: DEC-MTG-134（ローカル・Apple の AI で文字起こしを縮めて送ったときは、根拠の時刻の印を残さない）
        let report = LongInputReport()
        let body = try await LongInputReport.$current.withValue(report) {
            try await client.generate(
                systemInstruction: instruction, userText: MinutesPrompt.userText(for: meeting), model: model, effort: .medium)
        }
        let result = MinutesPrompt.parse(body, title: meeting.title, language: language)
        return report.shortened ? MinutesCitation.stripped(result) : result
    }
}
