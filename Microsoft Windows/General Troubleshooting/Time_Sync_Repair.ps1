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

# Helper functions for time privilege and policy checks
function Resolve-SidToName ($SidString) {
    $SidString = $SidString.Trim()
    $CleanSid = $SidString.TrimStart('*')
    if ($CleanSid -match '^S-\d-\d+(-\d+)+$') {
        try {
            $SidObj = [System.Security.Principal.SecurityIdentifier]::new($CleanSid)
            return $SidObj.Translate([System.Security.Principal.NTAccount]).Value
        } catch {
            return $SidString
        }
    }
    return $SidString
}

function Check-GroupMembership ($GroupsWithAccess, $UserName) {
    $HasAccess = $false
    foreach ($Group in $GroupsWithAccess) {
        $LocalGroupName = $Group -replace '.*\\', ''
        try {
            $Members = Get-LocalGroupMember -Group $LocalGroupName -ErrorAction Stop
            if ($Members.Name -contains $UserName) {
                Write-Host "  [+] User is a member of '$Group', granting them access." -ForegroundColor Green
                $HasAccess = $true
            }
        } catch {
            # Group might be a domain group or unresolvable locally; skip silently
        }
    }
    return $HasAccess
}

function Get-TargetUserSid ($TargetUser) {
    if (-not $TargetUser) { return $null }

    $SearchName = ($TargetUser -split '\\|@') | Select-Object -Last 1

    try {
        $NTAccount = New-Object System.Security.Principal.NTAccount($TargetUser)
        $UserSID = $NTAccount.Translate([System.Security.Principal.SecurityIdentifier]).Value
        Write-Host "[+] SID resolved via standard lookup: $UserSID" -ForegroundColor Green
        return $UserSID
    } catch {
        Write-Warning "Could not resolve SID for $TargetUser via standard lookup."
        Write-Host "[!] Attempting to find SID in local user profiles for Azure AD / cached account..." -ForegroundColor Yellow

        try {
            $Profiles = Get-CimInstance Win32_UserProfile -ErrorAction Stop
            $MatchedProfile = $Profiles | Where-Object { $_.LocalPath -match "\\$([regex]::Escape($SearchName))($|\\)" }
            if ($MatchedProfile) {
                $UserSID = $MatchedProfile[0].SID
                Write-Host "[+] Found Azure AD SID in local profiles: $UserSID" -ForegroundColor Green
                return $UserSID
            }
        } catch {
            # Ignore profile lookup failures and continue returning $null
        }

        Write-Warning "Could not find a local profile or SID for $TargetUser."
        Write-Warning "If this user has never logged into this machine, they will not have explicit direct rights here."
        return $null
    }
}

function Get-LocalUserRightsLines {
    $TempFile = "$env:TEMP\UserRights.txt"
    secedit /export /areas USER_RIGHTS /cfg $TempFile | Out-Null
    $SystemTimeLine = Get-Content $TempFile | Select-String -Pattern "^SeSystemtimePrivilege"
    $TimeZoneLine = Get-Content $TempFile | Select-String -Pattern "^SeTimeZonePrivilege"
    Remove-Item -Path $TempFile -Force
    return @{ SystemTime = $SystemTimeLine; TimeZone = $TimeZoneLine }
}

function Check-PolicyTimeLocks {
    Write-Host "`n--- Checking GPO / Intune UI & Auto-Sync Policies ---" -ForegroundColor Cyan

    $TimeLocked = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\System" -Name "DisableDateTime" -ErrorAction SilentlyContinue
    if ($TimeLocked.DisableDateTime -eq 1) {
        Write-Host "[-] GPO/Intune is actively BLOCKING users from changing the Date/Time UI." -ForegroundColor Red
    } else {
        Write-Host "[+] No GPO/Intune UI blocks detected for Date/Time." -ForegroundColor Green
    }

    $ZoneLocked = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Control Panel\International" -Name "PreventUserFromChangingTimezone" -ErrorAction SilentlyContinue
    if ($ZoneLocked.PreventUserFromChangingTimezone -eq 1) {
        Write-Host "[-] GPO/Intune is actively BLOCKING users from changing the Time Zone UI." -ForegroundColor Red
    } else {
        Write-Host "[+] No GPO/Intune UI blocks detected for Time Zone." -ForegroundColor Green
    }

    $AutoTime = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters" -Name "Type" -ErrorAction SilentlyContinue
    if ($AutoTime.Type -eq "NTP" -or $AutoTime.Type -eq "NT5DS") {
        Write-Host "[!] Time is set to synchronize automatically (NTP or Domain Sync)." -ForegroundColor Yellow
    }

    $AutoTimeZone = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\tzautoupdate" -Name "Start" -ErrorAction SilentlyContinue
    if ($AutoTimeZone.Start -eq 3) {
        Write-Host "[!] Time Zone is set to update automatically via Location Services." -ForegroundColor Yellow
    } elseif ($AutoTimeZone.Start -eq 4) {
        Write-Host "[+] Time Zone auto-update is explicitly disabled." -ForegroundColor Green
    }

    # --- Location Services checks (affects Auto-Time Zone) ---
    Write-Host "`n--- Checking Location Services Policies ---" -ForegroundColor Cyan

    $AppLocationPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy"
    $AppLocationName = "LetAppsAccessLocation"
    $AppLocation = Get-ItemProperty -Path $AppLocationPath -Name $AppLocationName -ErrorAction SilentlyContinue

    if ($null -eq $AppLocation -or $null -eq $AppLocation.$AppLocationName) {
        Write-Host "[+] 'Let Apps Access Location' is NOT configured by policy (Key Missing). Setting is User Controlled." -ForegroundColor Green
    } else {
        $Value = $AppLocation.$AppLocationName
        if ($Value -eq 0) {
            Write-Host "[+] 'Let Apps Access Location' is enforced as: USER IN CONTROL (Value: 0)" -ForegroundColor Green
        } elseif ($Value -eq 1) {
            Write-Host "[+] 'Let Apps Access Location' is enforced as: FORCE ALLOW (Value: 1)" -ForegroundColor Green
        } elseif ($Value -eq 2) {
            Write-Host "[-] 'Let Apps Access Location' is enforced as: FORCE DENY (Value: 2). Auto-Time Zone will fail." -ForegroundColor Red
        } else {
            Write-Host "[?] 'Let Apps Access Location' is set to an unknown value ($Value)." -ForegroundColor Yellow
        }
    }
}

function Evaluate-AzureADUserPermission {
    param (
        [array]$GrantedGroups,
        [string]$TargetUser
    )
    $HasAccess = $false
    $StrippedUsername = $TargetUser -replace "^AzureAD\\",""

    # Check 1: 'Users' group (BUILTIN\Users) grants access to all authenticated users
    if ($GrantedGroups -match "Users") {
        Write-Host "  [+] [$TargetUser] automatically has access because the 'BUILTIN\Users' group is granted this right." -ForegroundColor Green
        $HasAccess = $true
    }

    # Check 2: 'Administrators' group
    if (-not $HasAccess -and $GrantedGroups -match "Administrators") {
        $Admins = Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue
        $IsDirectAdmin = $Admins | Where-Object { $_.Name -match $StrippedUsername }
        if ($IsDirectAdmin) {
            Write-Host "  [+] [$TargetUser] has access because they are explicitly listed in the local 'Administrators' group." -ForegroundColor Green
            $HasAccess = $true
        } else {
            Write-Host "  [!] The 'Administrators' group has access, but [$TargetUser] is not explicitly listed in it." -ForegroundColor Yellow
            Write-Host "      (Note: If they receive Admin rights via an Intune Cloud Group SID, PowerShell cannot resolve that offline)." -ForegroundColor DarkYellow
        }
    }

    if (-not $HasAccess) {
        Write-Host "  [-] [$TargetUser] does NOT appear to have access." -ForegroundColor Red
    }

    return $HasAccess
}

function Show-UserTimePrivilegeReport {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  User Time Privilege & Policy Review" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan

    $TargetUser = Read-Host "Enter the user to analyze for time privileges (press Enter for current user). Use 'AzureAD\user@domain.com' for Azure AD users."
    if (-not $TargetUser) {
        $TargetUser = if ($env:USERDOMAIN) { "$env:USERDOMAIN\$env:USERNAME" } else { $env:USERNAME }
    }

    Write-Host "Analyzing Time Privileges for: $TargetUser" -ForegroundColor Cyan
    Write-Host "------------------------------------------------" -ForegroundColor Cyan

    $UserSID = Get-TargetUserSid $TargetUser
    if ($UserSID) {
        Write-Host "Resolved SID: $UserSID" -ForegroundColor White
    }

    $rights = Get-LocalUserRightsLines
    foreach ($priv in @(
        @{ Label = "CHANGE SYSTEM TIME"; Line = $rights.SystemTime; PrivName = "SeSystemtimePrivilege" },
        @{ Label = "CHANGE TIME ZONE"; Line = $rights.TimeZone; PrivName = "SeTimeZonePrivilege" }
    )) {
        Write-Host "`n[ $($priv.Label) ] ($($priv.PrivName))" -ForegroundColor Yellow
        if ($priv.Line) {
            $Entries = ($priv.Line.Line -split "=")[1].Split(",") | ForEach-Object { $_.Trim() }
            $Resolved = $Entries | ForEach-Object { Resolve-SidToName $_ }

            Write-Host "Granted to:" -ForegroundColor White
            $Resolved | ForEach-Object { Write-Host "  - $_" -ForegroundColor White }

            Write-Host "Evaluation:" -ForegroundColor White
            $DirectAccess = ($UserSID -ne $null -and $Entries -contains "*$UserSID")
            if ($DirectAccess) {
                Write-Host "  [+] User is explicitly granted this privilege." -ForegroundColor Green
            } else {
                $GroupAccess = Check-GroupMembership -GroupsWithAccess $Resolved -UserName $TargetUser
                if ($GroupAccess) {
                    Write-Host "  [+] User is a member of a granted group." -ForegroundColor Green
                } else {
                    # If the target is an AzureAD account, perform additional heuristics
                    $AzureAccess = $false
                    try {
                        $AzureAccess = Evaluate-AzureADUserPermission -GrantedGroups $Resolved -TargetUser $TargetUser
                    } catch {
                        # Ignore evaluation errors
                    }

                    if ($AzureAccess) {
                        Write-Host "  [+] Access granted via AzureAD/group evaluation." -ForegroundColor Green
                    } else {
                        Write-Host "  [-] User does not appear to have rights to change this setting locally." -ForegroundColor Red
                    }
                }
            }
        } else {
            Write-Host "  [-] No accounts are granted this privilege in the local policy." -ForegroundColor Red
        }
    }

    Check-PolicyTimeLocks
    Write-Host ""
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
Write-Host "4. Review user time privileges and policy locks" -ForegroundColor White
Write-Host "5. Exit" -ForegroundColor White
$choice = Read-Host "Enter choice (1, 2, 3, 4, or 5)"

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
    Show-UserTimePrivilegeReport
} elseif ($choice -eq '5') {
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