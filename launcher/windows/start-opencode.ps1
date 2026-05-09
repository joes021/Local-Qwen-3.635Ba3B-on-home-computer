param(
    [ValidateSet("speed", "balanced", "video")]
    [string]$Profile
)

. (Join-Path $PSScriptRoot "local-qwen-common.ps1")

if (-not (Get-Command opencode -ErrorAction SilentlyContinue)) {
    throw "OpenCode nije pronadjen u PATH-u."
}

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

Start-Process -FilePath (Get-WindowsPowerShellExe) -ArgumentList @(
    "-NoExit",
    "-Command",
    "opencode"
)
