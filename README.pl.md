<div align="center">

<img src="docs/images/icon.png" width="112" alt="Ikona Hanasu">

# Hanasu

**Mów naturalnie. Otrzymuj czysty, gotowy do wysłania tekst i notatki ze spotkań, które piszą się same.**

Aplikacja do wprowadzania tekstu głosem i notatek ze spotkań dla macOS i Windows. Korzysta z rozpoznawania mowy na urządzeniu oraz z Gemini, Claude lub modelu AI działającego na Twoim własnym urządzeniu.

[![Release](https://img.shields.io/github/v/release/kakibara/hanasu?sort=semver&label=release)](https://github.com/kakibara/hanasu/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/kakibara/hanasu/total)](https://github.com/kakibara/hanasu/releases)
[![License](https://img.shields.io/badge/license-PolyForm%20Noncommercial%20%2B%20small%20business-blue)](COMMERCIAL.md)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-000000?logo=apple)
![Windows 10/11](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows)
[![Windows build](https://github.com/kakibara/hanasu/actions/workflows/windows.yml/badge.svg)](https://github.com/kakibara/hanasu/actions/workflows/windows.yml)

[English](README.md) · [日本語](README.ja.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Italiano](README.it.md) · [Português (Brasil)](README.pt-BR.md) · [Русский](README.ru.md) · [Türkçe](README.tr.md) · [Tiếng Việt](README.vi.md) · [Bahasa Indonesia](README.id.md) · **Polski** · [العربية](README.ar.md) · [हिन्दी](README.hi.md)

<sub>To jest tłumaczenie angielskiego README. W razie rozbieżności najbardziej aktualna jest wersja angielska.</sub>

<img src="docs/images/hud.png" width="560" alt="HUD nagrywania Hanasu">

</div>

> [!NOTE]
> Hanasu powstało przede wszystkim z myślą o języku **japońskim** i to właśnie japoński jest najlepiej przetestowany.
> Ekrany aplikacji i instrukcje, które przekazuje AI, są dostępne w tych samych 17 językach co ten README. Ekrany są w języku systemu, a instrukcje dla AI w języku transkrypcji wybranym w Ustawieniach. Dla każdego innego języka Hanasu używa angielskiego.
> Aplikacja potrafi też przetłumaczyć to, co mówisz, na naturalny **angielski** (lub na **japoński**), zanim to wpisze.

## Dlaczego Hanasu

Wbudowane dyktowanie daje surową transkrypcję. Zostawia wtrącenia i błędy w homofonach, nie ma interpunkcji i zawiera każde „czekaj, chodziło mi o…”.
Hanasu wysyła transkrypcję do AI (Gemini, Claude lub lokalnego modelu na Twoim urządzeniu), które poprawia te błędy i porządkuje tekst. Następnie Hanasu wpisuje wynik tam, gdzie jest kursor.
Inspiracją były Typeless, Wispr Flow, Aqua Voice i Granola. Kod źródłowy Hanasu jest publiczny. Hanasu jest darmowe do użytku osobistego i dla małych firm; większe firmy potrzebują [licencji komercyjnej](COMMERCIAL.md). Używasz własnego klucza API Gemini lub Claude albo uruchamiasz lokalny model — bez klucza API i bez wysyłania tekstu poza urządzenie.

## Funkcje

### 🎙️ Wprowadzanie głosem

| | |
| --- | --- |
| **Mowa → dopracowany tekst** | Naciśnij <kbd>⌥ Space</kbd>, mów i naciśnij ponownie (lub kliknij **■ Zatrzymaj**). Hanasu usuwa wtrącenia, poprawia homofony, uwzględnia Twoje autopoprawki i wkleja tekst w miejscu kursora. |
| **Mów, wpisuj w tłumaczeniu** | Naciśnij <kbd>⌥⇧ Space</kbd> albo przełącz HUD na **English** lub **日本語** w trakcie mówienia. Utarte zwroty są tłumaczone naturalnie, więc お疲れ様です staje się „Hi,”. Języki do wyboru (angielski, japoński lub oba) ustawisz w **Ustawienia → Ogólne**. Domyślnie jest to angielski. |
| **Mieszane języki zostają tak, jak je wypowiedziano** | Domyślnie fragmenty wypowiedziane po angielsku pozostają po angielsku. Możesz zamiast tego ujednolicić wynik do japońskiego. |
| **Edycja głosem** | Zaznacz tekst, naciśnij <kbd>⌃⌥⌘ E</kbd> i powiedz „napisz to uprzejmiej”, „zamień na punkty” albo „przetłumacz na angielski”. |
| **Style dla aplikacji** | W Slacku tekst jest swobodny i krótki, w Mailu uprzejmy i podzielony na akapity, a w Pages, Wordzie i Notion — w stylu pisanym. Ustawienie wstępne możesz zmienić dla każdej aplikacji. |
| **Fragmenty tekstu** | Powiedz „podpis e-mail”, aby wstawić zapisany tekst dokładnie tak, jak go napisałeś. Fragmenty nigdy nie są wysyłane do AI. |
| **Słownik** | Dodawaj nazwy własne i reguły zamiany, np. `ストックマーク => Stockmark`. Na Macu AI może też proponować nowe wpisy na podstawie historii i spotkań, a Ty dodajesz tylko wybrane. |
| **Kontekst ekranu** *(opcjonalnie)* | Hanasu odczytuje tytuł okna i tekst wokół kursora, aby nazwy zgadzały się z tym, co już jest na ekranie. Pola haseł nigdy nie są odczytywane. |
| **Wybór mikrofonu** *(Mac)* | Wybierz mikrofon w Ustawieniach albo przełącz go przyciskiem mikrofonu w HUD bez przerywania nagrania. |
| **Historia** | Przeszukuj wcześniejsze wyniki i ponawiaj nieudane. Domyślnie historia jest przechowywana przez 30 dni; możesz to zmienić w Ustawieniach. Na Macu naciśnij <kbd>⌥⇧ V</kbd>, aby ponownie wkleić ostatni wynik. |
| **Nie ma gdzie wkleić?** | Jeśli żadne pole tekstowe nie ma fokusu (np. na wierzchu jest pulpit), Hanasu zostawia wynik na ekranie zamiast go wklejać. Skopiuj go stamtąd albo po prostu naciśnij <kbd>⌘V</kbd> tam, gdzie chcesz (możesz wybrać, czy wynik ma pozostać w schowku). |
| **Wklejanie nie dotarło?** | Jeśli wklejenie nie trafiło do żadnej aplikacji (np. przełączyłeś okno podczas nagrywania), Hanasu zostawia najnowszy wynik w schowku i informuje o tym w HUD. Naciśnij <kbd>⌘V</kbd> tam, gdzie chcesz. W Ustawienia → Ogólne możesz też sprawić, że w takiej sytuacji otworzy się historia dyktowania. |

<p align="center">
  <img src="docs/images/hud-english.png" width="420" alt="Wynik po angielsku">
  <img src="docs/images/edit-mode.png" width="420" alt="Edycja głosem">
</p>

### 📝 Notatki ze spotkań

| | |
| --- | --- |
| **Nagrywa obie strony** | Twój mikrofon jest nagrywany jako „ty”. Dźwięk wyjściowy Maca (Zoom, Meet, Teams, huddle w Slacku itd.) jest nagrywany jako „oni”. Do rozmowy nie dołącza żaden bot. |
| **Rozpoznawanie mówców** | Druga strona jest dzielona na Mówcę 1, Mówcę 2 itd. — na urządzeniu. Gdy z rozmowy jasno wynika imię (np. ktoś się przedstawia), AI je uzupełnia i oznacza jako przypuszczenie. Nazwy mówców możesz później zmienić. |
| **Protokoły AI** | Tworzone przez AI wybrane dla spotkań. Wybierz szablon: automatyczny, cotygodniowe spotkanie, 1-on-1, rozmowa sprzedażowa, burza mózgów lub własny. Zadania do wykonania zawierają osobę odpowiedzialną i termin. |
| **Notatki na żywo i wyróżnienia** | Pisz notatki ze znacznikiem czasu w trakcie rozmowy albo naciśnij <kbd>⌃⌥⌘ H</kbd>, aby oznaczyć „to ważne” (możesz to cofnąć przez 10 sekund). Protokół traktuje te fragmenty priorytetowo, a później możesz przeczytać rozmowę wokół każdego oznaczenia. |
| **Pływające napisy** *(Mac)* | Wyświetlaj transkrypcję na żywo jako napisy nad aplikacją do spotkań. |
| **Czat z AI w trakcie spotkania** *(Mac)* | Podczas nagrywania pytaj AI o dotychczasową rozmowę (<kbd>⌘J</kbd>). Jednym kliknięciem: „podsumuj dotąd” albo „decyzje i zadania”. Zadawaj pytania uzupełniające i kliknij znacznik czasu w odpowiedzi, aby przejść do tego miejsca w transkrypcji. |
| **Wykrywanie spotkań** | Gdy aplikacja do spotkań zaczyna używać mikrofonu, Hanasu pyta, czy nagrywać. Nigdy nie zaczyna nagrywać samo. |
| **Wyszukiwanie i pytania** | Przeszukuj tekst wszystkich spotkań albo zapytaj: „Co ustaliliśmy na zeszłotygodniowym spotkaniu?”. Odpowiedź wskazuje spotkania, z których korzystała. |
| **Eksport** | Kopiuj jako Markdown lub jako podsumowanie gotowe do Slacka, zapisuj jako `.md` / `.txt` albo wysyłaj zadania do Przypomnień. |
| **Porządkowanie** | Zmień nazwę spotkania, edytując tytuł bezpośrednio, albo usuń spotkanie, którego już nie potrzebujesz. |

<p align="center">
  <img src="docs/images/meeting-live.png" width="420" alt="Nagrywanie z notatkami na żywo">
  <img src="docs/images/meeting-ask.png" width="420" alt="Pytania o spotkania">
</p>
<p align="center">
  <img src="docs/images/meeting-minutes.png" width="420" alt="Protokół z zadaniami do wykonania">
  <img src="docs/images/meeting-suggestion.png" width="420" alt="Wykrywanie spotkań">
</p>

### 🤖 Wybierz AI

Wybierz AI, które dopracowuje tekst, osobno dla **wprowadzania głosem** i **spotkań**.

| AI | Model domyślny | Logowanie |
| --- | --- | --- |
| **Gemini** (domyślnie na Windows) | wprowadzanie głosem `gemini-3.5-flash-lite`, spotkania `gemini-3.8-flash` | Klucz API Google AI Studio lub konto usługi Vertex AI |
| **Claude** | wprowadzanie głosem `claude-haiku-5-5`, spotkania `claude-sonnet-5-5` (dostępny też Opus 5.5) | Klucz API Anthropic |
| **Lokalnie** (na Twoim urządzeniu; domyślnie na Macu) | Gemma 4 E4B (zalecany). Zobacz tabelę poniżej | Brak. Pobierz model w **Ustawienia → AI**. Jeśli na Macu brakuje modelu, gdy Hanasu zaczyna dopracowywać tekst, aplikacja zapyta, czy go pobrać |
| **Apple** *(Mac, macOS 27)* | Model Apple Intelligence działający na urządzeniu, przez polecenie `fm` | Brak |

Te AI przetwarzają wyłącznie tekst. Mowę transkrybuje silnik opisany poniżej.

#### 💻 Modele lokalne

W trybie **Lokalnie** Hanasu uruchamia mały model językowy na Twoim Macu lub PC za pomocą dołączonego [llama.cpp](https://github.com/ggml-org/llama.cpp), więc tekst nigdy nie opuszcza urządzenia. Mac używa GPU (Metal), a Windows — CPU. Model pobierasz jednorazowo w **Ustawienia → AI**. Przed użyciem Hanasu sprawdza jego rozmiar i SHA-256.

| Model | Rozmiar | Licencja | Uwagi |
| --- | --- | --- | --- |
| **Gemma 4 E4B** (Google) — **zalecany** | 4,59 GB | Apache-2.0 | Najbardziej naturalne wyniki zarówno przy porządkowaniu tekstu, jak i protokołach. Zalecane 16 GB pamięci lub więcej. Domyślny dla wprowadzania głosem i spotkań |
| LFM2.5-1.2B-JP (Liquid AI) | 1,25 GB | LFM Open License v1.0 | Mały i szybki. Organizacje z rocznym przychodem 10 mln USD lub więcej nie mogą używać go komercyjnie na tej licencji |
| Sarashina2.2 3B (SB Intuitions) | 2,07 GB | MIT | Trenowany na języku japońskim. Kontekst ma 8K, więc długie spotkania są streszczane w częściach |
| Qwen3.5-4B (Alibaba) | 2,74 GB | Apache-2.0 | Mniej więcej o połowę mniejszy od Gemmy, więc łatwiej go uruchomić przy 8 GB pamięci. Gorzej niż Gemma radzi sobie z autopoprawkami |

> [!TIP]
> Polecamy **Gemma 4 E4B**. W naszych testach pozostałe modele czasem zostawiały słowa, które chciałeś odwołać, dodawały zdania, których nie wypowiedziałeś, myliły osoby odpowiedzialne za zadania albo scalały lub pomijały zadania. Gemma 4 E4B niezawodnie radziła sobie zarówno z porządkowaniem tekstu, jak i z protokołami.

### 🔊 Wybierz silnik rozpoznawania mowy

| Silnik | Gdzie działa | Transkrypcja na żywo | Uwagi |
| --- | --- | --- | --- |
| **Standardowy systemu** (domyślnie) | Mac: `SpeechAnalyzer` · Windows: `Windows.Media.SpeechRecognition` | ✅ | Na Macu działa na urządzeniu |
| **Whisper** | Na urządzeniu (WhisperKit na Macu, whisper.cpp na Windows) | — (po zatrzymaniu) | Model pobiera się po jego wybraniu |
| **Gemini** | Google | — (po zatrzymaniu) | Nagrany dźwięk jest wysyłany do Google |

Możesz wybrać inny silnik dla wprowadzania głosem i dla spotkań. Na Windows spotkania używają Whisper lub Gemini.
Na Macu język transkrypcji wybierasz z listy (japoński, angielski, chiński, koreański, francuski, niemiecki, hiszpański, włoski, portugalski). Domyślnie jest to język systemu.

## Pobieranie

Najnowszą wersję pobierzesz z [**Releases**](https://github.com/kakibara/hanasu/releases/latest).

| Platforma | Plik | Wymagania |
| --- | --- | --- |
| macOS | `Hanasu-<version>-macOS.zip` | macOS 26 (Tahoe) lub nowszy, Apple Silicon |
| Windows | `Hanasu-<version>-Windows-x64.zip` | Windows 10 (2004 lub nowszy) / 11, x64 |

<details>
<summary><b>macOS: pierwsze uruchomienie</b></summary>

1. Rozpakuj plik i przenieś `Hanasu.app` do **Aplikacji**.
2. Aplikacja jest podpisana własnym certyfikatem i nie przeszła notaryzacji, więc macOS za pierwszym razem ją blokuje. Kliknij **Gotowe**, a następnie otwórz **Ustawienia systemowe → Prywatność i ochrona** i kliknij **Otwórz mimo to**.
   Zamiast tego możesz też uruchomić `xattr -dr com.apple.quarantine /Applications/Hanasu.app`.
3. Gdy pojawi się prośba, zezwól na dostęp do **Mikrofonu**, **Rozpoznawania mowy** i **Dostępności**. Dostępność jest potrzebna do wklejania za pomocą ⌘V.

</details>

<details>
<summary><b>Windows: pierwsze uruchomienie</b></summary>

1. Rozpakuj plik, umieść folder `Hanasu` w dowolnym miejscu (np. `%LOCALAPPDATA%\Programs`) i uruchom `Hanasu.exe`.
2. Aplikacja nie ma podpisu kodu, więc SmartScreen wyświetla ostrzeżenie. Kliknij **Więcej informacji → Uruchom mimo to**.
3. Silnik mowy Windows wymaga włączenia **Rozpoznawania mowy online** w ustawieniach Windows. Hanasu poinformuje Cię, jeśli jest wyłączone.

Więcej uwag oraz różnice między wersją na Windows a wersją na Maca znajdziesz w [windows/README.md](windows/README.md).

</details>

Gdy pojawi się nowa wersja, Hanasu poinformuje cię o tym przy uruchomieniu i zapyta, zanim się zaktualizuje. Możesz też wybrać w menu **アップデートを確認…** (Sprawdź aktualizacje) (sprawdzanie przy uruchomieniu można wyłączyć w **Ustawienia → Ogólne**). Wersje do v1.5.0 włącznie jeszcze tego nie mają, więc zaktualizuj je raz ręcznie.

## Szybki start

Na Macu przy pierwszym uruchomieniu otwiera się krótki przewodnik. Pozwala wybrać AI (Gemma 4 E4B, zalecany model lokalny, pobiera się od razu na miejscu), pokazuje główne funkcje i wskazówki dotyczące ustawień oraz prosi o uprawnienia potrzebne Hanasu. W każdej chwili możesz go otworzyć ponownie z menu, wybierając **Jak używać Hanasu…**.

1. **Wybierz AI.** Otwórz **Ustawienia → AI** i wybierz AI dla wprowadzania głosem i dla spotkań. Dla Gemini wklej klucz API z [Google AI Studio](https://aistudio.google.com/apikey) lub wybierz plik JSON konta usługi Vertex AI. Dla Claude wklej klucz API z [Claude Console](https://console.anthropic.com/settings/keys). Dla trybu Lokalnie pobierz model (zalecany jest Gemma 4 E4B). Klucz nie jest potrzebny. Kliknij przycisk testu, aby sprawdzić, czy wszystko działa.
2. **Dyktuj.** Ustaw kursor tam, gdzie ma się pojawić tekst, naciśnij skrót, mów i naciśnij skrót ponownie.
3. **Nagraj spotkanie.** Użyj menu na pasku menu (Mac) lub w zasobniku systemowym (Windows) albo skrótu. Słuchawki pomagają rozdzielić obie strony.

Na Macu ikonę Hanasu możesz wyświetlać na pasku menu, w Docku lub w obu miejscach (Ustawienia → Ogólne).

### Domyślne skróty

| Czynność | macOS | Windows |
| --- | --- | --- |
| Wprowadzanie głosem (start / stop) | <kbd>⌥ Space</kbd> | <kbd>Ctrl Alt Space</kbd> |
| Wprowadzanie głosem z tłumaczeniem (angielski / japoński) | <kbd>⌥⇧ Space</kbd> | <kbd>Ctrl Alt Shift Space</kbd> |
| Edycja zaznaczenia głosem | <kbd>⌃⌥⌘ E</kbd> | — |
| Ponowne wklejenie ostatniego wyniku | <kbd>⌥⇧ V</kbd> | — |
| Anulowanie nagrania | <kbd>Esc</kbd> | <kbd>Esc</kbd> |
| Nagrywanie spotkania (start / stop) | <kbd>⌃⌥⌘ M</kbd> | <kbd>Ctrl Alt Shift M</kbd> |
| Oznaczenie „to ważne” podczas spotkania | <kbd>⌃⌥⌘ H</kbd> | <kbd>Ctrl Alt Shift H</kbd> |

Każdy skrót możesz zmienić w Ustawieniach. Pełny podręcznik użytkownika (po japońsku) to [docs/guide.md](docs/guide.md).

## Prywatność

- **Dźwięk domyślnie zostaje na urządzeniu.** Rozpoznawanie mowy, Whisper i rozpoznawanie mówców działają lokalnie.
- **AI dostaje tekst, nie dźwięk.** Gemini lub Claude otrzymuje transkrypcję. W zależności od ustawień może też otrzymać nazwę aplikacji, w której piszesz, kontekst ekranu oraz transkrypcje spotkań na potrzeby pytań i czatu z AI w trakcie spotkania.
- **Tryby Lokalnie i Apple również zatrzymują tekst na urządzeniu.** Jeśli wybierzesz którykolwiek z nich, nic nie jest wysyłane do usługi AI. Jedyne, co się pobiera, to sam model.
- **Dźwięk trafia do Google tylko wtedy, gdy tak wybierzesz.** Jeśli wybierzesz silnik mowy Gemini, nagrany dźwięk jest wysyłany do Google.
- **Spotkania to zwykłe pliki.** Są zapisywane jako JSON i Markdown w `~/Documents/Hanasu/Meetings/` (Windows: `Documents\Hanasu\Meetings\`). Mac i Windows używają tego samego formatu.
- **Brak telemetrii.** Hanasu nie zbiera żadnych danych analitycznych.
- **Klucze API są chronione przez system.** Na macOS są przechowywane w Keychain, a inne aplikacje muszą poprosić o Twoje hasło logowania, aby je odczytać. Na Windows są szyfrowane za pomocą DPAPI lub — jeśli tak wybierzesz — klucza Windows Hello. Żadne z tych rozwiązań nie zatrzyma w pełni złośliwego oprogramowania działającego na Twoim koncie. Zobacz [docs/design/security.md](docs/design/security.md).

> [!IMPORTANT]
> Przed nagrywaniem uzyskaj zgodę wszystkich uczestników spotkania. Przestrzegaj zasad swojej organizacji dotyczących nagrywania i korzystania z usług AI.

## Budowanie ze źródeł

<details>
<summary><b>macOS</b> (Xcode Command Line Tools, Swift 6.2)</summary>

```bash
./scripts/build-app.sh             # buduje build/Hanasu.app
open build/Hanasu.app
./scripts/create-signing-cert.sh   # opcjonalnie: zachowuje uprawnienia między kolejnymi kompilacjami
```

</details>

<details>
<summary><b>Windows</b> (.NET 8 SDK)</summary>

```bash
cd windows
dotnet build Hanasu.Windows.sln
dotnet publish Hanasu.Windows/Hanasu.Windows.csproj -c Release -r win-x64 --self-contained -p:PublishSingleFile=true -o publish/win-x64
```

Zobacz [windows/README.md](windows/README.md).

</details>

## Dokumentacja

Dokumentacja jest napisana po japońsku.

| | |
| --- | --- |
| [docs/guide.md](docs/guide.md) | Podręcznik użytkownika: jak używać, ustawienia, reguły słownika |
| [docs/spec/](docs/spec/) | Zaimplementowane wymagania (`REQ-*`) i decyzje projektowe (`DEC-*`) |
| [docs/design/](docs/design/) | Jak to jest zbudowane: architektura i przepływ danych |
| [docs/roadmap.md](docs/roadmap.md) | Plany, które nie zostały jeszcze zrealizowane |
| [docs/releasing.md](docs/releasing.md) | Jak powstają wydania (tagpr) |

## Współtworzenie

Zgłoszenia (issues) i pull requesty są mile widziane.

1. Zanim zmienisz jakiekolwiek zachowanie, przeczytaj [docs/README.md](docs/README.md).
2. Kod jest oznaczony tagami `// 要件: REQ-…` (wymaganie) lub `// 設計判断: DEC-…` (decyzja projektowa). W CI `scripts/check-spec.py` sprawdza, czy specyfikacja jest aktualizowana przy każdej zmianie otagowanego kodu.
3. Nowa funkcja zaczyna się jako wymaganie w `docs/spec/`. Pomysły na później trafiają do `docs/roadmap.md`.

## Licencja

Hanasu ma dostępny kod źródłowy (source-available), ale nie jest oprogramowaniem open source. © 2026 kakibara. Zobacz [NOTICE](NOTICE).

- Licencja: [PolyForm Noncommercial License 1.0.0](LICENSE) wraz z [Hanasu Additional Permission 1.0](LICENSE-ADDITIONAL-PERMISSION.md).
- Darmowe do osobistego użytku niekomercyjnego, w edukacji, badaniach, organizacjach charytatywnych i administracji publicznej oraz do wewnętrznej pracy małych firm (mniej niż 100 osób i przychody poniżej US$1M). Każda firma może oceniać Hanasu przez 30 dni.
- Większe firmy, a także każdy, kto sprzedaje Hanasu lub wbudowuje je w produkt albo usługę, potrzebują licencji komercyjnej. Zobacz [COMMERCIAL.md](COMMERCIAL.md).
- Wersje wydane przed tą zmianą licencji zostały wydane na licencji Apache License 2.0 i pozostają na niej.
- Wkład w projekt wymaga zaakceptowania umowy opisanej w [CONTRIBUTING.md](CONTRIBUTING.md).

Licencje zewnętrzne są wymienione w [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) (macOS) i [windows/THIRD_PARTY_NOTICES.md](windows/THIRD_PARTY_NOTICES.md) (Windows). Oba pliki są dołączone do pobieranych paczek.
