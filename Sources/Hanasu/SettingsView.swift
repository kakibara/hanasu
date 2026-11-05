import AVFoundation
import SwiftUI

// 設計判断: DEC-COM-151
/// 設定画面の項目（左のサイドバーに並べる）
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, ai, words, appStyles, snippets, meeting, history, permissions

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "一般"
        case .ai: "AI"
        case .words: "辞書・ルール"
        case .appStyles: "アプリ別"
        case .snippets: "スニペット"
        case .meeting: "会議"
        case .history: "履歴"
        case .permissions: "権限"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape.fill"
        case .ai: "sparkles"
        case .words: "character.book.closed.fill"
        case .appStyles: "square.grid.2x2.fill"
        case .snippets: "text.badge.plus"
        case .meeting: "person.2.wave.2.fill"
        case .history: "clock.arrow.circlepath"
        case .permissions: "lock.shield.fill"
        }
    }

    /// サイドバーのアイコンの下地の色（システム設定と同じく、項目ごとに色を分けて見分けやすくする）
    var tint: Color {
        switch self {
        case .general: .gray
        case .ai: .purple
        case .words: .orange
        case .appStyles: .blue
        case .snippets: .teal
        case .meeting: .green
        case .history: .indigo
        case .permissions: .red
        }
    }
}

/// 角の丸い色付きの下地に白い記号を載せたアイコン（システム設定のサイドバーと同じ形）
struct SettingsPaneIcon: View {
    let pane: SettingsPane
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: pane.systemImage)
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(pane.tint.gradient, in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
    }
}

// 設計判断: DEC-COM-151
struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    var onOpenMeetingNotes: () -> Void
    var onBeginShortcutRecording: () -> Void
    var onEndShortcutRecording: () -> Void
    var onOpenHistory: () -> Void = {}
    var onCheckForUpdates: () -> Void = {}
    /// 最初に開く項目（確認用の描き出しで使う。nil なら前に開いていた項目）
    var initialPane: SettingsPane? = nil

    /// 選んでいる項目。前に開いていた項目を次に開いたときも出す
    @AppStorage("settingsPane") private var storedPane: SettingsPane = .general
    @State private var selection: SettingsPane?

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selection) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    SettingsPaneIcon(pane: pane)
                }
                .padding(.vertical, 2)
                .tag(pane)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            let pane = selection ?? initialPane ?? storedPane
            VStack(spacing: 0) {
                header(for: pane)
                Divider()
                content(for: pane)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 700, minHeight: 480)
        .onAppear { if selection == nil { selection = initialPane ?? storedPane } }
        .onChange(of: selection) { _, newValue in
            if let newValue, initialPane == nil { storedPane = newValue }
        }
    }

    /// 右側の上に出す、項目の名前
    private func header(for pane: SettingsPane) -> some View {
        HStack(spacing: 10) {
            SettingsPaneIcon(pane: pane, size: 28)
            Text(pane.title)
                .font(.title2.weight(.semibold))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func content(for pane: SettingsPane) -> some View {
        switch pane {
        case .general:
            GeneralTab(
                settings: settings,
                onBeginShortcutRecording: onBeginShortcutRecording,
                onEndShortcutRecording: onEndShortcutRecording,
                onCheckForUpdates: onCheckForUpdates)
        case .ai:
            // 要件: REQ-COM-020, REQ-COM-024
            AISettingsTab(settings: settings)
        case .words:
            WordsTab(settings: settings)
        case .appStyles:
            AppStylesTab()
        case .snippets:
            SnippetsSettingsView()
        case .meeting:
            MeetingTab(
                settings: settings,
                onOpenMeetingNotes: onOpenMeetingNotes,
                onBeginShortcutRecording: onBeginShortcutRecording,
                onEndShortcutRecording: onEndShortcutRecording)
        case .history:
            HistorySettingsTab(
                onOpenHistory: onOpenHistory,
                onBeginShortcutRecording: onBeginShortcutRecording,
                onEndShortcutRecording: onEndShortcutRecording)
        case .permissions:
            PermissionsTab()
        }
    }
}

private struct GeneralTab: View {
    @ObservedObject var settings: AppSettings
    var onBeginShortcutRecording: () -> Void
    var onEndShortcutRecording: () -> Void
    var onCheckForUpdates: () -> Void

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
            PasteUnconfirmedSettingsSection()
            // 要件: REQ-COM-040
            // アイコンを出す場所（メニューバー / Dock / 両方。AppPresence.swift）
            AppPresenceSettingsSection()
            Section("その他") {
                Toggle("開始・終了の効果音を鳴らす", isOn: $settings.playSounds)
            }
            // 要件: REQ-REL-010, REQ-REL-011
            // 起動時の確認と「今すぐ確認」（AppUpdate.swift）
            UpdateSettingsSection(onCheckNow: onCheckForUpdates)
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
                row("マイク", systemImage: "mic.fill",
                    granted: Permissions.microphoneStatus == .authorized, anchor: "Privacy_Microphone")
                row("音声認識", systemImage: "waveform",
                    granted: Permissions.speechStatus == .authorized, anchor: "Privacy_SpeechRecognition")
                row("アクセシビリティ", detail: "自動入力に必要", systemImage: "accessibility",
                    granted: Permissions.isAccessibilityTrusted(prompt: false),
                    anchor: "Privacy_Accessibility")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("マイクと音声認識は、初めて録音するときに許可を求めます。アクセシビリティはシステム設定で Hanasu をオンにしてください。再ビルドした後に効かなくなった場合は、一覧から Hanasu を削除して追加し直してください。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("再確認", systemImage: "arrow.clockwise") { refresh += 1 }
                }
            }
        }
        .formStyle(.grouped)
        .id(refresh)
    }

    private func row(_ title: String, detail: String? = nil, systemImage: String,
                     granted: Bool, anchor: String) -> some View {
        LabeledContent {
            HStack(spacing: 8) {
                if !granted {
                    Button("システム設定を開く") { Permissions.openPrivacySettings(anchor) }
                        .controlSize(.small)
                }
                Label(granted ? "許可済み" : "未許可",
                      systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(granted ? Color.green : Color.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((granted ? Color.green : Color.orange).opacity(0.12), in: Capsule())
            }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    if let detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
