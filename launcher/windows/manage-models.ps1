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
Write-Host ""
Write-Host "Katalog:"

foreach ($item in $catalog) {
    $marker = if ($item.id -eq $state.modelId) { "*" } elseif ($item.id -eq $recommendation.recommendedModel.id) { "+" } else { "-" }
    $line = "{0} {1} | {2} GiB | min GPU {3} MiB | min RAM {4} GiB" -f $marker, $item.id, $item.approxSizeGiB, $item.recommendedGpuMiB, $item.minimumRamGiB
    Write-Host $line
    Write-Host "    $($item.description)"
}

Write-Host ""
Write-Host "* = trenutno aktivan model"
Write-Host "+ = preporucen model za ovaj hardver"
