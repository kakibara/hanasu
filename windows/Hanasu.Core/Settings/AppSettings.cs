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

/// <summary>文章の処理（整形・英訳・議事録）に使う AI</summary>
[JsonConverter(typeof(JsonStringEnumConverter<TextAiProvider>))]
public enum TextAiProvider
{
    /// <summary>Gemini（既定。今までどおり）</summary>
    Gemini,
    /// <summary>Claude（Anthropic の Claude API。API キーで使う）</summary>
    Claude,
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
    /// <summary>話した内容を英語に翻訳して入力するショートカット</summary>
    public HotKeyCombo TranslateHotKey { get; set; } = HotKeyCombo.DefaultTranslate;
    public RecordingMode RecordingMode { get; set; } = RecordingMode.Toggle;
    /// <summary>録音に使うマイクの ID（WASAPI のエンドポイント ID）。空なら Windows の既定のマイク</summary>
    public string MicrophoneDeviceId { get; set; } = "";
    public TranscriptionEngine Engine { get; set; } = TranscriptionEngine.Windows;
    /// <summary>Whisper のモデル（<see cref="Transcription.WhisperModelCatalog"/> の Id）</summary>
    public string WhisperModel { get; set; } = "small";
    public string LocaleIdentifier { get; set; } = "ja-JP";
    public bool PlaySounds { get; set; } = true;

    // AI（文章の処理）。音声入力（整形・英訳）と会議（議事録）で、AI とモデルを別々に選ぶ（REQ-COM-024）
    /// <summary>AI で整形する（名前は前の版のまま。Gemini と Claude のどちらでも使う）</summary>
    public bool RefineWithGemini { get; set; } = true;
    /// <summary>音声入力の整形・英訳に使う AI</summary>
    public TextAiProvider DictationAi { get; set; } = TextAiProvider.Gemini;
    /// <summary>会議の議事録（作り直しを含む）に使う AI</summary>
    public TextAiProvider MeetingAi { get; set; } = TextAiProvider.Gemini;
    /// <summary>音声入力の整形・英訳に使う Claude のモデル（REQ-COM-023）</summary>
    public string ClaudeModel { get; set; } = Claude.ClaudeModels.DefaultModel;
    /// <summary>議事録に使う Claude のモデル（REQ-COM-023）</summary>
    public string ClaudeMinutesModel { get; set; } = Claude.ClaudeModels.DefaultMinutesModel;

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
    /// <summary>処理のあとも音声ファイル（me.wav / others.wav）を残す</summary>
    public bool KeepMeetingAudio { get; set; } = true;
    /// <summary>相手側の話者を分ける（sherpa-onnx。初めて使うときにモデルをダウンロードする）</summary>
    public bool DiarizeOthers { get; set; } = true;
    /// <summary>会議で「自分」として録るマイク。空なら Windows の既定のマイク</summary>
    public string MeetingMicrophoneDeviceId { get; set; } = "";
    /// <summary>会議で「相手」として録る出力（スピーカー・ヘッドホン）。空なら Windows の既定の出力</summary>
    public string MeetingOutputDeviceId { get; set; } = "";
    /// <summary>会議の保存先。空なら ドキュメント\Hanasu\Meetings</summary>
    public string MeetingsDirectory { get; set; } = "";
    /// <summary>次に記録する会議の議事録の型（Meeting.MinutesTemplate の値）</summary>
    public string MeetingMinutesTemplate { get; set; } = "auto";
    public string MeetingCustomMinutesPrompt { get; set; } = Meetings.MinutesTemplates.DefaultCustomPrompt;

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
    public string DictationModel => DictationAi == TextAiProvider.Claude ? ClaudeModel : Model;

    /// <summary>議事録に使うモデル（選んだ AI のもの）</summary>
    [JsonIgnore]
    public string MinutesModel => MeetingAi == TextAiProvider.Claude ? ClaudeMinutesModel : MeetingMinutesModel;

    public AppSettings Clone() => (AppSettings)MemberwiseClone();
}
