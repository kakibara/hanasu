# Hanasu

話した内容を Gemini で自然な日本語に整えて、カーソル位置に入力する macOS メニューバーアプリ（Typeless 風）。

- 音声認識: macOS 26 内蔵の音声認識エンジン（`SpeechAnalyzer` + `SpeechTranscriber`、`DictationTranscriber` も選択可）。オンデバイスで処理
- 整形: Gemini（初期値 `gemini-3.5-flash-lite`）。Google AI Studio の API キーか、Vertex AI のサービスアカウントで呼ぶ
- 入力: クリップボード + ⌘V（元のクリップボードは自動で戻す）
- 英訳して入力: `⌥⇧ Space` で録音するか、録音中の表示で「English」を選ぶと、日本語で話した内容を Gemini が自然な英語に翻訳して入力する
- 選択を声で編集: 文章を選択して `⌃⌥⌘ E` を押し、「もっと丁寧に」「箇条書きにして」「英語にして」のように話すと、Gemini が書き換えて選択範囲に貼り付ける

会議の記録機能もあります（Google Meet・Slack ハドル・Teams など）。マイクを「自分」、Mac で鳴っている音を「相手」として録り、文字起こしと Gemini の議事録を `~/Documents/Hanasu/Meetings/` に保存します。メニューバー →「会議の記録を開始」か `⌃⌥⌘ M`。イヤホンの利用を推奨します。Zoom・Teams・Slack ハドル・Webex・FaceTime・ブラウザ（Google Meet など）がマイクを使い始めると「会議を記録しますか？」と提案します（自動では記録しません）。

設計・仕様・技術選定は [docs/DESIGN.md](docs/DESIGN.md)（音声入力）と [docs/MEETING_RECORDER.md](docs/MEETING_RECORDER.md)（会議の記録）。

## 必要なもの

- macOS 26 (Tahoe) 以降、Apple Silicon
- Gemini の認証情報: API キー（[Google AI Studio](https://aistudio.google.com/apikey)）か、Vertex AI ユーザー権限のあるサービスアカウントの JSON 鍵
- 自分でビルドする場合: Xcode Command Line Tools（Swift 6.2）

## インストール（リリース版）

1. [Releases](https://github.com/kakibara/hanasu/releases) から `Hanasu-<バージョン>.dmg` をダウンロードして開き、`Hanasu.app` を「Applications」フォルダにドラッグする。
2. Apple の公証（notarization）を受けていない自己署名のアプリなので、そのままでは「開発元を確認できない」として開けません。次のどちらかで開いてください。
   - 一度開こうとして確認が出たら「完了」を押し、システム設定 → プライバシーとセキュリティ の下にある「このまま開く」を押す（macOS 15 以降は、右クリック →「開く」では開けません）
   - またはターミナルで `xattr -dr com.apple.quarantine /Applications/Hanasu.app` を実行してから開く
3. 初回起動で設定画面が開きます（以下「使い方」）。

## ビルドと起動（ソースから）

```bash
./scripts/build-app.sh
open build/Hanasu.app
./scripts/make-dmg.sh   # 配布用の build/Hanasu-<バージョン>.dmg を作る（任意）
```

## 使い方

1. 初回起動で設定画面が開くので、「Gemini」タブで認証方法を選び、API キーを保存するか、サービスアカウントの JSON ファイルを指定する。「整形を試す」で動作を確かめられる。
2. 入力したい場所にカーソルを置き、`⌥ Space` を押して話す。
3. もう一度 `⌥ Space` を押すと、整形された文章が入力される。録音中に `Esc` で取り消し。
4. 英語で入力したいときは、`⌥⇧ Space` で録音を始めるか、録音中に画面下の表示で「English」をクリックしてから止める。英訳した文章が入力される。
5. 書いた文章を直したいときは、その文章を選択して `⌃⌥⌘ E` を押し、どう直すかを話す（例:「もっと丁寧に」「箇条書きにして」「英語にして」「3 行に要約して」）。もう一度 `⌃⌥⌘ E` を押すと、Gemini が書き換えた文章で選択範囲が置き換わる。元に戻すときは、そのアプリで ⌘Z。メニューバーの「選択を声で編集」からも始められる。
   - Gemini の認証情報とアクセシビリティの許可が必要です。
   - 選択した文章は Gemini に送られます。
   - 選択をアクセシビリティ API で読めないアプリでは、⌘C で写し取って読みます（クリップボードはすぐ元に戻します）。
6. 入力先のアプリに合わせて文体が変わる（Slack などのチャットはくだけた短い文、メールは丁寧な文で段落を分ける、Pages・Word・Notion は書き言葉）。設定の「アプリ別」タブで、アプリごとのプリセット・追加ルール・既定の出力言語（日本語／English）を変えられる。

初回は次の許可を求められます。

- マイク・音声認識: 初めて録音するときにダイアログが出る
- アクセシビリティ: システム設定 → プライバシーとセキュリティ → アクセシビリティで Hanasu をオン（⌘V の自動送信に必要）

署名用の証明書がない環境ではアドホック署名になり、再ビルドのたびにアクセシビリティの許可が外れます（設定でオンに見えても効かない）。最初に一度だけ次を実行しておくと、ローカル用の自己署名証明書で署名するようになり、再ビルドしても許可が保たれます。

```bash
./scripts/create-signing-cert.sh
```

許可が外れてしまった場合は、アクセシビリティの一覧から Hanasu を削除（−）して追加し直してください。

## 設定できること

ショートカット（音声入力・英訳して入力・選択を声で編集）、トグル／押している間だけ録音、認識エンジン（DictationTranscriber / SpeechTranscriber）、Gemini モデル、ユーザー辞書、追加の整形ルール、アプリ別の文体（プリセット・追加ルール・既定の出力言語）、効果音。

会議の記録: 録音するスピーカーとマイク、マイク側も話者を分ける（会議室など）、議事録のモデル、音声ファイルを残すか、会議の自動検出（オン／オフと対象のアプリ）。

## リリースの作り方

[tagpr](https://github.com/Songmu/tagpr) で行います（`.tagpr`、`.github/workflows/tagpr.yml`）。

1. `main` に変更が入ると、tagpr が次のバージョンのリリース PR（`VERSION` と `CHANGELOG.md` の更新）を作り・更新します。
   - 既定はパッチ（0.1.0 → 0.1.1）。リリース PR に `tagpr:minor` / `tagpr:major` ラベルを付けるか、`VERSION` を直接書き換えると上げ幅を変えられます。
2. リリース PR をマージすると、tagpr がタグと下書きのリリースを作ります。
3. 続けて macOS 26 のランナーがアプリをビルドし、`Hanasu-<バージョン>.dmg` を添付してリリースを公開します。既存のタグの dmg を作り直すときは、Actions の「tagpr」を tag を指定して手動で実行します。

初回だけ必要な準備:

- リポジトリの Settings → Actions → General → Workflow permissions で「Allow GitHub Actions to create and approve pull requests」をオンにする。
- リリース用の署名証明書を作って Secrets に登録する（なければアドホック署名になり、アップデートのたびにアクセシビリティの許可が外れます）。

```bash
./scripts/setup-release-signing.sh
```

## ライセンス

Copyright (C) 2026 kakibara

[GNU Affero General Public License v3.0](LICENSE)（AGPL-3.0）で配布します。改変して配布したり、ネットワーク越しにサービスとして提供したりする場合は、そのソースコードも同じライセンスで公開する必要があります。

組み込んでいる第三者のソフトウェア（FluidAudio など）のライセンスは [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) にあります。配布するアプリにも `Contents/Resources` に同梱しています。
