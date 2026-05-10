param(
    [ValidateSet("speed", "balanced", "video")]
    [string]$Profile
)

. (Join-Path $PSScriptRoot "local-qwen-common.ps1")

$openCodeExe = Get-OpenCodeExecutable

Update-OpenCodeConfig | Out-Null

if (-not (Test-LlamaHealth)) {
    $args = @("-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot "start-server.ps1"))
    if ($Profile) {
        $args += @("-Profile", $Profile)
    }
    Start-Process -FilePath (Get-WindowsPowerShellExe) -ArgumentList $args -WindowStyle Hidden

    $deadline = (Get-Date).AddSeconds(90)
    do {
        Start-Sleep -Seconds 3
    } until ((Test-LlamaHealth) -or (Get-Date) -ge $deadline)
}

if (-not (Test-LlamaHealth)) {
    throw "llama.cpp server nije dostupan."
}

function Get-OpenCodeLaunchCommand {
    param([Parameter(Mandatory = $true)][string]$ExecutablePath)

    $escapedConfigPath = (Split-Path -Parent (Get-OpenCodeConfigPath)).Replace("'", "''")
    $escapedExecutable = $ExecutablePath.Replace("'", "''")
    return "`$env:OPENCODE_CONFIG_DIR='$escapedConfigPath'; `$env:OPENCODE_ENABLE_EXA='1'; & '$escapedExecutable'"
}

Start-Process -FilePath (Get-WindowsPowerShellExe) -ArgumentList @(
    "-NoExit",
    "-Command",
    (Get-OpenCodeLaunchCommand -ExecutablePath $openCodeExe)
)
