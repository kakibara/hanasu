# 配布・リリースの仕様（REL）

リリースの作り方と、配布物の形について、**実装済み**の振る舞いのうち、要件（REQ）と設計判断（DEC）を並べる。

- 区分・ID・タグの決まりは [docs/README.md](../README.md)。
- 手順は [docs/releasing.md](../releasing.md)。

---

## 要件

### REQ-REL-001 リリースは tagpr で行う
- 内容: `main` に変更が入ると tagpr がリリース PR を作り、それをマージするとタグとリリースができる。
- 受け入れ条件: リリース PR（`VERSION` と `CHANGELOG.md` の更新）をマージすると、そのバージョンのタグとリリースができる。
- 出典: ユーザーの依頼（2026-11-02、c35988b「リリースを tagpr で行う」）
- 対象: Mac / Windows
- 実装の場所: `.tagpr`、`.github/workflows/tagpr.yml`（`tagpr` ジョブ）
- 確かめ方: リリース PR をマージしたあとの Actions の実行結果

### REQ-REL-002 自己署名の証明書で署名してリリースする
- 内容: Apple の公証を受けず、自己署名の証明書「Hanasu Release Signing」で Mac 版を署名する。すべてのリリースを同じ証明書で署名する。
- 受け入れ条件: リリースの `Hanasu.app` が同じ証明書で署名され、アップデートしてもアクセシビリティなどの許可が外れない。
- 出典: ユーザーの依頼（2026-11-02、c35988b「リリースを tagpr で行う」で入れた自己署名でのリリース）
- 対象: Mac
- 実装の場所: `scripts/setup-release-signing.sh`、`scripts/ci-import-signing-cert.sh`、`.github/workflows/tagpr.yml`（`mac` ジョブ）
- 確かめ方: `codesign -dv --verbose=2 Hanasu.app` で署名者を確かめる

### REQ-REL-003 Mac 版は zip で配る
- 内容: Mac 版は `Hanasu-<バージョン>-macOS.zip` としてリリースに添付する。
- 受け入れ条件: リリースに `Hanasu-<版>-macOS.zip` が付き、Finder で展開した `Hanasu.app` が署名を保ったまま開ける。
- 出典: 2026-11-02 に一度 dmg に変えた（2f0a153）が、2026-11-03 にユーザーが「zip の方が適していた」と言い、次の版から zip に戻した（PR #20）
- 対象: Mac
- 実装の場所: `.github/workflows/tagpr.yml`（`mac` ジョブ）
- 確かめ方: リリースの添付ファイル（v1.3.0 で `Hanasu-1.3.0-macOS.zip` が付いたことを確かめた）

### REQ-REL-004 Windows 版もリリースに添付する
- 内容: Windows 版を `Hanasu-<バージョン>-Windows-x64.zip` としてリリースに添付する。
- 受け入れ条件: Windows 版のあるタグのリリースに `Hanasu-<版>-Windows-x64.zip` が付く。
- 出典: ユーザーの指定（2026-11-03、PR #20）「Windows 版もリリースに添付する」
- 対象: Windows
- 実装の場所: `.github/workflows/tagpr.yml`（`windows` ジョブ）
- 確かめ方: リリースの添付ファイル（v1.3.0 で `Hanasu-1.3.0-Windows-x64.zip` が付いたことを確かめた。CI の `windows.yml` でも publish の中身を確かめている）

### REQ-REL-005 Apache License 2.0 で配布し、配布物にライセンスと第三者の表示を入れる
- 内容: Hanasu は Apache License 2.0 で配布する（2026-11-03 までは AGPL-3.0）。Mac 版・Windows 版の配布物には、Hanasu のライセンス（`LICENSE`・`NOTICE`）と、組み込んだ第三者のソフトウェアのライセンス表示を入れる。
- 受け入れ条件: リポジトリの `LICENSE` が Apache License 2.0 の条文である。`Hanasu.app/Contents/Resources` に `LICENSE`・`NOTICE`・`THIRD_PARTY_NOTICES.md` がある。Windows 版の zip の `Hanasu` フォルダに `LICENSE.txt`・`NOTICE.txt`・`THIRD_PARTY_NOTICES.md`・`dotnet-THIRD-PARTY-NOTICES.txt` がある。
- 出典: ユーザーの依頼（2026-11-03「Apache-2.0 にして、Windows のライセンスの問題も修正して」）。v1.3.0 の Windows 版の zip にライセンスの表示が入っていなかったことへの対応
- 対象: Mac / Windows
- 実装の場所: `LICENSE`、`NOTICE`、`THIRD_PARTY_NOTICES.md`、`windows/THIRD_PARTY_NOTICES.md`、`scripts/build-app.sh`、`windows/Hanasu.Windows/Hanasu.Windows.csproj`、`.github/workflows/windows.yml`（publish の中身の確認）
- 確かめ方: `./scripts/build-app.sh` のあとの `ls build/Hanasu.app/Contents/Resources`、CI の `windows.yml` の「Check publish output」

### REQ-REL-006 版の上げ幅とリリース文を、決まった手順とテンプレートで作る
- 内容: リリースのたびに、前の版からの変更をまとめて版の上げ幅（major / minor / patch）を決め、テンプレートに沿ったリリース文を書いて、リリースの本文の先頭に入れる。手順はスキル（Claude Code の `release`）にまとめる。
- 受け入れ条件:
  - 新しい機能が入った版は minor 以上になる（tagpr の既定の patch のままにしない）。
  - リリースの本文が「リリース文（ハイライト・新しい機能・改善・不具合の修正・気をつけること）→ PR の一覧 → インストールの手順と SHA-256」の順になる。リリース文のない版は今までどおり（PR の一覧 → インストール）。
  - 手動の実行で作り直しても、リリース文とインストールの手順が二重にならない。
- 出典: ユーザーの依頼（2026-11-04「1.4の方が適切では？リリーススキルを作成して、バージョンの判定とリリース内容をまとめてリリース文を作成するのと、そのためのリリース文テンプレートの作成を含めてリリース手順をスキル化して」）
- 対象: Mac / Windows
- 実装の場所: `.claude/skills/release/SKILL.md`（手順）、`docs/releases/TEMPLATE.md`（テンプレート）、`scripts/compose-release-notes.py`、`.github/workflows/tagpr.yml`（`publish` ジョブ）
- 確かめ方: `python3 scripts/compose-release-notes.py --self-test`。リリースのあと `gh release view <タグ>` で本文の順番を見る

### REQ-REL-010 起動時に新しい版を確かめ、ユーザーが選んだときだけアップデートする
- 内容: 起動したときに、GitHub の最新のリリースが今の版より新しいかを確かめる。新しければ、入れ替えてよいかを尋ね、ユーザーが「アップデート」を選んだときだけ、新しい版をダウンロードして入れ替え、開き直す。
- 受け入れ条件:
  - 新しい版があると、版とリリース文を出して「アップデート」「あとで」「この版をスキップ」を尋ねる。尋ねずにダウンロード・入れ替えはしない。
  - 「アップデート」を選ぶと、その OS の zip をダウンロードし、確かめてから今のアプリと入れ替えて開き直す。入れ替えられないときは理由を出し、リリースのページを開けるようにする。
  - 新しい版がない・確かめられない（通信できない）ときは、起動時には何も出さない。
- 出典: ユーザーの依頼（2026-11-05「起動時にアップデートを確認してアップデートがあったらユーザーへの確認の上でアップデートを行う仕組みを作成して」）
- 対象: Mac / Windows
- 実装の場所: Mac は `AppUpdater`（`Sources/Hanasu/AppUpdate.swift`）と `AppDelegate.applicationDidFinishLaunching`。Windows は `UpdateService.CheckOnLaunchAsync`（`windows/Hanasu.Windows/Services/UpdateService.cs`）と `Hanasu.Core.Update`
- 確かめ方: Mac は `Hanasu --update-selftest`（版の比べ方・リリースの読み方・スキップ）、`Hanasu --check-update --current 1.0.0`（GitHub への問い合わせ）、`Hanasu.app/Contents/MacOS/Hanasu --verify-update <zip> --version <版>`（入れ替えの前の確認）。Windows は `cd windows && dotnet test Hanasu.Core.Tests`（`UpdateTests`）。入れ替えと開き直しは実機で確かめる

### REQ-REL-011 メニューから、いつでもアップデートを確かめられる
- 内容: メニューの「アップデートを確認…」（と設定の「今すぐ確認」）で、新しい版があるかをいつでも確かめられる。新しい版があれば REQ-REL-010 と同じく尋ねる。
- 受け入れ条件: 新しい版がなければ「最新です」と今の版を出す。確かめられなければ理由を出す。「この版をスキップ」を選んだ版も知らせる。
- 出典: ユーザーの依頼（2026-11-05「また、アップデートを確認するという機能も追加して」）
- 対象: Mac / Windows
- 実装の場所: Mac は `AppDelegate.checkForUpdates`（メニューバーとアプリのメニュー）、`UpdateSettingsSection`（設定の「一般」）。Windows は `TrayIcon`（タスクトレイのメニュー）、`SettingsWindow`（「一般」）、`UpdateService.CheckManuallyAsync`
- 確かめ方: `Hanasu --check-update`、`Hanasu --update-selftest`、`cd windows && dotnet test Hanasu.Core.Tests`。ダイアログは実機で確かめる

---

## 設計判断

### DEC-REL-001 リリースは下書きで作り、添付してから公開する
- 決めたこと: tagpr はリリースを下書き（`release = draft`）で作り、Mac 版と Windows 版の zip を添付し終えてから公開する。
- 理由: 添付ファイルのないリリースが公開されないようにする。
- 決めた場面: c35988b、PR #20
- 関係する要件: REQ-REL-001
- 対象: Mac / Windows
- 実装の場所: `.tagpr`、`.github/workflows/tagpr.yml`（`publish` ジョブ）

### DEC-REL-002 リリースのジョブを 4 つに分ける
- 決めたこと: `tagpr`（ubuntu）→ `mac`（macos-26）と `windows`（windows-latest）→ `publish`（ubuntu）。`windows/` がないタグでは windows ジョブは何もしない。
- 理由: それぞれの OS のランナーでビルドする。Windows 版の PR（#19）より先にマージしても動くようにする。
- 決めた場面: PR #20
- 関係する要件: REQ-REL-003, REQ-REL-004
- 対象: Mac / Windows
- 実装の場所: `.github/workflows/tagpr.yml`

### DEC-REL-003 Mac 版の zip は ditto で作る
- 決めたこと: `ditto -c -k --keepParent` で `Hanasu.app` を zip にする。
- 理由: 署名と拡張属性を保ったまま、Finder で展開できる。
- 決めた場面: PR #20
- 関係する要件: REQ-REL-003
- 対象: Mac
- 実装の場所: `.github/workflows/tagpr.yml`（`mac` ジョブ）

### DEC-REL-004 Windows 版の zip には、Whisper のネイティブ DLL も入れる
- 決めたこと: `dotnet publish … -r win-x64 --self-contained -p:PublishSingleFile=true` の出力フォルダを、`Hanasu` フォルダごと zip にする（`Hanasu.exe` と `runtimes/win-x64/`）。
- 理由: Whisper.net は exe の隣の DLL を読むので、exe だけでは Whisper を使えない。
- 決めた場面: PR #20
- 関係する要件: REQ-REL-004
- 対象: Windows
- 実装の場所: `.github/workflows/tagpr.yml`（`windows` ジョブ）

### DEC-REL-005 リリースノートに、インストールの手順と SHA-256 を足す
- 決めたこと: publish ジョブで、macOS と Windows のインストールの手順と、両方の zip の SHA-256 をリリースノートに足してから公開する。作り直したときに二重にならないよう、前に付けた「## インストール」から後ろを除いてから付け直す。
- 理由: 公証のない自己署名のアプリを開く手順を、リリースのページで分かるようにする。
- 決めた場面: PR #20
- 関係する要件: REQ-REL-002, REQ-REL-003, REQ-REL-004
- 対象: Mac / Windows
- 実装の場所: `.github/workflows/tagpr.yml`（`publish` ジョブ）、`scripts/compose-release-notes.py`（本文の組み立て。DEC-REL-010）

### DEC-REL-006 既存のタグの添付ファイルを、手動の実行で作り直せる
- 決めたこと: Actions の「tagpr」をタグを指定して手動で実行すると、tagpr を飛ばして両方の zip を作り直す。
- 理由: ビルドや添付に失敗したときに、タグを打ち直さずにやり直せるようにする。ただし、ワークフローは `main` のものを使うが、ビルドするコードとリリース文（DEC-REL-010）はタグの時点のものなので、タグの時点のコードが原因の失敗はこれでは直らない。公開前の下書きなら、直しを `main` に入れ、下書きとタグを消して、直した `main` にタグを付け直してから手動で実行する（下書きのリリースは公開するまでタグを作らないので、タグを先に push する）。公開済みの版は消さず、次のパッチで直す（v1.4.0 のリリース（2026-11-04）で、タグの時点のコードの不具合（Mac 版の最適化ビルドでだけ起きる型の推論の時間切れ）は手動の実行では直らず、タグを付け直したため。手順は `.claude/skills/release/SKILL.md` の「失敗したとき」）。
- 決めた場面: 2f0a153、PR #20
- 関係する要件: REQ-REL-001
- 対象: Mac / Windows
- 実装の場所: `.github/workflows/tagpr.yml`（`workflow_dispatch`）

### DEC-REL-007 ローカルのビルドも、自己署名の証明書で署名できる
- 決めたこと: `scripts/create-signing-cert.sh` でローカル用の自己署名証明書「Hanasu Local Signing」をログインキーチェーンに作り、`build-app.sh` はそれ（か `SIGN_IDENTITY`）で署名する。なければアドホック署名にする。
- 理由: アドホック署名はビルドごとに署名が変わり、アクセシビリティの許可が外れる。
- 決めた場面: 初版（a787da8）
- 関係する要件: REQ-REL-002
- 対象: Mac
- 実装の場所: `scripts/create-signing-cert.sh`、`scripts/build-app.sh`

### DEC-REL-008 Windows 版の話者分離のネイティブ DLL は、exe の隣に置く
- 決めたこと: `sherpa-onnx-c-api.dll` と `onnxruntime.dll` は single file の exe に入れず、exe の隣に置いて、フォルダごと zip にする。`windows.yml` の確認にも入れる。
- 理由: exe に入れると一時フォルダに展開して読むことになり、Windows 11 の System32 にある別の版の `onnxruntime.dll` と取り違えるおそれがある。
- 決めた場面: PR #19
- 関係する要件: REQ-REL-004
- 対象: Windows
- 実装の場所: `windows/Hanasu.Windows/Hanasu.Windows.csproj`、`.github/workflows/windows.yml`


### DEC-REL-009 版の上げ幅は、今の利用者への影響で決める
- 決めたこと: 上から順に当てはめる。major は、今の利用者が何かしないと使い続けられない変更（動作環境の引き上げ、設定や保存の形が前の版で読めなくなる、機能の廃止）。minor は新しい機能（新しい要件、要件の「対象」に OS が足された、新しい設定や選択肢）。patch はそれ以外（不具合の修正、文言・見た目の調整、文書・CI・内部の整理）。迷ったら大きい方にし、理由をユーザーに見せる。1.x のあいだ、major はユーザーが決める。版を変えるときは、tagpr のリリース PR の `VERSION` と `CHANGELOG.md` の先頭の見出しを直す（tagpr はマージのときに `VERSION` の版を使う）。
- 理由: tagpr は何もしなければ patch を上げるので、新しい機能が入った版も patch になっていた（v1.3.1〜v1.3.3）。新しい要件が増えたかは spec の差分で機械的に分かるので、判定の手がかりにしやすい。ラベル（`tagpr:minor`）はマージのときに読まれるかが README からは分からず、`VERSION` を直す方は「マージのときに優先する」と書かれている。
- 決めた場面: ユーザーの依頼（2026-11-04「1.4の方が適切では？リリーススキルを作成して、バージョンの判定とリリース内容をまとめてリリース文を作成するのと、そのためのリリース文テンプレートの作成を含めてリリース手順をスキル化して」）
- 関係する要件: REQ-REL-001, REQ-REL-006
- 対象: Mac / Windows
- 実装の場所: `.claude/skills/release/SKILL.md`（「2. 版の上げ幅を決める」「4. リリース PR を直す」）

### DEC-REL-010 リリース文は docs/releases/<タグ>.md に置き、publish ジョブが本文の先頭に入れる
- 決めたこと: リリース文はテンプレート（`docs/releases/TEMPLATE.md`）から `docs/releases/v<版>.md` に書き、tagpr のリリース PR のブランチにコミットする。publish ジョブはタグの時点のそのファイルを読み、`scripts/compose-release-notes.py` で「リリース文（`<!-- release-notes -->` で囲む）→ tagpr の PR の一覧 → インストールの手順と SHA-256」の順に組み立てる。テンプレートのコメントと中身のない見出しは除く。作り直すときは、前に入れたリリース文とインストールの手順を除いてから組み立てる。ファイルがなければ今までどおり。
- 理由: 公開のあとに本文を手で書き換えると、手動の実行（DEC-REL-006）で作り直したときに消える。リポジトリに置けば、レビューでき、作り直しても同じ本文になる。tagpr の本文は GitHub の自動のリリースノート（PR の一覧）だけで、自分で書いた文を入れる設定がない。リリース PR のブランチに足したコミットは、tagpr が PR を更新しても引き継がれる（tagpr の README）。
- 決めた場面: ユーザーの依頼（2026-11-04「1.4の方が適切では？リリーススキルを作成して、バージョンの判定とリリース内容をまとめてリリース文を作成するのと、そのためのリリース文テンプレートの作成を含めてリリース手順をスキル化して」）
- 関係する要件: REQ-REL-006
- 対象: Mac / Windows
- 実装の場所: `docs/releases/TEMPLATE.md`、`scripts/compose-release-notes.py`、`.github/workflows/tagpr.yml`（`publish` ジョブ）

### DEC-REL-020 新しい版は GitHub の releases/latest で知り、版は数字ごとに比べる
- 決めたこと: `https://api.github.com/repos/kakibara/hanasu/releases/latest` を、認証なしで 1 回呼ぶ。下書きとプレリリースは知らせない。`tag_name`（`v1.6.0`）と今の版（Mac は Info.plist の `CFBundleShortVersionString`、Windows はアセンブリの版）を、`.` で区切った数字ごとに比べ、新しいときだけ知らせる。リリース文は本文の `<!-- release-notes -->` の中（なければ「## インストール」の前まで）を出す。
- 理由: リリースは tagpr が GitHub に作る（REQ-REL-001）ので、別の置き場（appcast など）を持たずに済む。releases/latest は公開済みの最新の版だけを返す（DEC-REL-001 の下書きを拾わない）。文字列の比較では 1.10.0 が 1.9.0 より古くなる。認証なしの API は 1 時間に 60 回までなので、起動時に 1 回だけ呼ぶ。
- 決めた場面: ユーザーの依頼（2026-11-05、起動時のアップデートの確認）
- 関係する要件: REQ-REL-010, REQ-REL-011
- 対象: Mac / Windows
- 実装の場所: Mac は `AppVersion`、`UpdateRelease.parse`、`UpdateHTTP.fetchLatestRelease`。Windows は `AppVersion`、`ReleaseParser`、`UpdateChecker`

### DEC-REL-021 zip は https の GitHub のホストからだけ取り、API の SHA-256 と大きさで確かめる
- 決めたこと: 問い合わせとダウンロードは https だけで、ホストは `github.com`・`api.github.com`・`*.githubusercontent.com`（zip の転送先の CDN）に限る。転送もそのホストへだけ従う。zip は名前（`Hanasu-<版>-macOS.zip` / `Hanasu-<版>-Windows-x64.zip`）で選び、API が返す `digest`（`sha256:…`）と `size` に合わなければ使わない。`digest` がなければ入れ替えず、リリースのページを開くだけにする。秘密のヘッダーは送らない。
- 理由: 通信の途中や転送先で差し替えられた zip を入れないため。GitHub はアップロードされたファイルの SHA-256 を API で返す（リリースの本文の SHA-256（DEC-REL-005）と同じ値）。
- 決めた場面: ユーザーの依頼（2026-11-05、起動時のアップデートの確認）
- 関係する要件: REQ-REL-010
- 対象: Mac / Windows
- 実装の場所: Mac は `UpdateHTTP`（`isAllowed`・`download`）。Windows は `UpdateHosts`、`UpdateChecker.DownloadAsync`、`ModelDownload.DownloadVerifiedAsync`

### DEC-REL-022 尋ねるのは「アップデート / あとで / この版をスキップ」。スキップした版は起動時には知らせない
- 決めたこと: 新しい版の確認では、版・今の版・リリース文を出し、「アップデート」「あとで」「この版をスキップ」から選ばせる。スキップした版は設定に覚え、起動時の確認ではその版を知らせない（もっと新しい版が出れば知らせる）。メニューからの確認はスキップを見ずに知らせ、新しい版がなければ「最新です」と出す。確かめている・尋ねている途中にメニューから確かめると、「確かめています」と出す（ダイアログを 2 つ出さない）。起動時の確認が録音の終わりを待つ間にメニューから尋ねた版は、待ち終えてももう尋ねない（Mac）。
- 理由: ユーザーの確認なしに入れ替えないため（REQ-REL-010）。起動のたびに同じ版を尋ねられ続けないようにしつつ、自分で確かめたときは必ず答える。
- 決めた場面: ユーザーの依頼（2026-11-05、起動時のアップデートの確認と、アップデートを確認する機能）
- 関係する要件: REQ-REL-010, REQ-REL-011
- 対象: Mac / Windows
- 実装の場所: Mac は `AppUpdater.ask`、`UpdateSettings.shouldOffer`。Windows は `UpdatePromptWindow`、`UpdateChecker.ShouldPrompt`

### DEC-REL-023 録音中・会議の記録中・処理中は入れ替えない
- 決めたこと: 音声入力（と Mac の「選択を声で編集」）・会議の記録・議事録の作り直し・モデルのダウンロード（Whisper とローカルの LLM のモデル）が止まっているときだけ入れ替える。起動時の確認は、それらが終わるまで尋ねるのを待つ（Mac）か、入れ替えの直前に断って、終わってから選び直すよう伝える。ダウンロードのあとにもう一度確かめる。
- 理由: 入れ替えるにはアプリを終えるので、録音や会議の記録が途中で切れ、文字起こし・議事録が作られなくなる。数 GB のモデルのダウンロードもやり直しになる。
- 決めた場面: ユーザーの依頼（2026-11-05、起動時のアップデートの確認）
- 関係する要件: REQ-REL-010
- 対象: Mac / Windows
- 実装の場所: Mac は `AppUpdater.isBusy`（`AppDelegate` が渡す）。Windows は `UpdateService.IsRecordingOrProcessing`

### DEC-REL-024 起動時の確認は設定で切れ、初めての起動ではしない。失敗は知らせない
- 決めたこと: 設定の「一般」に「起動時にアップデートを確認する」（既定はオン）を置く。起動の 5 秒あとに確かめる。初めての起動（Mac はオンボーディング、Windows は設定がまだないとき）では確かめない。Mac は版の分からない起動（`swift build` の実行ファイル）、Windows は手元のビルド（版の先頭が 0）でも確かめない。起動時の確認で通信などに失敗しても、ログに書くだけで何も出さない。
- 理由: 通信を望まない人が止められるようにする。初めての起動は最新の版を入れた直後で、オンボーディングと重ねたくない。起動直後の設定画面などと重ならないよう少し待つ。オフラインのたびにエラーを出さない（メニューからの確認では理由を出す。REQ-REL-011）。
- 決めた場面: ユーザーの依頼（2026-11-05、起動時のアップデートの確認）
- 関係する要件: REQ-REL-010
- 対象: Mac / Windows
- 実装の場所: Mac は `UpdateSettings`、`AppUpdater.checkOnLaunch`、`UpdateSettingsSection`。Windows は `AppSettings.CheckForUpdatesOnLaunch`、`UpdateService.CheckOnLaunchAsync`、`SettingsWindow`

### DEC-REL-025 Mac では、新しい Hanasu.app が今と同じ証明書で署名されているときだけ入れ替える
- 決めたこと: 展開した `Hanasu.app` の署名を（入れ子のコードまで）確かめ、署名の葉の証明書が今動いている `Hanasu.app` と同じこと、bundle ID が同じこと、版がリリースの版と同じことを確かめる。今の Hanasu がアドホック署名（証明書がない）なら入れ替えない。
- 理由: 公証のない自己署名（REQ-REL-002）なので、Gatekeeper に中身の確かさを頼れない。同じ証明書で署名されていれば、配布用の鍵を持つ人が作ったものだと分かり、入れ替えてもアクセシビリティなどの許可が外れない。手元でビルドした Hanasu（ローカル用の証明書かアドホック。DEC-REL-007）は配布物と証明書が違うので、入れ替えるとかえって許可が外れる。
- 決めた場面: ユーザーの依頼（2026-11-05、起動時のアップデートの確認）
- 関係する要件: REQ-REL-002, REQ-REL-010
- 対象: Mac
- 実装の場所: `UpdateSignature`（`Sources/Hanasu/AppUpdate.swift`）

### DEC-REL-026 Mac の入れ替えは、Hanasu が終わるのを待つシェルスクリプトで行う
- 決めたこと: 今の Hanasu が証明書で署名されていない（DEC-REL-025）・`.app` でない・App Translocation（隔離されたまま開いた）・書き込めないフォルダなら、ダウンロードの前に断ってリリースのページを案内する。zip は `Hanasu.app` と同じボリュームの作業フォルダ（`itemReplacementDirectory`）に落として `ditto -x -k` で展開する（展開と署名の確認は UI のスレッドの外で行う）。固定の中身のスクリプト（パスは引数で渡す）を `/bin/sh` で動かしてから Hanasu を終える。スクリプトは Hanasu の終了を待ち（60 秒まで）、今の `.app` を作業フォルダへ移し、新しい `.app` を同じ場所に移す（失敗したら元に戻す）。そのあと `open` で開き直し、作業フォルダを消す。スクリプトを動かす前に、入れ替える版を `~/Library/Caches/<bundle ID>/update-pending` に書き、スクリプトは失敗の理由を `update-result` に書く（理由の文は表示の言語のものを Hanasu が引数で渡す。DEC-COM-165。元に戻すこともできなければ、前の `.app` を消さずに作業フォルダに残し、その場所も書く）。スクリプトを始める前に失敗したときはその場で知らせ、印を消す。次の起動で版が上がっていなければ、理由を出してリリースのページを案内する。
- 理由: 動いているアプリは自分を置き換えられない。同じボリュームなら移動が一瞬で終わり、途中で壊れた `.app` が残りにくい。URLSession で落としたファイルには隔離の属性が付かないので、入れ替えたあとに「開けない」確認が出ない。スクリプトの失敗は Hanasu が終わったあとに起きるので、その場では画面に出せない（macOS のアプリの保護が書き換えを止めることもある）。次の起動で知らせれば、黙って古い版のままにならない（REQ-REL-010 の「理由を出す」）。
- 決めた場面: ユーザーの依頼（2026-11-05、起動時のアップデートの確認）。失敗の理由の文を表示の言語で渡すのは PR #63（多言語化）
- 関係する要件: REQ-REL-010
- 対象: Mac
- 実装の場所: `UpdateInstaller`（`Sources/Hanasu/AppUpdate.swift`）

### DEC-REL-030 Windows の入れ替えは、隣のフォルダに展開し、PowerShell のスクリプトでフォルダごと取り替える
- 決めたこと: zip は `Hanasu.exe` のあるフォルダの隣の `Hanasu.update` に落として展開する（どのエントリーもそのフォルダの外に書かない。`Hanasu\Hanasu.exe` がなければ使わない。ダウンロードは 10 分で打ち切る）。今のフォルダの直下に、新しい `Hanasu` フォルダにないもの（`.dll`・`.pdb` のファイルと、エクスプローラーが作る `desktop.ini`・`Thumbs.db` を除く）があれば、Hanasu 専用のフォルダではないので入れ替えず、名前を挙げてリリースのページを案内する（ドライブの直下も断る）。固定の中身の PowerShell のスクリプト（パスは引数で渡す）を動かしてから Hanasu を終える。スクリプトは Hanasu の終了を待ち（60 秒まで）、今のフォルダを `<フォルダ>.old` に改名し（ファイルがまだ放されていなければ数秒やり直す）、新しいフォルダを今の名前に移す（これも数秒やり直し、失敗したら元に戻す）。`Hanasu.exe` を起動し直し、`.old` と作業フォルダを消す。経過は `%LOCALAPPDATA%\Hanasu\Logs\update.log` に書く。スクリプトを動かす前に入れ替える版を `%LOCALAPPDATA%\Hanasu\update-pending.txt` に書き、次の起動で版が上がっていなければ、ログの場所とリリースのページを案内する。フォルダに書き込めない（Program Files など）ときは、リリースのページを案内する。手元のビルド（版の先頭が 0）は入れ替えず、リリースのページを開く。
- 理由: 動いている exe と DLL は上書きできない。隣のフォルダなら同じドライブなので改名で取り替えられ、途中で壊れたフォルダが残りにくい。フォルダごと取り替えて古いものを消すので、デスクトップなど共有のフォルダに `Hanasu.exe` を置いていると、ほかのファイルまで消してしまう（PR #71 のレビュー）。Windows Defender は展開したばかりのファイルを数秒つかむので、移動はやり直す。Windows 版は署名していない（README の「初めて開くとき」）ので、確かめるのは SHA-256（DEC-REL-021）だけになる。
- 決めた場面: ユーザーの依頼（2026-11-05、起動時のアップデートの確認）
- 関係する要件: REQ-REL-010
- 対象: Windows
- 実装の場所: `UpdateService.InstallAsync`・`SwapScript`（`windows/Hanasu.Windows/Services/UpdateService.cs`）、`UpdatePackage.Extract`

---

## 廃止

やめた要件・設計判断は、消さずにここへ移す（`- 状態: 廃止（日付・理由・PR）`）。今はない。
