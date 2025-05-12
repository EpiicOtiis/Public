<# (AD_Replication_Troubleshooter.ps1) :: (Revision # 1)/Aaron Pleus - (04/10/2025)

   This script, like all scripts developed by Aaron Pleus, unless otherwise explicitly stated, is the copyrighted property of Aaron Pleus.;
   it may not be shared, sold, or distributed whole or in part, even with modifications applied, for any reason. this includes on reddit, on discord, or as part of other RMM tools.
   	
   The moment you edit this script it becomes your own risk and Aaron Pleus will not provide assistance with it.
#>

<#
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
    c. If the source DC is *offline* and the failure is older than $CleanupThresholdDays:
        i.  Warns the user about metadata cleanup.
        ii. Prompts for explicit confirmation to perform metadata cleanup.
        iii. If confirmed, attempts metadata cleanup using Remove-ADDomainController -ForceRemoval.
    d. If the source DC is online or the failure is not old enough for cleanup, suggests manual investigation.
6. Provides verbose output throughout the process.

.PARAMETER WarningThresholdDays
The number of days a replication failure must persist to be flagged as a warning.
Default: 5

.PARAMETER CleanupThresholdDays
The number of days a replication failure must persist AND the source DC must be offline
to be considered for metadata cleanup. This should typically be less than the
Tombstone Lifetime (TSL) but long enough to be sure the DC is permanently offline.
Default: 100

.PARAMETER TargetForest
Specify the target forest FQDN if running from a machine not joined to the target forest,
or to be explicit. Defaults to the current user's forest.

.EXAMPLE
.\Check-ADReplicationHealth.ps1 -Verbose

Runs the script with default thresholds and verbose output.

.EXAMPLE
.\Check-ADReplicationHealth.ps1 -WarningThresholdDays 7 -CleanupThresholdDays 90 -Verbose

Runs the script, flagging warnings for failures older than 7 days and considering cleanup
for offline DCs with failures older than 90 days.

.NOTES
- Requires the Active Directory PowerShell module installed.
- Requires permissions to query replication status (e.g., Domain Admins or delegated permissions).
- Metadata cleanup (Remove-ADDomainController -ForceRemoval) requires Domain Admins or Enterprise Admins permissions.
- Metadata cleanup is a PERMANENT operation. Ensure the DC is truly permanently offline before proceeding.
- The script identifies the 'Partner' DC in a failure as the potential source to investigate/remove.

.LINK
Get-ADReplicationFailure
https://docs.microsoft.com/en-us/powershell/module/activedirectory/get-adreplicationfailure

Remove-ADDomainController
https://docs.microsoft.com/en-us/powershell/module/activedirectory/remove-addomaincontroller
#>

[CmdletBinding(SupportsShouldProcess=$true)] # Adds -WhatIf, -Confirm support for destructive cmdlets
param(
    [int]$WarningThresholdDays = 5,
    [int]$CleanupThresholdDays = 100,
    [string]$TargetForest = (Get-ADForest).Name
)

# --- Script Setup ---
$VerbosePreference = 'Continue' # Ensure verbose messages are shown
Write-Verbose "Starting AD Replication Health Check Script..."
Write-Verbose "Parameters:"
Write-Verbose "  Warning Threshold: $WarningThresholdDays days"
Write-Verbose "  Cleanup Threshold: $CleanupThresholdDays days"
Write-Verbose "  Target Forest:     $TargetForest"

# Check for AD Module and Permissions (Basic)
Write-Verbose "Checking for Active Directory PowerShell Module..."
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Error "Active Directory PowerShell module is not installed. Please install 'RSAT: Active Directory Domain Services and Lightweight Directory Services Tools' feature."
    exit 1
}

try {
    Write-Verbose "Importing Active Directory Module..."
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Verbose "Testing basic AD connectivity to forest '$TargetForest'..."
    Get-ADForest -Identity $TargetForest -ErrorAction Stop | Out-Null
    Write-Verbose "AD Module loaded and basic connectivity successful."
} catch {
    Write-Error "Failed to import Active Directory module or connect to forest '$TargetForest'. Error: $($_.Exception.Message). Ensure the module is installed and you have permissions."
    exit 1
}

# --- Get Replication Data ---
Write-Host "`nGathering replication failure information for forest '$TargetForest'..." -ForegroundColor Cyan
try {
    # Get all replication failures in the forest
    $replicationFailures = Get-ADReplicationFailure -Target $TargetForest -Scope Forest -ErrorAction Stop
    $allDCs = Get-ADDomainController -Filter * -Server $TargetForest # Get all DCs for context
    Write-Verbose "Successfully retrieved replication status for $($allDCs.Count) DCs."
} catch {
    Write-Error "Failed to retrieve replication failures. Error: $($_.Exception.Message). Check permissions and connectivity to DCs."
    exit 1
}

# --- Report Summary ---
$failureCount = $replicationFailures.Count
$successCount = $allDCs.Count # Approximation: Assumes DCs not listed in failures are succeeding (or haven't reported yet)

Write-Host "`n--- Replication Status Summary ---" -ForegroundColor Green
if ($failureCount -eq 0) {
    Write-Host "No replication failures detected across $($allDCs.Count) Domain Controllers in forest '$TargetForest'." -ForegroundColor Green
    Write-Verbose "Script finished. No further action needed."
    exit 0
} else {
    Write-Host "$failureCount replication failure instance(s) detected." -ForegroundColor Yellow
    Write-Host "Note: A single DC issue can cause multiple failure instances (one per partner/partition)."
}

# --- Analyze and Report Failures ---
Write-Host "`n--- Detailed Replication Failures ---" -ForegroundColor Yellow

# Group failures by the DC experiencing the failure and its partner
$groupedFailures = $replicationFailures | Group-Object Server, Partner, Partition | Sort-Object Name

$problematicPartners = @{} # Hashtable to store partners with old failures

foreach ($group in $groupedFailures) {
    $failure = $group.Group | Select-Object -First 1 # Get representative failure details
    $server = $failure.Server
    $partner = $failure.Partner
    $partition = $failure.Partition
    $lastSuccess = $failure.LastSuccessTime
    $lastFailure = $failure.LastFailureTime
    $failureCountInGroup = $group.Count # How many times this specific link failed recently
    $failureReason = $failure.FailureReason

    Write-Host "------------------------------------"
    Write-Host "Server:         $server"
    Write-Host "Partner:        $partner"
    Write-Host "Partition:      $partition"
    Write-Host "Last Success:   $($lastSuccess | Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Host "Last Failure:   $($lastFailure | Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Host "Failure Count:  $failureCountInGroup"
    Write-Host "Failure Reason: $failureReason"

    if ($lastFailure) {
        $failureAge = (Get-Date) - $lastFailure
        Write-Host "Failure Age:    $($failureAge.Days) days, $($failureAge.Hours) hours"

        # Check against thresholds
        if ($failureAge.TotalDays -gt $CleanupThresholdDays) {
            Write-Host "Status:         CRITICAL - Failure older than $CleanupThresholdDays days." -ForegroundColor Red
            # Store the partner DC for potential investigation/cleanup
            if (-not $problematicPartners.ContainsKey($partner)) {
                $problematicPartners[$partner] = @{
                    FailureAgeDays = $failureAge.Days
                    LastFailureTime = $lastFailure
                    ReportedBy = New-Object System.Collections.Generic.List[string]
                }
            }
            $problematicPartners[$partner].ReportedBy.Add($server)
            # Update age if this failure is older than previously recorded for this partner
            if ($failureAge.Days -gt $problematicPartners[$partner].FailureAgeDays) {
                $problematicPartners[$partner].FailureAgeDays = $failureAge.Days
                $problematicPartners[$partner].LastFailureTime = $lastFailure
            }
        } elseif ($failureAge.TotalDays -gt $WarningThresholdDays) {
            Write-Host "Status:         WARNING - Failure older than $WarningThresholdDays days." -ForegroundColor Yellow
        } else {
            Write-Host "Status:         Recent failure." -ForegroundColor White
        }
    } else {
        Write-Host "Status:         Failure time not available." -ForegroundColor Gray
    }
}

# --- Interactive Remediation ---
if ($problematicPartners.Count -gt 0) {
    Write-Host "`n--- Potential Lingering Objects Investigation ---" -ForegroundColor Magenta
    Write-Host "The following source Domain Controllers (Partners) have failures older than $CleanupThresholdDays days:" -ForegroundColor Yellow
    $problematicPartners.GetEnumerator() | ForEach-Object {
        Write-Host "- $($_.Name) (Oldest failure reported: $($_.Value.FailureAgeDays) days ago by $($_.Value.ReportedBy.Count) DC(s))"
    }

    Write-Warning "Investigating these DCs may lead to metadata cleanup if they are confirmed offline."
    Write-Warning "Metadata cleanup is PERMANENT and should only be done if the DC is irrecoverable."

    foreach ($partnerEntry in $problematicPartners.GetEnumerator() | Sort-Object {$_.Value.FailureAgeDays} -Descending) {
        $partnerDCName = $partnerEntry.Name
        $partnerFailureAge = $partnerEntry.Value.FailureAgeDays
        $partnerLastFailure = $partnerEntry.Value.LastFailureTime

        Write-Host "`n------------------------------------"
        Write-Host "Investigating Partner DC: $partnerDCName" -ForegroundColor Cyan
        Write-Host "Oldest failure associated with this partner is $partnerFailureAge days old."
        Write-Host "Reported as failing source by: $($partnerEntry.Value.ReportedBy -join ', ')"

        # Prompt user to investigate this specific DC
        $choice = Read-Host "Do you want to check the status of '$partnerDCName'? (Y/N)"
        if ($choice -ne 'Y') {
            Write-Verbose "Skipping investigation for $partnerDCName."
            continue
        }

        # Check Connectivity
        Write-Verbose "Attempting to ping $partnerDCName..."
        $pingSuccess = Test-Connection -ComputerName $partnerDCName -Count 2 -Quiet -ErrorAction SilentlyContinue

        if ($pingSuccess) {
            Write-Host "Result: '$partnerDCName' is ONLINE (responding to ping)." -ForegroundColor Green
            Write-Host "Recommendation: Since the DC is online, the replication issue ($partnerFailureAge days old) needs manual investigation." -ForegroundColor Yellow
            Write-Host "Check Event Logs, run 'dcdiag /s:$partnerDCName', 'repadmin /showrepl $partnerDCName', and 'repadmin /replsummary' focusing on this DC."
        } else {
            Write-Host "Result: '$partnerDCName' is OFFLINE (did not respond to ping)." -ForegroundColor Red

            # Offer Metadata Cleanup only if offline AND failure age > cleanup threshold
            Write-Warning "Partner DC '$partnerDCName' appears OFFLINE and has replication failures older than $CleanupThresholdDays days."

            # *** CRITICAL SECTION - METADATA CLEANUP ***
            Write-Host "Metadata cleanup removes all traces of a permanently offline DC from Active Directory." -ForegroundColor Yellow
            Write-Host "This is irreversible. Only proceed if you are CERTAIN '$partnerDCName' will NEVER be online again." -ForegroundColor Red

            $confirmCleanup = Read-Host "Do you want to attempt METADATA CLEANUP for '$partnerDCName'? Type 'YES' to proceed, anything else to cancel."
            if ($confirmCleanup -eq 'YES') {
                Write-Warning "CONFIRMING METADATA CLEANUP for $partnerDCName."
                if ($PSCmdlet.ShouldProcess($partnerDCName, "Perform Metadata Cleanup (Remove-ADDomainController -ForceRemoval)")) {
                    try {
                        Write-Host "Attempting metadata cleanup for $partnerDCName..." -ForegroundColor Yellow
                        # Find a live DC to run the command against (preferably one that reported the failure)
                        $liveDC = $partnerEntry.Value.ReportedBy | Select-Object -First 1
                        if (-not $liveDC) {
                            # Fallback to any DC if none of the reporters are available (unlikely but possible)
                            $liveDC = ($allDCs | Where-Object {$_.Name -ne $partnerDCName} | Select-Object -First 1).Name
                        }

                        if (-not $liveDC) {
                            Write-Error "Could not find a live Domain Controller to target for metadata cleanup operation."
                            continue # Skip to next problematic partner
                        }

                        Write-Verbose "Executing Remove-ADDomainController against server '$liveDC' to clean up '$partnerDCName'."
                        Remove-ADDomainController -Identity $partnerDCName -ForceRemoval -Server $liveDC -Confirm:$false -ErrorAction Stop # Use -Confirm:$false because we did manual confirmation

                        Write-Host "Metadata cleanup command for '$partnerDCName' executed successfully." -ForegroundColor Green
                        Write-Host "Replication convergence may take time. Monitor replication health."
                        # Remove the cleaned DC from our list to avoid re-processing if script continues
                        $problematicPartners.Remove($partnerDCName)
                    } catch {
                        Write-Error "Metadata cleanup for '$partnerDCName' FAILED. Error: $($_.Exception.Message)"
                        Write-Error "Manual cleanup using 'ntdsutil' or AD Sites and Services might be required."
                        Write-Host "Please investigate the error message above."
                    }
                } else {
                    Write-Host "Metadata cleanup for '$partnerDCName' cancelled by user (-WhatIf or No to confirmation)." -ForegroundColor Yellow
                }
            } else {
                Write-Host "Metadata cleanup for '$partnerDCName' cancelled by user." -ForegroundColor Yellow
            }
            # *** END CRITICAL SECTION ***
        }
    }
} else {
    Write-Host "`nNo replication failures older than $CleanupThresholdDays days were found. No cleanup actions proposed." -ForegroundColor Green
}

Write-Host "`n--- Script Finished ---" -ForegroundColor Cyan
Write-Verbose "AD Replication Health Check script completed."
Read-Host "Press Enter to exit"