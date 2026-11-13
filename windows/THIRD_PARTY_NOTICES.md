# Third-party notices（Windows 版）

Hanasu は PolyForm Noncommercial License 1.0.0（同梱の `LICENSE.txt`）と Hanasu 追加の許可 1.0（同梱の `LICENSE-ADDITIONAL-PERMISSION.md`）で配布します（このライセンスに変える前の版は Apache License 2.0）。
配布する Windows 版（`Hanasu-<版>-Windows-x64.zip` の `Hanasu` フォルダ）には、次の第三者のソフトウェアが組み込まれています。それぞれのライセンスに従って表示します。

| ソフトウェア | 版 | 配布物の中 | ライセンス |
| --- | --- | --- | --- |
| .NET ランタイム（self-contained で `Hanasu.exe` に入る） | 8.0 | `Hanasu.exe` | MIT（ランタイムが含む第三者のコードは `dotnet-THIRD-PARTY-NOTICES.txt`） |
| System.Security.Cryptography.ProtectedData | 8.0.0 | `Hanasu.exe` | MIT |
| System.Management・System.CodeDom（動いている AI アプリの起動の引数を読む） | 8.0.0・8.0.0 | `Hanasu.exe` | MIT |
| Microsoft.Win32.SystemEvents（`hanasu` のコマンド） | 8.0.0 | `cli\hanasu.exe` | MIT |
| [NAudio](https://github.com/naudio/NAudio)（NAudio.Wasapi / NAudio.Core） | 2.2.1 | `Hanasu.exe` | MIT |
| [Whisper.net](https://github.com/sandrohanea/whisper.net) | 1.9.1 | `Hanasu.exe` | MIT |
| [whisper.cpp / ggml](https://github.com/ggml-org/whisper.cpp)（Whisper.net.Runtime に入っている） | Whisper.net.Runtime 1.9.1 | `runtimes/win-x64/*.dll` | MIT |
| [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) | 2.0.1 | `Hanasu.exe`、`sherpa-onnx-c-api.dll` | Apache-2.0（静的にリンクされたものは下の表） |
| [Anthropic C# SDK](https://github.com/anthropics/anthropic-sdk-csharp)（NuGet の Anthropic） | 13.4.0 | `Hanasu.exe` | Apache-2.0 |
| Microsoft.Extensions.AI.Abstractions（Anthropic SDK の依存） | 10.5.1 | `Hanasu.exe` | MIT |
| System.Text.Json・System.Text.Encodings.Web・System.IO.Pipelines・System.Net.ServerSentEvents（Anthropic SDK の依存） | 10.0.6・10.0.6・10.0.6・10.0.1 | `Hanasu.exe` | MIT |
| [ONNX Runtime](https://github.com/microsoft/onnxruntime)（sherpa-onnx に入っている） | 1.28.2 | `onnxruntime.dll` | MIT（中に入っているものは下の表） |
| [llama.cpp / ggml](https://github.com/ggml-org/llama.cpp)（ローカルの LLM を動かす `llama-server`） | b11770 | `llama/llama-server.exe`、`llama/*.dll` | MIT |
| [LLVM OpenMP](https://github.com/llvm/llvm-project/tree/main/openmp)（llama.cpp の Windows 版に入っている） | llama.cpp b11770 に同梱の版 | `llama/libomp.dll` | Apache-2.0 WITH LLVM-exception（条文は `llama/LICENSE-LLVM-OpenMP`） |

`onnxruntime.dll` と `sherpa-onnx-c-api.dll` には、次のソフトウェアが静的にリンクされています（ビルドのソースのパスと DLL の中の文字列で確かめたもの。ONNX Runtime が含む第三者のソフトウェアの完全な一覧は、[ONNX Runtime 1.28.2 の ThirdPartyNotices.txt](https://github.com/microsoft/onnxruntime/blob/v1.28.2/ThirdPartyNotices.txt)）。

| ソフトウェア | 版 | 配布物の中 | ライセンス |
| --- | --- | --- | --- |
| [Eigen](https://gitlab.com/libeigen/eigen) | 3.4.0（kaldi-decoder）・ONNX Runtime に同梱の版 | `onnxruntime.dll`、`sherpa-onnx-c-api.dll` | MPL-2.0（MPL-2.0 のファイルだけを変えずに使う。下の「Mozilla Public License 2.0」の節） |
| [Abseil](https://github.com/abseil/abseil-cpp) | ONNX Runtime に同梱の版 | `onnxruntime.dll` | Apache-2.0 |
| [Protocol Buffers](https://github.com/protocolbuffers/protobuf) | ONNX Runtime に同梱の版 | `onnxruntime.dll` | BSD-3-Clause |
| [ONNX](https://github.com/onnx/onnx) | ONNX Runtime に同梱の版 | `onnxruntime.dll` | Apache-2.0 |
| [RE2](https://github.com/google/re2) | ONNX Runtime に同梱の版 | `onnxruntime.dll` | BSD-3-Clause |
| [FlatBuffers](https://github.com/google/flatbuffers) | ONNX Runtime に同梱の版 | `onnxruntime.dll` | Apache-2.0 |
| [cpuinfo](https://github.com/pytorch/cpuinfo) | ONNX Runtime に同梱の版 | `onnxruntime.dll` | BSD-2-Clause |
| [PyTorch](https://github.com/pytorch/pytorch)（一部の演算の実装の元） | ONNX Runtime に同梱の版 | `onnxruntime.dll` | BSD-3-Clause |
| [Windows Implementation Libraries](https://github.com/microsoft/wil) | ONNX Runtime に同梱の版 | `onnxruntime.dll` | MIT |
| [SafeInt](https://github.com/dcleblanc/SafeInt) | ONNX Runtime に同梱の版 | `onnxruntime.dll` | MIT |
| [Guidelines Support Library](https://github.com/microsoft/GSL) | ONNX Runtime に同梱の版 | `onnxruntime.dll` | MIT |
| [date](https://github.com/HowardHinnant/date)（Howard Hinnant） | ONNX Runtime に同梱の版 | `onnxruntime.dll` | MIT |
| [Boost.Mp11](https://github.com/boostorg/mp11) | ONNX Runtime に同梱の版 | `onnxruntime.dll` | BSL-1.0 |
| [nlohmann/json](https://github.com/nlohmann/json) | 3.11.3・3.12.0 | `onnxruntime.dll`、`sherpa-onnx-c-api.dll` | MIT |
| [kaldi-native-fbank](https://github.com/csukuangfj/kaldi-native-fbank) | 1.22.4 | `sherpa-onnx-c-api.dll` | Apache-2.0 |
| [kaldi-decoder](https://github.com/k2-fsa/kaldi-decoder) | 0.3.0 | `sherpa-onnx-c-api.dll` | Apache-2.0 |
| [kaldifst](https://github.com/k2-fsa/kaldifst) | 1.8.0 | `sherpa-onnx-c-api.dll` | Apache-2.0 |
| [OpenFst](https://github.com/csukuangfj/openfst) | kaldifst 1.8.0 に同梱の版 | `sherpa-onnx-c-api.dll` | Apache-2.0 |
| [simple-sentencepiece](https://github.com/pkufool/simple-sentencepiece) | 0.7 | `sherpa-onnx-c-api.dll` | Apache-2.0 |
| [darts-clone](https://github.com/s-yata/darts-clone)（simple-sentencepiece に入っている） | simple-sentencepiece 0.7 に同梱の版 | `sherpa-onnx-c-api.dll` | BSD-2-Clause |
| [utf8proc](https://github.com/JuliaStrings/utf8proc) | 2.12.0 | `sherpa-onnx-c-api.dll` | MIT（Unicode のデータは Unicode のライセンス） |
| [fastcluster](https://github.com/csukuangfj/hclust-cpp)（hclust-cpp） | 2026-02-25 | `sherpa-onnx-c-api.dll` | BSD-2-Clause |

v1.3.0〜v2.6.1 の Windows 版の `sherpa-onnx-c-api.dll`（sherpa-onnx 1.13.8）は、使っていない音声合成（TTS）の部分として espeak-ng（GPL-3.0）を含んでいました。これらの版の Windows の zip は配布を取り下げました。そのソースは sherpa-onnx v1.13.8（https://github.com/k2-fsa/sherpa-onnx/tree/v1.13.8）と、その `cmake/espeak-ng-for-piper.cmake` が取る espeak-ng（https://github.com/csukuangfj/espeak-ng のコミット ed530aa113046142eb5115cf2fc9157854d0ffe1）です。

次のモデルは配布物に含めません。利用者が選んだとき（または初めて使うとき）に、ダウンロード元から取得します。ライセンスはダウンロード元の表示に従います。

- Whisper のモデル（`ggml-*.bin`、[ggerganov/whisper.cpp](https://huggingface.co/ggerganov/whisper.cpp)。OpenAI Whisper のモデル、MIT）
- 話者分離のモデル: [pyannote segmentation-3.0 の ONNX 版](https://huggingface.co/csukuangfj/sherpa-onnx-pyannote-segmentation-3-0)（MIT）、[3D-Speaker の CAM++](https://github.com/k2-fsa/sherpa-onnx/releases/tag/speaker-recongition-models)（Apache-2.0）
- ローカルの LLM のモデル（設定 → AI で利用者がダウンロード）: [Gemma 4 E4B](https://huggingface.co/ggml-org/gemma-4-E4B-it-GGUF)（Apache-2.0）、[LFM2.5-1.2B-JP](https://huggingface.co/LiquidAI/LFM2.5-1.2B-JP-202606-GGUF)（LFM Open License v1.0。年間売上 1,000 万ドル以上の組織の商用利用は、このライセンスでは許されていません）、[Sarashina2.2 3B](https://huggingface.co/mmnga/sarashina2.2-3b-instruct-v0.1-gguf)（MIT）、[Qwen3.5-4B](https://huggingface.co/unsloth/Qwen3.5-4B-GGUF)（Apache-2.0）

---

## MIT License の各ソフトウェア

次の著作権表示のそれぞれに、下の MIT License の条文が適用されます。

- .NET ランタイム、System.Security.Cryptography.ProtectedData、System.Management、System.CodeDom、Microsoft.Win32.SystemEvents、Microsoft.Extensions.AI.Abstractions、System.Text.Json、System.Text.Encodings.Web、System.IO.Pipelines、System.Net.ServerSentEvents: Copyright (c) .NET Foundation and Contributors
- NAudio: Copyright (c) 2020 Mark Heath
- Whisper.net: Copyright (c) 2024 sandrohanea
- whisper.cpp / ggml: Copyright (c) 2023-2024 The ggml authors
- llama.cpp / ggml: Copyright (c) 2023-2026 The ggml authors
- ONNX Runtime: Copyright (c) Microsoft Corporation
- Windows Implementation Libraries: Copyright (c) Microsoft Corporation. All rights reserved.
- SafeInt: Copyright (c) 2018 Microsoft
- Guidelines Support Library: Copyright (c) 2015 Microsoft Corporation. All rights reserved.
- date: Copyright (c) 2015, 2016, 2017 Howard Hinnant ほか、各ファイルに書かれた作者
- nlohmann/json: Copyright (c) 2013-2026 Niels Lohmann
- utf8proc: Copyright (c) 2014-2021 by Steven G. Johnson, Jiahao Chen, Tony Kelman, Jonas Fonseca, and other contributors listed in the git history. / Copyright (c) 2009, 2013 Public Software Group e. V., Berlin, Germany
- Anthropic C# SDK（13.0.0 で Apache-2.0 に変わる前に入った第三者の貢献の分。パッケージの LICENSE-MIT）: Copyright 2023 Anthropic, PBC.

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
- Anthropic C# SDK: Copyright 2023 Anthropic, PBC（13.0.0 から Apache-2.0。それより前にリポジトリに入った第三者の貢献には、上の MIT License の節の表示も当てはまる）
- Abseil: Copyright 2017 The Abseil Authors.
- ONNX: Copyright (c) ONNX Project Contributors
- FlatBuffers: Copyright 2014 Google Inc. All rights reserved.
- kaldi-native-fbank: Copyright (c) 2022 Xiaomi Corporation (authors: Fangjun Kuang)
- kaldi-decoder: Copyright (c) 2023 Xiaomi Corporation
- kaldifst: Kaldi の作者（各ファイルに書かれた作者。例: Copyright 2009-2011 Microsoft Corporation）
- OpenFst: Google LLC と OpenFst の作者
- simple-sentencepiece: Copyright 2024 Wei Kang

次の条文が、上のそれぞれに適用されます（Hanasu 自身のライセンスは Apache License 2.0 ではありません）。

```
                                 Apache License
                           Version 2.0, January 2004
                        https://www.apache.org/licenses/

   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

   1. Definitions.

      "License" shall mean the terms and conditions for use, reproduction,
      and distribution as defined by Sections 1 through 9 of this document.

      "Licensor" shall mean the copyright owner or entity authorized by
      the copyright owner that is granting the License.

      "Legal Entity" shall mean the union of the acting entity and all
      other entities that control, are controlled by, or are under common
      control with that entity. For the purposes of this definition,
      "control" means (i) the power, direct or indirect, to cause the
      direction or management of such entity, whether by contract or
      otherwise, or (ii) ownership of fifty percent (50%) or more of the
      outstanding shares, or (iii) beneficial ownership of such entity.

      "You" (or "Your") shall mean an individual or Legal Entity
      exercising permissions granted by this License.

      "Source" form shall mean the preferred form for making modifications,
      including but not limited to software source code, documentation
      source, and configuration files.

      "Object" form shall mean any form resulting from mechanical
      transformation or translation of a Source form, including but
      not limited to compiled object code, generated documentation,
      and conversions to other media types.

      "Work" shall mean the work of authorship, whether in Source or
      Object form, made available under the License, as indicated by a
      copyright notice that is included in or attached to the work
      (an example is provided in the Appendix below).

      "Derivative Works" shall mean any work, whether in Source or Object
      form, that is based on (or derived from) the Work and for which the
      editorial revisions, annotations, elaborations, or other modifications
      represent, as a whole, an original work of authorship. For the purposes
      of this License, Derivative Works shall not include works that remain
      separable from, or merely link (or bind by name) to the interfaces of,
      the Work and Derivative Works thereof.

      "Contribution" shall mean any work of authorship, including
      the original version of the Work and any modifications or additions
      to that Work or Derivative Works thereof, that is intentionally
      submitted to Licensor for inclusion in the Work by the copyright owner
      or by an individual or Legal Entity authorized to submit on behalf of
      the copyright owner. For the purposes of this definition, "submitted"
      means any form of electronic, verbal, or written communication sent
      to the Licensor or its representatives, including but not limited to
      communication on electronic mailing lists, source code control systems,
      and issue tracking systems that are managed by, or on behalf of, the
      Licensor for the purpose of discussing and improving the Work, but
      excluding communication that is conspicuously marked or otherwise
      designated in writing by the copyright owner as "Not a Contribution."

      "Contributor" shall mean Licensor and any individual or Legal Entity
      on behalf of whom a Contribution has been received by Licensor and
      subsequently incorporated within the Work.

   2. Grant of Copyright License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      copyright license to reproduce, prepare Derivative Works of,
      publicly display, publicly perform, sublicense, and distribute the
      Work and such Derivative Works in Source or Object form.

   3. Grant of Patent License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      (except as stated in this section) patent license to make, have made,
      use, offer to sell, sell, import, and otherwise transfer the Work,
      where such license applies only to those patent claims licensable
      by such Contributor that are necessarily infringed by their
      Contribution(s) alone or by combination of their Contribution(s)
      with the Work to which such Contribution(s) was submitted. If You
      institute patent litigation against any entity (including a
      cross-claim or counterclaim in a lawsuit) alleging that the Work
      or a Contribution incorporated within the Work constitutes direct
      or contributory patent infringement, then any patent licenses
      granted to You under this License for that Work shall terminate
      as of the date such litigation is filed.

   4. Redistribution. You may reproduce and distribute copies of the
      Work or Derivative Works thereof in any medium, with or without
      modifications, and in Source or Object form, provided that You
      meet the following conditions:

      (a) You must give any other recipients of the Work or
          Derivative Works a copy of this License; and

      (b) You must cause any modified files to carry prominent notices
          stating that You changed the files; and

      (c) You must retain, in the Source form of any Derivative Works
          that You distribute, all copyright, patent, trademark, and
          attribution notices from the Source form of the Work,
          excluding those notices that do not pertain to any part of
          the Derivative Works; and

      (d) If the Work includes a "NOTICE" text file as part of its
          distribution, then any Derivative Works that You distribute must
          include a readable copy of the attribution notices contained
          within such NOTICE file, excluding those notices that do not
          pertain to any part of the Derivative Works, in at least one
          of the following places: within a NOTICE text file distributed
          as part of the Derivative Works; within the Source form or
          documentation, if provided along with the Derivative Works; or,
          within a display generated by the Derivative Works, if and
          wherever such third-party notices normally appear. The contents
          of the NOTICE file are for informational purposes only and
          do not modify the License. You may add Your own attribution
          notices within Derivative Works that You distribute, alongside
          or as an addendum to the NOTICE text from the Work, provided
          that such additional attribution notices cannot be construed
          as modifying the License.

      You may add Your own copyright statement to Your modifications and
      may provide additional or different license terms and conditions
      for use, reproduction, or distribution of Your modifications, or
      for any such Derivative Works as a whole, provided Your use,
      reproduction, and distribution of the Work otherwise complies with
      the conditions stated in this License.

   5. Submission of Contributions. Unless You explicitly state otherwise,
      any Contribution intentionally submitted for inclusion in the Work
      by You to the Licensor shall be under the terms and conditions of
      this License, without any additional terms or conditions.
      Notwithstanding the above, nothing herein shall supersede or modify
      the terms of any separate license agreement you may have executed
      with Licensor regarding such Contributions.

   6. Trademarks. This License does not grant permission to use the trade
      names, trademarks, service marks, or product names of the Licensor,
      except as required for reasonable and customary use in describing the
      origin of the Work and reproducing the content of the NOTICE file.

   7. Disclaimer of Warranty. Unless required by applicable law or
      agreed to in writing, Licensor provides the Work (and each
      Contributor provides its Contributions) on an "AS IS" BASIS,
      WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
      implied, including, without limitation, any warranties or conditions
      of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A
      PARTICULAR PURPOSE. You are solely responsible for determining the
      appropriateness of using or redistributing the Work and assume any
      risks associated with Your exercise of permissions under this License.

   8. Limitation of Liability. In no event and under no legal theory,
      whether in tort (including negligence), contract, or otherwise,
      unless required by applicable law (such as deliberate and grossly
      negligent acts) or agreed to in writing, shall any Contributor be
      liable to You for damages, including any direct, indirect, special,
      incidental, or consequential damages of any character arising as a
      result of this License or out of the use or inability to use the
      Work (including but not limited to damages for loss of goodwill,
      work stoppage, computer failure or malfunction, or any and all
      other commercial damages or losses), even if such Contributor
      has been advised of the possibility of such damages.

   9. Accepting Warranty or Additional Liability. While redistributing
      the Work or Derivative Works thereof, You may choose to offer,
      and charge a fee for, acceptance of support, warranty, indemnity,
      or other liability obligations and/or rights consistent with this
      License. However, in accepting such obligations, You may act only
      on Your own behalf and on Your sole responsibility, not on behalf
      of any other Contributor, and only if You agree to indemnify,
      defend, and hold each Contributor harmless for any liability
      incurred by, or claims asserted against, such Contributor by reason
      of your accepting any such warranty or additional liability.

   END OF TERMS AND CONDITIONS

   APPENDIX: How to apply the Apache License to your work.

      To apply the Apache License to your work, attach the following
      boilerplate notice, with the fields enclosed by brackets "[]"
      replaced with your own identifying information. (Don't include
      the brackets!)  The text should be enclosed in the appropriate
      comment syntax for the file format. We also recommend that a
      file or class name and description of purpose be included on the
      same "printed page" as the copyright notice for easier
      identification within third-party archives.

   Copyright [yyyy] [name of copyright owner]

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       https://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
```

## BSD License の各ソフトウェア

### Protocol Buffers — BSD-3-Clause

```
Copyright 2008 Google Inc.  All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

    * Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
copyright notice, this list of conditions and the following disclaimer
in the documentation and/or other materials provided with the
distribution.
    * Neither the name of Google Inc. nor the names of its
contributors may be used to endorse or promote products derived from
this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

Code generated by the Protocol Buffer compiler is owned by the owner
of the input file used when generating it.  This code is not
standalone and requires a support library to be linked with it.  This
support library is itself covered by the above license.
```

### RE2 — BSD-3-Clause

```
Copyright (c) 2009 The RE2 Authors. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

   * Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimer.
   * Redistributions in binary form must reproduce the above
copyright notice, this list of conditions and the following disclaimer
in the documentation and/or other materials provided with the
distribution.
   * Neither the name of Google Inc. nor the names of its
contributors may be used to endorse or promote products derived from
this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

### PyTorch — BSD-3-Clause

```
From PyTorch:

Copyright (c) 2016-     Facebook, Inc            (Adam Paszke)
Copyright (c) 2014-     Facebook, Inc            (Soumith Chintala)
Copyright (c) 2011-2014 Idiap Research Institute (Ronan Collobert)
Copyright (c) 2012-2014 Deepmind Technologies    (Koray Kavukcuoglu)
Copyright (c) 2011-2012 NEC Laboratories America (Koray Kavukcuoglu)
Copyright (c) 2011-2013 NYU                      (Clement Farabet)
Copyright (c) 2006-2010 NEC Laboratories America (Ronan Collobert, Leon Bottou, Iain Melvin, Jason Weston)
Copyright (c) 2006      Idiap Research Institute (Samy Bengio)
Copyright (c) 2001-2004 Idiap Research Institute (Ronan Collobert, Samy Bengio, Johnny Mariethoz)

From Caffe2:

Copyright (c) 2016-present, Facebook Inc. All rights reserved.

All contributions by Facebook:
Copyright (c) 2016 Facebook Inc.

All contributions by Google:
Copyright (c) 2015 Google Inc.
All rights reserved.

All contributions by Yangqing Jia:
Copyright (c) 2015 Yangqing Jia
All rights reserved.

All contributions by Kakao Brain:
Copyright 2019-2020 Kakao Brain

All contributions by Cruise LLC:
Copyright (c) 2022 Cruise LLC.
All rights reserved.

All contributions by Tri Dao:
Copyright (c) 2024 Tri Dao.
All rights reserved.

All contributions by Arm:
Copyright (c) 2021, 2023-2025 Arm Limited and/or its affiliates

All contributions from Caffe:
Copyright(c) 2013, 2014, 2015, the respective contributors
All rights reserved.

All other contributions:
Copyright(c) 2015, 2016 the respective contributors
All rights reserved.

Caffe2 uses a copyright model similar to Caffe: each contributor holds
copyright over their contributions to Caffe2. The project versioning records
all such contribution and copyright details. If a contributor wants to further
mark their specific copyright on a particular contribution, they should
indicate their copyright solely in the commit message of the change when it is
committed.

All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

3. Neither the names of Facebook, Deepmind Technologies, NYU, NEC Laboratories America
   and IDIAP Research Institute nor the names of its contributors may be
   used to endorse or promote products derived from this software without
   specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.
```

### cpuinfo — BSD-2-Clause

```
Copyright (c) 2019 Google LLC
Copyright (c) 2017-2018 Facebook Inc.
Copyright (C) 2012-2017 Georgia Institute of Technology
Copyright (C) 2010-2012 Marat Dukhan

All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

### darts-clone — BSD-2-Clause

```
# The BSD 2-clause license

Copyright (c) 2008-2014, Susumu Yata
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
* Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

### fastcluster（hclust-cpp）— BSD-2-Clause

```
Copyright:
  * fastcluster_dm.cpp & fastcluster_R_dm.cpp:
     © 2011 Daniel Müllner <http://danifold.net>
  * fastcluster.(h|cpp) & demo.cpp & plotresult.r:
     © 2018 Christoph Dalitz <http://www.hsnr.de/ipattern/>
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

  * Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
  * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## utf8proc の Unicode のデータ — Unicode のライセンス

utf8proc の `utf8proc_data.c` は Unicode のデータファイルから作られています。そのデータには次の表示が適用されます。

```
This software contains data (`utf8proc_data.c`) derived from processing
the Unicode data files. The following license applies to that data:

**COPYRIGHT AND PERMISSION NOTICE**

*Copyright (c) 1991-2007 Unicode, Inc. All rights reserved. Distributed
under the Terms of Use in http://www.unicode.org/copyright.html.*

Permission is hereby granted, free of charge, to any person obtaining a
copy of the Unicode data files and any associated documentation (the "Data
Files") or Unicode software and any associated documentation (the
"Software") to deal in the Data Files or Software without restriction,
including without limitation the rights to use, copy, modify, merge,
publish, distribute, and/or sell copies of the Data Files or Software, and
to permit persons to whom the Data Files or Software are furnished to do
so, provided that (a) the above copyright notice(s) and this permission
notice appear with all copies of the Data Files or Software, (b) both the
above copyright notice(s) and this permission notice appear in associated
documentation, and (c) there is clear notice in each modified Data File or
in the Software as well as in the documentation associated with the Data
File(s) or Software that the data or software has been modified.

THE DATA FILES AND SOFTWARE ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY
KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF
THIRD PARTY RIGHTS. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR HOLDERS
INCLUDED IN THIS NOTICE BE LIABLE FOR ANY CLAIM, OR ANY SPECIAL INDIRECT OR
CONSEQUENTIAL DAMAGES, OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF
USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER
TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
PERFORMANCE OF THE DATA FILES OR SOFTWARE.

Except as contained in this notice, the name of a copyright holder shall
not be used in advertising or otherwise to promote the sale, use or other
dealings in these Data Files or Software without prior written
authorization of the copyright holder.

Unicode and the Unicode logo are trademarks of Unicode, Inc., and may be
registered in some jurisdictions. All other trademarks and registered
trademarks mentioned herein are the property of their respective owners.
```

## Boost.Mp11 — Boost Software License 1.0

```
Boost Software License - Version 1.0 - August 17th, 2003

Permission is hereby granted, free of charge, to any person or organization
obtaining a copy of the software and accompanying documentation covered by
this license (the "Software") to use, reproduce, display, distribute,
execute, and transmit the Software, and to prepare derivative works of the
Software, and to permit third-parties to whom the Software is furnished to
do so, all subject to the following:

The copyright notices in the Software and this entire statement, including
the above license grant, this restriction and the following disclaimer,
must be included in all copies of the Software, in whole or in part, and
all derivative works of the Software, unless such copies or derivative
works are solely in the form of machine-executable object code generated by
a source language processor.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
```

## Eigen — Mozilla Public License 2.0

`onnxruntime.dll` と `sherpa-onnx-c-api.dll` には、Eigen（ヘッダーだけの C++ のライブラリ）のコードが、変えずにコンパイルされて入っています。ONNX Runtime は `EIGEN_MPL2_ONLY` を付けてビルドされ、kaldi-decoder は `Eigen/Dense` だけを読むので、使っているのは MPL-2.0 のファイルだけです。

- ライセンス: Mozilla Public License, v. 2.0（条文: https://mozilla.org/MPL/2.0/ ）
- ソースコードの入手先: https://gitlab.com/libeigen/eigen （kaldi-decoder が使う版は 3.4.0: https://gitlab.com/libeigen/eigen/-/archive/3.4.0/eigen-3.4.0.tar.gz 。ONNX Runtime が使う版は ONNX Runtime 1.28.2 の `cmake/deps.txt` に書かれたもの）
