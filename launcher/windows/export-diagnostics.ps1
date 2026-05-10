. (Join-Path $PSScriptRoot "local-qwen-common.ps1")

$bundle = Export-DiagnosticsBundle
if (-not (Test-Path $bundle)) {
    throw "Diagnostics bundle nije pronadjen posle export-a: $bundle"
}

$bundleInfo = Get-Item $bundle
Write-Output "Diagnostics bundle: $bundle"
Write-Output ("Velicina bundle-a: {0:N2} MiB" -f ($bundleInfo.Length / 1MB))
