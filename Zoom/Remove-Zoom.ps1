<# (Remove-Zoom.ps1) :: (Revision # 1)/Aaron Pleus, (4/22/2025)

   This script, like all scripts developed by Aaron Pleus, unless otherwise explicitly stated, is the copyrighted property of Aaron Pleus.;
   it may not be shared, sold, or distributed whole or in part, even with modifications applied, for any reason. this includes on reddit, on discord, or as part of other RMM tools.
   	
   The moment you edit this script it becomes your own risk and Aaron Pleus will not provide assistance with it.#>

# PowerShell script to uninstall Zoom from user AppData and clean up residuals
# Checks all user profiles for Zoom in AppData and removes it

# Run as administrator
#Requires -RunAsAdministrator

# Function to log actions
function Write-Log {
    param($Message)
    $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): $Message"
    Write-Output $logMessage
}

# Function to uninstall Zoom from a specific user's AppData
function Remove-ZoomFromUserAppData {
    param($UserProfilePath)
    
    $zoomAppDataPath = Join-Path $UserProfilePath "AppData\Roaming\Zoom"
    $zoomUninstaller = Join-Path $zoomAppDataPath "bin\Uninstall.exe"
    
    if (Test-Path $zoomAppDataPath) {
        Write-Log "Found Zoom installation in $zoomAppDataPath"
        
        # Check for uninstaller
        if (Test-Path $zoomUninstaller) {
            Write-Log "Running Zoom uninstaller from $zoomUninstaller"
            try {
                # Run uninstaller silently
                Start-Process -FilePath $zoomUninstaller -ArgumentList "/quiet" -Wait -ErrorAction Stop
                Write-Log "Zoom uninstaller executed successfully"
            }
            catch {
                Write-Log "Error running uninstaller: $($_.Exception.Message)"
            }
        }
        else {
            Write-Log "No uninstaller found in $zoomAppDataPath"
        }
        
        # Clean up residual files
        Write-Log "Removing Zoom AppData folder: $zoomAppDataPath"
        try {
            Remove-Item -Path $zoomAppDataPath -Recurse -Force -ErrorAction Stop
            Write-Log "Successfully removed Zoom AppData folder"
        }
        catch {
            Write-Log "Error removing Zoom AppData folder: $($_.Exception.Message)"
        }
    }
}

# Main script
Write-Log "Starting Zoom AppData cleanup script"

# Get all user profiles
$profilesPath = "C:\Users"
$profiles = Get-ChildItem -Path $profilesPath -Directory -ErrorAction SilentlyContinue

foreach ($profile in $profiles) {
    Write-Log "Checking profile: $($profile.FullName)"
    Remove-ZoomFromUserAppData -UserProfilePath $profile.FullName
}

# Check for Zoom in current user's AppData
Write-Log "Checking current user's AppData"
Remove-ZoomFromUserAppData -UserProfilePath $env:USERPROFILE

Write-Log "Zoom AppData cleanup completed"