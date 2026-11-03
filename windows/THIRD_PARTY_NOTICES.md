# Third-party notices（Windows 版）

Hanasu は Apache License 2.0（同梱の `LICENSE.txt`）で配布します。
配布する Windows 版（`Hanasu-<版>-Windows-x64.zip` の `Hanasu` フォルダ）には、次の第三者のソフトウェアが組み込まれています。それぞれのライセンスに従って表示します。

| ソフトウェア | 版 | 配布物の中 | ライセンス |
| --- | --- | --- | --- |
| .NET ランタイム（self-contained で `Hanasu.exe` に入る） | 8.0 | `Hanasu.exe` | MIT（ランタイムが含む第三者のコードは `dotnet-THIRD-PARTY-NOTICES.txt`） |
| System.Security.Cryptography.ProtectedData | 8.0.0 | `Hanasu.exe` | MIT |
| [NAudio](https://github.com/naudio/NAudio)（NAudio.Wasapi / NAudio.Core） | 2.2.1 | `Hanasu.exe` | MIT |
| [Whisper.net](https://github.com/sandrohanea/whisper.net) | 1.9.1 | `Hanasu.exe` | MIT |
| [whisper.cpp / ggml](https://github.com/ggml-org/whisper.cpp)（Whisper.net.Runtime に入っている） | Whisper.net.Runtime 1.9.1 | `runtimes/win-x64/*.dll` | MIT |
| [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) | 1.13.8 | `Hanasu.exe`、`sherpa-onnx-c-api.dll` | Apache-2.0 |
| [ONNX Runtime](https://github.com/microsoft/onnxruntime)（sherpa-onnx に入っている） | sherpa-onnx 1.13.8 に同梱の版 | `onnxruntime.dll` | MIT |

次のモデルは配布物に含めません。利用者が選んだとき（または初めて使うとき）に、ダウンロード元から取得します。ライセンスはダウンロード元の表示に従います。

- Whisper のモデル（`ggml-*.bin`、[ggerganov/whisper.cpp](https://huggingface.co/ggerganov/whisper.cpp)。OpenAI Whisper のモデル、MIT）
- 話者分離のモデル: [pyannote segmentation-3.0 の ONNX 版](https://huggingface.co/csukuangfj/sherpa-onnx-pyannote-segmentation-3-0)（MIT）、[3D-Speaker の CAM++](https://github.com/k2-fsa/sherpa-onnx/releases/tag/speaker-recongition-models)（Apache-2.0）

---

## MIT License の各ソフトウェア

次の著作権表示のそれぞれに、下の MIT License の条文が適用されます。

- .NET ランタイム、System.Security.Cryptography.ProtectedData: Copyright (c) .NET Foundation and Contributors
- NAudio: Copyright (c) 2020 Mark Heath
- Whisper.net: Copyright (c) 2024 sandrohanea
- whisper.cpp / ggml: Copyright (c) 2023-2024 The ggml authors
- ONNX Runtime: Copyright (c) Microsoft Corporation

```
MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Apache License 2.0 の各ソフトウェア

- sherpa-onnx: Copyright 2019-2023 Xiaomi Corporation

条文は同梱の `LICENSE.txt`（Hanasu 自身のライセンスと同じ Apache License 2.0）にあります。
