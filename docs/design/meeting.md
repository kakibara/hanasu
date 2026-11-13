# Hanasu 会議の記録 — 設計と技術選定

Google Meet・Slack ハドル・Microsoft Teams などのオンライン会議の音声を Mac 上で拾い、
話者ごとに分けた文字起こしと議事録を残す機能。既存の音声入力アプリ Hanasu に機能として追加する。

- 対象 OS: macOS 26 (Tahoe) 以降 / Apple Silicon
- 作成日: 2026-11-02

> **この文書は「今こう作られている」の説明（as-is）。** コードと食い違ったら、コードが正しい（気づいたら、この文書を直す）。「こうあるべき」（要件と設計判断）は spec に書く。プロンプトの全文・既定値の一覧・CLI のオプションの一覧のようなコードの写しは置かず、ファイルと型・関数の名前で誘導する。

この文書は実装の説明（事例調査・技術選定・アーキテクチャ・データの流れ・状態遷移・なぜその作りにしたか）。

- 要件（初版の要件定義 F1〜F10・非機能要件・対象外と、あとから足した F11〜F16 など）と設計判断は [spec/meeting.md](../spec/meeting.md)。振る舞いを変えるときは、先に spec を見る（[docs/README.md](../README.md)）。
- 日付の付いた検証の結果と、過去に起きた問題は [verification/meeting.md](../verification/meeting.md)。
- まだ作っていないもの（会議アプリだけを録るモード、エコーキャンセル、ボットモード）は [roadmap.md](../roadmap.md)。

---

## 1. 背景と目的

- オンライン会議の内容を、あとから検索・共有できる形で残したい。
- 会議ツールが Meet / Slack / Teams とばらばらなので、ツールごとの録画・文字起こし機能に頼らず、1 つの方法でまとめて記録したい。
- 「誰が何を言ったか」が分かる形（話者分離）にしたい。

## 2. 事例調査

### 2.1 2 つの方式

会議の記録ツールは、音声の取り方で 2 つに分かれる。

| 方式 | 仕組み | 主な製品 | 長所 | 短所 |
| --- | --- | --- | --- | --- |
| **A. 会議ボット** | 録音用のボットが参加者として会議に入る | Otter（OtterPilot）、Fireflies、tl;dv、[Recall.ai Meeting Bot API](https://recall.ai/product/meeting-recording-api) | 参加者ごとの音声ストリームが取れることがあり、話者分離が正確。録音中であることが全員に見える | 会議ツールごとに API・審査・サーバーが必要。Slack ハドルはボット用の公開 API がなく、Recall.ai のような専業ベンダーに頼ることになる。ボットが入ることを嫌がる相手もいる |
| **B. 端末で録音（ボットなし）** | 自分の Mac のマイクと、Mac が再生している音（システム音声）を録る | [Granola](https://docs.granola.ai/article/transcription)、Hyprnote（現 anarlog）、[Meetily](https://luci.memories.ai/alternatives/meetily)、[Recall.ai Desktop Recording SDK](https://www.recall.ai/product/desktop-recording-sdk) | 会議ツールを問わない（Meet・Slack ハドル・Teams・Zoom・対面も同じ方法）。サーバー不要。会議にボットが入らない | 相手側の音声は 1 本にまとまるので、相手が複数いると話者分離に別の処理が要る。録音していることを自分で伝える必要がある |

Granola のドキュメントでは「マイクを 1 チャンネル、PC で鳴っている音をもう 1 チャンネル」として録り、
自分の発言と相手側の発言を分けている。アプリ単位で切り分けず、システム全体の音をまとめて録る。

### 2.2 採用: B（端末で録音）

- Slack ハドルにはボットで参加する公開 API がない。Meet・Teams もボット運用にはクラウド基盤と審査が要り、個人で作るには重い。
- 端末で録れば、3 つのツールすべてに同じ仕組みで対応できる。既存の Hanasu の権限・署名・Gemini 設定もそのまま使える。
- 話者分離の弱点は、「マイク = 自分」と「システム音声 = 相手側」の 2 チャンネルに分けたうえで、相手側だけを話者分離モデルにかけて補う（後述）。

## 3. 要件

要件の一覧は [spec/meeting.md](../spec/meeting.md) に移した（初版の F1〜F10 → REQ-MTG-001〜010、非機能要件 → REQ-MTG-020〜025、対象外 → REQ-MTG-030〜033、F11〜F16 → REQ-MTG-011〜016）。

### 3.4 運用上の注意

- 録音は相手の同意を得てから行う。アプリは録音中であることをメニューバーに常に表示する（REQ-MTG-026）。
- 社内規程で会議の録音・外部 AI の利用が制限されている場合はそれに従う。

## 4. 技術選定

### 4.1 システム音声の取得: Core Audio Process Tap

| 方式 | 判定 |
| --- | --- |
| 仮想オーディオデバイス（BlackHole 等）に出力を回す | ✕ ドライバーのインストールと出力先の切り替えが要る。会議中に自分が音を聞けなくなる設定ミスが起きやすい |
| ScreenCaptureKit の音声キャプチャ | △ 動くが「画面収録」権限が要り、ユーザーに画面まで録られるように見える（会議の記録では画面収録の許可を求めない。REQ-MTG-030。Hanasu が画面収録を求めるのは、音声入力のスクリーンショットの文字をオンにしたときだけ） |
| **Core Audio Process Tap**（`AudioHardwareCreateProcessTap`、macOS 14.2+） | ◎ 採用。ドライバー不要。「システムオーディオ録音」の権限だけで、Mac が再生している音を横取りせずに複製して受け取れる |

実装の流れ:

1. `CATapDescription(stereoGlobalTapButExcludeProcesses: [自分のプロセス])` で、自分以外が鳴らす音全体のタップを作る（Granola と同じく、アプリを限定しない）。
   - 録るアプリは限定しない。会議アプリだけを録るモードは計画（[roadmap.md](../roadmap.md) FUT-201）。
2. `AudioHardwareCreateProcessTap` → タップを含む非公開の集約デバイスを `AudioHardwareCreateAggregateDevice` で作る。
3. `AudioDeviceCreateIOProcIDWithBlock` で音声バッファを受け取る。形式は `kAudioTapPropertyFormat` で取得。
4. Info.plist に `NSAudioCaptureUsageDescription`。初回に「システムオーディオ録音」の許可ダイアログが出る。

### 4.2 マイク

`AVAudioEngine` の入力ノード（音声入力機能と同じ）。

### 4.3 文字起こし: SpeechAnalyzer + SpeechTranscriber（チャンネルごと）

- 音声入力機能の検証で、`SpeechTranscriber` の方が発話を落とさなかったので、こちらを使う。
- マイク用とシステム音声用に 2 つの `SpeechAnalyzer` を並べて動かす。
- `attributeOptions: [.audioTimeRange]` を付けると、結果テキストの**語ごと**に時刻が付く。これを後で話者分離の結果と突き合わせて、語単位で話者を割り当てる（1 つの認識結果に複数の話者が混ざっていても分けられる）。
- 2 つのチャンネルの時刻は、録音開始時刻を 0 秒とした共通の時間軸にそろえる（`AnalyzerInput(buffer:bufferStartTime:)` に、そのチャンネルの開始のずれ＋累積サンプル数から計算した時刻を渡す）。

### 4.3.1 Whisper / Gemini を選んだとき（記録のあとに文字起こし）

設定の「AI」→「文字起こし AI」の「会議の記録」で、エンジンを Mac 標準 / Whisper / Gemini から選べる（音声入力とは別に選ぶ。理由と各エンジンの中身は [design/dictation.md](dictation.md) 4.10）。
Mac 標準は今までどおり（チャンネルごとの SpeechTranscriber でライブ文字起こし）。Whisper と Gemini は次のようにする。

- **記録中**: `ChannelTranscriber(live: false)` で、文字起こしはせず、チャンネルごとに 16 kHz モノラルの AAC（me.m4a / others.m4a。4.18 の断片化した m4a）に書き出すだけにする
  （相手側はステレオのことが多いので左右をまとめる）。音量の表示と「音が入っていません」の注意は今までどおり。
  - **記録中のライブ文字起こしは出さない。** 会議ノートの記録中の画面には「文字起こしは、記録を止めたあとに Whisper で行います」、字幕パネルには「記録を止めたあとに Whisper で文字起こしします」と出す。
    Whisper を数秒ごとに回すと会議中の CPU・電池の負担が大きく、Gemini で細かく送ると呼び出しの数と費用がかさむため。
  - エンジンは記録を始めたときの設定で決める（記録中に設定を変えても混ざらない）。始める前に、Whisper はモデルがあるか、Gemini は認証情報があるかを確かめ、なければ記録を始めずに理由を出す。
- **記録のあと**（`MeetingRecorder.transcribeRecordedAudio`）: チャンネルごとに音声ファイルを読み直し、時刻つきで文字起こしする。
  時刻には、そのチャンネルの音声が録音開始から何秒後に始まったか（`ChannelTranscriber.audioStartOffset`）を足し、Mac 標準と同じ共通の時間軸にする。
  結果は `TranscribedPhrase` にして、そのまま既存の後処理（FluidAudio の話者分離 → 時刻による話者の割り当て → 回り込みの除去）に渡す。
  - Whisper: 語ごとの時刻（word timestamps）を使うので、1 つの区間に複数の話者が混ざっていても、Mac 標準と同じく語の単位で分けられる。
  - Gemini: 区間（1 文か、話者が変わるところ）ごとの時刻だけなので、区間を 1 語として扱う。
- **Gemini で長い会議を送るとき**: 5 分ごとに分けて送る（目安の前 15 秒のうち、いちばん静かなところで切る。語の途中で切らないため）。最大 3 つを並行して送る。
  - 応答は JSON（`responseSchema` で `segments: [{start, end, text}]`）。時刻は `"MM:SS.s"` で、その区切りの先頭を 0 として書かせ、区切りの開始時刻を足して全体の時刻にする。
    時刻は区切りの長さに収め、終わりが始まりより前なら直す。
  - 音声は FLAC（16 kHz モノラル。5 分で 5 MB 前後。inline data の上限 20 MB に収まる）。無音だけの区切りは送らない。
  - 区切りを短く（30 秒）すると、先頭が無音の区切りで発話を丸ごと落とすことが検証で分かったので、短くしすぎない。
- **録音を消す会議のとき**: 音声ファイルを消すのは、今までどおり後処理の最後（文字起こし・話者分離・議事録のあと）。
  記録のあとの文字起こしは消す前に終わるので、順番は変えなくてよい。**文字起こしに失敗したチャンネルがあるときは、会議の値にかかわらず音声を残す**
  （あとで使えるように。くわしくは 4.17）。
- 権限: Whisper / Gemini では、音声認識の権限は求めない（マイクとシステムオーディオ録音だけ）。

### 4.4 話者分離

相手側（システム音声）の録音ファイルに対して、会議終了後にまとめて実行する。
（マイク側は「自分」なので分離しない）

| 候補 | 仕組み | 長所 | 短所 |
| --- | --- | --- | --- |
| **A. [FluidAudio](https://github.com/FluidInference/FluidAudio)（推奨）** | pyannote（speaker-diarization-community-1）を CoreML 化したもの。Apple Neural Engine で動く Swift パッケージ（Apache-2.0） | 音声を Mac の外に出さない。言語に依存しない。会議全体を 1 回で処理するので、話者番号が最後まで一貫する。公開値で DER 約 15%、実時間の 100 倍超の速さ | 外部パッケージの追加と、初回のモデルダウンロード（Hugging Face）が必要 |
| B. [Gemini 3.5 Transcribe](https://ai.google.dev/gemini-api/docs/transcribe.md.txt) の話者分離 | 音声ファイルを送ると、語ごとに `spk_1` などの話者と時刻が返る | 追加パッケージ不要 | 話者分離を使うと **1 回 30 分まで**、話者は 8 人まで（3 人以上は実験的）。長い会議は分割が要り、分割ごとに話者番号がずれる。音声を外部に送る。Vertex AI ではファイルを Cloud Storage に置く必要がある |
| C. 汎用 Gemini に音声を渡して「話者ごとに書き起こして」と頼む | プロンプトで指示 | 手軽 | 時刻や話者の一貫性が保証されない |

**採用: A（FluidAudio）**。利用者の承認を得て組み込んだ（2026-11-02）。

- バージョンは `0.17.7` に固定（2026-10-08 公開。公開直後の版は避けた）。
- `traits: []` を指定し、話者分離に不要なテキスト正規化のビルド済みバイナリ（NemoTextProcessing.xcframework, 87MB）をリンクしない。
- モデル（pyannote speaker-diarization-community-1 の CoreML 版）は初回の話者分離時に Hugging Face からダウンロードされ、以後はキャッシュを使う。
- 話者分離は差し替え可能な部品（`SpeakerDiarizer` プロトコル）にしてあり、失敗したときは「相手」1 人として扱って処理を続ける。

### 4.4.1 マイク側の話者分離（会議室など）

会議室から数人で参加し、1 つのマイクを共有する場合に備えて、設定「マイク側も話者を分ける」（初期値オフ）を用意した。

- オンにすると、マイクの録音（me.m4a）にも同じ話者分離をかける。
- マイク側で**話した時間がいちばん長い人を「自分」**、ほかを登場順に「同席者1」「同席者2」…（話者キー `room1`, `room2`）にする。
- 1 人で参加するときは、自分の声が 2 人に分かれる誤判定を避けるためオフのままにする。
- 議事録のプロンプトにも「同席者＝本人と同じ部屋で同じマイクを使う参加者」と説明を加えた。

合成音声での確認の結果は [verification/meeting.md](../verification/meeting.md) 5。

### 4.5 話者の割り当て

1. FluidAudio の結果 `[(speakerId, 開始秒, 終了秒)]` と、相手側の語ごとの時刻を突き合わせ、語の時刻を含む区間の話者を割り当てる。
   - 語の時刻は「語の終わり寄り 0.4 秒」の中央を使う（無音のあとの最初の語には無音の分まで長い時間が付くため）。
   - 区間と区間のすき間にある語は、前の区間の終わりから 0.3 秒以上あいて始まっていれば次の話者、そうでなければ前の話者にする（話者分離は話し始めの検出が 1 秒前後遅れることがあるため）。
2. 同じ話者が続く語をまとめて 1 発言にする。
3. マイク側の発言（話者 =「自分」）と時刻順に並べる。
4. 話者番号は登場順に「話者1」「話者2」…と付け直す。

### 4.6 スピーカーからの回り込み対策

イヤホンを使わないと、相手の声がスピーカーから出てマイクにも入り、「自分」の発言として二重に記録される。

- 推奨はイヤホン（設定画面とドキュメントで案内）。
- 後処理で、相手側に同じ時間帯・ほぼ同じ文字列の発言がある「自分」の発言を取り除く（時刻が重なり、文字の一致率が高いものを削除）。

### 4.7 議事録: Gemini（既存の認証設定を流用）

- 音声入力機能と同じ `GeminiClient`（API キー／サービスアカウント）を使う。
- 長い会議でも入る（1 時間の文字起こしは数万文字。Gemini の入力上限に十分収まる）。
- モデルは要約の質を優先して `gemini-3.8-flash` を初期値にする（音声入力と違って待ち時間が問題になりにくい）。
- 出力: 概要／話題ごとの要点／決定事項／TODO（担当・期限が分かれば）／話者についてのメモ（「話者1 は文中で『田中さん』と呼ばれている」など。推定であることを明記する）。
- 話者の名前（REQ-MTG-027）: 同じ応答の末尾の `<speaker_names>` で、会話から名前がはっきり分かる話者の名前を受け取る（`MinutesPrompt.speakerNamesInstruction`、DEC-MTG-068）。`SpeakerNameInference`（Mac: `SpeakerNameInference.swift`、Windows: `Hanasu.Core/Meetings/SpeakerNameInference.cs`）が名前を検査し、名前のない話者（「自分」を除く）にだけ付け、議事録の本文とアクションアイテムの担当のラベルも置き換え、`meeting.json` の `inferredSpeakers` に記録する（DEC-MTG-069）。会議ノートの話者名の欄に「推測」と出し、直すと外す。呼び出すのは `Meeting.applyMinutes`（記録のあとの議事録・作り直し・CLI）。

### 4.8 会議の自動検出（F9）

Granola・Notion AI Meeting Notes の「会議が始まると記録を勧める」、Krisp の会議の自動検出にならい、会議アプリがマイクを使い始めたら記録を提案する。
**自動では記録を始めない。** 必ずユーザーがボタンを押してから始める。

#### 検出のしかた

1. Core Audio のプロセスオブジェクト（`kAudioHardwarePropertyProcessObjectList`）から、各プロセスの `kAudioProcessPropertyBundleID`・`kAudioProcessPropertyPID`・`kAudioProcessPropertyIsRunningInput` を読む。
2. bundle ID の先頭で会議アプリを判別する。Chrome・Slack・Teams はマイクをヘルパー（`com.google.Chrome.helper` など）で使うので、実行ファイルのパス（`proc_pidpath`）からいちばん外側の `.app` を求め、その bundle ID でも判別する。

対象のアプリ（Zoom・Teams・Slack・Webex・FaceTime と、ブラウザの Chrome・Arc・Edge・Safari）と、見分けに使う bundle ID の先頭は `MeetingDetector.swift` の `MeetingApp`（DEC-MTG-031）。

- ブラウザは Google Meet かどうかまでは分からない（タブの URL は読まない）。ブラウザがマイクを使い始めたら「ブラウザの会議（Google Meet など）かもしれません」と提案する。
- `com.apple.WebKit.GPU` は Safari 以外の WebKit を使うアプリとも共通なので、それらがマイクを使っても Safari として提案されることがある。
- Hanasu 自身（音声入力・会議の記録）は PID で除く。

#### 監視: リスナー＋マイク使用中だけの読み直し

CPU の負荷を小さくするため、ポーリングを常には行わず、プロパティリスナーを基本にした。

| 見るもの | プロパティ | 用途 |
| --- | --- | --- |
| システムオブジェクト | `kAudioHardwarePropertyProcessObjectList`、`kAudioHardwarePropertyDevices` | プロセス・機器が増えた・減った |
| 会議アプリのプロセス | `kAudioProcessPropertyIsRunning`、`kAudioProcessPropertyIsRunningInput` | 入出力を始めた・止めた |
| 入力機器 | `kAudioDevicePropertyDeviceIsRunningSomewhere` | どこかのアプリがマイクを使い始めた・止めた |

macOS 26 で試したところ、`kAudioProcessPropertyIsRunningInput` / `IsRunningOutput` の変化はリスナーに届かず、`kAudioProcessPropertyIsRunning`（入力か出力のどちらか）だけが届いた（`afplay` で確認）。
これだと、すでに音を鳴らしているブラウザがマイクを使い始めても通知が来ない。そこで、**入力機器の `IsRunningSomewhere` が 1 の間（＝誰かがマイクを使っている間）だけ、3 秒おきに会議アプリの `IsRunningInput` を読み直す。**
マイクを誰も使っていない間はタイマーも動かさないので、待っている間の CPU 使用はほぼ 0。マイクを使っている間も、読むのは会議アプリの数個のプロセスの値だけ。

#### 提案のしかた

| 場面 | 動き |
| --- | --- |
| 対象のアプリがマイクを使い始めて 3 秒たった（記録していないとき） | 画面の右上に「会議を記録しますか？」（「記録する」「今回はしない」）。一瞬だけマイクを確かめるアプリでは出さない |
| 「記録する」 | 会議ノートを開いて記録を始める（メニューの「会議の記録を開始」と同じ） |
| 「今回はしない」 | その会議では聞かない。マイクを止めて 60 秒たつまでは、また使い始めても聞かない（ミュートでマイクを止めるアプリのため） |
| すでに記録中・準備中・処理中 | 開始の提案は出さない。記録を終えた時点でまだマイクを使っているアプリにも、改めて聞かない |
| 記録中に、記録中にマイクを使っていた会議アプリがすべてマイクを止めて 15 秒たった | 「記録を止めますか？」（「記録を止める」「続ける」）。15 秒以内にまた使い始めたら出さない |
| 「続ける」 | 記録を続ける。会議アプリがまたマイクを使ってから止めるまでは聞かない |
| 返事がないまま 2 分 | 「今回はしない」「続ける」として閉じる |

- パネルは `nonactivatingPanel` で前面に出ず、会議アプリのフォーカスを奪わない。全画面の会議アプリの上にも出る（`fullScreenAuxiliary`）。HUD と同じく、1 回のクリックで押せるように AppKit の部品ではなくボタンで作った。
- 通知センター（`UNUserNotificationCenter`）ではなくパネルにしたのは、通知の許可が要らないこと、通知を切っている・集中モードの人にも出ること、CLI で見た目を確かめられること、のため。
- 提案を出すときは、効果音の設定がオンなら `Glass` を鳴らす。
- 隠すときは、出していた提案も消す（「記録を止めますか？」の経過時間が、隠れたパネルの中で動き続けないように。DEC-COM-016）。

#### 設定（設定の「会議」→「会議の自動検出」）

- 「会議が始まったら記録を提案する」: **既定はオン。** 提案するだけで勝手に録音はしないこと、目的が「記録の始め忘れ」を防ぐことで、オフが既定だと気づかれないまま役に立たないこと、待っている間の負荷がほぼないこと、から。不要なら「今回はしない」か設定でオフにできる。
- 対象のアプリ（会議アプリ 5 つ、ブラウザ 4 つ）をそれぞれ選べる。既定はすべてオン。外したアプリを保存するので、あとで対象を足したときは既定でオンになる。
- 設定は共有の `AppSettings` を大きく変えないよう、`MeetingDetectionSettings`（UserDefaults の `meetingAutoDetect`、`meetingAutoDetectDisabledApps`）に分けた。

#### 会議の名前をタイトルにする（REQ-MTG-034）

記録の準備中（`MeetingRecorder.start`、状態は `.starting`）に、マイクを使っている会議アプリ（`MeetingAutoDetect.titleSourceApps`。AppDelegate が `MeetingRecorder.titleSourceApps` につなぐ）のウインドウのタイトルを `MeetingTitle.detect` で読み、取り出せた名前を `Meeting.title` にする。どの入口から始めても同じ。読めなければ今までの日時のタイトル。
取り出す規則と、名前とみなさないもの（DEC-MTG-035）は `MeetingTitle.swift`。ブラウザは、アクティブなタブのタイトルだけが読めるので、Meet のタブが裏にあるときは取れない。

#### 確認用の CLI

`MeetingDetectorCLI.swift`（`--check-meeting-title`・`--detect-meeting-title`・`--list-audio-processes`・`--watch-audio-processes`・`--simulate-meeting-detection`・提案のパネルの描き出し）。

### 4.9 会議中のメモと「ここ重要」の印（F11〜F14）

- **データ**: `MeetingNote`（`kind`: `note`／`highlight`、`time`: 録音開始からの秒数、`text`）。`Meeting.notes` に配列で持ち、`meeting.json` に一緒に保存する。
  `notes` は省略可（`Optional`）にして、メモ機能より前の `meeting.json` もそのまま読めるようにした。メモがあれば `notes.md` も書き出す。
- **メモの時刻**: 行を**書き始めた**時刻にする（Enter を押した時刻ではない）。聞いてから書き終えるまでの遅れで、時刻が実際の発言より後ろにずれるのを防ぐ。
- **印**: 押した時刻に付ける。メモ欄に書きかけの文があれば、その文を印の説明にする。ショートカット（初期値 `⌃⌥⌘ H`、設定で変更・無効化できる）は
  **記録中だけ登録する**。ほかのアプリのキーを普段は奪わず、会議ツールを前面にしたまま印を付けられる。押すと効果音（Morse）が鳴る。
- **印の取り消し**: 付けてから 10 秒のあいだは、メモ欄と字幕のパネルに出る「取り消す」（`HighlightUndoButton`。記録中だけ、0.5 秒ごとに残りの秒数を出し直す。DEC-COM-016）で消せる。
  対象は `Meeting.undoableHighlight(at:)` が返す、10 秒以内のいちばん新しい印だけ。それより古い印は、記録中は右クリックでも消せず、記録のあとに「メモ」タブで消す（DEC-MTG-047）。
- **印の前後の会話**: 会議ノートの文書の「ここ重要」の欄（`HighlightContextsSection`）が、`Meeting.highlightContexts()` で印ごとに 30 秒前〜15 秒後の発言を出す（議事録の ★ と同じ範囲。DEC-MTG-049）。「前後の会話を見る」で後ろ側のパネルの文字起こしのその発言へ移る。
- **会議ノートのウインドウの大きさ**: `AppDelegate.makeMeetingWindow` は `NSHostingController.sizingOptions` を空にし、最小の大きさ（1040×560）を `contentMinSize` で決める。中身に合わせると、メモのテキスト欄でウインドウが画面より伸びていた。後ろ側のパネル・帯・チャットの説明文は `fixedSize` にせず行数で抑える。左右に並べる画面が細い幅で最小の高さを測ると、1 文字ずつ折り返した高さを求めて、中身がウインドウからはみ出す（DEC-MTG-048）。
- **真ん中の画面の最小の大きさ**: `MeetingWindowView.splitView` は `NavigationSplitView` の真ん中に、幅・高さとも最小 0・最大無限の `frame` を付ける。真ん中の最小の大きさが中身（記録中の帯・文字起こし）で変わると、分割の列が制約の更新の最中にレイアウトをやり直し、収まらないと AppKit の例外でアプリが落ちる（DEC-MTG-155）。
- **テキスト形式**: 会議ノートでの編集・`notes.md`・CLI の `--notes` で同じ形式を使う。1 行 1 件で、`[12:34] 内容`（メモ）、`[12:40] ★ 説明`（印）、時刻なしの行（記録後に書き足したメモ）。
- **議事録への反映**（メモか印があるときだけ。ない会議の指示と入力は今までと同じ）:
  - 入力に `<user_notes>`（`[時刻] メモ` と `[時刻] ★ここ重要`）を足す。
  - 文字起こしのうち、印の **30 秒前〜15 秒後** にかかる発言の行頭に `★` を付けて渡す。印は大事な発言を聞いてから押すので、前を長めにとる。
    範囲の計算は Gemini に任せず、こちらで決めて印を付ける（時刻の計算をモデルに頼ると外れやすいため）。
  - 指示に「メモの点を優先して取り上げ、文字起こしで補う」「メモにしかない情報も『（メモより）』と添えて残す」「★ の話題は詳しめに、決定事項・TODO を拾う」
    「印があれば『## 重要とした箇所』を概要の次に置く」を足す。
- **記録後の編集**: 会議ノートの文書のメモの欄（`MeetingNotesSection` の中の `MeetingNotesEditor`）でテキストとして直し、「保存」か「保存して議事録を作り直す」。ツールバーの「議事録を作り直す」でも作り直せる。記録を止めたあとの処理の間は読むだけにする（4.16）。
  - 作り直している会議の ID は `MeetingRecorder.regeneratingID`。`MeetingDetailView` はその会議のときヘッダーの下に回る印と処理の文言を出し、`MeetingRow` は一覧の印を回る印にする。一覧の選択は、作り直しや記録のあとの処理が終わっても変えない（DEC-MTG-070）。
- **字幕（F14）**: 記録中の画面の文字起こし（F3）は前からある。そのデータ（確定した発言と途中結果）をそのまま使い、前面に浮かぶ小さなパネル
  （`NSPanel`、`.floating`、アプリをアクティブにしない）に直近 2 発言と途中結果を出す。パネルにも「ここ重要」ボタンを置いた。記録が終わると閉じる。
  文字起こしの仕組みに手を入れずに作れる。

### 4.10 議事録の型（テンプレート）

Granola のテンプレート（1on1・商談・採用面接など）にならい、会議の種類に合わせて議事録の見出しを変えられるようにした（`MinutesTemplate.swift`）。

型は 自動（初期値）・定例・1on1・商談・ブレスト・カスタム。型ごとの見出しの構成と指示の文面は `MinutesTemplate.swift` の `MinutesTemplate` と `MinutesPrompt.systemInstruction`（DEC-MTG-060）。

- どの型でも、最後に「アクションアイテム」（商談は「次のアクション」、ブレストは「次のステップ」）と「話者についてのメモ」の見出しを付ける。
- 選べる場面は 2 つ。
  - **記録を始める前**: 会議ノートの左下の「会議の記録を開始」の下の設定の 1 行を押して出るパネル（`RecordSettingsPopover`）の「議事録の型」。記録の開始時に会議へ記録する（`meeting.json` の `minutesTemplate` / `customMinutesPrompt`）。記録中は変えられない。
  - **あとから**: 会議ノートのツールバーの「型: 〇〇」メニューで型を選び直すと、確認のあと議事録を作り直す。失敗したときは型も議事録も元のまま。
- 選んだ型とカスタムの指示は UserDefaults（`meetingMinutesTemplate` / `meetingCustomMinutesPrompt`）に置く。設定画面には出さず、会議ノートだけで選ぶ。

#### 名前付きテンプレート

見出しの構成や書き方の指示に名前を付けて保存し、組み込みの型と並べて選べる（`SavedMinutesTemplates.swift`、`MinutesTemplateViews.swift`。REQ-MTG-042、DEC-MTG-076）。

- 保存したものの一覧は UserDefaults の `meetingSavedMinutesTemplates`（JSON）。型の選択欄には `saved:<ID>` の形で入る。
- 管理は選択欄の右のボタン、または会議ノートの「型」メニューの「テンプレートを管理…」から開く `MinutesTemplateManagerSheet`（追加・複製・削除・名前と指示の編集。保存できる内容なら自動で保存）。カスタムの指示のシートからも「テンプレートとして保存…」で登録できる。
- 記録を始めるとき、会議には型「カスタム」と、そのときの指示・名前（`meeting.json` の `customMinutesPrompt` / `minutesTemplateName`）を写す。以降は既存のカスタムと同じ流れで議事録を作る。テンプレートを直す・消しても記録済みの会議は変わらない。

#### アクションアイテムの取り出し

あとで書き出しやリマインダーに使うため、アクションアイテムは Markdown とは別に構造化して受け取る。

1. 議事録の「## アクションアイテム」の本文には目印 `{{ACTION_ITEMS}}` だけを書かせる。
2. Markdown のあとに `<action_items>` で囲んだ JSON 配列（`owner`・`task`・`due`（YYYY-MM-DD）・`due_note`（「来週中」などの言い方））を出させる。期限は会議の日時を基準に日付に直せるときだけ `due` に入れる。
3. アプリが JSON を読み取り、目印を `- [ ] 内容（担当: 〇〇 / 期限: 11/6 (金)）` の一覧に置き換える。構造化した一覧は `meeting.json` の `actionItems` に保存する。
4. JSON が壊れていたときは、議事録のチェックボックスの行から読み取る。この機能より前に作った議事録（「## TODO」の行）も同じ方法で読み取るので、古い会議もリマインダーに登録できる。

Gemini の JSON モード（`responseSchema`）は使わず、テキストの応答の末尾に JSON を付けさせた。議事録の Markdown と一緒に 1 回で受け取れ、他の機能と共有している `GeminiClient` を変えずに済むため。

### 4.11 書き出し

tl;dv や Fireflies の書き出し（Slack・タスク管理）にならい、会議ノートの「書き出し」メニューから次を行える（`MeetingExport.swift`・`ReminderExport.swift`）。

| 項目 | 内容 |
| --- | --- |
| Markdown でコピー | メニューの「議事録」「文字起こし」の節で選んだ方の Markdown（DEC-MTG-066）。議事録の根拠の時刻の印（`[12:34]`）は取り除く（`MinutesCitation.strip`、DEC-MTG-134） |
| Markdown ファイルとして保存… / テキストファイルとして保存… | 選んだ方を .md か .txt で保存（印は取り除く）。.txt は見出しを【】、箇条書きを「・」、チェックボックスを「□」にし、太字などの記号を外す |
| Slack 向けにコピー | 議事録（印を取り除いたもの）を Slack の mrkdwn に直す。タイトルと日時を先頭に置き、「話者についてのメモ」（推測の内部メモ）は除く。見出し → `*太字*`、箇条書き → `•`、チェックボックス → `☐`、リンク → `<url\|text>`。太字は前後が空白でないと効かないので、日本語の文中では前後に空白を入れる。貼り付けて送る前提なので `&` `<` `>` のエスケープはしない |
| アクションアイテムをリマインダーに登録… | 選んだものだけを EventKit でリマインダーに登録する |

リマインダーへの登録:

- 一覧の初期の選択は、まだ登録していない「自分」の担当か担当が決まっていないもの。ほかの人の担当は外しておく（自分で選べば登録できる）。
- タイトルはやること、メモに担当・期限の言い方・会議名と日時を書く。`due` があれば日付だけの期限（終日）を付ける。
- 登録したアイテムには `reminderID` を保存し、「登録済み」と表示して二重登録を避ける。
- 権限（リマインダーのフルアクセス）は、シートの「登録」を押したときに初めて求める。Info.plist に `NSRemindersFullAccessUsageDescription`、Hardened Runtime 用に `com.apple.security.personal-information.calendars` の entitlement を足した。許可済みなら登録先のリストを選べる。

### 4.12 録音する機器と、音が入っているかの確認

実機で何も録音されなかった問題（[verification/meeting.md](../verification/meeting.md) 4）を直したときに、次を足した。

- 設定「会議」→「録音するスピーカー」（初期値は Mac 全体の音。特定の出力機器だけをタップすることもできる）と「録音するマイク」（DEC-MTG-019）
- 記録中の画面に「自分」「相手」の音量メーター。始めてから 10 秒たっても一度も音が入らないチャンネルは警告を出す（DEC-MTG-020）
- `Hanasu --list-audio-devices` で機器の一覧（UID・サンプリングレート）と、会議の記録と同じ方法で作ったマイクの形式を表示
- 起動時に、アプリの終了などで「記録中」「処理中」のまま残った会議を「失敗」にする（DEC-MTG-018）
- タップの実際のサンプリングレートを測って合わせる（DEC-MTG-003）、マイクは機器の構成が変わったら作り直す（DEC-MTG-004）

### 4.13 会議中の AI チャット

記録中に、その時点までの記録をもとに AI と会話する機能（REQ-MTG-040・041）。ロジックは `MeetingChat.swift`（`MeetingChat`）、状態と画面は `MeetingChatView.swift`（`MeetingChatModel`・`MeetingChatStore`・`MeetingChatView`・`LiveSidePanel`）、確認用の CLI は `MeetingChatCLI.swift`。

- **画面の置き場所**: 記録中の画面（`LiveTranscriptView`）の右側のパネルを `LiveSidePanel` にし、上の切り替え（`LiveSidePanelModePicker`）で「メモ」（`LiveNotesPanel`）と「AI チャット」（`MeetingChatView`）を出し分ける。字幕と「ここ重要」のボタン（`LiveHighlightControls`）はどちらでも上に出す。選んだほうは `@AppStorage("meetingLiveSidePanel")` で覚える。⌘J で AI チャットにして入力欄にフォーカスする（DEC-MTG-080）。
- **チャットの欄**（上から）:
  - 会話を始める前: 何ができるかの説明と、よく使う質問のボタン（`MeetingChat.quickPrompts`。DEC-MTG-083）。
  - 会話: 質問は右に吹き出し、答えは左に `MarkdownText` で出す。答えの見出し（「AI」）の横に、その答えを作った AI とモデル（`MeetingChat.Message.modelLabel`）。答えの下に「12:34 までの記録から」（渡した記録の範囲）と「コピー」「メモに残す」。待っている間は「ここまでの記録を読んでいます…」（ローカルでほかの処理を待つときは「ほかの処理が終わるのを待っています…」）と「止める」。失敗したらその理由と「もう一度」。
  - 入力欄: ↩ で送る（`TextField` の縦に伸びる形）。待っている間は送信のボタンが止めるボタンに変わる。会話のあとは、入力欄の上によく使う質問を小さく並べる。下に送り先のメニュー（`AIRouteMenu`。4.13.1）と「新しい会話」、外に送るかと「会話は保存しません」の 1 行。
  - 既定の送り先が使えない（キーがない・モデルが未ダウンロードなど）ときは、欄の上に `AIRouteUnavailableNotice` で理由と直し方を出す（REQ-COM-025）。
- **送るもの**: 送るたびに `MeetingChat.liveMaterial` で、そのときの `MeetingRecorder.liveLines`（確定した発言）・`volatileMe`／`volatileOthers`（確定前の途中結果）・`Meeting.notesForPrompt()`（メモと印）を集め、`MeetingChat.prompt` でそれまでの会話と今の質問を足した 1 つの本文にして、送り先（`MeetingChatModel.effectiveChoice`: 画面で切り替えたもの、なければ設定の「AI チャット・質問」= `TextAIPurpose.chat`）に `TextAIClient.require(_:settings:for:)` で作ったクライアントの `generate`（effort は low）で送る（DEC-MTG-081）。答えの付かなかった質問は `MeetingChat.answeredTurns` で除く。長さの上限は `MeetingChat.Options`（DEC-MTG-082）。
- **Whisper / Gemini のとき**: 記録中は文字起こしがないので、メモと印だけで答えることを欄の上に出し、本文にもそう書く。
- **答えの中の時刻**: `MeetingChat.linkingTimes` で [12:34] を `hanasu-time://<秒>` のリンクにし、`OpenURLAction` で受けて、`MeetingChat.lineIndex` で探した発言へスクロールする。記録中は `followLatest` を止めて「最新の発言へ」のボタンを出す（DEC-MTG-084）。
- **会話の持ち方**: `MeetingChatStore.shared` が会議の ID ごとに `MeetingChatModel` を持つ（メモリだけ）。同じ ID なので、記録を止めて会議の詳細に変わっても、「AI チャット」タブ（`MeetingDetailView` の 5 つめのタブ）で同じ会話が続く。記録のあとは `MeetingChat.material(for:)` で確定した文字起こしと話者名を渡す（DEC-MTG-086）。取り消し（「止める」）は、送った質問を会話から外して入力欄に戻す。
- **メモに残す**: `MeetingChat.noteText` で答えを「AI: …」の 1 行にし、記録中は `MeetingRecorder.addNote`（質問した時刻）、記録のあとは `MeetingRecorder.updateNotes`（時刻なし）で足す（DEC-MTG-085）。
- **確認**: `--test-meeting-chat` は本文の組み立て・時刻のリンク・メモへの変換と、送り先の切り替え（`MeetingChatRouteTest`）を AI なしで確かめる。`--chat-meeting … --show-target` は AI を呼ばずに用途・AI・モデルを出す。`--chat-meeting <会議のフォルダ> --ask … --ask …` は保存した会議で実際の AI と会話し（`--at <時刻>` でその時刻までを記録中として渡す）、`--render-meeting-chat` は画面を PNG にする。
- **「何を聞かれた？」**（REQ-MTG-047）: 流れは `MeetingAskedQuestion.swift`（`MeetingAskedQuestion`）、前面のパネルとショートカットと設定の節は `MeetingAskedQuestionPanel.swift`（`MeetingAskedQuestionPanel`・`MeetingAskedQuestionView`・`MeetingAskedHotKey`・`MeetingAskedSettingsSection`）。
  - 入口は 3 つ: 字幕の「何を聞かれた？」（`MeetingCaptionView`）、記録中だけ登録するショートカット（`MeetingAskedHotKey`。「ここ重要」と共通の `MeetingRecordingHotKey`）、記録中のチャットのよく使う質問の先頭（`MeetingChat.askedPrompt`。`MeetingChat.quickPrompts(live:)` が記録のあとは外す）。どれも `MeetingAskedQuestion.ask(recorder:origin:)` を呼ぶ。
  - 渡すもの: `MeetingChat.liveMaterial` を `MeetingChat.askedMaterial` で直近 10 分（`askedWindow`）に切り、それまでの会話を付けずに `MeetingChat.prompt` で本文にする。省いた前の発言は `chat.transcript.recentOnly` で数だけ書く（DEC-MTG-095）。
  - パネル: `NonKeyPanel`（キーウインドウにならない `NSPanel`。`sharingType = .none`）に、見出し・`MeetingChat.recentOthers` の相手の直近の発言（AI を待たずに出す）・答え・ボタンを出す。オフレコ中（`Meeting.isOffRecord`）と相手の音が入っていないとき（`MeetingRecorder.othersSilent`）は知らせを出す（DEC-MTG-096）。
  - 会話への入れ方: ウインドウのチャット（`MeetingChatModel.send`）とは別の作業で聞き、答えが出たら `MeetingChatModel.insertAnsweredTurn` で組にして入れる。表示は `MeetingChat.Message.label`。押したあとに「新しい会話」を押したら `MeetingChatModel.generation` が変わるので入れない（DEC-MTG-098）。送り先は、その会議の AI チャットと同じ（`MeetingChatModel.effectiveChoice`。画面で切り替えていればそれ、なければ設定の「AI チャット・質問」。DEC-MTG-150）。
  - 「チャットで続ける」: `MeetingAskedQuestion.openChatRequest` を立てて `openMeetingWindow`（AppDelegate が入れる）を呼ぶ。会議ノートのウインドウ（`MeetingWindowView`）が受け取り、その会議を選び、後ろ側のパネルを出して AI チャットにし、入力欄にフォーカスを移す。
  - 確認: `--test-meeting-chat` に切り方・出し分け・会話への入れ方（`MeetingAskedQuestion.selfTest`。AI を呼ぶ部分 `reply` を差し替える）を足した。`--chat-meeting … --live --at … [--pending …] --quick asked` で記録中と同じ形を作って実際の AI に聞く。`--render-meeting-notes` でパネルの状態と設定の節を描く。

#### 4.13.1 送り先の切り替え

AI チャットと会議への質問（11.2）で、その会話・その画面だけ、送り先の AI とモデルを既定から変える（REQ-MTG-048・049、DEC-MTG-150）。部品は `AIRouteMenu.swift`。

- **一覧**: `AIRoute.sections(settings:)` が AI の並び（ローカル・Apple・Gemini・Claude。DEC-COM-168）で選択肢を作る。Gemini は `AppSettings.suggestedModels` に、設定の 3 用途の Gemini のモデルのうち一覧にないものを足す。Claude も同じ。先頭は「既定（<AI> · <モデル>）」。
- **使えるか**: `AIRoute.availability(settings:appleFMReason:)` が中身を読まずに調べる（Claude・Gemini のキーは `Keychain.exists`、サービスアカウントはファイルがあるか、ローカルは `LocalLLMStore.isDownloaded`）。Apple の判定（`AppleFMAvailability.check`）は署名を確かめるので、モデルが最初に 1 回だけして覚える。見直すのは、画面が出たとき・設定が変わったとき・どれかのウインドウが前に出たとき（`AIRoute.availabilityRefreshes`。キーの保存とモデルのダウンロードは設定の値を変えないので、設定の画面から戻ったことで拾う）・送る直前。使えない項目は理由を文字に入れて選べなくする。
- **持ち方**: AI チャットは `MeetingChatModel.override`（会議ごと。`MeetingChatStore` と同じくアプリを終了するまで。「新しい会話」では戻さない）。会議への質問は `MeetingAskModel.override`。会議のウインドウは閉じても残す作りなので、`MeetingWindowView` が `NSWindow.willCloseNotification` を受けて戻す。
- **送るとき**: `TextAIClient.make(_:settings:for:timeout:)` が選んだ AI とモデルのクライアントを作る（`fromSettings` もこれを使う）。ローカルなら `LocalLLMClient` にモデルを渡し、ほかは `generate` にモデル名を渡す。

### 4.14 記録中のスリープ

記録したままスリープした（MacBook を閉じた）ときに、復帰の直後に「スリープ前までで止める」か「記録を続ける」かを聞く（REQ-MTG-043）。

- **Mac**: `MeetingRecorder.observeSleep` が `NSWorkspace` の `willSleepNotification`・`didWakeNotification` を受ける。スリープの直前（`systemWillSleep`）に、経過時間と、チャンネルごとに書き終えた音声の終わり（`ChannelTranscriber.audioEnd`）を `MeetingSleepPoint` に覚える。復帰（`systemDidWake`）で、スリープしていた時間を `sleepGap` に足して経過時間（`MeetingRecorder.elapsed`）から除き、`askAboutSleep` で `NSAlert` を出す（DEC-MTG-087、DEC-MTG-089）。確認の間も記録は続く。
- **止めるとき**: `MeetingRecorder.stop(cutAt:)` が、`MeetingSleepCut` で音声ファイルを `AVAssetExportSession`（パススルー）で切り詰め、それより後に始まる発言を捨て、会議の長さ・印・メモを直してから、いつもの後処理に進む（DEC-MTG-088）。
- **Windows**: `AppHost.OnPowerModeChanged` が `MeetingController.OnSystemSuspend`・`OnSystemResume` を呼ぶ。スリープ中は `MeetingController.ElapsedSeconds` を止める（ループバックの無音の埋め合わせにスリープの時間が入らない）。復帰で `ResumedFromSleep` を出し、`AppHost.AskAboutSleep` が `SleepPromptWindow` で聞いて `ResolveSleepAsync` に渡す。止めるときは `WavStreamWriter.Truncate` で WAV を切り詰め、`MeetingSleepCut.Apply` で長さ・印・メモを直す（DEC-MTG-111）。
- **確認**: Mac は `--test-meeting-sleep-cut`（`MeetingSleepCLI.swift`）、Windows は `MeetingControllerTests` の `Sleep…` と `WavTruncateTests`。実際のスリープは実機で確かめる。

### 4.15 議事録に使う発言の選び方（範囲・除外・オフレコ）

文字起こしの最初と最後を選ぶ（REQ-MTG-044）、発言や話者を除く（REQ-MTG-045）、記録中にオフレコにする（REQ-MTG-046）。ロジックは `MinutesSelection.swift`、画面は `MinutesSelectionViews.swift`、確認用の CLI は `MinutesSelectionCLI.swift`。

- **持ち方**: `Meeting` の `minutesFrom`・`minutesTo`・`excludedUtterances`・`excludedSpeakers`・`offRecord`（`OffRecordSpan`）・`minutesOutdated`。`utterances` は書き換えない（DEC-MTG-090）。
- **決まり**: `Meeting.minutesUse(of:)` が発言ごとに `MinutesUse`（使う・除外・オフレコ・話者を除外・範囲外）を返す。`displayBlocks()` は `mergedBlocks()` と同じまとめ方で、使い方が変わるところでも分ける。`blocksForMinutes()` はその中の使うものだけ。
- **辞書の置き換え**: 確定した発言に、辞書の置き換えルールを当ててから議事録を作る。認識したままの文は `Utterance.rawText` に残し、会議ノートの辞書のメニューから当て直す・戻すことができる。作りは [dictation.md](dictation.md) の 5.6（REQ-DIC-073・074）。
- **使うところ**: `transcriptForPrompt`・`transcriptForPromptMarkingHighlights`（議事録・話者名の推測・会議への質問・辞書の候補）、`transcriptMarkdown`（書き出し・transcript.md。除いた件数を 1 行書く）、`MeetingChat.material`・`liveMaterial`（記録中はオフレコの区間の発言を除く）、`MeetingAsk.material` は `blocksForMinutes()` を使う。検索の索引（`MeetingSearch`）は `mergedBlocks()` のまま（DEC-MTG-091）。
- **会議ノート**: 後ろ側のパネルの文字起こしの上に `TranscriptSelectionBar`（数・「選ぶ…」／「選び終える」・すべて元に戻す、範囲・除いた話者・オフレコの区間のカプセルは `FlowLayout` で折り返す・作り直しの促し。DEC-MTG-137）。行は `TranscriptDisplayRow`（`TranscriptLine` に `use` を渡して薄く・取り消し線・理由のバッジ。右クリックとマウスを載せたときの「…」で `TranscriptLineMenu`。選ぶモードでは `TranscriptUseCheckbox`、Shift で前に押した行からまとめて）。変更は `MeetingRecorder.changeMinutesSelection` で保存し、記録中・処理中・作り直し中の会議は変えない。文書の上には作り直しを促す帯（`MeetingStatusBanners`。DEC-MTG-092、DEC-MTG-093、DEC-MTG-132）。
- **記録中**: `LiveTranscriptView` の上に `LiveOffRecordButton` と `LiveOffRecordBanner`。`MeetingRecorder.toggleOffRecord` が経過時間で区間を足して閉じ、すぐ保存する。止めたときに開いた区間を閉じ、スリープ前までで止めたときは `MeetingSleepCut.apply` が区間をそろえる（DEC-MTG-094）。
- **Windows**: `windows/Hanasu.Core/Meetings/MinutesSelection.cs` に同じ決まりを置き、会議ノートの文字起こしのタブを発言ごとの一覧にした（DEC-MTG-112）。
- **確認**: `--test-minutes-selection`（決まり・AI に渡す文字起こし・書き出し・meeting.json・スリープ）、`--render-minutes-selection <フォルダ>`（文字起こしの帯・チェックボックス・作り直しの促し・記録中のオフレコ）。

### 4.16 会議ノートの画面（文書・後ろ側のパネル・引用・再生）

2026-11-09 に作り直した（計画は [plans/meeting-notes-ui.md](../plans/meeting-notes-ui.md)、見本は [plans/meeting-notes-ui/](../plans/meeting-notes-ui/)。REQ-MTG-050〜054）。

- **組み立て**: `MeetingWindowView` が `NavigationSplitView`（左の一覧と真ん中）に `.inspector` を付ける（DEC-MTG-130）。真ん中は記録中なら `LiveMeetingView`（`LiveTranscriptView`）、記録した会議と処理中なら `MeetingDetailView`（`MeetingDocumentView` と下の `MeetingPlayerBar`、ツールバー）。後ろ側のパネルは記録中なら `LiveInspector`（`LiveSidePanel`）、それ以外は `MeetingDetailInspector`（`MeetingInspector`）。真ん中とパネルの間の状態（パネルのタブ・移る先・発言を選んでいるか・作り直しの確かめ）は `MeetingPanelState`。確認用の描き出しは `MeetingDetailPreview`・`LivePreview`（パネルを横に並べる）か、`MeetingDetailView` の CLI 向けの init（パネルも自分で付ける）。
- **macOS 26 の一覧とパネル**: 一覧とパネルは真ん中の上に重なり、真ん中は safe area で避ける。パネルを真ん中に付けたり、文書に `minWidth`・理想の幅を持たせたりすると、左右に並べる画面が一覧の幅を 2 回数えた最小の幅を求め、最小の大きさで中身がはみ出す。文書には `.frame(minWidth: 0, idealWidth: 0)` を付けている。再生のバーは狭いと `ViewThatFits` で時刻を外し、速さと消音をメニューにまとめる。
- **文書**: `MinutesDocument` が議事録の Markdown を節に分け、先頭のタイトル（`# …`）を出さず、最初の `## ` の節を要約に、アクションアイテムが取り出せていればその見出しの節を本文から外す（`ActionItemsCard` に出す）。行番号は議事録の中の番号のままなので、検索の飛び先（`MarkdownText.lineID`）は変わらない。外した節の行は `actionRow(forLine:)` でカードの行（`ActionItemsCard.rowID`）へ読み替える（DEC-MTG-133）。
- **状態の帯**: `MeetingStatusBanners` が進行中（`ProcessingStagesView`。`MeetingRecorder.processingStages`・`processingStage`）・作り直し中・失敗（`errorMessage`。「詳しく」「閉じる」、閉じた帯は `MeetingBannerDismissals` にアプリを終えるまで覚える）・古い議事録を、優先の順に 2 本まで出す（DEC-MTG-132、DEC-MTG-136）。記録中の警告とオフレコは `LiveTranscriptView` の上の `StatusBanner`。
- **引用**: 議事録のプロンプトの `minutes.citations`（Mac と Windows で同じ文面）で、要点の行末に `[12:34]`、アクションアイテムの JSON に `"at"` を付けさせる。`MinutesCitation` が印を読み、`MarkdownText.decorateCitations` が `hanasu-time://<秒>` のリンクの小さな印にする（会議の長さを 1 秒より多く超える時刻は取り消し線の灰色で、押せない）。押すと `MeetingDetailView.focusTranscript` → `MeetingPanelState.focus` → `MeetingTranscriptPanel` がその発言へ移って色を付ける。ローカル・Apple の AI で文字起こしを縮めて送ったとき（`LongInputFitter` が `LongInputReport` に書く）は、保存の前に印を取り除く（DEC-MTG-134）。
- **録音の削除**: 4.17。
- **再生**: `MeetingPlayer.shared` が `me.m4a`・`others.m4a` を `AVMutableComposition` の 2 つのトラックに、`meeting.json` の `audioStartOffsets`（記録を止めたときに書く。Windows と同じキー）だけずらして重ね、`AVPlayer` で鳴らす。消音は `AVAudioMix`、速さは `rate`（`.timeDomain`）。再生位置を 0.25 秒ごとに見て、`MeetingTranscriptPanel` が今の発言に「再生中」を付けてスクロールする（手でスクロールしたら止め、「再生位置へ」で戻る）。スペースキーは、会議ノートが前面で文字の入力欄にフォーカスがないときだけ、`NSEvent` の監視で受ける。記録・音声入力を始めたら止め、その間は押せない（DEC-MTG-135）。

## 5. アーキテクチャ

```
                         ┌───────────────────────── MeetingRecorder（司令塔）──────────────────────────┐
                         │                                                                             │
 マイク ── AVAudioEngine ─┼─▶ ChannelTranscriber「自分」 ── SpeechAnalyzer ──▶ 語＋時刻 ─┐              │
                         │        └─ AVAudioFile（me.m4a）                               │              │
                         │                                                               ├─▶ ライブ表示  │
 システム音声 ─ Process Tap┼─▶ ChannelTranscriber「相手」 ── SpeechAnalyzer ──▶ 語＋時刻 ─┘              │
 （集約デバイス＋IOProc）  │        └─ AVAudioFile（others.m4a）                                          │
                         └──────────────────────────────┬──────────────────────────────────────────────┘
                                                        │ 停止
                                                        ▼
                    後処理: 確定 → 話者分離（others.m4a）→ 話者割り当て → 回り込み除去 → 並べ替え → 辞書の置き換え（設定でオフにできる）
                                                        │
                                                        ▼
                                Gemini で議事録 → 保存（transcript.md / minutes.md / meeting.json）
```

### 5.1 状態遷移

```
idle ──開始──▶ starting ──（権限OK・タップ作成・認識開始）──▶ recording
recording ──停止──▶ finishing（認識の確定）──▶ processing（話者分離・議事録）──▶ idle
（Whisper / Gemini のときは processing の最初に「Whisper で文字起こししています…（自分）」などを挟む）
エラー時は idle に戻り、それまでの録音・文字起こしは保存する
録音から作り直すとき（4.18）: idle ──押して確かめる──▶ processing（文字起こし・話者分離・議事録。current は空のまま、recoveringID に会議）──▶ idle
```

### 4.17 録音を消す（会議ごと・あとから・保存期間）

2026-11-10 に足した（計画は [plans/meeting-audio-deletion.md](../plans/meeting-audio-deletion.md)。REQ-MTG-010・055〜057）。対象の選び方と判定は UI から切り離した `MeetingAudioCleanup.swift` にまとめ、`--test-meeting-audio` が一時フォルダで確かめる（本物の保存先と設定は触らない）。

- **会議ごとの値**: 記録を始めるとき `MeetingAudioPolicy.apply` が、設定 `keepMeetingAudio` の裏返しを `meeting.json` の `deleteAudioAfterTranscription`（true のときだけ）に写す。記録中のツールバーの `LiveDeleteAudioToggle` は `MeetingRecorder.setDeleteAudioAfterTranscription` で記録中の会議の値だけを変える。記録の設定のパネル（`RecordSettingsPopover`）と設定画面（`MeetingAudioSettingsRows`）は既定（設定）を変える（DEC-MTG-139）。
- **後処理で消すか**: `MeetingRecorder.process` の最後で `MeetingAudioPolicy.shouldDeleteAfterProcessing`（会議の値がオンで、文字起こしの状態が「すべて」）なら消す。文字起こしの状態（`MeetingAudioCleanup.transcriptState`）は、発言が 0 件なら「なし」、`transcriptionFailedChannels` があるか状態が失敗なら「一部」（DEC-MTG-142）。失敗したチャンネルは `MeetingRecorder.stop` が書く: Whisper / Gemini は `transcribeRecordedAudio` の失敗、Mac 標準は `ChannelTranscriber.recognitionFailed`（記録中に結果のストリームがエラーで止まった。取り消しと、止めるときの締めのエラーは数えない）。
- **あとから消す**: `MeetingRecorder.deleteAudio` が `MeetingAudioCleanup.deleteAudio`（`me.m4a`・`others.m4a`・`me.wav`・`others.wav` を `removeItem`。ないファイルは成功）を呼ぶ。記録中・処理中の会議（`current`）は飛ばす。`MeetingPlayer.shared` で読み込んでいれば止めて読み直し（音声がないのでバーが消える）、`audioRevision` を進めてメニュー・帯・件数を描き直す（DEC-MTG-140）。入口は会議ノートの一覧の右クリックと「…」の `MeetingMoreMenuItems`（`MeetingWindowView.confirmDeleteAudio` → `MeetingAudioDeleteText` の文で確かめる）。
- **「音声ファイルは残しています」**: エラーの文には書かず、`MeetingStatusBanners` が `MeetingAudioCleanup.showsAudioKept`（文字起こしがそろっていないか失敗で、録音がある）のときに帯を出す。録音を消せば消える。この機能より前の会議のエラーの文は書き換えない。
- **録音の管理**: `MeetingAudioManagerWindow`（`AppDelegate` が recorder を渡す）の `MeetingAudioManagerView`。`MeetingAudioManagerModel` が `MeetingAudioCleanup.entries`（録音が残る会議を新しい順に。記録中・処理中を除く）を裏で数え、`bulkTargets` で「30 日より前」「すべて」の対象と外す会議（文字起こしがそろっていない）を分ける（DEC-MTG-141）。
- **保存期間**: 設定 `meetingAudioRetentionDays`（0 は無期限）。`MeetingRecorder.pruneExpiredAudio` を、起動時（`AppDelegate` で `markInterruptedMeetings` のあと）と、`stop` で `process` が返ったあとに呼ぶ（`process` は CLI からも呼ばれるので、そこでは呼ばない）。設定で期間を短くして今すぐ消える録音があれば、`MeetingAudioSettingsRows` が確かめてから消す（DEC-MTG-143）。
- **消したファイル**: 完全に消すが、同期するフォルダ（iCloud Drive など）やバックアップには残ることがある（[security.md](security.md) 5）。

### 4.18 記録中に落ちた会議を、録音から戻す

- **録音の書き方**: `ChannelTranscriber` は録音を `MeetingAudioWriter` で書く。`AVAssetWriter` の m4a（AAC 32 kbps）で、`movieFragmentInterval` を 2 秒にして断片を閉じながら書くので、落ちても最後に閉じた断片まで開ける（`AVAudioFile` で書いた m4a は、閉じないと開けなかった）。正常に閉じたファイルは今までの m4a と同じに読める。`ChannelTranscriber` のキューではバッファを写して渡すだけにし、書き出しは専用のキューで、書き手の準備を 1 回 1 秒まで待つ。書き手が止まった・書いていない音が 30 秒ぶんを超えたら書くのをやめ、記録を止めたときにエラーの文に出す（DEC-MTG-156）。
- **先頭のずれ**: `ChannelTranscriber.knownStartOffset`（`levelLock` で読む）を、`MeetingRecorder.updateLevels` がチャンネルごとに 1 回、`meeting.json` の `audioStartOffsets` に保存する（DEC-MTG-157）。Windows は `MeetingController.PersistStartOffsetsIfKnown` を 1 秒ごとに UI のスレッドで呼ぶ。
- **終了するとき**: `AppDelegate.applicationShouldTerminate` が、記録中なら確かめて（ログアウト・再起動では確かめない）、`MeetingRecorder.closeForTermination` で録音を閉じてから終える。会議は「記録中」のまま残り、次の起動で `markInterruptedMeetings` が「失敗」にする（DEC-MTG-160）。
- **作り直すボタン**: `MeetingRecorder.canRecover` → `MeetingRecovery.canRecover`（発言 0 件・開ける m4a・処理中でない）。開ける録音の長さは `MeetingRecovery.readableAudioSeconds` がファイルの更新日時と大きさごとに覚えておく。ボタンは `MeetingStatusBanners` のエラーの帯と `MeetingMoreMenuItems` に出し、押すと `MeetingRecoveryPrompt` がエンジン名（Gemini なら Google に送ること）を書いた `NSAlert` で確かめ、`prepareRecovery`（`checkReady` と音声認識の許可）を通してから `recoverFromAudio` を呼ぶ。
- **作り直し**: `recoverFromAudio` は `recoveringID` に会議を入れ（`current` には入れない）、状態を `.processing` にし、`MeetingRecovery.prepared`（エラーの文を消し、長さとオフレコを録音から直す）で保存する。Mac 標準は `ChannelTranscriber.transcribe(file:…)` で録音を文字起こしに流す（`--meeting-files` と同じ関数。10 秒ごとに文字起こしの進み具合を見て、30 秒より遅れていれば待つ）。Whisper / Gemini は `transcribeRecordedAudio`。そのあと `process(…, recovering: true)` で、録音を消さず、`MeetingRecovery.statusAfterRecovery` で状態を決める（DEC-MTG-158）。会議ノートは `recoveringID` の会議を処理中の画面（`MeetingDetailView(processing: true)`）で出し、帯の見出しを「録音から作り直しています」にする。
- **Windows**: `MeetingController.RecoverFromAudioAsync` が、`WavStreamWriter.RepairHeader` で 2 つの WAV のヘッダーを直し（DEC-MTG-159）、`MeetingRecovery`（Core）を当てて、`CreatePostProcessor(…, keepAudio: true)` の後処理に渡す。ボタンは会議ノートの `RecoverButton`。

### 5.2 記録中に何度も変わる値

- **音量と途中結果**: `MeetingRecorder.updateLevels`（0.25 秒ごと）の音量と、`ChannelTranscriber.onVolatile` の途中結果は `MeetingLiveSignals`（`MeetingRecorder.signals`）に入れる。`MeetingRecorder` の `@Published` に置くと会議ノートの全体が描き直されるため（DEC-MTG-151）。これを `@ObservedObject` で見るのは `LiveLevelMeters`・`LiveVolatileLines`・`LiveTranscriptPlaceholder`・`MeetingCaptionView` だけ。記録中の値を足すときも、頻繁に変わるものはこちらに置く。
- **文字起こしに渡す単位**: `ChannelTranscriber.enqueueForAnalyzer` が、変換したバッファを `analyzerChunkSeconds` までためてから SpeechAnalyzer に渡す（DEC-MTG-152）。音声ファイルへの書き出しと音量の測定は、届いたバッファごと。

### 5.3 保存形式

```
~/Documents/Hanasu/Meetings/2026-11-02 1430 定例/
├── meeting.json      # メタデータ、話者名の対応表（と、会話から推測した話者 inferredSpeakers）、発言の配列（話者・開始・終了・本文）、議事録の型、アクションアイテム、録音を消すか（deleteAudioAfterTranscription）、文字起こしに失敗したチャンネル（transcriptionFailedChannels）
├── transcript.md     # [00:01:23] 話者1: …… の形式
├── minutes.md        # Gemini の議事録
├── notes.md          # 会議中のメモと「ここ重要」の印（あるときだけ。中身は meeting.json の notes と同じ）
├── me.m4a            # マイク（AAC 16kHz モノラル。2 秒ごとに断片を閉じる m4a で、落ちても直前まで開ける（4.18）。会議ごとに処理後に削除できる。文字起こしがそろっていないときは残す。あとから・保存期間でも消せる。4.17）
└── others.m4a        # システム音声
```

## 6. 画面

- **メニューバー**: 「会議の記録を開始／停止」（録音中は経過時間を表示し、アイコンを赤い丸にする）、「会議ノートを開く」。
- **会議ノート ウィンドウ**: 左に日付でまとめた会議の一覧、真ん中に選んだ会議の文書、後ろ側のパネルに文字起こし・AI チャット（4.16）。記録中は真ん中にライブの文字起こし、後ろ側のパネルに「メモ｜AI チャット」と「ここ重要」ボタン、ツールバーに記録中の印・音量・オフレコ・字幕。ツールバーで議事録の型の選び直し（4.10）・作り直し・辞書（[dictation.md](dictation.md) の 5.6）・書き出し（4.11）・「…」（話者名・Finder で表示・削除）。左下の「会議の記録を開始」と、その下の設定の 1 行で録音する機器と議事録の型を選ぶ。
  - タイトルは文書の先頭の欄（`EditableTitleField`）で書き換える。いつも薄い枠と鉛筆の印を出し、マウスを載せると枠を濃く、編集中はアクセントの色にする。Enter・フォーカスが外れたときに `MeetingRecorder.rename` で保存し、空なら元に戻す。Esc でやめる。別の会議を選んだときは、書きかけのタイトルを元の会議に保存してから切り替える（`MeetingDocumentView.commitTitle`）。ウインドウを開いたときに最初の入力欄としてフォーカスが入らないよう、すぐ外す。
  - 削除: 一覧の右クリックの「削除…」、一覧で ⌫、ツールバーの「…」の「削除…」から。確かめのダイアログのあと、`MeetingRecorder.delete` → `MeetingStore.moveToTrash` で会議のフォルダを丸ごとゴミ箱に移し（`FileManager.trashItem`）、一覧を読み直す（検索の索引も `recorder.$meetings` から更新される）。消したあとは一覧の次の会議を選ぶ。記録中・処理中の会議（`current`）と、議事録を作り直している会議（`regeneratingID`）は消せない。会議を書き換える `MeetingRecorder.update` は、フォルダがもうない会議を保存し直さない。
- **字幕パネル**: 記録中、ほかのアプリの前面に直近の発言を出す小さなパネル（記録中のツールバーの「字幕」で出す）。キーウインドウにならない（`NonKeyPanel`）。右に「何を聞かれた？」と「★」のボタン。出したまま記録を終えると、次の記録の開始で出す（`MeetingCaptionPanel.rememberedShown`。DEC-MTG-099）。
- **ショートカット**: 記録の開始／停止 `⌃⌥⌘ M`、「ここ重要」の印 `⌃⌥⌘ H`、「何を聞かれた？」`⌃⌥⌘ A`（あとの 2 つは記録中だけ有効）。どれも変更可。
- **提案のパネル**: 会議アプリがマイクを使い始めたら画面の右上に「会議を記録しますか？」、記録中に止めたら「記録を止めますか？」（4.8）。
  - 一覧の上に検索欄（`⌘F`）と「会議に質問」ボタン（✦）。詳しくは 11 章。

## 7. 権限

| 権限 | 用途 | 備考 |
| --- | --- | --- |
| マイク | 自分の声 | 音声入力機能で許可済み |
| システムオーディオ録音 | 会議ツールの音 | 新規。`NSAudioCaptureUsageDescription`。初回の記録開始時にダイアログ |
| 音声認識 | 文字起こし | 許可済み。Whisper / Gemini を選んだときは求めない |
| リマインダー | アクションアイテムの登録 | 新規。`NSRemindersFullAccessUsageDescription`。会議ノートで「登録」を押したときだけダイアログ |

会議の記録は画面収録の許可を使わない（REQ-MTG-030）。Hanasu が画面収録を求めるのは、音声入力のスクリーンショットの文字（REQ-DIC-041）をオンにしたときだけ。

## 9. 検証

検証のしかたと、日付の付いた結果（後処理・話者分離・実機で録音されなかった問題・自動検出・メモ・議事録の型）は [verification/meeting.md](../verification/meeting.md) に移した。

参考にしたもの: Granola の会議をまたいだチャット（「先週の定例で何が決まった？」）、Otter の検索。

### 11.1 全文検索

- 会議ノートの一覧の上の検索欄に語を入れると、一覧が検索結果に変わる。ヒットした会議（新しい順）と、その中のヒットした箇所（タイトル → 議事録の行 → 文字起こしの発言の時刻順）を並べる。
- 箇所を選ぶと、その会議を開き、議事録の行なら「議事録」タブ、発言なら「文字起こし」タブに切り替えて、その位置までスクロールする。箇所の背景と検索語に色を付ける。会議の見出しを選ぶと、会議を開くだけ。
- 検索の対象: タイトル、議事録（行ごと。先頭の `##`・`-`・`- [ ]` などは除く）、文字起こし（`mergedBlocks()` の発言ごと）。話者名は対象にしない（その人の全発言がヒットしてしまうため）。
- 空白で区切ると AND（同じ箇所に全部の語を含むものだけ）。大文字・小文字、全角・半角（英数字・カタカナ）の違いは無視する。ひらがな・カタカナの違いや、濁点の有無は区別する（「ガ」と「カ」を同じにすると誤ヒットが多い）。
- 1 つの会議から表示する箇所は 20 件まで（「ほか N 件」と出す）。`Esc` で検索をやめる。

**索引**: メモリ上の文字 2-gram の転置索引（`MeetingSearch.swift` の `MeetingSearchIndex`）。

- 日本語は語の区切りがないので、形態素ではなく「隣り合う 2 文字」ごとに、それを含む箇所の番号を持つ。検索語の 2-gram のうち候補がいちばん少ないものから候補を取り、最後に本当に検索語を含むかを確かめる。1 文字だけの検索語は全件を順に調べる。
- `MeetingRecorder.meetings` はもともと全会議をメモリに読み込んでいるので、索引もメモリに持ち、ファイルには保存しない。保存すると、Finder や他のツールで会議のファイルを直したときに索引とずれる心配が増えるため。
- 会議の一覧が変わるたびに、会議全体のハッシュを比べて、変わった会議の分だけ作り直す（バックグラウンドの actor で行い、画面は止めない）。消した箇所が半分を超えたら詰め直す。
- 大量の会議での索引づくりと検索の速さは [verification/meeting.md](../verification/meeting.md) 9。

### 11.2 会議への質問（Ask）

✦ ボタンで右側が質問の画面になる。質問を入れると、次の順で会議を集めて、設定の「AI チャット・質問」の AI とモデル（`TextAIPurpose.chat`。質問の欄の下の「送り先」で変えていればそれ。4.13.1）に渡す（DEC-MTG-053）。

1. 質問から検索語を取り出し（`NLTokenizer` で語に分け、ひらがなを含む語・1 文字の語・「会議」「先週」などの言い回しを除く。続けて出てくる語は「料金プラン」のようにつなげた語も使う）、ヒットした会議。ヒットした語が長い・多い会議を先にする。
2. 足りなければ直近の会議。
3. 質問に「今日」「昨日」「一昨日」「今週」「先週」「先々週」「今月」「先月」「11月2日」「11/2」があれば、その期間の会議に絞る（週は月曜始まり。期間に会議がなければ絞らない）。

渡す量の上限: 会議 8 件、本文の合計 15 万文字。会議ごとに、議事録があれば議事録と、検索でヒットした発言の前後 2 発言ずつ（6,000 文字まで）を渡す。議事録がなければ文字起こし（4 万文字まで。超えるときはヒットした発言の前後、ヒットがなければ冒頭）を渡す。

答えには、根拠の会議を文中で「［M1: 2026/11/02 定例］」の形で引用させ、最後に「## 根拠」を付けさせる。画面では、渡した会議の一覧を出し、引用された会議に印を付ける。選ぶとその会議を開く。
記録にないことは「記録からは分かりません」と答えさせ、会議の記録の中の指示には従わないよう指示する。会議の内容を送るのは、その送り先の AI だけ（ローカル・Apple なら Mac の外に送らない）。答えの下に、答えを作った AI とモデルを出す。

### 11.3 確認用の CLI

`MeetingSearchCLI.swift`（`--search-meetings`・`--ask-meetings`・`--write-sample-meetings`・画面の描き出し）。`--meetings-dir` を省くと `~/Documents/Hanasu/Meetings` を使うので、確かめるときは `--write-sample-meetings` で作った架空の会議のフォルダを渡す。

## 参考

- Apple: [Capturing system audio with Core Audio taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps) / [AudioHardwareCreateProcessTap](https://developer.apple.com/documentation/coreaudio/audiohardwarecreateprocesstap(_:_:))
- Granola: [Transcription](https://docs.granola.ai/article/transcription) / [Google Meet integration](https://granola.ai/blog/granola-google-meet-integration-recording-transcription)
- Recall.ai: [Desktop Recording SDK](https://www.recall.ai/product/desktop-recording-sdk) / [Desktop SDK vs native APIs](https://docs.recall.ai/docs/desktop-recording-sdk-vs-native-and-cross-platform-apis)
- FluidAudio: [GitHub](https://github.com/FluidInference/FluidAudio) / [Offline diarization pipeline](https://docs.fluidinference.com/diarization/offline-pipeline)
- Gemini: [Transcribe (Gemini 3.5 Transcribe)](https://ai.google.dev/gemini-api/docs/transcribe.md.txt)
- [Hyprnote の OSS 代替一覧](https://openalternative.co/alternatives/hyprnote)
