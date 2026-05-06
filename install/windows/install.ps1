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
$desktopTargetDir = Join-Path $DesktopFolder "Local Qwen Home Computer"
$statePath = Join-Path $stateDir "install-state.json"

function Ensure-Dir {
    param([string]$Path)
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
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
    Invoke-Native winget install --id $WingetId --silent --accept-package-agreements --accept-source-agreements
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
    $asset = $release.assets | Where-Object { $_.name -match 'cudart-llama-bin-win-cuda-12\.4-x64\.zip' } | Select-Object -First 1

    if (-not $asset) {
        throw "Nisam nasao odgovarajuci Windows CUDA release asset za llama.cpp."
    }

    $zipPath = Join-Path $env:TEMP $asset.name
    Invoke-WebRequest -UseBasicParsing -Uri $asset.browser_download_url -OutFile $zipPath

    Ensure-Dir $DestinationDir
    Expand-Archive -LiteralPath $zipPath -DestinationPath $DestinationDir -Force
    Remove-Item -LiteralPath $zipPath -Force
}

function Download-RecommendedModel {
    param(
        [string]$RepoId,
        [string]$Filename,
        [string]$TargetPath
    )

    Ensure-Command -Name "py" -WingetId "Python.Python.3.12"
    Invoke-Native py -3 -m pip install --user -U huggingface_hub

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
    Invoke-Native py -3 $tmpPy
    Remove-Item -LiteralPath $tmpPy -Force
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

if (-not $SkipDependencies) {
    Ensure-Command -Name "git" -WingetId "Git.Git"
    Ensure-Command -Name "node" -WingetId "OpenJS.NodeJS.LTS"
    Ensure-Command -Name "npm" -WingetId "OpenJS.NodeJS.LTS"
    Ensure-Command -Name "py" -WingetId "Python.Python.3.12"
    Ensure-Command -Name "cmake" -WingetId "Kitware.CMake"
    Ensure-Command -Name "ninja" -WingetId "Ninja-build.Ninja"
}

Ensure-Dir $InstallRoot
Ensure-Dir $stateDir
Ensure-Dir $binDir
Ensure-Dir $appsDir
Ensure-Dir $modelsDir
Ensure-Dir $launchersDir
Ensure-Dir $configDir
Ensure-Dir $assetsDir
Ensure-Dir $desktopTargetDir

$upstreamDir = Join-Path $appsDir "llama.cpp"
$turboDir = Join-Path $appsDir "llama.cpp-turboquant"
$llamaBinDir = Join-Path $binDir "llama.cpp"

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

if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    throw "npm nije dostupan, pa OpenCode ne moze da se instalira."
}

if (-not (Get-Command opencode -ErrorAction SilentlyContinue)) {
    Invoke-Native npm install -g opencode-ai
}

$modelFile = Join-Path $modelsDir $defaults.modelChoices.recommendedWindows3060_12gb.filename
if ((-not $SkipModelDownload) -and !(Test-Path $modelFile)) {
    Download-RecommendedModel `
        -RepoId $defaults.modelChoices.recommendedWindows3060_12gb.source `
        -Filename $defaults.modelChoices.recommendedWindows3060_12gb.filename `
        -TargetPath $modelFile
}

Copy-FolderContent -Source (Join-Path $repoRoot "launcher\windows") -Destination $launchersDir
Copy-FolderContent -Source (Join-Path $repoRoot "assets\icons") -Destination (Join-Path $assetsDir "icons")
Copy-FolderContent -Source (Join-Path $repoRoot "config\profiles") -Destination (Join-Path $configDir "profiles")

$state = [ordered]@{
    installRoot = $InstallRoot
    desktopTargetDir = $desktopTargetDir
    upstreamDir = $upstreamDir
    turboDir = $turboDir
    llamaBinDir = $llamaBinDir
    modelFile = $modelFile
    modelId = $defaults.modelChoices.recommendedWindows3060_12gb.id
    defaultProfile = $Profile
    port = $defaults.service.port
    threads = $defaults.service.threads
    noMmap = $defaults.service.noMmap
    mlock = $defaults.service.mlock
    installedAt = (Get-Date).ToString("s")
}

$state | ConvertTo-Json -Depth 10 | Set-Content -Path $statePath -Encoding UTF8

$settings = [ordered]@{
    profile = $Profile
    llama = [ordered]@{
        contextSize = $defaults.profiles.$Profile.contextSize
        maxOutputTokens = 8192
    }
    opencode = [ordered]@{
        buildSteps = $defaults.opencode.steps.build
        planSteps = $defaults.opencode.steps.plan
        generalSteps = $defaults.opencode.steps.general
        exploreSteps = $defaults.opencode.steps.explore
    }
}
$settings | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $stateDir "settings.json") -Encoding UTF8

& powershell.exe -ExecutionPolicy Bypass -File (Join-Path $launchersDir "configure-settings.ps1") -Profile $Profile | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw "OpenCode konfiguracija nije uspesno upisana."
}

if (-not $SkipTurboQuantBuild) {
    & powershell.exe -ExecutionPolicy Bypass -File (Join-Path $launchersDir "build-turboquant.ps1")
    if ($LASTEXITCODE -ne 0) {
        throw "TurboQuant build nije uspeo."
    }
}

$controlCenterScript = Join-Path $launchersDir "control-center.ps1"
$controlCenterIcon = Join-Path $assetsDir "icons\control-center.ico"
$agentIcon = Join-Path $assetsDir "icons\agent-mode.ico"
$opencodeIcon = Join-Path $assetsDir "icons\opencode-local-qwen.ico"

New-Shortcut `
    -ShortcutPath (Join-Path $desktopTargetDir "Local Qwen Control Center.lnk") `
    -TargetPath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -Arguments "-ExecutionPolicy Bypass -File `"$controlCenterScript`"" `
    -WorkingDirectory $launchersDir `
    -IconLocation "$controlCenterIcon,0" `
    -Description "Control center for local Qwen + OpenCode"

New-Shortcut `
    -ShortcutPath (Join-Path $desktopTargetDir "OpenCode - Local Qwen.lnk") `
    -TargetPath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -Arguments "-ExecutionPolicy Bypass -File `"$($launchersDir)\start-opencode.ps1`"" `
    -WorkingDirectory $launchersDir `
    -IconLocation "$opencodeIcon,0" `
    -Description "Launch OpenCode wired to local Qwen"

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
"@

Set-Content -Path (Join-Path $stateDir "install-summary.txt") -Value $summary -Encoding UTF8
Write-Host $summary
