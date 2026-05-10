param(
    [string]$Version = "",
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptRoot "..\..")
$shellScript = Join-Path $scriptRoot "build-run-installer.sh"
$shellRelativeScript = "packaging/linux/build-run-installer.sh"

if (-not (Test-Path $shellScript)) {
    throw "Linux build skripta nije pronadjena: $shellScript"
}

if (-not $Version) {
    $versionInfo = Get-Content (Join-Path $repoRoot "version.json") -Raw | ConvertFrom-Json
    $Version = [string]$versionInfo.version
}

$arguments = @($shellScript, $Version)
if ($OutputDir) {
    $env:OUTPUT_DIR = $OutputDir
}

Push-Location $repoRoot
try {
    $arguments = @($shellRelativeScript, $Version)
    & bash @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Linux installer build nije uspeo (exit $LASTEXITCODE)."
    }
} finally {
    Pop-Location
    if ($OutputDir) {
        Remove-Item Env:OUTPUT_DIR -ErrorAction SilentlyContinue
    }
}
