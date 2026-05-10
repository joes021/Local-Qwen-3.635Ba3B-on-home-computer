. (Join-Path $PSScriptRoot "local-qwen-common.ps1")

$info = Get-LatestReleaseInfo
if ($info.aheadOfPublicRelease) {
    Write-Output "Lokalna instalacija je novija od javnog latest release-a: v$($info.currentVersion) > v$($info.latestVersion)"
    Write-Output "Javni release: $($info.releaseUrl)"
    exit 0
}

if (-not $info.updateAvailable) {
    Write-Output "Instalacija je vec na latest verziji: v$($info.currentVersion)"
    exit 0
}

$downloadUrl = "https://github.com/joes021/Local-Qwen-3.635Ba3B-on-home-computer/releases/latest/download/Local-Qwen-Setup-latest.exe"
$targetDir = Join-Path $env:TEMP "LocalQwenUpdate"
$targetPath = Join-Path $targetDir "Local-Qwen-Setup-latest.exe"

New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
if (Test-Path $targetPath) {
    Remove-Item -LiteralPath $targetPath -Force -ErrorAction SilentlyContinue
}
Write-Output "Trenutna verzija: v$($info.currentVersion)"
Write-Output "Nova verzija: v$($info.latestVersion)"
Write-Output "Release: $($info.releaseUrl)"
Write-Output "Preuzimam latest installer u: $targetPath"
Invoke-WebRequest -UseBasicParsing -Uri $downloadUrl -OutFile $targetPath
if (-not (Test-Path $targetPath)) {
    throw "Update installer nije pronadjen posle preuzimanja: $targetPath"
}
$downloadedFile = Get-Item $targetPath
if ($downloadedFile.Length -le 0) {
    throw "Update installer je preuzet kao prazan fajl: $targetPath"
}
Write-Output ("Preuzet installer: {0:N2} MiB" -f ($downloadedFile.Length / 1MB))
Unblock-File -Path $targetPath -ErrorAction SilentlyContinue
$process = Start-Process -FilePath $targetPath -PassThru

Write-Output "Pokrenut je update installer za v$($info.latestVersion)"
Write-Output "Installer PID: $($process.Id)"
Write-Output "Ako se installer ne pojavi odmah, proveri: $targetPath"
