# `hanasu` の共有のテストデータ

Mac と Windows の `hanasu` が同じ出力を出すことを確かめるためのデータ（設計判断 DEC-COM-192）。

| ファイル | 中身 |
| --- | --- |
| `meetings/` | 架空の会議（時刻は UTC、ID は決めた値） |
| `settings.json` | 架空の設定（プロンプトの言語・辞書・追加の指示・アプリ名を送るか） |
| `cases.json` | 動かすコマンドと MCP のツールの呼び出し、「今」・時差・乱数・偽の AI の答え |
| `expected.json` | 期待する出力。Mac の `Hanasu --write-cli-golden` が書く（手で直さない） |

- Mac: `swift build && .build/debug/Hanasu --test-hanasu-command`（リポジトリのルートで）。期待する出力を書き直すときは `.build/debug/Hanasu --write-cli-golden`
- Windows: `cd windows && dotnet test Hanasu.Core.Tests`（`CommandGoldenTests`）

## 比べないもの・置き換えるもの（`cases.json` の `ignoreKeys`・`replace`）

- 話者の表示の名前（`speakerName`・`speakers[].name`）。「同席者」などの訳が Mac と Windows で違う。話者のキーは比べる
- 使った AI（`ai`）。Windows に `apple` はなく、テストの偽の AI も違う
- 版・実行ファイルのパス（`version`・`executable`）
- 共有の英語の文の `this Mac` と `this PC`
- `compare` が `mcp-error` のものは、`isError` だけを比べる（理由の文は表示の言語）
- 文の出力（`--json` なし）は比べない
