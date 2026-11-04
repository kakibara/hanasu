# 会議の記録の仕様（MTG）

会議の記録（録音・文字起こし・話者分離・議事録・会議ノート・自動検出・メモ・検索・書き出し）について、**実装済み**の振る舞いのうち、要件（REQ）と設計判断（DEC）を並べる。

- 区分・ID・タグの決まりは [docs/README.md](../README.md)。
- 実装の説明は [design/meeting.md](../design/meeting.md)、検証の記録は [verification/meeting.md](../verification/meeting.md)。
- 初版の要件定義（2026-11-02、a787da8）の F1〜F10・非機能要件・対象外は、この文書の REQ-MTG-001〜010・020〜026・030〜033 に移した。F11〜F16 は 10 個の改善案（PR #10、#11）で足したもの。

---

## 要件

### REQ-MTG-001 メニューバーとショートカットで、会議の記録を始める・止める（F1）
- 内容: メニューバーの「会議の記録を開始／停止」と、ショートカット（初期値 `⌃⌥⌘ M`）で記録を始め、止める。
- 受け入れ条件: どのアプリが前面でもショートカットで記録が始まり、もう一度押すと止まって後処理に進む。
- 出典: 初版の要件定義 F1（必須、a787da8）
- 対象: Mac / Windows
- 実装の場所: `AppDelegate.registerMeetingHotKey`、`MeetingRecorder.toggle`
- Windows の実装: `windows/Hanasu.Core/Meetings/MeetingController.cs`、`windows/Hanasu.Windows/TrayIcon.cs`（メニューはタスクトレイ。ショートカットは DEC-MTG-110）
- 確かめ方: 実機で確かめる

### REQ-MTG-002 マイク（自分）とシステム音声（相手側）を別々に録る（F2）
- 内容: マイクを「自分」、Mac が鳴らしている音を「相手」の 2 チャンネルとして別々に録音する。
- 受け入れ条件: 記録した会議のフォルダに `me.m4a` と `others.m4a` ができ、それぞれに自分の声・相手の声が入る。
- 出典: 初版の要件定義 F2（必須）
- 対象: Mac / Windows
- 実装の場所: `MeetingRecorder.start`、`SystemAudioTap`、`ChannelTranscriber`
- Windows の実装: `windows/Hanasu.Windows/Services/MeetingChannelRecorder.cs`（相手は WASAPI ループバック。DEC-MTG-100）
- 確かめ方: 実機で確かめる（システムオーディオ録音の許可が要る）。`--list-audio-devices` で機器の一覧

### REQ-MTG-003 録音中に、文字起こしをリアルタイムに出す（F3）
- 内容: 録音中は、自分／相手を区別した文字起こしをリアルタイムに表示する。
- 受け入れ条件: Mac 標準のエンジンで記録中、会議ノートに自分と相手の発言が順に出る。
- 出典: 初版の要件定義 F3（必須）
- 対象: Mac / Windows
- 実装の場所: `LiveTranscriptView`、`MeetingRecorder.receive`、`ChannelTranscriber`
- Windows の実装: なし（Windows 版の会議ではライブの文字起こしを出さない。食い違いを参照）
- 確かめ方: `--render-meeting-notes <フォルダ>` で記録中の画面を PNG にする。実際の会議は実機
- 食い違い（ユーザーの確認待ち）: 文字起こしのエンジンに Whisper / Gemini を選ぶと、記録中はライブの文字起こしを出さず、記録を止めたあとにまとめて文字起こしする（DEC-MTG-005、PR #17）。F3 は必須の要件だが、出さないのは実装したエージェントの判断。要件を「Mac 標準のときだけ」に絞るかを確かめる。Windows 版の会議は Whisper / Gemini しか選べない（DEC-MTG-101）ので、ライブの文字起こしはいつも出ない

### REQ-MTG-004 相手側の音声を話者分離する（F4）
- 内容: 記録を止めたあと、相手側の音声を話者分離し、「話者1」「話者2」…に分ける。
- 受け入れ条件: 相手が 2 人の会議で、相手の発言が話者1・話者2 に分かれる。
- 出典: 初版の要件定義 F4（必須）
- 対象: Mac / Windows
- 実装の場所: `FluidAudioDiarizer`、`MeetingProcessor.buildUtterances`
- Windows の実装: `windows/Hanasu.Diarization/SherpaSpeakerDiarizer.cs`、`windows/Hanasu.Core/Meetings/MeetingProcessor.cs`
- 確かめ方: `.build/debug/Hanasu --meeting-files me.wav others.wav`（`say` の声で作った架空の会議）

### REQ-MTG-005 話者ごとの発言を、時刻つきの文字起こしとして保存する（F5）
- 内容: 話者と時刻の付いた発言を、文字起こしとして保存する。
- 受け入れ条件: `transcript.md` に `[00:01:23] 話者1: …` の形で発言が並ぶ。
- 出典: 初版の要件定義 F5（必須）
- 対象: Mac / Windows
- 実装の場所: `Meeting.transcriptMarkdown`、`MeetingStore.save`
- Windows の実装: `windows/Hanasu.Core/Meetings/MeetingStore.cs`
- 確かめ方: `--meeting-files me.wav others.wav` の出力

### REQ-MTG-006 Gemini で議事録を作る（F6）
- 内容: Gemini で議事録（要約・決定事項・TODO）を作る。TODO は PR #13 から「アクションアイテム」として取り出す（REQ-MTG-018）。
- 受け入れ条件: 記録のあと `minutes.md` に、概要・決定事項・アクションアイテムを含む議事録ができる。
- 出典: 初版の要件定義 F6（必須）
- 対象: Mac / Windows
- 実装の場所: `MeetingProcessor.makeMinutes`、`MinutesPrompt`
- Windows の実装: `windows/Hanasu.Core/Meetings/MinutesTemplate.cs`（Mac 版と同じ文面）
- 確かめ方: `.build/debug/Hanasu --minutes-from-transcript <文字起こし>`（Gemini の認証が要る）

### REQ-MTG-007 記録した会議を一覧し、読める・コピーできる（F7）
- 内容: 会議ノートのウインドウで、記録した会議を一覧し、文字起こしと議事録を読める・コピーできる。
- 受け入れ条件: 会議ノートの左に会議の一覧が出て、選ぶと右に「議事録」「文字起こし」が出る。コピー（書き出し）ができる。
- 出典: 初版の要件定義 F7（必須）
- 対象: Mac / Windows
- 実装の場所: `MeetingWindowView`、`MeetingDetailView`
- Windows の実装: `windows/Hanasu.Windows/Views/MeetingWindow.xaml.cs`（書き出しは「Markdown をコピー」だけ）
- 確かめ方: `--render-minutes-ui <フォルダ> --meeting-json <json>` で画面を PNG にする

### REQ-MTG-008 話者名を、あとから付け替えられる（F8）
- 内容: 「話者1」を「田中さん」のように、あとから付け替えられる。
- 受け入れ条件: 会議ノートで話者名を変えると、文字起こしと議事録の表示がその名前になり、保存される。
- 出典: 初版の要件定義 F8（あると良い）
- 対象: Mac / Windows
- 実装の場所: `MeetingRecorder.renameSpeaker`、`Meeting.displayName`
- Windows の実装: `windows/Hanasu.Windows/Views/MeetingWindow.xaml.cs`
- 確かめ方: 実機で確かめる

### REQ-MTG-009 会議アプリがマイクを使い始めたら、記録するかを聞く（F9）
- 内容: 会議アプリがマイクを使い始めたら「会議を記録しますか？」と知らせる。自動では記録を始めない。
- 受け入れ条件: Zoom などがマイクを使い始めると提案が出て、「記録する」を押したときだけ記録が始まる。
- 出典: 初版の要件定義 F9（あると良い、フェーズ 2）。PR #14（10 個の改善案の 1 つ）で実装した
- 対象: Mac
- 実装の場所: `MeetingDetector`、`MeetingAutoDetect`、`MeetingSuggestionPanel`
- 確かめ方: `.build/debug/Hanasu --simulate-meeting-detection`、`--list-audio-processes`、`--render-meeting-suggestion out.png`

### REQ-MTG-010 音声ファイルを残すか、処理のあとに消すかを選べる（F10）
- 内容: 設定で、録音した音声ファイルを残すか、後処理のあとに消すかを選べる。
- 受け入れ条件: 「音声ファイルを残す」をオフにすると、後処理のあとに `me.m4a` / `others.m4a` が消える。
- 出典: 初版の要件定義 F10（あると良い）
- 対象: Mac / Windows
- 実装の場所: `MeetingRecorder.process`
- Windows の実装: `windows/Hanasu.Core/Meetings/MeetingPostProcessor.cs`
- 確かめ方: `--meeting-files me.wav others.wav -keepMeetingAudio NO`

### REQ-MTG-011 記録中にメモを書ける（F11）
- 内容: 記録中にメモを書ける。1 行ずつ、録音開始からの経過時間つきで保存する。
- 受け入れ条件: 記録中にメモ欄で Enter を押すと、時刻つきの行が並び、`meeting.json` と `notes.md` に残る。
- 出典: PR #10（10 個の改善案の 1 つ）
- 対象: Mac / Windows
- 実装の場所: `LiveNotesPanel`、`MeetingRecorder.addNote`
- Windows の実装: `windows/Hanasu.Core/Meetings/MeetingController.cs`、`windows/Hanasu.Windows/Views/MeetingWindow.xaml.cs`
- 確かめ方: `--render-meeting-notes <フォルダ>`、`--meeting-files me.wav others.wav --notes notes.txt`

### REQ-MTG-012 記録中に「ここ重要」の印を付けられる（F12）
- 内容: 記録中に、ボタンと設定で変えられるショートカットで「ここ重要」の印を付けられる。
- 受け入れ条件: 会議ツールを前面にしたまま `⌃⌥⌘ H` を押すと、その時刻に印が付く。
- 出典: PR #10
- 対象: Mac / Windows
- 実装の場所: `MeetingRecorder.addHighlight`、`MeetingHighlightHotKey`
- Windows の実装: `windows/Hanasu.Core/Meetings/MeetingController.cs`（ショートカットは DEC-MTG-110）
- 確かめ方: 実機で確かめる。印の反映は `--meeting-files … --notes notes.txt`

### REQ-MTG-013 議事録は、メモと印を優先して反映する。記録後にメモを直して作り直せる（F13）
- 内容: 議事録はメモと印を優先して反映する。記録後にメモを直して、議事録を作り直せる。
- 受け入れ条件: 印を付けた箇所が議事録の「重要とした箇所」にまとまり、メモにしかない内容も残る。「保存して議事録を作り直す」で議事録が変わる。
- 出典: PR #10
- 対象: Mac / Windows
- 実装の場所: `Meeting.notesForPrompt`、`Meeting.transcriptForPromptMarkingHighlights`、`MeetingRecorder.regenerateMinutes`、`MeetingNotesEditor`
- Windows の実装: `windows/Hanasu.Core/Meetings/MinutesTemplate.cs`、`windows/Hanasu.Windows/Views/MeetingWindow.xaml.cs`
- 確かめ方: `--meeting-files me.wav others.wav --notes notes.txt`

### REQ-MTG-014 文字起こしの字幕を、ほかのアプリの前面に出せる（F14）
- 内容: 記録中の文字起こしを、会議ツールなどほかのアプリの前面に字幕として出せる。
- 受け入れ条件: 字幕を出すと、ほかのアプリの前面に直近の発言が出て、記録が終わると閉じる。
- 出典: PR #10
- 対象: Mac
- 実装の場所: `MeetingCaptionPanel`、`MeetingCaptionView`
- 確かめ方: `--render-meeting-notes <フォルダ>`（字幕パネルも描く）

### REQ-MTG-015 過去の会議を横断して検索し、ヒットした位置に飛べる（F15）
- 内容: 過去の会議の文字起こしと議事録を横断して検索し、ヒットした発言・行の位置に飛べる。
- 受け入れ条件: 会議ノートの検索欄に語を入れると、ヒットした会議と箇所が並び、選ぶとその位置までスクロールする。
- 出典: PR #11
- 対象: Mac
- 実装の場所: `MeetingSearchIndex`、`MeetingSearchResultsList`
- 確かめ方: `.build/debug/Hanasu --search-meetings <語> --meetings-dir <フォルダ>`（`--write-sample-meetings` で架空の会議を作る）

### REQ-MTG-016 過去の会議について質問すると、根拠の会議を引用して答える（F16）
- 内容: 過去の会議について質問すると、関係する会議をもとに Gemini が答え、根拠の会議を引用する。
- 受け入れ条件: 「先週の定例で何が決まった？」に、先週の定例をもとに答え、引用した会議に印が付く。
- 出典: PR #11
- 対象: Mac
- 実装の場所: `MeetingAsk`、`MeetingAskView`
- 確かめ方: `.build/debug/Hanasu --ask-meetings "<質問>" --meetings-dir <フォルダ> --show-context`

### REQ-MTG-017 会議の種類に合わせて、議事録の型を選べる
- 内容: 議事録を、会議の種類に合わせた型（テンプレート）で作れる。記録の前に選ぶことも、あとから選び直して作り直すこともできる。
- 受け入れ条件: 型を「商談」にすると、顧客の課題・提案内容などの見出しで議事録ができる。
- 出典: PR #13
- 対象: Mac / Windows
- 実装の場所: `MinutesTemplate`、`MinutesTemplatePicker`、`MinutesTemplateMenu`
- Windows の実装: `windows/Hanasu.Core/Meetings/MinutesTemplate.cs`
- 確かめ方: `.build/debug/Hanasu --minutes-from-transcript sales.txt --template sales`

### REQ-MTG-018 アクションアイテムを、決まった形で取り出す
- 内容: 議事録のアクションアイテム（担当・内容・期限）を、Markdown とは別に構造化して取り出し、保存する。
- 受け入れ条件: `meeting.json` の `actionItems` に担当・内容・期限が入り、議事録には一覧として出る。
- 出典: PR #13
- 対象: Mac / Windows
- 実装の場所: `ActionItem`、`MinutesPrompt.parse`
- Windows の実装: `windows/Hanasu.Core/Meetings/MinutesTemplate.cs`
- 確かめ方: `--minutes-from-transcript sales.txt --template sales --save-json sales.json`

### REQ-MTG-019 議事録とアクションアイテムを書き出す
- 内容: 会議ノートの「書き出し」から、Markdown のコピー、Slack 向けのコピー、.md / .txt の保存、アクションアイテムのリマインダーへの登録ができる。
- 受け入れ条件: 「Slack 向けにコピー」で貼り付けると Slack で見出し・箇条書きが崩れない。選んだアクションアイテムがリマインダーに入る。
- 出典: PR #13
- 対象: Mac
- 実装の場所: `MeetingExport`、`ReminderExporter`、`MeetingExportMenu`
- 確かめ方: `.build/debug/Hanasu --export-minutes sales.json`。リマインダーは実機

### REQ-MTG-020 対応する会議ツール（非機能要件）
- 内容: Google Meet（ブラウザ）・Slack ハドル・Microsoft Teams に対応する。仕組み上、Zoom など Mac で音が鳴るものは全部対象。
- 受け入れ条件: どの会議ツールでも、同じ操作で記録できる（ツールごとの設定が要らない）。
- 出典: 初版の非機能要件「対応ツール」
- 対象: Mac / Windows
- 実装の場所: `SystemAudioTap`（アプリを限定せずに Mac 全体の音を録る）
- Windows の実装: `windows/Hanasu.Windows/Services/MeetingChannelRecorder.cs`（選んだ出力機器で鳴る音すべて）
- 確かめ方: 実機で、各会議ツールで確かめる

### REQ-MTG-021 会議の長さ（非機能要件）
- 内容: 2 時間までの会議で実用に耐えること。
- 受け入れ条件: 2 時間の会議を記録して、文字起こしと議事録ができる。
- 出典: 初版の非機能要件「会議の長さ」
- 対象: Mac / Windows
- 実装の場所: 特定の場所はない（録音・文字起こし・後処理の全体）
- Windows の実装: 特定の場所はない
- コードのタグ: 不要（全体の性質で、決めている 1 か所がない）
- 確かめ方: 実機で確かめる（まだ 2 時間の会議では確かめていない）

### REQ-MTG-022 処理時間（非機能要件）
- 内容: 1 時間の会議で、停止から議事録の完成まで数分以内。
- 受け入れ条件: 1 時間の会議で、停止から数分以内に議事録ができる。
- 出典: 初版の非機能要件「処理時間」
- 対象: Mac / Windows
- 実装の場所: 特定の場所はない（後処理の全体）
- Windows の実装: 特定の場所はない
- コードのタグ: 不要（全体の性質で、決めている 1 か所がない）
- 確かめ方: 実機で確かめる。41 秒の音声での処理時間は [verification/meeting.md](../verification/meeting.md) 2〜3

### REQ-MTG-023 音声認識と話者分離は Mac の上で行う（非機能要件・プライバシー）
- 内容: 音声認識と話者分離は Mac の上で行う。外部（Gemini）に送るのは文字起こしテキストだけ。
- 受け入れ条件: 既定の設定（Mac 標準のエンジン）で記録したとき、音声は Mac の外に出ない。
- 出典: 初版の非機能要件「プライバシー」
- 対象: Mac / Windows
- 実装の場所: `ChannelTranscriber`（オンデバイスの SpeechAnalyzer）、`FluidAudioDiarizer`（オンデバイス）
- Windows の実装: `windows/Hanasu.Whisper/WhisperBatchTranscriber.cs`（会議の既定）、`windows/Hanasu.Diarization/SherpaSpeakerDiarizer.cs`（どちらも PC の上で動く）
- 確かめ方: 実機で、通信先を確かめる
- 食い違い（ユーザーの確認待ち）: 会議の文字起こしのエンジンに Gemini を選ぶと、録った音声（自分と相手の声）を Gemini に送る（REQ-COM-001、DEC-MTG-008、PR #17）。エンジンに Gemini を選べることはユーザーの指定（2026-11-03）なので、この要件に「Gemini のエンジンを選んだときを除く」と足すかを確かめる。設定画面には、音声を Google に送ることを注意の印つきで出している（DEC-COM-033）Windows 版も、会議の文字起こしに Gemini を選ぶと音声を送る（既定の Whisper は PC の上で動く）

### REQ-MTG-024 会議中の負荷（非機能要件）
- 内容: 会議中に CPU を使いすぎて、会議ツールの音声が途切れないこと。
- 受け入れ条件: 記録中も会議ツールの音声が途切れない。
- 出典: 初版の非機能要件「負荷」
- 対象: Mac / Windows
- 実装の場所: 特定の場所はない（話者分離と議事録を記録のあとに回すこと、DEC-MTG-005 など）
- Windows の実装: 特定の場所はない
- コードのタグ: 不要（全体の性質で、決めている 1 か所がない）
- 確かめ方: 実機で確かめる

### REQ-MTG-025 保存先と形式（非機能要件）
- 内容: `~/Documents/Hanasu/Meetings/` の下に、会議ごとに 1 フォルダ。Markdown なので他のツールでも読める。
- 受け入れ条件: 記録した会議ごとにフォルダができ、`transcript.md`・`minutes.md` を他のエディタで読める。
- 出典: 初版の非機能要件「保存先」
- 対象: Mac / Windows
- 実装の場所: `MeetingStore`
- Windows の実装: `windows/Hanasu.Core/Meetings/MeetingStore.cs`（`ドキュメント\Hanasu\Meetings\`。保存先は設定で変えられる。DEC-MTG-108）
- 確かめ方: `--meeting-files me.wav others.wav` の出力先

### REQ-MTG-026 録音中であることを、メニューバーに常に表示する（運用上の注意）
- 内容: 録音は相手の同意を得てから行う前提で、アプリは録音中であることをメニューバーに常に表示する。
- 受け入れ条件: 会議を記録している間、メニューバーのアイコンが記録中の表示になり、メニューに経過時間が出る。
- 出典: 初版の「運用上の注意」
- 対象: Mac
- 実装の場所: `AppDelegate.updateIcon`、`AppDelegate.menuNeedsUpdate`
- 確かめ方: 実機で確かめる
- 食い違い（ユーザーの確認待ち）: 会議の記録中に音声入力を使うと、その間のアイコンは音声入力の状態（録音中なら赤い `mic.fill`）になり、会議の記録中の印（`record.circle.fill`）は音声入力が終わるまで出ない（DEC-DIC-017）。どちらも赤いが、「常に表示」と言えるかを確かめる

### REQ-MTG-030 会議ツールの画面・映像は記録しない（対象外）
- 内容: 会議ツールの画面・映像は記録しない。
- 受け入れ条件: 画面収録の許可を求めず、映像のファイルを作らない。
- 出典: 初版の「対象外（今回はやらない）」
- 対象: Mac / Windows
- 実装の場所: なし
- Windows の実装: なし
- コードのタグ: 不要（やらないことの要件）
- 確かめ方: 権限の一覧（[design/meeting.md](../design/meeting.md) 7）に画面収録がないこと

### REQ-MTG-031 会議ツールにボットで参加しない（対象外）
- 内容: 会議ツールへボットで参加しない。ボットでの記録は計画（[roadmap.md](../roadmap.md) FUT-203）。
- 受け入れ条件: 会議の参加者に Hanasu のボットが現れない。
- 出典: 初版の「対象外（今回はやらない）」
- 対象: Mac / Windows
- 実装の場所: なし
- Windows の実装: なし
- コードのタグ: 不要（やらないことの要件）
- 確かめ方: 該当する機能がないこと

### REQ-MTG-032 参加者の名前は自動では取らない（対象外）
- 内容: 会議ツールの参加者一覧を読んで名前を取ることはしない。話者名は推定（議事録の「話者についてのメモ」）と、手での付け替え（REQ-MTG-008）だけ。
- 受け入れ条件: 話者は「話者1」などのまま保存され、自動では名前に変わらない。
- 出典: 初版の「対象外（今回はやらない）」
- 対象: Mac / Windows
- 実装の場所: なし
- Windows の実装: なし
- コードのタグ: 不要（やらないことの要件）
- 確かめ方: 該当する機能がないこと

### REQ-MTG-033 複数台の Mac の録音は統合しない（対象外）
- 内容: 複数台の Mac で録った記録を 1 つにまとめることはしない。
- 受け入れ条件: 記録は Mac ごとに別の会議として保存される。
- 出典: 初版の「対象外（今回はやらない）」
- 対象: Mac / Windows
- 実装の場所: なし
- Windows の実装: なし
- コードのタグ: 不要（やらないことの要件）
- 確かめ方: 該当する機能がないこと

---

## 設計判断

### DEC-MTG-001 ボットではなく、自分の Mac で録る方式にする
- 決めたこと: 会議にボットを入れず、自分の Mac のマイクとシステム音声を録る（Granola と同じ方式 B）。
- 理由: Slack ハドルにはボットで参加する公開 API がなく、Meet・Teams もボットにはクラウド基盤と審査が要る。端末で録れば全ツールに同じ仕組みで対応でき、既存の権限・署名・Gemini の設定を使える。
- 決めた場面: 初版（a787da8）
- 関係する要件: REQ-MTG-002, REQ-MTG-020
- 対象: Mac
- 実装の場所: `MeetingRecorder.start`

### DEC-MTG-002 システム音声は Core Audio Process Tap で録る
- 決めたこと: `CATapDescription(stereoGlobalTapButExcludeProcesses: [自分])` で自分以外の音全体のタップを作り、非公開の集約デバイスに入れて IOProc で受け取る。
- 理由: 仮想オーディオデバイスはドライバーの導入と出力先の切り替えが要り、ScreenCaptureKit は画面収録の許可が要る。Process Tap は「システムオーディオ録音」の許可だけで、音を横取りせずに複製して受け取れる。
- 決めた場面: 初版（a787da8）
- 関係する要件: REQ-MTG-002, REQ-MTG-020
- 対象: Mac
- 実装の場所: `SystemAudioTap.start`

### DEC-MTG-003 タップの実際のサンプリングレートを測って合わせる
- 決めたこと: 集約デバイスの入力の形式（`kAudioDevicePropertyStreamFormat`）を使い、IOProc に届くフレーム数と経過時間から実際のレートを測って、形式と 10% 以上違えば測った値に合わせる。録音中にレートが変わったら読み直す。「Mac 全体の音」では主デバイスを内蔵スピーカーにする。
- 理由: Bluetooth イヤホンを使うと、タップが報告する 48kHz と実際に届く 16kHz がずれ、相手の音声が 3 分の 1 の長さになった（[verification/meeting.md](../verification/meeting.md) 4）。
- 決めた場面: 実機で録音されなかった問題の修正（2026-11-02）
- 関係する要件: REQ-MTG-002
- 対象: Mac
- 実装の場所: `SystemAudioTap.inputFormat`、`RateMeter`

### DEC-MTG-004 マイクは、機器の構成が変わったら作り直す
- 決めたこと: マイクは `AVAudioEngine` の入力ノードで録る。`AVAudioEngineConfigurationChange` を受けたら作り直し、入力の形式が変わったら変換器も作り直す。タップは `inputNode.inputFormat`（機器側の実際の形式）で付ける。
- 理由: タップを作ると Bluetooth イヤホンの接続モードが切り替わり、マイクが無音を受け取り続けた。機器を切り替えても `outputFormat` は前の機器のままだった。
- 決めた場面: 実機で録音されなかった問題の修正（2026-11-02）
- 関係する要件: REQ-MTG-002
- 対象: Mac
- 実装の場所: `MeetingRecorder.startMic`、`MeetingRecorder.makeMicEngine`

### DEC-MTG-005 Mac 標準ではチャンネルごとにライブで文字起こしし、Whisper / Gemini では記録のあとにまとめて行う
- 決めたこと: Mac 標準は、マイク用とシステム音声用に 2 つの SpeechAnalyzer（SpeechTranscriber、語ごとの時刻つき）を並べてライブで文字起こしする。Whisper / Gemini では記録中は文字起こしをせず、チャンネルごとに 16 kHz モノラルの m4a に書き出すだけにし（`ChannelTranscriber(live: false)`）、会議ノートと字幕に「記録を止めたあとに Whisper で文字起こしします」と出す。
- 理由: SpeechTranscriber は音声入力の検証で発話を落とさなかった。Whisper を数秒ごとに回すと会議中の CPU・電池の負担が大きく、Gemini で細かく送ると呼び出しの数と費用がかさむ。
- 決めた場面: 初版（a787da8）。Whisper / Gemini の分は PR #17
- 関係する要件: REQ-MTG-003, REQ-MTG-024, REQ-COM-001
- 対象: Mac
- 実装の場所: `ChannelTranscriber`

### DEC-MTG-006 2 つのチャンネルの時刻を、録音開始を 0 秒とする共通の時間軸にそろえる
- 決めたこと: `AnalyzerInput(buffer:bufferStartTime:)` に、チャンネルの開始のずれと累積サンプル数から計算した時刻を渡す。記録のあとの文字起こしでも、そのチャンネルの音声が録音開始から何秒後に始まったか（`audioStartOffset`）を足す。
- 理由: 話者分離の結果や、もう一方のチャンネルと時刻で突き合わせるため。
- 決めた場面: 初版（a787da8）。記録のあとの分は PR #17
- 関係する要件: REQ-MTG-005
- 対象: Mac
- 実装の場所: `ChannelTranscriber.append`、`MeetingBatchTranscription.phrases`

### DEC-MTG-007 エンジンは記録を始めたときの設定で決め、始める前に準備を確かめる
- 決めたこと: 記録中に設定を変えても混ざらないよう、エンジンは記録の開始時に決める。Whisper はモデルがあるか、Gemini は認証情報があるかを確かめ、なければ記録を始めずに理由を出す。Whisper / Gemini では音声認識の権限を求めない。
- 理由: 記録が終わってから文字起こしできないと分かるのを避ける。
- 決めた場面: PR #17
- 関係する要件: REQ-COM-001
- 対象: Mac
- 実装の場所: `MeetingRecorder.checkReady`

### DEC-MTG-008 Gemini で会議を文字起こしするときは、5 分ごとに区切って送る
- 決めたこと: 目安の前 15 秒のうちいちばん静かなところで 5 分ごとに区切り、最大 3 つを並行して送る。音声は FLAC（16 kHz モノラル）、無音だけの区切りは送らない。応答は JSON（`responseSchema` で `segments: [{start, end, text}]`、時刻は区切りの先頭を 0 とした `"MM:SS.s"`）で受け、区切りの開始時刻を足す。時刻は区切りの長さに収め、終わりが始まりより前なら直す。Gemini は区間ごとの時刻だけなので、区間を 1 語として扱う。
- 理由: inline data の上限（20 MB）に収める。区切りを 30 秒にすると先頭が無音の区切りで発話を丸ごと落とした。語の途中で切らない。
- 決めた場面: PR #17
- 関係する要件: REQ-COM-001, REQ-MTG-005
- 対象: Mac
- 実装の場所: `GeminiTranscriber.transcribeSegments`、`GeminiTranscriber.parseSegments`、`TranscriptionAudio.chunkStarts`

### DEC-MTG-009 文字起こしに失敗したチャンネルがあれば、音声を残す
- 決めたこと: 音声を残さない設定でも、記録のあとの文字起こしに失敗したチャンネルがあれば音声ファイルを消さず、会議のエラーに「音声ファイルは残しています」と書く。消すのは後処理の最後（文字起こし・話者分離・議事録のあと）。
- 理由: あとで文字起こしし直せるようにする。
- 決めた場面: PR #17
- 関係する要件: REQ-MTG-010
- 対象: Mac
- 実装の場所: `MeetingRecorder.process`、`MeetingRecorder.transcribeRecordedAudio`

### DEC-MTG-010 話者分離は FluidAudio で行い、失敗しても処理を続ける
- 決めたこと: FluidAudio（pyannote speaker-diarization-community-1 の CoreML 版）を `0.17.7` に固定し、`traits: []` で不要なテキスト正規化のバイナリをリンクしない。相手側の音声に、会議のあとでまとめてかける。差し替えられる `SpeakerDiarizer` にし、失敗したら相手を 1 人として続ける。モデルは初回に Hugging Face から取り、以後はキャッシュを使う。
- 理由: 音声を Mac の外に出さず、言語に依存せず、会議全体を 1 回で処理するので話者番号が最後まで一貫する。Gemini の話者分離は 1 回 30 分までで、分割ごとに話者番号がずれる。利用者の承認を得て組み込んだ（2026-11-02）。公開直後の版は避けた。
- 決めた場面: 初版（a787da8）
- 関係する要件: REQ-MTG-004, REQ-MTG-023
- 対象: Mac
- 実装の場所: `FluidAudioDiarizer`、`SpeakerDiarizer`

### DEC-MTG-011 マイク側も話者を分けられる（既定はオフ）
- 決めたこと: 設定「マイク側も話者を分ける」（既定はオフ）をオンにすると、マイクの録音にも話者分離をかけ、話した時間がいちばん長い人を「自分」、ほかを登場順に「同席者1」「同席者2」…にする。議事録のプロンプトに同席者の説明を足す。
- 理由: 会議室から数人で 1 つのマイクを使う場合に備える。1 人で参加するときは、自分の声が 2 人に分かれる誤判定を避けるためオフのままにする。
- 決めた場面: 初版（a787da8）
- 関係する要件: REQ-MTG-004
- 対象: Mac
- 実装の場所: `MeetingProcessor.labelMicSpeakers`

### DEC-MTG-012 話者は、語ごとの時刻で割り当てる
- 決めたこと: 話者分離の区間と相手側の語ごとの時刻を突き合わせ、語の時刻には「語の終わり寄り 0.4 秒」の中央を使う。区間のすき間にある語は、前の区間の終わりから 0.3 秒以上あいて始まれば次の話者、そうでなければ前の話者にする。同じ話者が続く語を 1 発言にまとめ、自分の発言と時刻順に並べ、話者番号は登場順に付け直す。
- 理由: 1 つの認識結果に複数の話者が混ざっていても分けられる。無音のあとの最初の語には無音の分まで長い時間が付く。話者分離は話し始めの検出が 1 秒前後遅れることがある（[verification/meeting.md](../verification/meeting.md) 3）。
- 決めた場面: 初版（a787da8）
- 関係する要件: REQ-MTG-004, REQ-MTG-005
- 対象: Mac
- 実装の場所: `MeetingProcessor.split`、`MeetingProcessor.speaker`、`MeetingProcessor.renumberSpeakers`

### DEC-MTG-013 スピーカーから回り込んだ相手の声を、自分の発言から除く
- 決めたこと: 相手側に同じ時間帯・ほぼ同じ文字列の発言がある「自分」の発言を取り除く。イヤホンの利用を設定画面とドキュメントで勧める。
- 理由: イヤホンを使わないと、相手の声がマイクにも入り、自分の発言として二重に記録される。回り込みがあると自分の発言の認識そのものが崩れるので、イヤホンを前提にする（エコーキャンセルは [roadmap.md](../roadmap.md) FUT-202）。
- 決めた場面: 初版（a787da8）
- 関係する要件: REQ-MTG-005
- 対象: Mac
- 実装の場所: `MeetingProcessor.removeEcho`

### DEC-MTG-014 議事録のモデルと、出力の構成
- 決めたこと: 議事録のモデルの初期値は `gemini-3.8-flash`。音声入力と同じ `GeminiClient` と認証を使う。出力は概要・話題ごとの要点・決定事項・アクションアイテム・話者名の推定（推定であることを明記し、自動では書き換えない）。
- 理由: 音声入力と違って待ち時間が問題になりにくいので、要約の質を優先する。1 時間の文字起こし（数万文字）も入力の上限に収まる。
- 決めた場面: 初版（a787da8）
- 関係する要件: REQ-MTG-006
- 対象: Mac
- 実装の場所: `AppSettings`（`meetingMinutesModel` の初期値）、`MinutesPrompt.systemInstruction`

### DEC-MTG-015 議事録を作るかを、設定で切り替えられる（既定はオン）
- 決めたこと: 設定「記録後に Gemini で議事録を作る」（既定はオン）をオフにすると、文字起こしまでで止め、議事録は作らない。
- 理由: 初版のコードにあり、文書に書かれていなかった振る舞い。外部に送りたくない会議のために残す、と読める。今回、暗黙の振る舞いから設計判断に格上げして記録した。
- 決めた場面: 初版（a787da8）のコード。記録はこの PR
- 関係する要件: REQ-MTG-006, REQ-MTG-023
- 対象: Mac
- 実装の場所: `MeetingRecorder.process`

### DEC-MTG-016 音声ファイルは、既定では残す
- 決めたこと: 「音声ファイル（me.m4a / others.m4a）を残す」の初期値はオン。
- 理由: 初版のコードの初期値。文書には「設定で処理後に削除可」とだけあり、既定が書かれていなかった。あとで文字起こしし直したり、聞き直したりできる。今回、暗黙の振る舞いから設計判断に格上げして記録した。
- 決めた場面: 初版（a787da8）のコード。記録はこの PR
- 関係する要件: REQ-MTG-010
- 対象: Mac
- 実装の場所: `AppSettings`（`keepMeetingAudio` の初期値）

### DEC-MTG-017 会議ごとのフォルダの中身
- 決めたこと: `~/Documents/Hanasu/Meetings/<日付 時刻 タイトル>/` に `meeting.json`（メタデータ・話者名の対応表・発言・議事録の型・アクションアイテム・メモ）、`transcript.md`、`minutes.md`、`notes.md`（メモがあるときだけ）、`me.m4a`・`others.m4a`（AAC 16kHz モノラル）を置く。
- 理由: Markdown なので他のツールでも読める（REQ-MTG-025）。
- 決めた場面: 初版（a787da8）。項目は PR #10、#13 で足した
- 関係する要件: REQ-MTG-005, REQ-MTG-025
- 対象: Mac
- 実装の場所: `MeetingStore.save`、`Meeting`

### DEC-MTG-018 途中で落ちた会議は、起動時に「失敗」にする
- 決めたこと: 起動時に、アプリの終了などで「記録中」「処理中」のまま残った会議を「失敗」にする。エラーのときも、それまでの録音・文字起こしは保存する。
- 理由: 一覧に「記録中」のまま残り続けないようにする。
- 決めた場面: 実機で録音されなかった問題の修正（2026-11-02）
- 関係する要件: REQ-MTG-007
- 対象: Mac
- 実装の場所: `MeetingStore.markInterruptedMeetings`

### DEC-MTG-019 録音するスピーカーとマイクを選べる
- 決めたこと: 設定「会議」→「録音するスピーカー」（初期値は Mac 全体の音。特定の出力機器だけもタップできる）と「録音するマイク」（初期値はシステムの設定）。
- 理由: 実機の問題の調べで、機器を指定したい場面があった。
- 決めた場面: 実機で録音されなかった問題の修正（2026-11-02）
- 関係する要件: REQ-MTG-002
- 対象: Mac
- 実装の場所: `MeetingDevicePickers`、`AudioDevices`

### DEC-MTG-020 記録中に音量を出し、音が入らないチャンネルを知らせる
- 決めたこと: 記録中の画面に「自分」「相手」の音量メーターを出し、始めてから 10 秒たっても一度も音が入らないチャンネルには警告を出す。
- 理由: 実機で何も録れていなかったことに、記録のあとまで気づけなかった。
- 決めた場面: 実機で録音されなかった問題の修正（2026-11-02）
- 関係する要件: REQ-MTG-002
- 対象: Mac
- 実装の場所: `MeetingRecorder.updateLevels`

### DEC-MTG-021 会議の記録の既定のショートカットは ⌃⌥⌘ M
- 決めたこと: 記録の開始・停止の初期値は `⌃⌥⌘ M`。設定の「会議」タブで変えられる。
- 理由: ほかのアプリと重なりにくい修飾キーの組にした。
- 決めた場面: 初版（a787da8）
- 関係する要件: REQ-MTG-001
- 対象: Mac
- 実装の場所: `HotKeyCombo.defaultMeeting`

### DEC-MTG-030 会議の検出は、リスナーを基本にし、マイクが使われている間だけ読み直す
- 決めたこと: Core Audio のプロセス一覧・機器一覧・会議アプリのプロセスの `IsRunning`・入力機器の `IsRunningSomewhere` にリスナーを付け、入力機器が使われている間だけ 3 秒おきに会議アプリの `IsRunningInput` を読み直す。
- 理由: macOS 26 では `IsRunningInput` の変化がリスナーに届かず、すでに音を鳴らしているブラウザがマイクを使い始めても通知が来なかった。マイクを誰も使っていない間はタイマーも動かさないので、待っている間の CPU 使用はほぼ 0。
- 決めた場面: PR #14
- 関係する要件: REQ-MTG-009
- 対象: Mac
- 実装の場所: `MeetingDetector`

### DEC-MTG-031 会議アプリの見分け方
- 決めたこと: bundle ID の先頭で見分ける（Zoom・Teams・Slack・Webex・FaceTime、ブラウザは Chrome・Arc・Edge・Safari）。ヘルパーでマイクを使うアプリは、`proc_pidpath` からいちばん外側の `.app` の bundle ID でも見分ける。ブラウザはタブの URL を読まず「ブラウザの会議（Google Meet など）かもしれません」と提案する。Hanasu 自身は PID で除く。
- 理由: Chrome・Slack・Teams はマイクをヘルパーで使う。URL を読むには別の許可が要る。
- 決めた場面: PR #14
- 関係する要件: REQ-MTG-009
- 対象: Mac
- 実装の場所: `MeetingApp`、`AudioProcesses.appBundleID`

### DEC-MTG-032 提案のタイミング
- 決めたこと: マイクを使い始めて 3 秒たったら開始の提案を出す。「今回はしない」ならマイクを止めて 60 秒たつまで聞かない。記録中に会議アプリがすべてマイクを止めて 15 秒たったら停止の提案を出す。「続ける」なら、またマイクを使ってから止めるまで聞かない。記録中・準備中・処理中は開始の提案を出さず、記録を終えた時点でまだマイクを使っているアプリにも聞かない。返事がないまま 2 分で閉じる。
- 理由: 一瞬だけマイクを確かめるアプリ、ミュートでマイクを止めるアプリ、機器の切り替えで何度も聞かないようにする。
- 決めた場面: PR #14
- 関係する要件: REQ-MTG-009
- 対象: Mac
- 実装の場所: `MeetingAutoDetect.Timing`、`MeetingAutoDetect.evaluate`

### DEC-MTG-033 提案は、通知センターではなく前面に出ないパネルで出す
- 決めたこと: 画面の右上に `nonactivatingPanel` のパネルを出し（全画面アプリの上にも出る）、1 回のクリックで押せるボタンにする。効果音の設定がオンなら `Glass` を鳴らす。
- 理由: 通知の許可が要らず、通知を切っている人や集中モードの人にも出て、CLI で見た目を確かめられる。会議アプリのフォーカスを奪わない。
- 決めた場面: PR #14
- 関係する要件: REQ-MTG-009
- 対象: Mac
- 実装の場所: `MeetingSuggestionPanel`

### DEC-MTG-034 会議の自動検出は、既定でオンにする
- 決めたこと: 「会議が始まったら記録を提案する」は既定でオン。対象のアプリ（会議アプリ 5 つ、ブラウザ 4 つ）は 1 つずつ外せ、保存するのは「外したアプリ」にする。
- 理由: 提案するだけで勝手に録音はしない。目的は記録の始め忘れを防ぐことで、既定がオフだと気づかれず役に立たない。待っている間の負荷がほぼない。あとで対象を足したときは既定でオンになる。
- 決めた場面: PR #14
- 関係する要件: REQ-MTG-009
- 対象: Mac
- 実装の場所: `MeetingDetectionSettings`

### DEC-MTG-040 メモの時刻は、書き始めた時刻にする
- 決めたこと: メモの行の時刻は、Enter を押した時刻ではなく、その行を書き始めた時刻にする。
- 理由: 聞いてから書き終えるまでの遅れで、時刻が実際の発言より後ろにずれるのを防ぐ。
- 決めた場面: PR #10
- 関係する要件: REQ-MTG-011
- 対象: Mac
- 実装の場所: `LiveNotesPanel`

### DEC-MTG-041 印の強調範囲は 30 秒前〜15 秒後で、アプリの側で決める
- 決めたこと: 文字起こしのうち、印の 30 秒前〜15 秒後にかかる発言の行頭に `★` を付けて Gemini に渡す。
- 理由: 印は大事な発言を聞いてから押すので前を長めにとる。時刻の計算をモデルに頼ると外れやすい。
- 決めた場面: PR #10
- 関係する要件: REQ-MTG-013
- 対象: Mac
- 実装の場所: `Meeting.isNearHighlight`

### DEC-MTG-042 「ここ重要」のショートカットは、記録中だけ登録する
- 決めたこと: 初期値は `⌃⌥⌘ H`（設定で変更・無効化できる）。記録中だけ登録し、押すと効果音（Morse）が鳴る。メモ欄に書きかけの文があれば、その文を印の説明にする。
- 理由: ふだんはほかのアプリのキーを奪わず、会議ツールを前面にしたまま印を付けられる。何が重要かを一言添えられる。
- 決めた場面: PR #10
- 関係する要件: REQ-MTG-012
- 対象: Mac
- 実装の場所: `MeetingHighlightHotKey`、`LiveNotesPanel`

### DEC-MTG-043 メモは meeting.json に入れ、足すたびに保存する
- 決めたこと: メモと印は `Meeting.notes`（省略可）として `meeting.json` に入れ、`notes.md` も書き出す。記録中に足すたびに保存する。
- 理由: 既存の保存形式に合わせ、省略可にして古い会議も読めるようにする。アプリが落ちてもメモが残る。
- 決めた場面: PR #10
- 関係する要件: REQ-MTG-011, REQ-MTG-012
- 対象: Mac
- 実装の場所: `MeetingRecorder.appendNote`、`Meeting.notesMarkdown`

### DEC-MTG-044 メモはテキストの形式で編集する
- 決めたこと: 1 行 1 件で、`[12:34] 内容`（メモ）、`[12:40] ★ 説明`（印）、時刻なしの行（記録後に足したメモ）。会議ノートの「メモ」タブ・`notes.md`・CLI の `--notes` で同じ形式を使う。
- 理由: 行の追加・削除・時刻の修正がまとめてできる。
- 決めた場面: PR #10
- 関係する要件: REQ-MTG-013
- 対象: Mac
- 実装の場所: `MeetingNote.text`、`MeetingNote.parse`

### DEC-MTG-045 メモも印もない会議の議事録は、今までと同じにする
- 決めたこと: 指示と入力を足すのは、メモか印があるときだけ。あるときは `<user_notes>` を足し、メモの点を優先する・メモにしかない情報も「（メモより）」と添えて残す・★ の話題は詳しめに・印があれば「## 重要とした箇所」を概要の次に置く、と指示する。
- 理由: メモを使わない人の議事録を変えない。
- 決めた場面: PR #10
- 関係する要件: REQ-MTG-013
- 対象: Mac
- 実装の場所: `Meeting.notesForPrompt`

### DEC-MTG-046 字幕は、記録中の画面と同じデータを前面のパネルに出す
- 決めたこと: 確定した発言と途中結果を、`.floating` の `NSPanel`（アプリをアクティブにしない）に直近 2 発言だけ出し、「ここ重要」ボタンも置く。記録が終わると閉じる。
- 理由: 文字起こしの仕組みに手を入れずに作れて、手間が小さかった。
- 決めた場面: PR #10
- 関係する要件: REQ-MTG-014
- 対象: Mac
- 実装の場所: `MeetingCaptionPanel`

### DEC-MTG-050 検索の索引は、メモリ上の文字 2-gram の転置索引にする
- 決めたこと: 隣り合う 2 文字ごとに、それを含む箇所の番号を持つ。候補がいちばん少ない 2-gram から候補を取り、最後に本当に含むかを確かめる。1 文字の語は全件を順に調べる。索引はファイルに保存せず、会議全体のハッシュを比べて変わった会議の分だけ作り直す（バックグラウンドの actor）。
- 理由: 日本語は語の区切りがない。全件を走査すると 1 回 0.5 秒かかり、打つたびに引っかかる。会議はもともと全部メモリに読んでいる。保存すると、ほかのツールで会議のファイルを直したときに索引とずれる。
- 決めた場面: PR #11
- 関係する要件: REQ-MTG-015
- 対象: Mac
- 実装の場所: `MeetingSearchIndex`

### DEC-MTG-051 検索の決まり
- 決めたこと: 対象はタイトル・議事録（行ごと）・文字起こし（発言ごと）。話者名は対象にしない。空白区切りは AND（同じ箇所に全部の語）。大文字小文字、全角半角は無視し、ひらがな・カタカナ・濁点の有無は区別する。1 つの会議から出す箇所は 20 件まで。`Esc` で検索をやめる。
- 理由: 話者名を対象にすると、その人の全発言がヒットする。「ガ」と「カ」を同じにすると誤ったヒットが多い。
- 決めた場面: PR #11
- 関係する要件: REQ-MTG-015
- 対象: Mac
- 実装の場所: `MeetingSearchIndex.search`、`MeetingSearchIndex.fold`

### DEC-MTG-052 質問から検索語を取り出し、期間で絞る
- 決めたこと: `NLTokenizer` で語に分け、ひらがなを含む語・1 文字の語・「会議」「先週」などの言い回しを除き、続けて出てくる語はつなげた語も使う。ヒットした会議を先に、足りなければ直近の会議を足す。「今日」「先週」「11/2」などがあればその期間に絞る（週は月曜始まり。会議がなければ絞らない）。
- 理由: Gemini に検索語を作らせると往復が 1 回増える。
- 決めた場面: PR #11
- 関係する要件: REQ-MTG-016
- 対象: Mac
- 実装の場所: `MeetingAsk.keywords`、`MeetingAsk.period`、`MeetingAsk.gatherContext`

### DEC-MTG-053 質問で渡す量の上限
- 決めたこと: 会議 8 件・本文の合計 15 万文字まで。議事録があれば議事録とヒットした発言の前後 2 発言ずつ（6,000 文字まで）、なければ文字起こし（4 万文字まで）。モデルは `meetingMinutesModel`。設定項目は増やさない（CLI の `--limit` で会議数を変えられる）。
- 理由: 入力を抑えて答えを速くする。共有の設定ファイルへの変更を避けた。
- 決めた場面: PR #11
- 関係する要件: REQ-MTG-016
- 対象: Mac
- 実装の場所: `MeetingAsk.Options`、`MeetingAsk.material`

### DEC-MTG-054 答えには根拠の会議を引用させ、記録の中の指示に従わせない
- 決めたこと: 根拠の会議を文中で「［M1: 2026/11/02 定例］」の形で引用させ、最後に「## 根拠」を付けさせる。記録にないことは「記録からは分かりません」と答えさせる。会議の記録は `<meeting>` で囲み、中の指示に従わないよう指示する。
- 理由: 答えを確かめられるようにし、作り話とプロンプトインジェクションを防ぐ。
- 決めた場面: PR #11
- 関係する要件: REQ-MTG-016
- 対象: Mac
- 実装の場所: `MeetingAsk.ask`、`MeetingAsk.cited`

### DEC-MTG-060 議事録の型は 6 つ
- 決めたこと: 自動（初期値）・定例・1on1・商談・ブレスト・カスタム。どの型でも最後に「アクションアイテム」（商談は「次のアクション」、ブレストは「次のステップ」）と「話者についてのメモ」を付ける。カスタムはユーザーの指示を `<user_template>` で囲んでシステム指示に入れる。
- 理由: Granola のテンプレートにならい、よくある会議の種類を揃えた。自動は従来の議事録と同じ。
- 決めた場面: PR #13
- 関係する要件: REQ-MTG-017
- 対象: Mac
- 実装の場所: `MinutesTemplate`

### DEC-MTG-061 型は記録の開始時に会議へ記録し、あとから選び直せる
- 決めたこと: 記録を始める前に会議ノートの左下で選び、開始時に `meeting.json` に記録する（記録中は変えられない）。あとから「型: 〇〇」で選び直すと、確認のあと議事録を作り直し、失敗したら型も議事録も元のまま。選んだ型は UserDefaults に置き、設定画面には出さない。
- 理由: 録音機器の選択欄と同じ扱いにする。共有の設定ファイルへの変更を避けた。
- 決めた場面: PR #13
- 関係する要件: REQ-MTG-017
- 対象: Mac
- 実装の場所: `MinutesTemplateStore`、`MeetingRecorder.regenerateMinutes`

### DEC-MTG-062 アクションアイテムは、議事録の末尾の JSON で受け取る
- 決めたこと: 本文の「## アクションアイテム」には目印 `{{ACTION_ITEMS}}` だけを書かせ、Markdown のあとに `<action_items>` で囲んだ JSON（`owner`・`task`・`due`・`due_note`）を出させる。アプリが目印を一覧に置き換え、`meeting.json` の `actionItems` に保存する。JSON モード（`responseSchema`）は使わない。
  - `<action_items>` がなく、本文の中に JSON の配列（`[{` から `}]` まで）があって読めれば、それをアクションアイテムとし、本文のその場所を一覧に置き換える。
- 理由: Markdown と構造化データを 1 回の呼び出しで受け取れ、共有の `GeminiClient` を変えずに済む。一覧をアプリが書くので、議事録と構造化データが食い違わない。小さいモデル（ローカル。REQ-COM-030）は、目印と `<action_items>` を使わずに「## アクションアイテム」の下へ JSON をそのまま書くことがある（Gemma 4 E4B で確かめた）ので、その形も読む。
- 決めた場面: PR #13。本文の中の JSON を読むのは、ローカル LLM に対応した PR
- 関係する要件: REQ-MTG-018
- 対象: Mac / Windows
- 実装の場所: `MinutesPrompt.parse`、`MinutesPrompt.inlineItems`、`MinutesPrompt.decodeItems`
- Windows の実装: `windows/Hanasu.Core/Meetings/MinutesTemplate.cs`（`MinutesPrompt.Parse`・`InlineItems`）

### DEC-MTG-063 期限は、日付と言い方の 2 つで持つ
- 決めたこと: 会議の日時を基準に日付に直せるものは `due`（YYYY-MM-DD）、話された言い方は `due_note`（「来週中」など）に入れる。
- 理由: 期限付きのリマインダーにできるのは日付があるときだけ。言い方も残しておく。
- 決めた場面: PR #13
- 関係する要件: REQ-MTG-018
- 対象: Mac
- 実装の場所: `ActionItem`

### DEC-MTG-064 JSON が壊れていたら、議事録のチェックボックスの行から読む
- 決めたこと: JSON が読めないときと、この機能より前の議事録（「## TODO」の行）は、チェックボックスの行から読み取る。
- 理由: 古い会議もリマインダーに登録できるようにする。
- 決めた場面: PR #13
- 関係する要件: REQ-MTG-018
- 対象: Mac
- 実装の場所: `ActionItem.parse`

### DEC-MTG-065 Slack 向けのコピーの変換
- 決めたこと: タイトルと日時を先頭に置き、「話者についてのメモ」を除く。見出し → `*太字*`、箇条書き → `•`、チェックボックス → `☐`、リンク → `<url|text>`。日本語の文中では太字の前後に空白を入れる。`&` `<` `>` はエスケープしない。斜体は記号を外すだけ。
- 理由: 貼り付けて送る前提。推測の内部メモは共有しない。エスケープは API 用で、貼り付けると文字のまま出る。
- 決めた場面: PR #13
- 関係する要件: REQ-MTG-019
- 対象: Mac
- 実装の場所: `MeetingExport.slack`、`MeetingExport.slackInline`

### DEC-MTG-066 保存とコピーは、表示中のタブが対象
- 決めたこと: Markdown のコピーと .md / .txt の保存は、表示中のタブ（議事録か文字起こし）が対象。.txt は見出しを【】、箇条書きを「・」、チェックボックスを「□」にし、太字などの記号を外す。Slack 向けとリマインダーは議事録だけ。
- 理由: 従来の「コピー」ボタンと同じ動きにする。
- 決めた場面: PR #13
- 関係する要件: REQ-MTG-019, REQ-MTG-007
- 対象: Mac
- 実装の場所: `MeetingExport.plainText`、`MeetingExportMenu`

### DEC-MTG-067 リマインダーへの登録
- 決めたこと: 権限（フルアクセス）は「登録」を押したときに初めて求める。初期の選択は、まだ登録していない「自分」の担当か担当が決まっていないもの。タイトルはやること、メモに担当・期限の言い方・会議名と日時。`due` があれば終日の期限を付ける。登録したら `reminderID` を保存して「登録済み」と出す。
- 理由: シートを開いただけで権限を求めない。ほかの人の担当は自分で選べば登録できる。二重登録を避ける。
- 決めた場面: PR #13
- 関係する要件: REQ-MTG-019
- 対象: Mac
- 実装の場所: `ReminderExporter`、`ReminderExportSheet`

### DEC-MTG-100 Windows 版の相手の音は、WASAPI ループバックで録る
- 決めたこと: 相手の音は NAudio の `WasapiLoopbackCapture` で、会議ノートで選んだ出力の機器で鳴る音すべてを録る。Hanasu 自身の音を除く仕組みがないので、会議の開始・停止・印では効果音を鳴らさない。
- 理由: Mac 版の Process Tap（DEC-MTG-002）にあたる、ドライバーの要らない方法。効果音を鳴らすとループバックに入る。
- 決めた場面: PR #19
- 関係する要件: REQ-MTG-002, REQ-MTG-020
- 対象: Windows
- 実装の場所: `windows/Hanasu.Windows/Services/MeetingChannelRecorder.cs`

### DEC-MTG-101 Windows 版の会議では、Windows 標準のエンジンを選べない（既定は Whisper）
- 決めたこと: 会議の文字起こしは Whisper（既定）か Gemini。古い設定で Windows 標準になっていたら Whisper に直す。記録中のライブの文字起こしは出さず、「止めたあとに Whisper で行います」と出す。Whisper のモデルは音声入力と共通。始める前に、Whisper はモデルがあるか、Gemini は認証情報があるかを確かめる。
- 理由: Windows 標準の `SpeechRecognizer` は既定のマイクからしか聞けず、ループバックで録った相手の音を渡せない。「自分だけ Windows 標準・相手は Whisper」は、結局 Whisper のモデルが要るうえ、チャンネルで質と時刻の精度がそろわず、選んだマイクも使えないので採らなかった。ライブを出さないのは Mac 版で Whisper / Gemini を選んだときと同じ理由（DEC-MTG-005）。ユーザーの指定（REQ-COM-001、REQ-COM-002）と合わないので、そちらに食い違いとして書いた。
- 決めた場面: PR #19
- 関係する要件: REQ-COM-001, REQ-COM-002, REQ-MTG-003
- 対象: Windows
- 実装の場所: `windows/Hanasu.Core/Meetings/MeetingController.cs`、`windows/Hanasu.Core/Settings/AppSettings.cs`

### DEC-MTG-102 Windows 版の会議の音声は、WAV にストリームで書く
- 決めたこと: チャンネルごとに 16 kHz・モノラル・16 bit の WAV（`me.wav` / `others.wav`）に書きながら録り、ヘッダーの長さは 5 秒ごとに書き直す。
- 理由: 長い会議でもメモリに溜めない。Windows で AAC を書くには Media Foundation が要る。アプリが落ちても途中までの音声を読める。
- 決めた場面: PR #19
- 関係する要件: REQ-MTG-002, REQ-MTG-010
- 対象: Windows
- 実装の場所: `windows/Hanasu.Core/Audio/WavStreamWriter.cs`、`windows/Hanasu.Windows/Services/MeetingChannelRecorder.cs`

### DEC-MTG-103 Windows 版の 2 つのチャンネルの時刻合わせ
- 決めたこと: チャンネルごとに「最初の音が録音開始から何秒後に届いたか」を `meeting.json` の `audioStartOffsets` に残し、文字起こしの時刻に足す。ループバックは PC が無音の間データを渡さないので、届いた時刻と書いた長さの差が 0.25 秒より開いたら、その分の無音を足す（`ChannelTimeline`）。無音のところにかかった文字起こしの時刻は、声のあるところへ寄せる。
- 理由: Mac 版の DEC-MTG-006 と同じく共通の時間軸にそろえる。
- 決めた場面: PR #19
- 関係する要件: REQ-MTG-005
- 対象: Windows
- 実装の場所: `windows/Hanasu.Windows/Services/MeetingChannelRecorder.cs`、`windows/Hanasu.Core/Meetings/MeetingTranscription.cs`

### DEC-MTG-104 Windows 版の話者分離は sherpa-onnx で行う
- 決めたこと: sherpa-onnx（NuGet の 1.13.8、Apache-2.0）の `OfflineSpeakerDiarization` で、相手側を会議全体で 1 回に分ける。話者の数は決めず、しきい値 0.5 でまとめる。モデル（pyannote segmentation-3.0 の ONNX 版と 3D-Speaker の CAM++、約 34 MB）は初めて使うときに `%LOCALAPPDATA%\Hanasu\Models\diarization` にダウンロードする。失敗したら相手を「相手」1 人にまとめて続け、タスクトレイで知らせる。設定「相手側の話者を分ける」は既定でオン。マイク側の話者分離は作っていない。
- 理由: FluidAudio（DEC-MTG-010）は Apple 専用。sherpa-onnx は C# の API があり Mac でも動くので CLI で確かめられた。公開から 7 週たった版を選んだ。
- 決めた場面: PR #19
- 関係する要件: REQ-MTG-004, REQ-MTG-023
- 対象: Windows
- 実装の場所: `windows/Hanasu.Diarization/SherpaSpeakerDiarizer.cs`

### DEC-MTG-105 Windows 版の Whisper の語の時刻は、トークンの時刻から作る
- 決めたこと: トークンごとの時刻（t0/t1）を使い、Whisper.net が文字化け（U+FFFD）にして渡す日本語のトークンの断片は、前後の読めるトークンの位置から間の文字をまとめて 1 語にする。「(字幕)」のような括弧書きの注釈は除く。whisper.cpp の DTW の時刻は使わない。
- 理由: 日本語のトークンは 1 文字の途中で切れることがある。DTW の時刻は長い音声で途中から文字起こしが止まった。
- 決めた場面: PR #19
- 関係する要件: REQ-MTG-004, REQ-MTG-005
- 対象: Windows
- 実装の場所: `windows/Hanasu.Whisper/WhisperBatchTranscriber.cs`

### DEC-MTG-106 Windows 版の話者の割り当てに、2 つの決まりを足す
- 決めたこと: Mac 版の `MeetingProcessor`（DEC-MTG-012、DEC-MTG-013）を移し、2 つ足す。1 つの発話を話者で分けたとき、端に残った 1 秒未満・4 文字以下のかけらは隣にまとめる。スピーカーからの回り込みの除去は 6 文字以上のかけらだけを対象にする。
- 理由: 合成音声の確認で、Whisper の語の時刻の遅れから「でした。」が次の人に付いたり、「ます」が回り込みとして消えたりした。
- 決めた場面: PR #19
- 関係する要件: REQ-MTG-004, REQ-MTG-005
- 対象: Windows
- 実装の場所: `windows/Hanasu.Core/Meetings/MeetingProcessor.cs`

### DEC-MTG-107 Windows 版の会議の Gemini 文字起こしは、整形と同じモデルを使う
- 決めたこと: 会議を Gemini で文字起こしするときのモデルは、設定の Gemini のモデル（整形と同じ）。区切り方は Mac 版と同じ 5 分ごと・最大 3 つを並行（DEC-MTG-008）で、音声は WAV（5 分で約 10 MB）。
- 理由: 文字起こしには速いモデルで足りた（flash-lite で 1 分の会議を正確に起こせた）。
- 決めた場面: PR #19
- 関係する要件: REQ-COM-001
- 対象: Windows
- 実装の場所: `windows/Hanasu.Core/Meetings/MeetingTranscription.cs`

### DEC-MTG-108 Windows 版の meeting.json は、Mac 版と同じ形にする
- 決めたこと: キーは camelCase、列挙は小文字、日時は秒までの UTC、UUID は大文字、null は書かない。保存先は `ドキュメント\Hanasu\Meetings\<yyyy-MM-dd HHmm>\` で、設定で変えられる。Windows 版だけが書く `audioStartOffsets` は Mac 版では読み飛ばされる。`reminderID` は読み書きで落とさない。
- 理由: Mac で作った会議のフォルダを、そのまま Windows の会議ノートで開けるようにする（逆も）。Swift の `.iso8601` は小数の秒を読めない。
- 決めた場面: PR #19
- 関係する要件: REQ-MTG-025, REQ-COM-011
- 対象: Windows
- 実装の場所: `windows/Hanasu.Core/Meetings/MeetingModels.cs`、`windows/Hanasu.Core/Meetings/MeetingStore.cs`

### DEC-MTG-109 Windows 版では、音声入力と会議の記録を同時に動かさない
- 決めたこと: 一方が動いている間は、もう一方を始めない（記録中は音声入力のメニューとショートカットを止める）。終了しようとすると、記録中なら確かめる。起動時に、記録中・処理中のまま残った会議を「失敗」にする（音声は残る）。
- 理由: マイクを取り合わないようにする。Mac 版の DEC-MTG-018 と同じく、落ちた会議が「記録中」のまま残らないようにする。
- 決めた場面: PR #19
- 関係する要件: REQ-COM-010, REQ-COM-011
- 対象: Windows
- 実装の場所: `windows/Hanasu.Core/Dictation/DictationController.cs`、`windows/Hanasu.Core/Meetings/MeetingController.cs`

### DEC-MTG-110 Windows 版の会議のショートカットは、修飾キーを 3 つにする
- 決めたこと: 記録の開始・停止は `Ctrl + Alt + Shift + M`、「ここ重要」は `Ctrl + Alt + Shift + H`（記録中だけ登録）。設定で変えられる。
- 理由: `Ctrl + Shift + M`・`Alt + M` などは Teams・Zoom などのミュートに使われている。
- 決めた場面: PR #19
- 関係する要件: REQ-MTG-001, REQ-MTG-012
- 対象: Windows
- 実装の場所: `windows/Hanasu.Core/Settings/AppSettings.cs`

---

## 廃止

やめた要件・設計判断は、消さずにここへ移す（`- 状態: 廃止（日付・理由・PR）`）。今はない。
