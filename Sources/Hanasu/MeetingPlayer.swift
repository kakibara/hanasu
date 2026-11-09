@preconcurrency import AVFoundation
import AppKit
import SwiftUI

// 要件: REQ-MTG-053
// 設計判断: DEC-MTG-135
/// 会議ノートの音声の再生。me.m4a と others.m4a を 1 つの時間軸に重ね、録音開始からのずれだけずらして鳴らす。
/// 会議ノートのウインドウは 1 つなので、アプリに 1 つだけ置く（記録・音声入力が始まったら止める）
@MainActor
final class MeetingPlayer: ObservableObject {
    static let shared = MeetingPlayer()

    enum Availability: Equatable {
        /// 音声ファイルがない（読み込む前も）
        case none
        case loading
        case ready
        /// ファイルはあるが読めない（途中で落ちた会議など）
        case unreadable
    }

    @Published private(set) var meetingID: String?
    @Published private(set) var availability: Availability = .none
    /// 音声ファイルのあるチャンネル
    @Published private(set) var channels: Set<MeetingChannel> = []
    @Published private(set) var isPlaying = false
    /// 再生位置（録音開始からの秒）
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var rate: Float = 1 {
        didSet {
            player?.defaultRate = rate
            if isPlaying { player?.rate = rate }
        }
    }
    /// 消音しているチャンネル（イヤホンなしの会議で、相手の声がマイクにも入って二重に聞こえるとき）
    @Published var muted: Set<MeetingChannel> = [] {
        didSet { applyMix() }
    }
    /// 音声入力をしている（DictationController が入れる）。している間は再生しない
    @Published var dictationActive = false {
        didSet { if dictationActive { pause() } }
    }

    static let rates: [Float] = [1, 1.25, 1.5, 2]
    /// 再生位置を見る間隔（発言の強調が 0.5 秒以内に移るように）
    static let tick = 0.25

    private var player: AVPlayer?
    private var trackIDs: [MeetingChannel: CMPersistentTrackID] = [:]
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var loadToken = UUID()
    /// 音声の終わり（録音開始からの秒）。会議の長さは後片付けの分だけ音声より長いことがあるので、頭へ戻す判断はこちらで見る
    private var audioEnd: Double = 0
    private var systemObservers: [NSObjectProtocol] = []

    private init() {
        // スリープ・アプリの終了で止める
        let center = NSWorkspace.shared.notificationCenter
        systemObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { MeetingPlayer.shared.pause() }
        })
        systemObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { MeetingPlayer.shared.stop() }
        })
    }

    // MARK: - 読み込み

    /// 会議の音声を読み込む（同じ会議なら何もしない）
    func load(_ meeting: Meeting) {
        guard meetingID != meeting.id else { return }
        stop()
        meetingID = meeting.id
        let urls = Self.audioURLs(for: meeting)
        channels = Set(urls.keys)
        guard !urls.isEmpty else {
            availability = .none
            return
        }
        availability = .loading
        duration = meeting.duration
        let token = UUID()
        loadToken = token
        let offsets = Self.offsets(for: meeting)
        Task {
            do {
                let built = try await Self.makeComposition(urls: urls, offsets: offsets)
                guard self.loadToken == token else { return }
                let item = AVPlayerItem(asset: built.composition)
                item.audioTimePitchAlgorithm = .timeDomain
                let player = AVPlayer(playerItem: item)
                player.defaultRate = self.rate
                self.player = player
                self.trackIDs = built.trackIDs
                self.duration = max(meeting.duration, built.duration)
                self.audioEnd = built.duration
                self.applyMix()
                self.observe(player, item: item)
                self.availability = .ready
            } catch {
                guard self.loadToken == token else { return }
                appLog.error("meeting audio load failed: \(error.localizedDescription, privacy: .public)")
                self.availability = .unreadable
            }
        }
    }

    /// 再生をやめ、読み込んだ音声を手放す
    func stop() {
        loadToken = UUID()
        player?.pause()
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
        player = nil
        audioEnd = 0
        trackIDs = [:]
        meetingID = nil
        availability = .none
        channels = []
        isPlaying = false
        currentTime = 0
        muted = []
    }

    // MARK: - 操作

    func play() {
        guard availability == .ready, !dictationActive, let player else { return }
        // 最後まで再生したあと（音声の終わり以降にいるとき）は、頭から鳴らす
        if currentTime >= min(duration, audioEnd) - 0.1 { seek(to: 0) }
        player.playImmediately(atRate: rate)
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func seek(to seconds: Double) {
        let target = min(max(0, seconds), duration)
        currentTime = target
        player?.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func skip(by seconds: Double) {
        seek(to: currentTime + seconds)
    }

    /// その時刻から再生する（文字起こしの発言の時刻を押したとき）
    func play(from seconds: Double) {
        seek(to: seconds)
        play()
    }

    // 要件: REQ-MTG-053
    /// 会議ノートのウインドウの識別子（スペースキーで再生・一時停止するウインドウ）
    static let windowIdentifier = NSUserInterfaceItemIdentifier("HanasuMeetingWindow")
    private var keyMonitor: Any?

    // 要件: REQ-MTG-053
    /// スペースキーで再生・一時停止する（会議ノートが前面で、文字の入力欄にフォーカスがないときだけ）。
    /// ボタンのショートカットにすると、入力欄のスペースまで取ってしまうので、キーを見て決める
    func installSpaceKey() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // NSEvent は Sendable でないので、MainActor の中へは要る値だけを渡す
            guard event.keyCode == 49, event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
            else { return event }
            let handled = MainActor.assumeIsolated { () -> Bool in
                let player = MeetingPlayer.shared
                // 文字の入力欄と、キーボードでフォーカスしたボタン・切り替えでは、スペースをその部品に渡す
                guard let window = NSApp.keyWindow, window.identifier == Self.windowIdentifier,
                      !(window.firstResponder is NSText), !(window.firstResponder is NSButton),
                      !(window.firstResponder is NSSegmentedControl), window.attachedSheet == nil,
                      player.availability == .ready, !player.dictationActive else { return false }
                player.toggle()
                return true
            }
            return handled ? nil : event
        }
    }

    // MARK: - 中身

    private func observe(_ player: AVPlayer, item: AVPlayerItem) {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: Self.tick, preferredTimescale: 600), queue: .main) { time in
            MainActor.assumeIsolated {
                let shared = MeetingPlayer.shared
                guard shared.player === player else { return }
                shared.currentTime = time.seconds.isFinite ? time.seconds : 0
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { _ in
            MainActor.assumeIsolated { MeetingPlayer.shared.isPlaying = false }
        }
    }

    private func applyMix() {
        guard let item = player?.currentItem, !trackIDs.isEmpty else { return }
        let mix = AVMutableAudioMix()
        mix.inputParameters = trackIDs.map { channel, id in
            let parameters = AVMutableAudioMixInputParameters()
            parameters.trackID = id
            parameters.setVolume(muted.contains(channel) ? 0 : 1, at: .zero)
            return parameters
        }
        item.audioMix = mix
    }

    /// 確認用の描き出しで、音声を読まずに再生のバーを出す（CLI の --render-meeting-window）
    func showForRendering(meetingID: String, channels: Set<MeetingChannel>, time: Double, duration: Double,
                          availability: Availability = .ready) {
        stop()
        self.meetingID = meetingID
        self.channels = channels
        self.availability = availability
        self.duration = duration
        currentTime = time
    }

    // MARK: - 決まり（確かめ方の CLI からも使う）

    /// 会議フォルダの音声ファイル（あるものだけ）
    static func audioURLs(for meeting: Meeting) -> [MeetingChannel: URL] {
        var urls: [MeetingChannel: URL] = [:]
        for channel in [MeetingChannel.me, .others] {
            let url = MeetingStore.audioURL(for: meeting, channel: channel)
            if FileManager.default.fileExists(atPath: url.path) { urls[channel] = url }
        }
        return urls
    }

    /// チャンネルごとの、音声ファイルの先頭が録音開始から何秒後か（記録していない古い会議は 0）
    static func offsets(for meeting: Meeting) -> [MeetingChannel: Double] {
        var offsets: [MeetingChannel: Double] = [:]
        for channel in [MeetingChannel.me, .others] {
            offsets[channel] = max(0, meeting.audioStartOffsets?[channel.rawValue] ?? 0)
        }
        return offsets
    }

    struct Built {
        var composition: AVMutableComposition
        var trackIDs: [MeetingChannel: CMPersistentTrackID]
        /// 録音開始からの長さ（秒）
        var duration: Double
    }

    enum LoadError: LocalizedError {
        case noAudioTrack(MeetingChannel)

        var errorDescription: String? {
            switch self {
            case .noAudioTrack(let channel): tr("%@の音声を読めません", channel == .me ? tr("自分") : tr("相手"))
            }
        }
    }

    // 設計判断: DEC-MTG-135
    /// 2 つの音声を 1 つの時間軸に重ねる。読めないファイルがあれば投げる
    static func makeComposition(urls: [MeetingChannel: URL], offsets: [MeetingChannel: Double]) async throws -> Built {
        let composition = AVMutableComposition()
        var ids: [MeetingChannel: CMPersistentTrackID] = [:]
        var end = 0.0
        for channel in [MeetingChannel.me, .others] {
            guard let url = urls[channel] else { continue }
            let asset = AVURLAsset(url: url)
            guard let source = try await asset.loadTracks(withMediaType: .audio).first else { throw LoadError.noAudioTrack(channel) }
            let length = try await asset.load(.duration)
            guard length.seconds.isFinite, length.seconds > 0,
                  let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { throw LoadError.noAudioTrack(channel) }
            let offset = CMTime(seconds: offsets[channel] ?? 0, preferredTimescale: 600)
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: source, at: offset)
            ids[channel] = track.trackID
            end = max(end, offset.seconds + length.seconds)
        }
        return Built(composition: composition, trackIDs: ids, duration: end)
    }

    // 要件: REQ-MTG-053
    /// 再生位置の発言（その時刻までに始まった最後の発言。どれも始まっていなければ nil）。starts は時刻の順
    static func blockIndex(at seconds: Double, starts: [Double]) -> Int? {
        starts.lastIndex { $0 <= seconds }
    }

    // 要件: REQ-MTG-053
    /// 再生できない理由（記録中・音声入力中）。再生できるなら nil
    static func blockReason(recording: Bool, dictating: Bool) -> String? {
        if recording { return tr("会議を記録している間は再生できません（再生した音がマイクに入るため）") }
        if dictating { return tr("音声入力をしている間は再生できません") }
        return nil
    }
}
