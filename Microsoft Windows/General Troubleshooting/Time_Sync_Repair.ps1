<# (Time_Sync_Repair.ps1) :: (Revision 1)/Aaron Pleus, (10/28/2025)

   This script, like all scripts developed by Aaron Pleus, unless otherwise explicitly stated, is the copyrighted property of Aaron Pleus.;
   it may not be shared, sold, or distributed whole or in part, even with modifications applied, for any reason. this includes on reddit, on discord, or as part of other RMM tools.
   	
   The moment you edit this script it becomes your own risk and Aaron Pleus will not provide assistance with it.#>

# Requires Administrator privileges

# Check if running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: This script must be run as Administrator!" -ForegroundColor Red
    Write-Host "Please right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
    pause
    exit
}

$restart = $true
do {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  Domain and Time Sync Configuration" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan

# Check if computer is domain joined
Write-Host "Checking domain membership..." -ForegroundColor Yellow
$computerSystem = Get-WmiObject -Class Win32_ComputerSystem
$isDomainJoined = $computerSystem.PartOfDomain

if ($isDomainJoined) {
    Write-Host "`n[DOMAIN STATUS]" -ForegroundColor Green
    Write-Host "Computer is DOMAIN JOINED" -ForegroundColor Green
    Write-Host "Domain: $($computerSystem.Domain)" -ForegroundColor White
    
    # Get logon server (PDC/DC)
    $logonServer = $env:LOGONSERVER -replace '\\', ''
    Write-Host "Logon Server: $logonServer" -ForegroundColor White
    
    # Try to get PDC
    try {
        $domain = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
        $pdc = $domain.PdcRoleOwner.Name
        Write-Host "PDC Emulator: $pdc" -ForegroundColor White
    } catch {
        Write-Host "PDC Emulator: Unable to retrieve" -ForegroundColor Yellow
    }
} else {
    Write-Host "`n[DOMAIN STATUS]" -ForegroundColor Yellow
    Write-Host "Computer is NOT domain joined (Workgroup)" -ForegroundColor Yellow
    Write-Host "Workgroup: $($computerSystem.Workgroup)" -ForegroundColor White
}

# Show current time zone
Write-Host "`n[TIME ZONE]" -ForegroundColor Cyan
$currentTimeZone = Get-TimeZone
Write-Host "Current Time Zone: $($currentTimeZone.DisplayName)" -ForegroundColor White
Write-Host "Time Zone ID: $($currentTimeZone.Id)" -ForegroundColor White
Write-Host "UTC Offset: $($currentTimeZone.BaseUtcOffset)" -ForegroundColor White

# Check Group Policy Time Settings
Write-Host "`n[GROUP POLICY TIME SETTINGS]" -ForegroundColor Cyan
$gpTimeConfigured = $false
$ntpServerGP = $null
$typeGP = $null

try {
    # Check if Group Policy has configured time settings
    $w32timeGPPath = "HKLM:\SOFTWARE\Policies\Microsoft\W32Time\Parameters"
    $timeProvidersGPPath = "HKLM:\SOFTWARE\Policies\Microsoft\W32Time\TimeProviders\NtpClient"
    
    if (Test-Path $w32timeGPPath) {
        $ntpServerGP = (Get-ItemProperty -Path $w32timeGPPath -Name "NtpServer" -ErrorAction SilentlyContinue).NtpServer
        $typeGP = (Get-ItemProperty -Path $w32timeGPPath -Name "Type" -ErrorAction SilentlyContinue).Type
    }
    
    if ($ntpServerGP -or $typeGP) {
        $gpTimeConfigured = $true
        Write-Host "Group Policy IS configuring time settings:" -ForegroundColor Green
        if ($ntpServerGP) { Write-Host "  NTP Server (GP): $ntpServerGP" -ForegroundColor White }
        if ($typeGP) { 
            $typeDescription = switch ($typeGP) {
                "NoSync" { "No Sync" }
                "NTP" { "NTP" }
                "NT5DS" { "NT5DS (Domain Hierarchy)" }
                "AllSync" { "All Sync" }
                default { $typeGP }
            }
            Write-Host "  Type (GP): $typeDescription" -ForegroundColor White 
        }
    } else {
        Write-Host "Group Policy is NOT configuring time settings" -ForegroundColor Yellow
        Write-Host "Time configuration is set locally" -ForegroundColor White
    }
} catch {
    Write-Host "Unable to determine Group Policy settings" -ForegroundColor Yellow
}

# Get current time configuration
Write-Host "`n[CURRENT TIME CONFIGURATION]" -ForegroundColor Cyan
$w32tm = w32tm /query /status 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host $w32tm -ForegroundColor White
} else {
    Write-Host "Windows Time service may not be running." -ForegroundColor Yellow
    Write-Host "Current system time: $(Get-Date)" -ForegroundColor White
}

# Get time source configuration
Write-Host "`n[TIME SOURCE]" -ForegroundColor Cyan
$timeSource = w32tm /query /source 2>&1
Write-Host "Current Source: $timeSource" -ForegroundColor White

# Get registry time server setting (local config)
try {
    $localConfigPath = "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters"
    $localNtpServer = (Get-ItemProperty -Path $localConfigPath -Name "NtpServer" -ErrorAction SilentlyContinue).NtpServer
    $localType = (Get-ItemProperty -Path $localConfigPath -Name "Type" -ErrorAction SilentlyContinue).Type
    
    if ($localNtpServer) {
        Write-Host "Local NTP Server Config: $localNtpServer" -ForegroundColor White
    }
    if ($localType) {
        Write-Host "Local Type Config: $localType" -ForegroundColor White
    }
} catch {
    # Silent catch
}

# Prompt for action
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "What would you like to do?" -ForegroundColor Yellow
Write-Host "1. Change time sync settings" -ForegroundColor White
Write-Host "2. Force sync with current settings" -ForegroundColor White
Write-Host "3. Set time zone" -ForegroundColor White
Write-Host "4. Exit" -ForegroundColor White
$choice = Read-Host "Enter choice (1, 2, 3, or 4)"

if ($choice -eq '1') {
    # Change time sync settings
    Write-Host "`nSelect time source:" -ForegroundColor Yellow
    
    if ($isDomainJoined) {
        Write-Host "1. Use Domain Hierarchy (Group Policy/NT5DS)" -ForegroundColor White
        Write-Host "2. Specific Domain Controller (Manual NTP)" -ForegroundColor White
        Write-Host "3. Internet Time Server" -ForegroundColor White
        $subChoice = Read-Host "Enter choice (1, 2, or 3)"
    } else {
        Write-Host "1. Specific Domain Controller (Manual NTP)" -ForegroundColor White
        Write-Host "2. Internet Time Server" -ForegroundColor White
        $subChoice = Read-Host "Enter choice (1 or 2)"
        # Adjust choice for workgroup computers
        if ($subChoice -eq '1') { $subChoice = '2' }
        elseif ($subChoice -eq '2') { $subChoice = '3' }
    }
    if ($subChoice -eq '1') {
        # Domain Hierarchy / Group Policy option
        Write-Host "`nConfiguring time sync to use Domain Hierarchy (NT5DS)..." -ForegroundColor Yellow
        Write-Host "This will sync with the domain controller according to domain policy" -ForegroundColor White
        
        # Remove any GP override by clearing local policies if they exist
        $w32timeGPPath = "HKLM:\SOFTWARE\Policies\Microsoft\W32Time\Parameters"
        if (Test-Path $w32timeGPPath) {
            Write-Host "Note: Group Policy settings detected. Local changes may be overridden by GP." -ForegroundColor Yellow
        }
        
        # Stop the time service
        Stop-Service w32time -ErrorAction SilentlyContinue
        
        # Configure for domain hierarchy
        w32tm /config /syncfromflags:domhier /update
        
        # Start the service
        Start-Service w32time
        
        Write-Host "Configuration completed - Using domain hierarchy." -ForegroundColor Green
        
    } elseif ($subChoice -eq '2') {
        # Specific Domain Controller option
        $dc = Read-Host "`nEnter Domain Controller name or IP address"
        
        Write-Host "`nConfiguring time sync with Domain Controller: $dc" -ForegroundColor Yellow
        
        # Stop the time service
        Stop-Service w32time -ErrorAction SilentlyContinue
        
        # Configure for NTP
        w32tm /config /syncfromflags:manual /manualpeerlist:"$dc" /reliable:yes /update
        
        # Start the service
        Start-Service w32time
        
        Write-Host "Configuration completed." -ForegroundColor Green
        
    } elseif ($subChoice -eq '3') {
        # Internet time option
        Write-Host "`nConfiguring time sync with Internet time servers..." -ForegroundColor Yellow
        
        # Stop the time service
        Stop-Service w32time -ErrorAction SilentlyContinue
        
        # Configure for Internet time (NTP)
        w32tm /config /syncfromflags:manual /manualpeerlist:"time.windows.com,0x9 time.nist.gov,0x9" /reliable:yes /update
        
        # Set service to automatic
        Set-Service w32time -StartupType Automatic
        
        # Start the service
        Start-Service w32time
        
        Write-Host "Configuration completed." -ForegroundColor Green
        
    } else {
        Write-Host "Invalid choice. No changes made." -ForegroundColor Red
        pause
        exit
    }
    
    # Perform time resync after configuration changes
    Write-Host "`n[RESYNCING TIME]" -ForegroundColor Cyan
    Write-Host "Forcing time resynchronization..." -ForegroundColor Yellow
    
    $resync = w32tm /resync /rediscover 2>&1
    Write-Host $resync -ForegroundColor White
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`nTime resync completed successfully!" -ForegroundColor Green
    } else {
        Write-Host "`nTime resync command executed. Check output above for any errors." -ForegroundColor Yellow
    }
    
    # Show new status
    Write-Host "`n[NEW TIME STATUS]" -ForegroundColor Cyan
    Start-Sleep -Seconds 2
    $newStatus = w32tm /query /status 2>&1
    Write-Host $newStatus -ForegroundColor White
    
    # Show new time source
    Write-Host "`n[NEW TIME SOURCE]" -ForegroundColor Cyan
    $newTimeSource = w32tm /query /source 2>&1
    Write-Host "Current Source: $newTimeSource" -ForegroundColor White
    
} elseif ($choice -eq '2') {
    # Force sync with current settings
    Write-Host "`n[FORCING TIME SYNC]" -ForegroundColor Cyan
    Write-Host "Forcing time resynchronization with current settings..." -ForegroundColor Yellow
    
    $resync = w32tm /resync /rediscover 2>&1
    Write-Host $resync -ForegroundColor White
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`nTime resync completed successfully!" -ForegroundColor Green
    } else {
        Write-Host "`nTime resync command executed. Check output above for any errors." -ForegroundColor Yellow
    }
    
    # Show current status after sync
    Write-Host "`n[CURRENT TIME STATUS]" -ForegroundColor Cyan
    Start-Sleep -Seconds 2
    $currentStatus = w32tm /query /status 2>&1
    Write-Host $currentStatus -ForegroundColor White
    
    # Show current time source
    Write-Host "`n[CURRENT TIME SOURCE]" -ForegroundColor Cyan
    $currentTimeSource = w32tm /query /source 2>&1
    Write-Host "Current Source: $currentTimeSource" -ForegroundColor White
    
} elseif ($choice -eq '3') {
    # Set time zone
    Write-Host "`n[TIME ZONE SETTINGS]" -ForegroundColor Cyan
    
    # Show current time zone
    $currentTZ = Get-TimeZone
    Write-Host "Current Time Zone: $($currentTZ.DisplayName)" -ForegroundColor White
    Write-Host "Time Zone ID: $($currentTZ.Id)" -ForegroundColor White
    
    Write-Host "`nSelect time zone:" -ForegroundColor Yellow
    Write-Host "1. Eastern Time (EST/EDT)" -ForegroundColor White
    Write-Host "2. Central Time (CST/CDT)" -ForegroundColor White
    Write-Host "3. Mountain Time (MST/MDT)" -ForegroundColor White
    Write-Host "4. Pacific Time (PST/PDT)" -ForegroundColor White
    Write-Host "5. Alaska Time (AKST/AKDT)" -ForegroundColor White
    Write-Host "6. Hawaii-Aleutian Time (HST/HDT)" -ForegroundColor White
    Write-Host "7. Specify time zone manually" -ForegroundColor White
    Write-Host "8. Cancel" -ForegroundColor White
    
    $tzChoice = Read-Host "Enter choice (1-8)"
    
    $timeZoneId = $null
    
    switch ($tzChoice) {
        '1' { $timeZoneId = "Eastern Standard Time" }
        '2' { $timeZoneId = "Central Standard Time" }
        '3' { $timeZoneId = "Mountain Standard Time" }
        '4' { $timeZoneId = "Pacific Standard Time" }
        '5' { $timeZoneId = "Alaskan Standard Time" }
        '6' { $timeZoneId = "Hawaiian Standard Time" }
        '7' { 
            Write-Host "`nAvailable time zones:" -ForegroundColor Yellow
            Get-TimeZone | Select-Object Id, DisplayName | Format-Table -AutoSize
            $manualTZ = Read-Host "Enter the Time Zone ID from the list above"
            if ($manualTZ) {
                $timeZoneId = $manualTZ
            }
        }
        '8' { 
            Write-Host "Time zone change cancelled." -ForegroundColor Yellow
            $timeZoneId = $null
        }
        default {
            Write-Host "Invalid choice. Time zone change cancelled." -ForegroundColor Red
            $timeZoneId = $null
        }
    }
    
    if ($timeZoneId) {
        try {
            Set-TimeZone -Id $timeZoneId
            $newTZ = Get-TimeZone
            Write-Host "`nTime zone successfully changed to: $($newTZ.DisplayName)" -ForegroundColor Green
            Write-Host "New Time Zone ID: $($newTZ.Id)" -ForegroundColor White
            
            # Force time sync after time zone change
            Write-Host "`nForcing time synchronization after time zone change..." -ForegroundColor Yellow
            $resync = w32tm /resync /rediscover 2>&1
            Write-Host $resync -ForegroundColor White
            
        } catch {
            Write-Host "`nError setting time zone: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
} elseif ($choice -eq '4') {
    # Exit
    Write-Host "`nExiting without making changes..." -ForegroundColor Yellow
    $restart = $false
} else {
    Write-Host "`nInvalid choice. Exiting..." -ForegroundColor Red
    $restart = $false
}

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Script completed." -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    $restartChoice = Read-Host "Do you want to run the script again? (Y/N)"
    if ($restartChoice -eq 'Y' -or $restartChoice -eq 'y') {
        $restart = $true
        Clear-Host
    } else {
        $restart = $false
    }

} while ($restart)