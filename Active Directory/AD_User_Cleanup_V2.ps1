<#
.SYNOPSIS
    Interactive Active Directory cleanup and management utility.

.DESCRIPTION
    This PowerShell script provides an interactive menu-driven interface
    for performing common AD maintenance tasks including:
      * Viewing inventories of users and computers
      * Identifying inactive users/computers
      * Staging and deleting AD computer and user accounts
      * Searching for specially named accounts (e.g. 'test*') and removing them
      * Managing BitLocker recovery keys
      * Manual account search and object management
      * Configuring target 'pending deletion' OU and protected accounts
      * Enabling the AD Recycle Bin

    It records detailed audit logs at C:\Logs\AD_Cleanup_Audit.log and can
    export data under C:\ADCleanup_Exports (modifiable via variables).

    The script makes extensive use of the ActiveDirectory module and requires
    RSAT tools on a domain-joined workstation or domain controller.

.PARAMETER
    No parameters – run the script and interact with the menu. Options prompt
    for required input.

.EXAMPLE
    PS> .\AD_User_Cleanup V2.ps1
    Launches the menu. First choose option 7 to set the target OU where
    inactive accounts will be staged (or create a new one). Use option 8 to
    define accounts that should be excluded from cleanup (e.g. service or
    admin accounts). Navigate through the modules to audit, disable, move,
    rename, or delete objects.

.NOTES
    - Requires ActiveDirectory PowerShell module.
    - Should be run with an account having appropriate AD permissions.
    - The audit log records before/after state snapshots and any BitLocker
      recovery keys discovered.
    - CPU/Memory usage is minimal; user interaction uses Out-GridView where
      available.
#>

# --- CONFIGURATION ---
$LogFile = "C:\Logs\AD_Cleanup_Audit.log"
$ExportDir = "C:\ADCleanup_Exports"
$script:PendingDeletionOU = "NOT SET"
$script:ProtectedAccounts = @()  # Will be populated by user via menu 

# Ensure environment
if (!(Test-Path "C:\Logs")) { New-Item -ItemType Directory -Path "C:\Logs" -Force | Out-Null }
if (!(Test-Path $ExportDir)) { New-Item -ItemType Directory -Path $ExportDir -Force | Out-Null }
if (!(Get-Module -ListAvailable ActiveDirectory)) { 
    Write-Error "Active Directory module is required. Please install RSAT."
    return
}

# --- UI HELPER FUNCTIONS ---

Function Write-MenuHeader {
    Param([string]$Title, [string]$Color = "Green")
    cls
    Write-Host "=====================================================" -ForegroundColor $Color
    Write-Host "       $Title" -ForegroundColor $Color
    Write-Host "=====================================================" -ForegroundColor $Color
}

Function Write-MenuFooter {
    Param([string]$Color = "Green", [string]$BackChar = "B")
    Write-Host "-----------------------------------------------------" -ForegroundColor $Color
    if ($BackChar -eq "Q") {
        Write-Host "Q. Quit" -ForegroundColor Gray
    } else {
        Write-Host "$BackChar. Back" -ForegroundColor Gray
    }
}

Function Export-DataToCSV {
    Param([array]$Data, [string]$FileName)
    if (!$Data -or $Data.Count -eq 0) { return }
    
    if ((Read-Host "Export results to CSV? (Y/N)").ToUpper() -eq "Y") {
        $TimeStamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $FilePath = Join-Path $ExportDir "${FileName}_${TimeStamp}.csv"
        try {
            $Data | Export-Csv -Path $FilePath -NoTypeInformation
            Write-Host "Exported to: $FilePath" -ForegroundColor Green
            Start-Sleep 1
        } catch {
            Write-Host "Error exporting: $($_.Exception.Message)" -ForegroundColor Red
            Start-Sleep 2
        }
    }
}

Function Write-TargetOUStatus {
    # Displays the Current Target OU with consistent coloring: Red if NOT SET, Green if SET
    $StatusColor = if($script:PendingDeletionOU -eq "NOT SET") { "Red" } else { "Green" }
    Write-Host " CURRENT TARGET OU: " -NoNewline
    Write-Host $script:PendingDeletionOU -ForegroundColor $StatusColor
}

Function Write-ProtectedAccountsStatus {
    # Displays the Protected Accounts count with consistent coloring
    $StatusColor = if($script:ProtectedAccounts.Count -eq 0) { "Red" } else { "Green" }
    Write-Host " PROTECTED ACCOUNTS: " -NoNewline
    Write-Host "$($script:ProtectedAccounts.Count) account(s) protected" -ForegroundColor $StatusColor
}

# --- CORE LOGIC: BITLOCKER & SNAPSHOTS ---

Function Get-BitLockerRecoveryKeys {
    Param([string]$ComputerDN)
    try {
        # SearchBase must be a DN, so we keep this as is
        $Keys = Get-ADObject -Filter {objectClass -eq 'msFVE-RecoveryInformation'} -SearchBase $ComputerDN -Properties msFVE-RecoveryPassword, whenCreated
        return $Keys | ForEach-Object {
            [PSCustomObject]@{
                Created     = $_.whenCreated
                RecoveryKey = $_."msFVE-RecoveryPassword"
                KeyID       = $_.Name -replace '\{|\}' -replace '^[^-]*-'
            }
        }
    } catch { return $null }
}

Function Get-ObjectSnapshot {
    Param([string]$Guid)
    try {
        # Determine object type and pull appropriate properties
        $ObjType = Get-ADObject -Identity $Guid -Properties ObjectClass -ErrorAction Stop

        if ($ObjType.ObjectClass -eq "user") {
            $Obj = Get-ADUser -Identity $Guid -Properties Enabled, "msDS-parentdistname", LockedOut, DistinguishedName -ErrorAction Stop
        } else {
            $Obj = Get-ADComputer -Identity $Guid -Properties Enabled, "msDS-parentdistname", OperatingSystem, DistinguishedName -ErrorAction Stop
        }

        $Parent = $Obj."msDS-parentdistname"
        if (!$Parent) {
            $Parent = $Obj.DistinguishedName -replace '^CN=.*?,(?=OU=|CN=|DC=)', ''
        }

        return [PSCustomObject]@{
            Location = if($Parent){$Parent}else{"Root/Unknown"}
            Status   = if($null -ne $Obj.Enabled){ if($Obj.Enabled){"Enabled"}else{"Disabled"} }else{"N/A"}
            Locked   = if($ObjType.ObjectClass -eq "user"){ if($null -ne $Obj.LockedOut){ if($Obj.LockedOut){"LOCKED"}else{"Unlocked"} }else{"N/A"} }else{"N/A"}
            OS       = if($Obj.OperatingSystem){$Obj.OperatingSystem}else{"N/A"}
            DN       = $Obj.DistinguishedName
            Guid     = $Guid
        }
    } catch {
        return $null
    }
}

Function Write-DetailedAuditLog {
    Param([string]$Action, [string]$Name, [string]$Username = "", $BeforeState, $AfterState, [string]$FinalResult = "SUCCESS", [array]$BitLockerData = $null)
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Actor = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    
    # Combine Name and Username for display
    $DisplayName = if ($Username) { "$Name ($Username)" } else { $Name }
    
    # Logic for BitLocker logging
    $BLString = ""
    if ($BitLockerData -and $BitLockerData.Count -gt 0) {
        $BLString = "`n[BITLOCKER KEYS]: Found ($($BitLockerData.Count)) key(s)"
        foreach ($key in $BitLockerData) {
            $BLString += "`n  >> ID: $($key.KeyID) | CREATED: $($key.Created)"
            $BLString += "`n  >> KEY: $($key.RecoveryKey)"
        }
    } elseif ($Action -match "COMP_DELETE" -or $Action -match "COMP_STAGE" -or $Action -match "BITLOCKER" -or $Action -match "USER" -or $Action -match "RENAME") {
        # Explicitly log if no keys were found during a deletion, staging, or manual check
        $BLString = "`n[BITLOCKER KEYS]: No recovery keys found in AD for this object."
    }

    $LogBlock = @"
--------------------------------------------------
TIMESTAMP: $TimeStamp | ACTOR: $Actor
ACTION:    $Action | TARGET: $DisplayName | RESULT: $FinalResult
[BEFORE]:  Location: $(if($BeforeState.Location){$BeforeState.Location}else{"N/A"}) | Status: $(if($BeforeState.Status){$BeforeState.Status}else{"N/A"}) | Locked: $(if($BeforeState.Locked){$BeforeState.Locked}else{"N/A"}) | OS: $(if($BeforeState.OS){$BeforeState.OS}else{"N/A"})
[AFTER]:   Location: $(if($AfterState){$AfterState.Location}else{"N/A"}) | Status: $(if($AfterState){$AfterState.Status}else{"N/A"}) | Locked: $(if($AfterState){$AfterState.Locked}else{"N/A"}) | OS: $(if($AfterState){$AfterState.OS}else{"N/A"})$BLString
--------------------------------------------------
"@
    Add-Content -Path $LogFile -Value $LogBlock
    $LogColor = if($FinalResult -match "SUCCESS") { "Green" } else { "Red" }
    Write-Host "Audit Log Updated: $DisplayName ($FinalResult)" -ForegroundColor $LogColor
}

Function Test-DuplicateNameInOU {
    Param([string]$Name, [string]$TargetOU, [string]$ExcludeGUID)
    # Check if name already exists in target OU (excluding the object being moved)
    try {
        $Existing = Get-ADObject -Filter "Name -eq '$Name'" -SearchBase $TargetOU -ErrorAction Stop | Where-Object { $_.ObjectGUID -ne $ExcludeGUID }
        return $Existing.Count -gt 0
    } catch {
        return $false
    }
}

Function Resolve-DuplicateName {
    Param([string]$ObjectGUID, [string]$ObjectName, [string]$SamAccountName, [string]$TargetOU)
    # Rename object to include username to avoid conflict
    $NewName = "$ObjectName`_$SamAccountName"
    try {
        Rename-ADObject -Identity $ObjectGUID -NewName $NewName -ErrorAction Stop
        Write-Host "  >> Renamed to: $NewName (to avoid conflict in target OU)" -ForegroundColor Cyan
        return $NewName
    } catch {
        Write-Host "  >> ERROR renaming: $($_.Exception.Message)" -ForegroundColor Red
        throw $_
    }
}

Function Test-IsProtectedAccount {
    param($TargetObject)
    $isDC = $false
    try {
        $fullObj = Get-ADObject -Identity $TargetObject.DistinguishedName -Properties PrimaryGroupID
        if ($fullObj.PrimaryGroupID -eq 516) { $isDC = $true }
    } catch {}
    
    # Check DN-based protection
    $ProtectedDNs = @("CN=Builtin", "CN=System", "OU=Domain Controllers", "CN=Infrastructure")
    foreach ($dn in $ProtectedDNs) { if ($TargetObject.DistinguishedName -like "*$dn*") { return $true } }
    
    # Check against dynamically configured protected accounts
    if ($TargetObject.Name -in $script:ProtectedAccounts -or $TargetObject.SamAccountName -in $script:ProtectedAccounts) {
        return $true
    }
    
    return $isDC
}

Function Get-SafeADData {
    Param([string]$Type)
    # Included ObjectGUID in the property pull
    $Props = @('Name','SamAccountName','PasswordLastSet','Enabled','lastLogonTimestamp','DistinguishedName','ProtectedFromAccidentalDeletion','OperatingSystem','PrimaryGroupID','msDS-UserPasswordExpiryTimeComputed','PasswordNeverExpires','ObjectGUID')
    $Raw = if ($Type -eq "User") { Get-ADUser -Filter * -Properties $Props } else { Get-ADComputer -Filter * -Properties $Props }
    
    return $Raw | ForEach-Object {
        $Role = "Workstation"; if ($_.PrimaryGroupID -eq 516) { $Role = "Domain Controller" } elseif ($_.OperatingSystem -like "*Server*") { $Role = "Member Server" }
        $BLCount = (Get-ADObject -Filter {objectClass -eq 'msFVE-RecoveryInformation'} -SearchBase $_.DistinguishedName).Count
        
        $RawExp = $_."msDS-UserPasswordExpiryTimeComputed"
        $PassExp = if ($RawExp -le 0 -or $RawExp -eq 9223372036854775807) { "Never" } else { [datetime]::FromFileTime($RawExp) }

        [PSCustomObject]@{
            Name              = $_.Name
            Username          = $_.SamAccountName
            Status            = if($_.Enabled){"Enabled"}else{"Disabled"}
            LastLogon         = if ($_.lastLogonTimestamp -and $_.lastLogonTimestamp -ne 0) { [DateTime]::FromFileTime($_.lastLogonTimestamp) } else { $null }
            OS                = $_.OperatingSystem
            Role              = $Role
            BitLocker         = if($BLCount -gt 0){"YES ($BLCount)"}else{"NO"}
            PasswordExp       = $PassExp
            PassNeverExpires  = $_.PasswordNeverExpires
            DistinguishedName = $_.DistinguishedName
            ObjectGUID        = $_.ObjectGUID
            IsSystemAccount   = Test-IsProtectedAccount -TargetObject $_
        }
    }
}

# --- MODULE: SETTINGS ---

Function Manage-ProtectedAccountsMenu {
    $ExitProtected = $false
    do {
        Write-MenuHeader -Title "CONFIGURE PROTECTED ACCOUNTS" -Color Yellow
        Write-ProtectedAccountsStatus
        Write-Host ""
        Write-Host " 1. Select Protected Accounts (Multi-select)"
        Write-Host " 2. Clear Protected Accounts"
        Write-Host " 3. View Current Protected Accounts"
        Write-MenuFooter -Color Yellow -BackChar "B"
        
        $Choice = (Read-Host "`nSelection").ToUpper()
        switch ($Choice) {
            "1" {
                $AllUsers = Get-SafeADData "User" | Select-Object Name, Username, Status, LastLogon, PasswordLastSet, PasswordExp, PassNeverExpires, IsSystemAccount
                if ($AllUsers) {
                    $Selected = $AllUsers | Out-GridView -Title "Select Users to PROTECT (Ctrl+Click for multiple)" -PassThru
                    if ($Selected) {
                        # Collect both Name and SamAccountName for matching
                        $script:ProtectedAccounts = @()
                        foreach ($User in $Selected) {
                            $script:ProtectedAccounts += $User.Name
                            $script:ProtectedAccounts += $User.Username
                        }
                        $script:ProtectedAccounts = @($script:ProtectedAccounts | Sort-Object -Unique)
                        Write-Host "Protected $($Selected.Count) account(s). Total unique identifiers: $($script:ProtectedAccounts.Count)" -ForegroundColor Green; Start-Sleep 2
                    }
                } else {
                    Write-Host "No users found." -ForegroundColor Yellow; Start-Sleep 2
                }
            }
            "2" {
                if ((Read-Host "Clear all protected accounts? (Y/N)").ToUpper() -eq "Y") {
                    $script:ProtectedAccounts = @()
                    Write-Host "Protected accounts cleared." -ForegroundColor Green; Start-Sleep 2
                }
            }
            "3" {
                if ($script:ProtectedAccounts.Count -gt 0) {
                    $script:ProtectedAccounts | ForEach-Object { Write-Host " - $_" }
                    Read-Host "Press Enter to continue"
                } else {
                    Write-Host "No protected accounts configured yet." -ForegroundColor Yellow; Start-Sleep 2
                }
            }
            "B" { $ExitProtected = $true }
        }
    } until ($ExitProtected)
}

Function Manage-SettingsMenu {
    $ExitSettings = $false
    do {
        Write-MenuHeader -Title "SETTINGS & OU MANAGEMENT" -Color Yellow
        Write-TargetOUStatus
        Write-Host ""
        Write-Host " 1. Select Existing OU (Browse AD)"
        Write-Host " 2. Create New 'Pending Deletion' OU"
        Write-MenuFooter -Color Yellow -BackChar "B"
        
        $Choice = (Read-Host "`nSelection").ToUpper()
        if ($Choice -eq "B") { $ExitSettings = $true }
        elseif ($Choice -eq "1" -or $Choice -eq "2") {
            $DomainRoot = (Get-ADDomain).DistinguishedName
            $RootObj = [PSCustomObject]@{ Name = "[DOMAIN ROOT]"; DistinguishedName = $DomainRoot }
            $OUs = Get-ADOrganizationalUnit -Filter * | Select-Object Name, DistinguishedName
            $AllLocations = @($RootObj) + $OUs

            if ($Choice -eq "1") {
                $Selected = $AllLocations | Out-GridView -Title "Select Target Cleanup OU" -PassThru
                if ($Selected) { $script:PendingDeletionOU = $Selected.DistinguishedName; Write-Host "Target Set!" -ForegroundColor Green; Start-Sleep 1 }
            }
            elseif ($Choice -eq "2") {
                $Parent = $AllLocations | Out-GridView -Title "Select Parent for New OU" -PassThru
                if ($Parent) {
                    $NewName = Read-Host "Enter New OU Name"
                    try {
                        $NewOU = New-ADOrganizationalUnit -Name $NewName -Path $Parent.DistinguishedName -PassThru
                        $script:PendingDeletionOU = $NewOU.DistinguishedName
                        Write-Host "OU Created!" -ForegroundColor Green; Start-Sleep 1
                    } catch { Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red; Start-Sleep 2 }
                }
            }
        }
    } until ($ExitSettings)
}

# --- MODULE: BITLOCKER ---

Function Show-BitLockerMenu {
    $ExitBitLocker = $false
    do {
        Write-MenuHeader -Title "BITLOCKER RECOVERY TOOLS" -Color Cyan
        Write-Host " 1. Search: Find Computer by Name"
        Write-Host " 2. Manual: Select from Computer List"
        Write-MenuFooter -Color Cyan -BackChar "B"
        
        $Choice = (Read-Host "`nSelection").ToUpper()
        
        switch ($Choice) {
            "1" {
                $Search = Read-Host "Search Computer Name for Keys"
                if ($Search) {
                    $Comp = Get-ADComputer -Filter "Name -like '*$Search*'"
                    if ($Comp) {
                        $Selected = if(@($Comp).Count -gt 1){ $Comp | Out-GridView -Title "Select Computer" -PassThru } else { $Comp }
                        if ($Selected) {
                            $Keys = Get-BitLockerRecoveryKeys -ComputerDN $Selected.DistinguishedName
                            if ($Keys) { 
                                $Keys | Out-GridView -Title "Keys for $($Selected.Name)"
                                if ((Read-Host "Archive these keys to log? (Y/N)").ToUpper() -eq "Y") { 
                                    $Snap = Get-ObjectSnapshot $Selected.ObjectGUID
                                    Write-DetailedAuditLog -Action "BITLOCKER_MANUAL_VIEW" -Name $Selected.Name -BeforeState $Snap -AfterState $Snap -BitLockerData $Keys 
                                }
                            } else { 
                                Write-Host "No keys found." -ForegroundColor Red; Start-Sleep 2 
                                $Snap = Get-ObjectSnapshot $Selected.ObjectGUID
                                Write-DetailedAuditLog -Action "BITLOCKER_CHECK_NONE" -Name $Selected.Name -BeforeState $Snap -AfterState $Snap
                            }
                        }
                    } else {
                        Write-Host "No computers found matching '$Search'." -ForegroundColor Yellow; Start-Sleep 2
                    }
                }
            }
            "2" {
                $AllComputers = Get-SafeADData "Computer" | Select-Object Name, Role, OS, DistinguishedName, ObjectGUID
                if ($AllComputers) {
                    $Selected = $AllComputers | Out-GridView -Title "Select Computer" -PassThru
                    if ($Selected) {
                        # Need to get the full DN from the selected computer
                        $FullComp = Get-ADComputer -Identity $Selected.ObjectGUID -Properties DistinguishedName
                        $Keys = Get-BitLockerRecoveryKeys -ComputerDN $FullComp.DistinguishedName
                        if ($Keys) { 
                            $Keys | Out-GridView -Title "Keys for $($Selected.Name)"
                            if ((Read-Host "Archive these keys to log? (Y/N)").ToUpper() -eq "Y") { 
                                $Snap = Get-ObjectSnapshot $Selected.ObjectGUID
                                Write-DetailedAuditLog -Action "BITLOCKER_MANUAL_VIEW" -Name $Selected.Name -BeforeState $Snap -AfterState $Snap -BitLockerData $Keys 
                            }
                        } else { 
                            Write-Host "No keys found for $($Selected.Name)." -ForegroundColor Yellow; Start-Sleep 2 
                            $Snap = Get-ObjectSnapshot $Selected.ObjectGUID
                            Write-DetailedAuditLog -Action "BITLOCKER_CHECK_NONE" -Name $Selected.Name -BeforeState $Snap -AfterState $Snap
                        }
                    }
                } else {
                    Write-Host "No computers found in directory." -ForegroundColor Yellow; Start-Sleep 2
                }
            }
            "B" { $ExitBitLocker = $true }
        }
    } while (!$ExitBitLocker)
}

# --- MODULE: COMPUTER CLEANUP ---

Function Show-ComputerCleanupMenu {
    do {
        Write-MenuHeader -Title "COMPUTER & SERVER CLEANUP" -Color Cyan
        Write-TargetOUStatus
        Write-Host ""
        Write-Host " 1. VIEW: Inactive Servers"
        Write-Host " 2. VIEW: Inactive Workstations"
        Write-Host " 3. ACTION: Disable & Move (STAGING)"
        Write-Host " 4. ACTION: DELETE (From Staging OU Only)"
        Write-MenuFooter -Color Cyan -BackChar "B"
        
        $Choice = (Read-Host "`nSelection").ToUpper()
        $Now = Get-Date
        
        switch ($Choice) {
            "1" { 
                $Days = Read-Host "Days of inactivity (e.g. 90)"
                if (!$Days) { break }
                $Results = (Get-SafeADData "Computer") | Where-Object { $_.Role -ne "Workstation" -and ( $_.LastLogon -eq $null -or $_.LastLogon -lt $Now.AddDays(-[int]$Days) ) }
                if ($Results) { 
                    $Results | Out-GridView
                    Export-DataToCSV -Data $Results -FileName "AD_Servers_Inactive_${Days}Days"
                } else { 
                    Write-Host "No inactive servers found (>$Days days)." -ForegroundColor Yellow; Start-Sleep 2 
                }
            }
            "2" { 
                $Days = Read-Host "Days of inactivity (e.g. 90)"
                if (!$Days) { break }
                $Results = (Get-SafeADData "Computer") | Where-Object { $_.Role -eq "Workstation" -and ( $_.LastLogon -eq $null -or $_.LastLogon -lt $Now.AddDays(-[int]$Days) ) }
                if ($Results) { 
                    $Results | Out-GridView
                    Export-DataToCSV -Data $Results -FileName "AD_Workstations_Inactive_${Days}Days"
                } else { 
                    Write-Host "No inactive workstations found (>$Days days)." -ForegroundColor Yellow; Start-Sleep 2 
                }
            }
            "3" {
                if ($script:PendingDeletionOU -eq "NOT SET") { Write-Host "Set Target OU first." -ForegroundColor Red; Start-Sleep 2; break }
                if ($script:ProtectedAccounts.Count -eq 0) { Write-Host "Configure protected accounts first (option 8)." -ForegroundColor Red; Start-Sleep 2; break }
                $Days = Read-Host "Days of inactivity (e.g. 90)"
                if (!$Days) { break }
                $Data = (Get-SafeADData "Computer") | Where-Object { ( $_.LastLogon -eq $null -or $_.LastLogon -lt $Now.AddDays(-[int]$Days) ) -and $_.IsSystemAccount -eq $false }
                if (!$Data) { Write-Host "No computers match the criteria (inactive for $Days+ days, not system accounts)." -ForegroundColor Yellow; Start-Sleep 2; break }
                $Selected = $Data | Out-GridView -Title "Select to STAGE" -PassThru
                if ($Selected -and (Read-Host "Type 'CONFIRM'").ToUpper() -eq "CONFIRM") {
                    foreach ($C in $Selected) {
                        $Before = Get-ObjectSnapshot $C.ObjectGUID
                        $Keys = Get-BitLockerRecoveryKeys -ComputerDN $C.DistinguishedName
                        try {
                            # Only disable if not already disabled
                            if ($C.Status -eq "Enabled") {
                                Disable-ADAccount -Identity $C.ObjectGUID
                            }
                            Move-ADObject -Identity $C.ObjectGUID -TargetPath $script:PendingDeletionOU
                            # Using GUID here ensures we find it in the new OU for the After snapshot
                            $After = Get-ObjectSnapshot $C.ObjectGUID
                            Write-DetailedAuditLog -Action "COMP_STAGE" -Name $C.Name -BeforeState $Before -AfterState $After -BitLockerData $Keys
                        } catch { 
                            $After = Get-ObjectSnapshot $C.ObjectGUID
                            Write-DetailedAuditLog -Action "COMP_STAGE_FAIL" -Name $C.Name -BeforeState $Before -AfterState $After -FinalResult "ERROR: $($_.Exception.Message)" -BitLockerData $Keys
                        }
                    }
                }
            }
            "4" {
                if ($script:PendingDeletionOU -eq "NOT SET") { Write-Host "Error: Set Target OU." -ForegroundColor Red; Start-Sleep 2; break }
                $Data = (Get-SafeADData "Computer") | Where-Object { $_.DistinguishedName -like "*$script:PendingDeletionOU*" -and $_.Status -eq "Disabled" }
                if (!$Data) { Write-Host "No disabled computers found in staging OU." -ForegroundColor Yellow; Start-Sleep 2; break }
                $Selected = $Data | Out-GridView -Title "FINAL DELETE" -PassThru
                if ($Selected -and (Read-Host "Type 'DELETE'").ToUpper() -eq "DELETE") {
                    foreach ($C in $Selected) {
                        $Before = Get-ObjectSnapshot $C.ObjectGUID
                        # Capture BitLocker keys (if any) before attempting delete
                        $Keys = Get-BitLockerRecoveryKeys -ComputerDN $C.DistinguishedName
                        try {
                            # Safety: ensure the object is still a computer (avoid deleting OUs/containers)
                            $ObjCheck = Get-ADObject -Identity $C.ObjectGUID -Properties ObjectClass -ErrorAction Stop
                            if ($ObjCheck.ObjectClass -ne 'computer') {
                                throw "Target is not a computer object (found: $($ObjCheck.ObjectClass)). Aborting delete."
                            }

                            # Remove the computer and any child objects recursively using Remove-ADObject
                            # (Remove-ADComputer doesn't support -Recursive, but Remove-ADObject does)
                            Remove-ADObject -Identity $C.ObjectGUID -Confirm:$false -Recursive

                            # On successful delete, write a clear deleted after-state
                            $After = [PSCustomObject]@{
                                Location = "DELETED"
                                Status   = "DELETED"
                                Locked   = "N/A"
                                OS       = "N/A"
                            }
                            Write-DetailedAuditLog -Action "COMP_DELETE" -Name $C.Name -BeforeState $Before -AfterState $After -BitLockerData $Keys
                        } catch {
                            # If delete failed, capture current snapshot (object likely still exists) and log the error
                            $After = Get-ObjectSnapshot $C.ObjectGUID
                            Write-DetailedAuditLog -Action "COMP_DEL_FAIL" -Name $C.Name -BeforeState $Before -AfterState $After -FinalResult "ERROR: $($_.Exception.Message)" -BitLockerData $Keys
                        }
                    }
                }
            }
        }
    } while ($Choice -ne "B")
}

# --- MODULE: USER CLEANUP ---

Function Show-UserModuleMenu {
    do {
        Write-MenuHeader -Title "USER MODULE" -Color Cyan
        Write-TargetOUStatus
        Write-Host ""
        Write-Host " 1. VIEW: Inactive Users"
        Write-Host " 2. VIEW: Stale Passwords"
        Write-Host " 3. ACTION: Disable & Move"
        Write-Host " 4. ACTION: Disable Only"
        Write-Host " 5. ACTION: Delete Staged Users"
        Write-Host " 6. ACTION: Find 'test' Users & Disable"
        Write-Host " 7. ACTION: Find 'temp' Users & Disable"
        Write-Host " 8. ACTION: Find & Disable Stale Admins"
        Write-MenuFooter -Color Cyan -BackChar "B"
        
        $Choice = (Read-Host "`nSelection").ToUpper()
        $Now = Get-Date
        
        switch ($Choice) {
            "1" { 
                $Days = Read-Host "Days of inactivity (e.g. 90)"
                if (!$Days) { break }
                $Results = Get-SafeADData "User" | Where-Object { $_.LastLogon -eq $null -or $_.LastLogon -lt $Now.AddDays(-[int]$Days) }
                if ($Results) { 
                    $Results | Out-GridView
                    Export-DataToCSV -Data $Results -FileName "AD_Users_Inactive_${Days}Days"
                } else { 
                    Write-Host "No inactive users found (>$Days days)." -ForegroundColor Yellow; Start-Sleep 2 
                }
            }
            "2" { 
                $Results = Get-SafeADData "User" | Where-Object { ($_.PasswordExp -lt (Get-Date) -and $_.Status -eq "Enabled") -or ($_.PassNeverExpires -eq $true) }
                if ($Results) { 
                    $Results | Out-GridView
                    Export-DataToCSV -Data $Results -FileName "AD_Users_StalePasswords"
                } else { 
                    Write-Host "No users with stale passwords found." -ForegroundColor Yellow; Start-Sleep 2 
                }
            }
            "3" {
                if ($script:PendingDeletionOU -eq "NOT SET") { Write-Host "Set Target OU." -ForegroundColor Red; Start-Sleep 2; break }
                if ($script:ProtectedAccounts.Count -eq 0) { Write-Host "Configure protected accounts first (option 8)." -ForegroundColor Red; Start-Sleep 2; break }
                $Days = Read-Host "Days of inactivity (e.g. 90)"
                if (!$Days) { break }
                $Data = Get-SafeADData "User" | Where-Object { ( $_.LastLogon -eq $null -or $_.LastLogon -lt $Now.AddDays(-[int]$Days) ) -and $_.IsSystemAccount -eq $false }
                if (!$Data) { Write-Host "No users match the criteria (inactive for $Days+ days, not system accounts)." -ForegroundColor Yellow; Start-Sleep 2; break }
                $Sel = $Data | Out-GridView -PassThru
                if ($Sel -and (Read-Host "Type 'CONFIRM'").ToUpper() -eq "CONFIRM") {
                    foreach ($U in $Sel) {
                        $B = Get-ObjectSnapshot $U.ObjectGUID
                        try {
                            # Only disable if not already disabled
                            if ($U.Status -eq "Enabled") {
                                Disable-ADAccount -Identity $U.ObjectGUID
                            }
                            
                            # Check for duplicate name in target OU and rename if needed
                            if (Test-DuplicateNameInOU -Name $U.Name -TargetOU $script:PendingDeletionOU -ExcludeGUID $U.ObjectGUID) {
                                $RenamedName = Resolve-DuplicateName -ObjectGUID $U.ObjectGUID -ObjectName $U.Name -SamAccountName $U.Username -TargetOU $script:PendingDeletionOU
                                Write-DetailedAuditLog -Action "USER_RENAME" -Name $U.Name -Username $U.Username -BeforeState $B -AfterState $null -FinalResult "RENAMED to $RenamedName"
                                $B = Get-ObjectSnapshot $U.ObjectGUID  # Refresh snapshot after rename
                            }
                            
                            Move-ADObject -Identity $U.ObjectGUID -TargetPath $script:PendingDeletionOU
                            $A = Get-ObjectSnapshot $U.ObjectGUID
                            Write-DetailedAuditLog -Action "USER_DISABLE" -Name $U.Name -Username $U.Username -BeforeState $B -AfterState $A
                        } catch { Write-DetailedAuditLog -Action "USER_ERR" -Name $U.Name -Username $U.Username -BeforeState $B -AfterState $null -FinalResult "ERROR: $($_.Exception.Message)" }
                    }
                }
            }
            "4" {
                # new disable-only path
                if ($script:ProtectedAccounts.Count -eq 0) { Write-Host "Configure protected accounts first (option 8)." -ForegroundColor Red; Start-Sleep 2; break }
                $Days = Read-Host "Days of inactivity (e.g. 90)"
                if (!$Days) { break }
                $Data = Get-SafeADData "User" | Where-Object { ( $_.LastLogon -eq $null -or $_.LastLogon -lt $Now.AddDays(-[int]$Days) ) -and $_.IsSystemAccount -eq $false }
                if (!$Data) { Write-Host "No users match the criteria (inactive for $Days+ days, not system accounts)." -ForegroundColor Yellow; Start-Sleep 2; break }
                $Sel = $Data | Out-GridView -Title "Select to DISABLE" -PassThru
                if ($Sel -and (Read-Host "Type 'CONFIRM'").ToUpper() -eq "CONFIRM") {
                    foreach ($U in $Sel) {
                        $B = Get-ObjectSnapshot $U.ObjectGUID
                        try {
                            if ($U.Status -eq "Enabled") { Disable-ADAccount -Identity $U.ObjectGUID }
                            $A = Get-ObjectSnapshot $U.ObjectGUID
                            Write-DetailedAuditLog -Action "USER_DISABLE_ONLY" -Name $U.Name -Username $U.Username -BeforeState $B -AfterState $A
                        } catch { Write-DetailedAuditLog -Action "USER_ERR" -Name $U.Name -Username $U.Username -BeforeState $B -AfterState $null -FinalResult "ERROR: $($_.Exception.Message)" }
                    }
                }
            }
            "5" {
                $Days = Read-Host "Days of inactivity (e.g. 90)"
                if (!$Days) { break }
                $Data = Get-SafeADData "User" | Where-Object { $_.DistinguishedName -like "*$script:PendingDeletionOU*" -and $_.Status -eq "Disabled" -and ( $_.LastLogon -eq $null -or $_.LastLogon -lt $Now.AddDays(-[int]$Days) ) }
                if (!$Data) { Write-Host "No disabled users found in staging OU matching inactivity criteria (>$Days days)." -ForegroundColor Yellow; Start-Sleep 2; break }
                $Sel = $Data | Out-GridView -PassThru
                if ($Sel -and (Read-Host "Type 'DELETE'").ToUpper() -eq "DELETE") {
                    foreach ($U in $Sel) {
                        $B = Get-ObjectSnapshot $U.ObjectGUID
                        try {
                            Remove-ADUser -Identity $U.ObjectGUID -Confirm:$false
                            Write-DetailedAuditLog -Action "USER_DELETE" -Name $U.Name -Username $U.Username -BeforeState $B -AfterState $null
                        } catch { Write-DetailedAuditLog -Action "USER_ERR" -Name $U.Name -Username $U.Username -BeforeState $B -AfterState $null -FinalResult "ERROR: $($_.Exception.Message)" }
                    }
                }
            }
            "6" {
                # find any account with "test" in name or username and allow disabling
                $Matches = Get-SafeADData "User" | Where-Object { $_.Name -like '*test*' -or $_.Username -like '*test*' }
                if (!$Matches) { Write-Host "No users with 'test' found." -ForegroundColor Yellow; Start-Sleep 2; break }
                $Sel = $Matches | Out-GridView -Title "Select 'test' users to DISABLE" -PassThru
                if ($Sel -and (Read-Host "Type 'CONFIRM'").ToUpper() -eq "CONFIRM") {
                    foreach ($U in $Sel) {
                        $B = Get-ObjectSnapshot $U.ObjectGUID
                        try {
                            if ($U.Status -eq "Enabled") { Disable-ADAccount -Identity $U.ObjectGUID }
                            $A = Get-ObjectSnapshot $U.ObjectGUID
                            Write-DetailedAuditLog -Action "USER_DISABLE_TEST" -Name $U.Name -Username $U.Username -BeforeState $B -AfterState $A
                        } catch { Write-DetailedAuditLog -Action "USER_ERR" -Name $U.Name -Username $U.Username -BeforeState $B -AfterState $null -FinalResult "ERROR: $($_.Exception.Message)" }
                    }
                }
            }
            "7" {
                # find any account with "temp" in name or username and allow disabling
                $Matches = Get-SafeADData "User" | Where-Object { $_.Name -like '*temp*' -or $_.Username -like '*temp*' }
                if (!$Matches) { Write-Host "No users with 'temp' found." -ForegroundColor Yellow; Start-Sleep 2; break }
                $Sel = $Matches | Out-GridView -Title "Select 'temp' users to DISABLE" -PassThru
                if ($Sel -and (Read-Host "Type 'CONFIRM'").ToUpper() -eq "CONFIRM") {
                    foreach ($U in $Sel) {
                        $B = Get-ObjectSnapshot $U.ObjectGUID
                        try {
                            if ($U.Status -eq "Enabled") { Disable-ADAccount -Identity $U.ObjectGUID }
                            $A = Get-ObjectSnapshot $U.ObjectGUID
                            Write-DetailedAuditLog -Action "USER_DISABLE_TEMP" -Name $U.Name -Username $U.Username -BeforeState $B -AfterState $A
                        } catch { Write-DetailedAuditLog -Action "USER_ERR" -Name $U.Name -Username $U.Username -BeforeState $B -AfterState $null -FinalResult "ERROR: $($_.Exception.Message)" }
                    }
                }
            }
            "8" {
                # Find and disable stale admin users (excluding protected accounts and service accounts)
                if ($script:ProtectedAccounts.Count -eq 0) { Write-Host "Configure protected accounts first (option 8 in main menu)." -ForegroundColor Red; Start-Sleep 2; break }
                
                Write-Host "Gathering admin group memberships (including nested)..." -ForegroundColor Cyan
                
                # Get all admin group members recursively
                $AdminGroups = @("Domain Admins", "Enterprise Admins", "Administrators")
                $AdminUserGUIDs = @()
                
                foreach ($GroupName in $AdminGroups) {
                    try {
                        $GroupObj = Get-ADGroup -Filter "Name -eq '$GroupName'" -ErrorAction Stop
                        $Members = Get-ADGroupMember -Identity $GroupObj.ObjectGUID -Recursive -ErrorAction Stop | Where-Object { $_.objectClass -eq "user" }
                        $AdminUserGUIDs += $Members.ObjectGUID
                    } catch {
                        # Group may not exist (e.g., Enterprise Admins in single-domain forests)
                    }
                }
                
                $AdminUserGUIDs = @($AdminUserGUIDs | Sort-Object -Unique)
                
                if ($AdminUserGUIDs.Count -eq 0) { Write-Host "No admin users found." -ForegroundColor Yellow; Start-Sleep 2; break }
                
                $Days = Read-Host "Days of inactivity to check (e.g. 90)"
                if (!$Days) { break }
                
                $Now = Get-Date
                $AdminUsers = Get-SafeADData "User" | Where-Object { $_.ObjectGUID -in $AdminUserGUIDs }
                
                # Filter: inactive + not protected + not system account
                $Candidates = $AdminUsers | Where-Object {
                    ($_.LastLogon -eq $null -or $_.LastLogon -lt $Now.AddDays(-[int]$Days)) -and
                    $_.IsSystemAccount -eq $false -and
                    $_.Name -notin $script:ProtectedAccounts -and
                    $_.Username -notin $script:ProtectedAccounts
                }
                
                if (!$Candidates -or $Candidates.Count -eq 0) { 
                    Write-Host "No stale admin users found (excluding protected accounts and system accounts)." -ForegroundColor Yellow; Start-Sleep 2; break 
                }
                
                # Filter out service accounts (those with SPNs)
                $DataFiltered = $Candidates | ForEach-Object {
                    $User = $_
                    try {
                        $ADUserObj = Get-ADUser -Identity $User.ObjectGUID -Properties ServicePrincipalName -ErrorAction Stop
                        if (-not $ADUserObj.ServicePrincipalName -or $ADUserObj.ServicePrincipalName.Count -eq 0) {
                            # No SPN - safe to include
                            $User
                        }
                        # else: Has SPN - service account, skip it
                    } catch {
                        $User  # Include if error checking SPN
                    }
                }
                
                if (!$DataFiltered -or $DataFiltered.Count -eq 0) { 
                    Write-Host "No stale admin users found (all candidates are service accounts or protected)." -ForegroundColor Yellow; Start-Sleep 2; break 
                }
                
                $Sel = $DataFiltered | Out-GridView -Title "Select Stale Admins to DISABLE" -PassThru
                if ($Sel -and (Read-Host "Type 'CONFIRM'").ToUpper() -eq "CONFIRM") {
                    foreach ($U in $Sel) {
                        $B = Get-ObjectSnapshot $U.ObjectGUID
                        try {
                            if ($U.Status -eq "Enabled") { Disable-ADAccount -Identity $U.ObjectGUID }
                            $A = Get-ObjectSnapshot $U.ObjectGUID
                            Write-DetailedAuditLog -Action "USER_DISABLE_STALE_ADMIN" -Name $U.Name -Username $U.Username -BeforeState $B -AfterState $A
                        } catch { Write-DetailedAuditLog -Action "USER_ERR" -Name $U.Name -Username $U.Username -BeforeState $B -AfterState $null -FinalResult "ERROR: $($_.Exception.Message)" }
                    }
                }
            }
        }
    } while ($Choice -ne "B")
}

# --- MODULE: OBJECT MANAGEMENT ---

Function Show-ObjectManagementMenu {
    param($SelectedObject)
    
    $ExitManagement = $false
    do {
        $ObjectType = if($SelectedObject.ObjectClass -eq "user") { "USER" } else { "COMPUTER" }
        $ObjectName = $SelectedObject.Name
        
        Write-MenuHeader -Title "MANAGEMENT: $ObjectName ($ObjectType)" -Color Magenta
        Write-Host " 1. View Object Details"
        Write-Host " 2. Enable Account"
        Write-Host " 3. Disable Account"
        Write-Host " 4. Move to Different OU"
        Write-Host " 5. Delete Object"
        if ($SelectedObject.ObjectClass -eq "computer") {
            Write-Host " 6. View BitLocker Keys"
        }
        Write-MenuFooter -Color Magenta -BackChar "B"
        
        $Choice = (Read-Host "`nSelection").ToUpper()
        
        switch ($Choice) {
            "1" {
                $Details = Get-ADObject -Identity $SelectedObject.ObjectGUID -Properties * | Out-GridView -Title "Details: $ObjectName"
            }
            "2" {
                try {
                    Enable-ADAccount -Identity $SelectedObject.ObjectGUID
                    $Snap = Get-ObjectSnapshot $SelectedObject.ObjectGUID
                    Write-DetailedAuditLog -Action "MANUAL_ENABLE" -Name $ObjectName -BeforeState $null -AfterState $Snap
                    Write-Host "Account enabled successfully." -ForegroundColor Green; Start-Sleep 2
                } catch {
                    Write-Host "Error enabling account: $($_.Exception.Message)" -ForegroundColor Red; Start-Sleep 2
                }
            }
            "3" {
                try {
                    Disable-ADAccount -Identity $SelectedObject.ObjectGUID
                    $Snap = Get-ObjectSnapshot $SelectedObject.ObjectGUID
                    Write-DetailedAuditLog -Action "MANUAL_DISABLE" -Name $ObjectName -BeforeState $null -AfterState $Snap
                    Write-Host "Account disabled successfully." -ForegroundColor Green; Start-Sleep 2
                } catch {
                    Write-Host "Error disabling account: $($_.Exception.Message)" -ForegroundColor Red; Start-Sleep 2
                }
            }
            "4" {
                if ($script:PendingDeletionOU -eq "NOT SET") { 
                    Write-Host "No target OU set. Go to Settings to configure target OU first." -ForegroundColor Yellow; Start-Sleep 2; break 
                }
                if ((Read-Host "Move to target OU '$script:PendingDeletionOU'? (Y/N)").ToUpper() -eq "Y") {
                    try {
                        $Before = Get-ObjectSnapshot $SelectedObject.ObjectGUID
                        Move-ADObject -Identity $SelectedObject.ObjectGUID -TargetPath $script:PendingDeletionOU
                        $After = Get-ObjectSnapshot $SelectedObject.ObjectGUID
                        Write-DetailedAuditLog -Action "MANUAL_MOVE" -Name $ObjectName -BeforeState $Before -AfterState $After
                        Write-Host "Object moved successfully." -ForegroundColor Green; Start-Sleep 2
                    } catch {
                        Write-Host "Error moving object: $($_.Exception.Message)" -ForegroundColor Red; Start-Sleep 2
                    }
                }
            }
            "5" {
                if ((Read-Host "WARNING: Delete $ObjectName? Type 'DELETE' to confirm").ToUpper() -eq "DELETE") {
                    try {
                        $Before = Get-ObjectSnapshot $SelectedObject.ObjectGUID
                        if ($SelectedObject.ObjectClass -eq "user") {
                            Remove-ADUser -Identity $SelectedObject.ObjectGUID -Confirm:$false
                        } else {
                            $Keys = Get-BitLockerRecoveryKeys -ComputerDN $SelectedObject.DistinguishedName
                            Remove-ADComputer -Identity $SelectedObject.ObjectGUID -Confirm:$false
                            Write-DetailedAuditLog -Action "MANUAL_DELETE" -Name $ObjectName -BeforeState $Before -AfterState $null -BitLockerData $Keys
                        }
                        Write-DetailedAuditLog -Action "MANUAL_DELETE" -Name $ObjectName -BeforeState $Before -AfterState $null
                        Write-Host "Object deleted successfully." -ForegroundColor Green; Start-Sleep 2
                        $ExitManagement = $true
                    } catch {
                        Write-Host "Error deleting object: $($_.Exception.Message)" -ForegroundColor Red; Start-Sleep 2
                    }
                }
            }
            "6" {
                if ($SelectedObject.ObjectClass -eq "computer") {
                    $Keys = Get-BitLockerRecoveryKeys -ComputerDN $SelectedObject.DistinguishedName
                    if ($Keys) {
                        $Keys | Out-GridView -Title "BitLocker Keys for $ObjectName"
                        if ((Read-Host "Archive these keys to log? (Y/N)").ToUpper() -eq "Y") {
                            $Snap = Get-ObjectSnapshot $SelectedObject.ObjectGUID
                            Write-DetailedAuditLog -Action "BITLOCKER_MANUAL_VIEW" -Name $ObjectName -BeforeState $Snap -AfterState $Snap -BitLockerData $Keys
                        }
                    } else {
                        Write-Host "No BitLocker keys found." -ForegroundColor Yellow; Start-Sleep 2
                    }
                }
            }
            "B" { $ExitManagement = $true }
        }
    } while (!$ExitManagement)
}

# --- MAIN LOOP ---
do {
    Write-MenuHeader -Title "AD MANAGEMENT & CLEANUP" -Color Green
    Write-TargetOUStatus
    Write-ProtectedAccountsStatus
    Write-Host ""
    Write-Host " 1. Inventory: View All Users"
    Write-Host " 2. Inventory: View All Computers"
    Write-Host " 3. USER Module: User Cleanup"
    Write-Host " 4. COMPUTER Module: Server/Workstation Cleanup"
    Write-Host " 5. BITLOCKER: Recovery Key Management"
    Write-Host " 6. Manual Search & Identity Management"
    Write-Host " 7. Settings (Set Target OU)"
    Write-Host " 8. Configure Protected Accounts"
    Write-Host " 9. Enable AD Recycle Bin"
    Write-MenuFooter -Color Green -BackChar "Q"

    $MainChoice = (Read-Host "`nSelection").ToUpper()

    switch ($MainChoice) {
        "1" { 
            $Results = Get-SafeADData "User"
            $Results | Out-GridView
            Export-DataToCSV -Data $Results -FileName "AD_Users_All"
        }
        "2" { 
            $Results = Get-SafeADData "Computer"
            $Results | Out-GridView
            Export-DataToCSV -Data $Results -FileName "AD_Computers_All"
        }
        "3" { Show-UserModuleMenu }
        "4" { Show-ComputerCleanupMenu }
        "5" { Show-BitLockerMenu }
        "6" { 
            $ExitSearch = $false
            do {
                Write-MenuHeader -Title "MANUAL SEARCH & IDENTITY MANAGEMENT" -Color Magenta
                Write-Host " 1. Search: Find by Name/Username"
                Write-Host " 2. Manual: Select from User List"
                Write-Host " 3. Manual: Select from Computer List"
                Write-MenuFooter -Color Magenta -BackChar "B"
                
                $SearchChoice = (Read-Host "`nSelection").ToUpper()
                
                switch ($SearchChoice) {
                    "1" {
                        $Term = Read-Host "Enter Name/Username to Search"
                        if ($Term) {
                            $Res = Get-ADObject -Filter "Name -like '*$Term*' -or SamAccountName -like '*$Term*'" -Properties SamAccountName, ObjectGUID, DistinguishedName, ObjectClass
                            if ($Res) { 
                                $Selected = $Res | Out-GridView -Title "Search Results" -PassThru
                                if ($Selected) {
                                    Show-ObjectManagementMenu -SelectedObject $Selected
                                }
                            }
                            else { Write-Host "No results found for '$Term'." -ForegroundColor Yellow; Start-Sleep 2 }
                        }
                    }
                    "2" {
                        $AllUsers = Get-SafeADData "User" | Select-Object Name, Username, Status, LastLogon, DistinguishedName, ObjectGUID
                        if ($AllUsers) {
                            $Selected = $AllUsers | Out-GridView -Title "Select User" -PassThru
                            if ($Selected) {
                                # Convert to ADUser object for management
                                $ADUserObj = Get-ADUser -Identity $Selected.ObjectGUID -Properties ObjectClass
                                Show-ObjectManagementMenu -SelectedObject $ADUserObj
                            }
                        } else {
                            Write-Host "No users found." -ForegroundColor Yellow; Start-Sleep 2
                        }
                    }
                    "3" {
                        $AllComputers = Get-SafeADData "Computer" | Select-Object Name, Role, OS, Status, LastLogon, DistinguishedName, ObjectGUID
                        if ($AllComputers) {
                            $Selected = $AllComputers | Out-GridView -Title "Select Computer" -PassThru
                            if ($Selected) {
                                # Convert to ADComputer object for management
                                $ADCompObj = Get-ADComputer -Identity $Selected.ObjectGUID -Properties ObjectClass
                                Show-ObjectManagementMenu -SelectedObject $ADCompObj
                            }
                        } else {
                            Write-Host "No computers found." -ForegroundColor Yellow; Start-Sleep 2
                        }
                    }
                    "B" { $ExitSearch = $true }
                }
            } while (!$ExitSearch)
        }
        "7" { Manage-SettingsMenu }
        "8" { Manage-ProtectedAccountsMenu }
        "9" {
            Write-MenuHeader -Title "ENABLE AD RECYCLE BIN" -Color Yellow
            Write-Host "This will run the Enable_AD_Recycle_Bin script." -ForegroundColor Yellow
            Write-Host ""
            if ((Read-Host "Continue? (Y/N)").ToUpper() -eq "Y") {
                try {
                    Write-Host "Downloading and executing Enable_AD_Recycle_Bin script..." -ForegroundColor Cyan
                    irm https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Active%20Directory/Enable_AD_Recycle_Bin.ps1 | iex
                    Write-Host "Script execution completed." -ForegroundColor Green
                    Start-Sleep 2
                } catch {
                    Write-Host "Error executing script: $($_.Exception.Message)" -ForegroundColor Red
                    Start-Sleep 3
                }
            }
        }
    }
} while ($MainChoice -ne "Q")