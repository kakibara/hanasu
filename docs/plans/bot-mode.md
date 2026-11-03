# Hanasu ボットモード — 調査・要件定義・実装計画

会議に「Hanasu ノートテイカー」というボットを参加者として入れ、録音・文字起こし・議事録を作るモードの検討。
現在の会議記録（自分の Mac で録る方式、[design/meeting.md](../design/meeting.md)）と並べて使う前提。

- 作成日: 2026-11-02
- 状態: 計画（未実装）。[roadmap.md](../roadmap.md) の FUT-203

---

## 1. 結論

| 会議ツール | ボットで記録できるか | 現実的な手段 |
| --- | --- | --- |
| **Google Meet** | ◯ | ブラウザ（Chrome）で会議に参加するボット。公式のリアルタイム音声 API（Meet Media API）は**正式提供されずに 2027-01-15 で終了**するので使えない |
| **Microsoft Teams** | ◯ | ブラウザで参加するボット。公式のメディアボットもあるが、Windows・C#・Azure 必須で重い |
| **Slack ハドル** | ✕ | ボットが参加する公式の手段がない。Recall.ai も Slack ハドルはボットではなく端末録音（Desktop SDK）で対応している。**今の Hanasu の端末録音を使い続ける** |

ボットを自前で一から作るのは割に合わない（Meet・Teams の画面変更に追従し続ける必要がある）。
**ボットの部分は既存のボット基盤（Recall.ai か、OSS の Vexa）に任せ、Hanasu はボットの派遣と、結果の文字起こし・議事録作成を受け持つ**構成を推奨する。

## 2. 調査結果

### 2.1 Google Meet

| 手段 | 内容 | 判定 |
| --- | --- | --- |
| Meet Media API | 会議の音声・映像をリアルタイムに受け取る公式 API | ✕ 2026-10-28 に、正式提供せず **2027-01-15 にエンドポイントを停止**すると告知。Google は Meet REST API への移行を推奨（[リリースノート](https://developers.google.com/workspace/meet/release-notes)） |
| Meet REST API（会議後の取得） | 会議後に、Meet 自身の文字起こし（`conferenceRecords.transcripts.entries`。発言ごとに話者＝参加者が付く）、Gemini のメモ（`smartNotes`、2026-04 GA）、録画を取得 | ◯ ボットではないが、**実名つきの文字起こしが取れる**。ただし会議で Meet の文字起こし（日本語対応）を有効にする必要があり、Workspace のエディションの条件がある |
| ブラウザボット | Chrome で Meet に参加者として入り、音声と「誰が話しているか」を画面から取る。Otter・Fireflies・Recall.ai などがこの方式 | ◯ 唯一のリアルタイムのボット手段。Meet の画面変更で壊れやすいので、保守はボット基盤に任せたい |

### 2.2 Microsoft Teams

| 手段 | 内容 | 判定 |
| --- | --- | --- |
| 公式メディアボット（Graph Communications、application-hosted media bot） | 会議の音声を参加者ごとに受け取れる | △ Windows Server 上の C#（.NET）実装・Azure 必須、テナント管理者の承認が必要（[Microsoft Q&A](https://learn.microsoft.com/en-au/answers/questions/5807336/bot-joining-teams-meetings-and-receiving-real-time)） |
| Graph API（会議後の文字起こし取得） | `onlineMeetings/{id}/transcripts/{id}/content` で Teams の文字起こしを取得 | △ 自社テナントの会議だけ。管理者の同意とアプリケーションアクセスポリシーの設定が必要（[calltranscript get](https://learn.microsoft.com/graph/api/calltranscript-get?view=graph-rest-beta)）。**取引先が主催する会議には使えない** |
| ブラウザボット | Teams のウェブ版にゲストとして参加 | ◯ 主催者がどこでも使える。ゲスト参加を許可していないテナントでは入れない |

### 2.3 Slack ハドル

- 公式 API にハドルの音声・文字起こしを取る手段はない。Events API の `user_huddle_changed` で分かるのは参加・退出だけ（[MeetStream の解説](https://meetstream.ai/blog/get-recordings-transcripts-from-slack-huddles/)）。
- Recall.ai の「Slack Huddles API」も、中身は**利用者の端末で録る Desktop Recording SDK**（[Recall.ai](https://www.recall.ai/product/slack-huddles-api)）。
- → ボットモードの対象外。今の Hanasu の端末録音で記録する。

### 2.4 ボット基盤

| 候補 | 種類 | 対応 | 費用 | 備考 |
| --- | --- | --- | --- | --- |
| **[Recall.ai](https://www.recall.ai/pricing)** | 有料 API | Meet・Teams・Zoom・Webex | 録音 $0.50/時間＋文字起こし $0.15/時間（2026 年の従量課金、[告知](https://recall.ai/blog/new-recall-ai-pricing-for-2026)）。月 500 時間・1 録音 2 時間まで | 最短で使える。データ保管場所に**日本**を選べる。参加者別の音声・話者のタイムラインが取れる |
| **[Vexa](https://github.com/Vexa-ai/vexa)** | OSS（Apache-2.0） | Meet・Teams・Zoom | 自前のサーバー代 | 自社の GCP に置けば音声が社外の業者を通らない。リアルタイムの話者つき文字起こしを流す |
| [Attendee](https://github.com/attendee-labs/attendee) | ソース公開（Elastic License 2.0） | Meet・Teams・Zoom | 自前のサーバー代 | 社内利用の自前運用は可。OSI 準拠の OSS ではない |
| Meeting BaaS など | 有料 API | Meet・Teams・Zoom | $0.35〜0.50/時間 | Recall.ai の代替 |
| 自前でブラウザボットを作る | — | — | 開発・保守が大きい | 非推奨 |

## 3. 方式の比較と推奨

| 方式 | 話者 | 相手から見えるか | 対応 | 手間 | 社外に出るもの |
| --- | --- | --- | --- | --- | --- |
| 現行: 端末録音 | 自分／話者1・2…（推定） | 見えない | 全ツール | 済み | 文字起こしテキスト（Gemini） |
| A. 会議後に公式の文字起こしを取得（Meet REST API） | **実名** | Meet の「文字起こし中」表示が出る | Meet（自社 Workspace） | 小 | なし（Google 内で完結） |
| **B. ボット（Recall.ai）** | **実名** | **ボットが参加者として見える** | Meet・Teams・Zoom | 小〜中 | 会議の音声・映像（Recall.ai、日本リージョン可） |
| C. ボット（Vexa を自社 GCP で運用） | 実名 | 見える | Meet・Teams・Zoom | 大（運用込み） | なし（自社 GCP 内） |

**推奨: B を先に作り、C に差し替えられる形にする。** 社内 Meet の会議については A も補助として用意する。

- ボットは参加者一覧に表示されるので、「黙って録っている」状態にならない（端末録音との一番の違い）。
- Recall.ai なら数日で動く。会社として会議の音声を外部業者に渡せない場合は、同じ作りのまま Vexa（自社 GCP）に差し替える。
- 話者は会議ツール上の表示名で分かるので、FluidAudio による推定は不要になる。

## 4. 要件定義

### 4.1 機能要件

| ID | 要件 | 優先度 |
| --- | --- | --- |
| B1 | 会議の URL（Meet・Teams・Zoom）を貼ると、ボットが会議に参加する | 必須 |
| B2 | ボットの表示名を設定できる（初期値「Hanasu ノートテイカー」） | 必須 |
| B3 | 参加時にチャットへ「この会議は Hanasu で記録しています」と投稿する | 必須 |
| B4 | ボットの状態（参加待ち・入室待ち・記録中・終了・失敗）を会議ノートに表示する | 必須 |
| B5 | 会議が終わる（全員退出・主催者が終了）か、Hanasu から「退出」を押すとボットが退出する | 必須 |
| B6 | 会議後、参加者の**実名つき**の文字起こしと議事録を、端末録音と同じ形式で会議ノートに保存する | 必須 |
| B7 | 主催者に入室を拒否された・時間内に入室できなかった場合は、失敗として知らせる | 必須 |
| B8 | Google カレンダーの予定から、Meet・Teams の URL がある会議にボットを自動で送る（予定ごとに ON/OFF） | あると良い |
| B9 | 社内 Meet の会議は、会議後に Meet 自身の文字起こし・Gemini のメモも取り込める（方式 A） | あると良い |
| B10 | ボット基盤を Recall.ai と Vexa（自社運用）で切り替えられる | あると良い |

### 4.2 非機能要件

| 項目 | 要件 |
| --- | --- |
| 対応ツール | Google Meet・Microsoft Teams・Zoom。Slack ハドルは対象外（端末録音を使う） |
| 会議の長さ | 2 時間まで（Recall.ai の従量課金の上限に合わせる） |
| 処理時間 | 会議終了から議事録完成まで 5 分以内（1 時間の会議） |
| データの扱い | 音声・映像は Recall.ai の日本リージョンに置き、文字起こしの取得後に削除を依頼する（保管 7 日以内）。会議ノートは今と同じく Mac に保存 |
| 認証情報 | Recall.ai の API キーはキーチェーンに保存 |
| 透明性 | ボットの表示名とチャット投稿で、記録していることが全員に分かる |

### 4.3 対象外

- Slack ハドル（公式の手段がない）
- 会議ツールの公式メディア API での自前ボット（Teams の C# ボット、終了予定の Meet Media API）
- 映像の保存・画面共有の記録
- 複数の Mac での共同管理（ボットは利用者ごとに派遣する）

### 4.4 事前に決める必要があること

1. **会議の音声を外部業者（Recall.ai）に渡してよいか。** 社内規程・取引先との契約（NDA）。だめなら最初から C（Vexa を自社 GCP）にする。
2. **ボットのアカウント。** ゲストとして入ると、社内限定の Meet には入れない／毎回主催者の承認が要る。社内の会議にも使うなら、ボット用の Google Workspace アカウント（ライセンス 1 つ）を用意する。
3. **Teams の取引先テナントのゲスト参加。** 取引先がゲストを禁止していると入れない（この場合は端末録音で記録する）。

## 5. アーキテクチャ

```
┌──────────── Hanasu（Mac）────────────┐            ┌──────── ボット基盤 ────────┐
│ 会議ノート: URL を貼る／カレンダー    │  ボット作成   │ Recall.ai（または Vexa）     │
│        │                            │ ───────────▶ │  Chrome のボットが会議に参加 │──▶ Meet / Teams / Zoom
│ MeetingBotProvider（プロトコル）     │  状態を取得   │  ・全体の音声                │
│  ├ RecallProvider                  │ ◀─────────── │  ・話者のタイムライン（実名） │
│  └ VexaProvider（フェーズ 3）        │  音声・話者    │  ・参加者一覧               │
│        │                            │ ◀─────────── │                            │
│        ▼                            │              └────────────────────────────┘
│ 既存の後処理を再利用:                 │
│  音声 → SpeechTranscriber（語ごとの時刻） │
│  話者タイムライン → SpeakerTurn（実名）    │  ← FluidAudio の代わり
│  → buildUtterances → Gemini 議事録 → 保存 │
└──────────────────────────────────────┘
```

ポイント:

- **文字起こしは Hanasu 側（Mac 上の SpeechTranscriber）で行う。** Recall.ai の文字起こし（$0.15/時間）を使わずに済み、日本語の精度も端末録音と同じになる。音声は会議後にダウンロードする。
- **話者は、ボット基盤が返す「誰が話しているか」のタイムライン**（参加者名・開始・終了）を、既存の `SpeakerTurn` に入れるだけで、今の `MeetingProcessor.buildUtterances`（語ごとの話者割り当て）がそのまま使える。話者キーには参加者名を入れる。
- Hanasu は Mac のアプリなので、ボット基盤からの Webhook は受けずに、**状態を定期的に問い合わせる（ポーリング）**。会議中は 30 秒ごと、終了後は処理完了まで 10 秒ごと。
- 録音中に Mac がスリープしてもボットは記録を続ける。Hanasu は次に起きたときに結果を取りに行く。

### 5.1 データモデルの追加

```swift
enum MeetingSource: String, Codable { case local, bot }   // Meeting に追加
struct BotSession: Codable {
    var provider: String        // "recall" / "vexa"
    var botID: String
    var meetingURL: URL
    var state: State            // joining / waitingRoom / recording / done / failed
    var participants: [String]
}
protocol MeetingBotProvider {
    func createBot(meetingURL: URL, botName: String, chatMessage: String) async throws -> BotSession
    func status(_ session: BotSession) async throws -> BotSession
    func leave(_ session: BotSession) async throws
    func downloadAudio(_ session: BotSession, to url: URL) async throws
    func speakerTimeline(_ session: BotSession) async throws -> [SpeakerTurn]   // speakerId = 参加者名
    func deleteMedia(_ session: BotSession) async throws
}
```

## 6. 実装計画

| フェーズ | 内容 | 目安 |
| --- | --- | --- |
| **0. 準備** | 4.4 の判断（外部業者・ボットのアカウント）。Recall.ai のアカウント作成（日本リージョン）と API キー発行 | 利用者側 |
| **1. ボット派遣の最小版（Recall.ai）** | `MeetingBotProvider` と `RecallProvider`（作成・状態・退出・音声のダウンロード・話者タイムライン・削除）。会議ノートに「ボットを参加させる」（URL 入力）とボットの状態表示。設定にボット名・API キー（キーチェーン）。会議後に既存の後処理（文字起こし → 話者割り当て → 議事録 → 保存）。実際の Meet で動作確認 | 2〜3 日 |
| 2. カレンダー連携 | Google カレンダーの今後の予定を読み、Meet・Teams の URL がある予定にボットを自動派遣（予定ごとに ON/OFF）。OAuth（デスクトップアプリのフロー）でカレンダーの読み取りだけを許可 | 2 日 |
| 2'. Meet 公式文字起こしの取り込み（方式 A） | Meet REST API で会議後に文字起こし・Gemini のメモを取得し、会議ノートに保存（社内 Meet 向け。ボットなしで実名が取れる） | 1〜2 日 |
| 3. 自社運用への切り替え（必要な場合） | Vexa を自社 GCP（Chrome を動かすので Compute Engine か GKE）に構築し、`VexaProvider` を追加。設定でボット基盤を切り替え | 3〜5 日＋運用 |

フェーズ 1 の内訳:

1. Recall.ai API クライアント（ボット作成、状態、退出、録音ファイル・話者イベントの取得、メディア削除）— 0.5 日
2. 会議ノートの UI（URL 入力、状態表示、退出ボタン、失敗表示）— 0.5 日
3. 話者タイムライン → `SpeakerTurn` の変換、音声のダウンロード → 既存の後処理につなぐ — 0.5 日
4. 実会議でのテスト（Meet の社内・社外、Teams のゲスト参加、入室拒否、途中退出）と調整 — 0.5〜1 日

### 6.1 テスト計画

| ケース | 確認すること |
| --- | --- |
| 社内 Meet（自分が主催） | 入室承認 → 記録 → 終了で自動退出 → 実名つきの議事録 |
| 取引先主催の Teams（ゲスト） | ゲスト参加できるか。できない場合に分かりやすく失敗するか |
| 入室を拒否 | 失敗として表示され、課金が止まるか |
| 途中で Hanasu から退出 | ボットが抜け、それまでの記録で議事録ができるか |
| Mac のスリープ中に会議終了 | 起動後に結果を取りに行けるか |
| 2 時間を超える会議 | 上限で止まることを事前に知らせるか |

## 7. 費用の目安（Recall.ai）

- 1 時間の会議 = $0.50（文字起こしは Hanasu 側で行うので $0.15 はかからない）
- 週 20 時間の会議にボットを送ると、月 約 87 時間 ≒ **約 $43/月**
- 保管は 7 日まで無料（取得後すぐ削除するので追加なし）

## 8. リスク

| リスク | 対策 |
| --- | --- |
| 会議ツールの画面変更でボットが入れなくなる | ボット基盤（Recall.ai・Vexa）側で追従してもらう。失敗時は端末録音に切り替えるよう案内 |
| 社内限定の会議・ゲスト禁止のテナントに入れない | ボット用の社内アカウントを用意。入れない会議は端末録音 |
| 会議の音声が外部業者を通る | 日本リージョン・取得後の削除。だめならフェーズ 3（自社 GCP） |
| ボットがいることを嫌がる参加者がいる | 会議ごとにボット／端末録音を選べるようにする。事前に案内する |
| Meet Media API の終了（2027-01-15） | 使わない（ブラウザボット方式を採るので影響なし） |

## 参考

- Google: [Meet REST API リリースノート（Meet Media API の終了）](https://developers.google.com/workspace/meet/release-notes) / [Meet API v2 リファレンス](https://developers.google.cn/meet/api/reference/rest/v2?hl=ko) / [Meet の文字起こしの対応言語（日本語）](https://workspaceupdates.googleblog.com/2025/03/more-languages-for-recorded-captions-and-transcripts-in-google-meet.html) / [Transcripts with Google Meet](https://support.google.com/meet/answer/12849897)
- Microsoft: [calltranscript get](https://learn.microsoft.com/graph/api/calltranscript-get?view=graph-rest-beta) / [Q&A: Teams 会議に参加してリアルタイム音声を受け取るボット](https://learn.microsoft.com/en-au/answers/questions/5807336/bot-joining-teams-meetings-and-receiving-real-time) / [Q&A: Real-time Audio in Meetings Using a Bot](https://learn.microsoft.com/en-us/answers/questions/2180136/real-time-audio-in-meetings-using-a-bot)
- Slack: [Is There a Slack Huddles API?](https://meetstream.ai/blog/get-recordings-transcripts-from-slack-huddles/) / [Recall.ai Slack Huddles API](https://www.recall.ai/product/slack-huddles-api)
- ボット基盤: [Recall.ai 2026 年の料金](https://recall.ai/blog/new-recall-ai-pricing-for-2026) / [Recall.ai Pricing](https://www.recall.ai/pricing) / [Vexa](https://github.com/Vexa-ai/vexa) / [Attendee](https://github.com/attendee-labs/attendee) / [Recall.ai: Teams の録音ソフト](https://www.recall.ai/blog/microsoft-teams-recording-software-open-source)
