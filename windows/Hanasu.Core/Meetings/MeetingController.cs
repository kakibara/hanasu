using System.Diagnostics;
using Hanasu.Core.Gemini;
using Hanasu.Core.Settings;
using Hanasu.Core.Transcription;

namespace Hanasu.Core.Meetings;

public enum MeetingState { Idle, Starting, Recording, Processing }

/// <summary>
/// 会議の 1 チャンネル（マイク = 自分 / ループバック = 相手）を録り、16 kHz・モノラルの WAV に書き出す。
/// 時刻は録音開始からの共通の時間軸にそろえる（<see cref="Audio.ChannelTimeline"/>）。
/// </summary>
public interface IMeetingChannelRecorder : IAsyncDisposable
{
    MeetingChannel Channel { get; }

    /// <summary>最初の音が録音開始から何秒後だったか。何も届かなければ null</summary>
    double? StartOffset { get; }

    /// <summary>直近の音の大きさ（0〜1、表示用）</summary>
    double Level { get; }

    /// <summary>録音が思わぬ理由で止まったとき（機器が抜かれたなど）</summary>
    event EventHandler<Exception>? Faulted;

    /// <param name="wavPath">書き出す WAV</param>
    /// <param name="elapsed">録音開始からの秒数を返す時計（2 つのチャンネルで共通）</param>
    Task StartAsync(string wavPath, Func<double> elapsed, CancellationToken cancellationToken = default);

    Task StopAsync();
}

/// <summary>会議の記録に要る部品。Windows の部品は AppHost で、テストでは偽物を渡す。</summary>
public sealed class MeetingServices
{
    public required Func<AppSettings> Settings { get; init; }
    public required Func<AppSettings, IMeetingChannelRecorder> CreateMicRecorder { get; init; }
    public required Func<AppSettings, IMeetingChannelRecorder> CreateLoopbackRecorder { get; init; }
    public required Func<AppSettings, ISegmentTranscriber> CreateTranscriber { get; init; }
    /// <summary>話者分離をしない設定なら null を返す</summary>
    public Func<AppSettings, ISpeakerDiarizer?> CreateDiarizer { get; init; } = _ => null;
    /// <summary>議事録用の AI（設定の「会議の AI」。認証情報がなければ null）</summary>
    public required Func<AppSettings, Ai.ITextGenerator?> CreateMinutesClient { get; init; }
    public Func<DateTimeOffset> Now { get; init; } = () => DateTimeOffset.Now;
    public Action<string> Log { get; init; } = _ => { };
}

/// <summary>知らせたいこと（タスクトレイの吹き出しなどに出す）</summary>
public sealed record MeetingNotice(string Title, string Message, bool IsWarning = false, string? HelpUri = null);

/// <summary>
/// 会議の記録の流れ: idle → starting → recording → processing（文字起こし・話者分離・議事録）→ idle。
/// Mac 版 MeetingRecorder の司令塔の部分にあたる。UI のスレッドから呼ぶ。イベントはどのスレッドからも来る。
/// </summary>
public sealed class MeetingController
{
    private readonly MeetingServices services;
    private readonly object gate = new();
    private readonly Stopwatch clock = new();
    private MeetingState state = MeetingState.Idle;
    private IMeetingChannelRecorder? mic;
    private IMeetingChannelRecorder? loopback;
    private ISegmentTranscriber? transcriber;
    private AppSettings? recordingSettings;
    private Task? processing;

    public MeetingController(MeetingServices services)
    {
        this.services = services;
    }

    public MeetingState State
    {
        get { lock (gate) return state; }
        private set
        {
            lock (gate)
            {
                if (state == value) return;
                state = value;
            }
            StateChanged?.Invoke(this, value);
        }
    }

    /// <summary>記録中・処理中の会議</summary>
    public Meeting? Current { get; private set; }

    /// <summary>後処理の今の段階（「Whisper で文字起こししています…（自分）」など）</summary>
    public string? ProgressMessage { get; private set; }

    /// <summary>記録を始めてからの秒数</summary>
    public double ElapsedSeconds => clock.Elapsed.TotalSeconds;

    public double MicLevel => mic?.Level ?? 0;
    public double LoopbackLevel => loopback?.Level ?? 0;

    /// <summary>音声入力が動いている間は false を返す</summary>
    public Func<bool> CanStart { get; set; } = () => true;

    public event EventHandler<MeetingState>? StateChanged;
    /// <summary>会議の中身が変わった（メモの追加・後処理の完了など）。一覧と表示を更新する</summary>
    public event EventHandler<Meeting>? MeetingChanged;
    public event EventHandler<string>? ProgressChanged;
    public event EventHandler<MeetingNotice>? Notice;

    public MeetingStore Store(AppSettings settings) => new(settings.MeetingsDirectory);

    /// <summary>記録していなければ始め、記録中なら止める（ショートカットとメニューから）</summary>
    public Task ToggleAsync() => State switch
    {
        MeetingState.Idle => StartAsync(),
        MeetingState.Recording => StopAsync(),
        _ => Task.CompletedTask,
    };

    public async Task StartAsync()
    {
        lock (gate)
        {
            if (state != MeetingState.Idle) return;
        }
        if (!CanStart())
        {
            Notice?.Invoke(this, new MeetingNotice("会議の記録を始められません", "音声入力の録音中です。終わってからもう一度試してください。", true));
            return;
        }
        State = MeetingState.Starting;
        var settings = services.Settings();
        recordingSettings = settings;
        var store = Store(settings);
        Meeting? meeting = null;
        try
        {
            // 使えるかどうかは記録を始める前に確かめる（会議が終わってからモデルがないと分かると、記録が無駄になる）
            transcriber = services.CreateTranscriber(settings);
            await transcriber.PrepareAsync(Context(settings)).ConfigureAwait(false);

            meeting = store.NewMeeting(services.Now());
            meeting.MinutesTemplateId = settings.MeetingMinutesTemplate;
            meeting.CustomMinutesPrompt = settings.MeetingMinutesTemplate == MinutesTemplate.Custom.RawValue() ? settings.MeetingCustomMinutesPrompt : null;
            meeting.Status = MeetingStatus.Recording;
            store.Save(meeting);
            Current = meeting;

            clock.Restart();
            Func<double> elapsed = () => clock.Elapsed.TotalSeconds;
            mic = services.CreateMicRecorder(settings);
            mic.Faulted += OnMicFaulted;
            await mic.StartAsync(store.AudioPath(meeting, MeetingChannel.Me), elapsed).ConfigureAwait(false);

            loopback = services.CreateLoopbackRecorder(settings);
            try
            {
                await loopback.StartAsync(store.AudioPath(meeting, MeetingChannel.Others), elapsed).ConfigureAwait(false);
            }
            catch (TranscriptionException e)
            {
                // PC の音が録れなくても、自分の声だけで続ける
                services.Log($"meeting loopback start failed: {e.Message}");
                await loopback.DisposeAsync().ConfigureAwait(false);
                loopback = null;
                Notice?.Invoke(this, new MeetingNotice("PC の音（相手）を録音できません", $"自分の声（マイク）だけを記録します。{e.Message}", true, e.HelpUri));
            }
            services.Log("meeting started");
            State = MeetingState.Recording;
            MeetingChanged?.Invoke(this, meeting);
        }
        catch (Exception e) when (e is TranscriptionException or IOException or UnauthorizedAccessException)
        {
            services.Log($"meeting start failed: {e.GetType().Name}: {e.Message}");
            await DisposeRecordersAsync().ConfigureAwait(false);
            clock.Reset();
            if (meeting is not null)
            {
                meeting.Status = MeetingStatus.Failed;
                meeting.ErrorMessage = $"記録を始められませんでした: {e.Message}";
                try { store.Save(meeting); } catch (IOException) { }
                MeetingChanged?.Invoke(this, meeting);
            }
            Current = null;
            State = MeetingState.Idle;
            Notice?.Invoke(this, new MeetingNotice("会議の記録を始められませんでした", e.Message, true, (e as TranscriptionException)?.HelpUri));
        }
    }

    /// <summary>記録を止め、後処理を始める。後処理が終わるのを待つ Task を返す</summary>
    public async Task StopAsync()
    {
        lock (gate)
        {
            if (state != MeetingState.Recording) return;
        }
        var meeting = Current!;
        var settings = recordingSettings!;
        State = MeetingState.Processing;
        SetProgress("記録を止めています…");
        var micOffset = mic?.StartOffset;
        var loopbackOffset = loopback?.StartOffset;
        await StopRecordersAsync().ConfigureAwait(false);
        micOffset ??= mic?.StartOffset;
        loopbackOffset ??= loopback?.StartOffset;
        meeting.Duration = clock.Elapsed.TotalSeconds;
        clock.Stop();
        meeting.AudioStartOffsets = new Dictionary<string, double> { ["me"] = micOffset ?? 0, ["others"] = loopbackOffset ?? 0 };
        await DisposeRecordersAsync().ConfigureAwait(false);
        services.Log($"meeting stopped: {meeting.Duration:0}s");

        processing = ProcessAsync(meeting, settings);
        await processing.ConfigureAwait(false);
    }

    private async Task ProcessAsync(Meeting meeting, AppSettings settings)
    {
        var processor = new MeetingPostProcessor
        {
            Store = Store(settings),
            Transcriber = transcriber ?? services.CreateTranscriber(settings),
            Context = Context(settings),
            Diarizer = settings.DiarizeOthers ? services.CreateDiarizer(settings) : null,
            MinutesClient = settings.MakeMeetingMinutes ? () => services.CreateMinutesClient(settings) : null,
            MinutesModel = settings.MinutesModel,
            MinutesProvider = settings.MeetingAi,
            KeepAudio = settings.KeepMeetingAudio,
            Log = services.Log,
        };
        try
        {
            var result = await processor.ProcessAsync(meeting, new InlineProgress<string>(SetProgress)).ConfigureAwait(false);
            foreach (var warning in result.Warnings) Notice?.Invoke(this, new MeetingNotice("会議の記録", warning, true));
            Notice?.Invoke(this, meeting.ErrorMessage is null
                ? new MeetingNotice("会議の記録ができました", meeting.Minutes is null ? "文字起こしを保存しました。" : "文字起こしと議事録を保存しました。")
                : new MeetingNotice("会議の記録（一部に問題があります）", meeting.ErrorMessage, true));
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or InvalidOperationException)
        {
            services.Log($"meeting processing failed: {e.GetType().Name}: {e.Message}");
            meeting.Status = MeetingStatus.Failed;
            meeting.ErrorMessage = $"記録のあとの処理に失敗しました: {e.Message}";
            try { Store(settings).Save(meeting); } catch (IOException) { }
            Notice?.Invoke(this, new MeetingNotice("会議の記録に失敗しました", e.Message, true));
        }
        finally
        {
            transcriber = null;
            recordingSettings = null;
            Current = null;
            SetProgress(null);
            State = MeetingState.Idle;
            MeetingChanged?.Invoke(this, meeting);
        }
    }

    // MARK: - メモと印

    /// <summary>記録中のメモを足す。time は書き始めた時刻（録音開始からの秒数）。記録中でなければ何もしない</summary>
    public void AddNote(string text, double? time)
    {
        var body = text.Trim();
        if (body.Length == 0) return;
        AddNoteCore(new MeetingNote(MeetingNoteKind.Note, time ?? ElapsedSeconds, body));
    }

    /// <summary>「ここ重要」の印を今の時刻に付ける。text は印の説明（メモ欄に書きかけの文）</summary>
    public void AddHighlight(string text = "") => AddNoteCore(new MeetingNote(MeetingNoteKind.Highlight, ElapsedSeconds, text.Trim()));

    private void AddNoteCore(MeetingNote note)
    {
        if (State != MeetingState.Recording || Current is not { } meeting || recordingSettings is null) return;
        meeting.Notes ??= new();
        meeting.Notes.Add(note);
        try { Store(recordingSettings).Save(meeting); } catch (IOException e) { services.Log($"note save failed: {e.Message}"); }
        MeetingChanged?.Invoke(this, meeting);
    }

    // MARK: - 記録のあとの操作

    /// <summary>議事録を作り直す（型を変えるときは template を渡す）。失敗したら例外を投げ、会議は元のまま</summary>
    public async Task RegenerateMinutesAsync(Meeting meeting, MinutesTemplate? template = null, string? customPrompt = null,
        CancellationToken cancellationToken = default)
    {
        var settings = services.Settings();
        var client = services.CreateMinutesClient(settings)
            ?? throw (settings.MeetingAi switch
            {
                TextAiProvider.Claude => (Exception)Claude.ClaudeException.MissingCredentials(),
                TextAiProvider.Local => LocalLlm.LocalLlmException.ModelNotDownloaded(LocalLlm.LocalLlmModel.Find(settings.LocalMeetingModel)),
                _ => GeminiException.MissingCredentials(),
            });
        var draft = MeetingJson.Deserialize(MeetingJson.Serialize(meeting));
        draft.Id = meeting.Id;
        if (template is { } t)
        {
            draft.MinutesTemplateId = t.RawValue();
            draft.CustomMinutesPrompt = t == MinutesTemplate.Custom ? customPrompt ?? settings.MeetingCustomMinutesPrompt : null;
        }
        var result = await MeetingProcessor.MakeMinutesAsync(draft, client, settings.MinutesModel, cancellationToken).ConfigureAwait(false);
        meeting.MinutesTemplateId = draft.MinutesTemplateId;
        meeting.CustomMinutesPrompt = draft.CustomMinutesPrompt;
        meeting.Minutes = result.Markdown;
        meeting.ActionItems = result.ActionItems;
        if (meeting.ErrorMessage?.StartsWith("議事録を作れませんでした", StringComparison.Ordinal) == true
            || meeting.ErrorMessage?.StartsWith("Gemini の認証情報", StringComparison.Ordinal) == true
            || meeting.ErrorMessage?.StartsWith("Claude の認証情報", StringComparison.Ordinal) == true)
        {
            meeting.ErrorMessage = null;
        }
        Store(settings).Save(meeting);
        MeetingChanged?.Invoke(this, meeting);
    }

    /// <summary>話者名・メモ・題名を書き換えて保存する（会議ノートから）</summary>
    public void Save(Meeting meeting)
    {
        Store(services.Settings()).Save(meeting);
        MeetingChanged?.Invoke(this, meeting);
    }

    // MARK: - Private

    private static TranscriptionContext Context(AppSettings settings) =>
        new(settings.LocaleIdentifier, settings.UserDictionary.ContextualStrings, settings.MeetingMicrophoneDeviceId);

    private void SetProgress(string? message)
    {
        ProgressMessage = message;
        ProgressChanged?.Invoke(this, message ?? "");
    }

    private void OnMicFaulted(object? sender, Exception e)
    {
        services.Log($"meeting mic faulted: {e.Message}");
        Notice?.Invoke(this, new MeetingNotice("マイクの録音が止まりました", "マイクが抜かれたなどの理由で録音が止まったので、会議の記録を止めます。", true));
        _ = StopAsync();
    }

    private async Task StopRecordersAsync()
    {
        foreach (var recorder in new[] { mic, loopback })
        {
            if (recorder is null) continue;
            try { await recorder.StopAsync().ConfigureAwait(false); }
            catch (Exception e) when (e is IOException or InvalidOperationException) { services.Log($"recorder stop failed: {e.Message}"); }
        }
    }

    private async Task DisposeRecordersAsync()
    {
        if (mic is not null)
        {
            mic.Faulted -= OnMicFaulted;
            await mic.DisposeAsync().ConfigureAwait(false);
            mic = null;
        }
        if (loopback is not null)
        {
            await loopback.DisposeAsync().ConfigureAwait(false);
            loopback = null;
        }
    }
}

/// <summary>呼ばれたスレッドですぐに知らせる IProgress（Progress&lt;T&gt; は SynchronizationContext に乗り、順番が入れ替わることがあるため）</summary>
public sealed class InlineProgress<T>(Action<T> report) : IProgress<T>
{
    public void Report(T value) => report(value);
}
