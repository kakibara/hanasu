# Hanasu for Windows

Mac 版 Hanasu（`Sources/Hanasu`）の Windows 版。タスクトレイに常駐し、ショートカットで録音して文字起こしし、Gemini で自然な日本語に整えて（または英訳して）カーソル位置に入力する。

- 第 1 段階（このフォルダの今の中身）: **音声入力**と、そのための土台（録音・文字起こし・Gemini・設定）
- 第 2 段階（これから）: **会議の記録**。土台の部品をそのまま使えるように分けてある（下の「会議の記録を足すとき」）

## 使い方

1. `Hanasu.exe` を起動すると、タスクトレイにアイコンが出る（初回は設定画面も開く）。
2. 設定 → Gemini で、API キー（Google AI Studio）か、Vertex AI のサービスアカウントの JSON を設定する。
3. 入力したい場所にカーソルを置き、**Ctrl + Alt + Space** で録音を始める。画面の下に HUD が出る。
4. もう一度 **Ctrl + Alt + Space**（または HUD の「■ 停止」）で止めると、文字起こし → Gemini で整形 → 貼り付け まで進む。
   - **Ctrl + Alt + Shift + Space** で始めると英訳して入力する。録音中に HUD の「日本語 / English」を押して切り替えてもよい（止めた時点の選択で決まる）。
   - 録音中は **Esc**（または HUD の「取消」）で取り消す。
   - 「押している間だけ録音」も選べる（設定 → 一般 → 録音のしかた）。
5. タスクトレイのメニュー →「最近の結果」から、直近 10 件をクリップボードにコピーできる（メモリ上だけ。終了すると消える）。

既定のショートカットは、Windows が使う組み合わせを避けて選んだ。

| 避けたもの | 理由 |
| --- | --- |
| Alt + Space | Windows のウインドウメニュー |
| Win + H | Windows の音声入力 |
| Win + Space | 入力言語の切り替え |
| Ctrl + Space / Shift + Space | 日本語入力のオン／オフ（IME による）、全角／半角スペース |

## 必要なもの

- Windows 10 バージョン 2004（ビルド 19041）以降、または Windows 11。x64
- 文字起こしのエンジンごとに:
  - **Windows 標準（既定）**: 日本語の音声認識（設定 → 時刻と言語 → 言語と地域 → 日本語 → 言語のオプション）と、「オンライン音声認識」をオンにすること（設定 → プライバシーとセキュリティ → 音声認識）。マイクは Windows の既定のマイクを使う
  - **Whisper**: Microsoft Visual C++ 再頒布可能パッケージ（2015〜2022, x64）と、AVX2 に対応した CPU（Whisper.net のランタイムの条件）。モデルは設定で選んだときにダウンロードする
  - **Gemini**: Gemini の認証情報（整形と同じもの）。録音した音声が Google に送られる
- Gemini の認証情報: API キー（[Google AI Studio](https://aistudio.google.com/apikey)）か、Vertex AI ユーザー（`roles/aiplatform.user`）のあるサービスアカウントの JSON 鍵

## 構成

```
windows/
├── Hanasu.Windows.sln
├── Directory.Build.props        共通の設定（C# 12、Nullable、EnableWindowsTargeting など）
├── Hanasu.Core/                 net8.0。OS に依存しない部品（Mac でもテストできる）
│   ├── Gemini/                  プロンプト（Mac 版と同じ文面）・REST クライアント・サービスアカウントの JWT（RS256）・認証の決め方
│   ├── Text/UserDictionary.cs   ユーザー辞書と置き換えルール（Mac 版の UserDictionary.swift の移植）
│   ├── Settings/                設定（settings.json）・ショートカットの組み合わせ・秘密の値の暗号化のインターフェイス
│   ├── Audio/                   16 kHz・モノラルへの変換（窓付き sinc の再サンプリング）・WAV・無音の判定・効果音
│   ├── Transcription/           文字起こしのインターフェイス・録ってからまとめて文字起こし・Gemini の文字起こし・Whisper のモデル管理
│   └── Dictation/               音声入力の流れ（状態遷移）・整形と失敗時の扱い・最近の結果・HUD の文言
├── Hanasu.Whisper/              net8.0。Whisper.net（whisper.cpp）での文字起こし
├── Hanasu.Windows/              net8.0-windows10.0.19041.0。WPF の本体（タスクトレイ・ホットキー・録音・HUD・設定画面）
│   ├── AppHost.cs               部品を組み立てる場所
│   ├── TrayIcon.cs              タスクトレイのメニュー（WinForms の NotifyIcon）
│   ├── Services/                RegisterHotKey、WASAPI の録音（NAudio）、Windows の音声認識（WinRT）、
│   │                            クリップボード + SendInput の入力、前面アプリ、DPAPI、効果音、ログ
│   └── Views/                   HUD（WS_EX_NOACTIVATE）・設定画面・ショートカットの記録欄
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
        ├─ DictationTextProcessor（辞書の置き換え → Gemini で整形 / 英訳。認証がない・失敗したら原文を入れて知らせる）
        ├─ ClipboardTextInserter（クリップボード退避 → 文章 → Ctrl+V → 元に戻す）
        └─ IHud ── HudWindow（録音中・経過時間・途中経過・処理中・完了・エラー・日本語/English・取消・■ 停止）
```

- 状態遷移・HUD の文言・整形の失敗時の扱いは Core にあり、UI なしでテストしている（`DictationControllerTests`）。
- OS に依存する部品は `DictationServices` で渡す。Windows の部品は `AppHost.cs` で組み立てる。
- タスクトレイのメニューから始めると前面がタスクバーに移るので、`ForegroundWindowTracker` が覚えている直前のウインドウを前面に戻してから録音する。

### 会議の記録を足すとき

次の部品をそのまま使える。

| 部品 | 会議の記録での使い道 |
| --- | --- |
| `IAudioRecorder` / `WasapiRecorder` | マイク（自分）の録音。`SamplesAvailable` で録りながら 16 kHz・モノラルの音声を受け取れる。システム音声（相手）は NAudio の `WasapiLoopbackCapture` で同じ形のクラスを作る（`StreamingResampler` と `SampleConversion` をそのまま使える） |
| `IBatchTranscriber`（Whisper / Gemini） | 区切った音声の文字起こし。Whisper のモデルは `WhisperModelManager` で共通（同じ `%LOCALAPPDATA%\Hanasu\Models`）。`WhisperBatchTranscriber` は読み込んだモデルを使い回す |
| `GeminiClient.GenerateAsync` | 議事録づくり（`systemInstruction` と parts を渡すだけ。`Timeout` は長めにする）。`responseMimeType` に `application/json` も渡せる |
| `GeminiAuthResolver` / `SettingsService` | 認証と設定は音声入力と共通。会議の設定は `AppSettings` に足す（`SettingsStore.Normalize` で既定値を補う） |
| `HotKeyService` | 会議の開始・停止のショートカット |
| `AppHost` | `MeetingController` などをここで作り、`DictationController.CanStart` で音声入力と同時に動かないようにする |

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
Hanasu.exe                          本体（.NET ランタイム込み、約 78 MB。WPF のネイティブ DLL も中に入れてある）
runtimes/win-x64/whisper.dll        Whisper のネイティブライブラリ（exe には入れない。Whisper.net が exe の隣の runtimes/ から読むため）
runtimes/win-x64/ggml-whisper.dll
runtimes/win-x64/ggml-base-whisper.dll
runtimes/win-x64/ggml-cpu-whisper.dll
```

**フォルダごと（`Hanasu.exe` と `runtimes/`）を zip にして配る。** `Hanasu.exe` だけを配ると、Whisper のエンジンが使えない（Windows 標準と Gemini は動く）。
CI（`.github/workflows/windows.yml`）は同じコマンドで作り、`Hanasu-windows-x64.zip`（中身は上のフォルダ）を artifact に残す。

ARM64 版は `-r win-arm64 -o publish/win-arm64` で同じ形のものができる（runtimes/win-arm64/ が付く。実機では確かめていない）。

### 確認用の CLI

認証は環境変数 `GEMINI_SERVICE_ACCOUNT_JSON`（サービスアカウントの JSON のパス）か `GEMINI_API_KEY`。

```bash
cd windows
dotnet run --project Hanasu.Cli -- refine "えーと明日の会議なんですけど" [--translate] [--model <id>] [--app Slack] [--dict <辞書ファイル>]
dotnet run --project Hanasu.Cli -- transcribe-gemini <wav> [--dict <辞書ファイル>]
dotnet run --project Hanasu.Cli -- transcribe-whisper <wav> --model tiny [--models-dir <dir>] [--download]
dotnet run --project Hanasu.Cli -- dictation <wav> --engine whisper|gemini [--translate] [--whisper-model tiny]
dotnet run --project Hanasu.Cli -- dict <辞書ファイル> "<文章>"
dotnet run --project Hanasu.Cli -- models
```

## 保存する場所

| もの | 場所 |
| --- | --- |
| 設定 | `%APPDATA%\Hanasu\settings.json`（JSON。壊れていたら `settings.json.broken` に退けて既定値で始める） |
| Gemini の API キー | 設定の `protectedApiKey` に、DPAPI（CurrentUser）で暗号化して Base64 で入れる。平文では保存しない |
| サービスアカウント | JSON のパスだけを保存する（鍵の中身は写さない） |
| Whisper のモデル | `%LOCALAPPDATA%\Hanasu\Models\ggml-*.bin`（ダウンロード中は `.download`） |
| ログ | `%LOCALAPPDATA%\Hanasu\Logs\hanasu.log`（文字起こしの中身は書かない） |
| 最近の結果 | メモリ上だけ（10 件） |

## Mac 版との差

| 機能 | Windows 版 |
| --- | --- |
| 音声認識 | Windows 標準（`Windows.Media.SpeechRecognition`）・Whisper・Gemini から選ぶ。Mac 版の SpeechAnalyzer の代わり |
| 入力 | クリップボード + `SendInput` の Ctrl+V。クリップボードの履歴（Win+V）とクラウド同期に残さない印を付ける |
| アプリ別スタイル | **未実装**（入力先アプリ名を Gemini に伝えるだけ） |
| スニペット | **未実装** |
| 画面の文脈 | **未実装** |
| 履歴ウインドウ（検索・整え直し・音声の保存） | **未実装**。代わりにメモリ上の「最近の結果」10 件をメニューからコピーできる |
| 最後の結果をもう一度入力（`⌥⇧ V`） | **未実装**（「最近の結果」からコピーして貼る） |
| 選択を声で編集 | **未実装** |
| 辞書の候補を探す（Gemini で提案） | **未実装**（辞書の編集と置き換えの試しはできる） |
| 会議の記録 | **これから**（第 2 段階） |

## 依存パッケージ

| パッケージ | 使う場所 | ライセンス |
| --- | --- | --- |
| [NAudio.Wasapi](https://github.com/naudio/NAudio) 2.2.1（と NAudio.Core） | マイクの録音（WASAPI） | MIT |
| [Whisper.net](https://github.com/sandrohanea/whisper.net) / Whisper.net.Runtime 1.9.1（whisper.cpp を含む） | Whisper の文字起こし | MIT（whisper.cpp も MIT） |
| System.Security.Cryptography.ProtectedData 8.0.0 | API キーの DPAPI 暗号化 | MIT |
| xunit 2.9.3 / xunit.runner.visualstudio 2.8.2 | テストのみ | Apache-2.0 |
| Microsoft.NET.Test.Sdk 17.14.1 | テストのみ | MIT |

Whisper のモデル（`ggml-*.bin`）は配布物に含めず、利用者が選んだときに [Hugging Face の ggerganov/whisper.cpp](https://huggingface.co/ggerganov/whisper.cpp) からダウンロードする（OpenAI の Whisper のモデル、MIT）。
