. (Join-Path $PSScriptRoot "local-qwen-common.ps1")

$info = Get-LatestReleaseInfo
$info | ConvertTo-Json -Depth 10

if ($info.updateAvailable) {
    Write-Host "Dostupan je noviji release: v$($info.latestVersion)"
    Write-Host "Link: $($info.releaseUrl)"
} else {
    Write-Host "Instalacija je vec na latest verziji: v$($info.currentVersion)"
}
