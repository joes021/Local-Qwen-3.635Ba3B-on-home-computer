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

$cmake = Get-ToolPath "cmake"
$ninja = Get-ToolPath "ninja"
$buildRoot = Join-Path $state.turboDir $defaults.turboquant.buildDir
$binOut = Join-Path $buildRoot "bin"

if ($Reconfigure -and (Test-Path $buildRoot)) {
    Remove-Item -Recurse -Force $buildRoot
}

New-Item -ItemType Directory -Force -Path $buildRoot | Out-Null

Invoke-Native $cmake -S $state.turboDir -B $buildRoot -G $defaults.windowsBuild.cmakeGenerator -DGGML_CUDA=ON -DCMAKE_BUILD_TYPE=Release -DCMAKE_CUDA_ARCHITECTURES=$defaults.windowsBuild.cudaArch
Invoke-Native $cmake --build $buildRoot --config Release -j

foreach ($dllName in $defaults.turboquant.dllNames) {
    $src = Join-Path $state.llamaBinDir $dllName
    $dst = Join-Path $binOut $dllName
    if (Test-Path $src) {
        Copy-Item -LiteralPath $src -Destination $dst -Force
    }
}

$serverExe = Join-Path $binOut "llama-server.exe"
if (!(Test-Path $serverExe)) {
    throw "TurboQuant build nije proizveo llama-server.exe"
}

$state.turboBuildDir = $buildRoot
$state.turboBinDir = $binOut
$state.turboServerExe = $serverExe
$state | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $state.installRoot "state\install-state.json") -Encoding UTF8

Write-Host "TurboQuant build zavrsen."
Write-Host "Server: $serverExe"
