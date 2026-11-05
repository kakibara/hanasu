import AppKit
import AVFoundation
import SwiftUI

// 音声入力の履歴の確認用 CLI モード:
//   Hanasu --render-history <出力.png> [--settings] [--light|--dark]
//     仮のデータで履歴ウインドウ（--settings なら設定の「履歴」）を画像にする
//   Hanasu --history-check <作業フォルダ> [--gemini]
//     作業フォルダの中で保存・読み込み・上限・削除を確かめる。--gemini を付けると整形・英訳のやり直しも試す
// どちらも本物の履歴（~/Library/Application Support/Hanasu/History）には触れない。
// 確かめ方: REQ-DIC-060, REQ-DIC-061
@MainActor
enum DictationHistoryCLI {
    static func runIfRequested() {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--render-history"), args.indices.contains(index + 1) {
            let appearance: NSAppearance.Name? = args.contains("--dark") ? .darkAqua : args.contains("--light") ? .aqua : nil
            render(to: URL(fileURLWithPath: args[index + 1]), settingsTab: args.contains("--settings"), appearance: appearance)
            exit(0)
        }
        if let index = args.firstIndex(of: "--history-check"), args.indices.contains(index + 1) {
            let base = URL(fileURLWithPath: args[index + 1], isDirectory: true)
            let gemini = args.contains("--gemini")
            Task { @MainActor in
                let ok = await check(base: base, gemini: gemini)
                exit(ok ? 0 : 1)
            }
            RunLoop.main.run()
        }
    }

    // MARK: - 見た目の確認

    private static func sampleStore() -> DictationHistoryStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hanasu-history-render-\(UUID().uuidString)", isDirectory: true)
        let store = DictationHistoryStore(directory: directory)
        let now = Date()
        let samples: [(minutesAgo: Double, raw: String, output: String, mode: DictationHistoryEntry.Mode,
                       app: String, status: DictationHistoryEntry.Status, error: String?)] = [
            (3, "えーと明日の会議なんですけど あの資料はジェミニで作ったやつを使いますあ違うグーグルスライドで作ったやつです",
             "明日の会議なんですけど、資料はGoogleスライドで作ったやつを使います。", .refine, "Slack", .succeeded, nil),
            (12, "あの来週の水曜日って空いてますかえっと新しい機能のデモをしたいので 30分くらい時間をもらえると助かります",
             "あの来週の水曜日って空いてますかえっと新しい機能のデモをしたいので 30分くらい時間をもらえると助かります",
             .refine, "Mail", .geminiFailed, "Gemini API エラー（503）: The model is overloaded. Please try again later."),
            (40, "お疲れ様です 先日の件ですが来週の火曜日って空いてますか",
             "Hi, about the other day, are you available next Tuesday?", .translate, "Google Chrome", .succeeded, nil),
            (70, "Thanks for the update. Could you send me the slides by Friday?",
             "ご連絡ありがとうございます。金曜日までにスライドを送っていただけますか？", .translateJapanese, "Slack", .succeeded, nil),
            (95, "それ田中さんに確認してもらってもいいですか じゃなくて佐藤さんでした",
             "それ田中さんに確認してもらってもいいですか じゃなくて佐藤さんでした", .refine, "メモ", .noCredentials, nil),
            (60 * 24 + 30, "部長から来週までに出してって頼まれてるんですけど間に合いそうにないです",
             "部長から来週までに出してって頼まれてるんですけど、間に合いそうにないです。", .refine, "Slack", .succeeded, nil),
            (60 * 24 + 200, "今日の議事録を要約して", "今日の議事録を要約して", .refine, "Notion", .refineOff, nil),
            (60 * 24 * 3, "了解ですそれで進めてください", "了解です。それで進めてください。", .refine, "Slack", .succeeded, nil),
        ]
        for sample in samples.reversed() {
            store.record(raw: sample.raw, output: sample.output, mode: sample.mode, appName: sample.app,
                         status: sample.status, errorMessage: sample.error,
                         model: sample.status == .succeeded ? "gemini-3.5-flash-lite" : nil,
                         date: now.addingTimeInterval(-sample.minutesAgo * 60))
        }
        return store
    }

    private static func render(to url: URL, settingsTab: Bool, appearance: NSAppearance.Name?) {
        let app = NSApplication.shared
        if let appearance { app.appearance = NSAppearance(named: appearance) }
        let store = sampleStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let view: AnyView
        if settingsTab {
            view = AnyView(
                HistorySettingsTab(store: store, onOpenHistory: {}, onBeginShortcutRecording: {}, onEndShortcutRecording: {})
                    .frame(width: 560, height: 560))
        } else {
            // 失敗した項目を選んだ状態で描く
            let failed = store.entries.first { $0.status == .geminiFailed }?.id
            view = AnyView(DictationHistoryView(store: store, selection: failed).frame(width: 900, height: 580))
        }
        let hosting = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        if let appearance { window.appearance = NSAppearance(named: appearance) }
        window.contentView = hosting
        // List や Form は AppKit の部品なので、一度描かせてから写す
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        hosting.layoutSubtreeIfNeeded()
        if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            print("wrote \(url.path)")
        }
    }

    // MARK: - 保存と読み込みの確認

    private static func check(base: URL, gemini: Bool) async -> Bool {
        let directory = base.appendingPathComponent("hanasu-history-check-\(Int(Date().timeIntervalSince1970))", isDirectory: true)
        var failures = 0
        func expect(_ condition: Bool, _ label: String) {
            print("\(condition ? "✓" : "✗") \(label)")
            if !condition { failures += 1 }
        }
        print("作業フォルダ: \(directory.path)")

        // 1. 保存と上限（件数 5・30 日、音声も残す）
        let store = DictationHistoryStore(directory: directory)
        store.policy = .init(enabled: true, maxCount: 5, maxDays: 30, keepAudio: true)
        let now = Date()
        var audioURLs: [URL] = []
        for i in 0..<7 {
            let audio = store.newAudioURL()
            if let audio {
                FileManager.default.createFile(atPath: audio.path, contents: Data(repeating: UInt8(i), count: 1024))
                audioURLs.append(audio)
            }
            // 0 番目は 40 日前（期間の上限で消える）、ほかは i 時間前
            let date = i == 0 ? now.addingTimeInterval(-40 * 86400) : now.addingTimeInterval(-Double(7 - i) * 3600)
            store.record(raw: "原文 \(i)", output: "結果 \(i)", mode: [.refine, .translate, .translateJapanese][i % 3],
                         appName: "App\(i)", status: i == 3 ? .geminiFailed : .succeeded,
                         errorMessage: i == 3 ? "テスト用のエラー" : nil, model: "test-model", audioURL: audio, date: date)
        }
        expect(audioURLs.count == 7, "音声の保存先を 7 件払い出せる")
        expect(store.entries.count == 5, "件数の上限 5 件に収まる（\(store.entries.count) 件）")
        expect(store.entries.map(\.output) == ["結果 6", "結果 5", "結果 4", "結果 3", "結果 2"], "新しい順に並び、古いものから消える")
        expect(!FileManager.default.fileExists(atPath: audioURLs[0].path), "期間の上限で消えた項目の音声も消える")
        expect(!FileManager.default.fileExists(atPath: audioURLs[1].path), "件数の上限で消えた項目の音声も消える")
        expect(store.audioUsage().count == 5, "残っている音声は 5 件（\(store.audioUsage().count) 件）")

        // 2. 読み込み
        let reloaded = DictationHistoryStore(directory: directory)
        reloaded.policy = store.policy
        reloaded.load()
        expect(reloaded.entries == store.entries, "保存した内容をそのまま読み込める")
        // 設計判断: DEC-DIC-029
        let savedJSON = (try? String(contentsOf: store.fileURL, encoding: .utf8)) ?? ""
        expect(savedJSON.contains("\"translate\"") && savedJSON.contains("\"translateJapanese\""),
               "英訳は translate、和訳は translateJapanese として保存される")
        expect(reloaded.entries.contains { $0.mode == .translateJapanese && $0.mode.label == "和訳" }, "和訳のモードを読み込める")
        expect(reloaded.entries.first { $0.output == "結果 3" }?.status == .geminiFailed, "状態（Gemini 失敗）とエラー内容が残る")
        let attributes = try? FileManager.default.attributesOfItem(atPath: store.fileURL.path)
        let permissions = (attributes?[.posixPermissions] as? NSNumber)?.intValue ?? 0
        expect(permissions == 0o600, String(format: "history.json は本人だけが読める（%o）", permissions))

        // 3. 削除
        if let target = reloaded.entries.first(where: { $0.output == "結果 4" }) {
            let audio = reloaded.audioURL(for: target)
            reloaded.delete([target.id])
            expect(audio.map { !FileManager.default.fileExists(atPath: $0.path) } ?? false, "削除すると音声も消える")
        }
        let afterDelete = DictationHistoryStore(directory: directory)
        afterDelete.policy = store.policy
        afterDelete.load()
        expect(afterDelete.entries.count == 4 && !afterDelete.entries.contains { $0.output == "結果 4" }, "削除がファイルに反映される")

        // 4. 件数の上限を下げると、すぐに古いものが消える
        afterDelete.policy.maxCount = 2
        expect(afterDelete.entries.count == 2, "上限を下げるとその場で消える（\(afterDelete.entries.count) 件）")

        // 5. 保存しない設定
        afterDelete.policy.enabled = false
        expect(afterDelete.newAudioURL() == nil, "保存しない設定では音声の保存先を出さない")
        afterDelete.record(raw: "保存しない原文", output: "保存しない結果", mode: .refine, appName: nil, status: .refineOff)
        expect(afterDelete.entries.first?.output == "保存しない結果", "保存しない設定でも、メモリ上の最新として使える")
        let fileOnly = DictationHistoryStore(directory: directory)
        fileOnly.load()
        expect(!fileOnly.entries.contains { $0.output == "保存しない結果" }, "保存しない設定の項目はファイルに書かれない")
        expect(fileOnly.entries.count == 2, "保存済みの履歴はそのまま残る（\(fileOnly.entries.count) 件）")

        // 6. 壊れたファイルは上書きしない
        let broken = directory.appendingPathComponent("broken", isDirectory: true)
        try? FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        try? Data("{ not json".utf8).write(to: broken.appendingPathComponent("history.json"))
        let brokenStore = DictationHistoryStore(directory: broken)
        brokenStore.load()
        let brokenText = try? String(contentsOf: brokenStore.fileURL, encoding: .utf8)
        expect(brokenStore.lastError != nil && brokenText == "{ not json", "読めないファイルはエラーにして上書きしない")

        // 7. すべて削除
        fileOnly.deleteAll()
        let empty = DictationHistoryStore(directory: directory)
        empty.load()
        expect(empty.entries.isEmpty && empty.audioUsage().count == 0, "すべて削除で履歴と音声が消える")

        // 8. 録音の書き出し（音声認識に渡すのと同じ 16 kHz・モノラルの形式で 1 秒ぶん書く）
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("writer-test.m4a")
            guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false)
            else { throw DictationHistoryError.notFound }
            let writer = try DictationAudioWriter(url: url, format: format)
            for chunk in 0..<4 {
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4000) else { continue }
                buffer.frameLength = 4000
                for i in 0..<4000 {
                    let t = Double(chunk * 4000 + i) / 16000
                    buffer.int16ChannelData![0][i] = Int16(sin(2 * .pi * 440 * t) * 8000)
                }
                writer.write(buffer)
            }
            writer.close()
            writer.write(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16)!)  // 閉じた後の書き込みは無視される
            let file = try AVAudioFile(forReading: url)
            let seconds = Double(file.length) / file.processingFormat.sampleRate
            expect(abs(seconds - 1) < 0.1, String(format: "録音を m4a に書き出して読み戻せる（%.2f 秒）", seconds))
        } catch {
            expect(false, "録音の書き出し: \(error.localizedDescription)")
        }

        // 9. Gemini で整形・英訳し直す
        if gemini {
            do {
                let client = try TextAIClient.cli(args: CommandLine.arguments, settings: AppSettings.shared, for: .dictation)
                let retryStore = DictationHistoryStore(directory: directory)
                let entry = retryStore.record(
                    raw: "えーと明日の会議なんですけど あの資料はジェミニで作ったやつを使いますあ違うグーグルスライドで作ったやつです",
                    output: "えーと明日の会議なんですけど あの資料はジェミニで作ったやつを使いますあ違うグーグルスライドで作ったやつです",
                    mode: .refine, appName: "Slack", status: .geminiFailed, errorMessage: "テスト用のエラー")
                let refined = try await retryStore.retry(entry.id, mode: .refine, client: client)
                print("  整形し直し: \(refined.output)")
                expect(refined.status == .succeeded && refined.errorMessage == nil && refined.retriedAt != nil
                       && refined.output != entry.raw, "整形し直すと結果と状態が更新される")
                let translated = try await retryStore.retry(entry.id, mode: .translate, client: client)
                print("  英訳し直し: \(translated.output)")
                expect(translated.mode == .translate && translated.status == .succeeded, "英訳し直すとモードが英訳になる")
                let saved = DictationHistoryStore(directory: directory)
                saved.load()
                expect(saved.entries.first?.output == translated.output, "やり直した結果がファイルに残る")
            } catch {
                expect(false, "Gemini でのやり直し: \(error.localizedDescription)")
            }
        }

        try? FileManager.default.removeItem(at: directory)
        print(failures == 0 ? "すべて OK" : "\(failures) 件が NG")
        return failures == 0
    }
}
