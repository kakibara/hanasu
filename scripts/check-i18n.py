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
- Mac の UI の文字列（Sources/Hanasu/Resources/Localizable.xcstrings。scripts/i18n-strings.py）
  - Swift の tr("…") のキーとカタログのキーが一致している（足りない・余っているキーがない）
  - すべてのキーに、日本語以外の 16 言語の訳があり、%@ などの数が同じ
  - アプリのソース（開発用の CLI・自己テストを除く）に、tr() で包んでいない日本語の文字列がない
    （ログ・print、言語の決まりに使う語（行に // skip-tr）、比較・正規表現の文字列は除く）
- Windows の UI の文字列（windows/**/Properties/Strings*.resx。scripts/i18n-resx.py check）
  - 16 言語のサテライトがそろい、英語と同じ名前・{0} の組がある
  - アプリのコード（windows/Hanasu.Windows・Hanasu.Core・Hanasu.Whisper・Hanasu.Diarization の .cs と .xaml）に、
    .resx に移していない日本語の文字列がない（ログ、行に skip-tr のもの（XAML は前の行のコメント）は除く）
- README（README.md と README.<言語>.md）
  - 17 言語のファイルがそろい、どれにも言語の切り替えのリンクがある
  - 訳の表の行・<kbd>・<img>・コードブロック・<details>・リンクの数が README.md と同じ（README.md の変更の入れ忘れ）

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
LITERALS = ["MM:SS.s", "M2:", "## ", "{}", "[]", "★", "→", "null", "[--:--]", "[12:34]", "[1:02:34]", "\"at\": \"12:34\""]
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

        # 期限の日付の書式（ICU の形）: 引用符の外の英字は、日付の書式の文字（d M E y L c）だけ。
        # 「d de MMM」のように語をそのまま書くと、e などが書式の文字として読まれてしまう（'de' と引用符で囲む）
        if "minutes.item.dueDateFormat" in table:
            pattern = re.sub(r"'[^']*'", "", text(table["minutes.item.dueDateFormat"]))
            stray = sorted(set(re.findall(r"[A-Za-z]", pattern)) - set("dMEyLc"))
            if stray:
                errors.append(f"{rel}: minutes.item.dueDateFormat に引用符で囲んでいない文字 {stray} がある（語は 'de' のように ' で囲む）")

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
                                 ("chat.system", [me, remote1, others]),
                                 ("minutes.format", [text(table["minutes.result.none"])])):
                for needle in needles:
                    if needle not in text(table.get(key, "")):
                        errors.append(f"{rel}: {key} に、この言語のラベル「{needle}」が出てこない（speaker.* / minutes.result.none と合わせる）")


def load_strings_tool():
    import importlib.util
    spec = importlib.util.spec_from_file_location("i18n_strings", ROOT / "scripts/i18n-strings.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


JA_TEXT = re.compile(r"[ぁ-んァ-ヶ一-龯ー々]")
# つなぎに使う日本語の約物（「（…）」「、」「・」など）も、UI に出るなら訳す（tr("（%@）", …) のように）
JA_PUNCT = re.compile(r"[（）「」、。・【】『』]")
STRING_LITERAL = re.compile(r'"(?:[^"\\\n]|\\.)*"')
# 包まなくてよい行（ログ・標準出力・開発者向けのエラー）と、文字列の前に来ると包まなくてよいもの（比較・照合・正規表現）
LEAK_SKIP_LINE = re.compile(r"appLog\.|logger\.|\bprint\(|NSLog\(|os_log|fatalError\(|assertionFailure\(|preconditionFailure\(|precondition\(|// skip-tr|FileHandle\.standardError|^\s*//|^\s*///")
LEAK_SKIP_BEFORE = re.compile(r"(\btr\(|case|==|!=|\.contains\(|hasPrefix\(|hasSuffix\(|range\(of:|replacingOccurrences\(of:|with:|pattern:|forKey:)\s*$")


def check_mac_strings(errors: list[str], warnings: list[str], counts: dict[str, int]) -> None:
    tool = load_strings_tool()
    if not tool.CATALOG.exists():
        errors.append("strings: Sources/Hanasu/Resources/Localizable.xcstrings がない")
        return
    try:
        keys = tool.all_keys()
    except ValueError as e:
        errors.append(f"strings: {e}")
        return
    strings = tool.load_catalog()["strings"]
    for key in sorted(set(keys) - set(strings)):
        errors.append(f"strings: カタログにないキー {key!r}（{keys[key][0]}）→ python3 scripts/i18n-strings.py sync で足し、訳を入れる")
    for key in sorted(set(strings) - set(keys)):
        errors.append(f"strings: 使っていないキー {key!r} がカタログにある → python3 scripts/i18n-strings.py sync で消す")
    for language in LANGUAGES:
        if language == tool.SOURCE_LANGUAGE:
            continue
        done = 0
        for key in sorted(set(keys) & set(strings)):
            value = tool.translation(strings[key], language)
            if value is None:
                errors.append(f"strings/{language}: 訳がない {key!r}（{keys[key][0]}）")
                continue
            done += 1
            if tool.formats(key) != tool.formats(value) or not tool.positional_ok(value):
                errors.append(f"strings/{language}: %@ などが原文と合わない {key!r} → {value!r}")
            if language not in ("zh-CN", "zh-TW") and re.search(r"[ぁ-んァ-ヶ]", value):
                errors.append(f"strings/{language}: 訳に日本語のかなが残っている {key!r} → {value!r}")
        counts[f"strings:{language}"] = done

    # 包み忘れ（新しい機能で、UI の文字列を tr() なしで書いた）
    for path in tool.swift_files():
        in_multiline = False
        for number, line in enumerate(path.read_text(encoding="utf-8").split("\n"), start=1):
            if line.count('"""') % 2 == 1:
                in_multiline = not in_multiline
                if not in_multiline:
                    continue
            if in_multiline or LEAK_SKIP_LINE.search(line):
                continue
            for m in STRING_LITERAL.finditer(line):
                if (JA_TEXT.search(m.group(0)) or JA_PUNCT.search(m.group(0))) and not LEAK_SKIP_BEFORE.search(line[:m.start()]) and "\\(" not in line[:m.start()][-3:]:
                    errors.append(f"strings: {path.relative_to(ROOT)}:{number}: 日本語の文字列が tr() で包まれていない: {m.group(0)[:40]}"
                                  "（UI なら tr(\"…\") にする。言語の決まりに使う語なら行末に // skip-tr）")


WINDOWS_APP_DIRS = ["windows/Hanasu.Windows", "windows/Hanasu.Core", "windows/Hanasu.Whisper", "windows/Hanasu.Diarization"]


def check_windows_strings(errors: list[str]) -> None:
    import subprocess
    result = subprocess.run([sys.executable, str(ROOT / "scripts/i18n-resx.py"), "check"], capture_output=True, text=True)
    if result.returncode != 0:
        for line in (result.stdout + result.stderr).splitlines():
            if line.startswith("error"):
                errors.append("resx: " + line.removeprefix("error:").strip())
        if not any(e.startswith("resx: ") for e in errors):
            errors.append("resx: scripts/i18n-resx.py check が失敗した")
    literal = re.compile(r'"(?:[^"\\\n]|\\.)*"')
    for folder in WINDOWS_APP_DIRS:
        for path in sorted((ROOT / folder).rglob("*")):
            if path.suffix not in (".cs", ".xaml") or "/obj/" in str(path) or "/bin/" in str(path):
                continue
            previous = ""
            for number, line in enumerate(path.read_text(encoding="utf-8").split("\n"), start=1):
                stripped = line.lstrip()
                skip = ("skip-tr" in line or (path.suffix == ".xaml" and "skip-tr" in previous) or stripped.startswith("//")
                        or stripped.startswith("<!--") or "AppLog." in line)
                previous = line
                if skip:
                    continue
                for m in literal.finditer(line):
                    if JA_TEXT.search(m.group(0)):
                        errors.append(f"resx: {path.relative_to(ROOT)}:{number}: 日本語の文字列が .resx に移されていない: {m.group(0)[:40]}"
                                      "（UI なら Strings.resx に。言語の決まりに使う語なら行に skip-tr）")


README_NAMES = {"en": "README.md", **{lang: f"README.{lang}.md" for lang in LANGUAGES if lang != "en"}}
# 訳が README.md と同じ形かを見る印（表の行・キー・画像・コードブロック・折りたたみ・リンク）
README_MARKS = {
    "表の行": re.compile(r"^\|", re.M),
    "<kbd>": re.compile(r"<kbd>"),
    "<img": re.compile(r"<img"),
    "```": re.compile(r"^```", re.M),
    "<details>": re.compile(r"<details>"),
    "リンク": re.compile(r"\]\((?!README)[^)]+\)"),
}


def check_readmes(errors: list[str]) -> None:
    """README の 17 言語がそろい、言語の切り替えがあり、README.md と同じ形か（docs/README.md の 8 章）"""
    texts: dict[str, str] = {}
    for language, name in README_NAMES.items():
        path = ROOT / name
        if not path.exists():
            errors.append(f"readme: {name} がない")
            continue
        texts[language] = path.read_text(encoding="utf-8")
    base = texts.get("en")
    if base is None:
        return
    want = {label: len(p.findall(base)) for label, p in README_MARKS.items()}
    for language, body in texts.items():
        name = README_NAMES[language]
        switcher = next((line for line in body.splitlines() if "README.zh-CN.md" in line or "(README.md)" in line), "")
        for other, other_name in README_NAMES.items():
            if other != language and f"]({other_name})" not in switcher:
                errors.append(f"readme: {name} の言語の切り替えに {other_name} へのリンクがない")
        if language == "en":
            continue
        for label, pattern in README_MARKS.items():
            got = len(pattern.findall(body))
            if got != want[label]:
                errors.append(f"readme: {name} の{label}の数が README.md と違う（README.md: {want[label]}、{name}: {got}）"
                              " → README.md の変更を訳に入れる")


def main(argv: list[str]) -> int:
    errors: list[str] = []
    warnings: list[str] = []
    counts: dict[str, int] = {}
    check_prompts(errors, warnings, counts)
    check_mac_strings(errors, warnings, counts)
    check_windows_strings(errors)
    check_readmes(errors)

    if "--summary" in argv:
        print("プロンプトのキーの数: " + ", ".join(f"{k} {v}" for k, v in counts.items() if not k.startswith("strings:")))
        print("Mac の UI の訳の数: " + ", ".join(f"{k[8:]} {v}" for k, v in counts.items() if k.startswith("strings:")))
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
