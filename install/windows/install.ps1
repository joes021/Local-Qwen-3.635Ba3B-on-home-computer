param(
    [string]$InstallRoot = "$env:USERPROFILE\LocalQwenHome",
    [string]$DesktopFolder = "$env:USERPROFILE\Desktop",
    [string]$Profile = "balanced",
    [string]$ModelId = "",
    [string]$LogPath = "",
    [string]$SummaryPath = "",
    [string]$StatusPath = "",
    [switch]$SkipDependencies,
    [switch]$SkipRepoClone,
    [switch]$SkipOpenCodeInstall,
    [switch]$SkipLlamaDownload,
    [switch]$SkipTurboQuantBuild,
    [switch]$SkipModelDownload
)

$ErrorActionPreference = "Stop"
$script:CurrentStageName = "Startup"
$script:CurrentStageNumber = 0
$script:TotalInstallStages = 10
$script:InstallWarnings = New-Object System.Collections.Generic.List[string]
$script:InstallNotes = New-Object System.Collections.Generic.List[string]
$script:TurboQuantDependenciesReady = $true
$script:WindowsPowerShellExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$script:CurrentStatusDetail = "Pokretanje Windows install toka."
$script:CurrentStatusActivity = "startup"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$defaultsPath = Join-Path $repoRoot "config\profiles\defaults.json"
$defaults = Get-Content -Raw $defaultsPath | ConvertFrom-Json

$stateDir = Join-Path $InstallRoot "state"
$binDir = Join-Path $InstallRoot "bin"
$appsDir = Join-Path $InstallRoot "apps"
$modelsDir = Join-Path $InstallRoot "models"
$launchersDir = Join-Path $InstallRoot "launchers"
$scriptsDir = Join-Path $InstallRoot "scripts"
$configDir = Join-Path $InstallRoot "config"
$assetsDir = Join-Path $InstallRoot "assets"
$docsDir = Join-Path $InstallRoot "docs"
$toolsDir = Join-Path $InstallRoot "tools"
$desktopTargetDir = Join-Path $DesktopFolder "Local Qwen Home Computer"
$statePath = Join-Path $stateDir "install-state.json"
$installReportPath = Join-Path $stateDir "install-report.json"
$upstreamDir = Join-Path $appsDir "llama.cpp"
$turboDir = Join-Path $appsDir "llama.cpp-turboquant"
$llamaBinDir = Join-Path $binDir "llama.cpp"
$script:modelChoice = $null
$script:modelFile = $null
$script:TurboServerExe = $null
$script:TranscriptStarted = $false

if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
    $logDir = Split-Path -Parent $LogPath
    if (-not [string]::IsNullOrWhiteSpace($logDir)) {
        New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    }
    try {
        Start-Transcript -Path $LogPath -Force | Out-Null
        $script:TranscriptStarted = $true
    } catch {
    }
}

function Write-InstallOverview {
    param(
        [string]$InstallRoot,
        [string]$DesktopTargetDir
    )

    $lines = @(
        "This installer will set up Local Qwen Home Computer for Windows.",
        "Install root: $InstallRoot",
        "Desktop launchers: $DesktopTargetDir",
        "",
        "Planned stages:",
        "  [1/10] Prepare folders and workspace",
        "  [2/10] Check or install dependencies",
        "  [3/10] Copy launchers, scripts, config and icons",
        "  [4/10] Write install state and desktop shortcuts",
        "  [5/10] Clone or verify source repositories",
        "  [6/10] Download or verify llama.cpp runtime",
        "  [7/10] Install or verify OpenCode",
        "  [8/10] Download or verify selected model",
        "  [9/10] Apply settings and OpenCode wiring",
        "  [10/10] Optional TurboQuant build and final verification",
        ""
    )

    Write-Host ($lines -join [Environment]::NewLine) -ForegroundColor Cyan
}

function Invoke-InstallStage {
    param(
        [Parameter(Mandatory = $true)][int]$Number,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )

    $script:CurrentStageName = $Name
    $script:CurrentStageNumber = $Number
    $script:CurrentStatusActivity = "stage"
    $script:CurrentStatusDetail = "Pokrenut korak [$Number/$($script:TotalInstallStages)] $Name."
    Write-InstallStatus -State "running" -Detail $script:CurrentStatusDetail -ActivityType "stage" -ProgressPercent ((($Number - 1) / [double]$script:TotalInstallStages) * 100.0)
    Write-Host ("[{0}/{1}] {2}" -f $Number, $script:TotalInstallStages, $Name) -ForegroundColor Cyan
    & $Action
    $script:CurrentStatusDetail = "Zavrsen korak [$Number/$($script:TotalInstallStages)] $Name."
    Write-InstallStatus -State "running" -Detail $script:CurrentStatusDetail -ActivityType "stage" -ProgressPercent (($Number / [double]$script:TotalInstallStages) * 100.0)
    Write-Host ("[{0}/{1}] DONE - {2}" -f $Number, $script:TotalInstallStages, $Name) -ForegroundColor Green
    Write-Host ""
}

function Ensure-Dir {
    param([string]$Path)
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Write-Utf8NoBomText {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $directory = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Convert-StatusValue {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) {
        return ""
    }

    return ([string]$Value).Replace("`r", " ").Replace("`n", " ").Trim()
}

function Write-InstallStatus {
    param(
        [string]$State = "running",
        [string]$Detail = $script:CurrentStatusDetail,
        [string]$ActivityType = $script:CurrentStatusActivity,
        [Nullable[double]]$ProgressPercent = $null,
        [string]$Source = "",
        [string]$DownloadedGiB = "",
        [string]$TotalGiB = "",
        [string]$SpeedMBps = "",
        [string]$EtaSeconds = "",
        [string]$ModelStatus = ""
    )

    if ([string]::IsNullOrWhiteSpace($StatusPath)) {
        return
    }

    $statusDirectory = Split-Path -Parent $StatusPath
    if (-not [string]::IsNullOrWhiteSpace($statusDirectory)) {
        New-Item -ItemType Directory -Force -Path $statusDirectory | Out-Null
    }

    $percentText = ""
    if ($null -ne $ProgressPercent) {
        $percentText = [math]::Round([double]$ProgressPercent, 2)
    }

    $lines = @(
        "[status]",
        ("state={0}" -f (Convert-StatusValue $State)),
        ("stageNumber={0}" -f $script:CurrentStageNumber),
        ("totalStages={0}" -f $script:TotalInstallStages),
        ("stageName={0}" -f (Convert-StatusValue $script:CurrentStageName)),
        ("detail={0}" -f (Convert-StatusValue $Detail)),
        ("activityType={0}" -f (Convert-StatusValue $ActivityType)),
        ("progressPercent={0}" -f (Convert-StatusValue $percentText)),
        ("source={0}" -f (Convert-StatusValue $Source)),
        ("downloadedGiB={0}" -f (Convert-StatusValue $DownloadedGiB)),
        ("totalGiB={0}" -f (Convert-StatusValue $TotalGiB)),
        ("speedMBps={0}" -f (Convert-StatusValue $SpeedMBps)),
        ("etaSeconds={0}" -f (Convert-StatusValue $EtaSeconds)),
        ("modelStatus={0}" -f (Convert-StatusValue $ModelStatus)),
        ("updatedAt={0}" -f (Get-Date).ToString("o"))
    )

    Write-Utf8NoBomText -Path $StatusPath -Content ($lines -join "`r`n")
}

function Set-InstallStatusDetail {
    param(
        [Parameter(Mandatory = $true)][string]$Detail,
        [string]$ActivityType = $script:CurrentStatusActivity,
        [Nullable[double]]$ProgressPercent = $null
    )

    $script:CurrentStatusDetail = $Detail
    $script:CurrentStatusActivity = $ActivityType
    Write-InstallStatus -Detail $Detail -ActivityType $ActivityType -ProgressPercent $ProgressPercent
}

function Invoke-WithRetry {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [string]$FailureMessage = "Operacija nije uspela.",
        [int]$Attempts = 5,
        [int]$DelayMilliseconds = 350
    )

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            & $Action
            return
        } catch {
            if ($attempt -ge $Attempts) {
                throw "$FailureMessage $($_.Exception.Message)"
            }
            Start-Sleep -Milliseconds $DelayMilliseconds
        }
    }
}

function Get-WindowsPowerShellExe {
    if (-not (Test-Path $script:WindowsPowerShellExe)) {
        throw "Windows PowerShell nije pronadjen na ocekivanoj putanji: $($script:WindowsPowerShellExe)"
    }
    return $script:WindowsPowerShellExe
}

function Stop-RunningLocalQwenProcesses {
    $candidates = @()
    try {
        $processes = Get-CimInstance Win32_Process -ErrorAction Stop
        $protectedIds = New-Object System.Collections.Generic.HashSet[int]
        $currentId = $PID
        while ($currentId -and $protectedIds.Add([int]$currentId)) {
            $currentProcess = $processes | Where-Object { $_.ProcessId -eq $currentId } | Select-Object -First 1
            if (-not $currentProcess) {
                break
            }
            $currentId = [int]$currentProcess.ParentProcessId
            if ($currentId -le 0) {
                break
            }
        }

        $launcherMarkers = @(
            "control-center.ps1",
            "open-control-center.vbs",
            "manage-models.ps1",
            "repair-install.ps1",
            "repair-model.ps1",
            "repair-runtime.ps1",
            "repair-config.ps1",
            "verify-install.ps1",
            "start-opencode.ps1",
            "launch-agent.ps1",
            "open-opencode.cmd"
        )
        $candidates = @(
            $processes | Where-Object {
                $commandLine = [string]$_.CommandLine
                $commandLineLower = $commandLine.ToLowerInvariant()
                -not $protectedIds.Contains([int]$_.ProcessId) -and
                -not [string]::IsNullOrWhiteSpace($commandLine) -and
                $commandLineLower.Contains($InstallRoot.ToLowerInvariant()) -and
                ($launcherMarkers | Where-Object { $commandLineLower.Contains($_) }).Count -gt 0
            }
        )
    } catch {
        return
    }

    if (-not $candidates -or $candidates.Count -eq 0) {
        return
    }

    $stopped = New-Object System.Collections.Generic.List[string]
    foreach ($process in $candidates) {
        try {
            Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop
            $stopped.Add(("{0} ({1})" -f $process.Name, $process.ProcessId)) | Out-Null
        } catch {
        }
    }

    if ($stopped.Count -gt 0) {
        $message = "Zatvoreni su aktivni Local Qwen launcher procesi pre osvezavanja fajlova: {0}" -f ($stopped -join ", ")
        $script:InstallNotes.Add($message) | Out-Null
        Write-Host $message -ForegroundColor Yellow
    }
}

function Add-PathEntryIfMissing {
    param([Parameter(Mandatory = $true)][string]$PathEntry)

    if (-not $PathEntry -or -not (Test-Path $PathEntry)) {
        return
    }

    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "Process")
    $parts = @($currentPath -split ';' | Where-Object { $_ })
    if ($parts -notcontains $PathEntry) {
        [Environment]::SetEnvironmentVariable("PATH", "$PathEntry;$currentPath", "Process")
    }
}

function Install-PortableNinja {
    $ninjaDir = Join-Path $toolsDir "ninja"
    $ninjaExe = Join-Path $ninjaDir "ninja.exe"
    if (Test-Path $ninjaExe) {
        Add-PathEntryIfMissing -PathEntry $ninjaDir
        return $true
    }

    Write-Host "Preuzimam portable Ninja fallback..." -ForegroundColor Cyan
    Ensure-Dir $ninjaDir
    $zipPath = Join-Path $env:TEMP ("local-qwen-ninja-" + [guid]::NewGuid().ToString() + ".zip")
    try {
        Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/ninja-build/ninja/releases/latest/download/ninja-win.zip" -OutFile $zipPath
        Expand-Archive -LiteralPath $zipPath -DestinationPath $ninjaDir -Force
        if (-not (Test-Path $ninjaExe)) {
            throw "Portable Ninja archive nije sadrzao ninja.exe"
        }
        Add-PathEntryIfMissing -PathEntry $ninjaDir
        return $true
    } catch {
        Write-Host "Portable Ninja fallback nije uspeo: $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
    } finally {
        Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
    }
}

function Test-WingetPackageInstalled {
    param([string]$WingetId)

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        return $false
    }

    $output = & winget list --id $WingetId --exact --accept-source-agreements 2>$null | Out-String
    return ($LASTEXITCODE -eq 0) -and ($output -match [regex]::Escape($WingetId))
}

function Resolve-PythonExecutableFromCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [string[]]$Arguments = @()
    )

    try {
        $output = & $Command @Arguments -c "import sys; print(sys.executable)" 2>$null
        if ($LASTEXITCODE -ne 0) {
            return $null
        }

        $resolved = [string]($output | Select-Object -Last 1)
        if (-not [string]::IsNullOrWhiteSpace($resolved) -and (Test-Path $resolved)) {
            return $resolved.Trim()
        }

        return $null
    } catch {
        return $null
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
            $resolved = Resolve-PythonExecutableFromCommand -Command $candidate.Command -Arguments $candidate.Arguments
            if ($resolved) {
                return [pscustomobject]@{
                    Command = $resolved
                    Arguments = @()
                }
            }
        }
    }

    $pathCandidates = @(
        "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
        "$env:ProgramFiles\Python312\python.exe",
        "${env:ProgramFiles(x86)}\Python312\python.exe"
    ) | Where-Object { $_ -and (Test-Path $_) }

    foreach ($path in $pathCandidates) {
        if (Resolve-PythonExecutableFromCommand -Command $path -Arguments @()) {
            return [pscustomobject]@{
                Command = $path
                Arguments = @()
            }
        }
    }

    return $null
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

    return $null
}

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(ValueFromRemainingArguments = $true)][string[]]$ArgumentList
    )

    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "Komanda nije uspela: $FilePath $($ArgumentList -join ' ')"
    }
}

function Ensure-Command {
    param(
        [string]$Name,
        [string]$WingetId
    )

    if (Get-Command $Name -ErrorAction SilentlyContinue) {
        return
    }

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "Komanda '$Name' nije pronadjena, a winget nije dostupan za automatsku instalaciju."
    }

    Write-Host "Instaliram $Name preko winget..." -ForegroundColor Cyan
    & winget install --id $WingetId --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        if ((Get-Command $Name -ErrorAction SilentlyContinue) -or (Test-WingetPackageInstalled -WingetId $WingetId)) {
            Write-Host "$Name je vec instaliran ili je dostupan nakon winget pokusaja." -ForegroundColor Yellow
            return
        }
        throw "Komanda nije uspela: winget install --id $WingetId --silent --accept-package-agreements --accept-source-agreements"
    }
}

function Ensure-OptionalCommand {
    param(
        [string]$Name,
        [string]$WingetId,
        [string]$ReasonIfMissing
    )

    if (Get-Command $Name -ErrorAction SilentlyContinue) {
        return $true
    }

    if ($Name -eq "ninja") {
        if (Install-PortableNinja) {
            return $true
        }
    }

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        $script:InstallWarnings.Add("$ReasonIfMissing Komanda '$Name' nije pronadjena, a winget nije dostupan.") | Out-Null
        return $false
    }

    Write-Host "Instaliram opcioni alat $Name preko winget..." -ForegroundColor Cyan
    & winget install --id $WingetId --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        if ((Get-Command $Name -ErrorAction SilentlyContinue) -or (Test-WingetPackageInstalled -WingetId $WingetId)) {
            Write-Host "$Name je vec instaliran ili je dostupan nakon winget pokusaja." -ForegroundColor Yellow
            return $true
        }
        $script:InstallWarnings.Add("$ReasonIfMissing Nije uspela automatska instalacija za '$Name'.") | Out-Null
        return $false
    }

    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Ensure-PythonRuntime {
    $python = Get-PythonLauncher
    if ($python) {
        return $python
    }

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "Python nije pronadjen, a winget nije dostupan za automatsku instalaciju."
    }

    Write-Host "Instaliram Python 3.12 preko winget..." -ForegroundColor Cyan
    & winget install --id Python.Python.3.12 --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0 -and -not (Test-WingetPackageInstalled -WingetId "Python.Python.3.12")) {
        throw "Python instalacija preko winget nije uspela."
    }

    $python = Get-PythonLauncher
    if (-not $python) {
        throw "Python deluje instaliran, ali py/python jos nije dostupan u ovoj sesiji. Otvori novi PowerShell i pokreni installer ponovo sa -SkipDependencies."
    }

    return $python
}

function Invoke-RuntimeHelperJson {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $python = Ensure-PythonRuntime
    $scriptPath = Join-Path $repoRoot "scripts\local_qwen_runtime.py"
    $output = & $python.Command @($python.Arguments + @($scriptPath) + $Arguments)
    if ($LASTEXITCODE -ne 0) {
        throw "Shared runtime helper nije uspeo: $($Arguments -join ' ')"
    }
    return ($output | Out-String | ConvertFrom-Json)
}

function Get-DetectedGpuMemoryMiB {
    try {
        $controllers = Get-CimInstance Win32_VideoController -ErrorAction Stop | Where-Object { $_.AdapterRAM -gt 0 }
        if (-not $controllers) {
            return 0
        }
        return [int]([math]::Round((($controllers | Measure-Object -Property AdapterRAM -Maximum).Maximum) / 1MB))
    } catch {
        return 0
    }
}

function Get-SystemMemoryGiB {
    try {
        $computer = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        return [int]([math]::Round($computer.TotalPhysicalMemory / 1GB))
    } catch {
        return 0
    }
}

function Get-RecommendedModelChoice {
    $payload = Invoke-RuntimeHelperJson -Arguments @(
        "recommend",
        "--defaults", $defaultsPath,
        "--gpu-mib", ([string](Get-DetectedGpuMemoryMiB)),
        "--ram-gib", ([string](Get-SystemMemoryGiB)),
        "--cpu-threads", ([string][Environment]::ProcessorCount)
    )
    $recommendedId = [string]$payload.recommendedModel.id
    foreach ($property in $defaults.modelChoices.PSObject.Properties) {
        if ($property.Value.id -eq $recommendedId) {
            return $property.Value
        }
    }
    return $defaults.modelChoices.iq2_m_compact
}

function Get-ExistingInstallState {
    if (-not (Test-Path $statePath)) {
        return $null
    }

    try {
        return Get-Content -Raw $statePath | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Get-ModelChoiceById {
    param([string]$ModelId)

    foreach ($property in $defaults.modelChoices.PSObject.Properties) {
        if ($property.Value.id -eq $ModelId -or $property.Value.filename -eq $ModelId) {
            return $property.Value
        }
    }
    return $null
}

function Test-ModelFileLooksCompleteForChoice {
    param(
        [string]$Path,
        $ModelChoice
    )

    if (-not $Path -or -not (Test-Path $Path) -or -not $ModelChoice) {
        return $false
    }

    $minimum = [int64]$ModelChoice.minExpectedBytes
    if ($minimum -le 0) {
        return $true
    }

    $item = Get-Item $Path -ErrorAction SilentlyContinue
    return ($item -and $item.Length -ge $minimum)
}

function Get-AvailableCompleteModelIds {
    $completeIds = New-Object System.Collections.Generic.List[string]

    foreach ($property in $defaults.modelChoices.PSObject.Properties) {
        $choice = $property.Value
        $candidatePath = Join-Path $modelsDir ([string]$choice.filename)
        if (Test-ModelFileLooksCompleteForChoice -Path $candidatePath -ModelChoice $choice) {
            $completeIds.Add([string]$choice.id) | Out-Null
        }
    }

    return @($completeIds)
}

function Ensure-VsBuildTools {
    $vcvars = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
    if (Test-Path $vcvars) {
        return
    }

    Write-Host "Instaliram Visual Studio Build Tools 2022..." -ForegroundColor Cyan
    Invoke-Native winget install --id Microsoft.VisualStudio.2022.BuildTools --silent --accept-package-agreements --accept-source-agreements --override "--wait --quiet --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
}

function Test-WindowsSdkBuildToolsPresent {
    $rc = Get-ChildItem "C:\Program Files (x86)\Windows Kits\10\bin\*\x64\rc.exe" -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
    $mt = Get-ChildItem "C:\Program Files (x86)\Windows Kits\10\bin\*\x64\mt.exe" -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
    return [bool]($rc -and $mt)
}

function Repair-VsBuildToolsWindowsSdk {
    $setupExe = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe"
    $installPath = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools"
    if (-not (Test-Path $setupExe) -or -not (Test-Path $installPath)) {
        return $false
    }

    Write-Host "Dopunjavam Visual Studio Build Tools Windows SDK komponentama..." -ForegroundColor Cyan
    & $setupExe modify --installPath $installPath --add Microsoft.VisualStudio.Workload.VCTools --add Microsoft.VisualStudio.Component.Windows11SDK.26100 --includeRecommended --passive --norestart
    Start-Sleep -Seconds 5
    return (Test-WindowsSdkBuildToolsPresent)
}

function Ensure-CudaToolkit {
    if (Get-Command nvcc -ErrorAction SilentlyContinue) {
        return
    }

    $cudaDir = Get-ChildItem "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cudaDir) {
        return
    }

    Write-Host "Instaliram NVIDIA CUDA Toolkit..." -ForegroundColor Cyan
    Invoke-Native winget install --id Nvidia.CUDA --silent --accept-package-agreements --accept-source-agreements
}

function Ensure-OptionalVsBuildTools {
    $vcvars = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
    if ((Test-Path $vcvars) -and (Test-WindowsSdkBuildToolsPresent)) {
        return $true
    }

    if (Test-Path $vcvars) {
        if (Repair-VsBuildToolsWindowsSdk) {
            return $true
        }
        $script:InstallWarnings.Add("TurboQuant build bice preskocen. Visual Studio Build Tools postoje, ali Windows SDK build alati (rc.exe/mt.exe) nisu dostupni.") | Out-Null
        return $false
    }

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        $script:InstallWarnings.Add("TurboQuant build bice preskocen. Visual Studio Build Tools nisu pronadjeni, a winget nije dostupan.") | Out-Null
        return $false
    }

    Write-Host "Instaliram opcione Visual Studio Build Tools 2022..." -ForegroundColor Cyan
    & winget install --id Microsoft.VisualStudio.2022.BuildTools --silent --accept-package-agreements --accept-source-agreements --override "--wait --quiet --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
    if ($LASTEXITCODE -ne 0 -and -not (Test-Path $vcvars)) {
        $script:InstallWarnings.Add("TurboQuant build bice preskocen. Visual Studio Build Tools nisu mogli automatski da se instaliraju.") | Out-Null
        return $false
    }

    if (-not (Test-WindowsSdkBuildToolsPresent)) {
        if (-not (Repair-VsBuildToolsWindowsSdk)) {
            $script:InstallWarnings.Add("TurboQuant build bice preskocen. Visual Studio Build Tools su instalirani, ali Windows SDK build alati (rc.exe/mt.exe) nisu dostupni.") | Out-Null
            return $false
        }
    }

    return ((Test-Path $vcvars) -and (Test-WindowsSdkBuildToolsPresent))
}

function Ensure-OptionalCudaToolkit {
    if (Get-Command nvcc -ErrorAction SilentlyContinue) {
        return $true
    }

    $cudaDir = Get-ChildItem "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cudaDir) {
        return $true
    }

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        $script:InstallWarnings.Add("TurboQuant build bice preskocen. CUDA toolkit nije pronadjen, a winget nije dostupan.") | Out-Null
        return $false
    }

    Write-Host "Instaliram opcioni NVIDIA CUDA Toolkit..." -ForegroundColor Cyan
    & winget install --id Nvidia.CUDA --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        $cudaDir = Get-ChildItem "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $cudaDir) {
            $script:InstallWarnings.Add("TurboQuant build bice preskocen. CUDA toolkit nije mogao automatski da se instalira.") | Out-Null
            return $false
        }
    }

    return $true
}

function Copy-FolderContent {
    param(
        [string]$Source,
        [string]$Destination,
        [switch]$ReplaceExisting
    )

    Ensure-Dir $Destination
    if ($ReplaceExisting) {
        Get-ChildItem -LiteralPath $Destination -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $targetPath = $_.FullName
            Invoke-WithRetry -FailureMessage "Ne mogu da obrisem prethodni sadrzaj iz $targetPath." -Action {
                Remove-Item -LiteralPath $targetPath -Recurse -Force -ErrorAction Stop
            }
        }
    }
    Invoke-WithRetry -FailureMessage "Ne mogu da kopiram sadrzaj iz $Source u $Destination." -Action {
        Copy-Item -Path (Join-Path $Source "*") -Destination $Destination -Recurse -Force -ErrorAction Stop
    }
}

function Copy-FileWithRetry {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    Ensure-Dir (Split-Path -Parent $Destination)
    Invoke-WithRetry -FailureMessage "Ne mogu da kopiram fajl iz $Source u $Destination." -Action {
        Copy-Item -LiteralPath $Source -Destination $Destination -Force -ErrorAction Stop
    }
}

function Download-LlamaCppWindowsCuda {
    param([string]$DestinationDir)

    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/ggml-org/llama.cpp/releases/latest"
    $asset = $release.assets | Where-Object { $_.name -match '^llama-.*-bin-win-cuda-12\.4-x64\.zip$' } | Select-Object -First 1

    if (-not $asset) {
        $asset = $release.assets | Where-Object { $_.name -match '^llama-.*-bin-win-cuda-13\.1-x64\.zip$' } | Select-Object -First 1
    }

    if (-not $asset) {
        throw "Nisam nasao odgovarajuci kompletan Windows CUDA release asset za llama.cpp."
    }

    $zipPath = Join-Path $env:TEMP $asset.name
    Invoke-WebRequest -UseBasicParsing -Uri $asset.browser_download_url -OutFile $zipPath

    Ensure-Dir $DestinationDir
    Expand-Archive -LiteralPath $zipPath -DestinationPath $DestinationDir -Force
    Remove-Item -LiteralPath $zipPath -Force
    Get-ChildItem -LiteralPath $DestinationDir -Recurse -File | Unblock-File -ErrorAction SilentlyContinue

    if (-not (Test-Path (Join-Path $DestinationDir "llama-server.exe"))) {
        throw "llama.cpp ZIP je raspakovan, ali llama-server.exe nije pronadjen u $DestinationDir"
    }
}

function Test-LlamaBinaryRunnable {
    param([Parameter(Mandatory = $true)][string]$ServerExe)

    try {
        & $ServerExe --version *> $null
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

function Test-IsAppControlWarningText {
    param([Parameter(Mandatory = $true)][string]$WarningText)

    $normalized = $WarningText.ToLowerInvariant()
    return ($normalized -like "*wdac*") -or ($normalized -like "*app control*") -or ($normalized -like "*unsigned exe*")
}

function Test-HealthEndpointAlive {
    param([int]$Port = 8091)

    try {
        $response = Invoke-RestMethod -Uri ("http://127.0.0.1:{0}/health" -f $Port) -TimeoutSec 3
        return [string]$response.status -eq "ok"
    } catch {
        return $false
    }
}

function Get-FilteredInstallWarnings {
    param(
        [Parameter(Mandatory = $true)][System.Collections.Generic.List[string]]$Warnings,
        [string]$PreferredServerExe,
        [int]$Port = 8091,
        [bool]$HasTurboRuntime = $false
    )

    $runtimeHealthy = $HasTurboRuntime
    if (-not $runtimeHealthy -and $PreferredServerExe -and (Test-Path $PreferredServerExe)) {
        $runtimeHealthy = Test-LlamaBinaryRunnable -ServerExe $PreferredServerExe
    }
    if (-not $runtimeHealthy) {
        $runtimeHealthy = Test-HealthEndpointAlive -Port $Port
    }

    if (-not $runtimeHealthy) {
        return @($Warnings)
    }

    return @($Warnings | Where-Object { -not (Test-IsAppControlWarningText -WarningText ([string]$_)) })
}

function Download-RecommendedModel {
    param(
        [string]$RepoId,
        [string]$Filename,
        [string]$TargetPath,
        [Int64]$MinExpectedBytes = 0
    )

    $python = Ensure-PythonRuntime
    & $python.Command @($python.Arguments + @("-m", "pip", "install", "--user", "-U", "huggingface_hub"))
    if ($LASTEXITCODE -ne 0) {
        throw "Komanda nije uspela: $($python.Command) -m pip install --user -U huggingface_hub"
    }

    $targetDir = Split-Path -Parent $TargetPath
    Ensure-Dir $targetDir

    $pyCode = @"
from huggingface_hub import hf_hub_download
hf_hub_download(
    repo_id=r"$RepoId",
    filename=r"$Filename",
    local_dir=r"$targetDir",
    local_dir_use_symlinks=False,
)
"@

    $tmpPy = Join-Path $env:TEMP "local_qwen_hf_download.py"
    Set-Content -Path $tmpPy -Value $pyCode -Encoding UTF8
    & $python.Command @($python.Arguments + @($tmpPy))
    if ($LASTEXITCODE -ne 0) {
        throw "Komanda nije uspela: $($python.Command) $tmpPy"
    }
    Remove-Item -LiteralPath $tmpPy -Force

    if (!(Test-Path $TargetPath)) {
        throw "Model download nije proizveo ocekivani fajl: $TargetPath"
    }

    if ($MinExpectedBytes -gt 0) {
        $downloadedSize = (Get-Item $TargetPath).Length
        if ($downloadedSize -lt $MinExpectedBytes) {
            throw "Model je skinut nepotpuno: $TargetPath ($downloadedSize bajtova, ocekivano najmanje $MinExpectedBytes)"
        }
    }
}

function Write-InstallState {
    param(
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [Parameter(Mandatory = $true)][string]$DesktopTargetDir,
        [Parameter(Mandatory = $true)][string]$UpstreamDir,
        [Parameter(Mandatory = $true)][string]$TurboDir,
        [Parameter(Mandatory = $true)][string]$LlamaBinDir,
        [Parameter(Mandatory = $true)][string]$ModelFile,
        [Parameter(Mandatory = $true)][string]$ModelId,
        [Parameter(Mandatory = $true)][string]$Profile,
        [Parameter(Mandatory = $true)][string]$StatePath,
        [Parameter(Mandatory = $true)]$Defaults,
        [string]$TurboServerExe
    )

    $state = [ordered]@{
        installRoot = $InstallRoot
        desktopTargetDir = $DesktopTargetDir
        upstreamDir = $UpstreamDir
        turboDir = $TurboDir
        llamaBinDir = $LlamaBinDir
        modelFile = $ModelFile
        modelId = $ModelId
        defaultProfile = $Profile
        port = $Defaults.service.port
        threads = $Defaults.service.threads
        noMmap = $Defaults.service.noMmap
        mlock = $Defaults.service.mlock
        installedAt = (Get-Date).ToString("s")
    }

    if ($TurboServerExe) {
        $state.turboServerExe = $TurboServerExe
    }

    $state | ConvertTo-Json -Depth 10 | Set-Content -Path $StatePath -Encoding UTF8
}

function Write-InstallReport {
    param(
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [Parameter(Mandatory = $true)][string]$InstallRootStatePath,
        [Parameter(Mandatory = $true)][string]$InstallReportPath,
        [Parameter(Mandatory = $true)][string]$ModelFile,
        [Parameter(Mandatory = $true)][string]$LlamaBinDir,
        [Parameter(Mandatory = $true)][string]$TurboDir,
        [Parameter(Mandatory = $true)][string]$LaunchersDir,
        [Parameter(Mandatory = $true)][string]$DesktopTargetDir,
        [Parameter(Mandatory = $true)][string]$Profile,
        [Parameter(Mandatory = $true)]$Warnings
    )

    $llamaServerPath = Join-Path $LlamaBinDir "llama-server.exe"
    $turboServerPath = Join-Path $TurboDir "$($defaults.turboquant.buildDir)\bin\llama-server.exe"
    $configPath = Join-Path $env:USERPROFILE ".config\opencode\opencode.json"
    $desktopShortcutNames = @(
        "Local Qwen Control Center.lnk",
        "OpenCode - Local Qwen.lnk",
        "Verify Local Qwen Install.lnk",
        "Repair Windows App Control.lnk",
        "Update Local Qwen.lnk",
        "Uninstall Local Qwen.lnk"
    )
    $missingShortcuts = @($desktopShortcutNames | Where-Object { -not (Test-Path (Join-Path $DesktopTargetDir $_)) })

    $report = [ordered]@{
        generatedAt = (Get-Date).ToString("s")
        platform = "windows"
        profile = $Profile
        installRoot = $InstallRoot
        components = [ordered]@{
            installState = [ordered]@{
                path = $InstallRootStatePath
                ok = (Test-Path $InstallRootStatePath)
            }
            launchers = [ordered]@{
                path = $LaunchersDir
                ok = (Test-Path (Join-Path $LaunchersDir "control-center.ps1"))
            }
            desktopShortcuts = [ordered]@{
                path = $DesktopTargetDir
                ok = ($missingShortcuts.Count -eq 0)
                missing = @($missingShortcuts)
            }
            llamaCppRuntime = [ordered]@{
                path = $llamaServerPath
                ok = (Test-Path $llamaServerPath)
            }
            turboQuantRuntime = [ordered]@{
                path = $turboServerPath
                ok = (Test-Path $turboServerPath)
            }
            model = [ordered]@{
                path = $ModelFile
                ok = (Test-Path $ModelFile)
                sizeBytes = if (Test-Path $ModelFile) { (Get-Item $ModelFile).Length } else { 0 }
            }
            opencodeConfig = [ordered]@{
                path = $configPath
                ok = (Test-Path $configPath)
            }
        }
        warnings = @($Warnings)
    }

    $report | ConvertTo-Json -Depth 10 | Set-Content -Path $InstallReportPath -Encoding UTF8
}

function New-Shortcut {
    param(
        [string]$ShortcutPath,
        [string]$TargetPath,
        [AllowEmptyString()]
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
    if ($IconLocation) {
        $shortcut.IconLocation = $IconLocation
    }
    if ($Description) {
        $shortcut.Description = $Description
    }
    $shortcut.Save()

    if (-not (Test-Path $ShortcutPath)) {
        throw "Desktop shortcut nije sacuvan: $ShortcutPath"
    }
}

function Write-CmdLauncher {
    param(
        [Parameter(Mandatory = $true)][string]$LaunchersDir,
        [Parameter(Mandatory = $true)][string]$CmdName,
        [Parameter(Mandatory = $true)][string]$PsScriptName,
        [AllowEmptyString()]
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

function Write-HiddenVbsLauncher {
    param(
        [Parameter(Mandatory = $true)][string]$LaunchersDir,
        [Parameter(Mandatory = $true)][string]$VbsName,
        [Parameter(Mandatory = $true)][string]$PsScriptName,
        [AllowEmptyString()]
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

function Write-DesktopShortcuts {
    param(
        [Parameter(Mandatory = $true)][string]$LaunchersDir,
        [Parameter(Mandatory = $true)][string]$AssetsDir,
        [Parameter(Mandatory = $true)][string]$DesktopTargetDir
    )

    Ensure-Dir $DesktopTargetDir

    $controlCenterIcon = Join-Path $AssetsDir "icons\control-center.ico"
    $opencodeIcon = Join-Path $AssetsDir "icons\opencode-local-qwen.ico"
    $controlCenterVbs = Write-HiddenVbsLauncher -LaunchersDir $LaunchersDir -VbsName "open-control-center.vbs" -PsScriptName "control-center.ps1"
    $openCodeCmd = Write-CmdLauncher -LaunchersDir $LaunchersDir -CmdName "open-opencode.cmd" -PsScriptName "start-opencode.ps1"
    $verifyCmd = Write-CmdLauncher -LaunchersDir $LaunchersDir -CmdName "verify-install.cmd" -PsScriptName "verify-install.ps1"
    $repairCmd = Write-CmdLauncher -LaunchersDir $LaunchersDir -CmdName "repair-app-control.cmd" -PsScriptName "repair-app-control.ps1"
    $updateCmd = Write-CmdLauncher -LaunchersDir $LaunchersDir -CmdName "install-update.cmd" -PsScriptName "install-update.ps1"
    $uninstallCmd = Write-CmdLauncher -LaunchersDir $LaunchersDir -CmdName "uninstall-local-qwen.cmd" -PsScriptName "uninstall.ps1"

    New-Shortcut `
        -ShortcutPath (Join-Path $DesktopTargetDir "Local Qwen Control Center.lnk") `
        -TargetPath "wscript.exe" `
        -Arguments "`"$controlCenterVbs`"" `
        -WorkingDirectory $LaunchersDir `
        -IconLocation "$controlCenterIcon,0" `
        -Description "Control center for local Qwen + OpenCode"

    New-Shortcut `
        -ShortcutPath (Join-Path $DesktopTargetDir "OpenCode - Local Qwen.lnk") `
        -TargetPath $env:ComSpec `
        -Arguments "/c `"$openCodeCmd`"" `
        -WorkingDirectory $LaunchersDir `
        -IconLocation "$opencodeIcon,0" `
        -Description "Launch OpenCode wired to local Qwen"

    New-Shortcut `
        -ShortcutPath (Join-Path $DesktopTargetDir "Verify Local Qwen Install.lnk") `
        -TargetPath $env:ComSpec `
        -Arguments "/c `"$verifyCmd`"" `
        -WorkingDirectory $LaunchersDir `
        -IconLocation "$controlCenterIcon,0" `
        -Description "Verify local Qwen installation"

    New-Shortcut `
        -ShortcutPath (Join-Path $DesktopTargetDir "Repair Windows App Control.lnk") `
        -TargetPath $env:ComSpec `
        -Arguments "/c `"$repairCmd`"" `
        -WorkingDirectory $LaunchersDir `
        -IconLocation "$controlCenterIcon,0" `
        -Description "Inspect or repair Smart App Control / App Control issues"

    New-Shortcut `
        -ShortcutPath (Join-Path $DesktopTargetDir "Update Local Qwen.lnk") `
        -TargetPath $env:ComSpec `
        -Arguments "/c `"$updateCmd`"" `
        -WorkingDirectory $LaunchersDir `
        -IconLocation "$controlCenterIcon,0" `
        -Description "Download and launch the latest Local Qwen installer"

    New-Shortcut `
        -ShortcutPath (Join-Path $DesktopTargetDir "Uninstall Local Qwen.lnk") `
        -TargetPath $env:ComSpec `
        -Arguments "/c `"$uninstallCmd`"" `
        -WorkingDirectory $LaunchersDir `
        -IconLocation "$controlCenterIcon,0" `
        -Description "Uninstall Local Qwen with choice to keep models"

    $expectedShortcuts = @(
        "Local Qwen Control Center.lnk",
        "OpenCode - Local Qwen.lnk",
        "Verify Local Qwen Install.lnk",
        "Repair Windows App Control.lnk",
        "Update Local Qwen.lnk",
        "Uninstall Local Qwen.lnk"
    )
    $missing = @($expectedShortcuts | Where-Object { -not (Test-Path (Join-Path $DesktopTargetDir $_)) })
    if ($missing.Count -gt 0) {
        throw "Desktop shortcuts nisu kompletno napravljeni: $($missing -join ', ')"
    }
}

try {
    Write-InstallOverview -InstallRoot $InstallRoot -DesktopTargetDir $desktopTargetDir
    Write-InstallStatus -State "running" -Detail "Pripremam staged installer tok." -ActivityType "startup" -ProgressPercent 0

    Invoke-InstallStage -Number 1 -Name "Prepare folders and workspace" -Action {
        Ensure-Dir $InstallRoot
        Ensure-Dir $stateDir
        Ensure-Dir $binDir
        Ensure-Dir $appsDir
        Ensure-Dir $modelsDir
        Ensure-Dir $launchersDir
        Ensure-Dir $scriptsDir
        Ensure-Dir $configDir
        Ensure-Dir $assetsDir
        Ensure-Dir $docsDir
        Ensure-Dir $toolsDir
        Ensure-Dir $desktopTargetDir
    }

    Invoke-InstallStage -Number 2 -Name "Check or install dependencies" -Action {
        if ($SkipDependencies) {
            Write-Host "Skipping dependency installation because -SkipDependencies was requested." -ForegroundColor Yellow
            return
        }

        Ensure-Command -Name "git" -WingetId "Git.Git"
        Ensure-Command -Name "node" -WingetId "OpenJS.NodeJS.LTS"
        Ensure-Command -Name "npm" -WingetId "OpenJS.NodeJS.LTS"
        [void](Ensure-PythonRuntime)
        $script:TurboQuantDependenciesReady = $true
        if (-not (Ensure-OptionalCommand -Name "cmake" -WingetId "Kitware.CMake" -ReasonIfMissing "TurboQuant build bice preskocen.")) {
            $script:TurboQuantDependenciesReady = $false
        }
        if (-not (Ensure-OptionalCommand -Name "ninja" -WingetId "Ninja-build.Ninja" -ReasonIfMissing "TurboQuant build bice preskocen.")) {
            $script:TurboQuantDependenciesReady = $false
        }
        if (-not (Ensure-OptionalVsBuildTools)) {
            $script:TurboQuantDependenciesReady = $false
        }
        if (-not (Ensure-OptionalCudaToolkit)) {
            $script:TurboQuantDependenciesReady = $false
        }
    }

    Invoke-InstallStage -Number 3 -Name "Copy launchers, scripts, config and icons" -Action {
        Stop-RunningLocalQwenProcesses
        Copy-FolderContent -Source (Join-Path $repoRoot "launcher\windows") -Destination $launchersDir -ReplaceExisting
        Copy-FolderContent -Source (Join-Path $repoRoot "scripts") -Destination $scriptsDir -ReplaceExisting
        Copy-FolderContent -Source (Join-Path $repoRoot "assets\icons") -Destination (Join-Path $assetsDir "icons") -ReplaceExisting
        Copy-FolderContent -Source (Join-Path $repoRoot "config\profiles") -Destination (Join-Path $configDir "profiles") -ReplaceExisting
        Copy-FileWithRetry -Source (Join-Path $repoRoot "version.json") -Destination (Join-Path $InstallRoot "version.json")
        Copy-FileWithRetry -Source (Join-Path $repoRoot "release-notes.txt") -Destination (Join-Path $InstallRoot "release-notes.txt")
        Copy-FileWithRetry -Source (Join-Path $repoRoot "release-notes.txt") -Destination (Join-Path $docsDir "release-notes.txt")

        foreach ($stalePath in @(
            (Join-Path $launchersDir "version.json"),
            (Join-Path $launchersDir "release-notes.txt")
        )) {
            if (Test-Path $stalePath) {
                Remove-Item -LiteralPath $stalePath -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Invoke-InstallStage -Number 4 -Name "Write install state and desktop shortcuts" -Action {
        $recommendedModelChoice = Get-RecommendedModelChoice
        $requestedModelChoice = $null
        if (-not [string]::IsNullOrWhiteSpace($ModelId)) {
            $requestedModelChoice = Get-ModelChoiceById -ModelId $ModelId
            if (-not $requestedModelChoice) {
                $script:InstallWarnings.Add("Trazeni model '$ModelId' nije prepoznat; koristi se podrazumevani preporuceni izbor.") | Out-Null
            }
        }
        $existingInstallState = Get-ExistingInstallState
        $existingModelChoice = $null
        $existingModelComplete = $false
        if ($existingInstallState) {
            $existingModelChoice = Get-ModelChoiceById -ModelId ([string]$existingInstallState.modelId)
            $existingModelComplete = Test-ModelFileLooksCompleteForChoice -Path ([string]$existingInstallState.modelFile) -ModelChoice $existingModelChoice
        }
        $availableCompleteModelIds = @(Get-AvailableCompleteModelIds)
        $resolvedInstallModel = Invoke-RuntimeHelperJson -Arguments @(
            "resolve-install-model",
            "--defaults", $defaultsPath,
            "--gpu-mib", ([string](Get-DetectedGpuMemoryMiB)),
            "--ram-gib", ([string](Get-SystemMemoryGiB)),
            "--cpu-threads", ([string][Environment]::ProcessorCount),
            "--current-model-id", ([string]$(if ($existingModelChoice) { $existingModelChoice.id } else { "__none__" })),
            "--current-model-complete", ([string]$existingModelComplete).ToLower(),
            "--skip-model-download", ([string]$SkipModelDownload.IsPresent).ToLower(),
            "--available-complete-model-ids", ([string]$(if ($availableCompleteModelIds.Count -gt 0) { $availableCompleteModelIds -join "," } else { "__none__" }))
        )
        $selectedModelChoice = $null
        if ($resolvedInstallModel -and $resolvedInstallModel.selectedModel -and $resolvedInstallModel.selectedModel.id) {
            $selectedModelChoice = Get-ModelChoiceById -ModelId ([string]$resolvedInstallModel.selectedModel.id)
        }
        if ($requestedModelChoice) {
            $selectedModelChoice = $requestedModelChoice
        }
        if (-not $selectedModelChoice) {
            $selectedModelChoice = $recommendedModelChoice
        }

        $script:modelChoice = $selectedModelChoice
        $script:modelFile = Join-Path $modelsDir $selectedModelChoice.filename

        Write-InstallState `
            -InstallRoot $InstallRoot `
            -DesktopTargetDir $desktopTargetDir `
            -UpstreamDir $upstreamDir `
            -TurboDir $turboDir `
            -LlamaBinDir $llamaBinDir `
            -ModelFile $script:modelFile `
            -ModelId $selectedModelChoice.id `
            -Profile $Profile `
            -StatePath $statePath `
            -Defaults $defaults

        Write-DesktopShortcuts -LaunchersDir $launchersDir -AssetsDir $assetsDir -DesktopTargetDir $desktopTargetDir
    }

    Invoke-InstallStage -Number 5 -Name "Clone or verify source repositories" -Action {
        Set-InstallStatusDetail -Detail "Proveravam potrebne source repozitorijume za llama.cpp i TurboQuant." -ActivityType "repositories" -ProgressPercent 40
        if ($SkipRepoClone) {
            Write-Host "Skipping repository clone because -SkipRepoClone was requested." -ForegroundColor Yellow
            return
        }

        if (!(Test-Path $upstreamDir)) {
            Invoke-Native git clone https://github.com/ggml-org/llama.cpp.git $upstreamDir
        }

        if (!(Test-Path $turboDir)) {
            Invoke-Native git clone $defaults.turboquant.repo $turboDir
            Invoke-Native git -C $turboDir checkout $defaults.turboquant.branch
        }
    }

    Invoke-InstallStage -Number 6 -Name "Download or verify llama.cpp runtime" -Action {
        Set-InstallStatusDetail -Detail "Proveravam ili preuzimam llama.cpp runtime." -ActivityType "runtime" -ProgressPercent 50
        if ($SkipLlamaDownload) {
            Write-Host "Skipping llama.cpp runtime download because -SkipLlamaDownload was requested." -ForegroundColor Yellow
        } elseif (!(Test-Path (Join-Path $llamaBinDir "llama-server.exe"))) {
            Download-LlamaCppWindowsCuda -DestinationDir $llamaBinDir
        }

        $upstreamServerExe = Join-Path $llamaBinDir "llama-server.exe"
        if (Test-Path $upstreamServerExe) {
            if (-not (Test-LlamaBinaryRunnable -ServerExe $upstreamServerExe)) {
                $script:InstallWarnings.Add("Windows je blokirao pokretanje llama-server.exe. Moguca je Application Control / WDAC politika na masini. Ako precice postoje ali server ne krece, proveri da li sistem dozvoljava lokalne unsigned exe fajlove.") | Out-Null
            }
        } elseif ($SkipLlamaDownload) {
            $script:InstallWarnings.Add("llama-server.exe nije pronadjen, a runtime download je preskocen. Server launch nece raditi dok se runtime ne preuzme.") | Out-Null
        }
    }

    Invoke-InstallStage -Number 7 -Name "Install or verify OpenCode" -Action {
        Set-InstallStatusDetail -Detail "Proveravam ili instaliram OpenCode CLI." -ActivityType "opencode" -ProgressPercent 60
        if ($SkipOpenCodeInstall) {
            Write-Host "Skipping OpenCode installation because -SkipOpenCodeInstall was requested." -ForegroundColor Yellow
            return
        }

        if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
            throw "npm nije dostupan, pa OpenCode ne moze da se instalira."
        }

        if (-not (Get-OpenCodeExecutable)) {
            Invoke-Native npm install -g opencode-ai
            if (-not (Get-OpenCodeExecutable)) {
                throw "OpenCode instalacija je zavrsena, ali komanda i dalje nije pronadjena."
            }
        }
    }

    Invoke-InstallStage -Number 8 -Name "Download or verify selected model" -Action {
        Set-InstallStatusDetail -Detail "Proveravam da li izabrani model vec postoji ili krecem download." -ActivityType "model-download" -ProgressPercent 70
        if ($SkipModelDownload) {
            Write-Host "Skipping model download because -SkipModelDownload was requested." -ForegroundColor Yellow
            return
        }

        if ((!(Test-Path $script:modelFile)) -or ((Get-Item $script:modelFile -ErrorAction SilentlyContinue).Length -lt [int64]$script:modelChoice.minExpectedBytes)) {
            [Environment]::SetEnvironmentVariable("LOCAL_QWEN_INSTALL_STATUS_PATH", $StatusPath, "Process")
            [Environment]::SetEnvironmentVariable("LOCAL_QWEN_INSTALL_STAGE", "8", "Process")
            try {
                Download-RecommendedModel `
                    -RepoId $script:modelChoice.source `
                    -Filename $script:modelChoice.filename `
                    -TargetPath $script:modelFile `
                    -MinExpectedBytes ([int64]$script:modelChoice.minExpectedBytes)
            } finally {
                [Environment]::SetEnvironmentVariable("LOCAL_QWEN_INSTALL_STATUS_PATH", $null, "Process")
                [Environment]::SetEnvironmentVariable("LOCAL_QWEN_INSTALL_STAGE", $null, "Process")
            }
        } else {
            Set-InstallStatusDetail -Detail "Model je vec prisutan i deluje kompletno; download nije potreban." -ActivityType "model-download" -ProgressPercent 80
        }
    }

    Invoke-InstallStage -Number 9 -Name "Apply settings and OpenCode wiring" -Action {
        Set-InstallStatusDetail -Detail "Upisujem LocalQwenHome settings i povezujem OpenCode sa lokalnim endpointom." -ActivityType "config" -ProgressPercent 82
        $settings = [ordered]@{
            profile = $Profile
            llama = [ordered]@{
                contextSize = $defaults.profiles.$Profile.contextSize
                maxOutputTokens = 8192
                contextSizeCustomized = $false
                maxOutputTokensCustomized = $false
            }
            opencode = [ordered]@{
                buildSteps = $defaults.opencode.steps.build
                planSteps = $defaults.opencode.steps.plan
                generalSteps = $defaults.opencode.steps.general
                exploreSteps = $defaults.opencode.steps.explore
            }
        }
        $settings | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $stateDir "settings.json") -Encoding UTF8

        Write-InstallState `
            -InstallRoot $InstallRoot `
            -DesktopTargetDir $desktopTargetDir `
            -UpstreamDir $upstreamDir `
            -TurboDir $turboDir `
            -LlamaBinDir $llamaBinDir `
            -ModelFile $script:modelFile `
            -ModelId $script:modelChoice.id `
            -Profile $Profile `
            -StatePath $statePath `
            -Defaults $defaults

        & (Get-WindowsPowerShellExe) -ExecutionPolicy Bypass -File (Join-Path $launchersDir "configure-settings.ps1") -Profile $Profile | Out-Host
        if ($LASTEXITCODE -ne 0) {
            $script:InstallWarnings.Add("OpenCode konfiguracija nije uspesno upisana tokom install toka. Pokreni configure-settings.ps1 ili Verify Local Qwen Install nakon instalacije.") | Out-Null
        }
    }

    Invoke-InstallStage -Number 10 -Name "Optional TurboQuant build and final verification" -Action {
        Set-InstallStatusDetail -Detail "Pokrecem opcioni TurboQuant build i zavrsnu proveru zdravlja instalacije." -ActivityType "turboquant" -ProgressPercent 90
        if (-not $SkipTurboQuantBuild -and $script:TurboQuantDependenciesReady) {
            & (Get-WindowsPowerShellExe) -ExecutionPolicy Bypass -File (Join-Path $launchersDir "build-turboquant.ps1")
            if ($LASTEXITCODE -ne 0) {
                $script:InstallWarnings.Add("TurboQuant build nije uspeo. Instalacija ostaje upotrebljiva kroz upstream llama.cpp fallback.") | Out-Null
            }
        } elseif (-not $script:TurboQuantDependenciesReady) {
            Write-Host "Skipping TurboQuant build because optional build dependencies are not ready." -ForegroundColor Yellow
        } else {
            Write-Host "Skipping TurboQuant build because -SkipTurboQuantBuild was requested." -ForegroundColor Yellow
        }

        $script:TurboServerExe = Join-Path $turboDir "$($defaults.turboquant.buildDir)\bin\llama-server.exe"
        Write-InstallState `
            -InstallRoot $InstallRoot `
            -DesktopTargetDir $desktopTargetDir `
            -UpstreamDir $upstreamDir `
            -TurboDir $turboDir `
            -LlamaBinDir $llamaBinDir `
            -ModelFile $script:modelFile `
            -ModelId $script:modelChoice.id `
            -Profile $Profile `
            -StatePath $statePath `
            -Defaults $defaults `
            -TurboServerExe $(if (Test-Path $script:TurboServerExe) { $script:TurboServerExe } else { $null })

        $preferredServerExe = if (Test-Path $script:TurboServerExe) {
            $script:TurboServerExe
        } else {
            Join-Path $llamaBinDir "llama-server.exe"
        }
        $filteredWarnings = @(Get-FilteredInstallWarnings -Warnings $script:InstallWarnings -PreferredServerExe $preferredServerExe -Port ([int]$defaults.server.port) -HasTurboRuntime:(Test-Path $script:TurboServerExe))
        $script:InstallWarnings = New-Object System.Collections.Generic.List[string]
        foreach ($warning in $filteredWarnings) {
            $script:InstallWarnings.Add([string]$warning) | Out-Null
        }

        Write-InstallReport `
            -InstallRoot $InstallRoot `
            -InstallRootStatePath $statePath `
            -InstallReportPath $installReportPath `
            -ModelFile $script:modelFile `
            -LlamaBinDir $llamaBinDir `
            -TurboDir $turboDir `
            -LaunchersDir $launchersDir `
            -DesktopTargetDir $desktopTargetDir `
            -Profile $Profile `
            -Warnings $script:InstallWarnings
    }

    $desktopShortcutState = if ((Test-Path (Join-Path $desktopTargetDir "Local Qwen Control Center.lnk")) -and (Test-Path (Join-Path $desktopTargetDir "OpenCode - Local Qwen.lnk"))) { "OK" } else { "MISSING ITEMS" }
    $summaryWarnings = @($script:InstallWarnings)
    if (Test-Path $installReportPath) {
        try {
            $reportData = Get-Content -Raw $installReportPath | ConvertFrom-Json
            if ($reportData.PSObject.Properties["warnings"]) {
                $summaryWarnings = @($reportData.warnings)
            }
        } catch {
        }
    }
    $summary = @"
Installation summary

- Install root: $InstallRoot
- Install state: $statePath
- Launchers root: $launchersDir
- Desktop folder: $desktopTargetDir
- Desktop shortcuts: $desktopShortcutState
- OpenCode global install: $(if (Get-OpenCodeExecutable) { 'OK' } else { 'NOT FOUND' })
- Model path: $script:modelFile
- Install report: $installReportPath
"@

    if ($summaryWarnings.Count -gt 0) {
        $summary += "`r`nWarnings:`r`n- " + ($summaryWarnings -join "`r`n- ")
    }

    $defaultSummaryPath = Join-Path $stateDir "install-summary.txt"
    Write-Utf8NoBomText -Path $defaultSummaryPath -Content $summary
    if (-not [string]::IsNullOrWhiteSpace($SummaryPath)) {
        Write-Utf8NoBomText -Path $SummaryPath -Content $summary
    }
    Write-InstallStatus -State "completed" -Detail "Instalacija je zavrsena. Mozes da pregledas summary i log pre klika na Finish." -ActivityType "complete" -ProgressPercent 100
    Write-Host "INSTALLATION COMPLETE" -ForegroundColor Green
    Write-Host $summary
} catch {
    Write-InstallStatus -State "failed" -Detail ("Instalacija je stala u koraku '{0}': {1}" -f $script:CurrentStageName, $_.Exception.Message) -ActivityType "failed"
    Write-Error ("Install failed during stage '{0}': {1}" -f $script:CurrentStageName, $_.Exception.Message)
    throw
} finally {
    if ($script:TranscriptStarted) {
        try {
            Stop-Transcript | Out-Null
        } catch {
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($LogPath) -and (Test-Path $LogPath)) {
        try {
            $logContent = Get-Content -LiteralPath $LogPath -Raw
            Write-Utf8NoBomText -Path $LogPath -Content $logContent
        } catch {
        }
    }
}
