---
name: vmware-macos-boot-fix
description: 'Diagnose and fix a macOS guest in VMware Workstation on Windows that loops between the VMware logo and the Apple logo (boot loop, "Triple fault" and "CPU reset hard" in vmware.log). Covers Hyper-V/VBS/WHP forcing VMware into compatibility mode (including the hidden Windows Hello VBS scenario), bad global VMware config.ini keys (pciHole, pciPassthru, hypervisor.cpuid.v0), rollback, and stuck Windows Update when re-enabling features. Use when the user says macOS VM keeps rebooting, bootloops, triple faults, or asks to run macOS on VMware on a Windows host.'
---

# VMware Workstation macOS boot-loop fix (Windows host)

Symptom: the VM alternates between the VMware logo and the Apple logo every few seconds and never reaches the installer/desktop.
This is a guest kernel crash + VM reset, not a hang. Always confirm from the log before changing anything.

## 0. Rules

- Read-only diagnosis first (`scripts/diagnose.ps1`). Every change script records original values and asks for `YES`.
- System security changes (VBS, Windows Hello) need explicit user consent; state the cost first
  (WSL2 / Docker Desktop / Windows Sandbox stop working; Windows Hello PIN/face may need re-setup — make sure the user knows their Microsoft account password).
- Windows changes need a reboot; re-check after each reboot instead of assuming.
- Scripts self-elevate (UAC). Launch them with `Start-Process powershell -Verb RunAs ...`; the user answers in that window; read the log file afterwards.

## 1. Read vmware.log (in the VM folder)

Look for this sequence:

```text
Guest: About to do EFI boot ...           -> Apple logo appears (unlocker/SMC OK)
Guest: Firmware has transitioned to runtime.
Triple fault.                             -> macOS kernel died
CPU reset: hard                           -> loop
```

Then check which engine VMware used:

| Log line | Meaning | Go to |
|---|---|---|
| `IOPL_Init: Hyper-V detected by CPUID`, `WHP`, `Syncing WHP TSCs` | VMware runs on top of Windows Hypervisor Platform. macOS triple-faults here. | Step 2 |
| `Monitor Mode: CPL0`, `VBS is set to 0`, no WHP lines, still `Triple fault` | Hypervisor problem solved; a second cause remains. | Step 3 |

## 2. Get rid of the Windows hypervisor

Goal: `(Get-CimInstance Win32_ComputerSystem).HypervisorPresent` is `False` after reboot.

Disable in this order, rebooting and re-checking after each round (`scripts/disable-hypervisor.ps1` does all of it with backup):

1. Optional features: `Microsoft-Hyper-V-All`, `VirtualMachinePlatform`, `HypervisorPlatform`, `Containers-DisposableClientVM` (only those `Enabled`).
2. `bcdedit /set hypervisorlaunchtype off`
3. `HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\EnableVirtualizationBasedSecurity = 0` (also the policy key `HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard` if present).
4. **Hidden culprit:** `HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\WindowsHello\Enabled = 1`
   (Windows Hello enhanced sign-in security) keeps launching the hypervisor even after 1–3.
   Evidence: System log "Hypervisor launched successfully" at boot, `IsSecureKernelRunning=1`, `LsaIsoLaunchAttempted=1`,
   while `Win32_DeviceGuard.SecurityServicesConfigured = 0`. Set it to `0`.
   Also check `Scenarios\HypervisorEnforcedCodeIntegrity` (Memory integrity) and `Lsa\LsaCfgFlags` (Credential Guard).

Do not stop after 1–3 "because they took effect": verify `HypervisorPresent` every reboot.

## 3. Bad VMware global defaults

`C:\ProgramData\VMware\VMware Workstation\config.ini` applies to **every** VM (shown in vmware.log as `HOST DEFAULTS` / `SITE DEFAULTS`).
Guides for GPU passthrough / ESXi often leave these, and they break macOS:

```ini
hypervisor.cpuid.v0 = "FALSE"
pciPassthru.use64bitMMIO = "TRUE"
pciPassthru.64bitMMIOSizeGB = "32"
pciHole.start = "2048"
pciHole.end = "8192"
```

`pciHole` 2–8 GB overlaps guest RAM (e.g. `memsize = 8192`) → kernel triple fault right after "Firmware has transitioned to runtime".
Remove them with `scripts/clean-vmware-global-config.ps1` (backs up to `config.ini.bak-<timestamp>`), power the VM off first. This was the final fix in the original case.

Also inspect the VM's own `.vmx` for the same keys.

## 4. If it still loops

- Hybrid Intel CPUs (12th–14th gen, P+E cores): reduce `numvcpus` to 4 (`cpuid.coresPerSocket` = same), retry.
- Look for `DarwinPanic` in vmware.log for the actual panic string.
- Confirm the unlocker matches the VMware version (`smc.present = "TRUE"`, `smc.version = "0"`, guestOS `darwin*`).
- AMD hosts need the `cpuid.0.*`/`cpuid.1.*` masks; Intel hosts normally do not.

## 5. Rollback (restore Hyper-V / WSL2 / VBS)

`scripts/restore-hypervisor.ps1` restores the values recorded by the disable script.

Lessons:
- Restore the fast settings first (`bcdedit hypervisorlaunchtype auto`, registry values), then features — so a slow feature step cannot block them.
- `Enable-WindowsOptionalFeature` may try to download payloads from Windows Update (visible in `C:\Windows\Logs\CBS\CBS.log` as `WULib DownloadProgress: [29 / 100]` not moving, and `Get-DeliveryOptimizationStatus` bytes not growing). Use `-LimitAccess` to fail fast instead of hanging; if the payload is missing, reboot first (pending reboot blocks local sources), then retry with working network, or `-Source wim:X:\sources\install.wim:<index> -LimitAccess` from an ISO of the **same build**.
- To abort a stuck download: close the calling PowerShell, kill `DismHost`, kill `TiWorker`. `TrustedInstaller` usually refuses to stop — that is fine; reboot afterwards.

## 6. Unrelated but frequently confused

If an Ubuntu/Linux VM shows `NO-CARRIER` on NAT, check the host services `VMnetDHCP` and `VMware NAT Service` are running — not the guest netplan.
