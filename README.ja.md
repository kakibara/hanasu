<div align="center">

<img src="docs/images/icon.png" width="112" alt="Hanasu のアイコン">

# Hanasu

**話すだけで、そのまま送れる文章に。会議の議事録も、自動で。**

macOS と Windows で使える、音声入力と会議の記録のアプリです。端末の上で動く音声認識と、Gemini か Claude を使います。

[![Release](https://img.shields.io/github/v/release/kakibara/hanasu?sort=semver&label=release)](https://github.com/kakibara/hanasu/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/kakibara/hanasu/total)](https://github.com/kakibara/hanasu/releases)
[![License](https://img.shields.io/github/license/kakibara/hanasu)](LICENSE)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-000000?logo=apple)
![Windows 10/11](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows)
[![Windows build](https://github.com/kakibara/hanasu/actions/workflows/windows.yml/badge.svg)](https://github.com/kakibara/hanasu/actions/workflows/windows.yml)

[English](README.md) · **日本語**

<img src="docs/images/hud.png" width="560" alt="録音中の表示">

</div>

## Hanasu とは

OS の音声入力では、言いよどみや同音異義語の誤変換、「あ、違う」と言い直す前の文が、そのまま残ります。
Hanasu は文字起こしを Gemini か Claude に渡し、そうした部分を整えた日本語にしてから、カーソルの位置に入力します。
Typeless・Wispr Flow・Aqua Voice・Granola を参考に作りました。無料のオープンソースで、Gemini か Claude の API キーは自分のものを使います。

## できること

### 🎙️ 音声入力

| | |
| --- | --- |
| **話す → 整った文章** | <kbd>⌥ Space</kbd> を押して話し、もう一度押すか **■ 停止** をクリックします。言いよどみ・誤変換・言い直しを直した文章が、カーソルの位置に入ります。 |
| **日本語で話して英語で入力** | <kbd>⌥⇧ Space</kbd> で録音するか、録音中の表示で **English** を選びます。決まった言い回しも自然に訳します（お疲れ様です → "Hi,"）。 |
| **選択を声で編集** | 文章を選択して <kbd>⌃⌥⌘ E</kbd> を押し、「もっと丁寧に」「箇条書きにして」「英語にして」のように話します。 |
| **アプリ別の文体** | Slack ではくだけた短い文、メールでは丁寧で段落を分けた文、Pages・Word・Notion では書き言葉にします。アプリごとに変えられます。 |
| **スニペット** | 「メールの署名」と言うだけで、登録した文章をそのまま入れます。スニペットは Gemini に送りません。 |
| **ユーザー辞書** | 固有名詞や置き換えルール（`ストックマーク => Stockmark`）を登録できます。辞書の候補を Gemini に挙げてもらうこともできます。 |
| **画面の文脈**（オプトイン） | ウインドウのタイトルとカーソル前後の文章を読み、画面にある表記に合わせます。パスワード欄は読みません。 |
| **履歴** | 結果を検索したり、失敗したものを整え直したりできます。<kbd>⌥⇧ V</kbd> で最後の結果をもう一度入力します。 |

<p align="center">
  <img src="docs/images/hud-english.png" width="420" alt="英語で入力">
  <img src="docs/images/edit-mode.png" width="420" alt="選択を声で編集">
</p>

### 📝 会議の記録

| | |
| --- | --- |
| **自分と相手を別々に録る** | マイクの音を「自分」、Mac で鳴っている音（Zoom・Meet・Teams・Slack ハドルなど）を「相手」として録ります。会議にボットを入れる必要はありません。 |
| **話者分離** | 相手側を「話者1」「話者2」…に、端末の上で分けます。話者名はあとから付け替えられます。 |
| **Gemini で議事録** | 型（自動・定例・1on1・商談・ブレスト・カスタム）を選んで作ります。アクションアイテムは担当と期限つきで取り出します。 |
| **メモと「ここ重要」** | 記録中に時刻つきのメモを書いたり、<kbd>⌃⌥⌘ H</kbd> で印を付けたりできます。議事録はその部分を優先してまとめます。 |
| **会議の自動検出** | 会議アプリがマイクを使い始めると「記録しますか？」と聞きます。勝手には録音しません。 |
| **横断検索と質問** | すべての会議を全文検索できます。「先週の定例で何が決まった？」と聞くと、根拠の会議を引用して答えます。 |
| **書き出し** | Markdown か Slack 向けの形でコピーしたり、.md / .txt で保存したりできます。アクションアイテムはリマインダーに登録できます。 |

<p align="center">
  <img src="docs/images/meeting-live.png" width="420" alt="記録中のメモ">
  <img src="docs/images/meeting-ask.png" width="420" alt="会議に質問">
</p>
<p align="center">
  <img src="docs/images/meeting-minutes.png" width="420" alt="アクションアイテムつきの議事録">
  <img src="docs/images/meeting-suggestion.png" width="420" alt="会議の自動検出">
</p>

### 🤖 整形に使う AI を選べる

文章を整える AI を、**音声入力**と**会議**で別々に選べます。

| AI | 既定のモデル | 認証 |
| --- | --- | --- |
| **Gemini**（既定） | 音声入力 `gemini-3.5-flash-lite`、会議 `gemini-3.8-flash` | Google AI Studio の API キーか Vertex AI のサービスアカウント |
| **Claude** | 音声入力 `claude-haiku-5-5`、会議 `claude-sonnet-5-5`（Opus 5.5 も選べる） | Anthropic の API キー |

Claude は文章だけを扱います。音声の文字起こしは、下のエンジンが行います。

### 🔊 文字起こしのエンジンを選べる

| エンジン | 動く場所 | 録音中の文字 | 補足 |
| --- | --- | --- | --- |
| **OS 標準**（既定） | Mac: `SpeechAnalyzer` ・ Windows: `Windows.Media.SpeechRecognition` | ✅ | Mac では端末の上で動く |
| **Whisper** | 端末の上（Mac は WhisperKit、Windows は whisper.cpp） | 止めてから | 選んだときにモデルをダウンロードする |
| **Gemini** | Google | 止めてから | 録った音声を Google に送る |

音声入力と会議の記録で、別々のエンジンを選べます。Windows 版の会議の記録は、Whisper か Gemini を使います。

## ダウンロード

[**Releases**](https://github.com/kakibara/hanasu/releases/latest) から、最新版をダウンロードしてください。

| 対象 | ファイル | 必要な環境 |
| --- | --- | --- |
| macOS | `Hanasu-<版>-macOS.zip` | macOS 26 (Tahoe) 以降、Apple Silicon |
| Windows | `Hanasu-<版>-Windows-x64.zip` | Windows 10（2004 以降）/ 11、x64 |

<details>
<summary><b>macOS: 初めて開くとき</b></summary>

1. zip を展開し、`Hanasu.app` を「アプリケーション」フォルダに入れます。
2. Apple の公証を受けていない自己署名のアプリなので、初回は開けません。確認が出たら「完了」を押し、システム設定 → プライバシーとセキュリティ の下にある「このまま開く」を押します。ターミナルで `xattr -dr com.apple.quarantine /Applications/Hanasu.app` を実行してもかまいません。
3. マイク・音声認識・アクセシビリティの許可を求められたら許可します。アクセシビリティは、⌘V で貼り付けるのに使います。

</details>

<details>
<summary><b>Windows: 初めて開くとき</b></summary>

1. zip を展開し、`Hanasu` フォルダを好きな場所（例: `%LOCALAPPDATA%\Programs`）に置いて、`Hanasu.exe` を開きます。
2. コード署名をしていないので、SmartScreen の確認が出ます。「詳細情報」→「実行」を押します。
3. Windows 標準の音声認識を使うには、Windows の設定で「オンライン音声認識」をオンにしておく必要があります。オフのときは Hanasu が案内します。

Windows 版の注意点と Mac 版との違いは、[windows/README.md](windows/README.md) にあります。

</details>

## はじめかた

1. **AI の認証情報を設定する。** 設定の「AI」タブで Gemini か Claude を選びます。Gemini なら [Google AI Studio](https://aistudio.google.com/apikey) の API キーか Vertex AI のサービスアカウントの JSON、Claude なら [Claude Console](https://console.anthropic.com/settings/keys) の API キーを入れます。「整形を試す」で動作を確かめられます。
2. **音声入力する。** 入力したい場所にカーソルを置き、ショートカットを押して話し、もう一度押します。
3. **会議を記録する。** メニューバー（Windows はタスクトレイ）のメニューか、ショートカットで始めます。イヤホンを使うと、自分と相手の音が混ざりにくくなります。

### 既定のショートカット

| 操作 | macOS | Windows |
| --- | --- | --- |
| 音声入力（開始・停止） | <kbd>⌥ Space</kbd> | <kbd>Ctrl Alt Space</kbd> |
| 翻訳して入力（英訳・和訳） | <kbd>⌥⇧ Space</kbd> | <kbd>Ctrl Alt Shift Space</kbd> |
| 選択を声で編集 | <kbd>⌃⌥⌘ E</kbd> | — |
| 最後の結果をもう一度入力 | <kbd>⌥⇧ V</kbd> | — |
| 録音を取り消す | <kbd>Esc</kbd> | <kbd>Esc</kbd> |
| 会議の記録（開始・停止） | <kbd>⌃⌥⌘ M</kbd> | <kbd>Ctrl Alt Shift M</kbd> |
| 「ここ重要」の印 | <kbd>⌃⌥⌘ H</kbd> | <kbd>Ctrl Alt Shift H</kbd> |

ショートカットはどれも設定で変えられます。使い方・設定・ユーザー辞書の詳しい説明は、[利用ガイド](docs/guide.md) にあります。

## プライバシー

- **音声は、既定では端末の外に出しません。** 音声認識・Whisper・話者分離は、端末の上で動きます。
- **AI に送るのはテキストです。** Gemini か Claude に送るのは文字起こしです。設定によっては、入力先のアプリ名、画面の文脈、質問に使う会議の文字起こしも送ります。
- **音声を Google に送るのは、選んだときだけです。** 文字起こしのエンジンに Gemini を選ぶと、録った音声を送ります。
- **会議の記録は、ただのファイルです。** `~/Documents/Hanasu/Meetings/`（Windows は `ドキュメント\Hanasu\Meetings\`）に、JSON と Markdown で保存します。Mac 版と Windows 版で形式は同じです。
- **利用状況は集めません。**
- **API キーは OS の仕組みで守ります。** macOS ではキーチェーンに保存し、ほかのアプリが読むにはログインのパスワードが要ります。Windows では DPAPI か、選べば Windows Hello の鍵で暗号化します。どちらも、同じユーザーで動くマルウェアからは守りきれません（[docs/design/security.md](docs/design/security.md)）。

> [!IMPORTANT]
> 録音の前に、会議の参加者の了承を得てください。会社の規程で録音や外部の AI の利用が制限されている場合は、それに従ってください。

## ソースからビルドする

<details>
<summary><b>macOS</b>（Xcode Command Line Tools、Swift 6.2）</summary>

```bash
./scripts/build-app.sh             # build/Hanasu.app を作る
open build/Hanasu.app
./scripts/create-signing-cert.sh   # 任意。再ビルドしても許可が外れないようにする
```

</details>

<details>
<summary><b>Windows</b>（.NET 8 SDK）</summary>

```bash
cd windows
dotnet build Hanasu.Windows.sln
dotnet publish Hanasu.Windows/Hanasu.Windows.csproj -c Release -r win-x64 --self-contained -p:PublishSingleFile=true -o publish/win-x64
```

詳しくは [windows/README.md](windows/README.md) を見てください。

</details>

## 文書

| | |
| --- | --- |
| [docs/guide.md](docs/guide.md) | 利用ガイド（使い方・設定・ユーザー辞書） |
| [docs/spec/](docs/spec/) | 実装済みの要件（`REQ-*`）と設計判断（`DEC-*`） |
| [docs/design/](docs/design/) | 今の作り（アーキテクチャ・データの流れ） |
| [docs/roadmap.md](docs/roadmap.md) | まだ実装していない計画 |
| [docs/releasing.md](docs/releasing.md) | リリースの作り方（tagpr） |

## 開発に参加する

Issue と Pull Request を歓迎します。

1. 振る舞いを変える前に、[docs/README.md](docs/README.md) を読んでください。
2. コードには `// 要件: REQ-…` か `// 設計判断: DEC-…` の印が付いています。印の付いたコードを変えたのに spec を直していないと、CI（`scripts/check-spec.py`）が知らせます。
3. 新しい機能は、まず `docs/spec/` に要件として書きます。いつかやりたいことは `docs/roadmap.md` に書きます。

## ライセンス

[Apache License 2.0](LICENSE) © 2026 kakibara（[NOTICE](NOTICE)）。
第三者のソフトウェアのライセンスは、Mac 版は [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)、Windows 版は [windows/THIRD_PARTY_NOTICES.md](windows/THIRD_PARTY_NOTICES.md) にあります。どちらも配布物に同梱しています。
