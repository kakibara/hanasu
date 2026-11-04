using System.Globalization;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Hanasu.Core.Meetings;

/// <summary>
/// meeting.json の読み書きの設定。Mac 版（Swift の JSONEncoder、dateEncodingStrategy = .iso8601）と同じ形にする:
/// キーは camelCase、列挙は小文字、日時は秒までの UTC（"2026-11-03T05:30:00Z"。Swift の .iso8601 は小数の秒を読めない）、
/// null の値は書かない（Swift の Optional は省略）。
/// </summary>
public static class MeetingJson
{
    public static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        // 日本語と「/」をそのまま書く（Mac 版の .withoutEscapingSlashes と同じく読める形）
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase), new Iso8601SecondsConverter() },
        ReadCommentHandling = JsonCommentHandling.Skip,
        AllowTrailingCommas = true,
        // Mac 版の Double は 1e-05 のような指数表記で書くことがある
        NumberHandling = JsonNumberHandling.AllowReadingFromString,
    };

    public static string Serialize(Meeting meeting) => JsonSerializer.Serialize(meeting, Options);

    public static Meeting Deserialize(string json)
    {
        var meeting = JsonSerializer.Deserialize<Meeting>(json, Options) ?? throw new JsonException("meeting.json が空です");
        // 足りない値を補う（Mac 版では必ずあるキーだが、手で直したファイルなどに備える）
        meeting.SpeakerNames ??= new();
        meeting.Utterances ??= new();
        meeting.Title ??= "";
        foreach (var u in meeting.Utterances)
        {
            u.Text ??= "";
            u.Speaker ??= "others";
        }
        return meeting;
    }

    /// <summary>日時を秒までの UTC の ISO 8601 で書く。読むときは小数の秒やタイムゾーンつきも受け付ける</summary>
    private sealed class Iso8601SecondsConverter : JsonConverter<DateTimeOffset>
    {
        public override DateTimeOffset Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        {
            var s = reader.GetString() ?? throw new JsonException("日時がありません");
            return DateTimeOffset.Parse(s, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal);
        }

        public override void Write(Utf8JsonWriter writer, DateTimeOffset value, JsonSerializerOptions options) =>
            writer.WriteStringValue(value.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture));
    }
}

/// <summary>
/// 会議の記録を <c>&lt;保存先&gt;\&lt;日時&gt;\</c> に保存する（既定は <c>Documents\Hanasu\Meetings</c>）。Mac 版 MeetingStore と同じ形:
/// meeting.json・transcript.md・minutes.md・notes.md と、チャンネルごとの音声（Windows 版は me.wav / others.wav）。
/// </summary>
public sealed class MeetingStore
{
    public const string MeAudioFile = "me.wav";
    public const string OthersAudioFile = "others.wav";

    /// <summary>既定の保存先（ドキュメント\Hanasu\Meetings。Mac 版の ~/Documents/Hanasu/Meetings にあたる）</summary>
    public static string DefaultBaseDirectory =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "Hanasu", "Meetings");

    public string BaseDirectory { get; }

    public MeetingStore(string? baseDirectory = null)
    {
        BaseDirectory = string.IsNullOrWhiteSpace(baseDirectory) ? DefaultBaseDirectory : baseDirectory;
    }

    public string DirectoryOf(Meeting meeting) => Path.Combine(BaseDirectory, meeting.Id);

    public string AudioPath(Meeting meeting, MeetingChannel channel) =>
        Path.Combine(DirectoryOf(meeting), channel == MeetingChannel.Me ? MeAudioFile : OthersAudioFile);

    /// <summary>新しい会議を作り、フォルダを用意する。フォルダ名は "yyyy-MM-dd HHmm"（重なれば " (2)" を付ける）</summary>
    public Meeting NewMeeting(DateTimeOffset date)
    {
        var local = date.ToLocalTime();
        var baseId = local.ToString("yyyy-MM-dd HHmm", CultureInfo.InvariantCulture);
        var id = baseId;
        for (var suffix = 2; Directory.Exists(Path.Combine(BaseDirectory, id)); suffix++) id = $"{baseId} ({suffix})";
        // Swift の .iso8601 に合わせて秒までにする（保存して読み直したときに値が変わらないように）
        var started = new DateTimeOffset(date.UtcDateTime.Ticks - date.UtcDateTime.Ticks % TimeSpan.TicksPerSecond, TimeSpan.Zero);
        var meeting = new Meeting { Id = id, Title = $"会議 {Meeting.FormatDate(date)}", StartedAt = started };
        Directory.CreateDirectory(DirectoryOf(meeting));
        return meeting;
    }

    public void Save(Meeting meeting)
    {
        var dir = DirectoryOf(meeting);
        Directory.CreateDirectory(dir);
        WriteAtomically(Path.Combine(dir, "meeting.json"), MeetingJson.Serialize(meeting));
        WriteAtomically(Path.Combine(dir, "transcript.md"), meeting.TranscriptMarkdown());
        if (meeting.Minutes is not null) WriteAtomically(Path.Combine(dir, "minutes.md"), meeting.Minutes);
        var notesPath = Path.Combine(dir, "notes.md");
        if (meeting.AllNotes.Count == 0)
        {
            if (File.Exists(notesPath)) File.Delete(notesPath);
        }
        else
        {
            WriteAtomically(notesPath, meeting.NotesMarkdown());
        }
    }

    public Meeting? Load(string id)
    {
        var path = Path.Combine(BaseDirectory, id, "meeting.json");
        if (!File.Exists(path)) return null;
        try
        {
            var meeting = MeetingJson.Deserialize(File.ReadAllText(path));
            // フォルダの名前を正とする（フォルダを手で付け替えた場合に備える）
            meeting.Id = id;
            return meeting;
        }
        catch (Exception e) when (e is JsonException or FormatException or IOException)
        {
            return null;
        }
    }

    /// <summary>すべての会議（新しい順）。読めない meeting.json は飛ばす</summary>
    public List<Meeting> LoadAll()
    {
        if (!Directory.Exists(BaseDirectory)) return new();
        return Directory.EnumerateDirectories(BaseDirectory)
            .Select(d => Load(Path.GetFileName(d)))
            .OfType<Meeting>()
            .OrderByDescending(m => m.StartedAt)
            .ToList();
    }

    /// <summary>アプリが落ちたり終了したりして「記録中」「処理中」のまま残った会議を「失敗」にする（起動時に 1 回呼ぶ）</summary>
    public void MarkInterruptedMeetings()
    {
        foreach (var meeting in LoadAll().Where(m => m.Status is MeetingStatus.Recording or MeetingStatus.Processing))
        {
            meeting.Status = MeetingStatus.Failed;
            meeting.ErrorMessage = $"記録の途中でアプリが終了しました。音声ファイル（{MeAudioFile} / {OthersAudioFile}）は途中まで残っている場合があります。";
            try { Save(meeting); } catch (IOException) { }
        }
    }

    // 要件: REQ-MTG-028
    // 設計判断: DEC-MTG-022
    /// <summary>
    /// 会議のフォルダを丸ごと消す。moveToRecycleBin を渡すと、それでフォルダを消す（Windows のアプリはごみ箱へ移す）。
    /// 渡さなければ完全に消す（テスト用）
    /// </summary>
    public void Delete(Meeting meeting, Action<string>? moveToRecycleBin = null)
    {
        var dir = DirectoryOf(meeting);
        if (!Directory.Exists(dir)) return;
        if (moveToRecycleBin is not null) moveToRecycleBin(dir);
        else Directory.Delete(dir, recursive: true);
    }

    /// <summary>会議のフォルダがあるか（削除した会議を保存し直さないため）</summary>
    public bool Exists(Meeting meeting) => Directory.Exists(DirectoryOf(meeting));

    /// <summary>チャンネルの音声ファイルを消す（設定で「音声を残さない」とき）</summary>
    public void DeleteAudio(Meeting meeting)
    {
        foreach (var channel in new[] { MeetingChannel.Me, MeetingChannel.Others })
        {
            var path = AudioPath(meeting, channel);
            try { if (File.Exists(path)) File.Delete(path); } catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
        }
    }

    private static void WriteAtomically(string path, string text)
    {
        var temp = path + ".tmp";
        File.WriteAllText(temp, text);
        File.Move(temp, path, overwrite: true);
    }
}
