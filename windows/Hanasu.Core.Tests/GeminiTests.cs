using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Hanasu.Core.Gemini;
using Hanasu.Core.Settings;
using Hanasu.Core.Text;

namespace Hanasu.Core.Tests;

public class GeminiPromptTests
{
    [Fact]
    public void UserPromptMatchesMacLayout()
    {
        var dictionary = new UserDictionary("Hanasu\nVertex AI\nGemini\nジェミニ => Gemini");
        var request = new RefineRequest
        {
            Transcript = "えーと明日の会議なんですけど あの 資料はGeminiで作ったやつを使います",
            Model = "gemini-3.5-flash-lite",
            AppName = "Slack",
            Dictionary = dictionary.Spellings,
            DictionaryRules = dictionary.Rules,
            ExtraInstructions = "です・ます調に統一\n",
        };
        Assert.Equal("""
            入力先アプリ: Slack（体裁の参考。言葉は変えない）
            ユーザー辞書: Hanasu, Vertex AI, Gemini
            置き換えルール（左の読み・誤認識や、それに近い音の語が出てきたら右の表記にする）:
            - ジェミニ → Gemini
            追加ルール:
            です・ます調に統一
            <transcript>
            えーと明日の会議なんですけど あの 資料はGeminiで作ったやつを使います
            </transcript>
            """.ReplaceLineEndings("\n"), GeminiPrompts.UserPrompt(request));
    }

    [Fact]
    public void TranslationDropsExtraRulesAndOmitsEmptySections()
    {
        var request = new RefineRequest { Transcript = "テスト", Model = "m", ExtraInstructions = "です・ます調に統一" };
        Assert.Equal("<transcript>\nテスト\n</transcript>", GeminiPrompts.UserPrompt(request, Dictation.TranslationLanguage.English));
        Assert.Contains("追加ルール", GeminiPrompts.UserPrompt(request));
    }

    // 確かめ方: REQ-DIC-013
    [Fact]
    public void JapaneseTranslationKeepsExtraRulesAndUsesItsOwnInstruction()
    {
        // 和訳は出力が日本語なので、追加の整形ルールを使う（DEC-DIC-028）
        var request = new RefineRequest { Transcript = "test", Model = "m", ExtraInstructions = "です・ます調に統一" };
        Assert.Contains("追加ルール:\nです・ます調に統一", GeminiPrompts.UserPrompt(request, Dictation.TranslationLanguage.Japanese));
        Assert.Equal(GeminiPrompts.JapaneseTranslationInstruction, GeminiPrompts.TranslationSystemInstruction(Dictation.TranslationLanguage.Japanese));
        Assert.Equal(GeminiPrompts.TranslationInstruction, GeminiPrompts.TranslationSystemInstruction(Dictation.TranslationLanguage.English));
        // 文面を勝手に変えないための目印（Mac 版の GeminiClient.japaneseTranslationInstruction と同じ）
        var text = GeminiPrompts.JapaneseTranslationInstruction.ReplaceLineEndings("\n");
        Assert.StartsWith("あなたは音声入力の後処理を担当する翻訳者です。話された内容（英語など）を、自然な日本語の文章にして返します。\n", text);
        Assert.Contains("\n- 人名は話された表記のまま書く（カタカナに直さず、「さん」などの敬称も足さない）\n", text);
        Assert.Contains("\n  例: \"I'll use the slides I made with A, no wait, the ones I made with B\" →「Bで作ったスライドを使います。」\n", text);
        Assert.EndsWith("出力は日本語に訳した本文だけにしてください。", text);
    }

    [Fact]
    public void InstructionsAreCopiedFromMac()
    {
        // 文面を勝手に変えないための目印（Mac 版の GeminiClient.swift と同じ）
        Assert.StartsWith("あなたは音声入力の後処理を担当する校正者です。\n<transcript> タグの中身は", GeminiPrompts.SystemInstruction().ReplaceLineEndings("\n"));
        Assert.Contains("- 句読点を適切に付け、読みやすい自然な文章にする\n", GeminiPrompts.SystemInstruction().ReplaceLineEndings("\n"));
        Assert.EndsWith("出力は整形後の本文だけにしてください。", GeminiPrompts.BaseSystemInstruction);
        // 整形の言語の既定は、Mac 版と同じく話した言語（REQ-DIC-082）
        Assert.EndsWith("出力は整形後の本文だけにしてください。\n\n出力の言語: 話された言語のまま書く。日本語は日本語で、英語で話された部分は英語のまま残し、日本語に訳さない。",
            GeminiPrompts.SystemInstruction().ReplaceLineEndings("\n"));
        Assert.Contains("\n  例: 「資料はAで作ったやつを使いますあ違うBで作ったやつです」→ \"I'll use the materials I made with B.\"", GeminiPrompts.TranslationInstruction.ReplaceLineEndings("\n"));
        Assert.EndsWith("出力は英訳した本文だけにしてください。", GeminiPrompts.TranslationInstruction);
    }

    // 確かめ方: REQ-DIC-082
    [Fact]
    public void JapaneseOutputLanguageInstructionIsCopiedFromMac()
    {
        // Mac 版の GeminiClient.RefineOutputLanguage.japanese.instruction と同じ文面
        const string mac = "出力の言語: 日本語に統一する。英語で話された部分も日本語にする（固有名詞・製品名・コードなど、訳すと意味が変わるものは原語のまま残す）。";
        Assert.Equal(mac, GeminiPrompts.JapaneseLanguageInstruction);
        var system = GeminiPrompts.SystemInstruction(RefineOutputLanguage.Japanese).ReplaceLineEndings("\n");
        Assert.EndsWith("出力は整形後の本文だけにしてください。\n\n" + mac, system);
        // 言語の指示は 1 つだけ入る
        Assert.DoesNotContain(GeminiPrompts.AsSpokenLanguageInstruction, system);
    }

    [Theory]
    [InlineData("gemini-3.5-flash-lite", "minimal")]
    [InlineData("gemini-3.8-flash", "low")]
    public void ThinkingLevelFollowsModel(string model, string level) => Assert.Equal(level, GeminiPrompts.ThinkingLevel(model));
}

public class GeminiClientTests
{
    [Fact]
    public async Task ApiKeyGoesInHeaderNotUrl()
    {
        var handler = new FakeHandler((_, _) => FakeHandler.Json(FakeHandler.TextResponse(" 整えた文 ")));
        var client = new GeminiClient(new GeminiAuth.ApiKey("test-key-123"), new HttpClient(handler));
        var result = await client.RefineAsync(new RefineRequest { Transcript = "えー整える文", Model = "gemini-3.5-flash-lite" });

        Assert.Equal("整えた文", result);
        var (request, body) = Assert.Single(handler.Requests);
        Assert.Equal("https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent", request.RequestUri!.ToString());
        Assert.DoesNotContain("test-key", request.RequestUri.ToString());
        Assert.Equal("test-key-123", request.Headers.GetValues("x-goog-api-key").Single());

        var json = JsonNode.Parse(body!)!;
        Assert.Equal(GeminiPrompts.SystemInstruction(), json["systemInstruction"]!["parts"]![0]!["text"]!.GetValue<string>());
        Assert.Equal("user", json["contents"]![0]!["role"]!.GetValue<string>());
        Assert.Contains("<transcript>\nえー整える文\n</transcript>", json["contents"]![0]!["parts"]![0]!["text"]!.GetValue<string>());
        Assert.Equal("minimal", json["generationConfig"]!["thinkingConfig"]!["thinkingLevel"]!.GetValue<string>());
        Assert.Null(json["generationConfig"]!["temperature"]);
    }

    [Fact]
    public async Task ServiceAccountUsesVertexWithBearerToken()
    {
        var (credentials, rsa) = TestKeys.MakeServiceAccount();
        using var _ = rsa;
        var handler = new FakeHandler((request, _) => request.RequestUri!.Host == "oauth2.example.test"
            ? FakeHandler.Json("""{"access_token":"ya29.fake","expires_in":3600,"token_type":"Bearer"}""")
            : FakeHandler.Json(FakeHandler.TextResponse("ok")));
        var http = new HttpClient(handler);
        var tokens = new ServiceAccountTokenProvider(http);
        var client = new GeminiClient(new GeminiAuth.ServiceAccount(credentials, "us-central1"), http, tokens);

        await client.TranslateAsync(new RefineRequest { Transcript = "こんにちは", Model = "gemini-3.8-flash" }, Dictation.TranslationLanguage.English);
        await client.RefineAsync(new RefineRequest { Transcript = "こんにちは", Model = "gemini-3.8-flash" });

        // トークンは 1 回だけ取り、2 回目は使い回す
        Assert.Equal(3, handler.Requests.Count);
        Assert.Equal("https://us-central1-aiplatform.googleapis.com/v1/projects/example-project/locations/us-central1/publishers/google/models/gemini-3.8-flash:generateContent",
            handler.Requests[1].Request.RequestUri!.ToString());
        Assert.Equal("Bearer ya29.fake", handler.Requests[1].Request.Headers.Authorization!.ToString());
        Assert.Equal(GeminiPrompts.TranslationInstruction,
            JsonNode.Parse(handler.Requests[1].Body!)!["systemInstruction"]!["parts"]![0]!["text"]!.GetValue<string>());
    }

    [Fact]
    public async Task GlobalLocationHasNoRegionPrefix()
    {
        var (credentials, rsa) = TestKeys.MakeServiceAccount();
        using var _ = rsa;
        var handler = new FakeHandler((request, _) => request.RequestUri!.Host == "oauth2.example.test"
            ? FakeHandler.Json("""{"access_token":"t","expires_in":3600}""")
            : FakeHandler.Json(FakeHandler.TextResponse("ok")));
        var http = new HttpClient(handler);
        var client = new GeminiClient(new GeminiAuth.ServiceAccount(credentials), http, new ServiceAccountTokenProvider(http));
        await client.RefineAsync(new RefineRequest { Transcript = "a", Model = "m" });
        Assert.StartsWith("https://aiplatform.googleapis.com/v1/projects/example-project/locations/global/", handler.Requests[1].Request.RequestUri!.ToString());
    }

    // 確かめ方: REQ-COM-022
    [Fact]
    public async Task VertexLocationMustBeAHostNameLabel()
    {
        var (credentials, rsa) = TestKeys.MakeServiceAccount();
        using var _ = rsa;
        var handler = new FakeHandler((_, _) => FakeHandler.Json(FakeHandler.TextResponse("ok")));
        var http = new HttpClient(handler);
        // リージョンはホスト名に入るので、別のホストに向けられる形は送る前に断る（トークンも取らない）
        var client = new GeminiClient(new GeminiAuth.ServiceAccount(credentials, "evil.example.test/#"), http, new ServiceAccountTokenProvider(http));
        var e = await Assert.ThrowsAsync<GeminiException>(() => client.RefineAsync(new RefineRequest { Transcript = "a", Model = "m" }));
        Assert.Equal(GeminiErrorKind.InvalidLocation, e.Kind);
        Assert.True(e.IsCredentialProblem);
        Assert.Empty(handler.Requests);

        Assert.True(GeminiClient.IsValidLocation("global"));
        Assert.True(GeminiClient.IsValidLocation("asia-northeast1"));
        Assert.False(GeminiClient.IsValidLocation(""));
        Assert.False(GeminiClient.IsValidLocation("US-CENTRAL1"));
        Assert.False(GeminiClient.IsValidLocation("us-central1.example.test"));
    }

    [Fact]
    public async Task AudioIsSentAsInlineData()
    {
        var handler = new FakeHandler((_, _) => FakeHandler.Json(FakeHandler.TextResponse("文字起こし")));
        var client = new GeminiClient(new GeminiAuth.ApiKey("k"), new HttpClient(handler));
        var audio = new byte[] { 1, 2, 3, 4 };
        var text = await client.TranscribeAudioAsync(audio, "audio/wav", "gemini-3.5-flash-lite", ["Hanasu"]);

        Assert.Equal("文字起こし", text);
        var json = JsonNode.Parse(handler.Requests[0].Body!)!;
        var parts = json["contents"]![0]!["parts"]!.AsArray();
        Assert.Contains("ユーザー辞書: Hanasu", parts[0]!["text"]!.GetValue<string>());
        Assert.Equal("audio/wav", parts[1]!["inlineData"]!["mimeType"]!.GetValue<string>());
        Assert.Equal(Convert.ToBase64String(audio), parts[1]!["inlineData"]!["data"]!.GetValue<string>());
        Assert.Equal(GeminiPrompts.TranscriptionInstruction, json["systemInstruction"]!["parts"]![0]!["text"]!.GetValue<string>());
    }

    [Fact]
    public async Task EmptyTranscriptionMeansNoSpeech()
    {
        var handler = new FakeHandler((_, _) => FakeHandler.Json("""{"candidates":[{"content":{"parts":[]},"finishReason":"STOP"}]}"""));
        var client = new GeminiClient(new GeminiAuth.ApiKey("k"), new HttpClient(handler));
        Assert.Equal("", await client.TranscribeAudioAsync([0], "audio/wav", "m", []));
    }

    [Fact]
    public void ParsesTextSkippingThoughts()
    {
        var text = GeminiClient.ParseResponseText("""
            {"candidates":[{"content":{"parts":[{"text":"考え中","thought":true},{"text":"本文"},{"text":"の続き"}]}}]}
            """);
        Assert.Equal("本文の続き", text);
    }

    [Fact]
    public void ReportsBlockAndFinishReasons()
    {
        var blocked = Assert.Throws<GeminiException>(() => GeminiClient.ParseResponseText("""{"promptFeedback":{"blockReason":"SAFETY"}}"""));
        Assert.Equal(GeminiErrorKind.EmptyResponse, blocked.Kind);
        Assert.Contains("SAFETY", blocked.Message);
        var empty = Assert.Throws<GeminiException>(() => GeminiClient.ParseResponseText("""{"candidates":[{"finishReason":"MAX_TOKENS"}]}"""));
        Assert.Equal("MAX_TOKENS", empty.Reason);
        Assert.Throws<GeminiException>(() => GeminiClient.ParseResponseText("not json"));
    }

    [Fact]
    public async Task HttpErrorsCarryTheApiMessage()
    {
        var handler = new FakeHandler((_, _) => FakeHandler.Json("""{"error":{"code":403,"message":"Permission denied"}}""", HttpStatusCode.Forbidden));
        var client = new GeminiClient(new GeminiAuth.ApiKey("k"), new HttpClient(handler));
        var e = await Assert.ThrowsAsync<GeminiException>(() => client.RefineAsync(new RefineRequest { Transcript = "a", Model = "m" }));
        Assert.Equal(403, e.StatusCode);
        Assert.Equal("Gemini API エラー（403）: Permission denied", e.Message);
    }

    [Fact]
    public async Task TimesOut()
    {
        var handler = new SlowHandler();
        var client = new GeminiClient(new GeminiAuth.ApiKey("k"), new HttpClient(handler)) { Timeout = TimeSpan.FromMilliseconds(100) };
        var e = await Assert.ThrowsAsync<GeminiException>(() => client.RefineAsync(new RefineRequest { Transcript = "a", Model = "m" }));
        Assert.Equal(GeminiErrorKind.Timeout, e.Kind);
    }

    private static GeminiClient RetryClient(FakeHandler handler, TimeSpan? timeout = null, TimeSpan? baseDelay = null) =>
        new(new GeminiAuth.ApiKey("k"), new HttpClient(handler))
        {
            Timeout = timeout ?? TimeSpan.FromSeconds(15),
            RetryBaseDelay = baseDelay ?? TimeSpan.FromMilliseconds(1),
        };

    // 設計判断: DEC-COM-055
    [Fact]
    public async Task RetriesOn503ThenSucceeds()
    {
        var calls = 0;
        var handler = new FakeHandler((_, _) => ++calls < 3
            ? FakeHandler.Json("""{"error":{"message":"busy"}}""", HttpStatusCode.ServiceUnavailable)
            : FakeHandler.Json(FakeHandler.TextResponse("整形後")));
        var result = await RetryClient(handler).RefineAsync(new RefineRequest { Transcript = "a", Model = "m" });
        Assert.Equal("整形後", result);
        Assert.Equal(3, handler.Requests.Count);
    }

    [Fact]
    public async Task GivesUpAfterTwoRetriesOn429()
    {
        var handler = new FakeHandler((_, _) => FakeHandler.Json("""{"error":{"message":"slow down"}}""", HttpStatusCode.TooManyRequests));
        var e = await Assert.ThrowsAsync<GeminiException>(() => RetryClient(handler).RefineAsync(new RefineRequest { Transcript = "a", Model = "m" }));
        Assert.Equal(429, e.StatusCode);
        Assert.Equal(3, handler.Requests.Count);
    }

    [Fact]
    public async Task DoesNotRetryOtherErrorsOrWhenOverBudget()
    {
        var forbidden = new FakeHandler((_, _) => FakeHandler.Json("""{"error":{"message":"no"}}""", HttpStatusCode.Forbidden));
        await Assert.ThrowsAsync<GeminiException>(() => RetryClient(forbidden).RefineAsync(new RefineRequest { Transcript = "a", Model = "m" }));
        Assert.Single(forbidden.Requests);

        // 待ちが Timeout の半分を超えるなら、やり直さない
        var busy = new FakeHandler((_, _) => FakeHandler.Json("{}", HttpStatusCode.ServiceUnavailable));
        var client = RetryClient(busy, timeout: TimeSpan.FromSeconds(2), baseDelay: TimeSpan.FromSeconds(5));
        await Assert.ThrowsAsync<GeminiException>(() => client.RefineAsync(new RefineRequest { Transcript = "a", Model = "m" }));
        Assert.Single(busy.Requests);
    }

    [Fact]
    public async Task RetriesTransientNetworkErrors()
    {
        var calls = 0;
        var handler = new FakeHandler((_, _) => ++calls < 2
            ? throw new HttpRequestException("connection reset")
            : FakeHandler.Json(FakeHandler.TextResponse("ok")));
        Assert.Equal("ok", await RetryClient(handler).RefineAsync(new RefineRequest { Transcript = "a", Model = "m" }));
        Assert.Equal(2, handler.Requests.Count);
    }

    [Fact]
    public async Task MissingApiKeyIsReported()
    {
        var client = new GeminiClient(new GeminiAuth.ApiKey(" "), new HttpClient(new FakeHandler((_, _) => throw new InvalidOperationException())));
        var e = await Assert.ThrowsAsync<GeminiException>(() => client.RefineAsync(new RefineRequest { Transcript = "a", Model = "m" }));
        Assert.Equal(GeminiErrorKind.MissingCredentials, e.Kind);
    }

    private sealed class SlowHandler : HttpMessageHandler
    {
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            await Task.Delay(TimeSpan.FromSeconds(30), cancellationToken);
            return new HttpResponseMessage(HttpStatusCode.OK);
        }
    }
}

public class ServiceAccountTests
{
    [Fact]
    public void JwtIsSignedWithRs256()
    {
        var (credentials, rsa) = TestKeys.MakeServiceAccount();
        using var _ = rsa;
        var issuedAt = DateTimeOffset.FromUnixTimeSeconds(1_800_000_000);
        var jwt = ServiceAccountTokenProvider.MakeJwt(credentials, issuedAt);
        var parts = jwt.Split('.');
        Assert.Equal(3, parts.Length);

        var header = JsonNode.Parse(FromBase64Url(parts[0]))!;
        Assert.Equal("RS256", header["alg"]!.GetValue<string>());
        var claims = JsonNode.Parse(FromBase64Url(parts[1]))!;
        Assert.Equal(credentials.ClientEmail, claims["iss"]!.GetValue<string>());
        Assert.Equal("https://www.googleapis.com/auth/cloud-platform", claims["scope"]!.GetValue<string>());
        Assert.Equal(credentials.TokenUri, claims["aud"]!.GetValue<string>());
        Assert.Equal(1_800_000_000, claims["iat"]!.GetValue<long>());
        Assert.Equal(1_800_003_600, claims["exp"]!.GetValue<long>());

        var verified = rsa.VerifyData(Encoding.ASCII.GetBytes(parts[0] + "." + parts[1]), FromBase64UrlBytes(parts[2]),
            HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        Assert.True(verified);
        Assert.DoesNotContain('=', jwt);
        Assert.DoesNotContain('+', jwt);
    }

    [Fact]
    public async Task TokenIsCachedUntilAMinuteBeforeExpiry()
    {
        var (credentials, rsa) = TestKeys.MakeServiceAccount();
        using var _ = rsa;
        var count = 0;
        var handler = new FakeHandler((_, body) =>
        {
            count++;
            Assert.Contains("grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer", body);
            Assert.Contains("assertion=", body);
            return FakeHandler.Json($$"""{"access_token":"token-{{count}}","expires_in":120}""");
        });
        var now = DateTimeOffset.FromUnixTimeSeconds(1_800_000_000);
        var provider = new ServiceAccountTokenProvider(new HttpClient(handler), () => now);

        Assert.Equal("token-1", await provider.GetAccessTokenAsync(credentials));
        now = now.AddSeconds(50);
        Assert.Equal("token-1", await provider.GetAccessTokenAsync(credentials));
        now = now.AddSeconds(20);  // 期限まで 50 秒 → 取り直す
        Assert.Equal("token-2", await provider.GetAccessTokenAsync(credentials));
    }

    [Fact]
    public async Task TokenErrorsAreReadable()
    {
        var (credentials, rsa) = TestKeys.MakeServiceAccount();
        using var _ = rsa;
        var provider = new ServiceAccountTokenProvider(new HttpClient(new FakeHandler((_, _) =>
            FakeHandler.Json("""{"error":"invalid_grant"}""", HttpStatusCode.BadRequest))));
        var e = await Assert.ThrowsAsync<ServiceAccountException>(() => provider.GetAccessTokenAsync(credentials));
        Assert.Contains("400", e.Message);
    }

    [Fact]
    public void ParsesKeyFilesAndRejectsBrokenOnes()
    {
        var dir = TestKeys.TempDirectory();
        var path = Path.Combine(dir, "key.json");
        File.WriteAllText(path, """{"project_id":"p","client_email":"e@example.test","private_key":"x"}""");
        var credentials = ServiceAccountCredentials.Load(path);
        Assert.Equal("https://oauth2.googleapis.com/token", credentials.TokenUri);
        Assert.DoesNotContain("private", credentials.ToString(), StringComparison.OrdinalIgnoreCase);

        Assert.Throws<ServiceAccountException>(() => ServiceAccountCredentials.Load(Path.Combine(dir, "missing.json")));
        Assert.Throws<ServiceAccountException>(() => ServiceAccountCredentials.Parse("{"));
        Assert.Throws<ServiceAccountException>(() => ServiceAccountCredentials.Parse("""{"project_id":"p"}"""));

        // token_uri は Google のトークンの窓口に限る（DEC-COM-053）
        string KeyWith(string tokenUri) =>
            $$"""{"project_id":"p","client_email":"e@example.test","private_key":"x","token_uri":"{{tokenUri}}"}""";
        Assert.Equal("https://accounts.google.com/o/oauth2/token",
            ServiceAccountCredentials.Parse(KeyWith("https://accounts.google.com/o/oauth2/token")).TokenUri);
        foreach (var untrusted in new[]
        {
            "https://evil.example.test/token", "http://oauth2.googleapis.com/token", "https://oauth2.googleapis.com.evil.example.test/token",
            "https://oauth2.googleapis.com:8443/token", "https://user@oauth2.googleapis.com/token",
        })
        {
            var rejected = Assert.Throws<ServiceAccountException>(() => ServiceAccountCredentials.Parse(KeyWith(untrusted)));
            Assert.Contains("token_uri", rejected.Message);
        }
        var bad = credentials with { PrivateKey = "-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----" };
        Assert.Throws<ServiceAccountException>(() => ServiceAccountTokenProvider.MakeJwt(bad, DateTimeOffset.UtcNow));
    }

    private static string FromBase64Url(string s) => Encoding.UTF8.GetString(FromBase64UrlBytes(s));

    private static byte[] FromBase64UrlBytes(string s)
    {
        s = s.Replace('-', '+').Replace('_', '/');
        return Convert.FromBase64String(s.PadRight(s.Length + (4 - s.Length % 4) % 4, '='));
    }
}
