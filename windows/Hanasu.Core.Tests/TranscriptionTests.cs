using System.Net;
using Hanasu.Core.Audio;
using Hanasu.Core.Gemini;
using Hanasu.Core.Transcription;
using Hanasu.Whisper;

namespace Hanasu.Core.Tests;

internal sealed class FakeRecorder(float[] samples) : IAudioRecorder
{
    public bool Started, Stopped, Disposed;
    public string? DeviceId;
    public event EventHandler<float[]>? SamplesAvailable { add { } remove { } }
    public event EventHandler<Exception>? Faulted { add { } remove { } }
    public Task StartAsync(string deviceId, CancellationToken cancellationToken = default)
    {
        Started = true;
        DeviceId = deviceId;
        return Task.CompletedTask;
    }
    public Task<float[]> StopAsync()
    {
        Stopped = true;
        return Task.FromResult(samples);
    }
    public ValueTask DisposeAsync()
    {
        Disposed = true;
        return ValueTask.CompletedTask;
    }
}

internal sealed class FakeBatch(string result) : IBatchTranscriber
{
    public Exception? PrepareError { get; set; }
    public int Calls;
    public string DisplayName => "Fake";
    public Task PrepareAsync(TranscriptionContext context, CancellationToken cancellationToken = default) =>
        PrepareError is null ? Task.CompletedTask : Task.FromException(PrepareError);
    public Task<string> TranscribeAsync(float[] samples, TranscriptionContext context, CancellationToken cancellationToken = default)
    {
        Calls++;
        return Task.FromResult(result);
    }
}

public class TranscriptionTests
{
    private static readonly TranscriptionContext Context = new("ja-JP", ["Hanasu"], "mic-1");

    private static float[] Voice(double seconds = 1) =>
        Enumerable.Range(0, (int)(16000 * seconds)).Select(i => (float)(0.2 * Math.Sin(i * 0.1))).ToArray();

    [Fact]
    public async Task RecordsThenTranscribes()
    {
        var recorder = new FakeRecorder(Voice());
        var batch = new FakeBatch(" 文字起こし ");
        await using var t = new RecordThenTranscribe(recorder, batch);
        await t.StartAsync(Context);
        Assert.Equal("mic-1", recorder.DeviceId);
        Assert.Equal("Fake で文字起こししています…", t.FinishingMessage);
        Assert.Equal("文字起こし", await t.StopAsync());
        Assert.True(recorder.Stopped);
    }

    [Fact]
    public async Task SilenceIsNotSent()
    {
        var batch = new FakeBatch("ご視聴ありがとうございました");
        var t = new RecordThenTranscribe(new FakeRecorder(new float[16000]), batch);
        await t.StartAsync(Context);
        Assert.Equal("", await t.StopAsync());
        Assert.Equal(0, batch.Calls);
    }

    [Fact]
    public async Task PrepareErrorsStopBeforeRecording()
    {
        var recorder = new FakeRecorder(Voice());
        var t = new RecordThenTranscribe(recorder, new FakeBatch("") { PrepareError = new TranscriptionException("モデルがありません") });
        await Assert.ThrowsAsync<TranscriptionException>(() => t.StartAsync(Context));
        Assert.False(recorder.Started);
    }

    [Fact]
    public async Task GeminiTranscriberNeedsCredentialsAndSendsWav()
    {
        var missing = new GeminiBatchTranscriber(() => null, () => "m", () => []);
        await Assert.ThrowsAsync<TranscriptionException>(() => missing.PrepareAsync(Context));

        var handler = new FakeHandler((_, _) => FakeHandler.Json(FakeHandler.TextResponse("明日の会議です")));
        var gemini = new GeminiBatchTranscriber(() => new GeminiClient(new GeminiAuth.ApiKey("k"), new HttpClient(handler)), () => "gemini-3.5-flash-lite", () => ["Hanasu"]);
        await gemini.PrepareAsync(Context);
        Assert.Equal("明日の会議です", await gemini.TranscribeAsync(Voice(0.5), Context));
        Assert.Contains("\"mimeType\":\"audio/wav\"", handler.Requests[0].Body);

        var tooLong = new float[(int)(GeminiBatchTranscriber.MaxDuration.TotalSeconds * 16000) + 1];
        await Assert.ThrowsAsync<TranscriptionException>(() => gemini.TranscribeAsync(tooLong, Context));
    }

    [Fact]
    public async Task WhisperNeedsADownloadedModel()
    {
        var whisper = new WhisperBatchTranscriber(() => Path.Combine(TestKeys.TempDirectory(), "ggml-small.bin"), () => "small");
        var e = await Assert.ThrowsAsync<TranscriptionException>(() => whisper.PrepareAsync(Context));
        Assert.Contains("small", e.Message);
    }

    [Theory]
    [InlineData("ご視聴ありがとうございました", true)]
    [InlineData(" ご視聴ありがとうございました。 ", true)]
    [InlineData("[BLANK_AUDIO]", true)]
    [InlineData("明日の会議です", false)]
    public void FiltersWhisperHallucinations(string segment, bool expected) =>
        Assert.Equal(expected, WhisperText.IsHallucination(segment));

    [Fact]
    public void WhisperPromptStaysShort()
    {
        var words = Enumerable.Range(0, 100).Select(i => $"用語{i:000}").ToArray();
        Assert.True(WhisperBatchTranscriber.WhisperPrompt(words).Length <= 130);
        Assert.Equal("Hanasu、Gemini", WhisperBatchTranscriber.WhisperPrompt(["Hanasu", "Gemini"]));
    }
}

public class WhisperModelManagerTests
{
    [Fact]
    public void CatalogPointsAtHuggingFace()
    {
        var small = WhisperModelCatalog.Find("SMALL")!;
        Assert.Equal("https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin", small.DownloadUri.ToString());
        Assert.Null(WhisperModelCatalog.Find("nope"));
        Assert.All(WhisperModelCatalog.Models, m => Assert.EndsWith(".bin", m.FileName));
    }

    [Fact]
    public async Task DownloadsWithProgressThenDeletes()
    {
        var data = Enumerable.Range(0, 300_000).Select(i => (byte)i).ToArray();
        var handler = new FakeHandler((request, _) =>
        {
            Assert.EndsWith("ggml-test.bin", request.RequestUri!.ToString());
            return new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(data) };
        });
        var dir = TestKeys.TempDirectory();
        var manager = new WhisperModelManager(Path.Combine(dir, "Models"), new HttpClient(handler));
        // 本物の大きさとハッシュの代わりに、このデータのものを持つモデル
        var tiny = new WhisperModelInfo("test", "ggml-test.bin", data.Length,
            Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(data)), "テスト");
        var states = new List<WhisperModelState>();
        manager.StateChanged += (_, s) => { lock (states) states.Add(s); };

        Assert.Equal(WhisperModelStatus.NotDownloaded, manager.StateOf(tiny).Status);
        await manager.DownloadAsync(tiny);
        Assert.Equal(WhisperModelStatus.Downloaded, manager.StateOf(tiny).Status);
        Assert.Equal(data, File.ReadAllBytes(manager.PathFor(tiny)));
        Assert.False(File.Exists(manager.PathFor(tiny) + ".download"));
        lock (states)
        {
            Assert.Contains(states, s => s.Status == WhisperModelStatus.Downloading && s.Progress > 0 && s.Progress < 1);
            Assert.Equal(WhisperModelStatus.Downloaded, states[^1].Status);
        }

        manager.Delete(tiny);
        Assert.Equal(WhisperModelStatus.NotDownloaded, manager.StateOf(tiny).Status);
    }

    // 確かめ方: REQ-COM-022
    [Fact]
    public async Task DownloadWithWrongHashIsRejected()
    {
        var data = Enumerable.Range(0, 1000).Select(i => (byte)i).ToArray();
        var handler = new FakeHandler((_, _) => new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(data) });
        var manager = new WhisperModelManager(TestKeys.TempDirectory(), new HttpClient(handler));
        var model = new WhisperModelInfo("test", "ggml-test.bin", data.Length, new string('0', 64), "テスト");
        await manager.DownloadAsync(model);
        var state = manager.StateOf(model);
        Assert.Equal(WhisperModelStatus.Failed, state.Status);
        Assert.Contains("SHA-256", state.Error);
        Assert.Empty(Directory.GetFiles(manager.Directory));
    }

    [Fact]
    public void CatalogHasHashesAndSizes()
    {
        Assert.All(WhisperModelCatalog.Models, m =>
        {
            Assert.Matches("^[0-9a-f]{64}$", m.Sha256);
            Assert.True(m.Bytes > 10_000_000);
            Assert.Equal("huggingface.co", m.DownloadUri.Host);
        });
        Assert.All(Hanasu.Diarization.DiarizationModels.All, m =>
        {
            Assert.Matches("^[0-9a-f]{64}$", m.Sha256);
            Assert.Equal("huggingface.co", m.DownloadUri.Host);
        });
    }

    [Fact]
    public async Task DownloadsOnlyFromAllowedHosts()
    {
        var handler = new FakeHandler((_, _) => throw new InvalidOperationException("送ってはいけない"));
        var path = Path.Combine(TestKeys.TempDirectory(), "x.bin");
        await Assert.ThrowsAsync<ModelVerificationException>(() => ModelDownload.DownloadVerifiedAsync(new HttpClient(handler),
            new Uri("https://example.com/x.bin"), path, new string('0', 64), 10, null, default));
        await Assert.ThrowsAsync<ModelVerificationException>(() => ModelDownload.DownloadVerifiedAsync(new HttpClient(handler),
            new Uri("http://huggingface.co/x.bin"), path, new string('0', 64), 10, null, default));
        Assert.Empty(handler.Requests);
    }

    [Fact]
    public async Task CancelLeavesNoPartialFile()
    {
        var handler = new FakeHandler((_, _) => new HttpResponseMessage(HttpStatusCode.OK) { Content = new StreamContent(new EndlessStream()) });
        var manager = new WhisperModelManager(TestKeys.TempDirectory(), new HttpClient(handler));
        var tiny = WhisperModelCatalog.Find("tiny")!;
        var task = manager.DownloadAsync(tiny);
        for (var i = 0; i < 1000 && manager.StateOf(tiny).Progress == 0; i++) await Task.Delay(10);
        Assert.Equal(WhisperModelStatus.Downloading, manager.StateOf(tiny).Status);
        manager.CancelDownload(tiny);
        await task;
        Assert.Equal(WhisperModelStatus.NotDownloaded, manager.StateOf(tiny).Status);
        Assert.Empty(Directory.GetFiles(manager.Directory));
    }

    [Fact]
    public async Task HttpFailureIsReported()
    {
        var handler = new FakeHandler((_, _) => new HttpResponseMessage(HttpStatusCode.NotFound));
        var manager = new WhisperModelManager(TestKeys.TempDirectory(), new HttpClient(handler));
        var tiny = WhisperModelCatalog.Find("tiny")!;
        await manager.DownloadAsync(tiny);
        var state = manager.StateOf(tiny);
        Assert.Equal(WhisperModelStatus.Failed, state.Status);
        Assert.Contains("404", state.Error);
    }

    /// <summary>いつまでも終わらないダウンロード</summary>
    private sealed class EndlessStream : Stream
    {
        public override bool CanRead => true;
        public override bool CanSeek => false;
        public override bool CanWrite => false;
        public override long Length => throw new NotSupportedException();
        public override long Position { get => 0; set { } }
        public override void Flush() { }
        public override int Read(byte[] buffer, int offset, int count)
        {
            Thread.Sleep(1);
            return Math.Min(count, 4096);
        }
        public override async ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default)
        {
            await Task.Delay(1, cancellationToken);
            return buffer.Length;
        }
        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
        public override void SetLength(long value) => throw new NotSupportedException();
        public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();
    }
}
