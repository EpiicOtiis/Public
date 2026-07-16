[CmdletBinding()]
param(
    [switch]$RunScheduledUpgrade,
    [string]$TaskName = 'DuoWLUpgradeDeferred'
)

$ErrorActionPreference = 'Stop'
$InstallerUrl = 'https://dl.duosecurity.com/duo-win-login-latest.exe'
$InstallerName = 'duo-win-login-latest.exe'
$TempDir = Join-Path $env:TEMP 'DuoWLUpgrade'
$InstallerPath = Join-Path $TempDir $InstallerName

function Get-DuoInstallInfo {
    $candidates = New-Object System.Collections.Generic.List[object]

    $uninstallPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    foreach ($path in $uninstallPaths) {
        try {
            $items = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
            if ($null -ne $items) {
                foreach ($item in $items) {
                    if ($item.DisplayName -and ($item.DisplayName -match 'Duo' -or $item.DisplayName -match 'Windows Logon')) {
                        $candidates.Add([pscustomobject]@{
                            DisplayName = $item.DisplayName
                            DisplayVersion = $item.DisplayVersion
                            InstallLocation = $item.InstallLocation
                            Publisher = $item.Publisher
                            UninstallString = $item.UninstallString
                            Source = 'Registry'
                        })
                    }
                }
            }
        }
        catch {
            continue
        }
    }

    $programRoots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    foreach ($root in $programRoots) {
        if (-not (Test-Path $root)) {
            continue
        }

        foreach ($folder in Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Duo' }) {
            $exeFiles = Get-ChildItem -Path $folder.FullName -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'duo' -or $_.Name -match 'Duo' }
            foreach ($exeFile in $exeFiles) {
                try {
                    $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($exeFile.FullName)
                    if ($versionInfo -and $versionInfo.FileVersion) {
                        $candidates.Add([pscustomobject]@{
                            DisplayName = 'Duo Windows Login'
                            DisplayVersion = $versionInfo.FileVersion
                            InstallLocation = $folder.FullName
                            Publisher = 'Duo Security'
                            UninstallString = ''
                            Source = 'FileVersion'
                        })
                    }
                }
                catch {
                    continue
                }
            }
        }
    }

    if ($candidates.Count -eq 0) {
        return $null
    }

    $bestMatch = $null
    $bestVersion = $null

    foreach ($candidate in $candidates) {
        $parsedVersion = $null
        try {
            $parsedVersion = [Version]$candidate.DisplayVersion
        }
        catch {
            $parsedVersion = $null
        }

        if ($null -eq $parsedVersion) {
            continue
        }

        if ($null -eq $bestVersion -or $parsedVersion -gt $bestVersion) {
            $bestMatch = $candidate
            $bestVersion = $parsedVersion
        }
    }

    if ($null -ne $bestMatch) {
        return [pscustomobject]@{
            DisplayName = $bestMatch.DisplayName
            DisplayVersion = $bestMatch.DisplayVersion
            InstallLocation = $bestMatch.InstallLocation
            Publisher = $bestMatch.Publisher
            UninstallString = $bestMatch.UninstallString
            Source = $bestMatch.Source
        }
    }

    return [pscustomobject]@{
        DisplayName = $candidates[0].DisplayName
        DisplayVersion = $candidates[0].DisplayVersion
        InstallLocation = $candidates[0].InstallLocation
        Publisher = $candidates[0].Publisher
        UninstallString = $candidates[0].UninstallString
        Source = $candidates[0].Source
    }
}

function Test-DuoVersionRequiresManualUpgrade {
    param([string]$Version)

    if ([string]::IsNullOrWhiteSpace($Version)) {
        return $true
    }

    try {
        $parsed = [Version]$Version
        return $parsed.Major -lt 4
    }
    catch {
        return $true
    }
}

function Invoke-DuoInstaller {
    param([string]$Url, [string]$Destination)

    New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

    Write-Host "Downloading Duo Windows Login installer to $Destination..."
    Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing

    if (-not (Test-Path $Destination)) {
        throw "Installer download failed."
    }

    Write-Host 'Starting silent upgrade...'
    $process = Start-Process -FilePath $Destination -ArgumentList '/S' -Wait -PassThru

    if ($process.ExitCode -ne 0) {
        throw "Installer exited with code $($process.ExitCode)."
    }

    Write-Host 'Duo Windows Login upgrade completed successfully.'
}

function Request-DeferredInstallTime {
    Write-Host 'Choose a time to install later:'
    $hours = 0..23 | ForEach-Object { '{0:D2}:00' -f $_ }

    for ($i = 0; $i -lt $hours.Count; $i++) {
        Write-Host ("[{0}] {1}" -f $i, $hours[$i])
    }

    $choice = Read-Host 'Enter the number for the desired hour'
    if ($choice -notmatch '^\d+$') {
        throw 'Invalid selection.'
    }

    $index = [int]$choice
    if ($index -lt 0 -or $index -ge $hours.Count) {
        throw 'Selection out of range.'
    }

    return $hours[$index]
}

function New-DeferredUpgradeTask {
    param([string]$ScheduledTime)

    $scriptPath = $PSCommandPath
    if ([string]::IsNullOrWhiteSpace($scriptPath)) {
        $scriptPath = $MyInvocation.MyCommand.Path
    }

    $selectedTime = [DateTime]::Parse($ScheduledTime)
    if ($selectedTime -le (Get-Date)) {
        $selectedTime = $selectedTime.AddDays(1)
    }

    $taskAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -RunScheduledUpgrade"
    $taskTrigger = New-ScheduledTaskTrigger -Once -At $selectedTime -RandomDelay 00:05:00

    $taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingToSleep -StartWhenAvailable

    Register-ScheduledTask -TaskName $TaskName -Action $taskAction -Trigger $taskTrigger -Settings $taskSettings -Description 'Deferred Duo Windows Login upgrade' -User 'SYSTEM' -RunLevel Highest | Out-Null

    Write-Host "Scheduled Duo upgrade for $($selectedTime.ToString('yyyy-MM-dd HH:mm'))."
    Write-Host "The task '$TaskName' will run and remove itself after completion."
}

function Remove-DeferredUpgradeTask {
    try {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "Removed scheduled task '$TaskName'."
    }
    catch {
        Write-Verbose "No scheduled task was present to remove."
    }
}

try {
    $installInfo = Get-DuoInstallInfo

    if ($RunScheduledUpgrade) {
        Write-Host 'Running scheduled upgrade...'
        Invoke-DuoInstaller -Url $InstallerUrl -Destination $InstallerPath
        Remove-DeferredUpgradeTask
        return
    }

    if ($null -eq $installInfo) {
        Write-Host 'Duo Windows Login is not installed.'
        $choice = Read-Host 'Would you like to install it now? [Y/N]'
        if ($choice -match '^(y|yes)$') {
            Invoke-DuoInstaller -Url $InstallerUrl -Destination $InstallerPath
        }
        return
    }

    Write-Host "Installed application: $($installInfo.DisplayName)"
    Write-Host "Installed version: $($installInfo.DisplayVersion)"

    if (Test-DuoVersionRequiresManualUpgrade -Version $installInfo.DisplayVersion) {
        Write-Host 'The installed version is older than 4.x or could not be confirmed. Manual review is recommended before proceeding.'
        $laterChoice = Read-Host 'Would you like to schedule this upgrade for a later time? [Y/N]'
        if ($laterChoice -match '^(y|yes)$') {
            $scheduledTime = Request-DeferredInstallTime
            New-DeferredUpgradeTask -ScheduledTime $scheduledTime
        }
        return
    }

    Write-Host 'The installed version is 4.x or newer. Proceeding with the upgrade.'
    Invoke-DuoInstaller -Url $InstallerUrl -Destination $InstallerPath
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
