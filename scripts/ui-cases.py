#!/usr/bin/env python3
"""画面を見て確かめる UI のテスト項目（common/testdata/ui/*.json）を扱う。python3 の標準ライブラリだけで動く。

    python3 scripts/ui-cases.py check                  # 形・ID・要件との対応・生成した Markdown が最新かを確かめる
    python3 scripts/ui-cases.py md                     # docs/verification/ui-ux-test-cases.md を作り直す
    python3 scripts/ui-cases.py render [--ids UX-010,UX-016] [--priority P1] [--lang ja,en|all] [--out <フォルダ>]
                                                       # Mac の「render」の項目を .build/debug/Hanasu で PNG に描き、manifest.json を書く
    python3 scripts/ui-cases.py list [--kind render|drive|manual] [--os mac|windows]

決まりは docs/spec/common.md の DEC-COM-170。描いた PNG の判定は .claude/skills/ui-test/SKILL.md の手順で行う。
check はエラーがあれば終了コード 1 を返す。「実機で確かめる」要件に項目がないことは警告で、終了コードは変えない。
"""

# 設計判断: DEC-COM-170

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CASES_DIR = ROOT / "common" / "testdata" / "ui"
SPEC_DIR = ROOT / "docs" / "spec"
MAC_SOURCES = ROOT / "Sources" / "Hanasu"
MD_PATH = ROOT / "docs" / "verification" / "ui-ux-test-cases.md"
DEFAULT_BINARY = ROOT / ".build" / "debug" / "Hanasu"

# fullmatch で使う（$ は末尾の改行を許し、\d は全角の数字にも当たるので使わない）
ID_RE = re.compile(r"UX-[0-9]{3}")
REF_RE = re.compile(r"(?:REQ|DEC)-[A-Z]+-[0-9]{3}")
OSES = ("mac", "windows")
OS_LABEL = {"mac": "M", "windows": "W"}
PRIORITIES = ("P1", "P2", "P3")
KINDS = ("render", "drive", "manual")
# README と同じ 17 言語（--ui-language が受け付けるもの）
LANGUAGES = ("ja", "en", "zh-CN", "zh-TW", "ko", "es", "fr", "de", "it", "pt-BR", "ru", "tr", "vi", "id", "pl", "ar", "hi")
CASE_KEYS = {"id", "steps", "expected", "os", "priority", "refs", "automation", "origin"}
AUTOMATION_KEYS = {
    "render": {"kind", "renders", "look", "remaining", "languages"},
    "drive": {"kind", "plan"},
    "manual": {"kind", "reason"},
}


# ---------------------------------------------------------------- 読み込み

def load_sections() -> list[dict]:
    """節のファイルを order の順に読む。各節は {file, order, title, cases}"""
    sections = []
    for path in sorted(CASES_DIR.glob("*.json")):
        rel = path.relative_to(ROOT).as_posix()
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            sys.exit(f"error: {rel}: JSON として読めない（{e}）")
        if not isinstance(data, dict) or not isinstance(data.get("cases", []), list) \
                or not all(isinstance(c, dict) for c in data.get("cases", [])):
            sys.exit(f"error: {rel}: 節は {{order, title, cases: [項目…]}} の形にする")
        data["file"] = rel
        sections.append(data)
    sections.sort(key=lambda s: s.get("order", 999))
    return sections


def all_cases(sections: list[dict]) -> list[dict]:
    return [case for section in sections for case in section.get("cases", [])]


def load_spec() -> tuple[dict[str, bool], list[str]]:
    """spec の ID → 廃止か、と「確かめ方」に「実機」とある要件（廃止は除く）"""
    ids: dict[str, bool] = {}
    manual_reqs: list[str] = []
    heading = re.compile(r"^###\s+((?:REQ|DEC)-[A-Z]+-[0-9]{3})(?![0-9])")
    for path in sorted(SPEC_DIR.glob("*.md")):
        retired = False
        current = None
        in_howto = False  # 「- 確かめ方」の行と、その下の入れ子の箇条書きの中
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.startswith("## "):
                retired = line[3:].strip() == "廃止"
            m = heading.match(line)
            if m:
                current = m.group(1)
                ids[current] = retired
                in_howto = False
                continue
            if line.startswith("- "):
                in_howto = line.startswith("- 確かめ方")
            elif not line.strip() or line.startswith("#"):
                in_howto = False
            if in_howto and current and current.startswith("REQ-") and not retired and "実機" in line \
                    and current not in manual_reqs:
                manual_reqs.append(current)
    return ids, manual_reqs


def nonempty(value) -> bool:
    return isinstance(value, str) and bool(value.strip())


# Markdown の表のセルに入る文字列（| と改行を入れると表が崩れる）
def table_breaking(value) -> bool:
    return isinstance(value, str) and ("|" in value or "\n" in value or "\r" in value)


def render_flags() -> set[str]:
    """Mac のアプリが受け付ける --render-… の引数"""
    flags: set[str] = set()
    for path in MAC_SOURCES.glob("*.swift"):
        flags.update(re.findall(r'"(--render-[a-z-]+)"', path.read_text(encoding="utf-8")))
    return flags


# ---------------------------------------------------------------- check

def check(args: argparse.Namespace) -> int:
    sections = load_sections()
    errors: list[str] = []
    warnings: list[str] = []
    spec_ids, manual_reqs = load_spec()
    flags = render_flags()
    seen: dict[str, str] = {}
    referenced: set[str] = set()

    if not sections:
        errors.append(f"{CASES_DIR.relative_to(ROOT)} に節のファイルがない")
    orders = [s.get("order") for s in sections]
    if len(orders) != len(set(orders)):
        errors.append("節の order が重なっている")

    for section in sections:
        where = section["file"]
        for key in ("order", "title", "cases"):
            if key not in section:
                errors.append(f"{where}: 節に {key} がない")
        for case in section.get("cases", []):
            cid = case.get("id", "?")
            at = f"{where}: {cid!r}" if not isinstance(cid, str) else f"{where}: {cid}"
            unknown = set(case) - CASE_KEYS
            if unknown:
                errors.append(f"{at}: 知らないキー {sorted(unknown)}")
            if not isinstance(cid, str) or not ID_RE.fullmatch(cid):
                errors.append(f"{at}: ID は UX-<半角の 3 桁>")
                cid = repr(cid)
            if cid in seen:
                errors.append(f"{at}: ID が {seen[cid]} と重なっている")
            seen[cid] = where
            for key in ("steps", "expected"):
                if not nonempty(case.get(key)):
                    errors.append(f"{at}: {key} が空か文字列でない")
                elif table_breaking(case[key]):
                    errors.append(f"{at}: {key} に | と改行を使わない（Markdown の表が崩れる）")
            oses = case.get("os")
            if not isinstance(oses, list) or not oses or any(o not in OSES for o in oses) or len(set(oses)) != len(oses):
                errors.append(f"{at}: os は mac / windows の並び")
                oses = [o for o in oses if o in OSES] if isinstance(oses, list) else []
            if case.get("priority") not in PRIORITIES:
                errors.append(f"{at}: priority は {'/'.join(PRIORITIES)}")
            refs = case.get("refs", [])
            if not isinstance(refs, list):
                errors.append(f"{at}: refs は ID の並び")
                refs = []
            for ref in refs:
                if not isinstance(ref, str) or not REF_RE.fullmatch(ref):
                    errors.append(f"{at}: refs の {ref!r} は REQ-/DEC- の ID 1 つ（範囲は使わない）")
                elif ref not in spec_ids:
                    errors.append(f"{at}: refs の {ref} が spec にない")
                elif spec_ids[ref]:
                    errors.append(f"{at}: refs の {ref} は廃止されている")
                else:
                    referenced.add(ref)
            automation = case.get("automation")
            if not isinstance(automation, dict) or set(automation) != set(oses):
                errors.append(f"{at}: automation は os と同じキー（{oses}）の辞書にする")
                automation = automation if isinstance(automation, dict) else {}
            for os_name, auto in automation.items():
                errors += [f"{at} ({os_name}): {e}" for e in check_automation(os_name, auto, flags)]

    for req in manual_reqs:
        if req not in referenced:
            warnings.append(f"{req} は「実機で確かめる」要件だが、どの UI のテスト項目からも指されていない")

    if not errors:
        expected_md = build_markdown(sections)
        current = MD_PATH.read_text(encoding="utf-8") if MD_PATH.exists() else ""
        if current != expected_md:
            errors.append(f"{MD_PATH.relative_to(ROOT)} が古い。python3 scripts/ui-cases.py md で作り直す")

    cases = all_cases(sections)
    counts = {kind: sum(1 for c in cases if c.get("automation", {}).get("mac", {}).get("kind") == kind) for kind in KINDS}
    if not args.summary or errors or warnings:
        for e in errors:
            print(f"  エラー: {e}")
        for w in warnings:
            print(f"  警告: {w}")
    print(f"UI のテスト項目 {len(cases)} 件（Mac: 描画 {counts['render']}・操作 {counts['drive']}・手 {counts['manual']}）"
          f" エラー {len(errors)} 件・警告 {len(warnings)} 件")
    return 1 if errors else 0


def check_automation(os_name: str, auto, flags: set[str]) -> list[str]:
    if not isinstance(auto, dict):
        return ["確かめ方は {kind, …} の辞書にする"]
    kind = auto.get("kind")
    if kind not in KINDS:
        return [f"kind は {'/'.join(KINDS)}"]
    errors = []
    unknown = set(auto) - AUTOMATION_KEYS[kind]
    if unknown:
        errors.append(f"知らないキー {sorted(unknown)}")
    if os_name == "windows" and kind != "manual":
        errors.append("Windows の項目は今はすべて manual（描画・操作の仕組みは FUT-019）")
    if kind == "render":
        renders = auto.get("renders")
        if not isinstance(renders, list) or not renders \
                or not all(isinstance(r, list) and r and all(isinstance(a, str) for a in r) for r in renders):
            errors.append("renders は引数（文字列）の並びの並び")
        else:
            for r in renders:
                if r[0] not in flags:
                    errors.append(f"{r[0]} が Sources/Hanasu にない")
                if not any("{out}" in a for a in r):
                    errors.append(f"{r[0]} の引数に出力の {{out}} がない")
                if "--ui-language" in r:
                    errors.append(f"{r[0]}: --ui-language は書かない（言語は languages か render の --lang で選ぶ）")
                # 描画に渡すテスト用のデータ（common/testdata/ui/fixtures/…）。リポジトリの根からの相対パス
                for a in r:
                    if a.startswith("common/") and not (ROOT / a).exists():
                        errors.append(f"{r[0]} に渡す {a} がない")
        if not nonempty(auto.get("look")):
            errors.append("look（PNG で見る観点）が空か文字列でない")
        if "remaining" in auto and (not nonempty(auto["remaining"]) or table_breaking(auto["remaining"])):
            errors.append("remaining は空でない文字列で、| と改行を使わない")
        langs = auto.get("languages")
        if langs is not None and langs != "all" and (
                not isinstance(langs, list) or not langs or any(l not in LANGUAGES for l in langs) or len(set(langs)) != len(langs)):
            errors.append("languages は \"all\" か、17 言語のコードの重ならない並び")
    elif kind == "drive":
        if not nonempty(auto.get("plan")):
            errors.append("plan（どう操作するか）が空か文字列でない")
    elif not nonempty(auto.get("reason")):
        errors.append("reason（人が確かめる理由）が空か文字列でない")
    elif table_breaking(auto["reason"]):
        errors.append("reason に | と改行を使わない（Markdown の表が崩れる）")
    return errors


# ---------------------------------------------------------------- md

MD_HEADER = """# UI/UX テストケース一覧

<!-- 生成したファイル。手で直さない。元は common/testdata/ui/*.json で、python3 scripts/ui-cases.py md で作り直す（DEC-COM-170） -->

画面を見て確かめる UI のテスト項目の一覧。**このファイルは common/testdata/ui/*.json から作る**（項目を足す・直すときは JSON を直して `python3 scripts/ui-cases.py md`）。手順の一覧で、結果は書かない。実施したら、日付つきの結果を [ui-runs.md](ui-runs.md) に残す。

- 対象 OS: Mac = M、Windows = W。両方に欄がある項目は、同じ結果になることが期待。
- 優先度: **P1** = 出す前に必ず / **P2** = 通常 / **P3** = あれば確かめる。
- 「要件」の列は `docs/spec/` の ID。振る舞いの正しさの根拠はそこにある。
- 「Mac の確かめ方」の列: **描画** = `python3 scripts/ui-cases.py render` で PNG に描き、ui-test のスキル（`.claude/skills/ui-test/SKILL.md`）で判定する（「残り」は描画では見られず、人が確かめる部分）/ **操作** = 本物のアプリを操作して確かめる（自動の仕組みは FUT-018。今は人が確かめる）/ **手** = 人が確かめる。Windows はすべて人が確かめる（FUT-019）。
- 準備（人が確かめるとき）: ①新規ユーザー（初回起動）②既存ユーザー（設定・履歴・会議が溜まっている）の 2 つの環境、外付けマイクと内蔵マイク、会議アプリ（Zoom / Meet / Teams のどれか）、ネットワークを切れる状態。
"""

MD_FOOTER = """
## この一覧が見ていないもの

- 自動テストで見られるもの（辞書の置換、プロンプトの組み立て、`token_uri` の検証、履歴の検索など）は `swift build` / `cd windows && dotnet test Hanasu.Core.Tests` の側で見る。
- 性能の数値（レイテンシ・メモリ・CPU）の計測は含まない。性能を見る項目（UX-046・056・060）は「引っかからないか」を体感で見るだけ。
"""


def md_cell(text: str) -> str:
    return text.replace("\r", " ").replace("\n", " ").strip()


def mac_method(case: dict) -> str:
    auto = case.get("automation", {}).get("mac")
    if not auto:
        return "—"
    kind = auto["kind"]
    if kind == "render":
        flags = sorted({r[0] for r in auto["renders"]}, key=lambda f: [r[0] for r in auto["renders"]].index(f))
        text = "描画: " + "、".join(f"`{f}`" for f in flags)
        if auto.get("languages"):
            langs = auto["languages"]
            text += "（17 言語）" if langs == "all" else f"（{', '.join(langs)}）"
        if auto.get("remaining"):
            text += f"。残り: {auto['remaining']}"
        return text
    if kind == "drive":
        return "操作"
    return f"手（{auto['reason']}）"


def build_markdown(sections: list[dict]) -> str:
    out = [MD_HEADER]
    for number, section in enumerate(sections, start=1):
        out.append(f"\n## {number}. {section['title']}\n")
        if section.get("note"):
            out.append(f"\n{section['note']}\n")
        out.append("\n| ID | 手順 | 期待 | OS | 優先度 | 要件 | Mac の確かめ方 |\n| --- | --- | --- | --- | --- | --- | --- |\n")
        for case in section["cases"]:
            oses = "/".join(OS_LABEL[o] for o in case["os"])
            refs = ", ".join(case.get("refs", [])) or "—"
            steps = md_cell(case["steps"])
            out.append(f"| {case['id']} | {steps} | {md_cell(case['expected'])} | {oses} | {case['priority']} | {refs} | {md_cell(mac_method(case))} |\n")
    out.append(MD_FOOTER)
    return "".join(out)


def write_md(args: argparse.Namespace) -> int:
    MD_PATH.write_text(build_markdown(load_sections()), encoding="utf-8")
    print(f"wrote {MD_PATH.relative_to(ROOT)}")
    return 0


# ---------------------------------------------------------------- render

def selected_cases(args: argparse.Namespace) -> list[dict]:
    cases = all_cases(load_sections())
    if getattr(args, "ids", None):
        wanted = {i.strip() for i in args.ids.split(",") if i.strip()}
        missing = wanted - {c["id"] for c in cases}
        if missing:
            sys.exit(f"error: ない ID: {', '.join(sorted(missing))}")
        cases = [c for c in cases if c["id"] in wanted]
    if getattr(args, "priority", None):
        allowed = {p.strip().upper() for p in args.priority.split(",") if p.strip()}
        bad = allowed - set(PRIORITIES)
        if not allowed or bad:
            sys.exit(f"error: --priority は {','.join(PRIORITIES)} のどれか（{', '.join(sorted(bad)) or '空'} は使えない）")
        cases = [c for c in cases if c["priority"] in allowed]
    return cases


def languages_for(case_auto: dict, cli: str | None) -> list[str]:
    if cli is not None:
        langs = list(LANGUAGES) if cli.strip() == "all" else list(dict.fromkeys(l.strip() for l in cli.split(",") if l.strip()))
        bad = [l for l in langs if l not in LANGUAGES]
        if not langs or bad:
            sys.exit(f"error: --lang は 17 言語のコードか all（{', '.join(bad) or '空'} は使えない）")
        return langs
    langs = case_auto.get("languages")
    if langs == "all":
        return list(LANGUAGES)
    return langs or ["ja"]


def png_state(directory: Path) -> dict[Path, float]:
    return {p: p.stat().st_mtime_ns for p in directory.rglob("*.png")}


def render(args: argparse.Namespace) -> int:
    binary = Path(args.binary).resolve()
    if not binary.is_file() or not os.access(binary, os.X_OK):
        sys.exit(f"error: {binary} が実行できるファイルでない。先に swift build を動かす（.app ではなく中の実行ファイルを渡す）")
    out = Path(args.out).resolve() if args.out else ROOT / ".build" / "ui-cases" / dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    chosen = selected_cases(args)
    targets = [c for c in chosen if c.get("automation", {}).get("mac", {}).get("kind") == "render"]
    if getattr(args, "ids", None):
        skipped = [c["id"] for c in chosen if c not in targets]
        if skipped:
            print(f"描かない（Mac の確かめ方が render でない）: {', '.join(skipped)}")
    if not targets:
        print("描く項目がない（Mac の確かめ方が render の項目を選ぶ）")
        return 1 if getattr(args, "ids", None) else 0
    # 言語の指定の誤りは、描き始める前に止める
    plans = [(case, languages_for(case["automation"]["mac"], args.lang)) for case in targets]
    out.mkdir(parents=True, exist_ok=True)
    entries = []
    failed = 0
    for case, langs in plans:
        auto = case["automation"]["mac"]
        for lang in langs:
            case_dir = out / lang / case["id"]
            # 前の回の PNG で OK にならないよう、その項目のフォルダだけを空にしてから描く
            if case_dir.exists():
                shutil.rmtree(case_dir)
            case_dir.mkdir(parents=True)
            errors = []
            argvs = []
            for r in auto["renders"]:
                argv = [str(binary)] + [a.replace("{out}", str(case_dir)) for a in r] + ["--ui-language", lang]
                argvs.append(argv[1:])
                before = png_state(case_dir)
                try:
                    proc = subprocess.run(argv, capture_output=True, text=True, timeout=args.timeout, cwd=ROOT)
                    if proc.returncode != 0:
                        errors.append(f"{r[0]}: 終了コード {proc.returncode}: {proc.stderr.strip()[-300:]}")
                        continue
                except subprocess.TimeoutExpired:
                    errors.append(f"{r[0]}: {args.timeout} 秒で終わらなかった")
                    continue
                except OSError as e:
                    errors.append(f"{r[0]}: 起動できなかった（{e}）")
                    continue
                # 描画の CLI は PNG を書けなくても 0 で終わることがあるので、新しく書いた PNG があるかで見る
                after = png_state(case_dir)
                if not any(before.get(p) != t for p, t in after.items()):
                    errors.append(f"{r[0]}: PNG を書かなかった")
            pngs = sorted(p.relative_to(out).as_posix() for p in case_dir.rglob("*.png"))
            ok = not errors
            failed += 0 if ok else 1
            entries.append({
                "id": case["id"], "language": lang, "priority": case["priority"],
                "steps": case["steps"], "expected": case["expected"], "look": auto["look"],
                "remaining": auto.get("remaining"), "refs": case.get("refs", []),
                "argv": argvs, "pngs": pngs, "rendered": ok, "errors": errors,
            })
            print(f"{'OK' if ok else 'NG'} {case['id']} [{lang}] {len(pngs)} 枚" + ("" if ok else f" — {'; '.join(errors)}"))

    def git(*a: str) -> str:
        return subprocess.run(["git", *a], capture_output=True, text=True, cwd=ROOT).stdout.strip()

    manifest = {
        "created": dt.datetime.now().isoformat(timespec="seconds"),
        "binary": str(binary),
        "binary_modified": dt.datetime.fromtimestamp(binary.stat().st_mtime).isoformat(timespec="seconds"),
        "commit": git("rev-parse", "--short", "HEAD"),
        # 作業中の変更があると、commit だけではどのコードで描いたか分からない
        "dirty": bool(git("status", "--porcelain", "--untracked-files=no")),
        "out": str(out),
        "entries": entries,
    }
    (out / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"描いた {len(entries)} 件（失敗 {failed} 件）。一覧: {out / 'manifest.json'}")
    return 1 if failed else 0


# ---------------------------------------------------------------- list

def list_cases(args: argparse.Namespace) -> int:
    for case in selected_cases(args):
        for os_name in case["os"]:
            if args.os and os_name != args.os:
                continue
            auto = case["automation"][os_name]
            if args.kind and auto["kind"] != args.kind:
                continue
            print(f"{case['id']} {OS_LABEL[os_name]} {case['priority']} {auto['kind']:6} {case['steps'][:60]}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("check", help="形・ID・要件との対応・Markdown が最新かを確かめる")
    p.add_argument("--summary", action="store_true", help="エラーと警告と集計だけを出す")
    p.set_defaults(func=check)
    p = sub.add_parser("md", help="docs/verification/ui-ux-test-cases.md を作り直す")
    p.set_defaults(func=write_md)
    p = sub.add_parser("render", help="Mac の render の項目を PNG に描く")
    p.add_argument("--ids", help="UX-010,UX-016 のように ID を選ぶ")
    p.add_argument("--priority", help="P1 か P1,P2 のように優先度を選ぶ")
    p.add_argument("--lang", help="ja,en のように表示の言語を選ぶ（all で 17 言語）。省くと項目の languages か ja")
    p.add_argument("--out", help="出力のフォルダ（省くと .build/ui-cases/<日時>）")
    p.add_argument("--binary", default=str(DEFAULT_BINARY), help="Mac のアプリの実行ファイル")
    p.add_argument("--timeout", type=int, default=90, help="1 回の描画の待ち時間の上限（秒）")
    p.set_defaults(func=render)
    p = sub.add_parser("list", help="項目を一覧する")
    p.add_argument("--kind", choices=KINDS)
    p.add_argument("--os", choices=OSES)
    p.add_argument("--ids")
    p.add_argument("--priority")
    p.set_defaults(func=list_cases)
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
