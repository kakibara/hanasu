import AppKit
import CryptoKit
import Foundation
import Security
import SwiftUI

// MARK: - 版の比べ方

// 設計判断: DEC-REL-020
/// 「1.6.0」「v1.6.0」「1.6」の形の版。数字の部分ごとに比べる（1.10.0 は 1.9.0 より新しい）
struct AppVersion: Comparable, CustomStringConvertible {
    let components: [Int]

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
        // 末尾の 0 を除いて比べる（1.6 と 1.6.0 を同じにする）
        while numbers.count > 1, numbers.last == 0 { numbers.removeLast() }
        components = numbers
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let a = index < lhs.components.count ? lhs.components[index] : 0
            let b = index < rhs.components.count ? rhs.components[index] : 0
            if a != b { return a < b }
        }
        return false
    }

    var description: String { components.map(String.init).joined(separator: ".") }

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
            case .invalid(let reason): "リリースの情報を読めませんでした（\(reason)）"
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
            throw ParseError.invalid("JSON の形が違います")
        }
        if response.draft == true || response.prerelease == true { return nil }
        guard let version = AppVersion(response.tag_name) else { throw ParseError.invalid("版の形が違います: \(response.tag_name)") }
        guard let page = URL(string: response.html_url), UpdateHTTP.isAllowed(page) else {
            throw ParseError.invalid("リリースのページが GitHub ではありません")
        }
        let versionText = response.tag_name.hasPrefix("v") ? String(response.tag_name.dropFirst()) : response.tag_name
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
            case .disallowed(let host): "GitHub 以外の場所（\(host)）からは取りません"
            case .status(403), .status(429): "GitHub に何度も問い合わせたため、しばらく確かめられません（少し時間をおいてください）"
            case .status(let code): "GitHub から取れませんでした（HTTP \(code)）"
            case .sizeMismatch(let expected, let actual): "ダウンロードした大きさが違います（\(actual) バイト、想定は \(expected) バイト）"
            case .hashMismatch: "ダウンロードしたファイルの SHA-256 がリリースの値と違うので、使いません"
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
            case .unsignedCurrent: "今の Hanasu が配布用の証明書で署名されていない（手元でビルドしたものなど）ので、自動では入れ替えません"
            case .invalid(let reason): "新しい Hanasu の署名を確かめられませんでした（\(reason)）"
            case .differentCertificate: "新しい Hanasu が、今の Hanasu と違う証明書で署名されているので、入れ替えません"
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
            throw Failure.invalid("読み込めません")
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
        else { throw Failure.invalid("アプリの ID が違います") }
        guard let text = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              AppVersion(text) == expectedVersion
        else { throw Failure.invalid("版がリリースと違います") }
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
            case .notAnApp: "Hanasu.app として動いていないので、入れ替えられません"
            case .translocated: "Hanasu が「ダウンロード」などから直接開かれているので、入れ替えられません。Hanasu.app を「アプリケーション」フォルダに移してから開き直してください"
            case .notWritable(let path): "\(path) に書き込めないので、入れ替えられません"
            case .missingApp: "ダウンロードした zip に Hanasu.app がありません"
            case .extractFailed(let status): "ダウンロードした zip を展開できませんでした（ditto \(status)）"
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

    /// スクリプトの中身は固定で、パスは引数で渡す（パスをスクリプトの文に埋め込まない）
    static let swapScript = """
        #!/bin/sh
        # Hanasu のアップデート: Hanasu が終わるのを待ってから、.app を入れ替えて開き直す
        # 引数: <待つ PID> <入れ替える .app> <新しい .app> <作業フォルダ>
        pid="$1"; target="$2"; new="$3"; work="$4"
        i=0
        while kill -0 "$pid" 2>/dev/null; do
          i=$((i + 1))
          if [ "$i" -gt 600 ]; then exit 1; fi
          sleep 0.1
        done
        backup="$work/Hanasu-previous.app"
        if mv "$target" "$backup"; then
          if ! mv "$new" "$target"; then
            mv "$backup" "$target"
          fi
        fi
        open "$target"
        rm -rf "$work"
        """

    /// スクリプトを動かす（このあと Hanasu を終える）
    static func launchSwap(newApp: URL, workDirectory: URL, target: URL = Bundle.main.bundleURL) throws {
        let script = workDirectory.appendingPathComponent("swap.sh")
        try swapScript.write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), target.path, newApp.path, workDirectory.path]
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
    private var isRunning = false
    private var progressWindow: NSWindow?

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
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        guard let current = AppVersion.current else {
            if manual { alert("今の版が分かりません", "Hanasu.app として動いていないため、アップデートを確かめられません。") }
            return
        }
        let release: UpdateRelease?
        do {
            release = try await UpdateHTTP.fetchLatestRelease()
        } catch {
            appLog.notice("update check failed: \(error.localizedDescription, privacy: .public)")
            if manual { alert("アップデートを確かめられませんでした", error.localizedDescription) }
            return
        }
        guard let release,
              UpdateSettings.shared.shouldOffer(release, current: current, manual: manual)
        else {
            appLog.notice("update check: up to date (\(current.description, privacy: .public))")
            if manual { alert("Hanasu は最新です", "今の版（\(current)）が最新です。") }
            return
        }
        appLog.notice("update available: \(release.tag, privacy: .public)")
        // 設計判断: DEC-REL-023
        // 起動時の確認は、録音・記録が終わるまで尋ねるのを待つ
        if !manual {
            while isBusy() { try? await Task.sleep(for: .seconds(10)) }
        }
        switch ask(release, current: current) {
        case .update: await install(release)
        case .later: break
        case .skip: UpdateSettings.shared.skippedVersion = release.version.description
        }
    }

    private enum Choice { case update, later, skip }

    // 設計判断: DEC-REL-022
    private func ask(_ release: UpdateRelease, current: AppVersion) -> Choice {
        let alert = NSAlert()
        alert.messageText = "Hanasu \(release.version) があります"
        alert.informativeText = release.asset == nil
            ? "今の版は \(current) です。この版は自動では入れ替えられないので、「アップデート」でリリースのページを開きます。"
            : "今の版は \(current) です。「アップデート」を押すと、新しい版をダウンロードして確かめてから、Hanasu を終えて入れ替え、開き直します。"
        alert.addButton(withTitle: "アップデート")
        alert.addButton(withTitle: "あとで")
        alert.addButton(withTitle: "この版をスキップ")
        if !release.notes.isEmpty { alert.accessoryView = Self.notesView(release.notes) }
        NSApp.activate()
        return switch alert.runModal() {
        case .alertFirstButtonReturn: .update
        case .alertThirdButtonReturn: .skip
        default: .later
        }
    }

    /// リリース文を、スクロールできる欄に出す（Markdown は解釈せず、太字の印だけを外す）
    private static func notesView(_ notes: String) -> NSView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 220))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let text = NSTextView(frame: scroll.bounds)
        text.isEditable = false
        text.isSelectable = true
        text.autoresizingMask = [.width]
        text.textContainerInset = NSSize(width: 6, height: 6)
        text.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        text.textColor = NSColor.labelColor
        text.string = notes.replacingOccurrences(of: "**", with: "")
        scroll.documentView = text
        return scroll
    }

    // 設計判断: DEC-REL-023, DEC-REL-025, DEC-REL-026
    private func install(_ release: UpdateRelease) async {
        guard let asset = release.asset else {
            NSWorkspace.shared.open(release.pageURL)
            return
        }
        guard !isBusy() else {
            alert("今はアップデートできません", "録音中・会議の記録中・処理中は入れ替えません。終わってから、メニューの「アップデートを確認…」でもう一度選んでください。")
            return
        }
        var workDirectory: URL?
        do {
            try UpdateInstaller.checkInstallLocation()
            let work = try UpdateInstaller.makeWorkDirectory()
            workDirectory = work
            showProgress("Hanasu \(release.version) をダウンロードしています…")
            let zip = try await UpdateHTTP.download(asset, into: work)
            let newApp = try UpdateInstaller.extract(zip, into: work)
            try UpdateSignature.verify(newApp: newApp, current: Bundle.main.bundleURL, expectedVersion: release.version)
            closeProgress()
            // ダウンロードの間に録音・記録を始めていたら、入れ替えない
            guard !isBusy() else {
                try? FileManager.default.removeItem(at: work)
                alert("今はアップデートできません", "録音中・会議の記録中・処理中は入れ替えません。終わってから、メニューの「アップデートを確認…」でもう一度選んでください。")
                return
            }
            try UpdateInstaller.launchSwap(newApp: newApp, workDirectory: work)
            appLog.notice("update: installing \(release.tag, privacy: .public), terminating")
            NSApp.terminate(nil)
        } catch {
            closeProgress()
            if let workDirectory { try? FileManager.default.removeItem(at: workDirectory) }
            appLog.error("update failed: \(error.localizedDescription, privacy: .public)")
            let alert = NSAlert()
            alert.messageText = "アップデートできませんでした"
            alert.informativeText = "\(error.localizedDescription)\n\nリリースのページから zip をダウンロードして、手で入れ替えることもできます。"
            alert.addButton(withTitle: "リリースのページを開く")
            alert.addButton(withTitle: "閉じる")
            NSApp.activate()
            if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(release.pageURL) }
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
        window.title = "アップデート"
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

    private func alert(_ message: String, _ info: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        NSApp.activate()
        alert.runModal()
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
            Toggle("起動時にアップデートを確認する", isOn: $settings.checkOnLaunch)
            LabeledContent("今の版") {
                HStack {
                    Text(AppVersion.current?.description ?? "不明")
                    Button("今すぐ確認", action: onCheckNow)
                }
            }
        } header: {
            Text("アップデート")
        } footer: {
            Text("新しい版があれば、入れ替えてよいかを尋ねます。「アップデート」を選んだときだけ、GitHub のリリースから新しい版をダウンロードし、SHA-256 と署名を確かめてから入れ替えます。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - 確認用の CLI

/// アップデートの確認用の CLI モード（main.swift から呼ぶ）:
///   Hanasu --update-selftest
///       版の比べ方・リリースの情報の読み方・スキップの扱い・ホストの制限を、例のデータで確かめる（通信しない）
///   Hanasu --check-update [--current <版>]
///       GitHub に問い合わせ、最新の版・zip・SHA-256 と、知らせるかを出す（ダウンロードはしない）
///   Hanasu --verify-update <Hanasu-<版>-macOS.zip> --version <版>
///       zip を展開し、入れ替えの前と同じ確認（署名・証明書・bundle ID・版）をする。Hanasu.app の中の実行ファイルで動かす
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
        if let zip = value(after: "--verify-update", in: args) {
            guard let version = value(after: "--version", in: args).flatMap(AppVersion.init) else {
                print("--version <版> を付けてください")
                exit(1)
            }
            do {
                try UpdateInstaller.checkInstallLocation()
                let work = try UpdateInstaller.makeWorkDirectory()
                defer { try? FileManager.default.removeItem(at: work) }
                let app = try UpdateInstaller.extract(URL(fileURLWithPath: zip), into: work)
                try UpdateSignature.verify(newApp: app, current: Bundle.main.bundleURL, expectedVersion: version)
                print("ok: \(app.lastPathComponent) は今の Hanasu と同じ証明書で署名されていて、版は \(version) です")
                exit(0)
            } catch {
                print("ng: \(error.localizedDescription)")
                exit(1)
            }
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
        expect(UpdateInstaller.swapScript.contains("target=\"$2\"") && !UpdateInstaller.swapScript.contains("/Applications"),
               "スクリプトは引数でパスを受け取る")

        print(failures == 0 ? "すべて通りました" : "\(failures) 件の失敗")
        return failures == 0
    }
}
