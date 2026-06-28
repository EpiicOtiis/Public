# Synopsis:
#   A unified Winget helper script that can install, update, list, or uninstall
#   applications via interactive prompts or command-line arguments.
#
#   Command-line usage:
#     .\WinGet_Combined_V1.ps1 /updateall
#     .\WinGet_Combined_V1.ps1 /uninstall <PackageIdOrName>
#     .\WinGet_Combined_V1.ps1 /list
#     .\WinGet_Combined_V1.ps1 /help
#
#   If no arguments are provided, the script starts in interactive mode.
#
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

function Show-Usage {
    Write-Host "Usage:" -ForegroundColor Yellow
    Write-Host "  .\WinGet_Combined_V1.ps1 /updateall" -ForegroundColor White
    Write-Host "  .\WinGet_Combined_V1.ps1 /uninstall <PackageIdOrName>" -ForegroundColor White
    Write-Host "  .\WinGet_Combined_V1.ps1 /list" -ForegroundColor White
    Write-Host "  .\WinGet_Combined_V1.ps1" -ForegroundColor White
    Write-Host "" -ForegroundColor White
    Write-Host "If no arguments are provided, the script runs in interactive mode." -ForegroundColor DarkCyan
}

function List-InstalledPackages {
    Write-Host "`n--- Installed Winget Packages ---" -ForegroundColor Cyan
    try {
        $installedPackages = & $WingetPath list --source winget --accept-source-agreements --disable-interactivity 2>&1 | Out-String -Stream | Where-Object { $_ -and $_ -notmatch '^\s*[-\\/|─]' }
        if ($installedPackages) {
            $installedPackages | ForEach-Object { Write-Host $_ }
        } else {
            Write-Host "No installed packages were returned by Winget." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "Failed to list installed packages. Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Update-AllPackages {
    Write-Host "`n--- Updating All Available Winget Packages ---" -ForegroundColor Cyan
    try {
        & $WingetPath upgrade --all -e --accept-source-agreements -h --disable-interactivity
        Write-Host "Winget upgrade --all completed." -ForegroundColor Green
    } catch {
        Write-Host "Failed to update all packages. Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Uninstall-Package {
    param (
        [Parameter(Mandatory = $true)]
        [string]$PackageId
    )

    Write-Host "`n--- Uninstalling $PackageId ---" -ForegroundColor Cyan
    try {
        & $WingetPath uninstall $PackageId -e --accept-source-agreements -h --disable-interactivity
        Write-Host "Uninstall command initiated for '$PackageId'." -ForegroundColor Green
    } catch {
        Write-Host "Failed to uninstall '$PackageId'. Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Command-line argument handling
if ($args.Count -gt 0) {
    $command = $args[0].TrimStart('/','-').ToLower()
    switch ($command) {
        'updateall' {
            Update-AllPackages
            exit 0
        }
        'uninstall' {
            if ($args.Count -lt 2 -or [string]::IsNullOrWhiteSpace($args[1])) {
                Write-Host "Missing package ID or name for uninstall." -ForegroundColor Red
                Show-Usage
                exit 1
            }
            $packageId = $args[1..($args.Count - 1)] -join ' '
            Uninstall-Package -PackageId $packageId
            exit 0
        }
        'list' {
            List-InstalledPackages
            exit 0
        }
        'help' {
            Show-Usage
            exit 0
        }
        '?' {
            Show-Usage
            exit 0
        }
        Default {
            Write-Host "Unknown argument: $($args[0])" -ForegroundColor Red
            Show-Usage
            exit 1
        }
    }
}

# --- Main Loop for Actions ---
$continueActions = $true
while ($continueActions) {
    Write-Host "`nWhat would you like to do?" -ForegroundColor Yellow
    Write-Host "1. Update Applications" -ForegroundColor White
    Write-Host "2. Uninstall Applications" -ForegroundColor White
    Write-Host "3. Install Applications" -ForegroundColor White
    Write-Host "4. Exit" -ForegroundColor White
    $UserChoice = Read-Host "Enter your choice (1, 2, 3, or 4)"

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
            # --- Section for Installing Software ---
            Write-Host "`n--- Installing Winget Package ---" -ForegroundColor Cyan
            Write-Host "Enter the package ID or Name you wish to install." -ForegroundColor DarkCyan

            # Prompt the user for the package to install
            $PackageToInstall = Read-Host "Enter the 'Id' or 'Name' of the package you want to install (or press Enter to skip installation)"

            if (-not [string]::IsNullOrWhiteSpace($PackageToInstall)) {
                Write-Host "Attempting to install '$PackageToInstall'..." -ForegroundColor Yellow
                Try {
                    & ".\winget.exe" install "$PackageToInstall" -e --accept-source-agreements -h --disable-interactivity
                    Write-Host "Successfully initiated install for '$PackageToInstall'." -ForegroundColor Green
                }
                Catch {
                    Write-Host "Failed to install '$PackageToInstall'. Error: $($_.Exception.Message)" -ForegroundColor Red
                    Write-Host "Ensure the package ID/name is correct and available in Winget." -ForegroundColor Red
                }
            } else {
                Write-Host "No package specified for installation. Skipping installation." -ForegroundColor Yellow
            }
        }
        "4" {
            Write-Host "Exiting script." -ForegroundColor Yellow
            $continueActions = $false # Set to false to break out of the while loop
        }
        Default {
            Write-Host "Invalid choice. Please enter 1, 2, 3, or 4." -ForegroundColor Red
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