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

    // Gemini
    public bool RefineWithGemini { get; set; } = true;
    public GeminiAuthMode AuthMode { get; set; } = GeminiAuthMode.ApiKey;
    /// <summary>API キーを DPAPI（ユーザー単位）で暗号化して Base64 にしたもの。平文では保存しない</summary>
    public string ProtectedApiKey { get; set; } = "";
    public string ServiceAccountPath { get; set; } = "";
    public string VertexLocation { get; set; } = "global";
    public string Model { get; set; } = SuggestedModels[0];
    /// <summary>入力先アプリ名を Gemini に伝える</summary>
    public bool SendAppName { get; set; } = true;

    // 辞書・ルール
    public string DictionaryText { get; set; } = "";
    public string ExtraInstructions { get; set; } = "";

    [JsonIgnore]
    public UserDictionary UserDictionary => new(DictionaryText);

    /// <summary>ユーザー辞書の正しい表記の一覧</summary>
    [JsonIgnore]
    public IReadOnlyList<string> DictionaryWords => UserDictionary.Spellings;

    public AppSettings Clone() => (AppSettings)MemberwiseClone();
}
