$ErrorActionPreference = "Stop"

function Get-WindowsPowerShellExe {
    $path = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path $path)) {
        throw "Windows PowerShell nije pronadjen na ocekivanoj putanji: $path"
    }
    return $path
}

function Write-Utf8NoBomText {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $directory = Split-Path -Parent $Path
    if ($directory) {
        Ensure-Directory $directory
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Get-LocalQwenCodeRoot {
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
            (Test-Path (Join-Path $resolved "config\profiles\defaults.json")) -or
            (Test-Path (Join-Path $resolved "scripts\local_qwen_runtime.py")) -or
            (Test-Path (Join-Path $resolved "launchers"))
        ) {
            return $resolved
        }
    }

    return (Resolve-Path $twoLevelsUp).Path
}

function Get-LocalQwenStateRoot {
    $codeRoot = Get-LocalQwenCodeRoot
    $installedRoot = Join-Path $env:USERPROFILE "LocalQwenHome"

    if (Test-Path (Join-Path $codeRoot "state\install-state.json")) {
        return $codeRoot
    }

    if (Test-Path (Join-Path $installedRoot "state\install-state.json")) {
        return (Resolve-Path $installedRoot).Path
    }

    return $codeRoot
}

function Get-LocalQwenRoot {
    return Get-LocalQwenCodeRoot
}

function Get-InstallState {
    $root = Get-LocalQwenStateRoot
    $statePath = Join-Path $root "state\install-state.json"
    if (!(Test-Path $statePath)) {
        throw "Install state nije pronadjen: $statePath"
    }

    return Get-Content -Raw $statePath | ConvertFrom-Json
}

function Get-StateModelFilePath {
    param(
        [Parameter(Mandatory = $true)]$State
    )

    if ($State.PSObject.Properties["modelFile"] -and -not [string]::IsNullOrWhiteSpace([string]$State.modelFile)) {
        return [string]$State.modelFile
    }

    if ($State.PSObject.Properties["modelPath"] -and -not [string]::IsNullOrWhiteSpace([string]$State.modelPath)) {
        return [string]$State.modelPath
    }

    $installRoot = if ($State.PSObject.Properties["installRoot"] -and -not [string]::IsNullOrWhiteSpace([string]$State.installRoot)) {
        [string]$State.installRoot
    } else {
        Get-LocalQwenStateRoot
    }

    $modelId = if ($State.PSObject.Properties["modelId"] -and -not [string]::IsNullOrWhiteSpace([string]$State.modelId)) {
        [string]$State.modelId
    } else {
        $null
    }

    if ($modelId) {
        return Join-Path (Join-Path $installRoot "models") $modelId
    }

    return Join-Path $installRoot "models"
}

function Save-InstallState {
    param([Parameter(Mandatory = $true)]$State)

    $root = Get-LocalQwenStateRoot
    $statePath = Join-Path $root "state\install-state.json"
    Write-Utf8NoBomText -Path $statePath -Content ($State | ConvertTo-Json -Depth 20)
}

function Get-Defaults {
    $root = Get-LocalQwenCodeRoot
    $defaultsPath = Join-Path $root "config\profiles\defaults.json"
    if (!(Test-Path $defaultsPath)) {
        throw "Defaults config nije pronadjen: $defaultsPath"
    }

    return Get-Content -Raw $defaultsPath | ConvertFrom-Json
}

function Get-CustomModelsRegistryPath {
    $root = Get-LocalQwenStateRoot
    return Join-Path $root "state\custom-models.json"
}

function Get-CustomModels {
    $path = Get-CustomModelsRegistryPath
    if (-not (Test-Path $path)) {
        return @()
    }

    try {
        $payload = Get-Content -Raw $path | ConvertFrom-Json
        if ($payload -is [System.Array]) {
            return @($payload)
        }
        if ($payload -and $payload.models) {
            return @($payload.models)
        }
    } catch {
    }

    return @()
}

function Save-CustomModels {
    param(
        [Parameter(Mandatory = $true)][object[]]$Models
    )

    $path = Get-CustomModelsRegistryPath
    Ensure-Directory (Split-Path -Parent $path)
    Write-Utf8NoBomText -Path $path -Content (
        [pscustomobject]@{
            updatedAt = (Get-Date).ToUniversalTime().ToString("o")
            models = @($Models)
        } | ConvertTo-Json -Depth 20
    )
    return $path
}

function Get-EffectiveDefaultsPath {
    $defaults = Get-Defaults
    $customModels = @(Get-CustomModels)
    $defaultsPath = Join-Path (Get-LocalQwenCodeRoot) "config\profiles\defaults.json"

    if ($customModels.Count -eq 0) {
        return $defaultsPath
    }

    if (-not $defaults.PSObject.Properties["modelChoices"]) {
        $defaults | Add-Member -NotePropertyName "modelChoices" -NotePropertyValue ([ordered]@{})
    }

    foreach ($item in $customModels) {
        if (-not $item) {
            continue
        }
        $key = if ($item.PSObject.Properties["key"] -and $item.key) {
            [string]$item.key
        } else {
            ([string]$item.id -replace '[^a-zA-Z0-9_-]', '_')
        }
        $defaults.modelChoices | Add-Member -NotePropertyName $key -NotePropertyValue $item -Force
    }

    $path = Join-Path (Get-LocalQwenStateRoot) "state\effective-defaults.json"
    Ensure-Directory (Split-Path -Parent $path)
    Write-Utf8NoBomText -Path $path -Content ($defaults | ConvertTo-Json -Depth 20)
    return $path
}

function Get-RuntimeEngineScriptPath {
    $root = Get-LocalQwenCodeRoot
    $path = Join-Path $root "scripts\local_qwen_runtime.py"
    if (Test-Path $path) {
        return $path
    }
    throw "Shared runtime helper nije pronadjen: $path"
}

function Get-Settings {
    $root = Get-LocalQwenStateRoot
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

    $root = Get-LocalQwenStateRoot
    $settingsPath = Join-Path $root "state\settings.json"
    Write-Utf8NoBomText -Path $settingsPath -Content ($Settings | ConvertTo-Json -Depth 20)
}

function Get-VersionFilePath {
    $root = Get-LocalQwenCodeRoot
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
    $root = Get-LocalQwenCodeRoot
    foreach ($candidate in @(
        (Join-Path $root "release-notes.txt"),
        (Join-Path $root "docs\release-notes.txt")
    )) {
        if (Test-Path $candidate) {
            return $candidate
        }
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

function Get-FormattedReleaseNotesText {
    $raw = Get-ReleaseNotesText
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return "Release notes nisu dostupne."
    }

    $lines = $raw -split "(`r`n|`n|`r)"
    $formatted = New-Object System.Collections.Generic.List[string]
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            $formatted.Add("") | Out-Null
            continue
        }

        if ($trimmed -match '^v\d') {
            $formatted.Add($trimmed) | Out-Null
            continue
        }

        if ($trimmed -like '- *') {
            $formatted.Add(("• " + $trimmed.Substring(2).Trim())) | Out-Null
            continue
        }

        $formatted.Add($trimmed) | Out-Null
    }

    return ($formatted -join [Environment]::NewLine)
}

function Get-GitHubRepositorySlug {
    return "joes021/Local-Qwen-3.635Ba3B-on-home-computer"
}

function Get-OpenCodeConfigPath {
    return Join-Path $env:USERPROFILE ".config\opencode\opencode.json"
}

function Get-OpenCodeExecutable {
    $commandCandidates = @("opencode.cmd", "opencode.ps1", "opencode", "opencode.exe")
    foreach ($candidate in $commandCandidates) {
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($command -and $command.Source -and (Test-Path $command.Source)) {
            return $command.Source
        }
    }

    $pathCandidates = New-Object System.Collections.Generic.List[string]
    foreach ($base in @(
        (Join-Path $env:APPDATA "npm"),
        (Join-Path $env:USERPROFILE "AppData\Roaming\npm")
    )) {
        if ($base) {
            $pathCandidates.Add((Join-Path $base "opencode.cmd")) | Out-Null
            $pathCandidates.Add((Join-Path $base "opencode.ps1")) | Out-Null
            $pathCandidates.Add((Join-Path $base "opencode")) | Out-Null
        }
    }

    if (Get-Command npm -ErrorAction SilentlyContinue) {
        try {
            $prefix = (& npm prefix -g 2>$null | Select-Object -Last 1)
            if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]$prefix)) {
                $base = ([string]$prefix).Trim()
                foreach ($leaf in @("opencode.cmd", "opencode.ps1", "opencode")) {
                    $pathCandidates.Add((Join-Path $base $leaf)) | Out-Null
                }
            }
        } catch {
        }
    }

    foreach ($path in ($pathCandidates | Select-Object -Unique)) {
        if ($path -and (Test-Path $path)) {
            return $path
        }
    }

    throw "OpenCode nije pronadjen. Proveri globalnu npm instalaciju ili PATH."
}

function Test-OpenCodeAvailable {
    try {
        [void](Get-OpenCodeExecutable)
        return $true
    } catch {
        return $false
    }
}

function Get-DesktopTargetDir {
    $state = Get-InstallState
    if ($state.PSObject.Properties["desktopTargetDir"] -and $state.desktopTargetDir) {
        return [string]$state.desktopTargetDir
    }
    return (Join-Path $env:USERPROFILE "Desktop\Local Qwen Home Computer")
}

function Get-DesktopShortcutNames {
    return @(
        "Local Qwen Control Center.lnk",
        "OpenCode - Local Qwen.lnk",
        "Verify Local Qwen Install.lnk",
        "Repair Local Qwen Install.lnk",
        "Test Local Qwen Prompt.lnk",
        "Update Local Qwen.lnk",
        "Uninstall Local Qwen.lnk"
    )
}

function Get-LogDirectory {
    $state = Get-InstallState
    $logDir = Join-Path $state.installRoot "logs"
    Ensure-Directory $logDir
    return $logDir
}

function Get-ServiceLifecyclePath {
    $root = Get-LocalQwenStateRoot
    return (Join-Path $root "state\server-lifecycle.json")
}

function Set-ServiceLifecycleState {
    param(
        [Parameter(Mandatory = $true)][string]$State,
        [string]$Profile,
        [string]$StdOut,
        [string]$StdErr,
        [string]$Reason
    )

    $path = Get-ServiceLifecyclePath
    Ensure-Directory (Split-Path -Parent $path)
    $payload = [ordered]@{
        state = $State
        profile = $Profile
        stdout = $StdOut
        stderr = $StdErr
        reason = $Reason
        updatedAt = (Get-Date).ToString("s")
    }
    Write-Utf8NoBomText -Path $path -Content ($payload | ConvertTo-Json -Depth 10)
}

function Get-ServiceLifecycleState {
    $path = Get-ServiceLifecyclePath
    if (Test-Path $path) {
        try {
            return Get-Content -Raw $path | ConvertFrom-Json
        } catch {
        }
    }

    return [pscustomobject]@{
        state = "inactive"
        profile = $null
        stdout = $null
        stderr = $null
        reason = $null
        updatedAt = $null
    }
}

function Get-LatestLlamaLogs {
    $logDir = Get-LogDirectory
    $stdout = Get-ChildItem $logDir -Filter "llama-*.out.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $stderr = Get-ChildItem $logDir -Filter "llama-*.err.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $installSummary = Join-Path (Get-LocalQwenStateRoot) "state\install-summary.txt"
    $installReport = Join-Path (Get-LocalQwenStateRoot) "state\install-report.json"

    return [pscustomobject]@{
        LogDir = $logDir
        StdOut = if ($stdout) { $stdout.FullName } else { $null }
        StdErr = if ($stderr) { $stderr.FullName } else { $null }
        InstallSummary = if (Test-Path $installSummary) { $installSummary } else { $null }
        InstallReport = if (Test-Path $installReport) { $installReport } else { $null }
    }
}

function Get-DiagnosticsDirectory {
    $root = Get-LocalQwenStateRoot
    $path = Join-Path $root "state\diagnostics"
    Ensure-Directory $path
    return $path
}

function Get-InstallSummaryPath {
    $root = Get-LocalQwenStateRoot
    return Join-Path $root "state\install-summary.txt"
}

function Get-RepairSummaryPath {
    $root = Get-LocalQwenStateRoot
    return Join-Path $root "state\repair-summary.json"
}

function Get-RepairSummaryData {
    $path = Get-RepairSummaryPath
    if (Test-Path $path) {
        try {
            return Get-Content -Raw $path | ConvertFrom-Json
        } catch {
            return $null
        }
    }
    return $null
}

function Get-TokenMetricsHistoryPath {
    $root = Get-LocalQwenStateRoot
    return Join-Path $root "state\token-metrics-history.json"
}

function Get-ModelDownloadProgressPath {
    $root = Get-LocalQwenStateRoot
    return Join-Path $root "state\model-download-progress.json"
}

function Clear-ModelDownloadProgress {
    $path = Get-ModelDownloadProgressPath
    if (Test-Path $path) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
}

function Get-ModelDownloadProgressData {
    $path = Get-ModelDownloadProgressPath
    if (Test-Path $path) {
        try {
            return Get-Content -Raw $path | ConvertFrom-Json
        } catch {
            return $null
        }
    }
    return $null
}

function Update-TokenMetricsFromLatestLogs {
    $latestLogs = Get-LatestLlamaLogs
    if (-not $latestLogs.StdErr -or -not (Test-Path $latestLogs.StdErr)) {
        return $null
    }

    try {
        return Invoke-RuntimeEngineJson -Arguments @(
            "log-token-metrics",
            "--log-file", $latestLogs.StdErr,
            "--history-file", (Get-TokenMetricsHistoryPath),
            "--label", "live-log"
        )
    } catch {
        return $null
    }
}

function Get-TokenMetricsSummary {
    $liveSummary = Update-TokenMetricsFromLatestLogs
    if ($liveSummary) {
        return $liveSummary
    }

    $path = Get-TokenMetricsHistoryPath
    $history = @()
    if (Test-Path $path) {
        try {
            $loaded = Get-Content -Raw $path | ConvertFrom-Json
            if ($loaded) {
                $history = @($loaded)
            }
        } catch {
            $history = @()
        }
    }

    $current = if ($history.Count -gt 0) { $history[-1] } else { $null }
    $avgPrompt = 0.0
    $avgCompletion = 0.0
    $avgTotal = 0.0
    if ($history.Count -gt 0) {
        $avgPrompt = (($history | Measure-Object -Property promptTokensPerSecond -Average).Average)
        $avgCompletion = (($history | Measure-Object -Property completionTokensPerSecond -Average).Average)
        $avgTotal = (($history | Measure-Object -Property totalTokensPerSecond -Average).Average)
    }

    return [pscustomobject]@{
        current = $current
        history = @($history | Select-Object -Last 5)
        historyCount = $history.Count
        averages = [pscustomobject]@{
            promptTokensPerSecond = [math]::Round([double]$avgPrompt, 2)
            completionTokensPerSecond = [math]::Round([double]$avgCompletion, 2)
            totalTokensPerSecond = [math]::Round([double]$avgTotal, 2)
        }
    }
}

function Ensure-Directory {
    param([string]$Path)
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Invoke-NativeChecked {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(ValueFromRemainingArguments = $true)][string[]]$ArgumentList
    )

    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "Komanda nije uspela: $FilePath $($ArgumentList -join ' ')"
    }
}

function Get-PythonLauncher {
    $commandCandidates = @(
        @{ Command = "py"; Arguments = @("-3") },
        @{ Command = "python"; Arguments = @() },
        @{ Command = "python3"; Arguments = @() }
    )

    foreach ($candidate in $commandCandidates) {
        if (Get-Command $candidate.Command -ErrorAction SilentlyContinue) {
            try {
                $output = & $candidate.Command @($candidate.Arguments + @("-c", "import sys; print(sys.executable)")) 2>$null
                if ($LASTEXITCODE -eq 0) {
                    $resolved = [string]($output | Select-Object -Last 1)
                    if (-not [string]::IsNullOrWhiteSpace($resolved) -and (Test-Path $resolved.Trim())) {
                        return [pscustomobject]@{
                            Command = $resolved.Trim()
                            Arguments = @()
                        }
                    }
                }
            } catch {
            }
        }
    }

    return $null
}

function Invoke-RuntimeEngineJson {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $python = Get-PythonLauncher
    if (-not $python) {
        throw "Python nije pronadjen u PATH-u."
    }

    $scriptPath = Get-RuntimeEngineScriptPath
    $output = & $python.Command @($python.Arguments + @($scriptPath) + $Arguments)
    if ($LASTEXITCODE -ne 0) {
        throw "Shared runtime helper nije uspeo za: $($Arguments -join ' ')"
    }

    return ($output | Out-String | ConvertFrom-Json)
}

function Add-OptionalRuntimeArgument {
    param(
        [Parameter(Mandatory = $true)][System.Collections.Generic.List[string]]$ArgumentList,
        [Parameter(Mandatory = $true)][string]$Flag,
        [string]$Value
    )

    if (-not [string]::IsNullOrWhiteSpace($Value)) {
        $ArgumentList.Add($Flag) | Out-Null
        $ArgumentList.Add($Value) | Out-Null
    }
}

function Convert-CollectionToJsonArrayString {
    param($Collection)

    $items = New-Object System.Collections.ArrayList
    if ($null -ne $Collection) {
        foreach ($item in $Collection) {
            [void]$items.Add($item)
        }
    }
    if ($items.Count -eq 0) {
        return "[]"
    }

    return (@($items.ToArray()) | ConvertTo-Json -Depth 10 -Compress)
}

function Convert-CollectionToCliListArgument {
    param($Collection)

    $items = New-Object System.Collections.ArrayList
    if ($null -ne $Collection) {
        foreach ($item in $Collection) {
            $text = [string]$item
            if (-not [string]::IsNullOrWhiteSpace($text)) {
                [void]$items.Add($text)
            }
        }
    }
    if ($items.Count -eq 0) {
        return ""
    }

    $json = (@($items.ToArray()) | ConvertTo-Json -Depth 10 -Compress)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    return ("b64:" + [Convert]::ToBase64String($bytes))
}

function Get-LlamaHealthUrl {
    $state = Get-InstallState
    return "http://127.0.0.1:$($state.port)/health"
}

function Download-LlamaCppWindowsCuda {
    param([string]$DestinationDir)

    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/ggml-org/llama.cpp/releases/latest"
    $asset = $release.assets | Where-Object { $_.name -match '^llama-.*-bin-win-cuda-12\.4-x64\.zip$' } | Select-Object -First 1
    if (-not $asset) {
        $asset = $release.assets | Where-Object { $_.name -match '^llama-.*-bin-win-cuda-13\.1-x64\.zip$' } | Select-Object -First 1
    }
    if (-not $asset) {
        throw "Nisam nasao odgovarajuci Windows CUDA release asset za llama.cpp."
    }

    $zipPath = Join-Path $env:TEMP $asset.name
    Invoke-WebRequest -UseBasicParsing -Uri $asset.browser_download_url -OutFile $zipPath
    Ensure-Directory $DestinationDir
    Expand-Archive -LiteralPath $zipPath -DestinationPath $DestinationDir -Force
    Remove-Item -LiteralPath $zipPath -Force
    Get-ChildItem -LiteralPath $DestinationDir -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
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

function Get-HardwareProfileSummary {
    param(
        [ValidateSet("speed", "balanced", "video")]
        [string]$Profile
    )

    $plan = Get-EffectiveServerPlan -Profile $Profile
    $recommendation = Get-RecommendationBundle
    $class = [string]$recommendation.detectedClass
    $recommendedProfile = [string]$recommendation.recommendedProfile
    $reason = [string]$recommendation.reason

    return [pscustomobject]@{
        DetectedClass = $class
        RecommendedProfile = $recommendedProfile
        Reason = $reason
        EffectivePlan = $plan
        RecommendedModel = $recommendation.recommendedModel
        CandidateScores = $recommendation.candidateScores
    }
}

function Get-ModelCatalog {
    $defaultsPath = Get-EffectiveDefaultsPath
    $payload = Invoke-RuntimeEngineJson -Arguments @(
        "catalog",
        "--defaults", $defaultsPath
    )
    return @($payload.models)
}

function Get-RecommendationBundle {
    $defaultsPath = Get-EffectiveDefaultsPath
    $gpuMiB = Get-DetectedGpuMemoryMiB
    $ramGiB = Get-SystemMemoryGiB
    $cpuThreads = [Environment]::ProcessorCount
    return Invoke-RuntimeEngineJson -Arguments @(
        "recommend",
        "--defaults", $defaultsPath,
        "--gpu-mib", ([string]$(if ($gpuMiB) { $gpuMiB } else { 0 })),
        "--ram-gib", ([string]$(if ($ramGiB) { $ramGiB } else { 0 })),
        "--cpu-threads", ([string]$cpuThreads)
    )
}

function Get-DownloadCandidates {
    $defaultsPath = Get-EffectiveDefaultsPath
    $gpuMiB = Get-DetectedGpuMemoryMiB
    $ramGiB = Get-SystemMemoryGiB
    $cpuThreads = [Environment]::ProcessorCount
    return Invoke-RuntimeEngineJson -Arguments @(
        "download-candidates",
        "--defaults", $defaultsPath,
        "--gpu-mib", ([string]$(if ($gpuMiB) { $gpuMiB } else { 0 })),
        "--ram-gib", ([string]$(if ($ramGiB) { $ramGiB } else { 0 })),
        "--cpu-threads", ([string]$cpuThreads)
    )
}

function Get-SettingsPresetsBundle {
    $defaultsPath = Get-EffectiveDefaultsPath
    $gpuMiB = Get-DetectedGpuMemoryMiB
    $ramGiB = Get-SystemMemoryGiB
    $cpuThreads = [Environment]::ProcessorCount
    return Invoke-RuntimeEngineJson -Arguments @(
        "settings-presets",
        "--defaults", $defaultsPath,
        "--gpu-mib", ([string]$(if ($gpuMiB) { $gpuMiB } else { 0 })),
        "--ram-gib", ([string]$(if ($ramGiB) { $ramGiB } else { 0 })),
        "--cpu-threads", ([string]$cpuThreads)
    )
}

function Get-SettingsPresetPreview {
    param(
        [Parameter(Mandatory = $true)][string]$PresetId,
        [Parameter(Mandatory = $true)][string]$CurrentProfile,
        [Parameter(Mandatory = $true)][int]$CurrentContext,
        [Parameter(Mandatory = $true)][int]$CurrentOutput,
        [Parameter(Mandatory = $true)][int]$CurrentBuild,
        [Parameter(Mandatory = $true)][int]$CurrentPlan,
        [Parameter(Mandatory = $true)][int]$CurrentGeneral,
        [Parameter(Mandatory = $true)][int]$CurrentExplore
    )

    $defaultsPath = Get-EffectiveDefaultsPath
    $gpuMiB = Get-DetectedGpuMemoryMiB
    $ramGiB = Get-SystemMemoryGiB
    $cpuThreads = [Environment]::ProcessorCount
    return Invoke-RuntimeEngineJson -Arguments @(
        "settings-preset-preview",
        "--defaults", $defaultsPath,
        "--gpu-mib", ([string]$(if ($gpuMiB) { $gpuMiB } else { 0 })),
        "--ram-gib", ([string]$(if ($ramGiB) { $ramGiB } else { 0 })),
        "--cpu-threads", ([string]$cpuThreads),
        "--preset-id", $PresetId,
        "--current-profile", $CurrentProfile,
        "--current-context", ([string]$CurrentContext),
        "--current-output", ([string]$CurrentOutput),
        "--current-build", ([string]$CurrentBuild),
        "--current-plan", ([string]$CurrentPlan),
        "--current-general", ([string]$CurrentGeneral),
        "--current-explore", ([string]$CurrentExplore)
    )
}

function Get-ModelComparePayload {
    param(
        [Parameter(Mandatory = $true)][string[]]$ModelIds
    )

    $defaultsPath = Get-EffectiveDefaultsPath
    $gpuMiB = Get-DetectedGpuMemoryMiB
    $ramGiB = Get-SystemMemoryGiB
    $cpuThreads = [Environment]::ProcessorCount
    return Invoke-RuntimeEngineJson -Arguments @(
        "model-compare",
        "--defaults", $defaultsPath,
        "--gpu-mib", ([string]$(if ($gpuMiB) { $gpuMiB } else { 0 })),
        "--ram-gib", ([string]$(if ($ramGiB) { $ramGiB } else { 0 })),
        "--cpu-threads", ([string]$cpuThreads),
        "--model-ids", ([string]($ModelIds -join ","))
    )
}

function Get-InstalledModelIds {
    $catalog = @(Get-ModelCatalog)
    $installed = New-Object System.Collections.Generic.List[string]
    $state = Get-InstallState
    $modelsDir = Split-Path -Parent (Get-StateModelFilePath -State $state)
    foreach ($item in $catalog) {
        $candidatePath = Join-Path $modelsDir ([string]$item.filename)
        if (Test-ModelFileLooksComplete -Path $candidatePath -ModelId ([string]$item.id)) {
            $installed.Add([string]$item.id) | Out-Null
        }
    }
    return @($installed)
}

function Get-InstalledModelSizeMap {
    $catalog = @(Get-ModelCatalog)
    $modelsDir = Join-Path (Get-LocalQwenStateRoot) "models"
    $sizes = [ordered]@{}

    foreach ($choice in $catalog) {
        $candidatePath = Join-Path $modelsDir ([string]$choice.filename)
        if (Test-Path $candidatePath) {
            $sizes[[string]$choice.id] = [int64](Get-Item $candidatePath).Length
        }
    }

    return $sizes
}

function Get-ModelsDriveFreeGiB {
    $modelsDir = Join-Path (Get-LocalQwenStateRoot) "models"
    Ensure-Directory $modelsDir
    try {
        $rootPath = [System.IO.Path]::GetPathRoot($modelsDir)
        $drive = [System.IO.DriveInfo]::new($rootPath)
        return [math]::Round(($drive.AvailableFreeSpace / 1GB), 2)
    } catch {
        return $null
    }
}

function Get-FilteredModelCatalog {
    param(
        [switch]$VerifiedOnly,
        [switch]$CoderOnly,
        [switch]$FitOnly
    )

    $defaultsPath = Get-EffectiveDefaultsPath
    $gpuMiB = Get-DetectedGpuMemoryMiB
    $ramGiB = Get-SystemMemoryGiB
    $cpuThreads = [Environment]::ProcessorCount
    $arguments = [System.Collections.Generic.List[string]]::new()
    @(
        "filter-models",
        "--defaults", $defaultsPath,
        "--gpu-mib", ([string]$(if ($gpuMiB) { $gpuMiB } else { 0 })),
        "--ram-gib", ([string]$(if ($ramGiB) { $ramGiB } else { 0 })),
        "--cpu-threads", ([string]$cpuThreads)
    ) | ForEach-Object { $arguments.Add($_) | Out-Null }
    if ($VerifiedOnly) {
        $arguments.Add("--verified-only") | Out-Null
    }
    if ($CoderOnly) {
        $arguments.Add("--coder-only") | Out-Null
    }
    if ($FitOnly) {
        $arguments.Add("--fit-only") | Out-Null
    }

    return Invoke-RuntimeEngineJson -Arguments @($arguments.ToArray())
}

function Get-ModelBrowserPayload {
    param(
        [string]$Search = "",
        [string]$Family = "",
        [switch]$InstalledOnly,
        [switch]$RecommendedOnly,
        [switch]$FitOnly,
        [switch]$CoderOnly,
        [switch]$VerifiedOnly
    )

    $defaultsPath = Get-EffectiveDefaultsPath
    $gpuMiB = Get-DetectedGpuMemoryMiB
    $ramGiB = Get-SystemMemoryGiB
    $cpuThreads = [Environment]::ProcessorCount
    $state = Get-InstallState
    $freeDiskGiB = Get-ModelsDriveFreeGiB
    $sizeMap = Get-InstalledModelSizeMap
    $installedModelIds = [string]((Get-InstalledModelIds) -join ",")
    $arguments = [System.Collections.Generic.List[string]]::new()
    @(
        "model-browser",
        "--defaults", $defaultsPath,
        "--gpu-mib", ([string]$(if ($gpuMiB) { $gpuMiB } else { 0 })),
        "--ram-gib", ([string]$(if ($ramGiB) { $ramGiB } else { 0 })),
        "--cpu-threads", ([string]$cpuThreads),
        "--installed-model-sizes-json", ($sizeMap | ConvertTo-Json -Compress),
        "--free-disk-gib", ([string]$(if ($null -ne $freeDiskGiB) { $freeDiskGiB } else { -1 }))
    ) | ForEach-Object { $arguments.Add($_) | Out-Null }
    Add-OptionalRuntimeArgument -ArgumentList $arguments -Flag "--current-model-id" -Value ([string]$state.modelId
    )
    Add-OptionalRuntimeArgument -ArgumentList $arguments -Flag "--installed-model-ids" -Value $installedModelIds
    if (-not [string]::IsNullOrWhiteSpace($Search)) {
        $arguments.Add("--search") | Out-Null
        $arguments.Add($Search) | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace($Family)) {
        $arguments.Add("--family") | Out-Null
        $arguments.Add($Family) | Out-Null
    }
    if ($InstalledOnly) { $arguments.Add("--installed-only") | Out-Null }
    if ($RecommendedOnly) { $arguments.Add("--recommended-only") | Out-Null }
    if ($FitOnly) { $arguments.Add("--fit-only") | Out-Null }
    if ($CoderOnly) { $arguments.Add("--coder-only") | Out-Null }
    if ($VerifiedOnly) { $arguments.Add("--verified-only") | Out-Null }

    $payload = Invoke-RuntimeEngineJson -Arguments @($arguments.ToArray())
    if ($payload -and $payload.models) {
        foreach ($model in @($payload.models)) {
            $modelId = [string]$model.id
            if ($sizeMap.Contains($modelId)) {
                $installedBytes = [int64]$sizeMap[$modelId]
                $model.installedSizeBytes = $installedBytes
                $model.installedSizeGiB = [math]::Round(($installedBytes / 1GB), 2)
                $diskNeededBytes = [math]::Max(0, [int64]$model.diskNeededBytes - $installedBytes)
                $model.diskNeededBytes = $diskNeededBytes
                $model.diskNeededGiB = [math]::Round(($diskNeededBytes / 1GB), 2)
                $model.hasEnoughDisk = if ($null -eq $freeDiskGiB) { $true } else { ([double]$freeDiskGiB -ge [double]$model.diskNeededGiB) }
            }
        }
    }

    return $payload
}

function Get-LatestReleaseInfo {
    $currentVersion = Get-AppVersion
    return Invoke-RuntimeEngineJson -Arguments @(
        "latest-release",
        "--repo", (Get-GitHubRepositorySlug),
        "--current-version", $currentVersion
    )
}

function Get-EffectiveServiceStatus {
    $health = Test-LlamaHealth
    $lifecycle = Get-ServiceLifecycleState
    $summary = Invoke-RuntimeEngineJson -Arguments @(
        "service-status",
        "--has-health", ([string]$health).ToLower(),
        "--lifecycle-state", ([string]$lifecycle.state)
    )

    return [pscustomobject]@{
        Health = $health
        Lifecycle = $lifecycle
        Summary = $summary
    }
}

function Get-OnboardingChecklist {
    $state = Get-InstallState
    $hasServer = Test-LlamaHealth
    $hasModel = $false
    $modelPath = Get-StateModelFilePath -State $state
    try {
        $hasModel = Test-ModelFileLooksComplete -Path $modelPath
    } catch {
        $hasModel = $false
    }
    $configPath = Get-OpenCodeConfigPath
    $profile = [string](Get-Settings).profile

    $arguments = [System.Collections.Generic.List[string]]::new()
    @(
        "onboarding-checklist",
        "--has-server", ([string]$hasServer).ToLower(),
        "--has-model", ([string]$hasModel).ToLower(),
        "--has-opencode-config", ([string](Test-Path $configPath)).ToLower()
    ) | ForEach-Object { $arguments.Add($_) | Out-Null }
    Add-OptionalRuntimeArgument -ArgumentList $arguments -Flag "--profile" -Value $profile
    Add-OptionalRuntimeArgument -ArgumentList $arguments -Flag "--model-id" -Value ([string]$state.modelId)
    return Invoke-RuntimeEngineJson -Arguments @($arguments.ToArray())
}

function Get-HealthCenterData {
    $state = Get-InstallState
    $health = Test-LlamaHealth
    $hasModel = $false
    $modelPath = Get-StateModelFilePath -State $state
    try {
        $hasModel = Test-ModelFileLooksComplete -Path $modelPath
    } catch {
        $hasModel = $false
    }

    $runtimeOk = $false
    try {
        $runtimeOk = Test-Path (Get-LlamaServerExe)
    } catch {
        $runtimeOk = $false
    }

    $reportPath = Join-Path (Get-LocalQwenStateRoot) "state\install-report.json"
    $warnings = Get-EffectiveInstallWarnings -HealthOk:$health
    $warningsJson = Convert-CollectionToCliListArgument -Collection $warnings

    $arguments = [System.Collections.Generic.List[string]]::new()
    @(
        "health-center",
        "--has-server", ([string]$health).ToLower(),
        "--has-model", ([string]$hasModel).ToLower(),
        "--has-runtime", ([string]$runtimeOk).ToLower(),
        "--has-opencode-config", ([string](Test-Path (Get-OpenCodeConfigPath))).ToLower(),
        "--has-install-report", ([string](Test-Path $reportPath)).ToLower()
    ) | ForEach-Object { $arguments.Add($_) | Out-Null }
    if (-not [string]::IsNullOrWhiteSpace($warningsJson)) {
        $arguments.Add("--warnings-json") | Out-Null
        $arguments.Add($warningsJson) | Out-Null
    }
    $lifecycleState = [string](Get-ServiceLifecycleState).state
    if (-not [string]::IsNullOrWhiteSpace($lifecycleState)) {
        $arguments.Add("--lifecycle-state") | Out-Null
        $arguments.Add($lifecycleState) | Out-Null
    }
    $currentModelId = [string]$state.modelId
    if (-not [string]::IsNullOrWhiteSpace($currentModelId)) {
        $arguments.Add("--model-id") | Out-Null
        $arguments.Add($currentModelId) | Out-Null
    }
    $currentProfile = [string](Get-Settings).profile
    if (-not [string]::IsNullOrWhiteSpace($currentProfile)) {
        $arguments.Add("--profile") | Out-Null
        $arguments.Add($currentProfile) | Out-Null
    }
    return Invoke-RuntimeEngineJson -Arguments @($arguments.ToArray())
}

function Get-RepairPlanData {
    $state = Get-InstallState
    $health = Test-LlamaHealth
    $hasModel = $false
    $modelPath = Get-StateModelFilePath -State $state
    try {
        $hasModel = Test-ModelFileLooksComplete -Path $modelPath
    } catch {
        $hasModel = $false
    }

    $runtimeOk = $false
    try {
        $runtimeOk = Test-Path (Get-LlamaServerExe)
    } catch {
        $runtimeOk = $false
    }

    $reportPath = Join-Path (Get-LocalQwenStateRoot) "state\install-report.json"
    $warnings = Get-EffectiveInstallWarnings -HealthOk:$health
    $warningsJson = Convert-CollectionToCliListArgument -Collection $warnings

    $arguments = [System.Collections.Generic.List[string]]::new()
    @(
        "repair-plan",
        "--has-server", ([string]$health).ToLower(),
        "--has-model", ([string]$hasModel).ToLower(),
        "--has-runtime", ([string]$runtimeOk).ToLower(),
        "--has-opencode-config", ([string](Test-Path (Get-OpenCodeConfigPath))).ToLower(),
        "--has-install-report", ([string](Test-Path $reportPath)).ToLower()
    ) | ForEach-Object { $arguments.Add($_) | Out-Null }
    if (-not [string]::IsNullOrWhiteSpace($warningsJson)) {
        $arguments.Add("--warnings-json") | Out-Null
        $arguments.Add($warningsJson) | Out-Null
    }
    $lifecycleState = [string](Get-ServiceLifecycleState).state
    if (-not [string]::IsNullOrWhiteSpace($lifecycleState)) {
        $arguments.Add("--lifecycle-state") | Out-Null
        $arguments.Add($lifecycleState) | Out-Null
    }
    $currentModelId = [string]$state.modelId
    if (-not [string]::IsNullOrWhiteSpace($currentModelId)) {
        $arguments.Add("--model-id") | Out-Null
        $arguments.Add($currentModelId) | Out-Null
    }
    $currentProfile = [string](Get-Settings).profile
    if (-not [string]::IsNullOrWhiteSpace($currentProfile)) {
        $arguments.Add("--profile") | Out-Null
        $arguments.Add($currentProfile) | Out-Null
    }
    return Invoke-RuntimeEngineJson -Arguments @($arguments.ToArray())
}

function Get-InstallReportObject {
    $reportPath = Join-Path (Get-LocalQwenStateRoot) "state\install-report.json"
    if (-not (Test-Path $reportPath)) {
        return $null
    }
    try {
        return (Get-Content -Raw $reportPath | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Test-IsHistoricalAppControlWarning {
    param(
        [Parameter(Mandatory = $true)][string]$WarningText
    )
    $normalized = [string]$WarningText
    $normalized = $normalized.ToLowerInvariant()
    return ($normalized -like "*wdac*") -or ($normalized -like "*app control*")
}

function Get-EffectiveInstallWarnings {
    param(
        [bool]$HealthOk = $false
    )

    $report = Get-InstallReportObject
    if (-not $report) {
        return @()
    }

    $warnings = @()
    if ($report.PSObject.Properties["warnings"] -and $report.warnings) {
        $warnings = @($report.warnings)
    }
    if (-not $HealthOk) {
        return $warnings
    }

    return @($warnings | Where-Object { -not (Test-IsHistoricalAppControlWarning -WarningText ([string]$_)) })
}

function Get-SanitizedInstallReportJson {
    param(
        [bool]$HealthOk = $false
    )

    $report = Get-InstallReportObject
    if (-not $report) {
        return $null
    }
    $report.warnings = @(Get-EffectiveInstallWarnings -HealthOk:$HealthOk)
    return ($report | ConvertTo-Json -Depth 10)
}

function Get-NextActionRecommendation {
    $state = Get-InstallState
    $hasServer = Test-LlamaHealth
    $hasModel = $false
    $modelPath = Get-StateModelFilePath -State $state
    try {
        $hasModel = Test-ModelFileLooksComplete -Path $modelPath
    } catch {
        $hasModel = $false
    }
    $configPath = Get-OpenCodeConfigPath

    return Invoke-RuntimeEngineJson -Arguments @(
        "next-action",
        "--has-server", ([string]$hasServer).ToLower(),
        "--has-model", ([string]$hasModel).ToLower(),
        "--has-opencode-config", ([string](Test-Path $configPath)).ToLower()
    )
}

function Get-AgentAudit {
    param(
        [Parameter(Mandatory = $true)][string]$SecurityMode,
        [Parameter(Mandatory = $true)][string]$CapabilityMode,
        [Parameter(Mandatory = $true)][string]$WorkingFolder
    )

    return Invoke-RuntimeEngineJson -Arguments @(
        "agent-audit",
        "--security-mode", $SecurityMode,
        "--capability-mode", $CapabilityMode,
        "--working-folder", $WorkingFolder
    )
}

function Get-ModelMetadata {
    param([string]$ModelId = $null)

    if (-not $ModelId) {
        $ModelId = [string](Get-InstallState).modelId
    }

    foreach ($candidate in @(Get-ModelCatalog)) {
        if ($candidate.id -eq $ModelId -or $candidate.filename -eq $ModelId) {
            return $candidate
        }
    }

    return $null
}

function Add-OrUpdateCustomModel {
    param(
        [Parameter(Mandatory = $true)][pscustomobject]$Model
    )

    $models = New-Object System.Collections.ArrayList
    $replaced = $false
    foreach ($item in @(Get-CustomModels)) {
        if ($item -and [string]$item.id -eq [string]$Model.id) {
            [void]$models.Add($Model)
            $replaced = $true
        } else {
            [void]$models.Add($item)
        }
    }
    if (-not $replaced) {
        [void]$models.Add($Model)
    }
    Save-CustomModels -Models @($models.ToArray())
    return $Model
}

function Import-LocalGgufModel {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [string]$Label = "",
        [string]$Family = "Custom"
    )

    if (-not (Test-Path $SourcePath)) {
        throw "Lokalni GGUF nije pronadjen: $SourcePath"
    }
    if ([System.IO.Path]::GetExtension($SourcePath).ToLowerInvariant() -ne ".gguf") {
        throw "Podrzani su samo .gguf fajlovi."
    }

    $modelsDir = Join-Path (Get-LocalQwenStateRoot) "models"
    Ensure-Directory $modelsDir
    $file = Get-Item $SourcePath
    $fileName = $file.Name
    $targetPath = Join-Path $modelsDir $fileName
    if ($file.FullName -ne $targetPath) {
        Copy-Item -LiteralPath $file.FullName -Destination $targetPath -Force
    }

    $friendlyLabel = if ([string]::IsNullOrWhiteSpace($Label)) { [System.IO.Path]::GetFileNameWithoutExtension($fileName) } else { $Label.Trim() }
    $sizeBytes = [int64](Get-Item $targetPath).Length
    $model = [pscustomobject]@{
        key = ([System.IO.Path]::GetFileNameWithoutExtension($fileName) -replace '[^a-zA-Z0-9_-]', '_')
        id = $fileName
        label = $friendlyLabel
        family = $(if ([string]::IsNullOrWhiteSpace($Family)) { "Custom" } else { $Family.Trim() })
        agenticScore = 6
        opencodeFit = 6
        useCase = "agentic-general"
        filename = $fileName
        minExpectedBytes = $sizeBytes
        approxSizeGiB = [math]::Round(($sizeBytes / 1GB), 2)
        minimumGpuMiB = 0
        recommendedGpuMiB = 0
        minimumRamGiB = 8
        preferredProfiles = @("speed", "balanced")
        qualityTier = "compact"
        curationLevel = "custom"
        description = "Rucno dodat lokalni GGUF model."
        customSource = "local-file"
        originalPath = $file.FullName
        sources = @()
    }
    Add-OrUpdateCustomModel -Model $model | Out-Null
    return $model
}

function Add-HuggingFaceCustomModel {
    param(
        [Parameter(Mandatory = $true)][string]$Repo,
        [Parameter(Mandatory = $true)][string]$FileName,
        [string]$Label = "",
        [string]$Family = "Custom"
    )

    $repoText = $Repo.Trim()
    $fileNameText = $FileName.Trim()
    if ([string]::IsNullOrWhiteSpace($repoText) -or [string]::IsNullOrWhiteSpace($fileNameText)) {
        throw "Repo i filename su obavezni."
    }
    if ([System.IO.Path]::GetExtension($fileNameText).ToLowerInvariant() -ne ".gguf") {
        throw "HF model mora da pokazuje na .gguf fajl."
    }

    $url = "https://huggingface.co/$repoText/resolve/main/$fileNameText"
    $sizeBytes = 0
    try {
        $response = Invoke-WebRequest -Uri $url -Method Head -MaximumRedirection 5 -ErrorAction Stop
        $headerValue = $response.Headers["Content-Length"]
        if ($headerValue) {
            $sizeBytes = [int64]$headerValue
        }
    } catch {
        $sizeBytes = 0
    }

    $friendlyLabel = if ([string]::IsNullOrWhiteSpace($Label)) { [System.IO.Path]::GetFileNameWithoutExtension($fileNameText) } else { $Label.Trim() }
    $approxGiB = if ($sizeBytes -gt 0) { [math]::Round(($sizeBytes / 1GB), 2) } else { 0.0 }
    $model = [pscustomobject]@{
        key = ([System.IO.Path]::GetFileNameWithoutExtension($fileNameText) -replace '[^a-zA-Z0-9_-]', '_')
        id = $fileNameText
        label = $friendlyLabel
        family = $(if ([string]::IsNullOrWhiteSpace($Family)) { "Custom" } else { $Family.Trim() })
        agenticScore = 6
        opencodeFit = 6
        useCase = "agentic-general"
        source = $repoText
        filename = $fileNameText
        minExpectedBytes = $(if ($sizeBytes -gt 0) { [int64]([math]::Floor($sizeBytes * 0.9)) } else { 0 })
        approxSizeGiB = $approxGiB
        minimumGpuMiB = 0
        recommendedGpuMiB = 0
        minimumRamGiB = 8
        preferredProfiles = @("speed", "balanced")
        qualityTier = "compact"
        curationLevel = "custom"
        description = "Rucno dodat Hugging Face GGUF model."
        customSource = "huggingface"
        sources = @(
            [pscustomobject]@{
                repo = $repoText
                filename = $fileNameText
            }
        )
    }
    Add-OrUpdateCustomModel -Model $model | Out-Null
    return $model
}

function Set-SelectedModel {
    param([Parameter(Mandatory = $true)][string]$ModelId)

    $state = Get-InstallState
    $meta = Get-ModelMetadata -ModelId $ModelId
    if (-not $meta) {
        throw "Model nije pronadjen u katalogu: $ModelId"
    }

    $state.modelId = [string]$meta.id
    $currentModelPath = Get-StateModelFilePath -State $state
    $modelsDir = Split-Path -Parent $currentModelPath
    $resolvedModelPath = Join-Path $modelsDir ([string]$meta.filename)
    $state.modelFile = $resolvedModelPath
    $state.modelPath = $resolvedModelPath
    Save-InstallState -State $state
    return $state
}

function Test-ModelFileLooksComplete {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$ModelId = $null
    )

    if (!(Test-Path $Path)) {
        return $false
    }

    $meta = Get-ModelMetadata -ModelId $ModelId
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
    $modelPath = Get-StateModelFilePath -State $state
    if (!(Test-Path $modelPath)) {
        throw "Model nije pronadjen: $modelPath"
    }
    if (-not (Test-ModelFileLooksComplete -Path $modelPath)) {
        $file = Get-Item $modelPath
        $meta = Get-ModelMetadata
        $minExpectedBytes = if ($meta -and $meta.PSObject.Properties["minExpectedBytes"]) { [int64]$meta.minExpectedBytes } else { 0 }
        throw "Model deluje nepotpuno: $modelPath (trenutno $($file.Length) bajtova, ocekivano najmanje $minExpectedBytes)"
    }
    return $modelPath
}

function Download-RecommendedModel {
    param([string]$ModelId = $null)

    $state = Get-InstallState
    if (-not $ModelId) {
        $recommendation = Get-RecommendationBundle
        if ($recommendation.recommendedModel -and $recommendation.recommendedModel.id) {
            $ModelId = [string]$recommendation.recommendedModel.id
        } else {
            $ModelId = [string]$state.modelId
        }
    }

    $state = Set-SelectedModel -ModelId $ModelId
    $meta = Get-ModelMetadata -ModelId $ModelId
    if (-not $meta) {
        throw "Model metadata nije pronadjena za $ModelId"
    }

    $python = Get-PythonLauncher
    if (-not $python) {
        throw "Python nije pronadjen u PATH-u."
    }

    Clear-ModelDownloadProgress
    & $python.Command @($python.Arguments + @("-m", "pip", "install", "--user", "-U", "huggingface_hub"))
    if ($LASTEXITCODE -ne 0) {
        throw "huggingface_hub instalacija nije uspela."
    }

    $targetDir = Split-Path -Parent (Get-StateModelFilePath -State $state)
    Ensure-Directory $targetDir
    $tmpPy = Join-Path $env:TEMP "local_qwen_repair_model.py"
    $progressPath = Get-ModelDownloadProgressPath
    $sources = @($meta.sources)
    if ($sources.Count -eq 0 -and $meta.source) {
        $sources = @([pscustomobject]@{ repo = $meta.source; filename = $meta.filename })
    }

    $sourceJson = ($sources | ConvertTo-Json -Depth 10 -Compress)
    $code = @"
import json
import os
import time
import sys
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

sources = json.loads(r'''$sourceJson''')
local_dir = Path(r"$targetDir")
target_file = local_dir / r"$($meta.filename)"
progress_path = Path(r"$progressPath")
model_id = r"$ModelId"
min_expected_bytes = int($([int64]$meta.minExpectedBytes))
install_status_path = os.environ.get("LOCAL_QWEN_INSTALL_STATUS_PATH", "").strip()
install_stage = os.environ.get("LOCAL_QWEN_INSTALL_STAGE", "8").strip() or "8"
last_error = None

def write_progress(payload):
    progress_path.parent.mkdir(parents=True, exist_ok=True)
    progress_path.write_text(json.dumps(payload), encoding="utf-8")

def write_install_status(payload):
    if not install_status_path:
        return
    lines = [
        "[status]",
        "state=running",
        f"stageNumber={install_stage}",
        "totalStages=10",
        "stageName=Download or verify selected model",
        f"detail={payload.get('message', '')}",
        "activityType=model-download",
        f"progressPercent={payload.get('percent', '') if payload.get('percent') is not None else ''}",
        f"source={payload.get('source', '') or ''}",
        f"downloadedGiB={payload.get('downloadedGiB', '') if payload.get('downloadedGiB') is not None else ''}",
        f"totalGiB={payload.get('totalGiB', '') if payload.get('totalGiB') is not None else ''}",
        f"speedMBps={payload.get('speedMBps', '') if payload.get('speedMBps') is not None else ''}",
        f"etaSeconds={payload.get('etaSeconds', '') if payload.get('etaSeconds') is not None else ''}",
        f"modelStatus={payload.get('status', '') or ''}",
        f"updatedAt={time.time()}",
    ]
    Path(install_status_path).write_text("\n".join(lines), encoding="utf-8")

initial_payload = {
    "status": "starting",
    "modelId": model_id,
    "fileName": target_file.name,
    "message": "Pripremam download...",
    "updatedAt": time.time(),
}
write_progress(initial_payload)
write_install_status(initial_payload)

for item in sources:
    try:
        repo = item["repo"]
        filename = item["filename"]
        url = f"https://huggingface.co/{repo}/resolve/main/{filename}"
        request = Request(url, headers={"User-Agent": "LocalQwenSetup/1.0"})
        with urlopen(request) as response:
            total_bytes = int(response.headers.get("Content-Length") or "0")
            local_dir.mkdir(parents=True, exist_ok=True)
            part_path = target_file.with_suffix(target_file.suffix + ".part")
            downloaded = 0
            started = time.time()
            next_emit = 0.0
            starting_payload = {
                "status": "downloading",
                "modelId": model_id,
                "fileName": target_file.name,
                "source": repo,
                "url": url,
                "totalBytes": total_bytes,
                "downloadedBytes": 0,
                "downloadedGiB": 0.0,
                "totalGiB": round(total_bytes / (1024 ** 3), 2) if total_bytes else None,
                "speedMBps": 0.0,
                "etaSeconds": None,
                "percent": 0.0,
                "message": f"Preuzimam {filename} sa {repo}",
                "updatedAt": started,
            }
            write_progress(starting_payload)
            write_install_status(starting_payload)
            with open(part_path, "wb") as handle:
                while True:
                    chunk = response.read(1024 * 1024)
                    if not chunk:
                        break
                    handle.write(chunk)
                    downloaded += len(chunk)
                    now = time.time()
                    if now >= next_emit:
                        elapsed = max(0.001, now - started)
                        speed_mbps = (downloaded / (1024 * 1024)) / elapsed
                        eta = None
                        percent = None
                        if total_bytes > 0:
                            remaining = max(0, total_bytes - downloaded)
                            eta = int(remaining / max(1, downloaded / elapsed))
                            percent = round((downloaded / total_bytes) * 100, 2)
                        payload = {
                            "status": "downloading",
                            "modelId": model_id,
                            "fileName": target_file.name,
                            "source": repo,
                            "url": url,
                            "totalBytes": total_bytes,
                            "downloadedBytes": downloaded,
                            "downloadedGiB": round(downloaded / (1024 ** 3), 2),
                            "totalGiB": round(total_bytes / (1024 ** 3), 2) if total_bytes else None,
                            "speedMBps": round(speed_mbps, 2),
                            "etaSeconds": eta,
                            "percent": percent,
                            "message": f"Preuzimam {filename} sa {repo}",
                            "updatedAt": now,
                        }
                        write_progress(payload)
                        write_install_status(payload)
                        next_emit = now + 1.0
            if total_bytes and downloaded < total_bytes:
                raise RuntimeError("Download je prekinut pre nego sto je sav sadrzaj stigao.")
            if downloaded < min_expected_bytes:
                raise RuntimeError(f"Model deluje nepotpuno: {downloaded} < {min_expected_bytes}")
            os.replace(part_path, target_file)
            completed_payload = {
                "status": "completed",
                "modelId": model_id,
                "fileName": target_file.name,
                "source": repo,
                "totalBytes": downloaded,
                "downloadedBytes": downloaded,
                "downloadedGiB": round(downloaded / (1024 ** 3), 2),
                "totalGiB": round(downloaded / (1024 ** 3), 2),
                "speedMBps": None,
                "etaSeconds": 0,
                "percent": 100.0,
                "message": f"Download zavrsen sa {repo}",
                "updatedAt": time.time(),
            }
            write_progress(completed_payload)
            write_install_status(completed_payload)
        print(repo)
        raise SystemExit(0)
    except (HTTPError, URLError, RuntimeError, OSError) as exc:
        last_error = exc
        retry_payload = {
            "status": "retrying",
            "modelId": model_id,
            "fileName": target_file.name,
            "source": item.get("repo"),
            "message": f"Neuspeo pokusaj sa {item.get('repo')}: {exc}",
            "updatedAt": time.time(),
        }
        write_progress(retry_payload)
        write_install_status(retry_payload)

if last_error is not None:
    failed_payload = {
        "status": "failed",
        "modelId": model_id,
        "fileName": target_file.name,
        "message": str(last_error),
        "updatedAt": time.time(),
    }
    write_progress(failed_payload)
    write_install_status(failed_payload)
    raise last_error
"@
    Set-Content -Path $tmpPy -Value $code -Encoding UTF8
    $downloadOutput = & $python.Command @($python.Arguments + @($tmpPy))
    if ($LASTEXITCODE -ne 0) {
        throw "Model download nije uspeo."
    }
    Remove-Item -LiteralPath $tmpPy -Force -ErrorAction SilentlyContinue
    return ($downloadOutput | Select-Object -Last 1)
}

function Restore-BundledSupportFiles {
    $root = Get-LocalQwenStateRoot
    $copied = New-Object System.Collections.Generic.List[string]
    $baseDir = Join-Path ${env:ProgramFiles} "LocalQwenSetupBootstrap"
    $map = @(
        @{ Source = (Join-Path $baseDir "launcher\windows"); Destination = (Join-Path $root "launchers"); Label = "launchers" },
        @{ Source = (Join-Path $baseDir "scripts"); Destination = (Join-Path $root "scripts"); Label = "scripts" },
        @{ Source = (Join-Path $baseDir "config"); Destination = (Join-Path $root "config"); Label = "config" },
        @{ Source = (Join-Path $baseDir "assets"); Destination = (Join-Path $root "assets"); Label = "assets" },
        @{ Source = (Join-Path $baseDir "release-notes.txt"); Destination = (Join-Path $root "release-notes.txt"); Label = "release-notes-root" },
        @{ Source = (Join-Path $baseDir "release-notes.txt"); Destination = (Join-Path $root "docs\release-notes.txt"); Label = "release-notes" },
        @{ Source = (Join-Path $baseDir "version.json"); Destination = (Join-Path $root "version.json"); Label = "version" }
    )

    foreach ($entry in $map) {
        if (-not (Test-Path $entry.Source)) {
            continue
        }
        Ensure-Directory (Split-Path -Parent $entry.Destination)
        if ((Get-Item $entry.Source).PSIsContainer) {
            Copy-Item -Path (Join-Path $entry.Source "*") -Destination $entry.Destination -Recurse -Force
        } else {
            Copy-Item -LiteralPath $entry.Source -Destination $entry.Destination -Force
        }
        $copied.Add([string]$entry.Label) | Out-Null
    }

    return @($copied)
}

function Invoke-TestPrompt {
    param(
        [string]$Prompt = "Reply with exactly OK",
        [int]$MaxTokens = 16,
        [string]$Label = "test-prompt"
    )

    $state = Get-InstallState
    $body = @{
        model = $state.modelId
        messages = @(
            @{
                role = "user"
                content = $Prompt
            }
        )
        max_tokens = $MaxTokens
        temperature = 0
    } | ConvertTo-Json -Depth 10

    $url = "http://127.0.0.1:$($state.port)/v1/chat/completions"
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $response = Invoke-RestMethod -Method Post -Uri $url -ContentType "application/json" -Body $body -TimeoutSec 60
    $stopwatch.Stop()

    $tmpPath = Join-Path $env:TEMP ("local-qwen-metrics-" + [guid]::NewGuid().ToString() + ".json")
    $payload = $response | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $payload | Add-Member -Force -NotePropertyName "_elapsed_ms" -NotePropertyValue ([double]$stopwatch.Elapsed.TotalMilliseconds)
    $payload | Add-Member -Force -NotePropertyName "_measured_at" -NotePropertyValue ((Get-Date).ToUniversalTime().ToString("o"))
    $payload | ConvertTo-Json -Depth 30 | Set-Content -Path $tmpPath -Encoding UTF8

    try {
        $metrics = Invoke-RuntimeEngineJson -Arguments @(
            "token-metrics",
            "--response-file", $tmpPath,
            "--history-file", (Get-TokenMetricsHistoryPath),
            "--label", $Label
        )
    } finally {
        Remove-Item -LiteralPath $tmpPath -Force -ErrorAction SilentlyContinue
    }

    return [pscustomobject]@{
        Response = $response
        Metrics = $metrics
    }
}

function Update-OpenCodeConfig {
    $state = Get-InstallState
    $settings = Get-Settings
    $defaults = Get-Defaults
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

    if (-not $existing.PSObject.Properties["permission"]) {
        $existing | Add-Member -NotePropertyName "permission" -NotePropertyValue ([pscustomobject]@{})
    }

    $webAccess = $null
    if ($defaults.PSObject.Properties["opencode"] -and $defaults.opencode.PSObject.Properties["webAccess"]) {
        $webAccess = $defaults.opencode.webAccess
    }
    $webAccessEnabled = $true
    if ($webAccess -and $webAccess.PSObject.Properties["enabled"]) {
        $webAccessEnabled = [bool]$webAccess.enabled
    }

    if ($webAccessEnabled) {
        if (-not $existing.permission.PSObject.Properties["webfetch"]) {
            $existing.permission | Add-Member -NotePropertyName "webfetch" -NotePropertyValue "allow"
        } else {
            $existing.permission.webfetch = "allow"
        }
        if (-not $existing.permission.PSObject.Properties["websearch"]) {
            $existing.permission | Add-Member -NotePropertyName "websearch" -NotePropertyValue "allow"
        } else {
            $existing.permission.websearch = "allow"
        }
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

    Write-Utf8NoBomText -Path $configPath -Content ($existing | ConvertTo-Json -Depth 20)
    return $configPath
}

function Write-InstallReport {
    $root = Get-LocalQwenStateRoot
    $state = Get-InstallState
    $reportPath = Join-Path $root "state\install-report.json"
    $logMeta = Get-LatestLlamaLogs
    $configPath = Get-OpenCodeConfigPath
    $serverExe = $null
    $openCodeExe = $null
    try {
        $serverExe = Get-LlamaServerExe
    } catch {
        $serverExe = $null
    }
    try {
        $openCodeExe = Get-OpenCodeExecutable
    } catch {
        $openCodeExe = $null
    }

    $turboServerPath = $null
    if ($state.PSObject.Properties["turboServerExe"] -and $state.turboServerExe) {
        $turboServerPath = [string]$state.turboServerExe
    } elseif ($state.PSObject.Properties["turboDir"] -and $state.turboDir) {
        $turboServerPath = Join-Path ([string]$state.turboDir) "build-cuda\bin\llama-server.exe"
    }

    $warnings = New-Object System.Collections.Generic.List[string]
    if (-not (Test-OpenCodeAvailable)) {
        $warnings.Add("OpenCode nije dostupan kroz PATH ili poznate npm global putanje.") | Out-Null
    }

    $report = [ordered]@{
        generatedAt = (Get-Date).ToString("s")
        platform = "windows"
        profile = [string](Get-Settings).profile
        installRoot = $root
        recommendation = Get-RecommendationBundle
        components = [ordered]@{
            installState = [ordered]@{
                path = (Join-Path $root "state\install-state.json")
                ok = (Test-Path (Join-Path $root "state\install-state.json"))
            }
            launchers = [ordered]@{
                path = (Join-Path $root "launchers")
                ok = (Test-Path (Join-Path $root "launchers\control-center.ps1"))
            }
            desktopShortcuts = [ordered]@{
                path = (Get-DesktopTargetDir)
                ok = (Test-Path (Join-Path (Get-DesktopTargetDir) "Local Qwen Control Center.lnk"))
            }
            llamaCppRuntime = [ordered]@{
                path = $serverExe
                ok = [bool]($serverExe -and (Test-Path $serverExe))
            }
            turboQuantRuntime = [ordered]@{
                path = $turboServerPath
                ok = [bool]($turboServerPath -and (Test-Path $turboServerPath))
            }
            model = [ordered]@{
                path = (Get-StateModelFilePath -State $state)
                ok = (Test-Path (Get-StateModelFilePath -State $state))
                sizeBytes = if (Test-Path (Get-StateModelFilePath -State $state)) { (Get-Item (Get-StateModelFilePath -State $state)).Length } else { 0 }
                selectedId = $state.modelId
                metadata = Get-ModelMetadata
            }
            opencodeCommand = [ordered]@{
                path = $openCodeExe
                ok = [bool](Test-OpenCodeAvailable)
            }
            opencodeConfig = [ordered]@{
                path = $configPath
                ok = (Test-Path $configPath)
            }
            latestLogs = [ordered]@{
                stdout = $logMeta.StdOut
                stderr = $logMeta.StdErr
            }
        }
        warnings = @($warnings)
    }

    Write-Utf8NoBomText -Path $reportPath -Content ($report | ConvertTo-Json -Depth 10)
    return $reportPath
}

function Export-DiagnosticsBundle {
    $root = Get-LocalQwenStateRoot
    $diagDir = Get-DiagnosticsDirectory
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $bundleDir = Join-Path $diagDir "bundle-$stamp"
    Ensure-Directory $bundleDir

    $pathsToCopy = @(
        (Join-Path $root "state\install-state.json"),
        (Join-Path $root "state\settings.json"),
        (Join-Path $root "state\install-report.json"),
        (Join-Path $root "state\install-summary.txt"),
        (Join-Path $root "state\repair-summary.json"),
        (Join-Path $root "state\token-metrics-history.json"),
        (Join-Path $root "version.json"),
        (Join-Path $root "release-notes.txt"),
        (Get-OpenCodeConfigPath)
    )

    foreach ($path in $pathsToCopy) {
        if ($path -and (Test-Path $path)) {
            Copy-Item -LiteralPath $path -Destination (Join-Path $bundleDir ([IO.Path]::GetFileName($path))) -Force
        }
    }

    $latestLogs = Get-LatestLlamaLogs
    foreach ($logPath in @($latestLogs.StdOut, $latestLogs.StdErr, $latestLogs.InstallSummary, $latestLogs.InstallReport)) {
        if ($logPath -and (Test-Path $logPath)) {
            Copy-Item -LiteralPath $logPath -Destination (Join-Path $bundleDir ([IO.Path]::GetFileName($logPath))) -Force
        }
    }

    $meta = [ordered]@{
        generatedAt = (Get-Date).ToString("s")
        appVersion = Get-AppVersion
        installRoot = $root
        latestRelease = Get-LatestReleaseInfo
        recommendation = Get-RecommendationBundle
        onboarding = Get-OnboardingChecklist
        hardware = [ordered]@{
            gpu = Get-PrimaryGpuInfo
            cpu = Get-CpuName
            ramGiB = Get-SystemMemoryGiB
        }
        agent = if (Test-Path (Join-Path $root "state\agent-launch-settings.json")) { Get-Content -Raw (Join-Path $root "state\agent-launch-settings.json") | ConvertFrom-Json } else { $null }
    }
    Write-Utf8NoBomText -Path (Join-Path $bundleDir "diagnostics-meta.json") -Content ($meta | ConvertTo-Json -Depth 20)

    $zipPath = Join-Path $diagDir "local-qwen-diagnostics-$stamp.zip"
    if (Test-Path $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }
    Compress-Archive -Path (Join-Path $bundleDir "*") -DestinationPath $zipPath -Force
    return $zipPath
}

function New-CmdLauncher {
    param(
        [Parameter(Mandatory = $true)][string]$LaunchersDir,
        [Parameter(Mandatory = $true)][string]$CmdName,
        [Parameter(Mandatory = $true)][string]$PsScriptName,
        [string]$ExtraArguments = ""
    )

    $cmdPath = Join-Path $LaunchersDir $CmdName
    $content = @"
@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%$PsScriptName"

if not exist "%PS_SCRIPT%" (
  echo Launcher script not found: %PS_SCRIPT%
  pause
  exit /b 1
)

"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" $ExtraArguments
set "EXITCODE=%ERRORLEVEL%"
if not "%EXITCODE%"=="0" (
  echo.
  echo Launcher failed with exit code %EXITCODE%.
  echo.
  pause
)
exit /b %EXITCODE%
"@

    Set-Content -Path $cmdPath -Value $content -Encoding ASCII
    return $cmdPath
}

function New-HiddenVbsLauncher {
    param(
        [Parameter(Mandatory = $true)][string]$LaunchersDir,
        [Parameter(Mandatory = $true)][string]$VbsName,
        [Parameter(Mandatory = $true)][string]$PsScriptName,
        [string]$ExtraArguments = ""
    )

    $vbsPath = Join-Path $LaunchersDir $VbsName
    $escapedScriptName = $PsScriptName.Replace('"', '""')
    $escapedExtraArguments = $ExtraArguments.Replace('"', '""')
    $content = @"
Dim shell, scriptDir, psScript, command, powerShellExe
Set shell = CreateObject("WScript.Shell")
scriptDir = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
psScript = scriptDir & "\$escapedScriptName"
powerShellExe = shell.ExpandEnvironmentStrings("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe")
command = """" & powerShellExe & """ -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & psScript & """ $escapedExtraArguments"
shell.Run command, 0, False
"@

    Set-Content -Path $vbsPath -Value $content -Encoding ASCII
    return $vbsPath
}

function New-DesktopShortcutFile {
    param(
        [string]$ShortcutPath,
        [string]$TargetPath,
        [string]$Arguments,
        [string]$WorkingDirectory,
        [string]$IconLocation,
        [string]$Description
    )

    $wsh = New-Object -ComObject WScript.Shell
    $shortcut = $wsh.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $TargetPath
    $shortcut.Arguments = $Arguments
    $shortcut.WorkingDirectory = $WorkingDirectory
    if ($IconLocation) { $shortcut.IconLocation = $IconLocation }
    if ($Description) { $shortcut.Description = $Description }
    $shortcut.Save()
}

function Repair-DesktopShortcuts {
    $root = Get-LocalQwenStateRoot
    $launchersDir = Join-Path $root "launchers"
    $assetsDir = Join-Path $root "assets"
    $desktopTargetDir = Get-DesktopTargetDir
    Ensure-Directory $desktopTargetDir

    $controlCenterIcon = Join-Path $assetsDir "icons\control-center.ico"
    $opencodeIcon = Join-Path $assetsDir "icons\opencode-local-qwen.ico"
    $controlCenterVbs = New-HiddenVbsLauncher -LaunchersDir $launchersDir -VbsName "open-control-center.vbs" -PsScriptName "control-center.ps1"
    $openCodeCmd = New-CmdLauncher -LaunchersDir $launchersDir -CmdName "open-opencode.cmd" -PsScriptName "start-opencode.ps1"
    $verifyCmd = New-CmdLauncher -LaunchersDir $launchersDir -CmdName "verify-install.cmd" -PsScriptName "verify-install.ps1"
    $repairCmd = New-CmdLauncher -LaunchersDir $launchersDir -CmdName "repair-install.cmd" -PsScriptName "repair-install.ps1"
    $testPromptCmd = New-CmdLauncher -LaunchersDir $launchersDir -CmdName "test-prompt.cmd" -PsScriptName "test-prompt.ps1"
    $updateCmd = New-CmdLauncher -LaunchersDir $launchersDir -CmdName "install-update.cmd" -PsScriptName "install-update.ps1"
    $uninstallCmd = New-CmdLauncher -LaunchersDir $launchersDir -CmdName "uninstall-local-qwen.cmd" -PsScriptName "uninstall.ps1"

    New-DesktopShortcutFile -ShortcutPath (Join-Path $desktopTargetDir "Local Qwen Control Center.lnk") -TargetPath "wscript.exe" -Arguments "`"$controlCenterVbs`"" -WorkingDirectory $launchersDir -IconLocation "$controlCenterIcon,0" -Description "Control center for local Qwen + OpenCode"
    New-DesktopShortcutFile -ShortcutPath (Join-Path $desktopTargetDir "OpenCode - Local Qwen.lnk") -TargetPath $env:ComSpec -Arguments "/c `"$openCodeCmd`"" -WorkingDirectory $launchersDir -IconLocation "$opencodeIcon,0" -Description "Launch OpenCode wired to local Qwen"
    New-DesktopShortcutFile -ShortcutPath (Join-Path $desktopTargetDir "Verify Local Qwen Install.lnk") -TargetPath $env:ComSpec -Arguments "/c `"$verifyCmd`"" -WorkingDirectory $launchersDir -IconLocation "$controlCenterIcon,0" -Description "Verify local Qwen installation"
    New-DesktopShortcutFile -ShortcutPath (Join-Path $desktopTargetDir "Repair Local Qwen Install.lnk") -TargetPath $env:ComSpec -Arguments "/c `"$repairCmd`"" -WorkingDirectory $launchersDir -IconLocation "$controlCenterIcon,0" -Description "Repair local Qwen install"
    New-DesktopShortcutFile -ShortcutPath (Join-Path $desktopTargetDir "Test Local Qwen Prompt.lnk") -TargetPath $env:ComSpec -Arguments "/c `"$testPromptCmd`"" -WorkingDirectory $launchersDir -IconLocation "$controlCenterIcon,0" -Description "Send a smoke-test prompt to local Qwen"
    New-DesktopShortcutFile -ShortcutPath (Join-Path $desktopTargetDir "Update Local Qwen.lnk") -TargetPath $env:ComSpec -Arguments "/c `"$updateCmd`"" -WorkingDirectory $launchersDir -IconLocation "$controlCenterIcon,0" -Description "Download and launch the latest Local Qwen installer"
    New-DesktopShortcutFile -ShortcutPath (Join-Path $desktopTargetDir "Uninstall Local Qwen.lnk") -TargetPath $env:ComSpec -Arguments "/c `"$uninstallCmd`"" -WorkingDirectory $launchersDir -IconLocation "$controlCenterIcon,0" -Description "Uninstall Local Qwen with keep-or-remove model choice"
}
