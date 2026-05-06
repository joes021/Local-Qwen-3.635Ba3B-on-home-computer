param(
    [string]$InstallRoot = "$env:USERPROFILE\LocalQwenHome",
    [string]$DesktopFolder = "$env:USERPROFILE\Desktop",
    [string]$Profile = "balanced",
    [switch]$SkipDependencies,
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
$desktopTargetDir = Join-Path $DesktopFolder "Local Qwen Home Computer"
$statePath = Join-Path $stateDir "install-state.json"

function Ensure-Dir {
    param([string]$Path)
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
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
    winget install --id $WingetId --silent --accept-package-agreements --accept-source-agreements
}

if (-not $SkipDependencies) {
    Ensure-Command -Name "git" -WingetId "Git.Git"
    Ensure-Command -Name "node" -WingetId "OpenJS.NodeJS.LTS"
    Ensure-Command -Name "npm" -WingetId "OpenJS.NodeJS.LTS"
}

Ensure-Dir $InstallRoot
Ensure-Dir $stateDir
Ensure-Dir $binDir
Ensure-Dir $appsDir
Ensure-Dir $modelsDir
Ensure-Dir $launchersDir
Ensure-Dir $desktopTargetDir

$upstreamDir = Join-Path $appsDir "llama.cpp"
$turboDir = Join-Path $appsDir "llama.cpp-turboquant"

if (!(Test-Path $upstreamDir)) {
    git clone https://github.com/ggml-org/llama.cpp.git $upstreamDir
}

if (!(Test-Path $turboDir)) {
    git clone https://github.com/turboderp-org/llama.cpp.git $turboDir
}

if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    throw "npm nije dostupan, pa OpenCode ne moze da se instalira."
}

if (-not (Get-Command opencode -ErrorAction SilentlyContinue)) {
    npm install -g opencode-ai
}

$modelFile = Join-Path $modelsDir $defaults.modelChoices.recommendedWindows3060_12gb.filename
if ((-not $SkipModelDownload) -and !(Test-Path $modelFile)) {
    $downloadNote = @"
Model download nije jos potpuno automatizovan u ovoj prvoj javnoj verziji.

Predvidjeno odrediste:
$modelFile

Preporuceni model:
$($defaults.modelChoices.recommendedWindows3060_12gb.source) / $($defaults.modelChoices.recommendedWindows3060_12gb.filename)
"@
    Set-Content -Path (Join-Path $stateDir "model-download-next-step.txt") -Value $downloadNote -Encoding UTF8
}

$state = [ordered]@{
    installRoot = $InstallRoot
    desktopTargetDir = $desktopTargetDir
    upstreamDir = $upstreamDir
    turboDir = $turboDir
    modelFile = $modelFile
    defaultProfile = $Profile
    port = $defaults.service.port
    threads = $defaults.service.threads
    installedAt = (Get-Date).ToString("s")
}

$state | ConvertTo-Json -Depth 10 | Set-Content -Path $statePath -Encoding UTF8

$summary = @"
Windows install state written to:
$statePath

OpenCode global install:
$(if (Get-Command opencode -ErrorAction SilentlyContinue) { 'OK' } else { 'NOT FOUND' })

Next phase:
- copy launchers and control center
- connect OpenCode config
- add desktop shortcuts
"@

Set-Content -Path (Join-Path $stateDir "install-summary.txt") -Value $summary -Encoding UTF8
Write-Host $summary
