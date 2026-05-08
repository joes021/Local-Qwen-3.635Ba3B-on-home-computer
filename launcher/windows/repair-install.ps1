. (Join-Path $PSScriptRoot "local-qwen-common.ps1")

$state = Get-InstallState
$root = Get-LocalQwenRoot
$settings = Get-Settings
$messages = New-Object System.Collections.Generic.List[string]

Ensure-Directory (Join-Path $root "logs")
Ensure-Directory (Join-Path $root "state")
Ensure-Directory (Join-Path $root "launchers")
Ensure-Directory (Join-Path $root "config")
Ensure-Directory (Join-Path $root "assets")
Ensure-Directory (Join-Path $root "docs")

try {
    Repair-DesktopShortcuts
    $messages.Add("Desktop shortcuts su ponovo napravljeni.") | Out-Null
} catch {
    $messages.Add("Shortcut repair warning: $($_.Exception.Message)") | Out-Null
}

if (-not (Test-Path (Join-Path $state.llamaBinDir "llama-server.exe"))) {
    Download-LlamaCppWindowsCuda -DestinationDir $state.llamaBinDir
    $messages.Add("llama.cpp runtime je ponovo skinut.") | Out-Null
}

if (-not (Test-Path $state.modelFile) -or -not (Test-ModelFileLooksComplete -Path $state.modelFile)) {
    Download-RecommendedModel
    $messages.Add("Model je ponovo skinut ili dopunjen.") | Out-Null
}

$configPath = Update-OpenCodeConfig
$messages.Add("OpenCode config je osvezen: $configPath") | Out-Null

Save-Settings -Settings $settings
$reportPath = Write-InstallReport
$messages.Add("Install report je osvezen: $reportPath") | Out-Null

$summaryPath = Join-Path $root "state\install-summary.txt"
$summary = @(
    "Repair completed at $(Get-Date -Format s)",
    "Install root: $root",
    "Model: $($state.modelFile)",
    "Server: $(Get-LlamaServerExe)",
    "Desktop folder: $(Get-DesktopTargetDir)",
    "",
    "Actions:",
    ($messages -join [Environment]::NewLine)
) -join [Environment]::NewLine
Set-Content -Path $summaryPath -Value $summary -Encoding UTF8

$messages | ForEach-Object { Write-Host $_ }
Write-Host "Repair summary: $summaryPath"
