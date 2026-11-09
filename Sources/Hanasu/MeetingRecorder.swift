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
    // 設計判断: DEC-MTG-071
    /// 会議の一覧。ディスクからの読み込みは裏で行うので、起動直後は空で、読み終えたら入る（reloadMeetings）
    @Published private(set) var meetings: [Meeting] = []
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
    // 要件: REQ-MTG-013
    /// 議事録を作り直している会議。その間は削除させず（DEC-MTG-023）、会議ノートで作り直し中だとわかるように出す（DEC-MTG-070）。
    /// 描き出しの CLI からも入れる
    @Published var regeneratingID: String?
    // 要件: REQ-MTG-054
    // 設計判断: DEC-MTG-136
    /// 記録のあとの処理で出す段階（順番どおり）と、今の段階。処理していなければ空と nil。描き出しの CLI からも入れる
    @Published var processingStages: [MeetingProcessingStage] = []
    @Published var processingStage: MeetingProcessingStage?
    // 要件: REQ-MTG-054
    // 設計判断: DEC-MTG-136
    /// 記録中のメモの入力欄の、書きかけの文と書き始めた時刻（記録を止めるときに確定する）
    @Published var noteDraft = ""
    var noteDraftStartedAt: Double?

    var onStateChange: ((State) -> Void)?
    // 要件: REQ-MTG-034
    /// 会議の名前を読む対象のアプリ（優先順）。記録を始めるときに呼ぶ。AppDelegate が会議の自動検出につなぐ
    var titleSourceApps: () -> [MeetingApp] = { [] }
    var diarizer: SpeakerDiarizer = FluidAudioDiarizer()

    private let settings = AppSettings.shared
    private var micEngine: AVAudioEngine?
    private var systemTap: SystemAudioTap?
    private var meTranscriber: ChannelTranscriber?
    private var othersTranscriber: ChannelTranscriber?
    private var micObserver: NSObjectProtocol?
    private var levelTimer: Timer?
    private var recordingStartedAt = Date()

    // 要件: REQ-MTG-043
    /// 記録中に最初にスリープした時点（確認に答えるまで持つ）
    private var sleepPoint: MeetingSleepPoint?
    /// 今スリープしている間の、スリープした時刻
    private var sleptAt: Date?
    /// 記録を始めてから、スリープしていた時間の合計（秒。DEC-MTG-089）
    private var sleepGap: Double = 0
    /// スリープのあとの確認を出している
    private var askingAboutSleep = false
    private var powerObservers: [NSObjectProtocol] = []

    /// reloadMeetings を呼ぶたびに増やす。古い読み込みの結果が、新しいものを上書きしないための番号
    private var reloadGeneration = 0

    init() {
        reloadMeetings()
        observeSleep()
    }

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
        // 要件: REQ-MTG-053（記録の間は会議の音声を再生しない。再生した音がマイクに入るため）
        MeetingPlayer.shared.stop()
        lastError = nil
        noteDraft = ""
        noteDraftStartedAt = nil
        liveLines = []
        volatileMe = ""
        volatileOthers = ""
        sleepPoint = nil
        sleptAt = nil
        sleepGap = 0
        // prepare の途中で失敗したときに止めるための、まだ meTranscriber / othersTranscriber に入れていない文字起こし
        var preparing: [ChannelTranscriber] = []

        do {
            // 文字起こしのエンジンは、記録を始めたときの設定で決める（記録中に設定を変えても混ざらない）
            let engine = settings.meetingEngine
            try Self.checkReady(engine)
            try await Permissions.ensureRecordingPermissions(speechRecognition: engine.isLive)
            // 要件: REQ-MTG-034
            // 会議アプリのウインドウから会議の名前を読む（読めなければ日時のタイトル）。
            // 状態は .starting なので、読んでいる間にもう一度押しても二重には始まらない
            let detectedTitle = await MeetingTitle.detect(apps: titleSourceApps())
            var meeting = try MeetingStore.newMeeting()
            meeting.status = .recording
            if let detectedTitle { meeting.title = detectedTitle }
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
            // 以降で失敗しても teardownAudio で止められるよう、開始した時点で保持する
            systemTap = tap
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
            preparing = [me, others]
            async let preparedMe: Void = me.prepare(localeIdentifier: settings.localeIdentifier, contextualStrings: words)
            async let preparedOthers: Void = others.prepare(localeIdentifier: settings.localeIdentifier, contextualStrings: words)
            _ = try await (preparedMe, preparedOthers)

            othersBox.transcriber = others
            meTranscriber = me
            othersTranscriber = others
            preparing = []
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
            for transcriber in preparing { await transcriber.cancel() }
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

    // 要件: REQ-MTG-043
    /// 記録を止めて後処理に進む。cutAt を渡すと、そのスリープした時点で記録が終わったものとして、それより後に録った分を除く
    func stop(cutAt point: MeetingSleepPoint? = nil) async {
        guard state == .recording, let me = meTranscriber, let others = othersTranscriber else { return }
        // 要件: REQ-MTG-054
        // 設計判断: DEC-MTG-136（メモの入力欄の書きかけの文は、止めた時点のメモとして確定してから止める）
        commitNoteDraft()
        guard var meeting = current else { return }
        sleepPoint = nil
        NSSound(named: "Pop")?.play()
        // 設計判断: DEC-MTG-136
        processingStages = (batchEngine != nil ? [.transcribing] : []) + [.diarizing]
            + (settings.makeMeetingMinutes ? [.minutes] : [])
        processingStage = batchEngine != nil ? .transcribing : .diarizing
        setState(.processing(tr("文字起こしを確定しています…")))
        await teardownAudio()
        async let mePhrases = me.finish()
        async let otherPhrases = others.finish()
        var (mine, theirs) = await (mePhrases, otherPhrases)
        meTranscriber = nil
        othersTranscriber = nil

        // 設計判断: DEC-MTG-089
        meeting.duration = elapsed
        meeting.status = .processing
        // 設計判断: DEC-MTG-135（再生で 2 つのチャンネルを並べるため、音声の先頭のずれを残す）
        meeting.audioStartOffsets = [MeetingChannel.me.rawValue: me.audioStartOffset,
                                     MeetingChannel.others.rawValue: others.audioStartOffset]
        // 設計判断: DEC-MTG-094
        // オフレコのまま止めたら、記録の終わりまでをオフレコにする
        if let index = meeting.offRecord?.lastIndex(where: { $0.end == nil }) {
            meeting.offRecord?[index].end = meeting.duration
        }
        if let point {
            // 設計判断: DEC-MTG-088
            MeetingSleepCut.apply(to: &meeting, point: point)
            for channel in [MeetingChannel.me, .others] {
                let offset = channel == .me ? me.audioStartOffset : others.audioStartOffset
                do {
                    try await MeetingSleepCut.trimAudio(
                        at: MeetingStore.audioURL(for: meeting, channel: channel), toSeconds: point.cutoff(for: channel) - offset)
                } catch {
                    appLog.error("meeting audio trim failed (\(channel.rawValue, privacy: .public)): \(error.localizedDescription, privacy: .public)")
                }
            }
            appLog.notice("meeting cut at sleep: \(point.elapsed, privacy: .public)s")
        }
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
        if let point {
            mine = MeetingSleepCut.phrases(mine, before: point)
            theirs = MeetingSleepCut.phrases(theirs, before: point)
        }
        // 文字起こしに失敗したときは、音声を残さない設定でも消さない（あとで文字起こしし直せるように）
        meeting = await process(meeting, me: mine, others: theirs, keepAudio: transcriptionFailed)
        batchEngine = nil
        current = nil
        processingStages = []
        processingStage = nil
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
                errors.append(tr("%@の音声: %@", channel == .me ? tr("自分") : tr("相手"), "\(error.localizedDescription)"))
            }
        }
        let error = errors.isEmpty ? nil : tr("%@ で文字起こしできなかった部分があります（音声ファイルは残しています）。", "\(engine.shortName)") + errors.joined(separator: " / ")
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
        processingStage = .diarizing
        if !theirs.isEmpty, FileManager.default.fileExists(atPath: othersAudio.path) {
            setState(.processing(tr("話者を分けています…（初回はモデルをダウンロードします）")))
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
            setState(.processing(tr("同じ部屋の話者を分けています…")))
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

        // 設計判断: DEC-MTG-091, DEC-MTG-136（使う発言がなければ、議事録の段階を出さない）
        if meeting.usedUtterances.isEmpty { processingStages.removeAll { $0 == .minutes } }
        if settings.makeMeetingMinutes, !meeting.usedUtterances.isEmpty {
            processingStage = .minutes
            setState(.processing(tr("議事録を作成しています…")))
            do {
                // 要件: REQ-COM-032
                try await LocalModelDownloadPrompt.prepare(
                    for: .meeting, settings: settings, work: tr("議事録の作成"), whenSkipped: tr("議事録を作らずに、文字起こしだけを残します"))
                // 要件: REQ-COM-024
                let client = try TextAIClient.requireFromSettings(settings, for: .meeting, timeout: 300)
                let result = try await MeetingProcessor.makeMinutes(
                    for: meeting, client: client, model: settings.textModel(for: .meeting))
                // 要件: REQ-MTG-027
                meeting.applyMinutes(result)
            } catch {
                let message = tr("議事録を作れませんでした: %@", "\(error.localizedDescription)")
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
            lastError = tr("保存できませんでした: %@", "\(error.localizedDescription)")
        }
        return meeting
    }

    // MARK: - 編集

    func rename(_ meeting: Meeting, title: String) {
        update(meeting) { $0.title = title }
    }

    // 要件: REQ-MTG-008
    func renameSpeaker(_ meeting: Meeting, speaker: String, to name: String) {
        update(meeting) { $0.renameSpeaker(speaker, to: name) }
    }

    // 要件: REQ-MTG-008
    /// 複数の話者名を 1 回で付け替える（1 人ずつ保存すると、元の会議から書き直すので前の変更が消える）
    func renameSpeakers(_ meeting: Meeting, names: [String: String]) {
        guard !names.isEmpty else { return }
        update(meeting) { m in
            for (speaker, name) in names { m.renameSpeaker(speaker, to: name) }
        }
    }

    // 要件: REQ-MTG-013
    // 設計判断: DEC-MTG-061
    /// 議事録を作り直す。template を渡すと、その型に変えて作る（失敗したら型も元のまま）。
    func regenerateMinutes(_ meeting: Meeting, template: MinutesTemplate? = nil, customPrompt: String? = nil,
                           templateName: String? = nil) async {
        guard state == .idle else { return }
        // 設計判断: DEC-MTG-092
        // ビューの会議は古いことがある（選び方を変えた直後など）。一覧の最新から作る
        let meeting = meetings.first { $0.id == meeting.id } ?? meeting
        setState(.processing(tr("議事録を作り直しています…")))
        regeneratingID = meeting.id
        // 要件: REQ-MTG-053（作り直しの間は、その会議の再生を止める）
        if MeetingPlayer.shared.meetingID == meeting.id { MeetingPlayer.shared.stop() }
        defer { regeneratingID = nil }
        var updated = meeting
        do {
            // 要件: REQ-COM-032
            try await LocalModelDownloadPrompt.prepare(
                for: .meeting, settings: settings, work: tr("議事録の作成"), whenSkipped: tr("議事録は作り直しません"))
            let client = try TextAIClient.requireFromSettings(settings, for: .meeting, timeout: 300)
            var source = meeting
            if let template {
                source.minutesTemplate = template.rawValue
                source.customMinutesPrompt = template == .custom ? customPrompt : nil
                // 要件: REQ-MTG-042
                source.minutesTemplateName = template == .custom ? templateName : nil
            }
            let result = try await MeetingProcessor.makeMinutes(
                for: source, client: client, model: settings.textModel(for: .meeting))
            updated.minutesTemplate = source.minutesTemplate
            updated.customMinutesPrompt = source.customMinutesPrompt
            updated.minutesTemplateName = source.minutesTemplateName
            // 要件: REQ-MTG-027
            updated.applyMinutes(result)
            updated.errorMessage = nil
            // 設計判断: DEC-MTG-092
            updated.minutesOutdated = nil
        } catch {
            updated.errorMessage = tr("議事録を作れませんでした: %@", "\(error.localizedDescription)")
        }
        try? MeetingStore.save(updated)
        reloadMeetings()
        setState(.idle)
    }

    // MARK: - 議事録に使う発言（MinutesSelection.swift）

    // 要件: REQ-MTG-044, REQ-MTG-045, REQ-MTG-046
    /// 議事録に使う発言の選び方を変えられるか。記録中・処理中・議事録の作り直し中の会議は変えない（処理の保存で消えるため）
    func canEditMinutesSelection(_ meeting: Meeting) -> Bool {
        meeting.id != current?.id && meeting.id != regeneratingID && meeting.status != .processing
    }

    // 要件: REQ-MTG-044, REQ-MTG-045, REQ-MTG-046
    // 設計判断: DEC-MTG-090, DEC-MTG-092
    /// 議事録に使う発言の選び方を変えて保存する（議事録は作り直さない）
    func changeMinutesSelection(_ meeting: Meeting, _ change: (inout Meeting) -> Void) {
        guard canEditMinutesSelection(meeting) else { return }
        // ビューの会議は一覧の読み直しが終わるまで古い。続けて押したときに前の変更を消さないよう、
        // 一覧の最新に当て、一覧もすぐ書き換える
        guard let index = meetings.firstIndex(where: { $0.id == meeting.id }) else {
            update(meeting, change)
            return
        }
        guard MeetingStore.exists(meetings[index]) else {
            reloadMeetings()
            return
        }
        var updated = meetings[index]
        change(&updated)
        try? MeetingStore.save(updated)
        meetings[index] = updated
        reloadMeetings()
    }

    // 要件: REQ-MTG-046
    /// 記録中のオフレコの区間（終わっていないもの）。オフレコでなければ nil
    var openOffRecord: OffRecordSpan? {
        guard state == .recording else { return nil }
        return current?.offRecord?.last(where: { $0.end == nil })
    }

    // 要件: REQ-MTG-046
    // 設計判断: DEC-MTG-094
    /// 記録中に「オフレコ」を始める・終える。押すたびに保存する
    func toggleOffRecord() {
        guard state == .recording, var meeting = current else { return }
        var spans = meeting.offRecord ?? []
        if let index = spans.lastIndex(where: { $0.end == nil }) {
            spans[index].end = max(spans[index].start, elapsed)
        } else {
            spans.append(OffRecordSpan(start: elapsed))
        }
        meeting.offRecord = spans
        current = meeting
        try? MeetingStore.save(meeting)
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

    // 設計判断: DEC-MTG-071
    /// 会議の一覧を読み直す。ファイルの読み込みと復号はメインスレッドの外で行い、結果だけをメインに戻す。
    /// 読み終えるまでは前の一覧を出したままにする（空にしない）。続けて呼ばれたら、最後の呼び出しの結果だけを使う
    func reloadMeetings() {
        reloadGeneration += 1
        let generation = reloadGeneration
        Task { [weak self] in
            let loaded = await Task.detached(priority: .userInitiated) { MeetingStore.loadAll() }.value
            guard let self, generation == self.reloadGeneration else { return }
            self.meetings = loaded
        }
    }

    // MARK: - 削除

    // 要件: REQ-MTG-028
    // 設計判断: DEC-MTG-023
    /// 消してよい会議か。記録中・処理中の会議と、議事録を作り直している会議は消さない
    func canDelete(_ meeting: Meeting) -> Bool {
        meeting.id != current?.id && meeting.id != regeneratingID
    }

    // 要件: REQ-MTG-028
    // 設計判断: DEC-MTG-022
    /// 会議のフォルダをゴミ箱に移し、一覧から外す
    func delete(_ meeting: Meeting) throws {
        guard canDelete(meeting) else { return }
        try MeetingStore.moveToTrash(meeting)
        appLog.notice("meeting moved to trash: \(meeting.id, privacy: .private)")
        reloadMeetings()
    }

    // MARK: - メモと「ここ重要」の印（MeetingNotes.swift）

    // 設計判断: DEC-MTG-089
    /// 録音開始からの経過秒数。スリープしていた時間は除く（音声と文字起こしの時刻に合わせる）
    var elapsed: Double {
        current.map { max(0, Date().timeIntervalSince($0.startedAt) - sleepGap) } ?? 0
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

    // 要件: REQ-MTG-054
    // 設計判断: DEC-MTG-136
    /// メモの入力欄の書きかけの文を、メモとして確定する（記録を止めるとき）
    func commitNoteDraft() {
        let text = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { addNote(text, at: noteDraftStartedAt) }
        noteDraft = ""
        noteDraftStartedAt = nil
    }

    // 設計判断: DEC-MTG-043
    /// 記録中の会議にメモを足して、すぐ保存する（アプリが落ちてもメモは残る）
    private func appendNote(_ note: MeetingNote) {
        guard state == .recording, var meeting = current else { return }
        meeting.notes = (meeting.notes ?? []) + [note]
        current = meeting
        try? MeetingStore.save(meeting)
    }

    /// 会議ノートを PNG に描き出す確認用に、ディスクの会議の代わりに架空の会議を一覧に入れる（CLI の --render-meeting-window）
    func showMeetingsForRendering(_ meetings: [Meeting]) {
        reloadGeneration += 1  // 裏で読んでいる一覧で上書きしない
        self.meetings = meetings
    }

    /// 確認用に、記録を止めたあとの処理中（段階）の状態にする（CLI の --render-meeting-window）
    func showProcessingForRendering(_ meeting: Meeting, lines: [LiveLine], stages: [MeetingProcessingStage],
                                    stage: MeetingProcessingStage, message: String) {
        current = meeting
        liveLines = lines
        processingStages = stages
        processingStage = stage
        state = .processing(message)
    }

    /// 記録中の画面を PNG に描き出す確認用に、録音せずに「記録中」の状態にする（CLI の --render-meeting-notes）
    func showPreviewForRendering(_ meeting: Meeting, lines: [LiveLine], volatileOthers: String = "") {
        current = meeting
        liveLines = lines
        self.volatileOthers = volatileOthers
        state = .recording
    }

    // MARK: - Private

    // 設計判断: DEC-MTG-023
    /// 会議を書き換えて保存する。フォルダがもうない（消した）会議は保存し直さない
    private func update(_ meeting: Meeting, _ change: (inout Meeting) -> Void) {
        guard MeetingStore.exists(meeting) else {
            reloadMeetings()
            return
        }
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
                    self.lastError = tr("マイクを再開できませんでした: %@", "\(error.localizedDescription)")
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

    // MARK: - スリープ

    // 要件: REQ-MTG-043
    // 設計判断: DEC-MTG-087
    private func observeSleep() {
        let center = NSWorkspace.shared.notificationCenter
        powerObservers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.systemWillSleep() }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.systemDidWake() }
            },
        ]
    }

    // 設計判断: DEC-MTG-087, DEC-MTG-088
    /// スリープする直前。記録中なら、どこまで録ったかを覚える（答える前に繰り返しスリープしたら、最初の時点のまま）
    private func systemWillSleep() {
        guard state == .recording, let me = meTranscriber, let others = othersTranscriber else { return }
        let now = Date()
        sleptAt = now
        guard sleepPoint == nil else { return }
        var ends: [MeetingChannel: Double] = [:]
        ends[.me] = me.audioEnd
        ends[.others] = others.audioEnd
        sleepPoint = MeetingSleepPoint(at: now, elapsed: elapsed, audioEnds: ends)
        appLog.notice("meeting: system will sleep while recording (\(self.elapsed, privacy: .public)s)")
    }

    // 設計判断: DEC-MTG-087, DEC-MTG-089
    /// スリープから戻った。スリープしていた時間を経過時間から除き、記録中なら止めるか続けるかを聞く
    private func systemDidWake() {
        if let sleptAt {
            sleepGap += max(0, Date().timeIntervalSince(sleptAt))
            self.sleptAt = nil
        }
        guard state == .recording, let point = sleepPoint, !askingAboutSleep else { return }
        appLog.notice("meeting: woke while recording; asking whether to stop at the sleep point")
        // 通知を返してから出す（runModal の間、ほかの通知も受け取れるように）。
        // 印は今立てる（Task が走る前に復帰の通知がもう一度来ても、確認を 2 つ出さない）
        askingAboutSleep = true
        Task { @MainActor [weak self] in await self?.askAboutSleep(point) }
    }

    // 要件: REQ-MTG-043
    // 設計判断: DEC-MTG-087
    /// 「スリープ前までで止める」か「記録を続ける」かを聞く。確認を出している間も記録は続ける
    private func askAboutSleep(_ point: MeetingSleepPoint) async {
        let time = DateFormatter.localizedString(from: point.at, dateStyle: .none, timeStyle: .short)
        let alert = NSAlert()
        alert.messageText = tr("会議の記録中に Mac がスリープしました")
        alert.informativeText = tr("%@ にスリープしてから、記録を続けています。スリープする前までで記録を止めるか、このまま記録を続けるかを選んでください。", time)
        alert.addButton(withTitle: tr("スリープ前までで止める"))
        alert.addButton(withTitle: tr("記録を続ける"))
        NSApp.activate()
        let response = alert.runModal()
        askingAboutSleep = false
        // 確認の間に、ほかの手段で記録を止めていたら何もしない
        guard state == .recording, let latest = sleepPoint else { return }
        if response == .alertFirstButtonReturn {
            appLog.notice("meeting: stopping at the sleep point")
            await stop(cutAt: latest)
        } else {
            appLog.notice("meeting: continuing after sleep")
            sleepPoint = nil
        }
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
                notes.append(tr("マイク（自分）の音が入っていません。設定の「会議」→「録音するマイク」を確認してください。"))
            }
            if others.lastSoundAt == nil {
                notes.append(tr("相手側（スピーカー）の音が入っていません。会議の音が出ている機器を、設定の「会議」→「録音するスピーカー」で選んでください。"))
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
