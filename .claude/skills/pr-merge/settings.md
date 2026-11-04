# マージの前に不具合を止めるための設定（Hanasu 向けの提案）

[SKILL.md](SKILL.md) の手順は、エージェントが守れば効く。ここに書くのは、**守らなかったときにも止まる**ようにする設定。2026-11-04 に調べた。まだどれも入れていない（入れるかはユーザーが決める）。

## 今の状態（2026-11-04、`gh api` で確かめた）

| 項目 | 今 |
| --- | --- |
| リポジトリ | `kakibara/hanasu`（個人のアカウントの public リポジトリ） |
| `main` のブランチの保護・ruleset | なし（必須のチェックがなく、チェックが落ちていてもマージできる） |
| PR で動く CI | `spec`（spec の検査）、`windows`（`windows/` などを触ったときだけ） |
| PR で Mac 版をビルドする CI | なし（`tagpr.yml` の mac ジョブがリリースのときに初めてビルドする） |
| Mac のテスト | テストのターゲットなし。自己テストの CLI（`--test-dictionary`・`--test-paste-target`・`--test-speaker-names`）がある |
| 自動マージ（`allow_auto_merge`）・「ブランチを更新」ボタン（`allow_update_branch`） | どちらも off |
| マージの方法 | merge・squash・rebase のすべてが許可。履歴はマージコミット |

## この種類のアプリで気をつけること

Hanasu は「Swift Package の macOS アプリ（macOS 26・Apple Silicon）＋ .NET 8 の Windows 版」で、次の性質がある。

- **ビルドが OS ごとに分かれている。** Mac 版は macOS のランナーでしかビルドできず、Windows 版の WPF は Windows でしかビルドできない。どちらかの CI がないと、その OS のコンパイルエラーは素通りする。
- **最適化ビルドでだけ落ちることがある。** Swift の型の推論の時間切れ（v1.4.0）。PR の CI ではリリースと同じ `-c release` でビルドする。
- **振る舞いのテストが CLI の自己テスト。** XCTest のターゲットがないので、CI で `.build/debug/Hanasu --test-…` を走らせる（AI・マイク・許可が要らないものだけ）。
- **エージェントのセッションが並行して PR を作り、続けてマージする。** テキストのコンフリクトはないのに合わせると壊れる「意味のコンフリクト」が起きやすい。
- **リリースは tagpr。** `main` に入ったものはそのまま次のリリース PR に載る。`main` を壊すと、リリースのときに初めて気づく（PR #39）。

## 提案 1: PR で Mac 版をビルドする CI を足す（いちばん効く）

`.github/workflows/mac.yml` を足す。GitHub のホストのランナーは public リポジトリなら無料（macOS も）。

```yaml
# Mac 版のビルドと自己テスト。PR（と main への push）ごとに動く。
name: mac
on:
  pull_request:
  push:
    branches: ["main"]

permissions:
  contents: read

concurrency:
  group: mac-${{ github.ref }}
  cancel-in-progress: true

jobs:
  mac:
    runs-on: macos-26          # tagpr.yml の mac ジョブと同じ
    steps:
      - uses: actions/checkout@v6
        with:
          persist-credentials: false
      - uses: actions/cache@v4
        with:
          path: .build
          key: spm-${{ runner.os }}-${{ hashFiles('Package.resolved') }}
          restore-keys: spm-${{ runner.os }}-
      - name: Build (debug)
        run: swift build
      # AI・マイク・許可を使わない自己テスト（失敗があれば終了コード 1）
      - name: Self tests
        run: |
          .build/debug/Hanasu --test-dictionary
          .build/debug/Hanasu --test-paste-target
          .build/debug/Hanasu --test-speaker-names
      # リリース（scripts/build-app.sh）と同じ最適化ビルド。最適化でだけ落ちるもの（v1.4.0）を PR で見つける
      - name: Build (release)
        run: swift build -c release
```

- PR の `pull_request` のイベントは、**PR の head ではなく「その時点の base に PR を入れたマージコミット」（`refs/pull/N/merge`）**をビルドする。だから意味のコンフリクトも見つかる。ただし、そのあとに `main` が動くと古くなる（→ 提案 2 の「最新であること」）。
- 自己テストが CI のランナー（画面のログインがない）で動くかは、入れた最初の PR で確かめる（手元では 3 つとも終了コード 0 で、ウインドウを開かない）。
- 自己テストを足したら（`--test-…`）、この一覧にも足す。

## 提案 2: `main` に ruleset を入れて、チェックを必須にする

個人のアカウントの public リポジトリでも ruleset は使える。**マージキュー（merge queue）は組織のリポジトリだけ**なので使えない。代わりに「マージの前にブランチが最新であること」（strict）を必須にする。これで「古い `main` で通った CI」のままマージできなくなる。

必須にするチェック:

| チェックの名前 | ワークフロー | 注意 |
| --- | --- | --- |
| `check` | `spec.yml` | そのままでよい |
| `mac` | 提案 1 の `mac.yml` | |
| `windows` | `windows.yml` | **今は `paths` で絞っているので、必須にすると `windows/` を触らない PR が「待機中」のまま止まる。** 提案 3 で直してから必須にする。ジョブの名前も `build` から `windows` に変える（名前が一般的すぎるとほかのチェックと紛れる） |

入れ方（ユーザーが入れる。管理者の権限が要る）:

```bash
gh api -X PATCH repos/kakibara/hanasu -F allow_update_branch=true   # PR の「Update branch」ボタン
gh api -X POST repos/kakibara/hanasu/rulesets --input - <<'JSON'
{
  "name": "main",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "bypass_actors": [ { "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "pull_request" } ],
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "pull_request", "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false } },
    { "type": "required_status_checks", "parameters": {
        "strict_required_status_checks_policy": true,
        "required_status_checks": [ { "context": "check" }, { "context": "mac" }, { "context": "windows" } ] } }
  ]
}
JSON
```

- `actor_id: 5` はリポジトリの Admin の役割。`bypass_mode: pull_request` で、急ぎのときは管理者が PR の画面から迂回できる（ふだんは使わない）。
- 承認の数は 0 にする（1 人で作っているので。エージェントの確認はスキルの手順で行う）。
- tagpr はリリース PR のブランチに push し、タグを作るだけで `main` に直接 push しないので、この ruleset で止まらない。リリース PR にも必須のチェックが掛かる（リリース PR も `main` と同じコードなので通る）。
- strict にすると、並行した PR は 1 つマージするたびに「Update branch」が要る。手間は増えるが、それがまさに「新しい `main` で確かめ直す」こと。

## 提案 3: `windows.yml` を必須にできる形にする

GitHub の文書のとおり、`paths` で飛ばされたワークフローのチェックは「待機中」のまま残り、必須にすると PR がマージできなくなる。ジョブの `if:` で飛ばされたジョブは「成功」と報告されるので、絞り込みをジョブの側に移す。

```yaml
on:
  pull_request:          # paths を外す
  push:
    branches: ["main"]
  workflow_dispatch:

jobs:
  changes:
    runs-on: ubuntu-latest
    outputs:
      windows: ${{ steps.diff.outputs.windows }}
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0
          persist-credentials: false
      - id: diff
        env:
          BASE_REF: ${{ github.base_ref }}
        run: |
          if [ "${{ github.event_name }}" != "pull_request" ]; then echo "windows=true" >> "$GITHUB_OUTPUT"; exit 0; fi
          if git diff --name-only "origin/${BASE_REF}...HEAD" | grep -qE '^(windows/|\.github/workflows/windows\.yml$|scripts/llama-cpp\.lock$|scripts/fetch-llama-cpp\.ps1$)'; then
            echo "windows=true" >> "$GITHUB_OUTPUT"
          else
            echo "windows=false" >> "$GITHUB_OUTPUT"
          fi

  windows:               # 今の build ジョブ（名前を windows に）
    needs: changes
    if: needs.changes.outputs.windows == 'true'
    runs-on: windows-latest
    # …今の build ジョブの中身のまま
```

## 提案 4: Claude Code のフックで、確かめずにマージするのを止める

エージェントが `gh pr merge` を直接打つと、スキルの手順を飛ばせてしまう。プロジェクトの `.claude/settings.json` に PreToolUse のフックを足し、`--match-head-commit` のない `gh pr merge` を止める（確かめた SHA を付けることをスキルの手順にしているので、付いていない＝手順を通っていない、とみなす）。

`.claude/hooks/guard-pr-merge.sh`:

```bash
#!/bin/bash
# gh pr merge は、確かめたコミットを --match-head-commit で指定したときだけ通す（.claude/skills/pr-merge）
cmd=$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))')
if printf '%s' "$cmd" | grep -qE '(^|[;&|[:space:]])gh[[:space:]]+pr[[:space:]]+merge' \
   && ! printf '%s' "$cmd" | grep -q -- '--match-head-commit'; then
  echo "gh pr merge は .claude/skills/pr-merge の手順で確かめてから、--match-head-commit <確かめた SHA> を付けて実行する" >&2
  exit 2   # 2 で止め、標準エラーの文をエージェントに返す
fi
exit 0
```

`.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash",
        "hooks": [ { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/guard-pr-merge.sh" } ] }
    ]
  }
}
```

- 入れたら、release スキルの 5 の `gh pr merge <番号> --merge` にも `--match-head-commit` を付ける（付けないとリリース PR のマージも止まる）。
- フックはエージェントの手順を守らせるもの。人が GitHub の画面からマージするのは止めない（それは提案 2 の ruleset の役目）。

## 提案 5: 手元の道具

- Windows のテスト（`net8.0`）を Mac で走らせるには .NET 8 のランタイムが要る（`brew install dotnet@8`）。新しい SDK だけでも `DOTNET_ROLL_FORWARD=Major` で動く。WPF（`Hanasu.Windows`）は Mac ではビルドできないので、CI に任せる。
- `actionlint`（`brew install actionlint`）があると、ワークフローを触った PR を手元で検査できる。

## 優先の順

1. 提案 1（Mac の CI）— 今いちばん大きい穴（Mac 版のコンパイルエラーと最適化ビルドの失敗が PR で見つからない）を塞ぐ。
2. 提案 3 → 提案 2（ruleset）— チェックを必須にし、「最新の `main` で通ったこと」を GitHub に守らせる。
3. 提案 4（フック）— エージェントの手順の飛ばしを止める。

## 出典

- マージキューが使えるのは組織のリポジトリ: [GitHub の発表（2023-07-12）](https://github.blog/changelog/2023-07-12-pull-request-merge-queue-is-now-generally-available/)
- `paths` で飛ばされた必須のチェックは「待機中」のまま・ジョブの `if:` で飛ばすと「成功」: [Troubleshooting required status checks](https://docs.github.com/en/enterprise-server@3.7/pull-requests/collaborating-with-pull-requests/collaborating-on-repositories-with-code-quality-features/troubleshooting-required-status-checks)
- `gh pr merge --match-head-commit`: [gh pr merge のマニュアル](https://cli.github.com/manual/gh_pr_merge)
