using Anthropic;
using Anthropic.Models.Beta.Messages;
using Hanasu.Core.Ai;
using Hanasu.Core.Gemini;

namespace Hanasu.Core.Claude;

/// <summary>1 回の呼び出しで使ったトークン（確認用。キャッシュが効いたかを見る）</summary>
public sealed record ClaudeUsage(long InputTokens, long OutputTokens, long CacheCreationInputTokens, long CacheReadInputTokens, string ServedBy);

/// <summary>
/// Claude（Anthropic の Claude API）で、文章の処理（整形・英訳・議事録）をする。公式の C# SDK（NuGet の Anthropic）を使う。
/// 音声は送らない（Claude は音声の入力に対応していない。文字起こしは OS 標準・Whisper・Gemini のまま）。
/// - API キーは送るたびに読む（メモリ上に長く持たない）
/// - 送り先は https://api.anthropic.com に固定する（環境変数 ANTHROPIC_BASE_URL などを読まない）
/// - Sonnet 5.5 / Opus 5.5 は、安全の判定で断られたときにサーバー側で別のモデルに切り替える（fallbacks: "default"）。Haiku 5.5 にはない
/// </summary>
// 要件: REQ-COM-020
// 設計判断: DEC-COM-141, DEC-COM-142, DEC-COM-145
public sealed class ClaudeClient : ITextAiClient
{
    public static readonly Uri ApiBaseUrl = new("https://api.anthropic.com");

    /// <summary>fallbacks: "default" に要る beta のヘッダー（一覧の形の fallbacks は別の -2026-06-01）</summary>
    public const string ServerSideFallbackBeta = "server-side-fallback-2026-07-01";

    private static readonly HttpClient SharedHttp = SafeHttp.Create();

    private readonly Func<CancellationToken, Task<string?>> loadApiKey;
    private readonly HttpClient http;

    /// <summary>1 回の呼び出しの待ち時間の上限（やり直しを含む）。音声入力は 15 秒（Gemini と同じ）</summary>
    public TimeSpan Timeout { get; init; } = TimeSpan.FromSeconds(15);

    /// <summary>429・5xx（529 を含む）・つながらないときに SDK がやり直す回数（retry-after を見て待つ）</summary>
    public int MaxRetries { get; init; } = 2;

    /// <summary>最後の呼び出しの使用量（CLI の確認用）</summary>
    public ClaudeUsage? LastUsage { get; private set; }

    public string ProviderName => "Claude";

    public ClaudeClient(string apiKey, HttpClient? http = null)
        : this(_ => Task.FromResult<string?>(apiKey), http)
    {
    }

    /// <param name="loadApiKey">送るたびに呼ぶ。保存されていなければ null</param>
    public ClaudeClient(Func<CancellationToken, Task<string?>> loadApiKey, HttpClient? http = null)
    {
        this.loadApiKey = loadApiKey;
        this.http = http ?? SharedHttp;
    }

    // プロンプトは Gemini と同じ文面を使う（Mac 版と共有の言語ごとの JSON から読む。DEC-COM-102）
    public Task<string> RefineAsync(RefineRequest request, CancellationToken cancellationToken = default) =>
        GenerateTextAsync(TextPurpose.Refine, GeminiPrompts.SystemInstruction(request.OutputLanguage), GeminiPrompts.UserPrompt(request), request.Model, cancellationToken);

    public Task<string> TranslateAsync(RefineRequest request, Dictation.TranslationLanguage language, CancellationToken cancellationToken = default) =>
        GenerateTextAsync(TextPurpose.Translate, GeminiPrompts.TranslationSystemInstruction(language), GeminiPrompts.UserPrompt(request, language),
            request.Model, cancellationToken);

    public async Task<string> GenerateTextAsync(TextPurpose purpose, string systemInstruction, string userText, string model,
        CancellationToken cancellationToken = default)
    {
        model = ClaudeModels.Normalize(model, purpose.IsLong() ? ClaudeModels.DefaultMinutesModel : ClaudeModels.DefaultModel);
        var parameters = BuildParams(purpose, systemInstruction, userText, model);
        // キーは待ち時間を数え始める前に読む（Windows Hello の確認に時間がかかっても、時間切れにしない）
        var client = await CreateSdkClientAsync(cancellationToken).ConfigureAwait(false);
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(Timeout);
        try
        {
            var message = await client.Beta.Messages.Create(parameters, timeout.Token).ConfigureAwait(false);
            LastUsage = ReadUsage(message);
            return ReadText(message);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw ClaudeException.Timeout(Timeout);
        }
        catch (Exception e) when (e is not ClaudeException && ClaudeException.FromSdk(e, model) is { } classified)
        {
            throw classified;
        }
    }

    /// <summary>
    /// 「接続を試す」。モデルの情報を取るだけ（GET /v1/models/{id}。トークンを使わない）。
    /// キーが正しくなければ 401、そのモデルを使えなければ 404 の ClaudeException を投げる
    /// </summary>
    public async Task CheckAsync(string model, CancellationToken cancellationToken = default)
    {
        model = ClaudeModels.Normalize(model);
        var client = await CreateSdkClientAsync(cancellationToken).ConfigureAwait(false);
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(Timeout);
        try
        {
            await client.Models.Retrieve(model, cancellationToken: timeout.Token).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw ClaudeException.Timeout(Timeout);
        }
        catch (Exception e) when (e is not ClaudeException && ClaudeException.FromSdk(e, model) is { } classified)
        {
            throw classified;
        }
    }

    private async Task<AnthropicClient> CreateSdkClientAsync(CancellationToken cancellationToken)
    {
        var key = (await loadApiKey(cancellationToken).ConfigureAwait(false))?.Trim();
        if (string.IsNullOrEmpty(key)) throw ClaudeException.MissingCredentials();
        // 呼び出しごとに作る（キーを長く持たない）。HttpClient は使い回す（Dispose しない）
        return new AnthropicClient
        {
            ApiKey = key,
            BaseUrl = ApiBaseUrl.ToString(),
            HttpClient = http,
            MaxRetries = MaxRetries,
            Timeout = Timeout,
        };
    }

    /// <summary>
    /// 送る内容を組み立てる（テストと CLI の確認で、送らずに中身を見るため internal ではなく public）。
    /// - temperature / top_p / top_k は送らない（API の版 2026-10-21 では 400）
    /// - thinking は送らない（既定の adaptive。考える量は effort で決める）
    /// - assistant の prefill は使わない（400）。出力の形はシステムの指示で決める
    /// - システムの指示は固定なので、プロンプトキャッシュの印を付ける（短くて最小の長さに届かなければ、印があっても効かないだけ）
    /// </summary>
    public static MessageCreateParams BuildParams(TextPurpose purpose, string systemInstruction, string userText, string model)
    {
        var info = ClaudeModels.Find(model);
        var parameters = new MessageCreateParams
        {
            Model = model,
            MaxTokens = ClaudeModels.MaxTokens(purpose),
            System = new List<BetaTextBlockParam>
            {
                new() { Text = systemInstruction, CacheControl = new BetaCacheControlEphemeral() },
            },
            Messages = [new BetaUserMessageParam { Content = userText }],
            OutputConfig = new BetaOutputConfig { Effort = ClaudeModels.Effort(purpose) == "medium" ? Effort.Medium : Effort.Low },
        };
        if (info?.SupportsServerSideFallback == true)
        {
            // 安全の判定で断られたら、サーバー側で Anthropic の勧めるモデルに切り替える（同じ 1 回の呼び出しの中で）
            parameters = parameters with
            {
                Betas = [ServerSideFallbackBeta],
                Fallbacks = new Default(),
            };
        }
        return parameters;
    }

    /// <summary>応答の本文（text のブロック）をつなぐ。stop_reason を先に見る</summary>
    internal static string ReadText(BetaMessage message)
    {
        var stop = message.StopReason?.Raw();
        if (stop == "refusal")
        {
            throw ClaudeException.Refusal(message.StopDetails?.Category?.Raw());
        }
        var text = string.Concat(message.Content.Select(b => b.Value).OfType<BetaTextBlock>().Select(t => t.Text)).Trim();
        if (stop == "max_tokens") throw ClaudeException.MaxTokens();
        if (text.Length == 0) throw ClaudeException.EmptyResponse();
        return text;
    }

    private static ClaudeUsage ReadUsage(BetaMessage message) =>
        new(message.Usage.InputTokens, message.Usage.OutputTokens, message.Usage.CacheCreationInputTokens ?? 0,
            message.Usage.CacheReadInputTokens ?? 0, message.Model.Raw());
}
