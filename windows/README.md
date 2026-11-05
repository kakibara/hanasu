# Hanasu for Windows

Mac 版 Hanasu（`Sources/Hanasu`）の Windows 版。タスクトレイに常駐し、ショートカットで録音して文字起こしし、AI（Gemini か Claude）で自然な日本語に整えて（または英訳して）カーソル位置に入力する。

- **音声入力**（第 1 段階）と、そのための土台（録音・文字起こし・Gemini・設定）
- **会議の記録**（第 2 段階）: マイク（自分）と PC の音（相手）を別々に録り、記録のあとに文字起こし・話者分離・議事録まで作る。Mac 版の会議の記録（[docs/design/meeting.md](../docs/design/meeting.md)）にそろえた

## 使い方

1. `Hanasu.exe` を起動すると、タスクトレイにアイコンが出る（初回は設定画面も開く）。
2. 設定 → AI で、音声入力と会議（議事録）に使う AI（Gemini / Claude）とモデルを選び、その認証を設定する。
   - Gemini: API キー（Google AI Studio）か、Vertex AI のサービスアカウントの JSON
   - Claude: API キー（[Claude Console](https://platform.claude.com/) で作る）。「接続を試す」で確かめられる（料金はかからない）
   - API キーは暗号化して保存する。「API キーを Windows Hello で守る」をオンにすると、使うときに PIN・顔・指紋で確認する（下の「セキュリティ」）
3. 入力したい場所にカーソルを置き、**Ctrl + Alt + Space** で録音を始める。画面の下に HUD が出る。
4. もう一度 **Ctrl + Alt + Space**（または HUD の「■ 停止」）で止めると、文字起こし → AI で整形 → 貼り付け まで進む。
   - **Ctrl + Alt + Shift + Space** で始めると翻訳して入力する（既定は英訳。設定 → 一般 →「翻訳する言語」で日本語も選べる）。録音中に HUD の「話した言語 / English（/ 日本語）」を押して切り替えてもよい（止めた時点の選択で決まる）。
   - 録音中は **Esc**（または HUD の「取消」）で取り消す。
   - 「押している間だけ録音」も選べる（設定 → 一般 → 録音のしかた）。
   - 入力できる場所にフォーカスがない（デスクトップが前面にある など）か、管理者として動いているアプリが前面にあって貼り付けられないときは、結果を画面の下に表示して残す（自動では閉じない）。「コピー」か文章を選んでコピーし、「閉じる」で閉じる。既定では結果をクリップボードにも入れておくので、貼りたい場所で Ctrl+V を押すだけでよい（設定 → 一般 →「入力できる場所がないとき」で、クリップボードを元のままにすることもできる）。
5. 結果と原文は履歴に残る（既定で 30 日。設定 → 履歴 で 7・30・90・365 日・無期限と、件数の上限を選べる）。
   - タスクトレイのメニュー →「最近の結果」から、直近 10 件をクリップボードにコピーできる。
   - タスクトレイのメニュー →「履歴を開く…」で、日ごとの一覧から検索（結果・原文・アプリ名）・「失敗・未整形」の絞り込み・結果や原文のコピー・削除（Delete キー）ができる。

### 会議の記録

1. 録音することを相手に伝える（同意を得る）。イヤホンを使うと、相手の声がマイクに回り込みにくい。
2. タスクトレイのメニュー →「会議ノートを開く」。左下で「自分（マイク）」「相手（この出力で鳴る音）」と「議事録の型」を選ぶ（初期値は Windows の既定の機器と「自動」）。
3. 「● 会議の記録を開始」か **Ctrl + Alt + Shift + M**（タスクトレイのメニュー「会議の記録を開始」でもよい）で始める。
   - 記録中は、会議ノートの左上に経過時間と「■ 停止」、右にメモ欄と「★ ここ重要」が出る。メモは Enter で足す（時刻は書き始めた時点）。
     「ここ重要」は **Ctrl + Alt + Shift + H**（記録中だけ有効）でも付けられる。書きかけのメモがあれば、その文を印の説明にする。
     押し間違えたときは、付けてから 10 秒のあいだ出る「★ を取り消す（あと N 秒）」で消せる（それより古い印は、記録のあとに「メモ」タブで消す）。
   - 記録中のライブの文字起こしはない（下の「会議の記録の作り」）。
4. もう一度 **Ctrl + Alt + Shift + M**（または「■ 停止」・メニューの「会議の記録を停止」）で止めると、
   「自分」「相手」の順に文字起こし → 相手側の話者分離 → AI（設定 → AI の「会議」）で議事録 まで進み、終わるとタスクトレイに知らせる。
5. 会議ノートで、議事録・文字起こし・ここ重要・メモのタブを見る。「ここ重要」タブには、印ごとにその前後（30 秒前〜15 秒後）の発言が出る。
   - 話者名: 議事録を作るときに、会話（名乗り・名前での呼びかけ）から名前がはっきり分かる話者には自動で名前が付き、欄の横に「推測」と出る（「自分」とユーザーが付けた名前は変えない）。「話者1」などの欄に名前を書くと、文字起こしと議事録の表示（と、作り直したときの議事録）に使う。直すと「推測」が消える。
   - 「議事録を作り直す」「型: 〇〇」（型を選び直して作り直す）、「Markdown をコピー」（表示中のタブ）、「エクスプローラーで開く」。
   - 「メモ」タブで記録後にメモを直し、「保存して議事録を作り直す」。
   - 題名は上の欄（枠と ✎ の印が出ている）で直せる。Enter かほかの所をクリックすると保存し、Esc でやめる。
   - 会議を消すには、一覧で選んで Delete キー・右クリックの「ごみ箱に移す…」か、上の「ごみ箱に移す…」。会議のフォルダをまとめてごみ箱に移す（ごみ箱から戻せる）。記録中・処理中・議事録を作り直している会議は消せない。
6. 設定 → 会議 で、文字起こしのエンジン（Whisper / Gemini）・ショートカット・話者分離・音声を残すか・保存先を変えられる。議事録の AI とモデルは 設定 → AI。

既定のショートカットは、Windows が使う組み合わせを避けて選んだ。

| 避けたもの | 理由 |
| --- | --- |
| Alt + Space | Windows のウインドウメニュー |
| Win + H | Windows の音声入力 |
| Win + Space | 入力言語の切り替え |
| Ctrl + Space / Shift + Space | 日本語入力のオン／オフ（IME による）、全角／半角スペース |
| Ctrl + Shift + M・Alt + M など（会議） | Teams・Zoom などの会議ツールのミュートなど。会議のショートカットは修飾キーを 3 つ（Ctrl + Alt + Shift）にした |

## 必要なもの

- Windows 10 バージョン 2004（ビルド 19041）以降、または Windows 11。x64
- 文字起こしのエンジンごとに:
  - **Windows 標準（既定）**: 日本語の音声認識（設定 → 時刻と言語 → 言語と地域 → 日本語 → 言語のオプション）と、「オンライン音声認識」をオンにすること（設定 → プライバシーとセキュリティ → 音声認識）。マイクは Windows の既定のマイクを使う
  - **Whisper**: Microsoft Visual C++ 再頒布可能パッケージ（2015〜2022, x64）と、AVX2 に対応した CPU（Whisper.net のランタイムの条件）。モデルは設定で選んだときにダウンロードする
  - **Gemini**: Gemini の認証情報（整形と同じもの）。録音した音声が Google に送られる
- 会議の記録: 文字起こしは Whisper（既定。モデルは「一般」タブで選んだもの）か Gemini。話者分離のモデル（約 34 MB）は初めて使うときにダウンロードする。議事録には、会議の AI（Gemini か Claude）の認証情報が要る
- Gemini の認証情報: API キー（[Google AI Studio](https://aistudio.google.com/apikey)）か、Vertex AI ユーザー（`roles/aiplatform.user`）のあるサービスアカウントの JSON 鍵
- Claude を使うとき: Claude API の API キー。Claude は文章の処理（整形・英訳・議事録）だけに使い、音声は送らない（文字起こしは Windows 標準・Whisper・Gemini）
- ローカルの LLM を使うとき（REQ-COM-030）: 設定 → AI で「ローカル」にし、モデル（Gemma 4 E4B 4.59 GB・LFM2.5-1.2B-JP 1.25 GB・Sarashina2.2 2.07 GB）をダウンロードする。CPU で動かすので、Gemma 4 E4B はメモリ 16 GB 以上が目安。文章は PC の外に送らない
- Windows Hello で API キーを守るとき: Windows Hello（PIN・顔・指紋）が設定されていること

## 構成

```
windows/
├── Hanasu.Windows.sln
├── Directory.Build.props        共通の設定（C# 12、Nullable、EnableWindowsTargeting など）
├── Hanasu.Core/                 net8.0。OS に依存しない部品（Mac でもテストできる）
│   ├── Ai/                      文章の処理の AI の共通の形（ITextGenerator）・用途ごとの選び方（TextAiFactory）・区切りのタグの無害化・ログの伏せ字
│   ├── Claude/                  Claude API（公式の C# SDK）での整形・英訳・議事録・エラーの分類・モデルの一覧
│   ├── Gemini/                  プロンプト（Mac 版と同じ文面。Claude にも同じものを送る）・REST クライアント・サービスアカウントの JWT（RS256）・認証の決め方
│   ├── Net/                     リダイレクトに従わない HttpClient・モデルのダウンロード（ハッシュの確認）
│   ├── Text/UserDictionary.cs   ユーザー辞書と置き換えルール（Mac 版の UserDictionary.swift の移植）
│   ├── Settings/                設定（settings.json）・ショートカットの組み合わせ・API キーの保存（SecretStore。DPAPI と Windows Hello はインターフェイスで渡す）
│   ├── Audio/                   16 kHz・モノラルへの変換（窓付き sinc の再サンプリング）・WAV・無音の判定・効果音
│   ├── Transcription/           文字起こしのインターフェイス・録ってからまとめて文字起こし・Gemini の文字起こし・Whisper のモデル管理
│   ├── Dictation/               音声入力の流れ（状態遷移）・整形と失敗時の扱い・履歴（DictationHistoryStore）・HUD の文言・貼り付け先の判定（PasteTarget）
│   └── Meetings/                会議の記録: データと meeting.json（Mac 版と同じ形）・保存・議事録の型とプロンプト（Mac 版と共有）・
│                                話者の割り当てと回り込みの除去・Gemini の時刻つき文字起こし・後処理・記録の流れ（MeetingController）
├── Hanasu.Whisper/              net8.0。Whisper.net（whisper.cpp）での文字起こし（会議用に時刻つきの区間も返す）
├── Hanasu.Diarization/          net8.0。sherpa-onnx での相手側の話者分離と、そのモデルのダウンロード
├── Hanasu.Windows/              net8.0-windows10.0.19041.0。WPF の本体（タスクトレイ・ホットキー・録音・HUD・設定画面）
│   ├── AppHost.cs               部品を組み立てる場所
│   ├── TrayIcon.cs              タスクトレイのメニュー（WinForms の NotifyIcon）
│   ├── Services/                RegisterHotKey、WASAPI の録音（NAudio。会議はマイクとループバック）、Windows の音声認識（WinRT）、
│   │                            クリップボード + SendInput の入力、貼り付け先の様子（FocusProbe）、前面アプリ、DPAPI・Windows Hello・DLL の探索・UIPI（WindowsSecurity）、効果音、ログ
│   └── Views/                   HUD（WS_EX_NOACTIVATE）・設定画面・会議ノート・音声入力の履歴・ショートカットの記録欄
├── Hanasu.Cli/                  net8.0。確認用の CLI（Mac でも動く）
└── Hanasu.Core.Tests/           xUnit。Mac でも Windows でも dotnet test で動く
```

### 音声入力の流れ

```
HotKeyService（RegisterHotKey + 離したかの見張り）
  └▶ DictationController（Core。idle → preparing → recording → processing → idle）
        ├─ IDictationTranscriber ─┬ WindowsSpeechTranscriber（連続認識。途中経過を HUD に出す）
        │                         └ RecordThenTranscribe ── WasapiRecorder（16 kHz・モノラル）
        │                                                └─ IBatchTranscriber ─┬ WhisperBatchTranscriber
        │                                                                     └ GeminiBatchTranscriber（inline data で WAV を送る）
        ├─ DictationTextProcessor（辞書の置き換え → 音声入力の AI（Gemini / Claude）で整形 / 英訳。認証がない・失敗したら原文を入れて知らせる）
        ├─ ClipboardTextInserter（修飾キーを離すのを待つ → 貼り付け先の確認 → クリップボード退避 → 文章 → Ctrl+V → 元に戻す）
        │     └─ 貼り付け先の確認: WindowsSecurity.IsHigherIntegrity（UIPI）→ FocusProbe（Win32・UI Automation）→ PasteTargetJudge（Core）
        └─ IHud ── HudWindow（録音中・経過時間・途中経過・処理中・完了・エラー・日本語/English・取消・■ 停止・貼り付けなかった結果）
```

- 状態遷移・HUD の文言・整形の失敗時の扱いは Core にあり、UI なしでテストしている（`DictationControllerTests`）。
- OS に依存する部品は `DictationServices` で渡す。Windows の部品は `AppHost.cs` で組み立てる。
- タスクトレイのメニューから始めると前面がタスクバーに移るので、`ForegroundWindowTracker` が覚えている直前のウインドウを前面に戻してから録音する。

#### 貼り付けられないとき（REQ-DIC-080・081）

- Ctrl+V を送る直前に、`FocusProbe` が前面のウインドウのクラス名・`GetGUIThreadInfo`（`hwndFocus`・`hwndCaret`）・フォーカスのある Win32 の入力欄の `ES_READONLY`・UI Automation の `FocusedElement`（ControlType・`ValuePattern.IsReadOnly`）を集め、Core の `PasteTargetJudge.Judge` が貼るかを決める。貼らないのは、前面のウインドウがない・デスクトップ・タスクバー・前面のスレッドにフォーカスがない・読み取り専用の入力欄・エクスプローラーのファイルの一覧、と分かったときだけで、分からなければ貼る（ブラウザ・Electron・Excel のセルなど。DEC-DIC-120）。
- UI Automation は、結果で判定が変わりうるとき（デスクトップ・タスクバー・エクスプローラー・フォーカスがない。`PasteTargetJudge.NeedsAutomation`）だけ、スレッドプールで問い合わせて 400 ms で打ち切る。キャレットがあるときも問い合わせない。ブラウザ・Electron で毎回待たず、Chromium のアクセシビリティを有効にさせないため（DEC-DIC-124）。
- 貼らないとき（権限の高いウインドウ・`SendInput` の失敗・クリップボードを使えない・例外も同じ。DEC-DIC-123）は、`DictationController.ShowUnpasted` が `HudPhase.Unpasted` を出し、`HudWindow` が広がって結果の全文・「コピー」「閉じる」を出す。自動では閉じず、次の音声入力の HUD で消える。文章をクリックしたときだけ前面に出して（選択・Ctrl+C・Esc のため）、閉じるときに入力先だったウインドウにフォーカスを返す（DEC-DIC-121）。
- クリップボードは `AppSettings.PasteFallbackClipboard` に従う。既定の `KeepResult` は結果を（履歴に残さない印を付けて）入れたままにし、`RestoreOriginal` は初めから触らない（DEC-DIC-122）。

#### 履歴（REQ-DIC-060・063）

- `DictationController` は、整形のあと貼り付けの前に `DictationHistoryStore.Record` で残す（入力先がずれても取り戻せるように。DEC-DIC-072）。状態（成功・AI 失敗・未設定・整形オフ）・入力先のアプリ・モデル・知らせたエラーも持つ。
- `DictationHistoryStore`（Core）は新しい順に持ち、日数と件数の両方の上限（設定の `HistoryMaxDays` 既定 30・`HistoryMaxCount` 既定 1000）を、追加・起動・設定の変更のときに当てて古いものから消す（DEC-DIC-073）。保存しない設定では、ファイルに書かずメモリに 10 件だけ置く（DEC-DIC-074）。
- `history.json` は Mac 版と同じ形（DEC-DIC-130）。タスクトレイの「最近の結果」は履歴の新しい順の 10 件（DEC-DIC-078）、`HistoryWindow` は日ごとの一覧・検索・絞り込み・コピー・削除（DEC-DIC-079・131）。

### 会議の記録の作り

```
MeetingController（Core。idle → starting → recording → processing → idle）
  ├─ 記録中: MeetingChannelRecorder ×2（Windows）
  │    ├ 自分: マイク（WasapiCapture）────────┐ 16 kHz・モノラルに変換（StreamingResampler）
  │    └ 相手: 出力のループバック（WasapiLoopbackCapture）┘ → ChannelTimeline で時刻をそろえる → WavStreamWriter（me.wav / others.wav）
  └─ 止めたあと: MeetingPostProcessor（Core）
       1. チャンネルごとに文字起こし（ISegmentTranscriber）
          ├ WhisperBatchTranscriber（語ごとの時刻つき）
          └ GeminiSegmentTranscriber（5 分ごとに区切り、JSON で区間を返させる。最大 3 つを並行）
          → 無音のところにかかった時刻を声のあるところへ寄せる（MeetingAudio.SnapToSpeech）→ チャンネルの開始のずれを足す
       2. 相手側の話者分離（SherpaSpeakerDiarizer。失敗したら「相手」1 人として続ける）
       3. 話者の割り当て・回り込みの除去（MeetingProcessor。Mac 版の移植）
       4. 会議の AI（Gemini / Claude）で議事録（MinutesPrompt。型・メモ・「ここ重要」・アクションアイテムの取り出し・会話から分かる話者の名前（SpeakerNameInference。REQ-MTG-027））
       5. 保存（MeetingStore: meeting.json・transcript.md・minutes.md・notes.md）。設定で音声を消す
```

- **2 つのチャンネルと時刻**: マイクとループバックを別々に録り、録音開始を 0 秒とした共通の時間軸にそろえる。
  チャンネルごとに「最初の音が録音開始から何秒後に届いたか」（開始のずれ）を `meeting.json` の `audioStartOffsets` に残し、文字起こしの時刻に足す。
  WASAPI のループバックは、PC が何も鳴らしていない間はデータを渡してこないので、届いた時刻と書いた長さの差が 0.25 秒より開いたら、その分の無音を足す（`ChannelTimeline`）。
- **録音はファイルに直接書く**: 音声入力の `WasapiRecorder` はメモリに溜めるが、会議は長いので 16 kHz・モノラル・16 bit の WAV に書きながら録る（1 時間で 1 チャンネル約 115 MB）。
  ヘッダーの長さの欄は 5 秒ごとに書き直すので、アプリが落ちても途中までの音声を読める。
- **文字起こしのエンジン**（設定 → 会議）: **Whisper（既定）か Gemini。Windows 標準は会議では選べない。**
  - 理由: Windows 標準の `SpeechRecognizer` は Windows の既定のマイクからしか聞けず、ループバックで録った PC の音（相手）を渡せない。
    「自分だけ Windows 標準・相手は Whisper」も考えたが、結局 Whisper のモデルが要るうえ、チャンネルで認識の質と時刻の精度がそろわず、選んだマイクも使えないので採らなかった。
  - Whisper のモデルは音声入力と共通（「一般」タブで選んだもの）。記録を始める前に、Whisper はモデルがあるか、Gemini は認証情報があるかを確かめ、なければ始めずに理由を出す。
  - **記録中のライブの文字起こしは出さない**（Mac 版で Whisper / Gemini を選んだときと同じ）。Whisper を数秒ごとに回すと会議中の CPU の負担が大きく、Gemini で細かく送ると呼び出しの数と費用がかさむため。
  - Whisper の語の時刻: トークンごとの時刻（t0/t1）を使う。日本語のトークンは 1 文字の途中で切れることがあり、Whisper.net はその断片を文字化け（U+FFFD）にして渡すので、
    前後の読めるトークンの位置から間の文字をまとめて 1 語にする。「(字幕)」のような括弧書きの注釈は除く。whisper.cpp の DTW の時刻も試したが、長い音声で途中から文字起こしが止まったので使っていない。
  - Gemini: Mac 版と同じく 5 分ごとに区切り（目安の前 15 秒のうち、いちばん静かなところで切る）、`responseSchema` で `segments: [{start, end, text}]` を返させる。音声は WAV（5 分で約 10 MB）。
- **話者分離**（設定 → 会議 →「相手側の話者を分ける」、既定でオン）: [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx)（Apache-2.0）の `OfflineSpeakerDiarization`。
  会議全体を 1 回で処理するので話者番号が最後まで一貫する。話者の数は決めず、声の特徴の近さ（しきい値 0.5）でまとめる。
  - モデルは初めて使うときに `%LOCALAPPDATA%\Hanasu\Models\diarization` にダウンロードする: pyannote segmentation-3.0 の ONNX 版（約 6 MB、MIT）と 3D-Speaker の CAM++（約 28 MB、Apache-2.0。中国語・英語の大量の話者で学習）。
  - 失敗したとき（ダウンロードできないなど）は、相手側を「相手」1 人にまとめて続け、タスクトレイで知らせる。
  - マイク側の話者分離（会議室で 1 つのマイクを共有する場合、Mac 版の「マイク側も話者を分ける」）は作っていない。
- **話者の割り当て**: Mac 版 `MeetingProcessor` の移植（語の終わり寄りの時刻で話者を決める、区間のすき間の扱い、登場順に話者1・話者2…）。Windows 版で 2 つだけ足した:
  - 1 つの発話を話者で分けたとき、端に残った 1 秒未満・4 文字以下のかけらは隣にまとめる（Whisper の語の時刻が少し遅れ、前の人の最後の語が次の人に付きやすいため）。
  - スピーカーからの回り込みの除去は、6 文字以上のかけらだけを対象にする（「ます」「ありますか」がたまたま似て消えるのを防ぐ）。
- **議事録**: 設定 → AI の「会議（議事録）」で選んだ AI とモデル（既定は Gemini の gemini-3.8-flash。Claude にすると既定は claude-sonnet-5-5）。プロンプト（型ごとの見出しと指示・メモと「ここ重要」の扱い・`{{ACTION_ITEMS}}` と `<action_items>` の JSON）は
  Mac 版の `MinutesTemplate.swift`・`MeetingNotes.swift` と同じ文面にし、共有している部分には「両方を直す」とコメントを書いた。
- **保存**: `MeetingStore`。`meeting.json` は Mac 版（`MeetingModels.swift`）と同じ JSON（キーは camelCase、列挙は小文字、日時は秒までの UTC、UUID は大文字、null は書かない）。
  Mac で作った会議のフォルダを保存先に置けば、そのまま会議ノートで開ける（`MeetingJsonTests`。Swift の Codable で Windows の `meeting.json` を読めることも確かめた）。
  Windows 版だけが書く `audioStartOffsets` は、Mac 版では読み飛ばされる。
- 音声入力と会議の記録は同時に動かさない（`DictationController.CanStart` / `MeetingController.CanStart`）。
- 起動時に、記録中・処理中のまま残った会議を「失敗」にする（音声は残る）。

## ビルド・テスト・配布

Windows でも Mac でも同じコマンドで動く（Mac は .NET SDK だけでよい。`Directory.Build.props` で `EnableWindowsTargeting` を有効にしてある）。

```bash
cd windows
dotnet build Hanasu.Windows.sln                   # すべてをビルド（Mac では WPF もコンパイルだけ通る）
dotnet test Hanasu.Core.Tests                     # テスト（Mac では .NET 10 で動くよう RollForward=Major にしてある）
```

配布物（リリースに添付するもの）:

```bash
cd windows
dotnet publish Hanasu.Windows/Hanasu.Windows.csproj -c Release -r win-x64 --self-contained -p:PublishSingleFile=true -o publish/win-x64
```

できるもの（`windows/publish/win-x64/`）:

```
Hanasu.exe                          本体（.NET ランタイム込み、約 82 MB。WPF のネイティブ DLL も中に入れてある）
sherpa-onnx-c-api.dll               話者分離（sherpa-onnx）のネイティブライブラリ
onnxruntime.dll                     その依存（ONNX Runtime）。exe に入れると一時フォルダに展開して読むことになり、
                                    Windows 11 の System32 にある別の版の onnxruntime.dll と取り違えるおそれがあるので、exe の隣に置く
runtimes/win-x64/whisper.dll        Whisper のネイティブライブラリ（exe には入れない。Whisper.net が exe の隣の runtimes/ から読むため）
runtimes/win-x64/ggml-whisper.dll
runtimes/win-x64/ggml-base-whisper.dll
runtimes/win-x64/ggml-cpu-whisper.dll
llama/llama-server.exe              ローカルの LLM を動かす llama.cpp（b11770）と、それが読む DLL（llama*.dll・ggml*.dll・libomp.dll など）。
llama/*.dll                         publish のあとに pwsh ../scripts/fetch-llama-cpp.ps1 -Destination publish/win-x64 で入れる（SHA-256 を確かめる）
```

**フォルダごと（`Hanasu.exe`・2 つの DLL・`runtimes/`・`llama/`）を zip にして配る。** `Hanasu.exe` だけを配ると、Whisper のエンジンと話者分離とローカルの LLM が使えない（Windows 標準と Gemini は動く。話者分離に失敗したときは相手側を「相手」1 人にまとめる）。
CI（`.github/workflows/windows.yml`）は同じコマンドで作り、`llama/` を足して、`Hanasu-windows-x64.zip`（中身は上のフォルダ）とその SHA-256（`Hanasu-windows-x64.zip.sha256`）を artifact に残す。
- ローカルの LLM（`LocalLlmServer`）は、使うときに `llama\llama-server.exe` を 127.0.0.1 の空いたポートで起動し、5 分使わなければ止める。Hanasu と一緒に終わるよう、ジョブオブジェクトに入れる（`ChildProcessJob`。DEC-COM-063）。Windows 版の配布物は CPU 版の llama.cpp なので、GPU は使わない。

ARM64 版は `-r win-arm64 -o publish/win-arm64` で同じ形のものができる（runtimes/win-arm64/ が付く。実機では確かめていない）。

### 確認用の CLI

Gemini の認証は環境変数 `GEMINI_SERVICE_ACCOUNT_JSON`（サービスアカウントの JSON のパス）か `GEMINI_API_KEY`。Claude は `ANTHROPIC_API_KEY`。

```bash
cd windows
dotnet run --project Hanasu.Cli -- refine "えーと明日の会議なんですけど" [--translate] [--model <id>] [--app Slack] [--dict <辞書ファイル>]
dotnet run --project Hanasu.Cli -- transcribe-gemini <wav> [--dict <辞書ファイル>]
dotnet run --project Hanasu.Cli -- transcribe-whisper <wav> --model tiny [--models-dir <dir>] [--download]
dotnet run --project Hanasu.Cli -- dictation <wav> --engine whisper|gemini [--translate] [--whisper-model tiny]
dotnet run --project Hanasu.Cli -- dict <辞書ファイル> "<文章>"
dotnet run --project Hanasu.Cli -- models

# Claude
dotnet run --project Hanasu.Cli -- claude-request "<文章>" [--translate | --minutes] [--model <id>]   # 送らずに、送る HTTP リクエストを出す（キーは伏せる。キーがなくても動く）
dotnet run --project Hanasu.Cli -- claude-refine "<文章>" [--translate | --translate-to en|ja] [--model <id>] [--app Slack]  # Claude で整形・英訳する（使ったトークンとキャッシュも出す）
dotnet run --project Hanasu.Cli -- claude-check [--model <id>] [--fake-key]                          # 「接続を試す」と同じ確かめ。--fake-key は偽のキーで 401 の文言を見る
dotnet run --project Hanasu.Cli -- local-list | local-download <id> | local-refine "<文章>" [--model <id>] [--server <llama-server>] [--models-dir <dir>]  # ローカルの LLM（Mac の llama-server でも動く）

# 会議の後処理（2 つの音声を「自分」「相手」として文字起こし → 話者分離 → 話者の割り当て → 議事録）。会議は --meetings-dir の下に作る
dotnet run --project Hanasu.Cli -- meeting-files me.wav others.wav --meetings-dir <保存先> [--engine whisper|gemini] [--whisper-model base] [--models-dir <dir>] [--download] \
    [--others-offset 1.5] [--template regular] [--notes notes.txt] [--no-minutes] [--no-diarize] [--diarization-models-dir <dir>] [--minutes-ai gemini|claude] [--minutes-model <id>] [--delete-audio]
dotnet run --project Hanasu.Cli -- meeting-minutes <会議のフォルダ> [--template sales] [--minutes-ai claude]   # 議事録を作り直す
dotnet run --project Hanasu.Cli -- meeting-show <会議のフォルダ>                        # meeting.json を読んで出す（Mac で作った会議が読めるかの確認）
```

`HANASU_DEBUG=1` を付けると、Whisper の区間と語の時刻、Gemini の応答を出す。`HANASU_GEMINI_CHUNK_SECONDS`（Gemini の区切りの長さ）と `HANASU_DIARIZATION_THRESHOLD`（話者分離のしきい値）で確認用に値を変えられる。

## 保存する場所

| もの | 場所 |
| --- | --- |
| 設定 | `%APPDATA%\Hanasu\settings.json`（JSON。壊れていたら `settings.json.broken` に退けて既定値で始める） |
| API キー（Gemini・Claude） | `%LOCALAPPDATA%\Hanasu\secrets.json` に、DPAPI（CurrentUser）か Windows Hello の鍵で暗号化して入れる。平文では保存しない。settings.json には入れない（PR #19 までの settings.json の `protectedApiKey` は、起動したときにそのまま移す） |
| サービスアカウント | JSON のパスだけを保存する（鍵の中身は写さない） |
| Whisper のモデル | `%LOCALAPPDATA%\Hanasu\Models\ggml-*.bin`（ダウンロード中は `.download`） |
| ログ | `%LOCALAPPDATA%\Hanasu\Logs\hanasu.log`（文字起こしの中身は書かない。API キーに見える文字列は伏せる） |
| 音声入力の履歴 | `%LOCALAPPDATA%\Hanasu\History\history.json`（Mac 版と同じ形の JSON。一時ファイルに書いてから置き換える。読めなければ `history.json.broken` に退けて新しく始める）。設定 → 履歴 で保存しないにすると、直近 10 件だけをメモリに置く |
| 会議の記録 | `ドキュメント\Hanasu\Meetings\<yyyy-MM-dd HHmm>\`（設定 → 会議 で変えられる）。`meeting.json`・`transcript.md`・`minutes.md`・`notes.md`・`me.wav`・`others.wav` |
| 話者分離のモデル | `%LOCALAPPDATA%\Hanasu\Models\diarization\*.onnx` |
| ローカルの LLM のモデル | `%LOCALAPPDATA%\Hanasu\Models\llm\*.gguf`（ダウンロード中は `.download`） |

## Mac 版との差

| 機能 | Windows 版 |
| --- | --- |
| 音声認識 | Windows 標準（`Windows.Media.SpeechRecognition`）・Whisper・Gemini から選ぶ。Mac 版の SpeechAnalyzer の代わり |
| 入力 | クリップボード + `SendInput` の Ctrl+V。クリップボードの履歴（Win+V）とクラウド同期に残さない印を付ける |
| アプリ別スタイル | **未実装**（入力先アプリ名を AI に伝えるだけ） |
| スニペット | **未実装** |
| 画面の文脈 | **未実装** |
| 履歴ウインドウ | 検索・絞り込み・コピー・削除はできる。**整え直し（整形し直す・英訳し直す）と録音の保存は未実装** |
| 最後の結果をもう一度入力（`⌥⇧ V`） | **未実装**（「最近の結果」からコピーして貼る） |
| 選択を声で編集 | **未実装** |
| 辞書の候補を探す（AI で提案） | **未実装**（辞書の編集と置き換えの試しはできる） |
| 会議の記録 | 作った（下の表は会議の記録での差） |

会議の記録での差:

| 機能 | Windows 版 |
| --- | --- |
| 相手の音 | Core Audio Process Tap の代わりに WASAPI ループバック（選んだ出力の機器で鳴る音すべて）。Hanasu 自身の音を除く仕組みはないので、会議中は効果音を鳴らさない |
| 文字起こし | Whisper（既定）・Gemini。**Windows 標準は選べない**（ループバックの音を渡せないため）。Mac 版の「Mac 標準」のような記録中のライブの文字起こしはない |
| 字幕パネル（前面に浮かぶ直近の発言） | **なし**（ライブの文字起こしがないため） |
| 話者分離 | FluidAudio の代わりに sherpa-onnx（pyannote segmentation-3.0 + 3D-Speaker CAM++）。**マイク側の話者分離（同席者）は未実装** |
| メモと「ここ重要」 | 作った（記録中のメモ欄・ボタン・ショートカット・付けてから 10 秒の取り消し、記録後のメモの編集と作り直し）。記録中にメモを消す右クリックの「削除」はない。印の効果音は鳴らさない（ループバックに入るため） |
| 議事録の型・アクションアイテム | 作った（Mac 版と同じプロンプト） |
| 音声ファイル | AAC（m4a）ではなく WAV（me.wav / others.wav）。Mac で作った会議の音声（m4a）は Windows 版では文字起こしし直せない（会議ノートで読むのはできる） |
| 書き出し | 「Markdown をコピー」だけ。**ファイルとして保存・Slack 向けのコピー・リマインダーへの登録は未実装**（`reminderID` は読み書きで落とさない） |
| 会議の自動検出（会議アプリがマイクを使い始めたら知らせる） | **未実装** |
| 会議の横断検索・会議への質問（Ask） | **未実装** |

## セキュリティ

詳しくは [docs/design/security-windows.md](../docs/design/security-windows.md)。

- **API キー**: 既定の DPAPI は、この Windows ユーザーでしか読めないが、**同じユーザーで動くほかのアプリは確認なしに読める**（署名もパッケージ化もしていないアプリは、Windows に見分けてもらえないため）。
  設定 → AI →「API キーを Windows Hello で守る」をオンにすると、ほかのアプリが読もうとすると Windows Hello の確認が出る。確認は起動してから最初に使うとき 1 回で、画面をロックするとまた求める。Hanasu が動いている間のメモリまでは守れない。
- **配布物は署名していない**。初めて起動すると SmartScreen が「Windows によって PC が保護されました」と出す。ダウンロードした zip の SHA-256 を、リリースの `.sha256` と比べてから使う（PowerShell: `Get-FileHash Hanasu-windows-x64.zip`）。
- **zip は専用のフォルダに展開する**（「ダウンロード」フォルダの直下で展開しない）。exe は起動するときに同じフォルダの DLL を読むことがあり、知らない DLL が混ざっていると乗っ取られるおそれがある。
- 管理者として動いているアプリには貼り付けを送らない（届かないので）。入力できる場所がないときと同じく結果を画面に残す（既定ではクリップボードにも残すので、Ctrl+V で貼る）。
- モデルは決まったホストから取り、SHA-256 を確かめてから使う。

## 依存パッケージ

| パッケージ | 使う場所 | ライセンス |
| --- | --- | --- |
| [NAudio.Wasapi](https://github.com/naudio/NAudio) 2.2.1（と NAudio.Core） | マイクの録音（WASAPI） | MIT |
| [Whisper.net](https://github.com/sandrohanea/whisper.net) / Whisper.net.Runtime 1.9.1（whisper.cpp を含む） | Whisper の文字起こし | MIT（whisper.cpp も MIT） |
| System.Security.Cryptography.ProtectedData 8.0.0 | API キーの DPAPI 暗号化 | MIT |
| [Anthropic](https://github.com/anthropics/anthropic-sdk-csharp) 13.4.0（公式の C# SDK。Microsoft.Extensions.AI.Abstractions・System.Text.Json などを含む） | Claude API | Apache-2.0（依存は MIT） |
| xunit 2.9.3 / xunit.runner.visualstudio 2.8.2 | テストのみ | Apache-2.0 |
| Microsoft.NET.Test.Sdk 17.14.1 | テストのみ | MIT |
| [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx)（org.k2fsa.sherpa.onnx 1.13.8、ONNX Runtime を含む） | 会議の相手側の話者分離 | Apache-2.0（ONNX Runtime は MIT） |

配布物には、Hanasu のライセンス（`LICENSE.txt`・`LICENSE-ADDITIONAL-PERMISSION.md`・`NOTICE.txt`）と、これらの第三者のライセンスの表示（[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)、.NET ランタイムの `dotnet-THIRD-PARTY-NOTICES.txt`）を入れる。依存パッケージを足したら、THIRD_PARTY_NOTICES.md にも足すこと。
依存の版とハッシュは各プロジェクトの `packages.lock.json` に固定している（CI は locked mode）。パッケージを足したり版を変えたりしたら、`dotnet restore` で lock ファイルを作り直してコミットする。

Whisper のモデル（`ggml-*.bin`）は配布物に含めず、利用者が選んだときに [Hugging Face の ggerganov/whisper.cpp](https://huggingface.co/ggerganov/whisper.cpp) からダウンロードする（OpenAI の Whisper のモデル、MIT）。
話者分離のモデルも配布物に含めず、初めて使うときにダウンロードする: [pyannote segmentation-3.0 の ONNX 版](https://huggingface.co/csukuangfj/sherpa-onnx-pyannote-segmentation-3-0)（MIT）、
[3D-Speaker の CAM++](https://github.com/k2-fsa/sherpa-onnx/releases/tag/speaker-recongition-models)（`3dspeaker_speech_campplus_sv_zh_en_16k-common_advanced.onnx`、Apache-2.0）。
