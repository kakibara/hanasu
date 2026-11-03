using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Hanasu.Core.Settings;

/// <summary>Hanasu が使う場所。</summary>
public static class HanasuPaths
{
    /// <summary>設定の置き場所（%APPDATA%\Hanasu）</summary>
    public static string SettingsDirectory =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Hanasu");

    public static string SettingsFile => Path.Combine(SettingsDirectory, "settings.json");

    /// <summary>端末ごとの大きなデータの置き場所（%LOCALAPPDATA%\Hanasu）</summary>
    public static string LocalDataDirectory =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Hanasu");

    /// <summary>Whisper のモデルの置き場所（%LOCALAPPDATA%\Hanasu\Models）</summary>
    public static string ModelsDirectory => Path.Combine(LocalDataDirectory, "Models");
}

/// <summary>秘密の値（API キー）を守って保存するための暗号化。Windows では DPAPI（CurrentUser）を使う。</summary>
public interface ISecretProtector
{
    string Protect(string plaintext);
    /// <summary>復号できなければ null</summary>
    string? Unprotect(string protectedText);
}

/// <summary>設定を JSON で読み書きする。</summary>
public sealed class SettingsStore
{
    public static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        // 日本語をそのまま読める形で保存する
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        Converters = { new JsonStringEnumConverter() },
        ReadCommentHandling = JsonCommentHandling.Skip,
        AllowTrailingCommas = true,
    };

    public string Path { get; }

    public SettingsStore(string? path = null)
    {
        Path = path ?? HanasuPaths.SettingsFile;
    }

    /// <summary>読み込む。ファイルがなければ既定値。壊れていれば .broken として残し、既定値で始める</summary>
    public AppSettings Load()
    {
        AppSettings settings;
        if (!File.Exists(Path))
        {
            settings = new AppSettings();
        }
        else
        {
            try
            {
                settings = JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(Path), JsonOptions) ?? new AppSettings();
            }
            catch (JsonException)
            {
                try { File.Copy(Path, Path + ".broken", overwrite: true); } catch (IOException) { }
                settings = new AppSettings();
            }
        }
        Normalize(settings);
        return settings;
    }

    /// <summary>書きかけで壊れないよう、一時ファイルに書いてから置き換える</summary>
    public void Save(AppSettings settings)
    {
        var dir = System.IO.Path.GetDirectoryName(Path);
        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
        var temp = Path + ".tmp";
        File.WriteAllText(temp, JsonSerializer.Serialize(settings, JsonOptions));
        File.Move(temp, Path, overwrite: true);
    }

    /// <summary>会議の記録の設定を補う。ショートカットは音声入力のものと重ならないようにする</summary>
    private static void NormalizeMeeting(AppSettings s)
    {
        // Windows 標準のエンジンは会議では使えない（ループバックの音を渡せない）ので Whisper にする
        if (s.MeetingEngine == TranscriptionEngine.Windows) s.MeetingEngine = TranscriptionEngine.Whisper;
        var taken = new List<HotKeyCombo> { s.HotKey, s.TranslateHotKey };
        s.MeetingHotKey = Pick(s.MeetingHotKey, HotKeyCombo.DefaultMeeting, taken);
        taken.Add(s.MeetingHotKey);
        s.HighlightHotKey = Pick(s.HighlightHotKey, HotKeyCombo.DefaultHighlight, taken);
        if (string.IsNullOrWhiteSpace(s.MeetingMinutesModel)) s.MeetingMinutesModel = "gemini-3.8-flash";
        s.MeetingMicrophoneDeviceId ??= "";
        s.MeetingOutputDeviceId ??= "";
        s.MeetingsDirectory ??= "";
        if (Meetings.MinutesTemplates.FromRawValue(s.MeetingMinutesTemplate) is null) s.MeetingMinutesTemplate = "auto";
        s.MeetingCustomMinutesPrompt ??= Meetings.MinutesTemplates.DefaultCustomPrompt;

        static HotKeyCombo Pick(HotKeyCombo? value, HotKeyCombo fallback, List<HotKeyCombo> taken)
        {
            if (value is not null && value.Validate() is null && !taken.Contains(value)) return value;
            return taken.Contains(fallback) ? new HotKeyCombo(HotKeyModifiers.None, 0x7B /* F12 */) : fallback;
        }
    }

    /// <summary>読み込んだ値のうち、使えないものを既定値に戻す</summary>
    internal static void Normalize(AppSettings s)
    {
        s.HotKey ??= HotKeyCombo.DefaultDictation;
        s.TranslateHotKey ??= HotKeyCombo.DefaultTranslate;
        if (s.HotKey.Validate() is not null) s.HotKey = HotKeyCombo.DefaultDictation;
        if (s.TranslateHotKey.Validate() is not null || s.TranslateHotKey == s.HotKey)
        {
            s.TranslateHotKey = s.HotKey == HotKeyCombo.DefaultTranslate ? HotKeyCombo.DefaultDictation : HotKeyCombo.DefaultTranslate;
        }
        s.MicrophoneDeviceId ??= "";
        NormalizeMeeting(s);
        s.WhisperModel = Transcription.WhisperModelCatalog.Find(s.WhisperModel)?.Id ?? "small";
        if (string.IsNullOrWhiteSpace(s.LocaleIdentifier)) s.LocaleIdentifier = "ja-JP";
        s.ProtectedApiKey ??= "";
        s.ServiceAccountPath ??= "";
        // ターミナルから起動した場合などは、環境変数のサービスアカウントを初期値にする（Mac 版と同じ）
        if (s.ServiceAccountPath.Length == 0 && Environment.GetEnvironmentVariable("GEMINI_SERVICE_ACCOUNT_JSON") is { Length: > 0 } envPath)
        {
            s.ServiceAccountPath = envPath;
        }
        if (string.IsNullOrWhiteSpace(s.VertexLocation)) s.VertexLocation = "global";
        if (string.IsNullOrWhiteSpace(s.Model)) s.Model = AppSettings.SuggestedModels[0];
        s.DictionaryText ??= "";
        s.ExtraInstructions ??= "";
    }
}

/// <summary>
/// アプリ全体で 1 つの設定を持ち、変わったら保存して知らせる。
/// ショートカットの登録や会議の記録など、設定を使う側は Changed を見て追従する。
/// </summary>
public sealed class SettingsService
{
    private readonly SettingsStore store;
    private readonly object gate = new();
    private AppSettings current;

    public event EventHandler<SettingsChangedEventArgs>? Changed;

    public ISecretProtector Protector { get; }

    public SettingsService(SettingsStore store, ISecretProtector protector)
    {
        this.store = store;
        Protector = protector;
        current = store.Load();
    }

    /// <summary>今の設定の写し（書き換えても保存されない）</summary>
    public AppSettings Current
    {
        get { lock (gate) return current.Clone(); }
    }

    /// <summary>設定を書き換えて保存する。保存に失敗しても、メモリ上の設定は変える</summary>
    public Exception? Update(Action<AppSettings> mutate)
    {
        AppSettings before, after;
        lock (gate)
        {
            before = current.Clone();
            after = current.Clone();
            mutate(after);
            current = after;
        }
        Exception? error = null;
        try { store.Save(after); } catch (Exception e) when (e is IOException or UnauthorizedAccessException) { error = e; }
        Changed?.Invoke(this, new SettingsChangedEventArgs(before, after.Clone()));
        return error;
    }

    /// <summary>API キーを暗号化して保存する。空なら消す</summary>
    public Exception? SetApiKey(string? apiKey)
    {
        var trimmed = apiKey?.Trim() ?? "";
        var protectedText = trimmed.Length == 0 ? "" : Protector.Protect(trimmed);
        return Update(s => s.ProtectedApiKey = protectedText);
    }

    public string? LoadApiKey()
    {
        var protectedText = Current.ProtectedApiKey;
        return protectedText.Length == 0 ? null : Protector.Unprotect(protectedText);
    }
}

public sealed class SettingsChangedEventArgs(AppSettings before, AppSettings after) : EventArgs
{
    public AppSettings Before { get; } = before;
    public AppSettings After { get; } = after;
}
