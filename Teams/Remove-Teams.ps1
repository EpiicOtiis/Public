<# (Remove-Teams.ps1) :: (Revision # 1)/Aaron Pleus, (4/15/2025)

   This script, like all scripts developed by Aaron Pleus, unless otherwise explicitly stated, is the copyrighted property of Aaron Pleus.;
   it may not be shared, sold, or distributed whole or in part, even with modifications applied, for any reason. this includes on reddit, on discord, or as part of other RMM tools.
   	
   The moment you edit this script it becomes your own risk and Aaron Pleus will not provide assistance with it.#>

# Stop Teams processes
Get-Process -Name "Teams" -ErrorAction SilentlyContinue | Stop-Process -Force

# Remove Teams Machine-Wide Installer
$machineWide = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -eq "Teams Machine-Wide Installer" }
if ($machineWide) {
    $machineWide.Uninstall()
    Write-Host "Teams Machine-Wide Installer removed."
} else {
    Write-Host "Teams Machine-Wide Installer not found."
}

# Remove Teams from all user profiles
$users = Get-ChildItem -Path "C:\Users" -Directory
foreach ($user in $users) {
    $teamsPath = "$($user.FullName)\AppData\Local\Microsoft\Teams"
    if (Test-Path "$teamsPath\Current\Teams.exe") {
        Write-Host "Uninstalling Teams for user: $($user.Name)"
        Start-Process -FilePath "$teamsPath\Update.exe" -ArgumentList "--uninstall /s" -Wait -NoNewWindow
    }
}

# Clean up Teams folders
$teamsFolders = Get-ChildItem -Path "C:\Users\*\AppData\Local\Microsoft\Teams" -Directory -ErrorAction SilentlyContinue
foreach ($folder in $teamsFolders) {
    Remove-Item -Path $folder.FullName -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Removed Teams folder: $folder"
}