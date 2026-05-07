param(
    [string]$Version,
    [string]$OutputDir
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$versionPath = Join-Path $repoRoot "version.json"

function Find-Iscc {
    $candidates = @(
        "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
        "C:\Program Files\Inno Setup 6\ISCC.exe",
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
    ) | Where-Object { $_ -and (Test-Path $_) }

    if ($candidates) {
        return $candidates | Select-Object -First 1
    }

    $searchRoots = @(
        "C:\Program Files",
        "C:\Program Files (x86)",
        "$env:LOCALAPPDATA\Programs"
    ) | Where-Object { $_ -and (Test-Path $_) }

    foreach ($root in $searchRoots) {
        $match = Get-ChildItem $root -Filter ISCC.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($match) {
            return $match.FullName
        }
    }

    return $null
}

if (-not (Test-Path $versionPath)) {
    throw "version.json nije pronadjen."
}

$versionData = Get-Content -Raw $versionPath | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = $versionData.version
}

if (-not ($Version -match '^\d+\.\d+\.\d+$')) {
    throw "Version mora biti u obliku a.b.c"
}

$OutputDir = if ($OutputDir) { $OutputDir } else { Join-Path $repoRoot "dist\windows" }
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$iscc = Find-Iscc
if (-not $iscc) {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "ISCC.exe nije pronadjen, pokusavam instalaciju Inno Setup 6 preko winget..." -ForegroundColor Yellow
        & winget install --id JRSoftware.InnoSetup --silent --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -ne 0) {
            throw "Inno Setup instalacija preko winget nije uspela."
        }
        $iscc = Find-Iscc
    }
}

if (-not $iscc) {
    throw "ISCC.exe nije pronadjen ni nakon pokusaja instalacije."
}

$updatedVersion = [ordered]@{
    version = $Version
    windowsSetupBaseName = $versionData.windowsSetupBaseName
    displayName = $versionData.displayName
}
$updatedVersion | ConvertTo-Json -Depth 5 | Set-Content -Path $versionPath -Encoding UTF8

$issPath = Join-Path $PSScriptRoot "LocalQwenSetup.iss"
$defines = @(
    "/DMyAppName=$($versionData.displayName)",
    "/DMyAppVersion=$Version",
    "/DMySetupBaseName=$($versionData.windowsSetupBaseName)",
    "/O$OutputDir",
    $issPath
)

& $iscc @defines
if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup build nije uspeo."
}

$artifact = Join-Path $OutputDir "$($versionData.windowsSetupBaseName)-$Version.exe"
if (-not (Test-Path $artifact)) {
    throw "Ocekivani setup artefakt nije pronadjen: $artifact"
}

Write-Host "Setup artefakt spreman:" -ForegroundColor Green
Write-Host $artifact
