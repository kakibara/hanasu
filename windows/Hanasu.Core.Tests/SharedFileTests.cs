using System.Text;
using Hanasu.Core.IO;
using Hanasu.Core.Meetings;

namespace Hanasu.Core.Tests;

public class SharedFileTests
{
    // 確かめ方: REQ-COM-183（DEC-COM-194。共有違反のあいだはやり直し、続けば止める）
    [Fact]
    public void ReplaceRetriesOnSharingViolationOnly()
    {
        var attempts = 0;
        var waits = new List<TimeSpan>();
        SharedFile.Replace("a", "b", waits.Add, (_, _) =>
        {
            if (++attempts < 3) throw new IOException("in use", unchecked((int)0x80070020));
        });
        Assert.Equal(3, attempts);
        Assert.Equal(2, waits.Count);

        attempts = 0;
        Assert.Throws<IOException>(() => SharedFile.Replace("a", "b", _ => { }, (_, _) =>
        {
            attempts++;
            throw new IOException("in use", unchecked((int)0x80070020));
        }));
        Assert.Equal(SharedFile.MaxAttempts, attempts);
        Assert.True(SharedFile.RetryDelay * (SharedFile.MaxAttempts - 1) <= TimeSpan.FromSeconds(1));

        attempts = 0;
        Assert.Throws<DirectoryNotFoundException>(() => SharedFile.Replace("a", "b", _ => { }, (_, _) =>
        {
            attempts++;
            throw new DirectoryNotFoundException();
        }));
        Assert.Equal(1, attempts);
    }

    // 確かめ方: REQ-COM-183（hanasu と同じ開き方で開いている間も、アプリの保存は失敗しない。Windows のランナーで意味がある）
    [Fact]
    public void SaveSucceedsWhileAnotherReaderHoldsTheFile()
    {
        var dir = TestKeys.TempDirectory();
        var store = new MeetingStore(dir);
        var meeting = store.NewMeeting(DateTimeOffset.Parse("2026-10-01T09:00:00+09:00"));
        meeting.Title = "一回目";
        store.Save(meeting);
        var path = Path.Combine(dir, meeting.Id, "meeting.json");
        using (var reader = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
        {
            meeting.Title = "二回目";
            store.Save(meeting);
        }
        Assert.Equal("二回目", store.Load(meeting.Id)!.Title);
    }

    [Fact]
    public void ReadAllTextDropsBom()
    {
        var path = Path.Combine(TestKeys.TempDirectory(), "x.json");
        File.WriteAllText(path, "{}", new UTF8Encoding(true));
        Assert.Equal("{}", SharedFile.ReadAllText(path));
    }

    // 確かめ方: REQ-MTG-120（DEC-MTG-153。壊れた JSON は数えず、会議のフォルダでないものも数えない）
    [Fact]
    public void LoadAllReportingSkipsBrokenJsonWithoutCounting()
    {
        var dir = TestKeys.TempDirectory();
        var store = new MeetingStore(dir);
        store.Save(store.NewMeeting(DateTimeOffset.Parse("2026-10-01T09:00:00+09:00")));
        Directory.CreateDirectory(Path.Combine(dir, "broken"));
        File.WriteAllText(Path.Combine(dir, "broken", "meeting.json"), "{");
        Directory.CreateDirectory(Path.Combine(dir, "empty"));
        var report = store.LoadAllReporting();
        Assert.Single(report.Meetings);
        Assert.Empty(report.Unreadable);
        Assert.Empty(new MeetingStore(Path.Combine(dir, "none")).LoadAllReporting().Meetings);
    }
}
