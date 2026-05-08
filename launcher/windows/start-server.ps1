param(
    [ValidateSet("speed", "balanced", "video")]
    [string]$Profile,
    [switch]$Foreground,
    [int]$WaitSeconds = 90
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
$contextCustomized = if ($settings.llama.PSObject.Properties["contextSizeCustomized"]) {
    [bool]$settings.llama.contextSizeCustomized
} else {
    ([int]$ctx -ne [int]$profileData.contextSize)
}
$outputCustomized = if ($settings.llama.PSObject.Properties["maxOutputTokensCustomized"]) {
    [bool]$settings.llama.maxOutputTokensCustomized
} else {
    ([int]$maxOutput -ne 8192)
}

$usesTurboQuant = $false
if ($state.PSObject.Properties["turboServerExe"] -and $state.turboServerExe) {
    try {
        $usesTurboQuant = ((Resolve-Path $serverExe).Path -eq (Resolve-Path $state.turboServerExe).Path)
    } catch {
        $usesTurboQuant = $false
    }
}

if (-not $usesTurboQuant) {
    $detectedGpuMiB = Get-DetectedGpuMemoryMiB

    if ($settings.llama.PSObject.Properties["gpuLayers"] -and $settings.llama.gpuLayers) {
        $gpuLayers = [int]$settings.llama.gpuLayers
    } elseif ($detectedGpuMiB) {
        if ($detectedGpuMiB -le 8192) {
            $gpuLayers = 10
            if (-not $contextCustomized) { $ctx = [math]::Min($ctx, 4096) }
            if (-not $outputCustomized) { $maxOutput = [math]::Min($maxOutput, 1024) }
        } elseif ($detectedGpuMiB -le 12288) {
            $gpuLayers = 20
            if (-not $contextCustomized) { $ctx = [math]::Min($ctx, 8192) }
            if (-not $outputCustomized) { $maxOutput = [math]::Min($maxOutput, 2048) }
        } else {
            $gpuLayers = 28
            if (-not $contextCustomized) { $ctx = [math]::Min($ctx, 16384) }
            if (-not $outputCustomized) { $maxOutput = [math]::Min($maxOutput, 4096) }
        }
    } else {
        $gpuLayers = 20
        if (-not $contextCustomized) { $ctx = [math]::Min($ctx, 8192) }
        if (-not $outputCustomized) { $maxOutput = [math]::Min($maxOutput, 2048) }
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

$deadline = (Get-Date).AddSeconds([Math]::Max(10, $WaitSeconds))
do {
    Start-Sleep -Seconds 3
    if (Test-LlamaHealth) {
        break
    }
} until ((Get-Date) -ge $deadline)

if (Test-LlamaHealth) {
    Write-Host "llama.cpp je pokrenut na http://127.0.0.1:$($state.port)"
    Write-Host "Profil: $Profile"
    Write-Host "Model: $modelPath"
} else {
    Write-Host "Pokretanje nije potvrđeno u roku od $WaitSeconds sekundi. Pogledaj log:"
    Write-Host $stderrLog
}
