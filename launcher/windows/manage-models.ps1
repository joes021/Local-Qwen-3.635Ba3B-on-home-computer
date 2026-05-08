. (Join-Path $PSScriptRoot "local-qwen-common.ps1")

param(
    [string]$ModelId,
    [switch]$Download,
    [switch]$UseRecommended
)

$state = Get-InstallState
$recommendation = Get-RecommendationBundle
$catalog = @(Get-ModelCatalog)

if ($UseRecommended) {
    $ModelId = [string]$recommendation.recommendedModel.id
}

if ($ModelId) {
    $selectedState = Set-SelectedModel -ModelId $ModelId
    Write-Host "Aktivni model je postavljen na: $($selectedState.modelId)"
    if ($Download) {
        $source = Download-RecommendedModel -ModelId $ModelId
        Write-Host "Model je osvezen sa izvora: $source"
    }
    $configPath = Update-OpenCodeConfig
    $reportPath = Write-InstallReport
    Write-Host "OpenCode config: $configPath"
    Write-Host "Install report: $reportPath"
    exit 0
}

Write-Host "Trenutno izabran model: $($state.modelId)"
Write-Host "Preporucen model za ovu masinu: $($recommendation.recommendedModel.id)"
Write-Host "Hardverska klasa: $($recommendation.detectedClass)"
Write-Host "Preporucen profil: $($recommendation.recommendedProfile)"
Write-Host ""

$browser = Get-ModelBrowserPayload -FitOnly
$groups = [ordered]@{
    "Preporuceni za ovu masinu" = @($browser.models | Where-Object { $_.fitGroup -eq "recommended" })
    "Moze da radi uz kompromis" = @($browser.models | Where-Object { $_.fitGroup -eq "canRun" })
    "Nije preporuceno za ovu konfiguraciju" = @((Get-ModelBrowserPayload).models | Where-Object { $_.fitGroup -eq "notRecommended" })
}

foreach ($groupName in $groups.Keys) {
    Write-Host $groupName
    foreach ($item in $groups[$groupName]) {
        $marker = if ($item.active) { "*" } elseif ($item.recommended) { "+" } else { "-" }
        $status = @()
        if ($item.installed) { $status += "installed" }
        if ($item.recommended) { $status += "recommended" }
        $status += [string]$item.fitGroup
        if ($item.useCaseBadges -and @($item.useCaseBadges).Count -gt 0) {
            $status += "badge=" + ((@($item.useCaseBadges)) -join "|")
        }
        $line = "{0} {1} | {2} | {3} GiB | Speed {4} | GPU {5}/{6} MiB | RAM {7} GiB | Agentic {8}/10 | OpenCode {9}/10" -f `
            $marker, $item.id, $item.family, $item.approxSizeGiB, $item.speedEstimateLabel, $item.minimumGpuMiB, $item.recommendedGpuMiB, $item.minimumRamGiB, $item.agenticScore, $item.opencodeFit
        Write-Host $line
        Write-Host "    Installed: $($item.installedSizeGiB) GiB | Need disk: $($item.diskNeededGiB) GiB | Free disk: $($item.freeDiskGiB) GiB | Enough disk: $(if ($item.hasEnoughDisk) { 'da' } else { 'ne' })"
        Write-Host "    [$($status -join ', ')] $($item.description)"
    }
    Write-Host ""
}

Write-Host "* = trenutno aktivan model"
Write-Host "+ = preporucen model za ovaj hardver"
