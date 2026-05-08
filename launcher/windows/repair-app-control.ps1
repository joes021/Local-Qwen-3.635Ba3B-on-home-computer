param(
    [switch]$DisableSmartAppControl,
    [switch]$RefreshPoliciesOnly
)

$ErrorActionPreference = "Stop"

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-CiToolPolicies {
    $raw = CiTool.exe -lp -json | Out-String
    $jsonStart = $raw.IndexOf('{')
    if ($jsonStart -lt 0) {
        throw "CiTool output nije vracen u ocekivanom JSON obliku."
    }

    return ($raw.Substring($jsonStart) | ConvertFrom-Json)
}

function Get-SmartAppControlPolicies {
    $policies = (Get-CiToolPolicies).Policies
    return $policies | Where-Object {
        $_.FriendlyName -like "VerifiedAndReputableDesktop*"
    }
}

if (-not (Get-Command CiTool.exe -ErrorAction SilentlyContinue)) {
    throw "CiTool.exe nije dostupan na ovom sistemu."
}

if ($RefreshPoliciesOnly) {
    if (-not (Test-IsAdmin)) {
        throw "Za refresh App Control politika potrebna su administratorska prava."
    }

    CiTool.exe -r | Out-Host
    Write-Host "App Control politike su osvezene." -ForegroundColor Green
    exit 0
}

$smartPolicies = Get-SmartAppControlPolicies

Write-Host "Smart App Control / VerifiedAndReputableDesktop stanje:" -ForegroundColor Cyan
$smartPolicies |
    Select-Object FriendlyName, PolicyID, IsEnforced, IsAuthorized, IsSignedPolicy |
    Format-Table -AutoSize

if ($DisableSmartAppControl) {
    if (-not (Test-IsAdmin)) {
        throw "Za iskljucivanje Smart App Control potrebna su administratorska prava."
    }

    Write-Host ""
    Write-Host "Pokusavam da iskljucim Smart App Control preko registry + CiTool refresh..." -ForegroundColor Yellow

    Set-ItemProperty `
        -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy" `
        -Name "VerifiedAndReputablePolicyState" `
        -Type DWord `
        -Value 0

    try {
        if (-not (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Protected")) {
            New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Protected" -Force | Out-Null
        }

        Set-ItemProperty `
            -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Protected" `
            -Name "VerifiedAndReputablePolicyStateMinValueSeen" `
            -Type DWord `
            -Value 0
    } catch {
        Write-Host "Protected registry vrednost nije promenjena: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    CiTool.exe -r | Out-Host

    Write-Host ""
    Write-Host "Novo stanje:" -ForegroundColor Cyan
    $smartPolicies = Get-SmartAppControlPolicies
    $smartPolicies |
        Select-Object FriendlyName, PolicyID, IsEnforced, IsAuthorized, IsSignedPolicy |
        Format-Table -AutoSize

    Write-Host ""
    Write-Host "Napomena:" -ForegroundColor Yellow
    Write-Host "- Smart App Control je Microsoft sigurnosna funkcija." -ForegroundColor Yellow
    Write-Host "- Kada ga jednom prebacis na Off, Microsoft navodi da se cesto ne moze vratiti bez reset/reinstall toka." -ForegroundColor Yellow
    Write-Host "- Ako politiku vraca firma/Intune/GPO, promene mogu biti privremene." -ForegroundColor Yellow
}
