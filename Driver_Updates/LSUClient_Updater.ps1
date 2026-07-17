<#
.SYNOPSIS
    Interactive driver and firmware update script using the LSUClient module.
.DESCRIPTION
    Checks for the LSUClient module, scans for applicable Lenovo updates,
    and provides an interactive menu for unattended or manual installation.
    Includes automated cleanup of the temporary download directory.
#>

# 1. Ensure script is running as Administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "This script must be run as Administrator. Please elevate your PowerShell session."
    break
}

# 2. Ensure NuGet provider is installed (required for module installation)
if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
    Write-Host "Installing NuGet package provider..." -ForegroundColor Yellow
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
}

# 3. Install/Import LSUClient if missing
if (-not (Get-Module -ListAvailable -Name LSUClient)) {
    Write-Host "Installing LSUClient module from PSGallery..." -ForegroundColor Cyan
    Install-Module -Name LSUClient -Force -AllowClobber -Scope AllUsers
}
Import-Module LSUClient

# 4. Set the default download path (LSUClient defaults to this temp folder)
$tempPath = "$env:TEMP\LSUPackages"

# Helper function for pausing the menu
function Pause-Script {
    Write-Host "`nPress any key to return to the menu..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}

function Show-Menu {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host " Lenovo System Update (LSUClient) Manager " -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "1. Scan system for needed updates"
    Write-Host "2. Install ALL needed 'unattended' updates silently"
    Write-Host "3. Manually select updates to install (GUI Grid)"
    Write-Host "4. Clean up downloaded package cache"
    Write-Host "5. Exit"
    Write-Host "==========================================" -ForegroundColor Cyan
}

# 5. Main Interactive Loop
do {
    Show-Menu
    $choice = Read-Host "Select an option (1-5)"

    switch ($choice) {
        '1' {
            Write-Host "`nScanning Lenovo catalog for needed updates. This may take a moment..." -ForegroundColor Yellow
            $script:updates = Get-LSUpdate
            if ($script:updates) {
                Write-Host "`nFound $($script:updates.Count) needed updates:" -ForegroundColor Green
                $script:updates | Format-Table Title, Version, Date, @{Name="Silent";Expression={$_.Installer.Unattended}} -AutoSize
            } else {
                Write-Host "`nYour system is fully up to date." -ForegroundColor Green
            }
            Pause-Script
        }
        '2' {
            if (-not $script:updates) { 
                Write-Host "`nScanning for updates..." -ForegroundColor Yellow
                $script:updates = Get-LSUpdate 
            }
            
            # Filter for updates that support silent, non-interactive installation
            $silentUpdates = $script:updates | Where-Object { $_.Installer.Unattended }
            
            if ($silentUpdates) {
                Write-Host "`nDownloading and installing $($silentUpdates.Count) silent updates..." -ForegroundColor Yellow
                $silentUpdates | Save-LSUpdate -Verbose | Install-LSUpdate -Verbose
                Write-Host "`nInstallation complete! Note: Some firmware or BIOS updates may require a reboot." -ForegroundColor Green
            } else {
                Write-Host "`nNo silent/unattended updates found." -ForegroundColor Yellow
            }
            Pause-Script
        }
        '3' {
            if (-not $script:updates) { 
                Write-Host "`nScanning for updates..." -ForegroundColor Yellow
                $script:updates = Get-LSUpdate 
            }
            
            if ($script:updates) {
                Write-Host "`nOpening selection grid... Select the updates you want to install and click OK." -ForegroundColor Yellow
                # Out-GridView allows multi-select by holding CTRL
                $selected = $script:updates | Out-GridView -Title "Select Lenovo Updates to Install (Hold CTRL for multiple)" -PassThru
                
                if ($selected) {
                    Write-Host "`nDownloading and installing $($selected.Count) selected updates..." -ForegroundColor Yellow
                    $selected | Save-LSUpdate -Verbose | Install-LSUpdate -Verbose
                    Write-Host "`nInstallation complete!" -ForegroundColor Green
                } else {
                    Write-Host "`nNo updates selected." -ForegroundColor Yellow
                }
            } else {
                Write-Host "`nNo updates available to select." -ForegroundColor Yellow
            }
            Pause-Script
        }
        '4' {
            if (Test-Path $tempPath) {
                Write-Host "`nCleaning up downloaded package cache at $tempPath..." -ForegroundColor Yellow
                Remove-Item -Path "$tempPath\*" -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "Cleanup complete." -ForegroundColor Green
            } else {
                Write-Host "`nNo cache found at $tempPath. Nothing to clean." -ForegroundColor Green
            }
            Pause-Script
        }
        '5' {
            Write-Host "`nExiting..." -ForegroundColor Cyan
        }
        default {
            Write-Host "`nInvalid selection. Please try again." -ForegroundColor Red
            Pause-Script
        }
    }
} until ($choice -eq '5')