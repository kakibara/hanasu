#!/usr/bin/env python3
"""文体を学ぶ材料の読み込み（REQ-DIC-022・DEC-DIC-211）の固定のファイルを作る。

    python3 common/testdata/style/make-fixtures.py

reading/ に、文字コード・形式の違うファイルを作り、cases.json に「読んだら期待する本文」か「読めない理由」を書く。
Mac（--test-custom-styles）と Windows（CustomStyleTests）が同じ cases.json で確かめる。
20 MB を超えるファイルは大きいので、テストの中で作る。
"""
import json
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
READING = HERE / "reading"

TEXT = "文体の見本です。\r\n二行目は，読点に全角のカンマを使う。\r\n\r\n段落を分けた三行目。"
TEXT_LF = TEXT.replace("\r\n", "\n")


def write_texts():
    (READING / "utf8.txt").write_bytes(TEXT_LF.encode("utf-8"))
    (READING / "utf8-bom.txt").write_bytes(b"\xef\xbb\xbf" + TEXT.encode("utf-8"))
    (READING / "utf16le.txt").write_bytes(b"\xff\xfe" + TEXT.encode("utf-16-le"))
    (READING / "utf16be.txt").write_bytes(b"\xfe\xff" + TEXT.encode("utf-16-be"))
    (READING / "sjis.txt").write_bytes(TEXT.encode("cp932"))
    (READING / "cr.txt").write_bytes(TEXT.replace("\r\n", "\r").encode("utf-8"))
    md = "# 見出し\n\n- 箇条書きの記号は残す\n- **太字** も記号のまま\n\n本文の段落。\n"
    (READING / "sample.md").write_bytes(md.encode("utf-8"))
    (READING / "sample.markdown").write_bytes(md.encode("utf-8"))
    (READING / "sample.rtf").write_bytes(b"{\\rtf1\\ansi hello}")
    return md


W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'

DOCUMENT = f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document {W}><w:body>
<w:p><w:r><w:t>報告書の</w:t></w:r><w:r><w:rPr><w:b/></w:rPr><w:t>書き方</w:t></w:r></w:p>
<w:p><w:r><w:t>一行目</w:t><w:br/><w:t>二行目</w:t><w:cr/><w:t>三行目</w:t></w:r></w:p>
<w:p><w:r><w:t>見出し</w:t><w:tab/><w:t xml:space="preserve"> 本文 </w:t></w:r></w:p>
<w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr><w:r><w:t>番号付きの段落</w:t></w:r></w:p>
<w:tbl><w:tr><w:tc><w:p><w:r><w:t>セル1</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>セル2</w:t></w:r></w:p><w:p><w:r><w:t>セル2の二段落目</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
<w:p/>
<w:p><w:r><w:t>A&amp;B &lt;記号&gt;</w:t></w:r><w:r><w:fldChar w:fldCharType="begin"/></w:r><w:r><w:instrText>PAGE</w:instrText></w:r><w:r><w:fldChar w:fldCharType="end"/></w:r></w:p>
<w:p><w:del><w:r><w:delText>消した文字</w:delText></w:r></w:del><w:ins><w:r><w:t>足した文字</w:t></w:r></w:ins><w:r><w:footnoteReference w:id="1"/></w:r></w:p>
<w:p><w:pPr><w:tabs><w:tab w:val="left" w:pos="720"/></w:tabs></w:pPr><w:r><w:rPr><w:b/></w:rPr><w:t>タブ位置の定義は読まない</w:t></w:r><w:del><w:r><w:tab/><w:br/><w:delText>消した</w:delText></w:r></w:del></w:p>
<w:sectPr/></w:body></w:document>
"""
DOCX_TEXT = "報告書の書き方\n一行目\n二行目\n三行目\n見出し\t 本文 \n番号付きの段落\nセル1\nセル2\nセル2の二段落目\n\nA&B <記号>\n足した文字\nタブ位置の定義は読まない"

CONTENT_TYPES = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>
"""


def entry(name, method=zipfile.ZIP_DEFLATED):
    # 時刻を決めて、作り直しても同じバイトにする
    info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
    info.compress_type = method
    return info


def write_docx(path, document, method=zipfile.ZIP_DEFLATED, extra=None):
    with zipfile.ZipFile(path, "w") as z:
        z.writestr(entry("[Content_Types].xml", method), CONTENT_TYPES)
        for name, data in (extra or {}).items():
            z.writestr(entry(name, method), data)
        z.writestr(entry("word/document.xml", method), document)


def write_docxs():
    extra = {
        "word/header1.xml": f'<w:hdr {W}><w:p><w:r><w:t>ヘッダーは読まない</w:t></w:r></w:p></w:hdr>',
        "word/footnotes.xml": f'<w:footnotes {W}><w:footnote w:id="1"><w:p><w:r><w:t>脚注は読まない</w:t></w:r></w:p></w:footnote></w:footnotes>',
    }
    write_docx(READING / "sample.docx", DOCUMENT, extra=extra)
    write_docx(READING / "stored.docx", DOCUMENT, method=zipfile.ZIP_STORED)
    # 壊れたもの: zip でない
    (READING / "broken.docx").write_bytes(b"PK\x03\x04 this is not a zip file")
    # zip だが word/document.xml がない
    with zipfile.ZipFile(READING / "no-document.docx", "w") as z:
        z.writestr(entry("[Content_Types].xml"), CONTENT_TYPES)
    # DTD を含む（読まない）
    dtd = '<?xml version="1.0"?><!DOCTYPE w:document [<!ENTITY x "xxxxxxxxxx">]>' + f'<w:document {W}><w:body><w:p><w:r><w:t>&x;</w:t></w:r></w:p></w:body></w:document>'
    write_docx(READING / "dtd.docx", dtd)
    # 展開すると 50 MB を超える
    big = f'<w:document {W}><w:body><w:p><w:r><w:t>' + "a" * (50 * 1024 * 1024 + 1) + "</w:t></w:r></w:p></w:body></w:document>"
    write_docx(READING / "bomb.docx", big)


def main():
    READING.mkdir(exist_ok=True)
    md = write_texts()
    write_docxs()
    cases = {
        "_comment": "文体を学ぶ材料の読み込み（DEC-DIC-211）。make-fixtures.py が書く（手で直さない）。text は読んだ本文、error は読めない理由（unsupported・unreadable・tooLarge）",
        "cases": [
            {"file": "utf8.txt", "text": TEXT_LF},
            {"file": "utf8-bom.txt", "text": TEXT_LF},
            {"file": "utf16le.txt", "text": TEXT_LF},
            {"file": "utf16be.txt", "text": TEXT_LF},
            {"file": "sjis.txt", "text": TEXT_LF},
            {"file": "cr.txt", "text": TEXT_LF},
            {"file": "sample.md", "text": md},
            {"file": "sample.markdown", "text": md},
            {"file": "sample.docx", "text": DOCX_TEXT},
            {"file": "stored.docx", "text": DOCX_TEXT},
            {"file": "sample.rtf", "error": "unsupported"},
            {"file": "broken.docx", "error": "unreadable"},
            {"file": "no-document.docx", "error": "unreadable"},
            {"file": "dtd.docx", "error": "unreadable"},
            {"file": "bomb.docx", "error": "tooLarge"},
        ],
    }
    (HERE / "cases.json").write_text(json.dumps(cases, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
