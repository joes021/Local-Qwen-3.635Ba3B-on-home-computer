Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

. (Join-Path $PSScriptRoot "local-qwen-common.ps1")

$root = Get-LocalQwenRoot
$state = Get-InstallState

$configureSettingsScript = Join-Path $PSScriptRoot "configure-settings.ps1"
$startServerScript = Join-Path $PSScriptRoot "start-server.ps1"
$stopServerScript = Join-Path $PSScriptRoot "stop-server.ps1"
$startOpenCodeScript = Join-Path $PSScriptRoot "start-opencode.ps1"
$launchAgentScript = Join-Path $PSScriptRoot "launch-agent.ps1"
$manageModelsScript = Join-Path $PSScriptRoot "manage-models.ps1"
$checkUpdatesScript = Join-Path $PSScriptRoot "check-updates.ps1"
$exportDiagnosticsScript = Join-Path $PSScriptRoot "export-diagnostics.ps1"
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
$modelCatalog = @(Get-ModelCatalog)
$currentModelMeta = Get-ModelMetadata
$recommendationBundle = Get-RecommendationBundle

$form = New-Object System.Windows.Forms.Form
$form.Text = "Local Qwen Home Computer"
$form.StartPosition = "CenterScreen"
$form.Size = New-Object System.Drawing.Size(760, 720)
$form.MinimumSize = New-Object System.Drawing.Size(760, 720)
$form.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 251)
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$form.MaximizeBox = $false

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
$subtitle.Text = "Jedno mesto za pokretanje, podesavanja i agent rezim."
$subtitle.Location = New-Object System.Drawing.Point(20, 44)
$subtitle.Size = New-Object System.Drawing.Size(520, 22)
$subtitle.ForeColor = [System.Drawing.Color]::FromArgb(85, 85, 85)
$form.Controls.Add($subtitle)

$aboutButton = New-Object System.Windows.Forms.Button
$aboutButton.Text = "About"
$aboutButton.Location = New-Object System.Drawing.Point(620, 24)
$aboutButton.Size = New-Object System.Drawing.Size(104, 34)
$form.Controls.Add($aboutButton)

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Location = New-Object System.Drawing.Point(18, 78)
$tabs.Size = New-Object System.Drawing.Size(706, 586)
$form.Controls.Add($tabs)

$onboardingTab = New-Object System.Windows.Forms.TabPage
$onboardingTab.Text = "Onboarding"
$onboardingTab.BackColor = [System.Drawing.Color]::WhiteSmoke
$tabs.TabPages.Add($onboardingTab)

$launchTab = New-Object System.Windows.Forms.TabPage
$launchTab.Text = "Pokretanje"
$launchTab.BackColor = [System.Drawing.Color]::WhiteSmoke
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
$hardwareBox.Location = New-Object System.Drawing.Point(18, 182)
$hardwareBox.Size = New-Object System.Drawing.Size(648, 136)
$hardwareBox.Multiline = $true
$hardwareBox.ScrollBars = "Vertical"
$hardwareBox.ReadOnly = $true
$hardwareBox.BackColor = [System.Drawing.Color]::White
$hardwareBox.Text = "Ovde ce biti prikazan hardver i efektivne runtime opcije."
$launchTab.Controls.Add($hardwareBox)

$throughputBox = New-Object System.Windows.Forms.TextBox
$throughputBox.Location = New-Object System.Drawing.Point(18, 326)
$throughputBox.Size = New-Object System.Drawing.Size(648, 58)
$throughputBox.Multiline = $true
$throughputBox.ScrollBars = "Vertical"
$throughputBox.ReadOnly = $true
$throughputBox.BackColor = [System.Drawing.Color]::White
$throughputBox.Text = "Ovde ce biti prikazan benchmark poslednjeg zahteva i kratka istorija."
$launchTab.Controls.Add($throughputBox)

$launchOutput = New-Object System.Windows.Forms.TextBox
$launchOutput.Location = New-Object System.Drawing.Point(18, 392)
$launchOutput.Size = New-Object System.Drawing.Size(648, 128)
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

function Refresh-LaunchStatus {
    $latest = Get-Settings
    $plan = Get-EffectiveServerPlan -Profile ([string]$latest.profile)
    $selectedModel = Get-ModelMetadata
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
}

function Refresh-DiagnosticsView {
    $statusBundle = Get-EffectiveServiceStatus
    $latestLogs = Get-LatestLlamaLogs
    $latestRelease = Get-LatestReleaseInfo
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

function Refresh-ThroughputView {
    $tokenMetrics = Get-TokenMetricsSummary
    if (-not $tokenMetrics.current) {
        $throughputBox.Text = "Benchmark jos nije izmeren.`r`nPokreni 'Test prompt' da dobijes input/output tokene po sekundi i istoriju poslednjih merenja."
        return
    }

    $historyLines = @()
    foreach ($item in @($tokenMetrics.history)) {
        $historyLines += "$($item.promptTokensPerSecond) / $($item.completionTokensPerSecond) tok/s"
    }

    $throughputBox.Text = @(
        "Poslednje merenje: prompt $($tokenMetrics.current.promptTokensPerSecond) tok/s | output $($tokenMetrics.current.completionTokensPerSecond) tok/s | total $($tokenMetrics.current.totalMs) ms",
        "Prosek istorije: prompt $($tokenMetrics.averages.promptTokensPerSecond) tok/s | output $($tokenMetrics.averages.completionTokensPerSecond) tok/s",
        "Istorija: $($historyLines -join '   ;   ')"
    ) -join [Environment]::NewLine
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
    $notesBox.Text = Get-ReleaseNotesText
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

    $result = & powershell.exe -ExecutionPolicy Bypass -File $configureSettingsScript -Profile $Profile 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-LaunchMessage @($result)
        throw ($result -join [Environment]::NewLine)
    }

    Write-LaunchMessage @(
        "Pokrecem llama.cpp u pozadini za profil '$Profile'...",
        "Server ce se sam potvrditi cim /health postane dostupan."
    )
    Set-ServiceLifecycleState -State "starting" -Profile $Profile -Reason "Control Center je pokrenuo start u pozadini."
    Start-Process -FilePath "powershell.exe" -ArgumentList @(
        "-ExecutionPolicy", "Bypass",
        "-File", $startServerScript,
        "-Profile", $Profile,
        "-WaitSeconds", "90"
    ) -WindowStyle Hidden

    if ($result) {
        Write-LaunchMessage @($result)
    }
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

$repairInstallButton = New-Object System.Windows.Forms.Button
$repairInstallButton.Text = "Repair install"
$repairInstallButton.Location = New-Object System.Drawing.Point(18, 528)
$repairInstallButton.Size = New-Object System.Drawing.Size(124, 32)
$launchTab.Controls.Add($repairInstallButton)

$testPromptButton = New-Object System.Windows.Forms.Button
$testPromptButton.Text = "Test prompt"
$testPromptButton.Location = New-Object System.Drawing.Point(152, 528)
$testPromptButton.Size = New-Object System.Drawing.Size(110, 32)
$launchTab.Controls.Add($testPromptButton)

$modelManagerButton = New-Object System.Windows.Forms.Button
$modelManagerButton.Text = "Model manager"
$modelManagerButton.Location = New-Object System.Drawing.Point(272, 528)
$modelManagerButton.Size = New-Object System.Drawing.Size(124, 32)
$launchTab.Controls.Add($modelManagerButton)

$diagnosticsButton = New-Object System.Windows.Forms.Button
$diagnosticsButton.Text = "Diagnostics"
$diagnosticsButton.Location = New-Object System.Drawing.Point(406, 528)
$diagnosticsButton.Size = New-Object System.Drawing.Size(120, 32)
$launchTab.Controls.Add($diagnosticsButton)

$updatesButton = New-Object System.Windows.Forms.Button
$updatesButton.Text = "Check updates"
$updatesButton.Location = New-Object System.Drawing.Point(536, 528)
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
    [void]$modelCombo.Items.Add("$($item.label) | $($item.approxSizeGiB) GiB")
}
$initialModelIndex = 0
for ($i = 0; $i -lt $modelCatalog.Count; $i++) {
    if ($modelCatalog[$i].id -eq $currentModelMeta.id) {
        $initialModelIndex = $i
        break
    }
}
$modelCombo.SelectedIndex = $initialModelIndex
$settingsPanel.Controls.Add($modelCombo)

$downloadModelButton = New-Object System.Windows.Forms.Button
$downloadModelButton.Text = "Preuzmi izabrani model"
$downloadModelButton.Location = New-Object System.Drawing.Point(400, 78)
$downloadModelButton.Size = New-Object System.Drawing.Size(185, 32)
$settingsPanel.Controls.Add($downloadModelButton)

$contextRow = Add-ContextRow -Parent $settingsPanel -Y 122 -SelectedValue ([int]$settings.llama.contextSize)
$outputRow = Add-TrackFieldRow -Parent $settingsPanel -LabelText "Max output tokens" -Y 210 -Minimum 1024 -Maximum 16384 -TickFrequency 1024 -Value ([int]$settings.llama.maxOutputTokens) -Increment 256
$buildRow = Add-TrackFieldRow -Parent $settingsPanel -LabelText "Build steps" -Y 298 -Minimum 20 -Maximum 200 -TickFrequency 10 -Value ([int]$settings.opencode.buildSteps)
$planRow = Add-TrackFieldRow -Parent $settingsPanel -LabelText "Plan steps" -Y 386 -Minimum 20 -Maximum 200 -TickFrequency 10 -Value ([int]$settings.opencode.planSteps)
$generalRow = Add-TrackFieldRow -Parent $settingsPanel -LabelText "General steps" -Y 474 -Minimum 20 -Maximum 200 -TickFrequency 10 -Value ([int]$settings.opencode.generalSteps)
$exploreRow = Add-TrackFieldRow -Parent $settingsPanel -LabelText "Explore steps" -Y 562 -Minimum 10 -Maximum 150 -TickFrequency 10 -Value ([int]$settings.opencode.exploreSteps)

$settingsStatus = New-Object System.Windows.Forms.Label
$settingsStatus.Text = "Promene vaze za buduca pokretanja."
$settingsStatus.Location = New-Object System.Drawing.Point(18, 652)
$settingsStatus.Size = New-Object System.Drawing.Size(300, 24)
$settingsStatus.ForeColor = [System.Drawing.Color]::FromArgb(70, 70, 70)
$settingsPanel.Controls.Add($settingsStatus)

$saveSettingsButton = New-Object System.Windows.Forms.Button
$saveSettingsButton.Text = "Sacuvaj podesavanja"
$saveSettingsButton.Location = New-Object System.Drawing.Point(430, 646)
$saveSettingsButton.Size = New-Object System.Drawing.Size(155, 34)
$saveSettingsButton.BackColor = [System.Drawing.Color]::FromArgb(23, 111, 235)
$saveSettingsButton.ForeColor = [System.Drawing.Color]::White
$saveSettingsButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$settingsPanel.Controls.Add($saveSettingsButton)

$resetSettingsButton = New-Object System.Windows.Forms.Button
$resetSettingsButton.Text = "Vrati preporuku"
$resetSettingsButton.Location = New-Object System.Drawing.Point(285, 646)
$resetSettingsButton.Size = New-Object System.Drawing.Size(132, 34)
$settingsPanel.Controls.Add($resetSettingsButton)

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

$resetSettingsButton.Add_Click({
    $contextRow.Track.Value = 3
    $outputRow.Numeric.Value = 8192
    $buildRow.Numeric.Value = 120
    $planRow.Numeric.Value = 80
    $generalRow.Numeric.Value = 100
    $exploreRow.Numeric.Value = 60
    for ($i = 0; $i -lt $modelCatalog.Count; $i++) {
        if ($modelCatalog[$i].id -eq $recommendationBundle.recommendedModel.id) {
            $modelCombo.SelectedIndex = $i
            break
        }
    }
    Write-LaunchMessage @("Vracene preporucene vrednosti u formi. Klikni 'Sacuvaj podesavanja' da postanu aktivne.")
})

$saveSettingsButton.Add_Click({
    try {
        $contextValue = $contextRow.Presets[$contextRow.Track.Value]
        $selectedModel = $modelCatalog[$modelCombo.SelectedIndex]
        if ($selectedModel) {
            & powershell.exe -ExecutionPolicy Bypass -File $manageModelsScript -ModelId ([string]$selectedModel.id) 2>&1 | Out-Null
        }
        $result = & powershell.exe -ExecutionPolicy Bypass -File $configureSettingsScript `
            -ContextSize $contextValue `
            -MaxOutputTokens ([int]$outputRow.Numeric.Value) `
            -BuildSteps ([int]$buildRow.Numeric.Value) `
            -PlanSteps ([int]$planRow.Numeric.Value) `
            -GeneralSteps ([int]$generalRow.Numeric.Value) `
            -ExploreSteps ([int]$exploreRow.Numeric.Value) 2>&1

        if ($LASTEXITCODE -ne 0) {
            throw ($result -join [Environment]::NewLine)
        }

        $settingsStatus.Text = "Sacuvano za buduca pokretanja."
        $settingsStatus.ForeColor = [System.Drawing.Color]::FromArgb(20, 120, 50)
        Write-LaunchMessage @($result)
        Refresh-LaunchStatus
    } catch {
        $settingsStatus.Text = "Greska pri cuvanju."
        $settingsStatus.ForeColor = [System.Drawing.Color]::FromArgb(180, 45, 45)
        Write-LaunchMessage @($_.Exception.Message)
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Greska", 0, 16) | Out-Null
    }
})

$downloadModelButton.Add_Click({
    try {
        $selectedModel = $modelCatalog[$modelCombo.SelectedIndex]
        $result = & powershell.exe -ExecutionPolicy Bypass -File $manageModelsScript -ModelId ([string]$selectedModel.id) -Download 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw ($result -join [Environment]::NewLine)
        }
        Write-LaunchMessage @($result)
        $settingsStatus.Text = "Model je osvezen: $($selectedModel.id)"
        $settingsStatus.ForeColor = [System.Drawing.Color]::FromArgb(20, 120, 50)
        Refresh-LaunchStatus
        Refresh-LogsView
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
        $result = & powershell.exe -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "repair-install.ps1") 2>&1
        Write-LaunchMessage @($result)
        Refresh-LaunchStatus
        Refresh-LogsView
        Refresh-DiagnosticsView
    } catch {
        Write-LaunchMessage @($_.Exception.Message)
    }
})
$testPromptButton.Add_Click({
    try {
        $profile = [string](Get-Settings).profile
        $result = & powershell.exe -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "test-prompt.ps1") -Profile $profile 2>&1
        Write-LaunchMessage @($result)
        Refresh-LogsView
        Refresh-DiagnosticsView
        Refresh-ThroughputView
    } catch {
        Write-LaunchMessage @($_.Exception.Message)
    }
})
$modelManagerButton.Add_Click({
    try {
        $result = & powershell.exe -ExecutionPolicy Bypass -File $manageModelsScript 2>&1
        Write-LaunchMessage @($result)
    } catch {
        Write-LaunchMessage @($_.Exception.Message)
    }
})
$diagnosticsButton.Add_Click({
    try {
        $result = & powershell.exe -ExecutionPolicy Bypass -File $exportDiagnosticsScript 2>&1
        Write-LaunchMessage @($result)
        Refresh-DiagnosticsView
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
        $result = & powershell.exe -ExecutionPolicy Bypass -File $exportDiagnosticsScript 2>&1
        Write-LaunchMessage @($result)
        Refresh-DiagnosticsView
    } catch {
        Write-LaunchMessage @($_.Exception.Message)
    }
})
$updatesButton.Add_Click({
    try {
        $result = & powershell.exe -ExecutionPolicy Bypass -File $checkUpdatesScript 2>&1
        Write-LaunchMessage @($result)
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
    Refresh-LaunchStatus
    Refresh-DiagnosticsView
    Refresh-ThroughputView
})
$refreshTimer.Start()

Refresh-LaunchStatus
Refresh-LogsView
Refresh-AgentAudit
Refresh-OnboardingView
Refresh-DiagnosticsView
Refresh-ThroughputView

$form.Add_Shown({
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

[void]$form.ShowDialog()
