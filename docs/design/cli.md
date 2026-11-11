# `hanasu` コマンドの作り（Mac）

利用者向けの `hanasu` コマンドが、今どう作られているか。要件は spec の REQ-COM-180〜193・REQ-MTG-120〜127・REQ-DIC-160〜162、計画（まだ作っていない段階）は [plans/cli.md](../plans/cli.md)。オプションの一覧は `hanasu help` が正で、ここには写さない。

## 1. 入り口

- アプリと同じ実行ファイル。`main.swift` の最初で `HanasuCommand.handles` が振り分け、`HanasuCommand.main` に入る（DEC-COM-180）。`NSApplication`・`AppDelegate` は作らないので、起動時の処理（記録中の会議を「失敗」にする `MeetingStore.markInterruptedMeetings`、前回のローカルの AI のサーバーの片付け）は通らない。
- `HanasuCommand.main` は、シンボリックリンクから起動されたら実際のパスで `execv` し直し（`reexecIfSymlinked`。DEC-COM-183）、終了時とシグナルでローカルの AI のサーバーを止める用意をして（`stopLocalServerOnExit`。DEC-COM-184）、`HanasuCommand.run` を動かす。
- `run` は、`-AppleLanguages` などの Foundation の引数を除き、ポリシー `DisableCLI` を見てから、コマンドごとの関数に渡す。誤りは `HanasuCommandError`（終了コードと文）で返し、`run` が stderr に出す。

## 2. ファイル

| ファイル | 中身 |
| --- | --- |
| `HanasuCommand.swift` | 振り分け・終了コード（`HanasuExit`）・出力（`HanasuOutput`・`HanasuJSON`）・引数の読み取り（`HanasuArguments`）・ポリシー（`HanasuPolicy`）・ヘルプ（`HanasuHelp`） |
| `HanasuMeetingsCommand.swift` | `meetings list / show / search`・`actions`。会議のフォルダ・会議の指定（`resolve`）・期間（`HanasuPeriod`）・外向きの JSON |
| `HanasuAICommands.swift` | `ask`・`refine`・`edit`・`dict apply`。AI の選び方と送る前の確かめ（`HanasuAI`）、文章の受け取り方（`HanasuTextInput`） |
| `HanasuDoctorCommand.swift` | `doctor` |
| `HanasuMCPServer.swift` | `mcp`。stdio の JSON-RPC の読み書きと、MCP の手順（新旧の版） |
| `HanasuMCPTools.swift` | MCP のツールの定義（英語の説明・`inputSchema`・注釈）と呼び出し |
| `HanasuInstall.swift` | 配る部分。PATH へのリンク（`/usr/local/bin`・`~/.local/bin`）と `~/.zprofile` の 1 行、App Translocation の判定、MCP の登録の文（Claude Code のコマンド・Claude Desktop の JSON） |
| `CommandLineSettingsView.swift` | 設定画面の「コマンドと MCP」（`CommandLineSettingsTab`） |
| `HanasuShared.swift` | Windows 版と共有のファイル（`Resources/Command/hanasu.json`。DEC-COM-191）を読む。MCP の英語の文・エージェントへの説明・既定の文体の一覧 |
| `HanasuCommandCLI.swift` | 開発用の自己テスト（`--test-hanasu-command`）と速さの測定（`--bench-hanasu-command`） |
| `HanasuGoldenCLI.swift` | 共有のテストデータ（`common/testdata/cli`。DEC-COM-192）を動かし、期待する出力を書く（`--write-cli-golden`）・比べる |

名前が `CLI.swift` で終わるファイルは訳の検査の外なので、利用者に見える文はそれ以外のファイルに置き、`tr()` で書く。

## 3. 会議を読む

- `HanasuMeetingsCommand.load` が `MeetingStore.loadAllReporting(in:)` で全会議を並べて読み（DEC-MTG-123）、読んだ会議と読めない会議の名前を `HanasuLoadedMeetings` で返す。読めないフォルダは、会議がないことと区別して終了コード 5 にする（REQ-COM-185）。読めない会議（DEC-MTG-153）の数は、`--json` と MCP の結果では `unreadableMeetingCount`、文の出力では `warnIfUnreadable` が stderr に出す。指定した会議が読めない会議なら、`resolve(_:in:)` が 5 にする。
- 出す前に `Meeting.withUsedUtterancesOnly` で、議事録に使わない発言（除いた発言・オフレコ）を外す（DEC-MTG-121）。検索は索引を作らない `MeetingSearchIndex.scan`。

## 4. AI を使うコマンド

- AI は `HanasuAI.choice` で決める（`--ai`・`--model`、なければその用途の設定）。`HanasuAI.makeClient` が、ポリシー `AllowedAIProviders`、ローカルならほかのプロセスのサーバー（`LocalLLMServer.otherProcessServerRunning`）、認証情報（`HanasuAI.credentialStatus`）を確かめてから、`TextAIClient.cli` でクライアントを作る（DEC-COM-185）。誤りは `HanasuAI.mapped` で終了コードに分ける。
- `ask`・`ask_meetings` の AI は `HanasuAI.askPurpose`（「AI チャット・質問」を保存した人は `chat`、ほかは `meeting`。DEC-COM-190）。保存したかは `AppSettings.isChatAIProviderSaved`。自己テストは、子プロセスの設定を `HANASU_TEST_DEFAULTS_SUITE` の suite（`SettingsDefaults`）に差し替えて確かめる。
- `ask` は `MeetingAsk.gatherContext` に、検索の仕方として `MeetingSearchIndex.scan` と、指定した期間（`MeetingAsk.Options.period`）を渡し（DEC-MTG-124）、`MeetingAsk.answer` で聞く。アプリの「会議に質問」と同じプロンプト。
- `refine` は音声入力と同じ `GeminiClient.Request` を作り（辞書・追加のルール・出力の言語・`--app` / `--style` の文体）、`TextAIClient.refine` か `translate` に渡す。`edit` は `TextAIClient.editSelection`。どちらも `DictationHistoryStore` には書かない。失敗したら stdout に出さず、`--fallback-raw` のときだけ原文を出す（DEC-DIC-161）。
- 文章は `HanasuTextInput.read` が、位置の引数か stdin のどちらかから受け取る（DEC-DIC-160）。

## 5. MCP（`hanasu mcp`）

- `HanasuMCPServer.run` は、ポリシー `DisableMCP` を見てから、本当の stdout を `dup` で複製し、1 番を stderr に付け替える。JSON-RPC は複製した番号にだけ書くので、ほかのコードや子プロセスが stdout に書いても接続は壊れない（DEC-COM-186）。
- stdin を別のスレッドで読み、`\n` で区切る（`AsyncLineSequence` は U+2028 でも切るので使わない）。1 行ごとに `Task` で処理し（`notifications/cancelled` で取り消せる）、stdin が閉じたら処理中のものを待って終わる。
- `handle` が手順を分ける。`_meta` に `io.modelcontextprotocol/protocolVersion` があれば 2026-07-28 の形（結果に `resultType` とサーバーの名前）、なければ前の版の形で応える。`initialize`・`server/discover`・`ping`・`tools/list`・`tools/call`。
- 処理中のリクエストは `running` に置き、`start` がロックの中で登録する。`Task` の後片付けもロックを取るので、先に終わった `Task` が残って、stdin が閉じたあとの待ちが終わらなくなることはない。
- ツールは `HanasuMCPTools`。中身はコマンドと同じ関数（`HanasuMeetingsCommand.meetingJSON`・`searchResultJSON`・`actionItems`、`HanasuAICommands.ask`）で作るので、`--json` と同じ形になる。件数・長さの上限と続きの取り方（`nextOffset`・`transcriptNextFrom`）は DEC-MTG-125。引数の値の誤りは `isError` の結果で返す。

## 6. ローカルの AI のサーバー

- `LocalLLMServer` は、起動したプロセスごとに記録（`server-<持ち主の pid>.pid`）を書く。`hanasu` は、ほかの持ち主のサーバーが動いていれば起動しない。アプリの起動時の `cleanUpStaleServer` は、持ち主が終わっている記録のサーバーだけを止める（DEC-COM-184）。

## 7. 配る（設定画面の「コマンドと MCP」）

- 実行ファイルのパスは `HanasuInstall.executablePath`（リンクをたどった先）。登録の文（`claudeCodeCommand`・`claudeDesktopJSON`）も、`doctor` と設定画面で同じ関数から作る（REQ-COM-190）。
- 「PATH に入れる…」は `CommandLineSettingsTab.install`。`HanasuInstall.installSystemLink` が `/usr/local/bin` に直接作り、書けなければ AppleScript の管理者の確認を出す。取り消し・失敗なら、確かめてから `installUserLink`（`~/.local/bin`）と、zsh なら `addProfileLine`（`~/.zprofile`。印の行つき）。触るのは `linkState` が `current`・`otherHanasu` のリンクだけ（DEC-COM-188）。
- アプリからはターミナルの PATH が見えないので、`~/.local/bin` が PATH にあるかは、シェルの設定ファイルに `.local/bin` が書いてあるかで見る（`userDirectoryOnPath`）。`doctor` はターミナルから呼ばれるので、本当の `PATH` を見る。
- App Translocation（`isTranslocated`。DEC-COM-189）なら、知らせを出し、PATH とコピーのボタンを使えなくする。`DisableCLI` でも使えなくし、`DisableMCP` なら登録のしかたの代わりに止められていることを出す。
- エージェントへの説明は `HanasuHelp.agentGuide`（英語で固定。DEC-COM-187）。`hanasu help agent` と設定画面で同じ文を出す。

## 8. 確かめ方

- `.build/debug/Hanasu --test-hanasu-command`: 架空の会議と偽の `fm`（`HANASU_FM_PATH`）を使い、本物の実行ファイルをコマンドとして呼んで確かめる。ネットワークには送らない。キーチェーンは自己テストの一時的な項目（`HANASU_KEYCHAIN_SERVICE` で、`…selftest-` の名前だけを読ませられる）を、シンボリックリンク経由の `doctor` で読む。
- MCP は、`hanasu mcp` を子プロセスで動かし、新旧の版の手順・ツール・エラー・長い会議の切り方・ポリシーを確かめる（同じ自己テスト）。
- 配る部分は、一時フォルダをホームに見立てて、リンクと `~/.zprofile` の行を作って外し、登録の文・doctor・`help agent` を確かめる（同じ自己テスト）。画面は `--render-settings <フォルダ> --pane commandLine`（UX-183）。`/usr/local/bin` への管理者の確認と App Translocation は実機（UX-184）。
- 共有のテストデータ（DEC-COM-192）: 同じ自己テストの最後に、`common/testdata/cli/cases.json` のコマンドを動かし、`expected.json` と比べる（リポジトリのルートで動かす）。子プロセスの設定は `SettingsDefaults`（`HANASU_TEST_DEFAULTS_SUITE`）、「今」と乱数は `HanasuClock` が読む。期待する出力を書き直すのは `--write-cli-golden`。Windows 版も同じデータで比べる。
- `.build/debug/Hanasu --bench-hanasu-command [件数]`: 架空の会議での速さ。
