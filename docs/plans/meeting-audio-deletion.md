# 会議の録音を消す（会議ごとの自動削除・あとからの削除・保存期間）

- 状態: 実装した（2026-11-10 に計画を了承。要件は spec の REQ-MTG-010・051・054〜057、設計判断は DEC-MTG-139〜143。手順 0 の結果は verification/meeting.md の 15）
- 対象: Mac / Windows

## 目的

2026-11-09 の依頼「文字起こしを作成したら録音を削除するというオプションを作成してください。また、後から録音を削除する機能も作成してください」。

会議の録音（Mac は `me.m4a`・`others.m4a`、Windows は `me.wav`・`others.wav`）は、文字起こしと議事録ができたあとは要らないことが多い。録音は容量を食い（Windows の WAV は 1 時間・1 チャンネルで約 115 MB）、会話そのものなので残しておきたくない会議もある。

- 今あるもの: 設定「会議」の「音声ファイル（me.m4a / others.m4a）を残す」（REQ-MTG-010。既定はオン＝残す、DEC-MTG-016）。オフにすると、どの会議も後処理（文字起こし・話者分離・議事録）のあとに録音を消す。Whisper / Gemini で文字起こしに失敗したチャンネルがあれば残す（DEC-MTG-009）。
- 足りないもの:
  1. 会議ごとに選べない（設定は全体に 1 つで、設定画面の奥にしかない）。
  2. あとから録音だけを消す方法がない（会議ごとゴミ箱に入れる削除 REQ-MTG-028 しかない）。
  3. 古い録音を自動で消す方法がない。

### ユーザーとのやりとり（2026-11-09）

| 質問 | 答え |
| --- | --- |
| 今ある設定をどうするか | 会議ごとに選べるように |
| あとから消す範囲 | 会議ごと + まとめて消す + 選んで消す + 30 日以前の録音を消す |
| あとから消すときの消し方 | 完全に削除する（ゴミ箱に入れない） |
| 対象の OS | Mac と Windows |
| 会議ごとの選択をどこでするか | 記録中の画面でも切り替えられる（既定は設定） |
| 文字起こしに失敗した・途中で落ちた会議を、まとめて消す（すべて・30 日より前）とき | まとめて消す対象から外す |
| 「選んで消す」の場所 | 専用の「録音の管理」画面 |
| 「30 日以前」の意味 | 両方（押して消すボタンと、自動で消す保存期間の設定） |

## 要件の案

### 変える要件（ユーザーの合意が要る）

#### REQ-MTG-010 音声ファイルを残すか、処理のあとに消すかを選べる（F10）

- 今: 「設定で、録音した音声ファイルを残すか、後処理のあとに消すかを選べる。」受け入れ条件「『音声ファイルを残す』をオフにすると、後処理のあとに `me.m4a` / `others.m4a` が消える。」
- 変更後:
  - 名前: 「会議ごとに、文字起こしのあとに録音を消すかを選べる（F10）」
  - 内容: 会議ごとに、録音を「文字起こしと議事録のあとに消す」か「残す」かを選べる。既定は設定で決め、記録を始める前（記録の設定のパネル）と記録中（記録中の画面）に、その会議の分を変えられる。
  - 受け入れ条件:
    - 設定「会議」に「文字起こしのあとに録音を削除する」がある（今の「音声ファイルを残す」の裏返し。保存しているキーは変えないので、今「残す」をオフにしている人はオンに見える）。既定はオフ（残す）。
    - Mac: 会議ノートの記録の設定のパネル（REQ-MTG-051）に同じスイッチがあり、設定と同じ値（次の記録からの既定）を変える。Windows: 会議ノートの左下（マイク・スピーカー・議事録の型の下）に同じチェックボックスがある。
    - 記録を始めると、どの入口（会議ノートのボタン・メニュー・ショートカット・Mac の自動検出のパネル・Windows のトレイ）から始めても、その時点の既定がその会議の値になる。
    - 記録中の画面に「この会議の録音を文字起こしのあとに削除」の切り替えがあり、今の値が見える。押すとその会議の値だけが変わり、既定は変わらない。Mac はツールバー、Windows は左上の記録中の欄（`LiveBox`）。記録を止めて処理に入ったあとは変えられない。
    - Mac はどの入口から始めても会議ノートが開く（今のまま）。Windows もショートカット・トレイから記録を始めたときに会議ノートを開く（今は開かない。仮に決めたこと）。
    - 記録中に設定画面で既定を変えても、記録中の会議の値は変わらない。記録中は、一覧の下の 1 行に、既定ではなく記録中の会議の値を出す。
    - 値がオンの会議は、後処理のあとに 2 つの音声ファイルが消え、`transcript.md`・`minutes.md`・`meeting.json`・`notes.md` は残る。オフの会議は残る。
    - オンでも、次のときは録音を残す: 文字起こしに失敗したチャンネルがある（DEC-MTG-009）、発言が 0 件（AI が空を返した・無音と判定したときを含む）、記録中・処理中にアプリが終わった（起動時に「失敗」になる。DEC-MTG-018）。残したときは、会議の帯に「音声ファイルは残しています」が出る（録音があるかで表示のときに決める。DEC-MTG-140）。
    - Mac 標準のエンジンで、記録中に認識が止まるエラー（取り消しを除く）が起きたチャンネルも「失敗」に数える（今は数えていない。実装の前に頻度を確かめる。手順 0）。
  - 出典: 初版の要件定義 F10（あると良い）。会議ごとに選べるようにしたのは 2026-11-09 の依頼「文字起こしを作成したら録音を削除するというオプションを作成してください」（同日に「会議ごとに選べるように」「記録中の画面でも切り替える」と確かめた）
  - 対象: Mac / Windows
  - 実装の場所: `MeetingAudioPolicy`、`MeetingRecorder.start`・`stop`・`process`・`setDeleteAudioAfterTranscription`、`ChannelTranscriber`、`RecordSettingsPopover`、`LiveDeleteAudioToggle`、`SettingsView`
  - Windows の実装: `windows/Hanasu.Core/Meetings/MeetingController.cs`（`StartAsync`・`SetDeleteAudioAfterTranscription`）、`MeetingPostProcessor.cs`（消す条件・`transcriptionFailedChannels`）、`windows/Hanasu.Windows/AppHost.cs`（記録を始めたら会議ノートを開く）、`windows/Hanasu.Windows/Views/MeetingWindow.xaml.cs`、`SettingsWindow.xaml.cs`
  - 確かめ方: Mac `.build/debug/Hanasu --test-meeting-audio`（純粋な関数と一時フォルダで: 設定 → 会議への写し、写したあとに設定を変えても会議の値で決まる、記録中に会議の値だけを変える、失敗したチャンネル・発言 0 件なら残す）と `--meeting-files me.wav others.wav --delete-audio`（その会議だけ消える）。Windows `cd windows && dotnet test Hanasu.Core.Tests --filter "FullyQualifiedName~MeetingAudioDeletionTests"` と `hanasu-cli meeting-files … --delete-audio`。記録中の切り替えの見た目は `--render-meeting-window` の記録中の 2 枚（最小の大きさ・既定の大きさ）

#### REQ-MTG-051 会議の一覧は日付でまとめ、記録の操作は 1 つのボタンと 1 行の設定にする

- 今: 1 行は「今の設定（議事録の型・スピーカー・マイク）」、パネルは「スピーカー・マイク・議事録の型と、型の管理」。
- 変更後: 1 行に、録音を消すのがオンのときだけ「録音は削除」を足す（記録中は記録中の会議の値）。パネルに「文字起こしのあとに録音を削除する」のスイッチを足し、記録中は「この会議の分は記録中のツールバーで変えられます」と出す。ほかは今のまま。
- 理由: REQ-MTG-010 の会議ごとの選択を、記録の前に目に入る場所に置く。

#### REQ-MTG-054 記録中の画面と、記録を止めてから議事録ができるまで

- 今: 記録中のツールバーは「記録中の印・経過時間・自分と相手の音量・オフレコ・字幕・パネルの表示の切り替え」。
- 変更後: ツールバーに「この会議の録音を文字起こしのあとに削除」の切り替え（ゴミ箱の印のトグル。オンのときは色が付き、ヘルプに今の状態を出す）を足す。会議ノートの最小の大きさでも、はみ出しのメニューに隠れずに見える。
- 理由: REQ-MTG-010 の記録中の切り替え。ショートカットや自動検出から始めた会議でも値が見え、変えられる。

### REQ-MTG-055 記録した会議の録音だけを、あとから消せる（新規）

- 内容: 会議ノートで、記録した会議の録音（音声ファイル）だけを消せる。議事録・文字起こし・メモ・アクションアイテムは残る。消した録音は戻せない。
- 受け入れ条件:
  - Mac: ツールバーの「…」のメニューと一覧の右クリックに「録音を削除…」がある。録音が残っていない会議・記録中や処理中の会議では押せず（項目は出したまま）、ヘルプに理由（「この会議には録音が残っていません」「記録中・処理中は消せません」）を出す。
  - Windows: 一覧の右クリックと、会議の詳細の上のボタンの並びに「録音を削除…」がある。押せないときは Mac と同じ。
  - 選ぶと、会議のタイトル・録音の大きさ・「元に戻せません」を書いたダイアログが出る。残るものは、会議の文字起こしの状態（DEC-MTG-142）で書き分ける: すべてある会議は「議事録・文字起こし・メモは残ります」、一部だけの会議は「相手（または自分）の文字起こしはありません。その分の会話の記録は残りません」、ない会議は「この会議には文字起こしがありません。録音を消すと、会話の記録は残りません」。「削除」（破壊的な見た目）で音声ファイルが完全に消える（ゴミ箱に入らない）。キャンセルで何も変わらない。
  - 消したあと、会議は選ばれたままで、文書・文字起こしは読める。会議の帯の「音声ファイルは残しています」は出なくなる。Mac は再生のバーが消える（再生中なら止まる）。「録音を削除…」は押せなくなり、設定の件数・合計と録音の管理の一覧も変わる。
  - 議事録の作り直し中も押せる（作り直しは録音を使わず、`meeting.json` も書き換えない）。
  - 消せなかったファイルがあれば、理由をダイアログで出し、残ったファイルはそのまま。もうなかったファイルは消せたものとして扱う。
- 出典: 2026-11-09 の依頼「後から録音を削除する機能も作成してください」（同日に「完全に削除する」「Mac と Windows」と確かめた）
- 関係する要件: REQ-MTG-010, REQ-MTG-028, REQ-MTG-053
- 対象: Mac / Windows
- 実装の場所: `MeetingStore.audioFiles`・`audioSize`・`deleteAudio`、`MeetingRecorder.canDeleteAudio`・`deleteAudio`・`audioRevision`、`MeetingMoreMenuItems`、`MeetingWindowView`（一覧の右クリック）、`MeetingStatusBanners`（「残しています」を表示のときに決める）
- Windows の実装: `windows/Hanasu.Core/Meetings/MeetingStore.cs`（`AudioFiles`・`AudioSize`・`DeleteAudio`）、`MeetingController.cs`（`CanDeleteAudio`・`DeleteAudio`）、`windows/Hanasu.Windows/Views/MeetingWindow.xaml.cs`
- 確かめ方: Mac `.build/debug/Hanasu --test-meeting-audio`（一時フォルダで、録音だけが消えて他のファイルが残る・4 つのファイル名・もうないファイル・記録中の会議は消さない・文字起こしの状態の 3 つ）。`--render-meeting-window` で、録音がある会議とない会議の `more-menu.png`（押せる・押せない）。Windows `dotnet test … --filter "FullyQualifiedName~MeetingAudioDeletionTests"`。再生のバーが消えることは実機

### REQ-MTG-056 録音の管理の画面で、選んで・30 日より前・すべての録音を消せる（新規）

- 内容: 録音が残っている会議を一覧する「録音の管理」の画面で、選んだ会議・30 日より前に記録した会議・すべての会議の録音をまとめて消せる。消すのは録音だけ。文字起こしがすべてそろっていない会議は、まとめて消す対象から外す。
- 受け入れ条件:
  - 入口: 設定「会議」の「録音を管理…」（横に今残っている録音の件数と合計の大きさ。例「12 件・1.4 GB」。文字起こしがそろっていない会議があれば「うち 2 件は文字起こしが欠けています」）。Mac は会議ノートのツールバーの「…」のメニューの「録音の管理…」、Windows は会議ノートの一覧の右クリックの「録音の管理…」からも開ける。
  - 画面には、録音が残っている会議が新しい順に、チェックボックス・タイトル・記録した日時・大きさで並ぶ。記録中・処理中の会議は並ばない。文字起こしがない会議には「文字起こしなし」、一部だけの会議には「一部の文字起こしなし」の印が付く。
  - 「選んだ録音を削除…」（1 件も選んでいなければ押せない）、「30 日より前の録音を削除…」、「すべての録音を削除…」がある。後の 2 つは印の付いた会議を含めず、当てはまる会議がなければ押せない。
  - どれを押しても、消す件数・合計の大きさ・「元に戻せません」を書いたダイアログが出る。選んだ中に印の付いた会議があれば、その件数と「その分の会話の記録は残りません」を別に書く。「30 日より前」「すべて」では、外した会議があれば「文字起こしが欠けている N 件（大きさ）は残します。選んで消せます」と書く。「削除」で消え、一覧・件数・合計が更新される。キャンセルで何も変わらない。
  - 「30 日より前」は、記録を始めた日時が今から 30×24 時間より前の会議。
  - 一部のファイルを消せなかったら、消せなかった件数を出し、残ったものは一覧に残す。
  - 画面を開いている間に会議の一覧が変わったら（記録の処理が終わった・別の場所で消した）、読み直す。
  - 画面の下に「保存先を iCloud Drive・OneDrive などで同期している場合は、同期先の削除済みの項目にしばらく残ることがあります」と出す。
  - Mac: 会議ノートで選んでいる会議の録音を消したら、再生を止めて再生のバーを消す。
- 出典: 2026-11-09 の依頼「後から録音を削除する機能も作成してください」（同日に「会議ごと + まとめて消す + 選んで消す + 30日以前の録音を消す」「専用の『録音の管理』画面」「失敗した会議はまとめて消す対象から外す」と確かめた）
- 関係する要件: REQ-MTG-055, REQ-MTG-057
- 対象: Mac / Windows
- 実装の場所: `MeetingAudioManagerView`（新規。`MeetingAudioManager.swift`）、`MeetingAudioCleanup`（新規）、`SettingsView`、`MeetingMoreMenuItems`
- Windows の実装: `windows/Hanasu.Core/Meetings/MeetingAudioCleanup.cs`（新規）、`windows/Hanasu.Windows/Views/MeetingAudioWindow.cs`（新規。`SleepPromptWindow`・`MeetingDictionaryWindow` と同じく C# で組み立てる）、`SettingsWindow.xaml.cs`、`MeetingWindow.xaml.cs`
- 確かめ方: Mac `.build/debug/Hanasu --test-meeting-audio`（30 日の境目・選んだものだけ・すべて・記録中と印の付いた会議を除く・外した件数）と `--render-meeting-audio-manager <出力フォルダ>`（架空の会議で、印・ボタン・同期の注意）。Windows `dotnet test … --filter "FullyQualifiedName~MeetingAudioDeletionTests"`。UI のテスト項目を `common/testdata/ui/meeting.json` に足す

### REQ-MTG-057 決めた日数より前の録音を、自動で消せる（新規）

- 内容: 設定で「録音を残す期間」を選ぶと、その日数より前に記録した会議の録音を自動で消す。既定は「無期限」（消さない）。文字起こしがそろっていない会議は消さない。
- 受け入れ条件:
  - 設定「会議」に「録音を残す期間」があり、「無期限」（既定）・7 日・30 日・90 日・365 日から選べる。説明に「会議ごとに『残す』にした録音も、この期間を過ぎると消えます。文字起こしが欠けている会議の録音は消しません」と出す。
  - 無期限以外のとき、アプリの起動時と、会議の記録の後処理が終わったときに、記録を始めた日時がその日数より前の会議の録音を、知らせずに消す（ログには件数を書く）。記録中・処理中の会議と、文字起こしがそろっていない会議は消さない。
  - 期間を短くしたとき、今すぐ消える録音があれば、件数・合計の大きさ・「元に戻せません」・（あれば）残す会議の件数を書いたダイアログで確かめる。「変更して削除」で設定を変えて消し、キャンセルで設定を元に戻す。消える録音がなければ確かめずに変える。
  - 消したあと、会議ノートの再生のバー（Mac）・「録音を削除…」・設定の件数と合計が更新される。
- 出典: 2026-11-09 の依頼「後から録音を削除する機能も作成してください」（同日に「30 日以前の録音を消す」は「押して消す」と「自動で消す」の両方と確かめた）。文字起こしが欠けた会議を除くこと・会議ごとの「残す」より期間が強いことは、計画で仮に決めた（了承のときに確かめる）
- 関係する要件: REQ-MTG-056
- 対象: Mac / Windows
- 実装の場所: `AppSettings.meetingAudioRetentionDays`、`MeetingAudioCleanup.expired`、`MeetingRecorder.pruneExpiredAudio`、`AppDelegate`（起動時）、`SettingsView`
- Windows の実装: `AppSettings.MeetingAudioRetentionDays`、`MeetingAudioCleanup.cs`、`MeetingController.cs`（`ProcessAsync` のあと）、`AppHost.cs`（起動時、`MarkInterruptedMeetings` のあと）、`SettingsWindow.xaml.cs`
- 確かめ方: Mac `.build/debug/Hanasu --test-meeting-audio`（期間ごとの境目・無期限は消さない・印の付いた会議と記録中を除く）。Windows `dotnet test … --filter "FullyQualifiedName~MeetingAudioDeletionTests"`（設定の読み書きと、後処理のあとに消すこと）

## 設計判断の案

### DEC-MTG-139 録音を消すかは会議ごとに `meeting.json` に持ち、記録中の画面で変えられる

- 決めたこと: 記録を始めるとき（`MeetingRecorder.start` / `MeetingController.StartAsync`）に、設定（`keepMeetingAudio` / `KeepMeetingAudio`。キーはそのまま、表示は裏返し）を `meeting.json` の `deleteAudioAfterTranscription`（true のときだけ書く）に写す（`MeetingAudioPolicy.apply(to:settings:)` に切り出す）。記録中の画面の切り替えは、記録中の会議のこの値だけを変えて保存する。後処理はこの値と文字起こしの状態（DEC-MTG-142）で消すかを決め（`MeetingAudioPolicy.shouldDeleteAfterProcessing`）、設定は見ない。記録の設定のパネル・Windows の左下のチェックボックス・設定画面は、設定（次の記録からの既定）を変える。Windows は、ショートカット・トレイから記録を始めたときも会議ノートを開く（Mac の `toggleMeeting` と同じ）。
- 理由: 議事録の型（DEC-MTG-061）と同じく、会議に写しておけば記録中に既定を変えても扱いがぶれない。入口が多いので、どこから始めても見える記録中の画面で変えられるようにした（2026-11-09 にユーザーと確かめた）。Windows はショートカットとトレイから始めると会議ノートが開かず、記録中の画面が見えないので、Mac にそろえる。キーを変えないので、今の設定を引き継げる。
- 関係する要件: REQ-MTG-010, REQ-MTG-051, REQ-MTG-054
- 対象: Mac / Windows

### DEC-MTG-140 あとから消す録音は完全に消し、記録中・処理中の会議は除く。「残しています」は表示のときに決める

- 決めたこと:
  - 「録音を削除…」・録音の管理・保存期間は、音声ファイルを `FileManager.removeItem`（Windows は `File.Delete`）で完全に消す。もうないファイルは消せたものとして扱う。
  - 対象のファイルは、どちらの OS でも `me.m4a`・`others.m4a`・`me.wav`・`others.wav` の 4 つ（DEC-MTG-108 で Mac と Windows が同じ会議のフォルダを開けるので）。大きさ・件数・「録音があるか」も同じ 4 つで数える。Mac の再生は今どおり m4a だけ。
  - 記録中・記録のあとの処理中の会議（`MeetingRecorder.current` / `MeetingController.Current`）は除き、議事録の作り直し中は除かない。
  - Mac は消す前に、その会議を `MeetingPlayer.shared` で読み込んでいれば `stop()` し、消したあと読み直す。録音があるかはファイルがあるかで決め、消したら `MeetingRecorder.audioRevision`（Windows は `MeetingChanged`）を進めて、メニュー・件数・再生のバー・帯を描き直す。
  - 録音を消しても `meeting.json` は書き換えない。「音声ファイルは残しています」は `errorMessage` に書かず、表示のときに「文字起こしがそろっていない（DEC-MTG-142）か状態が失敗」かつ「録音がある」なら帯に足す。新しい会議からは、文字起こしの失敗の文（Mac の `MeetingRecorder.transcribeRecordedAudio`）と途中で落ちた会議の文（Mac の `MeetingStore.markInterruptedMeetings`、Windows の `Meeting_Interrupted`・`Meeting_AudioKept`）から、音声を残したことの部分を外す。この機能より前の会議の `errorMessage` はそのまま（古い文が残る）。
- 理由: ユーザーの選択（容量をすぐ空ける）。会議ごとの削除（DEC-MTG-022）がゴミ箱なのは会議そのものが取り直せないからで、録音は文字起こしが残る（残らない会議は DEC-MTG-142 で守る）。処理中は音声を読んでいる。作り直しは文字起こしから作るので録音を使わない。`meeting.json` を書き換えないので、作り直しの保存と競合しない。保存した文言で探して消すと、言語が変わったときに外れる。
- 関係する要件: REQ-MTG-055, REQ-MTG-056, REQ-MTG-057
- 対象: Mac / Windows

### DEC-MTG-141 まとめて消すのは「録音の管理」の画面で行う

- 決めたこと: 選んで・30 日より前・すべての 3 つの消し方は、1 つの画面にまとめる（Mac はウインドウ、Windows は C# で組み立てるダイアログのウインドウ）。入口は設定「会議」と会議ノートのメニュー。会議ノートの一覧は 1 つずつ選ぶままにする。対象の選び方（日数の境目・記録中と印の付いた会議を除く）は `MeetingAudioCleanup`（会議の配列・基準のフォルダ・今の日時を受け取る純粋な関数。Mac・Windows とも）に置き、CLI とテストは一時フォルダで確かめる。大きさは Mac は `ByteCountFormatter`、Windows は `MeetingAudioCleanup.FormatSize`（新規。KB・MB・GB、今の UI の文化の数の書き方）で出す。
- 理由: 一覧を複数選べるようにすると、真ん中の文書・後ろ側のパネル・削除・⌫ の振る舞い（REQ-MTG-050・051）をすべて考え直すことになる（2026-11-09 にユーザーと確かめた）。Mac の `MeetingStore.baseDirectory` は本物の保存先に固定なので、確かめるときに本物の録音を触らないよう、フォルダを受け取る形にする。
- 関係する要件: REQ-MTG-056
- 対象: Mac / Windows

### DEC-MTG-142 文字起こしの状態を 3 つに分け、そろっていない会議は録音を守る

- 決めたこと: 会議の文字起こしの状態を `MeetingAudioCleanup.transcriptState` で「すべて」「一部」「なし」に分ける。
  - なし: 状態が「失敗」で発言が 0 件、または発言が 0 件。
  - 一部: `meeting.json` の `transcriptionFailedChannels`（新しいキー。`["me"]`・`["others"]` など）があり、発言が 1 件以上。または状態が「失敗」で発言が 1 件以上。
  - すべて: それ以外。
  - `transcriptionFailedChannels` は、消す設定かどうかに関わらず、文字起こしに失敗したチャンネルがあれば書く（Mac は `stop`・`--meeting-files`、Windows は `MeetingPostProcessor`）。
  - 「すべて」以外の会議は、後処理の自動の削除・「30 日より前」・「すべて」・保存期間で消さない。会議ごと・選んで消すときは、ダイアログで状態を書き分けてから消す。
- 理由: DEC-MTG-009・018 で録音を残した会議は、録音がただ 1 つの記録になる（まとめて消すときに外すことは、2026-11-09 にユーザーと確かめた。後処理の自動の削除と保存期間にも当てはめ、発言 0 件も入れたのは計画で仮に決めた）。エラーの文言で見分けると、言語が変わったときに外れる。この機能より前に一部のチャンネルだけ失敗した会議（発言はあるがキーがない）は「すべて」に見える。
- 関係する要件: REQ-MTG-010, REQ-MTG-055, REQ-MTG-056, REQ-MTG-057
- 対象: Mac / Windows

### DEC-MTG-143 保存期間で消すのは、起動時・後処理のあと・期間を短くしたとき

- 決めたこと: 期間は「無期限」（既定）・7・30・90・365 日（音声入力の履歴 `DictationHistory.dayOptions` にそろえる）。消すのは、起動時（Mac は `AppDelegate` の `markInterruptedMeetings` のあと、Windows は `AppHost` の `MarkInterruptedMeetings` のあと）、記録の後処理が終わったとき（Mac は `MeetingRecorder.stop` で `process` が返ったあと、Windows は `MeetingController` の `ProcessAsync` のあと。`process` / `MeetingPostProcessor` の中では呼ばない）、設定で期間を短くして確かめたとき。起動したまま会議をしない間は、日付が過ぎても消さない。会議ごとの「残す」（`deleteAudioAfterTranscription` が false）は保存期間には効かない。
- 理由: 記録中には触らず、会議のたびに整理される。期間を短くしただけで何十件も黙って消えるのを防ぐ。`process` は確かめ方の CLI（`--meeting-files`）からも本物の保存先で呼ばれるので、そこで消すと開発者の録音が消える。会議ごとの「残す」は「明示的に残す」と「既定のまま」を見分けられないので、期間を全部に効かせ、設定の説明に書く。
- 関係する要件: REQ-MTG-057
- 対象: Mac / Windows

### 直す設計判断

- DEC-MTG-009: 「対象: Mac」→「Mac / Windows」。Mac 標準のエンジンの認識のエラーも失敗に数える、`transcriptionFailedChannels` を書く、「残しています」は表示のときに決める（DEC-MTG-140）、を足す。
- DEC-MTG-016: 「録音を消す」の初期値はオフ（残す）、と書き換える。「対象: Mac」→「Mac / Windows」。
- DEC-MTG-017: `meeting.json` の中身に `deleteAudioAfterTranscription`・`transcriptionFailedChannels` を足す。
- DEC-MTG-018: 「対象: Mac」→「Mac / Windows」（Windows も `MarkInterruptedMeetings`）。エラーの文から音声の部分を外す（DEC-MTG-140）。
- DEC-MTG-022: 録音だけを消す入口は DEC-MTG-140 を見る、と一言足す。
- DEC-MTG-108: 読み書きで落とさないキーに `deleteAudioAfterTranscription`・`transcriptionFailedChannels` を足す。
- DEC-MTG-131: 「…」のメニューを「話者名…・Finder で表示・録音を削除…・録音の管理…・削除…」にする。

## やらないこと

- 音声入力の履歴の録音（DEC-DIC-075。既定はオフ）は対象にしない。履歴にはすでに「録音だけをすべて削除…」がある。
- 後処理の途中（議事録の前）で消すこと。消すのは今までどおり後処理の最後。
- 処理に入ったあと（記録を止めたあと）に、その会議の値を変えること（終わったら「録音を削除…」で消せる）。
- 会議ノートの一覧の複数選択。
- ディスクからの完全な消去（上書き）。同期先・バックアップ（Time Machine・クラウドの削除済みの項目）に残る分は消せない（画面に注意を出す）。
- 自動検出のパネル（REQ-MTG-009）に選択肢を出すこと（記録中の画面で変えられる）。
- 消した録音から文字起こしし直すこと（もとから文字起こしし直す機能はない）。
- この機能より前の会議の `errorMessage` の「音声ファイルは残しています」を書き換えること。

## 手順

0. 実装の前に: 手元の Mac のログで `meeting … results error` と `meeting finalize error` の頻度を見て（`log show --predicate 'eventMessage CONTAINS "meeting"' --last 30d` など）、ふつうに止めたときにも出るエラーがあれば数えないものとして決める。結果を `docs/verification/meeting.md` に書く。ふつうに出るなら、Mac 標準のエラーを失敗に数えるのはやめて、ユーザーに報告する。
1. spec を書く（`docs/spec/meeting.md`）: REQ-MTG-010・051・054 を直し、REQ-MTG-055〜057、DEC-MTG-139〜143 を足し、DEC-MTG-009・016・017・018・022・108・131 を直す。
2. Mac のデータ（3 と同じファイルを触らない）:
   - `Sources/Hanasu/MeetingModels.swift`: `Meeting.deleteAudioAfterTranscription: Bool?`・`transcriptionFailedChannels: [MeetingChannel]?`。`MeetingStore.audioFiles(for:)`・`audioSize(for:)`・`deleteAudio(for:) -> [失敗]`（会議のフォルダを受け取る版を本体にする）。`markInterruptedMeetings` の文から音声の部分を外す。
   - `Sources/Hanasu/MeetingAudioCleanup.swift`（新規）: `MeetingAudioPolicy.apply(to:settings:)`・`shouldDeleteAfterProcessing`、`MeetingAudioCleanup.transcriptState`・`olderThan(days:now:)`・`all`・`expired(retentionDays:now:)`・`excluding(current:)`。
   - `Sources/Hanasu/ChannelTranscriber.swift`: 取り消し以外の認識のエラーを `failed` に残す（手順 0 の結果しだい）。
   - `Sources/Hanasu/MeetingRecorder.swift`: `start` で `MeetingAudioPolicy.apply`。`setDeleteAudioAfterTranscription(_:)`（記録中だけ）。`stop` で失敗したチャンネルを `transcriptionFailedChannels` に書き、`process` が返ったあとに `pruneExpiredAudio()`。`process` の消す条件を `shouldDeleteAfterProcessing` に。`canDeleteAudio`・`deleteAudio(_ meetings:)`・`audioRevision`。文字起こしの失敗の文から「（音声ファイルは残しています）」を外す。
   - `Sources/Hanasu/Settings.swift`: `meetingAudioRetentionDays`（0＝無期限）。`AppDelegate`: 起動時に `pruneExpiredAudio`。
   - `main.swift`: `--meeting-files` に `--delete-audio`（失敗したチャンネルも書く）、`--test-meeting-audio`（新規。`MeetingAudioCLI.swift`。純粋な関数と一時フォルダだけを使い、本物の保存先を触らない）。
3. Mac の UI:
   - `Sources/Hanasu/MeetingWindow.swift`: `RecordSettingsPopover` のスイッチと記録中の注記、`summary` と `.help` の文言（記録中は会議の値）、記録中のツールバーの `LiveDeleteAudioToggle`、`MeetingMoreMenuItems` の「録音を削除…」「録音の管理…」（押せないときのヘルプ）と一覧の右クリック、確かめるダイアログ、消したあとの再生のバー。`MeetingStatusBanners` で「残しています」を表示のときに足す。
   - `Sources/Hanasu/MeetingAudioManager.swift`（新規）: `MeetingAudioManagerView` とウインドウ。
   - `Sources/Hanasu/SettingsView.swift`: 「文字起こしのあとに録音を削除する」（裏返しの Binding）、「録音を残す期間」と説明、件数・合計と「録音を管理…」。期間を短くするときの確かめ。
   - 描き出し: `--render-meeting-audio-manager <出力フォルダ>`（新規）。`MeetingNotesUICLI.swift` の `--render-meeting-window` に、録音がある会議とない会議の「…」（録音があるかを差し替えられるようにする）と、`showPreviewForRendering` で記録中にした `MeetingWindowView` を最小の大きさと既定の大きさで `renderInWindow` する 2 枚（live-window-min・live-window）を足す。`--render-settings --pane meeting` は件数と合計を固定値にする。
4. Windows（2・3 と独立に進められる）:
   - `windows/Hanasu.Core/Meetings/MeetingModels.cs`: `DeleteAudioAfterTranscription`・`TranscriptionFailedChannels`（JSON キーは Mac と同じ）。`MeetingStore.cs`: `AudioFiles`（4 つの名前）・`AudioSize`・`DeleteAudio` が失敗を返す。`MarkInterruptedMeetings` の文。`MeetingAudioCleanup.cs`（新規。`FormatSize` も）。
   - `windows/Hanasu.Core/Settings/AppSettings.cs`: `MeetingAudioRetentionDays`。
   - `MeetingController.cs`: `StartAsync` で写す、`SetDeleteAudioAfterTranscription`、`CanDeleteAudio`・`DeleteAudio`、`ProcessAsync` のあとに `PruneExpiredAudio`。`MeetingPostProcessor.cs`: 消す条件を会議の値と文字起こしの状態に、`TranscriptionFailedChannels` を書く、`Meeting_AudioKept` を `errorMessage` に入れない。`windows/Hanasu.Cli/Program.cs` の `--delete-audio` を会議の値にする。
   - `windows/Hanasu.Windows/AppHost.cs`: ショートカットとトレイから記録を始めたら会議ノートを開く。起動時（`MarkInterruptedMeetings` のあと）に `PruneExpiredAudio`。
   - `windows/Hanasu.Windows/Views/MeetingWindow.xaml.cs`: 左下のチェックボックス、`LiveBox` の切り替え、右クリックとボタンの「録音を削除…」「録音の管理…」、帯の「残しています」。`MeetingAudioWindow.cs`（新規）。`SettingsWindow.xaml.cs`: チェックボックスの文言と説明、期間と説明、件数・合計と「録音を管理…」、期間を短くするときの確かめ。
   - テスト: `windows/Hanasu.Core.Tests/MeetingAudioDeletionTests.cs`（新規。今ある `MeetingAudioTests` とは別の名前）。`MeetingTests.cs` の `KeepMeetingAudio` のテストを会議の値に合わせて直す。
5. タグ: 振る舞いを決めているコードに `// 要件: REQ-MTG-010・055・056・057`、`// 設計判断: DEC-MTG-139〜143` を付ける。確かめ方の CLI とテストに `// 確かめ方: …`。
6. 文字列（17 言語）: 下の表のものを、Mac は `tr` で書いて `python3 scripts/i18n-strings.py sync`、Windows は `windows/Hanasu.Windows/Properties/Strings.*.resx`（画面）と `windows/Hanasu.Core/Properties/Strings.*.resx`（`MeetingController`・`MeetingPostProcessor`・`MeetingStore` の文）。i18n エージェントに言語を分けて任せる。プロンプトは変えない。README は録音に触れていないので直さない。
7. design を直す: `docs/design/meeting.md`（会議ごとの値・録音を消す流れ・文字起こしの状態・録音の管理・保存期間）、`docs/design/security.md` と `docs/design/security-windows.md`（録音を消せる場所と、同期先・バックアップに残ること）、`windows/README.md`（CLI の `--delete-audio` の意味、記録を始めたら会議ノートが開くこと）。
8. UI のテスト項目を `common/testdata/ui/meeting.json` に足し（録音の管理・「…」のメニュー・パネルのスイッチ・記録中の切り替え・設定の期間）、`python3 scripts/ui-cases.py md` と `check`。ui-test スキルで描いて見る。

### 足す・変える文字列（17 言語）

| 場所 | 文字列（日本語） |
| --- | --- |
| Mac・Win 設定 | 文字起こしのあとに録音を削除する（今の「音声ファイルを残す」を置き換え）、その説明（Win の `Settings_KeepAudioNote` は意味が裏返るので書き直し） |
| Mac・Win 設定 | 録音を残す期間、無期限・N 日（既存の履歴の期間の文字列を使えるなら使う）、期間の説明、録音を管理…、N 件・<大きさ>、うち N 件は文字起こしが欠けています、期間を短くするときのダイアログ（件数・大きさ・残す件数・元に戻せません・変更して削除） |
| Mac パネル・Win 左下 | スイッチの文言、1 行の「録音は削除」、`.help` の「記録する機器と議事録の型と録音の扱いを変える（次の記録から）」、記録中の注記「この会議の分は記録中のツールバーで変えられます」 |
| 記録中 | この会議の録音を文字起こしのあとに削除、オン・オフのヘルプ |
| 会議ノート | 録音を削除…、録音の管理…、押せないときのヘルプ 2 つ、確かめるダイアログ（タイトル・大きさ・文字起こしの状態の 3 つの文・元に戻せません・削除）、消せなかったとき、帯の「音声ファイルは残しています」 |
| 録音の管理 | 画面のタイトル、列の見出し、文字起こしなし・一部の文字起こしなし、3 つのボタン、確かめるダイアログ（件数・大きさ・印の付いた会議の件数・外した件数）、消せなかった件数、同期の注意、録音はありません |
| 変える文 | Mac の「%@ で文字起こしできなかった部分があります（音声ファイルは残しています）。」から括弧を外す、Mac の途中で落ちた会議の文と Win の `Meeting_Interrupted` から音声の部分を外す、Win の `Meeting_AudioKept` を帯の表示に使う |

## 確かめ方

- `swift build`
- `python3 scripts/check-spec.py`、`python3 scripts/check-spec.py --diff origin/main`、`python3 scripts/check-i18n.py`、`python3 scripts/ui-cases.py check`
- `.build/debug/Hanasu --test-meeting-audio`、`.build/debug/Hanasu --test-meeting-player`（今のテストが通ること）
- `.build/debug/Hanasu --meeting-files me.wav others.wav --delete-audio`（その会議だけ録音が消える）と、付けないとき残ること
- `.build/debug/Hanasu --render-meeting-window <フォルダ>`（記録中の 2 枚で、最小の大きさでも切り替えがはみ出さない。「…」の 2 枚）、`--render-meeting-audio-manager <出力フォルダ>`、`--render-settings <出力フォルダ> --pane meeting`
- `cd windows && dotnet test Hanasu.Core.Tests`
- 実機で見ること（Mac）: パネルでオンにして短い会議を記録 → 処理のあと録音が消え、再生のバーが出ない。ショートカットで始め、記録中のツールバーで切り替える → その会議だけに効き、設定は変わらない。記録中に設定画面で切り替えても記録中の会議には効かない。再生中に「録音を削除…」→ 再生が止まりバーが消える。録音の管理で 3 つの消し方と印。期間を 7 日にしたときの確かめのダイアログ。
- Windows の実機は手元にないので、テストまでと、画面はコードのレビューまで（PR に書く）。

## 敵対的レビュー

2026-11-09、requirements-reviewer（Opus）2 つ並べて、2 回（1 回目のあとで要件が増えたので、直した計画でもう 1 回）。聞く回数を使い切ったので、2 回目で「聞く」になった 2 つ（R2-1・R2-2）は推奨で仮に決め、了承のときに見てもらう。

| # | 重さ | 指摘 | 仕分け | どうしたか |
| --- | --- | --- | --- | --- |
| A1 | 重大 | 「会議ごと」が全体の設定の書き換えで、ショートカット・自動検出から始めた会議では選べない・見えない | 聞く | 答え「記録中の画面でも切り替え」を REQ-MTG-010・054 と DEC-MTG-139 に入れた |
| A2・B2 | 重大 | 失敗した・途中で落ちた会議の唯一の記録（録音）が「すべて」「30 日」で消え、ダイアログの文も事実と違う | 聞く | 答え「まとめて消す対象から外す」を DEC-MTG-142 にした |
| A3 | 重大 | Mac 標準のエンジンでは認識のエラーを失敗に数えていない | 直す | 受け入れ条件と手順に足した。誤検出の心配（R2-8）は手順 0 で頻度を見てから決める |
| A4 | 重大 | 「まとめて」「選んで」「30 日以前」の読み方を計画の側で決めていた | 聞く | 答えで REQ-MTG-056・057、DEC-MTG-141・143 にした |
| B1 | 重大 | REQ-MTG-051 を変えるのに「変える要件」にない。DEC も | 直す | REQ-MTG-051・054 を「変える要件」に、DEC を「直す設計判断」に足した |
| B3 | 重大 | Mac で開始時の写しを確かめる手段がない | 直す | `MeetingAudioPolicy` に切り出し、`--test-meeting-audio` で確かめる |
| A5〜A9、B4〜B10 | 軽微 | 押せない／出さないのあいまいさ、エラーの文、落ちた会議、同期先、画面の読み直し、テストのクラス名、描き出し、描き直し、文字列の表、Windows の実装の場所、PR #78 | 直す | 1 回目の直しのとおり（2 回目で見直したものは下の行） |
| R2-1 | 重大 | Windows はショートカット・トレイから始めると会議ノートが開かず、記録中の切り替えが見えない（`AppHost.cs:209,341`） | 聞く→仮に決めた | Windows も記録を始めたら会議ノートを開く（Mac と同じ）。REQ-MTG-010・DEC-MTG-139 に書いた |
| R2-2 | 重大 | 会議ごとに「残す」にした会議も保存期間で消える。関係が書かれていない | 聞く→仮に決めた | 保存期間は全部に効く（「明示的に残す」と「既定のまま」を見分けられない）。設定の説明に出す。DEC-MTG-143 |
| R2-3 | 重大 | 発言 0 件の会議が後処理の自動の削除で消え、何も残らない | 直す | 後処理の削除も文字起こしの状態で守る（REQ-MTG-010、`shouldDeleteAfterProcessing`） |
| R2-4 | 重大 | 「文字起こしなし」の定義が要件どうしで食い違い、ダイアログの文が事実と違う | 直す | 「すべて・一部・なし」の 3 つにし、`transcriptionFailedChannels` でどちらが欠けたかを持つ。DEC-MTG-142 |
| R2-5 | 重大 | 「残しています」を文言で探して消す作りは、古い会議・言語の切り替え・落ちた会議・作り直し中で成り立たない | 直す | `errorMessage` に書かず、表示のときに決める。`meeting.json` を書き換えない。古い会議はそのまま。DEC-MTG-140 |
| R2-6 | 重大 | 今の OS の形式だけ消すと、Mac と Windows で同じフォルダを使う人の録音が残る | 直す | 4 つのファイル名を対象にする。DEC-MTG-140 |
| R2-7 | 重大 | 記録中のツールバーを `--render-meeting-notes` では描けない。最小の幅ではみ出すかも分からない | 直す | `--render-meeting-window` に記録中の 2 枚を足す。REQ-MTG-054 に「はみ出しのメニューに隠れない」を足した |
| R2-8 | 重大 | `pruneExpiredAudio` を `process` に置くと、確かめ方の CLI が開発者の本物の録音を消す。自己テストも本物の保存先を触る | 直す | 呼ぶ場所を `stop` のあと・起動時・期間の変更に決め、`MeetingAudioCleanup` をフォルダを受け取る純粋な関数にした。DEC-MTG-141・143 |
| R2-9 | 軽微 | Mac 標準のエラーを数えると誤検出があり得る（推測） | 直す | 手順 0 で頻度を見て決め、verification に書く |
| R2-10 | 軽微 | 「すべて」「30 日」・保存期間で外した会議が見えない | 直す | ダイアログと設定の件数に、外した件数を出す |
| R2-11 | 軽微 | もうないファイルを「消せなかった」と出す | 直す | 消せたものとして扱う。DEC-MTG-140 |
| R2-12 | 軽微 | ユーザーに確かめていない広げ方を「確かめた」と書いていた | 直す | DEC-MTG-142・REQ-MTG-057 の出典を、確かめた範囲と仮に決めた範囲に分けた |
| R2-13 | 軽微 | 記録中、パネルは押せないのに「パネルで既定を変えても」と書き、1 行とツールバーの値がずれて見える | 直す | 「設定画面で」に直し、記録中の 1 行は会議の値を出す。パネルに注記を足す |
| R2-14 | 軽微 | `transcriptionIncomplete` を書く条件が 2 通りに読める | 直す | 消す設定に関わらず書く。`--meeting-files` でも書く |
| R2-15 | 軽微 | 保存期間で消す機会に「期間を変えたとき」がない。起動しっぱなしの扱い | 直す | DEC-MTG-143 に足した |
| R2-16 | 軽微 | 手順の事実（Windows の起動は `AppHost.cs:139`、DEC-MTG-108・018 の直し、タグの手順、Windows のダイアログは C# で組み立てる） | 直す | 手順 4・5 と「直す設計判断」を直した |
| R2-17 | 軽微 | 押せないときのヘルプと、変える文の 17 言語が表にない | 直す | 文字列の表に足した |

見られなかったこと: iCloud Drive で同期したフォルダで消したファイルが残るか（注意の文は「残ることがあります」とする）。Mac 標準のエンジンのエラーの頻度（手順 0 で見る）。Windows の `LiveBox`（幅 280）と左下に項目を足したときの見た目（Windows の描き出しがない）。

## 仮に決めたこと

**了承のときに見てほしいもの（ユーザーの好みで分かれる）**

- **Windows でショートカット・トレイから記録を始めたら、会議ノートを開く**（今は開かない）。記録中の切り替えを見せるため。開かないなら、Windows では会議ノートを自分で開いたときだけ切り替えが見える。
- **保存期間は、会議ごとに「残す」にした録音にも効く**。「残す」を選んだ会議は期間を過ぎても残したい、なら作りを変える（「残す」を明示的な値として持つ）。
- **後処理の自動の削除と保存期間でも、文字起こしがそろっていない会議（発言 0 件を含む）の録音は消さない**（Q6 で聞いたのは「まとめて消すとき」だけ）。

**そのほか**

- 設定画面の項目を「文字起こしのあとに録音を削除する」に言い換える（今の「音声ファイルを残す」の裏返し）。今オフにしている人はオンに見える。
- 記録の設定のパネルの値は「次の記録からの既定」（設定と同じ値）。記録中の画面の切り替えは「その会議だけ」。
- 保存期間の選択肢は 無期限（既定）・7・30・90・365 日（音声入力の履歴にそろえる）。自動で消すときは知らせない（ログだけ）。期間を短くしたときだけ確かめる。
- この機能より前に一部のチャンネルだけ失敗した会議は、「すべてそろっている」会議として扱う。古い会議のエラーの文は書き換えない。
- 録音の管理の入口は、設定「会議」と会議ノートのメニュー（Mac は「…」、Windows は一覧の右クリック）。
- 同期先に残ることの注意は、録音の管理の画面の下に出す（確かめるダイアログには書かない）。
- 議事録の作り直し中でも録音は消せる。
