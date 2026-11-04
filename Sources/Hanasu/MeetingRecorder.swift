@preconcurrency import AVFoundation
import AppKit
import AudioToolbox
import Foundation

/// 会議の記録: マイクとシステム音声を録り、文字起こし → 話者分離 → 議事録 → 保存 まで行う。
@MainActor
final class MeetingRecorder: ObservableObject {
    enum State: Equatable {
        case idle
        case starting
        case recording
        case processing(String)
    }

    struct LiveLine: Identifiable, Hashable {
        let id = UUID()
        let channel: MeetingChannel
        let start: Double
        let text: String
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var meetings: [Meeting] = MeetingStore.loadAll()
    @Published private(set) var current: Meeting?
    @Published private(set) var liveLines: [LiveLine] = []
    @Published private(set) var volatileMe = ""
    @Published private(set) var volatileOthers = ""
    @Published var lastError: String?
    /// 記録中の音量（0〜1）
    @Published private(set) var meLevel: Float = 0
    @Published private(set) var othersLevel: Float = 0
    /// 音が入っていないときの注意
    @Published private(set) var warnings: [String] = []
    /// 記録中の会議を、記録のあとにまとめて文字起こしするエンジン（Whisper / Gemini）。nil なら Mac 標準のライブ文字起こし
    @Published private(set) var batchEngine: TranscriptionEngine?

    var onStateChange: ((State) -> Void)?
    var diarizer: SpeakerDiarizer = FluidAudioDiarizer()

    private let settings = AppSettings.shared
    private var micEngine: AVAudioEngine?
    private var systemTap: SystemAudioTap?
    private var meTranscriber: ChannelTranscriber?
    private var othersTranscriber: ChannelTranscriber?
    private var micObserver: NSObjectProtocol?
    private var levelTimer: Timer?
    private var recordingStartedAt = Date()

    var isRecording: Bool { state == .recording }

    // MARK: - 開始・停止

    // 要件: REQ-MTG-001
    func toggle() {
        switch state {
        case .idle: Task { await start() }
        case .recording: Task { await stop() }
        default: break
        }
    }

    // 要件: REQ-MTG-002
    // 設計判断: DEC-MTG-001, DEC-DIC-085
    func start() async {
        guard state == .idle else { return }
        setState(.starting)
        lastError = nil
        liveLines = []
        volatileMe = ""
        volatileOthers = ""

        do {
            // 文字起こしのエンジンは、記録を始めたときの設定で決める（記録中に設定を変えても混ざらない）
            let engine = settings.meetingEngine
            try Self.checkReady(engine)
            try await Permissions.ensureRecordingPermissions(speechRecognition: engine.isLive)
            var meeting = try MeetingStore.newMeeting()
            meeting.status = .recording
            MinutesTemplateStore.apply(to: &meeting)
            try MeetingStore.save(meeting)
            current = meeting

            // システム音声（相手側）
            let tap = SystemAudioTap()
            let othersBox = TranscriberBox()
            let outputUID = settings.meetingOutputDeviceUID
            try tap.start(outputDeviceUID: outputUID.isEmpty ? nil : outputUID) { buffer in
                othersBox.transcriber?.append(buffer)
            }
            guard let tapFormat = tap.format else { throw SystemAudioTapError.unsupportedFormat }
            let others = ChannelTranscriber(
                channel: .others, inputFormat: tapFormat,
                fileURL: MeetingStore.audioURL(for: meeting, channel: .others), meetingStart: meeting.startedAt,
                live: engine.isLive)

            // マイク（自分）。エンジンは録音にもそのまま使う（ノードはエンジンを保持しないので、
            // エンジンを変数に持たないまま inputNode に触ると解放済みのメモリを読んで落ちる）
            let micEngine = Self.makeMicEngine(inputDeviceUID: settings.meetingInputDeviceUID)
            let micFormat = micEngine.inputNode.inputFormat(forBus: 0)
            guard micFormat.sampleRate > 0 else { throw SpeechRecognizerError.noInputDevice }
            let me = ChannelTranscriber(
                channel: .me, inputFormat: micFormat,
                fileURL: MeetingStore.audioURL(for: meeting, channel: .me), meetingStart: meeting.startedAt,
                live: engine.isLive)

            for transcriber in [me, others] {
                transcriber.onPhrase = { [weak self] phrase in self?.receive(phrase) }
                transcriber.onVolatile = { [weak self, channel = transcriber.channel] text in
                    if channel == .me { self?.volatileMe = text } else { self?.volatileOthers = text }
                }
            }
            let words = settings.userDictionary.contextualStrings
            async let preparedMe: Void = me.prepare(localeIdentifier: settings.localeIdentifier, contextualStrings: words)
            async let preparedOthers: Void = others.prepare(localeIdentifier: settings.localeIdentifier, contextualStrings: words)
            _ = try await (preparedMe, preparedOthers)

            othersBox.transcriber = others
            systemTap = tap
            meTranscriber = me
            othersTranscriber = others
            try startMic(for: me, engine: micEngine)

            batchEngine = engine.isLive ? nil : engine
            recordingStartedAt = Date()
            startLevelTimer()
            setState(.recording)
            MeetingHighlightHotKey.shared.activate { [weak self] in self?.addHighlight() }
            NSSound(named: "Tink")?.play()
            appLog.notice("meeting recording started: \(meeting.id, privacy: .public)")
        } catch {
            appLog.error("meeting start failed: \(error.localizedDescription, privacy: .public)")
            await teardownAudio()
            await meTranscriber?.cancel()
            await othersTranscriber?.cancel()
            meTranscriber = nil
            othersTranscriber = nil
            if var meeting = current {
                meeting.status = .failed
                meeting.errorMessage = error.localizedDescription
                try? MeetingStore.save(meeting)
            }
            current = nil
            lastError = error.localizedDescription
            reloadMeetings()
            setState(.idle)
        }
    }

    func stop() async {
        guard state == .recording, var meeting = current, let me = meTranscriber, let others = othersTranscriber else { return }
        NSSound(named: "Pop")?.play()
        setState(.processing("文字起こしを確定しています…"))
        await teardownAudio()
        async let mePhrases = me.finish()
        async let otherPhrases = others.finish()
        var (mine, theirs) = await (mePhrases, otherPhrases)
        meTranscriber = nil
        othersTranscriber = nil

        meeting.duration = Date().timeIntervalSince(meeting.startedAt)
        meeting.status = .processing
        current = meeting
        var transcriptionFailed = false
        if let engine = batchEngine {
            // Whisper / Gemini: 書き出した音声ファイルから、チャンネルごとに時刻つきで文字起こしする
            try? MeetingStore.save(meeting)
            let result = await transcribeRecordedAudio(
                meeting, engine: engine, offsets: [.me: me.audioStartOffset, .others: others.audioStartOffset])
            (mine, theirs) = (result.me, result.others)
            if let error = result.error {
                meeting.errorMessage = error
                transcriptionFailed = true
            }
        }
        // 文字起こしに失敗したときは、音声を残さない設定でも消さない（あとで文字起こしし直せるように）
        meeting = await process(meeting, me: mine, others: theirs, keepAudio: transcriptionFailed)
        batchEngine = nil
        current = nil
        reloadMeetings()
        setState(.idle)
    }

    // 設計判断: DEC-MTG-007
    /// Whisper / Gemini を選んでいるときに、記録を始められるかを確かめる
    static func checkReady(_ engine: TranscriptionEngine) throws {
        switch engine {
        case .apple:
            break
        case .whisper:
            let model = AppSettings.shared.whisperModel
            guard WhisperModelStore.isDownloaded(model) else {
                WhisperModelStore.shared.ensureDownloaded(model)
                throw BatchTranscriptionError.whisperModelMissing(model)
            }
        case .gemini:
            guard try GeminiTranscriber.auth(settings: AppSettings.shared) != nil else { throw BatchTranscriptionError.noCredentials }
        }
    }

    // 設計判断: DEC-MTG-009
    /// 記録した音声ファイル（me.m4a / others.m4a）を、Whisper / Gemini で文字起こしする。CLI の動作確認からも使う。
    /// - Parameter offsets: チャンネルごとの、音声ファイルの先頭が録音開始から何秒後か
    /// - Returns: 失敗したチャンネルがあれば error にその説明が入る（できたチャンネルの結果は返す）
    func transcribeRecordedAudio(_ meeting: Meeting, engine: TranscriptionEngine, offsets: [MeetingChannel: Double])
        async -> (me: [TranscribedPhrase], others: [TranscribedPhrase], error: String?)
    {
        var phrases: [MeetingChannel: [TranscribedPhrase]] = [:]
        var errors: [String] = []
        for channel in [MeetingChannel.me, .others] {
            do {
                phrases[channel] = try await MeetingBatchTranscription.transcribe(
                    audioURL: MeetingStore.audioURL(for: meeting, channel: channel), channel: channel,
                    offset: offsets[channel] ?? 0, engine: engine, settings: settings,
                    progress: { [weak self] message in self?.setState(.processing(message)) })
            } catch {
                appLog.error("meeting batch transcription failed (\(channel.rawValue, privacy: .public)): \(String(describing: error), privacy: .public)")
                errors.append("\(channel == .me ? "自分" : "相手")の音声: \(error.localizedDescription)")
            }
        }
        let error = errors.isEmpty ? nil : "\(engine.shortName) で文字起こしできなかった部分があります（音声ファイルは残しています）。" + errors.joined(separator: " / ")
        return (phrases[.me] ?? [], phrases[.others] ?? [], error)
    }

    // 要件: REQ-MTG-010
    // 設計判断: DEC-MTG-009, DEC-MTG-015
    /// 後処理（話者分離 → 並べ替え → 議事録 → 保存）。CLI の動作確認からも使う。
    /// 音声を残さない設定のときは、最後（話者分離と文字起こしのあと）に音声ファイルを消す。keepAudio なら消さない
    func process(_ meeting: Meeting, me mine: [TranscribedPhrase], others theirs: [TranscribedPhrase],
                 keepAudio: Bool = false) async -> Meeting {
        var meeting = meeting
        var turns: [SpeakerTurn] = []
        let othersAudio = MeetingStore.audioURL(for: meeting, channel: .others)
        if !theirs.isEmpty, FileManager.default.fileExists(atPath: othersAudio.path) {
            setState(.processing("話者を分けています…（初回はモデルをダウンロードします）"))
            do {
                turns = try await diarizer.diarize(audioURL: othersAudio)
            } catch {
                appLog.error("diarization failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        // マイク側（会議室で同じマイクを使う人がいるとき）
        var micTurns: [SpeakerTurn] = []
        let meAudio = MeetingStore.audioURL(for: meeting, channel: .me)
        if settings.diarizeMicChannel, !mine.isEmpty, FileManager.default.fileExists(atPath: meAudio.path) {
            setState(.processing("同じ部屋の話者を分けています…"))
            do {
                micTurns = try await diarizer.diarize(audioURL: meAudio)
            } catch {
                appLog.error("mic diarization failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        if ProcessInfo.processInfo.environment["HANASU_DEBUG"] != nil {
            for t in turns { print("turn \(t.speakerId) \(String(format: "%.2f-%.2f", t.start, t.end))") }
            for t in micTurns { print("mic turn \(t.speakerId) \(String(format: "%.2f-%.2f", t.start, t.end))") }
        }
        meeting.utterances = MeetingProcessor.buildUtterances(me: mine, others: theirs, turns: turns, micTurns: micTurns)
        try? MeetingStore.save(meeting)
        appLog.notice("meeting transcribed: me=\(mine.count) others=\(theirs.count) utterances=\(meeting.utterances.count) speakers=\(meeting.speakers.count)")

        if settings.makeMeetingMinutes, !meeting.utterances.isEmpty {
            setState(.processing("議事録を作成しています…"))
            do {
                // 要件: REQ-COM-024
                let client = try TextAIClient.requireFromSettings(settings, for: .meeting, timeout: 300)
                let result = try await MeetingProcessor.makeMinutes(
                    for: meeting, client: client, model: settings.textModel(for: .meeting))
                meeting.minutes = result.markdown
                meeting.actionItems = result.actionItems
            } catch {
                let message = "議事録を作れませんでした: \(error.localizedDescription)"
                meeting.errorMessage = meeting.errorMessage.map { $0 + "\n" + message } ?? message
                appLog.error("minutes failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        meeting.status = .done
        if !settings.keepMeetingAudio, !keepAudio {
            for channel in [MeetingChannel.me, .others] {
                try? FileManager.default.removeItem(at: MeetingStore.audioURL(for: meeting, channel: channel))
            }
        }
        do {
            try MeetingStore.save(meeting)
        } catch {
            lastError = "保存できませんでした: \(error.localizedDescription)"
        }
        return meeting
    }

    // MARK: - 編集

    func rename(_ meeting: Meeting, title: String) {
        update(meeting) { $0.title = title }
    }

    // 要件: REQ-MTG-008
    func renameSpeaker(_ meeting: Meeting, speaker: String, to name: String) {
        update(meeting) { $0.speakerNames[speaker] = name }
    }

    // 要件: REQ-MTG-013
    // 設計判断: DEC-MTG-061
    /// 議事録を作り直す。template を渡すと、その型に変えて作る（失敗したら型も元のまま）。
    func regenerateMinutes(_ meeting: Meeting, template: MinutesTemplate? = nil, customPrompt: String? = nil) async {
        guard state == .idle else { return }
        setState(.processing("議事録を作り直しています…"))
        var updated = meeting
        do {
            let client = try TextAIClient.requireFromSettings(settings, for: .meeting, timeout: 300)
            var source = meeting
            if let template {
                source.minutesTemplate = template.rawValue
                source.customMinutesPrompt = template == .custom ? customPrompt : nil
            }
            let result = try await MeetingProcessor.makeMinutes(
                for: source, client: client, model: settings.textModel(for: .meeting))
            updated.minutesTemplate = source.minutesTemplate
            updated.customMinutesPrompt = source.customMinutesPrompt
            updated.minutes = result.markdown
            updated.actionItems = result.actionItems
            updated.errorMessage = nil
        } catch {
            updated.errorMessage = "議事録を作れませんでした: \(error.localizedDescription)"
        }
        try? MeetingStore.save(updated)
        reloadMeetings()
        setState(.idle)
    }

    /// リマインダーに登録したアクションアイテムに印を付ける（古い議事録は、読み取った一覧ごと保存する）
    func markRemindersAdded(_ meeting: Meeting, items: [ActionItem], reminderIDs: [UUID: String]) {
        update(meeting) { m in
            m.actionItems = items.map { item in
                var item = item
                if let id = reminderIDs[item.id] { item.reminderID = id }
                return item
            }
        }
    }

    func reloadMeetings() {
        meetings = MeetingStore.loadAll()
    }

    // MARK: - メモと「ここ重要」の印（MeetingNotes.swift）

    /// 録音開始からの経過秒数
    var elapsed: Double {
        current.map { Date().timeIntervalSince($0.startedAt) } ?? 0
    }

    // 要件: REQ-MTG-011
    /// 記録中のメモを 1 行足す。time は書き始めた時刻（録音開始からの秒数）。省略すると今の時刻。
    func addNote(_ text: String, at time: Double? = nil) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        appendNote(MeetingNote(kind: .note, time: time ?? elapsed, text: text))
    }

    // 要件: REQ-MTG-012
    /// 今の時刻に「ここ重要」の印を付ける
    func addHighlight(_ text: String = "") {
        guard state == .recording else { return }
        appendNote(MeetingNote(kind: .highlight, time: elapsed, text: text.trimmingCharacters(in: .whitespacesAndNewlines)))
        NSSound(named: "Morse")?.play()
    }

    /// 記録中のメモを消す。「ここ重要」の印は、付けてから 10 秒以内のものだけ（undoHighlight）
    func removeNote(id: MeetingNote.ID) {
        guard state == .recording, var meeting = current,
              let note = meeting.allNotes.first(where: { $0.id == id }) else { return }
        if note.kind == .highlight {
            undoHighlight(id: id)
            return
        }
        meeting.notes?.removeAll { $0.id == id }
        current = meeting
        try? MeetingStore.save(meeting)
    }

    /// 今取り消せる「ここ重要」の印（付けてから 10 秒以内のいちばん新しいもの）。記録中でなければ nil
    var undoableHighlight: MeetingNote? {
        guard state == .recording else { return nil }
        return current?.undoableHighlight(at: elapsed)
    }

    // 要件: REQ-MTG-012
    // 設計判断: DEC-MTG-047
    /// 付けてから 10 秒以内の「ここ重要」の印を取り消す。取り消せたら true
    @discardableResult
    func undoHighlight(id: MeetingNote.ID) -> Bool {
        guard state == .recording, var meeting = current, undoableHighlight?.id == id else { return false }
        meeting.notes?.removeAll { $0.id == id }
        current = meeting
        try? MeetingStore.save(meeting)
        return true
    }

    /// 記録後にメモを書き換える
    @discardableResult
    func updateNotes(_ meeting: Meeting, notes: [MeetingNote]) -> Meeting {
        var updated = meeting
        updated.notes = notes
        try? MeetingStore.save(updated)
        reloadMeetings()
        return updated
    }

    // 設計判断: DEC-MTG-043
    /// 記録中の会議にメモを足して、すぐ保存する（アプリが落ちてもメモは残る）
    private func appendNote(_ note: MeetingNote) {
        guard state == .recording, var meeting = current else { return }
        meeting.notes = (meeting.notes ?? []) + [note]
        current = meeting
        try? MeetingStore.save(meeting)
    }

    /// 記録中の画面を PNG に描き出す確認用に、録音せずに「記録中」の状態にする（CLI の --render-meeting-notes）
    func showPreviewForRendering(_ meeting: Meeting, lines: [LiveLine], volatileOthers: String = "") {
        current = meeting
        liveLines = lines
        self.volatileOthers = volatileOthers
        state = .recording
    }

    // MARK: - Private

    private func update(_ meeting: Meeting, _ change: (inout Meeting) -> Void) {
        var updated = meeting
        change(&updated)
        try? MeetingStore.save(updated)
        reloadMeetings()
    }

    // 要件: REQ-MTG-003
    private func receive(_ phrase: TranscribedPhrase) {
        liveLines.append(LiveLine(channel: phrase.channel, start: phrase.start, text: phrase.text))
        liveLines.sort { $0.start < $1.start }
        if phrase.channel == .me { volatileMe = "" } else { volatileOthers = "" }
    }

    private func teardownAudio() async {
        MeetingHighlightHotKey.shared.deactivate()
        stopMic()
        systemTap?.stop()
        systemTap = nil
        levelTimer?.invalidate()
        levelTimer = nil
        meLevel = 0
        othersLevel = 0
        warnings = []
    }

    // MARK: - マイク

    // 設計判断: DEC-MTG-004
    /// 設定で選んだマイク（未指定ならシステムの設定）を入力にしたエンジン
    nonisolated static func makeMicEngine(inputDeviceUID uid: String) -> AVAudioEngine {
        let engine = AVAudioEngine()
        if !uid.isEmpty, let device = AudioDevices.device(uid: uid), let unit = engine.inputNode.audioUnit {
            var id = device.id
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                 &id, UInt32(MemoryLayout<AudioObjectID>.size))
        }
        return engine
    }

    // 設計判断: DEC-MTG-004
    /// マイクの録音を始める。機器の構成が変わったら（Bluetooth の切り替えなど）作り直す。
    private func startMic(for me: ChannelTranscriber, engine given: AVAudioEngine? = nil) throws {
        stopMic()
        let engine = given ?? Self.makeMicEngine(inputDeviceUID: settings.meetingInputDeviceUID)
        // マイクを切り替えると outputFormat は切り替え前の機器のままなので、機器側の実際の形式を使う
        let format = engine.inputNode.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw SpeechRecognizerError.noInputDevice }
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            me.append(buffer)
        }
        engine.prepare()
        try engine.start()
        micEngine = engine
        appLog.notice("meeting mic: \(format.sampleRate, privacy: .public)Hz \(format.channelCount)ch")
        micObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.state == .recording, let me = self.meTranscriber else { return }
                appLog.notice("meeting mic configuration changed; restarting")
                do {
                    try self.startMic(for: me)
                } catch {
                    self.lastError = "マイクを再開できませんでした: \(error.localizedDescription)"
                }
            }
        }
    }

    private func stopMic() {
        if let micObserver { NotificationCenter.default.removeObserver(micObserver) }
        micObserver = nil
        micEngine?.inputNode.removeTap(onBus: 0)
        micEngine?.stop()
        micEngine = nil
    }

    // MARK: - 音量と注意

    private func startLevelTimer() {
        levelTimer?.invalidate()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateLevels() }
        }
    }

    // 設計判断: DEC-MTG-020
    private func updateLevels() {
        guard let me = meTranscriber, let others = othersTranscriber else { return }
        meLevel = me.level
        othersLevel = others.level
        // 始めてから 10 秒たっても一度も音が入らなければ、機器の選び方が違う可能性が高い
        var notes: [String] = []
        if Date().timeIntervalSince(recordingStartedAt) > 10 {
            if me.lastSoundAt == nil {
                notes.append("マイク（自分）の音が入っていません。設定の「会議」→「録音するマイク」を確認してください。")
            }
            if others.lastSoundAt == nil {
                notes.append("相手側（スピーカー）の音が入っていません。会議の音が出ている機器を、設定の「会議」→「録音するスピーカー」で選んでください。")
            }
        }
        if notes != warnings { warnings = notes }
    }

    private func setState(_ newState: State) {
        state = newState
        onStateChange?(newState)
    }
}

/// オーディオスレッドから、あとで用意できた ChannelTranscriber を参照するための入れ物
private final class TranscriberBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _transcriber: ChannelTranscriber?
    var transcriber: ChannelTranscriber? {
        get { lock.withLock { _transcriber } }
        set { lock.withLock { _transcriber = newValue } }
    }
}
