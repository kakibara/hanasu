<div align="center">

<img src="docs/images/icon.png" width="112" alt="Ícone do Hanasu">

# Hanasu

**Fale naturalmente. Receba um texto limpo, pronto para enviar, e atas de reunião que se escrevem sozinhas.**

Um app de entrada por voz e anotações de reunião para macOS e Windows. Ele usa reconhecimento de fala no próprio dispositivo e Gemini, Claude ou um modelo de IA que roda no seu dispositivo.

[![Release](https://img.shields.io/github/v/release/kakibara/hanasu?sort=semver&label=release)](https://github.com/kakibara/hanasu/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/kakibara/hanasu/total)](https://github.com/kakibara/hanasu/releases)
[![License](https://img.shields.io/badge/license-PolyForm%20Noncommercial%20%2B%20small%20business-blue)](COMMERCIAL.md)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-000000?logo=apple)
![Windows 10/11](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows)
[![Windows build](https://github.com/kakibara/hanasu/actions/workflows/windows.yml/badge.svg)](https://github.com/kakibara/hanasu/actions/workflows/windows.yml)

[English](README.md) · [日本語](README.ja.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Italiano](README.it.md) · **Português (Brasil)** · [Русский](README.ru.md) · [Türkçe](README.tr.md) · [Tiếng Việt](README.vi.md) · [Bahasa Indonesia](README.id.md) · [Polski](README.pl.md) · [العربية](README.ar.md) · [हिन्दी](README.hi.md)

<sub>Esta é uma tradução do README em inglês. Se houver diferenças, o README em inglês é o mais atualizado.</sub>

<img src="docs/images/hud.png" width="560" alt="HUD de gravação do Hanasu">

</div>

> [!NOTE]
> O Hanasu foi feito primeiro para o **japonês**, e o japonês é o idioma mais testado.
> As telas do app e as instruções que ele dá à IA estão disponíveis nos mesmos 17 idiomas deste README. As telas seguem o idioma do sistema, e as instruções para a IA seguem o idioma de transcrição nos Ajustes. Para qualquer outro idioma, o Hanasu usa o inglês.
> Ele também pode traduzir o que você diz para um **inglês** natural, para **japonês** ou para qualquer um dos 17 idiomas suportados antes de digitar.

## Por que o Hanasu

O ditado nativo do sistema entrega uma transcrição crua. Ela mantém as hesitações e os erros com homófonos, não tem pontuação e inclui cada "espera, quer dizer…".
O Hanasu envia a transcrição para uma IA (Gemini, Claude ou um modelo local no seu dispositivo), que corrige esses erros e organiza o texto. Depois, o Hanasu digita o resultado onde está o seu cursor.
Ele é inspirado no Typeless, Wispr Flow, Aqua Voice e Granola. O código-fonte do Hanasu é público. Ele é gratuito para uso pessoal e para pequenas empresas; empresas maiores precisam de uma [licença comercial](COMMERCIAL.md). Você usa a sua própria chave de API do Gemini ou do Claude, ou roda um modelo local sem chave de API e sem que nenhum texto saia do seu dispositivo.

## Recursos

### 🎙️ Entrada por voz

| | |
| --- | --- |
| **Fale → texto refinado** | Pressione <kbd>⌥ Space</kbd>, fale e pressione de novo (ou clique em **■ Parar**). O Hanasu remove as hesitações, corrige homófonos, aplica as suas autocorreções e cola o texto no cursor. |
| **Fale e digite já traduzido** | Pressione <kbd>⌥⇧ Space</kbd> ou mude o HUD para **English**, **日本語** ou outro idioma enquanto fala. Expressões prontas são traduzidas com naturalidade, então お疲れ様です vira "Hi,". Escolha os idiomas oferecidos (qualquer um dos 17 idiomas suportados) em **Ajustes → Geral**. O padrão é inglês. No Mac, em **Ajustes → Por app** você pode fazer um app começar em um desses idiomas. |
| **Idiomas misturados ficam como foram falados** | Por padrão, as partes que você fala em inglês continuam em inglês. Se preferir, você pode unificar a saída em japonês. |
| **Edite por voz** | Selecione um texto, pressione <kbd>⌃⌥⌘ E</kbd> e diga "deixe mais educado", "transforme em tópicos" ou "traduza para o inglês". |
| **Estilos por app** | O texto fica informal e curto no Slack, educado e com parágrafos no Mail, e em estilo escrito no Pages, Word e Notion. Você pode mudar a predefinição de cada app. |
| **Snippets** | Diga "assinatura de e-mail" para inserir um texto salvo exatamente como você o escreveu. Snippets nunca são enviados para a IA. |
| **Dicionário** | Adicione nomes próprios e regras de substituição como `ストックマーク => Stockmark`. As regras também valem para as transcrições das reuniões. A partir de uma reunião aberta em Anotações de reunião, a IA pode sugerir novas entradas tiradas dessa reunião (no Mac, também do seu histórico e das reuniões recentes), e você adiciona só as que escolher. |
| **Contexto da tela** *(opcional)* | O Hanasu lê o título da janela e o texto ao redor do cursor, para que os nomes batam com o que já está na tela. Campos de senha nunca são lidos. |
| **Escolha o microfone** *(Mac)* | Escolha o microfone nos Ajustes, ou troque pelo botão de microfone no HUD sem interromper a gravação. |
| **Histórico** | Pesquise resultados anteriores e tente de novo os que falharam. Por padrão, o histórico é mantido por 30 dias, e você pode mudar isso nos Ajustes. No Mac, pressione <kbd>⌥⇧ V</kbd> para colar o último resultado de novo. |
| **Nenhum lugar para colar?** | Se nenhum campo de texto estiver em foco (por exemplo, com a área de trabalho em primeiro plano), o Hanasu mantém o resultado na tela em vez de colá-lo. Copie dali, ou simplesmente pressione <kbd>⌘V</kbd> onde quiser (você pode escolher se o resultado fica na área de transferência). |
| **A colagem não chegou?** | Se a colagem não chegou a nenhum app (por exemplo, você trocou de janela durante a gravação), o Hanasu deixa o último resultado na área de transferência e avisa no HUD. Pressione <kbd>⌘V</kbd> onde quiser. Em Ajustes → Geral, você também pode fazer o histórico de ditado abrir quando isso acontecer. |

<p align="center">
  <img src="docs/images/hud-english.png" width="420" alt="Saída em inglês">
  <img src="docs/images/edit-mode.png" width="420" alt="Edição por voz">
</p>

### 📝 Anotações de reunião

| | |
| --- | --- |
| **Grava os dois lados** | O seu microfone é gravado como "você". A saída de áudio do Mac (Zoom, Meet, Teams, huddles do Slack etc.) é gravada como "eles". Nenhum bot entra na chamada. |
| **Diarização de falantes** | O outro lado é dividido em Falante 1, Falante 2 e assim por diante, no próprio dispositivo. Quando a conversa deixa um nome claro (alguém se apresenta, por exemplo), a IA o preenche e o marca como suposição. Você pode renomear os falantes depois. |
| **Atas com IA** | Geradas pela IA que você escolher para reuniões. Escolha um modelo: automático, reunião semanal, 1:1, chamada de vendas, brainstorming ou personalizado. Os itens de ação incluem um responsável e um prazo. |
| **Confira a origem e ouça de novo** *(Mac)* | A ata abre em uma única página: resumo e itens de ação primeiro, com a transcrição ao lado. Clique no horário depois de um ponto para ir à fala de onde ele veio. Reproduza a gravação a partir de qualquer fala e silencie o seu lado ou o deles se a chamada teve eco. |
| **Notas ao vivo e destaques** | Digite notas com horário durante a chamada, ou pressione <kbd>⌃⌥⌘ H</kbd> para marcar "isto é importante" (dá para desfazer por 10 segundos). A ata dá prioridade a esses trechos, e depois você pode ler a conversa em torno de cada marcação. |
| **Legendas flutuantes** *(Mac)* | Mostre a transcrição ao vivo como legendas sobre o app da reunião. |
| **Chat com IA durante a reunião** *(Mac)* | Enquanto grava, pergunte à IA sobre a conversa até agora (<kbd>⌘J</kbd>). Um clique para "resumo até agora" ou "decisões e tarefas". Faça perguntas de acompanhamento e clique em um horário numa resposta para ir àquele trecho da transcrição. |
| **Detecção de reuniões** | Quando um app de reunião começa a usar o microfone, o Hanasu pergunta se deve gravar. Ele nunca começa a gravar sozinho. |
| **Pesquisar e perguntar** | Pesquise o texto de todas as reuniões, ou pergunte "O que decidimos na reunião semanal passada?". A resposta cita as reuniões que usou. |
| **Exportar** | Copie como Markdown ou como um resumo pronto para o Slack, salve como `.md` / `.txt`, ou envie os itens de ação para o Lembretes. |
| **Organizar** | Renomeie uma reunião editando o título diretamente, ou exclua uma reunião de que não precisa mais. |

<p align="center">
  <img src="docs/images/meeting-live.png" width="420" alt="Gravação com notas ao vivo">
  <img src="docs/images/meeting-ask.png" width="420" alt="Pergunte às suas reuniões">
</p>
<p align="center">
  <img src="docs/images/meeting-minutes.png" width="420" alt="Ata com itens de ação">
  <img src="docs/images/meeting-suggestion.png" width="420" alt="Detecção de reuniões">
</p>

### 🤖 Escolha a sua IA

Escolha a IA que refina o seu texto, separadamente para **entrada por voz** e **reuniões**.

| IA | Modelo padrão | Acesso |
| --- | --- | --- |
| **Gemini** (padrão no Windows) | entrada por voz `gemini-3.5-flash-lite`, reuniões `gemini-3.8-flash` | Chave de API do Google AI Studio ou conta de serviço do Vertex AI |
| **Claude** | entrada por voz `claude-haiku-5-5`, reuniões `claude-sonnet-5-5` (Opus 5.5 também disponível) | Chave de API da Anthropic |
| **Local** (no seu dispositivo; padrão no Mac) | Gemma 4 E4B (recomendado). Veja a tabela abaixo | Nenhum. Baixe o modelo em **Ajustes → IA**. No Mac, se o modelo não estiver presente quando o Hanasu começar a refinar o texto, ele pergunta se você quer baixá-lo |
| **Apple** *(Mac, macOS 27)* | O modelo do Apple Intelligence no dispositivo, pelo comando `fm` | Nenhum |

Essas IAs lidam apenas com texto. A fala é transcrita pelo mecanismo abaixo.

#### 💻 Modelos locais

Com **Local**, o Hanasu roda um modelo de linguagem pequeno no seu próprio Mac ou PC com o [llama.cpp](https://github.com/ggml-org/llama.cpp) incluído, então o seu texto nunca sai do dispositivo. O Mac usa a GPU (Metal), e o Windows usa a CPU. Você baixa um modelo uma única vez em **Ajustes → IA**. O Hanasu confere o tamanho e o SHA-256 antes de usá-lo.

| Modelo | Tamanho | Licença | Observações |
| --- | --- | --- | --- |
| **Gemma 4 E4B** (Google) — **recomendado** | 4.59 GB | Apache-2.0 | Os resultados mais naturais tanto na limpeza do texto quanto nas atas. Recomenda-se 16 GB de memória ou mais. É o padrão para entrada por voz e para reuniões |
| LFM2.5-1.2B-JP (Liquid AI) | 1.25 GB | LFM Open License v1.0 | Pequeno e rápido. Por esta licença, organizações com receita anual de US$ 10 milhões ou mais não podem usá-lo comercialmente |
| Sarashina2.2 3B (SB Intuitions) | 2.07 GB | MIT | Treinado em japonês. O contexto é de 8K, então reuniões longas são resumidas em partes |
| Qwen3.5-4B (Alibaba) | 2.74 GB | Apache-2.0 | Cerca de metade do tamanho do Gemma, então roda com mais facilidade em 8 GB de memória. Lida pior que o Gemma com autocorreções |

> [!TIP]
> Recomendamos o **Gemma 4 E4B**. Nos nossos testes, os outros modelos às vezes mantinham palavras que você quis retirar, acrescentavam frases que você não disse, confundiam o responsável por um item de ação, ou juntavam ou deixavam passar itens de ação. O Gemma 4 E4B lidou bem e de forma consistente com a limpeza do texto e com as atas.

### 🔊 Escolha o mecanismo de fala

| Mecanismo | Onde roda | Transcrição ao vivo | Observações |
| --- | --- | --- | --- |
| **Padrão do sistema** (padrão) | Mac: `SpeechAnalyzer` · Windows: `Windows.Media.SpeechRecognition` | ✅ | No dispositivo no Mac |
| **Whisper** | No dispositivo (WhisperKit no Mac, whisper.cpp no Windows) | — (depois que você para) | O modelo é baixado quando você o seleciona |
| **Gemini** | Google | — (depois que você para) | O áudio gravado é enviado ao Google |

Você pode escolher um mecanismo diferente para entrada por voz e para reuniões. No Windows, as reuniões usam Whisper ou Gemini.
No Mac, escolha o idioma da transcrição em uma lista (japonês, inglês, chinês, coreano, francês, alemão, espanhol, italiano, português). Ele começa como o idioma do sistema.

### ⌨️ Use pelo terminal e por agentes de IA *(Mac)*

O comando `hanasu` permite que scripts e agentes de IA (Claude Code, Claude Desktop e outros) leiam os registros das suas reuniões e usem o seu estilo de refinamento. Ele é o próprio app, então não há mais nada para instalar. Abra **Ajustes → Comando e MCP** para adicioná-lo ao PATH ou copiar a configuração para MCP.

| | |
| --- | --- |
| **Ler reuniões** | `hanasu meetings list / show / search` e `hanasu actions` mostram reuniões, atas, transcrições e itens de ação, como texto ou `--json`. Nada é enviado a lugar nenhum. |
| **Perguntar** | `hanasu ask "O que decidimos na semana passada?"` responde a partir das suas reuniões com a IA que você escolheu para reuniões. |
| **Refinar texto** | `hanasu refine` refina ou traduz texto do mesmo jeito que a entrada por voz, e `hanasu edit "<instrução>"` o reescreve. Os dois funcionam em pipes. |
| **MCP para agentes de IA** | `hanasu mcp` é um servidor MCP (stdio). Os agentes podem listar, ler, pesquisar e fazer perguntas sobre as suas reuniões. O conteúdo das reuniões compartilhado assim vai para o agente e para o provedor da IA dele. |
| **Conferir a configuração** | `hanasu doctor` mostra qual IA e quais credenciais são usadas, a pasta de reuniões e como registrar o MCP. Execute `hanasu help` para ver todas as opções. |

Administradores podem desativar o comando, o MCP ou algumas IAs com um perfil de configuração.

## Download

Baixe a versão mais recente em [**Releases**](https://github.com/kakibara/hanasu/releases/latest).

| Plataforma | Arquivo | Requisitos |
| --- | --- | --- |
| macOS | `Hanasu-<version>-macOS.zip` | macOS 26 (Tahoe) ou posterior, Apple Silicon |
| Windows | `Hanasu-<version>-Windows-x64.zip` | Windows 10 (2004 ou posterior) / 11, x64 |

<details>
<summary><b>macOS: primeira execução</b></summary>

1. Descompacte o arquivo e mova `Hanasu.app` para **Aplicativos**.
2. O app é autoassinado e não notarizado, então o macOS o bloqueia na primeira vez. Clique em **OK**, depois abra **Ajustes do Sistema → Privacidade e Segurança** e clique em **Abrir Mesmo Assim**.
   Você também pode executar `xattr -dr com.apple.quarantine /Applications/Hanasu.app`.
3. Quando solicitado, permita **Microfone**, **Reconhecimento de Fala** e **Acessibilidade**. A Acessibilidade é necessária para colar com ⌘V.

</details>

<details>
<summary><b>Windows: primeira execução</b></summary>

1. Descompacte o arquivo, coloque a pasta `Hanasu` em qualquer lugar (por exemplo `%LOCALAPPDATA%\Programs`) e execute `Hanasu.exe`.
2. O app não tem assinatura de código, então o SmartScreen mostra um aviso. Clique em **Mais informações → Executar assim mesmo**.
3. O mecanismo de fala do Windows exige que o **Reconhecimento de fala online** esteja ativado nas configurações do Windows. O Hanasu avisa se estiver desativado.

Veja [windows/README.md](windows/README.md) para mais observações e para as diferenças entre a versão Windows e a versão Mac.

</details>

Quando uma nova versão é lançada, o Hanasu avisa você ao abrir e pergunta antes de se atualizar. Você também pode escolher **アップデートを確認…** (Verificar atualizações) no menu (a verificação ao abrir pode ser desativada em **Ajustes → Geral**). As versões até a v1.5.0 ainda não têm isso, então atualize essas versões manualmente uma vez.

## Primeiros passos

No Mac, a primeira execução abre um breve tour guiado. Ele permite escolher a sua IA (o Gemma 4 E4B, modelo local recomendado, é baixado ali mesmo), mostra os principais recursos e dicas de configuração, e pede as permissões de que o Hanasu precisa. Abra-o de novo quando quiser em **Como usar o Hanasu…** no menu.

1. **Escolha uma IA.** Abra **Ajustes → IA** e escolha uma IA para entrada por voz e para reuniões. Para o Gemini, cole uma chave de API do [Google AI Studio](https://aistudio.google.com/apikey) ou selecione um arquivo JSON de conta de serviço do Vertex AI. Para o Claude, cole uma chave de API do [Claude Console](https://console.anthropic.com/settings/keys). Para Local, baixe um modelo (recomenda-se o Gemma 4 E4B). Nenhuma chave é necessária. Clique no botão de teste para conferir se funciona.
2. **Dite.** Coloque o cursor onde quer o texto, pressione o atalho, fale e pressione o atalho de novo.
3. **Grave uma reunião.** Use o menu da barra de menus (Mac) ou da bandeja (Windows), ou o atalho. Fones de ouvido ajudam a manter os dois lados separados.

No Mac, você pode mostrar o ícone do Hanasu na barra de menus, no Dock ou em ambos (Ajustes → Geral).

### Atalhos padrão

| Ação | macOS | Windows |
| --- | --- | --- |
| Entrada por voz (iniciar / parar) | <kbd>⌥ Space</kbd> | <kbd>Ctrl Alt Space</kbd> |
| Entrada por voz traduzida (para os idiomas escolhidos) | <kbd>⌥⇧ Space</kbd> | <kbd>Ctrl Alt Shift Space</kbd> |
| Editar a seleção por voz | <kbd>⌃⌥⌘ E</kbd> | — |
| Colar o último resultado de novo | <kbd>⌥⇧ V</kbd> | — |
| Cancelar a gravação | <kbd>Esc</kbd> | <kbd>Esc</kbd> |
| Gravação de reunião (iniciar / parar) | <kbd>⌃⌥⌘ M</kbd> | <kbd>Ctrl Alt Shift M</kbd> |
| Marcar "isto é importante" em uma reunião | <kbd>⌃⌥⌘ H</kbd> | <kbd>Ctrl Alt Shift H</kbd> |

Você pode mudar todos os atalhos nos Ajustes. O guia completo do usuário (em japonês) está em [docs/guide.md](docs/guide.md).

## Privacidade

- **Por padrão, o áudio fica no seu dispositivo.** O reconhecimento de fala, o Whisper e a diarização de falantes rodam todos localmente.
- **A IA recebe texto, não áudio.** O Gemini ou o Claude recebe a transcrição. Dependendo dos seus ajustes, também pode receber o nome do app em que você está digitando, o contexto da tela e as transcrições de reuniões para a função Perguntar e para o chat com IA da reunião.
- **Local e Apple também mantêm o texto no seu dispositivo.** Se você escolher qualquer um dos dois, nada é enviado a um serviço de IA. O único download é o próprio modelo.
- **O áudio só vai para o Google se você escolher.** Se você selecionar o mecanismo de fala Gemini, o áudio gravado é enviado ao Google.
- **Os agentes só recebem reuniões se você os conectar.** O comando `hanasu` e o servidor MCP dele só leem reuniões quando você ou um agente os chamam, e o que eles retornam vai para esse agente e para o provedor da IA dele.
- **Reuniões são arquivos comuns.** Elas são salvas como JSON e Markdown em `~/Documents/Hanasu/Meetings/` (Windows: `Documents\Hanasu\Meetings\`). Mac e Windows usam o mesmo formato.
- **Sem telemetria.** O Hanasu não coleta dados de análise.
- **As chaves de API são protegidas pelo sistema operacional.** No macOS, elas ficam no Keychain, e outros apps precisam pedir a sua senha de login para lê-las. No Windows, são criptografadas com DPAPI, ou com uma chave do Windows Hello se você preferir. Nenhum dos dois consegue impedir totalmente um malware executado com o seu usuário. Veja [docs/design/security.md](docs/design/security.md).

> [!IMPORTANT]
> Obtenha o consentimento de todos os participantes antes de gravar uma reunião. Siga as regras da sua organização sobre gravação e uso de serviços de IA.

## Compilar a partir do código-fonte

<details>
<summary><b>macOS</b> (Xcode Command Line Tools, Swift 6.2)</summary>

```bash
./scripts/build-app.sh             # gera build/Hanasu.app
open build/Hanasu.app
./scripts/create-signing-cert.sh   # opcional: mantém as permissões entre recompilações
```

</details>

<details>
<summary><b>Windows</b> (.NET 8 SDK)</summary>

```bash
cd windows
dotnet build Hanasu.Windows.sln
dotnet publish Hanasu.Windows/Hanasu.Windows.csproj -c Release -r win-x64 --self-contained -p:PublishSingleFile=true -o publish/win-x64
```

Veja [windows/README.md](windows/README.md).

</details>

## Documentação

A documentação está escrita em japonês.

| | |
| --- | --- |
| [docs/guide.md](docs/guide.md) | Guia do usuário: como usar, ajustes, regras do dicionário |
| [docs/spec/](docs/spec/) | Requisitos implementados (`REQ-*`) e decisões de design (`DEC-*`) |
| [docs/design/](docs/design/) | Como é construído: arquitetura e fluxo de dados |
| [docs/roadmap.md](docs/roadmap.md) | Planos ainda não implementados |
| [docs/releasing.md](docs/releasing.md) | Como as releases são feitas (tagpr) |

## Como contribuir

Issues e pull requests são bem-vindos.

1. Leia [docs/README.md](docs/README.md) antes de mudar qualquer comportamento.
2. O código é marcado com `// 要件: REQ-…` (requisito) ou `// 設計判断: DEC-…` (decisão de design). Na CI, `scripts/check-spec.py` verifica se a especificação foi atualizada sempre que um código marcado muda.
3. Um novo recurso começa como um requisito em `docs/spec/`. Ideias para depois vão em `docs/roadmap.md`.

## Licença

O Hanasu é source-available (código-fonte disponível), não de código aberto. © 2026 kakibara. Veja [NOTICE](NOTICE).

- Licença: [PolyForm Noncommercial License 1.0.0](LICENSE) mais a [Hanasu Additional Permission 1.0](LICENSE-ADDITIONAL-PERMISSION.md).
- Gratuito para uso pessoal não comercial, educação, pesquisa, instituições de caridade e governo, e para o trabalho interno de pequenas empresas (menos de 100 pessoas e menos de US$1M de receita). Qualquer empresa pode avaliar o Hanasu por 30 dias.
- Empresas maiores, e qualquer pessoa que venda o Hanasu ou o integre a um produto ou serviço, precisam de uma licença comercial. Veja [COMMERCIAL.md](COMMERCIAL.md).
- As versões lançadas antes desta mudança de licença foram lançadas sob a Apache License 2.0 e continuam sob ela.
- Contribuições exigem o acordo descrito em [CONTRIBUTING.md](CONTRIBUTING.md).

As licenças de terceiros estão listadas em [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) (macOS) e [windows/THIRD_PARTY_NOTICES.md](windows/THIRD_PARTY_NOTICES.md) (Windows). Os dois arquivos estão incluídos nos downloads.
