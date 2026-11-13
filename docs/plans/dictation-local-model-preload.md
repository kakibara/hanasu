# 音声入力で、ローカルのモデルを録音の間に読み込んでおく

- 状態: 実装済み（2026-11-13 に計画を了承。要件は [spec/common.md](../spec/common.md) の REQ-COM-033、設計判断は DEC-COM-110・DEC-DIC-220。PR は作るときに足す）

## 目的

2026-11-13 の依頼「音声入力を立ち上げるときに、文字起こしの後のAIをローカルモデルにすると立ち上げまで時間がかかる。音声入力を行っている最中にローカルモデルを読み込むことで、ボタンを押した瞬間に音声入力自体を始められるようにしてほしい」。同日、待たされている場面を尋ねて「押してから録音が始まるまで」、選択の編集も対象に「含める」と答えをもらった。

ボタンを押したらすぐ話し始められ、話し終えたらモデルの読み込みを待たずに整形に入れるようにする。

### 調べて分かったこと（依頼の前提との違い。了承のときに見てほしい）

- **コードでは、録音を始めるときにローカルのモデルを待っていない（Mac・Windows とも）。** 読み込み（llama-server の起動と 4.6 GB のモデルの読み込み）は、録音を止めたあとの整形の中で初めて行う（Mac: `DictationController.finishDictation` → `LocalLLMClient.generate` → `LocalLLMServer.beginRequest` → `ensureRunning`。Windows: `DictationTextProcessor` → `LocalLlmClient` → `LocalLlmServer.BeginRequestAsync`）。サーバーは最後に使ってから 5 分で止まる（DEC-COM-063）ので、5 分以上あけると毎回読み込む。
- **この Mac の今日のログでも、待ちは止めたあとに出ている。** Gemma 4 E4B で整形した 2 回は、`recognized`（止めた）から `insert outcome`（入力した）まで 13.5 秒と 18.1 秒。その間に `local llm server started` が出ている。Gemini の回は 1.5〜2.5 秒。
- **録音の開始（「準備中…」から録音中まで）の時間は、今はログに残っていない。** そのため、押してから録音が始まるまでが本当に遅いのか、遅いならなぜかは、まだ確かめられていない。ローカルのモデルの有無で録音の開始の処理は変わらないので、遅いなら原因は別（マイク・音声認識の準備など）の見込み。
- そこでこの計画では、(1) 録音を始めたら裏でモデルを読み込み始め（録音の開始は待たせない）、止めたあとの待ちをなくす。(2) 録音の開始にかかった時間をログに残し、ローカルのときに本当に遅いかを測る。測って遅ければ、その原因の調査は別に行う（→ 仮に決めたこと 1）。

## 要件の案

### REQ-COM-033 音声入力の AI がローカルなら、録音が始まったら裏でモデルを読み込み始める（新規）
- 内容: 音声入力整形の AI をローカルにしていて、その録音で AI を使う（音声入力で整形がオン・翻訳して入力する・Mac の選択の編集）とき、録音が始まったら、裏でそのモデルの読み込み（サーバーの起動）を始める。録音の開始はそれを待たない。録音を止めたときに読み込みが終わっていれば、すぐ整形に入る。終わっていなければ、その続きを待つ（最初から読み込み直さない）。録音している間は、5 分たってもサーバーを止めない。
- 受け入れ条件:
  - 録音の開始は読み込みを待たない: 「準備中…」から録音中になるまでの時間（足すログ `dictation recording started: <秒>`）が、ローカル（Gemma 4 E4B、サーバーが止まっている状態から）とローカルでない AI とで、各 5 回の中央値の差が 0.3 秒以内。
  - 読み込みが録音より短ければ、止めてからの待ちは読み込み済みのときと同じ: サーバーが止まっている状態から始め、足すログ `local llm server ready: <モデル> <秒>` の秒数より長く話して止めたとき、`recognized` から `insert outcome` までの時間が、サーバーが動いているとき（続けてもう 1 回、同じくらいの長さを話したとき）と比べて +1.0 秒以内。そのとき `local llm server started` は録音が始まった直後に 1 回だけで、止めたあとには出ない。
  - 読み込みより短く話したときは、止めてから読み込みの残りの分だけ待つ（読み込み直さない。`started` は 1 回だけ）。
  - 録音中に 5 分たっても、サーバーは止まらない（`local llm server stopped (idle)` が出ない）。止めた・取り消した時点から 5 分で止まる。
  - 読み込みを始めないとき: 整形がオフで翻訳もしない録音、AI がローカルでない、モデルがまだダウンロードされていない（Mac は今どおり止めたあとにダウンロードするかを尋ねる REQ-COM-032、Windows は今どおり設定でダウンロードするよう知らせる）、録音を始められなかった（権限がない・マイクを開けないなど）。
  - 録音の途中で HUD から翻訳の言語を選んだときは（整形がオフでも）、その時点で読み込みを始める。
  - 録音を取り消したとき・認識結果が空だったときも、読み込んだサーバーは 5 分使わなければ止まる（取り消しでは止めない）。
  - 読み込みに失敗しても録音は続く。止めた時点で失敗が分かっていれば、整形が今どおり起動し直す。止めたあとに続きを待っていた読み込みが失敗したら、起動し直さず、整形前の文を入力して理由を知らせる（REQ-DIC-007）。
  - ほかの処理を壊さない: 議事録・辞書の候補・AI チャット・会議への質問が違うモデルでローカルの AI を使っている（または待っている）間は、録音を始めても読み込まない。読み込みの途中に違うモデルの議事録などが来ても、その処理は失敗しない（読み込みが終わるまで待ってから切り替える）。止めたあとの整形の振る舞いは今のまま（DEC-COM-172）。
- 出典: 2026-11-13 の依頼「音声入力を行っている最中にローカルモデルを読み込むということで、ボタンを押した瞬間に音声入力自体を始めることができるようにしてください」。同日の質問への答え「押してから録音が始まるまで（が待たされる場面）」「選択の編集も含める」（了承の日付を足す）
- 対象: Mac / Windows（選択の編集は Mac だけの機能）
- 実装の場所: `DictationController.startDictation`・`selectOutputLanguage`・`finishDictation`・`cancelDictation`、`EditModeController.start`・`finish`・`cancel`、`LocalLLMServer.prewarm`・`releaseWarmHold`・`ensureRunning`
- Windows の実装: `windows/Hanasu.Core/Dictation/DictationController.cs`（`StartAsync`・`SelectOutputLanguage`）、`windows/Hanasu.Core/Dictation/DictationPrewarm.cs`（新規。判定）、`windows/Hanasu.Core/LocalLlm/LocalLlmServer.cs`（`Prewarm`・`ReleaseWarmHold`）、`windows/Hanasu.Windows/AppHost.cs`
- 確かめ方: Mac は `.build/debug/Hanasu --test-local-llm-wait`（足す (a)〜(f)。下の手順 4）。Windows は `cd windows && dotnet test Hanasu.Core.Tests`（`DictationPrewarmTests`・`LocalLlmTests`・`DictationControllerTests`）と、Mac の本物の llama-server で動かす `dotnet run --project Hanasu.Cli -- local-prewarm-check`。実機（Mac）で上の時間とログ。

### 変える要件（ユーザーの合意が要る）
- なし。REQ-COM-030・REQ-COM-032・REQ-DIC-007・REQ-DIC-050（選択の編集）の文面は変えない。

### 書き換える設計判断（理由がもう当てはまらない部分だけ）
- DEC-COM-060: 「ローカルを選んだ処理を始めるときに子プロセスとして起動」→「…処理を始めるとき、または音声入力・選択の編集の録音が始まったとき（DEC-COM-110）に起動」。
- DEC-COM-063: 「最後の処理から 5 分たつと止め」→「最後の処理（先読みを含む。録音している間は数えない）から 5 分たつと止め」。
- DEC-COM-172: 「先読みは、起動している間だけ使っている処理に数える（DEC-COM-110）」を 1 行足す。

## 設計判断の案

### DEC-COM-110 先読みは、同じモデルの起動を 1 つにまとめ、起動の間だけ使っている処理に数え、ほかの処理を止めない
- 決めたこと:
  - Mac（`LocalLLMServer`）:
    - `prewarm(_ model:) -> UUID?` を足す。ほかの処理が使っている・待っている（`LocalLLMGate.isIdle` が偽）ときで、動いている（起動中を含む）モデルが違うなら何もしないで nil を返す。そうでなければ「録音中の保持」（`warmHolds` に UUID を足す）を付けて返し、そのモデルが動いていなければ裏で起動する。起動している間は `gate.active` に数え（終わったら `gate.finish()`）、ほかのモデルを待つ処理（`waitsForOtherModel` が真）は起動が終わるまで待つ。
    - `releaseWarmHold(_ id:)` を足す。保持を外し、最後に使った時刻を新しくして、5 分の見張り（`scheduleIdleStop`）を付け直す。`stopIfIdle` は保持が 1 つでもあれば止めない。保持はほかの処理の順番（`LocalLLMGate.decision`）には関わらない（録音の長さだけ議事録を待たせない）。
    - `ensureRunning` は起動を `launching: (model, Task<Endpoint, Error>)` として持つ。同じモデルの起動の途中に来た呼び出しは、その Task を待つ（起動し直さない）。違うモデルなら今どおり止めて起動し直す。
    - 起動を待つループの片付け（`stop()`）は、そのループが起動したプロセスが今の `self.process` と同じときだけ行う（今は、割り込んだ別のモデルのサーバーを止めてしまう）。
    - `/health` が通ったら `local llm server ready: <モデル> <秒>` をログに出す。
    - 先読みの失敗は、ログに残すだけで HUD には出さない。続きを待っていた整形には同じ失敗が返り、整形前の文を入力する道（REQ-DIC-007）に進む。
  - Windows（`LocalLlmServer`）:
    - `Prewarm(LocalLlmModel) -> Guid?` と `ReleaseWarmHold(Guid)` を足す（Mac と同じ意味）。`activeRequests > 0` で動いているモデルが違うなら何もしない。それ以外は保持を付け、裏のタスクで `gate`（SemaphoreSlim）を取って `EnsureRunningAsync` で起動する。gate を持つ間は止めたあとの整形も gate で待つので、起動し直しは起きない。
    - 同じモデルが動いていれば `lastUsed` を新しくする。`StopIfIdle` は保持があれば止めない。`ReleaseWarmHold` で `lastUsed` を新しくし、見張りを付け直す。
    - 起動の差し替え口（Mac の `fakeLaunch` と同じ形。テストだけで使う）を足す。`ready` のログも足す。
    - 先読みの失敗はログだけ。止めたあとの整形は gate を取ってから今どおり起動し直す（Mac と違い、Windows は gate で 1 つずつなので「続きを待つ」がない）。
- 理由: 先読みのために起動し直しが起きると、かえって遅くなる。議事録などを録音の開始で止めると、取り消した録音でも議事録が切れる（DEC-COM-172 で守ったもの）。起動中は `servingModel` が nil で `active` も 0 のため、数えないと議事録が割り込んで起動し、先読みの片付けがそのサーバーを止めてしまう（レビューで見つけた）。録音は 5 分を超えうる（Whisper は 10 分まで、Apple の音声認識は上限なし）ので、録音の間は止めない。先読みすると、AI を使わずに終わった録音（取り消し・空・全体がスニペット）でもサーバーが 5 分動き、その間メモリを数 GB 使い、`hanasu`・MCP のローカルの AI は断られる（REQ-COM-187）。止めたあとに読み込むのは今と同じなので、損はこれらの録音に限られる。
- 決めた場面: 2026-11-13 の依頼「音声入力を行っている最中にローカルモデルを読み込む…」（了承の日付を足す）
- 関係する要件: REQ-COM-033, REQ-COM-030, REQ-COM-187
- 対象: Mac / Windows
- 実装の場所: `LocalLLMServer.prewarm`・`releaseWarmHold`・`ensureRunning`・`stopIfIdle`
- Windows の実装: `windows/Hanasu.Core/LocalLlm/LocalLlmServer.cs`

### DEC-DIC-220 録音が始まったとき・HUD で翻訳を選んだときに先読みを頼み、止めた・取り消した・失敗したときに保持を外す
- 決めたこと:
  - Mac の音声入力: `DictationController` に `prewarmLocalModelIfNeeded()` を足す。`state = .recording` にした直後（権限の確認と `recognizer.start` が通ったあと）と、`selectOutputLanguage` で翻訳を選んだときに呼ぶ。判定は `self.mode`（アプリ別の既定の翻訳を反映した後のもの）で、`settings.refineWithGemini || self.mode.translation != nil`、音声入力の AI がローカル、そのモデルがダウンロード済み。満たせば `LocalLLMServer.shared.prewarm` を裏で呼び（結果は待たない）、返った保持を覚えておく。`finishDictation` の整形が終わったあと・`finishCancelled`・`fail` で `releaseWarmHold` を呼ぶ。
  - Mac の選択の編集: `EditModeController` で、録音中になった直後に、AI がローカル・モデルがダウンロード済みなら同じく先読みを頼む（選択の編集は必ず AI を使う）。`finish` の AI の呼び出しのあと・取り消し・失敗で保持を外す。
  - Windows: 判定は `Hanasu.Core` の `DictationPrewarm.ModelToPrewarm(AppSettings, DictationMode, Func<LocalLlmModel, bool> isDownloaded) -> LocalLlmModel?`（静的）に置く。`DictationServices` に `Func<AppSettings, DictationMode, Guid?> PrewarmTextAi` と `Action<Guid> ReleaseTextAiWarmHold`（既定は何もしない）を足す。`DictationController` は録音中にした直後と `SelectOutputLanguage` で呼び、止めた・取り消した・失敗したときに外す。`AppHost` は `DictationPrewarm.ModelToPrewarm` と `LocalLlmServer.Shared.Prewarm` をつなぐだけにする。
  - 録音の開始のログ: Mac・Windows とも、録音中になった時点で `dictation recording started: <準備中からの秒>` を出す（選択の編集も `edit recording started`）。
  - 履歴のやり直しは対象にしない（録音がないため）。
- 理由: 依頼は「音声入力を行っている最中に読み込む」。準備中のうちに始めると、4.6 GB の読み込みと GPU への載せ替えが、音声認識の準備・マイクの開始・Whisper の先読みと重なり、録音の開始を遅らせうる。録音を始められなかったときに読み込まないためにも、録音中になってから始める。Whisper の先読み（`WhisperEngine.preload`）と同じ形。翻訳は整形がオフでも AI を使うので、HUD で選んだ時点でも始める。Windows の判定を Core に置くのは、テストのプロジェクトが `Hanasu.Windows` を参照しないため。
- 決めた場面: 2026-11-13 の依頼と、同日の答え「選択の編集も含める」（了承の日付を足す）
- 関係する要件: REQ-COM-033
- 対象: Mac / Windows
- 実装の場所: `DictationController.prewarmLocalModelIfNeeded`・`startDictation`・`selectOutputLanguage`・`finishDictation`・`finishCancelled`・`fail`、`EditModeController`
- Windows の実装: `windows/Hanasu.Core/Dictation/DictationPrewarm.cs`、`windows/Hanasu.Core/Dictation/DictationController.cs`、`windows/Hanasu.Windows/AppHost.cs`

## やらないこと

- 録音していないときに、モデルを読み込んだままにしておく（アプリの起動時に読み込む・5 分で止めない）。数 GB のメモリを使い続けるため（DEC-COM-063）。
- 先読みのオン・オフの設定。
- HUD に「モデルを読み込んでいます」と出すこと（UI の文字列もプロンプトも増やさないので、17 言語の訳は要らない。README も直さない）。
- 整形の途中に次の録音を始められるようにすること。
- 録音の開始そのものが遅い場合の原因の調査と直し（この計画ではログを足して測るまで。→ 仮に決めたこと 1）。

## 手順

1. spec: `docs/spec/common.md` に REQ-COM-033（REQ-COM-032 のあと）と DEC-COM-110、`docs/spec/dictation.md` に DEC-DIC-220 を書く。DEC-COM-060・063・172 を上のとおり書き換える。番号は書く直前に `grep` と開いている PR で確かめ直す。`docs/roadmap.md` からこの計画へのリンクは張らない（roadmap の項目ではないため）。実装したら、この計画の状態を「実装済み（PR へのリンク）」にする。
2. Mac のサーバー（`Sources/Hanasu/LocalLLMServer.swift`）: `launching`・`warmHolds`・`prewarm`・`releaseWarmHold` を足し、`ensureRunning`（`fakeLaunch` の分岐も同じ道を通す）・`stopIfIdle`・起動を待つループの片付け・`ready` のログを直す。タグ `// 要件: REQ-COM-033`・`// 設計判断: DEC-COM-110`。
3. Mac の録音（`Sources/Hanasu/DictationController.swift`、`Sources/Hanasu/EditModeController.swift`）: 先読みの依頼と保持の解除、録音の開始のログ。タグ `// 要件: REQ-COM-033`・`// 設計判断: DEC-DIC-220`。
4. Mac の確かめ（`Sources/Hanasu/AIPurposeCLI.swift` の `--test-local-llm-wait`、`// 確かめ方: REQ-COM-033`）: 待ち時間を入れ、起動中に `stop` されたら失敗を返す偽の `fakeLaunch` で、(a) `prewarm` のあとの `beginRequest` で `launchCount` が 1、(b) `prewarm` の起動の途中に来た同じモデルの `beginRequest` が同じ起動を待ち `launchCount` が 1、(c) 違うモデルの処理中（`finishRequest` 前）に `prewarm` しても nil で `launchCount` が増えない、(d) `prewarm` の起動の途中に違うモデルの `beginRequest(waitsForOtherModel: true)` が来ても、それは起動の終わりを待ってから成功する、(e) 保持がある間は 5 分の判定で止まらない（判定を時刻を渡して呼べるようにする）、(f) 続きを待っていた `beginRequest` は、先読みの起動が失敗すると同じ失敗を受け取り、起動し直さない。
5. Windows（2〜4 と別のファイルなので並べて進められる）: `LocalLlmServer` の `Prewarm`・`ReleaseWarmHold`・`StopIfIdle`・起動の差し替え口・`ready` のログ、`DictationPrewarm`（新規）、`DictationController`・`DictationServices`、`AppHost`。テストは `DictationPrewarmTests`（整形オン・翻訳・整形オフ・ローカルでない・モデルなし）、`DictationControllerTests`（録音中になったときに頼む・録音を始められなかったら頼まない・HUD で翻訳を選んだら頼む・止めた／取り消したら保持を外す）、`LocalLlmTests`（差し替え口で、Mac の (a)〜(e) と同じこと）。`windows/Hanasu.Cli` に `local-prewarm-check`（本物の llama-server を `--server`・`--models-dir` で指し、先読み → `BeginRequestAsync` でサーバーの起動が 1 回か）を足す。タグと `// 確かめ方: REQ-COM-033` を付ける。
6. design: `docs/design/dictation.md` の整形の流れに「録音が始まったら裏でローカルのモデルを読み込み始める（DEC-DIC-220・DEC-COM-110）」を 1〜2 行。
7. 確かめる（下）。

## 確かめ方

- `swift build`
- `.build/debug/Hanasu --test-local-llm-wait`（(a)〜(f) を含めて通る）
- `python3 scripts/check-spec.py`（`--diff origin/main` で触った ID も見る）、`python3 scripts/check-i18n.py`
- `cd windows && dotnet test Hanasu.Core.Tests`
- `cd windows && dotnet run --project Hanasu.Cli -- local-prewarm-check --server ../build/llama-cpp/macos-arm64/llama-server --model lfm2.5-1.2b-jp`（Mac で、軽いモデルで）
- 実機（Mac。ログは `/usr/bin/log stream --predicate 'subsystem == "dev.mactypeless.Hanasu"'`）:
  1. 音声入力整形をローカル（Gemma 4 E4B）にし、サーバーが止まった状態（アプリの起動直後か 5 分あける）で `⌥ Space` を 5 回（毎回 5 分あけるか、メニューからアプリを起動し直す）、`dictation recording started` の秒を記録する。Gemini でも 5 回。中央値の差を見る。
  2. サーバーが止まった状態から、`local llm server ready` の秒より長く話して止め、`recognized` → `insert outcome` を測る。続けてもう 1 回同じくらい話し、比べる。`started` が 1 回だけかを見る。
  3. 3 秒だけ話して止め、`started` が 1 回だけで、止めたあとに `ready` を待ってから入力されることを見る。
  4. エンジンを Whisper にして 1・2 をもう一度（Whisper とモデルの読み込みが重なっても、録音の開始が遅くならないか）。
  5. 選択の編集で 2 を行う。
  6. 6 分録音して、録音中に `stopped (idle)` が出ないことを見る。
- 「議事録などの最中は読み込まない」「読み込みの途中に議事録が来ても失敗しない」は、実機では作りにくいので CLI（(c)・(d)）と Windows のテストだけで確かめる。
- Windows の実機は手元にないので、テストと `local-prewarm-check` まで（実機で確かめられなかったことを PR に書く）。

## 敵対的レビュー

2026-11-13、requirements-reviewer（Opus）2 つ並べて（A: 目的・受け入れ条件・失敗時・範囲・ユーザーが決めること、B: 既存の要件・Mac と Windows・17 言語・安全・手順の事実・確かめ方）、1 回。

| # | 重さ | 指摘 | 仕分け | どうしたか |
| --- | --- | --- | --- | --- |
| 1 | 重大 | 「立ち上げまで時間がかかる」をどの待ちと読むか、ユーザーに聞かずに決めている | 聞く | 聞いた。答えは「押してから録音が始まるまで」。ただしコードとログでは待ちは止めたあとにあるので、録音の開始の時間をログで測ることを足し、遅ければ別に調べる（仮に決めたこと 1） |
| 2 | 重大 | 先読みの起動中に違うモデルの議事録・チャットが来ると、割り込んで起動したうえ、先読みの片付けの `stop()` がそのサーバーを止める（A・B が同じ指摘） | 直す | 起動の間は先読みを `active` に数え、片付けは自分の起動したプロセスのときだけ行う（DEC-COM-110）。CLI の (d) を足した |
| 3 | 重大 | 受け入れ条件に数値もログの目印もなく、確かめられない（A・B） | 直す | 録音の開始と `ready` のログを足し、0.3 秒・+1.0 秒の数値と測り方を書いた。読み込みより短く話したときの振る舞いも書いた |
| 4 | 重大 | 先読みを準備中に始めると、録音の開始とぶつかり、録音を始められなかったときも読み込む | 直す | 録音中になった直後に始める（DEC-DIC-220）。録音を始められなかったときは読み込まないを受け入れ条件に足した |
| 5 | 重大 | 選択の編集を対象外にした理由が弱い | 聞く | 聞いた。答えは「含める」。`EditModeController` を手順に足した |
| 6 | 重大 | Windows の先読みを確かめる手段がない（判定が AppHost にあり、サーバーに差し替え口がない） | 直す | 判定を Core の `DictationPrewarm` に移し、サーバーに差し替え口を足してテストを書く。`local-prewarm-check` で本物のサーバーでも確かめる |
| 7 | 軽微 | 5 分を超える録音では、録音中にサーバーが止まる | 直す | 録音中の保持を足し、止めた・取り消した時点から 5 分にした（Mac・Windows とも） |
| 8 | 軽微 | DEC-COM-060・063 の「決めたこと」と合わなくなる | 直す | 書き換える設計判断として挙げた。DEC-COM-172 にも 1 行足す |
| 9 | 軽微 | DEC に「決めた場面」がなく、REQ の「実装の場所」の形が `check-spec.py` を通らない | 直す | 足して、「Windows の実装」を分けた |
| 10 | 軽微 | `startDictation` の `mode` は引数で、アプリ別の既定の翻訳を見落とす | 直す | 判定は `self.mode` を見ると書いた |
| 11 | 軽微 | 続きを待っていた整形が先読みの失敗をどう扱うかが、受け入れ条件と設計で食い違う | 直す | Mac は同じ失敗を返して REQ-DIC-007 の道に進む、Windows は起動し直す、と書き分けた。CLI の (f) を足した |
| 12 | 軽微 | Windows の先読みで `lastUsed` を新しくしないと、前の見張りが録音中に止める | 直す | DEC-COM-110 の Windows に書いた |
| 13 | 軽微 | 先読みで、サーバーが動く時間が延び、`hanasu`・MCP のローカルの AI が断られる時間も増える | 直す | DEC-COM-110 の理由に書いた |
| 14 | 軽微 | 取り消した録音で、ほかの用途の使っていないモデル（チャットの Qwen など）を止めて読み込み直す | 直す | 損の一つとして理由に含めた（止めたあとに読み込むのは今と同じ） |
| 15 | 軽微 | `TextAIClient.prewarmLocal（仮）` が手順にない、Windows のタグがない、番号のまとまり | 直す | 名前を消し、タグを手順 5 に足した。番号はまとまりの空いている DEC-COM-110・DEC-DIC-220 に替えた |
| 16 | 軽微 | 大の計画なのに roadmap からのリンクと、実装後に状態を直す手順がない | 一部退ける | roadmap の項目ではないのでリンクは張らない。状態を直すことは手順 1 に足した |

見られなかったこと: メモリの少ない Mac で Whisper と Gemma を同時に読み込んだときの実際の時間（実機の確かめ方 4 で見る）。Windows の実機。

## 仮に決めたこと

1. **「押してから録音が始まるまで」が遅いことは、まだ再現・測定できていない。** コードではその間にローカルのモデルを待っておらず、今日のログでも待ち（13〜18 秒）は止めたあとに出ている。この計画では、止めたあとの待ちをなくし、録音の開始の時間をログに出して測る。測ってローカルのときに本当に遅ければ（受け入れ条件の 0.3 秒を超えれば）、原因を別に調べて直す。
2. 先読みは設定なしで常に行う。
3. 取り消した録音でも、読み込んだサーバーは 5 分そのまま（すぐには止めない）。続けて録り直すことが多いため。
