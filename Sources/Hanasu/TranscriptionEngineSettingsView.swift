import SwiftUI

// 要件: REQ-COM-001
// 設計判断: DEC-COM-020
/// 設定の「一般」タブの「文字起こし」欄。音声入力と会議の記録で、エンジンを別々に選ぶ。
/// Whisper を選ぶとモデルのダウンロードを始め、Gemini を選ぶと音声が送られることを示す。
struct TranscriptionEngineSettingsSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store = WhisperModelStore.shared

    private var engines: [TranscriptionEngine] { [settings.dictationEngine, settings.meetingEngine] }

    // 要件: REQ-COM-004
    /// 言語の候補。保存されている言語は読み込むときに一覧のものへ寄せてある（`AppSettings.nearestTranscriptionLocale`）
    private var languageOptions: [String] { AppSettings.transcriptionLocaleIdentifiers }

    var body: some View {
        Section {
            Picker("音声入力", selection: $settings.dictationEngine) {
                ForEach(TranscriptionEngine.allCases) { Text($0.label).tag($0) }
            }
            Picker("会議の記録", selection: $settings.meetingEngine) {
                ForEach(TranscriptionEngine.allCases) { Text($0.label).tag($0) }
            }
            if engines.contains(.apple) {
                Picker("Mac 標準の認識モデル", selection: $settings.engine) {
                    ForEach(RecognizerEngine.allCases) { Text($0.label).tag($0) }
                }
            }
            // 要件: REQ-COM-004
            Picker("言語", selection: $settings.localeIdentifier) {
                ForEach(languageOptions, id: \.self) { id in
                    Text(Locale(identifier: "ja-JP").localizedString(forIdentifier: id) ?? id).tag(id)
                }
            }
        } header: {
            Text("文字起こし")
        } footer: {
            Text("Mac 標準は、話している途中から文字が出ます。Whisper と Gemini は、録音を止めてからまとめて文字起こしします（会議の記録では、記録中の文字起こしは出ず、記録のあとに行います）。「選択を声で編集」も、音声入力と同じエンジンを使います。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: settings.dictationEngine) { _, engine in downloadIfNeeded(engine) }
        .onChange(of: settings.meetingEngine) { _, engine in downloadIfNeeded(engine) }

        if engines.contains(.whisper) {
            WhisperModelSection(settings: settings, store: store)
        }
        if engines.contains(.gemini) {
            GeminiTranscriptionSection(settings: settings)
        }
    }

    // 要件: REQ-COM-003
    private func downloadIfNeeded(_ engine: TranscriptionEngine) {
        guard engine == .whisper else { return }
        store.ensureDownloaded(settings.whisperModel)
    }
}

/// Whisper のモデルの選択・ダウンロード・削除
private struct WhisperModelSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: WhisperModelStore

    var body: some View {
        Section {
            Picker("モデル", selection: $settings.whisperModel) {
                ForEach(WhisperModel.allCases) { Text($0.label).tag($0) }
            }
            .onChange(of: settings.whisperModel) { _, model in
                // 選んだ時点でダウンロードを始める。ほかのモデルのダウンロード中なら止める
                for other in WhisperModel.allCases where other != model { store.cancelDownload(other) }
                store.ensureDownloaded(model)
            }
            WhisperModelRow(model: settings.whisperModel, store: store, isSelected: true)
            // 前に使っていたモデルが残っていれば、ここで消せる
            ForEach(WhisperModel.allCases.filter { $0 != settings.whisperModel && store.status($0) != .notDownloaded }) { model in
                WhisperModelRow(model: model, store: store, isSelected: false)
            }
        } header: {
            Text("Whisper")
        } footer: {
            Text("WhisperKit（CoreML 版の Whisper）を、この Mac の上で動かします。音声は Mac の外に送られません。日本語は small 以上がおすすめです。モデルの保存先: ~/Library/Application Support/Hanasu/Models/whisper")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct WhisperModelRow: View {
    let model: WhisperModel
    @ObservedObject var store: WhisperModelStore
    let isSelected: Bool
    @State private var confirmDelete = false

    var body: some View {
        LabeledContent(isSelected ? "状態" : model.rawValue) {
            switch store.status(model) {
            case .notDownloaded:
                HStack {
                    Text("未ダウンロード").foregroundStyle(.secondary)
                    Button("ダウンロード") { store.ensureDownloaded(model) }
                }
            case .downloading(let fraction):
                HStack {
                    if let fraction {
                        ProgressView(value: fraction).frame(width: 140)
                        Text("\(Int(fraction * 100))%").monospacedDigit().foregroundStyle(.secondary)
                    } else {
                        ProgressView().controlSize(.small)
                        Text("初回の最適化中…").foregroundStyle(.secondary)
                    }
                    Button("取り消す") { store.cancelDownload(model) }
                }
            case .downloaded:
                HStack {
                    Label("ダウンロード済み", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    if let size = store.diskUsage(model) {
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)).foregroundStyle(.secondary)
                    }
                    Button("削除…", role: .destructive) { confirmDelete = true }
                        .confirmationDialog("Whisper のモデル「\(model.rawValue)」を削除しますか？", isPresented: $confirmDelete) {
                            Button("削除", role: .destructive) { store.delete(model) }
                        } message: {
                            Text("もう一度使うには、ダウンロードし直します。")
                        }
                }
            case .failed(let message):
                HStack {
                    Text("⚠️ \(message)").foregroundStyle(.secondary).lineLimit(2).help(message)
                        .textSelection(.enabled)
                    Button("再試行") { store.ensureDownloaded(model) }
                }
            }
        }
    }
}

// 設計判断: DEC-COM-033
/// Gemini で文字起こしするときの注意とモデル
private struct GeminiTranscriptionSection: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Section {
            Label {
                Text("録った音声を Google（Gemini API / Vertex AI）に送って文字起こしします。会議の記録では、会議の音声（自分と相手の声）がすべて送られます。")
            } icon: {
                Image(systemName: "exclamationmark.icloud.fill").foregroundStyle(.orange)
            }
            HStack {
                TextField("文字起こしのモデル", text: $settings.geminiTranscriptionModel)
                Menu("候補") {
                    ForEach(AppSettings.suggestedModels, id: \.self) { model in
                        Button(model) { settings.geminiTranscriptionModel = model }
                    }
                }
                .fixedSize()
            }
        } header: {
            Text("Gemini で文字起こし")
        } footer: {
            Text("認証は「Gemini」タブの設定を使います。音声入力では、文字起こしのあとに辞書・スニペットを当ててから、いつもどおり整形します（Gemini を 2 回呼びます）。長い会議は 5 分ごとに分けて送ります。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
