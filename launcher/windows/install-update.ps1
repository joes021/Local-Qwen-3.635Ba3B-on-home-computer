. (Join-Path $PSScriptRoot "local-qwen-common.ps1")

$info = Get-LatestReleaseInfo
if (-not $info.updateAvailable) {
    Write-Host "Instalacija je vec na latest verziji: v$($info.currentVersion)"
    exit 0
}

$downloadUrl = "https://github.com/joes021/Local-Qwen-3.635Ba3B-on-home-computer/releases/latest/download/Local-Qwen-Setup-latest.exe"
$targetDir = Join-Path $env:TEMP "LocalQwenUpdate"
$targetPath = Join-Path $targetDir "Local-Qwen-Setup-latest.exe"

New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
Write-Host "Preuzimam latest installer u: $targetPath"
Invoke-WebRequest -UseBasicParsing -Uri $downloadUrl -OutFile $targetPath
Unblock-File -Path $targetPath -ErrorAction SilentlyContinue
Start-Process -FilePath $targetPath

Write-Host "Pokrenut je update installer za v$($info.latestVersion)"
Write-Host "Ako se installer ne pojavi odmah, proveri: $targetPath"
