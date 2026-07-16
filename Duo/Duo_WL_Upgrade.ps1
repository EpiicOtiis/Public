#Requires -RunAsAdministrator

[CmdletBinding()]
param(
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

function Invoke-DuoInstaller {
    param([string]$Url, [string]$Destination)

    New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

    Write-Host "Downloading Duo Windows Login installer to $Destination..."
    Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing -TimeoutSec 300

    if (-not (Test-Path $Destination)) {
        throw "Installer download failed."
    }

    Write-Host 'Starting silent upgrade...'
    $process = Start-Process -FilePath $Destination -ArgumentList '/S' -Wait -PassThru

    if ($process.ExitCode -ne 0) {
        throw "Installer exited with code $($process.ExitCode)."
    }

    Write-Host 'Duo Windows Login upgrade completed successfully.'
    
    if (Test-Path $TempDir) {
        Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Request-DeferredInstallTime {
    Write-Host 'Choose a time to install later:'
    $hours = 0..23 | ForEach-Object { '{0:D2}:00' -f $_ }

    for ($i = 0; $i -lt $hours.Count; $i++) {
        Write-Host ("[{0}] {1}" -f $i, $hours[$i])
    }

    $validChoice = $false
    $index = -1
    
    while (-not $validChoice) {
        $choice = Read-Host 'Enter the number for the desired hour'
        if ($choice -match '^\d+$') {
            $index = [int]$choice
            if ($index -ge 0 -and $index -lt $hours.Count) {
                $validChoice = $true
            } else {
                Write-Warning 'Selection out of range. Please try again.'
            }
        } else {
            Write-Warning 'Invalid selection. Please enter a valid number.'
        }
    }

    return $hours[$index]
}

function New-DeferredUpgradeTask {
    param([string]$ScheduledTime)

    $selectedTime = [DateTime]::Parse($ScheduledTime)
    if ($selectedTime -le (Get-Date)) {
        $selectedTime = $selectedTime.AddDays(1)
    }

    # Create a self-contained script block that handles the download, install, and cleanup
    $taskScript = @"
`$ErrorActionPreference = 'Stop'
`$TempDir = Join-Path `$env:TEMP 'DuoWLUpgrade'
`$InstallerPath = Join-Path `$TempDir '$InstallerName'
New-Item -ItemType Directory -Path `$TempDir -Force | Out-Null
Invoke-WebRequest -Uri '$InstallerUrl' -OutFile `$InstallerPath -UseBasicParsing -TimeoutSec 300
`$process = Start-Process -FilePath `$InstallerPath -ArgumentList '/S' -Wait -PassThru
if (`$process.ExitCode -eq 0 -and (Test-Path `$TempDir)) {
    Remove-Item -Path `$TempDir -Recurse -Force -ErrorAction SilentlyContinue
}
Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false -ErrorAction SilentlyContinue
"@

    # Convert the script to Base64 so it can run directly from the Task action
    $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($taskScript))

    $taskAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -EncodedCommand $encodedCommand"
    $taskTrigger = New-ScheduledTaskTrigger -Once -At $selectedTime -RandomDelay 00:05:00
    $taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -StartWhenAvailable -Priority 4

    Register-ScheduledTask -TaskName $TaskName -Action $taskAction -Trigger $taskTrigger -Settings $taskSettings -Description 'Deferred Duo Windows Login upgrade' -User 'SYSTEM' -RunLevel Highest | Out-Null

    Write-Host "Scheduled Duo upgrade for $($selectedTime.ToString('yyyy-MM-dd HH:mm'))."
    Write-Host "The task '$TaskName' will run silently and remove itself after completion."
}

try {
    $installInfo = Get-DuoInstallInfo

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

    Write-Host ''
    Write-Host 'Choose an action:'
    Write-Host '[1] Install now'
    Write-Host '[2] Install later'
    Write-Host '[3] Exit'

    $selection = Read-Host 'Enter your selection'

    switch ($selection) {
        '1' {
            Invoke-DuoInstaller -Url $InstallerUrl -Destination $InstallerPath
        }
        '2' {
            $scheduledTime = Request-DeferredInstallTime
            New-DeferredUpgradeTask -ScheduledTime $scheduledTime
        }
        '3' {
            Write-Host 'No action taken.'
        }
        default {
            Write-Host 'Invalid selection. No action taken.'
        }
    }
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}