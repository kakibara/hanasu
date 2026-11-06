<div align="center">

<img src="docs/images/icon.png" width="112" alt="Icône de Hanasu">

# Hanasu

**Parlez naturellement. Obtenez un texte propre, prêt à envoyer, et des comptes rendus de réunion qui s'écrivent tout seuls.**

Une application de saisie vocale et de notes de réunion pour macOS et Windows. Elle utilise la reconnaissance vocale sur l'appareil, et Gemini, Claude ou un modèle d'IA qui tourne sur votre propre machine.

[![Release](https://img.shields.io/github/v/release/kakibara/hanasu?sort=semver&label=release)](https://github.com/kakibara/hanasu/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/kakibara/hanasu/total)](https://github.com/kakibara/hanasu/releases)
[![License](https://img.shields.io/badge/license-PolyForm%20Noncommercial%20%2B%20small%20business-blue)](COMMERCIAL.md)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-000000?logo=apple)
![Windows 10/11](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows)
[![Windows build](https://github.com/kakibara/hanasu/actions/workflows/windows.yml/badge.svg)](https://github.com/kakibara/hanasu/actions/workflows/windows.yml)

[English](README.md) · [日本語](README.ja.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [한국어](README.ko.md) · [Español](README.es.md) · **Français** · [Deutsch](README.de.md) · [Italiano](README.it.md) · [Português (Brasil)](README.pt-BR.md) · [Русский](README.ru.md) · [Türkçe](README.tr.md) · [Tiếng Việt](README.vi.md) · [Bahasa Indonesia](README.id.md) · [Polski](README.pl.md) · [العربية](README.ar.md) · [हिन्दी](README.hi.md)

<sub>Ceci est une traduction du README anglais. En cas de différence, le README anglais est le plus à jour.</sub>

<img src="docs/images/hud.png" width="560" alt="HUD d'enregistrement de Hanasu">

</div>

> [!NOTE]
> Hanasu a été conçu avant tout pour le **japonais**, et le japonais est la langue la plus testée.
> Les écrans de l'application et les instructions qu'elle donne à l'IA existent dans les 17 mêmes langues que ce README. Les écrans suivent la langue du système, et les instructions à l'IA suivent la langue de transcription choisie dans les Réglages. Pour toute autre langue, Hanasu utilise l'anglais.
> Il peut aussi traduire ce que vous dites en un **anglais** naturel (ou en **japonais**) avant de le saisir.

## Pourquoi Hanasu

La dictée intégrée vous donne une transcription brute. Elle garde les mots de remplissage et les erreurs d'homophones, n'a pas de ponctuation et inclut chaque « attends, je veux dire… ».
Hanasu envoie la transcription à une IA (Gemini, Claude ou un modèle local sur votre appareil), qui corrige ces erreurs et met le texte au propre. Hanasu saisit ensuite le résultat là où se trouve votre curseur.
Il s'inspire de Typeless, Wispr Flow, Aqua Voice et Granola. Son code source est public. Il est gratuit pour un usage personnel et pour les petites entreprises ; les entreprises plus grandes ont besoin d'une [licence commerciale](COMMERCIAL.md). Vous utilisez votre propre clé d'API Gemini ou Claude, ou vous faites tourner un modèle local, sans clé d'API et sans qu'aucun texte ne quitte votre appareil.

## Fonctionnalités

### 🎙️ Saisie vocale

| | |
| --- | --- |
| **Parlez → texte soigné** | Appuyez sur <kbd>⌥ Space</kbd>, parlez, puis appuyez à nouveau (ou cliquez sur **■ Arrêter**). Hanasu supprime les mots de remplissage, corrige les homophones, applique vos autocorrections et colle le texte au niveau du curseur. |
| **Parlez, saisissez la traduction** | Appuyez sur <kbd>⌥⇧ Space</kbd>, ou basculez le HUD sur **English** ou **日本語** pendant que vous parlez. Les formules toutes faites sont traduites naturellement : お疲れ様です devient "Hi,". Choisissez les langues proposées (anglais, japonais ou les deux) dans **Réglages → Général**. L'anglais est la valeur par défaut. |
| **Les langues mélangées restent telles quelles** | Par défaut, les passages que vous dites en anglais restent en anglais. Vous pouvez choisir d'unifier la sortie en japonais. |
| **Modifier à la voix** | Sélectionnez du texte, appuyez sur <kbd>⌃⌥⌘ E</kbd> et dites « rends-le plus poli », « transforme-le en liste à puces » ou « traduis en anglais ». |
| **Styles par application** | Le texte est décontracté et court dans Slack, poli et en paragraphes dans Mail, et dans un style écrit dans Pages, Word et Notion. Vous pouvez changer le préréglage de chaque application. |
| **Extraits** | Dites « signature d'e-mail » pour insérer un texte enregistré exactement tel que vous l'avez écrit. Les extraits ne sont jamais envoyés à l'IA. |
| **Dictionnaire** | Ajoutez des noms propres et des règles de remplacement comme `ストックマーク => Stockmark`. Sur Mac, l'IA peut aussi suggérer de nouvelles entrées à partir de votre historique et de vos réunions, et vous n'ajoutez que celles que vous choisissez. |
| **Contexte de l'écran** *(sur option)* | Hanasu lit le titre de la fenêtre et le texte autour de votre curseur, pour que les noms correspondent à ce qui est déjà à l'écran. Les champs de mot de passe ne sont jamais lus. |
| **Choisissez votre micro** *(Mac)* | Choisissez le microphone dans les Réglages, ou changez-le depuis le bouton micro du HUD sans arrêter l'enregistrement. |
| **Historique** | Recherchez dans les résultats passés et relancez ceux qui ont échoué. L'historique est conservé 30 jours par défaut, et vous pouvez changer cela dans les Réglages. Sur Mac, appuyez sur <kbd>⌥⇧ V</kbd> pour coller à nouveau le dernier résultat. |
| **Nulle part où coller ?** | Si aucun champ de texte n'a le focus (par exemple, le bureau est au premier plan), Hanasu garde le résultat à l'écran au lieu de le coller. Copiez-le depuis là, ou appuyez simplement sur <kbd>⌘V</kbd> là où vous le voulez (vous pouvez choisir si le résultat reste dans le presse-papiers). |
| **Le collage n'est pas arrivé ?** | Si le collage n'a atteint aucune application (par exemple, vous avez changé de fenêtre pendant l'enregistrement), Hanasu laisse le dernier résultat dans le presse-papiers et vous le signale dans le HUD. Appuyez sur <kbd>⌘V</kbd> là où vous le voulez. Dans Réglages → Général, vous pouvez aussi faire ouvrir l'historique de dictée quand cela arrive. |

<p align="center">
  <img src="docs/images/hud-english.png" width="420" alt="Sortie en anglais">
  <img src="docs/images/edit-mode.png" width="420" alt="Modifier à la voix">
</p>

### 📝 Notes de réunion

| | |
| --- | --- |
| **Enregistre les deux côtés** | Votre microphone est enregistré comme « vous ». La sortie audio du Mac (Zoom, Meet, Teams, huddles Slack, etc.) est enregistrée comme « eux ». Aucun bot ne rejoint l'appel. |
| **Diarisation des locuteurs** | L'autre côté est séparé en Locuteur 1, Locuteur 2, etc., sur l'appareil. Quand la conversation rend un nom évident (quelqu'un se présente, par exemple), l'IA le renseigne et l'indique comme une supposition. Vous pouvez renommer les locuteurs ensuite. |
| **Comptes rendus par IA** | Rédigés par l'IA que vous choisissez pour les réunions. Choisissez un modèle : automatique, point hebdomadaire, 1-on-1, appel commercial, brainstorming ou personnalisé. Les actions incluent un responsable et une échéance. |
| **Notes en direct et temps forts** | Saisissez des notes horodatées pendant l'appel, ou appuyez sur <kbd>⌃⌥⌘ H</kbd> pour marquer « c'est important » (annulable pendant 10 secondes). Le compte rendu donne la priorité à ces passages, et vous pouvez ensuite relire la conversation autour de chaque marque. |
| **Sous-titres flottants** *(Mac)* | Affichez la transcription en direct sous forme de sous-titres par-dessus votre application de réunion. |
| **Chat IA pendant la réunion** *(Mac)* | Pendant l'enregistrement, interrogez l'IA sur la conversation jusqu'ici (<kbd>⌘J</kbd>). Un clic suffit pour « résumé jusqu'ici » ou « décisions et tâches ». Posez des questions de suivi, et cliquez sur un horodatage dans une réponse pour aller à ce passage de la transcription. |
| **Détection des réunions** | Quand une application de réunion commence à utiliser le micro, Hanasu vous demande s'il faut enregistrer. Il ne lance jamais l'enregistrement de lui-même. |
| **Rechercher et demander** | Recherchez dans le texte de toutes les réunions, ou demandez « Qu'avons-nous décidé au point de la semaine dernière ? ». La réponse cite les réunions utilisées. |
| **Export** | Copiez en Markdown ou sous forme de résumé prêt pour Slack, enregistrez en `.md` / `.txt`, ou envoyez les actions vers Rappels. |
| **Organiser** | Renommez une réunion en modifiant son titre directement, ou supprimez une réunion dont vous n'avez plus besoin. |

<p align="center">
  <img src="docs/images/meeting-live.png" width="420" alt="Enregistrement avec notes en direct">
  <img src="docs/images/meeting-ask.png" width="420" alt="Interrogez vos réunions">
</p>
<p align="center">
  <img src="docs/images/meeting-minutes.png" width="420" alt="Compte rendu avec actions">
  <img src="docs/images/meeting-suggestion.png" width="420" alt="Détection des réunions">
</p>

### 🤖 Choisissez votre IA

Choisissez l'IA qui met votre texte au propre, séparément pour la **saisie vocale** et les **réunions**.

| IA | Modèle par défaut | Connexion |
| --- | --- | --- |
| **Gemini** (par défaut sur Windows) | saisie vocale `gemini-3.5-flash-lite`, réunions `gemini-3.8-flash` | Clé d'API Google AI Studio ou compte de service Vertex AI |
| **Claude** | saisie vocale `claude-haiku-5-5`, réunions `claude-sonnet-5-5` (Opus 5.5 également disponible) | Clé d'API Anthropic |
| **Local** (sur votre appareil, par défaut sur Mac) | Gemma 4 E4B (recommandé). Voir le tableau ci-dessous | Aucune. Téléchargez le modèle dans **Réglages → IA**. Sur Mac, si le modèle est absent quand Hanasu commence à mettre le texte au propre, il vous demande s'il faut le télécharger |
| **Apple** *(Mac, macOS 27)* | Le modèle Apple Intelligence sur l'appareil, via la commande `fm` | Aucune |

Ces IA ne traitent que du texte. La parole est transcrite par le moteur ci-dessous.

#### 💻 Modèles locaux

Avec **Local**, Hanasu fait tourner un petit modèle de langage sur votre propre Mac ou PC grâce à [llama.cpp](https://github.com/ggml-org/llama.cpp), fourni avec l'application, si bien que votre texte ne quitte jamais l'appareil. Le Mac utilise le GPU (Metal), et Windows le CPU. Vous téléchargez un modèle une seule fois depuis **Réglages → IA**. Hanasu vérifie sa taille et son SHA-256 avant de l'utiliser.

| Modèle | Taille | Licence | Remarques |
| --- | --- | --- | --- |
| **Gemma 4 E4B** (Google) — **recommandé** | 4,59 Go | Apache-2.0 | Les résultats les plus naturels, aussi bien pour la mise au propre que pour les comptes rendus. 16 Go de mémoire ou plus sont recommandés. Modèle par défaut pour la saisie vocale comme pour les réunions |
| LFM2.5-1.2B-JP (Liquid AI) | 1,25 Go | LFM Open License v1.0 | Petit et rapide. Selon cette licence, les organisations dont le chiffre d'affaires annuel atteint 10 M$ US ou plus ne peuvent pas l'utiliser commercialement |
| Sarashina2.2 3B (SB Intuitions) | 2,07 Go | MIT | Entraîné sur du japonais. Son contexte est de 8K, donc les longues réunions sont résumées par morceaux |
| Qwen3.5-4B (Alibaba) | 2,74 Go | Apache-2.0 | Environ deux fois plus petit que Gemma, il tourne donc plus facilement avec 8 Go de mémoire. Moins bon que Gemma pour gérer les autocorrections |

> [!TIP]
> Nous recommandons **Gemma 4 E4B**. Lors de nos tests, les autres modèles conservaient parfois les mots que vous vouliez retirer, ajoutaient des phrases que vous n'aviez pas dites, se trompaient de responsable pour une action, ou fusionnaient ou oubliaient des actions. Gemma 4 E4B a géré de façon fiable la mise au propre comme les comptes rendus.

### 🔊 Choisissez votre moteur de reconnaissance vocale

| Moteur | Où il tourne | Transcription en direct | Remarques |
| --- | --- | --- | --- |
| **Standard du système** (par défaut) | Mac : `SpeechAnalyzer` · Windows : `Windows.Media.SpeechRecognition` | ✅ | Sur l'appareil sur Mac |
| **Whisper** | Sur l'appareil (WhisperKit sur Mac, whisper.cpp sur Windows) | — (après l'arrêt) | Le modèle est téléchargé quand vous le sélectionnez |
| **Gemini** | Google | — (après l'arrêt) | L'audio enregistré est envoyé à Google |

Vous pouvez choisir un moteur différent pour la saisie vocale et pour les réunions. Sur Windows, les réunions utilisent Whisper ou Gemini.
Sur Mac, choisissez la langue de transcription dans une liste (japonais, anglais, chinois, coréen, français, allemand, espagnol, italien, portugais). Elle correspond au départ à la langue de votre système.

## Téléchargement

Récupérez la dernière version depuis les [**Releases**](https://github.com/kakibara/hanasu/releases/latest).

| Plateforme | Fichier | Configuration requise |
| --- | --- | --- |
| macOS | `Hanasu-<version>-macOS.zip` | macOS 26 (Tahoe) ou ultérieur, Apple Silicon |
| Windows | `Hanasu-<version>-Windows-x64.zip` | Windows 10 (2004 ou ultérieur) / 11, x64 |

<details>
<summary><b>macOS : premier lancement</b></summary>

1. Décompressez le fichier et déplacez `Hanasu.app` dans **Applications**.
2. L'application est auto-signée et non notarisée, donc macOS la bloque la première fois. Cliquez sur **OK**, puis ouvrez **Réglages Système → Confidentialité et sécurité** et cliquez sur **Ouvrir quand même**.
   Vous pouvez aussi exécuter `xattr -dr com.apple.quarantine /Applications/Hanasu.app` à la place.
3. Quand on vous le demande, autorisez **Microphone**, **Reconnaissance vocale** et **Accessibilité**. L'accessibilité est nécessaire pour coller avec ⌘V.

</details>

<details>
<summary><b>Windows : premier lancement</b></summary>

1. Décompressez le fichier, placez le dossier `Hanasu` où vous voulez (par exemple `%LOCALAPPDATA%\Programs`) et lancez `Hanasu.exe`.
2. L'application n'est pas signée, donc SmartScreen affiche un avertissement. Cliquez sur **Informations complémentaires → Exécuter quand même**.
3. Le moteur de reconnaissance vocale de Windows nécessite d'activer la **Reconnaissance vocale en ligne** dans les paramètres de Windows. Hanasu vous prévient si elle est désactivée.

Consultez [windows/README.md](windows/README.md) pour plus de détails et pour les différences entre la version Windows et la version Mac.

</details>

Quand une nouvelle version sort, Hanasu vous prévient au lancement et vous pose la question avant de se mettre à jour. Vous pouvez aussi choisir **アップデートを確認…** (Rechercher les mises à jour) dans le menu (la vérification au lancement peut être désactivée dans **Réglages → Général**). Les versions jusqu'à la v1.5.0 n'ont pas encore cette fonction : mettez-les donc à jour à la main une fois.

## Démarrage rapide

Sur Mac, le premier lancement ouvre une courte visite guidée. Elle vous permet de choisir votre IA (Gemma 4 E4B, le modèle local recommandé, se télécharge directement), présente les principales fonctionnalités et des conseils de réglage, et demande les autorisations dont Hanasu a besoin. Rouvrez-la à tout moment via **Comment utiliser Hanasu…** dans le menu.

1. **Choisissez une IA.** Ouvrez **Réglages → IA** et choisissez une IA pour la saisie vocale et pour les réunions. Pour Gemini, collez une clé d'API depuis [Google AI Studio](https://aistudio.google.com/apikey) ou sélectionnez un fichier JSON de compte de service Vertex AI. Pour Claude, collez une clé d'API depuis la [Claude Console](https://console.anthropic.com/settings/keys). Pour Local, téléchargez un modèle (Gemma 4 E4B est recommandé). Aucune clé n'est nécessaire. Cliquez sur le bouton de test pour vérifier que tout fonctionne.
2. **Dictez.** Placez le curseur là où vous voulez le texte, appuyez sur le raccourci, parlez, puis appuyez à nouveau sur le raccourci.
3. **Enregistrez une réunion.** Utilisez le menu de la barre des menus (Mac) ou de la zone de notification (Windows), ou le raccourci. Un casque aide à bien séparer les deux côtés.

Sur Mac, vous pouvez afficher l'icône de Hanasu dans la barre des menus, dans le Dock, ou dans les deux (Réglages → Général).

### Raccourcis par défaut

| Action | macOS | Windows |
| --- | --- | --- |
| Saisie vocale (démarrer / arrêter) | <kbd>⌥ Space</kbd> | <kbd>Ctrl Alt Space</kbd> |
| Saisie vocale traduite (anglais / japonais) | <kbd>⌥⇧ Space</kbd> | <kbd>Ctrl Alt Shift Space</kbd> |
| Modifier la sélection à la voix | <kbd>⌃⌥⌘ E</kbd> | — |
| Coller à nouveau le dernier résultat | <kbd>⌥⇧ V</kbd> | — |
| Annuler l'enregistrement | <kbd>Esc</kbd> | <kbd>Esc</kbd> |
| Enregistrement de réunion (démarrer / arrêter) | <kbd>⌃⌥⌘ M</kbd> | <kbd>Ctrl Alt Shift M</kbd> |
| Marquer « c'est important » en réunion | <kbd>⌃⌥⌘ H</kbd> | <kbd>Ctrl Alt Shift H</kbd> |

Vous pouvez modifier chaque raccourci dans les Réglages. Le guide d'utilisation complet (en japonais) se trouve dans [docs/guide.md](docs/guide.md).

## Confidentialité

- **L'audio reste sur votre appareil par défaut.** La reconnaissance vocale, Whisper et la diarisation des locuteurs tournent tous en local.
- **L'IA reçoit du texte, pas de l'audio.** Gemini ou Claude reçoit la transcription. Selon vos réglages, il peut aussi recevoir le nom de l'application dans laquelle vous saisissez, le contexte de l'écran et les transcriptions de réunion pour les questions et pour le chat IA de la réunion.
- **Local et Apple gardent aussi le texte sur votre appareil.** Si vous choisissez l'un des deux, rien n'est envoyé à un service d'IA. Le seul téléchargement est le modèle lui-même.
- **L'audio n'est envoyé à Google que si vous le choisissez.** Si vous sélectionnez le moteur de reconnaissance vocale Gemini, l'audio enregistré est envoyé à Google.
- **Les réunions sont de simples fichiers.** Elles sont enregistrées en JSON et en Markdown dans `~/Documents/Hanasu/Meetings/` (Windows : `Documents\Hanasu\Meetings\`). Mac et Windows utilisent le même format.
- **Aucune télémétrie.** Hanasu ne collecte aucune donnée d'analyse.
- **Les clés d'API sont protégées par le système.** Sur macOS, elles sont conservées dans le Keychain, et les autres applications doivent demander votre mot de passe de session pour les lire. Sur Windows, elles sont chiffrées avec DPAPI, ou avec une clé Windows Hello si vous le choisissez. Aucun des deux ne peut totalement empêcher un logiciel malveillant exécuté sous votre compte. Voir [docs/design/security.md](docs/design/security.md).

> [!IMPORTANT]
> Obtenez le consentement de tous les participants avant d'enregistrer une réunion. Respectez les règles de votre organisation concernant l'enregistrement et l'utilisation des services d'IA.

## Compiler depuis les sources

<details>
<summary><b>macOS</b> (Xcode Command Line Tools, Swift 6.2)</summary>

```bash
./scripts/build-app.sh             # compile build/Hanasu.app
open build/Hanasu.app
./scripts/create-signing-cert.sh   # facultatif : conserve les autorisations d'une compilation à l'autre
```

</details>

<details>
<summary><b>Windows</b> (.NET 8 SDK)</summary>

```bash
cd windows
dotnet build Hanasu.Windows.sln
dotnet publish Hanasu.Windows/Hanasu.Windows.csproj -c Release -r win-x64 --self-contained -p:PublishSingleFile=true -o publish/win-x64
```

Voir [windows/README.md](windows/README.md).

</details>

## Documentation

La documentation est rédigée en japonais.

| | |
| --- | --- |
| [docs/guide.md](docs/guide.md) | Guide d'utilisation : prise en main, réglages, règles du dictionnaire |
| [docs/spec/](docs/spec/) | Exigences implémentées (`REQ-*`) et décisions de conception (`DEC-*`) |
| [docs/design/](docs/design/) | Comment c'est construit : architecture et flux de données |
| [docs/roadmap.md](docs/roadmap.md) | Projets pas encore implémentés |
| [docs/releasing.md](docs/releasing.md) | Comment les versions sont publiées (tagpr) |

## Contribuer

Les issues et les pull requests sont les bienvenues.

1. Lisez [docs/README.md](docs/README.md) avant de modifier un comportement.
2. Le code est balisé avec `// 要件: REQ-…` (exigence) ou `// 設計判断: DEC-…` (décision de conception). En CI, `scripts/check-spec.py` vérifie que la spécification est mise à jour chaque fois que du code balisé change.
3. Une nouvelle fonctionnalité commence par une exigence dans `docs/spec/`. Les idées pour plus tard vont dans `docs/roadmap.md`.

## Licence

Hanasu est à source disponible (source-available), et non open source. © 2026 kakibara. Voir [NOTICE](NOTICE).

- Licence : [PolyForm Noncommercial License 1.0.0](LICENSE) plus la [Hanasu Additional Permission 1.0](LICENSE-ADDITIONAL-PERMISSION.md).
- Gratuit pour un usage personnel non commercial, l'enseignement, la recherche, les organisations caritatives et les administrations publiques, ainsi que pour le travail interne des petites entreprises (moins de 100 personnes et moins de US$1M de chiffre d'affaires). Toute entreprise peut évaluer Hanasu pendant 30 jours.
- Les entreprises plus grandes, ainsi que quiconque vend Hanasu ou l'intègre à un produit ou à un service, ont besoin d'une licence commerciale. Voir [COMMERCIAL.md](COMMERCIAL.md).
- Les versions publiées avant ce changement de licence ont été publiées sous l'Apache License 2.0 et restent sous cette licence.
- Les contributions nécessitent l'accord décrit dans [CONTRIBUTING.md](CONTRIBUTING.md).

Les licences tierces sont listées dans [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) (macOS) et [windows/THIRD_PARTY_NOTICES.md](windows/THIRD_PARTY_NOTICES.md) (Windows). Les deux fichiers sont inclus dans les téléchargements.
