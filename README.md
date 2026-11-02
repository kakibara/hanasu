# Hanasu

話した内容を Gemini で自然な日本語に整えて、カーソル位置に入力する macOS メニューバーアプリ（Typeless 風）。

- 音声認識: macOS 26 内蔵の音声認識エンジン（`SpeechAnalyzer` + `SpeechTranscriber`、`DictationTranscriber` も選択可）。オンデバイスで処理
- 整形: Gemini（初期値 `gemini-3.5-flash-lite`）。Google AI Studio の API キーか、Vertex AI のサービスアカウントで呼ぶ
- 入力: クリップボード + ⌘V（元のクリップボードは自動で戻す）

会議の記録機能もあります（Google Meet・Slack ハドル・Teams など）。マイクを「自分」、Mac で鳴っている音を「相手」として録り、文字起こしと Gemini の議事録を `~/Documents/Hanasu/Meetings/` に保存します。メニューバー →「会議の記録を開始」か `⌃⌥⌘ M`。イヤホンの利用を推奨します。

設計・仕様・技術選定は [docs/DESIGN.md](docs/DESIGN.md)（音声入力）と [docs/MEETING_RECORDER.md](docs/MEETING_RECORDER.md)（会議の記録）。

## 必要なもの

- macOS 26 (Tahoe) 以降、Apple Silicon
- Gemini の認証情報: API キー（[Google AI Studio](https://aistudio.google.com/apikey)）か、Vertex AI ユーザー権限のあるサービスアカウントの JSON 鍵
- 自分でビルドする場合: Xcode Command Line Tools（Swift 6.2）

## インストール（リリース版）

1. [Releases](https://github.com/kakibara/hanasu/releases) から `Hanasu-<バージョン>.zip` をダウンロードして展開し、`Hanasu.app` を「アプリケーション」フォルダに入れる。
2. Apple の公証（notarization）を受けていない自己署名のアプリなので、そのままでは「開発元を確認できない」として開けません。次のどちらかで開いてください。
   - Finder で `Hanasu.app` を右クリック →「開く」→ 確認ダイアログで「開く」
   - またはターミナルで `xattr -dr com.apple.quarantine /Applications/Hanasu.app` を実行してから開く
3. 初回起動で設定画面が開きます（以下「使い方」）。

## ビルドと起動（ソースから）

```bash
./scripts/build-app.sh
open build/Hanasu.app
```

## 使い方

1. 初回起動で設定画面が開くので、「Gemini」タブで認証方法を選び、API キーを保存するか、サービスアカウントの JSON ファイルを指定する。「整形を試す」で動作を確かめられる。
2. 入力したい場所にカーソルを置き、`⌥ Space` を押して話す。
3. もう一度 `⌥ Space` を押すと、整形された文章が入力される。録音中に `Esc` で取り消し。

初回は次の許可を求められます。

- マイク・音声認識: 初めて録音するときにダイアログが出る
- アクセシビリティ: システム設定 → プライバシーとセキュリティ → アクセシビリティで Hanasu をオン（⌘V の自動送信に必要）

署名用の証明書がない環境ではアドホック署名になり、再ビルドのたびにアクセシビリティの許可が外れます（設定でオンに見えても効かない）。最初に一度だけ次を実行しておくと、ローカル用の自己署名証明書で署名するようになり、再ビルドしても許可が保たれます。

```bash
./scripts/create-signing-cert.sh
```

許可が外れてしまった場合は、アクセシビリティの一覧から Hanasu を削除（−）して追加し直してください。

## 設定できること

ショートカット、トグル／押している間だけ録音、認識エンジン（DictationTranscriber / SpeechTranscriber）、Gemini モデル、ユーザー辞書、追加の整形ルール、効果音。

会議の記録: 録音するスピーカーとマイク、マイク側も話者を分ける（会議室など）、議事録のモデル、音声ファイルを残すか。

## リリースの作り方

```bash
./scripts/build-app.sh
ditto -c -k --keepParent build/Hanasu.app build/Hanasu-0.1.0.zip
gh release create v0.1.0 build/Hanasu-0.1.0.zip --title "Hanasu 0.1.0"
```

## ライセンス

Copyright (C) 2026 kakibara

[GNU Affero General Public License v3.0](LICENSE)（AGPL-3.0）で配布します。改変して配布したり、ネットワーク越しにサービスとして提供したりする場合は、そのソースコードも同じライセンスで公開する必要があります。

組み込んでいる第三者のソフトウェア（FluidAudio など）のライセンスは [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) にあります。配布するアプリにも `Contents/Resources` に同梱しています。
