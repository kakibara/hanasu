# 同梱する llama.cpp（llama-server）の Windows 版を取ってきて、SHA-256 を確かめてから publish のフォルダの llama\ に入れる。
#   pwsh scripts/fetch-llama-cpp.ps1 -Destination <publish のフォルダ>
# 版とハッシュは scripts/llama-cpp.lock（Mac の scripts/fetch-llama-cpp.sh と同じ）。tagpr.yml・windows.yml の publish のあとに動かす。
# 設計判断: DEC-COM-061
param([Parameter(Mandatory = $true)][string]$Destination)
$ErrorActionPreference = 'Stop'

$lock = @{}
Get-Content (Join-Path $PSScriptRoot 'llama-cpp.lock') | Where-Object { $_ -match '^[a-z_]+=' } | ForEach-Object {
    $key, $value = $_ -split '=', 2
    $lock[$key] = $value
}
$version = $lock['version']
$asset = $lock['windows_asset']
$expected = $lock['windows_sha256']

$work = Join-Path ([System.IO.Path]::GetTempPath()) "llama-cpp-$version"
New-Item -ItemType Directory -Force -Path $work | Out-Null
$archive = Join-Path $work $asset
if (-not (Test-Path $archive) -or (Get-FileHash -Algorithm SHA256 $archive).Hash.ToLowerInvariant() -ne $expected) {
    Write-Output "llama.cpp $version を取ってきます: $asset"
    Invoke-WebRequest -Uri "https://github.com/ggml-org/llama.cpp/releases/download/$version/$asset" -OutFile $archive
}
$actual = (Get-FileHash -Algorithm SHA256 $archive).Hash.ToLowerInvariant()
if ($actual -ne $expected) {
    Remove-Item $archive
    throw "$asset の SHA-256 が想定と違います（$actual）"
}

$extracted = Join-Path $work 'extracted'
if (Test-Path $extracted) { Remove-Item -Recurse -Force $extracted }
Expand-Archive -Path $archive -DestinationPath $extracted
$target = Join-Path $Destination 'llama'
New-Item -ItemType Directory -Force -Path $target | Out-Null
# llama-server と、それが読む DLL だけ。ほかの道具（llama-cli など）とその *-impl.dll は入れない
Copy-Item (Join-Path $extracted 'llama-server.exe') $target
Get-ChildItem $extracted -Filter '*.dll' |
    Where-Object { $_.Name -notmatch '-impl\.dll$' -or $_.Name -eq 'llama-server-impl.dll' } |
    ForEach-Object { Copy-Item $_.FullName $target }
Get-ChildItem $extracted -Filter 'LICENSE*' | ForEach-Object { Copy-Item $_.FullName $target }
Write-Output "llama.cpp ${version}: $target"
Get-ChildItem $target | Select-Object Name, Length | Format-Table -AutoSize
