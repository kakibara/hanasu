import AppKit
import SwiftUI

// 文字起こしのエンジンの確認用 CLI:
//   Hanasu --transcribe-file <音声> --engine apple|whisper|gemini [-whisperModel tiny|base|small|largeV3Turbo]
//          （--engine dictation|speech は、Mac 標準のそのモジュールで起こす。従来どおり）
//   Hanasu --meeting-files <自分> <相手> --engine whisper|gemini   会議の後処理を Whisper / Gemini で（main.swift）
//   Hanasu --download-whisper <tiny|base|small|largeV3Turbo>      モデルをダウンロードする（進み具合を表示）
//   Hanasu --render-engine-settings <出力.png> [-dictationTranscriptionEngine whisper] [-meetingTranscriptionEngine gemini]
//          [--downloading]   設定の「AI」の「文字起こし AI」欄を PNG にする（--downloading は選んでいるモデルをダウンロード中の見た目にする）
// -whisperModel / -geminiTranscriptionModel は UserDefaults の引数で、その回だけ設定を上書きする（保存しない）。
// モデルの保存先は環境変数 HANASU_MODELS_DIR で変えられる（既定は ~/Library/Application Support/Hanasu/Models/whisper）。
// 確かめ方: REQ-COM-001, REQ-COM-002, REQ-COM-003
@MainActor
enum TranscriptionEngineCLI {
    /// --engine の値。apple / dictation / speech は Mac 標準（後ろの 2 つはモジュールの指定）
    static func parseEngine(_ args: [String]) -> (TranscriptionEngine, RecognizerEngine) {
        let value = args.firstIndex(of: "--engine").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        if let value, let module = RecognizerEngine(rawValue: value) { return (.apple, module) }
        if let value, let engine = TranscriptionEngine(rawValue: value) { return (engine, AppSettings.shared.engine) }
        return (.apple, .speech)
    }

    /// Whisper / Gemini で音声ファイルを文字に起こす（音声入力と同じ関数を使う）
    static func transcribeFile(_ url: URL, engine: TranscriptionEngine) async throws -> String {
        let settings = AppSettings.shared
        if engine == .whisper { try await ensureWhisperModel(settings.whisperModel) }
        let samples = try TranscriptionAudio.loadSamples(from: url)
        let hints = settings.userDictionary.contextualStrings + SnippetStore.shared.triggerPhrases
        if engine == .whisper {
            // 1 回目はモデルの読み込みを含むので、読み込みを先に済ませて文字起こしだけの時間を出す
            let loadStarted = Date()
            await WhisperEngine.shared.preload(settings.whisperModel)
            print(String(format: "[Whisper %@ 読み込み %.1fs]", settings.whisperModel.rawValue, Date().timeIntervalSince(loadStarted)))
        }
        return try await BatchTranscriber.transcribeText(samples, engine: engine, settings: settings, hints: hints)
    }

    static func ensureWhisperModel(_ model: WhisperModel) async throws {
        guard !WhisperModelStore.isDownloaded(model) else { return }
        print("Whisper のモデル（\(model.variant)）をダウンロードします: \(WhisperModelStore.baseDirectory.path)")
        let started = Date()
        let throttle = PrintThrottle()
        try await WhisperModelStore.download(model) { fraction in
            guard let fraction else { print("読み込み・最適化中…"); return }
            throttle.printIfAdvanced(Int(fraction * 100))
        }
        print(String(format: "ダウンロード完了 %.1fs（%@）", Date().timeIntervalSince(started),
                     ByteCountFormatter.string(fromByteCount: WhisperModelStore.shared.diskUsage(model) ?? 0, countStyle: .file)))
    }

    static func runIfRequested() {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--download-whisper"), args.indices.contains(index + 1) {
            guard let model = WhisperModel(rawValue: args[index + 1]) else {
                FileHandle.standardError.write(Data("error: モデルは \(WhisperModel.allCases.map(\.rawValue).joined(separator: " / "))\n".utf8))
                exit(1)
            }
            Task { @MainActor in
                do {
                    try await ensureWhisperModel(model)
                    exit(0)
                } catch {
                    FileHandle.standardError.write(Data("error: \(error.localizedDescription) (\(error))\n".utf8))
                    exit(1)
                }
            }
            RunLoop.main.run()
        }
        if let index = args.firstIndex(of: "--render-engine-settings"), args.indices.contains(index + 1) {
            renderSettings(to: URL(fileURLWithPath: args[index + 1]), args: args)
            exit(0)
        }
    }

    /// 設定の「AI」の「文字起こし AI」欄を PNG にする
    static func renderSettings(to url: URL, args: [String]) {
        _ = NSApplication.shared
        let settings = AppSettings.shared
        if args.contains("--downloading") {
            WhisperModelStore.shared.showDownloadingForRendering(settings.whisperModel, fraction: 0.42)
        }
        let height: CGFloat = 820
        // 設定の「AI」のうち、この欄だけを同じ Form の見た目で描く（設定画面全体は画面外では描きにくいため）
        let view = Form { TranscriptionEngineSettingsSection(settings: settings) }
            .formStyle(.grouped)
            .frame(width: 560, height: height)
            .background(Color(nsColor: .windowBackgroundColor))
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 560, height: height)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            print("wrote \(url.path)")
        }
    }
}

/// ダウンロードの進み具合を 10% ごとに表示する
private final class PrintThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var last = -1

    func printIfAdvanced(_ percent: Int) {
        let shouldPrint = lock.withLock {
            guard percent / 10 != last / 10 else { return false }
            last = percent
            return true
        }
        if shouldPrint { print("downloading \(percent)%") }
    }
}
