<# 
(DFSR_Authoritative_Restore_Single_DC.ps1) :: (Revision # 2) / by Aaron Pleus - (11/14/2025)

   This script, like all scripts developed by Aaron Pleus, unless otherwise explicitly stated, is the copyrighted property of Aaron Pleus.;
   it may not be shared, sold, or distributed whole or in part, even with modifications applied, for any reason. this includes on reddit, on discord, or as part of other RMM tools.
   	
   The moment you edit this script it becomes your own risk and Aaron Pleus will not provide assistance with it.

   This script performs an authoritative restore of the SYSVOL folder on a single Domain Controller.
   It is designed to fix DFSR errors caused by the server being offline or isolated for longer 
   than the 'MaxOfflineTimeInDays' threshold.

   WARNING: 
   - RUN THIS SCRIPT ONLY on the single, affected Domain Controller.
   - This procedure is for a server that is the ONLY Domain Controller in the domain.
   - Ensure you have a current, verifiable System State backup before proceeding.

This script does the following:
# 1. Checks for Administrator privileges and the required Active Directory PowerShell module.
# 2. Identifies the correct Active Directory objects for the DC's SYSVOL subscription.
# 3. Disables the SYSVOL replication subscription and sets the authoritative restore flag (msDFSR-Options=1).
# 4. Restarts the DFSR service to force it to read the new configuration.
# 5. Re-enables the SYSVOL subscription and cleans up the restore flag.
# 6. Forces DFSR to poll for the final configuration changes.
# 7. Provides instructions for verification.
#>

# Define Log Path
$logPath = "C:\Logs\DFSR-Authoritative-Restore_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# Function to write to log file and console
function Write-Log {
    param ([string]$Message)
    $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): $Message"
    $logMessage | Out-File -FilePath $logPath -Append
    Write-Host $logMessage
}

# --- PRE-FLIGHT CHECKS ---

# 1. Ensure script runs with administrative privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: This script requires administrative privileges. Please re-run from an elevated PowerShell prompt." -ForegroundColor Red
    exit 1
}

# Create log directory if it doesn't exist
$logDir = Split-Path $logPath -Parent
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

Write-Log "Starting DFSR Authoritative SYSVOL Restore script."

# 2. Check for and import the Active Directory module
if (-not (Get-Module -Name ActiveDirectory)) {
    Write-Log "Active Directory module not found. Attempting to install RSAT-AD-PowerShell feature..."
    try {
        Install-WindowsFeature RSAT-AD-PowerShell -ErrorAction Stop
        Import-Module ActiveDirectory
        Write-Log "Successfully installed and imported the Active Directory module."
    }
    catch {
        Write-Log "FATAL: Failed to install the Active Directory PowerShell module. Please install 'RSAT-AD-PowerShell' via Server Manager and re-run the script."
        exit 1
    }
}

# --- SCRIPT LOGIC ---

try {
    # Dynamically get DC and Domain information
    $dcName = $env:COMPUTERNAME
    $domainDN = (Get-ADDomain).DistinguishedName
    
    # Construct the Distinguished Name for the SYSVOL subscription object
    $subscriptionObjectDN = "CN=SYSVOL Subscription,CN=Domain System Volume,CN=DFSR-LocalSettings,CN=$dcName,OU=Domain Controllers,$domainDN"

    Write-Log "Target Domain Controller: $dcName"
    Write-Log "Target SYSVOL Subscription Object: $subscriptionObjectDN"

    if (-not (Get-ADObject -Filter "DistinguishedName -eq '$subscriptionObjectDN'")) {
        Write-Log "FATAL: Could not find the SYSVOL Subscription AD object at the expected path. Aborting."
        exit 1
    }

    # Step 1: Disable the subscription and set the authoritative flag
    Write-Log "Step 1: Disabling SYSVOL subscription and setting authoritative restore flag (msDFSR-Options = 1)..."
    Set-ADObject -Identity $subscriptionObjectDN -Replace @{
        'msDFSR-Enabled' = $false;
        'msDFSR-Options' = 1
    } -ErrorAction Stop
    Write-Log "Successfully set flags. The server is now marked for authoritative restore."

    # Step 2: Restart DFSR to force it to read the new authoritative configuration
    Write-Log "Step 2: Restarting the DFS Replication service to apply the authoritative setting..."
    Restart-Service -Name DFSR -Force -ErrorAction Stop
    Write-Log "DFS Replication service restarted. The service will now initialize SYSVOL from its local content."
    Write-Log "Waiting 60 seconds for the service to initialize..."
    Start-Sleep -Seconds 60

    # Step 3: Re-enable the subscription and clean up the flag
    Write-Log "Step 3: Re-enabling SYSVOL subscription and cleaning up the restore flag (msDFSR-Options = 0)..."
    Set-ADObject -Identity $subscriptionObjectDN -Replace @{
        'msDFSR-Enabled' = $true;
        'msDFSR-Options' = 0
    } -ErrorAction Stop
    Write-Log "Successfully re-enabled subscription and cleaned up flags."

    # Step 4: Force DFSR to poll for the final configuration update
    Write-Log "Step 4: Forcing DFSR to poll Active Directory for final configuration..."
    # Check if dfsrdiag is available, otherwise just restart the service again
    if (Get-Command dfsrdiag.exe -ErrorAction SilentlyContinue) {
        dfsrdiag.exe pollad
    } else {
        Write-Log "dfsrdiag.exe not found. Restarting DFSR service one more time to poll configuration."
        Restart-Service -Name DFSR -Force -ErrorAction Stop
    }
    Write-Log "Final polling command issued."

    # --- VERIFICATION ---
    Write-Log "----------------------------------------------------------------"
    Write-Log "SCRIPT EXECUTION COMPLETED."
    Write-Log "Verification Steps:"
    Write-Log "1. Open the Event Viewer and navigate to 'Applications and Services Logs' -> 'DFS Replication'."
    Write-Log "2. Look for Event ID 4602. This event confirms that the SYSVOL folder has been successfully initialized as authoritative."
    Write-Log "3. You should also see Event ID 5004 indicating the SYSVOL folder is now being shared."
    Write-Log "4. The Group Policy errors (Event 422) in the System log should now stop."
    Write-Log "5. You can run 'dcdiag /test:sysvolcheck' to confirm health."
    Write-Log "----------------------------------------------------------------"
}
catch {
    Write-Log "An error occurred during the script's execution: $($_.Exception.Message)"
    Write-Host "SCRIPT FAILED. Check the log for details: $logPath" -ForegroundColor Red
    exit 1
}

Write-Host "Script completed successfully. Please check the log file at $logPath and verify SYSVOL health." -ForegroundColor Green