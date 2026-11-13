# 記録中に落ちた会議を、録音から戻す

- 状態: 実装済み（2026-11-13）。要件と設計判断は [spec/meeting.md](../spec/meeting.md) の REQ-MTG-128・DEC-MTG-156〜160、確かめた結果は [verification/meeting.md](../verification/meeting.md) の 20 章
- 依頼: 2026-11-13「録音していたら以下のエラーが出たので確認調査して修正して」の調査で、落ちた会議の録音が開けないと分かった。同日「このタスクをここで実行してください：「Make meeting audio survive an app crash (Mac)」」。
- ユーザーに決めてもらったこと（2026-11-13）: 範囲は「録音から作り直すボタン」（記録中の文字起こしの都度保存はしない）。Windows にも入れる。Mac で記録中に終了するときは「確かめてから録音を閉じる」。作り直しで使うエンジンは「押したら確かめる」。今朝の会議の壊れた録音の修復は「試さない」。

## 目的

Mac 版で会議の記録中にアプリが落ちると、録音（`me.m4a`・`others.m4a`）が開けなくなり、記録中に出ていた文字起こしも残らない。2026-11-13 の会議では、約 3 分ぶんの録音と文字起こしを失った（`afinfo` が `AudioFileOpenURL failed`。ファイルの先頭は `ftyp` で、閉じられなかったので `moov` がない）。

落ちても直前（約 2 秒前）までの録音が残り、次に起動したときに、その録音から文字起こし・話者分離・議事録を作れるようにする。Windows 版は録音がもう残る（DEC-MTG-102）ので、作り直す入口だけを足す。

## 調べたこと（2026-11-13）

### Windows の今の作り

- 録音は `WavStreamWriter`（`windows/Hanasu.Core/Audio/WavStreamWriter.cs`）が 16 kHz・モノラル・16 bit の WAV に書き、5 秒ぶん書くごとにヘッダーの長さを書き直して `Flush` する（DEC-MTG-102）。落ちると、ヘッダーの長さは最大約 5 秒古い。最初の 5 秒で落ちると長さは 0 のまま。
- 読むのは自前の `WavFile.Decode`（`windows/Hanasu.Core/Audio/WavFile.cs`）で、data の長さはヘッダーの値とファイルの残りの小さいほう。ヘッダーより後ろに書かれた音は捨てられ、長さ 0 なら空（無音として飛ばし、エラーにしない）。`WavStreamWriter.Truncate` は、ファイルの長さから data の長さを計算し直してヘッダーを書く。
- 起動時に `MeetingStore.MarkInterruptedMeetings` が「失敗」にする（エラーの文は `Strings.Meeting_Interrupted`）。`AudioStartOffsets` と `Duration` は `MeetingController.StopAsync` でだけ入れるので、落ちた会議には残らない。終わっていないオフレコも閉じない。
- 後処理は `MeetingPostProcessor.ProcessAsync`（WAV を自分で読んで文字起こし・話者分離・議事録・保存。`AudioStartOffsets` がなければ 0）。`MeetingController.ProcessAsync`（private）が設定から組み立てて呼び、`Current`・`State` と進み具合（`ProgressChanged`）を出す。保存した会議を録音から処理し直す口はない（議事録だけなら `RegenerateMinutesAsync`）。
- 会議ノートは `MeetingWindow.xaml(.cs)`。ボタンは `ActionsPanel`（「議事録を作り直す」の `RegenerateButton` など）、帯は `ErrorText`（`BannerText`）。処理中は `UpdateState` が `LiveBox` に「後処理中」と進み具合を出す。文字列は `Hanasu.Windows/Properties/Strings*.resx`（17 言語。`scripts/i18n-resx.py`）。
- テストは `Hanasu.Core.Tests/MeetingTests.cs`（`MeetingControllerTests` と偽の録音機・文字起こし・話者分離）と `MeetingAudioDeletionTests.cs`。一時フォルダに会議を作れる（`TestKeys.TempDirectory()`）。


### 落ちたときに残るもの（手元の実験）

16 kHz・モノラルの音を 0.1 秒ずつ書き、約 19 秒で `kill -9` した。

| 書き方 | 落ちたあと |
| --- | --- |
| 今の `AVAudioFile` の m4a（AAC） | 開けない（`AudioFileOpenURL failed`） |
| CAF（非圧縮） | 18.8 秒すべて読める。1 分あたり約 1.9 MB |
| WAV（非圧縮、`AVAudioFile`） | 長さ 0 と読まれる（ヘッダーが未更新） |
| CAF に AAC | 長さ 0 と読まれる |
| 断片化した m4a（`AVAssetWriter`、`movieFragmentInterval` 5 秒） | 14.9 秒（最後の断片まで）読める |

断片化した m4a は、正常に閉じたファイルも `AVAudioFile`・`AVURLAsset`・`AVAudioPlayer`・`AVAssetExportSession`（`MeetingSleepCut.trimAudio` と同じ書き出し）で読めた。2 時間ぶん（32 kbps）の大きさは、普通の m4a の 23.3 MB に対し、断片 1 秒で 24.6 MB、5 秒で 24.0 MB。開く・途中に移る・再生の準備の速さは同じ（開く 0.02 秒、移って読む 0.002 秒、再生の準備 0.09 秒）。`expectsMediaDataInRealTime` を true にして書き手の準備が間に合わないときに捨てると音が欠けた（60 秒ぶんで 21.3 秒）ので、待ってから書く。

### Mac の今の作り

- 音声ファイルは `ChannelTranscriber.makeFile` が `AVAudioFile(forWriting:)`（AAC 32 kbps）で作り、`append` のたびに書き、`finish`・`cancel` で `file = nil` にして閉じる。記録中の文字起こしの形式（Mac 標準）か 16 kHz モノラル（Whisper / Gemini。`TranscriptionAudio.format`）。
- 起動時に `MeetingStore.markInterruptedMeetings` が「記録中」「処理中」の会議を「失敗」にし、エラーの文を「記録の途中でアプリが終了しました。」にする（DEC-MTG-018）。
- 2 つの録音の先頭のずれ（`audioStartOffsets`）と長さ（`duration`）は、記録を止めたとき（`MeetingRecorder.stop`）にだけ保存する。落ちた会議には残らない。発言（`utterances`）も止めたあとの `process` で初めて保存する。メモ・印・オフレコは押すたびに保存する（DEC-MTG-043・094）。
- 録音からの文字起こしは、Whisper / Gemini は `MeetingRecorder.transcribeRecordedAudio`（`MeetingBatchTranscription.transcribe`）、Mac 標準は `--meeting-files` の CLI が `ChannelTranscriber` にファイルを流す形で既にある。話者分離と議事録は `MeetingRecorder.process`。
- `process` は、文字起こしに失敗したチャンネルがあっても最後に必ず状態を「完了」にする（`MeetingRecorder.swift` の process の終わり）。エラーの文は消さずに書き足す。Windows の `MeetingPostProcessor` は、両方のチャンネルが失敗して発言が 0 件のときだけ「失敗」にし、エラーの文を上書きする。
- 会議ノートの一覧は、`recorder.current` を「記録中」の節に出す（`MeetingWindow.swift` の一覧）。Windows も `Current` を一覧の先頭に入れる（`MeetingWindow.xaml.cs` の `ReloadList`）。
- Mac には `applicationShouldTerminate` がなく、記録中に ⌘Q・ログアウト・再起動をすると、録音を閉じないまま終わる（落ちたときと同じく開けなくなる）。Windows は記録中の終了を確かめる（DEC-MTG-109）。
- 記録を始める前の確かめ（`MeetingRecorder.checkReady`・`Permissions.ensureRecordingPermissions`）は DEC-MTG-007。会議には、記録したときの文字起こしのエンジンは残らない。
- 失敗した会議の帯は `MeetingStatusBanners`（`MeetingDocumentView.swift`）。エラーの帯に「議事録を作り直す」（発言があるときだけ）、録音を残した会議には「音声ファイルは残しています」の帯を出す。「…」のメニューは `MeetingMoreMenuItems`（`MeetingWindow.swift`）。

## 要件の案

### REQ-MTG-128 記録中にアプリが落ちても、録音が残り、そこから文字起こしと議事録を作れる（新規）

- 内容: 記録の途中でアプリが落ちたり強制終了されたりしても、その直前までの録音を残す。Mac で記録中に終了しようとしたときは確かめ、終了するなら録音を閉じてから終わる。次に起動したあと、その会議の会議ノートから、残った録音を使って文字起こし・話者分離・議事録を作れる。
- 受け入れ条件:
  - Mac: 記録を始めて 5 秒より後に、アプリのプロセスを強制終了（`kill -9`）しても、`me.m4a`・`others.m4a` は開ける形で残り、終了した時刻の 3 秒前までの音が入っている。普通の終了（SIGTERM）でも同じ。
  - Windows: 同じく `me.wav`・`others.wav` は開ける形で残る（今の DEC-MTG-102 のまま）。作り直すときは、ヘッダーより後ろに書かれた音も使い、終了した時刻の 6 秒前までの音が入る。
  - Mac: 記録中に ⌘Q（メニューの「終了」も）で終了しようとすると、「会議を記録中です。終了しますか？」と確かめる。「終了」を選ぶと、録音を閉じてから終わる。「キャンセル」なら記録を続ける。ログアウト・再起動・システム終了のときは確かめずに、録音を閉じてから終わる。こうして終わった会議も、次に起動すると落ちた会議と同じく「失敗」になる。
  - 次に起動すると、その会議は今までどおり「失敗」（「記録の途中でアプリが終了しました。」）。会議ノートで選ぶと、作り直すボタン「録音から文字起こしと議事録を作る」が出る。Mac はエラーの帯と「…」のメニュー、Windows は会議の操作のボタンの並び（`ActionsPanel`）。
  - ボタンを出す条件は、Mac と Windows で同じ: 発言が 0 件、その OS の後処理が読める録音（Mac は `me.m4a`・`others.m4a`、Windows は `me.wav`・`others.wav`）のうち 1 つ以上が開けて長さが 0 より大きい、状態が「記録中」「処理中」ではない、その会議を作り直していない・議事録を作り直していない、そのアプリで記録・後処理をしていない。状態（失敗・完了）では決めない。
  - 押すと、使うエンジンを書いた確かめを出す（「今の設定（%@）で文字起こしし、話者を分け、議事録を作ります。」。Gemini なら「会議の音声を Google に送ります。」を足す）。OK を押したときだけ始める。
  - 始める前に、記録を始めるときと同じ準備の確かめ（Whisper のモデル・Gemini の認証・Mac 標準なら音声認識の許可）をする。通らなければ、会議を変えずに、記録を始めるときと同じ文で理由を出す。
  - 作り直している間は、その会議の帯（Mac）・操作の欄（Windows）に進み具合（文字起こし → 話者分離 → 議事録）を出す。その会議は一覧の「記録中」には移らない。その間は新しい記録を始められない（Mac はメニューを押せなくし、Windows は始めようとすると理由を出す）。作り直しは途中でやめられない。
  - 終わると、発言・話者・議事録が入り、エラーの文は「記録の途中で…」から作り直しの結果に置き換わる（問題がなければ消える）。両方のチャンネルとも文字起こしできず発言が 0 件なら、状態は「失敗」のままで、エラーの文に理由を書き、ボタンはまた出る（もう一度押せる）。片方だけ文字起こしできなければ、状態は「完了」、エラーの文にそのチャンネルを書く（記録を止めたあとと同じ）。
  - 2 つの録音の時刻はそろう（記録中に保存した先頭のずれを使う）。メモ・「ここ重要」の印・オフレコは残る。終わっていないオフレコの区間は、録音の終わりで閉じる。会議の長さは、残った録音の終わり（先頭のずれ＋長さの大きいほう）にする。
  - 作り直した会議の録音は、「文字起こしのあとに録音を削除」がオンの会議でも消さない（REQ-MTG-010 の「記録中・処理中にアプリが終わった会議は録音を残し」のとおり）。不要なら「録音を削除…」で消す。
  - 開ける録音が 1 つもない会議（この機能より前に落ちた会議、記録を始める途中で失敗した会議、ほかの OS で記録した会議など）には、ボタンを出さない。
  - 記録中に録音の書き出しが失敗しても（ディスクがいっぱいなど）、記録・文字起こし・停止は固まらない。書けなかったことは、止めたあとのエラーの文に出す。
- 出典: 2026-11-13 の依頼「録音していたら以下のエラーが出たので確認調査して修正して」の調査で分かった録音の消失と、同日の「このタスクをここで実行してください：「Make meeting audio survive an app crash (Mac)」」。同日に範囲・対象・終了のときの振る舞い・エンジンの見せ方を選んでもらった（了承の日付を足す）
- 対象: Mac / Windows
- 実装の場所（予定）: Mac は `MeetingAudioWriter`（新規）、`ChannelTranscriber`、`MeetingRecorder.recoverFromAudio`・`closeForTermination`、`MeetingRecovery`（新規）、`AppDelegate.applicationShouldTerminate`、`MeetingStatusBanners`、`MeetingMoreMenuItems`。Windows は `WavStreamWriter.RepairHeader`（新規）、`MeetingRecovery`（新規、Core）、`MeetingController.RecoverFromAudioAsync`（新規）、`MeetingWindow`
- 確かめ方: `--test-meeting-audio-crash`・`--test-meeting-recovery`・`--meeting-recover-files`（Mac、新規）、`dotnet test Hanasu.Core.Tests`（Windows、足すテスト）、実機で記録中に `kill -9`・⌘Q して作り直す

### 変える要件（ユーザーの合意が要る）

- なし。REQ-MTG-010（作り直した会議も録音を残す）・REQ-MTG-023（Gemini で音声を送ることは、今も「食い違い（ユーザーの確認待ち）」のまま。作り直しでは押す前に確かめる）・DEC-MTG-018（落ちた会議を起動時に「失敗」にする）はそのまま。

### 直す設計判断（spec の文を今の作りに合わせる）

- DEC-MTG-017（Mac の録音の形式）: 「AAC」に、断片化した m4a（DEC-MTG-156）を足す。
- DEC-MTG-018: 「それまでの録音・文字起こしは保存する」の「文字起こし」は Mac では今も保存されない。「録音は残り、REQ-MTG-128 で作り直せる」に直す。
- DEC-MTG-131（「…」のメニューの項目）: 「録音から文字起こしと議事録を作る」を足す。
- DEC-MTG-136（処理の段階）: 作り直しでは、Mac 標準でも「文字起こし」の段階を出すことを足す。
- DEC-MTG-143（保存期間で消すとき）: 作り直しのあとは消さない（作り直しの後処理では保存期間の削除を呼ばない）ことを足す。

## 設計判断の案

### DEC-MTG-156 Mac の会議の録音は、2 秒ごとに断片を閉じる m4a で、専用のキューで書く

- 決めたこと: `ChannelTranscriber` の音声ファイルの書き出しを、`AVAudioFile` から `MeetingAudioWriter`（新規）に替える。`MeetingAudioWriter` は `AVAssetWriter`（`fileType: .m4a`、`movieFragmentInterval` 2 秒、AAC 32 kbps、標本化周波数・チャンネル数は今と同じ）で書き、時刻は 0 から始める（先頭に空きを入れない。ずれは今までどおり `audioStartOffsets` に持つ）。`ChannelTranscriber` のキューでは PCM のバッファを写して `MeetingAudioWriter` の専用のキューに渡すだけにし、文字起こしへの受け渡しと音量の測定を待たせない。専用のキューでは、`expectsMediaDataInRealTime` を false にして、書き手の準備ができるまで（`status == .writing` の間だけ、1 回あたり最大 1 秒）待ってから書く。書き手が失敗した（`.failed`・待ちの上限・まだ書いていない音が 30 秒ぶんを超えた）ら、そこで書くのをやめ（溜めた音は捨てる）、ログに書き、`ChannelTranscriber` に「録音の一部を書けなかった」印を立てる。止めたあと（`stop`）にその印があれば、エラーの文に「録音の一部を書けませんでした（%@）。」を足す。`finish`・`cancel` は `finishWriting` を待ってから返す（待つのは最大 5 秒）。ファイルの名前と拡張子は変えない。
- 理由: 断片化した m4a は、落ちても最後に閉じた断片まで読める。今のファイルを読むところ（再生・話者分離・Whisper / Gemini・スリープの切り詰め・書き出し）はそのまま読める（手元の実験）。非圧縮（CAF）なら全部残るが、2 時間で 1 チャンネル約 230 MB になり、止めたとき・落ちたあとの変換も要る。断片の間隔は、失う長さ（最大約 2 秒）と大きさ（1 秒で約 5%、5 秒で約 3% 増える）の間を取った。準備が間に合わないときに捨てると音が欠けるので待つが、書き手が失敗したまま待ち続けると、文字起こしと停止まで固まる（`ChannelTranscriber` のキューは `queue.sync` で読まれる）ので、書き出しのキューを分け、待ちに上限を付ける。
- 関係する要件: REQ-MTG-128, REQ-MTG-002, REQ-MTG-010
- 対象: Mac

### DEC-MTG-157 2 つの録音の先頭のずれは、分かった時点で保存する

- 決めたこと: Mac: `ChannelTranscriber` の先頭のずれ（`timeOffset`）を、音量と同じく `levelLock` で読める口（`knownStartOffset`）にする（メインスレッドから `queue.sync` しない）。`MeetingRecorder.updateLevels`（0.25 秒ごと、メインスレッド）で、まだ保存していないチャンネルのずれが分かったら `current.audioStartOffsets` に入れて `meeting.json` に保存する（1 回の記録で多くて 2 回）。Windows: `MeetingController.StartAsync` で UI のスレッドの `SynchronizationContext` を取っておき、記録中だけ 1 秒ごとのタイマーで `PersistStartOffsetsIfKnown()`（新規、public）をその文脈に送って呼ぶ。メモ・オフレコの保存（`AddNoteCore`・`ToggleOffRecord`）と同じ UI のスレッドで `Current` を書き換えて保存するので、同時に書かない。テストは `PersistStartOffsetsIfKnown()` を直接呼ぶ。止めたときの保存は、両方とも今までどおり。
- 理由: 落ちた会議を録音から作り直すとき、2 つの録音の時刻をそろえるのに要る（DEC-MTG-135 と同じ値）。相手側の音は会議の音が鳴り始めてから届くので、ずれは 0 でないことが多い。
- 関係する要件: REQ-MTG-128
- 対象: Mac / Windows

### DEC-MTG-158 録音から作り直すのは、ボタンを押して確かめたときだけ。今の設定のエンジンで、記録を止めたあとと同じ処理をする

- 決めたこと:
  - ボタンを出す条件・会議の長さ・終わっていないオフレコの閉じ方は、純粋な関数 `MeetingRecovery`（Mac は Swift、Windows は Core の C#。同じ決まり）に置く: `canRecover(meeting:, readableAudioSeconds: [MeetingChannel: Double], busy: Bool)`、`duration(offsets:, audioSeconds:)`、`closeOpenOffRecord(_:, at:)`。Mac は、開ける録音の長さを `AVAudioFile` で測り、会議の ID とファイルの更新日時ごとに覚えておく（帯を描くたびに開かない）。
  - 押すと、使うエンジン（押した時点の設定）を書いた確かめを出し、OK で始める。始める前に `checkReady` と権限の確かめ（Mac 標準なら音声認識だけ。マイクと画面収録は要らない）をし、通らなければ会議を変えずに理由を出す。
  - Mac: `MeetingRecorder.recoverFromAudio(_:)`。状態が待機のときだけ動く。`recoveringID` にその会議の ID を入れ、状態を「処理中」にする（`current` には入れない。一覧の「記録中」に移らない）。エラーの文を消し、長さとオフレコを `MeetingRecovery` で直して保存し、文字起こしする。Mac 標準は、録音を `ChannelTranscriber`（`fileURL: nil`、`fixedTimeOffset` に保存したずれ）に流す。流すときは 10 秒ぶんごとに、文字起こしへの受け渡しが追いつくのを待つ（2 時間の録音をメモリに積まない）。この流し方は関数にまとめ、`--meeting-files` の Mac 標準でも使う。Whisper / Gemini は `transcribeRecordedAudio`。そのあと `process` に、作り直しであることを伝える引数（`recovering: true`）を付けて呼ぶ。`process` は、作り直しのときは、(1) 両方のチャンネルとも失敗して発言が 0 件なら状態を「失敗」にし、(2) 録音を消さない。終わったら `recoveringID` を外し、状態を待機に戻す。
  - Windows: `MeetingController.RecoverFromAudioAsync(Meeting)`。`State` が `Idle` で、記録・作り直しをしていないときだけ動く。`recovering`（`regenerating` と同じく会議の ID の集まり）に入れ、`Current` と `State` は変えない（一覧の先頭の「記録中」に移らない）。作り直しの間は `StartAsync` が理由（`Notice`）を出して始めない。WAV のヘッダーを直し（DEC-MTG-159）、`MeetingRecovery` を当てて保存し、`ProcessAsync` と同じ組み立て（`CreatePostProcessor(settings)` に切り出す）の `MeetingPostProcessor` に、録音を消さない指定（`KeepAudio = true`、新規）を付けて渡す。進み具合は `IProgress<string>` で会議ノートの `ActionStatus` に出す（議事録の作り直しと同じ）。終わっても保存期間の削除（`PruneExpiredAudio`）は呼ばない。
- 理由: 起動のたびに勝手に動かすと、別の会議の記録中や、外出先で AI に音声を送ることになる。会議には記録したときのエンジンが残らないので、押した時点の設定で行い、送り先を押す前に見せる（ユーザーの選択、2026-11-13）。`current` / `Current` に入れると、一覧の「記録中」に昔の会議が出る。作り直しの結果は、落ちた分の欠けがある唯一の録音から作るので、エンジンを替えてやり直せるよう録音は残す（REQ-MTG-010 の今の文のとおり）。両方失敗したら「失敗」のままにして、ボタンが消えないようにする。
- 関係する要件: REQ-MTG-128, REQ-MTG-054, REQ-MTG-010, REQ-MTG-023
- 対象: Mac / Windows

### DEC-MTG-159 Windows は、作り直す前に WAV のヘッダーを直す

- 決めたこと: `WavStreamWriter.RepairHeader(string path)`（新規）で、ファイルの長さから data の長さ（2 バイト単位に切り下げ）を計算し直し、RIFF と data の長さを書き直す（`Truncate` と同じ計算）。`MeetingController.RecoverFromAudioAsync` が、後処理の前に 2 つの WAV に当てる。ヘッダーが正しいファイルは変わらない。
- 理由: 落ちた WAV はヘッダーの長さが最大約 5 秒古く、`WavFile.Decode` はヘッダーより後ろを読まない。最初の 5 秒で落ちると長さが 0 で、チャンネルごと無音として飛ばされる。録音の書き方（5 秒ごとの書き直し）は変えない。
- 関係する要件: REQ-MTG-128
- 対象: Windows

### DEC-MTG-160 Mac で記録中に終了するときは確かめ、録音を閉じてから終わる

- 決めたこと: `AppDelegate.applicationShouldTerminate` で、会議を記録中（`MeetingRecorder.state == .recording`）なら、終わる理由を `NSAppleEventManager` の今のイベントの `kAEQuitReason` で見る。ログアウト・再起動・システム終了なら確かめない。それ以外（⌘Q・メニュー）なら `NSAlert`（「会議を記録中です。終了しますか？」「記録は止まり、次に起動したときに録音から文字起こしと議事録を作れます。」、ボタン「終了」「キャンセル」）で確かめる。終わるときは `.terminateLater` を返し、`MeetingRecorder.closeForTermination()`（新規。音声の取り込みを止め、2 つの `ChannelTranscriber` の書き出しを閉じる。最大 5 秒）を待ってから `reply(toApplicationShouldTerminate: true)` する。会議の状態は「記録中」のままにし、次の起動で `markInterruptedMeetings` が「失敗」にする。記録を止めたあとの処理中（`.processing`）・作り直し中の終了は、今までどおり確かめない（処理は失われ、起動時に「失敗」になる。録音は閉じてある）。
- 理由: 落ちるより、記録中に普通に終了するほうが起きやすい。Windows は記録中の終了を確かめる（DEC-MTG-109）。終了の前に後処理（文字起こし・議事録）まで待つと何分もかかるので、録音を閉じるだけにして、作り直しのボタンに任せる（ユーザーの選択、2026-11-13）。ログアウト・再起動を止めると、システムの終了を妨げる。
- 関係する要件: REQ-MTG-128
- 対象: Mac

## やらないこと

- この機能より前に落ちた会議の、開けない m4a の修復。2026-11-13 10:00 の会議の録音も戻らない（ユーザーの選択「試さない」）。
- 記録中の文字起こし（確定した発言）を記録中に保存すること（範囲の質問で選ばれなかった）。
- 落ちたことを起動時に知らせる通知・ダイアログ。会議ノートの一覧の「失敗」と、選んだときのボタンで分かる。→ roadmap に FUT-209 として足す。
- 作り直しを途中でやめること。→ FUT-210。
- 片方のチャンネルだけ文字起こしできなかった会議（発言が 1 件以上）で、欠けたチャンネルだけを録音から文字起こしし直すこと。→ FUT-211。
- スリープしたまま落ちた会議の、スリープより後の録音の切り詰め（DEC-MTG-088 は止めたときだけ）。作り直すと、スリープの後に録った分も入る。→ FUT-212。
- 会議に、記録したときの文字起こしのエンジンを残すこと（作り直しは押した時点の設定で、押す前に見せる）。
- 音声入力の履歴の録音（`DictationHistory` の m4a）。短いので今のまま。
- 処理の途中（話者分離・議事録の作成中）に落ちた会議で、発言がもう保存されているもの。今までどおり「議事録を作り直す」で足りる。
- Mac で、Windows で記録した会議（`me.wav`）を作り直すこと、またはその逆。

## 手順

1. spec（`docs/spec/meeting.md`）に REQ-MTG-128 と DEC-MTG-156〜160 を書き、「直す設計判断」の 5 つを直す。roadmap に FUT-209〜212 を足す。
2. Mac の録音の書き出し: `MeetingAudioWriter`（新規、`Sources/Hanasu/MeetingAudioWriter.swift`）を作り、`ChannelTranscriber.makeFile`・`append`・`finish`・`cancel` を替える。書けなかった印と、`levelLock` で読むずれ（`knownStartOffset`）を足す。タグ: REQ-MTG-128、DEC-MTG-156、DEC-MTG-157。
3. Mac の先頭のずれの保存: `MeetingRecorder.updateLevels`。止めたあとのエラーの文（書けなかった録音）: `MeetingRecorder.stop`。
4. Mac の作り直し: `MeetingRecovery`（新規、`Sources/Hanasu/MeetingRecovery.swift`）、`MeetingRecorder.recoverFromAudio`・`recoveringID`、`process` の `recovering` 引数、ファイルを流す関数（`ChannelTranscriber` に流す。`--meeting-files` も使う）。タグ: REQ-MTG-128、DEC-MTG-158。
5. Mac の終了: `AppDelegate.applicationShouldTerminate`、`MeetingRecorder.closeForTermination`。タグ: DEC-MTG-160。
6. Mac の画面: `MeetingStatusBanners` のエラーの帯にボタン、作り直し中の帯（`.recovering`。`ProcessingStagesView`）、`MeetingMoreMenuItems` に項目、押したときの確かめ（`NSAlert` か `confirmationDialog`）。
7. Windows（手順 2〜6 と触るファイルが重ならない）:
   - `WavStreamWriter.RepairHeader`（DEC-MTG-159）。
   - `MeetingRecovery`（新規、`windows/Hanasu.Core/Meetings/MeetingRecovery.cs`）。
   - `MeetingController`: `PersistStartOffsetsIfKnown` とタイマー（DEC-MTG-157）、`CreatePostProcessor` の切り出し、`RecoverFromAudioAsync`・`recovering`、`StartAsync` の作り直し中の断り（DEC-MTG-158）。`MeetingPostProcessor` に `KeepAudio` と、作り直しの進み具合のための段階の文。
   - `MeetingWindow.xaml(.cs)`: `ActionsPanel` の「議事録を作り直す」の隣に `RecoverButton`。`Show(Meeting?)` で出すかを決め、押したら確かめ（`MessageBox`）を出して `meetings.RecoverFromAudioAsync` を呼ぶ。
   - テスト（`Hanasu.Core.Tests`。`// 確かめ方: REQ-MTG-128` に当たるコメントを付ける）: ヘッダーの直し（長さ 0・古い長さ・正しい長さ）、`MeetingRecovery` の条件（m4a だけの会議・0 秒の WAV・発言あり・処理中は出さない）と長さとオフレコ、`PersistStartOffsetsIfKnown` でずれが保存されること、偽の文字起こしで落ちた会議を作り直すと「完了」になり発言・長さ・閉じたオフレコが入り録音が残ること、両方失敗なら「失敗」のままでもう一度作り直せること、作り直しの間は `StartAsync` が始めないこと。
8. UI の文字列を 17 言語で入れる（i18n スキル。i18n エージェントに言語を分けて任せる）。Mac は `tr(...)` と `python3 scripts/i18n-strings.py sync`、Windows は `Hanasu.Windows/Properties/Strings*.resx`（と進み具合の文は `Hanasu.Core/Properties/Strings*.resx`）で `scripts/i18n-resx.py check`。足す文字列（Mac と Windows で同じ意味）: ボタン「録音から文字起こしと議事録を作る」、説明「残った録音から、文字起こし・話者の区別・議事録を作ります」、確かめの見出し「録音から作り直しますか？」、本文「今の設定（%@）で文字起こしし、話者を分け、議事録を作ります。」、Gemini のときの足し書き「会議の音声を Google に送ります。」、作り直し中の見出し「録音から作り直しています」、Windows の断り「録音から作り直している間は、記録を始められません。」、書けなかった録音のエラー「録音の一部を書けませんでした（%@）。」、Mac の終了の確かめの見出し「会議を記録中です。終了しますか？」と本文「記録は止まり、次に起動したときに録音から文字起こしと議事録を作れます。」、ボタン「終了」（既存があれば使う）。
9. 自己テストの CLI を足す（下）。UI のテスト項目を `common/testdata/ui/meeting.json` に足し、`python3 scripts/ui-cases.py md`・`check`。`docs/design/meeting.md`・`windows/README.md`（差の表と 174〜175 行目）・`docs/verification/meeting.md` を直す。この計画の状態を「実装済み」にして、spec へのリンクを置く。

## 確かめ方

- `swift build`、`python3 scripts/check-spec.py`、`python3 scripts/check-i18n.py`
- `.build/debug/Hanasu --test-meeting-audio-crash`（新規。`// 確かめ方: REQ-MTG-128`）: 自分自身を子のプロセスとして起動し、一時フォルダに本物の `ChannelTranscriber`（書き出しだけ、`live: false`）で実時間で 10 秒書いたところで、親が `kill -9` する。同じことを SIGTERM でもする。残ったファイルが `AVAudioFile`・`AVURLAsset`（長さ）・`TranscriptionAudio.loadSamples` で読めて、どれも 7 秒以上あることを確かめる。正常に `finish` したファイルも同じ 3 つで全部の長さを読めること、途中に移って読めることを確かめる。書き手を失敗させた場合（書き込み先のフォルダを消す）に、`append` と `finish` が 5 秒以内に戻り、書けなかった印が立つことも確かめる。
- `.build/debug/Hanasu --test-meeting-recovery`（新規）: `MeetingRecovery` のボタンを出す条件（発言 0 件・開ける録音・処理中・作り直し中・ほかの OS の録音だけ・0 秒の録音の組み合わせ）、長さ（先頭のずれ＋録音の長さの大きいほう）、終わっていないオフレコの閉じ方。
- `.build/debug/Hanasu --meeting-recover-files <自分の音声> <相手の音声> [--me-offset 秒] [--others-offset 秒] [--engine apple|whisper|gemini]`（新規）: `--meeting-files` と同じく保存先に新しい会議を作り、音声を `MeetingAudioWriter` で書き、メモとオフレコ（終わっていないもの）を入れて「失敗」にした（落ちた会議と同じ形）うえで `recoverFromAudio` を当て、状態・発言・長さ・オフレコ・録音が残ることを出す。`say` で作った音声で確かめる。
- `--render-meeting-window` に、落ちた会議（失敗・録音あり・発言 0 件）の帯と、作り直し中の帯を足して描き、ボタンと進み具合が出ることを見る（UI のテスト項目）。
- `cd windows && dotnet test Hanasu.Core.Tests`（手順 7 のテスト）
- 実機（Mac）: 開発版で会議の記録を始め、両方に声が入る状態で 1 分ほどしてから `kill -9`。起動し直して、会議ノートでボタンを押し、確かめにエンジン名が出ること、文字起こし・話者・議事録ができること、再生で 2 つの録音の時刻がそろうこと、メモと印が残ることを見る。記録中に ⌘Q して確かめが出ること、「終了」で終わったあと録音が開けることも見る。
- 実機（Windows）: Windows の機械で同じことをしてもらう（この Mac では確かめられない）。

## 敵対的レビュー

2026-11-13、requirements-reviewer（Opus）2 つ並べて（A: 観点 1〜3・10・11、B: 観点 4〜9）、1 回。同じ指摘は 1 つにまとめた。

| # | 重さ | 指摘 | 仕分け | どうしたか |
| --- | --- | --- | --- | --- |
| 1 | 致命 | Mac の `process` は必ず「完了」にするので、作り直しで失敗するとボタンが消えてやり直せない（A1・B1） | 直す | ボタンの条件を状態でなく「発言 0 件・開ける録音」にし、作り直しで両方失敗したら「失敗」のままにする（DEC-MTG-158） |
| 2 | 重大 | 作り直しのあとに録音を消すと REQ-MTG-010 の今の文と食い違う（A5・B2） | 直す | 作り直した会議は録音を消さない（今の要件の文のとおり）。要件は変えない |
| 3 | 重大 | 書き手の準備を `ChannelTranscriber` のキューで待つと、失敗したときに文字起こし・停止・メインスレッドが固まる（A2・B3） | 直す | 書き出しを専用のキューに分け、待ちに上限、失敗したら書くのをやめて印を立てる。ずれは `levelLock` で読む（DEC-MTG-156・157） |
| 4 | 重大 | 押す前の準備の確かめ（`checkReady`・権限）がない（A3・B7） | 直す | 始める前に確かめ、通らなければ会議を変えずに理由を出す |
| 5 | 重大 | Mac は ⌘Q・ログアウト・再起動でも録音を失う（A4） | 聞く | ユーザーの答え「確かめてから録音を閉じる」を DEC-MTG-160 にした。SIGTERM も確かめ方に入れた |
| 6 | 重大 | 今の設定が Gemini だと、Mac 標準で記録した会議の音声を知らずに送る（A7・B7） | 聞く | ユーザーの答え「押したら確かめる」を受け入れ条件と DEC-MTG-158 に入れた。理由も書き直した |
| 7 | 重大 | Windows の「メモの保存と同じ排他」は存在しない（B4） | 直す | ずれの保存を UI のスレッド（`SynchronizationContext`）で行う。テストは public の口を直接呼ぶ |
| 8 | 重大 | 「開ける録音」が、ほかの OS の会議・記録の開始に失敗した会議で崩れる（B5、A9） | 直す | その OS が読む拡張子で、長さが 0 より大きいものに限る。テストに足した |
| 9 | 重大 | `current` / `Current` に入れると、昔の会議が一覧の「記録中」に出る（B6） | 直す | Mac は `recoveringID`、Windows は `recovering` で持ち、`current` / `Current` は使わない |
| 10 | 軽微 | 作り直しはやめられず、その間は記録を始められない（A6） | 直す | 受け入れ条件とやらないこと（FUT-210）に書いた。Windows は始めようとすると理由を出す |
| 11 | 軽微 | 確かめ方が、落ちたファイルの読み方の一部（`AVURLAsset`・`loadSamples`）を見ていない。書く速さが書かれていない（A8） | 直す | `--test-meeting-audio-crash` に足し、実時間で書くとした |
| 12 | 軽微 | Mac の `process` はエラーの文を消さない（A9） | 直す | `recoverFromAudio` が始めに消すとした |
| 13 | 軽微 | `--meeting-files` の流し方は、2 時間の録音をメモリに積む（A9・B8） | 直す | 10 秒ごとに追いつくのを待つ関数にまとめる |
| 14 | 軽微 | ツールチップの文が条件と合わない（A9） | 直す | 「残った録音から、文字起こし・話者の区別・議事録を作ります」にした |
| 15 | 軽微 | 落ちたことを起動時に知らせない・今朝の録音を戻さない、をユーザーに聞いていない（A9） | 聞く／直す | 今朝の録音はユーザーの答え「試さない」。起動時の知らせはやらないことに書き、FUT-209 にした |
| 16 | 軽微 | DEC-MTG-017・018・131・136 の直しが手順にない（B8） | 直す | 「直す設計判断」と手順 1 に入れた |
| 17 | 軽微 | 保存期間の削除が OS で違う（Windows は `ProcessAsync` のあとに消す）（B8） | 直す | 作り直しでは両方とも呼ばない。DEC-MTG-143 に足す |
| 18 | 軽微 | 文字列が 2 つでは足りない（B8） | 直す | 手順 8 に全部を書いた |
| 19 | 軽微 | Windows の受け入れ条件が Mac の見た目で書かれている（B8） | 直す | ボタンの場所と進み具合の場所を OS ごとに書き分けた |
| 20 | 軽微 | 最初の 2 秒で落ちた場合の下限がない（B8） | 直す | 受け入れ条件を「記録を始めて 5 秒より後」にした |
| 21 | 軽微 | 書き出しの時刻を `timeOffset` から始めると、ずれが二重になる（B8） | 直す | 時刻は 0 から始めると DEC-MTG-156 に書いた |
| 22 | 軽微 | 確かめ方のタグ・Windows のタイマーの差し替え・Mac の作り直しの流れの自己テストがない（B8） | 直す | タグを手順に入れた。Windows は public の口を直接呼ぶ。Mac は `--meeting-recover-files` を足した |
| 23 | 軽微 | スリープしたまま落ちた会議の穴を FUT にしていない（B8） | 直す | FUT-212 にした |

見られなかったこと: DEC-MTG-160（Mac の記録中の終了）は、2 回目の質問の答えを受けてレビューのあとに足したので、レビューを受けていない。`AVAssetWriter` が `.failed` のときと SIGTERM で終わったときの振る舞いは、どちらのレビュアーも動かして確かめていない。実装の最初に `--test-meeting-audio-crash` で確かめ、計画と違えばここに戻る。

## 仮に決めたこと

- 断片の間隔は 2 秒。落ちたときに失うのは最大で約 2 秒と、書き手が待っている分。
- 書き手が待つ上限は 1 回 1 秒、溜める上限は 30 秒ぶん、閉じるのを待つ上限は 5 秒。
- Windows の録音の書き方（5 秒ごとのヘッダーの書き直し）は変えない。落ちたときに失うのは、`FileStream` の中にあってまだ書かれていない分だけ（ヘッダーは作り直すときに直す）。
- 片方のチャンネルだけ文字起こしできなかったときは、記録を止めたあとと同じく「完了」でエラーの文に書く（そのあとボタンは出ない。FUT-211）。
