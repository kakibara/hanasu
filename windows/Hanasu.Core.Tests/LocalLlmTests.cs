using System.Text.Json.Nodes;
using Hanasu.Core.Ai;
using Hanasu.Core.LocalLlm;
using Hanasu.Core.Meetings;
using Hanasu.Core.Settings;

namespace Hanasu.Core.Tests;

/// <summary>ローカルの LLM（llama-server は動かさない。数え方と要点のまとめは偽物を渡す）</summary>
// 確かめ方: REQ-COM-030
public class LocalLlmTests
{
    /// <summary>2 文字を 1 トークンと数える偽の数え方</summary>
    private static Task<int> Count(string text, CancellationToken _) => Task.FromResult((text.Length + 1) / 2);

    private static LongInputFitter Fitter(int context, int output, List<string>? parts = null) =>
        new(context, output, Count, (part, index, total, _) =>
        {
            parts?.Add(part);
            // 部分の 1 行目だけを要点として返す
            var first = part.Split('\n')[0];
            return Task.FromResult($"- 部分 {index}/{total}: {first[..Math.Min(40, first.Length)]}");
        });

    [Fact]
    public async Task ShortInputIsKeptAsIs()
    {
        const string text = "<transcript>\n[00:01] 自分: こんにちは\n</transcript>";
        Assert.Equal(text, await Fitter(4096, 1024).FitAsync("指示", text));
    }

    [Fact]
    public async Task LongMinutesInputIsSummarizedInParts()
    {
        var lines = Enumerable.Range(0, 600).Select(i => $"[{i / 60:00}:{i % 60:00}] 話者{i % 3 + 1}: " + string.Concat(Enumerable.Repeat("議題について話しました。", 4)));
        const string header = "会議: 定例\n日時: 2026/11/04\n\n<user_notes>\nメモ\n</user_notes>\n\n";
        var input = header + "<transcript>\n" + string.Join("\n", lines) + "\n</transcript>";
        var parts = new List<string>();
        var fitted = await Fitter(8192, 3072, parts).FitAsync("議事録の指示", input);

        var tokens = await Count("議事録の指示", default) + await Count(fitted, default);
        Assert.True(tokens <= 8192 - 3072 - LongInputFitter.Margin, $"{tokens}");
        Assert.True(parts.Count >= 2);
        Assert.Contains(LongInputFitter.SummarizedNote, fitted);
        Assert.StartsWith(header + "<transcript>\n", fitted);
        Assert.EndsWith("\n</transcript>", fitted);
        Assert.True(fitted.IndexOf("部分 1/", StringComparison.Ordinal) < fitted.IndexOf("部分 2/", StringComparison.Ordinal));
        // 部分をつなぐと元の文字起こしになる（落とした行がない）
        Assert.Equal(string.Join("\n", lines), string.Join("\n", parts));
    }

    [Fact]
    public async Task OtherLongInputIsTruncatedFromTheEnd()
    {
        var input = "質問: 先週の定例で何が決まった？\n" + string.Concat(Enumerable.Repeat("<meeting>記録</meeting>\n", 2000));
        var fitted = await Fitter(4096, 1024).FitAsync("質問の指示", input);
        Assert.StartsWith("質問: 先週", fitted);
        Assert.EndsWith(LongInputFitter.OmittedNote, fitted);
        Assert.True(await Count("質問の指示", default) + await Count(fitted, default) <= 4096 - 1024 - LongInputFitter.Margin);
    }

    [Fact]
    public void TwoTranscriptsAreNotSplit()
    {
        Assert.Null(LongInputFitter.SplitTranscript("<transcript>\nあ\n</transcript>\n<transcript>\nい\n</transcript>"));
        Assert.NotNull(LongInputFitter.SplitTranscript("x\n<transcript>\nあ\n</transcript>"));
    }

    [Fact]
    public async Task VeryLongLineIsSplitToFit()
    {
        var oneLine = string.Concat(Enumerable.Repeat("長い発言", 5000));
        var chunks = await Fitter(2048, 512).SplitAsync(oneLine, 500);
        Assert.True(chunks.Count >= 2);
        Assert.All(chunks, c => Assert.True((c.Length + 1) / 2 <= 500));
        Assert.Equal(oneLine, string.Concat(chunks));
    }

    [Fact]
    public void CatalogMatchesTheMacVersion()
    {
        Assert.Equal(["gemma-4-e4b", "lfm2.5-1.2b-jp", "sarashina2.2-3b"], LocalLlmModel.All.Select(m => m.Id));
        foreach (var m in LocalLlmModel.All)
        {
            Assert.Matches("^[0-9a-f]{64}$", m.Sha256);
            Assert.Matches("^[0-9a-f]{40}$", m.Revision);
            Assert.Equal("huggingface.co", m.DownloadUri.Host);
            Assert.Contains($"/resolve/{m.Revision}/{m.FileName}", m.DownloadUri.AbsolutePath);
            Assert.True(m.MaxOutputTokens(longOutput: true) <= m.ContextLength / 2);
        }
        Assert.Equal(8192, LocalLlmModel.Sarashina22.ContextLength);
        Assert.Contains("1,000 万ドル", LocalLlmModel.Lfm25JP.LicenseNote);
        Assert.Equal(LocalLlmModel.Lfm25JP, LocalLlmModel.DefaultDictation);
        Assert.Equal(LocalLlmModel.Gemma4E4B, LocalLlmModel.DefaultMeeting);
    }

    [Fact]
    public void ServerArgumentsListenOnLoopbackWithoutTheKey()
    {
        var args = LocalLlmServer.Arguments(LocalLlmModel.Sarashina22, 51234, "/models/x.gguf");
        Assert.Equal("127.0.0.1", args[args.ToList().IndexOf("--host") + 1]);
        Assert.Equal("8192", args[args.ToList().IndexOf("--ctx-size") + 1]);
        Assert.Contains("--jinja", args);
        Assert.Contains("--no-webui", args);
        Assert.DoesNotContain(args, a => a.Contains("api-key", StringComparison.OrdinalIgnoreCase));
        Assert.InRange(LocalLlmServer.FreePort(), 1, 65535);
    }

    [Fact]
    public void RequestUsesTheModelSampling()
    {
        var body = JsonNode.Parse(LocalLlmClient.RequestBody("指示", "本文", LocalLlmModel.Lfm25JP, 2048))!;
        Assert.Equal("system", (string?)body["messages"]![0]!["role"]);
        Assert.Equal("本文", (string?)body["messages"]![1]!["content"]);
        Assert.Equal(0.1, (double)body["temperature"]!);
        Assert.Equal(50, (int)body["top_k"]!);
        Assert.Null(body["top_p"]);
        Assert.Equal("</s>", (string?)body["stop"]![0]);
        Assert.False((bool)body["stream"]!);
    }

    [Fact]
    public void ResponseIsParsed()
    {
        static string Reply(string content, string finish = "stop") =>
            new JsonObject { ["choices"] = new JsonArray(new JsonObject { ["finish_reason"] = finish, ["message"] = new JsonObject { ["content"] = content } }) }.ToJsonString();
        Assert.Equal("整えた文章です。", LocalLlmClient.ParseChat(Reply("整えた文章です。</s>")));
        Assert.Throws<LocalLlmException>(() => LocalLlmClient.ParseChat(Reply("途中", "length")));
        Assert.Throws<LocalLlmException>(() => LocalLlmClient.ParseChat(Reply("  ")));
        Assert.Throws<LocalLlmException>(() => LocalLlmClient.ParseChat("not json"));
    }

    [Fact]
    public void RewriteIsCleanedUp()
    {
        Assert.Equal("明日の会議です。", LocalLlmClient.CleanUpRewrite("「明日の会議です。」", "明日の会議です"));
        // 入力が「で始まるなら外さない
        Assert.Equal("「はい」と言った。", LocalLlmClient.CleanUpRewrite("「はい」と言った。", "「はい」と言った"));
        Assert.Equal("「A」と「B」", LocalLlmClient.CleanUpRewrite("「A」と「B」", "A と B"));
        Assert.Equal("一行目\n二行目", LocalLlmClient.CleanUpRewrite("一行目  \n二行目", "x"));
    }

    [Fact]
    public void FactoryNeedsTheModelFile()
    {
        var dir = TestKeys.TempDirectory();
        var server = new LocalLlmServer { ModelsDirectory = dir };
        var settings = new AppSettings { DictationAi = TextAiProvider.Local, LocalDictationModel = LocalLlmModel.Sarashina22.Id };
        Assert.Null(TextAiFactory.CreateLocal(settings, TextAiUse.Dictation, TimeSpan.FromSeconds(15), server));
        Assert.Equal("sarashina2.2-3b", settings.DictationModel);
        Assert.Equal("ローカル", TextAiFactory.NameOf(TextAiProvider.Local));
        Assert.Contains("ダウンロード", TextAiFactory.NotReadyBecause(TextAiProvider.Local));
        Assert.Equal("Gemini の認証情報が未設定のため", TextAiFactory.NotReadyBecause(TextAiProvider.Gemini));

        // 大きさが合うファイルがあれば作る（中身は見ない。ハッシュは置くときに確かめる）
        using (var f = File.Create(Path.Combine(dir, LocalLlmModel.Sarashina22.FileName))) f.SetLength(LocalLlmModel.Sarashina22.Bytes);
        var client = TextAiFactory.CreateLocal(settings, TextAiUse.Dictation, TimeSpan.FromSeconds(15), server);
        Assert.NotNull(client);
        Assert.Equal(LocalLlmClient.MinimumTimeout(TextAiUse.Dictation), client!.Timeout);
        Assert.Equal(LocalLlmModel.Sarashina22, client.Model);
    }

    [Fact]
    public void UnknownLocalModelFallsBackToTheDefault()
    {
        var dir = TestKeys.TempDirectory();
        var store = new SettingsStore(Path.Combine(dir, "settings.json"));
        File.WriteAllText(Path.Combine(dir, "settings.json"), """{"meetingAi":"local","localMeetingModel":"no-such-model"}""");
        var loaded = store.Load();
        Assert.Equal(TextAiProvider.Local, loaded.MeetingAi);
        Assert.Equal(LocalLlmModel.DefaultMeeting.Id, loaded.LocalMeetingModel);
    }

    [Fact]
    public void ActionItemsWrittenInsideTheBodyAreRead()
    {
        // Gemma 4 E4B が返した形: <action_items> を使わず、見出しの下に JSON をそのまま書く
        const string response = """
            ## 決定事項
            - ローンチは 12 月 10 日

            ## アクションアイテム
            [{"owner": "田中", "task": "案をまとめる", "due": "2026-11-11", "due_note": "来週の金曜"}]

            ## 話者についてのメモ
            なし
            """;
        var result = MinutesPrompt.Parse(response, "定例");
        Assert.Single(result.ActionItems);
        Assert.Equal("田中", result.ActionItems[0].Owner);
        Assert.DoesNotContain("[{", result.Markdown);
        Assert.Contains("案をまとめる", result.Markdown);
    }
}
