import AppKit
import SwiftUI

// 要件: REQ-COM-032
// 設計判断: DEC-COM-069
/// 用途の AI がローカルなのに、選んだモデルがまだダウンロードされていないとき、整形・議事録の直前に
/// 「ダウンロードしますか」と尋ね、ダウンロードの進み具合をウインドウに出して、終わるまで待つ。
/// ダウンロードしなかった・中止したときは何も投げずに戻る（呼び出し元の TextAIClient が今までどおり「モデルがない」と知らせる）
@MainActor
enum LocalModelDownloadPrompt {
    enum Outcome {
        /// モデルがある（もとからあった・ダウンロードした）
        case ready
        /// 「今回はしない」を選んだ
        case declined
        /// 進み具合のウインドウで「中止」した
        case cancelled
        case failed(String)
    }

    enum Failure: LocalizedError {
        case downloadFailed(LocalLLMModel, String)

        var errorDescription: String? {
            switch self {
            case .downloadFailed(let model, let message): "ローカルのモデル「\(model.name)」をダウンロードできませんでした: \(message)"
            }
        }
    }

    /// 同じモデルを 2 つの処理が同時に待つときは、尋ねるのを 1 回にする
    private static var inFlight: [LocalLLMModel: Task<Outcome, Never>] = [:]
    /// 出している進み具合のウインドウ（閉じるまで持っておく）
    private static var windows: [LocalLLMModel: NSWindow] = [:]

    /// - Parameters:
    ///   - work: これから行う処理（「整形」「翻訳」「議事録の作成」）。「続けて〜を始めます」に入れる
    ///   - whenSkipped: ダウンロードしないときにどうなるか（「整形前の文章を入力します」）
    ///   - restoreFrontmostApp: 尋ねる前に前面にあったアプリを、終わったら前に戻す（音声入力の入力先）
    static func prepare(for purpose: TextAIPurpose, settings: AppSettings = .shared, work: String, whenSkipped: String,
                        restoreFrontmostApp: Bool = false) async throws {
        guard settings.aiProvider(for: purpose) == .local else { return }
        let model = settings.localModel(for: purpose)
        guard !LocalLLMStore.isDownloaded(model) else { return }

        let outcome: Outcome
        if let task = inFlight[model] {
            outcome = await task.value
        } else {
            let previousApp = NSWorkspace.shared.frontmostApplication
            let task = Task { await run(model, work: work, whenSkipped: whenSkipped) }
            inFlight[model] = task
            outcome = await task.value
            inFlight[model] = nil
            if restoreFrontmostApp, let previousApp, previousApp != NSRunningApplication.current {
                await bringBack(previousApp)
            }
        }
        appLog.notice("local model prompt: \(model.rawValue, privacy: .public) -> \(String(describing: outcome), privacy: .public)")
        if case .failed(let message) = outcome { throw Failure.downloadFailed(model, message) }
    }

    private static func run(_ model: LocalLLMModel, work: String, whenSkipped: String) async -> Outcome {
        let store = LocalLLMStore.shared
        // 設定やオンボーディングで始めたダウンロードの途中なら、尋ねずに待つ
        if case .downloading = store.status(model) {} else {
            guard ask(model, work: work, whenSkipped: whenSkipped) else { return .declined }
        }
        guard let task = store.ensureDownloaded(model) else { return .ready }
        showProgress(model, work: work)
        await task.value
        windows.removeValue(forKey: model)?.close()
        switch store.status(model) {
        case .downloaded: return .ready
        case .failed(let message): return .failed(message)
        case .notDownloaded, .downloading: return .cancelled
        }
    }

    /// 「ダウンロードしますか」のダイアログ。ダウンロードするなら true
    private static func ask(_ model: LocalLLMModel, work: String, whenSkipped: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "ローカルのモデルをダウンロードしますか？"
        alert.informativeText = """
            \(work)に使うローカルのモデル「\(model.name)」（\(model.sizeLabel)）が、まだこの Mac にありません。\
            ダウンロードすると、終わったら続けて\(work)を始めます。ダウンロードしないときは、\(whenSkipped)。
            """
        alert.addButton(withTitle: "ダウンロードする")
        alert.addButton(withTitle: "今回はしない")
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func showProgress(_ model: LocalLLMModel, work: String) {
        let hosting = NSHostingController(rootView: LocalModelDownloadView(model: model, work: work))
        let window = NSWindow(contentViewController: hosting)
        window.title = "モデルのダウンロード"
        // 閉じるボタンは付けない（止めるときは「中止」）
        window.styleMask = [.titled]
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()
        windows[model] = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// 入力先のアプリを前に戻し、前に来るのを少し待つ（貼り付けの前に）
    private static func bringBack(_ app: NSRunningApplication) async {
        NSApp.yieldActivation(to: app)
        app.activate()
        for _ in 0..<20 {
            if NSWorkspace.shared.frontmostApplication == app { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}

// 要件: REQ-COM-032
// 設計判断: DEC-COM-069
/// ダウンロードの進み具合のウインドウの中身。バー・割合・ダウンロードした大きさ・「中止」
struct LocalModelDownloadView: View {
    let model: LocalLLMModel
    let work: String
    @ObservedObject var store = LocalLLMStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("\(model.name) をダウンロードしています", systemImage: "arrow.down.circle")
                .font(.headline)
            Text("終わったら、続けて\(work)を始めます。").font(.callout).foregroundStyle(.secondary)
            progress
            HStack {
                Spacer()
                Button("中止") { store.cancelDownload(model) }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    @ViewBuilder private var progress: some View {
        switch store.status(model) {
        case .downloading(let fraction?):
            ProgressView(value: fraction)
            Text("\(Int(fraction * 100))%（\(byteLabel(fraction)) / \(model.sizeLabel)）")
                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
        case .downloading(nil):
            ProgressView().progressViewStyle(.linear)
            Text("ダウンロードしたファイルを確かめています…").font(.caption).foregroundStyle(.secondary)
        default:
            ProgressView(value: 0)
            Text("準備しています…").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func byteLabel(_ fraction: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(Double(model.byteCount) * fraction), countStyle: .file)
    }
}
