<div align="center">

<img src="docs/images/icon.png" width="112" alt="Ikon Hanasu">

# Hanasu

**Bicaralah secara alami. Dapatkan teks yang rapi dan siap kirim, serta notulen rapat yang tertulis dengan sendirinya.**

Aplikasi input suara dan pencatat rapat untuk macOS dan Windows. Aplikasi ini memakai pengenalan ucapan di perangkat, serta Gemini, Claude, atau model AI yang berjalan di perangkat Anda sendiri.

[![Release](https://img.shields.io/github/v/release/kakibara/hanasu?sort=semver&label=release)](https://github.com/kakibara/hanasu/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/kakibara/hanasu/total)](https://github.com/kakibara/hanasu/releases)
[![License](https://img.shields.io/badge/license-PolyForm%20Noncommercial%20%2B%20small%20business-blue)](COMMERCIAL.md)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-000000?logo=apple)
![Windows 10/11](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows)
[![Windows build](https://github.com/kakibara/hanasu/actions/workflows/windows.yml/badge.svg)](https://github.com/kakibara/hanasu/actions/workflows/windows.yml)

[English](README.md) · [日本語](README.ja.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Italiano](README.it.md) · [Português (Brasil)](README.pt-BR.md) · [Русский](README.ru.md) · [Türkçe](README.tr.md) · [Tiếng Việt](README.vi.md) · **Bahasa Indonesia** · [Polski](README.pl.md) · [العربية](README.ar.md) · [हिन्दी](README.hi.md)

<sub>Ini adalah terjemahan dari README berbahasa Inggris. Jika ada perbedaan, README berbahasa Inggris adalah versi yang paling mutakhir.</sub>

<img src="docs/images/hud.png" width="560" alt="HUD perekaman Hanasu">

</div>

> [!NOTE]
> Hanasu dibuat terutama untuk **bahasa Jepang**, dan bahasa Jepang adalah bahasa yang paling banyak diuji.
> Layar aplikasi dan instruksi yang diberikannya kepada AI tersedia dalam 17 bahasa yang sama dengan README ini. Layar mengikuti bahasa sistem, sedangkan instruksi AI mengikuti bahasa transkripsi di Pengaturan. Untuk bahasa lainnya, Hanasu memakai bahasa Inggris.
> Hanasu juga dapat menerjemahkan ucapan Anda ke **bahasa Inggris**, **bahasa Jepang**, atau salah satu dari 17 bahasa yang didukung secara alami sebelum mengetikkannya.

## Mengapa Hanasu

Fitur dikte bawaan hanya memberi Anda transkrip mentah. Kata pengisi dan salah tulis homofon tetap ada, tidak ada tanda baca, dan setiap "eh, maksud saya…" ikut tertulis.
Hanasu mengirim transkrip ke AI (Gemini, Claude, atau model lokal di perangkat Anda), yang memperbaiki kesalahan tersebut dan merapikan teksnya. Lalu Hanasu mengetikkan hasilnya di posisi kursor Anda.
Hanasu terinspirasi oleh Typeless, Wispr Flow, Aqua Voice, dan Granola. Kode sumber Hanasu bersifat publik. Hanasu gratis untuk penggunaan pribadi dan untuk usaha kecil; perusahaan yang lebih besar memerlukan [lisensi komersial](COMMERCIAL.md). Anda memakai kunci API Gemini atau Claude milik sendiri, atau menjalankan model lokal tanpa kunci API dan tanpa ada teks yang keluar dari perangkat Anda.

## Fitur

### 🎙️ Input suara

| | |
| --- | --- |
| **Bicara → teks yang rapi** | Tekan <kbd>⌥ Space</kbd>, bicara, lalu tekan lagi (atau klik **■ Berhenti**). Hanasu menghapus kata pengisi, memperbaiki homofon, menerapkan koreksi yang Anda ucapkan sendiri, dan menempelkan teks di posisi kursor. |
| **Bicara, ketik hasil terjemahan** | Tekan <kbd>⌥⇧ Space</kbd>, atau ubah HUD ke **English**, **日本語**, atau bahasa lain saat Anda berbicara. Ungkapan baku diterjemahkan secara alami, jadi お疲れ様です menjadi "Hi,". Pilih bahasa yang ditawarkan (mana saja dari 17 bahasa yang didukung) di **Pengaturan → Umum**. Bawaannya adalah bahasa Inggris. Di Mac, **Pengaturan → Per App** dapat membuat sebuah aplikasi dimulai dalam salah satu bahasa ini. |
| **Campuran bahasa tetap seperti yang diucapkan** | Secara bawaan, bagian yang Anda ucapkan dalam bahasa Inggris tetap dalam bahasa Inggris. Anda bisa memilih untuk menyeragamkan seluruh keluaran ke bahasa Jepang. |
| **Edit dengan suara** | Pilih teks, tekan <kbd>⌃⌥⌘ E</kbd>, lalu ucapkan "buat lebih sopan", "ubah jadi poin-poin", atau "terjemahkan ke bahasa Inggris". |
| **Gaya per aplikasi** | Di Slack teks dibuat santai dan singkat, di Mail sopan dan berparagraf, dan di Pages, Word, serta Notion memakai gaya bahasa tulis. Anda dapat mengubah preset untuk setiap aplikasi. |
| **Snippet** | Ucapkan "tanda tangan email" untuk menyisipkan teks tersimpan persis seperti yang Anda tulis. Snippet tidak pernah dikirim ke AI. |
| **Kamus** | Tambahkan nama diri dan aturan penggantian seperti `ストックマーク => Stockmark`. Aturan penggantian juga diterapkan pada transkrip rapat. Dari rapat yang dibuka di Catatan rapat, AI dapat menyarankan entri baru dari rapat tersebut (di Mac, juga dari riwayat dan rapat terbaru Anda), dan Anda hanya menambahkan yang Anda pilih. |
| **Konteks layar** *(opsional)* | Hanasu membaca judul jendela dan teks di sekitar kursor, sehingga nama-nama cocok dengan apa yang sudah ada di layar. Kolom kata sandi tidak pernah dibaca. |
| **Pilih mikrofon** *(Mac)* | Pilih mikrofon di Pengaturan, atau ganti lewat tombol mikrofon di HUD tanpa menghentikan perekaman. |
| **Riwayat** | Cari hasil sebelumnya dan ulangi yang gagal. Secara bawaan riwayat disimpan selama 30 hari, dan Anda dapat mengubahnya di Pengaturan. Di Mac, tekan <kbd>⌥⇧ V</kbd> untuk menempelkan hasil terakhir lagi. |
| **Tidak ada tempat untuk menempel?** | Jika tidak ada kolom teks yang sedang aktif (misalnya desktop sedang di depan), Hanasu menampilkan hasilnya di layar alih-alih menempelkannya. Salin dari sana, atau cukup tekan <kbd>⌘V</kbd> di tempat yang Anda inginkan (Anda dapat memilih apakah hasilnya tetap ada di clipboard). |
| **Tempelan tidak sampai?** | Jika tempelan tidak sampai ke aplikasi mana pun (misalnya Anda berpindah jendela saat merekam), Hanasu meninggalkan hasil terbaru di clipboard dan memberi tahu Anda di HUD. Tekan <kbd>⌘V</kbd> di tempat yang Anda inginkan. Di Pengaturan → Umum, Anda juga dapat membuat riwayat dikte terbuka saat hal ini terjadi. |

<p align="center">
  <img src="docs/images/hud-english.png" width="420" alt="Keluaran bahasa Inggris">
  <img src="docs/images/edit-mode.png" width="420" alt="Edit dengan suara">
</p>

### 📝 Catatan rapat

| | |
| --- | --- |
| **Merekam kedua pihak** | Mikrofon Anda direkam sebagai "Anda". Keluaran audio Mac (Zoom, Meet, Teams, huddle Slack, dan sebagainya) direkam sebagai "mereka". Tidak ada bot yang ikut bergabung ke panggilan. |
| **Pemisahan pembicara** | Pihak lawan bicara dipisahkan menjadi Pembicara 1, Pembicara 2, dan seterusnya, langsung di perangkat. Jika percakapan memperjelas sebuah nama (misalnya seseorang memperkenalkan diri), AI mengisinya dan menandainya sebagai tebakan. Anda dapat mengganti nama pembicara setelahnya. |
| **Notulen AI** | Dibuat oleh AI yang Anda pilih untuk rapat. Pilih templat: otomatis, rapat mingguan, 1-on-1, panggilan penjualan, curah gagasan, atau kustom. Butir tindakan dilengkapi penanggung jawab dan tenggat waktu. |
| **Cek sumber & dengarkan lagi** *(Mac)* | Notulen terbuka dalam satu halaman: ringkasan dan item tindakan di bagian atas, dengan transkrip di sampingnya. Klik tanda waktu di akhir sebuah poin untuk melompat ke ucapan asalnya. Putar rekaman dari ucapan mana pun, dan bisukan suara Anda atau suara mereka jika panggilan bergema. |
| **Catatan langsung & sorotan** | Ketik catatan bertanda waktu selama panggilan, atau tekan <kbd>⌃⌥⌘ H</kbd> untuk menandai "ini penting" (dapat dibatalkan dalam 10 detik). Notulen memprioritaskan bagian-bagian tersebut, dan setelahnya Anda dapat membaca percakapan di sekitar setiap tanda. |
| **Teks terjemahan mengambang** *(Mac)* | Tampilkan transkrip langsung sebagai teks di atas aplikasi rapat Anda. |
| **Obrolan AI selama rapat** *(Mac)* | Saat merekam, tanyakan kepada AI tentang percakapan sejauh ini (<kbd>⌘J</kbd>). Sekali klik untuk "ringkasan sejauh ini" atau "keputusan & tugas". Ajukan pertanyaan lanjutan, dan klik tanda waktu dalam jawaban untuk melompat ke bagian transkrip tersebut. |
| **Deteksi rapat** | Saat aplikasi rapat mulai memakai mikrofon, Hanasu bertanya apakah Anda ingin merekam. Hanasu tidak pernah mulai merekam dengan sendirinya. |
| **Cari & Tanya** | Cari teks di semua rapat, atau tanyakan "Apa yang kita putuskan di rapat mingguan lalu?". Jawabannya mencantumkan rapat yang menjadi sumbernya. |
| **Ekspor** | Salin sebagai Markdown atau sebagai ringkasan yang siap untuk Slack, simpan sebagai `.md` / `.txt`, atau kirim butir tindakan ke Pengingat. |
| **Atur** | Ganti nama rapat dengan mengedit judulnya langsung, atau hapus rapat yang tidak lagi Anda perlukan. |

<p align="center">
  <img src="docs/images/meeting-live.png" width="420" alt="Merekam dengan catatan langsung">
  <img src="docs/images/meeting-ask.png" width="420" alt="Bertanya tentang rapat Anda">
</p>
<p align="center">
  <img src="docs/images/meeting-minutes.png" width="420" alt="Notulen dengan butir tindakan">
  <img src="docs/images/meeting-suggestion.png" width="420" alt="Deteksi rapat">
</p>

### 🤖 Pilih AI Anda

Pilih AI yang merapikan teks Anda, secara terpisah untuk **input suara** dan **rapat**.

| AI | Model bawaan | Masuk |
| --- | --- | --- |
| **Gemini** (bawaan di Windows) | input suara `gemini-3.5-flash-lite`, rapat `gemini-3.8-flash` | Kunci API Google AI Studio atau akun layanan Vertex AI |
| **Claude** | input suara `claude-haiku-5-5`, rapat `claude-sonnet-5-5` (Opus 5.5 juga tersedia) | Kunci API Anthropic |
| **Lokal** (di perangkat Anda; bawaan di Mac) | Gemma 4 E4B (disarankan). Lihat tabel di bawah | Tidak perlu. Unduh model di **Pengaturan → AI**. Di Mac, jika model belum ada saat Hanasu mulai merapikan teks, Hanasu akan menanyakan apakah model perlu diunduh |
| **Apple** *(Mac, macOS 27)* | Model Apple Intelligence di perangkat, melalui perintah `fm` | Tidak perlu |

AI ini hanya menangani teks. Ucapan ditranskripsikan oleh mesin di bawah ini.

#### 💻 Model lokal

Dengan **Lokal**, Hanasu menjalankan model bahasa kecil di Mac atau PC Anda sendiri dengan [llama.cpp](https://github.com/ggml-org/llama.cpp) yang sudah disertakan, sehingga teks Anda tidak pernah keluar dari perangkat. Mac memakai GPU (Metal), sedangkan Windows memakai CPU. Anda cukup mengunduh model sekali dari **Pengaturan → AI**. Hanasu memeriksa ukuran dan SHA-256 model sebelum memakainya.

| Model | Ukuran | Lisensi | Catatan |
| --- | --- | --- | --- |
| **Gemma 4 E4B** (Google) — **disarankan** | 4.59 GB | Apache-2.0 | Hasil paling alami, baik untuk merapikan teks maupun notulen. Disarankan memori 16 GB atau lebih. Bawaan untuk input suara dan rapat |
| LFM2.5-1.2B-JP (Liquid AI) | 1.25 GB | LFM Open License v1.0 | Kecil dan cepat. Organisasi dengan pendapatan tahunan US$10 juta atau lebih tidak boleh memakainya secara komersial di bawah lisensi ini |
| Sarashina2.2 3B (SB Intuitions) | 2.07 GB | MIT | Dilatih dengan bahasa Jepang. Konteksnya 8K, jadi rapat yang panjang diringkas per bagian |
| Qwen3.5-4B (Alibaba) | 2.74 GB | Apache-2.0 | Sekitar setengah ukuran Gemma, jadi lebih mudah dijalankan dengan memori 8 GB. Lebih lemah daripada Gemma dalam menangani koreksi yang diucapkan sendiri |

> [!TIP]
> Kami menyarankan **Gemma 4 E4B**. Dalam pengujian kami, model lain kadang mempertahankan kata yang ingin Anda tarik kembali, menambahkan kalimat yang tidak Anda ucapkan, keliru menentukan penanggung jawab butir tindakan, atau menggabungkan maupun melewatkan butir tindakan. Gemma 4 E4B menangani perapian teks dan notulen dengan andal.

### 🔊 Pilih mesin ucapan Anda

| Mesin | Berjalan di | Transkrip langsung | Catatan |
| --- | --- | --- | --- |
| **Standar OS** (bawaan) | Mac: `SpeechAnalyzer` · Windows: `Windows.Media.SpeechRecognition` | ✅ | Di perangkat pada Mac |
| **Whisper** | Di perangkat (WhisperKit di Mac, whisper.cpp di Windows) | — (setelah Anda berhenti) | Model diunduh saat Anda memilihnya |
| **Gemini** | Google | — (setelah Anda berhenti) | Audio rekaman dikirim ke Google |

Anda dapat memilih mesin yang berbeda untuk input suara dan untuk rapat. Di Windows, rapat memakai Whisper atau Gemini.
Di Mac, pilih bahasa transkripsi dari daftar (Jepang, Inggris, Tionghoa, Korea, Prancis, Jerman, Spanyol, Italia, Portugis). Awalnya bahasa ini mengikuti bahasa sistem Anda.

## Unduh

Dapatkan build terbaru dari [**Releases**](https://github.com/kakibara/hanasu/releases/latest).

| Platform | Berkas | Persyaratan |
| --- | --- | --- |
| macOS | `Hanasu-<version>-macOS.zip` | macOS 26 (Tahoe) atau lebih baru, Apple Silicon |
| Windows | `Hanasu-<version>-Windows-x64.zip` | Windows 10 (2004 atau lebih baru) / 11, x64 |

<details>
<summary><b>macOS: pertama kali dibuka</b></summary>

1. Ekstrak berkas dan pindahkan `Hanasu.app` ke **Aplikasi**.
2. Aplikasi ini ditandatangani sendiri (self-signed) dan belum dinotarisasi, jadi macOS memblokirnya saat pertama kali dibuka. Klik **Selesai**, lalu buka **Pengaturan Sistem → Privasi & Keamanan** dan klik **Tetap Buka**.
   Anda juga bisa menjalankan `xattr -dr com.apple.quarantine /Applications/Hanasu.app` sebagai gantinya.
3. Saat diminta, izinkan **Mikrofon**, **Pengenalan Ucapan**, dan **Aksesibilitas**. Aksesibilitas diperlukan untuk menempel dengan ⌘V.

</details>

<details>
<summary><b>Windows: pertama kali dibuka</b></summary>

1. Ekstrak berkas, letakkan folder `Hanasu` di mana saja (misalnya `%LOCALAPPDATA%\Programs`), lalu jalankan `Hanasu.exe`.
2. Aplikasi ini tidak memiliki tanda tangan kode, jadi SmartScreen menampilkan peringatan. Klik **Info selengkapnya → Tetap jalankan**.
3. Mesin ucapan Windows memerlukan **Pengenalan ucapan online** diaktifkan di pengaturan Windows. Hanasu akan memberi tahu Anda jika fitur ini nonaktif.

Lihat [windows/README.md](windows/README.md) untuk catatan lainnya dan perbedaan versi Windows dengan versi Mac.

</details>

Saat versi baru dirilis, Hanasu memberi tahu Anda ketika dibuka dan bertanya sebelum memperbarui dirinya sendiri. Anda juga dapat memilih **アップデートを確認…** (Periksa Pembaruan) di menu (pemeriksaan saat dibuka dapat dimatikan di **Pengaturan → Umum**). Versi hingga v1.5.0 belum memiliki fitur ini, jadi perbarui versi tersebut secara manual sekali.

## Mulai cepat

Di Mac, saat pertama kali dibuka akan muncul tur panduan singkat. Tur ini memungkinkan Anda memilih AI (Gemma 4 E4B, model lokal yang disarankan, langsung diunduh di sana), menunjukkan fitur utama dan tips pengaturan, serta meminta izin yang dibutuhkan Hanasu. Buka kembali kapan saja dari **Cara menggunakan Hanasu…** di menu.

1. **Pilih AI.** Buka **Pengaturan → AI** dan pilih AI untuk input suara dan untuk rapat. Untuk Gemini, tempelkan kunci API dari [Google AI Studio](https://aistudio.google.com/apikey) atau pilih berkas JSON akun layanan Vertex AI. Untuk Claude, tempelkan kunci API dari [Claude Console](https://console.anthropic.com/settings/keys). Untuk Lokal, unduh sebuah model (Gemma 4 E4B disarankan). Tidak perlu kunci. Klik tombol uji untuk memastikan semuanya berfungsi.
2. **Dikte.** Letakkan kursor di tempat Anda menginginkan teks, tekan pintasan, bicara, lalu tekan pintasan lagi.
3. **Rekam rapat.** Gunakan menu di bilah menu (Mac) atau baki sistem (Windows), atau pintasan. Headphone membantu memisahkan suara kedua pihak.

Di Mac, Anda dapat menampilkan ikon Hanasu di bilah menu, di Dock, atau di keduanya (Pengaturan → Umum).

### Pintasan bawaan

| Tindakan | macOS | Windows |
| --- | --- | --- |
| Input suara (mulai / berhenti) | <kbd>⌥ Space</kbd> | <kbd>Ctrl Alt Space</kbd> |
| Input suara dengan terjemahan (ke bahasa yang Anda pilih) | <kbd>⌥⇧ Space</kbd> | <kbd>Ctrl Alt Shift Space</kbd> |
| Edit pilihan dengan suara | <kbd>⌃⌥⌘ E</kbd> | — |
| Tempel lagi hasil terakhir | <kbd>⌥⇧ V</kbd> | — |
| Batalkan perekaman | <kbd>Esc</kbd> | <kbd>Esc</kbd> |
| Perekaman rapat (mulai / berhenti) | <kbd>⌃⌥⌘ M</kbd> | <kbd>Ctrl Alt Shift M</kbd> |
| Tandai "ini penting" dalam rapat | <kbd>⌃⌥⌘ H</kbd> | <kbd>Ctrl Alt Shift H</kbd> |

Anda dapat mengubah semua pintasan di Pengaturan. Panduan pengguna lengkap (dalam bahasa Jepang) ada di [docs/guide.md](docs/guide.md).

## Privasi

- **Secara bawaan, audio tetap di perangkat Anda.** Pengenalan ucapan, Whisper, dan pemisahan pembicara semuanya berjalan secara lokal.
- **AI menerima teks, bukan audio.** Gemini atau Claude menerima transkrip. Tergantung pengaturan Anda, AI juga dapat menerima nama aplikasi tempat Anda mengetik, konteks layar, dan transkrip rapat untuk fitur Tanya dan obrolan AI selama rapat.
- **Lokal dan Apple juga menyimpan teks di perangkat Anda.** Jika Anda memilih salah satunya, tidak ada yang dikirim ke layanan AI. Satu-satunya yang diunduh adalah model itu sendiri.
- **Audio dikirim ke Google hanya jika Anda memilihnya.** Jika Anda memilih mesin ucapan Gemini, audio rekaman dikirim ke Google.
- **Rapat disimpan sebagai berkas biasa.** Rapat disimpan dalam format JSON dan Markdown di `~/Documents/Hanasu/Meetings/` (Windows: `Documents\Hanasu\Meetings\`). Mac dan Windows memakai format yang sama.
- **Tanpa telemetri.** Hanasu tidak mengumpulkan data analitik apa pun.
- **Kunci API dilindungi oleh OS.** Di macOS, kunci disimpan di Keychain, dan aplikasi lain harus meminta kata sandi login Anda untuk membacanya. Di Windows, kunci dienkripsi dengan DPAPI, atau dengan kunci Windows Hello jika Anda memilihnya. Keduanya tidak dapat sepenuhnya menghentikan malware yang berjalan sebagai pengguna Anda. Lihat [docs/design/security.md](docs/design/security.md).

> [!IMPORTANT]
> Mintalah persetujuan dari semua peserta rapat sebelum Anda merekam. Patuhi aturan organisasi Anda mengenai perekaman dan penggunaan layanan AI.

## Build dari kode sumber

<details>
<summary><b>macOS</b> (Xcode Command Line Tools, Swift 6.2)</summary>

```bash
./scripts/build-app.sh             # membangun build/Hanasu.app
open build/Hanasu.app
./scripts/create-signing-cert.sh   # opsional: mempertahankan izin di setiap build ulang
```

</details>

<details>
<summary><b>Windows</b> (.NET 8 SDK)</summary>

```bash
cd windows
dotnet build Hanasu.Windows.sln
dotnet publish Hanasu.Windows/Hanasu.Windows.csproj -c Release -r win-x64 --self-contained -p:PublishSingleFile=true -o publish/win-x64
```

Lihat [windows/README.md](windows/README.md).

</details>

## Dokumentasi

Dokumentasi ditulis dalam bahasa Jepang.

| | |
| --- | --- |
| [docs/guide.md](docs/guide.md) | Panduan pengguna: cara penggunaan, pengaturan, aturan kamus |
| [docs/spec/](docs/spec/) | Persyaratan yang sudah diimplementasikan (`REQ-*`) dan keputusan desain (`DEC-*`) |
| [docs/design/](docs/design/) | Cara aplikasi dibangun: arsitektur dan alur data |
| [docs/roadmap.md](docs/roadmap.md) | Rencana yang belum diimplementasikan |
| [docs/releasing.md](docs/releasing.md) | Cara rilis dibuat (tagpr) |

## Berkontribusi

Issue dan pull request sangat diterima.

1. Baca [docs/README.md](docs/README.md) sebelum Anda mengubah perilaku apa pun.
2. Kode diberi tag `// 要件: REQ-…` (persyaratan) atau `// 設計判断: DEC-…` (keputusan desain). Di CI, `scripts/check-spec.py` memeriksa bahwa spec diperbarui setiap kali kode yang bertag berubah.
3. Fitur baru dimulai sebagai persyaratan di `docs/spec/`. Ide untuk nanti dicatat di `docs/roadmap.md`.

## Lisensi

Hanasu bersifat source-available (kode sumber tersedia), bukan open source. © 2026 kakibara. Lihat [NOTICE](NOTICE).

- Lisensi: [PolyForm Noncommercial License 1.0.0](LICENSE) ditambah [Hanasu Additional Permission 1.0](LICENSE-ADDITIONAL-PERMISSION.md).
- Gratis untuk penggunaan pribadi nonkomersial, pendidikan, penelitian, lembaga amal dan pemerintah, serta untuk pekerjaan internal usaha kecil (kurang dari 100 orang dan pendapatan di bawah US$1M). Perusahaan mana pun boleh mengevaluasi Hanasu selama 30 hari.
- Perusahaan yang lebih besar, serta siapa pun yang menjual Hanasu atau memasukkannya ke dalam produk atau layanan, memerlukan lisensi komersial. Lihat [COMMERCIAL.md](COMMERCIAL.md).
- Versi yang dirilis sebelum perubahan lisensi ini dirilis di bawah Apache License 2.0 dan tetap berada di bawah lisensi tersebut.
- Kontribusi memerlukan persetujuan atas perjanjian di [CONTRIBUTING.md](CONTRIBUTING.md).

Lisensi pihak ketiga tercantum di [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) (macOS) dan [windows/THIRD_PARTY_NOTICES.md](windows/THIRD_PARTY_NOTICES.md) (Windows). Kedua berkas tersebut disertakan dalam unduhan.
