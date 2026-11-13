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
/// - 最後の処理から 5 分たつと止める（音声入力の録音中の先読みの保持があれば止めない）。モデルを変えたら起動し直す。Dispose で止める
/// - 音声入力の録音が始まったら、裏で先に起動しておける（Prewarm）
/// - Windows では、起動した直後に ProcessStarted（ジョブオブジェクトへの登録）を呼ぶ。Hanasu が落ちても一緒に終わるように
/// Mac 版の LocalLLMServer.swift と同じ考え（両方を直す）
/// </summary>
// 要件: REQ-COM-030, REQ-COM-033
// 設計判断: DEC-COM-060, DEC-COM-063, DEC-COM-110
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
    // 設計判断: DEC-COM-110
    /// <summary>音声入力の録音中の先読みの保持。1 つでもあれば、5 分たっても止めない</summary>
    private readonly HashSet<Guid> warmHolds = [];
    private int launchCount;

    /// <summary>確かめる用: サーバーを起動した回数</summary>
    public int LaunchCount => Volatile.Read(ref launchCount);

    /// <summary>確かめる用: llama-server を起こさずに、起動したことにする（Mac 版の fakeLaunch と同じ）</summary>
    public Func<LocalLlmModel, CancellationToken, Task<LocalLlmEndpoint>>? LaunchOverride { get; set; }

    /// <summary>使える状態で動いているモデル（起動中は null）</summary>
    public LocalLlmModel? ServingModel
    {
        get { lock (stateLock) return IsServingLocked() ? model : null; }
    }

    private bool IsServingLocked() => endpoint is not null && model is not null && (LaunchOverride is not null || process is { HasExited: false });

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
    /// <summary>
    /// llama-server の場所: 環境変数 HANASU_LLAMA_SERVER → exe の隣の llama/ → 1 つ上の llama/（cli\hanasu.exe から見た ..\llama\。WD4）
    /// </summary>
    public static string? ResolveExecutable()
    {
        var fromEnv = Environment.GetEnvironmentVariable("HANASU_LLAMA_SERVER");
        if (!string.IsNullOrEmpty(fromEnv) && File.Exists(fromEnv)) return fromEnv;
        var name = OperatingSystem.IsWindows() ? "llama-server.exe" : "llama-server";
        var bundled = Path.Combine(AppContext.BaseDirectory, "llama", name);
        if (File.Exists(bundled)) return bundled;
        var parent = Path.GetDirectoryName(Path.TrimEndingDirectorySeparator(AppContext.BaseDirectory));
        var shared = parent is null ? null : Path.Combine(parent, "llama", name);
        return shared is not null && File.Exists(shared) ? shared : null;
    }

    // 要件: REQ-COM-187
    // 設計判断: DEC-COM-184
    /// <summary>起動したサーバーを記録する（ほかのプロセスの hanasu が、二重に読み込まないよう見分けるため）。テストでは切る</summary>
    public bool WriteRecords { get; set; } = true;

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
        lock (stateLock) TouchLocked();
    }

    // 要件: REQ-COM-033
    // 設計判断: DEC-COM-110
    /// <summary>
    /// 音声入力の録音が始まったときに、そのモデルを裏で起動しておく（結果は待たない）。
    /// ほかの処理が違うモデルを使っている（起動中を含む）ときは何もしないで null を返す（その処理を止めない）。
    /// そうでなければ録音中の保持を付けてその ID を返す。録音を止めた・取り消した・失敗したら ReleaseWarmHold で外す
    /// </summary>
    public Guid? Prewarm(LocalLlmModel m)
    {
        bool launch;
        Guid hold;
        lock (stateLock)
        {
            var current = model;
            if (Volatile.Read(ref activeRequests) > 0 && current?.Id != m.Id)
            {
                Log?.Invoke($"local llm prewarm skipped: {m.Id} (other model in use)");
                return null;
            }
            hold = Guid.NewGuid();
            warmHolds.Add(hold);
            lastUsed = DateTime.UtcNow;
            // 同じモデルが使える状態で動いていなければ起動する（落ちていた・起動を取り消されたときも）
            launch = !(current?.Id == m.Id && IsServingLocked());
            // 処理と同じにここで数える（Mac の beginPrewarm と同じ。起動の途中で 5 分の見張りに止められないように）
            if (launch) Interlocked.Increment(ref activeRequests);
        }
        if (launch) _ = Task.Run(() => PrewarmLaunchAsync(m));
        return hold;
    }

    /// <summary>
    /// 先読みの起動。gate を取って起動する（その間に来た整形は gate で待ち、同じサーバーを使う）。
    /// gate を待つ間に、ほかの処理が違うモデルで動き出していたら、その処理を止めないよう起動しない
    /// </summary>
    private async Task PrewarmLaunchAsync(LocalLlmModel m)
    {
        try
        {
            await gate.WaitAsync().ConfigureAwait(false);
            try
            {
                lock (stateLock)
                {
                    if (Volatile.Read(ref activeRequests) > 1 && model is { } other && other.Id != m.Id)
                    {
                        Log?.Invoke($"local llm prewarm skipped: {m.Id} (other model in use)");
                        return;
                    }
                }
                await EnsureRunningAsync(m, CancellationToken.None).ConfigureAwait(false);
            }
            finally
            {
                gate.Release();
            }
        }
        catch (Exception e)
        {
            Log?.Invoke($"local llm prewarm failed: {e.Message}");
        }
        finally
        {
            FinishRequest();
        }
    }

    /// <summary>録音中の保持を外す。そこから 5 分使わなければ止める</summary>
    public void ReleaseWarmHold(Guid hold)
    {
        lock (stateLock)
        {
            if (!warmHolds.Remove(hold)) return;
            TouchLocked();
        }
    }

    /// <summary>最後に使った時刻を新しくし、5 分の見張りを付け直す</summary>
    private void TouchLocked()
    {
        lastUsed = DateTime.UtcNow;
        idleTimer?.Dispose();
        idleTimer = new Timer(_ => StopIfIdle(), null, IdleTimeout, System.Threading.Timeout.InfiniteTimeSpan);
    }

    // 設計判断: DEC-COM-063, DEC-COM-110
    /// <summary>5 分使っていないとして止めてよいか（使っている処理も、録音中の保持もない）。確かめる用に時刻を渡せる</summary>
    public bool ShouldStopForIdle(DateTime nowUtc)
    {
        lock (stateLock)
        {
            return Volatile.Read(ref activeRequests) == 0 && warmHolds.Count == 0 && nowUtc - lastUsed >= IdleTimeout - TimeSpan.FromSeconds(1);
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
            if (process is not null && ShouldStopForIdle(DateTime.UtcNow))
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
        if (process is not null && WriteRecords) LocalLlmServerRecords.Remove();
        process = null;
        model = null;
        endpoint = null;
    }

    private async Task<LocalLlmEndpoint> EnsureRunningAsync(LocalLlmModel m, CancellationToken ct)
    {
        lock (stateLock)
        {
            if (model?.Id == m.Id && IsServingLocked()) return endpoint!;
            StopLocked();
        }
        var startedAt = DateTime.UtcNow;
        if (LaunchOverride is { } fake)
        {
            Interlocked.Increment(ref launchCount);
            lock (stateLock) model = m;
            var fakeEndpoint = await fake(m, ct).ConfigureAwait(false);
            lock (stateLock) endpoint = fakeEndpoint;
            return fakeEndpoint;
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
        // Hanasu を起動したときの環境に LLAMA_ARG_* があっても使わない（決めた引数だけで動かす）。
        // CLI が環境変数で受け取るほかの API キーは、llama-server には要らないので渡さない
        foreach (var key in info.Environment.Keys
                     .Where(k => k.StartsWith("LLAMA_ARG_", StringComparison.OrdinalIgnoreCase) || SecretEnvironmentKeys.Contains(k, StringComparer.OrdinalIgnoreCase))
                     .ToList())
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
        Interlocked.Increment(ref launchCount);
        p.BeginErrorReadLine();
        p.BeginOutputReadLine();
        ProcessStarted?.Invoke(p);
        if (WriteRecords) LocalLlmServerRecords.Write(p.Id, executable);
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
        Log?.Invoke($"local llm server ready: {m.Id} {(DateTime.UtcNow - startedAt).TotalSeconds.ToString("F1", System.Globalization.CultureInfo.InvariantCulture)}s");
        return started;
    }

    /// <summary>子プロセスに渡さない環境変数（Hanasu の CLI が環境変数で受け取る、ほかのサービスの秘密。Mac 版と同じ一覧）</summary>
    public static readonly IReadOnlyList<string> SecretEnvironmentKeys =
    [
        "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "GEMINI_API_KEY", "GOOGLE_API_KEY",
        "GEMINI_SERVICE_ACCOUNT_JSON", "GOOGLE_APPLICATION_CREDENTIALS", "HF_TOKEN",
    ];

    public static IReadOnlyList<string> Arguments(LocalLlmModel m, int port, string modelPath)
    {
        var args = new List<string>
        {
            "--model", modelPath,
            // キーなしで読める /models に、モデルのファイルのパス（ユーザー名を含む）ではなく id を出させる
            "--alias", m.Id,
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
