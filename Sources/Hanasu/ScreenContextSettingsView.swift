import AppKit
import SwiftUI

/// 設定画面の「画面の文脈」の欄。AI タブに置く
struct ScreenContextSettingsSection: View {
    @ObservedObject var settings = ScreenContextSettings.shared

    var body: some View {
        Section {
            Toggle(isOn: $settings.enabled) {
                Text(tr("画面の文脈を AI に渡す"))
                Text(tr("録音を始めたときに、前面のウインドウのタイトルと、入力欄のカーソルの前後の文章（それぞれ最大 %@ 文字）を読み取ります。固有名詞の表記や書き方、話の流れを合わせるための参考として、話した内容と一緒に AI（Gemini か Claude）に送ります（翻訳でも使います）。パスワード欄と下の除外アプリは読みません。読み取った文章は保存しません。", "\(ScreenContextReader.maxChars)"))
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
            }
            .disabled(!settings.enabled)
        } header: {
            Text(tr("画面の文脈"))
        } footer: {
            Text(tr("読み取りにはアクセシビリティの許可（自動入力と同じもの）を使います。画面に表示されている他人のメッセージも AI に送られることがあるので、社外秘の画面などでは除外に入れるか、オフにしてください。"))
                .font(.caption).foregroundStyle(.secondary)
        }
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
