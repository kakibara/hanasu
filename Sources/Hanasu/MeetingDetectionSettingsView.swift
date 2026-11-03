import SwiftUI

/// 設定の「会議」タブに置く、会議の自動検出の欄
struct MeetingDetectionSettingsSection: View {
    @ObservedObject var settings = MeetingDetectionSettings.shared

    var body: some View {
        Section {
            Toggle(isOn: $settings.enabled) {
                Text("会議が始まったら記録を提案する")
                Text("会議アプリがマイクを使い始めたら「会議を記録しますか？」と画面の右上に出します。自動では記録を始めません。")
            }
            if settings.enabled {
                LabeledContent("会議アプリ") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(MeetingApp.allCases.filter { !$0.isBrowser }) { toggle(for: $0) }
                    }
                    .frame(width: 180, alignment: .leading)
                }
                LabeledContent("ブラウザ") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(MeetingApp.allCases.filter(\.isBrowser)) { toggle(for: $0) }
                    }
                    .frame(width: 180, alignment: .leading)
                }
            }
        } header: {
            Text("会議の自動検出")
        } footer: {
            Text("ブラウザは Google Meet かどうかまでは分からないので、マイクを使い始めたら「ブラウザの会議かもしれない」として提案します。記録中に会議アプリがマイクを止めたら「記録を止めますか？」と聞きます。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func toggle(for app: MeetingApp) -> some View {
        Toggle(app.label, isOn: Binding(
            get: { settings.isEnabled(app) },
            set: { settings.setEnabled(app, $0) }))
            .toggleStyle(.checkbox)
    }
}
