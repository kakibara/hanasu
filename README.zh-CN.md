<div align="center">

<img src="docs/images/icon.png" width="112" alt="Hanasu 图标">

# Hanasu

**自然地说话，就能得到干净、可直接发送的文字，会议纪要也会自动写好。**

适用于 macOS 和 Windows 的语音输入与会议记录应用。它使用设备端语音识别，并结合 Gemini、Claude 或在你自己设备上运行的 AI 模型。

[![Release](https://img.shields.io/github/v/release/kakibara/hanasu?sort=semver&label=release)](https://github.com/kakibara/hanasu/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/kakibara/hanasu/total)](https://github.com/kakibara/hanasu/releases)
[![License](https://img.shields.io/badge/license-PolyForm%20Noncommercial%20%2B%20small%20business-blue)](COMMERCIAL.md)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-000000?logo=apple)
![Windows 10/11](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows)
[![Windows build](https://github.com/kakibara/hanasu/actions/workflows/windows.yml/badge.svg)](https://github.com/kakibara/hanasu/actions/workflows/windows.yml)

[English](README.md) · [日本語](README.ja.md) · **简体中文** · [繁體中文](README.zh-TW.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Italiano](README.it.md) · [Português (Brasil)](README.pt-BR.md) · [Русский](README.ru.md) · [Türkçe](README.tr.md) · [Tiếng Việt](README.vi.md) · [Bahasa Indonesia](README.id.md) · [Polski](README.pl.md) · [العربية](README.ar.md) · [हिन्दी](README.hi.md)

<sub>本文是英文 README 的翻译。如有出入，请以英文 README 为准，它始终是最新的。</sub>

<img src="docs/images/hud.png" width="560" alt="Hanasu 录音 HUD">

</div>

> [!NOTE]
> Hanasu 首先是为**日语**打造的，日语也是测试最充分的语言。
> 应用的界面和给 AI 的指令提供与本 README 相同的 17 种语言。界面跟随系统语言，AI 指令跟随设置中的转写语言。其他语言则使用英语。
> 它也可以把你说的话翻译成自然的**英语**、**日语**或所支持的 17 种语言中的任意一种后再输入。

## 为什么选择 Hanasu

系统自带的听写只会给你原始的转写结果：口头禅和同音字错误都还在，没有标点，每一句"等等，我是说……"也都原样保留。
Hanasu 会把转写结果交给 AI（Gemini、Claude，或你设备上的本地模型），由它修正这些错误并整理文字，然后在光标处输入结果。
它的灵感来自 Typeless、Wispr Flow、Aqua Voice 和 Granola。Hanasu 的源代码是公开的。个人使用和小型企业使用均免费；规模更大的公司需要[商业许可](COMMERCIAL.md)。你可以使用自己的 Gemini 或 Claude API 密钥，也可以运行本地模型——无需 API 密钥，文字也不会离开你的设备。

## 功能

### 🎙️ 语音输入

| | |
| --- | --- |
| **说话 → 润色好的文字** | 按下 <kbd>⌥ Space</kbd> 后说话，再按一次（或点击 **■ 停止**）。Hanasu 会去除口头禅、修正同音字错误、应用你在说话中途的更正，并把文字粘贴到光标处。 |
| **说话，输入翻译后的文字** | 按下 <kbd>⌥⇧ Space</kbd>，或在说话时把 HUD 切换到 **English**、**日本語** 或其他语言。固定的客套话会被自然地翻译，例如 お疲れ様です 会变成 "Hi,"。可在 **设置 → 通用** 中选择提供哪些语言（所支持的 17 种语言均可）。默认为英语。在 Mac 上，可以在 **设置 → 按应用** 中让某个应用一开始就使用其中一种语言。 |
| **混合语言按原样保留** | 默认情况下，你用英语说的部分会保留为英语。你也可以选择把输出统一为日语。 |
| **用语音编辑** | 选中一段文字，按下 <kbd>⌃⌥⌘ E</kbd>，然后说"改得更礼貌一些"、"改成要点列表"或"翻译成英语"。 |
| **按应用切换风格** | 在 Slack 中文字随意而简短，在 Mail 中礼貌并分段，在 Pages、Word 和 Notion 中使用书面语。每个应用的预设都可以修改。 |
| **片段** | 说"邮件签名"，即可原样插入你保存的文字。片段永远不会发送给 AI。 |
| **词典** | 添加专有名词和替换规则，例如 `ストックマーク => Stockmark`。替换规则也会应用到会议的转写文字。在会议笔记中打开一场会议，AI 就能从这场会议中推荐新词条（在 Mac 上，还会参考你的历史记录和最近的会议），你只需添加选中的那些。 |
| **屏幕上下文** *（需手动开启）* | Hanasu 会读取窗口标题和光标周围的文字，让名称与屏幕上已有的内容保持一致。绝不会读取密码输入框。 |
| **选择麦克风** *（Mac）* | 在设置中选择麦克风，或通过 HUD 上的麦克风按钮切换，无需停止录音。 |
| **历史记录** | 搜索过去的结果，并重试失败的项目。历史记录默认保留 30 天，可在设置中修改。在 Mac 上，按 <kbd>⌥⇧ V</kbd> 可再次粘贴上一次的结果。 |
| **没有地方可以粘贴？** | 如果没有任何文本框获得焦点（例如桌面在最前面），Hanasu 会把结果显示在屏幕上，而不是粘贴。你可以从那里复制，或直接在需要的位置按 <kbd>⌘V</kbd>（可以选择结果是否保留在剪贴板中）。 |
| **粘贴没有成功？** | 如果粘贴没有送达任何应用（例如你在录音时切换了窗口），Hanasu 会把最新结果留在剪贴板中，并在 HUD 中提示你。在需要的位置按 <kbd>⌘V</kbd> 即可。你还可以在 设置 → 通用 中设置在这种情况下打开听写历史记录。 |

<p align="center">
  <img src="docs/images/hud-english.png" width="420" alt="英语输出">
  <img src="docs/images/edit-mode.png" width="420" alt="用语音编辑">
</p>

### 📝 会议记录

| | |
| --- | --- |
| **双方都录制** | 你的麦克风会被记录为"你"。Mac 的音频输出（Zoom、Meet、Teams、Slack huddle 等）会被记录为"对方"。不会有机器人加入通话。 |
| **说话人分离** | 对方会在设备端被区分为说话人 1、说话人 2 等。当对话中能明确得知名字时（例如有人自我介绍），AI 会填入名字并标注为推测。之后也可以重命名说话人。 |
| **AI 会议纪要** | 由你为会议选择的 AI 生成。可选模板：自动、周例会、一对一、销售拜访、头脑风暴或自定义。待办事项包含负责人和截止日期。 |
| **查看依据并重新收听** *（Mac）* | 会议纪要以单页形式打开：摘要和待办事项在前，转写就在旁边。点击要点后面的时间戳，即可跳到它所依据的发言。可以从任意一句发言开始播放录音；如果通话有回声，还可以把你这一方或对方静音。 |
| **实时笔记与重点标记** | 在通话中输入带时间戳的笔记，或按 <kbd>⌃⌥⌘ H</kbd> 标记"这很重要"（10 秒内可撤销）。会议纪要会优先处理这些部分，之后你也可以查看每个标记前后的对话。 |
| **浮动字幕** *（Mac）* | 以字幕形式在会议应用上方显示实时转写。 |
| **会议中的 AI 聊天** *（Mac）* | 录音时，可以就到目前为止的对话向 AI 提问（<kbd>⌘J</kbd>）。"到目前为止的总结"和"决定事项与待办"只需点一下。可以继续追问，点击回答中的时间戳即可跳转到转写中的对应位置。 |
| **会议检测** | 当会议应用开始使用麦克风时，Hanasu 会询问是否录制。它绝不会自行开始录制。 |
| **搜索与提问** | 搜索所有会议的文字，或提问"上周例会我们决定了什么？"。回答会注明引用了哪些会议。 |
| **导出** | 复制为 Markdown 或可直接发到 Slack 的摘要，保存为 `.md` / `.txt`，或把待办事项发送到"提醒事项"。 |
| **整理** | 直接编辑标题即可重命名会议，也可以删除不再需要的会议。 |

<p align="center">
  <img src="docs/images/meeting-live.png" width="420" alt="录制中并记录实时笔记">
  <img src="docs/images/meeting-ask.png" width="420" alt="向会议提问">
</p>
<p align="center">
  <img src="docs/images/meeting-minutes.png" width="420" alt="包含待办事项的会议纪要">
  <img src="docs/images/meeting-suggestion.png" width="420" alt="会议检测">
</p>

### 🤖 选择 AI

可以分别为**语音输入**和**会议**选择用来润色文字的 AI。

| AI | 默认模型 | 登录方式 |
| --- | --- | --- |
| **Gemini**（Windows 上默认） | 语音输入 `gemini-3.5-flash-lite`，会议 `gemini-3.8-flash` | Google AI Studio API 密钥或 Vertex AI 服务账号 |
| **Claude** | 语音输入 `claude-haiku-5-5`，会议 `claude-sonnet-5-5`（也可使用 Opus 5.5） | Anthropic API 密钥 |
| **本地**（在你的设备上；Mac 上默认） | Gemma 4 E4B（推荐）。见下表 | 无需。在 **设置 → AI** 中下载模型。在 Mac 上，如果开始润色文字时还没有模型，Hanasu 会询问是否下载 |
| **Apple** *（Mac，macOS 27）* | 设备端的 Apple Intelligence 模型，通过 `fm` 命令调用 | 无需 |

这些 AI 只处理文字。语音由下文的引擎转写。

#### 💻 本地模型

选择**本地**时，Hanasu 会使用内置的 [llama.cpp](https://github.com/ggml-org/llama.cpp) 在你自己的 Mac 或 PC 上运行小型语言模型，因此文字永远不会离开设备。Mac 使用 GPU（Metal），Windows 使用 CPU。只需在 **设置 → AI** 中下载一次模型。Hanasu 在使用前会校验模型的大小和 SHA-256。

| 模型 | 大小 | 许可证 | 说明 |
| --- | --- | --- | --- |
| **Gemma 4 E4B** (Google) — **推荐** | 4.59 GB | Apache-2.0 | 无论是文字整理还是会议纪要，效果都最自然。建议 16 GB 或以上内存。语音输入和会议的默认模型 |
| LFM2.5-1.2B-JP (Liquid AI) | 1.25 GB | LFM Open License v1.0 | 小巧快速。根据该许可证，年收入达到 1000 万美元或以上的组织不得将其用于商业用途 |
| Sarashina2.2 3B (SB Intuitions) | 2.07 GB | MIT | 使用日语训练。上下文长度为 8K，因此长会议会分段总结 |
| Qwen3.5-4B (Alibaba) | 2.74 GB | Apache-2.0 | 体积约为 Gemma 的一半，在 8 GB 内存上更容易运行。处理说话中途更正的能力不如 Gemma |

> [!TIP]
> 我们推荐 **Gemma 4 E4B**。在我们的测试中，其他模型有时会保留你本想收回的话、添加你没说过的句子、搞错待办事项的负责人，或者合并、遗漏待办事项。Gemma 4 E4B 在文字整理和会议纪要两方面都表现稳定。

### 🔊 选择语音引擎

| 引擎 | 运行位置 | 实时转写 | 说明 |
| --- | --- | --- | --- |
| **系统标准**（默认） | Mac：`SpeechAnalyzer` · Windows：`Windows.Media.SpeechRecognition` | ✅ | 在 Mac 上于设备端运行 |
| **Whisper** | 设备端（Mac 上为 WhisperKit，Windows 上为 whisper.cpp） | —（停止后） | 选择时下载模型 |
| **Gemini** | Google | —（停止后） | 录制的音频会发送给 Google |

语音输入和会议可以选择不同的引擎。在 Windows 上，会议使用 Whisper 或 Gemini。
在 Mac 上，可以从列表中选择转写语言（日语、英语、中文、韩语、法语、德语、西班牙语、意大利语、葡萄牙语）。初始值为你的系统语言。

## 下载

从 [**Releases**](https://github.com/kakibara/hanasu/releases/latest) 获取最新版本。

| 平台 | 文件 | 系统要求 |
| --- | --- | --- |
| macOS | `Hanasu-<version>-macOS.zip` | macOS 26 (Tahoe) 或更高版本，Apple Silicon |
| Windows | `Hanasu-<version>-Windows-x64.zip` | Windows 10（2004 或更高版本）/ 11，x64 |

<details>
<summary><b>macOS：首次启动</b></summary>

1. 解压文件，并把 `Hanasu.app` 移到 **应用程序** 文件夹。
2. 该应用为自签名且未经公证，因此首次打开时会被 macOS 阻止。点击 **完成**，然后打开 **系统设置 → 隐私与安全性**，点击 **仍要打开**。
   也可以改为运行 `xattr -dr com.apple.quarantine /Applications/Hanasu.app`。
3. 出现提示时，允许 **麦克风**、**语音识别** 和 **辅助功能**。使用 ⌘V 粘贴需要辅助功能权限。

</details>

<details>
<summary><b>Windows：首次启动</b></summary>

1. 解压文件，把 `Hanasu` 文件夹放到任意位置（例如 `%LOCALAPPDATA%\Programs`），然后运行 `Hanasu.exe`。
2. 该应用没有代码签名，因此 SmartScreen 会显示警告。点击 **更多信息 → 仍要运行**。
3. Windows 语音引擎需要在 Windows 设置中开启 **联机语音识别**。如果未开启，Hanasu 会提示你。

更多说明以及 Windows 版与 Mac 版的区别，请参阅 [windows/README.md](windows/README.md)。

</details>

有新版本发布时，Hanasu 会在启动时告诉你，并在自行更新之前先询问你。你也可以在菜单中选择 **アップデートを確認…**（检查更新）（启动时的检查可以在 **设置 → 通用** 中关闭）。v1.5.0 及更早的版本还没有这个功能，因此请手动更新这些版本一次。

## 快速开始

在 Mac 上，首次启动时会打开一个简短的引导。你可以在其中选择 AI（推荐的本地模型 Gemma 4 E4B 可以当场下载），了解主要功能和设置技巧，并授予 Hanasu 所需的权限。随时可以从菜单中的 **Hanasu 使用方法…** 再次打开。

1. **选择 AI。** 打开 **设置 → AI**，分别为语音输入和会议选择 AI。使用 Gemini 时，粘贴从 [Google AI Studio](https://aistudio.google.com/apikey) 获取的 API 密钥，或选择 Vertex AI 服务账号的 JSON 文件。使用 Claude 时，粘贴从 [Claude Console](https://console.anthropic.com/settings/keys) 获取的 API 密钥。使用本地模型时，下载一个模型（推荐 Gemma 4 E4B），无需密钥。点击测试按钮确认能否正常工作。
2. **听写。** 把光标放在要输入文字的位置，按下快捷键，说话，然后再按一次快捷键。
3. **录制会议。** 使用菜单栏（Mac）或托盘（Windows）菜单，或使用快捷键。戴耳机有助于把双方的声音分开。

在 Mac 上，可以把 Hanasu 图标显示在菜单栏、程序坞或两者中（设置 → 通用）。

### 默认快捷键

| 操作 | macOS | Windows |
| --- | --- | --- |
| 语音输入（开始 / 停止） | <kbd>⌥ Space</kbd> | <kbd>Ctrl Alt Space</kbd> |
| 语音输入并翻译（翻译成你选择的语言） | <kbd>⌥⇧ Space</kbd> | <kbd>Ctrl Alt Shift Space</kbd> |
| 用语音编辑选中的文字 | <kbd>⌃⌥⌘ E</kbd> | — |
| 再次粘贴上一次的结果 | <kbd>⌥⇧ V</kbd> | — |
| 取消录音 | <kbd>Esc</kbd> | <kbd>Esc</kbd> |
| 会议录制（开始 / 停止） | <kbd>⌃⌥⌘ M</kbd> | <kbd>Ctrl Alt Shift M</kbd> |
| 在会议中标记"这很重要" | <kbd>⌃⌥⌘ H</kbd> | <kbd>Ctrl Alt Shift H</kbd> |

所有快捷键都可以在设置中修改。完整的用户指南（日语）见 [docs/guide.md](docs/guide.md)。

## 隐私

- **默认情况下，音频留在你的设备上。** 语音识别、Whisper 和说话人分离都在本地运行。
- **AI 收到的是文字，而不是音频。** Gemini 或 Claude 接收的是转写结果。根据你的设置，它还可能收到你正在输入的应用名称、屏幕上下文，以及用于提问功能和会议 AI 聊天的会议转写。
- **本地模型和 Apple 同样会把文字留在设备上。** 选择其中任意一个时，不会向任何 AI 服务发送内容。唯一的下载是模型本身。
- **只有你选择时，音频才会发送给 Google。** 如果选择 Gemini 语音引擎，录制的音频会发送给 Google。
- **会议是普通文件。** 会议以 JSON 和 Markdown 格式保存在 `~/Documents/Hanasu/Meetings/`（Windows：`Documents\Hanasu\Meetings\`）下。Mac 和 Windows 使用相同的格式。
- **没有遥测。** Hanasu 不收集任何分析数据。
- **API 密钥受操作系统保护。** 在 macOS 上，密钥保存在 Keychain 中，其他应用必须输入你的登录密码才能读取。在 Windows 上，密钥使用 DPAPI 加密，也可以选择使用 Windows Hello 密钥加密。两者都无法完全防范以你的用户身份运行的恶意软件。参见 [docs/design/security.md](docs/design/security.md)。

> [!IMPORTANT]
> 录制前，请征得所有与会者的同意。请遵守你所在组织关于录音和使用 AI 服务的规定。

## 从源码构建

<details>
<summary><b>macOS</b>（Xcode Command Line Tools，Swift 6.2）</summary>

```bash
./scripts/build-app.sh             # 构建 build/Hanasu.app
open build/Hanasu.app
./scripts/create-signing-cert.sh   # 可选：重新构建后保留权限
```

</details>

<details>
<summary><b>Windows</b>（.NET 8 SDK）</summary>

```bash
cd windows
dotnet build Hanasu.Windows.sln
dotnet publish Hanasu.Windows/Hanasu.Windows.csproj -c Release -r win-x64 --self-contained -p:PublishSingleFile=true -o publish/win-x64
```

参见 [windows/README.md](windows/README.md)。

</details>

## 文档

文档以日语编写。

| | |
| --- | --- |
| [docs/guide.md](docs/guide.md) | 用户指南：使用方法、设置、词典规则 |
| [docs/spec/](docs/spec/) | 已实现的需求（`REQ-*`）和设计决策（`DEC-*`） |
| [docs/design/](docs/design/) | 实现方式：架构与数据流 |
| [docs/roadmap.md](docs/roadmap.md) | 尚未实现的计划 |
| [docs/releasing.md](docs/releasing.md) | 发布流程（tagpr） |

## 参与贡献

欢迎提交 Issue 和 Pull Request。

1. 修改任何行为之前，请先阅读 [docs/README.md](docs/README.md)。
2. 代码中带有 `// 要件: REQ-…`（需求）或 `// 設計判断: DEC-…`（设计决策）标签。CI 中的 `scripts/check-spec.py` 会检查带标签的代码发生变化时 spec 是否也随之更新。
3. 新功能从 `docs/spec/` 中的一条需求开始。以后再做的想法写进 `docs/roadmap.md`。

## 许可证

Hanasu 是源代码可用（source-available）的软件，而不是开源软件。© 2026 kakibara。参见 [NOTICE](NOTICE)。

- 许可证：[PolyForm Noncommercial License 1.0.0](LICENSE) 加上 [Hanasu Additional Permission 1.0](LICENSE-ADDITIONAL-PERMISSION.md)。
- 个人非商业用途、教育、研究、慈善机构和政府，以及小型企业（少于 100 人且收入低于 US$1M）的内部工作，均可免费使用。任何公司都可以评估 Hanasu 30 天。
- 规模更大的公司，以及任何销售 Hanasu 或将其集成到产品或服务中的人，都需要商业许可。参见 [COMMERCIAL.md](COMMERCIAL.md)。
- 在此次许可证变更之前发布的版本，是在 Apache License 2.0 下发布的，并继续适用该许可证。
- 贡献需要同意 [CONTRIBUTING.md](CONTRIBUTING.md) 中的协议。

第三方许可证列在 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)（macOS）和 [windows/THIRD_PARTY_NOTICES.md](windows/THIRD_PARTY_NOTICES.md)（Windows）中。下载包中包含这两个文件。
