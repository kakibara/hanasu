@preconcurrency import AVFoundation
import Foundation

// 記録中のスリープでの切り詰め（MeetingSleep.swift）の確認用の CLI モード:
//   Hanasu --test-meeting-sleep-cut
//     スリープした時点での切り詰め（発言・印・メモ・会議の長さ・音声ファイル）を確かめる。マイクも AI も使わない。失敗があれば終了コード 1
enum MeetingSleepCLI {
    // 確かめ方: REQ-MTG-043
    /// Hanasu --test-meeting-sleep-cut
    ///   スリープした時点での切り詰め（発言・印・メモ・会議の長さ・音声ファイル）を確かめる。マイクも AI も使わない。失敗があれば終了コード 1
    static func runSelfTestIfRequested(_ args: [String] = CommandLine.arguments) {
        guard args.contains("--test-meeting-sleep-cut") else { return }
        Task {
            exit(await selfTest() ? 0 : 1)
        }
        RunLoop.main.run()
    }

    private static func selfTest() async -> Bool {
        var failures: [String] = []
        func check(_ ok: Bool, _ message: String) {
            print(ok ? "ok: \(message)" : "NG: \(message)")
            if !ok { failures.append(message) }
        }

        // 自分の音声は 100 秒まで、相手の音声は 98 秒まで書いた時点でスリープした（経過時間は 101 秒）
        let point = MeetingSleepPoint(at: Date(), elapsed: 101, audioEnds: [.me: 100, .others: 98])
        func phrase(_ channel: MeetingChannel, _ start: Double, _ text: String) -> TranscribedPhrase {
            TranscribedPhrase(channel: channel, start: start, end: start + 1, text: text, words: [])
        }
        let kept = MeetingSleepCut.phrases([
            phrase(.me, 10, "前"), phrase(.me, 99.5, "スリープ直前"), phrase(.me, 100.2, "復帰後"),
            phrase(.others, 97, "相手の前"), phrase(.others, 99, "相手の復帰後"),
        ], before: point).map(\.text)
        check(kept == ["前", "スリープ直前", "相手の前"], "スリープより後に始まる発言を捨てる: \(kept)")
        check(MeetingSleepPoint(at: Date(), elapsed: 50, audioEnds: [:]).cutoff(for: .others) == 50,
              "音声のないチャンネルは経過時間で切る")

        var meeting = Meeting(id: "sleep-test", title: "t", startedAt: Date(), duration: 4000, status: .recording)
        meeting.notes = [
            MeetingNote(kind: .note, time: 30, text: "前のメモ"),
            MeetingNote(kind: .highlight, time: 90, text: "前の印"),
            MeetingNote(kind: .highlight, time: 120, text: "後の印"),
            MeetingNote(kind: .note, time: 130, text: "後のメモ"),
            MeetingNote(kind: .note, time: nil, text: "時刻なし"),
        ]
        MeetingSleepCut.apply(to: &meeting, point: point)
        check(meeting.duration == 101, "会議の長さはスリープした時点まで: \(meeting.duration)")
        let notes = (meeting.notes ?? []).map { "\($0.text)@\($0.time.map { String(Int($0)) } ?? "-")" }
        check(notes == ["前のメモ@30", "前の印@90", "後のメモ@101", "時刻なし@-"], "後の印は消し、後のメモは時刻をそろえる: \(notes)")

        // 音声ファイルの切り詰め（3 秒の音を 1.5 秒にする）
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hanasu-sleep-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("me.m4a")
            try writeTone(to: url, seconds: 3)
            try await MeetingSleepCut.trimAudio(at: url, toSeconds: 1.5)
            let trimmed = try await AVURLAsset(url: url).load(.duration).seconds
            check(abs(trimmed - 1.5) < 0.1, "音声ファイルを 1.5 秒に切り詰める: \(trimmed)")
            try await MeetingSleepCut.trimAudio(at: url, toSeconds: 10)
            let unchanged = try await AVURLAsset(url: url).load(.duration).seconds
            check(abs(unchanged - trimmed) < 0.01, "もともと短ければ切り詰めない: \(unchanged)")
        } catch {
            check(false, "音声ファイルの切り詰め: \(error)")
        }

        print(failures.isEmpty ? "all passed" : "\(failures.count) failed")
        return failures.isEmpty
    }

    private static func writeTone(to url: URL, seconds: Double) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let file = try AVAudioFile(
            forWriting: url,
            settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 32000],
            commonFormat: .pcmFormatFloat32, interleaved: false)
        let frames = AVAudioFrameCount(16_000 * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let data = buffer.floatChannelData![0]
        for i in 0..<Int(frames) { data[i] = sin(Float(i) * 0.06) * 0.3 }
        try file.write(from: buffer)
    }
}
