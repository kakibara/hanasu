using System.Diagnostics;
using System.Net;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Hanasu.Core;
using Hanasu.Core.Ai;
using Hanasu.Core.Audio;
using Hanasu.Core.Claude;
using Hanasu.Core.Dictation;
using Hanasu.Core.Gemini;
using Hanasu.Core.LocalLlm;
using Hanasu.Core.Meetings;
using Hanasu.Core.Settings;
using Hanasu.Core.Text;
using Hanasu.Core.Transcription;
using Hanasu.Diarization;
using Hanasu.Whisper;

// 確認用の CLI。Gemini の認証は環境変数 GEMINI_SERVICE_ACCOUNT_JSON（サービスアカウントの JSON のパス）か GEMINI_API_KEY。
// Claude の認証は環境変数 ANTHROPIC_API_KEY（claude-request はキーなしで動く。キーは表示しない）。
//   hanasu-cli claude-request "<文章>" [--translate | --translate-to en|ja | --minutes] [--model <id>]   送らずに、送る HTTP リクエスト（ヘッダーと本文）を出す
//   hanasu-cli claude-refine "<文章>" [--translate | --translate-to en|ja] [--model <id>] [--app <アプリ名>] [--dict <辞書ファイル>]   Claude で整形・英訳する
//   hanasu-cli claude-check [--model <id>] [--fake-key]   「接続を試す」と同じ確かめ。--fake-key は偽のキーで送り、401 の文言を見る
//   hanasu-cli refine "<文章>" [--translate | --translate-to en|ja] [--model <id>] [--app <アプリ名>] [--dict <辞書ファイル>]
//   hanasu-cli transcribe-gemini <wav> [--model <id>] [--dict <辞書ファイル>]
//   hanasu-cli transcribe-whisper <wav> [--model tiny] [--models-dir <dir>] [--download]
//   hanasu-cli dictation <wav> --engine whisper|gemini [--translate | --translate-to en|ja] [--whisper-model tiny] [--models-dir <dir>]
//   hanasu-cli dict <辞書ファイル> "<文章>"
//   hanasu-cli models
//   hanasu-cli meeting-files <自分の wav> <相手の wav> --meetings-dir <保存先> [--engine whisper|gemini] [--whisper-model tiny] [--models-dir <dir>]
//              [--download] [--others-offset <秒>] [--me-offset <秒>] [--template regular] [--notes <メモのファイル>] [--no-minutes]
//              [--no-diarize] [--diarization-models-dir <dir>] [--minutes-model <id>] [--model <文字起こしの Gemini のモデル>] [--delete-audio]
//     会議の後処理（チャンネルごとの文字起こし → 話者分離 → 話者の割り当て → 議事録）を、2 つの音声ファイルで通す
//   hanasu-cli meeting-minutes <会議のフォルダ> [--template <型>] [--minutes-model <id>]   議事録を作り直す
//   hanasu-cli meeting-show <会議のフォルダ>   meeting.json を読んで中身を出す（Mac で作った会議が読めるかの確認）
// ローカルの LLM（llama.cpp の llama-server。--server <パス> か環境変数 HANASU_LLAMA_SERVER、なければ exe の隣の llama/。Mac の llama-server でも動く）:
//   hanasu-cli local-list [--models-dir <dir>]   モデルの一覧（ダウンロード済みか）
//   hanasu-cli local-download <id> [--models-dir <dir>]   モデルをダウンロードし、大きさと SHA-256 を確かめる
//   hanasu-cli local-refine "<文章>" [--model <id>] [--translate | --translate-to en|ja] [--server <パス>] [--models-dir <dir>]   ローカルで整形・英訳する
//   meeting-minutes / meeting-files に --minutes-ai local --minutes-model <id> を付けると、議事録をローカルで作る
// どのコマンドにも --prompt-language <言語>（en、ja、zh-TW、pt-BR など。ja-JP のような識別子でもよい）を付けると、
// AI へのプロンプトをその言語で組み立てる（省くと設定の文字起こしの言語。Mac 版の CLI の --prompt-language と同じ）。
// 対応していない言語を書いたら止める。例: claude-request "テスト" --prompt-language en

var command = args.FirstOrDefault();
// 確かめ方: REQ-COM-061
if (Option(args, "--prompt-language") is { } promptLanguage)
{
    PromptLanguage.Override = PromptLanguage.FromCode(promptLanguage) ?? PromptLanguage.SupportedOrNull(promptLanguage);
    if (PromptLanguage.Override is null)
    {
        Console.Error.WriteLine($"error: --prompt-language は {string.Join("|", PromptLanguage.All.Select(l => l.Code))} のどれか（{promptLanguage} は対応していない）");
        return 2;
    }
}
else
{
    // 省いたときは、アプリと同じく設定の文字起こしの言語（設定のファイルがなければ設定の既定）
    PromptLanguage.UseSettings(new SettingsStore().Load().LocaleIdentifier);
}
try
{
    switch (command)
    {
        case "refine": await Refine(args); break;
        case "transcribe-gemini": await TranscribeGemini(args); break;
        case "transcribe-whisper": await TranscribeWhisper(args); break;
        case "dictation": await Dictation(args); break;
        case "dict": Dict(args); break;
        case "models": Models(); break;
        case "meeting-files": await MeetingFiles(args); break;
        case "meeting-minutes": await MeetingMinutes(args); break;
        case "meeting-show": MeetingShow(args); break;
        case "claude-request": await ClaudeRequest(args); break;
        case "claude-refine": await ClaudeRefine(args); break;
        case "claude-check": await ClaudeCheck(args); break;
        case "local-list": LocalList(args); break;
        case "local-download": await LocalDownload(args); break;
        case "local-refine": await LocalRefine(args); break;
        default:
            Console.Error.WriteLine("使い方: hanasu-cli refine|transcribe-gemini|transcribe-whisper|dictation|dict|models|meeting-files|meeting-minutes|meeting-show|claude-request|claude-refine|claude-check|local-list|local-download|local-refine ...（Program.cs の先頭を参照）");
            return 2;
    }
    return 0;
}
catch (Exception e) when (e is TextAiException or ServiceAccountException or TranscriptionException or InvalidDataException or IOException)
{
    Console.Error.WriteLine($"エラー: {SecretRedactor.Redact(e.Message)}");
    return 1;
}
finally
{
    // 読み込んだモデルを手放してから終わる（macOS の Metal は、手放さずに終わると終了時に落ちる）
    WhisperBatchTranscriber.ReleaseCachedModel();
    // 起動したローカルの LLM のサーバーを止める
    LocalLlmServer.Shared.Stop();
}

static string? Option(string[] args, string name)
{
    var i = Array.IndexOf(args, name);
    return i >= 0 && i + 1 < args.Length ? args[i + 1] : null;
}

static bool Flag(string[] args, string name) => args.Contains(name);

// 確かめ方: REQ-DIC-013
/// <summary>--translate（英訳）か --translate-to en|ja。どちらもなければ null</summary>
static TranslationLanguage? TranslationOption(string[] args) => Option(args, "--translate-to")?.ToLowerInvariant() switch
{
    "ja" or "japanese" => TranslationLanguage.Japanese,
    "en" or "english" => TranslationLanguage.English,
    null => Flag(args, "--translate") ? TranslationLanguage.English : null,
    var other => throw new IOException($"--translate-to は en か ja です（{other}）"),
};

static GeminiAuth AuthFromEnvironment()
{
    if (Environment.GetEnvironmentVariable("GEMINI_SERVICE_ACCOUNT_JSON") is { Length: > 0 } path)
    {
        return new GeminiAuth.ServiceAccount(ServiceAccountCredentials.Load(path),
            Environment.GetEnvironmentVariable("GEMINI_VERTEX_LOCATION") ?? "global");
    }
    if (Environment.GetEnvironmentVariable("GEMINI_API_KEY") is { Length: > 0 } key) return new GeminiAuth.ApiKey(key);
    throw GeminiException.MissingCredentials();
}

static ClaudeClient ClaudeFromEnvironment(TimeSpan timeout) =>
    Environment.GetEnvironmentVariable("ANTHROPIC_API_KEY") is { Length: > 0 } key
        ? new ClaudeClient(key) { Timeout = timeout }
        : throw ClaudeException.MissingCredentials();

static UserDictionary LoadDictionary(string[] args) =>
    new(Option(args, "--dict") is { } file ? File.ReadAllText(file) : "");

static AppSettings CliSettings(string[] args)
{
    var settings = new AppSettings
    {
        Model = Option(args, "--model") ?? AppSettings.SuggestedModels[0],
        DictionaryText = Option(args, "--dict") is { } file ? File.ReadAllText(file) : "",
        ExtraInstructions = Option(args, "--rules") ?? "",
    };
    return settings;
}

static async Task Refine(string[] args)
{
    var text = args.ElementAtOrDefault(1) ?? throw new IOException("文章を指定してください");
    var settings = CliSettings(args);
    var translation = TranslationOption(args);
    var processor = new DictationTextProcessor(_ => new GeminiClient(AuthFromEnvironment()));
    var sw = Stopwatch.StartNew();
    var outcome = await processor.ProcessAsync(text, translation?.ToMode() ?? DictationMode.Refine,
        Option(args, "--app"), settings);
    Console.WriteLine($"[{translation?.Verb() ?? "整形"} {settings.Model} {sw.Elapsed.TotalSeconds:0.0}s {outcome.Status}]");
    if (outcome.Warning is not null) Console.WriteLine($"警告: {outcome.Warning}");
    Console.WriteLine(outcome.Output);
}

static async Task TranscribeGemini(string[] args)
{
    var samples = WavFile.DecodeTo16kMono(File.ReadAllBytes(args[1]));
    var settings = CliSettings(args);
    var transcriber = new GeminiBatchTranscriber(() => new GeminiClient(AuthFromEnvironment()) { Timeout = TimeSpan.FromSeconds(60) },
        () => settings.Model, () => settings.DictionaryWords);
    var context = new TranscriptionContext("ja-JP", settings.UserDictionary.ContextualStrings, "");
    await transcriber.PrepareAsync(context);
    var sw = Stopwatch.StartNew();
    var text = await transcriber.TranscribeAsync(samples, context);
    Console.WriteLine($"[Gemini 文字起こし {settings.Model} 音声 {samples.Length / (double)AudioFormat.SampleRate:0.0}s / {sw.Elapsed.TotalSeconds:0.0}s]");
    Console.WriteLine(text);
}

static async Task<string> EnsureWhisperModel(string[] args, string optionName)
{
    var model = WhisperModelCatalog.Find(Option(args, optionName) ?? "tiny") ?? throw new IOException("モデルが見つかりません（models で一覧）");
    var manager = new WhisperModelManager(Option(args, "--models-dir") ?? HanasuPaths.ModelsDirectory);
    if (!manager.IsDownloaded(model))
    {
        if (!Flag(args, "--download")) throw new IOException($"モデル {model.Id} がありません。--download を付けるとダウンロードします（{model.SizeLabel}）");
        var last = -1;
        manager.StateChanged += (_, s) =>
        {
            var percent = (int)(s.Progress * 100);
            if (percent / 10 != last / 10) { last = percent; Console.Error.WriteLine($"ダウンロード中 {percent}%"); }
        };
        await manager.DownloadAsync(model);
        if (manager.StateOf(model) is { Status: WhisperModelStatus.Failed, Error: var error }) throw new IOException(error);
    }
    return manager.PathFor(model);
}

static async Task TranscribeWhisper(string[] args)
{
    var samples = WavFile.DecodeTo16kMono(File.ReadAllBytes(args[1]));
    var path = await EnsureWhisperModel(args, "--model");
    var transcriber = new WhisperBatchTranscriber(() => path, () => Path.GetFileName(path));
    var context = new TranscriptionContext("ja-JP", LoadDictionary(args).ContextualStrings, "");
    var sw = Stopwatch.StartNew();
    await transcriber.PrepareAsync(context);
    var text = await transcriber.TranscribeAsync(samples, context);
    Console.WriteLine($"[Whisper {Path.GetFileName(path)} 音声 {samples.Length / (double)AudioFormat.SampleRate:0.0}s / {sw.Elapsed.TotalSeconds:0.0}s（読み込み込み）]");
    Console.WriteLine(text);
}

/// <summary>音声入力の流れ（文字起こし → 辞書 → Gemini 整形）を、マイクの代わりに WAV で通す</summary>
static async Task Dictation(string[] args)
{
    var samples = WavFile.DecodeTo16kMono(File.ReadAllBytes(args[1]));
    var settings = CliSettings(args);
    var engine = Option(args, "--engine") ?? "gemini";
    IBatchTranscriber batch = engine == "whisper"
        ? new WhisperBatchTranscriber(() => EnsureWhisperModel(args, "--whisper-model").GetAwaiter().GetResult(), () => "whisper")
        : new GeminiBatchTranscriber(() => new GeminiClient(AuthFromEnvironment()) { Timeout = TimeSpan.FromSeconds(60) },
            () => settings.Model, () => settings.DictionaryWords);
    var transcriber = new RecordThenTranscribe(new WavRecorder(samples), batch);
    var context = new TranscriptionContext("ja-JP", settings.UserDictionary.ContextualStrings, "");
    var sw = Stopwatch.StartNew();
    await transcriber.StartAsync(context);
    var raw = await transcriber.StopAsync();
    Console.WriteLine($"[文字起こし {engine} {sw.Elapsed.TotalSeconds:0.0}s] {raw}");
    sw.Restart();
    var mode = TranslationOption(args)?.ToMode() ?? DictationMode.Refine;
    var outcome = await new DictationTextProcessor(_ => new GeminiClient(AuthFromEnvironment())).ProcessAsync(raw, mode, Option(args, "--app"), settings);
    Console.WriteLine($"[{mode} {settings.Model} {sw.Elapsed.TotalSeconds:0.0}s {outcome.Status}] {outcome.Output}");
}

static void Dict(string[] args)
{
    var dictionary = new UserDictionary(File.ReadAllText(args[1]));
    foreach (var (index, issue) in dictionary.Issues) Console.WriteLine($"注意（{index + 1} 行目）: {issue}");
    var (text, replacements) = dictionary.ApplyWithLog(args[2]);
    foreach (var r in replacements) Console.WriteLine($"置き換え: {r.Matched} → {r.Target}");
    Console.WriteLine(text);
}

static void Models()
{
    foreach (var m in WhisperModelCatalog.Models) Console.WriteLine($"{m.Id}\t{m.SizeLabel}\t{m.Description}\t{m.DownloadUri}");
}

/// <summary>
/// 会議の後処理を、マイクとループバックの代わりに 2 つの音声ファイルで通す。会議は --meetings-dir の下に作る
/// （~/Documents/Hanasu/Meetings には書かないよう、保存先は必ず指定させる）
/// </summary>
static async Task MeetingFiles(string[] args)
{
    var mePath = args.ElementAtOrDefault(1) ?? throw new IOException("自分の音声（WAV）を指定してください");
    var othersPath = args.ElementAtOrDefault(2) ?? throw new IOException("相手の音声（WAV）を指定してください");
    var dir = Option(args, "--meetings-dir") ?? throw new IOException("--meetings-dir で保存先を指定してください");
    var settings = CliSettings(args);
    var store = new MeetingStore(dir);
    var meeting = store.NewMeeting(DateTimeOffset.Now);
    if (Option(args, "--template") is { } templateName)
    {
        var template = MinutesTemplates.FromRawValue(templateName) ?? throw new IOException($"議事録の型が見つかりません: {templateName}");
        meeting.MinutesTemplateId = template.RawValue();
        if (template == MinutesTemplate.Custom) meeting.CustomMinutesPrompt = MinutesTemplates.DefaultCustomPrompt;
    }
    if (Option(args, "--notes") is { } notesFile) meeting.Notes = MeetingNote.Parse(File.ReadAllText(notesFile));

    // 録音のかわりに、音声を 16 kHz・モノラルの WAV にして会議のフォルダに置く
    double Seconds(string name) => double.Parse(Option(args, name) ?? "0", System.Globalization.CultureInfo.InvariantCulture);
    var me = WavFile.DecodeTo16kMono(File.ReadAllBytes(mePath));
    var others = WavFile.DecodeTo16kMono(File.ReadAllBytes(othersPath));
    File.WriteAllBytes(store.AudioPath(meeting, MeetingChannel.Me), WavFile.Encode(me));
    File.WriteAllBytes(store.AudioPath(meeting, MeetingChannel.Others), WavFile.Encode(others));
    meeting.AudioStartOffsets = new() { ["me"] = Seconds("--me-offset"), ["others"] = Seconds("--others-offset") };
    meeting.Duration = Math.Max(Seconds("--me-offset") + me.Length / (double)AudioFormat.SampleRate,
        Seconds("--others-offset") + others.Length / (double)AudioFormat.SampleRate);

    var engine = Option(args, "--engine") ?? "whisper";
    ISegmentTranscriber transcriber = engine == "gemini"
        ? new GeminiSegmentTranscriber(() => new GeminiClient(AuthFromEnvironment()) { Timeout = TimeSpan.FromSeconds(300) }, () => settings.Model)
        : new WhisperBatchTranscriber(() => EnsureWhisperModel(args, "--whisper-model").GetAwaiter().GetResult(), () => "whisper");
    var diarizationDir = Option(args, "--diarization-models-dir") ?? Path.Combine(HanasuPaths.ModelsDirectory, "diarization");
    var processor = new MeetingPostProcessor
    {
        Store = store,
        Transcriber = transcriber,
        Context = new TranscriptionContext("ja-JP", settings.UserDictionary.ContextualStrings, ""),
        Diarizer = Flag(args, "--no-diarize") ? null : new SherpaSpeakerDiarizer(new DiarizationModels(diarizationDir)),
        MinutesClient = Flag(args, "--no-minutes") ? null : () => MinutesClientFromEnvironment(args),
        MinutesModel = Option(args, "--minutes-model") ?? DefaultMinutesModel(args),
        MinutesProvider = Option(args, "--minutes-ai") switch { "claude" => TextAiProvider.Claude, "local" => TextAiProvider.Local, _ => TextAiProvider.Gemini },
        KeepAudio = !Flag(args, "--delete-audio"),
        Log = m => Console.Error.WriteLine($"[log] {m}"),
    };
    var sw = Stopwatch.StartNew();
    string? last = null;
    var result = await processor.ProcessAsync(meeting, new InlineProgress<string>(m =>
    {
        // Whisper の進み具合（%）は 25% ごとにだけ出す
        var percent = System.Text.RegularExpressions.Regex.Match(m, @"(\d+)%）$");
        if (m == last || (percent.Success && int.Parse(percent.Groups[1].Value) % 25 != 0)) return;
        last = m;
        Console.Error.WriteLine($"[{sw.Elapsed.TotalSeconds,5:0.0}s] {m}");
    }));
    foreach (var w in result.Warnings) Console.WriteLine($"警告: {w}");
    PrintMeeting(store.DirectoryOf(meeting), result.Meeting);
    Console.WriteLine($"[後処理 {sw.Elapsed.TotalSeconds:0.0}s]");
}

static async Task MeetingMinutes(string[] args)
{
    var folder = Path.GetFullPath(args.ElementAtOrDefault(1) ?? throw new IOException("会議のフォルダを指定してください"));
    var store = new MeetingStore(Path.GetDirectoryName(folder));
    var meeting = store.Load(Path.GetFileName(folder)) ?? throw new IOException("meeting.json を読めません");
    if (Option(args, "--template") is { } name)
    {
        meeting.MinutesTemplateId = (MinutesTemplates.FromRawValue(name) ?? throw new IOException($"議事録の型が見つかりません: {name}")).RawValue();
    }
    var sw = Stopwatch.StartNew();
    var result = await MeetingProcessor.MakeMinutesAsync(meeting, MinutesClientFromEnvironment(args),
        Option(args, "--minutes-model") ?? DefaultMinutesModel(args));
    // 確かめ方: REQ-MTG-027（会話から分かった話者の名前も付けて表示する）
    meeting.ApplyMinutes(result);
    store.Save(meeting);
    Console.WriteLine($"[議事録 {sw.Elapsed.TotalSeconds:0.0}s]");
    var inferred = (meeting.InferredSpeakers ?? new()).Select(k => $"{k}={meeting.SpeakerNames.GetValueOrDefault(k)}").ToList();
    Console.WriteLine($"[推測した話者の名前] 応答: {(result.SpeakerNames.Count == 0 ? "なし" : string.Join(", ", result.SpeakerNames.OrderBy(p => p.Key, StringComparer.Ordinal).Select(p => $"{p.Key}={p.Value}")))}"
        + $" / 付けた: {(inferred.Count == 0 ? "なし" : string.Join(", ", inferred))}");
    Console.WriteLine(meeting.Minutes);
}

/// <summary>議事録の AI（--minutes-ai gemini|claude|local。既定は gemini）</summary>
static ITextGenerator MinutesClientFromEnvironment(string[] args) =>
    Option(args, "--minutes-ai") switch
    {
        "claude" => ClaudeFromEnvironment(TimeSpan.FromSeconds(300)),
        "local" => LocalClient(args, Option(args, "--minutes-model"), LocalLlmModel.DefaultMeeting, TextAiUse.Meeting),
        _ => new GeminiClient(AuthFromEnvironment()) { Timeout = TimeSpan.FromSeconds(180) },
    };

static string DefaultMinutesModel(string[] args) =>
    Option(args, "--minutes-ai") switch
    {
        "claude" => ClaudeModels.DefaultMinutesModel,
        "local" => LocalLlmModel.DefaultMeeting.Id,
        _ => "gemini-3.8-flash",
    };

// MARK: - ローカルの LLM

/// <summary>--server・--models-dir を Shared のサーバーに当てる</summary>
static LocalLlmServer ConfigureLocalServer(string[] args)
{
    var server = LocalLlmServer.Shared;
    if (Option(args, "--server") is { } path) server.ExecutablePath = Path.GetFullPath(path);
    if (Option(args, "--models-dir") is { } dir) server.ModelsDirectory = Path.GetFullPath(dir);
    server.Log = message => Console.Error.WriteLine($"[{message}]");
    return server;
}

static LocalLlmModel LocalModelOption(string? id, LocalLlmModel fallback) =>
    id is null ? fallback : LocalLlmModel.Find(id) ?? throw new IOException($"ローカルのモデルが見つかりません: {id}（{string.Join(" / ", LocalLlmModel.All.Select(m => m.Id))}）");

static LocalLlmClient LocalClient(string[] args, string? id, LocalLlmModel fallback, TextAiUse use)
{
    var server = ConfigureLocalServer(args);
    var model = LocalModelOption(id, fallback);
    if (!server.IsDownloaded(model)) throw LocalLlmException.ModelNotDownloaded(model);
    return new LocalLlmClient(model, server) { Timeout = LocalLlmClient.MinimumTimeout(use) };
}

// 確かめ方: REQ-COM-030
static void LocalList(string[] args)
{
    var server = ConfigureLocalServer(args);
    foreach (var model in LocalLlmModel.All)
    {
        Console.WriteLine($"{(server.IsDownloaded(model) ? "✓" : "-")} {model.Id,-16} {model.Label}  文脈 {model.ContextLength}  {model.License}");
    }
    Console.WriteLine($"置き場所: {server.ModelsDirectory}");
    Console.WriteLine($"llama-server: {server.ExecutablePath ?? LocalLlmServer.ResolveExecutable() ?? "見つかりません（--server か HANASU_LLAMA_SERVER で指定できます）"}");
}

// 確かめ方: REQ-COM-030
static async Task LocalDownload(string[] args)
{
    var server = ConfigureLocalServer(args);
    var model = LocalModelOption(args.ElementAtOrDefault(1) ?? throw new IOException("モデルの id を指定してください"), LocalLlmModel.DefaultDictation);
    var manager = new LocalLlmModelManager(server);
    var lastStep = -1;
    var sw = Stopwatch.StartNew();
    await manager.DownloadAsync(model, (received, total) =>
    {
        var step = (int)(received * 10 / Math.Max(1, total));
        if (step <= lastStep) return;
        lastStep = step;
        Console.WriteLine($"  {step * 10}%");
    });
    if (manager.LastError(model) is { } error) throw new IOException(error);
    Console.WriteLine($"確かめました: {server.ModelPath(model)}（{sw.Elapsed.TotalSeconds:0} 秒）");
}

// 確かめ方: REQ-COM-030
static async Task LocalRefine(string[] args)
{
    var text = args.ElementAtOrDefault(1) ?? throw new IOException("文章を指定してください");
    var client = LocalClient(args, Option(args, "--model"), LocalLlmModel.DefaultDictation, TextAiUse.Dictation);
    var request = ClaudeRefineRequest(args, text, client.Model.Id);
    var translation = TranslationOption(args);
    var sw = Stopwatch.StartNew();
    var output = translation is { } language ? await client.TranslateAsync(request, language) : await client.RefineAsync(request);
    Console.WriteLine($"[{translation?.Verb() ?? "整形"} ローカル {client.Model.Id} {sw.Elapsed.TotalSeconds:0.0}s]");
    Console.WriteLine(output);
}

static void MeetingShow(string[] args)
{
    var folder = Path.GetFullPath(args.ElementAtOrDefault(1) ?? throw new IOException("会議のフォルダを指定してください"));
    var meeting = new MeetingStore(Path.GetDirectoryName(folder)).Load(Path.GetFileName(folder)) ?? throw new IOException("meeting.json を読めません");
    PrintMeeting(folder, meeting);
}

static void PrintMeeting(string folder, Meeting meeting)
{
    Console.WriteLine($"会議: {meeting.Title}（{meeting.Status}、{Meeting.Clock(meeting.Duration)}、型: {meeting.Template.Title()}）");
    Console.WriteLine($"保存先: {folder}");
    if (meeting.ErrorMessage is not null) Console.WriteLine($"エラー: {meeting.ErrorMessage}");
    Console.WriteLine($"話者: {string.Join("、", meeting.Speakers.Select(s => $"{s}={meeting.DisplayName(s)}"))}");
    Console.WriteLine();
    Console.WriteLine(meeting.TranscriptForPrompt());
    if (meeting.AllNotes.Count > 0)
    {
        Console.WriteLine();
        Console.WriteLine(meeting.NotesText);
    }
    if (meeting.Minutes is not null)
    {
        Console.WriteLine();
        Console.WriteLine(meeting.Minutes);
    }
    foreach (var item in meeting.ResolvedActionItems) Console.WriteLine($"アクション: {item.MarkdownLine}");
}

// MARK: - Claude

static RefineRequest ClaudeRefineRequest(string[] args, string text, string defaultModel)
{
    var dictionary = LoadDictionary(args);
    return new RefineRequest
    {
        Transcript = dictionary.Apply(text),
        Model = Option(args, "--model") ?? defaultModel,
        AppName = Option(args, "--app"),
        Dictionary = dictionary.Spellings,
        DictionaryRules = dictionary.Rules,
        ExtraInstructions = Option(args, "--rules") ?? "",
    };
}

/// <summary>送らずに、SDK が組み立てる HTTP リクエストを出す（キーは伏せる）。キーがなければ架空のキーで組み立てる</summary>
// 確かめ方: REQ-COM-020
static async Task ClaudeRequest(string[] args)
{
    var text = args.ElementAtOrDefault(1) ?? throw new IOException("文章を指定してください");
    var translation = TranslationOption(args);
    var purpose = Flag(args, "--minutes") ? TextPurpose.Minutes : translation is not null ? TextPurpose.Translate : TextPurpose.Refine;
    var request = ClaudeRefineRequest(args, text, purpose == TextPurpose.Minutes ? ClaudeModels.DefaultMinutesModel : ClaudeModels.DefaultModel);
    var key = Environment.GetEnvironmentVariable("ANTHROPIC_API_KEY") is { Length: > 0 } k ? k : "sk-ant-api03-dry-run-not-a-real-key-0000";
    var capture = new CaptureHandler();
    var client = new ClaudeClient(key, new HttpClient(capture));
    var (system, user) = purpose switch
    {
        TextPurpose.Translate => (GeminiPrompts.TranslationSystemInstruction(translation!.Value), GeminiPrompts.UserPrompt(request, translation)),
        TextPurpose.Minutes => (MinutesPrompt.SystemInstruction(MinutesTemplate.Regular, null), $"<transcript>\n{PromptText.NeutralizeDelimiters(text)}\n</transcript>"),
        _ => (GeminiPrompts.SystemInstruction(request.OutputLanguage), GeminiPrompts.UserPrompt(request)),
    };
    await client.GenerateTextAsync(purpose, system, user, request.Model);
    var sent = capture.Requests.Single();
    Console.WriteLine($"{sent.Method} {sent.Uri}");
    foreach (var (name, value) in sent.Headers.OrderBy(h => h.Name, StringComparer.OrdinalIgnoreCase))
    {
        var shown = name.Equals("x-api-key", StringComparison.OrdinalIgnoreCase) || name.Equals("authorization", StringComparison.OrdinalIgnoreCase)
            ? (value.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase) ? "Bearer " + SecretRedactor.Mask(value[7..]) : SecretRedactor.Mask(value))
            : value;
        Console.WriteLine($"{name}: {shown}");
    }
    Console.WriteLine();
    Console.WriteLine(JsonNode.Parse(sent.Body ?? "{}")!.ToJsonString(new JsonSerializerOptions
    {
        WriteIndented = true,
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    }));
}

/// <summary>Claude で整形・英訳する（ANTHROPIC_API_KEY が要る）。使ったトークン（キャッシュを含む）も出す</summary>
// 確かめ方: REQ-COM-020
static async Task ClaudeRefine(string[] args)
{
    var text = args.ElementAtOrDefault(1) ?? throw new IOException("文章を指定してください");
    var request = ClaudeRefineRequest(args, text, ClaudeModels.DefaultModel);
    var client = ClaudeFromEnvironment(TimeSpan.FromSeconds(60));
    var translation = TranslationOption(args);
    var sw = Stopwatch.StartNew();
    var output = translation is { } language ? await client.TranslateAsync(request, language) : await client.RefineAsync(request);
    var u = client.LastUsage;
    Console.WriteLine($"[{translation?.Verb() ?? "整形"} {request.Model} {sw.Elapsed.TotalSeconds:0.0}s 入力 {u?.InputTokens} / 出力 {u?.OutputTokens} / キャッシュ作成 {u?.CacheCreationInputTokens} / キャッシュ読み {u?.CacheReadInputTokens} / 応答したモデル {u?.ServedBy}]");
    Console.WriteLine(output);
}

/// <summary>「接続を試す」と同じ確かめ（GET /v1/models/{id}）。--fake-key で偽のキーを送り、401 の文言を出す</summary>
// 確かめ方: REQ-COM-020
static async Task ClaudeCheck(string[] args)
{
    var model = Option(args, "--model") ?? ClaudeModels.DefaultModel;
    var client = Flag(args, "--fake-key")
        ? new ClaudeClient("sk-ant-api03-hanasu-fake-key-for-401-check-0000") { Timeout = TimeSpan.FromSeconds(20) }
        : ClaudeFromEnvironment(TimeSpan.FromSeconds(20));
    try
    {
        await client.CheckAsync(model);
        Console.WriteLine($"接続できました。{model} を使えます。");
    }
    catch (ClaudeException e)
    {
        Console.WriteLine($"[{e.Kind} {e.StatusCode}] {e.Message}");
        if (!Flag(args, "--fake-key")) throw;
    }
}

/// <summary>SDK が送る HTTP リクエストを受け取り、送らずに決まった応答を返す</summary>
sealed class CaptureHandler : HttpMessageHandler
{
    public sealed record Captured(string Method, Uri? Uri, List<(string Name, string Value)> Headers, string? Body);

    public List<Captured> Requests { get; } = new();

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var headers = request.Headers.SelectMany(h => h.Value.Select(v => (h.Key, v))).ToList();
        if (request.Content is not null) headers.AddRange(request.Content.Headers.SelectMany(h => h.Value.Select(v => (h.Key, v))));
        var body = request.Content is null ? null : await request.Content.ReadAsStringAsync(cancellationToken);
        Requests.Add(new Captured(request.Method.Method, request.RequestUri, headers, body));
        const string reply = """
            {"id":"msg_dry_run","type":"message","role":"assistant","model":"claude-haiku-5-5",
             "content":[{"type":"text","text":"（送らずに表示しただけ）"}],"stop_reason":"end_turn","stop_sequence":null,
             "usage":{"input_tokens":0,"output_tokens":0}}
            """;
        return new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(reply, Encoding.UTF8, "application/json") };
    }
}

/// <summary>マイクの代わりに、決まった音声を返す</summary>
sealed class WavRecorder(float[] samples) : IAudioRecorder
{
    public event EventHandler<float[]>? SamplesAvailable;
    public event EventHandler<Exception>? Faulted { add { } remove { } }
    public Task StartAsync(string deviceId, CancellationToken cancellationToken = default)
    {
        SamplesAvailable?.Invoke(this, samples);
        return Task.CompletedTask;
    }
    public Task<float[]> StopAsync() => Task.FromResult(samples);
    public ValueTask DisposeAsync() => ValueTask.CompletedTask;
}
