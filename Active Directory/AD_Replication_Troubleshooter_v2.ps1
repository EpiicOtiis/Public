<# (AD_Replication_Troubleshooter.ps1) :: (Revision # 2)/Aaron Pleus - (05/13/2025)

   This script, like all scripts developed by Aaron Pleus, unless otherwise explicitly stated, is the copyrighted property of Aaron Pleus.;
   it may not be shared, sold, or distributed whole or in part, even with modifications applied, for any reason. this includes on reddit, on discord, or as part of other RMM tools.
   	
   The moment you edit this script it becomes your own risk and Aaron Pleus will not provide assistance with it.

.SYNOPSIS
Checks Active Directory replication health, reports failures, and offers interactive remediation
for lingering objects caused by offline Domain Controllers.

.DESCRIPTION
This script performs the following actions:
1. Imports the ActiveDirectory PowerShell module.
2. Retrieves replication failure information for the entire AD forest.
3. Reports a summary of replication status (successes and failures).
4. Identifies replication failures older than a specified threshold ($WarningThresholdDays).
5. For failures older than a critical threshold ($CleanupThresholdDays):
    a. Prompts the user to investigate the source DC of the failure.
    b. If investigation is confirmed, attempts to ping the source DC.
    c. If the source DC is offline and the failure is older than $CleanupThresholdDays:
        i. Warns the user about metadata cleanup.
        ii. Prompts for explicit confirmation to perform metadata cleanup.
        iii. If confirmed, attempts metadata cleanup using Remove-ADDomainController -ForceRemoval.
    d. If the source DC is online or the failure is not old enough, suggests manual investigation.
6. Provides verbose output and logs metadata cleanup attempts to a file.

.PARAMETER WarningThresholdDays
The number of days a replication failure must persist to be flagged as a warning.
Default: 5

.PARAMETER CleanupThresholdDays
The number of days a replication failure must persist AND the source DC must be offline
to be considered for metadata cleanup. Must be greater than WarningThresholdDays.
Default: 100

.PARAMETER TargetForest
Specify the target forest FQDN. Defaults to the current user's forest.

.EXAMPLE
.\Check-ADReplicationHealth.ps1 -Verbose
Runs the script with default thresholds and verbose output.

.EXAMPLE
.\Check-ADReplicationHealth.ps1 -WarningThresholdDays 7 -CleanupThresholdDays 90 -Verbose
Runs the script with custom thresholds.

.NOTES
- Requires the Active Directory PowerShell module.
- Requires permissions to query replication status and perform metadata cleanup (e.g., Domain Admins).
- Metadata cleanup is PERMANENT. Ensure the DC is truly offline before proceeding.
- Logs metadata cleanup attempts to a file in the script's directory.
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [ValidateRange(1, [int]::MaxValue)]
    [int]$WarningThresholdDays = 5,
    
    [ValidateScript({
        if ($_ -le $WarningThresholdDays) {
            throw "CleanupThresholdDays must be greater than WarningThresholdDays ($WarningThresholdDays)."
        }
        $_ -ge 1
    })]
    [int]$CleanupThresholdDays = 100,
    
    [string]$TargetForest = (Get-ADForest).Name
)

# --- Script Setup ---
$VerbosePreference = 'Continue'
Write-Verbose "Starting AD Replication Health Check..."
Write-Verbose "Parameters: WarningThreshold=$WarningThresholdDays days, CleanupThreshold=$CleanupThresholdDays days, TargetForest=$TargetForest"

# Initialize Logging
$logFileName = "ADReplicationHealth_Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$logFilePath = Join-Path -Path $PSScriptRoot -ChildPath $logFileName
Write-Verbose "Logging metadata cleanup attempts to: $logFilePath"

# Check for AD Module
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Error "Active Directory PowerShell module not installed. Install 'RSAT: Active Directory Domain Services and Lightweight Directory Services Tools'."
    exit 1
}

try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Get-ADForest -Identity $TargetForest -ErrorAction Stop | Out-Null
    Write-Verbose "AD Module loaded and connectivity to '$TargetForest' confirmed."
} catch {
    Write-Error "Failed to connect to forest '$TargetForest'. Error: $($_.Exception.Message)"
    exit 1
}

# --- Get Replication Data ---
Write-Host "`nGathering replication failure information for '$TargetForest'..." -ForegroundColor Cyan
try {
    $replicationFailures = Get-ADReplicationFailure -Target $TargetForest -Scope Forest -ErrorAction Stop
    $allDCs = Get-ADDomainController -Filter * -Server $TargetForest
    Write-Verbose "Retrieved replication status for $($allDCs.Count) DCs."
} catch {
    Write-Error "Failed to retrieve replication failures. Error: $($_.Exception.Message)"
    exit 1
}

# --- Report Summary ---
$failureCount = $replicationFailures.Count
$failedDCs = $replicationFailures.Server | Sort-Object -Unique
$successCount = ($allDCs.Name | Where-Object { $_ -notin $failedDCs }).Count

Write-Host "`n--- Replication Status Summary ---" -ForegroundColor Green
if ($failureCount -eq 0) {
    Write-Host "No replication failures detected across $($allDCs.Count) Domain Controllers." -ForegroundColor Green
    Write-Host "Successful DCs: $successCount" -ForegroundColor Green
    exit 0
} else {
    Write-Host "Successful DCs: $successCount" -ForegroundColor Green
    Write-Host "$failureCount replication failure(s) detected." -ForegroundColor Yellow
    Write-Host "Note: A single DC issue may cause multiple failure instances."
}

# --- Analyze and Report Failures ---
Write-Host "`n--- Detailed Replication Failures ---" -ForegroundColor Yellow
$groupedFailures = $replicationFailures | Group-Object Server, Partner, Partition | Sort-Object Name
$problematicPartners = @{}

$totalFailures = $groupedFailures.Count
$currentFailure = 0

foreach ($group in $groupedFailures) {
    $currentFailure++
    $percentComplete = ($currentFailure / $totalFailures) * 100
    Write-Progress -Activity "Analyzing Replication Failures" -Status "Processing failure $currentFailure of $totalFailures" -PercentComplete $percentComplete -CurrentOperation "Server: $($group.Group[0].Server), Partner: $($group.Group[0].Partner), Partition: $($group.Group[0].Partition)"

    $failure = $group.Group | Select-Object -First 1
    $server = $failure.Server
    $partner = $failure.Partner
    $partition = $failure.Partition
    $lastSuccess = $failure.LastSuccessTime
    $lastFailure = $failure.LastFailureTime
    $failureCountInGroup = $group.Count
    $failureReason = $failure.FailureReason

    Write-Host "------------------------------------"
    Write-Host "Server: $server | Partner: $partner | Partition: $partition"
    Write-Host "Last Success: $($lastSuccess | Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Host "Last Failure: $($lastFailure | Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Host "Failure Count: $failureCountInGroup | Reason: $failureReason"

    if ($lastFailure) {
        $failureAge = (Get-Date) - $lastFailure
        Write-Host "Failure Age: $($failureAge.Days) days, $($failureAge.Hours) hours"

        if ($failureAge.TotalDays -gt $CleanupThresholdDays) {
            Write-Host "Status: CRITICAL - Failure older than $CleanupThresholdDays days." -ForegroundColor Red
            if (-not $problematicPartners.ContainsKey($partner)) {
                $problematicPartners[$partner] = @{
                    FailureAgeDays = $failureAge.Days
                    ReportedBy = New-Object System.Collections.Generic.List[string]
                }
            }
            $problematicPartners[$partner].ReportedBy.Add($server)
            if ($failureAge.Days -gt $problematicPartners[$partner].FailureAgeDays) {
                $problematicPartners[$partner].FailureAgeDays = $failureAge.Days
            }
        } elseif ($failureAge.TotalDays -gt $WarningThresholdDays) {
            Write-Host "Status: WARNING - Failure older than $WarningThresholdDays days." -ForegroundColor Yellow
        } else {
            Write-Host "Status: Recent failure." -ForegroundColor White
        }
    } else {
        Write-Host "Status: Failure time not available." -ForegroundColor Gray
    }
}

# Clear the progress bar
Write-Progress -Activity "Analyzing Replication Failures" -Completed

# --- Interactive Remediation ---
if ($problematicPartners.Count -gt 0) {
    Write-Host "`n--- Potential Lingering Objects Investigation ---" -ForegroundColor Magenta
    Write-Host "Source DCs with failures older than $CleanupThresholdDays days:" -ForegroundColor Yellow
    $problematicPartners.GetEnumerator() | ForEach-Object {
        Write-Host "- $($_.Name) (Oldest failure: $($_.Value.FailureAgeDays) days, reported by $($_.Value.ReportedBy.Count) DC(s))"
    }

    Write-Warning "Investigating may lead to metadata cleanup if DCs are offline. This is PERMANENT."
    foreach ($partnerEntry in $problematicPartners.GetEnumerator() | Sort-Object {$_.Value.FailureAgeDays} -Descending) {
        $partnerDCName = $partnerEntry.Name
        $partnerFailureAge = $partnerEntry.Value.FailureAgeDays

        Write-Host "`nInvestigating Partner DC: $partnerDCName (Failure age: $partnerFailureAge days)" -ForegroundColor Cyan
        Write-Host "Reported by: $($partnerEntry.Value.ReportedBy -join ', ')"

        $choice = Read-Host "Check status of '$partnerDCName'? (Y/N)"
        if ($choice -ne 'Y') {
            Write-Verbose "Skipping $partnerDCName."
            continue
        }

        Write-Verbose "Pinging $partnerDCName..."
        $pingSuccess = Test-Connection -ComputerName $partnerDCName -Count 2 -Quiet -ErrorAction SilentlyContinue

        if ($pingSuccess) {
            Write-Host "'$partnerDCName' is ONLINE." -ForegroundColor Green
            Write-Host "Recommendation: Investigate replication issue ($partnerFailureAge days old) manually using dcdiag, repadmin /showrepl, or /replsummary."
        } else {
            Write-Host "'$partnerDCName' is OFFLINE." -ForegroundColor Red
            Write-Warning "DC '$partnerDCName' is offline with failures older than $CleanupThresholdDays days."

            Write-Host "Metadata cleanup is irreversible. Only proceed if '$partnerDCName' is permanently offline." -ForegroundColor Red
            $confirmCleanup = Read-Host "Attempt METADATA CLEANUP for '$partnerDCName'? Type 'YES' to proceed."
            if ($confirmCleanup -eq 'YES') {
                # Log cleanup attempt
                $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): Attempting metadata cleanup for DC '$partnerDCName'."
                $logMessage | Out-File -FilePath $logFilePath -Append -Encoding UTF8

                if ($PSCmdlet.ShouldProcess($partnerDCName, "Remove-ADDomainController -ForceRemoval")) {
                    try {
                        $liveDC = $partnerEntry.Value.ReportedBy | Select-Object -First 1
                        if (-not $liveDC) {
                            $liveDC = ($allDCs | Where-Object {$_.Name -ne $partnerDCName} | Select-Object -First 1).Name
                        }
                        if (-not $liveDC) {
                            Write-Error "No live DC found for metadata cleanup."
                            $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): Failed: No live DC found for cleanup of '$partnerDCName'."
                            $logMessage | Out-File -FilePath $logFilePath -Append -Encoding UTF8
                            continue
                        }

                        Write-Verbose "Cleaning up '$partnerDCName' using '$liveDC'."
                        Remove-ADDomainController -Identity $partnerDCName -ForceRemoval -Server $liveDC -Confirm:$false -ErrorAction Stop
                        Write-Host "Metadata cleanup for '$partnerDCName' succeeded." -ForegroundColor Green
                        $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): Success: Metadata cleanup for '$partnerDCName' completed using server '$liveDC'."
                        $logMessage | Out-File -FilePath $logFilePath -Append -Encoding UTF8
                        $problematicPartners.Remove($partnerDCName)
                    } catch {
                        Write-Error "Metadata cleanup failed. Error: $($_.Exception.Message). Try 'ntdsutil' or AD Sites and Services."
                        $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): Failed: Metadata cleanup for '$partnerDCName' with error: $($_.Exception.Message)"
                        $logMessage | Out-File -FilePath $logFilePath -Append -Encoding UTF8
                    }
                }
            } else {
                Write-Host "Metadata cleanup cancelled." -ForegroundColor Yellow
                $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): Cancelled: Metadata cleanup for '$partnerDCName' by user."
                $logMessage | Out-File -FilePath $logFilePath -Append -Encoding UTF8
            }
        }
    }
} else {
    Write-Host "`nNo failures older than $CleanupThresholdDays days found." -ForegroundColor Green
}

Write-Host "`n--- Script Finished ---" -ForegroundColor Cyan
Read-Host "Press Enter to exit"