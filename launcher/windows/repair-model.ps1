. (Join-Path $PSScriptRoot "local-qwen-common.ps1")

$state = Get-InstallState
$messages = New-Object System.Collections.Generic.List[string]

$source = Download-RecommendedModel -ModelId ([string]$state.modelId)
$messages.Add("Model je osvezen sa izvora: $source") | Out-Null
$messages.Add("Model path: $($state.modelFile)") | Out-Null
$messages.Add("OpenCode config: $(Update-OpenCodeConfig)") | Out-Null
$messages.Add("Install report: $(Write-InstallReport)") | Out-Null

$messages | ForEach-Object { Write-Host $_ }
