<# (AD_Replication_Troubleshooter.ps1) :: (Revision # 2)/Aaron Pleus - (05/13/2025)

   This script, like all scripts developed by Aaron Pleus, unless otherwise explicitly stated, is the copyrighted property of Aaron Pleus.;
   it may not be shared, sold, or distributed whole or in part, even with modifications applied, for any reason. this includes on reddit, on discord, or as part of other RMM tools.
   	
   The moment you edit this script it becomes your own risk and Aaron Pleus will not provide assistance with it.

   
.SYNOPSIS
Checks Active Directory replication health, reports failures, and guides users through metadata cleanup for offline Domain Controllers.

.DESCRIPTION
This script helps administrators monitor and resolve Active Directory replication issues:
1. Checks for the ActiveDirectory PowerShell module and connectivity to the target forest.
2. Retrieves and summarizes replication failures across the forest.
3. Identifies Domain Controllers (DCs) with persistent replication failures.
4. Guides users step-by-step through investigating and cleaning up offline DCs, with clear prompts and confirmations.
5. Logs all actions and errors to a file for auditing.
6. Provides detailed error messages to prevent crashes and aid troubleshooting.

.PARAMETER WarningThresholdDays
Number of days a replication failure must persist to be flagged as a warning. Default: 5

.PARAMETER CleanupThresholdDays
Number of days a replication failure must persist AND the source DC must be offline to be considered for metadata cleanup.
Must be greater than WarningThresholdDays. Default: 100

.PARAMETER TargetForest
The target forest FQDN. Defaults to the current user's forest.

.PARAMETER DebugMode
Enables detailed error output for troubleshooting. Default: $false

.EXAMPLE
.\Check-ADReplicationHealth.ps1 -Verbose
Runs the script with default thresholds and verbose output.

.EXAMPLE
.\Check-ADReplicationHealth.ps1 -WarningThresholdDays 7 -CleanupThresholdDays 90 -DebugMode
Runs with custom thresholds and detailed error output.

.NOTES
- Requires the Active Directory PowerShell module (RSAT-AD-Tools).
- Requires permissions to query replication status and perform metadata cleanup (e.g., Domain Admins).
- Metadata cleanup is PERMANENT. Ensure the DC is truly offline before proceeding.
- Logs are saved to the script's directory as ADReplicationHealth_Log_<timestamp>.log.
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
    
    [string]$TargetForest = (Get-ADForest).Name,
    
    [switch]$DebugMode
)

# --- Script Setup ---
$ErrorActionPreference = 'Stop'
$VerbosePreference = 'Continue'

# Initialize Logging
$logFileName = "ADReplicationHealth_Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$logFilePath = Join-Path -Path $PSScriptRoot -ChildPath $logFileName
function Write-Log {
    param($Message)
    $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): $Message"
    $logEntry | Out-File -FilePath $logFilePath -Append -Encoding UTF8
    if ($DebugMode) { Write-Verbose $logEntry }
}

Write-Log "Starting AD Replication Health Check"
Write-Verbose "Parameters: WarningThreshold=$WarningThresholdDays days, CleanupThreshold=$CleanupThresholdDays days, TargetForest=$TargetForest"
Write-Verbose "Logs saved to: $logFilePath"

# Introduction for user
Write-Host "`n=== Active Directory Replication Health Check ===" -ForegroundColor Cyan
Write-Host "This script will:"
Write-Host "- Check replication status across all Domain Controllers in '$TargetForest'."
Write-Host "- Identify DCs with replication failures older than $WarningThresholdDays days."
Write-Host "- Guide you through investigating and cleaning up offline DCs (failures older than $CleanupThresholdDays days)."
Write-Host "- Log all actions to '$logFilePath'."
Write-Host "Press Enter to continue, or Ctrl+C to cancel."
Read-Host

try {
    # --- Check AD Module and Connectivity ---
    Write-Host "`nChecking prerequisites..." -ForegroundColor Cyan
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        $errorMsg = "Active Directory PowerShell module not installed. Install 'RSAT: Active Directory Domain Services and Lightweight Directory Services Tools'."
        Write-Log $errorMsg
        Write-Error $errorMsg
        Write-Host "Please install the module and re-run the script. Press Enter to exit."
        Read-Host
        return
    }

    Write-Verbose "Importing Active Directory module..."
    Import-Module ActiveDirectory
    Write-Verbose "Testing connectivity to forest '$TargetForest'..."
    Get-ADForest -Identity $TargetForest | Out-Null
    Write-Host "Connected to forest '$TargetForest' successfully." -ForegroundColor Green
    Write-Log "Connected to forest '$TargetForest'"

    # --- Get Replication Data ---
    Write-Host "`nGathering replication failure information..." -ForegroundColor Cyan
    $replicationFailures = Get-ADReplicationFailure -Target $TargetForest -Scope Forest
    $allDCs = Get-ADDomainController -Filter * -Server $TargetForest
    Write-Verbose "Retrieved status for $($allDCs.Count) DCs"
    Write-Log "Retrieved replication status for $($allDCs.Count) DCs"

    # --- Report Summary ---
    $failureCount = $replicationFailures.Count
    $failedDCs = $replicationFailures.Server | Sort-Object -Unique
    $successCount = ($allDCs.Name | Where-Object { $_ -notin $failedDCs }).Count

    Write-Host "`n--- Replication Status Summary ---" -ForegroundColor Green
    Write-Host "Total DCs: $($allDCs.Count)"
    Write-Host "Successful DCs: $successCount" -ForegroundColor Green
    Write-Log "Summary: $failureCount failure(s), $successCount successful DC(s)"

    if ($failureCount -eq 0) {
        Write-Host "No replication failures detected." -ForegroundColor Green
        Write-Host "No further action needed. Press Enter to exit."
        Write-Log "No replication failures detected"
        Read-Host
        return
    } else {
        Write-Host "$failureCount replication failure(s) detected." -ForegroundColor Yellow
        Write-Host "Note: A single DC issue may cause multiple failure instances."
        Write-Host "Press Enter to review details."
        Read-Host
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

    Write-Progress -Activity "Analyzing Replication Failures" -Completed

    # --- Interactive Remediation ---
    if ($problematicPartners.Count -gt 0) {
        Write-Host "`n=== Potential Lingering Objects Investigation ===" -ForegroundColor Magenta
        Write-Host "The following DCs have replication failures older than $CleanupThresholdDays days:"
        $problematicPartners.GetEnumerator() | ForEach-Object {
            Write-Host "- $($_.Name) (Oldest failure: $($_.Value.FailureAgeDays) days, reported by $($_.Value.ReportedBy.Count) DC(s))"
        }
        Write-Host "`nThese DCs may need metadata cleanup if they are permanently offline."
        Write-Warning "Metadata cleanup permanently removes a DC from Active Directory. Only proceed if a DC is unrecoverable."
        Write-Host "The script will guide you through checking each DC's status and deciding whether to clean it up."
        Write-Host "Press Enter to begin investigation."
        Read-Host
        Write-Log "Starting investigation of problematic DCs"

        foreach ($partnerEntry in $problematicPartners.GetEnumerator() | Sort-Object {$_.Value.FailureAgeDays} -Descending) {
            $partnerDCName = $partnerEntry.Name
            $partnerFailureAge = $partnerEntry.Value.FailureAgeDays

            Write-Host "`n--- Investigating DC: $partnerDCName ---" -ForegroundColor Cyan
            Write-Host "Failure Age: $partnerFailureAge days"
            Write-Host "Reported by: $($partnerEntry.Value.ReportedBy -join ', ')"
            Write-Host "`nStep 1: Check if '$partnerDCName' is online by pinging it."
            Write-Host "If offline, you can choose to perform metadata cleanup (permanent removal)."
            Write-Host "Do you want to proceed with checking '$partnerDCName'? (Y/N)"

            $choice = Read-Host
            if ($choice -ne 'Y' -and $choice -ne 'y') {
                Write-Verbose "Skipping investigation for $partnerDCName"
                Write-Log "Skipped investigation for DC '$partnerDCName'"
                continue
            }

            Write-Verbose "Pinging $partnerDCName..."
            Write-Log "Pinging DC '$partnerDCName'"
            $pingSuccess = Test-Connection -ComputerName $partnerDCName -Count 2 -Quiet -ErrorAction SilentlyContinue

            if ($pingSuccess) {
                Write-Host "`nResult: '$partnerDCName' is ONLINE." -ForegroundColor Green
                Write-Host "The DC responded to ping, so it may still be operational."
                Write-Host "Recommendation: Manually investigate the replication issue ($partnerFailureAge days old)."
                Write-Host "Try running:"
                Write-Host "  - dcdiag /s:$partnerDCName"
                Write-Host "  - repadmin /showrepl $partnerDCName"
                Write-Host "  - repadmin /replsummary"
                Write-Host "Press Enter to continue to the next DC."
                Write-Log "DC '$partnerDCName' is online; manual investigation recommended"
                Read-Host
            } else {
                Write-Host "`nResult: '$partnerDCName' is OFFLINE (no ping response)." -ForegroundColor Red
                Write-Host "This DC may be permanently offline, causing lingering objects."
                Write-Host "`nStep 2: Decide whether to perform metadata cleanup."
                Write-Host "Metadata cleanup will:"
                Write-Host "- Permanently remove '$partnerDCName' from Active Directory."
                Write-Host "- Delete all references to this DC across the forest."
                Write-Host "- Only proceed if '$partnerDCName' will never be brought back online."
                Write-Warning "This action is IRREVERSIBLE!"
                Write-Host "Do you want to attempt metadata cleanup for '$partnerDCName'?"
                Write-Host "Type 'YES' to proceed, or anything else to skip."

                $confirmCleanup = Read-Host
                if ($confirmCleanup -eq 'YES') {
                    Write-Host "`nStep 3: Confirm metadata cleanup for '$partnerDCName'."
                    Write-Host "You are about to permanently remove '$partnerDCName' from Active Directory."
                    Write-Host "This will affect all DCs in the forest and cannot be undone."
                    Write-Host "Confirm by typing 'CONFIRM' to proceed, or anything else to cancel."

                    $finalConfirm = Read-Host
                    if ($finalConfirm -eq 'CONFIRM') {
                        Write-Log "Attempting metadata cleanup for DC '$partnerDCName'"
                        if ($PSCmdlet.ShouldProcess($partnerDCName, "Remove-ADDomainController -ForceRemoval")) {
                            try {
                                $liveDC = $partnerEntry.Value.ReportedBy | Select-Object -First 1
                                if (-not $liveDC) {
                                    $liveDC = ($allDCs | Where-Object {$_.Name -ne $partnerDCName} | Select-Object -First 1).Name
                                }
                                if (-not $liveDC) {
                                    $errorMsg = "No live DC found to perform metadata cleanup for '$partnerDCName'."
                                    Write-Error $errorMsg
                                    Write-Log $errorMsg
                                    Write-Host "Press Enter to continue to the next DC."
                                    Read-Host
                                    continue
                                }

                                Write-Host "Executing cleanup on server '$liveDC' for DC '$partnerDCName'..." -ForegroundColor Yellow
                                Write-Verbose "Running Remove-ADDomainController for '$partnerDCName' on '$liveDC'"
                                Remove-ADDomainController -Identity $partnerDCName -ForceRemoval -Server $liveDC -Confirm:$false
                                Write-Host "Metadata cleanup for '$partnerDCName' succeeded." -ForegroundColor Green
                                Write-Host "Replication convergence may take time. Monitor with 'repadmin /replsummary'."
                                Write-Log "Success: Metadata cleanup for '$partnerDCName' completed using server '$liveDC'"
                                $problematicPartners.Remove($partnerDCName)
                            } catch {
                                $errorMsg = "Metadata cleanup for '$partnerDCName' failed. Error: $($_.Exception.Message)"
                                Write-Error $errorMsg
                                Write-Log $errorMsg
                                Write-Host "Recommendation: Try manual cleanup using 'ntdsutil' or AD Sites and Services."
                                Write-Host "Press Enter to continue to the next DC."
                            } finally {
                                Read-Host
                            }
                        }
                    } else {
                        Write-Host "Metadata cleanup for '$partnerDCName' cancelled." -ForegroundColor Yellow
                        Write-Log "Cancelled: Metadata cleanup for '$partnerDCName' (user cancelled at final confirmation)"
                        Write-Host "Press Enter to continue to the next DC."
                        Read-Host
                    }
                } else {
                    Write-Host "Metadata cleanup for '$partnerDCName' cancelled." -ForegroundColor Yellow
                    Write-Log "Cancelled: Metadata cleanup for '$partnerDCName' (user cancelled)"
                    Write-Host "Press Enter to continue to the next DC."
                    Read-Host
                }
            }
        }
    } else {
        Write-Host "`nNo replication failures older than $CleanupThresholdDays days found." -ForegroundColor Green
        Write-Log "No failures older than $CleanupThresholdDays days found"
    }
} catch {
    $errorMsg = "Unexpected error occurred: $($_.Exception.Message)"
    Write-Error $errorMsg
    Write-Log $errorMsg
    if ($DebugMode) {
        Write-Host "Debug Info: $($_.Exception | Format-List -Property * -Force | Out-String)" -ForegroundColor Red
    }
    Write-Host "Review the log file at '$logFilePath' for details."
    Write-Host "Press Enter to exit."
    Read-Host
}

Write-Host "`n=== Script Finished ===" -ForegroundColor Cyan
Write-Log "Script completed"
Write-Host "Review the log file at '$logFilePath' for a complete record of actions."
Write-Host "Press Enter to exit."
Read-Host