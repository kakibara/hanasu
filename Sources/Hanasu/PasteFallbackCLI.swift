import AppKit
import SwiftUI

// 入力できる場所がないときの動作確認用の CLI モード:
//   Hanasu --test-paste-target
//     役割と属性の組み合わせごとに、貼る / 表示する / 分からない の判定を確かめる（失敗があれば終了コード 1）
//   Hanasu --probe-paste-target [秒]
//     指定の秒数（既定 3 秒）待ってから、今のフォーカスを読んで判定を表示する（実機で確かめる用。アクセシビリティの許可が要る）
//   Hanasu --render-paste-fallback <出力.png> [--long] [--display-only] [--warning] [--edit]
//     結果を残すパネルを画像にする。--long で長い文章（スクロール）、--display-only で「表示だけにする」のときの案内
//   Hanasu --render-paste-fallback-settings <出力.png>
//     設定の「一般」タブに足した「入力できる場所がないとき」の欄を画像にする
@MainActor
enum PasteFallbackCLI {
    static func runIfRequested() {
        let args = CommandLine.arguments
        if args.contains("--test-paste-target") {
            exit(selfTest() ? 0 : 1)
        }
        if let index = args.firstIndex(of: "--probe-paste-target") {
            let seconds = args.indices.contains(index + 1) ? Double(args[index + 1]) ?? 3 : 3
            probe(after: seconds)
        }
        if let index = args.firstIndex(of: "--render-paste-fallback"), args.indices.contains(index + 1) {
            renderPanel(to: URL(fileURLWithPath: args[index + 1]), args: args)
        }
        if let index = args.firstIndex(of: "--render-paste-fallback-settings"), args.indices.contains(index + 1) {
            renderSettings(to: URL(fileURLWithPath: args[index + 1]))
        }
    }

    // MARK: --test-paste-target

    // 確かめ方: REQ-DIC-080
    /// 判定の表。名前・フォーカスの様子・期待する判定
    static let cases: [(String, PasteFocusSnapshot, PasteTargetDecision)] = [
        ("テキストエディットの本文", .init(bundleID: "com.apple.TextEdit", role: "AXTextArea", valueSettable: true, hasSelectedTextRange: true), .paste),
        ("Safari のアドレス欄", .init(bundleID: "com.apple.Safari", role: "AXTextField", valueSettable: true, hasSelectedTextRange: true), .paste),
        ("検索欄（サブロール）", .init(bundleID: "com.apple.mail", role: "AXTextField", subrole: "AXSearchField"), .paste),
        ("検索欄（ロール）", .init(bundleID: "com.example.app", role: "AXSearchField"), .paste),
        ("コンボボックス", .init(bundleID: "com.example.app", role: "AXComboBox"), .paste),
        ("パスワード欄", .init(bundleID: "com.apple.Safari", role: "AXTextField", subrole: "AXSecureTextField"), .paste),
        ("ターミナル（書き換えられない AXTextArea）", .init(bundleID: "com.apple.Terminal", role: "AXTextArea", hasSelectedTextRange: true), .paste),
        ("Chrome の contenteditable（AXGroup・編集できる領域の中）", .init(bundleID: "com.google.Chrome", role: "AXGroup", hasEditableAncestor: true), .paste),
        ("Web 全体が編集できる（designMode）", .init(bundleID: "com.google.Chrome", role: "AXWebArea", hasEditableAncestor: true), .paste),
        ("自前で描く編集欄（AXGroup・選択範囲あり）", .init(bundleID: "com.example.editor", role: "AXGroup", hasSelectedTextRange: true), .paste),
        ("選べるラベル（AXStaticText・選択範囲あり）は貼ってみる", .init(bundleID: "com.example.app", role: "AXStaticText", hasSelectedTextRange: true), .paste),
        ("Finder のファイルの一覧", .init(bundleID: "com.apple.finder", role: "AXOutline"), .show),
        ("Finder のデスクトップ（要素なし）", .init(bundleID: "com.apple.finder", window: .none, element: .none), .show),
        ("Finder のデスクトップ（ウインドウはある）", .init(bundleID: "com.apple.finder", element: .none), .show),
        ("Finder の名前の変更", .init(bundleID: "com.apple.finder", role: "AXTextField", valueSettable: true), .paste),
        ("Finder の検索欄", .init(bundleID: "com.apple.finder", role: "AXTextField", subrole: "AXSearchField"), .paste),
        ("Safari のページ（入力欄の外）", .init(bundleID: "com.apple.Safari", role: "AXWebArea"), .show),
        ("Chrome のリンク", .init(bundleID: "com.google.Chrome", role: "AXLink"), .show),
        ("ボタン", .init(bundleID: "com.apple.systempreferences", role: "AXButton"), .show),
        ("書き換えられるスライダーも入力欄ではない", .init(bundleID: "com.apple.systempreferences", role: "AXSlider", valueSettable: true), .show),
        ("チェックボックス", .init(bundleID: "com.example.app", role: "AXCheckBox", valueSettable: true), .show),
        ("ラベル（選択範囲なし）", .init(bundleID: "com.example.app", role: "AXStaticText"), .show),
        ("画像", .init(bundleID: "com.apple.Preview", role: "AXImage"), .show),
        ("ウインドウがないアプリ", .init(bundleID: "com.apple.Safari", window: .none, element: .none), .show),
        ("Slack（Electron）のメッセージ一覧", .init(bundleID: "com.tinyspeck.slackmacgap", isElectron: true, role: "AXWebArea"), .unknown),
        ("Electron のボタン", .init(bundleID: "com.microsoft.VSCode", isElectron: true, role: "AXButton"), .unknown),
        ("Electron の要素なし（AX を出していない）", .init(bundleID: "com.tinyspeck.slackmacgap", isElectron: true, element: .none), .unknown),
        ("Electron の入力欄", .init(bundleID: "com.tinyspeck.slackmacgap", isElectron: true, role: "AXTextArea"), .paste),
        ("Electron でもウインドウがない", .init(bundleID: "com.tinyspeck.slackmacgap", isElectron: true, window: .none, element: .none), .show),
        ("ウインドウはあるが要素がない（自前で描くターミナルなど）", .init(bundleID: "net.kovidgoyal.kitty", element: .none), .unknown),
        ("AXWindow にフォーカス", .init(bundleID: "org.alacritty", role: "AXWindow"), .unknown),
        ("AXGroup（中身が分からない）", .init(bundleID: "com.example.canvas", role: "AXGroup"), .unknown),
        ("Excel の表（選んだまま貼れる）", .init(bundleID: "com.microsoft.Excel", role: "AXTable"), .unknown),
        ("Keynote の画面（AXLayoutArea）", .init(bundleID: "com.apple.iWork.Keynote", role: "AXLayoutArea"), .unknown),
        ("Mail の一覧（AXTable）", .init(bundleID: "com.apple.mail", role: "AXTable"), .unknown),
        ("要素を読めなかった（タイムアウトなど）", .init(bundleID: "com.example.app", element: .failed), .unknown),
        ("Finder でも読めなかったときは分からない", .init(bundleID: "com.apple.finder", element: .failed), .unknown),
        ("ウインドウを読めず、要素もない", .init(bundleID: "com.example.app", window: .failed, element: .none), .unknown),
        ("フォーカスのあるアプリが分からない", .init(hasApp: false, window: .failed, element: .failed), .unknown),
    ]

    static func selfTest() -> Bool {
        var failures = 0
        for (name, snapshot, expected) in cases {
            let (decision, reason) = PasteTargetJudge.decide(snapshot)
            let ok = decision == expected
            if !ok { failures += 1 }
            print("\(ok ? "OK  " : "NG  ") \(label(decision))\(ok ? "" : "（期待: \(label(expected))）")  \(name) — \(reason)")
        }
        print(failures == 0 ? "\n\(cases.count) 件すべて合格" : "\n\(failures) / \(cases.count) 件が不合格")
        return failures == 0
    }

    private static func label(_ decision: PasteTargetDecision) -> String {
        switch decision {
        case .paste: "貼る      "
        case .show: "表示する  "
        case .unknown: "分からない"
        }
    }

    // MARK: --probe-paste-target

    private static func probe(after seconds: Double) -> Never {
        _ = NSApplication.shared
        print(String(format: "%.0f 秒後にフォーカスを読みます。確かめたいアプリ・場所をクリックしてください…", seconds))
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        guard AXIsProcessTrusted() else {
            print("アクセシビリティの許可がありません（このコマンドを動かしているアプリに許可が要ります）")
            exit(1)
        }
        Task { @MainActor in
            let result = await PasteTargetProbe.check()
            let s = result.snapshot
            print("""
            アプリ: \(s.bundleID ?? "-")\(s.isElectron ? "（Electron）" : "")
            ウインドウ: \(s.window.rawValue)  要素: \(s.element.rawValue)
            役割: \([s.role, s.subrole].compactMap { $0 }.joined(separator: "/"))
            AXValue を書き換えられる: \(s.valueSettable)  選択範囲: \(s.hasSelectedTextRange)  編集できる領域の中: \(s.hasEditableAncestor)
            判定: \(label(result.decision).trimmingCharacters(in: .whitespaces)) — \(result.reason)
            """)
            exit(0)
        }
        RunLoop.main.run()
        exit(0)
    }

    // MARK: --render-paste-fallback

    // 確かめ方: REQ-DIC-080
    private static func renderPanel(to url: URL, args: [String]) -> Never {
        _ = NSApplication.shared
        let short = "明日の会議なんですけど、資料は Google スライドで作ったものを使います。"
        let long = (1...12).map { "\($0). 来週の定例では、先月の振り返りと今月の計画を話します。資料は前日までに共有フォルダに置いてください。" }
            .joined(separator: "\n")
        let panel = PasteFallbackPanel.shared
        panel.show(
            text: args.contains("--long") ? long : short,
            subject: args.contains("--edit") ? .edit : .result,
            clipboardKept: !args.contains("--display-only"),
            warning: args.contains("--warning") ? "Gemini の応答が 15 秒以内に返りませんでした。整形前の文章を入力しました。" : nil,
            headless: true)
        write(panel.snapshotPNG(), to: url)
    }

    // MARK: --render-paste-fallback-settings

    // 確かめ方: REQ-DIC-081
    private static func renderSettings(to url: URL) -> Never {
        _ = NSApplication.shared
        let view = Form { PasteFallbackSettingsSection() }
            .formStyle(.grouped)
            .frame(width: 560, height: 220)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 560, height: 220)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)
        if let rep { hosting.cacheDisplay(in: hosting.bounds, to: rep) }
        write(rep?.representation(using: .png, properties: [:]), to: url)
    }

    private static func write(_ data: Data?, to url: URL) -> Never {
        guard let data, (try? data.write(to: url)) != nil else {
            FileHandle.standardError.write(Data("error: 画像を書き出せませんでした\n".utf8))
            exit(1)
        }
        print("wrote \(url.path)")
        exit(0)
    }
}
