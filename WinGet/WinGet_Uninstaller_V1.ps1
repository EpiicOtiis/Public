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

# Execute winget list, capture all output (stdout and stderr) into a single array of strings.
# Then, filter out lines that appear to be progress bars or spinners.
$WingetListOutput = & ".\winget.exe" list --source winget --accept-source-agreements --disable-interactivity 2>&1 | Out-String | ConvertFrom-String -Delimiter "`n"

# Filter out lines that match known spinner/progress bar patterns or are empty/whitespace
$InstalledPackagesRaw = $WingetListOutput | Where-Object {
    $_ -notmatch '^\s*[-/\\]+\s*$' -and                                  # Filters out lines like -, \, /, | (spinners)
    $_ -notmatch '^[\x00-\x1F\x7F-\xFF]+[\s\dKBM/]+\s*$' -and             # Filters out lines with unicode progress bars like Γûê with KB/MB info
    $_ -notmatch '^\s*$'                                                # Filters out empty or whitespace-only lines
}

if ($InstalledPackagesRaw) {
    # Display the filtered list to the user
    $InstalledPackagesRaw | ForEach-Object { Write-Host $_ }
    Write-Host "-------------------------------------`n" -ForegroundColor DarkCyan

    # Prompt the user for the package to uninstall
    $PackageToUninstall = Read-Host "Enter the 'Id' or 'Name' of the package you want to uninstall (or press Enter to skip uninstallation)"

    if (-not [string]::IsNullOrWhiteSpace($PackageToUninstall)) {
        Write-Host "Attempting to uninstall '$PackageToUninstall'..." -ForegroundColor Yellow
        Try {
            # Execute the uninstall command, redirecting all output to null for silence
            & ".\winget.exe" uninstall "$PackageToUninstall" -e --accept-source-agreements -h --disable-interactivity 2>&1 | Out-Null
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
    Write-Host "Could not retrieve list of installed Winget packages, or all output was filtered out. Please check Winget's status." -ForegroundColor Red
}

# Countdown for 30 seconds
Write-Host "`n" # Add a newline for better readability before the countdown
for ($i = 30; $i -gt 0; $i--) {
    Write-Host "`rTask completed. This window will close in $i seconds." -NoNewline
    Start-Sleep -Seconds 1
}
Write-Host ""  # To add a newline at the end