<# (WinGet_Uninstaller_V1) :: (Revision # 1)/Aaron Pleus, (10/09/2025)

   This script, like all scripts developed by Aaron Pleus, unless otherwise explicitly stated, is the copyrighted property of Aaron Pleus/Integris IT.;
   it may not be shared, sold, or distributed whole or in part, even with modifications applied, for any reason. this includes on reddit, on discord, or as part of other RMM tools.
   	
   The moment you edit this script it becomes your own risk and Aaron Pleus/Integris IT will not provide assistance with it.#>

# WebClient Configuration
$dc = New-Object net.webclient
$dc.UseDefaultCredentials = $true
$dc.Headers.Add("user-agent", "Internet Explorer")
$dc.Headers.Add("X-FORMS_BASED_AUTH_ACCEPTED", "f")

# Temporary Installer Directory Configuration
$InstallerFolder = Join-Path -Path $env:ProgramData -ChildPath 'CustomScripts'
if (-not (Test-Path -Path $InstallerFolder)) {
    New-Item -Path $InstallerFolder -ItemType Directory -Force -Confirm:$false -Verbose
}

# Check if Winget is installed
Write-Host "Checking if Winget is installed" -ForegroundColor Yellow
$TestWinget = Get-AppxProvisionedPackage -Online | Where-Object {$_.DisplayName -eq "Microsoft.DesktopAppInstaller"}

# If Winget is not installed or version is too old, download and install Winget
# Note: The version check here is for the App Installer package, not necessarily the winget CLI version itself.
# Modern versions of Winget usually come with Windows updates.
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

# --- Section for Listing and Uninstalling Software ---

Write-Host "`n--- Listing Installed Winget Packages ---" -ForegroundColor Cyan
Write-Host "Below is a list of packages Winget can manage. Note the 'Id' or 'Name' of the software you wish to uninstall." -ForegroundColor DarkCyan

# Run 'winget list' and capture its output
# Using --accept-source-agreements here just in case, though it might not be strictly necessary for 'list'
$InstalledPackagesRaw = (& ".\winget.exe" list --source winget --accept-source-agreements)

if ($InstalledPackagesRaw) {
    # Display the list to the user
    $InstalledPackagesRaw | ForEach-Object { Write-Host $_ }
    Write-Host "-------------------------------------`n" -ForegroundColor DarkCyan

    # Prompt the user for the package to uninstall
    $PackageToUninstall = Read-Host "Enter the 'Id' or 'Name' of the package you want to uninstall (or press Enter to skip uninstallation)"

    if (-not [string]::IsNullOrWhiteSpace($PackageToUninstall)) {
        Write-Host "Attempting to uninstall '$PackageToUninstall'..." -ForegroundColor Yellow
        Try {
            # Execute the uninstall command
            # Removed '--accept-package-agreements' as it's not supported by winget uninstall v1.11.510
            # Kept '--accept-source-agreements' as it's a generally safe flag and might be supported for some uninstall scenarios
            & ".\winget.exe" uninstall "$PackageToUninstall" -e --accept-source-agreements -h
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

# Countdown for 30 seconds
Write-Host "`n" # Add a newline for better readability before the countdown
for ($i = 30; $i -gt 0; $i--) {
    Write-Host "`rTask completed. This window will close in $i seconds." -NoNewline
    Start-Sleep -Seconds 1
}
Write-Host ""  # To add a newline at the end