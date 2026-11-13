# 文体を学ぶ機能のテストデータ

REQ-DIC-022・023 を確かめるためのデータ。Mac（`.build/debug/Hanasu --test-custom-styles`）と Windows（`CustomStyleTests`）が同じものを読む。

| ファイル | 中身 |
| --- | --- |
| `plain-comma.txt` | 特徴のはっきりした材料（である調・読点に「，」）。実際の AI で学ばせ、整形の出力がその文体になるかを確かめる（REQ-DIC-023 の受け入れ条件） |
| `reading/` | 文字コード・形式の違うファイル（DEC-DIC-211）。`make-fixtures.py` が作る（手で直さない） |
| `cases.json` | `reading/` の各ファイルを読んだときに期待する本文か、読めない理由。`make-fixtures.py` が書く |

作り直すとき: `python3 common/testdata/style/make-fixtures.py`

`reading/` は `.gitattributes` でバイナリにしている（Windows の改行の変換で、読み込みのテストが変わらないように）。20 MB を超えるファイルはテストの中で作る。
