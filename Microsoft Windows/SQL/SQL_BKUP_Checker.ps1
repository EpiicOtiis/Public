<#
====================================================================
SQL Server Backup Diagnostic Tool (Refactored)
====================================================================
It automatically checks the last 7 days of SQL operations.
#>

$DaysBack = 7
$SqlInstance = 'localhost'
$StartTime = (Get-Date).AddDays(-$DaysBack)

function Write-Header {
    param([string]$Title)
    Write-Host "`n=== $Title ===" -ForegroundColor Cyan
}

# 1. Prerequisites Check
Write-Header "Initialization & Prerequisites"
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "You are not running PowerShell as Administrator. Event Log access may be restricted."
} else {
    Write-Host "Administrator privileges confirmed." -ForegroundColor Green
}

Write-Host "Target Instance : $SqlInstance"
Write-Host "Timeframe       : Last $DaysBack Days (Since $StartTime)"

# 2. SQL Helper Function
Add-Type -AssemblyName System.Data
function Invoke-SqlCmdQuery {
    param([string]$Query)
    $connectionString = "Server=$SqlInstance;Database=master;Integrated Security=True;Connect Timeout=15;"
    $connection = New-Object System.Data.SqlClient.SqlConnection $connectionString
    $command = $connection.CreateCommand()
    $command.CommandText = $Query
    
    try {
        $connection.Open()
        $adapter = New-Object System.Data.SqlClient.SqlDataAdapter $command
        $table = New-Object System.Data.DataTable
        $adapter.Fill($table) | Out-Null
        return $table
    } catch {
        Write-Warning "SQL Connection/Query Failed: $_"
        return $null
    } finally {
        if ($connection.State -eq 'Open') { $connection.Close() }
        if ($null -ne $connection) { $connection.Dispose() }
    }
}

# 3. Analyze SQL Backup Event Logs (Focusing on Errors/Warnings)
Write-Header "Windows Event Log Analysis (Last 7 Days)"
$backupEventIds = @(3041, 3201, 18210, 18204, 12291, 3013, 3047) # Primary failure/error IDs
try {
    $events = Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Id = $backupEventIds; StartTime = $StartTime } -ErrorAction Stop
    $sqlEvents = $events | Where-Object { $_.ProviderName -match 'SQL' }
    
    if ($sqlEvents) {
        Write-Host "Found $($sqlEvents.Count) backup-related error/warning events!" -ForegroundColor Red
        $sqlEvents | Select-Object TimeCreated, Id, LevelDisplayName, @{Name='Message';Expression={$_.Message -replace "`r`n", " "}} | 
            Format-Table -AutoSize -Wrap
    } else {
        Write-Host "No SQL backup errors found in the Windows Event Log." -ForegroundColor Green
    }
} catch {
    Write-Host "No backup error events found, or unable to read Application log." -ForegroundColor Yellow
}

# 4. Check Backup History in MSDB
Write-Header "Database Backup Status (MSDB History)"
$historyQuery = @"
WITH LatestBackups AS (
    SELECT database_name,
        MAX(CASE WHEN type = 'D' THEN backup_finish_date END) AS LastFullBackup,
        MAX(CASE WHEN type = 'L' THEN backup_finish_date END) AS LastLogBackup
    FROM msdb.dbo.backupset
    GROUP BY database_name
)
SELECT 
    d.name AS DatabaseName, 
    d.state_desc AS State, 
    d.recovery_model_desc AS RecoveryModel, 
    l.LastFullBackup, 
    l.LastLogBackup
FROM master.sys.databases d
LEFT JOIN LatestBackups l ON l.database_name = d.name
WHERE d.name <> 'tempdb'
ORDER BY d.name;
"@

$dbStatus = Invoke-SqlCmdQuery -Query $historyQuery

if ($dbStatus) {
    $issuesFound = 0
    foreach ($row in $dbStatus) {
        $dbName = $row.DatabaseName
        $state = $row.State
        $recovery = $row.RecoveryModel
        $lastFull = $row.LastFullBackup
        $lastLog = $row.LastLogBackup

        # Skip offline databases
        if ($state -ne 'ONLINE') { continue }

        $issue = ""
        if ([string]::IsNullOrEmpty($lastFull) -or $lastFull.GetType().Name -eq 'DBNull') {
            $issue = "MISSING: No Full Backup history found."
        } elseif ($lastFull -lt $StartTime) {
            $issue = "STALE: Last Full Backup is older than $DaysBack days ($lastFull)."
        } elseif ($recovery -ne 'SIMPLE') {
            if ([string]::IsNullOrEmpty($lastLog) -or $lastLog.GetType().Name -eq 'DBNull') {
                $issue = "MISSING: No Log Backup history for FULL recovery model."
            } elseif ($lastLog -lt $StartTime) {
                $issue = "STALE: Last Log Backup is older than $DaysBack days ($lastLog)."
            }
        }

        if ($issue) {
            $issuesFound++
            Write-Host "[!] $dbName - $issue" -ForegroundColor Yellow
        }
    }
    
    if ($issuesFound -eq 0) {
        Write-Host "All ONLINE databases have current backups within the last $DaysBack days." -ForegroundColor Green
    }
} else {
    Write-Warning "Could not query backup history. Check SQL permissions or connection."
}

# 5. SQL Agent Backup Jobs Check
Write-Header "SQL Agent Backup Job Failures"
$jobsQuery = @"
SELECT 
    j.name AS JobName, 
    h.run_date, 
    h.run_time, 
    h.message
FROM msdb.dbo.sysjobhistory h
JOIN msdb.dbo.sysjobs j ON h.job_id = j.job_id
WHERE h.run_status = 0 -- 0 means Failed
  AND (j.name LIKE '%Backup%' OR h.message LIKE '%BACKUP%')
  AND msdb.dbo.agent_datetime(h.run_date, h.run_time) >= GETDATE() - $DaysBack
ORDER BY h.run_date DESC, h.run_time DESC;
"@

$failedJobs = Invoke-SqlCmdQuery -Query $jobsQuery
if ($failedJobs -and $failedJobs.Rows.Count -gt 0) {
    Write-Host "Found $($failedJobs.Rows.Count) failed backup job executions in the last $DaysBack days:" -ForegroundColor Red
    $failedJobs | Select-Object JobName, run_date, @{Name='ErrorMessage';Expression={$_.message -replace "`r`n", " "}} | Format-Table -AutoSize -Wrap
} else {
    Write-Host "No failed SQL Agent backup jobs detected in the last $DaysBack days." -ForegroundColor Green
}

Write-Header "Diagnostic Complete"
Write-Host "Review any red or yellow items above to determine the root cause of the backup failures.`n" -ForegroundColor White