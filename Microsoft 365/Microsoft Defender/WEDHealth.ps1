<#
.SYNOPSIS
    Comprehensive script for Microsoft Defender Health, Updates, and Deployment.
.DESCRIPTION
    1. Audits service status and versioning (Engine, Signatures).
    2. Triggers Defender signature updates.
    3. Handles OS-specific installation (DISM vs MSI).
    4. Facilitates MDE onboarding.
#>

function Test-IsAdmin {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    Write-Error "This script must be run as an Administrator."
    exit
}

# --- 1. Health & Update Check ---
Write-Host "--- Checking Defender Health & Versioning ---" -ForegroundColor Cyan

$OSInfo = Get-CimInstance Win32_OperatingSystem
$OSCaption = $OSInfo.Caption
Write-Host "Operating System: $OSCaption"

# Service Check
$Services = @("WinDefend", "Sense")
foreach ($SvcName in $Services) {
    $Svc = Get-Service -Name $SvcName -ErrorAction SilentlyContinue
    if ($Svc) {
        $Color = if ($Svc.Status -eq 'Running') { "Green" } else { "Yellow" }
        Write-Host "Service [$SvcName]: $($Svc.Status)" -ForegroundColor $Color
    } else {
        Write-Host "Service [$SvcName]: NOT FOUND" -ForegroundColor Red
    }
}

# Version & Update Check
try {
    $MpStatus = Get-MpComputerStatus -ErrorAction Stop
    Write-Host "`n--- Defender Component Versions ---" -ForegroundColor Gray
    Write-Host "Antivirus Signature Version: $($MpStatus.AntivirusSignatureVersion)"
    Write-Host "Antivirus Last Updated:      $($MpStatus.AntivirusSignatureLastUpdated)"
    Write-Host "Engine Version:              $($MpStatus.EngineVersion)"
    Write-Host "Platform/Product Version:    $($MpStatus.AMProductVersion)"
    
    # Check if signatures are older than 24 hours
    if ($MpStatus.AntivirusSignatureLastUpdated -lt (Get-Date).AddDays(-1)) {
        Write-Host "[!] Warning: Defender signatures are more than 24 hours old." -ForegroundColor Yellow
    }
} catch {
    Write-Host "[!] Could not retrieve Defender status. The service may be disabled or uninstalled." -ForegroundColor Red
}

# --- 2. Update Management ---
$DoUpdate = Read-Host "`nWould you like to check for and install Defender updates now? (Y/N)"
if ($DoUpdate -eq 'Y') {
    Write-Host "Checking for updates... (This may take a moment)" -ForegroundColor Cyan
    try {
        Update-MpSignature -ErrorAction Stop
        Write-Host "Update check completed successfully." -ForegroundColor Green
        
        # Refresh status
        $NewStatus = Get-MpComputerStatus
        Write-Host "New Signature Version: $($NewStatus.AntivirusSignatureVersion)"
    } catch {
        Write-Host "Failed to update. Check internet connectivity or WSUS/Windows Update settings." -ForegroundColor Red
    }
}

# --- 3. Installation Logic ---
$SenseSvc = Get-Service -Name "Sense" -ErrorAction SilentlyContinue

if (-not $SenseSvc) {
    $InstallChoice = Read-Host "`nMDE (Sense) service is missing. Would you like to install it? (Y/N)"
    if ($InstallChoice -eq 'Y') {
        
        $OSVersion = [version]$OSInfo.Version
        if ($OSCaption -match "2012 R2" -or ($OSCaption -match "2016" -and $OSVersion -lt [version]"10.0.17763")) {
            Write-Host "Detected Server 2012 R2/2016. Modern Unified Solution (MSI) is required." -ForegroundColor Yellow
            
            $MsiPath = Join-Path $env:TEMP "mdemodernunified.msi"
            $DownloadUrl = Read-Host "Enter the direct download URL for the MDE MSI (or leave blank to use local path)"
            
            if ($DownloadUrl) {
                Write-Host "Downloading MSI..."
                Invoke-WebRequest -Uri $DownloadUrl -OutFile $MsiPath
            } else {
                $MsiPath = Read-Host "Enter the full local path to the MDE MSI"
            }

            if (Test-Path $MsiPath) {
                Write-Host "Installing MSI..."
                Start-Process msiexec.exe -ArgumentList "/i `"$MsiPath`" /quiet /norestart" -Wait
                Write-Host "Installation complete."
            }
        } 
        else {
            Write-Host "Detected modern OS. Enabling via DISM..." -ForegroundColor Yellow
            try {
                # This ensures the optional feature is present
                Enable-WindowsOptionalFeature -Online -FeatureName "Windows-Defender-Default-Definitions" -LimitAccess -ErrorAction SilentlyContinue
                Write-Host "Feature enablement complete."
            } catch {
                Write-Host "Automatic enablement failed. Ensure Defender has not been removed from this image." -ForegroundColor Red
            }
        }
    }
}

# --- 4. Onboarding Logic ---
$OnboardChoice = Read-Host "`nWould you like to onboard this device to MDE? (Y/N)"
if ($OnboardChoice -eq 'Y') {
    Write-Host "1. Automatic: Provide path to onboarding script (.cmd or .ps1)"
    Write-Host "2. Manual: Paste the onboarding script content"
    $Method = Read-Host "Select option (1 or 2)"

    if ($Method -eq '1') {
        $ScriptPath = Read-Host "Enter the full path to the onboarding script"
        if (Test-Path $ScriptPath) {
            Write-Host "Executing onboarding..."
            if ($ScriptPath -like "*.cmd") {
                Start-Process cmd.exe -ArgumentList "/c `"$ScriptPath`"" -Wait
            } else {
                & $ScriptPath
            }
        }
    } 
    elseif ($Method -eq '2') {
        Write-Host "Paste your onboarding script content below. Type 'EOF' on a new line when finished:"
        $ScriptLines = New-Object System.Collections.Generic.List[string]
        do {
            $Line = Read-Host
            if ($Line -ne 'EOF') { $ScriptLines.Add($Line) }
        } while ($Line -ne 'EOF')

        $TempScript = Join-Path $env:TEMP "MDE_Onboard_Manual.cmd"
        $ScriptLines | Out-File -FilePath $TempScript -Encoding ASCII
        Start-Process cmd.exe -ArgumentList "/c `"$TempScript`"" -Wait
        Remove-Item $TempScript
    }
}

Write-Host "`n--- Script Execution Finished ---" -ForegroundColor Cyan