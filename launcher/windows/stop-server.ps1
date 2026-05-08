. (Join-Path $PSScriptRoot "local-qwen-common.ps1")

Get-Process llama-server -ErrorAction SilentlyContinue | Stop-Process -Force
Set-ServiceLifecycleState -State "inactive" -Reason "Stop server komanda je izvrsena."
Write-Host "llama.cpp server je zaustavljen."
