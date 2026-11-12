using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;
using Hanasu.Core.Meetings;

namespace Hanasu.Core.Dictation;

// 設計判断: DEC-DIC-029
/// <summary>
/// 履歴の 1 件のモード（Mac 版の DictationHistoryEntry.Mode と同じ値）。JSON に書く値は、整形は refine、英訳は今までの値（translate）のまま、
/// 和訳は translateJapanese、ほかの言語への翻訳は translate:&lt;言語のコード&gt;（translate:ko、translate:zh-CN など）。
/// 知らない値も、履歴のファイルを読めなくしないよう、そのまま持って書き戻す
/// </summary>
[JsonConverter(typeof(HistoryModeJsonConverter))]
public readonly record struct HistoryMode
{
    private const string RefineValue = "refine";
    private const string TranslateValue = "translate";
    private const string TranslateJapaneseValue = "translateJapanese";
    private const string TranslatePrefix = "translate:";

    private readonly string? value;

    private HistoryMode(string value) => this.value = value;

    public static HistoryMode Refine { get; } = new(RefineValue);
    public static HistoryMode Translate { get; } = new(TranslateValue);
    public static HistoryMode TranslateJapanese { get; } = new(TranslateJapaneseValue);

    /// <summary>JSON に書く値（default は refine）</summary>
    public string Value => value ?? RefineValue;

    /// <summary>この言語に翻訳したときのモード</summary>
    public static HistoryMode Of(TranslationLanguage language) =>
        language == TranslationLanguage.English ? Translate
        : language == TranslationLanguage.Japanese ? TranslateJapanese
        : new(TranslatePrefix + language.Code);

    /// <summary>JSON の値から。今までの値（refine・translate・translateJapanese）は大文字と小文字を区別せずに読み、ほかの値はそのまま持つ</summary>
    public static HistoryMode FromValue(string? value)
    {
        foreach (var known in new[] { Refine, Translate, TranslateJapanese })
        {
            if (string.Equals(value, known.Value, StringComparison.OrdinalIgnoreCase)) return known;
        }
        if (value is not null && value.StartsWith(TranslatePrefix, StringComparison.OrdinalIgnoreCase)
            && TranslationLanguage.FromStoredValue(value[TranslatePrefix.Length..]) is { } language)
        {
            return Of(language);
        }
        return string.IsNullOrEmpty(value) ? Refine : new(value);
    }

    /// <summary>翻訳の言語（整形と、知らない値なら null）</summary>
    public TranslationLanguage? Translation =>
        this == Translate ? TranslationLanguage.English
        : this == TranslateJapanese ? TranslationLanguage.Japanese
        : Value.StartsWith(TranslatePrefix, StringComparison.Ordinal) ? TranslationLanguage.FromStoredValue(Value[TranslatePrefix.Length..])
        : null;

    public bool Equals(HistoryMode other) => Value == other.Value;

    public override int GetHashCode() => Value.GetHashCode();

    public override string ToString() => Value;
}

/// <summary>HistoryMode を文字列で読み書きする。古い形の数（0・1・2）も読む。それ以外の形は整形として読む（履歴のファイル全体を読めなくしない）</summary>
public sealed class HistoryModeJsonConverter : JsonConverter<HistoryMode>
{
    public override HistoryMode Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        switch (reader.TokenType)
        {
            case JsonTokenType.String:
                return HistoryMode.FromValue(reader.GetString());
            case JsonTokenType.Number when reader.TryGetInt32(out var number):
                return number switch
                {
                    1 => HistoryMode.Translate,
                    2 => HistoryMode.TranslateJapanese,
                    _ => HistoryMode.Refine,
                };
            default:
                reader.Skip();
                return HistoryMode.Refine;
        }
    }

    public override void Write(Utf8JsonWriter writer, HistoryMode value, JsonSerializerOptions options) =>
        writer.WriteStringValue(value.Value);
}

/// <summary>
/// 履歴の 1 件の状態（Mac 版の DictationHistoryEntry.Status と同じ値。JSON では camelCase で書く）。
/// AI の失敗は Mac 版に合わせて geminiFailed と書く（Claude で失敗したときも同じ）。
/// </summary>
public enum HistoryStatus { Succeeded, GeminiFailed, NoCredentials, RefineOff }

/// <summary>音声入力の履歴 1 件。history.json は Mac 版と同じ形（キーは camelCase、日時は秒までの UTC）</summary>
// 設計判断: DEC-DIC-071
public sealed class DictationHistoryEntry
{
    /// <summary>大文字の UUID（Mac 版の Swift の UUID と同じ書き方）</summary>
    public string Id { get; init; } = Guid.NewGuid().ToString().ToUpperInvariant();
    public DateTimeOffset Date { get; init; }
    /// <summary>文字起こしの原文</summary>
    public string Raw { get; init; } = "";
    /// <summary>入力した結果（整形後・翻訳後。失敗したときは辞書だけ当てた原文）</summary>
    public string Output { get; init; } = "";
    public HistoryMode Mode { get; init; }
    /// <summary>入力先のアプリ</summary>
    public string? AppName { get; init; }
    public HistoryStatus Status { get; init; }
    /// <summary>AI のエラーの内容（知らせた文言）</summary>
    public string? ErrorMessage { get; init; }
    /// <summary>整形・英訳に使ったモデル</summary>
    public string? Model { get; init; }

    /// <summary>「履歴を保存しない」設定のときの項目。ファイルには書かず、メモリ上だけに置く</summary>
    [JsonIgnore]
    public bool Transient { get; init; }

    // 設計判断: DEC-DIC-029
    public static HistoryMode ModeOf(DictationMode mode) =>
        mode.Translation is { } language ? HistoryMode.Of(language) : HistoryMode.Refine;

    public static HistoryStatus StatusOf(ProcessStatus status) => status switch
    {
        ProcessStatus.Succeeded => HistoryStatus.Succeeded,
        ProcessStatus.AiFailed => HistoryStatus.GeminiFailed,
        ProcessStatus.NoCredentials => HistoryStatus.NoCredentials,
        _ => HistoryStatus.RefineOff,
    };

    /// <summary>モードの名前（「整形」「英訳」「韓国語訳」）。知らない値は、そのまま出す</summary>
    public static string ModeLabel(HistoryMode mode) =>
        mode.Translation is { } language ? language.Verb()
        : mode == HistoryMode.Refine ? Strings.History_Mode_Refine
        : mode.Value;

    public static string StatusLabel(HistoryStatus status) => status switch
    {
        HistoryStatus.Succeeded => Strings.History_Status_Succeeded,
        HistoryStatus.GeminiFailed => Strings.History_Status_AiFailed,
        HistoryStatus.NoCredentials => Strings.History_Status_NoCredentials,
        _ => Strings.History_Status_RefineOff,
    };

    /// <summary>一覧で「失敗・未整形」として印を付ける</summary>
    [JsonIgnore]
    public bool IsUnrefined => Status != HistoryStatus.Succeeded;

    /// <summary>失敗したもの（取り戻したい可能性が高い）。一覧で ⚠ を付ける</summary>
    [JsonIgnore]
    public bool IsFailure => Status is HistoryStatus.GeminiFailed or HistoryStatus.NoCredentials;
}

/// <summary>履歴の保存の方針（設定の HistoryEnabled・HistoryMaxCount・HistoryMaxDays）</summary>
/// <param name="MaxDays">残す日数。0 は無期限</param>
public sealed record HistoryPolicy(bool Enabled = true, int MaxCount = 1000, int MaxDays = 30)
{
    /// <summary>件数の選択肢（Mac 版と同じ）</summary>
    public static readonly IReadOnlyList<int> CountOptions = [100, 500, 1000, 5000];

    /// <summary>日数の選択肢。0 は無期限（Mac 版と同じ）</summary>
    public static readonly IReadOnlyList<int> DayOptions = [7, 30, 90, 365, 0];

    public static string DaysLabel(int days) => days > 0 ? string.Format(Strings.History_Days, days) : Strings.History_DaysUnlimited;
}

/// <summary>
/// 音声入力の履歴を <c>%LOCALAPPDATA%\Hanasu\History\history.json</c> に保存する（Mac 版の DictationHistoryStore）。
/// 新しい順に持ち、件数と日数の上限を超えたものは古い順に消す。追加・起動・設定の変更のときに消す。
/// 保存しない設定のときは、ファイルに書かずメモリ上に直近 10 件だけ置く（「最近の結果」のため）。
/// ほかのスレッド（音声入力の流れ）から呼ばれるので、中身は lock で守る。
/// </summary>
// 要件: REQ-DIC-060, REQ-DIC-063
// 設計判断: DEC-DIC-130
public sealed class DictationHistoryStore
{
    /// <summary>保存しない設定のときに、メモリ上に置いておく件数</summary>
    public const int TransientLimit = 10;

    /// <summary>タスクトレイの「最近の結果」に出す件数</summary>
    public const int RecentCount = 10;

    private sealed class FileContents
    {
        public int Version { get; set; } = 1;
        public List<DictationHistoryEntry> Entries { get; set; } = new();
    }

    private readonly object gate = new();
    private readonly Func<DateTimeOffset> clock;
    private List<DictationHistoryEntry> entries = new();
    private HistoryPolicy policy = new();

    public event EventHandler? Changed;

    public string Directory { get; }
    public string FilePath => Path.Combine(Directory, "history.json");

    /// <summary>直近の読み込み・保存のエラー（履歴のウインドウに出す）。なければ null</summary>
    public string? LastError { get; private set; }

    public static string DefaultDirectory => Path.Combine(Settings.HanasuPaths.LocalDataDirectory, "History");

    public DictationHistoryStore(string directory, Func<DateTimeOffset>? clock = null)
    {
        Directory = directory;
        this.clock = clock ?? (() => DateTimeOffset.Now);
    }

    /// <summary>新しい順</summary>
    public IReadOnlyList<DictationHistoryEntry> Entries
    {
        get { lock (gate) return entries.ToArray(); }
    }

    /// <summary>「最近の結果」に出す、新しい順の 10 件</summary>
    public IReadOnlyList<DictationHistoryEntry> Recent
    {
        get { lock (gate) return entries.Take(RecentCount).ToArray(); }
    }

    public HistoryPolicy Policy
    {
        get { lock (gate) return policy; }
    }

    /// <summary>保存の方針を変える。上限が狭まれば、その場で古いものを消して保存する</summary>
    public void ApplyPolicy(HistoryPolicy newPolicy)
    {
        bool changed;
        lock (gate)
        {
            if (policy == newPolicy) return;
            policy = newPolicy;
            changed = Prune();
            if (changed) Save();
        }
        if (changed) OnChanged();
    }

    // 設計判断: DEC-DIC-130
    /// <summary>
    /// ファイルから読む。読めないファイル（壊れた JSON）は history.json.broken に名前を変えて残し、空から始める
    /// （上書きして話した内容を失わないように）。読んだあと上限を当てる
    /// </summary>
    public void Load()
    {
        lock (gate)
        {
            var transient = entries.Where(e => e.Transient).ToList();
            List<DictationHistoryEntry> loaded = new();
            LastError = null;
            if (File.Exists(FilePath))
            {
                try
                {
                    var contents = JsonSerializer.Deserialize<FileContents>(File.ReadAllText(FilePath), MeetingJson.Options);
                    loaded = (contents?.Entries ?? new()).Where(e => e is not null).ToList();
                }
                catch (Exception e) when (e is JsonException or NotSupportedException)
                {
                    var broken = FilePath + ".broken";
                    try
                    {
                        File.Move(FilePath, broken, overwrite: true);
                        LastError = string.Format(Strings.History_BrokenFileKept, Path.GetFileName(broken));
                    }
                    catch (IOException moveError)
                    {
                        LastError = string.Format(Strings.History_ReadFailed, moveError.Message);
                    }
                }
                catch (Exception e) when (e is IOException or UnauthorizedAccessException)
                {
                    LastError = string.Format(Strings.History_ReadFailed, e.Message);
                }
            }
            entries = loaded.Concat(transient).OrderByDescending(e => e.Date).ToList();
            if (Prune()) Save();
        }
        OnChanged();
    }

    // 設計判断: DEC-DIC-072, DEC-DIC-074
    /// <summary>1 件足す（貼り付けの前に呼ぶ）。保存しない設定なら、メモリ上だけに置く</summary>
    public DictationHistoryEntry Record(string raw, string output, DictationMode mode, ProcessStatus status,
        string? appName = null, string? errorMessage = null, string? model = null, DateTimeOffset? date = null)
    {
        DictationHistoryEntry entry;
        lock (gate)
        {
            entry = new DictationHistoryEntry
            {
                // ファイルには秒までで書くので、メモリ上もそろえる
                Date = WholeSeconds(date ?? clock()),
                Raw = raw,
                Output = output,
                Mode = DictationHistoryEntry.ModeOf(mode),
                AppName = string.IsNullOrEmpty(appName) ? null : appName,
                Status = DictationHistoryEntry.StatusOf(status),
                ErrorMessage = string.IsNullOrEmpty(errorMessage) ? null : errorMessage,
                Model = string.IsNullOrEmpty(model) ? null : model,
                Transient = !policy.Enabled,
            };
            entries.Insert(0, entry);
            entries = entries.OrderByDescending(e => e.Date).ToList();
            Prune();
            if (!entry.Transient) Save();
        }
        OnChanged();
        return entry;
    }

    public void Delete(IEnumerable<string> ids)
    {
        var set = ids.ToHashSet(StringComparer.OrdinalIgnoreCase);
        lock (gate)
        {
            if (entries.RemoveAll(e => set.Contains(e.Id)) == 0) return;
            Save();
        }
        OnChanged();
    }

    public void DeleteAll()
    {
        lock (gate)
        {
            entries.Clear();
            Save();
        }
        OnChanged();
    }

    // 設計判断: DEC-DIC-073
    /// <summary>上限を超えたものを消す（lock の中で呼ぶ）。消したものがあれば true</summary>
    private bool Prune()
    {
        var now = clock();
        DateTimeOffset? cutoff = policy.MaxDays > 0 ? now.AddDays(-policy.MaxDays) : null;
        var kept = new List<DictationHistoryEntry>(entries.Count);
        int persistent = 0, transient = 0;
        foreach (var entry in entries)  // 新しい順
        {
            bool keep;
            if (entry.Transient)
            {
                keep = ++transient <= TransientLimit;
            }
            else if (cutoff is { } c && entry.Date < c)
            {
                keep = false;
            }
            else
            {
                keep = ++persistent <= policy.MaxCount;
            }
            if (keep) kept.Add(entry);
        }
        var removed = kept.Count != entries.Count;
        entries = kept;
        return removed;
    }

    // 設計判断: DEC-DIC-130
    /// <summary>保存する（lock の中で呼ぶ）。一時ファイルに書いてから置き換える。失敗したら LastError に残す</summary>
    private void Save()
    {
        try
        {
            System.IO.Directory.CreateDirectory(Directory);
            var contents = new FileContents { Entries = entries.Where(e => !e.Transient).ToList() };
            var temp = FilePath + ".tmp";
            File.WriteAllText(temp, JsonSerializer.Serialize(contents, MeetingJson.Options));
            File.Move(temp, FilePath, overwrite: true);
            LastError = null;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            LastError = string.Format(Strings.History_SaveFailed, e.Message);
        }
    }

    private void OnChanged() => Changed?.Invoke(this, EventArgs.Empty);

    private static DateTimeOffset WholeSeconds(DateTimeOffset date) =>
        new(date.Ticks - date.Ticks % TimeSpan.TicksPerSecond, date.Offset);

    // MARK: - 表示（履歴のウインドウとタスクトレイ）

    // 設計判断: DEC-DIC-079
    /// <summary>
    /// 検索。結果・原文・アプリ名が対象で、空白で区切った語をすべて含むものを残す（大文字と小文字は区別しない）。
    /// unrefinedOnly なら「失敗・未整形」だけ
    /// </summary>
    public static IReadOnlyList<DictationHistoryEntry> Filter(IEnumerable<DictationHistoryEntry> entries, string? query, bool unrefinedOnly)
    {
        var words = (query ?? "").Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
        return entries.Where(e =>
            (!unrefinedOnly || e.IsUnrefined)
            && words.All(w => e.Output.Contains(w, StringComparison.CurrentCultureIgnoreCase)
                || e.Raw.Contains(w, StringComparison.CurrentCultureIgnoreCase)
                || (e.AppName?.Contains(w, StringComparison.CurrentCultureIgnoreCase) ?? false))).ToArray();
    }

    /// <summary>日ごとの見出し（今日・昨日・「11月2日（月）」）。年が違えば年も付ける。月・曜日の名前は表示の言語で書く</summary>
    public static string DayLabel(DateTimeOffset date, DateTimeOffset now)
    {
        var day = date.ToLocalTime().Date;
        var today = now.ToLocalTime().Date;
        if (day == today) return Strings.History_Today;
        if (day == today.AddDays(-1)) return Strings.History_Yesterday;
        // 要件: REQ-COM-060（書式は言語ごとのリソース。月・曜日の名前は表示の言語のカルチャ）
        var pattern = day.Year == today.Year ? Strings.History_DayFormat : Strings.History_DayFormatWithYear;
        // 暦はグレゴリオ暦にそろえる（ar-SA の既定のウンム・アル＝クラー暦で見出しがヒジュラ暦になるのを防ぐ。Meeting.FormatDate と同じ）
        return day.ToString(pattern, Meetings.Meeting.DisplayLanguage.Culture);
    }

    // 要件: REQ-COM-060
    /// <summary>
    /// 詳しい欄の日時。日本語は今までの形（"yyyy/MM/dd HH:mm:ss"）、ほかの言語は表示の言語のカルチャの短い日付と、
    /// 秒つきの時刻（"G"）。暦はグレゴリオ暦にそろえる（DayLabel と同じカルチャ）
    /// </summary>
    public static string DetailDateLabel(DateTimeOffset date)
    {
        var language = Meetings.Meeting.DisplayLanguage;
        return date.ToLocalTime().ToString(language == Ai.PromptLanguage.Ja ? "yyyy/MM/dd HH:mm:ss" : "G", language.Culture);
    }

    /// <summary>メニューに出す 1 行（失敗したものには ⚠ を付け、長ければ途中で切る）</summary>
    public static string MenuLabel(DictationHistoryEntry entry, int maxChars = 40)
    {
        var text = entry.Output.ReplaceLineEndings(" ").Trim();
        if (text.Length > maxChars) text = text[..maxChars] + "…";
        return $"{(entry.IsFailure ? "⚠ " : "")}{entry.Date.ToLocalTime():HH:mm}  {text}";
    }
}
