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

### REQ-REL-005 PolyForm Noncommercial と追加の許可で配布し、大きい会社には商用ライセンスを求める。配布物にライセンスと第三者の表示を入れる
- 内容: Hanasu は PolyForm Noncommercial License 1.0.0 と「Hanasu 追加の許可 1.0」で配布する（ソース公開。オープンソースではない）。個人の非商用の利用と小規模事業者の社内の業務は無料で、それより大きい会社の業務での利用と、規模にかかわらず Hanasu を売る・製品やサービスに組み込む・ホスティングで提供することには、商用ライセンスが必要になる。このライセンスに変える前の版は Apache License 2.0（2026-11-03 までは AGPL-3.0）で、その版は Apache License 2.0 のまま。Mac 版・Windows 版の配布物には、Hanasu のライセンス（`LICENSE`・`LICENSE-ADDITIONAL-PERMISSION.md`・`NOTICE`）と、組み込んだ第三者のソフトウェアのライセンス表示を入れる。
- 受け入れ条件: リポジトリの `LICENSE` が PolyForm Noncommercial License 1.0.0 の条文で、`LICENSE-ADDITIONAL-PERMISSION.md`・`COMMERCIAL.md`・`COMMERCIAL.ja.md`・`CONTRIBUTING.md` がある。`Hanasu.app/Contents/Resources` に `LICENSE`・`LICENSE-ADDITIONAL-PERMISSION.md`・`NOTICE`・`THIRD_PARTY_NOTICES.md` がある。Windows 版の zip の `Hanasu` フォルダに `LICENSE.txt`・`LICENSE-ADDITIONAL-PERMISSION.md`・`NOTICE.txt`・`THIRD_PARTY_NOTICES.md`・`dotnet-THIRD-PARTY-NOTICES.txt` がある。
- 出典: ユーザーの依頼（2026-11-03「Apache-2.0 にして、Windows のライセンスの問題も修正して」）。v1.3.0 の Windows 版の zip にライセンスの表示が入っていなかったことへの対応。ユーザーの依頼（2026-11-04「大企業などに無制限にこのオープンソースのプロジェクトに乗っ取られることを防ぐべきです。安定度以上の企業が商用利用する場合は契約が必要である、という形で進めたい」）と、そのヒアリングでの合意（看板は手放してよい・線は会社の規模・組み込んで売るなら小さい会社も契約・期限付きの開放はしない）、2026-11-05「ライセンスを書き換え」
- 対象: Mac / Windows
- 実装の場所: `LICENSE`、`LICENSE-ADDITIONAL-PERMISSION.md`、`COMMERCIAL.md`、`COMMERCIAL.ja.md`、`CONTRIBUTING.md`、`NOTICE`、`THIRD_PARTY_NOTICES.md`、`windows/THIRD_PARTY_NOTICES.md`、`scripts/build-app.sh`、`windows/Hanasu.Windows/Hanasu.Windows.csproj`、`.github/workflows/windows.yml`（publish の中身の確認）
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
- 確かめ方: `Hanasu --check-update`、`Hanasu --update-selftest`、`cd windows && dotnet test Hanasu.Core.Tests`。Mac のダイアログの見た目は `Hanasu --preview-update-dialog [<リリース文の .md>]` で出せる。ダイアログは実機で確かめる

### REQ-REL-012 アップデートのダウンロード中は、進み具合をバーと大きさで見せ、途中でやめられる
- 内容: 「アップデート」を選んで新しい版の zip をダウンロードしている間、進み具合のバーと「割合・落とした大きさ / 全体の大きさ」を 1 つの窓に出し、進むにつれて更新する。窓の「中止」で、ダウンロードをやめられる。ダウンロードが終わって確かめ・展開をしている間は、そのことを出す。
- 受け入れ条件:
  - ダウンロード中は、0 から 100% へ進むバーと「<割合>%（<落とした大きさ> / <全体の大きさ>）」が出る。落とした量が増えていれば、少なくとも 1 秒に 1 回は新しい値になる。全体の大きさはリリースの API が返す zip の大きさ（`size`）。割合は整数で、100% を超えない。
  - 大きさは KB / MB / GB の 1000 区切り。Mac は `ByteCountFormatter` の `.file`（例「12.3 MB / 27.1 MB」）、Windows は `MeetingAudioCleanup.FormatSize`（10 MB 以上は整数。例「12 MB / 27 MB」）。
  - ダウンロードが終わったら（Mac は SHA-256 の計算の前から）、確かめ・展開の間はバーを不定（動き続ける形）にして、そのことを出す（Mac は「ダウンロードしたファイルを確かめています…」、Windows は「ダウンロードした zip を展開しています。」）。
  - 「中止」はダウンロード中だけ押せる（確かめ・展開の間は押せない）。押すとダウンロードをやめ、作業フォルダを消し、窓を閉じ、入れ替えない。エラーのダイアログは出さない。あとでメニューの「アップデートを確認…」から選び直せる。
  - 窓は、どの終わり方（入れ替えに進む・失敗・中止・録音中で入れ替えない・Windows の「Hanasu のものでないファイルがある」）でも閉じる。案内やエラーのダイアログは、窓を閉じてから出す。
  - Windows は、ダウンロードと展開の通知の吹き出しを出さず、この窓に置き換える。
- 出典: ユーザーの依頼（2026-11-11「更新のダウンロードをバーでダウンロード進捗を表現して。容量も」。対象は Mac と Windows の両方、「中止」を付ける（同日の答え）。計画の了承は同日）
- 対象: Mac / Windows
- 実装の場所: Mac は `UpdateHTTP.download`・`UpdateDownloadDelegate`、`AppUpdater.install`・`UpdateProgressModel`・`UpdateProgressView`（`Sources/Hanasu/AppUpdate.swift`）。Windows は `UpdateService.InstallAsync`、`UpdateProgressWindow`（`windows/Hanasu.Windows/Views/UpdateProgressWindow.cs`）、`UpdateDownloadProgress`（`windows/Hanasu.Core/Update/UpdateDownloadProgress.cs`）
- 確かめ方: Mac は `Hanasu --update-selftest`（割合・文・間引き）、`Hanasu --render-update-progress <出力.png> [--fraction 0.42 | --verifying]`（窓の見た目。UX-186）、`Hanasu --download-update [--cancel-after <秒>]`（GitHub から最新の zip を実際に落とし、進み具合を行で出し、大きさと SHA-256 を確かめて消す。入れ替えない。`--cancel-after` で中止して止まるかを見る）。Windows は `cd windows && dotnet test Hanasu.Core.Tests`（`UpdateTests`）。窓が進む・中止で止まるのは実機で確かめる（UX-186）

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

### DEC-REL-011 商用ライセンスの線引きは「100 人未満かつ売上 100 万米ドル未満」で、評価 30 日・猶予 90 日を付け、強制の仕組みは入れない
- 決めたこと: 土台は標準の PolyForm Noncommercial License 1.0.0 で、条文は変えない。小規模事業者の社内の業務・評価・猶予は、許可を足すだけの別の文書（`LICENSE-ADDITIONAL-PERMISSION.md`。英語が正文、日本語は参考訳）に書く。小規模事業者は、グループを合わせて 100 人未満（従業員と業務委託）かつ前の事業年度の売上 100 万米ドル未満で、個人事業主を含む。小規模事業者でも、売る・製品やサービスに組み込む・ホスティングで提供するのは許可に含めない。どの会社も、会社全体で 30 日は評価のために業務で使える。小規模事業者でなくなったら、その事業年度の終わりから 90 日は使い続けられる。商用ライセンスは実際に使う人の数で数える年額で、価格は当面「問い合わせ」。アプリにライセンスの確認や利用の監視は入れない。外部からのコードの貢献には `CONTRIBUTING.md` の貢献者ライセンス契約（CLA）への同意を求め、PR のテンプレートに同意のチェックを置く。
- 理由: 標準の条文に制限を足すと、その名前のライセンスとは呼べず解釈もぶれるので、許可を足す形にした（BSL の Additional Use Grant と同じ考え方）。PolyForm Small Business そのままでは、小さい会社が組み込んで売るのを止められない。線は PolyForm Small Business と同じ数字にし、企業の法務が読み慣れた形にした。評価と猶予は、大きい会社の社員が試し始められるようにし（個人から会社へ広がる流れ）、線を越えた会社が契約の手続きをする時間を取るため（Docker Desktop の有料化の猶予）。会社の人数全体での課金と監査は利用者を逃がす（Oracle Java）ので、実際に使う人数で数え、強制はしない（秀丸エディタ・Yaak は名誉の仕組みで会社に売れている）。CLA がないと、貢献されたコードを商用ライセンスで売れない。利用者が増えてからライセンスを変えるとフォークされる（HashiCorp・Redis）ので、フォークがない今のうちに変えた。
- 決めた場面: ユーザーの依頼（2026-11-04「大企業などに無制限にこのオープンソースのプロジェクトに乗っ取られることを防ぐべきです」）のヒアリング、2026-11-05 のヒアリング（窓口は Google フォーム・価格はまだ載せない・評価 30 日と猶予 90 日・CLA に同意してもらう）と「ライセンスを書き換え」
- 関係する要件: REQ-REL-005
- 対象: Mac / Windows
- 実装の場所: `LICENSE-ADDITIONAL-PERMISSION.md`、`COMMERCIAL.md`、`COMMERCIAL.ja.md`、`CONTRIBUTING.md`、`.github/pull_request_template.md`

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
- 実装の場所: Mac は `UpdateHTTP`（`isAllowed`・`download`・`verify`）、`UpdateDownloadDelegate`（転送の制限と大きさの上限）。Windows は `UpdateHosts`、`UpdateChecker.DownloadAsync`、`ModelDownload.DownloadVerifiedAsync`

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

### DEC-REL-027 リリース文はアプリの機能と自分の OS の話に絞り、見出し・箇条書きを整えて先頭から出す。Mac ではダイアログを Task の外から出す
- 決めたこと: 新しい版を尋ねるダイアログに出すリリース文は、アプリの機能の話だけに絞る。出す節は「## ハイライト」「## 新しい機能」「## 改善」「## 不具合の修正」だけで、ほかの節（「気をつけること」「アップデートのしかた」など）は出さない（最初の「## 」の見出しより前の文は出す。この 4 つの見出しがどれもなければ、絞らずに全部出す）。行の終わりの OS の印（「（Mac）」「（Windows）」「（Mac / Windows）」。半角の括弧も。あとの「。」は除いて見る）がその OS を含まない行は出さず、その行の下の一段深い行も出さない。出す行の OS の印は外す（「。」は残す）。絞って中身がなくなった節は、見出しも出さない。全文は、リリースのページを開いて読めるようにする（Mac は欄の終わりの「リリースのページで全文を見る」のリンク、Windows は「リリースのページを開く」のボタン）。そのうえで、Markdown の記号をそのまま出さず、見出しは太い大きめの字、箇条書き（番号付きも）は印のあとを字下げして折り返し、太字・斜体・コード・リンクは字の形にして出す（Mac・Windows とも `ReleaseNotesFormatter`。HTML のコメントは出さない。入れ子の箇条書きは一段ずつ深く字下げする）。リンクは http / https のものだけ押して開ける（ほかは字だけ出す）。字数では切らず、長ければ欄の中でスクロールする。欄の字は選んでコピーできる。欄は開いたときに先頭が見える位置にする。Mac では、アップデートのダイアログ（尋ねる・最新です・失敗した、など）は、Swift の Task の中で `runModal` を呼ばず、`RunLoop.main.perform` で Task の外から出して、結果を待つ。出している間も画面は動くので、起動時の確認のダイアログと重ならないよう、知らせのダイアログを出す間も「尋ねている」扱いにし、起動時の確認は、その知らせが閉じるまで待ってから尋ねる（メニューから同じ版を尋ねていれば、もう尋ねない）。
- 理由: GitHub のリリース文には、作る側の確認の状況（「実機でまだ確かめていない」）や、手で入れ替える人向けの手順（ダイアログには出ない「下のインストールの手順」を指す）、もう一方の OS だけの話も入り、アプリの中で読むと関係のないものが混じる（ユーザーの指摘、2026-11-08「アプリの機能のみに絞った方がいい」）。リリース文の書き方（docs/releases/TEMPLATE.md）は、節の名前と、項目の終わりの（Mac）（Windows）が決まっているので、それで絞れる。記号のままでは読みにくい（ユーザーの指摘）。リリース文は docs/releases/TEMPLATE.md の形（見出しと箇条書き）で書くので、それだけ整えれば足りる。Task の中で `runModal` を呼ぶと、出している間メインのディスパッチキューが回らず（手元の実験で、1.5 秒の間に 0 回。Task の外からなら 31 回）、スクロールが重くなり、ほかの画面の更新も止まる。並べ終えた欄は終わりが見えた状態になり、リリース文の頭（ハイライト）が見えなかった。Windows では 800 字で切っていたので、長いリリース文の後ろが読めなかった。前の Windows の欄（TextBox）は字を選べたので、整えたあとも選べるようにする（PR #80 のレビュー）。リリース文は GitHub から来るので、押して開くリンクは Web のページに限る。ダイアログを出している間も起動時の確認が進むので、待たずにやめると、メニューで「確かめています」を見ている間に届いた新しい版を、この起動では知らせなくなる（PR #79 のレビュー）。
- 決めた場面: ユーザーの依頼（2026-11-07「スクロールが重いのと markdown をそのまま表示しているので読みにくいです」）。機能の 4 節と自分の OS の項目に絞るのは、ユーザーの依頼（2026-11-08、PR #79 で「機能の 4 節＋自分の OS だけ」を選んだ）。Windows は同じ指摘を受けて合わせた
- 関係する要件: REQ-REL-010, REQ-REL-011
- 対象: Mac / Windows
- 実装の場所: Mac は `AppUpdater.presentAsk`・`AppUpdater.runModal`、`UpdateRelease.appNotes`・`ReleaseNotesFormatter`（`Sources/Hanasu/AppUpdate.swift`）。確かめるのは `Hanasu --preview-update-dialog [<リリース文の .md>]` と `Hanasu --update-selftest`。Windows は `ReleaseNotesFormatter.ForApp`・`ReleaseNotesFormatter.Parse`（`windows/Hanasu.Core/Update/ReleaseNotesFormatter.cs`。テストは `ReleaseNotesFormatterTests`。絞り込みは Mac の selfTest と同じ見本で確かめる）と `UpdatePromptWindow.ReleaseNotesDocument`

### DEC-REL-028 進み具合はモデルのダウンロードと同じ形の 1 つの窓に出し、更新は 0.1 秒ごとに間引く。中止はダウンロード中だけ
- 決めたこと:
  - 見せ方はローカルのモデルのダウンロード（`LocalModelDownloadPrompt`）と同じにする: 見出し「Hanasu <版> をダウンロードしています…」、確定のバー、小さな字の「<割合>%（<落とした大きさ> / <全体>）」（数字は等幅）、右下に「中止」。
  - 全体は API の `asset.size` を使う（`Content-Length` は見ない）。割合は `min(1, 落とした量 / size)` を切り捨てた整数の %。
  - 間引き: 前に出してから 0.1 秒以上たち、かつ落とした量が変わっていれば出す。落とした量が size に達したときは必ず出す。判定は純粋な関数（Mac は `UpdateProgressModel.shouldPublish`、Windows は `UpdateDownloadProgress.ShouldPublish`）にしてテストする。
  - 割合の文: Mac はモデルのダウンロードと同じ `tr("%@%%（%@ / %@）", …)`。Windows は `Update_Progress`（`{0}% ({1} / {2})`、{0} は整数）。`P0` の書式は言語によって「45 %」「%45」となり Mac の訳とそろわないので使わない。
  - 確かめ・展開の間はバーを不定にし、「中止」を押せなくする。Mac は SHA-256 の計算を `UpdateHTTP.download` の外（`UpdateHTTP.verify`）に出し、落とし終えた時点で切り替える。
  - 中止: Mac はダウンロードの `Task` をキャンセルし、`UpdateDownloadDelegate` の `URLSession` を `invalidateAndCancel` する。キャンセルはダイアログを出さずに作業フォルダを消して戻る。Windows は 10 分の打ち切り（DEC-REL-030）のトークンとつないだ `CancellationTokenSource` を「中止」で取り消し、中止による `OperationCanceledException` はダイアログを出さずに作業フォルダを消して戻る（10 分の打ち切りは今のまま `Update_DownloadTimeout`）。
  - 窓: Mac は今の `.titled`・`.floating` のまま（閉じるボタンなし。やめるのは「中止」）。Windows は `Topmost` にせず、最小化でき、閉じる操作（閉じるボタン・Alt+F4）はダウンロード中なら「中止」と同じにし、確かめ・展開の間は取り消す。どちらも必ず閉じ（Mac は `defer`、Windows は `try/finally`）、ダイアログはそのあとに出す。
  - Mac の通信: `UpdateHTTP.download` は、`URLSessionDownloadDelegate` を持つ 1 回きりの `URLSession`（`UpdateDownloadDelegate`）で行う（`LocalLLMStore.DownloadDelegate` と同じ作り）。設定は `UpdateHTTP.session` と同じ（ephemeral・Cookie と認証の保存なし・TLS 1.2 以上・`timeoutIntervalForRequest` 60 秒）。転送は `UpdateHTTP.isAllowed` のホストへだけ従い、落とした量が `asset.size` を超えたら止める。Mac には全体の時間の上限を設けない（「中止」で止められるため）。
- 理由: ユーザーがすでに見ているモデルのダウンロードと同じ見た目・操作にすれば迷わない。Mac は既存の文字列を使える。`asset.size` は確かめ（DEC-REL-021）にも使っている確かな値で、転送先の CDN が `Content-Length` を返さなくても出せる。async の `session.download(for:)` は進み具合を返さないので delegate の作りにする。0.1 秒の間引きなら、速い回線でも UI のスレッドに何百回も投げず、遅い回線でも 1 秒に何度も更新される（「割合が 1% 変わったら」では、遅い回線で数秒止まって見える。計画のレビュー）。確かめ・展開は数秒で終わり、途中でやめると後始末が複雑になるので、中止はダウンロード中だけ。Mac には全体の時間の上限がなく、進み具合が見えると「遅いからやめたい」場面が増えるので「中止」を付ける（モデルのダウンロードの窓にもある）。Windows は今、吹き出しで作業を邪魔しない作りなので、前面に固定せず最小化できるようにする。Windows の展開のあとには、例外を通らずに戻る道（Hanasu のものでないファイルがある）があるので、閉じるのは `finally` にする（計画のレビュー）。
- 決めた場面: ユーザーの依頼（2026-11-11「更新のダウンロードをバーでダウンロード進捗を表現して。容量も」）と、同日の答え（Mac と Windows の両方・「中止」を付ける）
- 関係する要件: REQ-REL-012, REQ-REL-010
- 対象: Mac / Windows
- 実装の場所: Mac は `UpdateDownloadDelegate`、`UpdateHTTP.download`・`UpdateHTTP.verify`、`UpdateProgressModel`・`UpdateProgressView`、`AppUpdater.install`・`AppUpdater.showProgress`（`Sources/Hanasu/AppUpdate.swift`）。Windows は `UpdateDownloadProgress`（`windows/Hanasu.Core/Update/UpdateDownloadProgress.cs`）、`UpdateProgressWindow`（`windows/Hanasu.Windows/Views/UpdateProgressWindow.cs`）、`UpdateService.InstallAsync`

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
