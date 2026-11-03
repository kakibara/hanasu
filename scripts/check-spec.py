#!/usr/bin/env python3
"""spec（要件・設計判断）とコードのタグを突き合わせる。python3 の標準ライブラリだけで動く。

    python3 scripts/check-spec.py                     # すべて表示する
    python3 scripts/check-spec.py --summary           # エラーと集計だけを表示する
    python3 scripts/check-spec.py --diff origin/main  # PR 用: この差分が触った要件・設計判断と、spec を直したかを見る

--diff では、PR の本文を環境変数 PR_BODY（か --pr-body-file）で渡せる。本文かコミットメッセージに
「Spec-Impact: なし（理由）」と書けば、spec を直さなくても通す。

決まりは docs/README.md。エラーがあれば終了コード 1 を返す。
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SPEC_DIR = ROOT / "docs" / "spec"
ROADMAP = ROOT / "docs" / "roadmap.md"

# 領域。足すときは docs/README.md の「ID の付け方」も直す
DOMAINS = {
    "DIC": "音声入力",
    "MTG": "会議の記録",
    "COM": "設定・認証・共通",
    "REL": "配布・リリース",
}

REQUIRED = {
    "REQ": ["内容", "受け入れ条件", "出典", "対象", "実装の場所", "確かめ方"],
    "DEC": ["決めたこと", "理由", "決めた場面", "関係する要件", "対象"],
}
RETIRED_SECTION = "廃止"

# タグを探すファイル（コード）
CODE_SUFFIXES = {".swift", ".cs", ".xaml", ".csproj", ".props", ".sh", ".ps1", ".yml", ".yaml", ".py"}
CODE_NAMES = {".tagpr"}
SKIP_DIRS = {".git", ".build", "build", "docs", "node_modules", "bin", "obj", ".swiftpm", "publish"}
SELF = Path(__file__).resolve()
# 「タグのないファイル」を数える場所（アプリのコード）
APP_CODE_DIRS = [("Sources/Hanasu", {".swift"}), ("windows", {".cs", ".xaml"})]

# 文書の中の ID・リンク・ファイル名を確かめるファイル
DOC_GLOBS = ["docs/**/*.md", "README.md", "CLAUDE.md", ".github/pull_request_template.md"]
# 文書が名前を挙げるソースのファイル（あるかを確かめる）
PATH_PREFIXES = ("Sources/", "windows/")

ID_RE = r"(?:REQ|DEC)-[A-Z]+-\d{3}"
HEADING_RE = re.compile(r"^###\s+((REQ|DEC)-([A-Z]+)-(\d+))\b\s*(.*)$")
SECTION_RE = re.compile(r"^##\s+(.*)$")
ANY_HEADING_RE = re.compile(r"^#{1,3}\s")
FIELD_RE = re.compile(r"^-\s+([^:：]+?)\s*[:：]\s*(.*)$")
TAG_RE = re.compile(
    r"(?://|#|<!--|\*)\s*(要件|設計判断|確かめ方)\s*[:：]\s*("
    + ID_RE
    + r"(?:\s*[,、]\s*"
    + ID_RE
    + r")*)"
)
DOC_ID_RE = re.compile(r"\b(" + ID_RE + r"|FUT-\d{3})\b")
FUT_HEADING_RE = re.compile(r"^###\s+(FUT-\d{3})\b")
LINK_RE = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")
CODE_SPAN_RE = re.compile(r"`([^`\s]+)`")
SPEC_IMPACT_RE = re.compile(r"(?m)^\s*Spec-Impact\s*[:：]\s*なし\s*[（(].+?[）)]")
HTML_COMMENT_RE = re.compile(r"<!--.*?-->", re.S)
TARGETS = ("Mac", "Windows")


@dataclass
class Item:
    id: str
    kind: str  # REQ / DEC
    domain: str
    title: str
    file: Path
    line: int
    section: str
    fields: dict[str, str] = field(default_factory=dict)

    @property
    def retired(self) -> bool:
        return self.fields.get("状態", "").startswith("廃止")

    @property
    def tag_exempt(self) -> bool:
        return self.fields.get("コードのタグ", "").startswith("不要")

    @property
    def pending(self) -> str | None:
        return self.fields.get("食い違い（ユーザーの確認待ち）")

    @property
    def windows_only(self) -> bool:
        target = self.fields.get("対象", "")
        return "Windows" in target and "Mac" not in target


def rel(path: Path) -> str:
    return str(path.relative_to(ROOT))


def git(*args: str) -> str:
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True, check=True).stdout


# ---------------------------------------------------------------- spec


def parse_spec_text(text: str, path: Path, errors: list[str] | None, items: dict[str, Item]) -> None:
    current: Item | None = None
    section = ""
    in_code = False
    for no, raw in enumerate(text.splitlines(), 1):
        line = raw.rstrip()
        if line.startswith("```"):
            in_code = not in_code
            continue
        if in_code:
            continue
        s = SECTION_RE.match(line)
        if s:
            section = s.group(1).strip()
            current = None
            continue
        m = HEADING_RE.match(line)
        if m:
            item_id, kind, domain, number, title = m.groups()
            where = f"{rel(path)}:{no}"
            if errors is not None:
                if len(number) != 3:
                    errors.append(f"{where}: ID の番号は 3 桁にする: {item_id}")
                if domain not in DOMAINS:
                    errors.append(f"{where}: 知らない領域 {domain}（{item_id}）。docs/README.md と DOMAINS に足す")
                if item_id in items:
                    first = items[item_id]
                    errors.append(f"{where}: ID が重複している: {item_id}（先は {rel(first.file)}:{first.line}）")
            current = Item(item_id, kind, domain, title.strip(), path, no, section)
            items.setdefault(item_id, current)
            continue
        if ANY_HEADING_RE.match(line):
            current = None
            continue
        if current is not None:
            f = FIELD_RE.match(line)
            if f:
                current.fields.setdefault(f.group(1).strip(), f.group(2).strip())


def parse_spec(errors: list[str]) -> dict[str, Item]:
    items: dict[str, Item] = {}
    for path in sorted(SPEC_DIR.glob("*.md")):
        parse_spec_text(path.read_text(encoding="utf-8"), path, errors, items)
    for item in items.values():
        where = f"{rel(item.file)}:{item.line}"
        missing = [k for k in REQUIRED[item.kind] if k not in item.fields]
        if missing and not item.retired:
            errors.append(f"{where}: {item.id} に必須の項目がない: {', '.join(missing)}")
        target = item.fields.get("対象", "")
        if target and not any(t in target for t in TARGETS):
            errors.append(f"{where}: {item.id} の「対象」に Mac / Windows がない: {target}")
        in_retired = item.section.startswith(RETIRED_SECTION)
        if item.retired and not in_retired:
            errors.append(f"{where}: {item.id} は廃止なので「## {RETIRED_SECTION}」の節に移す")
        if in_retired and not item.retired:
            errors.append(f"{where}: {item.id} は「## {RETIRED_SECTION}」の節にあるのに「状態: 廃止（日付・理由・PR）」がない")
    for item in items.values():
        if item.kind != "DEC":
            continue
        for ref in re.findall(ID_RE, item.fields.get("関係する要件", "")):
            target_item = items.get(ref)
            if target_item is None:
                errors.append(f"{rel(item.file)}:{item.line}: {item.id} の「関係する要件」{ref} がない")
            elif target_item.kind != "REQ":
                errors.append(f"{rel(item.file)}:{item.line}: {item.id} の「関係する要件」{ref} は要件ではない")
    return items


# ---------------------------------------------------------------- コードのタグ


def is_code_file(path: Path) -> bool:
    parts = set(path.parts[:-1])
    if parts & SKIP_DIRS:
        return False
    return path.suffix in CODE_SUFFIXES or path.name in CODE_NAMES


def code_files() -> list[Path]:
    files = []
    for path in ROOT.rglob("*"):
        if path.is_file() and path.resolve() != SELF and is_code_file(path.relative_to(ROOT)):
            files.append(path)
    return sorted(files)


def tags_in_line(line: str) -> list[tuple[str, str]]:
    """(ラベル, ID) の一覧"""
    return [(m.group(1), i) for m in TAG_RE.finditer(line) for i in re.findall(ID_RE, m.group(2))]


def scan_tags(items: dict[str, Item], errors: list[str]):
    tags: dict[str, list[str]] = defaultdict(list)  # ID → 場所（要件・設計判断のタグ）
    checks: dict[str, list[str]] = defaultdict(list)  # ID → 場所（確かめ方のタグ）
    per_file: Counter[str] = Counter()
    for path in code_files():
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        for no, line in enumerate(text.splitlines(), 1):
            for label, tag_id in tags_in_line(line):
                where = f"{rel(path)}:{no}"
                item = items.get(tag_id)
                if item is None:
                    errors.append(f"{where}: タグが、ない ID を指している: {tag_id}")
                    continue
                if item.retired:
                    errors.append(f"{where}: タグが、廃止した ID を指している: {tag_id}")
                if label == "確かめ方":
                    if item.kind != "REQ":
                        errors.append(f"{where}: 「確かめ方」のタグには要件だけを書く（{tag_id}）")
                    checks[tag_id].append(where)
                    continue
                expected = "要件" if item.kind == "REQ" else "設計判断"
                if label != expected:
                    errors.append(f"{where}: {tag_id} は「{expected}」のタグに書く（「{label}」に書いてある）")
                tags[tag_id].append(where)
                per_file[rel(path)] += 1
    return tags, checks, per_file


# ---------------------------------------------------------------- 文書


def check_docs(items: dict[str, Item], errors: list[str]) -> set[str]:
    futs: set[str] = set()
    if ROADMAP.exists():
        for no, line in enumerate(ROADMAP.read_text(encoding="utf-8").splitlines(), 1):
            m = FUT_HEADING_RE.match(line)
            if m:
                if m.group(1) in futs:
                    errors.append(f"{rel(ROADMAP)}:{no}: FUT の ID が重複している: {m.group(1)}")
                futs.add(m.group(1))
    known = set(items) | futs
    docs = sorted({p for g in DOC_GLOBS for p in ROOT.glob(g) if p.is_file()})
    for path in docs:
        in_code = False
        for no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            where = f"{rel(path)}:{no}"
            if line.lstrip().startswith("```"):
                in_code = not in_code
            for ref in DOC_ID_RE.findall(line):
                if ref not in known:
                    errors.append(f"{where}: 文書の中の ID {ref} がどこにも定義されていない")
            if in_code:
                continue
            for target in LINK_RE.findall(line):
                if re.match(r"^[a-z]+:", target) or target.startswith("#"):
                    continue
                dest = (path.parent / target.split("#", 1)[0]).resolve()
                if not dest.exists():
                    errors.append(f"{where}: リンク先がない: {target}")
            # spec・design が名前を挙げるソースのファイル
            for span in CODE_SPAN_RE.findall(line):
                span = span.rstrip("、。,.:：）)")
                if not span.startswith(PATH_PREFIXES) or re.search(r"[<>*{}…]", span):
                    continue
                if not (ROOT / span).exists():
                    errors.append(f"{where}: 名前を挙げたファイルがない: {span}")
    return futs


# ---------------------------------------------------------------- --diff


@dataclass
class FileDiff:
    path: str
    status: str = "M"
    added: list[int] = field(default_factory=list)  # 新しい側の行番号
    anchors: list[int] = field(default_factory=list)  # 消した行のある場所（新しい側の行番号）
    removed_tags: list[str] = field(default_factory=list)


def parse_diff(base: str) -> dict[str, FileDiff]:
    files: dict[str, FileDiff] = {}
    for row in git("diff", "--name-status", "--no-renames", f"{base}...HEAD").splitlines():
        status, _, name = row.partition("\t")
        files[name] = FileDiff(name, status[:1])
    current: FileDiff | None = None
    new_no = 0
    for line in git("diff", "-U0", "--no-color", "--no-renames", f"{base}...HEAD").splitlines():
        if line.startswith("diff --git"):
            current = None
            continue
        if line.startswith("--- "):
            if line != "--- /dev/null":
                name = line[6:]
                current = files.setdefault(name, FileDiff(name))
            continue
        if line.startswith("+++ "):
            if line != "+++ /dev/null":
                name = line[6:]
                current = files.setdefault(name, FileDiff(name))
            continue
        m = re.match(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@", line)
        if m:
            new_no = int(m.group(1))
            if m.group(2) == "0":  # 消しただけの hunk は、その後ろの行を目印にする
                new_no += 1
            continue
        if current is None:
            continue
        if line.startswith("+"):
            current.added.append(new_no)
            new_no += 1
        elif line.startswith("-"):
            current.anchors.append(new_no)
            current.removed_tags += [i for _, i in tags_in_line(line[1:])]
    return files


def indent_of(line: str) -> int:
    return len(line) - len(line.lstrip())


def enclosing_tags(lines: list[str], index: int) -> list[str]:
    """変わった行を含む宣言の直前にあるタグ（近似）。

    変わった行から上へ、インデントがより浅い行（宣言の書き出しの候補）をたどり、
    その直前に続くコメントの中にタグがあれば返す。なければさらに外側を見る。
    """
    if not lines:
        return []
    index = min(max(index, 0), len(lines) - 1)

    def tags_above(i: int) -> list[str]:
        found = []
        j = i - 1
        while j >= 0:
            s = lines[j].strip()
            if s.startswith(("//", "#", "///", "@", "[", "*", "/*")):
                found += [tag_id for label, tag_id in tags_in_line(lines[j]) if label != "確かめ方"]
                j -= 1
                continue
            break
        return found

    # 変わった行そのものがタグか宣言のとき
    direct = [i for label, i in tags_in_line(lines[index]) if label != "確かめ方"]
    if direct:
        return direct
    found = tags_above(index)
    if found:
        return found
    threshold = indent_of(lines[index]) if lines[index].strip() else 10**6
    for i in range(index - 1, -1, -1):
        if not lines[i].strip():
            continue
        level = indent_of(lines[i])
        if level < threshold:
            found = tags_above(i)
            if found:
                return found
            threshold = level
            if level == 0:
                break
    return []


def run_diff(base: str, items: dict[str, Item], tags: dict[str, list[str]], pr_body: str,
             errors: list[str], warnings: list[str]) -> None:
    files = parse_diff(base)
    touched: dict[str, set[str]] = defaultdict(set)  # ID → ファイル
    for name, d in files.items():
        if not is_code_file(Path(name)) or Path(name).resolve() == SELF:
            continue
        for tag_id in d.removed_tags:
            touched[tag_id].add(name)
        path = ROOT / name
        if d.status == "D" or not path.exists():
            continue
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        for no in d.added + d.anchors:
            for tag_id in enclosing_tags(lines, no - 1):
                touched[tag_id].add(name)
        # 新しく足したアプリのファイルにタグがない
        if d.status == "A" and any(name.startswith(dir_ + "/") and Path(name).suffix in suf
                                   for dir_, suf in APP_CODE_DIRS):
            if not any(tags_in_line(line) for line in lines):
                warnings.append(f"{name}: 新しく足したファイルにタグが 1 つもない（暗黙の振る舞いが増えたかもしれない）")

    spec_changed = any(name.startswith("docs/spec/") for name in files)
    print(f"\n== この差分が触った要件・設計判断（{base}...HEAD）")
    if not touched:
        print("  なし")
    for tag_id in sorted(touched):
        item = items.get(tag_id)
        title = item.title if item else "（spec にない ID）"
        print(f"  {tag_id} {title}  ← {', '.join(sorted(touched[tag_id]))}")
    print(f"  docs/spec の変更: {'あり' if spec_changed else 'なし'}")

    if touched and not spec_changed:
        messages = git("log", "--format=%B", f"{base}..HEAD")
        body = HTML_COMMENT_RE.sub("", pr_body or "")  # テンプレートの例（コメントの中）は数えない
        impact = SPEC_IMPACT_RE.search(body) or SPEC_IMPACT_RE.search(messages)
        if impact:
            print(f"  spec を直さない理由: {impact.group(0)}")
        else:
            errors.append(
                "要件・設計判断のタグのあるコードを変えたのに docs/spec/ を直していない。"
                "spec を直すか、PR の本文かコミットメッセージに「Spec-Impact: なし（理由）」と書く: "
                + ", ".join(sorted(touched)))

    # タグを消したのに、spec に残っている
    for tag_id in sorted({i for d in files.values() for i in d.removed_tags}):
        item = items.get(tag_id)
        if item and not item.retired and not tags.get(tag_id) and not item.tag_exempt:
            warnings.append(f"{tag_id}: コードのタグを消したのに、spec に残っている（機能をなくしたなら「## {RETIRED_SECTION}」に移す）")

    # spec の項目を消した（廃止に移していない）
    try:
        base_files = git("ls-tree", "--name-only", base, "docs/spec/").split()
    except subprocess.CalledProcessError:
        base_files = []
    base_items: dict[str, Item] = {}
    for name in base_files:
        if name.endswith(".md"):
            parse_spec_text(git("show", f"{base}:{name}"), ROOT / name, None, base_items)
    for tag_id in sorted(set(base_items) - set(items)):
        warnings.append(f"{tag_id}: spec から項目を消している。消さずに「## {RETIRED_SECTION}」の節へ移し、日付・理由・PR を書く")


# ---------------------------------------------------------------- main


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--summary", action="store_true", help="エラーと集計だけを表示する")
    parser.add_argument("--diff", metavar="BASE", help="BASE...HEAD の差分が触った要件・設計判断を調べる（PR 用）")
    parser.add_argument("--pr-body-file", metavar="FILE", help="PR の本文（Spec-Impact を探す）。なければ環境変数 PR_BODY")
    args = parser.parse_args()

    errors: list[str] = []
    warnings: list[str] = []
    items = parse_spec(errors)
    tags, checks, per_file = scan_tags(items, errors)
    futs = check_docs(items, errors)

    live = [i for i in items.values() if not i.retired]
    reqs = [i for i in live if i.kind == "REQ"]
    decs = [i for i in live if i.kind == "DEC"]
    untagged_windows_reqs = []
    for item in reqs:
        if tags.get(item.id) or item.tag_exempt:
            continue
        if item.windows_only:
            # windows/ のタグ付けはまだなので、報告だけにする（docs/roadmap.md FUT-002）
            untagged_windows_reqs.append(item)
            continue
        errors.append(f"{rel(item.file)}:{item.line}: 要件 {item.id} にコードのタグが 1 つもない（「コードのタグ: 不要（理由）」がなければ、決めている場所に付ける）")
    untagged_decs = [i for i in decs if not tags.get(i.id)]
    exempt_reqs = [i for i in reqs if i.tag_exempt and not tags.get(i.id)]
    pending = [i for i in live if i.pending]
    manual_only = [i for i in reqs if "`" not in i.fields.get("確かめ方", "")]
    unlinked_checks = [i for i in reqs if "`" in i.fields.get("確かめ方", "") and not checks.get(i.id)]
    retired = [i for i in items.values() if i.retired]

    app_files: list[Path] = []
    for directory, suffixes in APP_CODE_DIRS:
        base = ROOT / directory
        if base.exists():
            app_files += sorted(p for p in base.rglob("*") if p.is_file() and p.suffix in suffixes
                                and not (set(p.relative_to(ROOT).parts) & SKIP_DIRS))
    untagged_files = [p for p in app_files if per_file[rel(p)] == 0]

    print("== 集計")
    by_domain = Counter((i.domain, i.kind) for i in live)
    for domain, name in DOMAINS.items():
        print(f"  {domain}（{name}）: 要件 {by_domain[(domain, 'REQ')]}、設計判断 {by_domain[(domain, 'DEC')]}")
    print(f"  合計: 要件 {len(reqs)}、設計判断 {len(decs)}、廃止 {len(retired)}、計画（FUT）{len(futs)}")
    print(f"  コードのタグ: {sum(per_file.values())} 個（{len(per_file)} ファイル）、確かめ方のタグ: {sum(len(v) for v in checks.values())} 個")
    print(f"  タグのある要件: {sum(1 for i in reqs if tags.get(i.id))} / {len(reqs)}"
          f"（タグが不要な要件 {len(exempt_reqs)}、Windows だけでタグがまだない要件 {len(untagged_windows_reqs)}）")
    print(f"  タグのある設計判断: {len(decs) - len(untagged_decs)} / {len(decs)}")
    print(f"  タグのないアプリのファイル: {len(untagged_files)} / {len(app_files)}")
    print(f"  確かめ方が実機だけの要件: {len(manual_only)}、確かめ方のコードに ID がない要件: {len(unlinked_checks)}")
    print(f"  食い違い（ユーザーの確認待ち）: {len(pending)}")

    if not args.summary:
        def section(title: str, rows: list[str]) -> None:
            print(f"\n== {title}")
            for row in rows or ["なし"]:
                print(f"  {row}")
        section("食い違い（ユーザーの確認待ち）", [f"{i.id} {i.title}" for i in pending])
        section("Windows だけの要件で、タグがまだないもの（報告だけ。FUT-002）", [f"{i.id} {i.title}" for i in untagged_windows_reqs])
        section("タグのない設計判断（報告だけ）", [f"{i.id} {i.title}" for i in untagged_decs])
        section("タグが不要とした要件", [f"{i.id} {i.title}（{i.fields.get('コードのタグ')}）" for i in exempt_reqs])
        section("確かめ方が実機だけの要件（CLI・テストがない）", [f"{i.id} {i.title}" for i in manual_only])
        section("確かめ方の CLI・テストに `// 確かめ方:` の ID がない要件", [f"{i.id} {i.title}" for i in unlinked_checks])
        section("ファイルごとのタグの数", [f"{c:4d}  {n}" for n, c in sorted(per_file.items(), key=lambda kv: (-kv[1], kv[0]))])
        section("タグのないアプリのファイル（暗黙の振る舞いが多い場所の目安）", [rel(p) for p in untagged_files])

    if args.diff:
        pr_body = os.environ.get("PR_BODY", "")
        if args.pr_body_file:
            pr_body = Path(args.pr_body_file).read_text(encoding="utf-8")
        run_diff(args.diff, items, tags, pr_body, errors, warnings)

    if warnings:
        print(f"\n== 警告（{len(warnings)} 件）")
        for w in warnings:
            print(f"  {w}")
    if errors:
        print(f"\n== エラー（{len(errors)} 件）")
        for e in errors:
            print(f"  {e}")
        return 1
    print("\nエラーはありません。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
