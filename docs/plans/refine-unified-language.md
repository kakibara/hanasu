# 整形の言語の「〜に統一」を、利用者の言語にそろえる

状態: 実装済み（2026-11-13。spec は REQ-DIC-082・DEC-DIC-200・201。2026-11-13 に計画を了承）

## 目的
2026-11-12 の依頼「整形の言語が『日本語に統一』しかないのは、多言語化として問題ではないか」。

今の「整形の言語」は「話した言語」と「日本語に統一」の 2 択で、そろえる先が日本語に固定されている（REQ-DIC-082。DEC-COM-162 で「どの言語でも日本語にする」と決めていた）。そのため韓国語の利用者にも「Always Japanese（日本語に統一）」が出て、役に立たない。

そろえる先を利用者の言語にして、どの言語の利用者にも意味のある選択肢にする。ここでの「利用者の言語」は、プロンプトの言語（文字起こしの言語。REQ-COM-061）のこと。

ユーザーに確かめたこと（2026-11-13）:
- 選択肢は「話した言語」と「〈自分の言語〉に統一」の 2 択にする。17 言語から選ぶ形にはしない。ほかの言語にそろえたいときは翻訳を使う。
- 今「日本語に統一」を保存している人は、「〈自分の言語〉に統一」として読む。文字起こしの言語が日本語の人は何も変わらない。
- 表示は日本語で、文字起こしの言語が日本語でない人（例: 英語）は、「英語で話して日本語で入れる」使い方がこの設定ではできなくなる。それでよい。和訳で代える。

## 変える要件（ユーザーの合意が要る）

### REQ-DIC-082 整形の出力の言語を設定で選べ、既定は話した言語にする
- 名前: 今のまま。

**内容**
- 今:「『話した言語』（既定）と『日本語に統一』から選べる」
- 変更後:「『話した言語』（既定）と『〈利用者の言語〉に統一』から選べる。利用者の言語は、プロンプトの言語（文字起こしの言語。REQ-COM-061。対応言語にない言語なら英語）。既定では、ほかの言語で話した部分はその言語のまま残し、訳さない」

**受け入れ条件（変える・足すもの）**
- 2 つめの選択肢の名前は、プロンプトの言語の名前を表示の言語で書いたもの。
  - 表示が日本語・プロンプトが日本語なら「日本語に統一」。
  - 表示もプロンプトも韓国語なら「한국어로 통일」。
  - 表示が英語・プロンプトが日本語なら「Always Japanese」。
  - 表示が日本語・プロンプトが英語なら「英語に統一」。
- 「〈利用者の言語〉に統一」では、ほかの言語で話した部分も利用者の言語になる。固有名詞・製品名・コードなど、訳すと意味が変わるものは原語のまま残す。
- 文字起こしの言語を変えたら、選択肢の名前とそろえる先の言語もそれに合わせて変わる。設定は「統一する」のまま。
- 対応言語にない文字起こしの言語（例: スウェーデン語）では、英語に統一する（名前も英語。REQ-COM-061 と同じ）。
- 前の版で「日本語に統一」を保存していた人は、「〈利用者の言語〉に統一」になる。文字起こしの言語が日本語の人は、名前も出力も今と同じ。
- 文字起こしの言語が日本語でない人は、「〈利用者の言語〉に統一」で日本語にそろえることはできなくなる。日本語にしたいときは和訳（REQ-DIC-013）を使う。
- プロンプトの言語が日本語のとき、整形に送るプロンプト（system・user）は今と一字一句同じ。`--show-prompts` の見出しの名前だけが変わる。
- 今ある条件（整形がオフのときは選べない、指示は 1 つだけ入る、履歴の「整形し直す」も同じ設定に従う）は変えない。

**出典**
- 足す: 2026-11-12 の依頼「日本語に統一しかないのは多言語化として問題か」。そろえる先を利用者の言語にすること、今の保存値の扱い、表示と文字起こしの言語が違う人の扱いは、2026-11-13 にユーザーに確かめた（了承の日付を足す）。
- 消す: 「プロンプトの言語が日本語でないときも、『日本語に統一』は日本語にする（DEC-COM-162）」。

**Windows の実装**
- 「選択肢は『話した言語』『日本語に統一』」を新しい名前に直す。

**確かめ方**
- 次の CLI・テストに差し替える。
  - Mac の自己テスト `--test-refine-language`（下）。
  - `--show-prompts` の前後の比べ方。
  - Windows のテストのフィルタ（`FullyQualifiedName~UnifiedOutputLanguage|FullyQualifiedName~RefineOutputLanguage`）。

### DEC-COM-162（設計判断。書き換える）
- 「整形の言語の『日本語に統一』（REQ-DIC-082）は、プロンプトの言語によらず今のまま（どの言語でも日本語にする）」を直す。直したあと:「整形の言語の統一の先は、プロンプトの言語（DEC-DIC-200）。日本語の文面は今のまま」。
- 「出力が日本語（和訳・日本語に統一）のとき」を「出力が日本語（和訳）のとき」に直す。
- 理由の「要件（REQ-DIC-082・013）は変えない」に、追記を足す:「REQ-DIC-082 は、のちに 2026-11-12 の依頼で統一の先を変えた」。
- 理由: どの言語でも日本語にすると、日本語以外の利用者には役に立たない選択肢になる。

### DEC-DIC-028（設計判断。一部を書き換える）
- 「整形の『日本語に統一』（REQ-DIC-082）も同じ」を消す。これは「出力が日本語なら ja.json の文体ルールを使う」という決まり。
- 実装の場所の「`AppStyle.promptSection`（`japaneseOutput`）」を直す。
- 統一の先はプロンプトの言語になる。そのため整形の文体ルールと画面の文脈の指示は、話した言語のときと同じく、プロンプトの言語の文面になる（DEC-DIC-200）。
- 和訳の扱いは変えない。

## 設計判断の案

### DEC-DIC-200 整形の言語の統一の先は、プロンプトの言語にし、文体のルールもその言語の文面を使う

**決めたこと**
- 統一の先は、Mac は `PromptLanguage.current`、Windows は `PromptLanguage.Current`。
- 設定に保存するのは「統一する」ことだけで、言語は保存しない。文字起こしの言語を変えたら、それに合わせて変わる。
- 指示のキーは `refine.outputLanguage.unified`。今の `refine.outputLanguage.japanese` の名前を変える。
  - 各言語の JSON に、その言語自身にそろえる文面を書く。
  - ja.json は今の `refine.outputLanguage.japanese` と一字一句同じ。
  - 言語名を `${language}` で埋めない。その言語の JSON が自分の言語を書けばよい。
- 統一のときの次の 3 つは、話した言語のときと同じにする（プロンプトの言語の文面）。出力がプロンプトの言語なので合う。
  - アプリ別の文体ルール
  - 画面の文脈の整形の指示
  - 共通の追加の整形ルール
- そのため、Mac の整形の経路の `japaneseOutput` の引数をなくす（`AppStyle.promptSection`・`ScreenContext.instruction`）。Windows の `AppStyle.PromptSection` には、もともとこの引数がない。

**理由**
- 2026-11-13 にユーザーに確かめた形。17 言語から選ぶ形は、翻訳（REQ-DIC-013）と役割が重なり、一覧も長くなる。
- 統一の先と文体ルールの言語が同じになる。そのため、DEC-DIC-028 の「日本語の出力には ja.json の文体ルール」という例外が、整形では要らなくなる。

**そのほか**
- 関係する要件: REQ-DIC-082, REQ-COM-061
- 対象: Mac / Windows

### DEC-DIC-201 保存する値は今のまま（`japanese` / `Japanese`）にし、意味を「統一する」に変える

**決めたこと**
- 保存する値は、Mac は今の `japanese`、Windows は今の `Japanese` のまま変えない。
- 意味は「プロンプトの言語に統一する」に変える。
- コードの名前は、Mac は `.unified`、Windows は `Unified` にする。保存する値だけを今のまま残す。
  - Mac: rawValue を `japanese` にする。
  - Windows: `[JsonStringEnumMemberName("Japanese")]` などで、JSON の名前を今のままにする。
- 値の横に、この判断のコメントを書く。

**理由**
- 前の版に戻しても、設定が読める。
- Windows は `JsonStringEnumConverter` で読む。知らない値があると `JsonException` になり、設定全体が初期値に戻る（`SettingsStore.Load`）。
- 同じ理由で値を変えない先例がある（DEC-DIC-027・153）。

**そのほか**
- 関係する要件: REQ-DIC-082
- 対象: Mac / Windows

## やらないこと
- 統一の先を 17 言語から選べるようにする（ユーザーの判断。ほかの言語にそろえたいときは翻訳 REQ-DIC-013 を使う）。roadmap にも足さない。
- 表示の言語と文字起こしの言語が違うときに、「〈表示の言語〉に統一」を足す（2026-11-13 のユーザーの判断。和訳で代える）。
- 翻訳（和訳・英訳など）の文面は変えない。和訳のときの文体ルールの扱い（DEC-DIC-028 の和訳の部分）も変えない。
- 文字起こしの言語の決め方（REQ-COM-061・062）は変えない。

## 手順

**0. 前の出力を取っておく（変更の前）**
- `swift build` のあと、`.build/debug/Hanasu --show-prompts --prompt-language ja > <スクラッチ>/before-ja.txt` を取る。

**1. spec と文書を直す**
- `docs/spec/dictation.md`
  - REQ-DIC-082 の内容・受け入れ条件・出典（古い一文を消す）・Windows の実装・確かめ方。
  - DEC-DIC-028 の決めたことと実装の場所。
  - DEC-DIC-200・201 を足す。DEC-DIC-08x・09x は埋まっているので、空いている 200 から使う。
- `docs/spec/common.md` の DEC-COM-162（3 か所）。
- `docs/design/dictation.md` の「整形の言語」の説明。

**2. i18n の決まりを直す（手順 4 の前）**
- `.claude/agents/i18n.md` の 23 行の「やらないこと」。
- `.claude/skills/i18n/SKILL.md` の 50 行と 70 行。
- 新しい決まり:
  - `refine.outputLanguage.unified` は、その言語自身にそろえる指示。言語名を `${…}` で埋めない。
  - zh-CN は簡体字の中国語、zh-TW は繁体字の中国語、pt-BR はブラジルのポルトガル語にそろえると書く。
  - UI の「〈言語〉に統一」は、言語名を `%@` で入れる。
  - 「日本語」「和訳」はどの言語でも日本語の意味のまま（「日本語に統一」は外す）。

**3. Mac（`Sources/Hanasu/`。手順 4 の Windows と独立）**
- `GeminiClient.swift`:
  - `RefineOutputLanguage` の `.japanese` を `.unified` にする。rawValue は `japanese` のまま（DEC-DIC-201）。
  - `label` は `tr("%@に統一", TranslationLanguage(PromptLanguage.current).nameInUILanguage)`。
  - `instruction` は `refine.outputLanguage.unified` を読む。
  - `refinePrompt`・`userPrompt` から `japaneseOutput` を外す。
- `AppStyles.swift`（`AppStyle.promptSection`。38 行・137〜144 行の注記も直す）と `ScreenContext.swift`（`ScreenContext.instruction`。89 行の注記も直す）から、`japaneseOutput` の引数をなくす。呼び出し元も直す。
- `Settings.swift`: rawValue が今のままなので、読み込みは直さない。
- 自己テストの CLI `--test-refine-language` を足す（`RefineLanguageCLI.swift` を新しく作り、`main.swift` から呼ぶ）。確かめること:
  - 保存値 `japanese` が `.unified` に、`asSpoken` が `.asSpoken` に、知らない値が `.asSpoken` になる。
  - `--ui-language`・`--prompt-language` の組み合わせ（ja/ja・en/ja・ko/ko・ja/en）で、`.unified.label` が受け入れ条件の名前になる。
  - `.unified.instruction` が、そのプロンプトの言語の JSON の `refine.outputLanguage.unified` と同じ。
  - ラベルを標準出力に出す。
  - 付けるタグ: `// 確かめ方: REQ-DIC-082`。
- `PromptsCLI.swift`: そのまま（allCases を回す。見出しは `refine japanese` のまま。rawValue が変わらないため）。
- タグ: `// 要件: REQ-DIC-082`、`// 設計判断: DEC-DIC-200`・`DEC-DIC-201`。

**4. Windows（`windows/`。手順 3 と独立）**
- `Hanasu.Core/Settings/AppSettings.cs`:
  - `RefineOutputLanguage.Japanese` を `Unified` にする。
  - JSON の名前は `Japanese` のまま（DEC-DIC-201）。
  - 52 行の注記を直す。
- `Hanasu.Core/Gemini/GeminiPrompts.cs`: `JapaneseLanguageInstruction` を `UnifiedLanguageInstruction`（`refine.outputLanguage.unified`）にする。54 行の注記も直す。
- `Hanasu.Windows/Views/SettingsWindow.xaml(.cs)`:
  - 項目の Tag を `Unified` にする。
  - 名前は `string.Format(Strings.Settings_RefineLanguage_Unified, TranslationLanguage.Of(PromptLanguage.Current).NameInUiLanguage())` で入れる。
  - 設定を読み込むたびに名前を入れ直す。
- `Hanasu.Windows/Properties/Strings*.resx`（17 言語）: `Settings_RefineLanguage_Japanese` を `Settings_RefineLanguage_Unified`（`{0}` に言語名）にする。
- テスト（`Hanasu.Core.Tests`）:
  - `GeminiTests.JapaneseOutputLanguageInstructionIsCopiedFromMac` の名前を `UnifiedOutputLanguageInstructionIsCopiedFromMac` にする。日本語と韓国語で、JSON の文面と同じことを見る。
  - `SettingsTests` に足す: `"Japanese"` の保存値が `Unified` で読めること、`Unified` を保存すると `"Japanese"` で書かれること。
  - 付けるタグ: `// 確かめ方: REQ-DIC-082`。

**5. 訳（i18n スキル。手順 2〜4 のあと）**
- プロンプト: 17 の `Sources/Hanasu/Resources/Prompts/<言語>.json` の `refine.outputLanguage.japanese` を `refine.outputLanguage.unified` にする。ja 以外は、その言語自身にそろえる文面に書き直す（ja は今のまま）。
- Mac の UI: `tr("%@に統一")` を足して `python3 scripts/i18n-strings.py sync` を通し、17 言語の訳を入れる。「日本語に統一」のキーはなくなる。
- Windows の resx（手順 4）。
- 言語の格・助詞は、`%@訳` の先例のように、言語名の形が変わらない言い方にする（例: ロシア語「Всегда: %@」の形）。
- i18n エージェントに、言語を 3 つ程度ずつ分けて任せる。

**6. UI のテスト項目**
- `common/testdata/ui/edit.json` の UX-152 の steps・expected・look を、「〈利用者の言語〉に統一」に直す。
- `python3 scripts/ui-cases.py md` と `check` を通す。

**7. PR**
- 本文の「気をつけること」に書く:
  - 日本語以外の文字起こしの言語で「日本語に統一」を選んでいた人は、更新すると自分の言語に統一になる。
  - 表示と文字起こしの言語が違う人は、日本語にそろえるには和訳を使う。
- リリース文を書くときに拾えるようにする。

## 確かめ方
- `swift build`
- 次の 2 つの差分がないこと（rawValue を変えないので、見出しも同じ）:
  - `.build/debug/Hanasu --show-prompts --prompt-language ja > after-ja.txt`
  - 手順 0 の before-ja.txt
- `.build/debug/Hanasu --show-prompts --prompt-language ko`（ほかに en・zh-CN）で、`refine japanese / system` を見る。
  - 最後の指示が、その言語にそろえる内容である。
  - 文体ルール・画面の文脈の指示も、その言語の文面である。
- `.build/debug/Hanasu --test-refine-language`（受け入れ条件の名前・前の値の読み方・指示の文面）
- `python3 scripts/check-spec.py`、`python3 scripts/check-i18n.py`、`python3 scripts/ui-cases.py check`
- `cd windows && dotnet test Hanasu.Core.Tests`。WPF の画面とリソースは、PR の Windows の CI（`dotnet build Hanasu.Windows.sln`）が通ることで確かめる。
- UI: ui-test スキルで UX-152 を描く。`--render-settings` は今の選択だけを描くので、2 つめの名前は `--test-refine-language` で確かめる。
- 実機: 文字起こしを日本語にして、英語の混ざった発話を「日本語に統一」で入れる。今と同じく日本語になること。

## 敵対的レビュー
2026-11-13、requirements-reviewer（Opus）1 つ、1 回。

| # | 重さ | 指摘 | 仕分け | どうしたか |
| --- | --- | --- | --- | --- |
| 1 | 重大 | Windows で保存値を `Unified` に変えると、前の版に戻したときに `JsonException` になり、設定全体が初期値に戻る | 直す | DEC-DIC-201 を「保存値は今のまま、意味を変える」に書き換えた（`SettingsStore.Load` で確かめた。先例は DEC-DIC-027・153） |
| 2 | 重大 | i18n のエージェントとスキルが「`refine.outputLanguage.japanese` を自分の言語に変えない」と決めたまま | 直す | 手順 2 に、3 か所を直す手順を足した |
| 3 | 重大 | 「日本語の利用者は変わらない」は文字起こしの言語で決まる。表示が日本語で文字起こしが英語の人は、日本語に統一できなくなる | 聞く | ユーザーの答え「そのままでよい」を受け入れ条件・やらないこと・PR の注意に入れた |
| 4 | 重大 | `--render-settings` は今の選択しか描かず、名前と前の値の読み方を確かめられない | 直す | 自己テスト `--test-refine-language` と手順 0（変更の前の出力）を足した |
| 5 | 軽微 | spec・注記に「日本語に統一」の前提が残る（REQ の出典・Windows の実装・テストのフィルタ、DEC-COM-162 の 3 か所、DEC-DIC-028 の実装の場所、コードの注記） | 直す | 手順 1・3・4 に箇所を挙げた |
| 6 | 軽微 | Windows の `Prompts.Current`・`NameInUiLanguage` の名前の誤り | 直す | `PromptLanguage.Current`・`TranslationLanguage.Of(…).NameInUiLanguage()` に直した |
| 7 | 軽微 | 対応言語にない文字起こしの言語では英語に統一になる | 直す | 受け入れ条件に足した |
| 8 | 軽微 | Windows の画面のコードは `Hanasu.Core.Tests` ではビルドされない | 直す | 確かめ方に Windows の CI を足した |
| 9 | 軽微 | 出力が変わる利用者のことをリリース文に残す手順がない | 直す | 手順 7 に PR の本文の注意を足した |

見られなかったこと（実装と訳のときに見る）:
- 17 言語の「〈言語〉に統一」の文法（格・助詞）。
- Windows で、設定のウインドウを開いたまま文字起こしの言語が変わったときに、名前が変わるか。
- ローカルの LLM の結果の検査（`LocalLLMClient.cleanUpRewrite`）が、統一で訳した結果をどう扱うか。今の「日本語に統一」と同じ扱いになる見込み。

## 仮に決めたこと
- 統一のときも、共通の追加の整形ルールを使う（今と同じ。出力がプロンプトの言語なので合う）。
- 英語の表示での名前は「Always 〈言語名〉」にする（今の「Always Japanese」に合わせる）。各言語の言い方は訳のときに決める。
- 自己テストの CLI の名前は `--test-refine-language` にする。
