namespace Hanasu.Core.LocalLlm;

public enum LocalLlmModelStatus
{
    NotDownloaded,
    Downloading,
    Downloaded,
    Failed,
}

public sealed record LocalLlmModelState(LocalLlmModel Model, LocalLlmModelStatus Status, double Progress = 0, string? Error = null);

/// <summary>
/// ローカルの LLM のモデル（GGUF）のダウンロード・削除と、その状態（設定画面に出す）。
/// 取り方は Whisper と同じ ModelDownload（huggingface.co の https から取り、大きさと SHA-256 を確かめてから置く）。
/// 置き場所は LocalLlmServer.ModelsDirectory（%LOCALAPPDATA%\Hanasu\Models\llm）
/// </summary>
// 要件: REQ-COM-030
// 設計判断: DEC-COM-062
public sealed class LocalLlmModelManager(LocalLlmServer server, HttpClient? http = null)
{
    private readonly HttpClient http = http ?? SafeHttp.CreateForDownloads();
    private readonly object gate = new();
    private readonly Dictionary<string, (CancellationTokenSource Cts, double Progress)> downloads = [];
    private readonly Dictionary<string, string> failures = [];

    public event EventHandler<LocalLlmModelState>? StateChanged;

    public string Directory => server.ModelsDirectory;

    public LocalLlmModelState StateOf(LocalLlmModel model)
    {
        lock (gate)
        {
            if (downloads.TryGetValue(model.Id, out var d)) return new(model, LocalLlmModelStatus.Downloading, d.Progress);
            if (server.IsDownloaded(model)) return new(model, LocalLlmModelStatus.Downloaded, 1);
            if (failures.TryGetValue(model.Id, out var error)) return new(model, LocalLlmModelStatus.Failed, 0, error);
            return new(model, LocalLlmModelStatus.NotDownloaded);
        }
    }

    /// <summary>ダウンロードを始める（もうあれば何もしない）。終わるか失敗するまで待つ Task を返す</summary>
    public Task DownloadAsync(LocalLlmModel model, Action<long, long>? progress = null)
    {
        CancellationTokenSource cts;
        lock (gate)
        {
            if (downloads.ContainsKey(model.Id) || server.IsDownloaded(model)) return Task.CompletedTask;
            cts = new CancellationTokenSource();
            downloads[model.Id] = (cts, 0);
            failures.Remove(model.Id);
        }
        Raise(model);
        return Task.Run(() => RunDownloadAsync(model, cts, progress));
    }

    public void CancelDownload(LocalLlmModel model)
    {
        lock (gate)
        {
            if (downloads.TryGetValue(model.Id, out var d)) d.Cts.Cancel();
        }
    }

    /// <summary>ダウンロードしたモデルを消す（動かしていればサーバーを止めてから）</summary>
    public void Delete(LocalLlmModel model)
    {
        CancelDownload(model);
        server.Stop(model);
        var path = server.ModelPath(model);
        if (File.Exists(path)) File.Delete(path);
        lock (gate) failures.Remove(model.Id);
        Raise(model);
    }

    /// <summary>直前の失敗の理由（CLI 用）</summary>
    public string? LastError(LocalLlmModel model)
    {
        lock (gate) return failures.TryGetValue(model.Id, out var error) ? error : null;
    }

    private async Task RunDownloadAsync(LocalLlmModel model, CancellationTokenSource cts, Action<long, long>? progress)
    {
        try
        {
            System.IO.Directory.CreateDirectory(Directory);
            var lastReported = -1.0;
            await ModelDownload.DownloadVerifiedAsync(http, model.DownloadUri, server.ModelPath(model), model.Sha256, model.Bytes, (received, total) =>
            {
                progress?.Invoke(received, total);
                var fraction = total > 0 ? Math.Min(1.0, (double)received / total) : 0;
                if (fraction - lastReported < 0.005) return;
                lastReported = fraction;
                lock (gate) downloads[model.Id] = (cts, fraction);
                Raise(model);
            }, cts.Token).ConfigureAwait(false);
        }
        catch (Exception e)
        {
            if (e is not OperationCanceledException)
            {
                lock (gate) failures[model.Id] = e.Message;
            }
        }
        finally
        {
            lock (gate) downloads.Remove(model.Id);
            cts.Dispose();
            Raise(model);
        }
    }

    private void Raise(LocalLlmModel model) => StateChanged?.Invoke(this, StateOf(model));
}
