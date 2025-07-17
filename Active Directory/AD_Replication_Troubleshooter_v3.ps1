<# (AD_Replication_Troubleshooter.ps1) :: (Revision # 3)/Aaron Pleus - (07/07/2025)

   This script, like all scripts developed by Aaron Pleus, unless otherwise explicitly stated, is the copyrighted property of Aaron Pleus.;
   it may not be shared, sold, or distributed whole or in part, even with modifications applied, for any reason. this includes on reddit, on discord, or as part of other RMM tools.
   	
   The moment you edit this script it becomes your own risk and Aaron Pleus will not provide assistance with it.
#>

<#
# This script does the following:

## Domain Controller Identification: 
Uses Get-ADDomainController to list all domain controllers with their names, IP addresses, and sites.
### Replication Diagnostics:
Runs repadmin /replsummary to show a summary of replication status.
Runs repadmin /queue to display pending replication tasks.
Runs repadmin /syncall /e /d to check synchronization status across all domain controllers.
### DCDiag Tests:
Executes dcdiag /test:Replication to specifically test replication.
Runs a general dcdiag /v for broader diagnostic information.
Event Viewer Check: Queries the "Directory Service" log for errors and warnings related to replication (using common event IDs like 1000, 1925, etc.) from the last 24 hours.
Error Handling: Includes try-catch blocks to handle potential errors gracefully and provide feedback.
#>

#requires -RunAsAdministrator

# Import Active Directory module
Import-Module ActiveDirectory

# Function to get domain controllers with name and IP
function Get-DomainControllers {
    try {
        $dcs = Get-ADDomainController -Filter * | Select-Object Name, IPv4Address, Site
        if ($dcs) {
            Write-Host "`n=== Domain Controllers ===" -ForegroundColor Green
            $dcs | Format-Table Name, IPv4Address, Site -AutoSize
            return $dcs
        } else {
            Write-Host "No domain controllers found." -ForegroundColor Yellow
            return $null
        }
    } catch {
        Write-Host "Error retrieving domain controllers: $_" -ForegroundColor Red
        return $null
    }
}

# Function to run repadmin commands
function Run-RepadminCommands {
    Write-Host "`n=== Replication Summary (repadmin /replsummary) ===" -ForegroundColor Green
    try {
        $replSummary = repadmin /replsummary
        $replSummary | ForEach-Object { Write-Host $_ }
    } catch {
        Write-Host "Error running repadmin /replsummary: $_" -ForegroundColor Red
    }

    Write-Host "`n=== Replication Queue (repadmin /queue) ===" -ForegroundColor Green
    try {
        $replQueue = repadmin /queue
        $replQueue | ForEach-Object { Write-Host $_ }
    } catch {
        Write-Host "Error running repadmin /queue: $_" -ForegroundColor Red
    }

    Write-Host "`n=== Replication Sync Status (repadmin /syncall) ===" -ForegroundColor Green
    try {
        $replSync = repadmin /syncall /e /d
        $replSync | ForEach-Object { Write-Host $_ }
    } catch {
        Write-Host "Error running repadmin /syncall: $_" -ForegroundColor Red
    }
}

# Function to run dcdiag tests
function Run-DCDiagTests {
    Write-Host "`n=== DCDiag Replication Tests ===" -ForegroundColor Green
    try {
        $dcdiag = dcdiag /test:replications /v
        $dcdiag | ForEach-Object { Write-Host $_ }
    } catch {
        Write-Host "Error running dcdiag /test:Replication: $_" -ForegroundColor Red
    }

    Write-Host "`n=== DCDiag General Tests ===" -ForegroundColor Green
    try {
        $dcdiagGeneral = dcdiag /v
        $dcdiagGeneral | ForEach-Object { Write-Host $_ }
    } catch {
        Write-Host "Error running dcdiag: $_" -ForegroundColor Red
    }
}

# Function to check Event Viewer for replication errors
function Check-EventViewerErrors {
    Write-Host "`n=== Event Viewer Replication Errors (Last 24 Hours) ===" -ForegroundColor Green
    $startTime = (Get-Date).AddHours(-24)
    $events = Get-WinEvent -FilterHashtable @{
        LogName = 'Directory Service'
        StartTime = $startTime
        Level = 2,3  # Error and Warning
    } -ErrorAction SilentlyContinue | Where-Object {
        $_.Id -in (1000, 1004, 1006, 1311, 1388, 1865, 1925, 1926, 1988, 2103)  # Common AD replication event IDs
    }

    if ($events) {
        Write-Host "Found replication-related errors in Event Viewer:" -ForegroundColor Yellow
        $events | Select-Object TimeCreated, Id, Message | Format-Table -AutoSize
    } else {
        Write-Host "No replication-related errors found in Event Viewer." -ForegroundColor Green
    }
}

# Main script execution
Write-Host "=== Active Directory Replication Troubleshooting Script ===" -ForegroundColor Cyan

# Step 1: Get domain controllers
$dcs = Get-DomainControllers

# Step 2: Run repadmin commands if domain controllers are found
if ($dcs) {
    Run-RepadminCommands
}

# Step 3: Run dcdiag tests
Run-DCDiagTests

# Step 4: Check Event Viewer for replication errors
Check-EventViewerErrors

Write-Host "`n=== Troubleshooting Complete ===" -ForegroundColor Cyan
Write-Host "Review the output above for any errors or warnings." -ForegroundColor Yellow