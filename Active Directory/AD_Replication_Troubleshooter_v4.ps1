<# 
(AD_Replication_Troubleshooter.ps1) :: (Revision # 4)/Aaron Pleus - (07/21/2025)

   This script, like all scripts developed by Aaron Pleus, unless otherwise explicitly stated, is the copyrighted property of Aaron Pleus.;
   it may not be shared, sold, or distributed whole or in part, even with modifications applied, for any reason. this includes on reddit, on discord, or as part of other RMM tools.
   	
   The moment you edit this script it becomes your own risk and Aaron Pleus will not provide assistance with it.

# This script does the following:

## Domain Controller Identification: 
# Lists all servers in Active Directory sites, including their DNS hostnames and IP addresses.
# Identifies the domain and whether each server is a Global Catalog (GC) server.
### Replication Diagnostics:
# Runs repadmin /replsummary to show a summary of replication status.
# Runs repadmin /queue to display pending replication tasks.
# Runs repadmin /syncall /e /d to check synchronization status across all domain controllers.
### DCDiag Tests:
# Executes dcdiag /test:Replication to specifically test replication.
# Runs a general dcdiag /v for broader diagnostic information.
# Event Viewer Check: Queries the "Directory Service" log for errors and warnings related to replication from the last 24 hours.
# Error Handling: Includes try-catch blocks to handle potential errors gracefully and provide feedback.
#>

#requires -RunAsAdministrator

# Import the ActiveDirectory module
Import-Module ActiveDirectory -ErrorAction Stop

# --- Main script execution ---
Write-Host "=== Active Directory Replication Troubleshooting Script ===" -ForegroundColor Cyan

# --- Domain Controller Identification ---
Write-Host "`n=== Collecting AD Site and Server Information ===" -ForegroundColor Cyan
$serverInfo = @()
$domainControllers = @()
try {
    # Get the configuration naming context dynamically
    $ConfigPartition = (Get-ADRootDSE).configurationNamingContext

    # Get all AD sites
    $sites = Get-ADObject -Filter { objectClass -eq "site" } -SearchBase $ConfigPartition -Properties Name -ErrorAction Stop

    # Iterate through each site to find servers
    foreach ($site in $sites) {
        $serversInSite = Get-ADObject -Filter { objectClass -eq "server" } -SearchBase "CN=Servers,$($site.DistinguishedName)" -Properties Name, dNSHostName -ErrorAction Stop
        foreach ($server in $serversInSite) {
            $isDC = $false
            $domain = "N/A"
            $isGC = "N/A"
            
            # Check if the server is a domain controller
            $dc = Get-ADDomainController -Identity $server.Name -ErrorAction SilentlyContinue
            if ($dc) {
                $isDC = $true
                $domain = $dc.Domain
                $isGC = $dc.IsGlobalCatalog
                $domainControllers += $dc
            }

            # Attempt to resolve the IP address for the server's DNS hostname
            $ipAddress = try {
                (Resolve-DnsName -Name $server.dNSHostName -Type A -ErrorAction Stop).IPAddress
            } catch {
                "Unresolvable"
            }
            
            $serverInfo += [PSCustomObject]@{
                SiteName     = $site.Name
                ServerName   = $server.Name
                DNSHostName  = $server.dNSHostName
                IPAddress    = $ipAddress
                IsDomainController = $isDC
                Domain       = $domain
                IsGlobalCatalog = $isGC
            }
        }
    }

    # Display server information
    if ($serverInfo) {
        Write-Host "`n=== AD Site Server Details ===" -ForegroundColor Green
        $serverInfo | Format-Table -AutoSize
    } else {
        Write-Host "No servers found in AD sites." -ForegroundColor Yellow
    }
} catch {
    Write-Host "Error retrieving AD site servers: $_" -ForegroundColor Red
}

# --- Replication Diagnostics ---
function Run-RepadminCommands {
    Write-Host "`n=== Replication Summary (repadmin /replsummary) ===" -ForegroundColor Green
    try {
        repadmin /replsummary
    } catch {
        Write-Host "Error running repadmin /replsummary: $_" -ForegroundColor Red
    }

    Write-Host "`n=== Replication Queue (repadmin /queue) ===" -ForegroundColor Green
    try {
        repadmin /queue
    } catch {
        Write-Host "Error running repadmin /queue: $_" -ForegroundColor Red
    }

    Write-Host "`n=== Replication Sync Status (repadmin /syncall) ===" -ForegroundColor Green
    try {
        repadmin /syncall /e /d
    } catch {
        Write-Host "Error running repadmin /syncall: $_" -ForegroundColor Red
    }
}

# --- DCDiag Tests ---
function Run-DCDiagTests {
    Write-Host "`n=== DCDiag Replication Tests ===" -ForegroundColor Green
    try {
        dcdiag /test:replications /v
    } catch {
        Write-Host "Error running dcdiag /test:Replication: $_" -ForegroundColor Red
    }

    Write-Host "`n=== DCDiag General Tests ===" -ForegroundColor Green
    try {
        dcdiag /v
    } catch {
        Write-Host "Error running dcdiag: $_" -ForegroundColor Red
    }
}

# --- Event Viewer Check ---
function Check-EventViewerErrors {
    Write-Host "`n=== Event Viewer Replication Errors (Last 24 Hours) ===" -ForegroundColor Green
    $startTime = (Get-Date).AddHours(-24)
    try {
        # Common AD replication event IDs
        $replicationEventIDs = 1000, 1004, 1006, 1311, 1388, 1865, 1925, 1926, 1988, 2103
        
        $events = Get-WinEvent -FilterHashtable @{
            LogName   = 'Directory Service'
            StartTime = $startTime
            Level     = 2, 3  # Error and Warning
            Id        = $replicationEventIDs
        } -ErrorAction Stop

        if ($events) {
            Write-Host "Found replication-related errors in Event Viewer:" -ForegroundColor Yellow
            $events | Select-Object TimeCreated, Id, Message | Format-Table -Wrap -AutoSize
        } else {
            Write-Host "No replication-related errors found in Event Viewer in the last 24 hours." -ForegroundColor Green
        }
    } catch {
        Write-Host "Error retrieving Event Viewer logs: $_" -ForegroundColor Red
    }
}

# --- Execute Diagnostic Steps ---
if ($domainControllers) {
    Run-RepadminCommands
    Run-DCDiagTests
    Check-EventViewerErrors
} else {
    Write-Host "`nSkipping replication and diagnostic tests because no domain controllers were identified." -ForegroundColor Yellow
}

Write-Host "`n=== Troubleshooting Complete ===" -ForegroundColor Cyan
Write-Host "Review the output above for any errors or warnings." -ForegroundColor Yellow