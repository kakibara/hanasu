import AppKit
import SwiftUI

/// 設定画面の「画面の文脈」の欄。Gemini タブに置く
struct ScreenContextSettingsSection: View {
    @ObservedObject var settings = ScreenContextSettings.shared

    var body: some View {
        Section {
            Toggle(isOn: $settings.enabled) {
                Text("画面の文脈を Gemini に渡す")
                Text("録音を始めたときに、前面のウインドウのタイトルと、入力欄のカーソルの前後の文章（それぞれ最大 \(ScreenContextReader.maxChars) 文字）を読み取ります。固有名詞の表記や書き方、話の流れを合わせるための参考として、話した内容と一緒に Gemini に送ります（英訳でも使います）。パスワード欄と下の除外アプリは読みません。読み取った文章は保存しません。")
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("除外するアプリ（バンドル ID かアプリ名を 1 行に 1 つ）")
                    Spacer()
                    Menu("起動中のアプリから追加") {
                        ForEach(runningApps, id: \.bundleID) { app in
                            Button("\(app.name)（\(app.bundleID)）") { add(app.bundleID) }
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
            Text("画面の文脈")
        } footer: {
            Text("読み取りにはアクセシビリティの許可（自動入力と同じもの）を使います。画面に表示されている他人のメッセージも Gemini に送られることがあるので、社外秘の画面などでは除外に入れるか、オフにしてください。")
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
