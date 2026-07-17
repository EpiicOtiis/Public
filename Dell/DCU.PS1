# Define the path to the DCU CLI
$dcuPath = "C:\Program Files\Dell\CommandUpdate\dcu-cli.exe"

# DCU requires a DIRECTORY for the report argument. 
# It will automatically generate a file named "DCUApplicableUpdates.xml" in this folder.
$reportDir = $env:TEMP
$reportPath = Join-Path -Path $reportDir -ChildPath "DCUApplicableUpdates.xml"

# Check if Dell Command Update is installed
if (-not (Test-Path $dcuPath)) {
    Write-Host "Dell Command | Update is not installed at the expected path." -ForegroundColor Red
    exit
}

Write-Host "Scanning for available updates. This may take a few minutes..." -ForegroundColor Cyan

# Clean up any old reports so we don't read outdated data
if (Test-Path $reportPath) { Remove-Item $reportPath -Force }

# Run the scan (-NoNewWindow stops the popup, -Wait pauses the script until the scan is done)
$scanProcess = Start-Process -FilePath $dcuPath -ArgumentList "/scan -silent -report=`"$reportDir`"" -NoNewWindow -Wait -PassThru

# Check if the report was successfully created
if (Test-Path $reportPath) {
    # Cast the file content to an XML object
    [xml]$report = Get-Content $reportPath
    
    # Grab the updates (forced into an array in case there is only 1 update available)
    $updates = @($report.updates.update)
    
    if ($updates -and $updates.Count -gt 0) {
        Write-Host "`nFound $($updates.Count) available update(s):" -ForegroundColor Green
        Write-Host "------------------------------------------------"
        
        # Loop through and display each available update
        foreach ($update in $updates) {
            $name = $update.name
            $version = $update.version
            $urgency = $update.urgency
            
            Write-Host "- [$urgency] $name (Version: $version)"
        }
        Write-Host "------------------------------------------------`n"
        
        # Prompt the user for a decision
        $prompt = Read-Host "Would you like to install these updates now? (Y/N)"
        
        if ($prompt -match "^[Yy]") {
            Write-Host "`nInstalling updates... Please wait." -ForegroundColor Cyan
            
            # Apply updates
            $installProcess = Start-Process -FilePath $dcuPath -ArgumentList "/applyUpdates -silent -reboot=disable" -NoNewWindow -Wait -PassThru
            
            if ($installProcess.ExitCode -eq 2) {
                Write-Host "Updates installed successfully. A system REBOOT is required to complete the process." -ForegroundColor Yellow
            } elseif ($installProcess.ExitCode -eq 0) {
                Write-Host "Updates installed successfully." -ForegroundColor Green
            } else {
                Write-Host "The installation process returned an unexpected code ($($installProcess.ExitCode)) or failed." -ForegroundColor Red
            }
        } else {
            Write-Host "`nUpdate installation cancelled by user." -ForegroundColor Yellow
        }
    } else {
        Write-Host "`nYour system is up to date. No updates are currently available." -ForegroundColor Green
    }
} else {
    Write-Host "`nFailed to generate the update report. Ensure you are running PowerShell as an Administrator." -ForegroundColor Red
}