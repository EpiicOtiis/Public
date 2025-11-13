<# (Windows_Update_Toolbox.ps1) :: (Revision # 1)/Aaron Pleus, (11/13/2025)

   This script, like all scripts developed by Aaron Pleus, unless otherwise explicitly stated, is the copyrighted property of Aaron Pleus.;
   it may not be shared, sold, or distributed whole or in part, even with modifications applied, for any reason. this includes on reddit, on discord, or as part of other RMM tools.
   	
   The moment you edit this script it becomes your own risk and Aaron Pleus will not provide assistance with it.#>

#region Core Script Functions

function Request-Administrator {
    # Get the current user's principal
    $currentUser = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()

    # Check if the user is in the Administrator role
    if (-not $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Warning "Administrator rights are required to run this script."
        Write-Warning "Attempting to re-launch as an Administrator..."
        
        # Relaunch the script with elevated privileges
        $scriptPath = $MyInvocation.MyCommand.Path
        try {
            Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs -ErrorAction Stop
        }
        catch {
            Write-Error "Failed to re-launch as Administrator. Please right-click the script and select 'Run as Administrator'."
            Read-Host "Press Enter to exit"
        }
        # Exit the current non-elevated session
        exit
    }
}

function Test-SupportedOS {
    $osInfo = Get-CimInstance Win32_OperatingSystem
    $osName = $osInfo.Caption
    $osBuild = $osInfo.BuildNumber

    $isSupported = $false
    $detectedOS = "Unsupported Operating System"

    if ($osName -like "*Server*") {
        if ($osBuild -ge 14393) { # Windows Server 2016 build number
            $isSupported = $true
            $detectedOS = $osName
        }
    }
    elseif ($osBuild -ge 10240) { # Windows 10 initial build number
        $isSupported = $true
        $detectedOS = $osName
    }

    if (-not $isSupported) {
        Write-Error "Sorry, this Operating System ($detectedOS) is not compatible with this tool."
        Write-Error "This tool is designed for Windows 10, Windows 11, and Windows Server 2016 or newer."
        Read-Host "Press Enter to exit"
        exit
    }
    
    # Return the OS name for display purposes
    return $detectedOS
}

function Show-MainMenu {
    param($osName)
    Clear-Host
    Write-Host "========================================================================" -ForegroundColor Green
    Write-Host "          Windows Update Toolbox [PowerShell Edition]" -ForegroundColor Green
    Write-Host "========================================================================" -ForegroundColor Green
    Write-Host "Detected OS: $osName"
    Write-Host
    Write-Host "    1. Open System Protection"
    Write-Host "    2. Reset Windows Update Components"
    Write-Host "    3. Delete Temporary Files"
    Write-Host "    4. Open Internet Options"
    Write-Host "    5. Run Chkdsk on the Windows Partition"
    Write-Host
    Write-Host "--- System File Repair (Recommended Order) ---" -ForegroundColor Yellow
    Write-Host "    6. Check if Image is Flagged as Corrupted (DISM CheckHealth)"
    Write-Host "    7. Scan Image for Component Store Corruption (DISM ScanHealth)"
    Write-Host "    8. Perform Repair Operations Automatically (DISM RestoreHealth)"
    Write-Host "    9. Run System File Checker (SFC)"
    Write-Host
    Write-Host "--- Other System Tools ---" -ForegroundColor Yellow
    Write-Host "   10. Clean Up Superseded Components (DISM StartComponentCleanup)"
    Write-Host "   11. Delete Incorrect Registry Values"
    Write-Host "   12. Repair/Reset Winsock Settings"
    Write-Host "   13. Force Group Policy Update"
    Write-Host "   14. Manage Windows Updates (PSWindowsUpdate)"
    Write-Host "   15. Reset the Windows Store"
    Write-Host "   16. Find the Windows Product Key"
    Write-Host "   17. Explore Other Local Solutions (Troubleshooting)"
    Write-Host "   18. Explore Other Online Solutions"
    Write-Host "   19. Restart Your PC (Immediate)"
    Write-Host "   20. Schedule a One-Time Reboot"
    Write-Host
    Write-Host "    q. Quit"
    Write-Host
}

function Pause-And-Return {
    Write-Host
    Read-Host "Press Enter to return to the main menu..."
}

#endregion Core Script Functions

#region Menu Option Functions

function Show-SystemProtection {
    Write-Host "Opening System Protection..." -ForegroundColor Cyan
    Start-Process systempropertiesprotection
}

function Reset-WindowsUpdateComponents {
    Write-Host "--- Stopping Windows Update related services ---" -ForegroundColor Yellow
    $services = @("bits", "wuauserv", "appidsvc", "cryptsvc", "msiserver", "TrustedInstaller")
    Stop-Service -Name $services -Force -ErrorAction SilentlyContinue
    
    Write-Host "Waiting for services to release file locks..." -ForegroundColor Cyan
    Start-Sleep -Seconds 5
    
    $systemRoot = $env:SystemRoot
    $softDist = Join-Path -Path $systemRoot -ChildPath "SoftwareDistribution"
    $catRoot2 = Join-Path -Path $systemRoot -ChildPath "System32\catroot2"
    
    Write-Host "--- Renaming SoftwareDistribution and Catroot2 folders ---" -ForegroundColor Yellow
    if (Test-Path "$softDist.bak") { Remove-Item -Path "$softDist.bak" -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path "$catRoot2.bak") { Remove-Item -Path "$catRoot2.bak" -Recurse -Force -ErrorAction SilentlyContinue }
    
    if (Test-Path $softDist) {
        Write-Host "Renaming $softDist..." -ForegroundColor Cyan
        Rename-Item -Path $softDist -NewName "SoftwareDistribution.bak" -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $catRoot2) {
        Write-Host "Renaming $catRoot2..." -ForegroundColor Cyan
        Rename-Item -Path $catRoot2 -NewName "catroot2.bak" -Force -ErrorAction SilentlyContinue
    }

    Write-Host "--- Re-registering DLLs ---" -ForegroundColor Yellow
    $dlls = @("atl.dll", "urlmon.dll", "mshtml.dll", "shdocvw.dll", "browseui.dll", "jscript.dll", "vbscript.dll", "scrrun.dll", "msxml.dll", "msxml3.dll", "msxml6.dll", "actxprxy.dll", "softpub.dll", "wintrust.dll", "dssenh.dll", "rsaenh.dll", "gpkcsp.dll", "sccbase.dll", "slbcsp.dll", "cryptdlg.dll", "oleaut32.dll", "ole32.dll", "shell32.dll", "initpki.dll", "wuapi.dll", "wuaueng.dll", "wuaueng1.dll", "wucltui.dll", "wups.dll", "wups2.dll", "wuweb.dll", "qmgr.dll", "qmgrprxy.dll", "wucltux.dll", "muweb.dll", "wuwebv.dll")
    foreach ($dll in $dlls) {
        regsvr32.exe /s $dll
    }

    Write-Host "--- Resetting Winsock and WinHTTP Proxy ---" -ForegroundColor Yellow
    netsh winsock reset
    netsh winhttp reset proxy

    Write-Host "--- Setting services to their default startup types ---" -ForegroundColor Yellow
    Set-Service -Name "wuauserv" -StartupType Automatic -ErrorAction SilentlyContinue
    Set-Service -Name "bits" -StartupType DelayedStart -ErrorAction SilentlyContinue
    Set-Service -Name "cryptsvc" -StartupType Automatic -ErrorAction SilentlyContinue
    Set-Service -Name "TrustedInstaller" -StartupType Manual -ErrorAction SilentlyContinue
    
    Write-Host "--- Starting services ---" -ForegroundColor Yellow
    Start-Service -Name $services -ErrorAction SilentlyContinue

    Write-Host "Windows Update Components reset successfully." -ForegroundColor Green
}

function Clear-TemporaryFiles {
    Write-Host "Deleting temporary files..." -ForegroundColor Cyan
    Get-ChildItem -Path $env:TEMP -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path "$env:SystemRoot\Temp" -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Temporary files deleted." -ForegroundColor Green
}

function Show-InternetOptions {
    Write-Host "Opening Internet Options..." -ForegroundColor Cyan
    Start-Process InetCpl.cpl
}

function Start-DiskCheck {
    Write-Host "This will open a new window to run CHKDSK." -ForegroundColor Yellow
    Write-Host "CHKDSK with /f requires a reboot. You will be prompted in the new window." -ForegroundColor Yellow
    Start-Process cmd.exe -ArgumentList "/c chkdsk $env:SystemDrive /f /r & pause" -Verb RunAs
}

function Start-SFCScan {
    Write-Host "This will open a new window to run SFC /SCANNOW." -ForegroundColor Yellow
    Write-Host "This process can take some time." -ForegroundColor Yellow
    Start-Process cmd.exe -ArgumentList "/c sfc /scannow & pause" -Verb RunAs
}

function Start-DismScan {
    param($Argument)
    Write-Host "This will open a new window to run DISM with the $Argument switch." -ForegroundColor Yellow
    Write-Host "This process can take some time." -ForegroundColor Yellow
    Start-Process cmd.exe -ArgumentList "/c Dism.exe /Online /Cleanup-Image $Argument & pause" -Verb RunAs
}

function Reset-RegistryKeys {
    Write-Host "This function is advanced and will modify the registry." -ForegroundColor Yellow
    $confirmation = Read-Host "Are you sure you want to proceed? (y/n)"
    if ($confirmation -ne 'y') {
        Write-Host "Operation cancelled." -ForegroundColor Red
        return
    }

    # Backup logic can be added here if desired.
    
    Write-Host "Deleting specified registry values..." -ForegroundColor Cyan
    $regPaths = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\WindowsUpdate",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\WindowsUpdate",
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    )
    foreach ($path in $regPaths) {
        if(Test-Path $path) {
            Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    # For specific values
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate" -Name "SusClientId", "SusClientIDValidation" -Force -ErrorAction SilentlyContinue
    
    Write-Host "Registry values reset." -ForegroundColor Green
}

function Reset-Winsock {
    Write-Host "--- Resetting Network Configurations ---" -ForegroundColor Yellow
    Write-Host "Resetting Winsock..." -ForegroundColor Cyan
    netsh winsock reset
    Write-Host "Resetting TCP/IP..." -ForegroundColor Cyan
    netsh int ip reset
    Write-Host "Flushing DNS Cache..." -ForegroundColor Cyan
    ipconfig /flushdns
    Write-Host "Network configurations reset." -ForegroundColor Green
}

function Force-GPUpdate {
    Write-Host "Forcing Group Policy update..." -ForegroundColor Cyan
    gpupdate.exe /force
    Write-Host "GPUpdate complete." -ForegroundColor Green
}

function Manage-WindowsUpdates {
    # Check for the PSWindowsUpdate module
    if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
        Write-Host "The PSWindowsUpdate module is not installed." -ForegroundColor Yellow
        $install = Read-Host "Do you want to install it now? (y/n)"
        if ($install -eq 'y') {
            Write-Host "Installing PSWindowsUpdate module..." -ForegroundColor Cyan
            Install-Module PSWindowsUpdate -Force -AcceptLicense -Scope AllUsers
        } else {
            return # Exit function if user declines install
        }
    } else {
        Write-Host "PSWindowsUpdate module is already installed. Checking for updates to the module..." -ForegroundColor Cyan
        Update-Module -Name PSWindowsUpdate -Force -AcceptLicense -ErrorAction SilentlyContinue
    }
    
    # This variable will hold the list of updates for the current session
    $availableUpdates = $null
    
    do {
        Clear-Host
        Write-Host "--- PSWindowsUpdate Menu ---" -ForegroundColor Green
        Write-Host "1. Scan for and list available updates"
        Write-Host "2. Install all available updates"
        Write-Host "3. Install specific updates (by KB number)"
        Write-Host "q. Return to main menu"
        $choice = Read-Host "Select an option"

        switch ($choice) {
            "1" {
                Write-Host "Scanning for updates... This may take a moment." -ForegroundColor Cyan
                $availableUpdates = Get-WindowsUpdate
                if ($null -eq $availableUpdates) {
                    Write-Host "No available updates were found." -ForegroundColor Green
                } else {
                    $availableUpdates | Format-Table Title, KB, Size -AutoSize
                }
                Read-Host "Press Enter to continue..."
            }
            "2" {
                Write-Host "Installing all available updates. This may take a long time and reboot automatically." -ForegroundColor Yellow
                Install-WindowsUpdate -AcceptAll -AutoReboot
                Read-Host "Press Enter to continue..."
            }
            "3" { 
                if ($null -eq $availableUpdates) {
                    Write-Warning "You must scan for updates first (Option 1)."
                } else {
                    # Display the list again for convenience
                    $availableUpdates | Format-Table Title, KB, Size -AutoSize
                    Write-Host
                    $kbInput = Read-Host "Enter the KB number(s) to install, separated by a comma (e.g., KB5031356,KB5032007)"
                    $kbsToInstall = $kbInput -split ',' | ForEach-Object { $_.Trim() }

                    Write-Host "Attempting to install selected updates. This may reboot automatically." -ForegroundColor Yellow
                    Install-WindowsUpdate -KBArticleID $kbsToInstall -AcceptAll -AutoReboot
                }
                Read-Host "Press Enter to continue..."
            }
        }
    } while ($choice -ne 'q')
}

function Reset-WindowsStore {
    Write-Host "Resetting the Windows Store cache..." -ForegroundColor Cyan
    Start-Process wsreset.exe -Wait
    Write-Host "Windows Store reset complete." -ForegroundColor Green
}

function Get-ProductKey {
    Write-Host "Retrieving Windows Product Key from firmware..." -ForegroundColor Cyan
    try {
        $key = (Get-CimInstance -ClassName SoftwareLicensingService).OA3xOriginalProductKey
        Write-Host "Product Key: $key" -ForegroundColor Green
    }
    catch {
        Write-Error "Could not retrieve the product key."
    }
}

function Show-LocalTroubleshooting {
    Write-Host "Opening built-in troubleshooters..." -ForegroundColor Cyan
    Start-Process control.exe -ArgumentList "/name Microsoft.Troubleshooting"
}

function Show-OnlineHelp {
    Write-Host "Opening Microsoft Support for Windows Update..." -ForegroundColor Cyan
    Start-Process "https://support.microsoft.com/en-us/windows/windows-update-troubleshooter-19bc41ca-ad72-ae67-af3c-89ce169755dd"
}

function Restart-Computer-Immediate {
    Write-Host "Your PC will restart in 60 seconds." -ForegroundColor Yellow
    $confirmation = Read-Host "Are you sure? (y/n)"
    if ($confirmation -eq 'y') {
        Restart-Computer -Force
    } else {
        Write-Host "Restart cancelled." -ForegroundColor Red
    }
}

function Schedule-OneTimeReboot {
    Write-Host "Launching the One-Time Reboot Scheduler script..." -ForegroundColor Cyan
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Windows%20Troubleshooting/One_Time_Reboot_Scheduler.ps1'))
    }
    catch {
        Write-Error "Failed to download and execute the script from GitHub."
        Write-Error "Please check your internet connection and the URL."
    }
}

#endregion Menu Option Functions


# ==================================================================================
# SCRIPT ENTRY POINT
# ==================================================================================

# 1. Check for Admin rights
Request-Administrator

# 2. Check for supported OS
$os = Test-SupportedOS

# 3. Main script loop
do {
    Show-MainMenu -osName $os
    $selection = Read-Host "Please select an option"
    
    Clear-Host
    switch ($selection) {
        "1"  { Show-SystemProtection }
        "2"  { Reset-WindowsUpdateComponents }
        "3"  { Clear-TemporaryFiles }
        "4"  { Show-InternetOptions }
        "5"  { Start-DiskCheck }
        "6"  { Start-DismScan -Argument "/CheckHealth" }
        "7"  { Start-DismScan -Argument "/ScanHealth" }
        "8"  { Start-DismScan -Argument "/RestoreHealth" }
        "9"  { Start-SFCScan }
        "10" { Start-DismScan -Argument "/StartComponentCleanup" }
        "11" { Reset-RegistryKeys }
        "12" { Reset-Winsock }
        "13" { Force-GPUpdate }
        "14" { Manage-WindowsUpdates }
        "15" { Reset-WindowsStore }
        "16" { Get-ProductKey }
        "17" { Show-LocalTroubleshooting }
        "18" { Show-OnlineHelp }
        "19" { Restart-Computer-Immediate }
        "20" { Schedule-OneTimeReboot }
        "q"  { Write-Host "Exiting script." }
        default { Write-Warning "Invalid option. Please try again." }
    }

    if ($selection -ne 'q') {
        Pause-And-Return
    }

} while ($selection -ne 'q')