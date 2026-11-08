import Foundation

// 利用者向けの `hanasu` コマンド（計画は docs/plans/cli.md）。
// アプリと同じ実行ファイルのサブコマンドで、`hanasu` はその実行ファイルへのシンボリックリンク。
// 開発用の CLI（`--` で始まるフラグ。main.swift と *CLI.swift）とは別のもので、出力は表示の言語に訳す。
// このファイルと HanasuMeetingsCommand.swift は、名前が CLI.swift で終わらないので、訳の検査（check-i18n.py）の対象になる。

// 要件: REQ-COM-182
/// 終了コード。スクリプトやエージェントが、失敗の理由で分けられるようにする
enum HanasuExit: Int32 {
    case ok = 0
    /// 失敗（AI の失敗など）
    case failure = 1
    /// 使い方の誤り
    case usage = 2
    /// 認証情報・モデルがない
    case credentials = 3
    /// 会議が見つからない・1 つに決まらない
    case notFound = 4
    /// 管理者のポリシーで止められている・会議のフォルダを読む権限がない
    case denied = 5
}

/// コマンドを止める誤り。message は stderr に出し、details はその下に 1 行ずつ出す
struct HanasuCommandError: Error {
    var exit: HanasuExit
    var message: String
    var details: [String] = []
}

// 要件: REQ-COM-180
// 設計判断: DEC-COM-180
enum HanasuCommand {
    /// 最初の引数がこれなら、実行ファイルの名前が何でもサブコマンドとして扱う
    static let commandNames: Set<String> = ["help", "meetings", "actions"]
    static let topLevelFlags: Set<String> = ["--version", "--help", "-h"]

    /// コマンドとして呼ばれたか。`hanasu`（シンボリックリンクの名前）で呼ばれたら、引数が何でもコマンドとして扱う。
    /// アプリの実行ファイル（Hanasu）を直接呼んだときは、最初の引数がサブコマンドのときだけ
    static func handles(_ arguments: [String]) -> Bool {
        if isCommandName(arguments.first) { return true }
        guard arguments.count >= 2 else { return false }
        return commandNames.contains(arguments[1]) || topLevelFlags.contains(arguments[1])
    }

    static func isCommandName(_ argv0: String?) -> Bool {
        guard let argv0 else { return false }
        return (argv0 as NSString).lastPathComponent == "hanasu"
    }

    // 要件: REQ-COM-183
    /// コマンドを実行して終える。アプリ（NSApplication・AppDelegate）は起動しない。
    /// 起動時の処理（`MeetingStore.markInterruptedMeetings`）を通らず、会議のファイルを書き換えない
    static func main(_ arguments: [String]) -> Never {
        reexecIfSymlinked(arguments)
        Task.detached {
            let code = await run(Array(arguments.dropFirst()))
            exit(code.rawValue)
        }
        dispatchMain()
    }

    // 設計判断: DEC-COM-183
    /// シンボリックリンク（/usr/local/bin/hanasu など）から起動したときは、リンクをたどった先の実際のパスで起動し直す。
    /// macOS は起動したときのパス（リンクのまま）から Bundle.main を決めるので、リンク経由だと .app として解決されず、
    /// 訳（Localizable.xcstrings）・アプリの設定・管理者のポリシーのドメインを読めない。
    /// argv[0] は変えない（`hanasu` という名前で呼ばれたことを、起動し直したあとも分かるように）
    static func reexecIfSymlinked(_ arguments: [String]) {
        var size = UInt32(MAXPATHLEN)
        var buffer = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&buffer, &size) == 0 else { return }
        let invoked = URL(fileURLWithPath: String(cString: buffer)).standardizedFileURL
        let resolved = invoked.resolvingSymlinksInPath()
        guard resolved.path != invoked.path else { return }
        var argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) }
        argv.append(nil)
        execv(resolved.path, argv)
        // 起動し直せなければ、そのまま続ける（訳と設定は読めないが、会議は読める）
        HanasuOutput.err("hanasu: exec \(resolved.path): \(String(cString: strerror(errno)))")
    }

    /// 引数（実行ファイルの名前を除く）を実行し、終了コードを返す
    static func run(_ arguments: [String]) async -> HanasuExit {
        let arguments = HanasuArguments.droppingFoundationDefaults(arguments)
        do {
            // 要件: REQ-COM-184
            if HanasuPolicy.cliDisabled {
                throw HanasuCommandError(
                    exit: .denied,
                    message: tr("管理者のポリシーで、hanasu コマンドは使えないようにされています（%@）。", HanasuPolicy.Key.disableCLI.rawValue))
            }
            guard let command = arguments.first else {
                HanasuOutput.out(HanasuHelp.full())
                return .ok
            }
            let rest = Array(arguments.dropFirst())
            switch command {
            case "help":
                HanasuOutput.out(rest.first.flatMap(HanasuHelp.section(for:)) ?? HanasuHelp.full())
                return .ok
            case "--help", "-h":
                HanasuOutput.out(HanasuHelp.full())
                return .ok
            case "--version":
                HanasuOutput.out("hanasu \(version)")
                return .ok
            case "meetings":
                return try await HanasuMeetingsCommand.runMeetings(rest)
            case "actions":
                return try await HanasuMeetingsCommand.runActions(rest)
            default:
                throw HanasuCommandError(exit: .usage, message: tr("知らないコマンドです: %@", command),
                                         details: [tr("使い方は hanasu help で表示できます。")])
            }
        } catch let error as HanasuCommandError {
            HanasuOutput.err("hanasu: " + error.message)
            for line in error.details { HanasuOutput.err("  " + line) }
            return error.exit
        } catch {
            HanasuOutput.err("hanasu: " + error.localizedDescription)
            return .failure
        }
    }

    /// アプリの版（Info.plist）。.app の外で動かしたとき（swift build のまま）は dev
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}

// 要件: REQ-COM-181
/// stdout には結果だけを出し、途中経過・警告・エラーは stderr に出す
enum HanasuOutput {
    static func out(_ text: String) {
        FileHandle.standardOutput.write(Data((text.hasSuffix("\n") ? text : text + "\n").utf8))
    }

    static func err(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }

    // 要件: REQ-COM-181
    // 設計判断: DEC-COM-181
    /// `--json` の出力。どの形にも版（schemaVersion）を付け、キーは英語で並びを固定する
    static func json(_ object: [String: Any]) throws {
        var object = object
        object["schemaVersion"] = HanasuJSON.schemaVersion
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        out(String(decoding: data, as: UTF8.self))
    }
}

// 設計判断: DEC-COM-181
enum HanasuJSON {
    /// 項目を消したり意味を変えたりするときに上げる（足すだけなら上げない）
    static let schemaVersion = 1

    /// ISO 8601 で、時差を付ける（例: 2026-11-02T13:12:00+09:00）
    static func date(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = .current
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    /// 秒を小数 2 桁までにする（JSON に長い小数を出さない）
    static func seconds(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    static func optional(_ value: Any?) -> Any {
        value ?? NSNull()
    }
}

/// コマンドの引数（位置の引数・値のない旗・値のあるオプション）
struct HanasuArguments {
    var positionals: [String] = []
    var flags: Set<String> = []
    var values: [String: String] = [:]

    /// - Parameters:
    ///   - flags: 値を取らないオプション（`--json` など）
    ///   - options: 値を取るオプション（`--limit 10` か `--limit=10`）
    static func parse(_ arguments: [String], flags: Set<String>, options: Set<String>) throws -> HanasuArguments {
        var result = HanasuArguments()
        var index = 0
        var onlyPositionals = false
        while index < arguments.count {
            let argument = arguments[index]
            index += 1
            if onlyPositionals || !argument.hasPrefix("-") || argument == "-" {
                result.positionals.append(argument)
                continue
            }
            if argument == "--" {
                onlyPositionals = true
                continue
            }
            let name: String
            var inlineValue: String?
            if let equals = argument.firstIndex(of: "=") {
                name = String(argument[..<equals])
                inlineValue = String(argument[argument.index(after: equals)...])
            } else {
                name = argument
            }
            if flags.contains(name), inlineValue == nil {
                result.flags.insert(name)
            } else if options.contains(name) {
                if let inlineValue {
                    result.values[name] = inlineValue
                } else if index < arguments.count {
                    result.values[name] = arguments[index]
                    index += 1
                } else {
                    throw HanasuCommandError(exit: .usage, message: tr("%@ には値が要ります。", name))
                }
            } else {
                throw HanasuCommandError(exit: .usage, message: tr("知らないオプションです: %@", argument),
                                         details: [tr("使い方は hanasu help で表示できます。")])
            }
        }
        return result
    }

    /// macOS のアプリの決まりの `-AppleLanguages (en)` のような引数（Foundation が設定として読む）を除く。
    /// 表示の言語をその回だけ変えるのに使える
    static func droppingFoundationDefaults(_ arguments: [String]) -> [String] {
        var result: [String] = []
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument.hasPrefix("-Apple") || argument.hasPrefix("-NS") {
                index += 2
                continue
            }
            result.append(argument)
            index += 1
        }
        return result
    }

    func int(_ name: String) throws -> Int? {
        guard let raw = values[name] else { return nil }
        guard let value = Int(raw), value > 0 else {
            throw HanasuCommandError(exit: .usage, message: tr("%@ には 1 以上の整数を指定してください: %@", name, raw))
        }
        return value
    }
}

// 要件: REQ-COM-184
// 設計判断: DEC-COM-182
/// 管理者のポリシー。構成プロファイル（MDM）で配った、アプリのドメインの管理された設定だけを見る。
/// ユーザーが `defaults write` で書いた値は効かない（管理されていない値は無視する）
enum HanasuPolicy {
    enum Key: String {
        /// true なら hanasu コマンドを使わせない
        case disableCLI = "DisableCLI"
    }

    /// アプリの設定のドメイン（シンボリックリンク経由でも、.app の外でも同じものを見る）
    static var domain: String { Bundle.main.bundleIdentifier ?? "dev.mactypeless.Hanasu" }

    /// 自己テストで差し替える（nil なら本物の管理された設定を読む）
    nonisolated(unsafe) static var testValues: [String: Any]?

    static func forcedValue(_ key: Key) -> Any? {
        if let testValues { return testValues[key.rawValue] }
        guard CFPreferencesAppValueIsForced(key.rawValue as CFString, domain as CFString) else { return nil }
        return CFPreferencesCopyAppValue(key.rawValue as CFString, domain as CFString)
    }

    static var cliDisabled: Bool { (forcedValue(.disableCLI) as? Bool) == true }

    /// 効いているポリシー（キー → 値）。doctor で出す
    static var active: [String: Any] {
        var result: [String: Any] = [:]
        for key in [Key.disableCLI] {
            if let value = forcedValue(key) { result[key.rawValue] = value }
        }
        return result
    }
}

/// ヘルプ。オプションの名前とコマンドは訳さず、説明だけを表示の言語にする
enum HanasuHelp {
    static func full() -> String {
        var lines = [tr("hanasu — Hanasu の会議の記録を、ターミナルや AI エージェントから読む"), "", tr("使い方:")]
        lines += meetingsUsage + actionsUsage
        lines += [
            "  hanasu help [meetings|actions]",
            "  hanasu --version",
            "",
        ]
        lines += commonNotes
        return lines.joined(separator: "\n")
    }

    static func section(for command: String) -> String? {
        switch command {
        case "meetings": return ([tr("使い方:")] + meetingsUsage + commonNotes).joined(separator: "\n")
        case "actions": return ([tr("使い方:")] + actionsUsage + commonNotes).joined(separator: "\n")
        default: return nil
        }
    }

    private static var period: String { tr("<期間>") }
    private static var count: String { tr("<件数>") }

    private static var meetingsUsage: [String] {
        [
            "  hanasu meetings list [--since \(period)] [--until \(period)] [--limit \(count)] [--json]",
            "      " + tr("会議を新しい順に並べる"),
            "  hanasu meetings show \(tr("<会議>")) [--transcript | --notes | --actions | --all] [--json]",
            "      " + tr("会議の中身を出す（既定は議事録）"),
            "  hanasu meetings search \(tr("<語>"))... [--since \(period)] [--until \(period)] [--limit \(count)] [--json]",
            "      " + tr("会議を横断して検索する（空白で区切ると、すべてを含むものだけ）"),
        ]
    }

    private static var actionsUsage: [String] {
        [
            "  hanasu actions [--since \(period)] [--until \(period)] [--owner \(tr("<名前>"))] [--limit \(count)] [--json]",
            "      " + tr("会議をまたいでアクションアイテムを並べる"),
        ]
    }

    private static var commonNotes: [String] {
        [
            tr("会議の指定: ID（例: 2026-11-02_1312）、latest（最新の完了した会議）、日付（例: 2026-11-02）"),
            tr("期間の指定: 7d・24h・2w（今からさかのぼる）、日付（例: 2026-11-01）"),
            tr("--json で、決まった形の JSON を出します。--meetings-dir <フォルダ>（か環境変数 HANASU_MEETINGS_DIR）で、会議のフォルダを変えられます。"),
            tr("終了コード: 0 成功、1 失敗、2 使い方の誤り、3 認証情報がない、4 会議が見つからない、5 ポリシーか権限で止められた"),
        ]
    }
}
