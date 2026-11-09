import Foundation

// 利用者向けの `hanasu doctor`（計画は docs/plans/cli.md の C8）。段階 2 では、AI・認証情報・会議のフォルダ・ポリシーを出す。
// MCP の登録のしかたは段階 3・4 で足す。名前が CLI.swift で終わらないので、訳の検査の対象になる。

// 要件: REQ-COM-186
// 設計判断: DEC-COM-185
enum HanasuDoctorCommand {
    static func run(_ arguments: [String]) throws -> HanasuExit {
        let args = try HanasuArguments.parse(arguments, flags: ["--json", "--help", "-h"], options: HanasuMeetingsCommand.commonOptions)
        if args.flags.contains("--help") || args.flags.contains("-h") {
            HanasuOutput.out(HanasuHelp.section(for: "doctor") ?? HanasuHelp.full())
            return .ok
        }
        let settings = AppSettings.shared
        let executable = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath().path
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
