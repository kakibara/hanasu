import Foundation

// 要件: REQ-MTG-027
// 設計判断: DEC-MTG-068, DEC-MTG-069
/// 議事録の応答の <speaker_names> から、会話で分かった話者の名前を読み、名前のない話者に付ける。
/// 名前を付けた話者は meeting.inferredSpeakers に入れ、議事録の本文とアクションアイテムの担当の「話者1」なども名前に置き換える。
/// Windows 版の SpeakerNameInference（windows/Hanasu.Core/Meetings/SpeakerNameInference.cs）と同じ決まり（両方を直す）。
enum SpeakerNameInference {
    static let openTag = "<speaker_names>"
    static let closeTag = "</speaker_names>"
    /// 名前の末尾から外す敬称（長いものから見る）
    static let honorifics = ["ちゃん", "さん", "さま", "くん", "様", "君", "氏"]
    static let maxLength = 20

    /// 応答から <speaker_names> を取り出して本文から消す。表示ラベル（「話者1」など）→ 名前。読めなければ空
    static func extract(from response: String) -> (body: String, names: [String: String]) {
        guard let open = response.range(of: openTag, options: .backwards) else { return (response, [:]) }
        let rest = response[open.upperBound...]
        let close = rest.range(of: closeTag)
        var json = String(close.map { rest[..<$0.lowerBound] } ?? rest)
        json = json.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
        var body = response
        body.removeSubrange(open.lowerBound..<(close?.upperBound ?? response.endIndex))
        // <speaker_names> をコードブロックで囲んで返したときの残り
        body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        while let fence = ["```xml", "```json", "```"].first(where: body.hasSuffix) {
            body = String(body.dropLast(fence.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var names: [String: String] = [:]
        if let data = json.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (label, value) in object {
                if let name = value as? String { names[label.trimmingCharacters(in: .whitespacesAndNewlines)] = name }
            }
        }
        return (body, names)
    }

    /// 名前として使える形にする。使えなければ nil（空・長すぎる・改行や制御文字・「話者1」などのラベルそのもの）
    static func cleanName(_ raw: String, language: PromptLanguage = .current) -> String? {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let honorific = honorifics.first(where: { name.hasSuffix($0) && name.count > $0.count }) {
            name = String(name.dropLast(honorific.count)).trimmingCharacters(in: .whitespaces)
        }
        guard !name.isEmpty, name.count <= maxLength,
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0) }),
              !isPlaceholder(name, language: language) else { return nil }
        return name
    }

    /// 名前ではない値（「自分」「相手」「話者1」「同席者1」と、分からないことを表す言葉）
    // 要件: REQ-COM-061
    /// 見るのは、議事録を作ったときのプロンプトの言語のラベルと、前から使っている日本語のラベルだけ。
    /// ほかの言語のラベルまで見ると、「Ben」（トルコ語の「自分」）や「Saya」のような実際の名前を捨ててしまう
    static func isPlaceholder(_ name: String, language: PromptLanguage = .current) -> Bool {
        let lowered = name.lowercased()
        if ["自分", "相手", "不明", "なし", "null", "unknown"].contains(lowered) { return true }  // skip-tr
        let labels = ["speaker.me", "speaker.others", "minutes.result.none"].map { Prompts.text($0, language: language) }
        if labels.contains(where: { $0.lowercased() == lowered }) { return true }
        if name.range(of: #"^(話者|同席者)[0-9０-９]+$"#, options: .regularExpression) != nil { return true }  // skip-tr（ラベルの形。FUT-014）
        return ["speaker.remote", "speaker.room"].map { Prompts.text($0, language: language) }.contains { template in
            let pattern = "^" + NSRegularExpression.escapedPattern(for: template)
                .replacingOccurrences(of: NSRegularExpression.escapedPattern(for: "${n}"), with: "[0-9０-９]+") + "$"
            return name.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    /// 名前のない話者（「自分」を除く）に、応答の名前を付ける。付けた話者キー → 名前を返す。
    /// minutes の本文とアクションアイテムの担当の中のラベルも、付けた名前に置き換える
    @discardableResult
    static func apply(_ names: [String: String], to meeting: inout Meeting, minutes: inout MinutesResult) -> [String: String] {
        guard !names.isEmpty else { return [:] }
        var labelToKey: [String: String] = [:]
        for key in meeting.speakers where key != "me" && (meeting.speakerNames[key] ?? "").isEmpty {
            // 要件: REQ-COM-061（応答のラベルは、プロンプトに書いたラベルと同じ言語）
            labelToKey[meeting.promptName(for: key, language: minutes.language)] = key
        }
        var applied: [(key: String, label: String, name: String)] = []
        for label in names.keys.sorted() {
            guard let key = labelToKey[label], let name = cleanName(names[label] ?? "", language: minutes.language) else { continue }
            applied.append((key, label, name))
        }
        guard !applied.isEmpty else { return [:] }
        var inferred = meeting.inferredSpeakers ?? []
        for a in applied {
            meeting.speakerNames[a.key] = a.name
            if !inferred.contains(a.key) { inferred.append(a.key) }
            // 「相手」はふつうの言葉でもあるので、本文は置き換えない（担当がちょうど「相手」のときだけ）
            if a.key != "others" { minutes.markdown = replaceLabel(a.label, with: a.name, in: minutes.markdown) }
            for index in minutes.actionItems.indices {
                guard let owner = minutes.actionItems[index].owner else { continue }
                minutes.actionItems[index].owner = owner == a.label ? a.name
                    : (a.key == "others" ? owner : replaceLabel(a.label, with: a.name, in: owner))
            }
        }
        meeting.inferredSpeakers = inferred
        return Dictionary(uniqueKeysWithValues: applied.map { ($0.key, $0.name) })
    }

    /// 「話者1」を名前に置き換える。「話者10」の「話者1」は置き換えない（後ろに数字が続くときは別の話者）
    static func replaceLabel(_ label: String, with name: String, in text: String) -> String {
        let pattern = NSRegularExpression.escapedPattern(for: label) + "(?![0-9０-９])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text),
                                              withTemplate: NSRegularExpression.escapedTemplate(for: name))
    }
}

extension Meeting {
    // 要件: REQ-MTG-027
    /// 議事録の結果を会議に入れる。応答で分かった話者の名前も、名前のない話者に付ける（SpeakerNameInference）
    mutating func applyMinutes(_ result: MinutesResult) {
        var result = result
        SpeakerNameInference.apply(result.speakerNames, to: &self, minutes: &result)
        minutes = result.markdown
        actionItems = result.actionItems
    }

    // 要件: REQ-MTG-008
    // 設計判断: DEC-MTG-069
    /// 話者名を手で付け替える。推測で付けた名前を直したら（消したときも）、推測の印を外す
    mutating func renameSpeaker(_ speaker: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (speakerNames[speaker] ?? "") != trimmed else { return }
        speakerNames[speaker] = trimmed.isEmpty ? nil : trimmed
        inferredSpeakers?.removeAll { $0 == speaker }
        if inferredSpeakers?.isEmpty == true { inferredSpeakers = nil }
    }

    /// 会話から推測して付けた名前か
    func isInferredName(_ speaker: String) -> Bool {
        inferredSpeakers?.contains(speaker) == true && !(speakerNames[speaker] ?? "").isEmpty
    }
}
