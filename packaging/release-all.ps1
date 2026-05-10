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
$linuxBuildScript = Join-Path $repoRoot "packaging\linux\build-run-package.ps1"
$releaseNotesPath = Join-Path $repoRoot "release-notes.txt"
$distWindows = Join-Path $repoRoot "dist\windows"
$distLinux = Join-Path $repoRoot "dist\linux"
$tempReleaseDir = Join-Path $repoRoot "dist\release-meta"

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
$fullFixLogAsset = Join-Path $tempReleaseDir "Local-Qwen-Full-Fix-Log-v$Version.txt"
$releaseSummaryPath = Join-Path $tempReleaseDir "release-summary-v$Version.md"

function Get-ReleaseSection {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Version
    )

    $content = Get-Content -Raw $Path
    $pattern = "(?ms)^v$([regex]::Escape($Version))\s*\r?\n(?<body>.*?)(?=^\s*v\d+\.\d+\.\d+\s*$|\z)"
    $match = [regex]::Match($content, $pattern)
    if (-not $match.Success) {
        throw "Fix log sekcija za v$Version nije pronadjena u $Path"
    }
    return ("v{0}`r`n{1}" -f $Version, $match.Groups["body"].Value.Trim())
}

if (-not $SkipBuild) {
    & powershell -ExecutionPolicy Bypass -File $windowsBuildScript -Version $Version
    if ($LASTEXITCODE -ne 0) {
        throw "Windows build nije uspeo."
    }

    & powershell -ExecutionPolicy Bypass -File $linuxBuildScript -Version $Version
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

New-Item -ItemType Directory -Force -Path $tempReleaseDir | Out-Null
$releaseSection = Get-ReleaseSection -Path $releaseNotesPath -Version $Version
Set-Content -Path $fullFixLogAsset -Value $releaseSection -Encoding UTF8
$releaseSummary = @(
    "v$Version",
    "",
    "- Windows installer: Local-Qwen-Setup-$Version.exe",
    "- Linux installer: Local-Qwen-Setup-$Version.run",
    "- Stable aliases: Local-Qwen-Setup-latest.exe and Local-Qwen-Setup-latest.run",
    "- Full fix log is attached below in Assets as Local-Qwen-Full-Fix-Log-v$Version.txt"
) -join "`r`n"
Set-Content -Path $releaseSummaryPath -Value $releaseSummary -Encoding UTF8

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
        $fullFixLogAsset `
        --title "v$Version" `
        --notes-file $releaseSummaryPath

    if ($LASTEXITCODE -ne 0) {
        throw "gh release create nije uspeo."
    }
}

Write-Host "Release automation zavrsena:" -ForegroundColor Green
Write-Host "Version: $Version"
Write-Host "Windows: $windowsArtifact"
Write-Host "Linux:   $linuxArtifact"
