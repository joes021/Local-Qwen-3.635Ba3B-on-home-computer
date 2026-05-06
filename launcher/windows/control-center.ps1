Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

. (Join-Path $PSScriptRoot "local-qwen-common.ps1")

$form = New-Object System.Windows.Forms.Form
$form.Text = "Local Qwen Home Computer"
$form.StartPosition = "CenterScreen"
$form.Size = New-Object System.Drawing.Size(640, 420)
$form.MinimumSize = $form.Size
$form.MaximumSize = $form.Size
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 251)
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

$root = Get-LocalQwenRoot
$iconPath = Join-Path $root "assets\icons\control-center.ico"
if (Test-Path $iconPath) {
    $form.Icon = New-Object System.Drawing.Icon($iconPath)
}

$title = New-Object System.Windows.Forms.Label
$title.Text = "Local Qwen 3.6 35B A3B Control Center"
$title.Location = New-Object System.Drawing.Point(18, 14)
$title.Size = New-Object System.Drawing.Size(500, 28)
$title.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 14, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($title)

$status = New-Object System.Windows.Forms.Label
$status.Location = New-Object System.Drawing.Point(22, 50)
$status.Size = New-Object System.Drawing.Size(560, 22)
$form.Controls.Add($status)

$output = New-Object System.Windows.Forms.TextBox
$output.Location = New-Object System.Drawing.Point(22, 180)
$output.Size = New-Object System.Drawing.Size(580, 170)
$output.Multiline = $true
$output.ScrollBars = "Vertical"
$output.ReadOnly = $true
$output.BackColor = [System.Drawing.Color]::White
$output.Text = "Ready."
$form.Controls.Add($output)

$profileLabel = New-Object System.Windows.Forms.Label
$profileLabel.Text = "Profil"
$profileLabel.Location = New-Object System.Drawing.Point(22, 88)
$profileLabel.Size = New-Object System.Drawing.Size(80, 22)
$form.Controls.Add($profileLabel)

$profileCombo = New-Object System.Windows.Forms.ComboBox
$profileCombo.Location = New-Object System.Drawing.Point(22, 112)
$profileCombo.Size = New-Object System.Drawing.Size(140, 28)
$profileCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
foreach ($name in @("speed", "balanced", "video")) {
    [void]$profileCombo.Items.Add($name)
}
$profileCombo.SelectedItem = [string](Get-Settings).profile
$form.Controls.Add($profileCombo)

$startButton = New-Object System.Windows.Forms.Button
$startButton.Text = "Start server"
$startButton.Location = New-Object System.Drawing.Point(190, 108)
$startButton.Size = New-Object System.Drawing.Size(120, 34)
$form.Controls.Add($startButton)

$stopButton = New-Object System.Windows.Forms.Button
$stopButton.Text = "Stop server"
$stopButton.Location = New-Object System.Drawing.Point(320, 108)
$stopButton.Size = New-Object System.Drawing.Size(120, 34)
$form.Controls.Add($stopButton)

$openButton = New-Object System.Windows.Forms.Button
$openButton.Text = "Otvori OpenCode"
$openButton.Location = New-Object System.Drawing.Point(450, 108)
$openButton.Size = New-Object System.Drawing.Size(152, 34)
$openButton.BackColor = [System.Drawing.Color]::FromArgb(23, 111, 235)
$openButton.ForeColor = [System.Drawing.Color]::White
$openButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$form.Controls.Add($openButton)

$configureButton = New-Object System.Windows.Forms.Button
$configureButton.Text = "Upisi OpenCode config"
$configureButton.Location = New-Object System.Drawing.Point(22, 148)
$configureButton.Size = New-Object System.Drawing.Size(170, 28)
$form.Controls.Add($configureButton)

$webButton = New-Object System.Windows.Forms.Button
$webButton.Text = "Otvori web UI"
$webButton.Location = New-Object System.Drawing.Point(202, 148)
$webButton.Size = New-Object System.Drawing.Size(120, 28)
$form.Controls.Add($webButton)

function Refresh-Status {
    if (Test-LlamaHealth) {
        $status.Text = "Status: server aktivan na $(Get-LlamaHealthUrl)"
        $status.ForeColor = [System.Drawing.Color]::FromArgb(20, 120, 50)
    } else {
        $status.Text = "Status: server nije aktivan"
        $status.ForeColor = [System.Drawing.Color]::FromArgb(180, 45, 45)
    }
}

$startButton.Add_Click({
    $result = & powershell.exe -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "start-server.ps1") -Profile ([string]$profileCombo.SelectedItem) 2>&1
    $output.Text = ($result -join [Environment]::NewLine)
    Refresh-Status
})

$stopButton.Add_Click({
    $result = & powershell.exe -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "stop-server.ps1") 2>&1
    $output.Text = ($result -join [Environment]::NewLine)
    Refresh-Status
})

$openButton.Add_Click({
    Start-Process -FilePath "powershell.exe" -ArgumentList @(
        "-ExecutionPolicy", "Bypass",
        "-File", (Join-Path $PSScriptRoot "start-opencode.ps1"),
        "-Profile", ([string]$profileCombo.SelectedItem)
    )
    $output.Text = "OpenCode launcher je pokrenut."
})

$configureButton.Add_Click({
    $path = Update-OpenCodeConfig
    $output.Text = "OpenCode config upisan u:`r`n$path"
})

$webButton.Add_Click({
    Start-Process (Get-LlamaHealthUrl).Replace("/health", "/")
})

Refresh-Status
[void]$form.ShowDialog()
