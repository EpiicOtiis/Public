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
$LogPath = "C:\ProgramData\VMwareToolsUninstall.log"

# --- FUNCTIONS ---

function Write-UninstallLog {
    param (
        [string]$Message,
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] [$Level] $Message"
    
    try {
        Add-Content -Path $LogPath -Value $logEntry -ErrorAction Stop
    } catch {
        Write-Host $logEntry
    }
}

function Test-VMwareToolsInstalled {
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    $tools = Get-ChildItem $regPath -ErrorAction SilentlyContinue | 
        Get-ItemProperty -ErrorAction SilentlyContinue | 
        Where-Object { $_.DisplayName -match "VMware Tools" }
    
    return $null -ne $tools
}

function Verify-UninstallSuccess {
    Start-Sleep -Seconds 5
    
    if (Test-VMwareToolsInstalled) {
        Write-UninstallLog "VMware Tools is still installed after uninstall attempt." -Level 'WARNING'
        return $false
    } else {
        Write-UninstallLog "VMware Tools successfully uninstalled." -Level 'SUCCESS'
        return $true
    }
}

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
        Write-UninstallLog "Standard uninstall called but VMware Tools not found in registry." -Level 'INFO'
        return
    }

    $Guid = $VMwareRegKey.PSChildName
    Write-Host "Initiating standard silent uninstallation for VMware Tools (GUID: $Guid)..." -ForegroundColor Cyan
    Write-UninstallLog "Starting standard uninstall with GUID: $Guid" -Level 'INFO'
    
    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x $Guid /qn /norestart" -Wait -PassThru
    
    if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
        Write-Host "Standard uninstallation completed successfully. A reboot is required to finish removing drivers." -ForegroundColor Green
        Write-UninstallLog "MSI uninstall process exited with code $($process.ExitCode) (success)." -Level 'INFO'
    } else {
        Write-Host "Uninstallation exited with code $($process.ExitCode). You may need to use -ForceCleanup." -ForegroundColor Red
        Write-UninstallLog "MSI uninstall process exited with code $($process.ExitCode) (failure)." -Level 'ERROR'
    }

    if ($RebootAfter) {
        Write-Host "Rebooting in 60 seconds after uninstall..." -ForegroundColor Cyan
        $isInstalled = Test-VMwareToolsInstalled
        if ($isInstalled) {
            Write-UninstallLog "Uninstall initiated. VMware Tools still present (drivers may still be loaded). Proceeding with reboot." -Level 'INFO'
        } else {
            Write-UninstallLog "Uninstall completed. VMware Tools no longer present in registry. Proceeding with reboot." -Level 'SUCCESS'
        }
        Start-Process 'shutdown.exe' -ArgumentList '/r /f /t 60 /c "Rebooting after VMware Tools uninstall."'
    } else {
        Verify-UninstallSuccess | Out-Null
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
    Write-UninstallLog "Force cleanup completed successfully." -Level 'SUCCESS'

    if ($RebootAfter) {
        Write-Host "Rebooting in 60 seconds after force cleanup..." -ForegroundColor Cyan
        $isInstalled = Test-VMwareToolsInstalled
        if ($isInstalled) {
            Write-UninstallLog "Force cleanup initiated. VMware Tools registry entries still present. Proceeding with reboot." -Level 'WARNING'
        } else {
            Write-UninstallLog "Force cleanup completed. VMware Tools successfully removed from registry and filesystem. Proceeding with reboot." -Level 'SUCCESS'
        }
        Start-Process 'shutdown.exe' -ArgumentList '/r /f /t 60 /c "Rebooting after VMware Tools force cleanup."'
    } else {
        Verify-UninstallSuccess | Out-Null
    }
}

function Invoke-RemoteRebootScheduler {
    Write-Host "Scheduling reboot using One_Time_Reboot_Scheduler..." -ForegroundColor Cyan
    Write-UninstallLog "Invoking remote reboot scheduler." -Level 'INFO'
    try {
        iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Microsoft%20Windows/General%20Troubleshooting/One_Time_Reboot_Scheduler.ps1'))
        Write-UninstallLog "Remote reboot scheduler executed successfully." -Level 'INFO'
    } catch {
        Write-Warning "Failed to invoke the reboot scheduler. Error: $($_.Exception.Message)"
        Write-UninstallLog "Failed to invoke reboot scheduler: $($_.Exception.Message)" -Level 'ERROR'
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
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest

    $task = Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal
    
    Write-UninstallLog "Startup task '$taskName' registered successfully." -Level 'INFO'
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
    Write-Host "" -ForegroundColor Cyan
    Write-Host "Progress Details:" -ForegroundColor Cyan
    Write-Host "  - Task Name: VMWareToolsScheduledUninstall" -ForegroundColor Cyan
    Write-Host "  - Task History: Check Task Scheduler for execution details" -ForegroundColor Cyan
    Write-Host "  - Uninstall Log: $LogPath" -ForegroundColor Cyan
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

Write-Host "VMware Tools Management Script" -ForegroundColor Cyan
Write-Host "Uninstall logs are written to: $LogPath" -ForegroundColor Yellow

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