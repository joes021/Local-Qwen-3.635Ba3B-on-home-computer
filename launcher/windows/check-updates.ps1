param(
    [switch]$Json
)

. (Join-Path $PSScriptRoot "local-qwen-common.ps1")

$info = Get-LatestReleaseInfo

if ($Json) {
    $info | ConvertTo-Json -Depth 10
    exit 0
}

if ($info.aheadOfPublicRelease) {
    Write-Output "Lokalna instalacija je novija od javnog latest release-a: v$($info.currentVersion) > v$($info.latestVersion)"
    Write-Output "Poslednji javni release: $($info.releaseUrl)"
} elseif ($info.updateAvailable) {
    Write-Output "Dostupan je noviji release: v$($info.latestVersion)"
    Write-Output "Link: $($info.releaseUrl)"
} else {
    Write-Output "Instalacija je vec na latest verziji: v$($info.currentVersion)"
}
