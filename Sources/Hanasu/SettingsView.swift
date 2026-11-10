import AVFoundation
import SwiftUI

// 設計判断: DEC-COM-151
/// 設定画面の項目（左のサイドバーに並べる）
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, ai, words, appStyles, snippets, meeting, history, permissions

    var id: Self { self }

    var title: String {
        switch self {
        case .general: tr("一般")
        case .ai: "AI"
        case .words: tr("辞書・ルール")
        case .appStyles: tr("アプリ別")
        case .snippets: tr("スニペット")
        case .meeting: tr("会議")
        case .history: tr("履歴")
        case .permissions: tr("権限")
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
            Section(tr("ショートカット")) {
                LabeledContent(tr("録音の開始／停止")) {
                    ShortcutRecorder(
                        combo: $settings.hotKey,
                        kind: .dictation,
                        onBeginRecording: onBeginShortcutRecording,
                        onEndRecording: onEndShortcutRecording)
                }
                LabeledContent(tr("翻訳して入力")) {
                    ShortcutRecorder(
                        combo: $settings.translateHotKey,
                        defaultCombo: .defaultTranslate,
                        kind: .translate,
                        onBeginRecording: onBeginShortcutRecording,
                        onEndRecording: onEndShortcutRecording)
                }
                EditModeShortcutRow(onBeginRecording: onBeginShortcutRecording, onEndRecording: onEndShortcutRecording)
                Picker(tr("録音モード"), selection: $settings.recordingMode) {
                    ForEach(RecordingMode.allCases) { Text($0.label).tag($0) }
                }
                Text(tr("「翻訳して入力」では、AI（設定の「AI」で音声入力に選んだもの）が、話した内容を下の「翻訳する言語」に翻訳して入力します。録音中は Esc で取り消せます。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            // 要件: REQ-DIC-013
            // 翻訳する言語（TranslationSettingsView.swift）
            TranslationSettingsSection(languages: $settings.translationLanguages)
            // 要件: REQ-DIC-140
            Section {
                DictationMicrophonePicker(settings: settings)
            } header: {
                Text(tr("マイク"))
            } footer: {
                Text(tr("音声入力と「選択を声で編集」で使うマイク。録音中の画面（HUD）のマイクのボタンからも切り替えられます。会議の記録のマイクは「会議」タブで選びます。"))
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
            Section(tr("その他")) {
                Toggle(tr("開始・終了の効果音を鳴らす"), isOn: $settings.playSounds)
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
                Text(tr("追加の整形ルール"))
            } footer: {
                Text(tr("例: 「です・ます調に統一する」「英単語は半角で書く」「文末に句点を付けない」"))
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
                    Text(tr("記録した会議の議事録・文字起こし"))
                    Spacer()
                    Button(tr("会議ノートを開く"), action: onOpenMeetingNotes)
                }
            }
            Section {
                MeetingDevicePickers(settings: settings)
            } header: {
                Text(tr("録音する機器"))
            } footer: {
                Text(tr("「Mac 全体の音」は、どのスピーカー・イヤホンから出ている音も録ります。特定の機器の音だけを録りたいときに選んでください。マイクは、会議ツールで使っているマイクと同じものを選ぶのが確実です。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(tr("会議の記録")) {
                LabeledContent(tr("記録の開始／停止")) {
                    ShortcutRecorder(
                        combo: $settings.meetingHotKey,
                        defaultCombo: .defaultMeeting,
                        kind: .meeting,
                        onBeginRecording: onBeginShortcutRecording,
                        onEndRecording: onEndShortcutRecording)
                }
                Toggle(isOn: $settings.diarizeMicChannel) {
                    Text(tr("マイク側も話者を分ける"))
                    Text(tr("会議室などで 1 つのマイクを複数人で使うときにオン。いちばん長く話した人を「自分」、ほかを「同席者1」「同席者2」…にします。1 人で参加するときはオフのままにしてください（自分の声が 2 人に分かれることがあります）。"))
                }
                // 要件: REQ-DIC-073
                Toggle(isOn: $settings.applyDictionaryToMeetings) {
                    Text(tr("文字起こしに辞書の置き換えルールを当てる"))
                    Text(tr("記録を止めたあとの文字起こしに、「辞書・ルール」の置き換えルールを当てます。議事録は当てたあとの文から作ります。認識したままの文も残すので、会議ノートの「辞書」から戻せます。"))
                }
                Toggle(isOn: $settings.makeMeetingMinutes) {
                    Text(tr("記録後に AI で議事録を作る"))
                    // 要件: REQ-COM-024
                    Text(tr("議事録のモデル: %@ · %@（設定の「AI」で、音声入力とは別に選べます）", "\(settings.aiProvider(for: .meeting).name)", "\(settings.textModel(for: .meeting))"))
                }
                // 要件: REQ-MTG-010, REQ-MTG-056, REQ-MTG-057
                MeetingAudioSettingsRows(settings: settings, fixedEntries: SettingsRenderOverrides.meetingAudioEntries)
            }
            MeetingDetectionSettingsSection()
            MeetingNotesSettingsSection(onBeginShortcutRecording: onBeginShortcutRecording,
                                        onEndShortcutRecording: onEndShortcutRecording)
            Section {
                Text(tr("マイクを「自分」、スピーカーの音（Meet・Slack ハドル・Teams など）を「相手」として録ります。スピーカーだと相手の声がマイクにも入るので、イヤホンを使うと正確になります。"))
                Text(tr("録音する前に、参加者の了承を得てください。"))
                Text(tr("保存先: ~/Documents/Hanasu/Meetings"))
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
                // まだ一度も求めていない（未決定）ときは、システム設定の一覧に Hanasu が載っていないので、
                // オンボーディングと同じく「許可する」でその場で求める。拒否済みのときだけシステム設定を開く。
                row(tr("マイク"), systemImage: "mic.fill",
                    granted: Permissions.microphoneStatus == .authorized,
                    notDetermined: Permissions.microphoneStatus == .notDetermined,
                    deniedHint: tr("システム設定 → プライバシーとセキュリティ → マイク で Hanasu をオンにしてください。"),
                    anchor: "Privacy_Microphone") {
                    _ = await AVCaptureDevice.requestAccess(for: .audio)
                }
                row(tr("音声認識"), systemImage: "waveform",
                    granted: Permissions.speechStatus == .authorized,
                    notDetermined: Permissions.speechStatus == .notDetermined,
                    deniedHint: tr("システム設定 → プライバシーとセキュリティ → 音声認識 で Hanasu をオンにしてください。"),
                    anchor: "Privacy_SpeechRecognition") {
                    _ = try? await Permissions.ensureRecordingPermissions(speechRecognition: true)
                }
                row(tr("アクセシビリティ"), detail: tr("自動入力に必要"), systemImage: "accessibility",
                    granted: Permissions.isAccessibilityTrusted(prompt: false),
                    deniedHint: tr("システム設定 → プライバシーとセキュリティ → アクセシビリティ で Hanasu をオンにしてください。"),
                    anchor: "Privacy_Accessibility")
                // 設計判断: DEC-MTG-074
                // システムオーディオ録音（会議の記録の相手の声）は、許可の状態を取る API がないので、状態は出さずに
                // 「いつ求められるか」と「拒否したときに直す場所」だけを案内する
                LabeledContent {
                    HStack(spacing: 8) {
                        Text(tr("初めて会議の記録を始めるときに macOS が求めます"))
                            .font(.callout).foregroundStyle(.secondary)
                        Button(tr("システム設定を開く")) { Permissions.openPrivacySettings("Privacy_AudioCapture") }
                            .controlSize(.small)
                            .accessibilityLabel(tr("システムオーディオ録音のシステム設定を開く"))
                    }
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tr("システムオーディオ録音"))
                            Text(tr("会議の記録で相手の声に必要")).font(.caption).foregroundStyle(.secondary)
                            Text(tr("拒否した場合は、システム設定 → プライバシーとセキュリティ → 画面収録とシステムオーディオ録音 で Hanasu をオンにしてください。"))
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } icon: {
                        Image(systemName: "speaker.wave.2.fill").foregroundStyle(.secondary)
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(tr("マイクと音声認識は、初めて録音するときに許可を求めます。アクセシビリティはシステム設定で Hanasu をオンにしてください。再ビルドした後に効かなくなった場合は、一覧から Hanasu を削除して追加し直してください。システムオーディオ録音の許可の状態は、macOS から取れないためここには出ません。"))
                        .font(.caption).foregroundStyle(.secondary)
                    Button(tr("再確認"), systemImage: "arrow.clockwise") { refresh += 1 }
                }
            }
        }
        .formStyle(.grouped)
        .id(refresh)
        // システム設定で許可して戻ってきたら、表示を新しくする
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh += 1
        }
    }

    private func row(_ title: String, detail: String? = nil, systemImage: String,
                     granted: Bool, notDetermined: Bool = false, deniedHint: String,
                     anchor: String, request: (() async -> Void)? = nil) -> some View {
        let showHint = !granted && !notDetermined
        let statusText = granted ? tr("許可済み") : notDetermined ? tr("まだ求めていません") : tr("未許可")
        let tint: Color = granted ? .green : .orange
        return LabeledContent {
            HStack(spacing: 8) {
                if !granted {
                    if notDetermined, let request {
                        Button(tr("許可する")) {
                            Task {
                                await request()
                                refresh += 1
                            }
                        }
                        .controlSize(.small)
                        .accessibilityLabel(tr("%@を許可する", "\(title)"))
                    } else {
                        Button(tr("システム設定を開く")) { Permissions.openPrivacySettings(anchor) }
                            .controlSize(.small)
                            .accessibilityLabel(tr("%@のシステム設定を開く", "\(title)"))
                    }
                }
                Label(statusText,
                      systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(tint.opacity(0.12), in: Capsule())
            }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    if let detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                    if showHint {
                        Text(deniedHint)
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
