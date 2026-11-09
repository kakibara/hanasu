# Hanasu の計画（ロードマップ）

**まだ main に入っていないもの**だけを置く。実装済みの振る舞いは [spec/](spec/) にある。

- 各項目に `FUT-<番号>` を付ける。番号は使い回さない（やめた項目も、消さずに「やめた」と書いて残す）。
- 実装したら、その項目の中身を spec に要件（REQ）か設計判断（DEC）として書き、ここからは消して「→ REQ-…」とだけ残す（[docs/README.md](README.md) の「変更の手順」）。
- 状態は 進行中 / 未着手 / 見送り（理由つき） / やめた / 実装した（→ REQ-…） のどれか。
- 番号の分け方: 0xx 全体・Windows、1xx 音声入力、2xx 会議の記録。
- 実装したものは「→ REQ-…」とだけ残す（番号は使い回さない）。

| ID | 項目 | 状態 | 出どころ |
| --- | --- | --- | --- |
| FUT-001 | Windows 版（音声入力と会議の記録） | 実装した（PR #19）→ REQ-COM-010, REQ-COM-011 | ユーザーの指定（2026-11-03） |
| FUT-002 | Windows 版のコードに要件・設計判断のタグを付ける | 未着手 | この PR |
| FUT-003 | Windows 版に、Mac 版だけにある機能を足す | 未着手（足すかは未定） | PR #19 |
| FUT-010 | Developer ID で署名し、API キーをデータ保護キーチェーンに移す | 未着手（Apple Developer Program が要る） | Claude API の対応の PR |
| FUT-011 | Whisper・話者分離のモデルを、決めたリビジョンとハッシュに固定する | 未着手 | Claude API の対応の PR |
| FUT-012 | 表示の言語（UI の文字列）を、システムの言語に合わせて 17 言語で切り替える | 実装した → REQ-COM-060 | ユーザーの依頼（2026-11-05） |
| FUT-013 | 文字起こしの言語の一覧に、ロシア語・トルコ語・ベトナム語・インドネシア語・ポーランド語・アラビア語・ヒンディー語を足す | 未着手 | 多言語化の PR |
| FUT-014 | 言語に依存する決まりを、日本語以外にも広げる（会議への質問の期間の語と検索の除外語、スニペットのフィラー、話者名の敬称） | 未着手 | 多言語化の PR |
| FUT-015 | `hanasu` コマンド（会議の記録を読む・探す・聞く・MCP、文章の整形・翻訳・書き換え） | 段階 1・2 を実装した → REQ-COM-180〜188、REQ-MTG-120〜126、REQ-DIC-160〜162。段階 3〜6 は未着手 | ユーザーの依頼（2026-11-06〜08）、[plans/cli.md](plans/cli.md) |
| FUT-016 | Mac と Windows で共有するデータを common/resources に置く（プロンプト・モデルの一覧・選択肢） | 未着手（計画あり） | [plans/common-shared-data.md](plans/common-shared-data.md) |
| FUT-017 | Mac と Windows で同じ決まりのロジックを、共有のテストデータ（common/testdata/logic）で確かめる | 未着手（計画あり） | [plans/common-shared-data.md](plans/common-shared-data.md) |
| FUT-018 | UI のテスト項目のうち、本物のアプリを起動して操作するもの（drive）を Mac で自動で動かす | 未着手 | DEC-COM-170 の PR |
| FUT-019 | Windows 版の UI のテスト項目を自動で確かめる（画面を PNG にする CLI を足す） | 未着手 | DEC-COM-170 の PR |
| FUT-101 | ブラウザのサイト別スタイル | 見送り | PR #5 |
| FUT-102 | 画面の文脈で、Slack のスレッドの直前のメッセージも読む | 見送り | PR #7 |
| FUT-103 | 音声認識にカスタム言語モデル（customLanguageModel）を使う | 見送り | PR #12 |
| FUT-104 | 会議の文字起こし・議事録にも辞書の置き換えルールを当てる | 未着手 | PR #12 |
| FUT-105 | 履歴の録音から文字起こしし直す | 未着手 | PR #9 |
| FUT-106 | Whisper で録音中に途中経過を出す | 見送り | PR #17 |
| FUT-107 | Gemini のストリーミング応答で、体感の待ち時間を短くする | 未着手 | 初版の「今後の拡張候補」 |
| FUT-108 | Fn キー（Globe キー）でのトリガー | 未着手 | 初版の「今後の拡張候補」 |
| FUT-201 | 会議アプリだけを録るモード | 未着手（フェーズ 2） | 初版のフェーズ分け |
| FUT-202 | マイク側のエコーキャンセル | 未着手（フェーズ 2） | 初版のフェーズ分け |
| FUT-203 | ボットモード（会議にボットを参加させて記録する） | 未着手（計画あり） | [plans/bot-mode.md](plans/bot-mode.md) |
| FUT-204 | 会議の AI チャットを、ほかのアプリの前面のパネルでも使う | 未着手 | PR #68（会議中の AI チャット、2026-11-05） |
| FUT-205 | Windows 版にも、議事録の名前付きテンプレートを足す（Mac 版は REQ-MTG-042） | 未着手 | REQ-MTG-042 の PR |

---

## 全体・Windows

### FUT-001 Windows 版（音声入力と会議の記録）
- 状態: 実装した（PR #19、acfc066）→ REQ-COM-010, REQ-COM-011。共通の要件は「対象」に Windows を足し、Windows だけの細部は DEC-COM-100〜107、DEC-DIC-110〜114、DEC-MTG-100〜110、DEC-REL-008 に書いた。説明は [windows/README.md](../windows/README.md)。

### FUT-002 Windows 版のコードに要件・設計判断のタグを付ける
- 状態: 未着手（別の作業で行う）
- 中身: `windows/` のコードに `// 要件: REQ-…`、`// 設計判断: DEC-…`、テスト・CLI に `// 確かめ方: REQ-…` を付ける。対象: REQ-COM-010・011 と、「対象」に Windows がある要件、DEC-COM-100〜107・DEC-DIC-110〜114・DEC-MTG-100〜110・DEC-REL-008。`scripts/check-spec.py` は `windows/` の `.cs` も読むので、付ければそのまま数えられる。今は「対象が Windows だけの要件にタグがない」ことを報告だけにしている。付け終えたら、check-spec.py のこの例外を外す。
- 出どころ: この PR（文書を spec と roadmap に分けたとき）

### FUT-003 Windows 版に、Mac 版だけにある機能を足す
- 状態: 未着手（足すかどうかは未定。ユーザーに確かめる）
- 中身: アプリ別の文体・スニペット・画面の文脈・履歴の整え直しと録音（履歴そのものは REQ-DIC-060・063 で足した）・最後の結果の再入力・選択を声で編集・辞書の候補の提案、会議の字幕・マイク側の話者分離・自動検出・横断検索と質問・会議の AI チャット（REQ-MTG-040・041。Windows 版は記録中の文字起こしがないので、先にそれが要る）・書き出し（ファイル・Slack・リマインダー）・初回起動のオンボーディングと既定の AI の選択（REQ-COM-050・051）。今の差は DEC-COM-107 と [windows/README.md](../windows/README.md) の「Mac 版との差」。
- 出どころ: PR #19

### FUT-012 表示の言語（UI の文字列）を、システムの言語に合わせて 17 言語で切り替える
- 状態: 実装した → REQ-COM-060（Mac は DEC-COM-165・166、Windows は DEC-COM-167。AI へのプロンプトは REQ-COM-061）
- 出どころ: ユーザーの依頼（2026-11-05）

### FUT-013 文字起こしの言語の一覧に、7 言語を足す
- 状態: 未着手
- 中身: REQ-COM-004 の一覧（11 項目）に、プロンプトが対応しているロシア語・トルコ語・ベトナム語・インドネシア語・ポーランド語・アラビア語・ヒンディー語を足す。今はシステムの言語がこれらなら初期値には入るが、一覧からは選べない。エンジン（SpeechAnalyzer・Whisper・Gemini）ごとに使えるかを確かめてから足す。
- 出どころ: 多言語化の PR（2026-11-05）

### FUT-014 言語に依存する決まりを、日本語以外にも広げる
- 状態: 未着手
- 中身: 今は日本語だけを見ている決まりを、ほかの言語でも働くようにする。会議への質問の「先週」「昨日」などの期間の読み取りと検索の除外語（`MeetingAsk`）、スニペットの照合で外すフィラーと語尾（`Snippets`）、話者名から外す敬称（`SpeakerNameInference.honorifics`）。
- 出どころ: 多言語化の PR（2026-11-05）

### FUT-015 `hanasu` コマンド
- 状態: 段階 1（会議を読む。AI なし）と段階 2（AI を使うコマンド）を実装した（2026-11-09）→ REQ-COM-180〜188、REQ-MTG-120〜126、REQ-DIC-160〜162。段階 3〜6（MCP・配る・会社の環境・Windows）は未着手（[plans/cli.md](plans/cli.md) の 6 章）。段階 2 で `doctor`（計画の C8）の MCP 以外の部分を先に入れた。ポリシー `AllowedAIProviders` は `hanasu` にだけ効き、アプリ自体に効かせるのは段階 5
- 中身: アプリと同じ実行ファイルのサブコマンドとして、`hanasu` コマンドを足す。会議の記録を AI エージェントやスクリプトから読めるようにし（`meetings`・`actions`・`ask`・`mcp`）、音声入力の整え方をパイプで使えるようにする（`refine`・`edit`）。録音の操作と音声ファイルの文字起こしは入れない。アプリを使ってよい環境なら、CLI のために追加のインストールや管理者の権限を求めない（配布物に含め、絶対パスで動き、PATH は任意）。会社向けに、管理者のポリシーで CLI・MCP・使える AI を決められるようにする。Windows 版は、配布物に `cli\hanasu.exe` を足す。
- 出どころ: ユーザーの依頼（2026-11-06〜08）。計画の中の C1〜C9・M1〜M13・R1〜R9・E1〜E12 は、実装するときに spec の要件（REQ）として書き直す

### FUT-016 Mac と Windows で共有するデータを common/resources に置く
- 状態: 未着手（計画あり。[plans/common-shared-data.md](plans/common-shared-data.md) の段階 A）
- 中身: プロンプトの JSON を `common/resources/prompts/` に移し、モデルの一覧（ローカル LLM・Whisper・Gemini・Claude）と選択肢・既定値を `common/resources/*.json` に置いて、Mac と Windows の両方がビルドで埋め込んで読む。今の「両方を直す」値の二重持ちをなくす。
- 出どころ: ユーザーの依頼（2026-11-08「共通の設定ファイル化できるものは common/resource 以下に置く」）

### FUT-017 Mac と Windows で同じ決まりのロジックを、共有のテストデータで確かめる
- 状態: 未着手（計画あり。[plans/common-shared-data.md](plans/common-shared-data.md) の段階 B）
- 中身: 辞書・話者名の推測・ActionItem の読み取り・議事録のプロンプトの組み立て・長い入力の縮め方・言語の決め方について、入力と期待する出力の組を `common/testdata/logic/*.json` に置き、`Hanasu.Core.Tests` と Mac の自己テストの CLI の両方で回す。共通の処理を Rust で書く案は、これで足りなくなったら考え直す。
- 出どころ: ユーザーの依頼（2026-11-08「共通の処理を Rust で実装したら」）への提案

### FUT-018 本物のアプリを起動して操作する UI のテストを、Mac で自動で動かす
- 状態: 未着手
- 中身: `common/testdata/ui` の項目で `automation.mac.kind` が `drive` のもの（ショートカットで録音して HUD が出る、Esc で取り消す など）を、アプリを起動してアクセシビリティの API で操作し、画面を撮って確かめる。ターミナルにアクセシビリティと画面収録の許可が要り、マイクや OS のダイアログが絡むので、`render`（DEC-COM-170）とは別に作る。
- 出どころ: DEC-COM-170 の PR（2026-11-08）

### FUT-019 Windows 版の UI のテスト項目を自動で確かめる
- 状態: 未着手
- 中身: Windows 版には画面を PNG にする CLI がないので、`common/testdata/ui` の Windows の項目はすべて `manual`。WPF の画面を決まった状態で PNG にする CLI を `Hanasu.Windows` に足し、Windows の上で `scripts/ui-cases.py render` と同じ流れで確かめられるようにする。
- 出どころ: DEC-COM-170 の PR（2026-11-08）

---

## 音声入力

### FUT-101 ブラウザのサイト別スタイル
- 状態: 見送り（利用者の多い Chrome / Arc で、副作用なしに URL を取る方法が決まらない）
- 中身: Chrome / Safari / Arc の中で「Gmail ならメール、Slack の Web 版ならチャット」とサイトで文体を分ける（REQ-DIC-020 の延長）。
- 出どころ: PR #5
- 調べたこと: 録音を始めたときに前面タブの URL が要る。アクセシビリティ（AX）で取れるかを調べた結果:
  - **Safari**: Web の中身は `AXWebArea` で、`AXURL` 属性にページの URL がある。`AXFocusedUIElement` から `AXParent` をたどって `AXWebArea` を探せば取れる見込み。Hanasu は ⌘V のためにアクセシビリティの許可を持っているので、許可は増えない。
  - **Chrome / Arc（Chromium）**: 支援技術が動いていないと、Web の中身の AX ツリーを作らない。アプリの要素に `AXManualAccessibility`（または `AXEnhancedUserInterface`）を立てれば作るが、その後はすべてのページで AX ツリーを保つので、CPU とメモリを余計に使う（`AXEnhancedUserInterface` はウインドウ操作のアニメーションが崩れる副作用も知られている）。アドレスバー（`AXTextField`）の値を読む方法もあるが、スキームが省かれていたり、入力途中の文字列だったりする。
  - **AppleScript**（`URL of active tab of front window`）なら Chrome・Safari・Arc とも取れるが、ブラウザごとに「オートメーション」の許可が新たに要り、Info.plist に `NSAppleEventsUsageDescription` を足す必要がある。
  - 調べたときの開発環境ではアクセシビリティの許可がなく（アプリの起動もしない約束）、実機で確かめられなかった。
- 作るときの形: Safari だけなら小さく作れる。スタイルのキーを bundle ID に加えてホスト名（例: `mail.google.com`）でも持ち、ホスト名の一致をアプリより先に見る形にする。

### FUT-102 画面の文脈で、Slack のスレッドの直前のメッセージも読む
- 状態: 見送り（Slack の画面の作りに強く依存して壊れやすく、実機の許可がない環境では確かめられない）
- 中身: 返信相手のメッセージを、画面の文脈（REQ-DIC-040）として渡す。今は Slack はウインドウのタイトル（チャンネル名・相手の名前）だけを渡している（DEC-DIC-062）。
- 出どころ: PR #7
- 作るときの形: AX のツリーを辿って、スレッドの直前のメッセージを探す。

### FUT-103 音声認識にカスタム言語モデル（customLanguageModel）を使う
- 状態: 見送り（初期値の SpeechTranscriber では使えず、学習データを辞書の読みからそのまま作れない）
- 中身: 辞書の語を、音声認識そのものにもっと強く効かせる（REQ-DIC-070 の延長）。
- 出どころ: PR #12
- 調べたこと:
  - `AnalysisContext.contextualStrings[.general]` は、もとから音声入力（`SpeechRecognizer`）と会議（`ChannelTranscriber`）の両方で設定している。PR #12 で、ルールの読みと表記も渡すようにした（DEC-DIC-009）。
  - `DictationTranscriber.ContentHint.customizedLanguage(modelConfiguration:)` で、`SFSpeechLanguageModel` のカスタム言語モデルを使える。ただし、
    - DictationTranscriber でしか使えない（初期値の SpeechTranscriber にはない）。
    - `SFCustomLanguageModelData` から学習データを作り、`SFSpeechLanguageModel.prepareCustomLanguageModel` で事前に準備する必要がある。発音は X-SAMPA で書くので、辞書の「読み」（かな）からそのままは作れない。
- 作るときの形: DictationTranscriber を使う人が多ければ、語とルールの表記を「よく出る語句」として学習データにする方法を試す価値がある。

### FUT-104 会議の文字起こし・議事録にも辞書の置き換えルールを当てる
- 状態: 未着手
- 中身: 今の会議の記録では、辞書を語彙のヒントにだけ使っている（DEC-DIC-085）。文字起こしと議事録にも置き換えルールを当てる。
- 出どころ: PR #12（会議の後処理はほかの PR も触っていたので見送った）

### FUT-105 履歴の録音から文字起こしし直す
- 状態: 未着手
- 中身: 「録音した音声も残す」をオンにした履歴（DEC-DIC-075）で、認識結果が明らかに違うときに、録音から文字起こしし直す。
- 出どころ: PR #9

### FUT-106 Whisper で録音中に途中経過を出す
- 状態: 見送り（数秒ごとに文字起こしし直すので、CPU と電池の負担が大きい）
- 中身: Whisper のエンジンでも、録音中に途中経過を HUD に出す（REQ-DIC-002 の食い違いの解消の候補）。
- 出どころ: PR #17

### FUT-010 Developer ID で署名し、API キーをデータ保護キーチェーンに移す
- 状態: 未着手（Apple Developer Program に入る必要がある）
- 中身: Team ID のある証明書（Developer ID）で署名・公証し、keychain-access-groups の entitlement を付けて、API キーをデータ保護キーチェーン（`kSecUseDataProtectionKeychain`）に移す。`SecAccessControl` で使うときに本人の確認（Touch ID）を求めることもできるようになる。今の自己署名では使えない（-34018）ので、ファイル型のキーチェーンの ACL にしている（DEC-COM-048）。同じユーザーで動くアドホック署名のプログラムが確認なしで読めた問題（[design/security.md](design/security.md) の 1.3）は、これで防げる見込み。
- 出どころ: Claude API の対応の PR（セキュリティの調査）

### FUT-011 Whisper・話者分離のモデルを、決めたリビジョンとハッシュに固定する
- 状態: 未着手
- 中身: いまは WhisperKit・FluidAudio が、Hugging Face のリポジトリの最新（`main`）を取り、サーバーが返すハッシュと比べている。Hanasu の側でリビジョン（コミット）とファイルのハッシュを決めて渡し、差し替えられたモデルを取らないようにする（[design/security.md](design/security.md) の 4 章）。
- 出どころ: Claude API の対応の PR（セキュリティの調査）

### FUT-107 Gemini のストリーミング応答で、体感の待ち時間を短くする
- 状態: 未着手
- 中身: 整形の応答をストリーミングで受け取り、待ち時間を短く感じさせる。
- 出どころ: 初版（a787da8）の「今後の拡張候補」

### FUT-108 Fn キー（Globe キー）でのトリガー
- 状態: 未着手
- 中身: Fn キー（Globe キー）で録音を始める。`CGEventTap` が必要で、入力監視の権限が要る（Carbon の `RegisterEventHotKey` では Fn 単体を登録できない。DEC-DIC-011）。
- 出どころ: 初版（a787da8）の「今後の拡張候補」

---

## 会議の記録

### FUT-201 会議アプリだけを録るモード
- 状態: 未着手（初版のフェーズ 2）
- 中身: 設定で「会議アプリだけ」にすると、`kAudioHardwarePropertyProcessObjectList` から Chrome・Safari・Slack・Teams などの音声プロセスを探して `stereoMixdownOfProcesses` で限定する。今は自分以外の音全体を録っている（DEC-MTG-002）。
- 出どころ: 初版（a787da8）の技術選定 4.1 とフェーズ分け

### FUT-202 マイク側のエコーキャンセル
- 状態: 未着手（初版のフェーズ 2）
- 中身: イヤホンを使わないとき、スピーカーから回り込んだ相手の声で自分の発言の認識が崩れる（[verification/meeting.md](verification/meeting.md) 2）。Voice Processing I/O、または相手側の音声を参照信号にした自前のエコー除去で防ぐ。今はテキストでの除去（DEC-MTG-013）とイヤホンの推奨だけ。
- 出どころ: 初版（a787da8）のフェーズ分け、検証結果

### FUT-203 ボットモード（会議にボットを参加させて記録する）
- 状態: 未着手（調査・要件定義・実装計画あり）
- 中身: Meet・Teams・Zoom にボットを参加させ、参加者の実名つきの文字起こしと議事録を残す。Slack ハドルは対象外。
- 出どころ: 2026-11-02 の調査。詳しくは [plans/bot-mode.md](plans/bot-mode.md)。計画の中の B1〜B10 は、実装するときに REQ-MTG の新しい番号として spec に書き直す（初版の要件定義では「会議ツールへのボット参加」は対象外。REQ-MTG-031）

### FUT-204 会議の AI チャットを、ほかのアプリの前面のパネルでも使う
- 状態: 未着手
- 中身: 会議中は会議ツールを前面に出していることが多いので、字幕のパネル（REQ-MTG-014）のように、AI チャットもほかのアプリの前面に浮かぶパネルで使えるようにする。今は会議ノートのウインドウの中（記録中の画面の右側。DEC-MTG-080）だけ。入力を受けるにはパネルがキーウインドウになる必要があり、会議ツールからフォーカスを奪わない工夫が要る。答えを少しずつ出す（FUT-107）と、待ち時間も短く感じられる。
- 出どころ: PR #68（会議中の AI チャット、2026-11-05）

### FUT-205 Windows 版にも、議事録の名前付きテンプレートを足す
- 状態: 未着手
- 中身: Mac 版の REQ-MTG-042（名前を付けて保存・管理できる議事録のテンプレート）を Windows 版にも入れる。保存先は `windows/Hanasu.Core/Settings` の設定、会議ノートの型の選択欄と作り直しのメニューに保存済みを並べる。`meeting.json` の `minutesTemplateName` は、読み書きで落とさないところまで先に入れた（DEC-MTG-108）。残りは画面と保存先。
- 出どころ: REQ-MTG-042 の依頼（2026-11-05）。Mac 版だけを先に作った
