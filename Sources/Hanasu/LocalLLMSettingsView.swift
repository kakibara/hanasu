import SwiftUI

// 要件: REQ-COM-030
// 設計判断: DEC-COM-062, DEC-COM-066, DEC-COM-067
/// 設定の「AI」で、用途の AI を「ローカル」にしたときの欄。モデルを選び、ダウンロード・削除し、ライセンスを見せる
struct LocalModelChoice: View {
    @Binding var model: LocalLLMModel
    @ObservedObject var store = LocalLLMStore.shared
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker(tr("ローカルのモデル"), selection: $model) {
                ForEach(LocalLLMModel.allCases) { model in
                    Text(tr("%@（%@）", model.name, model.sizeLabel) + (model.isRecommended ? tr("・おすすめ") : "")).tag(model)
                }
            }
            Text(model.summary).font(.caption).foregroundStyle(.secondary)
            status
            HStack(spacing: 4) {
                Text(model.licenseNote)
                Link(tr("ライセンス"), destination: model.licenseURL)
            }
            .font(.caption)
            .foregroundStyle(model == .lfm25JP ? Color.orange : Color.secondary)
            Text(tr("文章はこの Mac の中だけで処理し、ネットには送りません。初めて使うときはモデルの読み込みに数十秒かかります。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var status: some View {
        switch store.status(model) {
        case .notDownloaded:
            HStack {
                Text(tr("まだダウンロードしていません")).font(.caption).foregroundStyle(.orange)
                Spacer()
                Button(tr("ダウンロード（%@）", "\(model.sizeLabel)")) { store.ensureDownloaded(model) }
            }
        case .downloading(let fraction):
            HStack {
                if let fraction {
                    ProgressView(value: fraction)
                    Text("\(Int(fraction * 100))%").font(.caption).monospacedDigit()
                } else {
                    ProgressView().controlSize(.small)
                    Text(tr("確かめています…")).font(.caption)
                }
                Button(tr("中止")) { store.cancelDownload(model) }
            }
        case .downloaded:
            HStack {
                Label(tr("ダウンロード済み"), systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                Spacer()
                Button(tr("削除…")) { confirmDelete = true }
                    .confirmationDialog(tr("ローカルのモデル「%@」を削除しますか？", "\(model.name)"), isPresented: $confirmDelete) {
                        Button(tr("削除"), role: .destructive) { store.delete(model) }
                    } message: {
                        Text(tr("もう一度使うには、ダウンロードし直します（%@）。", "\(model.sizeLabel)"))
                    }
            }
        case .failed(let message):
            HStack {
                Text("⚠️ \(message)").font(.caption).foregroundStyle(.red)
                Spacer()
                Button(tr("もう一度")) { store.ensureDownloaded(model) }
            }
        }
    }
}

// 要件: REQ-COM-031
// 設計判断: DEC-COM-071, DEC-COM-072
/// 設定の「AI」で、用途の AI を「Apple」にしたときの欄。使えるか（使えなければ理由）を出す
struct AppleFMChoice: View {
    @State private var availability = AppleFMAvailability.check()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let reason = availability.reason {
                Text("⚠️ \(reason)").font(.caption).foregroundStyle(.orange)
            } else if let url = availability.executableURL {
                Label(tr("使えます（%@）", "\(url.path)"), systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
            }
            Text(tr("macOS 27 の Apple Intelligence の、この Mac の中のモデルを fm（Foundation Models の CLI）で使います。Private Cloud Compute は使わず、文章をネットに送りません。初めて使う前に、ターミナルで sudo fm license を実行して利用条件に同意する必要があるかもしれません。文脈が短いので、長い会議は分けてまとめます。"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { availability = AppleFMAvailability.check() }
    }
}

