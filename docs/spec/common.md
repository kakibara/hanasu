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

### REQ-COM-004 文字起こしの言語を一覧から選べ、初期値はシステムの言語にする
- 内容: 設定の「一般」→「文字起こし」の「言語」を、入力欄から一覧に変える。一覧は日本語・英語（米国・英国）・中国語（簡体・繁体）・韓国語・フランス語・ドイツ語・スペイン語・イタリア語・ポルトガル語（ブラジル）。初期値は macOS のシステムの言語にする。一覧にない言語（システムの言語や、前の版で保存した言語）は、言語コードが同じ一覧の項目に寄せる（en-JP → en-US、zh-Hans-CN → zh-CN、zh-Hant-TW → zh-TW。ja-JP はそのまま）。言語コードが同じ項目がなければ、そのまま使う。この言語は、AI へのプロンプトの言語にもなる（REQ-COM-061）。
- 受け入れ条件:
  - 初めて起動したとき、言語はシステムの言語になっている（システムが英語なら English）。
  - システムの言語や保存されている言語が一覧になければ、言語コードが同じ項目が選ばれている（en-JP → en-US、zh-Hans-CN → zh-CN、zh-Hant-TW → zh-TW、ja-JP はそのまま）。
  - 一覧から言語を変えると、次の音声入力・会議の記録からその言語で文字起こしされる。
- 出典: ユーザーの依頼（2026-11-04）「音声入力の入力言語を選択できるようにしてください。デフォルトはシステムの言語にしてください」
- 対象: Mac
- 実装の場所: `AppSettings.transcriptionLocaleIdentifiers`、`AppSettings.systemLocaleIdentifier`、`AppSettings.nearestTranscriptionLocale`、`TranscriptionEngineSettingsSection.languageOptions`
- 食い違い（ユーザーの確認待ち）: 言語は音声入力と会議の記録で共有する（従来の設定を一覧にしただけ）。音声入力だけ別の言語にする必要があるかは未確認。
- 確かめ方: 実機で確かめる（設定の一覧で言語を変え、音声入力を試す）

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
  - Mac: [design/security.md](../design/security.md) に、項目ごとの「確かめたこと・直したこと・残る危険」がある。直したもの: AI の通信はリダイレクトに従わずキャッシュを残さない（DEC-COM-044）、サービスアカウントの `token_uri` と Vertex AI のリージョンを確かめる（DEC-COM-053）、会議のフォルダを 0700 にする（DEC-COM-052）、自己署名でも Hardened Runtime を付ける（DEC-COM-051）、文字起こし・メモ・議事録の中の区切りのタグを無害にしてから埋め込む（DEC-COM-054）。
  - Windows: [design/security-windows.md](../design/security-windows.md) に項目ごとの「確かめたこと・直したこと・残る危険」がある。直したもの（モデルのハッシュの確認、リダイレクトでキーを送らない、DLL の探索の場所、権限の高いウインドウに貼らない、区切りのタグの無害化、ログの伏せ字、NuGet の lock ファイル、配布物の SHA-256）は、DEC-COM-142・145〜150 のとおりに動く。加えて、サービスアカウントの `token_uri` を Google の窓口に限ることと、Vertex AI のリージョンの確認（DEC-COM-053）も動く。
- 出典: ユーザーの依頼（2026-11-03「その他セキュリティで気をつけるべきところを調査してその結果を盛り込んで」）。固定する項目に DEC-COM-054（Mac の区切りのタグ）と DEC-COM-053（Windows の `token_uri` とリージョンの確認）を加えたのは、ユーザーの依頼（2026-11-05、PR #65）
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
  - Mac: 設定の「AI」タブの「使う AI とモデル」に「音声入力」と「会議」が並び、それぞれで Gemini / Claude とモデルを選べる（例: 音声入力は Gemini の flash-lite、会議は Claude Sonnet 5.5）。既定は、両方ローカルの Gemma 4 E4B（REQ-COM-030。2026-11-04 の依頼で Gemini から変えた）。以前から使っている人で、AI を選んで保存していない人は、今までどおり Gemini のまま（DEC-COM-068）。辞書の候補探しは会議の設定を使う（DEC-COM-040）。
  - Windows: 設定 → AI の「使う AI とモデル」に「音声入力（整形・英訳）」と「会議（議事録）」の 2 行があり、行ごとに AI とモデルを選べる。既定は今までどおり（どちらも Gemini、モデルは gemini-3.5-flash-lite と gemini-3.8-flash）。Windows 版には選択の編集・会議への質問がないので、音声入力は整形・英訳、会議は議事録（作り直しを含む）に効く。
- 出典: ユーザーの指示（2026-11-03「会議の要約モデルと音声入力モデルは個別に指定できるようにして」）。Mac の既定をローカルの Gemma にしたのは 2026-11-04 の依頼「デフォルトの文字起こしモデルを Google のローカルモデルの Gemma にして」
- 対象: Mac / Windows
- 実装の場所: `TextAIPurpose`、`AppSettings`（`dictationAIProvider`・`meetingAIProvider`・`aiProvider(for:)`・`textModel(for:)`）、`AIChoiceRow`
- Windows の実装: `windows/Hanasu.Core/Ai/TextAiFactory.cs`、`windows/Hanasu.Core/Settings/AppSettings.cs`（`DictationAi` / `MeetingAi`）、`windows/Hanasu.Windows/Views/SettingsWindow.xaml.cs`
- 確かめ方: Mac は `.build/debug/Hanasu --render-ai-settings /tmp/ai.png --claude`（音声入力は Gemini、会議は Claude の見た目）、`--test-ai-defaults`（既定のローカルと、以前から使っている人を Gemini のままにする引き継ぎ）
  - Windows は `cd windows && dotnet test Hanasu.Core.Tests`（`TextAiSelectionTests`）

### REQ-COM-030 整形と議事録に使う AI として、端末の中で動く小型の LLM（Gemma 4 E4B・LFM2.5-1.2B-JP・Sarashina2.2・Qwen3.5-4B）を選べ、Gemma 4 E4B を勧める
- 内容: 文字起こしのあとの整形などと、議事録などの文章の処理に使う AI として、Gemini・Claude のほかに、端末の中で動く小型の LLM（ローカル）を選べる。モデルは Gemma 4 E4B・LFM2.5-1.2B-JP・Sarashina2.2・Qwen3.5-4B の 4 つから選ぶ。おすすめは Gemma 4 E4B（Google）で、選ぶ欄に「おすすめ」と出し、初めてローカルにしたときの既定にする（DEC-COM-067）。文章は端末の外に送らない。
- 受け入れ条件:
  - Mac: 設定の「AI」タブで、音声入力か会議の AI を「ローカル」にし、モデルを 4 つから選べる。Gemma 4 E4B に「おすすめ」と出る。選んだモデルがまだなければ、その場でダウンロードでき、進み具合が出る。ダウンロードしたモデルは消せる。ローカルにすると、その用途の処理（音声入力: 整形・英訳・選択の編集、会議: 議事録・会議への質問・辞書の候補）がそのモデルで行われ、文章をネットに送らない。音声入力の整形・英訳と議事録の作成（作り直しを含む）・音声入力の履歴のやり直しでは、モデルがないとダウンロードするかを尋ねる（REQ-COM-032）。そのほかの処理（選択の編集・会議への質問・辞書の候補）でモデルがないまま使おうとすると、設定でダウンロードするよう知らせる。
  - Mac: 文脈に入らない長い会議でも議事録ができる（DEC-COM-065）。
  - Windows: 設定 → AI で「音声入力」か「会議」の AI を「ローカル」にし、モデルを 4 つから選べる。Gemma 4 E4B に「おすすめ」と出る。ダウンロード・削除・進み具合は Mac と同じ。整形・英訳・議事録（作り直しを含む）がそのモデルで行われる。
  - モデルのライセンス（とくに LFM2.5 の、年間売上 1,000 万ドル以上の組織の商用利用を許さない条件）が、選ぶ画面に出る（DEC-COM-066）。
- 出典: ユーザーの依頼（2026-11-04「文字起こし後の整形や議事録作成のモデルとしても小型の local LLM をつかえるようにしてください。Gemma 4 E4B, LFM2.5-1.2B-JP, Sarashina2.2 を選択できるようにして」）。2026-11-04「ローカルモデルに Qwen の一番軽いモデルも追加して。Google の Gemma をレコメンドして。Sarashina などは良くなかった」。同じ日に、Qwen の小さいモデルの能力を調べた結果を見て「4B に替えて試して」（いちばん軽い 0.8B は、指示に従う力・多言語の知識が足りないため）
- 対象: Mac / Windows
- 実装の場所: `LocalLLMModel`、`LocalLLMStore`、`LocalLLMServer`、`LocalLLMClient`、`TextAIClient`（`.local`）、`AIChoiceRow`
- Windows の実装: `windows/Hanasu.Core/LocalLlm/`（`LocalLlmModel`・`LocalLlmClient`・`LongInputFitter`・`LocalLlmServer`）、`windows/Hanasu.Core/Ai/TextAiFactory.cs`、`windows/Hanasu.Windows/Views/SettingsWindow.xaml.cs`
- 確かめ方: Mac は `.build/debug/Hanasu --local-llm-list`、`--local-llm-download <id>`、`--refine-text <文> --ai local --model <id>`、`--minutes-from-transcript <文字起こし> --ai local --model <id>`、`--local-llm-test-fit`（長い入力の分け方）、`--render-ai-settings /tmp/ai.png --local`
  - Windows は `cd windows && dotnet test Hanasu.Core.Tests`（`LocalLlmTests`）、`dotnet run --project Hanasu.Cli -- local-refine "<文章>" --model <id> --server <llama-server のパス>`（Mac の llama-server でも動く）

### REQ-COM-031 整形と議事録に使う AI として、Apple の Foundation Models の CLI（fm）を選べる（Mac）
- 内容: 整形などと議事録などの文章の処理に使う AI として、macOS 27 から入っている Apple の Foundation Models の CLI（`fm`）を、ローカルの LLM（REQ-COM-030）と並べて選べる。端末の中のモデル（Apple Intelligence のオンデバイスのモデル）で処理し、文章を端末の外に送らない。
- 受け入れ条件:
  - Mac: 設定の「AI」タブで、音声入力か会議の AI を「Apple」にできる。macOS 27 以上で、Apple が署名した `fm` が見つかるときだけ使え、そうでないときは選んだ欄に理由（「macOS 27 以降で使えます（この Mac は macOS 26.6）」など）が出る。
  - Mac: 「Apple」にすると、その用途の処理（音声入力: 整形・英訳・選択の編集、会議: 議事録・会議への質問・辞書の候補）が `fm` で行われる。使えないまま処理しようとすると、理由を知らせる。
  - Mac: 文脈（8,192 トークン。未確認）に入らない長い会議でも、議事録ができる（DEC-COM-065 の分け方を使う）。
  - Windows には出さない（Windows に `fm` はない）。
- 出典: ユーザーの依頼（2026-11-04「mac os 27で登場したApple Foundation Models CLIも選択肢に加えて」）
- 対象: Mac
- 実装の場所: `AppleFMClient`、`AppleFMAvailability`、`TextAIClient`（`.appleFM`）、`AIChoiceRow`
- 確かめ方: `.build/debug/Hanasu --apple-fm-status`（使えるか・理由）、`HANASU_FM_PATH=<偽の fm> .build/debug/Hanasu --refine-text <文> --ai apple`・`--minutes-from-transcript <文字起こし> --ai apple`（偽の fm で、渡す引数と長い会議の分け方を確かめる）、`--render-ai-settings /tmp/ai.png --apple`。本物の `fm` は macOS 27 の実機で確かめる

### REQ-COM-032 ローカルのモデルがまだないまま整形・議事録を始めたら、ダウンロードするかを尋ね、ダウンロードしたら続けて処理する（Mac）
- 内容: 用途の AI をローカルにしていて、選んだモデル（既定は Gemma 4 E4B）がまだダウンロードされていないまま、実際に整形・英訳や議事録の作成をしようとしたとき、「ローカルのモデルがないのでダウンロードしますか」と尋ねるダイアログを出す。「ダウンロードする」を選ぶと、ダウンロードを始めて進み具合のバーを出し、終わったらそのまま整形（議事録の作成）を続ける。
- 受け入れ条件:
  - 音声入力の AI をローカルにし、モデルがないまま録音を止めると、ダイアログに、モデルの名前と大きさ、終わったら続けて整形（英訳）すること、ダウンロードしないときにどうなるか（整形前の文章を入力する）が出る。
  - 「ダウンロードする」を押すと、進み具合のバー（割合とダウンロードした大きさ）と「中止」のボタンを出した小さなウインドウが出る。ダウンロードが終わるとウインドウが閉じ、録音を始めたときのアプリを前に戻して、整形した文章を入力する。
  - 「今回はしない」か「中止」を選ぶと、整形せずに認識結果を入力し、モデルがないことを知らせる（今までどおり）。ダウンロードに失敗したら、その理由を知らせて整形前の文章を入力する。
  - 会議の記録を止めたとき・議事録を作り直すときも、会議の AI がローカルでモデルがなければ同じダイアログを出し、ダウンロードしたら続けて議事録を作る。ダウンロードしないときは、議事録を作らずに文字起こしを残し、理由を知らせる。音声入力の履歴の「やり直し」でも同じように尋ねる。
  - 設定やオンボーディングで始めたダウンロードの途中なら、尋ねずに進み具合のウインドウを出し、終わるのを待って続ける。
- 出典: ユーザーの依頼（2026-11-04「選択したローカルモデルがダウンロードされてないのに文字起こしモデルとして選択されていたときは、実際に文字起こしして整形するという風になった時に、ローカルモデルがないのでダウンロードしますかというダイアログを出現させて。ダウンロードするという風にしたらダウンロードが始まって、終わったら解析するという風にしてください。ダウンロードは進捗バーを出してください」）
- 対象: Mac（Windows 版は今までどおり、設定でダウンロードするよう知らせる）
- 実装の場所: `LocalModelDownloadPrompt`、`LocalModelDownloadView`、`DictationController.finishDictation`、`MeetingRecorder`（議事録の作成と作り直し）、`DictationHistoryStore.retry`
- 確かめ方: `.build/debug/Hanasu --render-local-model-download /tmp/download.png`（進み具合のウインドウの見た目）。ダイアログ・ダウンロード・続けて整形することは実機で確かめる（`HANASU_MODELS_DIR` を空のフォルダにして起動し、音声入力の AI をローカルにして録音する）

### REQ-COM-040 アイコンを出す場所を、メニューバー / Dock / 両方から選べる（Mac）
- 内容: Moom のように、Hanasu のアイコンを出す場所を「メニューバーだけ」「Dock だけ」「メニューバーと Dock の両方」から設定で選べる。既定は両方（今までの出し方）。
- 受け入れ条件:
  - 設定の「一般」→「アイコンの表示」で選ぶと、アプリを起動し直さずにすぐ切り替わる。次に起動したときも、選んだ出し方で始まる（起動の途中で Dock のアイコンが一瞬出たりしない）。
  - 「メニューバーだけ」: Dock にアイコンが出ず、⌘Tab の一覧にも出ない。メニューバーのアイコンとメニューは今までどおり。
  - 「Dock だけ」: メニューバーにアイコンが出ない。Dock のアイコンを右クリックすると、メニューバーのメニューと同じ操作（録音・英訳・選択を声で編集・会議の記録・会議ノート・最近の結果・履歴・設定）ができる。録音中・会議の記録中は Dock のアイコンに印が付く。
  - どの出し方でも、Finder や Launchpad からもう一度開くと設定画面が前に出る（DEC-COM-009）。
- 出典: ユーザーの依頼（2026-11-04「hanasuはmoomと同様にステータスバーモードと、Dockモード、その両方を設定で選べるようにしてください」）
- 対象: Mac
- 実装の場所: `AppPresence`、`AppPresenceSettings`、`AppPresenceSettingsSection`、`AppDelegate.applyPresence`、`AppDelegate.applicationDockMenu`
- 確かめ方: `.build/debug/Hanasu --render-presence-settings /tmp/presence.png`（設定の欄）。切り替えは実機で確かめる（`.app` を起動して 3 つを順に選び、Dock・メニューバー・⌘Tab・Dock のメニューを見る）

### REQ-COM-050 初回起動時に、整形などに使う既定の AI をその場で選ばせる。おすすめ（既定）は Gemma 4 E4B で、チュートリアルの中で選んでダウンロードする（Mac）
- 内容: Hanasu を初めて起動したとき、オンボーディングの中で、整形・翻訳・議事録などに使う既定の AI を選ばせる。おすすめ（既定）は、この Mac の中で動く Gemma 4 E4B。Gemma はモデルのダウンロードが要るので、黙って最初から選んでおくのではなく、チュートリアルの中でユーザーが Gemma を選び、その場でダウンロードする。ほかの AI（Gemini / Claude / Apple）も選べ、その AI を使う準備（API キー・サービスアカウント）もその画面でできる。選んだ AI は設定に保存する。
- 受け入れ条件:
  - 初回起動で開くオンボーディングに「使う AI を選ぶ」ページがあり、いちばん上（左上）に「おすすめ」の印を付けた Gemma 4 E4B のカード、続いて Gemini・Claude・Apple のカードが、それぞれの特徴（文章をネットに送るか・要る準備）とともに並ぶ。はじめはどれも選ばれておらず、どれかを選ぶまで、そのページから先へ進めない。
  - Gemma を選ぶと、音声入力と会議の両方の AI が「ローカル」の Gemma 4 E4B になり、その場で保存される（設定の「AI」タブを開くと同じ選択になっている）。同じページに、ダウンロードの大きさ・進み具合・中止のボタンが出る。まだダウンロードしていなければ「次へ」は「ダウンロードして次へ」になり、押すとダウンロードを始めて次のページへ進む。ダウンロードは、次のページを見ている間も続く。
  - ほかの AI を選ぶと、音声入力と会議の両方がその AI になり、その AI に要る準備の欄が同じページに出る: Gemini は API キーかサービスアカウント、Claude は API キー、Apple は使えるかどうか。準備はあとからでもよい（設定の「AI」でできる）。
  - 最後のページで、Gemma のダウンロードがまだ終わっていなければ、その進み具合が分かる。
- 出典: ユーザーの依頼（2026-11-04「初回起動時にデフォルトのAIを選択させるようにして」）。同じ日の追加の依頼「デフォルトのモデルはgemmaにしてください。ただし、gemmaはモデルをダウンロードする必要があるので、何も言わずに（Gemma を）最初に選択するのではなく、チュートリアルの中で（Gemma を選択）して、ダウンロードするというプロセスを採用してください」（音声入力で「Gemma」が「現場」と書き起こされていたのを直して引いた）
- 対象: Mac（Windows 版は対象外。FUT-003）
- 実装の場所: `OnboardingAIPage`、`OnboardingAIChoice`、`OnboardingGemmaDownload`、`OnboardingModel.chooseDefaultAI`・`next`、`AISettingsTab` の `ClaudeKeySection`・`GeminiAuthSection`
- 確かめ方: `.build/debug/Hanasu --render-onboarding /tmp/onboarding`（各ページの画像。`--ai local|gemini|claude` で選んだあとの準備の欄、`--downloading` で Gemma のダウンロード中）。初回の表示・保存・ダウンロードは実機で確かめる

### REQ-COM-051 初回起動時に、主な機能と設定の Tips を説明するオンボーディングを出す（Mac）
- 内容: 初めて起動したとき、ページをめくって進むオンボーディングのウインドウを出し、主な機能（音声入力・翻訳して入力・選択を声で編集・最後の結果の再入力・会議の記録・履歴・辞書・スニペット・アプリ別の文体）の使い方と、設定の Tips（AI とモデルを選べる、マイクを選べる、文字起こしのエンジンを選べる など）を見せる。Tips のうち AI とモデルは、その画面の中で選べる。2 回目以降の起動では出さない。
- 受け入れ条件:
  - 初回起動でオンボーディングのウインドウが前面に出る。「次へ」「戻る」でページを移り、今のページが分かる印がある。最後のページの「はじめる」かウインドウを閉じると終わり、次からの起動では出ない。
  - 機能の説明には、今の設定のショートカット（音声入力・翻訳・選択を声で編集・会議の記録・「ここ重要」・最後の結果の再入力）を出す。
  - 「設定の Tips」のページで、音声入力と会議のそれぞれの AI とモデルを選べ、選ぶとその場で設定に保存される。ほかの Tips には、設定のどのタブのどこで変えるかを書く。
  - 最後のページで、自動入力に要るアクセシビリティと、録音に要るマイク・音声認識の許可の状態を見られ、その場で許可を求められる。
  - メニューから、いつでももう一度開ける（DEC-COM-091）。
- 出典: ユーザーの依頼（2026-11-04「チュートリアルを作成して、アプリのオンボーディングを実施するようにして。主だった機能の説明と、設定のTips(AIモデルが選択できる(その場で選択させる)、など)」）
- 対象: Mac（Windows 版は対象外。FUT-003）
- 実装の場所: `OnboardingView`、`OnboardingPage`、`OnboardingModel`、`OnboardingState`、`OnboardingWindowController`、`AppDelegate.applicationDidFinishLaunching`・`openOnboarding`
- 確かめ方: `.build/debug/Hanasu --render-onboarding /tmp/onboarding`（全ページを PNG にする）。初回だけ出ることとメニューから開けることは実機で確かめる

### REQ-COM-060 表示の言語を、システムの言語に合わせて切り替える（17 言語）
- 内容: メニュー・設定・HUD・ウインドウ・通知・エラーの文言・オンボーディング・権限を求めるときの説明など、利用者に見える文字列を、システムの言語（優先する言語の並びのうち、対応している最初の言語）で出す。対応言語は REQ-COM-061 と同じ 17 言語で、どれにも対応していなければ英語。表示の言語と AI へのプロンプトの言語（文字起こしの言語。REQ-COM-061）は別に決まる。開発用の CLI の出力とログは訳さない。
- 受け入れ条件:
  - システムの言語が日本語なら、今までと同じ日本語で出る。
  - システムの言語を英語（ほかの対応言語）にするか、`-AppleLanguages "(en)"` を付けて起動すると、メニュー・設定・HUD・オンボーディングがその言語で出る。
  - 対応していない言語（例: スウェーデン語）だけのときは英語で出る。
  - マイク・音声認識・画面の音声・リマインダーの許可を求める説明も、その言語で出る。
- 出典: ユーザーの依頼（2026-11-05）「アプリの表示言語とプロンプトの言語もシステムの言語に合わせて変更されるようにして」。開発用の CLI とログを訳さないことは、同日にユーザーに確かめた
- 対象: Mac
- 実装の場所: `UILanguage`、`tr`、`L10n`（`Sources/Hanasu/L10n.swift`）、`Sources/Hanasu/Resources/Localizable.xcstrings`、`scripts/i18n-strings.py`（`infoplist`）
- 確かめ方: `.build/debug/Hanasu --render-onboarding /tmp/onboarding --ui-language en`（画面を PNG にする CLI は `--ui-language <言語>` で言語を変えられる）、`python3 scripts/check-i18n.py`。システムの言語での切り替えは実機で確かめる（`open -a build/Hanasu.app --args -AppleLanguages "(en)"`）

### REQ-COM-061 AI へのプロンプトの言語を、文字起こしの言語に合わせて切り替える（17 言語）
- 内容: 整形・翻訳・選択を声で編集・Gemini での文字起こし・議事録・会議への質問・会議中の AI チャット（よく使う質問を含む）・辞書の候補で AI に送る指示（システムプロンプトと、user content の見出しや注記）を、設定の文字起こしの言語（REQ-COM-004。初期値はシステムの言語）に合わせた言語で送る。対応言語は README と同じ 17 言語（英語・日本語・中国語（簡体字・繁体字）・韓国語・スペイン語・フランス語・ドイツ語・イタリア語・ポルトガル語（ブラジル）・ロシア語・トルコ語・ベトナム語・インドネシア語・ポーランド語・アラビア語・ヒンディー語）で、どれでもなければ英語にする。日本語向けの整形のルール（フィラー・言い直し・口頭の記号の指示・誤変換の直し方・文体のプリセット）は、言語ごとに、その言語の話し言葉に合わせて書き直す。議事録の見出し・話者のラベル・アクションアイテムの「担当」「期限」も、その言語で書く。
- 受け入れ条件:
  - 文字起こしの言語が日本語のとき、送るプロンプトは今までと一字一句同じ（`--show-prompts` の出力が変わらない）。
  - 文字起こしの言語を英語（ほかの対応言語）にすると、整形・翻訳・議事録などのプロンプトがその言語になり、議事録の見出しと話者のラベル（「Me」「Speaker 1」など）もその言語で出る。
  - 対応していない言語（例: スウェーデン語）では英語のプロンプトになる。
  - Mac と Windows で同じ文面を送る。
  - 前の言語で作った議事録（見出し・「担当」「期限」・「なし」）も、書き出し・リマインダー・話者名の推定で読める。
- 出典: ユーザーの依頼（2026-11-05）「アプリの表示言語とプロンプトの言語もシステムの言語に合わせて変更されるようにして。今後の機能追加の際も全ての言語に対応させるようにして」。切り替えの基準を文字起こしの言語にすること、日本語向けのルールは言語ごとに書き直すこと、日本語の文面は変えないことは、同日にユーザーに確かめた
- 対象: Mac / Windows
- 実装の場所: `PromptLanguage`、`Prompts`（`Sources/Hanasu/Prompts.swift`）、`Sources/Hanasu/Resources/Prompts/<言語>.json`、`Meeting.promptName`
- Windows の実装: `windows/Hanasu.Core/Ai/Prompts.cs`（同じ JSON を埋め込んで読む）
- 確かめ方: `.build/debug/Hanasu --show-prompts --prompt-language en`（すべてのプロンプトを見本の入力で表示する。`ja` なら今までと同じ）、`python3 scripts/check-i18n.py`、Windows: `cd windows && dotnet test Hanasu.Core.Tests --filter "FullyQualifiedName~Prompt"`

### REQ-COM-062 UI の文字列とプロンプトを足すときは、すべての対応言語に訳を入れる
- 内容: 新しい機能で UI の文字列か AI へのプロンプトを足すときは、同じ変更の中で 17 言語すべての訳を入れる。訳の漏れはスクリプトで見つけ、CI で落とす。訳を入れる手順はスキル（`.claude/skills/i18n/SKILL.md`）、訳を担当するエージェントは `.claude/agents/i18n.md` に置く。
- 受け入れ条件:
  - プロンプトのキーが 1 つの言語にしかない・埋める場所（`${…}`）やタグが言語で食い違う・話者のラベルが指示の中のものと違う、といったときに `python3 scripts/check-i18n.py` が失敗し、PR の CI（`.github/workflows/spec.yml`）も失敗する。
  - CLAUDE.md と docs/README.md に、この決まりが書いてある。
- 出典: ユーザーの依頼（2026-11-05）「今後の機能追加の際も全ての言語に対応させるようにして。多言語担当は専用の skill と agent を用意しておくと良さそう」
- 対象: Mac / Windows
- 実装の場所: `scripts/check-i18n.py`、`scripts/i18n-strings.py`、`.github/workflows/spec.yml`、`.claude/skills/i18n/SKILL.md`、`.claude/agents/i18n.md`
- 確かめ方: `python3 scripts/check-i18n.py`（UI の文字列では、tr() で包んでいない日本語の文字列と、訳のないキーも見つける）

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

### DEC-COM-008 メニューバーに常駐し、既定では Dock にも出す
- 決めたこと: メニューバーにアイコンを置いて常駐する。Dock には、既定では出す（`Info.plist` に `LSUIElement` を置かず、起動時に `NSApp.setActivationPolicy` で決める）。出す場所は設定で変えられる（REQ-COM-040、DEC-COM-080）。対象は macOS 26 (Tahoe) 以降の Apple Silicon。
- 理由: どのアプリの上でも使う道具なので、ウインドウを持たずに待つ。SpeechAnalyzer が macOS 26 の API。初版の文書は「`LSUIElement = true` で Dock に出さない」だったが、コードは初版から `.regular` で Dock にも出し、Dock のメニュー（`applicationDockMenu`）も持っていた。REQ-COM-040 の既定（両方）で、その出し方を引き継いだ。
- 決めた場面: 初版（a787da8）。文書とコードの食い違いを直し、出す場所を選べるようにしたのはこの PR（REQ-COM-040）
- 関係する要件: REQ-DIC-001, REQ-COM-040
- 対象: Mac
- 実装の場所: `main.swift`（起動時の `setActivationPolicy`）、`AppDelegate.applicationDidFinishLaunching`

### DEC-COM-009 起動のたびに設定画面を開き、アクセシビリティの許可を求める
- 決めたこと: 起動したら設定画面を開き、⌘V の送信に要るアクセシビリティの許可を求める。Dock や Finder でアイコンを開いたときも設定画面を前に出す。ただし、オンボーディングを出す初回の起動では、どちらもせずにオンボーディングを出す（DEC-COM-093）。
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

### DEC-COM-016 画面に出ていない表示は、時間で動く部品（経過時間・点滅・スピナー）を描かない
- 決めたこと: 隠したパネルと、閉じても残るウインドウの中で、時間で描き直す部品を動かさない。
  - 音声入力の HUD（`HUDController`）: 出している間だけ中身を描く（`HUDModel.isShown`）。隠したら中身を外す。一度も出していない HUD も描かない。
  - 会議の提案のパネル（`MeetingSuggestionPanel`）: 隠すときに、出していた提案（「記録を止めますか？」の経過時間）も消す。
  - 「★ を取り消す」のボタン（`HighlightUndoButton`）: 0.5 秒ごとの時計は、記録中だけ動かす。
- 理由: SwiftUI は、`orderOut` したパネルや一度も出していないパネルの中でも、`TimelineView`・`symbolEffect(.pulse)`・不定の `ProgressView` を動かし続ける。
  - HUD の初期の状態は「録音中」なので、選択を声で編集する HUD（一度も使っていなければ出したことがない）が、起動してからずっと経過時間と点滅を描いていた。
  - 使っていない間も CPU を約 8% 使っていた（2026-11-04 の計測。verification/dictation.md の 17）。
  - ほかの常駐アプリでも同じ問題が報告されている（OpenClip・Kannu など）。対処は、隠すときに中身を空にするか外すこと。
- 決めた場面: このPR（2026-11-04、使っていない間の CPU を抑える依頼）
- 関係する要件: REQ-DIC-002, REQ-MTG-009, REQ-MTG-012
- 対象: Mac
- 実装の場所: `HUDModel.isShown`、`HUDController.hide`、`MeetingSuggestionPanel.hide`、`HighlightUndoButton`

### DEC-COM-017 ウインドウとパネルは、マウスのある画面に開く
- 決めたこと: 複数のディスプレイで、Windows 版の設定・会議ノート・履歴のウインドウは、初めて開くときにマウスのある画面の作業領域の中央に出す（XAML の `CenterScreen` はメインの画面に出すので使わず、ハンドルができた時点で物理ピクセルで置く。作業領域に収める縮め方も、その画面の DPI で行う）。2 回目以降に前に出すときは、前の位置のまま。Mac 版の会議の提案パネル（右上）と字幕（初回の下の中央）も、マウスのある画面に出す。字幕の 2 回目以降は前に置いた位置。Mac 版の設定・会議ノート・履歴は、今までどおり `NSWindow.center()`（macOS の標準）。
- 理由: 音声入力の HUD と貼り付けのパネルは、もともとマウスのある画面に出している（`HUDPanel.position`）。会議の提案は会議アプリを使っている画面、設定・会議・履歴はトレイのアイコンを押した画面にいることが多く、メインの画面に出すとサブの画面で作業している人が見失う。前面のアプリの画面（アクティブウインドウの画面）は、常駐アプリからは取りにくく、マウスの位置のほうが素直。
- 決めた場面: PR #65 の判断事項の対応（2026-11-05 のユーザーの依頼「判断して実装して」）
- 関係する要件: REQ-MTG-009, REQ-MTG-014, REQ-COM-010, REQ-COM-011
- 対象: Mac / Windows
- 実装の場所: `MeetingSuggestionPanel.position`、`MeetingCaptionPanel`（`MeetingNotesViews.swift`）
- Windows の実装: `windows/Hanasu.Windows/Views/WindowFit.cs`（`FitToMouseScreen`。`SettingsWindow` / `MeetingWindow` / `HistoryWindow` のコンストラクタから呼ぶ）

### DEC-COM-018 ショートカットがほかと重なるときは保存せず、どれと重なるかを出す
- 決めたこと: 設定のショートカットの欄で記録したキー（と「初期値に戻す」）が、ほかのショートカット（Mac: 録音の開始／停止・翻訳して入力・選択を声で編集・会議の記録・「ここ重要」の印・最後の結果をもう一度入力。Windows: 音声入力・翻訳して入力・会議の記録・「ここ重要」の印）と同じなら、保存せずに、欄の下に「⌃⌥⌘M は「会議の記録の開始／停止」のショートカットと同じです。別のキーを選んでください。」のように、どれと重なるかを出す。「ここ重要」のショートカットをオフにしていても重なりとして扱う。
- 理由: 同じキーを 2 つの機能に登録すると、どちらが動くか（Mac では登録に失敗してアラートが出るか）が分からない。Windows 版は PR #19 から重なりを弾いていたが、文言が「ほかのショートカット（音声入力・翻訳・会議）と同じです」でどれかが分からず、Mac 版は確かめていなかった。
- 決めた場面: PR #65 の判断事項の対応（2026-11-05）
- 関係する要件: REQ-DIC-001, REQ-DIC-050, REQ-MTG-001, REQ-MTG-012
- 対象: Mac / Windows
- 実装の場所: `ShortcutKind`、`ShortcutRecorder.apply`
- Windows の実装: `windows/Hanasu.Windows/Views/SettingsWindow.xaml.cs`（`ConflictingShortcut`）

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

### DEC-COM-028 Whisper のダウンロードは確認を挟まず、大きさを選ぶ前と途中に見せる
- 決めたこと: Whisper のエンジンかモデルを選んだ時点でダウンロードを始める（REQ-COM-003 のまま。確認のダイアログは入れない）。その代わりに、何がどれだけ落ちてくるかを選ぶ前に見せる。Mac: 文字起こしの欄の説明に「Whisper を選ぶと、モデル（small・約 485 MB）のダウンロードがすぐ始まります」と、今選んでいるモデルの大きさ（`WhisperModel.sizeLabel`。目安の値）を出し、モデルの一覧・「ダウンロード（約 485 MB）」のボタン・進み具合の「40%（約 485 MB）」・削除の確かめにも大きさを出す。Windows: モデルの一覧には大きさが出ていたので（`WhisperModelInfo.SizeLabel`）、説明を「選んだ時点でダウンロードし始める」と直し、「ダウンロード（487 MB）」のボタンと進み具合に大きさを足す。
- 理由: REQ-COM-003 はユーザーの指定（2026-11-03）で「選んだときにダウンロードする」と決まっている。モデルは最大でも 630 MB（Mac）/ 1.6 GB（Windows の large-v3-turbo）で、ローカル LLM（数 GB。REQ-COM-032 では尋ねる）ほど大きくなく、取り消しと削除がすぐそこにある。確認を挟むと要件を変えることになるうえ、設定画面でわざわざ選んだ直後に尋ねるのは手数が増えるだけなので、大きさを先に見せるだけにした。
- 決めた場面: PR #65 の判断事項の対応（2026-11-05）
- 関係する要件: REQ-COM-003
- 対象: Mac / Windows
- 実装の場所: `WhisperModel.approximateBytes`・`sizeLabel`、`TranscriptionEngineSettingsSection`、`WhisperModelRow`
- Windows の実装: `windows/Hanasu.Windows/Views/SettingsWindow.xaml.cs`（`UpdateWhisperControls`）

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
- 決めたこと: 文章の処理に使う AI（Gemini / Claude / ローカル。ローカルは REQ-COM-030）を、「音声入力」（整形・英訳・選択の編集・音声入力の履歴のやり直し）と「会議」（議事録とその作り直し・会議への質問・辞書の候補探し）の 2 つの用途で別々に選ぶ。Mac の既定はどちらもローカルの Gemma 4 E4B（DEC-COM-068。以前から使っている人は Gemini のまま）。Windows の既定はどちらも Gemini。辞書の候補探しは会議の記録を読む長い処理なので、会議の設定（AI とモデル、Gemini なら `meetingMinutesModel`）を使う。文字起こしのエンジン（OS 標準 / Whisper / Gemini）は今までどおり別に選び、Claude には音声を送らない。設定画面は「Gemini」タブを「AI」タブにし、先頭に 2 つの用途を並べる。Gemini の認証の欄は、文字起こしのエンジン「Gemini」でも使うので、AI の選択に関わらず出す。
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
- 決めたこと: 「接続を試す」は、選んでいるモデルの `GET https://api.anthropic.com/v1/models/{model}` を送る。200 なら「接続できました」、401 なら「キーが正しくありません」、404 なら「モデルが見つからないか、このキーでは使えません」。Gemini にも同じボタンを置く（API キー: `GET https://generativelanguage.googleapis.com/v1beta/models/{model}`、サービスアカウント: `GET https://{host}/v1/publishers/google/models/{model}` にアクセストークンを付ける）。400（API_KEY_INVALID）/ 401 / 403 は「API キー（またはサービスアカウント）が正しくないか、Gemini API を使う権限がありません」、404 は「モデルが見つからないか、この認証では使えません」。モデルは、音声入力に Gemini を選んでいればそのモデル、そうでなければ会議のモデル。やり直しはしない。
- 理由: トークンを使わずに、キーの正しさとモデルを使えることを確かめられる。Gemini は Claude より先からあったのに「接続を試す」がなく、キーの入れ間違いに録音のあとで気づいていた（PR #65 のレビュー）。サービスアカウントでも、トークンが取れること（鍵の形・時刻・権限）をその場で確かめられる。
- 決めた場面: Claude API に対応した PR。Gemini は PR #65 の判断事項の対応（2026-11-05）
- 関係する要件: REQ-COM-020, REQ-DIC-003
- 対象: Mac
- 実装の場所: `ClaudeClient.testConnection`、`ClaudeKeySection.testConnection`、`GeminiClient.testConnection`、`GeminiAuthSection.testConnection`

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
- 決めたこと: 鍵ファイルの `token_uri` が `https://oauth2.googleapis.com`（古い鍵の `https://accounts.google.com`）でなければ、署名した JWT を送らない。Vertex AI のリージョンは英小文字・数字・ハイフンだけ（40 文字まで）を受け付ける（ホスト名に入るため）。Windows 版も、リージョンは同じ形だけを、`token_uri` は同じ Google の窓口（`oauth2.googleapis.com`・`accounts.google.com`、https、ポートとユーザー情報なし）だけを受け付ける。
- 理由: 鍵ファイルや設定（UserDefaults・settings.json）を書き換えられると、署名した JWT やアクセストークンを別のホストに送らされうる。リージョンはホスト名の一部になるので、確かめないと `evil.example/#` のような値で送り先そのものを変えられる。
- 決めた場面: この PR（セキュリティの調査）。Windows のリージョンの確認はセキュリティの見直し（2026-11-05）。Windows の `token_uri` を Google の窓口に限ったのはユーザーの依頼（2026-11-05、PR #65。それまでは https の確認だけで、テストが偽の窓口を使うために緩めていた。テストは `Parse` のあとで窓口を差し替える）
- 関係する要件: REQ-COM-022
- 対象: Mac / Windows
- 実装の場所: `ServiceAccountTokenProvider.isTrustedTokenURL`、`GeminiClient.isValidLocation`
- Windows の実装: `windows/Hanasu.Core/Gemini/GeminiClient.cs`（`IsValidLocation`）、`windows/Hanasu.Core/Gemini/ServiceAccount.cs`（`Parse`・`IsTrustedTokenUri`）

### DEC-COM-054 Mac 版も、文字起こし・メモ・議事録の中の区切りのタグを無害にしてから埋め込む
- 決めたこと: プロンプトの区切りに使うタグ（`<transcript>` `<transcript_excerpts>` `<user_notes>` `<action_items>` `<speaker_names>` と、会議への質問の `<meeting>` `<minutes>` `<question>`）が、埋め込むユーザー由来の文章（音声入力の認識結果、会議の文字起こし、本人のメモ、会議への質問に渡す議事録と文字起こし）に含まれていたら、全角の山かっこ（`＜/transcript＞`）に置き換えてから埋め込む。閉じタグ・空白入り・大文字・属性つきも拾う。選択を声で編集するモードは、毎回変わる名前のタグ（DEC-DIC-033）のままにする。画面の文脈は `<` をすべて全角にする（DEC-DIC-065）のままにする。
- 理由: Windows 版の DEC-COM-142 と同じ。区切りのタグを本文に書かれると、区切りの外（指示の側）に文を置けてしまう。ローカルの LLM の `LongInputFitter` も `<transcript>` が 1 つずつあることを前提に分けるので、本文に同じタグがあると分けられず、後ろを省く動きになっていた。Windows 版より対象のタグが多いのは、会議への質問（`MeetingAsk`）が Mac だけにあるため。出力は入力欄に貼るか会議ノートに書くだけで、Hanasu が命令として実行することはないので、被害は「変な文章が入る」までだが、守りを Windows とそろえる。
- 決めた場面: セキュリティの見直し（2026-11-05）
- 関係する要件: REQ-COM-022, REQ-DIC-003, REQ-MTG-006
- 対象: Mac
- 実装の場所: `PromptText.neutralizeDelimiters`、`GeminiClient.userPrompt`、`MinutesPrompt.userText`、`MeetingAsk.material`、`MeetingChat.prompt`（会議中の AI チャット。PR #68 のあとに足した。`<pending_transcript>` `<conversation>` と会話の役割のタグ `<user>` `<assistant>` も対象）

### DEC-COM-055 Gemini の呼び出しは、429 / 503 と一時的な通信の失敗だけ、時間の予算の中で 2 回までやり直す
- 決めたこと: Gemini の 429 と 503、および一時的な通信の失敗（Mac: 接続が切れた・つながらない・名前が引けない。Windows: `HttpRequestException`）は、0.5 秒・1 秒待って 2 回までやり直す。ここまでにかかった時間と待ちの合計が、タイムアウトの半分を超えるときはやり直さない（15 秒なら 7.5 秒まで）。やり直しの送信のタイムアウトは、残りの時間にする。タイムアウト自体と、400 / 401 / 403 などはやり直さない。
- 理由: 一瞬の混雑（429 / 503）で整形が失敗して、認識結果がそのまま入力されるのを減らす。音声入力は待たされないことが大事（DEC-DIC-010 の 15 秒）なので、全体の予算を超えない。Claude は DEC-COM-046 でやり直していたが、Gemini はやり直さず、Mac と Windows の両方で食い違っていたので、両方にそろえて入れた。
- 決めた場面: ユーザーの依頼（2026-11-05、PR #65）
- 関係する要件: REQ-DIC-007
- 対象: Mac / Windows
- 実装の場所: `GeminiClient.generate`・`retryDelay`・`isTransientNetworkError`
- Windows の実装: `windows/Hanasu.Core/Gemini/GeminiClient.cs`（`GenerateAsync`・`RetryDelay`・`MaxRetries`・`RetryBaseDelay`）

### DEC-COM-060 ローカルの LLM は、llama.cpp の llama-server を同梱し、使うときだけ子プロセスで動かす
- 決めたこと: Mac・Windows とも、llama.cpp の `llama-server` をアプリに同梱し、ローカルを選んだ処理を始めるときに子プロセスとして起動して、OpenAI 互換の `POST /v1/chat/completions` に送る（streaming は使わない）。チャットの形式は GGUF に入っているテンプレートを llama.cpp の jinja で使う（`--jinja`）。Gemma 4 の考える過程は使わない（`--reasoning off`）。Mac は Metal に全部の層を載せる（`-ngl 99`）。Windows は CPU で動かす。
- 理由: 3 つのモデルのチャットの形式がばらばら（Gemma 4 は `<|turn>`、LFM2.5 は ChatML 風、Sarashina2.2 は `<|system|>…</s>`）で、llama.cpp の C API の組み込みのテンプレートには Gemma 4 と Sarashina がない。llama-server なら GGUF のテンプレートをそのまま使える。Mac と Windows で同じ作りにでき、クライアントは Gemini・Claude と同じ 1 回送って待つ HTTP にできる。MLX（mlx-swift-lm）は `swift build` で Metal のシェーダーを作れず、Windows の LLamaSharp は中の llama.cpp が古くなりがち（0.30.0 で b10221）なので採らなかった。
- 決めた場面: ローカル LLM に対応した PR
- 関係する要件: REQ-COM-030
- 対象: Mac / Windows
- 実装の場所: `LocalLLMServer`、`LocalLLMClient`
- Windows の実装: `windows/Hanasu.Core/LocalLlm/LocalLlmServer.cs`、`windows/Hanasu.Core/LocalLlm/LocalLlmClient.cs`

### DEC-COM-061 llama.cpp は b11770 に固定し、配布物の SHA-256 を確かめてから同梱する
- 決めたこと: llama.cpp の GitHub のリリース b11770（2026-10-21）の `llama-b11770-bin-macos-arm64.tar.gz` と `llama-b11770-bin-win-cpu-x64.zip` を、決めておいた SHA-256 と比べてから展開する（`scripts/fetch-llama-cpp.sh`）。Mac は `llama-server` と、それが読む dylib（`libllama-server-impl`・`libllama`・`libllama-common`・`libmtmd`・`libggml*`。`@loader_path` で読むので同じフォルダに置く）だけを `Hanasu.app/Contents/Resources/llama/` に入れ、本体と同じ証明書・Hardened Runtime で 1 つずつ署名する。自己署名の証明書（Team ID がない）のときだけ、llama-server にライブラリの検証を外す権限（`Resources/llama-server.entitlements` の `com.apple.security.cs.disable-library-validation`）を付ける。Windows は `llama-server.exe` と、それが読む DLL を publish の `llama/` に入れる。llama.cpp のライセンス（MIT）を一緒に入れる。開発中の CLI は、環境変数 `HANASU_LLAMA_SERVER` でサーバーのパスを指定できる。
- 理由: 決まった版・決まった中身だけを配る（DEC-COM-150 と同じ考え）。公開から 2 週間たった版にした（出てすぐの版を避ける）。Gemma 4 に対応した版（b8637 以降）と、公開直後の修正（2026-04）を含む。Mac の Hardened Runtime では、ほかの証明書で署名されたライブラリを読めないので、同梱するものも同じ証明書で署名し直す。ただし自己署名には Team ID がなく、同じ証明書で署名した dylib も「Team ID が違う」として読めなかった（docs/verification/dictation.md の 13）。llama-server は秘密を持たない別のプロセスなので、そのプロセスだけ検証を外す。Apple の証明書（Team ID あり）では外さない。
- 決めた場面: ローカル LLM に対応した PR
- 関係する要件: REQ-COM-030, REQ-REL-005
- 対象: Mac / Windows
- 実装の場所: `scripts/llama-cpp.lock`、`scripts/fetch-llama-cpp.sh`、`scripts/build-app.sh`、`Resources/llama-server.entitlements`、`LocalLLMServer.executableURL`
- Windows の実装: `scripts/fetch-llama-cpp.ps1`、`.github/workflows/tagpr.yml`・`.github/workflows/windows.yml`（publish のあとに `llama/` を入れる）、`windows/Hanasu.Core/LocalLlm/LocalLlmServer.cs`（`ResolveExecutable`）

### DEC-COM-062 4 つのモデルは、版・ファイル・SHA-256 を決めておき、設定から初めにダウンロードする
- 決めたこと: モデルはアプリに入れず、設定の「AI」でダウンロードする。Hugging Face のリポジトリのコミットを決め（`resolve/<コミット>/<ファイル>`）、大きさと SHA-256 を確かめてから置く。
  - Gemma 4 E4B: `ggml-org/gemma-4-E4B-it-GGUF` の `gemma-4-E4B-it-Q4_0.gguf`（4.59 GB、Apache-2.0）
  - LFM2.5-1.2B-JP: `LiquidAI/LFM2.5-1.2B-JP-202606-GGUF` の `LFM2.5-1.2B-JP-202606-Q8_0.gguf`（1.25 GB、LFM Open License v1.0）
  - Sarashina2.2: `mmnga/sarashina2.2-3b-instruct-v0.1-gguf` の `sarashina2.2-3b-instruct-v0.1-Q4_K_M.gguf`（2.07 GB、MIT）
  - Qwen3.5-4B: `unsloth/Qwen3.5-4B-GGUF` の `Qwen3.5-4B-Q4_K_M.gguf`（2.74 GB、Apache-2.0）
  - 置き場所: Mac は `~/Library/Application Support/Hanasu/Models/llm/`、Windows は `%LOCALAPPDATA%\Hanasu\Models\llm\`
- 理由: 4 つで 11 GB あり、使わない人に配らない。差し替えられたファイルを読まない（FUT-011 と同じ考え。Windows は `ModelDownload` の確かめ方をそのまま使う）。Gemma 4 E4B は llama.cpp の開発元が作り直しを追っている ggml-org の Q4_0 にした（Google の QAT 版より小さい）。LFM2.5 は 1.2B と小さいので、質を落とさない Q8_0 にした。Sarashina2.2 は 3 つの大きさのうち日本語の質がいちばんよい 3B（日本語 MT-Bench 6.51）を、4 bit（Q4_K_M、日本語の imatrix 付き）で使う。Qwen3.5 は 4 つの小さい大きさ（0.8B・2B・4B・9B）のうち 4B にした。0.8B は考えない使い方で IFEval 52.1・MMMLU 34.1、2B は 61.2・56.9 と、指示に従う力と多言語の知識が足りず、2B は開発元が「考える過程が止まらなくなりやすい」と注意している。4B は MMMLU 76.1 で Gemma 4 E4B（76.6）と同じくらいで、大きさは半分強。9B は Gemma より重い。llama.cpp の開発元の ggml-org は 4B の GGUF を出していないので、unsloth の Q4_K_M（2026-03-02 の版）を使う（b11770 は Qwen3.5 の形 `qwen35` を読める）。4 つとも Hugging Face で同意の手続き（gated）が要らず、GGUF にチャットのテンプレートが入っている。
- 決めた場面: ローカル LLM に対応した PR
- 関係する要件: REQ-COM-030, REQ-COM-022
- 対象: Mac / Windows
- 実装の場所: `LocalLLMModel`、`LocalLLMStore.download`
- Windows の実装: `windows/Hanasu.Core/LocalLlm/LocalLlmModel.cs`、`windows/Hanasu.Core/Net/ModelDownload.cs`

### DEC-COM-063 サーバーは 127.0.0.1 の空いたポートで、起動のたびに作る API キーを付け、5 分使わなければ止める
- 決めたこと: `--host 127.0.0.1` と、空いているポート（OS に選ばせる）で起動する。起動のたびに乱数の API キーを作り、環境変数 `LLAMA_API_KEY` で渡す（コマンドラインに書かない）。Hanasu の CLI が環境変数で受け取るほかのサービスの秘密（`ANTHROPIC_API_KEY`・`GEMINI_API_KEY`・`GEMINI_SERVICE_ACCOUNT_JSON` など。`secretEnvironmentKeys` の一覧）と `LLAMA_ARG_*` は、子プロセスの環境から外す。モデルの名前は `--alias <モデルの id>` で付ける。Web の画面は出さない（`--no-webui`）。同時に 1 つの処理だけ（`--parallel 1`）。最後の処理から 5 分たつと止め、モデルを変えたら起動し直し、アプリを終えるときに止める。Mac は、前回落ちたときに残ったサーバー（自分が起動した記録のあるもの）を起動時に止める。Windows は、ジョブオブジェクトで Hanasu が終わると一緒に終わるようにする。
- 理由: ほかの端末から使われないよう、外に開かない。同じ端末のほかのプロセスに勝手に使われないよう、キーを付ける。コマンドラインは `ps` でほかのユーザーにも見えるので、キーは環境変数で渡す。llama-server はキーなしでも `/health` と `/models` に応えるので（ブラウザから DNS リバインディングで 127.0.0.1 のポートを叩かれると読める）、`/models` にモデルのファイルのパス（ユーザー名を含む）が出ないよう別名を付ける。llama-server は自己署名の Mac ではライブラリの検証を外したプロセス（DEC-COM-061）なので、要らない秘密を持たせない。モデルは数 GB のメモリを使い続けるので、使っていないときは返す（続けて使うときは読み込み済みで速い）。
- 決めた場面: ローカル LLM に対応した PR。環境変数の整理と `--alias` はセキュリティの見直し（2026-11-05）
- 関係する要件: REQ-COM-030, REQ-COM-022
- 対象: Mac / Windows
- 実装の場所: `LocalLLMServer`
- Windows の実装: `windows/Hanasu.Core/LocalLlm/LocalLlmServer.cs`、`windows/Hanasu.Windows/Services/ChildProcessJob.cs`

### DEC-COM-064 文脈の長さと生成の設定は、モデルごとに決める
- 決めたこと: 文脈の長さ（`-c`）は、Gemma 4 E4B・LFM2.5・Qwen3.5 は 32,768、Sarashina2.2 は 8,192（モデルの上限）。出力の上限は、音声入力（整形・英訳・選択の編集・辞書の候補）は 2,048、会議（議事録・会議への質問）は 4,096 で、どちらも文脈の半分を超えない。サンプリングは開発元の推奨にする（Gemma 4: temperature 1.0・top_p 0.95・top_k 64、LFM2.5: temperature 0.1・top_k 50・repetition_penalty 1.05）。Sarashina2.2 は推奨がないので temperature 0.2・top_p 0.95・repetition_penalty 1.05。Qwen3.5-4B は考えない使い方の推奨（temperature 0.7・top_p 0.8・top_k 20）にし、推奨の presence_penalty 1.5 は付けない。待つ時間は、音声入力は 1 回 120 秒、会議は 1 回 30 分（モデルの読み込みを含む）。
- 理由: Gemma 4 と LFM2.5 は 128K まで（Qwen3.5 は 256K まで）読めるが、KV キャッシュのメモリを抑える（32K で 1 時間ほどの会議の文字起こしが入る）。整形は短い文なので、出力の上限は小さくてよい。端末の CPU・GPU で動くので、Gemini・Claude より長く待つ。presence_penalty は一度出た語を避けさせるので、元の言葉をなるべく残す整形には合わない。
- 決めた場面: ローカル LLM に対応した PR
- 関係する要件: REQ-COM-030
- 対象: Mac / Windows
- 実装の場所: `LocalLLMModel`（`contextLength`・`sampling`）、`LocalLLMClient.maxOutputTokens`
- Windows の実装: `windows/Hanasu.Core/LocalLlm/LocalLlmModel.cs`

### DEC-COM-065 文脈に入らない入力は、文字起こしを部分ごとの要点にまとめてから送り、ほかは後ろを省く
- 決めたこと: 送る前に、システムの指示と入力の長さを llama-server の `/tokenize` で数える。文脈（出力の上限と余白を引いた分）に入らないとき:
  - 入力に `<transcript>` が 1 つだけあるとき（議事録）: 文字起こしを行の切れ目で、入る大きさの部分に分け、部分ごとに「話者・決まったこと・数字・日付・依頼（誰が・何を・いつまで）・★の付いた発言を落とさない要点」を書かせる。要点をつないだものを `<transcript>` の中身の代わりに入れ、元の指示で議事録を作る。つないだ要点もまだ入らなければ、要点をもう一度まとめる（3 回まで）。
  - それ以外（会議への質問・辞書の候補など）: 入る長さまで後ろを省き、「（長いため、以下を省きました）」と書き足す。
- 理由: Sarashina2.2 は 8K しか読めず、1 時間の会議（2〜4 万トークン）は入らない。議事録は全体を見てまとめる必要があるので、省くより要点にまとめる方がよい。会議への質問は、検索で関係の深い会議から順に並べてあるので、後ろを省いても答えに要る部分は残りやすい。
- 決めた場面: ローカル LLM に対応した PR
- 関係する要件: REQ-COM-030
- 対象: Mac / Windows
- 実装の場所: `LocalLLMClient.generate`、`LongInputFitter`
- Windows の実装: `windows/Hanasu.Core/LocalLlm/LongInputFitter.cs`

### DEC-COM-066 モデルのライセンスを、選ぶところに出す
- 決めたこと: 設定でローカルのモデルを選ぶ欄に、モデルごとのライセンス（Apache-2.0・LFM Open License v1.0・MIT）と、ライセンスの文へのリンクを出す。LFM2.5 には「年間売上 1,000 万ドル以上の組織の商用利用は、このライセンスでは許されない」と書く。THIRD_PARTY_NOTICES に llama.cpp と 4 つのモデルを書く（モデルはアプリに入れないので、ダウンロードしたときのライセンスに従う）。
- 理由: LFM Open License v1.0 は、年間売上 1,000 万ドル以上の組織の商用利用を許していない。ダウンロードするのは利用者なので、選ぶときに分かるようにする。
- 決めた場面: ローカル LLM に対応した PR
- 関係する要件: REQ-COM-030, REQ-REL-005
- 対象: Mac / Windows
- 実装の場所: `LocalLLMModel.licenseNote`、`AIChoiceRow`
- Windows の実装: `windows/Hanasu.Core/LocalLlm/LocalLlmModel.cs`、`windows/Hanasu.Windows/Views/SettingsWindow.xaml.cs`

### DEC-COM-067 Gemma 4 E4B を勧め、ローカルを選んだときの既定のモデルは、音声入力・会議とも Gemma 4 E4B
- 決めたこと: Gemma 4 E4B（Google）を「おすすめ」とし、選ぶ欄の名前に「・おすすめ」、説明の頭に「おすすめ。」と出す。用途の AI を初めて「ローカル」にしたときのモデルは、音声入力・会議とも Gemma 4 E4B。前に選んで保存してあるモデルは変えない。Mac では AI の既定もローカルにしたので、新しく使い始めた人は音声入力・会議とも Gemma 4 E4B になる（DEC-COM-068。Windows の AI の既定は Gemini のまま）。Mac のオンボーディングで Gemma を選んだときに、音声入力・会議とも Gemma 4 E4B にするのは DEC-COM-092。
- 理由: 実機で比べると（docs/verification/dictation.md の 13）、LFM2.5 は整形で言い直しを読み違えて言っていない文を足し、議事録では同じ議題を繰り返してアクションアイテムを出せなかった。Sarashina2.2 は議事録で担当者を取り違え、期限を作った。利用者の評価も「Sarashina などは良くなかった」（2026-11-04）。あとから足した Qwen3.5-4B も、整形で言い直しの前の文を残し、議事録でアクションアイテムを 1 件にまとめて期限を落とした（同じく 19）。Gemma 4 E4B だけが整形も議事録も安定していた。整形の待ち時間も 2 回目以降 4 秒ほどで、LFM2.5 の速さを優先するほどの差はない。前は音声入力の既定を、速さを優先して LFM2.5 にしていた。
- 決めた場面: ローカル LLM に対応した PR。おすすめと既定の変更は、Qwen3.5-4B を足した PR
- 関係する要件: REQ-COM-030
- 対象: Mac / Windows
- 実装の場所: `LocalLLMModel.recommended`・`defaultDictation`・`defaultMeeting`、`LocalModelChoice`
- Windows の実装: `windows/Hanasu.Core/LocalLlm/LocalLlmModel.cs`

### DEC-COM-068 Mac の AI の既定は、音声入力・会議ともローカルの Gemma 4 E4B。以前から使っている人は Gemini のままにする
- 決めたこと: `dictationAIProvider`・`meetingAIProvider` の既定（`UserDefaults.register`）を `local` にする（モデルの既定は DEC-COM-067 で Gemma 4 E4B）。ただし、この版に上げた人の AI は変えない: 起動して最初に `AppSettings` を作るとき、印（UserDefaults の `aiProviderDefaultsVersion`）がなければ、Hanasu の設定が 1 つでも保存されている人（以前から使っている人。数え方は DEC-COM-090 と同じで、システムが書くキーは数えない）の、保存していない AI の選択に `gemini` を書く。新しく使い始めた人には何も書かない。どちらも印を書き、次からは見ない。オンボーディングの「以前から使っている人」の判定（DEC-COM-090）は、この印を数えない。
- 理由: ユーザーの依頼（REQ-COM-024 の出典）。既定を変えるだけだと、AI を選ばずに既定の Gemini で使っていた人（オンボーディングを入れる前から使っている人）が、上げた途端にローカルに変わり、4.6 GB のダウンロードを求められる。印を書くのは、新しく使い始めた人がオンボーディングを閉じたあとの 2 回目の起動で、「設定が保存されている人」と取り違えて Gemini を書いてしまわないようにするため。モデルがないまま整形を始めても、ダウンロードするかを尋ねる（REQ-COM-032）ので、黙って失敗することはない。
- 決めた場面: 既定を Gemma にした PR（2026-11-04 の依頼）
- 関係する要件: REQ-COM-024, REQ-COM-030, REQ-COM-032
- 対象: Mac（Windows の既定は Gemini のまま）
- 実装の場所: `AppSettings.init`、`AppSettings.preserveAIProviderForExistingUsers`、`AppSettings.hasSavedSettings`、`OnboardingState`

### DEC-COM-069 モデルがないときの確認は NSAlert で尋ね、進み具合は小さなウインドウに出し、終わったら入力先のアプリを前に戻す
- 決めたこと: 整形などの処理の直前（`TextAIClient` を作る前）に `LocalModelDownloadPrompt.prepare` を呼ぶ。用途の AI がローカルで、モデルがなければ、Hanasu を前に出して NSAlert（「ダウンロードする」「今回はしない」）で尋ねる。ダウンロードは設定と同じ `LocalLLMStore.ensureDownloaded` で行い（大きさと SHA-256 を確かめる。DEC-COM-062）、進み具合は閉じるボタンのない小さなウインドウ（`LocalModelDownloadView`。バー・割合・ダウンロードした大きさ・「中止」。ハッシュを確かめる間は動き続けるバー）に出す。すでにダウンロード中なら尋ねずにウインドウを出す。同じモデルを 2 つの処理が同時に待つときは、尋ねるのを 1 回にする。音声入力では、尋ねる前に前面にあったアプリを覚えておき、ダイアログとウインドウを閉じたら（ダウンロードしなかったときも）そのアプリを前に戻してから整形・入力に進む。ダウンロードしなかったとき・中止したときは今までと同じ「モデルがない」エラーで、失敗したときはその理由のエラーで、呼び出し元が今までどおり整形前の文章を入力する（議事録は作らずに知らせる）。選択の編集・会議への質問・辞書の候補には入れない。
- 理由: 録音を止めたあとに数 GB を黙って取り始めないよう、ユーザーに選ばせる（依頼の「ダウンロードしますかというダイアログ」）。HUD は前面に出ないパネル（入力先のフォーカスを動かさない）でボタンも小さいので、確認と中止にはふつうのダイアログとウインドウを使う。その代わりに前面が Hanasu に移るので、入力先のアプリを前に戻さないと、整形した文章を貼る先がなくなる。選択の編集は、録音の前に選択を読むので、ダイアログで前面が変わると選択の読み取りと置き換えが崩れる。会議への質問と辞書の候補は、設定や会議ノートのウインドウの中の操作で、すぐ横の設定でダウンロードできる。
- 決めた場面: 既定を Gemma にした PR（2026-11-04 の依頼）
- 関係する要件: REQ-COM-032
- 対象: Mac
- 実装の場所: `LocalModelDownloadPrompt`、`LocalModelDownloadView`、`DictationController.finishDictation`、`MeetingRecorder`、`DictationHistoryStore.retry`

### DEC-COM-070 Apple の Foundation Models は、CLI の `fm respond` を 1 回ずつ子プロセスで呼ぶ
- 決めたこと: 処理のたびに `fm respond --instructions <システムの指示> <入力>` を子プロセスで動かし、標準出力の文章を結果にする（Apple の WWDC26 のセッション 334 の使い方）。プロンプトは Gemini・Claude・ローカルと同じものを使う。終了コードが 0 でなければ、標準エラーの最後の数行を添えて知らせる。待つ時間は、音声入力は 1 回 60 秒、会議は 1 回 10 分で、過ぎたら止める。
- 理由: ユーザーの指定が CLI（REQ-COM-031）。Apple の公式の文書で確かめられた使い方は、`fm respond` に入力を引数で渡し、`--instructions` で指示を渡す形だけで、標準入力で渡せるかは確かめられなかった。`fm serve`（OpenAI 互換のサーバー）はコミュニティの文書にしかなく、決まったポート（127.0.0.1:1976）で認証もないとされるので使わない。
- 引数で渡すことの注意: 入力（文字起こし・整えた文章）は、`fm` が動いている数秒〜数分のあいだ、同じ Mac のほかのユーザーにも `ps` で見える。標準入力で渡せると分かったら、そちらに変える。
- 決めた場面: ローカル LLM に対応した PR（Apple の Foundation Models を足した分）
- 関係する要件: REQ-COM-031
- 対象: Mac
- 実装の場所: `AppleFMClient.respond`

### DEC-COM-071 `fm` は macOS 27 以上で、Apple が署名した /usr/bin/fm だけを使う
- 決めたこと: macOS 27 以上で、`/usr/bin/fm` があり、その署名が Apple のもの（コードの要件 `anchor apple`）のときだけ「使える」とする。ほかの場所の `fm`（Homebrew などの同じ名前のもの）は使わない。使えないときは、理由（macOS が 27 より前・見つからない・Apple の署名でない）を設定の欄と知らせに出す。利用条件への同意がまだのとき（`fm` がすべてのコマンドを断る。未確認）は、ターミナルで `sudo fm license` を実行するよう案内する。確認用に、環境変数 `HANASU_FM_PATH` で別の実行ファイルを指定でき、そのときは macOS の版と署名を見ない。
- 理由: 入力の文章を渡すので、同じ名前の別のプログラムに渡さない。`fm` は macOS 27 に初めから入っている（WWDC26 のセッション 334）ので、システムの場所にあるはずだが、場所は Apple の文書で確かめられなかった（未確認。macOS 27 の実機で確かめる）。手元の Mac は macOS 26.6 で本物を動かせないので、偽の `fm` で渡す引数と分け方を確かめられるようにする。
- 決めた場面: ローカル LLM に対応した PR（Apple の Foundation Models を足した分）
- 関係する要件: REQ-COM-031, REQ-COM-022
- 対象: Mac
- 実装の場所: `AppleFMAvailability.check`

### DEC-COM-072 Apple の Foundation Models は、端末の中のモデルだけを使う
- 決めたこと: `--model pcc`（Private Cloud Compute）は使わず、既定の端末の中のモデルだけを使う。設定でモデルは選ばない。
- 理由: ローカルの選択肢として足すもので、文章を端末の外に送らない（REQ-COM-031）。Private Cloud Compute は Apple のサーバーに送り、使用量の上限もある。要るなら別に要件にする。
- 決めた場面: ローカル LLM に対応した PR（Apple の Foundation Models を足した分）
- 関係する要件: REQ-COM-031
- 対象: Mac
- 実装の場所: `AppleFMClient.arguments`

### DEC-COM-073 `fm` の文脈は 8,192 トークンとし、トークン数は文字の種類から多めに見積もる
- 決めたこと: 文脈は 8,192 トークン（コミュニティの文書の値。Apple の文書では未確認）として、DEC-COM-065 の分け方（`LongInputFitter`）をそのまま使う。出力の上限は、音声入力は 1,536、会議は 2,048 として入力の分を空ける。`fm` にはトークン数を数える方法がないので、漢字・かな・全角の文字は 1 文字 1 トークン、ほかは 3 文字で 1 トークンと多めに見積もる。見えないシステムの指示（約 54 トークン）は余白（256）に含める。
- 理由: 1 時間の会議（2〜4 万トークン）は入らないので、文字起こしを部分ごとの要点にしてから議事録にする。見積もりが少なすぎると文脈を超えて失敗するので、多めにとる（日本語の多くのトークナイザーは 1 文字 1 トークン以下）。
- 決めた場面: ローカル LLM に対応した PR（Apple の Foundation Models を足した分）
- 関係する要件: REQ-COM-031
- 対象: Mac
- 実装の場所: `AppleFMClient.contextLength`・`estimateTokens`、`LongInputFitter`

### DEC-COM-080 Dock は活性化ポリシー、メニューバーは NSStatusItem.isVisible で出し入れする
- 決めたこと: 設定は `AppPresenceSettings`（UserDefaults の `appPresence`）に `menuBar` / `dock` / `both` で持ち、既定は `both`。Dock に出すときは `.regular`、出さないときは `.accessory`（Dock・⌘Tab に出ないが、ウインドウとメニューの ⌘C などは使える）。メニューバーのアイコンは作ったまま `isVisible` で隠す。設定を変えたら、その場で両方を当て直し、ポリシーを変えたあとは Hanasu を前に出し直して設定画面を前面に戻す。起動時は `app.run()` の前にポリシーを決める。
- 理由: ポリシーは実行中に変えられるので、起動し直さずに切り替えられる。`.accessory` に変えた直後はアプリが後ろに回り、設定画面が他のアプリの裏に隠れるので、前に出し直す。アイコンを消して作り直すより、隠すほうが状態（録音中のアイコン）を持ち続けられる。`.regular` で起動してから変えると Dock のアイコンが一瞬出るので、起動前に決める。3 つの選択肢にして、どちらも出ない状態を作れないようにした（Hanasu に戻る道がなくなる）。
- 決めた場面: この PR（REQ-COM-040）
- 関係する要件: REQ-COM-040
- 対象: Mac
- 実装の場所: `AppPresence`、`AppPresenceSettings`、`AppDelegate.applyPresence`、`main.swift`

### DEC-COM-081 「Dock だけ」のときは、Dock のメニューをメニューバーのメニューと同じにし、録音中は Dock のアイコンに印を付ける
- 決めたこと: メニューバーのアイコンを出さないときは、Dock のメニューを、メニューバーのメニューと同じ作り（`AppDelegate.populateMenu`）で出す（「Hanasu を終了」は Dock に元からあるので除く）。音声入力の録音中・会議の記録中は、Dock のアイコンのバッジに「●」を出す。メニューバーにも出すとき（両方）は、Dock のメニューは今までどおり会議の操作と設定だけにし、バッジも出さない。
- 理由: メニューバーのメニューにしかない操作（最近の結果・履歴・英訳など）に辿り着けるようにする。録音していることがひと目で分かるように（DEC-DIC-017、REQ-MTG-026）、メニューバーのアイコンの代わりに Dock で示す。両方のときは今までの見た目を変えない。
- 決めた場面: この PR（REQ-COM-040）
- 関係する要件: REQ-COM-040, REQ-MTG-026
- 対象: Mac
- 実装の場所: `AppDelegate.applicationDockMenu`、`AppDelegate.populateMenu`、`AppDelegate.updateIcon`

### DEC-COM-090 オンボーディングは一度だけ出し、閉じても終わったことにする。以前から使っている人には自動では出さない
- 決めたこと: 終わったかどうかを UserDefaults の `onboardingCompletedVersion`（今は 1）に持つ。起動時にこれがなければオンボーディングを出す。最後のページの「はじめる」だけでなく、途中でウインドウを閉じても終わったことにする。ただし、この値がなくても、すでに Hanasu の設定が保存されている（UserDefaults の Hanasu のドメインに何かの値がある）なら、以前から使っている人として、出さずに終わったことにする。
- 理由: 依頼が「初回起動時」で、2 回目以降に出すと邪魔になる。閉じた人に毎回出し直すと、同じ説明を何度も見せることになる（メニューから開き直せる。DEC-COM-091）。この機能を入れた版に上げただけの人は「初回」ではなく、すでに AI を選んで使っているので、起動のたびの流れを変えない。版の番号で持つのは、内容を大きく変えたときに、もう一度見せられるようにするため。
- 決めた場面: オンボーディングを入れた PR（REQ-COM-050・051）
- 関係する要件: REQ-COM-050, REQ-COM-051
- 対象: Mac
- 実装の場所: `OnboardingState`

### DEC-COM-091 オンボーディングは、メニューバー（と Dock だけのときの Dock）のメニューと、アプリのメニューから開き直せる
- 決めたこと: メニューバーのメニューの「設定…」の上と、アプリのメニュー（「Hanasu」）の「設定…」の上に「Hanasu の使い方…」を置き、オンボーディングを最初のページから開く。開き直したときも AI のページは同じ（選ぶと保存する）。
- 理由: 一度閉じたら二度と見られないと、あとで機能を探すときに困る。AI の選び直しも設定の「AI」タブと同じ結果になるので、開き直しても害がない。Dock だけのときは Dock のメニューがメニューバーのメニューと同じ作りなので（DEC-COM-081）、そこにも出る。
- 決めた場面: オンボーディングを入れた PR（REQ-COM-051）
- 関係する要件: REQ-COM-051
- 対象: Mac
- 実装の場所: `AppDelegate.populateMenu`、`AppDelegate.makeMainMenu`、`AppDelegate.openOnboarding`

### DEC-COM-092 オンボーディングは 7 ページにし、AI の選択は音声入力と会議の両方に当て、どれかを選ぶまで先に進めない。Gemma を選んだら両方を Gemma 4 E4B にする
- 決めたこと: ページは「ようこそ」「使う AI を選ぶ」「音声入力」「会議の記録」「履歴・辞書・スニペット」「設定の Tips」「許可と準備」の 7 つ。大きさを変えられないウインドウ（640×600）で、下に「戻る」「次へ」とページの点を置く。AI のページのカードは「Gemma 4 E4B（おすすめ）」「Gemini」「Claude」「Apple」の 4 つ。そのページで押したものを選んだことにし（今の設定の値には、はじめは選んだ印を付けない）、押すまで「次へ」を押せない。押すと `dictationAIProvider` と `meetingAIProvider` の両方をその AI にする。Gemma のときは `localDictationModel` と `localMeetingModel` も両方 Gemma 4 E4B にする（前に保存してあるモデルがあっても書き換える。既定も Gemma 4 E4B。DEC-COM-067）。Gemini・Claude のモデルは各 AI の既定のまま（REQ-COM-023、DEC-COM-005、DEC-MTG-014）。モデルを変えたい人（音声入力だけ速い LFM2.5 にする など）には「設定の Tips」のページの欄（設定の「AI」タブと同じ `AIChoiceRow`）で選ばせる。準備の欄は設定の「AI」タブの部品をそのまま使う。Apple の Foundation Models が使えない Mac（`AppleFMAvailability` が理由を返す。macOS 27 より前など）では、そのカードを薄くして押せなくし、理由はカードの上に指を置くと出す。アプリの設定の既定（オンボーディングを通らないときの値）は、両方ローカルの Gemma 4 E4B（DEC-COM-068）。
- 理由: 依頼が「デフォルトの AI を選択させる」「デフォルトのモデルは Gemma」「黙って最初に選ばず、チュートリアルの中で選んでダウンロードする」なので、Gemma を「おすすめ」としていちばん目立つ場所に置きつつ、選ぶのはユーザーに任せる。用途ごとに別のモデルにすると 2 つ（Gemma と LFM2.5 で約 5.8 GB）をダウンロードすることになるので、両方 Gemma にして 1 回（約 4.6 GB）で済ませる。設定の既定は、はじめ Gemini のままにしていた（ダウンロードしていない人の整形が黙って失敗するため）が、モデルがないときにダウンロードするかを尋ねるようにした（REQ-COM-032）ので、Gemma に変えた（DEC-COM-068）。初めての人に用途ごとの選び分けを先に求めると迷うので、まず 1 つ選ばせ、別々にできることは Tips で見せる。部品を共有して、設定画面と見た目・保存先・文言が食い違わないようにする。
- 決めた場面: オンボーディングを入れた PR #53（REQ-COM-050・051）。Gemma をおすすめにしたのも同じ PR
- 関係する要件: REQ-COM-050, REQ-COM-051, REQ-COM-024, REQ-COM-030
- 対象: Mac
- 実装の場所: `OnboardingPage`、`OnboardingAIChoice`、`OnboardingAIPage`、`OnboardingTipsPage`、`OnboardingModel.chooseDefaultAI`

### DEC-COM-093 初回の起動では、設定画面とアクセシビリティの許可の代わりにオンボーディングを出す
- 決めたこと: オンボーディングを出す起動では、設定画面を開かず、起動時のアクセシビリティの許可のダイアログも出さない（DEC-COM-009 の例外）。許可は、オンボーディングの最後のページのボタンで求める。2 回目からの起動は DEC-COM-009 のまま。オンボーディングを出している間に Finder や Dock から開き直したときは、設定画面ではなくオンボーディングを前に出す。
- 理由: 設定画面とシステムの許可のダイアログがオンボーディングに重なると、どれを見ればよいか分からなくなる。許可が要る理由（自動入力に要る）を説明してから求めたほうが、許可してもらいやすい。許可しないまま閉じても、次の起動で今までどおり求める。
- 決めた場面: オンボーディングを入れた PR（REQ-COM-051）
- 関係する要件: REQ-COM-051, REQ-DIC-004
- 対象: Mac
- 実装の場所: `AppDelegate.applicationDidFinishLaunching`、`AppDelegate.applicationShouldHandleReopen`、`OnboardingPermissionsPage`

### DEC-COM-094 Gemma のダウンロードは、ボタンで始め、終わるのを待たずに次へ進める
- 決めたこと: Gemma のカードを押しただけではダウンロードを始めない。AI のページのダウンロードの欄の「ダウンロード（4.59 GB）」か、「次へ」の代わりに出す「ダウンロードして次へ」を押したときに始める（`LocalLLMStore.ensureDownloaded`。設定の「AI」タブのダウンロードと同じ処理で、同じ進み具合が見える）。始めたら、終わるのを待たずにほかのページへ進め、ダウンロードはウインドウを閉じても続く。進み具合は AI のページと最後のページに出し、中止もできる。この Mac のメモリが 16 GB より少ないときは、Gemma が重いかもしれないことを欄に書く（選べなくはしない）。
- 理由: 約 4.6 GB を、押した意味の分からないうちに落とし始めないようにする（カードを試しに押す人もいる）。ダウンロードには数分かかるので、待たせずに残りの説明を読んでもらう。メモリの少ない Mac では動くが遅いので、選ぶ前に分かるようにする（LocalLLMModel の説明の「メモリ 16 GB 以上向け」）。
- 決めた場面: PR #53
- 関係する要件: REQ-COM-050
- 対象: Mac
- 実装の場所: `OnboardingGemmaDownload`、`OnboardingModel.next`、`OnboardingPermissionsPage`

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
- 決めたこと: Mac 版の `GeminiClient.swift`（整形・英訳）、`MinutesTemplate.swift`・`MeetingNotes.swift`（議事録）の組み立てをそのまま移す。文面は、多言語化の PR から Mac と同じ言語ごとの JSON（`Sources/Hanasu/Resources/Prompts/`。DEC-COM-160）を埋め込んで読むので、文面を 2 か所で直すことはない。組み立てを変えるときは両方を直す。テストで文面と組み立てを確かめる。
- 理由: Mac と Windows で結果をそろえる。片方だけ直すことを防ぐ。
- 決めた場面: PR #19。文面を JSON に移したのは多言語化の PR（2026-11-05）
- 関係する要件: REQ-DIC-003, REQ-DIC-010, REQ-DIC-082, REQ-MTG-006
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
- 決めたこと: 録った音声を WAV にして inline data で送り、文字起こしだけをさせる（指示は `GeminiPrompts.TranscriptionInstruction` に新しく書いた。整形は次の呼び出しで行うので「聞こえたとおり」に書き起こさせる）。音声入力では、Windows は 5 分ごとに分けて送る（DEC-DIC-145）。タイムアウトは、整形・英訳が 15 秒（Mac 版と同じ）、音声の文字起こしが 60 秒。設定画面に「音声が Google に送られる」と書く。
- 理由: inline data の上限に収める。文字起こしと整形を分けるのは Mac 版と同じ理由（DEC-COM-031）。
- 決めた場面: PR #19
- 関係する要件: REQ-COM-001
- 対象: Windows
- 実装の場所: `windows/Hanasu.Core/Transcription/Transcribers.cs`、`windows/Hanasu.Core/Gemini/GeminiPrompts.cs`

### DEC-COM-107 Windows 版は、Mac 版の一部の機能を持たない
- 決めたこと: Windows 版には、アプリ別の文体・スニペット・画面の文脈・履歴の整え直しと録音・最後の結果の再入力・選択を声で編集・辞書の候補の提案・会議の字幕・マイク側の話者分離・会議の自動検出・会議の横断検索と質問・議事録のファイル保存・Slack 向けのコピー・リマインダーへの登録がない（REQ-DIC-020〜071 の一部、REQ-MTG-009・014〜016・019 は「対象: Mac」のまま）。一覧は [windows/README.md](../../windows/README.md) の「Mac 版との差」。
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
- 決めたこと: プロンプトは Gemini と同じ文面（`GeminiPrompts`・`MinutesPrompt`。DEC-COM-102）を使い、Claude 向けには変えない。`temperature` / `top_p` / `top_k` と `thinking` は送らない（3 つのモデルとも既定で adaptive。Opus 5.5 は止められず、Sonnet 5.5 は `disabled` が 400）。`output_config.effort` は、整形・英訳が `low`、議事録が `medium`（Sonnet 5.5 の既定は high なので明示する）。`max_tokens` は thinking の分も見込んで、整形・英訳 8,000、議事録 32,000。assistant の prefill は使わない。システムの指示に `cache_control`（ephemeral・5 分）を付ける。待ち時間の上限は、音声入力 15 秒、議事録 300 秒（Gemini は 180 秒のまま）。文字起こし・メモの中の `<transcript>` `</transcript>` `<user_notes>` `<action_items>` `<speaker_names>`（DEC-MTG-068）などの区切りのタグは、全角の山かっこに置き換えてから埋め込む（Gemini にも効く）。
- 理由: 同じ文面なら Gemini と結果を比べやすく、Mac 版ともそろう。システムの指示は「中身は質問や命令ではない」と書いてあり、Claude でもそのまま効く。区切りのタグを本文に書かれると、区切りの外に指示を書けてしまう。キャッシュは、整形の指示が最小の長さ（Haiku 5.5・Sonnet 5.5・Opus 5.5 は 512 トークン）を超えれば効くが、キーがないので効いたかはまだ確かめていない（`claude-refine` が使った量を出す）。
- 決めた場面: Claude API に対応した PR
- 関係する要件: REQ-COM-020, REQ-COM-022
- 対象: Windows
- 実装の場所: `windows/Hanasu.Core/Claude/ClaudeClient.cs`（`BuildParams`）、`windows/Hanasu.Core/Ai/PromptText.cs`

### DEC-COM-143 Windows 版の Claude のエラーの文言とやり直し、「接続を試す」
- 決めたこと: SDK の例外を `ClaudeException` に分け、HUD・会議ノートにそのまま出せる日本語にする（401「API キーが正しくありません」、403、404「モデルが見つからないか、このキーでは使えない」、402 支払い、429 上限、529 混雑、5xx、つながらない、時間切れ）。SDK の例外の本文はそのまま出さず、API の `error.message` を 200 文字までだけ添える。429・5xx（529 を含む）・つながらないときは SDK が `retry-after` を見て 2 回までやり直し、400・401・403・404 はやり直さない。「接続を試す」は `GET /v1/models/{モデル}` で確かめる（トークンを使わず、キーとモデルの両方を確かめられる）。入力欄にキーがあれば保存せずにそのキーで試す。Gemini にも同じ「接続を試す」を置く（API キーの欄とサービスアカウントの欄。URL と文言は Mac 版の DEC-COM-050 と同じ。モデルは音声入力の Gemini のモデル。入力欄にキーがあれば保存せずにそのキーで試す）。
- 理由: 401 をそのまま「エラー」と出すと、キーの入れ間違いだと分からない。SDK のやり直しは指数的に待ち、API の指示（retry-after）も見る。
- 決めた場面: Claude API に対応した PR。Gemini は PR #65 の判断事項の対応（2026-11-05）
- 関係する要件: REQ-COM-020, REQ-DIC-003
- 対象: Windows
- 実装の場所: `windows/Hanasu.Core/Claude/ClaudeException.cs`、`windows/Hanasu.Core/Claude/ClaudeClient.cs`（`CheckAsync`）、`windows/Hanasu.Core/Gemini/GeminiClient.cs`（`CheckAsync`）、`windows/Hanasu.Windows/Views/SettingsWindow.xaml.cs`（`OnCheckGemini`）

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
- 決めたこと: Ctrl+V を送る前に、前面のウインドウのプロセスの整合性レベルを調べ、Hanasu より高い（管理者として実行など）か調べられなければ、送らずに結果を画面に残す（入力できる場所がないときと同じ表示。DEC-DIC-123）。クリップボードに残すかは設定に従う（既定は残す。REQ-DIC-081・DEC-DIC-122）。クリップボードに置く文章には、履歴（Win+V）・クラウドのクリップボード・監視アプリに残さない印（`ExcludeClipboardContentFromMonitorProcessing`・`CanIncludeInClipboardHistory`=0・`CanUploadToCloudClipboard`=0）を付ける（PR #19 から付いていることを確かめた）。メニューの「最近の結果」と会議の「Markdown をコピー」は、ユーザーが自分でコピーする操作なので印を付けない。Hanasu は管理者権限を求めず（`asInvoker`）、`uiAccess` も使わない。
- 理由: UIPI で届かないキーを SendInput は成功として返すので、送ったつもりで何も入らず、元のクリップボードに戻して文章を失うことがある。
- 決めた場面: Claude API に対応した PR（印は PR #19）。結果を画面に残す表示にそろえたのは、入力できる場所がないときに結果を画面に残す PR（Windows 版）
- 関係する要件: REQ-DIC-004, REQ-COM-022, REQ-DIC-080
- 対象: Windows
- 実装の場所: `windows/Hanasu.Windows/Services/ClipboardTextInserter.cs`、`windows/Hanasu.Windows/Services/WindowsSecurity.cs`（`IsHigherIntegrity`）

### DEC-COM-150 Windows 版の依存パッケージは lock ファイルで固定し、配布物の SHA-256 を残す
- 決めたこと: すべてのプロジェクトで `packages.lock.json` を使い（`RestorePackagesWithLockFile`）、CI の Restore の段では `--locked-mode`（`CI=true` のとき `RestoreLockedMode`）で、lock と食い違えば失敗させる。publish の段は RID（win-x64）と ILLink を足して restore し直し、lock ファイル（RID なしで作る）と入力が合わないので、locked mode を外す。CI は zip の SHA-256 を `Hanasu-windows-x64.zip.sha256` に書いて artifact に入れる。
- 理由: 同じ版の番号でも中身が差し替わったパッケージや、知らないうちに上がった推移的な依存を取り込まない。配布物は署名していないので、ダウンロードした人がハッシュで確かめられるようにする。
- 決めた場面: Claude API に対応した PR。リリースのワークフローにも同じ扱いを入れたのは、v1.3.1 の Windows 版のビルドが locked mode で失敗したため
- 関係する要件: REQ-COM-022, REQ-REL-005
- 対象: Windows
- 実装の場所: `windows/Directory.Build.props`、`.github/workflows/windows.yml`、`.github/workflows/tagpr.yml`（リリースの Windows 版のビルド）

### DEC-COM-160 プロンプトは言語ごとの JSON に置き、Mac と Windows で同じファイルを読む
- 決めたこと: AI へのプロンプトの文面を `Sources/Hanasu/Resources/Prompts/<言語>.json`（キー → 文字列か 1 行 1 要素の配列。`${name}` はアプリが埋める）に置く。Mac は SwiftPM のリソース（`Hanasu_Hanasu.bundle`）として入れ、`scripts/build-app.sh` が .app の Contents/Resources に写す。SwiftPM が作る `Bundle.module` は、見つからないとビルドしたマシンのパスを見に行って止まるので使わず、`HanasuResources` で .app と実行ファイルの隣を探す。Windows は同じファイルを `Hanasu.Core` に EmbeddedResource として埋め込む。その言語にないキーは英語、英語にもなければ日本語を使う。
- 理由: 17 言語の文面をコードに埋めると、Mac と Windows で 2 か所ずつ直すことになり、ずれる（DEC-COM-102 の「両方を直す」をなくす）。JSON なら訳の担当がコードを触らずに直せ、`scripts/check-i18n.py` で漏れを機械的に見つけられる。
- 決めた場面: 多言語化の PR（2026-11-05）
- 関係する要件: REQ-COM-061
- 対象: Mac / Windows
- 実装の場所: `Prompts`、`HanasuResources`（`Sources/Hanasu/Prompts.swift`）、`Package.swift`、`scripts/build-app.sh`、`windows/Hanasu.Core/Hanasu.Core.csproj`

### DEC-COM-161 文字起こしの言語を、プロンプトの言語に寄せる決まり
- 決めたこと: 文字起こしの言語の識別子の言語コードで決める。中国語は繁体字（Hant）か台湾・香港・マカオなら zh-TW、それ以外は zh-CN。ポルトガル語はすべて pt-BR。古いインドネシア語のコード `in` は id。17 言語のどれでもなければ英語。設定が保存されていなければシステムの言語から決める。日時はその言語の曜日で「2026/11/02 (月) 14:30」の形に書く。CLI では `--prompt-language <言語>` で変えられ、日本語の文面を確かめる self-test は日本語に固定する。
- 理由: 文字起こしの言語は、ユーザーが話す言語そのもので、初期値はシステムの言語（REQ-COM-004）。表示の言語より、話す言語に合わせた指示の方が整形の質が上がる（英語の画面で日本語を話す人もいる）。
- 決めた場面: 多言語化の PR（2026-11-05。基準はユーザーに確かめた）
- 関係する要件: REQ-COM-061, REQ-COM-004
- 対象: Mac / Windows
- 実装の場所: `PromptLanguage.from(localeIdentifier:)`、`PromptLanguage.current`

### DEC-COM-162 日本語の文面は変えず、ほかの言語は訳ではなく、その言語の話し言葉に合わせて書き直す
- 決めたこと: ja.json は今までのプロンプトと一字一句同じにする（Windows の Gemini での文字起こしの指示だけ、「主に日本語で、英語などが」を「主に${language}で、ほかの言語が」にした）。en.json を言語によらない形で書き、ほかの 15 言語はそれをもとに、フィラー・言い直し・口頭の記号の指示・決まり文句・誤認識の例・文体のプリセット（敬語や T–V の区別）をその言語のものに書き直す。整形の言語の「日本語に統一」（REQ-DIC-082）と、翻訳の言語（英語・日本語。REQ-DIC-013）は、プロンプトの言語によらず今のまま（「日本語に統一」はどの言語でも日本語にする）。
- 理由: 日本語の整形の質を落とさない。直訳したプロンプトでは、日本語の例（「えー」「改行」）がほかの言語の話し方に合わない。要件（REQ-DIC-082・013）は変えない。
- 決めた場面: 多言語化の PR（2026-11-05。言語ごとに書き直すことはユーザーに確かめた）
- 関係する要件: REQ-COM-061, REQ-DIC-003, REQ-DIC-082, REQ-DIC-013
- 対象: Mac / Windows
- 実装の場所: `Sources/Hanasu/Resources/Prompts/`

### DEC-COM-163 会議の話者のラベル・議事録の見出し・「担当」「期限」は、プロンプトの言語で書き、読むときはすべての言語を受け付ける
- 決めたこと: AI に渡す文字起こしの話者名は、名前がなければプロンプトの言語のラベル（`speaker.*`。日本語なら「自分」「話者1」「同席者1」「相手」）にする（`Meeting.promptName`）。表示のラベル（`Meeting.displayName`）とは分ける。議事録のタイトル行・「なし」・アクションアイテムの「担当」「期限」と日付の形もプロンプトの言語で書く。議事録を読むところ（チェックボックスの行の読み取り、Slack への書き出しで話者のメモの見出しを外す、リマインダーの初期の選択、話者名の推定でラベルを名前として扱わない）は、17 言語すべての言い方を受け付ける。
- 理由: 指示に出てくるラベルと、AI が見る文字起こしのラベルが同じ言語でないと、AI が話者を取り違える。言語の設定を変えたあとも、前に作った議事録を読めるようにする。
- 決めた場面: 多言語化の PR（2026-11-05）
- 関係する要件: REQ-COM-061, REQ-MTG-006, REQ-MTG-018, REQ-MTG-027
- 対象: Mac / Windows
- 実装の場所: `Meeting.promptName`、`Meeting.promptLabel`、`ActionItem.markdownLine`、`ActionItem.parse(fromMarkdown:)`、`SpeakerNameInference.isPlaceholder`、`MeetingExport.slackBody`

### DEC-COM-164 訳の漏れは scripts/check-i18n.py で見つけ、CI で動かす。訳はスキルとエージェントに任せる
- 決めたこと: `scripts/check-i18n.py`（python3 の標準ライブラリだけ）が、17 言語のプロンプトのファイルがそろっていること、日本語と同じキー・埋める場所・タグ・JSON のキー・残す記号があること、話者のラベルと「なし」が同じ言語の指示の中で使われていることを確かめ、食い違えば失敗する。英語と同じままの値は報告だけする。`.github/workflows/spec.yml` で毎回動かす。文字列やプロンプトを足す手順は `.claude/skills/i18n/SKILL.md`、訳は `.claude/agents/i18n.md` のエージェントに任せる。
- 理由: 17 言語を人の目だけでそろえるのは無理がある。機械で見られるもの（漏れ・形の食い違い）は CI で止め、訳の質はエージェントの確認の手順で担保する。
- 決めた場面: 多言語化の PR（2026-11-05）
- 関係する要件: REQ-COM-062
- 対象: Mac / Windows
- 実装の場所: `scripts/check-i18n.py`、`.github/workflows/spec.yml`

### DEC-COM-165 UI の文字列は、日本語の原文をキーにして tr() で引き、String Catalog を起動後に JSON のまま読む
- 決めたこと: 利用者に見える文字列は `tr("日本語の原文", 引数…)` で引く（補間は `%@`。訳では `%1$@` のように順番を変えてよい）。訳は `Sources/Hanasu/Resources/Localizable.xcstrings`（String Catalog。ソースの言語は ja）に置き、SwiftPM のリソースとしてそのまま入れて、起動後に一度だけ JSON として読む。日本語ではキーをそのまま出し、その言語に訳がなければ英語、英語にもなければ日本語を出す。カタログのキーは `scripts/i18n-strings.py sync` で Swift の `tr("…")` にそろえ、訳は `export` / `import` で出し入れする。言語の決まりに使う日本語の語（会議への質問の期間の語、スニペットのフィラー、敬称、議事録を読むときの語）は UI ではないので包まず、行末に `// skip-tr` を書く。開発用の CLI（`*CLI.swift`・`main.swift`・自己テスト）とログは訳さない。
- 理由: Xcode がなくても（Command Line Tools と SwiftPM だけで）ビルドできるようにする。`xcstringstool` は Xcode にしかなく、SwiftPM は .xcstrings を変換せずに写すだけなので、.lproj の Localizable.strings を作れない。String Catalog の形にしておけば、Xcode でも開ける。原文をキーにすると、日本語のコードが読みやすいままで、キーの付け忘れもない。
- 決めた場面: 多言語化の PR（Mac の表示。2026-11-05）
- 関係する要件: REQ-COM-060, REQ-COM-062
- 対象: Mac
- 実装の場所: `tr`、`L10n`、`scripts/i18n-strings.py`

### DEC-COM-166 表示の言語は、優先する言語の並びのうち対応している最初の言語。.app は 17 言語の .lproj を持つ
- 決めたこと: `UILanguage` は `Locale.preferredLanguages` を前から見て、17 言語のどれかに寄せられる最初の言語にする（寄せ方は `PromptLanguage.supported(localeIdentifier:)`。DEC-COM-161 と同じ）。どれにもなければ英語。日付・曜日の表示もこの言語のロケールで書く。.app の Info.plist は開発の言語を en にし、`CFBundleLocalizations` に 17 言語を並べ、`scripts/build-app.sh` が言語ごとの `<言語>.lproj/InfoPlist.strings`（権限を求めるときの説明）を作る。CLI では `--ui-language <言語>` で変えられ、自己テストは日本語に固定する。
- 理由: macOS がアプリの言語を選ぶのと同じ決め方にして、AppKit が出す部分（標準のメニュー項目・権限のダイアログ）とアプリの文言の言語をそろえる。.lproj がないと、macOS はアプリが日本語だけだと見なす。
- 決めた場面: 多言語化の PR（Mac の表示。2026-11-05）
- 関係する要件: REQ-COM-060
- 対象: Mac
- 実装の場所: `UILanguage`、`Resources/Info.plist`、`scripts/build-app.sh`

### DEC-COM-151 Mac の設定画面は、左のサイドバーで項目を切り替える
- 決めたこと: 設定のウインドウを、上のタブ（`TabView`）から、システム設定と同じ左のサイドバー（`NavigationSplitView`）に変える。項目（一般・AI・辞書・ルール・アプリ別・スニペット・会議・履歴・権限）と順番は変えず、それぞれに色付きの角丸のアイコンを付け、右側の上に項目の名前を出す。ウインドウは大きさを変えられ（最小 700×480、初めは 780×600）、位置と大きさを覚える。最後に開いていた項目を、次に開いたときも出す（UserDefaults の `settingsPane`）。ショートカットの欄は、キーの欄の幅を変えず、「初期値に戻す」をその左の小さなボタンにする。権限の欄は、許可済み・未許可を色付きの印で出す。画面の文言の「「AI」タブ」などは「設定の「AI」」にした。
- 理由: ユーザーの依頼（2026-11-05「Mac の設定画面をもう少しモダンにして」）。8 つのタブが上に詰まって並び、窓が 560×460 の固定で、長い「一般」などが狭かった。サイドバーなら項目が増えても並べられ、今の macOS の設定画面と同じ見た目と操作になる。ウインドウの大きさを中身に合わせないのは、会議ノート（`AppDelegate.makeMeetingWindow`）と同じ理由（長い項目を開くと縦に伸びる）。
- 決めた場面: 設定画面をサイドバーにした PR
- 関係する要件: REQ-COM-040
- 対象: Mac
- 実装の場所: `SettingsView`、`SettingsPane`、`SettingsPaneIcon`、`AppDelegate.makeSettingsWindow`、`ShortcutRecorder`
- 確かめ方: `.build/debug/Hanasu --render-settings /tmp/settings [--pane ai] [--dark]`

### DEC-COM-153 Windows 版の固定色の面は、ハイコントラストのテーマでは OS の色に差し替える。HUD はそのまま
- 決めたこと: 会議ノートの左の欄（`#FAFAFA`）・「● 記録中」の表示（`#FDECEA`）・記録中のメモ欄（`#F6F8FC`）・設定の試し書きの出力（`#F7F7F7`）は、通常のテーマでは今までの色のまま、ハイコントラストのテーマ（`SystemParameters.HighContrast`）では背景を OS の `Window` / `Control` の色、枠を `WindowFrame`（記録中は `Highlight`）の色に差し替える（`App.xaml` の `SidePane` / `LivePane` / `LiveTitle` / `InnerPane` / `ReadOnlyOutput` のスタイル。ウインドウを作るときに読むので、テーマを変えたあとは開き直す）。会議の一覧の補足と鉛筆の印の灰色（`#5F6368`）も `GrayText` にする。音声入力の HUD（濃い半透明の背景に白い文字）は変えない。
- 理由: 補足の文は PR #65 で `GrayText` にしたが、面の色が固定のままだと、ハイコントラスト（黒い背景に白い文字）で白っぽい面に白い文字が載って読めない。HUD は Mac 版と同じ、前面に浮かぶ独自の見た目で、背景（`#1E2126`、不透明度 95%）と白い文字のコントラストは十分にあり、OS の色に差し替えると録音中の赤い停止ボタンなどの意味の色も失う。
- 決めた場面: PR #65 の判断事項の対応（2026-11-05）
- 関係する要件: REQ-COM-010, REQ-COM-011
- 対象: Windows
- 実装の場所: `windows/Hanasu.Windows/App.xaml`、`windows/Hanasu.Windows/Views/MeetingWindow.xaml`、`windows/Hanasu.Windows/Views/SettingsWindow.xaml`

### DEC-COM-152 Windows 版のトレイのメニューは、Mac 版のメニューバーと同じ文言にし、アクセスキーを付ける
- 決めたこと: 「録音を開始(R)」/「録音を停止して入力(R)」、「英訳して入力を開始(T)」、「会議の記録を開始(M)」/「会議の記録を停止（mm:ss）(M)」/「会議の記録を準備中…」/「会議の記録を処理中…」、「会議ノートを開く(N)…」、「最近の結果(E)」、「履歴を開く(H)…」、「設定(S)…」、「Hanasu を終了(X)」。並びと区切りは Mac 版の `AppDelegate` のメニューと同じ。Mac 版だけの項目（選択を声で編集・自動入力の状態・Hanasu の使い方）は、Windows 版にその機能がないので置かない。
- 理由: 以前は「音声入力を開始」「録音を止めて入力」「会議ノートを開く」「終了」と、Mac 版と言い回しが違っていた（UX-095）。アクセスキーは Windows のメニューの慣習で、キーボードだけで操作する人（UX-090）に要る。
- 決めた場面: PR #65 の判断事項の対応（2026-11-05）
- 関係する要件: REQ-COM-010, REQ-COM-011
- 対象: Windows
- 実装の場所: `windows/Hanasu.Windows/TrayIcon.cs`

---

## 廃止

やめた要件・設計判断は、消さずにここへ移す（`- 状態: 廃止（日付・理由・PR）`）。今はない。
