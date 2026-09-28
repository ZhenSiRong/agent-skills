# Disables everything that makes Windows launch its hypervisor. Records originals, asks for YES, no auto reboot.
$ErrorActionPreference = 'Continue'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

$log = Join-Path $PSScriptRoot 'hypervisor-original-state.txt'
Start-Transcript -Path $log -Force | Out-Null
$dgKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'
$helloKey = "$dgKey\Scenarios\WindowsHello"
$features = 'Microsoft-Hyper-V-All', 'VirtualMachinePlatform', 'HypervisorPlatform', 'Containers-DisposableClientVM'

"=== ORIGINAL STATE ==="
$enabled = Get-WindowsOptionalFeature -Online | Where-Object { $_.FeatureName -in $features -and $_.State -eq 'Enabled' }
$enabled | Format-Table FeatureName, State | Out-String
& "$env:SystemRoot\System32\bcdedit.exe" /enum '{current}' | Select-String hypervisorlaunchtype
"EnableVirtualizationBasedSecurity = " + (Get-ItemProperty $dgKey -ErrorAction SilentlyContinue).EnableVirtualizationBasedSecurity
"Scenarios\WindowsHello\Enabled   = " + (Get-ItemProperty $helloKey -ErrorAction SilentlyContinue).Enabled
""
"Cost: WSL2 / Docker Desktop / Windows Sandbox stop working; Windows Hello PIN/face may need to be set up again."
$answer = Read-Host "Type YES to apply, anything else to exit without changes"

if ($answer -ceq 'YES') {
    & "$env:SystemRoot\System32\bcdedit.exe" /set hypervisorlaunchtype off
    Set-ItemProperty $dgKey -Name EnableVirtualizationBasedSecurity -Value 0 -Type DWord
    if (Test-Path $helloKey) { Set-ItemProperty $helloKey -Name Enabled -Value 0 -Type DWord }
    foreach ($f in $enabled) {
        Disable-WindowsOptionalFeature -Online -FeatureName $f.FeatureName -NoRestart | Out-Null
        "Disabled feature: $($f.FeatureName)"
    }
    "=== DONE. Reboot, then check (Get-CimInstance Win32_ComputerSystem).HypervisorPresent -eq False ==="
} else {
    "No changes made."
}
Stop-Transcript | Out-Null
Read-Host "Press Enter to close"
