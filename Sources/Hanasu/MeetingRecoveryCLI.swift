@preconcurrency import AVFoundation
import Foundation

// 記録中に落ちた会議を録音から戻す機能の確認用の CLI モード:
//   Hanasu --test-meeting-audio-crash
//     自分自身を子のプロセスとして起動し、一時フォルダに本物の ChannelTranscriber（書き出しだけ）で実時間で 10 秒書いたところで
//     kill -9 する。SIGTERM でも同じことをする。残った m4a が AVAudioFile・AVURLAsset・TranscriptionAudio.loadSamples で読めて、
//     どれも 7 秒以上あることを確かめる。正常に閉じたファイルが全部読めて途中に移れること、書き出しが止まったときに
//     append と閉じるのが待たずに戻り、書けなかった印が立つことも確かめる。マイクも AI も使わない。失敗があれば終了コード 1
//   Hanasu --test-meeting-recovery
//     MeetingRecovery（作り直すボタンを出す条件・会議の長さ・終わっていないオフレコの閉じ方）を確かめる
//   Hanasu --meeting-recover-files <自分の音声> <相手の音声> [--me-offset 秒] [--others-offset 秒] [--engine apple|whisper|gemini]
//     保存先に落ちた会議（失敗・録音あり・発言 0 件・終わっていないオフレコ）を作り、録音から作り直して結果を出す
enum MeetingRecoveryCLI {
    static let childFlag = "--meeting-audio-crash-child"

    static func runIfRequested(_ args: [String] = CommandLine.arguments) {
        if let index = args.firstIndex(of: childFlag), index + 1 < args.count {
            let seconds = args.firstIndex(of: "--finish-after").flatMap { args.indices.contains($0 + 1) ? Double(args[$0 + 1]) : nil }
            Task { await runChild(directory: URL(fileURLWithPath: args[index + 1], isDirectory: true), finishAfter: seconds) }
            RunLoop.main.run()
        }
        // 確かめ方: REQ-MTG-128
        if args.contains("--test-meeting-audio-crash") {
            Task { exit(await crashTest() ? 0 : 1) }
            RunLoop.main.run()
        }
        // 確かめ方: REQ-MTG-128
        if args.contains("--test-meeting-recovery") {
            Task { exit(await recoveryTest() ? 0 : 1) }
            RunLoop.main.run()
        }
        // 確かめ方: REQ-MTG-128
        if let index = args.firstIndex(of: "--meeting-recover-files"), index + 2 < args.count {
            Task { @MainActor in
                do {
                    exit(try await recoverFiles(me: URL(fileURLWithPath: args[index + 1]),
                                                others: URL(fileURLWithPath: args[index + 2]), args: args) ? 0 : 1)
                } catch {
                    FileHandle.standardError.write(Data("error: \(error.localizedDescription) (\(error))\n".utf8))
                    exit(1)
                }
            }
            RunLoop.main.run()
        }
    }

    // MARK: - 作り直すボタンの条件・長さ・オフレコ

    private static func recoveryTest() async -> Bool {
        let c = Checker()
        var crashed = Meeting(id: "crashed", title: "t", startedAt: Date())
        crashed.status = .failed
        let audio: [MeetingChannel: Double] = [.me: 12, .others: 10]
        c.check(MeetingRecovery.canRecover(crashed, readableAudioSeconds: audio, busy: false), "落ちた会議（失敗・発言 0 件・録音あり）は作り直せる")
        var done = crashed
        done.status = .done
        c.check(MeetingRecovery.canRecover(done, readableAudioSeconds: audio, busy: false), "状態（完了）では決めない（発言 0 件・録音あり）")
        c.check(MeetingRecovery.canRecover(crashed, readableAudioSeconds: [.others: 3], busy: false), "片方だけ開ける録音でも作り直せる")
        c.check(!MeetingRecovery.canRecover(crashed, readableAudioSeconds: [:], busy: false), "開ける録音がなければ出さない")
        c.check(!MeetingRecovery.canRecover(crashed, readableAudioSeconds: [.me: 0], busy: false), "長さ 0 の録音だけなら出さない")
        c.check(!MeetingRecovery.canRecover(crashed, readableAudioSeconds: audio, busy: true), "記録・後処理・作り直しの間は出さない")
        var spoken = crashed
        spoken.utterances = [Utterance(speaker: "me", start: 0, end: 1, text: "a")]
        c.check(!MeetingRecovery.canRecover(spoken, readableAudioSeconds: audio, busy: false), "発言がある会議には出さない")
        for status in [Meeting.Status.recording, .processing] {
            var m = crashed
            m.status = status
            c.check(!MeetingRecovery.canRecover(m, readableAudioSeconds: audio, busy: false), "\(status.rawValue) の会議には出さない")
        }

        c.check(MeetingRecovery.duration(offsets: [.me: 0.5, .others: 3], audioSeconds: [.me: 12, .others: 10]) == 13,
                "長さは、先頭のずれ＋録音の長さの大きいほう")
        c.check(MeetingRecovery.duration(offsets: [.me: 2], audioSeconds: [:]) == 0, "録音がなければ長さ 0")
        let spans = MeetingRecovery.closeOpenOffRecord(
            [OffRecordSpan(start: 1, end: 2), OffRecordSpan(start: 5, end: nil), OffRecordSpan(start: 20, end: nil)], at: 13)
        c.check(spans?.map(\.end) == [2, 13, 20], "終わっていないオフレコを録音の終わりで閉じる（終わりより後に始まった区間は長さ 0）: \(String(describing: spans?.map(\.end)))")
        c.check(MeetingRecovery.closeOpenOffRecord(nil, at: 3) == nil, "オフレコがなければそのまま")

        var withOffsets = crashed
        withOffsets.errorMessage = "記録の途中でアプリが終了しました。"
        withOffsets.audioStartOffsets = ["others": 2.5]
        withOffsets.offRecord = [OffRecordSpan(start: 4, end: nil)]
        withOffsets.notes = [MeetingNote(kind: .highlight, time: 3, text: "")]
        let prepared = MeetingRecovery.prepared(withOffsets, audioSeconds: audio)
        c.check(prepared.errorMessage == nil && prepared.status == .processing && prepared.duration == 12.5
                && prepared.offRecord?.first?.end == 12.5 && prepared.notes?.count == 1,
                "作り直しの前に、エラーの文を消し・長さとオフレコを直し・処理中にする（メモは残す）")

        var bothFailed = crashed
        bothFailed.transcriptionFailedChannels = [.me, .others]
        c.check(MeetingRecovery.statusAfterRecovery(bothFailed) == .failed, "両方のチャンネルとも文字起こしできず発言 0 件なら「失敗」のまま")
        var oneFailed = crashed
        oneFailed.transcriptionFailedChannels = [.others]
        oneFailed.utterances = spoken.utterances
        c.check(MeetingRecovery.statusAfterRecovery(oneFailed) == .done, "片方だけ失敗なら「完了」")
        var silent = crashed
        silent.transcriptionFailedChannels = []
        c.check(MeetingRecovery.statusAfterRecovery(silent) == .done, "失敗はないが発言がない（無音）なら「完了」（ボタンはまた出る）")

        // 開ける録音を測る（Mac が読む m4a だけ。ほかの OS の WAV・長さ 0・壊れたファイルは数えない）
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("hanasu-recovery-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: dir) }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        if let writer = try? MeetingAudioWriter(url: dir.appendingPathComponent("me.m4a"), format: TranscriptionAudio.format) {
            for i in 0..<30 { writer.append(tone(format: TranscriptionAudio.format, index: i, seconds: 0.1)) }
            await writer.finish()
        }
        try? Data("RIFF....WAVE".utf8).write(to: dir.appendingPathComponent("others.wav"))
        var measured = MeetingRecovery.readableAudioSeconds(in: dir)
        c.check(measured.keys.sorted { $0.rawValue < $1.rawValue } == [.me] && abs((measured[.me] ?? 0) - 3) < 0.2,
                "m4a だけを測る（me 3 秒・others.wav は数えない）: \(measured)")
        try? Data("not audio".utf8).write(to: dir.appendingPathComponent("others.m4a"))
        measured = MeetingRecovery.readableAudioSeconds(in: dir)
        c.check(measured[.others] == nil, "開けない m4a は数えない")
        if let empty = try? MeetingAudioWriter(url: dir.appendingPathComponent("others.m4a"), format: TranscriptionAudio.format) {
            await empty.finish()
        }
        measured = MeetingRecovery.readableAudioSeconds(in: dir)
        c.check(measured[.others] == nil, "音を書かなかった m4a（記録を始める途中で失敗）は数えない")

        print(c.failures == 0 ? "すべて OK" : "NG が \(c.failures) 件")
        return c.failures == 0
    }

    // MARK: - 録音から作り直す流れ（保存先に会議を作る）

    /// 保存先に落ちた会議を作り、録音から作り直して結果を出す。状態が「完了」で発言があり、録音が残っていれば true
    @MainActor
    private static func recoverFiles(me: URL, others: URL, args: [String]) async throws -> Bool {
        func value(_ flag: String) -> Double? {
            args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? Double(args[$0 + 1]) : nil }
        }
        let settings = AppSettings.shared
        let (engine, _) = TranscriptionEngineCLI.parseEngine(args)
        if engine == .whisper { try await TranscriptionEngineCLI.ensureWhisperModel(settings.whisperModel) }
        var meeting = try MeetingStore.newMeeting()
        meeting.title = "テスト（録音から作り直す）"
        meeting.status = .recording
        // 録音を消す設定でも、作り直した会議の録音は残す（REQ-MTG-010）
        MeetingAudioPolicy.apply(to: &meeting, deleteAfterTranscription: true)
        meeting.audioStartOffsets = ["me": value("--me-offset") ?? 0, "others": value("--others-offset") ?? 0]
        meeting.notes = [MeetingNote(kind: .note, time: 1, text: "作り直しても残るメモ"), MeetingNote(kind: .highlight, time: 2, text: "")]
        meeting.offRecord = [OffRecordSpan(start: 0.5, end: 0.8), OffRecordSpan(start: 60 * 60, end: nil)]
        try MeetingStore.save(meeting)
        // 録音を、記録中と同じ書き手で書く（16 kHz モノラル）
        for (channel, url) in [(MeetingChannel.me, me), (.others, others)] {
            _ = try await ChannelTranscriber.transcribe(
                file: url, channel: channel, offset: 0, live: false,
                writingTo: MeetingStore.audioURL(for: meeting, channel: channel),
                localeIdentifier: settings.localeIdentifier, contextualStrings: [])
        }
        // 起動時に「失敗」にする（落ちた会議と同じ形）
        meeting.status = .failed
        meeting.errorMessage = tr("記録の途中でアプリが終了しました。")
        try MeetingStore.save(meeting)
        print("保存先: \(MeetingStore.directory(for: meeting).path)")

        let recorder = MeetingRecorder()
        print("作り直せる: \(recorder.canRecover(meeting))（録音 \(MeetingRecovery.readableAudioSeconds(of: meeting))）")
        print("確かめの文: \(MeetingRecoveryPrompt.confirmText(engine: engine))")
        // 権限の確かめ（prepareRecovery）は呼ばない。開発用のバイナリには権限の説明がなく、尋ねると TCC に止められる（--meeting-files と同じ）
        try MeetingRecorder.checkReady(engine)
        recorder.onStateChange = { state in if case .processing(let message) = state { print("… \(message)") } }
        let started = Date()
        await recorder.recoverFromAudio(meeting, engine: engine)
        guard let result = MeetingStore.loadAll().first(where: { $0.id == meeting.id }) else {
            print("NG: 会議を読めない")
            return false
        }
        print(String(format: "[作り直し %.1fs]", Date().timeIntervalSince(started)))
        print("状態: \(result.status.rawValue) / 発言 \(result.utterances.count) 件 / 話者 \(result.speakers) / 長さ \(String(format: "%.1f", result.duration)) 秒")
        print("オフレコ: \(result.offRecord?.map { "\($0.start)-\($0.end.map { String(format: "%.1f", $0) } ?? "nil")" } ?? [])")
        print("メモ: \(result.notes?.count ?? 0) 件 / エラーの文: \(result.errorMessage ?? "なし")")
        print("録音: \(MeetingStore.hasAudio(result) ? "残した" : "消した") / もう一度作り直せる: \(recorder.canRecover(result))")
        print(result.transcriptMarkdown())
        print(result.minutes ?? "(議事録なし)")
        let ok = result.status == .done && !result.utterances.isEmpty && MeetingStore.hasAudio(result)
            && result.offRecord?.allSatisfy { $0.end != nil } == true && result.notes?.count == 2 && result.duration > 0
        print(ok ? "OK" : "NG")
        return ok
    }

    // MARK: - 子のプロセス

    /// 相手側の音（48 kHz ステレオの Float）を 0.1 秒ずつ、実時間で書き続ける。1 秒ごとに「sec N」を出す。
    /// finishAfter を渡すと、その秒数を書いたところで閉じて終わる
    private static func runChild(directory: URL, finishAfter: Double?) async {
        setvbuf(stdout, nil, _IONBF, 0)
        guard let input = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2) else { exit(3) }
        let transcriber = ChannelTranscriber(
            channel: .others, inputFormat: input, fileURL: directory.appendingPathComponent("others.m4a"),
            meetingStart: Date(), live: false)
        do {
            try await transcriber.prepare(localeIdentifier: "ja-JP", contextualStrings: [])
        } catch {
            print("prepare failed: \(error)")
            exit(4)
        }
        let start = Date()
        var index = 0
        while true {
            transcriber.append(tone(format: input, index: index, seconds: 0.1))
            index += 1
            if index % 10 == 0 { print("sec \(index / 10)") }
            if let finishAfter, Double(index) / 10 >= finishAfter {
                _ = await transcriber.finish()
                print("finished")
                exit(0)
            }
            // 実時間に合わせる（遅れたら待たない）
            let next = start.addingTimeInterval(Double(index) * 0.1)
            let wait = next.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
        }
    }

    /// 440 Hz の音（index 番目の 0.1 秒）
    static func tone(format: AVAudioFormat, index: Int, seconds: Double) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(format.sampleRate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let base = Double(index) * Double(frames)
        for channel in 0..<Int(format.channelCount) {
            if let data = buffer.floatChannelData?[channel] {
                for n in 0..<Int(frames) { data[n] = Float(0.3 * sin((base + Double(n)) * 2 * .pi * 440 / format.sampleRate)) }
            } else if let data = buffer.int16ChannelData?[channel] {
                for n in 0..<Int(frames) { data[n] = Int16(9000 * sin((base + Double(n)) * 2 * .pi * 440 / format.sampleRate)) }
            }
        }
        return buffer
    }

    // MARK: - 落ちたときの録音

    private final class Checker {
        var failures = 0
        func check(_ ok: Bool, _ label: String) {
            print((ok ? "OK  " : "NG  ") + label)
            if !ok { failures += 1 }
        }
    }

    /// 子のプロセスを起動し、afterSeconds 秒書いたら signal で止める（signal が nil なら自分で閉じて終わるのを待つ）
    private static func runChildProcess(directory: URL, afterSeconds: Int, signal: Int32?) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0])
        var arguments = [childFlag, directory.path]
        if signal == nil { arguments += ["--finish-after", "\(afterSeconds)"] }
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let target = "sec \(afterSeconds)"
        let handle = pipe.fileHandleForReading
        var text = ""
        let deadline = Date().addingTimeInterval(Double(afterSeconds) + 20)
        while process.isRunning, Date() < deadline {
            let data = handle.availableData
            if data.isEmpty { break }
            text += String(decoding: data, as: UTF8.self)
            if signal != nil, text.contains(target) { break }
        }
        if let signal, process.isRunning {
            kill(process.processIdentifier, signal)
        }
        process.waitUntilExit()
    }

    /// 3 つの読み方で長さ（秒）を読む。読めなければ nil
    private static func readableSeconds(_ url: URL) async -> (file: Double?, asset: Double?, samples: Double?) {
        let file = (try? AVAudioFile(forReading: url)).map { Double($0.length) / $0.processingFormat.sampleRate }
        let asset = try? await AVURLAsset(url: url).load(.duration).seconds
        let samples = (try? TranscriptionAudio.loadSamples(from: url)).map { Double($0.count) / TranscriptionAudio.sampleRate }
        return (file, asset, samples)
    }

    private static func crashTest() async -> Bool {
        let c = Checker()
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("hanasu-audio-crash-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }

        for (name, signal) in [("kill -9", SIGKILL), ("SIGTERM", SIGTERM)] {
            let dir = root.appendingPathComponent(name.replacingOccurrences(of: " ", with: ""), isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            do {
                try await runChildProcess(directory: dir, afterSeconds: 10, signal: signal)
            } catch {
                c.check(false, "\(name): 子のプロセスを起動できる（\(error)）")
                continue
            }
            let url = dir.appendingPathComponent("others.m4a")
            let read = await readableSeconds(url)
            func show(_ v: Double?) -> String { v.map { String(format: "%.1f", $0) } ?? "読めない" }
            c.check((read.file ?? 0) >= 7, "\(name): 10 秒書いて止めた録音を AVAudioFile で読める（\(show(read.file)) 秒）")
            c.check((read.asset ?? 0) >= 7, "\(name): AVURLAsset で長さを読める（\(show(read.asset)) 秒）")
            c.check((read.samples ?? 0) >= 7, "\(name): TranscriptionAudio.loadSamples で読める（\(show(read.samples)) 秒）")
        }

        // 正常に閉じたファイル
        let finishedDir = root.appendingPathComponent("finished", isDirectory: true)
        try? fm.createDirectory(at: finishedDir, withIntermediateDirectories: true)
        do {
            try await runChildProcess(directory: finishedDir, afterSeconds: 4, signal: nil)
        } catch {
            c.check(false, "閉じる: 子のプロセスを起動できる（\(error)）")
        }
        let finishedURL = finishedDir.appendingPathComponent("others.m4a")
        let finished = await readableSeconds(finishedURL)
        func near(_ v: Double?, _ expected: Double) -> Bool { v.map { abs($0 - expected) < 0.3 } ?? false }
        c.check(near(finished.file, 4) && near(finished.asset, 4) && near(finished.samples, 4),
                "閉じた録音は 3 つの読み方で全部（4 秒）読める（\(String(describing: finished))）")
        if let file = try? AVAudioFile(forReading: finishedURL),
           let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1600) {
            file.framePosition = AVAudioFramePosition(file.processingFormat.sampleRate * 2.5)
            let ok = (try? file.read(into: buffer)) != nil && buffer.frameLength > 0
            c.check(ok, "閉じた録音の途中（2.5 秒）に移って読める")
        } else {
            c.check(false, "閉じた録音の途中に移って読める（開けない）")
        }

        // 書き出しが止まったとき
        await writerFailureTests(c, root: root)

        print(c.failures == 0 ? "すべて OK" : "NG が \(c.failures) 件")
        return c.failures == 0
    }

    private static func writerFailureTests(_ c: Checker, root: URL) async {
        let format = TranscriptionAudio.format
        // 書き手が止まった（取り消された）あと
        do {
            let writer = try MeetingAudioWriter(url: root.appendingPathComponent("cancelled.m4a"), format: format)
            writer.append(tone(format: format, index: 0, seconds: 1))
            writer.cancelForTesting()
            let start = Date()
            for i in 1...20 { writer.append(tone(format: format, index: i, seconds: 1)) }
            await writer.finish()
            let elapsed = Date().timeIntervalSince(start)
            try? await Task.sleep(nanoseconds: 100_000_000)
            c.check(writer.failure != nil, "書き手が止まると、書けなかった印が立つ（\(writer.failure ?? "nil")）")
            c.check(elapsed < 5, "書き手が止まっても、append と閉じるのは待たずに戻る（\(String(format: "%.2f", elapsed)) 秒）")
        } catch {
            c.check(false, "書き手を作れる（\(error)）")
        }
        // ファイルから実時間より速く流すとき（--meeting-files・--meeting-recover-files）は、捨てずに全部書く
        do {
            let url = root.appendingPathComponent("fast.m4a")
            let writer = try MeetingAudioWriter(url: url, format: format, realtime: false)
            for i in 0..<120 { writer.append(tone(format: format, index: i, seconds: 1)) }
            await writer.finish()
            let read = await readableSeconds(url)
            c.check(writer.failure == nil && abs((read.file ?? 0) - 120) < 0.5,
                    "ファイルから速く流しても、120 秒ぶん全部書ける（\(read.file.map { String(format: "%.1f", $0) } ?? "読めない") 秒）")
        } catch {
            c.check(false, "書き手を作れる（\(error)）")
        }
        // 書き出しのキューが詰まったまま、30 秒ぶんを超えて渡したとき
        do {
            let writer = try MeetingAudioWriter(url: root.appendingPathComponent("stalled.m4a"), format: format)
            writer.stallForTesting(seconds: 3)
            let start = Date()
            for i in 0..<40 { writer.append(tone(format: format, index: i, seconds: 1)) }
            let appendElapsed = Date().timeIntervalSince(start)
            c.check(appendElapsed < 1, "書き出しが詰まっても append は待たない（40 秒ぶんで \(String(format: "%.2f", appendElapsed)) 秒）")
            c.check(writer.failure != nil, "まだ書いていない音が 30 秒ぶんを超えたら、書けなかった印が立つ")
            let finishStart = Date()
            await writer.finish()
            let finishElapsed = Date().timeIntervalSince(finishStart)
            c.check(finishElapsed < MeetingAudioWriter.finishWaitSeconds + 3.5,
                    "詰まったあとも、閉じるのは上限の内に戻る（\(String(format: "%.2f", finishElapsed)) 秒）")
        } catch {
            c.check(false, "書き手を作れる（\(error)）")
        }
    }
}
