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

    /// <summary>設定がまだないときの文字起こしの言語（Windows の表示の言語から。テストで差し替える）</summary>
    private readonly Func<string> systemLocale;

    public SettingsStore(string? path = null, Func<string>? systemLocale = null)
    {
        Path = path ?? HanasuPaths.SettingsFile;
        this.systemLocale = systemLocale ?? (() => TranscriptionLocales.SystemDefault);
    }

    /// <summary>
    /// 読み込む。ファイルがなければ既定値。壊れていれば .broken として残し、既定値で始める。
    /// 新しく始めるときの文字起こしの言語は、Windows の表示の言語にする（保存してある設定の言語は変えない）
    /// </summary>
    // 要件: REQ-COM-004
    public AppSettings Load()
    {
        AppSettings settings;
        if (!File.Exists(Path))
        {
            settings = new AppSettings { LocaleIdentifier = systemLocale() };
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
                settings = new AppSettings { LocaleIdentifier = systemLocale() };
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
        // 設計判断: DEC-DIC-027
        s.TranslationLanguages = Dictation.TranslationLanguages.Normalize(s.TranslationLanguages);
        s.MicrophoneDeviceId ??= "";
        NormalizeMeeting(s);
        s.WhisperModel = Transcription.WhisperModelCatalog.Find(s.WhisperModel)?.Id ?? "small";
        if (string.IsNullOrWhiteSpace(s.LocaleIdentifier)) s.LocaleIdentifier = "ja-JP";
        s.ProtectedApiKey ??= "";
        // 一覧にない Claude のモデルは既定（音声入力は Haiku 5.5、議事録は Sonnet 5.5）に戻す
        s.ClaudeModel = Claude.ClaudeModels.Normalize(s.ClaudeModel);
        s.ClaudeMinutesModel = Claude.ClaudeModels.Normalize(s.ClaudeMinutesModel, Claude.ClaudeModels.DefaultMinutesModel);
        if (!Enum.IsDefined(s.DictationAi)) s.DictationAi = TextAiProvider.Gemini;
        if (!Enum.IsDefined(s.MeetingAi)) s.MeetingAi = TextAiProvider.Gemini;
        // 一覧にないローカルのモデルは既定に戻す
        s.LocalDictationModel = LocalLlm.LocalLlmModel.Find(s.LocalDictationModel)?.Id ?? LocalLlm.LocalLlmModel.DefaultDictation.Id;
        s.LocalMeetingModel = LocalLlm.LocalLlmModel.Find(s.LocalMeetingModel)?.Id ?? LocalLlm.LocalLlmModel.DefaultMeeting.Id;
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

    /// <summary>API キー（settings.json には入れない）</summary>
    public SecretStore Secrets { get; }

    public SettingsService(SettingsStore store, SecretStore secrets)
    {
        this.store = store;
        Secrets = secrets;
        current = store.Load();
        // 要件: REQ-COM-061（プロンプトの言語は、設定の文字起こしの言語に合わせる）
        Ai.PromptLanguage.UseSettings(current.LocaleIdentifier);
        MigrateSecrets();
    }

    /// <summary>
    /// PR #19 までの settings.json の Gemini の API キーを secrets.json に移す（復号せずにそのまま移すので、読めなくならない）。
    /// secrets.json に書けたときだけ settings.json から消す
    /// </summary>
    // 設計判断: DEC-COM-144
    private void MigrateSecrets()
    {
        var legacy = current.ProtectedApiKey;
        if (legacy.Length == 0) return;
        try
        {
            if (Secrets.MigrateLegacy(legacy)) Update(s => s.ProtectedApiKey = "");
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            // 移せなければ、次に起動したときにもう一度試す（settings.json の値は残す）
        }
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
            // 要件: REQ-COM-061
            Ai.PromptLanguage.UseSettings(after.LocaleIdentifier);
        }
        Exception? error = null;
        try { store.Save(after); } catch (Exception e) when (e is IOException or UnauthorizedAccessException) { error = e; }
        Changed?.Invoke(this, new SettingsChangedEventArgs(before, after.Clone()));
        return error;
    }
}

public sealed class SettingsChangedEventArgs(AppSettings before, AppSettings after) : EventArgs
{
    public AppSettings Before { get; } = before;
    public AppSettings After { get; } = after;
}
