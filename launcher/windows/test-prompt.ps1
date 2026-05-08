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

$result = Invoke-TestPrompt -Prompt $Prompt
$content = $result.Response.choices[0].message.content
Write-Host "Smoke test odgovor:"
Write-Host $content
if ($result.Metrics -and $result.Metrics.current) {
    Write-Host "Benchmark:"
    Write-Host "Prompt tok/s: $($result.Metrics.current.promptTokensPerSecond)"
    Write-Host "Output tok/s: $($result.Metrics.current.completionTokensPerSecond)"
    Write-Host "Ukupno ms: $($result.Metrics.current.totalMs)"
}
