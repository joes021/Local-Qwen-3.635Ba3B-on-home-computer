param(
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "local-qwen-common.ps1")

function Get-DefaultOutputPath {
    $root = Get-LocalQwenRoot
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

$root = Get-LocalQwenRoot
$controlCenterPath = Join-Path $root "launchers\control-center.ps1"
$commonPath = Join-Path $root "launchers\local-qwen-common.ps1"
$releaseNotesPath = Join-Path $root "release-notes.txt"
$versionPath = Join-Path $root "version.json"
$settingsPath = Join-Path $root "state\settings.json"
$installReportPath = Join-Path $root "state\install-report.json"

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("Local Qwen UI dump generated at $(Get-Date -Format s)") | Out-Null
$lines.Add("Install root: $root") | Out-Null
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
$lines.Add(("Uses quick actions layout: {0}" -f ([bool]($controlContent -match '\$launchPrimaryGroup\.Text = "Quick actions"')))) | Out-Null
$lines.Add(("Uses tools column layout: {0}" -f ([bool]($controlContent -match '\$launchToolsGroup\.Text = "Tools"')))) | Out-Null
$lines.Add(("Has model download live progress view: {0}" -f ([bool]($controlContent -match 'Refresh-ModelDownloadProgressView')))) | Out-Null
$lines.Add(("Has throughput test button: {0}" -f ([bool]($controlContent -match 'Test throughput')))) | Out-Null

Add-Section -Lines $lines -Title "Release notes head"
if (Test-Path $releaseNotesPath) {
    foreach ($line in (Get-Content $releaseNotesPath -TotalCount 16)) {
        $lines.Add($line) | Out-Null
    }
}

$lines | Set-Content -Path $OutputPath -Encoding UTF8
Write-Host "UI dump sacuvan: $OutputPath"
