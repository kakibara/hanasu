#!/usr/bin/env python3
"""Mac の UI の文字列（String Catalog）を扱う。手順は .claude/skills/i18n/SKILL.md。

  python3 scripts/i18n-strings.py sync                 Swift の tr("…") のキーを Localizable.xcstrings にそろえる
                                                       （新しいキーを足し、使っていないキーを消す）
  python3 scripts/i18n-strings.py export <言語>        その言語の訳がないキーを JSON（キー → ""）で標準出力に出す
  python3 scripts/i18n-strings.py export <言語> --all  訳のあるキーも含めて出す（キー → 今の訳）
  python3 scripts/i18n-strings.py import <言語> <JSON> JSON（キー → 訳）を取り込む
  python3 scripts/i18n-strings.py infoplist <Resources>  .app の Contents/Resources に、言語ごとの <言語>.lproj/InfoPlist.strings を書く
                                                       （権限を求めるときの説明。.lproj があることで AppKit も表示の言語を選べる）

キーは日本語の原文（ソースの言語は ja）。補間は %@（訳では %1$@ のように順番を変えてよい）。
python3 の標準ライブラリだけを使う。check-i18n.py もこのファイルの関数を使う。
"""
# 要件: REQ-COM-060, REQ-COM-062
# 設計判断: DEC-COM-165

from __future__ import annotations

import json
import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Sources/Hanasu"
CATALOG = SOURCES / "Resources/Localizable.xcstrings"
LANGUAGES = ["en", "ja", "zh-CN", "zh-TW", "ko", "es", "fr", "de", "it", "pt-BR", "ru", "tr", "vi", "id", "pl", "ar", "hi"]
SOURCE_LANGUAGE = "ja"

JA = re.compile(r"[ぁ-んァ-ヶ一-龯ー々〆〇]")
FORMAT = re.compile(r"%%|%(\d+\$)?([-+ 0#]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j)?[@dDuUxXoOfeEgGcCsSpaAF])")


def is_app_source(path: Path) -> bool:
    """訳す対象のソース（開発用の CLI と自己テストは訳さない）"""
    name = path.name
    return not (name.endswith("CLI.swift") or name.endswith("SelfTest.swift") or name == "main.swift")


def swift_files() -> list[Path]:
    return sorted(p for p in SOURCES.glob("*.swift") if is_app_source(p))


def unescape(body: str) -> str:
    out = []
    i = 0
    while i < len(body):
        c = body[i]
        if c == "\\" and i + 1 < len(body):
            n = body[i + 1]
            if n == "n":
                out.append("\n"); i += 2; continue
            if n == "t":
                out.append("\t"); i += 2; continue
            if n in "\"\\'":
                out.append(n); i += 2; continue
            if n == "0":
                out.append("\0"); i += 2; continue
            if n == "u" and body[i + 2:i + 3] == "{":
                end = body.index("}", i)
                out.append(chr(int(body[i + 3:end], 16))); i = end + 1; continue
            if n == "(":
                raise ValueError("tr のキーに補間 \\( がある（%@ と引数にする）")
        out.append(c)
        i += 1
    return "".join(out)


def multiline_value(raw: str) -> str:
    """\"\"\" の中身（最初の改行のあと〜最後の行の字下げ）を Swift と同じ規則で文字列にする"""
    lines = raw.split("\n")
    if lines and lines[0].strip() == "":
        lines = lines[1:]
    indent = lines[-1] if lines and lines[-1].strip() == "" else ""
    body = lines[:-1] if indent or (lines and lines[-1] == "") else lines
    text = "\n".join(l[len(indent):] if l.startswith(indent) else l for l in body)
    # 行末の \ は改行をつなぐ
    text = text.replace("\\\n", "")
    return unescape(text)


TR_CALL = re.compile(r"\btr\(\s*(\"\"\"|\")")


def extract_keys(path: Path) -> list[tuple[str, int]]:
    """ファイルの中の tr("…") のキーと行番号"""
    src = path.read_text(encoding="utf-8")
    keys = []
    for m in TR_CALL.finditer(src):
        line_start = src.rfind("\n", 0, m.start()) + 1
        if src[line_start:m.start()].lstrip().startswith("//"):
            continue
        quote = m.group(1)
        start = m.end()
        if quote == '"""':
            end = src.index('"""', start)
            key = multiline_value(src[start:end])
        else:
            j = start
            while src[j] != '"':
                j += 2 if src[j] == "\\" else 1
            key = unescape(src[start:j])
        keys.append((key, src.count("\n", 0, m.start()) + 1))
    return keys


INFO_PLIST = ROOT / "Resources/Info.plist"


def plist_texts() -> dict[str, str]:
    """Info.plist の、利用者に見せる文（権限を求めるときの説明）。キー → 日本語の文。
    scripts/build-app.sh が <言語>.lproj/InfoPlist.strings にする"""
    with INFO_PLIST.open("rb") as f:
        plist = plistlib.load(f)
    return {k: v for k, v in plist.items() if k.endswith("UsageDescription") and isinstance(v, str)}


def all_keys() -> dict[str, list[str]]:
    result: dict[str, list[str]] = {}
    for name, text in plist_texts().items():
        result.setdefault(text, []).append(f"Info.plist {name}")
    for path in swift_files():
        for key, line in extract_keys(path):
            result.setdefault(key, []).append(f"{path.name}:{line}")
    return result


def load_catalog() -> dict:
    if not CATALOG.exists():
        return {"sourceLanguage": SOURCE_LANGUAGE, "strings": {}, "version": "1.0"}
    return json.loads(CATALOG.read_text(encoding="utf-8"))


def save_catalog(catalog: dict) -> None:
    catalog["strings"] = dict(sorted(catalog["strings"].items()))
    text = json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True, separators=(",", " : "))
    CATALOG.write_text(text + "\n", encoding="utf-8")


def translation(entry: dict, language: str) -> str | None:
    unit = entry.get("localizations", {}).get(language, {}).get("stringUnit", {})
    value = unit.get("value")
    return value if value else None


def positional_ok(text: str) -> bool:
    """%1$@ のような番号付きの指定子を使うなら、すべてに番号を付け、1..n をちょうど 1 回ずつ使う"""
    specs = [m for m in FORMAT.finditer(text) if m.group(0) != "%%"]
    numbered = [m.group(1) for m in specs if m.group(1)]
    if not numbered:
        return True
    if len(numbered) != len(specs):
        return False
    return sorted(int(n[:-1]) for n in numbered) == list(range(1, len(specs) + 1))


def formats(text: str) -> list[str]:
    """書式の指定子（順番を変えた %1$@ は %@ と同じに数える）"""
    return sorted("%%" if m.group(0) == "%%" else "%" + m.group(2) for m in FORMAT.finditer(text))


def cmd_sync() -> int:
    keys = all_keys()
    catalog = load_catalog()
    strings = catalog.setdefault("strings", {})
    added = [k for k in keys if k not in strings]
    removed = [k for k in strings if k not in keys]
    for key in added:
        strings[key] = {"extractionState": "manual", "localizations": {}}
    for key in removed:
        del strings[key]
    for key, places in keys.items():
        strings[key]["comment"] = ", ".join(places[:3])
    save_catalog(catalog)
    print(f"{len(keys)} keys（足した {len(added)}、消した {len(removed)}）")
    return 0


def cmd_export(language: str, include_all: bool) -> int:
    catalog = load_catalog()
    out = {}
    for key, entry in catalog["strings"].items():
        value = translation(entry, language)
        if include_all or value is None:
            out[key] = value or ""
    json.dump(out, sys.stdout, ensure_ascii=False, indent=2)
    print()
    return 0


def cmd_import(language: str, path: str) -> int:
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    catalog = load_catalog()
    strings = catalog["strings"]
    count = 0
    problems = []
    for key, value in data.items():
        if key not in strings:
            problems.append(f"カタログにないキー: {key!r}")
            continue
        if not isinstance(value, str) or not value.strip():
            continue
        if formats(key) != formats(value) or not positional_ok(value):
            problems.append(f"%@ の数が合わない: {key!r} → {value!r}")
            continue
        strings[key].setdefault("localizations", {})[language] = {"stringUnit": {"state": "translated", "value": value}}
        count += 1
    save_catalog(catalog)
    for p in problems:
        print(f"skip: {p}", file=sys.stderr)
    print(f"{language}: {count} 件を取り込んだ（取り込まなかった {len(problems)} 件）")
    return 1 if problems else 0


# Apple の .lproj の名前（中国語は書き方の名前にする）
LPROJ = {"zh-CN": "zh-Hans", "zh-TW": "zh-Hant"}


def strings_escape(text: str) -> str:
    return text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def cmd_infoplist(resources: str) -> int:
    catalog = load_catalog()["strings"]
    texts = plist_texts()
    missing = []
    for language in LANGUAGES:
        lines = []
        for name, source in sorted(texts.items()):
            value = source if language == SOURCE_LANGUAGE else translation(catalog.get(source, {}), language)
            if value is None:
                missing.append(f"{language}: {name}")
                value = translation(catalog.get(source, {}), "en") or source
            lines.append(f'"{name}" = "{strings_escape(value)}";')
        folder = Path(resources) / f"{LPROJ.get(language, language)}.lproj"
        folder.mkdir(parents=True, exist_ok=True)
        (folder / "InfoPlist.strings").write_text("\n".join(lines) + "\n", encoding="utf-8")
    for m in missing:
        print(f"warning: 訳がない: {m}", file=sys.stderr)
    return 0


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__)
        return 2
    if argv[0] == "sync":
        return cmd_sync()
    if argv[0] == "export" and len(argv) >= 2:
        return cmd_export(argv[1], "--all" in argv)
    if argv[0] == "import" and len(argv) == 3:
        return cmd_import(argv[1], argv[2])
    if argv[0] == "infoplist" and len(argv) == 2:
        return cmd_infoplist(argv[1])
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
