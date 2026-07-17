# Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'

# 1. Check if Duo is installed
$regPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$installed = Get-ItemProperty -Path $regPaths -ErrorAction SilentlyContinue | 
    Where-Object { $_.DisplayName -match 'Duo' -and $_.DisplayName -match 'Windows' } | 
    Select-Object -First 1

if (-not $installed) {
    Write-Host 'Duo Windows Logon not installed, skipping upgrade.'
} else {
    Write-Host "Duo detected. Installed Version: $($installed.DisplayVersion)"
    $installer = "$env:TEMP\duo-win-login-latest.exe"

    try {
        # 2. Download the latest installer to check its version number
        Write-Host 'Checking for latest version...'
        Invoke-WebRequest -Uri 'https://dl.duosecurity.com/duo-win-login-latest.exe' -OutFile $installer -UseBasicParsing -TimeoutSec 300
        
        $latestVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($installer).FileVersion
        Write-Host "Latest Available Version: $latestVersion"

        # 3. Compare versions and skip if already up to date
        if ($installed.DisplayVersion -and ([version]$installed.DisplayVersion -ge [version]$latestVersion)) {
            Write-Host 'The latest version is already installed. Skipping upgrade.'
        } else {
            # 4. Proceed with Upgrade
            Write-Host 'Upgrading Duo silently...'
            $process = Start-Process -FilePath $installer -ArgumentList '/S' -Wait -PassThru
            
            if ($process.ExitCode -ne 0) { 
                Write-Host "WARNING: Installer exited with code $($process.ExitCode)" -ForegroundColor Yellow
            } else {
                Write-Host 'Duo upgrade completed successfully.' -ForegroundColor Green
            }
        }
    }
    catch {
        Write-Host "Script failed: $_" -ForegroundColor Red
    }
    finally {
        # 5. Cleanup the downloaded file
        if (Test-Path $installer) { 
            Remove-Item $installer -Force -ErrorAction SilentlyContinue
            Write-Host 'Temp installer cleaned up.' 
        }
    }
}

# 6. Pause for testing so the window stays open
Write-Host "`nTesting complete."
Read-Host "Press Enter to exit"






# Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'

# 1. Check if Duo is installed
$regPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$installed = Get-ItemProperty -Path $regPaths -ErrorAction SilentlyContinue | 
    Where-Object { $_.DisplayName -match 'Duo' -and $_.DisplayName -match 'Windows' } | 
    Select-Object -First 1

if (-not $installed) {
    Write-Host 'Duo Windows Logon not installed, skipping upgrade.'
} else {
    Write-Host "Duo detected. Installed Version: $($installed.DisplayVersion)"
    $installer = "$env:TEMP\duo-win-login-latest.exe"

    try {
        # 2. Download the latest installer to check its version number
        Write-Host 'Checking for latest version...'
        Invoke-WebRequest -Uri 'https://dl.duosecurity.com/duo-win-login-latest.exe' -OutFile $installer -UseBasicParsing -TimeoutSec 300
        
        $latestVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($installer).FileVersion
        Write-Host "Latest Available Version: $latestVersion"

        # 3. Compare versions and skip if already up to date
        if ($installed.DisplayVersion -and ([version]$installed.DisplayVersion -ge [version]$latestVersion)) {
            Write-Host 'The latest version is already installed. Skipping upgrade.'
        } else {
            # 4. Proceed with Upgrade
            Write-Host 'Upgrading Duo silently...'
            $process = Start-Process -FilePath $installer -ArgumentList '/S' -Wait -PassThru
            
            if ($process.ExitCode -ne 0) { 
                Write-Host "WARNING: Installer exited with code $($process.ExitCode)" -ForegroundColor Yellow
            } else {
                Write-Host 'Duo upgrade completed successfully.' -ForegroundColor Green
            }
        }
    }
    catch {
        Write-Host "Script failed: $_" -ForegroundColor Red
    }
    finally {
        # 5. Cleanup the downloaded file
        if (Test-Path $installer) { 
            Remove-Item $installer -Force -ErrorAction SilentlyContinue
            Write-Host 'Temp installer cleaned up.' 
        }
    }
}