# 画面から辞書の候補を探す

- 状態: 実装した（2026-11-13）→ REQ-DIC-075、DEC-DIC-230〜237（[spec/dictation.md](../spec/dictation.md)）。確かめた結果は [verification/dictation.md](../verification/dictation.md) の 21

## 目的
2026-11-13 の依頼「全画面を取り込んで辞書を登録するという機能を追加してください」。

画面に出ている固有名詞・型番・社内用語（資料・チャット・Web の画面）を、話す前に辞書へ入れておきたい。今の辞書の候補（REQ-DIC-071・072）は、過去の音声入力の結果と会議の記録からしか探せず、まだ話していない語は候補にならない。すべての画面を撮って文字を読み、AI に送るものを見せて確かめてから、辞書の候補（表記と、話すとどう認識されやすいかの読み）を挙げてもらい、選んだものだけを辞書に足せるようにする。

同日のユーザーの回答で決めたこと:
- 1 回目: 入口はメニューバー（Windows はタスクトレイ）のメニューの項目だけ。候補には AI が推測した読みも付ける。REQ-MTG-030 を変えて、この機能からも画面収録の許可を求める。対象は Mac と Windows の両方。
- 2 回目（敵対的レビューから）: 読んだものを見せてから、ボタンを押したときだけ AI に送る。Windows にも既定の除外（パスワード管理アプリ・通知・認証のダイアログ）を作る。Mac の除外アプリの欄をいつでも編集できるようにする（REQ-DIC-042 を変える）。

## 要件の案

### REQ-DIC-075 画面に出ている文字から辞書の候補を挙げてもらい、選んだものだけを足す（新規）
- 内容: メニューの「画面から辞書の候補を探す…」を選ぶと、その時点のすべての画面を撮って文字を読む（OCR。画像はどこにも送らず、ファイルにも残さない）。AI に送る材料（語の一覧と画面の行）を候補の画面に見せ、ユーザーが「候補を探す」を押したときだけ、その材料を会議の AI（辞書の候補探しと同じ。DEC-COM-040）に送り、辞書の候補を挙げてもらう。候補には、画面にある表記と、AI が推測した「話すとこう認識されやすい」読みを付ける。ユーザーが選んだ候補と読みだけを辞書の末尾に足す。
- 受け入れ条件:
  1. **入口**: Mac はメニューバーのメニュー（「Dock だけ」のときは Dock のメニューにも）、Windows はタスクトレイのメニューに「画面から辞書の候補を探す…」がある。音声入力の準備中・録音中・処理中と、選択を声で編集しているあいだは選べない（灰色）。選べてしまった場合も、何もしない。
  2. **撮る**: 選ぶと、メニューが閉じてから、つないでいるすべての画面を 1 回撮る。撮り終えてから候補の画面を開く（全画面表示のアプリの上で選んでも、そのアプリの画面が撮られる）。撮り直しはしない（もう一度撮るには、画面を閉じてメニューから選び直す）。
  3. **送る前に見せる**: 候補の画面に「画面の文字を読んでいます…」を出し、読み終えたら、**実際に送る材料**（「語」と「画面の行」の 2 つの欄。スクロールできる）、「N 画面から読み、語 M 個・行 L 行を送ります。」、送り先の AI の名前、「候補を探す」ボタンを出す。材料が AI の上限に入りきらず一部を外したときは、ここで「画面の文字が多いので、一部だけを送ります。」と出す（見せた範囲と送る範囲は同じ）。**「候補を探す」を押すまで、何も AI に送らない。**「キャンセル」で閉じると、OCR も AI の呼び出しも止め、辞書を変えない。
  4. **探す**: 「候補を探す」を押すと「探しています…」を出す。
  5. **候補と追加**: 候補は表記と理由と、読みごとのチェックで並ぶ。既定ではどれもチェックしない。候補をチェックすると、その読みもすべてチェックされ、要らない読みは外せる。「選んだ N 件を辞書に追加」で、チェックした候補が、チェックした読みだけを付けて、辞書の末尾に `読み => 表記`（読みが残らなければ語だけ）の行として入る。追加すると画面を閉じ、「N 件を辞書に追加しました。」と知らせる。候補が 0 件なら「新しい候補は見つかりませんでした。」。
  6. **絞り込み**: 表記は、読みの有無によらず、画面から読んだ材料に出てくるものだけ（AI が作った語は除く）。読みは画面にないので AI の推測を使ってよいが、表記と同じ読み・1 文字の読み・長すぎる読み・既存の辞書や他の候補で使っている読み・区切り文字や矢印を含む読みは除き、1 つの候補の読みは 4 つまで（DEC-DIC-231）。辞書にすでにある表記は、新しい読みがあるときだけ残す。
  7. **効くこと**: 画面に「J3」が出ているとき、Gemini・Claude で探すと「J3」の候補に、音声認識が出しやすい形の読み（「Jスリー」を含む）が付く。その候補を足した辞書で `--apply-dictionary "Jスリーの件ですが"` が「J3の件ですが」になる。ローカル（Gemma 4 E4B。Mac の既定）・Apple の fm と、文字起こしの言語が英語のときは、試して結果を verification に残す（満たさなくても不合格にはしない。「仮に決めたこと」を参照）。
  8. **写さないもの**: Hanasu 自身のウインドウ（候補の画面・設定・HUD など）は写らない。Mac は、除外アプリ（REQ-DIC-040 と共有）とシステムの秘密が出る部分（DEC-DIC-182）も写らない。Windows は、既定の除外（パスワード管理アプリ・通知のトースト・認証のダイアログ。DEC-DIC-235）を読む前に塗りつぶす。候補の画面の説明に、写さないものと、写るもの（ブラウザの中のパスワード管理の拡張・ほかの画面のターミナルなど）を書く。
  9. **許可（Mac）**: 画面収録の許可がないとき、会議の記録中・議事録の作り直し中でなければ macOS の許可のダイアログを出し、候補の画面に「画面収録を許可したら、Hanasu を終了して開き直し、もう一度選んでください。」と「システム設定を開く」を出す。会議の記録中・作り直し中は求めず、「会議の記録が終わってから許可してください」と出す。どちらも撮らず、AI に何も送らない。
  10. **うまくいかないとき**: 撮れなかった・文字を読めなかった（真っ黒・文字がない）ときは、理由を出し、送らない。Windows で文字起こしの言語の OCR が入っていないときは、入っている言語（なければ英語）で読み、「<言語> の文字を読む機能が Windows に入っていないため、<読んだ言語> で読みました。」と追加のしかたを出す。どの言語でも読めないときは理由を出し、送らない。会議の AI が使えない（鍵がない・ローカルのモデルがない）、ネットにつながらない、時間切れ、応答が読めないときは、理由を出し、辞書を変えない。ローカルのモデルがないときは、ダウンロードを尋ねず「設定の『AI』でモデルをダウンロードしてください」と出す（DEC-COM-069）。
  11. **データ**: 撮った画像は OCR が終わったら捨て、ディスクに書かない。読んだ文字は候補の画面を閉じるまでメモリの上だけに置き、ファイル・ログ・履歴に残さない。ログには画面の数・語の数・行の数・文字数・時間・送ったかだけを出す。送り先は会議の AI だけ。ローカルなら Mac・PC の外に出ない。Apple の fm では `fm respond` の引数に入り、動いている間は同じ Mac のほかのユーザーにも見える（DEC-COM-070）。これらを候補の画面の説明に書く。
  12. **1 つだけ**: 候補の画面が開いているときにもう一度選ぶと、新しく撮らずに、開いている画面を前に出す。候補の画面はタスクバー（Windows）・ウインドウの一覧（Mac）に出る。
- 出典: 2026-11-13 の依頼「全画面を取り込んで辞書を登録するという機能を追加してください」。同日の 2 回の回答で、メニューの項目・AI が推測した読みも付ける・REQ-MTG-030 と REQ-DIC-042 を変える・Mac と Windows の両方・送るものを見せてから送る・Windows にも既定の除外、を決めた（了承の日付を足す）
- 関係する要件: REQ-DIC-040, REQ-DIC-041, REQ-DIC-042, REQ-DIC-070, REQ-DIC-071, REQ-DIC-072, REQ-DIC-073, REQ-MTG-030, REQ-COM-032
- 対象: Mac / Windows
- 実装の場所（予定）: Mac は `DictionarySuggester.screenMaterial`・`suggestFromScreen`・`filter(…)` の 2 つの引数、`ScreenSnapshotReader.captureAll`・`recognizeAll`（今の `read` を 2 つに分ける）、`ScreenDictionaryWindow`、`AppDelegate.populateMenu`・`validateMenuItem`・`openScreenDictionary`。Windows は `Hanasu.Core/Text/ScreenDictionary.cs`、`DictionarySuggester.Filter` の 2 つの引数・`SuggestFromScreenAsync`、`Hanasu.Windows/Services/ScreenTextReader.cs`、`Hanasu.Windows/Views/ScreenDictionaryWindow.cs`、`TrayIcon`、`AppHost.ShowScreenDictionary`
- 確かめ方: `.build/debug/Hanasu --test-screen-dictionary`、`--suggest-dictionary --screen-text <ファイル>`、`--suggest-dictionary --screen`、`--render-screen-dictionary <フォルダ>`、`--apply-dictionary`。`cd windows && dotnet test Hanasu.Core.Tests --filter "FullyQualifiedName~ScreenDictionary|FullyQualifiedName~DictionarySuggester"`、`dotnet run --project Hanasu.Cli -- screen-dict-suggest <ファイル>`、`Hanasu.exe --dump-screen-text <ファイル>`（CI の windows-latest でも動かす）。画面は UI のテスト項目

### 変える要件（ユーザーの合意が要る。2026-11-13 の回答で合意）
- **REQ-MTG-030** の受け入れ条件: 今「Hanasu が画面収録の許可を求めるのは、設定の画面の『スクリーンショットの文字も AI に渡す』の欄から（音声入力のスクリーンショット。REQ-DIC-041・042）だけ。」 → 「…の欄からと、メニューの『画面から辞書の候補を探す…』から（REQ-DIC-075。会議の記録中は求めない）だけ。」。確かめ方の「画面収録が音声入力のスクリーンショットのためだけにあること」にも REQ-DIC-075 を足す。
- **REQ-DIC-042** の受け入れ条件 6: 今「除外アプリの欄は、AX の文脈かスクリーンショットのどちらかがオンなら編集できる。」 → 「除外アプリの欄はいつでも編集でき、画面から辞書の候補を探すとき（REQ-DIC-075）にも効く。」。
- REQ-DIC-071 は変えない（設定の欄の候補探しは今のまま）。

## 設計判断の案
（番号は DEC-DIC-230〜237。main の DEC-DIC-200・201・210〜216・220 と重ならない。spec に書くときに確かめ直す）

### DEC-DIC-230 Mac は、メニューを選んだときに 1 回だけ、音声入力のスクリーンショットと同じフィルタで撮り、撮り終えてからウインドウを開く
- 決めたこと: `ScreenSnapshotReader.read` を `captureAll`（すべての画面の `CGImage` と枠を返す）と `recognizeAll`（OCR して行を返す）に分け、`read` は 2 つを続けて呼ぶだけにする（音声入力の振る舞いは変えない）。画面から辞書の候補を探すときは、メニューが閉じるのを 0.3 秒待ってから `captureAll` を、入力先なし（`targetPID: nil`）・除外アプリの設定で呼び、撮り終えてから候補の画面を開いて `recognizeAll` を始める。OCR の言語は DEC-DIC-183 と同じ。候補の画面は `collectionBehavior` に `.moveToActiveSpace`・`.fullScreenAuxiliary` を付ける。メニューの項目は `validateMenuItem` で、`controller.state != .idle` か `editController.state != .idle` のときは無効にし（ステータスメニューは `autoenablesItems` が true なので `isEnabled` を書いても効かない）、`openScreenDictionary` の頭でも同じ条件なら何もしない。
- 理由: 既存の撮る・読む部分（REQ-DIC-041）とフィルタ（DEC-DIC-181・182）を使えば、写さないものが音声入力のスクリーンショットとそろう。ウインドウを先に開くと、全画面のアプリの Space から移って違う画面を撮るおそれがある。録音中・処理中に候補の画面や許可のダイアログが前面に出ると、整形した文章の貼り先がなくなる（DEC-COM-069・DEC-DIC-189）。
- 関係する要件: REQ-DIC-075
- 対象: Mac
- DEC-DIC-181 の「撮るのは、録音を始めたときと HUD でオンにしたときの 1 回ずつ」に「（画面から辞書の候補を探すときは DEC-DIC-230）」を書き足す

### DEC-DIC-231 送る材料は語の一覧と行。読みは推測を許し、表記はいつも材料と照らし合わせ、読みは 1 つずつ選べる
- 決めたこと:
  - 材料: `ScreenSnapshotLayout.layout(lines, limit: DictionarySuggester.characterLimit)` で語の一覧と行を作り（DEC-DIC-183 の並べ方。`layout` は変えない）、`DictionarySuggester.screenMaterial` で、語を先に、残りに行を、`Budget.cost` で数えながら上限まで詰め、送る語・行と `truncated` を返す。候補の画面はこの結果をそのまま見せ、同じものを送る。行も送るのは、「株式会社ストックマーク」のように語の取り出しで分かれる表記が行にしか出てこず、表記の照らし合わせに要るため。
  - 上限: `DictionarySuggester.budget(for:existing:instruction:)` に system instruction を渡せるようにし、画面用の instruction で枠を見積もる（Gemini・Claude は 60,000 文字、ローカル・Apple は文脈から見積もったトークン数。DEC-DIC-170）。
  - プロンプト: 新しいキー `dictionarySuggest.screenSystem`（画面用の system instruction）・`dictionarySuggest.screenTermsHeader`・`dictionarySuggest.screenLinesHeader`（17 言語）。読みは「その言語の音声認識が、その語を話したときに書きやすい形」を、英字・数字とカナが混ざった形（日本語なら「Jスリー」「ジェイスリー」）も含めて 4 つまで挙げさせる。ふつうの言葉と重なる読み・1 文字の読みは入れさせない。材料の中の指示に従わないことは、今の `dictionarySuggest.system` と同じく書く。各言語の版は、その言語の音声認識に合わせて書き直す。
  - 絞り込み: `DictionarySuggester.filter` に引数を 2 つ足す（Mac と Windows）。`readingsMustAppear`（既定 true。画面からは false）と、`requireSpellingInMaterial`（既定 false。画面からは true。読みの有無によらず、表記が材料に出てこなければ除く）。画面からは、読みの長さを 20 文字まで・1 候補 4 つまでに絞る。
  - 候補の行: 表記と理由の行の下に、読みごとのチェックを並べる（DEC-DIC-171 の行を広げた `ScreenDictionaryCandidateRow`。会議ノートと設定の欄の候補の行は変えない）。
- 理由: 画面には正しい表記しかなく、誤認識の形は出てこない（1 回目の回答）。今の `filter` は読みが残らなかった候補だけ表記を照らし合わせ、読みが材料に出てくることで AI が作った語を除いていた（`DictionarySuggester.swift:166-167`）。読みの照らし合わせを外すなら、表記の照らし合わせを必ずにしないと AI が作った語が通る。照合は「J」と「ジェイ」を同じにしない（DEC-DIC-081）ので、読みは実際に認識される形で、複数要る。推測の読みは、ふつうの言葉や、画面に埋め込まれた指示から作られたものが混ざりうる。辞書のルールは音声入力にも会議の文字起こしにも決定的に当たる（REQ-DIC-070・073）ので、読みを 1 つずつ外せるようにする。`layout` は文字数で数え、DEC-DIC-183・184 のタグがあるので、変えずに外で詰め直す。
- 関係する要件: REQ-DIC-075, REQ-DIC-071
- 対象: Mac / Windows
- DEC-DIC-089 に「画面からの候補では、読みを材料と照らし合わせず、表記はいつも照らし合わせる（DEC-DIC-231）」を書き足す

### DEC-DIC-232 候補の画面は独立したウインドウにし、送る材料を見せてから送る
- 決めたこと: Mac は SwiftUI の `ScreenDictionaryView` を入れた `NSWindow`、Windows は親を持たない `Window`（`ShowInTaskbar = true`。`MeetingDictionaryWindow` の並びを使う）。どちらも同時に 1 つだけで、開くときに前に出す。状態は「許可がない」「読んでいる」「読んだ（送る材料と『候補を探す』）」「探している」「候補」「0 件」「エラー」。送り先は「AI」タブの「議事録」の AI とモデルの名前で出す。
- 理由: メニューから開くので親のウインドウがない（親がないままタスクバーに出さないと、裏に回ったとき戻せない）。画面全体の文字は他人のメッセージや社外秘を含みうるので（DEC-DIC-180 と同じ理由）、送る前に、実際に送るものを見せる（2 回目の回答）。会議ノートの候補の画面と見た目をそろえる（DEC-DIC-171）。
- 関係する要件: REQ-DIC-075
- 対象: Mac / Windows
- DEC-DIC-087 の「対象: …（Windows は会議ノートの候補の画面だけ）」に、画面からの候補の画面（REQ-DIC-075）を足す

### DEC-DIC-233 Mac の画面収録の許可は、この機能を選んだときにも求める。求めたら撮らずに、開き直しを案内する
- 決めたこと: `ScreenRecordingPermission.isGranted` が偽で、`meetingRecorder.state == .idle` かつ `meetingRecorder.regeneratingID == nil` なら `ScreenRecordingPermission.request()` を呼び、候補の画面に開き直しの案内と「システム設定を開く」を出す（`CGRequestScreenCaptureAccess` は待たずに戻り、許可は開き直すまで効かないため、同じ回では撮らない）。会議の記録中・作り直し中は求めず、案内だけを出す。音声入力の録音中・処理中はメニューの項目が選べない（DEC-DIC-230）。DEC-DIC-189 の「設定の欄でだけ求め」を「設定の欄と、画面から辞書の候補を探すとき（DEC-DIC-233）にだけ求め」に直し、「録音中は求めない」は残す。設定の「権限」タブの画面収録の行の 2 つの文（「スクリーンショットの文字をオンにするときに求めます」「音声入力でスクリーンショットの文字を使うときだけ必要（…）」）を、この機能を含む文に直す（17 言語）。
- 理由: 1 回目の回答。会議の記録中・作り直し中に求めないのは、macOS の「終了して再度開く」で記録や作り直しが切れるのを防ぐため（DEC-DIC-189 と同じ。終了の確認も両方を見ている。`AppDelegate.swift:112-113`）。
- 関係する要件: REQ-DIC-075, REQ-MTG-030
- 対象: Mac

### DEC-DIC-234 Windows は、すべてのモニターを GDI で撮り、Hanasu のウインドウはキャプチャから外し、Windows.Media.Ocr で読む
- 決めたこと: `Screen.AllScreens`（モニターごと）を `BitBlt` で撮る（アプリは PerMonitorV2。物理ピクセルで撮る）。撮る前に、開いている Hanasu のウインドウに `SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)` を立てる（最低の OS が 10.0.19041 なので使える）。タスクトレイのメニューが閉じるのを 0.3 秒待ち、撮り終えてから候補の画面を開く。OCR は `Windows.Media.Ocr.OcrEngine` を、文字起こしの言語の OCR があればその言語、なければユーザーのプロファイルの言語、なければ英語で作り、どれに落ちたかを画面に出す（受け入れ条件 10）。`OcrEngine.MaxImageDimension` を超える画像は、重なりを持たせたタイルに分けて読み、同じ行は 1 つにする。OCR の行は単語（`OcrWord`）をつなぎ直す: 両側が漢字・かなの単語は空白なしで、ほかは空白でつなぐ（日本語・中国語の行が 1 文字ずつ空白で区切られて返ることへの対策。`--dump-screen-text` で確かめる）。語の取り出しと材料（Mac の `ScreenSnapshotLayout.terms`・`layout` にあたるもの）は `Hanasu.Core/Text/ScreenDictionary.cs` に移植する。Mac の正規表現は ICU の `\p{Han}` と集合の引き算なので、.NET では文字の範囲を書き下ろし、ハングル・キリル文字・アラビア文字・デーヴァナーガリー・全角の英数字を含む例を `common/testdata/logic/screen-terms.json` に置いて、両方で回す。
- 理由: Windows.Graphics.Capture はモニターを撮ると黄色い枠が出る（消すには追加の許可が要る）。GDI なら許可も枠もなく、`WDA_EXCLUDEFROMCAPTURE` で自分のウインドウを外せる。OCR の言語パックがない言語ではエンジンを作れない。縮めると小さい文字が読めない。語の取り出しを両方で同じにするため、例を共有する。
- 関係する要件: REQ-DIC-075
- 対象: Windows

### DEC-DIC-235 Windows は、既定の除外アプリのウインドウを、読む前に塗りつぶす
- 決めたこと: 撮る前に `EnumWindows` で、見えていて（`IsWindowVisible`）、最小化されておらず、`DWMWA_CLOAKED` が立っておらず、大きさが 0 でないトップレベルのウインドウを集め、プロセスの exe の名前が既定の一覧にあるものの枠（`DWMWA_EXTENDED_FRAME_BOUNDS`）を、撮った画像の上で黒く塗ってから OCR する。一覧は固定で、設定の欄は作らない: パスワード管理（`KeePass.exe`・`KeePassXC.exe`・`1Password.exe`・`Bitwarden.exe`・`Dashlane.exe`・`Keeper.exe`・`Enpass.exe`・`LastPass.exe`・`NordPass.exe`・`RoboForm.exe`・`ProtonPass.exe`）、通知（`ShellExperienceHost.exe`。スマホ連携 `PhoneExperienceHost.exe` も）、認証のダイアログ（`CredentialUIBroker.exe`）、ロック画面（`LockApp.exe`）。ほかのウインドウの下に隠れている部分まで塗ってよい（多く除く側に倒す）。一覧の exe 名は実機で確かめ、確かめられなかったものは verification に書く。
- 理由: Mac の DEC-DIC-182 と同じく、2FA のコードの通知・認証のダイアログ・パスワードを、Windows の既定の AI（Gemini）に送らない（2 回目の回答）。GDI はアプリを選んで撮れないので、撮ったあとで塗る。`ShellExperienceHost.exe` はスタートメニューなど隠れたウインドウも持ち、cloaked を見ないと画面の大きな範囲を塗ってしまう。
- 関係する要件: REQ-DIC-075
- 対象: Windows

### DEC-DIC-236 ローカルのモデルがないときは、ダウンロードを尋ねない
- 決めたこと: 画面からの候補探しでは `LocalModelDownloadPrompt.prepare` を呼ばず、`TextAIClient.requireFromSettings` の失敗をそのまま理由として出す。
- 理由: DEC-COM-069 は、辞書の候補ではダウンロードを尋ねないとしている（設定ですぐダウンロードできるため）。会議ノートの候補の画面（`MeetingDictionarySheet.search`）は尋ねているが、それは今の食い違いで、この PR では直さない。
- 関係する要件: REQ-DIC-075, REQ-COM-032
- 対象: Mac

### DEC-DIC-237 確かめる CLI は、撮る部分と AI を呼ばない部分に分ける
- 決めたこと:
  - Mac: `--test-screen-dictionary`（純粋な部分: 材料・上限と `truncated`・絞り込みの 2 つの引数と読みの上限・`screen-terms.json`。失敗があれば終了コード 1）。`common/testdata/logic/` の例は、plans/common-shared-data.md の入口（`--test-shared-cases`）がまだないので、`--test-screen-dictionary` が読む（入口ができたら移す）。`--suggest-dictionary --screen`（実機で撮って呼ぶ）と `--suggest-dictionary --screen-text <ファイル>`（1 行 1 つの OCR の行から呼ぶ）は、今の `DictionaryCLI.suggest` の中に `--meeting`・`--from-file` と同じ分かれ道として足す（足さないと最近の会議が送られる）。`--render-screen-dictionary <フォルダ>`（許可がない・読んだ・一部だけ送る・候補・0 件・エラー）。
  - Windows: `Hanasu.Core.Tests`（`screen-terms.json`・語のつなぎ方・絞り込み・材料）、`Hanasu.Cli` の `screen-dict-suggest <OCR の行のファイル>`、`Hanasu.Windows` の隠し引数 `--dump-screen-text <出力ファイル>`（アプリと同じ撮り方・除外・OCR で読んだ行と、落ちた OCR の言語を書き出す）。
  - CI: `.github/workflows/mac.yml` の自己テストに `--test-screen-dictionary` を足す。`windows.yml` に、`notepad.exe` を `KeePassXC.exe` の名前でコピーして決まった文字を出して起動し、日本語の OCR を入れて（`Add-WindowsCapability -Online -Name "Language.OCR~~~ja-JP~0.0.1.0"`）、`--dump-screen-text` の出力にその文字がないこと・日本語の行が空白なしでつながることを確かめる手順を足す（CI の画面で撮れなければ、そのことを PR に書いて manual に回す）。両方の paths に `common/testdata/logic/**` を足す。
  - それぞれに `// 確かめ方: REQ-DIC-075`。
- 関係する要件: REQ-DIC-075
- 対象: Mac / Windows

## やらないこと
- ショートカット・設定の欄のボタン（1 回目の回答で、メニューだけにした）。
- 範囲を選んで撮る・1 つのウインドウだけを撮る・撮り直す。
- 撮った画像を見せる・保存する。送る材料から語や行を選んで外す（送りたくないものがあれば閉じる）。
- 候補の画面で読みを書き換える（外すことはできる。書き換えは追加後に設定の辞書の表で）。
- 読んだ文字を、音声入力の整形（REQ-DIC-041）に回す・次の録音まで残す。
- 定期的に画面を撮って候補を出す。
- Windows の除外アプリの設定の欄（2 回目の回答で、既定の一覧だけにした）。
- 会議ノートの候補の画面がダウンロードを尋ねる食い違い（DEC-DIC-236）と、今のメニューの `isEnabled` が効いていないかもしれないこと（DEC-DIC-230）を直すこと。見つけたことは PR に書く。

## 手順
0. `origin/main` をこのブランチに取り込む（#110・#112・#117。計画が触るファイルの多くが変わっている）。そのあと DEC-DIC-230〜237・REQ-DIC-075 が空いていることを確かめ直す。
1. spec（ひとまとめで）:
   - `docs/spec/dictation.md`: REQ-DIC-075、DEC-DIC-230〜237 を足す。REQ-DIC-042 の受け入れ条件 6、DEC-DIC-087・089・180（「欄はどちらかがオンなら編集できる」）・181・189 を直す。
   - `docs/spec/meeting.md`: REQ-MTG-030 を直す。
   - `docs/spec/common.md`: DEC-COM-107 の Windows にない機能の一覧に「画面から辞書の候補は Windows にもある」を書き足す。
   - `docs/roadmap.md`: FUT-003 に、画面からの候補では GDI で撮ったこと（DEC-DIC-234）と、除外の一覧（DEC-DIC-235）を使い回せることを書く。FUT-017 に「`common/testdata/logic/screen-terms.json` を先に作った」と書く。
2. 共有の例: `common/testdata/logic/screen-terms.json`（入力の行 → 語、Windows の OCR の語の並び → つないだ行）。手順 4・5 の前に作る。
3. プロンプト: `Sources/Hanasu/Resources/Prompts/<言語>.json` に `dictionarySuggest.screenSystem`・`screenTermsHeader`・`screenLinesHeader` を 17 言語で（i18n エージェントに 3 言語ずつ分けて並べて任せる。読みの例は言語ごとに書き直させる）。
4. Mac（手順 5 と並べて進められる。触るファイルが重ならない）:
   - `ScreenSnapshot.swift`: `read` を `captureAll`・`recognizeAll` に分ける（DEC-DIC-230。音声入力の振る舞いは変えない）。
   - `DictionarySuggester.swift`: `filter` の 2 つの引数、`budget(for:existing:instruction:)`、`screenMaterial`、`suggestFromScreen`。タグ `// 要件: REQ-DIC-075`、`// 設計判断: DEC-DIC-231`。
   - 新しいファイル `ScreenDictionaryWindow.swift`（DEC-DIC-231・232・233・236。`ScreenDictionaryCandidateRow`）。`AppSettings.shared.dictionaryText` に `DictionarySuggester.appending` で足す。
   - `AppDelegate`: `populateMenu` に項目、`validateMenuItem`、`openScreenDictionary`。
   - `ScreenContextSettingsView.swift`: 除外アプリの欄の `.disabled(…)` を外し、欄の説明に、画面から辞書の候補を探すときにも効くことを書く（REQ-DIC-042）。
   - `SettingsView.swift`: 「権限」タブの画面収録の 2 つの文（DEC-DIC-233）。
   - CLI: `DictionaryCLI.suggest` に `--screen`・`--screen-text`、新しいファイル `ScreenDictionaryCLI.swift` に `--test-screen-dictionary`・`--render-screen-dictionary`、`main.swift` の入口。
   - UI の文字列は `tr("…")`、`python3 scripts/i18n-strings.py sync` のあと 17 言語の訳。
5. Windows（手順 4 と並べて進められる）:
   - `Hanasu.Core/Text/ScreenDictionary.cs`、`DictionarySuggester.cs`（`Filter` の 2 つの引数・`BudgetFor` の instruction・`SuggestFromScreenAsync`）。
   - `Hanasu.Windows/Services/ScreenTextReader.cs`（DEC-DIC-234・235）と `--dump-screen-text`。
   - `Hanasu.Windows/Views/ScreenDictionaryWindow.cs`、`TrayIcon`（項目と、音声入力中に無効にする条件）、`AppHost.ShowScreenDictionary`。
   - `Strings.resx` と 16 の訳。
   - `Hanasu.Core.Tests` にテスト、`Hanasu.Cli` に `screen-dict-suggest`。
6. CI: `mac.yml`・`windows.yml`（DEC-DIC-237）。
7. UI のテスト項目: `common/testdata/ui/dictation.json` に足す（Mac は render: 許可がない・読んだ・一部だけ送る・候補（読みのチェック）・0 件・エラー。Windows は manual: 同じ状態と、除外のウインドウが塗られること）。`common/testdata/ui/settings.json` の UX-171 など、除外アプリの欄を「どちらかがオンなら編集できる」とする既存の項目を直し、権限タブの文の項目を直す。`python3 scripts/ui-cases.py md`・`check`。
8. 文書:
   - `docs/design/dictation.md`（辞書の候補の節に画面からの経路、権限の表）、`docs/design/meeting.md` の 2 か所（画面収録を求めるのは…だけ）、`docs/design/security.md`（画面の文字が会議の AI に送られること、fm の引数、画面に埋め込まれた指示が推測の読みになりうることと、読みを 1 つずつ外せること）、`docs/design/security-windows.md`（GDI・既定の除外・写るもの・ログ）、`docs/guide.md`（画面収録の許可を求める場面、辞書の候補の入口）、`windows/README.md`（Mac 版との差）。
   - `README.md` の 3 か所（辞書の行・「Screen Recording is asked for only if…」・プライバシーの節の AI に渡るもの）と、15 の訳（`README.ja.md` を含む `README.*.md` の 16 ファイルのうち、`ls README.*.md` で数えて全部）の同じ場所。
9. 確かめる（下）。

## 確かめ方
- `swift build`
- `python3 scripts/check-spec.py`、`python3 scripts/check-spec.py --diff origin/main`、`python3 scripts/check-i18n.py`、`python3 scripts/ui-cases.py check`
- `.build/debug/Hanasu --test-screen-dictionary`、`--test-screen-ocr`・`--test-dictionary`・`--test-meeting-dictionary`（今のものが壊れていないこと）
- `.build/debug/Hanasu --suggest-dictionary --screen-text <「J3」「Kubernetes」「株式会社ストックマーク」を含む行のファイル>` を Gemini・Claude・ローカル（Gemma 4 E4B）で。出た `Jスリー => J3` などを入れた辞書で `--apply-dictionary "Jスリーの件ですが" --dictionary <辞書>` が「J3の件ですが」になること（受け入れ条件 7）。`--prompt-language en` でも 1 回。結果を verification に残す
- `.build/debug/Hanasu --suggest-dictionary --screen`（実機。Hanasu の設定のウインドウと除外アプリを開いたままで、その文字が材料に入らないこと）
- `.build/debug/Hanasu --render-screen-dictionary <フォルダ>` と設定の画面を ui-test スキルで見る（`--ui-language en` も）
- `cd windows && dotnet test Hanasu.Core.Tests`、CI の `--dump-screen-text` の手順
- 実機（Mac）: メニューから選ぶ → 許可がなければダイアログと開き直しの案内 → 開き直して選ぶ → 送る材料（語と行）→ 「候補を探す」 → 候補 → 読みを 1 つ外して追加 → 辞書の末尾に、外した読みなしで入る。全画面表示のアプリ（Keynote など）の上で選んでも、そのアプリの文字が読まれる。録音中はメニューの項目が灰色（灰色にならなければ `validateMenuItem` を見直す）。会議の記録中に許可がないと、求めずに案内が出る。読んでいる間・探している間の「キャンセル」で止まる。もう一度選ぶと開いている画面が前に出る。`log show --predicate 'subsystem == "dev.mactypeless.Hanasu"'` に読んだ文字が出ないこと
- Windows: CI か実機で `--dump-screen-text`。画面は UI のテスト項目（manual）。ログのファイルに読んだ文字が出ないこと。確かめられなかったことは PR に書く

## 敵対的レビュー
2026-11-13、requirements-reviewer（Opus）。1 回目は 2 つ並べて（A: 目的・受け入れ条件・失敗時・範囲・仮に決めたこと、B: 既存の要件・Mac と Windows・17 言語・データと安全・手順の事実・確かめ方）、2 回目は直した計画を 1 つで。

### 1 回目
| # | 重さ | 指摘 | 仕分け | どうしたか |
| --- | --- | --- | --- | --- |
| 1 | 重大 | 推測した読み「ジェイスリー」は、実際の認識「Jスリー」と照合で合わず、足したルールが効かない。受け入れ条件が「読みが付いて並ぶ」までしか見ていない | 直す | 受け入れ条件 7 を「足した辞書で `--apply-dictionary` が『J3の件ですが』になる」に。プロンプトで混ざった形を含めて複数の読みを挙げさせる（DEC-DIC-231）。1 回目の質問の例は「ジェイスリー」だった |
| 2 | 重大 | 選んだ瞬間にすべての画面の文字を AI に送り、説明は送ったあとにしか見えない | 聞く | 回答「読んだ語を見せてから送る」→ 受け入れ条件 3、DEC-DIC-232 |
| 3 | 重大 | Windows に除外がなく、既定の Gemini に 2FA の通知やパスワード管理の画面が送られうる | 聞く | 回答「既定の除外を作る」→ DEC-DIC-235、受け入れ条件 8 |
| 4 | 重大 | 音声入力の録音中・処理中に選んだときの扱いがなく、前面を奪い許可を求める。DEC-DIC-189 の「録音中は求めない」を黙って外している | 直す | 受け入れ条件 1 で項目を無効に（Mac・Windows）。DEC-DIC-230・233、DEC-DIC-189 の「録音中は求めない」を残す |
| 5 | 重大 | `CGRequestScreenCaptureAccess` はすぐ戻り、許可は開き直すまで効かない | 直す | 受け入れ条件 9 と DEC-DIC-233 を、開き直しを案内する流れに |
| 6 | 重大 | 今の `filter` は読みが残れば表記を照らし合わせない | 直す | DEC-DIC-231 に `requireSpellingInMaterial` |
| 7 | 重大 | 除外アプリの欄は、トグルがどちらもオフ（既定）だと編集できない（REQ-DIC-042） | 聞く | 回答「いつでも編集できるように変える」→ 変える要件に REQ-DIC-042 |
| 8 | 重大 | Apple の fm では画面の文字が `fm respond` の引数に入り `ps` で見える | 直す | 受け入れ条件 11 と security.md の手順に |
| 9 | 重大 | Windows の OCR が使える言語に黙って落ちる | 直す | 受け入れ条件 10、DEC-DIC-234 |
| 10 | 重大 | Windows の撮る・読む部分を確かめる手段がない。日本語の OCR の行が 1 文字ずつ区切られると語が取れない（推測） | 直す | DEC-DIC-237 に `--dump-screen-text` と CI、DEC-DIC-234 に語のつなぎ方 |
| 11 | 重大 | REQ-MTG-030 を変えると、権限タブの文・README・guide.md・design・DEC-DIC-087・181 が事実と合わなくなる | 直す | 手順 1・4・8 |
| 12 | 軽微 | 材料が上限で切れても知らせない | 直す | 受け入れ条件 3 |
| 13 | 軽微 | `layout` は文字数で数える。`budget(for:)` が古い instruction で見積もる | 直す | DEC-DIC-231 |
| 14 | 軽微 | `--suggest-dictionary --screen` は今の `DictionaryCLI` が先に受け取り、最近の会議を送る | 直す | DEC-DIC-237 |
| 15 | 軽微 | 確かめ方に Claude・英語・キャンセル・前に出す・ログがない | 直す | 確かめ方に足した |
| 16 | 軽微 | FUT-003・FUT-017 に触れていない | 直す | 手順 1 |
| 17 | 軽微 | ローカルのモデルがないとき尋ねるかがあいまい | 直す | DEC-DIC-236 |
| 18 | 軽微 | Windows.Graphics.Capture を見送る理由の「ピッカーが要る」は不正確（推測） | 直す | 理由を「枠が出る」に絞った |

### 2 回目
| # | 重さ | 指摘 | 仕分け | どうしたか |
| --- | --- | --- | --- | --- |
| 1 | 重大 | DEC-DIC-200・201 は main ですでに使われている（#110）。作業ツリーは main より 3 つのマージ分古い | 直す | DEC-DIC-230〜237 に振り直し、手順 0 で main を取り込む（`git show origin/main:docs/spec/dictation.md` で確かめた） |
| 2 | 重大 | 見せるのは語だけなのに、行（他人のメッセージの文章）も送る | 直す | 受け入れ条件 3・DEC-DIC-231: 送る材料（語と行）をそのまま見せ、切ったことも送る前に出す |
| 3 | 重大 | 推測の読みは材料と照らし合わせなくなるのに、読みを 1 つずつ外せない。ふつうの言葉や画面に埋め込まれた指示による読みが辞書に入りうる | 直す（質問の回数を使い切ったので、「仮に決めたこと」で了承を求める） | 受け入れ条件 5・6、DEC-DIC-231: 読みごとのチェック、読みの長さと数の上限。security.md に書く |
| 4 | 重大 | ステータスメニューは `autoenablesItems` が true のままで、`isEnabled` を書いても効かない見込み | 直す | DEC-DIC-230: `validateMenuItem` と、`openScreenDictionary` の頭での確認（`grep autoenablesItems` で確かめた） |
| 5 | 重大 | `ShellExperienceHost.exe` の隠れたウインドウまで塗ると画面の大半が消える。除外を確かめる手段がない | 直す | DEC-DIC-235 で cloaked・最小化・大きさ 0 を除く。DEC-DIC-237 で CI に偽の `KeePassXC.exe` を使った確かめを足した。一覧も広げた |
| 6 | 重大 | Mac の既定の AI（ローカルの Gemma）で効くことを、受け入れ条件が求めていない | 聞く（質問の回数を使い切ったので、「仮に決めたこと」で了承を求める） | 下の「仮に決めたこと」 |
| 7 | 重大 | 全画面表示のアプリの上で使うと、候補の画面を開くときに Space が移り、違う画面を撮るおそれ | 直す | 受け入れ条件 2・DEC-DIC-230: 撮り終えてから開く、`.moveToActiveSpace`・`.fullScreenAuxiliary`、実機の確かめに足した |
| 8 | 軽微 | DEC-DIC-180 と既存の UI のテスト項目も「どちらかがオンなら編集できる」 | 直す | 手順 1・7 |
| 9 | 軽微 | プロンプトの言語は文字起こしの言語で決まる（DEC-COM-161） | 直す | 受け入れ条件 7 を「文字起こしの言語が英語」に |
| 10 | 軽微 | CI で `--test-screen-dictionary` が回らない、paths、`--test-shared-cases` との関係、手順の番号、確かめ方に DEC を書いていた | 直す | DEC-DIC-237、手順 2・6、REQ-DIC-075 の確かめ方にコマンドを直接書いた |
| 11 | 軽微 | 作り直し中の許可、Windows のウインドウの親とタスクバー、.NET の正規表現の移植、README の数、Windows のログ | 直す | DEC-DIC-233・232・234、手順 8、確かめ方 |

見られなかったこと: `WDA_EXCLUDEFROMCAPTURE` が `BitBlt` に効くか、Windows.Media.Ocr の日本語の行の形、`MaxImageDimension` の値、既定の除外の exe 名と cloaked のウインドウ（Windows の実機がない。DEC-DIC-237 の CI と `--dump-screen-text` で確かめ、確かめられなければ PR と verification に書く）。全画面の Space の振る舞いと、今のメニューの `isEnabled` が効くか（Mac の実機で見る）。Gemma 4 E4B が画面の語にどんな読みを返すか（新しいプロンプトがまだないので、実装の途中で測る）。

## 仮に決めたこと（了承のときに見てください）
- **Mac の既定の AI（ローカルの Gemma 4 E4B）での質**: 送り先は「議事録」の AI で、Mac の既定はローカルの Gemma。Gemma で読みの推測が外れても不合格にはせず、結果を verification に残す。候補の画面で、送り先がローカル・Apple のときは「読みの推測は Gemini・Claude のほうが確かです（設定の『AI』の『議事録』で変えられます）」と添える。Gemma でも効くことを合格の条件にしたいなら、実装の途中で測った結果を見て、プロンプトを直すか、この機能だけ別の AI を選べるようにするかを決め直す。
- **読みを 1 つずつ外せる**（2 回目のレビューの指摘 3）: 候補の行に読みごとのチェックを付ける。会議ノート・設定の欄の候補の行は今のまま。
- 送り先の AI は、ほかの辞書の候補探しと同じ「議事録」の AI（DEC-COM-040）。
- 送る材料から語や行を選んで外すことはできない。送りたくないものがあれば閉じる。
- Windows の撮り方は GDI。既定の除外の一覧は固定（設定の欄はない）。
- Apple の fm でも、材料の上限は会議の候補と同じ（文脈から見積もる）。送る前に材料を見せるので、音声入力のスクリーンショット（500 文字）のようには絞らない。
