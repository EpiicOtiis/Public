<#
.SYNOPSIS
    Generalized SQL Server backup diagnostic report tool.
.DESCRIPTION
    This script inspects SQL Server backup-related event log entries, backup history, SQL Agent job steps,
    and backup path configuration. It avoids hard-coded database names, server names, and backup folder references,
    making it suitable for SQL Server instances running on Windows Server 2012 R2 or later.
.NOTES
    Run this script from a machine with access to the target SQL Server instance using Windows integrated security.
    Example usage: .\SQL_BKUP_Checker.ps1 -SqlInstance 'localhost' -DaysBack 14 -ShowGrid
#>

[CmdletBinding()]
param(
    [Parameter(Position=0, HelpMessage='Target SQL Server instance name, for example localhost or SERVER\\INSTANCE.')]
    [string]
    $SqlInstance = 'localhost',

    [Parameter(Position=1, HelpMessage='Number of days to search back for backup events and backup history.')]
    [ValidateRange(1, 365)]
    [int]
    $DaysBack = 7,

    [Parameter(HelpMessage='If present, the script relaunches under the SYSTEM account to access local SQL when available.')]
    [switch]
    $UseSystemAccount,

    [Parameter(HelpMessage='If present, event and job findings are opened in Out-GridView.')]
    [switch]
    $ShowGrid
)

function Get-IsSystemAccount {
    try {
        $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        return $sid -eq 'S-1-5-18'
    } catch {
        return $false
    }
}

function Invoke-ScriptAsSystem {
    $currentScript = $MyInvocation.MyCommand.Path
    if (-not $currentScript) {
        Write-Warning 'Cannot determine script path for SYSTEM relaunch.'
        return
    }

    $taskName = "SQL_BKUP_Checker_System_$([guid]::NewGuid().ToString('N'))"
    $tempFolder = Join-Path $env:TEMP 'SQL_BKUP_Checker'
    New-Item -Path $tempFolder -ItemType Directory -Force | Out-Null
    $outputFile = Join-Path $tempFolder "$taskName-output.txt"
    $errorFile = Join-Path $tempFolder "$taskName-error.txt"

    $scriptArgs = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', "`"$currentScript`"",
        '-SqlInstance', "`"$SqlInstance`"",
        '-DaysBack', $DaysBack
    )

    if ($ShowGrid) {
        Write-Warning 'ShowGrid is not supported under SYSTEM; disabling for relaunch.'
    }

    $scriptArgsString = $scriptArgs -join ' '
    $taskCommand = "powershell.exe $scriptArgsString > `"$outputFile`" 2> `"$errorFile`""

    Write-Host "Re-launching script as SYSTEM via scheduled task '$taskName'..."
    $createArgs = @('/Create', '/TN', $taskName, '/SC', 'ONCE', '/ST', '00:00', '/RL', 'HIGHEST', '/F', '/RU', 'SYSTEM', '/TR', $taskCommand)
    $createResult = & schtasks.exe @createArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to create SYSTEM task: $createResult"
        return
    }

    & schtasks.exe /Run /TN $taskName | Out-Null
    Write-Host 'Waiting for SYSTEM task to finish...'
    $timeoutSeconds = 120
    $elapsed = 0

    while ($elapsed -lt $timeoutSeconds) {
        Start-Sleep -Seconds 2
        $elapsed += 2
        $query = & schtasks.exe /Query /TN $taskName /V /FO LIST 2>$null
        if ($query -match 'Status:\s*(.+)') {
            $status = $Matches[1].Trim()
            if ($status -ne 'Running') { break }
        } else {
            break
        }
    }

    if (Test-Path $outputFile) {
        Write-Host "--- SYSTEM OUTPUT ($outputFile) ---"
        Get-Content $outputFile | ForEach-Object { Write-Host $_ }
    }

    if (Test-Path $errorFile -and (Get-Content $errorFile).Length -gt 0) {
        Write-Host '--- SYSTEM STDERR ---'
        Get-Content $errorFile | ForEach-Object { Write-Host $_ }
    }

    & schtasks.exe /Delete /TN $taskName /F | Out-Null
}

function Write-Section {
    param([string]$Title)
    Write-Host ''
    Write-Host ('=' * 80) -ForegroundColor DarkCyan
    Write-Host $Title -ForegroundColor Cyan
    Write-Host ('=' * 80) -ForegroundColor DarkCyan
}

function Get-OperatingSystemInfo {
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        return [PSCustomObject]@{
            Caption      = $os.Caption
            Version      = $os.Version
            BuildNumber  = $os.BuildNumber
            Architecture = $os.OSArchitecture
        }
    } catch {
        return [PSCustomObject]@{
            Caption      = [System.Environment]::OSVersion.VersionString
            Version      = ''
            BuildNumber  = ''
            Architecture = ''
        }
    }
}

function Invoke-SqlQuery {
    param(
        [Parameter(Mandatory)] [string]$Instance,
        [Parameter(Mandatory)] [string]$Query
    )

    $connectionString = "Server=$Instance;Database=msdb;Integrated Security=True;Connect Timeout=15;"
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
        Write-Warning "Unable to query SQL Server instance '$Instance'. $_"
        return $null
    } finally {
        if ($connection.State -eq 'Open') {
            $connection.Close()
        }
        $connection.Dispose()
    }
}

function Get-SqlEventProviderName {
    $providers = Get-WinEvent -ListProvider *sql* -ErrorAction SilentlyContinue
    if (-not $providers) { return $null }
    $preferred = $providers | Where-Object { $_.Name -match 'MSSQL' } | Select-Object -First 1
    if ($preferred) {
        return $preferred.Name
    }
    return ($providers | Select-Object -First 1).Name
}

function Parse-SqlEventMessage {
    param([System.Diagnostics.Eventing.Reader.EventRecord]$Event)

    $message = $Event.Message -replace "`r`n", ' '
    $databaseName = 'Unknown'
    $backupTarget = 'Unknown'

    $patterns = @(
        'Database:\s*([^\s,]+)',
        "database\s+'([^']+)'",
        'backup of database\s+"?([^"\s]+)"?',
        'backup database\s+"?([^"\s]+)"?'
    )

    foreach ($pattern in $patterns) {
        if ($message -match $pattern) {
            $databaseName = $Matches[1]
            break
        }
    }

    $winPathPattern = @'
((?:[A-Z]:\\|\\\\)[^\s"']+\.(?:bak|trn|diff|log))
'@
    $pathPattern = @'
path\s+"?([^"']+)"?
'@

    if ($message -match $winPathPattern) {
        $backupTarget = $Matches[1]
    } elseif ($message -match $pathPattern) {
        $backupTarget = $Matches[1]
    }

    return [PSCustomObject]@{
        TimeCreated  = $Event.TimeCreated
        ProviderName = $Event.ProviderName
        Id           = $Event.Id
        Level        = $Event.LevelDisplayName
        DatabaseName = $databaseName
        Target       = $backupTarget
        Message      = $message
    }
}

function Get-SqlBackupEvents {
    param([datetime]$StartTime)

    $backupEventIds = @(18264, 18265, 18270, 3041, 3201, 18210, 18204, 208, 12291, 3013, 3047, 3051, 3034)
    $events = Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Id = $backupEventIds; StartTime = $StartTime } -ErrorAction SilentlyContinue
    if (-not $events) { return @() }
    return $events | Where-Object { $_.ProviderName -match 'SQL' } | ForEach-Object { Parse-SqlEventMessage -Event $_ }
}

function Get-SqlInstanceInfo {
    $query = @"
SELECT
    SERVERPROPERTY('MachineName') AS MachineName,
    SERVERPROPERTY('ServerName') AS ServerName,
    SERVERPROPERTY('InstanceName') AS InstanceName,
    SERVERPROPERTY('ProductVersion') AS ProductVersion,
    SERVERPROPERTY('ProductLevel') AS ProductLevel,
    SERVERPROPERTY('Edition') AS Edition,
    CASE SERVERPROPERTY('IsClustered') WHEN 1 THEN 'Yes' ELSE 'No' END AS IsClustered
"@
    return Invoke-SqlQuery -Instance $SqlInstance -Query $query
}

function Get-SqlBackupHistory {
    $query = @"
WITH LatestBackups AS (
    SELECT
        database_name,
        MAX(CASE WHEN type = 'D' THEN backup_finish_date END) AS LastFullBackup,
        MAX(CASE WHEN type = 'I' THEN backup_finish_date END) AS LastDiffBackup,
        MAX(CASE WHEN type = 'L' THEN backup_finish_date END) AS LastLogBackup,
        MAX(backup_finish_date) AS LastAnyBackup
    FROM msdb.dbo.backupset
    GROUP BY database_name
)
SELECT
    d.name AS DatabaseName,
    d.state_desc AS State,
    d.recovery_model_desc AS RecoveryModel,
    l.LastFullBackup,
    l.LastDiffBackup,
    l.LastLogBackup,
    l.LastAnyBackup
FROM master.sys.databases d
LEFT JOIN LatestBackups l ON l.database_name = d.name
ORDER BY d.name;
"@
    return Invoke-SqlQuery -Instance $SqlInstance -Query $query
}

function Get-SqlAgentBackupJobs {
    $query = @"
SELECT
    j.name AS JobName,
    j.enabled AS IsEnabled,
    s.step_name AS StepName,
    s.subsystem AS Subsystem,
    s.command AS Command
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobsteps s ON s.job_id = j.job_id
WHERE
    s.command LIKE '%BACKUP%'
    OR s.command LIKE '%RESTORE%'
    OR s.command LIKE '%.bak%'
    OR s.command LIKE '%.trn%'
    OR s.command LIKE '%.diff%'
ORDER BY j.name, s.step_id;
"@
    return Invoke-SqlQuery -Instance $SqlInstance -Query $query
}

function Get-SqlBackupPaths {
    $query = @"
SELECT DISTINCT
    physical_device_name AS BackupFile
FROM msdb.dbo.backupmediafamily
WHERE physical_device_name IS NOT NULL
ORDER BY physical_device_name;
"@
    return Invoke-SqlQuery -Instance $SqlInstance -Query $query
}

function Get-SqlDefaultBackupDirectory {
    $query = @"
DECLARE @BackupDirectory nvarchar(512);
EXEC master.dbo.xp_instance_regread
    N'HKEY_LOCAL_MACHINE',
    N'SOFTWARE\\Microsoft\\MSSQLServer\\MSSQLServer',
    N'BackupDirectory',
    @BackupDirectory OUTPUT;
SELECT @BackupDirectory AS BackupDirectory;
"@
    return Invoke-SqlQuery -Instance $SqlInstance -Query $query
}

function Analyze-BackupHealth {
    param(
        [Parameter(Mandatory)] [System.Data.DataTable]$History,
        [Parameter(Mandatory)] [int]$DaysBack
    )

    $threshold = (Get-Date).AddDays(-$DaysBack)
    $findings = @()

    foreach ($row in $History) {
        $database = $row.DatabaseName
        $state = $row.State
        $recovery = $row.RecoveryModel
        $lastFull = $row.LastFullBackup
        $lastLog = $row.LastLogBackup

        if ($state -ne 'ONLINE') {
            $findings += [PSCustomObject]@{ Database = $database; Issue = "Database is not ONLINE (state: $state)." }
            continue
        }

        if (-not $lastFull) {
            $findings += [PSCustomObject]@{ Database = $database; Issue = 'No full backup history found.' }
            continue
        }

        if ($lastFull -lt $threshold) {
            $findings += [PSCustomObject]@{ Database = $database; Issue = "Last full backup is older than $DaysBack days ($lastFull)." }
        }

        if ($recovery -ne 'SIMPLE') {
            if (-not $lastLog) {
                $findings += [PSCustomObject]@{ Database = $database; Issue = 'No log backup history found for a non-SIMPLE recovery model database.' }
            } elseif ($lastLog -lt $threshold) {
                $findings += [PSCustomObject]@{ Database = $database; Issue = "Last log backup is older than $DaysBack days ($lastLog)." }
            }
        }
    }

    return $findings
}

function Test-BackupPathAvailability {
    param([Parameter(Mandatory)] [string[]]$Paths)

    $results = @()
    foreach ($path in ($Paths | Sort-Object -Unique | Where-Object { $_ })) {
        $folder = Split-Path $path
        $exists = $false
        $access = $null

        if ($folder) {
            try {
                $exists = Test-Path $folder
                if ($exists) { $access = try { (Get-Acl $folder).Access } catch { $null } }
            } catch {
                $exists = $false
            }
        }

        $results += [PSCustomObject]@{
            Path     = $path
            Folder   = $folder
            Exists   = $exists
            Readable = if ($exists -and $access) { $true } else { $false }
        }
    }

    return $results
}

if ($UseSystemAccount -and -not (Get-IsSystemAccount)) {
    Write-Host 'UseSystemAccount requested; relaunching script under SYSTEM.' -ForegroundColor Cyan
    Invoke-ScriptAsSystem
    return
}

# --- Start script execution ---
$startTime = (Get-Date).AddDays(-$DaysBack)

Write-Section 'SQL Backup Diagnostic Report'
Write-Host "Target SQL Instance: $SqlInstance"
Write-Host "Search window: $DaysBack day(s) (since $startTime)"

$osInfo = Get-OperatingSystemInfo
Write-Host "Operating System: $($osInfo.Caption) $($osInfo.Architecture) (Build $($osInfo.BuildNumber))"

$providerName = Get-SqlEventProviderName
if ($providerName) {
    Write-Host "SQL Event Provider: $providerName"
} else {
    Write-Host 'SQL event provider not discovered automatically; filtering on SQL-related providers instead.' -ForegroundColor Yellow
}

Write-Section 'Event Log Analysis'
$events = Get-SqlBackupEvents -StartTime $startTime
if ($events.Count -gt 0) {
    $events | Sort-Object TimeCreated -Descending | Select-Object TimeCreated, ProviderName, Id, Level, DatabaseName, Target, Message | Format-Table -Wrap -AutoSize
    if ($ShowGrid) { $events | Sort-Object TimeCreated -Descending | Out-GridView -Title 'SQL Backup Events' }
} else {
    Write-Host 'No SQL backup-related event log entries were found in the selected time window.' -ForegroundColor Yellow
}

Write-Section 'Instance Information'
$instanceInfo = Get-SqlInstanceInfo
if ($instanceInfo -and $instanceInfo.Rows.Count -gt 0) {
    $instanceInfo | Format-Table -AutoSize
} else {
    Write-Warning 'Unable to retrieve SQL Server instance information.'
}

Write-Section 'Backup History Summary'
$history = Get-SqlBackupHistory
if ($history -and $history.Rows.Count -gt 0) {
    $history | Select-Object DatabaseName, State, RecoveryModel, LastFullBackup, LastDiffBackup, LastLogBackup, LastAnyBackup | Format-Table -AutoSize
    $healthFindings = Analyze-BackupHealth -History $history -DaysBack $DaysBack
    if ($healthFindings.Count -gt 0) {
        Write-Section 'Backup Health Findings'
        $healthFindings | Format-Table -AutoSize
    } else {
        Write-Host 'No obvious backup age or log backup issues were detected for the databases in the selected window.' -ForegroundColor Green
    }
} else {
    Write-Warning 'Unable to retrieve backup history from msdb, or no backup history exists.'
}

Write-Section 'SQL Agent Job Inspection'
$jobMatches = Get-SqlAgentBackupJobs
if ($jobMatches -and $jobMatches.Rows.Count -gt 0) {
    $jobMatches | Select-Object JobName, IsEnabled, StepName, Subsystem, @{Name='Command';Expression={if ($_.Command.Length -gt 180){$_.Command.Substring(0,180) + '...'} else {$_.Command}}} | Format-Table -AutoSize
    if ($ShowGrid) { $jobMatches | Out-GridView -Title 'SQL Agent Backup/Restore Jobs' }
} else {
    Write-Host 'No SQL Agent steps containing BACKUP/RESTORE or backup file patterns were found.' -ForegroundColor Yellow
}

Write-Section 'Backup Path Discovery'
$backupPaths = Get-SqlBackupPaths
$pathResults = @()
if ($backupPaths -and $backupPaths.Rows.Count -gt 0) {
    $pathResults = Test-BackupPathAvailability -Paths ($backupPaths | Select-Object -ExpandProperty BackupFile)
    $pathResults | Format-Table Path, Folder, Exists, Readable -AutoSize
} else {
    Write-Host 'No backup paths were discovered in msdb backup media history.' -ForegroundColor Yellow
}

$defaultBackupDir = Get-SqlDefaultBackupDirectory
if ($defaultBackupDir -and $defaultBackupDir.Rows.Count -gt 0 -and $defaultBackupDir.BackupDirectory) {
    Write-Section 'Configured Default Backup Directory'
    $defaultBackupDir | Format-Table -AutoSize
    $defaultPath = $defaultBackupDir.BackupDirectory[0]
    if ($defaultPath) {
        $defaultPathExists = Test-Path $defaultPath
        Write-Host "Default backup directory exists: $defaultPathExists"
        if ($defaultPathExists) {
            try {
                Get-Acl $defaultPath | Select-Object -ExpandProperty Access | Format-Table -AutoSize
            } catch {
                Write-Warning "Unable to read ACL for default backup directory: $_"
            }
        }
    }
}

Write-Section 'Summary'
if ($events.Count -gt 0) { Write-Host "Found $($events.Count) matching SQL backup-related event(s)." }
if ($healthFindings -and $healthFindings.Count -gt 0) { Write-Host "Found $($healthFindings.Count) backup health issue(s)." -ForegroundColor Yellow }
if ($jobMatches -and $jobMatches.Rows.Count -gt 0) { Write-Host "Found $($jobMatches.Rows.Count) SQL Agent job step(s) that reference backup or restore activity." }
if ($pathResults -and $pathResults.Count -gt 0) { Write-Host "Discovered $($pathResults.Count) unique backup path(s) from backup history." }
Write-Host 'Review the findings above to determine the next action for SQL backup recovery or investigation.' -ForegroundColor Cyan
