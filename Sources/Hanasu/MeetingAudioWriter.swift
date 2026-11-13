@preconcurrency import AVFoundation
import CoreMedia
import Foundation

// 要件: REQ-MTG-128, REQ-MTG-002
// 設計判断: DEC-MTG-156
/// 会議の 1 チャンネルの録音（me.m4a / others.m4a）を、2 秒ごとに断片を閉じる m4a に書く。
/// アプリが落ちても、最後に閉じた断片までは開ける形で残る（AVAudioFile の m4a は、閉じないと開けない）。
/// append は 1 つのスレッド（ChannelTranscriber のキュー）から順に呼ぶ。書くのは専用のキューで、呼んだ側は待たない。
final class MeetingAudioWriter: @unchecked Sendable {
    /// 断片を閉じる間隔（秒）。落ちたときに失うのは、おおよそこの長さまで
    static let fragmentSeconds = 2.0
    /// 書き手の準備を 1 回あたり待つ上限（秒）
    static let readyWaitSeconds = 1.0
    /// まだ書いていない音をためてよい上限（秒ぶん）。超えたら書くのをやめる
    static let maxBacklogSeconds = 30.0
    /// 閉じる（finishWriting）のを待つ上限（秒）
    static let finishWaitSeconds = 5.0

    let url: URL
    private let queue: DispatchQueue
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    /// 書き手に渡す形式（入力と同じ周波数・チャンネル数の、16 bit 整数・インターリーブ）
    private let pcmFormat: AVAudioFormat
    private let formatDescription: CMAudioFormatDescription
    /// append を呼ぶスレッドだけで触る
    private var converter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?

    /// 書き出しのキューだけで触る
    private var framesWritten: Int64 = 0
    private var finished = false

    private let lock = NSLock()
    private var _failure: String?
    private var _backlogFrames: Int64 = 0

    /// - Parameter format: 書く音の標本化周波数とチャンネル数（ChannelTranscriber が書き出しに使う形式）
    init(url: URL, format: AVAudioFormat, fragmentSeconds: Double = MeetingAudioWriter.fragmentSeconds) throws {
        self.url = url
        try? FileManager.default.removeItem(at: url)
        guard let pcmFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: format.sampleRate,
                                            channels: format.channelCount, interleaved: true)
        else { throw MeetingAudioWriterError.unsupportedFormat }
        self.pcmFormat = pcmFormat
        var description: CMAudioFormatDescription?
        let status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault, asbd: pcmFormat.streamDescription, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &description)
        guard status == noErr, let description else { throw MeetingAudioWriterError.unsupportedFormat }
        formatDescription = description

        writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        writer.movieFragmentInterval = CMTime(seconds: fragmentSeconds, preferredTimescale: 600)
        input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderBitRateKey: 32000,
        ])
        // 準備が間に合わないときに捨てると音が欠けるので、実時間の扱いにせず、準備を待ってから書く
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { throw MeetingAudioWriterError.unsupportedFormat }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? MeetingAudioWriterError.unsupportedFormat
        }
        // 時刻は 0 から（先頭のずれは audioStartOffsets に持つ）
        writer.startSession(atSourceTime: .zero)
        queue = DispatchQueue(label: "Hanasu.MeetingAudioWriter.\(url.lastPathComponent)")
    }

    /// 書けなくなった理由。書けていれば nil
    var failure: String? { lock.withLock { _failure } }

    /// 音を写して、書き出しのキューに渡す（待たない）。書けなくなったあとは何もしない
    func append(_ buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0, failure == nil, let copy = convert(buffer) else { return }
        let frames = Int64(copy.frameLength)
        let backlogLimit = Int64(Self.maxBacklogSeconds * pcmFormat.sampleRate)
        let overflow: Bool = lock.withLock {
            guard _failure == nil else { return false }
            if _backlogFrames + frames > backlogLimit {
                return true
            }
            _backlogFrames += frames
            return false
        }
        if overflow {
            fail("backlog over \(Self.maxBacklogSeconds)s")
            return
        }
        queue.async { [self] in
            defer { lock.withLock { _backlogFrames -= frames } }
            write(copy)
        }
    }

    /// これまでに渡した音を書き終えてからファイルを閉じる。待つのは最大 finishWaitSeconds 秒。2 回目からは何もしない
    func finish() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let once = ResumeOnce(continuation)
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.finishWaitSeconds) { [url] in
                if once.resume() {
                    appLog.error("meeting audio finish timed out: \(url.lastPathComponent, privacy: .public)")
                }
            }
            queue.async { [self] in
                guard !finished else {
                    once.resume()
                    return
                }
                finished = true
                guard writer.status == .writing else {
                    once.resume()
                    return
                }
                input.markAsFinished()
                writer.finishWriting { [self] in
                    if writer.status != .completed {
                        appLog.error("meeting audio finish failed: \(String(describing: self.writer.error), privacy: .public)")
                    }
                    once.resume()
                }
            }
        }
    }

    // MARK: - 確かめ方の CLI から（--test-meeting-audio-crash）

    /// 書き手を取り消す（書き手が止まったときの振る舞いを確かめる）
    func cancelForTesting() {
        queue.async { [self] in writer.cancelWriting() }
    }

    /// 書き出しのキューを seconds 秒止める（書き出しが詰まったときの振る舞いを確かめる）
    func stallForTesting(seconds: Double) {
        queue.async { Thread.sleep(forTimeInterval: seconds) }
    }

    // MARK: - Private

    /// 書き出しのキューの上で呼ぶ
    private func write(_ buffer: AVAudioPCMBuffer) {
        guard !finished, failure == nil else { return }
        // 書き手の準備ができるまで待つ（書き手が動いている間だけ、上限つき）
        let deadline = Date().addingTimeInterval(Self.readyWaitSeconds)
        while writer.status == .writing, !input.isReadyForMoreMediaData, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.002)
        }
        guard writer.status == .writing else {
            fail(writer.error?.localizedDescription ?? "status \(writer.status.rawValue)")
            return
        }
        guard input.isReadyForMoreMediaData else {
            fail("writer not ready within \(Self.readyWaitSeconds)s")
            return
        }
        guard let sample = makeSampleBuffer(buffer, at: framesWritten) else {
            fail("could not make a sample buffer")
            return
        }
        guard input.append(sample) else {
            fail(writer.error?.localizedDescription ?? "append")
            return
        }
        framesWritten += Int64(buffer.frameLength)
    }

    private func fail(_ reason: String) {
        let first: Bool = lock.withLock {
            guard _failure == nil else { return false }
            _failure = reason
            return true
        }
        if first {
            appLog.error("meeting audio write failed (\(self.url.lastPathComponent, privacy: .public)): \(reason, privacy: .public)")
        }
    }

    /// 書き手に渡す形式に変える（いつも新しいバッファを返すので、呼んだ側のバッファは使い回してよい）
    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if converterInputFormat != buffer.format {
            converterInputFormat = buffer.format
            converter = AVAudioConverter(from: buffer.format, to: pcmFormat)
        }
        guard let converter,
              let output = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: buffer.frameLength)
        else { return nil }
        do {
            try converter.convert(to: output, from: buffer)
        } catch {
            return nil
        }
        return output.frameLength > 0 ? output : nil
    }

    private func makeSampleBuffer(_ buffer: AVAudioPCMBuffer, at frame: Int64) -> CMSampleBuffer? {
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(pcmFormat.sampleRate)),
            presentationTimeStamp: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(pcmFormat.sampleRate)),
            decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreate(
            allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil, refcon: nil,
            formatDescription: formatDescription, sampleCount: CMItemCount(buffer.frameLength),
            sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil,
            sampleBufferOut: &sample) == noErr,
            let sample,
            CMSampleBufferSetDataBufferFromAudioBufferList(
                sample, blockBufferAllocator: kCFAllocatorDefault, blockBufferMemoryAllocator: kCFAllocatorDefault,
                flags: 0, bufferList: buffer.audioBufferList) == noErr
        else { return nil }
        return sample
    }
}

enum MeetingAudioWriterError: LocalizedError {
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "Unsupported audio format for the meeting recording"
        }
    }
}

/// 待ちの上限と書き終わりの、先に来たほうでだけ続きを動かす
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?

    init(_ continuation: CheckedContinuation<Void, Never>) { self.continuation = continuation }

    /// 初めて呼ばれたときだけ続きを動かして true を返す
    @discardableResult
    func resume() -> Bool {
        let pending: CheckedContinuation<Void, Never>? = lock.withLock {
            defer { continuation = nil }
            return continuation
        }
        pending?.resume()
        return pending != nil
    }
}
