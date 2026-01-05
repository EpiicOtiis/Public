<#
(AD_User_Common_MGMT.ps1) :: (Revision # 1)/Aaron Pleus - (01/05/2026)

   This script, like all scripts developed by Aaron Pleus, unless otherwise explicitly stated, is the copyrighted property of Aaron Pleus.;
   it may not be shared, sold, or distributed whole or in part, even with modifications applied, for any reason. this includes on reddit, on discord, or as part of other RMM tools.
   	
   The moment you edit this script it becomes your own risk and Aaron Pleus will not provide assistance with it
.SYNOPSIS
    AD User Review and Disable Tool
    
.DESCRIPTION
    A script to search for AD users/groups, view detailed information, 
    manage memberships via multi-select, and perform account actions.

    Please note: This script cannot be used in "Backstage" due to its interactive nature.
#>

# --- Section 1: Ensure AD Module is Loaded ---
# Checks if the Active Directory module is available before starting
if (!(Get-Module -ListAvailable ActiveDirectory)) {
    Write-Error "Active Directory module is required. Please install RSAT."
    return
}
Import-Module ActiveDirectory

function Start-ADUserReview {
    do {
        cls
        Write-Host "=== AD User Review and Disable Tool ===" -ForegroundColor Cyan
        Write-Host "Type 'Q' or 'Exit' at the search prompt to quit the script." -ForegroundColor Gray
        Write-Host "----------------------------------------------------------"
        
        $SearchTerm = Read-Host "Enter search term (Username, Name, or Group)"
        
        # --- Section 2: Handle Exit/Empty Input ---
        # If the user hits enter without typing or types Q/Exit, the script closes
        if ([string]::IsNullOrWhiteSpace($SearchTerm) -or $SearchTerm -eq "q" -or $SearchTerm -eq "exit") { 
            Write-Host "Exiting script..." -ForegroundColor Yellow
            break 
        }

        # --- Section 3: Search Logic ---
        # Searches for both users and groups where the name or SamAccountName matches the input
        $Results = Get-ADObject -Filter "Name -like '*$SearchTerm*' -or SamAccountName -like '*$SearchTerm*'" `
                                -Properties SamAccountName, DisplayName, ObjectClass, Enabled |
                   Select-Object Name, SamAccountName, ObjectClass, Enabled, DistinguishedName

        if ($null -eq $Results) {
            Write-Host "No users or groups found matching '$SearchTerm'." -ForegroundColor Red
            Start-Sleep -Seconds 2
            continue
        }

        # --- Section 4: Selection UI ---
        # If multiple results are found, a GUI popup lets you pick the specific target
        $Target = $Results | Out-GridView -Title "Select the User or Group to manage" -OutputMode Single

        if ($null -eq $Target) { continue }

        $ExitTargetMenu = $false
        do {
            cls
            Write-Host "Managing: $($Target.Name) [$($Target.ObjectClass)]" -ForegroundColor Yellow
            Write-Host "------------------------------------------------"

            # --- Section 5: Information Display ---
            if ($Target.ObjectClass -eq "user") {
                # Fetch detailed properties. Note: Hyphenated property name requires quotes
                $UserDetails = Get-ADUser -Identity $Target.DistinguishedName -Properties *, "msDS-UserPasswordExpiryTimeComputed"
                $Status = if ($UserDetails.Enabled) { "ENABLED" } else { "DISABLED" }
                
                # Convert the raw FileTime integer into a human-readable date
                $RawExp = $UserDetails."msDS-UserPasswordExpiryTimeComputed"
                $PasswordExpiry = if ($RawExp -le 0 -or $RawExp -eq 9223372036854775807) { "Never" } else { [datetime]::FromFileTime($RawExp) }

                Write-Host "Status:          $Status"
                Write-Host "Username:        $($UserDetails.SamAccountName)"
                Write-Host "Last Logon:      $($UserDetails.LastLogonDate)"
                Write-Host "Password Set:    $($UserDetails.PasswordLastSet)"
                Write-Host "Password Exp:    $PasswordExpiry"
                Write-Host "When Created:    $($UserDetails.WhenCreated)"
                Write-Host "Description:     $($UserDetails.Description)"
            } 
            else {
                $GroupDetails = Get-ADGroup -Identity $Target.DistinguishedName -Properties *
                Write-Host "Category:        $($GroupDetails.GroupCategory)"
                Write-Host "Scope:           $($GroupDetails.GroupScope)"
                Write-Host "Member Count:    $($GroupDetails.Members.Count)"
            }

            Write-Host "`nOptions:"
            Write-Host "1. Manage Memberships (Add/Remove)"
            if ($Target.ObjectClass -eq "user") {
                Write-Host "2. Reset Password"
                Write-Host "3. Toggle Enable/Disable Status"
                Write-Host "4. Unlock Account"
            }
            Write-Host "B. Back to Search"
            Write-Host "Q. Quit Entirely"
            $Choice = Read-Host "`nSelect an option"

            switch ($Choice) {
                # --- Section 6: Membership Management ---
                "1" {
                    if ($Target.ObjectClass -eq "user") {
                        # Logic to remove a User from multiple Groups
                        $CurrentGroups = Get-ADPrincipalGroupMembership -Identity $Target.DistinguishedName | Sort-Object Name
                        $ToRemove = $CurrentGroups | Out-GridView -Title "SELECT GROUPS TO REMOVE USER FROM (Ctrl+Click to multi-select)" -OutputMode Multiple
                        
                        if ($ToRemove) {
                            foreach ($Group in $ToRemove) {
                                Remove-ADGroupMember -Identity $Group.DistinguishedName -Members $Target.DistinguishedName -Confirm:$false
                                Write-Host "Removed from $($Group.Name)" -ForegroundColor Green
                            }
                        }
                    } else {
                        # Logic to remove multiple Members from a Group
                        $CurrentMembers = Get-ADGroupMember -Identity $Target.DistinguishedName | Sort-Object Name
                        $ToRemove = $CurrentMembers | Out-GridView -Title "SELECT MEMBERS TO REMOVE FROM GROUP (Ctrl+Click to multi-select)" -OutputMode Multiple
                        
                        if ($ToRemove) {
                            foreach ($Member in $ToRemove) {
                                Remove-ADGroupMember -Identity $Target.DistinguishedName -Members $Member.DistinguishedName -Confirm:$false
                                Write-Host "Removed member $($Member.Name)" -ForegroundColor Green
                            }
                        }
                    }
                    Write-Host "Processing updates..."
                    Start-Sleep -Seconds 1
                }

                # --- Section 7: User Actions (Reset, Toggle, Unlock) ---
                "2" {
                    if ($Target.ObjectClass -eq "user") {
                        $NewPW = Read-Host "Enter new password" -AsSecureString
                        Set-ADAccountPassword -Identity $Target.DistinguishedName -NewPassword $NewPW
                        Write-Host "Password reset successfully." -ForegroundColor Green
                        Start-Sleep -Seconds 2
                    }
                }

                "3" {
                    if ($Target.ObjectClass -eq "user") {
                        if ($UserDetails.Enabled) {
                            Disable-ADAccount -Identity $Target.DistinguishedName
                            Write-Host "Account Disabled." -ForegroundColor Red
                        } else {
                            Enable-ADAccount -Identity $Target.DistinguishedName
                            Write-Host "Account Enabled." -ForegroundColor Green
                        }
                        Start-Sleep -Seconds 2
                    }
                }

                "4" {
                    if ($Target.ObjectClass -eq "user") {
                        Unlock-ADAccount -Identity $Target.DistinguishedName
                        Write-Host "Account Unlocked." -ForegroundColor Green
                        Start-Sleep -Seconds 2
                    }
                }

                "b" { $ExitTargetMenu = $true }
                "q" { exit }
            }
        } until ($ExitTargetMenu)

    } while ($true)
}

# Run the function
Start-ADUserReview