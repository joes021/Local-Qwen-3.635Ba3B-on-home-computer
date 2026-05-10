param(
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "local-qwen-common.ps1")

function Get-PreferredDumpStateRoot {
    $installedRoot = Join-Path $env:USERPROFILE "LocalQwenHome"
    if (Test-Path (Join-Path $installedRoot "state\install-state.json")) {
        return $installedRoot
    }
    return Get-LocalQwenStateRoot
}

function Get-DefaultOutputPath {
    $root = Get-PreferredDumpStateRoot
    return (Join-Path $root "state\ui-dump.txt")
}

function Add-Section {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$Title
    )

    $Lines.Add("") | Out-Null
    $Lines.Add($Title) | Out-Null
    $Lines.Add(("-" * $Title.Length)) | Out-Null
}

function Add-FileMetadata {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        $Lines.Add("MISSING: $Path") | Out-Null
        return
    }

    $item = Get-Item $Path
    $hash = (Get-FileHash -Algorithm SHA256 $Path).Hash
    $Lines.Add("Path: $Path") | Out-Null
    $Lines.Add("Length: $($item.Length)") | Out-Null
    $Lines.Add("LastWriteTime: $($item.LastWriteTime.ToString("s"))") | Out-Null
    $Lines.Add("SHA256: $hash") | Out-Null
}

function Get-Matches {
    param(
        [string]$Content,
        [string]$Pattern
    )

    $results = [regex]::Matches($Content, $Pattern)
    return @($results | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
}

if (-not $OutputPath) {
    $OutputPath = Get-DefaultOutputPath
}

Ensure-Directory (Split-Path -Parent $OutputPath)

$codeRoot = Get-LocalQwenCodeRoot
$stateRoot = Get-PreferredDumpStateRoot
$controlCenterPath = Join-Path $stateRoot "launchers\control-center.ps1"
$commonPath = Join-Path $stateRoot "launchers\local-qwen-common.ps1"
$releaseNotesPath = Join-Path $stateRoot "release-notes.txt"
$versionPath = Join-Path $stateRoot "version.json"
$settingsPath = Join-Path $stateRoot "state\settings.json"
$installReportPath = Join-Path $stateRoot "state\install-report.json"

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("Local Qwen UI dump generated at $(Get-Date -Format s)") | Out-Null
$lines.Add("Code root: $codeRoot") | Out-Null
$lines.Add("State root: $stateRoot") | Out-Null
$lines.Add("App version: v$(Get-AppVersion)") | Out-Null

Add-Section -Lines $lines -Title "Key files"
foreach ($path in @($controlCenterPath, $commonPath, $releaseNotesPath, $versionPath, $settingsPath, $installReportPath)) {
    Add-FileMetadata -Lines $lines -Path $path
    $lines.Add("") | Out-Null
}

$controlContent = if (Test-Path $controlCenterPath) { Get-Content -Raw $controlCenterPath } else { "" }

Add-Section -Lines $lines -Title "Buttons"
foreach ($text in (Get-Matches -Content $controlContent -Pattern '\.Text = "([^"]+)"')) {
    $lines.Add($text) | Out-Null
}

Add-Section -Lines $lines -Title "Labels and groups"
foreach ($text in (Get-Matches -Content $controlContent -Pattern '\$[A-Za-z0-9_]+\.(?:Text)\s*=\s*"([^"]+)"')) {
    $lines.Add($text) | Out-Null
}

Add-Section -Lines $lines -Title "Quick checks"
$lines.Add(("Uses new background worker path: {0}" -f ([bool]($controlContent -match '\$powerShellExe = Get-WindowsPowerShellExe')))) | Out-Null
$lines.Add(("Uses launch primary group layout: {0}" -f ([bool]($controlContent -match '\$launchPrimaryGroup\.Text = "Pokretanje"')))) | Out-Null
$lines.Add(("Uses tools tab layout: {0}" -f ([bool]($controlContent -match '\$toolsTab\.Text = "Tools"')))) | Out-Null
$lines.Add(("Has model download live progress view: {0}" -f ([bool]($controlContent -match 'Refresh-ModelDownloadProgressView')))) | Out-Null
$lines.Add(("Has throughput test button: {0}" -f ([bool]($controlContent -match 'Test throughput')))) | Out-Null

Add-Section -Lines $lines -Title "Release notes head"
if (Test-Path $releaseNotesPath) {
    foreach ($line in (Get-Content $releaseNotesPath -TotalCount 16)) {
        $lines.Add($line) | Out-Null
    }
}

Write-Utf8NoBomText -Path $OutputPath -Content ($lines -join [Environment]::NewLine)
Write-Output "UI dump sacuvan: $OutputPath"
