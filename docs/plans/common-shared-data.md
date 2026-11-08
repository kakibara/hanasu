# Mac と Windows で共有するデータとテストデータ（common/）

状態: 計画（段階 C は実装した → DEC-COM-170。段階 A は FUT-016、段階 B は FUT-017）

## 目的

2026-11-08 の依頼「バックエンドの処理が増えてきたので共通の処理を Rust で実装したらよいのでは。共通の設定ファイル化できるものは common/resource 以下に置けるのでは」と、同じ日の追加の依頼「画面を見て確認する UI のテストの項目も共通のテストデータに追加して」。

Windows 版には「Mac 版と同じ（両方を直す）」と書いた箇所が約 30 あり、片方だけ直すとずれる。Rust で処理を共有するのは、今はまだやらない（ビルドと配布が重くなるわりに、共有できるロジックが小さいため）。代わりに次の 3 つで、ずれを止めて、機械で見つけられるようにする。

1. **共有のデータ**（`common/resources/`）: プロンプト・モデルの一覧・選択肢と既定値を 1 か所に置き、両方の版が読む。
2. **ロジックのテストデータ**（`common/testdata/logic/`）: 入力と期待する出力の組を置き、C# のテストと Mac の自己テストの CLI の両方で通す。
3. **UI のテスト項目**（`common/testdata/ui/`）: 画面を見て確かめる項目（今の `docs/verification/ui-ux-test-cases.md` の UX-001〜132）をデータにし、Mac では画面を PNG にして自動で確かめられるようにする。

ユーザーに見える振る舞いは変えない。そのため、新しい要件（REQ）は作らず、設計判断（DEC）だけを足す。

## ユーザーと決めたこと（2026-11-08）

- UI のテスト項目は、Mac では自動で実行できる形にする。
- spec で「確かめ方: 実機で確かめる」となっている要件に UI のテスト項目がないときは、検査で**警告**にする（CI は落とさない）。抜けている項目は、この変更で書き足す。
- `docs/verification/ui-ux-test-cases.md` はデータから作る（手では直さない）。

## 設計判断の案

段階 C を先に実装したので、設計判断 C を DEC-COM-170 にした。A・B は spec に書くときに 170 番台の続きの空きから取る。

### 設計判断 A: Mac と Windows で共有するデータは common/resources に置き、ビルドで埋め込む
- 決めたこと: プロンプト（`common/resources/prompts/<言語>.json`）と、両方の版が同じ値を持つデータ（`common/resources/models.json`: ローカル LLM・Whisper・Gemini・Claude のモデルの一覧・既定値・SHA-256、`common/resources/choices.json`: 履歴の日数・件数の選択肢、タイムアウト、やり直しの回数）を置く。Mac は `common/` を path にしたリソースだけの SwiftPM の target（`HanasuCommon`。空の `.swift` を 1 つ置く）で入れ、Windows は `Hanasu.Core` に EmbeddedResource として埋め込む。実行中にユーザーのフォルダから読み直すことはしない。
- 理由: DEC-COM-160 で、プロンプトの文面はすでに 1 つのファイルを両方の版が読んでいる。ただ置き場所が Mac のフォルダなので、共有のものだと分かりにくい。値の二重持ち（`LocalLLMModel.swift` と `LocalLlmModel.cs` など）もなくせる。SHA-256 は安全に関わる値なので、ビルドで埋め込むだけにする。
- 関係する要件: REQ-COM-030, REQ-COM-001, REQ-COM-061
- 対象: Mac / Windows
- DEC-COM-160 の「置き場所」を書き直す。

### 設計判断 B: Mac と Windows で同じ決まりのロジックは、共有のテストデータで確かめる
- 決めたこと: `common/testdata/logic/<名前>.json` に `{ "cases": [{ "name", "input", "expected" }] }` の形で置く。C# は `Hanasu.Core.Tests` がファイルを読んで回し、Mac は `--test-shared-cases`（自己テストの CLI。mac.yml で動かす）が回す。
- 対象（最初に入れるもの）: `UserDictionary`（語と置き換えルールの読み取り・適用）、`SpeakerNameInference`、`ActionItem` の Markdown の読み取り、議事録のプロンプトの組み立て（`MinutesPrompt`）、`LongInputFitter`、`PromptLanguage` / 文字起こしの言語の決め方。
- 理由: ロジックを Rust で共有するよりビルドが軽く、Mac でも `dotnet test` が動いたまま、ずれを CI で見つけられる。
- 関係する要件: REQ-DIC-070, REQ-MTG-027, REQ-MTG-017, REQ-COM-061
- 対象: Mac / Windows

### 設計判断 C（→ DEC-COM-170）: 画面を見て確かめる UI のテスト項目は common/testdata/ui に置き、Mac は画面を PNG にして確かめる
- 決めたこと:
  - `common/testdata/ui/<節>.json`（`onboarding`・`dictation`・`edit`・`history`・`meeting`・`settings`・`cross`）に、1 項目ずつ次の形で置く。

    ```json
    {
      "id": "UX-010",
      "steps": "ショートカットで録音を始め、もう一度で止める",
      "expected": "HUD が出て、認識中のテキストと音量が動く。…",
      "os": ["mac", "windows"],
      "priority": "P1",
      "refs": ["REQ-DIC-001", "REQ-DIC-002", "REQ-DIC-003", "REQ-DIC-004", "REQ-DIC-014"],
      "automation": {
        "mac": { "kind": "render", "args": ["--render-hud", "{out}"], "look": "録音中の HUD に経過時間・音量・取消・停止が出ている" },
        "windows": { "kind": "manual", "reason": "Windows を Mac から動かせない" }
      }
    }
    ```

    - `refs` は範囲（〜）を使わず、ID を 1 つずつ書く。
    - `automation.<OS>.kind` は次の 3 つ。
      - `render`: 既定。アプリの `--render-*`（画面を PNG にする自己テストの CLI）で描いて確かめる。`{out}` は出力のフォルダに置き換える。`look` は PNG で見る観点（省くと `expected`）。
      - `drive`: 本物のアプリを起動して操作する。今回は値だけ決め、動かす仕組みは作らない（FUT-018）。
      - `manual`: 人が確かめる。`reason` に理由（本物のマイク・ネットワークを切る・OS の許可のダイアログ・VoiceOver・複数のディスプレイ・長時間の録音など）を書く。
  - `scripts/ui-cases.py` を足す（python3 の標準ライブラリだけ）。
    - `check`: 形・ID の重なり・`refs` が spec にあり廃止されていないこと・`render` の `--render-*` が `Sources/Hanasu/main.swift` にあること・生成した Markdown が最新であることを確かめる。spec で「確かめ方」に「実機」とある要件で、どの項目の `refs` にもないものは警告にする。エラーがあれば終了コード 1。
    - `md`: `docs/verification/ui-ux-test-cases.md` を作り直す（先頭に「生成したファイル。手で直さない」と書く）。
    - `render [--ids UX-010,…] [--priority P1] [--lang ja,en|all] [--out <フォルダ>]`: `.build/debug/Hanasu` で `render` の項目を描き、`<out>/<言語>/<ID>/*.png` と、ID・PNG・`look`・`expected` を並べた `<out>/manifest.json` を書く。描けなかった項目（終了コードが 0 でない・PNG がない）は manifest に失敗として書く。
  - `.claude/skills/ui-test/SKILL.md` を足す。`swift build` → `ui-cases.py render` → manifest の PNG を 1 つずつ読み、`look` を満たすかを OK / NG / 判断できない で判定する → 日付つきの結果を `docs/verification/dictation.md`・`meeting.md` の実施の記録に書く → NG を PNG のパスと一緒に報告する。「UI のテストをして」「画面を確かめて」「UX-0xx を確かめて」などの依頼で使う。
  - CI（`spec.yml`）で `ui-cases.py check` を動かす。描画と見た目の判定は CI ではしない（判定にモデルが要るため）。
- 理由: 項目が Markdown の表だけだと、要件との対応も、どれを自動で見られるかも、機械で確かめられない。画面を PNG にする CLI はすでに 25 種あり（`--render-hud`・`--render-settings`・`--render-history` など）、`--ui-language` で 17 言語の見た目も描ける。これを使えば、許可やマイクがなくても決まった状態の画面を毎回同じに描ける。本物のアプリを操作する方法は、アクセシビリティと画面収録の許可が要り、壊れやすいので後に回す。
- 関係する要件: なし（確かめ方の仕組み）。spec の「確かめ方」と対応を取る。
- 対象: Mac（Windows の項目はデータだけ持ち、すべて `manual`）

## やらないこと

- 共通の処理を Rust で書く。共有のテストデータで足りなくなったら、範囲をテキストの処理に絞って考え直す。
- 本物のアプリを起動して操作する `drive` の実行の仕組み → FUT-018。
- Windows の UI の自動実行（描画の CLI がない。Mac から動かせない）→ FUT-019。
- 要件の「確かめ方」の書き換え（UX の ID を書き足すなど）。対応はデータの `refs` で取る。
- UI の文字列は動かさない（Mac は `.xcstrings`、Windows は `.resx` で形が違う）。UI のテスト項目は文書なので日本語だけで書く（17 言語の訳の決まりの対象外）。

## 手順

段階 A・B・C は触るファイルが重ならないので、別々に進められる（C は A のあとの `Package.swift` に触らない）。

### 段階 A: common/resources（設計判断 A）
1. spec に 設計判断 A を足し、DEC-COM-160 の置き場所を直す。
2. `git mv Sources/Hanasu/Resources/Prompts common/resources/prompts`。
3. `Package.swift` に `HanasuCommon`（path: `common`、resources: `.copy("resources")`）を足し、`Hanasu` から依存する。`HanasuResources`（`Prompts.swift`）と `scripts/build-app.sh` の探す場所を新しいバンドルに合わせる。
4. `windows/Hanasu.Core/Hanasu.Core.csproj` の EmbeddedResource のパスを直す（リソース名 `Hanasu.Prompts.<言語>.json` は変えない）。
5. `models.json`・`choices.json` を作り、Mac（`LocalLLMModel`・`ClaudeModel`・`Settings.suggestedModels`・Whisper のモデル）と Windows（`LocalLlmModel`・`ClaudeModels`・`AppSettings.SuggestedModels`・`WhisperModels`・`DictationHistory` の選択肢）を、JSON から読む形に替える。値は変えない。
6. `scripts/check-i18n.py`、`.claude/skills/i18n/SKILL.md`、`.claude/agents/i18n.md`、`CLAUDE.md`、`docs/README.md`（文書の地図に common/）、`windows/README.md`、design の該当箇所のパスを直す。

### 段階 B: ロジックのテストデータ（設計判断 B）
1. spec に 設計判断 B を足す。
2. 対象のロジックごとに、今の C# のテスト（`UserDictionaryTests`・`SpeakerNameInferenceTests`・`MeetingTests` の ActionItem と議事録・`LocalLlmTests`・`UiLanguageTests`）から入力と期待を取り出して `common/testdata/logic/*.json` にする。
3. `Hanasu.Core.Tests` に、JSON を読んで回す `[Theory]` を足す（csproj で `common/testdata/logic` を出力にコピーする）。
4. Mac に `--test-shared-cases`（新しいファイル `SharedCasesCLI.swift`）を足し、`.github/workflows/mac.yml` の自己テストに加える。`// 確かめ方:` のタグを付ける。

### 段階 C: UI のテスト項目（設計判断 C）
1. spec に 設計判断 C を足し、roadmap に FUT-018・FUT-019 を足す。
2. `scripts/ui-cases.py` を書く。最初は今の Markdown の表を読んで `common/testdata/ui/*.json` に変える 1 回だけの変換（`import-md`）を付け、変換したら消す。
3. 97 項目の `automation.mac` を決める。既存の `--render-*` で画面が描けるものは `render`（`args` と `look`）にし、ほかは `manual` と理由。足りない描画（例: 権限の画面・アップデートの確認）は、描画の CLI を足すか `manual` にする（足すのは、既存の描画の関数に状態を渡すだけで済むものに限る）。
4. 「実機で確かめる」の要件で項目がないもの（REQ-COM-010・011・022・031・032・060、REQ-DIC-008・014・040・062・083・084、REQ-MTG-013・020・022・023・024・027・029・034・040、REQ-REL-010・011 など約 20 件）に、項目（UX-133〜）を書き足す。
5. `ui-cases.py md` で `docs/verification/ui-ux-test-cases.md` を作り直す。実施の記録の表は `docs/verification/dictation.md`・`meeting.md` に移す。
6. `.claude/skills/ui-test/SKILL.md` を書き、`spec.yml` に `python3 scripts/ui-cases.py check` を足す。`docs/README.md` の文書の地図に `common/testdata/ui` とスキルを書く。

## 確かめ方

- `swift build`、`scripts/build-app.sh` で作った .app でプロンプトが読める（`--show-prompts`）。
- `cd windows && dotnet test Hanasu.Core.Tests`（JSON の組のテストを含む）。
- `.build/debug/Hanasu --test-shared-cases`。
- `python3 scripts/check-spec.py`、`python3 scripts/check-i18n.py`、`python3 scripts/ui-cases.py check`（警告の数を PR に書く）。
- `python3 scripts/ui-cases.py render --priority P1 --lang ja,en` を動かし、ui-test のスキルで判定まで通す。結果を `docs/verification/` に書く。
- 実機: 作った .app を起動し、音声入力の整形と議事録の作成が今までどおり動く（プロンプトとモデルの一覧を読めている）。

## 仮に決めたこと（了承のときに見てほしいもの）

- フォルダ名は `common/resources`（複数形）と `common/testdata`。
- 自動実行は、画面を PNG に描いて判定する方法（`render`）だけを作る。本物のアプリを操作する方法（`drive`）は FUT-018 に回す。
- 見た目の判定は Claude（ui-test のスキル）が PNG を読んで行い、CI では描画も判定もしない。CI は `check` だけ。
- 段階 A・B・C は 1 つの PR にせず、段階ごとに PR を分ける（C は A と B を待たずに進められる）。
