param(
    [ValidateSet("everything", "keep-models", "shortcuts-only")]
    [string]$Mode
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "local-qwen-common.ps1")

function Remove-PathIfExists {
    param([string]$Path)
    if ($Path -and (Test-Path $Path)) {
        try {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            return $true
        } catch {
            return $false
        }
    }
    return $true
}

function Remove-DesktopLaunchers {
    $desktopDir = Get-DesktopTargetDir
    foreach ($name in (Get-DesktopShortcutNames)) {
        $path = Join-Path $desktopDir $name
        if (Test-Path $path) {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }
    if ((Test-Path $desktopDir) -and -not (Get-ChildItem -LiteralPath $desktopDir -Force -ErrorAction SilentlyContinue)) {
        Remove-Item -LiteralPath $desktopDir -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-DeferredDelete {
    param(
        [Parameter(Mandatory = $true)][string[]]$Paths
    )

    $cmdPath = Join-Path $env:TEMP ("local-qwen-uninstall-{0}.cmd" -f ([guid]::NewGuid().ToString("N")))
    $lines = @(
        "@echo off",
        "setlocal",
        "timeout /t 2 /nobreak >nul"
    )
    foreach ($path in $Paths) {
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            $lines += "if exist `"$path`" rmdir /s /q `"$path`""
            $lines += "if exist `"$path`" del /f /q `"$path`" >nul 2>nul"
        }
    }
    $lines += "del /f /q `"%~f0`" >nul 2>nul"
    Set-Content -LiteralPath $cmdPath -Value ($lines -join "`r`n") -Encoding ASCII
    Start-Process -FilePath $env:ComSpec -ArgumentList "/c `"$cmdPath`"" -WindowStyle Hidden
}

function Get-UninstallMode {
    if ($Mode) {
        return $Mode
    }

    Write-Host ""
    Write-Host "Uninstall Local Qwen" -ForegroundColor Cyan
    Write-Host "Izaberi sta zelis da obrises:"
    Write-Host "  [1] Samo desktop precice"
    Write-Host "  [2] Obrisi aplikaciju, zadrzi modele"
    Write-Host "  [3] Obrisi sve ukljucujuci modele (default)"
    $choice = Read-Host "Izbor [1/2/3]"
    switch (([string]$choice).Trim()) {
        "1" { return "shortcuts-only" }
        "2" { return "keep-models" }
        "3" { return "everything" }
        "" { return "everything" }
        default { return "everything" }
    }
}

$root = Get-LocalQwenStateRoot
$state = Get-InstallState
$bootstrapRoot = Join-Path ${env:ProgramFiles} "LocalQwenSetupBootstrap"
$selectedMode = Get-UninstallMode
$messages = New-Object System.Collections.Generic.List[string]

switch ($selectedMode) {
    "shortcuts-only" {
        Remove-DesktopLaunchers
        $messages.Add("Obrisane su desktop precice.") | Out-Null
    }
    "keep-models" {
        Remove-DesktopLaunchers
        foreach ($relative in @("launchers", "scripts", "assets", "config", "docs", "state", "bin", "apps")) {
            [void](Remove-PathIfExists (Join-Path $root $relative))
        }
        foreach ($file in @("version.json", "release-notes.txt", "README.md")) {
            $path = Join-Path $root $file
            if (Test-Path $path) {
                Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
            }
        }
        $configPath = Get-OpenCodeConfigPath
        if (Test-Path $configPath) {
            Remove-Item -LiteralPath $configPath -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path $bootstrapRoot) {
            if (-not (Remove-PathIfExists $bootstrapRoot)) {
                $messages.Add("Bootstrap folder u Program Files nije automatski obrisan; moguca su administratorska prava.") | Out-Null
            }
        }
        $messages.Add("Aplikacioni fajlovi su obrisani, modeli su sacuvani.") | Out-Null
    }
    "everything" {
        Remove-DesktopLaunchers
        $configPath = Get-OpenCodeConfigPath
        if (Test-Path $configPath) {
            Remove-Item -LiteralPath $configPath -Force -ErrorAction SilentlyContinue
        }
        Invoke-DeferredDelete -Paths @($root, $bootstrapRoot)
        $messages.Add("Zakazano je potpuno brisanje LocalQwenHome i bootstrap foldera, ukljucujuci modele.") | Out-Null
    }
}

Write-Host ""
Write-Host "UNINSTALL SUMMARY" -ForegroundColor Green
foreach ($message in $messages) {
    Write-Host "- $message"
}
Write-Host "- npm/opencode global install nije automatski uklonjen, da ne bismo obrisali alat koji mozda koristis i van ovog projekta."
