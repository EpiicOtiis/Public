<# (AD_Replication_Troubleshooter.ps1) :: (Revision # 4)/Aaron Pleus - (07/21/2025)

   This script, like all scripts developed by Aaron Pleus, unless otherwise explicitly stated, is the copyrighted property of Aaron Pleus.;
   it may not be shared, sold, or distributed whole or in part, even with modifications applied, for any reason. this includes on reddit, on discord, or as part of other RMM tools.
   	
   The moment you edit this script it becomes your own risk and Aaron Pleus will not provide assistance with it.
#>

<#
# This script does the following:

## Domain Controller Identification: 
Lists all servers in Active Directory sites, including their DNS hostnames and IP addresses.
Identifies the domain and whether each server is a Global Catalog (GC) server.
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

# Import the ActiveDirectory module
Import-Module ActiveDirectory -ErrorAction Stop

# Create an array to store results
$results = @()

# Get all servers in AD sites
Write-Host "=== Collecting AD Site Servers ===" -ForegroundColor Cyan
try {
    # Get the configuration naming context dynamically
    $ConfigPartition = (Get-ADRootDSE).configurationNamingContext

    # Initialize results array
    $results = @()

    # Get all AD sites
    $sites = Get-ADObject -Filter { objectClass -eq "site" } -SearchBase $ConfigPartition -Properties Name -ErrorAction Stop

    # Iterate through each site to find servers
    foreach ($site in $sites) {
        $servers = Get-ADObject -Filter { objectClass -eq "server" } -SearchBase "CN=Servers,$($site.DistinguishedName)" -Properties Name, dNSHostName -ErrorAction Stop
        foreach ($server in $servers) {
            # Get domain and DC type
            $serverDetails = Get-ADDomainController -Identity $server.Name -ErrorAction SilentlyContinue
            $domain = if ($serverDetails) { $serverDetails.Domain } else { "Unknown" }
            $isGC = if ($serverDetails) { $serverDetails.IsGlobalCatalog } else { $false }
            $dcType = if ($isGC) { "GC" } else { "" }

            # Attempt to resolve the IP address for the server's DNS hostname
            $ipAddress = $null
            try {
                $ipAddress = (Resolve-DnsName -Name $server.dNSHostName -Type A -ErrorAction Stop).IPAddress
            } catch {
                $ipAddress = "Unresolvable"
            }
            
            $results += [PSCustomObject]@{
                SiteName     = $site.Name
                ServerName   = $server.Name
                DNSHostName  = $server.dNSHostName
                IPAddress    = $ipAddress
                Domain       = $domain
                DCType       = $dcType
            }
        }
    }

    # Display results for this function
    if ($results) {
        Write-Host "`n=== AD Site Servers ===" -ForegroundColor Green
        $results | Format-Table -AutoSize
    } else {
        Write-Host "No servers found in AD sites." -ForegroundColor Yellow
    }
} catch {
    Write-Host "Error retrieving AD site servers: $_" -ForegroundColor Red
}

# Run repadmin commands
function Run-RepadminCommands {
    Write-Host "`n=== Replication Summary (repadmin /replsummary) ===" -ForegroundColor Green
    try {
        $replSummary = & repadmin /replsummary
        $replSummary | ForEach-Object { Write-Host $_ }
    } catch {
        Write-Host "Error running repadmin /replsummary: $_" -ForegroundColor Red
    }

    Write-Host "`n=== Replication Queue (repadmin /queue) ===" -ForegroundColor Green
    try {
        $replQueue = & repadmin /queue
        $replQueue | ForEach-Object { Write-Host $_ }
    } catch {
        Write-Host "Error running repadmin /queue: $_" -ForegroundColor Red
    }

    Write-Host "`n=== Replication Sync Status (repadmin /syncall) ===" -ForegroundColor Green
    try {
        $replSync = & repadmin /syncall /e /d
        $replSync | ForEach-Object { Write-Host $_ }
    } catch {
        Write-Host "Error running repadmin /syncall: $_" -ForegroundColor Red
    }
}

# Run dcdiag tests
function Run-DCDiagTests {
    Write-Host "`n=== DCDiag Replication Tests ===" -ForegroundColor Green
    try {
        $dcdiag = & dcdiag /test:replications /v
        $dcdiag | ForEach-Object { Write-Host $_ }
    } catch {
        Write-Host "Error running dcdiag /test:Replication: $_" -ForegroundColor Red
    }

    Write-Host "`n=== DCDiag General Tests ===" -ForegroundColor Green
    try {
        $dcdiagGeneral = & dcdiag /v
        $dcdiagGeneral | ForEach-Object { Write-Host $_ }
    } catch {
        Write-Host "Error running dcdiag: $_" -ForegroundColor Red
    }
}

# Check Event Viewer for replication errors
function Check-EventViewerErrors {
    Write-Host "`n=== Event Viewer Replication Errors (Last 24 Hours) ===" -ForegroundColor Green
    $startTime = (Get-Date).AddHours(-24)
    try {
        $events = Get-WinEvent -FilterHashtable @{
            LogName   = 'Directory Service'
            StartTime = $startTime
            Level     = 2, 3  # Error and Warning
        } -ErrorAction Stop | Where-Object {
            $_.Id -in (1000, 1004, 1006, 1311, 1388, 1865, 1925, 1926, 1988, 2103)  # Common AD replication event IDs
        }

        if ($events) {
            Write-Host "Found replication-related errors in Event Viewer:" -ForegroundColor Yellow
            $events | Select-Object TimeCreated, Id, Message | Format-Table -AutoSize
        } else {
            Write-Host "No replication-related errors found in Event Viewer." -ForegroundColor Green
        }
    } catch {
        Write-Host "Error retrieving Event Viewer logs: $_" -ForegroundColor Red
    }
}

# Main script execution
Write-Host "=== Active Directory Replication Troubleshooting Script ===" -ForegroundColor Cyan

# Execute steps if domain controllers are found
if ($dcs) {
    Run-RepadminCommands
    Run-DCDiagTests
    Check-EventViewerErrors
} else {
    Write-Host "Skipping replication and diagnostic tests due to no domain controllers found." -ForegroundColor Yellow
}

Write-Host "`n=== Troubleshooting Complete ===" -ForegroundColor Cyan
Write-Host "Review the output above for any errors or warnings." -ForegroundColor Yellow