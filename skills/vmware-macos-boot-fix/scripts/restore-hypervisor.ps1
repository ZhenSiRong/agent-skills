# Restores Hyper-V/VBS defaults. Fast settings first; features from local source only (no Windows Update hang).
$ErrorActionPreference = 'Continue'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

Start-Transcript -Path (Join-Path $PSScriptRoot 'restore-status.txt') -Force | Out-Null
$dgKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'
"Will set: hypervisorlaunchtype=auto, EnableVirtualizationBasedSecurity=1, Scenarios\WindowsHello\Enabled=1,"
"and enable VirtualMachinePlatform + HypervisorPlatform. Check hypervisor-original-state.txt for what was originally on."
$answer = Read-Host "Type YES to restore, anything else to exit"

if ($answer -ceq 'YES') {
    & "$env:SystemRoot\System32\bcdedit.exe" /set hypervisorlaunchtype auto
    Set-ItemProperty $dgKey -Name EnableVirtualizationBasedSecurity -Value 1 -Type DWord
    if (Test-Path "$dgKey\Scenarios\WindowsHello") { Set-ItemProperty "$dgKey\Scenarios\WindowsHello" -Name Enabled -Value 1 -Type DWord }
    foreach ($f in 'VirtualMachinePlatform', 'HypervisorPlatform') {
        try {
            Enable-WindowsOptionalFeature -Online -FeatureName $f -NoRestart -LimitAccess -ErrorAction Stop | Out-Null
            "Enabled feature: $f"
        } catch {
            "FAILED (no local payload): $f. Reboot and retry with network, or use -Source wim:X:\sources\install.wim:<index> -LimitAccess from a same-build ISO."
        }
    }
    "=== DONE. Reboot. ==="
} else {
    "No changes made."
}
Stop-Transcript | Out-Null
Read-Host "Press Enter to close"
