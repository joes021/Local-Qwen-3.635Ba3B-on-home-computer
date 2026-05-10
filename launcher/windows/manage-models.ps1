param(
    [string]$ModelId,
    [switch]$Download,
    [switch]$UseRecommended,
    [string]$Search = "",
    [string]$Family = "",
    [switch]$InstalledOnly,
    [switch]$RecommendedOnly,
    [switch]$FitOnly,
    [switch]$CoderOnly,
    [switch]$VerifiedOnly
)

. (Join-Path $PSScriptRoot "local-qwen-common.ps1")

$state = Get-InstallState
$recommendation = Get-RecommendationBundle
$catalog = @(Get-ModelCatalog)

function Format-ModelBrowserValue {
    param(
        $Value,
        [string]$Suffix = "",
        [switch]$TreatZeroAsUnknown
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return "nepoznato"
    }

    if ($TreatZeroAsUnknown) {
        try {
            if ([double]$Value -le 0) {
                return "nepoznato"
            }
        } catch {
        }
    }

    if ($Suffix) {
        return "$Value $Suffix"
    }

    return [string]$Value
}

function Format-EnoughDiskLabel {
    param($Value)

    if ($null -eq $Value) {
        return "nepoznato"
    }

    if ($Value) {
        return "da"
    }

    return "ne"
}

function Format-InstalledSizeLabel {
    param($Item)

    if (-not $Item.installed) {
        return "nije skinut"
    }

    return Format-ModelBrowserValue -Value $Item.installedSizeGiB -Suffix 'GiB'
}

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

$hasExplicitBrowserFilter = (
    -not [string]::IsNullOrWhiteSpace($Search) -or
    -not [string]::IsNullOrWhiteSpace($Family) -or
    $InstalledOnly -or
    $RecommendedOnly -or
    $FitOnly -or
    $CoderOnly -or
    $VerifiedOnly
)
$effectiveFitOnly = if ($hasExplicitBrowserFilter) { [bool]$FitOnly } else { $true }
$browser = Get-ModelBrowserPayload `
    -Search $Search `
    -Family $Family `
    -InstalledOnly:$InstalledOnly `
    -RecommendedOnly:$RecommendedOnly `
    -FitOnly:$effectiveFitOnly `
    -CoderOnly:$CoderOnly `
    -VerifiedOnly:$VerifiedOnly

$groups = [ordered]@{}
$recommendedModels = @($browser.models | Where-Object { $_.recommended -or $_.fitGroup -eq "recommended" })
$canRunModels = @($browser.models | Where-Object { $_.fitGroup -eq "canRun" -and -not $_.recommended })
$notRecommendedModels = @($browser.models | Where-Object { $_.fitGroup -eq "notRecommended" -and -not $_.recommended })
$unknownFitModels = @($browser.models | Where-Object { $_.fitGroup -notin @("recommended", "canRun", "notRecommended") -and -not $_.recommended })

if ($recommendedModels.Count -gt 0) {
    $groups["Preporuceni za ovu masinu"] = $recommendedModels
}
if ($canRunModels.Count -gt 0) {
    $groups["Moze da radi uz kompromis"] = $canRunModels
}
if ((-not $effectiveFitOnly) -and $notRecommendedModels.Count -gt 0) {
    $groups["Nije preporuceno za ovu konfiguraciju"] = $notRecommendedModels
}
if ((-not $effectiveFitOnly) -and $unknownFitModels.Count -gt 0) {
    $groups["Rucno dodati / nepoznat fit"] = $unknownFitModels
}

if ($groups.Count -eq 0) {
    Write-Host "Nema modela za zadate filtere."
    exit 0
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
        $line = "{0} {1} | {2} | {3} | Speed {4} | GPU {5}/{6} | RAM {7} | Agentic {8}/10 | OpenCode {9}/10" -f `
            $marker, $item.id, $item.family, (Format-ModelBrowserValue -Value $item.approxSizeGiB -Suffix 'GiB' -TreatZeroAsUnknown), $item.speedEstimateLabel, (Format-ModelBrowserValue -Value $item.minimumGpuMiB -Suffix 'MiB' -TreatZeroAsUnknown), (Format-ModelBrowserValue -Value $item.recommendedGpuMiB -Suffix 'MiB' -TreatZeroAsUnknown), (Format-ModelBrowserValue -Value $item.minimumRamGiB -Suffix 'GiB' -TreatZeroAsUnknown), $item.agenticScore, $item.opencodeFit
        Write-Host $line
        Write-Host "    Installed: $(Format-InstalledSizeLabel -Item $item) | Need disk: $(Format-ModelBrowserValue -Value $item.diskNeededGiB -Suffix 'GiB') | Free disk: $(Format-ModelBrowserValue -Value $item.freeDiskGiB -Suffix 'GiB') | Enough disk: $(Format-EnoughDiskLabel -Value $item.hasEnoughDisk)"
        Write-Host "    [$($status -join ', ')] $($item.description)"
    }
    Write-Host ""
}

Write-Host "* = trenutno aktivan model"
Write-Host "+ = preporucen model za ovaj hardver"
