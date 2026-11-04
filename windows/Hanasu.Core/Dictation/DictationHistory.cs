using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;
using Hanasu.Core.Meetings;

namespace Hanasu.Core.Dictation;

/// <summary>履歴の 1 件のモード（Mac 版の DictationHistoryEntry.Mode と同じ値）</summary>
public enum HistoryMode { Refine, Translate }

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
    /// <summary>入力した結果（整形後・英訳後。失敗したときは辞書だけ当てた原文）</summary>
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

    public static HistoryMode ModeOf(DictationMode mode) => mode == DictationMode.TranslateToEnglish ? HistoryMode.Translate : HistoryMode.Refine;

    public static HistoryStatus StatusOf(ProcessStatus status) => status switch
    {
        ProcessStatus.Succeeded => HistoryStatus.Succeeded,
        ProcessStatus.AiFailed => HistoryStatus.GeminiFailed,
        ProcessStatus.NoCredentials => HistoryStatus.NoCredentials,
        _ => HistoryStatus.RefineOff,
    };

    public static string ModeLabel(HistoryMode mode) => mode == HistoryMode.Translate ? "英訳" : "整形";

    public static string StatusLabel(HistoryStatus status) => status switch
    {
        HistoryStatus.Succeeded => "成功",
        HistoryStatus.GeminiFailed => "AI 失敗（原文のまま）",
        HistoryStatus.NoCredentials => "未設定のため原文のまま",
        _ => "整形オフ（原文のまま）",
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

    public static string DaysLabel(int days) => days > 0 ? $"{days} 日" : "無期限";
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
                        LastError = $"履歴のファイルを読めなかったので、{Path.GetFileName(broken)} として残し、新しく始めました";
                    }
                    catch (IOException moveError)
                    {
                        LastError = $"履歴のファイルを読めませんでした: {moveError.Message}";
                    }
                }
                catch (IOException e)
                {
                    LastError = $"履歴のファイルを読めませんでした: {e.Message}";
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
            LastError = $"履歴を保存できませんでした: {e.Message}";
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

    /// <summary>日ごとの見出し（今日・昨日・「11月2日（月）」）。年が違えば年も付ける</summary>
    public static string DayLabel(DateTimeOffset date, DateTimeOffset now)
    {
        var day = date.ToLocalTime().Date;
        var today = now.ToLocalTime().Date;
        if (day == today) return "今日";
        if (day == today.AddDays(-1)) return "昨日";
        var culture = CultureInfo.GetCultureInfo("ja-JP");
        var weekday = culture.DateTimeFormat.GetShortestDayName(day.DayOfWeek);
        return day.Year == today.Year ? $"{day.Month}月{day.Day}日（{weekday}）" : $"{day.Year}年{day.Month}月{day.Day}日（{weekday}）";
    }

    /// <summary>メニューに出す 1 行（失敗したものには ⚠ を付け、長ければ途中で切る）</summary>
    public static string MenuLabel(DictationHistoryEntry entry, int maxChars = 40)
    {
        var text = entry.Output.ReplaceLineEndings(" ").Trim();
        if (text.Length > maxChars) text = text[..maxChars] + "…";
        return $"{(entry.IsFailure ? "⚠ " : "")}{entry.Date.ToLocalTime():HH:mm}  {text}";
    }
}
