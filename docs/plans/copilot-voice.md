# Microsoft Copilot と声でやり取りする — 実現性の調査

声で質問し、裏で Microsoft Copilot に聞いて、回答を声で読み上げる。これが実現できるかの調査。

- 作成日: 2026-11-09
- 状態: 調査だけ（作るかは未定）。[roadmap.md](../roadmap.md) の FUT-109
- 出どころ: ユーザーの依頼（2026-11-09「Microsoft Copilot と連携して音声入力を受け付け、Copilot のチャットを裏で読み込み、その回答を音声で話すことは実現可能か」）

---

## 1. 結論

| 対象 | 実現できるか | 理由 |
| --- | --- | --- |
| **Microsoft 365 Copilot**（会社のアカウント・法人ライセンス） | ◯ 公式の API で実現できる | Chat API（Graph の `/beta`、プレビュー）か Work IQ API（GA）で、質問を送って回答を受け取れる |
| **個人向けの Microsoft Copilot**（copilot.microsoft.com、Windows の Copilot アプリ） | ✕ やるべきではない | 公式の API がない。規約は、ボットやスクレイパーなどのプログラムで Copilot に入ることを禁じ、アカウントを止めることがあると書いている |

作りは「マイク → 文字起こし（Hanasu の今の仕組み）→ Copilot の API → 回答の文章 → 読み上げ」になる。Copilot の API は**文章しか返さない**ので、読み上げは Hanasu の側で作る。

前提として、次の 3 つがそろう必要がある。

1. 使う人が Microsoft 365 Copilot のライセンス（Chat API の場合）か、テナントの Copilot Credits の課金（Work IQ の場合）を持っている。
2. テナントの管理者が、Hanasu のアプリ登録と、要る権限に同意している。
3. Chat API を使うなら、`/beta`（本番での利用はサポート外）であることを受け入れる。

## 2. 調査結果

### 2.1 Microsoft 365 Copilot Chat API（プレビュー）

| 項目 | 内容 |
| --- | --- |
| 状態 | Learn では「(Preview)」。Graph の `/beta` にあり、「本番のアプリでの利用はサポートしない」と書かれている |
| エンドポイント | 会話を作る `POST /beta/copilot/conversations`、送る `POST /beta/copilot/conversations/{conversationId}/chat`、途中の文章を順に受け取る `chatOverStream`（SSE、`text/event-stream`） |
| 続けての質問 | 会話 ID で続けられる |
| 根拠に渡せるもの | OneDrive・SharePoint のファイル（`contextualResources.files`）、追加の文章（`additionalContext`）。Web 検索は既定で使う。`webContext.isWebEnabled: false` で、その 1 回だけ切れる |
| 認証 | **ユーザーとしてのサインイン（委任）だけ**。アプリだけの権限と、個人の Microsoft アカウントは使えない |
| 権限 | Sites.Read.All、Mail.Read、People.Read.All、OnlineMeetingTranscript.Read.All、Chat.Read、ChannelMessage.Read.All、ExternalItem.Read.All の**7 つすべて**が要る |
| ライセンス | 使う人ごとに Microsoft 365 Copilot のアドオンライセンスが要る（追加の料金はない）。ライセンスのない人は使えない |
| できないこと | 回答は文章だけ。ファイルの作成・メールの送信・会議の予定などの操作、コードの実行、画像の生成はできない。時間のかかる処理はタイムアウトしやすい |

途中の文章を順に受け取れるので、文ごとに読み上げを始められる。声のやり取りでは待ち時間が短くなり、いちばん向いている。

### 2.2 Work IQ API（GA）

| 項目 | 内容 |
| --- | --- |
| 状態 | 2026-06-16 に Work IQ が GA（Work IQ CLI の Learn の記述） |
| 送り先 | `https://workiq.svc.cloud.microsoft`。A2A（JSON-RPC の `SendMessage`）、ローカルの MCP（`npx @microsoft/workiq mcp`）、リモートの MCP、REST |
| 認証 | Entra ID の委任だけ（OBO も可）。アプリだけの認証は使えない。テナントの管理者の同意が要る |
| 料金 | Copilot Credits の従量課金（M365 管理センターの Copilot > Cost management で管理） |
| 途中の文章 | 公式の文書には、順に受け取る方法が書かれていない（A2A は同期の `SendMessage` だけ） |

GA で権限もまとまっているが、回答が全部そろうまで読み上げを始められない可能性がある。従量課金なので、使う量の見積もりも要る。

### 2.3 個人向けの Microsoft Copilot

- 外部のアプリから質問を送り、回答を受け取る公式の API はない。
- 個人向けの規約は、ボットやスクレイパーなどのプログラムで入ることを禁じ、使えるのを本人の個人的な利用に限っている。Microsoft は予告なくアクセスを止められる。
- Web 画面を裏で操作したり、通信をまねたりする方法は、規約に反する。画面が変わればすぐ壊れる。**採らない。**

### 2.4 Copilot の会話履歴を読む API

- `aiInteractionHistory/getAllEnterpriseInteractions`（Graph）で、ユーザーの Copilot とのやり取りを読める。
- ただし、コンプライアンスの記録のためのもの。アプリの権限（`AiEnterpriseInteraction.Read.All`）と管理者の同意が前提で、M365 Copilot のライセンスも要る。委任で使えるかは、Learn のページの間で記述が食い違っている。
- 「Copilot と会話する」用途には使わない。

### 2.5 Copilot Studio のエージェント（別の道）

- 自社で作った Copilot Studio のエージェントには、Direct Line（REST・WebSocket）、Agents SDK の `CopilotStudioClient`、音声用の Direct Line Speech でつなげる。
- ただし、Copilot そのものではなく、自分で作ったエージェントになる。Copilot Studio のライセンスが要る（Teams だけのプランでは Direct Line のシークレットを作れないという記述がある）。

### 2.6 Microsoft 自身の音声機能（比べる相手）

- Microsoft 365 Copilot アプリには、既に音声での会話がある（Windows・Mac のデスクトップと Web で GA）。
- 「Hey Copilot」の呼びかけで始められるのは Windows のデスクトップだけ。英語の呼びかけだけに反応するが、会話はほかの言語でも続けられる。
- 外部のアプリからこの音声機能を呼ぶ API はない。

## 3. Hanasu で作るときの構成案

```
ショートカット → 録音 → 文字起こし（REQ-COM-001 のエンジン）
  → Copilot Chat API（chatOverStream）
  → 届いた文章を文ごとに区切り、Markdown と引用の印を外す
  → 読み上げ（Mac: AVSpeechSynthesizer、Windows: Windows.Media.SpeechSynthesis）
```

- **入力**: 今の文字起こしをそのまま使える。
- **読み上げ**: Hanasu には今、読み上げの機能がない。新しく作る。OS の読み上げで足りなければ、クラウドの音声合成（Azure Speech・Gemini の TTS など）も選べる。
- **回答の整え**: Copilot の回答は Markdown・引用の印（[1] など）・表を含む。読み上げる前に外す処理が要る。
- **サインイン**: Mac は MSAL for macOS、Windows は MSAL.NET で、公開クライアントとして Entra ID にアプリを登録する。トークンは今の API キーと同じく安全な場所に保存する。
- **画面**: 質問と回答の文章を残す画面（会議の AI チャット REQ-MTG-040 のような形）が要るかは、要件定義で決める。

## 4. 作る前に決める・確かめること

1. **対象のユーザー**: 会社の M365 Copilot のライセンスを持つ人に限ってよいか（個人向けの Copilot は対象にしない）。
2. **Chat API か Work IQ か**: 待ち時間の短さ（Chat API の SSE）を取るか、GA と従量課金（Work IQ）を取るか。
3. **テナントの同意**: 7 つの読み取り権限は広い。社内の IT 部門が、配布するアプリに同意できるか。
4. **試作で確かめること**:
   - ネイティブのアプリ（公開クライアント）から Chat API を呼べるか。Learn には書かれていない。
   - API で作った会話が、Copilot アプリの履歴に出るか。Learn には書かれていない。
   - 日本語での回答の速さ（最初の文字が届くまでの時間）。
5. **17 言語**: UI の文字列と、読み上げの声（言語ごとの音声）を 17 言語で用意する（REQ-COM-062）。

作ると決めたら、[requirements スキル](../../.claude/skills/requirements/SKILL.md)の手順で要件定義から始める。

## 5. 出典（2026-11-09 に確かめた）

Microsoft の公式の文書:

- [Microsoft 365 Copilot APIs Overview](https://learn.microsoft.com/en-us/microsoft-365/copilot/extensibility/copilot-apis-overview)
- [Chat API overview (Preview)](https://learn.microsoft.com/en-us/microsoft-365/copilot/extensibility/api/ai-services/chat/overview)
- [copilotConversation: chat](https://learn.microsoft.com/en-us/microsoft-365/copilot/extensibility/api/ai-services/chat/copilotconversation-chat)
- [Work IQ API overview](https://learn.microsoft.com/en-us/microsoft-365/copilot/extensibility/work-iq/api-overview)
- [Work IQ CLI](https://learn.microsoft.com/en-us/microsoft-365/copilot/extensibility/work-iq/cli)
- [Copilot Credits の従量課金](https://learn.microsoft.com/en-us/microsoft-365/copilot/usage-based-billing-overview-copilot-credits)
- [aiInteractionHistory: getAllEnterpriseInteractions](https://learn.microsoft.com/en-us/graph/api/aiinteractionhistory-getallenterpriseinteractions)
- [AI interaction の変更通知](https://learn.microsoft.com/en-us/microsoft-365/copilot/extensibility/api/ai-services/change-notifications/aiinteraction-changenotifications)
- [Microsoft Copilot Terms of Use（個人向け）](https://www.microsoft.com/en-us/microsoft-copilot/for-individuals/termsofuse)
- [Use your voice to chat with Microsoft 365 Copilot](https://support.microsoft.com/en-us/Microsoft-365-Copilot/use-your-voice-to-chat-with-microsoft-365-copilot)
- [Copilot Studio と Azure Communication Services の連携](https://learn.microsoft.com/en-us/azure/communication-services/samples/integrate-azure-communication-services-with-copilot-studio)
- [Speech SDK：カスタム音声アシスタント](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/quickstarts/voice-assistants)

第三者の記事（公式の文書で確かめられなかった点の参考）:

- [Microsoft 365 Copilot Chat API: Work IQ (GA) vs Graph Beta（spknowledge）](https://spknowledge.com/2026/09/02/microsoft-365-copilot-chat-api/)
- [「Hey Copilot」(MC1189003)（handsontek）](https://m365admin.handsontek.net/microsoft-365-copilot-hey-copilot-start-voice-copilot-windows-devices/)
- [Microsoft Copilot API: Official APIs vs Scraping（cloro）](https://cloro.dev/blog/microsoft-copilot-api/)
