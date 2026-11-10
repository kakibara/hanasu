import Foundation

// 利用者向けの `hanasu doctor`（計画は docs/plans/cli.md の C8）。AI・認証情報・会議のフォルダ・ポリシー・MCP の登録のしかたを出す。
// Claude Desktop の設定に貼る JSON と設定画面は、計画の段階 4 で足す。名前が CLI.swift で終わらないので、訳の検査の対象になる。

// 要件: REQ-COM-186, REQ-COM-190, REQ-COM-191, REQ-COM-192
// 設計判断: DEC-COM-185
enum HanasuDoctorCommand {
    static func run(_ arguments: [String]) throws -> HanasuExit {
        let args = try HanasuArguments.parse(arguments, flags: ["--json", "--help", "-h"], options: HanasuMeetingsCommand.commonOptions)
        if args.flags.contains("--help") || args.flags.contains("-h") {
            HanasuOutput.out(HanasuHelp.section(for: "doctor") ?? HanasuHelp.full())
            return .ok
        }
        let settings = AppSettings.shared
        let executable = HanasuInstall.executablePath
        let directory = HanasuMeetingsCommand.meetingsDirectory(args)
        let folder = folderStatus(directory)
        let purposes = TextAIPurpose.allCases.map { purpose in
            (purpose, HanasuAI.Choice(provider: settings.aiProvider(for: purpose), model: settings.textModel(for: purpose)))
        }
        // キーは実際に読んで、読めるかを確かめる（値は捨てる）。シンボリックリンク経由でパスワードを求められるかも、ここで分かる
        let gemini = HanasuAI.credentialStatus(.gemini, settings: settings, read: true)
        let claude = HanasuAI.credentialStatus(.claude, settings: settings, read: true)
        let downloaded = LocalLLMModel.allCases.filter(LocalLLMStore.isDownloaded)
        let apple = AppleFMAvailability.check()
        let policies = HanasuPolicy.active
        let translocated = HanasuInstall.isTranslocated()
        // ターミナルから呼ばれたときは、そのシェルの PATH が見える
        let searchPath = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let links = [HanasuInstall.systemLink(), HanasuInstall.userLink()].map { link in
            (link: link, state: HanasuInstall.linkState(at: link, executable: executable),
             onPath: searchPath.contains(link.deletingLastPathComponent().path))
        }

        if args.flags.contains("--json") {
            func credentialJSON(_ status: HanasuAI.CredentialStatus) -> [String: Any] {
                ["configured": status.source != nil, "source": HanasuJSON.optional(status.source),
                 "readable": status.source == nil ? NSNull() : (status.problem == nil) as Any,
                 "problem": HanasuJSON.optional(status.problem)]
            }
            var ai: [String: Any] = [:]
            for (purpose, choice) in purposes { ai[purpose.rawValue] = choice.json }
            try HanasuOutput.json([
                "version": HanasuCommand.version,
                "executable": executable,
                "meetingsDirectory": ["path": directory.path, "status": folder.status, "problem": HanasuJSON.optional(folder.problem)],
                "ai": ai,
                "credentials": [
                    "gemini": credentialJSON(gemini),
                    "claude": credentialJSON(claude),
                    "local": ["downloadedModels": downloaded.map(\.rawValue),
                              "otherProcessServerRunning": LocalLLMServer.otherProcessServerRunning()],
                    "apple": ["available": apple.executableURL != nil, "reason": HanasuJSON.optional(apple.reason)],
                ],
                "policies": policies,
                "install": [
                    "translocated": translocated,
                    "links": links.map { ["path": $0.link.path, "state": $0.state.json, "onPath": $0.onPath] },
                ],
                "mcp": ["command": executable, "args": ["mcp"],
                        "claudeCode": HanasuInstall.claudeCodeCommand(executable: executable),
                        "claudeDesktop": HanasuInstall.claudeDesktopConfig(executable: executable),
                        "disabled": HanasuPolicy.mcpDisabled, "askMeetingsDisabled": HanasuPolicy.mcpAskMeetingsDisabled],
            ])
            return .ok
        }

        func credentialLine(_ status: HanasuAI.CredentialStatus) -> String {
            guard let label = status.label else { return tr("未設定") }
            if let problem = status.problem { return tr("%@（読めません: %@）", label, problem) }
            return tr("%@（読めます）", label)
        }
        let folderLine: String = switch folder.status {
        case "readable": tr("%@（読めます）", directory.path)
        case "missing": tr("%@（まだありません）", directory.path)
        default: tr("%@（読めません: %@）", directory.path, folder.problem ?? "")
        }
        var lines = [
            "hanasu \(HanasuCommand.version)",
            tr("実行ファイル: %@", executable),
        ]
        // 要件: REQ-COM-192
        if translocated {
            lines.append("  " + tr("Hanasu がダウンロードした場所から移されずに動いています（App Translocation）。このパスは起動のたびに変わるので、Hanasu をアプリケーションフォルダに移して開き直してから、PATH と MCP に登録してください。"))
        }
        // 要件: REQ-COM-191
        let installed = links.filter { $0.state.isOurs }
        if installed.isEmpty {
            lines.append(tr("PATH: 入っていません（設定画面の「コマンドと MCP」で入れられます。絶対パスならそのまま使えます）"))
        }
        for item in installed {
            var line = item.state == .current ? tr("PATH: %@", item.link.path) : tr("PATH: %@（別の場所の Hanasu を指しています）", item.link.path)
            if !item.onPath { line += " " + tr("（このシェルの PATH にはありません）") }
            lines.append(line)
        }
        lines += [
            tr("会議のフォルダ: %@", folderLine),
            tr("使う AI:"),
        ]
        for (purpose, choice) in purposes {
            let commands = purpose == .meeting ? "ask" : "refine, edit"
            lines.append("  " + tr("%@（%@）", purpose.label, commands) + ": " + tr("%@（%@）", choice.provider.name, choice.model))
        }
        lines += [
            tr("認証情報:"),
            "  Gemini: " + credentialLine(gemini),
            "  Claude: " + credentialLine(claude),
            "  " + tr("ローカル: %@", downloaded.isEmpty ? tr("ダウンロード済みのモデルはありません") : downloaded.map(\.rawValue).joined(separator: " / ")),
            "  Apple: " + (apple.executableURL != nil ? tr("使えます") : (apple.reason ?? "")),
        ]
        if LocalLLMServer.otherProcessServerRunning() {
            lines.append("  " + tr("Hanasu のアプリがローカルの AI を使っています。"))
        }
        // 要件: REQ-COM-189
        lines.append("MCP:")
        if HanasuPolicy.mcpDisabled {
            lines.append("  " + tr("管理者のポリシーで、hanasu mcp は使えないようにされています（%@）。", HanasuPolicy.Key.disableMCP.rawValue))
        } else {
            lines += HanasuHelp.mcpNotes.map { "  " + $0 }
            lines.append("  " + tr("Claude Desktop の設定（claude_desktop_config.json）に足す形:"))
            lines += HanasuInstall.claudeDesktopJSON(executable: executable).components(separatedBy: "\n").map { "    " + $0 }
        }
        if policies.isEmpty {
            lines.append(tr("管理者のポリシー: なし"))
        } else {
            lines.append(tr("管理者のポリシー:"))
            for key in policies.keys.sorted() {
                let value = policies[key].map { value -> String in
                    if let list = value as? [Any] { return list.map { "\($0)" }.joined(separator: ", ") }
                    return "\(value)"
                } ?? ""
                lines.append("  \(key) = \(value)")
            }
        }
        HanasuOutput.out(lines.joined(separator: "\n"))
        return .ok
    }

    /// 会議のフォルダを読めるか（中身は数えない）。readable・missing・unreadable
    static func folderStatus(_ directory: URL) -> (status: String, problem: String?) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) else { return ("missing", nil) }
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            return ("readable", nil)
        } catch {
            return ("unreadable", error.localizedDescription)
        }
    }
}
