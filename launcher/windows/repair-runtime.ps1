. (Join-Path $PSScriptRoot "local-qwen-common.ps1")

$state = Get-InstallState
$messages = New-Object System.Collections.Generic.List[string]

$restored = @(Restore-BundledSupportFiles)
if ($restored.Count -gt 0) {
    $messages.Add("Obnovljeni bundled fajlovi: $($restored -join ', ')") | Out-Null
}

Ensure-Directory (Join-Path (Get-LocalQwenRoot) "launchers")
Repair-DesktopShortcuts
$messages.Add("Desktop shortcuts su obnovljeni.") | Out-Null

if (-not (Test-Path (Join-Path $state.llamaBinDir "llama-server.exe"))) {
    Download-LlamaCppWindowsCuda -DestinationDir $state.llamaBinDir
    $messages.Add("llama.cpp runtime je ponovo skinut.") | Out-Null
} else {
    $messages.Add("llama.cpp runtime je vec prisutan.") | Out-Null
}

$messages.Add("Install report: $(Write-InstallReport)") | Out-Null
$messages | ForEach-Object { Write-Host $_ }
