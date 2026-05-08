. (Join-Path $PSScriptRoot "local-qwen-common.ps1")

param(
    [string]$ModelId,
    [switch]$Download,
    [switch]$UseRecommended
)

$state = Get-InstallState
$recommendation = Get-RecommendationBundle
$downloadCandidates = Get-DownloadCandidates
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
Write-Host "Hardverska klasa: $($downloadCandidates.detectedClass)"
Write-Host "Preporucen profil: $($downloadCandidates.recommendedProfile)"
Write-Host ""

$groups = [ordered]@{
    "Preporuceni za ovu masinu" = @($downloadCandidates.groups.recommended)
    "Moze da radi uz kompromis" = @($downloadCandidates.groups.canRun)
    "Nije preporuceno za ovu konfiguraciju" = @($downloadCandidates.groups.notRecommended)
}

foreach ($groupName in $groups.Keys) {
    Write-Host $groupName
    foreach ($item in $groups[$groupName]) {
        $marker = if ($item.id -eq $state.modelId) { "*" } elseif ($item.id -eq $recommendation.recommendedModel.id) { "+" } else { "-" }
        $line = "{0} {1} | {2} | {3} GiB | GPU {4}/{5} MiB | RAM {6} GiB | Agentic {7}/10 | OpenCode {8}/10" -f `
            $marker, $item.id, $item.family, $item.approxSizeGiB, $item.minimumGpuMiB, $item.recommendedGpuMiB, $item.minimumRamGiB, $item.agenticScore, $item.opencodeFit
        Write-Host $line
        Write-Host "    $($item.description)"
    }
    Write-Host ""
}

Write-Host "* = trenutno aktivan model"
Write-Host "+ = preporucen model za ovaj hardver"
