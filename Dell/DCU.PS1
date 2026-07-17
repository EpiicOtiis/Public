# Define the path to the DCU CLI
$dcuPath = "C:\Program Files\Dell\CommandUpdate\dcu-cli.exe"

# Define a temporary path for the scan report
$reportPath = "$env:TEMP\DCU_Report.xml"

# Check if Dell Command Update is installed
if (-not (Test-Path $dcuPath)) {
    Write-Host "Dell Command | Update is not installed at the expected path." -ForegroundColor Red
    exit
}

Write-Host "Scanning for available updates. This may take a few minutes..." -ForegroundColor Cyan

# Clean up any old reports
if (Test-Path $reportPath) { Remove-Item $reportPath -Force }

# Run the scan and generate an XML report (-Wait ensures PowerShell pauses until the scan finishes)
$scanProcess = Start-Process -FilePath $dcuPath -ArgumentList "/scan -silent -report=$reportPath" -Wait -PassThru

# Check if the report was successfully created
if (Test-Path $reportPath) {
    # Cast the file content to an XML object
    [xml]$report = Get-Content $reportPath
    
    # Extract the update nodes (DCU typically stores them under <Update> tags)
    $updates = Select-Xml -Xml $report -XPath "//Update" | Select-Object -ExpandProperty Node
    
    if ($updates) {
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
            
            # Apply updates (leaving reboot disabled here so your system doesn't restart unexpectedly)
            $installProcess = Start-Process -FilePath $dcuPath -ArgumentList "/applyUpdates -silent -reboot=disable" -Wait -PassThru
            
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
    Write-Host "`nFailed to generate the update report. The scan may have failed or was interrupted." -ForegroundColor Red
}