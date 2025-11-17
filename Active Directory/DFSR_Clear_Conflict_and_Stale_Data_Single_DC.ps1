<# 
(DFSR_Clear_Conflict_and_Stale_Data_Single_DC.ps1) :: (Revision # 1)/Aaron Pleus - (07/28/2025)

   This script, like all scripts developed by Aaron Pleus, unless otherwise explicitly stated, is the copyrighted property of Aaron Pleus.;
   it may not be shared, sold, or distributed whole or in part, even with modifications applied, for any reason. this includes on reddit, on discord, or as part of other RMM tools.
   	
   The moment you edit this script it becomes your own risk and Aaron Pleus will not provide assistance with it.

This script does the following:
# Clears DFSR Conflict and Stale Data on a single Domain Controller
# Backs up the SYSVOL folder before making changes
# Stops the DFSR service, deletes ConflictAndDeleted folder and Dfsr.db, sets SYSVOL to authoritative, and restarts the DFSR service
# Verifies SYSVOL share 
# Forces DFSR to poll Active Directory for configuration changes
# Runs DCDIAG to check SYSVOL health

# Script Requires -RunAsAdministrator
#>


# Define variables
$sysvolPath = "C:\Windows\SYSVOL"  # Updated to include entire SYSVOL directory
$dfsrPrivatePath = "$sysvolPath\domain\DfsrPrivate"
$backupPath = "C:\Backups\SYSVOL_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
$logPath = "C:\Logs\Clear-DFSRStaleData_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# Function to write to log file
function Write-Log {
    param ($Message)
    $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): $Message"
    Write-Output $logMessage | Out-File -FilePath $logPath -Append
    Write-Host $logMessage
}

# Ensure script runs with administrative privileges
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "Error: This script requires administrative privileges. Please run as Administrator."
    exit 1
}

# Create log directory if it doesn't exist
$logDir = Split-Path $logPath -Parent
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    Write-Log "Created log directory: $logDir"
}

# Step 1: Backup SYSVOL folder
Write-Log "Starting backup of SYSVOL folder to $backupPath"
try {
    if (-not (Test-Path $sysvolPath)) {
        Write-Log "Error: SYSVOL path $sysvolPath does not exist."
        exit 1
    }
    New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
    Copy-Item -Path "$sysvolPath\*" -Destination $backupPath -Recurse -Force -ErrorAction Stop
    # Verify backup contains key subfolders
    $expectedSubfolders = @("sysvol", "domain", "staging", "staging areas")
    $backupSubfolders = Get-ChildItem -Path $backupPath -Directory | Select-Object -ExpandProperty Name
    $missingSubfolders = $expectedSubfolders | Where-Object { $_ -notin $backupSubfolders }
    if ($missingSubfolders) {
        Write-Log "Warning: Backup may be incomplete. Missing subfolders: $($missingSubfolders -join ', ')"
    } else {
        Write-Log "Backup of SYSVOL completed successfully. All expected subfolders present."
    }
}
catch {
    Write-Log "Error during backup: $($_.Exception.Message)"
    exit 1
}

# Step 2: Stop DFSR service
Write-Log "Stopping DFS Replication service..."
try {
    Stop-Service -Name DFSR -Force -ErrorAction Stop
    Write-Log "DFS Replication service stopped."
}
catch {
    Write-Log "Error stopping DFSR service: $($_.Exception.Message)"
    exit 1
}

# Step 3: Delete DFSR ConflictAndDeleted folder and Dfsr.db
Write-Log "Deleting DFSR ConflictAndDeleted folder and Dfsr.db file..."
try {
    if (Test-Path $dfsrPrivatePath) {
        Remove-Item -Path "$dfsrPrivatePath\ConflictAndDeleted" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$dfsrPrivatePath\Dfsr.db" -Force -ErrorAction SilentlyContinue
        Write-Log "Successfully deleted ConflictAndDeleted folder and Dfsr.db file."
    }
    else {
        Write-Log "Warning: DFSRPrivate folder not found at $dfsrPrivatePath. Skipping deletion."
    }
}
catch {
    Write-Log "Error during deletion of DFSR files: $($_.Exception.Message)"
    exit 1
}

# Step 4: Set SYSVOL to authoritative (if applicable)
Write-Log "Setting SYSVOL to authoritative in registry..."
try {
    $registryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\DFSR\Parameters\SysVols"
    if (Test-Path $registryPath) {
        Set-ItemProperty -Path $registryPath -Name "SysVolInfo" -Value "Authoritative" -ErrorAction Stop
        Write-Log "SYSVOL set to authoritative."
    }
    else {
        Write-Log "Warning: SysVolInfo registry key not found. Skipping this step."
    }
}
catch {
    Write-Log "Error setting registry key: $($_.Exception.Message)"
}

# Step 5: Start DFSR service
Write-Log "Starting DFS Replication service..."
try {
    Start-Service -Name DFSR -ErrorAction Stop
    Write-Log "DFS Replication service started."
}
catch {
    Write-Log "Error starting DFSR service: $($_.Exception.Message)"
    exit 1
}

# Step 6: Verify SYSVOL share
Write-Log "Verifying SYSVOL share accessibility..."
try {
    $serverName = $env:COMPUTERNAME
    if (Test-Path "\\$serverName\SYSVOL") {
        Write-Log "SYSVOL share is accessible at \\$serverName\SYSVOL."
    }
    else {
        Write-Log "Warning: SYSVOL share is not accessible at \\$serverName\SYSVOL."
    }
}
catch {
    Write-Log "Error verifying SYSVOL share: $($_.Exception.Message)"
}

# Step 7: Force DFSR to poll Active Directory
Write-Log "Forcing DFSR to poll Active Directory configuration..."
try {
    $dfsrdiagOutput = dfsrdiag pollad | Out-String -Width 120
    Write-Log "dfsrdiag pollad executed successfully.`nOutput:`n$dfsrdiagOutput"
}
catch {
    Write-Log "Error running dfsrdiag pollad: $($_.Exception.Message)"
}

# Step 8: Run DCDIAG to check SYSVOL health
Write-Log "Running DCDIAG to verify SYSVOL health..."
try {
    # Run dcdiag and capture output
    $dcdiagOutput = dcdiag /test:sysvolcheck | Out-String -Width 120
    # Split output into lines and filter out empty lines
    $dcdiagLines = $dcdiagOutput -split "`n" | Where-Object { $_ -match '\S' }
    # Format output with clear sections
    $formattedOutput = @()
    $currentTest = ""
    foreach ($line in $dcdiagLines) {
        $line = $line.Trim()
        if ($line -match "Doing primary tests") {
            $formattedOutput += "===== DCDIAG SYSVOL Check Results ====="
        }
        elseif ($line -match "Testing server:") {
            $currentTest = $line
            $formattedOutput += "`n$currentTest"
        }
        elseif ($line -match "Starting test:") {
            $currentTest = $line
            $formattedOutput += "`n$currentTest"
        }
        elseif ($line -match "passed test|failed test") {
            $formattedOutput += "  $line"
        }
        else {
            $formattedOutput += "    $line"
        }
    }
    # Join formatted output for logging
    $formattedDcdiag = $formattedOutput -join "`n"
    Write-Log "DCDIAG Output:`n$formattedDcdiag"
    Write-Host "DCDIAG Output:`n$formattedDcdiag"
}
catch {
    Write-Log "Error running DCDIAG: $($_.Exception.Message)"
}

Write-Log "Script execution completed. Check the DFS Replication event log for further details."
Write-Host "Script completed. Log file saved at: $logPath"