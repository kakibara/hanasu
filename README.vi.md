<div align="center">

<img src="docs/images/icon.png" width="112" alt="Biểu tượng Hanasu">

# Hanasu

**Cứ nói tự nhiên. Nhận văn bản gọn gàng, sẵn sàng để gửi và biên bản cuộc họp tự động được viết ra.**

Ứng dụng nhập liệu bằng giọng nói và ghi chép cuộc họp cho macOS và Windows. Ứng dụng dùng nhận dạng giọng nói ngay trên thiết bị, cùng với Gemini, Claude hoặc một mô hình AI chạy trên chính thiết bị của bạn.

[![Release](https://img.shields.io/github/v/release/kakibara/hanasu?sort=semver&label=release)](https://github.com/kakibara/hanasu/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/kakibara/hanasu/total)](https://github.com/kakibara/hanasu/releases)
[![License](https://img.shields.io/github/license/kakibara/hanasu)](LICENSE)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-000000?logo=apple)
![Windows 10/11](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows)
[![Windows build](https://github.com/kakibara/hanasu/actions/workflows/windows.yml/badge.svg)](https://github.com/kakibara/hanasu/actions/workflows/windows.yml)

[English](README.md) · [日本語](README.ja.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Italiano](README.it.md) · [Português (Brasil)](README.pt-BR.md) · [Русский](README.ru.md) · [Türkçe](README.tr.md) · **Tiếng Việt** · [Bahasa Indonesia](README.id.md) · [Polski](README.pl.md) · [العربية](README.ar.md) · [हिन्दी](README.hi.md)

<sub>Đây là bản dịch của README tiếng Anh. Nếu có khác biệt, README tiếng Anh là bản mới nhất.</sub>

<img src="docs/images/hud.png" width="560" alt="HUD ghi âm của Hanasu">

</div>

> [!NOTE]
> Hanasu được xây dựng trước hết cho **tiếng Nhật**, và tiếng Nhật là ngôn ngữ được kiểm thử kỹ nhất.
> Giao diện ứng dụng và chỉ dẫn mà ứng dụng gửi cho AI có sẵn bằng 17 ngôn ngữ giống như README này. Giao diện theo ngôn ngữ hệ thống, còn chỉ dẫn cho AI theo ngôn ngữ chép lời trong Cài đặt. Với các ngôn ngữ khác, Hanasu dùng tiếng Anh.
> Ứng dụng cũng có thể dịch những gì bạn nói sang **tiếng Anh** (hoặc **tiếng Nhật**) một cách tự nhiên trước khi gõ ra.

## Vì sao chọn Hanasu

Tính năng đọc chính tả có sẵn chỉ cho bạn bản chép lời thô. Nó giữ nguyên các từ đệm và lỗi từ đồng âm, không có dấu câu, và chép cả mọi câu kiểu "khoan, ý tôi là…".
Hanasu gửi bản chép lời đến một AI (Gemini, Claude hoặc một mô hình cục bộ trên thiết bị của bạn) để sửa những lỗi đó và chỉnh lại văn bản. Sau đó Hanasu gõ kết quả vào vị trí con trỏ.
Hanasu lấy cảm hứng từ Typeless, Wispr Flow, Aqua Voice và Granola. Hanasu miễn phí và mã nguồn mở. Bạn tự dùng khóa API Gemini hoặc Claude của mình, hoặc chạy một mô hình cục bộ không cần khóa API và không để văn bản nào rời khỏi thiết bị.

## Tính năng

### 🎙️ Nhập liệu bằng giọng nói

| | |
| --- | --- |
| **Nói → văn bản chỉn chu** | Nhấn <kbd>⌥ Space</kbd>, nói, rồi nhấn lại lần nữa (hoặc bấm **■ Dừng**). Hanasu loại bỏ từ đệm, sửa từ đồng âm, áp dụng những chỗ bạn tự sửa lời và dán văn bản vào vị trí con trỏ. |
| **Nói và gõ ra bản dịch** | Nhấn <kbd>⌥⇧ Space</kbd>, hoặc chuyển HUD sang **English** hay **日本語** trong lúc nói. Các câu nói quen thuộc được dịch tự nhiên, nên お疲れ様です sẽ thành "Hi,". Chọn các ngôn ngữ muốn hiển thị (tiếng Anh, tiếng Nhật hoặc cả hai) trong **Cài đặt → Chung**. Mặc định là tiếng Anh. |
| **Giữ nguyên ngôn ngữ trộn lẫn như khi nói** | Theo mặc định, những phần bạn nói bằng tiếng Anh sẽ được giữ nguyên tiếng Anh. Bạn cũng có thể chọn thống nhất toàn bộ đầu ra sang tiếng Nhật. |
| **Chỉnh sửa bằng giọng nói** | Chọn một đoạn văn bản, nhấn <kbd>⌃⌥⌘ E</kbd> và nói "viết lịch sự hơn", "chuyển thành gạch đầu dòng" hoặc "dịch sang tiếng Anh". |
| **Văn phong theo từng ứng dụng** | Trong Slack, văn bản thân mật và ngắn gọn; trong Mail, lịch sự và chia đoạn; trong Pages, Word và Notion, theo văn viết. Bạn có thể đổi thiết lập sẵn cho từng ứng dụng. |
| **Đoạn mẫu** | Nói "chữ ký email" để chèn đúng nguyên văn đoạn văn bản bạn đã lưu. Đoạn mẫu không bao giờ được gửi đến AI. |
| **Từ điển** | Thêm danh từ riêng và quy tắc thay thế như `ストックマーク => Stockmark`. Trên Mac, AI còn có thể gợi ý mục mới từ lịch sử và các cuộc họp của bạn, và bạn chỉ thêm những mục mình chọn. |
| **Ngữ cảnh màn hình** *(tùy chọn bật)* | Hanasu đọc tiêu đề cửa sổ và văn bản quanh con trỏ để tên riêng khớp với những gì đã có trên màn hình. Ô mật khẩu không bao giờ bị đọc. |
| **Chọn micrô** *(Mac)* | Chọn micrô trong Cài đặt, hoặc đổi micrô bằng nút micrô trên HUD mà không cần dừng ghi âm. |
| **Lịch sử** | Tìm kiếm các kết quả trước đây và thử lại những lần thất bại. Theo mặc định, lịch sử được lưu 30 ngày, bạn có thể thay đổi trong Cài đặt. Trên Mac, nhấn <kbd>⌥⇧ V</kbd> để dán lại kết quả gần nhất. |
| **Không có chỗ để dán?** | Nếu không có ô văn bản nào đang được chọn (ví dụ, màn hình nền đang ở phía trước), Hanasu giữ kết quả trên màn hình thay vì dán. Hãy sao chép từ đó, hoặc chỉ cần nhấn <kbd>⌘V</kbd> ở nơi bạn muốn (bạn có thể chọn có giữ kết quả trong bảng nhớ tạm hay không). |
| **Dán không thành công?** | Nếu thao tác dán không đến được ứng dụng nào (ví dụ, bạn chuyển cửa sổ trong lúc ghi âm), Hanasu để kết quả mới nhất trong bảng nhớ tạm và báo cho bạn trên HUD. Hãy nhấn <kbd>⌘V</kbd> ở nơi bạn muốn. Trong Cài đặt → Chung, bạn cũng có thể đặt để lịch sử đọc chính tả tự mở khi điều này xảy ra. |

<p align="center">
  <img src="docs/images/hud-english.png" width="420" alt="Kết quả bằng tiếng Anh">
  <img src="docs/images/edit-mode.png" width="420" alt="Chỉnh sửa bằng giọng nói">
</p>

### 📝 Ghi chép cuộc họp

| | |
| --- | --- |
| **Ghi âm cả hai phía** | Micrô của bạn được ghi là "bạn". Âm thanh phát ra từ Mac (Zoom, Meet, Teams, Slack huddle, v.v.) được ghi là "phía bên kia". Không có bot nào tham gia cuộc gọi. |
| **Phân tách người nói** | Phía bên kia được tách thành Người nói 1, Người nói 2, v.v., ngay trên thiết bị. Khi cuộc trò chuyện làm rõ được tên (ví dụ có người tự giới thiệu), AI sẽ điền tên đó và đánh dấu là phỏng đoán. Bạn có thể đổi tên người nói sau đó. |
| **Biên bản bằng AI** | Được tạo bởi AI bạn chọn cho cuộc họp. Chọn mẫu: tự động, họp định kỳ hằng tuần, 1-1, cuộc gọi bán hàng, động não hoặc tùy chỉnh. Các đầu việc có người phụ trách và hạn chót. |
| **Ghi chú trực tiếp & đánh dấu** | Gõ ghi chú có dấu thời gian trong cuộc gọi, hoặc nhấn <kbd>⌃⌥⌘ H</kbd> để đánh dấu "chỗ này quan trọng" (có thể hoàn tác trong 10 giây). Biên bản sẽ ưu tiên những phần đó, và sau này bạn có thể đọc lại đoạn hội thoại quanh mỗi dấu. |
| **Phụ đề nổi** *(Mac)* | Hiển thị bản chép lời trực tiếp dưới dạng phụ đề phía trên ứng dụng họp của bạn. |
| **Trò chuyện với AI trong cuộc họp** *(Mac)* | Trong lúc ghi âm, hãy hỏi AI về cuộc hội thoại cho đến lúc này (<kbd>⌘J</kbd>). Chỉ một cú nhấp để có "tóm tắt đến giờ" hoặc "quyết định & việc cần làm". Hãy hỏi tiếp, và bấm vào dấu thời gian trong câu trả lời để chuyển đến đoạn đó trong bản chép lời. |
| **Phát hiện cuộc họp** | Khi một ứng dụng họp bắt đầu dùng micrô, Hanasu hỏi bạn có muốn ghi âm không. Ứng dụng không bao giờ tự bắt đầu ghi âm. |
| **Tìm kiếm & Hỏi đáp** | Tìm trong nội dung của mọi cuộc họp, hoặc hỏi "Cuộc họp tuần trước chúng ta đã quyết định gì?". Câu trả lời có trích dẫn các cuộc họp được dùng làm nguồn. |
| **Xuất** | Sao chép dưới dạng Markdown hoặc bản tóm tắt sẵn để gửi lên Slack, lưu thành `.md` / `.txt`, hoặc gửi các đầu việc sang Lời nhắc. |
| **Sắp xếp** | Đổi tên cuộc họp bằng cách sửa trực tiếp tiêu đề, hoặc xóa cuộc họp bạn không còn cần. |

<p align="center">
  <img src="docs/images/meeting-live.png" width="420" alt="Ghi âm kèm ghi chú trực tiếp">
  <img src="docs/images/meeting-ask.png" width="420" alt="Hỏi đáp về các cuộc họp">
</p>
<p align="center">
  <img src="docs/images/meeting-minutes.png" width="420" alt="Biên bản kèm các đầu việc">
  <img src="docs/images/meeting-suggestion.png" width="420" alt="Phát hiện cuộc họp">
</p>

### 🤖 Chọn AI

Chọn AI dùng để chỉnh sửa văn bản, riêng cho **nhập liệu bằng giọng nói** và **cuộc họp**.

| AI | Mô hình mặc định | Đăng nhập |
| --- | --- | --- |
| **Gemini** (mặc định trên Windows) | nhập liệu bằng giọng nói `gemini-3.5-flash-lite`, cuộc họp `gemini-3.8-flash` | Khóa API Google AI Studio hoặc tài khoản dịch vụ Vertex AI |
| **Claude** | nhập liệu bằng giọng nói `claude-haiku-5-5`, cuộc họp `claude-sonnet-5-5` (có cả Opus 5.5) | Khóa API Anthropic |
| **Cục bộ** (trên thiết bị của bạn; mặc định trên Mac) | Gemma 4 E4B (khuyên dùng). Xem bảng bên dưới | Không cần. Tải mô hình trong **Cài đặt → AI**. Trên Mac, nếu chưa có mô hình khi Hanasu bắt đầu chỉnh sửa văn bản, ứng dụng sẽ hỏi bạn có muốn tải về không |
| **Apple** *(Mac, macOS 27)* | Mô hình Apple Intelligence trên thiết bị, thông qua lệnh `fm` | Không cần |

Các AI này chỉ xử lý văn bản. Giọng nói được chép lời bởi công cụ nhận dạng bên dưới.

#### 💻 Mô hình cục bộ

Với **Cục bộ**, Hanasu chạy một mô hình ngôn ngữ nhỏ ngay trên Mac hoặc PC của bạn bằng [llama.cpp](https://github.com/ggml-org/llama.cpp) đi kèm, nên văn bản của bạn không bao giờ rời khỏi thiết bị. Mac dùng GPU (Metal), còn Windows dùng CPU. Bạn chỉ cần tải mô hình một lần từ **Cài đặt → AI**. Hanasu kiểm tra kích thước và SHA-256 của mô hình trước khi sử dụng.

| Mô hình | Kích thước | Giấy phép | Ghi chú |
| --- | --- | --- | --- |
| **Gemma 4 E4B** (Google) — **khuyên dùng** | 4.59 GB | Apache-2.0 | Cho kết quả tự nhiên nhất cả khi chỉnh sửa văn bản lẫn khi viết biên bản. Nên có từ 16 GB bộ nhớ trở lên. Mặc định cho cả nhập liệu bằng giọng nói và cuộc họp |
| LFM2.5-1.2B-JP (Liquid AI) | 1.25 GB | LFM Open License v1.0 | Nhỏ và nhanh. Theo giấy phép này, tổ chức có doanh thu hằng năm từ 10 triệu USD trở lên không được dùng cho mục đích thương mại |
| Sarashina2.2 3B (SB Intuitions) | 2.07 GB | MIT | Được huấn luyện bằng tiếng Nhật. Ngữ cảnh chỉ 8K nên cuộc họp dài sẽ được tóm tắt theo từng phần |
| Qwen3.5-4B (Alibaba) | 2.74 GB | Apache-2.0 | Kích thước khoảng một nửa Gemma nên dễ chạy hơn với 8 GB bộ nhớ. Xử lý chỗ tự sửa lời kém hơn Gemma |

> [!TIP]
> Chúng tôi khuyên dùng **Gemma 4 E4B**. Trong các thử nghiệm của chúng tôi, những mô hình khác đôi khi giữ lại những từ bạn định rút lại, thêm câu bạn không hề nói, nhầm người phụ trách đầu việc, hoặc gộp hay bỏ sót đầu việc. Gemma 4 E4B xử lý ổn định cả việc chỉnh sửa văn bản lẫn viết biên bản.

### 🔊 Chọn công cụ nhận dạng giọng nói

| Công cụ | Chạy trên | Chép lời trực tiếp | Ghi chú |
| --- | --- | --- | --- |
| **Mặc định của hệ điều hành** (mặc định) | Mac: `SpeechAnalyzer` · Windows: `Windows.Media.SpeechRecognition` | ✅ | Trên Mac chạy ngay trên thiết bị |
| **Whisper** | Trên thiết bị (WhisperKit trên Mac, whisper.cpp trên Windows) | — (sau khi dừng) | Mô hình được tải về khi bạn chọn |
| **Gemini** | Google | — (sau khi dừng) | Âm thanh đã ghi được gửi đến Google |

Bạn có thể chọn công cụ khác nhau cho nhập liệu bằng giọng nói và cho cuộc họp. Trên Windows, cuộc họp dùng Whisper hoặc Gemini.
Trên Mac, chọn ngôn ngữ chép lời từ danh sách (tiếng Nhật, tiếng Anh, tiếng Trung, tiếng Hàn, tiếng Pháp, tiếng Đức, tiếng Tây Ban Nha, tiếng Ý, tiếng Bồ Đào Nha). Ban đầu ngôn ngữ này được đặt theo ngôn ngữ hệ thống của bạn.

## Tải về

Tải bản mới nhất từ [**Releases**](https://github.com/kakibara/hanasu/releases/latest).

| Nền tảng | Tệp | Yêu cầu |
| --- | --- | --- |
| macOS | `Hanasu-<version>-macOS.zip` | macOS 26 (Tahoe) trở lên, Apple Silicon |
| Windows | `Hanasu-<version>-Windows-x64.zip` | Windows 10 (2004 trở lên) / 11, x64 |

<details>
<summary><b>macOS: lần mở đầu tiên</b></summary>

1. Giải nén tệp và di chuyển `Hanasu.app` vào **Ứng dụng**.
2. Ứng dụng được tự ký và chưa được Apple công chứng (notarize), nên macOS sẽ chặn ở lần mở đầu tiên. Bấm **Xong**, sau đó mở **Cài đặt hệ thống → Quyền riêng tư & Bảo mật** và bấm **Vẫn mở**.
   Bạn cũng có thể chạy `xattr -dr com.apple.quarantine /Applications/Hanasu.app` thay vào đó.
3. Khi được hỏi, hãy cho phép **Micrô**, **Nhận dạng giọng nói** và **Trợ năng**. Quyền Trợ năng là cần thiết để dán bằng ⌘V.

</details>

<details>
<summary><b>Windows: lần mở đầu tiên</b></summary>

1. Giải nén tệp, đặt thư mục `Hanasu` ở bất kỳ đâu (ví dụ `%LOCALAPPDATA%\Programs`) và chạy `Hanasu.exe`.
2. Ứng dụng chưa được ký mã, nên SmartScreen sẽ hiện cảnh báo. Bấm **Thông tin thêm → Vẫn chạy**.
3. Công cụ nhận dạng giọng nói của Windows cần bật **Nhận dạng giọng nói trực tuyến** trong phần cài đặt của Windows. Hanasu sẽ báo cho bạn nếu tùy chọn này đang tắt.

Xem [windows/README.md](windows/README.md) để biết thêm ghi chú và những điểm khác nhau giữa bản Windows và bản Mac.

</details>

## Bắt đầu nhanh

Trên Mac, lần mở đầu tiên sẽ hiện một phần hướng dẫn ngắn. Phần này cho bạn chọn AI (Gemma 4 E4B, mô hình cục bộ được khuyên dùng, có thể tải ngay tại đó), giới thiệu các tính năng chính và mẹo cài đặt, đồng thời xin các quyền mà Hanasu cần. Bạn có thể mở lại bất cứ lúc nào từ mục **Cách dùng Hanasu…** trong menu.

1. **Chọn AI.** Mở **Cài đặt → AI** và chọn AI cho nhập liệu bằng giọng nói và cho cuộc họp. Với Gemini, dán khóa API lấy từ [Google AI Studio](https://aistudio.google.com/apikey) hoặc chọn tệp JSON của tài khoản dịch vụ Vertex AI. Với Claude, dán khóa API lấy từ [Claude Console](https://console.anthropic.com/settings/keys). Với Cục bộ, tải một mô hình về (khuyên dùng Gemma 4 E4B). Không cần khóa. Bấm nút kiểm tra để xác nhận mọi thứ hoạt động.
2. **Đọc chính tả.** Đặt con trỏ ở nơi bạn muốn có văn bản, nhấn phím tắt, nói, rồi nhấn lại phím tắt.
3. **Ghi âm cuộc họp.** Dùng menu trên thanh menu (Mac) hoặc khay hệ thống (Windows), hoặc dùng phím tắt. Đeo tai nghe sẽ giúp tách biệt âm thanh của hai phía.

Trên Mac, bạn có thể hiện biểu tượng Hanasu trên thanh menu, trên Dock hoặc cả hai (Cài đặt → Chung).

### Phím tắt mặc định

| Thao tác | macOS | Windows |
| --- | --- | --- |
| Nhập liệu bằng giọng nói (bắt đầu / dừng) | <kbd>⌥ Space</kbd> | <kbd>Ctrl Alt Space</kbd> |
| Nhập liệu bằng giọng nói kèm dịch (tiếng Anh / tiếng Nhật) | <kbd>⌥⇧ Space</kbd> | <kbd>Ctrl Alt Shift Space</kbd> |
| Chỉnh sửa vùng chọn bằng giọng nói | <kbd>⌃⌥⌘ E</kbd> | — |
| Dán lại kết quả gần nhất | <kbd>⌥⇧ V</kbd> | — |
| Hủy ghi âm | <kbd>Esc</kbd> | <kbd>Esc</kbd> |
| Ghi âm cuộc họp (bắt đầu / dừng) | <kbd>⌃⌥⌘ M</kbd> | <kbd>Ctrl Alt Shift M</kbd> |
| Đánh dấu "chỗ này quan trọng" trong cuộc họp | <kbd>⌃⌥⌘ H</kbd> | <kbd>Ctrl Alt Shift H</kbd> |

Bạn có thể thay đổi mọi phím tắt trong Cài đặt. Hướng dẫn sử dụng đầy đủ (bằng tiếng Nhật) nằm ở [docs/guide.md](docs/guide.md).

## Quyền riêng tư

- **Âm thanh mặc định ở lại trên thiết bị của bạn.** Nhận dạng giọng nói, Whisper và phân tách người nói đều chạy cục bộ.
- **AI nhận văn bản, không nhận âm thanh.** Gemini hoặc Claude nhận bản chép lời. Tùy theo cài đặt, AI cũng có thể nhận tên ứng dụng bạn đang gõ, ngữ cảnh màn hình và bản chép lời cuộc họp cho tính năng Hỏi đáp và trò chuyện với AI trong cuộc họp.
- **Cục bộ và Apple cũng giữ văn bản trên thiết bị của bạn.** Nếu bạn chọn một trong hai, không có gì được gửi đến dịch vụ AI nào. Thứ duy nhất được tải về là chính mô hình.
- **Âm thanh chỉ được gửi đến Google nếu bạn chọn.** Nếu bạn chọn công cụ nhận dạng giọng nói Gemini, âm thanh đã ghi sẽ được gửi đến Google.
- **Cuộc họp là các tệp thông thường.** Chúng được lưu dưới dạng JSON và Markdown trong `~/Documents/Hanasu/Meetings/` (Windows: `Documents\Hanasu\Meetings\`). Mac và Windows dùng cùng một định dạng.
- **Không thu thập dữ liệu từ xa (telemetry).** Hanasu không thu thập dữ liệu phân tích nào.
- **Khóa API được hệ điều hành bảo vệ.** Trên macOS, khóa được lưu trong Keychain và các ứng dụng khác phải hỏi mật khẩu đăng nhập của bạn mới đọc được. Trên Windows, khóa được mã hóa bằng DPAPI, hoặc bằng khóa Windows Hello nếu bạn chọn. Cả hai cách đều không thể ngăn hoàn toàn phần mềm độc hại chạy dưới tài khoản người dùng của bạn. Xem [docs/design/security.md](docs/design/security.md).

> [!IMPORTANT]
> Hãy xin sự đồng ý của mọi người trong cuộc họp trước khi ghi âm. Tuân thủ quy định của tổ chức bạn về việc ghi âm và sử dụng dịch vụ AI.

## Build từ mã nguồn

<details>
<summary><b>macOS</b> (Xcode Command Line Tools, Swift 6.2)</summary>

```bash
./scripts/build-app.sh             # build ra build/Hanasu.app
open build/Hanasu.app
./scripts/create-signing-cert.sh   # tùy chọn: giữ các quyền qua những lần build lại
```

</details>

<details>
<summary><b>Windows</b> (.NET 8 SDK)</summary>

```bash
cd windows
dotnet build Hanasu.Windows.sln
dotnet publish Hanasu.Windows/Hanasu.Windows.csproj -c Release -r win-x64 --self-contained -p:PublishSingleFile=true -o publish/win-x64
```

Xem [windows/README.md](windows/README.md).

</details>

## Tài liệu

Tài liệu được viết bằng tiếng Nhật.

| | |
| --- | --- |
| [docs/guide.md](docs/guide.md) | Hướng dẫn sử dụng: cách dùng, cài đặt, quy tắc từ điển |
| [docs/spec/](docs/spec/) | Các yêu cầu đã triển khai (`REQ-*`) và quyết định thiết kế (`DEC-*`) |
| [docs/design/](docs/design/) | Cách ứng dụng được xây dựng: kiến trúc và luồng dữ liệu |
| [docs/roadmap.md](docs/roadmap.md) | Các kế hoạch chưa được triển khai |
| [docs/releasing.md](docs/releasing.md) | Cách phát hành phiên bản (tagpr) |

## Đóng góp

Chúng tôi hoan nghênh issue và pull request.

1. Đọc [docs/README.md](docs/README.md) trước khi thay đổi bất kỳ hành vi nào.
2. Mã nguồn được gắn thẻ `// 要件: REQ-…` (yêu cầu) hoặc `// 設計判断: DEC-…` (quyết định thiết kế). Trong CI, `scripts/check-spec.py` kiểm tra rằng spec được cập nhật mỗi khi mã có gắn thẻ thay đổi.
3. Một tính năng mới bắt đầu bằng một yêu cầu trong `docs/spec/`. Ý tưởng để làm sau được ghi vào `docs/roadmap.md`.

## Giấy phép

[Apache License 2.0](LICENSE) © 2026 kakibara. Xem [NOTICE](NOTICE).
Giấy phép của bên thứ ba được liệt kê trong [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) (macOS) và [windows/THIRD_PARTY_NOTICES.md](windows/THIRD_PARTY_NOTICES.md) (Windows). Cả hai tệp đều có trong gói tải về.
