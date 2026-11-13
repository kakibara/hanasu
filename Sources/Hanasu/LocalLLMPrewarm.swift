import Foundation

// 要件: REQ-COM-033
// 設計判断: DEC-DIC-220, DEC-COM-110
/// 音声入力・選択の編集の録音 1 回分の、ローカルのモデルの先読み。
/// 録音中になったら request で裏の読み込みを頼み（録音は待たない）、止めた・取り消した・失敗したら release で保持を外す
@MainActor
final class LocalModelWarmHold {
    private var task: Task<UUID?, Never>?

    /// 音声入力の AI がローカルで、そのモデルがダウンロード済みなら、裏で読み込みを始める。もう頼んでいれば何もしない
    func request(settings: AppSettings) {
        guard task == nil, settings.aiProvider(for: .dictation) == .local else { return }
        let model = settings.localModel(for: .dictation)
        // モデルがなければ読み込まない（止めたあとに、ダウンロードするかを尋ねる。REQ-COM-032）
        guard LocalLLMStore.isDownloaded(model) else { return }
        task = Task.detached { await LocalLLMServer.shared.prewarm(model) }
    }

    /// 録音中の保持を外す（そこから 5 分使わなければサーバーが止まる）。頼んでいなければ何もしない
    func release() {
        guard let task else { return }
        self.task = nil
        Task.detached {
            if let hold = await task.value { await LocalLLMServer.shared.releaseWarmHold(hold) }
        }
    }
}
