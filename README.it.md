<div align="center">

<img src="docs/images/icon.png" width="112" alt="Icona di Hanasu">

# Hanasu

**Parla in modo naturale. Ottieni testo pulito, pronto da inviare, e verbali delle riunioni che si scrivono da soli.**

Un'app per la dettatura vocale e le note delle riunioni per macOS e Windows. Usa il riconoscimento vocale sul dispositivo e Gemini, Claude o un modello di IA che gira sul tuo dispositivo.

[![Release](https://img.shields.io/github/v/release/kakibara/hanasu?sort=semver&label=release)](https://github.com/kakibara/hanasu/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/kakibara/hanasu/total)](https://github.com/kakibara/hanasu/releases)
[![License](https://img.shields.io/badge/license-PolyForm%20Noncommercial%20%2B%20small%20business-blue)](COMMERCIAL.md)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-000000?logo=apple)
![Windows 10/11](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows)
[![Windows build](https://github.com/kakibara/hanasu/actions/workflows/windows.yml/badge.svg)](https://github.com/kakibara/hanasu/actions/workflows/windows.yml)

[English](README.md) · [日本語](README.ja.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · **Italiano** · [Português (Brasil)](README.pt-BR.md) · [Русский](README.ru.md) · [Türkçe](README.tr.md) · [Tiếng Việt](README.vi.md) · [Bahasa Indonesia](README.id.md) · [Polski](README.pl.md) · [العربية](README.ar.md) · [हिन्दी](README.hi.md)

<sub>Questa è una traduzione del README in inglese. In caso di differenze, il README in inglese è il più aggiornato.</sub>

<img src="docs/images/hud.png" width="560" alt="HUD di registrazione di Hanasu">

</div>

> [!NOTE]
> Hanasu è stato pensato prima di tutto per il **giapponese**, e il giapponese è la lingua più testata.
> Le schermate dell'app e le istruzioni che dà all'IA sono disponibili nelle stesse 17 lingue di questo README. Le schermate seguono la lingua di sistema, e le istruzioni per l'IA seguono la lingua di trascrizione nelle Impostazioni. Per qualsiasi altra lingua, Hanasu usa l'inglese.
> Può anche tradurre ciò che dici in un **inglese** naturale, in **giapponese** o in una qualsiasi delle 17 lingue supportate prima di digitarlo.

## Perché Hanasu

La dettatura integrata ti dà una trascrizione grezza. Mantiene i riempitivi e gli errori sugli omofoni, non ha punteggiatura e include ogni "aspetta, cioè…".
Hanasu invia la trascrizione a un'IA (Gemini, Claude o un modello locale sul tuo dispositivo), che corregge quegli errori e sistema il testo. Poi Hanasu digita il risultato dove si trova il cursore.
Si ispira a Typeless, Wispr Flow, Aqua Voice e Granola. Il suo codice sorgente è pubblico. È gratuito per uso personale e per le piccole imprese; le aziende più grandi hanno bisogno di una [licenza commerciale](COMMERCIAL.md). Usi la tua chiave API di Gemini o Claude, oppure esegui un modello locale senza chiave API e senza che il testo lasci il tuo dispositivo.

## Funzionalità

### 🎙️ Dettatura vocale

| | |
| --- | --- |
| **Parla → testo rifinito** | Premi <kbd>⌥ Space</kbd>, parla e premilo di nuovo (oppure fai clic su **■ Fatto**). Hanasu rimuove i riempitivi, corregge gli omofoni, applica le tue autocorrezioni e incolla il testo nel punto del cursore. |
| **Parla e digita la traduzione** | Premi <kbd>⌥⇧ Space</kbd>, oppure passa l'HUD a **English**, **日本語** o a un'altra lingua mentre parli. Le formule di cortesia vengono tradotte in modo naturale, così お疲れ様です diventa "Hi,". Scegli le lingue da proporre (una qualsiasi delle 17 lingue supportate) in **Impostazioni → Generali**. L'inglese è il predefinito. Su Mac, in **Impostazioni → Per app** puoi far partire un'app in una di queste lingue. |
| **Le lingue miste restano come le pronunci** | Per impostazione predefinita, le parti che dici in inglese restano in inglese. In alternativa puoi scegliere di uniformare l'output in giapponese. |
| **Modifica con la voce** | Seleziona del testo, premi <kbd>⌃⌥⌘ E</kbd> e di' "rendilo più cortese", "trasformalo in un elenco puntato" o "traduci in inglese". |
| **Stili per app** | Il testo è informale e breve in Slack, cortese e diviso in paragrafi in Mail, e in stile scritto in Pages, Word e Notion. Puoi cambiare il preset per ogni app. |
| **Snippet** | Di' "firma email" per inserire un testo salvato esattamente come l'hai scritto. Gli snippet non vengono mai inviati all'IA. |
| **Dizionario** | Aggiungi nomi propri e regole di sostituzione come `ストックマーク => Stockmark`. Le regole valgono anche per le trascrizioni delle riunioni. Da una riunione aperta in Note delle riunioni, l'IA può suggerire nuove voci tratte da quella riunione (su Mac anche dalla cronologia e dalle riunioni recenti), e aggiungi solo quelle che scegli. |
| **Contesto dello schermo** *(facoltativo)* | Hanasu legge il titolo della finestra e il testo intorno al cursore, così i nomi corrispondono a ciò che è già sullo schermo. I campi password non vengono mai letti. |
| **Testo degli screenshot** *(facoltativo, Mac)* | Hanasu fa uno screenshot di tutti i tuoi schermi, legge il testo sul tuo Mac e passa all'IA solo quel testo, così nomi e numeri di modello presenti in altre finestre (per esempio «QX-7s») vengono scritti come appaiono. L'immagine non viene mai inviata né salvata. Attivalo o disattivalo per una singola registrazione con il pulsante nell'HUD. Richiede l'autorizzazione Registrazione schermo. |
| **Scegli il microfono** *(Mac)* | Scegli il microfono nelle Impostazioni, oppure cambialo dal pulsante del microfono nell'HUD senza interrompere la registrazione. |
| **Cronologia** | Cerca i risultati passati e riprova quelli non riusciti. La cronologia viene conservata per 30 giorni per impostazione predefinita, e puoi cambiarlo nelle Impostazioni. Su Mac, premi <kbd>⌥⇧ V</kbd> per incollare di nuovo l'ultimo risultato. |
| **Nessun posto dove incollare?** | Se nessun campo di testo ha il focus (per esempio, è in primo piano la scrivania), Hanasu mostra il risultato sullo schermo invece di incollarlo. Copialo da lì, oppure premi semplicemente <kbd>⌘V</kbd> dove ti serve (puoi scegliere se il risultato resta negli appunti). |
| **L'incolla non è arrivato?** | Se l'incolla non ha mai raggiunto un'app (per esempio, hai cambiato finestra durante la registrazione), Hanasu lascia l'ultimo risultato negli appunti e te lo segnala nell'HUD. Premi <kbd>⌘V</kbd> dove ti serve. In Impostazioni → Generali puoi anche far aprire la cronologia della dettatura quando succede. |

<p align="center">
  <img src="docs/images/hud-english.png" width="420" alt="Output in inglese">
  <img src="docs/images/edit-mode.png" width="420" alt="Modifica con la voce">
</p>

### 📝 Note delle riunioni

| | |
| --- | --- |
| **Registra entrambe le parti** | Il tuo microfono viene registrato come "tu". L'uscita audio del Mac (Zoom, Meet, Teams, huddle di Slack e così via) viene registrata come "loro". Nessun bot entra nella chiamata. |
| **Diarizzazione dei parlanti** | L'altra parte viene suddivisa in Parlante 1, Parlante 2 e così via, sul dispositivo. Quando la conversazione rende chiaro un nome (per esempio, qualcuno si presenta), l'IA lo inserisce e lo segna come ipotesi. Puoi rinominare i parlanti in seguito. |
| **Verbali con IA** | Generati dall'IA che scegli per le riunioni. Scegli un modello: automatico, riunione settimanale, 1-on-1, chiamata commerciale, brainstorming o personalizzato. Le azioni da svolgere includono un responsabile e una scadenza. |
| **Verifica la fonte e riascolta** *(Mac)* | Il verbale si apre in un'unica pagina: prima il riepilogo e le azioni da svolgere, con la trascrizione accanto. Fai clic sulla marca temporale dopo un punto per passare all'intervento da cui proviene. Riproduci la registrazione da qualsiasi intervento e silenzia la tua parte o la loro se nella chiamata c'era eco. |
| **Note dal vivo e momenti salienti** | Scrivi note con marca temporale durante la chiamata, oppure premi <kbd>⌃⌥⌘ H</kbd> per segnare "questo è importante" (puoi annullarlo per 10 secondi). Il verbale dà priorità a quelle parti, e in seguito puoi rileggere la conversazione intorno a ogni segno. |
| **Sottotitoli fluttuanti** *(Mac)* | Mostra la trascrizione dal vivo come sottotitoli sopra l'app della riunione. Se li lasci attivi, ricompaiono anche alla riunione successiva. |
| **Chat IA durante la riunione** *(Mac)* | Durante la registrazione, chiedi all'IA della conversazione fin qui (<kbd>⌘J</kbd>). Un clic per "riassunto fin qui" o "decisioni e cose da fare". Fai domande di approfondimento e fai clic su una marca temporale in una risposta per passare a quel punto della trascrizione. Ti fanno una domanda all'improvviso mentre stai facendo altro? Premi **Cosa mi hanno chiesto?** nei sottotitoli (oppure <kbd>⌃⌥⌘ A</kbd>) senza lasciare l'app della riunione: un pannello fluttuante mostra cosa hanno appena detto gli altri, poi il riepilogo dell'IA con la domanda e il contesto da cui è nata. Dal menu sotto il campo di testo puoi cambiare l'IA e il modello per quella conversazione. |
| **Rilevamento delle riunioni** | Quando un'app di riunioni inizia a usare il microfono, Hanasu chiede se registrare. Non inizia mai a registrare da solo. |
| **Cerca e chiedi** | Cerca nel testo di tutte le riunioni, oppure chiedi "Cosa abbiamo deciso nella riunione della settimana scorsa?". La risposta cita le riunioni che ha usato. |
| **Esporta** | Copia come Markdown o come riepilogo pronto per Slack, salva come `.md` / `.txt`, oppure invia le azioni da svolgere a Promemoria. |
| **Organizza** | Rinomina una riunione modificandone il titolo direttamente, oppure elimina una riunione che non ti serve più. |

<p align="center">
  <img src="docs/images/meeting-live.png" width="420" alt="Registrazione con note dal vivo">
  <img src="docs/images/meeting-ask.png" width="420" alt="Fai domande sulle tue riunioni">
</p>
<p align="center">
  <img src="docs/images/meeting-minutes.png" width="420" alt="Verbale con azioni da svolgere">
  <img src="docs/images/meeting-suggestion.png" width="420" alt="Rilevamento delle riunioni">
</p>

### 🤖 Scegli la tua IA

Scegli l'IA che rifinisce il testo, separatamente per la **dettatura vocale** e per le **riunioni** (verbali). Sul Mac ne scegli una anche per **Chat IA e domande** (la chat IA della riunione e le domande sulle riunioni passate).

| IA | Modello predefinito | Accesso |
| --- | --- | --- |
| **Gemini** (predefinita su Windows) | dettatura vocale `gemini-3.5-flash-lite`, riunioni e Chat IA e domande `gemini-3.8-flash` | Chiave API di Google AI Studio o service account di Vertex AI |
| **Claude** | dettatura vocale e Chat IA e domande `claude-haiku-5-5`, riunioni `claude-sonnet-5-5` (disponibile anche Opus 5.5) | Chiave API di Anthropic |
| **Locale** (sul tuo dispositivo; predefinita su Mac) | Gemma 4 E4B (consigliato). Vedi la tabella qui sotto | Nessuno. Scarica il modello in **Impostazioni → IA**. Su Mac, se il modello manca quando Hanasu inizia a rifinire il testo, ti chiede se scaricarlo |
| **Apple** *(Mac, macOS 27)* | Il modello Apple Intelligence sul dispositivo, tramite il comando `fm` | Nessuno |

Queste IA gestiscono solo testo. Il parlato viene trascritto dal motore qui sotto.

#### 💻 Modelli locali

Con **Locale**, Hanasu esegue un piccolo modello linguistico sul tuo Mac o PC con [llama.cpp](https://github.com/ggml-org/llama.cpp) incluso, così il testo non lascia mai il dispositivo. Il Mac usa la GPU (Metal) e Windows usa la CPU. Scarichi un modello una sola volta da **Impostazioni → IA**. Hanasu ne verifica dimensione e SHA-256 prima di usarlo.

| Modello | Dimensione | Licenza | Note |
| --- | --- | --- | --- |
| **Gemma 4 E4B** (Google) — **consigliato** | 4.59 GB | Apache-2.0 | I risultati più naturali sia per la pulizia del testo sia per i verbali. Si consigliano almeno 16 GB di memoria. È il predefinito sia per la dettatura vocale sia per le riunioni |
| LFM2.5-1.2B-JP (Liquid AI) | 1.25 GB | LFM Open License v1.0 | Piccolo e veloce. Con questa licenza, le organizzazioni con un fatturato annuo pari o superiore a 10 milioni di dollari USA non possono usarlo a fini commerciali |
| Sarashina2.2 3B (SB Intuitions) | 2.07 GB | MIT | Addestrato sul giapponese. Il suo contesto è di 8K, quindi le riunioni lunghe vengono riassunte a parti |
| Qwen3.5-4B (Alibaba) | 2.74 GB | Apache-2.0 | Circa metà della dimensione di Gemma, quindi è più facile da eseguire con 8 GB di memoria. Meno efficace di Gemma nel gestire le autocorrezioni |

> [!TIP]
> Consigliamo **Gemma 4 E4B**. Nei nostri test, gli altri modelli a volte mantenevano le parole che volevi ritirare, aggiungevano frasi che non avevi detto, confondevano il responsabile di un'azione da svolgere, oppure univano o perdevano azioni da svolgere. Gemma 4 E4B ha gestito in modo affidabile sia la pulizia del testo sia i verbali.

### 🔊 Scegli il motore di riconoscimento vocale

| Motore | Dove gira | Trascrizione dal vivo | Note |
| --- | --- | --- | --- |
| **Standard del sistema operativo** (predefinito) | Mac: `SpeechAnalyzer` · Windows: `Windows.Media.SpeechRecognition` | ✅ | Sul dispositivo su Mac |
| **Whisper** | Sul dispositivo (WhisperKit su Mac, whisper.cpp su Windows) | — (dopo l'interruzione) | Il modello viene scaricato quando lo selezioni |
| **Gemini** | Google | — (dopo l'interruzione) | L'audio registrato viene inviato a Google |

Puoi scegliere un motore diverso per la dettatura vocale e per le riunioni. Su Windows, le riunioni usano Whisper o Gemini.
Su Mac, scegli la lingua di trascrizione da un elenco (giapponese, inglese, cinese, coreano, francese, tedesco, spagnolo, italiano, portoghese). All'inizio è la lingua del sistema.

### ⌨️ Usalo dal terminale e dagli agenti IA

Il comando `hanasu` permette a script e agenti IA (Claude Code, Claude Desktop e altri) di leggere le registrazioni delle tue riunioni e di usare il tuo stile di rifinitura. È incluso nell'app, quindi non c'è altro da installare: sul Mac è l'app stessa, su Windows è `cli\hanasu.exe` nella cartella di Hanasu. Apri **Impostazioni → Comando e MCP** per collegarlo a Claude Desktop, ChatGPT (Codex) o Claude Code con un clic, per aggiungerlo al PATH o per copiare la configurazione MCP per altre app. (Per ora la normale chat di ChatGPT non può usare gli strumenti MCP locali a causa di un bug di OpenAI; Codex sì.)

| | |
| --- | --- |
| **Leggi le riunioni** | `hanasu meetings list / show / search` e `hanasu actions` stampano riunioni, verbali, trascrizioni e azioni da svolgere, come testo o con `--json`. Non viene inviato nulla. |
| **Chiedi** | `hanasu ask "Cosa abbiamo deciso la settimana scorsa?"` risponde a partire dalle tue riunioni. Sul Mac usa l'IA che hai scelto per **Chat IA e domande** (o quella delle riunioni, se non ne hai scelta una); su Windows, quella delle riunioni. |
| **Rifinisci il testo** | `hanasu refine` rifinisce o traduce il testo come fa la dettatura vocale, e `hanasu edit "<istruzione>"` lo riscrive. Entrambi funzionano nelle pipe. `--app` sceglie lo stile di un'app (un bundle ID sul Mac, il nome di un eseguibile come `slack.exe` su Windows). |
| **MCP per agenti IA** | `hanasu mcp` è un server MCP (stdio). Gli agenti possono elencare, leggere, cercare e interrogare le tue riunioni. Il contenuto delle riunioni condiviso in questo modo arriva all'agente e al fornitore della sua IA. |
| **Verifica la configurazione** | `hanasu doctor` mostra quale IA e quali credenziali vengono usate, la cartella delle riunioni e come registrare MCP. Esegui `hanasu help` per vedere tutte le opzioni. |

Su Windows, esegui `[Console]::OutputEncoding = [Text.UTF8Encoding]::new()` prima di leggere l'output in PowerShell. Le chiavi API protette con Windows Hello ti chiedono una conferma ogni volta che un comando le usa.

Sul Mac, gli amministratori possono disattivare il comando, MCP o alcune IA con un profilo di configurazione.

## Download

Scarica l'ultima build da [**Releases**](https://github.com/kakibara/hanasu/releases/latest).

| Piattaforma | File | Requisiti |
| --- | --- | --- |
| macOS | `Hanasu-<version>-macOS.zip` | macOS 26 (Tahoe) o successivo, Apple Silicon |
| Windows | `Hanasu-<version>-Windows-x64.zip` | Windows 10 (2004 o successivo) / 11, x64 |

<details>
<summary><b>macOS: primo avvio</b></summary>

1. Estrai il file e sposta `Hanasu.app` in **Applicazioni**.
2. L'app è autofirmata e non notarizzata, quindi macOS la blocca la prima volta. Fai clic su **Fine**, poi apri **Impostazioni di Sistema → Privacy e sicurezza** e fai clic su **Apri comunque**.
   In alternativa puoi eseguire `xattr -dr com.apple.quarantine /Applications/Hanasu.app`.
3. Quando richiesto, consenti **Microfono**, **Riconoscimento vocale** e **Accessibilità**. L'accessibilità serve per incollare con ⌘V. **Registrazione schermo** viene richiesta solo se attivi il testo degli screenshot.

</details>

<details>
<summary><b>Windows: primo avvio</b></summary>

1. Estrai il file, metti la cartella `Hanasu` dove vuoi (per esempio `%LOCALAPPDATA%\Programs`) ed esegui `Hanasu.exe`.
2. L'app non ha la firma del codice, quindi SmartScreen mostra un avviso. Fai clic su **Ulteriori informazioni → Esegui comunque**.
3. Il motore vocale di Windows richiede che **Riconoscimento vocale online** sia attivato nelle impostazioni di Windows. Hanasu ti avvisa se è disattivato.

Vedi [windows/README.md](windows/README.md) per altre note e per le differenze tra la versione Windows e quella Mac.

</details>

Quando esce una nuova versione, Hanasu te lo segnala all'avvio e te lo chiede prima di aggiornarsi. Puoi anche scegliere **アップデートを確認…** (Controlla aggiornamenti) nel menu (il controllo all'avvio si può disattivare in **Impostazioni → Generali**). Le versioni fino alla v1.5.0 non hanno ancora questa funzione, quindi aggiornale a mano una volta.

## Avvio rapido

Su Mac, il primo avvio apre un breve tour guidato. Ti permette di scegliere l'IA (Gemma 4 E4B, il modello locale consigliato, si scarica direttamente lì), mostra le funzionalità principali e alcuni consigli sulle impostazioni, e chiede i permessi di cui Hanasu ha bisogno. Puoi riaprirlo in qualsiasi momento da **Come usare Hanasu…** nel menu.

1. **Scegli un'IA.** Apri **Impostazioni → IA** e scegli un'IA per la dettatura vocale e per le riunioni (sul Mac, anche per Chat IA e domande). Per Gemini, incolla una chiave API da [Google AI Studio](https://aistudio.google.com/apikey) oppure seleziona un file JSON di service account di Vertex AI. Per Claude, incolla una chiave API dalla [Claude Console](https://console.anthropic.com/settings/keys). Per Locale, scarica un modello (si consiglia Gemma 4 E4B). Non serve alcuna chiave. Fai clic sul pulsante di prova per verificare che funzioni.
2. **Detta.** Metti il cursore dove vuoi il testo, premi la scorciatoia, parla e premi di nuovo la scorciatoia.
3. **Registra una riunione.** Usa il menu nella barra dei menu (Mac) o nell'area di notifica (Windows), oppure la scorciatoia. Le cuffie aiutano a tenere separate le due parti.

Su Mac puoi mostrare l'icona di Hanasu nella barra dei menu, nel Dock o in entrambi (Impostazioni → Generali).

### Scorciatoie predefinite

| Azione | macOS | Windows |
| --- | --- | --- |
| Dettatura vocale (avvia / interrompi) | <kbd>⌥ Space</kbd> | <kbd>Ctrl Alt Space</kbd> |
| Dettatura vocale tradotta (nelle lingue scelte) | <kbd>⌥⇧ Space</kbd> | <kbd>Ctrl Alt Shift Space</kbd> |
| Modifica la selezione con la voce | <kbd>⌃⌥⌘ E</kbd> | — |
| Incolla di nuovo l'ultimo risultato | <kbd>⌥⇧ V</kbd> | — |
| Annulla la registrazione | <kbd>Esc</kbd> | <kbd>Esc</kbd> |
| Registrazione della riunione (avvia / interrompi) | <kbd>⌃⌥⌘ M</kbd> | <kbd>Ctrl Alt Shift M</kbd> |
| Segna "questo è importante" in una riunione | <kbd>⌃⌥⌘ H</kbd> | <kbd>Ctrl Alt Shift H</kbd> |
| "Cosa mi hanno chiesto?" in una riunione | <kbd>⌃⌥⌘ A</kbd> | — |

Puoi cambiare ogni scorciatoia nelle Impostazioni. La guida utente completa (in giapponese) è [docs/guide.md](docs/guide.md).

## Privacy

- **Per impostazione predefinita l'audio resta sul tuo dispositivo.** Il riconoscimento vocale, Whisper e la diarizzazione dei parlanti girano tutti in locale.
- **L'IA riceve testo, non audio.** Gemini o Claude ricevono la trascrizione. A seconda delle impostazioni, possono ricevere anche il nome dell'app in cui stai scrivendo, il contesto dello schermo, il testo letto da uno screenshot dello schermo (mai l'immagine) e le trascrizioni delle riunioni per la funzione Chiedi e per la chat IA durante la riunione.
- **Anche Locale e Apple tengono il testo sul tuo dispositivo.** Se scegli una delle due, non viene inviato nulla a un servizio di IA. L'unico download è il modello stesso.
- **L'audio va a Google solo se lo scegli tu.** Se selezioni il motore vocale Gemini, l'audio registrato viene inviato a Google.
- **Gli agenti ricevono le riunioni solo se li colleghi.** Il comando `hanasu` e il suo server MCP leggono le riunioni solo quando li chiami tu o un agente, e ciò che restituiscono va a quell'agente e al fornitore della sua IA.
- **Le riunioni sono semplici file.** Vengono salvate come JSON e Markdown in `~/Documents/Hanasu/Meetings/` (Windows: `Documents\Hanasu\Meetings\`). Mac e Windows usano lo stesso formato.
- **Nessuna telemetria.** Hanasu non raccoglie dati analitici.
- **Le chiavi API sono protette dal sistema operativo.** Su macOS sono conservate nel Keychain, e le altre app devono chiedere la tua password di login per leggerle. Su Windows sono cifrate con DPAPI, oppure con una chiave di Windows Hello se lo scegli. Nessuno dei due può fermare del tutto un malware eseguito con il tuo utente. Vedi [docs/design/security.md](docs/design/security.md).

> [!IMPORTANT]
> Ottieni il consenso di tutti i partecipanti alla riunione prima di registrare. Rispetta le regole della tua organizzazione sulla registrazione e sull'uso dei servizi di IA.

## Compilare dai sorgenti

<details>
<summary><b>macOS</b> (Xcode Command Line Tools, Swift 6.2)</summary>

```bash
./scripts/build-app.sh             # compila build/Hanasu.app
open build/Hanasu.app
./scripts/create-signing-cert.sh   # facoltativo: mantiene i permessi tra una ricompilazione e l'altra
```

</details>

<details>
<summary><b>Windows</b> (.NET 8 SDK)</summary>

```bash
cd windows
dotnet build Hanasu.Windows.sln
dotnet publish Hanasu.Windows/Hanasu.Windows.csproj -c Release -r win-x64 --self-contained -p:PublishSingleFile=true -o publish/win-x64
```

Vedi [windows/README.md](windows/README.md).

</details>

## Documentazione

La documentazione è scritta in giapponese.

| | |
| --- | --- |
| [docs/guide.md](docs/guide.md) | Guida utente: come usarlo, impostazioni, regole del dizionario |
| [docs/spec/](docs/spec/) | Requisiti implementati (`REQ-*`) e decisioni di progettazione (`DEC-*`) |
| [docs/design/](docs/design/) | Come è costruito: architettura e flusso dei dati |
| [docs/roadmap.md](docs/roadmap.md) | Piani non ancora implementati |
| [docs/releasing.md](docs/releasing.md) | Come vengono fatte le release (tagpr) |

## Contribuire

Issue e pull request sono benvenute.

1. Leggi [docs/README.md](docs/README.md) prima di modificare qualsiasi comportamento.
2. Il codice è contrassegnato con `// 要件: REQ-…` (requisito) o `// 設計判断: DEC-…` (decisione di progettazione). In CI, `scripts/check-spec.py` verifica che la specifica venga aggiornata ogni volta che cambia del codice contrassegnato.
3. Una nuova funzionalità nasce come requisito in `docs/spec/`. Le idee per il futuro vanno in `docs/roadmap.md`.

## Licenza

Hanasu è source-available (con codice sorgente disponibile), non open source. © 2026 kakibara. Vedi [NOTICE](NOTICE).

- Licenza: [PolyForm Noncommercial License 1.0.0](LICENSE) più la [Hanasu Additional Permission 1.0](LICENSE-ADDITIONAL-PERMISSION.md).
- Gratuito per uso personale non commerciale, istruzione, ricerca, enti di beneficenza e pubblica amministrazione, e per il lavoro interno delle piccole imprese (meno di 100 persone e meno di US$1M di fatturato). Qualsiasi azienda può valutare Hanasu per 30 giorni.
- Le aziende più grandi, e chiunque venda Hanasu o lo integri in un prodotto o servizio, hanno bisogno di una licenza commerciale. Vedi [COMMERCIAL.md](COMMERCIAL.md).
- Le versioni pubblicate prima di questo cambio di licenza sono state pubblicate con l'Apache License 2.0 e restano sotto tale licenza.
- I contributi richiedono l'accordo descritto in [CONTRIBUTING.md](CONTRIBUTING.md).

Le licenze di terze parti sono elencate in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) (macOS) e [windows/THIRD_PARTY_NOTICES.md](windows/THIRD_PARTY_NOTICES.md) (Windows). Entrambi i file sono inclusi nei download.
