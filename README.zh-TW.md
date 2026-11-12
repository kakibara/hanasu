<div align="center">

<img src="docs/images/icon.png" width="112" alt="Hanasu 圖示">

# Hanasu

**自然地說話，就能得到乾淨、可直接送出的文字，會議記錄也會自動寫好。**

適用於 macOS 與 Windows 的語音輸入與會議記錄應用程式。它使用裝置端語音辨識，並搭配 Gemini、Claude 或在你自己裝置上執行的 AI 模型。

[![Release](https://img.shields.io/github/v/release/kakibara/hanasu?sort=semver&label=release)](https://github.com/kakibara/hanasu/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/kakibara/hanasu/total)](https://github.com/kakibara/hanasu/releases)
[![License](https://img.shields.io/badge/license-PolyForm%20Noncommercial%20%2B%20small%20business-blue)](COMMERCIAL.md)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-000000?logo=apple)
![Windows 10/11](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows)
[![Windows build](https://github.com/kakibara/hanasu/actions/workflows/windows.yml/badge.svg)](https://github.com/kakibara/hanasu/actions/workflows/windows.yml)

[English](README.md) · [日本語](README.ja.md) · [简体中文](README.zh-CN.md) · **繁體中文** · [한국어](README.ko.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Italiano](README.it.md) · [Português (Brasil)](README.pt-BR.md) · [Русский](README.ru.md) · [Türkçe](README.tr.md) · [Tiếng Việt](README.vi.md) · [Bahasa Indonesia](README.id.md) · [Polski](README.pl.md) · [العربية](README.ar.md) · [हिन्दी](README.hi.md)

<sub>本文為英文 README 的翻譯。若內容有出入，請以英文 README 為準，它永遠是最新版本。</sub>

<img src="docs/images/hud.png" width="560" alt="Hanasu 錄音 HUD">

</div>

> [!NOTE]
> Hanasu 首先是為**日語**打造的，日語也是測試最充分的語言。
> 應用程式的介面和給 AI 的指示提供與本 README 相同的 17 種語言。介面會跟隨系統語言，AI 指示會跟隨設定中的轉錄語言。其他語言則使用英語。
> 它也能把你說的話翻譯成自然的**英語**、**日語**或支援的 17 種語言中的任一種後再輸入。

## 為什麼選擇 Hanasu

系統內建的聽寫只會給你原始的轉錄結果：贅詞和同音字錯誤都還在，沒有標點，每一句「等等，我是說……」也都原封不動。
Hanasu 會把轉錄結果交給 AI（Gemini、Claude，或你裝置上的本機模型），由它修正這些錯誤並整理文字，然後在游標位置輸入結果。
它的靈感來自 Typeless、Wispr Flow、Aqua Voice 和 Granola。Hanasu 的原始碼是公開的。個人使用和小型企業使用皆免費；規模更大的公司需要[商業授權](COMMERCIAL.md)。你可以使用自己的 Gemini 或 Claude API 金鑰，也可以執行本機模型——不需要 API 金鑰，文字也不會離開你的裝置。

## 功能

### 🎙️ 語音輸入

| | |
| --- | --- |
| **說話 → 潤飾好的文字** | 按下 <kbd>⌥ Space</kbd> 後說話，再按一次（或點選 **■ 完成**）。Hanasu 會去除贅詞、修正同音字錯誤、套用你說到一半的更正，並把文字貼到游標位置。 |
| **說話，輸入翻譯後的文字** | 按下 <kbd>⌥⇧ Space</kbd>，或在說話時把 HUD 切換到 **English**、**日本語** 或其他語言。固定的客套話會被自然地翻譯，例如 お疲れ様です 會變成「Hi,」。可在 **設定 → 一般** 中選擇要提供哪些語言（支援的 17 種語言皆可）。預設為英語。在 Mac 上，可以在 **設定 → 依 App** 中讓某個 App 一開始就使用其中一種語言。 |
| **混合語言照原樣保留** | 預設情況下，你用英語說的部分會保留為英語。你也可以選擇把輸出統一為日語。 |
| **用語音編輯** | 選取一段文字，按下 <kbd>⌃⌥⌘ E</kbd>，然後說「改得更有禮貌一點」、「改成條列式」或「翻譯成英文」。 |
| **依應用程式切換風格** | 在 Slack 中文字隨興而簡短，在 Mail 中有禮貌並分段，在 Pages、Word 和 Notion 中使用書面語。每個應用程式的預設風格都可以修改。 |
| **片段** | 說「電子郵件簽名」，就能原封不動地插入你儲存的文字。片段絕不會傳送給 AI。 |
| **字典** | 新增專有名詞和取代規則，例如 `ストックマーク => Stockmark`。取代規則也會套用到會議的轉錄文字。在會議筆記中開啟一場會議，AI 就能從這場會議建議新詞條（在 Mac 上，也會參考你的歷史紀錄和最近的會議），你只需新增挑選的那些。 |
| **畫面情境** *（需手動開啟）* | Hanasu 會讀取視窗標題和游標周圍的文字，讓名稱與畫面上已有的內容一致。絕不會讀取密碼欄位。 |
| **截圖文字** *（需手動開啟，Mac）* | Hanasu 會對你的所有顯示器截圖，在 Mac 上讀取其中的文字，並只把這些文字交給 AI，讓其他視窗中的名稱和型號（例如「QX-7s」）照畫面上的寫法輸出。影像絕不會被傳送或儲存。可以用 HUD 上的按鈕，僅針對某一次錄音開啟或關閉。需要螢幕錄製權限。 |
| **選擇麥克風** *（Mac）* | 在設定中選擇麥克風，或透過 HUD 上的麥克風按鈕切換，不必停止錄音。 |
| **歷史紀錄** | 搜尋過去的結果，並重試失敗的項目。歷史紀錄預設保留 30 天，可在設定中修改。在 Mac 上，按 <kbd>⌥⇧ V</kbd> 可再次貼上上一次的結果。 |
| **沒有地方可以貼上？** | 如果沒有任何文字欄位取得焦點（例如桌面在最前面），Hanasu 會把結果顯示在畫面上，而不是貼上。你可以從那裡複製，或直接在需要的位置按 <kbd>⌘V</kbd>（可以選擇結果是否保留在剪貼簿中）。 |
| **貼上沒有成功？** | 如果貼上沒有送達任何應用程式（例如你在錄音時切換了視窗），Hanasu 會把最新結果留在剪貼簿中，並在 HUD 中通知你。在需要的位置按 <kbd>⌘V</kbd> 即可。你也可以在 設定 → 一般 中設定在這種情況下開啟聽寫歷史紀錄。 |

<p align="center">
  <img src="docs/images/hud-english.png" width="420" alt="英語輸出">
  <img src="docs/images/edit-mode.png" width="420" alt="用語音編輯">
</p>

### 📝 會議記錄

| | |
| --- | --- |
| **雙方都錄下來** | 你的麥克風會被記錄為「你」。Mac 的音訊輸出（Zoom、Meet、Teams、Slack huddle 等）會被記錄為「對方」。不會有機器人加入通話。 |
| **說話者分離** | 對方會在裝置端被區分為說話者 1、說話者 2 等。當對話中能明確得知名字時（例如有人自我介紹），AI 會填入名字並標示為推測。之後也可以重新命名說話者。 |
| **AI 會議記錄** | 由你為會議選擇的 AI 產生。可選範本：自動、週會、一對一、業務拜訪、腦力激盪或自訂。待辦事項包含負責人和截止日期。 |
| **查看依據並重新聆聽** *（Mac）* | 會議記錄會以單一頁面開啟：摘要和待辦事項在前，轉錄就在旁邊。點選重點後面的時間戳記，即可跳到它所依據的發言。可以從任何一句發言開始播放錄音；如果通話有回音，還可以把你這一方或對方靜音。 |
| **即時筆記與重點標記** | 在通話中輸入附時間戳記的筆記，或按 <kbd>⌃⌥⌘ H</kbd> 標記「這很重要」（10 秒內可復原）。會議記錄會優先處理這些部分，之後你也可以查看每個標記前後的對話。 |
| **浮動字幕** *（Mac）* | 以字幕形式在會議應用程式上方顯示即時轉錄。如果一直開著，下次會議時也會自動顯示。 |
| **會議中的 AI 聊天** *（Mac）* | 錄音時，可以就到目前為止的對話向 AI 提問（<kbd>⌘J</kbd>）。「到目前為止的摘要」和「決定事項與待辦」只要點一下。可以繼續追問，點選回答中的時間戳記即可跳到轉錄中的對應位置。正忙著別的事卻突然被點名發問？不必離開會議應用程式，點選字幕上的「問了我什麼？」（或按 <kbd>⌃⌥⌘ A</kbd>），浮動面板就會顯示對方剛才說的話，以及 AI 整理出的「被問了什麼」和「來龍去脈」。透過輸入框下方的選單，可以切換這次對話使用的 AI 與模型。 |
| **會議偵測** | 當會議應用程式開始使用麥克風時，Hanasu 會詢問是否要錄音。它絕不會自行開始錄音。 |
| **搜尋與提問** | 搜尋所有會議的文字，或提問「上週的週會我們決定了什麼？」。回答會註明引用了哪些會議。 |
| **匯出** | 複製為 Markdown 或可直接貼到 Slack 的摘要，儲存為 `.md` / `.txt`，或把待辦事項傳送到「提醒事項」。 |
| **整理** | 直接編輯標題即可重新命名會議，也可以刪除不再需要的會議。 |

<p align="center">
  <img src="docs/images/meeting-live.png" width="420" alt="錄音中並記錄即時筆記">
  <img src="docs/images/meeting-ask.png" width="420" alt="向會議提問">
</p>
<p align="center">
  <img src="docs/images/meeting-minutes.png" width="420" alt="包含待辦事項的會議記錄">
  <img src="docs/images/meeting-suggestion.png" width="420" alt="會議偵測">
</p>

### 🤖 選擇 AI

可以分別為**語音輸入**和**會議**（會議紀錄）選擇用來潤飾文字的 AI。在 Mac 上，還可以另外為 **AI 聊天·提問**（會議中的 AI 聊天，以及對過去會議的提問）選擇 AI。

| AI | 預設模型 | 登入方式 |
| --- | --- | --- |
| **Gemini**（Windows 上的預設） | 語音輸入 `gemini-3.5-flash-lite`，會議和 AI 聊天·提問 `gemini-3.8-flash` | Google AI Studio API 金鑰或 Vertex AI 服務帳戶 |
| **Claude** | 語音輸入和 AI 聊天·提問 `claude-haiku-5-5`，會議 `claude-sonnet-5-5`（也可使用 Opus 5.5） | Anthropic API 金鑰 |
| **本機**（在你的裝置上；Mac 上的預設） | Gemma 4 E4B（建議）。請見下表 | 不需要。在 **設定 → AI** 中下載模型。在 Mac 上，如果開始潤飾文字時還沒有模型，Hanasu 會詢問是否下載 |
| **Apple** *（Mac，macOS 27）* | 裝置端的 Apple Intelligence 模型，透過 `fm` 指令呼叫 | 不需要 |

這些 AI 只處理文字。語音由下方的引擎轉錄。

#### 💻 本機模型

選擇**本機**時，Hanasu 會使用內建的 [llama.cpp](https://github.com/ggml-org/llama.cpp) 在你自己的 Mac 或 PC 上執行小型語言模型，因此文字絕不會離開裝置。Mac 使用 GPU（Metal），Windows 使用 CPU。只需在 **設定 → AI** 中下載一次模型。Hanasu 在使用前會檢查模型的大小和 SHA-256。

| 模型 | 大小 | 授權條款 | 說明 |
| --- | --- | --- | --- |
| **Gemma 4 E4B** (Google) — **建議** | 4.59 GB | Apache-2.0 | 無論是文字整理還是會議記錄，結果都最自然。建議 16 GB 以上的記憶體。語音輸入和會議的預設模型 |
| LFM2.5-1.2B-JP (Liquid AI) | 1.25 GB | LFM Open License v1.0 | 小巧快速。依此授權條款，年營收達 1,000 萬美元以上的組織不得用於商業用途 |
| Sarashina2.2 3B (SB Intuitions) | 2.07 GB | MIT | 以日語訓練。上下文長度為 8K，因此長時間的會議會分段摘要 |
| Qwen3.5-4B (Alibaba) | 2.74 GB | Apache-2.0 | 大小約為 Gemma 的一半，在 8 GB 記憶體上比較容易執行。處理說到一半的更正不如 Gemma |

> [!TIP]
> 我們建議使用 **Gemma 4 E4B**。在我們的測試中，其他模型有時會保留你原本想收回的話、加入你沒說過的句子、搞錯待辦事項的負責人，或是合併、漏掉待辦事項。Gemma 4 E4B 在文字整理和會議記錄兩方面都表現穩定。

### 🔊 選擇語音引擎

| 引擎 | 執行位置 | 即時轉錄 | 說明 |
| --- | --- | --- | --- |
| **系統標準**（預設） | Mac：`SpeechAnalyzer` · Windows：`Windows.Media.SpeechRecognition` | ✅ | 在 Mac 上於裝置端執行 |
| **Whisper** | 裝置端（Mac 上為 WhisperKit，Windows 上為 whisper.cpp） | —（停止後） | 選擇時下載模型 |
| **Gemini** | Google | —（停止後） | 錄下的音訊會傳送給 Google |

語音輸入和會議可以選擇不同的引擎。在 Windows 上，會議使用 Whisper 或 Gemini。
在 Mac 上，可以從清單中選擇轉錄語言（日語、英語、中文、韓語、法語、德語、西班牙語、義大利語、葡萄牙語）。初始值為你的系統語言。

### ⌨️ 從終端機和 AI 代理程式使用

透過 `hanasu` 指令，腳本和 AI 代理程式（Claude Code、Claude Desktop 等）可以讀取你的會議記錄，並使用你的潤飾風格。它隨應用程式一起提供，不需要另外安裝任何東西：在 Mac 上它就是應用程式本身，在 Windows 上則是 Hanasu 資料夾中的 `cli\hanasu.exe`。開啟 **設定 → 指令與 MCP**，即可一鍵將它連接到 Claude Desktop、ChatGPT（Codex）或 Claude Code，將它加入 PATH，或複製供其他 App 使用的 MCP 設定。（由於 OpenAI 的問題，ChatGPT 的一般聊天目前還無法使用本機 MCP 工具；Codex 可以。）

| | |
| --- | --- |
| **讀取會議** | `hanasu meetings list / show / search` 和 `hanasu actions` 以文字或 `--json` 輸出會議、會議記錄、轉錄和待辦事項。不會傳送到任何地方。 |
| **提問** | `hanasu ask "上週我們決定了什麼？"` 會根據你的會議內容回答。在 Mac 上使用你為 **AI 聊天·提問** 選擇的 AI（若未選擇，則使用會議的 AI）；在 Windows 上使用會議的 AI。 |
| **潤飾文字** | `hanasu refine` 會像語音輸入一樣潤飾或翻譯文字，`hanasu edit "<指示>"` 則會改寫文字。兩者都可以在管線中使用。`--app` 可選擇某個應用程式的風格（在 Mac 上用 bundle ID，在 Windows 上用 `slack.exe` 這類 exe 名稱）。 |
| **給 AI 代理程式用的 MCP** | `hanasu mcp` 是一個 MCP 伺服器（stdio）。代理程式可以列出、讀取、搜尋你的會議，並針對會議提問。以這種方式分享的會議內容會傳給代理程式及其 AI 供應商。 |
| **檢查設定** | `hanasu doctor` 會顯示使用的 AI 和憑證、會議檔案夾，以及登錄 MCP 的方法。執行 `hanasu help` 可查看所有選項。 |

在 Windows 上用 PowerShell 讀取輸出前，請先執行 `[Console]::OutputEncoding = [Text.UTF8Encoding]::new()`。以 Windows Hello 保護的 API 金鑰，每次被指令使用時都會請你確認。

在 Mac 上，管理員可以透過設定描述檔關閉此指令、MCP 或部分 AI。

## 下載

從 [**Releases**](https://github.com/kakibara/hanasu/releases/latest) 取得最新版本。

| 平台 | 檔案 | 系統需求 |
| --- | --- | --- |
| macOS | `Hanasu-<version>-macOS.zip` | macOS 26 (Tahoe) 或更新版本，Apple Silicon |
| Windows | `Hanasu-<version>-Windows-x64.zip` | Windows 10（2004 或更新版本）/ 11，x64 |

<details>
<summary><b>macOS：第一次啟動</b></summary>

1. 解壓縮檔案，並把 `Hanasu.app` 移到 **應用程式** 資料夾。
2. 此應用程式為自行簽署且未經公證，因此第一次開啟時會被 macOS 阻擋。點選 **完成**，然後開啟 **系統設定 → 隱私權與安全性**，點選 **強制打開**。
   也可以改為執行 `xattr -dr com.apple.quarantine /Applications/Hanasu.app`。
3. 出現詢問時，允許 **麥克風**、**語音辨識** 和 **輔助使用**。使用 ⌘V 貼上需要輔助使用權限。只有在開啟截圖文字時，才會詢問 **螢幕錄製** 權限。

</details>

<details>
<summary><b>Windows：第一次啟動</b></summary>

1. 解壓縮檔案，把 `Hanasu` 資料夾放到任意位置（例如 `%LOCALAPPDATA%\Programs`），然後執行 `Hanasu.exe`。
2. 此應用程式沒有程式碼簽章，因此 SmartScreen 會顯示警告。點選 **其他資訊 → 仍要執行**。
3. Windows 語音引擎需要在 Windows 設定中開啟 **線上語音辨識**。如果沒有開啟，Hanasu 會通知你。

更多說明以及 Windows 版與 Mac 版的差異，請參閱 [windows/README.md](windows/README.md)。

</details>

有新版本發布時，Hanasu 會在啟動時通知你，並在自行更新之前先詢問你。你也可以在選單中選擇 **アップデートを確認…**（檢查更新）（啟動時的檢查可以在 **設定 → 一般** 中關閉）。v1.5.0 及更早的版本還沒有這項功能，因此請手動更新這些版本一次。

## 快速開始

在 Mac 上，第一次啟動時會開啟簡短的導覽。你可以在其中選擇 AI（建議的本機模型 Gemma 4 E4B 可以當場下載），了解主要功能和設定技巧，並授予 Hanasu 所需的權限。隨時可以從選單中的 **Hanasu 使用方式…** 再次開啟。

1. **選擇 AI。** 開啟 **設定 → AI**，分別為語音輸入和會議（在 Mac 上還有 AI 聊天·提問）選擇 AI。使用 Gemini 時，貼上從 [Google AI Studio](https://aistudio.google.com/apikey) 取得的 API 金鑰，或選擇 Vertex AI 服務帳戶的 JSON 檔案。使用 Claude 時，貼上從 [Claude Console](https://console.anthropic.com/settings/keys) 取得的 API 金鑰。使用本機模型時，下載一個模型（建議 Gemma 4 E4B），不需要金鑰。點選測試按鈕確認能否正常運作。
2. **聽寫。** 把游標放在要輸入文字的位置，按下快捷鍵，說話，然後再按一次快捷鍵。
3. **錄製會議。** 使用選單列（Mac）或系統匣（Windows）選單，或使用快捷鍵。戴耳機有助於把雙方的聲音分開。

在 Mac 上，Hanasu 圖示一律顯示在 Dock 中，也可以同時顯示在選單列（設定 → 一般）。按一下 Dock 圖示不會打開設定，請從選單列圖示或 Dock 圖示的右鍵選單打開。

### 預設快捷鍵

| 動作 | macOS | Windows |
| --- | --- | --- |
| 語音輸入（開始 / 停止） | <kbd>⌥ Space</kbd> | <kbd>Ctrl Alt Space</kbd> |
| 語音輸入並翻譯（翻譯成你選擇的語言） | <kbd>⌥⇧ Space</kbd> | <kbd>Ctrl Alt Shift Space</kbd> |
| 用語音編輯選取的文字 | <kbd>⌃⌥⌘ E</kbd> | — |
| 再次貼上上一次的結果 | <kbd>⌥⇧ V</kbd> | — |
| 取消錄音 | <kbd>Esc</kbd> | <kbd>Esc</kbd> |
| 會議錄音（開始 / 停止） | <kbd>⌃⌥⌘ M</kbd> | <kbd>Ctrl Alt Shift M</kbd> |
| 在會議中標記「這很重要」 | <kbd>⌃⌥⌘ H</kbd> | <kbd>Ctrl Alt Shift H</kbd> |
| 在會議中使用「問了我什麼？」 | <kbd>⌃⌥⌘ A</kbd> | — |

所有快捷鍵都可以在設定中修改。完整的使用指南（日文）請見 [docs/guide.md](docs/guide.md)。

## 隱私權

- **預設情況下，音訊會留在你的裝置上。** 語音辨識、Whisper 和說話者分離都在本機執行。
- **AI 收到的是文字，而不是音訊。** Gemini 或 Claude 收到的是轉錄結果。依你的設定，它還可能收到你正在輸入的應用程式名稱、畫面情境、從螢幕截圖中讀取的文字（絕不包括影像本身），以及提問功能和會議 AI 聊天所用的會議轉錄。
- **本機模型和 Apple 同樣會把文字留在裝置上。** 選擇其中任何一個時，不會傳送任何內容給 AI 服務。唯一的下載是模型本身。
- **只有你選擇時，音訊才會傳送給 Google。** 如果選擇 Gemini 語音引擎，錄下的音訊會傳送給 Google。
- **只有你連接代理程式時，它才會取得會議。** `hanasu` 指令及其 MCP 伺服器只在你或代理程式呼叫時才讀取會議，傳回的內容會交給該代理程式及其 AI 供應商。
- **會議就是一般檔案。** 會議以 JSON 和 Markdown 格式儲存在 `~/Documents/Hanasu/Meetings/`（Windows：`Documents\Hanasu\Meetings\`）下。Mac 和 Windows 使用相同的格式。
- **沒有遙測。** Hanasu 不會收集任何分析資料。
- **API 金鑰受作業系統保護。** 在 macOS 上，金鑰儲存在 Keychain 中，其他應用程式必須輸入你的登入密碼才能讀取。在 Windows 上，金鑰以 DPAPI 加密，也可以選擇以 Windows Hello 金鑰加密。兩者都無法完全阻擋以你的使用者身分執行的惡意軟體。請參閱 [docs/design/security.md](docs/design/security.md)。

> [!IMPORTANT]
> 錄音前，請取得所有與會者的同意。請遵守你所屬組織關於錄音和使用 AI 服務的規定。

## 從原始碼建置

<details>
<summary><b>macOS</b>（Xcode Command Line Tools，Swift 6.2）</summary>

```bash
./scripts/build-app.sh             # 建置 build/Hanasu.app
open build/Hanasu.app
./scripts/create-signing-cert.sh   # 選用：重新建置後仍保留權限
```

</details>

<details>
<summary><b>Windows</b>（.NET 8 SDK）</summary>

```bash
cd windows
dotnet build Hanasu.Windows.sln
dotnet publish Hanasu.Windows/Hanasu.Windows.csproj -c Release -r win-x64 --self-contained -p:PublishSingleFile=true -o publish/win-x64
```

請參閱 [windows/README.md](windows/README.md)。

</details>

## 文件

文件以日文撰寫。

| | |
| --- | --- |
| [docs/guide.md](docs/guide.md) | 使用指南：使用方式、設定、字典規則 |
| [docs/spec/](docs/spec/) | 已實作的需求（`REQ-*`）與設計決策（`DEC-*`） |
| [docs/design/](docs/design/) | 實作方式：架構與資料流 |
| [docs/roadmap.md](docs/roadmap.md) | 尚未實作的計畫 |
| [docs/releasing.md](docs/releasing.md) | 發布流程（tagpr） |

## 參與貢獻

歡迎提交 Issue 和 Pull Request。

1. 修改任何行為之前，請先閱讀 [docs/README.md](docs/README.md)。
2. 程式碼中標有 `// 要件: REQ-…`（需求）或 `// 設計判断: DEC-…`（設計決策）。CI 中的 `scripts/check-spec.py` 會檢查有標記的程式碼變更時，spec 是否也一併更新。
3. 新功能從 `docs/spec/` 中的一項需求開始。之後再做的構想寫進 `docs/roadmap.md`。

## 授權條款

Hanasu 是原始碼公開（source-available）的軟體，而不是開源軟體。© 2026 kakibara。請參閱 [NOTICE](NOTICE)。

- 授權條款：[PolyForm Noncommercial License 1.0.0](LICENSE) 加上 [Hanasu Additional Permission 1.0](LICENSE-ADDITIONAL-PERMISSION.md)。
- 個人非商業用途、教育、研究、慈善機構和政府，以及小型企業（少於 100 人且營收低於 US$1M）的內部工作，皆可免費使用。任何公司都可以評估 Hanasu 30 天。
- 規模更大的公司，以及任何販售 Hanasu 或將其整合到產品或服務中的人，都需要商業授權。請參閱 [COMMERCIAL.md](COMMERCIAL.md)。
- 在這次授權條款變更之前發布的版本，是以 Apache License 2.0 發布的，並繼續適用該授權條款。
- 貢獻需要同意 [CONTRIBUTING.md](CONTRIBUTING.md) 中的協議。

第三方授權條款列於 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)（macOS）和 [windows/THIRD_PARTY_NOTICES.md](windows/THIRD_PARTY_NOTICES.md)（Windows）。下載檔中包含這兩個檔案。
