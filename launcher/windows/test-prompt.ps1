param(
    [string]$Profile,
    [string]$Prompt = "Reply with exactly OK"
)

. (Join-Path $PSScriptRoot "local-qwen-common.ps1")

if (-not (Test-LlamaHealth)) {
    $args = @("-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot "start-server.ps1"))
    if ($Profile) {
        $args += @("-Profile", $Profile)
    }
    Start-Process -FilePath "powershell.exe" -ArgumentList $args -WindowStyle Hidden

    $deadline = (Get-Date).AddSeconds(90)
    do {
        Start-Sleep -Seconds 3
    } until ((Test-LlamaHealth) -or (Get-Date) -ge $deadline)
}

if (-not (Test-LlamaHealth)) {
    throw "llama.cpp server nije dostupan."
}

$response = Invoke-TestPrompt -Prompt $Prompt
$content = $response.choices[0].message.content
Write-Host "Smoke test odgovor:"
Write-Host $content
