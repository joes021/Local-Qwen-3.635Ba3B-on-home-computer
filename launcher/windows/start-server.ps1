param(
    [ValidateSet("speed", "balanced", "video")]
    [string]$Profile,
    [switch]$Foreground
)

. (Join-Path $PSScriptRoot "local-qwen-common.ps1")

$state = Get-InstallState
$defaults = Get-Defaults
$settings = Get-Settings

if (-not $Profile) {
    $Profile = if ($settings.profile) { [string]$settings.profile } else { [string]$state.defaultProfile }
}

$profileData = $defaults.profiles.$Profile
if (-not $profileData) {
    throw "Nepoznat profil: $Profile"
}

$logDir = Join-Path $state.installRoot "logs"
Ensure-Directory $logDir

$serverExe = Get-LlamaServerExe
$modelPath = Get-LlamaModelPath

$ctx = if ($settings.llama.contextSize) { [int]$settings.llama.contextSize } else { [int]$profileData.contextSize }
$maxOutput = if ($settings.llama.maxOutputTokens) { [int]$settings.llama.maxOutputTokens } else { 8192 }

$args = @(
    "-m", $modelPath,
    "--port", $state.port,
    "-ngl", "999",
    "-ncmoe", [string]$profileData.ncmoe,
    "-c", [string]$ctx,
    "-ctk", [string]$profileData.cacheTypeK,
    "-ctv", [string]$profileData.cacheTypeV,
    "-fa", "on",
    "-n", [string]$maxOutput,
    "-t", [string]$state.threads
)

if ($state.noMmap) {
    $args += "--no-mmap"
}

if ($state.mlock) {
    $args += "--mlock"
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$stdoutLog = Join-Path $logDir "llama-$Profile-$stamp.out.log"
$stderrLog = Join-Path $logDir "llama-$Profile-$stamp.err.log"

Get-Process llama-server -ErrorAction SilentlyContinue | Stop-Process -Force

if ($Foreground) {
    & $serverExe @args
    exit $LASTEXITCODE
}

Start-Process -FilePath $serverExe -ArgumentList $args -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog -WindowStyle Hidden
Start-Sleep -Seconds 8

if (Test-LlamaHealth) {
    Write-Host "llama.cpp je pokrenut na http://127.0.0.1:$($state.port)"
    Write-Host "Profil: $Profile"
    Write-Host "Model: $modelPath"
} else {
    Write-Host "Pokretanje nije potvrđeno. Pogledaj log:"
    Write-Host $stderrLog
}
