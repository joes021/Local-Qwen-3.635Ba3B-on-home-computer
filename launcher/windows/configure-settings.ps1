param(
    [ValidateSet("speed", "balanced", "video")]
    [string]$Profile,
    [int]$ContextSize,
    [int]$MaxOutputTokens,
    [int]$BuildSteps,
    [int]$PlanSteps,
    [int]$GeneralSteps,
    [int]$ExploreSteps
)

. (Join-Path $PSScriptRoot "local-qwen-common.ps1")

$settings = Get-Settings

if ($Profile) { $settings.profile = $Profile }
if (-not $settings.llama.PSObject.Properties["contextSizeCustomized"]) {
    $settings.llama | Add-Member -NotePropertyName "contextSizeCustomized" -NotePropertyValue $false
}
if (-not $settings.llama.PSObject.Properties["maxOutputTokensCustomized"]) {
    $settings.llama | Add-Member -NotePropertyName "maxOutputTokensCustomized" -NotePropertyValue $false
}

if ($ContextSize) {
    $settings.llama.contextSize = $ContextSize
    $settings.llama.contextSizeCustomized = $true
}
if ($MaxOutputTokens) {
    $settings.llama.maxOutputTokens = $MaxOutputTokens
    $settings.llama.maxOutputTokensCustomized = $true
}
if ($BuildSteps) { $settings.opencode.buildSteps = $BuildSteps }
if ($PlanSteps) { $settings.opencode.planSteps = $PlanSteps }
if ($GeneralSteps) { $settings.opencode.generalSteps = $GeneralSteps }
if ($ExploreSteps) { $settings.opencode.exploreSteps = $ExploreSteps }

Save-Settings -Settings $settings
$configPath = Update-OpenCodeConfig
$settingsPath = Join-Path (Get-LocalQwenStateRoot) "state\settings.json"

Write-Host "Sacuvano."
Write-Host "Settings: $settingsPath"
Write-Host "OpenCode config: $configPath"
