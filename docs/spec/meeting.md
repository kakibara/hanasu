# 会議の記録の仕様（MTG）

会議の記録（録音・文字起こし・話者分離・議事録・会議ノート・自動検出・メモ・検索・書き出し・AI チャット）について、**実装済み**の振る舞いのうち、要件（REQ）と設計判断（DEC）を並べる。

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
- 実装の場所: `LiveTranscriptView`、`MeetingRecorder.receive`、`ChannelTranscriber`（見た目と配置は REQ-MTG-054）
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
- 受け入れ条件:
  - Mac: 会議ノートの左に会議の一覧が出て、選ぶと真ん中に議事録の文書（REQ-MTG-050）、後ろ側のパネルに文字起こしが出る。コピー（書き出し）ができる。メモを編集している間も、議事録と文字起こしが見えたまま。
  - Windows: 会議ノートの左に会議の一覧が出て、選ぶと右に「議事録」「文字起こし」が出る。コピー（書き出し）ができる。どのタブ（「メモ」を含む）を開いても、上のタブの切り替えが見えたままで、ほかのタブに戻れる。
- 出典: 初版の要件定義 F7（必須）。Mac の受け入れ条件は 2026-11-09 の依頼「hanasu の会議ノートの UI もモダンに変更したい。どのような UI が良いかを考え、タスクを洗い出して要件を定義し、要件に沿ってモダンな UI を考えて」、同日に計画（docs/plans/meeting-notes-ui.md）を了承で変えた
- 対象: Mac / Windows
- 実装の場所: `MeetingWindowView`、`MeetingDocumentView`、`MeetingInspector`
- Windows の実装: `windows/Hanasu.Windows/Views/MeetingWindow.xaml.cs`（書き出しは「Markdown をコピー」だけ）
- 確かめ方: Mac は `.build/debug/Hanasu --render-meeting-window <フォルダ>` で画面を PNG にする（中身の大きさがウインドウの中身を超えない（NG が出ない）こと。メモを編集している状態でもタイトルと文字起こしが見えること）

### REQ-MTG-008 話者名を、あとから付け替えられる（F8）
- 内容: 「話者1」を「田中さん」のように、あとから付け替えられる。
- 受け入れ条件: 会議ノートで話者名を変えると、文字起こしと議事録の表示がその名前になり、保存される。
- 出典: 初版の要件定義 F8（あると良い）
- 対象: Mac / Windows
- 実装の場所: `MeetingRecorder.renameSpeaker`・`renameSpeakers`（話者名のシートで変えた話者をまとめて保存する）、`Meeting.renameSpeaker`、`Meeting.displayName`
- Windows の実装: `windows/Hanasu.Windows/Views/MeetingWindow.xaml.cs`、`windows/Hanasu.Core/Meetings/MeetingModels.cs`（`Meeting.RenameSpeaker`）
- 確かめ方: 実機で確かめる

### REQ-MTG-009 会議アプリがマイクを使い始めたら、記録するかを聞く（F9）
- 内容: 会議アプリがマイクを使い始めたら「会議を記録しますか？」と知らせる。自動では記録を始めない。
- 受け入れ条件: Zoom などがマイクを使い始めると提案が出て、「記録する」を押したときだけ記録が始まる。
- 出典: 初版の要件定義 F9（あると良い、フェーズ 2）。PR #14（10 個の改善案の 1 つ）で実装した
- 対象: Mac
- 実装の場所: `MeetingDetector`、`MeetingAutoDetect`、`MeetingSuggestionPanel`
- 確かめ方: `.build/debug/Hanasu --simulate-meeting-detection`、`--list-audio-processes`、`--render-meeting-suggestion out.png`

### REQ-MTG-010 会議ごとに、文字起こしのあとに録音を消すかを選べる（F10）
- 内容: 会議ごとに、録音を「文字起こしと議事録のあとに消す」か「残す」かを選べる。既定は設定で決め、記録を始める前（記録の設定のパネル）と記録中（記録中の画面）に、その会議の分を変えられる。
- 受け入れ条件:
  - 設定「会議」に「文字起こしのあとに録音を削除する」がある（以前の「音声ファイルを残す」の裏返し。保存しているキーは変えない）。既定はオフ（残す）。
  - Mac: 会議ノートの記録の設定のパネル（REQ-MTG-051）に同じスイッチがあり、設定と同じ値（次の記録からの既定）を変える。Windows: 会議ノートの左下（マイク・スピーカー・議事録の型の下）に同じチェックボックスがある。
  - 記録を始めると、どの入口（会議ノートのボタン・メニュー・ショートカット・Mac の自動検出のパネル・Windows のトレイ）から始めても、その時点の既定がその会議の値になる。Mac も Windows も、記録を始めると会議ノートが開く。
  - 記録中の画面に「この会議の録音を文字起こしのあとに削除」の切り替えがあり、今の値が見える。押すとその会議の値だけが変わり、既定は変わらない。Mac はツールバー、Windows は左上の記録中の欄。記録を止めて処理に入ったあとは変えられない。
  - 記録中に設定画面で既定を変えても、記録中の会議の値は変わらない。記録中は、一覧の下の 1 行に記録中の会議の値を出す。
  - 値がオンの会議は、後処理のあとに音声ファイル（`me.m4a` / `others.m4a`、Windows は `me.wav` / `others.wav`）が消え、`transcript.md`・`minutes.md`・`meeting.json`・`notes.md` は残る。オフの会議は残る。
  - オンでも、文字起こしがそろっていない会議（文字起こしに失敗したチャンネルがある・発言が 0 件。DEC-MTG-142）と、記録中・処理中にアプリが終わった会議（DEC-MTG-018）は録音を残し、会議の帯に「音声ファイルは残しています」を出す。
  - Mac 標準のエンジンで、記録中に認識の結果のストリームがエラーで止まったチャンネル（取り消しを除く）も、文字起こしに失敗したチャンネルに数える。
- 出典: 初版の要件定義 F10（あると良い）。会議ごとに選べるようにしたのは 2026-11-09 の依頼「文字起こしを作成したら録音を削除するというオプションを作成してください。また、後から録音を削除する機能も作成してください」、2026-11-10 に計画（docs/plans/meeting-audio-deletion.md）を了承
- 関係する要件: REQ-MTG-051, REQ-MTG-054, REQ-MTG-057
- 対象: Mac / Windows
- 実装の場所: `MeetingAudioPolicy`、`MeetingRecorder.start`・`stop`・`process`・`setDeleteAudioAfterTranscription`、`ChannelTranscriber`、`RecordSettingsPopover`、`LiveDeleteAudioToggle`、`SettingsView`
- Windows の実装: `windows/Hanasu.Core/Meetings/MeetingController.cs`（`StartAsync`・`SetDeleteAudioAfterTranscription`）、`windows/Hanasu.Core/Meetings/MeetingPostProcessor.cs`、`windows/Hanasu.Windows/AppHost.cs`、`windows/Hanasu.Windows/Views/MeetingWindow.xaml.cs`、`windows/Hanasu.Windows/Views/SettingsWindow.xaml.cs`
- 確かめ方: `.build/debug/Hanasu --test-meeting-audio`（会議への写し・会議の値で決まる・文字起こしがそろっていなければ残す）、`.build/debug/Hanasu --meeting-files me.wav others.wav --delete-audio`。Windows: `cd windows && dotnet test Hanasu.Core.Tests --filter "FullyQualifiedName~MeetingAudioDeletionTests"`、`dotnet run --project Hanasu.Cli -- meeting-files me.wav others.wav --delete-audio`。記録中の切り替えの見た目は `.build/debug/Hanasu --render-meeting-window <フォルダ>` の `live-window-min.png`

### REQ-MTG-011 記録中にメモを書ける（F11）
- 内容: 記録中にメモを書ける。1 行ずつ、録音開始からの経過時間つきで保存する。
- 受け入れ条件: 記録中にメモ欄で Enter を押すと、時刻つきの行が並び、`meeting.json` と `notes.md` に残る。
- 出典: PR #10（10 個の改善案の 1 つ）
- 対象: Mac / Windows
- 実装の場所: `LiveNotesPanel`、`MeetingRecorder.addNote`
- Windows の実装: `windows/Hanasu.Core/Meetings/MeetingController.cs`、`windows/Hanasu.Windows/Views/MeetingWindow.xaml.cs`
- 確かめ方: `--render-meeting-notes <フォルダ>`、`--meeting-files me.wav others.wav --notes notes.txt`

### REQ-MTG-012 記録中に「ここ重要」の印を付けられる（F12）
- 内容: 記録中に、ボタンと設定で変えられるショートカットで「ここ重要」の印を付けられる。付けてから 10 秒のあいだは、その印を取り消せる（押し間違いのやり直し）。記録のあとに、印を付けた時刻の前後の会話を確かめられる。
- 受け入れ条件:
  - 会議ツールを前面にしたまま `⌃⌥⌘ H` を押すと、その時刻に印が付く。
  - 印を付けてから 10 秒のあいだ、会議ノートのメモ欄（Mac は字幕のパネルにも）に残りの秒数つきの「取り消す」が出て、押すとその印が消え、`meeting.json` からも消える。10 秒を過ぎると「取り消す」は消え、記録中には消せない（記録のあとに、Mac は文書のメモの欄、Windows は「メモ」タブで消す。REQ-MTG-013）。
  - 印ごとに時刻・説明と、その前後（30 秒前〜15 秒後）の発言が出る。Mac は会議ノートの文書の「ここ重要」の欄に出し、「前後の会話を見る」で後ろ側のパネルの文字起こしのその位置へ移る。Windows は会議ノートの「ここ重要」タブに出す。
- 出典: PR #10。前後の会話の確認はユーザーの依頼（2026-11-04「重要の秒数付近の会話をかくにんできるようにして。あと、mac版では会議メモを開くと足袋などが消失して文字起こしや要約のページに戻れないので修正して」）。取り消しはユーザーの依頼（2026-11-04「会議のここ重要を削除できないので削除できるようにして。10秒前まで削除できるようにして」。付けてから 10 秒のあいだ取り消せる、という意味だとユーザーに確かめた）。Mac の置き場所は 2026-11-09 の依頼「hanasu の会議ノートの UI もモダンに変更したい。どのような UI が良いかを考え、タスクを洗い出して要件を定義し、要件に沿ってモダンな UI を考えて」、同日に計画（docs/plans/meeting-notes-ui.md）を了承で変えた
- 対象: Mac / Windows
- 実装の場所: `MeetingRecorder.addHighlight`、`MeetingHighlightHotKey`、`MeetingRecorder.undoHighlight`、`HighlightUndoButton`、`Meeting.highlightContexts`、`HighlightContextsView`
- Windows の実装: `windows/Hanasu.Core/Meetings/MeetingController.cs`（ショートカットは DEC-MTG-110。取り消しは `UndoHighlight`）、`windows/Hanasu.Core/Meetings/MeetingModels.cs`（`HighlightContexts`・`HighlightContextText`）、`windows/Hanasu.Windows/Views/MeetingWindow.xaml.cs`（`UpdateUndoHighlight`、「ここ重要」タブ）
- 確かめ方: 実機で確かめる。印の反映は `--meeting-files … --notes notes.txt`。取り消しは `.build/debug/Hanasu --render-meeting-notes <フォルダ>`（「ここ重要の取り消し」の結果と `live-undo.png`・`caption-undo.png`）、Windows は `cd windows && dotnet test Hanasu.Core.Tests --filter "FullyQualifiedName~HighlightUndo|FullyQualifiedName~UndoesARecentHighlight|FullyQualifiedName~HighlightContext"`。前後の会話は `.build/debug/Hanasu --render-minutes-ui <フォルダ>`（「ここ重要の前後」）と `.build/debug/Hanasu --render-meeting-window <フォルダ>`（文書の「ここ重要」の欄）

### REQ-MTG-013 議事録は、メモと印を優先して反映する。記録後にメモを直して作り直せる（F13）
- 内容: 議事録はメモと印を優先して反映する。記録後にメモを直して、議事録を作り直せる。作り直しているあいだは、どの会議を作り直しているかがわかり、作り直しても選んでいた会議のままになる。
- 受け入れ条件:
  - 印を付けた箇所が議事録の「重要とした箇所」にまとまり、メモにしかない内容も残る。「保存して議事録を作り直す」で議事録が変わる。
  - Mac の会議ノートで議事録を作り直すと、終わるまで、その会議の文書の上の帯に「議事録を作り直しています…」と回る印が出て（今の議事録は薄く出したまま）、左の一覧のその会議にも回る印が出る。終わっても、一覧で選んでいた会議のまま（先頭の会議に移らない）。
- 出典: PR #10。作り直し中の表示と選択はユーザーの依頼（2026-11-04「議事録を再生成したら選択していた会議から先頭の会議に移動してしまうのですが、議事録を再生成しても、同じ会議に留まるようにしてください。また、議事録生成中の場合は生成中であることがわかるようにしてください。」）
- 対象: Mac / Windows（2 つ目の受け入れ条件は Mac。Windows 版は作り直し中に「〇〇 で議事録を作っています…」と出し、作り直しても選んだ会議のまま）
- 実装の場所: `Meeting.notesForPrompt`、`Meeting.transcriptForPromptMarkingHighlights`、`MeetingRecorder.regenerateMinutes`、`MeetingRecorder.regeneratingID`、`MeetingNotesEditor`、`MeetingDetailView`、`MeetingWindowView`
- Windows の実装: `windows/Hanasu.Core/Meetings/MinutesTemplate.cs`、`windows/Hanasu.Windows/Views/MeetingWindow.xaml.cs`
- 確かめ方: `--meeting-files me.wav others.wav --notes notes.txt`。作り直し中の表示は `.build/debug/Hanasu --render-meeting-window <フォルダ>` の `regenerating.png`。選んだ会議のままかは実機で確かめる

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
- 食い違い（ユーザーの確認待ち）: 会議の記録中に音声入力を使うと、その間のアイコンは音声入力の状態（録音中なら赤い `mic.fill`）になり、会議の記録中の印（`record.circle.fill`）は音声入力が終わるまで出ない（DEC-DIC-017）。どちらも赤いが、「常に表示」と言えるかを確かめる。また、REQ-COM-040 で「Dock だけ」を選ぶとメニューバーにアイコンが出ないので、記録中の印は Dock のアイコンのバッジ（「●」）と Dock のメニューの経過時間で示す（DEC-COM-081）。この場合は要件を「メニューバーか Dock に常に表示する」と読んでよいかを確かめる

### REQ-MTG-027 会話の内容から話者の名前を推測して付ける
- 内容: 議事録を作るときに、会話の内容（名乗り・自己紹介・名前での呼びかけに本人が応じた、など）から名前がはっきり分かる話者に、その名前を付ける。付けた名前は「推測」と分かるように出し、あとから直せる（REQ-MTG-008）。
- 受け入れ条件:
  - 相手が「田中です」と名乗ったり、「田中さん、どうですか」に答えたりした会議の記録を止めると、議事録ができたときに、その話者が文字起こし・議事録・アクションアイテムの担当で「田中」と表示される。
  - 会話から分からない話者は「話者1」などのまま。「自分」には名前を付けない。ユーザーが付けた名前は変えない。
  - 会議ノートの話者名の欄に「推測」と出る。名前を直すと「推測」が消える。
  - 議事録を作り直すと、まだ名前のない話者だけを推測し直す。
- 出典: ユーザーの依頼（2026-11-04「会議の会話内容から話者の名前を推測して名前をつけるようにしてください」）
- 対象: Mac / Windows
- 実装の場所: `MinutesPrompt.speakerNamesInstruction`、`SpeakerNameInference`、`Meeting.applyMinutes`、`SpeakerNamesSheet`
- Windows の実装: `windows/Hanasu.Core/Meetings/SpeakerNameInference.cs`、`windows/Hanasu.Core/Meetings/MinutesTemplate.cs`（`MinutesPrompt.SpeakerNamesInstruction`）、`windows/Hanasu.Core/Meetings/MeetingModels.cs`（`Meeting.ApplyMinutes`・`RenameSpeaker`）、`windows/Hanasu.Windows/Views/MeetingWindow.xaml.cs`
- 確かめ方: `.build/debug/Hanasu --test-speaker-names`（読み取り・名前の検査・当てはめ・置き換え・meeting.json）、`--minutes-from-transcript <文字起こし.txt>`（実際の AI で推測した名前を表示）。Windows: `cd windows && dotnet test Hanasu.Core.Tests --filter "FullyQualifiedName~SpeakerNameInference"`。会議ノートの「推測」の表示は実機で確かめる

### REQ-MTG-028 記録した会議を削除できる
- 内容: 会議ノートで、記録した会議を削除できる。削除すると、その会議のフォルダ（議事録・文字起こし・メモ・音声）がなくなり、一覧・検索・質問の対象から外れる。
- 受け入れ条件:
  - 会議ノートで会議を選んで「削除」を選ぶと、確かめるダイアログが出る。「ゴミ箱に入れる」（Windows は「ごみ箱に移す」）を押すと、一覧からその会議が消え、保存先のフォルダもなくなる。キャンセルすると何も変わらない。
  - 記録中・処理中（議事録の作り直し中を含む）の会議は削除できない。
- 出典: ユーザーの依頼（2026-11-04「会議の記録を削除できるようにしてください」）
- 対象: Mac / Windows
- 実装の場所: `MeetingStore.moveToTrash`、`MeetingRecorder.delete`・`canDelete`、`MeetingWindowView`、`MeetingDetailView`
- Windows の実装: `windows/Hanasu.Core/Meetings/MeetingStore.cs`（`Delete`）、`windows/Hanasu.Core/Meetings/MeetingController.cs`（`Delete`・`CanDelete`）、`windows/Hanasu.Windows/Views/MeetingWindow.xaml.cs`
- 確かめ方: Windows: `cd windows && dotnet test Hanasu.Core.Tests --filter "FullyQualifiedName~MeetingControllerTests"`（フォルダが消えること、記録中・作り直し中は消せないこと）。Mac: `.build/debug/Hanasu --render-meeting-window <フォルダ>` の `more-menu.png` に「削除…」が出ること。ゴミ箱に移ることは実機で確かめる

### REQ-MTG-029 会議のタイトルを変えられ、変えられることが見てわかる
- 内容: 会議ノートの上のタイトルを、その場で書き換えられる。書き換えられる欄であることが、触らなくても見た目でわかる。
- 受け入れ条件:
  - タイトルの欄に、枠と鉛筆の印（Windows は ✎）が出ている。マウスを載せると枠が濃くなり、「クリックしてタイトルを変更」と出る。
  - 書き換えて Enter を押すか、ほかの所をクリックすると保存され、一覧のタイトルも変わる。空にしたときは元のタイトルに戻す。Esc で書き換えをやめられる。
- 出典: ユーザーの依頼（2026-11-04「タイトルが編集できることをUI上でも見ただけでわかるようにしてください」）
- 対象: Mac / Windows
- 実装の場所: `EditableTitleField`、`MeetingDocumentView`
- Windows の実装: `windows/Hanasu.Windows/Views/MeetingWindow.xaml`（`TitleBox`）、`windows/Hanasu.Windows/Views/MeetingWindow.xaml.cs`
- 確かめ方: `.build/debug/Hanasu --render-meeting-window <フォルダ>` の `document.png` で、タイトルの欄に枠と鉛筆の印が出ること。保存は実機で確かめる

### REQ-MTG-034 会議を認識したとき、会議のタイトルを議事録のタイトルにする
- 内容: Google Meet・Microsoft Teams などの会議を記録するとき、会議アプリのウインドウに出ている会議の名前を読み取り、日時のタイトルの代わりに議事録（会議ノート）のタイトルにする。
- 受け入れ条件:
  - マイクを使っている会議アプリ（Teams、ブラウザの Google Meet、Webex）のウインドウから会議の名前が読み取れたとき、記録を始めた会議のタイトルがその名前になる（提案の「記録する」でも、メニュー・ショートカット・会議ノートの開始ボタンで始めても同じ）。
  - 読み取れないとき（Zoom・Slack・FaceTime のようにウインドウに名前が出ないアプリ、Teams のチャットなど会議でない画面、Meet の会議コードだけのタイトル、アクセシビリティが未許可）は、今までどおり「会議 <日時>」にする。記録の開始は妨げない。
  - 読み取った名前は、あとから REQ-MTG-029 のとおり書き換えられる。
- 出典: ユーザーの依頼（2026-11-05「google meetやteamsなどの会議を認識したときに会議のタイトルを認識して議事録のタイトルに追加するようにしてください」）
- 対象: Mac
- 実装の場所: `MeetingTitle`、`MeetingAutoDetect.titleSourceApps`、`MeetingRecorder.start`（`titleSourceApps`）
- 確かめ方: `.build/debug/Hanasu --check-meeting-title`（取り出す規則）、`--detect-meeting-title`（実機のウインドウから読む）。Teams・Meet の会議中に記録を始めてタイトルが変わることは実機で確かめる

### REQ-MTG-030 会議の記録では、会議ツールの画面・映像を記録しない（対象外）
- 内容: 会議の記録では、会議ツールの画面・映像を記録しない。
- 受け入れ条件: 会議の記録は、画面収録の許可を求めず、映像のファイルを作らない。Hanasu が画面収録の許可を求めるのは、設定の画面の「スクリーンショットの文字も AI に渡す」の欄から（音声入力のスクリーンショット。REQ-DIC-041・042）だけ。
- 出典: 初版の「対象外（今回はやらない）」。2026-11-10、音声入力のスクリーンショット（REQ-DIC-041）のために、範囲を会議の記録に絞った（ユーザーの合意。[plans/screen-ocr.md](../plans/screen-ocr.md)）
- 対象: Mac / Windows
- 実装の場所: なし
- Windows の実装: なし
- コードのタグ: 不要（やらないことの要件）
- 確かめ方: 会議の記録のコード（`MeetingRecorder`・`SystemAudioTap` など）が ScreenCaptureKit の映像と画面収録の許可を使わないこと。権限の一覧（[design/meeting.md](../design/meeting.md) 7）で、画面収録が音声入力のスクリーンショットのためだけにあること

### REQ-MTG-031 会議ツールにボットで参加しない（対象外）
- 内容: 会議ツールへボットで参加しない。ボットでの記録は計画（[roadmap.md](../roadmap.md) FUT-203）。
- 受け入れ条件: 会議の参加者に Hanasu のボットが現れない。
- 出典: 初版の「対象外（今回はやらない）」
- 対象: Mac / Windows
- 実装の場所: なし
- Windows の実装: なし
- コードのタグ: 不要（やらないことの要件）
- 確かめ方: 該当する機能がないこと

### REQ-MTG-032 会議ツールの参加者一覧から名前は取らない（対象外）
- 内容: 会議ツールの参加者一覧（画面やAPI）を読んで名前を取ることはしない。話者名は、会話の内容からの推測（REQ-MTG-027）と、手での付け替え（REQ-MTG-008）だけ。
- 受け入れ条件: 会議ツールの画面や API から参加者の名前を読まない。会話から名前が分からない話者は「話者1」などのまま保存される。
- 出典: 初版の「対象外（今回はやらない）」。ユーザーの依頼（2026-11-04「会議の会話内容から話者の名前を推測して名前をつけるようにしてください」）で、会話からの推測で名前を付けるようにしたので、「自動では名前に変わらない」を外した
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

### REQ-MTG-042 議事録のテンプレートに名前を付けて保存し、管理できる
- 内容: 議事録の見出しの構成や書き方の指示に名前を付けてテンプレートとして保存し、一覧から追加・名前と指示の編集・複製・削除ができる。保存したテンプレートは、記録の前の型の選択欄と、会議ノートの「型」メニュー（作り直し）で、組み込みの型と並べて選べる。
- 受け入れ条件:
  - 会議ノートの型の選択欄の右の管理ボタンから、名前と指示を入れてテンプレートを追加できる。アプリを再起動しても残る。
  - 同じ名前のテンプレートは作れない（前後の空白と大文字小文字は区別しない）。名前か指示が空のテンプレートも作れない。
  - 保存したテンプレートを選んで記録すると、その指示で議事録ができる。会議ノートの「型: 〇〇」には、そのテンプレートの名前が出る。
  - 会議ノートの「型」メニューから保存したテンプレートを選ぶと、確認のあと、その指示で議事録を作り直す。
  - 保存したテンプレートを直す・消しても、すでに記録した会議の議事録や、その会議に写した指示は変わらない。
  - 選んでいたテンプレートを消したときは、次の記録の型は「自動」になる。
  - カスタムの指示のシートから、書いた指示をそのままテンプレートとして保存できる。
- 出典: ユーザーの依頼（2026-11-05「MTGの議事録のテンプレートを名前付きで作成保存して管理できるようにしてください」）、PR #67
- 関係する要件: REQ-MTG-017
- 対象: Mac
- 実装の場所: `SavedMinutesTemplate`、`SavedMinutesTemplateStore`、`MinutesTemplateManagerSheet`、`MinutesTemplatePicker`、`MinutesTemplateMenu`、`CustomMinutesPromptSheet`、`MinutesTemplateStore.apply`
- 確かめ方: `.build/debug/Hanasu --test-saved-templates`（保存・重複の拒否・複製・削除・適用・プロンプトへの反映）、`--render-minutes-ui <出力フォルダ>` の `record-panel-saved.png`・`template-manager-sheet.png`

### REQ-MTG-040 記録中に、それまでの会話の記録をもとに AI とチャットできる
- 内容: 会議を記録している間に、その時点までの文字起こし（確定前の途中結果を含む）・メモ・「ここ重要」の印をもとに、AI に質問して答えを得られる。
- 受け入れ条件:
  - 記録中の画面の右側を「AI チャット」に切り替えると（⌘J でも）、文字起こしを見たまま質問を入力して送れる。「ここ重要」のボタンはチャット中も押せる。
  - 答えは、送った時点までの記録をもとにし、根拠の発言の時刻を [12:34] の形で示す。時刻を押すと、文字起こしのその発言へ移る。
  - 「ここまでを要約」「決まったこと・宿題」などのボタン 1 つで、よく使う質問を送れる。
  - 答えはコピーでき、「メモに残す」でメモに足せる（議事録で優先して取り上げる）。
  - 記録中は文字起こしをしないエンジン（Whisper / Gemini）では、メモと印だけをもとに答えることを知らせる。
- 出典: ユーザーの依頼（2026-11-05「会議の録音中に、それまでの会話記録を元に AI とチャットができる機能を作成。UI/UX も使い勝手が良いように考えてデザインする」）
- 対象: Mac
- 実装の場所: `MeetingChat`、`MeetingChatModel`、`MeetingChatView`、`LiveSidePanel`、`LiveTranscriptView`
- 確かめ方: `.build/debug/Hanasu --test-meeting-chat`（AI を呼ばない）、`.build/debug/Hanasu --chat-meeting <会議のフォルダ> --at 10:00 --ask "<質問>"`（その時刻までを記録中として渡す）、`.build/debug/Hanasu --render-meeting-chat <出力フォルダ>`（画面を PNG にする）。実際の会議は実機

### REQ-MTG-041 AI チャットは、前のやりとりを踏まえて会話を続けられる
- 内容: 一問一答ではなく、続けて質問すると、それまでの質問と答えを踏まえて答える（「それ」「さっきの」が通じる）。
- 受け入れ条件:
  - 「決まったことは？」のあとに「その中で期限があるものは？」と聞くと、前の答えを受けて答える。
  - 「新しい会話」で会話を消して、始め直せる。
- 出典: ユーザーの依頼（2026-11-05「チャットも会話ができるようにしてください」）
- 対象: Mac
- 実装の場所: `MeetingChat.prompt`、`MeetingChatModel`、`MeetingChatStore`
- 確かめ方: `.build/debug/Hanasu --chat-meeting <会議のフォルダ> --ask "決まったことは？" --ask "その中で期限があるものは？"`、`.build/debug/Hanasu --test-meeting-chat`

### REQ-MTG-043 記録中にスリープしたら、復帰の直後に「スリープ前までで止める」か「続ける」かを選べる
- 内容: 会議を記録したまま Mac をスリープした（MacBook を閉じた）・Windows がスリープした場合、復帰した直後に、スリープする前までで記録を止めるか、記録を続けるかを聞く。
- 受け入れ条件:
  - 記録中にスリープして復帰すると、スリープした時刻を添えて「スリープ前までで止める」「記録を続ける」を選ぶ確認が出る。
  - 「スリープ前までで止める」を選ぶと、記録はスリープした時点で終わったものとして後処理に進む。スリープより後（復帰してから選ぶまで）の音声・文字起こし・「ここ重要」の印は会議に残らず、会議の長さもスリープした時点まで。
  - 「記録を続ける」を選ぶと、そのまま記録を続ける。スリープしていた時間は会議の時間軸に入れない（メモの時刻と文字起こしの時刻がずれない）。
  - 答える前にもう一度スリープしても、確認は 1 つだけ出し、「止める」は最初にスリープした時点で止める。
  - 記録していないとき・後処理の途中にスリープしたときは、何も聞かない（後処理はそのまま続く）。
- 出典: ユーザーの依頼（2026-11-06「会議の録音を起動したまま mac をスリープさせてしまったり macbook を閉じた場合に、再開しても録音を継続したままになっていました。そのような場合は、作業再開直後にスリープ前までで録音を停止させるか録音を継続するかを選べるようにしてください。windows でも同様の対応を行なってください」）
- 関係する要件: REQ-MTG-001, REQ-MTG-011, REQ-MTG-012
- 対象: Mac / Windows
- 実装の場所: `MeetingRecorder.systemWillSleep`、`MeetingRecorder.systemDidWake`、`MeetingRecorder.stop(cutAt:)`、`MeetingSleepCut`
- Windows の実装: `windows/Hanasu.Core/Meetings/MeetingController.cs`（`OnSystemSuspend`・`OnSystemResume`・`ResolveSleepAsync`）、`windows/Hanasu.Windows/AppHost.cs`、`windows/Hanasu.Windows/Views/SleepPromptWindow.cs`
- 確かめ方: `.build/debug/Hanasu --test-meeting-sleep-cut`（スリープ時点での切り詰め。音声ファイルの切り詰めを含む）、`cd windows && dotnet test Hanasu.Core.Tests --filter "FullyQualifiedName~Sleep"`。実際のスリープと確認の画面は実機

### REQ-MTG-044 文字起こしの最初と最後を選んで、その範囲で議事録を作れる
- 内容: 記録した会議の文字起こしで、議事録に使う最初の発言と最後の発言を選ぶ。範囲の外の発言（始まる前・終わった後の雑談、止め忘れて録れた次の会議など）は議事録に使わない。
- 受け入れ条件:
  - 会議ノートの文字起こしで、発言を右クリックして「ここから議事録に使う」「ここまで議事録に使う」を選べる。片方だけでもよい。
  - 範囲の外の発言は、文字起こしに薄く残る（消えない）。範囲はいつでも変えられ、解除できる。
  - 範囲を変えたあと「議事録を作り直す」と、範囲の中の発言だけで議事録ができる。
- 出典: ユーザーの依頼（2026-11-06「会議を録音したら文字起こしの最初と最後を選んで、その範囲内で議事録を作成する。特定の発言を無視して議事録を作成する」、想定ケースの提案に「推奨どおり進める」）
- 関係する要件: REQ-MTG-013, REQ-MTG-045
- 対象: Mac / Windows
- 実装の場所: `Meeting.minutesFrom`・`Meeting.minutesTo`、`Meeting.minutesUse(of:)`、`TranscriptSelectionBar`、`TranscriptLineMenu`
- Windows の実装: `windows/Hanasu.Core/Meetings/MinutesSelection.cs`、`windows/Hanasu.Windows/Views/MeetingWindow.xaml`・`windows/Hanasu.Windows/Views/MeetingWindow.xaml.cs`
- 確かめ方: `.build/debug/Hanasu --test-minutes-selection`、`cd windows && dotnet test Hanasu.Core.Tests --filter "FullyQualifiedName~MinutesSelection"`。画面は `.build/debug/Hanasu --render-minutes-selection <出力フォルダ>`

### REQ-MTG-045 特定の発言・特定の話者の発言を除いて議事録を作れる
- 内容: 記録した会議の文字起こしで、議事録に使わない発言を選んで除く。話者ごとにまとめても除ける。想定する場面は、オフレコの話・機微な話（人事・個人の事情・公開前の数字）、会議と関係ない割り込み（電話・家族や隣の人の声・別のタブの動画）、接続や機材のやりとり（「聞こえますか」「画面見えてますか」）、途中の脱線・雑談、撤回した発言（言い直す前の誤った数字）、会議に関係ない話者（通訳の重なった音声など）。
- 受け入れ条件:
  - 発言を右クリックして「議事録から除く」「議事録に戻す」を選べる。「議事録に使う発言を選ぶ」にすると発言ごとにチェックボックスが出て、Shift を押しながらクリックすると前にクリックした発言からまとめて切り替えられる。
  - 話者の発言を右クリックして、その話者の発言をすべて除く・戻すことができる。
  - 除いた発言は文字起こしに薄く取り消し線つきで残り、元に戻せる。
  - 除いた発言（範囲の外・オフレコを含む）は、議事録・話者の名前の推測・AI チャット・会議への質問・文字起こしの書き出し（コピー・保存・transcript.md）に使わない。会議の検索ではヒットする（文字起こしでは薄く出る）。
  - 議事録に使う発言を変えても、議事録はすぐには作り直さず、「作り直すと反映されます」と出す（Mac は文書の上の帯、Windows は議事録のタブ）。
- 出典: ユーザーの依頼（2026-11-06「会議を録音したら文字起こしの最初と最後を選んで、その範囲内で議事録を作成する。特定の発言を無視して議事録を作成する」、想定ケースの提案に「推奨どおり進める」）。Mac の知らせの置き場所は 2026-11-09 の依頼「hanasu の会議ノートの UI もモダンに変更したい。どのような UI が良いかを考え、タスクを洗い出して要件を定義し、要件に沿ってモダンな UI を考えて」、同日に計画（docs/plans/meeting-notes-ui.md）を了承で変えた
- 関係する要件: REQ-MTG-013, REQ-MTG-016, REQ-MTG-040, REQ-MTG-044
- 対象: Mac / Windows
- 実装の場所: `Meeting.excludedUtterances`・`Meeting.excludedSpeakers`、`Meeting.minutesUse(of:)`、`Meeting.blocksForMinutes`、`MeetingRecorder.setExcluded`、`TranscriptSelectionBar`、`TranscriptLineMenu`
- Windows の実装: `windows/Hanasu.Core/Meetings/MinutesSelection.cs`、`windows/Hanasu.Windows/Views/MeetingWindow.xaml`・`windows/Hanasu.Windows/Views/MeetingWindow.xaml.cs`
- 確かめ方: `.build/debug/Hanasu --test-minutes-selection`、`cd windows && dotnet test Hanasu.Core.Tests --filter "FullyQualifiedName~MinutesSelection"`。画面は `.build/debug/Hanasu --render-minutes-selection <出力フォルダ>`

### REQ-MTG-046 記録中に「オフレコ」を始めて終えると、その間の発言を議事録に使わない
- 内容: 記録中に「オフレコ」のボタンを押してから、もう一度押す（オフレコを終える）までの間の発言を、議事録などに使わない（REQ-MTG-045 で除いた発言と同じ扱い）。録音そのものは続ける。
- 受け入れ条件:
  - 記録中の画面に「オフレコ」のボタンがあり、押すと「オフレコ中」と始めた時刻が出て、ボタンが「オフレコを終える」に変わる。オフレコ中の発言は薄く出し、AI チャットにも渡さない。
  - オフレコのまま記録を止めたら、記録の終わりまでをオフレコにする。
  - 記録のあと、会議ノートの文字起こしでオフレコの区間を見られ、区間ごとに解除できる。
- 出典: ユーザーの依頼（2026-11-06「会議を録音したら文字起こしの最初と最後を選んで、その範囲内で議事録を作成する。特定の発言を無視して議事録を作成する」、想定ケースの提案に「推奨どおり進める」）
- 関係する要件: REQ-MTG-045, REQ-MTG-040
- 対象: Mac / Windows
- 実装の場所: `Meeting.offRecord`、`MeetingRecorder.toggleOffRecord`、`LiveOffRecordControls`、`TranscriptSelectionBar`
- Windows の実装: `windows/Hanasu.Core/Meetings/MeetingController.cs`（`ToggleOffRecord`）、`windows/Hanasu.Windows/Views/MeetingWindow.xaml`・`windows/Hanasu.Windows/Views/MeetingWindow.xaml.cs`
- 確かめ方: `.build/debug/Hanasu --test-minutes-selection`、`cd windows && dotnet test Hanasu.Core.Tests --filter "FullyQualifiedName~OffRecord"`。画面は `.build/debug/Hanasu --render-minutes-selection <出力フォルダ>`。実際の記録は実機

### REQ-MTG-050 記録した会議は、真ん中の文書と後ろ側のパネルで、議事録と元の発言を並べて読める
- 内容: 記録した会議を選ぶと、真ん中に「要約・アクションアイテム・議事録・ここ重要・メモ」を上から順に 1 枚の文書として出し、後ろ側（左から右に書く言語では右）のパネルに「文字起こし」と「AI チャット」を切り替えて出す。タブを切り替えなくても、議事録を読みながら文字起こしを見られる。
- 受け入れ条件:
  - 会議を選ぶと、真ん中の文書の上から、タイトル（変えられる）・日時と長さと参加者・状態の帯（あれば）・要約・アクションアイテム・議事録の残りの本文・「ここ重要」・メモの順に出る。要約は議事録の最初の `## ` の節（型の既定では「概要」）で、なければ出さない。アクションアイテムの欄は、取り出したアクションアイテムが 1 つ以上あるときだけ出し、そのときは本文の「## アクションアイテム」（型によって「次のアクション」「次のステップ」）の節を本文に重ねて出さない。0 件なら、その節を本文のまま出す。「ここ重要」の印がない会議では「ここ重要」の欄を出さない。メモの欄はいつも出す。
  - 後ろ側のパネルの上に「文字起こし｜AI チャット」の切り替えがあり、どちらを選んでも真ん中の文書は見えたまま。パネルはツールバーのボタンと ⌥⌘I で隠せる・出せる。幅はドラッグで変えられる。
  - ウインドウの最小の大きさで後ろ側のパネルを出したまま、真ん中の文書の幅が 400pt 以上ある。
  - 検索で議事録の行を選ぶと、その行（要約・本文のどちらに出ていても）へスクロールして色を付ける。アクションアイテムの節の行なら、アクションアイテムの欄の同じ順番の行へ移る（順番が合わなければ欄の先頭）。
  - 今までのタブでできたこと（議事録・文字起こし・メモの編集・ここ重要の前後の会話・AI チャット・議事録に使う発言の選択・検索から飛ぶ・話者名・作り直し・書き出し・Finder で表示・削除）は、すべてこの画面でできる。
  - 「質問」（REQ-MTG-016）を開いている間は、後ろ側のパネルを出さない。
- 出典: 2026-11-09 の依頼「hanasu の会議ノートの UI もモダンに変更したい。どのような UI が良いかを考え、タスクを洗い出して要件を定義し、要件に沿ってモダンな UI を考えて」、同日に計画（docs/plans/meeting-notes-ui.md）を了承
- 関係する要件: REQ-MTG-007, REQ-MTG-015, REQ-MTG-018
- 対象: Mac（Windows は今のタブのまま。FUT-206）
- 実装の場所: `MeetingWindowView`、`MeetingDocumentView`、`MinutesDocument`、`MeetingInspector`
- 確かめ方: `.build/debug/Hanasu --render-meeting-window <フォルダ>`（最小の大きさ・パネルあり・発言を選ぶ状態を描き、中身の大きさがウインドウを超えない（NG が出ない）こと。文書の順番）と `--test-minutes-document`（節の分け方・アクションアイテムの節の外し方・検索の行の読み替え）

### REQ-MTG-051 会議の一覧は日付でまとめ、記録の操作は 1 つのボタンと 1 行の設定にする
- 内容: 左の一覧を「記録中・今日・昨日・今週・先週・それより前（月ごと）」に分けて出す。一覧の下は「会議の記録を開始」のボタン（記録中は「記録を停止」）と、その下の今の設定の 1 行にする。1 行を押すと、スピーカー・マイク・議事録の型を選べる小さなパネルが出る。
- 受け入れ条件:
  - 一覧の見出しが日付のまとまりになり、各行にタイトル・開始の時刻・長さ、作成中なら回る印、失敗なら「失敗」が出る。
  - 一覧の下に、記録していないときは「会議の記録を開始」、記録中は「記録を停止」、準備中・処理中は進み具合が出る。その下に今の設定（議事録の型・スピーカー・マイク。録音を消すのがオンなら「録音は削除」）の 1 行が出る。1 行を押すとパネルが出て、スピーカー・マイク・議事録の型と、型の管理（REQ-MTG-042）、「文字起こしのあとに録音を削除する」（REQ-MTG-010）を選べる。記録中・処理中は変えられず、記録中は 1 行に記録中の会議の録音の扱いを出し、パネルに「この会議の分は記録中のツールバーで変えられます」と出す。
  - 記録を始められなかったとき（権限・モデル・認証がないなど）は、ボタンの下に理由を出す。
  - 右クリック・⌫ での削除、検索、「質問」は今と同じに使える。
- 出典: 2026-11-09 の依頼「hanasu の会議ノートの UI もモダンに変更したい。どのような UI が良いかを考え、タスクを洗い出して要件を定義し、要件に沿ってモダンな UI を考えて」、同日に計画（docs/plans/meeting-notes-ui.md）を了承。録音を消す設定を足したのは 2026-11-09 の依頼「文字起こしを作成したら録音を削除するというオプションを作成してください。また、後から録音を削除する機能も作成してください」、2026-11-10 に計画（docs/plans/meeting-audio-deletion.md）を了承
- 関係する要件: REQ-MTG-001, REQ-MTG-042, REQ-MTG-010
- 対象: Mac
- 実装の場所: `MeetingWindowView`、`MeetingListGrouping`、`MeetingRow`、`RecordButton`、`RecordSettingsPopover`
- 確かめ方: `.build/debug/Hanasu --test-minutes-document`（日付のまとまり）、`.build/debug/Hanasu --render-meeting-window <フォルダ>`（基準の日時を固定して、今日・昨日・今週・先月の会議を置いた一覧）

### REQ-MTG-052 議事録の要点から、根拠の発言へ移れる
- 内容: 議事録を作るとき、AI に要点ごとに根拠の発言の時刻を付けさせる（Mac と Windows で同じ指示）。Mac の会議ノートでは、議事録の本文とアクションアイテムの時刻を小さな印として出し、押すと文字起こしのその発言へ移って強調する。書き出しでは印を取り除く。
- 受け入れ条件:
  - 議事録のプロンプトに、要点の箇条書きの行末に根拠の発言の時刻を `[12:34]`（1 時間を超えたら `[1:02:34]`）の形で付ける指示と、アクションアイテムの JSON に任意の `"at"` を付ける指示が、17 言語で入る（Mac と Windows で同じ文面）。
  - Mac の会議ノートで、議事録の本文とアクションアイテムの欄に時刻の印が出る。印を押すと、後ろ側のパネルが文字起こしに切り替わり（隠れていれば出し）、その時刻（1 秒の幅を見る）までに始まった最後の発言へスクロールして背景に色を付ける。音声を再生中なら、その位置へ移る（再生していなければ再生は始めない）。
  - 会議の長さを 1 秒より多く超える時刻の印は、薄く出して押せないようにする。
  - 移った先の発言が議事録から除いた発言でも移り、その発言は除いた発言の見た目で出る。
  - ローカルの AI・Apple の AI で文字起こしを部分ごとの要点にまとめてから議事録を作ったとき（DEC-COM-065）は、議事録から時刻の印を取り除いてから保存する。
  - 書き出し（Markdown のコピー・.md / .txt の保存・Slack 向け・リマインダー）には印を入れない。会議フォルダの `minutes.md` と `meeting.json` には残す。Windows 版は、議事録の表示と書き出しで印を取り除く。
  - 引用のない今までの議事録は、今までどおりに読める。AI が実際に印を付ける割合は参考値とし、合否の条件にはしない。
- 出典: 2026-11-09 の依頼「hanasu の会議ノートの UI もモダンに変更したい。どのような UI が良いかを考え、タスクを洗い出して要件を定義し、要件に沿ってモダンな UI を考えて」、同日に計画（docs/plans/meeting-notes-ui.md）を了承。書き出しでは消すこと、Windows にも同じ指示を入れることは、同日に確かめた
- 関係する要件: REQ-MTG-006, REQ-MTG-018, REQ-MTG-019, REQ-COM-061
- 対象: Mac / Windows（Windows は指示と、印を取り除くことだけ）
- 実装の場所: `MinutesCitation`、`MinutesPrompt.systemInstruction`（`minutes.citations`）、`ActionItem.at`、`MeetingExport`、`ReminderExporter`、`MinutesDocumentView`、`MeetingRecorder`（要点にまとめたとき）
- Windows の実装: `windows/Hanasu.Core/Meetings/MinutesCitation.cs`、`windows/Hanasu.Core/Meetings/MinutesTemplate.cs`（`MinutesPrompt`）、`windows/Hanasu.Windows/Views/MeetingWindow.xaml.cs`（議事録の表示とコピーで取り除く）
- 確かめ方: `.build/debug/Hanasu --test-minutes-citations`、`cd windows && dotnet test Hanasu.Core.Tests --filter "FullyQualifiedName~MinutesCitation"`。AI が付ける割合は `--minutes-from-transcript <文字起こし.txt>` で見る

### REQ-MTG-053 残した音声を再生し、再生位置の発言を文字起こしで示す
- 内容: 音声ファイル（`me.m4a`・`others.m4a`）を残した会議では、文書の下に再生のバーを出し、2 つのチャンネルを重ねて再生する（片方ずつ消音できる）。再生中は、今の位置の発言を文字起こしで強調し、その発言が見えるようにスクロールする。文字起こしの発言の時刻を押すと、そこから再生する。
- 受け入れ条件:
  - 再生のバーに、再生・一時停止、15 秒戻る・進む、今の時刻と長さ、位置のスライダー、速さ（1×・1.25×・1.5×・2×）、「自分」「相手」の消音の切り替えがある。スライダーには話者ごとの色で話した区間と、「ここ重要」の印の位置が出る。
  - 再生すると、消音していないチャンネルの声が聞こえ、文字起こしで今の位置の発言の背景に色が付く。強調は、発言の開始の時刻から 0.5 秒以内に移る。ユーザーが文字起こしを手でスクロールしたら自動のスクロールを止め、「再生位置へ」のボタンで戻る。
  - 文字起こしの発言の時刻を押すと、その発言の開始から再生する。スペースキーで再生・一時停止する（文字の入力欄にフォーカスがあるときを除く）。
  - 音声ファイルが両方ない会議・記録中の会議・処理中や議事録の作り直し中の会議では、再生のバーを出さない。片方だけあるときは、ある方だけを再生し、ない方の消音の切り替えを押せなくして、ない方を知らせる。読み込めない音声では「この音声は再生できません」と出し、再生のボタンを押せなくする。
  - 会議を記録している間と音声入力をしている間は、再生を止め、再生のボタンを押せなくして理由を出す。別の会議を選んだ・ウインドウを閉じた・スリープした・アプリを終了したら、再生を止める。
- 出典: 2026-11-09 の依頼「hanasu の会議ノートの UI もモダンに変更したい。どのような UI が良いかを考え、タスクを洗い出して要件を定義し、要件に沿ってモダンな UI を考えて」、同日に計画（docs/plans/meeting-notes-ui.md）を了承。消音を付けることは同日に確かめた
- 関係する要件: REQ-MTG-010, REQ-MTG-002
- 対象: Mac
- 実装の場所: `MeetingPlayer`、`MeetingPlayerBar`、`MeetingInspector`
- 確かめ方: `.build/debug/Hanasu --test-meeting-player`（音声の組み立て・チャンネルのずれ・片方だけ・読めないファイル・時刻から発言を引く・強調が 0.5 秒以内に移る・記録中と音声入力中は押せない）。聞こえ方は実機で確かめる

### REQ-MTG-054 記録中の画面と、記録を止めてから議事録ができるまで
- 内容: 記録中は、真ん中に文字起こし（リアルタイム）、後ろ側のパネルに「メモ｜AI チャット」を出す。記録を止めると、同じ会議を選んだまま、真ん中が議事録の文書に、後ろ側のパネルが「文字起こし｜AI チャット」に替わり、文書の上の帯に処理の進み具合が出る。
- 受け入れ条件:
  - 記録中、ツールバーに記録中の印・経過時間・自分と相手の音量・オフレコ・字幕・この会議の録音を文字起こしのあとに削除（REQ-MTG-010）・パネルの表示の切り替えがある。会議ノートの最小の大きさでも、どれもはみ出しのメニューに隠れない。「★ ここ重要」は後ろ側のパネルの上に、「メモ」「AI チャット」のどちらを選んでいても出る。停止は一覧の下のボタンと、メニュー・ショートカット。
  - 記録中の警告（音が入らないチャンネル）とオフレコ中の知らせは、真ん中の文字起こしの上の帯に出る。「話者の区別は記録を止めたあとに行います」は見出しの下に出る。Whisper / Gemini で記録しているときは、文字起こしの欄に記録を止めたあとに文字起こしすることを出す。
  - 記録中に AI チャットを開いても、真ん中の文字起こしは見えたまま（REQ-MTG-040）。
  - 記録を止めるとき、メモの入力欄に打ちかけの文があれば、止めた時点のメモとして確定してから止める。
  - 記録を止めると、選んでいる会議は変わらず、真ん中が文書になり、上の帯に段階（「文字起こし」（Whisper / Gemini のときだけ）→「話者の区別」→「議事録」）のどこまで進んだかが出る。議事録を作らない設定・使う発言がない会議では「議事録」の段階を出さない。終わると帯が消え、議事録とアクションアイテムが出る。
  - 処理の間、メモの欄は読むだけにし、議事録ができたら書き足せることを出す。
- 出典: 2026-11-09 の依頼「hanasu の会議ノートの UI もモダンに変更したい。どのような UI が良いかを考え、タスクを洗い出して要件を定義し、要件に沿ってモダンな UI を考えて」、同日に計画（docs/plans/meeting-notes-ui.md）を了承。記録中の配置（真ん中に文字起こし）は同日に確かめた。録音を消す切り替えを足したのは 2026-11-09 の依頼「文字起こしを作成したら録音を削除するというオプションを作成してください。また、後から録音を削除する機能も作成してください」、2026-11-10 に計画（docs/plans/meeting-audio-deletion.md）を了承
- 関係する要件: REQ-MTG-003, REQ-MTG-011, REQ-MTG-040, REQ-MTG-046, REQ-MTG-010
- 対象: Mac
- 実装の場所: `LiveTranscriptView`、`LiveSidePanel`、`LiveNotesPanel`、`MeetingRecorder.stop`、`MeetingProcessingStage`、`MeetingStatusBanners`
- 確かめ方: `.build/debug/Hanasu --render-meeting-notes <フォルダ>`（記録中の画面。警告・オフレコ・Whisper の案内）、`.build/debug/Hanasu --render-meeting-window <フォルダ>`（処理中の段階の帯）。記録して止める流れは実機

### REQ-MTG-055 記録した会議の録音だけを、あとから消せる
- 内容: 会議ノートで、記録した会議の録音（音声ファイル）だけを消せる。議事録・文字起こし・メモ・アクションアイテムは残る。消した録音は戻せない。
- 受け入れ条件:
  - Mac: ツールバーの「…」のメニューと一覧の右クリックに「録音を削除…」がある。Windows: 一覧の右クリックと、会議の詳細の上のボタンの並びに「録音を削除…」がある。録音が残っていない会議・記録中や処理中の会議では押せない（Mac はヘルプに理由を出す）。
  - 選ぶと、会議のタイトル・録音の大きさ・「元に戻せません」を書いたダイアログが出る。残るものは文字起こしの状態（DEC-MTG-142）で書き分ける（すべてある・一部だけ・ない）。「削除」で音声ファイルが完全に消える（ゴミ箱に入らない）。キャンセルで何も変わらない。
  - 消したあと、会議は選ばれたままで、文書・文字起こしは読める。会議の帯の「音声ファイルは残しています」は出なくなる。Mac は再生のバーが消える（再生中なら止まる）。設定の件数・合計と録音の管理の一覧も変わる。
  - 議事録の作り直し中も消せる。
  - 消せなかったファイルがあれば、理由を出し、残ったファイルはそのまま。もうなかったファイルは消せたものとして扱う。
- 出典: 2026-11-09 の依頼「文字起こしを作成したら録音を削除するというオプションを作成してください。また、後から録音を削除する機能も作成してください」、2026-11-10 に計画（docs/plans/meeting-audio-deletion.md）を了承
- 関係する要件: REQ-MTG-010, REQ-MTG-028, REQ-MTG-053
- 対象: Mac / Windows
- 実装の場所: `MeetingStore.audioFiles`・`audioSize`・`deleteAudio`、`MeetingRecorder.canDeleteAudio`・`deleteAudio`、`MeetingMoreMenuItems`、`MeetingWindowView`、`MeetingStatusBanners`
- Windows の実装: `windows/Hanasu.Core/Meetings/MeetingStore.cs`（`AudioFiles`・`AudioSize`・`DeleteAudio`）、`windows/Hanasu.Core/Meetings/MeetingController.cs`（`CanDeleteAudio`・`DeleteAudio`）、`windows/Hanasu.Windows/Views/MeetingWindow.xaml.cs`
- 確かめ方: `.build/debug/Hanasu --test-meeting-audio`（録音だけが消える・4 つのファイル名・もうないファイル・記録中の会議は消さない・文字起こしの状態）、`.build/debug/Hanasu --render-meeting-window <フォルダ>` の `more-menu.png`（録音あり）と `more-menu-no-audio.png`。Windows: `cd windows && dotnet test Hanasu.Core.Tests --filter "FullyQualifiedName~MeetingAudioDeletionTests"`。再生のバーが消えることは実機

### REQ-MTG-056 録音の管理の画面で、選んで・30 日より前・すべての録音を消せる
- 内容: 録音が残っている会議を一覧する「録音の管理」の画面で、選んだ会議・30 日より前に記録した会議・すべての会議の録音をまとめて消せる。消すのは録音だけ。文字起こしがそろっていない会議は、まとめて消す対象から外す。
- 受け入れ条件:
  - 入口: 設定「会議」の「録音を管理…」（横に今残っている録音の件数と合計の大きさ。文字起こしがそろっていない会議があればその件数も）。Mac は会議ノートの「…」のメニュー、Windows は会議ノートの一覧の右クリックの「録音の管理…」からも開ける。
  - 録音が残っている会議が新しい順に、チェックボックス・タイトル・記録した日時・大きさで並ぶ。記録中・処理中の会議は並ばない。文字起こしがない会議には「文字起こしなし」、一部だけの会議には「一部の文字起こしなし」の印が付く。
  - 「選んだ録音を削除…」（1 件も選んでいなければ押せない）、「30 日より前の録音を削除…」、「すべての録音を削除…」がある。後の 2 つは印の付いた会議を含めず、当てはまる会議がなければ押せない。
  - どれも、消す件数・合計の大きさ・「元に戻せません」を書いたダイアログで確かめる（Windows の確かめは OK／キャンセル）。選んだ中に印の付いた会議があれば、その件数と「その分の会話の記録は残りません」を書く。「30 日より前」「すべて」で外した会議があれば、その件数と大きさを書く。
  - 「30 日より前」は、記録を始めた日時が今から 30×24 時間より前の会議。
  - 消せなかったファイルがあれば件数を出し、残ったものは一覧に残す。画面を開いている間に会議の一覧が変わったら読み直す。
  - 画面の下に、同期するフォルダ（iCloud Drive・OneDrive など）に保存していると同期先の削除済みの項目に残ることがある、と出す。
- 出典: 2026-11-09 の依頼「文字起こしを作成したら録音を削除するというオプションを作成してください。また、後から録音を削除する機能も作成してください」、2026-11-10 に計画（docs/plans/meeting-audio-deletion.md）を了承（「選んで消す」は専用の画面で、失敗した会議はまとめて消す対象から外す、と 2026-11-09 に確かめた）
- 関係する要件: REQ-MTG-055, REQ-MTG-057
- 対象: Mac / Windows
- 実装の場所: `MeetingAudioManagerView`、`MeetingAudioCleanup`、`SettingsView`、`MeetingMoreMenuItems`
- Windows の実装: `windows/Hanasu.Core/Meetings/MeetingAudioCleanup.cs`、`windows/Hanasu.Windows/Views/MeetingAudioWindow.cs`、`windows/Hanasu.Windows/Views/SettingsWindow.xaml.cs`、`windows/Hanasu.Windows/Views/MeetingWindow.xaml.cs`
- 確かめ方: `.build/debug/Hanasu --test-meeting-audio`（30 日の境目・選んだものだけ・すべて・記録中と印の付いた会議を除く）、`.build/debug/Hanasu --render-meeting-audio-manager <出力フォルダ>`。Windows: `cd windows && dotnet test Hanasu.Core.Tests --filter "FullyQualifiedName~MeetingAudioDeletionTests"`

### REQ-MTG-057 決めた日数より前の録音を、自動で消せる
- 内容: 設定の「録音を残す期間」で、その日数より前に記録した会議の録音を自動で消す。既定は「無期限」（消さない）。文字起こしがそろっていない会議は消さない。
- 受け入れ条件:
  - 設定「会議」に「録音を残す期間」があり、「無期限」（既定）・7 日・30 日・90 日・365 日から選べる。説明に、会議ごとに「残す」にした録音も期間を過ぎると消えること、文字起こしがそろっていない会議の録音は消さないことを出す。
  - 無期限以外のとき、アプリの起動時と会議の記録の後処理が終わったときに、記録を始めた日時がその日数より前の会議の録音を、知らせずに消す（ログには件数を書く）。記録中・処理中の会議と、文字起こしがそろっていない会議は消さない。
  - 期間を変えたとき、今すぐ消える録音があれば、件数・合計の大きさ・「元に戻せません」・（あれば）残す会議の件数を書いたダイアログで確かめる。「変更して削除」（Windows は「OK」）で設定を変えて消し、キャンセルで設定を元に戻す。
- 出典: 2026-11-09 の依頼「文字起こしを作成したら録音を削除するというオプションを作成してください。また、後から録音を削除する機能も作成してください」、2026-11-10 に計画（docs/plans/meeting-audio-deletion.md）を了承（「30 日以前の録音を消す」は押して消すと自動で消すの両方、と 2026-11-09 に確かめた。文字起こしがそろっていない会議を除くこと・会議ごとの「残す」より期間が強いことは、計画の「仮に決めたこと」として了承された）
- 関係する要件: REQ-MTG-056, REQ-MTG-010
- 対象: Mac / Windows
- 実装の場所: `AppSettings.meetingAudioRetentionDays`、`MeetingAudioCleanup.expired`、`MeetingRecorder.pruneExpiredAudio`、`AppDelegate`、`SettingsView`
- Windows の実装: `windows/Hanasu.Core/Settings/AppSettings.cs`（`MeetingAudioRetentionDays`）、`windows/Hanasu.Core/Meetings/MeetingAudioCleanup.cs`、`windows/Hanasu.Core/Meetings/MeetingController.cs`（`PruneExpiredAudio`）、`windows/Hanasu.Windows/AppHost.cs`、`windows/Hanasu.Windows/Views/SettingsWindow.xaml.cs`
- 確かめ方: `.build/debug/Hanasu --test-meeting-audio`（期間ごとの境目・無期限は消さない・印の付いた会議と記録中を除く）。Windows: `cd windows && dotnet test Hanasu.Core.Tests --filter "FullyQualifiedName~MeetingAudioDeletionTests"`

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
- 決めたこと: 録音を消す会議（REQ-MTG-010）でも、文字起こしに失敗したチャンネルがあれば音声ファイルを消さない。失敗したチャンネルは、消す設定かどうかに関わらず `meeting.json` の `transcriptionFailedChannels` に書く（DEC-MTG-142）。Mac 標準のエンジンでは、記録中に認識の結果のストリームがエラーで止まったチャンネル（取り消しを除く）も失敗に数える（止めるときの締めのエラーは数えない）。「音声ファイルは残しています」はエラーの文に入れず、録音が残っていれば表示のときに帯に出す（DEC-MTG-140）。消すのは後処理の最後（文字起こし・話者分離・議事録のあと）。
- 理由: あとで文字起こしし直せるようにする。
- 決めた場面: PR #17。Mac 標準のエンジン・`transcriptionFailedChannels`・表示のときに決めることは 2026-11-10 の録音の削除（docs/plans/meeting-audio-deletion.md）で足した。Mac 標準の締めのエラーを数えないのは、手元のログで頻度を確かめられず、止めるたびに出るなら録音を残し続けることになるため
- 関係する要件: REQ-MTG-010
- 対象: Mac / Windows
- 実装の場所: `MeetingRecorder.process`、`MeetingRecorder.transcribeRecordedAudio`、`ChannelTranscriber`
- Windows の実装: `windows/Hanasu.Core/Meetings/MeetingPostProcessor.cs`

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
- 決めたこと: 議事録のモデルの初期値は `gemini-3.8-flash`。音声入力と同じ `GeminiClient` と認証を使う。出力は概要・話題ごとの要点・決定事項・アクションアイテム・話者についてのメモ（推定であることを明記する）。会話から名前がはっきり分かる話者には、同じ応答で名前も受け取って付ける（REQ-MTG-027、DEC-MTG-068）。
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

### DEC-MTG-016 録音は、既定では残す
- 決めたこと: 「文字起こしのあとに録音を削除する」（以前の「音声ファイル（me.m4a / others.m4a）を残す」の裏返し。キー `keepMeetingAudio` / `KeepMeetingAudio` は変えない）の初期値はオフ（残す）。「録音を残す期間」の初期値は「無期限」。
- 理由: 初版のコードの初期値。文書には「設定で処理後に削除可」とだけあり、既定が書かれていなかった。あとで文字起こしし直したり、聞き直したりできる。今回、暗黙の振る舞いから設計判断に格上げして記録した。
- 決めた場面: 初版（a787da8）のコード。記録はこの PR
- 関係する要件: REQ-MTG-010
- 対象: Mac / Windows
- 実装の場所: `AppSettings`（`keepMeetingAudio`・`meetingAudioRetentionDays` の初期値）
- Windows の実装: `windows/Hanasu.Core/Settings/AppSettings.cs`

### DEC-MTG-017 会議ごとのフォルダの中身
- 決めたこと: `~/Documents/Hanasu/Meetings/<日付 時刻 タイトル>/` に `meeting.json`（メタデータ・話者名の対応表・発言・議事録の型・アクションアイテム・メモ・録音を消すか `deleteAudioAfterTranscription`・文字起こしに失敗したチャンネル `transcriptionFailedChannels`）、`transcript.md`、`minutes.md`、`notes.md`（メモがあるときだけ）、`me.m4a`・`others.m4a`（AAC 16kHz モノラル）を置く。
- 理由: Markdown なので他のツールでも読める（REQ-MTG-025）。
- 決めた場面: 初版（a787da8）。項目は PR #10、#13 で足した
- 関係する要件: REQ-MTG-005, REQ-MTG-025
- 対象: Mac
- 実装の場所: `MeetingStore.save`、`Meeting`

### DEC-MTG-018 途中で落ちた会議は、起動時に「失敗」にする
- 決めたこと: 起動時に、アプリの終了などで「記録中」「処理中」のまま残った会議を「失敗」にする。エラーのときも、それまでの録音・文字起こしは保存する。録音を消す会議でも録音は残し、「音声ファイルは残しています」は録音があれば表示のときに出す（エラーの文には入れない。DEC-MTG-140）。
- 理由: 一覧に「記録中」のまま残り続けないようにする。
- 決めた場面: 実機で録音されなかった問題の修正（2026-11-02）
- 関係する要件: REQ-MTG-007
- 対象: Mac / Windows
- 実装の場所: `MeetingStore.markInterruptedMeetings`
- Windows の実装: `windows/Hanasu.Core/Meetings/MeetingStore.cs`（`MarkInterruptedMeetings`）

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

### DEC-MTG-022 会議の削除は、フォルダごとゴミ箱に移し、先に確かめる
- 決めたこと: 削除は、会議のフォルダを丸ごと Mac のゴミ箱（Windows のごみ箱）に移す。完全には消さない。押す前に、会議のタイトルと「ゴミ箱から戻せる」ことを書いたダイアログで確かめる。入口は、一覧の右クリックの「削除…」、一覧を選んで ⌫（Windows は Delete キー）、Mac はツールバーの「…」のメニューの「削除…」（DEC-MTG-131）、Windows は会議の詳細の上のゴミ箱のボタン。消したあとは一覧の次の会議を選ぶ。録音だけを消す操作（REQ-MTG-055〜057）は DEC-MTG-140 で、ゴミ箱に入れずに消す。
- 理由: 会議の記録は取り直せないので、押し間違えても戻せるようにする。フォルダの中身（音声・メモ）を 1 つずつ消すと、取り残しや、消しかけのフォルダが残るおそれがある。
- 決めた場面: ユーザーの依頼（2026-11-04）。この PR
- 関係する要件: REQ-MTG-028
- 対象: Mac / Windows
- 実装の場所: `MeetingStore.moveToTrash`、`MeetingWindowView`
- Windows の実装: `windows/Hanasu.Windows/Views/MeetingWindow.xaml.cs`（`Microsoft.VisualBasic.FileIO.FileSystem.DeleteDirectory` の `RecycleOption.SendToRecycleBin`）

### DEC-MTG-023 記録中・処理中・議事録の作り直し中の会議は消せず、消した会議を保存し直さない
- 決めたこと: 記録中・記録のあとの処理中の会議と、議事録を作り直している会議は、削除の操作を出さない（押せない）。また、会議を書き換えて保存する処理（タイトル・話者名・リマインダーの印など）は、その会議のフォルダがもうなければ保存しない。
- 理由: 処理の最後の保存は、フォルダがなければ作り直すので、処理中に消すと、消したはずの会議が中途半端な形で戻ってくる。
- 決めた場面: この PR
- 関係する要件: REQ-MTG-028
- 対象: Mac / Windows
- 実装の場所: `MeetingRecorder.canDelete`・`update`
- Windows の実装: `windows/Hanasu.Core/Meetings/MeetingController.cs`（`CanDelete`）

### DEC-MTG-024 タイトルの欄は、いつも枠と鉛筆の印を出し、フォーカスが外れたときも保存する
- 決めたこと: 会議の詳細の上のタイトルの欄に、いつも薄い枠と鉛筆の印を出す。マウスを載せると枠を濃くし、編集中はアクセントの色の枠にする。Enter・フォーカスが外れたときに保存し、空なら元に戻す。Esc で書き換えをやめる。別の会議を選んだときは、書きかけのタイトルを元の会議に保存してから切り替える。
- 理由: 前は枠のない文字の欄で、見出しと見分けがつかず、書き換えられることが分からなかった（ユーザーの依頼（2026-11-04））。Mac では Enter のときしか保存しなかったので、書き換えてほかをクリックすると、変えたつもりのタイトルが保存されなかった。
- 決めた場面: ユーザーの依頼（2026-11-04）。この PR
- 関係する要件: REQ-MTG-029
- 対象: Mac / Windows
- 実装の場所: `EditableTitleField`、`MeetingDetailView.commitTitle`
- Windows の実装: `windows/Hanasu.Windows/Views/MeetingWindow.xaml`（`TitleBox` のスタイル）

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

### DEC-MTG-035 会議の名前は、ウインドウのタイトルをアクセシビリティで読んで取り出す
- 決めたこと: 記録を始めるとき、マイクを使っている会議アプリのウインドウのタイトルを `kAXTitleAttribute` で読み（前面のウインドウから順に）、アプリごとの決まりで名前を取り出す。Teams は末尾の「| Microsoft Teams」を除いた残り、Meet は「<名前> - Google Meet」または「Meet - <名前>」、Webex は末尾の「| Webex」を除いた残り。ブラウザのタイトル末尾（- Google Chrome など）は先に除く。Teams の画面名（Chat・Calendar など）や Meet の会議コード（abc-defg-hij）だけのものは名前とみなさない。Zoom・Slack・FaceTime はウインドウに名前が出ないので対象外。名前は 100 文字までにする。アクセシビリティが未許可なら読まない（許可は求めない）。読むのは別スレッドで、各アプリへの問い合わせは 0.5 秒で切る。読むのは記録の準備中（`.starting`）なので、その間にもう一度押しても二重には始まらない。フォーカス・メインのウインドウを先に見る。マイクを使っているアプリを対象にし、会議の自動検出をオフにしているときは対象のアプリすべてを見る。
- 理由: 画面収録の許可（`CGWindowList` のウインドウ名に要る）は、会議の記録では REQ-MTG-030 のとおり求めない。アクセシビリティは音声入力の貼り付けのために元から案内している許可で、追加の求めが要らない。タブの URL は読まない（DEC-MTG-031）。会議の名前と言い切れないときは、誤ったタイトルを付けるより日時のタイトルにする。
- 決めた場面: ユーザーの依頼（2026-11-05）。PR #66
- 関係する要件: REQ-MTG-034
- 対象: Mac
- 実装の場所: `MeetingTitle.extract`、`MeetingTitle.detect`

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
- 決めたこと: 1 行 1 件で、`[12:34] 内容`（メモ）、`[12:40] ★ 説明`（印）、時刻なしの行（記録後に足したメモ）。会議ノートのメモの欄（Mac は文書の中、Windows は「メモ」タブ）・`notes.md`・CLI の `--notes` で同じ形式を使う。
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

### DEC-MTG-047 「ここ重要」の取り消しは、付けてから 10 秒以内のいちばん新しい印だけ
- 決めたこと: 記録中に取り消せるのは、録音開始からの経過時間で付けてから 10 秒以内（ちょうど 10 秒まで）の印のうち、いちばん新しいもの。会議ノートのメモ欄に「★ を取り消す（あと N 秒）」を出し（Mac は字幕のパネルにも「取り消す」）、押すと `meeting.json` から消してすぐ保存する。10 秒を過ぎた印は、記録中には消せない（Mac の右クリックの「削除」もメモだけにし、印は 10 秒以内のときだけ「取り消す」を出す）。記録のあとはメモの欄のテキストで消せる（DEC-MTG-044）。ショートカットでの取り消しは作らない。
- 理由: 依頼は押し間違いのやり直し。古い印まで記録中に消せると、会議ツールを見ながら押したつもりの印を誤って消しやすい。記録のあとならテキストでまとめて直せる。同じショートカットを 2 回押して取り消す形は、続けて 2 つ印を付けたいときと区別できないので採らなかった。
- 決めた場面: ユーザーの依頼（2026-11-04「会議のここ重要を削除できないので削除できるようにして。10秒前まで削除できるようにして」。付けてから 10 秒のあいだ取り消せる、という意味だとユーザーに確かめた）
- 関係する要件: REQ-MTG-012
- 対象: Mac / Windows
- 実装の場所: `Meeting.undoableHighlight(at:)`、`MeetingRecorder.undoHighlight`・`removeNote`、`HighlightUndoButton`、`LiveNotesPanel`、`MeetingCaptionView`
- Windows の実装: `windows/Hanasu.Core/Meetings/MeetingModels.cs`（`Meeting.UndoableHighlight`・`HighlightUndoSeconds`）、`windows/Hanasu.Core/Meetings/MeetingController.cs`（`UndoableHighlight`・`UndoHighlight`）、`windows/Hanasu.Windows/Views/MeetingWindow.xaml`・`MeetingWindow.xaml.cs`（`UndoHighlightButton`）

### DEC-MTG-048 会議ノートのウインドウ（Mac）は、大きさを中身に合わせない
- 決めたこと: 会議ノートのウインドウの `NSHostingController` の `sizingOptions` を空にし、ウインドウの最小の大きさ（1040×560。DEC-MTG-130）は `contentMinSize` で決める。文書のメモの欄のテキスト欄には最小の高さ（120）と最大の高さ（360）を決め、中でスクロールさせる。説明文は高さを中身に合わせて固定せず（`fixedSize` にしない）、3 行までにする。
- 理由: 中身に合わせる設定のままだと、「メモ」タブのテキスト欄がメモの全行ぶんの高さを最小として求め、ウインドウが画面より縦に伸びて（メモ 60 行で高さ 672 → 1441）、タイトルとタブの切り替えが画面の外に出て、議事録・文字起こしに戻れなくなっていた（ユーザーの依頼（2026-11-04「重要の秒数付近の会話をかくにんできるようにして。あと、mac版では会議メモを開くと足袋などが消失して文字起こしや要約のページに戻れないので修正して」））。
- 理由（説明文）: 説明文を `fixedSize`（縦）にしていると、左右に並べる画面（`NavigationSplitView`）が細い幅で最小の高さを測ったとき、1 文字ずつ折り返した高さ（約 1500）を求めた。ウインドウは伸びなくなったが、中身がウインドウより縦に大きくなって（中身 1529／ウインドウ 640）上下が画面の外に出て、タイトル・タブの切り替え・左の検索欄・記録のボタンが見えなくなっていた。メモの行数にはよらない（メモ 2 行の会議でも起きた）（ユーザーの依頼（2026-11-04「メモタブを押したらこうなってしまい、元に戻せません」））。
- 決めた場面: 同じ依頼の修正。説明文は 2026-11-04 の 2 つめの依頼の修正。最小の大きさとメモの欄の置き場所は 2026-11-09 の会議ノートの UI の作り直し（docs/plans/meeting-notes-ui.md）で変えた
- 関係する要件: REQ-MTG-007
- 対象: Mac
- 実装の場所: `AppDelegate.makeMeetingWindow`、`MeetingNotesEditor`

### DEC-MTG-049 印の前後の会話は「ここ重要」タブにまとめ、範囲は議事録と同じにする
- 決めたこと: 印ごとに時刻・説明と、その 30 秒前〜15 秒後にかかる発言（まとめた発言の単位）を時刻の順に出す。範囲は議事録で重要として扱う範囲（DEC-MTG-041）と同じ。時刻のない印（記録後にメモで書き足したもの）は出さない。Mac は会議ノートの文書の「ここ重要」の欄に出し、印ごとに「前後の会話を見る」を置き、後ろ側のパネルの文字起こしのその発言へ移って強調する。Windows は「ここ重要」タブに、同じ内容を読むだけの文章で出す。
- 理由: 依頼は印を付けた秒数の付近の会話を確かめること。印ごとにまとまっていれば、文字起こしを探さずに見比べられる。議事録で ★ を付ける範囲と同じにすると、議事録の「重要とした箇所」が何から作られたかを確かめられる。
- 決めた場面: ユーザーの依頼（2026-11-04「重要の秒数付近の会話をかくにんできるようにして。あと、mac版では会議メモを開くと足袋などが消失して文字起こしや要約のページに戻れないので修正して」）
- 関係する要件: REQ-MTG-012
- 対象: Mac / Windows
- 実装の場所: `Meeting.highlightContexts`、`HighlightContextsView`、`MeetingDetailView`
- Windows の実装: `windows/Hanasu.Core/Meetings/MeetingModels.cs`（`HighlightContexts`・`HighlightContextText`）、`windows/Hanasu.Windows/Views/MeetingWindow.xaml`・`MeetingWindow.xaml.cs`（`HighlightsBox`）

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
- 決めたこと: JSON が読めないときと、この機能より前の議事録（「## TODO」の行）は、チェックボックスの行から読み取る。読む前に、行末の時刻の印（DEC-MTG-134）を取り除く。
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

### DEC-MTG-066 保存とコピーは、書き出しのメニューで議事録か文字起こしを選ぶ
- 決めたこと: Markdown のコピーと .md / .txt の保存は、書き出しのメニューで「議事録」「文字起こし」を名前で選ぶ（タブがなくなったため。2026-11-09 の会議ノートの UI の作り直し（docs/plans/meeting-notes-ui.md）で変えた）。議事録の時刻の印は取り除く（DEC-MTG-134）。.txt は見出しを【】、箇条書きを「・」、チェックボックスを「□」にし、太字などの記号を外す。Slack 向けとリマインダーは議事録だけ。
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

### DEC-MTG-068 話者の名前は、議事録と同じ 1 回の呼び出しで、末尾の <speaker_names> の JSON で受け取る
- 決めたこと: 議事録の指示（`MinutesPrompt`）の最後に、名前の付いていない話者（「話者N」「同席者N」「相手」）のうち会話から名前がはっきり分かるものだけを `<speaker_names>{"話者1": "田中"}</speaker_names>` で出させる指示を足す。名乗った・自己紹介した・名前で呼びかけられて本人が応じた、などはっきり分かるときだけで、敬称は付けさせない。「自分」は入れさせない。応答を読むときは、`<speaker_names>` を `<action_items>` より先に取り出して本文から消す（壊れていたら名前は付けず、議事録はそのまま使う）。Windows 版は文字起こしとメモの中の `<speaker_names>` も無害にする（DEC-COM-142）。（ラベルと例の文面は、プロンプトの言語のもの。多言語化の PR で変えた。DEC-COM-163）
- 理由: 議事録を作るときに文字起こし全体を読ませているので、呼び出しを増やさずに済み、料金もローカル LLM の待ち時間も増えない。アクションアイテム（DEC-MTG-062）と同じ形にすると、読み取りの作りをそろえられる。議事録を作らない設定（DEC-MTG-015）では名前も付かないが、名前は議事録の材料と同じ読み取りから出るので、別の呼び出しは作らなかった。
- 決めた場面: 話者の名前を推測して付ける PR
- 関係する要件: REQ-MTG-027
- 対象: Mac / Windows
- 実装の場所: `MinutesPrompt.speakerNamesInstruction`、`MinutesPrompt.parse`、`SpeakerNameInference.extract`
- Windows の実装: `windows/Hanasu.Core/Meetings/MinutesTemplate.cs`（`SpeakerNamesInstruction`・`Parse`）、`windows/Hanasu.Core/Meetings/SpeakerNameInference.cs`（`Extract`）、`windows/Hanasu.Core/Ai/PromptText.cs`

### DEC-MTG-069 推測した名前は、名前のない話者にだけ付け、議事録のラベルも置き換え、推測の印を残す
- 決めたこと: 応答のラベル（「話者1」など）を、まだ名前のない話者キー（「自分」を除く）に戻して名前を付ける。ユーザーが付けた名前と、前に付けた名前は変えない。名前は前後の空白と末尾の敬称（さん・様・さま・くん・君・ちゃん・氏）を外し、1〜20 文字で、改行・制御文字がなく、「自分」「相手」「話者N」「同席者N」「不明」などそのものでないものだけを使う。同じ名前が 2 人に付くのは許す。付けた話者キーを `meeting.json` の `inferredSpeakers`（省略可。Mac 版と Windows 版で同じキー）に入れ、話者名の画面で「推測」と出す。ユーザーが名前を直すか消すと印を外す。議事録の本文とアクションアイテムの担当の中のラベルも名前に置き換える（「話者1」は後ろに数字が続くとき置き換えない）。「相手」はふつうの言葉でもあるので、本文は置き換えず、担当がちょうど「相手」のときだけ置き換える。（ラベルと例の文面は、プロンプトの言語のもの。多言語化の PR で変えた。DEC-COM-163）
- 理由: ユーザーが直した名前を AI で上書きしない。議事録は作った時点の名前で書く作り（REQ-MTG-008 の「作り直すと反映」）なので、作った直後から文字起こしと議事録の名前をそろえる。推測は間違えうるので、印を残して直しやすくする。話者分離は 1 人を 2 つに分けることがあるので、同じ名前を許す。Mac 版の話者名の画面は、1 人ずつ保存すると元の会議から書き直して前の変更が消えるので、まとめて保存する（`MeetingRecorder.renameSpeakers`）。
- 決めた場面: 話者の名前を推測して付ける PR
- 関係する要件: REQ-MTG-027, REQ-MTG-008
- 対象: Mac / Windows
- 実装の場所: `SpeakerNameInference.apply`・`cleanName`・`replaceLabel`、`Meeting.renameSpeaker`・`isInferredName`、`SpeakerNamesSheet`
- Windows の実装: `windows/Hanasu.Core/Meetings/SpeakerNameInference.cs`（`Apply`・`CleanName`・`ReplaceLabel`）、`windows/Hanasu.Core/Meetings/MeetingModels.cs`（`InferredSpeakers`・`RenameSpeaker`・`IsInferredName`）、`windows/Hanasu.Windows/Views/MeetingWindow.xaml.cs`

### DEC-MTG-070 処理が終わっても会議の選択を変えず、作り直し中は会議ごとに印を出す
- 決めたこと: 会議ノートの一覧の選択は、記録を始めたときだけその会議に移す。記録のあとの処理や議事録の作り直しが終わっても選び直さない（記録中の会議と保存した会議は同じ ID なので、記録のあとも選んだまま議事録が出る）。作り直している会議は `MeetingRecorder.regeneratingID` で持ち、その会議の詳細の上に回る印と処理の文言を出し、今の議事録は薄く出したままにする。一覧では、その会議（記録のあとの処理中は記録中の会議）の印を回る印にする。
- 理由: 以前は処理が終わると一覧の先頭を選んでいて、作り直しのたびに別の会議へ移っていた。記録の状態（`state`）だけでは、どの会議を作り直しているかがわからず、作り直していない会議を開いていても同じ表示になる。今の議事録を消さずに薄く出すのは、作り直しに失敗したときは元の議事録が残る（DEC-MTG-061）ため。
- 決めた場面: 作り直しで選択が先頭に移る問題の修正（2026-11-04 のユーザーの依頼）
- 関係する要件: REQ-MTG-013, REQ-MTG-007
- 対象: Mac
- 実装の場所: `MeetingWindowView`、`MeetingRow`、`MeetingDetailView`、`MeetingRecorder.regenerateMinutes`

### DEC-MTG-071 会議の一覧の読み込みは、メインスレッドの外で行う
- 決めたこと: `MeetingRecorder.meetings` の元になる `MeetingStore.loadAll()`（全会議の `meeting.json` の読み込みと復号）は、起動時と `reloadMeetings()`（名前の変更・編集・削除など）のたびに、裏のタスクで行い、結果だけをメインに戻す。読み終えるまでは前の一覧を出したままにする（空にしない。起動直後だけ空で、読み終えたら入る）。続けて呼ばれたときは、呼び出しごとの番号（`reloadGeneration`）が最新のものの結果だけを使い、古い読み込みが新しい一覧を上書きしないようにする。
- 理由: 会議が増えると、読み込みがメインスレッドを止めて、会議ノートの操作や起動が引っかかる。一覧が少し遅れて出ても、使い方は変わらない。
- 決めた場面: PR #65
- 関係する要件: REQ-MTG-007
- 対象: Mac / Windows
- 実装の場所: `MeetingRecorder.reloadMeetings`
- Windows の実装: `windows/Hanasu.Windows/Views/MeetingWindow.xaml.cs`（`ReloadList`。`MeetingStore.LoadAll` を `Task.Run` で読み、番号 `reloadGeneration` が最新のときだけ一覧に出す。会議ノートを開いた直後だけ空。読めなかったときは前の一覧のまま。ウィンドウを閉じたあとに読み終えた結果は出さない。起動時の `MeetingStore.MarkInterruptedMeetings` は、記録を始める前に済ませる書き込みなので同期のまま）

### DEC-MTG-072 議事録を作り直す前に、今の議事録があるときだけ確かめる
- 決めたこと: 「議事録を作り直す」「保存して議事録を作り直す」は、その会議に今の議事録があるときだけ「議事録を作り直しますか？ 今の議事録とアクションアイテムは置き換わります。」と確かめる（型を変えるときの確認は DEC-MTG-061 のまま。Windows 版は既定のボタンをキャンセルにそろえた）。議事録がまだない（作成に失敗した）ときは、置き換わるものがないので尋ねずに作る。「保存して議事録を作り直す」でキャンセルしたときは、メモの保存もしない（「保存」のボタンは別にある）。
- 理由: 作り直すと今の議事録は残らず（DEC-MTG-061 は失敗したときだけ元のまま）、手で直したい箇所を書き留める前に押すと戻せない。型を変えるときだけ確認があり、同じ結果になるボタンに確認がないのは一貫しない（UX-096）。一方、議事録がないときまで尋ねると、失敗のあとにもう一度作る操作が重くなる。
- 決めた場面: PR #65 の判断事項の対応（2026-11-05 のユーザーの依頼「判断して実装して」）
- 関係する要件: REQ-MTG-013, REQ-MTG-017
- 対象: Mac / Windows
- 実装の場所: `MeetingDetailView`（`confirmRegenerate`）、`MeetingNotesEditor.saveAndRegenerate`
- Windows の実装: `windows/Hanasu.Windows/Views/MeetingWindow.xaml.cs`（`ConfirmRegenerate`）

### DEC-MTG-073 Windows 版の会議の一覧が空のときは、読み込み中と 0 件の案内を出す
- 決めたこと: 会議ノートの左の一覧の上に、一覧が空のときだけ案内を重ねる（履歴の `EmptyText` と同じ作り）。開いた直後の読み込み中（DEC-MTG-071）は「会議の一覧を読み込んでいます…」、読み終えて 0 件なら「まだ会議の記録がありません。左下の「● 会議の記録を開始」で記録を始めると、ここに並びます。」、読めなかったときは「会議の一覧を読み込めませんでした。」。
- 理由: 一覧の読み込みを裏に移した（DEC-MTG-071）ので、開いた直後は空に見える。空の理由（読み込み中なのか、まだ記録していないのか）が分からないと、新しいユーザーは次に何をするかが分からない（UX-040 の履歴と同じ）。
- 決めた場面: PR #65 の判断事項の対応（2026-11-05）
- 関係する要件: REQ-MTG-007, REQ-COM-011
- 対象: Windows
- 実装の場所: `windows/Hanasu.Windows/Views/MeetingWindow.xaml`（`ListEmptyText`）、`windows/Hanasu.Windows/Views/MeetingWindow.xaml.cs`（`ReloadList`）

### DEC-MTG-074 システムオーディオ録音の許可は、状態を出さずに、求められる時機と直す場所を案内する
- 決めたこと: 会議の記録で相手の声を録る Core Audio のプロセスタップ（DEC-MTG-002）には「システムオーディオ録音」の許可が要り、初めてタップを作るときに macOS が求める。許可の状態を取る公開 API がないので、設定の「権限」タブには状態の代わりに「初めて会議の記録を始めるときに macOS が求めます」と、拒否したときに直す場所（システム設定 → プライバシーとセキュリティ → 画面収録とシステムオーディオ録音）と「開く…」のボタン（`Privacy_AudioCapture`）を出す。オンボーディングの許可のページにも、同じことを 1 行で添える。タップの作成に失敗したときのエラー文にも、確かめる場所を添える。
- 理由: マイク・音声認識・アクセシビリティは権限タブとオンボーディングに並ぶのに、システムオーディオ録音だけどこにも書かれておらず、拒否したあとに「システム音声を取得できませんでした（AudioHardwareCreateProcessTap: …）」としか出なかった（PR #65 のレビュー）。状態を出せないものを「未許可」と見せると、まだ求められていないだけの人を惑わせる。
- 決めた場面: PR #65 の判断事項の対応（2026-11-05）
- 関係する要件: REQ-MTG-002, REQ-COM-051
- 対象: Mac
- 実装の場所: `SettingsView.swift`（`PermissionsTab`）、`OnboardingPermissionsPage`、`SystemAudioTapError`

### DEC-MTG-075 黄色の「ここ重要」のボタンは、文字を黒にする。ほかの意味の色はシステムの色のまま
- 決めたこと: 会議ノートと字幕の「★ ここ重要」のボタン（`.borderedProminent` に `.tint(.yellow)`）は、文字と星を白ではなく黒にする。辞書の警告の三角も黄から橙にする。印の星（`.yellow`）、録音中の赤、警告・エラーの橙、成功の緑はシステムの意味の色のまま（macOS の「コントラストを上げる」に従って濃くなる）。
- 理由: 黄色の面に白い文字はコントラストが約 1.3:1 で、押せるボタンの文字としては読めない（WCAG の 4.5:1 に遠い）。黒なら約 13:1。ほかの意味の色は文字やアイコンと一緒に出していて色だけに頼っておらず、固定の色（`Color(red:…)`）ではなくシステムの色なので、アクセシビリティの設定で変わる。
- 決めた場面: PR #65 の判断事項の対応（2026-11-05）
- 関係する要件: REQ-MTG-012, REQ-MTG-014
- 対象: Mac
- 実装の場所: `LiveNotesPanel`・`MeetingCaptionView`（`MeetingNotesViews.swift`）、`DictionarySettingsView`

### DEC-MTG-076 保存したテンプレートは UserDefaults に JSON で置き、会議には指示を写して「カスタム」の型で作る
- 決めたこと: 保存したテンプレート（ID・名前・指示）は、UserDefaults の `meetingSavedMinutesTemplates` に JSON の配列で置く。記録の前の選択は、既存の `meetingMinutesTemplate` に `saved:<ID>` の形で入れる。記録を始めるとき、会議には型「カスタム」・その時点の指示（`customMinutesPrompt`）・テンプレートの名前（`minutesTemplateName`）を写す。議事録の作り方は、既存のカスタムの型（DEC-MTG-060）と同じ。Windows 版は `meeting.json` の `minutesTemplateName` を読み書きで落とさない（画面は FUT-205）。名前は前後の空白を取り、大文字小文字を区別せず重複を禁止する。管理のシートは、保存できる内容になったときに自動で保存し、保存できない間は理由を出して保存しない。
- 理由: 選んだ型の保管場所と同じ UserDefaults にそろえ、共有の設定ファイルを変えずに済む（DEC-MTG-061）。会議に指示を写すので、あとでテンプレートを直したり消したりしても、その会議の作り直しや記録済みの議事録が変わらず、`meeting.json` だけで再現できる。作り方を「カスタム」と同じにしたので、プロンプトの組み立てと読み取りは変えていない。型は ID で持つので、名前を直しても選択は外れない。
- 決めた場面: 名前付きテンプレートの依頼（2026-11-05）、PR #67
- 関係する要件: REQ-MTG-042
- 対象: Mac
- 実装の場所: `SavedMinutesTemplateStore`、`MinutesTemplateStore.resolve`・`apply`、`Meeting.minutesTemplateName`・`templateTitle`、`MeetingRecorder.regenerateMinutes`

### DEC-MTG-080 チャットは、記録中の画面の右側を「メモ」「AI チャット」で切り替えて出す
- 決めたこと: 記録中の画面の右側（メモ欄）の上に「メモ｜AI チャット」の切り替えを置き、AI チャットは同じ場所に出す。文字起こしは左に出したままにする。字幕と「ここ重要」のボタンは、どちらを選んでいても上に出す。右側は後ろ側のパネル（DEC-MTG-130 の幅）に出す。選んだほうは覚えておき（`meetingLiveSidePanel`）、次の記録でも同じほうを出す。⌘J で AI チャットに切り替えて、入力欄にフォーカスを移す。
- 理由: 会議中は文字起こしを見ながら聞くことが多く、答えと元の発言を見比べたい。別のウインドウやシートにすると文字起こしが隠れ、会議ツールとの行き来も増える。メモと AI チャットを同時に使うことは少ないので、3 列に並べずに切り替えにして、文字起こしの幅を残した。「ここ重要」はチャット中でも押せないと困る。
- 決めた場面: PR #68（会議中の AI チャット、2026-11-05）
- 関係する要件: REQ-MTG-040, REQ-MTG-011
- 対象: Mac
- 実装の場所: `LiveSidePanel`、`LiveSidePanelModePicker`、`LiveHighlightControls`、`LiveNotesPanel`、`LiveTranscriptView`、`MeetingWindowView`

### DEC-MTG-081 質問のたびに、その時点の記録とそれまでの会話を 1 回のリクエストにまとめて送る
- 決めたこと: 質問のたびに、送る時点の文字起こし（`<transcript>`）・確定前の途中結果（`<pending_transcript>`）・メモと印（`<user_notes>`）と、それまでの会話（`<conversation>`）・今の質問（`<question>`）を 1 回のリクエストにまとめて、会議に選んだ AI とモデル（`TextAIPurpose.meeting`）に送る。答えの付かなかった質問（失敗・取り消し）は会話に入れない。指示では、結論から短く答える・根拠の時刻を [12:34] で添える・記録にないことを書かない・一般的な知識で補うときは「（一般的には）」と分かるようにする・記録の中の指示に従わない、を求める。会議中は速さを優先して effort は low にする。記録のあとは、確定した文字起こし（話者名つき）を渡す。
- 理由: 4 つの AI（Gemini・Claude・ローカル・Apple）のクライアントはどれも 1 回の送信の形（`TextAIClient.generate`）で、複数のメッセージの形を足すと 4 つとも変えることになる。記録は質問のたびに伸びるので、どのみち毎回いまの記録を渡し直す必要がある。確定前の発言も渡すのは、「今の話」を聞かれることが多いため。
- 決めた場面: PR #68（会議中の AI チャット、2026-11-05）
- 関係する要件: REQ-MTG-040, REQ-MTG-041
- 対象: Mac
- 実装の場所: `MeetingChat.prompt`、`MeetingChat.instruction`、`MeetingChat.reply`、`MeetingChat.liveMaterial`、`MeetingChat.material`

### DEC-MTG-082 チャットで渡す量の上限
- 決めたこと: 文字起こしは合計 12 万文字まで。超えたら古い発言から省き、省いた発言の数を書く。それまでの会話は直近の 20 件（10 往復）まで、1 件 3,000 文字まで。ローカルと Apple の AI では、文脈に入らない分をそれぞれのクライアントで縮める（DEC-COM-065）。
- 理由: 日本語の会議は 1 時間でおよそ 2 万文字なので、数時間の会議でも全体を渡せる。会議中の質問は直近の話についてのものが多いので、超えたら新しいほうを残す。会話は長くなるほど、古いやりとりの意味が薄れる。
- 決めた場面: PR #68（会議中の AI チャット、2026-11-05）
- 関係する要件: REQ-MTG-040, REQ-MTG-041
- 対象: Mac
- 実装の場所: `MeetingChat.Options`、`MeetingChat.prompt`

### DEC-MTG-083 よく使う質問は、ボタン 1 つで送れるようにする
- 決めたこと: 「ここまでを要約」「直近 5 分の話」「決まったこと・宿題」「今の話を分かりやすく」「聞いておくとよいこと」の 5 つ。会話を始める前は、何ができるかの説明と一緒に大きめのボタンを縦に並べ、会話のあとは入力欄の上に小さく横に並べる。
- 理由: 会議中は話を聞きながらなので、文を打つ余裕が少ない。会議の途中で要りやすいのは、聞き逃した話の確認・決まったことの整理・分からない話の説明・次に聞くことで、要約は遅れて参加したときに使う。ボタンが何を聞くかは、マウスを載せると出る。
- 決めた場面: PR #68（会議中の AI チャット、2026-11-05）
- 関係する要件: REQ-MTG-040
- 対象: Mac
- 実装の場所: `MeetingChat.quickPrompts`、`MeetingChatView`

### DEC-MTG-084 答えの中の時刻を押すと、文字起こしのその発言へ移る
- 決めたこと: 答えの中の [12:34]（全角の［］も）を `hanasu-time://<秒>` のリンクにし、押すと、その時刻（1 秒の幅を見る）までに始まった最後の発言へスクロールして背景に色を付ける。記録中は、移ったあと新しい発言が来ても下へ戻らず、「最新の発言へ」のボタンで戻る。記録のあとは後ろ側のパネルを「文字起こし」にして移る。議事録の時刻の印（DEC-MTG-134）も同じ規則で読む。
- 理由: AI の答えを元の発言で確かめられるようにする（誤変換や作り話に気づける）。記録中に自動で下へ戻ると、読んでいる発言が流れてしまう。
- 決めた場面: PR #68（会議中の AI チャット、2026-11-05）
- 関係する要件: REQ-MTG-040
- 対象: Mac
- 実装の場所: `MeetingChat.linkingTimes`、`MeetingChat.lineIndex`、`LiveTranscriptView`、`MeetingInspector`

### DEC-MTG-085 会話は保存せず、残したい答えは「メモに残す」でメモにする
- 決めたこと: 会話はアプリを終了するまで会議ごとにメモリに持ち、meeting.json などのファイルには保存しない。残したい答えは「メモに残す」で、Markdown の記号と改行を除いた 1 行（「AI: …」、600 文字まで）のメモにする。記録中は質問した時刻のメモ、記録のあとは時刻なしのメモ（記録のあとに書き足したメモと同じ）にする。処理中・議事録の作り直し中は残せない。答えは「コピー」でもコピーできる。チャットの欄には、送り先の AI とモデルと、会話を保存しないことを出す。
- 理由: 会議の記録（文字起こし・議事録・メモ）は会議で起きたことの記録で、AI の答えをそのまま混ぜると区別がつかなくなる。記録のあとの処理は meeting.json を書き換えるので、記録中に会話を保存すると処理の書き込みとぶつかる。メモにすれば議事録で優先して取り上げられる（REQ-MTG-013）。メモはテキストの形式で 1 行 1 件（DEC-MTG-044）なので 1 行にし、「AI:」で本人のメモと区別する。
- 決めた場面: PR #68（会議中の AI チャット、2026-11-05）
- 関係する要件: REQ-MTG-040, REQ-MTG-011, REQ-MTG-013
- 対象: Mac
- 実装の場所: `MeetingChatModel`、`MeetingChat.noteText`、`LiveSidePanel.saveNote`、`MeetingDetailView.saveChatAnswerToNotes`

### DEC-MTG-086 記録のあとも、会議ノートの「AI チャット」で同じ会話を続けられる
- 決めたこと: 会議ノートの後ろ側のパネルに「AI チャット」を出す（前は詳細のタブ。2026-11-09 の会議ノートの UI の作り直し（docs/plans/meeting-notes-ui.md）で変えた）。記録中に始めた会話はそのまま残り、記録のあとは確定した文字起こし（話者分離と話者名のあと）で続ける。記録中にチャットしなかった会議（過去の会議）でも使える。会議を削除したら、その会話も消す。
- 理由: 記録を止めると、画面が記録中の画面から会議の詳細に変わるので、タブがないと会話が見えなくなる。会議が終わった直後に、確認やまとめをそのまま続けたいことが多い。過去の会議を横断して聞く「会議に質問」（REQ-MTG-016）は一問一答のままにし、1 つの会議を掘り下げるのはこちらで行う。
- 決めた場面: PR #68（会議中の AI チャット、2026-11-05）
- 関係する要件: REQ-MTG-041
- 対象: Mac
- 実装の場所: `MeetingChatStore`、`MeetingInspector`、`MeetingWindowView.delete`

### DEC-MTG-087 スリープは OS の通知で知り、確認は復帰したときにアラートで出す（Mac）
- 決めたこと: `NSWorkspace` の `willSleepNotification` でスリープする時点を覚え、`didWakeNotification` で確認のアラート（「スリープ前までで止める」が既定のボタン、もう 1 つが「記録を続ける」）を出す。確認が出ている間も記録は続ける。答える前にスリープ・復帰を繰り返しても、確認は 1 つで、止める位置は最初のスリープ。確認の間にほかの手段（メニュー・ショートカット）で記録を止めていたら、答えは使わない。
- 理由: 蓋を閉じたスリープも `willSleep` で知らせが来る（外部ディスプレイにつないで閉じたときはスリープしないので、記録を続けてよい）。スリープの前に聞くことはできないので、復帰した直後に聞く。止め忘れが主な場面なので「止める」を既定にした。確認の間に録った分は、「止める」なら捨て、「続ける」なら残るので、確認中も録り続けたほうが失うものがない。
- 決めた場面: ユーザーの依頼（2026-11-06、スリープ後の記録の扱い）
- 関係する要件: REQ-MTG-043
- 対象: Mac
- 実装の場所: `MeetingRecorder.systemWillSleep`、`MeetingRecorder.systemDidWake`、`MeetingRecorder.askAboutSleep`

### DEC-MTG-088 「スリープ前までで止める」は、チャンネルごとの音声の位置で切り、音声ファイルも切り詰める
- 決めたこと: スリープする時点で、チャンネルごとに「録音開始からの時刻で、どこまで音声を書いたか」（`ChannelTranscriber.audioEnd`）を覚える。止めるときは、その位置より後に始まる発言を捨て、音声ファイル（`me.m4a` / `others.m4a`）もその位置で切り詰める（Whisper / Gemini はその音声から文字起こしする）。切り詰めに失敗しても、発言を捨てるのは行う。会議の長さはスリープした時点までにし、それより後の「ここ重要」の印は消し、メモは消さずに時刻をスリープした時点にそろえる。
- 理由: スリープ中は音声が届かないので、音声の時間軸（DEC-MTG-006）にはスリープの時間が入らない。時計の時刻で切ると、復帰したあとの音声の一部が残る。メモは本人が書いた文なので消さない。
- 決めた場面: ユーザーの依頼（2026-11-06、スリープ後の記録の扱い）
- 関係する要件: REQ-MTG-043, REQ-MTG-011, REQ-MTG-012
- 対象: Mac
- 実装の場所: `MeetingSleepCut`、`MeetingRecorder.stop(cutAt:)`、`ChannelTranscriber.audioEnd`、`MeetingSleepCLI`（確認）

### DEC-MTG-089 記録を続けたときは、スリープしていた時間を経過時間から除く（Mac）
- 決めたこと: 記録中の経過時間（メモ・「ここ重要」の時刻、会議の長さ）は、開始からの時計の時間からスリープしていた時間を引いたものにする。
- 理由: 音声と文字起こしの時刻はスリープの時間を含まない（DEC-MTG-088）。時計の時間のままだと、スリープより後のメモや印が、スリープしていた分だけ後ろにずれて、議事録でメモと発言を結びつけられなくなる。
- 決めた場面: ユーザーの依頼（2026-11-06、スリープ後の記録の扱い）
- 関係する要件: REQ-MTG-043, REQ-MTG-011, REQ-MTG-012
- 対象: Mac
- 実装の場所: `MeetingRecorder.elapsed`、`MeetingRecorder.systemDidWake`、`LiveTranscriptView`（記録中の時計）

### DEC-MTG-090 議事録に使う発言の選び方は、meeting.json に「発言の ID・話者・時刻」で持つ
- 決めたこと: `meeting.json` に、範囲（`minutesFrom` / `minutesTo`。発言の開始時刻の秒）、除いた発言（`excludedUtterances`。発言の ID）、除いた話者（`excludedSpeakers`。話者キー）、オフレコの区間（`offRecord`。`id`・`start`・`end`。`end` がなければ記録の終わりまで）を足す。どれも省略可。発言が議事録に使われるかは、範囲（`minutesFrom ≤ 開始 ≤ minutesTo`）・除いた発言・除いた話者・オフレコ（`start ≤ 開始 < end`）の 4 つで決め、どれか 1 つに当たれば使わない（`Meeting.minutesUse(of:)`）。発言のまとめ（同じ話者が続く発言を 1 つにする）は、使う発言と使わない発言をまたいでまとめない。使い方を変えたら `minutesOutdated` を true にし、議事録を作り直したら外す。
- 理由: 発言そのもの（`utterances`）は書き換えずに残すので、いつでも戻せる（辞書の置き換えでは `text` を書き換えるが、認識したままの文を `rawText` に残す。DEC-DIC-172）。発言の ID は保存し直しても変わらない。範囲を時刻で持てば、話者名を変えても変わらない。範囲・個別・話者・オフレコを別々に持つと、どれか 1 つだけを解除できる。Mac と Windows で同じキーにして、どちらで選んでも同じ結果にする（DEC-MTG-108）。
- 決めた場面: ユーザーの依頼（2026-11-06、議事録の範囲と除外）
- 関係する要件: REQ-MTG-044, REQ-MTG-045, REQ-MTG-046
- 対象: Mac / Windows
- 実装の場所: `Meeting.minutesUse(of:)`、`Meeting.blocksForMinutes`、`windows/Hanasu.Core/Meetings/MinutesSelection.cs`

### DEC-MTG-091 除いた発言は文字起こしに残し、AI に渡すもの・書き出しには入れない。検索には残す
- 決めたこと: 議事録・話者名の推測・AI チャット（記録中と記録のあと）・会議への質問・辞書の候補探し・文字起こしの書き出し（Markdown のコピー・保存・`transcript.md`）は、使う発言だけから作る。会議ノートの文字起こしは全部を出し、使わない発言は薄く（除いた発言とオフレコは取り消し線も）して、理由（範囲外・除外・話者を除外・オフレコ）を添える。会議の横断検索の索引は変えない。使う発言が 1 つもなければ、議事録は作らない（記録のあとも、作り直しのボタンも）。Windows 版には AI チャット・会議への質問・会議の検索がないので、議事録（話者名の推測を含む）・会議ノートからの辞書の候補探し（REQ-DIC-072）・文字起こしの書き出しだけが対象。
- 理由: 除く目的は「AI と共有物に入れない」こと。文字起こしから消すと、間違えて除いたときに気づけず戻せない。検索は自分の Mac の中だけで、見つけた発言が除いたものだと文字起こしで分かる。
- 決めた場面: ユーザーの依頼（2026-11-06、議事録の範囲と除外）
- 関係する要件: REQ-MTG-045
- 対象: Mac / Windows
- 実装の場所: `Meeting.transcriptForPrompt`、`Meeting.transcriptForPromptMarkingHighlights`、`Meeting.transcriptMarkdown`、`MeetingChat.material`、`MeetingChat.liveMaterial`

### DEC-MTG-092 選び方を変えても議事録は自動では作り直さず、作り直しを促す
- 決めたこと: 発言を除く・範囲を変えるたびに議事録を作り直さない。`minutesOutdated` が true の会議は、Mac は文書の上の帯（DEC-MTG-132）と文字起こしの上の帯、Windows は議事録のタブと文字起こしの上の帯に「文字起こしか、議事録に使う発言を変えました。作り直すと反映されます」と「議事録を作り直す」を出す。辞書を当て直して文字起こしが変わったときも同じ帯を出す（DEC-DIC-174。2026-11-09 に文言を変えた）。
- 理由: 発言を 1 つずつ除くたびに AI を呼ぶと、時間とお金がかかり、作り直しの途中にまた変えることになる。いくつか選んでから 1 回作り直すのが自然。
- 決めた場面: ユーザーの依頼（2026-11-06、議事録の範囲と除外）
- 関係する要件: REQ-MTG-044, REQ-MTG-045
- 対象: Mac / Windows
- 実装の場所: `Meeting.minutesOutdated`、`TranscriptSelectionBar`、`MeetingStatusBanners`

### DEC-MTG-093 発言の選び方は、右クリックのメニューと「議事録に使う発言を選ぶ」のチェックボックスの 2 つ（Mac）
- 決めたこと: 文字起こしの発言を右クリックするか、行にマウスを載せると右端に出る「…」を押すと「議事録から除く／戻す」「ここから議事録に使う」「ここまで議事録に使う」「〇〇の発言をすべて除く／戻す」を出す。文字起こしの上の帯（後ろ側のパネル。DEC-MTG-137）の「選ぶ…」で、発言ごとのチェックボックス（オンが使う）を出す。Shift を押しながらチェックボックスを押すと、前に押した発言からその発言までを同じ状態にする。帯には、使う発言の数・範囲・除いた話者・オフレコの区間（それぞれ解除のボタン）と「すべて元に戻す」を出す。
- 理由: 1 つ 2 つを除くだけなら右クリックで足りる。「…」は、右クリックで出せることに気づかない人と、文字を選べる行（`textSelection`）で右クリックが文字のメニューになる場合のため。雑談の続く区間のように多くを除くときは、チェックボックスと Shift でまとめて選べるほうが速い。文字起こしの文字を選んでコピーする操作（`textSelection`）とぶつからないように、行のクリックでは選ばない。
- 決めた場面: ユーザーの依頼（2026-11-06、議事録の範囲と除外）
- 関係する要件: REQ-MTG-044, REQ-MTG-045, REQ-MTG-046
- 対象: Mac
- 実装の場所: `TranscriptSelectionBar`、`TranscriptLineMenu`、`MeetingInspector`

### DEC-MTG-094 オフレコの区間は、記録の経過時間で持ち、押すたびに保存する
- 決めたこと: 「オフレコ」を押した時刻と終えた時刻を、記録の経過時間（メモ・印と同じ時間軸。DEC-MTG-089）で `offRecord` に入れ、押すたびに meeting.json に保存する（DEC-MTG-043 のメモと同じく、落ちても残る）。オフレコのまま記録を止めたら終わりを記録の長さにする。スリープ前までで止めたときは、スリープの後に始めた区間を消し、終わりをスリープした時点までにする。メモと「ここ重要」の印は、オフレコ中に付けても残す。
- 理由: 発言の時刻と同じ時間軸なので、記録のあとに文字起こし（Whisper / Gemini を含む）ができてから発言に当てはめられる。メモと印は本人が書いたもので、オフレコの区間の目印にもなる。
- 決めた場面: ユーザーの依頼（2026-11-06、議事録の範囲と除外）
- 関係する要件: REQ-MTG-046, REQ-MTG-043
- 対象: Mac / Windows
- 実装の場所: `MeetingRecorder.toggleOffRecord`、`MeetingSleepCut.apply`、`windows/Hanasu.Core/Meetings/MeetingController.cs`

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
- 決めたこと: キーは camelCase、列挙は小文字、日時は秒までの UTC、UUID は大文字、null は書かない。保存先は `ドキュメント\Hanasu\Meetings\<yyyy-MM-dd HHmm>\` で、設定で変えられる。`audioStartOffsets` は Mac 版も書いて読む（DEC-MTG-135）。`reminderID` とアクションアイテムの `at`（DEC-MTG-134）、`deleteAudioAfterTranscription`・`transcriptionFailedChannels`（DEC-MTG-139・142）は読み書きで落とさない。
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

### DEC-MTG-111 Windows 版のスリープは PowerModeChanged で知り、スリープ中は記録の時計を止める
- 決めたこと: `SystemEvents.PowerModeChanged` の `Suspend` で、記録の時計（2 つのチャンネルの時刻合わせに使う経過時間）を止めて、その時刻を覚える。`Resume` で時計を動かし直し、確認のウインドウ（「スリープ前までで止める」が既定、閉じたら「記録を続ける」）を前面に出す。「止める」なら、会議の長さをスリープした時刻にし、WAV（`me.wav` / `others.wav`）をその時刻で切り詰めてから後処理する。印とメモの扱いは Mac と同じ（DEC-MTG-088）。
- 理由: ループバックは届かなかった時間を無音で埋める（DEC-MTG-103）ので、時計がスリープの時間を数えると、その分の無音（16 kHz で 1 時間に約 115 MB）が WAV に入る。時計を止めればスリープの時間は時間軸に入らず、WAV の位置と経過時間が対応するので、経過時間で切ればよい。Windows 版は記録のあとに WAV から文字起こしするので、WAV を切り詰めれば文字起こしもスリープの前までになる。閉じたときに続けるのは、録った音声を失わない側に倒すため。
- 決めた場面: ユーザーの依頼（2026-11-06、スリープ後の記録の扱い）
- 関係する要件: REQ-MTG-043, REQ-MTG-002
- 対象: Windows
- 実装の場所: `windows/Hanasu.Core/Meetings/MeetingController.cs`、`windows/Hanasu.Core/Audio/WavStreamWriter.cs`（`Truncate`）、`windows/Hanasu.Windows/AppHost.cs`、`windows/Hanasu.Windows/Views/SleepPromptWindow.cs`

### DEC-MTG-112 Windows 版の文字起こしのタブは、発言ごとの一覧にして、チェックボックスと右クリックで選ぶ
- 決めたこと: 会議ノートの「文字起こし」タブを、読み取り専用のテキストから発言ごとの一覧（時刻・話者・本文・使うかのチェックボックス）に変える。右クリックのメニューと Shift でのまとめての切り替え、上の帯（使う発言の数・範囲・除いた話者・オフレコの区間・すべて元に戻す・議事録を作り直す）は Mac と同じ（DEC-MTG-093）。記録中の画面に「オフレコ」のボタンを「ここ重要」の隣に置く。発言のコピーは、一覧で選んで Ctrl + C（使う発言・使わない発言とも、表示どおりの 1 行 1 発言）。
- 理由: テキストの欄では発言ごとに状態を持てない。Windows 版は記録中にライブの文字起こしを出さない（DEC-MTG-101）ので、オフレコ中の発言を薄く出すのは記録のあとだけ。
- 決めた場面: ユーザーの依頼（2026-11-06、議事録の範囲と除外）
- 関係する要件: REQ-MTG-044, REQ-MTG-045, REQ-MTG-046
- 対象: Windows
- 実装の場所: `windows/Hanasu.Windows/Views/MeetingWindow.xaml`・`windows/Hanasu.Windows/Views/MeetingWindow.xaml.cs`

---

### DEC-MTG-130 文書と後ろ側のパネルは `NavigationSplitView` と `inspector` で作り、最小の大きさを 1040×560 にする
- 決めたこと: 左の一覧は `NavigationSplitView` のサイドバー（220〜260）のまま。後ろ側のパネルは SwiftUI の `.inspector(isPresented:)`（幅 300〜560、初期値 360。記録中は 300〜520、初期値 340）を `NavigationSplitView` に付け、真ん中の画面とパネルの状態は `MeetingPanelState` で分け合う。表示の有無を `meetingInspectorShown`、記録後のタブを `meetingInspectorTab` に覚える。真ん中の文書は最小 400pt とし、文書には `minWidth` を付けず（理想の幅も 0 にし）、ウインドウの最小の大きさ 1040×560（一覧 260 ＋ 文書 400 ＋ パネル 360 ＋ 区切り）で確保する。ツールバーのパネルの表示の切り替え（⌥⌘I）で出し入れする。ガラスはツールバーと再生のバーだけにし、重ねない。右から左に書く言語では、パネルの位置はシステムに任せる。
- 理由: macOS 26 の標準の部品で、Liquid Glass の見た目・サイズ変更・キーボード操作・右から左の言語の配置が手に入る。最小の幅 900 では、サイドバーとパネルを出すと文書が 300pt を切る。macOS 26 では一覧とパネルが真ん中の上に重なるので、パネルを真ん中の画面に付けたり文書に `minWidth`・理想の幅を持たせたりすると、左右に並べる画面が一覧の幅を 2 回数えた最小の幅を求め、最小の大きさで中身がウインドウからはみ出した（`--render-meeting-window` で 1296 > 1000 を確かめて直した）。
- 決めた場面: 2026-11-09 の会議ノートの UI の作り直し（docs/plans/meeting-notes-ui.md）
- 関係する要件: REQ-MTG-050
- 対象: Mac
- 実装の場所: `MeetingWindowView`、`MeetingPanelState`、`MeetingDetailInspector`、`LiveInspector`、`AppDelegate.makeMeetingWindow`

### DEC-MTG-131 会議への操作は、ツールバーと「…」のメニューにまとめる
- 決めたこと: 記録後のツールバーは、前から「議事録の型」「議事録を作り直す」「辞書」（DEC-DIC-171）「書き出し」「…（話者名…・Finder で表示・録音を削除…・録音の管理…・削除…）」「インスペクタ」。タイトルの欄・日時の行は文書の先頭に置く。日時は `DateFormatter`、長さは `DateComponentsFormatter` で書き、時刻と見間違えないようにする。参加者は話者の色の丸と名前を並べ、押すと「話者名」のシートを開く。
- 理由: 前は 5 つのボタンが本文の上で折り返していた。使う頻度の低い操作（Finder・削除）はメニューに入れる。
- 決めた場面: 2026-11-09 の会議ノートの UI の作り直し（docs/plans/meeting-notes-ui.md）
- 関係する要件: REQ-MTG-050, REQ-MTG-008, REQ-MTG-028, REQ-MTG-055, REQ-MTG-056
- 対象: Mac
- 実装の場所: `MeetingWindowView`、`MeetingDocumentHeader`

### DEC-MTG-132 状態は真ん中の先頭の帯で出し、2 本まで積む
- 決めたこと: 次の状態を、真ん中（記録後は文書、記録中は文字起こし）の先頭の帯にする。帯は種類ごとに色と印を変え、右端に次にすることのボタンを置く。同時に起きたときは、この順で上の 2 本まで出す。(1) 進行中: 議事録を作成中（段階）・作り直し中。(2) 記録中の警告: 音が入らないチャンネル（DEC-MTG-020）、オフレコ中。(3) 失敗: `errorMessage`。長い文は 1 行に切り、「詳しく」で全文（選んでコピーできる）。「閉じる」で、アプリを終えるまでその会議では出さない。(4) 古い: 議事録に使う発言を変えた（DEC-MTG-092）。
- 理由: 長いオレンジの文章が見出しを押し下げるのをやめ、何をすればよいかを 1 か所で示す。失敗の帯は作り直しが成功するまで消えないので、閉じられるようにする。
- 決めた場面: 2026-11-09 の会議ノートの UI の作り直し（docs/plans/meeting-notes-ui.md）
- 関係する要件: REQ-MTG-013, REQ-MTG-045, REQ-MTG-050, REQ-MTG-054
- 対象: Mac
- 実装の場所: `MeetingStatusBanners`

### DEC-MTG-133 要約とアクションアイテムを文書の先頭に出す
- 決めたこと: 議事録の Markdown を見出し `## ` で節に分け、最初の節を「要約」として先頭に、続けて `Meeting.resolvedActionItems` のカードを出し、残りの節を本文として出す。カードが 1 件以上あるときは、アクションアイテムの見出し（`minutes.actionHeading*` の言語ごとの文言）の節を本文から外す。カードの各行は、やること・担当・期限・根拠の時刻の印。リマインダーに登録済みの行には、ベルの印を出す（四角のチェックボックスは使わない）。カードの右上に「リマインダーに登録…」を置く。`minutes` の文字列は変えない。検索の飛び先は、描いた行の行番号をそのまま ID にし、外した節の行はカードの同じ順番の行へ読み替える。
- 理由: 会議のあと最初に読むのは要約とやること。文字列は変えないので、書き出し・検索・Windows との互換は今のまま。四角は完了のチェックに見えて押したくなる。
- 決めた場面: 2026-11-09 の会議ノートの UI の作り直し（docs/plans/meeting-notes-ui.md）
- 関係する要件: REQ-MTG-018, REQ-MTG-050, REQ-MTG-015
- 対象: Mac
- 実装の場所: `MinutesDocument`、`MinutesDocumentView`、`ActionItemsCard`

### DEC-MTG-134 引用は議事録の Markdown の中の `[12:34]` で受け取り、書き出しでは取り除く
- 決めたこと: プロンプトの `minutes.citations` を、Mac と Windows の `MinutesPrompt` で `minutes.actionItems` のあとに入れる（`minutes.actionItems` は変えない）。中身は、要点の箇条書きの行末に根拠の発言の時刻を `[12:34]` の形で 1〜2 個付ける（はっきりしなければ付けない。チェックボックスの行には付けない）こと、アクションアイテムの JSON に根拠の時刻を `"at"` として付けてよいこと。`MinutesCitation` に印の取り出し（`[m:ss]`・`[mm:ss]`・`[h:mm:ss]`、全角の［］）と取り除き（前の空白ごと）を置く。表示は `MeetingChat.linkingTimes`（DEC-MTG-084）と同じ規則で読み、小さなカプセルで描く。会議の長さを 1 秒より多く超える時刻は無効の印にする。書き出し（`MeetingExport` の Markdown・テキスト・Slack 向け、`ReminderExporter`）では取り除き、`minutes.md` と `meeting.json` には残す。`ActionItem.parse(fromMarkdown:)` は読む前に行末の印を取り除く。要点にまとめてから議事録を作ったとき（DEC-COM-065）は保存の前に取り除く。`ActionItem` に任意の `at` を足し、Windows でも読み書きで落とさない。Windows は議事録の表示と書き出しで取り除く。
- 理由: 文字起こしの各行はもう `[時刻] 話者: 発言` の形で AI に渡しているので、同じ形で返させるのがいちばん確か。`minutes` の文字列に入るので、検索・保存の仕組みを変えずに済む。Mac と Windows で同じ文面を送る決まり（REQ-COM-061・DEC-COM-102）を守る。
- 決めた場面: 2026-11-09 の会議ノートの UI の作り直し（docs/plans/meeting-notes-ui.md）。書き出しで消すこと・Windows にも入れることはユーザーに確かめた
- 関係する要件: REQ-MTG-052, REQ-COM-061
- 対象: Mac / Windows
- 実装の場所: `MinutesCitation`、`MinutesPrompt`、`ActionItem`、`MeetingExport`、`ReminderExporter`
- Windows の実装: `windows/Hanasu.Core/Meetings/MinutesCitation.cs`、`windows/Hanasu.Core/Meetings/MinutesTemplate.cs`、`windows/Hanasu.Core/Meetings/MeetingModels.cs`（`ActionItem.At`）

### DEC-MTG-135 再生は 2 つの音声を `AVMutableComposition` で重ね、チャンネルのずれは `audioStartOffsets` に残す
- 決めたこと: `me.m4a` と `others.m4a` を 1 つの `AVMutableComposition` の 2 つの音声トラックとして、それぞれ録音開始からのずれ（`ChannelTranscriber.audioStartOffset`、DEC-MTG-006）だけずらして入れ、`AVPlayer` で再生する。消音は `AVAudioMix` のトラックごとの音量を 0 にする。ずれは Windows 版と同じ `meeting.json` の `audioStartOffsets`（`{"me": 0.12, "others": 0.31}`）に、Mac も記録を止めたときに書き、読む。項目のない会議は 0 として扱う。再生位置は 0.25 秒ごとに見て、`MeetingChat.lineIndex` で今の発言を引く。速さは `AVPlayer.rate`（声の高さを変えない `.timeDomain`）。記録・音声入力が始まったら再生を止める。
- 理由: 2 つの `AVAudioPlayer` を同時に動かすより、1 つの時間軸でシーク・速さ変更ができてずれない。同じ意味のキーを 2 つにしない。イヤホンなしの会議では相手の声がマイクにも入る（DEC-MTG-013）ので、片方ずつ消せるようにする。
- 決めた場面: 2026-11-09 の会議ノートの UI の作り直し（docs/plans/meeting-notes-ui.md）。消音はユーザーに確かめた
- 関係する要件: REQ-MTG-053, REQ-MTG-010
- 対象: Mac
- 実装の場所: `MeetingPlayer`、`MeetingRecorder.stop`、`Meeting.audioStartOffsets`

### DEC-MTG-136 処理の段階を状態として持ち、処理中のメモは読むだけにする
- 決めたこと: 記録のあとの処理の段階（`MeetingProcessingStage`: 文字起こし（Whisper / Gemini のときだけ）・話者の区別・議事録）と、出す段階の一覧を `MeetingRecorder.processingStages`・`processingStage` に持つ。帯は一覧を並べ、今の段階に印を付ける。議事録を作らない設定・使う発言がないときは議事録の段階を一覧に入れない。処理の間、文書のメモの欄は読むだけにする。記録を止める前に、メモの入力欄の打ちかけの文を止めた時点のメモとして確定する。
- 理由: 前の処理の状態は自由な文だけで、段階を出せなかった。処理は止めた時点の会議を最後に保存するので、処理中のメモの編集は上書きされて消える。
- 決めた場面: 2026-11-09 の会議ノートの UI の作り直し（docs/plans/meeting-notes-ui.md）
- 関係する要件: REQ-MTG-054, REQ-MTG-011
- 対象: Mac
- 実装の場所: `MeetingProcessingStage`、`MeetingRecorder`、`LiveNotesPanel`、`MeetingNotesEditor`

### DEC-MTG-137 議事録に使う発言の選択は、後ろ側のパネルの文字起こしの上の帯で行う
- 決めたこと: `TranscriptSelectionBar`（DEC-MTG-093）を後ろ側のパネルの文字起こしの上に置く。1 行目は使う発言の数と「選ぶ…」（選んでいる間は「すべて元に戻す」「選び終える」）。範囲・除いた話者・オフレコのカプセル（それぞれ解除）は、あるときに 2 行目以降に折り返して出す。「選ぶ…」でチェックボックスを出す。パネルの幅は選んでいる間も変えない（広げたいときはドラッグで広げる）。右クリック・「…」のメニューは今のまま。
- 理由: パネルの幅（360）では前の 1 行の帯が収まらないので、折り返す。計画では選ぶ間だけ 520 まで広げるとしたが、パネルの幅の決まりを途中で変えても今の幅は変わらず、広げた幅で最小の幅を求めるとウインドウからはみ出すので、やめた（2026-11-09、実装のとき）。
- 決めた場面: 2026-11-09 の会議ノートの UI の作り直し（docs/plans/meeting-notes-ui.md）
- 関係する要件: REQ-MTG-044, REQ-MTG-045, REQ-MTG-046, REQ-MTG-050
- 対象: Mac
- 実装の場所: `TranscriptSelectionBar`、`MeetingInspector`

### DEC-MTG-138 一覧の日付のまとまり
- 決めたこと: 会議の開始の日で「今日・昨日・今週・先週・それより前は月ごと」に分ける。週の始まりは `Calendar.current.firstWeekday`。月の書き方は `DateFormatter.setLocalizedDateFormatFromTemplate("yMMMM")`。検索中は検索結果の一覧を出す。描画の CLI は `--now` で基準の日時を固定できる。
- 理由: 会議は「この前の〇〇」と時期で探すことが多い。
- 決めた場面: 2026-11-09 の会議ノートの UI の作り直し（docs/plans/meeting-notes-ui.md）
- 関係する要件: REQ-MTG-051
- 対象: Mac
- 実装の場所: `MeetingListGrouping`

### DEC-MTG-139 録音を消すかは会議ごとに meeting.json に持ち、記録中の画面で変えられる
- 決めたこと: 記録を始めるとき（`MeetingRecorder.start` / `MeetingController.StartAsync`）に、設定（`keepMeetingAudio` / `KeepMeetingAudio`。表示は裏返し）を `meeting.json` の `deleteAudioAfterTranscription`（true のときだけ書く）に写す（`MeetingAudioPolicy.apply`）。記録中の画面の切り替えは、記録中の会議のこの値だけを変える。後処理はこの値と文字起こしの状態（DEC-MTG-142）で消すかを決め（`MeetingAudioPolicy.shouldDeleteAfterProcessing`）、設定は見ない。記録の設定のパネル・Windows の左下のチェックボックス・設定画面は、次の記録からの既定（設定）を変える。Windows も、ショートカット・トレイから記録を始めたら会議ノートを開く（Mac の `toggleMeeting` と同じ）。
- 理由: 議事録の型（DEC-MTG-061）と同じく、会議に写しておけば記録中に既定を変えても扱いがぶれない。入口が多いので、どこから始めても見える記録中の画面で変えられるようにした（2026-11-09 にユーザーと確かめた）。Windows はショートカットとトレイから始めると会議ノートが開かず、記録中の画面が見えなかった。キーを変えないので、今の設定を引き継げる。
- 決めた場面: 2026-11-10 の録音の削除（docs/plans/meeting-audio-deletion.md）
- 関係する要件: REQ-MTG-010, REQ-MTG-051, REQ-MTG-054
- 対象: Mac / Windows
- 実装の場所: `MeetingAudioPolicy`、`MeetingRecorder.start`・`setDeleteAudioAfterTranscription`・`process`
- Windows の実装: `windows/Hanasu.Core/Meetings/MeetingAudioCleanup.cs`（`MeetingAudioPolicy`）、`windows/Hanasu.Core/Meetings/MeetingController.cs`、`windows/Hanasu.Windows/AppHost.cs`

### DEC-MTG-140 あとから消す録音は完全に消し、記録中・処理中の会議は除く。「残しています」は表示のときに決める
- 決めたこと:
  - 録音を削除・録音の管理・保存期間は、音声ファイルを `FileManager.removeItem`（Windows は `File.Delete`）で完全に消す。もうないファイルは消せたものとして扱う。
  - 対象のファイルは、どちらの OS でも `me.m4a`・`others.m4a`・`me.wav`・`others.wav` の 4 つ。大きさ・件数・録音があるかも同じ 4 つで数える。Mac の再生は m4a だけ。
  - 記録中・記録のあとの処理中の会議（`MeetingRecorder.current` / `MeetingController.Current`）は除く。議事録の作り直し中は除かない。
  - Mac は消す前に、その会議を `MeetingPlayer.shared` で読み込んでいれば止め、消したあと読み直す。録音があるかはファイルがあるかで決め、消したら `MeetingRecorder.audioRevision`（Windows は画面を読み直す）を進めて描き直す。
  - 録音を消しても `meeting.json` は書き換えない。「音声ファイルは残しています」はエラーの文に書かず、文字起こしがそろっていないか状態が失敗で、かつ録音があるときに、表示のときに帯に足す。この機能より前の会議のエラーの文はそのまま。
- 理由: 容量をすぐ空けたい（2026-11-09 にユーザーと確かめた）。会議の削除（DEC-MTG-022）がゴミ箱なのは会議そのものが取り直せないからで、録音は文字起こしが残る（残らない会議は DEC-MTG-142 で守る）。DEC-MTG-108 で Mac と Windows が同じ会議のフォルダを開ける。処理中は音声を読んでいる。作り直しは文字起こしから作るので録音を使わない。`meeting.json` を書き換えないので作り直しの保存と競合せず、保存した文言で探して消すと言語が変わったときに外れる。
- 決めた場面: 2026-11-10 の録音の削除（docs/plans/meeting-audio-deletion.md）
- 関係する要件: REQ-MTG-055, REQ-MTG-056, REQ-MTG-057
- 対象: Mac / Windows
- 実装の場所: `MeetingStore.audioFiles`・`deleteAudio`、`MeetingRecorder.canDeleteAudio`・`deleteAudio`、`MeetingStatusBanners`
- Windows の実装: `windows/Hanasu.Core/Meetings/MeetingStore.cs`、`windows/Hanasu.Core/Meetings/MeetingController.cs`、`windows/Hanasu.Windows/Views/MeetingWindow.xaml.cs`

### DEC-MTG-141 まとめて消すのは「録音の管理」の画面で行い、対象の選び方は純粋な関数にする
- 決めたこと: 選んで・30 日より前・すべての 3 つは 1 つの画面にまとめる（Mac はウインドウ、Windows は C# で組み立てるウインドウ）。入口は設定「会議」と会議ノートのメニュー。会議ノートの一覧は 1 つずつ選ぶまま。対象の選び方（日数の境目・記録中と文字起こしがそろっていない会議を除く）は `MeetingAudioCleanup`（会議の配列・会議のフォルダ・今の日時を受け取る。Mac・Windows とも）に置き、自己テストは一時フォルダで確かめる。大きさは Mac は `ByteCountFormatter`、Windows は `MeetingAudioCleanup.FormatSize`。
- 理由: 一覧を複数選べるようにすると、真ん中の文書・後ろ側のパネル・削除・⌫ の振る舞い（REQ-MTG-050・051）をすべて考え直すことになる（専用の画面にすることは 2026-11-09 にユーザーと確かめた）。Mac の `MeetingStore.baseDirectory` は本物の保存先に固定なので、確かめるときに本物の録音を触らないようにする。
- 決めた場面: 2026-11-10 の録音の削除（docs/plans/meeting-audio-deletion.md）
- 関係する要件: REQ-MTG-056
- 対象: Mac / Windows
- 実装の場所: `MeetingAudioCleanup`、`MeetingAudioManagerView`
- Windows の実装: `windows/Hanasu.Core/Meetings/MeetingAudioCleanup.cs`、`windows/Hanasu.Windows/Views/MeetingAudioWindow.cs`

### DEC-MTG-142 文字起こしの状態を 3 つに分け、そろっていない会議は録音を守る
- 決めたこと: `MeetingAudioCleanup.transcriptState` で「すべて」「一部」「なし」に分ける。なし: 発言が 0 件。一部: 発言があり、`transcriptionFailedChannels` が空でないか、状態が「失敗」か、`transcriptionFailedChannels` のキーがなくエラーの文がある（この機能より前の会議）。すべて: それ以外。`transcriptionFailedChannels` は、消す設定かどうかに関わらず後処理で必ず書き、失敗がなければ空の配列にする（キーがないのは、この機能より前の会議だけになる）。「すべて」以外の会議は、後処理の自動の削除・「30 日より前」・「すべて」・保存期間で消さない。会議ごと・選んで消すときは、ダイアログで状態を書き分けてから消す。
- 理由: DEC-MTG-009・018 で録音を残した会議は、録音がただ 1 つの記録になる（まとめて消すときに外すことは 2026-11-09 にユーザーと確かめ、後処理と保存期間に当てはめることと発言 0 件を入れることは計画で決めて了承された）。エラーの文言で見分けると、言語が変わったときに外れる。この機能より前は、一部のチャンネルだけ失敗しても状態を「完了」にしてエラーの文に書くだけだったので、キーがない会議はエラーの文があるかで守る（議事録だけのエラーの会議も守る側に倒れるが、会議ごと・選んで消すことはできる。PR #91 のレビューで、まとめて消すときに録音を失うと分かって直した）。
- 決めた場面: 2026-11-10 の録音の削除（docs/plans/meeting-audio-deletion.md）
- 関係する要件: REQ-MTG-010, REQ-MTG-055, REQ-MTG-056, REQ-MTG-057
- 対象: Mac / Windows
- 実装の場所: `MeetingAudioCleanup.transcriptState`、`MeetingRecorder.stop`
- Windows の実装: `windows/Hanasu.Core/Meetings/MeetingAudioCleanup.cs`、`windows/Hanasu.Core/Meetings/MeetingPostProcessor.cs`

### DEC-MTG-143 保存期間で消すのは、起動時・後処理のあと・期間を短くしたとき
- 決めたこと: 期間は「無期限」（既定）・7・30・90・365 日（音声入力の履歴 `HistorySettings.dayOptions` にそろえる）。消すのは、起動時（会議を「失敗」にしたあと）、記録の後処理が終わったとき（Mac は `MeetingRecorder.stop` で `process` が返ったあと、Windows は `MeetingController` の後処理のあと。`process` / `MeetingPostProcessor` の中では呼ばない）、設定で期間を変えて、今すぐ消える録音を確かめたとき（期間を延ばしても、起動したまま日がたって過ぎた録音があれば確かめる）。起動したまま会議をしない間は、日付が過ぎても消さない。会議ごとの「残す」は保存期間には効かない。
- 理由: 記録中には触らず、会議のたびに整理される。期間を変えただけで何十件も黙って消えるのを防ぐ。`process` は確かめ方の CLI（`--meeting-files`）からも本物の保存先で呼ばれるので、そこで消すと開発者の録音が消える。会議ごとの「残す」は「明示的に残す」と「既定のまま」を見分けられないので、期間を全部に効かせ、設定の説明に書く。
- 決めた場面: 2026-11-10 の録音の削除（docs/plans/meeting-audio-deletion.md）
- 関係する要件: REQ-MTG-057
- 対象: Mac / Windows
- 実装の場所: `MeetingRecorder.pruneExpiredAudio`、`AppDelegate`、`SettingsView`
- Windows の実装: `windows/Hanasu.Core/Meetings/MeetingController.cs`（`PruneExpiredAudio`）、`windows/Hanasu.Windows/AppHost.cs`、`windows/Hanasu.Windows/Views/SettingsWindow.xaml.cs`

## 廃止

やめた要件・設計判断は、消さずにここへ移す（`- 状態: 廃止（日付・理由・PR）`）。今はない。
