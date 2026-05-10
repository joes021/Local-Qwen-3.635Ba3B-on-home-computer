. (Join-Path $PSScriptRoot "local-qwen-common.ps1")

$state = Get-InstallState
$messages = New-Object System.Collections.Generic.List[string]
$modelPath = Get-StateModelFilePath -State $state

$source = Download-RecommendedModel -ModelId ([string]$state.modelId)
if ($source -eq "already-installed") {
    $messages.Add("Model je vec prisutan i deluje kompletno, pa download nije bio potreban.") | Out-Null
} else {
    $messages.Add("Model je osvezen sa izvora: $source") | Out-Null
}
$messages.Add("Model path: $modelPath") | Out-Null
$messages.Add("OpenCode config: $(Update-OpenCodeConfig)") | Out-Null
$messages.Add("Install report: $(Write-InstallReport)") | Out-Null

$messages | ForEach-Object { Write-Output $_ }
