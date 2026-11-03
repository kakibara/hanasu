# このリポジトリで作業するエージェントへ

Hanasu（音声入力と会議の記録。Mac 版は `Sources/Hanasu`、Windows 版は `windows/`）。文書の地図と決まりは [docs/README.md](docs/README.md)。

## 機能を変える前に
- 変える場所のコードのタグ（`// 要件: REQ-…`、`// 設計判断: DEC-…`）と、[docs/spec/](docs/spec/) のその項目を読む。
- **要件（REQ）を変えるときは、ユーザーの合意を取る。** 合意なしに要件を書き換えない。合わないところは、その要件に「食い違い（ユーザーの確認待ち）」と書いて残す。
- 設計判断（DEC）は、書いてある理由がもう当てはまらないことを確かめてから変え、spec も直す。
- タグのないコード（暗黙の振る舞い）を変えるときは、先に要件か設計判断として spec に書いて（格上げして）タグを付けるか、暗黙のままでよいと判断する。

## 新しい機能を作るとき
- 要件を先に spec に書く（出典に、依頼の日付と要旨か PR 番号）。決めた細部は設計判断として、理由と PR 番号を書く。
- その振る舞いを決めているコードに、タグを付ける（すべての要件に少なくとも 1 か所）。
- 実装の説明は [docs/design/](docs/design/)、日付の付いた検証の結果は [docs/verification/](docs/verification/)。

## 文書の役割
- spec は「こうあるべき」（要件・設計判断）。design は「今こう作られている」で、コードと食い違ったらコードが正しい（design を直す）。design にコードの写し（プロンプトの全文・既定値の一覧・CLI のオプション）を置かず、ファイルと型・関数の名前で誘導する。

## 機能をなくすとき
- spec の項目は消さず、そのファイルの「## 廃止」の節へ移して `- 状態: 廃止（日付・理由・PR）` を書く。ID は使い回さない。コードのタグは外す。

## 計画
- まだ作らないもの・見送ったものは [docs/roadmap.md](docs/roadmap.md) に `FUT-<番号>` で書く。spec と design には計画を書かない。
- roadmap の項目を実装したら、spec に移して roadmap には「→ REQ-…」だけを残す。

## 確かめる・PR
- `python3 scripts/check-spec.py` をエラーなしで通す。PR の前に `python3 scripts/check-spec.py --diff origin/main` で、触った要件・設計判断の一覧を見る（CI の `.github/workflows/spec.yml` も同じものを動かす）。
- タグのあるコードを変えたら spec を直す。直さなくてよい変更なら、PR の本文かコミットメッセージに `Spec-Impact: なし（理由）` と書く。
- PR の本文は `.github/pull_request_template.md` の項目（触った ID・Spec-Impact・新しい要件の合意・roadmap から移したもの）を埋める。
- 要件の「確かめ方」に挙げた CLI・テストには `// 確かめ方: REQ-…` を書く。
- Mac のアプリは `swift build`、Windows 版は `cd windows && dotnet test Hanasu.Core.Tests` で確かめる。
