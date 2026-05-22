<#
.SYNOPSIS
    Checks Microsoft Defender health and provides options for installation and onboarding.
.DESCRIPTION
    1. Audits WinDefend and Sense (MDE) services.
    2. Identifies if the OS requires DISM or the Modern Unified Solution (MSI).
    3. Facilitates installation and onboarding.
#>

function Test-IsAdmin {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    Write-Error "This script must be run as an Administrator."
    exit
}

# --- 1. Health Check ---
Write-Host "--- Checking Defender Health ---" -ForegroundColor Cyan

$OSInfo = Get-CimInstance Win32_OperatingSystem
$OSCaption = $OSInfo.Caption
$OSVersion = [version]$OSInfo.Version
Write-Host "Operating System: $OSCaption ($($OSInfo.Version))"

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

# --- 2. Installation Logic ---
$SenseSvc = Get-Service -Name "Sense" -ErrorAction SilentlyContinue

if (-not $SenseSvc) {
    $InstallChoice = Read-Host "MDE (Sense) service is missing. Would you like to install it? (Y/N)"
    if ($InstallChoice -eq 'Y') {
        
        # Determine Installation Method
        # Windows Server 2012 R2 (6.3) and 2016 (10.0.14393) require the MSI (Unified Solution)
        if ($OSCaption -match "2012 R2" -or ($OSCaption -match "2016" -and $OSVersion -lt [version]"10.0.17763")) {
            Write-Host "Detected Server 2012 R2/2016. Modern Unified Solution (MSI) is required." -ForegroundColor Yellow
            
            $MsiPath = Join-Path $env:TEMP "mdemodernunified.msi"
            $DownloadUrl = Read-Host "Please enter the direct download URL for the MDE MSI (or leave blank to use local path)"
            
            if ($DownloadUrl) {
                Write-Host "Downloading MSI..."
                Invoke-WebRequest -Uri $DownloadUrl -OutFile $MsiPath
            } else {
                $MsiPath = Read-Host "Enter the full local path to the MDE MSI"
            }

            if (Test-Path $MsiPath) {
                Write-Host "Installing MSI..."
                Start-Process msiexec.exe -ArgumentList "/i `"$MsiPath`" /quiet /norestart" -Wait
                Write-Host "Installation process complete."
            }
        } 
        else {
            # Windows 10/11 and Server 2019+ use DISM or are built-in
            Write-Host "Detected modern OS. Attempting to enable via DISM/Features..." -ForegroundColor Yellow
            try {
                Enable-WindowsOptionalFeature -Online -FeatureName "Windows-Defender-Default-Definitions" -LimitAccess -ErrorAction SilentlyContinue
                Write-Host "Feature check complete."
            } catch {
                Write-Host "Could not automatically enable via DISM. Please ensure 'Windows Defender' features are not removed from the image." -ForegroundColor Red
            }
        }
    }
}

# --- 3. Onboarding Logic ---
$OnboardChoice = Read-Host "Would you like to onboard this device to MDE? (Y/N)"
if ($OnboardChoice -eq 'Y') {
    Write-Host "`n1. Automatic: Provide path to onboarding script"
    Write-Host "2. Manual: Paste the onboarding script content"
    $Method = Read-Host "Select option (1 or 2)"

    if ($Method -eq '1') {
        $ScriptPath = Read-Host "Enter the full path to the onboarding script (.cmd or .ps1)"
        if (Test-Path $ScriptPath) {
            Write-Host "Executing onboarding script..."
            if ($ScriptPath -like "*.cmd") {
                Start-Process cmd.exe -ArgumentList "/c `"$ScriptPath`"" -Wait
            } else {
                & $ScriptPath
            }
        } else {
            Write-Host "Path not found." -ForegroundColor Red
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
        Write-Host "Executing temporary onboarding script..."
        Start-Process cmd.exe -ArgumentList "/c `"$TempScript`"" -Wait
        Remove-Item $TempScript
    }
}

Write-Host "`n--- Script Execution Finished ---" -ForegroundColor Cyan