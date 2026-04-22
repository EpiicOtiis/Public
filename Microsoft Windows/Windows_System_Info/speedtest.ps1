# --- Functions ---
function Get-LatestSpeedtestUrl {
    Write-Host "Checking for the latest version on speedtest.net..." -ForegroundColor Cyan
    try {
        $Url = "https://www.speedtest.net/apps/cli"
        $PageContent = Invoke-WebRequest -Uri $Url -UseBasicParsing
        $Regex = 'https://install\.speedtest\.net/app/cli/ookla-speedtest-[\d\.]+-win64\.zip'
        $Match = [regex]::Match($PageContent.Content, $Regex)
        
        if ($Match.Success) { return $Match.Value } 
        else { return "https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-win64.zip" }
    } catch {
        return "https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-win64.zip"
    }
}

# --- Configuration ---
$TempFolder = Join-Path $env:TEMP "OoklaSpeedtest"
$ZipFile = Join-Path $TempFolder "speedtest.zip"
$ExePath = Join-Path $TempFolder "speedtest.exe"

# --- Preparation ---
if (-not (Test-Path $TempFolder)) {
    New-Item -ItemType Directory -Path $TempFolder -Force | Out-Null
}

if (-not (Test-Path $ExePath)) {
    $DownloadUrl = Get-LatestSpeedtestUrl
    Write-Host "Downloading Speedtest CLI..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $ZipFile
    Expand-Archive -Path $ZipFile -DestinationPath $TempFolder -Force
    Remove-Item $ZipFile
}

# Define arguments as an array to prevent "Unrecognized option" errors
$DefaultArgs = @("--accept-license", "--accept-gdpr")

# --- Main Menu Loop ---
$Running = $true
while ($Running) {
    Clear-Host
    Write-Host "==============================================" -ForegroundColor Yellow
    Write-Host "        SPEEDTEST.NET CLI WRAPPER" -ForegroundColor Yellow
    Write-Host "==============================================" -ForegroundColor Yellow
    Write-Host "1. Run Standard Speedtest"
    Write-Host "2. List Nearby Servers"
    Write-Host "3. Run Test on Specific Server ID"
    Write-Host "4. Run Test with Progress Bar"
    Write-Host "5. Show Speedtest CLI Help"
    Write-Host "6. Show Speedtest CLI Version"
    Write-Host "7. Exit"
    Write-Host "==============================================" -ForegroundColor Yellow
    
    $Choice = Read-Host "Select an option [1-7]"

    switch ($Choice) {
        "1" {
            Write-Host "`nRunning Standard Test..." -ForegroundColor Green
            & $ExePath $DefaultArgs
        }
        "2" {
            Write-Host "`nFetching nearby servers..." -ForegroundColor Green
            & $ExePath $DefaultArgs --servers
        }
        "3" {
            $ServerID = Read-Host "Enter Server ID"
            if ($ServerID) {
                Write-Host "`nRunning test on server $ServerID..." -ForegroundColor Green
                & $ExePath $DefaultArgs --server-id=$ServerID
            }
        }
        "4" {
            Write-Host "`nRunning Test with Progress Bar..." -ForegroundColor Green
            & $ExePath $DefaultArgs --progress=yes
        }
        "5" {
            Write-Host "`n--- Speedtest CLI Help Documentation ---" -ForegroundColor Cyan
            & $ExePath --help
        }
        "6" {
            Write-Host "`n--- Speedtest CLI Local Version ---" -ForegroundColor Cyan
            & $ExePath --version
        }
        "7" {
            $Running = $false
            continue
        }
        Default {
            Write-Host "Invalid selection." -ForegroundColor Red
            Start-Sleep -Seconds 1
            continue
        }
    }

    Write-Host "`n----------------------------------------------" -ForegroundColor Yellow
    Write-Host "Operation Finished." -ForegroundColor Cyan
    Write-Host "Press any key to return to menu, or 'Q' to quit..."
    
    # Wait for a single key press
    $Key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    if ($Key.Character -eq 'q' -or $Key.Character -eq 'Q') {
        $Running = $false
    }
}

Write-Host "Exiting..." -ForegroundColor Gray