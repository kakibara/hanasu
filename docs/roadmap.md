# Hanasu の計画（ロードマップ）

**まだ main に入っていないもの**だけを置く。実装済みの振る舞いは [spec/](spec/) にある。

- 各項目に `FUT-<番号>` を付ける。番号は使い回さない（やめた項目も、消さずに「やめた」と書いて残す）。
- 実装したら、その項目の中身を spec に要件（REQ）か設計判断（DEC）として書き、ここからは消して「→ REQ-…」とだけ残す（[docs/README.md](README.md) の「変更の手順」）。
- 状態は 進行中 / 未着手 / 見送り（理由つき） / やめた のどれか。
- 番号の分け方: 0xx 全体・Windows、1xx 音声入力、2xx 会議の記録。

| ID | 項目 | 状態 | 出どころ |
| --- | --- | --- | --- |
| FUT-001 | Windows 版（音声入力と会議の記録） | 進行中（PR #19） | ユーザーの指定（2026-11-03） |
| FUT-002 | Windows 版のコードに要件・設計判断のタグを付ける | 未着手（#19 のマージ後） | この PR |
| FUT-101 | ブラウザのサイト別スタイル | 見送り | PR #5 |
| FUT-102 | 画面の文脈で、Slack のスレッドの直前のメッセージも読む | 見送り | PR #7 |
| FUT-103 | 音声認識にカスタム言語モデル（customLanguageModel）を使う | 見送り | PR #12 |
| FUT-104 | 会議の文字起こし・議事録にも辞書の置き換えルールを当てる | 未着手 | PR #12 |
| FUT-105 | 履歴の録音から文字起こしし直す | 未着手 | PR #9 |
| FUT-106 | Whisper で録音中に途中経過を出す | 見送り | PR #17 |
| FUT-107 | Gemini のストリーミング応答で、体感の待ち時間を短くする | 未着手 | 初版の「今後の拡張候補」 |
| FUT-108 | Fn キー（Globe キー）でのトリガー | 未着手 | 初版の「今後の拡張候補」 |
| FUT-201 | 会議アプリだけを録るモード | 未着手（フェーズ 2） | 初版のフェーズ分け |
| FUT-202 | マイク側のエコーキャンセル | 未着手（フェーズ 2） | 初版のフェーズ分け |
| FUT-203 | ボットモード（会議にボットを参加させて記録する） | 未着手（計画あり） | [plans/bot-mode.md](plans/bot-mode.md) |

---

## 全体・Windows

### FUT-001 Windows 版（音声入力と会議の記録）
- 状態: 進行中（PR #19、`feature/windows-app`）
- 中身: Windows でも音声入力と会議の記録を使えるようにする。文字起こしのエンジンは Windows 標準の音声認識（既定）・Whisper・Gemini から選べる（REQ-COM-001〜003 と同じ）。
- 出どころ: ユーザーの指定（2026-11-03）「Windows 版は音声入力と会議の記録の両方を作る」
- マージしたら: 既存の REQ / DEC のうち Windows でも同じものは「対象」に Windows を足す。Windows だけの振る舞いは、同じ領域（DIC・MTG・COM）に新しい ID で書く。リリースへの添付（REQ-REL-004）はもう main にある。

### FUT-002 Windows 版のコードに要件・設計判断のタグを付ける
- 状態: 未着手（PR #19 のマージ後に別の作業で行う）
- 中身: `windows/` のコードに `// 要件: REQ-…`、`// 設計判断: DEC-…` を付ける。`scripts/check-spec.py` は `windows/` の `.cs` も読むので、タグを付ければそのまま数えられる。
- 出どころ: この PR（文書を spec と roadmap に分けたとき）

---

## 音声入力

### FUT-101 ブラウザのサイト別スタイル
- 状態: 見送り（利用者の多い Chrome / Arc で、副作用なしに URL を取る方法が決まらない）
- 中身: Chrome / Safari / Arc の中で「Gmail ならメール、Slack の Web 版ならチャット」とサイトで文体を分ける（REQ-DIC-020 の延長）。
- 出どころ: PR #5
- 調べたこと: 録音を始めたときに前面タブの URL が要る。アクセシビリティ（AX）で取れるかを調べた結果:
  - **Safari**: Web の中身は `AXWebArea` で、`AXURL` 属性にページの URL がある。`AXFocusedUIElement` から `AXParent` をたどって `AXWebArea` を探せば取れる見込み。Hanasu は ⌘V のためにアクセシビリティの許可を持っているので、許可は増えない。
  - **Chrome / Arc（Chromium）**: 支援技術が動いていないと、Web の中身の AX ツリーを作らない。アプリの要素に `AXManualAccessibility`（または `AXEnhancedUserInterface`）を立てれば作るが、その後はすべてのページで AX ツリーを保つので、CPU とメモリを余計に使う（`AXEnhancedUserInterface` はウインドウ操作のアニメーションが崩れる副作用も知られている）。アドレスバー（`AXTextField`）の値を読む方法もあるが、スキームが省かれていたり、入力途中の文字列だったりする。
  - **AppleScript**（`URL of active tab of front window`）なら Chrome・Safari・Arc とも取れるが、ブラウザごとに「オートメーション」の許可が新たに要り、Info.plist に `NSAppleEventsUsageDescription` を足す必要がある。
  - 調べたときの開発環境ではアクセシビリティの許可がなく（アプリの起動もしない約束）、実機で確かめられなかった。
- 作るときの形: Safari だけなら小さく作れる。スタイルのキーを bundle ID に加えてホスト名（例: `mail.google.com`）でも持ち、ホスト名の一致をアプリより先に見る形にする。

### FUT-102 画面の文脈で、Slack のスレッドの直前のメッセージも読む
- 状態: 見送り（Slack の画面の作りに強く依存して壊れやすく、実機の許可がない環境では確かめられない）
- 中身: 返信相手のメッセージを、画面の文脈（REQ-DIC-040）として渡す。今は Slack はウインドウのタイトル（チャンネル名・相手の名前）だけを渡している（DEC-DIC-062）。
- 出どころ: PR #7
- 作るときの形: AX のツリーを辿って、スレッドの直前のメッセージを探す。

### FUT-103 音声認識にカスタム言語モデル（customLanguageModel）を使う
- 状態: 見送り（初期値の SpeechTranscriber では使えず、学習データを辞書の読みからそのまま作れない）
- 中身: 辞書の語を、音声認識そのものにもっと強く効かせる（REQ-DIC-070 の延長）。
- 出どころ: PR #12
- 調べたこと:
  - `AnalysisContext.contextualStrings[.general]` は、もとから音声入力（`SpeechRecognizer`）と会議（`ChannelTranscriber`）の両方で設定している。PR #12 で、ルールの読みと表記も渡すようにした（DEC-DIC-009）。
  - `DictationTranscriber.ContentHint.customizedLanguage(modelConfiguration:)` で、`SFSpeechLanguageModel` のカスタム言語モデルを使える。ただし、
    - DictationTranscriber でしか使えない（初期値の SpeechTranscriber にはない）。
    - `SFCustomLanguageModelData` から学習データを作り、`SFSpeechLanguageModel.prepareCustomLanguageModel` で事前に準備する必要がある。発音は X-SAMPA で書くので、辞書の「読み」（かな）からそのままは作れない。
- 作るときの形: DictationTranscriber を使う人が多ければ、語とルールの表記を「よく出る語句」として学習データにする方法を試す価値がある。

### FUT-104 会議の文字起こし・議事録にも辞書の置き換えルールを当てる
- 状態: 未着手
- 中身: 今の会議の記録では、辞書を語彙のヒントにだけ使っている（DEC-DIC-085）。文字起こしと議事録にも置き換えルールを当てる。
- 出どころ: PR #12（会議の後処理はほかの PR も触っていたので見送った）

### FUT-105 履歴の録音から文字起こしし直す
- 状態: 未着手
- 中身: 「録音した音声も残す」をオンにした履歴（DEC-DIC-075）で、認識結果が明らかに違うときに、録音から文字起こしし直す。
- 出どころ: PR #9

### FUT-106 Whisper で録音中に途中経過を出す
- 状態: 見送り（数秒ごとに文字起こしし直すので、CPU と電池の負担が大きい）
- 中身: Whisper のエンジンでも、録音中に途中経過を HUD に出す（REQ-DIC-002 の食い違いの解消の候補）。
- 出どころ: PR #17

### FUT-107 Gemini のストリーミング応答で、体感の待ち時間を短くする
- 状態: 未着手
- 中身: 整形の応答をストリーミングで受け取り、待ち時間を短く感じさせる。
- 出どころ: 初版（a787da8）の「今後の拡張候補」

### FUT-108 Fn キー（Globe キー）でのトリガー
- 状態: 未着手
- 中身: Fn キー（Globe キー）で録音を始める。`CGEventTap` が必要で、入力監視の権限が要る（Carbon の `RegisterEventHotKey` では Fn 単体を登録できない。DEC-DIC-011）。
- 出どころ: 初版（a787da8）の「今後の拡張候補」

---

## 会議の記録

### FUT-201 会議アプリだけを録るモード
- 状態: 未着手（初版のフェーズ 2）
- 中身: 設定で「会議アプリだけ」にすると、`kAudioHardwarePropertyProcessObjectList` から Chrome・Safari・Slack・Teams などの音声プロセスを探して `stereoMixdownOfProcesses` で限定する。今は自分以外の音全体を録っている（DEC-MTG-002）。
- 出どころ: 初版（a787da8）の技術選定 4.1 とフェーズ分け

### FUT-202 マイク側のエコーキャンセル
- 状態: 未着手（初版のフェーズ 2）
- 中身: イヤホンを使わないとき、スピーカーから回り込んだ相手の声で自分の発言の認識が崩れる（[verification/meeting.md](verification/meeting.md) 2）。Voice Processing I/O、または相手側の音声を参照信号にした自前のエコー除去で防ぐ。今はテキストでの除去（DEC-MTG-013）とイヤホンの推奨だけ。
- 出どころ: 初版（a787da8）のフェーズ分け、検証結果

### FUT-203 ボットモード（会議にボットを参加させて記録する）
- 状態: 未着手（調査・要件定義・実装計画あり）
- 中身: Meet・Teams・Zoom にボットを参加させ、参加者の実名つきの文字起こしと議事録を残す。Slack ハドルは対象外。
- 出どころ: 2026-11-02 の調査。詳しくは [plans/bot-mode.md](plans/bot-mode.md)。計画の中の B1〜B10 は、実装するときに REQ-MTG の新しい番号として spec に書き直す（初版の要件定義では「会議ツールへのボット参加」は対象外。REQ-MTG-031）
