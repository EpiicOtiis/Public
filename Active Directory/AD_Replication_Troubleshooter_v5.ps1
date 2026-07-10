<# 
(AD_Replication_Troubleshooter.ps1) :: (Revision # 6)/Aaron Pleus

This script does the following:

Domain Controller Identification:
# Lists all servers in Active Directory sites, including their DNS hostnames and IP addresses.
# Identifies which servers are Domain Controllers and if they are a Global Catalog (GC).
# Handles errors for individual servers without stopping the entire script.

FSMO Role Check:
# Identifies and displays the holders of the five FSMO roles (both forest-wide and domain-wide).

Network Connectivity Tests:
# Performs port connectivity checks (Test-NetConnection) on critical AD ports (LDAP, LDAPS, Kerberos, DNS, SMB, RPC) for all domain controllers.

Replication Diagnostics:
# Runs repadmin /replsummary to show a summary of replication status.
# Runs repadmin /queue to display pending replication tasks.
# Runs repadmin /syncall /e /d to check synchronization status across all domain controllers.
# Runs repadmin /kcc on each domain controller to force KCC topology checks.
# Ensures the dfsrdiag tool is available (installing if necessary).
# Runs DFSR diagnostic checks including pollad, replicationstate, dumpmachinecfg, and SYSVOL backlog tests.

DCDiag Tests:
# Executes dcdiag /test:replications to specifically test replication.
# Runs a general dcdiag /v for broader diagnostic information.

Event Viewer Check:
# Queries the "Directory Service" and "DFS Replication" logs for errors and warnings from the last 24 hours.

Error Handling:
# Includes try-catch blocks to handle potential errors gracefully and provide feedback.
#>

#requires -RunAsAdministrator

param (
    [switch]$FSMO,
    [switch]$Repadmin,
    [switch]$Connectivity,
    [switch]$DFSR,
    [switch]$DCDiag,
    [switch]$EventViewer
)

# If no specific switches are set, default to running all checks
if (-not ($FSMO -or $Repadmin -or $Connectivity -or $DFSR -or $DCDiag -or $EventViewer)) {
    $FSMO = $true
    $Repadmin = $true
    $Connectivity = $true
    $DFSR = $true
    $DCDiag = $true
    $EventViewer = $true
}

# Import the ActiveDirectory module
Import-Module ActiveDirectory -ErrorAction Stop

# --- Main script execution ---
Write-Host "=== Active Directory Replication Troubleshooting Script ===" -ForegroundColor Cyan

# --- Local Network Configuration ---
Write-Host "`n=== Local System Network Configuration ===" -ForegroundColor Green
try {
    # Hostname & DNS Domain info
    $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    $dnsDomain = (Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -ErrorAction Stop | Where-Object { $_.DNSDomain }).DNSDomain | Select-Object -Unique -First 1
    
    Write-Host ("Host Name          : {0}" -f $computerSystem.Name)
    Write-Host ("Primary DNS Suffix : {0}" -f $dnsDomain)
    Write-Host ("Domain/Workgroup   : {0}" -f $computerSystem.Domain)
    Write-Host ("System Type        : {0}" -f $computerSystem.SystemType)
    Write-Host ""

    # Active adapters configuration
    $adapters = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" -ErrorAction Stop
    foreach ($adapter in $adapters) {
        Write-Host ("Adapter: {0}" -f $adapter.Description) -ForegroundColor Cyan
        Write-Host "--------------------------------------------------"
        
        $ips = if ($adapter.IPAddress) { $adapter.IPAddress -join ", " } else { "N/A" }
        $subnets = if ($adapter.IPSubnet) { $adapter.IPSubnet -join ", " } else { "N/A" }
        $gateways = if ($adapter.DefaultIPGateway) { $adapter.DefaultIPGateway -join ", " } else { "N/A" }
        $dns = if ($adapter.DNSServerSearchOrder) { $adapter.DNSServerSearchOrder -join ", " } else { "N/A" }
        
        Write-Host ("  DHCP Enabled     : {0}" -f $adapter.DHCPEnabled)
        Write-Host ("  IP Address(es)   : {0}" -f $ips)
        Write-Host ("  Subnet Mask(s)   : {0}" -f $subnets)
        Write-Host ("  Default Gateway  : {0}" -f $gateways)
        if ($adapter.DHCPEnabled) {
            Write-Host ("  DHCP Server      : {0}" -f $adapter.DHCPServer)
        }
        Write-Host ("  DNS Servers      : {0}" -f $dns)
        Write-Host ("  MAC Address      : {0}" -f $adapter.MACAddress)
        Write-Host ""
    }
}
catch {
    $err = $_
    Write-Host ("Error retrieving local network settings: {0}" -f $err) -ForegroundColor Red
}

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
                }
                catch {
                    "Unresolvable"
                }

                # Attempt to retrieve DNS Server forwarders if the server is a DC
                $dnsForwarders = "N/A"
                if ($isDC) {
                    try {
                        if (Get-Command Get-DnsServerForwarder -ErrorAction SilentlyContinue) {
                            $forwardersObj = Get-DnsServerForwarder -ComputerName $server.Name -ErrorAction Stop
                            if ($forwardersObj -and $forwardersObj.IPAddress) {
                                $dnsForwarders = ($forwardersObj.IPAddress.IPAddressToString) -join ", "
                            }
                            else {
                                $dnsForwarders = "None"
                            }
                        }
                        else {
                            # Fallback to CIM/WMI if Get-DnsServerForwarder is not available locally
                            $dnsObj = Get-CimInstance -Namespace root\MicrosoftDNS -ClassName MicrosoftDNS_Server -ComputerName $server.Name -ErrorAction Stop
                            if ($dnsObj -and $dnsObj.Forwarders) {
                                $dnsForwarders = ($dnsObj.Forwarders) -join ", "
                            }
                            else {
                                $dnsForwarders = "None"
                            }
                        }
                    }
                    catch {
                        $dnsForwarders = "Unknown / Query Failed"
                    }
                }
                
                $serverInfo += [PSCustomObject]@{
                    SiteName           = $site.Name
                    ServerName         = $server.Name
                    DNSHostName        = $server.dNSHostName
                    IPAddress          = $ipAddress
                    IsDomainController = $isDC
                    Domain             = $domain
                    IsGlobalCatalog    = $isGC
                    DNSForwarders      = $dnsForwarders
                    Status             = $dcStatus
                }
            }
            catch {
                # This block now catches the error for a single server and reports it.
                # The script will then continue to the next server in the list.
                $serverInfo += [PSCustomObject]@{
                    SiteName           = $site.Name
                    ServerName         = $server.Name
                    DNSHostName        = $server.dNSHostName
                    IPAddress          = "N/A"
                    IsDomainController = $false
                    Domain             = "N/A"
                    IsGlobalCatalog    = "N/A"
                    DNSForwarders      = "N/A"
                    Status             = "ERROR: Not a DC or unreachable."
                }
            }
        }
    }

    # Display server information
    if ($serverInfo) {
        Write-Host "`n=== AD Site Server Details ===" -ForegroundColor Green
        $serverInfo | Format-Table -AutoSize

        # Display DNS Server Forwarders details if available
        $dnsServers = $serverInfo | Where-Object { $_.IsDomainController -eq $true -and $_.DNSForwarders -ne "N/A" }
        if ($dnsServers) {
            Write-Host "`n=== DNS Server Forwarders ===" -ForegroundColor Green
            foreach ($dnsServer in $dnsServers) {
                Write-Host "Server: $($dnsServer.ServerName) ($($dnsServer.IPAddress))" -ForegroundColor Cyan
                Write-Host "Forwarders: $($dnsServer.DNSForwarders)"
            }
        }
    }
    else {
        Write-Host "No servers found in AD sites." -ForegroundColor Yellow
    }
}
catch {
    $err = $_
    Write-Host ("A critical error occurred while retrieving AD site information: {0}" -f $err) -ForegroundColor Red
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
        $err = $_
        Write-Host ("Error retrieving FSMO roles: {0}" -f $err) -ForegroundColor Red
    }
}


# --- Replication Diagnostics ---
function Run-RepadminCommands {
    Write-Host "`n=== Replication Summary (repadmin /replsummary) ===" -ForegroundColor Green
    try { repadmin /replsummary } catch { $err = $_; Write-Host ("Error running repadmin /replsummary: {0}" -f $err) -ForegroundColor Red }

    Write-Host "`n=== Replication Queue (repadmin /queue) ===" -ForegroundColor Green
    try { repadmin /queue } catch { $err = $_; Write-Host ("Error running repadmin /queue: {0}" -f $err) -ForegroundColor Red }

    Write-Host "`n=== Replication Sync Status (repadmin /syncall) ===" -ForegroundColor Green
    try { repadmin /syncall /e /d } catch { $err = $_; Write-Host ("Error running repadmin /syncall: {0}" -f $err) -ForegroundColor Red }

    Write-Host "`n=== KCC Topology Generation (repadmin /kcc) ===" -ForegroundColor Green
    try {
        if ($domainControllers -and $domainControllers.Count -gt 0) {
            foreach ($dc in $domainControllers) {
                $memberName = if ($dc.DNSHostName) { $dc.DNSHostName } else { $dc.Name }
                try {
                    Write-Host "Running repadmin /kcc on $memberName"
                    repadmin /kcc $memberName
                }
                catch {
                    $err = $_
                    Write-Host ("Error running repadmin /kcc on {0}: {1}" -f $memberName, $err) -ForegroundColor Red
                }
            }
        }
        else {
            Write-Host "No domain controllers found to run repadmin /kcc." -ForegroundColor Yellow
        }
    }
    catch {
        $err = $_
        Write-Host ("Unexpected error during repadmin /kcc operations: {0}" -f $err) -ForegroundColor Red
    }
}

function Run-NetworkConnectivityTests {
    Write-Host "`n=== Network Connectivity Tests (Test-NetConnection) ===" -ForegroundColor Green

    $ports = @{
        'LDAP'     = 389
        'LDAPS'    = 636
        'Kerberos' = 88
        'DNS'      = 53
        'SMB'      = 445
        'RPC'      = 135
    }

    if (-not ($domainControllers -and $domainControllers.Count -gt 0)) {
        Write-Host "No domain controllers found for network connectivity tests." -ForegroundColor Yellow
        return
    }

    foreach ($dc in $domainControllers) {
        $target = if ($dc.DNSHostName) { $dc.DNSHostName } else { $dc.Name }
        Write-Host "`n--- Testing connectivity to $target ---" -ForegroundColor Cyan

        foreach ($svc in $ports.Keys) {
            $port = $ports[$svc]
            try {
                $res = Test-NetConnection -ComputerName $target -Port $port -WarningAction SilentlyContinue
                $success = $false
                if ($null -ne $res) {
                    if ($res.TcpTestSucceeded -eq $true) { $success = $true }
                }

                if ($success) {
                    Write-Host "$svc ($port) on $target : SUCCESS" -ForegroundColor Green
                }
                else {
                    Write-Host "$svc ($port) on $target : FAILED" -ForegroundColor Red
                }
            }
            catch {
                $err = $_
                Write-Host ("Error testing {0} ({1}) on {2}: {3}" -f $svc, $port, $target, $err) -ForegroundColor Red
            }
        }
    }
}

# --- DFSR Diagnostic Checks ---
function Ensure-DFSRDiagTool {
    Write-Host "`n=== DFSR Diagnostic Tool Check ===" -ForegroundColor Green

    $dfsrPath = Get-Command dfsrdiag.exe -ErrorAction SilentlyContinue
    if ($dfsrPath) {
        Write-Host "dfsrdiag is already available." -ForegroundColor Green
        return $true
    }

    Write-Host "dfsrdiag is not available. Attempting installation..." -ForegroundColor Yellow
    $installSucceeded = $false

    if (Get-Command Install-WindowsFeature -ErrorAction SilentlyContinue) {
        try {
            Install-WindowsFeature RSAT-DFS-Mgmt-Con -IncludeAllSubFeature -ErrorAction Stop | Out-Null
            $installSucceeded = $true
        }
        catch {
            $err = $_
            Write-Host ("Install-WindowsFeature failed: {0}" -f $err) -ForegroundColor Red
        }
    }
    elseif (Get-Command Add-WindowsCapability -ErrorAction SilentlyContinue) {
        try {
            Add-WindowsCapability -Online -Name "Rsat.Dfs.Tools~~~~0.0.1.0" -ErrorAction Stop | Out-Null
            $installSucceeded = $true
        }
        catch {
            $err = $_
            Write-Host ("Add-WindowsCapability failed: {0}" -f $err) -ForegroundColor Red
        }
    }
    elseif (Get-Command Enable-WindowsOptionalFeature -ErrorAction SilentlyContinue) {
        try {
            Enable-WindowsOptionalFeature -Online -FeatureName "RSATDFS-Mgmt-Con" -NoRestart -All -ErrorAction Stop | Out-Null
            $installSucceeded = $true
        }
        catch {
            $err = $_
            Write-Host ("Enable-WindowsOptionalFeature failed: {0}" -f $err) -ForegroundColor Red
        }
    }
    else {
        Write-Host "No supported installation cmdlet found. Please install DFSR tools manually." -ForegroundColor Red
        return $false
    }

    if ($installSucceeded -and (Get-Command dfsrdiag.exe -ErrorAction SilentlyContinue)) {
        Write-Host "dfsrdiag installed successfully." -ForegroundColor Green
        return $true
    }

    Write-Host "dfsrdiag installation completed but the command is still unavailable." -ForegroundColor Red
    return $false
}

function Run-DFSRDiagChecks {
    if (-not (Ensure-DFSRDiagTool)) {
        Write-Host "Skipping DFSR diagnostics because dfsrdiag is unavailable." -ForegroundColor Yellow
        return
    }

    Write-Host "`n=== DFSR Diagnostic Checks ===" -ForegroundColor Green

    try {
        Write-Host "`n--- dfsrdiag pollad /verbose ---" -ForegroundColor Cyan
        & dfsrdiag pollad /verbose
    }
    catch {
        $err = $_
        Write-Host ("Error running dfsrdiag pollad: {0}" -f $err) -ForegroundColor Red
    }

    try {
        Write-Host "`n--- dfsrdiag replicationstate /verbose ---" -ForegroundColor Cyan
        & dfsrdiag replicationstate /verbose
    }
    catch {
        $err = $_
        Write-Host ("Error running dfsrdiag replicationstate: {0}" -f $err) -ForegroundColor Red
    }

    if ($domainControllers.Count -gt 0) {
        foreach ($dc in $domainControllers) {
            $memberName = if ($dc.DNSHostName) { $dc.DNSHostName } else { $dc.Name }
            try {
                Write-Host "`n--- dfsrdiag dumpmachinecfg /member:${memberName} ---" -ForegroundColor Cyan
                & dfsrdiag dumpmachinecfg /member:${memberName}
            }
            catch {
                Write-Host "Error running dfsrdiag dumpmachinecfg for ${memberName}: ${_}" -ForegroundColor Red
            }
        }
    }

    if ($domainControllers.Count -gt 1) {
        $sysvolFolderNames = @('SYSVOL Share', 'SYSVOL')
        Write-Host "`n--- SYSVOL backlog checks for Domain System Volume ---" -ForegroundColor Cyan
        $sysvolChecksPassed = 0
        $sysvolChecksFailed = 0
        
        foreach ($source in $domainControllers) {
            foreach ($destination in $domainControllers) {
                if ($source.Name -ne $destination.Name) {
                    $sourceName = if ($source.DNSHostName) { $source.DNSHostName } else { $source.Name }
                    $destinationName = if ($destination.DNSHostName) { $destination.DNSHostName } else { $destination.Name }
                    $pairCheckSucceeded = $false
                    
                    foreach ($rfname in $sysvolFolderNames) {
                        try {
                            Write-Host "`nChecking SYSVOL backlog from ${sourceName} to ${destinationName} using replicated folder '${rfname}'..." -ForegroundColor Yellow
                            & dfsrdiag backlog /rgname:"Domain System Volume" /rfname:"${rfname}" /smem:${sourceName} /rmem:${destinationName} /verbose
                            $pairCheckSucceeded = $true
                            Write-Host "[SUCCESS] Backlog check succeeded for ${sourceName} -> ${destinationName} (${rfname})" -ForegroundColor Green
                            break  # Exit loop if successful
                        }
                        catch {
                            # Continue to next folder name
                        }
                    }
                    
                    if ($pairCheckSucceeded) {
                        $sysvolChecksPassed++
                    }
                    else {
                        $sysvolChecksFailed++
                        Write-Host "[FAILED] Backlog check failed for ${sourceName} -> ${destinationName} (tried both SYSVOL and SYSVOL Share)" -ForegroundColor Red
                    }
                }
            }
        }
        
        Write-Host "`n=== SYSVOL Backlog Check Summary ===" -ForegroundColor Cyan
        Write-Host "Passed: ${sysvolChecksPassed} | Failed: ${sysvolChecksFailed}" -ForegroundColor Yellow
        if ($sysvolChecksFailed -eq 0) {
            Write-Host "[SUCCESS] All SYSVOL backlog checks passed!" -ForegroundColor Green
        }
        else {
            Write-Host "[WARNING] Some SYSVOL backlog checks failed. Review errors above." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "Not enough domain controllers found to perform SYSVOL backlog checks." -ForegroundColor Yellow
    }
}

# --- DCDiag Tests ---
function Run-DCDiagTests {
    Write-Host "`n=== DCDiag Replication Tests ===" -ForegroundColor Green
    try { dcdiag /test:replications /v } catch { $err = $_; Write-Host ("Error running dcdiag /test:Replication: {0}" -f $err) -ForegroundColor Red }

    Write-Host "`n=== DCDiag General Tests ===" -ForegroundColor Green
    try { dcdiag /v } catch { $err = $_; Write-Host ("Error running dcdiag: {0}" -f $err) -ForegroundColor Red }
}

# --- Event Viewer Check ---
function Check-EventViewerErrors {
    Write-Host "`n=== Event Viewer Replication Errors (Last 24 Hours) ===" -ForegroundColor Green
    $startTime = (Get-Date).AddHours(-24)

    $directoryEventIDs = 1000, 1004, 1006, 1311, 1388, 1865, 1925, 1926, 1988, 2103
    $dfsrEventIDs = 4000, 4002, 4004, 4012, 4013, 4102, 4112, 5002, 5004, 5008, 5014

    $directoryEvents = Get-WinEvent -FilterHashtable @{
        LogName   = 'Directory Service'
        StartTime = $startTime
        Level     = 2, 3 # 2 for Error, 3 for Warning
        Id        = $directoryEventIDs
    } -ErrorAction SilentlyContinue

    $dfsrEvents = Get-WinEvent -FilterHashtable @{
        LogName   = 'DFS Replication'
        StartTime = $startTime
        Level     = 2, 3
        Id        = $dfsrEventIDs
    } -ErrorAction SilentlyContinue

    if (($directoryEvents -and $directoryEvents.Count -gt 0) -or ($dfsrEvents -and $dfsrEvents.Count -gt 0)) {
        Write-Host "Found replication-related errors in Event Viewer:" -ForegroundColor Yellow
        if ($directoryEvents -and $directoryEvents.Count -gt 0) {
            Write-Host "`nDirectory Service Log:" -ForegroundColor Cyan
            $directoryEvents | Select-Object TimeCreated, Id, Message | Format-Table -Wrap -AutoSize
        }
        if ($dfsrEvents -and $dfsrEvents.Count -gt 0) {
            Write-Host "`nDFS Replication Log:" -ForegroundColor Cyan
            $dfsrEvents | Select-Object TimeCreated, Id, Message | Format-Table -Wrap -AutoSize
        }
    }
    else {
        Write-Host "No replication-related or SYSVOL-related errors found in Event Viewer in the last 24 hours." -ForegroundColor Green
    }
}

# --- Execute Diagnostic Steps ---
# This part now works correctly because the script will no longer halt on a single server error.
if ($domainControllers) {
    if ($FSMO) {
        # Run the FSMO Role check
        Get-FSMORoles
    }
    
    if ($Repadmin) {
        # Run replication diagnostics
        Run-RepadminCommands
    }
    
    if ($Connectivity) {
        # Run network connectivity tests to DCs for common AD ports
        Run-NetworkConnectivityTests
    }
    
    if ($DFSR) {
        # Run DFSR diagnostic checks
        Run-DFSRDiagChecks
    }
    
    if ($DCDiag) {
        # Run DCDiag tests
        Run-DCDiagTests
    }
    
    if ($EventViewer) {
        # Run Event Viewer checks
        Check-EventViewerErrors
    }
}
else {
    Write-Host "`nSkipping FSMO, replication, and diagnostic tests because no domain controllers were identified." -ForegroundColor Yellow
}

Write-Host "`n=== Troubleshooting Complete ===" -ForegroundColor Cyan
Write-Host "Review the output above for any errors or warnings." -ForegroundColor Yellow