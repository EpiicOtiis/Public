# Get the local computer name
$ComputerName = $env:COMPUTERNAME
$OutputPath = "$PSScriptRoot\$($ComputerName)_ShareReport.csv"
$Results = @()

# Get all non-administrative shares
$Shares = Get-SmbShare | Where-Object { $_.Name -notlike "*$" }

Write-Host "--- Starting Share Scan on $ComputerName ---" -ForegroundColor Yellow

foreach ($Share in $Shares) {
    Write-Host "Scanning: $($Share.Name)..." -ForegroundColor Cyan
    $Path = $Share.Path

    if (Test-Path $Path) {
        # Execute Robocopy in 'List Only' mode for speed
        $RoboData = robocopy "$Path" "$Path" /L /S /NJH /BYTES /XJ /R:0 /W:0

        # Parse Robocopy summary
        $Summary = $RoboData[-8..-1] | Out-String
        
        if ($Summary -match 'Files\s+:\s+(\d+)') { $FileCount = [int64]$Matches[1] } else { $FileCount = 0 }
        if ($Summary -match 'Bytes\s+:\s+(\d+)') { $TotalBytes = [int64]$Matches[1] } else { $TotalBytes = 0 }

        # Get the most recent file modification date
        $LatestFile = Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue | 
                      Sort-Object LastWriteTime -Descending | 
                      Select-Object -First 1
        
        $Results += [PSCustomObject]@{
            "Share Name"      = $Share.Name
            "Local Path"      = $Path
            "Storage Used GB" = [Math]::Round($TotalBytes / 1GB, 2)
            "File Count"      = $FileCount
            "Last Modified"   = if($LatestFile){ $LatestFile.LastWriteTime } else { "N/A" }
        }
    }
}

# 1. Show the results on screen
Write-Host "`n--- Scan Results ---" -ForegroundColor Green
$Results | Format-Table -AutoSize

# 2. Ask the user if they want to export
$Confirmation = Read-Host "`nWould you like to export these results to CSV? (Y/N)"

if ($Confirmation -eq 'Y') {
    $Results | Export-Csv -Path $OutputPath -NoTypeInformation
    Write-Host "Success! Saved to: $OutputPath" -ForegroundColor Green
} else {
    Write-Host "Export cancelled. Have a great day!" -ForegroundColor Yellow
}