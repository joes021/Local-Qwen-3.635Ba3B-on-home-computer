. (Join-Path $PSScriptRoot "local-qwen-common.ps1")

$state = Get-InstallState
$root = Get-LocalQwenStateRoot
$settings = Get-Settings
$messages = New-Object System.Collections.Generic.List[string]
$found = New-Object System.Collections.Generic.List[string]
$fixed = New-Object System.Collections.Generic.List[string]
$manual = New-Object System.Collections.Generic.List[string]
$notes = New-Object System.Collections.Generic.List[string]
$attempted = New-Object System.Collections.Generic.HashSet[string]
$repairAppControlScript = Join-Path $PSScriptRoot "repair-app-control.ps1"

function Add-UniqueListItem {
    param(
        [Parameter(Mandatory = $true)]$List,
        [Parameter(Mandatory = $true)][string]$Value
    )

    if (-not [string]::IsNullOrWhiteSpace($Value) -and -not $List.Contains($Value)) {
        $List.Add($Value) | Out-Null
    }
}

function Invoke-RepairStep {
    param([Parameter(Mandatory = $true)][pscustomobject]$Step)

    Add-UniqueListItem -List $found -Value ("Planirana repair akcija: {0}" -f $Step.title)

    switch ([string]$Step.id) {
        "repair-app-control" {
            if (Test-Path $repairAppControlScript) {
                try {
                    & (Get-WindowsPowerShellExe) -NoProfile -ExecutionPolicy Bypass -File $repairAppControlScript | ForEach-Object {
                        if ($_){ Add-UniqueListItem -List $messages -Value ([string]$_) }
                    }
                    Add-UniqueListItem -List $fixed -Value "App Control / WDAC repair je pokrenut."
                } catch {
                    Add-UniqueListItem -List $manual -Value ("App Control repair trazi rucnu proveru: {0}" -f $_.Exception.Message)
                }
            } else {
                Add-UniqueListItem -List $manual -Value "repair-app-control.ps1 nije pronadjen."
            }
        }
        "repair-runtime" {
            if (-not (Test-Path (Join-Path $state.llamaBinDir "llama-server.exe"))) {
                Download-LlamaCppWindowsCuda -DestinationDir $state.llamaBinDir
                Add-UniqueListItem -List $messages -Value "llama.cpp runtime je ponovo skinut."
                Add-UniqueListItem -List $fixed -Value "llama.cpp runtime je ponovo preuzet."
            } else {
                Add-UniqueListItem -List $notes -Value "repair-runtime je preskocen jer je runtime vec bio prisutan pri ponovnoj proveri."
            }
        }
        "repair-model" {
            if (-not (Test-Path $state.modelFile) -or -not (Test-ModelFileLooksComplete -Path $state.modelFile)) {
                Download-RecommendedModel
                Add-UniqueListItem -List $messages -Value "Model je ponovo skinut ili dopunjen."
                Add-UniqueListItem -List $fixed -Value "Aktivni model je obnovljen."
            } else {
                Add-UniqueListItem -List $notes -Value "repair-model je preskocen jer je model vec bio zdrav pri ponovnoj proveri."
            }
        }
        "repair-config" {
            $configPath = Update-OpenCodeConfig
            Add-UniqueListItem -List $messages -Value ("OpenCode config je osvezen: {0}" -f $configPath)
            Add-UniqueListItem -List $fixed -Value ("OpenCode config je upisan: {0}" -f $configPath)
        }
        "start-server" {
            Add-UniqueListItem -List $notes -Value "Repair plan je predlozio start-server; to ostavljamo korisniku kao sledeci korak posle repair-a."
        }
        default {
            Add-UniqueListItem -List $manual -Value ("Nepoznata repair akcija: {0}" -f $Step.id)
        }
    }
}

Ensure-Directory (Join-Path $root "logs")
Ensure-Directory (Join-Path $root "state")
Ensure-Directory (Join-Path $root "launchers")
Ensure-Directory (Join-Path $root "scripts")
Ensure-Directory (Join-Path $root "config")
Ensure-Directory (Join-Path $root "assets")
Ensure-Directory (Join-Path $root "docs")

try {
    $restoredSupport = @(Restore-BundledSupportFiles)
    if ($restoredSupport.Count -gt 0) {
        Add-UniqueListItem -List $found -Value "Bundled support fajlovi su provereni i osvezeni."
        Add-UniqueListItem -List $messages -Value ("Bundled support osvezen: {0}" -f ($restoredSupport -join ", "))
        Add-UniqueListItem -List $fixed -Value "Launchers, scripts i release-notes su osvezeni iz bootstrap paketa."
    }

    Add-UniqueListItem -List $found -Value "Desktop shortcuts provereni i po potrebi obnovljeni."
    Repair-DesktopShortcuts
    Add-UniqueListItem -List $messages -Value "Desktop shortcuts su ponovo napravljeni."
    Add-UniqueListItem -List $fixed -Value "Desktop shortcuts su obnovljeni."
} catch {
    Add-UniqueListItem -List $messages -Value ("Shortcut repair warning: {0}" -f $_.Exception.Message)
    Add-UniqueListItem -List $manual -Value ("Desktop shortcuts nisu potpuno obnovljeni: {0}" -f $_.Exception.Message)
}

$bootstrapScriptDir = Join-Path ${env:ProgramFiles} "LocalQwenSetupBootstrap\scripts"
if ((Test-Path $bootstrapScriptDir) -and -not (Test-Path (Join-Path $root "scripts\local_qwen_runtime.py"))) {
    Add-UniqueListItem -List $found -Value "Shared runtime helper je nedostajao u LocalQwenHome."
    Copy-Item -Path (Join-Path $bootstrapScriptDir "*") -Destination (Join-Path $root "scripts") -Recurse -Force
    Add-UniqueListItem -List $messages -Value "Shared runtime scripts su obnovljeni iz bootstrap instalacije."
    Add-UniqueListItem -List $fixed -Value "Shared runtime scripts su vraceni iz bootstrap paketa."
}

for ($round = 1; $round -le 6; $round++) {
    $repairPlan = Get-RepairPlanData
    $nextStep = @($repairPlan.steps | Where-Object { -not $attempted.Contains([string]$_.id) } | Select-Object -First 1)
    if (-not $nextStep -or $nextStep.Count -eq 0) {
        break
    }

    $currentStep = $nextStep[0]
    $attempted.Add([string]$currentStep.id) | Out-Null
    Add-UniqueListItem -List $messages -Value ("Repair round {0}: {1}" -f $round, $currentStep.title)
    Invoke-RepairStep -Step $currentStep
}

$configPath = Update-OpenCodeConfig
Add-UniqueListItem -List $messages -Value ("OpenCode config je osvezen na kraju repair toka: {0}" -f $configPath)
Add-UniqueListItem -List $fixed -Value ("OpenCode config je potvrden na kraju repair toka: {0}" -f $configPath)

Save-Settings -Settings $settings
$reportPath = Write-InstallReport
Add-UniqueListItem -List $messages -Value ("Install report je osvezen: {0}" -f $reportPath)
Add-UniqueListItem -List $fixed -Value "Install report je osvezen."

$finalPlan = Get-RepairPlanData
if (@($finalPlan.steps).Count -gt 0) {
    foreach ($step in @($finalPlan.steps)) {
        Add-UniqueListItem -List $manual -Value ("I dalje ceka korak: {0} - {1}" -f $step.title, $step.reason)
    }
}

if ($manual.Count -eq 0 -and $fixed.Count -eq 0) {
    Add-UniqueListItem -List $notes -Value "Repair nije morao da menja kriticne fajlove; sistem je vec delovao zdravo."
}

$repairSummaryPath = Get-RepairSummaryPath
$repairSummaryArguments = [System.Collections.Generic.List[string]]::new()
@(
    "repair-summary",
    "--outcome", $(if ($manual.Count -gt 0) { "partial" } else { "completed" })
) | ForEach-Object { $repairSummaryArguments.Add($_) | Out-Null }

$foundArgument = Convert-CollectionToCliListArgument -Collection $found
if (-not [string]::IsNullOrWhiteSpace($foundArgument)) {
    $repairSummaryArguments.Add("--found-json") | Out-Null
    $repairSummaryArguments.Add($foundArgument) | Out-Null
}

$fixedArgument = Convert-CollectionToCliListArgument -Collection $fixed
if (-not [string]::IsNullOrWhiteSpace($fixedArgument)) {
    $repairSummaryArguments.Add("--fixed-json") | Out-Null
    $repairSummaryArguments.Add($fixedArgument) | Out-Null
}

$manualArgument = Convert-CollectionToCliListArgument -Collection $manual
if (-not [string]::IsNullOrWhiteSpace($manualArgument)) {
    $repairSummaryArguments.Add("--manual-json") | Out-Null
    $repairSummaryArguments.Add($manualArgument) | Out-Null
}

$notesArgument = Convert-CollectionToCliListArgument -Collection $notes
if (-not [string]::IsNullOrWhiteSpace($notesArgument)) {
    $repairSummaryArguments.Add("--notes-json") | Out-Null
    $repairSummaryArguments.Add($notesArgument) | Out-Null
}

$repairSummary = Invoke-RuntimeEngineJson -Arguments @($repairSummaryArguments.ToArray())
Write-Utf8NoBomText -Path $repairSummaryPath -Content ($repairSummary | ConvertTo-Json -Depth 20)

$summaryPath = Get-InstallSummaryPath
$summary = @(
    "Repair completed at $(Get-Date -Format s)",
    "Install root: $root",
    "Model: $($state.modelFile)",
    "Server: $(Get-LlamaServerExe)",
    "Desktop folder: $(Get-DesktopTargetDir)",
    "Repair summary: $repairSummaryPath",
    "",
    "Found:",
    ($(if ($found.Count -gt 0) { $found -join [Environment]::NewLine } else { "Nema posebnih problema." })),
    "",
    "Fixed:",
    ($(if ($fixed.Count -gt 0) { $fixed -join [Environment]::NewLine } else { "Nista nije moralo da se popravlja." })),
    "",
    "Manual:",
    ($(if ($manual.Count -gt 0) { $manual -join [Environment]::NewLine } else { "Nema rucnih koraka." })),
    "",
    "Notes:",
    ($(if ($notes.Count -gt 0) { $notes -join [Environment]::NewLine } else { "Nema dodatnih napomena." })),
    "",
    "Actions:",
    ($messages -join [Environment]::NewLine),
    "",
    "Next step:",
    ([string]$repairSummary.nextStep)
) -join [Environment]::NewLine
Write-Utf8NoBomText -Path $summaryPath -Content $summary

$messages | ForEach-Object { Write-Output $_ }
Write-Output "Repair found: $($repairSummary.counts.found) | fixed: $($repairSummary.counts.fixed) | manual: $($repairSummary.counts.manual)"
Write-Output "Repair next step: $($repairSummary.nextStep)"
Write-Output "Repair summary json: $repairSummaryPath"
Write-Output "Repair summary text: $summaryPath"
