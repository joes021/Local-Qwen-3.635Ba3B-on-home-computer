param(
    [string]$Version,
    [switch]$SkipBuild,
    [switch]$SkipGitPush,
    [switch]$SkipReleasePublish
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$versionPath = Join-Path $repoRoot "version.json"
$windowsBuildScript = Join-Path $repoRoot "packaging\windows\build-setup.ps1"
$linuxBuildScript = Join-Path $repoRoot "packaging\linux\build-run-installer.sh"
$releaseNotesPath = Join-Path $repoRoot "release-notes.txt"
$distWindows = Join-Path $repoRoot "dist\windows"
$distLinux = Join-Path $repoRoot "dist\linux"

if (-not (Test-Path $versionPath)) {
    throw "version.json nije pronadjen."
}

$versionData = Get-Content -Raw $versionPath | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = [string]$versionData.version
}

if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    throw "Version mora biti u obliku a.b.c"
}

$windowsArtifact = Join-Path $distWindows "$($versionData.windowsSetupBaseName)-$Version.exe"
$windowsLatest = Join-Path $distWindows "$($versionData.windowsSetupBaseName)-latest.exe"
$linuxArtifact = Join-Path $distLinux "$($versionData.windowsSetupBaseName)-$Version.run"
$linuxLatest = Join-Path $distLinux "$($versionData.windowsSetupBaseName)-latest.run"

if (-not $SkipBuild) {
    & powershell -ExecutionPolicy Bypass -File $windowsBuildScript -Version $Version
    if ($LASTEXITCODE -ne 0) {
        throw "Windows build nije uspeo."
    }

    & bash $linuxBuildScript $Version
    if ($LASTEXITCODE -ne 0) {
        throw "Linux build nije uspeo."
    }
}

if (!(Test-Path $windowsArtifact)) {
    throw "Windows artefakt nije pronadjen: $windowsArtifact"
}
if (!(Test-Path $linuxArtifact)) {
    throw "Linux artefakt nije pronadjen: $linuxArtifact"
}

Copy-Item $windowsArtifact $windowsLatest -Force
Copy-Item $linuxArtifact $linuxLatest -Force

if (-not $SkipGitPush) {
    & git -C $repoRoot push origin main
    if ($LASTEXITCODE -ne 0) {
        throw "git push origin main nije uspeo."
    }

    & git -C $repoRoot tag -f "v$Version"
    if ($LASTEXITCODE -ne 0) {
        throw "git tag za v$Version nije uspeo."
    }

    & git -C $repoRoot push origin "v$Version" --force
    if ($LASTEXITCODE -ne 0) {
        throw "git push taga v$Version nije uspeo."
    }
}

if (-not $SkipReleasePublish) {
    & gh release create "v$Version" `
        $windowsArtifact `
        $windowsLatest `
        $linuxArtifact `
        $linuxLatest `
        --title "v$Version" `
        --notes-file $releaseNotesPath

    if ($LASTEXITCODE -ne 0) {
        throw "gh release create nije uspeo."
    }
}

Write-Host "Release automation zavrsena:" -ForegroundColor Green
Write-Host "Version: $Version"
Write-Host "Windows: $windowsArtifact"
Write-Host "Linux:   $linuxArtifact"
