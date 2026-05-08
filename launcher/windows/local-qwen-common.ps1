$ErrorActionPreference = "Stop"

function Get-LocalQwenRoot {
    $oneLevelUp = Join-Path $PSScriptRoot ".."
    $twoLevelsUp = Join-Path $PSScriptRoot "..\.."

    $candidateRoots = @($oneLevelUp, $twoLevelsUp)
    foreach ($candidate in $candidateRoots) {
        $resolved = $null
        try {
            $resolved = (Resolve-Path $candidate -ErrorAction Stop).Path
        } catch {
            continue
        }

        if (
            (Test-Path (Join-Path $resolved "state\install-state.json")) -or
            (Test-Path (Join-Path $resolved "config\profiles\defaults.json")) -or
            (Test-Path (Join-Path $resolved "launchers"))
        ) {
            return $resolved
        }
    }

    return (Resolve-Path $twoLevelsUp).Path
}

function Get-InstallState {
    $root = Get-LocalQwenRoot
    $statePath = Join-Path $root "state\install-state.json"
    if (!(Test-Path $statePath)) {
        throw "Install state nije pronadjen: $statePath"
    }

    return Get-Content -Raw $statePath | ConvertFrom-Json
}

function Get-Defaults {
    $root = Get-LocalQwenRoot
    $defaultsPath = Join-Path $root "config\profiles\defaults.json"
    if (!(Test-Path $defaultsPath)) {
        throw "Defaults config nije pronadjen: $defaultsPath"
    }

    return Get-Content -Raw $defaultsPath | ConvertFrom-Json
}

function Get-Settings {
    $root = Get-LocalQwenRoot
    $settingsPath = Join-Path $root "state\settings.json"
    if (Test-Path $settingsPath) {
        return Get-Content -Raw $settingsPath | ConvertFrom-Json
    }

    $defaults = Get-Defaults
    return [pscustomobject]@{
        profile = "balanced"
        llama = [pscustomobject]@{
            contextSize = $defaults.profiles.balanced.contextSize
            maxOutputTokens = 8192
            contextSizeCustomized = $false
            maxOutputTokensCustomized = $false
        }
        opencode = [pscustomobject]@{
            buildSteps = $defaults.opencode.steps.build
            planSteps = $defaults.opencode.steps.plan
            generalSteps = $defaults.opencode.steps.general
            exploreSteps = $defaults.opencode.steps.explore
        }
    }
}

function Save-Settings {
    param([Parameter(Mandatory = $true)]$Settings)

    $root = Get-LocalQwenRoot
    $settingsPath = Join-Path $root "state\settings.json"
    $Settings | ConvertTo-Json -Depth 20 | Set-Content -Path $settingsPath -Encoding UTF8
}

function Get-VersionFilePath {
    $root = Get-LocalQwenRoot
    $path = Join-Path $root "version.json"
    if (Test-Path $path) {
        return $path
    }
    return $null
}

function Get-AppVersion {
    $versionPath = Get-VersionFilePath
    if (-not $versionPath) {
        return "unknown"
    }

    try {
        $data = Get-Content -Raw $versionPath | ConvertFrom-Json
        if ($data.version) {
            return [string]$data.version
        }
    } catch {
    }

    return "unknown"
}

function Get-ReleaseNotesPath {
    $root = Get-LocalQwenRoot
    $path = Join-Path $root "docs\release-notes.txt"
    if (Test-Path $path) {
        return $path
    }
    return $null
}

function Get-ReleaseNotesText {
    $notesPath = Get-ReleaseNotesPath
    if (-not $notesPath) {
        return "Release notes nisu dostupne u ovoj instalaciji."
    }

    try {
        return Get-Content -Raw $notesPath
    } catch {
        return "Release notes nisu mogle da se procitaju."
    }
}

function Get-OpenCodeConfigPath {
    return Join-Path $env:USERPROFILE ".config\opencode\opencode.json"
}

function Ensure-Directory {
    param([string]$Path)
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Get-LlamaHealthUrl {
    $state = Get-InstallState
    return "http://127.0.0.1:$($state.port)/health"
}

function Test-LlamaHealth {
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri (Get-LlamaHealthUrl) -TimeoutSec 5
        return $response.Content -match '"status"\s*:\s*"ok"'
    } catch {
        return $false
    }
}

function Get-DetectedGpuMemoryMiB {
    try {
        $controllers = Get-CimInstance Win32_VideoController -ErrorAction Stop | Where-Object { $_.AdapterRAM -gt 0 }
        if (-not $controllers) {
            return $null
        }

        $maxBytes = ($controllers | Measure-Object -Property AdapterRAM -Maximum).Maximum
        if (-not $maxBytes) {
            return $null
        }

        return [int]([math]::Round($maxBytes / 1MB))
    } catch {
        return $null
    }
}

function Get-PrimaryGpuInfo {
    try {
        $controllers = Get-CimInstance Win32_VideoController -ErrorAction Stop | Where-Object { $_.AdapterRAM -gt 0 }
        if (-not $controllers) {
            return $null
        }

        $primary = $controllers | Sort-Object AdapterRAM -Descending | Select-Object -First 1
        return [pscustomobject]@{
            Name = [string]$primary.Name
            MemoryMiB = [int]([math]::Round($primary.AdapterRAM / 1MB))
            DriverVersion = [string]$primary.DriverVersion
        }
    } catch {
        return $null
    }
}

function Get-CpuName {
    try {
        $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1 -ExpandProperty Name
        return [string]$cpu
    } catch {
        return $null
    }
}

function Get-SystemMemoryGiB {
    try {
        $computer = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        return [int]([math]::Round($computer.TotalPhysicalMemory / 1GB))
    } catch {
        return $null
    }
}

function Get-LlamaServerExe {
    $state = Get-InstallState
    $candidates = @()

    if ($state.PSObject.Properties["turboServerExe"] -and $state.turboServerExe) {
        $candidates += [string]$state.turboServerExe
    }

    if ($state.PSObject.Properties["llamaBinDir"] -and $state.llamaBinDir) {
        $candidates += (Join-Path $state.llamaBinDir "llama-server.exe")
    }

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    throw "llama-server.exe nije pronadjen ni u TurboQuant ni u upstream bin folderu."
}

function Get-EffectiveServerPlan {
    param(
        [ValidateSet("speed", "balanced", "video")]
        [string]$Profile
    )

    $state = Get-InstallState
    $defaults = Get-Defaults
    $settings = Get-Settings

    if (-not $Profile) {
        $Profile = if ($settings.profile) { [string]$settings.profile } else { [string]$state.defaultProfile }
    }

    $profileData = $defaults.profiles.$Profile
    if (-not $profileData) {
        throw "Nepoznat profil: $Profile"
    }

    $serverExe = Get-LlamaServerExe
    $gpuInfo = Get-PrimaryGpuInfo
    $cpuName = Get-CpuName
    $memoryGiB = Get-SystemMemoryGiB
    $ctx = if ($settings.llama.contextSize) { [int]$settings.llama.contextSize } else { [int]$profileData.contextSize }
    $maxOutput = if ($settings.llama.maxOutputTokens) { [int]$settings.llama.maxOutputTokens } else { 8192 }
    $gpuLayers = 999
    $contextCustomized = if ($settings.llama.PSObject.Properties["contextSizeCustomized"]) {
        [bool]$settings.llama.contextSizeCustomized
    } else {
        ([int]$ctx -ne [int]$profileData.contextSize)
    }
    $outputCustomized = if ($settings.llama.PSObject.Properties["maxOutputTokensCustomized"]) {
        [bool]$settings.llama.maxOutputTokensCustomized
    } else {
        ([int]$maxOutput -ne 8192)
    }

    $usesTurboQuant = $false
    if ($state.PSObject.Properties["turboServerExe"] -and $state.turboServerExe) {
        try {
            $usesTurboQuant = ((Resolve-Path $serverExe).Path -eq (Resolve-Path $state.turboServerExe).Path)
        } catch {
            $usesTurboQuant = $false
        }
    }

    $adjustmentNotes = New-Object System.Collections.Generic.List[string]

    if (-not $usesTurboQuant) {
        $detectedGpuMiB = if ($gpuInfo) { [int]$gpuInfo.MemoryMiB } else { $null }

        if ($settings.llama.PSObject.Properties["gpuLayers"] -and $settings.llama.gpuLayers) {
            $gpuLayers = [int]$settings.llama.gpuLayers
            $adjustmentNotes.Add("gpuLayers je rucno zadat kroz settings.") | Out-Null
        } elseif ($detectedGpuMiB) {
            if ($detectedGpuMiB -le 8192) {
                $gpuLayers = 10
                if (-not $contextCustomized) {
                    $ctx = [math]::Min($ctx, 4096)
                    $adjustmentNotes.Add("Fallback za GPU do 8 GB: context ogranicen na 4096.") | Out-Null
                }
                if (-not $outputCustomized) {
                    $maxOutput = [math]::Min($maxOutput, 1024)
                    $adjustmentNotes.Add("Fallback za GPU do 8 GB: output ogranicen na 1024.") | Out-Null
                }
            } elseif ($detectedGpuMiB -le 12288) {
                $gpuLayers = 20
                if (-not $contextCustomized) {
                    $ctx = [math]::Min($ctx, 8192)
                    $adjustmentNotes.Add("Fallback za GPU do 12 GB: context ogranicen na 8192.") | Out-Null
                }
                if (-not $outputCustomized) {
                    $maxOutput = [math]::Min($maxOutput, 2048)
                    $adjustmentNotes.Add("Fallback za GPU do 12 GB: output ogranicen na 2048.") | Out-Null
                }
            } else {
                $gpuLayers = 28
                if (-not $contextCustomized) {
                    $ctx = [math]::Min($ctx, 16384)
                    $adjustmentNotes.Add("Fallback za jaci GPU: context ogranicen na 16384.") | Out-Null
                }
                if (-not $outputCustomized) {
                    $maxOutput = [math]::Min($maxOutput, 4096)
                    $adjustmentNotes.Add("Fallback za jaci GPU: output ogranicen na 4096.") | Out-Null
                }
            }
        } else {
            $gpuLayers = 20
            if (-not $contextCustomized) {
                $ctx = [math]::Min($ctx, 8192)
                $adjustmentNotes.Add("GPU VRAM nije ocitan: context ogranicen na 8192.") | Out-Null
            }
            if (-not $outputCustomized) {
                $maxOutput = [math]::Min($maxOutput, 2048)
                $adjustmentNotes.Add("GPU VRAM nije ocitan: output ogranicen na 2048.") | Out-Null
            }
        }
    } else {
        $adjustmentNotes.Add("TurboQuant runtime aktivan: koriste se video-style cache tipovi.") | Out-Null
    }

    return [pscustomobject]@{
        Profile = $Profile
        UsesTurboQuant = $usesTurboQuant
        ServerExe = $serverExe
        GpuName = if ($gpuInfo) { $gpuInfo.Name } else { $null }
        GpuMemoryMiB = if ($gpuInfo) { $gpuInfo.MemoryMiB } else { $null }
        GpuDriverVersion = if ($gpuInfo) { $gpuInfo.DriverVersion } else { $null }
        CpuName = $cpuName
        SystemMemoryGiB = $memoryGiB
        ContextSize = $ctx
        MaxOutputTokens = $maxOutput
        GpuLayers = $gpuLayers
        Ncmoe = [int]$profileData.ncmoe
        CacheTypeK = [string]$profileData.cacheTypeK
        CacheTypeV = [string]$profileData.cacheTypeV
        Threads = [int]$state.threads
        Port = [int]$state.port
        ContextCustomized = $contextCustomized
        OutputCustomized = $outputCustomized
        AdjustmentNotes = @($adjustmentNotes)
    }
}

function Get-ModelMetadata {
    $state = Get-InstallState
    $defaults = Get-Defaults

    foreach ($property in $defaults.modelChoices.PSObject.Properties) {
        $candidate = $property.Value
        if ($candidate.id -eq $state.modelId -or $candidate.filename -eq $state.modelId) {
            return $candidate
        }
    }

    return $null
}

function Test-ModelFileLooksComplete {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (!(Test-Path $Path)) {
        return $false
    }

    $meta = Get-ModelMetadata
    if (-not $meta) {
        return $true
    }

    $minExpectedBytes = 0
    if ($meta.PSObject.Properties["minExpectedBytes"] -and $meta.minExpectedBytes) {
        $minExpectedBytes = [int64]$meta.minExpectedBytes
    }

    if ($minExpectedBytes -le 0) {
        return $true
    }

    return ((Get-Item $Path).Length -ge $minExpectedBytes)
}

function Get-LlamaModelPath {
    $state = Get-InstallState
    if (!(Test-Path $state.modelFile)) {
        throw "Model nije pronadjen: $($state.modelFile)"
    }
    if (-not (Test-ModelFileLooksComplete -Path $state.modelFile)) {
        $file = Get-Item $state.modelFile
        $meta = Get-ModelMetadata
        $minExpectedBytes = if ($meta -and $meta.PSObject.Properties["minExpectedBytes"]) { [int64]$meta.minExpectedBytes } else { 0 }
        throw "Model deluje nepotpuno: $($state.modelFile) (trenutno $($file.Length) bajtova, ocekivano najmanje $minExpectedBytes)"
    }
    return $state.modelFile
}

function Update-OpenCodeConfig {
    $state = Get-InstallState
    $settings = Get-Settings
    $configPath = Get-OpenCodeConfigPath
    Ensure-Directory (Split-Path -Parent $configPath)

    $existing = $null
    if (Test-Path $configPath) {
        try {
            $existing = Get-Content -Raw $configPath | ConvertFrom-Json
        } catch {
            $existing = [pscustomobject]@{}
        }
    } else {
        $existing = [pscustomobject]@{}
    }

    if (-not $existing.PSObject.Properties["provider"]) {
        $existing | Add-Member -NotePropertyName "provider" -NotePropertyValue ([pscustomobject]@{})
    }

    $existing.provider | Add-Member -Force -NotePropertyName "local-llamacpp" -NotePropertyValue ([pscustomobject]@{
        npm = "@ai-sdk/openai-compatible"
        name = "Local llama.cpp"
        options = [pscustomobject]@{
            baseURL = "http://127.0.0.1:$($state.port)/v1"
            apiKey = "llama.cpp"
        }
        models = [pscustomobject]@{
            ($state.modelId) = [pscustomobject]@{
                name = "Qwen 3.6 35B A3B Local (llama.cpp)"
            }
        }
    })

    $existing | Add-Member -Force -NotePropertyName "model" -NotePropertyValue "local-llamacpp/$($state.modelId)"

    if (-not $existing.PSObject.Properties["small_model"]) {
        $existing | Add-Member -NotePropertyName "small_model" -NotePropertyValue "local-llamacpp/$($state.modelId)"
    }

    if (-not $existing.PSObject.Properties["agent"]) {
        $existing | Add-Member -NotePropertyName "agent" -NotePropertyValue ([pscustomobject]@{})
    }

    foreach ($name in @("build", "plan", "general", "explore")) {
        if (-not $existing.agent.PSObject.Properties[$name]) {
            $existing.agent | Add-Member -NotePropertyName $name -NotePropertyValue ([pscustomobject]@{})
        }
    }

    $existing.agent.build.steps = [int]$settings.opencode.buildSteps
    $existing.agent.plan.steps = [int]$settings.opencode.planSteps
    $existing.agent.general.steps = [int]$settings.opencode.generalSteps
    $existing.agent.explore.steps = [int]$settings.opencode.exploreSteps

    $existing | ConvertTo-Json -Depth 20 | Set-Content -Path $configPath -Encoding UTF8
    return $configPath
}
