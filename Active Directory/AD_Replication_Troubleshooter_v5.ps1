<# 
(AD_Replication_Troubleshooter.ps1) :: (Revision # 5)/Aaron Pleus - (07/23/2025)

   This script, like all scripts developed by Aaron Pleus, unless otherwise explicitly stated, is the copyrighted property of Aaron Pleus.;
   it may not be shared, sold, or distributed whole or in part, even with modifications applied, for any reason. this includes on reddit, on discord, or as part of other RMM tools.
   	
   The moment you edit this script it becomes your own risk and Aaron Pleus will not provide assistance with it.

This script does the following:

Domain Controller Identification:
# Lists all servers in Active Directory sites, including their DNS hostnames and IP addresses.
# Identifies which servers are Domain Controllers and if they are a Global Catalog (GC).
# Handles errors for individual servers without stopping the entire script.

FSMO Role Check:
# Identifies and displays the holders of the five FSMO roles (both forest-wide and domain-wide).

Replication Diagnostics:
# Runs repadmin /replsummary to show a summary of replication status.
# Runs repadmin /queue to display pending replication tasks.
# Runs repadmin /syncall /e /d to check synchronization status across all domain controllers.

DCDiag Tests:
# Executes dcdiag /test:Replication to specifically test replication.
# Runs a general dcdiag /v for broader diagnostic information.

Event Viewer Check:
# Queries the "Directory Service" log for errors and warnings related to replication from the last 24 hours.

Error Handling:
# Includes try-catch blocks to handle potential errors gracefully and provide feedback.
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

# This outer try-catch will handle critical errors, like not being able to contact AD at all.
try {
    # Get the configuration naming context dynamically
    $ConfigPartition = (Get-ADRootDSE).configurationNamingContext

    # Get all AD sites
    $sites = Get-ADObject -Filter { objectClass -eq "site" } -SearchBase $ConfigPartition -Properties Name -ErrorAction Stop

    # Iterate through each site to find servers
    foreach ($site in $sites) {
        $serversInSite = Get-ADObject -Filter { objectClass -eq "server" } -SearchBase "CN=Servers,$($site.DistinguishedName)" -Properties Name, dNSHostName -ErrorAction Stop
        
        foreach ($server in $serversInSite) {
            # This inner try-catch handles errors for a SINGLE server, allowing the loop to continue.
            try {
                $isDC = $false
                $domain = "N/A"
                $isGC = "N/A"
                $dcStatus = "OK"

                # Check if the server is a domain controller.
                # If Get-ADDomainController fails, the CATCH block will handle it.
                $dc = Get-ADDomainController -Identity $server.Name -ErrorAction Stop
                
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
                    Status       = $dcStatus
                }
            }
            catch {
                # This block now catches the error for a single server and reports it.
                # The script will then continue to the next server in the list.
                $serverInfo += [PSCustomObject]@{
                    SiteName     = $site.Name
                    ServerName   = $server.Name
                    DNSHostName  = $server.dNSHostName
                    IPAddress    = "N/A"
                    IsDomainController = $false
                    Domain       = "N/A"
                    IsGlobalCatalog = "N/A"
                    Status       = "ERROR: Not a DC or unreachable."
                }
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
    Write-Host "A critical error occurred while retrieving AD site information: $_" -ForegroundColor Red
}

# --- FSMO Role Check ---
function Get-FSMORoles {
    Write-Host "`n=== FSMO Role Holders ===" -ForegroundColor Green
    try {
        # Get the forest-wide FSMO roles
        $forest = Get-ADForest
        Write-Host "Forest-wide FSMO Roles:"
        Write-Host "-----------------------"
        Write-Host "Schema Master        : $($forest.SchemaMaster)"
        Write-Host "Domain Naming Master : $($forest.DomainNamingMaster)"
        Write-Host ""

        # Get the domain-specific FSMO roles
        $domain = Get-ADDomain
        Write-Host "Domain-wide FSMO Roles:"
        Write-Host "----------------------"
        Write-Host "PDC Emulator         : $($domain.PDCEmulator)"
        Write-Host "RID Master           : $($domain.RIDMaster)"
        Write-Host "Infrastructure Master: $($domain.InfrastructureMaster)"
    }
    catch {
        Write-Host "Error retrieving FSMO roles: $_" -ForegroundColor Red
    }
}


# --- Replication Diagnostics ---
function Run-RepadminCommands {
    Write-Host "`n=== Replication Summary (repadmin /replsummary) ===" -ForegroundColor Green
    try { repadmin /replsummary } catch { Write-Host "Error running repadmin /replsummary: $_" -ForegroundColor Red }

    Write-Host "`n=== Replication Queue (repadmin /queue) ===" -ForegroundColor Green
    try { repadmin /queue } catch { Write-Host "Error running repadmin /queue: $_" -ForegroundColor Red }

    Write-Host "`n=== Replication Sync Status (repadmin /syncall) ===" -ForegroundColor Green
    try { repadmin /syncall /e /d } catch { Write-Host "Error running repadmin /syncall: $_" -ForegroundColor Red }
}

# --- DCDiag Tests ---
function Run-DCDiagTests {
    Write-Host "`n=== DCDiag Replication Tests ===" -ForegroundColor Green
    try { dcdiag /test:replications /v } catch { Write-Host "Error running dcdiag /test:Replication: $_" -ForegroundColor Red }

    Write-Host "`n=== DCDiag General Tests ===" -ForegroundColor Green
    try { dcdiag /v } catch { Write-Host "Error running dcdiag: $_" -ForegroundColor Red }
}

# --- Event Viewer Check ---
function Check-EventViewerErrors {
    Write-Host "`n=== Event Viewer Replication Errors (Last 24 Hours) ===" -ForegroundColor Green
    $startTime = (Get-Date).AddHours(-24)
    try {
        $replicationEventIDs = 1000, 1004, 1006, 1311, 1388, 1865, 1925, 1926, 1988, 2103
        
        $events = Get-WinEvent -FilterHashtable @{
            LogName   = 'Directory Service'
            StartTime = $startTime
            Level     = 2, 3 # 2 for Error, 3 for Warning
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
# This part now works correctly because the script will no longer halt on a single server error.
if ($domainControllers) {
    # Run the FSMO Role check
    Get-FSMORoles
    
    # Run the rest of the diagnostics
    Run-RepadminCommands
    Run-DCDiagTests
    Check-EventViewerErrors
} else {
    Write-Host "`nSkipping FSMO, replication, and diagnostic tests because no domain controllers were identified." -ForegroundColor Yellow
}

Write-Host "`n=== Troubleshooting Complete ===" -ForegroundColor Cyan
Write-Host "Review the output above for any errors or warnings." -ForegroundColor Yellow