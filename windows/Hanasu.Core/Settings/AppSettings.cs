using System.Text.Json.Serialization;
using Hanasu.Core.Text;

namespace Hanasu.Core.Settings;

[JsonConverter(typeof(JsonStringEnumConverter<RecordingMode>))]
public enum RecordingMode
{
    /// <summary>押すたびに開始／停止</summary>
    Toggle,
    /// <summary>押している間だけ録音</summary>
    PushToTalk,
}

[JsonConverter(typeof(JsonStringEnumConverter<TranscriptionEngine>))]
public enum TranscriptionEngine
{
    /// <summary>Windows 標準の音声認識（Windows.Media.SpeechRecognition）。既定</summary>
    Windows,
    /// <summary>Whisper（whisper.cpp）。端末の上で動かす</summary>
    Whisper,
    /// <summary>録った音声を Gemini に送って文字起こしする</summary>
    Gemini,
}

[JsonConverter(typeof(JsonStringEnumConverter<GeminiAuthMode>))]
public enum GeminiAuthMode
{
    /// <summary>API キー（Google AI Studio）</summary>
    ApiKey,
    /// <summary>サービスアカウント（Vertex AI）</summary>
    ServiceAccount,
}

/// <summary>入力できる場所がなくて貼り付けなかったとき、クリップボードをどうするか（REQ-DIC-081）</summary>
[JsonConverter(typeof(JsonStringEnumConverter<PasteFallbackClipboard>))]
public enum PasteFallbackClipboard
{
    /// <summary>結果をクリップボードに入れたままにする。貼りたい場所で Ctrl+V を押すだけで済む（既定。DEC-DIC-122）</summary>
    KeepResult,
    /// <summary>結果は画面に表示するだけにして、クリップボードは元のままにする（表示の「コピー」で写す）</summary>
    RestoreOriginal,
}

// 要件: REQ-DIC-082
// 設計判断: DEC-DIC-200
/// <summary>
/// 音声入力の AI による整形の出力の言語（Mac 版の GeminiClient.RefineOutputLanguage と同じ）。
/// 統一の先はプロンプトの言語（PromptLanguage.Current）で、言語は保存しない
/// </summary>
[JsonConverter(typeof(RefineOutputLanguageJsonConverter))]
public enum RefineOutputLanguage
{
    /// <summary>話した言語（既定）。ほかの言語で話した部分はそのまま残し、訳さない</summary>
    AsSpoken,
    /// <summary>プロンプトの言語に統一する。ほかの言語で話した部分もその言語にする。settings.json の値は前の版の Japanese のまま（DEC-DIC-201）</summary>
    Unified,
}

// 設計判断: DEC-DIC-201
/// <summary>
/// 整形の言語を settings.json に書く・読む。「統一する」は、日本語に固定していた版の値 "Japanese" のまま書く
/// （前の版に戻しても読める。知らない値で JsonException になると、設定全体が初期値に戻るため）。
/// 知らない値は「話した言語」として読む
/// </summary>
public sealed class RefineOutputLanguageJsonConverter : JsonConverter<RefineOutputLanguage>
{
    /// <summary>「統一する」を保存する値</summary>
    public const string UnifiedStoredValue = "Japanese";

    public override RefineOutputLanguage Read(ref System.Text.Json.Utf8JsonReader reader, Type typeToConvert, System.Text.Json.JsonSerializerOptions options) =>
        reader.TokenType == System.Text.Json.JsonTokenType.String && reader.GetString() == UnifiedStoredValue
            ? RefineOutputLanguage.Unified
            : RefineOutputLanguage.AsSpoken;

    public override void Write(System.Text.Json.Utf8JsonWriter writer, RefineOutputLanguage value, System.Text.Json.JsonSerializerOptions options) =>
        writer.WriteStringValue(value == RefineOutputLanguage.Unified ? UnifiedStoredValue : nameof(RefineOutputLanguage.AsSpoken));
}

/// <summary>文章の処理（整形・英訳・議事録）に使う AI</summary>
[JsonConverter(typeof(JsonStringEnumConverter<TextAiProvider>))]
public enum TextAiProvider
{
    /// <summary>Gemini（既定。今までどおり）</summary>
    Gemini,
    /// <summary>Claude（Anthropic の Claude API。API キーで使う）</summary>
    Claude,
    /// <summary>端末の中で動く小型の LLM（llama.cpp の llama-server。REQ-COM-030）</summary>
    Local,
}

/// <summary>
/// 設定。<c>%APPDATA%\Hanasu\settings.json</c> に JSON で保存する（<see cref="SettingsStore"/>）。
/// 会議の記録の設定もここに足していく（Mac 版の AppSettings と同じく 1 か所にまとめる）。
/// </summary>
public sealed class AppSettings
{
    public static readonly IReadOnlyList<string> SuggestedModels = ["gemini-3.5-flash-lite", "gemini-3.8-flash", "gemini-flash-latest"];

    // 一般
    public HotKeyCombo HotKey { get; set; } = HotKeyCombo.DefaultDictation;
    /// <summary>話した内容を翻訳して入力するショートカット（翻訳の言語は TranslationLanguages の最初）</summary>
    public HotKeyCombo TranslateHotKey { get; set; } = HotKeyCombo.DefaultTranslate;
    // 要件: REQ-DIC-013
    // 設計判断: DEC-DIC-027
    /// <summary>翻訳の言語（1 つ以上。並びは TranslationLanguages.All の順）。既定は English だけ。読み込むときに SettingsStore.Normalize で直す</summary>
    [JsonConverter(typeof(Dictation.TranslationLanguagesJsonConverter))]
    public Dictation.TranslationLanguage[] TranslationLanguages { get; set; } = [Dictation.TranslationLanguage.English];
    /// <summary>「翻訳して入力」で始める言語（選んだ言語のうち最初）</summary>
    [JsonIgnore]
    public Dictation.TranslationLanguage PrimaryTranslationLanguage => Dictation.TranslationLanguages.Normalize(TranslationLanguages)[0];
    public RecordingMode RecordingMode { get; set; } = RecordingMode.Toggle;
    /// <summary>録音に使うマイクの ID（WASAPI のエンドポイント ID）。空なら Windows の既定のマイク</summary>
    public string MicrophoneDeviceId { get; set; } = "";
    public TranscriptionEngine Engine { get; set; } = TranscriptionEngine.Windows;
    /// <summary>Whisper のモデル（<see cref="Transcription.WhisperModelCatalog"/> の Id）</summary>
    public string WhisperModel { get; set; } = "small";
    /// <summary>
    /// 文字起こしの言語。設定のファイルがないとき（初めて起動したとき）は Windows の表示の言語（SettingsStore.Load。REQ-COM-004）。
    /// 前の版で保存した設定にこの項目がなければ ja-JP（前の版の既定）
    /// </summary>
    public string LocaleIdentifier { get; set; } = "ja-JP";
    public bool PlaySounds { get; set; } = true;
    // 要件: REQ-REL-010
    // 設計判断: DEC-REL-024
    /// <summary>起動したときに、新しい版がないか確かめる</summary>
    public bool CheckForUpdatesOnLaunch { get; set; } = true;
    // 設計判断: DEC-REL-022
    /// <summary>「この版をスキップ」を選んだ版（例 "1.6.0"）。起動時の確認ではこの版を知らせない。空ならスキップなし</summary>
    public string SkippedUpdateVersion { get; set; } = "";
    // 要件: REQ-DIC-081
    // 設計判断: DEC-DIC-122
    /// <summary>入力できる場所がなくて貼り付けなかったとき、結果をクリップボードに入れたままにするか</summary>
    public PasteFallbackClipboard PasteFallbackClipboard { get; set; } = PasteFallbackClipboard.KeepResult;

    // 音声入力の履歴（設定の「履歴」タブ）
    // 要件: REQ-DIC-063
    // 設計判断: DEC-DIC-073, DEC-DIC-074
    /// <summary>履歴をファイルに保存する（オフのときは、メモリ上に直近 10 件だけ置く）</summary>
    public bool HistoryEnabled { get; set; } = true;
    /// <summary>残す件数の上限（HistoryPolicy.CountOptions）</summary>
    public int HistoryMaxCount { get; set; } = 1000;
    /// <summary>残す日数（HistoryPolicy.DayOptions。0 は無期限）。既定は 30 日</summary>
    public int HistoryMaxDays { get; set; } = 30;

    // AI（文章の処理）。音声入力（整形・英訳）と会議（議事録）で、AI とモデルを別々に選ぶ（REQ-COM-024）
    /// <summary>AI で整形する（名前は前の版のまま。Gemini と Claude のどちらでも使う）</summary>
    public bool RefineWithGemini { get; set; } = true;
    // 要件: REQ-DIC-082
    /// <summary>整形の出力の言語（設定の「AI」→「整形の言語」）。既定は話した言語</summary>
    // 設計判断: DEC-DIC-201（SettingsStore.JsonOptions の JsonStringEnumConverter より先に使うよう、プロパティに付ける）
    [JsonConverter(typeof(RefineOutputLanguageJsonConverter))]
    public RefineOutputLanguage RefineOutputLanguage { get; set; } = RefineOutputLanguage.AsSpoken;
    /// <summary>音声入力の整形・英訳に使う AI</summary>
    public TextAiProvider DictationAi { get; set; } = TextAiProvider.Gemini;
    /// <summary>会議の議事録（作り直しを含む）に使う AI</summary>
    public TextAiProvider MeetingAi { get; set; } = TextAiProvider.Gemini;
    /// <summary>音声入力の整形・英訳に使う Claude のモデル（REQ-COM-023）</summary>
    public string ClaudeModel { get; set; } = Claude.ClaudeModels.DefaultModel;
    /// <summary>議事録に使う Claude のモデル（REQ-COM-023）</summary>
    public string ClaudeMinutesModel { get; set; } = Claude.ClaudeModels.DefaultMinutesModel;
    // 要件: REQ-COM-030
    // 設計判断: DEC-COM-067
    /// <summary>ローカルを選んだときの、音声入力のモデル（LocalLlmModel の Id）</summary>
    public string LocalDictationModel { get; set; } = LocalLlm.LocalLlmModel.DefaultDictation.Id;
    /// <summary>ローカルを選んだときの、議事録のモデル</summary>
    public string LocalMeetingModel { get; set; } = LocalLlm.LocalLlmModel.DefaultMeeting.Id;

    // Gemini
    public GeminiAuthMode AuthMode { get; set; } = GeminiAuthMode.ApiKey;
    /// <summary>
    /// PR #19 までの Gemini の API キー（DPAPI で暗号化して Base64）。今は secrets.json（SecretStore）に置くので、
    /// 読み込んだときに移して空にする（SettingsService.MigrateSecrets）
    /// </summary>
    public string ProtectedApiKey { get; set; } = "";
    public string ServiceAccountPath { get; set; } = "";
    public string VertexLocation { get; set; } = "global";
    public string Model { get; set; } = SuggestedModels[0];
    // 要件: REQ-COM-001
    // 設計判断: DEC-COM-173
    /// <summary>
    /// Gemini で文字起こしするときのモデル（音声入力と会議の記録で共通）。整形のモデル（<see cref="Model"/>）とは別に選ぶ。
    /// 2026-11-10 までは <see cref="Model"/> を共用していたので、設定のファイルになければ読み込みで <see cref="Model"/> の値を写す
    /// </summary>
    public string GeminiTranscriptionModel { get; set; } = "";
    /// <summary>入力先アプリ名を Gemini に伝える</summary>
    public bool SendAppName { get; set; } = true;

    // 会議の記録
    /// <summary>
    /// 会議の文字起こしのエンジン。Whisper（既定）か Gemini。Windows 標準は選べない
    /// （SpeechRecognizer は既定のマイクからしか聞けず、ループバックで録った PC の音を渡せないため。windows/README.md）
    /// </summary>
    public TranscriptionEngine MeetingEngine { get; set; } = TranscriptionEngine.Whisper;
    /// <summary>会議の記録の開始／停止</summary>
    public HotKeyCombo MeetingHotKey { get; set; } = HotKeyCombo.DefaultMeeting;
    /// <summary>「ここ重要」の印。記録中だけ登録する</summary>
    public HotKeyCombo HighlightHotKey { get; set; } = HotKeyCombo.DefaultHighlight;
    public bool HighlightHotKeyEnabled { get; set; } = true;
    /// <summary>議事録のモデル（Mac 版と同じく、要約の質を優先して gemini-3.8-flash）</summary>
    public string MeetingMinutesModel { get; set; } = "gemini-3.8-flash";
    public bool MakeMeetingMinutes { get; set; } = true;
    // 要件: REQ-DIC-073
    // 設計判断: DEC-DIC-173
    /// <summary>記録を止めたあとの文字起こしに、辞書の置き換えルールを当てる（既定はオン。今までの設定になければオン）</summary>
    public bool ApplyDictionaryToMeetings { get; set; } = true;
    // 要件: REQ-MTG-010
    // 設計判断: DEC-MTG-016, DEC-MTG-139
    /// <summary>
    /// 次に記録する会議の録音を、処理のあとも残す（既定）。画面では裏返しの「文字起こしのあとに録音を削除する」として出す（キーは前のまま）。
    /// 記録を始めたときに会議の deleteAudioAfterTranscription に写し、後処理は会議の値で決める
    /// </summary>
    public bool KeepMeetingAudio { get; set; } = true;
    // 要件: REQ-MTG-057
    // 設計判断: DEC-MTG-016, DEC-MTG-143
    /// <summary>会議の録音を残す日数。0 は無期限（既定）。選択肢は音声入力の履歴と同じ（HistoryPolicy.DayOptions）</summary>
    public int MeetingAudioRetentionDays { get; set; }
    /// <summary>相手側の話者を分ける（sherpa-onnx。初めて使うときにモデルをダウンロードする）</summary>
    public bool DiarizeOthers { get; set; } = true;
    /// <summary>会議で「自分」として録るマイク。空なら Windows の既定のマイク</summary>
    public string MeetingMicrophoneDeviceId { get; set; } = "";
    /// <summary>会議で「相手」として録る出力（スピーカー・ヘッドホン）。空なら Windows の既定の出力</summary>
    public string MeetingOutputDeviceId { get; set; } = "";
    /// <summary>会議の保存先。空なら ドキュメント\Hanasu\Meetings</summary>
    public string MeetingsDirectory { get; set; } = "";
    // 要件: REQ-COM-191
    // 設計判断: DEC-COM-199
    /// <summary>設定の「コマンドと MCP」でユーザーの PATH に足した項目（外すときと、別の場所の Hanasu の項目を見分けるときに使う）。足していなければ null</summary>
    public string? CommandPathEntry { get; set; }
    /// <summary>次に記録する会議の議事録の型（Meeting.MinutesTemplate の値）</summary>
    public string MeetingMinutesTemplate { get; set; } = "auto";
    // 設計判断: DEC-MTG-061
    /// <summary>議事録の「カスタム」の指示。空なら今のプロンプトの言語の既定（読むときは MinutesTemplates.CustomPromptOrDefault）</summary>
    public string MeetingCustomMinutesPrompt { get; set; } = "";

    // 辞書・ルール
    public string DictionaryText { get; set; } = "";
    public string ExtraInstructions { get; set; } = "";

    [JsonIgnore]
    public UserDictionary UserDictionary => new(DictionaryText);

    /// <summary>ユーザー辞書の正しい表記の一覧</summary>
    [JsonIgnore]
    public IReadOnlyList<string> DictionaryWords => UserDictionary.Spellings;

    /// <summary>音声入力の整形・英訳に使うモデル（選んだ AI のもの）</summary>
    [JsonIgnore]
    public string DictationModel => DictationAi switch
    {
        TextAiProvider.Claude => ClaudeModel,
        TextAiProvider.Local => LocalDictationModel,
        _ => Model,
    };

    /// <summary>議事録に使うモデル（選んだ AI のもの）</summary>
    [JsonIgnore]
    public string MinutesModel => MeetingAi switch
    {
        TextAiProvider.Claude => ClaudeMinutesModel,
        TextAiProvider.Local => LocalMeetingModel,
        _ => MeetingMinutesModel,
    };

    /// <summary>履歴の保存の方針</summary>
    [JsonIgnore]
    public Dictation.HistoryPolicy HistoryPolicy => new(HistoryEnabled, Math.Max(1, HistoryMaxCount), Math.Max(0, HistoryMaxDays));

    public AppSettings Clone()
    {
        var clone = (AppSettings)MemberwiseClone();
        // 配列は書き換えられても元に響かないよう写す
        clone.TranslationLanguages = [.. TranslationLanguages];
        return clone;
    }
}
