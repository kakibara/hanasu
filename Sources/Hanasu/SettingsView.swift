import AVFoundation
import SwiftUI

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
            // 要件: REQ-COM-020, REQ-COM-024
            AISettingsTab(settings: settings)
                .tabItem { Label("AI", systemImage: "sparkles") }
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
                LabeledContent("翻訳して入力") {
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
                Text("「翻訳して入力」では、AI（「AI」タブで音声入力に選んだもの）が、話した内容を下の「翻訳する言語」に翻訳して入力します。録音中は Esc で取り消せます。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            // 要件: REQ-DIC-013
            // 翻訳する言語（TranslationSettingsView.swift）
            TranslationSettingsSection(languages: $settings.translationLanguages)
            // 要件: REQ-DIC-140
            Section {
                DictationMicrophonePicker(settings: settings)
            } header: {
                Text("マイク")
            } footer: {
                Text("音声入力と「選択を声で編集」で使うマイク。録音中の画面（HUD）のマイクのボタンからも切り替えられます。会議の記録のマイクは「会議」タブで選びます。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            // 音声入力と会議の記録の文字起こしのエンジン（TranscriptionEngineSettingsView.swift）
            TranscriptionEngineSettingsSection(settings: settings)
            // 入力できる場所がないときのクリップボードの扱い（PasteFallbackPanel.swift）
            PasteFallbackSettingsSection()
            // 要件: REQ-COM-040
            // アイコンを出す場所（メニューバー / Dock / 両方。AppPresence.swift）
            AppPresenceSettingsSection()
            Section("その他") {
                Toggle("開始・終了の効果音を鳴らす", isOn: $settings.playSounds)
            }
        }
        .formStyle(.grouped)
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
                Toggle(isOn: $settings.makeMeetingMinutes) {
                    Text("記録後に AI で議事録を作る")
                    // 要件: REQ-COM-024
                    Text("議事録のモデル: \(settings.aiProvider(for: .meeting).name) · \(settings.textModel(for: .meeting))（「AI」タブで、音声入力とは別に選べます）")
                }
                Toggle("音声ファイル（me.m4a / others.m4a）を残す", isOn: $settings.keepMeetingAudio)
            }
            MeetingDetectionSettingsSection()
            MeetingNotesSettingsSection(onBeginShortcutRecording: onBeginShortcutRecording,
                                        onEndShortcutRecording: onEndShortcutRecording)
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
