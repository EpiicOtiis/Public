<# (Remove-Teams.ps1) :: (Revision # 2)/Aaron Pleus, (4/15/2025)

   This script, like all scripts developed by Aaron Pleus, unless otherwise explicitly stated, is the copyrighted property of Aaron Pleus.;
   it may not be shared, sold, or distributed whole or in part, even with modifications applied, for any reason. this includes on reddit, on discord, or as part of other RMM tools.
       
   The moment you edit this script it becomes your own risk and Aaron Pleus will not provide assistance with it.#>

# Stop Teams processes
Get-Process -Name "Teams" -ErrorAction SilentlyContinue | Stop-Process -Force

# Remove Teams Machine-Wide Installer
$machineWide = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -eq "Teams Machine-Wide Installer" }
if ($machineWide) {
    try {
        $machineWide.Uninstall()
        Write-Host "Teams Machine-Wide Installer removed."
    } catch {
        Write-Host "Failed to remove Teams Machine-Wide Installer: $_"
    }
} else {
    Write-Host "Teams Machine-Wide Installer not found."
}

# Remove Teams from all user profiles
$users = Get-ChildItem -Path "C:\Users" -Directory
foreach ($user in $users) {
    $teamsPath = "$($user.FullName)\AppData\Local\Microsoft\Teams"
    $updateExePath = "$teamsPath\Update.exe"
    if (Test-Path "$teamsPath\Current\Teams.exe" -and (Test-Path $updateExePath)) {
        Write-Host "Uninstalling Teams for user: $($user.Name)"
        try {
            Start-Process -FilePath $updateExePath -ArgumentList "--uninstall /s" -Wait -NoNewWindow
        } catch {
            Write-Host "Failed to uninstall Teams for user $($user.Name): $_"
        }
    } else {
        Write-Host "Teams executable or Update.exe not found for user: $($user.Name)"
    }
}

# Clean up Teams folders
$teamsFolders = Get-ChildItem -Path "C:\Users\*\AppData\Local\Microsoft\Teams" -Directory -ErrorAction SilentlyContinue
foreach ($folder in $teamsFolders) {
    try {
        Remove-Item -Path $folder.FullName -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "Removed Teams folder: $folder"
    } catch {
        Write-Host "Failed to remove Teams folder: $folder. Error: $_"
    }
}