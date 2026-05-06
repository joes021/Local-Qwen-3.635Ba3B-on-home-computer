. (Join-Path $PSScriptRoot "local-qwen-common.ps1")

Get-Process llama-server -ErrorAction SilentlyContinue | Stop-Process -Force
Write-Host "llama.cpp server je zaustavljen."
