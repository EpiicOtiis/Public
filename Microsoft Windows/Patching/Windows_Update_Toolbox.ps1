<# (Windows_Update_Toolbox.ps1) :: (Revision # 1)/Aaron Pleus, (11/13/2025)

   This script, like all scripts developed by Aaron Pleus, unless otherwise explicitly stated, is the copyrighted property of Aaron Pleus.;
   it may not be shared, sold, or distributed whole or in part, even with modifications applied, for any reason. this includes on reddit, on discord, or as part of other RMM tools.
   	
   The moment you edit this script it becomes your own risk and Aaron Pleus will not provide assistance with it.
   #>

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

function Get-SystemDetails {
    $osInfo = Get-CimInstance Win32_OperatingSystem
    $csInfo = Get-CimInstance Win32_ComputerSystem
    $cpuInfo = Get-CimInstance Win32_Processor | Select-Object -First 1
    $biosInfo = Get-CimInstance Win32_BIOS | Select-Object -First 1
    $netAdapters = Get-NetAdapter -ErrorAction SilentlyContinue

    if (-not $netAdapters) {
        $netAdapters = Get-CimInstance Win32_NetworkAdapter -Filter "NetEnabled = TRUE" | Select-Object @{Name='Name';Expression={$_.Name}}, @{Name='InterfaceDescription';Expression={$_.Description}}, @{Name='Status';Expression={ if ($_.NetConnectionStatus -eq 2) { 'Up' } else { 'Down' } }}
    }

    $connectedAdapters = $netAdapters | Where-Object { $_.Status -eq 'Up' }
    $networkSummary = if ($connectedAdapters) {
        ($connectedAdapters | ForEach-Object { "$($_.Name) ($($_.InterfaceDescription))" } | Sort-Object) -join ', '
    }
    else {
        if ($netAdapters) {
            ($netAdapters | ForEach-Object { "$($_.Name) [$($_.Status)]" } | Sort-Object) -join ', '
        }
        else {
            'No network adapters detected.'
        }
    }

    [PSCustomObject]@{
        OSCaption = $osInfo.Caption
        OSBuild = $osInfo.BuildNumber
        OSVersion = $osInfo.Version
        Manufacturer = $csInfo.Manufacturer
        Model = $csInfo.Model
        SerialNumber = $biosInfo.SerialNumber
        Processor = $cpuInfo.Name
        TotalPhysicalMemoryGB = [math]::Round($csInfo.TotalPhysicalMemory / 1GB, 2)
        ConnectedNetworkAdapters = $networkSummary
        ComputerName = $csInfo.Name
    }
}

function Test-SupportedOS {
    $systemDetails = Get-SystemDetails
    $osName = $systemDetails.OSCaption
    $osBuild = [int]$systemDetails.OSBuild

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
    
    return $systemDetails
}

function Show-MainMenu {
    param($systemDetails)
    Clear-Host
    Write-Host "========================================================================" -ForegroundColor Green
    Write-Host "          Windows Update Toolbox [PowerShell Edition]" -ForegroundColor Green
    Write-Host "========================================================================" -ForegroundColor Green
    Write-Host "Detected OS: $($systemDetails.OSCaption) (Build $($systemDetails.OSBuild))"
    Write-Host "Manufacturer: $($systemDetails.Manufacturer) $($systemDetails.Model)"
    Write-Host "Serial Number: $($systemDetails.SerialNumber)"
    Write-Host "Processor: $($systemDetails.Processor)"
    Write-Host "Installed RAM: $($systemDetails.TotalPhysicalMemoryGB) GB"
    Write-Host "Network: $($systemDetails.ConnectedNetworkAdapters)"
    Write-Host
    Write-Host "--- Windows Update Tools ---" -ForegroundColor Yellow
    Write-Host "    2. Reset Windows Update Components"
    Write-Host "   10. Clean Up Superseded Components (DISM StartComponentCleanup)"
    Write-Host "   14. Manage Windows Updates"
    Write-Host "   15. Reset the Windows Store"
    Write-Host
    Write-Host "--- System Repair ---" -ForegroundColor Yellow
    Write-Host "    5. Run Chkdsk on the Windows Partition"
    Write-Host "    6. Check if Image is Flagged as Corrupted (DISM CheckHealth)"
    Write-Host "    7. Scan Image for Component Store Corruption (DISM ScanHealth)"
    Write-Host "    8. Perform Repair Operations Automatically (DISM RestoreHealth - Online or ISO source)"
    Write-Host "    9. Run System File Checker (SFC)"
    Write-Host "   21. Query recent CHKDSK results"
    Write-Host "   22. Check Windows drive dirty bit"
    Write-Host
    Write-Host "--- Network & Policy ---" -ForegroundColor Yellow
    Write-Host "    4. Open Internet Options"
    Write-Host "   11. Delete Incorrect Registry Values"
    Write-Host "   12. Repair/Reset Winsock Settings"
    Write-Host "   13. Force Group Policy Update"
    Write-Host
    Write-Host "--- Utilities ---" -ForegroundColor Yellow
    Write-Host "    1. Open System Protection"
    Write-Host "    3. Delete Temporary Files"
    Write-Host "   16. Find the Windows Product Key"
    Write-Host "   17. Launch Windows Troubleshooters"
    Write-Host "   18. Open Windows Update Support Website"
    Write-Host "   23. Check Disk Health (Clear Disk Info)"
    Write-Host
    Write-Host "--- Restart & Scheduling ---" -ForegroundColor Yellow
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

function Show-ChkdskResults {
    Write-Host "Querying recent CHKDSK results from the Application event log..." -ForegroundColor Cyan
    $countInput = Read-Host "How many recent CHKDSK results do you want to display? Press Enter for the most recent run"
    $count = 1

    if (-not [string]::IsNullOrWhiteSpace($countInput)) {
        if (-not [int]::TryParse($countInput, [ref]$count) -or $count -lt 1) {
            Write-Warning "Invalid number provided. Defaulting to the most recent run."
            $count = 1
        }
    }

    $events = Get-WinEvent -LogName "Application" -FilterXPath '*[System[(EventID=1001 or EventID=26214)]]' |
        Where-Object { $_.Message -like "*Chkdsk*" } |
        Sort-Object TimeCreated -Descending |
        Select-Object -First $count

    if ($events) {
        $events | Format-List
        if ($events.Count -lt $count) {
            Write-Host "Only $($events.Count) CHKDSK result(s) were found, which is fewer than the requested $count." -ForegroundColor Yellow
        }
    } else {
        Write-Host "No recent CHKDSK results found in the Application event log." -ForegroundColor Yellow
    }
}

function Test-DriveDirtyBit {
    $systemDrive = $env:SystemDrive.TrimEnd('\')
    $driveLetter = $systemDrive.Substring(0,2)
    Write-Host "Checking whether $driveLetter is marked dirty..." -ForegroundColor Cyan

    try {
        $result = fsutil dirty query $driveLetter 2>&1
        if ($result -match '(?i)is dirty') {
            Write-Host "$driveLetter is marked dirty. CHKDSK is likely required and may run at next boot if configured." -ForegroundColor Yellow
        }
        elseif ($result -match '(?i)is not dirty') {
            Write-Host "$driveLetter is not marked dirty." -ForegroundColor Green
        }
        else {
            Write-Host "Unable to determine dirty bit status for $driveLetter." -ForegroundColor Yellow
            Write-Host $result
        }
    }
    catch {
        Write-Error "Failed to query dirty bit on $driveLetter. $_"
    }
}

function Start-SFCScan {
    Write-Host "This will open a new window to run SFC /SCANNOW." -ForegroundColor Yellow
    Write-Host "This process can take some time." -ForegroundColor Yellow
    Start-Process cmd.exe -ArgumentList "/c sfc /scannow & pause" -Verb RunAs
}

function Start-DismScan {
    param($Argument)

    if ($Argument -eq "/RestoreHealth") {
        $method = Get-DISMRepairMethod
        if ($method -eq 'ISO') {
            $isoPath = Get-RepairISOPath
            if (-not $isoPath) {
                Write-Warning "ISO repair cancelled or source not found."
                return
            }

            try {
                Write-Host "Mounting ISO and running DISM RestoreHealth with local source..." -ForegroundColor Cyan
                $driveLetter = Mount-ISO -isoPath $isoPath
                
                # Ensure drive letter has colon for proper path construction
                if ($driveLetter -notmatch ':$') {
                    $driveLetter = "$driveLetter`:"
                }
                
                $sourcePath = Join-Path $driveLetter "Sources\install.wim"
                if (-not (Test-Path $sourcePath)) {
                    $sourcePath = Join-Path $driveLetter "Sources\install.esd"
                }

                if (-not (Test-Path $sourcePath)) {
                    # Provide diagnostics - list what's actually on the ISO
                    Write-Host "Diagnostic: Contents of mounted ISO at $driveLetter" -ForegroundColor Yellow
                    $isoContents = Get-ChildItem -Path $driveLetter -ErrorAction SilentlyContinue
                    if ($isoContents) {
                        $isoContents | Format-Table Name, PSIsContainer -AutoSize
                    } else {
                        Write-Host "Unable to list ISO contents" -ForegroundColor Red
                    }
                    
                    $sourcesFolder = Join-Path $driveLetter "Sources"
                    if (Test-Path $sourcesFolder) {
                        Write-Host "Contents of $sourcesFolder`:" -ForegroundColor Yellow
                        Get-ChildItem -Path $sourcesFolder | Format-Table Name, Length -AutoSize
                    }
                    
                    throw "No install.wim or install.esd was found inside the mounted ISO at $sourcesFolder"
                }

                $sourceArg = if ($sourcePath -like "*.wim") {
                    "/Source:WIM:$sourcePath:1"
                } else {
                    "/Source:ESD:$sourcePath:1"
                }

                Write-Host "Using source file: $sourcePath" -ForegroundColor Green
                Write-Host "This process can take some time." -ForegroundColor Yellow
                Start-Process cmd.exe -ArgumentList "/c Dism.exe /Online /Cleanup-Image /RestoreHealth $sourceArg /LimitAccess & pause" -Verb RunAs -Wait
            }
            catch {
                Write-Error "ISO-based RestoreHealth failed: $_"
            }
            finally {
                Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
            }
        }
        else {
            Write-Host "Starting online DISM RestoreHealth repair..." -ForegroundColor Cyan
            Write-Host "This process can take some time." -ForegroundColor Yellow
            Start-Process cmd.exe -ArgumentList "/c Dism.exe /Online /Cleanup-Image /RestoreHealth & pause" -Verb RunAs
        }

        return
    }

    if ($Argument -eq "/ScanHealth") {
        Write-Host "This will open a new window to run DISM ScanHealth." -ForegroundColor Yellow
        Write-Host "This process can take some time." -ForegroundColor Yellow
        Start-Process cmd.exe -ArgumentList "/c Dism.exe /Online /Cleanup-Image /ScanHealth & pause" -Verb RunAs

        $repairNow = Read-Host "DISM ScanHealth complete. Do you want to run RestoreHealth now? (y/n)"
        if ($repairNow -eq 'y') {
            Start-DismScan -Argument "/RestoreHealth"
        }

        return
    }

    Write-Host "This will open a new window to run DISM with the $Argument switch." -ForegroundColor Yellow
    Write-Host "This process can take some time." -ForegroundColor Yellow
    Start-Process cmd.exe -ArgumentList "/c Dism.exe /Online /Cleanup-Image $Argument & pause" -Verb RunAs
}

function Get-DISMRepairMethod {
    do {
        Write-Host "Select the DISM RestoreHealth repair method:" -ForegroundColor Yellow
        Write-Host "  1. Online repair (default Windows Update / configured source)"
        Write-Host "  2. ISO repair (local or downloaded Windows ISO source)"
        $choice = Read-Host "Enter 1 or 2"
        switch ($choice) {
            '1' { return 'Online' }
            '2' { return 'ISO' }
            default { Write-Warning "Invalid selection; please enter 1 or 2." }
        }
    } while ($true)
}

function Show-FilePickerDialog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$Title = "Select File",
        
        [Parameter(Mandatory=$false)]
        [string]$Filter = "All Files (*.*)|*.*",
        
        [Parameter(Mandatory=$false)]
        [string]$InitialDirectory = $env:UserProfile
    )
    
    try {
        # Load Windows Forms assembly
        Add-Type -AssemblyName System.Windows.Forms
        
        $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
        $openFileDialog.Title = $Title
        $openFileDialog.Filter = $Filter
        $openFileDialog.InitialDirectory = $InitialDirectory
        $openFileDialog.CheckFileExists = $true
        $openFileDialog.CheckPathExists = $true
        
        $result = $openFileDialog.ShowDialog()
        
        if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
            return $openFileDialog.FileName
        }
        else {
            return $null
        }
    }
    catch {
        Write-Error "File picker dialog failed: $_"
        # Fallback to manual text entry
        Write-Host "File picker unavailable. Please enter the ISO file path manually:" -ForegroundColor Yellow
        $manualPath = Read-Host "Enter full path to ISO file"
        return $manualPath
    }
}

function Get-DISMRepairMethod {
    do {
        Write-Host "Select the DISM RestoreHealth repair method:" -ForegroundColor Yellow
        Write-Host "  1. Online repair (default Windows Update / configured source)"
        Write-Host "  2. ISO repair (local or downloaded Windows ISO source)"
        $choice = Read-Host "Enter 1 or 2"
        switch ($choice) {
            '1' { return 'Online' }
            '2' { return 'ISO' }
            default { Write-Warning "Invalid selection; please enter 1 or 2." }
        }
    } while ($true)
}

function Get-RepairISOPath {
    $isoMap = @{
        '10-22H2' = 'https://networkpeopleinc.sharepoint.com/sites/NPI-External/_layouts/15/download.aspx?share=EXYvembfJz1KvgXctVfa76ABCz5aowkfUznvhg6e8vrruA&e=eaJ1aB'
        '11-23H2' = 'https://networkpeopleinc.sharepoint.com/sites/NPI-External/_layouts/15/download.aspx?share=EfdQEs-VpLNGgHHhfXibEQ8BIGElBVW53x_k-vUMs6JOQw&e=dR4GuU'
        '11-24H2' = 'https://networkpeopleinc.sharepoint.com/sites/NPI-External/_layouts/15/download.aspx?share=EfHJfrP5Og5HmJYtwWRmUjABogqLNb_htumy92S5f8dxGg&e=HMeacl'
        '11-25H2' = 'https://integristech-my.sharepoint.com/personal/aaron_pleus_integrisit_com/_layouts/15/download.aspx?share=IQBl8nXUkBlZT5LlvumdTuGmARK7h78TJeR6-qNzEI9u7NQ'
    }

    $options = @(
        @{ Number = 1; Label = 'Windows 10 22H2 (Build 19045)'; Key = '10-22H2' }
        @{ Number = 2; Label = 'Windows 11 23H2 (Build 22631)'; Key = '11-23H2' }
        @{ Number = 3; Label = 'Windows 11 24H2 (Build 26100)'; Key = '11-24H2' }
        @{ Number = 4; Label = 'Windows 11 25H2 (Build 26200)'; Key = '11-25H2' }
    )

    $currentOS = Get-CimInstance Win32_OperatingSystem
    Write-Host "Current system build: $($currentOS.Caption) (Build $($currentOS.BuildNumber))" -ForegroundColor Cyan
    Write-Host "Choose the Windows ISO source for DISM repair:" -ForegroundColor Yellow
    foreach ($opt in $options) {
        Write-Host "  $($opt.Number). $($opt.Label)"
    }

    $selection = Read-Host "Enter 1-4"
    $chosen = $options | Where-Object { $_.Number -eq [int]$selection }
    if (-not $chosen) {
        Write-Warning "Invalid selection."
        return $null
    }

    $tempIsoPath = Join-Path -Path $env:TEMP -ChildPath "RepairSource_$($chosen.Key).iso"
    
    $haveLocalISO = Read-Host "Do you already have a local ISO file for $($chosen.Label)? (y/n)"
    if ($haveLocalISO -eq 'y') {
        # First check if the downloaded file exists for this version
        if (Test-Path $tempIsoPath) {
            $existingFile = Get-Item $tempIsoPath
            $sizeGB = [math]::Round($existingFile.Length / 1GB, 2)
            Write-Host "Found previously downloaded ISO: $tempIsoPath ($sizeGB GB)" -ForegroundColor Yellow
            
            $useDownloaded = Read-Host "Use this file? (y/n)"
            if ($useDownloaded -eq 'y') {
                Write-Host "Using downloaded ISO: $tempIsoPath" -ForegroundColor Green
                return $tempIsoPath
            }
        }
        
        # If not using the downloaded file, prompt for manual file selection
        Write-Host "Opening file picker to select your ISO file..." -ForegroundColor Cyan
        $localPath = Show-FilePickerDialog -Title "Select Windows ISO File" -Filter "ISO Files (*.iso)|*.iso|All Files (*.*)|*.*"
        
        if (-not $localPath) {
            Write-Host "File selection cancelled." -ForegroundColor Yellow
            return $null
        }
        
        if (Test-Path $localPath) {
            Write-Host "Using local ISO: $localPath" -ForegroundColor Green
            return $localPath
        }
        else {
            Write-Error "Local ISO path not found: $localPath"
            return $null
        }
    }

    $tempIsoPath = Join-Path -Path $env:TEMP -ChildPath "RepairSource_$($chosen.Key).iso"
    
    # Check if file already exists and ask user what to do
    if (Test-Path $tempIsoPath) {
        $existingFile = Get-Item $tempIsoPath
        $sizeGB = [math]::Round($existingFile.Length / 1GB, 2)
        Write-Host "Found existing ISO file: $tempIsoPath ($sizeGB GB)" -ForegroundColor Yellow
        
        $useExisting = Read-Host "Do you want to use this existing file? (y/n)"
        if ($useExisting -eq 'y') {
            Write-Host "Using existing downloaded ISO: $tempIsoPath" -ForegroundColor Green
            return $tempIsoPath
        }
        else {
            Write-Host "Deleting existing file and downloading fresh..." -ForegroundColor Cyan
            Remove-Item -Path $tempIsoPath -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Host "Downloading the selected ISO to $tempIsoPath" -ForegroundColor Cyan
    Write-Host "Note: Large ISO files may take 10-30+ minutes depending on connection speed." -ForegroundColor Yellow
    
    $downloadSuccess = $false
    $downloadErrors = @()
    $maxRetries = 3
    $retryCount = 0

    # Try BITS transfer first (better for large files and resumes on failure)
    while (-not $downloadSuccess -and $retryCount -lt $maxRetries) {
        try {
            Write-Host "Attempting BITS transfer (Attempt $($retryCount + 1) of $maxRetries)..." -ForegroundColor Cyan
            $bitsJob = Start-BitsTransfer -Source $isoMap[$chosen.Key] -Destination $tempIsoPath -Asynchronous -DisplayName "ISORepairDownload" -ErrorAction Stop
            
            # Monitor progress
            do {
                Start-Sleep -Seconds 5
                $bitsJob = Get-BitsTransfer -JobId $bitsJob.JobId
                if ($bitsJob.BytesTotal -gt 0) {
                    $percent = [math]::Round(($bitsJob.BytesTransferred / $bitsJob.BytesTotal) * 100, 2)
                    $gb = [math]::Round($bitsJob.BytesTransferred / 1GB, 2)
                    $totalGB = [math]::Round($bitsJob.BytesTotal / 1GB, 2)
                    Write-Host "Download Progress: $percent% ($gb GB / $totalGB GB)" -ForegroundColor Cyan
                }
            } while ($bitsJob.JobState -eq 'Transferring' -or $bitsJob.JobState -eq 'Connecting')

            if ($bitsJob.JobState -eq 'Transferred') {
                Complete-BitsTransfer -BitsJob $bitsJob
                Write-Host "Download complete." -ForegroundColor Green
                $downloadSuccess = $true
            }
            elseif ($bitsJob.JobState -eq 'Error' -or $bitsJob.JobState -eq 'TransientError') {
                $downloadErrors += "BITS Error: $($bitsJob.ErrorInformation.ErrorDescription)"
                Remove-BitsTransfer -BitsJob $bitsJob -ErrorAction SilentlyContinue
                Remove-Item -Path $tempIsoPath -Force -ErrorAction SilentlyContinue
                $retryCount++
                if ($retryCount -lt $maxRetries) {
                    Write-Host "Download interrupted. Retrying in 10 seconds..." -ForegroundColor Yellow
                    Start-Sleep -Seconds 10
                }
            }
            else {
                $downloadErrors += "BITS unexpected state: $($bitsJob.JobState)"
                Remove-BitsTransfer -BitsJob $bitsJob -ErrorAction SilentlyContinue
                Remove-Item -Path $tempIsoPath -Force -ErrorAction SilentlyContinue
                $retryCount++
            }
        }
        catch {
            $downloadErrors += "BITS: $($_.Exception.Message)"
            Remove-Item -Path $tempIsoPath -Force -ErrorAction SilentlyContinue
            $retryCount++
            if ($retryCount -lt $maxRetries) {
                Write-Host "BITS transfer failed. Retrying in 10 seconds..." -ForegroundColor Yellow
                Start-Sleep -Seconds 10
            }
        }
    }

    # Fallback to Invoke-WebRequest if BITS fails
    if (-not $downloadSuccess -and $retryCount -ge $maxRetries) {
        Write-Host "BITS transfer exhausted retries. Trying Invoke-WebRequest as fallback..." -ForegroundColor Yellow
        $retryCount = 0
        
        while (-not $downloadSuccess -and $retryCount -lt $maxRetries) {
            try {
                Write-Host "Attempting Invoke-WebRequest (Attempt $($retryCount + 1) of $maxRetries)..." -ForegroundColor Cyan
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
                Invoke-WebRequest -Uri $isoMap[$chosen.Key] -OutFile $tempIsoPath -UseBasicParsing -TimeoutSec 600 -ErrorAction Stop
                Write-Host "Download complete." -ForegroundColor Green
                $downloadSuccess = $true
            }
            catch {
                $downloadErrors += "WebRequest: $($_.Exception.Message)"
                Remove-Item -Path $tempIsoPath -Force -ErrorAction SilentlyContinue
                $retryCount++
                if ($retryCount -lt $maxRetries) {
                    Write-Host "Download failed. Retrying in 10 seconds..." -ForegroundColor Yellow
                    Start-Sleep -Seconds 10
                }
            }
        }
    }

    if (-not $downloadSuccess) {
        Write-Error "Failed to download ISO after $maxRetries attempts. Details:`n$($downloadErrors -join "`n")"
        if (Test-Path $tempIsoPath) {
            Remove-Item -Path $tempIsoPath -Force -ErrorAction SilentlyContinue
        }
        return $null
    }

    return $tempIsoPath
}

function Mount-ISO {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$isoPath
    )
    try {
        Write-Verbose "Attempting to mount ISO: $isoPath"
        $mountResult = Mount-DiskImage -ImagePath $isoPath -PassThru
        $driveLetter = ($mountResult | Get-Volume).DriveLetter
        if ($driveLetter) {
            Write-Verbose "ISO mounted successfully. Drive letter: $driveLetter"
            return $driveLetter
        } else {
            throw "Failed to get drive letter after mounting ISO."
        }
    } catch {
        Write-Error "Failed to mount ISO: $_"
        throw $_
    }
}

function Reset-RegistryKeys {
    Write-Host "This will remove Windows Update-related registry keys and values from HKCU and HKLM." -ForegroundColor Yellow
    Write-Host "It affects Windows Update policy and configuration entries only." -ForegroundColor Yellow
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
    do {
        Clear-Host
        Write-Host "--- Manage Windows Updates ---" -ForegroundColor Green
        Write-Host "1. PowerShell (PSWindowsUpdate)"
        Write-Host "2. GUI (WUAManager)"
        Write-Host "q. Return to main menu"
        $choice = Read-Host "Select an option"

        switch ($choice) {
            "1" { Manage-WindowsUpdatesPowerShell }
            "2" { Run-WUAManager }
            "q" { break }
            default { Write-Warning "Invalid option. Please try again." }
        }
    } while ($choice -ne 'q')
}

function Manage-WindowsUpdatesPowerShell {
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

function Run-WUAManager {
    Write-Host "Downloading and launching WUAManager..." -ForegroundColor Cyan
    $downloadUrl = "https://www.carifred.com/wau_manager/WAUManager.exe"
    $outputPath = Join-Path -Path $env:TEMP -ChildPath "WUAManager.exe"

    try {
        if (Test-Path $outputPath) {
            Remove-Item -Path $outputPath -Force -ErrorAction SilentlyContinue
        }

        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

        $downloadSuccess = $false
        $downloadErrors = @()

        try {
            Invoke-WebRequest -Uri $downloadUrl -OutFile $outputPath -ErrorAction Stop
            $downloadSuccess = $true
        }
        catch {
            $downloadErrors += "Invoke-WebRequest: $($_.Exception.Message)"
            Write-Warning "Invoke-WebRequest failed; trying BITS transfer as fallback..."
        }

        if (-not $downloadSuccess) {
            try {
                Start-BitsTransfer -Source $downloadUrl -Destination $outputPath -ErrorAction Stop
                $downloadSuccess = $true
            }
            catch {
                $downloadErrors += "BITS: $($_.Exception.Message)"
            }
        }

        if (-not $downloadSuccess -or -not (Test-Path $outputPath) -or (Get-Item $outputPath).Length -eq 0) {
            throw "Unable to download WUAManager. Details: $($downloadErrors -join ' | ')"
        }

        Write-Host "Downloaded WUAManager to $outputPath" -ForegroundColor Green
        Start-Process -FilePath $outputPath -ErrorAction Stop
    }
    catch {
        Write-Error "Failed to download or launch WUAManager."
        Write-Error $_.Exception.Message
        if ($downloadErrors) {
            Write-Error "Download diagnostics: $($downloadErrors -join ' ; ')"
        }
        Write-Error "If this continues, try downloading WUAManager manually from $downloadUrl."
    }
}

function Start-ClearDiskInfo {
    Write-Host "Downloading and launching Clear Disk Info..." -ForegroundColor Cyan
    $downloadUrl = "https://www.carifred.com/cleardiskinfo/ClearDiskInfo.exe"
    $outputPath = Join-Path -Path $env:TEMP -ChildPath "ClearDiskInfo.exe"

    try {
        if (Test-Path $outputPath) {
            Remove-Item -Path $outputPath -Force -ErrorAction SilentlyContinue
        }

        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

        $downloadSuccess = $false
        $downloadErrors = @()

        try {
            Invoke-WebRequest -Uri $downloadUrl -OutFile $outputPath -ErrorAction Stop
            $downloadSuccess = $true
        }
        catch {
            $downloadErrors += "Invoke-WebRequest: $($_.Exception.Message)"
            Write-Warning "Invoke-WebRequest failed; trying BITS transfer as fallback..."
        }

        if (-not $downloadSuccess) {
            try {
                Start-BitsTransfer -Source $downloadUrl -Destination $outputPath -ErrorAction Stop
                $downloadSuccess = $true
            }
            catch {
                $downloadErrors += "BITS: $($_.Exception.Message)"
            }
        }

        if (-not $downloadSuccess -or -not (Test-Path $outputPath) -or (Get-Item $outputPath).Length -eq 0) {
            throw "Unable to download Clear Disk Info. Details: $($downloadErrors -join ' | ')"
        }

        Write-Host "Downloaded Clear Disk Info to $outputPath" -ForegroundColor Green
        Start-Process -FilePath $outputPath -ErrorAction Stop
    }
    catch {
        Write-Error "Failed to download or launch Clear Disk Info."
        Write-Error $_.Exception.Message
        if ($downloadErrors) {
            Write-Error "Download diagnostics: $($downloadErrors -join ' ; ')"
        }
        Write-Error "If this continues, try downloading Clear Disk Info manually from $downloadUrl."
    }
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
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Microsoft%20Windows/General%20Troubleshooting/One_Time_Reboot_Scheduler.ps1'))
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
$systemDetails = Test-SupportedOS

# 3. Main script loop
do {
    Show-MainMenu -systemDetails $systemDetails
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
        "21" { Show-ChkdskResults }
        "22" { Test-DriveDirtyBit }
        "23" { Start-ClearDiskInfo }
        "q"  { Write-Host "Exiting script." }
        default { Write-Warning "Invalid option. Please try again." }
    }

    if ($selection -ne 'q') {
        Pause-And-Return
    }

} while ($selection -ne 'q')