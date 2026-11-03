import SwiftUI

// 要件: REQ-COM-030
// 設計判断: DEC-COM-062, DEC-COM-066
/// 設定の「AI」タブで、用途の AI を「ローカル」にしたときの欄。モデルを選び、ダウンロード・削除し、ライセンスを見せる
struct LocalModelChoice: View {
    @Binding var model: LocalLLMModel
    @ObservedObject var store = LocalLLMStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("ローカルのモデル", selection: $model) {
                ForEach(LocalLLMModel.allCases) { model in
                    Text("\(model.name)（\(model.sizeLabel)）").tag(model)
                }
            }
            Text(model.summary).font(.caption).foregroundStyle(.secondary)
            status
            HStack(spacing: 4) {
                Text(model.licenseNote)
                Link("ライセンス", destination: model.licenseURL)
            }
            .font(.caption)
            .foregroundStyle(model == .lfm25JP ? Color.orange : Color.secondary)
            Text("文章はこの Mac の中だけで処理し、ネットには送りません。初めて使うときはモデルの読み込みに数十秒かかります。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var status: some View {
        switch store.status(model) {
        case .notDownloaded:
            HStack {
                Text("まだダウンロードしていません").font(.caption).foregroundStyle(.orange)
                Spacer()
                Button("ダウンロード（\(model.sizeLabel)）") { store.ensureDownloaded(model) }
            }
        case .downloading(let fraction):
            HStack {
                if let fraction {
                    ProgressView(value: fraction)
                    Text("\(Int(fraction * 100))%").font(.caption).monospacedDigit()
                } else {
                    ProgressView().controlSize(.small)
                    Text("確かめています…").font(.caption)
                }
                Button("中止") { store.cancelDownload(model) }
            }
        case .downloaded:
            HStack {
                Label("ダウンロード済み", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                Spacer()
                Button("削除") { store.delete(model) }
            }
        case .failed(let message):
            HStack {
                Text("⚠️ \(message)").font(.caption).foregroundStyle(.red)
                Spacer()
                Button("もう一度") { store.ensureDownloaded(model) }
            }
        }
    }
}
