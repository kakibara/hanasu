# Changelog

## [v2.6.2](https://github.com/kakibara/hanasu/compare/v2.6.1...v2.6.2) - 2026-11-13

- Windows 版の sherpa-onnx を 2.0.1 に上げ、GPL-3.0 の espeak-ng を配布物から外す by @kakibara in https://github.com/kakibara/hanasu/pull/111

## [v2.6.1](https://github.com/kakibara/hanasu/compare/v2.6.0...v2.6.1) - 2026-11-12

- Windows の hanasu を Server GC で動かし、CI の検索の速さの上限を 3 秒にする by @kakibara in https://github.com/kakibara/hanasu/pull/107

## [v2.6.0](https://github.com/kakibara/hanasu/compare/v2.5.0...v2.6.0) - 2026-11-12

- 多言語に対応したあとも日本語・英語を前提にしていた所を、Mac と Windows の両方で直す by @kakibara in https://github.com/kakibara/hanasu/pull/104
- hanasu コマンドを Mac と Windows に足す（会議を読む・探す・聞く・MCP、文章の整形） by @kakibara in https://github.com/kakibara/hanasu/pull/78
- Dock のアイコンを押しても設定画面を出さないようにし、「メニューバーだけ」をなくす（Mac） by @kakibara in https://github.com/kakibara/hanasu/pull/106

## [v2.5.0](https://github.com/kakibara/hanasu/compare/v2.4.1...v2.5.0) - 2026-11-11

- 設定の「AI」タブに文字起こし AI を移し、文章の AI を「音声入力整形」「議事録」と呼ぶ by @kakibara in https://github.com/kakibara/hanasu/pull/102

## [v2.4.1](https://github.com/kakibara/hanasu/compare/v2.4.0...v2.4.1) - 2026-11-11

- 長い記録でメモリと CPU が増え続けるのを抑える by @kakibara in https://github.com/kakibara/hanasu/pull/99
- 起動のたびに設定画面を開くのをやめる by @kakibara in https://github.com/kakibara/hanasu/pull/101

## [v2.4.0](https://github.com/kakibara/hanasu/compare/v2.3.0...v2.4.0) - 2026-11-11

- AI チャットと会議に質問の送り先を、議事録とは別に選べるようにし、画面でも切り替えられるようにする（Mac） by @kakibara in https://github.com/kakibara/hanasu/pull/95
- 更新のダウンロード中に、進み具合のバーと大きさ・「中止」を出す by @kakibara in https://github.com/kakibara/hanasu/pull/98

## [v2.3.0](https://github.com/kakibara/hanasu/compare/v2.2.0...v2.3.0) - 2026-11-11

- 会議の録音を消す機能: 会議ごとに文字起こしのあとに消す・あとから消す・録音の管理・保存期間（Mac と Windows） by @kakibara in https://github.com/kakibara/hanasu/pull/91
- 会議中に「何を聞かれた？」をボタン 1 つで確かめられるようにする（Mac） by @kakibara in https://github.com/kakibara/hanasu/pull/94
- 音声入力で、画面のスクリーンショットの文字を AI の整形に渡せるようにする by @kakibara in https://github.com/kakibara/hanasu/pull/93
- 録音中の HUD の「■ 停止」を「■ 完了」にする by @kakibara in https://github.com/kakibara/hanasu/pull/92

## [v2.2.0](https://github.com/kakibara/hanasu/compare/v2.1.0...v2.2.0) - 2026-11-09

- UI のテスト項目をデータにし、Mac は画面を PNG に描いて確かめる（DEC-COM-170） by @kakibara in https://github.com/kakibara/hanasu/pull/86
- 会議ノートから辞書を作り、会議の文字起こしにも辞書を当てる（Mac・Windows） by @kakibara in https://github.com/kakibara/hanasu/pull/89
- Microsoft Copilot と声でやり取りする実現性の調査を docs/plans に置く by @kakibara in https://github.com/kakibara/hanasu/pull/88
- 会議ノートの UI を作り直す（Mac）: 文書と右のパネル・議事録から発言への引用・音声の再生 by @kakibara in https://github.com/kakibara/hanasu/pull/90

## [v2.1.0](https://github.com/kakibara/hanasu/compare/v2.0.1...v2.1.0) - 2026-11-08

- 依頼から要件定義を詰めて計画を固めるスキル requirements を足す by @kakibara in https://github.com/kakibara/hanasu/pull/82
- 翻訳の言語とアプリ別の出力言語を、対応する 17 言語すべてにする by @kakibara in https://github.com/kakibara/hanasu/pull/81
- 更新ダイアログのリリース文を整えて出し、スクロールを軽くする（Mac） by @kakibara in https://github.com/kakibara/hanasu/pull/79
- 更新の知らせのリリース文を整えて全文を出す（Windows） by @kakibara in https://github.com/kakibara/hanasu/pull/80
- 会議の記録中のスリープへの対応と、議事録に使う発言を選ぶ機能（Mac・Windows） by @kakibara in https://github.com/kakibara/hanasu/pull/77
- 要件定義の計画を了承の前に敵対的にレビューするスキルとエージェントを足す by @kakibara in https://github.com/kakibara/hanasu/pull/84
- Mac の履歴も、知らないモードの値を残して読み、値のまま書き戻す by @kakibara in https://github.com/kakibara/hanasu/pull/85

## [v2.0.1](https://github.com/kakibara/hanasu/compare/v2.0.0...v2.0.1) - 2026-11-06

- AI の選択肢を、ローカルを左に、外部 API を右に並べる by @kakibara in https://github.com/kakibara/hanasu/pull/74
- 設定の「スニペット」画面が崩れるのを直す by @kakibara in https://github.com/kakibara/hanasu/pull/75
- 設定の文言の古い言い方（「「AI」タブ」「Gemini か Claude」）を直し、韓国語・中国語の「ここ重要」をそろえる by @kakibara in https://github.com/kakibara/hanasu/pull/73

## [v2.0.0](https://github.com/kakibara/hanasu/compare/v1.5.0...v2.0.0) - 2026-11-06

- 初回起動のオンボーディングと既定の AI の選択を足す by @kakibara in https://github.com/kakibara/hanasu/pull/53
- 録音中の HUD に、どのエンジンでもマイクの音量を出す by @kakibara in https://github.com/kakibara/hanasu/pull/54
- PR をマージする前に不具合がないことを確かめるスキルを足す by @kakibara in https://github.com/kakibara/hanasu/pull/52
- 貼り付けが届かなかったときは、最新の結果をクリップボードに残す by @kakibara in https://github.com/kakibara/hanasu/pull/56
- README を今の実装に合わせ、ローカルのモデルに Qwen3.5-4B を足し、Gemma 4 E4B を勧める by @kakibara in https://github.com/kakibara/hanasu/pull/57
- README に、貼り付けが届かなかったときの扱いを足す by @kakibara in https://github.com/kakibara/hanasu/pull/58
- Mac の既定の AI をローカルの Gemma にし、モデルがないときはダウンロードを尋ねる by @kakibara in https://github.com/kakibara/hanasu/pull/59
- 会議の記録中に、それまでの会話をもとに AI とチャットできるようにする by @kakibara in https://github.com/kakibara/hanasu/pull/68
- PR #65 の判断事項 12 件の対応（#65 に積む） by @kakibara in https://github.com/kakibara/hanasu/pull/69
- 会議アプリから会議の名前を読み取り、議事録のタイトルにする by @kakibara in https://github.com/kakibara/hanasu/pull/66
- Mac の設定画面を、左のサイドバーで項目を切り替える形にする by @kakibara in https://github.com/kakibara/hanasu/pull/70
- 包括レビューに基づく改善（セキュリティ・パフォーマンス・UI/UX） by @kakibara in https://github.com/kakibara/hanasu/pull/65
- 議事録のテンプレートに名前を付けて保存・管理できるようにする（Mac 版） by @kakibara in https://github.com/kakibara/hanasu/pull/67
- 起動時とメニューからアップデートを確かめ、ユーザーが選んだときだけ入れ替える by @kakibara in https://github.com/kakibara/hanasu/pull/71
- AI へのプロンプトを 17 言語にし、文字起こしの言語で切り替える（多言語化 1/3） by @kakibara in https://github.com/kakibara/hanasu/pull/62
- ライセンスを PolyForm Noncommercial と追加の許可にし、大きい会社には商用ライセンスを求める by @kakibara in https://github.com/kakibara/hanasu/pull/72
- Mac の表示を 17 言語にし、システムの言語で切り替える（多言語化 2/3） by @kakibara in https://github.com/kakibara/hanasu/pull/63
- Windows の表示を 17 言語にし、Windows の表示の言語で切り替える（多言語化 3/3） by @kakibara in https://github.com/kakibara/hanasu/pull/64
- README を 15 の言語に訳し、すべての README に言語の切り替えを付ける by @kakibara in https://github.com/kakibara/hanasu/pull/61

## [v1.5.0](https://github.com/kakibara/hanasu/compare/v1.4.1...v1.5.0) - 2026-11-04

- 文字起こしの言語の選択と、整形の出力の言語の設定を追加する by @kakibara in https://github.com/kakibara/hanasu/pull/43
- Mac のアイコンを出す場所を、メニューバー / Dock / 両方から選べるようにする by @kakibara in https://github.com/kakibara/hanasu/pull/44
- 会議の記録を削除できるようにし、タイトルの欄が書き換えられると見てわかるようにする by @kakibara in https://github.com/kakibara/hanasu/pull/45
- Mac の会議ノートで、議事録を作り直しても選んでいた会議のままにし、作り直し中だとわかるようにする by @kakibara in https://github.com/kakibara/hanasu/pull/46
- 音声入力のマイクを、設定と録音中の HUD から選べるようにする by @kakibara in https://github.com/kakibara/hanasu/pull/47
- 録音中の HUD で、言語の切り替えが折り返さないようにする by @kakibara in https://github.com/kakibara/hanasu/pull/49
- 翻訳の言語に日本語を足し、設定で翻訳する言語を複数選べるようにする by @kakibara in https://github.com/kakibara/hanasu/pull/51
- 使っていない間の Mac 版の CPU を抑える（隠れた HUD などの描き直しを止める） by @kakibara in https://github.com/kakibara/hanasu/pull/50

## [v1.4.1](https://github.com/kakibara/hanasu/compare/v1.4.0...v1.4.1) - 2026-11-04

- リリースのスキルに、v1.4.0 で分かったこと（最適化ビルドの確認とタグの付け直し）を書き足す by @kakibara in https://github.com/kakibara/hanasu/pull/41
- Mac の会議ノートで「メモ」タブを開くと、中身がウインドウからはみ出して戻れなくなるのを直す by @kakibara in https://github.com/kakibara/hanasu/pull/42

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
