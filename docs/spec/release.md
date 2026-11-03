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
- 実装の場所: `.github/workflows/tagpr.yml`（`publish` ジョブ）

### DEC-REL-006 既存のタグの添付ファイルを、手動の実行で作り直せる
- 決めたこと: Actions の「tagpr」をタグを指定して手動で実行すると、tagpr を飛ばして両方の zip を作り直す。
- 理由: ビルドや添付に失敗したときに、タグを打ち直さずにやり直せるようにする。
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

---

## 廃止

やめた要件・設計判断は、消さずにここへ移す（`- 状態: 廃止（日付・理由・PR）`）。今はない。
