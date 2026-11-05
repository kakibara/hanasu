import Foundation

// 設計判断: DEC-COM-030
/// 録った音声（16 kHz モノラル）を inline data で Gemini の generateContent に送り、文字起こしだけをさせる。
/// 整形は別の呼び出し（GeminiClient.refine）で行う。間に辞書の置き換えとスニペットの照合を挟むため。
struct GeminiTranscriber {
    var auth: GeminiClient.Auth
    var model: String
    /// 会議を分けて送るときの 1 区切りの長さ（秒）。環境変数 HANASU_GEMINI_CHUNK_SECONDS で変えられる（区切りの確認用）
    static var meetingChunkSeconds: Double {
        ProcessInfo.processInfo.environment["HANASU_GEMINI_CHUNK_SECONDS"].flatMap(Double.init) ?? 300
    }
    /// 同時に送る区切りの数
    static let maxConcurrentRequests = 3

    /// 認証: 環境変数 GEMINI_SERVICE_ACCOUNT_JSON（CLI での確認用）→ 設定 → 環境変数 GEMINI_API_KEY の順
    static func auth(settings: AppSettings) throws -> GeminiClient.Auth? {
        let env = ProcessInfo.processInfo.environment
        if let path = env["GEMINI_SERVICE_ACCOUNT_JSON"], !path.isEmpty {
            return .serviceAccount(try ServiceAccountCredentials.load(path: path), location: settings.vertexLocation)
        }
        if let auth = try GeminiClient.authFromSettings(settings) { return auth }
        if let key = env["GEMINI_API_KEY"], !key.isEmpty { return .apiKey(key) }
        return nil
    }

    // MARK: - 音声入力

    // 要件: REQ-COM-061
    static func dictationInstruction(localeIdentifier: String) -> String {
        Prompts.text("transcribe.dictation.system", ["languageNote": languageNote(localeIdentifier)])
    }

    // 設計判断: DEC-COM-031
    /// 音声入力用。全文を返す。何も話されていなければ空文字
    func transcribe(_ samples: [Float], localeIdentifier: String, hints: [String]) async throws -> String {
        let audio = try TranscriptionAudio.encodeForUpload(samples[...])
        let client = GeminiClient(auth: auth, timeout: 60)
        do {
            return try await client.generate(
                systemInstruction: Self.dictationInstruction(localeIdentifier: localeIdentifier),
                parts: Self.parts(audio: audio, hints: hints, note: Prompts.text("transcribe.dictation.user")),
                model: model)
        } catch GeminiError.emptyResponse(let reason) where reason == nil || reason == "STOP" {
            return ""
        }
    }

    // MARK: - 会議

    // 要件: REQ-COM-061
    static func meetingInstruction(localeIdentifier: String) -> String {
        Prompts.text("transcribe.meeting.system", ["languageNote": languageNote(localeIdentifier)])
    }

    static var meetingSchema: [String: Any] { [
        "type": "OBJECT",
        "properties": [
            "segments": [
                "type": "ARRAY",
                "items": [
                    "type": "OBJECT",
                    "properties": [
                        "start": ["type": "STRING", "description": Prompts.text("transcribe.schema.start")],
                        "end": ["type": "STRING", "description": Prompts.text("transcribe.schema.end")],
                        "text": ["type": "STRING"],
                    ],
                    "required": ["start", "end", "text"],
                ],
            ],
        ],
        "required": ["segments"],
    ] }

    // 設計判断: DEC-MTG-008
    /// 会議用。長い音声は meetingChunkSeconds ごとに分けて送り、時刻は区切りの開始時刻を足して全体の時刻にする
    func transcribeSegments(_ samples: [Float], localeIdentifier: String, hints: [String],
                            progress: (@MainActor (String) -> Void)? = nil) async throws -> [TimedSegment] {
        guard !samples.isEmpty else { return [] }
        let starts = TranscriptionAudio.chunkStarts(samples, length: Self.meetingChunkSeconds)
        let ranges = starts.indices.map { i in starts[i]..<(i + 1 < starts.count ? starts[i + 1] : samples.count) }
        let total = ranges.count
        let client = GeminiClient(auth: auth, timeout: 300)
        let instruction = Self.meetingInstruction(localeIdentifier: localeIdentifier)
        let schema = Self.meetingSchema
        let language = PromptLanguage.current
        let model = self.model
        var done = 0
        await progress?("Gemini で文字起こししています…（0/\(total)）")

        var results: [Int: [TimedSegment]] = [:]
        try await withThrowingTaskGroup(of: (Int, [TimedSegment]).self) { group in
            var next = 0
            func addNext() {
                guard next < ranges.count else { return }
                let index = next
                let range = ranges[index]
                next += 1
                group.addTask {
                    let offset = Double(range.lowerBound) / TranscriptionAudio.sampleRate
                    let duration = Double(range.count) / TranscriptionAudio.sampleRate
                    // 無音だけの区切りは送らない
                    if TranscriptionAudio.rms(samples[range]) < 0.0005 { return (index, []) }
                    let audio = try TranscriptionAudio.encodeForUpload(samples[range])
                    let note = total > 1
                        ? Prompts.text("transcribe.meeting.chunkUser", ["index": "\(index + 1)", "total": "\(total)", "start": Self.clock(offset)], language: language)
                        : Prompts.text("transcribe.meeting.user", language: language)
                    let json = try await client.generate(
                        systemInstruction: instruction,
                        parts: Self.parts(audio: audio, hints: hints, note: note),
                        model: model,
                        responseSchema: schema)
                    if ProcessInfo.processInfo.environment["HANASU_DEBUG"] != nil {
                        print(String(format: "gemini chunk %d/%d %.1f-%.1fs: %@", index + 1, total, offset, offset + duration, json))
                    }
                    return (index, try Self.parseSegments(json, duration: duration).map { segment in
                        var s = segment
                        s.start += offset
                        s.end += offset
                        return s
                    })
                }
            }
            for _ in 0..<min(Self.maxConcurrentRequests, ranges.count) { addNext() }
            while let (index, segments) = try await group.next() {
                results[index] = segments
                done += 1
                await progress?("Gemini で文字起こししています…（\(done)/\(total)）")
                addNext()
            }
        }
        return ranges.indices.flatMap { results[$0] ?? [] }
    }

    // 設計判断: DEC-MTG-008
    /// JSON の応答を区間にする。時刻は区切りの長さに収め、終わりが始まりより前にならないようにする
    static func parseSegments(_ json: String, duration: Double) throws -> [TimedSegment] {
        struct Envelope: Decodable {
            struct Segment: Decodable {
                var start: String
                var end: String
                var text: String
            }
            var segments: [Segment]
        }
        guard let data = json.data(using: .utf8) else { throw GeminiError.invalidResponse }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        var previousEnd = 0.0
        return envelope.segments.compactMap { segment in
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, var start = parseTime(segment.start) else { return nil }
            start = min(max(start, 0), duration)
            var end = parseTime(segment.end).map { min(max($0, start), duration) } ?? start
            if end <= start { end = min(start + 1, duration) }
            // 時刻が前後したときは、直前の区間の終わりにそろえる
            if start < previousEnd - 5 { start = previousEnd; end = max(end, start) }
            previousEnd = end
            return TimedSegment(start: start, end: end, text: text)
        }
    }

    /// "MM:SS.s" / "HH:MM:SS" / "83.4" を秒にする
    static func parseTime(_ value: String) -> Double? {
        let parts = value.trimmingCharacters(in: .whitespaces).split(separator: ":").map { Double($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        return parts.compactMap { $0 }.reduce(0) { $0 * 60 + $1 }
    }

    // MARK: - Private

    // 要件: REQ-COM-061
    /// 言語名はプロンプトの言語で書く（日本語なら「日本語（日本）」）
    private static func languageNote(_ localeIdentifier: String) -> String {
        let language = PromptLanguage.current
        let locale = language == .ja ? Locale(identifier: "ja-JP") : language.locale
        let name = locale.localizedString(forIdentifier: localeIdentifier) ?? localeIdentifier
        return Prompts.text("transcribe.languageNote", ["language": name], language: language)
    }

    private static func parts(audio: (data: Data, mimeType: String), hints: [String], note: String) -> [[String: Any]] {
        var text = note
        if let prompt = WhisperEngine.prompt(from: hints) {
            text += "\n" + Prompts.text("transcribe.dictionary", ["words": prompt])
        }
        return [
            ["inlineData": ["mimeType": audio.mimeType, "data": audio.data.base64EncodedString()]],
            ["text": text],
        ]
    }

    private static func clock(_ seconds: Double) -> String {
        String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}
