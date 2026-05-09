param(
    [ValidateSet("strict", "blacklist", "open")]
    [string]$SecurityMode = "strict",
    [ValidateSet("read-only", "read-write", "confirm-commands", "auto-commands")]
    [string]$CapabilityMode = "confirm-commands",
    [string]$WorkingFolder = $env:USERPROFILE,
    [ValidateSet("speed", "balanced", "video")]
    [string]$Profile,
    [switch]$NoLaunch
)

. (Join-Path $PSScriptRoot "local-qwen-common.ps1")

$root = Get-LocalQwenRoot
$sessionRoot = Join-Path $root "state\agent-session-config"
$sessionConfigPath = Join-Path $sessionRoot "opencode.json"
$sessionMetaPath = Join-Path $root "state\agent-launch-settings.json"
$serverStartScript = Join-Path $PSScriptRoot "start-server.ps1"
$serverHealthUrl = Get-LlamaHealthUrl

function Ensure-LlamaServer {
    param([string]$SelectedProfile)

    if (Test-LlamaHealth) {
        return
    }

    $args = @(
        "-ExecutionPolicy", "Bypass",
        "-File", $serverStartScript
    )

    if ($SelectedProfile) {
        $args += @("-Profile", $SelectedProfile)
    }

    Start-Process -FilePath (Get-WindowsPowerShellExe) -ArgumentList $args -WindowStyle Hidden

    $deadline = (Get-Date).AddSeconds(90)
    do {
        Start-Sleep -Seconds 3
    } until ((Test-LlamaHealth) -or (Get-Date) -ge $deadline)

    if (-not (Test-LlamaHealth)) {
        throw "llama.cpp server nije odgovorio na $serverHealthUrl."
    }
}

function New-RuleMap {
    param([string]$DefaultAction)

    return [ordered]@{
        "*" = $DefaultAction
    }
}

function Build-PermissionConfig {
    param(
        [string]$Security,
        [string]$Capability
    )

    $permission = [ordered]@{
        "*" = "allow"
        "doom_loop" = "allow"
        "question" = "allow"
        "skill" = "allow"
        "task" = "allow"
    }

    switch ($Capability) {
        "read-only" {
            $permission["edit"] = "deny"
            $permission["bash"] = "deny"
        }
        "read-write" {
            $permission["edit"] = "allow"
            $permission["bash"] = "deny"
        }
        "confirm-commands" {
            $permission["edit"] = "allow"
            $permission["bash"] = "ask"
        }
        "auto-commands" {
            $permission["edit"] = "allow"
            $permission["bash"] = "allow"
        }
    }

    switch ($Security) {
        "strict" {
            $permission["external_directory"] = "deny"
        }
        "open" {
            $permission["external_directory"] = "allow"
        }
        "blacklist" {
            $permission["external_directory"] = "deny"

            $blockedPaths = @(
                "C:\Windows\**",
                "C:\Program Files\**",
                "C:\Program Files (x86)\**",
                "C:\ProgramData\**",
                "$env:USERPROFILE\AppData\**",
                "C:\System Volume Information\**",
                "C:\`$Recycle.Bin\**"
            )

            $readRules = New-RuleMap -DefaultAction "allow"
            $editRules = if ($Capability -eq "read-only") { New-RuleMap -DefaultAction "deny" } else { New-RuleMap -DefaultAction "allow" }
            $globRules = New-RuleMap -DefaultAction "allow"
            $grepRules = New-RuleMap -DefaultAction "allow"

            foreach ($blockedPath in $blockedPaths) {
                $readRules[$blockedPath] = "deny"
                $editRules[$blockedPath] = "deny"
                $globRules[$blockedPath] = "deny"
                $grepRules[$blockedPath] = "deny"
            }

            $permission["read"] = $readRules
            $permission["edit"] = $editRules
            $permission["glob"] = $globRules
            $permission["grep"] = $grepRules

            if ($Capability -eq "confirm-commands" -or $Capability -eq "auto-commands") {
                $bashRules = [ordered]@{
                    "*" = if ($Capability -eq "confirm-commands") { "ask" } else { "allow" }
                    "Remove-Item *" = "deny"
                    "del *" = "deny"
                    "erase *" = "deny"
                    "format *" = "deny"
                    "diskpart*" = "deny"
                    "bcdedit *" = "deny"
                    "reg delete *" = "deny"
                    "shutdown *" = "deny"
                    "Restart-Computer*" = "deny"
                    "Stop-Computer*" = "deny"
                    "* C:\Windows\*" = "deny"
                    "* C:\Program Files\*" = "deny"
                    "* C:\Program Files (x86)\*" = "deny"
                    "* $env:USERPROFILE\AppData\*" = "deny"
                }
                $permission["bash"] = $bashRules
            }
        }
    }

    return $permission
}

function Save-SessionConfig {
    param(
        [string]$Security,
        [string]$Capability,
        [string]$RootFolder,
        [string]$SelectedProfile
    )

    Ensure-Directory $sessionRoot

    $config = [ordered]@{
        '$schema' = "https://opencode.ai/config.json"
        "permission" = (Build-PermissionConfig -Security $Security -Capability $Capability)
    }

    $config | ConvertTo-Json -Depth 20 | Set-Content -Path $sessionConfigPath -Encoding UTF8

    $meta = [ordered]@{
        securityMode = $Security
        capabilityMode = $Capability
        workingFolder = $RootFolder
        profile = $SelectedProfile
        audit = (Get-AgentAudit -SecurityMode $Security -CapabilityMode $Capability -WorkingFolder $RootFolder)
        generatedAt = (Get-Date).ToString("s")
    }

    $meta | ConvertTo-Json -Depth 5 | Set-Content -Path $sessionMetaPath -Encoding UTF8
}

if (-not (Test-Path $WorkingFolder)) {
    throw "Izabrani folder ne postoji: $WorkingFolder"
}

$resolvedFolder = (Resolve-Path -LiteralPath $WorkingFolder).Path
$selectedProfile = if ($Profile) { $Profile } else { [string](Get-Settings).profile }
$audit = Get-AgentAudit -SecurityMode $SecurityMode -CapabilityMode $CapabilityMode -WorkingFolder $resolvedFolder

Save-SessionConfig -Security $SecurityMode -Capability $CapabilityMode -RootFolder $resolvedFolder -SelectedProfile $selectedProfile

if ($NoLaunch) {
    Write-Host "Konfiguracija upisana:"
    Write-Host "Security mode: $SecurityMode"
    Write-Host "Capability mode: $CapabilityMode"
    Write-Host "Working folder: $resolvedFolder"
    Write-Host "Risk level: $($audit.riskLevel)"
    Write-Host "Session config: $sessionConfigPath"
    exit 0
}

if ($audit.requiresWarning) {
    Write-Host "Agent risk: $($audit.riskLevel)" -ForegroundColor Yellow
    $audit.reasons | ForEach-Object { Write-Host "- $_" -ForegroundColor Yellow }
}

if (-not (Get-Command opencode -ErrorAction SilentlyContinue)) {
    throw "OpenCode nije pronadjen u PATH-u."
}

Ensure-LlamaServer -SelectedProfile $selectedProfile

$windowTitle = "OpenCode Agent | $SecurityMode | $CapabilityMode"
$escapedConfigDir = $sessionRoot.Replace("'", "''")
$escapedTitle = $windowTitle.Replace("'", "''")
$command = "`$env:OPENCODE_CONFIG_DIR='$escapedConfigDir'; `$Host.UI.RawUI.WindowTitle='$escapedTitle'; opencode"

Start-Process -FilePath (Get-WindowsPowerShellExe) -WorkingDirectory $resolvedFolder -ArgumentList @(
    "-NoExit",
    "-Command",
    $command
)
