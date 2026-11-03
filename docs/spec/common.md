# 設定・認証・共通の仕様（COM）

音声入力と会議の記録で共通のもの（文字起こしのエンジン、Gemini の呼び出しと認証、アプリの形、ショートカット、設定、権限）について、**実装済み**の振る舞いのうち、要件（REQ）と設計判断（DEC）を並べる。

- 区分・ID・タグの決まりは [docs/README.md](../README.md)。
- 実装の説明は [design/dictation.md](../design/dictation.md)（3 章・4.10・5.3・6・7）と [design/meeting.md](../design/meeting.md)（4.3.1）。

---

## 要件

### REQ-COM-001 文字起こしのエンジンを、Mac 標準 / Whisper / Gemini から選べる
- 内容: 音声入力と会議の記録の両方で、文字起こしのエンジンを OS 標準・Whisper（端末の上で動かす）・Gemini（音声を送る）の 3 つから選べる。
- 受け入れ条件: 設定の「一般」→「文字起こし」でエンジンを変えると、次の音声入力・会議の記録からそのエンジンで文字起こしされる。
- 出典: ユーザーの指定（2026-11-03、PR #17）「Mac 標準 / Whisper / Gemini を選べる。Windows でも同じにする」
- 対象: Mac（Windows は PR #19 で作業中。[roadmap.md](../roadmap.md) FUT-001）
- 実装の場所: `TranscriptionEngine`、`AppSettings`（`dictationEngine` / `meetingEngine`）、`TranscriptionEngineSettingsSection`、`BatchTranscriber`
- 確かめ方: `.build/debug/Hanasu --transcribe-file /tmp/test.aiff --engine apple|whisper|gemini`、`--meeting-files me.wav others.wav --engine whisper|gemini`、`--render-engine-settings /tmp/engine.png`

### REQ-COM-002 文字起こしの既定は、OS 標準のエンジンにする
- 内容: 文字起こしのエンジンの既定は OS 標準（Mac は SpeechAnalyzer。音は Mac の外に出ない）。初版から「Mac 標準の音声入力エンジン」で文字起こしする。
- 受け入れ条件: 設定を変えていない状態で、音声入力と会議の記録が Mac 標準のエンジンで文字起こしされる。
- 出典: 初版（a787da8）の「Mac 標準の音声入力」で認識するという依頼。ユーザーの指定（2026-11-03、PR #17）「既定は OS の標準」
- 対象: Mac（Windows は Windows 標準の音声認識。PR #19 で作業中）
- 実装の場所: `AppSettings.init`（`dictationEngine` / `meetingEngine` の初期値）、`SpeechRecognizer`
- 確かめ方: 新しいユーザーの UserDefaults で `--render-engine-settings /tmp/engine.png` を描き、Mac 標準が選ばれていること

### REQ-COM-003 Whisper は、選んだときにモデルをダウンロードする
- 内容: Whisper のモデルはアプリに同梱せず、エンジンかモデルを選んだ時点でダウンロードする。
- 受け入れ条件: 設定で Whisper を選ぶとダウンロードが始まり、進み具合が出て、終わるとそのモデルで文字起こしできる。
- 出典: ユーザーの指定（2026-11-03、PR #17）「Whisper は選んだときにモデルをダウンロードする」
- 対象: Mac（Windows は PR #19 で作業中）
- 実装の場所: `WhisperModelStore.ensureDownloaded`、`TranscriptionEngineSettingsSection.downloadIfNeeded`
- 確かめ方: `.build/debug/Hanasu --download-whisper base`（保存先は `HANASU_MODELS_DIR` で変えられる）、`--render-engine-settings /tmp/engine.png --downloading`

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
- 決めたこと: API キーはキーチェーン（`kSecClassGenericPassword`）に保存し、UserDefaults やログには残さない。
- 理由: 秘密情報を平文の設定ファイルに置かない。
- 決めた場面: 初版（a787da8）
- 関係する要件: REQ-DIC-003
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
