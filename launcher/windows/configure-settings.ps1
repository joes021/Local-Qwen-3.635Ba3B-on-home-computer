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
if ($ContextSize) { $settings.llama.contextSize = $ContextSize }
if ($MaxOutputTokens) { $settings.llama.maxOutputTokens = $MaxOutputTokens }
if ($BuildSteps) { $settings.opencode.buildSteps = $BuildSteps }
if ($PlanSteps) { $settings.opencode.planSteps = $PlanSteps }
if ($GeneralSteps) { $settings.opencode.generalSteps = $GeneralSteps }
if ($ExploreSteps) { $settings.opencode.exploreSteps = $ExploreSteps }

Save-Settings -Settings $settings
$configPath = Update-OpenCodeConfig

Write-Host "Sacuvano."
Write-Host "Settings: $(Join-Path (Get-LocalQwenRoot) 'state\settings.json')"
Write-Host "OpenCode config: $configPath"
