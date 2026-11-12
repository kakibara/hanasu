import AppKit
import SwiftUI

// 設定画面の「コマンドと MCP」（計画は docs/plans/cli.md の段階 4。E3〜E5・E7）。
// 中身の処理（リンク・シェルの設定・登録の文）は HanasuInstall.swift。

// 要件: REQ-COM-190, REQ-COM-191, REQ-COM-192, REQ-COM-193, REQ-COM-194
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

            AgentConnectSection(executable: SettingsRenderOverrides.agentConnect?.executable ?? executable,
                                connectBlocked: registrationBlocked || mcpDisabled)

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

// MARK: - AI アプリにつなぐ

// 要件: REQ-COM-194
// 設計判断: DEC-COM-202, DEC-COM-204, DEC-COM-205
/// Claude Desktop（設定の場所ごと）・ChatGPT（Codex）・Claude Code に、hanasu の MCP をボタンでつなぐ・外す。中身は AgentConnect.swift
struct AgentConnectSection: View {
    let executable: String
    /// App Translocation・DisableCLI・DisableMCP のとき（つなぐボタンを押せない。外すのはできる）
    let connectBlocked: Bool

    @State private var rows: [AgentConnect.Row] = []
    @State private var loaded = false
    @State private var busy: AgentConnect.Target?
    @State private var messages: [AgentConnect.Target: String] = [:]

    private var environment: AgentConnect.Environment { SettingsRenderOverrides.agentConnect?.environment ?? .live }

    var body: some View {
        Section {
            if !loaded {
                ProgressView().controlSize(.small)
            }
            ForEach(rows) { row in
                rowView(row)
            }
        } header: {
            Text(tr("AI アプリにつなぐ"))
        } footer: {
            Text(tr("MCP で返した会議の中身は、MCP を使うエージェントと、その AI の提供元に渡ります。ask_meetings は、会議の中身を hanasu ask と同じ AI（hanasu doctor の ask の行）にも送ります。"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .task { await reload() }
    }

    @ViewBuilder
    private func rowView(_ row: AgentConnect.Row) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(row))
                    Text(abbreviated(row.file.path))
                        .font(.caption).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                if busy == row.target {
                    ProgressView().controlSize(.small)
                }
                if row.state.removable {
                    Button(tr("外す…")) { disconnect(row) }
                        .disabled(busy != nil)
                }
                if row.state != .connected {
                    Button(tr("つなぐ…")) { connect(row) }
                        .disabled(busy != nil || connectBlocked || !row.found)
                }
            }
            Label(stateText(row), systemImage: icon(row))
                .font(.callout)
                .foregroundStyle(color(row))
                .fixedSize(horizontal: false, vertical: true)
            ForEach(notes(row), id: \.self) { note in
                Text(note).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if busy == row.target {
                Text(tr("登録しています…")).font(.caption).foregroundStyle(.secondary)
            } else if let message = messages[row.target] {
                Text(message).font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - 文

    private func title(_ row: AgentConnect.Row) -> String {
        switch row.target {
        case .claudeDesktop(let dir):
            dir.lastPathComponent == "Claude" ? "Claude Desktop" : tr("Claude Desktop（%@）", dir.lastPathComponent)
        case .codex: tr("ChatGPT（Codex）")
        case .claudeCode: tr("Claude Code（ターミナルと Claude Desktop の Code）")
        }
    }

    /// 確かめ・結果の文で使うアプリの名前
    private func appName(_ row: AgentConnect.Row) -> String {
        switch row.target {
        case .claudeDesktop: title(row)
        case .codex: "ChatGPT"
        case .claudeCode: "Claude Code"
        }
    }

    /// ホームの下は ~ で書く（描画の架空のホームも）
    private func abbreviated(_ path: String) -> String {
        let home = environment.home.standardizedFileURL.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    private func stateText(_ row: AgentConnect.Row) -> String {
        if !row.found { return tr("%@ が見つかりません", appName(row)) }
        return stateText(row.state)
    }

    private func stateText(_ state: AgentConnect.State) -> String {
        switch state {
        case .connected: return tr("つないでいます")
        case .notConnected: return tr("つないでいません")
        case .other: return tr("別の場所の Hanasu を指しています（つなぎ直すと、このアプリを指します）")
        case .foreign(let command): return tr("Hanasu のものでない hanasu が登録されています（%@）", command)
        case .unreadable(let problem): return tr("設定ファイルを読めません: %@", problemText(problem))
        }
    }

    private func problemText(_ problem: AgentConnect.Problem) -> String {
        switch problem {
        case .invalidJSON: tr("JSON として読めません")
        case .unexpectedShape: tr("思っていた形ではありません")
        case .tomlUnsupported: tr("mcp_servers をこの書き方で書いたファイルは、Hanasu では書き換えられません")
        case .io(let message): message
        }
    }

    private func icon(_ row: AgentConnect.Row) -> String {
        guard row.found else { return "questionmark.circle" }
        switch row.state {
        case .connected: return "checkmark.circle.fill"
        case .notConnected: return "circle"
        case .other, .foreign, .unreadable: return "exclamationmark.triangle.fill"
        }
    }

    private func color(_ row: AgentConnect.Row) -> Color {
        guard row.found else { return .secondary }
        switch row.state {
        case .connected: return .green
        case .notConnected: return .secondary
        case .other, .foreign, .unreadable: return .orange
        }
    }

    private func notes(_ row: AgentConnect.Row) -> [String] {
        var notes: [String] = []
        if case .unreadable = row.state, row.found {
            notes.append(tr("下の MCP の欄の内容を、手で足してください。"))
        }
        switch row.target {
        case .codex:
            notes.append(tr("ChatGPT のふつうのチャットでは、今は使えません（OpenAI の不具合）。Codex で使えます。"))
        case .claudeCode:
            if row.claudePath == nil { notes.append(tr("Claude Code は見つかりませんでした。入れると、この登録が使われます。")) }
            if row.projectEntry { notes.append(tr("一部のフォルダだけの登録もあります（claude mcp add をスコープなしで動かしたもの）。")) }
        case .claudeDesktop: break
        }
        return notes
    }

    // MARK: - つなぐ・外す

    private func reload() async {
        let environment = environment
        let executable = executable
        let result = await Task.detached { AgentConnect.rows(env: environment, executable: executable) }.value
        rows = result
        loaded = true
    }

    @MainActor
    private func connect(_ row: AgentConnect.Row) {
        messages[row.target] = nil
        if row.running {
            messages[row.target] = tr("%@ を終了してから、もう一度押してください。", appName(row))
            return
        }
        let alert = NSAlert()
        alert.messageText = tr("%@ に Hanasu をつなぎますか？", appName(row))
        if case .claudeCode = row.target, row.claudePath != nil {
            alert.informativeText = tr("Claude Code の claude mcp add で、どのフォルダからも使える hanasu を登録します。")
        } else {
            alert.informativeText = tr("次のファイルに hanasu を足します。書く前のファイルは、同じフォルダに %@ として写しておきます。\n\n%@",
                                       row.file.lastPathComponent + AgentConnect.backupSuffix, abbreviated(row.file.path))
        }
        alert.addButton(withTitle: tr("つなぐ"))
        alert.addButton(withTitle: tr("キャンセル"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var overwrite = false
        if case .foreign(let command) = row.state {
            guard confirmOverwrite(command) else { return }
            overwrite = true
        }
        let replace = overwrite
        perform(row, connecting: true) { env, exe in
            AgentConnect.connect(row, env: env, executable: exe, overwrite: replace)
        }
    }

    @MainActor
    private func confirmOverwrite(_ command: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = tr("Hanasu のものでない hanasu が登録されています（%@）", command)
        alert.informativeText = tr("今の登録（%@）を、Hanasu に置き換えますか？", command)
        alert.addButton(withTitle: tr("置き換える"))
        alert.addButton(withTitle: tr("キャンセル"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    @MainActor
    private func disconnect(_ row: AgentConnect.Row) {
        messages[row.target] = nil
        if row.running {
            messages[row.target] = tr("%@ を終了してから、もう一度押してください。", appName(row))
            return
        }
        let alert = NSAlert()
        alert.messageText = tr("%@ から Hanasu を外しますか？", appName(row))
        alert.informativeText = tr("Hanasu の hanasu の登録だけを消します。")
        alert.addButton(withTitle: tr("外す"))
        alert.addButton(withTitle: tr("キャンセル"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        perform(row, connecting: false) { env, exe in
            AgentConnect.disconnect(row, env: env, executable: exe)
        }
    }

    /// 画面を止めずに動かし（claude は数秒かかる）、終わったら結果を出して読み直す
    @MainActor
    private func perform(_ row: AgentConnect.Row, connecting: Bool,
                         _ action: @escaping @Sendable (AgentConnect.Environment, String) -> AgentConnect.Outcome) {
        busy = row.target
        let environment = environment
        let executable = executable
        Task { @MainActor in
            let outcome = await Task.detached { action(environment, executable) }.value
            busy = nil
            messages[row.target] = outcomeText(outcome, row: row, connecting: connecting)
            await reload()
        }
    }

    private func outcomeText(_ outcome: AgentConnect.Outcome, row: AgentConnect.Row, connecting: Bool) -> String {
        switch outcome {
        case .done:
            if !connecting { return tr("外しました。%@ を開き直すと反映されます。", appName(row)) }
            if case .claudeCode = row.target {
                return tr("つなぎました。新しい Claude Code のセッションから使えます。初めて会議を読むときに「書類」フォルダへのアクセスを求められたら、許可してください。")
            }
            return tr("つなぎました。%@ を開き直すと使えます。初めて会議を読むときに、macOS が「書類」フォルダへのアクセスを求めたら、許可してください。", appName(row))
        case .unchanged: return tr("すでにつないでいます。")
        case .nothing: return tr("外す登録がありません。")
        case .needsOverwrite(let command): return tr("Hanasu のものでない hanasu が登録されています（%@）", command)
        case .running: return tr("%@ を終了してから、もう一度押してください。", appName(row))
        case .unreadable(let problem):
            return tr("設定ファイルを読めません: %@", problemText(problem)) + "\n" + tr("下の MCP の欄の内容を、手で足してください。")
        case .failed(let message): return tr("書き換えられませんでした: %@", message)
        case .timedOut: return tr("claude コマンドが 30 秒で終わらなかったので、打ち切りました。")
        }
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
