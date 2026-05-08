. (Join-Path $PSScriptRoot "local-qwen-common.ps1")

$settings = Get-Settings
$messages = New-Object System.Collections.Generic.List[string]

$restored = @(Restore-BundledSupportFiles)
if ($restored.Count -gt 0) {
    $messages.Add("Obnovljeni bundled fajlovi: $($restored -join ', ')") | Out-Null
}

Save-Settings -Settings $settings
$messages.Add("Settings: $(Join-Path (Get-LocalQwenRoot) 'state\settings.json')") | Out-Null
$messages.Add("OpenCode config: $(Update-OpenCodeConfig)") | Out-Null
$messages.Add("Install report: $(Write-InstallReport)") | Out-Null

$messages | ForEach-Object { Write-Host $_ }
