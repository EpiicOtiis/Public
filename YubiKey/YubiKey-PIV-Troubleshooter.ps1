<#
.SYNOPSIS
Provides a guided troubleshooting and management interface for YubiKey PIV operations on Windows.

.DESCRIPTION
This script helps administrators check prerequisites, install required YubiKey tools, inspect PIV status, unblock a PIN using the default PUK, factory reset the PIV applet, and restart the workstation.
#>

# Requires -RunAsAdministrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "This script must be run as an Administrator. Please elevate your PowerShell prompt and try again."
    Exit
}

# --- GLOBAL VARIABLES ---
$tempDir = "C:\temp\yk-downloads"
$global:ykmanPath = $null
$global:pivToolPath = $null

# --- HELPER FUNCTIONS ---

function Get-YkTools {
    $searchPaths = @(
        "C:\Program Files\Yubico", 
        "C:\Program Files (x86)\Yubico", 
        "C:\Program Files\Yubico PIV Tool", 
        "C:\Program Files (x86)\Yubico PIV Tool"
    )
    
    $validPaths = $searchPaths | Where-Object { Test-Path $_ }
    
    if ($validPaths) {
        $global:ykmanPath = (Get-ChildItem -Path $validPaths -Filter "ykman.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
        $global:pivToolPath = (Get-ChildItem -Path $validPaths -Filter "yubico-piv-tool.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
    }
}

function Check-Prerequisites {
    Write-Host "`n=== Checking Prerequisites ===" -ForegroundColor Cyan
    if (!(Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir | Out-Null }
    
    # 1. Check & Install Minidriver
    $mdInstalled = Get-ChildItem -Path @('HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall') -ErrorAction SilentlyContinue | 
                   Get-ItemProperty -ErrorAction SilentlyContinue | 
                   Where-Object { $_.DisplayName -match "YubiKey Smart Card Minidriver" }
    
    if ($mdInstalled) {
        Write-Host "[OK] YubiKey Smart Card Minidriver is installed." -ForegroundColor Green
    } else {
        Write-Host "[!] YubiKey Smart Card Minidriver is NOT installed." -ForegroundColor Red
        $installMD = Read-Host "Do you want to download and install the Minidriver now? (Y/N)"
        if ($installMD -match "^y$|^yes$") {
            $is64Bit = [Environment]::Is64BitOperatingSystem
            $mdUrl = if ($is64Bit) { 
                "https://downloads.yubico.com/support/YubiKey-Minidriver-5.0.4.273-x64.msi" 
            } else { 
                "https://downloads.yubico.com/support/YubiKey-Minidriver-5.0.4.273-x86.msi" 
            }
            
            $mdInstaller = "$tempDir\YubiKey-Minidriver.msi"
            Write-Host "Downloading Minidriver..." -ForegroundColor Yellow
            Invoke-WebRequest -Uri $mdUrl -OutFile $mdInstaller
            
            Write-Host "Installing Minidriver silently..." -ForegroundColor Yellow
            Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$mdInstaller`" /qn /norestart" -Wait -NoNewWindow
            Write-Host "Minidriver installed successfully!" -ForegroundColor Green
        }
    }

    # 2. Check & Install Management CLI (ykman or piv-tool)
    Get-YkTools
    if ($global:ykmanPath) {
        Write-Host "[OK] ykman found at: $($global:ykmanPath)" -ForegroundColor Green
    } elseif ($global:pivToolPath) {
        Write-Host "[OK] yubico-piv-tool found at: $($global:pivToolPath)" -ForegroundColor Green
    } else {
        Write-Host "[!] No Yubico CLI management tool found." -ForegroundColor Red
        $installTool = Read-Host "Do you want to download and install a management tool now? (Y/N)"
        if ($installTool -match "^y$|^yes$") {
            Write-Host "1. Yubico Authenticator (GUI App + ykman included)"
            Write-Host "2. YubiKey Manager v5.9.2 (ykman CLI only)"
            Write-Host "3. Yubico PIV Tool v2.7.3 (piv-tool CLI only)"
            $toolChoice = Read-Host "Select option (1, 2, or 3)"
            
            if ($toolChoice -eq "1") {
                $installer = "$tempDir\yubico-authenticator.msi"
                Write-Host "Downloading Yubico Authenticator..." -ForegroundColor Yellow
                Invoke-WebRequest -Uri "https://developers.yubico.com/yubioath-flutter/Releases/yubico-authenticator-latest-win64.msi" -OutFile $installer
                Write-Host "Installing..." -ForegroundColor Yellow
                Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$installer`" /qn /norestart" -Wait -NoNewWindow
            } elseif ($toolChoice -eq "2") {
                $installer = "$tempDir\yubikey-manager.msi"
                Write-Host "Downloading YubiKey Manager CLI..." -ForegroundColor Yellow
                Invoke-WebRequest -Uri "https://developers.yubico.com/yubikey-manager/Releases/yubikey-manager-5.9.2-win64.msi" -OutFile $installer
                Write-Host "Installing..." -ForegroundColor Yellow
                Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$installer`" /qn /norestart" -Wait -NoNewWindow
            } elseif ($toolChoice -eq "3") {
                $installer = "$tempDir\yubico-piv-tool.msi"
                Write-Host "Downloading Yubico PIV Tool..." -ForegroundColor Yellow
                Invoke-WebRequest -Uri "https://developers.yubico.com/yubico-piv-tool/Releases/yubico-piv-tool-2.7.3-win64.msi" -OutFile $installer
                Write-Host "Installing..." -ForegroundColor Yellow
                Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$installer`" /qn /norestart" -Wait -NoNewWindow
            }
            
            # Refresh paths after install
            Start-Sleep -Seconds 3
            Get-YkTools
            if ($global:ykmanPath -or $global:pivToolPath) {
                Write-Host "Installation successful! CLI found." -ForegroundColor Green
            } else {
                Write-Host "Installation failed or tool could not be located." -ForegroundColor Red
            }
        }
    }
    Write-Host "Press any key to return to menu..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Search-UninstallMinidriverEvents {
    Write-Host "`n=== Searching for Minidriver Uninstall Events ===" -ForegroundColor Cyan

    $installedDriver = Get-ChildItem -Path @('HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall') -ErrorAction SilentlyContinue |
        Get-ItemProperty -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match "YubiKey Smart Card Minidriver" } |
        Select-Object -First 1

    if ($installedDriver) {
        Write-Host "[OK] YubiKey Smart Card Minidriver is currently installed." -ForegroundColor Green
        if ($installedDriver.DisplayVersion) {
            Write-Host "Installed version: $($installedDriver.DisplayVersion)" -ForegroundColor Gray
        }
    } else {
        Write-Host "[!] YubiKey Smart Card Minidriver is not currently installed." -ForegroundColor Yellow
    }

    $uninstallEvents = Get-WinEvent -FilterHashtable @{ LogName='Application'; ProviderName='MsiInstaller'; ID=@(1034, 11724) } -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match "YubiKey Smart Card Minidriver" } |
        Sort-Object TimeCreated -Descending

    if ($uninstallEvents) {
        Write-Host "`nFound uninstall-related events:" -ForegroundColor Yellow
        foreach ($event in $uninstallEvents) {
            Write-Host " - $($event.TimeCreated): $($event.Id) - $($event.Message.Trim())" -ForegroundColor DarkYellow
        }
    } else {
        Write-Host "`nNo matching uninstall events were found in the Application log." -ForegroundColor Yellow
    }

    Write-Host "`n=== Additional Event Log Checks ===" -ForegroundColor Cyan

    Write-Host "`n[Application/System logs - last 30 days]" -ForegroundColor Yellow
    Get-WinEvent -FilterHashtable @{
        LogName   = 'Application', 'System'
        StartTime = (Get-Date).AddDays(-30)
    } -ErrorAction SilentlyContinue |
    Where-Object { $_.Message -match 'yubi|minidriver' } |
    Select-Object TimeCreated, LogName, ProviderName, Id, Message |
    Format-Table -AutoSize

    Write-Host "`n[MsiInstaller Application logs - last 30 days]" -ForegroundColor Yellow
    Get-WinEvent -FilterHashtable @{
        LogName      = 'Application'
        ProviderName = 'MsiInstaller'
        StartTime    = (Get-Date).AddDays(-30)
    } -ErrorAction SilentlyContinue |
    Where-Object { $_.Message -match 'yubi|minidriver' } |
    Select-Object TimeCreated, Id, Message |
    Format-List

    Write-Host "`n[Smart Card logs - last 30 days]" -ForegroundColor Yellow
    $scLogs = (Get-WinEvent -ListLog *SmartCard* -ErrorAction SilentlyContinue).LogName
    if ($scLogs) {
        Get-WinEvent -FilterHashtable @{
            LogName   = $scLogs
            StartTime = (Get-Date).AddDays(-30)
        } -ErrorAction SilentlyContinue |
        Select-Object TimeCreated, LogName, Id, Message |
        Out-GridView -Title "SmartCard Event Logs"
    } else {
        Write-Host "No Smart Card event logs were found on this system." -ForegroundColor Yellow
    }

    Write-Host "`n[System logs - last 7 days]" -ForegroundColor Yellow
    Get-WinEvent -FilterHashtable @{
        LogName   = 'System'
        StartTime = (Get-Date).AddDays(-7)
    } -ErrorAction SilentlyContinue |
    Where-Object { $_.Message -match 'Yubi|Minidriver|Smart Card|ScFilter' } |
    Select-Object TimeCreated, ProviderName, Id, Message |
    Format-List

    Write-Host "`nPress any key to return to menu..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Show-Menu {
    Clear-Host
    Write-Host "===============================================" -ForegroundColor Cyan
    Write-Host "     YubiKey PIV Troubleshooter & Manager      " -ForegroundColor Cyan
    Write-Host "===============================================" -ForegroundColor Cyan
    Write-Host "1. Check & Install Prerequisites (Minidriver/CLI)"
    Write-Host "2. Get PIV Info (Check PIN/PUK remaining tries)"
    Write-Host "3. Unblock PIN (Using Default PUK: 12345678)"
    Write-Host "4. Factory Reset PIV Applet (Wipes Certificate)"
    Write-Host "5. Search for uninstall Minidriver events"
    Write-Host "6. Reboot Workstation"
    Write-Host "7. Exit"
    Write-Host "===============================================" -ForegroundColor Cyan
}

# --- MAIN SCRIPT LOOP ---
$menuRunning = $true

while ($menuRunning) {
    Show-Menu
    $selection = Read-Host "Enter your selection (1-7)"
    
    # Ensure we always have the freshest tool paths dynamically
    Get-YkTools

    switch ($selection) {
        "1" {
            Check-Prerequisites
        }
        "2" {
            Write-Host "`nRetrieving PIV Information..." -ForegroundColor Yellow
            if ($global:ykmanPath) {
                & $global:ykmanPath piv info
            } elseif ($global:pivToolPath) {
                & $global:pivToolPath -a status
            } else {
                Write-Host "`n[!] No CLI tool found. Please run Option 1 first." -ForegroundColor Red
            }
            Write-Host "`nPress any key to return to menu..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "3" {
            Write-Host "`nAttempting to unblock PIN with default PUK..." -ForegroundColor Yellow
            if ($global:ykmanPath) {
                $result = & $global:ykmanPath piv unblock-pin --puk 12345678 --new-pin 123456 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "[SUCCESS] PIN is reset to 123456." -ForegroundColor Green
                } else {
                    Write-Host "[FAILED] Could not unblock PIN. (Is the PUK blocked?)" -ForegroundColor Red
                    Write-Host "Error output: $result" -ForegroundColor DarkRed
                }
            } elseif ($global:pivToolPath) {
                $result = & $global:pivToolPath -a unblock-pin -P 12345678 -N 123456 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "[SUCCESS] PIN is reset to 123456." -ForegroundColor Green
                } else {
                    Write-Host "[FAILED] Could not unblock PIN. (Is the PUK blocked?)" -ForegroundColor Red
                    Write-Host "Error output: $result" -ForegroundColor DarkRed
                }
            } else {
                Write-Host "`n[!] No CLI tool found. Please run Option 1 first." -ForegroundColor Red
            }
            Write-Host "`nPress any key to return to menu..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "4" {
            Write-Host "`n[WARNING] This will completely wipe the Smart Card applet." -ForegroundColor Red
            $confirmReset = Read-Host "Are you absolutely sure you want to factory reset the PIV applet? (Y/N)"
            if ($confirmReset -match "^y$|^yes$") {
                Write-Host "Factory resetting PIV applet..." -ForegroundColor Yellow
                if ($global:ykmanPath) {
                    $result = & $global:ykmanPath piv reset --force 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "[SUCCESS] Reset complete. PIN is 123456, PUK is 12345678." -ForegroundColor Green
                    } else {
                        Write-Host "[FAILED] The reset operation encountered an error." -ForegroundColor Red
                        Write-Host "Error output: $result" -ForegroundColor DarkRed
                    }
                } elseif ($global:pivToolPath) {
                    $result = & $global:pivToolPath -a reset 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "[SUCCESS] Reset complete. PIN is 123456, PUK is 12345678." -ForegroundColor Green
                    } else {
                        Write-Host "[FAILED] The reset operation encountered an error." -ForegroundColor Red
                        Write-Host "Error output: $result" -ForegroundColor DarkRed
                    }
                } else {
                    Write-Host "`n[!] No CLI tool found. Please run Option 1 first." -ForegroundColor Red
                }
            } else {
                Write-Host "Factory reset aborted." -ForegroundColor Yellow
            }
            Write-Host "`nPress any key to return to menu..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "5" {
            Search-UninstallMinidriverEvents
        }
        "6" {
            $confirmReboot = Read-Host "`nAre you sure you want to restart this computer now? (Y/N)"
            if ($confirmReboot -match "^y$|^yes$") {
                Write-Host "Initiating reboot..." -ForegroundColor Yellow
                Restart-Computer -Force
            }
        }
        "7" {
            Write-Host "`nExiting Troubleshooter. Have a good day!" -ForegroundColor Green
            $menuRunning = $false
        }
        Default {
            Write-Host "`nInvalid selection. Please choose a number between 1 and 6." -ForegroundColor Red
            Start-Sleep -Seconds 2
        }
    }
}