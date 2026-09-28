# Removes global VMware defaults that break macOS guests (pciHole overlap, passthrough MMIO, hidden hypervisor bit).
$ErrorActionPreference = 'Stop'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

$cfg = 'C:\ProgramData\VMware\VMware Workstation\config.ini'
$pattern = '^\s*(hypervisor\.cpuid\.v0|pciPassthru\.use64bitMMIO|pciPassthru\.64bitMMIOSizeGB|pciHole\.start|pciHole\.end)\s*='

"Lines to remove from $cfg (they apply to EVERY VM):"
Get-Content $cfg | Where-Object { $_ -match $pattern }
"Power off the macOS VM before continuing."
$answer = Read-Host "Type YES to back up and remove these lines, anything else to exit"
if ($answer -ceq 'YES') {
    $backup = "$cfg.bak-" + (Get-Date -Format 'yyyyMMdd-HHmmss')
    Copy-Item $cfg $backup
    "Backup: $backup"
    Set-Content -Path $cfg -Value (Get-Content $cfg | Where-Object { $_ -notmatch $pattern }) -Encoding ascii
    "=== DONE. Start the VM again. ==="
} else {
    "No changes made."
}
Read-Host "Press Enter to close"
