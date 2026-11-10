import AppKit
import Foundation

// 会議の録音を消す機能の確認用の CLI モード:
//   Hanasu --test-meeting-audio
//     会議ごとの値（写し・JSON の往復）、後処理のあとに消すかの決め方、文字起こしの状態、録音のファイルだけを消すこと
//     （4 つのファイル名・もうないファイル・消せないファイル）、録音の管理と保存期間の対象の選び方（30 日の境目・記録中と
//     文字起こしがそろっていない会議を除く）、「音声ファイルは残しています」を出すか。一時フォルダだけを使い、
//     ~/Documents の会議も設定も触らない。失敗があれば終了コード 1
//   Hanasu --render-meeting-audio-manager <出力フォルダ>
//     録音の管理の画面を、架空の会議で PNG にする（MeetingAudioManager.swift）
// 確かめ方: REQ-MTG-010, REQ-MTG-055, REQ-MTG-056, REQ-MTG-057
@MainActor
enum MeetingAudioCLI {
    static func runIfRequested(_ args: [String] = CommandLine.arguments) {
        if args.contains("--test-meeting-audio") { exit(test() ? 0 : 1) }
        if let index = args.firstIndex(of: "--render-meeting-audio-manager"), index + 1 < args.count {
            do {
                try MeetingAudioManagerRender.render(to: URL(fileURLWithPath: args[index + 1], isDirectory: true))
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
                exit(1)
            }
        }
    }

    private final class Checker {
        var failures = 0
        func check(_ ok: Bool, _ label: String) {
            print((ok ? "OK  " : "NG  ") + label)
            if !ok { failures += 1 }
        }
    }

    static let now = Date(timeIntervalSince1970: 1_793_005_200)

    /// 架空の会議。utterances が 0 なら文字起こしなし
    static func meeting(_ id: String, daysAgo: Double, utterances: Int = 2, status: Meeting.Status = .done,
                        failed: [MeetingChannel]? = nil) -> Meeting {
        var m = Meeting(id: id, title: "会議 \(id)", startedAt: now.addingTimeInterval(-daysAgo * 24 * 3600))
        m.status = status
        // 式を分けて型を書く（Swift 6.3 では 1 つの式のままだと型の推論が時間切れになる）
        var list: [Utterance] = []
        for i in 0..<utterances {
            let speaker: String = i.isMultiple(of: 2) ? "me" : "spk1"
            let start: Double = Double(i) * 5
            list.append(Utterance(speaker: speaker, start: start, end: start + 4, text: "発言 \(i)"))
        }
        m.utterances = list
        m.transcriptionFailedChannels = failed
        return m
    }

    static func test() -> Bool {
        let c = Checker()
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("hanasu-meeting-audio-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        func dir(_ m: Meeting) -> URL { root.appendingPathComponent(m.id, isDirectory: true) }
        func put(_ m: Meeting, _ files: [String: Int]) {
            try? fm.createDirectory(at: dir(m), withIntermediateDirectories: true)
            for (name, size) in files {
                fm.createFile(atPath: dir(m).appendingPathComponent(name).path, contents: Data(count: size))
            }
        }

        // 会議ごとの値（REQ-MTG-010・DEC-MTG-139）
        var a = meeting("a", daysAgo: 1)
        MeetingAudioPolicy.apply(to: &a, deleteAfterTranscription: true)
        c.check(a.deleteAudioAfterTranscription == true, "設定が「削除」なら、会議の値が true になる")
        MeetingAudioPolicy.apply(to: &a, deleteAfterTranscription: false)
        c.check(a.deleteAudioAfterTranscription == nil, "設定が「残す」なら、会議の値は書かない（nil）")
        MeetingAudioPolicy.apply(to: &a, deleteAfterTranscription: true)
        a.transcriptionFailedChannels = [.others]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? encoder.encode(a), let json = String(data: data, encoding: .utf8),
           let back = try? decoder.decode(Meeting.self, from: data) {
            c.check(json.contains("\"deleteAudioAfterTranscription\":true"), "meeting.json に deleteAudioAfterTranscription を書く")
            c.check(json.contains("\"transcriptionFailedChannels\":[\"others\"]"), "meeting.json に transcriptionFailedChannels を書く（Windows と同じ形）")
            c.check(back.deleteAudioAfterTranscription == true && back.transcriptionFailedChannels == [.others], "読み戻すと同じ値になる")
        } else {
            c.check(false, "meeting.json の書き出しと読み戻し")
        }
        let old = #"{"id":"old","title":"古い会議","startedAt":"2026-11-01T00:00:00Z","duration":0,"status":"done","speakerNames":{},"utterances":[]}"#
        let oldMeeting = try? decoder.decode(Meeting.self, from: Data(old.utf8))
        c.check(oldMeeting != nil && oldMeeting?.deleteAudioAfterTranscription == nil, "この機能より前の meeting.json も読める（値は nil＝残す）")

        // 後処理のあとに消すか（REQ-MTG-010・DEC-MTG-142）
        var on = meeting("on", daysAgo: 0)
        on.deleteAudioAfterTranscription = true
        c.check(MeetingAudioPolicy.shouldDeleteAfterProcessing(on), "会議の値がオンで文字起こしがそろっていれば消す")
        var off = on
        off.deleteAudioAfterTranscription = nil
        c.check(!MeetingAudioPolicy.shouldDeleteAfterProcessing(off), "会議の値がオフなら消さない（設定は見ない）")
        var empty = meeting("empty", daysAgo: 0, utterances: 0)
        empty.deleteAudioAfterTranscription = true
        c.check(!MeetingAudioPolicy.shouldDeleteAfterProcessing(empty), "発言が 0 件なら、オンでも消さない")
        var partial = on
        partial.transcriptionFailedChannels = [.me]
        c.check(!MeetingAudioPolicy.shouldDeleteAfterProcessing(partial), "文字起こしに失敗したチャンネルがあれば、オンでも消さない")
        var failedStatus = on
        failedStatus.status = .failed
        c.check(!MeetingAudioPolicy.shouldDeleteAfterProcessing(failedStatus), "状態が「失敗」なら、オンでも消さない")

        // 文字起こしの状態
        c.check(MeetingAudioCleanup.transcriptState(of: on) == .complete, "状態: すべて")
        c.check(MeetingAudioCleanup.transcriptState(of: partial) == .partial(failedChannels: [.me]), "状態: 一部（自分が欠けた）")
        c.check(MeetingAudioCleanup.transcriptState(of: failedStatus) == .partial(failedChannels: []), "状態: 失敗で発言がある会議は一部")
        c.check(MeetingAudioCleanup.transcriptState(of: empty) == .none, "状態: 発言 0 件はなし")

        // 録音のファイルだけを消す（REQ-MTG-055・DEC-MTG-140）
        let files = meeting("files", daysAgo: 3)
        put(files, ["me.m4a": 1000, "others.m4a": 2000, "me.wav": 300, "others.wav": 400,
                    "meeting.json": 10, "transcript.md": 10, "minutes.md": 10, "notes.md": 10])
        c.check(MeetingAudioCleanup.audioFiles(in: dir(files)).count == 4, "4 つのファイル名（m4a・wav）を録音として数える")
        c.check(MeetingAudioCleanup.audioSize(in: dir(files)) == 3700, "大きさは 4 つの合計")
        let failures = MeetingAudioCleanup.deleteAudio(in: dir(files))
        c.check(failures.isEmpty, "消せなかったファイルはない")
        c.check(MeetingAudioCleanup.audioFiles(in: dir(files)).isEmpty, "録音のファイルがなくなる")
        let kept = ["meeting.json", "transcript.md", "minutes.md", "notes.md"].allSatisfy {
            fm.fileExists(atPath: dir(files).appendingPathComponent($0).path)
        }
        c.check(kept, "meeting.json・文字起こし・議事録・メモは残る")
        c.check(MeetingAudioCleanup.deleteAudio(in: dir(files)).isEmpty, "もうないファイルは消せたものとして扱う")
        let locked = meeting("locked", daysAgo: 3)
        put(locked, ["me.m4a": 10])
        try? fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir(locked).path)
        let lockedFailures = MeetingAudioCleanup.deleteAudio(in: dir(locked))
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir(locked).path)
        c.check(lockedFailures.count == 1 && lockedFailures.first?.file == "me.m4a", "消せないファイルは、ファイル名と理由を返す")

        // 録音の管理の一覧（REQ-MTG-056・DEC-MTG-141）
        let recent = meeting("recent", daysAgo: 2)
        let justInside = meeting("inside", daysAgo: 30 - 1.0 / 86400)
        let justOutside = meeting("outside", daysAgo: 30 + 1.0 / 86400)
        let oldPartial = meeting("oldPartial", daysAgo: 60, failed: [.others])
        let oldNone = meeting("oldNone", daysAgo: 90, utterances: 0, status: .failed)
        let recording = meeting("recording", daysAgo: 0, status: .recording)
        let current = meeting("current", daysAgo: 0)
        let noAudio = meeting("noAudio", daysAgo: 100)
        for m in [recent, justInside, justOutside, oldPartial, oldNone, recording, current] { put(m, ["me.m4a": 100, "others.m4a": 100]) }
        put(noAudio, ["meeting.json": 10])
        let all = [noAudio, oldNone, recent, justOutside, recording, oldPartial, current, justInside, locked]
        let entries = MeetingAudioCleanup.entries(all, excluding: current.id, directory: dir)
        c.check(entries.map(\.id) == ["recent", "locked", "inside", "outside", "oldPartial", "oldNone"],
                "録音が残る会議を新しい順に並べ、記録中・処理中・録音のない会議を除く（\(entries.map(\.id))）")
        c.check(entries.first { $0.id == "oldNone" }?.state == MeetingTranscriptState.none, "失敗して発言のない会議には「文字起こしなし」")
        c.check(entries.first { $0.id == "oldPartial" }?.state == .partial(failedChannels: [.others]), "一部が欠けた会議には「一部の文字起こしなし」")

        let older = MeetingAudioCleanup.bulkTargets(entries, olderThan: MeetingAudioCleanup.olderThanDays, now: now)
        c.check(Set(older.targets.map(\.id)) == ["outside"], "30 日より前: 30×24 時間を 1 秒でも過ぎた会議だけ（\(older.targets.map(\.id))）")
        c.check(Set(older.skipped.map(\.id)) == ["oldPartial", "oldNone"], "30 日より前: 文字起こしがそろっていない会議は外す")
        let everything = MeetingAudioCleanup.bulkTargets(entries, olderThan: nil, now: now)
        c.check(Set(everything.targets.map(\.id)) == ["recent", "inside", "outside", "locked"], "すべて: 文字起こしがそろった会議すべて")
        c.check(everything.skipped.count == 2 && MeetingAudioCleanup.totalSize(everything.skipped) == 400, "すべて: 外した件数と大きさ")

        // 保存期間（REQ-MTG-057・DEC-MTG-143）
        c.check(MeetingAudioCleanup.expired(entries, retentionDays: 0, now: now).targets.isEmpty, "保存期間が無期限なら何も消さない")
        c.check(Set(MeetingAudioCleanup.expired(entries, retentionDays: 7, now: now).targets.map(\.id)) == ["inside", "outside"],
                "保存期間 7 日: 7 日より前で、文字起こしがそろった会議")
        c.check(MeetingAudioCleanup.expired(entries, retentionDays: 365, now: now).targets.isEmpty, "保存期間 365 日: 当てはまる会議はない")
        c.check(MeetingAudioCleanup.retentionOptions == HistorySettings.dayOptions.sorted(), "保存期間の選択肢は音声入力の履歴と同じ")

        // 「音声ファイルは残しています」（DEC-MTG-140）
        c.check(MeetingAudioCleanup.showsAudioKept(partial, hasAudio: true), "文字起こしが欠けて録音が残っていれば出す")
        c.check(!MeetingAudioCleanup.showsAudioKept(partial, hasAudio: false), "録音を消したら出さない")
        c.check(!MeetingAudioCleanup.showsAudioKept(on, hasAudio: true), "文字起こしがそろった会議には出さない")
        c.check(MeetingAudioCleanup.showsAudioKept(oldNone, hasAudio: true), "途中で落ちた（失敗の）会議で録音が残っていれば出す")
        c.check(!MeetingAudioCleanup.showsAudioKept(recording, hasAudio: true), "記録中の会議には出さない")

        print(c.failures == 0 ? "すべて OK" : "NG が \(c.failures) 件")
        return c.failures == 0
    }
}
