import AppKit
import SwiftUI

// 設定画面の「コマンドと MCP」（計画は docs/plans/cli.md の段階 4。E3〜E5・E7）。
// 中身の処理（リンク・シェルの設定・登録の文）は HanasuInstall.swift。

// 要件: REQ-COM-190, REQ-COM-191, REQ-COM-192, REQ-COM-193
// 設計判断: DEC-COM-188
struct CommandLineSettingsTab: View {
    /// リンクやシェルの設定を変えたあとに、状態を読み直す
    @State private var refresh = 0
    @State private var message: String?
    @State private var showsAgentGuide = false

    var body: some View {
        let _ = refresh
        let executable = HanasuInstall.executablePath
        let translocated = HanasuInstall.isTranslocated()
        let cliDisabled = HanasuPolicy.cliDisabled
        let mcpDisabled = HanasuPolicy.mcpDisabled
        // 仮の場所のパスは起動のたびに変わるので、登録に使わせない（REQ-COM-192）
        let registrationBlocked = translocated || cliDisabled

        Form {
            if translocated {
                // 要件: REQ-COM-192
                Section {
                    Label(tr("Hanasu がダウンロードした場所から移されずに動いています（App Translocation）。このパスは起動のたびに変わるので、PATH と MCP には登録できません。Hanasu をアプリケーションフォルダに移してから、開き直してください。"),
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if cliDisabled {
                Section {
                    Label(tr("管理者のポリシーで、hanasu コマンドは使えないようにされています（%@）。", HanasuPolicy.Key.disableCLI.rawValue),
                          systemImage: "lock.fill")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                CopyableValue(title: tr("実行ファイル"), value: executable, disabled: registrationBlocked)
                pathStatus(executable: executable)
                HStack {
                    let installed = HanasuInstall.linkState(at: HanasuInstall.systemLink(), executable: executable) == .current
                        || HanasuInstall.linkState(at: HanasuInstall.userLink(), executable: executable) == .current
                    if !installed {
                        Button(tr("PATH に入れる…")) { install(executable: executable) }
                            .disabled(registrationBlocked)
                    }
                    if canRemove(executable: executable) {
                        // 外すのは、ポリシーで止められていてもできる（残ったリンクを片付けられるように）
                        Button(tr("PATH から外す…")) { remove(executable: executable) }
                    }
                }
                if let message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text(tr("hanasu コマンド"))
            } footer: {
                Text(tr("ターミナルやスクリプト、AI エージェントから、会議の記録を読んだり、文章を整えたりできます。PATH に入れなくても、上の実行ファイルのパスで呼べます。使い方はターミナルで hanasu help を見てください。"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            // 要件: REQ-COM-190
            Section {
                if mcpDisabled {
                    Label(tr("管理者のポリシーで、hanasu mcp は使えないようにされています（%@）。", HanasuPolicy.Key.disableMCP.rawValue),
                          systemImage: "lock.fill")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    CopyableValue(title: "Claude Code", value: HanasuInstall.claudeCodeCommand(executable: executable),
                                  disabled: registrationBlocked)
                    CopyableValue(title: "Claude Desktop", value: HanasuInstall.claudeDesktopJSON(executable: executable),
                                  disabled: registrationBlocked,
                                  note: tr("Claude Desktop の設定ファイル（claude_desktop_config.json）の mcpServers に足します。ほかのアプリも、command と args に同じものを書きます。"))
                }
            } header: {
                Text("MCP")
            } footer: {
                if !mcpDisabled {
                    Text(tr("MCP で返した会議の中身は、MCP を使うエージェントと、その AI の提供元に渡ります。ask_meetings は、会議の中身を hanasu ask と同じ AI（hanasu doctor の ask の行）にも送ります。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            // 要件: REQ-COM-193
            Section {
                HStack {
                    Button(showsAgentGuide ? tr("説明を隠す") : tr("説明を見る")) { showsAgentGuide.toggle() }
                    CopyButton(value: HanasuHelp.agentGuide(executable: executable))
                        .disabled(registrationBlocked)
                }
                if showsAgentGuide {
                    Text(HanasuHelp.agentGuide(executable: executable))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text(tr("エージェントへの説明"))
            } footer: {
                Text(tr("MCP を登録できないときは、この説明（英語）をエージェントの指示（Claude Code の CLAUDE.md やスキルなど）に貼ると、エージェントがシェルから hanasu を呼んで会議を読めます。ターミナルでは hanasu help agent で出せます。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - PATH の状態

    // 要件: REQ-COM-191
    @ViewBuilder
    private func pathStatus(executable: String) -> some View {
        let system = HanasuInstall.systemLink()
        let user = HanasuInstall.userLink()
        let systemState = HanasuInstall.linkState(at: system, executable: executable)
        let userState = HanasuInstall.linkState(at: user, executable: executable)
        let shell = HanasuInstall.Shell(path: HanasuInstall.loginShellPath)
        LabeledContent("PATH") {
            VStack(alignment: .trailing, spacing: 4) {
                if !systemState.isOurs && !userState.isOurs {
                    Text(tr("入っていません"))
                }
                ForEach([(system, systemState), (user, userState)].filter { $0.1.isOurs }, id: \.0) { link, state in
                    Text(state == .current ? tr("%@ に入っています", link.path) : tr("%@ は、別の場所の Hanasu を指しています。入れ直すと、このアプリを指します。", link.path))
                }
                if systemState == .foreign {
                    Text(HanasuInstall.InstallError.occupied(system.path).localizedDescription)
                        .foregroundStyle(.orange)
                }
            }
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
        }
        if userState.isOurs && !systemState.isOurs && !HanasuInstall.userDirectoryOnPath(shell: shell) {
            // ~/.local/bin がシェルの PATH にないとき。zsh なら「PATH に入れる」で足せる。ほかのシェルは、足す行を出す
            CopyableValue(title: tr("シェルの設定に足す行"), value: HanasuInstall.pathLine(for: shell), disabled: false,
                          note: tr("新しいターミナルで hanasu と打って使うには、この行をシェルの設定ファイルに足してください（%@）。", HanasuInstall.loginShellPath))
        }
    }

    private func canRemove(executable: String) -> Bool {
        HanasuInstall.linkState(at: HanasuInstall.systemLink(), executable: executable).isOurs
            || HanasuInstall.linkState(at: HanasuInstall.userLink(), executable: executable).isOurs
            || HanasuInstall.hasProfileLine()
    }

    // MARK: - 入れる・外す

    // 設計判断: DEC-COM-188
    /// /usr/local/bin を先に試し（書けなければ管理者の確認）、だめなら確かめてから ~/.local/bin に入れる
    @MainActor
    private func install(executable: String) {
        message = nil
        defer { refresh += 1 }
        let system = HanasuInstall.systemLink()
        var reason = ""
        if HanasuInstall.linkState(at: system, executable: executable) == .foreign {
            reason = HanasuInstall.InstallError.occupied(system.path).localizedDescription
        } else {
            switch HanasuInstall.installSystemLink(executable: executable) {
            case .done:
                message = tr("%@ に入れました。新しいターミナルで hanasu と打つと使えます。", system.path)
                return
            case .canceled:
                reason = tr("/usr/local/bin への登録を取り消しました。")
            case .failed(let text):
                reason = tr("/usr/local/bin に入れられませんでした: %@", text)
            }
        }

        let alert = NSAlert()
        alert.messageText = tr("管理者の権限なしで、~/.local/bin に入れますか？")
        alert.informativeText = reason + "\n" + tr("ホームフォルダの ~/.local/bin に hanasu のリンクを作ります。管理者の権限は要りません。")
        alert.addButton(withTitle: tr("~/.local/bin に入れる"))
        alert.addButton(withTitle: tr("キャンセル"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try HanasuInstall.installUserLink(executable: executable)
        } catch {
            message = error.localizedDescription
            return
        }
        let user = HanasuInstall.userLink()
        message = tr("%@ に入れました。新しいターミナルで hanasu と打つと使えます。", user.path)

        let shell = HanasuInstall.Shell(path: HanasuInstall.loginShellPath)
        guard shell == .zsh, !HanasuInstall.userDirectoryOnPath(shell: shell) else { return }
        let profile = NSAlert()
        profile.messageText = tr("~/.zprofile に PATH の 1 行を足しますか？")
        profile.informativeText = tr("新しいターミナルで hanasu と打って使えるように、~/.zprofile の終わりに次の行を足します。「PATH から外す」で消せます。")
            + "\n\n" + HanasuInstall.exportLine
        profile.addButton(withTitle: tr("足す"))
        profile.addButton(withTitle: tr("足さない"))
        guard profile.runModal() == .alertFirstButtonReturn else { return }
        do {
            try HanasuInstall.addProfileLine()
        } catch {
            message = error.localizedDescription
        }
    }

    @MainActor
    private func remove(executable: String) {
        message = nil
        defer { refresh += 1 }
        let alert = NSAlert()
        alert.messageText = tr("hanasu を PATH から外しますか？")
        alert.informativeText = tr("Hanasu が作ったリンクと、~/.zprofile に足した行を消します。絶対パスで登録した MCP は、そのまま使えます。")
        alert.addButton(withTitle: tr("外す"))
        alert.addButton(withTitle: tr("キャンセル"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var problems: [String] = []
        switch HanasuInstall.removeSystemLink(executable: executable) {
        case .done, .canceled: break
        case .failed(let text): problems.append(text)
        }
        do { try HanasuInstall.removeUserLink(executable: executable) } catch { problems.append(error.localizedDescription) }
        do { try HanasuInstall.removeProfileLine() } catch { problems.append(error.localizedDescription) }
        message = problems.isEmpty ? tr("PATH から外しました。") : problems.joined(separator: "\n")
    }
}

/// 名前・値（等幅で選べる）・コピーのボタン
private struct CopyableValue: View {
    let title: String
    let value: String
    let disabled: Bool
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Spacer()
                CopyButton(value: value).disabled(disabled)
            }
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .foregroundStyle(disabled ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
            if let note {
                Text(note).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// クリップボードにコピーし、少しの間「コピーしました」と出す
private struct CopyButton: View {
    let value: String
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
        } label: {
            Label(copied ? tr("コピーしました") : tr("コピー"), systemImage: copied ? "checkmark" : "doc.on.doc")
        }
        .controlSize(.small)
    }
}
