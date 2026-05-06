param(
    [switch]$Reconfigure
)

. (Join-Path $PSScriptRoot "local-qwen-common.ps1")

$state = Get-InstallState
$defaults = Get-Defaults

function Get-ToolPath {
    param([string]$Name)

    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $cmd) {
        throw "Potreban alat nije pronadjen u PATH-u: $Name"
    }
    return $cmd.Source
}

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(ValueFromRemainingArguments = $true)][string[]]$ArgumentList
    )

    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "Komanda nije uspela: $FilePath $($ArgumentList -join ' ')"
    }
}

function Import-VsBuildEnvironment {
    $vcvars = Get-ChildItem "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $vcvars) {
        throw "vcvars64.bat nije pronadjen. Visual Studio Build Tools 2022 nisu pravilno instalirani."
    }

    $dump = cmd.exe /c "`"$($vcvars.FullName)`" && set"
    foreach ($line in $dump) {
        if ($line -match '^(.*?)=(.*)$') {
            [Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process')
        }
    }
}

function Import-CudaEnvironment {
    $cudaBin = Get-ChildItem "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v*\bin" -Directory -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
    if (-not $cudaBin) {
        throw "CUDA Toolkit bin folder nije pronadjen."
    }

    $cudaRoot = Split-Path -Parent $cudaBin.FullName
    [Environment]::SetEnvironmentVariable("CUDA_PATH", $cudaRoot, "Process")
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "Process")
    if ($currentPath -notlike "*$($cudaBin.FullName)*") {
        [Environment]::SetEnvironmentVariable("PATH", "$($cudaBin.FullName);$currentPath", "Process")
    }
}

$cmake = Get-ToolPath "cmake"
$buildRoot = Join-Path $state.turboDir $defaults.turboquant.buildDir

Import-VsBuildEnvironment
Import-CudaEnvironment

if ($Reconfigure -and (Test-Path $buildRoot)) {
    Remove-Item -Recurse -Force $buildRoot
}

New-Item -ItemType Directory -Force -Path $buildRoot | Out-Null

Invoke-Native $cmake -S $state.turboDir -B $buildRoot -G $defaults.windowsBuild.cmakeGenerator -DGGML_CUDA=ON -DCMAKE_BUILD_TYPE=Release -DCMAKE_CUDA_ARCHITECTURES=$defaults.windowsBuild.cudaArch
Invoke-Native $cmake --build $buildRoot --config Release -j

$serverExe = Get-ChildItem -Path $buildRoot -Recurse -Filter "llama-server.exe" | Where-Object { $_.FullName -match '\\(bin|Release)\\' } | Select-Object -First 1
if (-not $serverExe) {
    throw "TurboQuant build nije proizveo llama-server.exe"
}

$binOut = $serverExe.Directory.FullName
foreach ($dllName in $defaults.turboquant.dllNames) {
    $src = Join-Path $state.llamaBinDir $dllName
    $dst = Join-Path $binOut $dllName
    if (Test-Path $src) {
        Copy-Item -LiteralPath $src -Destination $dst -Force
    }
}

$state.turboBuildDir = $buildRoot
$state.turboBinDir = $binOut
$state.turboServerExe = $serverExe.FullName
$state | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $state.installRoot "state\install-state.json") -Encoding UTF8

Write-Host "TurboQuant build zavrsen."
Write-Host "Server: $($serverExe.FullName)"
