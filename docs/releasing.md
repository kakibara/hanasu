# リリースの作り方

[tagpr](https://github.com/Songmu/tagpr) で行います（`.tagpr`、`.github/workflows/tagpr.yml`）。

1. `main` に変更が入ると、tagpr が次のバージョンのリリース PR（`VERSION` と `CHANGELOG.md` の更新）を作り・更新します。
   - 既定はパッチ（0.1.0 → 0.1.1）。リリース PR に `tagpr:minor` / `tagpr:major` ラベルを付けるか、`VERSION` を直接書き換えると上げ幅を変えられます。
2. リリース PR をマージすると、tagpr がタグと下書きのリリースを作ります。
3. 続けて macOS 26 のランナーが Mac 版を、Windows のランナーが Windows 版をビルドし、`Hanasu-<バージョン>-macOS.zip` と `Hanasu-<バージョン>-Windows-x64.zip` を添付してリリースを公開します。既存のタグの添付ファイルを作り直すときは、Actions の「tagpr」を tag を指定して手動で実行します。

初回だけ必要な準備:

- リポジトリの Settings → Actions → General → Workflow permissions で「Allow GitHub Actions to create and approve pull requests」をオンにする。
- リリース用の署名証明書を作って Secrets に登録する（なければアドホック署名になり、アップデートのたびにアクセシビリティの許可が外れます）。

```bash
./scripts/setup-release-signing.sh
```
