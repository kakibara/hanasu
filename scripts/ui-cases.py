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
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CASES_DIR = ROOT / "common" / "testdata" / "ui"
SPEC_DIR = ROOT / "docs" / "spec"
MAC_SOURCES = ROOT / "Sources" / "Hanasu"
MD_PATH = ROOT / "docs" / "verification" / "ui-ux-test-cases.md"
DEFAULT_BINARY = ROOT / ".build" / "debug" / "Hanasu"

ID_RE = re.compile(r"^UX-\d{3}$")
REF_RE = re.compile(r"^(?:REQ|DEC)-[A-Z]+-\d{3}$")
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
        data = json.loads(path.read_text(encoding="utf-8"))
        data["file"] = path.relative_to(ROOT).as_posix()
        sections.append(data)
    sections.sort(key=lambda s: s.get("order", 999))
    return sections


def all_cases(sections: list[dict]) -> list[dict]:
    return [case for section in sections for case in section.get("cases", [])]


def load_spec() -> tuple[dict[str, bool], list[str]]:
    """spec の ID → 廃止か、と「確かめ方」に「実機」とある要件（廃止は除く）"""
    ids: dict[str, bool] = {}
    manual_reqs: list[str] = []
    heading = re.compile(r"^###\s+((?:REQ|DEC)-[A-Z]+-\d{3})\b")
    for path in sorted(SPEC_DIR.glob("*.md")):
        retired = False
        current = None
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.startswith("## "):
                retired = line[3:].strip() == "廃止"
            m = heading.match(line)
            if m:
                current = m.group(1)
                ids[current] = retired
                continue
            if current and current.startswith("REQ-") and not retired and line.startswith("- 確かめ方") and "実機" in line:
                manual_reqs.append(current)
    return ids, manual_reqs


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
            at = f"{where}: {cid}"
            unknown = set(case) - CASE_KEYS
            if unknown:
                errors.append(f"{at}: 知らないキー {sorted(unknown)}")
            if not ID_RE.match(cid):
                errors.append(f"{at}: ID は UX-<3 桁>")
            if cid in seen:
                errors.append(f"{at}: ID が {seen[cid]} と重なっている")
            seen[cid] = where
            for key in ("steps", "expected"):
                if not str(case.get(key, "")).strip():
                    errors.append(f"{at}: {key} が空")
            if "|" in case.get("steps", "") + case.get("expected", ""):
                errors.append(f"{at}: 手順・期待に | を使わない（Markdown の表が崩れる）")
            oses = case.get("os", [])
            if not oses or any(o not in OSES for o in oses) or len(set(oses)) != len(oses):
                errors.append(f"{at}: os は mac / windows の並び")
            if case.get("priority") not in PRIORITIES:
                errors.append(f"{at}: priority は {'/'.join(PRIORITIES)}")
            for ref in case.get("refs", []):
                if not REF_RE.match(ref):
                    errors.append(f"{at}: refs の {ref} は REQ-/DEC- の ID 1 つ（範囲は使わない）")
                elif ref not in spec_ids:
                    errors.append(f"{at}: refs の {ref} が spec にない")
                elif spec_ids[ref]:
                    errors.append(f"{at}: refs の {ref} は廃止されている")
                referenced.add(ref)
            automation = case.get("automation", {})
            if set(automation) != set(oses):
                errors.append(f"{at}: automation のキーは os と同じ（{oses}）にする")
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


def check_automation(os_name: str, auto: dict, flags: set[str]) -> list[str]:
    kind = auto.get("kind")
    if kind not in KINDS:
        return [f"kind は {'/'.join(KINDS)}"]
    errors = []
    unknown = set(auto) - AUTOMATION_KEYS[kind]
    if unknown:
        errors.append(f"知らないキー {sorted(unknown)}")
    if kind == "render":
        if os_name != "mac":
            errors.append("render は Mac だけ（Windows の描画は FUT-019）")
        renders = auto.get("renders")
        if not renders or not all(isinstance(r, list) and r for r in renders):
            errors.append("renders は引数の並びの並び")
        else:
            for r in renders:
                if r[0] not in flags:
                    errors.append(f"{r[0]} が Sources/Hanasu にない")
                if not any("{out}" in a for a in r):
                    errors.append(f"{r[0]} の引数に出力の {{out}} がない")
                # 描画に渡すテスト用のデータ（common/testdata/ui/fixtures/…）。リポジトリの根からの相対パス
                for a in r:
                    if a.startswith("common/") and not (ROOT / a).exists():
                        errors.append(f"{r[0]} に渡す {a} がない")
        if not str(auto.get("look", "")).strip():
            errors.append("look（PNG で見る観点）が空")
        langs = auto.get("languages")
        if langs is not None and langs != "all" and (not isinstance(langs, list) or any(l not in LANGUAGES for l in langs)):
            errors.append("languages は \"all\" か 17 言語のコードの並び")
    elif kind == "drive":
        if not str(auto.get("plan", "")).strip():
            errors.append("plan（どう操作するか）が空")
    elif not str(auto.get("reason", "")).strip():
        errors.append("reason（人が確かめる理由）が空")
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
    return text.replace("\n", " ").strip()


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
        allowed = set(args.priority.split(","))
        cases = [c for c in cases if c["priority"] in allowed]
    return cases


def languages_for(case_auto: dict, cli: str | None) -> list[str]:
    if cli:
        langs = list(LANGUAGES) if cli == "all" else [l.strip() for l in cli.split(",") if l.strip()]
        bad = [l for l in langs if l not in LANGUAGES]
        if bad:
            sys.exit(f"error: --lang は 17 言語のコードか all（{', '.join(bad)} は対応していない）")
        return langs
    langs = case_auto.get("languages")
    if langs == "all":
        return list(LANGUAGES)
    return langs or ["ja"]


def render(args: argparse.Namespace) -> int:
    binary = Path(args.binary).resolve()
    if not binary.exists():
        sys.exit(f"error: {binary} がない。先に swift build を動かす")
    out = Path(args.out).resolve() if args.out else ROOT / ".build" / "ui-cases" / dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    targets = [c for c in selected_cases(args) if c.get("automation", {}).get("mac", {}).get("kind") == "render"]
    if not targets:
        print("描く項目がない（Mac の確かめ方が render の項目を選ぶ）")
        return 0
    entries = []
    failed = 0
    for case in targets:
        auto = case["automation"]["mac"]
        for lang in languages_for(auto, args.lang):
            case_dir = out / lang / case["id"]
            case_dir.mkdir(parents=True, exist_ok=True)
            errors = []
            for r in auto["renders"]:
                argv = [str(binary)] + [a.replace("{out}", str(case_dir)) for a in r] + ["--ui-language", lang]
                try:
                    proc = subprocess.run(argv, capture_output=True, text=True, timeout=args.timeout, cwd=ROOT)
                    if proc.returncode != 0:
                        errors.append(f"{r[0]}: 終了コード {proc.returncode}: {proc.stderr.strip()[-300:]}")
                except subprocess.TimeoutExpired:
                    errors.append(f"{r[0]}: {args.timeout} 秒で終わらなかった")
            pngs = sorted(p.relative_to(out).as_posix() for p in case_dir.rglob("*.png"))
            if not pngs:
                errors.append("PNG が 1 つもできなかった")
            ok = not errors
            failed += 0 if ok else 1
            entries.append({
                "id": case["id"], "language": lang, "priority": case["priority"],
                "steps": case["steps"], "expected": case["expected"], "look": auto["look"],
                "remaining": auto.get("remaining"), "refs": case.get("refs", []),
                "pngs": pngs, "rendered": ok, "errors": errors,
            })
            print(f"{'OK' if ok else 'NG'} {case['id']} [{lang}] {len(pngs)} 枚" + ("" if ok else f" — {'; '.join(errors)}"))
    manifest = {
        "created": dt.datetime.now().isoformat(timespec="seconds"),
        "binary": str(binary),
        "commit": subprocess.run(["git", "rev-parse", "--short", "HEAD"], capture_output=True, text=True, cwd=ROOT).stdout.strip(),
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
