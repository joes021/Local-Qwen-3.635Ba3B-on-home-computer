. (Join-Path $PSScriptRoot "local-qwen-common.ps1")

$state = Get-InstallState
$checks = @()
$healthOk = Test-LlamaHealth
$reportPath = Join-Path (Get-LocalQwenStateRoot) "state\install-report.json"
$modelPath = Get-StateModelFilePath -State $state

try {
    $reportPath = Write-InstallReport
} catch {
}

$checks += [pscustomobject]@{ Name = "Install root"; Ok = (Test-Path $state.installRoot); Value = $state.installRoot }
$checks += [pscustomobject]@{ Name = "llama server"; Ok = (Test-Path (Get-LlamaServerExe)); Value = (Get-LlamaServerExe) }
$modelOk = (Test-Path $modelPath) -and (Test-ModelFileLooksComplete -Path $modelPath)
$modelValue = $modelPath
if (Test-Path $modelPath) {
    $modelValue = "$modelPath ($((Get-Item $modelPath).Length) bytes)"
}
$checks += [pscustomobject]@{ Name = "Model file"; Ok = $modelOk; Value = $modelValue }
$openCodeValue = "--"
try {
    $openCodeValue = Get-OpenCodeExecutable
} catch {
    $openCodeValue = $_.Exception.Message
}
$checks += [pscustomobject]@{ Name = "OpenCode command"; Ok = (Test-OpenCodeAvailable); Value = $openCodeValue }
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
    $sanitizedReport = Get-SanitizedInstallReportJson -HealthOk:$healthOk
    if ($sanitizedReport) {
        $sanitizedReport | Out-Host
    } else {
        Get-Content $reportPath | Out-Host
    }
}

if ($checks.Where({ -not $_.Ok }).Count -gt 0) {
    exit 1
}
