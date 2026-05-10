param(
    [switch]$Reconfigure
)

. (Join-Path $PSScriptRoot "local-qwen-common.ps1")

$state = Get-InstallState
$defaults = Get-Defaults

function Get-ToolPath {
    param([string]$Name)

    $localCandidates = @()
    switch ($Name.ToLowerInvariant()) {
        "ninja" {
            $localCandidates += (Join-Path $state.installRoot "tools\ninja\ninja.exe")
        }
        "cmake" {
            $localCandidates += (Join-Path $state.installRoot "tools\cmake\bin\cmake.exe")
        }
    }

    foreach ($candidate in $localCandidates) {
        if ($candidate -and (Test-Path $candidate)) {
            return $candidate
        }
    }

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

function Stop-RunningLlamaServerProcesses {
    $processes = @(Get-Process llama-server -ErrorAction SilentlyContinue)
    if ($processes.Count -eq 0) {
        return
    }

    Write-Host "Zaustavljam aktivne llama-server procese pre TurboQuant build-a..." -ForegroundColor Yellow
    $processes | Stop-Process -Force -ErrorAction SilentlyContinue

    $deadline = (Get-Date).AddSeconds(15)
    do {
        Start-Sleep -Milliseconds 500
        $remaining = @(Get-Process llama-server -ErrorAction SilentlyContinue)
    } until ($remaining.Count -eq 0 -or (Get-Date) -ge $deadline)

    if ($remaining.Count -gt 0) {
        throw "Nisam uspeo da zaustavim sve llama-server procese pre TurboQuant build-a."
    }
}

function Set-StatePropertyValue {
    param(
        [Parameter(Mandatory = $true)]$StateObject,
        [Parameter(Mandatory = $true)][string]$Name,
        $Value
    )

    if ($StateObject.PSObject.Properties[$Name]) {
        $StateObject.PSObject.Properties[$Name].Value = $Value
    } else {
        $StateObject | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
    }
}

function Import-VsBuildEnvironment {
    $devCmd = Get-ChildItem "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat" -ErrorAction SilentlyContinue | Select-Object -First 1
    $envCommand = $null
    if ($devCmd) {
        $envCommand = "`"$($devCmd.FullName)`" -arch=x64 -host_arch=x64"
    } else {
        $vcvars = Get-ChildItem "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($vcvars) {
            $envCommand = "`"$($vcvars.FullName)`""
        }
    }

    if (-not $envCommand) {
        throw "Visual Studio Build Tools 2022 nisu pravilno instalirani."
    }

    $dump = cmd.exe /c "$envCommand && set"
    foreach ($line in $dump) {
        if ($line -match '^(.*?)=(.*)$') {
            [Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process')
        }
    }
}

function Add-ToProcessPath {
    param([string]$PathEntry)

    if (-not $PathEntry -or -not (Test-Path $PathEntry)) {
        return
    }

    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "Process")
    if ($currentPath -notlike "*$PathEntry*") {
        [Environment]::SetEnvironmentVariable("PATH", "$PathEntry;$currentPath", "Process")
    }
}

function Add-ToProcessVariablePath {
    param(
        [Parameter(Mandatory = $true)][string]$VariableName,
        [string]$PathEntry
    )

    if (-not $PathEntry -or -not (Test-Path $PathEntry)) {
        return
    }

    $currentValue = [Environment]::GetEnvironmentVariable($VariableName, "Process")
    if ([string]::IsNullOrWhiteSpace($currentValue)) {
        [Environment]::SetEnvironmentVariable($VariableName, $PathEntry, "Process")
        return
    }

    if ($currentValue -notlike "*$PathEntry*") {
        [Environment]::SetEnvironmentVariable($VariableName, "$PathEntry;$currentValue", "Process")
    }
}

function Get-WindowsSdkInfo {
    $sdkRoot = "C:\Program Files (x86)\Windows Kits\10"
    if (-not (Test-Path $sdkRoot)) {
        return $null
    }

    $versionDir = Get-ChildItem (Join-Path $sdkRoot "Lib") -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        Select-Object -First 1
    if (-not $versionDir) {
        return $null
    }

    $version = $versionDir.Name
    $binDir = Join-Path $sdkRoot "bin\$version\x64"
    $includeRoot = Join-Path $sdkRoot "Include\$version"
    $libRoot = Join-Path $sdkRoot "Lib\$version"

    return [pscustomobject]@{
        Root = $sdkRoot
        Version = $version
        BinDir = $binDir
        IncludeRoot = $includeRoot
        LibRoot = $libRoot
    }
}

function Get-WindowsSdkBinDirectory {
    $sdk = Get-WindowsSdkInfo
    if ($sdk -and (Test-Path (Join-Path $sdk.BinDir "rc.exe"))) {
        return $sdk.BinDir
    }
    return $null
}

function Ensure-WindowsSdkEnvironment {
    $sdk = Get-WindowsSdkInfo
    if (-not $sdk) {
        return
    }

    [Environment]::SetEnvironmentVariable("WindowsSdkDir", ($sdk.Root + "\"), "Process")
    [Environment]::SetEnvironmentVariable("WindowsSDKVersion", ($sdk.Version + "\"), "Process")
    [Environment]::SetEnvironmentVariable("UCRTVersion", $sdk.Version, "Process")
    [Environment]::SetEnvironmentVariable("UniversalCRTSdkDir", ($sdk.Root + "\"), "Process")

    Add-ToProcessPath $sdk.BinDir
    foreach ($includeLeaf in @("ucrt", "shared", "um", "winrt", "cppwinrt")) {
        Add-ToProcessVariablePath -VariableName "INCLUDE" -PathEntry (Join-Path $sdk.IncludeRoot $includeLeaf)
    }
    foreach ($libLeaf in @("ucrt\\x64", "um\\x64")) {
        Add-ToProcessVariablePath -VariableName "LIB" -PathEntry (Join-Path $sdk.LibRoot $libLeaf)
    }
}

function Get-PreferredCmakeGenerator {
    $ninja = Get-ToolPath "ninja"
    if ($ninja) {
        return "Ninja"
    }
    return [string]$defaults.windowsBuild.cmakeGenerator
}

function Get-BuildCacheGenerator {
    param([Parameter(Mandatory = $true)][string]$BuildRoot)

    $cachePath = Join-Path $BuildRoot "CMakeCache.txt"
    if (-not (Test-Path $cachePath)) {
        return $null
    }

    try {
        $line = Get-Content $cachePath | Where-Object { $_ -match '^CMAKE_GENERATOR(:INTERNAL)?=' } | Select-Object -First 1
        if ($line) {
            return ([string]$line -split '=', 2)[1].Trim()
        }
    } catch {
    }

    return $null
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
$ninja = Get-ToolPath "ninja"
$buildRoot = Join-Path $state.turboDir $defaults.turboquant.buildDir

Stop-RunningLlamaServerProcesses

$originalPath = [Environment]::GetEnvironmentVariable("PATH", "Process")
$currentPath = $originalPath
foreach ($toolDir in @((Split-Path -Parent $cmake), (Split-Path -Parent $ninja))) {
    if ($toolDir -and (Test-Path $toolDir) -and ($currentPath -notlike "*$toolDir*")) {
        $currentPath = "$toolDir;$currentPath"
    }
}
[Environment]::SetEnvironmentVariable("PATH", $currentPath, "Process")

Import-VsBuildEnvironment
Import-CudaEnvironment
Ensure-WindowsSdkEnvironment
Add-ToProcessPath "$env:SystemRoot\System32"
Add-ToProcessPath "$env:SystemRoot\System32\Wbem"
Add-ToProcessPath (Split-Path -Parent $cmake)
Add-ToProcessPath (Split-Path -Parent $ninja)
Add-ToProcessPath (Get-WindowsSdkBinDirectory)

if ($originalPath) {
    foreach ($entry in ($originalPath -split ';')) {
        Add-ToProcessPath $entry
    }
}

if (-not (Get-Command rc.exe -ErrorAction SilentlyContinue) -or -not (Get-Command mt.exe -ErrorAction SilentlyContinue)) {
    throw "Windows SDK build alati (rc.exe i/ili mt.exe) nisu dostupni iz Visual Studio Build Tools okruzenja."
}

$generator = Get-PreferredCmakeGenerator
$existingGenerator = Get-BuildCacheGenerator -BuildRoot $buildRoot
if ((Test-Path $buildRoot) -and $existingGenerator -and ($existingGenerator -ne $generator)) {
    Write-Host "Postojeci TurboQuant build cache koristi generator '$existingGenerator'; cistim build dir za '$generator'." -ForegroundColor Yellow
    Remove-Item -Recurse -Force $buildRoot
}

if ($Reconfigure -and (Test-Path $buildRoot)) {
    Remove-Item -Recurse -Force $buildRoot
}

New-Item -ItemType Directory -Force -Path $buildRoot | Out-Null

Invoke-Native $cmake -S $state.turboDir -B $buildRoot -G $generator -DGGML_CUDA=ON -DCMAKE_BUILD_TYPE=Release "-DCMAKE_CUDA_ARCHITECTURES=$($defaults.windowsBuild.cudaArch)"
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

Set-StatePropertyValue -StateObject $state -Name "turboBuildDir" -Value $buildRoot
Set-StatePropertyValue -StateObject $state -Name "turboBinDir" -Value $binOut
Set-StatePropertyValue -StateObject $state -Name "turboServerExe" -Value $serverExe.FullName
Write-Utf8NoBomText -Path (Join-Path $state.installRoot "state\install-state.json") -Content ($state | ConvertTo-Json -Depth 10)

Write-Host "TurboQuant build zavrsen."
Write-Host "Server: $($serverExe.FullName)"
