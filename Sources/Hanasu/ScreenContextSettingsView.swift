import AppKit
import SwiftUI

// 要件: REQ-DIC-040, REQ-DIC-042
// 設計判断: DEC-DIC-068, DEC-DIC-180, DEC-DIC-189
/// 設定画面の「画面の文脈」の欄。AI タブに置く。
/// AX で読む画面の文脈と、スクリーンショットの文字の 2 つのトグルを並べ、除外アプリは共有する。
/// オンなのに許可がないときは、読み取れないことをトグルの下で知らせる（黙って空の文脈にならないように）
struct ScreenContextSettingsSection: View {
    @ObservedObject var settings = ScreenContextSettings.shared
    @State private var accessibilityTrusted = Permissions.isAccessibilityTrusted(prompt: false)
    @State private var screenRecordingGranted = ScreenRecordingPermission.isGranted
    /// 確認用の CLI で、許可がない見た目を描くとき
    var previewScreenRecordingDenied = false

    var body: some View {
        Section {
            Toggle(isOn: $settings.enabled) {
                Text(tr("画面の文脈を AI に渡す"))
                Text(tr("録音を始めたときに、前面のウインドウのタイトルと、入力欄のカーソルの前後の文章（それぞれ最大 %@ 文字）を読み取ります。固有名詞の表記や書き方、話の流れを合わせるための参考として、話した内容と一緒に AI（設定の「AI」の「音声入力整形」で選んだもの）に渡します（翻訳でも使います）。パスワード欄と下の除外アプリは読みません。読み取った文章は保存しません。", "\(ScreenContextReader.maxChars)"))
            }
            if settings.enabled && !accessibilityTrusted {
                HStack(alignment: .firstTextBaseline) {
                    Label(tr("アクセシビリティがまだ許可されていないので、画面の文脈は読み取れません（音声入力そのものは使えます）。"),
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(tr("許可する…")) {
                        // 未許可なら macOS のダイアログが出る。出ないとき（以前に拒否した）はシステム設定を開く
                        if !Permissions.isAccessibilityTrusted(prompt: true) {
                            Permissions.openPrivacySettings("Privacy_Accessibility")
                        }
                        refreshTrust()
                    }
                    .accessibilityLabel(tr("アクセシビリティを許可する"))
                }
            }
            // 要件: REQ-DIC-041, REQ-DIC-042
            // 設計判断: DEC-DIC-180, DEC-DIC-182, DEC-DIC-187
            Toggle(isOn: $settings.useScreenshot) {
                Text(tr("スクリーンショットの文字も AI に渡す"))
                Text(tr("録音を始めたときに、つないでいるすべての画面を撮り、写っている文字をこの Mac の中で読み取ります（画像は送らず、保存もしません）。画面に出ている固有名詞や型番の表記に合わせるための参考として、読み取った文字だけを AI に渡します（翻訳でも使います）。録音中の画面に出るボタンで、その録音だけ切り替えられます。Hanasu・除外アプリ・通知・認証のダイアログは写しません。ブラウザの中のパスワードの候補やプライベートウインドウ、ほかの画面のターミナルなどは写ることがあります。整形をオフにしているときは、翻訳するときだけ使います。Apple の Foundation Models では、読み取った文字が動いている数秒の間ほかのユーザーからも見えるコマンドの引数に入ります。"))
            }
            if settings.useScreenshot && !screenRecordingAllowed {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(tr("画面収録がまだ許可されていないので、スクリーンショットは撮れません（音声入力そのものは使えます）。"),
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(settings.meetingInProgress
                             ? tr("会議の記録が終わってから許可してください（許可のあと macOS が Hanasu を開き直すことがあり、記録が途中で切れるため）。")
                             : tr("許可したあとで効かないときは、Hanasu を終了して開き直してください。"))
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button(tr("許可する…")) {
                        // 未許可なら macOS のダイアログが出る。出ないとき（以前に拒否した）はシステム設定を開く
                        if !ScreenRecordingPermission.request() {
                            Permissions.openPrivacySettings("Privacy_ScreenCapture")
                        }
                        refreshTrust()
                    }
                    .disabled(settings.meetingInProgress)
                    .accessibilityLabel(tr("画面収録を許可する"))
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(tr("除外するアプリ（バンドル ID かアプリ名を 1 行に 1 つ）"))
                    Spacer()
                    Menu(tr("起動中のアプリから追加")) {
                        ForEach(runningApps, id: \.bundleID) { app in
                            Button(tr("%@（%@）", app.name, app.bundleID)) { add(app.bundleID) }
                        }
                    }
                    .fixedSize()
                }
                TextEditor(text: $settings.excludedAppsText)
                    .font(.body.monospaced())
                    .frame(minHeight: 80)
                // 要件: REQ-DIC-042, REQ-DIC-075
                // 設計判断: DEC-DIC-180（欄はいつでも編集でき、画面から辞書の候補を探すときにも効く）
                Text(tr("ここにあるアプリは、画面の文脈・スクリーンショットのほか、メニューの「画面から辞書の候補を探す…」でも読みません。"))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text(tr("画面の文脈"))
        } footer: {
            Text(tr("画面の文脈の読み取りにはアクセシビリティの許可（自動入力と同じもの）を、スクリーンショットには画面収録の許可を使います。画面に表示されている他人のメッセージも AI に送られることがあるので、社外秘の画面などでは除外に入れるか、オフにしてください。"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: settings.enabled) { _, _ in refreshTrust() }
        .onChange(of: settings.useScreenshot) { _, on in
            // 設計判断: DEC-DIC-189
            // オンにしたとき、許可がなければ macOS のダイアログで求める（会議の記録中は求めない。録音中も求めない）
            if on, !ScreenRecordingPermission.isGranted, !settings.meetingInProgress, !settings.dictationInProgress,
               !previewScreenRecordingDenied {
                ScreenRecordingPermission.request()
            }
            refreshTrust()
        }
        // システム設定で許可して戻ってきたら、表示を新しくする（権限タブと同じ）
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshTrust()
        }
    }

    private var screenRecordingAllowed: Bool { screenRecordingGranted && !previewScreenRecordingDenied }

    private func refreshTrust() {
        accessibilityTrusted = Permissions.isAccessibilityTrusted(prompt: false)
        screenRecordingGranted = ScreenRecordingPermission.isGranted
    }

    /// 起動中の通常のアプリ（Dock に出るもの）。自分は除く
    private var runningApps: [(name: String, bundleID: String)] {
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            .compactMap { app in app.bundleIdentifier.map { (app.localizedName ?? $0, $0) } }
            .filter { seen.insert($0.1).inserted }
            .sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
    }

    private func add(_ bundleID: String) {
        guard !settings.isExcluded(bundleID: bundleID, appName: nil) else { return }
        let text = settings.excludedAppsText
        settings.excludedAppsText = text + (text.isEmpty || text.hasSuffix("\n") ? "" : "\n") + bundleID
    }
}
