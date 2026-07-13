<#
.SYNOPSIS
Maps a network drive for the currently logged-in user from an admin context.

.DESCRIPTION
This script is designed to be run as the SYSTEM account (via ConnectWise Backstage or another RMM tool). 
It prompts the technician for drive details, detects logged-in human user sessions, and injects a 
temporary scheduled task directly into that user's interactive context—even if the PC is locked and 
the user does not have administrative privileges.

.NOTES
This script MUST be run with administrative privileges (or as SYSTEM) to create the scheduled task.
#>

$ErrorActionPreference = 'Stop'

function Get-LoggedInUserSelection {
    $users = @()

    # Try quser first (highly accurate for active sessions)
    try {
        $queryOutput = & quser 2>$null
        if ($LASTEXITCODE -eq 0 -and $queryOutput) {
            foreach ($line in $queryOutput) {
                if ($line -match '^USERNAME') { continue }
                if ([string]::IsNullOrWhiteSpace($line)) { continue }

                $trimmedLine = $line.Trim()
                if ($trimmedLine -match '^(?<user>[^\s]+)') {
                    $userName = $Matches.user.TrimStart('>')
                    if ($userName -and $userName -ne 'USERNAME' -and $userName -notin $users) {
                        $users += $userName
                    }
                }
            }
        }
    }
    catch {
        # Fallback if quser fails entirely
    }

    # Fallback to CIM if quser didn't yield results
    if (-not $users) {
        $cimUser = (Get-CimInstance Win32_ComputerSystem).UserName
        if ($cimUser) {
            # CIM often returns DOMAIN\Username; Scheduled Tasks prefer just the username or full UPN
            if ($cimUser -match '\\') {
                $cimUser = $cimUser.Split('\')[1]
            }
            $users += $cimUser
        }
    }

    if (-not $users) {
        throw "No logged-in user could be detected."
    }

    # If exactly one user found, verify
    if ($users.Count -eq 1) {
        $selectedUser = $users[0]
        Write-Host "Detected logged-in user: $selectedUser" -ForegroundColor Cyan
        $confirm = Read-Host "Is this the correct user? (Y/N)"
        if ($confirm -notmatch '^(y|yes)$') {
            throw "User selection cancelled."
        }
        return $selectedUser
    }

    # If multiple users found, prompt to choose
    Write-Host "Multiple users were detected:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $users.Count; $i++) {
        Write-Host "[$i] $($users[$i])"
    }

    $selection = Read-Host "Select the correct user by number"
    if ($selection -notmatch '^\d+$' -or [int]$selection -lt 0 -or [int]$selection -ge $users.Count) {
        throw "Invalid selection."
    }

    return $users[[int]$selection]
}

# --- CONFIGURATION ---
$DriveLetterDefault  = "Z:"
$NASPathDefault      = "\\NAS_IP_OR_NAME\ShareName"
$NASUserDefault      = "NAS_NAME\Username"
$NASPasswordDefault  = "Password"

$DriveLetter = Read-Host "Enter the drive letter to map (press Enter to keep '$DriveLetterDefault')"
if ([string]::IsNullOrWhiteSpace($DriveLetter)) { $DriveLetter = $DriveLetterDefault }

$NASPath = Read-Host "Enter the UNC path to the share (press Enter to keep '$NASPathDefault')"
if ([string]::IsNullOrWhiteSpace($NASPath)) { $NASPath = $NASPathDefault }

$NASUser = Read-Host "Enter the NAS username (press Enter to keep '$NASUserDefault')"
if ([string]::IsNullOrWhiteSpace($NASUser)) { $NASUser = $NASUserDefault }

$NASPassword = Read-Host "Enter the NAS password (press Enter to keep '$NASPasswordDefault')"
if ([string]::IsNullOrWhiteSpace($NASPassword)) { $NASPassword = $NASPasswordDefault }
# ---------------------

# Try to get the user selection
try {
    $LoggedUser = Get-LoggedInUserSelection
}
catch {
    # Clean output for expected cancellations or missing users
    Write-Host "`n[!] $($_.Exception.Message)" -ForegroundColor Red
    exit
}

# Execute the mapping task
if ($null -ne $LoggedUser) {
    # Define the action (the net use command executed via cmd hidden shell)
    $Action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c net use $DriveLetter `"$NASPath`" `"$NASPassword`" /user:`"$NASUser`" /persistent:yes"
    
    # Define the principal to target the non-admin user's interactive token
    $Principal = New-ScheduledTaskPrincipal -UserId $LoggedUser -LogonType Interactive

    $TaskName = "AutoMapDrivePS"
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Principal $Principal -Force | Out-Null

    # Execute immediately, wait for registration processing, then clean up the task footprint
    Start-ScheduledTask -TaskName $TaskName
    Start-Sleep -Seconds 3
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false

    Write-Host "Successfully queued drive mapping for user context: $LoggedUser" -ForegroundColor Green
}