#!/usr/bin/env python3
"""訳の漏れを見つける（決まりは docs/README.md の「多言語」、手順は .claude/skills/i18n/SKILL.md）。

  python3 scripts/check-i18n.py            漏れがあれば終了コード 1
  python3 scripts/check-i18n.py --summary  言語ごとの数も出す

確かめること:
- AI へのプロンプト（Sources/Hanasu/Resources/Prompts/<言語>.json）
  - 対応言語のすべてにファイルがあり、日本語（ja.json）と同じキーがそろっている
  - 値が空でない
  - 埋める場所（${name}）・区切りのタグ（<transcript> など）・JSON のキー（"owner": など）が、日本語と同じ
  - 話者のラベル（speaker.*）や「なし」（minutes.result.none）が、同じ言語の議事録の指示の中で使われている
- 英語と同じ文面のままの値（訳し忘れの疑い）は、報告だけする

python3 の標準ライブラリだけを使う。
"""
# 要件: REQ-COM-062
# 設計判断: DEC-COM-164

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# 対応言語（README と同じ 17 言語）。Mac の PromptLanguage、Windows の PromptLanguage と同じ並び
LANGUAGES = ["en", "ja", "zh-CN", "zh-TW", "ko", "es", "fr", "de", "it", "pt-BR", "ru", "tr", "vi", "id", "pl", "ar", "hi"]
REFERENCE = "ja"

PROMPTS_DIR = ROOT / "Sources/Hanasu/Resources/Prompts"

PLACEHOLDER = re.compile(r"\$\{[A-Za-z]+\}")
TAG = re.compile(r"</?([a-z_]+)(?:_…)?>")
JSON_KEY = re.compile(r"\"([a-z_]+)\":")
# 値に必ず残す記号（日本語に入っていれば、ほかの言語にも要る）
LITERALS = ["MM:SS.s", "M2:", "## ", "{}", "[]", "★", "→", "null", "[--:--]"]
# 英語と同じでよいキー（書式など）
SAME_AS_ENGLISH_OK = {"minutes.item.dueDateFormat", "user.dictionaryRuleSeparator", "minutes.item.details"}


def text(value) -> str:
    if isinstance(value, list):
        return "\n".join(str(v) for v in value)
    return str(value)


def fill(template: str, **args: str) -> str:
    for name, value in args.items():
        template = template.replace("${" + name + "}", value)
    return template


def load(path: Path) -> dict:
    with path.open(encoding="utf-8") as f:
        data = json.load(f)
    return {k: v for k, v in data.items() if not k.startswith("_")}


def check_prompts(errors: list[str], warnings: list[str], counts: dict[str, int]) -> None:
    files = {p.stem: p for p in PROMPTS_DIR.glob("*.json")}
    for name in sorted(set(files) - set(LANGUAGES)):
        errors.append(f"prompts: 対応言語にない言語のファイルがある: {files[name].relative_to(ROOT)}")
    if REFERENCE not in files:
        errors.append(f"prompts: 基準の {REFERENCE}.json がない")
        return
    reference = load(files[REFERENCE])
    english = load(files["en"]) if "en" in files else {}

    for language in LANGUAGES:
        path = files.get(language)
        if path is None:
            errors.append(f"prompts: {language}.json がない（{PROMPTS_DIR.relative_to(ROOT)}）")
            continue
        try:
            table = load(path)
        except json.JSONDecodeError as e:
            errors.append(f"prompts/{language}.json: JSON として読めない: {e}")
            continue
        counts[language] = len(table)
        rel = f"prompts/{language}.json"
        for key in sorted(set(reference) - set(table)):
            errors.append(f"{rel}: キー {key} がない（訳の漏れ）")
        for key in sorted(set(table) - set(reference)):
            errors.append(f"{rel}: 日本語（{REFERENCE}.json）にないキー {key} がある")
        for key in sorted(set(reference) & set(table)):
            ref, val = text(reference[key]), text(table[key])
            if not val.strip():
                errors.append(f"{rel}: {key} が空")
                continue
            if isinstance(reference[key], list) != isinstance(table[key], list) and key.startswith("style."):
                errors.append(f"{rel}: {key} はルールの配列にする（日本語と同じ形）")
            for label, pattern in (("埋める場所", PLACEHOLDER), ("タグ", TAG), ("JSON のキー", JSON_KEY)):
                want, got = sorted(set(pattern.findall(ref))), sorted(set(pattern.findall(val)))
                if want != got:
                    errors.append(f"{rel}: {key} の{label}が日本語と違う（日本語: {want}、この言語: {got}）")
            for literal in LITERALS:
                if literal in ref and literal not in val:
                    errors.append(f"{rel}: {key} に「{literal}」がない（日本語にはある）")
            if language not in ("en", REFERENCE) and key in english and val == text(english[key]) \
                    and key not in SAME_AS_ENGLISH_OK and re.search(r"[A-Za-z]{3,}", PLACEHOLDER.sub("", val)):
                warnings.append(f"{rel}: {key} が英語と同じ（訳し忘れ？）")

        # 同じ言語の中で、話者のラベルと「なし」が議事録の指示に使われているか
        if all(k in table for k in ("speaker.me", "speaker.remote", "speaker.others", "minutes.intro", "minutes.speakerNames",
                                    "minutes.format", "minutes.result.none", "ask.system")):
            me = text(table["speaker.me"])
            remote1 = fill(text(table["speaker.remote"]), n="1")
            others = text(table["speaker.others"])
            for key, needles in (("minutes.intro", [me, remote1, others]),
                                 ("minutes.speakerNames", [me, remote1, others]),
                                 ("minutes.actionItems", [me, remote1]),
                                 ("ask.system", [me, remote1]),
                                 ("minutes.format", [text(table["minutes.result.none"])])):
                for needle in needles:
                    if needle not in text(table.get(key, "")):
                        errors.append(f"{rel}: {key} に、この言語のラベル「{needle}」が出てこない（speaker.* / minutes.result.none と合わせる）")


def main(argv: list[str]) -> int:
    errors: list[str] = []
    warnings: list[str] = []
    counts: dict[str, int] = {}
    check_prompts(errors, warnings, counts)

    if "--summary" in argv:
        print("プロンプトのキーの数: " + ", ".join(f"{k} {v}" for k, v in counts.items()))
    for w in warnings:
        print(f"warning: {w}")
    for e in errors:
        print(f"error: {e}")
    if errors:
        print(f"\n訳の漏れ・食い違いが {len(errors)} 件あります（手順は .claude/skills/i18n/SKILL.md）")
        return 1
    print(f"OK（{len(LANGUAGES)} 言語。報告 {len(warnings)} 件）")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
