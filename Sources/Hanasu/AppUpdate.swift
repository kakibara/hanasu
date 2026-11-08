import AppKit
import CryptoKit
import Foundation
import Security
import SwiftUI

// MARK: - 版の比べ方

// 設計判断: DEC-REL-020
/// 「1.6.0」「v1.6.0」「1.6」の形の版。数字の部分ごとに比べる（1.10.0 は 1.9.0 より新しい）
struct AppVersion: Comparable, CustomStringConvertible {
    /// 比べるための数字（末尾の 0 を除いたもの）
    let components: [Int]
    /// 出すための形（少なくとも 3 つの数字。「1.7」は「1.7.0」、「v2」は「2.0.0」）
    let description: String

    init?(_ text: String) {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") { trimmed.removeFirst() }
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 4 else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isASCII), part.allSatisfy(\.isNumber), let number = Int(part) else { return nil }
            numbers.append(number)
        }
        var shown = numbers
        while shown.count < 3 { shown.append(0) }
        description = shown.map(String.init).joined(separator: ".")
        // 末尾の 0 を除いて比べる（1.6 と 1.6.0 を同じにする）
        while numbers.count > 1, numbers.last == 0 { numbers.removeLast() }
        components = numbers
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool { lhs.components == rhs.components }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let a = index < lhs.components.count ? lhs.components[index] : 0
            let b = index < rhs.components.count ? rhs.components[index] : 0
            if a != b { return a < b }
        }
        return false
    }

    /// 動いている Hanasu の版（Info.plist の CFBundleShortVersionString。build-app.sh が VERSION から書く）
    static var current: AppVersion? {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(AppVersion.init)
    }
}

// MARK: - リリースの情報

// 設計判断: DEC-REL-020, DEC-REL-021
/// GitHub の releases/latest の応答から、使う所だけを読む
struct UpdateRelease: Equatable {
    let version: AppVersion
    let tag: String
    let pageURL: URL
    /// リリース文（`<!-- release-notes -->` の中。なければ「## インストール」の前まで）
    let notes: String
    /// この Mac に入れる zip（ないか、SHA-256 が分からなければ nil。そのときはリリースのページを開くだけにする）
    let asset: Asset?

    struct Asset: Equatable {
        let name: String
        let url: URL
        let size: Int64
        /// 小文字の 16 進
        let sha256: String
    }

    static func == (lhs: UpdateRelease, rhs: UpdateRelease) -> Bool { lhs.tag == rhs.tag && lhs.asset == rhs.asset }

    enum ParseError: LocalizedError {
        case invalid(String)
        var errorDescription: String? {
            switch self {
            case .invalid(let reason): tr("リリースの情報を読めませんでした（%@）", "\(reason)")
            }
        }
    }

    private struct Response: Decodable {
        let tag_name: String
        let html_url: String
        let draft: Bool?
        let prerelease: Bool?
        let body: String?
        let assets: [AssetResponse]?
    }

    private struct AssetResponse: Decodable {
        let name: String
        let browser_download_url: String
        let size: Int64?
        let digest: String?
    }

    /// Mac 版の zip の名前（REQ-REL-003）
    static func macAssetName(for version: String) -> String { "Hanasu-\(version)-macOS.zip" }

    /// 下書き・プレリリースは nil（releases/latest は元から返さないが、念のため見る）
    static func parse(_ data: Data) throws -> UpdateRelease? {
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw ParseError.invalid(tr("JSON の形が違います"))
        }
        if response.draft == true || response.prerelease == true { return nil }
        guard let version = AppVersion(response.tag_name) else { throw ParseError.invalid(tr("版の形が違います: %@", "\(response.tag_name)")) }
        guard let page = URL(string: response.html_url), UpdateHTTP.isAllowed(page) else {
            throw ParseError.invalid(tr("リリースのページが GitHub ではありません"))
        }
        let versionText = response.tag_name.hasPrefix("v") || response.tag_name.hasPrefix("V")
            ? String(response.tag_name.dropFirst()) : response.tag_name
        let name = macAssetName(for: versionText)
        var asset: Asset?
        if let found = response.assets?.first(where: { $0.name == name }),
           let url = URL(string: found.browser_download_url), UpdateHTTP.isAllowed(url),
           let size = found.size, size > 0,
           let sha = sha256(fromDigest: found.digest)
        {
            asset = Asset(name: name, url: url, size: size, sha256: sha)
        }
        return UpdateRelease(version: version, tag: response.tag_name, pageURL: page,
                             notes: releaseNotes(from: response.body ?? ""), asset: asset)
    }

    /// GitHub の digest（"sha256:<64 桁の 16 進>"）から、SHA-256 を取る
    static func sha256(fromDigest digest: String?) -> String? {
        guard let digest, digest.lowercased().hasPrefix("sha256:") else { return nil }
        let hex = digest.dropFirst("sha256:".count).lowercased()
        guard hex.count == 64, hex.allSatisfy({ $0.isHexDigit }) else { return nil }
        return String(hex)
    }

    /// 本文から、使う人向けのリリース文だけを取る（PR の一覧とインストールの手順は出さない）
    static func releaseNotes(from body: String) -> String {
        let start = "<!-- release-notes -->", end = "<!-- /release-notes -->"
        var text = body
        if let s = body.range(of: start) {
            text = String(body[s.upperBound...])
            if let e = text.range(of: end) { text = String(text[..<e.lowerBound]) }
        } else if let install = body.range(of: "## インストール") {
            text = String(body[..<install.lowerBound])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum Platform { case mac, windows }

    /// ダイアログに出す節（リリース文の書き方 docs/releases/TEMPLATE.md の見出し）
    static let appSections: Set<String> = ["ハイライト", "新しい機能", "改善", "不具合の修正"] // skip-tr（リリース文の見出しを探す語）

    // 設計判断: DEC-REL-027
    /// リリース文を、ダイアログに出す分（アプリの機能の節と、その OS の項目）に絞る。
    /// 4 つの見出しがどれもなければ、絞らずに返す
    static func appNotes(from notes: String, platform: Platform = .mac) -> String {
        let lines = notes.components(separatedBy: "\n")
        func sectionTitle(_ line: String) -> String? {
            guard let match = line.firstMatch(of: #/^##(?!#)\s+(.*?)\s*$/#) else { return nil }
            return String(match.1)
        }
        guard lines.contains(where: { sectionTitle($0).map(appSections.contains) == true }) else { return notes }

        // 節ごとに分ける（最初の見出しより前は、見出しのない節として出す）
        var sections: [(title: String?, body: [String])] = [(nil, [])]
        for line in lines {
            if let title = sectionTitle(line) {
                sections.append((title, []))
            } else {
                sections[sections.count - 1].body.append(line)
            }
        }

        var output: [String] = []
        for section in sections {
            if let title = section.title, !appSections.contains(title) { continue }
            var kept: [String] = []
            // 出さない行の字下げ（その下の一段深い行も出さない）
            var droppedIndent: Int?
            for line in section.body {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let indent = line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
                if trimmed.isEmpty {
                    kept.append("")
                    continue
                }
                if let dropped = droppedIndent {
                    if indent > dropped { continue }
                    droppedIndent = nil
                }
                guard let tag = line.firstMatch(of: #/\s*[（(]\s*(Mac|Windows)(?:\s*/\s*(Mac|Windows))?\s*[）)]\s*([。.]?)\s*$/#) else {
                    kept.append(line)
                    continue
                }
                let platforms = [tag.1, tag.2].compactMap { $0 }.map(String.init)
                let mine = platform == .mac ? "Mac" : "Windows"
                if platforms.contains(mine) {
                    // 印は外し、文の終わりの「。」は残す
                    kept.append(String(line[..<tag.range.lowerBound]) + tag.3)
                } else {
                    droppedIndent = indent
                }
            }
            guard kept.contains(where: { !$0.isEmpty }) else { continue }
            if let title = section.title { output.append("## \(title)") }
            output.append(contentsOf: kept)
        }
        return output.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// 設計判断: DEC-REL-027
/// リリース文（Markdown）を、ダイアログの欄に出す形にする。
/// 使うのは、リリース文の書き方（docs/releases/TEMPLATE.md）に出てくるもの: 見出し・箇条書き・番号付きの箇条書き・太字・斜体・コード・リンク。
/// 表やコードのブロックは使わないので、そのまま 1 行ずつ出す
enum ReleaseNotesFormatter {
    static let bodySize: CGFloat = 12

    static func attributed(_ markdown: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var previousWasBlank = true
        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            // HTML のコメント（release-notes の印など）は出さない
            if line.hasPrefix("<!--") && line.hasSuffix("-->") { continue }
            if line.isEmpty {
                previousWasBlank = true
                continue
            }
            let block = Block(rawLine)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 2
            paragraph.paragraphSpacingBefore = result.length == 0 ? 0 : block.spacingBefore(afterBlank: previousWasBlank)
            let piece = NSMutableAttributedString()
            if let marker = block.marker {
                // 印のあとを、印の幅だけ字下げして折り返す。印は行の中の Markdown の解釈に通さない（"1." が読み替えられないように）
                let indent = CGFloat(block.level) * 14
                let markerWidth: CGFloat = 16
                paragraph.firstLineHeadIndent = indent
                paragraph.headIndent = indent + markerWidth
                paragraph.tabStops = [NSTextTab(textAlignment: .left, location: indent + markerWidth)]
                piece.append(NSAttributedString(string: "\(marker)\t", attributes: [
                    .font: NSFont.systemFont(ofSize: bodySize), .foregroundColor: NSColor.secondaryLabelColor,
                ]))
            }
            piece.append(inline(block.text, font: block.font))
            piece.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: piece.length))
            if result.length > 0 { result.append(NSAttributedString(string: "\n")) }
            result.append(piece)
            previousWasBlank = false
        }
        return result
    }

    /// 1 行の種類
    struct Block {
        enum Kind { case heading(Int), bullet, numbered(String), paragraph }
        let kind: Kind
        let text: String
        let level: Int

        /// line は行頭の空白を残したもの（字下げの深さを数える。空白 2 つかタブ 1 つで 1 段）
        init(_ line: String) {
            let indent = line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
            level = indent / 2
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let match = trimmed.firstMatch(of: #/^(#{1,6})\s+(.*)$/#) {
                kind = .heading(match.1.count)
                text = String(match.2)
            } else if let match = trimmed.firstMatch(of: #/^[-*+]\s+(.*)$/#) {
                kind = .bullet
                text = String(match.1)
            } else if let match = trimmed.firstMatch(of: #/^(\d+)[.)]\s+(.*)$/#) {
                kind = .numbered(String(match.1))
                text = String(match.2)
            } else {
                kind = .paragraph
                text = trimmed
            }
        }

        var marker: String? {
            switch kind {
            case .bullet: "•"
            case .numbered(let number): "\(number)."
            default: nil
            }
        }

        var font: NSFont {
            switch kind {
            case .heading(1): .boldSystemFont(ofSize: ReleaseNotesFormatter.bodySize + 4)
            case .heading(2): .boldSystemFont(ofSize: ReleaseNotesFormatter.bodySize + 2)
            case .heading: .boldSystemFont(ofSize: ReleaseNotesFormatter.bodySize)
            default: .systemFont(ofSize: ReleaseNotesFormatter.bodySize)
            }
        }

        func spacingBefore(afterBlank: Bool) -> CGFloat {
            switch kind {
            case .heading: 12
            case .bullet, .numbered: afterBlank ? 6 : 3
            case .paragraph: afterBlank ? 6 : 0
            }
        }
    }

    /// 行の中の Markdown（太字・斜体・コード・リンク）を、字の形にする
    static func inline(_ text: String, font: NSFont) -> NSAttributedString {
        let parsed = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
        let result = NSMutableAttributedString()
        for run in parsed.runs {
            let piece = String(parsed[run.range].characters)
            var runFont = font
            var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.labelColor]
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.stronglyEmphasized) {
                runFont = NSFontManager.shared.convert(runFont, toHaveTrait: .boldFontMask)
            }
            if intent.contains(.emphasized) {
                runFont = NSFontManager.shared.convert(runFont, toHaveTrait: .italicFontMask)
            }
            if intent.contains(.code) {
                runFont = .monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular)
            }
            // 押して開くのは http / https だけ（ほかは字だけ出す）
            if let link = run.link, let scheme = link.scheme?.lowercased(), scheme == "https" || scheme == "http" {
                attributes[.link] = link
            }
            attributes[.font] = runFont
            result.append(NSAttributedString(string: piece, attributes: attributes))
        }
        return result
    }
}

// MARK: - 通信

// 設計判断: DEC-REL-021
/// アップデートの確認とダウンロードに使う通信。API のキーは送らないが、https と GitHub のホストだけにする。
/// zip は github.com から GitHub の CDN（*.githubusercontent.com）へ転送されるので、その転送だけに従う
enum UpdateHTTP {
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/kakibara/hanasu/releases/latest")!

    static func isAllowed(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return host == "github.com" || host == "api.github.com" || host.hasSuffix(".githubusercontent.com")
    }

    enum Failure: LocalizedError {
        case disallowed(String)
        case status(Int)
        case sizeMismatch(expected: Int64, actual: Int64)
        case hashMismatch

        var errorDescription: String? {
            switch self {
            case .disallowed(let host): tr("GitHub 以外の場所（%@）からは取りません", "\(host)")
            case .status(403), .status(429): tr("GitHub に何度も問い合わせたため、しばらく確かめられません（少し時間をおいてください）")
            case .status(let code): tr("GitHub から取れませんでした（HTTP %@）", "\(code)")
            case .sizeMismatch(let expected, let actual): tr("ダウンロードした大きさが違います（%@ バイト、想定は %@ バイト）", "\(actual)", "\(expected)")
            case .hashMismatch: tr("ダウンロードしたファイルの SHA-256 がリリースの値と違うので、使いません")
            }
        }
    }

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration, delegate: RedirectGuard(), delegateQueue: nil)
    }()

    static func makeRequest(_ url: URL, accept: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("Hanasu/\(AppVersion.current?.description ?? "dev")", forHTTPHeaderField: "User-Agent")
        return request
    }

    /// 最新のリリース（下書き・プレリリースなら nil）
    static func fetchLatestRelease() async throws -> UpdateRelease? {
        var request = makeRequest(latestReleaseURL, accept: "application/vnd.github+json")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        try check(response)
        return try UpdateRelease.parse(data)
    }

    /// zip を directory に落とし、大きさと SHA-256 を確かめる
    static func download(_ asset: UpdateRelease.Asset, into directory: URL) async throws -> URL {
        guard isAllowed(asset.url) else { throw Failure.disallowed(asset.url.host ?? "") }
        var request = makeRequest(asset.url, accept: "application/octet-stream")
        request.timeoutInterval = 60
        let (temporary, response) = try await session.download(for: request)
        let destination = directory.appendingPathComponent(asset.name)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
        try check(response)
        let size = (try FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? -1
        guard size == asset.size else { throw Failure.sizeMismatch(expected: asset.size, actual: size) }
        guard try LocalLLMStore.sha256(of: destination) == asset.sha256 else { throw Failure.hashMismatch }
        return destination
    }

    private static func check(_ response: URLResponse) throws {
        if let url = response.url, !isAllowed(url) { throw Failure.disallowed(url.host ?? "") }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw Failure.status(http.statusCode) }
    }

    /// 転送は https の GitHub のホストへだけ従う
    private final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? {
            guard let url = request.url, UpdateHTTP.isAllowed(url) else { return nil }
            return request
        }
    }
}

// MARK: - 設定

// 設計判断: DEC-COM-013, DEC-REL-022, DEC-REL-024
final class UpdateSettings: ObservableObject {
    static let shared = UpdateSettings()

    private let defaults = UserDefaults.standard
    private static let checkKey = "checkForUpdatesOnLaunch"
    private static let skippedKey = "skippedUpdateVersion"

    /// 起動時にアップデートを確かめる（既定はオン）
    @Published var checkOnLaunch: Bool { didSet { defaults.set(checkOnLaunch, forKey: Self.checkKey) } }
    /// 「この版をスキップ」を選んだ版（起動時の確認では、この版を知らせない）
    @Published var skippedVersion: String { didSet { defaults.set(skippedVersion, forKey: Self.skippedKey) } }

    private init() {
        defaults.register(defaults: [Self.checkKey: true])
        checkOnLaunch = defaults.bool(forKey: Self.checkKey)
        skippedVersion = defaults.string(forKey: Self.skippedKey) ?? ""
    }

    // 設計判断: DEC-REL-022
    /// 知らせるか。起動時の確認はスキップした版を知らせない。メニューからの確認はスキップを見ない
    static func shouldOffer(_ release: UpdateRelease, current: AppVersion, skipped: String, manual: Bool) -> Bool {
        guard release.version > current else { return false }
        if manual { return true }
        return AppVersion(skipped) != release.version
    }
}

// MARK: - 署名と入れ替え

// 設計判断: DEC-REL-025
/// 新しい Hanasu.app が、今の Hanasu.app と同じ証明書で署名されているかを確かめる（REQ-REL-002 の「Hanasu Release Signing」）。
/// 自己署名なので Apple の公証には頼れない。同じ証明書でなければ入れ替えない（入れ替えると許可も外れる）
enum UpdateSignature {
    enum Failure: LocalizedError {
        case unsignedCurrent
        case invalid(String)
        case differentCertificate

        var errorDescription: String? {
            switch self {
            case .unsignedCurrent: tr("今の Hanasu が配布用の証明書で署名されていない（手元でビルドしたものなど）ので、自動では入れ替えません")
            case .invalid(let reason): tr("新しい Hanasu の署名を確かめられませんでした（%@）", "\(reason)")
            case .differentCertificate: tr("新しい Hanasu が、今の Hanasu と違う証明書で署名されているので、入れ替えません")
            }
        }
    }

    /// 署名の葉の証明書（アドホック署名なら nil）
    static func leafCertificate(of app: URL) -> Data? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, SecCSFlags(), &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any],
              let certificates = dictionary[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certificates.first
        else { return nil }
        return SecCertificateCopyData(leaf) as Data
    }

    /// 署名が壊れていないか（中のファイル・入れ子のコードまで）
    static func validate(_ app: URL) throws {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, SecCSFlags(), &code) == errSecSuccess, let code else {
            throw Failure.invalid(tr("読み込めません"))
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        let status = SecStaticCodeCheckValidity(code, flags, nil)
        guard status == errSecSuccess else { throw Failure.invalid("OSStatus \(status)") }
    }

    /// 新しい .app を確かめる: 署名が正しい・今と同じ証明書・同じ bundle ID・リリースの版
    static func verify(newApp: URL, current: URL, expectedVersion: AppVersion) throws {
        guard let currentLeaf = leafCertificate(of: current) else { throw Failure.unsignedCurrent }
        try validate(newApp)
        guard leafCertificate(of: newApp) == currentLeaf else { throw Failure.differentCertificate }
        guard let bundle = Bundle(url: newApp),
              bundle.bundleIdentifier == Bundle(url: current)?.bundleIdentifier
        else { throw Failure.invalid(tr("アプリの ID が違います")) }
        guard let text = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              AppVersion(text) == expectedVersion
        else { throw Failure.invalid(tr("版がリリースと違います")) }
    }
}

// 設計判断: DEC-REL-026
/// Hanasu.app の入れ替え。Hanasu が終わるのを待つ小さなシェルスクリプトを動かしてから、Hanasu を終える。
/// スクリプトは、今の .app を作業フォルダへ退け、新しい .app を同じ場所に移し、失敗したら戻して、開き直す
enum UpdateInstaller {
    enum Failure: LocalizedError {
        case notAnApp
        case translocated
        case notWritable(String)
        case missingApp
        case extractFailed(Int32)

        var errorDescription: String? {
            switch self {
            case .notAnApp: tr("Hanasu.app として動いていないので、入れ替えられません")
            case .translocated: tr("Hanasu が「ダウンロード」などから直接開かれているので、入れ替えられません。Hanasu.app を「アプリケーション」フォルダに移してから開き直してください")
            case .notWritable(let path): tr("%@ に書き込めないので、入れ替えられません", "\(path)")
            case .missingApp: tr("ダウンロードした zip に Hanasu.app がありません")
            case .extractFailed(let status): tr("ダウンロードした zip を展開できませんでした（ditto %@）", "\(status)")
            }
        }
    }

    /// 入れ替えられる場所で動いているか（できないなら、ダウンロードの前に理由を返す）
    static func checkInstallLocation(_ app: URL = Bundle.main.bundleURL) throws {
        guard app.pathExtension == "app" else { throw Failure.notAnApp }
        // 隔離の属性が付いたまま開くと、OS が読み取り専用の別の場所（App Translocation）から動かす
        if app.path.contains("/AppTranslocation/") { throw Failure.translocated }
        let parent = app.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path),
              FileManager.default.isWritableFile(atPath: app.path)
        else { throw Failure.notWritable(parent.path) }
        // 証明書のない（手元でビルドした）Hanasu は、ダウンロードしても verify で断るので、先に断る
        guard UpdateSignature.leafCertificate(of: app) != nil else { throw UpdateSignature.Failure.unsignedCurrent }
    }

    // 設計判断: DEC-REL-026
    /// 入れ替えを始めた印（入れ替える版とリリースのページ）と、スクリプトが失敗の理由を書くファイル。
    /// 次の起動で、版が上がっていなければ知らせる（スクリプトの失敗は、Hanasu が終わったあとなので画面に出せない）
    static var pendingFile: URL { stateDirectory.appendingPathComponent("update-pending") }
    static var resultFile: URL { stateDirectory.appendingPathComponent("update-result") }
    private static var stateDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent(Bundle.main.bundleIdentifier ?? "dev.mactypeless.Hanasu", isDirectory: true)
    }

    static func recordPending(_ release: UpdateRelease) throws {
        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: resultFile)
        try "\(release.version)\n\(release.pageURL.absoluteString)\n".write(to: pendingFile, atomically: true, encoding: .utf8)
    }

    /// 前の起動で始めた入れ替えの結果を読み、印を消す。版が上がっていなければ（入れ替える版, ページ, 理由）
    static func takeFailedAttempt(current: AppVersion?) -> (version: String, page: URL?, reason: String)? {
        // 版の分からない起動（swift build の実行ファイル）では、アプリの印を読まない
        guard let current, let text = try? String(contentsOf: pendingFile, encoding: .utf8) else { return nil }
        let reason = (try? String(contentsOf: resultFile, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        try? FileManager.default.removeItem(at: pendingFile)
        try? FileManager.default.removeItem(at: resultFile)
        let lines = text.split(separator: "\n").map(String.init)
        guard let first = lines.first, let expected = AppVersion(first) else { return nil }
        if current >= expected { return nil }
        return (expected.description, lines.count > 1 ? URL(string: lines[1]) : nil, reason)
    }

    /// 入れ替えのための作業フォルダ（入れ替える .app と同じボリュームに作る。mv がコピーにならないように）
    static func makeWorkDirectory(for app: URL = Bundle.main.bundleURL) throws -> URL {
        try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: app, create: true)
    }

    /// zip を展開し、中の Hanasu.app を返す
    static func extract(_ zip: URL, into directory: URL) throws -> URL {
        let destination = directory.appendingPathComponent("extracted", isDirectory: true)
        try? FileManager.default.removeItem(at: destination)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zip.path, destination.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure.extractFailed(process.terminationStatus) }
        let app = destination.appendingPathComponent("Hanasu.app", isDirectory: true)
        guard FileManager.default.fileExists(atPath: app.path) else { throw Failure.missingApp }
        return app
    }

    /// スクリプトの中身は固定で、パスと失敗の理由の文（表示の言語）は引数で渡す（スクリプトの文に埋め込まない）。
    /// 中の日本語はスクリプトのコメントだけで、利用者には出ない
    static let swapScript = """
        #!/bin/sh
        # Hanasu のアップデート: Hanasu が終わるのを待ってから、.app を入れ替えて開き直す
        # 引数: <待つ PID> <入れ替える .app> <新しい .app> <作業フォルダ> <失敗の理由を書くファイル>
        #       <終わらなかったときの文> <前の .app を残したときの文（このあとに場所を付ける）>
        pid="$1"; target="$2"; new="$3"; work="$4"; result="$5"; timeout_message="$6"; kept_message="$7"
        i=0
        while kill -0 "$pid" 2>/dev/null; do
          i=$((i + 1))
          if [ "$i" -gt 600 ]; then
            echo "$timeout_message" > "$result"
            rm -rf "$work"
            exit 1
          fi
          sleep 0.1
        done
        backup="$work/Hanasu-previous.app"
        if mv "$target" "$backup" 2>> "$result"; then
          if ! mv "$new" "$target" 2>> "$result"; then
            mv "$backup" "$target" 2>> "$result"
          fi
        fi
        if [ -e "$target" ]; then
          open "$target"
          rm -rf "$work"
        else
          # 元に戻すこともできなかった。前の Hanasu.app を消さずに残し、場所を書いておく
          echo "$kept_message $backup" >> "$result"
        fi
        """

    /// スクリプトを動かす（このあと Hanasu を終える）
    static func launchSwap(newApp: URL, workDirectory: URL, target: URL = Bundle.main.bundleURL) throws {
        let script = workDirectory.appendingPathComponent("swap.sh")
        try swapScript.write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), target.path, newApp.path, workDirectory.path,
                             resultFile.path,
                             tr("Hanasu が 60 秒たっても終わらなかったので、入れ替えませんでした"),
                             tr("前の Hanasu.app は次の場所に残っています:")]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}

// MARK: - 確認の流れ

// 要件: REQ-REL-010, REQ-REL-011
/// 起動時とメニューからのアップデートの確認。見つかったら尋ね、「アップデート」を選んだときだけダウンロードして入れ替える
@MainActor
final class AppUpdater {
    /// 録音中・会議の記録中・処理中なら true（AppDelegate が渡す）
    var isBusy: () -> Bool = { false }
    /// GitHub に問い合わせている間
    private var isFetching = false
    /// 尋ねている・入れ替えている間（ダイアログを 2 つ出さない）
    private var isPrompting = false
    /// この起動で尋ねた版（起動時の確認が録音の終わりを待つ間に、メニューから尋ねた版をもう一度尋ねない）
    private var offeredTags: Set<String> = []
    private var progressWindow: NSWindow?

    // 設計判断: DEC-REL-026
    /// 前の起動で始めた入れ替えが済んでいなければ、理由を出してリリースのページを案内する（起動のたびに呼ぶ）
    func reportPreviousAttempt() {
        guard let failed = UpdateInstaller.takeFailedAttempt(current: AppVersion.current) else { return }
        appLog.error("update: previous attempt to \(failed.version, privacy: .public) failed: \(failed.reason, privacy: .public)")
        isPrompting = true
        Task {
            // 知らせている間は、起動時の確認のダイアログを重ねない
            defer { isPrompting = false }
            try? await Task.sleep(for: .seconds(1))
            let alert = NSAlert()
            alert.messageText = tr("Hanasu %@ へのアップデートができませんでした", "\(failed.version)")
            alert.informativeText = (failed.reason.isEmpty ? "" : "\(failed.reason)\n\n")
                + tr("Hanasu.app を入れ替えられませんでした（macOS がアプリの書き換えを止めたときなど）。リリースのページから zip をダウンロードして、手で入れ替えてください。")
            alert.addButton(withTitle: tr("リリースのページを開く"))
            alert.addButton(withTitle: tr("閉じる"))
            if await Self.runModal(alert) == .alertFirstButtonReturn {
                NSWorkspace.shared.open(failed.page ?? URL(string: "https://github.com/kakibara/hanasu/releases/latest")!)
            }
        }
    }

    // 要件: REQ-REL-010
    // 設計判断: DEC-REL-024
    /// 起動時の確認。設定で切れる。失敗しても知らせない（ログだけ）
    func checkOnLaunch() {
        guard UpdateSettings.shared.checkOnLaunch, AppVersion.current != nil else { return }
        Task {
            // 起動の直後に設定画面などと重ならないよう、少し待つ
            try? await Task.sleep(for: .seconds(5))
            await check(manual: false)
        }
    }

    // 要件: REQ-REL-011
    // 設計判断: DEC-REL-022
    /// メニューからの確認。結果（最新・失敗）も知らせる
    func checkManually() {
        Task { await check(manual: true) }
    }

    private func check(manual: Bool) async {
        if isFetching || isPrompting {
            if manual { await alert(tr("アップデートを確かめています"), tr("いま確かめているか、アップデートの確認を出しているところです。")) }
            return
        }
        guard let current = AppVersion.current else {
            if manual { await alert(tr("今の版が分かりません"), tr("Hanasu.app として動いていないため、アップデートを確かめられません。")) }
            return
        }
        let release: UpdateRelease?
        isFetching = true
        do {
            release = try await UpdateHTTP.fetchLatestRelease()
            isFetching = false
        } catch {
            isFetching = false
            appLog.notice("update check failed: \(error.localizedDescription, privacy: .public)")
            if manual { await alert(tr("アップデートを確かめられませんでした"), error.localizedDescription) }
            return
        }
        guard let release,
              UpdateSettings.shared.shouldOffer(release, current: current, manual: manual)
        else {
            appLog.notice("update check: up to date (\(current.description, privacy: .public))")
            if manual { await alert(tr("Hanasu は最新です"), tr("今の版（%@）が最新です。", "\(current)")) }
            return
        }
        appLog.notice("update available: \(release.tag, privacy: .public)")
        // 設計判断: DEC-REL-023
        // 起動時の確認は、録音・記録が終わるまで尋ねるのを待つ
        if !manual {
            while isBusy() { try? await Task.sleep(for: .seconds(10)) }
            // メニューからの確認の知らせ（「確かめています」など）を出している間は、閉じるまで待つ
            // （ダイアログを出している間も画面は動くので、ここで止めると、この起動ではもう知らせなくなる）
            while isPrompting, !offeredTags.contains(release.tag) { try? await Task.sleep(for: .seconds(1)) }
            // 待つ間にメニューから確かめて尋ねた版は、もう尋ねない
            guard !isFetching, !isPrompting, !offeredTags.contains(release.tag) else { return }
        } else if isPrompting {
            // 問い合わせている間に、起動時の確認が尋ね始めていた
            return
        }
        offeredTags.insert(release.tag)
        isPrompting = true
        defer { isPrompting = false }
        switch await ask(release, current: current) {
        case .update: await install(release)
        case .later: break
        case .skip: UpdateSettings.shared.skippedVersion = release.version.description
        }
    }

    enum Choice { case update, later, skip }

    // 設計判断: DEC-REL-022
    private func ask(_ release: UpdateRelease, current: AppVersion) async -> Choice {
        await Self.presentAsk(release, current: current)
    }

    /// 尋ねるダイアログ（確認用の CLI からも出す）
    static func presentAsk(_ release: UpdateRelease, current: AppVersion) async -> Choice {
        let alert = NSAlert()
        alert.messageText = tr("Hanasu %@ があります", "\(release.version)")
        alert.informativeText = release.asset == nil
            ? tr("今の版は %@ です。この版は自動では入れ替えられないので、「アップデート」でリリースのページを開きます。", "\(current)")
            : tr("今の版は %@ です。「アップデート」を押すと、新しい版をダウンロードして確かめてから、Hanasu を終えて入れ替え、開き直します。", "\(current)")
        alert.addButton(withTitle: tr("アップデート"))
        alert.addButton(withTitle: tr("あとで"))
        alert.addButton(withTitle: tr("この版をスキップ"))
        if !release.notes.isEmpty {
            let notes = notesView(UpdateRelease.appNotes(from: release.notes), page: release.pageURL)
            alert.accessoryView = notes
            // 並べ終えると欄の終わりが見えた状態になるので、先頭から読めるように戻す
            alert.layout()
            if let scroll = notes as? NSScrollView {
                scroll.documentView?.scroll(.zero)
            }
        }
        return switch await runModal(alert) {
        case .alertFirstButtonReturn: .update
        case .alertThirdButtonReturn: .skip
        default: .later
        }
    }

    // 設計判断: DEC-REL-027
    /// ダイアログを、Task の外（RunLoop）から出す。
    /// Task の中で runModal を呼ぶと、出している間メインのディスパッチキューが回らず、スクロールが重くなり、ほかの画面の更新も止まる
    static func runModal(_ alert: NSAlert) async -> NSApplication.ModalResponse {
        await withCheckedContinuation { continuation in
            RunLoop.main.perform(inModes: [.default, .modalPanel]) {
                MainActor.assumeIsolated {
                    NSApp.activate()
                    continuation.resume(returning: alert.runModal())
                }
            }
        }
    }

    // 設計判断: DEC-REL-027
    /// リリース文を、スクロールできる欄に整えて出す（見出し・箇条書き・太字・リンク）。
    /// 終わりに、全文を読むためのリリースのページへのリンクを付ける。短ければ欄も低くする
    private static func notesView(_ notes: String, page: URL) -> NSView {
        let content = NSMutableAttributedString(attributedString: ReleaseNotesFormatter.attributed(notes))
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacingBefore = content.length == 0 ? 0 : 12
        if content.length > 0 { content.append(NSAttributedString(string: "\n")) }
        content.append(NSAttributedString(string: tr("リリースのページで全文を見る"), attributes: [
            .font: NSFont.systemFont(ofSize: ReleaseNotesFormatter.bodySize),
            .link: page,
            .paragraphStyle: paragraph,
        ]))

        let width: CGFloat = 440, inset = NSSize(width: 8, height: 8), maxHeight: CGFloat = 260
        // 中身の高さ（枠・余白・スクロールバーの分を引いた幅で測る）
        let textWidth = width - inset.width * 2 - 10 - NSScroller.scrollerWidth(for: .regular, scrollerStyle: .overlay)
        let needed = content.boundingRect(with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
                                          options: [.usesLineFragmentOrigin, .usesFontLeading]).height
        let height = min(maxHeight, ceil(needed) + inset.height * 2 + 6)

        // scrollableTextView は、中の文が長ければ縦に伸びてスクロールできる組み合わせを作る
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 0, y: 0, width: width, height: height)
        scroll.borderType = .bezelBorder
        if let text = scroll.documentView as? NSTextView {
            text.isEditable = false
            text.isSelectable = true
            text.isRichText = true
            text.textContainerInset = inset
            text.textStorage?.setAttributedString(content)
        }
        return scroll
    }

    // 設計判断: DEC-REL-023, DEC-REL-025, DEC-REL-026
    private func install(_ release: UpdateRelease) async {
        guard let asset = release.asset else {
            NSWorkspace.shared.open(release.pageURL)
            return
        }
        guard !isBusy() else {
            await alert(tr("今はアップデートできません"), tr("録音中・会議の記録中・処理中は入れ替えません。終わってから、メニューの「アップデートを確認…」でもう一度選んでください。"))
            return
        }
        var workDirectory: URL?
        do {
            try UpdateInstaller.checkInstallLocation()
            let work = try UpdateInstaller.makeWorkDirectory()
            workDirectory = work
            showProgress(tr("Hanasu %@ をダウンロードしています…", "\(release.version)"))
            let zip = try await UpdateHTTP.download(asset, into: work)
            // 展開と署名の確認は数秒かかるので、UI のスレッドの外で行う
            let current = Bundle.main.bundleURL, version = release.version
            let newApp = try await Task.detached {
                let app = try UpdateInstaller.extract(zip, into: work)
                try UpdateSignature.verify(newApp: app, current: current, expectedVersion: version)
                return app
            }.value
            closeProgress()
            // ダウンロードの間に録音・記録を始めていたら、入れ替えない
            guard !isBusy() else {
                try? FileManager.default.removeItem(at: work)
                await alert(tr("今はアップデートできません"), tr("録音中・会議の記録中・処理中は入れ替えません。終わってから、メニューの「アップデートを確認…」でもう一度選んでください。"))
                return
            }
            try UpdateInstaller.recordPending(release)
            try UpdateInstaller.launchSwap(newApp: newApp, workDirectory: work)
            appLog.notice("update: installing \(release.tag, privacy: .public), terminating")
            NSApp.terminate(nil)
        } catch {
            closeProgress()
            if let workDirectory { try? FileManager.default.removeItem(at: workDirectory) }
            // スクリプトを始める前の失敗はここで知らせるので、次の起動ではもう知らせない
            try? FileManager.default.removeItem(at: UpdateInstaller.pendingFile)
            appLog.error("update failed: \(error.localizedDescription, privacy: .public)")
            let alert = NSAlert()
            alert.messageText = tr("アップデートできませんでした")
            alert.informativeText = tr("%@\n\nリリースのページから zip をダウンロードして、手で入れ替えることもできます。", "\(error.localizedDescription)")
            alert.addButton(withTitle: tr("リリースのページを開く"))
            alert.addButton(withTitle: tr("閉じる"))
            if await Self.runModal(alert) == .alertFirstButtonReturn { NSWorkspace.shared.open(release.pageURL) }
        }
    }

    private func showProgress(_ message: String) {
        let view = HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text(message)
        }
        .padding(20)
        .frame(width: 360)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = tr("アップデート")
        window.styleMask = [.titled]
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()
        progressWindow = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func closeProgress() {
        progressWindow?.close()
        progressWindow = nil
    }

    private func alert(_ message: String, _ info: String) async {
        // 出している間も画面は動くので、起動時の確認のダイアログを重ねない
        let wasPrompting = isPrompting
        isPrompting = true
        defer { isPrompting = wasPrompting }
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        _ = await Self.runModal(alert)
    }
}

extension UpdateSettings {
    func shouldOffer(_ release: UpdateRelease, current: AppVersion, manual: Bool) -> Bool {
        Self.shouldOffer(release, current: current, skipped: skippedVersion, manual: manual)
    }
}

// MARK: - 設定画面

// 要件: REQ-REL-010, REQ-REL-011
// 設計判断: DEC-REL-024
/// 設定の「一般」タブの「アップデート」の欄
struct UpdateSettingsSection: View {
    @ObservedObject var settings = UpdateSettings.shared
    var onCheckNow: () -> Void

    var body: some View {
        Section {
            Toggle(tr("起動時にアップデートを確認する"), isOn: $settings.checkOnLaunch)
            LabeledContent(tr("今の版")) {
                HStack {
                    Text(AppVersion.current?.description ?? tr("不明"))
                    Button(tr("今すぐ確認"), action: onCheckNow)
                }
            }
        } header: {
            Text(tr("アップデート"))
        } footer: {
            Text(tr("新しい版があれば、入れ替えてよいかを尋ねます。「アップデート」を選んだときだけ、GitHub のリリースから新しい版をダウンロードし、SHA-256 と署名を確かめてから入れ替えます。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
