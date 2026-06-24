<#
.SYNOPSIS
    Locally checks the health of VMware Tools or uninstalls it completely from a Windows machine.

.DESCRIPTION
    This script is designed for post-migration cleanup or local monitoring. It does not require PowerCLI.
    It can gracefully uninstall VMware Tools via its MSI GUID, or forcefully rip it out if the installer is broken.

.EXAMPLE
    .\Manage-VMwareTools.ps1 -CheckHealth
    Checks if VMware Tools is installed, its version, and if its services are running.

.EXAMPLE
    .\Manage-VMwareTools.ps1 -Uninstall
    Performs a clean, silent uninstallation of VMware Tools and suppresses the reboot.

.EXAMPLE
    .\Manage-VMwareTools.ps1 -Uninstall -ForceCleanup
    Aggressively deletes VMware Tools files, services, and registry keys if the standard uninstall fails.
#>

[CmdletBinding(DefaultParameterSetName='Check')]
param (
    [Parameter(ParameterSetName='Check')]
    [switch]$CheckHealth,

    [Parameter(ParameterSetName='Remove')]
    [switch]$Uninstall,

    [Parameter(ParameterSetName='Remove')]
    [switch]$ForceCleanup,

    [Parameter(ParameterSetName='Remove')]
    [switch]$RebootAfter
)

# --- GLOBAL VARIABLES ---
$RegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
$VMwareRegKey = Get-ChildItem $RegPath -ErrorAction SilentlyContinue | 
                Get-ItemProperty -ErrorAction SilentlyContinue | 
                Where-Object { $_.DisplayName -match "VMware Tools" }

$VMwareServices = @("VMTools", "VGAuthService")

# --- FUNCTIONS ---

function Get-VMwareToolsHealth {
    Write-Host "--- VMware Tools Health Report ---" -ForegroundColor Cyan
    
    if ($VMwareRegKey) {
        Write-Host "Status: Installed" -ForegroundColor Green
        Write-Host "Version: $($VMwareRegKey.DisplayVersion)"
        Write-Host "Install Date: $($VMwareRegKey.InstallDate)"
        Write-Host "MSI GUID: $($VMwareRegKey.PSChildName)"
        
        Write-Host "`nService Status:" -ForegroundColor Cyan
        foreach ($svc in $VMwareServices) {
            $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
            if ($service) {
                if ($service.Status -eq "Running") {
                    Write-Host "  [OK] $($svc) is $($service.Status)" -ForegroundColor Green
                } else {
                    Write-Host "  [WARNING] $($svc) is $($service.Status)" -ForegroundColor Yellow
                }
            } else {
                Write-Host "  [ERROR] $($svc) service is missing!" -ForegroundColor Red
            }
        }
    } else {
        Write-Host "Status: Not Installed (or cannot be found in the registry)." -ForegroundColor Yellow
    }
    Write-Host "----------------------------------`n" -ForegroundColor Cyan
}

function Invoke-StandardUninstall {
    param (
        [switch]$RebootAfter
    )

    if (-not $VMwareRegKey) {
        Write-Host "VMware Tools does not appear to be installed via MSI. Nothing to gracefully uninstall." -ForegroundColor Yellow
        return
    }

    $Guid = $VMwareRegKey.PSChildName
    Write-Host "Initiating standard silent uninstallation for VMware Tools (GUID: $Guid)..." -ForegroundColor Cyan
    
    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x $Guid /qn /norestart" -Wait -PassThru
    
    if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
        Write-Host "Standard uninstallation completed successfully. A reboot is required to finish removing drivers." -ForegroundColor Green
    } else {
        Write-Host "Uninstallation exited with code $($process.ExitCode). You may need to use -ForceCleanup." -ForegroundColor Red
    }

    if ($RebootAfter) {
        Write-Host "Rebooting in 60 seconds after uninstall..." -ForegroundColor Cyan
        Start-Process 'shutdown.exe' -ArgumentList '/r /f /t 60 /c "Rebooting after VMware Tools uninstall."'
    }
}

function Invoke-ForceCleanup {
    param (
        [switch]$RebootAfter
    )

    Write-Warning "Initiating Force Cleanup! This will forcefully delete services, files, and registry keys."
    
    Write-Host "Killing VMware processes..."
    Get-Process -Name "vmtoolsd" -ErrorAction SilentlyContinue | Stop-Process -Force

    Write-Host "Stopping and removing VMware services..."
    $allVMServices = Get-Service -DisplayName "VMware*" -ErrorAction SilentlyContinue
    foreach ($svc in $allVMServices) {
        Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
        & sc.exe delete $($svc.Name) | Out-Null
    }

    Write-Host "Cleaning up Registry keys..."
    $RegTargets = @(
        "HKLM:\SOFTWARE\VMware, Inc.",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$($VMwareRegKey.PSChildName)"
    )
    foreach ($reg in $RegTargets) {
        if (Test-Path $reg) {
            Remove-Item -Path $reg -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Host "Deleting Program Files directories..."
    $FolderTargets = @(
        "C:\Program Files\VMware\VMware Tools",
        "C:\ProgramData\VMware\VMware Tools"
    )
    foreach ($folder in $FolderTargets) {
        if (Test-Path $folder) {
            Remove-Item -Path $folder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Host "Force cleanup complete. A system reboot is highly recommended." -ForegroundColor Green

    if ($RebootAfter) {
        Write-Host "Rebooting in 60 seconds after force cleanup..." -ForegroundColor Cyan
        Start-Process 'shutdown.exe' -ArgumentList '/r /f /t 60 /c "Rebooting after VMware Tools force cleanup."'
    }
}

function Invoke-RemoteRebootScheduler {
    Write-Host "Scheduling reboot using One_Time_Reboot_Scheduler..." -ForegroundColor Cyan
    try {
        iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Microsoft%20Windows/General%20Troubleshooting/One_Time_Reboot_Scheduler.ps1'))
    } catch {
        Write-Warning "Failed to invoke the reboot scheduler. Error: $($_.Exception.Message)"
    }
}

function Register-UninstallOnStartupTask {
    param (
        [switch]$ForceCleanup,
        [switch]$RebootAfter
    )

    $taskName = 'VMWareToolsScheduledUninstall'
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }

    $scriptPath = $MyInvocation.MyCommand.Path
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -Uninstall"
    if ($ForceCleanup) { $arguments += ' -ForceCleanup' }
    if ($RebootAfter) { $arguments += ' -RebootAfter' }

    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arguments
    $trigger = New-ScheduledTaskTrigger -AtStartup -Delay (New-TimeSpan -Minutes 1)
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal
}

function Invoke-ScheduledUninstall {
    param (
        [switch]$ForceCleanup
    )

    $forceText = if ($ForceCleanup) { 'Force cleanup' } else { 'Standard uninstall' }
    Register-UninstallOnStartupTask -ForceCleanup:$ForceCleanup -RebootAfter
    Invoke-RemoteRebootScheduler

    Write-Host "A startup task has been created to run the $forceText after reboot." -ForegroundColor Cyan
    Write-Host "Once the machine reboots, VMware Tools uninstall will run automatically, and the system will reboot again afterward." -ForegroundColor Cyan
}

# --- EXECUTION LOGIC ---

function Show-VMwareToolsMenu {
    while ($true) {
        Clear-Host
        Write-Host '=== VMware Tools Management Menu ===' -ForegroundColor Cyan
        Write-Host '1) Check VMware Tools health'
        Write-Host '2) Standard uninstall VMware Tools'
        Write-Host '3) Force cleanup VMware Tools'
        Write-Host '4) Schedule uninstall VMware Tools'
        Write-Host '5) Exit'
        $choice = Read-Host 'Select an option [1-5]'

        switch ($choice) {
            '1' {
                Get-VMwareToolsHealth
                Read-Host 'Press Enter to continue...'
            }
            '2' {
                Invoke-StandardUninstall
                Read-Host 'Press Enter to continue...'
            }
            '3' {
                Invoke-ForceCleanup
                Read-Host 'Press Enter to continue...'
            }
            '4' {
                $forceCleanupChoice = Read-Host 'Run force cleanup after reboot? (y/n)'
                if ($forceCleanupChoice -and $forceCleanupChoice.ToLower() -eq 'y') {
                    Invoke-ScheduledUninstall -ForceCleanup
                } else {
                    Invoke-ScheduledUninstall
                }
                Read-Host 'Press Enter to continue...'
            }
            '5' {
                Write-Host 'Exiting.' -ForegroundColor Cyan
                return
            }
            default {
                Write-Warning 'Invalid selection. Please enter 1, 2, 3, 4, or 5.'
                Read-Host 'Press Enter to continue...'
            }
        }
    }
}

# Request Admin privileges (Required for uninstall and service checking)
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "This script requires Administrator privileges. Please run PowerShell as Administrator."
    Exit
}

if ($PSBoundParameters.Count) {
    if ($CheckHealth) {
        Get-VMwareToolsHealth
    }

    if ($Uninstall) {
        if ($ForceCleanup) {
            Invoke-ForceCleanup -RebootAfter:$RebootAfter
        } else {
            Invoke-StandardUninstall -RebootAfter:$RebootAfter
        }
    }
} else {
    Show-VMwareToolsMenu
}