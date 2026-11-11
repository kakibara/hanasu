using System.Diagnostics;
using System.IO;
using System.Windows;
using Hanasu.Core.Dictation;
using Hanasu.Core.Meetings;
using Hanasu.Core.Settings;
using Hanasu.Core.Update;
using Hanasu.Windows.Views;

namespace Hanasu.Windows.Services;

/// <summary>
/// アップデート。GitHub の最新のリリースを確かめ（起動時と、メニュー・設定からの手動）、新しい版があればユーザーに確認して、
/// 同意があればダウンロード → 検証 → 展開 → PowerShell のスクリプトで入れ替えて起動し直す。
/// 通信・検証・展開の部分は Hanasu.Core.Update にある（テストはそちら）。ここは画面と入れ替えの段取り。
/// </summary>
internal sealed class UpdateService
{
    /// <summary>起動してから最初の確認までの待ち（起動直後の処理と重ならないように）</summary>
    private static readonly TimeSpan LaunchDelay = TimeSpan.FromSeconds(5);

    private readonly AppHost host;
    private bool busy;

    public UpdateService(AppHost host) => this.host = host;

    /// <summary>今の版。リリースのビルドは -p:Version=&lt;版&gt; で作る。取れなければ 0.0.0</summary>
    public AppVersion CurrentVersion { get; } =
        typeof(AppHost).Assembly.GetName().Version is { } v ? AppVersion.FromVersion(v) : AppVersion.Parse("0.0.0")!;

    /// <summary>手元のビルド（Directory.Build.props の既定の 0.1.0 など、主版が 0）。起動時の確認はしない</summary>
    public bool IsDevBuild => CurrentVersion.Major == 0;

    // 要件: REQ-REL-010
    // 設計判断: DEC-REL-024
    /// <summary>起動時の確認。設定がオフ・手元のビルドなら何もしない。失敗は黙ってログだけに書く（ユーザーには何も出さない）</summary>
    public async Task CheckOnLaunchAsync()
    {
        try
        {
            if (!host.Settings.Current.CheckForUpdatesOnLaunch || IsDevBuild) return;
            await Task.Delay(LaunchDelay);
            // 待っている間に設定が変わったかもしれない
            if (!host.Settings.Current.CheckForUpdatesOnLaunch) return;
            if (busy) return;
            busy = true;
            try
            {
                var result = await CheckAsync();
                if (UpdateChecker.ShouldPrompt(result, host.Settings.Current.SkippedUpdateVersion, manual: false))
                {
                    await PromptAndInstallAsync(result);
                }
            }
            finally
            {
                busy = false;
            }
        }
        catch (Exception e)
        {
            AppLog.Write($"update: launch check failed: {e.Message}");
        }
    }

    // 要件: REQ-REL-011
    // 設計判断: DEC-REL-022
    /// <summary>手動の確認（メニューの「アップデートを確認…」・設定の「今すぐ確認」）。スキップした版も知らせ、最新なら「最新です」と出す。失敗は理由を出す</summary>
    public async Task CheckManuallyAsync()
    {
        if (busy)
        {
            MessageBox.Show(Strings.Update_Checking, "Hanasu", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        busy = true;
        try
        {
            var result = await CheckAsync();
            if (UpdateChecker.ShouldPrompt(result, host.Settings.Current.SkippedUpdateVersion, manual: true))
            {
                await PromptAndInstallAsync(result);
            }
            else
            {
                MessageBox.Show(string.Format(Strings.Update_UpToDate, CurrentVersion), "Hanasu", MessageBoxButton.OK, MessageBoxImage.Information);
            }
        }
        catch (UpdateException e)
        {
            AppLog.Write($"update: manual check failed: {e.Message}");
            MessageBox.Show(string.Format(Strings.Update_CheckFailed, e.Message), "Hanasu", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
        catch (Exception e)
        {
            AppLog.Write($"update: manual check failed: {e}");
            MessageBox.Show(string.Format(Strings.Update_CheckFailed, e.Message), "Hanasu", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
        finally
        {
            busy = false;
        }
    }

    // 設計判断: DEC-REL-020
    private async Task<UpdateCheckResult> CheckAsync()
    {
        using var http = UpdateChecker.CreateApiClient(CurrentVersion.ToString());
        return await UpdateChecker.CheckAsync(http, CurrentVersion, CancellationToken.None);
    }

    // 設計判断: DEC-REL-022
    private async Task PromptAndInstallAsync(UpdateCheckResult result)
    {
        var release = result.Release!;
        // 手元のビルドは、フォルダを入れ替えない（リリースのページを案内するだけ）
        var canInstall = result.Kind == UpdateCheckKind.Available && !IsDevBuild;
        var window = new UpdatePromptWindow(CurrentVersion, release, canInstall);
        window.ShowDialog();
        switch (window.Choice)
        {
            case UpdateChoice.Skip:
                var error = host.Settings.Update(s => s.SkippedUpdateVersion = release.Version.ToString());
                if (error is not null) AppLog.Write($"update: skip not saved: {error.Message}");
                break;
            case UpdateChoice.Update when canInstall:
                await InstallAsync(release);
                break;
            case UpdateChoice.Update:
                Shell.Open(release.ReleaseUrl.AbsoluteUri);
                break;
        }
    }

    // 設計判断: DEC-REL-023
    /// <summary>録音中・会議の記録中・処理中のほか、議事録の作り直しとモデルのダウンロードも「忙しい」に含める（途中で終わると失われるため）</summary>
    private bool IsRecordingOrProcessing() =>
        host.Dictation.State != DictationState.Idle || host.Meetings.State != MeetingState.Idle
        || host.Meetings.IsRegenerating || host.WhisperModels.IsAnyDownloading || host.LocalLlmModels.IsAnyDownloading;

    /// <summary>ダウンロード全体の上限（これを過ぎたらやめる）</summary>
    private static readonly TimeSpan DownloadTimeout = TimeSpan.FromMinutes(10);

    /// <summary>入れ替えを始める前に書く印（中身は入れ替えたい版）。入れ替えが失敗すると、次の起動まで残る</summary>
    private static string PendingFile => Path.Combine(HanasuPaths.LocalDataDirectory, "update-pending.txt");

    // 設計判断: DEC-REL-030
    /// <summary>
    /// 起動のたびに呼ぶ。前回、入れ替えを始めたのに版が上がっていなければ（スクリプトが入れ替えられなかった）、理由の手がかりと
    /// リリースのページを案内する。印のファイルは読んだら消す
    /// </summary>
    public void ReportPreviousAttempt()
    {
        try
        {
            if (!File.Exists(PendingFile)) return;
            var lines = File.ReadAllText(PendingFile).Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            try { File.Delete(PendingFile); }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { AppLog.Write($"update: pending marker not deleted: {e.Message}"); }
            var expected = lines.Length > 0 ? AppVersion.Parse(lines[0]) : null;
            if (expected is null || CurrentVersion >= expected) return;
            AppLog.Write($"update: previous attempt to {expected} did not complete (running {CurrentVersion})");
            var logPath = Path.Combine(HanasuPaths.LocalDataDirectory, "Logs", "update.log");
            var answer = MessageBox.Show(
                string.Format(Strings.Update_PreviousAttemptFailed, expected, CurrentVersion, logPath),
                "Hanasu", MessageBoxButton.YesNo, MessageBoxImage.Warning);
            if (answer == MessageBoxResult.Yes)
            {
                // 印に書いたリリースのページ（GitHub のものだけ）。なければ最新のリリース
                var page = lines.Length > 1 && Uri.TryCreate(lines[1], UriKind.Absolute, out var uri) && UpdateHosts.IsAllowed(uri)
                    ? uri.AbsoluteUri : $"https://github.com/{UpdateHosts.Repository}/releases/latest";
                Shell.Open(page);
            }
        }
        catch (Exception e)
        {
            AppLog.Write($"update: report previous attempt failed: {e.Message}");
        }
    }

    private static void ShowBusyMessage() =>
        MessageBox.Show(Strings.Update_Busy,
            "Hanasu", MessageBoxButton.OK, MessageBoxImage.Information);

    // 要件: REQ-REL-012
    // 設計判断: DEC-REL-021, DEC-REL-028, DEC-REL-030
    private async Task InstallAsync(ReleaseInfo release)
    {
        if (IsRecordingOrProcessing())
        {
            ShowBusyMessage();
            return;
        }
        var asset = release.Asset!;
        // 入れ替えは、いま動いているフォルダ（Hanasu.exe のあるところ）を、隣の作業用フォルダで作った新しいものと取り替える
        var installDir = Path.TrimEndingDirectorySeparator(AppContext.BaseDirectory);
        var parent = Path.GetDirectoryName(installDir);
        // ドライブの直下（C:\ など）に置いてあるときは、フォルダごとの入れ替えができない
        if (parent is null || string.Equals(Path.GetPathRoot(installDir), installDir + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
        {
            OfferReleasePage(release, Strings.Update_DriveRoot);
            return;
        }
        var staging = Path.Combine(parent, "Hanasu.update");
        // 案内やエラーは、進み具合の窓を閉じてから出す（窓はどの終わり方でも finally で閉じる）
        Action? afterClose = null;
        var progressWindow = new UpdateProgressWindow(release.Version, asset.Size);
        using var userCancel = new CancellationTokenSource();
        progressWindow.CancelRequested += (_, _) => userCancel.Cancel();
        progressWindow.Show();
        try
        {
            PrepareStagingDirectory(staging);
            var zipPath = Path.Combine(staging, asset.Name);
            // 設計判断: DEC-REL-030（通信が止まったまま待ち続けないよう、全体で 10 分に区切る）
            using (var http = UpdateChecker.CreateDownloadClient(CurrentVersion.ToString()))
            using (var timeout = new CancellationTokenSource(DownloadTimeout))
            using (var linked = CancellationTokenSource.CreateLinkedTokenSource(timeout.Token, userCancel.Token))
            {
                // 進み具合はスレッドプールから来るので、0.1 秒ごとに間引いてから UI のスレッドへ送る
                var gate = new object();
                DateTime? lastPublishedAt = null;
                long lastReceived = 0;
                void Report(long received, long total)
                {
                    lock (gate)
                    {
                        var now = DateTime.UtcNow;
                        if (!UpdateDownloadProgress.ShouldPublish(lastPublishedAt, lastReceived, now, received, asset.Size)) return;
                        lastPublishedAt = now;
                        lastReceived = received;
                    }
                    progressWindow.Dispatcher.BeginInvoke(() => progressWindow.SetProgress(received, asset.Size));
                }
                try
                {
                    await UpdateChecker.DownloadAsync(http, asset, zipPath, Report, linked.Token);
                }
                catch (OperationCanceledException) when (userCancel.IsCancellationRequested)
                {
                    // 「中止」: 何も出さずにやめる（メニューの「アップデートを確認…」から選び直せる）
                    AppLog.Write($"update: download of {release.Tag} canceled by the user");
                    TryDeleteDirectory(staging);
                    return;
                }
                catch (OperationCanceledException) when (timeout.IsCancellationRequested)
                {
                    throw new UpdateException(Strings.Update_DownloadTimeout);
                }
            }
            progressWindow.SetProgress(asset.Size, asset.Size);
            progressWindow.SetPreparing();
            var staged = await Task.Run(() => UpdatePackage.Extract(zipPath, Path.Combine(staging, "pkg")));

            // 設計判断: DEC-REL-030（入れ替えは今のフォルダごと消すので、Hanasu 専用のフォルダでなければ進まない）
            var foreign = UpdatePackage.FindForeignEntries(installDir, staged);
            if (foreign.Count > 0)
            {
                AppLog.Write($"update: install folder has foreign entries: {string.Join(", ", foreign)}");
                TryDeleteDirectory(staging);
                var shown = string.Join("\n", foreign.Take(5).Select(n => string.Format(Strings.Update_ForeignItem, n)));
                var more = foreign.Count > 5 ? string.Format(Strings.Update_ForeignMore, foreign.Count - 5) : "";
                afterClose = () => OfferReleasePage(release,
                    string.Format(Strings.Update_ForeignEntries, installDir, shown, more));
                return;
            }
            var scriptPath = Path.Combine(staging, "apply-update.ps1");
            await File.WriteAllTextAsync(scriptPath, SwapScript, new System.Text.UTF8Encoding(encoderShouldEmitUTF8Identifier: true));

            // ダウンロードの間に録音が始まったかもしれない
            if (IsRecordingOrProcessing())
            {
                TryDeleteDirectory(staging);
                afterClose = ShowBusyMessage;
                return;
            }
            // 入れ替えが失敗したら、次の起動で知らせるための印
            Directory.CreateDirectory(HanasuPaths.LocalDataDirectory);
            await File.WriteAllTextAsync(PendingFile, $"{release.Version}\n{release.ReleaseUrl.AbsoluteUri}\n");
            progressWindow.CloseForGood();
            StartSwapScript(scriptPath, installDir, staged, parent);
        }
        catch (Exception e) when (e is UpdateException or global::Hanasu.Core.ModelVerificationException or IOException or UnauthorizedAccessException
                                      or global::System.Net.Http.HttpRequestException or TaskCanceledException or System.ComponentModel.Win32Exception
                                      or InvalidOperationException)
        {
            AppLog.Write($"update: install failed: {e}");
            TryDeleteDirectory(staging);
            TryDeletePendingFile();
            var reason = e is UnauthorizedAccessException ? Strings.Update_FolderNotWritable : e.Message;
            afterClose = () => OfferReleasePage(release, string.Format(Strings.Update_Failed, reason));
        }
        catch (Exception e)
        {
            // 想定していない失敗でも、「アップデート」を押した人に何も出さないことがないように
            AppLog.Write($"update: install failed (unexpected): {e}");
            TryDeleteDirectory(staging);
            TryDeletePendingFile();
            afterClose = () => OfferReleasePage(release, string.Format(Strings.Update_Failed, e.Message));
        }
        finally
        {
            // return で抜けたときも、窓を閉じてから案内を出す
            progressWindow.CloseForGood();
            afterClose?.Invoke();
        }
    }

    /// <summary>スクリプトを始める前の失敗はその場で知らせるので、次の起動ではもう知らせない</summary>
    private static void TryDeletePendingFile()
    {
        try { if (File.Exists(PendingFile)) File.Delete(PendingFile); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { AppLog.Write($"update: pending marker not deleted: {e.Message}"); }
    }

    /// <summary>作業用フォルダを空の状態で作る（前の失敗の残りは消す）。書き込めなければ UnauthorizedAccessException</summary>
    private static void PrepareStagingDirectory(string staging)
    {
        TryDeleteDirectory(staging);
        Directory.CreateDirectory(staging);
        // 書き込めるか、先に確かめる（入れ替えの直前に分かっても遅い）
        var probe = Path.Combine(staging, ".write-test");
        File.WriteAllText(probe, "");
        File.Delete(probe);
    }

    private static void TryDeleteDirectory(string path)
    {
        try { if (Directory.Exists(path)) Directory.Delete(path, recursive: true); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { AppLog.Write($"update: cleanup failed: {path}: {e.Message}"); }
    }

    /// <summary>入れ替えに進めないときの案内。リリースのページをブラウザで開くか尋ねる</summary>
    private static void OfferReleasePage(ReleaseInfo release, string message)
    {
        var answer = MessageBox.Show(string.Format(Strings.Update_OpenReleasePageQuestion, message), "Hanasu", MessageBoxButton.YesNo, MessageBoxImage.Warning);
        if (answer == MessageBoxResult.Yes) Shell.Open(release.ReleaseUrl.AbsoluteUri);
    }

    // 設計判断: DEC-REL-030
    /// <summary>
    /// 入れ替えのスクリプトを別のプロセスで始め、自分は終わる。スクリプトは、このプロセスが終わるのを待ってから
    /// フォルダを取り替えて Hanasu.exe を起動する。パスは引数だけで渡す（スクリプトの文字列には埋め込まない）
    /// </summary>
    private void StartSwapScript(string scriptPath, string installDir, string stagedDir, string workingDirectory)
    {
        var info = new ProcessStartInfo("powershell.exe")
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            // インストール先のフォルダの中を作業場所にすると、フォルダの名前を変えられない
            WorkingDirectory = workingDirectory,
        };
        foreach (var argument in new[]
                 {
                     "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden",
                     "-File", scriptPath,
                     "-WaitPid", Environment.ProcessId.ToString(System.Globalization.CultureInfo.InvariantCulture),
                     "-Install", installDir,
                     "-Staged", stagedDir,
                 })
        {
            info.ArgumentList.Add(argument);
        }
        using var process = Process.Start(info) ?? throw new InvalidOperationException(Strings.Update_ScriptStartFailed);
        AppLog.Write($"update: swap script started (pid {process.Id}), quitting");
        host.QuitForUpdate();
    }

    /// <summary>
    /// 入れ替えのスクリプト（中身は固定。パスは引数で受け取る）。
    /// Hanasu が終わるのを待つ → 今のフォルダを「.old」に改名（ファイルがまだ放されていないことがあるので数秒リトライ）
    /// → 新しいフォルダを今の名前に移す。失敗したら「.old」を戻す → Hanasu.exe を起動 → 「.old」と作業用フォルダを消す（消せなくてもよい）。
    /// 作業用フォルダは、同じドライブで移せるよう、インストール先の隣にある。
    /// </summary>
    private const string SwapScript = """
        param(
            [Parameter(Mandatory = $true)][int]$WaitPid,
            [Parameter(Mandatory = $true)][string]$Install,
            [Parameter(Mandatory = $true)][string]$Staged
        )
        $ErrorActionPreference = 'Stop'
        $Old = $Install + '.old'
        $LogDir = Join-Path $env:LOCALAPPDATA 'Hanasu\Logs'
        function Write-Log([string]$Message) {
            try {
                New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
                Add-Content -LiteralPath (Join-Path $LogDir 'update.log') -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $Message)
            } catch { }
        }

        Write-Log 'update: waiting for Hanasu to exit'
        $stillRunning = $false
        try {
            $process = Get-Process -Id $WaitPid -ErrorAction SilentlyContinue
            if ($process) {
                if (-not $process.WaitForExit(60000)) { $stillRunning = $true }
            }
        } catch { }

        $swapped = $false
        if (-not $stillRunning) {
            try {
                if (Test-Path -LiteralPath $Old) { Remove-Item -LiteralPath $Old -Recurse -Force -ErrorAction SilentlyContinue }
                $renamed = $false
                for ($i = 0; $i -lt 15 -and -not $renamed; $i++) {
                    try {
                        [System.IO.Directory]::Move($Install, $Old)
                        $renamed = $true
                    } catch {
                        Start-Sleep -Seconds 1
                    }
                }
                if ($renamed) {
                    # 展開したばかりのファイルはウイルス対策ソフトが開いていることがあるので、こちらも数秒リトライ
                    $moved = $false
                    $moveError = ''
                    for ($i = 0; $i -lt 15 -and -not $moved; $i++) {
                        try {
                            [System.IO.Directory]::Move($Staged, $Install)
                            $moved = $true
                        } catch {
                            $moveError = $_.Exception.Message
                            Start-Sleep -Seconds 1
                        }
                    }
                    if ($moved) {
                        $swapped = $true
                    } else {
                        Write-Log ('update: move failed, rolling back: ' + $moveError)
                        if (-not (Test-Path -LiteralPath $Install)) {
                            [System.IO.Directory]::Move($Old, $Install)
                        }
                    }
                } else {
                    Write-Log 'update: could not rename the install folder'
                }
            } catch {
                Write-Log ('update: failed: ' + $_.Exception.Message)
            }
        } else {
            Write-Log 'update: Hanasu did not exit in time'
        }

        if (-not $stillRunning) {
            $exe = Join-Path $Install 'Hanasu.exe'
            if (Test-Path -LiteralPath $exe) {
                Start-Process -FilePath $exe -WorkingDirectory $Install
            }
        }

        if ($swapped) {
            Remove-Item -LiteralPath $Old -Recurse -Force -ErrorAction SilentlyContinue
        }
        Set-Location -LiteralPath (Split-Path -Parent $Install)
        Remove-Item -LiteralPath $PSScriptRoot -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log ('update: done (swapped=' + $swapped + ')')
        """;
}
