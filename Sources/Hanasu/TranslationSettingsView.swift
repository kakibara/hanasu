import AppKit
import SwiftUI

// 要件: REQ-DIC-013
// 設計判断: DEC-DIC-027
/// 設定の「一般」タブの「翻訳」の欄。翻訳の言語をそれぞれオン・オフする（最後の 1 つはオフにできない）
struct TranslationSettingsSection: View {
    @Binding var languages: [TranslationLanguage]

    var body: some View {
        Section {
            ForEach(TranslationLanguage.allCases) { language in
                let isOn = languages.contains(language)
                Toggle(isOn: Binding(
                    get: { isOn },
                    set: { on in
                        languages = TranslationLanguage.normalized(on ? languages + [language] : languages.filter { $0 != language })
                    })) {
                    // その言語での言語名と、表示の言語での名前（DEC-DIC-150）
                    Text(language.label)
                    if let subtitle = language.subtitleInUILanguage {
                        Text(subtitle)
                    }
                }
                .disabled(isOn && languages.count == 1)
            }
        } header: {
            Text(tr("翻訳する言語"))
        } footer: {
            Text(tr("「翻訳して入力」のショートカットでは、選んだ言語のうち上のものに翻訳します。録音中の HUD で「話した言語」と選んだ言語を切り替えられます（止めたときに選んでいる言語で入力）。翻訳は AI（設定の「AI」の「音声入力整形」で選んだもの）で行います。少なくとも 1 つは選んでください。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// 確かめ方: REQ-DIC-013
//   Hanasu --render-translation-settings <出力.png> [--languages en,ja]
//     設定の「一般」タブの「翻訳する言語」の欄を画像にする（--languages を付けると、その選び方で描く。設定は変えない）
@MainActor
enum TranslationSettingsCLI {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--render-translation-settings"), args.indices.contains(index + 1) else { return }
        _ = NSApplication.shared
        var languages = AppSettings.shared.translationLanguages
        if let i = args.firstIndex(of: "--languages"), args.indices.contains(i + 1) {
            languages = TranslationLanguage.normalized(args[i + 1].split(separator: ",").compactMap { TranslationLanguage.cliCode(String($0)) })
        }
        // 17 言語のトグル（2 行のものもある）が全部入る高さ
        let size = NSSize(width: 560, height: CGFloat(140 + 60 * TranslationLanguage.allCases.count))
        let view = Form { TranslationSettingsSection(languages: .constant(languages)) }
            .formStyle(.grouped)
            .frame(width: size.width, height: size.height)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)
        if let rep { hosting.cacheDisplay(in: hosting.bounds, to: rep) }
        let url = URL(fileURLWithPath: args[index + 1])
        guard let data = rep?.representation(using: .png, properties: [:]), (try? data.write(to: url)) != nil else {
            FileHandle.standardError.write(Data("error: 画像を書き出せませんでした\n".utf8))
            exit(1)
        }
        print("wrote \(url.path)")
        exit(0)
    }
}
