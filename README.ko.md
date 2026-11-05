<div align="center">

<img src="docs/images/icon.png" width="112" alt="Hanasu 아이콘">

# Hanasu

**자연스럽게 말하면, 바로 보낼 수 있는 깔끔한 글과 저절로 완성되는 회의록을 얻을 수 있습니다.**

macOS와 Windows용 음성 입력·회의 기록 앱입니다. 온디바이스 음성 인식과 함께 Gemini, Claude 또는 내 기기에서 실행되는 AI 모델을 사용합니다.

[![Release](https://img.shields.io/github/v/release/kakibara/hanasu?sort=semver&label=release)](https://github.com/kakibara/hanasu/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/kakibara/hanasu/total)](https://github.com/kakibara/hanasu/releases)
[![License](https://img.shields.io/github/license/kakibara/hanasu)](LICENSE)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-000000?logo=apple)
![Windows 10/11](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows)
[![Windows build](https://github.com/kakibara/hanasu/actions/workflows/windows.yml/badge.svg)](https://github.com/kakibara/hanasu/actions/workflows/windows.yml)

[English](README.md) · [日本語](README.ja.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · **한국어** · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Italiano](README.it.md) · [Português (Brasil)](README.pt-BR.md) · [Русский](README.ru.md) · [Türkçe](README.tr.md) · [Tiếng Việt](README.vi.md) · [Bahasa Indonesia](README.id.md) · [Polski](README.pl.md) · [العربية](README.ar.md) · [हिन्दी](README.hi.md)

<sub>이 문서는 영어 README의 번역본입니다. 내용이 다를 경우 영어 README가 최신입니다.</sub>

<img src="docs/images/hud.png" width="560" alt="Hanasu 녹음 HUD">

</div>

> [!NOTE]
> Hanasu는 **일본어**를 우선으로 만들어졌으며, 일본어가 가장 많이 테스트되었습니다.
> 앱 화면과 AI에 주는 지시문은 이 README와 같은 17개 언어로 제공됩니다. 화면은 시스템 언어를, AI 지시문은 설정의 전사 언어를 따릅니다. 그 밖의 언어에서는 영어를 사용합니다.
> 말한 내용을 자연스러운 **영어**(또는 **일본어**)로 번역해 입력할 수도 있습니다.

## 왜 Hanasu인가

OS에 내장된 받아쓰기는 가공되지 않은 전사 결과만 줍니다. 군말과 동음이의어 오류가 그대로 남고, 문장 부호가 없으며, "아, 그러니까…" 같은 말까지 전부 들어갑니다.
Hanasu는 전사 결과를 AI(Gemini, Claude 또는 기기 내 로컬 모델)에 보내 이런 오류를 고치고 문장을 다듬은 뒤, 그 결과를 커서 위치에 입력합니다.
Typeless, Wispr Flow, Aqua Voice, Granola에서 영감을 받았습니다. Hanasu는 무료 오픈 소스입니다. 직접 발급한 Gemini 또는 Claude API 키를 쓰거나, API 키 없이 텍스트가 기기 밖으로 나가지 않는 로컬 모델을 실행할 수 있습니다.

## 기능

### 🎙️ 음성 입력

| | |
| --- | --- |
| **말하기 → 다듬어진 텍스트** | <kbd>⌥ Space</kbd>를 누르고 말한 다음 다시 누르세요(또는 **■ 정지** 클릭). Hanasu가 군말을 없애고, 동음이의어를 바로잡고, 말하다가 고친 내용을 반영해 커서 위치에 붙여 넣습니다. |
| **말하면 번역해서 입력** | <kbd>⌥⇧ Space</kbd>를 누르거나, 말하는 도중 HUD를 **English** 또는 **日本語**로 전환하세요. 정해진 인사말도 자연스럽게 번역되어 お疲れ様です는 "Hi,"가 됩니다. 제공할 언어(영어, 일본어 또는 둘 다)는 **설정 → 일반**에서 고릅니다. 기본값은 영어입니다. |
| **섞어 쓴 언어는 말한 그대로** | 기본적으로 영어로 말한 부분은 영어로 남습니다. 출력을 일본어로 통일하도록 선택할 수도 있습니다. |
| **음성으로 편집** | 텍스트를 선택하고 <kbd>⌃⌥⌘ E</kbd>를 누른 뒤 "더 정중하게", "글머리 기호로 바꿔 줘", "영어로 번역해 줘"라고 말하세요. |
| **앱별 스타일** | Slack에서는 가볍고 짧게, Mail에서는 정중하게 단락을 나눠서, Pages·Word·Notion에서는 문어체로 작성합니다. 앱마다 프리셋을 바꿀 수 있습니다. |
| **스니펫** | "이메일 서명"이라고 말하면 저장해 둔 텍스트를 작성한 그대로 삽입합니다. 스니펫은 AI로 전송되지 않습니다. |
| **사전** | 고유 명사와 `ストックマーク => Stockmark` 같은 치환 규칙을 추가합니다. Mac에서는 AI가 기록과 회의를 바탕으로 새 항목을 제안하기도 하며, 고른 것만 추가됩니다. |
| **화면 맥락** *(선택 사항)* | Hanasu가 창 제목과 커서 주변 텍스트를 읽어, 이름이 화면에 이미 있는 표기와 일치하도록 합니다. 암호 입력란은 절대 읽지 않습니다. |
| **마이크 선택** *(Mac)* | 설정에서 마이크를 고르거나, 녹음을 멈추지 않고 HUD의 마이크 버튼으로 전환할 수 있습니다. |
| **기록** | 지난 결과를 검색하고 실패한 항목을 다시 시도합니다. 기록은 기본적으로 30일간 보관되며 설정에서 바꿀 수 있습니다. Mac에서는 <kbd>⌥⇧ V</kbd>를 눌러 마지막 결과를 다시 붙여 넣을 수 있습니다. |
| **붙여 넣을 곳이 없다면?** | 포커스된 텍스트 필드가 없으면(예: 데스크톱이 맨 앞에 있을 때) Hanasu는 붙여 넣는 대신 결과를 화면에 띄워 둡니다. 거기서 복사하거나, 원하는 곳에서 <kbd>⌘V</kbd>를 누르세요(결과를 클립보드에 남길지 선택할 수 있습니다). |
| **붙여 넣기가 안 됐다면?** | 붙여 넣기가 어떤 앱에도 전달되지 않았다면(예: 녹음 중에 창을 전환한 경우) Hanasu는 최신 결과를 클립보드에 남기고 HUD로 알려 줍니다. 원하는 곳에서 <kbd>⌘V</kbd>를 누르세요. 설정 → 일반에서 이럴 때 받아쓰기 기록이 열리도록 할 수도 있습니다. |

<p align="center">
  <img src="docs/images/hud-english.png" width="420" alt="영어 출력">
  <img src="docs/images/edit-mode.png" width="420" alt="음성으로 편집">
</p>

### 📝 회의 기록

| | |
| --- | --- |
| **양쪽 모두 녹음** | 내 마이크는 "나"로, Mac의 오디오 출력(Zoom, Meet, Teams, Slack 허들 등)은 "상대"로 녹음됩니다. 통화에 봇이 참여하지 않습니다. |
| **화자 분리** | 상대 쪽은 기기에서 화자 1, 화자 2 등으로 나뉩니다. 대화에서 이름이 분명해지면(예: 누군가 자기소개를 할 때) AI가 이름을 채우고 추정이라고 표시합니다. 나중에 화자 이름을 바꿀 수 있습니다. |
| **AI 회의록** | 회의용으로 고른 AI가 작성합니다. 템플릿은 자동, 주간 회의, 1:1, 영업 미팅, 브레인스토밍, 사용자 지정 중에서 고릅니다. 액션 아이템에는 담당자와 기한이 포함됩니다. |
| **실시간 메모와 하이라이트** | 통화 중에 타임스탬프가 붙은 메모를 입력하거나, <kbd>⌃⌥⌘ H</kbd>를 눌러 "중요"로 표시하세요(10초 동안 취소 가능). 회의록은 그 부분을 우선해서 다루며, 나중에 각 표시 전후의 대화를 읽어 볼 수 있습니다. |
| **플로팅 자막** *(Mac)* | 실시간 전사를 회의 앱 위에 자막으로 표시합니다. |
| **회의 중 AI 채팅** *(Mac)* | 녹음 중에 지금까지의 대화에 대해 AI에게 물어볼 수 있습니다(<kbd>⌘J</kbd>). "지금까지 요약"과 "결정 사항과 할 일"은 클릭 한 번이면 됩니다. 이어서 질문할 수 있고, 답변의 타임스탬프를 클릭하면 전사의 해당 부분으로 이동합니다. |
| **회의 감지** | 회의 앱이 마이크를 쓰기 시작하면 Hanasu가 녹음할지 묻습니다. 스스로 녹음을 시작하는 일은 없습니다. |
| **검색과 질문** | 모든 회의의 텍스트를 검색하거나 "지난주 정기 회의에서 뭘 결정했지?"라고 물어보세요. 답변에는 참고한 회의가 인용됩니다. |
| **내보내기** | Markdown이나 Slack에 바로 올릴 수 있는 요약으로 복사하거나, `.md` / `.txt`로 저장하거나, 액션 아이템을 미리 알림으로 보냅니다. |
| **정리** | 제목을 그 자리에서 편집해 회의 이름을 바꾸거나, 더 이상 필요 없는 회의를 삭제합니다. |

<p align="center">
  <img src="docs/images/meeting-live.png" width="420" alt="실시간 메모를 남기며 녹음">
  <img src="docs/images/meeting-ask.png" width="420" alt="회의에 질문하기">
</p>
<p align="center">
  <img src="docs/images/meeting-minutes.png" width="420" alt="액션 아이템이 포함된 회의록">
  <img src="docs/images/meeting-suggestion.png" width="420" alt="회의 감지">
</p>

### 🤖 AI 선택

텍스트를 다듬을 AI를 **음성 입력**과 **회의**에 대해 따로 고릅니다.

| AI | 기본 모델 | 인증 |
| --- | --- | --- |
| **Gemini** (Windows 기본값) | 음성 입력 `gemini-3.5-flash-lite`, 회의 `gemini-3.8-flash` | Google AI Studio API 키 또는 Vertex AI 서비스 계정 |
| **Claude** | 음성 입력 `claude-haiku-5-5`, 회의 `claude-sonnet-5-5` (Opus 5.5도 사용 가능) | Anthropic API 키 |
| **로컬** (내 기기에서 실행, Mac 기본값) | Gemma 4 E4B (권장). 아래 표 참고 | 없음. **설정 → AI**에서 모델 다운로드. Mac에서는 텍스트를 다듬기 시작할 때 모델이 없으면 다운로드할지 물어봅니다 |
| **Apple** *(Mac, macOS 27)* | `fm` 명령을 통한 온디바이스 Apple Intelligence 모델 | 없음 |

이 AI들은 텍스트만 처리합니다. 음성은 아래의 엔진이 전사합니다.

#### 💻 로컬 모델

**로컬**을 선택하면 Hanasu는 내장된 [llama.cpp](https://github.com/ggml-org/llama.cpp)로 내 Mac이나 PC에서 작은 언어 모델을 실행하므로, 텍스트가 기기 밖으로 나가지 않습니다. Mac은 GPU(Metal)를, Windows는 CPU를 사용합니다. 모델은 **설정 → AI**에서 한 번만 다운로드하면 됩니다. Hanasu는 사용 전에 모델의 크기와 SHA-256을 확인합니다.

| 모델 | 크기 | 라이선스 | 비고 |
| --- | --- | --- | --- |
| **Gemma 4 E4B** (Google) — **권장** | 4.59 GB | Apache-2.0 | 텍스트 정리와 회의록 모두에서 가장 자연스러운 결과. 메모리 16 GB 이상 권장. 음성 입력과 회의 모두의 기본값 |
| LFM2.5-1.2B-JP (Liquid AI) | 1.25 GB | LFM Open License v1.0 | 작고 빠름. 이 라이선스에 따라 연 매출 1,000만 달러 이상인 조직은 상업적으로 사용할 수 없음 |
| Sarashina2.2 3B (SB Intuitions) | 2.07 GB | MIT | 일본어로 학습됨. 컨텍스트가 8K라 긴 회의는 나누어 요약함 |
| Qwen3.5-4B (Alibaba) | 2.74 GB | Apache-2.0 | Gemma의 절반 정도 크기라 메모리 8 GB에서도 돌리기 쉬움. 말하다가 고친 내용을 처리하는 능력은 Gemma보다 약함 |

> [!TIP]
> **Gemma 4 E4B**를 권장합니다. 테스트에서 다른 모델들은 취소하려던 말을 남기거나, 말하지 않은 문장을 덧붙이거나, 액션 아이템의 담당자를 혼동하거나, 액션 아이템을 합치거나 빠뜨리는 경우가 있었습니다. Gemma 4 E4B는 텍스트 정리와 회의록 모두를 안정적으로 처리했습니다.

### 🔊 음성 엔진 선택

| 엔진 | 실행 위치 | 실시간 전사 | 비고 |
| --- | --- | --- | --- |
| **OS 기본** (기본값) | Mac: `SpeechAnalyzer` · Windows: `Windows.Media.SpeechRecognition` | ✅ | Mac에서는 온디바이스 |
| **Whisper** | 온디바이스 (Mac은 WhisperKit, Windows는 whisper.cpp) | — (정지한 후) | 선택하면 모델을 다운로드 |
| **Gemini** | Google | — (정지한 후) | 녹음된 오디오가 Google로 전송됨 |

음성 입력과 회의에 서로 다른 엔진을 고를 수 있습니다. Windows에서는 회의에 Whisper 또는 Gemini를 사용합니다.
Mac에서는 목록(일본어, 영어, 중국어, 한국어, 프랑스어, 독일어, 스페인어, 이탈리아어, 포르투갈어)에서 전사 언어를 고릅니다. 처음에는 시스템 언어로 설정됩니다.

## 다운로드

[**Releases**](https://github.com/kakibara/hanasu/releases/latest)에서 최신 빌드를 받으세요.

| 플랫폼 | 파일 | 요구 사항 |
| --- | --- | --- |
| macOS | `Hanasu-<version>-macOS.zip` | macOS 26 (Tahoe) 이상, Apple Silicon |
| Windows | `Hanasu-<version>-Windows-x64.zip` | Windows 10 (2004 이상) / 11, x64 |

<details>
<summary><b>macOS: 처음 실행하기</b></summary>

1. 파일의 압축을 풀고 `Hanasu.app`을 **응용 프로그램**으로 옮깁니다.
2. 이 앱은 자체 서명되었고 공증을 받지 않았기 때문에 처음에는 macOS가 실행을 막습니다. **완료**를 클릭한 다음 **시스템 설정 → 개인정보 보호 및 보안**을 열고 **그래도 열기**를 클릭하세요.
   대신 `xattr -dr com.apple.quarantine /Applications/Hanasu.app`을 실행해도 됩니다.
3. 요청이 나오면 **마이크**, **음성 인식**, **손쉬운 사용**을 허용하세요. 손쉬운 사용은 ⌘V로 붙여 넣는 데 필요합니다.

</details>

<details>
<summary><b>Windows: 처음 실행하기</b></summary>

1. 파일의 압축을 풀고 `Hanasu` 폴더를 원하는 곳(예: `%LOCALAPPDATA%\Programs`)에 둔 뒤 `Hanasu.exe`를 실행합니다.
2. 이 앱은 코드 서명이 되어 있지 않아 SmartScreen이 경고를 표시합니다. **추가 정보 → 실행**을 클릭하세요.
3. Windows 음성 엔진을 쓰려면 Windows 설정에서 **온라인 음성 인식**을 켜야 합니다. 꺼져 있으면 Hanasu가 알려 줍니다.

자세한 내용과 Windows 버전이 Mac 버전과 다른 점은 [windows/README.md](windows/README.md)를 참고하세요.

</details>

## 빠른 시작

Mac에서는 처음 실행할 때 짧은 안내 투어가 열립니다. 여기서 AI를 고르고(권장 로컬 모델인 Gemma 4 E4B는 그 자리에서 다운로드됩니다), 주요 기능과 설정 팁을 확인하고, Hanasu에 필요한 권한을 요청합니다. 메뉴의 **Hanasu 사용법…**에서 언제든 다시 열 수 있습니다.

1. **AI를 고릅니다.** **설정 → AI**를 열고 음성 입력과 회의에 사용할 AI를 고릅니다. Gemini라면 [Google AI Studio](https://aistudio.google.com/apikey)에서 받은 API 키를 붙여 넣거나 Vertex AI 서비스 계정 JSON 파일을 선택합니다. Claude라면 [Claude Console](https://console.anthropic.com/settings/keys)에서 받은 API 키를 붙여 넣습니다. 로컬이라면 모델을 다운로드합니다(Gemma 4 E4B 권장). 키는 필요 없습니다. 테스트 버튼을 눌러 제대로 동작하는지 확인하세요.
2. **받아쓰기.** 텍스트를 넣을 곳에 커서를 두고, 단축키를 누르고, 말한 뒤, 단축키를 다시 누릅니다.
3. **회의를 녹음합니다.** 메뉴 막대(Mac)나 트레이(Windows) 메뉴, 또는 단축키를 사용하세요. 헤드폰을 쓰면 양쪽 소리를 구분하기 쉬워집니다.

Mac에서는 Hanasu 아이콘을 메뉴 막대, Dock 또는 둘 다에 표시할 수 있습니다(설정 → 일반).

### 기본 단축키

| 동작 | macOS | Windows |
| --- | --- | --- |
| 음성 입력 (시작 / 정지) | <kbd>⌥ Space</kbd> | <kbd>Ctrl Alt Space</kbd> |
| 음성 입력, 번역 (영어 / 일본어) | <kbd>⌥⇧ Space</kbd> | <kbd>Ctrl Alt Shift Space</kbd> |
| 선택한 텍스트를 음성으로 편집 | <kbd>⌃⌥⌘ E</kbd> | — |
| 마지막 결과 다시 붙여 넣기 | <kbd>⌥⇧ V</kbd> | — |
| 녹음 취소 | <kbd>Esc</kbd> | <kbd>Esc</kbd> |
| 회의 녹음 (시작 / 정지) | <kbd>⌃⌥⌘ M</kbd> | <kbd>Ctrl Alt Shift M</kbd> |
| 회의 중 "중요" 표시 | <kbd>⌃⌥⌘ H</kbd> | <kbd>Ctrl Alt Shift H</kbd> |

모든 단축키는 설정에서 바꿀 수 있습니다. 전체 사용자 가이드(일본어)는 [docs/guide.md](docs/guide.md)에 있습니다.

## 개인정보 보호

- **오디오는 기본적으로 기기에 남습니다.** 음성 인식, Whisper, 화자 분리는 모두 로컬에서 실행됩니다.
- **AI에는 오디오가 아닌 텍스트가 전달됩니다.** Gemini나 Claude는 전사 결과를 받습니다. 설정에 따라 입력 중인 앱의 이름, 화면 맥락, 질문 기능과 회의 중 AI 채팅에 쓰이는 회의 전사도 받을 수 있습니다.
- **로컬과 Apple도 텍스트를 기기에 둡니다.** 둘 중 하나를 고르면 AI 서비스로 아무것도 전송되지 않습니다. 다운로드하는 것은 모델 자체뿐입니다.
- **오디오는 직접 선택했을 때만 Google로 갑니다.** Gemini 음성 엔진을 선택하면 녹음된 오디오가 Google로 전송됩니다.
- **회의는 일반 파일입니다.** `~/Documents/Hanasu/Meetings/`(Windows: `Documents\Hanasu\Meetings\`) 아래에 JSON과 Markdown으로 저장됩니다. Mac과 Windows는 같은 형식을 사용합니다.
- **텔레메트리가 없습니다.** Hanasu는 어떤 분석 데이터도 수집하지 않습니다.
- **API 키는 OS가 보호합니다.** macOS에서는 Keychain에 보관되며, 다른 앱이 읽으려면 로그인 암호를 요구합니다. Windows에서는 DPAPI로, 원하면 Windows Hello 키로 암호화됩니다. 어느 쪽도 내 사용자 권한으로 실행되는 악성 코드를 완전히 막지는 못합니다. [docs/design/security.md](docs/design/security.md)를 참고하세요.

> [!IMPORTANT]
> 녹음하기 전에 회의 참석자 모두의 동의를 받으세요. 녹음과 AI 서비스 사용에 관한 소속 조직의 규칙을 따르세요.

## 소스에서 빌드하기

<details>
<summary><b>macOS</b> (Xcode Command Line Tools, Swift 6.2)</summary>

```bash
./scripts/build-app.sh             # build/Hanasu.app을 빌드
open build/Hanasu.app
./scripts/create-signing-cert.sh   # 선택 사항: 다시 빌드해도 권한이 유지됨
```

</details>

<details>
<summary><b>Windows</b> (.NET 8 SDK)</summary>

```bash
cd windows
dotnet build Hanasu.Windows.sln
dotnet publish Hanasu.Windows/Hanasu.Windows.csproj -c Release -r win-x64 --self-contained -p:PublishSingleFile=true -o publish/win-x64
```

[windows/README.md](windows/README.md)를 참고하세요.

</details>

## 문서

문서는 일본어로 작성되어 있습니다.

| | |
| --- | --- |
| [docs/guide.md](docs/guide.md) | 사용자 가이드: 사용법, 설정, 사전 규칙 |
| [docs/spec/](docs/spec/) | 구현된 요구 사항(`REQ-*`)과 설계 결정(`DEC-*`) |
| [docs/design/](docs/design/) | 구현 방식: 아키텍처와 데이터 흐름 |
| [docs/roadmap.md](docs/roadmap.md) | 아직 구현되지 않은 계획 |
| [docs/releasing.md](docs/releasing.md) | 릴리스 방법(tagpr) |

## 기여하기

이슈와 풀 리퀘스트를 환영합니다.

1. 동작을 바꾸기 전에 [docs/README.md](docs/README.md)를 읽어 주세요.
2. 코드에는 `// 要件: REQ-…`(요구 사항) 또는 `// 設計判断: DEC-…`(설계 결정) 태그가 붙어 있습니다. CI에서는 `scripts/check-spec.py`가 태그된 코드가 바뀔 때마다 spec도 갱신되었는지 확인합니다.
3. 새 기능은 `docs/spec/`에 요구 사항을 쓰는 것에서 시작합니다. 나중을 위한 아이디어는 `docs/roadmap.md`에 적습니다.

## 라이선스

[Apache License 2.0](LICENSE) © 2026 kakibara. [NOTICE](NOTICE)를 참고하세요.
서드 파티 라이선스는 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)(macOS)와 [windows/THIRD_PARTY_NOTICES.md](windows/THIRD_PARTY_NOTICES.md)(Windows)에 정리되어 있습니다. 두 파일 모두 다운로드에 포함되어 있습니다.
