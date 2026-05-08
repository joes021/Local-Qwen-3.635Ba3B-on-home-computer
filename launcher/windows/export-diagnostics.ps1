. (Join-Path $PSScriptRoot "local-qwen-common.ps1")

$bundle = Export-DiagnosticsBundle
Write-Host "Diagnostics bundle: $bundle"
