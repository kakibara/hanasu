<div align="center">

<img src="docs/images/icon.png" width="112" alt="Hanasu simgesi">

# Hanasu

**Doğal konuşun. Göndermeye hazır, temiz metinler ve kendiliğinden yazılan toplantı tutanakları elde edin.**

macOS ve Windows için bir sesle yazma ve toplantı notu uygulaması. Cihaz üzerinde konuşma tanıma ile Gemini, Claude ya da kendi cihazınızda çalışan bir yapay zekâ modeli kullanır.

[![Release](https://img.shields.io/github/v/release/kakibara/hanasu?sort=semver&label=release)](https://github.com/kakibara/hanasu/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/kakibara/hanasu/total)](https://github.com/kakibara/hanasu/releases)
[![License](https://img.shields.io/badge/license-PolyForm%20Noncommercial%20%2B%20small%20business-blue)](COMMERCIAL.md)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-000000?logo=apple)
![Windows 10/11](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows)
[![Windows build](https://github.com/kakibara/hanasu/actions/workflows/windows.yml/badge.svg)](https://github.com/kakibara/hanasu/actions/workflows/windows.yml)

[English](README.md) · [日本語](README.ja.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Italiano](README.it.md) · [Português (Brasil)](README.pt-BR.md) · [Русский](README.ru.md) · **Türkçe** · [Tiếng Việt](README.vi.md) · [Bahasa Indonesia](README.id.md) · [Polski](README.pl.md) · [العربية](README.ar.md) · [हिन्दी](README.hi.md)

<sub>Bu belge İngilizce README'nin bir çevirisidir. Aralarında fark varsa en güncel olan İngilizce README'dir.</sub>

<img src="docs/images/hud.png" width="560" alt="Hanasu kayıt HUD'u">

</div>

> [!NOTE]
> Hanasu öncelikle **Japonca** için geliştirilmiştir ve en çok test edilen dil Japoncadır.
> Uygulamanın ekranları ve yapay zekâya verdiği talimatlar, bu README ile aynı 17 dilde sunulur. Ekranlar sistem dilinizi, yapay zekâ talimatları ise Ayarlar'daki döküm dilini izler. Diğer diller için Hanasu İngilizce kullanır.
> Söylediklerinizi yazmadan önce doğal bir **İngilizceye**, **Japoncaya** ya da desteklenen 17 dilden herhangi birine çevirebilir de.

## Neden Hanasu

Yerleşik dikte özelliği size ham bir döküm verir. Dolgu sözcükleri ve sesteş kelime hatalarını olduğu gibi bırakır, noktalama içermez ve her "dur, yani…" ifadesini de yazar.
Hanasu dökümü bir yapay zekâya (Gemini, Claude ya da cihazınızdaki yerel bir model) gönderir; yapay zekâ bu hataları düzeltir ve metni toparlar. Ardından Hanasu sonucu imlecin bulunduğu yere yazar.
Typeless, Wispr Flow, Aqua Voice ve Granola'dan esinlenmiştir. Kaynak kodu herkese açıktır. Kişisel kullanım ve küçük işletmeler için ücretsizdir; daha büyük şirketlerin [ticari lisansa](COMMERCIAL.md) ihtiyacı vardır. Kendi Gemini veya Claude API anahtarınızı kullanırsınız ya da API anahtarı gerektirmeyen ve metninizin cihazınızdan hiç çıkmadığı yerel bir model çalıştırırsınız.

## Özellikler

### 🎙️ Sesle yazma

| | |
| --- | --- |
| **Konuşun → derli toplu metin** | <kbd>⌥ Space</kbd> tuşuna basın, konuşun ve tekrar basın (ya da **■ Bitti**'ye tıklayın). Hanasu dolgu sözcüklerini çıkarır, sesteş kelimeleri düzeltir, konuşurken yaptığınız düzeltmeleri uygular ve metni imlecin olduğu yere yapıştırır. |
| **Konuşun, çevrilmiş olarak yazılsın** | <kbd>⌥⇧ Space</kbd> tuşlarına basın ya da konuşurken HUD'u **English**, **日本語** veya başka bir dil olarak değiştirin. Kalıp ifadeler doğal biçimde çevrilir; örneğin お疲れ様です "Hi," olur. Sunulacak dilleri (desteklenen 17 dilden herhangi biri) **Ayarlar → Genel** bölümünden seçin. Varsayılan İngilizcedir. Mac'te **Ayarlar → Uygulamalar** bölümünden bir uygulamanın bu dillerden biriyle başlamasını sağlayabilirsiniz. |
| **Karışık diller söylendiği gibi kalır** | Varsayılan olarak İngilizce söylediğiniz kısımlar İngilizce kalır. Bunun yerine çıktının tamamını Japonca yapmayı da seçebilirsiniz. |
| **Sesle düzenleme** | Bir metin seçin, <kbd>⌃⌥⌘ E</kbd> tuşlarına basın ve "daha kibar yap", "madde işaretlerine dönüştür" ya da "İngilizceye çevir" deyin. |
| **Uygulamaya göre stiller** | Metin Slack'te samimi ve kısa, Mail'de paragraflı ve kibar; Pages, Word ve Notion'da ise yazı dilindedir. Her uygulamanın ön ayarını değiştirebilirsiniz. |
| **Hazır metinler** | "e-posta imzası" dediğinizde kaydettiğiniz metin tam yazdığınız gibi eklenir. Hazır metinler asla yapay zekâya gönderilmez. |
| **Sözlük** | Özel adlar ve `ストックマーク => Stockmark` gibi değiştirme kuralları ekleyin. Değiştirme kuralları toplantı dökümlerine de uygulanır. Toplantı Notları'nda açtığınız bir toplantı için yapay zekâ o toplantıdan yeni girdiler önerebilir (Mac'te ayrıca geçmişinizden ve son toplantılarınızdan); yalnızca seçtiklerinizi eklersiniz. |
| **Ekran bağlamı** *(isteğe bağlı)* | Hanasu pencere başlığını ve imlecin çevresindeki metni okur; böylece adlar ekranda zaten yazılı olanlarla eşleşir. Parola alanları asla okunmaz. |
| **Ekran görüntüsündeki metin** *(isteğe bağlı, Mac)* | Hanasu tüm ekranlarınızın görüntüsünü alır, metni Mac'inizde okur ve yapay zekâya yalnızca bu metni iletir; böylece başka pencerelerdeki adlar ve model numaraları (örneğin "QX-7s") ekranda göründüğü gibi yazılır. Görüntü asla gönderilmez ve saklanmaz. HUD'daki düğmeyle tek bir kayıt için açıp kapatabilirsiniz. Ekran Kaydı izni gerekir. |
| **Mikrofonunuzu seçin** *(Mac)* | Mikrofonu Ayarlar'dan seçin ya da kaydı durdurmadan HUD'daki mikrofon düğmesinden değiştirin. |
| **Geçmiş** | Önceki sonuçlarda arama yapın ve başarısız olanları yeniden deneyin. Geçmiş varsayılan olarak 30 gün saklanır; bunu Ayarlar'dan değiştirebilirsiniz. Mac'te son sonucu yeniden yapıştırmak için <kbd>⌥⇧ V</kbd> tuşlarına basın. |
| **Yapıştıracak yer yok mu?** | Odakta bir metin alanı yoksa (örneğin masaüstü öndeyse) Hanasu sonucu yapıştırmak yerine ekranda tutar. Oradan kopyalayın ya da istediğiniz yerde <kbd>⌘V</kbd> tuşlarına basın (sonucun panoda kalıp kalmayacağını seçebilirsiniz). |
| **Yapıştırma ulaşmadı mı?** | Yapıştırma hiçbir uygulamaya ulaşmadıysa (örneğin kayıt sırasında pencere değiştirdiyseniz) Hanasu en son sonucu panoda bırakır ve bunu HUD'da bildirir. İstediğiniz yerde <kbd>⌘V</kbd> tuşlarına basın. Ayarlar → Genel bölümünden, bu durumda dikte geçmişinin açılmasını da sağlayabilirsiniz. |

<p align="center">
  <img src="docs/images/hud-english.png" width="420" alt="İngilizce çıktı">
  <img src="docs/images/edit-mode.png" width="420" alt="Sesle düzenleme">
</p>

### 📝 Toplantı notları

| | |
| --- | --- |
| **İki tarafı da kaydeder** | Mikrofonunuz "siz" olarak kaydedilir. Mac'in ses çıkışı (Zoom, Meet, Teams, Slack huddle'ları vb.) "karşı taraf" olarak kaydedilir. Görüşmeye hiçbir bot katılmaz. |
| **Konuşmacı ayrımı** | Karşı taraf cihaz üzerinde Konuşmacı 1, Konuşmacı 2 vb. olarak ayrılır. Konuşmadan bir ad anlaşılırsa (örneğin biri kendini tanıtırsa) yapay zekâ adı doldurur ve tahmin olarak işaretler. Konuşmacıları sonradan yeniden adlandırabilirsiniz. |
| **Yapay zekâ tutanakları** | Toplantılar için seçtiğiniz yapay zekâ tarafından hazırlanır. Bir şablon seçin: otomatik, haftalık toplantı, birebir görüşme, satış görüşmesi, beyin fırtınası ya da özel. Aksiyon maddeleri bir sorumlu ve bir bitiş tarihi içerir. |
| **Kaynağı kontrol edin ve yeniden dinleyin** *(Mac)* | Tutanak tek sayfa olarak açılır: önce özet ve aksiyon maddeleri, yanında da döküm. Bir maddenin sonundaki zamana tıklayarak o maddenin dayandığı konuşmaya gidin. Kaydı herhangi bir konuşmadan itibaren oynatın; görüşmede yankı olduysa kendi tarafınızın ya da karşı tarafın sesini kapatın. |
| **Canlı notlar ve önemli anlar** | Görüşme sırasında zaman damgalı notlar yazın ya da "bu önemli" diye işaretlemek için <kbd>⌃⌥⌘ H</kbd> tuşlarına basın (10 saniye içinde geri alabilirsiniz). Tutanaklar bu bölümlere öncelik verir; sonrasında her işaretin çevresindeki konuşmayı okuyabilirsiniz. |
| **Yüzen altyazılar** *(Mac)* | Canlı dökümü toplantı uygulamanızın üzerinde altyazı olarak gösterin. Açık bırakırsanız bir sonraki toplantıda da görünürler. |
| **Toplantı sırasında yapay zekâ sohbeti** *(Mac)* | Kayıt sırasında, o ana kadarki konuşma hakkında yapay zekâya soru sorun (<kbd>⌘J</kbd>). "Şu ana kadarki özet" ya da "kararlar ve yapılacaklar" tek tıkla. Ek sorular sorun ve dökümün o bölümüne gitmek için yanıttaki bir zaman damgasına tıklayın. Başka bir işle uğraşırken aniden size soru mu yöneltildi? Toplantı uygulamanızdan ayrılmadan altyazılardaki **Bana ne soruldu?** düğmesine (ya da <kbd>⌃⌥⌘ A</kbd> tuşlarına) basın: yüzen bir panelde diğerlerinin az önce söyledikleri, ardından yapay zekânın özeti, yani sorunun ne olduğu ve konuşmanın oraya nasıl geldiği görünür. O sohbette kullanılacak yapay zekâyı ve modeli, giriş kutusunun altındaki menüden değiştirebilirsiniz. |
| **Toplantı algılama** | Bir toplantı uygulaması mikrofonu kullanmaya başladığında Hanasu kayıt yapılıp yapılmayacağını sorar. Kaydı asla kendiliğinden başlatmaz. |
| **Arama ve Sorma** | Tüm toplantıların metninde arama yapın ya da "Geçen haftaki toplantıda ne karar verdik?" diye sorun. Yanıt, kullandığı toplantıları kaynak olarak gösterir. |
| **Dışa aktarma** | Markdown olarak ya da Slack'e hazır bir özet olarak kopyalayın, `.md` / `.txt` olarak kaydedin veya aksiyon maddelerini Anımsatıcılar'a gönderin. |
| **Düzenleme** | Bir toplantının başlığını yerinde düzenleyerek adını değiştirin ya da artık ihtiyaç duymadığınız bir toplantıyı silin. |

<p align="center">
  <img src="docs/images/meeting-live.png" width="420" alt="Canlı notlarla kayıt">
  <img src="docs/images/meeting-ask.png" width="420" alt="Toplantılarınıza soru sorun">
</p>
<p align="center">
  <img src="docs/images/meeting-minutes.png" width="420" alt="Aksiyon maddeleriyle tutanak">
  <img src="docs/images/meeting-suggestion.png" width="420" alt="Toplantı algılama">
</p>

### 🤖 Yapay zekânızı seçin

Metninizi düzelten yapay zekâyı **sesle yazma** ve **toplantılar** (tutanaklar) için ayrı ayrı seçin. Mac'te ayrıca **yapay zekâ sohbeti ve sorular** (toplantı sırasındaki yapay zekâ sohbeti ve geçmiş toplantılara sorulan sorular) için de bir yapay zekâ seçersiniz.

| Yapay zekâ | Varsayılan model | Oturum açma |
| --- | --- | --- |
| **Gemini** (Windows'ta varsayılan) | sesle yazma `gemini-3.5-flash-lite`, toplantılar ile yapay zekâ sohbeti ve sorular `gemini-3.8-flash` | Google AI Studio API anahtarı veya Vertex AI hizmet hesabı |
| **Claude** | sesle yazma ile yapay zekâ sohbeti ve sorular `claude-haiku-5-5`, toplantılar `claude-sonnet-5-5` (Opus 5.5 de kullanılabilir) | Anthropic API anahtarı |
| **Yerel** (cihazınızda; Mac'te varsayılan) | Gemma 4 E4B (önerilen). Aşağıdaki tabloya bakın | Gerekmez. Modeli **Ayarlar → Yapay Zekâ** bölümünden indirin. Mac'te, Hanasu metni düzeltmeye başladığında model yoksa indirmek isteyip istemediğinizi sorar |
| **Apple** *(Mac, macOS 27)* | `fm` komutu üzerinden cihaz üzerindeki Apple Intelligence modeli | Gerekmez |

Bu yapay zekâlar yalnızca metinle çalışır. Konuşma, aşağıdaki motor tarafından metne dökülür.

#### 💻 Yerel modeller

**Yerel** seçildiğinde Hanasu, birlikte gelen [llama.cpp](https://github.com/ggml-org/llama.cpp) ile kendi Mac'inizde veya PC'nizde küçük bir dil modeli çalıştırır; böylece metniniz cihazdan hiç çıkmaz. Mac GPU'yu (Metal), Windows ise CPU'yu kullanır. Modeli **Ayarlar → Yapay Zekâ** bölümünden bir kez indirirsiniz. Hanasu kullanmadan önce modelin boyutunu ve SHA-256 değerini doğrular.

| Model | Boyut | Lisans | Notlar |
| --- | --- | --- | --- |
| **Gemma 4 E4B** (Google) — **önerilen** | 4.59 GB | Apache-2.0 | Hem metin düzeltmede hem tutanaklarda en doğal sonuçlar. 16 GB veya daha fazla bellek önerilir. Sesle yazma ve toplantılar için varsayılan |
| LFM2.5-1.2B-JP (Liquid AI) | 1.25 GB | LFM Open License v1.0 | Küçük ve hızlı. Yıllık geliri 10 milyon ABD doları veya üzerinde olan kuruluşlar bu lisans kapsamında ticari amaçla kullanamaz |
| Sarashina2.2 3B (SB Intuitions) | 2.07 GB | MIT | Japonca ile eğitilmiş. Bağlam uzunluğu 8K olduğundan uzun toplantılar parça parça özetlenir |
| Qwen3.5-4B (Alibaba) | 2.74 GB | Apache-2.0 | Gemma'nın yaklaşık yarısı boyutunda, bu yüzden 8 GB bellekte çalıştırmak daha kolay. Konuşurken yapılan düzeltmeleri işlemede Gemma'dan zayıf |

> [!TIP]
> **Gemma 4 E4B**'yi öneriyoruz. Testlerimizde diğer modeller zaman zaman geri almak istediğiniz sözcükleri korudu, söylemediğiniz cümleler ekledi, aksiyon maddesinin sorumlusunu karıştırdı ya da aksiyon maddelerini birleştirdi veya atladı. Gemma 4 E4B ise hem metin düzeltmeyi hem tutanakları güvenilir biçimde yaptı.

### 🔊 Konuşma motorunuzu seçin

| Motor | Çalıştığı yer | Canlı döküm | Notlar |
| --- | --- | --- | --- |
| **İşletim sistemi standardı** (varsayılan) | Mac: `SpeechAnalyzer` · Windows: `Windows.Media.SpeechRecognition` | ✅ | Mac'te cihaz üzerinde |
| **Whisper** | Cihaz üzerinde (Mac'te WhisperKit, Windows'ta whisper.cpp) | — (durdurduktan sonra) | Model, seçtiğinizde indirilir |
| **Gemini** | Google | — (durdurduktan sonra) | Kaydedilen ses Google'a gönderilir |

Sesle yazma ve toplantılar için farklı motorlar seçebilirsiniz. Windows'ta toplantılar Whisper veya Gemini kullanır.
Mac'te döküm dilini bir listeden seçin (Japonca, İngilizce, Çince, Korece, Fransızca, Almanca, İspanyolca, İtalyanca, Portekizce). Başlangıçta sistem dilinize ayarlıdır.

## İndirme

En son sürümü [**Releases**](https://github.com/kakibara/hanasu/releases/latest) sayfasından edinin.

| Platform | Dosya | Gereksinimler |
| --- | --- | --- |
| macOS | `Hanasu-<version>-macOS.zip` | macOS 26 (Tahoe) veya üstü, Apple Silicon |
| Windows | `Hanasu-<version>-Windows-x64.zip` | Windows 10 (2004 veya üstü) / 11, x64 |

<details>
<summary><b>macOS: ilk açılış</b></summary>

1. Zip dosyasını açın ve `Hanasu.app` uygulamasını **Uygulamalar** klasörüne taşıyın.
2. Uygulama kendinden imzalıdır ve notarize edilmemiştir, bu yüzden macOS ilk seferde açılmasını engeller. **Bitti**'ye tıklayın, ardından **Sistem Ayarları → Gizlilik ve Güvenlik** bölümünü açıp **Yine de Aç**'a tıklayın.
   Bunun yerine `xattr -dr com.apple.quarantine /Applications/Hanasu.app` komutunu da çalıştırabilirsiniz.
3. İstendiğinde **Mikrofon**, **Konuşma Tanıma** ve **Erişilebilirlik** izinlerini verin. Erişilebilirlik izni ⌘V ile yapıştırmak için gereklidir. **Ekran Kaydı** izni yalnızca ekran görüntüsündeki metni açarsanız istenir.

</details>

<details>
<summary><b>Windows: ilk açılış</b></summary>

1. Zip dosyasını açın, `Hanasu` klasörünü istediğiniz bir yere koyun (örneğin `%LOCALAPPDATA%\Programs`) ve `Hanasu.exe` dosyasını çalıştırın.
2. Uygulama kod imzalı olmadığından SmartScreen bir uyarı gösterir. **Ek bilgi → Yine de çalıştır**'a tıklayın.
3. Windows konuşma motoru, Windows ayarlarında **Çevrimiçi konuşma tanıma** seçeneğinin açık olmasını gerektirir. Kapalıysa Hanasu sizi uyarır.

Daha fazla not ve Windows sürümünün Mac sürümünden farkları için [windows/README.md](windows/README.md) dosyasına bakın.

</details>

Yeni bir sürüm yayımlandığında Hanasu bunu açılışta size bildirir ve kendini güncellemeden önce sorar. Menüden **アップデートを確認…** (Güncellemeleri Denetle) öğesini de seçebilirsiniz (açılıştaki denetim **Ayarlar → Genel** bölümünden kapatılabilir). v1.5.0 ve önceki sürümlerde bu özellik henüz yok; bu yüzden onları bir kez elle güncelleyin.

## Hızlı başlangıç

Mac'te ilk açılışta kısa bir rehberli tur başlar. Tur, yapay zekânızı seçmenizi sağlar (önerilen yerel model Gemma 4 E4B orada hemen indirilir), ana özellikleri ve ayar ipuçlarını gösterir ve Hanasu'nun ihtiyaç duyduğu izinleri ister. Turu istediğiniz zaman menüdeki **Hanasu nasıl kullanılır…** öğesinden yeniden açabilirsiniz.

1. **Bir yapay zekâ seçin.** **Ayarlar → Yapay Zekâ** bölümünü açın ve sesle yazma ile toplantılar için (Mac'te ayrıca yapay zekâ sohbeti ve sorular için de) birer yapay zekâ seçin. Gemini için [Google AI Studio](https://aistudio.google.com/apikey)'dan aldığınız API anahtarını yapıştırın ya da bir Vertex AI hizmet hesabı JSON dosyası seçin. Claude için [Claude Console](https://console.anthropic.com/settings/keys)'dan aldığınız API anahtarını yapıştırın. Yerel için bir model indirin (Gemma 4 E4B önerilir). Anahtar gerekmez. Çalıştığını doğrulamak için test düğmesine tıklayın.
2. **Dikte edin.** İmleci metnin gelmesini istediğiniz yere koyun, kısayola basın, konuşun ve kısayola tekrar basın.
3. **Bir toplantı kaydedin.** Menü çubuğu (Mac) veya sistem tepsisi (Windows) menüsünü ya da kısayolu kullanın. Kulaklık kullanmak iki tarafın birbirinden ayrı tutulmasına yardımcı olur.

Mac'te Hanasu simgesi her zaman Dock'tadır; isterseniz menü çubuğunda da gösterebilirsiniz (Ayarlar → Genel). Dock simgesine tıklamak ayarları açmaz; ayarları menü çubuğu simgesinden ya da Dock simgesinin sağ tık menüsünden açın.

### Varsayılan kısayollar

| Eylem | macOS | Windows |
| --- | --- | --- |
| Sesle yazma (başlat / durdur) | <kbd>⌥ Space</kbd> | <kbd>Ctrl Alt Space</kbd> |
| Çevirili sesle yazma (seçtiğiniz dillere) | <kbd>⌥⇧ Space</kbd> | <kbd>Ctrl Alt Shift Space</kbd> |
| Seçimi sesle düzenleme | <kbd>⌃⌥⌘ E</kbd> | — |
| Son sonucu yeniden yapıştırma | <kbd>⌥⇧ V</kbd> | — |
| Kaydı iptal etme | <kbd>Esc</kbd> | <kbd>Esc</kbd> |
| Toplantı kaydı (başlat / durdur) | <kbd>⌃⌥⌘ M</kbd> | <kbd>Ctrl Alt Shift M</kbd> |
| Toplantıda "bu önemli" diye işaretleme | <kbd>⌃⌥⌘ H</kbd> | <kbd>Ctrl Alt Shift H</kbd> |
| Toplantıda "Bana ne soruldu?" | <kbd>⌃⌥⌘ A</kbd> | — |

Tüm kısayolları Ayarlar'dan değiştirebilirsiniz. Kullanıcı kılavuzunun tamamı (Japonca) [docs/guide.md](docs/guide.md) dosyasındadır.

## Gizlilik

- **Ses varsayılan olarak cihazınızda kalır.** Konuşma tanıma, Whisper ve konuşmacı ayrımı tamamen yerel olarak çalışır.
- **Yapay zekâya ses değil, metin gider.** Gemini veya Claude dökümü alır. Ayarlarınıza bağlı olarak yazı yazdığınız uygulamanın adını, ekran bağlamını, ekranınızın ekran görüntüsünden okunan metni (görüntünün kendisi asla gönderilmez) ve Sorma özelliği ve toplantı sırasındaki yapay zekâ sohbeti için toplantı dökümlerini de alabilir.
- **Yerel ve Apple da metni cihazınızda tutar.** Bunlardan birini seçerseniz hiçbir yapay zekâ hizmetine hiçbir şey gönderilmez. İndirilen tek şey modelin kendisidir.
- **Ses yalnızca siz seçerseniz Google'a gider.** Gemini konuşma motorunu seçerseniz kaydedilen ses Google'a gönderilir.
- **Toplantılar düz dosyalardır.** `~/Documents/Hanasu/Meetings/` (Windows: `Documents\Hanasu\Meetings\`) altında JSON ve Markdown olarak kaydedilir. Mac ve Windows aynı biçimi kullanır.
- **Telemetri yok.** Hanasu hiçbir analiz verisi toplamaz.
- **API anahtarları işletim sistemi tarafından korunur.** macOS'ta Keychain'de saklanır ve diğer uygulamaların bunları okuyabilmesi için giriş parolanızı istemesi gerekir. Windows'ta DPAPI ile ya da tercih ederseniz bir Windows Hello anahtarıyla şifrelenir. İki yöntem de sizin kullanıcı hesabınızla çalışan kötü amaçlı yazılımları tamamen durduramaz. Bkz. [docs/design/security.md](docs/design/security.md).

> [!IMPORTANT]
> Kayda başlamadan önce toplantıdaki herkesin onayını alın. Kuruluşunuzun kayıt yapmaya ve yapay zekâ hizmetlerini kullanmaya ilişkin kurallarına uyun.

## Kaynaktan derleme

<details>
<summary><b>macOS</b> (Xcode Command Line Tools, Swift 6.2)</summary>

```bash
./scripts/build-app.sh             # build/Hanasu.app'i derler
open build/Hanasu.app
./scripts/create-signing-cert.sh   # isteğe bağlı: yeniden derlemelerde izinleri korur
```

</details>

<details>
<summary><b>Windows</b> (.NET 8 SDK)</summary>

```bash
cd windows
dotnet build Hanasu.Windows.sln
dotnet publish Hanasu.Windows/Hanasu.Windows.csproj -c Release -r win-x64 --self-contained -p:PublishSingleFile=true -o publish/win-x64
```

Bkz. [windows/README.md](windows/README.md).

</details>

## Belgeler

Belgeler Japonca yazılmıştır.

| | |
| --- | --- |
| [docs/guide.md](docs/guide.md) | Kullanıcı kılavuzu: kullanım, ayarlar, sözlük kuralları |
| [docs/spec/](docs/spec/) | Uygulanmış gereksinimler (`REQ-*`) ve tasarım kararları (`DEC-*`) |
| [docs/design/](docs/design/) | Nasıl yapıldığı: mimari ve veri akışı |
| [docs/roadmap.md](docs/roadmap.md) | Henüz uygulanmamış planlar |
| [docs/releasing.md](docs/releasing.md) | Sürümlerin nasıl yayımlandığı (tagpr) |

## Katkıda bulunma

Issue'lar ve pull request'ler memnuniyetle karşılanır.

1. Herhangi bir davranışı değiştirmeden önce [docs/README.md](docs/README.md) dosyasını okuyun.
2. Kod, `// 要件: REQ-…` (gereksinim) veya `// 設計判断: DEC-…` (tasarım kararı) ile etiketlenir. CI'da `scripts/check-spec.py`, etiketli kod değiştiğinde spec'in de güncellendiğini kontrol eder.
3. Yeni bir özellik, `docs/spec/` içinde bir gereksinim olarak başlar. Sonraya bırakılan fikirler `docs/roadmap.md` dosyasına yazılır.

## Lisans

Hanasu kaynağı erişilebilir (source-available) bir yazılımdır, açık kaynak değildir. © 2026 kakibara. Bkz. [NOTICE](NOTICE).

- Lisans: [PolyForm Noncommercial License 1.0.0](LICENSE) ile birlikte [Hanasu Additional Permission 1.0](LICENSE-ADDITIONAL-PERMISSION.md).
- Kişisel ve ticari olmayan kullanım, eğitim, araştırma, hayır kurumları ve devlet kurumları ile küçük işletmelerin (100 kişiden az ve geliri US$1M'nin altında) şirket içi işleri için ücretsizdir. Her şirket Hanasu'yu 30 gün boyunca değerlendirebilir.
- Daha büyük şirketlerin ve Hanasu'yu satan ya da bir ürün veya hizmete yerleştiren herkesin ticari lisansa ihtiyacı vardır. Bkz. [COMMERCIAL.md](COMMERCIAL.md).
- Bu lisans değişikliğinden önce yayımlanan sürümler Apache License 2.0 altında yayımlanmıştır ve bu lisans altında kalır.
- Katkılar için [CONTRIBUTING.md](CONTRIBUTING.md) dosyasındaki sözleşmenin kabul edilmesi gerekir.

Üçüncü taraf lisansları [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) (macOS) ve [windows/THIRD_PARTY_NOTICES.md](windows/THIRD_PARTY_NOTICES.md) (Windows) dosyalarında listelenmiştir. Her iki dosya da indirilen paketlere dahildir.
