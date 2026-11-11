# `hanasu` コマンドの段階 6（Windows の `cli\hanasu.exe`）— 計画

- 状態: 計画（未実装）。[plans/cli.md](cli.md) の 6 章の段階 6 を、実装できる粒度に詰めたもの。要件・設計判断の案の番号（W1〜・WD1〜）は、この計画の中だけのもの。実装するときに spec の番号（COM・MTG・DIC・REL の、今の続きの空き番号。REL は #98 の REQ-REL-012・DEC-REL-028 の続き）にする
- 前提: main の #95（AI チャット・質問の送り先。REQ-COM-025）・#96・#98（アップデートのダウンロードの進み具合）を取り込んだあとの作り（4c3563a）
- 出どころ: 2026-11-11 の依頼「段階 6 に進む」。ユーザーの決定（2026-11-11）:
  1. Windows の `hanasu` には、Mac と同じコマンドを**すべて**入れる（`meetings search`・`ask`・`edit`・`refine --app / --style`、MCP の `search_meetings`・`ask_meetings` を含む）。Windows のアプリにまだない会議の検索・会議への質問・選択の書き換え・文体は、`Hanasu.Core` に移して `hanasu` から使う（アプリの画面に出すのは、この計画の外）
  2. Windows Hello で守った API キーも、**確認を出して使える**
  3. Windows の設定画面にも「**コマンドと MCP**」を足す
  4. （1 回目のレビューのあと）`hanasu ask`・`ask_meetings` の AI は、**アプリの「会議に質問」と同じ**にする。Mac は「AI チャット・質問」の送り先（REQ-COM-025）に直す。Windows にはその設定がないので「会議」の AI を使い、違いを差の表に書く。→ 決定 7 で絞った
  5. （同）Windows の `--app` は、**exe の名前ごとの既定の文体を当てる**（Mac の組み込みの既定の文体と同じ結果。設定の画面は作らない）
  6. （同）自動アップデートで `hanasu` が動いているときは、**知らせてから終わらせる**（承諾したら終わらせて入れ替え、取り消したら今回はアップデートしない）
  7. （2 回目のレビューのあと）決定 4 は、Mac では「AI チャット・質問」を**利用者が自分で選んで保存したときだけ**その AI を使い、保存していなければ今までどおり「会議」の AI を使う（A'）。「AI チャット・質問」の既定はローカルで、前から使っている人にも会議の値を写さない（DEC-COM-171）。`hanasu` はアプリのローカルの AI のサーバーを共有できない（DEC-COM-184）ので、既定のままの人で `ask` が失敗したり、呼ぶたびにモデルを読み込み直したりしないようにする
  8. （同）読めない会議（ファイルはあるのに読めないもの）の数を、**Mac と Windows の両方で** JSON と MCP の結果に出す。壊れた `meeting.json` は今までどおり黙って飛ばす（REQ-MTG-120・REQ-COM-181 を直す）
  9. （同）MCP の引数の値の誤りは、今の作りのとおりツールの結果（`isError`）で返し、REQ-COM-189 の「計画からの変更（ユーザーの確認待ち）」を外す。Windows も同じにする
- 管理者のポリシーは Windows に入れない（[plans/admin.md](admin.md)。FUT-020）

## 目的

Mac と同じく、Windows でも会議の記録を AI エージェントやスクリプトから読め（会議を並べる・読む・探す・質問する・MCP）、音声入力の整え方をパイプで使える（整形・翻訳・書き換え・辞書）ようにする。同じコマンド名・同じ JSON の形・同じ終了コードにして、エージェントへの説明や MCP の登録を、Mac と Windows でそろえる（計画の 4.4「対象」）。

## 今の Windows 版（調べた事実）

- 開発用の `Hanasu.Cli`（`hanasu-cli`、net8.0）は確かめの道具で、認証は環境変数だけ。利用者向けではない。
- `Hanasu.Core`（net8.0）に、会議の読み込み（`MeetingStore.LoadAll`。1 件ずつ順に読み、`IOException` の会議は黙って飛ばす）、設定（`SettingsStore.Load`）、AI のクライアント（`TextAiFactory.Create`。Gemini・Claude・Local の 3 つで、Apple はない）、整形と翻訳（`DictationTextProcessor`・`GeminiPrompts`）、辞書（`UserDictionary.Apply`）、除いた発言・オフレコ（`MinutesSelection`）がある。プロンプトの JSON（`Sources/Hanasu/Resources/Prompts`）は Core に埋め込まれ、`edit.*`・`style.*`・`ask.*` も読める（まだ使っていない）。
- ない: 選択の書き換え（`TextPurpose` に Edit がない）、アプリ別の文体、会議の検索、会議への質問、「AI チャット・質問」の送り先。
- アプリの保存（`MeetingStore`・`SettingsStore`・`SecretStore`）は、一時ファイルを `File.Move(…, overwrite: true)` で置き換える。読む側の `File.ReadAllText` は削除の共有なしで開くので、Windows では、ほかのプロセスが読んでいる間は置き換えが失敗する（Mac の rename では起きない）。
- 秘密は `SecretStore`（Core）。DPAPI と Windows Hello の実装（`DpapiDataProtector`・`WindowsHelloKey`）は `Hanasu.Windows` の internal で、Hanasu.Windows の文字列（`Hello_*`）・`AppLog`・`NativeMethods` に依る。アプリは画面のロック・スリープで鍵を捨てる（DEC-COM-144。`AppHost` の `SessionSwitch`・`PowerModeChanged`）。DLL を探す場所を絞る処理（DEC-COM-148。`WindowsSecurity.HardenDllSearch`）も Hanasu.Windows にある。
- ローカルの LLM（`LocalLlmServer`）に pid の記録はない。アプリは llama-server をジョブオブジェクトに入れる（`ChildProcessJob`。internal）。`ResolveExecutable` は exe の隣の `llama\` だけを探す。使わなければ 5 分で止まる。
- 配布の zip（`tagpr.yml`・`windows.yml`）は `Hanasu.Windows` だけを publish（自己完結・単一ファイル・win-x64）し、`llama\` を足す。zip の最上位は `Hanasu\`。自動アップデートは、フォルダごと名前を変えて入れ替える（`UpdateService` の `SwapScript`）。exe を開いているプロセスがあると、入れ替えに失敗して古い版のまま起動し直す。処理中は入れ替えない（DEC-REL-023）。
- 設定画面は `SettingsWindow.xaml` の TabControl（一般・AI・会議・履歴・辞書とルール）。レジストリや PATH を触るコードはない。
- Windows の話者の表示の名前の訳は、Mac と一部違う（例: en の同席者は Mac が "Room Speaker"、Windows が "In-room"）。
- この Mac で `cd windows && dotnet test Hanasu.Core.Tests` が動く（557 件合格）。Windows 用の TFM も `EnableWindowsTargeting` でコンパイルできる（実行はできない）。

## 要件の案

### 既存の要件・設計判断の扱い（ユーザーの合意が要るもの）

新しい番号は作らず、既存の要件の「対象」を広げ、「Windows の実装」と、Windows で違う中身を書く。

| ID | 扱い | Windows で書くこと・直す文 |
| --- | --- | --- |
| REQ-COM-180 | Mac / Windows | Windows は配布の zip の `cli\hanasu.exe`（アプリと同じ zip。別のインストールは要らない）。Mac の「アプリと同じ実行ファイル」は Mac の実装に移す |
| REQ-COM-181 | Mac / Windows | 「成功したときの stderr は空」に「読めない会議があったときの知らせ（W7）を除く」を足す（決定 8） |
| REQ-COM-182・183 | Mac / Windows | 同じ。183 に「Windows で、`hanasu` が読んでいる間もアプリの保存が失敗しない」を足す（W6） |
| REQ-COM-184・188 | Mac だけ | Windows のポリシーは FUT-020 |
| REQ-COM-185 | Mac / Windows | Windows の知らせ（フォルダのアクセス権・OneDrive の同期でオンラインだけにある会議）を書く（W7） |
| REQ-COM-186 | Mac / Windows | `ask` の AI を、Mac は「AI チャット・質問」を保存した人だけそれに、ほかは「会議」に直す（決定 4・7。Windows は「会議」）。認証情報はキーチェーン（Mac）・`secrets.json`（Windows。DPAPI か Windows Hello。W3）。`--ai apple` は Windows では終了コード 2 と「Windows では使えません」。doctor の `credentials.apple` は Windows では `available: false` と理由 |
| REQ-COM-024 | Mac / Windows | Windows の受け入れ条件の「選択の編集・会議への質問がないので…」に、「`hanasu edit` は音声入力の AI、`hanasu ask` は会議の AI を使う」を足す |
| REQ-COM-187 | Mac / Windows | WD4 |
| REQ-COM-189 | Mac / Windows | `DisableMCP` の部分は Mac だけ。「計画からの変更（ユーザーの確認待ち）」を外し、引数の値の誤りは `isError` で返すと書く（決定 9） |
| REQ-COM-190・191・193 | Mac / Windows | Windows は設定の「コマンドと MCP」のタブ（W4）。191 は Windows ではユーザーの PATH |
| REQ-COM-192 | Mac だけ | Windows の、`cli\hanasu.exe` がない・一時フォルダで動いているときは W4 に書く |
| REQ-MTG-120 | Mac / Windows | 「読めない `meeting.json` は飛ばす」を、「壊れた `meeting.json` は飛ばす。ファイルはあるのに読めない会議は飛ばして、その数を出す（W7）」に直す（決定 8） |
| REQ-MTG-121〜125 | Mac / Windows | 同じ。会議の一覧を返す `meetings search`・`actions` と MCP の 3 つのツールにも、読めない会議の数を足す（W7） |
| REQ-MTG-127 | Mac / Windows | `DisableMCPAskMeetings` は Mac だけ。「`ask_meetings` の説明には…設定の会議の AI」を、REQ-COM-186 の送り先に合わせる（決定 7） |
| REQ-MTG-126 | Mac / Windows | 「会議の AI（REQ-COM-024）で」→「Mac は『AI チャット・質問』（REQ-COM-025）を保存した人はそれ、ほかは会議の AI。Windows は会議の AI で」（決定 4・7） |
| REQ-DIC-160・161・162 | Mac / Windows | 160 の `--app` は、Mac は bundle ID、Windows は exe の名前（決定 5。W2） |
| DEC-COM-180・182・183 | Mac だけ | — |
| DEC-COM-181・184・186・187、DEC-MTG-120〜125、DEC-DIC-160・161 | Mac / Windows | 186 は WD6、187 は置き場所を「コードか、`Sources/Hanasu/Resources` の共有のファイル」に直す（WD2） |
| DEC-COM-185 | Mac / Windows | 「doctor はキーを実際に読む」を、Windows Hello で守ったキーは読まずに守り方だけを出す、に直す（確認を出さないため。W3） |
| DEC-MTG-123 | Mac / Windows | Windows も並べて読む（W7） |
| DEC-COM-107・FUT-003 | 直す | Windows にないものの一覧から、`hanasu` で使えるもの（検索・質問・書き換え・文体）を「`hanasu` からは使える。アプリの画面にはない」に直す |
| DEC-COM-144・147・148・149 | 直す | 「実装の場所」を、`Hanasu.Platform` に移した型の名前に直す（WD1）。`design/security-windows.md` も同じ |
| DEC-REL-022 | 直す | Windows の尋ね方に、動いている `hanasu` を終わらせることを足す（W5） |
| DEC-REL-030 | 直す | 入れ替えのスクリプトが、名前を変える直前に `cli\hanasu.exe` のプロセスを探し直して終わらせることを足す（W5・WD8） |

### W1 Windows でも `hanasu` コマンドを使える
- 内容: 配布の zip の `cli\hanasu.exe` で、Mac と同じ `hanasu` のコマンド（`meetings list / show / search`・`actions`・`ask`・`refine`・`edit`・`dict apply`・`doctor`・`mcp`・`help`（`help agent` を含む）・`--version`）が動く。コマンド名・オプション・JSON の形（`schemaVersion` 1 のキーと値の型）・終了コード（0〜5）・stdout と stderr の分け方は Mac と同じ。ヘルプとエラーは表示の言語（17 言語）。
- 受け入れ条件:
  - 共有の架空の会議（WD3）で、Mac と Windows の `--json` と `--show-prompt` の出力が、決めた違い（WD3 の一覧）を除いて同じになる。`doctor --json` は形の違いを決めて書く（Windows では `install` は `{ "cliPath", "onPath", "pathEntries" }`、`policies` の項目はない、`credentials.*.source` は `dpapi`・`windowsHello`・`env`・`none`、`ai` に `chat` はない）。
  - 追加のインストール（.NET のランタイムなど）なしで動く。絶対パスで呼べば PATH なしで動く。
  - 文字コード（WD9）。英語の Windows（コードページ 437）でも日本語の Windows（932）でも、次が化けない:
    - 画面に出す: cmd・Windows Terminal・PowerShell で `hanasu --help`・`hanasu meetings list` の日本語が読める。
    - ファイル・パイプに出す: `hanasu meetings list --json > out.json`（cmd・PowerShell 7.4 以降）が UTF-8（BOM なし）・LF の JSON になる。
    - パイプで受け取る: PowerShell 7 で `"明日は10時" | hanasu refine` が化けない。
    - PowerShell が読み取る: `hanasu meetings list --json | ConvertFrom-Json` は、`[Console]::OutputEncoding` を UTF-8 にした PowerShell で化けない。この設定の行（5.1 では `$OutputEncoding` も）をヘルプ・README・エージェントへの説明に書く。
    - cmd の `echo 日本語 | hanasu refine` は、UTF-8 として正しくなければコンソールのコードページで読み直すので化けない。
    - Windows PowerShell 5.1 の `>`（UTF-16 で書く）は直せないので、ヘルプと README に `| Out-File -Encoding utf8` か `cmd /c` を使うと書く。
  - 会議のフォルダは、アプリの設定の保存先（`MeetingsDirectory`。空なら既定）。`--meetings-dir`・`HANASU_MEETINGS_DIR` で変えられる（REQ-MTG-125）。
  - Windows に `apple` はない。`--ai apple` は終了コード 2。
- 確かめ方: `cd windows && dotnet test Hanasu.Core.Tests`（Mac でも動く。パイプの読み直しの判定は純粋な関数にして確かめる）、CI（windows.yml）で publish した `cli\hanasu.exe` を Windows のランナーで動かす（`--version`・共有の会議で `meetings list / show / search --json` を期待する出力と比べる・`mcp` の手順・`chcp 932` と `chcp 437` でのパイプとファイル）。CI の stdout はパイプなので、画面に出すとき（`WriteConsoleW`）と PowerShell 5.1 は実機

### W2 Windows に会議の検索・会議への質問・選択の書き換え・文体を移す（`hanasu` から使う）
- 内容: Mac の `MeetingSearchIndex.scan`（一致の決まり: 全角半角・大文字小文字・空白で区切った語のすべてを含む。当たる場所は `title`・`minutes`・`transcript` の 3 つ）、`MeetingAsk`（集め方・件数と文字数の上限・期間・同じプロンプト `ask.*`）、選択の書き換え（`edit.*`）、文体のプリセット（`style.*`。none・chat・email・document-polite・document-plain）と、組み込みの既定の文体（Mac の `AppStyleStore.defaultStyles` に当たる Windows の exe の名前の一覧。例: `slack.exe` は chat、`OUTLOOK.EXE` は email、`WINWORD.EXE` は document-polite。大文字小文字を区別しない）を、`Hanasu.Core` に移す。プロンプトの文面は今の JSON をそのまま使い、足さない。
- 受け入れ条件:
  - 検索: 共有の会議と語で、当たる会議・場所・件数が Mac と同じ。除いた発言・オフレコにだけある語では当たらない。
  - 質問: AI に送る内容（`--show-prompt`）が、同じ会議・同じ質問・同じ言語・同じ「今」で Mac と同じ。期間の外の会議は送らない。
  - 書き換えと文体: `edit` と `refine --style`・`refine --app` で AI に送るプロンプトが、同じ入力で Mac と同じ（`--app` は、対応する Mac の bundle ID と Windows の exe の名前で同じ文体と同じアプリ名になる。アプリ名は WD5）。
  - Windows のアプリの画面は、この計画では変えない。
- 出典: 決定 1・5
- 関係する要件: REQ-MTG-015, REQ-MTG-016, REQ-DIC-020, REQ-DIC-021, REQ-DIC-050, REQ-MTG-123, REQ-MTG-126, REQ-DIC-160〜162
- 確かめ方: `dotnet test Hanasu.Core.Tests`（共有のテストデータ）

### W3 Windows Hello で守った API キーも、確認を出して使える
- 内容: `hanasu` が Windows Hello で守ったキーを読むときは、確認を出し、通れば使う。鍵はそのプロセスの中でだけ持ち、アプリと同じく画面のロック・ログオフ・スリープで捨てる（DEC-COM-144）。`refine` などは呼ぶたびに確認が出る。`hanasu mcp` は、最初に要ったときと、ロックなどのあとに要ったときに出る。
- 受け入れ条件:
  - 確認が通れば整形した文が出る。取り消したら、何も出さずに終了コード 3（MCP は `isError`）と理由。次の呼び出しでは、また確認を出す。
  - 確認が 60 秒で終わらなければ、終了コード 3 と「確認の画面がほかのウインドウの裏に隠れていないか」を出す。画面のないセッション（SSH・切断した RDP など）では確認を出さずに 3 と理由。
  - `hanasu doctor` は、キーがあるか・どちらで守っているかを、復号せずに出す（確認を出さない）。DPAPI のキーは今までどおり読めるかを確かめる。
  - `hanasu mcp` は、確認が通ったあとは鍵を持ち続け、画面のロック・ログオフ・スリープのあとに鍵が要ったら、また確認を出す。
  - 確認の画面が MCP の stdout を壊さない。
  - `hanasu --help`・AI のコマンドの `--help`・`doctor` に、Windows Hello のときは呼ぶたびに確認が出ることを書く。
  - `hanasu` がログ（アプリと同じ `hanasu.log`）に書くのは、起動・終了・エラーの種類だけで、質問・会議・整える文の中身と鍵は書かない（`security-windows.md` の約束）。
- 出典: 決定 2（計画の 5.1・8 章のリスク）
- 関係する要件: REQ-COM-186、DEC-COM-144
- 確かめ方: 取り消し・時間切れ・画面のないとき・復号しない doctor・ロックの知らせのあとの再確認は、偽の鍵（`IUserPresenceKey` の偽物）と偽のセッションの知らせで `dotnet test`。コンソールの exe でロックを知るには `Microsoft.Win32.SystemEvents` のパッケージを足す（窓がないので、隠れたメッセージの窓を作る）。実際の確認の画面（前に出るか）と実際のロックは実機

### W4 Windows の設定画面に「コマンドと MCP」を足す
- 内容: 設定に「コマンドと MCP」のタブを足し、`cli\hanasu.exe` の絶対パス、PATH の状態と「PATH に入れる」「PATH から外す」（ユーザーの PATH（`HKCU\Environment\Path`）に `cli` のフォルダを足す・外す。管理者の権限は要らない）、Claude Code のコマンド・Claude Desktop の JSON（`claude_desktop_config.json` の `mcpServers`）・エージェントへの説明を、コピーのボタンつきで出す。
- 受け入れ条件:
  - 「PATH に入れる」のあと、スタートメニューから新しく起動した PowerShell・コマンドプロンプトで `hanasu --version` が動く（開いたままのターミナルや、そこから起動したアプリには届かないので、再起動が要ることを画面に出す）。ほかの項目・値の型・`%…%` の書き方は変えない。「PATH から外す」で、足した項目だけを消す。
  - 別の場所の `…\cli` を指す項目（前に置いていた場所。消えたフォルダを含む）があるときは、そのことを出し、入れ直すと新しい場所になる。
  - Claude Desktop の JSON は、`\` を含むパスでもそのまま貼れる正しい JSON。Claude Code のコマンドと、エージェントへの説明に書くコマンドは、PowerShell 7・Windows PowerShell 5.1（`& "…"` の形）でそのまま動く。Git Bash 向けの書き方も説明に添える（WD2）。
  - `cli\hanasu.exe` がない（`Hanasu.exe` だけを置いた）か、アプリが一時フォルダ（`%TEMP%` の下。zip の中から開いた）で動いているときは、そのことと「zip をすべて展開したフォルダから開き直す」を出し、PATH とコピーのボタンを使えなくする。
  - 表示の言語（17 言語）で出る。
- 出典: 決定 3（計画の E3・E4・E7）
- 関係する要件: REQ-COM-190, REQ-COM-191, REQ-COM-193
- 確かめ方: PATH の項目の足し方・外し方・見分け方と、登録の文・説明のコマンドの組み立ては、Core の純粋な関数にして `dotnet test`。画面と新しいターミナルで動くことは実機（UX の項目を足す）

### W5 自動アップデートのときに `hanasu` が動いていたら、知らせてから終わらせる
- 内容: 自動アップデートで入れ替える前に、インストールしたフォルダの `cli\hanasu.exe` で動いているプロセス（MCP のサーバー・実行中のコマンド）があれば、アップデートの確認（DEC-REL-022 の「アップデート / あとで / この版をスキップ」）に「動いている hanasu（N 個）を終わらせます。MCP を使うアプリ（Claude Desktop など）は、Hanasu のツールが使えなくなったら再起動してください」と出す。承諾したら終わらせてから入れ替え、取り消したら今回はアップデートしない（決定 6）。入れ替えのスクリプトは、名前を変える直前に、同じパスの `hanasu.exe` を探し直して終わらせる（確認のあと、ダウンロードの間に起動したものも含める）。
- 受け入れ条件:
  - `hanasu mcp` を動かしたまま、確認で承諾すると、入れ替わって新しい版が起動する（前は失敗して古い版のまま）。取り消すと、入れ替えず、今の版のまま動く。
  - 動いている `hanasu` がなければ、今までどおり（確認の文は増えない）。
  - 終わらせられない `hanasu`（管理者として動かしたもの）があるときや、ターミナルの作業フォルダが `cli\` の中にあって名前を変えられないときは、今までどおり古い版のまま起動し直し、「`hanasu` を終わらせ、`cli` のフォルダから出てから、もう一度アップデートしてください」と知らせる（黙って失敗しない）。
  - 確認の文は上のとおりに決めておく（MCP のクライアントが自動で戻るかに依らない文にする）。Claude Desktop と Claude Code が実際にどうなるかは実機で確かめて `docs/verification/` に記録し、README の Windows の節に書く。
- 出典: 決定 6。REQ-REL-010・011、DEC-REL-022・023・030
- 確かめ方: 動いている `hanasu` の見つけ方と、入れ替えのスクリプトの組み立て（探し直す・終わらせられなかったときの知らせ）は、Core の純粋な関数にして `dotnet test`。実際の入れ替えと MCP のクライアントの振る舞いは実機

### W6 Windows で、`hanasu` が読んでいる間もアプリの保存が失敗しない
- 内容: `hanasu` は、会議・設定・秘密のファイルを、置き換えを妨げない形（`FileShare.ReadWrite | FileShare.Delete`）で開いて、すぐ閉じる。アプリの保存（`WriteAtomically`）は、共有違反で置き換えに失敗したら、短く（例: 50 ms ずつ最大 1 秒）やり直す。
- 受け入れ条件: アプリが会議（メモ・「ここ重要」・オフレコ・議事録）・設定・秘密を保存している最中に、`hanasu`（MCP の連続の呼び出しを含む）が読んでも、アプリの保存は失敗せず、会議は「失敗」にならない。
- 出典: レビューの指摘（REQ-COM-183 を Windows で守るため）
- 関係する要件: REQ-COM-183
- 確かめ方: ファイルを `hanasu` と同じ開き方で開いたまま `MeetingStore.Save` するテスト（Windows のランナーの `dotnet test`。Mac では置き換えの制限がないので、Windows の CI で確かめる）

### W7 読めない会議を「ない」と取り違えず（Mac / Windows）、Windows でも速さの目安を守る
- 内容: `meeting.json` があるのに読めない会議（OneDrive のオンラインだけにあってオフライン・アクセスが拒否される）は、飛ばして、その数を出す。数えるのは、ファイルを開けない・読めないもの（.NET の `IOException`・`UnauthorizedAccessException`、Mac のファイルの読み込みの失敗）だけで、読めたが壊れている `meeting.json`（JSON として読めない）は今までどおり黙って飛ばす。Mac と Windows の両方で同じにする（決定 8）。
  - `--json` と MCP の結果: 会議を集めるコマンド（`meetings list / search`・`actions`・`ask`）とツール（`list_meetings`・`search_meetings`・`list_action_items`・`ask_meetings`）の結果に `unreadableMeetingCount`（整数。0 のときも出す）を足す。項目を足すだけなので `schemaVersion` は 1 のまま（REQ-COM-181）。MCP のツールの説明に「0 でなければ、ない会議があるとは言い切らない」旨を足す。
  - 文の出力: 1 以上なら、stderr に件数とフォルダと理由（Mac: フォルダのアクセス権・iCloud などの同期、Windows: フォルダのアクセス権・OneDrive の同期）を 1 行出す。終了コードは 0 のまま。
  - 指定した会議（`meetings show <id>`・`get_meeting`）が読めなければ、終了コード 5 と同じ理由（MCP は `isError`）。
  - Windows も会議を並べて読む（DEC-MTG-123）。
- 受け入れ条件:
  - 読めない `meeting.json`（テストでは読み込みを失敗させる偽のファイルの読み手を使う）を 2 件混ぜると、`--json` と MCP の結果の `unreadableMeetingCount` が 2 で、文の出力では stderr に 1 行出る。壊れた JSON の会議を混ぜても数は変わらない。
  - Windows で、架空の会議 1,000 件の `meetings list / show / search` が、CI の Windows のランナーで 2 秒以内。超えたら CI を落とす（ランナーの揺れを考え、3 回のうちいちばん速い値で比べる）。
- 出典: レビューの指摘（計画の 4.4 の速さ、REQ-COM-185）。決定 8
- 関係する要件: REQ-MTG-120, REQ-COM-181, REQ-COM-185, DEC-MTG-123
- 確かめ方: `dotnet test`（読めない会議の数え方）、`.build/debug/Hanasu --test-hanasu-command`（Mac の数え方）、CI で速さを測る

### 決定 4・7 の Mac 側の直し
- Mac の `hanasu ask`・`ask_meetings`・`doctor` の「ask」の行は、「AI チャット・質問」の送り先（REQ-COM-025）が利用者の設定に保存されていれば（`UserDefaults` の既定の登録ではなく、アプリの領域に値がある）その AI を、なければ今までどおり `TextAIPurpose.meeting` の AI を使う。`--ai`・`--model` でその回だけ変えられるのは今のまま。`ask_meetings` の説明に出す送り先の AI と、`doctor` の「ask」の行（どちらを使っているかと、その理由）も合わせる。doctor の chat の行に「refine, edit」と出している誤りも直す。
- 確かめ方: `.build/debug/Hanasu --test-hanasu-command`（決めた設定の suite で、「AI チャット・質問」を保存したときは偽の `fm` に、保存していないときは会議の AI に送られること）

## 設計判断の案

### WD1 作り: 中身は `Hanasu.Core`、exe は薄く、Windows に依る部品は共有のライブラリにする
- 決めたこと: コマンドの振り分け・引数・会議の JSON・検索・質問・書き換え・文体・MCP の手順・PATH の項目の処理・入れ替えのスクリプトの組み立ては、`Hanasu.Core` の新しい名前空間 `Hanasu.Core.Command`（net8.0）に純粋な関数として置き、Mac でも `dotnet test` で確かめる。時計と時差は引数で渡す（テストで固定するため）。exe は新しいプロジェクト（`Hanasu.Command`、`AssemblyName=hanasu`、Exe、`net8.0-windows10.0.19041.0`、自己完結・単一ファイル・win-x64）で、Core を呼ぶだけ。DPAPI・Windows Hello・ジョブオブジェクト・DLL の探し方を絞る処理（今は Hanasu.Windows の internal）と、それが使う `AppLog`・`NativeMethods` の一部・`Hello_*` の文字列（17 言語）は、新しい共有のライブラリ（`Hanasu.Platform`、`net8.0-windows10.0.19041.0`）に移し、アプリと `hanasu` の両方が使う。`hanasu` は起動の最初に DLL の探し方を絞る（DEC-COM-148）。移した型を指す DEC-COM-144・147・148・149 の「実装の場所」と `design/security-windows.md` は、移すのと同じコミットで直す。PATH に入れる `cli\` には `hanasu.exe` だけを置き（ネイティブの DLL を混ぜると、ほかのプログラムの DLL の探し先に入る）、CI の「Check publish output」で確かめる。開発用の `Hanasu.Cli` はそのまま残す。
- 理由: 中身を Mac で確かめられる。Windows Hello の WinRT は Windows の TFM が要るので、exe と共有のライブラリだけにする。同じ部品をアプリと `hanasu` で使い、秘密の読み方を 1 つにする。

### WD2 文字列と、エージェントへの説明
- 決めたこと: `hanasu` の文（ヘルプ・エラー・doctor）は `Hanasu.Core/Properties/Strings.resx` に `Cmd_…` の名前で足し、16 言語の訳を入れる。MCP のツールの説明・`instructions`・結果の決まり文句（英語。DEC-COM-187）は、`Sources/Hanasu/Resources/` の共有のファイル（新規。プロンプトの JSON と同じ置き方）に移し、Mac はバンドルから（`Package.swift` の `resources` に `.copy` を足し、`scripts/build-app.sh` の確かめにも足す）、Windows は Core に `Link` で埋め込んで読む。エージェントへの説明は、文の枠を共有し、OS の名前・コマンドの書き方（Mac は POSIX のシェル、Windows は PowerShell の `& "…"` と Git Bash 向けの書き方）・パスを OS ごとに差し込む。`scripts/check-i18n.py` の調べる対象に、新しいプロジェクトを足す。
- 理由: Core の Strings は公開の型で、コンソールの exe から使える。英語の約束の文を 2 か所に書くと、ずれる。`common/` に置くと、今の Mac のビルド（SwiftPM のリソース）からは読めない。説明のコマンドは、それを動かすシェルで動かないと役に立たない。

### WD3 Mac と Windows の出力を、共有のテストデータでそろえる
- 決めたこと: `common/testdata/cli/` に、固定した架空の会議（時刻は UTC、ID と UUID は決めた値）と、コマンドごとの期待する `--json`・`--show-prompt` の出力を置く。テストは時差（Asia/Tokyo）と「今」（決めた日時）を固定して動かす。期待する出力は Mac の自己テスト（`--write-cli-golden`。新規）が作り、Mac の自己テストと Windows の `dotnet test` の両方が比べる。設定も固定する: テストデータのフォルダに決めた設定（辞書・追加の指示・アプリ名を送るか・出力の言語・文字起こしの言語・AI の送り先。すべて架空の値）を置き、Mac は子プロセスに環境変数（`HANASU_TEST_DEFAULTS_SUITE`・`HANASU_TEST_NOW`。自己テストのときだけ読む）で、その設定を書いた UserDefaults の suite と「今」を渡す。Windows は Core の関数に設定と「今」を引数で渡す。期待する出力に、作った人の設定や辞書が入らないことを、Mac の自己テストで確かめる（決めた設定にない語が出たら失敗）。抜粋（`snippet` の前後 32 文字）は書記素で数える（Swift の `Character`、.NET の `StringInfo` のテキスト要素）。比べないもの: 実行ファイルのパス・版・`ai` の値（`--ai` を要るコマンドは `--show-prompt` だけを比べる）・話者の表示の名前（訳が OS で違う。話者のキーは比べる）。一覧はテストデータのフォルダに書く。大文字小文字・全角半角の一致は、Windows のランナーの `dotnet test` でも動かす。
- 理由: 「同じ JSON の形」を、目で比べずに確かめ続けられる。計画の FUT-017（共有のテストデータ）の一部を先に作ることになる。

### WD4 ローカルの LLM を、アプリと `hanasu` で同時に使っても、アプリのサーバーを止めない
- 決めたこと: Mac（DEC-COM-184）と同じく、llama-server を起動したプロセスごとに記録（`%LOCALAPPDATA%\Hanasu\llm-server-<持ち主の pid>.json`）を書き、`hanasu` は、ほかの生きている持ち主のサーバーがあれば起動せず、終了コード 1 と「アプリを終了するか、外の AI を使う」旨を出す。`hanasu` も llama-server をジョブオブジェクトに入れ、Ctrl-C や異常な終了でも残さない。`ResolveExecutable` は、exe の隣の `llama\` のほか、1 つ上（`cli\` から見た `..\llama\`）も探す。
- 理由: モデルを二重に読み込むと数 GB のメモリを使う（REQ-COM-187）。今の CLI は Ctrl-C で llama-server を残しうる。

### WD5 `--app` は、Windows では exe の名前で既定の文体を引く
- 決めたこと: Mac の組み込みの既定の文体の一覧を、Mac の bundle ID と Windows の exe の名前の対応として、`Sources/Hanasu/Resources/` の共有のファイル（新規）に置き、Mac と Windows の両方が読む。共有のファイルに置くのは「識別子 → 文体と、訳さないアプリ名（Slack・Microsoft Outlook などの固有名）」だけ。訳す名前を持つ Mac だけのアプリ（メッセージ・メール）は、今のまま Swift のコードに `tr()` で残す（訳は xcstrings のまま。訳の置き場所を増やさない）。AI に送るアプリ名は、一覧にあれば一覧の名前、なければ Mac は今のまま（アプリの表示名か bundle ID）、Windows は exe の名前から拡張子を外したもの。こうすると、対応する bundle ID と exe の名前で、送るアプリ名も同じになる。Windows のアプリにはアプリ別の文体の設定がないので、`hanasu` は既定の一覧だけを使う。出力の言語の既定も Mac と同じ。
- 理由: 決定 5。2 か所に書くと、ずれる。訳した名前を JSON に置くと、`check-i18n.py` で漏れを調べられない。

### WD6 `hanasu mcp` の stdout を守る
- 決めたこと: 起動したときに本当の stdout のハンドルを複製して取っておき、プロセスの標準出力（`SetStdHandle` と `Console.SetOut`）を stderr に向ける。JSON-RPC は取っておいたハンドルにだけ、UTF-8・`\n` で書く。U+2028・U+2029 は `\u` の形にする。
- 理由: Core のどこかや子プロセスが標準出力に書いても、接続を壊さない（Mac の DEC-COM-186 と同じ守り方。`Console.SetOut` だけでは子プロセスに効かない）。

### WD7 PATH への登録
- 決めたこと: `HKCU\Environment` の `Path`（型は今の型のまま）に、`<アプリのフォルダ>\cli` を最後に足し、`WM_SETTINGCHANGE`（"Environment"）を送る。外すときは、足した項目と同じもの（大文字小文字を区別しない）だけを消す。別の場所の Hanasu の項目は、末尾が `\cli` で、その親に `Hanasu.exe` があるか、項目が「前に Hanasu が足した」と設定に記録したものと同じか、で見分ける（消えたフォルダも見分けられるように、足した値を設定に記録しておく）。
- 理由: 管理者の権限なしで、新しく起動したターミナルから使える（計画の 5.1）。

### WD8 自動アップデートと `hanasu`
- 決めたこと: アップデートの確認を出す前に、インストールしたフォルダの `cli\hanasu.exe` のパスで動いているプロセスを数え、あれば確認に件数と終わらせることを出す（決定 6）。承諾したら、入れ替えのスクリプト（DEC-REL-030）が、アプリの終了を待ったあと、名前を変える直前に同じパスのプロセスを探し直して終わらせ、それからフォルダの名前を変える。パスを読めないプロセス（管理者として動かしたもの）や、作業フォルダが `cli\` の中にあるターミナルのために名前を変えられなければ、今のやり直しが尽きたあと古い版のまま起動し直し、新しい版のアプリが理由を知らせる（スクリプトが結果をファイルに残し、起動したアプリが読む）。#98 のダウンロードの窓と中止はそのまま使う。
- 理由: 決定 6。DEC-REL-023（処理中は入れ替えない）の考え方に合わせ、黙って終わらせない。ダウンロードは最大 10 分かかるので、確認のときに数えたものだけでは足りない。

### WD9 文字コードと改行
- 決めたこと: 出力と入力を、相手がコンソールかどうかで分ける（`GetConsoleMode` が通ればコンソール）。
  - stdout・stderr がコンソール: `WriteConsoleW`（UTF-16）で書く。コードページに依らず表示できる。
  - stdout・stderr がパイプ・ファイル: ストリームに直接 UTF-8（BOM なし）のバイトで書き、改行は `\n`。`hanasu mcp` もこちら。
  - stdin がコンソール: `ReadConsoleW` で読む。
  - stdin がパイプ・ファイル: UTF-8 として読み、先頭の BOM は外す。UTF-8 として正しくなければ、`GetConsoleCP` のコードページで読み直す（cmd の `echo` のように、コンソールのコードページで書く相手のため）。
  - `Console.OutputEncoding` は変えない（親のコンソールの設定を書き換えない）。
- 理由: .NET のコンソールは、既定ではコンソールのコードページで読み書きし、改行は CRLF。UTF-8 のバイトをコンソールに書くと、conhost はコードページとして表示して化ける。パイプには Mac と同じバイトを出し、JSON を UTF-8 で読めるようにする。PowerShell が外部のコマンドの出力を読むときは `[Console]::OutputEncoding` を使うので、その設定の行を説明に書く（W1）。

## やらないこと
- Windows のアプリの画面に、会議の検索・会議への質問・選択を声で編集・アプリ別の文体・「AI チャット・質問」の送り先を足すこと（決定 1 は `hanasu` からの利用）。あとで要るなら FUT にする。
- Windows の管理者のポリシー（FUT-020）。
- 開発用の `Hanasu.Cli` を利用者向けにすること（そのまま残す）。

## 文書
- `windows/README.md`（配布物の中身に `cli\hanasu.exe`、Mac との差の表の更新。`ask` の AI の違い）、`docs/design/cli.md`（Windows の節）、`docs/design/security-windows.md`（1 章の表に `hanasu` の行。呼ぶたびの確認に慣れてしまう危険、`hanasu mcp` のロックでの鍵の破棄、DLL の探し方）。
- README（`README.md` と 16 の訳）の「Use it from the terminal and AI agents *(Mac)*」を Mac と Windows の節にし、Windows の設定の名前と PowerShell 5.1 の文字コードを書く。
- `tagpr.yml` のリリース文のインストールの手順に `cli\hanasu.exe` を足す。
- plans/cli.md の状態、roadmap の FUT-015・FUT-003。

## 手順
1. spec: 上の表のとおり既存の要件・設計判断を直し、W1〜W7・WD1〜WD9 を spec の番号で書く。コードの `// 要件:` と、Swift・C# のテストの `// 確かめ方:` を付ける。
2. Mac 側の直し: 決定 4・7（`hanasu ask`・`ask_meetings`・`doctor`）、決定 8（読めない会議の数。Mac の `meetings`・`actions`・`ask` と MCP）、決定 9（REQ-COM-189 の「確認待ち」を外す）。
3. 共有のファイル（MCP の英語の文・既定の文体の一覧）を `Sources/Hanasu/Resources/` に移し、Mac が読む（`Package.swift` の `resources`・`scripts/build-app.sh` の確かめ）。`common/testdata/cli/`（固定した会議・固定した設定・期待する出力）と、Mac の `--write-cli-golden`・設定の suite と「今」の環境変数・比べる自己テスト。
4. `Hanasu.Platform` を作り、DPAPI・Windows Hello・ジョブオブジェクト・DLL の探し方と、それが使うものを移す（アプリの振る舞いは変えない）。DEC-COM-144・147・148・149 の「実装の場所」と `security-windows.md` を同じコミットで直す。アプリの保存のやり直し（W6）。
5. Core: `Hanasu.Core.Command`（引数・終了コード・出力と入力の文字コード（WD9）・JSON・会議の指定と期間・`meetings`・`actions`・`dict apply`・`doctor`・ヘルプ）。会議を並べて読み、読めない会議を数える（W7）。
6. Core: 検索・質問・書き換え・文体と既定の一覧・`refine`・`edit`・`ask`。`TextPurpose` に `Edit`（音声入力の AI と同じ送り先・短い処理）と `Ask`（会議の AI と同じ送り先・長い処理。Mac の DEC-COM-142 の effort と max_tokens に合わせる）を足す。
7. Core: MCP（新旧の版の手順・5 つのツール・上限・`notice`・引数の値の誤りは `isError`）。
8. ローカルの LLM の記録とジョブオブジェクト（WD4）。
9. exe（`Hanasu.Command`）と Windows Hello（W3。`Microsoft.Win32.SystemEvents` を足し、lock ファイルも更新する）。
10. 配布: `tagpr.yml`・`windows.yml` で `cli\` に publish し、`cli\` に `hanasu.exe` だけがあることを「Check publish output」で確かめ、CI で動かす（W1 の確かめ方・W7 の速さ）。`windows.yml` の `paths` に、共有のファイル（`Sources/Hanasu/Resources/` の新しいファイル）と `common/testdata/cli/**` を足す。自動アップデート（W5。DEC-REL-022・030 を直す）。
11. 設定の「コマンドと MCP」のタブ（W4）。
12. 文字列の 17 言語（Core と Hanasu.Platform・Hanasu.Windows の .resx。i18n エージェントに 3 言語ずつ）。UX の項目を足し、`scripts/ui-cases.py md`。
13. 文書。
14. 確かめる。

2〜9 は Core と共有のテストデータを順に使うので、1 つのセッションで順に行う。コミットは手順ごとに分ける。

## 確かめ方
- `cd windows && dotnet test Hanasu.Core.Tests`（この Mac で動く）と、CI の Windows のランナーの `dotnet test`（ファイルの共有・大文字小文字の一致・速さ）
- `cd windows && dotnet build`（Windows の TFM のプロジェクトも、この Mac でコンパイルできる）
- `swift build`・`swift build -c release`・`.build/debug/Hanasu --test-hanasu-command`（期待する出力と比べる）
- `python3 scripts/check-spec.py`・`check-i18n.py`・`i18n-resx.py check`・`ui-cases.py check`
- CI（windows.yml）: publish した `cli\hanasu.exe` を動かす（W1）
- 実機（Windows）: Windows Hello の確認、PATH に入れて新しいターミナルで動くこと、Claude Desktop と Claude Code に登録して会議について答えること、自動アップデートと MCP のクライアントの振る舞い、アプリとローカルの AI を同時に使うこと、PowerShell 5.1 のパイプ

## 敵対的レビュー

2026-11-11 に、requirements-reviewer（Opus）2 つ（A: 目的・受け入れ条件・失敗時・範囲・仮に決めたこと、B: 既存の要件・Mac と Windows・17 言語・データと安全・手順の事実・確かめ方）でレビューした。指摘はコードで確かめてから仕分けた。

| 指摘 | 仕分け | どう直したか |
| --- | --- | --- |
| `hanasu ask` の AI が #95 の REQ-COM-025 とぶつかる | 聞いた → 決定 4 | Mac を「AI チャット・質問」に直し、Windows は「会議」 |
| `--app` を「名前を送るだけ」にするのは「全部」と食い違う | 聞いた → 決定 5 | WD5 で既定の文体の一覧を共有する |
| 自動アップデートで `hanasu` を黙って終わらせる。MCP が立ち直る前提を確かめていない | 聞いた → 決定 6 | W5・WD8 で知らせてから終わらせ、クライアントの振る舞いを実機で確かめる |
| `hanasu` が読んでいる間、Windows でアプリの保存が失敗する | 直した | W6 |
| 文字コード（コードページ・PowerShell のパイプ）と改行が決まっていない | 直した | WD9 と W1 の受け入れ条件 |
| `hanasu mcp` が Windows Hello の鍵をロックのあとも持ち続ける（DEC-COM-144 とぶつかる）。確認が出ない・時間切れ・画面のないセッション。DLL の探し方 | 直した | W3（DEC-COM-144 のとおり）と WD1 |
| エージェントへの説明と Claude Code のコマンドが PowerShell・cmd で動かない。`common/` のファイルは Mac のビルドから読めない | 直した | WD2 |
| Windows の速さの条件がない。読めない会議を黙って飛ばす | 直した | W7 |
| `cli\hanasu.exe` がない・一時フォルダで動いているとき | 直した | W4 |
| 既存の要件の対象を広げるだけでは成り立たない（Mac 専用の中身・重なり・設計判断・DEC-COM-185・187・REQ-DIC-160） | 直した | 「既存の要件・設計判断の扱い」の表 |
| 共有のテストデータが時差・今日の日付・訳・`apple`・乱数の ID で一致しない。検索の場所の種類が Mac にない | 直した | WD3 と W2 |
| Platform の TFM と、移すものの依存。入れ替えのスクリプトと PATH の処理のテストの置き場所 | 直した | WD1 と W4・W5 の確かめ方 |
| `--ai apple` と doctor の `apple`、新しく起動したターミナルの条件、別の場所の項目の見分け方、計画に存在しないパスを書いた、FUT-003・DEC-COM-107・tagpr のリリース文・タグ・`ui-cases.py md` の抜け、DEC-COM-186 より弱い守り方 | 直した | 表・W4・WD7・WD6・文書・手順 |

2026-11-11 に、直した計画を requirements-reviewer（Opus）1 つで、観点 1〜11 のすべてについてもう一度レビューした。

| 指摘 | 仕分け | どう直したか |
| --- | --- | --- |
| 「AI チャット・質問」の既定はローカルなので、決定 4 のままだと、既定のままの人で `ask` が失敗するか、呼ぶたびにモデルを読み込み直す | 聞いた → 決定 7 | 保存した人だけ「AI チャット・質問」、ほかは「会議」。REQ-MTG-127・REQ-COM-024 も表に足した |
| 読めない会議を stderr にだけ出すと、MCP のエージェントに届かず、Windows だけ REQ-MTG-120・REQ-COM-181 と違う。何を数えるかがあいまい | 聞いた → 決定 8 | W7 で、Mac と Windows の両方で `unreadableMeetingCount` を出し、開けない・読めないものだけを数える |
| REQ-COM-189 の「確認待ち」（`isError`）を Windows にも広げることを伝えていない | 聞いた → 決定 9 | 表と手順 2・7 |
| WD9 はパイプしか考えておらず、コンソールの表示・cmd の `echo`・PowerShell の読み取りで化ける | 直した | WD9 をコンソールとパイプで分け、W1 の受け入れ条件を向きごとに書き直した |
| 共有のテストデータを Mac で作ると、作った人の設定と辞書が入る | 直した | WD3 で設定を固定し、環境変数で子プロセスに渡す |
| `--app` で AI に送るアプリ名と、訳した名前の置き場所が決まっていない | 直した | WD5 |
| アップデートの細部（作業フォルダ・管理者の `hanasu`・ダウンロード中に起動したもの・DEC-REL-022・030・#98 と REL の番号）と、判断できない受け入れ条件（W5 の文・W7 の速さ） | 直した | W5・WD8・W7・表・状態の行 |
| `windows.yml` の `paths`、`Package.swift` と `build-app.sh`、Windows の `doctor --json` の形、Platform に移したあとの「実装の場所」、ロックのあとの再確認と `SystemEvents`、`TextPurpose` の `Ask`、`cli\` に `hanasu.exe` だけ、抜粋の数え方、ログに中身を書かない | 直した | 手順 3・4・6・9・10、W1・W3、WD1・WD2・WD3 |

## 仮に決めたこと
- Mac と Windows の出力を共有のテストデータでそろえ、期待する出力は Mac が作る（WD3）。話者の表示の名前は比べない。
- `hanasu` の文は Core の `Strings.resx` に足す（WD2）。
- Windows Hello の確認の待ち時間は 60 秒（W3）。
- アプリの保存のやり直しは 50 ms ずつ最大 1 秒（W6）。
- 「AI チャット・質問」を保存したかは、`UserDefaults` のアプリの領域に値があるかで見る（決定 7）。
- 読めない会議の数の項目名は `unreadableMeetingCount`。0 のときも出す（W7）。
- Windows の速さは、CI の 3 回のうちいちばん速い値が 2 秒を超えたら落とす（W7）。
- Windows で一覧にないアプリの名前は、exe の名前から拡張子を外したもの（WD5）。
- パイプで受け取った文が UTF-8 として正しくなければ、コンソールのコードページで読み直す（WD9）。
