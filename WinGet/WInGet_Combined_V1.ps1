<# (WinGet_Combined_V1) :: (Revision # 1)/Aaron Pleus, (10/09/2025)

   This script, like all scripts developed by Aaron Pleus, unless otherwise explicitly stated, is the copyrighted property of Aaron Pleus/Integris IT.;
   it may not be shared, sold, or distributed whole or in part, even with modifications applied, for any reason. this includes on reddit, on discord, or as part of other RMM tools.

   The moment you edit this script it becomes your own risk and Aaron Pleus/Integris IT will not provide assistance with it.#>

# WebClient Configuration
$dc = New-Object net.webclient
$dc.UseDefaultCredentials = $true
$dc.Headers.Add("user-agent", "Internet Explorer")
$dc.Headers.Add("X-FORMS_BASED_AUTH_ACCEPTED", "f")

# Fix console encoding for winget output
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$env:TERM = "dumb"

# Temporary Installer Directory Configuration
$InstallerFolder = Join-Path -Path $env:ProgramData -ChildPath 'CustomScripts'
if (-not (Test-Path -Path $InstallerFolder)) {
    New-Item -Path $InstallerFolder -ItemType Directory -Force -Confirm:$false -Verbose
}

# Check if Winget is installed
Write-Host "Checking if Winget is installed" -ForegroundColor Yellow
$TestWinget = Get-AppxProvisionedPackage -Online | Where-Object {$_.DisplayName -eq "Microsoft.DesktopAppInstaller"}

# If Winget is not installed or version is too old, download and install Winget
if (-not $TestWinget -or ([Version]$TestWinget.Version -le [Version]"2022.506.16.0")) {
    # Download Winget MSIXBundle
    Write-Host "WinGet is not installed or needs update. Downloading WinGet..."
    $WinGetURL = "https://aka.ms/getwinget"
    Try {
        $dc.DownloadFile($WinGetURL, "$InstallerFolder\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle")
        Write-Host "Downloaded WinGet MSIXBundle." -ForegroundColor Green

        # Install WinGet MSIXBundle
        Write-Host "Installing MSIXBundle for App Installer..."
        Add-AppxProvisionedPackage -Online -PackagePath "$InstallerFolder\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" -SkipLicense
        Write-Host "Installed MSIXBundle for App Installer" -ForegroundColor Green
    }
    Catch {
        Write-Host "Failed to download or install MSIXBundle for App Installer. Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}
else {
    Write-Host "WinGet is Installed and up to date." -ForegroundColor Green
}

# Find the winget.exe file
$WingetPath = $null
$ResolveWingetPath = Get-ChildItem -Path "C:\Program Files\WindowsApps\" -Filter "winget.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName | Where-Object { $_ -like "*Microsoft.DesktopAppInstaller_*" }

if ($ResolveWingetPath) {
    $WingetPath = $ResolveWingetPath | Select-Object -Last 1
    Write-Host "Found winget.exe at: $WingetPath" -ForegroundColor Green
} else {
    Write-Host "Failed to find winget.exe. Please ensure it's installed correctly." -ForegroundColor Red
    # Exit if winget.exe is not found
    exit 1
}

# Get the directory of winget.exe
$WingetExeDirectory = Split-Path -Path $WingetPath -Parent
Set-Location -Path $WingetExeDirectory

# --- Main Loop for Actions ---
$continueActions = $true
while ($continueActions) {
    Write-Host "`nWhat would you like to do?" -ForegroundColor Yellow
    Write-Host "1. Update Applications" -ForegroundColor White
    Write-Host "2. Uninstall Applications" -ForegroundColor White
    Write-Host "3. Exit" -ForegroundColor White
    $UserChoice = Read-Host "Enter your choice (1, 2, or 3)"

    switch ($UserChoice) {
        "1" {
            # --- Section for Listing and Updating Software ---
            Write-Host "`n--- Checking for Available Winget Updates ---" -ForegroundColor Cyan
            Write-Host "Below is a list of applications with available updates. Note the 'Id' or 'Name' of the software you wish to update." -ForegroundColor DarkCyan

            # Run 'winget upgrade' to list available updates
            $AvailableUpdatesRaw = & ".\winget.exe" upgrade --source winget --accept-source-agreements --disable-interactivity 2>&1 | Out-String -Stream | Where-Object { $_ -and $_ -notmatch '^\s*[-\\/|─]' }

            if ($AvailableUpdatesRaw) {
                # Display the list to the user
                $AvailableUpdatesRaw | ForEach-Object { Write-Host $_ }
                Write-Host "-------------------------------------`n" -ForegroundColor DarkCyan

                # Prompt the user for the package to update
                $PackageToUpdate = Read-Host "Enter the 'Id' or 'Name' of the package you want to update (or press Enter to skip updates)"

                if (-not [string]::IsNullOrWhiteSpace($PackageToUpdate)) {
                    Write-Host "Attempting to update '$PackageToUpdate'..." -ForegroundColor Yellow
                    Try {
                        # Execute the update command
                        & ".\winget.exe" upgrade "$PackageToUpdate" -e --accept-source-agreements -h --disable-interactivity
                        Write-Host "Successfully initiated update for '$PackageToUpdate'." -ForegroundColor Green
                    }
                    Catch {
                        Write-Host "Failed to update '$PackageToUpdate'. Error: $($_.Exception.Message)" -ForegroundColor Red
                        Write-Host "Ensure the package ID/name is correct and an update is available." -ForegroundColor Red
                    }
                } else {
                    Write-Host "No package specified for update. Skipping updates." -ForegroundColor Yellow
                }
            } else {
                Write-Host "No Winget packages with available updates found." -ForegroundColor Green
            }
        }
        "2" {
            # --- Section for Listing and Uninstalling Software ---
            Write-Host "`n--- Listing Installed Winget Packages ---" -ForegroundColor Cyan
            Write-Host "Below is a list of packages Winget can manage. Note the 'Id' or 'Name' of the software you wish to uninstall." -ForegroundColor DarkCyan

            # Run 'winget list' and capture its output
            $InstalledPackagesRaw = & ".\winget.exe" list --source winget --accept-source-agreements --disable-interactivity 2>&1 | Out-String -Stream | Where-Object { $_ -and $_ -notmatch '^\s*[-\\/|─]' }

            if ($InstalledPackagesRaw) {
                # Display the list to the user
                $InstalledPackagesRaw | ForEach-Object { Write-Host $_ }
                Write-Host "-------------------------------------`n" -ForegroundColor DarkCyan

                # Prompt the user for the package to uninstall
                $PackageToUninstall = Read-Host "Enter the 'Id' or 'Name' of the package you want to uninstall (or press Enter to skip uninstallation)"

                if (-not [string]::IsNullOrWhiteSpace($PackageToUninstall)) {
                    Write-Host "Attempting to uninstall '$PackageToUninstall'..." -ForegroundColor Yellow
                    Try {
                        & ".\winget.exe" uninstall "$PackageToUninstall" -e --accept-source-agreements -h --disable-interactivity
                        Write-Host "Successfully initiated uninstall for '$PackageToUninstall'." -ForegroundColor Green
                    }
                    Catch {
                        Write-Host "Failed to uninstall '$PackageToUninstall'. Error: $($_.Exception.Message)" -ForegroundColor Red
                        Write-Host "Ensure the package ID/name is correct and the software is installed via Winget or recognized by it." -ForegroundColor Red
                    }
                } else {
                    Write-Host "No package specified for uninstallation. Skipping uninstallation." -ForegroundColor Yellow
                }
            } else {
                Write-Host "Could not retrieve list of installed Winget packages." -ForegroundColor Red
            }
        }
        "3" {
            Write-Host "Exiting script." -ForegroundColor Yellow
            $continueActions = $false # Set to false to break out of the while loop
        }
        Default {
            Write-Host "Invalid choice. Please enter 1, 2, or 3." -ForegroundColor Red
        }
    }

    # If the user chose to exit, the loop will terminate.
    # Otherwise, ask if they want to perform another action.
    if ($continueActions) {
        $anotherAction = Read-Host "Do you want to perform another action (update/uninstall)? (Y/N)"
        if ($anotherAction -notmatch "^[yY]") {
            $continueActions = $false
        }
    }
}

# Countdown for 30 seconds (only reached after the loop exits)
Write-Host "`n" # Add a newline for better readability before the countdown
for ($i = 30; $i -gt 0; $i--) {
    Write-Host "`rTask completed. This window will close in $i seconds." -NoNewline
    Start-Sleep -Seconds 1
}
Write-Host ""  # To add a newline at the end