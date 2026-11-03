using Hanasu.Core.Gemini;
using Hanasu.Core.Settings;

namespace Hanasu.Core.Dictation;

/// <summary>録音を始めたショートカットで決まる。整形して日本語で入力するか、英語に翻訳して入力するか</summary>
public enum DictationMode { Refine, TranslateToEnglish }

public enum ProcessStatus
{
    /// <summary>Gemini で整形（英訳）した</summary>
    Succeeded,
    /// <summary>整形をオフにしていたので、辞書だけ当てた</summary>
    RefineOff,
    /// <summary>認証情報がないので、原文を入力した</summary>
    NoCredentials,
    /// <summary>Gemini が失敗したので、原文を入力した</summary>
    GeminiFailed,
}

/// <summary>整形の結果。Warning があれば HUD でエラーとして知らせる（入力はする）。</summary>
public sealed record ProcessOutcome(string Output, ProcessStatus Status, string? Warning = null);

/// <summary>
/// 認識結果に辞書を当て、Gemini で整形（または英訳）する。失敗したら原文を返して知らせる（話した内容を失わない）。
/// Mac 版の DictationController.finishDictation の中ほどにあたる（スニペット・アプリ別スタイル・画面の文脈は Windows 版にはない）。
/// </summary>
public sealed class DictationTextProcessor
{
    private readonly Func<AppSettings, IDictationRefiner?> refinerFactory;

    /// <param name="refinerFactory">設定から Gemini のクライアントを作る。認証情報がなければ null。サービスアカウントが読めなければ例外</param>
    public DictationTextProcessor(Func<AppSettings, IDictationRefiner?> refinerFactory)
    {
        this.refinerFactory = refinerFactory;
    }

    /// <summary>Gemini に送るか（英訳は Gemini でしかできないので、整形をオフにしていても送る）</summary>
    public static bool UsesGemini(AppSettings settings, DictationMode mode) =>
        settings.RefineWithGemini || mode == DictationMode.TranslateToEnglish;

    public async Task<ProcessOutcome> ProcessAsync(string raw, DictationMode mode, string? appName, AppSettings settings,
        CancellationToken cancellationToken = default)
    {
        var dictionary = settings.UserDictionary;
        // ユーザー辞書の置き換えルールを決定的に当てる（Gemini で整形しないときも効く）
        var corrected = dictionary.Apply(raw);
        if (!UsesGemini(settings, mode)) return new ProcessOutcome(corrected, ProcessStatus.RefineOff);

        var translating = mode == DictationMode.TranslateToEnglish;
        var verb = translating ? "翻訳" : "整形";
        try
        {
            var refiner = refinerFactory(settings);
            if (refiner is null)
            {
                return new ProcessOutcome(corrected, ProcessStatus.NoCredentials,
                    $"Gemini の認証情報が未設定のため、{verb}せずに入力しました（メニュー → 設定）。");
            }
            var request = new RefineRequest
            {
                Transcript = corrected,
                Model = settings.Model,
                AppName = settings.SendAppName ? appName : null,
                Dictionary = dictionary.Spellings,
                ExtraInstructions = settings.ExtraInstructions,
                DictionaryRules = dictionary.Rules,
            };
            var output = translating
                ? await refiner.TranslateToEnglishAsync(request, cancellationToken).ConfigureAwait(false)
                : await refiner.RefineAsync(request, cancellationToken).ConfigureAwait(false);
            return new ProcessOutcome(output, ProcessStatus.Succeeded);
        }
        catch (Exception e) when (e is GeminiException or ServiceAccountException or HttpRequestException)
        {
            return new ProcessOutcome(corrected, ProcessStatus.GeminiFailed, $"{e.Message}\n{verb}前の文章を入力しました。");
        }
    }
}

/// <summary>最近の結果。メモリ上に 10 件だけ持ち、メニューからコピーできるようにする（Mac 版の RecentDictations）。</summary>
public sealed class RecentResults
{
    public const int Capacity = 10;

    public sealed record Entry(DateTimeOffset Time, string Raw, string Output, DictationMode Mode);

    private readonly object gate = new();
    private readonly LinkedList<Entry> entries = new();

    public event EventHandler? Changed;

    /// <summary>新しい順</summary>
    public IReadOnlyList<Entry> Entries
    {
        get { lock (gate) return entries.ToArray(); }
    }

    public void Add(string raw, string output, DictationMode mode, DateTimeOffset? time = null)
    {
        lock (gate)
        {
            entries.AddFirst(new Entry(time ?? DateTimeOffset.Now, raw, output, mode));
            while (entries.Count > Capacity) entries.RemoveLast();
        }
        Changed?.Invoke(this, EventArgs.Empty);
    }

    /// <summary>メニューに出す 1 行（長ければ途中で切る）</summary>
    public static string MenuLabel(Entry entry, int maxChars = 40)
    {
        var text = entry.Output.ReplaceLineEndings(" ").Trim();
        if (text.Length > maxChars) text = text[..maxChars] + "…";
        return $"{entry.Time:HH:mm}  {text}";
    }
}
