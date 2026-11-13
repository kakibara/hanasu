# 文章から文体を学び、カスタム文体として登録する

- 状態: 実装した → REQ-DIC-022・023、DEC-DIC-210〜216（[spec/dictation.md](../spec/dictation.md)）。REQ-DIC-020 を Windows に広げた。2026-11-13 に計画を了承

## 目的
2026-11-13 の依頼「テキストを投入すると、そこから文体を学ぶ機能を作成してください。学んで、それを新しい文体にカスタム登録できるようにしてください。アップロード形式は Word ファイル、テキストファイル、マークダウンファイルです。コピーでもできるようにして」。

今の文体は、組み込みのプリセット 4 つ（チャット・メール・文書（です・ます）・文書（である））と、アプリごとの追加ルール（手で書く）だけ（REQ-DIC-020、DEC-DIC-040）。自分の報告書・メールのような「自分の書き方」に寄せたいとき、ルールを自分で言葉にするのは難しい。自分の文章を渡すだけで AI が文体のルールを書き出し、名前を付けて「カスタム文体」として保存し、アプリ別のプリセットと並べて選べるようにする。

ユーザーに確かめたこと（2026-11-13）:
1. 使う場所: **アプリ別のプリセットの選択欄に並べる**（全アプリ共通の既定は作らない）
2. 保存して毎回 AI に渡すもの: **文体のルールだけ**（投入した文章も、そこからの例文も保存しない）
3. 対象: **Mac と Windows の両方**。Windows 版にはアプリ別の文体の画面がまだないので、それも作る
4. 翻訳のとき: **学んだ文章の言語と、出力の言語が同じときだけ使う**（違えば「なし」と同じ）
5. Windows のアプリ別の文体: **Mac とそろえて既定でオン**（更新で結果が変わることを知らせる）
6. 出し方: **1 つの PR で出す**（Windows の画面は実機で確かめないままマージしうる。ロジックは自動テストで確かめる）

## 要件の案

### REQ-DIC-022 文章から文体を学び、カスタム文体として登録する（新規）
- 内容: 設定の「アプリ別」の「カスタム文体」から、文章を貼り付けるか、Word（.docx）・テキスト（.txt）・Markdown（.md）のファイルを選んで読み込み、AI に文体のルールを書き出してもらう。ルール・名前・学んだ文章の言語は、保存の前に画面で読めて直せる。名前を付けて保存すると、カスタム文体として残る。あとから名前・言語・ルールを直せ、消せる。
- 受け入れ条件:
  - 「文章から学ぶ…」で開くシートで、文章を貼り付けて「文体を学ぶ」を押すと、文体のルール（1 行に 1 つ、12 個まで）・名前の案・文章の言語（17 言語のどれか）が出る。直して「保存」すると、カスタム文体の一覧に出る。アプリを再起動しても残る。
  - ルールは「どう書くか」（文末・丁寧さ・文の長さ・段落と改行・句読点と記号・語彙の硬さ）だけで、「〜を足す」「〜で始める・結ぶ」のような内容を加えるルールと、材料の固有名詞・数字・話題は入れない（DEC-DIC-210）。
  - 「ファイルを選ぶ…」で .docx・.txt・.md・.markdown を選ぶと、その本文が入力欄に入る（複数選ぶと、空行をはさんで選んだ順に足す）。.txt・.md は UTF-8（BOM の有無を問わない）・UTF-16（BOM あり。LE・BE）・Shift_JIS を読める。読めないファイル（壊れた .docx・ほかの拡張子・20 MB より大きい・展開すると大きすぎる .docx）は、ファイル名と理由を出し、入力欄は変えない。入力欄に入れるのは 100,000 字まで。超えた分は入れず、そのことを出す。
  - 文章が 100 字より短いと「文体を学ぶ」は押せず、理由を出す。送る上限（DEC-DIC-212）より長いと、先頭から上限までを使うことを、押す前に出す。
  - 投入した文章は保存しない。シートを閉じると消える。保存するのは名前・言語・ルールだけ。
  - AI が失敗した・ルールを読み取れなかった・AI の設定がない・文章の言語が 17 言語のどれでもないときは、理由を出し、入力した文章は残したままにする（もう一度押せる）。学んでいる間は「やめる」で止められ、止めても入力欄は残る。学んでいる間にシートを閉じたら、AI への要求を取り消す。
  - 名前が空・ルールが空・同じ名前（前後の空白と大文字小文字を区別しない。組み込みのプリセットの表示名も含む）は保存できず、理由を出す。ルールは 20 行・全体で 2,000 字までで、超えると保存できず理由を出す。
  - 一覧からカスタム文体を消すと、確認を出す（使っているアプリの数を出す）。消すと、使っていたアプリのプリセットは「なし」になる（そのアプリの追加ルールは残る）。
  - 「アプリ」の節の「初期設定に戻す…」では、カスタム文体は消えず、アプリへの割り当てだけが初期の表に戻る（確認の文もそう書く）。
- 出典: 2026-11-13 の依頼「テキストを投入すると、そこから文体を学ぶ機能…」（了承の日付を足す）
- 対象: Mac / Windows
- 実装の場所（予定）: Mac は `CustomStyle`・`CustomStyleStore`・`StyleLearner`・`StyleSourceReader`・`DocxText`・`StyleLearningSheet`・`CustomStylesSection`。Windows は `Hanasu.Core.Dictation` の `CustomStyle`・`StyleLearner`・`StyleSourceReader`・`DocxText`、`Hanasu.Windows.Views.StyleLearningWindow`、設定の「アプリ別」タブ
- 確かめ方: `.build/debug/Hanasu --test-custom-styles`、`.build/debug/Hanasu --learn-style --from-file <ファイル>`（実際の AI）、`--render-style-learning <出力フォルダ>`、`cd windows && dotnet test Hanasu.Core.Tests`（`CustomStyleTests`）

### REQ-DIC-023 カスタム文体をアプリに割り当てて、音声入力の文体に使う（新規）
- 内容: アプリ別の設定のプリセットの選択欄に、組み込みのプリセットのあとにカスタム文体を並べ、アプリに割り当てられる。割り当てたアプリで、出力の言語がカスタム文体の言語と同じときは、そのルールを、プリセットのルールと同じ位置・同じ優先順位（DEC-DIC-043）で AI に渡す。違うときは「なし」と同じに扱う。
- 受け入れ条件:
  - 特徴のはっきりした固定の材料（`common/testdata/style/plain-comma.txt`: である調・読点に「，」）から学んだカスタム文体を割り当て、決まった発話（です・ます調で「、」を使い、挨拶のない短い文）を実際の AI で `--refine-text` に通すと、出力の文末が である調 になり、読点が「，」になる。話していない挨拶・宛名・署名・定型句は増えない。割り当てがないときの出力とは違う。
  - `--show-prompt` で見ると、文体の節にカスタム文体のルールが「- 」で並び、組み込みのプリセットのルールは入らない。カスタム文体の名前は送らない。内容を足さない歯止めの行（`style.learnedGuard`）が入る。
  - 出力の言語（翻訳なら訳す先、整形なら文字起こしの言語。整形の言語の統一（REQ-DIC-082）がオンならその先）がカスタム文体の言語と違うときは、文体の節にカスタム文体のルールが入らない（アプリ別の追加ルールは今までどおり入る）。
  - カスタム文体のルールを直すと、次の音声入力から直したルールが使われる。
  - 割り当てたカスタム文体が見つからない（消した・ほかの版で保存した設定）ときは「なし」として扱い、エラーにしない。
  - `hanasu refine --app <アプリ> --style <プリセット>` は、そのアプリにカスタム文体を割り当てていても、`--style` のプリセットを使う（REQ-DIC-160 の「--style が --app より優先」を保つ）。画面で組み込みのプリセットに選び直したときも、カスタム文体の割り当ては外れる。
- 出典: 同上
- 対象: Mac / Windows
- 実装の場所（予定）: Mac は `AppStyle.customStyleID`・`AppStyle.hasRules`・`AppStyle.promptSection`・`AppStyleRow`・`HanasuAICommands.runRefine`。Windows は `AppStyle`（Core）の `HasRules`・`PromptSection`、`AppStyleSetting`、`DictationTextProcessor.ProcessAsync`、`AiCommands`
- 確かめ方: `--test-custom-styles`（節の組み立て・言語の一致・`--style` の優先）、`HANASU_TEST_DEFAULTS_SUITE=<suite> .build/debug/Hanasu --refine-text "<発話>" --app <bundle ID> [--show-prompt]`、`--test-hanasu-command` と Windows の `CommandGoldenTests`（`common/testdata/cli/cases.json` にカスタム文体の例を足す）、`dotnet test`

### 変える要件（ユーザーの合意が要る）
- **REQ-DIC-020 入力先アプリに合わせて文体を変える**: 対象「Mac」→「Mac / Windows」。Windows 版の音声入力でも、前面のアプリ（exe の名前）ごとにプリセット（カスタム文体を含む）と追加ルールを決められ、設定の新しいタブ「アプリ別」で編集できる。**既定でオン**（Mac と同じ。更新すると Slack・Teams はチャット、Outlook はメール、Word は です・ます調 に整形が変わる。windows/README とリリース文で知らせる）。Windows の受け入れ条件を足す: 「slack.exe が前面のときに音声入力すると、チャットの文体ルールが AI に渡る」。
  - **REQ-DIC-021（アプリごとの既定の出力言語）は Windows には作らない**（対象は Mac のまま。FUT-003 に残す）。
- **REQ-DIC-160（`hanasu refine`）**: Windows の `--app <exe>` は、アプリの設定の「アプリ別」を先に引き（オンのとき）、なければ既定の一覧を使う。Windows の `hanasu refine --app` の結果が、ユーザーの設定で変わるようになる（Mac は今もそう）。
- **DEC-COM-107（Windows にない機能の一覧）**: 「アプリ別の文体」を外し、「アプリごとの既定の出力言語」に書き換える。
- **DEC-DIC-190**: 「Windows のアプリにアプリ別の文体の設定はない」を直し、上の REQ-DIC-160 の引き方を書く。
- **DEC-DIC-040・041・042・044・046**: 対象を「Mac / Windows」にする（Windows の音声入力でも使うようになる）。DEC-DIC-043 は「プリセット（カスタム文体を含む）」に、DEC-DIC-047 は Windows の置き場所（DEC-DIC-213）を足す。

## 設計判断の案

番号は DEC-DIC-210 から（200 と 201 は開いている PR #110 が使っている）。

### DEC-DIC-210 文体を学ぶ AI と、学ばせ方
- 決めたこと: 学ぶ処理は、設定の AI の「議事録」の AI とモデル（Mac は `TextAIPurpose.meeting`、Windows は `MeetingAi`・`MinutesModel`）に送り、120 秒まで待つ。設定の AI の「議事録」の説明に「文体を学ぶ」を足す。指示は新しいプロンプト `styleLearn.system`・`styleLearn.user`（17 言語）で、`{"name": "…", "language": "<言語のコード>", "rules": ["…"]}` の JSON で返させる。ルールは設定の文字起こしの言語（プロンプトの言語）で書かせる。見るのは「どう書くか」だけ（文末・敬語と丁寧さ・文の長さ・段落と改行・句読点と記号・語彙の硬さ・よく使う言い回しの型）。次は禁じる: 内容を加えるルール（「〜を足す」「〜で始める」「〜で結ぶ」「挨拶・署名を入れる」）、材料の固有名詞・数字・事実・話題。ルールには、材料から引かない一般的な言い換えの例（「〜なんですけど → 〜だが」）を添えさせる。材料は `PromptText.neutralizeDelimiters` で区切りのタグを無害にして `<material>` で囲み、材料の中の指示には従わせない。応答は最初の `{` から最後の `}` までを読み（`DictionarySuggester.parse` と同じ）、ルールは空行を除いて先頭の 12 個まで。`language` が 17 言語のコードでなければ失敗にする。
- 理由: 長い文章を読む分析なので、辞書の候補（DEC-DIC-088・170。同じく「議事録」の AI）にそろえる。音声入力整形の AI は短く速い処理向けで 15 秒で切れる。内容を加えるルールは、プリセットが持つ歯止め（「話していない宛名・挨拶・署名は足さない」）を越えて DEC-DIC-006 を破る。言い換えの例がないとルールが効かない（DEC-DIC-043 の理由）。ルールを読める言語で書かせると、保存の前に直せる。
- 関係する要件: REQ-DIC-022
- 対象: Mac / Windows

### DEC-DIC-211 取り込むファイルの読み方は、Mac と Windows で同じ規則にする
- 決めたこと: .docx は zip を開いて `word/document.xml` を読み、段落（`w:p`）を改行、`w:t` を文字、`w:tab` をタブ、`w:br`・`w:cr` を改行にする。表のセルは段落として読む。箇条書きと番号（`numbering.xml` が描くもの）・画像・脚注・コメント・ヘッダーとフッターは読まない。Mac は小さな zip の読み手（中央ディレクトリを読み、raw deflate を Apple の `Compression` で展開）を `DocxText` に書き、Windows は `System.IO.Compression.ZipArchive`。どちらも `document.xml` の展開後の大きさが 50 MB を超えたら読まず、XML の DTD は読まない（Windows は `DtdProcessing.Prohibit`）。.txt・.md は、BOM で UTF-8・UTF-16（LE・BE）を見分け、BOM がなければ UTF-8 で読み、UTF-8 として正しくなければ Shift_JIS（CP932）で読む。Windows は `StyleSourceReader` の中で `CodePagesEncodingProvider.Instance.GetEncoding(932)` を直接使う（アプリの起動で登録していないため）。.md の記号は外さない。20 MB より大きいファイルは読まない。読める拡張子は .docx・.txt・.md・.markdown。ファイルの本文は入力欄に入れ、貼り付けと同じに扱う。
- 理由: Mac の `NSAttributedString` と自前の読み方では番号・表・改行の文字が変わり、同じファイルから学んだ文体が OS で変わる。追加のライブラリなしで、両方で同じ規則にできる。番号の文字は本文にないので、両方とも読まない（.md の箇条書きの記号は本文にあるので残す）。展開の大きさを見ないと、小さな .docx で固まる。日本語の古いテキストは Shift_JIS が多い。本文を入力欄に入れると、送る前に要らない部分（署名・引用）を消せる。
- 関係する要件: REQ-DIC-022
- 対象: Mac / Windows

### DEC-DIC-212 送る文章の長さの下限と上限
- 決めたこと: 字数は Unicode のスカラー値で数える（Swift は `unicodeScalars.count`、C# は `EnumerateRunes().Count()`）。前後の空白を除いて 100 字未満なら学ばない。上限は、Gemini・Claude は 30,000 字。ローカル・Apple は `DictionarySuggester.budget(for:)` と同じ出し方（文脈の長さから出力・system・枠・余白を引いたトークン数）で、`LongInputFitter` に切られる・要約されることがない量だけを送る。超えた分は送らず、先頭から上限までを使い、シートに使う字数を出す。入力欄に入れるのは 100,000 字まで。
- 理由: 短すぎると特徴が読み取れない。文体は数千字あれば読み取れ、長く送るほど時間と費用がかかる。端末の中のモデルは文脈の長さがモデルで違い（8,192〜32,768）、字数で決め打ちすると、あふれた分が黙って省かれ、返し方の指示まで切れる（DEC-DIC-170 と同じ理由）。数え方を決めないと、Mac と Windows で境目の合否が分かれる。大きすぎる本文を入力欄に入れると画面が固まる。
- 関係する要件: REQ-DIC-022
- 対象: Mac / Windows

### DEC-DIC-213 カスタム文体の持ち方と、アプリへの割り当て方
- 決めたこと: カスタム文体は ID（UUID）・名前・言語（17 言語のコード）・ルール（1 行に 1 つの文字列）だけを持つ。投入した文章は保存しない。Mac は UserDefaults の `customAppStyles`（JSON の配列）に `CustomStyleStore` で置き、`AppStyle` に `customStyleID`（任意）を足す。カスタム文体を選んだアプリの `preset` は `none` で保存する。`hasRules` はカスタム文体があれば true にする。組み込みのプリセットを選んだら（画面でも `hanasu refine --style` でも）`customStyleID` を消す。Windows は `settings.json` の `CustomStyles`、アプリ別の設定は `AppStylesEnabled`（既定 true）・`AppStyles`（exe の名前・アプリ名・プリセット・カスタム文体の ID・追加ルール。未設定なら既定の一覧 DEC-DIC-190）に置く。名前は前後の空白を取り、大文字小文字を区別せず、カスタム文体どうしと組み込みのプリセットの表示名（今の表示の言語）との重複を禁止する。ルールは 20 行・2,000 字まで。「初期設定に戻す」はアプリの割り当てだけを戻し、カスタム文体は消さない。
- 理由: ユーザーとの確認で「ルールだけ」に決めた。ID で持つので名前を直しても割り当ては外れない。`preset` を `none` にしておくと、前の版に戻しても知らないキーを無視して「なし」として読める。ルールの長さに上限がないと、毎回の音声入力が長くなり、端末の中の AI では話した内容が要約される。投入した文章は残らないので、初期設定に戻すだけで学んだ文体が消えると作り直せない。
- 関係する要件: REQ-DIC-022, REQ-DIC-023
- 対象: Mac / Windows

### DEC-DIC-214 カスタム文体のルールは、出力の言語が同じときだけ、プリセットのルールの代わりに渡す
- 決めたこと: `AppStyle.promptSection`（Mac）・`AppStyle.PromptSection`（Windows）で、カスタム文体を選んだアプリでは、出力の言語がカスタム文体の言語と同じときだけ、プリセットのルールの位置にカスタム文体のルールを「- 」で並べ、そのあとに歯止めの行 `style.learnedGuard`（新しいキー。17 言語。「話していない挨拶・宛名・署名・定型句は足さない。箇条書きや段落への組み替えは、話した内容がそうなっているときだけ」）を足す。出力の言語は、翻訳なら訳す先、整形なら文字起こしの言語（整形の言語の統一がオンならその先）。違うときはカスタム文体を「なし」と同じに扱う（アプリ別の追加ルールは今までどおり渡す）。見出し・アプリ別の追加ルール・優先順位の行（DEC-DIC-043）はプリセットと同じ。カスタム文体の名前は送らない。翻訳の読み替えの注記は使わない。
- 理由: ユーザーとの確認で「学んだ言語と同じときだけ使う」に決めた。学んだルールには表記（句読点・全角半角）も入るので、ほかの言語の出力には合わない。組み込みのプリセットが持つ歯止めがカスタム文体にはないので、固定の行で補う。組み立てをプリセットと同じにすると、Mac と Windows で同じプロンプトにでき、golden で比べられる。
- 関係する要件: REQ-DIC-023
- 対象: Mac / Windows

### DEC-DIC-215 画面の置き場所
- 決めたこと: 設定の「アプリ別」タブ（Mac は今の `AppStylesTab`、Windows は新しいタブ）の「プリセット」の説明の下に「カスタム文体」の節を置き、一覧（名前・言語・ルールの数）と「文章から学ぶ…」「編集…」「削除…」を並べる。「文章から学ぶ…」はシート（Windows はモーダルのウインドウ）で、上から: 入力欄（貼り付け）と「ファイルを選ぶ…」・字数と使う字数の表示、「文体を学ぶ」（学んでいる間は進み具合と「やめる」）、名前・言語・ルールの欄（学んだあとに出す。手で直せる）、「保存」「キャンセル」。「編集…」は同じシートの名前・言語・ルールの欄だけを出す。プリセットの選択欄は、組み込みのプリセットのあとに区切りを入れてカスタム文体を名前の順に並べる。ファイルのドラッグ＆ドロップは作らない。
- 理由: 割り当てる場所と同じタブに置くと、作ってすぐ割り当てられる。学ぶ前に文章を見られ、学んだあとに直せる流れを 1 つのシートにまとめる。
- 関係する要件: REQ-DIC-022, REQ-DIC-023
- 対象: Mac / Windows

### DEC-DIC-216 Windows 版のアプリ別の文体は、exe の名前で引き、出力言語は持たない
- 決めたこと: 録音を始めたときの前面のウインドウ（Hanasu かタスクバーなら最後に前面だったウインドウ。`ForegroundWindowTracker.ForegroundAppName` と同じ選び方）の exe の名前（小文字）で `AppStyles` を引く。`ApplicationFrameHost.exe`（ストアアプリ）は引かない。引く処理（exe の名前 → `AppStyle`。スイッチ・知らない ID・ストアアプリの扱い）は `Hanasu.Core` の純粋な関数にし、`DictationController` には exe の名前を返す関数（`ForegroundAppExe`）を `ForegroundAppName` と同じ形で渡す。`DictationTextProcessor.ProcessAsync` で `RefineRequest.AppStyle` に入れる。設定のタブでは、実行中のアプリ（メインウインドウのあるプロセス）から足すか、「exe を選ぶ…」で足す。行ごとにプリセット（カスタム文体を含む）・追加ルール・一覧から外す、と全体のオンオフ・「初期設定に戻す…」を置く。アプリごとの既定の出力言語（REQ-DIC-021）は作らない。
- 理由: Windows の既定の一覧（DEC-DIC-190）と `hanasu refine --app` が exe の名前で引くのにそろえる。ストアアプリはどれも同じ exe なので見分けられない。Windows の画面はこの Mac で動かせないので、引く処理を Core に置いて `dotnet test` で確かめる。出力言語は HUD の切り替え（REQ-DIC-011）にも手が要り、今回の依頼の外。
- 関係する要件: REQ-DIC-020
- 対象: Windows

## やらないこと
- 全アプリ共通の既定の文体。ユーザーとの確認で作らないと決めた。
- 例文（投入した文章の一部）を保存して毎回渡すこと。同上。
- 翻訳のときに、ほかの言語から学んだカスタム文体を読み替えて使うこと。同上（言語が同じときだけ使う）。
- .doc（古い Word）・.rtf・.pdf・Pages の読み込み、ファイルのドラッグ＆ドロップ、URL からの読み込み、`hanasu refine --style` でカスタム文体を名前で選ぶこと → FUT-111 として roadmap に足す。
- Windows のアプリごとの既定の出力言語（REQ-DIC-021）→ FUT-003 に残す。
- 学び直し（同じカスタム文体に文章を足して学び直す）。新しく学んで保存し、古いものを消せばよい。
- 材料にしか出てこない語がルールに入っていないかを、アプリの側で機械的に調べること。ルールは「〜と思います」のような材料にある言い回しを正しく引くことがあり、機械的に外すと誤る。指示（DEC-DIC-210）と、保存の前にユーザーが読むことで防ぐ。

## 手順
0. 始める前に `git fetch origin` し、PR #110 がマージされていれば rebase する。まだなら、#110 が触る `AppStyle.promptSection`（`japaneseOutput` の引数）・Windows の `AppSettings.cs`・`GeminiPrompts.cs`・`SettingsWindow.xaml(.cs)`・`Prompts/*.json` で、あとから合わせる前提で書く（出力の言語の決め方は、#110 の前は「日本語に統一」、後は「文字起こしの言語に統一」）。
1. spec: `docs/spec/dictation.md` に REQ-DIC-022・023、DEC-DIC-210〜216 を書き、「変える要件」の項目を直す。`docs/spec/common.md` の DEC-COM-107 を直す。`docs/roadmap.md` に FUT-111 を足し、FUT-003 の中身から「アプリ別の文体」を外して「アプリごとの既定の出力言語」にする。
2. 共有:
   - `Sources/Hanasu/Resources/Prompts/<言語>.json` に `styleLearn.system`・`styleLearn.user`・`style.learnedGuard` を 17 言語で足す（i18n スキル。i18n エージェントに言語を分けて任せる）。
   - `common/testdata/style/`: 特徴のはっきりした材料 `plain-comma.txt`（である調・読点「，」）、UTF-8・BOM 付き UTF-8・UTF-16 LE・UTF-16 BE・Shift_JIS の .txt、.md、.docx（表・番号付きの段落・`w:tab`・`w:br` を含む）、壊れた .docx、扱わない拡張子のファイルと、それぞれの期待する本文（Mac と Windows で同じ 1 つ）。20 MB を超えるファイルと展開すると大きい .docx はテストの中で作る。
   - `common/testdata/cli/`: `settings.json` にカスタム文体と割り当てを足し、`cases.json` に `refine --app <アプリ> --show-prompt` の例（言語が同じ・違う、`--style chat` を足した例）を足す。
3. Mac（手順 4 と独立）:
   - `AppStyles.swift`: `CustomStyle`・`CustomStyleStore`、`AppStyle.customStyleID`・`hasRules`・`promptSection`（DEC-DIC-214）、`AppStyleStore.resetToDefaults` はそのまま（カスタム文体は別のストア）。
   - 新しい `StyleLearning.swift`: `DocxText`・`StyleSourceReader`（DEC-DIC-211）、`StyleLearner`（DEC-DIC-210・212。`TextAIClient.requireFromSettings(_, for: .meeting)`、上限は `DictionarySuggester.budget` と同じ出し方）。
   - `AppStylesView.swift`: `AppStyleRow` の選択欄（組み込みを選んだら ID を消す）、`CustomStylesSection`、初期設定に戻すの確認の文。新しい `StyleLearningSheet.swift`（`Task` を持ち、閉じたら取り消す）。
   - `HanasuAICommands.swift` の `runRefine`: `--style` で `customStyleID` を消す。
   - `TextAI.swift`: `TextAIPurpose.meeting.detail` に「文体を学ぶ」。
   - `PromptsCLI.swift`（`--show-prompts`）: カスタム文体の節と `styleLearn.*` を出す。
   - CLI: `--test-custom-styles`・`--learn-style --from-file <ファイル>`・`--render-style-learning <出力フォルダ>` を `main.swift` と新しい `StyleLearningCLI.swift` に。設定は `HANASU_TEST_DEFAULTS_SUITE` の suite に書いてから動かす。`// 確かめ方: REQ-DIC-022` などを付ける。
   - UI の文字列は `tr()` で書き、`python3 scripts/i18n-strings.py sync` のあと 17 言語の訳を入れる。
4. Windows（手順 3 と独立）:
   - `Hanasu.Core/Dictation/AppStyle.cs`: `CustomStyle`、`AppStyle` にカスタム文体を渡せるようにし、`HasRules`・`PromptSection` を DEC-DIC-214 に合わせる。exe の名前から `AppStyle` を引く関数（DEC-DIC-216）。
   - 新しい `Hanasu.Core/Dictation/StyleLearning.cs`: `DocxText`・`StyleSourceReader`・`StyleLearner`（上限は `LongInputFitter` と `LocalLlmModel.ContextLength` から）。
   - `Hanasu.Core/Settings/AppSettings.cs`: `AppStylesEnabled`・`AppStyles`・`CustomStyles`。
   - `Hanasu.Core/Dictation/DictationController.cs`・`DictationText.cs`: `ForegroundAppExe` を受け取り、`RefineRequest.AppStyle` に入れる。`Hanasu.Windows/Services/ForegroundWindowTracker.cs` に exe の名前を返す関数を足し、`AppHost.cs` でつなぐ。
   - `Hanasu.Core/Command/AiCommands.cs`・`SharedText.cs`: `--app` は設定のアプリ別を先に引く。`--style` でカスタム文体の ID を消す。
   - `Hanasu.Windows/Views/SettingsWindow.xaml(.cs)`: 「アプリ別」タブ。新しい `StyleLearningWindow.cs`（コードで組む WPF。`CancellationTokenSource` を持ち、閉じたら取り消す）。
   - 文字列は Core と Windows の `Properties/Strings.resx` と 16 の訳。
   - テスト: `CustomStyleTests.cs`（読み込みは共有の固定のファイル、Shift_JIS はプロバイダーを登録していない状態でも読めること、応答の読み取り、長さの上限と数え方、プロンプトの節、名前の重複、ルールの上限、消したときの扱い、設定の読み書き）。`DictationControllerTests.cs`（`FakeRefiner` で、slack.exe ならチャットのルール・カスタム文体ならそのルール・スイッチがオフなら届かない・知らない ID なら「なし」・ApplicationFrameHost.exe は引かない）。`CommandGoldenTests`（手順 2 の例）。
5. 文書: `docs/design/dictation.md`（カスタム文体と学ぶ流れ）、`docs/design/security.md`・`security-windows.md`（投入した文章を「議事録」の AI に送り保存しないこと。学んだルールは保存して毎回送り、優先順位が高いので、他人の文書の中の指示がルールに紛れ込むおそれがあり、保存の前にユーザーが読むこと）、`docs/guide.md`、`windows/README.md`（使い方・「Mac 版との差」・更新でアプリ別の文体がオンになること）、`README.md` の「アプリ別の文体」の行に一文足し、16 の訳（`README.<言語>.md`）にも同じ変更。リリース文（次のリリースのとき）に Windows の振る舞いが変わることを書くよう、PR の本文に残す。
6. UI のテストの項目: `common/testdata/ui/settings.json` に、学ぶシート（Mac は render、Windows は manual）・カスタム文体の節・プリセットの選択欄・Windows の「アプリ別」タブの項目を足し、`python3 scripts/ui-cases.py md`・`check`。
7. 確かめる（下）。

手順 3 と 4 は触るファイルが重ならず、どちらも手順 1・2 のあとに進められる。

## 確かめ方
- `swift build`
- `.build/debug/Hanasu --test-custom-styles`: 保存・名前の重複（組み込みの名前を含む）の拒否・ルールの上限・編集・削除で割り当てが「なし」・初期設定に戻してもカスタム文体が残る・知らない ID は「なし」・`hasRules`・プロンプトの節（整形・英訳・ほかの言語への翻訳・言語が同じ／違う・アプリ名を送らない設定・歯止めの行）・`--style` で ID が消える・固定のファイルの読み込み（期待する本文と一致、壊れたもの・大きすぎるものは理由つきで失敗）・応答の読み取り（コードブロック・13 個以上・空・知らない言語）・長さの下限と上限（Gemini・Claude・8K のローカル・Apple）
- 実際の AI（Gemini か Claude）: `--learn-style --from-file common/testdata/style/plain-comma.txt` で学び、suite に保存して `--refine-text "<決まった発話>" --app <bundle ID>` を割り当てあり・なしで比べる（である調・「，」になる、挨拶が増えない）。.docx の材料でも学べること
- `--render-style-learning <出力フォルダ>`・`--render-app-styles <png>` を ui-test スキルで見る
- `cd windows && dotnet test Hanasu.Core.Tests`
- `--test-hanasu-command`（Mac の golden）
- `python3 scripts/check-spec.py`・`python3 scripts/check-i18n.py`・`python3 scripts/ui-cases.py check`
- 実機（Mac）: Word の .docx を読み込んで学び、Word に割り当て、話した結果がその文体になること
- 実機（Windows）: **この Mac では確かめられない**。ユーザーとの確認で、1 つの PR で出す（Windows の画面・前面の exe での切り替えの実機の確かめは、マージの前の必須にしない）。ロジックは `dotnet test` で、ビルドは CI で確かめる。確かめていないことは PR の本文と終わったときの報告に書き、UI のテストの項目（manual）に残す

## 敵対的レビュー
2026-11-13、requirements-reviewer を 2 つ（A: 目的・受け入れ条件・失敗時・範囲・仮に決めたこと、B: 既存の要件・Mac と Windows・17 言語・データと安全・手順の事実・確かめ方）並べて走らせた。

| 指摘 | 重さ | 仕分け | どうしたか |
| --- | --- | --- | --- |
| 学んだルールが「挨拶を足す」などの内容を加える指示になり、DEC-DIC-006 を破る（A1） | 重大 | 直す | 学ばせるルールを「どう書くか」に限り、内容を加えるルールを禁じた（DEC-DIC-210）。固定の歯止めの行 `style.learnedGuard` を足した（DEC-DIC-214）。受け入れ条件に「挨拶が増えない」 |
| 受け入れ条件がプロンプトの形しか見ず、出力が本当に変わるかを確かめない（A2・B4） | 重大 | 直す | 特徴のはっきりした材料と決まった発話で、実際の AI の出力を比べる受け入れ条件と確かめ方を足した。ルールに一般的な言い換えの例を添えさせる（DEC-DIC-043 の理由） |
| ローカル・Apple の上限を 4,000 字で決め打ちすると、8K のモデルであふれて黙って切られる（A3・B） | 重大 | 直す | `DictionarySuggester.budget` と同じトークンでの出し方にした（DEC-DIC-212） |
| `customStyleID` が残ると `hanasu refine --style` が効かない（A4） | 重大 | 直す | 組み込みのプリセットを選んだら ID を消す（DEC-DIC-213）。受け入れ条件・手順・テストに足した |
| Windows で既定でオンにすると、更新で結果が変わる（A5・B） | 重大 | 聞いた | 「Mac とそろえて既定でオン」。windows/README とリリース文で知らせる手順を足した |
| Windows の画面と exe での切り替えを誰も動かさずにマージする（A6・B5） | 重大 | 聞いた・直す | 「1 つの PR で出す」。引く処理を Core の純粋な関数にし、`DictationControllerTests` で確かめる手順を足した（DEC-DIC-216） |
| 設計判断の 200・201 は PR #110 が使っている（B1） | 重大 | 直す | DEC-DIC-210〜216 に移した。手順 0 に #110 との合わせ方を書いた |
| Windows のアプリで Shift_JIS が読めない。テストはほかのテストの登録で通ってしまう（B2） | 重大 | 直す | `StyleSourceReader` で CP932 を直接取り、登録していない状態のテストを足した（DEC-DIC-211） |
| 学んだルールを翻訳で使うと、表記のルールが別の言語に当たる（A10・B3） | 重大 | 聞いた | 「学んだ言語と同じときだけ使う」。言語をカスタム文体に持たせた（DEC-DIC-213・214） |
| .docx の読み方が Mac と Windows で違い、学ぶ結果が OS で変わる（B6） | 重大 | 直す | 両方とも zip と XML で同じ規則にした（DEC-DIC-211）。固定のファイルを足した |
| 大きなファイルを入力欄に入れると固まる・展開すると大きい .docx（A7・B） | 軽微 | 直す | 入力欄は 100,000 字まで、展開後 50 MB まで、DTD を読まない |
| 「やめる」・閉じる・「初期設定に戻す」の扱いがない（A8） | 軽微 | 直す | 受け入れ条件に書いた。初期設定に戻してもカスタム文体は残す |
| 手で直したルールの長さに上限がない（A9・B） | 軽微 | 直す | 20 行・2,000 字まで |
| 組み込みのプリセットと同じ名前・字数の数え方の違い（A11） | 軽微 | 直す | 組み込みの表示名との重複も拒む。Unicode のスカラー値で数える |
| 材料の固有名詞がルールに入らないことを、アプリの側でも調べる（A11） | 軽微 | 退ける | 材料にある言い回しを正しく引くルールまで外してしまう。指示と保存前の確認で防ぐ（やらないことに書いた） |
| `hasRules` が false で節ごと落ちる（B） | 軽微 | 直す | `hasRules`／`HasRules` をカスタム文体で true にする |
| DEC-DIC-040〜046 の対象・REQ-DIC-160 の Windows の振る舞いの直しが足りない（B） | 軽微 | 直す | 「変える要件」に足した。golden の例を足した |
| `-customAppStyles '<JSON>'` は UserDefaults の data で読めない（B） | 軽微 | 直す | `HANASU_TEST_DEFAULTS_SUITE` に書いてから動かす |
| `--show-prompts` に新しいプロンプトが出ない（B） | 軽微 | 直す | `PromptsCLI` に足す |
| security.md に、学んだルールに他人の文書の指示が紛れ込む危険を書く（B） | 軽微 | 直す | 手順 5 に書いた |

## 仮に決めたこと
- 学ぶ AI は「議事録」の AI（DEC-DIC-210）。
- 下限 100 字・上限 30,000 字（ローカル・Apple はモデルの文脈から）・AI が返すルールは 12 個まで・保存できるルールは 20 行・2,000 字まで（DEC-DIC-210・212・213）。
- カスタム文体を消したアプリは「なし」に戻す（そのアプリの初期の文体には戻さない）。
- 学び直しは作らない。.doc・.pdf・ドラッグ＆ドロップは作らない（FUT-111）。
- Word の箇条書きの番号・記号は読まない（DEC-DIC-211）。
- README（17 言語）にも一文足す。
