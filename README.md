<div align="center">

<img src="docs/images/icon.png" width="112" alt="Hanasu icon">

# Hanasu

**Speak naturally. Get clean, ready-to-send text and meeting minutes that write themselves.**

A voice-input and meeting-notes app for macOS and Windows. It uses on-device speech recognition, and Gemini, Claude, or an AI model that runs on your own device.

[![Release](https://img.shields.io/github/v/release/kakibara/hanasu?sort=semver&label=release)](https://github.com/kakibara/hanasu/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/kakibara/hanasu/total)](https://github.com/kakibara/hanasu/releases)
[![License](https://img.shields.io/badge/license-PolyForm%20Noncommercial%20%2B%20small%20business-blue)](COMMERCIAL.md)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-000000?logo=apple)
![Windows 10/11](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows)
[![Windows build](https://github.com/kakibara/hanasu/actions/workflows/windows.yml/badge.svg)](https://github.com/kakibara/hanasu/actions/workflows/windows.yml)

**English** · [日本語](README.ja.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Italiano](README.it.md) · [Português (Brasil)](README.pt-BR.md) · [Русский](README.ru.md) · [Türkçe](README.tr.md) · [Tiếng Việt](README.vi.md) · [Bahasa Indonesia](README.id.md) · [Polski](README.pl.md) · [العربية](README.ar.md) · [हिन्दी](README.hi.md)

<img src="docs/images/hud.png" width="560" alt="Hanasu recording HUD">

</div>

> [!NOTE]
> Hanasu was built for **Japanese** first, and Japanese is the most tested language.
> The app's screens and the instructions it gives the AI come in the same 17 languages as this README. The screens follow your system language, and the AI instructions follow the transcription language in Settings. For any other language, Hanasu uses English.
> It can also translate what you say into natural **English**, **Japanese**, or any of the 17 supported languages before typing it.

## Why Hanasu

Built-in dictation gives you a raw transcript. It keeps fillers and homophone mistakes, has no punctuation, and includes every "wait, I mean…".
Hanasu sends the transcript to an AI (Gemini, Claude, or a local model on your device), which fixes those mistakes and tidies the text. Then Hanasu types the result where your cursor is.
It is inspired by Typeless, Wispr Flow, Aqua Voice and Granola. Its source code is public. It is free for personal use and for small businesses; larger companies need a [commercial license](COMMERCIAL.md). You bring your own Gemini or Claude API key, or run a local model with no API key and no text leaving your device.

## Features

### 🎙️ Voice input

| | |
| --- | --- |
| **Speak → polished text** | Press <kbd>⌥ Space</kbd>, talk, and press it again (or click **■ Done**). Hanasu removes fillers, fixes homophones, applies your self-corrections, and pastes the text at your cursor. |
| **Speak, type it translated** | Press <kbd>⌥⇧ Space</kbd>, or switch the HUD to **English**, **日本語**, or another language while you talk. Set phrases are translated naturally, so お疲れ様です becomes "Hi,". Pick the languages to offer (any of the 17 supported languages) in **Settings → General**. English is the default. On Mac, **Settings → Per App** can make an app start in one of these languages. |
| **Mixed languages stay as spoken** | By default, the parts you say in English stay in English. You can choose to unify the output into Japanese instead. |
| **Edit by voice** | Select some text, press <kbd>⌃⌥⌘ E</kbd>, and say "make it more polite", "turn it into bullets" or "translate to English". |
| **Per-app styles** | Text is casual and short in Slack, polite with paragraphs in Mail, and in written style in Pages, Word and Notion. You can change the preset for each app. |
| **Snippets** | Say "email signature" to insert saved text exactly as you wrote it. Snippets are never sent to the AI. |
| **Dictionary** | Add proper nouns and replacement rules such as `ストックマーク => Stockmark`. The rules are also applied to meeting transcripts. From a meeting in Meeting Notes, the AI can suggest new entries from that meeting (on Mac, also from your history and recent meetings), and you add only the ones you pick. |
| **Screen context** *(opt-in)* | Hanasu reads the window title and the text around your cursor, so names match what is already on screen. Password fields are never read. |
| **Screenshot text** *(opt-in, Mac)* | Hanasu takes a screenshot of all your displays, reads the text on your Mac, and passes only that text to the AI, so names and model numbers in other windows (for example "QX-7s") are spelled the way they appear. The image is never sent or saved. Turn it on or off for one recording with the button on the HUD. Needs the Screen Recording permission. |
| **Choose your mic** *(Mac)* | Pick the microphone in Settings, or switch it from the mic button on the HUD without stopping the recording. |
| **History** | Search past results and retry failed ones. History is kept for 30 days by default, and you can change that in Settings. On Mac, press <kbd>⌥⇧ V</kbd> to paste the last result again. |
| **Nowhere to paste?** | If no text field has focus (for example, the desktop is in front), Hanasu keeps the result on screen instead of pasting it. Copy it from there, or just press <kbd>⌘V</kbd> where you want it (you can choose whether the result stays on the clipboard). |
| **Paste didn't land?** | If the paste never reached an app (for example, you switched windows while recording), Hanasu leaves the latest result on the clipboard and tells you in the HUD. Press <kbd>⌘V</kbd> where you want it. In Settings → General you can also have the dictation history open when this happens. |

<p align="center">
  <img src="docs/images/hud-english.png" width="420" alt="English output">
  <img src="docs/images/edit-mode.png" width="420" alt="Edit by voice">
</p>

### 📝 Meeting notes

| | |
| --- | --- |
| **Records both sides** | Your microphone is recorded as "you". The Mac's audio output (Zoom, Meet, Teams, Slack huddles, and so on) is recorded as "them". No bot joins the call. |
| **Speaker diarization** | The other side is split into Speaker 1, Speaker 2, and so on, on device. When the conversation makes a name clear (someone introduces themselves, for example), the AI fills it in and marks it as a guess. You can rename speakers afterwards. |
| **AI minutes** | Made by the AI you choose for meetings. Choose a template: auto, weekly sync, 1-on-1, sales call, brainstorm, or custom. Action items include an owner and a due date. |
| **Check the source & listen again** *(Mac)* | The minutes open as one page: summary and action items first, with the transcript beside them. Click the timestamp after a point to jump to the remark it came from. Play the recording from any remark, and mute your side or theirs if the call echoed. |
| **Live notes & highlights** | Type timestamped notes during the call, or press <kbd>⌃⌥⌘ H</kbd> to mark "this matters" (you can undo it for 10 seconds). The minutes give those parts priority, and afterwards you can read the conversation around each mark. |
| **Floating captions** *(Mac)* | Show the live transcript as captions on top of your meeting app. If you leave them on, they come back for the next meeting. |
| **AI chat during the meeting** *(Mac)* | While recording, ask the AI about the conversation so far (<kbd>⌘J</kbd>). One click for "summarize so far" or "decisions & to-dos". Ask follow-ups, and click a timestamp in an answer to jump to that part of the transcript. Put on the spot while doing something else? Press **What was I asked?** on the captions (or <kbd>⌃⌥⌘ A</kbd>) without leaving your meeting app: a floating panel shows what the others just said, then the AI's summary of the question and how the discussion got there. Switch the AI and model for that conversation from the menu under the input box. |
| **Meeting detection** | When a meeting app starts using the mic, Hanasu asks whether to record. It never starts recording on its own. |
| **Search & Ask** | Search the text of every meeting, or ask "What did we decide in last week's sync?". The answer cites the meetings it used. |
| **Export** | Copy as Markdown or as a summary ready for Slack, save as `.md` / `.txt`, or send action items to Reminders. |
| **Organize** | Rename a meeting by editing its title in place, or delete a meeting you no longer need. |

<p align="center">
  <img src="docs/images/meeting-live.png" width="420" alt="Recording with live notes">
  <img src="docs/images/meeting-ask.png" width="420" alt="Ask your meetings">
</p>
<p align="center">
  <img src="docs/images/meeting-minutes.png" width="420" alt="Minutes with action items">
  <img src="docs/images/meeting-suggestion.png" width="420" alt="Meeting detection">
</p>

### 🤖 Choose your AI

Pick the AI that polishes your text, separately for **voice input** and **meetings** (minutes). On the Mac, you also pick one for **AI chat & Ask** (the meeting AI chat and questions about past meetings).

| AI | Default model | Sign-in |
| --- | --- | --- |
| **Gemini** (default on Windows) | voice input `gemini-3.5-flash-lite`, meetings and AI chat & Ask `gemini-3.8-flash` | Google AI Studio API key or Vertex AI service account |
| **Claude** | voice input and AI chat & Ask `claude-haiku-5-5`, meetings `claude-sonnet-5-5` (Opus 5.5 also available) | Anthropic API key |
| **Local** (on your device; default on Mac) | Gemma 4 E4B (recommended). See the table below | None. Download the model in **Settings → AI**. On the Mac, if the model is missing when Hanasu starts to polish text, it asks whether to download it |
| **Apple** *(Mac, macOS 27)* | The on-device Apple Intelligence model, through the `fm` command | None |

These AIs only handle text. Speech is transcribed by the engine below.

#### 💻 Local models

With **Local**, Hanasu runs a small language model on your own Mac or PC with the bundled [llama.cpp](https://github.com/ggml-org/llama.cpp), so your text never leaves the device. The Mac uses the GPU (Metal), and Windows uses the CPU. You download a model once from **Settings → AI**. Hanasu checks its size and SHA-256 before using it.

| Model | Size | License | Notes |
| --- | --- | --- | --- |
| **Gemma 4 E4B** (Google) — **recommended** | 4.59 GB | Apache-2.0 | The most natural results for both clean-up and minutes. 16 GB of memory or more is recommended. The default for both voice input and meetings |
| LFM2.5-1.2B-JP (Liquid AI) | 1.25 GB | LFM Open License v1.0 | Small and fast. Organizations with annual revenue of US$10M or more may not use it commercially under this license |
| Sarashina2.2 3B (SB Intuitions) | 2.07 GB | MIT | Trained on Japanese. Its context is 8K, so long meetings are summarized in parts |
| Qwen3.5-4B (Alibaba) | 2.74 GB | Apache-2.0 | About half the size of Gemma, so it is easier to run on 8 GB of memory. Weaker than Gemma at handling self-corrections |

> [!TIP]
> We recommend **Gemma 4 E4B**. In our tests, the other models sometimes kept the words you meant to take back, added sentences you didn't say, mixed up who owns an action item, or merged or missed action items. Gemma 4 E4B handled both clean-up and minutes reliably.

### 🔊 Choose your speech engine

| Engine | Runs on | Live transcript | Notes |
| --- | --- | --- | --- |
| **OS standard** (default) | Mac: `SpeechAnalyzer` · Windows: `Windows.Media.SpeechRecognition` | ✅ | On-device on Mac |
| **Whisper** | On device (WhisperKit on Mac, whisper.cpp on Windows) | — (after you stop) | The model downloads when you select it |
| **Gemini** | Google | — (after you stop) | The recorded audio is sent to Google |

You can choose a different engine for voice input and for meetings. On Windows, meetings use Whisper or Gemini.
On Mac, pick the transcription language from a list (Japanese, English, Chinese, Korean, French, German, Spanish, Italian, Portuguese). It starts as your system language.

### ⌨️ Use it from the terminal and AI agents *(Mac)*

The `hanasu` command lets scripts and AI agents (Claude Code, Claude Desktop, and others) read your meeting records and use your clean-up style. It is the app itself, so there is nothing else to install. Open **Settings → Command & MCP** to add it to your PATH or to copy the setup for MCP.

| | |
| --- | --- |
| **Read meetings** | `hanasu meetings list / show / search` and `hanasu actions` print meetings, minutes, transcripts and action items, as text or `--json`. Nothing is sent anywhere. |
| **Ask** | `hanasu ask "What did we decide last week?"` answers from your meetings with the AI you chose for meetings. |
| **Clean up text** | `hanasu refine` polishes or translates text the same way voice input does, and `hanasu edit "<instruction>"` rewrites it. Both work in pipes. |
| **MCP for AI agents** | `hanasu mcp` is an MCP server (stdio). Agents can list, read, search and ask your meetings. The meeting content you share this way goes to the agent and its AI provider. |
| **Check the setup** | `hanasu doctor` shows which AI and credentials are used, the meeting folder, and how to register MCP. Run `hanasu help` for every option. |

Administrators can turn off the command, MCP, or some AIs with a configuration profile.

## Download

Get the latest build from [**Releases**](https://github.com/kakibara/hanasu/releases/latest).

| Platform | File | Requirements |
| --- | --- | --- |
| macOS | `Hanasu-<version>-macOS.zip` | macOS 26 (Tahoe) or later, Apple Silicon |
| Windows | `Hanasu-<version>-Windows-x64.zip` | Windows 10 (2004 or later) / 11, x64 |

<details>
<summary><b>macOS: first launch</b></summary>

1. Unzip the file and move `Hanasu.app` to **Applications**.
2. The app is self-signed and not notarized, so macOS blocks it the first time. Click **Done**, then open **System Settings → Privacy & Security** and click **Open Anyway**.
   You can also run `xattr -dr com.apple.quarantine /Applications/Hanasu.app` instead.
3. When asked, allow **Microphone**, **Speech Recognition** and **Accessibility**. Accessibility is needed to paste with ⌘V. **Screen Recording** is asked for only if you turn on screenshot text.

</details>

<details>
<summary><b>Windows: first launch</b></summary>

1. Unzip the file, put the `Hanasu` folder anywhere (for example `%LOCALAPPDATA%\Programs`), and run `Hanasu.exe`.
2. The app is not code-signed, so SmartScreen shows a warning. Click **More info → Run anyway**.
3. The Windows speech engine needs **Online speech recognition** turned on in Windows settings. Hanasu tells you if it is off.

See [windows/README.md](windows/README.md) for more notes and how the Windows version differs from the Mac version.

</details>

When a new version is released, Hanasu tells you at launch and asks before it updates itself. You can also choose **アップデートを確認…** (Check for Updates) in the menu (the launch check can be turned off in **Settings → General**). Versions up to v1.5.0 don't have this yet, so update those by hand once.

## Quick start

On Mac, the first launch opens a short guided tour. It lets you pick your AI (Gemma 4 E4B, the recommended local model, downloads right there), shows the main features and settings tips, and asks for the permissions Hanasu needs. Open it again any time from **How to use Hanasu…** in the menu.

1. **Choose an AI.** Open **Settings → AI** and choose an AI for voice input and for meetings (on the Mac, also for AI chat & Ask). For Gemini, paste an API key from [Google AI Studio](https://aistudio.google.com/apikey) or select a Vertex AI service-account JSON file. For Claude, paste an API key from the [Claude Console](https://console.anthropic.com/settings/keys). For Local, download a model (Gemma 4 E4B is recommended). No key is needed. Click the test button to check that it works.
2. **Dictate.** Put the cursor where you want the text, press the shortcut, speak, and press the shortcut again.
3. **Record a meeting.** Use the menu-bar (Mac) or tray (Windows) menu, or the shortcut. Headphones help keep the two sides apart.

On Mac, you can show the Hanasu icon in the menu bar, in the Dock, or in both (Settings → General).

### Default shortcuts

| Action | macOS | Windows |
| --- | --- | --- |
| Voice input (start / stop) | <kbd>⌥ Space</kbd> | <kbd>Ctrl Alt Space</kbd> |
| Voice input, translated (into the languages you picked) | <kbd>⌥⇧ Space</kbd> | <kbd>Ctrl Alt Shift Space</kbd> |
| Edit selection by voice | <kbd>⌃⌥⌘ E</kbd> | — |
| Paste last result again | <kbd>⌥⇧ V</kbd> | — |
| Cancel recording | <kbd>Esc</kbd> | <kbd>Esc</kbd> |
| Meeting recording (start / stop) | <kbd>⌃⌥⌘ M</kbd> | <kbd>Ctrl Alt Shift M</kbd> |
| Mark "this matters" in a meeting | <kbd>⌃⌥⌘ H</kbd> | <kbd>Ctrl Alt Shift H</kbd> |
| "What was I asked?" in a meeting | <kbd>⌃⌥⌘ A</kbd> | — |

You can change every shortcut in Settings. The full user guide (in Japanese) is [docs/guide.md](docs/guide.md).

## Privacy

- **Audio stays on your device by default.** Speech recognition, Whisper and speaker diarization all run locally.
- **The AI gets text, not audio.** Gemini or Claude receives the transcript. Depending on your settings, it can also receive the name of the app you are typing into, the screen context, text read from a screenshot of your screen (never the image), and meeting transcripts for Ask and the meeting AI chat.
- **Local and Apple keep text on your device too.** If you choose either one, nothing is sent to an AI service. The only download is the model itself.
- **Audio goes to Google only if you choose it.** If you select the Gemini speech engine, the recorded audio is sent to Google.
- **Agents get meetings only if you connect them.** The `hanasu` command and its MCP server only read meetings when you or an agent call them, and what they return goes to that agent and its AI provider.
- **Meetings are plain files.** They are saved as JSON and Markdown under `~/Documents/Hanasu/Meetings/` (Windows: `Documents\Hanasu\Meetings\`). Mac and Windows use the same format.
- **No telemetry.** Hanasu collects no analytics.
- **API keys are protected by the OS.** On macOS they are kept in the Keychain, and other apps must ask for your login password to read them. On Windows they are encrypted with DPAPI, or with a Windows Hello key if you choose. Neither can fully stop malware running as your user. See [docs/design/security.md](docs/design/security.md).

> [!IMPORTANT]
> Get consent from everyone in the meeting before you record. Follow your organization's rules on recording and on using AI services.

## Build from source

<details>
<summary><b>macOS</b> (Xcode Command Line Tools, Swift 6.2)</summary>

```bash
./scripts/build-app.sh             # builds build/Hanasu.app
open build/Hanasu.app
./scripts/create-signing-cert.sh   # optional: keeps permissions across rebuilds
```

</details>

<details>
<summary><b>Windows</b> (.NET 8 SDK)</summary>

```bash
cd windows
dotnet build Hanasu.Windows.sln
dotnet publish Hanasu.Windows/Hanasu.Windows.csproj -c Release -r win-x64 --self-contained -p:PublishSingleFile=true -o publish/win-x64
```

See [windows/README.md](windows/README.md).

</details>

## Documentation

The documentation is written in Japanese.

| | |
| --- | --- |
| [docs/guide.md](docs/guide.md) | User guide: how to use it, settings, dictionary rules |
| [docs/spec/](docs/spec/) | Implemented requirements (`REQ-*`) and design decisions (`DEC-*`) |
| [docs/design/](docs/design/) | How it is built: architecture and data flow |
| [docs/roadmap.md](docs/roadmap.md) | Plans that are not implemented yet |
| [docs/releasing.md](docs/releasing.md) | How releases are made (tagpr) |

## Contributing

Issues and pull requests are welcome.

1. Read [docs/README.md](docs/README.md) before you change any behavior.
2. Code is tagged with `// 要件: REQ-…` (requirement) or `// 設計判断: DEC-…` (design decision). In CI, `scripts/check-spec.py` checks that the spec is updated whenever tagged code changes.
3. A new feature starts as a requirement in `docs/spec/`. Ideas for later go in `docs/roadmap.md`.

## License

Hanasu is source-available, not open source. © 2026 kakibara. See [NOTICE](NOTICE).

- License: [PolyForm Noncommercial License 1.0.0](LICENSE) plus the [Hanasu Additional Permission 1.0](LICENSE-ADDITIONAL-PERMISSION.md).
- Free for personal noncommercial use, education, research, charities and government, and for the internal work of small businesses (fewer than 100 people and under US$1M in revenue). Any company may evaluate Hanasu for 30 days.
- Larger companies, and anyone who sells Hanasu or builds it into a product or service, need a commercial license. See [COMMERCIAL.md](COMMERCIAL.md).
- Versions released before this license change were released under the Apache License 2.0 and stay under it.
- Contributions need the agreement in [CONTRIBUTING.md](CONTRIBUTING.md).

Third-party licenses are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) (macOS) and [windows/THIRD_PARTY_NOTICES.md](windows/THIRD_PARTY_NOTICES.md) (Windows). Both files are included in the downloads.
