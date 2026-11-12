import AppKit
import Darwin
import Foundation

// `hanasu` コマンドを配る部分（計画は docs/plans/cli.md の段階 4。E3〜E5・E7）。
// 設定画面の「コマンドと MCP」と `hanasu doctor` が使う。名前が CLI.swift で終わらないので、訳の検査の対象になる。

// 要件: REQ-COM-190, REQ-COM-191, REQ-COM-192
// 設計判断: DEC-COM-188, DEC-COM-189
enum HanasuInstall {
    static let commandName = "hanasu"
    /// 管理者の確認で入れる場所（root が持つ）
    static let systemDirectory = URL(fileURLWithPath: "/usr/local/bin", isDirectory: true)
    /// ~/.zprofile に足す行の前に置く印。外すときは、この印とすぐ次の 1 行だけを消す（言語によらない固定の文）
    static let profileMarker = "# Added by Hanasu: puts the hanasu command on PATH"
    static let exportLine = "export PATH=\"$HOME/.local/bin:$PATH\""

    /// アプリの実行ファイルの実際のパス（シンボリックリンクをたどった先）
    static var executablePath: String {
        (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath().path
    }

    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// 管理者の権限なしで入れる場所
    static func userDirectory(home: URL = home) -> URL {
        home.appendingPathComponent(".local/bin", isDirectory: true)
    }

    // MARK: - App Translocation

    // 要件: REQ-COM-192
    // 設計判断: DEC-COM-189
    /// ダウンロードした場所から移さずに開いたので、macOS が読み取り専用の仮の場所で動かしているか。
    /// 仮の場所は起動のたびに変わるので、そのパスを PATH や MCP の登録に書くと、次から動かない
    static func isTranslocated(_ bundlePath: String = Bundle.main.bundlePath) -> Bool {
        bundlePath.contains("/AppTranslocation/")
    }

    // MARK: - リンクの状態

    enum LinkState: Equatable {
        /// 何もない
        case missing
        /// このアプリの実行ファイルを指している
        case current
        /// 別の場所の Hanasu を指している（前に置いていた場所など。入れ直してよい）
        case otherHanasu(String)
        /// Hanasu のものでないファイル（上書きしない）
        case foreign

        var json: String {
            switch self {
            case .missing: "missing"
            case .current: "current"
            case .otherHanasu: "otherHanasu"
            case .foreign: "foreign"
            }
        }

        /// 入れ直したり外したりしてよい（自分の作ったリンク）
        var isOurs: Bool {
            switch self {
            case .current, .otherHanasu: true
            case .missing, .foreign: false
            }
        }
    }

    static func linkState(at link: URL, executable: String = executablePath) -> LinkState {
        var info = stat()
        guard lstat(link.path, &info) == 0 else { return .missing }
        guard (info.st_mode & S_IFMT) == S_IFLNK,
              let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) else { return .foreign }
        let target = URL(fileURLWithPath: destination, relativeTo: link.deletingLastPathComponent())
        let resolved = target.resolvingSymlinksInPath().path
        if resolved == URL(fileURLWithPath: executable).resolvingSymlinksInPath().path { return .current }
        // アプリの中の実行ファイル（…/Contents/MacOS/Hanasu）か、開発でビルドしたもの（…/Hanasu）。消えた場所を指していてもよい
        if target.standardizedFileURL.lastPathComponent == "Hanasu" { return .otherHanasu(target.standardizedFileURL.path) }
        return .foreign
    }

    static func systemLink() -> URL { systemDirectory.appendingPathComponent(commandName) }
    static func userLink(home: URL = home) -> URL { userDirectory(home: home).appendingPathComponent(commandName) }

    enum InstallError: LocalizedError {
        case occupied(String)
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .occupied(let path): tr("%@ に、Hanasu のものでないファイルがあります。上書きしません。", path)
            case .failed(let message): message
            }
        }
    }

    // MARK: - ~/.local/bin（管理者の権限なし）

    // 要件: REQ-COM-191
    static func installUserLink(home: URL = home, executable: String = executablePath) throws {
        let link = userLink(home: home)
        switch linkState(at: link, executable: executable) {
        case .current: return
        case .foreign: throw InstallError.occupied(link.path)
        case .otherHanasu: try FileManager.default.removeItem(at: link)
        case .missing: break
        }
        try FileManager.default.createDirectory(at: userDirectory(home: home), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: executable)
    }

    static func removeUserLink(home: URL = home, executable: String = executablePath) throws {
        let link = userLink(home: home)
        guard linkState(at: link, executable: executable).isOurs else { return }
        try FileManager.default.removeItem(at: link)
    }

    // MARK: - /usr/local/bin（管理者の確認）

    enum PrivilegedResult: Equatable {
        case done
        case canceled
        case failed(String)
    }

    // 設計判断: DEC-COM-188
    /// /usr/local/bin にリンクを作る。書ける場所ならそのまま作り、書けなければ管理者の確認（macOS のパスワードの画面）を出す
    @MainActor
    static func installSystemLink(executable: String = executablePath) -> PrivilegedResult {
        let link = systemLink()
        switch linkState(at: link, executable: executable) {
        case .current: return .done
        case .foreign: return .failed(InstallError.occupied(link.path).localizedDescription)
        case .otherHanasu, .missing: break
        }
        if (try? FileManager.default.removeItem(at: link)) != nil || linkState(at: link, executable: executable) == .missing,
           (try? FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: executable)) != nil {
            return .done
        }
        return runAsAdministrator(
            "/bin/mkdir -p \(shellQuoted(systemDirectory.path)) && /bin/ln -sfh \(shellQuoted(executable)) \(shellQuoted(link.path))")
    }

    @MainActor
    static func removeSystemLink(executable: String = executablePath) -> PrivilegedResult {
        let link = systemLink()
        guard linkState(at: link, executable: executable).isOurs else { return .done }
        if (try? FileManager.default.removeItem(at: link)) != nil { return .done }
        return runAsAdministrator("/bin/rm -f \(shellQuoted(link.path))")
    }

    /// 管理者の権限でシェルのコマンドを 1 つ動かす（AppleScript の with administrator privileges。macOS が確認を出す）
    @MainActor
    private static func runAsAdministrator(_ command: String) -> PrivilegedResult {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        guard let script = NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges") else {
            return .failed(tr("管理者の確認を出せませんでした。"))
        }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        guard let error else { return .done }
        if (error[NSAppleScript.errorNumber] as? Int) == -128 { return .canceled }
        return .failed(error[NSAppleScript.errorMessage] as? String ?? tr("管理者の確認を出せませんでした。"))
    }

    // MARK: - シェルの PATH

    enum Shell: Equatable {
        case zsh, bash, fish, other

        init(path: String) {
            switch URL(fileURLWithPath: path).lastPathComponent {
            case "zsh": self = .zsh
            case "bash": self = .bash
            case "fish": self = .fish
            default: self = .other
            }
        }
    }

    /// ログインシェル（ユーザーのアカウントの設定。アプリの環境変数ではなく）
    static var loginShellPath: String {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell { return String(cString: shell) }
        return ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }

    /// ~/.local/bin を PATH に足す 1 行（シェルごと）
    static func pathLine(for shell: Shell) -> String {
        shell == .fish ? "fish_add_path $HOME/.local/bin" : exportLine
    }

    /// PATH を決めるシェルの設定ファイル
    static func profileFiles(for shell: Shell, home: URL = home) -> [URL] {
        let names: [String] = switch shell {
        case .zsh: [".zshenv", ".zprofile", ".zshrc", ".zlogin"]
        case .bash: [".bash_profile", ".bash_login", ".profile", ".bashrc"]
        case .fish: [".config/fish/config.fish", ".config/fish/fish_variables"]
        case .other: [".profile"]
        }
        return names.map { home.appendingPathComponent($0) }
    }

    /// ~/.local/bin がシェルの PATH に入っていそうか。アプリからはターミナルの PATH が見えないので、設定ファイルに書いてあるかで見る
    static func userDirectoryOnPath(shell: Shell, home: URL = home) -> Bool {
        profileFiles(for: shell, home: home).contains { file in
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { return false }
            return text.contains(".local/bin")
        }
    }

    static func zprofile(home: URL = home) -> URL { home.appendingPathComponent(".zprofile") }

    static func hasProfileLine(home: URL = home) -> Bool {
        guard let text = try? String(contentsOf: zprofile(home: home), encoding: .utf8) else { return false }
        return text.components(separatedBy: "\n").contains(profileMarker)
    }

    // 要件: REQ-COM-191
    /// ~/.zprofile の終わりに、印と PATH の 1 行を足す（zsh だけ。足す前に画面で確かめる）
    static func addProfileLine(home: URL = home) throws {
        guard !hasProfileLine(home: home) else { return }
        let file = zprofile(home: home)
        var text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
        text += "\n\(profileMarker)\n\(exportLine)\n"
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    /// 足した行（印と、そのすぐ次の PATH の 1 行）だけを消す。ユーザーが書き換えていれば、印だけを消す
    static func removeProfileLine(home: URL = home) throws {
        let file = zprofile(home: home)
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return }
        var lines = text.components(separatedBy: "\n")
        guard let index = lines.firstIndex(of: profileMarker) else { return }
        let end = lines.indices.contains(index + 1) && lines[index + 1] == exportLine ? index + 2 : index + 1
        // 足すときに入れた空行も消す
        let start = index > 0 && lines[index - 1].isEmpty ? index - 1 : index
        lines.removeSubrange(start..<end)
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    // MARK: - MCP の登録

    // 要件: REQ-COM-190
    /// シェルにそのまま貼れる形（安全な文字だけならそのまま、ほかは ' で囲む）
    static func shellQuoted(_ text: String) -> String {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/._-+:@%,="))
        if !text.isEmpty, text.unicodeScalars.allSatisfy({ safe.contains($0) && $0.isASCII }) { return text }
        return "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Claude Code に登録するコマンド（絶対パスで書くので、PATH が要らない。--scope user で、どのフォルダの Claude Code からも使える）
    static func claudeCodeCommand(executable: String = executablePath) -> String {
        "claude mcp add --scope user hanasu -- \(shellQuoted(executable)) mcp"
    }

    /// Claude Desktop の設定（claude_desktop_config.json）の mcpServers に足す形
    static func claudeDesktopConfig(executable: String = executablePath) -> [String: Any] {
        ["mcpServers": ["hanasu": ["command": executable, "args": ["mcp"]]]]
    }

    /// 人が貼る形（command を先に、引数は 1 行に）。値は JSON の決まりどおりにエスケープする
    static func claudeDesktopJSON(executable: String = executablePath) -> String {
        let command = (try? JSONSerialization.data(withJSONObject: executable, options: [.fragmentsAllowed, .withoutEscapingSlashes]))
            .map { String(decoding: $0, as: UTF8.self) } ?? "\"\""
        return """
        {
          "mcpServers": {
            "hanasu": {
              "command": \(command),
              "args": ["mcp"]
            }
          }
        }
        """
    }
}
