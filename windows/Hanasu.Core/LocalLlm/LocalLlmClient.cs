using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Hanasu.Core.Ai;
using Hanasu.Core.Gemini;

namespace Hanasu.Core.LocalLlm;

/// <summary>ローカルの LLM の失敗。Message はそのまま HUD・会議ノートに出せる文（表示の言語。REQ-COM-060）にする（文章の中身は入れない）</summary>
public sealed class LocalLlmException : TextAiException
{
    private LocalLlmException(string message, bool credentialProblem = false, Exception? inner = null) : base(message, inner)
    {
        IsCredentialProblem = credentialProblem;
    }

    /// <summary>モデルがない・サーバーがない（設定を直さない限り、やり直しても通らない）</summary>
    public override bool IsCredentialProblem { get; }

    public static LocalLlmException ServerNotFound() =>
        new(Strings.LocalLlm_ServerNotFound, true);

    public static LocalLlmException ModelNotDownloaded(LocalLlmModel? model) =>
        new(model is null ? Strings.LocalLlm_ModelNotDownloaded : string.Format(Strings.LocalLlm_NamedModelNotDownloaded, model.Name), true);

    public static LocalLlmException Exited(int code, string log) =>
        new(string.Format(Strings.LocalLlm_Exited, code) + (log.Length == 0 ? "" : "\n" + log));

    public static LocalLlmException StartupTimedOut(TimeSpan timeout) =>
        new(string.Format(Strings.LocalLlm_StartupTimedOut, timeout.TotalSeconds.ToString("0")));

    public static LocalLlmException Http(int status, string message) =>
        new(string.Format(Strings.LocalLlm_Http, status) + (message.Length == 0 ? "" : $": {message}"));

    public static LocalLlmException Truncated() => new(Strings.LocalLlm_Truncated);

    public static LocalLlmException Empty() => new(Strings.LocalLlm_Empty);

    public static LocalLlmException Invalid() => new(Strings.LocalLlm_Invalid);

    public static LocalLlmException Timeout(TimeSpan timeout) => new(string.Format(Strings.LocalLlm_Timeout, timeout.TotalSeconds.ToString("0")));
}

/// <summary>
/// ローカルの LLM（llama-server の OpenAI 互換 API）に文章を送る。プロンプトは Gemini・Claude と同じもの（GeminiPrompts）を使う。
/// 文脈に入らない入力は LongInputFitter で縮めてから送る。Mac 版の LocalLLMClient.swift と同じ考え（両方を直す）
/// </summary>
// 要件: REQ-COM-030
// 設計判断: DEC-COM-060, DEC-COM-064, DEC-COM-065
public sealed class LocalLlmClient(LocalLlmModel model, LocalLlmServer server, HttpClient? http = null) : ITextAiClient
{
    private static readonly HttpClient SharedHttp = CreateHttp();
    private readonly HttpClient http = http ?? SharedHttp;

    /// <summary>127.0.0.1 の llama-server だけに使う。リダイレクトに従わず、プロキシを通さない</summary>
    public static HttpClient CreateHttp() =>
        new(new SocketsHttpHandler { AllowAutoRedirect = false, UseProxy = false, UseCookies = false })
        {
            Timeout = System.Threading.Timeout.InfiniteTimeSpan,
        };

    /// <summary>用途ごとの最短の待ち時間（モデルの読み込みを含む。DEC-COM-064）</summary>
    public static TimeSpan MinimumTimeout(TextAiUse use) => use == TextAiUse.Dictation ? TimeSpan.FromSeconds(120) : TimeSpan.FromMinutes(30);

    public LocalLlmModel Model => model;

    /// <summary>1 回の呼び出しの待ち時間の上限（サーバーの起動を含む）</summary>
    public TimeSpan Timeout { get; init; } = TimeSpan.FromSeconds(120);

    public string ProviderName => Strings.Ai_Local;

    public async Task<string> RefineAsync(RefineRequest request, CancellationToken cancellationToken = default) =>
        CleanUpRewrite(await GenerateTextAsync(TextPurpose.Refine, GeminiPrompts.SystemInstruction(request.OutputLanguage), GeminiPrompts.UserPrompt(request),
            request.Model, cancellationToken).ConfigureAwait(false), request.Transcript);

    public async Task<string> TranslateAsync(RefineRequest request, Dictation.TranslationLanguage language, CancellationToken cancellationToken = default) =>
        CleanUpRewrite(await GenerateTextAsync(TextPurpose.Translate, GeminiPrompts.TranslationSystemInstruction(language),
            GeminiPrompts.UserPrompt(request, language), request.Model, cancellationToken).ConfigureAwait(false), request.Transcript);

    /// <summary>
    /// 整形・英訳の結果の後始末。小さいモデルは、結果の全体を「」で囲んだり（Sarashina2.2）、行末に Markdown の改行の空白を付けたり（LFM2.5）するので、
    /// 入力が「で始まっていないのに全体が「」で囲まれていれば外し、行末の空白を除く（Mac 版の cleanUpRewrite と同じ）
    /// </summary>
    public static string CleanUpRewrite(string output, string input)
    {
        var text = string.Join("\n", output.Split('\n').Select(line => line.TrimEnd(' ', '\t', '\r')));
        if (text.Length >= 2 && text[0] == '「' && text[^1] == '」' && !input.TrimStart().StartsWith('「')
            && text[1..^1].IndexOfAny(['「', '」']) < 0)
        {
            text = text[1..^1];
        }
        return text;
    }

    /// <summary>model は使わない（このクライアントのモデルで動かす）</summary>
    public async Task<string> GenerateTextAsync(TextPurpose purpose, string systemInstruction, string userText, string model,
        CancellationToken cancellationToken = default)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(Timeout);
        try
        {
            var endpoint = await server.BeginRequestAsync(Model, timeout.Token).ConfigureAwait(false);
            try
            {
                var maxOutput = Model.MaxOutputTokens(purpose.IsLong());
                var fitter = new LongInputFitter(Model.ContextLength, maxOutput,
                    (text, ct) => CountTokensAsync(endpoint, text, ct),
                    (part, index, total, ct) => ChatAsync(endpoint, LongInputFitter.PartInstruction(index, total), LongInputFitter.PartUserText(part),
                        LongInputFitter.PartOutputTokens(Model.ContextLength), ct));
                var fitted = await fitter.FitAsync(systemInstruction, userText, timeout.Token).ConfigureAwait(false);
                return await ChatAsync(endpoint, systemInstruction, fitted, maxOutput, timeout.Token).ConfigureAwait(false);
            }
            finally
            {
                server.FinishRequest();
            }
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw LocalLlmException.Timeout(Timeout);
        }
        catch (HttpRequestException e)
        {
            throw LocalLlmException.Http(0, e.Message);
        }
    }

    private async Task<string> ChatAsync(LocalLlmEndpoint endpoint, string system, string userText, int maxTokens, CancellationToken ct)
    {
        using var response = await PostAsync(endpoint, "v1/chat/completions", RequestBody(system, userText, Model, maxTokens), ct).ConfigureAwait(false);
        return ParseChat(await response.Content.ReadAsStringAsync(ct).ConfigureAwait(false));
    }

    private async Task<int> CountTokensAsync(LocalLlmEndpoint endpoint, string text, CancellationToken ct)
    {
        var body = new JsonObject { ["content"] = text, ["add_special"] = false }.ToJsonString();
        using var response = await PostAsync(endpoint, "tokenize", body, ct).ConfigureAwait(false);
        var json = JsonNode.Parse(await response.Content.ReadAsStringAsync(ct).ConfigureAwait(false));
        return json?["tokens"] is JsonArray tokens ? tokens.Count : throw LocalLlmException.Invalid();
    }

    private async Task<HttpResponseMessage> PostAsync(LocalLlmEndpoint endpoint, string path, string body, CancellationToken ct)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(endpoint.BaseUri, path))
        {
            Content = new StringContent(body, Encoding.UTF8, "application/json"),
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", endpoint.ApiKey);
        var response = await http.SendAsync(request, ct).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            var status = (int)response.StatusCode;
            var message = ErrorMessage(await response.Content.ReadAsStringAsync(ct).ConfigureAwait(false));
            response.Dispose();
            throw LocalLlmException.Http(status, message);
        }
        return response;
    }

    // 設計判断: DEC-COM-064
    public static string RequestBody(string system, string userText, LocalLlmModel model, int maxTokens)
    {
        var body = new JsonObject
        {
            ["messages"] = new JsonArray
            {
                new JsonObject { ["role"] = "system", ["content"] = system },
                new JsonObject { ["role"] = "user", ["content"] = userText },
            },
            ["max_tokens"] = maxTokens,
            ["stream"] = false,
            // Sarashina2.2 は終わりの印を文字として出すことがあるので、そこで止める
            ["stop"] = new JsonArray(EndMarker),
            ["temperature"] = model.Sampling.Temperature,
        };
        if (model.Sampling.TopP is { } topP) body["top_p"] = topP;
        if (model.Sampling.TopK is { } topK) body["top_k"] = topK;
        if (model.Sampling.RepeatPenalty is { } penalty) body["repeat_penalty"] = penalty;
        return body.ToJsonString();
    }

    public const string EndMarker = "</s>";

    /// <summary>応答の本文を取り出す。終わりの印（&lt;/s&gt;）が文字で残っていれば除く</summary>
    public static string ParseChat(string json)
    {
        JsonNode? root;
        try
        {
            root = JsonNode.Parse(json);
        }
        catch (JsonException)
        {
            throw LocalLlmException.Invalid();
        }
        var choice = root?["choices"]?[0] ?? throw LocalLlmException.Invalid();
        if ((string?)choice["finish_reason"] == "length") throw LocalLlmException.Truncated();
        var text = ((string?)choice["message"]?["content"] ?? "").Trim();
        while (text.EndsWith(EndMarker, StringComparison.Ordinal)) text = text[..^EndMarker.Length].Trim();
        return text.Length == 0 ? throw LocalLlmException.Empty() : text;
    }

    private static string ErrorMessage(string json)
    {
        try
        {
            var message = (string?)JsonNode.Parse(json)?["error"]?["message"] ?? "";
            return message.Length > 300 ? message[..300] : message;
        }
        catch (JsonException)
        {
            return "";
        }
    }
}
