using Hanasu.Core.Dictation;
using Hanasu.Core.Gemini;
using Hanasu.Core.Settings;
using Hanasu.Core.Transcription;

namespace Hanasu.Core.Tests;

internal sealed class FakeHud : IHud
{
    public List<HudState> Shown { get; } = new();
    public string Transcript { get; private set; } = "";
    public bool Translating { get; private set; }
    public event EventHandler<bool>? LanguageSelected;
    public event EventHandler? StopRequested;
    public event EventHandler? CancelRequested;
    public void ClickStop() => StopRequested?.Invoke(this, EventArgs.Empty);
    public void ClickCancel() => CancelRequested?.Invoke(this, EventArgs.Empty);
    public void Show(HudState state) => Shown.Add(state);
    public void UpdateTranscript(string text) => Transcript = text;
    public void SetTranslating(bool translating) => Translating = translating;
    public void Click(bool english) => LanguageSelected?.Invoke(this, english);
    public HudState Last => Shown[^1];
}

internal sealed class FakeTranscriber : IDictationTranscriber
{
    public string Result { get; set; } = "えーと明日の会議です";
    public Exception? StartError { get; set; }
    public TaskCompletionSource? StartGate { get; set; }
    public bool Started, Stopped, Cancelled, Disposed;
    public TranscriptionContext? Context;
    public event EventHandler<string>? PartialTextChanged;
    public string? FinishingMessage => null;

    public async Task StartAsync(TranscriptionContext context, CancellationToken cancellationToken = default)
    {
        Context = context;
        if (StartGate is not null) await StartGate.Task;
        if (StartError is not null) throw StartError;
        Started = true;
        PartialTextChanged?.Invoke(this, "えーと");
    }

    public Task<string> StopAsync(CancellationToken cancellationToken = default)
    {
        Stopped = true;
        return Task.FromResult(Result);
    }

    public Task CancelAsync()
    {
        Cancelled = true;
        return Task.CompletedTask;
    }

    public ValueTask DisposeAsync()
    {
        Disposed = true;
        return ValueTask.CompletedTask;
    }
}

internal sealed class FakeRefiner : IDictationRefiner
{
    public List<(string Kind, RefineRequest Request)> Calls { get; } = new();
    public Exception? Error { get; set; }

    public Task<string> RefineAsync(RefineRequest request, CancellationToken cancellationToken = default)
    {
        Calls.Add(("refine", request));
        return Error is null ? Task.FromResult("整形:" + request.Transcript) : Task.FromException<string>(Error);
    }

    public Task<string> TranslateToEnglishAsync(RefineRequest request, CancellationToken cancellationToken = default)
    {
        Calls.Add(("translate", request));
        return Error is null ? Task.FromResult("EN:" + request.Transcript) : Task.FromException<string>(Error);
    }
}

internal sealed class FakeInserter : ITextInserter
{
    public List<string> Inserted { get; } = new();
    public List<PasteFallbackClipboard> Fallbacks { get; } = new();
    public InsertOutcome Outcome { get; set; } = InsertOutcome.Pasted;
    public Exception? Error { get; set; }
    public Task<InsertOutcome> InsertAsync(string text, PasteFallbackClipboard fallback)
    {
        Inserted.Add(text);
        Fallbacks.Add(fallback);
        return Error is null ? Task.FromResult(Outcome) : Task.FromException<InsertOutcome>(Error);
    }
}

internal sealed class Harness
{
    public AppSettings Settings { get; } = new() { DictionaryText = "ジェミニ => Gemini\nHanasu" };
    public FakeHud Hud { get; } = new();
    public FakeTranscriber Transcriber { get; set; } = new();
    public FakeRefiner Refiner { get; } = new();
    public bool HasCredentials { get; set; } = true;
    public FakeInserter Inserter { get; } = new();
    public DictationHistoryStore History { get; } = new(TestKeys.TempDirectory());
    public List<bool> Escape { get; } = new();
    public List<SoundCue> Sounds { get; } = new();
    public List<string> OpenedHelp { get; } = new();
    public DictationController Controller { get; }

    public Harness()
    {
        Controller = new DictationController(new DictationServices
        {
            Settings = () => Settings,
            CreateTranscriber = _ => Transcriber,
            Processor = new DictationTextProcessor(_ => HasCredentials ? Refiner : null),
            Inserter = Inserter,
            Hud = Hud,
            History = History,
            ForegroundAppName = () => "Slack",
            SetEscapeHotKeyEnabled = Escape.Add,
            PlaySound = Sounds.Add,
            OpenHelp = OpenedHelp.Add,
        });
    }
}

public class DictationControllerTests
{
    [Fact]
    public async Task ToggleRecordsRefinesAndInserts()
    {
        var h = new Harness { Transcriber = { Result = "えーと資料はジェミニで作りました" } };
        h.Controller.HandleHotKey(HotKeyEventKind.Pressed, DictationMode.Refine);
        await Task.Yield();
        Assert.Equal(DictationState.Recording, h.Controller.State);
        Assert.Equal(HudState.Recording, h.Hud.Last);
        Assert.Equal("えーと", h.Hud.Transcript);
        Assert.Equal([true], h.Escape);
        Assert.Contains("ジェミニ", h.Transcriber.Context!.ContextualStrings);

        // 押している間だけのモードではないので、離しても止まらない
        h.Controller.HandleHotKey(HotKeyEventKind.Released, DictationMode.Refine);
        Assert.Equal(DictationState.Recording, h.Controller.State);

        h.Controller.HandleHotKey(HotKeyEventKind.Pressed, DictationMode.Refine);
        await WaitIdle(h);
        Assert.True(h.Transcriber.Stopped && h.Transcriber.Disposed);
        // 辞書を当ててから Gemini に送る
        var (kind, request) = Assert.Single(h.Refiner.Calls);
        Assert.Equal("refine", kind);
        Assert.Equal("えーと資料はGeminiで作りました", request.Transcript);
        Assert.Equal("Slack", request.AppName);
        Assert.Equal(["Gemini", "Hanasu"], request.Dictionary);
        Assert.Equal(["整形:えーと資料はGeminiで作りました"], h.Inserter.Inserted);
        Assert.Equal(HudPhase.Done, h.Hud.Last.Phase);
        Assert.Equal("入力しました", h.Hud.Last.Message);
        Assert.Equal([SoundCue.Start, SoundCue.Stop], h.Sounds);
        var entry = Assert.Single(h.History.Entries);
        Assert.Equal("えーと資料はジェミニで作りました", entry.Raw);
        Assert.Equal("整形:えーと資料はGeminiで作りました", entry.Output);
        Assert.Equal(HistoryStatus.Succeeded, entry.Status);
        Assert.Equal(HistoryMode.Refine, entry.Mode);
        Assert.Equal("Slack", entry.AppName);
        Assert.Equal(h.Settings.Model, entry.Model);
        Assert.True(File.Exists(h.History.FilePath));
        Assert.Equal([true, false], h.Escape);
    }

    [Fact]
    public async Task PushToTalkStopsOnRelease()
    {
        var h = new Harness();
        h.Settings.RecordingMode = RecordingMode.PushToTalk;
        h.Controller.HandleHotKey(HotKeyEventKind.Pressed, DictationMode.Refine);
        await Task.Yield();
        h.Controller.HandleHotKey(HotKeyEventKind.Pressed, DictationMode.Refine);  // 押し直し（キーリピートなど）は無視
        Assert.Equal(DictationState.Recording, h.Controller.State);
        h.Controller.HandleHotKey(HotKeyEventKind.Released, DictationMode.Refine);
        await WaitIdle(h);
        Assert.Single(h.Inserter.Inserted);
    }

    [Fact]
    public async Task ReleaseWhilePreparingStopsRightAfterStart()
    {
        var h = new Harness { Transcriber = { StartGate = new TaskCompletionSource() } };
        h.Settings.RecordingMode = RecordingMode.PushToTalk;
        h.Controller.HandleHotKey(HotKeyEventKind.Pressed, DictationMode.Refine);
        Assert.Equal(DictationState.Preparing, h.Controller.State);
        h.Controller.HandleHotKey(HotKeyEventKind.Released, DictationMode.Refine);
        h.Transcriber.StartGate.SetResult();
        await WaitIdle(h);
        Assert.True(h.Transcriber.Stopped);
        Assert.Single(h.Inserter.Inserted);
    }

    [Fact]
    public async Task TranslateHotKeyAndHudSwitchChooseTheLanguage()
    {
        var h = new Harness();
        await h.Controller.StartAsync(DictationMode.TranslateToEnglish);
        Assert.True(h.Hud.Translating);
        // HUD で「話した言語」を押すと、止めた時点の選択で入力する
        h.Hud.Click(english: false);
        Assert.False(h.Hud.Translating);
        Assert.Equal(DictationMode.Refine, h.Controller.Mode);
        h.Hud.Click(english: true);
        await h.Controller.FinishAsync();
        Assert.Equal("translate", Assert.Single(h.Refiner.Calls).Kind);
        Assert.Equal("英訳して入力しました", h.Hud.Last.Message);
        // 録音が終わったら切り替えは効かない
        h.Hud.Click(english: false);
        Assert.Equal(DictationMode.TranslateToEnglish, h.Controller.Mode);
    }

    [Fact]
    public async Task EscapeCancelsWithoutInserting()
    {
        var h = new Harness();
        await h.Controller.StartAsync();
        h.Controller.Cancel();
        await WaitIdle(h);
        Assert.True(h.Transcriber.Cancelled);
        Assert.Empty(h.Inserter.Inserted);
        Assert.Equal("取り消しました", h.Hud.Last.Message);
        Assert.Equal([true, false], h.Escape);
    }

    [Fact]
    public async Task HudStopButtonFinishesAndInserts()
    {
        var h = new Harness();
        // 押している間だけのモードでも、停止ボタンで止まる
        h.Settings.RecordingMode = RecordingMode.PushToTalk;
        await h.Controller.StartAsync();
        h.Hud.ClickStop();
        await WaitIdle(h);
        Assert.True(h.Transcriber.Stopped);
        Assert.Single(h.Inserter.Inserted);
        Assert.Equal("入力しました", h.Hud.Last.Message);
    }

    [Fact]
    public async Task HudStopButtonWhilePreparingStopsRightAfterStart()
    {
        var h = new Harness { Transcriber = { StartGate = new TaskCompletionSource() } };
        var start = h.Controller.StartAsync();
        h.Hud.ClickStop();
        h.Transcriber.StartGate.SetResult();
        await start;
        await WaitIdle(h);
        Assert.Single(h.Inserter.Inserted);
    }

    [Fact]
    public async Task HudCancelButtonActsLikeEscape()
    {
        var h = new Harness();
        await h.Controller.StartAsync();
        h.Hud.ClickCancel();
        await WaitIdle(h);
        Assert.True(h.Transcriber.Cancelled);
        Assert.Empty(h.Inserter.Inserted);
        Assert.Equal("取り消しました", h.Hud.Last.Message);
        // 終わった後に押されても何もしない
        h.Hud.ClickStop();
        h.Hud.ClickCancel();
        Assert.Equal(DictationState.Idle, h.Controller.State);
    }

    [Fact]
    public async Task CancelWhilePreparing()
    {
        var h = new Harness { Transcriber = { StartGate = new TaskCompletionSource() } };
        var start = h.Controller.StartAsync();
        h.Controller.Cancel();
        h.Transcriber.StartGate.SetResult();
        await start;
        Assert.Equal(DictationState.Idle, h.Controller.State);
        Assert.True(h.Transcriber.Cancelled);
        Assert.Empty(h.Inserter.Inserted);
    }

    [Fact]
    public async Task StartErrorsAreShownAndOpenHelp()
    {
        var h = new Harness { Transcriber = { StartError = new TranscriptionException("オンライン音声認識をオンにしてください", "ms-settings:privacy-speech") } };
        await h.Controller.StartAsync();
        Assert.Equal(DictationState.Idle, h.Controller.State);
        Assert.Equal(HudState.Error("オンライン音声認識をオンにしてください"), h.Hud.Last);
        Assert.Equal(["ms-settings:privacy-speech"], h.OpenedHelp);
        Assert.True(h.Transcriber.Disposed);
        Assert.Equal([true, false], h.Escape);
    }

    [Fact]
    public async Task EmptyRecognitionInsertsNothing()
    {
        var h = new Harness { Transcriber = { Result = "  " } };
        await h.Controller.StartAsync();
        await h.Controller.FinishAsync();
        Assert.Empty(h.Inserter.Inserted);
        Assert.Equal(HudState.Error("音声が認識されませんでした"), h.Hud.Last);
    }

    [Fact]
    public async Task WithoutCredentialsTheRawTextIsInsertedWithAWarning()
    {
        var h = new Harness { HasCredentials = false, Transcriber = { Result = "ジェミニのテスト" } };
        await h.Controller.StartAsync();
        await h.Controller.FinishAsync();
        Assert.Equal(["Geminiのテスト"], h.Inserter.Inserted);
        Assert.Equal(HudPhase.Error, h.Hud.Last.Phase);
        Assert.Contains("認証情報が未設定", h.Hud.Last.Message);
    }

    [Fact]
    public async Task GeminiFailureFallsBackToRawText()
    {
        var h = new Harness();
        h.Refiner.Error = GeminiException.Http(500, "Internal");
        await h.Controller.StartAsync();
        await h.Controller.FinishAsync();
        Assert.Equal(["えーと明日の会議です"], h.Inserter.Inserted);
        Assert.Contains("整形前の文章を入力しました", h.Hud.Last.Message);
        Assert.Contains(SoundCue.Error, h.Sounds);
    }

    [Fact]
    public async Task RefineOffSkipsGeminiButTranslationStillUsesIt()
    {
        var h = new Harness();
        h.Settings.RefineWithGemini = false;
        await h.Controller.StartAsync();
        await h.Controller.FinishAsync();
        Assert.Empty(h.Refiner.Calls);
        Assert.Equal("入力しました", h.Hud.Last.Message);

        h.Transcriber = new FakeTranscriber();
        await h.Controller.StartAsync(DictationMode.TranslateToEnglish);
        await h.Controller.FinishAsync();
        Assert.Equal("translate", Assert.Single(h.Refiner.Calls).Kind);
    }

    [Fact]
    public async Task AppNameIsNotSentWhenTurnedOff()
    {
        var h = new Harness();
        h.Settings.SendAppName = false;
        await h.Controller.StartAsync();
        await h.Controller.FinishAsync();
        Assert.Null(Assert.Single(h.Refiner.Calls).Request.AppName);
    }

    // 確かめ方: REQ-DIC-080
    [Fact]
    public async Task UnpastedResultStaysOnTheHudWithTheFullText()
    {
        var h = new Harness { Transcriber = { Result = "えーと資料はジェミニで作りました" } };
        h.Inserter.Outcome = InsertOutcome.NotPastedBecause(NotPastedReason.Desktop, clipboardHasText: true);
        await h.Controller.StartAsync();
        await h.Controller.FinishAsync();

        var shown = h.Hud.Last;
        Assert.Equal(HudPhase.Unpasted, shown.Phase);
        Assert.Equal("整形:えーと資料はGeminiで作りました", shown.ResultText);
        Assert.Equal("入力できる場所が見つかりませんでした", HudText.Title(shown));
        Assert.Contains("クリップボードにも入れてあります", HudText.Detail(shown, ""));
        // 自動では閉じない。クリックを受け取る
        Assert.Null(HudText.AutoHideDelay(shown.Phase));
        Assert.True(HudText.AcceptsClicks(shown.Phase));
        Assert.Equal(DictationState.Idle, h.Controller.State);
        // 履歴（最近の結果）には今までどおり残る
        Assert.Equal("整形:えーと資料はGeminiで作りました", h.History.Entries[0].Output);
    }

    // 確かめ方: REQ-DIC-081
    [Theory]
    [InlineData(PasteFallbackClipboard.KeepResult)]
    [InlineData(PasteFallbackClipboard.RestoreOriginal)]
    public async Task FallbackSettingIsPassedToTheInserter(PasteFallbackClipboard fallback)
    {
        var h = new Harness();
        h.Settings.PasteFallbackClipboard = fallback;
        h.Inserter.Outcome = InsertOutcome.NotPastedBecause(NotPastedReason.NoFocus, clipboardHasText: fallback == PasteFallbackClipboard.KeepResult);
        await h.Controller.StartAsync();
        await h.Controller.FinishAsync();
        Assert.Equal(fallback, Assert.Single(h.Inserter.Fallbacks));
        var note = HudText.Detail(h.Hud.Last, "");
        if (fallback == PasteFallbackClipboard.KeepResult) Assert.Contains("Ctrl+V を押してください", note);
        else Assert.Contains("「コピー」を押す", note);
    }

    [Fact]
    public async Task HigherIntegrityWindowGetsTheSamePanel()
    {
        var h = new Harness { Inserter = { Outcome = InsertOutcome.NotPastedBecause(NotPastedReason.HigherIntegrity, clipboardHasText: true) } };
        await h.Controller.StartAsync();
        await h.Controller.FinishAsync();
        Assert.Equal(HudPhase.Unpasted, h.Hud.Last.Phase);
        Assert.Equal("管理者として動いているアプリには貼り付けられません", HudText.Title(h.Hud.Last));
    }

    [Fact]
    public async Task InsertErrorStillKeepsTheResultOnScreen()
    {
        var h = new Harness { Inserter = { Error = new InvalidOperationException("壊れた") } };
        await h.Controller.StartAsync();
        await h.Controller.FinishAsync();
        Assert.Equal(HudPhase.Unpasted, h.Hud.Last.Phase);
        Assert.Equal("入力できませんでした", HudText.Title(h.Hud.Last));
        Assert.Contains("「コピー」を押す", HudText.Detail(h.Hud.Last, ""));
        Assert.Equal(DictationState.Idle, h.Controller.State);
    }

    [Fact]
    public async Task AiWarningIsShownAboveTheHowTo()
    {
        var h = new Harness { HasCredentials = false };
        h.Inserter.Outcome = InsertOutcome.NotPastedBecause(NotPastedReason.Taskbar, clipboardHasText: true);
        await h.Controller.StartAsync();
        await h.Controller.FinishAsync();
        var note = HudText.Detail(h.Hud.Last, "")!;
        Assert.Equal(HudPhase.Unpasted, h.Hud.Last.Phase);
        Assert.Contains("\n", note);
        Assert.EndsWith("Ctrl+V を押してください。", note);
        Assert.Contains(SoundCue.Error, h.Sounds);
    }

    [Fact]
    public async Task NextDictationReplacesTheUnpastedPanel()
    {
        var h = new Harness { Inserter = { Outcome = InsertOutcome.NotPastedBecause(NotPastedReason.Desktop, clipboardHasText: true) } };
        await h.Controller.StartAsync();
        await h.Controller.FinishAsync();
        Assert.Equal(HudPhase.Unpasted, h.Hud.Last.Phase);
        h.Inserter.Outcome = InsertOutcome.Pasted;
        await h.Controller.StartAsync();
        Assert.Equal(HudPhase.Recording, h.Hud.Last.Phase);
        await h.Controller.FinishAsync();
        Assert.Equal(HudPhase.Done, h.Hud.Last.Phase);
    }

    [Fact]
    public async Task DoesNotStartWhenBlocked()
    {
        var h = new Harness();
        h.Controller.CanStart = () => false;
        await h.Controller.StartAsync();
        Assert.Equal(DictationState.Idle, h.Controller.State);
        Assert.Empty(h.Hud.Shown);
    }

    private static async Task WaitIdle(Harness h)
    {
        for (var i = 0; i < 200 && h.Controller.State != DictationState.Idle; i++) await Task.Delay(5);
        Assert.Equal(DictationState.Idle, h.Controller.State);
    }
}

public class HudTextTests
{
    [Fact]
    public void TitlesAndDetailsFollowMac()
    {
        Assert.Equal("録音中", HudText.Title(HudState.Recording));
        Assert.Equal("話してください…", HudText.Detail(HudState.Recording, ""));
        Assert.Equal("エラー", HudText.Title(HudState.Error("失敗")));
        Assert.Equal("失敗", HudText.Detail(HudState.Error("失敗"), "x"));
        Assert.Equal("Gemini で英語に翻訳しています…", HudText.ProcessingTitle(true));
        Assert.True(HudText.CanChooseLanguage(HudPhase.Recording));
        Assert.False(HudText.CanChooseLanguage(HudPhase.Processing));
        Assert.True(HudText.ShowsRecordingControls(HudPhase.Recording));
        Assert.False(HudText.ShowsRecordingControls(HudPhase.Done));
        Assert.Equal("1:05", HudText.Elapsed(TimeSpan.FromSeconds(65)));
    }

    [Fact]
    public void LongTranscriptShowsTheEnd()
    {
        var text = new string('あ', 200) + "最後";
        var tail = HudText.Tail(text, 10);
        Assert.Equal("…" + new string('あ', 8) + "最後", tail);
    }
}
