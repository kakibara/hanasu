# Changelog

## [v1.4.0](https://github.com/kakibara/hanasu/compare/v1.3.3...v1.4.0) - 2026-11-04

- 会議の「ここ重要」の取り消し・前後の会話の確認と、Mac の会議ノートで「メモ」タブを開くとタブが消える不具合の修正 by @kakibara in https://github.com/kakibara/hanasu/pull/34
- 会議の会話から話者の名前を推測して付ける by @kakibara in https://github.com/kakibara/hanasu/pull/35
- 会議ノートの左の欄で、一覧と下の設定欄が重ならないようにする by @kakibara in https://github.com/kakibara/hanasu/pull/37
- リリースの手順をスキルにし、版の決め方とリリース文のテンプレートを決める by @kakibara in https://github.com/kakibara/hanasu/pull/38

## [v1.3.3](https://github.com/kakibara/hanasu/compare/v1.3.2...v1.3.3) - 2026-11-04

- 整形と議事録に、端末の中で動く小型の LLM（Gemma 4 E4B・LFM2.5-1.2B-JP・Sarashina2.2）と Apple の Foundation Models（fm）を選べるようにする by @kakibara in https://github.com/kakibara/hanasu/pull/31
- Windows 版にも音声入力の履歴を残し、既定 30 日・設定で日数を変えられるようにする by @kakibara in https://github.com/kakibara/hanasu/pull/32

## [v1.3.2](https://github.com/kakibara/hanasu/compare/v1.3.1...v1.3.2) - 2026-11-03

- リリースの Windows 版のビルドでも、publish では lock ファイルの locked mode を外す by @kakibara in https://github.com/kakibara/hanasu/pull/29
- 入力できる場所がないときは、結果を画面に残して自分で貼れるようにする（Mac 版） by @kakibara in https://github.com/kakibara/hanasu/pull/27
- 入力できる場所がないときは、結果を画面に残して自分で貼れるようにする（Windows 版） by @kakibara in https://github.com/kakibara/hanasu/pull/28

## [v1.3.1](https://github.com/kakibara/hanasu/compare/v1.3.0...v1.3.1) - 2026-11-03

- 文書を実装済みの仕様と将来の計画に分け、要件・設計判断を ID で追えるようにする by @kakibara in https://github.com/kakibara/hanasu/pull/21
- ライセンスを Apache-2.0 にし、Windows 版の配布物にもライセンスの表示を入れる by @kakibara in https://github.com/kakibara/hanasu/pull/23
- README を GitHub 向けに作り直し、英語版を用意する by @kakibara in https://github.com/kakibara/hanasu/pull/24
- Claude API を選べるようにし、API キーの保存とセキュリティを見直す（Mac 版） by @kakibara in https://github.com/kakibara/hanasu/pull/26
- Claude API を選べるようにし、API キーの保存とセキュリティを見直す（Windows 版） by @kakibara in https://github.com/kakibara/hanasu/pull/25

## [v1.3.0](https://github.com/kakibara/hanasu/compare/v1.2.0...v1.3.0) - 2026-11-03

- 録音中の HUD に停止・取消のボタンを付ける by @kakibara in https://github.com/kakibara/hanasu/pull/16
- 文字起こしのエンジンを Mac 標準 / Whisper / Gemini から選べるようにする by @kakibara in https://github.com/kakibara/hanasu/pull/17
- リリースを zip に戻し、Windows 版も添付する by @kakibara in https://github.com/kakibara/hanasu/pull/20
- Windows 版（音声入力と会議の記録）を追加する by @kakibara in https://github.com/kakibara/hanasu/pull/19

## [v1.2.0](https://github.com/kakibara/hanasu/compare/v1.1.1...v1.2.0) - 2026-11-03

- 選択したテキストを声で書き換える編集モードを追加する by @kakibara in https://github.com/kakibara/hanasu/pull/8
- 会議の自動検出と、記録を始めるかの提案を追加 by @kakibara in https://github.com/kakibara/hanasu/pull/14
- 入力先アプリごとの整形スタイル（チャット／メール／文書のプリセット・既定の出力言語） by @kakibara in https://github.com/kakibara/hanasu/pull/5
- スニペット（決まった言葉で定型文を入力）を追加する by @kakibara in https://github.com/kakibara/hanasu/pull/6
- 画面の文脈（ウインドウのタイトル・カーソル前後の文章）を使って整形する by @kakibara in https://github.com/kakibara/hanasu/pull/7
- ユーザー辞書に置き換えルールと候補の提案を足す by @kakibara in https://github.com/kakibara/hanasu/pull/12
- 音声入力の履歴ウインドウと、整形・英訳のやり直し by @kakibara in https://github.com/kakibara/hanasu/pull/9
- 会議中のメモと「ここ重要」の印を議事録に反映する by @kakibara in https://github.com/kakibara/hanasu/pull/10
- 会議の横断検索と、過去の会議への質問（Ask）を追加 by @kakibara in https://github.com/kakibara/hanasu/pull/11
- 議事録のテンプレートと書き出し（Slack・ファイル・リマインダー） by @kakibara in https://github.com/kakibara/hanasu/pull/13

## [v1.1.1](https://github.com/kakibara/hanasu/compare/v1.1.0...v1.1.1) - 2026-11-02

## [v1.1.0](https://github.com/kakibara/hanasu/compare/v1.0.0...v1.1.0) - 2026-11-02

## [v1.0.0](https://github.com/kakibara/hanasu/commits/v1.0.0) - 2026-11-02
