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
$gpuLayers = 999

$args = @(
    "-m", $modelPath,
    "--port", $state.port,
    "-ncmoe", [string]$profileData.ncmoe,
    "-c", [string]$ctx,
    "-fa", "on",
    "-n", [string]$maxOutput,
    "-t", [string]$state.threads
)

$usesTurboQuant = $false
if ($state.PSObject.Properties["turboServerExe"] -and $state.turboServerExe) {
    try {
        $usesTurboQuant = ((Resolve-Path $serverExe).Path -eq (Resolve-Path $state.turboServerExe).Path)
    } catch {
        $usesTurboQuant = $false
    }
}

if ($usesTurboQuant) {
    $args += @(
        "-ctk", [string]$profileData.cacheTypeK,
        "-ctv", [string]$profileData.cacheTypeV
    )
} else {
    $detectedGpuMiB = Get-DetectedGpuMemoryMiB

    if ($settings.llama.PSObject.Properties["gpuLayers"] -and $settings.llama.gpuLayers) {
        $gpuLayers = [int]$settings.llama.gpuLayers
    } elseif ($detectedGpuMiB) {
        if ($detectedGpuMiB -le 8192) {
            $gpuLayers = 10
            $ctx = [math]::Min($ctx, 4096)
            $maxOutput = [math]::Min($maxOutput, 1024)
        } elseif ($detectedGpuMiB -le 12288) {
            $gpuLayers = 20
            $ctx = [math]::Min($ctx, 8192)
            $maxOutput = [math]::Min($maxOutput, 2048)
        } else {
            $gpuLayers = 28
            $ctx = [math]::Min($ctx, 16384)
            $maxOutput = [math]::Min($maxOutput, 4096)
        }
    } else {
        $gpuLayers = 20
        $ctx = [math]::Min($ctx, 8192)
        $maxOutput = [math]::Min($maxOutput, 2048)
    }
}

$args = @(
    "-m", $modelPath,
    "--port", $state.port,
    "-ngl", [string]$gpuLayers,
    "-ncmoe", [string]$profileData.ncmoe,
    "-c", [string]$ctx,
    "-fa", "on",
    "-n", [string]$maxOutput,
    "-t", [string]$state.threads
)

if ($usesTurboQuant) {
    $args += @(
        "-ctk", [string]$profileData.cacheTypeK,
        "-ctv", [string]$profileData.cacheTypeV
    )
}

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
