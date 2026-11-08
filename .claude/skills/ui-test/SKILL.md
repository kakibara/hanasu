---
name: ui-test
description: Hanasu の画面を見て確かめる UI のテスト（common/testdata/ui/*.json の UX-…）を Mac で自動で行う手順。swift build のあと scripts/ui-cases.py render で「render」の項目の画面を PNG に描き、PNG を 1 枚ずつ読んで見る観点（look）を満たすかを OK / NG / 判断できない で判定し、日付つきの結果を docs/verification/ui-runs.md に残す。「UI のテストをして」「画面を確かめて」「UX-010 を確かめて」「P1 の UI のテストを流して」「英語の画面が崩れていないか見て」「リリースの前に画面を見て」などのとき、また画面に関わる変更のあとで見た目を確かめるときに使う。UI のテスト項目を足す・直すときも、このスキルの「項目を足す・直す」を読む。
---

# UI のテスト（画面を描いて確かめる）

決まりは [docs/spec/common.md](../../../docs/spec/common.md) の DEC-COM-170。項目は `common/testdata/ui/<節>.json`、一覧（生成したもの）は [docs/verification/ui-ux-test-cases.md](../../../docs/verification/ui-ux-test-cases.md)、結果は [docs/verification/ui-runs.md](../../../docs/verification/ui-runs.md)。

項目の Mac の確かめ方（`automation.mac.kind`）は 3 つ。

| kind | 意味 | このスキルで |
| --- | --- | --- |
| `render` | アプリの `--render-*` で決まった状態の画面を PNG に描き、`look` と照らす | 描いて判定する |
| `drive` | 本物のアプリを起動して操作する（自動の仕組みは FUT-018） | 判定しない。「操作の項目」として残りに挙げる |
| `manual` | 人が確かめる（`reason` に理由） | 判定しない。残りに挙げる |

## 1. 描く

```bash
swift build
python3 scripts/ui-cases.py render --priority P1            # 優先度で選ぶ（P1,P2 も可）
python3 scripts/ui-cases.py render --ids UX-016,UX-030      # ID で選ぶ
python3 scripts/ui-cases.py render --ids UX-098 --lang all  # 17 言語で描く（--lang を省くと項目の languages か ja）
```

- 出力は `.build/ui-cases/<日時>/<言語>/<ID>/*.png` と、同じフォルダの `manifest.json`（ID・言語・PNG・`look`・`expected`・`remaining`・描けたか）。最後の行に manifest のパスが出る。
- 依頼が範囲を言わないときは `--priority P1`。画面に関わる変更のあとなら、その画面の項目（`python3 scripts/ui-cases.py list --kind render` で探す）を選ぶ。
- 描けなかった項目（`rendered: false`）は、`errors` を読んで原因を報告する。判定はしない。
- 描画の CLI は、画面を出さずに描く（ウインドウを画面の外に置く）。マイク・ネットワークは使わない。ただし設定の画面などは、この Mac の本物の設定の値で描かれる。PNG に API キーやメールアドレスが見えていたら、報告や記録にその値を書かない。

## 2. 判定する

manifest の `entries` を 1 件ずつ、PNG をすべて Read で開いて判定する。

- 見るのは `look`（PNG で見る観点）。`expected` は項目全体の期待で、そのうち描画で見られる部分が `look`。`remaining` は描画では見られない部分なので、判定に含めない。
- 判定は 3 つ。
  - **OK**: `look` に書いたことが PNG で確かめられた。
  - **NG**: `look` に反する（文言がない・切れている・重なっている・ボタンがない・読めない色など）。どの PNG のどこかを書く。
  - **判断できない**: PNG だけでは分からない（この Mac の状態で表示が変わる、描画が途中など）。理由を書く。
- `look` 以外でも、明らかな崩れ（文字の切れ・重なり・はみ出し・日本語以外の言語なのに日本語が残っている・空白の画面）に気づいたら「気づいたこと」として書く。項目の判定は変えない。
- 描き方の限界（2026-11-08 に分かったもの）。次のことで look に反して見えるときは、NG ではなく「判断できない」にし、理由に「描き方の限界」と書く。
  - 設定のウインドウ（`--render-settings`）と会議ノートのウインドウ（`window-tab*.png`）の左のサイドバーは、中身のない白い板と黒いグラデーションになる。設定の `--dark` は、ウインドウの背景が描かれず白い地に白い文字になって読めない。
  - 画面の外の前面でないウインドウで描くので、強調の色（オンのトグルの色、`borderedProminent` のボタンの色、「★ ここ重要」の黄色）が灰色になる。
  - `--render-ai-settings` は AI の欄の途中（Claude の API キー）から描かれ、上の「使う AI とモデル」「整形の言語」が写らない。そこを見る項目は `--render-settings {out} --pane ai` で描く。
  - 描画の CLI が決めた幅（会議の記録中の画面は 640 など）で描くので、右端のボタンの文字が切れることがある。本物のウインドウの最小の幅でも切れるかは、実機で確かめる。
- 枚数が多いとき（`--lang all` など）は、言語ごと・項目ごとに分けてエージェントに判定を任せてよい。そのときは manifest のパスと、この節の判定の決まりを渡し、結果だけを受け取る。

## 3. 記録する

[docs/verification/ui-runs.md](../../../docs/verification/ui-runs.md) の末尾に、日付の付いた節を足す。過去の節は書き換えない。

```markdown
## <番号>. <YYYY-MM-DD> <範囲>（<コミット>、macOS <版>）

- 描いたもの: `python3 scripts/ui-cases.py render …`（<件数> 件、言語: …）
- 判定: OK <n>・NG <n>・判断できない <n>・描けなかった <n>

| ID | 言語 | 判定 | メモ |
| --- | --- | --- | --- |
| UX-016 | ja | OK | |
| UX-030 | en | NG | translate.png で「English」のボタンの文字が切れている |

- 気づいたこと: …
- 判定していないもの: drive <n> 件・manual <n> 件（範囲の中の項目の ID）
```

- コミットは manifest の `commit`、macOS の版は `sw_vers -productVersion`。
- PNG は `.build/` にあり、コミットしない。NG の PNG は、報告のときにパスを示す（ユーザーに見せるなら SendUserFile で送る）。
- NG を直すのは別の作業。直す依頼がなければ、報告にとどめる。直したら、同じ項目を描き直して新しい節を足す。

## 4. 報告する

判定の数、NG の項目と PNG のパス、描けなかった項目、判定していない（drive・manual の）項目の数を短く伝える。

## 項目を足す・直す

1. `common/testdata/ui/<節>.json` の `cases` に足す（ID は最後の番号の続き。使い回さない）。形は DEC-COM-170 と既存の項目に合わせる。
   - `refs` は spec の ID を 1 つずつ（範囲は使わない）。
   - Mac で描けるなら `render`。`renders` は引数の並びの並びで、出力は `{out}`（項目のフォルダ）を使う（`{out}/hud.png` か、フォルダを取る CLI なら `{out}`）。決まったデータが要るなら `common/testdata/ui/fixtures/` に置いて、リポジトリの根からの相対パスで渡す（例: `--meeting-json common/testdata/ui/fixtures/speaker-names.meeting.json`）。
   - 描く CLI がない画面は、既存の描画の関数に状態を渡すだけで描けるなら `--render-*` を足す（`Sources/Hanasu/*CLI.swift`）。そうでなければ `drive` か `manual`。
   - Windows の欄は、今はすべて `manual`（FUT-019）。
2. `python3 scripts/ui-cases.py md` で一覧を作り直す。
3. `python3 scripts/ui-cases.py check` をエラーなしで通す（CI の `spec.yml` も動かす）。spec で「確かめ方」に「実機」とある要件に項目がないと警告が出るので、要件を足したら項目も足す。
