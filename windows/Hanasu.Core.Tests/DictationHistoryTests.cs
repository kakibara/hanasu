using System.Text.Json;
using Hanasu.Core.Dictation;
using Hanasu.Core.Settings;

namespace Hanasu.Core.Tests;

// 確かめ方: REQ-DIC-060, REQ-DIC-063
public class DictationHistoryTests
{
    private static readonly DateTimeOffset Now = new(2026, 11, 4, 12, 0, 0, TimeSpan.Zero);

    private static DictationHistoryStore NewStore(string? dir = null, Func<DateTimeOffset>? clock = null) =>
        new(dir ?? TestKeys.TempDirectory(), clock ?? (() => Now));

    [Fact]
    public void DefaultsKeepThirtyDays()
    {
        var settings = new AppSettings();
        Assert.True(settings.HistoryEnabled);
        Assert.Equal(30, settings.HistoryMaxDays);
        Assert.Equal(1000, settings.HistoryMaxCount);
        Assert.Equal(new HistoryPolicy(true, 1000, 30), settings.HistoryPolicy);
        Assert.Contains(30, HistoryPolicy.DayOptions);
        Assert.Equal("無期限", HistoryPolicy.DaysLabel(0));
    }

    [Fact]
    public void SettingsWithoutHistoryKeysUseTheDefaults()
    {
        // 前の版の settings.json には履歴の項目がない
        var settings = JsonSerializer.Deserialize<AppSettings>("""{ "playSounds": false }""", SettingsStore.JsonOptions)!;
        Assert.Equal(new HistoryPolicy(true, 1000, 30), settings.HistoryPolicy);
    }

    [Fact]
    public void RecordSavesAndReloads()
    {
        var dir = TestKeys.TempDirectory();
        var store = NewStore(dir);
        store.Record("えーと明日", "明日", DictationMode.Refine, ProcessStatus.Succeeded, "Slack", model: "gemini-3.8-flash-lite",
            date: Now.AddMinutes(-1).AddMilliseconds(500));
        store.Record("hello", "Hello.", DictationMode.TranslateToEnglish, ProcessStatus.AiFailed, null, errorMessage: "時間切れ", date: Now);

        var reloaded = NewStore(dir);
        reloaded.Load();
        Assert.Null(reloaded.LastError);
        Assert.Equal(2, reloaded.Entries.Count);
        var newest = reloaded.Entries[0];
        Assert.Equal("Hello.", newest.Output);
        Assert.Equal(HistoryMode.Translate, newest.Mode);
        Assert.Equal(HistoryStatus.GeminiFailed, newest.Status);
        Assert.Equal("時間切れ", newest.ErrorMessage);
        Assert.True(newest.IsFailure);
        var older = reloaded.Entries[1];
        Assert.Equal("Slack", older.AppName);
        Assert.Equal("gemini-3.8-flash-lite", older.Model);
        // 秒までで保存する（読み直しても値が変わらない）
        Assert.Equal(Now.AddMinutes(-1), older.Date);
        Assert.Equal(store.Entries[1].Date, older.Date);
        Assert.Equal(store.Entries[1].Id, older.Id);
    }

    [Fact]
    public void FileUsesTheSameShapeAsTheMacVersion()
    {
        var store = NewStore();
        store.Record("raw", "out", DictationMode.Refine, ProcessStatus.RefineOff, date: Now);
        using var doc = JsonDocument.Parse(File.ReadAllText(store.FilePath));
        Assert.Equal(1, doc.RootElement.GetProperty("version").GetInt32());
        var entry = doc.RootElement.GetProperty("entries")[0];
        Assert.Equal("2026-11-04T12:00:00Z", entry.GetProperty("date").GetString());
        Assert.Equal("refine", entry.GetProperty("mode").GetString());
        Assert.Equal("refineOff", entry.GetProperty("status").GetString());
        var id = entry.GetProperty("id").GetString()!;
        Assert.Equal(id.ToUpperInvariant(), id);
        Assert.True(Guid.TryParse(id, out _));
        // null は書かない。メモリ上だけの印も書かない
        Assert.False(entry.TryGetProperty("appName", out _));
        Assert.False(entry.TryGetProperty("transient", out _));
    }

    [Fact]
    public void ReadsAHistoryFileWrittenByTheMacVersion()
    {
        var dir = TestKeys.TempDirectory();
        // Mac 版（Swift の JSONEncoder、.iso8601・.sortedKeys）が書く形。Windows 版にない項目（録音・やり直し）は読み飛ばす
        File.WriteAllText(Path.Combine(dir, "history.json"), """
            {
              "entries" : [
                {
                  "appName" : "Slack",
                  "audioFileName" : "6F9619FF-8B86-D011-B42D-00C04FC964FF.m4a",
                  "date" : "2026-11-04T11:00:00Z",
                  "id" : "6F9619FF-8B86-D011-B42D-00C04FC964FF",
                  "mode" : "translate",
                  "output" : "See you tomorrow.",
                  "raw" : "また明日",
                  "retriedAt" : "2026-11-04T11:05:00Z",
                  "status" : "noCredentials"
                }
              ],
              "version" : 1
            }
            """);
        var store = NewStore(dir);
        store.Load();
        var entry = Assert.Single(store.Entries);
        Assert.Equal("See you tomorrow.", entry.Output);
        Assert.Equal(HistoryMode.Translate, entry.Mode);
        Assert.Equal(HistoryStatus.NoCredentials, entry.Status);
        Assert.Equal("6F9619FF-8B86-D011-B42D-00C04FC964FF", entry.Id);
    }

    [Fact]
    public void OldEntriesAreRemovedByDays()
    {
        var store = NewStore();
        store.Record("a", "31 日前", DictationMode.Refine, ProcessStatus.Succeeded, date: Now.AddDays(-31));
        store.Record("b", "29 日前", DictationMode.Refine, ProcessStatus.Succeeded, date: Now.AddDays(-29));
        Assert.Equal(["29 日前"], store.Entries.Select(e => e.Output));

        // 日数を縮めると、その場で消す
        store.ApplyPolicy(new HistoryPolicy(true, 1000, 7));
        Assert.Empty(store.Entries);
    }

    [Fact]
    public void UnlimitedDaysKeepsOldEntries()
    {
        var store = NewStore();
        store.ApplyPolicy(new HistoryPolicy(true, 1000, 0));
        store.Record("a", "2 年前", DictationMode.Refine, ProcessStatus.Succeeded, date: Now.AddYears(-2));
        Assert.Single(store.Entries);
    }

    [Fact]
    public void LoadAppliesTheDaysLimit()
    {
        var dir = TestKeys.TempDirectory();
        var clock = Now.AddDays(-20);
        var store = NewStore(dir, () => clock);
        store.Record("a", "古い", DictationMode.Refine, ProcessStatus.Succeeded, date: clock);
        // 20 日たって起動すると、30 日を過ぎたものが消える
        clock = Now.AddDays(15);
        var later = NewStore(dir, () => clock);
        later.Load();
        Assert.Empty(later.Entries);
        var again = NewStore(dir);
        again.Load();
        Assert.Empty(again.Entries);
    }

    [Fact]
    public void CountLimitKeepsTheNewest()
    {
        var store = NewStore();
        store.ApplyPolicy(new HistoryPolicy(true, 3, 30));
        for (var i = 0; i < 5; i++) store.Record($"r{i}", $"o{i}", DictationMode.Refine, ProcessStatus.Succeeded, date: Now.AddMinutes(i - 10));
        Assert.Equal(["o4", "o3", "o2"], store.Entries.Select(e => e.Output));
    }

    [Fact]
    public void DisabledKeepsTenInMemoryAndDoesNotTouchTheFile()
    {
        var dir = TestKeys.TempDirectory();
        var store = NewStore(dir);
        store.Record("saved", "保存した", DictationMode.Refine, ProcessStatus.Succeeded, date: Now.AddHours(-1));
        store.ApplyPolicy(new HistoryPolicy(false, 1000, 30));
        for (var i = 0; i < 12; i++) store.Record($"r{i}", $"o{i}", DictationMode.Refine, ProcessStatus.Succeeded, date: Now.AddMinutes(i));
        // メモリ上は 10 件と、保存済みの 1 件（保存済みは消さない）
        Assert.Equal(11, store.Entries.Count);
        Assert.Equal("o11", store.Recent[0].Output);
        var reloaded = NewStore(dir);
        reloaded.Load();
        Assert.Equal(["保存した"], reloaded.Entries.Select(e => e.Output));
    }

    [Fact]
    public void BrokenFileIsKeptAsideAndNotOverwritten()
    {
        var dir = TestKeys.TempDirectory();
        File.WriteAllText(Path.Combine(dir, "history.json"), "{ 壊れた");
        var store = NewStore(dir);
        store.Load();
        Assert.NotNull(store.LastError);
        Assert.Empty(store.Entries);
        Assert.Equal("{ 壊れた", File.ReadAllText(Path.Combine(dir, "history.json.broken")));
        store.Record("r", "o", DictationMode.Refine, ProcessStatus.Succeeded, date: Now);
        Assert.Null(store.LastError);
        Assert.Equal("{ 壊れた", File.ReadAllText(Path.Combine(dir, "history.json.broken")));
    }

    [Fact]
    public void DeleteAndDeleteAll()
    {
        var dir = TestKeys.TempDirectory();
        var store = NewStore(dir);
        var a = store.Record("a", "A", DictationMode.Refine, ProcessStatus.Succeeded, date: Now.AddMinutes(-2));
        store.Record("b", "B", DictationMode.Refine, ProcessStatus.Succeeded, date: Now.AddMinutes(-1));
        var changes = 0;
        store.Changed += (_, _) => changes++;
        store.Delete([a.Id.ToLowerInvariant()]);
        Assert.Equal(["B"], store.Entries.Select(e => e.Output));
        store.DeleteAll();
        Assert.Empty(store.Entries);
        Assert.Equal(2, changes);
        var reloaded = NewStore(dir);
        reloaded.Load();
        Assert.Empty(reloaded.Entries);
    }

    [Fact]
    public void RecentIsTheNewestTen()
    {
        var store = NewStore();
        for (var i = 0; i < 12; i++) store.Record($"r{i}", $"o{i}", DictationMode.Refine, ProcessStatus.Succeeded, date: Now.AddMinutes(i - 20));
        Assert.Equal(10, store.Recent.Count);
        Assert.Equal("o11", store.Recent[0].Output);
        Assert.Equal("o2", store.Recent[^1].Output);
    }

    [Fact]
    public void FilterMatchesAllWordsInOutputRawOrApp()
    {
        var store = NewStore();
        store.Record("あしたの会議", "明日の会議は10時から", DictationMode.Refine, ProcessStatus.Succeeded, "Slack", date: Now.AddMinutes(-3));
        store.Record("しりょう", "資料を送ります", DictationMode.Refine, ProcessStatus.AiFailed, "Outlook", date: Now.AddMinutes(-2));
        store.Record("hello", "Hello", DictationMode.TranslateToEnglish, ProcessStatus.RefineOff, "Teams", date: Now.AddMinutes(-1));
        var all = store.Entries;
        Assert.Equal(["明日の会議は10時から"], DictationHistoryStore.Filter(all, "会議 10時", false).Select(e => e.Output));
        Assert.Equal(["資料を送ります"], DictationHistoryStore.Filter(all, "しりょう", false).Select(e => e.Output));
        Assert.Equal(["Hello"], DictationHistoryStore.Filter(all, "teams", false).Select(e => e.Output));
        Assert.Equal(["Hello", "資料を送ります"], DictationHistoryStore.Filter(all, "", true).Select(e => e.Output));
        Assert.Equal(3, DictationHistoryStore.Filter(all, "  ", false).Count);
    }

    [Fact]
    public void DayLabels()
    {
        var offset = TimeZoneInfo.Local.GetUtcOffset(Now);
        var now = new DateTimeOffset(2026, 11, 4, 12, 0, 0, offset);
        Assert.Equal("今日", DictationHistoryStore.DayLabel(now.AddHours(-1), now));
        Assert.Equal("昨日", DictationHistoryStore.DayLabel(now.AddDays(-1), now));
        Assert.Equal("11月2日（月）", DictationHistoryStore.DayLabel(now.AddDays(-2), now));
        Assert.Equal("2025年11月4日（火）", DictationHistoryStore.DayLabel(now.AddYears(-1), now));
    }

    [Fact]
    public void MenuLabelIsShortSingleLineAndMarksFailures()
    {
        var offset = TimeZoneInfo.Local.GetUtcOffset(Now);
        var entry = new DictationHistoryEntry
        {
            Date = new DateTimeOffset(2026, 11, 3, 9, 5, 0, offset),
            Raw = "r",
            Output = "一行目\n" + new string('あ', 60),
            Status = HistoryStatus.GeminiFailed,
        };
        var label = DictationHistoryStore.MenuLabel(entry);
        Assert.StartsWith("⚠ 09:05  一行目 あ", label);
        Assert.EndsWith("…", label);
        Assert.DoesNotContain('\n', label);
    }
}
