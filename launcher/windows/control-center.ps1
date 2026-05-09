Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

. (Join-Path $PSScriptRoot "local-qwen-common.ps1")

$root = Get-LocalQwenRoot
$state = Get-InstallState
$script:LatestReleaseCache = $null
$script:LatestReleaseCacheAt = $null
$script:ModelUiLoaded = $false
$script:VisibleModelList = @()
$script:SettingsPresetsBundle = $null
$script:PendingSettingsProfile = $null
$script:SelectedSettingsPreset = $null
$script:SavedSettingsProfile = $null
$script:SavedSettingsContext = $null
$script:SavedSettingsOutput = $null
$script:SavedSettingsBuild = $null
$script:SavedSettingsPlan = $null
$script:SavedSettingsGeneral = $null
$script:SavedSettingsExplore = $null

$configureSettingsScript = Join-Path $PSScriptRoot "configure-settings.ps1"
$startServerScript = Join-Path $PSScriptRoot "start-server.ps1"
$stopServerScript = Join-Path $PSScriptRoot "stop-server.ps1"
$startOpenCodeScript = Join-Path $PSScriptRoot "start-opencode.ps1"
$launchAgentScript = Join-Path $PSScriptRoot "launch-agent.ps1"
$manageModelsScript = Join-Path $PSScriptRoot "manage-models.ps1"
$checkUpdatesScript = Join-Path $PSScriptRoot "check-updates.ps1"
$exportDiagnosticsScript = Join-Path $PSScriptRoot "export-diagnostics.ps1"
$repairInstallScript = Join-Path $PSScriptRoot "repair-install.ps1"
$repairModelScript = Join-Path $PSScriptRoot "repair-model.ps1"
$repairRuntimeScript = Join-Path $PSScriptRoot "repair-runtime.ps1"
$repairConfigScript = Join-Path $PSScriptRoot "repair-config.ps1"
$repairAppControlScript = Join-Path $PSScriptRoot "repair-app-control.ps1"
$iconPath = Join-Path $root "assets\icons\control-center.ico"

function Add-TrackFieldRow {
    param(
        [System.Windows.Forms.Control]$Parent,
        [string]$LabelText,
        [int]$Y,
        [int]$Minimum,
        [int]$Maximum,
        [int]$TickFrequency,
        [int]$Value,
        [int]$Increment = 1
    )

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $LabelText
    $label.Location = New-Object System.Drawing.Point(18, $Y)
    $label.Size = New-Object System.Drawing.Size(220, 22)
    $label.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $Parent.Controls.Add($label)

    $track = New-Object System.Windows.Forms.TrackBar
    $track.Location = New-Object System.Drawing.Point(18, ($Y + 22))
    $track.Size = New-Object System.Drawing.Size(420, 42)
    $track.Minimum = $Minimum
    $track.Maximum = $Maximum
    $track.TickFrequency = $TickFrequency
    $track.SmallChange = $Increment
    $track.LargeChange = [Math]::Max($Increment, $TickFrequency)
    $track.Value = [Math]::Min($Maximum, [Math]::Max($Minimum, $Value))
    $Parent.Controls.Add($track)

    $numeric = New-Object System.Windows.Forms.NumericUpDown
    $numeric.Location = New-Object System.Drawing.Point(455, ($Y + 24))
    $numeric.Size = New-Object System.Drawing.Size(130, 27)
    $numeric.Minimum = $Minimum
    $numeric.Maximum = $Maximum
    $numeric.Increment = $Increment
    $numeric.Value = $track.Value
    $numeric.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $Parent.Controls.Add($numeric)

    $trackHandler = {
        if ($numeric.Value -ne $track.Value) {
            $numeric.Value = $track.Value
        }
    }.GetNewClosure()

    $numericHandler = {
        $next = [int]$numeric.Value
        if ($track.Value -ne $next) {
            $track.Value = $next
        }
    }.GetNewClosure()

    $track.Add_ValueChanged($trackHandler)
    $numeric.Add_ValueChanged($numericHandler)

    return @{
        Track = $track
        Numeric = $numeric
    }
}

function Add-ContextRow {
    param(
        [System.Windows.Forms.Control]$Parent,
        [int]$Y,
        [int]$SelectedValue
    )

    $presets = @(65536, 131072, 196608, 262144, 327680)
    $presetLabels = @("64K", "128K", "192K", "256K", "320K")

    $label = New-Object System.Windows.Forms.Label
    $label.Text = "llama.cpp context size"
    $label.Location = New-Object System.Drawing.Point(18, $Y)
    $label.Size = New-Object System.Drawing.Size(220, 22)
    $label.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $Parent.Controls.Add($label)

    $track = New-Object System.Windows.Forms.TrackBar
    $track.Location = New-Object System.Drawing.Point(18, ($Y + 22))
    $track.Size = New-Object System.Drawing.Size(420, 42)
    $track.Minimum = 0
    $track.Maximum = $presets.Count - 1
    $track.TickFrequency = 1
    $Parent.Controls.Add($track)

    $selectedIndex = 0
    for ($i = 0; $i -lt $presets.Count; $i++) {
        if ($presets[$i] -eq $SelectedValue) {
            $selectedIndex = $i
            break
        }
        if ($SelectedValue -gt $presets[$i]) {
            $selectedIndex = $i
        }
    }
    $track.Value = $selectedIndex

    $combo = New-Object System.Windows.Forms.ComboBox
    $combo.Location = New-Object System.Drawing.Point(455, ($Y + 24))
    $combo.Size = New-Object System.Drawing.Size(130, 28)
    $combo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    foreach ($item in $presetLabels) {
        [void]$combo.Items.Add($item)
    }
    $combo.SelectedIndex = $selectedIndex
    $combo.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $Parent.Controls.Add($combo)

    $valueLabel = New-Object System.Windows.Forms.Label
    $valueLabel.Location = New-Object System.Drawing.Point(18, ($Y + 58))
    $valueLabel.Size = New-Object System.Drawing.Size(260, 22)
    $valueLabel.ForeColor = [System.Drawing.Color]::FromArgb(70, 70, 70)
    $Parent.Controls.Add($valueLabel)

    $syncContext = {
        $combo.SelectedIndex = $track.Value
        $valueLabel.Text = "Izabrano: $($presets[$track.Value]) tokena"
    }.GetNewClosure()

    $track.Add_ValueChanged($syncContext)
    $comboHandler = {
        if ($track.Value -ne $combo.SelectedIndex) {
            $track.Value = $combo.SelectedIndex
        }
    }.GetNewClosure()
    $combo.Add_SelectedIndexChanged($comboHandler)

    & $syncContext

    return @{
        Track = $track
        Combo = $combo
        Presets = $presets
    }
}

function Set-TextboxLines {
    param(
        [System.Windows.Forms.TextBox]$TextBox,
        [object]$Result
    )

    if ($null -eq $Result) {
        $TextBox.Text = ""
        return
    }

    if ($Result -is [System.Array]) {
        $TextBox.Text = ($Result -join [Environment]::NewLine)
    } else {
        $TextBox.Text = [string]$Result
    }
}

function Set-WorkerStatus {
    param(
        [string]$State,
        [string]$Detail
    )

    $workerStatusLabel.Text = "Status: $State$(if ($Detail) { ' | ' + $Detail } else { '' })"
}

function Invoke-BackgroundShellScript {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [string[]]$ArgumentList = @(),
        [scriptblock]$OnSuccess = $null,
        [scriptblock]$OnFinally = $null
    )

    Set-WorkerStatus -State "Working" -Detail $Name
    Write-LaunchMessage @("$Name je pokrenut u pozadini.")

    $job = Start-Job -ScriptBlock {
        param($Path, $Args)
        $lines = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Path @Args 2>&1
        $code = $LASTEXITCODE
        [pscustomobject]@{
            ExitCode = $code
            Output = @($lines)
        }
    } -ArgumentList $ScriptPath, $ArgumentList

    $poller = New-Object System.Windows.Forms.Timer
    $poller.Interval = 800
    $poller.Add_Tick({
        if ($job.State -in @('Completed', 'Failed', 'Stopped')) {
            $poller.Stop()
            $result = $null
            try {
                $result = Receive-Job -Job $job -Keep -ErrorAction SilentlyContinue | Select-Object -Last 1
            } catch {
            }

            $outputLines = @()
            if ($result -and $result.Output) {
                $outputLines = @($result.Output)
            } else {
                try {
                    $outputLines = @(Receive-Job -Job $job -ErrorAction SilentlyContinue)
                } catch {
                    $outputLines = @()
                }
            }

            $exitCode = if ($result -and $null -ne $result.ExitCode) { [int]$result.ExitCode } else { if ($job.State -eq 'Completed') { 0 } else { 1 } }
            if ($outputLines.Count -gt 0) {
                Write-LaunchMessage $outputLines
            }

            if ($exitCode -eq 0) {
                Set-WorkerStatus -State "Idle" -Detail "$Name zavrsen"
                if ($OnSuccess) {
                    & $OnSuccess
                }
            } else {
                Set-WorkerStatus -State "Error" -Detail "$Name nije uspeo"
            }

            if ($OnFinally) {
                & $OnFinally
            }

            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            $poller.Dispose()
        }
    })
    $poller.Start()
}

function Get-AgentAuditSummary {
    param(
        [string]$SecurityMode,
        [string]$CapabilityMode,
        [string]$WorkingFolder
    )

    try {
        $audit = Get-AgentAudit -SecurityMode $SecurityMode -CapabilityMode $CapabilityMode -WorkingFolder $WorkingFolder
        return [pscustomobject]@{
            Text = @(
                "Risk: $($audit.riskLevel.ToUpper())",
                ($audit.reasons -join [Environment]::NewLine)
            ) -join [Environment]::NewLine
            Color = switch ($audit.riskLevel) {
                "high" { [System.Drawing.Color]::FromArgb(176, 45, 45) }
                "medium" { [System.Drawing.Color]::FromArgb(176, 120, 18) }
                default { [System.Drawing.Color]::FromArgb(20, 120, 50) }
            }
        }
    } catch {
        return [pscustomobject]@{
            Text = "Risk audit nije dostupan."
            Color = [System.Drawing.Color]::FromArgb(70, 70, 70)
        }
    }
}

function Get-AgentMetaPath {
    return Join-Path $root "state\agent-launch-settings.json"
}

function Load-AgentMeta {
    $path = Get-AgentMetaPath
    if (Test-Path $path) {
        try {
            return Get-Content -Raw $path | ConvertFrom-Json
        } catch {
            return $null
        }
    }

    return $null
}

$settings = Get-Settings
$agentMeta = Load-AgentMeta
$modelCatalog = @()
$currentModelMeta = [pscustomobject]@{ id = [string]$state.modelId }
$recommendationBundle = $null
$script:PendingSettingsProfile = [string]$settings.profile
$script:SavedSettingsProfile = [string]$settings.profile
$script:SavedSettingsContext = [int]$settings.llama.contextSize
$script:SavedSettingsOutput = [int]$settings.llama.maxOutputTokens
$script:SavedSettingsBuild = [int]$settings.opencode.buildSteps
$script:SavedSettingsPlan = [int]$settings.opencode.planSteps
$script:SavedSettingsGeneral = [int]$settings.opencode.generalSteps
$script:SavedSettingsExplore = [int]$settings.opencode.exploreSteps

$form = New-Object System.Windows.Forms.Form
$form.Text = "Local Qwen Home Computer v$(Get-AppVersion)"
$form.StartPosition = "CenterScreen"
$form.Size = New-Object System.Drawing.Size(760, 800)
$form.MinimumSize = New-Object System.Drawing.Size(760, 800)
$form.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 251)
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$form.MaximizeBox = $true
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable

if (Test-Path $iconPath) {
    $form.Icon = New-Object System.Drawing.Icon($iconPath)
}

$title = New-Object System.Windows.Forms.Label
$title.Text = "Local Qwen 3.6 35B A3B Control Center"
$title.Location = New-Object System.Drawing.Point(16, 14)
$title.Size = New-Object System.Drawing.Size(520, 28)
$title.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 14, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = "Jedno mesto za pokretanje, podesavanja i agent rezim. Aktivna verzija: v$(Get-AppVersion)"
$subtitle.Location = New-Object System.Drawing.Point(20, 44)
$subtitle.Size = New-Object System.Drawing.Size(520, 22)
$subtitle.ForeColor = [System.Drawing.Color]::FromArgb(85, 85, 85)
$form.Controls.Add($subtitle)

$aboutButton = New-Object System.Windows.Forms.Button
$aboutButton.Text = "About"
$aboutButton.Location = New-Object System.Drawing.Point(620, 24)
$aboutButton.Size = New-Object System.Drawing.Size(104, 34)
$form.Controls.Add($aboutButton)

$statusStrip = New-Object System.Windows.Forms.StatusStrip
$statusStrip.SizingGrip = $false
$statusStrip.Dock = [System.Windows.Forms.DockStyle]::Bottom
$form.Controls.Add($statusStrip)

$workerStatusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$workerStatusLabel.Spring = $true
$workerStatusLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$workerStatusLabel.Text = "Status: Idle"
$statusStrip.Items.Add($workerStatusLabel) | Out-Null

$quickPanel = New-Object System.Windows.Forms.GroupBox
$quickPanel.Text = "Quick status / Quick actions"
$quickPanel.Location = New-Object System.Drawing.Point(18, 74)
$quickPanel.Size = New-Object System.Drawing.Size(706, 76)
$form.Controls.Add($quickPanel)

$quickServerLabel = New-Object System.Windows.Forms.Label
$quickServerLabel.Location = New-Object System.Drawing.Point(16, 22)
$quickServerLabel.Size = New-Object System.Drawing.Size(210, 20)
$quickServerLabel.Text = "Server: --"
$quickPanel.Controls.Add($quickServerLabel)

$quickModelLabel = New-Object System.Windows.Forms.Label
$quickModelLabel.Location = New-Object System.Drawing.Point(16, 46)
$quickModelLabel.Size = New-Object System.Drawing.Size(320, 20)
$quickModelLabel.Text = "Model: --"
$quickPanel.Controls.Add($quickModelLabel)

$quickHealthLabel = New-Object System.Windows.Forms.Label
$quickHealthLabel.Location = New-Object System.Drawing.Point(232, 22)
$quickHealthLabel.Size = New-Object System.Drawing.Size(150, 20)
$quickHealthLabel.Text = "Health: --"
$quickPanel.Controls.Add($quickHealthLabel)

$quickOpenCodeLabel = New-Object System.Windows.Forms.Label
$quickOpenCodeLabel.Location = New-Object System.Drawing.Point(232, 46)
$quickOpenCodeLabel.Size = New-Object System.Drawing.Size(150, 20)
$quickOpenCodeLabel.Text = "OpenCode: --"
$quickPanel.Controls.Add($quickOpenCodeLabel)

$quickThroughputLabel = New-Object System.Windows.Forms.Label
$quickThroughputLabel.Location = New-Object System.Drawing.Point(388, 22)
$quickThroughputLabel.Size = New-Object System.Drawing.Size(160, 20)
$quickThroughputLabel.Text = "Throughput: --"
$quickPanel.Controls.Add($quickThroughputLabel)

$quickSignalLabel = New-Object System.Windows.Forms.Label
$quickSignalLabel.Location = New-Object System.Drawing.Point(388, 46)
$quickSignalLabel.Size = New-Object System.Drawing.Size(160, 20)
$quickSignalLabel.ForeColor = [System.Drawing.Color]::FromArgb(90, 90, 90)
$quickSignalLabel.Text = "Signal: --"
$quickPanel.Controls.Add($quickSignalLabel)

$quickStartButton = New-Object System.Windows.Forms.Button
$quickStartButton.Text = "Start"
$quickStartButton.Location = New-Object System.Drawing.Point(556, 18)
$quickStartButton.Size = New-Object System.Drawing.Size(60, 22)
$quickPanel.Controls.Add($quickStartButton)

$quickStopButton = New-Object System.Windows.Forms.Button
$quickStopButton.Text = "Stop"
$quickStopButton.Location = New-Object System.Drawing.Point(622, 18)
$quickStopButton.Size = New-Object System.Drawing.Size(60, 22)
$quickPanel.Controls.Add($quickStopButton)

$quickOpenCodeButton = New-Object System.Windows.Forms.Button
$quickOpenCodeButton.Text = "OpenCode"
$quickOpenCodeButton.Location = New-Object System.Drawing.Point(556, 44)
$quickOpenCodeButton.Size = New-Object System.Drawing.Size(60, 22)
$quickPanel.Controls.Add($quickOpenCodeButton)

$quickRefreshButton = New-Object System.Windows.Forms.Button
$quickRefreshButton.Text = "Osvezi"
$quickRefreshButton.Location = New-Object System.Drawing.Point(622, 44)
$quickRefreshButton.Size = New-Object System.Drawing.Size(60, 22)
$quickPanel.Controls.Add($quickRefreshButton)

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Location = New-Object System.Drawing.Point(18, 158)
$tabs.Size = New-Object System.Drawing.Size(706, 562)
$form.Controls.Add($tabs)

$onboardingTab = New-Object System.Windows.Forms.TabPage
$onboardingTab.Text = "Onboarding"
$onboardingTab.BackColor = [System.Drawing.Color]::WhiteSmoke
$tabs.TabPages.Add($onboardingTab)

$healthTab = New-Object System.Windows.Forms.TabPage
$healthTab.Text = "Health"
$healthTab.BackColor = [System.Drawing.Color]::WhiteSmoke
$tabs.TabPages.Add($healthTab)

$launchTab = New-Object System.Windows.Forms.TabPage
$launchTab.Text = "Pokretanje"
$launchTab.BackColor = [System.Drawing.Color]::WhiteSmoke
$launchTab.AutoScroll = $true
$tabs.TabPages.Add($launchTab)

$settingsTab = New-Object System.Windows.Forms.TabPage
$settingsTab.Text = "Podesavanja"
$settingsTab.BackColor = [System.Drawing.Color]::WhiteSmoke
$tabs.TabPages.Add($settingsTab)

$agentTab = New-Object System.Windows.Forms.TabPage
$agentTab.Text = "Agent"
$agentTab.BackColor = [System.Drawing.Color]::WhiteSmoke
$tabs.TabPages.Add($agentTab)

$logsTab = New-Object System.Windows.Forms.TabPage
$logsTab.Text = "Logovi"
$logsTab.BackColor = [System.Drawing.Color]::WhiteSmoke
$tabs.TabPages.Add($logsTab)

$diagnosticsTab = New-Object System.Windows.Forms.TabPage
$diagnosticsTab.Text = "Diagnostics"
$diagnosticsTab.BackColor = [System.Drawing.Color]::WhiteSmoke
$tabs.TabPages.Add($diagnosticsTab)

$settingsPanel = New-Object System.Windows.Forms.Panel
$settingsPanel.Location = New-Object System.Drawing.Point(0, 0)
$settingsPanel.Size = New-Object System.Drawing.Size(698, 556)
$settingsPanel.AutoScroll = $true
$settingsTab.Controls.Add($settingsPanel)

$agentPanel = New-Object System.Windows.Forms.Panel
$agentPanel.Location = New-Object System.Drawing.Point(0, 0)
$agentPanel.Size = New-Object System.Drawing.Size(698, 556)
$agentPanel.AutoScroll = $true
$agentTab.Controls.Add($agentPanel)

$serverStatus = New-Object System.Windows.Forms.Label
$serverStatus.Location = New-Object System.Drawing.Point(18, 18)
$serverStatus.Size = New-Object System.Drawing.Size(620, 22)
$serverStatus.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10, [System.Drawing.FontStyle]::Bold)
$launchTab.Controls.Add($serverStatus)

$profileNote = New-Object System.Windows.Forms.Label
$profileNote.Location = New-Object System.Drawing.Point(18, 44)
$profileNote.Size = New-Object System.Drawing.Size(640, 22)
$profileNote.ForeColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
$launchTab.Controls.Add($profileNote)

$hardwareBox = New-Object System.Windows.Forms.TextBox
$hardwareBox.Location = New-Object System.Drawing.Point(18, 356)
$hardwareBox.Size = New-Object System.Drawing.Size(648, 110)
$hardwareBox.Multiline = $true
$hardwareBox.ScrollBars = "Vertical"
$hardwareBox.ReadOnly = $true
$hardwareBox.BackColor = [System.Drawing.Color]::White
$hardwareBox.Text = "Ovde ce biti prikazan hardver i efektivne runtime opcije."
$launchTab.Controls.Add($hardwareBox)

$liveThroughputPanel = New-Object System.Windows.Forms.GroupBox
$liveThroughputPanel.Text = "LIVE THROUGHPUT"
$liveThroughputPanel.Location = New-Object System.Drawing.Point(18, 176)
$liveThroughputPanel.Size = New-Object System.Drawing.Size(648, 96)
$liveThroughputPanel.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10, [System.Drawing.FontStyle]::Bold)
$liveThroughputPanel.BackColor = [System.Drawing.Color]::FromArgb(255, 250, 228)
$launchTab.Controls.Add($liveThroughputPanel)

$livePromptLabel = New-Object System.Windows.Forms.Label
$livePromptLabel.Location = New-Object System.Drawing.Point(18, 24)
$livePromptLabel.Size = New-Object System.Drawing.Size(180, 22)
$livePromptLabel.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
$livePromptLabel.Text = "Input: -- tok/s"
$liveThroughputPanel.Controls.Add($livePromptLabel)

$liveOutputLabel = New-Object System.Windows.Forms.Label
$liveOutputLabel.Location = New-Object System.Drawing.Point(224, 24)
$liveOutputLabel.Size = New-Object System.Drawing.Size(180, 22)
$liveOutputLabel.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
$liveOutputLabel.Text = "Output: -- tok/s"
$liveThroughputPanel.Controls.Add($liveOutputLabel)

$liveTotalLabel = New-Object System.Windows.Forms.Label
$liveTotalLabel.Location = New-Object System.Drawing.Point(430, 24)
$liveTotalLabel.Size = New-Object System.Drawing.Size(180, 22)
$liveTotalLabel.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
$liveTotalLabel.Text = "Total: -- tok/s"
$liveThroughputPanel.Controls.Add($liveTotalLabel)

$liveStateLabel = New-Object System.Windows.Forms.Label
$liveStateLabel.Location = New-Object System.Drawing.Point(18, 50)
$liveStateLabel.Size = New-Object System.Drawing.Size(610, 20)
$liveStateLabel.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5, [System.Drawing.FontStyle]::Bold)
$liveStateLabel.ForeColor = [System.Drawing.Color]::FromArgb(176, 120, 18)
$liveStateLabel.Text = "JOS NEMA MERENJA"
$liveThroughputPanel.Controls.Add($liveStateLabel)

$liveSignalLabel = New-Object System.Windows.Forms.Label
$liveSignalLabel.Location = New-Object System.Drawing.Point(18, 70)
$liveSignalLabel.Size = New-Object System.Drawing.Size(612, 18)
$liveSignalLabel.ForeColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
$liveSignalLabel.Text = "Signal: jos nema merenja. Pokreni Test prompt ili posalji zahtev kroz OpenCode."
$liveThroughputPanel.Controls.Add($liveSignalLabel)

$usagePanel = New-Object System.Windows.Forms.GroupBox
$usagePanel.Text = "Request activity"
$usagePanel.Location = New-Object System.Drawing.Point(18, 278)
$usagePanel.Size = New-Object System.Drawing.Size(648, 136)
$usagePanel.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10, [System.Drawing.FontStyle]::Bold)
$usagePanel.BackColor = [System.Drawing.Color]::FromArgb(245, 248, 255)
$launchTab.Controls.Add($usagePanel)

$usageCountLabel = New-Object System.Windows.Forms.Label
$usageCountLabel.Location = New-Object System.Drawing.Point(18, 24)
$usageCountLabel.Size = New-Object System.Drawing.Size(196, 22)
$usageCountLabel.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
$usageCountLabel.Text = "Zahtevi: 0"
$usagePanel.Controls.Add($usageCountLabel)

$usageLastMsLabel = New-Object System.Windows.Forms.Label
$usageLastMsLabel.Location = New-Object System.Drawing.Point(224, 24)
$usageLastMsLabel.Size = New-Object System.Drawing.Size(196, 22)
$usageLastMsLabel.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
$usageLastMsLabel.Text = "Avg odgovor: --"
$usagePanel.Controls.Add($usageLastMsLabel)

$usageSourceLabel = New-Object System.Windows.Forms.Label
$usageSourceLabel.Location = New-Object System.Drawing.Point(430, 24)
$usageSourceLabel.Size = New-Object System.Drawing.Size(196, 22)
$usageSourceLabel.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
$usageSourceLabel.Text = "Izvor: --"
$usagePanel.Controls.Add($usageSourceLabel)

$usageModelLabel = New-Object System.Windows.Forms.Label
$usageModelLabel.Location = New-Object System.Drawing.Point(18, 50)
$usageModelLabel.Size = New-Object System.Drawing.Size(196, 20)
$usageModelLabel.Text = "Aktivni model: --"
$usagePanel.Controls.Add($usageModelLabel)

$usageProfileLabel = New-Object System.Windows.Forms.Label
$usageProfileLabel.Location = New-Object System.Drawing.Point(224, 50)
$usageProfileLabel.Size = New-Object System.Drawing.Size(196, 20)
$usageProfileLabel.Text = "Aktivni profil: --"
$usagePanel.Controls.Add($usageProfileLabel)

$usageServerLabel = New-Object System.Windows.Forms.Label
$usageServerLabel.Location = New-Object System.Drawing.Point(430, 50)
$usageServerLabel.Size = New-Object System.Drawing.Size(196, 20)
$usageServerLabel.Text = "Server: --"
$usagePanel.Controls.Add($usageServerLabel)

$usageRecentBox = New-Object System.Windows.Forms.TextBox
$usageRecentBox.Location = New-Object System.Drawing.Point(18, 76)
$usageRecentBox.Size = New-Object System.Drawing.Size(610, 48)
$usageRecentBox.Multiline = $true
$usageRecentBox.ReadOnly = $true
$usageRecentBox.ScrollBars = "Vertical"
$usageRecentBox.BackColor = [System.Drawing.Color]::White
$usageRecentBox.Text = "Skorasnje aktivnosti ce se pojaviti ovde cim server primi zahteve."
$usagePanel.Controls.Add($usageRecentBox)

$throughputBox = New-Object System.Windows.Forms.TextBox
$throughputBox.Location = New-Object System.Drawing.Point(18, 422)
$throughputBox.Size = New-Object System.Drawing.Size(648, 82)
$throughputBox.Multiline = $true
$throughputBox.ScrollBars = "Vertical"
$throughputBox.ReadOnly = $true
$throughputBox.BackColor = [System.Drawing.Color]::FromArgb(255, 253, 242)
$throughputBox.Text = "JOS NEMA MERENJA.`r`nPokreni 'Test prompt' ili posalji normalan zahtev kroz server/OpenCode da bi se pojavili input/output tokeni po sekundi i istorija."
$launchTab.Controls.Add($throughputBox)

$launchOutput = New-Object System.Windows.Forms.TextBox
$launchOutput.Location = New-Object System.Drawing.Point(18, 518)
$launchOutput.Size = New-Object System.Drawing.Size(648, 112)
$launchOutput.Multiline = $true
$launchOutput.ScrollBars = "Vertical"
$launchOutput.ReadOnly = $true
$launchOutput.BackColor = [System.Drawing.Color]::White
$launchOutput.Text = "Ovde ce se pojavljivati status i rezultati akcija."
$launchTab.Controls.Add($launchOutput)

$logsLabel = New-Object System.Windows.Forms.Label
$logsLabel.Text = "Centralni pregled poslednjih logova"
$logsLabel.Location = New-Object System.Drawing.Point(18, 16)
$logsLabel.Size = New-Object System.Drawing.Size(320, 22)
$logsTab.Controls.Add($logsLabel)

$refreshLogsButton = New-Object System.Windows.Forms.Button
$refreshLogsButton.Text = "Osvezi logove"
$refreshLogsButton.Location = New-Object System.Drawing.Point(538, 12)
$refreshLogsButton.Size = New-Object System.Drawing.Size(128, 30)
$logsTab.Controls.Add($refreshLogsButton)

$logsMeta = New-Object System.Windows.Forms.TextBox
$logsMeta.Location = New-Object System.Drawing.Point(18, 48)
$logsMeta.Size = New-Object System.Drawing.Size(648, 88)
$logsMeta.Multiline = $true
$logsMeta.ScrollBars = "Vertical"
$logsMeta.ReadOnly = $true
$logsMeta.BackColor = [System.Drawing.Color]::White
$logsTab.Controls.Add($logsMeta)

$logsContent = New-Object System.Windows.Forms.TextBox
$logsContent.Location = New-Object System.Drawing.Point(18, 146)
$logsContent.Size = New-Object System.Drawing.Size(648, 374)
$logsContent.Multiline = $true
$logsContent.ScrollBars = "Vertical"
$logsContent.ReadOnly = $true
$logsContent.BackColor = [System.Drawing.Color]::White
$logsTab.Controls.Add($logsContent)

$diagnosticsLabel = New-Object System.Windows.Forms.Label
$diagnosticsLabel.Text = "Zivi pregled stanja i odluka sistema"
$diagnosticsLabel.Location = New-Object System.Drawing.Point(18, 16)
$diagnosticsLabel.Size = New-Object System.Drawing.Size(320, 22)
$diagnosticsTab.Controls.Add($diagnosticsLabel)

$refreshDiagnosticsButton = New-Object System.Windows.Forms.Button
$refreshDiagnosticsButton.Text = "Osvezi diagnostics"
$refreshDiagnosticsButton.Location = New-Object System.Drawing.Point(408, 12)
$refreshDiagnosticsButton.Size = New-Object System.Drawing.Size(128, 30)
$diagnosticsTab.Controls.Add($refreshDiagnosticsButton)

$exportDiagnosticsButton = New-Object System.Windows.Forms.Button
$exportDiagnosticsButton.Text = "Export bundle"
$exportDiagnosticsButton.Location = New-Object System.Drawing.Point(542, 12)
$exportDiagnosticsButton.Size = New-Object System.Drawing.Size(124, 30)
$diagnosticsTab.Controls.Add($exportDiagnosticsButton)

$diagnosticsMeta = New-Object System.Windows.Forms.TextBox
$diagnosticsMeta.Location = New-Object System.Drawing.Point(18, 48)
$diagnosticsMeta.Size = New-Object System.Drawing.Size(648, 112)
$diagnosticsMeta.Multiline = $true
$diagnosticsMeta.ScrollBars = "Vertical"
$diagnosticsMeta.ReadOnly = $true
$diagnosticsMeta.BackColor = [System.Drawing.Color]::White
$diagnosticsTab.Controls.Add($diagnosticsMeta)

$diagnosticsContent = New-Object System.Windows.Forms.TextBox
$diagnosticsContent.Location = New-Object System.Drawing.Point(18, 170)
$diagnosticsContent.Size = New-Object System.Drawing.Size(648, 350)
$diagnosticsContent.Multiline = $true
$diagnosticsContent.ScrollBars = "Vertical"
$diagnosticsContent.ReadOnly = $true
$diagnosticsContent.BackColor = [System.Drawing.Color]::White
$diagnosticsTab.Controls.Add($diagnosticsContent)

$healthLabel = New-Object System.Windows.Forms.Label
$healthLabel.Text = "Repair & Health Center"
$healthLabel.Location = New-Object System.Drawing.Point(18, 16)
$healthLabel.Size = New-Object System.Drawing.Size(280, 22)
$healthTab.Controls.Add($healthLabel)

$refreshHealthButton = New-Object System.Windows.Forms.Button
$refreshHealthButton.Text = "Osvezi health"
$refreshHealthButton.Location = New-Object System.Drawing.Point(538, 12)
$refreshHealthButton.Size = New-Object System.Drawing.Size(128, 30)
$healthTab.Controls.Add($refreshHealthButton)

$healthSummaryLabel = New-Object System.Windows.Forms.Label
$healthSummaryLabel.Text = "Stanje: --"
$healthSummaryLabel.Location = New-Object System.Drawing.Point(18, 48)
$healthSummaryLabel.Size = New-Object System.Drawing.Size(648, 24)
$healthSummaryLabel.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10, [System.Drawing.FontStyle]::Bold)
$healthTab.Controls.Add($healthSummaryLabel)

$healthActionPanel = New-Object System.Windows.Forms.Panel
$healthActionPanel.Location = New-Object System.Drawing.Point(18, 78)
$healthActionPanel.Size = New-Object System.Drawing.Size(648, 42)
$healthTab.Controls.Add($healthActionPanel)

$repairRuntimeHealthButton = New-Object System.Windows.Forms.Button
$repairRuntimeHealthButton.Text = "Repair runtime"
$repairRuntimeHealthButton.Location = New-Object System.Drawing.Point(0, 6)
$repairRuntimeHealthButton.Size = New-Object System.Drawing.Size(120, 30)
$healthActionPanel.Controls.Add($repairRuntimeHealthButton)

$repairModelHealthButton = New-Object System.Windows.Forms.Button
$repairModelHealthButton.Text = "Repair model"
$repairModelHealthButton.Location = New-Object System.Drawing.Point(132, 6)
$repairModelHealthButton.Size = New-Object System.Drawing.Size(120, 30)
$healthActionPanel.Controls.Add($repairModelHealthButton)

$repairConfigHealthButton = New-Object System.Windows.Forms.Button
$repairConfigHealthButton.Text = "Repair config"
$repairConfigHealthButton.Location = New-Object System.Drawing.Point(264, 6)
$repairConfigHealthButton.Size = New-Object System.Drawing.Size(120, 30)
$healthActionPanel.Controls.Add($repairConfigHealthButton)

$repairAllHealthButton = New-Object System.Windows.Forms.Button
$repairAllHealthButton.Text = "Repair all"
$repairAllHealthButton.Location = New-Object System.Drawing.Point(396, 6)
$repairAllHealthButton.Size = New-Object System.Drawing.Size(120, 30)
$healthActionPanel.Controls.Add($repairAllHealthButton)

$guidedRepairButton = New-Object System.Windows.Forms.Button
$guidedRepairButton.Text = "Guided repair"
$guidedRepairButton.Location = New-Object System.Drawing.Point(528, 6)
$guidedRepairButton.Size = New-Object System.Drawing.Size(120, 30)
$healthActionPanel.Controls.Add($guidedRepairButton)

$healthMeta = New-Object System.Windows.Forms.TextBox
$healthMeta.Location = New-Object System.Drawing.Point(18, 130)
$healthMeta.Size = New-Object System.Drawing.Size(648, 104)
$healthMeta.Multiline = $true
$healthMeta.ScrollBars = "Vertical"
$healthMeta.ReadOnly = $true
$healthMeta.BackColor = [System.Drawing.Color]::White
$healthTab.Controls.Add($healthMeta)

$healthContent = New-Object System.Windows.Forms.TextBox
$healthContent.Location = New-Object System.Drawing.Point(18, 246)
$healthContent.Size = New-Object System.Drawing.Size(648, 274)
$healthContent.Multiline = $true
$healthContent.ScrollBars = "Vertical"
$healthContent.ReadOnly = $true
$healthContent.BackColor = [System.Drawing.Color]::White
$healthTab.Controls.Add($healthContent)

$onboardingTitle = New-Object System.Windows.Forms.Label
$onboardingTitle.Text = "Prvi start i provera"
$onboardingTitle.Location = New-Object System.Drawing.Point(18, 16)
$onboardingTitle.Size = New-Object System.Drawing.Size(220, 22)
$onboardingTab.Controls.Add($onboardingTitle)

$onboardingBox = New-Object System.Windows.Forms.TextBox
$onboardingBox.Location = New-Object System.Drawing.Point(18, 48)
$onboardingBox.Size = New-Object System.Drawing.Size(648, 380)
$onboardingBox.Multiline = $true
$onboardingBox.ScrollBars = "Vertical"
$onboardingBox.ReadOnly = $true
$onboardingBox.BackColor = [System.Drawing.Color]::White
$onboardingTab.Controls.Add($onboardingBox)

$refreshOnboardingButton = New-Object System.Windows.Forms.Button
$refreshOnboardingButton.Text = "Osvezi onboarding"
$refreshOnboardingButton.Location = New-Object System.Drawing.Point(18, 440)
$refreshOnboardingButton.Size = New-Object System.Drawing.Size(150, 32)
$onboardingTab.Controls.Add($refreshOnboardingButton)

$nextActionLabel = New-Object System.Windows.Forms.Label
$nextActionLabel.Text = "Sledeci preporuceni korak"
$nextActionLabel.Location = New-Object System.Drawing.Point(18, 486)
$nextActionLabel.Size = New-Object System.Drawing.Size(220, 22)
$onboardingTab.Controls.Add($nextActionLabel)

$nextActionBox = New-Object System.Windows.Forms.TextBox
$nextActionBox.Location = New-Object System.Drawing.Point(18, 514)
$nextActionBox.Size = New-Object System.Drawing.Size(490, 50)
$nextActionBox.Multiline = $true
$nextActionBox.ReadOnly = $true
$nextActionBox.BackColor = [System.Drawing.Color]::White
$onboardingTab.Controls.Add($nextActionBox)

$runNextActionButton = New-Object System.Windows.Forms.Button
$runNextActionButton.Text = "Pokreni sledeci korak"
$runNextActionButton.Location = New-Object System.Drawing.Point(520, 520)
$runNextActionButton.Size = New-Object System.Drawing.Size(146, 38)
$onboardingTab.Controls.Add($runNextActionButton)

function Write-LaunchMessage {
    param([string[]]$Lines)

    $stamp = Get-Date -Format "HH:mm:ss"
    $prefix = "[$stamp]"
    $text = (($Lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join [Environment]::NewLine)
    if ([string]::IsNullOrWhiteSpace($text)) {
        return
    }

    if ([string]::IsNullOrWhiteSpace($launchOutput.Text) -or $launchOutput.Text -eq "Ovde ce se pojavljivati status i rezultati akcija.") {
        $launchOutput.Text = "$prefix $text"
    } else {
        $launchOutput.Text = "$prefix $text$([Environment]::NewLine)$([Environment]::NewLine)$($launchOutput.Text)"
    }
}

function Format-ServerPlan {
    param($Plan)

    $hardware = Get-HardwareProfileSummary -Profile $Plan.Profile
    $selectedModel = Get-ModelMetadata

    $runtime = if ($Plan.UsesTurboQuant) { "TurboQuant" } else { "Upstream fallback" }
    $gpu = if ($Plan.GpuName) { "$($Plan.GpuName) ($($Plan.GpuMemoryMiB) MiB)" } else { "GPU nije ocitan" }
    $cpu = if ($Plan.CpuName) { $Plan.CpuName } else { "CPU nije ocitan" }
    $ram = if ($Plan.SystemMemoryGiB) { "$($Plan.SystemMemoryGiB) GiB RAM" } else { "RAM nije ocitan" }
    $contextMode = if ($Plan.ContextCustomized) { "rucno zadat" } else { "auto / profil" }
    $outputMode = if ($Plan.OutputCustomized) { "rucno zadat" } else { "auto / profil" }
    $notes = if ($Plan.AdjustmentNotes.Count -gt 0) { $Plan.AdjustmentNotes -join [Environment]::NewLine } else { "Nema dodatnih ogranicenja." }

    return @(
        "Hardver",
        "GPU: $gpu",
        "CPU: $cpu",
        "Memorija: $ram",
        "",
        "Efektivni runtime plan",
        "Detektovana klasa: $($hardware.DetectedClass)",
        "Preporuceni profil: $($hardware.RecommendedProfile)",
        "Aktivni model: $($selectedModel.id)",
        "Preporuceni model: $($hardware.RecommendedModel.id)",
        "Profil: $($Plan.Profile)",
        "Runtime: $runtime",
        "Server: $($Plan.ServerExe)",
        "Port: $($Plan.Port)",
        "Threads: $($Plan.Threads)",
        "GPU layers (-ngl): $($Plan.GpuLayers)",
        "Experts na CPU (-ncmoe): $($Plan.Ncmoe)",
        "Context (-c): $($Plan.ContextSize) [$contextMode]",
        "Output (-n): $($Plan.MaxOutputTokens) [$outputMode]",
        "Cache K/V: $($Plan.CacheTypeK) / $($Plan.CacheTypeV)",
        "",
        "Napomene",
        $notes,
        "",
        "Zasto je ovo izabrano",
        $hardware.Reason
    ) -join [Environment]::NewLine
}

function Refresh-LogsView {
    $latest = Get-LatestLlamaLogs
    $metaLines = @(
        "Log folder: $($latest.LogDir)",
        "STDOUT: $(if ($latest.StdOut) { $latest.StdOut } else { 'nema' })",
        "STDERR: $(if ($latest.StdErr) { $latest.StdErr } else { 'nema' })",
        "Install summary: $(if ($latest.InstallSummary) { $latest.InstallSummary } else { 'nema' })",
        "Install report: $(if ($latest.InstallReport) { $latest.InstallReport } else { 'nema' })"
    )
    $logsMeta.Text = $metaLines -join [Environment]::NewLine

    $parts = New-Object System.Collections.Generic.List[string]

    if ($latest.StdErr) {
        $parts.Add("===== STDERR =====") | Out-Null
        $parts.Add((Get-Content $latest.StdErr -Raw -ErrorAction SilentlyContinue)) | Out-Null
    }
    if ($latest.StdOut) {
        $parts.Add("===== STDOUT =====") | Out-Null
        $parts.Add((Get-Content $latest.StdOut -Raw -ErrorAction SilentlyContinue)) | Out-Null
    }
    if ($latest.InstallSummary) {
        $parts.Add("===== INSTALL SUMMARY =====") | Out-Null
        $parts.Add((Get-Content $latest.InstallSummary -Raw -ErrorAction SilentlyContinue)) | Out-Null
    }
    if ($latest.InstallReport) {
        $parts.Add("===== INSTALL REPORT =====") | Out-Null
        $parts.Add((Get-Content $latest.InstallReport -Raw -ErrorAction SilentlyContinue)) | Out-Null
    }

    if ($parts.Count -eq 0) {
        $logsContent.Text = "Nema logova za prikaz."
    } else {
        $logsContent.Text = ($parts -join [Environment]::NewLine + [Environment]::NewLine)
    }
}

function Refresh-OnboardingView {
    $checklist = Get-OnboardingChecklist
    $nextAction = Get-NextActionRecommendation
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("Spremno za rad: $(if ($checklist.ready) { 'DA' } else { 'NE' })") | Out-Null
    $lines.Add("Profil: $($checklist.profile)") | Out-Null
    $lines.Add("Model: $($checklist.modelId)") | Out-Null
    $lines.Add("") | Out-Null
    foreach ($step in $checklist.steps) {
        $prefix = if ($step.status -eq "done") { "[OK]" } else { "[ ]" }
        $lines.Add("$prefix $($step.title)") | Out-Null
    }
    $lines.Add("") | Out-Null
    $lines.Add("Preporuka: ako nesto nije gotovo, idi redom od vrha na dole.") | Out-Null
    $onboardingBox.Text = ($lines -join [Environment]::NewLine)
    $nextActionBox.Text = "$($nextAction.title)$([Environment]::NewLine)$($nextAction.reason)"
}

function Refresh-HealthCenterView {
    $payload = Get-HealthCenterData
    $repairSummary = Get-RepairSummaryData

    $healthSummaryLabel.Text = "Stanje: $($payload.title) | Ozbiljnost: $($payload.severityLabel) ($($payload.severityScore)) | Profil: $($payload.profile) | Model: $($payload.modelId)"
    $healthSummaryLabel.ForeColor = switch ([string]$payload.overallState) {
        "healthy" { [System.Drawing.Color]::FromArgb(20, 120, 50) }
        "warming" { [System.Drawing.Color]::FromArgb(176, 120, 18) }
        "attention" { [System.Drawing.Color]::FromArgb(176, 120, 18) }
        default { [System.Drawing.Color]::FromArgb(180, 45, 45) }
    }

    $metaLines = @(
        "Summary: $($payload.summary)",
        "Service: $($payload.service.title)",
        "Service reason: $($payload.service.reason)",
        "Primary action: $($payload.primaryAction.title)",
        "Recommended actions: $(if ($payload.recommendedActions) { (@($payload.recommendedActions) | ForEach-Object { $_.title }) -join ', ' } else { 'nema' })",
        "Last repair: $(if ($repairSummary) { $repairSummary.repairedAt } else { 'nema repair summary-a' })"
    )
    $healthMeta.Text = $metaLines -join [Environment]::NewLine

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("Checks") | Out-Null
    foreach ($item in @($payload.checks)) {
        $prefix = if ($item.ok) { "[OK]" } else { "[!]" }
        $lines.Add("$prefix $($item.title)") | Out-Null
        $lines.Add("    $($item.description)") | Out-Null
    }
    if (@($payload.warnings).Count -gt 0) {
        $lines.Add("") | Out-Null
        $lines.Add("Warnings") | Out-Null
        foreach ($warning in @($payload.warnings)) {
            $lines.Add("- $($warning.title)") | Out-Null
        }
    }
    $lines.Add("") | Out-Null
    $lines.Add("Recommended actions") | Out-Null
    foreach ($item in @($payload.recommendedActions)) {
        $lines.Add("- $($item.title): $($item.reason)") | Out-Null
    }
    if ($repairSummary) {
        $lines.Add("") | Out-Null
        $lines.Add("Last repair summary") | Out-Null
        $lines.Add("Outcome: $($repairSummary.outcome)") | Out-Null
        $lines.Add("Found: $($repairSummary.counts.found) | Fixed: $($repairSummary.counts.fixed) | Manual: $($repairSummary.counts.manual)") | Out-Null
        if (@($repairSummary.fixed).Count -gt 0) {
            $lines.Add("Fixed items") | Out-Null
            foreach ($item in @($repairSummary.fixed)) {
                $lines.Add("- $item") | Out-Null
            }
        }
        if (@($repairSummary.manual).Count -gt 0) {
            $lines.Add("Manual items") | Out-Null
            foreach ($item in @($repairSummary.manual)) {
                $lines.Add("- $item") | Out-Null
            }
        }
        $lines.Add("Next step: $($repairSummary.nextStep)") | Out-Null
    }
    $healthContent.Text = $lines -join [Environment]::NewLine
    $guidedRepairButton.Text = if ($payload.primaryAction -and $payload.primaryAction.title) { "Guided: $($payload.primaryAction.title)" } else { "Guided repair" }
}

function Invoke-HealthRepairAction {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$ScriptPath
    )

    Invoke-BackgroundShellScript -Name $Name -ScriptPath $ScriptPath -OnSuccess {
        Refresh-HealthCenterView
        Refresh-LaunchStatus
        Refresh-LogsView
        Refresh-DiagnosticsView
        Refresh-OnboardingView
    }
}

function Invoke-HealthActionById {
    param([Parameter(Mandatory = $true)][string]$ActionId)

    switch ($ActionId) {
        "repair-runtime" { Invoke-HealthRepairAction -Name "Repair runtime" -ScriptPath $repairRuntimeScript }
        "repair-model" { Invoke-HealthRepairAction -Name "Repair model" -ScriptPath $repairModelScript }
        "repair-config" { Invoke-HealthRepairAction -Name "Repair config" -ScriptPath $repairConfigScript }
        "repair-app-control" { Invoke-HealthRepairAction -Name "Repair App Control" -ScriptPath $repairAppControlScript }
        "repair-all" { Invoke-HealthRepairAction -Name "Repair all" -ScriptPath $repairInstallScript }
        "start-server" {
            $profile = [string](Get-Settings).profile
            Start-LlamaBackground -Profile $profile
        }
        default {
            Write-LaunchMessage @("Nema mapirane health akcije za: $ActionId")
        }
    }
}

function Refresh-LaunchStatus {
    param(
        [switch]$Lightweight
    )

    $latest = Get-Settings
    $statusBundle = Get-EffectiveServiceStatus
    $summaryState = [string]$statusBundle.Summary.state
    $reason = [string]$statusBundle.Summary.reason
    switch ($summaryState) {
        "active" {
            $serverStatus.Text = "Server status: AKTIVAN na $(Get-LlamaHealthUrl)"
            $serverStatus.ForeColor = [System.Drawing.Color]::FromArgb(20, 120, 50)
        }
        "warming" {
            $serverStatus.Text = "Server status: STARTING / WARMING - servis se jos podize"
            $serverStatus.ForeColor = [System.Drawing.Color]::FromArgb(176, 120, 18)
        }
        "failed" {
            $serverStatus.Text = "Server status: START NIJE USPEO - proveri diagnostics i logove"
            $serverStatus.ForeColor = [System.Drawing.Color]::FromArgb(180, 45, 45)
        }
        default {
            $serverStatus.Text = "Server status: NIJE aktivan"
            $serverStatus.ForeColor = [System.Drawing.Color]::FromArgb(180, 45, 45)
        }
    }

    if (-not $Lightweight) {
        $plan = Get-EffectiveServerPlan -Profile ([string]$latest.profile)
        $selectedModel = Get-ModelMetadata
        $profileNote.Text = "Model: $($selectedModel.id) | Context: $($latest.llama.contextSize) | Output: $($latest.llama.maxOutputTokens) | Steps: B $($latest.opencode.buildSteps) / P $($latest.opencode.planSteps) / G $($latest.opencode.generalSteps) / E $($latest.opencode.exploreSteps) | Lifecycle: $summaryState$(if ($reason) { ' - ' + $reason } else { '' })"
        $hardwareBox.Text = Format-ServerPlan -Plan $plan
        if ($modelCombo) {
            $selectedIndex = 0
            for ($i = 0; $i -lt $modelCatalog.Count; $i++) {
                if ($modelCatalog[$i].id -eq $selectedModel.id) {
                    $selectedIndex = $i
                    break
                }
            }
            $modelCombo.SelectedIndex = $selectedIndex
        }
    } else {
        $profileNote.Text = "Context: $($latest.llama.contextSize) | Output: $($latest.llama.maxOutputTokens) | Steps: B $($latest.opencode.buildSteps) / P $($latest.opencode.planSteps) / G $($latest.opencode.generalSteps) / E $($latest.opencode.exploreSteps) | Lifecycle: $summaryState$(if ($reason) { ' - ' + $reason } else { '' })"
    }

    $quickServerLabel.Text = "Server: $([string]$statusBundle.Summary.title)"
    $quickHealthLabel.Text = "Health: $(if ($statusBundle.Health) { 'ok' } else { 'not-ready' })"
    $quickOpenCodeLabel.Text = "OpenCode: $(if (Test-Path (Get-OpenCodeConfigPath)) { 'config ok' } else { 'nema config' })"
    $quickModelLabel.Text = "Model: $([string]$state.modelId)"
}

function Refresh-DiagnosticsView {
    $statusBundle = Get-EffectiveServiceStatus
    $latestLogs = Get-LatestLlamaLogs
    $latestRelease = Get-LatestReleaseInfoCached
    $onboarding = Get-OnboardingChecklist
    $nextAction = Get-NextActionRecommendation
    $tokenMetrics = Get-TokenMetricsSummary
    $state = Get-InstallState
    $settings = Get-Settings
    $selectedModel = Get-ModelMetadata

    $metaLines = @(
        "Version: v$(Get-AppVersion)",
        "Lifecycle: $($statusBundle.Lifecycle.state)",
        "Effective state: $($statusBundle.Summary.state)",
        "Reason: $($statusBundle.Summary.reason)",
        "Health: $(if ($statusBundle.Health) { 'ok' } else { 'not-ready' })",
        "Profile: $($settings.profile)",
        "Model: $($selectedModel.id)",
        "Port: $($state.port)",
        "OpenCode config: $(Get-OpenCodeConfigPath)"
    )
    $diagnosticsMeta.Text = $metaLines -join [Environment]::NewLine

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("Latest release") | Out-Null
    $lines.Add("Current: v$(Get-AppVersion)") | Out-Null
    $lines.Add("GitHub latest: $($latestRelease.latestVersion)") | Out-Null
    $lines.Add("Update available: $(if ($latestRelease.updateAvailable) { 'da' } else { 'ne' })") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("Lifecycle details") | Out-Null
    $lines.Add("Updated: $($statusBundle.Lifecycle.updatedAt)") | Out-Null
    $lines.Add("Stdout: $($statusBundle.Lifecycle.stdout)") | Out-Null
    $lines.Add("Stderr: $($statusBundle.Lifecycle.stderr)") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("Token throughput") | Out-Null
    if ($tokenMetrics.current) {
        $lines.Add("Last prompt tok/s: $($tokenMetrics.current.promptTokensPerSecond)") | Out-Null
        $lines.Add("Last output tok/s: $($tokenMetrics.current.completionTokensPerSecond)") | Out-Null
        $lines.Add("Last total ms: $($tokenMetrics.current.totalMs)") | Out-Null
        $lines.Add("Average prompt tok/s: $($tokenMetrics.averages.promptTokensPerSecond)") | Out-Null
        $lines.Add("Average output tok/s: $($tokenMetrics.averages.completionTokensPerSecond)") | Out-Null
        foreach ($item in @($tokenMetrics.history)) {
            $lines.Add("- $($item.measuredAt): in $($item.promptTokensPerSecond) tok/s | out $($item.completionTokensPerSecond) tok/s") | Out-Null
        }
    } else {
        $lines.Add("Jos nema benchmark merenja. Pokreni 'Test prompt'.") | Out-Null
    }
    $lines.Add("") | Out-Null
    $lines.Add("Onboarding") | Out-Null
    $lines.Add("Ready: $(if ($onboarding.ready) { 'da' } else { 'ne' })") | Out-Null
    foreach ($step in $onboarding.steps) {
        $lines.Add("- $($step.title): $($step.status)") | Out-Null
    }
    $lines.Add("") | Out-Null
    $lines.Add("Next action") | Out-Null
    $lines.Add("$($nextAction.title)") | Out-Null
    $lines.Add("$($nextAction.reason)") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("Logs") | Out-Null
    $lines.Add("STDOUT: $(if ($latestLogs.StdOut) { $latestLogs.StdOut } else { 'nema' })") | Out-Null
    $lines.Add("STDERR: $(if ($latestLogs.StdErr) { $latestLogs.StdErr } else { 'nema' })") | Out-Null
    $lines.Add("Install report: $(if ($latestLogs.InstallReport) { $latestLogs.InstallReport } else { 'nema' })") | Out-Null
    $diagnosticsContent.Text = $lines -join [Environment]::NewLine
}

function Get-LatestReleaseInfoCached {
    $ttlSeconds = 600
    if ($script:LatestReleaseCache -and $script:LatestReleaseCacheAt) {
        $age = ((Get-Date) - $script:LatestReleaseCacheAt).TotalSeconds
        if ($age -lt $ttlSeconds) {
            return $script:LatestReleaseCache
        }
    }

    try {
        $script:LatestReleaseCache = Get-LatestReleaseInfo
        $script:LatestReleaseCacheAt = Get-Date
        return $script:LatestReleaseCache
    } catch {
        if ($script:LatestReleaseCache) {
            return $script:LatestReleaseCache
        }

        return [pscustomobject]@{
            latestVersion = "unknown"
            updateAvailable = $false
        }
    }
}

function Refresh-ThroughputView {
    $tokenMetrics = Get-TokenMetricsSummary
    $statusBundle = Get-EffectiveServiceStatus
    $usageModelLabel.Text = "Aktivni model: $([string](Get-InstallState).modelId)"
    $usageProfileLabel.Text = "Aktivni profil: $([string](Get-Settings).profile)"
    $usageServerLabel.Text = "Server: $([string]$statusBundle.Summary.title)"
    if (-not $tokenMetrics.current) {
        $livePromptLabel.Text = "Input: -- tok/s"
        $liveOutputLabel.Text = "Output: -- tok/s"
        $liveTotalLabel.Text = "Total: -- tok/s"
        $liveStateLabel.Text = "JOS NEMA MERENJA"
        $liveStateLabel.ForeColor = [System.Drawing.Color]::FromArgb(176, 120, 18)
        $liveSignalLabel.Text = "Signal: jos nema merenja. Pokreni Test prompt ili posalji zahtev kroz OpenCode."
        $quickThroughputLabel.Text = "Throughput: --"
        $quickSignalLabel.Text = "Signal: nema podataka"
        $usageCountLabel.Text = "Zahtevi: 0"
        $usageLastMsLabel.Text = "Avg odgovor: --"
        $usageSourceLabel.Text = "Izvor: jos nema merenja"
        $usageRecentBox.Text = "Skorasnje aktivnosti ce se pojaviti ovde cim server primi zahteve."
        $throughputBox.Text = "JOS NEMA MERENJA.`r`nPokreni 'Test prompt' ili posalji normalan zahtev kroz server/OpenCode da bi se pojavili input/output tokeni po sekundi i istorija."
        return
    }

    $measuredAt = $null
    try {
        $measuredAt = [datetime]::Parse([string]$tokenMetrics.current.measuredAt)
    } catch {
        $measuredAt = $null
    }
    $ageText = if ($measuredAt) {
        $seconds = [math]::Max(0, [int]((Get-Date) - $measuredAt).TotalSeconds)
        "pre $seconds s"
    } else {
        "vreme nepoznato"
    }

    $livePromptLabel.Text = "Input: $($tokenMetrics.current.promptTokensPerSecond) tok/s"
    $liveOutputLabel.Text = "Output: $($tokenMetrics.current.completionTokensPerSecond) tok/s"
    $liveTotalLabel.Text = "Total: $($tokenMetrics.current.totalTokensPerSecond) tok/s"
    $liveStateLabel.Text = "LIVE METRIKE SU DOSTUPNE"
    $liveStateLabel.ForeColor = [System.Drawing.Color]::FromArgb(20, 120, 50)
    $liveSignalLabel.Text = "Signal: poslednji zahtev $ageText | merenja: $($tokenMetrics.historyCount)"
    $quickThroughputLabel.Text = "Throughput: $($tokenMetrics.current.totalTokensPerSecond) tok/s"
    $quickSignalLabel.Text = "Signal: $ageText"
    $usageCountLabel.Text = "Zahtevi: $($tokenMetrics.requestCount)"
    $usageLastMsLabel.Text = "Avg odgovor: $($tokenMetrics.activity.averageTotalMs) ms"
    $usageSourceLabel.Text = "Izvor: $($tokenMetrics.activity.lastSource) | Label: $($tokenMetrics.lastLabel)"

    $recentLines = @()
    foreach ($item in @($tokenMetrics.activity.recentActivities)) {
        $recentLines += "$($item.measuredAt) | $($item.source) | $($item.label) | $($item.totalMs) ms | $($item.status)"
    }
    if ($recentLines.Count -eq 0) {
        $usageRecentBox.Text = "Skorasnje aktivnosti ce se pojaviti ovde cim server primi zahteve."
    } else {
        $usageRecentBox.Text = "Poslednjih $($recentLines.Count) aktivnosti:`r`n$($recentLines -join [Environment]::NewLine)"
    }

    $historyLines = @()
    foreach ($item in @($tokenMetrics.history)) {
        $historyLines += "$($item.promptTokensPerSecond) / $($item.completionTokensPerSecond) / $($item.totalTokensPerSecond) tok/s"
    }

    $throughputBox.Text = @(
        "Poslednje merenje: prompt $($tokenMetrics.current.promptTokensPerSecond) tok/s | output $($tokenMetrics.current.completionTokensPerSecond) tok/s | total $($tokenMetrics.current.totalTokensPerSecond) tok/s | total $($tokenMetrics.current.totalMs) ms",
        "Prosek istorije: prompt $($tokenMetrics.averages.promptTokensPerSecond) tok/s | output $($tokenMetrics.averages.completionTokensPerSecond) tok/s | total $($tokenMetrics.averages.totalTokensPerSecond) tok/s",
        "Aktivnost: avg odgovor $($tokenMetrics.activity.averageTotalMs) ms | test prompt $($tokenMetrics.activity.sources.testPrompt) | OpenCode $($tokenMetrics.activity.sources.opencode) | ostalo $($tokenMetrics.activity.sources.other)",
        "Istorija: $($historyLines -join '   ;   ')"
    ) -join [Environment]::NewLine
}

function Ensure-ModelUiState {
    if ($script:ModelUiLoaded) {
        return
    }

    $modelCatalog = @(Get-ModelCatalog)
    $currentModelMeta = Get-ModelMetadata
    $recommendationBundle = Get-RecommendationBundle
    $script:SettingsPresetsBundle = Get-SettingsPresetsBundle
    $script:ModelUiLoaded = $true

    Apply-ModelFilters
}

function Set-SettingsProfileVisuals {
    if ($settingsProfileLabel) {
        $settingsProfileLabel.Text = "Profil koji ce biti sacuvan: $($script:PendingSettingsProfile)"
    }
}

function Update-SavedSettingsSnapshot {
    param(
        [string]$Profile,
        [int]$ContextSize,
        [int]$MaxOutputTokens,
        [int]$BuildSteps,
        [int]$PlanSteps,
        [int]$GeneralSteps,
        [int]$ExploreSteps
    )

    $script:SavedSettingsProfile = $Profile
    $script:SavedSettingsContext = $ContextSize
    $script:SavedSettingsOutput = $MaxOutputTokens
    $script:SavedSettingsBuild = $BuildSteps
    $script:SavedSettingsPlan = $PlanSteps
    $script:SavedSettingsGeneral = $GeneralSteps
    $script:SavedSettingsExplore = $ExploreSteps
}

function Get-SettingsPresetById {
    param([string]$PresetId)

    Ensure-ModelUiState
    foreach ($item in @($script:SettingsPresetsBundle.presets)) {
        if ([string]$item.id -eq [string]$PresetId) {
            return $item
        }
    }
    return $null
}

function Format-SettingsPresetText {
    param($Preset)

    if (-not $Preset) {
        return "Izaberi quick preset da odmah dobijes i objasnjenje i spremne vrednosti za cuvanje."
    }

    return @(
        "$($Preset.title) | profil: $($Preset.profile)",
        "Za koga je: $($Preset.target)",
        "Sta radi: $($Preset.summary)",
        "Tradeoff: $($Preset.tradeoff)",
        "Vrednosti: ctx $($Preset.contextSize) | out $($Preset.maxOutputTokens) | build $($Preset.buildSteps) | plan $($Preset.planSteps) | general $($Preset.generalSteps) | explore $($Preset.exploreSteps)"
    ) -join [Environment]::NewLine
}

function Update-SettingsPresetCompareText {
    param([string]$PresetId)

    if (-not $presetCompareBox) {
        return
    }
    if (-not $PresetId) {
        $presetCompareBox.Text = "Compare pregled ce ovde pokazati sta bi se promenilo u odnosu na trenutno sacuvane vrednosti."
        return
    }

    try {
        $preview = Get-SettingsPresetPreview `
            -PresetId $PresetId `
            -CurrentProfile $script:SavedSettingsProfile `
            -CurrentContext $script:SavedSettingsContext `
            -CurrentOutput $script:SavedSettingsOutput `
            -CurrentBuild $script:SavedSettingsBuild `
            -CurrentPlan $script:SavedSettingsPlan `
            -CurrentGeneral $script:SavedSettingsGeneral `
            -CurrentExplore $script:SavedSettingsExplore
        $presetCompareBox.Text = @(
            "Sta ce se promeniti u odnosu na trenutno sacuvano stanje:",
            (@($preview.compareLines) -join [Environment]::NewLine)
        ) -join [Environment]::NewLine
    } catch {
        $presetCompareBox.Text = "Compare pregled nije dostupan."
    }
}

function Try-SelectVisibleModelById {
    param([string]$ModelId)

    if (-not $ModelId) {
        return $false
    }
    for ($i = 0; $i -lt $script:VisibleModelList.Count; $i++) {
        if ([string]$script:VisibleModelList[$i].id -eq [string]$ModelId) {
            $modelCombo.SelectedIndex = $i
            return $true
        }
    }
    return $false
}

function Apply-SettingsPresetToForm {
    param([string]$PresetId)

    $preset = Get-SettingsPresetById -PresetId $PresetId
    if (-not $preset) {
        throw "Quick preset nije pronadjen: $PresetId"
    }

    $script:SelectedSettingsPreset = $preset
    $script:PendingSettingsProfile = [string]$preset.profile

    $contextIndex = 0
    for ($i = 0; $i -lt $contextRow.Presets.Count; $i++) {
        if ([int]$contextRow.Presets[$i] -eq [int]$preset.contextSize) {
            $contextIndex = $i
            break
        }
    }
    $contextRow.Track.Value = $contextIndex
    $outputRow.Numeric.Value = [Math]::Min([decimal]$outputRow.Numeric.Maximum, [decimal]([int]$preset.maxOutputTokens))
    $buildRow.Numeric.Value = [Math]::Min([decimal]$buildRow.Numeric.Maximum, [decimal]([int]$preset.buildSteps))
    $planRow.Numeric.Value = [Math]::Min([decimal]$planRow.Numeric.Maximum, [decimal]([int]$preset.planSteps))
    $generalRow.Numeric.Value = [Math]::Min([decimal]$generalRow.Numeric.Maximum, [decimal]([int]$preset.generalSteps))
    $exploreRow.Numeric.Value = [Math]::Min([decimal]$exploreRow.Numeric.Maximum, [decimal]([int]$preset.exploreSteps))

    if ($presetInfoBox) {
        $presetInfoBox.Text = Format-SettingsPresetText -Preset $preset
    }
    Update-SettingsPresetCompareText -PresetId ([string]$preset.id)
    Set-SettingsProfileVisuals

    $selectedModelApplied = $false
    if ($preset.modelId) {
        $selectedModelApplied = Try-SelectVisibleModelById -ModelId ([string]$preset.modelId)
    }
    Refresh-ModelSelectionInfo

    $settingsStatus.Text = "Quick preset pripremljen: $($preset.title)"
    $settingsStatus.ForeColor = [System.Drawing.Color]::FromArgb(70, 70, 70)

    if ($selectedModelApplied) {
        Write-LaunchMessage @("Quick preset '$($preset.title)' je pripremljen. Klikni 'Sacuvaj podesavanja' da postane aktivan.")
    } else {
        Write-LaunchMessage @("Quick preset '$($preset.title)' je pripremljen. Model izbor ostaje kakav je trenutno vidljiv pod aktivnim filterima.")
    }
}

function Save-SettingsFromForm {
    Ensure-ModelUiState
    $contextValue = $contextRow.Presets[$contextRow.Track.Value]
    if ($modelCombo.SelectedIndex -lt 0 -or $modelCombo.SelectedIndex -ge $script:VisibleModelList.Count) {
        throw "Nijedan model nije dostupan za aktivne filtere."
    }
    $selectedModel = $script:VisibleModelList[$modelCombo.SelectedIndex]
    if ($selectedModel) {
        & powershell.exe -ExecutionPolicy Bypass -File $manageModelsScript -ModelId ([string]$selectedModel.id) 2>&1 | Out-Null
    }
    $result = & powershell.exe -ExecutionPolicy Bypass -File $configureSettingsScript `
        -Profile $script:PendingSettingsProfile `
        -ContextSize $contextValue `
        -MaxOutputTokens ([int]$outputRow.Numeric.Value) `
        -BuildSteps ([int]$buildRow.Numeric.Value) `
        -PlanSteps ([int]$planRow.Numeric.Value) `
        -GeneralSteps ([int]$generalRow.Numeric.Value) `
        -ExploreSteps ([int]$exploreRow.Numeric.Value) 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw ($result -join [Environment]::NewLine)
    }

    Update-SavedSettingsSnapshot `
        -Profile $script:PendingSettingsProfile `
        -ContextSize $contextValue `
        -MaxOutputTokens ([int]$outputRow.Numeric.Value) `
        -BuildSteps ([int]$buildRow.Numeric.Value) `
        -PlanSteps ([int]$planRow.Numeric.Value) `
        -GeneralSteps ([int]$generalRow.Numeric.Value) `
        -ExploreSteps ([int]$exploreRow.Numeric.Value)
    Update-SettingsPresetCompareText -PresetId $(if ($script:SelectedSettingsPreset) { [string]$script:SelectedSettingsPreset.id } else { $null })
    $settingsStatus.Text = "Sacuvano za buduca pokretanja."
    $settingsStatus.ForeColor = [System.Drawing.Color]::FromArgb(20, 120, 50)
    Write-LaunchMessage @($result)
    Refresh-LaunchStatus
    return $true
}

function Apply-ModelFilters {
    if (-not $script:ModelUiLoaded -or -not $modelCombo) {
        return
    }

    $selectedModelId = $null
    if ($modelCombo.SelectedIndex -ge 0 -and $modelCombo.SelectedIndex -lt $script:VisibleModelList.Count) {
        $selectedModelId = [string]$script:VisibleModelList[$modelCombo.SelectedIndex].id
    } elseif ($currentModelMeta) {
        $selectedModelId = [string]$currentModelMeta.id
    }

    $filteredPayload = Get-FilteredModelCatalog `
        -VerifiedOnly:([bool]($verifiedOnlyCheck -and $verifiedOnlyCheck.Checked)) `
        -CoderOnly:([bool]($coderOnlyCheck -and $coderOnlyCheck.Checked)) `
        -FitOnly:([bool]($fitOnlyCheck -and $fitOnlyCheck.Checked))

    $script:VisibleModelList = @($filteredPayload.models)
    $modelCombo.Items.Clear()
    foreach ($item in $script:VisibleModelList) {
        [void]$modelCombo.Items.Add("$($item.label) | $($item.family) | $($item.approxSizeGiB) GiB")
    }

    if ($modelCombo.Items.Count -eq 0) {
        $modelCombo.SelectedIndex = -1
        return
    }

    $initialModelIndex = -1
    if ($selectedModelId) {
        for ($i = 0; $i -lt $script:VisibleModelList.Count; $i++) {
            if ($script:VisibleModelList[$i].id -eq $selectedModelId) {
                $initialModelIndex = $i
                break
            }
        }
    }
    if ($initialModelIndex -lt 0 -and $recommendationBundle -and $recommendationBundle.recommendedModel) {
        for ($i = 0; $i -lt $script:VisibleModelList.Count; $i++) {
            if ($script:VisibleModelList[$i].id -eq $recommendationBundle.recommendedModel.id) {
                $initialModelIndex = $i
                break
            }
        }
    }
    if ($initialModelIndex -lt 0) {
        $initialModelIndex = 0
    }

    $modelCombo.SelectedIndex = $initialModelIndex
}

function Refresh-ModelSelectionInfo {
    try {
        Ensure-ModelUiState
        if (-not $modelCombo) {
            return
        }
        if ($script:VisibleModelList.Count -eq 0 -or $modelCombo.SelectedIndex -lt 0 -or $modelCombo.SelectedIndex -ge $script:VisibleModelList.Count) {
            $modelInfoBox.Text = "Nijedan model ne odgovara aktivnim filterima."
            return
        }

        $selectedModel = $script:VisibleModelList[$modelCombo.SelectedIndex]
        $downloadCandidates = Get-DownloadCandidates
        $selectedFit = $null
        $selectedGroup = "nepoznato"

        foreach ($groupName in @("recommended", "canRun", "notRecommended")) {
            foreach ($item in @($downloadCandidates.groups.$groupName)) {
                if ($item.id -eq $selectedModel.id) {
                    $selectedFit = $item
                    $selectedGroup = $groupName
                    break
                }
            }
            if ($selectedFit) {
                break
            }
        }

        $statusText = switch ($selectedGroup) {
            "recommended" { "preporucen za ovu masinu" }
            "canRun" { "moze da radi uz kompromis" }
            "notRecommended" { "nije preporucen za ovu konfiguraciju" }
            default { "status nije poznat" }
        }

        $fitReasons = if ($selectedFit -and $selectedFit.fitReasons) {
            (@($selectedFit.fitReasons) | Select-Object -First 3) -join " "
        } else {
            ""
        }

        $modelInfoBox.Text = @(
            "Status: $statusText"
            "Family: $($selectedModel.family) | Agentic: $($selectedModel.agenticScore)/10 | OpenCode: $($selectedModel.opencodeFit)/10 | Speed: $($selectedModel.speedEstimateLabel)"
            "Installed: $($selectedModel.installedSizeGiB) GiB | Need disk: $($selectedModel.diskNeededGiB) GiB | Free disk: $($selectedModel.freeDiskGiB) GiB | Enough disk: $(if ($selectedModel.hasEnoughDisk) { 'da' } else { 'ne' })"
            "GPU prag: $($selectedModel.minimumGpuMiB) MiB | Preporuceni GPU: $($selectedModel.recommendedGpuMiB) MiB | RAM: $($selectedModel.minimumRamGiB) GiB"
            "Opis: $($selectedModel.description)"
            "Badge: $($(if ($selectedModel.useCaseBadges -and @($selectedModel.useCaseBadges).Count -gt 0) { @($selectedModel.useCaseBadges) -join ', ' } else { 'nema posebne oznake' }))"
            "$(if ($fitReasons) { 'Fit: ' + $fitReasons } else { '' })"
        ) -join [Environment]::NewLine
    } catch {
        $modelInfoBox.Text = "Model info trenutno nije dostupna."
    }
}

function Refresh-ModelUiFromInstallState {
    try {
        $currentModelMeta = Get-ModelMetadata
        Apply-ModelFilters
        Refresh-ModelSelectionInfo
    } catch {
    }
}

function Show-ModelBrowserDialog {
    Ensure-ModelUiState

    $browserForm = New-Object System.Windows.Forms.Form
    $browserForm.Text = "Model browser"
    $browserForm.StartPosition = "CenterParent"
    $browserForm.Size = New-Object System.Drawing.Size(1120, 720)
    $browserForm.MinimumSize = New-Object System.Drawing.Size(980, 640)
    $browserForm.BackColor = [System.Drawing.Color]::WhiteSmoke
    $browserForm.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    if (Test-Path $iconPath) {
        $browserForm.Icon = New-Object System.Drawing.Icon($iconPath)
    }

    $searchLabel = New-Object System.Windows.Forms.Label
    $searchLabel.Text = "Pretraga"
    $searchLabel.Location = New-Object System.Drawing.Point(18, 18)
    $searchLabel.Size = New-Object System.Drawing.Size(80, 22)
    $browserForm.Controls.Add($searchLabel)

    $searchBox = New-Object System.Windows.Forms.TextBox
    $searchBox.Location = New-Object System.Drawing.Point(18, 42)
    $searchBox.Size = New-Object System.Drawing.Size(250, 28)
    $browserForm.Controls.Add($searchBox)

    $familyLabel = New-Object System.Windows.Forms.Label
    $familyLabel.Text = "Family"
    $familyLabel.Location = New-Object System.Drawing.Point(286, 18)
    $familyLabel.Size = New-Object System.Drawing.Size(80, 22)
    $browserForm.Controls.Add($familyLabel)

    $familyCombo = New-Object System.Windows.Forms.ComboBox
    $familyCombo.Location = New-Object System.Drawing.Point(286, 42)
    $familyCombo.Size = New-Object System.Drawing.Size(180, 28)
    $familyCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    [void]$familyCombo.Items.Add("Sve")
    foreach ($familyName in (($modelCatalog | ForEach-Object { [string]$_.family } | Sort-Object -Unique))) {
        [void]$familyCombo.Items.Add($familyName)
    }
    $familyCombo.SelectedIndex = 0
    $browserForm.Controls.Add($familyCombo)

    $installedOnlyBrowser = New-Object System.Windows.Forms.CheckBox
    $installedOnlyBrowser.Text = "Samo installed"
    $installedOnlyBrowser.Location = New-Object System.Drawing.Point(486, 44)
    $installedOnlyBrowser.Size = New-Object System.Drawing.Size(120, 24)
    $browserForm.Controls.Add($installedOnlyBrowser)

    $recommendedOnlyBrowser = New-Object System.Windows.Forms.CheckBox
    $recommendedOnlyBrowser.Text = "Samo preporuceni"
    $recommendedOnlyBrowser.Location = New-Object System.Drawing.Point(614, 44)
    $recommendedOnlyBrowser.Size = New-Object System.Drawing.Size(140, 24)
    $browserForm.Controls.Add($recommendedOnlyBrowser)

    $fitOnlyBrowser = New-Object System.Windows.Forms.CheckBox
    $fitOnlyBrowser.Text = "Samo za ovu masinu"
    $fitOnlyBrowser.Location = New-Object System.Drawing.Point(762, 44)
    $fitOnlyBrowser.Size = New-Object System.Drawing.Size(150, 24)
    $fitOnlyBrowser.Checked = $true
    $browserForm.Controls.Add($fitOnlyBrowser)

    $coderOnlyBrowser = New-Object System.Windows.Forms.CheckBox
    $coderOnlyBrowser.Text = "Samo coder"
    $coderOnlyBrowser.Location = New-Object System.Drawing.Point(486, 72)
    $coderOnlyBrowser.Size = New-Object System.Drawing.Size(110, 24)
    $browserForm.Controls.Add($coderOnlyBrowser)

    $verifiedOnlyBrowser = New-Object System.Windows.Forms.CheckBox
    $verifiedOnlyBrowser.Text = "Samo verified"
    $verifiedOnlyBrowser.Location = New-Object System.Drawing.Point(614, 72)
    $verifiedOnlyBrowser.Size = New-Object System.Drawing.Size(120, 24)
    $verifiedOnlyBrowser.Checked = $true
    $browserForm.Controls.Add($verifiedOnlyBrowser)

    $refreshBrowserButton = New-Object System.Windows.Forms.Button
    $refreshBrowserButton.Text = "Osvezi"
    $refreshBrowserButton.Location = New-Object System.Drawing.Point(930, 56)
    $refreshBrowserButton.Size = New-Object System.Drawing.Size(90, 30)
    $browserForm.Controls.Add($refreshBrowserButton)

    $summaryLabel = New-Object System.Windows.Forms.Label
    $summaryLabel.Text = "Ucitavam model browser..."
    $summaryLabel.Location = New-Object System.Drawing.Point(18, 80)
    $summaryLabel.Size = New-Object System.Drawing.Size(1000, 22)
    $browserForm.Controls.Add($summaryLabel)

    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Location = New-Object System.Drawing.Point(18, 108)
    $grid.Size = New-Object System.Drawing.Size(1068, 360)
    $grid.ReadOnly = $true
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.AllowUserToResizeRows = $false
    $grid.MultiSelect = $false
    $grid.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
    $grid.RowHeadersVisible = $false
    $grid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $grid.BackgroundColor = [System.Drawing.Color]::White
    $grid.Columns.Add("status", "Status") | Out-Null
    $grid.Columns.Add("id", "Model") | Out-Null
    $grid.Columns.Add("family", "Family") | Out-Null
    $grid.Columns.Add("fit", "Fit") | Out-Null
    $grid.Columns.Add("size", "Velicina") | Out-Null
    $grid.Columns.Add("speed", "Brzina") | Out-Null
    $grid.Columns.Add("disk", "Disk") | Out-Null
    $grid.Columns.Add("agentic", "Agentic") | Out-Null
    $grid.Columns.Add("opencode", "OpenCode") | Out-Null
    $grid.Columns["status"].FillWeight = 110
    $grid.Columns["id"].FillWeight = 220
    $grid.Columns["family"].FillWeight = 95
    $grid.Columns["fit"].FillWeight = 95
    $grid.Columns["size"].FillWeight = 70
    $grid.Columns["speed"].FillWeight = 75
    $grid.Columns["disk"].FillWeight = 85
    $grid.Columns["agentic"].FillWeight = 70
    $grid.Columns["opencode"].FillWeight = 70
    $browserForm.Controls.Add($grid)

    $detailBox = New-Object System.Windows.Forms.TextBox
    $detailBox.Location = New-Object System.Drawing.Point(18, 478)
    $detailBox.Size = New-Object System.Drawing.Size(780, 164)
    $detailBox.Multiline = $true
    $detailBox.ScrollBars = "Vertical"
    $detailBox.ReadOnly = $true
    $detailBox.BackColor = [System.Drawing.Color]::White
    $browserForm.Controls.Add($detailBox)

    $activateButton = New-Object System.Windows.Forms.Button
    $activateButton.Text = "Aktiviraj model"
    $activateButton.Location = New-Object System.Drawing.Point(820, 478)
    $activateButton.Size = New-Object System.Drawing.Size(130, 34)
    $browserForm.Controls.Add($activateButton)

    $downloadButton = New-Object System.Windows.Forms.Button
    $downloadButton.Text = "Preuzmi / osvezi"
    $downloadButton.Location = New-Object System.Drawing.Point(960, 478)
    $downloadButton.Size = New-Object System.Drawing.Size(126, 34)
    $browserForm.Controls.Add($downloadButton)

    $useRecommendedButton = New-Object System.Windows.Forms.Button
    $useRecommendedButton.Text = "Aktiviraj preporuku"
    $useRecommendedButton.Location = New-Object System.Drawing.Point(820, 522)
    $useRecommendedButton.Size = New-Object System.Drawing.Size(266, 34)
    $browserForm.Controls.Add($useRecommendedButton)

    $compareButton = New-Object System.Windows.Forms.Button
    $compareButton.Text = "Uporedi izabrani"
    $compareButton.Location = New-Object System.Drawing.Point(820, 566)
    $compareButton.Size = New-Object System.Drawing.Size(266, 34)
    $browserForm.Controls.Add($compareButton)

    $closeBrowserButton = New-Object System.Windows.Forms.Button
    $closeBrowserButton.Text = "Zatvori"
    $closeBrowserButton.Location = New-Object System.Drawing.Point(976, 608)
    $closeBrowserButton.Size = New-Object System.Drawing.Size(110, 34)
    $closeBrowserButton.Add_Click({ $browserForm.Close() })
    $browserForm.Controls.Add($closeBrowserButton)

    $browserModels = @()

    $updateBrowserDetails = {
        if ($grid.SelectedRows.Count -eq 0) {
            $detailBox.Text = "Izaberi model da vidis detalje."
            return
        }
        $selected = $grid.SelectedRows[0].Tag
        if (-not $selected) {
            $detailBox.Text = "Detalji nisu dostupni."
            return
        }

        $statusText = @()
        if ($selected.active) { $statusText += "AKTIVAN" }
        if ($selected.installed) { $statusText += "INSTALLED" }
        if ($selected.recommended) { $statusText += "PREPORUCEN" }
        if ($selected.fitGroup -eq "recommended") { $statusText += "DOBAR FIT" }
        elseif ($selected.fitGroup -eq "canRun") { $statusText += "MOZE DA RADI" }
        else { $statusText += "NIJE PREPORUCEN" }

        $detailBox.Text = @(
            "Status: $($statusText -join ' | ')",
            "Model: $($selected.id)",
            "Family: $($selected.family) | Use case: $($selected.useCase)",
            "Badge: $($(if ($selected.useCaseBadges -and @($selected.useCaseBadges).Count -gt 0) { @($selected.useCaseBadges) -join ', ' } else { 'nema posebne oznake' }))",
            "Velicina: $($selected.approxSizeGiB) GiB | GPU: $($selected.minimumGpuMiB)/$($selected.recommendedGpuMiB) MiB | RAM: $($selected.minimumRamGiB) GiB",
            "Installed: $($selected.installedSizeGiB) GiB | Need disk: $($selected.diskNeededGiB) GiB | Free disk: $($selected.freeDiskGiB) GiB | Enough disk: $(if ($selected.hasEnoughDisk) { 'da' } else { 'ne' })",
            "Procena brzine: $($selected.speedEstimateLabel) | $($selected.speedEstimateReason)",
            "Agentic: $($selected.agenticScore)/10 | OpenCode: $($selected.opencodeFit)/10 | Curation: $($selected.curationLevel)",
            "Opis: $($selected.description)"
        ) -join [Environment]::NewLine
    }.GetNewClosure()

    $refreshBrowserGrid = {
        try {
            $familyFilter = if ($familyCombo.SelectedIndex -gt 0) { [string]$familyCombo.SelectedItem } else { "" }
            $payload = Get-ModelBrowserPayload `
                -Search $searchBox.Text `
                -Family $familyFilter `
                -InstalledOnly:([bool]$installedOnlyBrowser.Checked) `
                -RecommendedOnly:([bool]$recommendedOnlyBrowser.Checked) `
                -FitOnly:([bool]$fitOnlyBrowser.Checked) `
                -CoderOnly:([bool]$coderOnlyBrowser.Checked) `
                -VerifiedOnly:([bool]$verifiedOnlyBrowser.Checked)

            $browserModels = @($payload.models)
            $grid.Rows.Clear()
            foreach ($item in $browserModels) {
                $status = @()
                if ($item.active) { $status += "AKTIVAN" }
                if ($item.installed) { $status += "INSTALLED" }
                if ($item.recommended) { $status += "PREPORUKA" }
                if ($item.useCaseBadges -and @($item.useCaseBadges).Count -gt 0) { $status += ((@($item.useCaseBadges) | Select-Object -First 1) -join '') }
                $status += switch ($item.fitGroup) {
                    "recommended" { "FIT" }
                    "canRun" { "KOMPROMIS" }
                    default { "SLAB FIT" }
                }
                $rowIndex = $grid.Rows.Add(
                    ($status -join " | "),
                    [string]$item.id,
                    [string]$item.family,
                    [string]$item.fitGroup,
                    ("{0} GiB" -f $item.approxSizeGiB),
                    [string]$item.speedEstimateLabel,
                    ("need {0}G" -f $item.diskNeededGiB),
                    ("{0}/10" -f $item.agenticScore),
                    ("{0}/10" -f $item.opencodeFit)
                )
                $grid.Rows[$rowIndex].Tag = $item
            }

            $summaryLabel.Text = "Prikazano: $($browserModels.Count) | Preporuceni profil: $($payload.recommendedProfile) | Hardverska klasa: $($payload.detectedClass)"
            if ($grid.Rows.Count -gt 0) {
                $grid.ClearSelection()
                $grid.Rows[0].Selected = $true
            }
            & $updateBrowserDetails
        } catch {
            $summaryLabel.Text = "Model browser trenutno nije dostupan."
            $detailBox.Text = $_.Exception.Message
        }
    }.GetNewClosure()

    $refreshBrowserHandler = { & $refreshBrowserGrid }.GetNewClosure()
    $refreshBrowserButton.Add_Click($refreshBrowserHandler)
    $searchBox.Add_TextChanged($refreshBrowserHandler)
    $familyCombo.Add_SelectedIndexChanged($refreshBrowserHandler)
    $installedOnlyBrowser.Add_CheckedChanged($refreshBrowserHandler)
    $recommendedOnlyBrowser.Add_CheckedChanged($refreshBrowserHandler)
    $fitOnlyBrowser.Add_CheckedChanged($refreshBrowserHandler)
    $coderOnlyBrowser.Add_CheckedChanged($refreshBrowserHandler)
    $verifiedOnlyBrowser.Add_CheckedChanged($refreshBrowserHandler)
    $grid.Add_SelectionChanged({ & $updateBrowserDetails }.GetNewClosure())

    $activateButton.Add_Click({
        if ($grid.SelectedRows.Count -eq 0 -or -not $grid.SelectedRows[0].Tag) {
            return
        }
        $selected = $grid.SelectedRows[0].Tag
        try {
            $result = & powershell.exe -ExecutionPolicy Bypass -File $manageModelsScript -ModelId ([string]$selected.id) 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw ($result -join [Environment]::NewLine)
            }
            Write-LaunchMessage @($result)
            Refresh-ModelUiFromInstallState
            Refresh-LaunchStatus
            & $refreshBrowserGrid
        } catch {
            Write-LaunchMessage @($_.Exception.Message)
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Greska", 0, 16) | Out-Null
        }
    }.GetNewClosure())

    $downloadButton.Add_Click({
        if ($grid.SelectedRows.Count -eq 0 -or -not $grid.SelectedRows[0].Tag) {
            return
        }
        $selected = $grid.SelectedRows[0].Tag
        Invoke-BackgroundShellScript -Name "Model browser download" -ScriptPath $manageModelsScript -ArgumentList @("-ModelId", ([string]$selected.id), "-Download") -OnSuccess ({
            Refresh-ModelUiFromInstallState
            Refresh-LaunchStatus
            Refresh-LogsView
            & $refreshBrowserGrid
        }.GetNewClosure())
    }.GetNewClosure())

    $useRecommendedButton.Add_Click({
        try {
            $result = & powershell.exe -ExecutionPolicy Bypass -File $manageModelsScript -UseRecommended 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw ($result -join [Environment]::NewLine)
            }
            Write-LaunchMessage @($result)
            Refresh-ModelUiFromInstallState
            Refresh-LaunchStatus
            & $refreshBrowserGrid
        } catch {
            Write-LaunchMessage @($_.Exception.Message)
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Greska", 0, 16) | Out-Null
        }
    }.GetNewClosure())

    $compareButton.Add_Click({
        if ($grid.SelectedRows.Count -eq 0 -or -not $grid.SelectedRows[0].Tag) {
            return
        }
        try {
            $selected = $grid.SelectedRows[0].Tag
            $recommendedId = if ($recommendationBundle -and $recommendationBundle.recommendedModel) { [string]$recommendationBundle.recommendedModel.id } else { $null }
            $activeId = [string](Get-InstallState).modelId
            $ids = @($selected.id, $activeId, $recommendedId) | Where-Object { $_ } | Select-Object -Unique
            $compare = Get-ModelComparePayload -ModelIds $ids
            $lines = New-Object System.Collections.Generic.List[string]
            $lines.Add("Model compare") | Out-Null
            $lines.Add("Best speed: $($compare.summary.bestForSpeed)") | Out-Null
            $lines.Add("Best coding: $($compare.summary.bestForCoding)") | Out-Null
            $lines.Add("Best quality: $($compare.summary.bestForQuality)") | Out-Null
            $lines.Add("") | Out-Null
            foreach ($item in @($compare.models)) {
                $lines.Add("$($item.id)") | Out-Null
                $lines.Add("  Family: $($item.family) | Speed: $($item.speedEstimateLabel) | Agentic: $($item.agenticScore)/10 | OpenCode: $($item.opencodeFit)/10") | Out-Null
                $lines.Add("  Size: $($item.approxSizeGiB) GiB | Fit: $($item.fitGroup) | Badge: $((@($item.useCaseBadges) -join ', '))") | Out-Null
            }
            $detailBox.Text = $lines -join [Environment]::NewLine
        } catch {
            $detailBox.Text = $_.Exception.Message
        }
    }.GetNewClosure())

    & $refreshBrowserGrid
    [void]$browserForm.ShowDialog($form)
}

function Show-AboutDialog {
    $aboutForm = New-Object System.Windows.Forms.Form
    $aboutForm.Text = "About"
    $aboutForm.StartPosition = "CenterParent"
    $aboutForm.Size = New-Object System.Drawing.Size(640, 540)
    $aboutForm.MinimumSize = New-Object System.Drawing.Size(640, 540)
    $aboutForm.BackColor = [System.Drawing.Color]::WhiteSmoke
    $aboutForm.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    if (Test-Path $iconPath) {
        $aboutForm.Icon = New-Object System.Drawing.Icon($iconPath)
    }

    $versionLabel = New-Object System.Windows.Forms.Label
    $versionLabel.Text = "Verzija: v$(Get-AppVersion)"
    $versionLabel.Location = New-Object System.Drawing.Point(18, 18)
    $versionLabel.Size = New-Object System.Drawing.Size(260, 24)
    $versionLabel.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 11, [System.Drawing.FontStyle]::Bold)
    $aboutForm.Controls.Add($versionLabel)

    $notesLabel = New-Object System.Windows.Forms.Label
    $notesLabel.Text = "Poslednji fix log"
    $notesLabel.Location = New-Object System.Drawing.Point(18, 52)
    $notesLabel.Size = New-Object System.Drawing.Size(220, 22)
    $aboutForm.Controls.Add($notesLabel)

    $notesBox = New-Object System.Windows.Forms.TextBox
    $notesBox.Location = New-Object System.Drawing.Point(18, 78)
    $notesBox.Size = New-Object System.Drawing.Size(588, 380)
    $notesBox.Multiline = $true
    $notesBox.ScrollBars = "Vertical"
    $notesBox.ReadOnly = $true
    $notesBox.BackColor = [System.Drawing.Color]::White
    $notesBox.Text = Get-FormattedReleaseNotesText
    $aboutForm.Controls.Add($notesBox)

    $closeButton = New-Object System.Windows.Forms.Button
    $closeButton.Text = "Zatvori"
    $closeButton.Location = New-Object System.Drawing.Point(496, 468)
    $closeButton.Size = New-Object System.Drawing.Size(110, 32)
    $closeButton.Add_Click({ $aboutForm.Close() })
    $aboutForm.Controls.Add($closeButton)

    [void]$aboutForm.ShowDialog($form)
}

function Start-LlamaBackground {
    param([string]$Profile)

    Write-LaunchMessage @(
        "Pokrecem llama.cpp u pozadini za profil '$Profile'...",
        "Server ce se sam potvrditi cim /health postane dostupan."
    )
    Set-ServiceLifecycleState -State "starting" -Profile $Profile -Reason "Control Center je pokrenuo start u pozadini."

    $escapedConfigure = $configureSettingsScript.Replace("'", "''")
    $escapedStart = $startServerScript.Replace("'", "''")
    $escapedProfile = $Profile.Replace("'", "''")
    $backgroundCommand = "& '$escapedConfigure' -Profile '$escapedProfile' | Out-Null; & '$escapedStart' -Profile '$escapedProfile' -WaitSeconds 90"
    Start-Process -FilePath "powershell.exe" -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-WindowStyle", "Hidden",
        "-Command", $backgroundCommand
    ) -WindowStyle Hidden

    Write-LaunchMessage @("Profil '$Profile' je predat pozadinskom launcheru.")
    Refresh-LaunchStatus
    Refresh-DiagnosticsView
    Refresh-ThroughputView
}

$startBalanced = New-Object System.Windows.Forms.Button
$startBalanced.Text = "Start balanced"
$startBalanced.Location = New-Object System.Drawing.Point(18, 82)
$startBalanced.Size = New-Object System.Drawing.Size(120, 36)
$launchTab.Controls.Add($startBalanced)

$startVideo = New-Object System.Windows.Forms.Button
$startVideo.Text = "Start video"
$startVideo.Location = New-Object System.Drawing.Point(148, 82)
$startVideo.Size = New-Object System.Drawing.Size(120, 36)
$launchTab.Controls.Add($startVideo)

$startSpeed = New-Object System.Windows.Forms.Button
$startSpeed.Text = "Start speed"
$startSpeed.Location = New-Object System.Drawing.Point(278, 82)
$startSpeed.Size = New-Object System.Drawing.Size(120, 36)
$launchTab.Controls.Add($startSpeed)

$startLlama = New-Object System.Windows.Forms.Button
$startLlama.Text = "Start llama.cpp"
$startLlama.Location = New-Object System.Drawing.Point(408, 82)
$startLlama.Size = New-Object System.Drawing.Size(130, 36)
$launchTab.Controls.Add($startLlama)

$stopServer = New-Object System.Windows.Forms.Button
$stopServer.Text = "Stop server"
$stopServer.Location = New-Object System.Drawing.Point(548, 82)
$stopServer.Size = New-Object System.Drawing.Size(118, 36)
$launchTab.Controls.Add($stopServer)

$openOpenCode = New-Object System.Windows.Forms.Button
$openOpenCode.Text = "Otvori OpenCode"
$openOpenCode.Location = New-Object System.Drawing.Point(18, 132)
$openOpenCode.Size = New-Object System.Drawing.Size(180, 36)
$launchTab.Controls.Add($openOpenCode)

$openWebUi = New-Object System.Windows.Forms.Button
$openWebUi.Text = "Otvori llama.cpp web"
$openWebUi.Location = New-Object System.Drawing.Point(208, 132)
$openWebUi.Size = New-Object System.Drawing.Size(180, 36)
$launchTab.Controls.Add($openWebUi)

$refreshStatus = New-Object System.Windows.Forms.Button
$refreshStatus.Text = "Osvezi status"
$refreshStatus.Location = New-Object System.Drawing.Point(398, 132)
$refreshStatus.Size = New-Object System.Drawing.Size(130, 36)
$launchTab.Controls.Add($refreshStatus)

$openFolderButton = New-Object System.Windows.Forms.Button
$openFolderButton.Text = "Otvori folder"
$openFolderButton.Location = New-Object System.Drawing.Point(538, 132)
$openFolderButton.Size = New-Object System.Drawing.Size(128, 36)
$launchTab.Controls.Add($openFolderButton)

$quickStartButton.Add_Click({ $startLlama.PerformClick() })
$quickStopButton.Add_Click({ $stopServer.PerformClick() })
$quickOpenCodeButton.Add_Click({ $openOpenCode.PerformClick() })
$quickRefreshButton.Add_Click({
    Refresh-LaunchStatus
    Refresh-ThroughputView
    Write-LaunchMessage @("Quick status je osvezen.")
})

$repairInstallButton = New-Object System.Windows.Forms.Button
$repairInstallButton.Text = "Repair install"
$repairInstallButton.Location = New-Object System.Drawing.Point(18, 594)
$repairInstallButton.Size = New-Object System.Drawing.Size(124, 32)
$launchTab.Controls.Add($repairInstallButton)

$testPromptButton = New-Object System.Windows.Forms.Button
$testPromptButton.Text = "Test prompt"
$testPromptButton.Location = New-Object System.Drawing.Point(152, 594)
$testPromptButton.Size = New-Object System.Drawing.Size(110, 32)
$launchTab.Controls.Add($testPromptButton)

$modelManagerButton = New-Object System.Windows.Forms.Button
$modelManagerButton.Text = "Model manager"
$modelManagerButton.Location = New-Object System.Drawing.Point(272, 594)
$modelManagerButton.Size = New-Object System.Drawing.Size(124, 32)
$launchTab.Controls.Add($modelManagerButton)

$diagnosticsButton = New-Object System.Windows.Forms.Button
$diagnosticsButton.Text = "Diagnostics"
$diagnosticsButton.Location = New-Object System.Drawing.Point(406, 594)
$diagnosticsButton.Size = New-Object System.Drawing.Size(120, 32)
$launchTab.Controls.Add($diagnosticsButton)

$updatesButton = New-Object System.Windows.Forms.Button
$updatesButton.Text = "Check updates"
$updatesButton.Location = New-Object System.Drawing.Point(536, 594)
$updatesButton.Size = New-Object System.Drawing.Size(130, 32)
$launchTab.Controls.Add($updatesButton)

$modelLabel = New-Object System.Windows.Forms.Label
$modelLabel.Text = "Model varijanta"
$modelLabel.Location = New-Object System.Drawing.Point(18, 18)
$modelLabel.Size = New-Object System.Drawing.Size(220, 22)
$settingsPanel.Controls.Add($modelLabel)

$modelCombo = New-Object System.Windows.Forms.ComboBox
$modelCombo.Location = New-Object System.Drawing.Point(18, 44)
$modelCombo.Size = New-Object System.Drawing.Size(567, 30)
$modelCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$modelCombo.Font = New-Object System.Drawing.Font("Segoe UI", 10)
foreach ($item in $modelCatalog) {
    [void]$modelCombo.Items.Add("$($item.label) | $($item.family) | $($item.approxSizeGiB) GiB")
}
$settingsPanel.Controls.Add($modelCombo)

$verifiedOnlyCheck = New-Object System.Windows.Forms.CheckBox
$verifiedOnlyCheck.Text = "Samo verified"
$verifiedOnlyCheck.Location = New-Object System.Drawing.Point(18, 82)
$verifiedOnlyCheck.Size = New-Object System.Drawing.Size(120, 24)
$settingsPanel.Controls.Add($verifiedOnlyCheck)

$coderOnlyCheck = New-Object System.Windows.Forms.CheckBox
$coderOnlyCheck.Text = "Samo coder modeli"
$coderOnlyCheck.Location = New-Object System.Drawing.Point(150, 82)
$coderOnlyCheck.Size = New-Object System.Drawing.Size(150, 24)
$settingsPanel.Controls.Add($coderOnlyCheck)

$fitOnlyCheck = New-Object System.Windows.Forms.CheckBox
$fitOnlyCheck.Text = "Samo za ovu masinu"
$fitOnlyCheck.Location = New-Object System.Drawing.Point(312, 82)
$fitOnlyCheck.Size = New-Object System.Drawing.Size(155, 24)
$settingsPanel.Controls.Add($fitOnlyCheck)

$downloadModelButton = New-Object System.Windows.Forms.Button
$downloadModelButton.Text = "Preuzmi izabrani model"
$downloadModelButton.Location = New-Object System.Drawing.Point(400, 106)
$downloadModelButton.Size = New-Object System.Drawing.Size(185, 32)
$settingsPanel.Controls.Add($downloadModelButton)

$modelCombo.Add_SelectedIndexChanged({
    Refresh-ModelSelectionInfo
})

$filterHandler = {
    Apply-ModelFilters
    Refresh-ModelSelectionInfo
}.GetNewClosure()

$verifiedOnlyCheck.Add_CheckedChanged($filterHandler)
$coderOnlyCheck.Add_CheckedChanged($filterHandler)
$fitOnlyCheck.Add_CheckedChanged($filterHandler)

$modelInfoBox = New-Object System.Windows.Forms.TextBox
$modelInfoBox.Location = New-Object System.Drawing.Point(18, 146)
$modelInfoBox.Size = New-Object System.Drawing.Size(567, 108)
$modelInfoBox.Multiline = $true
$modelInfoBox.ScrollBars = "Vertical"
$modelInfoBox.ReadOnly = $true
$modelInfoBox.BackColor = [System.Drawing.Color]::White
$settingsPanel.Controls.Add($modelInfoBox)

$presetGroup = New-Object System.Windows.Forms.GroupBox
$presetGroup.Text = "Quick presets"
$presetGroup.Location = New-Object System.Drawing.Point(18, 262)
$presetGroup.Size = New-Object System.Drawing.Size(567, 248)
$settingsPanel.Controls.Add($presetGroup)

$settingsProfileLabel = New-Object System.Windows.Forms.Label
$settingsProfileLabel.Location = New-Object System.Drawing.Point(16, 26)
$settingsProfileLabel.Size = New-Object System.Drawing.Size(340, 22)
$presetGroup.Controls.Add($settingsProfileLabel)

$laptopSafeButton = New-Object System.Windows.Forms.Button
$laptopSafeButton.Text = "Laptop safe"
$laptopSafeButton.Location = New-Object System.Drawing.Point(16, 54)
$laptopSafeButton.Size = New-Object System.Drawing.Size(126, 30)
$presetGroup.Controls.Add($laptopSafeButton)

$codingFastButton = New-Object System.Windows.Forms.Button
$codingFastButton.Text = "Coding fast"
$codingFastButton.Location = New-Object System.Drawing.Point(152, 54)
$codingFastButton.Size = New-Object System.Drawing.Size(126, 30)
$presetGroup.Controls.Add($codingFastButton)

$longContextButton = New-Object System.Windows.Forms.Button
$longContextButton.Text = "Long context"
$longContextButton.Location = New-Object System.Drawing.Point(288, 54)
$longContextButton.Size = New-Object System.Drawing.Size(126, 30)
$presetGroup.Controls.Add($longContextButton)

$bestCurrentButton = New-Object System.Windows.Forms.Button
$bestCurrentButton.Text = "Best current setup"
$bestCurrentButton.Location = New-Object System.Drawing.Point(424, 54)
$bestCurrentButton.Size = New-Object System.Drawing.Size(126, 30)
$presetGroup.Controls.Add($bestCurrentButton)

$applyAndStartPresetButton = New-Object System.Windows.Forms.Button
$applyAndStartPresetButton.Text = "Primeni + start"
$applyAndStartPresetButton.Location = New-Object System.Drawing.Point(394, 18)
$applyAndStartPresetButton.Size = New-Object System.Drawing.Size(156, 28)
$presetGroup.Controls.Add($applyAndStartPresetButton)

$presetInfoBox = New-Object System.Windows.Forms.TextBox
$presetInfoBox.Location = New-Object System.Drawing.Point(16, 92)
$presetInfoBox.Size = New-Object System.Drawing.Size(534, 66)
$presetInfoBox.Multiline = $true
$presetInfoBox.ScrollBars = "Vertical"
$presetInfoBox.ReadOnly = $true
$presetInfoBox.BackColor = [System.Drawing.Color]::White
$presetGroup.Controls.Add($presetInfoBox)

$presetCompareBox = New-Object System.Windows.Forms.TextBox
$presetCompareBox.Location = New-Object System.Drawing.Point(16, 164)
$presetCompareBox.Size = New-Object System.Drawing.Size(534, 72)
$presetCompareBox.Multiline = $true
$presetCompareBox.ScrollBars = "Vertical"
$presetCompareBox.ReadOnly = $true
$presetCompareBox.BackColor = [System.Drawing.Color]::White
$presetGroup.Controls.Add($presetCompareBox)

$contextRow = Add-ContextRow -Parent $settingsPanel -Y 522 -SelectedValue ([int]$settings.llama.contextSize)
$outputRow = Add-TrackFieldRow -Parent $settingsPanel -LabelText "Max output tokens" -Y 610 -Minimum 1024 -Maximum 16384 -TickFrequency 1024 -Value ([int]$settings.llama.maxOutputTokens) -Increment 256
$buildRow = Add-TrackFieldRow -Parent $settingsPanel -LabelText "Build steps" -Y 698 -Minimum 20 -Maximum 200 -TickFrequency 10 -Value ([int]$settings.opencode.buildSteps)
$planRow = Add-TrackFieldRow -Parent $settingsPanel -LabelText "Plan steps" -Y 786 -Minimum 20 -Maximum 200 -TickFrequency 10 -Value ([int]$settings.opencode.planSteps)
$generalRow = Add-TrackFieldRow -Parent $settingsPanel -LabelText "General steps" -Y 874 -Minimum 20 -Maximum 200 -TickFrequency 10 -Value ([int]$settings.opencode.generalSteps)
$exploreRow = Add-TrackFieldRow -Parent $settingsPanel -LabelText "Explore steps" -Y 962 -Minimum 10 -Maximum 150 -TickFrequency 10 -Value ([int]$settings.opencode.exploreSteps)

$settingsStatus = New-Object System.Windows.Forms.Label
$settingsStatus.Text = "Promene vaze za buduca pokretanja."
$settingsStatus.Location = New-Object System.Drawing.Point(18, 1052)
$settingsStatus.Size = New-Object System.Drawing.Size(300, 24)
$settingsStatus.ForeColor = [System.Drawing.Color]::FromArgb(70, 70, 70)
$settingsPanel.Controls.Add($settingsStatus)

$saveSettingsButton = New-Object System.Windows.Forms.Button
$saveSettingsButton.Text = "Sacuvaj podesavanja"
$saveSettingsButton.Location = New-Object System.Drawing.Point(430, 1046)
$saveSettingsButton.Size = New-Object System.Drawing.Size(155, 34)
$saveSettingsButton.BackColor = [System.Drawing.Color]::FromArgb(23, 111, 235)
$saveSettingsButton.ForeColor = [System.Drawing.Color]::White
$saveSettingsButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$settingsPanel.Controls.Add($saveSettingsButton)

$resetSettingsButton = New-Object System.Windows.Forms.Button
$resetSettingsButton.Text = "Vrati preporuku"
$resetSettingsButton.Location = New-Object System.Drawing.Point(285, 1046)
$resetSettingsButton.Size = New-Object System.Drawing.Size(132, 34)
$settingsPanel.Controls.Add($resetSettingsButton)

Set-SettingsProfileVisuals
$presetInfoBox.Text = "Izaberi quick preset da odmah dobijes i objasnjenje i spremne vrednosti za cuvanje."
$presetCompareBox.Text = "Compare pregled ce ovde pokazati sta bi se promenilo u odnosu na trenutno sacuvane vrednosti."

$securityGroup = New-Object System.Windows.Forms.GroupBox
$securityGroup.Text = "Zastita"
$securityGroup.Location = New-Object System.Drawing.Point(18, 16)
$securityGroup.Size = New-Object System.Drawing.Size(630, 150)
$agentPanel.Controls.Add($securityGroup)

$strictRadio = New-Object System.Windows.Forms.RadioButton
$strictRadio.Text = "Strogo ogranicen agent"
$strictRadio.Location = New-Object System.Drawing.Point(18, 28)
$strictRadio.Size = New-Object System.Drawing.Size(250, 22)
$securityGroup.Controls.Add($strictRadio)

$strictInfo = New-Object System.Windows.Forms.Label
$strictInfo.Text = "Radi samo unutar izabranog foldera."
$strictInfo.Location = New-Object System.Drawing.Point(38, 50)
$strictInfo.Size = New-Object System.Drawing.Size(260, 20)
$securityGroup.Controls.Add($strictInfo)

$blacklistRadio = New-Object System.Windows.Forms.RadioButton
$blacklistRadio.Text = "Ogranicen agent sa blacklist pravilima"
$blacklistRadio.Location = New-Object System.Drawing.Point(18, 82)
$blacklistRadio.Size = New-Object System.Drawing.Size(300, 22)
$securityGroup.Controls.Add($blacklistRadio)

$blacklistInfo = New-Object System.Windows.Forms.Label
$blacklistInfo.Text = "Blokira Windows, Program Files, AppData i slicne putanje."
$blacklistInfo.Location = New-Object System.Drawing.Point(38, 104)
$blacklistInfo.Size = New-Object System.Drawing.Size(360, 20)
$securityGroup.Controls.Add($blacklistInfo)

$openRadio = New-Object System.Windows.Forms.RadioButton
$openRadio.Text = "Potpuno otvoren agent"
$openRadio.Location = New-Object System.Drawing.Point(360, 28)
$openRadio.Size = New-Object System.Drawing.Size(200, 22)
$securityGroup.Controls.Add($openRadio)

$openInfo = New-Object System.Windows.Forms.Label
$openInfo.Text = "Bez realne zastite van foldera. Najrizicnije."
$openInfo.Location = New-Object System.Drawing.Point(380, 50)
$openInfo.Size = New-Object System.Drawing.Size(220, 36)
$securityGroup.Controls.Add($openInfo)

$capabilityGroup = New-Object System.Windows.Forms.GroupBox
$capabilityGroup.Text = "Autonomija"
$capabilityGroup.Location = New-Object System.Drawing.Point(18, 180)
$capabilityGroup.Size = New-Object System.Drawing.Size(630, 132)
$agentPanel.Controls.Add($capabilityGroup)

$readOnlyRadio = New-Object System.Windows.Forms.RadioButton
$readOnlyRadio.Text = "1. Samo citanje fajlova"
$readOnlyRadio.Location = New-Object System.Drawing.Point(18, 26)
$readOnlyRadio.Size = New-Object System.Drawing.Size(220, 22)
$capabilityGroup.Controls.Add($readOnlyRadio)

$readWriteRadio = New-Object System.Windows.Forms.RadioButton
$readWriteRadio.Text = "2. Citanje + izmena fajlova"
$readWriteRadio.Location = New-Object System.Drawing.Point(18, 52)
$readWriteRadio.Size = New-Object System.Drawing.Size(240, 22)
$capabilityGroup.Controls.Add($readWriteRadio)

$confirmRadio = New-Object System.Windows.Forms.RadioButton
$confirmRadio.Text = "3. Citanje + izmena + komande uz potvrdu"
$confirmRadio.Location = New-Object System.Drawing.Point(18, 78)
$confirmRadio.Size = New-Object System.Drawing.Size(330, 22)
$capabilityGroup.Controls.Add($confirmRadio)

$autoRadio = New-Object System.Windows.Forms.RadioButton
$autoRadio.Text = "4. Citanje + izmena + komande bez potvrde"
$autoRadio.Location = New-Object System.Drawing.Point(18, 104)
$autoRadio.Size = New-Object System.Drawing.Size(340, 22)
$capabilityGroup.Controls.Add($autoRadio)

$folderLabel = New-Object System.Windows.Forms.Label
$folderLabel.Text = "Radni folder"
$folderLabel.Location = New-Object System.Drawing.Point(18, 330)
$folderLabel.Size = New-Object System.Drawing.Size(140, 22)
$agentPanel.Controls.Add($folderLabel)

$folderBox = New-Object System.Windows.Forms.TextBox
$folderBox.Location = New-Object System.Drawing.Point(18, 354)
$folderBox.Size = New-Object System.Drawing.Size(500, 28)
$folderBox.Text = if ($agentMeta -and $agentMeta.workingFolder) { [string]$agentMeta.workingFolder } elseif ($settings.opencode.PSObject.Properties["workingDirectory"] -and $settings.opencode.workingDirectory) { [string]$settings.opencode.workingDirectory } else { $env:USERPROFILE }
$agentPanel.Controls.Add($folderBox)

$browseFolderButton = New-Object System.Windows.Forms.Button
$browseFolderButton.Text = "Izaberi..."
$browseFolderButton.Location = New-Object System.Drawing.Point(530, 352)
$browseFolderButton.Size = New-Object System.Drawing.Size(118, 30)
$agentPanel.Controls.Add($browseFolderButton)

$agentWarning = New-Object System.Windows.Forms.Label
$agentWarning.Text = "AUTO + C:\ je skoro puna sloboda nad sistemom."
$agentWarning.Location = New-Object System.Drawing.Point(18, 392)
$agentWarning.Size = New-Object System.Drawing.Size(620, 54)
$agentWarning.ForeColor = [System.Drawing.Color]::FromArgb(176, 72, 18)
$agentPanel.Controls.Add($agentWarning)

$agentStatus = New-Object System.Windows.Forms.Label
$agentStatus.Text = "Konfiguracija se cuva pre starta."
$agentStatus.Location = New-Object System.Drawing.Point(18, 470)
$agentStatus.Size = New-Object System.Drawing.Size(360, 24)
$agentStatus.ForeColor = [System.Drawing.Color]::FromArgb(70, 70, 70)
$agentPanel.Controls.Add($agentStatus)

$saveAgentButton = New-Object System.Windows.Forms.Button
$saveAgentButton.Text = "Sacuvaj agent rezim"
$saveAgentButton.Location = New-Object System.Drawing.Point(365, 466)
$saveAgentButton.Size = New-Object System.Drawing.Size(140, 34)
$agentPanel.Controls.Add($saveAgentButton)

$launchAgentButton = New-Object System.Windows.Forms.Button
$launchAgentButton.Text = "Pokreni agent"
$launchAgentButton.Location = New-Object System.Drawing.Point(520, 466)
$launchAgentButton.Size = New-Object System.Drawing.Size(128, 34)
$launchAgentButton.BackColor = [System.Drawing.Color]::FromArgb(23, 111, 235)
$launchAgentButton.ForeColor = [System.Drawing.Color]::White
$launchAgentButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$agentPanel.Controls.Add($launchAgentButton)

$refreshAuditButton = New-Object System.Windows.Forms.Button
$refreshAuditButton.Text = "Osvezi audit"
$refreshAuditButton.Location = New-Object System.Drawing.Point(18, 506)
$refreshAuditButton.Size = New-Object System.Drawing.Size(120, 30)
$agentPanel.Controls.Add($refreshAuditButton)

if ($agentMeta -and $agentMeta.securityMode) {
    switch ([string]$agentMeta.securityMode) {
        "strict" { $strictRadio.Checked = $true }
        "blacklist" { $blacklistRadio.Checked = $true }
        "open" { $openRadio.Checked = $true }
        default { $strictRadio.Checked = $true }
    }
} else {
    $strictRadio.Checked = $true
}

if ($agentMeta -and $agentMeta.capabilityMode) {
    switch ([string]$agentMeta.capabilityMode) {
        "read-only" { $readOnlyRadio.Checked = $true }
        "read-write" { $readWriteRadio.Checked = $true }
        "confirm-commands" { $confirmRadio.Checked = $true }
        "auto-commands" { $autoRadio.Checked = $true }
        default { $confirmRadio.Checked = $true }
    }
} else {
    $confirmRadio.Checked = $true
}

$folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
$browseFolderButton.Add_Click({
    if (Test-Path $folderBox.Text) {
        $folderDialog.SelectedPath = $folderBox.Text
    }
    if ($folderDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $folderBox.Text = $folderDialog.SelectedPath
        Refresh-AgentAudit
    }
})

$refreshAuditButton.Add_Click({
    Refresh-AgentAudit
    Write-LaunchMessage @("Agent risk audit je osvezen.")
})
$strictRadio.Add_CheckedChanged({ if ($strictRadio.Checked) { Refresh-AgentAudit } })
$blacklistRadio.Add_CheckedChanged({ if ($blacklistRadio.Checked) { Refresh-AgentAudit } })
$openRadio.Add_CheckedChanged({ if ($openRadio.Checked) { Refresh-AgentAudit } })
$readOnlyRadio.Add_CheckedChanged({ if ($readOnlyRadio.Checked) { Refresh-AgentAudit } })
$readWriteRadio.Add_CheckedChanged({ if ($readWriteRadio.Checked) { Refresh-AgentAudit } })
$confirmRadio.Add_CheckedChanged({ if ($confirmRadio.Checked) { Refresh-AgentAudit } })
$autoRadio.Add_CheckedChanged({ if ($autoRadio.Checked) { Refresh-AgentAudit } })
$folderBox.Add_TextChanged({ Refresh-AgentAudit })

$laptopSafeButton.Add_Click({
    Apply-SettingsPresetToForm -PresetId "laptop-safe"
})

$codingFastButton.Add_Click({
    Apply-SettingsPresetToForm -PresetId "coding-fast"
})

$longContextButton.Add_Click({
    Apply-SettingsPresetToForm -PresetId "long-context"
})

$bestCurrentButton.Add_Click({
    Apply-SettingsPresetToForm -PresetId "best-current-setup"
})

$resetSettingsButton.Add_Click({
    Ensure-ModelUiState
    $script:PendingSettingsProfile = [string]$recommendationBundle.recommendedProfile
    Set-SettingsProfileVisuals
    $script:SelectedSettingsPreset = $null
    $presetInfoBox.Text = "Vrati preporuku postavlja neutralne preporucene vrednosti u formu. Ako zelis objasnjen preset, izaberi jedan od quick preset dugmica iznad."
    Update-SettingsPresetCompareText -PresetId $null
    $contextRow.Track.Value = 3
    $outputRow.Numeric.Value = 8192
    $buildRow.Numeric.Value = 120
    $planRow.Numeric.Value = 80
    $generalRow.Numeric.Value = 100
    $exploreRow.Numeric.Value = 60
    if ($recommendationBundle) {
        for ($i = 0; $i -lt $script:VisibleModelList.Count; $i++) {
            if ($script:VisibleModelList[$i].id -eq $recommendationBundle.recommendedModel.id) {
                $modelCombo.SelectedIndex = $i
                break
            }
        }
    }
    Refresh-ModelSelectionInfo
    Write-LaunchMessage @("Vracene preporucene vrednosti u formi. Klikni 'Sacuvaj podesavanja' da postanu aktivne.")
})

$saveSettingsButton.Add_Click({
    try {
        [void](Save-SettingsFromForm)
    } catch {
        $settingsStatus.Text = "Greska pri cuvanju."
        $settingsStatus.ForeColor = [System.Drawing.Color]::FromArgb(180, 45, 45)
        Write-LaunchMessage @($_.Exception.Message)
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Greska", 0, 16) | Out-Null
    }
})

$applyAndStartPresetButton.Add_Click({
    try {
        if (-not $script:SelectedSettingsPreset) {
            Apply-SettingsPresetToForm -PresetId "best-current-setup"
        }
        [void](Save-SettingsFromForm)
        Start-LlamaBackground -Profile $script:PendingSettingsProfile
        Write-LaunchMessage @("Preset je primenjen i server se podize u pozadini.")
    } catch {
        $settingsStatus.Text = "Greska pri primeni preset-a."
        $settingsStatus.ForeColor = [System.Drawing.Color]::FromArgb(180, 45, 45)
        Write-LaunchMessage @($_.Exception.Message)
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Greska", 0, 16) | Out-Null
    }
})

$downloadModelButton.Add_Click({
    try {
        Ensure-ModelUiState
        if ($modelCombo.SelectedIndex -lt 0 -or $modelCombo.SelectedIndex -ge $script:VisibleModelList.Count) {
            throw "Nijedan model nije dostupan za aktivne filtere."
        }
        $selectedModel = $script:VisibleModelList[$modelCombo.SelectedIndex]
        Invoke-BackgroundShellScript -Name "Model download" -ScriptPath $manageModelsScript -ArgumentList @("-ModelId", ([string]$selectedModel.id), "-Download") -OnSuccess {
            $settingsStatus.Text = "Model je osvezen: $($selectedModel.id)"
            $settingsStatus.ForeColor = [System.Drawing.Color]::FromArgb(20, 120, 50)
            Refresh-LaunchStatus
            Refresh-LogsView
        }
    } catch {
        $settingsStatus.Text = "Model download nije uspeo."
        $settingsStatus.ForeColor = [System.Drawing.Color]::FromArgb(180, 45, 45)
        Write-LaunchMessage @($_.Exception.Message)
    }
})

function Get-AgentValues {
    if (-not (Test-Path $folderBox.Text)) {
        throw "Izabrani folder ne postoji."
    }

    $security = if ($strictRadio.Checked) { "strict" } elseif ($blacklistRadio.Checked) { "blacklist" } else { "open" }
    $capability = if ($readOnlyRadio.Checked) { "read-only" } elseif ($readWriteRadio.Checked) { "read-write" } elseif ($confirmRadio.Checked) { "confirm-commands" } else { "auto-commands" }

    return [pscustomobject]@{
        SecurityMode = $security
        CapabilityMode = $capability
        WorkingFolder = $folderBox.Text
        Profile = [string](Get-Settings).profile
    }
}

function Refresh-AgentAudit {
    try {
        $values = Get-AgentValues
        $audit = Get-AgentAuditSummary -SecurityMode $values.SecurityMode -CapabilityMode $values.CapabilityMode -WorkingFolder $values.WorkingFolder
        $agentWarning.Text = $audit.Text
        $agentWarning.ForeColor = $audit.Color
    } catch {
        $agentWarning.Text = "Risk audit nije dostupan."
        $agentWarning.ForeColor = [System.Drawing.Color]::FromArgb(176, 72, 18)
    }
}

$saveAgentButton.Add_Click({
    try {
        $values = Get-AgentValues
        $result = & powershell.exe -ExecutionPolicy Bypass -File $launchAgentScript `
            -SecurityMode $values.SecurityMode `
            -CapabilityMode $values.CapabilityMode `
            -WorkingFolder $values.WorkingFolder `
            -Profile $values.Profile `
            -NoLaunch 2>&1

        if ($LASTEXITCODE -ne 0) {
            throw ($result -join [Environment]::NewLine)
        }

        $agentStatus.Text = "Agent konfiguracija sacuvana."
        $agentStatus.ForeColor = [System.Drawing.Color]::FromArgb(20, 120, 50)
        Write-LaunchMessage @($result)
    } catch {
        $agentStatus.Text = "Greska pri cuvanju."
        $agentStatus.ForeColor = [System.Drawing.Color]::FromArgb(180, 45, 45)
        Write-LaunchMessage @($_.Exception.Message)
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Greska", 0, 16) | Out-Null
    }
})

$launchAgentButton.Add_Click({
    try {
        $values = Get-AgentValues
        Start-Process -FilePath "powershell.exe" -ArgumentList @(
            "-ExecutionPolicy", "Bypass",
            "-File", $launchAgentScript,
            "-SecurityMode", $values.SecurityMode,
            "-CapabilityMode", $values.CapabilityMode,
            "-WorkingFolder", $values.WorkingFolder,
            "-Profile", $values.Profile
        )

        $agentStatus.Text = "Agent launcher pokrenut."
        $agentStatus.ForeColor = [System.Drawing.Color]::FromArgb(20, 120, 50)
        Write-LaunchMessage @("Pokrenut agent launcher za folder: $($values.WorkingFolder)")
    } catch {
        $agentStatus.Text = "Greska pri pokretanju."
        $agentStatus.ForeColor = [System.Drawing.Color]::FromArgb(180, 45, 45)
        Write-LaunchMessage @($_.Exception.Message)
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Greska", 0, 16) | Out-Null
    }
})

$startBalanced.Add_Click({
    try {
        Start-LlamaBackground -Profile "balanced"
    } catch {
        Write-LaunchMessage @($_.Exception.Message)
    }
})
$startVideo.Add_Click({
    try {
        Start-LlamaBackground -Profile "video"
    } catch {
        Write-LaunchMessage @($_.Exception.Message)
    }
})
$startSpeed.Add_Click({
    try {
        Start-LlamaBackground -Profile "speed"
    } catch {
        Write-LaunchMessage @($_.Exception.Message)
    }
})
$startLlama.Add_Click({
    try {
        $profile = [string](Get-Settings).profile
        Start-LlamaBackground -Profile $profile
    } catch {
        Write-LaunchMessage @($_.Exception.Message)
    }
})

$stopServer.Add_Click({
    $result = & powershell.exe -ExecutionPolicy Bypass -File $stopServerScript 2>&1
    Write-LaunchMessage @($result)
    Refresh-LaunchStatus
})

$openOpenCode.Add_Click({
    Start-Process -FilePath "powershell.exe" -ArgumentList @(
        "-ExecutionPolicy", "Bypass",
        "-File", $startOpenCodeScript,
        "-Profile", ([string](Get-Settings).profile)
    )
    Write-LaunchMessage @("OpenCode launcher je pokrenut.")
})

$openWebUi.Add_Click({
    Start-Process (Get-LlamaHealthUrl).Replace("/health", "/")
    Write-LaunchMessage @("Otvoren llama.cpp web UI.")
})

$refreshStatus.Add_Click({
    Refresh-LaunchStatus
    Write-LaunchMessage @("Status i hardverski plan su osvezeni.")
})
$refreshLogsButton.Add_Click({
    Refresh-LogsView
    Write-LaunchMessage @("Logovi su osvezeni.")
})
$refreshOnboardingButton.Add_Click({
    Refresh-OnboardingView
    Write-LaunchMessage @("Onboarding pregled je osvezen.")
})
$refreshHealthButton.Add_Click({
    Refresh-HealthCenterView
    Write-LaunchMessage @("Health pregled je osvezen.")
})
$runNextActionButton.Add_Click({
    try {
        $nextAction = Get-NextActionRecommendation
        switch ($nextAction.actionId) {
            "repair-install" {
                $result = & powershell.exe -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "repair-install.ps1") 2>&1
                Write-LaunchMessage @($result)
            }
            "start-server" {
                $profile = [string](Get-Settings).profile
                Start-LlamaBackground -Profile $profile
            }
            "write-opencode-config" {
                $result = & powershell.exe -ExecutionPolicy Bypass -File $configureSettingsScript -Profile ([string](Get-Settings).profile) 2>&1
                Write-LaunchMessage @($result)
            }
            "open-opencode" {
                Start-Process -FilePath "powershell.exe" -ArgumentList @(
                    "-ExecutionPolicy", "Bypass",
                    "-File", $startOpenCodeScript,
                    "-Profile", ([string](Get-Settings).profile)
                )
                Write-LaunchMessage @("Otvaram OpenCode kao sledeci korak.")
            }
        }
        Refresh-LaunchStatus
        Refresh-LogsView
        Refresh-OnboardingView
        Refresh-DiagnosticsView
        Refresh-ThroughputView
    } catch {
        Write-LaunchMessage @($_.Exception.Message)
    }
})
$openFolderButton.Add_Click({
    Start-Process explorer.exe $root
    Write-LaunchMessage @("Otvoren install folder: $root")
})
$repairInstallButton.Add_Click({
    try {
        Invoke-BackgroundShellScript -Name "Repair install" -ScriptPath $repairInstallScript -OnSuccess {
            Refresh-LaunchStatus
            Refresh-LogsView
            Refresh-HealthCenterView
            Refresh-DiagnosticsView
        }
    } catch {
        Write-LaunchMessage @($_.Exception.Message)
    }
})
$repairRuntimeHealthButton.Add_Click({
    try {
        Invoke-HealthRepairAction -Name "Repair runtime" -ScriptPath $repairRuntimeScript
    } catch {
        Write-LaunchMessage @($_.Exception.Message)
    }
})
$repairModelHealthButton.Add_Click({
    try {
        Invoke-HealthRepairAction -Name "Repair model" -ScriptPath $repairModelScript
    } catch {
        Write-LaunchMessage @($_.Exception.Message)
    }
})
$repairConfigHealthButton.Add_Click({
    try {
        Invoke-HealthRepairAction -Name "Repair config" -ScriptPath $repairConfigScript
    } catch {
        Write-LaunchMessage @($_.Exception.Message)
    }
})
$repairAllHealthButton.Add_Click({
    try {
        Invoke-HealthRepairAction -Name "Repair all" -ScriptPath $repairInstallScript
    } catch {
        Write-LaunchMessage @($_.Exception.Message)
    }
})
$guidedRepairButton.Add_Click({
    try {
        $payload = Get-HealthCenterData
        Invoke-HealthActionById -ActionId ([string]$payload.primaryAction.id)
    } catch {
        Write-LaunchMessage @($_.Exception.Message)
    }
})
$testPromptButton.Add_Click({
    try {
        $profile = [string](Get-Settings).profile
        Invoke-BackgroundShellScript -Name "Test prompt" -ScriptPath (Join-Path $PSScriptRoot "test-prompt.ps1") -ArgumentList @("-Profile", $profile) -OnSuccess {
            Refresh-LogsView
            Refresh-DiagnosticsView
            Refresh-ThroughputView
        }
    } catch {
        Write-LaunchMessage @($_.Exception.Message)
    }
})
$modelManagerButton.Add_Click({
    try {
        Show-ModelBrowserDialog
        Write-LaunchMessage @("Otvoren model browser.")
    } catch {
        Write-LaunchMessage @($_.Exception.Message)
    }
})
$diagnosticsButton.Add_Click({
    try {
        Invoke-BackgroundShellScript -Name "Diagnostics export" -ScriptPath $exportDiagnosticsScript -OnSuccess {
            Refresh-DiagnosticsView
        }
    } catch {
        Write-LaunchMessage @($_.Exception.Message)
    }
})
$refreshDiagnosticsButton.Add_Click({
    Refresh-DiagnosticsView
    Refresh-ThroughputView
    Write-LaunchMessage @("Diagnostics pregled je osvezen.")
})
$exportDiagnosticsButton.Add_Click({
    try {
        Invoke-BackgroundShellScript -Name "Diagnostics export" -ScriptPath $exportDiagnosticsScript -OnSuccess {
            Refresh-DiagnosticsView
        }
    } catch {
        Write-LaunchMessage @($_.Exception.Message)
    }
})
$updatesButton.Add_Click({
    try {
        Invoke-BackgroundShellScript -Name "Check updates" -ScriptPath $checkUpdatesScript
    } catch {
        Write-LaunchMessage @($_.Exception.Message)
    }
})
$aboutButton.Add_Click({
    Show-AboutDialog
    Write-LaunchMessage @("Otvoren About prozor.")
})

$refreshTimer = New-Object System.Windows.Forms.Timer
$refreshTimer.Interval = 3000
$refreshTimer.Add_Tick({
    Refresh-LaunchStatus -Lightweight
    Refresh-ThroughputView
})
$refreshTimer.Start()

Refresh-LaunchStatus -Lightweight
$hardwareBox.Text = "Hardverski plan ce se ucitati na zahtev ili posle prvog punog refresh-a."
$logsContent.Text = "Logovi ce se ucitati kada otvoris tab ili kliknes osvezavanje."
$onboardingBox.Text = "Onboarding pregled ce se ucitati kada otvoris tab ili kliknes osvezavanje."
$nextActionBox.Text = "Sledeci korak ce se ucitati kada otvoris Onboarding tab."
$healthMeta.Text = "Health pregled nije jos ucitan."
$healthContent.Text = "Otvori Health tab ili klikni osvezavanje da se ucita objedinjeni repair i health pregled."
$diagnosticsMeta.Text = "Diagnostics nisu jos ucitani."
$diagnosticsContent.Text = "Otvori Diagnostics tab ili klikni osvezavanje da se ucita detaljan pregled."
$throughputBox.Text = "JOS NEMA MERENJA.`r`nPokreni 'Test prompt' ili posalji normalan zahtev kroz server/OpenCode da bi se pojavili input/output tokeni po sekundi i istorija."
$modelInfoBox.Text = "Model info ce se ucitati kada otvoris Podesavanja tab."
$agentWarning.Text = "Risk audit ce se ucitati kada otvoris Agent tab."
$agentWarning.ForeColor = [System.Drawing.Color]::FromArgb(70, 70, 70)

$tabs.Add_SelectedIndexChanged({
    switch ($tabs.SelectedTab.Text) {
        "Podesavanja" {
            Ensure-ModelUiState
            Refresh-ModelSelectionInfo
        }
        "Onboarding" { Refresh-OnboardingView }
        "Health" { Refresh-HealthCenterView }
        "Logovi" { Refresh-LogsView }
        "Agent" { Refresh-AgentAudit }
        "Diagnostics" {
            Refresh-DiagnosticsView
            Refresh-ThroughputView
        }
    }
})

$startupTimer = New-Object System.Windows.Forms.Timer
$startupTimer.Interval = 800
$startupTimer.Add_Tick({
    $startupTimer.Stop()
    $effectiveStatus = Get-EffectiveServiceStatus
    if ($effectiveStatus.Summary.state -eq "inactive" -or $effectiveStatus.Summary.state -eq "failed") {
        try {
            $profile = [string](Get-Settings).profile
            Write-LaunchMessage @("Control Center je otvoren. Auto-start llama.cpp za profil '$profile'.")
            Start-LlamaBackground -Profile $profile
        } catch {
            Write-LaunchMessage @($_.Exception.Message)
        }
    } elseif ($effectiveStatus.Summary.state -eq "warming") {
        Write-LaunchMessage @("llama.cpp je vec u STARTING / WARMING stanju. Cekam da health postane dostupan.")
    } else {
        Write-LaunchMessage @("llama.cpp je vec aktivan.")
    }
})

$form.Add_Shown({
    $startupTimer.Start()
})

[void]$form.ShowDialog()
