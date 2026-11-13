#!/usr/bin/env python3
"""配布物に入る依存のライセンスを、一覧（common/third-party-licenses.json）と lock ファイルで突き合わせる。
python3 の標準ライブラリだけで動く。

    python3 scripts/check-licenses.py

確かめること（どれかに外れたら終了コード 1）:
- lock ファイル（windows/Hanasu.Windows・windows/Hanasu.Command の packages.lock.json、Package.resolved、
  scripts/llama-cpp.lock）の依存が、すべて一覧の packages に同じ版で載っている。一覧にあって lock にない項目もエラー。
- 配布物に入る項目（packages の shipped が true のものと contained）のライセンス（SPDX の式）が allowed に入る。
  AND はすべての部分、OR はどれか 1 つが allowed に入ればよい。WITH は例外ごと 1 つの語として見る。
- 配布物に入る項目の名前（notice_name があればそれ）が、notices に書いた THIRD_PARTY_NOTICES に出てくる。
- contained の contained_in が、配布物に入る packages の名前を指す。

設計判断: DEC-REL-012。要件: REQ-REL-005。
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIST = ROOT / "common" / "third-party-licenses.json"
NUGET_LOCKS = [
    ROOT / "windows" / "Hanasu.Windows" / "packages.lock.json",
    ROOT / "windows" / "Hanasu.Command" / "packages.lock.json",
]
SWIFT_RESOLVED = ROOT / "Package.resolved"
LLAMA_LOCK = ROOT / "scripts" / "llama-cpp.lock"


def locked_dependencies() -> dict[tuple[str, str], set[str]]:
    """(ecosystem, name) → 版の集まり"""
    found: dict[tuple[str, str], set[str]] = {}
    for path in NUGET_LOCKS:
        data = json.loads(path.read_text(encoding="utf-8"))
        for deps in data.get("dependencies", {}).values():
            for name, info in deps.items():
                if info.get("type") == "Project":
                    continue
                found.setdefault(("nuget", name), set()).add(info["resolved"])
    data = json.loads(SWIFT_RESOLVED.read_text(encoding="utf-8"))
    for pin in data.get("pins", []):
        state = pin.get("state", {})
        found.setdefault(("swift", pin["identity"]), set()).add(state.get("version") or state.get("revision", ""))
    for line in LLAMA_LOCK.read_text(encoding="utf-8").splitlines():
        if line.startswith("version="):
            found.setdefault(("llama-cpp", "llama.cpp"), set()).add(line.split("=", 1)[1].strip())
    return found


TOKEN = re.compile(r"\(|\)|[^\s()]+")


def license_allowed(expression: str, allowed: set[str]) -> bool:
    """SPDX の式を読み、allowed で満たせるかを返す。読めない式は False"""
    tokens = TOKEN.findall(expression)
    pos = 0

    def peek() -> str | None:
        return tokens[pos] if pos < len(tokens) else None

    def take() -> str:
        nonlocal pos
        token = tokens[pos]
        pos += 1
        return token

    def parse_or() -> bool:
        result = parse_and()
        while peek() == "OR":
            take()
            right = parse_and()
            result = result or right
        return result

    def parse_and() -> bool:
        result = parse_atom()
        while peek() == "AND":
            take()
            right = parse_atom()
            result = result and right
        return result

    def parse_atom() -> bool:
        token = peek()
        if token is None or token in ("AND", "OR", "WITH", ")"):
            raise ValueError(expression)
        take()
        if token == "(":
            result = parse_or()
            if peek() != ")":
                raise ValueError(expression)
            take()
            return result
        if peek() == "WITH":
            take()
            if peek() is None:
                raise ValueError(expression)
            token = f"{token} WITH {take()}"
        return token in allowed

    try:
        result = parse_or()
    except (ValueError, IndexError):
        return False
    return result and pos == len(tokens)


def main() -> int:
    data = json.loads(LIST.read_text(encoding="utf-8"))
    allowed = set(data["allowed"])
    errors: list[str] = []

    packages = data["packages"]
    listed: dict[tuple[str, str], dict] = {}
    for item in packages:
        key = (item["ecosystem"], item["name"])
        if key in listed:
            errors.append(f"一覧に 2 回出てくる: {item['ecosystem']} {item['name']}")
        listed[key] = item

    locked = locked_dependencies()
    for key, versions in sorted(locked.items()):
        item = listed.get(key)
        if item is None:
            errors.append(f"一覧にない依存: {key[0]} {key[1]} {', '.join(sorted(versions))}"
                          "（ライセンスとバイナリの中身を確かめて common/third-party-licenses.json に足す）")
            continue
        for version in sorted(versions):
            if version != item["version"]:
                errors.append(f"版が違う: {key[0]} {key[1]} は lock が {version}、一覧が {item['version']}"
                              "（上げたなら、中身を確かめ直して一覧を直す）")
    for key in sorted(listed):
        if key not in locked:
            errors.append(f"lock にない依存が一覧にある: {key[0]} {key[1]}（外したなら一覧からも消す）")

    shipped_names = {item["name"] for item in packages if item.get("shipped")}
    notice_cache: dict[str, str] = {}

    def check_shipped(kind: str, item: dict) -> None:
        name = item["name"]
        if not license_allowed(item["license"], allowed):
            errors.append(f"許さないライセンス（か読めない式）: {kind} {name}: {item['license']}")
        if not item.get("note"):
            errors.append(f"note がない: {kind} {name}（確かめた中身を書く）")
        notices = item.get("notices") or []
        if not notices:
            errors.append(f"notices がない: {kind} {name}")
        needle = item.get("notice_name", name)
        for notice in notices:
            if notice not in notice_cache:
                path = ROOT / notice
                if not path.is_file():
                    errors.append(f"notices のファイルがない: {notice}（{kind} {name}）")
                    notice_cache[notice] = ""
                    continue
                notice_cache[notice] = path.read_text(encoding="utf-8")
            if needle not in notice_cache[notice]:
                errors.append(f"表示に出てこない: {kind} {name}（「{needle}」が {notice} にない）")

    for item in packages:
        if item.get("shipped"):
            check_shipped("package", item)
        elif not item.get("note"):
            errors.append(f"note がない: package {item['name']}（配布物に入らない理由を書く）")
    for item in data.get("contained", []):
        check_shipped("contained", item)
        for parent in item.get("contained_in", []):
            if parent not in shipped_names:
                errors.append(f"contained_in が配布物に入る依存を指していない: {item['name']} → {parent}")
        if not item.get("contained_in"):
            errors.append(f"contained_in がない: {item['name']}")
    for item in data.get("unversioned", []):
        if item.get("notices"):
            check_shipped("unversioned", {**item, "license": item["license"]})

    if errors:
        for error in errors:
            print(f"エラー: {error}")
        print(f"\n{len(errors)} 件のエラー（一覧: {LIST.relative_to(ROOT)}。決まりは DEC-REL-012）")
        return 1
    count = len(packages) + len(data.get("contained", []))
    print(f"エラーはありません（{count} 項目、lock の依存 {len(locked)} 個）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
