# リリースの作り方

[tagpr](https://github.com/Songmu/tagpr) で行います（`.tagpr`、`.github/workflows/tagpr.yml`）。

Claude Code では、スキル `release`（[.claude/skills/release/SKILL.md](../.claude/skills/release/SKILL.md)）が下の 2〜5 をまとめて行います（「リリースして」と頼む）。

1. `main` に変更が入ると、tagpr が次のバージョンのリリース PR（`VERSION` と `CHANGELOG.md` の更新）を作り・更新します。
2. **版の上げ幅を決めます**（DEC-REL-009）。tagpr の既定はパッチ（1.3.3 → 1.3.4）なので、新しい機能が入っていればマイナー（1.4.0）にします。
   - major: 今の利用者が何かしないと使い続けられない（動作環境の引き上げ・保存の形が前の版で読めない・機能の廃止）
   - minor: 新しい機能（新しい要件・対象の OS が増えた・新しい設定や選択肢）
   - patch: それ以外（不具合の修正・文言・文書・CI・内部の整理）

   変えるときは、リリース PR の `VERSION` を直し、`CHANGELOG.md` の先頭の見出しの版を合わせます（tagpr はマージのときに `VERSION` の版を使います）。
3. **リリース文を書きます**（REQ-REL-006、DEC-REL-010）。[docs/releases/TEMPLATE.md](releases/TEMPLATE.md) を `docs/releases/v<版>.md` にコピーし、使う人向けに「ハイライト・新しい機能・改善・不具合の修正・気をつけること」を書いて、リリース PR のブランチにコミットします。
4. リリース PR をマージすると、tagpr がタグと下書きのリリースを作ります。
5. 続けて macOS 26 のランナーが Mac 版を、Windows のランナーが Windows 版をビルドし、`Hanasu-<バージョン>-macOS.zip` と `Hanasu-<バージョン>-Windows-x64.zip` を添付してリリースを公開します。本文は「リリース文 → PR の一覧 → インストールの手順と SHA-256」の順です（`scripts/compose-release-notes.py`。リリース文がなければ PR の一覧から）。既存のタグの添付ファイルや本文を作り直すときは、Actions の「tagpr」を tag を指定して手動で実行します。

リリースが失敗したとき:

- 手動の実行は、ワークフローは `main` のものを使いますが、ビルドするコードとリリース文は**タグの時点のもの**です。一時的な失敗やワークフローの問題なら、手動の実行で作り直せます。
- タグの時点のコードが原因なら、手動の実行では直りません。公開前の下書きなら、直しを `main` に入れ、下書きとタグを消して、直した `main` にタグを付け直し（下書きはタグを作らないので、タグを先に push）、下書きを作ってから手動で実行します。公開済みの版は消さず、次のパッチで直します。手順は [.claude/skills/release/SKILL.md](../.claude/skills/release/SKILL.md) の「失敗したとき」です。
- リリースの前に、Mac 版の最適化ビルド（`swift build -c release`）が通るかを確かめます。PR の CI は Mac 版をビルドしません。

初回だけ必要な準備:

- リポジトリの Settings → Actions → General → Workflow permissions で「Allow GitHub Actions to create and approve pull requests」をオンにする。
- リリース用の署名証明書を作って Secrets に登録する（なければアドホック署名になり、アップデートのたびにアクセシビリティの許可が外れます）。

```bash
./scripts/setup-release-signing.sh
```
