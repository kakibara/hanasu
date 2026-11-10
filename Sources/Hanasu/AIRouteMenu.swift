import SwiftUI

// 要件: REQ-MTG-047, REQ-MTG-048
// 設計判断: DEC-MTG-095
/// AI チャットと会議に質問の送り先（AI とモデル）の一覧と、使えるかの判定
enum AIRoute {
    /// 使えるかどうか。キーやファイルの中身は読まない（DEC-COM-049）
    struct Availability: Equatable {
        var claude: Bool
        var gemini: Bool
        var downloadedLocalModels: Set<LocalLLMModel>
        /// Apple の fm が使えないときの理由（使えるなら nil）
        var appleFMReason: String?

        /// 選べないときの理由（選べるなら nil）
        func unavailableReason(_ choice: TextAIChoice) -> String? {
            switch choice.provider {
            case .claude: claude ? nil : tr("API キーが未設定")
            case .gemini: gemini ? nil : tr("認証が未設定")
            case .local:
                LocalLLMModel(rawValue: choice.model).map(downloadedLocalModels.contains) == true ? nil : tr("未ダウンロード")
            case .appleFM: appleFMReason == nil ? nil : tr("使えません")
            }
        }
    }

    /// 今の設定と端末で、使えるかを確かめる。Apple の判定は署名を確かめるので、呼ぶ側が 1 回だけ確かめて渡す
    static func availability(settings: AppSettings, appleFMReason: String?) -> Availability {
        let gemini: Bool
        switch settings.authMode {
        case .apiKey:
            gemini = Keychain.exists(.geminiAPIKey)
        case .serviceAccount:
            let path = settings.serviceAccountPath.trimmingCharacters(in: .whitespacesAndNewlines)
            gemini = !path.isEmpty && FileManager.default.fileExists(atPath: (path as NSString).expandingTildeInPath)
        }
        return Availability(
            claude: Keychain.exists(.claudeAPIKey),
            gemini: gemini,
            downloadedLocalModels: Set(LocalLLMModel.allCases.filter(LocalLLMStore.isDownloaded)),
            appleFMReason: appleFMReason)
    }

    /// Apple の fm が使えないときの理由（使えるなら nil）。署名を確かめるので、画面が出たときに 1 回だけ呼ぶ
    static func appleFMReason() -> String? {
        let availability = AppleFMAvailability.check()
        return availability.executableURL == nil ? (availability.reason ?? tr("使えません")) : nil
    }

    struct Section: Identifiable {
        var provider: TextAIProvider
        var choices: [TextAIChoice]
        var id: String { provider.rawValue }
    }

    /// 一覧。AI の並び（DEC-COM-168）でセクションに分ける。Gemini・Claude は、設定に一覧にないモデルがあれば足す
    static func sections(settings: AppSettings) -> [Section] {
        TextAIProvider.allCases.map { provider in
            let models: [String]
            switch provider {
            case .local: models = LocalLLMModel.allCases.map(\.rawValue)
            case .appleFM: models = [AppleFMClient.modelName]
            case .gemini: models = merged(AppSettings.suggestedModels, TextAIPurpose.allCases.map { settings.geminiModel(for: $0) })
            case .claude: models = merged(ClaudeClient.Model.allCases.map(\.rawValue), TextAIPurpose.allCases.map { settings.claudeModel(for: $0) })
            }
            return Section(provider: provider, choices: models.map { TextAIChoice(provider: provider, model: $0) })
        }
    }

    /// 一覧の後ろに、まだないもの（空でないもの）を順に足す
    static func merged(_ base: [String], _ extra: [String]) -> [String] {
        var result = base
        for model in extra where !model.isEmpty && !result.contains(model) { result.append(model) }
        return result
    }

    /// 一覧の 1 行の文字。選べないときは理由を添える（メニューの項目では help が出ないため）
    static func itemTitle(_ choice: TextAIChoice, reason: String?) -> String {
        reason.map { tr("%@（%@）", choice.modelName, $0) } ?? choice.modelName
    }
}

// 要件: REQ-MTG-047, REQ-MTG-048
// 設計判断: DEC-MTG-095
/// 送り先のメニュー。ボタンは「送り先: Claude · Haiku 5.5」。先頭に「既定」、続けて AI ごとのモデル
struct AIRouteMenu: View {
    /// 設定の既定（AI チャット・質問の AI とモデル）
    var defaultChoice: TextAIChoice
    /// 既定から切り替えたもの。nil なら既定
    @Binding var override: TextAIChoice?
    var availability: AIRoute.Availability
    @ObservedObject var settings: AppSettings
    /// 答えを待っている間は切り替えない
    var disabled: Bool

    private var current: TextAIChoice { override ?? defaultChoice }
    private var isOverridden: Bool { override != nil && override != defaultChoice }

    var body: some View {
        Menu {
            Button {
                override = nil
            } label: {
                itemLabel(tr("既定（%@）", defaultChoice.label), selected: !isOverridden)
            }
            ForEach(AIRoute.sections(settings: settings)) { section in
                Section(section.provider.name) {
                    ForEach(section.choices, id: \.self) { choice in
                        let reason = availability.unavailableReason(choice)
                        Button {
                            override = choice == defaultChoice ? nil : choice
                        } label: {
                            itemLabel(AIRoute.itemTitle(choice, reason: reason), selected: isOverridden && choice == current)
                        }
                        .disabled(reason != nil)
                    }
                }
            }
        } label: {
            Label(tr("送り先: %@", current.label),
                  systemImage: isOverridden ? "arrow.triangle.swap" : "sparkles")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(disabled)
        .help(isOverridden
              ? tr("この会話だけ、既定（%@）から変えています", defaultChoice.label)
              : tr("送り先の AI とモデルを、この会話だけ変える"))
    }

    @ViewBuilder private func itemLabel(_ title: String, selected: Bool) -> some View {
        if selected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }
}

// 要件: REQ-COM-025
/// 既定の送り先が使えないときの案内（送る前に出す）
struct AIRouteUnavailableNotice: View {
    var defaultChoice: TextAIChoice
    var reason: String

    var body: some View {
        Label(tr("既定の送り先（%@）は今は使えません（%@）。下の「送り先」で選ぶか、設定の「AI」→「AI チャット・質問」で変えてください。",
                 defaultChoice.label, reason),
              systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }
}
