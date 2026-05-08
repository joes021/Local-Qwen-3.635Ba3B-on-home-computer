. (Join-Path $PSScriptRoot "local-qwen-common.ps1")

$state = Get-InstallState
$checks = @()

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

$checks | Format-Table -AutoSize

if ($checks.Where({ -not $_.Ok }).Count -gt 0) {
    exit 1
}
