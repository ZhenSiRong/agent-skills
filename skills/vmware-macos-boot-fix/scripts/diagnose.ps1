param([string]$VmDir)
# Read-only. Usage: powershell -ExecutionPolicy Bypass -File diagnose.ps1 -VmDir "D:\macos-vm"

"== Host hypervisor"
"HypervisorPresent: " + (Get-CimInstance Win32_ComputerSystem).HypervisorPresent
$dg = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction SilentlyContinue
"VBS status: $($dg.VirtualizationBasedSecurityStatus)  Configured: $($dg.SecurityServicesConfigured -join ',')  Running: $($dg.SecurityServicesRunning -join ',')"
$dgKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'
"EnableVirtualizationBasedSecurity: " + (Get-ItemProperty $dgKey -ErrorAction SilentlyContinue).EnableVirtualizationBasedSecurity
Get-ChildItem "$dgKey\Scenarios" -ErrorAction SilentlyContinue | ForEach-Object { "Scenario $($_.PSChildName): Enabled=" + (Get-ItemProperty $_.PSPath).Enabled }
"Policy DeviceGuard: " + ((Get-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard -ErrorAction SilentlyContinue | Out-String).Trim())
"LsaCfgFlags: " + (Get-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Control\Lsa -ErrorAction SilentlyContinue).LsaCfgFlags
"CBS RebootPending: " + (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')

"== Optional features (needs admin; errors are harmless otherwise)"
Get-WindowsOptionalFeature -Online -ErrorAction SilentlyContinue | Where-Object { $_.FeatureName -match 'Hyper-V|VirtualMachinePlatform|HypervisorPlatform|DisposableClientVM' } | Format-Table FeatureName, State | Out-String

"== VMware global config.ini (applies to every VM)"
$cfg = 'C:\ProgramData\VMware\VMware Workstation\config.ini'
if (Test-Path $cfg) { Get-Content $cfg | Select-String 'hypervisor\.cpuid|pciHole|pciPassthru' | ForEach-Object { "SUSPICIOUS: $($_.Line)" } }

if ($VmDir) {
    "== VM folder $VmDir"
    $vmx = Get-ChildItem $VmDir -Filter *.vmx | Select-Object -First 1
    if ($vmx) { Get-Content $vmx.FullName | Select-String '^(guestOS|numvcpus|cpuid\.|memsize|smc\.|hypervisor\.|pciHole|firmware)' | ForEach-Object { $_.Line } }
    $log = Join-Path $VmDir 'vmware.log'
    if (Test-Path $log) {
        Get-Content $log | Select-String 'Hyper-V detected|WHP|Monitor Mode|VBS is set|About to do EFI boot|transitioned to runtime|Triple fault|DarwinPanic' |
            Select-Object -First 30 | ForEach-Object { "$($_.LineNumber): $($_.Line)" }
    }
}
