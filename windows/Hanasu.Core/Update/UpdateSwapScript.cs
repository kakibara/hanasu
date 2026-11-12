namespace Hanasu.Core.Update;

// 要件: REQ-REL-010, REQ-REL-013
// 設計判断: DEC-REL-030, DEC-REL-031
/// <summary>
/// Windows のアップデートの入れ替えのスクリプト（中身は固定。パスは引数で受け取る）。
/// Hanasu が終わるのを待つ → 動いている cli\hanasu.exe を探し直して終わらせる → 今のフォルダを「.old」に改名（ファイルがまだ放されていないことがあるので数秒リトライ。
/// 改名できなければ、印のファイルに rename-failed を足す）→ 新しいフォルダを今の名前に移す。失敗したら「.old」を戻す → Hanasu.exe を起動 →
/// 「.old」と作業用フォルダを消す（消せなくてもよい）。作業用フォルダは、同じドライブで移せるよう、インストール先の隣にある。
/// </summary>
public static class UpdateSwapScript
{
    public const string Text = """
        param(
            [Parameter(Mandatory = $true)][int]$WaitPid,
            [Parameter(Mandatory = $true)][string]$Install,
            [Parameter(Mandatory = $true)][string]$Staged,
            [string]$Cli = '',
            [string]$Pending = ''
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

        # 要件: REQ-REL-013
        # 設計判断: DEC-REL-031
        # 動いている hanasu（cli\hanasu.exe）を、名前を変える直前に探し直して終わらせる（確認のあと、ダウンロードの間に起動したものも含める）
        if (-not $stillRunning -and $Cli) {
            try {
                foreach ($command in @(Get-Process -Name 'hanasu' -ErrorAction SilentlyContinue)) {
                    $path = $null
                    try { $path = $command.Path } catch { }
                    if ($path -and [string]::Equals($path, $Cli, [System.StringComparison]::OrdinalIgnoreCase)) {
                        try {
                            $command.Kill()
                            [void]$command.WaitForExit(5000)
                            Write-Log ('update: stopped hanasu ' + $command.Id)
                        } catch {
                            Write-Log ('update: could not stop hanasu ' + $command.Id)
                        }
                    }
                }
            } catch { }
        }

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
                    # 新しく起動したアプリ（古い版のまま）が理由を知らせる（管理者として動いている hanasu・作業フォルダが cli の中のターミナル）
                    if ($Pending) { try { Add-Content -LiteralPath $Pending -Value 'rename-failed' } catch { } }
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
