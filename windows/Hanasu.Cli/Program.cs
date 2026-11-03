using System.Diagnostics;
using Hanasu.Core.Audio;
using Hanasu.Core.Dictation;
using Hanasu.Core.Gemini;
using Hanasu.Core.Settings;
using Hanasu.Core.Text;
using Hanasu.Core.Transcription;
using Hanasu.Whisper;

// 確認用の CLI。認証は環境変数 GEMINI_SERVICE_ACCOUNT_JSON（サービスアカウントの JSON のパス）か GEMINI_API_KEY。
//   hanasu-cli refine "<文章>" [--translate] [--model <id>] [--app <アプリ名>] [--dict <辞書ファイル>]
//   hanasu-cli transcribe-gemini <wav> [--model <id>] [--dict <辞書ファイル>]
//   hanasu-cli transcribe-whisper <wav> [--model tiny] [--models-dir <dir>] [--download]
//   hanasu-cli dictation <wav> --engine whisper|gemini [--translate] [--whisper-model tiny] [--models-dir <dir>]
//   hanasu-cli dict <辞書ファイル> "<文章>"
//   hanasu-cli models

var command = args.FirstOrDefault();
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
        default:
            Console.Error.WriteLine("使い方: hanasu-cli refine|transcribe-gemini|transcribe-whisper|dictation|dict|models ...（Program.cs の先頭を参照）");
            return 2;
    }
    return 0;
}
catch (Exception e) when (e is GeminiException or ServiceAccountException or TranscriptionException or InvalidDataException or IOException)
{
    Console.Error.WriteLine($"エラー: {e.Message}");
    return 1;
}
finally
{
    // 読み込んだモデルを手放してから終わる（macOS の Metal は、手放さずに終わると終了時に落ちる）
    WhisperBatchTranscriber.ReleaseCachedModel();
}

static string? Option(string[] args, string name)
{
    var i = Array.IndexOf(args, name);
    return i >= 0 && i + 1 < args.Length ? args[i + 1] : null;
}

static bool Flag(string[] args, string name) => args.Contains(name);

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
    var translating = Flag(args, "--translate");
    var processor = new DictationTextProcessor(_ => new GeminiClient(AuthFromEnvironment()));
    var sw = Stopwatch.StartNew();
    var outcome = await processor.ProcessAsync(text, translating ? DictationMode.TranslateToEnglish : DictationMode.Refine,
        Option(args, "--app"), settings);
    Console.WriteLine($"[{(translating ? "英訳" : "整形")} {settings.Model} {sw.Elapsed.TotalSeconds:0.0}s {outcome.Status}]");
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
    var mode = Flag(args, "--translate") ? DictationMode.TranslateToEnglish : DictationMode.Refine;
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
