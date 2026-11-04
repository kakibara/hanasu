---
name: release
description: Hanasu をリリースする手順。前の版からの変更を集めて版の上げ幅（major / minor / patch）を決め、docs/releases/TEMPLATE.md からリリース文を書き、tagpr のリリース PR の VERSION・CHANGELOG・リリース文を直してマージし、公開されたリリース（Mac 版と Windows 版の zip・本文）を確かめる。「リリースして」「v1.4.0 を出して」「次の版を出して」「リリース文を書いて」「バージョンはいくつにすべき？」などの依頼で使う。
---

# Hanasu のリリース

tagpr（`.tagpr`・`.github/workflows/tagpr.yml`）で行う。`main` に変更が入ると tagpr がリリース PR（ブランチ `tagpr-from-v<前の版>`、ラベル `tagpr`）を作り・更新し、それをマージするとタグと下書きのリリースができる。続けて Mac 版と Windows 版をビルドして zip を添付し、publish ジョブが本文を組み立てて公開する。仕組みの説明は [docs/releasing.md](../../../docs/releasing.md)、決まりは [docs/spec/release.md](../../../docs/spec/release.md)（REQ-REL-006、DEC-REL-009・010）。

このスキルの仕事は次の 5 つ。**マージ（＝公開）はユーザーの了承を取ってから**行う（依頼の言葉に「出して」「リリースして」があればそれが了承。版や中身を変えたときは、変えた結果を見せてから）。

1. 前の版からの変更を集める
2. 版の上げ幅を決める
3. リリース文を書く
4. リリース PR を直す（VERSION・CHANGELOG・リリース文）
5. マージして、公開されたリリースを確かめる

## 1. 前の版からの変更を集める

```bash
git fetch origin --tags
PREV=$(git describe --tags --abbrev=0 origin/main)          # 前の版（例: v1.3.3）
gh pr list --label tagpr --state open --json number,headRefName,title   # リリース PR
git log --merges --first-parent --format='%s' "$PREV"..origin/main      # マージした PR
python3 scripts/check-spec.py --diff "$PREV"                 # 触った要件・設計判断
git diff --stat "$PREV"..origin/main -- docs/spec docs/roadmap.md
```

- マージした PR ごとに `gh pr view <番号> --json title,body` で「概要」と「実機で確かめてほしい点」を読む。リリース PR そのもの（`tagpr` ラベル）は除く。
- 新しい要件があるかは、前の版と今の spec を比べる: `git diff "$PREV"..origin/main -- docs/spec | grep '^+### REQ-'`。「対象」に Windows や Mac が足された要件も、その OS の利用者には新しい機能になる。「## 廃止」へ移った項目も見る。
- 出ている注意（実機で確かめていない・大きなダウンロードがある・ライセンスの条件がある など）を拾っておく。

## 2. 版の上げ幅を決める（DEC-REL-009）

上から順に当てはめ、最初に当たったものにする。

| 上げ幅 | 当てはまるとき |
| --- | --- |
| **major**（2.0.0） | 今の利用者が何かしないと使い続けられない: 動作環境の引き上げ（例: macOS 26 → 27、Windows 10 をやめる）、設定・`meeting.json`・履歴などの保存の形が前の版で読めなくなる、機能の廃止（spec の「## 廃止」へ移った要件） |
| **minor**（1.4.0） | 新しい機能: 新しい要件（`REQ-…`）が増えた、要件の「対象」に OS が足された、新しい設定や選択肢（AI・モデル・エンジンなど）が増えた |
| **patch**（1.3.4） | それ以外: 不具合の修正、見た目や文言の調整、文書・CI・リリースの仕組み・内部の整理だけ |

- tagpr は何もしなければ patch にする。minor 以上なら 4 で VERSION を直す。
- 迷ったら上げ幅の大きい方にし、ユーザーに理由と一緒に見せる（例:「話者の名前の推測（REQ-MTG-027）と印の前後の会話という新しい機能があるので minor（v1.4.0）」）。
- 1.x のあいだは、major はユーザーが決める。major に当たりそうなら、理由を書いてユーザーに確かめる。

## 3. リリース文を書く（REQ-REL-006）

`docs/releases/TEMPLATE.md` を `docs/releases/v<版>.md`（例: `docs/releases/v1.4.0.md`）にコピーして書く。書き方の決まりはテンプレートの先頭のコメントにある。要点:

- 読む人は Hanasu を使う人。PR の番号・型や関数の名前・ブランチ名は書かない（PR の一覧は publish ジョブが下に付ける）。
- 1 で集めた PR を、「新しい機能」「改善」「不具合の修正」に振り分ける。リリースの仕組み・CI・文書だけの PR は書かない（使う人に関係がなければ）。
- 「ハイライト」はこの版でいちばん伝えたいことを 1〜3 文。
- 「気をつけること」に、PR の「実機で確かめてほしい点」のうちまだ確かめていない機能、初めて使うときのダウンロードの大きさ、ライセンスの条件、動作環境の変化を書く。推測で「確かめた」と書かない。
- 書くことのない見出しは消す。文は短く、1 つのリリース文の中で文体（「〜できます」か「〜できる」か）をそろえる。
- 書いたら確かめる: `python3 scripts/compose-release-notes.py --self-test`、それと組み立てた本文の見え方:

```bash
gh release view "$PREV" --json body --jq .body > /tmp/body.md   # 形の見本として前の版の本文を使う
sed -n '/^## インストール$/,$p' /tmp/body.md > /tmp/install.md
python3 scripts/compose-release-notes.py --body /tmp/body.md --install /tmp/install.md --notes docs/releases/v<版>.md
```

（`/tmp` の代わりに作業用のフォルダを使ってよい。前の版の本文には前の版の PR の一覧が入っているので、並び方だけを見る。）

## 4. リリース PR を直す

リリース PR のブランチ（`tagpr-from-v<前の版>`）に直接コミットする。tagpr は、リリース PR のブランチに足したコミットを PR を更新するときにも「できる限り」引き継ぎ、`VERSION` を手で直せばマージのときにその版を使う。

```bash
git worktree add ../release-work origin/tagpr-from-v1.3.3 -b release-work   # ほかの作業と分ける
cd ../release-work
```

1. 版を変えるとき（2 で minor 以上）:
   - `VERSION` を新しい版にする（例: `1.4.0`）。
   - `CHANGELOG.md` の先頭の見出しの版と比較のリンクを直す（`## [v1.3.4](…/compare/v1.3.3...v1.3.4)` → `## [v1.4.0](…/compare/v1.3.3...v1.4.0)`）。項目はそのまま。
2. `docs/releases/v<版>.md` を足す（3 で書いたもの）。
3. `python3 scripts/check-spec.py` を通す。
4. **リリースと同じビルドが通るかを確かめる。** PR の CI は Mac 版をビルドせず（`spec.yml` と、`windows/` を触ったときの `windows.yml` だけ）、手元の確認もデバッグビルドが多いので、リリースの最適化ビルドでだけ起きる失敗を見落としやすい（v1.4.0 で、Swift の型の推論が最適化ビルドでだけ時間切れになった）。リリース PR の中身（`origin/main` と同じコード）で:
   - Mac: `swift build -c release`（3 分ほど。リリースの mac ジョブの `scripts/build-app.sh` と同じ最適化ビルド）
   - Windows: `main` への push で動いた `windows.yml` が通っているか（`gh run list --workflow windows.yml --branch main --limit 1`）。`windows/` を触っていない版は省いてよい
5. コミットして、リリース PR のブランチに push する（`git push origin HEAD:tagpr-from-v1.3.3`）。コミットメッセージは「v1.4.0 のリリース文を書き、版を 1.4.0 にする」のように、何をしたかを書く。
6. リリース PR のタイトルが古い版のままでも、マージのときは `VERSION` の版になる。分かりやすいように `gh pr edit <番号> --title "Release for v1.4.0"` で直してよい。
7. PR の CI（`check`）が通るのを待つ。

**このあと `main` に別の PR をマージすると、tagpr がリリース PR を作り直す。** 足したコミットは引き継がれる見込みだが、マージの直前に `git show origin/tagpr-from-…:VERSION` と `docs/releases/` を見て、残っているかを確かめる。

## 5. マージして、公開されたリリースを確かめる

ユーザーに、版・理由・リリース文（本文の見え方）を見せて了承を取ってからマージする（依頼の時点で「出して」と言われていればそれでよい。版や中身を依頼から変えたときは見せてから）。

```bash
gh pr merge <リリース PR の番号> --merge
RUN=$(gh run list --workflow tagpr.yml --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch "$RUN" --exit-status       # 7〜10 分。バックグラウンドで待ってよい
gh run view "$RUN" --json jobs --jq '.jobs[] | "\(.name) \(.conclusion)"'
gh release view v<版> --json isDraft,assets,body --jq '{isDraft, assets:[.assets[] | "\(.name) \(.size)"]}'
gh release view v<版> --json body --jq .body | head -40
```

確かめること:

- 4 つのジョブ（tagpr・mac・windows・publish）がすべて success。
- 下書きでない（`isDraft: false`）、Latest になっている（`gh release list --limit 2`）。
- 添付が `Hanasu-<版>-macOS.zip` と `Hanasu-<版>-Windows-x64.zip` の 2 つで、大きさが前の版から大きく外れていない（llama.cpp の同梱で Mac 版は約 18 MB、Windows 版は約 100 MB）。
- 本文が、リリース文 → PR の一覧 → インストールと SHA-256 の順。

### 失敗したとき

まずログ（`gh run view <RUN> --log-failed`）で原因を見る。**手動の実行（DEC-REL-006）は、ワークフローは `main` のものを使うが、ビルドするコードとリリース文はタグの時点のもの**なので、原因がどこにあるかで直し方が変わる。

- **一時的な失敗**（ランナー・ネットワーク・GitHub の不調）や、**ワークフローの側の問題**（`main` のワークフローを直せば済む）なら、Actions の「tagpr」をタグを指定して手動で実行する。下書きのまま残っているリリースに添付し直して公開する。

  ```bash
  gh workflow run tagpr.yml --ref main -f tag=v<版>
  ```

- **タグの時点のコードが原因**（コンパイルエラー・テストの失敗など）なら、手動の実行では直らない（同じコードをビルドするだけ）。ユーザーに確かめてから、**公開前の下書きなら**タグを付け直す（v1.4.0 でこうした）:

  ```bash
  # 1. 直しを PR にして main に入れる（Spec-Impact を書く）。Mac は swift build -c release で確かめる
  # 2. 下書きのリリースとタグを消す（公開前の下書きだけ。公開済みの版には使わない）
  gh release delete v<版> --yes --cleanup-tag
  # 3. 直しの入った main のコミットにタグを付けて push する（下書きのリリースは、公開するまでタグを作らないので、タグを先に）
  git fetch origin --tags
  git tag -a v<版> <直しの入った main のコミット> -m "v<版>"
  git push origin v<版>
  # 4. 下書きのリリースを作る（PR の一覧は前の版から作り直す）
  gh release create v<版> --draft --verify-tag --title v<版> --generate-notes --notes-start-tag <前の版>
  # 5. 手動の実行で、両方の zip を添付して公開する
  gh workflow run tagpr.yml --ref main -f tag=v<版>
  ```

  `main` に直しを入れると、tagpr は古いタグをもとに次の版のリリース PR（例: v<版>.1、中身は直しの PR だけ）を作る。直しはもう付け直した版に入っているので、**このリリース PR はマージしない**（次に `main` に変更が入ると、tagpr が付け直したタグのあとの変更で作り直す）。

- **公開済みの版**は消さない。直しを入れて、次の patch として出す。

### 公開のあとにリリース文を直すとき

publish ジョブはタグの時点の `docs/releases/v<版>.md` を読むので、`main` のファイルを直して手動で実行しても本文は変わらない（タグの時点の文で作り直される）。誤字などは `gh release edit v<版> --notes-file <直した本文>` で直接直し、記録のために `docs/releases/v<版>.md` も `main` で直しておく。そのあとはその版の手動の実行をしない（タグの時点の文に戻る）。

## 報告

ユーザーに、版（と、その理由）、リリースの URL、添付の 2 つの大きさ、リリース文の要点、確かめていないこと（あれば）を伝える。
