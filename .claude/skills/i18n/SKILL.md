---
name: i18n
description: Hanasu の多言語（17 言語）の手順。AI へのプロンプトや UI の文字列を足す・変えるときに、すべての対応言語の訳を入れ、scripts/check-i18n.py で漏れを確かめる。プロンプトのキーの足し方、言語ごとの書き直し方（直訳しない）、訳を i18n エージェントに任せる方法、Mac と Windows で同じ文面にする仕組みを書く。「プロンプトを足して」「この文言を直して」「新しい設定項目を足して」「訳を入れて」「多言語に対応させて」「check-i18n が落ちた」などのとき、また新しい機能でユーザーに見える文字列か AI への指示を足すときは必ず使う。
---

# Hanasu の多言語

決まり（なぜ・何を）は [docs/README.md](../../../docs/README.md) の「8. 多言語」、要件は REQ-COM-061・062、設計判断は DEC-COM-160〜164（[docs/spec/common.md](../../../docs/spec/common.md)）。ここには手順を書く。

## 対応言語

README と同じ 17 言語。並びも同じにする（`scripts/check-i18n.py` の `LANGUAGES`、Mac の `PromptLanguage`、Windows の `PromptLanguage`）。

| コード | 言語 | コード | 言語 | コード | 言語 |
| --- | --- | --- | --- | --- | --- |
| en | 英語（どれでもないときの既定） | es | スペイン語 | tr | トルコ語 |
| ja | 日本語（基準） | fr | フランス語 | vi | ベトナム語 |
| zh-CN | 中国語（簡体字） | de | ドイツ語 | id | インドネシア語 |
| zh-TW | 中国語（繁体字） | it | イタリア語 | pl | ポーランド語 |
| ko | 韓国語 | pt-BR | ポルトガル語（ブラジル） | ar | アラビア語 |
| | | ru | ロシア語 | hi | ヒンディー語 |

言語を足すときは、この 3 か所と `Sources/Hanasu/Resources/Prompts/<コード>.json` を足し、`PromptLanguage.from(localeIdentifier:)`（Mac・Windows）の寄せ方を見直す。各言語の JSON に新しい言語の `languageName.<コード>` も足す（翻訳の言語・アプリ別の出力言語は `PromptLanguage` から作り、言語名はここから読むので、ほかに足す所はない。DEC-DIC-150）。

## AI へのプロンプト

### 仕組み
- 文面は `Sources/Hanasu/Resources/Prompts/<言語>.json` だけに置く。キー → 文字列か、1 行 1 要素の配列（`style.*.refine` / `style.*.translation` だけは 1 ルール 1 要素）。`${name}` はアプリが埋める。
- Mac: `Prompts.text("キー", ["name": 値])`、`Prompts.list("キー")`、読み取り用に全言語の文面を集める `Prompts.allTexts("キー")`（`Sources/Hanasu/Prompts.swift`）。
- Windows: 同じ JSON を `Hanasu.Core` に埋め込み、`windows/Hanasu.Core/Ai/Prompts.cs` の同じ名前の関数で読む。**文面を Windows のコードに書き写さない。**
- どの言語を使うかは、設定の文字起こしの言語（`PromptLanguage.current`）。その言語にないキーは英語、英語にもなければ日本語（漏れは CI で落ちるので、ふだんは起きない）。
- ja.json は今までの文面と一字一句同じ。en.json は言語によらない形の英語で、ほかの言語の元になる。

### プロンプトを足す・変える手順
1. 日本語の文面を ja.json に書く（キーは `機能.部分` の形。例 `minutes.speakerNames`）。日本語の文面を変えるときは、変える前に `--show-prompts` の出力を取っておく。
2. コードではキーで読む（`Prompts.text`）。Swift・C# の中に文面を書かない。埋めるものは `${name}` にする（`{}` や `{{…}}` はプロンプトの JSON の例と紛れるので使わない）。
3. en.json に英語を書く。日本語に固有の例（「えー」「改行」「です・ます」）は、英語の話し言葉の例に置き換える。
4. ほかの 15 言語を書く。量が多いので、[.claude/agents/i18n.md](../../agents/i18n.md) のエージェントに、言語をいくつかずつに分けて並べて任せる（下の「訳を任せる」）。
5. Windows でも使うなら、Windows のコードでも同じキーを読む。
6. 確かめる（下の「確かめる」）。

### 訳の書き方（エージェントにも同じことを渡す）
- **直訳しない。** その言語で話す人が音声入力したときの指示として書き直す（DEC-COM-162）。
  - フィラー・言い直しの言葉・口頭の記号の指示（「改行」「句点」）・決まり文句・挨拶は、その言語で実際に言うものにする。
  - 誤認識の例は、その言語で起きやすいもの（中国語の同音字、ベトナム語の声調、ドイツ語の複合語の切れ目など）にする。
  - 文体のプリセット（chat・email・documentPolite・documentPlain）は、その言語の本当の文体に当てる（韓国語の 합니다체／한다체、T–V の区別がある言語は話者の使った呼び方を変えない）。
  - 「やること・やらないこと」の項目は減らさず、足さない。
- **変えないもの**: `${…}`、タグ（`<transcript>`・`<action_items>`・`<selection_…>` など）、例の JSON のキー（`"owner":` など）、`null`・`{}`・`[]`、`MM:SS.s`、`[--:--]`、`★`、`→`、`## `、`M2:`（会議への質問の引用。アプリが `M<番号>:` を読む）。
- **同じ言語の中でそろえるもの**: 話者のラベル（`speaker.me`・`speaker.remote`・`speaker.room`・`speaker.others`）は、`minutes.intro`・`minutes.speakerNames`・`minutes.actionItems`・`minutes.common`・`minutes.notes`・`ask.system` に同じ文字列で出す。「なし」（`minutes.result.none`）は `minutes.format` と `minutes.sections.sales` に同じ語で出す。「ここ重要」（`minutes.notes.highlight`）は `minutes.notes` の印の名前と同じにする。
- `refine.outputLanguage.unified` は、その言語自身にそろえる指示（ko.json なら「韓国語に統一する」。設定の名前が「〈プロンプトの言語〉に統一」のため。REQ-DIC-082・DEC-DIC-200）。言語名を `${…}` で埋めず、その言語の名前をそのまま書く。zh-CN は簡体字の中国語、zh-TW は繁体字の中国語、pt-BR はブラジルのポルトガル語と書く。`translate.english.system` はその言語→英語、`translate.japanese.system` はその言語→日本語の指示にする。
- 議事録・要点・会議への答えを「どの言語で書くか」は、その言語にする（`minutes.intro`・`longInput.part`・`ask.system`）。

### 訳を任せる
- `.claude/agents/i18n.md` のエージェント（`subagent_type: "i18n"`）に、言語を 3 つ程度ずつ分けて並べて渡す。渡すもの: 足した・変えたキーの一覧、ja.json と en.json のその値、上の「訳の書き方」。
- エージェントは自分の言語のファイルだけを直し、`python3 scripts/check-i18n.py` を通してから返す。ほかのファイル・ビルド・コミットは任せない（並べて走らせると取り合うため）。
- 戻ってきたら、親が `--show-prompts --prompt-language <言語>` で 1 つ 2 つ目で確かめる。

## UI の文字列（Mac）

### 仕組み
- 利用者に見える文字列は `tr("日本語の原文")`、補間があれば `tr("…%@…", 値1, 値2)`（`Sources/Hanasu/L10n.swift`。DEC-COM-165）。`Text("…")`・`Button("…")` に日本語を直接書かない（`Text(tr("…"))`）。
- 訳は `Sources/Hanasu/Resources/Localizable.xcstrings`（String Catalog。キーは日本語の原文）。アプリは起動後に JSON のまま読む。表示の言語は `UILanguage.current`（システムの言語。DEC-COM-166）。
- 訳さないもの: 開発用の CLI（`*CLI.swift`・`main.swift`・自己テスト）の出力、ログ（`appLog`・`print`）、言語の決まりに使う日本語の語（行末に `// skip-tr` を書く。例: 会議への質問の「先週」、スニペットのフィラー）。
- 権限を求めるときの説明（`Resources/Info.plist` の `…UsageDescription`）もカタログのキーになる。`build-app.sh` が `<言語>.lproj/InfoPlist.strings` を作る。

### 文字列を足す・変える手順
1. コードに `tr("日本語の原文")` と書く（文の一部をつなぎ合わせず、文ごとに 1 つのキーにする。数や名前は `%@` で入れる）。
2. `python3 scripts/i18n-strings.py sync`（カタログのキーをコードにそろえる。原文を変えたら、古いキーは消え、新しいキーが足される）。
3. 訳を入れる: `python3 scripts/i18n-strings.py export <言語> > <作業用>/<言語>.json`（訳のないキーが値 "" で出る）→ 値を訳す → `python3 scripts/i18n-strings.py import <言語> <作業用>/<言語>.json`。16 言語（ja 以外）すべてに入れる。量が多ければ i18n エージェントに、言語を分けて並べて任せる（作業用のファイルだけを書かせ、import は親がまとめてする。カタログは 1 つのファイルなので、並べて import すると取り合う）。
4. 訳の決まり: Apple のその言語の用語（設定・アクセシビリティ・メニューバーなど）に合わせる。`%@` などの数は原文と同じ（順番を変えるなら全部 `%1$@` の形）。製品名・キーの記号（⌥ ⌘）・ファイル名は変えない。「日本語」「和訳」はどの言語でも日本語の意味のまま。「%@に統一」（整形の言語）の `%@` は言語名で、格や助詞で形が変わらない言い方にする。見本のデータ（署名・住所）はその言語の架空のものにする。
5. 確かめる（下の「確かめる」）。画面は `.build/debug/Hanasu --render-… <出力> --ui-language <言語>` で PNG にして見る。

## UI の文字列（Windows）

### 仕組みと手順（.resx。REQ-COM-060・DEC-COM-167）
- 置き場所: `windows/Hanasu.Core/Properties/Strings.resx`（エラー・進み具合・HUD・テンプレートの名前など、Core が出す文言）と `windows/Hanasu.Windows/Properties/Strings.resx`（画面・トレイ・知らせ）。どちらも**英語がニュートラル**。各言語は同じフォルダの `Strings.<カルチャ>.resx`（ja・ko・pt-BR…。中国語だけ `zh-Hans`・`zh-Hant`）。
- 足す手順:
  1. `Strings.resx` に名前（`Settings_Title`・`Error_…` のように、どこの何かが分かる名前）と英語の値、`<comment>` にどこで使うか・`{0}` が何かを書く。
  2. `Strings.ja.resx` に日本語を書く。埋める値は `{0}` `{1}`（英語と同じ組）。
  3. コードは `Strings.名前`、埋めるものは `string.Format(Strings.名前, …)`。XAML は `{x:Static p:Strings.名前}`（`xmlns:p="clr-namespace:Hanasu.Windows.Properties"`）。日本語の語順に頼って文をつなげない（「{0}して入力」ではなく、文ごとに名前を分ける）。
  4. ほかの 15 言語: `python3 scripts/i18n-resx.py export <言語>` で訳のない名前を JSON で出し、エージェントに訳を入れてもらい、`python3 scripts/i18n-resx.py import <言語> <JSON>` で書き戻す（`{0}` の組が英語と違う値は受け付けない）。
  5. `python3 scripts/i18n-resx.py check` が通ることを確かめる。
- 訳さないもの: ログ（`AppLog`）、開発用の CLI（`windows/Hanasu.Cli`）、テスト、言語の決まりとして読む語（敬称・議事録の見出しの読み取り・Whisper の幻聴の文）、AI へのプロンプト（上の JSON）。残す日本語の文字列には、行末に `// skip-tr（理由）`（XAML は前の行に `<!-- skip-tr（理由） -->`）を書く。`check-i18n.py` が、移し忘れた日本語の文字列を見つける。
- テストは表示の言語を日本語に固定している（`UiCultureFixture`）。英語などを見るときは `UiCultureFixture.With("en", …)`。

## README

README も 17 言語（`README.md` が英語、`README.ja.md` が日本語、ほかは `README.<言語>.md`）。英語と日本語を正とし、ほかの 15 言語は `README.md` から訳す。

1. `README.md`（と `README.ja.md`）を直したら、`git diff -- README.md` を見本として渡し、15 の訳の同じ場所に同じ変更を入れる。言語を 3〜5 つずつに分け、i18n エージェントに並べて任せる。
2. 変えないもの: バッジ・コード・コマンド・パス・リンク先・製品名・モデル名・`<kbd>` のキー、日本語のメニュー名（**アップデートを確認…** など。英語版と同じく、訳を括弧で添える）。
3. ライセンスなど法的な文は、意味を正確に訳す（やわらげない・足さない）。
4. 各訳の冒頭の「英語版と食い違ったら英語版が新しい」の一文と、言語の切り替え（18 行目あたり。自分の言語は太字でリンクなし）はそのまま残す。
5. `python3 scripts/check-i18n.py` が、ファイルの漏れ・切り替えのリンクの欠け・表の行や `<kbd>`・リンクなどの数の違いを見つける。数が同じでも文面の取り込み漏れはありうるので、変えた場所を訳で目で確かめる。

## 確かめる

```bash
python3 scripts/check-i18n.py --summary
```
- キーの漏れ・余分、空の値、`${…}`・タグ・JSON のキー・残す記号の食い違い、話者のラベルと「なし」のずれがあれば `error:` で終了コード 1。英語と同じままの値は `warning:`（訳し忘れでないか見る）。
- Mac の UI では、`tr("…")` とカタログのキーのずれ、訳のないキー、`%@` の数の違い、`tr()` で包んでいない日本語の文字列もエラーにする。

```bash
swift build && .build/debug/Hanasu --show-prompts --prompt-language en
```
- すべてのプロンプトを見本の入力で組み立てて表示する（AI は呼ばない）。`--prompt-language ja` の出力は、日本語の文面を変えていなければ前と同じになる。前後で `diff` を取る。

```bash
cd windows && dotnet test Hanasu.Core.Tests --filter "FullyQualifiedName~Prompt"
```

```bash
python3 scripts/i18n-resx.py check
```
- Windows の UI の文字列（.resx）で、どの言語にも全部の名前の訳があり、`{0}` などの組が英語と同じかを確かめる（漏れがあれば終了コード 1）。
- Windows が同じ JSON を読み、全言語のキーがそろっていることを確かめる。

- 実際の AI の結果を見るなら `.build/debug/Hanasu --refine-text "<その言語の文>" --prompt-language <言語>`（AI の認証が要る）。
