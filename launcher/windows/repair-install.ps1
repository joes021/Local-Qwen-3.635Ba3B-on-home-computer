. (Join-Path $PSScriptRoot "local-qwen-common.ps1")

$state = Get-InstallState
$root = Get-LocalQwenRoot
$settings = Get-Settings
$messages = New-Object System.Collections.Generic.List[string]
$found = New-Object System.Collections.Generic.List[string]
$fixed = New-Object System.Collections.Generic.List[string]
$manual = New-Object System.Collections.Generic.List[string]
$notes = New-Object System.Collections.Generic.List[string]

Ensure-Directory (Join-Path $root "logs")
Ensure-Directory (Join-Path $root "state")
Ensure-Directory (Join-Path $root "launchers")
Ensure-Directory (Join-Path $root "scripts")
Ensure-Directory (Join-Path $root "config")
Ensure-Directory (Join-Path $root "assets")
Ensure-Directory (Join-Path $root "docs")

try {
    $found.Add("Desktop shortcuts provereni i po potrebi obnovljeni.") | Out-Null
    Repair-DesktopShortcuts
    $messages.Add("Desktop shortcuts su ponovo napravljeni.") | Out-Null
    $fixed.Add("Desktop shortcuts su obnovljeni.") | Out-Null
} catch {
    $messages.Add("Shortcut repair warning: $($_.Exception.Message)") | Out-Null
    $manual.Add("Desktop shortcuts nisu potpuno obnovljeni: $($_.Exception.Message)") | Out-Null
}

$bootstrapScriptDir = Join-Path ${env:ProgramFiles} "LocalQwenSetupBootstrap\scripts"
if ((Test-Path $bootstrapScriptDir) -and -not (Test-Path (Join-Path $root "scripts\local_qwen_runtime.py"))) {
    $found.Add("Shared runtime helper je nedostajao u LocalQwenHome.") | Out-Null
    Copy-Item -Path (Join-Path $bootstrapScriptDir "*") -Destination (Join-Path $root "scripts") -Recurse -Force
    $messages.Add("Shared runtime scripts su obnovljeni iz bootstrap instalacije.") | Out-Null
    $fixed.Add("Shared runtime scripts su vraceni iz bootstrap paketa.") | Out-Null
}

if (-not (Test-Path (Join-Path $state.llamaBinDir "llama-server.exe"))) {
    $found.Add("llama.cpp runtime nije bio prisutan.") | Out-Null
    Download-LlamaCppWindowsCuda -DestinationDir $state.llamaBinDir
    $messages.Add("llama.cpp runtime je ponovo skinut.") | Out-Null
    $fixed.Add("llama.cpp runtime je ponovo preuzet.") | Out-Null
}

if (-not (Test-Path $state.modelFile) -or -not (Test-ModelFileLooksComplete -Path $state.modelFile)) {
    $found.Add("Aktivni model je nedostajao ili je bio nepotpun.") | Out-Null
    Download-RecommendedModel
    $messages.Add("Model je ponovo skinut ili dopunjen.") | Out-Null
    $fixed.Add("Aktivni model je obnovljen.") | Out-Null
}

$found.Add("OpenCode config je osvezen kroz repair tok.") | Out-Null
$configPath = Update-OpenCodeConfig
$messages.Add("OpenCode config je osvezen: $configPath") | Out-Null
$fixed.Add("OpenCode config je upisan: $configPath") | Out-Null

Save-Settings -Settings $settings
$reportPath = Write-InstallReport
$messages.Add("Install report je osvezen: $reportPath") | Out-Null
$fixed.Add("Install report je osvezen.") | Out-Null

if ($manual.Count -eq 0 -and $fixed.Count -eq 0) {
    $notes.Add("Repair nije morao da menja kriticne fajlove; sistem je vec delovao zdravo.") | Out-Null
}

$repairSummaryPath = Get-RepairSummaryPath
$repairSummary = Invoke-RuntimeEngineJson -Arguments @(
    "repair-summary",
    "--outcome", $(if ($manual.Count -gt 0) { "partial" } else { "completed" }),
    "--found-json", ((@($found) | ConvertTo-Json -Compress)),
    "--fixed-json", ((@($fixed) | ConvertTo-Json -Compress)),
    "--manual-json", ((@($manual) | ConvertTo-Json -Compress)),
    "--notes-json", ((@($notes) | ConvertTo-Json -Compress))
)
$repairSummary | ConvertTo-Json -Depth 20 | Set-Content -Path $repairSummaryPath -Encoding UTF8

$summaryPath = Join-Path $root "state\install-summary.txt"
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
    "Actions:",
    ($messages -join [Environment]::NewLine),
    "",
    "Next step:",
    ([string]$repairSummary.nextStep)
) -join [Environment]::NewLine
Set-Content -Path $summaryPath -Value $summary -Encoding UTF8

$messages | ForEach-Object { Write-Host $_ }
Write-Host "Repair found: $($repairSummary.counts.found) | fixed: $($repairSummary.counts.fixed) | manual: $($repairSummary.counts.manual)"
Write-Host "Repair next step: $($repairSummary.nextStep)"
Write-Host "Repair summary: $summaryPath"
