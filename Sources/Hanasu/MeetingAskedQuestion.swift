import AppKit
import Combine
import Foundation

// 要件: REQ-MTG-047
// 設計判断: DEC-MTG-095, DEC-MTG-096, DEC-MTG-098
/// 会議の記録中に「何を聞かれた？」を確かめる。押した時点の直近の記録を AI に渡して、いちばん新しい質問・依頼と背景をまとめさせる。
/// ウインドウの AI チャットを待たずに聞き、答えが出たらその会議の AI チャットの会話に入れる。
/// 字幕のボタン・ショートカットからは前面のパネル（MeetingAskedQuestionPanel）に、チャットのボタンからはチャットの中に出す
@MainActor
final class MeetingAskedQuestion: ObservableObject {
    static let shared = MeetingAskedQuestion()

    /// どこから押したか
    enum Origin {
        /// 字幕のボタン・ショートカット（前面のパネルに出す）
        case panel
        /// 会議ノートの AI チャットのよく使う質問（チャットの中に出す）
        case chat
    }

    enum Phase: Equatable {
        /// 使えない（理由）
        case unavailable(String)
        case running
        case answered(String)
        case failed(String)
    }

    /// 押した 1 回分
    struct Request: Equatable {
        var id = UUID()
        var meetingID: String
        var origin: Origin
        /// 押した時点（録音開始からの秒数）
        var at: Double
        /// AI を待たずに出す、相手の直近の発言
        var recentOthers: [MeetingChat.Line]
        /// オフレコ中・相手の音声が入っていないときの知らせ
        var notice: String?
        var phase: Phase
        /// 押したときの会話の世代（「新しい会話」のあとは、チャットに失敗や知らせを出さない）
        var generation = 0
    }

    /// 会議ノートのウインドウに、その会議の AI チャットを開いてもらう依頼（ウインドウが受け取ったら consume する）
    struct OpenChatRequest: Equatable {
        var id = UUID()
        var meetingID: String
    }

    @Published private(set) var request: Request?
    @Published private(set) var openChatRequest: OpenChatRequest?

    /// AI を呼ぶ部分（確認用に差し替える）。渡すのは組み立てたプロンプト
    var reply: (MeetingChat.Prompt) async throws -> String = MeetingAskedQuestion.replyWithSettings
    /// 会議ノートのウインドウを前に出す（AppDelegate が入れる）
    var openMeetingWindow: () -> Void = {}

    private var task: Task<Void, Never>?
    /// 最後に押したときの記録（「もう一度」に使う）
    private(set) weak var recorder: MeetingRecorder?
    /// その記録が記録中か（パネルの「もう一度」を、記録を止めたら押せなくする）
    @Published private(set) var recording = false
    private var recorderState: AnyCancellable?

    // MARK: - 状態

    func isRunning(for meetingID: String) -> Bool {
        request?.meetingID == meetingID && request?.phase == .running
    }

    /// チャットから押した質問（その会議の、今の会話の世代のもの）
    private func chatRequest(for meetingID: String, generation: Int) -> Request? {
        guard let request, request.meetingID == meetingID, request.origin == .chat,
              request.generation == generation else { return nil }
        return request
    }

    /// チャットから押して失敗したときの理由（チャットの中に出す）。「新しい会話」のあとは出さない
    func failure(for meetingID: String, generation: Int) -> String? {
        switch chatRequest(for: meetingID, generation: generation)?.phase {
        case .failed(let message), .unavailable(let message): message
        default: nil
        }
    }

    /// チャットから押したときの、オフレコ中・相手の音声が入っていないときの知らせ
    func notice(for meetingID: String, generation: Int) -> String? {
        chatRequest(for: meetingID, generation: generation)?.notice
    }

    /// ボタンのヘルプ
    static var helpText: String {
        let settings = MeetingNotesSettings.shared
        return settings.askedHotKeyEnabled
            ? tr("直前に聞かれたことと、その背景を AI がまとめます（%@）", "\(settings.askedHotKey.displayString)")
            : tr("直前に聞かれたことと、その背景を AI がまとめます")
    }

    static func unavailableMessage(engine: String) -> String {
        tr("記録を止めたあとに文字起こしするエンジン（%@）では使えません。", "\(engine)")
    }

    // 要件: REQ-MTG-047
    /// 使えない理由。使えるなら nil
    static func unavailableReason(recording: Bool, batchEngineName: String?) -> String? {
        if !recording { return tr("会議を記録している間だけ使えます。") }
        if let batchEngineName { return unavailableMessage(engine: batchEngineName) }
        return nil
    }

    // MARK: - 押したとき

    /// 字幕のボタン・ショートカット・チャットのボタンから呼ぶ
    func ask(recorder: MeetingRecorder, origin: Origin) {
        watch(recorder)
        let recording = recorder.state == .recording && recorder.current != nil
        if let reason = Self.unavailableReason(recording: recording, batchEngineName: recorder.batchEngine?.shortName) {
            guard origin == .panel else { return }
            task?.cancel()
            request = Request(meetingID: recorder.current?.id ?? "", origin: origin, at: recorder.elapsed,
                              recentOthers: [], phase: .unavailable(reason))
            MeetingAskedQuestionPanel.shared.show()
            return
        }
        guard let meeting = recorder.current, let live = MeetingChat.liveMaterial(recorder: recorder) else { return }
        // 設計判断: DEC-MTG-098（同じ会議で作っている途中なら、新しくは送らない）
        if isRunning(for: meeting.id) {
            if origin == .panel { MeetingAskedQuestionPanel.shared.show() }
            return
        }
        var notice: String?
        if meeting.isOffRecord(at: live.elapsed) {
            notice = tr("オフレコ中です。オフレコの間の発言は AI に渡しません。")
        } else if recorder.othersSilent {
            notice = tr("相手側（スピーカー）の音が入っていません。相手の発言がないので、質問を見つけられないことがあります。")
        }
        let material = MeetingChat.askedMaterial(from: live, notes: meeting.allNotes)
        start(material: material, meetingID: meeting.id, origin: origin, notice: notice,
              model: MeetingChatStore.shared.model(for: meeting.id))
    }

    /// 「もう一度」: 今の時点の記録で聞き直す
    func retry() {
        guard let recorder, recording else { return }
        let origin = request?.origin ?? .panel
        cancel()
        ask(recorder: recorder, origin: origin)
    }

    /// 「やめる」: この質問だけをやめる（ウインドウのチャットには触れない）
    func cancel() {
        task?.cancel()
        task = nil
        guard request?.phase == .running else { return }
        if request?.origin == .chat {
            request = nil
        } else {
            request?.phase = .failed(tr("やめました。"))
        }
    }

    /// パネルを閉じたとき。チャットから押した質問は、パネルを閉じても続ける
    func dismiss() {
        guard request?.origin == .panel else { return }
        if request?.phase == .running { cancel() }
        request = nil
    }

    /// 記録の状態を見る（「もう一度」を押せるか）
    private func watch(_ recorder: MeetingRecorder) {
        guard self.recorder !== recorder || recorderState == nil else { return }
        self.recorder = recorder
        recorderState = recorder.$state
            .map { $0 == .recording }
            .removeDuplicates()
            .sink { [weak self] in self?.recording = $0 }
    }

    /// 記録を始めたとき: 別の会議のパネルは閉じる（DEC-MTG-096）
    func recordingStarted(meetingID: String) {
        guard let request, request.meetingID != meetingID else { return }
        task?.cancel()
        self.request = nil
        MeetingAskedQuestionPanel.shared.close()
    }

    // 要件: REQ-MTG-047
    // 設計判断: DEC-MTG-096
    /// 「チャットで続ける」: 会議ノートのウインドウを前に出し、その会議の AI チャットを開いてもらう
    func continueInChat() {
        guard let meetingID = request?.meetingID, !meetingID.isEmpty else { return }
        openChatRequest = OpenChatRequest(meetingID: meetingID)
        openMeetingWindow()
    }

    /// 会議ノートのウインドウが依頼を受け取ったとき
    func consumeOpenChatRequest(_ id: UUID) {
        if openChatRequest?.id == id { openChatRequest = nil }
    }

    // MARK: - 聞く

    // 設計判断: DEC-MTG-095, DEC-MTG-098
    /// 押した時点の記録で聞き、答えが出たら会議の AI チャットの会話に入れる。会話（それまでのやりとり）は渡さない
    func start(material: MeetingChat.Material, meetingID: String, origin: Origin, notice: String?, model: MeetingChatModel) {
        task?.cancel()
        let quick = MeetingChat.askedPrompt
        let prompt = MeetingChat.prompt(question: quick.question, material: material, history: [])
        let generation = model.generation
        let new = Request(meetingID: meetingID, origin: origin, at: material.elapsed,
                          recentOthers: MeetingChat.recentOthers(in: material), notice: notice, phase: .running,
                          generation: generation)
        request = new
        if origin == .panel { MeetingAskedQuestionPanel.shared.show() }
        let reply = self.reply
        task = Task { [weak self] in
            do {
                let text = try await reply(prompt)
                guard let self, !Task.isCancelled, self.request?.id == new.id else { return }
                self.request?.phase = .answered(text)
                self.task = nil
                model.insertAnsweredTurn(
                    question: MeetingChat.Message(role: .user, text: quick.question, label: quick.label),
                    answer: MeetingChat.Message(role: .assistant, text: text, coveredUntil: prompt.coveredUntil,
                                                lineCount: prompt.lineCount),
                    generation: generation)
            } catch {
                guard let self, !Task.isCancelled, self.request?.id == new.id else { return }
                self.request?.phase = .failed(tr("答えを作れませんでした: %@", "\(error.localizedDescription)"))
                self.task = nil
            }
        }
    }

    /// 設定の「AI」で会議に選んだ AI とモデルに聞く（チャットと同じ指示。会議中は速さを優先して effort は low）
    static func replyWithSettings(_ prompt: MeetingChat.Prompt) async throws -> String {
        let settings = AppSettings.shared
        let client = try TextAIClient.requireFromSettings(settings, for: .meeting, timeout: 120)
        let text = try await client.generate(systemInstruction: MeetingChat.instruction, userText: prompt.text,
                                             model: settings.textModel(for: .meeting), effort: .low)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 確認用の描き出し（CLI）で、状態を入れる
    func setRequestForPreview(_ request: Request?, recorder: MeetingRecorder? = nil) {
        task?.cancel()
        self.request = request
        recorderState = nil
        self.recorder = recorder
        recording = recorder?.state == .recording
    }
}
