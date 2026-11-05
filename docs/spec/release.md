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

---

## 廃止

やめた要件・設計判断は、消さずにここへ移す（`- 状態: 廃止（日付・理由・PR）`）。今はない。
