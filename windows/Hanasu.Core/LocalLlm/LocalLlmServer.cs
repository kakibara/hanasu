using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;

namespace Hanasu.Core.LocalLlm;

/// <summary>llama-server の宛先と、起動のたびに作る API キー</summary>
public sealed record LocalLlmEndpoint(Uri BaseUri, string ApiKey);

/// <summary>
/// 同梱した llama.cpp の llama-server を、ローカルの LLM を使うときだけ子プロセスで動かす（OS に依存しない。Mac でも動く）。
/// - 127.0.0.1 の空いたポートで、起動のたびに作る API キー（環境変数 LLAMA_API_KEY）を付けて起動する
/// - 最後の処理から 5 分たつと止める。モデルを変えたら起動し直す。Dispose で止める
/// - Windows では、起動した直後に ProcessStarted（ジョブオブジェクトへの登録）を呼ぶ。Hanasu が落ちても一緒に終わるように
/// Mac 版の LocalLLMServer.swift と同じ考え（両方を直す）
/// </summary>
// 要件: REQ-COM-030
// 設計判断: DEC-COM-060, DEC-COM-063
public sealed class LocalLlmServer : IDisposable
{
    /// <summary>アプリで 1 つだけ使う。Windows の部品は AppHost で ProcessStarted を設定する</summary>
    public static LocalLlmServer Shared { get; } = new();

    public static readonly TimeSpan IdleTimeout = TimeSpan.FromMinutes(5);
    /// <summary>モデルの読み込みを待つ最大の時間（Gemma 4 E4B は 4.6 GB を読む）</summary>
    public static readonly TimeSpan StartupTimeout = TimeSpan.FromMinutes(3);

    private readonly SemaphoreSlim gate = new(1, 1);
    private readonly object stateLock = new();
    private readonly HttpClient http = LocalLlmClient.CreateHttp();
    private Process? process;
    private LocalLlmModel? model;
    private LocalLlmEndpoint? endpoint;
    private int activeRequests;
    private DateTime lastUsed = DateTime.UtcNow;
    private Timer? idleTimer;
    private readonly Queue<string> stderrTail = new();

    /// <summary>llama-server の場所を明示する（CLI の --server、テスト）。null なら ResolveExecutable で探す</summary>
    public string? ExecutablePath { get; set; }

    /// <summary>起動した直後に呼ぶ（Windows: ジョブオブジェクトに入れる）</summary>
    public Action<Process>? ProcessStarted { get; set; }

    /// <summary>ログに書く（Windows は AppLog。文章の中身は渡さない）</summary>
    public Action<string>? Log { get; set; }

    /// <summary>モデルの置き場所</summary>
    public string ModelsDirectory { get; set; } = DefaultModelsDirectory;

    public static string DefaultModelsDirectory => Path.Combine(Settings.HanasuPaths.ModelsDirectory, "llm");

    public string ModelPath(LocalLlmModel m) => Path.Combine(ModelsDirectory, m.FileName);

    /// <summary>確かめ終えたファイルがあるか（ハッシュは置くときに確かめてあるので、ここでは大きさだけ見る）</summary>
    public bool IsDownloaded(LocalLlmModel m) => File.Exists(ModelPath(m)) && new FileInfo(ModelPath(m)).Length == m.Bytes;

    // 設計判断: DEC-COM-061
    /// <summary>llama-server の場所: 環境変数 HANASU_LLAMA_SERVER → exe の隣の llama/</summary>
    public static string? ResolveExecutable()
    {
        var fromEnv = Environment.GetEnvironmentVariable("HANASU_LLAMA_SERVER");
        if (!string.IsNullOrEmpty(fromEnv) && File.Exists(fromEnv)) return fromEnv;
        var name = OperatingSystem.IsWindows() ? "llama-server.exe" : "llama-server";
        var bundled = Path.Combine(AppContext.BaseDirectory, "llama", name);
        return File.Exists(bundled) ? bundled : null;
    }

    /// <summary>処理を 1 つ始める。そのモデルでサーバーが動いていなければ起動する。終わったら FinishRequest を呼ぶ</summary>
    public async Task<LocalLlmEndpoint> BeginRequestAsync(LocalLlmModel m, CancellationToken ct)
    {
        Interlocked.Increment(ref activeRequests);
        try
        {
            await gate.WaitAsync(ct).ConfigureAwait(false);
            try
            {
                var result = await EnsureRunningAsync(m, ct).ConfigureAwait(false);
                lock (stateLock) lastUsed = DateTime.UtcNow;
                return result;
            }
            finally
            {
                gate.Release();
            }
        }
        catch
        {
            Interlocked.Decrement(ref activeRequests);
            throw;
        }
    }

    public void FinishRequest()
    {
        if (Interlocked.Decrement(ref activeRequests) < 0) Interlocked.Exchange(ref activeRequests, 0);
        lock (stateLock)
        {
            lastUsed = DateTime.UtcNow;
            idleTimer?.Dispose();
            idleTimer = new Timer(_ => StopIfIdle(), null, IdleTimeout, System.Threading.Timeout.InfiniteTimeSpan);
        }
    }

    /// <summary>そのモデルを動かしていれば止める（モデルを消すとき）</summary>
    public void Stop(LocalLlmModel m)
    {
        lock (stateLock)
        {
            if (model?.Id == m.Id) StopLocked();
        }
    }

    public void Stop()
    {
        lock (stateLock) StopLocked();
    }

    public void Dispose() => Stop();

    private void StopIfIdle()
    {
        lock (stateLock)
        {
            if (Volatile.Read(ref activeRequests) == 0 && DateTime.UtcNow - lastUsed >= IdleTimeout - TimeSpan.FromSeconds(1) && process is not null)
            {
                Log?.Invoke("local llm server stopped (idle)");
                StopLocked();
            }
        }
    }

    private void StopLocked()
    {
        idleTimer?.Dispose();
        idleTimer = null;
        if (process is { } p)
        {
            try
            {
                if (!p.HasExited)
                {
                    p.Kill(entireProcessTree: true);
                    p.WaitForExit(3000);
                }
            }
            catch (Exception e) when (e is InvalidOperationException or System.ComponentModel.Win32Exception)
            {
                // すでに終わっている
            }
            p.Dispose();
        }
        process = null;
        model = null;
        endpoint = null;
    }

    private async Task<LocalLlmEndpoint> EnsureRunningAsync(LocalLlmModel m, CancellationToken ct)
    {
        lock (stateLock)
        {
            if (process is { HasExited: false } && model?.Id == m.Id && endpoint is not null) return endpoint;
            StopLocked();
        }
        var executable = ExecutablePath ?? ResolveExecutable() ?? throw LocalLlmException.ServerNotFound();
        if (!IsDownloaded(m)) throw LocalLlmException.ModelNotDownloaded(m);

        var port = FreePort();
        var apiKey = Convert.ToHexString(RandomNumberGenerator.GetBytes(32)).ToLowerInvariant();
        var info = new ProcessStartInfo(executable)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardError = true,
            RedirectStandardOutput = true,
            WorkingDirectory = Path.GetDirectoryName(executable)!,
        };
        foreach (var arg in Arguments(m, port, ModelPath(m))) info.ArgumentList.Add(arg);
        // Hanasu を起動したときの環境に LLAMA_ARG_* があっても使わない（決めた引数だけで動かす）
        foreach (var key in info.Environment.Keys.Where(k => k.StartsWith("LLAMA_ARG_", StringComparison.Ordinal)).ToList())
        {
            info.Environment.Remove(key);
        }
        info.Environment["LLAMA_API_KEY"] = apiKey;

        var p = new Process { StartInfo = info };
        lock (stderrTail) stderrTail.Clear();
        p.ErrorDataReceived += (_, e) =>
        {
            if (e.Data is null) return;
            lock (stderrTail)
            {
                stderrTail.Enqueue(e.Data);
                while (stderrTail.Count > 20) stderrTail.Dequeue();
            }
        };
        p.OutputDataReceived += (_, _) => { };
        p.Start();
        p.BeginErrorReadLine();
        p.BeginOutputReadLine();
        ProcessStarted?.Invoke(p);
        lock (stateLock)
        {
            process = p;
            model = m;
        }
        Log?.Invoke($"local llm server started: {m.Id} port={port}");

        var started = new LocalLlmEndpoint(new Uri($"http://127.0.0.1:{port}/"), apiKey);
        var deadline = DateTime.UtcNow + StartupTimeout;
        while (true)
        {
            ct.ThrowIfCancellationRequested();
            if (p.HasExited)
            {
                var code = p.ExitCode;
                Stop();
                string log;
                lock (stderrTail) log = string.Join("\n", stderrTail.TakeLast(8));
                throw LocalLlmException.Exited(code, log);
            }
            if (await IsHealthyAsync(started, ct).ConfigureAwait(false)) break;
            if (DateTime.UtcNow > deadline)
            {
                Stop();
                throw LocalLlmException.StartupTimedOut(StartupTimeout);
            }
            await Task.Delay(250, ct).ConfigureAwait(false);
        }
        lock (stateLock) endpoint = started;
        return started;
    }

    public static IReadOnlyList<string> Arguments(LocalLlmModel m, int port, string modelPath)
    {
        var args = new List<string>
        {
            "--model", modelPath,
            "--host", "127.0.0.1",
            "--port", port.ToString(System.Globalization.CultureInfo.InvariantCulture),
            "--ctx-size", m.ContextLength.ToString(System.Globalization.CultureInfo.InvariantCulture),
            "--parallel", "1",
            "--jinja",
            "--reasoning", "off",
            "--no-webui",
        };
        // Mac（Metal）は全部の層を GPU に載せる。Windows の配布物は CPU 版なので付けない
        if (OperatingSystem.IsMacOS()) args.AddRange(["--n-gpu-layers", "99"]);
        return args;
    }

    private async Task<bool> IsHealthyAsync(LocalLlmEndpoint e, CancellationToken ct)
    {
        try
        {
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
            timeout.CancelAfter(TimeSpan.FromSeconds(2));
            using var response = await http.GetAsync(new Uri(e.BaseUri, "health"), timeout.Token).ConfigureAwait(false);
            return response.StatusCode == HttpStatusCode.OK;
        }
        catch (Exception ex) when (ex is HttpRequestException or OperationCanceledException && !ct.IsCancellationRequested)
        {
            return false;
        }
    }

    /// <summary>127.0.0.1 で OS に空いたポートを選ばせる</summary>
    public static int FreePort()
    {
        var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        try
        {
            return ((IPEndPoint)listener.LocalEndpoint).Port;
        }
        finally
        {
            listener.Stop();
        }
    }
}
