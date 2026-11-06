import AppKit
import Foundation

// MARK: - 確認用の CLI

/// アップデートの確認用の CLI モード（main.swift から呼ぶ）:
///   Hanasu --update-selftest
///       版の比べ方・リリースの情報の読み方・スキップの扱い・ホストの制限を、例のデータで確かめる（通信しない）
///   Hanasu --check-update [--current <版>]
///       GitHub に問い合わせ、最新の版・zip・SHA-256 と、知らせるかを出す（ダウンロードはしない）
///   Hanasu --verify-update <Hanasu-<版>-macOS.zip> --version <版>
///       zip を展開し、入れ替えの前と同じ確認（署名・証明書・bundle ID・版）をする。Hanasu.app の中の実行ファイルで動かす
///   Hanasu --preview-update-dialog [<リリース文の .md>]
///       新しい版を尋ねるダイアログを、そのリリース文で出す（通信もダウンロードもしない。選んだボタンを出して終わる）
// 確かめ方: REQ-REL-010, REQ-REL-011
@MainActor
enum AppUpdateCLI {
    static func runIfRequested() {
        let args = CommandLine.arguments
        if args.contains("--update-selftest") { exit(selfTest() ? 0 : 1) }
        if args.contains("--check-update") {
            let current = value(after: "--current", in: args).flatMap(AppVersion.init) ?? AppVersion.current
            run {
                guard let release = try await UpdateHTTP.fetchLatestRelease() else {
                    print("最新のリリースがありません（下書き・プレリリース）")
                    return
                }
                print("最新: \(release.tag)（\(release.pageURL.absoluteString)）")
                if let asset = release.asset {
                    print("zip: \(asset.name) \(asset.size) バイト sha256 \(asset.sha256)")
                    print("     \(asset.url.absoluteString)")
                } else {
                    print("zip: なし（リリースのページを開くだけにする）")
                }
                if let current {
                    let launch = UpdateSettings.shared.shouldOffer(release, current: current, manual: false)
                    let manual = UpdateSettings.shared.shouldOffer(release, current: current, manual: true)
                    print("今の版: \(current)。起動時に知らせる: \(launch ? "はい" : "いいえ")、メニューから: \(manual ? "はい" : "いいえ（最新です）")")
                } else {
                    print("今の版: 不明（--current <版> で指定できます）")
                }
                print("リリース文:\n\(release.notes)")
            }
        }
        if args.contains("--preview-update-dialog") {
            let path = value(after: "--preview-update-dialog", in: args).flatMap { $0.hasPrefix("--") ? nil : $0 }
            let notes = path.flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }
                ?? "## ハイライト\n\n**太字**と`コード`と[リンク](https://github.com/kakibara/hanasu)。\n\n## 改善\n\n- 1 つめ\n- 2 つめ。長い行は、印の幅だけ字下げして折り返します。長い行は、印の幅だけ字下げして折り返します。\n  - 入れ子\n1. 番号付き"
            NSApplication.shared.setActivationPolicy(.accessory)
            let release = UpdateRelease(version: AppVersion("99.0.0")!, tag: "v99.0.0",
                                        pageURL: URL(string: "https://github.com/kakibara/hanasu/releases")!,
                                        notes: UpdateRelease.releaseNotes(from: notes), asset: nil)
            run {
                let choice = await AppUpdater.presentAsk(release, current: AppVersion.current ?? AppVersion("2.0.0")!)
                print("選んだもの: \(choice)")
            }
        }
        if let zip = value(after: "--verify-update", in: args) {
            guard let version = value(after: "--version", in: args).flatMap(AppVersion.init) else {
                print("--version <版> を付けてください")
                exit(1)
            }
            var work: URL?
            var ok = false
            do {
                let directory = try UpdateInstaller.makeWorkDirectory()
                work = directory
                let app = try UpdateInstaller.extract(URL(fileURLWithPath: zip), into: directory)
                try UpdateSignature.verify(newApp: app, current: Bundle.main.bundleURL, expectedVersion: version)
                print("ok: \(app.lastPathComponent) は今の Hanasu と同じ証明書で署名されていて、版は \(version) です")
                ok = true
            } catch {
                print("ng: \(error.localizedDescription)")
            }
            if let work { try? FileManager.default.removeItem(at: work) }
            exit(ok ? 0 : 1)
        }
    }

    private static func run(_ body: @escaping @MainActor () async throws -> Void) -> Never {
        Task { @MainActor in
            do {
                try await body()
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
                exit(1)
            }
        }
        RunLoop.main.run()
        exit(0)
    }

    private static func value(after flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }

    static func selfTest() -> Bool {
        var failures = 0
        func expect(_ ok: Bool, _ label: String) {
            print("\(ok ? "ok" : "NG"): \(label)")
            if !ok { failures += 1 }
        }
        func v(_ text: String) -> AppVersion { AppVersion(text)! }

        // 版
        expect(v("1.10.0") > v("1.9.0"), "1.10.0 は 1.9.0 より新しい")
        expect(v("v1.6.0") == v("1.6"), "v1.6.0 と 1.6 は同じ")
        expect(v("2.0.0") > v("1.99.99"), "2.0.0 は 1.99.99 より新しい")
        expect(!(v("1.6.0") > v("1.6.0")), "同じ版は新しくない")
        expect(v("1.7").description == "1.7.0" && v("v2").description == "2.0.0" && v("1.10.0").description == "1.10.0",
               "版は 3 つの数字で出す")
        expect(AppVersion("1.6.0-beta") == nil && AppVersion("") == nil && AppVersion("1..0") == nil, "形の違う版は読まない")

        // リリースの情報
        let sampleSHA = String(repeating: "ab", count: 32)
        func json(tag: String, draft: Bool = false, prerelease: Bool = false, assetName: String? = nil,
                  digest: String? = "sha256:" + String(repeating: "ab", count: 32), host: String = "github.com") -> Data {
            let name = assetName ?? "Hanasu-\(tag.dropFirst())-macOS.zip"
            let digestField = digest.map { "\"digest\": \"\($0)\"," } ?? ""
            return Data("""
                {"tag_name": "\(tag)", "html_url": "https://github.com/kakibara/hanasu/releases/tag/\(tag)",
                 "draft": \(draft), "prerelease": \(prerelease),
                 "body": "<!-- release-notes -->\\n## ハイライト\\n\\n新しい版\\n<!-- /release-notes -->\\n\\n## What's Changed\\n\\n## インストール\\n",
                 "assets": [
                   {"name": "Hanasu-\(tag.dropFirst())-Windows-x64.zip", "browser_download_url": "https://github.com/x.zip", "size": 1, "digest": "sha256:\(sampleSHA)"},
                   {"name": "\(name)", "browser_download_url": "https://\(host)/kakibara/hanasu/releases/download/\(tag)/\(name)",
                    \(digestField) "size": 18484710}
                 ]}
                """.utf8)
        }
        /// 読んだ結果: エラーなら "error"、知らせないなら "nil"、読めたらそのリリース
        func parsed(_ data: Data) -> (outcome: String, release: UpdateRelease?) {
            do {
                guard let release = try UpdateRelease.parse(data) else { return ("nil", nil) }
                return ("release", release)
            } catch {
                return ("error", nil)
            }
        }
        let release = parsed(json(tag: "v1.7.0")).release
        expect(release?.version == v("1.7.0"), "tag_name から版を読む")
        expect(release?.asset?.name == "Hanasu-1.7.0-macOS.zip" && release?.asset?.sha256 == sampleSHA
               && release?.asset?.size == 18484710, "Mac 版の zip と SHA-256 を選ぶ")
        expect(release?.notes == "## ハイライト\n\n新しい版", "リリース文だけを取る")
        expect(parsed(json(tag: "v1.7.0", draft: true)).outcome == "nil", "下書きは知らせない")
        expect(parsed(json(tag: "v1.7.0", prerelease: true)).outcome == "nil", "プレリリースは知らせない")
        let noDigest = parsed(json(tag: "v1.7.0", digest: nil))
        expect(noDigest.outcome == "release" && noDigest.release?.asset == nil, "SHA-256 がなければ入れ替えない（ページを開く）")
        expect(parsed(json(tag: "v1.7.0", digest: "sha256:xyz")).release?.asset == nil, "形の違う SHA-256 は使わない")
        expect(parsed(json(tag: "v1.7.0", host: "example.com")).release?.asset == nil, "GitHub 以外の zip は使わない")
        expect(parsed(Data("{}".utf8)).outcome == "error", "形の違う応答はエラー")
        expect(UpdateRelease.releaseNotes(from: "## What's Changed\n- a\n\n## インストール\n- b") == "## What's Changed\n- a",
               "印がなければ「## インストール」の前まで")

        // リリース文の整形（DEC-REL-027）
        let formatted = ReleaseNotesFormatter.attributed("<!-- release-notes -->\n## 改善\n\n- **太字**の項目\n1. 番号\n\nふつうの文")
        expect(formatted.string == "改善\n•\t太字の項目\n1.\t番号\nふつうの文", "見出し・箇条書きの印を外し、太字の記号を出さない")
        let boldFont = formatted.attribute(.font, at: (formatted.string as NSString).range(of: "太字").location, effectiveRange: nil) as? NSFont
        expect(boldFont?.fontDescriptor.symbolicTraits.contains(.bold) == true, "太字は太い字で出す")
        let headingFont = formatted.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        expect(headingFont.map { $0.pointSize > ReleaseNotesFormatter.bodySize } == true, "見出しは大きい字で出す")
        let linked = ReleaseNotesFormatter.attributed("[ページ](https://github.com/kakibara/hanasu)")
        expect(linked.string == "ページ" && linked.attribute(.link, at: 0, effectiveRange: nil) != nil, "リンクは押せる文字で出す")

        // 知らせるか
        if let release {
            expect(UpdateSettings.shouldOffer(release, current: v("1.6.0"), skipped: "", manual: false), "新しい版は起動時に知らせる")
            expect(!UpdateSettings.shouldOffer(release, current: v("1.6.0"), skipped: "1.7.0", manual: false), "スキップした版は起動時に知らせない")
            expect(UpdateSettings.shouldOffer(release, current: v("1.6.0"), skipped: "1.7.0", manual: true), "メニューからはスキップした版も知らせる")
            expect(UpdateSettings.shouldOffer(release, current: v("1.6.0"), skipped: "1.6.5", manual: false), "前にスキップした版より新しければ知らせる")
            expect(!UpdateSettings.shouldOffer(release, current: v("1.7.0"), skipped: "", manual: true), "同じ版なら知らせない")
        } else {
            expect(false, "例のリリースを読めない")
        }

        // ホスト
        expect(UpdateHTTP.isAllowed(URL(string: "https://release-assets.githubusercontent.com/x")!), "GitHub の CDN には従う")
        expect(!UpdateHTTP.isAllowed(URL(string: "http://github.com/x")!), "http には従わない")
        expect(!UpdateHTTP.isAllowed(URL(string: "https://github.com.example.com/x")!), "似た名前のホストには従わない")
        expect(!UpdateHTTP.isAllowed(URL(string: "https://evilgithubusercontent.com/x")!), "githubusercontent.com で終わるだけのホストには従わない")

        // 入れ替えのスクリプトは、パスを引数で受け取る（文に埋め込まない）
        expect(UpdateInstaller.swapScript.contains("result=\"$5\"") && UpdateInstaller.swapScript.contains("if [ -e \"$target\" ]") && UpdateInstaller.swapScript.contains("target=\"$2\"") && !UpdateInstaller.swapScript.contains("/Applications"),
               "スクリプトは引数でパスを受け取る")

        print(failures == 0 ? "すべて通りました" : "\(failures) 件の失敗")
        return failures == 0
    }
}
