. (Join-Path $PSScriptRoot "local-qwen-common.ps1")

$info = Get-LatestReleaseInfo
$info | ConvertTo-Json -Depth 10

if ($info.aheadOfPublicRelease) {
    Write-Host "Lokalna instalacija je novija od javnog latest release-a: v$($info.currentVersion) > v$($info.latestVersion)"
    Write-Host "Poslednji javni release: $($info.releaseUrl)"
} elseif ($info.updateAvailable) {
    Write-Host "Dostupan je noviji release: v$($info.latestVersion)"
    Write-Host "Link: $($info.releaseUrl)"
} else {
    Write-Host "Instalacija je vec na latest verziji: v$($info.currentVersion)"
}
