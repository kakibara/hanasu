import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    var onOpenMeetingNotes: () -> Void
    var onBeginShortcutRecording: () -> Void
    var onEndShortcutRecording: () -> Void
    var onOpenHistory: () -> Void = {}

    var body: some View {
        TabView {
            GeneralTab(
                settings: settings,
                onBeginShortcutRecording: onBeginShortcutRecording,
                onEndShortcutRecording: onEndShortcutRecording)
                .tabItem { Label("一般", systemImage: "gearshape") }
            GeminiTab(settings: settings)
                .tabItem { Label("Gemini", systemImage: "sparkles") }
            WordsTab(settings: settings)
                .tabItem { Label("辞書・ルール", systemImage: "character.book.closed") }
            AppStylesTab()
                .tabItem { Label("アプリ別", systemImage: "square.grid.2x2") }
            SnippetsSettingsView()
                .tabItem { Label("スニペット", systemImage: "text.badge.plus") }
            MeetingTab(
                settings: settings,
                onOpenMeetingNotes: onOpenMeetingNotes,
                onBeginShortcutRecording: onBeginShortcutRecording,
                onEndShortcutRecording: onEndShortcutRecording)
                .tabItem { Label("会議", systemImage: "person.2.wave.2") }
            HistorySettingsTab(
                onOpenHistory: onOpenHistory,
                onBeginShortcutRecording: onBeginShortcutRecording,
                onEndShortcutRecording: onEndShortcutRecording)
                .tabItem { Label("履歴", systemImage: "clock.arrow.circlepath") }
            PermissionsTab()
                .tabItem { Label("権限", systemImage: "lock.shield") }
        }
        .frame(width: 560, height: 460)
    }
}

private struct GeneralTab: View {
    @ObservedObject var settings: AppSettings
    var onBeginShortcutRecording: () -> Void
    var onEndShortcutRecording: () -> Void

    var body: some View {
        Form {
            Section("ショートカット") {
                LabeledContent("録音の開始／停止") {
                    ShortcutRecorder(
                        combo: $settings.hotKey,
                        onBeginRecording: onBeginShortcutRecording,
                        onEndRecording: onEndShortcutRecording)
                }
                LabeledContent("英訳して入力") {
                    ShortcutRecorder(
                        combo: $settings.translateHotKey,
                        defaultCombo: .defaultTranslate,
                        onBeginRecording: onBeginShortcutRecording,
                        onEndRecording: onEndShortcutRecording)
                }
                EditModeShortcutRow(onBeginRecording: onBeginShortcutRecording, onEndRecording: onEndShortcutRecording)
                Picker("録音モード", selection: $settings.recordingMode) {
                    ForEach(RecordingMode.allCases) { Text($0.label).tag($0) }
                }
                Text("日本語で話すと、「英訳して入力」では Gemini が自然な英語に翻訳して入力します（Gemini の認証情報が必要です）。録音中は Esc で取り消せます。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("音声認識") {
                Picker("認識エンジン", selection: $settings.engine) {
                    ForEach(RecognizerEngine.allCases) { Text($0.label).tag($0) }
                }
                TextField("言語", text: $settings.localeIdentifier, prompt: Text("ja-JP"))
                Text("どちらも macOS 内蔵のオンデバイスモデルです。音声は Mac の外に送られません。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("その他") {
                Toggle("開始・終了の効果音を鳴らす", isOn: $settings.playSounds)
            }
        }
        .formStyle(.grouped)
    }
}

private struct GeminiTab: View {
    @ObservedObject var settings: AppSettings
    @State private var apiKey = Keychain.loadAPIKey() ?? ""
    @State private var savedMessage: String?
    @State private var testInput = "えーと明日の会議なんですけど あの資料はジェミニで作ったやつを使いますあ違うグーグルスライドで作ったやつです"
    @State private var testOutput = ""
    @State private var isTesting = false

    var body: some View {
        Form {
            Section {
                Toggle("Gemini で自然な日本語に整える", isOn: $settings.refineWithGemini)
                Toggle("入力先のアプリ名を Gemini に伝える（体裁の参考）", isOn: $settings.sendAppName)
            }
            ScreenContextSettingsSection()
            Section("認証") {
                Picker("認証方法", selection: $settings.authMode) {
                    ForEach(GeminiAuthMode.allCases) { Text($0.label).tag($0) }
                }
                switch settings.authMode {
                case .apiKey:
                    HStack {
                        SecureField("API キー", text: $apiKey)
                        Button("保存") {
                            savedMessage = Keychain.saveAPIKey(apiKey) ? "キーチェーンに保存しました" : "保存に失敗しました"
                        }
                    }
                    if let savedMessage {
                        Text(savedMessage).font(.caption).foregroundStyle(.secondary)
                    }
                    Link("Google AI Studio で API キーを発行", destination: URL(string: "https://aistudio.google.com/apikey")!)
                        .font(.caption)
                case .serviceAccount:
                    HStack {
                        TextField("サービスアカウントの JSON", text: $settings.serviceAccountPath, prompt: Text("~/path/to/key.json"))
                        Button("選択…", action: chooseServiceAccountFile)
                    }
                    TextField("リージョン", text: $settings.vertexLocation, prompt: Text("global"))
                    Text(serviceAccountSummary)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("モデル") {
                HStack {
                    TextField("モデル", text: $settings.model)
                    Menu("候補") {
                        ForEach(AppSettings.suggestedModels, id: \.self) { model in
                            Button(model) { settings.model = model }
                        }
                    }
                    .fixedSize()
                }
                Text("思考レベル: \(GeminiClient.thinkingLevel(for: settings.model))（lite は minimal、それ以外は low）")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("試してみる") {
                TextField("認識結果の例", text: $testInput, axis: .vertical)
                    .lineLimit(2...4)
                HStack {
                    Button(isTesting ? "送信中…" : "整形を試す") { runTest(translate: false) }
                        .disabled(isTesting || testInput.isEmpty)
                    Button("英訳を試す") { runTest(translate: true) }
                        .disabled(isTesting || testInput.isEmpty)
                    Spacer()
                }
                if !testOutput.isEmpty {
                    Text(testOutput).textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var serviceAccountSummary: String {
        let path = settings.serviceAccountPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return "Vertex AI のユーザー権限（roles/aiplatform.user）を持つサービスアカウントの鍵を指定してください。" }
        do {
            let credentials = try ServiceAccountCredentials.load(path: path)
            return "プロジェクト: \(credentials.projectID)　アカウント: \(credentials.clientEmail)"
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

    private func runTest(translate: Bool) {
        isTesting = true
        testOutput = ""
        let request = GeminiClient.Request(
            transcript: settings.userDictionary.apply(to: testInput),
            model: settings.model,
            appName: nil,
            dictionary: settings.dictionaryWords,
            extraInstructions: settings.extraInstructions,
            dictionaryRules: settings.userDictionary.rules)
        if settings.authMode == .apiKey {
            Keychain.saveAPIKey(apiKey)
        }
        Task {
            let started = Date()
            do {
                guard let auth = try GeminiClient.authFromSettings(settings) else { throw GeminiError.missingAPIKey }
                let client = GeminiClient(auth: auth)
                let output = translate ? try await client.translateToEnglish(request) : try await client.refine(request)
                testOutput = output + String(format: "\n\n（%.1f 秒）", Date().timeIntervalSince(started))
            } catch {
                testOutput = "⚠️ " + error.localizedDescription
            }
            isTesting = false
        }
    }
}

private struct WordsTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            DictionaryEditorSection(text: $settings.dictionaryText)
            DictionarySuggestionSection(settings: settings)
            Section {
                TextEditor(text: $settings.extraInstructions)
                    .frame(minHeight: 100)
            } header: {
                Text("追加の整形ルール")
            } footer: {
                Text("例: 「です・ます調に統一する」「英単語は半角で書く」「文末に句点を付けない」")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct MeetingTab: View {
    @ObservedObject var settings: AppSettings
    var onOpenMeetingNotes: () -> Void
    var onBeginShortcutRecording: () -> Void
    var onEndShortcutRecording: () -> Void

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("記録した会議の議事録・文字起こし")
                    Spacer()
                    Button("会議ノートを開く", action: onOpenMeetingNotes)
                }
            }
            Section {
                MeetingDevicePickers(settings: settings)
            } header: {
                Text("録音する機器")
            } footer: {
                Text("「Mac 全体の音」は、どのスピーカー・イヤホンから出ている音も録ります。特定の機器の音だけを録りたいときに選んでください。マイクは、会議ツールで使っているマイクと同じものを選ぶのが確実です。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("会議の記録") {
                LabeledContent("記録の開始／停止") {
                    ShortcutRecorder(
                        combo: $settings.meetingHotKey,
                        defaultCombo: .defaultMeeting,
                        onBeginRecording: onBeginShortcutRecording,
                        onEndRecording: onEndShortcutRecording)
                }
                Toggle(isOn: $settings.diarizeMicChannel) {
                    Text("マイク側も話者を分ける")
                    Text("会議室などで 1 つのマイクを複数人で使うときにオン。いちばん長く話した人を「自分」、ほかを「同席者1」「同席者2」…にします。1 人で参加するときはオフのままにしてください（自分の声が 2 人に分かれることがあります）。")
                }
                Toggle("記録後に Gemini で議事録を作る", isOn: $settings.makeMeetingMinutes)
                HStack {
                    TextField("議事録のモデル", text: $settings.meetingMinutesModel)
                    Menu("候補") {
                        ForEach(AppSettings.suggestedModels, id: \.self) { model in
                            Button(model) { settings.meetingMinutesModel = model }
                        }
                    }
                    .fixedSize()
                }
                Toggle("音声ファイル（me.m4a / others.m4a）を残す", isOn: $settings.keepMeetingAudio)
            }
            MeetingDetectionSettingsSection()
            Section {
                Text("マイクを「自分」、スピーカーの音（Meet・Slack ハドル・Teams など）を「相手」として録ります。スピーカーだと相手の声がマイクにも入るので、イヤホンを使うと正確になります。")
                Text("録音する前に、参加者の了承を得てください。")
                Text("保存先: ~/Documents/Hanasu/Meetings")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct PermissionsTab: View {
    @State private var refresh = 0

    var body: some View {
        Form {
            Section {
                row("マイク", granted: Permissions.microphoneStatus == .authorized, anchor: "Privacy_Microphone")
                row("音声認識", granted: Permissions.speechStatus == .authorized, anchor: "Privacy_SpeechRecognition")
                row("アクセシビリティ（自動入力に必要）",
                    granted: Permissions.isAccessibilityTrusted(prompt: false),
                    anchor: "Privacy_Accessibility")
            } footer: {
                Text("マイクと音声認識は、初めて録音するときに許可を求めます。アクセシビリティはシステム設定で Hanasu をオンにしてください。再ビルドした後に効かなくなった場合は、一覧から Hanasu を削除して追加し直してください。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("再確認") { refresh += 1 }
        }
        .formStyle(.grouped)
        .id(refresh)
    }

    private func row(_ title: String, granted: Bool, anchor: String) -> some View {
        LabeledContent(title) {
            HStack {
                Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(granted ? .green : .secondary)
                Text(granted ? "許可済み" : "未許可")
                if !granted {
                    Button("開く") { Permissions.openPrivacySettings(anchor) }
                }
            }
        }
    }
}
