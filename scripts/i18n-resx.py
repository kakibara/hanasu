#!/usr/bin/env python3
"""Windows 版の UI の文字列（.resx）の訳を出し入れし、漏れを確かめる。

windows/ の下の Strings.resx（ニュートラル = 英語）ごとに、言語ごとの Strings.<カルチャ>.resx を扱う。
使い方:
  python3 scripts/i18n-resx.py export <言語>          訳がない（か空の）名前を JSON で出す（{"<resx のパス>": {"名前": ""}}）
  python3 scripts/i18n-resx.py import <言語> <JSON>   export と同じ形の JSON の訳を Strings.<カルチャ>.resx に書く
  python3 scripts/i18n-resx.py check                  すべての言語に、すべての名前の訳があり、{0} などがそろっているか

<言語> は対応言語のコード（ja, zh-CN, zh-TW, ko, es, fr, de, it, pt-BR, ru, tr, vi, id, pl, ar, hi）。
中国語のファイルは zh-Hans・zh-Hant にする（.NET は zh-CN・zh-SG を zh-Hans、zh-TW・zh-HK・zh-MO を zh-Hant にたどるため）。
import は、{0} などの埋める場所が英語と違う値を受け付けない（そのときは何も書かずに終了コード 1）。空の値は訳がないものとして飛ばす
（空白だけの値は、区切りの文字として使えるので訳として扱う）。
標準ライブラリだけで動く。
"""

import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WINDOWS = ROOT / "windows"

# 要件: REQ-COM-060
# 英語（en）はニュートラル（Strings.resx）。並びは scripts/check-i18n.py の LANGUAGES と同じ（en を除く）
LANGUAGES = ["ja", "zh-CN", "zh-TW", "ko", "es", "fr", "de", "it", "pt-BR", "ru", "tr", "vi", "id", "pl", "ar", "hi"]
# ファイル名のカルチャ。中国語だけ、.NET のカルチャの親（zh-Hans・zh-Hant）にする
FILE_CULTURE = {"zh-CN": "zh-Hans", "zh-TW": "zh-Hant"}

PLACEHOLDER = re.compile(r"\{(\d+)(?:[,:][^{}]*)?\}")

HEADER = """<?xml version="1.0" encoding="utf-8"?>
<root>
  <resheader name="resmimetype">
    <value>text/microsoft-resx</value>
  </resheader>
  <resheader name="version">
    <value>2.0</value>
  </resheader>
  <resheader name="reader">
    <value>System.Resources.ResXResourceReader, System.Windows.Forms, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089</value>
  </resheader>
  <resheader name="writer">
    <value>System.Resources.ResXResourceWriter, System.Windows.Forms, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089</value>
  </resheader>
"""


def file_culture(lang: str) -> str:
    return FILE_CULTURE.get(lang, lang)


def neutral_files() -> list[Path]:
    """windows/ の下のニュートラルの Strings.resx（bin・obj は除く）"""
    return sorted(
        p for p in WINDOWS.rglob("Strings.resx")
        if not ({"bin", "obj"} & set(p.relative_to(WINDOWS).parts))
    )


def satellite_path(neutral: Path, lang: str) -> Path:
    return neutral.with_name(f"Strings.{file_culture(lang)}.resx")


def key_of(neutral: Path) -> str:
    return neutral.relative_to(ROOT).as_posix()


def read_resx(path: Path) -> dict[str, tuple[str, str]]:
    """名前 → (値, コメント)。ファイルの並びのまま"""
    if not path.exists():
        return {}
    entries: dict[str, tuple[str, str]] = {}
    for data in ET.parse(path).getroot().findall("data"):
        name = data.get("name")
        if name is None:
            continue
        value = data.findtext("value") or ""
        comment = data.findtext("comment") or ""
        entries[name] = (value, comment)
    return entries


def escape(text: str) -> str:
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def write_resx(path: Path, entries: list[tuple[str, str, str]]) -> None:
    """entries: (名前, 値, コメント) の並び"""
    out = [HEADER]
    for name, value, comment in entries:
        out.append(f'  <data name="{escape(name)}" xml:space="preserve">\n')
        out.append(f"    <value>{escape(value)}</value>\n")
        if comment:
            out.append(f"    <comment>{escape(comment)}</comment>\n")
        out.append("  </data>\n")
    out.append("</root>\n")
    path.write_text("".join(out), encoding="utf-8")


def placeholders(text: str) -> set[str]:
    """埋める場所。{0:N0} のような書式も含めて比べる（英語と書式が違うと、数の書き方が変わってしまう）。
    閉じていない { や } があれば "!unbalanced" を入れる（string.Format が例外を出すため）"""
    body = text.replace("{{", "").replace("}}", "")
    found = {m.group(0) for m in PLACEHOLDER.finditer(body)}
    if "{" in PLACEHOLDER.sub("", body) or "}" in PLACEHOLDER.sub("", body):
        found.add("!unbalanced")
    return found


def check_lang(lang: str) -> None:
    if lang not in LANGUAGES:
        sys.exit(f"error: 対応していない言語です: {lang}（{', '.join(LANGUAGES)}）")


def cmd_export(lang: str) -> int:
    check_lang(lang)
    result: dict[str, dict[str, str]] = {}
    for neutral in neutral_files():
        existing = read_resx(satellite_path(neutral, lang))
        missing = {name: "" for name in read_resx(neutral) if not existing.get(name, ("", ""))[0]}
        if missing:
            result[key_of(neutral)] = missing
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


def cmd_import(lang: str, json_path: str) -> int:
    check_lang(lang)
    data = json.loads(Path(json_path).read_text(encoding="utf-8"))
    files = {key_of(n): n for n in neutral_files()}
    errors: list[str] = []
    plans: list[tuple[Path, list[tuple[str, str, str]], int]] = []
    for key, values in data.items():
        neutral = files.get(key)
        if neutral is None:
            errors.append(f"{key}: そのような Strings.resx はありません（{', '.join(files)}）")
            continue
        source = read_resx(neutral)
        target_path = satellite_path(neutral, lang)
        current = {name: value for name, (value, _) in read_resx(target_path).items()}
        changed = 0
        for name, value in values.items():
            if name not in source:
                errors.append(f"{key}: {name}: ニュートラルの resx にない名前です")
                continue
            if not isinstance(value, str) or value == "":
                continue
            expected = placeholders(source[name][0])
            actual = placeholders(value)
            if expected != actual:
                errors.append(f"{key}: {name}: 埋める場所が英語と違います（英語 {sorted(expected)}、訳 {sorted(actual)}）")
                continue
            if current.get(name) != value:
                current[name] = value
                changed += 1
        # ニュートラルの並びにそろえ、ニュートラルにない名前は落とす
        entries = [(name, current[name], "") for name in source if current.get(name, "")]
        plans.append((target_path, entries, changed))
    if errors:
        for e in errors:
            print(f"error: {e}", file=sys.stderr)
        print("何も書いていません。", file=sys.stderr)
        return 1
    for path, entries, changed in plans:
        write_resx(path, entries)
        print(f"{path.relative_to(ROOT)}: {changed} 件を書きました（全 {len(entries)} 件）")
    return 0


def cmd_check() -> int:
    errors: list[str] = []
    files = neutral_files()
    if not files:
        errors.append("windows/ の下に Strings.resx がありません")
    for neutral in files:
        source = read_resx(neutral)
        for name, (value, _) in source.items():
            if not value:
                errors.append(f"{key_of(neutral)}: {name}: 英語の値が空です")
        for lang in LANGUAGES:
            path = satellite_path(neutral, lang)
            rel = path.relative_to(ROOT).as_posix()
            if not path.exists():
                errors.append(f"{rel}: ファイルがありません（{lang}）")
                continue
            target = read_resx(path)
            for name, (value, _) in source.items():
                translated = target.get(name, ("", ""))[0]
                if not translated:
                    errors.append(f"{rel}: {name}: 訳がありません")
                elif placeholders(translated) != placeholders(value):
                    errors.append(f"{rel}: {name}: 埋める場所が英語と違います（英語 {sorted(placeholders(value))}、訳 {sorted(placeholders(translated))}）")
            for name in target:
                if name not in source:
                    errors.append(f"{rel}: {name}: ニュートラルの resx にない名前です")
    for e in errors:
        print(f"error: {e}")
    if errors:
        print(f"{len(errors)} 件のエラー")
        return 1
    print(f"エラーはありません（{len(files)} 個の resx × {len(LANGUAGES)} 言語）")
    return 0


def main(argv: list[str]) -> int:
    if len(argv) >= 2 and argv[0] == "export" and len(argv) == 2:
        return cmd_export(argv[1])
    if len(argv) == 3 and argv[0] == "import":
        return cmd_import(argv[1], argv[2])
    if argv == ["check"]:
        return cmd_check()
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
