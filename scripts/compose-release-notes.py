#!/usr/bin/env python3
"""リリースの本文を組み立てる（.github/workflows/tagpr.yml の publish ジョブで使う）。

  python3 scripts/compose-release-notes.py --body body.md --install install.md [--notes docs/releases/v1.4.0.md]
  python3 scripts/compose-release-notes.py --self-test

本文は次の順にする:
  1. リリース文（docs/releases/<タグ>.md。あれば。印 <!-- release-notes --> で囲む）
  2. tagpr が作った PR の一覧（「## What's Changed」と Full Changelog）
  3. インストールの手順と SHA-256（publish ジョブが作る。「## インストール」から）

作り直したとき（Actions の手動の実行）に二重にならないよう、前の本文から
印で囲んだリリース文と「## インストール」から後ろを除いてから組み立てる。
"""
# 要件: REQ-REL-006
# 設計判断: DEC-REL-005, DEC-REL-010
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

START = "<!-- release-notes -->"
END = "<!-- /release-notes -->"
INSTALL_HEADING = "## インストール"


def strip_previous(body: str) -> str:
    """前に付けたリリース文（印で囲んだ部分）と、「## インストール」から後ろを除く"""
    body = re.sub(re.escape(START) + r".*?" + re.escape(END), "", body, flags=re.S)
    lines = []
    for line in body.splitlines():
        if line.strip() == INSTALL_HEADING:
            break
        lines.append(line)
    return "\n".join(lines).strip()


def clean_notes(notes: str) -> str:
    """リリース文の中身。テンプレートの説明（HTML のコメント）と、中身のない見出しを除く"""
    notes = notes.replace(START, "").replace(END, "")
    notes = re.sub(r"<!--.*?-->", "", notes, flags=re.S)
    sections: list[list[str]] = [[]]
    for line in notes.splitlines():
        if line.startswith("## "):
            sections.append([])
        sections[-1].append(line.rstrip())
    kept = []
    for section in sections:
        body = [l for l in section[1:] if l.strip()] if section and section[0].startswith("## ") else section
        if section and section[0].startswith("## ") and not body:
            continue  # 見出しだけ（テンプレートのまま使わなかった節）
        kept.append("\n".join(section).strip())
    text = "\n\n".join(s for s in kept if s)
    return re.sub(r"\n{3,}", "\n\n", text).strip()


def compose(body: str, install: str, notes: str | None) -> str:
    parts = []
    if notes is not None and clean_notes(notes):
        parts.append(f"{START}\n{clean_notes(notes)}\n{END}")
    previous = strip_previous(body)
    if previous:
        parts.append(previous)
    parts.append(install.strip())
    return "\n\n".join(parts) + "\n"


def self_test() -> bool:
    install = "## インストール\n\n### macOS\n\n1. 展開する"
    auto = "<!-- Release notes generated -->\n\n## What's Changed\n* 機能 by @a in #1\n\n**Full Changelog**: v1...v2"
    notes = "<!-- テンプレートの説明 -->\n## ハイライト\n\n話者の名前を推測します。\n\n## 改善\n\n<!-- なければ消す -->\n\n## 不具合の修正\n\n- 直した\n"
    results = []

    def check(name: str, ok: bool) -> None:
        results.append((name, ok))

    first = compose(auto, install, notes)
    check("リリース文が先頭に、印で囲んで入る", first.startswith(START + "\n## ハイライト\n\n話者の名前を推測します。"))
    check("中身のない見出しとテンプレートの説明は消える", "## 改善" not in first and "テンプレート" not in first)
    check("PR の一覧はリリース文のあと", first.index(END) < first.index("## What's Changed"))
    check("インストールは最後", first.rstrip().endswith("1. 展開する"))
    again = compose(first, install, notes)
    check("作り直しても二重にならない", again == first)
    without = compose(auto, install, None)
    check("リリース文がなければ今までどおり", without.startswith("<!-- Release notes generated -->") and START not in without)
    check("リリース文を外して作り直すと消える", compose(first, install, None) == without)
    for name, ok in results:
        print(f"{'OK' if ok else 'NG'}  {name}")
    return all(ok for _, ok in results)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--body", type=Path, help="今のリリースの本文")
    parser.add_argument("--install", type=Path, help="インストールの手順と SHA-256")
    parser.add_argument("--notes", type=Path, help="リリース文（docs/releases/<タグ>.md）")
    parser.add_argument("--self-test", action="store_true", help="組み立て方を確かめる")
    args = parser.parse_args()
    if args.self_test:
        return 0 if self_test() else 1
    if args.body is None or args.install is None:
        parser.error("--body と --install が要る")
    notes = args.notes.read_text(encoding="utf-8") if args.notes and args.notes.exists() else None
    sys.stdout.write(compose(args.body.read_text(encoding="utf-8"), args.install.read_text(encoding="utf-8"), notes))
    return 0


if __name__ == "__main__":
    sys.exit(main())
