# AI アプリにボタン 1 つで Hanasu の会議をつなぐ

- 状態: 実装した（2026-11-12。spec は REQ-COM-194・DEC-COM-200〜205。実機の確かめは docs/verification/ui-runs.md の 13 章）
- PR: 78 の続き（main に入れる前に足す）

## 目的

2026-11-12 の依頼「メインにする前に、Claude や ChatGPT、Anthropic に接続するための設定を簡単にできる画面を追加してください」。同日の答え「A（Hanasu の AI ではなく、会議の DB へのアクセス・検索ができるようにしたい）、推奨で。もしくは CLI コマンドを登録という方法もあるがどちらが良い？」。

今の設定の「コマンドと MCP」（REQ-COM-190）は、Claude Code のコマンドと Claude Desktop の JSON を出してコピーさせるだけで、登録は利用者が自分でする（ターミナルを開く・設定ファイルを探して JSON を手で合わせる）。これを、AI アプリごとにボタン 1 つで登録・解除でき、今つながっているかが分かるようにする。

### MCP と CLI（コマンドの登録）のどちらを使うか

3 つとも MCP にする。CLI の登録（PATH に入れる REQ-COM-191 と、エージェントへの説明 REQ-COM-193）は今のまま残し、シェルで組み合わせたい人が使う。

| アプリ | 使う方法 | 理由 |
| --- | --- | --- |
| Claude Desktop | MCP（設定ファイル） | チャットはシェルのコマンドを動かせないので、MCP しか道がない |
| ChatGPT（Codex） | MCP（`~/.codex/config.toml`） | 同上。下の「ユーザーに聞くこと」 |
| Claude Code | MCP（`claude mcp add --scope user`） | 下の通り |

Claude Code は CLI（スキルを置く）でも動くが、MCP にする理由:

- MCP のツールの説明は、`hanasu mcp` がその場で返す。Hanasu を更新すれば新しい説明になる。スキルは置いたときの写しなので、更新のたびに古くなる。
- Claude Code のサンドボックスを有効にしていると、Bash から動かすコマンドは通信やキーチェーンが絞られ、`hanasu ask`（AI に送る）が失敗しうる。MCP のサーバーはこの制約の外で動く。
- 今の Claude Code は MCP のツールを必要になるまで読み込まない（ツールの検索）ので、つないでおくだけで会話が重くなることはほぼない。
- 登録を Claude Code 自身のコマンドに任せるので、Claude Code が動いていても安全に書ける（`~/.claude.json` は Claude Code が常に書き換えている）。

## ユーザーに聞いたこと（2026-11-12）

答え: 「推奨で。ok」（1 は推奨、2 は了承）。あわせて、ChatGPT の不具合が直ったかを調べた（2026-11-12 の時点で直っていない。openai/codex#38162 は開いたままで、OpenAI からの返事も修正もない。10-29 の macOS 26.1023、11-04 の Windows・Fedora でも再現。Codex では使える）。調べる中で、Windows の ChatGPT（Codex）のアプリが落ちると `config.toml` が NUL で埋まる不具合（openai/codex#26421。アプリが一度に置き換えずに書いている）が見つかったので、ChatGPT（Codex）も動いているあいだは書かないことにした（DEC-COM-202）。

1. **ChatGPT をどう扱うか。** OpenAI の不具合 [openai/codex#38162](https://github.com/openai/codex/issues/38162) は 2026-11-04 の時点でも開いたままで、ChatGPT のデスクトップのアプリは、手元の MCP のサーバーを起動してツールの一覧まで取るのに、ふつうのチャットにはツールを出さない（macOS・Windows で再現）。同じ登録は、ChatGPT のアプリの中の Codex と Codex CLI では使える。この Mac の `/Applications/ChatGPT.app` は、バンドル ID が `com.openai.codex`（Codex を含むアプリ）だった。
   - 推奨: 行の名前を「ChatGPT（Codex）」にし、`~/.codex/config.toml` に登録する。行の下に「ChatGPT のふつうのチャットでは、今は使えません（OpenAI の不具合）。Codex で使えます」と出す。
   - ほか: ChatGPT は今回入れない（roadmap に残す）。または、Web の ChatGPT からも使えるリモートの MCP のサーバーを作る（会議の中身をインターネットに出すことになるので勧めない）。
2. **確かめるために、この Mac の本物の設定ファイルに書いてよいか。** 実装のあと、この Mac の `~/.codex/config.toml`・Claude Desktop の設定・Claude Code に Hanasu を実際につなぎ、写しから戻せることも確かめたい。

## 要件の案

### REQ-COM-194 設定の「コマンドと MCP」から、AI アプリにボタン 1 つで Hanasu をつなぐ・外す（新規）
- 内容: 設定の「コマンドと MCP」の最初に「AI アプリにつなぐ」の節を足し、Claude Desktop・ChatGPT（Codex）・Claude Code の行を並べる。Claude Desktop は、見つかった設定の場所ごとに 1 行（既定の `Claude` と、`Claude-Personal` のように別の場所で動かしているもの）。各行に、今の状態と「つなぐ…」「外す…」のボタンを出す。つなぐときは、何をどこに書くかを確かめてから書き、書いたあとで、使い始めるまでにすること（アプリを開き直す・初めて会議を読むときに macOS が出す「書類」フォルダへのアクセスの確認を許可する）を出す。
  - Claude Desktop: その場所の `claude_desktop_config.json` の `mcpServers` に `hanasu`（実行ファイルの絶対パスと `mcp`）を足す。
  - ChatGPT（Codex）: `~/.codex/config.toml` に `[mcp_servers.hanasu]` の表を足す。
  - Claude Code: `claude mcp add --scope user hanasu -- <絶対パス> mcp` を動かす（外すのは `claude mcp remove --scope user hanasu`）。`claude` が見つからない（Claude Code を入れていない）ときも押せて、`~/.claude.json` の `mcpServers` に直接書く。あとで Claude Code を入れれば使える。
- 受け入れ条件:
  - 状態は次のどれかで、設定画面を開いたときとボタンを押したあとに読み直す。
    - 「つないでいます」
    - 「つないでいません」
    - 「別の場所の Hanasu を指しています（つなぎ直すと、このアプリを指します）」
    - 「Hanasu のものでない hanasu が登録されています」
    - 「設定ファイルを読めません（理由）」
    - 「（アプリ）が見つかりません」
  - つないでも外しても、ほかの項目（ほかの MCP のサーバー、`preferences` などの設定、config.toml のほかの表・コメント・Hanasu の表に利用者が足したキー）は値も意味も変わらない。書く前のファイルを、同じフォルダに元と同じ権限で `<名前>.hanasu-backup` として写す（前の写しは上書き）。書くのは一時ファイルに書いて置き換える形で、途中で止まっても元のファイルが壊れない。設定ファイルがシンボリックリンクなら、リンクは残してリンク先を書き換える。書いたあとの本体の権限は元と同じ。
  - Hanasu のものでない `hanasu` があれば、上書きするかを確かめる。取り消せば何も書かない。
  - ファイルが読めない・JSON として壊れている・config.toml の書き方が読み取れない（DEC-COM-201）ときは、何も書かず、理由と、手で足す内容（今のコピーの欄）を出す。
  - 外すと、Hanasu の項目（DEC-COM-203）だけを消す。Hanasu のものでない `hanasu` は消さない。
  - Claude Desktop はその設定の場所で、ChatGPT（Codex）のアプリは動いているあいだ、つなぐのも外すのも書かずに「（アプリ）を終了してから、もう一度押してください」と出す（DEC-COM-202）。
  - ChatGPT（Codex）の行の下に、「ChatGPT のふつうのチャットでは今は使えません（OpenAI の不具合）。Codex で使えます」と出す。
  - Claude Code の `claude` コマンドは、画面を止めずに動かし、そのあいだはボタンを押せなくして「Claude Code に登録しています…」と出す。30 秒で終わらなければ打ち切って、そのことを出す。失敗したら、その出力（stderr）を出し、状態は読み直したとおりに出す。つなぎ直し（前の項目を外して足す）の途中で足すのに失敗したら、前の項目を元どおりに入れ直す。
  - 「つなぐ…」を押せないとき: アプリが App Translocation で動いている（Mac。REQ-COM-192）、`cli\hanasu.exe` がないか一時フォルダで動いている（Windows）、`DisableCLI` か `DisableMCP`（Mac。Windows のポリシーは FUT-020）。「外す…」は、外せる Hanasu の項目があるときに押せる（ポリシーや場所によらない。ただし、そのアプリが動いていて書けないときは、押すと終了を頼む文を出す）。
  - 節の下に、REQ-COM-190 と同じ「会議の中身がエージェントとその AI の提供元に渡る」文を出す。
- 出典: 2026-11-12 の依頼「メインにする前に、Claude や ChatGPT、Anthropic に接続するための設定を簡単にできる画面を追加してください」、同日の答え「A、推奨で」（了承の日付を足す）
- 関係する要件: REQ-COM-184, REQ-COM-185, REQ-COM-189, REQ-COM-190, REQ-COM-192, REQ-REL-013
- 対象: Mac / Windows
- 実装の場所: Mac は `AgentConnect`（新しいファイル `Sources/Hanasu/AgentConnect.swift`。ファイルの読み書き・状態・`claude` の呼び出し。ホーム・動いているか・`claude` の場所は `AgentConnect.Environment` で受け、テストで差し替える）と `CommandLineSettingsTab`。Windows は `Hanasu.Core.Command.AgentConnect`（新しいファイル `windows/Hanasu.Core/Command/AgentConnect.cs`。同じ形）と `SettingsWindow.CommandLine.cs`・`SettingsWindow.xaml`、動いているかを見る部品（`Hanasu.Windows/Services/AgentApps.cs`）
- 確かめ方: 共有のテストデータ `common/testdata/connect/`（つなぐ前のファイル・操作・つないだ後に期待するファイル・状態）を、Mac は `.build/debug/Hanasu --test-hanasu-command`、Windows は `cd windows && dotnet test Hanasu.Core.Tests`（`AgentConnectTests`）で流す。期待する config.toml は CI で Python の `tomllib` で読めることを確かめる。画面は `.build/debug/Hanasu --render-settings <フォルダ> --pane commandLine --connect-fixture <名前>`（UX-195）。実際に AI アプリから会議を読めることは実機（下の「確かめ方」）

### 変える要件（ユーザーの合意が要る）
- REQ-COM-192: 今「PATH に入れるボタンと、登録のしかたのコピーのボタンを使えなくする」 → 「…と、AI アプリにつなぐボタンを使えなくする」。理由: 仮の場所のパスで登録すると、次に起動したときに動かなくなるのは、つなぐボタンも同じ。
- REQ-COM-190: Claude Code のコピーのコマンドを `claude mcp add hanasu -- …` → `claude mcp add --scope user hanasu -- …` にする（Windows は、PowerShell 5.1 のために `--` を付けない今の形に `--scope user` だけを足す）。理由: `--scope` を付けないと、`claude` を動かしたフォルダ（プロジェクト）だけに登録され、ほかのフォルダの Claude Code からは使えない。

## 設計判断の案

### DEC-COM-200 Claude Desktop は、`.mcpb`（拡張機能）でなく `claude_desktop_config.json` に書いて登録し、設定の場所ごとに扱う
- 決めたこと:
  - Claude Desktop の設定ファイル `claude_desktop_config.json` の `mcpServers.hanasu` に `{"command": <実行ファイルの絶対パス>, "args": ["mcp"]}` を足して登録する。ほかのキーは読んだまま残す（Mac は `JSONSerialization`、Windows は `JsonNode`。キーの並びと字下げは変わることがある）。
  - 設定の場所は、Mac は `~/Library/Application Support/` の、Windows は `%APPDATA%\` の、`Claude` と `Claude-` で始まるフォルダのうち `claude_desktop_config.json` があるもの（`Claude` はファイルがなくてもフォルダがあれば）。ただし、設定に `deploymentMode` のキーがあるフォルダ（Claude Desktop が配置のモードのために自分で作る `Claude-3p` など。起動の引数で選ぶものではない）は出さない。Windows のストアの版で `%LOCALAPPDATA%\Packages\Claude_*\LocalCache\Roaming\Claude` があれば、`%APPDATA%\Claude` の代わりにそちら。行の名前は、`Claude` なら「Claude Desktop」、ほかは「Claude Desktop（フォルダの名前）」。
- 理由:
  - 質問のときは `.mcpb` を推奨したが、調べ直すと次のことが分からなかった。
    - `.mcpb` の `command` に束の外の絶対パスを書いてよいか（仕様の例は束の中の相対パスだけで、「自己完結」と書いてある）。
    - 署名のない `.mcpb` の扱い、入れ直したときに置き換わるか、会社の管理で拡張機能の許可リストが有効なときに入れられるか。
    - 入れたかどうかを Hanasu から確かめる決まった方法。
  - `mcpServers` は Anthropic の手引きにある決まった形で、状態を読んで確かめられ、外すのも同じ場所でできる。
  - 同じ Claude.app を `--user-data-dir` で別の場所を指して動かす人がいる（この Mac にも `Claude-Personal`・`Claude-3p` がある）。既定の場所にだけ書くと、ふだん使っている Claude では使えない。
  - `.mcpb` は、仕様が上の点をはっきりさせたら考え直す（roadmap に FUT として残す）。
- 決めた場面: 2026-11-12 の依頼と答え（この計画）。敵対的レビューの指摘
- 関係する要件: REQ-COM-194
- 対象: Mac / Windows

### DEC-COM-201 config.toml は、TOML を全部は読まず、`hanasu` の表だけを行で扱う
- 決めたこと: `~/.codex/config.toml`（Windows は `%USERPROFILE%\.codex\config.toml`）を行で読む。
  - つなぐ: 印の行 `# Added by Hanasu` と `[mcp_servers.hanasu]`・`command = "<パス>"`・`args = ["mcp"]`・`tool_timeout_sec = 300` を、ファイルの終わりに足す（前に空行 1 つ）。`tool_timeout_sec` は、ローカルの AI で `ask_meetings` を動かすと Codex の既定（60 秒）を超えうるため。外すときは、印の行とその前の空行も消す。パスは TOML の基本文字列の決まりで `\` と `"` と制御文字をエスケープする。すでに Hanasu の表があれば、その表の `command` と `args` の行だけを書き換え、利用者が足したキー（`enabled`・`env` など）は残す。
  - Hanasu の表: `[mcp_servers.hanasu]`（`"hanasu"` と引用したものも）の見出しから、次の見出しまで。外すときは `[mcp_servers.hanasu.env]` のような下の表も消す。
  - 書かない（読み取れない）ファイル: 見出し `[mcp_servers]`・`[mcp_servers.<名前>]` 以外で `mcp_servers` を作っているもの（一番上の `mcp_servers = { … }`・`mcp_servers.<名前>.… =`・`[mcp_servers]` の中の `<名前> = { … }`）、`[[mcp_servers…]]`、`'''`・`"""` の複数行の文字列があるもの。
  - 見出しは `[mcp_servers.hanasu]`・`[mcp_servers."hanasu"]`・`[mcp_servers.'hanasu']`（空白と行末のコメントを許す）を Hanasu の表とみなす。Hanasu の表の中の `command`・`args` が複数行（`[` で始まり同じ行で閉じない配列、複数行の文字列）なら、書かない。
  - 書いたあとで読み直し、Hanasu の表が期待どおりでなければ、写しに戻して失敗を出す。
  - `CODEX_HOME` は見ない（Mac の Finder から開いたアプリにはシェルの環境変数が届かず、Windows でも利用者の設定で場所がずれるとかえって分かりにくい）。既定の場所だけを扱い、画面に場所を出す。
- 理由: Swift と .NET に TOML の読み書きの部品がなく、足すと依存が増える。読んで書き直すと利用者のコメントや並びが消える。Hanasu が触るのを自分の表だけにすれば、ほかの行は 1 バイトも変わらない。`codex mcp add` を使う道もあるが、Codex CLI を入れていない人（ChatGPT のアプリだけの人）が多く、この Mac にもない。
- 決めた場面: 同上
- 関係する要件: REQ-COM-194
- 対象: Mac / Windows

### DEC-COM-202 Claude Desktop がその設定の場所で動いているあいだと、ChatGPT（Codex）のアプリが動いているあいだは、書かない
- ChatGPT（Codex）: Mac はバンドル ID `com.openai.codex`・`com.openai.chat` の `NSRunningApplication`、Windows は実行ファイルのパスが `WindowsApps\OpenAI.` の下にあるプロセスが動いていれば書かない（Codex CLI の `codex` は見ない。CLI は設定を書くことが少なく、動いていても会話の途中で止められない）。理由: Windows のアプリが落ちると `config.toml` が NUL で埋まる不具合（openai/codex#26421）があり、アプリは一度に置き換えずに書いている。動いているアプリと同時に書くと、どちらかの変更が消えるか、ファイルが壊れうる。
- 決めたこと（Claude Desktop）: 動いている Claude Desktop のプロセスの引数を読み、`--user-data-dir` がその設定の場所（ないときは既定の `Claude`）なら「動いている」とする。引数を読めなかったプロセスがあれば、どの場所も「動いている」とする（安全な側に倒す）。引数の読み分けは、Mac・Windows で共有のテストデータで確かめられるよう、純粋な関数（Windows は Core）にする。Mac は `NSRunningApplication`（バンドル ID `com.anthropic.claudefordesktop`）の pid の引数を `sysctl`（`KERN_PROCARGS2`）で、Windows は `Claude.exe` のうち実行ファイルのパスが `AnthropicClaude` か `WindowsApps\Claude_` の下にあるものの引数を読む（名前だけでは Claude Code の `claude.exe` と見分けられない）。動いていれば、つなぐ・外すのどちらも書かずに「Claude を終了してから、もう一度押してください」と出す。Hanasu が Claude を終了させることはしない。
- 理由:
  - Claude Desktop は動いているあいだ、このファイルの `preferences` を自分で書く。そのときに Hanasu の足した項目を古い中身で上書きするおそれがある。
  - Claude Desktop は起動のときにしか MCP のサーバーを読まないので、どのみち開き直しが要る。
  - Hanasu が終了させると、返事を作っている途中の会話や、Claude Desktop の中で動いている Claude Code の作業を止めてしまう。
- 決めた場面: 同上
- 関係する要件: REQ-COM-194
- 対象: Mac / Windows

### DEC-COM-203 Hanasu の項目かどうかは、指している実行ファイルで見分ける
- 決めたこと: Claude Desktop の `command`、config.toml の `command`、Claude Code の `~/.claude.json` の `mcpServers.hanasu.command` が、Hanasu の実行ファイルの形（Mac は末尾が `/Hanasu.app/Contents/MacOS/Hanasu`、Windows は末尾が `\cli\hanasu.exe`。大文字・小文字は Windows だけ無視）なら Hanasu の項目とみなす。シンボリックリンク（PATH に入れた `/usr/local/bin/hanasu`・`~/.local/bin/hanasu` など）はたどった先で見る。今のアプリのパスと同じなら（開発用のビルドの `.build/debug/Hanasu` もこれで「つないでいます」になる）「つないでいます」、違う Hanasu なら「別の場所の Hanasu を指しています」。素の `hanasu`（PATH で探す）は Hanasu のものでないとみなす（上書きの確認を出す）。
- 理由: 利用者が `hanasu` という名前で別のサーバーを登録していることがあり、それを消したり上書きしたりしない。アプリを移したあと、前の場所を指す項目を、確かめなしにつなぎ直せるようにする（REQ-COM-191 のリンクと同じ考え方）。
- 決めた場面: 同上
- 関係する要件: REQ-COM-194
- 対象: Mac / Windows

### DEC-COM-204 Claude Code は `claude` コマンドで登録し、状態は `~/.claude.json` を読むだけにする
- 決めたこと:
  - 登録は `claude mcp add --scope user hanasu -- <絶対パス> mcp`、外すのは `claude mcp remove --scope user hanasu`。`claude mcp add` は同じ名前があると失敗するので、`~/.claude.json` の一番上の `mcpServers.hanasu` があれば（別の場所の Hanasu でも、確かめて上書きする Hanasu のものでない項目でも）、先に remove してから add する。add が失敗したら、remove の前に読んだ項目（`command`・`args`・`env`）を `claude mcp add-json --scope user` で入れ直す。
  - `claude` の場所は、Mac は `~/.local/bin/claude`・`/opt/homebrew/bin/claude`・`/usr/local/bin/claude`・`~/.claude/local/claude`・Claude Desktop に入っている Claude Code（`~/Library/Application Support/Claude/claude-code/<版>/<ハッシュ>/claude.app/Contents/MacOS/claude` の、いちばん新しい版）を順に見て、なければログインシェルで `command -v claude` を 1 回だけ（5 秒まで）。Windows は `%USERPROFILE%\.local\bin\claude.exe`・Claude Desktop に入っている Claude Code（同じ形の場所が `%APPDATA%\Claude\claude-code` の下にあれば）・`%APPDATA%\npm\claude.cmd` を見て、なければ `where.exe claude`。見つからなくても「つなぐ…」は押せる（下の直接書く道）。
  - `claude` が見つからないとき（Claude Code をまだ入れていない環境）は、`~/.claude.json`（Windows は `%USERPROFILE%\.claude.json`）の一番上の `mcpServers.hanasu` に、Claude Desktop と同じ形（`command`・`args`）を直接書く。ファイルがなければ `{"mcpServers": {...}}` だけのファイルを作る。書き方（写し・置き換え・シンボリックリンク・権限・ほかのキーを残す）は Claude Desktop と同じ。`claude` という名前のプロセス（Claude Code）が動いていれば書かずに「Claude Code を終了してから、もう一度押してください」と出す。外すのも同じ道。あとで Claude Code を入れると、この登録がそのまま使われる（2026-11-12 に、`mcpServers` だけの `.claude.json` を `CLAUDE_CONFIG_DIR` の一時フォルダに置いて `claude mcp get hanasu` を動かし、「User config」の登録として読まれ、Claude Code が自分のキーを足しても `hanasu` が残ることを確かめた）。
  - `claude` は、Mac ではログインシェル（`HanasuInstall.loginShellPath` の `-l -c`）を通して動かす（npm で入れた `claude` は `#!/usr/bin/env node` で、Finder から開いたアプリの PATH では `node` が見つからないため）。引数はシェルの引用（`HanasuInstall.shellQuoted`）で渡す。Windows は `claude.exe` を直接、`.cmd` のときはパスに `&`・`%`・`^`・`"` がなければ `cmd /c` で動かし、あれば動かさずにコピーの欄を案内する。どちらも画面の外（バックグラウンド）で、30 秒で打ち切る。
  - 行の名前は「Claude Code（ターミナルと Claude Desktop の Code）」。どちらも `~/.claude.json` の同じ登録を読むため。
  - 今のコピーの文（スコープなし）で登録された、プロジェクトだけの項目（`projects[<フォルダ>].mcpServers.hanasu`）は、状態の下に「一部のフォルダだけの登録もあります」と出すだけで、触らない。
  - 状態は `~/.claude.json` の一番上の `mcpServers.hanasu` を読むだけで、書かない。
- 理由: `~/.claude.json` は Claude Code が動いているあいだ常に書き換えるので、Hanasu が直接書くとぶつかる。`claude` に任せれば、Claude Code が自分のやり方で書く。`claude` がない環境では Claude Code も動いていないので、直接書いてもぶつからない。直接書く道を用意するのは、Claude Code を入れる前につないでおきたい・`claude` が Hanasu から見つからない場所にある、という人のため（2026-11-12 の依頼「Claude Code を入れていない環境でも追加できるようにして欲しい」）。Finder から開いたアプリにはターミナルの PATH が届かない（DEC-COM-188）ので、よくある場所を先に見る。`CLAUDE_CONFIG_DIR` は、DEC-COM-201 の `CODEX_HOME` と同じ理由で見ない。
- 決めた場面: 同上
- 関係する要件: REQ-COM-194, REQ-COM-190
- 対象: Mac / Windows

### DEC-COM-205 アプリが見つからないときは、「つなぐ…」を押せなくする
- 決めたこと: Claude Desktop は設定の場所（DEC-COM-200）が 1 つもなく、Mac ならバンドル ID のアプリもないとき、ChatGPT（Codex）は `~/.codex` がなく、Mac ならバンドル ID `com.openai.codex`・`com.openai.chat` のアプリもないときに「見つかりません」と出し、「つなぐ…」を押せなくする。Claude Code は例外で、`claude` が見つからなくても押せる（DEC-COM-204 の直接書く道。状態の下に「Claude Code は見つかりませんでした。入れると、この登録が使われます」と出す）。
- 理由: 入っていないアプリのために、ホームに使われないフォルダとファイルを作らない。Claude Code だけは、利用者の依頼（2026-11-12）で、入れる前に登録できるようにする。書くのは `~/.claude.json` の 1 つだけで、Claude Code が入れば使われる。
- 決めた場面: 同上
- 関係する要件: REQ-COM-194
- 対象: Mac / Windows

## やらないこと

- `.mcpb`（Claude Desktop の拡張機能）での登録 → roadmap に FUT を足す（DEC-COM-200 の分からない点が分かったら）。
- Web 版の ChatGPT・claude.ai から使えるようにすること（リモートの MCP のサーバーが要り、会議の中身をインターネットに出す）。
- Claude Code にスキル（CLI の使い方）を置くボタン。今の「エージェントへの説明」のコピー（REQ-COM-193）は残す。
- Cursor・VS Code・Windsurf などほかのアプリ（コピーの欄の JSON で登録できる）。
- `hanasu doctor` に状態を出すこと、`hanasu connect` のようなコマンド。
- Claude Desktop を Hanasu が終了・起動すること。

## 手順

1. spec（docs/spec/common.md）に REQ-COM-194、DEC-COM-200〜205 を書き、REQ-COM-190・192 を直す。roadmap に `.mcpb` の FUT を足す。
2. 共有のテストデータ `common/testdata/connect/` を作る（場合ごとに、つなぐ前のファイル・操作・期待するファイル・状態）。
3. Mac: `Sources/Hanasu/AgentConnect.swift`（`enum AgentConnect`。`Target`、`Location`、`State`、`Environment`（ホーム・プロセスの一覧・`claude` の場所と動かし方）、`locations(env:)`、`state(_:env:executable:)`、`connect(_:env:executable:overwrite:)`、`disconnect(_:env:executable:)`、JSON と TOML の書き換え、写し）。`CommandLineSettingsTab` に「AI アプリにつなぐ」の節と確認の NSAlert。`HanasuInstall.claudeCodeCommand` に `--scope user`。`SettingsCLI` に `--connect-fixture`。タグを付ける。
4. Windows: `windows/Hanasu.Core/Command/AgentConnect.cs`（3 と同じ決まり）、`CommandInstall.ClaudeCodeCommand` に `--scope user`、`Hanasu.Windows/Services/AgentApps.cs`（動いている Claude Desktop と `claude` の場所）、`SettingsWindow.xaml` と `SettingsWindow.CommandLine.cs` に節と確認（`MessageBox`）。3 と 4 は別のファイルなので並べて進められる（決まりは 1・2 に合わせる）。
5. UI の文字列（約 25）を、Mac は `tr()` と `python3 scripts/i18n-strings.py sync`、Windows は `Strings.resx` の `Settings_Connect_*` で、17 言語の訳を入れる（i18n エージェントに言語を分けて任せる）。
6. テスト: Mac は `HanasuCommandCLI`（`--test-hanasu-command`）、Windows は `windows/Hanasu.Core.Tests/AgentConnectTests.cs` で、2 の共有のデータを流す。`// 確かめ方: REQ-COM-194` を付ける。CI（`.github/workflows/spec.yml` か windows.yml）に、期待する config.toml を `python3 -c 'import tomllib…'` で読む手順を足す。`claudeCode` の期待（`HanasuCommandCLI.swift:658` と `windows/Hanasu.Core.Tests/CommandTests.cs`）も直す。
7. UI のテスト項目: `common/testdata/ui/settings.json` に UX-195（Mac。つないでいる・いない・別の場所・Hanasu のものでない・見つからない・押せないとき）、UX-196（Windows）を足し、`python3 scripts/ui-cases.py md` と `check`。ui-test スキルで UX-195 を描いて確かめる。
8. 文書: design/cli.md（登録の章）、design/security.md と security-windows.md（Hanasu が書く利用者の設定ファイル、写しの権限、写しにほかのサーバーの秘密が入りうること）、windows/README.md の「コマンドと MCP」、README.md の「⌨️」の節（「copy the setup」→ ボタンでつなげる）と 16 の訳。
9. 確かめる（下）。

## 確かめ方

- 共有のテストデータの場合（Mac・Windows で同じ）:
  1. Claude Desktop: ファイルがない → 作る。ほかの `mcpServers` と `preferences` がある → 残る。Hanasu のものでない `hanasu` → 上書きの確認が要る（`overwrite: false` で何も書かない）。壊れた JSON → 書かない。前の場所の Hanasu → 「別の場所」。外す → `hanasu` だけ消える。写しができ、権限が元と同じ。動いている（引数の既定・`--user-data-dir`）→ その場所だけ書かない。場所が 2 つ → 2 行。
  2. config.toml: ない → 作る。ほかの表とコメント → 1 バイトも変わらない。Hanasu の表がある → `command`・`args` の行だけ変わり、`enabled = false` は残る。外す → 下の表 `[mcp_servers.hanasu.env]` ごと消える。一番上の `mcp_servers = {…}`・ドットのキー・`hanasu = {…}`・複数行の文字列 → 書かない。空白・`"`・`\` を含むパス → 期待どおりの行で、`tomllib` で読める。
  3. Claude Code: `claude` を偽のスクリプト（本物と同じく、同じ名前があれば add が rc=1、なければ remove が rc=1）に差し替え、渡した引数を確かめる。別の場所の Hanasu → remove してから add。add の失敗 → 前の項目が入れ直される。打ち切り（偽のスクリプトが戻らない）。`claude` がない → `.claude.json` がなければ `mcpServers` だけのファイルができ、あればほかのキー（`projects` など）が残る。`claude` のプロセスが動いている → 書かない。`~/.claude.json` の状態の読み分け。`claude` がない → 見つからない。`claude` が失敗 → stderr を出す。
  4. 共通: 設定ファイルがシンボリックリンク → リンクが残り、リンク先が変わり、権限が元と同じ。`deploymentMode` のあるフォルダ → 行に出ない。プロセスの引数（なし・`--user-data-dir=…`・`--user-data-dir …`・読めない）→ 動いている場所の判定。
- `swift build`、`.build/debug/Hanasu --test-hanasu-command`
- `cd windows && dotnet test Hanasu.Core.Tests`
- `python3 scripts/check-spec.py`、`python3 scripts/check-i18n.py`、`python3 scripts/i18n-resx.py check`、`python3 scripts/ui-cases.py check`
- `.build/debug/Hanasu --render-settings <フォルダ> --pane commandLine --connect-fixture <名前>`（UX-195）
- 実機（この Mac。2026-11-12 に了承。写しから戻せることも確かめる）。実装するエージェントは Claude Desktop（既定の `Claude`）の中で動いているので、分けて行う:
  - エージェントがすること:
    - Claude Desktop（`Claude-Personal`。今は動いていない）: 既定の `Claude` が動いていても、この行は書ける。つなぐ → ユーザーに `Claude-Personal` を開いてもらい、チャットで「先週の会議」を聞くと hanasu のツールが使われる。初めてのとき「書類」フォルダの確認が出るか、拒否したら REQ-COM-185 の文が返るか。
    - Claude Desktop（既定）: 動いているので「終了してから」が出て、書かれないこと。
    - ChatGPT（Codex）: ChatGPT のアプリが動いていれば「終了してから」が出ること。ユーザーに終了してもらってつなぐ → 開いてもらい、Codex で hanasu のツールが使えるか、ふつうのチャットでは使えないか（不具合のとおりか）。
    - Claude Code: つなぐ → 別のフォルダで `claude -p` を動かし、hanasu のツールが一覧に出て使えること。つなぎ直し（別の場所 → このアプリ）も。
  - ユーザーにしてもらうこと: 既定の Claude Desktop を終了して（このセッションも止まる）、Hanasu の設定で「つなぐ…」を押し、Claude を開き直してチャットで会議を聞く。結果を教えてもらう。
  - Windows の実機は、利用者に頼む（UX-196。更新のときに REQ-REL-013 の確認が出ることも）。

## 敵対的レビュー

2026-11-12 に requirements-reviewer を 2 つ（観点 1〜3・10・11 と、観点 4〜9）走らせた。

直したこと:
- ChatGPT のふつうのチャットでは、手元の MCP が今は使えない（openai/codex#38162 が 2026-11-04 時点で開いたまま）。→ 実装のあとに確かめるのをやめ、了承の前にユーザーに聞く（ユーザーに聞くこと 1）。
- Claude Code をスキルにしたのは、了承をもらった推奨（`claude mcp add`）からの変更で、サンドボックスで `ask` が失敗しうる・更新で古くなる弱みがあった。→ MCP（`claude mcp add --scope user`）に戻し、ユーザーの「どちらが良い？」への答えとして理由を書いた。スキルの要件の案は取り下げた。
- この Mac には Claude Desktop の設定の場所が 3 つ（`Claude`・`Claude-Personal`・`Claude-3p`）あり、既定だけに書くと、ふだん使う Claude で使えない。バンドル ID で終了させると別の Claude まで終わる。→ 場所ごとに行を出し、動いているかを場所ごとに見て、Hanasu は終了させない（DEC-COM-200・202）。
- 初めて会議を読むときの「書類」フォルダの確認（REQ-COM-185）が抜けていた。→ つないだあとの案内と実機の確認に足した。
- config.toml で、一番上の `mcp_servers = {…}` やドットのキーがあると、表を足すと TOML として壊れる。書き込みの置き換えも書いていなかった。→ 書かない場合に足し、一時ファイルで置き換え、読み直し、`tomllib` で CI で確かめる（DEC-COM-201）。
- 状態が 4 つでは足りない（Hanasu のものでない・読めない）。→ 6 つにした。
- 動いているか・入っているかを差し替える口がなく、テストと画面の描画が手元の本物の状態に左右される。→ `AgentConnect.Environment` と `--connect-fixture` を足した。
- 写しを作り直すと 0600 のファイルが 0644 になる。→ 元の権限で写す（テストに足した）。security.md に書く。
- `CODEX_HOME`・`CLAUDE_CONFIG_DIR` は Finder から開いたアプリに届かない。→ 見ないと決め、既定の場所の場所を画面に出す。
- 外すときに Claude Desktop が動いていたらどうするか、Hanasu の表に利用者が足したキーをどうするかがあいまい。→ 受け入れ条件と DEC-COM-201 に書いた。
- DEC に「決めた場面」がない（check-spec が落ちる）、REQ-COM-192 を直す必要、README の「copy the setup」、windows/README.md・security-windows.md、Windows の REQ-REL-013、ポリシーが Mac だけであること。→ 手順と要件に足した。
- 調べる中で、今のコピーの `claude mcp add` に `--scope user` がなく、動かしたフォルダだけに登録されることが分かった。→ 「変える要件」に足した。

退けたこと: なし。

2026-11-12 に、直した計画で 2 回目（観点 1〜11）を走らせた。直したこと:
- `claude mcp add` は同じ名前があると失敗する（手元で確かめた）ので、別の場所の Hanasu をつなぎ直せなかった。→ 項目があれば必ず remove してから add し、失敗したら入れ直す（DEC-COM-204）。
- 設定ファイルがシンボリックリンク（dotfiles）だと、一時ファイルでの置き換えがリンクを壊し、0755 の普通のファイルにする。→ リンク先を書き換え、本体の権限もそろえる（受け入れ条件）。
- `Claude-3p` は起動の引数で選ぶ場所でなく、Claude Desktop が配置のモードで使う場所らしい（`deploymentMode` のキー）。→ そのフォルダは行に出さない。引数を読めないときは「動いている」に倒す（DEC-COM-200・202）。
- 実装するエージェントは既定の Claude Desktop の中で動いているので、既定の Claude を終了して確かめられない。→ 実機の確かめを、エージェントがすること（`Claude-Personal`・ChatGPT（Codex）・Claude Code）と、ユーザーにしてもらうこと（既定の Claude）に分けた。
- Claude Desktop の Code のタブだけで Claude Code を使う人には `claude` が見つからなかった。→ Claude Desktop に入っている `claude` も探し、行の名前を「Claude Code（ターミナルと Claude Desktop の Code）」にした。
- npm で入れた `claude` は Finder から開いたアプリの PATH では動かない。`claude` は数秒かかり、止まったときの扱いがなかった。→ ログインシェルを通し、バックグラウンドで 30 秒まで（DEC-COM-204・受け入れ条件）。
- 軽微: 実機の確かめの「動いたまま書く」の残り、「外す…」を押せるとき、Windows のコピーの `--` の扱い、直すテストの場所、PATH のリンクや開発用のビルドの見分け、TOML の引用した見出しと複数行の値、`tool_timeout_sec`、`.cmd` の引用、引数の読み分けを Core に置く、プロジェクトだけの登録、DEC-COM-204 の理由の誤り。→ それぞれ直した。

退けたこと: なし（会社の管理で Claude Desktop の手元の MCP が止められているときの表示は、調べる手段がないので、実機で見つかったら直す）。

## 仮に決めたこと

- **Claude Desktop は `.mcpb` でなく設定ファイルに書く**（DEC-COM-200）。質問のときの推奨から変えた。
- **Claude Desktop が動いているときは、利用者に終了してもらう**（DEC-COM-202）。Claude Desktop の中で Claude Code を使っている人は、つなぐ間だけ Claude Desktop を閉じることになる。
- 書く前の写しは 1 つだけ（`<名前>.hanasu-backup`。前の写しは上書き）。
- ChatGPT（Codex）のアプリの見分け方（バンドル ID・`WindowsApps\OpenAI.` のパス）は、この Mac の `com.openai.codex` と報告から決めた。Windows のパスは実機で確かめる。
