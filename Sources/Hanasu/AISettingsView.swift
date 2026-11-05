import AppKit
import SwiftUI
import UniformTypeIdentifiers

// 要件: REQ-COM-020, REQ-COM-024
// 設計判断: DEC-COM-040
/// 設定の「AI」タブ。音声入力と会議のそれぞれで、使う AI（Gemini / Claude）とモデルを選ぶ。
/// 認証は、Claude は API キー、Gemini は API キーかサービスアカウント。
struct AISettingsTab: View {
    @ObservedObject var settings: AppSettings
    @State private var testInput = tr("えーと明日の会議なんですけど あの資料はジェミニで作ったやつを使いますあ違うグーグルスライドで作ったやつです")
    @State private var testOutput = ""
    @State private var isTesting = false

    var body: some View {
        Form {
            Section {
                AIChoiceRow(settings: settings, purpose: .dictation)
                AIChoiceRow(settings: settings, purpose: .meeting)
            } header: {
                Text(tr("使う AI とモデル"))
            } footer: {
                Text(tr("文章を整える処理だけに使います。音声の文字起こしは「一般」→「文字起こし」で選んだエンジンが行い、Claude には音声を送りません。辞書の候補探しは「会議」の AI を使います。「ローカル」は、この Mac の中で小型の LLM を動かします。「Apple」は macOS 27 の Foundation Models（fm）の、この Mac の中のモデルを使います（どちらも文章をネットに送りません）。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle(tr("音声入力を AI で整える"), isOn: $settings.refineWithGemini)
                // 要件: REQ-DIC-082
                Picker(tr("整形の言語"), selection: $settings.refineOutputLanguage) {
                    ForEach(GeminiClient.RefineOutputLanguage.allCases) { Text($0.label).tag($0) }
                }
                .disabled(!settings.refineWithGemini)
                Toggle(tr("入力先のアプリ名を AI に伝える（体裁の参考）"), isOn: $settings.sendAppName)
            }
            ScreenContextSettingsSection()
            ClaudeKeySection(settings: settings)
            GeminiAuthSection(settings: settings)
            Section(tr("試してみる（音声入力の AI）")) {
                TextField(tr("認識結果の例"), text: $testInput, axis: .vertical)
                    .lineLimit(2...4)
                HStack {
                    Button(isTesting ? tr("送信中…") : tr("整形を試す")) { runTest(translation: nil) }
                        .disabled(isTesting || testInput.isEmpty)
                    // 要件: REQ-DIC-013
                    ForEach(settings.translationLanguages) { language in
                        Button(tr("%@を試す", "\(language.verb)")) { runTest(translation: language) }
                            .disabled(isTesting || testInput.isEmpty)
                    }
                    Spacer()
                }
                if !testOutput.isEmpty {
                    Text(testOutput).textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func runTest(translation: TranslationLanguage?) {
        isTesting = true
        testOutput = ""
        let model = settings.textModel(for: .dictation)
        let request = GeminiClient.Request(
            transcript: settings.userDictionary.apply(to: testInput),
            model: model,
            appName: nil,
            dictionary: settings.dictionaryWords,
            extraInstructions: settings.extraInstructions,
            dictionaryRules: settings.userDictionary.rules,
            outputLanguage: settings.refineOutputLanguage)
        Task {
            let started = Date()
            do {
                let client = try TextAIClient.requireFromSettings(settings, for: .dictation)
                let output = if let translation {
                    try await client.translate(request, to: translation)
                } else {
                    try await client.refine(request)
                }
                testOutput = output + String(format: tr("\n\n（%@ %@ %.1f 秒）"), client.provider.name, model, Date().timeIntervalSince(started))
            } catch {
                testOutput = "⚠️ " + error.localizedDescription
            }
            isTesting = false
        }
    }
}

// 要件: REQ-COM-024, REQ-COM-030
// 設計判断: DEC-COM-092
/// 1 つの用途（音声入力 / 会議）の、AI とモデルの選択。オンボーディングの「設定の Tips」でも使う
struct AIChoiceRow: View {
    @ObservedObject var settings: AppSettings
    var purpose: TextAIPurpose
    /// AI の切り替え（右上のセグメント）を出すか。オンボーディングの AI のページでは、AI はカードで選ぶので出さない
    var showsProviderPicker = true

    private var provider: Binding<TextAIProvider> {
        purpose == .dictation ? $settings.dictationAIProvider : $settings.meetingAIProvider
    }
    private var geminiModel: Binding<String> {
        purpose == .dictation ? $settings.model : $settings.meetingMinutesModel
    }
    private var claudeModel: Binding<String> {
        purpose == .dictation ? $settings.claudeModel : $settings.claudeMinutesModel
    }
    private var localModel: Binding<LocalLLMModel> {
        purpose == .dictation ? $settings.localDictationModel : $settings.localMeetingModel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(purpose.label).font(.headline)
                    Text(purpose == .dictation ? tr("整形・翻訳・選択の編集") : tr("議事録（作り直しも）・会議への質問・辞書の候補"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if showsProviderPicker {
                    Picker("AI", selection: provider) {
                        ForEach(TextAIProvider.allCases) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
            switch provider.wrappedValue {
            case .gemini:
                HStack {
                    TextField(tr("Gemini のモデル"), text: geminiModel)
                    Menu(tr("候補")) {
                        ForEach(AppSettings.suggestedModels, id: \.self) { model in
                            Button(model) { geminiModel.wrappedValue = model }
                        }
                    }
                    .fixedSize()
                }
                if purpose == .dictation {
                    Text(tr("思考レベル: %@（lite は minimal、それ以外は low）", "\(GeminiClient.thinkingLevel(for: settings.model))"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            case .claude:
                Picker(tr("Claude のモデル"), selection: claudeModel) {
                    ForEach(ClaudeClient.Model.allCases) { Text($0.label).tag($0.rawValue) }
                    // 一覧にない ID（以前の設定や、CLI で入れたもの）もそのまま出す
                    if ClaudeClient.Model(rawValue: claudeModel.wrappedValue) == nil {
                        Text(claudeModel.wrappedValue).tag(claudeModel.wrappedValue)
                    }
                }
                Text(purpose == .dictation
                     ? tr("考える量（effort）は low。待ち時間を短くするため")
                     : tr("考える量（effort）は medium。長い会議の記録をまとめるため"))
                    .font(.caption).foregroundStyle(.secondary)
            case .local:
                LocalModelChoice(model: localModel)
            case .appleFM:
                AppleFMChoice()
            }
        }
        .padding(.vertical, 2)
    }
}

// 要件: REQ-COM-021
// 設計判断: DEC-COM-049, DEC-COM-050
/// Claude の API キー。入力欄はマスクし、保存したキーは画面に出さない（末尾 4 文字だけ）。
/// キーの中身はここでは読まない（接続を試すときに ClaudeClient が読む）
struct ClaudeKeySection: View {
    @ObservedObject var settings: AppSettings
    @State private var newKey = ""
    @State private var hint: String? = Keychain.hint(.claudeAPIKey)
    @State private var saved = Keychain.exists(.claudeAPIKey)
    @State private var status: String?
    @State private var isTesting = false

    var body: some View {
        Section {
            LabeledContent(tr("保存したキー")) {
                HStack {
                    Text(saved ? (hint ?? tr("保存済み")) : tr("未設定"))
                        .foregroundStyle(saved ? .primary : .secondary)
                        .monospaced()
                    if saved {
                        Button(isTesting ? tr("確かめています…") : tr("接続を試す"), action: testConnection)
                            .disabled(isTesting)
                        Button(tr("削除"), role: .destructive, action: deleteKey)
                    }
                }
            }
            HStack {
                SecureField(saved ? tr("新しいキーで置き換える") : tr("API キー（sk-ant-…）"), text: $newKey)
                Button(tr("保存"), action: saveKey)
                    .disabled(newKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let status {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            Link(tr("Claude Console で API キーを発行"), destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                .font(.caption)
        } header: {
            Text(tr("Claude（Anthropic）の API キー"))
        } footer: {
            Text(tr("キーはキーチェーンに保存し、Hanasu 以外のアプリが読もうとすると macOS がパスワードを求めるようにします。ただし、同じユーザーで動く悪意のあるプログラムからは守りきれません。料金の目安（100 万トークンあたり 入力 / 出力、2026-11 時点）: Haiku 5.5 は $0.10 / $0.50（10 万トークンを超える部分は $0.50 / $2.50）、Sonnet 5.5 は $2 / $10、Opus 5.5 は $4 / $20。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func refresh() {
        saved = Keychain.exists(.claudeAPIKey)
        hint = Keychain.hint(.claudeAPIKey)
    }

    private func saveKey() {
        let ok = Keychain.save(.claudeAPIKey, key: newKey)
        newKey = ""  // 入力した文字は画面とメモリに残さない
        refresh()
        status = ok ? tr("キーチェーンに保存しました。「接続を試す」で確かめられます") : tr("保存に失敗しました")
    }

    private func deleteKey() {
        Keychain.delete(.claudeAPIKey)
        refresh()
        status = tr("キーを削除しました")
    }

    private func testConnection() {
        guard let client = ClaudeClient.fromKeychain() else { refresh(); return }
        isTesting = true
        status = nil
        let model = settings.aiProvider(for: .dictation) == .claude ? settings.claudeModel : settings.claudeMinutesModel
        Task {
            do {
                try await client.testConnection(model: model)
                status = tr("接続できました（%@ を使えます）", "\(model)")
            } catch {
                status = "⚠️ " + error.localizedDescription
            }
            isTesting = false
        }
    }
}

/// Gemini の認証。AI に Gemini を選んだときと、文字起こしのエンジン「Gemini」で使う。オンボーディングの AI のページでも使う
struct GeminiAuthSection: View {
    @ObservedObject var settings: AppSettings
    @State private var newKey = ""
    @State private var hint: String? = Keychain.hint(.geminiAPIKey)
    @State private var saved = Keychain.exists(.geminiAPIKey)
    @State private var savedMessage: String?

    var body: some View {
        Section {
            Picker(tr("認証方法"), selection: $settings.authMode) {
                ForEach(GeminiAuthMode.allCases) { Text($0.label).tag($0) }
            }
            switch settings.authMode {
            case .apiKey:
                LabeledContent(tr("保存したキー")) {
                    HStack {
                        Text(saved ? (hint ?? tr("保存済み")) : tr("未設定"))
                            .foregroundStyle(saved ? .primary : .secondary)
                            .monospaced()
                        if saved {
                            Button(tr("削除"), role: .destructive) {
                                Keychain.delete(.geminiAPIKey)
                                refresh()
                                savedMessage = tr("キーを削除しました")
                            }
                        }
                    }
                }
                HStack {
                    SecureField(saved ? tr("新しいキーで置き換える") : tr("API キー"), text: $newKey)
                    Button(tr("保存")) {
                        let ok = Keychain.save(.geminiAPIKey, key: newKey)
                        newKey = ""
                        refresh()
                        savedMessage = ok ? tr("キーチェーンに保存しました") : tr("保存に失敗しました")
                    }
                    .disabled(newKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let savedMessage {
                    Text(savedMessage).font(.caption).foregroundStyle(.secondary)
                }
                Link(tr("Google AI Studio で API キーを発行"), destination: URL(string: "https://aistudio.google.com/apikey")!)
                    .font(.caption)
            case .serviceAccount:
                HStack {
                    TextField(tr("サービスアカウントの JSON"), text: $settings.serviceAccountPath, prompt: Text("~/path/to/key.json"))
                    Button(tr("選択…"), action: chooseServiceAccountFile)
                }
                TextField(tr("リージョン"), text: $settings.vertexLocation, prompt: Text("global"))
                Text(serviceAccountSummary)
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text(tr("Gemini の認証"))
        } footer: {
            Text(tr("AI に Gemini を選んだときと、文字起こしのエンジンに Gemini を選んだときに使います。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func refresh() {
        saved = Keychain.exists(.geminiAPIKey)
        hint = Keychain.hint(.geminiAPIKey)
    }

    private var serviceAccountSummary: String {
        let path = settings.serviceAccountPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return tr("Vertex AI のユーザー権限（roles/aiplatform.user）を持つサービスアカウントの鍵を指定してください。") }
        do {
            let credentials = try ServiceAccountCredentials.load(path: path)
            return tr("プロジェクト: %@　アカウント: %@", "\(credentials.projectID)", "\(credentials.clientEmail)")
        } catch {
            return "⚠️ " + error.localizedDescription
        }
    }

    private func chooseServiceAccountFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.serviceAccountPath = url.path
        }
    }
}
