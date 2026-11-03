# 設定・認証・共通の仕様（COM）

音声入力と会議の記録で共通のもの（文字起こしのエンジン、Gemini・Claude の呼び出しと認証、セキュリティ、アプリの形、ショートカット、設定、権限）について、**実装済み**の振る舞いのうち、要件（REQ）と設計判断（DEC）を並べる。

- 区分・ID・タグの決まりは [docs/README.md](../README.md)。
- 実装の説明は [design/dictation.md](../design/dictation.md)（3 章・4.10・5.3・6・7）と [design/meeting.md](../design/meeting.md)（4.3.1）、セキュリティは [design/security.md](../design/security.md)。

---

## 要件

### REQ-COM-001 文字起こしのエンジンを、Mac 標準 / Whisper / Gemini から選べる
- 内容: 音声入力と会議の記録の両方で、文字起こしのエンジンを OS 標準・Whisper（端末の上で動かす）・Gemini（音声を送る）の 3 つから選べる。
- 受け入れ条件: 設定の「一般」→「文字起こし」でエンジンを変えると、次の音声入力・会議の記録からそのエンジンで文字起こしされる。
- 出典: ユーザーの指定（2026-11-03、PR #17）「Mac 標準 / Whisper / Gemini を選べる。Windows でも同じにする」。Windows はユーザーの依頼（2026-11-03「Windows でも使えるようにして」）と PR #19
- 対象: Mac / Windows
- 実装の場所: `TranscriptionEngine`、`AppSettings`（`dictationEngine` / `meetingEngine`）、`TranscriptionEngineSettingsSection`、`BatchTranscriber`
- Windows の実装: `windows/Hanasu.Core/Transcription/Transcribers.cs`、`windows/Hanasu.Windows/Views/SettingsWindow.xaml.cs`
- 確かめ方: `.build/debug/Hanasu --transcribe-file /tmp/test.aiff --engine apple|whisper|gemini`、`--meeting-files me.wav others.wav --engine whisper|gemini`、`--render-engine-settings /tmp/engine.png`
- 食い違い（ユーザーの確認待ち）: Windows 版の会議の記録では Windows 標準のエンジンを選べず、Whisper / Gemini の 2 つだけ（DEC-MTG-101、PR #19）。ユーザーの指定は「Windows でも同じにする」だったが、Windows 標準の音声認識は既定のマイクからしか聞けず、PC の音（相手）を渡せないため、実装したエージェントが外した。要件を「Windows の会議では Whisper / Gemini」に変えるかを確かめる

### REQ-COM-002 文字起こしの既定は、OS 標準のエンジンにする
- 内容: 文字起こしのエンジンの既定は OS 標準（Mac は SpeechAnalyzer。音は Mac の外に出ない）。初版から「Mac 標準の音声入力エンジン」で文字起こしする。
- 受け入れ条件: 設定を変えていない状態で、音声入力と会議の記録が Mac 標準のエンジンで文字起こしされる。
- 出典: 初版（a787da8）の「Mac 標準の音声入力」で認識するという依頼。ユーザーの指定（2026-11-03、PR #17）「既定は OS の標準」。Windows は PR #19（音声入力の既定は Windows 標準の音声認識）
- 対象: Mac / Windows
- 実装の場所: `AppSettings.init`（`dictationEngine` / `meetingEngine` の初期値）、`SpeechRecognizer`
- Windows の実装: `windows/Hanasu.Core/Settings/AppSettings.cs`、`windows/Hanasu.Windows/Services/WindowsSpeechTranscriber.cs`
- 確かめ方: 新しいユーザーの UserDefaults で `--render-engine-settings /tmp/engine.png` を描き、Mac 標準が選ばれていること
- 食い違い（ユーザーの確認待ち）: Windows 版の会議の記録の既定は Whisper（Windows 標準を選べないため。DEC-MTG-101）。「既定は OS の標準」を Windows の会議にも当てはめるかを確かめる

### REQ-COM-003 Whisper は、選んだときにモデルをダウンロードする
- 内容: Whisper のモデルはアプリに同梱せず、エンジンかモデルを選んだ時点でダウンロードする。
- 受け入れ条件: 設定で Whisper を選ぶとダウンロードが始まり、進み具合が出て、終わるとそのモデルで文字起こしできる。
- 出典: ユーザーの指定（2026-11-03、PR #17）「Whisper は選んだときにモデルをダウンロードする」。Windows は PR #19
- 対象: Mac / Windows
- 実装の場所: `WhisperModelStore.ensureDownloaded`、`TranscriptionEngineSettingsSection.downloadIfNeeded`
- Windows の実装: `windows/Hanasu.Core/Transcription/WhisperModels.cs`
- 確かめ方: `.build/debug/Hanasu --download-whisper base`（保存先は `HANASU_MODELS_DIR` で変えられる）、`--render-engine-settings /tmp/engine.png --downloading`

### REQ-COM-010 Windows でも音声入力を使える
- 内容: Windows 10（2004 以降）/ 11 でも、Mac 版と同じ流れの音声入力（ショートカットで録音 → 文字起こし → Gemini で整形・英訳 → カーソル位置に入力）を使える。共通の要件（REQ-DIC-001〜008・010〜012・070、REQ-COM-001〜003）は、それぞれの項目の「対象」に Windows を書いた。
- 受け入れ条件: Windows の PC で `Hanasu.exe` を起動するとタスクトレイに常駐し、`Ctrl + Alt + Space` で話した内容が整えられてカーソル位置に入る。
- 出典: ユーザーの依頼（2026-11-03「Windows でも使えるようにして」「音声入力と会議の記録の両方」）、PR #19
- 対象: Windows
- 実装の場所: `windows/Hanasu.Core/Dictation/DictationController.cs`、`windows/Hanasu.Windows/AppHost.cs`
- 確かめ方: `cd windows && dotnet test Hanasu.Core.Tests`（`DictationControllerTests`）、`dotnet run --project Hanasu.Cli -- dictation <wav> --engine whisper|gemini`。起動・常駐・入力は Windows の実機で確かめる（まだ確かめていない）

### REQ-COM-011 Windows でも会議の記録を使える
- 内容: Windows でも、マイク（自分）と PC の音（相手）を別々に録り、記録のあとに文字起こし・相手側の話者分離・Gemini の議事録まで作り、会議ノートで読める。共通の要件（REQ-MTG-001〜013・017・018・020〜025・030〜033）は、それぞれの項目の「対象」に Windows を書いた。
- 受け入れ条件: Windows の PC で `Ctrl + Alt + Shift + M` で記録を始めて止めると、`ドキュメント\Hanasu\Meetings\<日時>\` に文字起こしと議事録ができる。`meeting.json` は Mac 版と同じ形で、Mac で作った会議も開ける。
- 出典: ユーザーの依頼（2026-11-03「音声入力と会議の記録の両方」）、PR #19（第 2 段階、a8d8236）
- 対象: Windows
- 実装の場所: `windows/Hanasu.Core/Meetings/MeetingController.cs`、`windows/Hanasu.Core/Meetings/MeetingPostProcessor.cs`、`windows/Hanasu.Windows/Views/MeetingWindow.xaml.cs`
- 確かめ方: `cd windows && dotnet test Hanasu.Core.Tests`（`MeetingJsonTests` など）、`dotnet run --project Hanasu.Cli -- meeting-files me.wav others.wav --meetings-dir <保存先>`。ループバックの録音は Windows の実機で確かめる（まだ確かめていない）

### REQ-COM-020 整形などに使う AI として、Claude API を選べる
- 内容: 整形・英訳などの文章の処理に使う AI を、Gemini と Claude（Anthropic の Claude API）から選べる。Claude の認証は、ユーザーが入力する API キーで行う。音声の文字起こしには使わない。
- 受け入れ条件: 設定で Claude を選び API キーを入れると、整形・英訳などが Claude で行われる。キーが正しくないときは、そう分かる文言で知らせる。
  - Mac: 設定の「AI」タブで、音声入力か会議の AI を Claude にし、「Claude（Anthropic）の API キー」に保存すると、その用途の処理（音声入力: 整形・英訳・選択の編集、会議: 議事録・会議への質問・辞書の候補）が Claude で行われる。キーが正しくないときは「Claude の API キーが正しくありません（401）」と出る（「接続を試す」でも、整形のときも）。音声は Claude に送らない（文字起こしは「一般」→「文字起こし」のエンジンのまま）。
  - Windows: 設定 → AI で「音声入力」か「会議」の AI を Claude にし、「Claude の API キー」を保存すると、整形・英訳・議事録（作り直しを含む）が Claude で行われる。キーが正しくなければ、HUD・会議ノート・「接続を試す」に「Claude の API キーが正しくありません（401）」と出る（音声入力では整える前の文章を入力する）。
- 出典: ユーザーの依頼（2026-11-03「claude APIも利用できるようにして。認証はAPIキーを入力する形にして」）
- 対象: Mac / Windows
- 実装の場所: `ClaudeClient`、`TextAIClient`、`TextAIProvider`、`AISettingsTab`、`ClaudeKeySection`
- Windows の実装: `windows/Hanasu.Core/Claude/ClaudeClient.cs`、`windows/Hanasu.Core/Claude/ClaudeException.cs`、`windows/Hanasu.Core/Ai/TextAiFactory.cs`、`windows/Hanasu.Windows/Views/SettingsWindow.xaml.cs`
- 確かめ方: Mac は `.build/debug/Hanasu --refine-text <文> --ai claude --show-request`（送る JSON とヘッダー。キーは伏せる）、`ANTHROPIC_API_KEY=<偽のキー> .build/debug/Hanasu --refine-text <文> --ai claude` と `--claude-test`（401 の文言）、`--render-ai-settings /tmp/ai.png --claude`
  - Windows は `cd windows && dotnet test Hanasu.Core.Tests`（`ClaudeClientTests`・`TextAiSelectionTests`）、`dotnet run --project Hanasu.Cli -- claude-request "<文章>"`（送る内容。キーは伏せる）、`claude-check --fake-key`（401 の文言）、`claude-refine "<文章>"`（`ANTHROPIC_API_KEY` があるとき）

### REQ-COM-021 API キーは、他のアプリから読み取れない形で保存する
- 内容: Claude と Gemini の API キーを、OS が用意する保護の仕組みに保存し、Hanasu 以外のアプリからは（ユーザーの確認なしに）読めないようにする。ログ・設定ファイル・画面には平文で出さない。
- 受け入れ条件:
  - Mac: キーはログインキーチェーンの項目（サービス `dev.mactypeless.Hanasu`）に入り、その ACL は復号を Hanasu 自身だけに許し、ほかのアプリにはログインのパスワードを求める（`security dump-keychain -a` で `require-password`）。UserDefaults・ログ・画面にはキーを出さない（設定画面は末尾 4 文字だけ。入力欄はマスクし、保存したら空にする）。削除できる。
  - Mac で守れないもの: この Mac（macOS 26.6.2）で試すと、アドホック署名の別のプログラムは ACL に関係なく確認なしで読めた（[design/security.md](../design/security.md) の 1.3）。同じユーザーで動く悪意のあるプログラムからは守れない。
  - Windows: API キーは `%LOCALAPPDATA%\Hanasu\secrets.json` に暗号化して置き、`settings.json`・ログ・画面には平文で出さない（画面は末尾 4 文字だけ）。設定 → AI →「API キーを Windows Hello で守る」をオンにすると、ほかのアプリが読もうとしても Windows Hello の確認（PIN・顔・指紋）が出る。オフ（既定の DPAPI）のときは、同じ Windows ユーザーで動くほかのアプリからは確認なしに読める（Windows の仕組みの限界。[design/security-windows.md](../design/security-windows.md)）。PR #19 までに保存した Gemini の API キーは、そのまま読める。
- 出典: ユーザーの依頼（2026-11-03「APIキーは重要な情報なので、他のアプリからは読み取れない状態で保存して」）
- 対象: Mac / Windows
- 実装の場所: `Keychain`（`save`・`load`・`hint`・`delete`）、`ClaudeKeySection`、`ClaudeClient.redacted`
- Windows の実装: `windows/Hanasu.Core/Settings/SecretStore.cs`、`windows/Hanasu.Windows/Services/WindowsSecurity.cs`（`WindowsHelloKey`）、`windows/Hanasu.Windows/Services/SmallServices.cs`（`DpapiDataProtector`）
- 確かめ方: Mac は `.build/debug/Hanasu --keychain-selftest`（名前を変えた一時的な項目で、保存・末尾 4 文字・読み出し・ACL・削除。`--keep` で残し、`--keychain-selftest-delete <サービス名>` で消す）
  - Windows は `cd windows && dotnet test Hanasu.Core.Tests`（`SecretStoreTests`。DPAPI と Windows Hello は偽物）。Windows Hello の確認が出ることは Windows の実機で確かめる（まだ確かめていない）

### REQ-COM-022 セキュリティの調査の結果を、実装と文書に入れる
- 内容: 通信・秘密の扱い・ダウンロード・保存するファイル・クリップボード・プロンプトインジェクション・権限・依存関係・配布について調べ、直せるものは直し、残る危険は文書に書く。
- 受け入れ条件:
  - Mac: [design/security.md](../design/security.md) に、項目ごとの「確かめたこと・直したこと・残る危険」がある。直したもの: AI の通信はリダイレクトに従わずキャッシュを残さない（DEC-COM-044）、サービスアカウントの `token_uri` と Vertex AI のリージョンを確かめる（DEC-COM-053）、会議のフォルダを 0700 にする（DEC-COM-052）、自己署名でも Hardened Runtime を付ける（DEC-COM-051）。
  - Windows: [design/security-windows.md](../design/security-windows.md) に項目ごとの「確かめたこと・直したこと・残る危険」がある。直したもの（モデルのハッシュの確認、リダイレクトでキーを送らない、DLL の探索の場所、権限の高いウインドウに貼らない、区切りのタグの無害化、ログの伏せ字、NuGet の lock ファイル、配布物の SHA-256）は、DEC-COM-142・145〜150 のとおりに動く。
- 出典: ユーザーの依頼（2026-11-03「その他セキュリティで気をつけるべきところを調査してその結果を盛り込んで」）
- 対象: Mac / Windows
- 実装の場所: `SecureHTTP`、`ServiceAccountTokenProvider.isTrustedTokenURL`、`GeminiClient.isValidLocation`、`MeetingStore.createPrivateDirectory`、`scripts/build-app.sh`
- Windows の実装: `windows/Hanasu.Core/Net/ModelDownload.cs`、`windows/Hanasu.Core/Net/SafeHttp.cs`、`windows/Hanasu.Core/Ai/PromptText.cs`、`windows/Hanasu.Core/Ai/SecretRedactor.cs`、`windows/Hanasu.Windows/Services/WindowsSecurity.cs`
- 確かめ方: Mac は [design/security.md](../design/security.md) の各項目。`--keychain-selftest`。Hardened Runtime は `./scripts/build-app.sh` のあとに `codesign -dvv build/Hanasu.app`（flags に runtime）と実機の起動で確かめる
  - Windows は `cd windows && dotnet test Hanasu.Core.Tests`（`DownloadWithWrongHashIsRejected`・`DownloadsOnlyFromAllowedHosts`・`PromptSafetyTests`）、CI（`.github/workflows/windows.yml` の locked restore と SHA-256）。DLL の探索と UIPI は Windows の実機で確かめる（まだ確かめていない）

### REQ-COM-023 Claude の既定のモデルは、音声入力は Haiku 5.5、会議は Sonnet 5.5 にする
- 内容: Claude を選んだときの既定のモデルは、音声入力（整形・英訳・選択の編集）が `claude-haiku-5-5`、会議（議事録・会議への質問）が `claude-sonnet-5-5`。どちらも設定で Haiku 5.5 / Sonnet 5.5 / Opus 5.5 から変えられる。
- 受け入れ条件: 設定を変えていない状態で Claude を選ぶと、音声入力は `claude-haiku-5-5`、会議は `claude-sonnet-5-5` で送られる（Mac: `--refine-text … --ai claude --show-request` の `model`、`--render-ai-settings`）。「AI」タブのモデルの選択で 3 つから変えられる。
  - Windows: 設定を変えていない状態で Claude を選ぶと、音声入力は `claude-haiku-5-5`、議事録は `claude-sonnet-5-5` で送る。設定 → AI のモデルの欄で 3 つから選べる。一覧にない ID が設定に残っていたら既定に戻す。
- 出典: ユーザーの指示（2026-11-03「規定モデルは haiku にして」、2026-11-04「Claude は議事録は sonnet にして」）
- 対象: Mac / Windows
- 実装の場所: `ClaudeClient.Model`（`defaultDictation`・`defaultMeeting`）、`AppSettings.init`（`claudeModel`・`claudeMinutesModel` の初期値）
- Windows の実装: `windows/Hanasu.Core/Claude/ClaudeModels.cs`、`windows/Hanasu.Core/Settings/AppSettings.cs`
- 確かめ方: Mac は `.build/debug/Hanasu --refine-text <文> --ai claude --show-request`、`--render-ai-settings /tmp/ai.png --claude`
  - Windows は `cd windows && dotnet test Hanasu.Core.Tests`（`ClaudeClientTests.ModelsAndDefaults`・`UnknownModelFallsBackToTheDefaultForThePurpose`）、`dotnet run --project Hanasu.Cli -- claude-request "<文章>" [--minutes]`

### REQ-COM-024 音声入力と会議で、使う AI とモデルを別々に選べる
- 内容: 音声入力（整形・英訳・選択の編集）と会議（議事録・会議への質問）のそれぞれで、AI（Gemini / Claude）とモデルを別々に選べる。
- 受け入れ条件:
  - Mac: 設定の「AI」タブの「使う AI とモデル」に「音声入力」と「会議」が並び、それぞれで Gemini / Claude とモデルを選べる（例: 音声入力は Gemini の flash-lite、会議は Claude Sonnet 5.5）。既定は、今までの設定を引き継いで両方 Gemini（音声入力は `geminiModel`、会議は `meetingMinutesModel`）。辞書の候補探しは会議の設定を使う（DEC-COM-040）。
  - Windows: 設定 → AI の「使う AI とモデル」に「音声入力（整形・英訳）」と「会議（議事録）」の 2 行があり、行ごとに AI とモデルを選べる。既定は今までどおり（どちらも Gemini、モデルは gemini-3.5-flash-lite と gemini-3.8-flash）。Windows 版には選択の編集・会議への質問がないので、音声入力は整形・英訳、会議は議事録（作り直しを含む）に効く。
- 出典: ユーザーの指示（2026-11-03「会議の要約モデルと音声入力モデルは個別に指定できるようにして」）
- 対象: Mac / Windows
- 実装の場所: `TextAIPurpose`、`AppSettings`（`dictationAIProvider`・`meetingAIProvider`・`aiProvider(for:)`・`textModel(for:)`）、`AIChoiceRow`
- Windows の実装: `windows/Hanasu.Core/Ai/TextAiFactory.cs`、`windows/Hanasu.Core/Settings/AppSettings.cs`（`DictationAi` / `MeetingAi`）、`windows/Hanasu.Windows/Views/SettingsWindow.xaml.cs`
- 確かめ方: Mac は `.build/debug/Hanasu --render-ai-settings /tmp/ai.png --claude`（音声入力は Gemini、会議は Claude の見た目）
  - Windows は `cd windows && dotnet test Hanasu.Core.Tests`（`TextAiSelectionTests`）

---

## 設計判断

### DEC-COM-001 Gemini の認証は、API キーとサービスアカウントの 2 通りから選ぶ
- 決めたこと: Google AI Studio の API キー（`generativelanguage.googleapis.com`、`x-goog-api-key` ヘッダー。URL のクエリに載せない）か、Vertex AI のサービスアカウント（`aiplatform.googleapis.com`、`Authorization: Bearer`）から選ぶ。リクエスト本文の形式はどちらも同じ。ターミナルから起動したときは環境変数 `GEMINI_SERVICE_ACCOUNT_JSON` を鍵のパスの初期値にする。
- 理由: 個人の API キーでも、会社の GCP（Vertex AI）でも使えるようにする。出典の文書がないため設計判断として扱う（要件にするならユーザーに確かめる）。
- 決めた場面: 初版（a787da8）
- 関係する要件: REQ-DIC-003, REQ-MTG-006
- 対象: Mac
- 実装の場所: `GeminiClient.Auth`、`GeminiClient.authFromSettings`、`GeminiClient.generate`

### DEC-COM-002 API キーはキーチェーンに保存する
- 決めたこと: API キー（Gemini・Claude）はキーチェーン（`kSecClassGenericPassword`、サービス `dev.mactypeless.Hanasu`、アカウント `gemini-api-key` / `claude-api-key`）に保存し、UserDefaults やログには残さない。項目の ACL は DEC-COM-048。
- 理由: 秘密情報を平文の設定ファイルに置かない。
- 決めた場面: 初版（a787da8）。Claude のキーと ACL はこの PR（Claude API の対応）
- 関係する要件: REQ-DIC-003, REQ-COM-021
- 対象: Mac
- 実装の場所: `Keychain`

### DEC-COM-003 サービスアカウントは鍵のパスだけを保存し、トークンを使い回す
- 決めたこと: 鍵ファイル（JSON）のパスだけを保存し、中身はアプリに取り込まない。秘密鍵で RS256 の JWT を作って `token_uri` でアクセストークン（scope: `cloud-platform`）に替え、期限の 1 分前まで使い回す。トークンはメモリ上だけに置く。RSA の署名は Security.framework の `SecKeyCreateSignature` で、PKCS#8 の外側を外して PKCS#1 にしてから読む。
- 理由: 外部のライブラリに頼らず、鍵を複製しない。
- 決めた場面: 初版（a787da8）
- 関係する要件: REQ-DIC-003
- 対象: Mac
- 実装の場所: `ServiceAccountTokenProvider`、`ServiceAccountCredentials`

### DEC-COM-004 Vertex AI のリージョンの初期値は global
- 決めたこと: リージョンの初期値は `global`。`us-central1` なども指定できる。
- 理由: 新しいモデルが先に来る。
- 決めた場面: 初版（a787da8）
- 関係する要件: REQ-DIC-003
- 対象: Mac
- 実装の場所: `AppSettings.init`（`vertexLocation` の初期値）

### DEC-COM-005 整形の既定のモデルは gemini-3.5-flash-lite
- 決めたこと: 整形（と英訳・編集）のモデルの初期値は `gemini-3.5-flash-lite`。`gemini-3.8-flash` と任意のモデル ID も選べる。
- 理由: 検証で flash-lite は約 1.3 秒、3.8-flash は約 2 秒で、仕上がりは同じだった（[verification/dictation.md](../verification/dictation.md) 2）。音声入力は待たされないことが大事。
- 決めた場面: 初版（a787da8）
- 関係する要件: REQ-DIC-003
- 対象: Mac
- 実装の場所: `AppSettings.suggestedModels`

### DEC-COM-006 thinkingLevel は、モデル名から自動で選ぶ
- 決めたこと: モデル名に `lite` を含めば `minimal`、それ以外は `low`。
- 理由: 思考を最小にして待ち時間を減らす。`gemini-3.8-flash` は `minimal` に対応しない。
- 決めた場面: 初版（a787da8）
- 関係する要件: REQ-DIC-003
- 対象: Mac
- 実装の場所: `GeminiClient.thinkingLevel`

### DEC-COM-007 Gemini は SDK を使わず、REST の generateContent を直接呼ぶ
- 決めたこと: `URLSession` で `generateContent` を呼ぶ。`temperature` などのサンプリングのパラメータは送らない。
- 理由: Swift 向けの公式 SDK に依存しない。リクエストは 1 種類だけ。サンプリングのパラメータは非推奨になった。
- 決めた場面: 初版（a787da8）
- 関係する要件: REQ-DIC-003, REQ-MTG-006
- 対象: Mac
- 実装の場所: `GeminiClient.generate`

### DEC-COM-008 メニューバーに常駐するアプリにする
- 決めたこと: `LSUIElement = true` で Dock に出さず、メニューバーに常駐する。対象は macOS 26 (Tahoe) 以降の Apple Silicon。
- 理由: どのアプリの上でも使う道具なので、ウインドウを持たずに待つ。SpeechAnalyzer が macOS 26 の API。
- 決めた場面: 初版（a787da8）
- 関係する要件: REQ-DIC-001
- 対象: Mac
- 実装の場所: `AppDelegate.applicationDidFinishLaunching`（Info.plist の `LSUIElement`）

### DEC-COM-009 起動のたびに設定画面を開き、アクセシビリティの許可を求める
- 決めたこと: 起動したら設定画面を開き、⌘V の送信に要るアクセシビリティの許可を求める。Dock や Finder でアイコンを開いたときも設定画面を前に出す。
- 理由: メニューバーのアイコンが隠れていても設定に辿り着けるようにする。README には「初回起動で設定画面が開く」とあるが、コードは毎回開く。今回、暗黙の振る舞いから設計判断に格上げして記録した。
- 決めた場面: 初版（a787da8）のコード。記録はこの PR
- 関係する要件: REQ-DIC-004
- 対象: Mac
- 実装の場所: `AppDelegate.applicationDidFinishLaunching`、`AppDelegate.applicationShouldHandleReopen`

### DEC-COM-010 グローバルショートカットは Carbon の RegisterEventHotKey で登録する
- 決めたこと: 外部のライブラリを使わず、`RegisterEventHotKey` で押下と解放の両方を受け取る。ショートカットの記録の画面も自前で作る。登録に失敗したら（ほかのアプリと重なるなど）アラートで別のキーを選ぶよう案内する。
- 理由: アクセシビリティの許可なしで使え、押下と解放が取れるのでトグルとプッシュトゥトークの両方を作れる。依存を増やさない。
- 決めた場面: 初版（a787da8）
- 関係する要件: REQ-DIC-001, REQ-DIC-006, REQ-MTG-001
- 対象: Mac
- 実装の場所: `HotKeyManager`、`ShortcutRecorder`

### DEC-COM-011 ショートカットの ID は、インスタンスをまたいで重ならないようにする
- 決めたこと: `HotKeyManager` の登録 ID をクラス全体で採番する。
- 理由: どのインスタンスも同じイベントターゲットにハンドラを置くので、ID が重なると、後から置いたハンドラがほかのインスタンスのショートカットまで受け取る（音声入力の ID 1 と会議の ID 1 が重なっていた）。
- 決めた場面: PR #8、PR #10（同じ変更を 2 つの PR で入れた）
- 関係する要件: REQ-DIC-050, REQ-MTG-012
- 対象: Mac
- 実装の場所: `HotKeyManager`（`nextID`）

### DEC-COM-012 ショートカットを記録している間は、すべてのショートカットを外す
- 決めたこと: 設定画面でショートカットを記録している間は、音声入力・英訳・編集・会議・再入力のショートカットを一時的に外し、終わったら戻す。
- 理由: 記録したいキーを横取りしないため。
- 決めた場面: 初版（a787da8）。対象は機能を足すたびに増えた
- 関係する要件: REQ-DIC-001
- 対象: Mac
- 実装の場所: `AppDelegate.openSettings`

### DEC-COM-013 設定は UserDefaults に置き、機能ごとに別のストアに分ける
- 決めたこと: 設定は UserDefaults に置く（API キーだけキーチェーン）。初版の設定は `AppSettings`、あとから足した機能（アプリ別の文体・スニペット・画面の文脈・履歴・編集・会議のメモ・会議の検出・議事録の型）は、それぞれ別のストアとキーに持つ。
- 理由: 10 個の改善案を並行して作ったので、共有の `Settings.swift` の変更を小さくして衝突を避けた。
- 決めた場面: 初版（a787da8）。分け方は PR #5〜#14
- 関係する要件: REQ-DIC-020, REQ-DIC-030, REQ-DIC-040, REQ-DIC-060
- 対象: Mac
- 実装の場所: `AppSettings`

### DEC-COM-014 権限は、要るときに求める
- 決めたこと: マイク（`AVCaptureDevice.requestAccess`）と音声認識（`SFSpeechRecognizer.requestAuthorization`）は録音を始めるときに、アクセシビリティは起動時と初めて入力するときに求める。Whisper / Gemini のエンジンでは音声認識の権限を求めない。権限がなければ HUD に出し、システム設定の該当ページを開く。
- 理由: 使わない権限を求めない。
- 決めた場面: 初版（a787da8）。Whisper / Gemini の分は PR #17
- 関係する要件: REQ-DIC-001, REQ-COM-001
- 対象: Mac
- 実装の場所: `Permissions.ensureRecordingPermissions`

### DEC-COM-015 SwiftPM でビルドし、スクリプトで .app に組み立てる
- 決めたこと: Xcode のプロジェクトを使わず Swift Package Manager でビルドし（Swift 6.2、言語モードは Swift 5）、`scripts/build-app.sh` で `.app` に組み立てて署名する。
- 理由: 開発する Mac に Command Line Tools しかない。マイク・音声認識の許可のダイアログには Info.plist の利用目的の文字列が要るので、`.app` として起動する。
- 決めた場面: 初版（a787da8）
- 関係する要件: REQ-DIC-001
- 対象: Mac
- 実装の場所: `scripts/build-app.sh`

### DEC-COM-020 エンジンは、音声入力と会議の記録で別々に選ぶ
- 決めたこと: 「音声入力」と「会議の記録」でエンジンを別々に選ぶ。「選択を声で編集」は音声入力と同じエンジンを使う。Mac 標準を選んでいる間だけ「Mac 標準の認識モデル」を出す。言語（`ja-JP`）は共通。設定は「一般」タブの「文字起こし」欄に置き、タブは増やさない。
- 理由: 音声入力は待ち時間と途中経過が大事で、会議は記録のあとに待てるので精度を優先したい。自分の短い発話は Gemini に送ってよくても相手の声を含む会議の音声は送りたくない、という使い分けができる。
- 決めた場面: PR #17
- 関係する要件: REQ-COM-001
- 対象: Mac
- 実装の場所: `AppSettings`（`dictationEngine` / `meetingEngine`）、`TranscriptionEngineSettingsSection`

### DEC-COM-021 Whisper には WhisperKit を使う
- 決めたこと: WhisperKit v1.1.1（MIT）の `WhisperKit` の製品だけを使う（依存は同じパッケージの ArgmaxCore だけ）。
- 理由: whisper.cpp より、Swift から直接使え、Neural Engine で動き、Hugging Face からのモデルの取得まで揃っている。C/C++ のビルドやモデルの変換を自分たちで持たずに済む。
- 決めた場面: PR #17
- 関係する要件: REQ-COM-001
- 対象: Mac
- 実装の場所: `WhisperEngine`（`Package.swift` の依存）

### DEC-COM-022 Whisper のモデルは 4 つから選び、既定は small
- 決めたこと: tiny / base / small / large-v3-turbo（`openai_whisper-large-v3-v20240930_626MB`、M1 以降）。既定は small で、音声入力と会議で共通。
- 理由: tiny / base は日本語には足りないことを確かめた（[verification/dictation.md](../verification/dictation.md) 8）。small / large-v3-turbo の精度は実機で確かめる。
- 決めた場面: PR #17
- 関係する要件: REQ-COM-001, REQ-COM-003
- 対象: Mac
- 実装の場所: `WhisperModel`、`AppSettings.init`（`whisperModel` の初期値）

### DEC-COM-023 Whisper のモデルの置き場所と、完了の印
- 決めたこと: 保存先は `~/Library/Application Support/Hanasu/Models/whisper`。ダウンロード後に一度読み込んで CoreML の最適化を済ませ、印（`.hanasu-complete`）を置く。印のないフォルダは使わない。進み具合・取り消し・削除を設定画面に出し、前に使ったモデルが残っていればその行から消せる。
- 理由: 途中で止まったダウンロードを使わない。
- 決めた場面: PR #17
- 関係する要件: REQ-COM-003
- 対象: Mac
- 実装の場所: `WhisperModelStore`

### DEC-COM-024 Whisper の言語は設定の言語に合わせ、辞書の語をヒントに渡す
- 決めたこと: 言語は設定の言語から決め（`ja-JP` → `ja`）、自動判定はしない。辞書の語とスニペットの起動フレーズを、前の文脈（prompt tokens）として最大 30 語渡す。
- 理由: 検証で、辞書の語を渡すと「Whisper」「Gemini」「スプレッドシート」の表記が直った。
- 決めた場面: PR #17
- 関係する要件: REQ-COM-001
- 対象: Mac
- 実装の場所: `AppSettings.whisperLanguage`、`WhisperEngine.prompt`

### DEC-COM-025 長い音声は、Whisper の VAD を使わず自分で区切る
- 決めたこと: 30 秒を超える音声は、20〜30 秒ごとに、目安の前 5 秒のうちいちばん静かなところで切り、無音だけの区切りは飛ばして、まとめて WhisperKit に渡す（並行して処理される）。
- 理由: WhisperKit の VAD での区切り（`chunkingStrategy: .vad`）は、長い音声で区間が抜けたり、音声の長さを超える時刻の区間が出たりした。
- 決めた場面: PR #17
- 関係する要件: REQ-COM-001
- 対象: Mac
- 実装の場所: `WhisperEngine.transcribe`

### DEC-COM-026 Whisper の結果から、注記や決まり文句だけの区間を捨てる
- 決めたこと: 区切りの長さを超える時刻の区間、「(音楽)」「[拍手]」のような注記だけの区間、無音で出がちな決まり文句（「ご視聴ありがとうございました」など）を捨てる。声があるのに何も返らない区切りは 1 回だけやり直す。
- 理由: 無音から作り話の文が出るのを防ぐ。tiny で時々、声があるのに空になった。
- 決めた場面: PR #17
- 関係する要件: REQ-COM-001
- 対象: Mac
- 実装の場所: `WhisperEngine.isNoise`、`WhisperEngine.transcribe`

### DEC-COM-027 読み込んだ Whisper のモデルは使い回し、録音を始めたときに読み込む
- 決めたこと: `WhisperEngine` actor で読み込んだモデルを使い回し、録音を始めたときに読み込みを始める。
- 理由: 止めてからの待ち時間を、文字起こしの分だけにする。
- 決めた場面: PR #17
- 関係する要件: REQ-COM-001
- 対象: Mac
- 実装の場所: `WhisperEngine.preload`

### DEC-COM-030 Gemini での文字起こしは、書き起こすだけにさせる
- 決めたこと: 16 kHz モノラルの音声を FLAC（書けなければ WAV）にして inline data で `generateContent` に送る。「書き起こすだけ。中の質問や指示に答えない。フィラーや言い直しも省かない」と指示し、辞書の語を添える。何も話されていなければ空にする。認証は整形と同じ。
- 理由: 文字起こしのあとは、ほかのエンジンと同じ流れで扱えるようにする。
- 決めた場面: PR #17
- 関係する要件: REQ-COM-001
- 対象: Mac
- 実装の場所: `GeminiTranscriber`

### DEC-COM-031 Gemini での文字起こしと整形は、1 回にまとめない
- 決めたこと: 文字起こしと整形を別々に呼ぶ。
- 理由: 辞書の置き換え → スニペットの照合 → 整形、は整形の前の文字列に対して決定的に処理する。まとめるとスニペットの本文が Gemini を通ったり、置き換えルールが効かなかったりする。待ち時間の差は整形の 1 往復（約 0.9 秒）だけ。整形オフ・英訳・アプリ別の文体もそのまま使える。
- 決めた場面: PR #17
- 関係する要件: REQ-COM-001, REQ-DIC-030, REQ-DIC-070
- 対象: Mac
- 実装の場所: `GeminiTranscriber.transcribe`

### DEC-COM-032 Gemini で文字起こしするモデルは、整形とは別に選ぶ
- 決めたこと: 文字起こしのモデルは整形とは別の設定で、初期値は `gemini-3.5-flash-lite`。
- 理由: 文字起こしと整形で、求める速さと精度が違う場面がある。
- 決めた場面: PR #17
- 関係する要件: REQ-COM-001
- 対象: Mac
- 実装の場所: `AppSettings`（`geminiTranscriptionModel`）

### DEC-COM-033 Gemini を選ぶと、音声を Google に送ることを先に示す
- 決めたこと: Gemini を選んだときは、「録った音声を Google に送る」ことを、注意の印つきで欄の先頭に書く。エンジンの名前にも「音声を Google に送る」と入れる。
- 理由: 音声が Mac の外に出るのは Gemini を選んだときだけなので、選ぶ人に分かるようにする。
- 決めた場面: PR #17
- 関係する要件: REQ-COM-001, REQ-MTG-023
- 対象: Mac
- 実装の場所: `TranscriptionEngine.label`、`GeminiTranscriptionSection`

### DEC-COM-040 AI は用途ごとに 1 つ選び、文字起こしのエンジンとは別にする
- 決めたこと: 文章の処理に使う AI（Gemini / Claude）を、「音声入力」（整形・英訳・選択の編集・音声入力の履歴のやり直し）と「会議」（議事録とその作り直し・会議への質問・辞書の候補探し）の 2 つの用途で別々に選ぶ。既定はどちらも Gemini（今までの設定を引き継ぐ）。辞書の候補探しは会議の記録を読む長い処理なので、会議の設定（AI とモデル、Gemini なら `meetingMinutesModel`）を使う。文字起こしのエンジン（OS 標準 / Whisper / Gemini）は今までどおり別に選び、Claude には音声を送らない。設定画面は「Gemini」タブを「AI」タブにし、先頭に 2 つの用途を並べる。Gemini の認証の欄は、文字起こしのエンジン「Gemini」でも使うので、AI の選択に関わらず出す。
- 理由: ユーザーの指示（REQ-COM-024）。音声入力は速さ、会議は長い記録のまとめと、求めるものが違う。辞書の候補探しは、今まで議事録のモデルを使っていた（DEC-DIC-088 の作り）のに合わせた。
- 決めた場面: この PR（Claude API の対応）
- 関係する要件: REQ-COM-020, REQ-COM-024
- 対象: Mac
- 実装の場所: `TextAIProvider`、`TextAIPurpose`、`TextAIClient.fromSettings`、`AppSettings.aiProvider(for:)`・`textModel(for:)`、`AISettingsTab`

### DEC-COM-041 Claude は SDK を使わず、REST の Messages API を直接呼ぶ
- 決めたこと: `POST https://api.anthropic.com/v1/messages` に、`x-api-key`・`anthropic-version: 2026-10-21`・`content-type: application/json` を付けて送る。`temperature` / `top_p` / `top_k`（この版では 400）と assistant の prefill（400）は送らない。出力の形はシステムプロンプトの指示で決める。応答は `type` が `text` のブロックだけをつなぐ（`thinking`・`fallback` のブロックは除く）。streaming は使わない。
- 理由: Swift には公式 SDK がない。Gemini と同じく 1 回送って結果を待つ形（DEC-COM-007）にそろえる。議事録は長いが、max_tokens とタイムアウトを大きくして待つ（DEC-COM-043）。
- 決めた場面: この PR
- 関係する要件: REQ-COM-020
- 対象: Mac
- 実装の場所: `ClaudeClient.requestBody`・`headers`・`generate`・`parseMessage`

### DEC-COM-042 Claude のモデルは 3 つから選ぶ
- 決めたこと: `claude-haiku-5-5`・`claude-sonnet-5-5`・`claude-opus-5-5`（日付を付けない ID）から選ぶ。音声入力と会議で別々に持つ（`claudeModel`・`claudeMinutesModel`）。既定は REQ-COM-023。一覧にない ID が設定に入っていても、そのまま送る。設定画面に料金の目安（2026-11 時点）を書く。
- 理由: 速さ・費用・賢さの違う 3 段階で足りる。料金は使う人が選ぶときの判断材料になるが、変わるので時点を書く。
- 決めた場面: この PR
- 関係する要件: REQ-COM-020, REQ-COM-023, REQ-COM-024
- 対象: Mac
- 実装の場所: `ClaudeClient.Model`、`AIChoiceRow`、`ClaudeKeySection`

### DEC-COM-043 Claude の考える量は effort で決め、thinking は送らない
- 決めたこと: 音声入力の処理（整形・英訳・選択の編集）は `output_config.effort: "low"`、`max_tokens` 8192。会議の処理（議事録・会議への質問・辞書の候補）は `"medium"`、`max_tokens` 32000、タイムアウトは最低 600 秒。`thinking` は送らない（3 つとも adaptive が既定）。
- 理由: Opus 5.5 は thinking を無効にできず（`disabled` は 400）、Sonnet 5.5 は `disabled` が 400（`between_tools` は Sonnet 5.5 だけ）、Haiku 5.5 は `disabled` を受け付けるが、3 つで形をそろえるため effort だけで決める。資料では、軽い処理は low で考えるのを省くことが多い。thinking も max_tokens に数えられるので、返ってくる文章より大きく取る。議事録は streaming を使わないので、出力が長くても切れないだけのタイムアウトにする。
- 決めた場面: この PR
- 関係する要件: REQ-COM-020
- 対象: Mac
- 実装の場所: `ClaudeClient.Effort`、`TextAIClient`（用途ごとの effort）、`MeetingProcessor.makeMinutes`、`MeetingAsk.ask`

### DEC-COM-044 AI の通信は、リダイレクトに従わず、キャッシュとクッキーを使わない
- 決めたこと: Gemini・Claude・サービスアカウントのトークンの通信は、`SecureHTTP.session`（ephemeral、URL キャッシュ・クッキー・資格情報の保存なし、TLS 1.2 以上）で送る。リダイレクトには従わずエラーにする。`https` 以外の URL には送らない。証明書の検証は OS の既定のまま。
- 理由: リダイレクトに従うと、キーの入ったヘッダー（`x-api-key`・`x-goog-api-key`・`Authorization`）が別のホストに送られうる。応答（整えた文章・議事録）をディスクのキャッシュに残さない。
- 決めた場面: この PR（セキュリティの調査）
- 関係する要件: REQ-COM-022
- 対象: Mac
- 実装の場所: `SecureHTTP`

### DEC-COM-045 Claude の stop_reason を先に見て、refusal は server-side fallback に任せる（Haiku 以外）
- 決めたこと: 応答の `stop_reason` が `refusal` なら「安全のための判定で断られた」（`stop_details.category` があれば添える）、`max_tokens` なら「長さの上限で切れた」としてエラーにし、本文は使わない（音声入力では、整形前の文章を入力する）。Sonnet 5.5 と Opus 5.5 には `fallbacks: "default"` と `anthropic-beta: server-side-fallback-2026-07-01` を付け、断られたときは Anthropic が勧めるモデルで同じリクエストをやり直してもらう。Haiku 5.5 には付けない。
- 理由: refusal は HTTP 200 で返り、中身が空か途中まで。切れた文章を貼り付けると困る。資料は fallbacks を最初から付けることを勧めている。Haiku 5.5 には server-side fallback がない（配列の形は 400、`"default"` は断られたまま）。
- 決めた場面: この PR
- 関係する要件: REQ-COM-020
- 対象: Mac
- 実装の場所: `ClaudeClient.parseMessage`、`ClaudeClient.Model.supportsServerSideFallback`、`ClaudeClient.requestBody`

### DEC-COM-046 Claude のエラーは 429 と 5xx だけ少しやり直し、ほかは分かる文言で知らせる
- 決めたこと: 429 と 5xx（529 を含む）は、`retry-after`（なければ 1 秒・2 秒）だけ待って 2 回までやり直す。待ち時間がタイムアウトの半分（最大 10 秒）を超えるときはやり直さない。400 / 401 / 402 / 403 / 404 / 413 はやり直さず、状態ごとの文言にする（401 は「API キーが正しくありません」）。文言にキーは入れない。
- 理由: 音声入力は待たされないことが大事（DEC-DIC-010 の 15 秒）。4xx はやり直しても直らない。
- 決めた場面: この PR
- 関係する要件: REQ-COM-020
- 対象: Mac
- 実装の場所: `ClaudeClient.send`・`retryDelay`・`ClaudeError`

### DEC-COM-047 Claude にも Gemini と同じプロンプトを送り、システムプロンプトをキャッシュする
- 決めたこと: 整形・英訳・選択の編集・議事録・会議への質問・辞書の候補は、Gemini と同じ文面（`GeminiClient.refinePrompt`・`translationPrompt`・`editInstruction`・`editPrompt`、`MinutesPrompt`、`MeetingAsk.instruction`、`DictionarySuggester.instruction`）を使い、Claude ではシステムプロンプトを `system` に入れる。`system` のブロックに `cache_control: {type: "ephemeral"}` を付ける。
- 理由: 2 つの AI で振る舞いをそろえ、プロンプトインジェクションの対策（`<transcript>` タグ、選択文のランダムなタグ名）もそのまま効かせる。システムプロンプトは固定なのでキャッシュが効くが、最小のトークン数（512）に満たなければキャッシュされない（エラーにはならない）。整形のシステムプロンプトは日本語で約 600 文字で、最小に届くかは本物のキーで確かめていない。
- 決めた場面: この PR
- 関係する要件: REQ-COM-020, REQ-DIC-003
- 対象: Mac
- 実装の場所: `TextAIClient`、`GeminiClient.refinePrompt`・`translationPrompt`、`ClaudeClient.requestBody`

### DEC-COM-048 キーチェーンの項目の ACL は、Hanasu だけに読ませ、ほかのアプリにはパスワードを求める
- 決めたこと: ファイル型のログインキーチェーンに、`SecAccessCreate` で作った ACL を付けて保存する。復号を許すアプリは Hanasu 自身だけ、ほかのアプリには `requirePassphase`（ログインのパスワードの入力）を求める。macOS 26.6 では、ACL の確認の出し方が保存のときにバイト順が入れ替わったので、入れ替えた値で保存し、保存された項目を読み返して確かめる（違えば、そのままの値で作り直す）。データ保護キーチェーン（`kSecUseDataProtectionKeychain`）・`SecAccessControl`・Secure Enclave の永続の鍵は使わない。`kSecAttrAccessible` は、ファイル型のキーチェーンでは効かないので付けない。
- 理由: データ保護キーチェーンなどは、Apple Developer の Team ID と keychain-access-groups の entitlement（プロビジョニングプロファイルが要る）がないと -34018 になる（この Mac で確かめた）。自己署名のアプリでできる一番強い形が、ファイル型のキーチェーンの ACL。確認を「許可」のクリックではなくパスワードにすると、うっかり許すことが減る。
- 決めた場面: この PR（[design/security.md](../design/security.md) の 1 章）
- 関係する要件: REQ-COM-021
- 対象: Mac
- 実装の場所: `Keychain.save`・`makeAccess`・`storedDecryptPrompt`

### DEC-COM-049 API キーは使うときに読み、設定画面には末尾 4 文字だけを出す
- 決めたこと: キーはリクエストを送るたびにキーチェーンから読み、クライアントやビューの状態に持たない（`ClaudeClient.apiKey` は読み出す関数）。設定画面は、保存のときに項目の属性（`kSecAttrComment`）に書いた末尾 4 文字（「…abcd」）を出し、キーの中身を読まない。入力欄は `SecureField` で、保存したら空にする。キーの有無も属性だけで調べる（確認のダイアログが出ない）。
- 理由: 前の版は設定画面を開くとキーを読み、`@State` に持っていた。メモリに長く置かない。属性はほかのアプリからも読めるが、末尾 4 文字だけなら困らない。
- 決めた場面: この PR
- 関係する要件: REQ-COM-021
- 対象: Mac
- 実装の場所: `Keychain.hint`・`exists`、`ClaudeClient.fromKeychain`、`ClaudeKeySection`、`GeminiAuthSection`

### DEC-COM-050 「接続を試す」は GET /v1/models/{model} で確かめる
- 決めたこと: 「接続を試す」は、選んでいるモデルの `GET https://api.anthropic.com/v1/models/{model}` を送る。200 なら「接続できました」、401 なら「キーが正しくありません」、404 なら「モデルが見つからないか、このキーでは使えません」。
- 理由: トークンを使わずに、キーの正しさとモデルを使えることを確かめられる。
- 決めた場面: この PR
- 関係する要件: REQ-COM-020
- 対象: Mac
- 実装の場所: `ClaudeClient.testConnection`、`ClaudeKeySection.testConnection`

### DEC-COM-051 自己署名でも Hardened Runtime を付ける
- 決めたこと: `scripts/build-app.sh` で自己署名の証明書（Hanasu Local Signing / Hanasu Release Signing）で署名するときも `--options runtime` を付ける。entitlements はマイク（`device.audio-input`）とリマインダー（`personal-information.calendars`）だけのまま。
- 理由: キーチェーンは Hanasu を信頼するので、ほかのプログラムが `DYLD_INSERT_LIBRARIES` などで Hanasu にコードを差し込むと、Hanasu としてキーを読める。Hardened Runtime はそれを止める。Hanasu はシステムのもの以外の dylib を読み込まない（`otool -L` で確かめた）ので、ライブラリの検証で困らない。
- 決めた場面: この PR
- 関係する要件: REQ-COM-022
- 対象: Mac
- 実装の場所: `scripts/build-app.sh`

### DEC-COM-052 会議の記録のフォルダは、本人だけが開けるようにする
- 決めたこと: `~/Documents/Hanasu/Meetings` と会議ごとのフォルダを 0700 で作り、前の版で作ったもの（0755）も保存のときに 0700 に直す。
- 理由: 会話の録音・文字起こし・議事録が入る。`~/Documents` はふつう本人だけが開けるが、権限を変えられていても守れるようにする。音声入力の履歴はすでに 0700 / 0600（DEC-DIC-070）。
- 決めた場面: この PR（セキュリティの調査）
- 関係する要件: REQ-COM-022, REQ-MTG-005
- 対象: Mac
- 実装の場所: `MeetingStore.createPrivateDirectory`

### DEC-COM-053 サービスアカウントの token_uri と Vertex AI のリージョンを確かめてから送る
- 決めたこと: 鍵ファイルの `token_uri` が `https://oauth2.googleapis.com`（古い鍵の `https://accounts.google.com`）でなければ、署名した JWT を送らない。Vertex AI のリージョンは英小文字・数字・ハイフンだけを受け付ける（ホスト名に入るため）。
- 理由: 鍵ファイルや設定（UserDefaults）を書き換えられると、署名した JWT やアクセストークンを別のホストに送らされうる。
- 決めた場面: この PR（セキュリティの調査）
- 関係する要件: REQ-COM-022
- 対象: Mac
- 実装の場所: `ServiceAccountTokenProvider.isTrustedTokenURL`、`GeminiClient.isValidLocation`

### DEC-COM-100 Windows 版は C# / .NET 8 / WPF で作り、OS に依存しない部分を分ける
- 決めたこと: `windows/` に C# 12 / .NET 8（LTS）/ WPF で作る（ターゲットは `net8.0-windows10.0.19041.0`）。プロンプト・Gemini・JWT・辞書・設定・音声の変換・状態遷移は OS に依存しない `Hanasu.Core`（net8.0）に置き、Mac でも `dotnet test` で確かめる。Whisper（`Hanasu.Whisper`）と話者分離（`Hanasu.Diarization`）も net8.0 に分ける。
- 理由: WinRT の音声認識に 19041 が要る。Windows の実機がない環境でも、UI 以外を Mac の上でテストし、CLI で実際に確かめられるようにする。
- 決めた場面: PR #19
- 関係する要件: REQ-COM-010, REQ-COM-011
- 対象: Windows
- 実装の場所: `windows/Hanasu.Core/`、`windows/Directory.Build.props`

### DEC-COM-101 Windows 版はタスクトレイに常駐し、2 つ目の起動は知らせて終える
- 決めたこと: WinForms の `NotifyIcon` でタスクトレイに常駐する（メニューは「音声入力を開始」「英訳して入力」「最近の結果」「設定…」「終了」と会議の項目）。2 つ目の起動は知らせて終わる。初回の起動では設定画面を開く。
- 理由: WPF に標準のトレイアイコンがなく、依存を増やさずに済む。2 つ起動するとホットキーを取り合う。
- 決めた場面: PR #19
- 関係する要件: REQ-COM-010
- 対象: Windows
- 実装の場所: `windows/Hanasu.Windows/TrayIcon.cs`、`windows/Hanasu.Windows/App.xaml.cs`

### DEC-COM-102 Windows 版の整形・英訳・議事録のプロンプトは、Mac 版と同じ文面にする
- 決めたこと: Mac 版の `GeminiClient.swift`（整形・英訳）、`MinutesTemplate.swift`・`MeetingNotes.swift`（議事録）の文面と組み立てをそのまま移し、共有している部分には「両方を直す」とコメントを書く。テストで文面と組み立てを確かめる。
- 理由: Mac と Windows で結果をそろえる。片方だけ直すことを防ぐ。
- 決めた場面: PR #19
- 関係する要件: REQ-DIC-003, REQ-DIC-010, REQ-MTG-006
- 対象: Windows
- 実装の場所: `windows/Hanasu.Core/Gemini/GeminiPrompts.cs`、`windows/Hanasu.Core/Meetings/MinutesTemplate.cs`

### DEC-COM-103 Windows 版の設定と秘密の保存
- 決めたこと: 設定は `%APPDATA%\Hanasu\settings.json`（壊れていたら `settings.json.broken` に退けて既定値で始める）。API キーは settings.json に入れず、`%LOCALAPPDATA%\Hanasu\secrets.json` に暗号化して置く（DEC-COM-144。PR #19 では settings.json の `protectedApiKey` に DPAPI で入れていた）。サービスアカウントは JSON のパスだけを保存する。ログは `%LOCALAPPDATA%\Hanasu\Logs\hanasu.log` で、文字起こしの中身は書かない（キーに見えるものは伏せる。DEC-COM-147）。
- 理由: 設定ファイルは、問い合わせのときに見せたり、移動プロファイルで別の PC に運ばれたりする。秘密は端末ごとの場所に分ける。
- 決めた場面: PR #19。API キーの置き場所は Claude API に対応した PR で変えた
- 関係する要件: REQ-COM-010, REQ-COM-021
- 対象: Windows
- 実装の場所: `windows/Hanasu.Core/Settings/SettingsStore.cs`、`windows/Hanasu.Core/Settings/SecretStore.cs`

### DEC-COM-104 Windows 標準のエンジンは、Windows の既定のマイクを使う
- 決めたこと: Windows 標準（`Windows.Media.SpeechRecognition` の連続認識）を選んだときは、Windows の既定のマイクを使い、設定画面でマイクの選択を無効にする（そう書く）。マイクの選択は Whisper / Gemini で使う。オンライン音声認識がオフ・日本語の音声認識がない・マイクが許可されていないときは、HUD に理由と直し方を出し、該当の設定ページ（`ms-settings:`）を開く。
- 理由: この API は録音デバイスを受け取れない。
- 決めた場面: PR #19
- 関係する要件: REQ-COM-001, REQ-COM-002
- 対象: Windows
- 実装の場所: `windows/Hanasu.Windows/Services/WindowsSpeechTranscriber.cs`

### DEC-COM-105 Windows 版の Whisper は Whisper.net で動かし、既定は small
- 決めたこと: Whisper.net（whisper.cpp）で動かす。モデルは tiny〜large-v3-turbo（q5_0 を含む）から選び、既定は small。設定でモデルを選んだ時点で `%LOCALAPPDATA%\Hanasu\Models` にダウンロードする（進み具合・取り消し・削除あり）。無音（約 -46 dBFS 未満）なら Whisper / Gemini に送らず、決まり文句の段は捨てる。
- 理由: Whisper.net は Mac でも動くので CLI で確かめられた。tiny は日本語の精度が低かった。Whisper は無音に「ご視聴ありがとうございました」と書く。
- 決めた場面: PR #19
- 関係する要件: REQ-COM-001, REQ-COM-003
- 対象: Windows
- 実装の場所: `windows/Hanasu.Whisper/WhisperBatchTranscriber.cs`、`windows/Hanasu.Core/Transcription/WhisperModels.cs`

### DEC-COM-106 Windows 版の Gemini での文字起こし
- 決めたこと: 録った音声を WAV にして inline data で送り、文字起こしだけをさせる（指示は `GeminiPrompts.TranscriptionInstruction` に新しく書いた。整形は次の呼び出しで行うので「聞こえたとおり」に書き起こさせる）。音声入力では 1 回 7 分まで。タイムアウトは、整形・英訳が 15 秒（Mac 版と同じ）、音声の文字起こしが 60 秒。設定画面に「音声が Google に送られる」と書く。
- 理由: inline data の上限に収める。文字起こしと整形を分けるのは Mac 版と同じ理由（DEC-COM-031）。
- 決めた場面: PR #19
- 関係する要件: REQ-COM-001
- 対象: Windows
- 実装の場所: `windows/Hanasu.Core/Transcription/Transcribers.cs`、`windows/Hanasu.Core/Gemini/GeminiPrompts.cs`

### DEC-COM-107 Windows 版は、Mac 版の一部の機能を持たない
- 決めたこと: Windows 版には、アプリ別の文体・スニペット・画面の文脈・履歴ウインドウ・最後の結果の再入力・選択を声で編集・辞書の候補の提案・会議の字幕・マイク側の話者分離・会議の自動検出・会議の横断検索と質問・議事録のファイル保存・Slack 向けのコピー・リマインダーへの登録がない（REQ-DIC-020〜071 の一部、REQ-MTG-009・014〜016・019 は「対象: Mac」のまま）。一覧は [windows/README.md](../../windows/README.md) の「Mac 版との差」。
- 理由: PR #19 の範囲を、音声入力（第 1 段階）と会議の記録（第 2 段階）の中心にした。足すかどうかは [roadmap.md](../roadmap.md) FUT-003。
- 決めた場面: PR #19
- 関係する要件: REQ-COM-010, REQ-COM-011
- 対象: Windows
- 実装の場所: なし（作っていない）

### DEC-COM-140 Windows 版の AI の選択は、音声入力と会議で 1 つずつ。設定画面の「Gemini」タブを「AI」タブにする
- 決めたこと: 設定に `DictationAi`（整形・英訳）と `MeetingAi`（議事録・作り直し）を持ち、どちらも既定は Gemini（今までどおり）。モデルは AI ごとに別に持つ（Gemini は今の `model` と `meetingMinutesModel`、Claude は `claudeModel` と `claudeMinutesModel`）ので、AI を切り替えても前に選んだモデルが残る。設定画面の「Gemini」タブを「AI」タブにして、上に「使う AI とモデル」の 2 行（音声入力・会議）、下に Gemini の認証・Claude の API キー・キーの保護・試すを並べる。会議タブの「議事録のモデル」は AI タブへ移した。英訳は AI でしかできないので、「AI で整形する」をオフにしても英訳は音声入力の AI に送る（今までどおり）。Gemini での文字起こし（エンジンが Gemini のとき）は、AI の選択にかかわらず Gemini の認証と音声入力の Gemini のモデルを使う。
- 理由: ユーザーの指示（REQ-COM-024）。音声入力は速さ、議事録は質を優先したいので、用途ごとに選べるほうがよい。認証は AI ごとに 1 つで足りるので、用途ごとには持たない。
- 決めた場面: Claude API に対応した PR
- 関係する要件: REQ-COM-020, REQ-COM-024
- 対象: Windows
- 実装の場所: `windows/Hanasu.Core/Ai/TextAiFactory.cs`、`windows/Hanasu.Windows/Views/SettingsWindow.xaml`

### DEC-COM-141 Windows 版の Claude は公式の C# SDK で呼び、Sonnet 5.5・Opus 5.5 はサーバー側の fallbacks を使う
- 決めたこと: NuGet の `Anthropic`（13.4.0。API の版 `2026-10-21` を送る最初の系列）を使い、REST は直接書かない。送り先は `https://api.anthropic.com` に固定し、API キーは明示して渡す（SDK が環境変数 `ANTHROPIC_API_KEY`・`ANTHROPIC_AUTH_TOKEN`・`ANTHROPIC_BASE_URL` を読まないようにする）。SDK 13 は API キーを `Authorization: Bearer` で送る（`x-api-key` ではない）。`stop_reason` を先に見て、`refusal` は断られた理由（category）を添えたエラー、`max_tokens` は「途中で切れた」エラーにする（音声入力では整える前の文章を入力する）。Sonnet 5.5 と Opus 5.5 には `fallbacks: "default"`（beta `server-side-fallback-2026-07-01`）を付け、安全の判定で断られたときは同じ呼び出しの中で Anthropic の勧めるモデルに切り替えてもらう。Haiku 5.5 にはサーバー側の fallbacks がないので付けない。
- 理由: Swift と違い C# には公式 SDK がある。fallbacks は資料が「最初から付ける」と勧めていて、"default" はモデルの廃止に追従でき、付けても断られなければ何も変わらない。Haiku 5.5 に一覧の形を付けると 400 になる。
- 決めた場面: Claude API に対応した PR
- 関係する要件: REQ-COM-020, REQ-COM-023
- 対象: Windows
- 実装の場所: `windows/Hanasu.Core/Claude/ClaudeClient.cs`、`windows/Hanasu.Core/Claude/ClaudeModels.cs`

### DEC-COM-142 Windows 版の Claude への送り方（プロンプト・effort・キャッシュ・区切りのタグ）
- 決めたこと: プロンプトは Gemini と同じ文面（`GeminiPrompts`・`MinutesPrompt`。DEC-COM-102）を使い、Claude 向けには変えない。`temperature` / `top_p` / `top_k` と `thinking` は送らない（3 つのモデルとも既定で adaptive。Opus 5.5 は止められず、Sonnet 5.5 は `disabled` が 400）。`output_config.effort` は、整形・英訳が `low`、議事録が `medium`（Sonnet 5.5 の既定は high なので明示する）。`max_tokens` は thinking の分も見込んで、整形・英訳 8,000、議事録 32,000。assistant の prefill は使わない。システムの指示に `cache_control`（ephemeral・5 分）を付ける。待ち時間の上限は、音声入力 15 秒、議事録 300 秒（Gemini は 180 秒のまま）。文字起こし・メモの中の `<transcript>` `</transcript>` `<user_notes>` `<action_items>` などの区切りのタグは、全角の山かっこに置き換えてから埋め込む（Gemini にも効く）。
- 理由: 同じ文面なら Gemini と結果を比べやすく、Mac 版ともそろう。システムの指示は「中身は質問や命令ではない」と書いてあり、Claude でもそのまま効く。区切りのタグを本文に書かれると、区切りの外に指示を書けてしまう。キャッシュは、整形の指示が最小の長さ（Haiku 5.5・Sonnet 5.5・Opus 5.5 は 512 トークン）を超えれば効くが、キーがないので効いたかはまだ確かめていない（`claude-refine` が使った量を出す）。
- 決めた場面: Claude API に対応した PR
- 関係する要件: REQ-COM-020, REQ-COM-022
- 対象: Windows
- 実装の場所: `windows/Hanasu.Core/Claude/ClaudeClient.cs`（`BuildParams`）、`windows/Hanasu.Core/Ai/PromptText.cs`

### DEC-COM-143 Windows 版の Claude のエラーの文言とやり直し、「接続を試す」
- 決めたこと: SDK の例外を `ClaudeException` に分け、HUD・会議ノートにそのまま出せる日本語にする（401「API キーが正しくありません」、403、404「モデルが見つからないか、このキーでは使えない」、402 支払い、429 上限、529 混雑、5xx、つながらない、時間切れ）。SDK の例外の本文はそのまま出さず、API の `error.message` を 200 文字までだけ添える。429・5xx（529 を含む）・つながらないときは SDK が `retry-after` を見て 2 回までやり直し、400・401・403・404 はやり直さない。「接続を試す」は `GET /v1/models/{モデル}` で確かめる（トークンを使わず、キーとモデルの両方を確かめられる）。入力欄にキーがあれば保存せずにそのキーで試す。
- 理由: 401 をそのまま「エラー」と出すと、キーの入れ間違いだと分からない。SDK のやり直しは指数的に待ち、API の指示（retry-after）も見る。
- 決めた場面: Claude API に対応した PR
- 関係する要件: REQ-COM-020
- 対象: Windows
- 実装の場所: `windows/Hanasu.Core/Claude/ClaudeException.cs`、`windows/Hanasu.Core/Claude/ClaudeClient.cs`（`CheckAsync`）

### DEC-COM-144 Windows 版の API キーは secrets.json に置き、既定は DPAPI、選べば Windows Hello で守る
- 決めたこと: Gemini と Claude の API キーを `%LOCALAPPDATA%\Hanasu\secrets.json` に置く。既定は DPAPI（CurrentUser・キーの種類ごとのエントロピー）。設定で「Windows Hello で守る」を選ぶと、Windows Hello（`KeyCredentialManager`）の鍵で決まった文字列に署名し、その SHA-256 を鍵にして AES-256-GCM で暗号化する。Windows Hello の確認は、起動してから最初に使うとき 1 回で、作った鍵は画面のロック・ログオフ・スリープまでメモリに置く。切り替えるときは、2 回署名して同じ鍵が出ることを確かめてから書き換える（出なければ DPAPI のまま）。画面には末尾 4 文字（`hint`）だけを出し、入力欄はマスクして、保存したら空にする。キーは送るたびに secrets.json から読み、クライアントは持ち続けない。PR #19 の settings.json の `protectedApiKey` は、復号せずにそのまま secrets.json に移し（`dpapiLegacy`）、移せたときだけ settings.json から消す。読めない値（別のユーザーで保存した、Windows Hello の鍵が作り直された）は消さずに、入れ直すよう知らせる。
- 理由: 署名もパッケージ化もしていないデスクトップアプリには、Windows がアプリを見分ける印（パッケージの ID）がないので、DPAPI・資格情報マネージャー・TPM の鍵（確認なし）は、どれも同じユーザーのほかのプロセスから確認なしに使える。Windows Hello の鍵だけは、使うたびに本人の確認が要るので、ほかのアプリが黙って読むことを防げる。ただし毎回の確認は音声入力では使いにくいので、ロックまでの 1 回にした。既定を DPAPI にしたのは、Windows Hello を設定していない PC があり、切り替えに確認が要るため。資格情報マネージャーは DPAPI と守れる範囲が同じで、利点がない。
- 決めた場面: Claude API に対応した PR
- 関係する要件: REQ-COM-021
- 対象: Windows
- 実装の場所: `windows/Hanasu.Core/Settings/SecretStore.cs`、`windows/Hanasu.Windows/Services/WindowsSecurity.cs`（`WindowsHelloKey`）、`windows/Hanasu.Core/Settings/SettingsStore.cs`（`SettingsService.MigrateSecrets`）

### DEC-COM-145 Windows 版の API の通信は https だけで、リダイレクトに従わない
- 決めたこと: Gemini・Claude・サービスアカウントのトークンの通信は `SafeHttp.Create`（リダイレクトに従わない HttpClient）で行う。証明書の検証は OS に任せ、外す設定は置かない。サービスアカウントの JSON の `token_uri` が https でなければ使わない。Claude の送り先は固定し、環境変数で変えられないようにする（DEC-COM-141）。
- 理由: Gemini の API キーは独自のヘッダー（`x-goog-api-key`）で送るので、.NET はリダイレクトの先が別のホストでも付けたまま送る（`Authorization` は外す）。署名した JWT は鍵の代わりになるので、平文の HTTP では送らない。
- 決めた場面: Claude API に対応した PR
- 関係する要件: REQ-COM-022
- 対象: Windows
- 実装の場所: `windows/Hanasu.Core/Net/SafeHttp.cs`、`windows/Hanasu.Core/Gemini/ServiceAccount.cs`

### DEC-COM-146 Windows 版のモデルのダウンロードは、決まったホストから取り、大きさと SHA-256 を確かめる
- 決めたこと: Whisper と話者分離のモデルは `huggingface.co` からだけ https で取る（リダイレクト先の CDN は https に限る）。モデルごとにコードに書いた大きさと SHA-256（Hugging Face の LFS の値）と比べ、違えば消して失敗にする。「.download」に書いてから名前を変え、想定より大きいものは書き続けない。ファイル名はコードに書いた固定の名前だけを使う。話者の埋め込みのモデル（3D-Speaker CAM++）は、GitHub のリリースと同じ名前・同じ大きさのファイルを、ハッシュが公開されている Hugging Face の `csukuangfj/speaker-embedding-models` から取る。すでに置いてあるモデルは、大きさだけを確かめる（毎回ハッシュは計算しない）。
- 理由: 取ったファイルを whisper.cpp と ONNX Runtime が読むので、差し替えられると危ない。GitHub のリリースの添付にはハッシュが公開されていない。
- 決めた場面: Claude API に対応した PR
- 関係する要件: REQ-COM-003, REQ-COM-022
- 対象: Windows
- 実装の場所: `windows/Hanasu.Core/Net/ModelDownload.cs`、`windows/Hanasu.Core/Transcription/WhisperModels.cs`、`windows/Hanasu.Diarization/SherpaSpeakerDiarizer.cs`

### DEC-COM-147 Windows 版のログは、API キーに見える文字列を伏せてから書く
- 決めたこと: `AppLog.Write` は `SecretRedactor.Redact` を通してから書く（`sk-ant-…`・`AIza…`・`ya29.…`・Bearer と `x-api-key` の値を `***` にする）。CLI のエラーも同じ。`ClaudeException` の文言には SDK の例外の本文を入れない（DEC-COM-143）。
- 理由: キーをログに出さない作りにしてあるが、例外の文言など思わぬ経路で混ざっても残らないようにする。
- 決めた場面: Claude API に対応した PR
- 関係する要件: REQ-COM-021, REQ-COM-022
- 対象: Windows
- 実装の場所: `windows/Hanasu.Core/Ai/SecretRedactor.cs`、`windows/Hanasu.Windows/Services/SmallServices.cs`（`AppLog`）

### DEC-COM-148 Windows 版は、起動の最初に DLL を探す場所を絞る
- 決めたこと: `App` の静的コンストラクターで `SetDllDirectory("")` と `SetDefaultDllDirectories`（exe のフォルダ・System32・`AddDllDirectory` で足したフォルダ）を呼び、作業フォルダと PATH を DLL の探索から外す。Whisper のネイティブライブラリのフォルダ（`runtimes/win-*/`）は `AddDllDirectory` で足す。Hanasu 自身の P/Invoke（user32 / kernel32 / advapi32）は `DefaultDllImportSearchPaths(System32)` で System32 からだけ読む。`onnxruntime.dll` と `sherpa-onnx-c-api.dll` は今までどおり exe の隣に置く（exe のフォルダは System32 より先に探されるので、Windows 11 の System32 の別の版と取り違えない）。
- 理由: 作業フォルダや PATH にある同じ名前の DLL を読み込むと、ほかのプログラムのコードが Hanasu の中で動く。exe が起動するときに読む DLL（静的なインポート）には効かないので、zip を「ダウンロード」フォルダの直下で展開しないよう README に書く。
- 決めた場面: Claude API に対応した PR
- 関係する要件: REQ-COM-022
- 対象: Windows
- 実装の場所: `windows/Hanasu.Windows/Services/WindowsSecurity.cs`（`HardenDllSearch`）、`windows/Hanasu.Windows/Native/NativeMethods.cs`

### DEC-COM-149 Windows 版は、Hanasu より権限の高いウインドウには貼り付けを送らない
- 決めたこと: Ctrl+V を送る前に、前面のウインドウのプロセスの整合性レベルを調べ、Hanasu より高い（管理者として実行など）か調べられなければ、送らずにクリップボードに残して「Ctrl+V で貼り付けて」と知らせる。クリップボードに置く文章には、履歴（Win+V）・クラウドのクリップボード・監視アプリに残さない印（`ExcludeClipboardContentFromMonitorProcessing`・`CanIncludeInClipboardHistory`=0・`CanUploadToCloudClipboard`=0）を付ける（PR #19 から付いていることを確かめた）。メニューの「最近の結果」と会議の「Markdown をコピー」は、ユーザーが自分でコピーする操作なので印を付けない。Hanasu は管理者権限を求めず（`asInvoker`）、`uiAccess` も使わない。
- 理由: UIPI で届かないキーを SendInput は成功として返すので、送ったつもりで何も入らず、元のクリップボードに戻して文章を失うことがある。
- 決めた場面: Claude API に対応した PR（印は PR #19）
- 関係する要件: REQ-DIC-004, REQ-COM-022
- 対象: Windows
- 実装の場所: `windows/Hanasu.Windows/Services/ClipboardTextInserter.cs`、`windows/Hanasu.Windows/Services/WindowsSecurity.cs`（`IsHigherIntegrity`）

### DEC-COM-150 Windows 版の依存パッケージは lock ファイルで固定し、配布物の SHA-256 を残す
- 決めたこと: すべてのプロジェクトで `packages.lock.json` を使い（`RestorePackagesWithLockFile`）、CI の Restore の段では `--locked-mode`（`CI=true` のとき `RestoreLockedMode`）で、lock と食い違えば失敗させる。publish の段は RID（win-x64）と ILLink を足して restore し直し、lock ファイル（RID なしで作る）と入力が合わないので、locked mode を外す。CI は zip の SHA-256 を `Hanasu-windows-x64.zip.sha256` に書いて artifact に入れる。
- 理由: 同じ版の番号でも中身が差し替わったパッケージや、知らないうちに上がった推移的な依存を取り込まない。配布物は署名していないので、ダウンロードした人がハッシュで確かめられるようにする。
- 決めた場面: Claude API に対応した PR。リリースのワークフローにも同じ扱いを入れたのは、v1.3.1 の Windows 版のビルドが locked mode で失敗したため
- 関係する要件: REQ-COM-022, REQ-REL-005
- 対象: Windows
- 実装の場所: `windows/Directory.Build.props`、`.github/workflows/windows.yml`、`.github/workflows/tagpr.yml`（リリースの Windows 版のビルド）

---

## 廃止

やめた要件・設計判断は、消さずにここへ移す（`- 状態: 廃止（日付・理由・PR）`）。今はない。
