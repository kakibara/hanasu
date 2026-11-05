---
name: pr-merge
description: Hanasu の PR を main にマージする手順。コンフリクトがないことだけでなく、「今の main にその PR を入れた結果」を手元で作り、Mac 版のデバッグ・リリースの両ビルド、自己テストの CLI、Windows 版のテスト、spec の検査、差分の読み合わせで不具合がないことを確かめてから、確かめたコミットだけをマージする。複数の PR は 1 つずつ、前のマージのあとの main で確かめ直す。「PR をマージして」「#50 を入れて」「開いている PR をまとめてマージして」「マージしても大丈夫か見て」などの依頼で使う。リリース PR（ラベル tagpr）は release スキルで扱う。
---

# Hanasu の PR のマージ

GitHub の「コンフリクトなし」は、テキストの上でぶつからないことしか言っていない。Hanasu では次の理由で、それだけでは足りない。

- **PR の CI の Mac 版のビルドと自己テスト（`mac.yml`）は、必須のチェックではない。** 動くのは `spec.yml`（spec の検査）、`windows/` を触ったときの `windows.yml`、`Sources/` を触ったときの `mac.yml`。`mac.yml` の結果を見ずにマージすると、Mac 版のコンパイルエラーはリリースのビルド（`tagpr.yml` の mac ジョブ）で初めて見つかる。
- **デバッグビルドで通っても、最適化ビルドで落ちることがある**（v1.4.0 で、確認用の CLI の式の型の推論が `-c release` でだけ時間切れになった。PR #39）。
- **並行して作った PR は、ぶつからずにマージできても、合わせると壊れる**（意味のコンフリクト）。たとえば片方が関数の引数を足し、もう片方がその関数を新しく呼ぶ。2026-11-04 には #43〜#49 を 25 分で続けてマージし、HUD・設定・`main.swift` を複数の PR が触っていた。
- **Mac にはテストのターゲットがない。** 振る舞いの確認は、`.build/debug/Hanasu --test-…` の自己テストの CLI と、PR に書かれた確かめ方に頼っている。
- `main` にはブランチの保護も ruleset もない（2026-11-04 時点）。必須のチェックがないので、確かめずにマージできてしまう。設定の提案は [settings.md](settings.md)。

このスキルの原則:

1. **確かめるのは「今の `origin/main` に PR を入れた結果」**。PR のブランチそのものではない。
2. **確かめたコミット（PR の head の SHA）だけをマージする**（`gh pr merge --match-head-commit`）。確かめている間に PR に push があったら、やり直す。
3. **複数の PR は 1 つずつ**。1 つマージしたら `main` が動くので、次の PR は新しい `main` に入れた結果で確かめ直す。
4. **不具合・確かめられないことが見つかったら、マージしない**で報告する。直すのは PR のブランチで（その PR を作ったセッションがあればそこへ、なければユーザーに確かめてから）。
5. **マージはユーザーの了承を取ってから。** 依頼の言葉に「マージして」「入れて」があればそれが了承。確かめた結果に「確かめていないこと」が残るときは、それを見せてから。

## 1. PR を見る

```bash
git fetch origin --prune
N=<PR の番号>
gh pr view $N --json number,title,state,headRefName,headRefOid,baseRefName,isDraft,labels,mergeable,mergeStateStatus,files \
  --jq '{number,title,state,head:.headRefName,sha:.headRefOid,base:.baseRefName,isDraft,labels:[.labels[].name],mergeable,mergeStateStatus,files:[.files[].path]}'
gh pr checks $N
```

- `state` が `OPEN` でない（ほかのセッションがもうマージした・閉じた）なら止めて伝える。並行して作業しているので、確かめている間にもマージされうる（6 の直前にもう一度見る）。
- `mergeable` が `UNKNOWN` のときは GitHub がまだ計算中。数秒おいてもう一度見る（2 の手元のマージで判断してもよい）。
- `base` が `main` でない・下書き（`isDraft`）・ラベル `tagpr`（リリース PR → release スキル）なら、ここで止めて伝える。
- `mergeable` が `CONFLICTING` なら 2 に進まず、コンフリクトのあるファイルを伝える（解き方は「失敗したとき」）。
- `gh pr checks` に失敗（`fail`）があれば、ログ（`gh run view <run> --log-failed`）を読んで原因を伝え、マージしない。走っている（`pending`）なら終わるのを待つ（`gh pr checks $N --watch` をバックグラウンドで）。
- 本文の「どう確かめたか」「実機で確かめてほしい点」「新しい要件・要件の変更」を読んでおく（5 と報告で使う）。
- `SHA=$(gh pr view $N --json headRefOid --jq .headRefOid)` を控える。以降はこの SHA を確かめる。

## 2. 「main に入れた結果」を手元で作る

確かめ用の worktree を 1 つ決めて使い回す（`.build` のキャッシュが残るので、2 回目からのビルドが速い）。ほかのセッションの作業場所は使わない。

```bash
# メインのチェックアウトの隣に作る（例: ~/gits/hanasu-merge-check）。なければ作る
CHECK="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/../hanasu-merge-check"
[ -d "$CHECK" ] || git worktree add --detach "$CHECK" origin/main
cd "$CHECK"
git merge --abort 2>/dev/null; git reset -q --hard; git clean -qfd -e .build
git checkout -q --detach origin/main
git fetch -q origin "pull/$N/head"
test "$(git rev-parse FETCH_HEAD)" = "$SHA"     # 1 で控えた SHA と同じか
git merge --no-ff --no-edit FETCH_HEAD          # 失敗したら＝コンフリクト
```

- ここはマージの結果を試すだけの場所。コミットは push しない。
- `git merge` が失敗したら、`git diff --name-only --diff-filter=U` でコンフリクトのあるファイルを控え、`git merge --abort` して「失敗したとき」へ。

## 3. 変更の範囲から、確かめることを決める

```bash
BASE=$(git merge-base origin/main FETCH_HEAD)
git diff --name-only origin/main...FETCH_HEAD > /tmp/pr-files       # PR が触ったファイル
git diff --name-only "$BASE" origin/main > /tmp/main-files           # PR の作成のあとに main で変わったファイル
comm -12 <(sort /tmp/pr-files) <(sort /tmp/main-files)               # 両方が触ったファイル（意味のコンフリクトの候補）
```

（`/tmp` の代わりにスクラッチのフォルダを使ってよい。）

| 触ったもの | 確かめること（4 の番号） |
| --- | --- |
| `Sources/`・`Package.swift`・`Package.resolved` | 4-1 Mac のデバッグビルド、4-2 リリースビルド、4-3 自己テスト |
| `Resources/`（`Info.plist`・entitlements）・`scripts/build-app.sh` | 4-2 に加えて 4-5 のアプリの組み立て |
| `windows/`・`scripts/llama-cpp.lock`・`scripts/fetch-llama-cpp.ps1` | 4-4 Windows のテスト（と PR の `windows` のチェック） |
| `docs/spec/`・タグのあるコード | 4-0 spec の検査（いつも） |
| `scripts/compose-release-notes.py`・`docs/releases/` | 4-0 の `--self-test` |
| `.github/workflows/` | ワークフローを読む（`actionlint` があれば通す）。`tagpr.yml` はリリースでしか動かないので、特に丁寧に読む |
| 文書だけ（`docs/`・`README*`） | 4-0 だけ |

迷ったら確かめる側に倒す。**両方が触ったファイルがあれば、文書だけの PR でも 4-1 から通す。**

## 4. 確かめる（2 の worktree で）

### 4-0 spec の検査（いつも）

```bash
python3 scripts/check-spec.py --summary
PR_BODY="$(gh pr view $N --json body --jq .body)" python3 scripts/check-spec.py --summary --diff origin/main
python3 scripts/compose-release-notes.py --self-test
```

### 4-1 Mac のデバッグビルド

```bash
swift build 2>&1 | tail -30
```

- 警告が PR の前より増えていないかも見る（`swift build 2>&1 | grep -c "warning:"` を `origin/main` の数と比べる。増えたら中身を読む）。

### 4-2 Mac のリリースビルド（最適化）

```bash
swift build -c release 2>&1 | tail -30      # 初回は数分。バックグラウンドで走らせてよい
```

リリースの mac ジョブ（`scripts/build-app.sh`）と同じ最適化ビルド。ここで落ちるものは、リリースまで誰も気づかない。

### 4-3 自己テストの CLI

AI もマイクも使わず、決めた例で確かめるもの。失敗があれば終了コード 1。

```bash
B=.build/debug/Hanasu
$B --test-dictionary        # 辞書の置き換えの規則（REQ-DIC-070）
$B --test-paste-target      # 入力できる場所の判定（REQ-DIC-080）
$B --test-speaker-names     # 話者の名前の推測の読み取り（REQ-MTG-027）
```

- PR が新しい `--test-…` を足していれば、それも走らせる（`grep -rhoE '"--test-[a-z-]*"' Sources/Hanasu | sort -u`）。
- マイク・キーチェーン・アクセシビリティの許可が要るもの（`--test-dictation-mic-switch`・`--claude-test`・`--probe-…`）は、PR がその場所を触ったときだけ、ユーザーに断ってから走らせる。
- PR の「どう確かめたか」に挙がっている CLI（`--render-…` で画像にするものなど）のうち、AI を呼ばないものは、マージの結果でもう一度走らせる。画像は開いて見る。

### 4-4 Windows のテスト

```bash
cd windows && dotnet test Hanasu.Core.Tests -c Release 2>&1 | tail -20; cd ..
```

- テストは `net8.0`。手元に .NET 8 のランタイムがなく新しい SDK だけのときは `DOTNET_ROLL_FORWARD=Major` を付けて走らせる（それで通らなければ、PR の `windows` のチェックの結果を使う）。
- `Hanasu.Windows`（WPF）は Mac ではビルドできない。`windows/Hanasu.Windows/` を触った PR は、**PR の `windows` のチェックが今の `main` を取り込んだ状態で通っていること**を見るPR のブランチが古いと、チェックは古い `main` との組み合わせで動いている。3 で `main` 側も `windows/` を触っていたら、PR のブランチに `origin/main` を取り込んでもらい（「失敗したとき」のコンフリクトと同じ頼み方）、CI を走らせ直してから見る。

### 4-5 アプリの組み立て（`Resources/`・`build-app.sh` を触ったとき）

```bash
./scripts/build-app.sh && codesign -dvv build/Hanasu.app 2>&1 | grep -E "Identifier|Signature"
plutil -lint Resources/Info.plist
```

- 新しく使う許可（マイク・画面収録・音声認識・Apple Events など）があれば、`Info.plist` の `NS…UsageDescription` と entitlements が足されているかを見る（ないと、配ったアプリが許可を求めた瞬間に落ちる）。

## 5. 差分を読む（ビルドとテストでは見つからない不具合）

`git diff origin/main...FETCH_HEAD` を読む。PR の差分が大きい（目安 500 行超）か、3 の「両方が触ったファイル」があるときは、見落としを減らすために別の目でも読む（`code-review` スキル、または差分と下の観点だけを渡したサブエージェント。自分の結論は渡さない）。

まず、**3 の両方が触ったファイルは、マージの結果の全体を読む**（差分だけでなく）。同じ関数・型・設定のキーを、両方が別の前提で変えていないか。

この app で起きやすい不具合の観点:

- **保存の形**: `meeting.json`・履歴・辞書などの `Codable` に足した項目が、古いファイルを読めるか（`decodeIfPresent` か既定値）。`UserDefaults` のキーの名前を変えていないか（変えたら、前の値を読み替えているか）。
- **スレッド**: UI に触る処理が `@MainActor` にあるか。録音・認識のコールバック（オーディオのスレッド）から UI や `@Published` を直接触っていないか。`Task` の中の `self` の強い参照でパネルが解放されないこと。
- **録音と後片付け**: 失敗・取り消しの道で、オーディオのタップ・`AVAudioEngine`・一時ファイル・`llama-server` のプロセスを止めているか。
- **HUD とパネル**: 前面に出ないパネル（入力先のフォーカスを奪わない）のままか。文字が長いとき・言語を変えたときに折り返し・はみ出しがないか（#42・#49 の類）。
- **秘密の扱い**: API キーをログ・例外のメッセージ・画像・`meeting.json` に出していないか（`docs/design/security.md`）。
- **Mac と Windows**: spec の「対象」が Mac / Windows の両方の要件を変えたのに、片方だけ直していないか。
- **CLI の入口**: `main.swift` の引数の分岐で、新しいフラグが前の分岐に食われていないか（`firstIndex(of:)` の順）。
- **spec**: 触ったタグのある要件を、ユーザーの合意なしに変えていないか（本文の「新しい要件・要件の変更」）。

見つけたものは「どの入力・状態で・何が起きるか」まで書く。推測のものは「推測」と書いて分ける。

## 6. マージする

4 と 5 がすべて通り、ユーザーの了承があるとき（依頼で「マージして」と言われていればそれ）だけ。

```bash
gh pr view $N --json state,headRefOid --jq '"\(.state) \(.headRefOid)"'   # まだ OPEN で $SHA か（違えば 1 からやり直す）
git fetch -q origin main && git rev-parse origin/main # 2 で使った main から動いていないか
gh pr merge $N --merge --match-head-commit "$SHA"
```

- `main` が 2 のあとに動いていたら、2 からやり直す（動いた分が PR と関係ないと言えるのは、3 の「両方が触ったファイル」がなく、動いた分が文書だけのときに限る）。
- ruleset で「ブランチが最新であること」を必須にしていて（[settings.md](settings.md) の提案 2）、PR のブランチが古いとマージは断られる。そのときは `gh pr update-branch $N` で `main` を取り込み、SHA が変わるので 1 からやり直す（2 で作ったのと同じ組み合わせなので、ビルドのキャッシュが効いて速い）。
- このリポジトリはマージコミットで入れる（`--merge`。履歴が「Merge pull request #…」でそろっている）。`--admin`・`--auto` は使わない。ブランチは消さない（ほかのセッションの worktree が使っていることがある）。

## 7. マージのあと

```bash
gh run list --branch main --limit 5            # main への push で動いた spec・windows（と tagpr）
```

- `main` の `spec`・`windows` が通るのを見る（失敗したら、すぐユーザーに伝える）。
- 続けて別の PR をマージするときは、**1 から**やり直す（2 で新しい `origin/main` に入れ直す）。
- 確かめ用の worktree は残しておいてよい（次のキャッシュになる）。片付けるときは `git worktree remove "$CHECK"`。

## 失敗したとき

- **コンフリクト**: PR のブランチで `origin/main` を取り込んで解くのが筋。その PR を作ったセッション（`claude/…` のブランチ）が生きていればそこへ頼む。いなければ、ユーザーに確かめてから PR のブランチを取り込み・解き・push し、2 からやり直す。
- **ビルド・テストの失敗、差分の不具合**: マージしない。ログの要点（ファイル・行・メッセージ）と、PR 単体では通るのか（PR のブランチで同じことをして見分ける）を伝える。PR 単体で通り、`main` と合わせると落ちるなら「意味のコンフリクト」と書く。
- **確かめられないこと**（実機・マイク・AI の応答・Windows の画面）: 不具合ではないが、報告に「確かめていない」と並べ、ユーザーの判断を待つ。

## 報告

PR ごとに、次を短く伝える。

- マージしたか（しなかったなら理由）と、マージしたコミット（`$SHA` の先頭 7 桁）
- 確かめたこと: 4 で走らせたもの（通った・落ちた）と、5 で見た観点
- 両方が触ったファイル（あれば）と、そこで見たこと
- 確かめていないこと: PR の「実機で確かめてほしい点」のうち手元で確かめられなかったもの
