<div align="center">

<img src="docs/images/icon.png" width="112" alt="Icono de Hanasu">

# Hanasu

**Habla con naturalidad. Obtén texto limpio y listo para enviar, y actas de reuniones que se escriben solas.**

Una app de dictado por voz y notas de reuniones para macOS y Windows. Usa reconocimiento de voz en el dispositivo y Gemini, Claude o un modelo de IA que se ejecuta en tu propio equipo.

[![Release](https://img.shields.io/github/v/release/kakibara/hanasu?sort=semver&label=release)](https://github.com/kakibara/hanasu/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/kakibara/hanasu/total)](https://github.com/kakibara/hanasu/releases)
[![License](https://img.shields.io/badge/license-PolyForm%20Noncommercial%20%2B%20small%20business-blue)](COMMERCIAL.md)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-000000?logo=apple)
![Windows 10/11](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows)
[![Windows build](https://github.com/kakibara/hanasu/actions/workflows/windows.yml/badge.svg)](https://github.com/kakibara/hanasu/actions/workflows/windows.yml)

[English](README.md) · [日本語](README.ja.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [한국어](README.ko.md) · **Español** · [Français](README.fr.md) · [Deutsch](README.de.md) · [Italiano](README.it.md) · [Português (Brasil)](README.pt-BR.md) · [Русский](README.ru.md) · [Türkçe](README.tr.md) · [Tiếng Việt](README.vi.md) · [Bahasa Indonesia](README.id.md) · [Polski](README.pl.md) · [العربية](README.ar.md) · [हिन्दी](README.hi.md)

<sub>Esta es una traducción del README en inglés. Si difieren, el README en inglés es el más actualizado.</sub>

<img src="docs/images/hud.png" width="560" alt="HUD de grabación de Hanasu">

</div>

> [!NOTE]
> Hanasu se hizo ante todo para el **japonés**, y el japonés es el idioma más probado.
> Las pantallas de la app y las instrucciones que da a la IA están en los mismos 17 idiomas que este README. Las pantallas siguen el idioma del sistema, y las instrucciones para la IA siguen el idioma de transcripción de los Ajustes. Para cualquier otro idioma, Hanasu usa el inglés.
> También puede traducir lo que dices a un **inglés** natural, al **japonés** o a cualquiera de los 17 idiomas compatibles antes de escribirlo.

## Por qué Hanasu

El dictado integrado te da una transcripción en bruto. Conserva las muletillas y los errores de homófonos, no tiene puntuación e incluye cada «espera, quiero decir…».
Hanasu envía la transcripción a una IA (Gemini, Claude o un modelo local en tu dispositivo), que corrige esos errores y pule el texto. Después, Hanasu escribe el resultado donde está tu cursor.
Está inspirado en Typeless, Wispr Flow, Aqua Voice y Granola. Su código fuente es público. Es gratuito para uso personal y para pequeñas empresas; las empresas más grandes necesitan una [licencia comercial](COMMERCIAL.md). Usas tu propia clave de API de Gemini o Claude, o ejecutas un modelo local sin clave de API y sin que ningún texto salga de tu dispositivo.

## Funciones

### 🎙️ Dictado por voz

| | |
| --- | --- |
| **Habla → texto pulido** | Pulsa <kbd>⌥ Space</kbd>, habla y vuelve a pulsarlo (o haz clic en **■ Listo**). Hanasu quita las muletillas, corrige los homófonos, aplica tus autocorrecciones y pega el texto en el cursor. |
| **Habla y escríbelo traducido** | Pulsa <kbd>⌥⇧ Space</kbd>, o cambia el HUD a **English**, **日本語** u otro idioma mientras hablas. Las frases hechas se traducen con naturalidad, así que お疲れ様です se convierte en "Hi,". Elige los idiomas que se ofrecen (cualquiera de los 17 idiomas compatibles) en **Ajustes → General**. El inglés es el predeterminado. En Mac, **Ajustes → Por app** permite que una app empiece en uno de esos idiomas. |
| **Los idiomas mezclados se quedan como los dijiste** | De forma predeterminada, las partes que dices en inglés se quedan en inglés. Puedes optar por unificar la salida en japonés. |
| **Edita con la voz** | Selecciona un texto, pulsa <kbd>⌃⌥⌘ E</kbd> y di «hazlo más cortés», «conviértelo en viñetas» o «tradúcelo al inglés». |
| **Estilos por app** | El texto es informal y breve en Slack, cortés y con párrafos en Mail, y en estilo escrito en Pages, Word y Notion. Puedes cambiar el preajuste de cada app o hacer que la IA aprenda un estilo personalizado a partir de tus propios textos (pégalos o elige un archivo de Word, de texto o Markdown). |
| **Fragmentos** | Di «firma de correo» para insertar un texto guardado tal como lo escribiste. Los fragmentos nunca se envían a la IA. |
| **Diccionario** | Añade nombres propios y reglas de sustitución como `ストックマーク => Stockmark`. Las reglas también se aplican a las transcripciones de las reuniones. Desde una reunión en Notas de reuniones, la IA puede sugerir entradas nuevas a partir de esa reunión (en Mac, también de tu historial y tus reuniones recientes), y solo añades las que elijas. |
| **Contexto de pantalla** *(opcional)* | Hanasu lee el título de la ventana y el texto alrededor del cursor, para que los nombres coincidan con lo que ya está en pantalla. Los campos de contraseña nunca se leen. |
| **Texto de capturas de pantalla** *(opcional, Mac)* | Hanasu hace una captura de todas tus pantallas, lee el texto en tu Mac y solo pasa ese texto a la IA, así que los nombres y números de modelo de otras ventanas (por ejemplo, "QX-7s") se escriben tal como aparecen. La imagen nunca se envía ni se guarda. Actívalo o desactívalo para una sola grabación con el botón del HUD. Necesita el permiso de Grabación de pantalla. |
| **Elige tu micrófono** *(Mac)* | Elige el micrófono en Ajustes, o cámbialo desde el botón de micrófono del HUD sin detener la grabación. |
| **Historial** | Busca resultados anteriores y reintenta los que fallaron. El historial se guarda 30 días de forma predeterminada, y puedes cambiarlo en Ajustes. En Mac, pulsa <kbd>⌥⇧ V</kbd> para volver a pegar el último resultado. |
| **¿No hay dónde pegar?** | Si ningún campo de texto tiene el foco (por ejemplo, el escritorio está delante), Hanasu deja el resultado en pantalla en lugar de pegarlo. Cópialo desde ahí o simplemente pulsa <kbd>⌘V</kbd> donde lo quieras (puedes elegir si el resultado se queda en el portapapeles). |
| **¿El pegado no llegó?** | Si el pegado nunca llegó a una app (por ejemplo, cambiaste de ventana mientras grababas), Hanasu deja el último resultado en el portapapeles y te avisa en el HUD. Pulsa <kbd>⌘V</kbd> donde lo quieras. En Ajustes → General también puedes hacer que se abra el historial de dictado cuando esto ocurra. |

<p align="center">
  <img src="docs/images/hud-english.png" width="420" alt="Salida en inglés">
  <img src="docs/images/edit-mode.png" width="420" alt="Editar con la voz">
</p>

### 📝 Notas de reuniones

| | |
| --- | --- |
| **Graba ambos lados** | Tu micrófono se graba como «tú». La salida de audio del Mac (Zoom, Meet, Teams, huddles de Slack, etc.) se graba como «ellos». Ningún bot se une a la llamada. |
| **Diarización de hablantes** | El otro lado se separa en Hablante 1, Hablante 2, etc., en el dispositivo. Cuando la conversación deja claro un nombre (por ejemplo, alguien se presenta), la IA lo completa y lo marca como suposición. Puedes renombrar a los hablantes después. |
| **Actas con IA** | Las genera la IA que elijas para las reuniones. Elige una plantilla: automática, reunión semanal, 1-on-1, llamada de ventas, lluvia de ideas o personalizada. Las tareas incluyen un responsable y una fecha límite. |
| **Comprueba el origen y vuelve a escuchar** *(Mac)* | El acta se abre en una sola página: primero el resumen y las tareas, con la transcripción al lado. Haz clic en la marca de tiempo al final de un punto para saltar a la intervención de la que salió. Reproduce la grabación desde cualquier intervención y silencia tu lado o el de ellos si la llamada tenía eco. |
| **Notas en vivo y destacados** | Escribe notas con marca de tiempo durante la llamada, o pulsa <kbd>⌃⌥⌘ H</kbd> para marcar «esto importa» (puedes deshacerlo durante 10 segundos). Las actas dan prioridad a esas partes y, después, puedes leer la conversación alrededor de cada marca. |
| **Subtítulos flotantes** *(Mac)* | Muestra la transcripción en vivo como subtítulos encima de tu app de reuniones. Si los dejas activados, vuelven a aparecer en la siguiente reunión. |
| **Chat con IA durante la reunión** *(Mac)* | Mientras grabas, pregunta a la IA sobre la conversación hasta ahora (<kbd>⌘J</kbd>). Con un clic obtienes «resumen hasta ahora» o «decisiones y tareas». Haz preguntas de seguimiento y haz clic en una marca de tiempo de una respuesta para saltar a esa parte de la transcripción. ¿Te hacen una pregunta de repente mientras estabas en otra cosa? Sin salir de tu app de reuniones, pulsa «¿Qué me preguntaron?» en los subtítulos (o <kbd>⌃⌥⌘ A</kbd>): un panel flotante muestra lo último que dijeron los demás y, después, el resumen de la IA con la pregunta y el contexto que llevó a ella. Cambia la IA y el modelo de esa conversación desde el menú que hay bajo el cuadro de texto. |
| **Detección de reuniones** | Cuando una app de reuniones empieza a usar el micrófono, Hanasu pregunta si quieres grabar. Nunca empieza a grabar por su cuenta. |
| **Buscar y preguntar** | Busca en el texto de todas las reuniones, o pregunta «¿Qué decidimos en la reunión de la semana pasada?». La respuesta cita las reuniones que usó. |
| **Exportar** | Copia como Markdown o como un resumen listo para Slack, guarda como `.md` / `.txt`, o envía las tareas a Recordatorios. |
| **Organizar** | Renombra una reunión editando su título en el sitio, o elimina una reunión que ya no necesites. |

<p align="center">
  <img src="docs/images/meeting-live.png" width="420" alt="Grabación con notas en vivo">
  <img src="docs/images/meeting-ask.png" width="420" alt="Pregunta a tus reuniones">
</p>
<p align="center">
  <img src="docs/images/meeting-minutes.png" width="420" alt="Actas con tareas">
  <img src="docs/images/meeting-suggestion.png" width="420" alt="Detección de reuniones">
</p>

### 🤖 Elige tu IA

Elige la IA que pule tu texto, por separado para el **dictado por voz** y las **reuniones** (actas). En el Mac, también eliges una para **Chat con IA y preguntas** (el chat con IA de las reuniones y las preguntas sobre reuniones pasadas).

| IA | Modelo predeterminado | Inicio de sesión |
| --- | --- | --- |
| **Gemini** (predeterminada en Windows) | dictado por voz `gemini-3.5-flash-lite`, reuniones y «Chat con IA y preguntas» `gemini-3.8-flash` | Clave de API de Google AI Studio o cuenta de servicio de Vertex AI |
| **Claude** | dictado por voz y «Chat con IA y preguntas» `claude-haiku-5-5`, reuniones `claude-sonnet-5-5` (también Opus 5.5) | Clave de API de Anthropic |
| **Local** (en tu dispositivo; predeterminada en Mac) | Gemma 4 E4B (recomendado). Consulta la tabla de abajo | Ninguno. Descarga el modelo en **Ajustes → IA**. En Mac, si falta el modelo cuando Hanasu empieza a pulir el texto, te pregunta si quieres descargarlo |
| **Apple** *(Mac, macOS 27)* | El modelo de Apple Intelligence en el dispositivo, mediante el comando `fm` | Ninguno |

Estas IA solo manejan texto. La voz la transcribe el motor que se describe abajo.

#### 💻 Modelos locales

Con **Local**, Hanasu ejecuta un modelo de lenguaje pequeño en tu propio Mac o PC con [llama.cpp](https://github.com/ggml-org/llama.cpp) incluido, así que tu texto nunca sale del dispositivo. El Mac usa la GPU (Metal) y Windows usa la CPU. Descargas un modelo una sola vez desde **Ajustes → IA**. Hanasu comprueba su tamaño y su SHA-256 antes de usarlo.

| Modelo | Tamaño | Licencia | Notas |
| --- | --- | --- | --- |
| **Gemma 4 E4B** (Google) — **recomendado** | 4,59 GB | Apache-2.0 | Los resultados más naturales tanto para el pulido como para las actas. Se recomiendan 16 GB de memoria o más. El predeterminado para el dictado por voz y las reuniones |
| LFM2.5-1.2B-JP (Liquid AI) | 1,25 GB | LFM Open License v1.0 | Pequeño y rápido. Según esta licencia, las organizaciones con ingresos anuales de 10 M US$ o más no pueden usarlo comercialmente |
| Sarashina2.2 3B (SB Intuitions) | 2,07 GB | MIT | Entrenado en japonés. Su contexto es de 8K, así que las reuniones largas se resumen por partes |
| Qwen3.5-4B (Alibaba) | 2,74 GB | Apache-2.0 | Aproximadamente la mitad de tamaño que Gemma, así que es más fácil de ejecutar con 8 GB de memoria. Peor que Gemma con las autocorrecciones |

> [!TIP]
> Recomendamos **Gemma 4 E4B**. En nuestras pruebas, los otros modelos a veces conservaban las palabras que querías retirar, añadían frases que no dijiste, confundían al responsable de una tarea, o fusionaban u omitían tareas. Gemma 4 E4B manejó con fiabilidad tanto el pulido como las actas.

### 🔊 Elige tu motor de voz

| Motor | Dónde se ejecuta | Transcripción en vivo | Notas |
| --- | --- | --- | --- |
| **Estándar del SO** (predeterminado) | Mac: `SpeechAnalyzer` · Windows: `Windows.Media.SpeechRecognition` | ✅ | En el dispositivo en Mac |
| **Whisper** | En el dispositivo (WhisperKit en Mac, whisper.cpp en Windows) | — (al detener) | El modelo se descarga al seleccionarlo |
| **Gemini** | Google | — (al detener) | El audio grabado se envía a Google |

Puedes elegir un motor distinto para el dictado por voz y para las reuniones. En Windows, las reuniones usan Whisper o Gemini.
En Mac, elige el idioma de transcripción de una lista (japonés, inglés, chino, coreano, francés, alemán, español, italiano, portugués). Empieza con el idioma de tu sistema.

### ⌨️ Úsalo desde la terminal y agentes de IA

El comando `hanasu` permite que scripts y agentes de IA (Claude Code, Claude Desktop y otros) lean tus grabaciones de reuniones y pulan texto igual que el dictado por voz. Viene con la app, así que no hay que instalar nada más: en el Mac es la propia app, y en Windows es `cli\hanasu.exe`, dentro de la carpeta de Hanasu. Abre **Ajustes → Comando y MCP** para conectarlo a Claude Desktop, ChatGPT (Codex) o Claude Code con un clic, añadirlo a tu PATH o copiar la configuración de MCP para otras apps. (Por ahora, el chat normal de ChatGPT no puede usar herramientas MCP locales por un error de OpenAI; Codex sí puede).

| | |
| --- | --- |
| **Leer reuniones** | `hanasu meetings list / show / search` y `hanasu actions` muestran reuniones, actas, transcripciones y tareas, como texto o en `--json`. No se envía nada a ningún sitio. |
| **Preguntar** | `hanasu ask "¿Qué decidimos la semana pasada?"` responde a partir de tus reuniones. En el Mac usa la IA que elegiste para **Chat con IA y preguntas** (o la de las reuniones si no has elegido ninguna); en Windows, la de las reuniones. |
| **Pulir texto** | `hanasu refine` pule o traduce texto igual que el dictado por voz, y `hanasu edit "<instrucción>"` lo reescribe. Los dos funcionan en tuberías (pipes). `--app` elige el estilo de una app (un bundle ID en el Mac, o el nombre de un ejecutable como `slack.exe` en Windows). |
| **MCP para agentes de IA** | `hanasu mcp` es un servidor MCP (stdio). Los agentes pueden listar, leer y buscar tus reuniones, y hacer preguntas sobre ellas. El contenido de las reuniones que compartes así llega al agente y al proveedor de su IA. |
| **Comprobar la configuración** | `hanasu doctor` muestra qué IA y qué credenciales se usan, la carpeta de reuniones y cómo registrar MCP. Ejecuta `hanasu help` para ver todas las opciones. |

En Windows, ejecuta `[Console]::OutputEncoding = [Text.UTF8Encoding]::new()` antes de leer la salida en PowerShell. Si tus claves de API están protegidas con Windows Hello, se te pedirá confirmación cada vez que un comando las use.

En el Mac, los administradores pueden desactivar el comando, MCP o algunas IA con un perfil de configuración.

## Descarga

Consigue la última versión en [**Releases**](https://github.com/kakibara/hanasu/releases/latest).

| Plataforma | Archivo | Requisitos |
| --- | --- | --- |
| macOS | `Hanasu-<version>-macOS.zip` | macOS 26 (Tahoe) o posterior, Apple Silicon |
| Windows | `Hanasu-<version>-Windows-x64.zip` | Windows 10 (2004 o posterior) / 11, x64 |

<details>
<summary><b>macOS: primer inicio</b></summary>

1. Descomprime el archivo y mueve `Hanasu.app` a **Aplicaciones**.
2. La app está autofirmada y no notarizada, así que macOS la bloquea la primera vez. Haz clic en **Aceptar**, luego abre **Ajustes del Sistema → Privacidad y seguridad** y haz clic en **Abrir igualmente**.
   También puedes ejecutar `xattr -dr com.apple.quarantine /Applications/Hanasu.app` en su lugar.
3. Cuando se te pida, permite **Micrófono**, **Reconocimiento de voz** y **Accesibilidad**. La accesibilidad es necesaria para pegar con ⌘V. **Grabación de pantalla** solo se pide si activas el texto de capturas de pantalla.

</details>

<details>
<summary><b>Windows: primer inicio</b></summary>

1. Descomprime el archivo, coloca la carpeta `Hanasu` en cualquier lugar (por ejemplo `%LOCALAPPDATA%\Programs`) y ejecuta `Hanasu.exe`.
2. La app no tiene firma de código, así que SmartScreen muestra una advertencia. Haz clic en **Más información → Ejecutar de todas formas**.
3. El motor de voz de Windows necesita tener activado el **Reconocimiento de voz en línea** en la configuración de Windows. Hanasu te avisa si está desactivado.

Consulta [windows/README.md](windows/README.md) para más notas y para ver en qué se diferencia la versión de Windows de la de Mac.

</details>

Cuando se publica una versión nueva, Hanasu te avisa al iniciarse y te pregunta antes de actualizarse. También puedes elegir **アップデートを確認…** (Buscar actualizaciones) en el menú (la comprobación al iniciar se puede desactivar en **Ajustes → General**). Las versiones hasta la v1.5.0 aún no tienen esta función, así que actualízalas a mano una vez.

## Inicio rápido

En Mac, el primer inicio abre un breve recorrido guiado. Te permite elegir tu IA (Gemma 4 E4B, el modelo local recomendado, se descarga ahí mismo), muestra las funciones principales y consejos de configuración, y pide los permisos que Hanasu necesita. Vuelve a abrirlo cuando quieras desde **Cómo usar Hanasu…** en el menú.

1. **Elige una IA.** Abre **Ajustes → IA** y elige una IA para el dictado por voz y para las reuniones (en el Mac, también para «Chat con IA y preguntas»). Para Gemini, pega una clave de API de [Google AI Studio](https://aistudio.google.com/apikey) o selecciona un archivo JSON de cuenta de servicio de Vertex AI. Para Claude, pega una clave de API de la [Claude Console](https://console.anthropic.com/settings/keys). Para Local, descarga un modelo (se recomienda Gemma 4 E4B). No hace falta ninguna clave. Haz clic en el botón de prueba para comprobar que funciona.
2. **Dicta.** Coloca el cursor donde quieras el texto, pulsa el atajo, habla y vuelve a pulsar el atajo.
3. **Graba una reunión.** Usa el menú de la barra de menús (Mac) o de la bandeja (Windows), o el atajo. Los auriculares ayudan a mantener separados los dos lados.

En Mac, el icono de Hanasu está siempre en el Dock y también puedes mostrarlo en la barra de menús (Ajustes → General). Hacer clic en el icono del Dock no abre los ajustes: ábrelos desde el icono de la barra de menús o desde el menú de clic derecho del icono del Dock.

### Atajos predeterminados

| Acción | macOS | Windows |
| --- | --- | --- |
| Dictado por voz (iniciar / detener) | <kbd>⌥ Space</kbd> | <kbd>Ctrl Alt Space</kbd> |
| Dictado por voz traducido (a los idiomas que elegiste) | <kbd>⌥⇧ Space</kbd> | <kbd>Ctrl Alt Shift Space</kbd> |
| Editar la selección con la voz | <kbd>⌃⌥⌘ E</kbd> | — |
| Volver a pegar el último resultado | <kbd>⌥⇧ V</kbd> | — |
| Cancelar la grabación | <kbd>Esc</kbd> | <kbd>Esc</kbd> |
| Grabación de reunión (iniciar / detener) | <kbd>⌃⌥⌘ M</kbd> | <kbd>Ctrl Alt Shift M</kbd> |
| Marcar «esto importa» en una reunión | <kbd>⌃⌥⌘ H</kbd> | <kbd>Ctrl Alt Shift H</kbd> |
| «¿Qué me preguntaron?» en una reunión | <kbd>⌃⌥⌘ A</kbd> | — |

Puedes cambiar todos los atajos en Ajustes. La guía de usuario completa (en japonés) es [docs/guide.md](docs/guide.md).

## Privacidad

- **El audio se queda en tu dispositivo de forma predeterminada.** El reconocimiento de voz, Whisper y la diarización de hablantes se ejecutan localmente.
- **La IA recibe texto, no audio.** Gemini o Claude reciben la transcripción. Según tu configuración, también pueden recibir el nombre de la app en la que escribes, el contexto de pantalla, el texto leído de una captura de tu pantalla (nunca la imagen) y las transcripciones de reuniones para preguntar y para el chat con IA de la reunión.
- **Local y Apple también mantienen el texto en tu dispositivo.** Si eliges cualquiera de los dos, no se envía nada a ningún servicio de IA. Lo único que se descarga es el propio modelo.
- **El audio va a Google solo si así lo eliges.** Si seleccionas el motor de voz Gemini, el audio grabado se envía a Google.
- **Los agentes solo reciben reuniones si los conectas.** El comando `hanasu` y su servidor MCP solo leen reuniones cuando los llamas tú o los llama un agente, y lo que devuelven llega a ese agente y al proveedor de su IA.
- **Las reuniones son archivos normales.** Se guardan como JSON y Markdown en `~/Documents/Hanasu/Meetings/` (Windows: `Documents\Hanasu\Meetings\`). Mac y Windows usan el mismo formato.
- **Sin telemetría.** Hanasu no recopila analíticas.
- **Las claves de API están protegidas por el SO.** En macOS se guardan en el Keychain, y otras apps deben pedir tu contraseña de inicio de sesión para leerlas. En Windows se cifran con DPAPI o, si lo eliges, con una clave de Windows Hello. Ninguno de los dos puede detener por completo el malware que se ejecuta con tu usuario. Consulta [docs/design/security.md](docs/design/security.md).

> [!IMPORTANT]
> Obtén el consentimiento de todos los participantes de la reunión antes de grabar. Sigue las normas de tu organización sobre la grabación y el uso de servicios de IA.

## Compilar desde el código fuente

<details>
<summary><b>macOS</b> (Xcode Command Line Tools, Swift 6.2)</summary>

```bash
./scripts/build-app.sh             # compila build/Hanasu.app
open build/Hanasu.app
./scripts/create-signing-cert.sh   # opcional: conserva los permisos entre compilaciones
```

</details>

<details>
<summary><b>Windows</b> (.NET 8 SDK)</summary>

```bash
cd windows
dotnet build Hanasu.Windows.sln
dotnet publish Hanasu.Windows/Hanasu.Windows.csproj -c Release -r win-x64 --self-contained -p:PublishSingleFile=true -o publish/win-x64
```

Consulta [windows/README.md](windows/README.md).

</details>

## Documentación

La documentación está escrita en japonés.

| | |
| --- | --- |
| [docs/guide.md](docs/guide.md) | Guía de usuario: cómo usarlo, ajustes, reglas del diccionario |
| [docs/spec/](docs/spec/) | Requisitos implementados (`REQ-*`) y decisiones de diseño (`DEC-*`) |
| [docs/design/](docs/design/) | Cómo está construido: arquitectura y flujo de datos |
| [docs/roadmap.md](docs/roadmap.md) | Planes que aún no están implementados |
| [docs/releasing.md](docs/releasing.md) | Cómo se publican las versiones (tagpr) |

## Contribuir

Los issues y las pull requests son bienvenidos.

1. Lee [docs/README.md](docs/README.md) antes de cambiar cualquier comportamiento.
2. El código está etiquetado con `// 要件: REQ-…` (requisito) o `// 設計判断: DEC-…` (decisión de diseño). En CI, `scripts/check-spec.py` comprueba que la especificación se actualice siempre que cambia código etiquetado.
3. Una función nueva empieza como un requisito en `docs/spec/`. Las ideas para más adelante van en `docs/roadmap.md`.

## Licencia

Hanasu es de código fuente disponible (source-available), no de código abierto. © 2026 kakibara. Consulta [NOTICE](NOTICE).

- Licencia: [PolyForm Noncommercial License 1.0.0](LICENSE) más la [Hanasu Additional Permission 1.0](LICENSE-ADDITIONAL-PERMISSION.md).
- Gratuito para uso personal no comercial, educación, investigación, organizaciones benéficas y gobierno, y para el trabajo interno de pequeñas empresas (menos de 100 personas y menos de US$1M de ingresos). Cualquier empresa puede evaluar Hanasu durante 30 días.
- Las empresas más grandes, y cualquiera que venda Hanasu o lo integre en un producto o servicio, necesitan una licencia comercial. Consulta [COMMERCIAL.md](COMMERCIAL.md).
- Las versiones publicadas antes de este cambio de licencia se publicaron bajo la Apache License 2.0 y siguen bajo ella.
- Las contribuciones requieren el acuerdo que figura en [CONTRIBUTING.md](CONTRIBUTING.md).

Las licencias de terceros se enumeran en [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) (macOS) y [windows/THIRD_PARTY_NOTICES.md](windows/THIRD_PARTY_NOTICES.md) (Windows). Ambos archivos se incluyen en las descargas.
