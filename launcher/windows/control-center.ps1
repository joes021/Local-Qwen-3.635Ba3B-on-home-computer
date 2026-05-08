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

    $track.Add_ValueChanged({
        if ($numeric.Value -ne $track.Value) {
            $numeric.Value = $track.Value
        }
    })

    $numeric.Add_ValueChanged({
        $next = [int]$numeric.Value
        if ($track.Value -ne $next) {
            $track.Value = $next
        }
    })

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
    }

    $track.Add_ValueChanged($syncContext)
    $combo.Add_SelectedIndexChanged({
        if ($track.Value -ne $combo.SelectedIndex) {
            $track.Value = $combo.SelectedIndex
        }
    })

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
$hardwareBox.Size = New-Object System.Drawing.Size(648, 170)
$hardwareBox.Multiline = $true
$hardwareBox.ScrollBars = "Vertical"
$hardwareBox.ReadOnly = $true
$hardwareBox.BackColor = [System.Drawing.Color]::White
$hardwareBox.Text = "Ovde ce biti prikazan hardver i efektivne runtime opcije."
$launchTab.Controls.Add($hardwareBox)

$launchOutput = New-Object System.Windows.Forms.TextBox
$launchOutput.Location = New-Object System.Drawing.Point(18, 386)
$launchOutput.Size = New-Object System.Drawing.Size(648, 134)
$launchOutput.Multiline = $true
$launchOutput.ScrollBars = "Vertical"
$launchOutput.ReadOnly = $true
$launchOutput.BackColor = [System.Drawing.Color]::White
$launchOutput.Text = "Ovde ce se pojavljivati status i rezultati akcija."
$launchTab.Controls.Add($launchOutput)

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
        $notes
    ) -join [Environment]::NewLine
}

function Refresh-LaunchStatus {
    $latest = Get-Settings
    $plan = Get-EffectiveServerPlan -Profile ([string]$latest.profile)
    if (Test-LlamaHealth) {
        $serverStatus.Text = "Server status: AKTIVAN na $(Get-LlamaHealthUrl)"
        $serverStatus.ForeColor = [System.Drawing.Color]::FromArgb(20, 120, 50)
    } else {
        $serverStatus.Text = "Server status: NIJE aktivan"
        $serverStatus.ForeColor = [System.Drawing.Color]::FromArgb(180, 45, 45)
    }

    $profileNote.Text = "Context: $($latest.llama.contextSize) | Output: $($latest.llama.maxOutputTokens) | Steps: B $($latest.opencode.buildSteps) / P $($latest.opencode.planSteps) / G $($latest.opencode.generalSteps) / E $($latest.opencode.exploreSteps)"
    $hardwareBox.Text = Format-ServerPlan -Plan $plan
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

$contextRow = Add-ContextRow -Parent $settingsPanel -Y 22 -SelectedValue ([int]$settings.llama.contextSize)
$outputRow = Add-TrackFieldRow -Parent $settingsPanel -LabelText "Max output tokens" -Y 110 -Minimum 1024 -Maximum 16384 -TickFrequency 1024 -Value ([int]$settings.llama.maxOutputTokens) -Increment 256
$buildRow = Add-TrackFieldRow -Parent $settingsPanel -LabelText "Build steps" -Y 198 -Minimum 20 -Maximum 200 -TickFrequency 10 -Value ([int]$settings.opencode.buildSteps)
$planRow = Add-TrackFieldRow -Parent $settingsPanel -LabelText "Plan steps" -Y 286 -Minimum 20 -Maximum 200 -TickFrequency 10 -Value ([int]$settings.opencode.planSteps)
$generalRow = Add-TrackFieldRow -Parent $settingsPanel -LabelText "General steps" -Y 374 -Minimum 20 -Maximum 200 -TickFrequency 10 -Value ([int]$settings.opencode.generalSteps)
$exploreRow = Add-TrackFieldRow -Parent $settingsPanel -LabelText "Explore steps" -Y 462 -Minimum 10 -Maximum 150 -TickFrequency 10 -Value ([int]$settings.opencode.exploreSteps)

$settingsStatus = New-Object System.Windows.Forms.Label
$settingsStatus.Text = "Promene vaze za buduca pokretanja."
$settingsStatus.Location = New-Object System.Drawing.Point(18, 552)
$settingsStatus.Size = New-Object System.Drawing.Size(300, 24)
$settingsStatus.ForeColor = [System.Drawing.Color]::FromArgb(70, 70, 70)
$settingsPanel.Controls.Add($settingsStatus)

$saveSettingsButton = New-Object System.Windows.Forms.Button
$saveSettingsButton.Text = "Sacuvaj podesavanja"
$saveSettingsButton.Location = New-Object System.Drawing.Point(430, 546)
$saveSettingsButton.Size = New-Object System.Drawing.Size(155, 34)
$saveSettingsButton.BackColor = [System.Drawing.Color]::FromArgb(23, 111, 235)
$saveSettingsButton.ForeColor = [System.Drawing.Color]::White
$saveSettingsButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$settingsPanel.Controls.Add($saveSettingsButton)

$resetSettingsButton = New-Object System.Windows.Forms.Button
$resetSettingsButton.Text = "Vrati preporuku"
$resetSettingsButton.Location = New-Object System.Drawing.Point(285, 546)
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
$agentWarning.Size = New-Object System.Drawing.Size(460, 22)
$agentWarning.ForeColor = [System.Drawing.Color]::FromArgb(176, 72, 18)
$agentPanel.Controls.Add($agentWarning)

$agentStatus = New-Object System.Windows.Forms.Label
$agentStatus.Text = "Konfiguracija se cuva pre starta."
$agentStatus.Location = New-Object System.Drawing.Point(18, 462)
$agentStatus.Size = New-Object System.Drawing.Size(360, 24)
$agentStatus.ForeColor = [System.Drawing.Color]::FromArgb(70, 70, 70)
$agentPanel.Controls.Add($agentStatus)

$saveAgentButton = New-Object System.Windows.Forms.Button
$saveAgentButton.Text = "Sacuvaj agent rezim"
$saveAgentButton.Location = New-Object System.Drawing.Point(365, 452)
$saveAgentButton.Size = New-Object System.Drawing.Size(140, 34)
$agentPanel.Controls.Add($saveAgentButton)

$launchAgentButton = New-Object System.Windows.Forms.Button
$launchAgentButton.Text = "Pokreni agent"
$launchAgentButton.Location = New-Object System.Drawing.Point(520, 452)
$launchAgentButton.Size = New-Object System.Drawing.Size(128, 34)
$launchAgentButton.BackColor = [System.Drawing.Color]::FromArgb(23, 111, 235)
$launchAgentButton.ForeColor = [System.Drawing.Color]::White
$launchAgentButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$agentPanel.Controls.Add($launchAgentButton)

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
    }
})

$resetSettingsButton.Add_Click({
    $contextRow.Track.Value = 3
    $outputRow.Numeric.Value = 8192
    $buildRow.Numeric.Value = 120
    $planRow.Numeric.Value = 80
    $generalRow.Numeric.Value = 100
    $exploreRow.Numeric.Value = 60
    Write-LaunchMessage @("Vracene preporucene vrednosti u formi. Klikni 'Sacuvaj podesavanja' da postanu aktivne.")
})

$saveSettingsButton.Add_Click({
    try {
        $contextValue = $contextRow.Presets[$contextRow.Track.Value]
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
$openFolderButton.Add_Click({
    Start-Process explorer.exe $root
    Write-LaunchMessage @("Otvoren install folder: $root")
})
$aboutButton.Add_Click({
    Show-AboutDialog
    Write-LaunchMessage @("Otvoren About prozor.")
})

$refreshTimer = New-Object System.Windows.Forms.Timer
$refreshTimer.Interval = 3000
$refreshTimer.Add_Tick({
    Refresh-LaunchStatus
})
$refreshTimer.Start()

Refresh-LaunchStatus

$form.Add_Shown({
    if (-not (Test-LlamaHealth)) {
        try {
            $profile = [string](Get-Settings).profile
            Write-LaunchMessage @("Control Center je otvoren. Auto-start llama.cpp za profil '$profile'.")
            Start-LlamaBackground -Profile $profile
        } catch {
            Write-LaunchMessage @($_.Exception.Message)
        }
    } else {
        Write-LaunchMessage @("llama.cpp je vec aktivan.")
    }
})

[void]$form.ShowDialog()
