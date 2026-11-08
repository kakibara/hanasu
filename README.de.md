<div align="center">

<img src="docs/images/icon.png" width="112" alt="Hanasu-Symbol">

# Hanasu

**Sprich ganz natürlich. Erhalte sauberen, versandfertigen Text – und Besprechungsprotokolle, die sich von selbst schreiben.**

Eine App für Spracheingabe und Besprechungsnotizen für macOS und Windows. Sie nutzt Spracherkennung auf dem Gerät sowie Gemini, Claude oder ein KI-Modell, das auf deinem eigenen Gerät läuft.

[![Release](https://img.shields.io/github/v/release/kakibara/hanasu?sort=semver&label=release)](https://github.com/kakibara/hanasu/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/kakibara/hanasu/total)](https://github.com/kakibara/hanasu/releases)
[![License](https://img.shields.io/badge/license-PolyForm%20Noncommercial%20%2B%20small%20business-blue)](COMMERCIAL.md)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-000000?logo=apple)
![Windows 10/11](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows)
[![Windows build](https://github.com/kakibara/hanasu/actions/workflows/windows.yml/badge.svg)](https://github.com/kakibara/hanasu/actions/workflows/windows.yml)

[English](README.md) · [日本語](README.ja.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Français](README.fr.md) · **Deutsch** · [Italiano](README.it.md) · [Português (Brasil)](README.pt-BR.md) · [Русский](README.ru.md) · [Türkçe](README.tr.md) · [Tiếng Việt](README.vi.md) · [Bahasa Indonesia](README.id.md) · [Polski](README.pl.md) · [العربية](README.ar.md) · [हिन्दी](README.hi.md)

<sub>Dies ist eine Übersetzung der englischen README. Bei Abweichungen ist die englische README die aktuellste Fassung.</sub>

<img src="docs/images/hud.png" width="560" alt="Aufnahme-HUD von Hanasu">

</div>

> [!NOTE]
> Hanasu wurde in erster Linie für **Japanisch** gebaut, und Japanisch ist die am gründlichsten getestete Sprache.
> Die Oberfläche der App und die Anweisungen, die sie der KI gibt, gibt es in denselben 17 Sprachen wie diese README. Die Oberfläche folgt deiner Systemsprache, die KI-Anweisungen folgen der Transkriptionssprache in den Einstellungen. Für alle anderen Sprachen verwendet Hanasu Englisch.
> Es kann das Gesagte vor dem Eintippen auch in natürliches **Englisch**, ins **Japanische** oder in jede der 17 unterstützten Sprachen übersetzen.

## Warum Hanasu

Die eingebaute Diktierfunktion liefert dir ein rohes Transkript. Es enthält Füllwörter und Homophon-Fehler, hat keine Satzzeichen und jedes „Moment, ich meine …“ bleibt drin.
Hanasu schickt das Transkript an eine KI (Gemini, Claude oder ein lokales Modell auf deinem Gerät), die diese Fehler korrigiert und den Text glättet. Danach tippt Hanasu das Ergebnis dort ein, wo dein Cursor steht.
Inspiriert ist es von Typeless, Wispr Flow, Aqua Voice und Granola. Der Quellcode ist öffentlich. Für die private Nutzung und für kleine Unternehmen ist Hanasu kostenlos; größere Unternehmen brauchen eine [kommerzielle Lizenz](COMMERCIAL.md). Du verwendest deinen eigenen API-Schlüssel für Gemini oder Claude – oder du nutzt ein lokales Modell, ganz ohne API-Schlüssel und ohne dass Text dein Gerät verlässt.

## Funktionen

### 🎙️ Spracheingabe

| | |
| --- | --- |
| **Sprechen → ausgefeilter Text** | Drücke <kbd>⌥ Space</kbd>, sprich und drücke die Taste erneut (oder klicke auf **■ Stopp**). Hanasu entfernt Füllwörter, korrigiert Homophone, übernimmt deine Selbstkorrekturen und fügt den Text an der Cursorposition ein. |
| **Sprechen, übersetzt eintippen** | Drücke <kbd>⌥⇧ Space</kbd> oder stelle das HUD während des Sprechens auf **English**, **日本語** oder eine andere Sprache um. Feste Wendungen werden natürlich übersetzt, so wird お疲れ様です zu "Hi,". Welche Sprachen angeboten werden (jede der 17 unterstützten Sprachen), wählst du unter **Einstellungen → Allgemein**. Standard ist Englisch. Auf dem Mac kannst du unter **Einstellungen → Pro App** festlegen, dass eine App in einer dieser Sprachen startet. |
| **Gemischte Sprachen bleiben wie gesprochen** | Standardmäßig bleiben Teile, die du auf Englisch sagst, auf Englisch. Du kannst die Ausgabe stattdessen auch einheitlich auf Japanisch ausgeben lassen. |
| **Per Sprache bearbeiten** | Markiere einen Text, drücke <kbd>⌃⌥⌘ E</kbd> und sage „formuliere es höflicher“, „mach eine Aufzählung daraus“ oder „übersetze ins Englische“. |
| **Stile pro App** | In Slack ist der Text locker und kurz, in Mail höflich und in Absätzen, in Pages, Word und Notion im Schriftstil. Die Voreinstellung lässt sich für jede App ändern. |
| **Textbausteine** | Sage „E-Mail-Signatur“, um einen gespeicherten Text genau so einzufügen, wie du ihn geschrieben hast. Textbausteine werden nie an die KI gesendet. |
| **Wörterbuch** | Füge Eigennamen und Ersetzungsregeln wie `ストックマーク => Stockmark` hinzu. Auf dem Mac kann die KI außerdem neue Einträge aus deinem Verlauf und deinen Besprechungen vorschlagen – du übernimmst nur die, die du auswählst. |
| **Bildschirmkontext** *(optional)* | Hanasu liest den Fenstertitel und den Text rund um den Cursor, damit Namen zu dem passen, was schon auf dem Bildschirm steht. Passwortfelder werden nie gelesen. |
| **Mikrofon wählen** *(Mac)* | Wähle das Mikrofon in den Einstellungen oder wechsle es über die Mikrofontaste im HUD, ohne die Aufnahme zu stoppen. |
| **Verlauf** | Durchsuche frühere Ergebnisse und wiederhole fehlgeschlagene. Der Verlauf wird standardmäßig 30 Tage aufbewahrt; das lässt sich in den Einstellungen ändern. Auf dem Mac fügst du mit <kbd>⌥⇧ V</kbd> das letzte Ergebnis erneut ein. |
| **Nirgends zum Einfügen?** | Hat kein Textfeld den Fokus (zum Beispiel, weil der Schreibtisch im Vordergrund ist), lässt Hanasu das Ergebnis auf dem Bildschirm stehen, statt es einzufügen. Kopiere es von dort oder drücke einfach <kbd>⌘V</kbd> an der gewünschten Stelle (du kannst wählen, ob das Ergebnis in der Zwischenablage bleibt). |
| **Einfügen nicht angekommen?** | Hat das Einfügen keine App erreicht (zum Beispiel, weil du während der Aufnahme das Fenster gewechselt hast), lässt Hanasu das letzte Ergebnis in der Zwischenablage und weist im HUD darauf hin. Drücke <kbd>⌘V</kbd> an der gewünschten Stelle. Unter Einstellungen → Allgemein kannst du außerdem festlegen, dass sich in diesem Fall der Diktierverlauf öffnet. |

<p align="center">
  <img src="docs/images/hud-english.png" width="420" alt="Ausgabe auf Englisch">
  <img src="docs/images/edit-mode.png" width="420" alt="Per Sprache bearbeiten">
</p>

### 📝 Besprechungsnotizen

| | |
| --- | --- |
| **Nimmt beide Seiten auf** | Dein Mikrofon wird als „du“ aufgenommen, die Audioausgabe des Mac (Zoom, Meet, Teams, Slack-Huddles usw.) als „die anderen“. Kein Bot tritt dem Call bei. |
| **Sprechertrennung** | Die andere Seite wird auf dem Gerät in Sprecher 1, Sprecher 2 usw. aufgeteilt. Wenn aus dem Gespräch ein Name klar hervorgeht (etwa weil sich jemand vorstellt), trägt die KI ihn ein und kennzeichnet ihn als Vermutung. Sprecher kannst du nachträglich umbenennen. |
| **KI-Protokolle** | Erstellt von der KI, die du für Besprechungen wählst. Wähle eine Vorlage: automatisch, wöchentliches Meeting, 1-on-1, Verkaufsgespräch, Brainstorming oder benutzerdefiniert. Aufgaben enthalten eine verantwortliche Person und ein Fälligkeitsdatum. |
| **Live-Notizen & Markierungen** | Tippe während des Calls Notizen mit Zeitstempel oder drücke <kbd>⌃⌥⌘ H</kbd>, um „das ist wichtig“ zu markieren (10 Sekunden lang rückgängig zu machen). Das Protokoll berücksichtigt diese Stellen bevorzugt, und hinterher kannst du das Gespräch rund um jede Markierung nachlesen. |
| **Schwebende Untertitel** *(Mac)* | Zeige das Live-Transkript als Untertitel über deiner Besprechungs-App an. |
| **KI-Chat während der Besprechung** *(Mac)* | Frag die KI während der Aufnahme zum bisherigen Gespräch (<kbd>⌘J</kbd>). „Bisher zusammenfassen“ oder „Entscheidungen & To-dos“ mit einem Klick. Stell Folgefragen und klicke auf einen Zeitstempel in einer Antwort, um zu dieser Stelle im Transkript zu springen. |
| **Besprechungserkennung** | Sobald eine Besprechungs-App das Mikrofon nutzt, fragt Hanasu, ob aufgenommen werden soll. Es startet nie von selbst eine Aufnahme. |
| **Suchen & Fragen** | Durchsuche den Text aller Besprechungen oder frage „Was haben wir im Meeting letzte Woche beschlossen?“. Die Antwort nennt die Besprechungen, auf die sie sich stützt. |
| **Export** | Als Markdown oder als Slack-fertige Zusammenfassung kopieren, als `.md` / `.txt` speichern oder Aufgaben an Erinnerungen senden. |
| **Organisieren** | Benenne eine Besprechung um, indem du ihren Titel direkt bearbeitest, oder lösche eine Besprechung, die du nicht mehr brauchst. |

<p align="center">
  <img src="docs/images/meeting-live.png" width="420" alt="Aufnahme mit Live-Notizen">
  <img src="docs/images/meeting-ask.png" width="420" alt="Fragen an deine Besprechungen">
</p>
<p align="center">
  <img src="docs/images/meeting-minutes.png" width="420" alt="Protokoll mit Aufgaben">
  <img src="docs/images/meeting-suggestion.png" width="420" alt="Besprechungserkennung">
</p>

### 🤖 KI wählen

Wähle die KI, die deinen Text aufbereitet, getrennt für **Spracheingabe** und **Besprechungen**.

| KI | Standardmodell | Anmeldung |
| --- | --- | --- |
| **Gemini** (Standard unter Windows) | Spracheingabe `gemini-3.5-flash-lite`, Besprechungen `gemini-3.8-flash` | API-Schlüssel von Google AI Studio oder Vertex-AI-Dienstkonto |
| **Claude** | Spracheingabe `claude-haiku-5-5`, Besprechungen `claude-sonnet-5-5` (auch Opus 5.5 verfügbar) | Anthropic-API-Schlüssel |
| **Lokal** (auf deinem Gerät; Standard auf dem Mac) | Gemma 4 E4B (empfohlen). Siehe Tabelle unten | Keine. Lade das Modell unter **Einstellungen → KI** herunter. Fehlt auf dem Mac das Modell, wenn Hanasu mit dem Aufbereiten des Textes beginnt, fragt es, ob es heruntergeladen werden soll |
| **Apple** *(Mac, macOS 27)* | Das Apple-Intelligence-Modell auf dem Gerät, über den Befehl `fm` | Keine |

Diese KIs verarbeiten nur Text. Die Sprache wird von der unten beschriebenen Engine transkribiert.

#### 💻 Lokale Modelle

Mit **Lokal** führt Hanasu mithilfe des mitgelieferten [llama.cpp](https://github.com/ggml-org/llama.cpp) ein kleines Sprachmodell auf deinem eigenen Mac oder PC aus, sodass dein Text das Gerät nie verlässt. Der Mac nutzt die GPU (Metal), Windows die CPU. Ein Modell lädst du einmalig unter **Einstellungen → KI** herunter. Hanasu prüft vor der Verwendung dessen Größe und SHA-256.

| Modell | Größe | Lizenz | Hinweise |
| --- | --- | --- | --- |
| **Gemma 4 E4B** (Google) — **empfohlen** | 4,59 GB | Apache-2.0 | Die natürlichsten Ergebnisse, sowohl beim Aufbereiten als auch bei Protokollen. 16 GB Arbeitsspeicher oder mehr empfohlen. Standard für Spracheingabe und Besprechungen |
| LFM2.5-1.2B-JP (Liquid AI) | 1,25 GB | LFM Open License v1.0 | Klein und schnell. Organisationen mit einem Jahresumsatz ab 10 Mio. US-Dollar dürfen es unter dieser Lizenz nicht kommerziell nutzen |
| Sarashina2.2 3B (SB Intuitions) | 2,07 GB | MIT | Auf Japanisch trainiert. Der Kontext umfasst 8K, daher werden lange Besprechungen in Teilen zusammengefasst |
| Qwen3.5-4B (Alibaba) | 2,74 GB | Apache-2.0 | Etwa halb so groß wie Gemma und läuft daher leichter mit 8 GB Arbeitsspeicher. Schwächer als Gemma beim Umgang mit Selbstkorrekturen |

> [!TIP]
> Wir empfehlen **Gemma 4 E4B**. In unseren Tests behielten die anderen Modelle manchmal Wörter bei, die du zurücknehmen wolltest, fügten Sätze hinzu, die du nicht gesagt hast, verwechselten die verantwortliche Person einer Aufgabe oder führten Aufgaben zusammen bzw. ließen sie aus. Gemma 4 E4B hat sowohl das Aufbereiten als auch die Protokolle zuverlässig gemeistert.

### 🔊 Sprach-Engine wählen

| Engine | Läuft auf | Live-Transkript | Hinweise |
| --- | --- | --- | --- |
| **Betriebssystem-Standard** (Standard) | Mac: `SpeechAnalyzer` · Windows: `Windows.Media.SpeechRecognition` | ✅ | Auf dem Mac direkt auf dem Gerät |
| **Whisper** | Auf dem Gerät (WhisperKit auf dem Mac, whisper.cpp unter Windows) | — (nach dem Stoppen) | Das Modell wird bei der Auswahl heruntergeladen |
| **Gemini** | Google | — (nach dem Stoppen) | Das aufgenommene Audio wird an Google gesendet |

Für Spracheingabe und Besprechungen kannst du unterschiedliche Engines wählen. Unter Windows nutzen Besprechungen Whisper oder Gemini.
Auf dem Mac wählst du die Transkriptionssprache aus einer Liste (Japanisch, Englisch, Chinesisch, Koreanisch, Französisch, Deutsch, Spanisch, Italienisch, Portugiesisch). Voreingestellt ist deine Systemsprache.

## Download

Die neueste Version gibt es unter [**Releases**](https://github.com/kakibara/hanasu/releases/latest).

| Plattform | Datei | Voraussetzungen |
| --- | --- | --- |
| macOS | `Hanasu-<version>-macOS.zip` | macOS 26 (Tahoe) oder neuer, Apple Silicon |
| Windows | `Hanasu-<version>-Windows-x64.zip` | Windows 10 (2004 oder neuer) / 11, x64 |

<details>
<summary><b>macOS: erster Start</b></summary>

1. Entpacke die Datei und verschiebe `Hanasu.app` in den Ordner **Programme**.
2. Die App ist selbst signiert und nicht notarisiert, deshalb blockiert macOS sie beim ersten Mal. Klicke auf **Fertig**, öffne dann **Systemeinstellungen → Datenschutz & Sicherheit** und klicke auf **Dennoch öffnen**.
   Alternativ kannst du `xattr -dr com.apple.quarantine /Applications/Hanasu.app` ausführen.
3. Erlaube auf Nachfrage **Mikrofon**, **Spracherkennung** und **Bedienungshilfen**. Die Bedienungshilfen werden benötigt, um mit ⌘V einzufügen.

</details>

<details>
<summary><b>Windows: erster Start</b></summary>

1. Entpacke die Datei, lege den Ordner `Hanasu` an einem beliebigen Ort ab (zum Beispiel `%LOCALAPPDATA%\Programs`) und starte `Hanasu.exe`.
2. Die App ist nicht codesigniert, deshalb zeigt SmartScreen eine Warnung an. Klicke auf **Weitere Informationen → Trotzdem ausführen**.
3. Die Windows-Spracherkennung setzt voraus, dass in den Windows-Einstellungen die **Online-Spracherkennung** aktiviert ist. Hanasu weist dich darauf hin, wenn sie ausgeschaltet ist.

Weitere Hinweise und die Unterschiede zwischen der Windows- und der Mac-Version findest du in [windows/README.md](windows/README.md).

</details>

Wenn eine neue Version erscheint, informiert dich Hanasu beim Start und fragt nach, bevor es sich selbst aktualisiert. Du kannst auch im Menü **アップデートを確認…** (Nach Updates suchen) wählen (die Prüfung beim Start lässt sich unter **Einstellungen → Allgemein** ausschalten). Versionen bis v1.5.0 haben das noch nicht; aktualisiere sie daher einmal von Hand.

## Schnellstart

Auf dem Mac öffnet sich beim ersten Start eine kurze Einführung. Dort wählst du deine KI aus (Gemma 4 E4B, das empfohlene lokale Modell, wird direkt dort heruntergeladen), siehst die wichtigsten Funktionen und Tipps zu den Einstellungen und erteilst die Berechtigungen, die Hanasu braucht. Du kannst sie jederzeit über **So verwendest du Hanasu …** im Menü erneut öffnen.

1. **KI wählen.** Öffne **Einstellungen → KI** und wähle eine KI für Spracheingabe und für Besprechungen. Für Gemini fügst du einen API-Schlüssel aus [Google AI Studio](https://aistudio.google.com/apikey) ein oder wählst eine JSON-Datei eines Vertex-AI-Dienstkontos. Für Claude fügst du einen API-Schlüssel aus der [Claude Console](https://console.anthropic.com/settings/keys) ein. Für Lokal lädst du ein Modell herunter (Gemma 4 E4B wird empfohlen); ein Schlüssel ist nicht nötig. Klicke auf die Testschaltfläche, um zu prüfen, ob alles funktioniert.
2. **Diktieren.** Setze den Cursor an die gewünschte Stelle, drücke das Tastenkürzel, sprich und drücke das Tastenkürzel erneut.
3. **Besprechung aufnehmen.** Nutze das Menü in der Menüleiste (Mac) bzw. im Infobereich (Windows) oder das Tastenkürzel. Kopfhörer helfen, die beiden Seiten sauber zu trennen.

Auf dem Mac kannst du das Hanasu-Symbol in der Menüleiste, im Dock oder an beiden Stellen anzeigen (Einstellungen → Allgemein).

### Standard-Tastenkürzel

| Aktion | macOS | Windows |
| --- | --- | --- |
| Spracheingabe (Start / Stopp) | <kbd>⌥ Space</kbd> | <kbd>Ctrl Alt Space</kbd> |
| Spracheingabe mit Übersetzung (in die gewählten Sprachen) | <kbd>⌥⇧ Space</kbd> | <kbd>Ctrl Alt Shift Space</kbd> |
| Auswahl per Sprache bearbeiten | <kbd>⌃⌥⌘ E</kbd> | — |
| Letztes Ergebnis erneut einfügen | <kbd>⌥⇧ V</kbd> | — |
| Aufnahme abbrechen | <kbd>Esc</kbd> | <kbd>Esc</kbd> |
| Besprechungsaufnahme (Start / Stopp) | <kbd>⌃⌥⌘ M</kbd> | <kbd>Ctrl Alt Shift M</kbd> |
| „Das ist wichtig“ in einer Besprechung markieren | <kbd>⌃⌥⌘ H</kbd> | <kbd>Ctrl Alt Shift H</kbd> |

Alle Tastenkürzel lassen sich in den Einstellungen ändern. Das vollständige Benutzerhandbuch (auf Japanisch) findest du unter [docs/guide.md](docs/guide.md).

## Datenschutz

- **Audio bleibt standardmäßig auf deinem Gerät.** Spracherkennung, Whisper und Sprechertrennung laufen alle lokal.
- **Die KI erhält Text, kein Audio.** Gemini oder Claude bekommt das Transkript. Je nach Einstellungen kann es außerdem den Namen der App erhalten, in die du tippst, den Bildschirmkontext sowie Besprechungstranskripte für Fragen und den KI-Chat in Besprechungen.
- **Lokal und Apple halten auch den Text auf deinem Gerät.** Wenn du eine der beiden Optionen wählst, wird nichts an einen KI-Dienst gesendet. Heruntergeladen wird nur das Modell selbst.
- **Audio geht nur an Google, wenn du das so wählst.** Wenn du die Gemini-Sprach-Engine auswählst, wird das aufgenommene Audio an Google gesendet.
- **Besprechungen sind einfache Dateien.** Sie werden als JSON und Markdown unter `~/Documents/Hanasu/Meetings/` gespeichert (Windows: `Documents\Hanasu\Meetings\`). Mac und Windows verwenden dasselbe Format.
- **Keine Telemetrie.** Hanasu erhebt keine Nutzungsdaten.
- **API-Schlüssel sind durch das Betriebssystem geschützt.** Unter macOS liegen sie im Keychain, und andere Apps müssen dein Anmeldepasswort abfragen, um sie zu lesen. Unter Windows werden sie mit DPAPI verschlüsselt oder, wenn du das wählst, mit einem Windows-Hello-Schlüssel. Beides kann Schadsoftware, die unter deinem Benutzerkonto läuft, nicht vollständig aufhalten. Siehe [docs/design/security.md](docs/design/security.md).

> [!IMPORTANT]
> Hol vor der Aufnahme die Zustimmung aller Teilnehmenden ein. Halte dich an die Regeln deiner Organisation zu Aufnahmen und zur Nutzung von KI-Diensten.

## Aus dem Quellcode bauen

<details>
<summary><b>macOS</b> (Xcode Command Line Tools, Swift 6.2)</summary>

```bash
./scripts/build-app.sh             # baut build/Hanasu.app
open build/Hanasu.app
./scripts/create-signing-cert.sh   # optional: behält Berechtigungen über Neubauten hinweg
```

</details>

<details>
<summary><b>Windows</b> (.NET 8 SDK)</summary>

```bash
cd windows
dotnet build Hanasu.Windows.sln
dotnet publish Hanasu.Windows/Hanasu.Windows.csproj -c Release -r win-x64 --self-contained -p:PublishSingleFile=true -o publish/win-x64
```

Siehe [windows/README.md](windows/README.md).

</details>

## Dokumentation

Die Dokumentation ist auf Japanisch verfasst.

| | |
| --- | --- |
| [docs/guide.md](docs/guide.md) | Benutzerhandbuch: Bedienung, Einstellungen, Wörterbuchregeln |
| [docs/spec/](docs/spec/) | Umgesetzte Anforderungen (`REQ-*`) und Designentscheidungen (`DEC-*`) |
| [docs/design/](docs/design/) | Wie es gebaut ist: Architektur und Datenfluss |
| [docs/roadmap.md](docs/roadmap.md) | Pläne, die noch nicht umgesetzt sind |
| [docs/releasing.md](docs/releasing.md) | Wie Releases erstellt werden (tagpr) |

## Mitwirken

Issues und Pull Requests sind willkommen.

1. Lies [docs/README.md](docs/README.md), bevor du ein Verhalten änderst.
2. Der Code ist mit `// 要件: REQ-…` (Anforderung) oder `// 設計判断: DEC-…` (Designentscheidung) markiert. In der CI prüft `scripts/check-spec.py`, dass die Spezifikation aktualisiert wird, sobald sich markierter Code ändert.
3. Eine neue Funktion beginnt als Anforderung in `docs/spec/`. Ideen für später gehören in `docs/roadmap.md`.

## Lizenz

Hanasu ist Source-Available-Software, nicht Open Source. © 2026 kakibara. Siehe [NOTICE](NOTICE).

- Lizenz: [PolyForm Noncommercial License 1.0.0](LICENSE) plus die [Hanasu Additional Permission 1.0](LICENSE-ADDITIONAL-PERMISSION.md).
- Kostenlos für die private, nicht kommerzielle Nutzung, für Bildung, Forschung, gemeinnützige Organisationen und staatliche Stellen sowie für die interne Arbeit kleiner Unternehmen (weniger als 100 Personen und unter US$1M Umsatz). Jedes Unternehmen darf Hanasu 30 Tage lang evaluieren.
- Größere Unternehmen sowie alle, die Hanasu verkaufen oder in ein Produkt oder einen Dienst einbauen, brauchen eine kommerzielle Lizenz. Siehe [COMMERCIAL.md](COMMERCIAL.md).
- Versionen, die vor dieser Lizenzänderung veröffentlicht wurden, wurden unter der Apache License 2.0 veröffentlicht und bleiben unter ihr.
- Beiträge setzen die Vereinbarung in [CONTRIBUTING.md](CONTRIBUTING.md) voraus.

Lizenzen von Drittanbietern sind in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) (macOS) und [windows/THIRD_PARTY_NOTICES.md](windows/THIRD_PARTY_NOTICES.md) (Windows) aufgeführt. Beide Dateien sind in den Downloads enthalten.
