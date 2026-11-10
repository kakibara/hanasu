# AI チャット・会議への質問のモデルを、議事録と分けて選び、画面でも切り替える

- 状態: 実装済み（2026-11-10 に計画を了承）。要件と設計判断は spec に移した: REQ-COM-025・DEC-COM-171・DEC-COM-172（[spec/common.md](../spec/common.md)）、REQ-MTG-048・REQ-MTG-049・DEC-MTG-150（[spec/meeting.md](../spec/meeting.md)）。この文書は計画と敵対的レビューの記録として残す
- 番号: 計画を書いたときは、要件の 2 つと送り先のメニューの設計判断に、先に main に入った PR #94（「何を聞かれた？」）と同じ番号を使っていたので、REQ-MTG-048・049・DEC-MTG-150 に付け直した（この文書の中も付け直した番号で書く）
- PR #94 との合わせ: 「何を聞かれた？」（REQ-MTG-047）は答えをその会議の AI チャットの会話に入れるので、AI チャットと同じ送り先（画面で切り替えていればそれ、なければ「AI チャット・質問」）で聞くようにした（DEC-MTG-150 に書いた）。#94 の計画も「AI と effort はチャットと同じ」としていた
- 対象: Mac（Windows 版には AI チャットと会議への質問がない。roadmap の FUT-003 の本文、windows/README.md の「会議の横断検索・会議への質問（Ask）」）

## 目的
2026-11-10 の依頼「AIチャット画面でAIのモデルをデフォルトから切り替えられるようにしてください」「あと、AIチャットのモデルも別に設定できるようにしてください。」

今は AI チャット（記録中・会議ノート）も「会議に質問」も、設定の「会議」で選んだ AI とモデル（`TextAIPurpose.meeting`）に固定で送っている（DEC-MTG-081、`MeetingChatModel.send`、`MeetingAskModel`）。議事録には重く賢いモデル、対話には速いモデル、という使い分けができず、質問ごとに試すこともできない。

ユーザーとのやりとり（同日）で決まったこと:
- 画面では AI もモデルも選べる。
- 画面での切り替えは、その会議の会話だけに効く（設定の既定は書き換えない）。
- 設定の「AI チャット・質問」は、会議とは独立した値。既存の利用者にも会議の値を写さない（完全に独立）。
- 「会議に質問」も「AI チャット・質問」の設定を使う（「会議の AI は議事録の要約用、質問などの対話のモデルは別に設定する」という棲み分け）。「会議に質問」の画面にも、その場で切り替えるメニューを付ける。
- Claude を選んだときの既定は Haiku 5.5。

## 要件の案

### REQ-COM-025 AI チャットと会議への質問に使う AI とモデルを、議事録とは別に選べる（新規）
- 内容: 設定の「AI」→「使う AI とモデル」に、「音声入力」「会議」に加えて「AI チャット・質問」の行を足し、会議の AI チャット（記録中・会議ノート）と会議への質問（REQ-MTG-016）に使う AI（ローカル / Apple / Gemini / Claude）とモデルを選べる。「会議」の行は議事録（作り直しを含む）と辞書の候補探しだけに使う。
- 受け入れ条件:
  - 設定の「AI」タブに 3 行が並び、それぞれの説明は「整形・翻訳・選択の編集」「議事録（作り直しも）・辞書の候補」「会議の AI チャット・会議への質問」。「AI チャット・質問」の行で AI とモデルを選べる（`--render-ai-settings`）。
  - 「AI チャット・質問」に Claude Haiku 5.5、「会議」に Claude Sonnet 5.5 を選ぶと、議事録は Sonnet、AI チャットと会議への質問は Haiku で送る（AI を呼ばずに送り先を出す `--show-target`。下の確かめ方）。
  - 既定は、新しく使い始めた人も以前から使っている人も、ローカルの Gemma 4 E4B（会議の値は写さない）。この AI で Claude を選んだときの既定のモデルは Haiku 5.5、Gemini は gemini-3.8-flash（DEC-COM-171）。
  - 既定のままの送り先が使えない（以前から使っている人で Gemma を入れていない等）とき、AI チャットと会議に質問の画面は、送る前にそのことと直し方（画面のメニューで選ぶ・設定の「AI」）を出す。送ったときは今のエラーの文言で知らせる（何も送らない）。
  - 初回起動のオンボーディングで AI を選ぶと、3 つの用途すべてにその AI を入れ、「設定の Tips」のページにも 3 行を出す（REQ-COM-050・051、DEC-COM-092）。
- 出典: 2026-11-10 の依頼「AIチャットのモデルも別に設定できるようにしてください」と同日の回答（了承の日付を足す）
- 対象: Mac
- 実装の場所: `TextAIPurpose.chat`、`AppSettings`（`chatAIProvider`・`claudeChatModel`・`geminiChatModel`・`localChatModel`・`aiProvider(for:)`・`textModel(for:)`・`localModel(for:)`）、`AIChoiceRow`、`AISettingsTab`、`OnboardingModel`、`OnboardingTipsPage`（名前は実装で確かめる）
- 確かめ方: `.build/debug/Hanasu --test-ai-purposes`（新設。AI を呼ばない）、`--chat-meeting … --show-target`、`--ask-meetings … --show-target`、`--minutes-from-transcript … --show-target`、`--render-ai-settings /tmp/ai.png --claude`

### REQ-MTG-048 AI チャットの画面で、その会議の会話に使う AI とモデルを既定から切り替えられる（新規）
- 内容: AI チャットの入力欄の下に、今の送り先（AI とモデル）を出し、押すと AI とモデルの一覧から選べる。選んだものは、その会議の会話にだけ効き、次の質問から使う。ほかの会議・アプリの終了後・設定の既定は変わらない。
- 受け入れ条件:
  - 入力欄の下に「送り先: Claude · Haiku 5.5」のように出る。押すと、先頭に「既定（<設定の AI とモデル>）」、その下に AI ごとにローカル（4 つ）・Apple・Gemini（候補のモデル）・Claude（3 つ）が並ぶ。今の送り先に印が付く。
  - 使えないもの（Claude の API キーがない、Gemini の認証がない、ローカルのモデルが未ダウンロード、Apple の fm が使えない）は、項目の文字に理由（「未設定」「未ダウンロード」「使えません」）を添えて選べなくする。
  - 選ぶと、次に送る質問からその AI とモデルに送る。それまでの会話はそのまま続く（REQ-MTG-041）。答えの下に、その答えを作った AI とモデルの名前が出る。
  - 既定から切り替えている間は、送り先の表示に既定から変えていることが分かる印が付き、一覧の「既定」で戻せる。
  - 送り先が外の AI（Gemini・Claude）なら「文字起こしとメモをこの AI に送ります」、ローカル・Apple なら「この Mac の外には送りません」と出し、どちらも「会話は保存しません」を添える（DEC-MTG-085）。
  - 記録中に切り替えた会議を、記録のあと会議ノートの AI チャットで開いても、同じ切り替えが続く（DEC-MTG-086 の同じ会話）。別の会議を開くと既定で始まる。アプリを終了すると既定に戻る。「新しい会話」では戻らない。
  - 答えを待っている間は切り替えられない。
- 出典: 2026-11-10 の依頼「AIチャット画面でAIのモデルをデフォルトから切り替えられるようにしてください」と同日の回答（了承の日付を足す）
- 対象: Mac
- 実装の場所: `MeetingChatModel`（`override`）、`MeetingChatView`、`AIRouteMenu`（新設。AI チャットと会議に質問で共有）、`MeetingChat.Message`（`modelLabel`）、`TextAIClient.make`
- 確かめ方: `.build/debug/Hanasu --test-meeting-chat`（切り替えの有無で送り先が変わる・使えない選択肢の判定）、`--render-meeting-chat <出力フォルダ>`（既定・切り替え中・既定が使えないの 3 枚）、実機で一覧を開いて選ぶ

### REQ-MTG-049 「会議に質問」の画面でも、使う AI とモデルを既定から切り替えられる（新規）
- 内容: 会議に質問の画面にも REQ-MTG-048 と同じ送り先のメニューを出し、その画面での質問に使う AI とモデルを選べる。設定の既定は変わらない。
- 受け入れ条件:
  - 質問の入力欄の近くに「送り先: …」のメニューがあり、一覧・使えないものの扱い・既定に戻すは REQ-MTG-048 と同じ。外に送るかの文は、この画面が送るものに合わせて「検索で選んだ会議の議事録と文字起こしをこの AI に送ります」（ローカル・Apple なら「この Mac の外には送りません」）にする。
  - 選んだものは次の質問から使う。会議のウインドウを閉じるか、アプリを終了すると既定に戻る（ウインドウは閉じても残す作りなので、閉じる通知で戻す）。
  - 答えを待っている間は切り替えられない。
- 出典: 2026-11-10 の回答「（会議に質問の画面にもメニューを）付ける」（了承の日付を足す）
- 対象: Mac
- 実装の場所: `MeetingAskModel`（`override`）、`MeetingAskView`、`AIRouteMenu`
- 確かめ方: `.build/debug/Hanasu --test-meeting-chat`（共有の判定）、`--render-meeting-search`（会議に質問の画面を描く CLI。名前は実装で確かめる）、実機

### 変える要件（ユーザーの合意が要る）
「会議（議事録・会議への質問・辞書の候補）」と書いている要件を、「会議（議事録・辞書の候補）」と「AI チャット・質問（AI チャット・会議への質問）」に分ける。Windows の記述は変えない。
- **REQ-COM-020**: 「整形などに使う AI」の対象に、AI チャット・質問の用途があることを足す。
- **REQ-COM-023**: Claude の既定に「AI チャット・質問は Haiku 5.5」を足す（Mac）。
- **REQ-COM-024**: Mac の受け入れ条件を 3 用途に（音声入力 / 会議（議事録・辞書の候補）/ AI チャット・質問）。Windows の行は変えない。
- **REQ-COM-030**・**REQ-COM-031**: 「会議: 議事録・会議への質問・辞書の候補」を「会議: 議事録・辞書の候補、AI チャット・質問: AI チャット・会議への質問」に。ローカルのモデルがないとき、AI チャット・会議への質問は設定（または画面のメニュー）へ案内する（今の会議への質問と同じ扱い）。
- **REQ-COM-050**: 「音声入力と会議の両方の AI が…になり」→「音声入力・会議・AI チャット・質問の AI が…になり」。
- **REQ-COM-051**: 「設定の Tips」の受け入れ条件「音声入力と会議のそれぞれの AI とモデルを選べ」→「音声入力・会議・AI チャット・質問のそれぞれの…」。

### 直す設計判断
- **DEC-COM-040**: 用途に AI チャット・質問を足し、「会議への質問は会議の AI」を外す。
- **DEC-COM-042**: Claude のモデルを「音声入力・会議・AI チャット・質問で別々に持つ（`claudeModel`・`claudeMinutesModel`・`claudeChatModel`）」に。
- **DEC-COM-043**: effort は機能で決まる（議事録・会議への質問・辞書の候補は medium、AI チャットは low）と書き直す。用途では決めない。
- **DEC-COM-064**: ローカルの出力の上限と待つ時間を、用途の言葉ではなく処理の長さ（短い処理: 整形・英訳・選択の編集・辞書の候補・AI チャット / 長い処理: 議事録・会議への質問）で書き直す（今のコードの `effort` → `.short`/`.long` に合わせる）。
- **DEC-COM-092**: オンボーディングは 3 用途。
- **DEC-MTG-053**: 会議への質問のモデルは `meetingMinutesModel` → AI チャット・質問の用途のモデル（画面で切り替えていればそれ）。
- **DEC-MTG-081**: 送り先を「AI チャット・質問に選んだ AI とモデル（`TextAIPurpose.chat`）、または画面で切り替えたもの」に。
- **DEC-MTG-085**: 送り先の表示を、切り替えのメニューと、外に送るかの文に。

## 設計判断の案

### DEC-COM-171 AI チャット・質問の設定は会議と独立させ、既定は速さを優先する
- 決めたこと: 用途 `TextAIPurpose.chat`（表示は「AI チャット・質問」）を足し、設定のキーを `chatTextAIProvider`・`claudeChatModel`・`geminiChatModel`・`localChatModel` にする。既定は AI がローカル、モデルはローカル Gemma 4 E4B・Claude `claude-haiku-5-5`・Gemini `gemini-3.8-flash`。以前から使っている人にも会議の値を写さず、引き継ぎの印も足さない（`hasSavedSettings` が数えるキーを増やさない。新しい印を書くとオンボーディングが出なくなるため）。DEC-COM-068 の Gemini への引き継ぎも、この用途には当てない。ローカル・Apple の最低の待ち時間は、音声入力以外と同じ。`purpose == .dictation ? A : B` の形で書かれた場所（`AIChoiceRow` の binding と説明、`AppSettings.aiProvider(for:)`・`localModel(for:)`、`TextAIClient.cliModel`）は、3 用途を網羅する switch に書き直す（`LocalLLMClient.minimumTimeout`・`AppleFMClient.minimumTimeout` は「音声入力か、それ以外か」の意味なので三項のまま残す）。
- 理由: ユーザーが「最初から独立した値」「既存の利用者にも写さない」を選んだ（2026-11-10）。対話は待ち時間が短いほうがよい。Gemini の lite は長い記録からの答えで質が落ちやすいので、議事録と同じ flash にする。網羅の switch にすれば、次に用途を足したときにコンパイルで気づける。
- 関係する要件: REQ-COM-025, REQ-COM-023, REQ-COM-024
- 対象: Mac
- 影響（以前から使っている人で、会議を Gemini・Claude にしている人）:
  - Gemma 4 E4B を入れていない人は、この版に上げると AI チャットと会議に質問が「未ダウンロード」で止まる。画面に出す案内（REQ-COM-025 の受け入れ条件 4 つ目）で知らせる。
  - Gemma 4 E4B を入れている人（例: 音声入力 = ローカル、会議 = Claude）は、止まらずに送り先がローカルに変わる。会議への質問はローカルの文脈（32,768 トークン）に入らない分を省く（DEC-COM-065）ので、答えが浅くなりうる。送り先はメニューのボタンに常に出る（REQ-MTG-048・049）ので画面で気づけるようにし、リリース文でも知らせる。

### DEC-COM-172 AI チャット・質問と議事録は、ローカルのモデルを切り替えるとき、使っている処理が終わるのを待つ（音声入力は今のまま）
- 決めたこと:
  - `LocalLLMServer` で「サーバーを使っている処理」（`activeRequests`。起動のあとに数える）と「起動を待っている処理」（`waitingRequests`）を分けて数える。待っている処理は、使っている処理が 0 になったら、来た順に 1 つずつ進む。先に進んだ処理と同じモデルを待っていた処理は、起動し直さずにそのまま通る。5 分で止める判定（DEC-COM-063）は、待っている処理があるときも止めない。
  - 待つのは、`LocalLLMClient` に `waitsForOtherModel = true` を付けた処理（AI チャット・会議への質問（`.chat`）と、議事録・辞書の候補（`.meeting`））。音声入力（`.dictation`）は今のまま、違うモデルを求めたら処理中でもサーバーを止めて起動し直す。
  - 待ちには期限を付ける（`beginRequest(model, deadline:)`。期限はその処理のタイムアウトと同じ）。過ぎたら「ほかの処理（議事録の作成など）が終わらないため、ローカルの AI を使えませんでした」で失敗させる。Task の取り消し（「止める」）にも従う。
  - 送る前に `LocalLLMServer.wouldWait(for:)` で待つかどうかを見て、待つなら AI チャット・会議に質問の表示を「ほかの処理が終わるのを待っています…」にする。
  - 待つかどうか・誰が先に進むかの判断は、サーバーを起こさずに試せるよう小さな型（`LocalLLMGate`）に切り出す。
- 理由: 今は違うモデルを求められると、処理中でもサーバーを止める（`stop()`）。AI チャット・質問のローカルのモデルを会議と別にできるようになると、記録を止めた直後の議事録の作成（ローカルでは最大 30 分）中にチャットで聞くと、議事録が途中で切れる（DEC-MTG-086 の「会議が終わった直後に続けたい」場面）。待てば議事録は守られ、チャットは遅れるだけ。待っている処理を「使っている処理」と同じに数えると、待つ処理どうしが止まり合うので分ける。音声入力は依頼の外で、待たせると整形が最大 120 秒遅れたうえ失敗しうる（REQ-DIC-007）ので、今の振る舞いを変えない（音声入力が議事録を止めうるのは今と同じ）。
- 関係する要件: REQ-COM-030, REQ-COM-025, REQ-MTG-048, REQ-MTG-049
- 対象: Mac（Windows の `LocalLlmServer` にも違うモデルで止める同じ作りがあるが、Windows には AI チャットと会議への質問がなく、議事録と整形のモデルの組み合わせは今のまま。直すなら FUT に足す）
- 実装の場所: `LocalLLMServer.beginRequest`・`ensureRunning`・`wouldWait(for:)`、`LocalLLMGate`、`LocalLLMClient.waitsForOtherModel`、`TextAIClient.make`

### DEC-MTG-150 送り先の切り替えは、入力欄の下のメニューで、会議ごと（会議に質問は画面ごと）のメモリに持つ
- 決めたこと:
  - 部品: `AIRouteMenu`（SwiftUI の `Menu`）を、AI チャットの入力欄の下（今の「…に送ります。会話は保存しません。」の場所）と、会議に質問の入力欄の近くに出す。ボタンは「送り先: <AI> · <モデル>」（切り替え中は印つき）。その下に、外に送るかの文（REQ-MTG-048）を出す。
  - 一覧: 先頭に「既定（<AI> · <モデル>）」。続けて AI の並び（DEC-COM-168: ローカル・Apple・Gemini・Claude）でセクションに分ける。Gemini は `AppSettings.suggestedModels` と、設定の Gemini のモデル（3 用途）のうち一覧にないもの。Claude は `ClaudeClient.Model.allCases`。ローカルは `LocalLLMModel.allCases`。
  - 使えるかの判定は中身を読まずに行う（DEC-COM-049）: Claude は `Keychain.exists(.claudeAPIKey)`、Gemini は API キーなら `Keychain.exists(.geminiAPIKey)`、サービスアカウントならパスが空でなくファイルがあること、ローカルは `LocalLLMStore.isDownloaded`、Apple は `AppleFMAvailability.check()`（署名を確かめるので、AI チャット・会議に質問の画面が出たときに 1 回だけ確かめて model に覚える。描くたびには呼ばない）。使えない項目は `.disabled` にし、理由は項目の文字に入れる（メニューの項目では help が出ないため）。
  - 持ち方: AI チャットは `MeetingChatModel.override`（`TextAIChoice?`。nil なら既定）。`MeetingChatStore` の会議ごとのモデルと一緒にアプリを終了するまで残り、「新しい会話」では戻さず、会議を消したら消える。会議に質問は `MeetingAskModel.override`。会議のウインドウは閉じても残す作り（`AppDelegate.openMeetingWindow`、`isReleasedWhenClosed = false`）で `@StateObject` も残るので、`MeetingWindowView` が `NSWindow.willCloseNotification` を受けて `override` を nil に戻す。
  - 送るとき: `TextAIClient.make(provider:model:settings:purpose:timeout:)` でクライアントを作る（`fromSettings` もこれで書き直す）。答え（`MeetingChat.Message`）に `modelLabel` を持たせ、答えの下の「<時刻> までの記録から」の横に出す。会議に質問の答えも同じく出す。
  - 選んだ送り先が送るときに使えなくなっていたら（キーを消した等）、今のエラーの文言（`答えを作れませんでした: …`）で知らせ、切り替えは残す。
- 理由: 入力欄の近くなら、送る前に送り先が目に入る（外に送るかどうかが分かる。DEC-MTG-085 の表示を兼ねる）。会議中は画面が狭いので、ツールバーやシートを足さない。使えないものを隠すと「なぜ出ないのか」が分からないので、理由を添えて選べなくする。「新しい会話」は話題を変えるためのもので、モデルの選択とは別。
- 関係する要件: REQ-MTG-048, REQ-MTG-049, REQ-MTG-040, REQ-MTG-041, REQ-MTG-016
- 対象: Mac

## やらないこと
- 画面で切り替えた送り先を、設定の既定に書き戻すこと・アプリをまたいで覚えること（回答のとおり）。
- 既存の利用者に会議の AI・モデルを写すこと（回答のとおり）。
- AI チャット・会議への質問で、ローカルのモデルがないときにダウンロードを尋ねること（DEC-COM-069 の対象外のまま。案内だけ出す）。
- Windows 版（AI チャットと会議への質問がない）。
- 一覧にない Gemini のモデル名を、チャットの画面で入力すること（設定の欄で入れる）。
- 答えを少しずつ出す（FUT-107）。

## 手順
作業は今のブランチ（claude/screen-ocr-context。別の作業の未コミットの変更がある）ではなく、`origin/main` から切った worktree（`claude/ai-chat-model`）で行い、この計画のファイルもそちらへ移す。

1. spec: `docs/spec/common.md` に REQ-COM-025・DEC-COM-171・DEC-COM-172 を足し、REQ-COM-020・023・024・030・031・050 と DEC-COM-040・042・043・092 を直す。`docs/spec/meeting.md` に REQ-MTG-048・049・DEC-MTG-150 を足し、DEC-MTG-053・081・085 を直す。番号を書く前に、開いている PR（#78・#91）と突き合わせ直す。
2. 設定と AI の土台:
   - `TextAI.swift`: `TextAIPurpose.chat`、`TextAIChoice`（provider と model）、`TextAIClient.make(provider:model:settings:purpose:timeout:)`、`fromSettings` を `make` で書き直す、`cliModel` を網羅の switch に。
   - `Settings.swift`: キーと `@Published` の 4 つ、既定値、`aiProvider(for:)`・`textModel(for:)`・`localModel(for:)` を網羅の switch に。引き継ぎの印は足さない。
   - `LocalLLMServer.swift`・`LocalLLMClient.swift`: DEC-COM-172 の待ち（`LocalLLMGate`、`waitingRequests`、`beginRequest(model, deadline:)`、`wouldWait(for:)`、`waitsForOtherModel`）。
3. 呼び出しを `.chat` に: `MeetingChatModel.send`、`MeetingChatView`（送り先の表示）、`MeetingChatCLI`（`--chat-meeting`）、`MeetingAskModel`、`MeetingSearchCLI`（`--ask-meetings`）。`MeetingSearchView` の説明文（「設定の『AI』で会議に選んだもの」）と `MeetingChat.swift` 冒頭のコメントを直す。議事録・辞書の候補（`MeetingRecorder`・`MeetingDictionaryViews`・`DictionarySettingsView`・`DictionaryCLI`・`MinutesCLI`）は `.meeting` のまま。
4. 設定とオンボーディングの画面: `AISettingsTab` に 3 行目、`AIChoiceRow` の binding と説明を網羅の switch に、footer の文言、`AISettingsView` の Gemini の「接続を試す」のモデル選びと、`ClaudeKeySection.testConnection` のモデル選び（どちらも `.chat` も見る。Claude を選んでいる用途のうち先のもの）。`OnboardingModel`（AI の選択で 3 用途に入れる・CLI の保存と戻し）、「設定の Tips」のページに 3 行目と説明文、`OnboardingPermissionsPage.aiSummary`。`ClaudeCLI.renderSettings` の保存と戻しに 4 つの値を足す。
5. 送り先のメニュー: `AIRouteMenu`（新しいファイル `AIRouteMenu.swift`）、`MeetingChatModel.override`・`MeetingAskModel.override`、`MeetingChat.Message.modelLabel`、答えの行と会議に質問の答えに表示、既定が使えないときの案内。タグを付ける。
6. 確かめ方の CLI（`// 確かめ方: REQ-…` を付ける）:
   - `--test-ai-purposes`（新設）: UserDefaults の使い捨てのスイートで `AppSettings` の用途ごとの組み合わせ（3 用途 × 4 AI の `aiProvider(for:)`・`textModel(for:)`、既定値、`hasSavedSettings` が新しいキーの既定で増えないこと）を確かめる。`AppSettings` が `.shared` 固定で試せなければ、組み合わせを決める純粋な関数（`AppSettings.choice(for:values:)` など）に切り出して試す。
   - `--show-target`: `--chat-meeting`・`--ask-meetings`・`--minutes-from-transcript` に、AI を呼ばずに用途（`chat` / `meeting`）・AI・モデルを出して終える旗を足す（呼び出しが正しい用途を使っているかを、設定を書き換えずに確かめる。用途ごとの AI とモデルの組み合わせは `--test-ai-purposes` で確かめる）。
   - `--test-local-llm-wait`（新設）: `LocalLLMGate` を、サーバーを起こさずに試す（使っている処理がある間は違うモデルが待つ、待つ処理が 2 つでも止まり合わない、同じモデルはそのまま通る、音声入力は待たない、期限で失敗する、取り消しで抜ける）。
   - `--test-meeting-chat` に、`override` の有無での送り先と、使えない選択肢の判定を足す。`--render-meeting-chat` に 3 枚（既定・切り替え中・既定が使えない）、会議に質問の描き出しにメニューを足す。
7. UI の文字列を 17 言語で入れる（`python3 scripts/i18n-strings.py sync`、i18n エージェントに言語を分けて任せる）。対象: 用途の名前と説明、設定とオンボーディングの説明文、送り先のメニューの文言と理由、外に送るかの文（AI チャット用と会議に質問用）、既定が使えないときの案内、待っているときの表示、待ちの期限切れのエラー、会議に質問の説明文。プロンプトは変えない。
8. README: 「Choose your AI」の用途の説明（音声入力と会議 → 3 用途）と既定のモデルの表、158 行付近の説明を直し、`README.ja.md` と 15 の訳（`README.<言語>.md`）にも同じ変更を入れる。
9. UI のテスト項目: `common/testdata/ui/meeting.json`（チャットと会議に質問の送り先のメニュー）、`settings.json`（3 行）、`onboarding.json`（Tips の 3 行）に足し、`python3 scripts/ui-cases.py md`・`check`。ui-test スキルで描いて見る。
10. 文書: `docs/design/meeting.md`（AI チャットと会議に質問の送り先。438 行付近の「`meetingMinutesModel` に」を直す）、`docs/design/dictation.md` の用途の説明、`docs/design/` のローカルの LLM の説明（DEC-COM-172）、`docs/guide.md`（83 行の用途の説明と Claude の初期値、18 行の AI チャットの説明に送り先のメニュー）。

## 確かめ方
- `swift build`
- `python3 scripts/check-spec.py`、`python3 scripts/check-spec.py --diff origin/main`、`python3 scripts/check-i18n.py`
- `.build/debug/Hanasu --test-ai-purposes`、`--test-ai-defaults`、`--test-meeting-chat`、`--test-local-llm-wait`
- 送り先の確認（AI を呼ばない）: `--chat-meeting <フォルダ> --ask "…" --show-target` と `--ask-meetings "…" --show-target` が用途 `chat`、`--minutes-from-transcript <文字起こし> --show-target` が用途 `meeting` を出す。用途ごとの AI とモデル（会議 = Claude Sonnet、AI チャット・質問 = Claude Haiku の組み合わせなど）は `--test-ai-purposes` の使い捨ての設定で確かめる。
- `.build/debug/Hanasu --render-meeting-chat <dir>`、`--render-ai-settings /tmp/ai.png --claude`、オンボーディングの描き出し（ui-test スキルで判定）
- 実機:
  - 会議を記録しながら AI チャットのメニューで Haiku → Sonnet に切り替えて送り、答えの下のモデル名が変わる。記録を止めて会議ノートで同じ切り替えが続き、別の会議では既定に戻る。キーのない AI が理由つきで選べない。
  - 会議に質問で切り替えて送ると、その AI で答える。会議のウインドウを閉じて開き直すと既定に戻る。
  - 会議 = ローカル Gemma、チャット = ローカル Qwen3.5 で、記録を止めた直後（議事録の作成中）にチャットで聞くと、「ほかの処理が終わるのを待っています…」と出て、議事録が最後まで作られ、チャットはそのあとに答える。続けて会議に質問でも聞いても止まり合わない（DEC-COM-172）。
- Windows は触らない（`cd windows && dotnet test Hanasu.Core.Tests` は念のため通す）。

## 敵対的レビュー
2026-11-10、requirements-reviewer（Opus）1 つ、1 回目。

| # | 重さ | 指摘 | 仕分け | どうしたか |
| --- | --- | --- | --- | --- |
| 1 | 致命 | 引き継ぎの新しい印を書くと `hasSavedSettings` が数え、新しい人にオンボーディングが出なくなる | 直す（2 の答えで不要に） | 既存の利用者に写さないことになり、印を足さない。DEC-COM-171 に理由を書いた |
| 2 | 重大 | AI だけ会議から写すと、ローカルの別モデルの人が未ダウンロードの Gemma になって動かない。Q3 の答えとも半分食い違う | 聞く | 答え「写さない（完全に独立）」。使えないときの案内を受け入れ条件に、影響を DEC-COM-171 に書いた |
| 3 | 重大 | チャットが別のローカルのモデルを求めると、議事録の作成中でも llama-server を止める | 直す | DEC-COM-172（違うモデルは、ほかの処理が終わるまで待つ）を足した |
| 4 | 重大 | 「会議への質問は会議の AI」と書いた REQ-COM-020・030・031・050、DEC-COM-042・043・092、DEC-MTG-053 が変える一覧にない | 直す | 「変える要件」「直す設計判断」に足した |
| 5 | 重大 | 会議に質問の説明文が「会議に選んだ AI に渡す」のまま残り、外に送るかを誤って伝える | 直す | 手順 3・7・10 に足した |
| 6 | 重大 | Gemini の判定に `authFromSettings` を使うと、キーと秘密鍵を読む（DEC-COM-049 に反する） | 直す | `Keychain.exists` とファイルの有無で判定する、と DEC-MTG-150 に書いた |
| 7 | 重大 | 「議事録は Sonnet、チャットは Haiku」を AI を呼ばずに確かめる手段がない | 直す | `--test-ai-purposes` と `--show-target` を手順 6 に足した |
| 8 | 重大 | README に用途ごとの AI と既定のモデルの表がある（計画は「記述なし」と誤記） | 直す | 手順 8（README と 15 の訳）を足した |
| 9 | 軽微 | オンボーディングの「設定の Tips」に 3 行目がない | 直す | 手順 4 と受け入れ条件に足した |
| 10 | 軽微 | 描き出しの CLI が新しい値を保存して戻さない | 直す | 手順 4 に `ClaudeCLI.renderSettings` とオンボーディングを足した |
| 11 | 軽微 | 三項演算子の箇所は `.chat` を足してもコンパイルで止まらない | 直す | 網羅の switch に書き直すと DEC-COM-171 に書いた（待ち時間の 2 か所は意図して残す） |
| 12a | 軽微 | 会議に質問の画面での切り替えを聞かずに「やらないこと」にしていた | 聞く | 答え「付ける」。REQ-MTG-049 を足した |
| 12b | 軽微 | 「Haiku 5.5 は 200k の文脈」に根拠がない | 直す | 理由から外した |
| 12c | 軽微 | メニューの項目では help が出ない | 直す | 理由は項目の文字に入れる |
| 12d | 軽微 | `AppleFMAvailability.check()` は署名を確かめるので重い | 直す | メニューを開いたときに 1 回だけ |
| 12e | 軽微 | 送り先を「AI · モデル」だけにすると、外に送ることが読めない | 直す | 外に送るかの文を残す（REQ-MTG-048） |

2026-11-10、requirements-reviewer（Opus）1 つ、2 回目（REQ-MTG-049 と DEC-COM-172 を足したため）。

| # | 重さ | 指摘 | 仕分け | どうしたか |
| --- | --- | --- | --- | --- |
| 1 | 重大 | DEC-COM-172 の待ちは、`beginRequest` が先に数えるため待つ処理どうしが止まり合う。待ちに期限もない | 直す | 使っている処理と待っている処理を分けて数え、期限（`deadline`）と待ち中の表示を足した。`LocalLLMGate` に切り出し `--test-local-llm-wait` で確かめる |
| 2 | 重大 | 待ちを音声入力にも当てると、依頼の外で音声入力が遅くなる | 聞く代わりに推奨で決めた（質問は 2 回使った） | 音声入力は今のまま（待たない）。「仮に決めたこと」に書いた |
| 3 | 重大 | 会議のウインドウは閉じても残るので、会議に質問の切り替えが戻らない | 直す | `willCloseNotification` で戻す、と DEC-MTG-150 に書いた |
| 4 | 重大 | 「設定の Tips」を決めている REQ-COM-051 が変える一覧にない | 直す | 「変える要件」に足した |
| 5 | 重大 | Gemma を入れている既存の利用者は、知らせなしに送り先がローカルに変わり、会議への質問が浅くなる | 聞く代わりに推奨で決めた | 影響を DEC-COM-171 に書いた。送り先はメニューに常に出るので画面で分かり、リリース文でも知らせる（「仮に決めたこと」） |
| 6 | 軽微 | 会議に質問が送るのは議事録と文字起こしで、メモではない | 直す | 会議に質問用の文を分けた（REQ-MTG-049） |
| 7 | 軽微 | Claude の「接続を試す」がチャット・質問のモデルを見ない | 直す | 手順 4 に足した |
| 8 | 軽微 | `docs/guide.md` と `README.ja.md` が手順にない | 直す | 手順 8・10 に足した |
| 9 | 軽微 | Apple の判定をメニューを開いたときだけにすると、既定が使えないときの案内と合わない | 直す | 画面が出たときに 1 回確かめて覚える |
| 10 | 軽微 | 辞書の候補を「会議」に残すことを聞いていない | 推奨で決めた | 「仮に決めたこと」に書いた |
| 11a | 軽微 | `--show-target` の確かめ方で、設定の切り替え方が書かれていない（CLI はアプリと別の設定のドメイン） | 直す | `--show-target` は用途を出すだけにし、組み合わせは `--test-ai-purposes` で確かめる |
| 11b | 軽微 | DEC-COM-064 も用途の言葉で書いている | 直す | 「直す設計判断」に足した |
| 11c | 軽微 | Windows に AI チャットがない根拠の参照が違う | 直す | FUT-003 と windows/README.md に直した |

見られなかったこと: ビルドとテストは動かしていない。macOS 26 の SwiftUI `Menu` で、使えない項目がどう見えるか（実機で確かめる）。Claude Haiku 5.5 の文脈の長さで、会議への質問の最大 15 万文字が入るか（実装のときに API の資料で確かめ、入らなければ報告する）。

## 仮に決めたこと
了承のときに見てください。違えば直します。
- 用途の名前は「AI チャット・質問」。
- **辞書の候補探しは「会議」側に残す**（会議の記録を読む長い処理なので）。
- **ローカルのモデルを切り替えるときの待ちは、AI チャット・質問と議事録にだけ当て、音声入力は今のまま**（DEC-COM-172）。
- **以前から使っている人で送り先が変わる人へは、リリース文と、常に見える送り先の表示で知らせる**（一度だけのお知らせは出さない）。
- 画面の切り替えは「新しい会話」では戻さず、会議ごとにアプリを終了するまで残す。会議に質問は会議のウインドウを閉じるまで。
- 答えの下に、その答えを作ったモデルの名前を出す。
- Gemini を選んだときの AI チャット・質問の既定は gemini-3.8-flash。
