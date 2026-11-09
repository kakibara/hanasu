# 会議ノートから辞書を作る

- 作成日: 2026-11-09
- 状態: 2026-11-09 に了承し、実装した（spec は REQ-DIC-072〜074・DEC-DIC-170〜175。作りは [design/dictation.md](../design/dictation.md) の 5.6）。実装のときに計画から変えたこと: Mac の「辞書」のメニューは、窓の最小幅で上の並びが切れないよう枠のないアイコンだけにした。ローカルのトークン数は /tokenize ではなく多めの見積もりで数える（DEC-DIC-170）

## 目的

2026-11-09 の依頼「議事録から辞書を作成する機能を欲しいです。どのように実現したらいいか考えてください。」

会議で出た固有名詞（社名・製品名・人名）は、毎回まちがって認識される。会議ノートで「この会議の言葉を辞書に入れたい」と思ったときに、その場で候補を出し、選んだ語を辞書に足せるようにする。足した語はその会議の文字起こしにもすぐ当てられ、これから記録する会議でも文字起こしに当たるようにする。

### 今あるもの（調べた結果）

- REQ-DIC-071（Mac だけ）: 設定の「辞書・ルール」で「候補を探す」を押すと、今回の起動後の音声入力の結果と、**新しい順に 5 件**の会議（文字起こしと議事録）を会議の AI に送って候補を挙げ、選んだものだけを辞書に足す（`DictionarySuggester`、`DictionarySuggestionSection`）。会議を選べず、会議ノートからは使えない。
- DEC-DIC-085（Mac）: 会議では辞書を認識のヒントにだけ使い、置き換えルールは当てない。置き換えは roadmap の FUT-104（未着手）。
- Windows 版: 辞書の候補の機能はない（`windows/README.md` の「Mac 版との差」で未実装）。会議でも辞書は認識のヒント（`TranscriptionContext`）にだけ使う。
- プロンプトの `dictionarySuggest.*` は 17 言語そろっており、Windows も同じ JSON を読む（`Hanasu.Core.csproj` が埋め込む）。

### ユーザーに決めてもらったこと（2026-11-09）

| 質問 | 答え |
| --- | --- |
| 入口 | 会議ノートの会議から 1 件ずつ |
| どの辞書に入れるか | 今の辞書（1 つだけ）に足す |
| 対象の OS | Mac と Windows の両方 |
| 足したあと、その会議の文字起こし・議事録も直すか | 今回いっしょにやる（FUT-104 を実装する） |
| これから記録する会議にも自動で当てるか | 当てる。設定でオフにできる（既定はオン） |
| 会議に当てたあと、議事録をどうするか | 作り直しを促すだけ（作り直しは今のボタンで、今の確かめのまま） |
| 候補の画面を通さずに「今の辞書をこの会議に当てる」操作 | 今回入れる |

## 要件の案

### REQ-DIC-072 会議ノートの会議から辞書の候補を挙げてもらい、選んだものだけを足す（新規）

- 内容: 会議ノートで開いている会議 1 件の議事録と文字起こしから、会議の AI に辞書の候補を挙げてもらい、ユーザーが選んだものだけを今の辞書に足す。
- 受け入れ条件:
  - 会議の詳細の上に「辞書」のメニューがあり、「この会議から辞書の候補を探す…」を選べる。議事録に使う発言が 0 件の会議、記録中・後処理中・議事録を作り直している会議では選べない。
  - 選ぶと候補の画面が開き、すぐに探し始める。探している間は進み具合を出す。「キャンセル」で閉じると AI の呼び出しを止め、辞書も会議も変えない。
  - 材料はその会議だけ。オフレコの区間と、議事録に使わないと除いた発言は送らない（REQ-MTG-045・046 と同じ）。
  - 候補は `読み → 表記` と理由で並ぶ。既定ではどれもチェックしない。チェックしたものだけが「選んだ N 件を辞書に追加」で辞書の末尾に `読み => 表記`（読みがなければ語だけ）の行として入る。
  - 候補の画面に「この会議の文字起こしにも辞書を当てる」がある。既定は、新しい会議に当てる設定（REQ-DIC-073）と同じ（設定がオンならオン、オフならオフ）。オンで追加すると、追加のあとで REQ-DIC-074 と同じ当て直しをする。
  - 追加すると画面を閉じ、「N 件を辞書に追加しました。」と知らせる（当てたら REQ-DIC-074 の知らせも続けて出す）。
  - 候補が 0 件なら「新しい候補は見つかりませんでした。」と出す。
  - 会議の AI が使えない（鍵がない・ローカルのモデルがない）、ネットにつながらない、時間切れ、応答が読めないときは、理由を画面に出し、辞書も会議も変えない。
  - 文字起こしが長くて材料に入りきらなかったときは、「会議が長いので、文字起こしの最初の約 N 分だけを読みました。」と出す（DEC-DIC-170）。
- 出典: 2026-11-09 の依頼「議事録から辞書を作成する機能を欲しいです」（入口は会議ノートから 1 件ずつ、今の辞書に足す、Mac と Windows の両方、と回答）
- 関係する要件: REQ-DIC-071, REQ-DIC-074, REQ-MTG-045, REQ-MTG-046
- 対象: Mac / Windows
- 実装の場所（予定）: Mac `MeetingDictionarySheet`（新規）、`MeetingDictionaryMenu`（新規。`MeetingDetailView` に置く）、`DictionarySuggester.corpus(for:)`。Windows `Hanasu.Core/Text/DictionarySuggester.cs`（新規。Mac 版の移植）、`Hanasu.Windows/Views/MeetingDictionaryWindow.cs`（新規）、`MeetingWindow.xaml` の `ActionsPanel`
- 確かめ方: Mac `.build/debug/Hanasu --test-meeting-dictionary`（AI を呼ばない部分）、`--suggest-dictionary --meeting <会議のフォルダ>`（実際に AI を呼ぶ）、`--render-meeting-dictionary <出力フォルダ>`（画面を PNG に）。Windows `cd windows && dotnet test Hanasu.Core.Tests --filter "FullyQualifiedName~DictionarySuggester"`、`dotnet run --project Hanasu.Cli -- meeting-dict-suggest <会議のフォルダ>`。Windows の画面は手で見る UI のテスト項目

### REQ-DIC-073 これから記録する会議の文字起こしに、辞書の置き換えルールを当てる（新規。FUT-104 を移す）

- 内容: 会議の記録を止めて文字起こしが確定したら、議事録を作る前に、辞書の置き換えルールを発言ごとに当てる。設定でオフにできる（既定はオン）。議事録・文字起こしの表示・transcript.md・会議への質問・AI チャット・書き出しは、置き換えた後の文を使う。認識したままの文も残す。
- 受け入れ条件:
  - 設定の会議の欄に「文字起こしに辞書の置き換えルールを当てる」があり、既定でオン。今までの設定のファイルにこの項目がなくてもオンになる。
  - オンで、辞書に `ストックマーク => Stockmark` があるとき、新しく記録した会議の文字起こしの「ストックマーク」が「Stockmark」になり、議事録の材料にも「Stockmark」が渡る。議事録を作る設定がオフでも、文字起こしには当たる。
  - オフなら、今までと同じく置き換えない（認識のヒントには渡す）。
  - 記録中のライブの文字起こし・字幕・記録中の AI チャットには当てない。
- 出典: 2026-11-09 の依頼（「その会議の文字起こし・議事録にも辞書を当てて直す」を今回いっしょにやる、これから記録する会議にも当てて設定でオフにできる、と回答）。roadmap の FUT-104
- 関係する要件: REQ-DIC-070, REQ-DIC-074, REQ-MTG-006
- 対象: Mac / Windows
- 実装の場所（予定）: Mac `MeetingDictionary.apply(_:to:)`（新規）、`MeetingRecorder.process`、`AppSettings.applyDictionaryToMeetings`、`SettingsView` の会議の欄。Windows `Hanasu.Core/Meetings/MeetingDictionary.cs`（新規）、`MeetingPostProcessor.ProcessAsync`、`AppSettings.ApplyDictionaryToMeetings`、`SettingsWindow.xaml` の会議の欄
- 確かめ方: Mac `.build/debug/Hanasu --test-meeting-dictionary`、`--meeting-files <me> <others> --dictionary <辞書>`（`recorder.process` を通して置き換えが当たることを見る）。Windows `dotnet test Hanasu.Core.Tests --filter "FullyQualifiedName~MeetingDictionary|FullyQualifiedName~MeetingControllerTests"`（偽の文字起こしで、止めたあとの発言に当たる・オフなら当たらない）

### REQ-DIC-074 会議ノートで、今の辞書をその会議の文字起こしに当て直す（新規）

- 内容: 会議ノートで開いている会議の文字起こしに、今の辞書の置き換えルールを当て直す。候補の画面から追加したとき（REQ-DIC-072）と、「辞書」のメニューの「今の辞書をこの会議に当て直す」から使う。議事録は作り直さず、作り直しを促す。
- 受け入れ条件:
  - 「辞書」のメニューに「今の辞書をこの会議に当て直す」がある。選べない条件は REQ-DIC-072 と同じ。新しい会議に当てる設定（REQ-DIC-073）がオフでも使える。
  - 当て直しは、認識したままの文に今の辞書を当てる。辞書からルールを消して当て直すと、その語は認識したままの文に戻る。設定で表記を直して当て直すと、新しい表記になる。
  - 当てたら、当てる前と比べて文が変わった発言の数 M を「当て直して、M 件の発言が変わりました。」と出す。M が 0 なら「当て直しました。変わった発言はありませんでした（辞書で置き換えてある発言: K 件）。」と出す（K は `rawText` のある発言の数。Mac と Windows で同じ数え方）。
  - 「辞書」のメニューに「この会議を認識したままの文に戻す」もある（辞書で置き換えた発言が 1 つ以上あるときだけ選べる）。選ぶと、すべての発言を認識したままの文に戻し、変わった発言の数を同じように知らせる。辞書は変えない。
  - 当て直せなかったとき（その間に記録・後処理・作り直しが始まった、会議のフォルダがない）と、保存に失敗したときは、「この会議を変えられませんでした: <理由>」と出し、会議を変えない。
  - 文字起こしが変わり、議事録がある会議では、議事録のタブと文字起こしの上の帯に「文字起こしか、議事録に使う発言を変えました。作り直すと反映されます。」と「議事録を作り直す」を出す（DEC-MTG-092 の帯）。議事録は自動では作り直さない。作り直すときは今の確かめ（DEC-MTG-072）が出る。
- 出典: 2026-11-09 の依頼（会議に当てたあと議事録は作り直しを促すだけ、候補の画面を通さずに当て直す操作も今回入れる、と回答）
- 関係する要件: REQ-DIC-072, REQ-DIC-073, REQ-MTG-013
- 対象: Mac / Windows
- 実装の場所（予定）: Mac `MeetingRecorder.applyDictionary(to:)`（新規）、`MeetingDictionaryMenu`。Windows `MeetingController.ApplyDictionary`（新規）、`MeetingWindow.xaml.cs`
- 確かめ方: Mac `.build/debug/Hanasu --test-meeting-dictionary`、`--render-meeting-dictionary <出力フォルダ>`（帯の出た詳細画面も描く）。Windows `dotnet test Hanasu.Core.Tests --filter "FullyQualifiedName~MeetingDictionary|FullyQualifiedName~MeetingControllerTests"`（変わる・変わらない・議事録なし・ルールを消して戻る）

### 変える要件

- なし（REQ-DIC-070・071 の文面は変えない）。

### 変える設計判断

- **DEC-DIC-085「会議の記録では、辞書を語彙のヒントにだけ使う」→ 廃止**して「## 廃止」へ移す。理由の「会議の後処理はほかの PR も触っていた」はもう当てはまらず、ユーザーが会議にも置き換えを当てると決めた（2026-11-09）。「語彙のヒントに渡す」部分は DEC-DIC-175 に引き継ぎ、`MeetingRecorder.swift` のタグ `// 設計判断: DEC-MTG-001, DEC-DIC-085` を `DEC-DIC-175` に付け替える。
- **DEC-DIC-088「候補の材料と呼び出し」**: 会議の材料は認識したままの文（`rawText`。なければ `text`）を使う、と書き足す。置き換えた後の文を送ると誤認識の形（読み）が材料に出てこず、DEC-DIC-089 の絞り込みで読みが消えるため。
- **DEC-MTG-092「選び方を変えても議事録は自動では作り直さず、作り直しを促す」**: 帯を出すきっかけに「文字起こしに辞書を当て直して変わったとき」を足し、帯の文言を「議事録に使う発言を変えました。作り直すと反映されます。」から「文字起こしか、議事録に使う発言を変えました。作り直すと反映されます。」に変える（Mac・Windows、17 言語）。
- **DEC-MTG-090**: 理由の「発言そのもの（utterances）は書き換えずに残す」に、「辞書の置き換えでは `text` を書き換えるが、認識したままの文を `rawText` に残す（DEC-DIC-172）」と書き添える。
- **DEC-MTG-091**・**DEC-COM-107**: 「Windows 版には辞書の候補探しがない」旨の記述を、「会議ノートからの候補探しはある。設定の欄からはない」に直す。
- **DEC-DIC-087**・**DEC-DIC-089**: 対象に Windows を足し、Windows の実装の場所（`Hanasu.Core/Text/DictionarySuggester.cs` の `Appending`・`Filter`）を書き、Windows のコードにもタグを付ける。

## 設計判断の案

番号は、開いている PR #78 が DEC-DIC の 160 番台を使い、さらに足す予定なので、170 番台にする。

### DEC-DIC-170 会議 1 件の材料と呼び出し

- 決めたこと:
  - 材料は「その会議の議事録に使う発言（`blocksForMinutes`。オフレコと除いた発言は入らない）を認識したままの文で並べたもの（話者名つき）」を先に、「議事録の本文」をあとに置く。議事録は、文字起こしを入れて残った分だけ入れる。
  - 長さの上限は会議の AI で変える。Gemini・Claude は全体で 60,000 字。ローカルの LLM と Apple は、そのモデルの文脈の長さ（Mac `LocalLLMModel.contextLength`・`AppleFMClient.contextLength`、Windows `LocalLlmModel.ContextLength`）から、出力・system instruction・既存の辞書の分を引いたトークン数まで。数え方は今ある数え方を使う（Apple `AppleFMClient.estimateTokens`、ローカルは llama-server の /tokenize。Mac `LocalLLMClient.countTokens`、Windows `LocalLlmClient.CountTokensAsync`）。アプリの側で先に切るので、`LongInputFitter` が黙って後ろを省くことはない。
  - 文字起こしを切ったときだけ、切った位置の発言の時刻から「会議が長いので、文字起こしの最初の約 N 分だけを読みました。」と出す（議事録だけが入らなかったときは出さない）。
  - 音声入力の結果は入れない。
  - AI は会議の AI（DEC-COM-040。Mac `TextAIClient.requireFromSettings(settings, for: .meeting)`、Windows `AppHost.CreateTextAi(settings, TextAiUse.Meeting)`）。タイムアウトは Mac は今の候補探しと同じ 120 秒、Windows は会議の既定（Gemini 180 秒・Claude 300 秒・ローカルは `MinimumTimeout`）。ローカルのモデルがないときの扱いは議事録と同じ（Mac `LocalModelDownloadPrompt.prepare`）。
  - プロンプトは今の `dictionarySuggest.*` を使い、新しいキーは足さない。Windows の `TextPurpose` は `Minutes` を使う。
  - 材料を囲む `<material>` を、区切りのタグを無害にする一覧に足し（Mac `PromptText.delimiterTag`、Windows `PromptText.NeutralizeDelimiters`）、`DictionarySuggester.userPrompt`（Windows `UserPrompt`）で材料をそれに通す。`filter` は通したあとの材料で照合する。設定の欄（REQ-DIC-071）の材料にも同じく効く。
  - キャンセルで閉じたら、呼び出しの Task を止める（Mac `Task.cancel`、Windows `CancellationToken`）。
- 理由: オフレコを守り、「この会議のことばだけ」を出す。置き換えルールの読み（誤認識の形）は文字起こしにしか出てこず、材料に出てこない読みは DEC-DIC-089 で除くので、文字起こしを先に入れる。ローカル・Apple は文脈が 8,192〜32,768 トークンしかなく、60,000 字で切っても AI の側で黙って切られ、「読んだ範囲」の知らせが誤りになる。字数で見積もると、英語では入る量を捨て、まれな漢字では足りなくなるので、今ある数え方を使う。
- 関係する要件: REQ-DIC-072
- 対象: Mac / Windows

### DEC-DIC-171 入口と候補の画面

- 決めたこと:
  - Mac: `MeetingDetailView` の上のボタンの並び（「話者名…」の右）に「辞書」のメニュー（`MeetingDictionaryMenu`）を置き、「この会議から辞書の候補を探す…」「今の辞書をこの会議に当て直す」「この会議を認識したままの文に戻す」を並べる。候補は `.sheet` の `MeetingDictionarySheet` で出す。候補の行の見た目は設定の `DictionarySuggestionSection` と同じにし、行の部品を共有する。結果の知らせは `.alert` で出す。
  - Windows: `MeetingWindow.xaml` の `ActionsPanel` の「議事録を作り直す」の右に「辞書…」のボタンを置き、押すと同じ 3 つの項目の `ContextMenu` を出す。候補は C# だけで作る `MeetingDictionaryWindow`（`SleepPromptWindow` と同じ作り）を `ShowDialog()` で開く。結果の知らせは `MessageBox`。
  - 画面を開いたらすぐ探す（ボタンを押したときだけ AI を呼ぶ、という DEC-DIC-087 の範囲内）。閉じたら結果は捨て、次に開いたらもう一度呼ぶ。
  - 追加したら画面を閉じる。
  - Windows の設定画面は `Settings.Changed` を受けて、辞書の欄（`DictionaryBox`）がキーボードのフォーカスを持っていない（`IsKeyboardFocused` が false）ときに中身を読み直す。開いたままの設定画面が、会議ノートで足した行を古い中身で書き戻さないようにする。
- 理由: 会議ノートで会議を見ているときに、その場で使える。2 つの操作をメニューにまとめ、上のボタンの並びを広げない。設定の欄と同じ見た目にすると、選び方を覚え直さなくてよい。WPF の論理フォーカス（`IsFocused`）はウインドウが非アクティブでも残るので使わない。
- 関係する要件: REQ-DIC-072, REQ-DIC-074
- 対象: Mac / Windows

### DEC-DIC-172 会議の発言は、認識したままの文を残し、そこから置き換える

- 決めたこと:
  - 発言（`Utterance`）に省略できる `rawText`（Windows `RawText`、JSON のキーは `rawText`）を足す。置き換えで `text` が変わったときだけ `rawText` に認識したままの文を入れ、変わらなければ `rawText` を消す。当て直すときは `rawText ?? text` に今の辞書を当てる。Mac と Windows で同じ meeting.json の形にする。
  - 続く発言をまとめる処理（`blocksForMinutes`・`mergedBlocks`、Windows `BlocksForMinutes`）に、認識したままの文もつなぐ形を足す。辞書の候補の材料（`transcriptForPrompt(raw: true)`、Windows `TranscriptForPrompt(raw: true)`）はこれを使う。
- 理由: 誤ったルールを足しても、辞書を直して当て直せば元に戻せる。読み（誤認識の形）が残るので、辞書の候補の材料に使える（DEC-DIC-088）。キーを省略できるので、前の版の meeting.json もそのまま読め、前の版のアプリも新しい meeting.json を読める（知らないキーは無視される。前の版で保存し直すと `rawText` は消える）。
- 関係する要件: REQ-DIC-073, REQ-DIC-074
- 対象: Mac / Windows

### DEC-DIC-173 新しい会議には、文字起こしが確定した直後、議事録の前に 1 回当てる

- 決めたこと:
  - Mac は `MeetingRecorder.process` の `MeetingProcessor.buildUtterances` の直後、Windows は `MeetingPostProcessor.ProcessAsync` の `BuildUtterances` の直後に、設定がオンなら当ててから保存する。Windows は `MeetingPostProcessor` に辞書と設定を渡すプロパティを足し、作る 2 か所（`MeetingController` と `Hanasu.Cli/Program.cs`）で渡す。
  - 設定は Mac `AppSettings.applyDictionaryToMeetings`、Windows `AppSettings.ApplyDictionaryToMeetings`。既定はオンで、保存したファイルに項目がなければオンとして読む。
  - 記録中の発言（ライブの文字起こし・字幕・記録中の AI チャット）には当てない。
  - 照合の決まりは音声入力と同じ `UserDictionary.apply`（DEC-DIC-081〜083）を発言ごとに使う。そのため、2 つの発言にまたがる語（「ストック」｜「マーク」）には当たらない。これは受け入れる。
  - 横断検索は置き換えた後の文（`text`）だけで探す。認識したままの文では探さない。開いている PR #78 の `hanasu` コマンド・MCP が出す発言も、置き換えた後の文（`text`）にする。
  - 「確定した発言に、設定に応じて当てる」部分は、辞書と設定の値を引数で受け取る関数（Mac `MeetingDictionary.applyOnFinish(_:dictionary:enabled:)`）にし、`MeetingRecorder.process` はそれを呼ぶ。`process` には辞書と設定を外から渡せる口を足す（CLI の確かめで、本物の設定を書き換えないため）。
- 理由: 確定した発言は 1 か所で作られるので、そこに当てれば議事録・表示・書き出しにすべて効く。ライブの表示は認識のたびに書き換わり、確定後の発言で置き換わる。発言をまたいで当てると、発言の時刻と話者の区切りを作り直す必要があり、見合わない。
- 関係する要件: REQ-DIC-073
- 対象: Mac / Windows

### DEC-DIC-174 会議に当て直したら、議事録は作り直さず、作り直しを促す

- 決めたこと:
  - 当て直せる条件は、議事録に使う発言を変えられる条件と同じ（Mac `canEditMinutesSelection`、Windows `CanEditMinutesSelection`）に、使う発言が 1 つ以上あることを足したもの。認識したままの文に戻す操作も同じ条件で、作りは「すべての発言を `rawText ?? text` に戻し、`rawText` を消す」。
  - 変わった発言の数は、当てる前と後で `text` が違う発言の数で数える（Mac・Windows とも）。保存は失敗を受け取り、失敗したら一覧を元に戻して知らせる（`changeMinutesSelection` の `try?` は使わない）。
  - Mac は `changeMinutesSelection` と同じく、一覧（`meetings[index]`）をその場で書き換えてから保存する。あとで「議事録を作り直す」を押したとき、`regenerateMinutes` が一覧の古い会議から作らないようにする。
  - 発言が 1 つでも変わり、議事録があれば `minutesOutdated = true` にして、DEC-MTG-092 の帯を出す。議事録の作り直しは今の「議事録を作り直す」に任せ、DEC-MTG-072 の確かめもそのまま出す。
- 理由: 作り直すと議事録・アクションアイテムが置き換わり、リマインダーに登録した印（`ActionItem.reminderID`）も消える。辞書に 1 語足しただけで、確かめなしにそうならないようにする（ユーザーの回答）。作り直しを当て直しの流れから外すので、別の会議を記録している間（Mac で `state` が idle でない間）でも当て直しは働き、作り直しは今のボタンの条件に従う。
- 関係する要件: REQ-DIC-074, REQ-MTG-013
- 対象: Mac / Windows

### DEC-DIC-175 会議でも、辞書を語彙のヒントとして認識に渡す

- 決めたこと: 置き換えの設定（DEC-DIC-173）にかかわらず、会議の認識に辞書の語・読み・表記をヒントとして渡す（今と同じ。Mac `MeetingRecorder.start`・`MeetingBatchTranscription`、Windows `MeetingController.Context`）。
- 理由: DEC-DIC-085 を廃止しても、ヒントの振る舞いは残す。spec に書いておかないと暗黙の振る舞いになる。
- 関係する要件: REQ-DIC-073, REQ-MTG-003
- 対象: Mac / Windows

## やらないこと

- 設定の「辞書・ルール」の「候補を探す」（REQ-DIC-071）を Windows に移すこと。今回は会議ノートの入口だけ（FUT-003 に残す）。
- 辞書を会議ごと・案件ごとに分けること（ユーザーの回答で「今の辞書に足す」）。
- 会議が終わったら自動で候補を出すこと。外の議事録（貼り付けたテキスト・ファイル）から候補を出すこと。
- 候補の画面で表記を書き換えること。誤った表記は、追加してから設定で直し、「今の辞書をこの会議に当て直す」で当て直す。
- 当て直しのあとに議事録を自動で作り直すこと（ユーザーの回答）。議事録の文章そのもの（AI が書いた Markdown）に置き換えを当てること。
- 記録中のライブの文字起こし・字幕に置き換えを当てること。発言をまたぐ語に当てること（DEC-DIC-173）。
- 横断検索で認識したままの文も探すこと（DEC-DIC-173）。
- 長い会議を分けて何回も AI に送ること（DEC-DIC-170）。
- プロンプトの `dictionarySuggest.minutesHeader` の「Gemini が」の表記を直すこと（今も Claude・ローカルで使われているが、今回の範囲の外）。

## 手順

1. **spec と roadmap**（この手順が終わってから 2〜4 に入る）
   - `docs/spec/dictation.md` に REQ-DIC-072・073・074、DEC-DIC-170〜175 を書く。DEC-DIC-085 を「## 廃止」へ移す。DEC-DIC-088 を書き足す。書く前に `git fetch origin && gh pr list --state open` で、ほかの PR が同じ番号を使っていないかを確かめ直す。
   - `docs/spec/meeting.md` の DEC-MTG-090・091・092、`docs/spec/common.md` の DEC-COM-107、`docs/spec/dictation.md` の DEC-DIC-087・089 を直す（「変える設計判断」のとおり）。
   - `docs/roadmap.md`: FUT-104 を「実装した → REQ-DIC-073, REQ-DIC-074」に。FUT-003 の「辞書の候補の提案」に「会議ノートからは REQ-DIC-072 で足した。設定からは未実装」と書く。この計画を参照し、実装したら状態を直す。
2. **Mac**（3 とは独立して進められる）
   - `MeetingModels.swift`・`MinutesSelection.swift`: `Utterance.rawText: String?`、まとめた発言の認識したままの文、`Meeting.transcriptForPrompt(raw:)`。
   - `MeetingDictionary.swift`（新規）: `apply(_ dictionary: UserDictionary, to meeting: Meeting) -> (meeting: Meeting, changed: Int)`。
   - `Settings.swift`: `applyDictionaryToMeetings`（既定 true）。`SettingsView.swift` の会議の欄（「記録後に AI で議事録を作る」の上）にトグル。
   - `MeetingDictionary.swift` に `applyOnFinish(_:dictionary:enabled:)`・`revert(_:)` も置く。
   - `MeetingRecorder.swift`: `process` に辞書と設定を外から渡せる口を足し、`applyOnFinish` を呼ぶ（DEC-DIC-173）。`applyDictionary(to:)`・`revertDictionary(of:)` を足す（結果は変わった発言の数か失敗の理由。DEC-DIC-174）。`start` のタグを DEC-DIC-175 に付け替える。
   - `PromptText.swift`: `material` をタグの一覧に足し、`DictionarySuggester.userPrompt` で材料を通す。
   - `DictionarySuggester.swift`: `corpus(for meeting:)`、上限を会議の AI から決める `limit(for:)`、切った範囲を返す `promptText`（DEC-DIC-170）。今の `promptText` の会議の部分も認識したままの文にする（DEC-DIC-088）。
   - `MeetingDictionaryViews.swift`（新規）: `MeetingDictionaryMenu`・`MeetingDictionarySheet`。`DictionarySettingsView.swift` から候補の行を切り出して共有する。`MeetingWindow.swift` の `MeetingDetailView` に置く。`MinutesSelectionViews.swift` の `MinutesOutdatedNotice` の文言を直す。
   - `MeetingDictionaryCLI.swift`（新規）と `main.swift`: `--test-meeting-dictionary`（失敗で終了コード 1）、`--suggest-dictionary --meeting <フォルダ>`、`--render-meeting-dictionary <出力フォルダ>`（探している・候補あり・0 件・エラー・長くて切った、の候補の画面 5 枚と、「辞書」のメニューと帯の出た詳細画面）。`--meeting-files` に `--dictionary <ファイル>` と `--no-meeting-dictionary` を足し、`process` の口に渡す（本物の設定は読まない・書き換えない）。`// 確かめ方: REQ-DIC-072` / `073` / `074` を付ける。
3. **Windows**（2 とは独立して進められる）
   - `Hanasu.Core/Meetings/MeetingModels.cs`・`MinutesSelection.cs`: `Utterance.RawText`（null なら JSON に書かない）と `Copy()`、まとめた発言の認識したままの文、`Meeting.TranscriptForPrompt(raw)`。
   - `Hanasu.Core/Meetings/MeetingDictionary.cs`（新規）: `Apply`。
   - `Hanasu.Core/Settings`: `AppSettings.ApplyDictionaryToMeetings`（既定 true）。
   - `MeetingPostProcessor`: 辞書と設定のプロパティを足して `ProcessAsync` で当てる。`MeetingController`（`ProcessAsync` で作るところ）と `Hanasu.Cli/Program.cs` で渡す。`MeetingController.ApplyDictionary(meeting)`・`RevertDictionary(meeting)` を足す。`Context` にタグ DEC-DIC-175。
   - `Hanasu.Core/Ai/PromptText.cs`: `material` をタグの一覧に足し、`DictionarySuggester.UserPrompt` で材料を通す。
   - `Hanasu.Core/Text/DictionarySuggester.cs`（新規）: Mac の `DictionarySuggester` の会議 1 件の `Corpus`・上限・`UserPrompt`・`Parse`・`Filter`・`Appending` の移植。
   - `Hanasu.Windows/Views/MeetingDictionaryWindow.cs`（新規）、`MeetingWindow.xaml(.cs)` の「辞書…」のボタンと `ContextMenu`、`Show(Meeting)` での有効・無効、`MinutesOutdatedPanel` の文言。`SettingsWindow.xaml(.cs)` のチェックボックスと `Settings.Changed` の購読（DEC-DIC-171）。
   - テスト: `Hanasu.Core.Tests/MeetingDictionaryTests.cs`（置き換え・当て直し・ルールを消して戻る・`RawText` の往復・Mac の meeting.json との互換・まとめた発言の材料）、`MeetingTests.cs` の `MeetingControllerTests` に足す（止めたあとに当たる・設定がオフなら当たらない・`ApplyDictionary` で変わる／変わらない／議事録なしでは帯を立てない・変わった発言の数・`RevertDictionary` で戻る）、`DictionarySuggesterTests.cs`（`Parse`・`Filter`・`Appending`・材料からオフレコが抜ける・文字起こしが先・上限で切る・`<material>` の無害化。AI は `FakeHandler`）、`SettingsTests.cs`（項目のない設定のファイルで `ApplyDictionaryToMeetings` がオン）。
   - CLI: `Hanasu.Cli/Program.cs` に `meeting-dict-suggest <会議のフォルダ> [--dict <辞書ファイル>]`（辞書の指定は今の `--dict` に合わせる。使い方のコメント・case・default の一覧の 3 か所）。
4. **UI の文字列を 17 言語で**（2・3 のあと。i18n スキル。i18n エージェントに言語を分けて任せる）
   - Mac: `tr(...)` で書き、`python3 scripts/i18n-strings.py sync` で `Localizable.xcstrings` にそろえて訳を入れる。
   - Windows: 画面の文字列は `Hanasu.Windows/Properties/Strings*.resx`、Core が出す文字列（材料を切った知らせ・応答を読めないときの理由）は `Hanasu.Core/Properties/Strings*.resx`。英語が `Strings.resx`。`scripts/i18n-resx.py`。
   - 足す文字列（案。Mac と Windows の両方）: 「辞書」（Windows は「辞書…」）、「この会議から辞書の候補を探す…」、「今の辞書をこの会議に当て直す」、「この会議を認識したままの文に戻す」、「この会議の文字起こしにも辞書を当てる」、「会議が長いので、文字起こしの最初の約 %@ 分だけを読みました。」、「当て直して、%@ 件の発言が変わりました。」、「当て直しました。変わった発言はありませんでした（辞書で置き換えてある発言: %@ 件）。」、「認識したままの文に戻し、%@ 件の発言が変わりました。」、「この会議を変えられませんでした: %@」、「文字起こしに辞書の置き換えルールを当てる」とその説明、候補の画面の題と説明（会議の中身は会議に選んだ AI にだけ渡す。Windows 版は Apple を除いた文面）、候補の一覧のアクセシビリティの名前。Mac の `LocalModelDownloadPrompt.prepare` に渡す「辞書の候補探し」と「候補を探さずに閉じます」。Windows には、Mac に既にある「探しています…」「選んだ %@ 件を辞書に追加」「新しい候補は見つかりませんでした。」「追加したいものを選んでください（%@）。」「%@ 件を辞書に追加しました。」も足す。
   - 変える文字列: DEC-MTG-092 の帯の文言（Mac・Windows）。
   - プロンプトは変えない。
5. **文書**
   - `README.md` の辞書の行（「On Mac, the AI can also suggest new entries from your history and meetings」）を、Windows でも会議ノートから候補を出せること、会議の文字起こしにも当たることが分かるように直し、`README.ja.md`（英語と並んで正）と 15 の訳（`README.<言語>.md`）にも同じ変更を入れる（docs/README.md の 8 章）。
   - `docs/guide.md` の「ユーザー辞書」の節に、会議ノートからの候補・当て直し・新しい会議への置き換えと設定を書く（「外部の送り先は Gemini だけ」の古い記述も直す）。
   - `docs/design/dictation.md` の 5.4（「会議の記録では、語彙ヒントにだけ使う…FUT-104」を直す）・5.5、`docs/design/meeting.md` の後処理の流れ、`windows/README.md` の「Mac 版との差」（辞書の候補の行を「会議ノートからは作った。設定からは未実装」に）・会議の使い方・会議の作りの図。
   - `docs/design/security.md` の 7 章の「辞書の候補」の記述（`<material>` の無害化）と、`docs/design/security-windows.md` に、会議の中身を辞書の候補のために会議の AI に送ることを書く。
   - UI のテスト項目: `common/testdata/ui/meeting.json` に、候補の画面と帯（Mac は `render`、Windows は `manual`）、「辞書」のメニューを選べない条件（Mac・Windows とも `manual`）を足し、`python3 scripts/ui-cases.py md` と `check`。
6. **確かめる**（下）

## 確かめ方

- `swift build`
- `.build/debug/Hanasu --test-meeting-dictionary`（置き換え・当て直しで元に戻る・表記を直して当て直す・認識したままの文に戻す・変わらなければ `rawText` なし・変わった発言の数・`applyOnFinish` のオン／オフ・設定の項目がないときの既定がオン・まとめた発言の材料が認識したままの文・材料にオフレコが入らない・文字起こしが先・上限で切って分を出す・ローカル／Apple の上限・`rawText` のない古い meeting.json を読める・`<material>` の無害化）
- `.build/debug/Hanasu --meeting-files <me> <others> --dictionary <辞書>` と `--no-meeting-dictionary`（辞書の読みを話した音声で、止めたあとの処理に置き換えが当たる・当たらない。本物の設定は変えない）
- `.build/debug/Hanasu --test-dictionary`（音声入力の辞書の振る舞いが変わっていない）、`--test-minutes-selection`
- `.build/debug/Hanasu --render-meeting-dictionary <出力フォルダ>` を ui-test スキルで見る。英語・ドイツ語・ロシア語（長い文言で上のボタンの並びが詰まらないか）とアラビア語（右から左）でも崩れないか
- `.build/debug/Hanasu --suggest-dictionary --meeting <会議のフォルダ>`（実際に AI を呼ぶ。手元の会議で 1 回）
- `cd windows && dotnet test Hanasu.Core.Tests`
- `python3 scripts/check-spec.py`、`python3 scripts/check-spec.py --diff origin/main`、`python3 scripts/check-i18n.py`、`python3 scripts/ui-cases.py check`
- 実機で見ること:
  - Mac: 会議を記録して止め、辞書のルールが文字起こしと議事録に当たる。設定をオフにすると当たらない。会議ノートの「辞書」→ 候補を探す → 選んで追加 → 辞書の末尾に入り、その会議の文字起こしが直り、議事録の上に帯が出る。帯の「議事録を作り直す」で確かめが出る。キャンセルで何も変わらない。別の会議を記録している間も当て直せる。ルールを消して当て直すと戻る。
  - Windows: 同じことを実機で。設定画面を開いたまま会議ノートで足しても、設定画面の辞書の欄に足した行が出て、消えない。

## 敵対的レビュー

2026-11-09、requirements-reviewer（Opus）。1 回目は 2 つ並べて（A は目的・受け入れ条件・失敗時・範囲・ユーザーが決めること、B は既存の要件・Mac と Windows・17 言語・データと安全・手順の事実・確かめ方）。1 回目の答えで要件が増えたので、直した計画で 2 回目（C、観点すべて）。

1 回目:

| # | 重さ | 指摘 | 仕分け | どうしたか |
| --- | --- | --- | --- | --- |
| A1 | 重大 | 会議に当て直す入口が候補の画面しかなく、候補 0 件・手で足した語・表記の誤り・ルールを消して戻す、ができない | 聞く | 「今回入れる」の答えで REQ-DIC-074 を足した |
| A2 | 重大 | 新しい会議すべてに、オフにできずに置き換えを当てることを聞いていない | 聞く | 「当てる。設定でオフにできる」の答えを REQ-DIC-073 に入れた |
| A3・B4 | 重大 | 確かめなしの議事録の作り直しで、DEC-MTG-072 を黙って外している。アクションアイテムのリマインダーの印も消える | 聞く | 「作り直しを促すだけ」の答えで DEC-DIC-174 にし、DEC-MTG-092 の帯を使う |
| A4・B1 | 重大 | Mac の `regenerateMinutes` は idle でないと黙って戻り、一覧の古い会議から作り直して置き換えを消す。失敗時に議事録が古い印が残らない | 直す | 作り直しを当て直しの流れから外し、一覧をその場で書き換え、`minutesOutdated` を立てる（DEC-DIC-174） |
| A5・B10 | 重大 | 60,000 字の上限は、ローカル・Apple では AI の側で黙って切られ、知らせが誤る。議事録が後ろなので先に落ちる | 直す | 上限を会議の AI の文脈から決め、議事録を先に置き、文字起こしを切ったときだけ知らせる（DEC-DIC-170） |
| B2 | 重大 | DEC-DIC の 160 番台の 2 つは、開いている PR #78 が使っている | 直す | DEC-DIC-170〜175 にした（PR #78 の `docs/spec/dictation.md:1316` で確かめた） |
| B3 | 重大 | README.md の 47 行目（と 15 の訳）・`docs/guide.md` の辞書の節が古くなる | 直す | 手順 5 に足した |
| B5 | 重大 | Windows のフィルタが `MeetingControllerTests` を拾わない。作り直しの条件・`process` への差し込み・押せない条件の確かめ方がない | 直す | フィルタと列挙するテストを直し、Mac は `--meeting-files --dictionary`、押せない条件は UI のテスト項目にした |
| A6 | 軽微 | キャンセルで AI の呼び出しを止めると書いていない | 直す | DEC-DIC-170 に書いた |
| A6 | 軽微 | 検索で誤認識の形が当たらなくなる | 直す | 置き換えた後の文だけで探すと DEC-DIC-173 に書き、やらないことに足した |
| A6 | 軽微 | 開き直すたびに AI を呼ぶ | 直す | DEC-DIC-171 と「仮に決めたこと」に書いた |
| B6 | 軽微 | 発言をまとめるときに `rawText` が消え、読みが材料から落ちる | 直す | DEC-DIC-172 にまとめ方を書き、確かめる項目に足した |
| B7 | 軽微 | DEC-DIC-085 の「ヒントに渡す」部分が宙に浮き、タグが廃止の ID を指す | 直す | DEC-DIC-175 を足し、タグを付け替える手順を書いた |
| B8 | 軽微 | Windows の Core の resx と既存の文字列が抜けている。`MeetingPostProcessor` に辞書を渡す口がない | 直す | 手順 3・4 に足した |
| B9 | 軽微 | 発言ごとに当てるので、発言をまたぐ語に当たらない | 直す | 限界として DEC-DIC-173 に書いた |
| B11 | 軽微 | security.md に指した一覧がない。`<material>` を無害化していない | 直す | `<material>` を無害化の一覧に足し（DEC-DIC-170）、security.md の 7 章と security-windows.md に書く手順にした（Windows の文書はある） |
| B12 | 軽微 | WPF の `IsFocused` では読み直されず、足した行が消える | 直す | `IsKeyboardFocused` と書いた（DEC-DIC-171） |

2 回目:

| # | 重さ | 指摘 | 仕分け | どうしたか |
| --- | --- | --- | --- | --- |
| C1 | 重大 | 「議事録も直す」を作り直しを促すだけに狭めた。議事録とアクションアイテムの本文に置き換えだけを当てる案（AI を呼ばない、リマインダーの印も消えない）を聞いていない | 聞く（質問の回数を使い切ったので推奨で仮に決めた） | 「仮に決めたこと」の 1 つ目。了承のときに選んでもらう |
| C2 | 重大 | 「あとで戻せます」と伝えたのに、会議ごとに戻す操作がない（辞書は音声入力と共有） | 聞く（同上） | 「この会議を認識したままの文に戻す」を REQ-DIC-074 に入れ、「仮に決めたこと」に書いた |
| C3 | 重大 | 候補の画面のチェックが、新しい会議の設定をオフにした人にも既定でオン | 直す | 既定を設定の値にそろえた（REQ-DIC-072） |
| C4 | 重大 | 「M か所」の数え方が決まっていない。自動で当てた直後の当て直しで「置き換える語はありません」と出て誤解を招く。保存の失敗を知らせない | 直す | 変わった発言の数にし、0 件のときは置き換え済みの数も出す。失敗の知らせを足した（REQ-DIC-074・DEC-DIC-174） |
| C5 | 重大 | 議事録を先に置き、1 字 1 トークンで見積もると、ローカル・Apple で文字起こし（読みの出どころ）が落ちる | 直す | 文字起こしを先にし、今ある数え方を使う（DEC-DIC-170） |
| C6 | 重大 | `--meeting-files --dictionary` では設定オフを確かめられない（本物の設定を読む） | 直す | 当てる部分を関数にし、`process` に口を足し、`--no-meeting-dictionary` を足した（DEC-DIC-173・手順 2） |
| C7 | 軽微 | DEC-MTG-090・091、DEC-COM-107、DEC-DIC-087・089 が事実と合わなくなる | 直す | 「変える設計判断」と手順 1 に足した |
| C8 | 軽微 | `LocalModelDownloadPrompt` の文言・ウインドウの題などの文字列、`neutralizeDelimiters` の呼び出し、`README.ja.md`、ドイツ語・ロシア語の描き出し、PR #78 の CLI・MCP が出す文、Windows の `--dict`、設定の既定の確かめ方が抜けている | 直す | 手順 2〜5・確かめ方・DEC-DIC-170・173 に足した |

見られなかったこと:
- アプリの側で切った材料が、ローカルのモデルの実際のトークン数に収まるか（実装のときに `--test-meeting-dictionary` とローカルのモデルで確かめる）。
- Mac の `.sheet` の中から `LocalModelDownloadPrompt` のアラートを出したときに前に出るか、Windows の `SettingsWindow` が `Settings.Changed` をどのスレッドで受けるか（実装と実機で確かめる）。
- PR #78 が `MeetingModels.swift`・`MeetingSearch.swift` を変えているので、どちらかが先に入ったら、あとの方で取り込んでぶつかりを直す。

## 仮に決めたこと

- **議事録の本文には置き換えを当てない（作り直しを促すだけ）。** 2 回目のレビューで、議事録とアクションアイテムの本文に置き換えルールだけを当てる案（AI を呼ばず費用なし、リマインダーの印も消えない。ただし議事録には認識したままの文がないので戻せず、AI が書いた文に機械的に当たる）が挙がった。お聞きした 3 つの選択肢にはこの案がなかった。推奨は「当てない」（戻せない変更を議事録に入れないため）。当てる方がよければ、了承のときにそう言ってください。
- **「この会議を認識したままの文に戻す」を入れる。** 「あとで戻せます」とお伝えしたことに合わせた（作りは小さい）。要らなければ外します。
- 候補の画面の「この会議の文字起こしにも辞書を当てる」の既定は、新しい会議に当てる設定と同じにする。
- 候補の画面は開いたらすぐ探し、閉じたら結果を捨てる。開き直すとまた AI を呼ぶ（長い会議なら 1 回で最大 60,000 字ぶんの費用）。
- 入口は「辞書」のメニュー 1 つに 2 つの項目をまとめる。
- 長い会議は分けて送らず、上限で切って知らせる。
