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

言語を足すときは、この 3 か所と `Sources/Hanasu/Resources/Prompts/<コード>.json` を足し、`PromptLanguage.from(localeIdentifier:)`（Mac・Windows）の寄せ方を見直す。

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
- `refine.outputLanguage.japanese` は、どの言語でも「日本語に統一する」の意味のまま（設定の名前が「日本語に統一」のため）。`translate.english.system` はその言語→英語、`translate.japanese.system` はその言語→日本語の指示にする。
- 議事録・要点・会議への答えを「どの言語で書くか」は、その言語にする（`minutes.intro`・`longInput.part`・`ask.system`）。

### 訳を任せる
- `.claude/agents/i18n.md` のエージェント（`subagent_type: "i18n"`）に、言語を 3 つ程度ずつ分けて並べて渡す。渡すもの: 足した・変えたキーの一覧、ja.json と en.json のその値、上の「訳の書き方」。
- エージェントは自分の言語のファイルだけを直し、`python3 scripts/check-i18n.py` を通してから返す。ほかのファイル・ビルド・コミットは任せない（並べて走らせると取り合うため）。
- 戻ってきたら、親が `--show-prompts --prompt-language <言語>` で 1 つ 2 つ目で確かめる。

## UI の文字列

Mac の UI の文字列の多言語化は FUT-012（[docs/roadmap.md](../../../docs/roadmap.md)）で進めている。入ったら、この節に Mac の手順（String Catalog）を書く。

### Windows（.resx。REQ-COM-060・DEC-COM-165）
- 置き場所: `windows/Hanasu.Core/Properties/Strings.resx`（エラー・進み具合・HUD・テンプレートの名前など、Core が出す文言）と `windows/Hanasu.Windows/Properties/Strings.resx`（画面・トレイ・知らせ）。どちらも**英語がニュートラル**。各言語は同じフォルダの `Strings.<カルチャ>.resx`（ja・ko・pt-BR…。中国語だけ `zh-Hans`・`zh-Hant`）。
- 足す手順:
  1. `Strings.resx` に名前（`Settings_Title`・`Error_…` のように、どこの何かが分かる名前）と英語の値、`<comment>` にどこで使うか・`{0}` が何かを書く。
  2. `Strings.ja.resx` に日本語を書く。埋める値は `{0}` `{1}`（英語と同じ組）。
  3. コードは `Strings.名前`、埋めるものは `string.Format(Strings.名前, …)`。XAML は `{x:Static p:Strings.名前}`（`xmlns:p="clr-namespace:Hanasu.Windows.Properties"`）。日本語の語順に頼って文をつなげない（「{0}して入力」ではなく、文ごとに名前を分ける）。
  4. ほかの 15 言語: `python3 scripts/i18n-resx.py export <言語>` で訳のない名前を JSON で出し、エージェントに訳を入れてもらい、`python3 scripts/i18n-resx.py import <言語> <JSON>` で書き戻す（`{0}` の組が英語と違う値は受け付けない）。
  5. `python3 scripts/i18n-resx.py check` が通ることを確かめる。
- 訳さないもの: ログ（`AppLog`）、開発用の CLI（`windows/Hanasu.Cli`）、テスト、言語の決まりとして読む語（敬称・議事録の見出しの読み取り・Whisper の幻聴の文）、AI へのプロンプト（上の JSON）。
- テストは表示の言語を日本語に固定している（`UiCultureFixture`）。英語などを見るときは `UiCultureFixture.With("en", …)`。

## 確かめる

```bash
python3 scripts/check-i18n.py --summary
```
- キーの漏れ・余分、空の値、`${…}`・タグ・JSON のキー・残す記号の食い違い、話者のラベルと「なし」のずれがあれば `error:` で終了コード 1。英語と同じままの値は `warning:`（訳し忘れでないか見る）。

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
