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
    Start-Process -FilePath (Get-WindowsPowerShellExe) -ArgumentList $args -WindowStyle Hidden

    $deadline = (Get-Date).AddSeconds(90)
    do {
        Start-Sleep -Seconds 3
    } until ((Test-LlamaHealth) -or (Get-Date) -ge $deadline)
}

if (-not (Test-LlamaHealth)) {
    throw "llama.cpp server nije dostupan."
}

$result = Invoke-TestPrompt -Prompt $Prompt
$choice = $result.Response.choices[0]
$message = $choice.message
$content = [string]$message.content
$usedReasoningFallback = $false
if ([string]::IsNullOrWhiteSpace($content) -and $message.PSObject.Properties["reasoning_content"]) {
    $reasoningExcerpt = (([string]$message.reasoning_content) -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
    if (-not [string]::IsNullOrWhiteSpace([string]$reasoningExcerpt)) {
        $content = [string]$reasoningExcerpt
    } else {
        $content = [string]$message.reasoning_content
    }
    if ($content.Length -gt 220) {
        $content = $content.Substring(0, 220) + "..."
    }
    $usedReasoningFallback = $true
}
if ([string]::IsNullOrWhiteSpace($content)) {
    $content = "[Prazan odgovor]"
}
Write-Output "Smoke test odgovor:"
Write-Output $content
if ($usedReasoningFallback) {
    Write-Output "Napomena: model nije vratio finalni tekst, pa je prikazan kratak reasoning izvod."
}
if ($choice.PSObject.Properties["finish_reason"] -and -not [string]::IsNullOrWhiteSpace([string]$choice.finish_reason)) {
    Write-Output "Finish reason: $($choice.finish_reason)"
}
if ($result.Metrics -and $result.Metrics.current) {
    Write-Output "Benchmark:"
    Write-Output "Prompt tok/s: $($result.Metrics.current.promptTokensPerSecond)"
    Write-Output "Output tok/s: $($result.Metrics.current.completionTokensPerSecond)"
    Write-Output "Ukupno ms: $($result.Metrics.current.totalMs)"
}
