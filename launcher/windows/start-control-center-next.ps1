$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "local-qwen-common.ps1")

function Get-ControlCenterNextCandidateRoots {
    $roots = New-Object System.Collections.Generic.List[string]

    if ($env:CONTROL_CENTER_NEXT_ROOT) {
        $roots.Add($env:CONTROL_CENTER_NEXT_ROOT) | Out-Null
    }

    $stateRoot = Get-LocalQwenStateRoot
    foreach ($candidate in @(
        (Join-Path $stateRoot "control-center-next"),
        (Join-Path $env:USERPROFILE "local-qwen-control-center-next"),
        (Join-Path $env:USERPROFILE "Documents\local-qwen-control-center-next"),
        "C:\Users\AzdahaI9\Documents\local-qwen-control-center-next"
    )) {
        if (-not [string]::IsNullOrWhiteSpace([string]$candidate)) {
            $roots.Add([string]$candidate) | Out-Null
        }
    }

    return @($roots | Select-Object -Unique)
}

function Get-ControlCenterNextLauncherPath {
    foreach ($root in @(Get-ControlCenterNextCandidateRoots)) {
        if (-not $root) {
            continue
        }
        $candidate = Join-Path $root "launchers\windows\start-control-center-next.ps1"
        if (Test-Path $candidate) {
            return $candidate
        }
    }
    return $null
}

function Start-LegacyControlCenter {
    $legacyPath = Join-Path $PSScriptRoot "control-center.ps1"
    if (-not (Test-Path $legacyPath)) {
        throw "Legacy Control Center nije pronadjen: $legacyPath"
    }

    & (Get-WindowsPowerShellExe) -NoProfile -ExecutionPolicy Bypass -File $legacyPath
}

$nextLauncher = Get-ControlCenterNextLauncherPath
if (-not $nextLauncher) {
    Write-Output "Control Center Next nije pronadjen. Otvaram legacy Control Center."
    Start-LegacyControlCenter
    exit 0
}

$env:LOCAL_QWEN_HOME = Get-LocalQwenStateRoot
$env:CONTROL_CENTER_NEXT_TARGET_PLATFORM = "windows"
& (Get-WindowsPowerShellExe) -NoProfile -ExecutionPolicy Bypass -File $nextLauncher
$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) {
    Write-Output "Control Center Next nije uspeo, vracam se na legacy Control Center."
    Start-LegacyControlCenter
    exit 0
}
