param(
    [string]$InstallRoot = "$env:USERPROFILE\LocalQwenHome",
    [string]$DesktopFolder = "$env:USERPROFILE\Desktop",
    [string]$Profile = "balanced",
    [switch]$SkipDependencies,
    [switch]$SkipLlamaDownload,
    [switch]$SkipTurboQuantBuild,
    [switch]$SkipModelDownload
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$defaultsPath = Join-Path $repoRoot "config\profiles\defaults.json"
$defaults = Get-Content -Raw $defaultsPath | ConvertFrom-Json

$stateDir = Join-Path $InstallRoot "state"
$binDir = Join-Path $InstallRoot "bin"
$appsDir = Join-Path $InstallRoot "apps"
$modelsDir = Join-Path $InstallRoot "models"
$launchersDir = Join-Path $InstallRoot "launchers"
$configDir = Join-Path $InstallRoot "config"
$assetsDir = Join-Path $InstallRoot "assets"
$docsDir = Join-Path $InstallRoot "docs"
$desktopTargetDir = Join-Path $DesktopFolder "Local Qwen Home Computer"
$statePath = Join-Path $stateDir "install-state.json"
$installReportPath = Join-Path $stateDir "install-report.json"

function Ensure-Dir {
    param([string]$Path)
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Test-WingetPackageInstalled {
    param([string]$WingetId)

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        return $false
    }

    $output = & winget list --id $WingetId --exact --accept-source-agreements 2>$null | Out-String
    return ($LASTEXITCODE -eq 0) -and ($output -match [regex]::Escape($WingetId))
}

function Resolve-PythonExecutableFromCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [string[]]$Arguments = @()
    )

    try {
        $output = & $Command @Arguments -c "import sys; print(sys.executable)" 2>$null
        if ($LASTEXITCODE -ne 0) {
            return $null
        }

        $resolved = [string]($output | Select-Object -Last 1)
        if (-not [string]::IsNullOrWhiteSpace($resolved) -and (Test-Path $resolved)) {
            return $resolved.Trim()
        }

        return $null
    } catch {
        return $null
    }
}

function Get-PythonLauncher {
    $commandCandidates = @(
        @{ Command = "py"; Arguments = @("-3") },
        @{ Command = "python"; Arguments = @() },
        @{ Command = "python3"; Arguments = @() }
    )

    foreach ($candidate in $commandCandidates) {
        if (Get-Command $candidate.Command -ErrorAction SilentlyContinue) {
            $resolved = Resolve-PythonExecutableFromCommand -Command $candidate.Command -Arguments $candidate.Arguments
            if ($resolved) {
                return [pscustomobject]@{
                    Command = $resolved
                    Arguments = @()
                }
            }
        }
    }

    $pathCandidates = @(
        "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
        "$env:ProgramFiles\Python312\python.exe",
        "${env:ProgramFiles(x86)}\Python312\python.exe"
    ) | Where-Object { $_ -and (Test-Path $_) }

    foreach ($path in $pathCandidates) {
        if (Resolve-PythonExecutableFromCommand -Command $path -Arguments @()) {
            return [pscustomobject]@{
                Command = $path
                Arguments = @()
            }
        }
    }

    return $null
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

function Ensure-Command {
    param(
        [string]$Name,
        [string]$WingetId
    )

    if (Get-Command $Name -ErrorAction SilentlyContinue) {
        return
    }

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "Komanda '$Name' nije pronadjena, a winget nije dostupan za automatsku instalaciju."
    }

    Write-Host "Instaliram $Name preko winget..." -ForegroundColor Cyan
    & winget install --id $WingetId --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        if ((Get-Command $Name -ErrorAction SilentlyContinue) -or (Test-WingetPackageInstalled -WingetId $WingetId)) {
            Write-Host "$Name je vec instaliran ili je dostupan nakon winget pokusaja." -ForegroundColor Yellow
            return
        }
        throw "Komanda nije uspela: winget install --id $WingetId --silent --accept-package-agreements --accept-source-agreements"
    }
}

function Ensure-PythonRuntime {
    $python = Get-PythonLauncher
    if ($python) {
        return $python
    }

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "Python nije pronadjen, a winget nije dostupan za automatsku instalaciju."
    }

    Write-Host "Instaliram Python 3.12 preko winget..." -ForegroundColor Cyan
    & winget install --id Python.Python.3.12 --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0 -and -not (Test-WingetPackageInstalled -WingetId "Python.Python.3.12")) {
        throw "Python instalacija preko winget nije uspela."
    }

    $python = Get-PythonLauncher
    if (-not $python) {
        throw "Python deluje instaliran, ali py/python jos nije dostupan u ovoj sesiji. Otvori novi PowerShell i pokreni installer ponovo sa -SkipDependencies."
    }

    return $python
}

function Invoke-RuntimeHelperJson {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $python = Ensure-PythonRuntime
    $scriptPath = Join-Path $repoRoot "scripts\local_qwen_runtime.py"
    $output = & $python.Command @($python.Arguments + @($scriptPath) + $Arguments)
    if ($LASTEXITCODE -ne 0) {
        throw "Shared runtime helper nije uspeo: $($Arguments -join ' ')"
    }
    return ($output | Out-String | ConvertFrom-Json)
}

function Get-DetectedGpuMemoryMiB {
    try {
        $controllers = Get-CimInstance Win32_VideoController -ErrorAction Stop | Where-Object { $_.AdapterRAM -gt 0 }
        if (-not $controllers) {
            return 0
        }
        return [int]([math]::Round((($controllers | Measure-Object -Property AdapterRAM -Maximum).Maximum) / 1MB))
    } catch {
        return 0
    }
}

function Get-SystemMemoryGiB {
    try {
        $computer = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        return [int]([math]::Round($computer.TotalPhysicalMemory / 1GB))
    } catch {
        return 0
    }
}

function Get-RecommendedModelChoice {
    $payload = Invoke-RuntimeHelperJson -Arguments @(
        "recommend",
        "--defaults", $defaultsPath,
        "--gpu-mib", ([string](Get-DetectedGpuMemoryMiB)),
        "--ram-gib", ([string](Get-SystemMemoryGiB)),
        "--cpu-threads", ([string][Environment]::ProcessorCount)
    )
    $recommendedId = [string]$payload.recommendedModel.id
    foreach ($property in $defaults.modelChoices.PSObject.Properties) {
        if ($property.Value.id -eq $recommendedId) {
            return $property.Value
        }
    }
    return $defaults.modelChoices.iq2_m_compact
}

function Ensure-VsBuildTools {
    $vcvars = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
    if (Test-Path $vcvars) {
        return
    }

    Write-Host "Instaliram Visual Studio Build Tools 2022..." -ForegroundColor Cyan
    Invoke-Native winget install --id Microsoft.VisualStudio.2022.BuildTools --silent --accept-package-agreements --accept-source-agreements --override "--wait --quiet --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
}

function Ensure-CudaToolkit {
    if (Get-Command nvcc -ErrorAction SilentlyContinue) {
        return
    }

    $cudaDir = Get-ChildItem "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cudaDir) {
        return
    }

    Write-Host "Instaliram NVIDIA CUDA Toolkit..." -ForegroundColor Cyan
    Invoke-Native winget install --id Nvidia.CUDA --silent --accept-package-agreements --accept-source-agreements
}

function Copy-FolderContent {
    param(
        [string]$Source,
        [string]$Destination
    )

    Ensure-Dir $Destination
    Copy-Item -Path (Join-Path $Source "*") -Destination $Destination -Recurse -Force
}

function Download-LlamaCppWindowsCuda {
    param([string]$DestinationDir)

    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/ggml-org/llama.cpp/releases/latest"
    $asset = $release.assets | Where-Object { $_.name -match '^llama-.*-bin-win-cuda-12\.4-x64\.zip$' } | Select-Object -First 1

    if (-not $asset) {
        $asset = $release.assets | Where-Object { $_.name -match '^llama-.*-bin-win-cuda-13\.1-x64\.zip$' } | Select-Object -First 1
    }

    if (-not $asset) {
        throw "Nisam nasao odgovarajuci kompletan Windows CUDA release asset za llama.cpp."
    }

    $zipPath = Join-Path $env:TEMP $asset.name
    Invoke-WebRequest -UseBasicParsing -Uri $asset.browser_download_url -OutFile $zipPath

    Ensure-Dir $DestinationDir
    Expand-Archive -LiteralPath $zipPath -DestinationPath $DestinationDir -Force
    Remove-Item -LiteralPath $zipPath -Force
    Get-ChildItem -LiteralPath $DestinationDir -Recurse -File | Unblock-File -ErrorAction SilentlyContinue

    if (-not (Test-Path (Join-Path $DestinationDir "llama-server.exe"))) {
        throw "llama.cpp ZIP je raspakovan, ali llama-server.exe nije pronadjen u $DestinationDir"
    }
}

function Test-LlamaBinaryRunnable {
    param([Parameter(Mandatory = $true)][string]$ServerExe)

    try {
        & $ServerExe --version *> $null
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

function Download-RecommendedModel {
    param(
        [string]$RepoId,
        [string]$Filename,
        [string]$TargetPath,
        [Int64]$MinExpectedBytes = 0
    )

    $python = Ensure-PythonRuntime
    & $python.Command @($python.Arguments + @("-m", "pip", "install", "--user", "-U", "huggingface_hub"))
    if ($LASTEXITCODE -ne 0) {
        throw "Komanda nije uspela: $($python.Command) -m pip install --user -U huggingface_hub"
    }

    $targetDir = Split-Path -Parent $TargetPath
    Ensure-Dir $targetDir

    $pyCode = @"
from huggingface_hub import hf_hub_download
hf_hub_download(
    repo_id=r"$RepoId",
    filename=r"$Filename",
    local_dir=r"$targetDir",
    local_dir_use_symlinks=False,
)
"@

    $tmpPy = Join-Path $env:TEMP "local_qwen_hf_download.py"
    Set-Content -Path $tmpPy -Value $pyCode -Encoding UTF8
    & $python.Command @($python.Arguments + @($tmpPy))
    if ($LASTEXITCODE -ne 0) {
        throw "Komanda nije uspela: $($python.Command) $tmpPy"
    }
    Remove-Item -LiteralPath $tmpPy -Force

    if (!(Test-Path $TargetPath)) {
        throw "Model download nije proizveo ocekivani fajl: $TargetPath"
    }

    if ($MinExpectedBytes -gt 0) {
        $downloadedSize = (Get-Item $TargetPath).Length
        if ($downloadedSize -lt $MinExpectedBytes) {
            throw "Model je skinut nepotpuno: $TargetPath ($downloadedSize bajtova, ocekivano najmanje $MinExpectedBytes)"
        }
    }
}

function Write-InstallState {
    param(
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [Parameter(Mandatory = $true)][string]$DesktopTargetDir,
        [Parameter(Mandatory = $true)][string]$UpstreamDir,
        [Parameter(Mandatory = $true)][string]$TurboDir,
        [Parameter(Mandatory = $true)][string]$LlamaBinDir,
        [Parameter(Mandatory = $true)][string]$ModelFile,
        [Parameter(Mandatory = $true)][string]$ModelId,
        [Parameter(Mandatory = $true)][string]$Profile,
        [Parameter(Mandatory = $true)][string]$StatePath,
        [Parameter(Mandatory = $true)]$Defaults,
        [string]$TurboServerExe
    )

    $state = [ordered]@{
        installRoot = $InstallRoot
        desktopTargetDir = $DesktopTargetDir
        upstreamDir = $UpstreamDir
        turboDir = $TurboDir
        llamaBinDir = $LlamaBinDir
        modelFile = $ModelFile
        modelId = $ModelId
        defaultProfile = $Profile
        port = $Defaults.service.port
        threads = $Defaults.service.threads
        noMmap = $Defaults.service.noMmap
        mlock = $Defaults.service.mlock
        installedAt = (Get-Date).ToString("s")
    }

    if ($TurboServerExe) {
        $state.turboServerExe = $TurboServerExe
    }

    $state | ConvertTo-Json -Depth 10 | Set-Content -Path $StatePath -Encoding UTF8
}

function Write-InstallReport {
    param(
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [Parameter(Mandatory = $true)][string]$InstallRootStatePath,
        [Parameter(Mandatory = $true)][string]$InstallReportPath,
        [Parameter(Mandatory = $true)][string]$ModelFile,
        [Parameter(Mandatory = $true)][string]$LlamaBinDir,
        [Parameter(Mandatory = $true)][string]$TurboDir,
        [Parameter(Mandatory = $true)][string]$LaunchersDir,
        [Parameter(Mandatory = $true)][string]$DesktopTargetDir,
        [Parameter(Mandatory = $true)][string]$Profile,
        [Parameter(Mandatory = $true)]$Warnings
    )

    $llamaServerPath = Join-Path $LlamaBinDir "llama-server.exe"
    $turboServerPath = Join-Path $TurboDir "$($defaults.turboquant.buildDir)\bin\llama-server.exe"
    $configPath = Join-Path $env:USERPROFILE ".config\opencode\opencode.json"

    $report = [ordered]@{
        generatedAt = (Get-Date).ToString("s")
        platform = "windows"
        profile = $Profile
        installRoot = $InstallRoot
        components = [ordered]@{
            installState = [ordered]@{
                path = $InstallRootStatePath
                ok = (Test-Path $InstallRootStatePath)
            }
            launchers = [ordered]@{
                path = $LaunchersDir
                ok = (Test-Path (Join-Path $LaunchersDir "control-center.ps1"))
            }
            desktopShortcuts = [ordered]@{
                path = $DesktopTargetDir
                ok = (Test-Path (Join-Path $DesktopTargetDir "Local Qwen Control Center.lnk"))
            }
            llamaCppRuntime = [ordered]@{
                path = $llamaServerPath
                ok = (Test-Path $llamaServerPath)
            }
            turboQuantRuntime = [ordered]@{
                path = $turboServerPath
                ok = (Test-Path $turboServerPath)
            }
            model = [ordered]@{
                path = $ModelFile
                ok = (Test-Path $ModelFile)
                sizeBytes = if (Test-Path $ModelFile) { (Get-Item $ModelFile).Length } else { 0 }
            }
            opencodeConfig = [ordered]@{
                path = $configPath
                ok = (Test-Path $configPath)
            }
        }
        warnings = @($Warnings)
    }

    $report | ConvertTo-Json -Depth 10 | Set-Content -Path $InstallReportPath -Encoding UTF8
}

function New-Shortcut {
    param(
        [string]$ShortcutPath,
        [string]$TargetPath,
        [string]$Arguments,
        [string]$WorkingDirectory,
        [string]$IconLocation,
        [string]$Description
    )

    $wsh = New-Object -ComObject WScript.Shell
    $shortcut = $wsh.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $TargetPath
    $shortcut.Arguments = $Arguments
    $shortcut.WorkingDirectory = $WorkingDirectory
    if ($IconLocation) {
        $shortcut.IconLocation = $IconLocation
    }
    if ($Description) {
        $shortcut.Description = $Description
    }
    $shortcut.Save()
}

function Write-CmdLauncher {
    param(
        [Parameter(Mandatory = $true)][string]$LaunchersDir,
        [Parameter(Mandatory = $true)][string]$CmdName,
        [Parameter(Mandatory = $true)][string]$PsScriptName,
        [string]$ExtraArguments = ""
    )

    $cmdPath = Join-Path $LaunchersDir $CmdName
    $content = @"
@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%$PsScriptName"

if not exist "%PS_SCRIPT%" (
  echo Launcher script not found: %PS_SCRIPT%
  pause
  exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" $ExtraArguments
set "EXITCODE=%ERRORLEVEL%"
if not "%EXITCODE%"=="0" (
  echo.
  echo Launcher failed with exit code %EXITCODE%.
  echo.
  pause
)
exit /b %EXITCODE%
"@

    Set-Content -Path $cmdPath -Value $content -Encoding ASCII
    return $cmdPath
}

function Write-HiddenVbsLauncher {
    param(
        [Parameter(Mandatory = $true)][string]$LaunchersDir,
        [Parameter(Mandatory = $true)][string]$VbsName,
        [Parameter(Mandatory = $true)][string]$PsScriptName,
        [string]$ExtraArguments = ""
    )

    $vbsPath = Join-Path $LaunchersDir $VbsName
    $escapedScriptName = $PsScriptName.Replace('"', '""')
    $escapedExtraArguments = $ExtraArguments.Replace('"', '""')
    $content = @"
Dim shell, scriptDir, psScript, command
Set shell = CreateObject("WScript.Shell")
scriptDir = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
psScript = scriptDir & "\$escapedScriptName"
command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & psScript & """ $escapedExtraArguments"
shell.Run command, 0, False
"@

    Set-Content -Path $vbsPath -Value $content -Encoding ASCII
    return $vbsPath
}

function Write-DesktopShortcuts {
    param(
        [Parameter(Mandatory = $true)][string]$LaunchersDir,
        [Parameter(Mandatory = $true)][string]$AssetsDir,
        [Parameter(Mandatory = $true)][string]$DesktopTargetDir
    )

    Ensure-Dir $DesktopTargetDir

    $controlCenterIcon = Join-Path $AssetsDir "icons\control-center.ico"
    $opencodeIcon = Join-Path $AssetsDir "icons\opencode-local-qwen.ico"
    $controlCenterVbs = Write-HiddenVbsLauncher -LaunchersDir $LaunchersDir -VbsName "open-control-center.vbs" -PsScriptName "control-center.ps1"
    $openCodeCmd = Write-CmdLauncher -LaunchersDir $LaunchersDir -CmdName "open-opencode.cmd" -PsScriptName "start-opencode.ps1"
    $verifyCmd = Write-CmdLauncher -LaunchersDir $LaunchersDir -CmdName "verify-install.cmd" -PsScriptName "verify-install.ps1"
    $repairCmd = Write-CmdLauncher -LaunchersDir $LaunchersDir -CmdName "repair-app-control.cmd" -PsScriptName "repair-app-control.ps1"

    New-Shortcut `
        -ShortcutPath (Join-Path $DesktopTargetDir "Local Qwen Control Center.lnk") `
        -TargetPath "wscript.exe" `
        -Arguments "`"$controlCenterVbs`"" `
        -WorkingDirectory $LaunchersDir `
        -IconLocation "$controlCenterIcon,0" `
        -Description "Control center for local Qwen + OpenCode"

    New-Shortcut `
        -ShortcutPath (Join-Path $DesktopTargetDir "OpenCode - Local Qwen.lnk") `
        -TargetPath $env:ComSpec `
        -Arguments "/c `"$openCodeCmd`"" `
        -WorkingDirectory $LaunchersDir `
        -IconLocation "$opencodeIcon,0" `
        -Description "Launch OpenCode wired to local Qwen"

    New-Shortcut `
        -ShortcutPath (Join-Path $DesktopTargetDir "Verify Local Qwen Install.lnk") `
        -TargetPath $env:ComSpec `
        -Arguments "/c `"$verifyCmd`"" `
        -WorkingDirectory $LaunchersDir `
        -IconLocation "$controlCenterIcon,0" `
        -Description "Verify local Qwen installation"

    New-Shortcut `
        -ShortcutPath (Join-Path $DesktopTargetDir "Repair Windows App Control.lnk") `
        -TargetPath $env:ComSpec `
        -Arguments "/c `"$repairCmd`"" `
        -WorkingDirectory $LaunchersDir `
        -IconLocation "$controlCenterIcon,0" `
        -Description "Inspect or repair Smart App Control / App Control issues"
}

if (-not $SkipDependencies) {
    Ensure-Command -Name "git" -WingetId "Git.Git"
    Ensure-Command -Name "node" -WingetId "OpenJS.NodeJS.LTS"
    Ensure-Command -Name "npm" -WingetId "OpenJS.NodeJS.LTS"
    [void](Ensure-PythonRuntime)
    Ensure-Command -Name "cmake" -WingetId "Kitware.CMake"
    Ensure-Command -Name "ninja" -WingetId "Ninja-build.Ninja"
    Ensure-VsBuildTools
    Ensure-CudaToolkit
}

Ensure-Dir $InstallRoot
Ensure-Dir $stateDir
Ensure-Dir $binDir
Ensure-Dir $appsDir
Ensure-Dir $modelsDir
Ensure-Dir $launchersDir
Ensure-Dir $configDir
Ensure-Dir $assetsDir
Ensure-Dir $docsDir
Ensure-Dir $desktopTargetDir

$upstreamDir = Join-Path $appsDir "llama.cpp"
$turboDir = Join-Path $appsDir "llama.cpp-turboquant"
$llamaBinDir = Join-Path $binDir "llama.cpp"
$modelChoice = Get-RecommendedModelChoice
$modelFile = Join-Path $modelsDir $modelChoice.filename
$warnings = New-Object System.Collections.Generic.List[string]

Copy-FolderContent -Source (Join-Path $repoRoot "launcher\windows") -Destination $launchersDir
Copy-FolderContent -Source (Join-Path $repoRoot "assets\icons") -Destination (Join-Path $assetsDir "icons")
Copy-FolderContent -Source (Join-Path $repoRoot "config\profiles") -Destination (Join-Path $configDir "profiles")
Copy-Item -LiteralPath (Join-Path $repoRoot "version.json") -Destination (Join-Path $InstallRoot "version.json") -Force
Copy-Item -LiteralPath (Join-Path $repoRoot "release-notes.txt") -Destination (Join-Path $InstallRoot "release-notes.txt") -Force
Copy-Item -LiteralPath (Join-Path $repoRoot "release-notes.txt") -Destination (Join-Path $docsDir "release-notes.txt") -Force

foreach ($stalePath in @(
    (Join-Path $launchersDir "version.json"),
    (Join-Path $launchersDir "release-notes.txt")
)) {
    if (Test-Path $stalePath) {
        Remove-Item -LiteralPath $stalePath -Force -ErrorAction SilentlyContinue
    }
}

Write-InstallState `
    -InstallRoot $InstallRoot `
    -DesktopTargetDir $desktopTargetDir `
    -UpstreamDir $upstreamDir `
    -TurboDir $turboDir `
    -LlamaBinDir $llamaBinDir `
    -ModelFile $modelFile `
    -ModelId $modelChoice.id `
    -Profile $Profile `
    -StatePath $statePath `
    -Defaults $defaults

Write-DesktopShortcuts -LaunchersDir $launchersDir -AssetsDir $assetsDir -DesktopTargetDir $desktopTargetDir

if (!(Test-Path $upstreamDir)) {
    Invoke-Native git clone https://github.com/ggml-org/llama.cpp.git $upstreamDir
}

if (!(Test-Path $turboDir)) {
    Invoke-Native git clone $defaults.turboquant.repo $turboDir
    Invoke-Native git -C $turboDir checkout $defaults.turboquant.branch
}

if ((-not $SkipLlamaDownload) -and !(Test-Path (Join-Path $llamaBinDir "llama-server.exe"))) {
    Download-LlamaCppWindowsCuda -DestinationDir $llamaBinDir
}

$upstreamServerExe = Join-Path $llamaBinDir "llama-server.exe"
if (Test-Path $upstreamServerExe) {
    if (-not (Test-LlamaBinaryRunnable -ServerExe $upstreamServerExe)) {
        $warnings.Add("Windows je blokirao pokretanje llama-server.exe. Moguca je Application Control / WDAC politika na masini. Ako prečice postoje ali server ne kreće, proveri da li sistem dozvoljava lokalne unsigned exe fajlove.") | Out-Null
    }
}

if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    throw "npm nije dostupan, pa OpenCode ne moze da se instalira."
}

if (-not (Get-Command opencode -ErrorAction SilentlyContinue)) {
    Invoke-Native npm install -g opencode-ai
}

if ((-not $SkipModelDownload) -and ((!(Test-Path $modelFile)) -or ((Get-Item $modelFile -ErrorAction SilentlyContinue).Length -lt [int64]$modelChoice.minExpectedBytes))) {
    Download-RecommendedModel `
        -RepoId $modelChoice.source `
        -Filename $modelChoice.filename `
        -TargetPath $modelFile `
        -MinExpectedBytes ([int64]$modelChoice.minExpectedBytes)
}

$settings = [ordered]@{
    profile = $Profile
    llama = [ordered]@{
        contextSize = $defaults.profiles.$Profile.contextSize
        maxOutputTokens = 8192
        contextSizeCustomized = $false
        maxOutputTokensCustomized = $false
    }
    opencode = [ordered]@{
        buildSteps = $defaults.opencode.steps.build
        planSteps = $defaults.opencode.steps.plan
        generalSteps = $defaults.opencode.steps.general
        exploreSteps = $defaults.opencode.steps.explore
    }
}
$settings | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $stateDir "settings.json") -Encoding UTF8

Write-InstallState `
    -InstallRoot $InstallRoot `
    -DesktopTargetDir $desktopTargetDir `
    -UpstreamDir $upstreamDir `
    -TurboDir $turboDir `
    -LlamaBinDir $llamaBinDir `
    -ModelFile $modelFile `
    -ModelId $modelChoice.id `
    -Profile $Profile `
    -StatePath $statePath `
    -Defaults $defaults

& powershell.exe -ExecutionPolicy Bypass -File (Join-Path $launchersDir "configure-settings.ps1") -Profile $Profile | Out-Host
if ($LASTEXITCODE -ne 0) {
    $warnings.Add("OpenCode konfiguracija nije uspesno upisana tokom install toka. Pokreni configure-settings.ps1 ili Verify Local Qwen Install nakon instalacije.") | Out-Null
}

if (-not $SkipTurboQuantBuild) {
    & powershell.exe -ExecutionPolicy Bypass -File (Join-Path $launchersDir "build-turboquant.ps1")
    if ($LASTEXITCODE -ne 0) {
        $warnings.Add("TurboQuant build nije uspeo. Instalacija ostaje upotrebljiva kroz upstream llama.cpp fallback.") | Out-Null
    }
}

$turboServerExe = Join-Path $turboDir "$($defaults.turboquant.buildDir)\bin\llama-server.exe"
Write-InstallState `
    -InstallRoot $InstallRoot `
    -DesktopTargetDir $desktopTargetDir `
    -UpstreamDir $upstreamDir `
    -TurboDir $turboDir `
    -LlamaBinDir $llamaBinDir `
    -ModelFile $modelFile `
    -ModelId $modelChoice.id `
    -Profile $Profile `
    -StatePath $statePath `
    -Defaults $defaults `
    -TurboServerExe $(if (Test-Path $turboServerExe) { $turboServerExe } else { $null })

Write-InstallReport `
    -InstallRoot $InstallRoot `
    -InstallRootStatePath $statePath `
    -InstallReportPath $installReportPath `
    -ModelFile $modelFile `
    -LlamaBinDir $llamaBinDir `
    -TurboDir $turboDir `
    -LaunchersDir $launchersDir `
    -DesktopTargetDir $desktopTargetDir `
    -Profile $Profile `
    -Warnings $warnings

$summary = @"
Windows install state written to:
$statePath

OpenCode global install:
$(if (Get-Command opencode -ErrorAction SilentlyContinue) { 'OK' } else { 'NOT FOUND' })

Desktop launchers:
$desktopTargetDir

Installed launcher root:
$launchersDir

Model path:
$modelFile

Install report:
$installReportPath
"@

if ($warnings.Count -gt 0) {
    $summary += "`r`nWarnings:`r`n- " + ($warnings -join "`r`n- ")
}

Set-Content -Path (Join-Path $stateDir "install-summary.txt") -Value $summary -Encoding UTF8
Write-Host $summary
