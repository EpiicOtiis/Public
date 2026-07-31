# ==============================================================================
# Script: Deploy-YubiKeyMinidriver-Dynamic.ps1
# Purpose: Automatically queries Yubico for the latest Minidriver version, 
#          downloads the newest MSI, and schedules a 2 AM reboot if upgraded.
#          Logs each run to a timestamped file and prunes logs > 30 days old.
# ==============================================================================

$tempDir = "C:\temp\yk-deployment"
$requiresReboot = $false

# 1. Setup Logging - Create folder if it doesn't exist
if (!(Test-Path $tempDir)) {
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
}

# Prune logs older than 30 days
Get-ChildItem "$tempDir\ykdeploy-*.log" -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
    Remove-Item -Force -ErrorAction SilentlyContinue

# Start logging with a date-stamped file
$LogFile = "$tempDir\ykdeploy-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
Start-Transcript -Path $LogFile
Write-Output "==== YubiKey Minidriver script started: $(Get-Date) ===="

try {
    # 2. Dynamically query Yubico for the latest version number
    Write-Output "Querying Yubico for the latest Minidriver version..."
    $targetVersion = $null

    # Force TLS 1.2 for the SYSTEM account to prevent connection rejections
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    
    $html = Invoke-WebRequest -Uri "https://www.yubico.com/support/download/smart-card-drivers-tools/" -UseBasicParsing -ErrorAction Stop
    $match = [regex]::Match($html.Content, 'YubiKey-Minidriver\s*([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)')
    
    if ($match.Success) {
        $targetVersion = $match.Groups[1].Value
        Write-Output "Yubico's latest version is: $targetVersion"
    } else {
        Write-Output "WARNING: Failed to locate version string on Yubico website. Exiting to prevent unnecessary downloads."
        Write-Output "==== YubiKey Minidriver script completed: $(Get-Date) ===="
        Stop-Transcript
        Exit
    }

    # 3. Check current installed version
    $installedDriver = Get-ChildItem -Path @('HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall') -ErrorAction SilentlyContinue | 
                       Get-ItemProperty -ErrorAction SilentlyContinue | 
                       Where-Object { $_.DisplayName -match "YubiKey Smart Card Minidriver" } | 
                       Select-Object -First 1

    $needsUpdate = $false

    if ($installedDriver) {
        $installedVersion = $installedDriver.DisplayVersion
        if ([version]$installedVersion -lt [version]$targetVersion) {
            Write-Output "Minidriver is outdated (Installed: $installedVersion). Proceeding with upgrade."
            $needsUpdate = $true
        } else {
            Write-Output "Minidriver is up to date (Version $installedVersion). No action required."
        }
    } else {
        Write-Output "Minidriver is not installed. Proceeding with installation."
        $needsUpdate = $true
    }

    # 4. Download and Install
    if ($needsUpdate) {
        $is64Bit = [Environment]::Is64BitOperatingSystem
        $downloadUrl = if ($is64Bit) { 
            "https://downloads.yubico.com/support/YubiKey-Minidriver-latest-x64.msi" 
        } else { 
            "https://downloads.yubico.com/support/YubiKey-Minidriver-latest-x86.msi" 
        }
        
        $installerPath = "$tempDir\YubiKey-Minidriver-$targetVersion.msi"
        
        Write-Output "Downloading latest MSI from $downloadUrl..."
        Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing -ErrorAction Stop
        
        Write-Output "Installing silently..."
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$installerPath`" /qn /norestart /l*v `"$tempDir\msi-install.log`"" -Wait -NoNewWindow -PassThru
        
        if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
            Write-Output "SUCCESS: Installation complete."
            $requiresReboot = $true
        } else {
            Write-Output "WARNING: Installation failed with exit code $($process.ExitCode)."
        }
    }

    # 5. Schedule Reboot
    if ($requiresReboot) {
        $taskName = "YubiKey-Minidriver-Reboot"
        $now = Get-Date
        $rebootTime = Get-Date -Hour 2 -Minute 0 -Second 0
        
        # If it is already past 2 AM, schedule for the next day
        if ($now -ge $rebootTime) {
            $rebootTime = $rebootTime.AddDays(1)
        }
        
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        
        $action = New-ScheduledTaskAction -Execute "shutdown.exe" -Argument "/r /t 0 /f /c `"A scheduled reboot is required to complete the YubiKey Minidriver update.`""
        $trigger = New-ScheduledTaskTrigger -Once -At $rebootTime
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -User "NT AUTHORITY\SYSTEM" -RunLevel Highest -Force | Out-Null
        
        Write-Output "Reboot successfully scheduled for $rebootTime."
    }

} catch {
    Write-Output "ERROR: $_"
}

Write-Output "==== YubiKey Minidriver script completed: $(Get-Date) ===="
Stop-Transcript