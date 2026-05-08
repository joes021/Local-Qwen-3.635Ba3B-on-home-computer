. (Join-Path $PSScriptRoot "local-qwen-common.ps1")

$state = Get-InstallState
$checks = @()
$healthOk = Test-LlamaHealth
$reportPath = Join-Path (Get-LocalQwenRoot) "state\install-report.json"

$checks += [pscustomobject]@{ Name = "Install root"; Ok = (Test-Path $state.installRoot); Value = $state.installRoot }
$checks += [pscustomobject]@{ Name = "llama server"; Ok = (Test-Path (Get-LlamaServerExe)); Value = (Get-LlamaServerExe) }
$modelOk = (Test-Path $state.modelFile) -and (Test-ModelFileLooksComplete -Path $state.modelFile)
$modelValue = $state.modelFile
if (Test-Path $state.modelFile) {
    $modelValue = "$($state.modelFile) ($((Get-Item $state.modelFile).Length) bytes)"
}
$checks += [pscustomobject]@{ Name = "Model file"; Ok = $modelOk; Value = $modelValue }
$checks += [pscustomobject]@{ Name = "OpenCode command"; Ok = [bool](Get-Command opencode -ErrorAction SilentlyContinue); Value = "opencode" }
$checks += [pscustomobject]@{ Name = "OpenCode config"; Ok = (Test-Path (Get-OpenCodeConfigPath)); Value = (Get-OpenCodeConfigPath) }
$checks += [pscustomobject]@{ Name = "Install report"; Ok = (Test-Path $reportPath); Value = $reportPath }
$checks += [pscustomobject]@{ Name = "Health endpoint"; Ok = $healthOk; Value = (Get-LlamaHealthUrl) }

$checks | Format-Table -AutoSize

Write-Host ""
Write-Host "Efektivni runtime plan:" -ForegroundColor Cyan
Get-EffectiveServerPlan -Profile ([string](Get-Settings).profile) | Format-List | Out-Host

if (Test-Path $reportPath) {
    Write-Host ""
    Write-Host "Install report:" -ForegroundColor Cyan
    Get-Content $reportPath | Out-Host
}

if ($checks.Where({ -not $_.Ok }).Count -gt 0) {
    exit 1
}
