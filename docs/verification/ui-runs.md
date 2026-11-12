# UI のテストの実施の記録

画面を見て確かめる UI のテスト（[ui-ux-test-cases.md](ui-ux-test-cases.md)、元は `common/testdata/ui/*.json`）を行った結果。手順は `.claude/skills/ui-test/SKILL.md`、決まりは DEC-COM-170。

- ここに書いた結果は、その日の版での結果。あとで実装が変わっても書き換えず、新しい結果は日付を付けて足す。
- 描画（render）の項目は、`python3 scripts/ui-cases.py render` で描いた PNG を見て判定する。人が確かめた項目（操作・手）も、ここに同じ形で書く。

---

## 1. 2026-11-08 Mac の描画の項目すべて（6bc778b の上の作業中の変更、macOS 26.6.2）

UI のテスト項目をデータにした変更（DEC-COM-170）で、仕組みを通して確かめたときの結果。

- 描いたもの: `python3 scripts/ui-cases.py render --ids <描画の項目のうち UX-098 以外の 37 件>`（ja）、`python3 scripts/ui-cases.py render --ids UX-098 --lang en`。描画の CLI で描けなかった項目はない。
- 判定のあとで、この Mac の状態で表示が変わる項目（UX-070・075・122・128）と、描き方の限界で判定できなかった項目（UX-092 の設定のダーク）の見る観点を直し、UX-077 を設定の一般から文字起こしの欄の描画に替えて描き直した（下の表はその結果）。
- 判定: OK 34・NG 2・判断できない 2・描けなかった 0

| ID | 言語 | 判定 | メモ |
| --- | --- | --- | --- |
| UX-001 | ja | OK | 7 ページすべて描けた |
| UX-002 | ja | OK | Gemma 4 E4B に「おすすめ」。選ぶまで「次へ」が無効 |
| UX-003 | ja | OK | 各行に何に要るかと、設定の「権限」で許可し直せることがある |
| UX-010 | ja | OK | |
| UX-016 | ja | OK | |
| UX-019 | ja | OK | |
| UX-135 | ja | OK | |
| UX-030 | ja | OK | |
| UX-031 | ja | OK | |
| UX-032 | ja | OK | |
| UX-033 | ja | OK | |
| UX-034 | ja | OK | |
| UX-041 | ja | OK | |
| UX-048 | ja | OK | |
| UX-051 | ja | OK | |
| UX-052 | ja | OK | |
| UX-053 | ja | 判断できない | live.png・live-undo.png の右上の「★ ここ重要」が「★ こ」で切れている。描画の幅 640 による可能性（描き方の限界）。本物のウインドウの最小の幅で切れるかは実機で確かめる |
| UX-054 | ja | OK | |
| UX-057 | ja | OK | |
| UX-058 | ja | OK | |
| UX-062 | ja | OK | |
| UX-111 | ja | OK | 長い話者名が「山田 太郎太…」と省略。長いエラーは崩れない |
| UX-136 | ja | OK | |
| UX-139 | ja | OK | 推測した「田中」が出る。名前のない話者は「話者2」 |
| UX-141 | ja | OK | 答えの時刻は角かっこなしの青いリンク（例: 10:12） |
| UX-070 | ja | OK | キーは未設定の表示。キー全体は見えていない |
| UX-075 | ja | OK | この Mac は Whisper のモデルがダウンロード済みなので「削除…」のボタン |
| UX-076 | ja | OK | |
| UX-077 | ja | OK | 文字起こしの節に「言語」の欄 |
| UX-078 | ja | NG | presence.png に 3 つの選択肢はあるが、変えたときにすぐ反映されるのか再起動が要るのかが書いていない |
| UX-079 | ja | OK | この Mac に拒否した権限はない |
| UX-122 | ja | OK | |
| UX-128 | ja | OK | この Mac はアクセシビリティを許可済みなので、未許可の案内は出ていない |
| UX-129 | ja | OK | |
| UX-143 | ja | OK | 「macOS 27 以降で使えます（この Mac は macOS 26.6）」 |
| UX-092 | ja | OK | 履歴（ライト・ダーク）と会議の記録中の画面（ダーク）。選んでいない履歴の行の本文はやや薄い |
| UX-131 | ja | 判断できない | 「★ ここ重要」のボタンが黄色でなく暗い灰色に黒い星。前面でないウインドウで強調の色が付かない描き方の限界による可能性 |
| UX-098 | en | NG | settings-appStyles.png（Per App）の出力言語のポップアップが、すべての行で「Spoken Lang…」と切れる。UI の文言に日本語は残っていない |

- 気づいたこと:
  - 描き方の限界: 設定と会議ノートのウインドウの左のサイドバーが白い板になる。設定の `--dark` は白い地に白い文字で読めない。強調の色（オンのトグル・目立たせるボタン）が灰色になる。ui-test のスキルに書いた。
  - 会議ノートの詳細を単独で描いた PNG（detail*.png）は左右の端が切れる（同じ内容の window-tab*.png では切れない）。描画の枠の大きさの問題とみられる。
  - 履歴の失敗の詳細に、API が返した英語のエラー（「The model is overloaded…」）がそのまま出る。英語の画面でも、仮のデータの日本語のエラー文が写る（DictationHistoryCLI の仮のデータ）。
  - オンボーディングの Tips のページ・貼り付けられなかった結果のパネルで、続きがあること（スクロールできること）が見た目から分かりにくい。
  - アプリ別の欄で「Microsoft Teams…」が省略され、Teams が 2 行あると見分けにくい。
  - 英語のとき、辞書のアイコンが「あ」の字の本のまま。
  - 会議の記録中の AI チャットで、よく使う質問のボタンの列が右端で切れる（横に流せる作りなら問題ない）。
- 判定していないもの: 操作（drive）22 件・手（manual）36 件と、Windows の項目すべて。

## 2. 2026-11-08 議事録に使う発言の選択とオフレコ（main の取り込みのあと、macOS 26.6.2）

main から取り込んだ REQ-MTG-043〜046 に項目（UX-149〜151）を足し、描画の項目を描いた。

- 描いたもの: `python3 scripts/ui-cases.py render --ids UX-150,UX-151`（ja）
- 判定: OK 2・NG 0・判断できない 0・描けなかった 0

| ID | 言語 | 判定 | メモ |
| --- | --- | --- | --- |
| UX-150 | ja | OK | live-offrecord.png に「オフレコを終える」と「オフレコ中（05:00 から）…」の帯。オフレコの発言は薄く取り消し線と「オフレコ」の印。transcript-selected.png に「オフレコ 05:00 〜 06:40」 |
| UX-151 | ja | OK | 範囲の外は薄く「範囲外」、除いた発言は取り消し線と「除外」、話者の除外は「話者を除外」。transcript-selecting.png にチェックボックス。minutes-outdated.png に「作り直すと反映されます」 |

- 気づいたこと: live-offrecord.png でも「★ ここ重要」が「★ こ」で切れる（1 の UX-053 と同じ。描画の幅による可能性）。
- 判定していないもの: UX-149（スリープ。手）。

## 3. 2026-11-09 レビューのあとの直し（macOS 26.6.2）

PR #86 のレビューで、`ui-cases.py` が「確かめ方」の下の箇条書きに書いた「実機」を読んでいなかったことが分かり、直したら REQ-DIC-082 に項目がないことが分かった。UX-152 を足して描いた。あわせて、描画の CLI が PNG を書かずに 0 で終わったときも失敗にした（偽の実行ファイル `/usr/bin/true` で、前の回の PNG が残っていても失敗になることを確かめた）。

- 描いたもの: `python3 scripts/ui-cases.py render --ids UX-152`（ja）
- 判定: OK 1・NG 0・判断できない 0・描けなかった 0

| ID | 言語 | 判定 | メモ |
| --- | --- | --- | --- |
| UX-152 | ja | OK | settings-ai.png に「整形の言語」の欄があり、「話した言語」が選ばれている |

- 気づいたこと: `--render-ai-settings` の PNG は AI の欄の途中（Claude の API キー）から描かれ、上の「使う AI とモデル」「整形の言語」が写らない。設定の AI を見るときは `--render-settings --pane ai` を使う。

## 4. 2026-11-09 会議ノートの UI の作り直し（00fd9e0 の上の作業中の変更、macOS 26.6.2）

- 描いたもの: `python3 scripts/ui-cases.py render --ids UX-052,UX-053,UX-054,UX-057,UX-058,UX-062,UX-111,UX-136,UX-139,UX-141,UX-150,UX-151,UX-160,UX-161,UX-162,UX-163,UX-164,UX-165,UX-131`（19 件、言語: ja）。指摘を直したあと、UX-150・162・164・165 を描き直した
- 判定: OK 15・NG 0・判断できない 4・描けなかった 0
- `--render-meeting-window` の出力に NG はない（最小の大きさ 1040×560 で、左右の画面がウインドウの中身に収まり、文書の幅は 412）

| ID | 言語 | 判定 | メモ |
| --- | --- | --- | --- |
| UX-052 | ja | OK | live.png で自分と相手が色で分かれ、時刻つき。確定前の発言は薄い |
| UX-053 | ja | OK | live.png にメモ欄と「★ ここ重要」、live-undo.png に「★ を取り消す（あと 5 秒）」 |
| UX-054 | ja | OK | caption.png が読める |
| UX-057 | ja | OK | 型の選択・テンプレートの管理・カスタムの指示のシート、detail.png のアクションアイテムのカード |
| UX-058 | ja | OK | 題名の枠と鉛筆、参加者のボタン、more-menu.png の「話者名…」 |
| UX-062 | ja | OK | search.png・ask.png |
| UX-111 | ja | OK | 長いエラーが帯の中で 2 行に切られ、長い話者名は崩れない |
| UX-131 | ja | 判断できない | 描き方の限界（「★ ここ重要」の黄色が灰色になる）。文字と星が黒いことは確かめた |
| UX-136 | ja | OK | detail-regenerating.png の帯と薄い議事録 |
| UX-139 | ja | OK | 推測した「田中」、名前のない「話者2」、「自分」 |
| UX-141 | ja | OK | よく使う質問のボタン、答えの時刻のリンクと「メモに残す」 |
| UX-150 | ja | OK | 直したあと: オフレコのボタンをツールバーでも文字つきにした（`labelStyle(.titleAndIcon)`）。live-offrecord.png の帯と、文字起こしのオフレコの区間 |
| UX-151 | ja | OK | 範囲の外・オフレコの発言の見た目、チェックボックス、折り返すカプセル、文書の上の帯 |
| UX-160 | ja | OK | document-full.png の順番（見出し・概要・アクションアイテム・本文・ここ重要・メモ）、本文にアクションアイテムの見出しがない。ツールバーのボタン |
| UX-161 | ja | OK | ツールバーが切れていない。出力に NG がない |
| UX-162 | ja | OK | 行末の印、「59:00」は灰色の取り消し線。直したあと: 印が前の文と行をまたいで割れない |
| UX-163 | ja | 判断できない | バー・「再生中」・片方だけ・読めない音声の文言は OK。描き方の限界（ガラスの中のスライダーの話者の色と★の色、暗い地での文字の色が描けない） |
| UX-164 | ja | OK | live.png の配置、processing-document.png の段階の帯と「議事録ができたら書き足せます」 |
| UX-165 | ja | OK | banners-document.png で失敗の帯（2 行まで、「詳しく」「閉じる」）と作り直しの帯が積んで出る |

気づいたこと（判定に含めない）:

- ウインドウで描いた PNG（window*.png・*-min.png・processing.png など）は、真ん中の文書・左の一覧・後ろ側のパネルが描けない（描き方の限界）。中身は単独で描いた PNG（document-full.png・inspector-*.png・processing-document.png・banners-document.png）で見る。
- 再生のバーのボタンと文字の色、「★ ここ重要」の黄色は、実機（明るい表示・暗い表示）で確かめる。
- 見出しの参加者の丸は重ねて並べるので、頭文字が半分隠れる。

## 5. 2026-11-09 main（PR #89 の会議ノートから辞書を作る）の取り込みのあと（macOS 26.6.2）

辞書のメニューを詳細の上のボタンの並びからツールバーへ移したので、その項目だけ描き直した。

| 項目 | 言語 | 結果 | 見たこと |
|---|---|---|---|
| UX-154 | ja | OK | window-min.png のツールバーで「作り直す」と「書き出し」の間に辞書のアイコン（本）があり、切れていない。detail-outdated.png の文書の上と文字起こしの上に「文字起こしか、議事録に使う発言を変えました」の帯、文字起こしに Anews・Stockmark が出ている |
| UX-161 | ja | OK | 辞書のアイコンを足しても、出力に NG がなく、最小の大きさでツールバーが切れていない |

## 6. 2026-11-10 会議の録音の削除（dcc99df に未コミットの変更、macOS 26.6.2）

- 描いたもの: `python3 scripts/ui-cases.py render --ids UX-161,UX-164,UX-166,UX-167,UX-168`（5 件、言語: ja）
- 判定: OK 5・NG 0・判断できない 0・描けなかった 0

| ID | 言語 | 判定 | メモ |
| --- | --- | --- | --- |
| UX-161 | ja | OK | 記録中のツールバーに切り替えを足しても、出力に NG がない |
| UX-164 | ja | OK | live-min.png の配置は変わらない |
| UX-166 | ja | OK | live-window-min.png・live-window.png で、オフレコ・字幕のあとにゴミ箱の切り替えが押された見た目で出て、パネルの切り替えと並び、はみ出しのメニューに隠れていない |
| UX-167 | ja | OK | more-menu.png に「録音を削除…」「録音の管理…」が区切り線の間に並び、more-menu-no-audio.png では「録音を削除…」だけが薄い |
| UX-168 | ja | OK | manager.png の見出しと件数・合計（うち 2 件は欠けている）、印 2 つ、大きさ、3 つのボタン、同期の注意。manager-empty.png の「録音はありません」 |

気づいたこと（判定に含めない）:

- 記録中のゴミ箱の切り替えのオレンジの色は、画面の外のウインドウでは描けない。実機で見る。
- 設定の「会議」の描き出しは高さが足りず、録音の項目（文字起こしのあとに削除・残す期間・残っている録音）が写らない（UX-169 は manual にした）。

## 7. 2026-11-10 スクリーンショットの文字（REQ-DIC-041・042）を足したブランチ（macOS 26.6.2）

| 項目 | 言語 | 結果 | 見たこと |
|---|---|---|---|
| UX-172 | ja | OK | hud-screenshot-on/off/inactive.png で、録音中の HUD の 2 行目の音量の目安の左にカメラのボタンがある。on は青、off は灰色、inactive は薄い灰色で、マイクのボタンと音量の目安は隣り合ったまま。文字と重ならない |
| UX-172 | en | OK | 言語の切り替え（Spoken Language・English・日本語）が出る幅の HUD でも、ボタンが切れず、ほかと重ならない |
| UX-171 | ja | OK | スクリーンショットのトグルがオンで、画面収録が未許可の案内と「許可する…」が出る。--meeting では「許可する…」が押せない見た目で、会議の記録が終わってから許可する旨が出る。除外アプリの欄は押せる |
| UX-171 | de | OK | 長い説明が折り返され、トグルと重ならない |

確かめていないこと: 画面収録の許可のダイアログ、許可して戻ったときに案内が消えること、権限タブの行（`--render-settings` では描いていない）。

## 8. 2026-11-10 AI チャット・質問の送り先の切り替え（c9609d8 の上の作業中の変更、macOS 26.6.2）

AI チャット・会議への質問のモデルを議事録と分けて選び、画面でも切り替える変更（REQ-COM-025・REQ-MTG-048・REQ-MTG-049、[plans/ai-chat-model.md](../plans/ai-chat-model.md)）のあとで確かめた結果。

- 描いたもの: `python3 scripts/ui-cases.py render --ids UX-141,UX-180,UX-181,UX-182 --lang ja,en`。ほかに `--render-meeting-chat <dir> --ui-language de` で、ドイツ語の送り先のメニュー・外に送るかの文・使えないときの案内が切れないことを見た。
- 判定: OK 8・NG 0・判断できない 0・描けなかった 0

| ID | 言語 | 判定 | メモ |
| --- | --- | --- | --- |
| UX-141 | ja | OK | 答えの見出しの「AI」の横に「Claude · Haiku 5.5」 |
| UX-141 | en | OK | |
| UX-180 | ja | OK | 送り先のメニュー・外に送るかの文・切り替え中の印・既定が使えないときの案内（オレンジ） |
| UX-180 | en | OK | 「Send to: Claude · Haiku 5.5」 |
| UX-181 | ja | OK | 質問の欄の下に送り先と送るものの説明、答えの下にモデル名 |
| UX-181 | en | OK | |
| UX-182 | ja | OK | 設定の「AI」とオンボーディングの Tips に 3 行。Tips のページはこの Mac の設定のまま描かれる |
| UX-182 | en | OK | |

- 残り（実機）: メニューを開いて選ぶこと、使えない項目が選べないこと、記録のあとも切り替えが続くこと、会議のウインドウを閉じると会議に質問の切り替えが戻ること、ローカルで議事録の作成中にチャットが待つこと（DEC-COM-172）。

## 9. 2026-11-10 main（PR #94 の「何を聞かれた？」）の取り込みのあと（macOS 26.6.2）

- 描いたもの: `python3 scripts/ui-cases.py render --ids UX-141,UX-180,UX-181,UX-182 --lang ja`
- 判定: OK 4・NG 0・判断できない 0・描けなかった 0。AI チャットの入力欄の上に「何を聞かれた？」のボタン（PR #94）、下に送り先のメニューが並んで出る
- 「何を聞かれた？」の答えも、その会議の AI チャットの送り先で作るようにした（`--test-meeting-chat` の「その会議の AI チャットと同じ送り先に聞く」）

## 10. 2026-11-11 アップデートのダウンロードの進み具合（34806a4 の上の作業中の変更、macOS 26.6.2）

- 描いたもの: `python3 scripts/ui-cases.py render --ids UX-186 --lang ja,en`（1 件、言語: ja・en）
- 判定: OK 2・NG 0・判断できない 0・描けなかった 0

| ID | 言語 | 判定 | メモ |
| --- | --- | --- | --- |
| UX-186 | ja | OK | バーが約 4 割、「42%（11.4 MB / 27.1 MB）」が 1 行。確かめ中は不定のバーと「ダウンロードしたファイルを確かめています…」、「中止」は薄い |
| UX-186 | en | OK | 「Downloading Hanasu 2.3.1…」「42% (11.4 MB / 27.1 MB)」「Verifying the downloaded file…」が切れない |

- 描画では見られない部分（REQ-REL-012）: `Hanasu --download-update` で GitHub の v2.3.0 の zip（20.8 MB）を実際に落とし、0% から 100% まで進み、大きさと SHA-256 が合った（1.6 秒、画面への更新 8 回）。`--cancel-after 0.3` で中止すると 0.3 秒で止まり、作業フォルダに何も残らなかった。古い版の Hanasu.app からの入れ替えと、Windows の窓は、まだ実機で見ていない

## 11. 2026-11-11 文字起こし AI を「AI」タブへ移し、用途を「音声入力整形」「議事録」と呼ぶ（0d2b3f3 の上の作業中の変更、macOS 26.6.2）

- 描いたもの: `python3 scripts/ui-cases.py render --ids UX-182,UX-188,UX-077`（3 件、言語: ja）。英語は `Hanasu --ui-language en --render-settings <dir> --pane ai` で別に描いた。
- 判定: OK 4・NG 0・判断できない 0・描けなかった 0

| ID | 言語 | 判定 | メモ |
| --- | --- | --- | --- |
| UX-182 | ja | OK | 「文字起こしのあとの AI」に「音声入力整形」「議事録」「AI チャット・質問」。議事録の説明は「作り直しも含む・辞書の候補」。オンボーディングの Tips のページも同じ 3 行 |
| UX-188 | ja | OK | AI タブの先頭に「文字起こし AI」（音声入力・会議の記録・Mac 標準の認識モデル・文字起こしの言語）、その下に「文字起こしのあとの AI」。一般タブのコードから文字起こしの欄を外した（描いた画像は上の部分だけで、一般タブの下までは写らない） |
| UX-077 | ja | OK | 見出しが「文字起こし AI」、言語のラベルが「文字起こしの言語」 |
| UX-188 | en | OK | 「Transcription AI」「Transcription Language」「AI After Transcription」「Dictation Refinement」「Minutes」が切れない |

- Windows: `dotnet build Hanasu.Windows/Hanasu.Windows.csproj -p:EnableWindowsTargeting=true`（Mac の上）で XAML ごとビルドが通った。画面の見た目と出し分けは、まだ Windows の実機で見ていない（UX-187 の Windows は手）。

## 12. 2026-11-10 `hanasu` コマンドの段階 4（設定の「コマンドと MCP」。ff7b733 の上の作業中の変更、macOS 26.6.2）

- 描いたもの: `.build/debug/Hanasu --render-settings <フォルダ> --pane commandLine`（ja・en・ar）。
- 判定: OK 1

| ID | 言語 | 判定 | メモ |
| --- | --- | --- | --- |
| UX-183 | ja・en・ar | OK | 実行ファイルのパス・PATH の状態と「PATH に入れる…」・Claude Code のコマンド・Claude Desktop の JSON に、コピーのボタン。ウインドウの高さで、下の「エージェントへの説明」の節は描き出しの外（`hanasu help agent` の出力を自己テストで確かめた）。サイドバーが空なのは、ほかの項目の描き出しと同じ |

- 残り: UX-184（App Translocation）と UX-185（Claude Code に登録して質問）は人が確かめる。「PATH に入れる…」で管理者の確認が出て `/usr/local/bin` に入ることも実機。

## 13. 2026-11-12 設定の「AI アプリにつなぐ」（REQ-COM-194。b21a709 の上の作業中の変更、macOS 26.6.2）

- 描いたもの: `python3 scripts/ui-cases.py render --ids UX-195,UX-183 --lang en,ar`、ja は `.build/debug/Hanasu --render-settings <フォルダ> --pane commandLine [--connect-fixture empty]`。
- 判定: OK 2

| ID | 言語 | 判定 | メモ |
| --- | --- | --- | --- |
| UX-195 | ja・en・ar | OK | 架空の状態 all で 5 行（Claude Desktop・Claude-Personal・Claude-Work・ChatGPT（Codex）・Claude Code）。つないでいます（緑）・別の場所・Hanasu のものでない（npx）・読めない・つないでいません と、ボタンの出し分け、ChatGPT と Claude Code の注記が出る。empty では Claude Desktop と ChatGPT が「見つかりません」で「つなぐ…」が薄い。文字の欠け・重なりなし |
| UX-183 | en・ar | OK | 「AI アプリにつなぐ」の下に、実行ファイル・PATH・MCP のコピーの欄が続く（commandLine の描画は縦 2700 にした） |

- 実機（この Mac、本物の設定ファイル。2026-11-12 にユーザーが了承）: `.build/debug/Hanasu --agent-connect-list` / `--agent-connect <番号> connect|disconnect`（設定画面のボタンと同じ処理）で確かめた。
  - 状態の読み取り: 既定の Claude（このセッションが動いている）は running、`Claude-Personal` は止まっている、`Claude-3p`（`deploymentMode` あり）は出ない、ChatGPT は止まっている、`claude` は `~/.local/bin/claude`。
  - 既定の Claude Desktop: `running` で書かれなかった。
  - `Claude-Personal`: つないだ。`.hanasu-backup` が 0600 で残り、ほかのキー（`coworkUserFilesPath`・`preferences`）は値が同じ。
  - ChatGPT（Codex）: つないだ。`~/.codex/config.toml` の差分は終わりの 6 行（印の行・表）だけで、`tomllib` で読める。0600 のまま。
  - Claude Code: `claude mcp add --scope user` で登録し、`claude mcp get hanasu` が「✔ Connected」（`hanasu mcp` が起動して応えた）。外す → 消えた。前の場所の Hanasu を登録しておいてつなぐ → remove してから add され「connected」。最後に外した。
- 残り: `Claude-Personal` と ChatGPT のアプリを開いて、チャット（ChatGPT は Codex）で会議を読めるかと、既定の Claude Desktop を終了してつなぐのは、ユーザーに頼む。Windows（UX-196）は Windows の実機。
