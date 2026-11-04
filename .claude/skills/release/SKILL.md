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
4. コミットして、リリース PR のブランチに push する（`git push origin HEAD:tagpr-from-v1.3.3`）。コミットメッセージは「v1.4.0 のリリース文を書き、版を 1.4.0 にする」のように、何をしたかを書く。
5. リリース PR のタイトルが古い版のままでも、マージのときは `VERSION` の版になる。分かりやすいように `gh pr edit <番号> --title "Release for v1.4.0"` で直してよい。
6. PR の CI（`check`）が通るのを待つ。

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

- mac か windows のジョブが落ちたら、ログ（`gh run view <RUN> --log-failed`）で原因を見て、`main` に直しを入れてから、Actions の「tagpr」をタグを指定して手動で実行する（`gh workflow run tagpr.yml --ref main -f tag=v<版>`。DEC-REL-006）。下書きのまま残っているリリースに添付し直して公開する。
- リリース文を公開のあとに直したいときは、`docs/releases/v<版>.md` を直して `main` に入れ、同じ手動の実行で本文を作り直す（`gh release edit` で直接書き換えてもよいが、次の作り直しで戻る）。

## 報告

ユーザーに、版（と、その理由）、リリースの URL、添付の 2 つの大きさ、リリース文の要点、確かめていないこと（あれば）を伝える。
