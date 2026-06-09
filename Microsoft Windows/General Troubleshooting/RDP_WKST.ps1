#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Interactive utility to view and manage Remote Desktop (RDP) settings on a workstation.
.
.DESCRIPTION
    Displays the current RDP configuration (enabled/disabled, NLA, port, service status,
    firewall rules, and Remote Desktop Users group members) and provides an interactive
    menu to enable/disable RDP, toggle NLA, manage group membership, enable firewall rules,
    and restart the Remote Desktop service.
.
.EXAMPLE
    PS> .\RDP_WKST.ps1
    Launches the interactive menu for inspecting and managing RDP settings.
.
.NOTES
    - Requires running the script as Administrator.
    - Tested on modern Windows with the required NetSecurity and Microsoft.PowerShell.LocalAccounts
      cmdlets available.
#>

# Small helper to mimic a "Pause" behavior used throughout the script
function Pause {
    Read-Host -Prompt "Press Enter to continue..." | Out-Null
}

function Get-RDPStatus {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "          CURRENT RDP STATUS            " -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    # 1. Check if RDP is Enabled
    $fDenyTS = (Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -ErrorAction SilentlyContinue).fDenyTSConnections
    if ($fDenyTS -eq 0) {
        Write-Host "RDP Status:         " -NoNewline; Write-Host "ENABLED" -ForegroundColor Green
    } else {
        Write-Host "RDP Status:         " -NoNewline; Write-Host "DISABLED" -ForegroundColor Red
    }

    # 2. Check NLA Status
    $nlaStatus = (Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -ErrorAction SilentlyContinue).UserAuthentication
    if ($nlaStatus -eq 1) {
        Write-Host "NLA Status:         " -NoNewline; Write-Host "ENABLED" -ForegroundColor Green
    } else {
        Write-Host "NLA Status:         " -NoNewline; Write-Host "DISABLED (Less Secure)" -ForegroundColor Yellow
    }

    # 3. Check Active RDP Port
    $rdpPort = (Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "PortNumber" -ErrorAction SilentlyContinue).PortNumber
    Write-Host "RDP Port:           $rdpPort" -ForegroundColor Cyan

    # 4. Check Service Status
    $service = Get-Service -Name "TermService" -ErrorAction SilentlyContinue
    if ($service -and $service.Status -eq 'Running') {
        Write-Host "TermService:        " -NoNewline; Write-Host "RUNNING" -ForegroundColor Green
    } elseif ($service) {
        Write-Host "TermService:        " -NoNewline; Write-Host $service.Status -ForegroundColor Red
    } else {
        Write-Host "TermService:        " -NoNewline; Write-Host "NOT FOUND" -ForegroundColor Yellow
    }

    # 5. Check Active Firewall Profiles
    Write-Host "`n--- Network & Firewall ---" -ForegroundColor Cyan
    $profiles = Get-NetConnectionProfile -ErrorAction SilentlyContinue
    if ($profiles) {
        foreach ($profile in $profiles) {
            Write-Host "Active Network:     $($profile.Name) ($($profile.NetworkCategory))"
        }
    } else {
        Write-Host "Active Network:     Could not determine"
    }

    $fwRules = Get-NetFirewallRule -DisplayGroup "Remote Desktop" -Enabled True -ErrorAction SilentlyContinue
    if ($fwRules) {
        Write-Host "RDP Firewall Rules: " -NoNewline; Write-Host "ENABLED" -ForegroundColor Green
    } else {
        Write-Host "RDP Firewall Rules: " -NoNewline; Write-Host "DISABLED or MISSING" -ForegroundColor Red
    }

    # 6. Authorized Users (Remote Desktop Users Group)
    Write-Host "`n--- Authorized Users ---" -ForegroundColor Cyan
    try {
        $rdpUsers = Get-LocalGroupMember -Group "Remote Desktop Users" -ErrorAction Stop
        if ($rdpUsers) {
            foreach ($user in $rdpUsers) {
                Write-Host " - $($user.Name) ($($user.ObjectClass))"
            }
        } else {
            Write-Host " - Group is currently empty."
        }
    } catch {
        Write-Host "Could not query Remote Desktop Users group." -ForegroundColor Yellow
    }
    Write-Host "========================================`n" -ForegroundColor Cyan
}

function Show-Menu {
    param (
        [string]$Title = 'RDP Management Utility'
    )
    Clear-Host
    Get-RDPStatus
    Write-Host "1. Enable RDP"
    Write-Host "2. Disable RDP"
    Write-Host "3. Enable NLA (Network Level Authentication)"
    Write-Host "4. Disable NLA"
    Write-Host "5. Add User to RDP Group"
    Write-Host "6. Remove User from RDP Group"
    Write-Host "7. Enable Default Windows Firewall RDP Rules"
    Write-Host "8. Restart Remote Desktop Service (Apply Port/NLA changes)"
    Write-Host "9. Refresh Status"
    Write-Host "0. Exit"
    Write-Host ""
}

# Main Loop
$quit = $false
while (-not $quit) {
    Show-Menu
    $selection = Read-Host "Select an option"

    switch ($selection) {
        '1' {
            Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0
            Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue | Out-Null
            Start-Service -Name "TermService" -ErrorAction SilentlyContinue
            Write-Host "RDP Enabled (and default firewall rules activated)." -ForegroundColor Green
            Pause
        }
        '2' {
            Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 1
            Write-Host "RDP Disabled." -ForegroundColor Green
            Pause
        }
        '3' {
            Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -Value 1
            Write-Host "NLA Enabled. (Restart service for changes to take effect)" -ForegroundColor Green
            Pause
        }
        '4' {
            Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -Value 0
            Write-Host "NLA Disabled. (Restart service for changes to take effect)" -ForegroundColor Green
            Pause
        }
        '5' {
            $userToAdd = Read-Host "Enter username to ADD (e.g., Domain\User, AzureAD\User@domain.com, or LocalUser)"
            if (![string]::IsNullOrWhiteSpace($userToAdd)) {
                try {
                    Add-LocalGroupMember -Group "Remote Desktop Users" -Member $userToAdd -ErrorAction Stop
                    Write-Host "Successfully added $userToAdd." -ForegroundColor Green
                } catch {
                    Write-Host "Error adding user: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
            Pause
        }
        '6' {
            $userToRem = Read-Host "Enter username to REMOVE (e.g., Domain\User, AzureAD\User@domain.com, or LocalUser)"
            if (![string]::IsNullOrWhiteSpace($userToRem)) {
                try {
                    Remove-LocalGroupMember -Group "Remote Desktop Users" -Member $userToRem -ErrorAction Stop
                    Write-Host "Successfully removed $userToRem." -ForegroundColor Green
                } catch {
                    Write-Host "Error removing user: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
            Pause
        }
        '7' {
            Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
            Write-Host "Default Windows Firewall RDP rules enabled." -ForegroundColor Green
            Pause
        }
        '8' {
            Write-Host "Restarting TermService..." -ForegroundColor Yellow
            Restart-Service -Name "TermService" -Force -ErrorAction SilentlyContinue
            Write-Host "Service Restarted." -ForegroundColor Green
            Pause
        }
        '9' {
            # Just loops back and refreshes
        }
        '0' {
            $quit = $true
        }
        default {
            Write-Host "Invalid selection. Please try again." -ForegroundColor Red
            Pause
        }
    }
}