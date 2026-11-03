#!/usr/bin/env python3
"""spec（要件・設計判断）とコードのタグを突き合わせる。python3 の標準ライブラリだけで動く。

    python3 scripts/check-spec.py            # すべて表示する
    python3 scripts/check-spec.py --summary  # エラーと集計だけを表示する

決まりは docs/README.md。エラーがあれば終了コード 1 を返す。
"""

from __future__ import annotations

import argparse
import re
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

# タグを探すファイル（コード）
CODE_SUFFIXES = {".swift", ".cs", ".xaml", ".sh", ".ps1", ".yml", ".yaml", ".py"}
SKIP_DIRS = {".git", ".build", "build", "docs", "node_modules", "bin", "obj", ".swiftpm"}
SELF = Path(__file__).resolve()
# 「タグのないファイル」を数える場所（アプリのコード）
APP_CODE_DIRS = [("Sources/Hanasu", {".swift"}), ("windows", {".cs", ".xaml"})]

# 文書の中の ID とリンクを確かめるファイル
DOC_GLOBS = ["docs/**/*.md", "README.md", "CLAUDE.md"]

ID_RE = r"(?:REQ|DEC)-[A-Z]+-\d{3}"
HEADING_RE = re.compile(r"^###\s+((REQ|DEC)-([A-Z]+)-(\d+))\b\s*(.*)$")
ANY_HEADING_RE = re.compile(r"^#{1,3}\s")
FIELD_RE = re.compile(r"^-\s+([^:：]+?)\s*[:：]\s*(.*)$")
TAG_RE = re.compile(
    r"(?://|#|<!--|\*)\s*(要件|設計判断)\s*[:：]\s*("
    + ID_RE
    + r"(?:\s*[,、]\s*"
    + ID_RE
    + r")*)"
)
DOC_ID_RE = re.compile(r"\b(" + ID_RE + r"|FUT-\d{3})\b")
FUT_HEADING_RE = re.compile(r"^###\s+(FUT-\d{3})\b")
LINK_RE = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")
TARGETS = ("Mac", "Windows")


@dataclass
class Item:
    id: str
    kind: str  # REQ / DEC
    domain: str
    title: str
    file: Path
    line: int
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


def rel(path: Path) -> str:
    return str(path.relative_to(ROOT))


def parse_spec(errors: list[str]) -> dict[str, Item]:
    items: dict[str, Item] = {}
    for path in sorted(SPEC_DIR.glob("*.md")):
        current: Item | None = None
        in_code = False
        for no, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            line = raw.rstrip()
            if line.startswith("```"):
                in_code = not in_code
                continue
            if in_code:
                continue
            m = HEADING_RE.match(line)
            if m:
                item_id, kind, domain, number, title = m.groups()
                where = f"{rel(path)}:{no}"
                if len(number) != 3:
                    errors.append(f"{where}: ID の番号は 3 桁にする: {item_id}")
                if domain not in DOMAINS:
                    errors.append(f"{where}: 知らない領域 {domain}（{item_id}）。docs/README.md と DOMAINS に足す")
                if item_id in items:
                    first = items[item_id]
                    errors.append(f"{where}: ID が重複している: {item_id}（先は {rel(first.file)}:{first.line}）")
                current = Item(item_id, kind, domain, title.strip(), path, no)
                items.setdefault(item_id, current)
                continue
            if ANY_HEADING_RE.match(line):
                current = None
                continue
            if current is not None:
                f = FIELD_RE.match(line)
                if f:
                    key, value = f.group(1).strip(), f.group(2).strip()
                    current.fields.setdefault(key, value)
    for item in items.values():
        where = f"{rel(item.file)}:{item.line}"
        missing = [k for k in REQUIRED[item.kind] if k not in item.fields]
        if missing and not item.retired:
            errors.append(f"{where}: {item.id} に必須の項目がない: {', '.join(missing)}")
        target = item.fields.get("対象", "")
        if target and not any(t in target for t in TARGETS):
            errors.append(f"{where}: {item.id} の「対象」に Mac / Windows がない: {target}")
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


def code_files() -> list[Path]:
    files = []
    for path in ROOT.rglob("*"):
        if not path.is_file() or path.resolve() == SELF:
            continue
        parts = set(path.relative_to(ROOT).parts[:-1])
        if parts & SKIP_DIRS:
            continue
        if path.suffix in CODE_SUFFIXES or path.name == ".tagpr":
            files.append(path)
    return sorted(files)


def scan_tags(items: dict[str, Item], errors: list[str]):
    tags: dict[str, list[str]] = defaultdict(list)  # ID → 場所
    per_file: Counter[str] = Counter()
    for path in code_files():
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        for no, line in enumerate(text.splitlines(), 1):
            for m in TAG_RE.finditer(line):
                label, ids = m.group(1), re.findall(ID_RE, m.group(2))
                for tag_id in ids:
                    where = f"{rel(path)}:{no}"
                    item = items.get(tag_id)
                    if item is None:
                        errors.append(f"{where}: タグが、ない ID を指している: {tag_id}")
                        continue
                    if item.retired:
                        errors.append(f"{where}: タグが、廃止した ID を指している: {tag_id}")
                    expected = "要件" if item.kind == "REQ" else "設計判断"
                    if label != expected:
                        errors.append(f"{where}: {tag_id} は「{expected}」のタグに書く（「{label}」に書いてある）")
                    tags[tag_id].append(where)
                    per_file[rel(path)] += 1
    return tags, per_file


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
            if line.lstrip().startswith("```"):
                in_code = not in_code
            for ref in DOC_ID_RE.findall(line):
                if ref not in known:
                    errors.append(f"{rel(path)}:{no}: 文書の中の ID {ref} がどこにも定義されていない")
            if in_code:
                continue
            for target in LINK_RE.findall(line):
                if re.match(r"^[a-z]+:", target) or target.startswith("#"):
                    continue
                dest = (path.parent / target.split("#", 1)[0]).resolve()
                if not dest.exists():
                    errors.append(f"{rel(path)}:{no}: リンク先がない: {target}")
    return futs


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--summary", action="store_true", help="エラーと集計だけを表示する")
    args = parser.parse_args()

    errors: list[str] = []
    items = parse_spec(errors)
    tags, per_file = scan_tags(items, errors)
    futs = check_docs(items, errors)

    live = [i for i in items.values() if not i.retired]
    reqs = [i for i in live if i.kind == "REQ"]
    decs = [i for i in live if i.kind == "DEC"]
    for item in reqs:
        if not tags.get(item.id) and not item.tag_exempt:
            errors.append(f"{rel(item.file)}:{item.line}: 要件 {item.id} にコードのタグが 1 つもない（「コードのタグ: 不要（理由）」がなければ、決めている場所に付ける）")
    untagged_decs = [i for i in decs if not tags.get(i.id)]
    exempt_reqs = [i for i in reqs if i.tag_exempt and not tags.get(i.id)]
    pending = [i for i in live if i.pending]

    # アプリのコードのうち、タグのないファイル
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
    print(f"  合計: 要件 {len(reqs)}、設計判断 {len(decs)}、計画（FUT）{len(futs)}")
    print(f"  コードのタグ: {sum(per_file.values())} 個（{len(per_file)} ファイル）")
    print(f"  タグのある要件: {sum(1 for i in reqs if tags.get(i.id))} / {len(reqs)}"
          f"（タグが不要な要件 {len(exempt_reqs)}）")
    print(f"  タグのある設計判断: {len(decs) - len(untagged_decs)} / {len(decs)}")
    print(f"  タグのないアプリのファイル: {len(untagged_files)} / {len(app_files)}")
    print(f"  食い違い（ユーザーの確認待ち）: {len(pending)}")

    if not args.summary:
        print("\n== 食い違い（ユーザーの確認待ち）")
        for i in pending:
            print(f"  {i.id} {i.title}")
        print("\n== タグのない設計判断（報告だけ）")
        for i in untagged_decs:
            print(f"  {i.id} {i.title}")
        print("\n== タグが不要とした要件")
        for i in exempt_reqs:
            print(f"  {i.id} {i.title}（{i.fields.get('コードのタグ')}）")
        print("\n== ファイルごとのタグの数")
        for name, count in sorted(per_file.items(), key=lambda kv: (-kv[1], kv[0])):
            print(f"  {count:4d}  {name}")
        print("\n== タグのないアプリのファイル（暗黙の振る舞いが多い場所の目安）")
        for p in untagged_files:
            print(f"  {rel(p)}")

    if errors:
        print(f"\n== エラー（{len(errors)} 件）")
        for e in errors:
            print(f"  {e}")
        return 1
    print("\nエラーはありません。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
