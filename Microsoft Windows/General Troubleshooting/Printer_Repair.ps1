# Combined Printer Maintenance Script
# Revision 2 / Aaron Pleus, (3/9/26)
#
# This script provides a menu for printer cleanup and listing functionalities.
# Copyright: Aaron Pleus

function RestartSpooler {
    Write-Host "Stopping Print Spooler service..." -ForegroundColor Yellow
    Stop-Service -Name Spooler -Force -Verbose
    Start-Sleep -Seconds 2

    Write-Host "Starting Print Spooler service..." -ForegroundColor Yellow
    Start-Service -Name Spooler -Verbose
    Write-Host "Done." -ForegroundColor Green
}

function CleanSpooler {
    Write-Host "Stopping Print Spooler service..." -ForegroundColor Yellow
    Stop-Service -Name Spooler -Force -Verbose
    Start-Sleep -Seconds 2

    Write-Host "Removing queued print jobs (cleaning spool folder)..." -ForegroundColor Yellow
    $path = "$env:SystemRoot\system32\spool\printers\*"
    Remove-Item $path -Include *.shd, *.spl -Force -ErrorAction SilentlyContinue -Verbose

    Write-Host "Starting Print Spooler service..." -ForegroundColor Yellow
    Start-Service -Name Spooler -Verbose
    Write-Host "Spooler cleaned and restarted." -ForegroundColor Green
}

function ListPrinters {
    Write-Host "`nInstalled Printers:" -ForegroundColor Cyan
    Get-Printer | Select-Object Name, PortName, DriverName, PrinterStatus | Format-Table -AutoSize
}

function ExportPrinters {
    $filePath = "$env:USERPROFILE\Desktop\PrintersExport.csv"
    Write-Host "Exporting printer list to $filePath..." -ForegroundColor Cyan
    Get-Printer | Select-Object Name, PortName, DriverName, Shared, Published | Export-Csv -Path $filePath -NoTypeInformation
    Write-Host "Export complete." -ForegroundColor Green
}

function Get-LoggedInUserSelection {
    $users = @()

    try {
        $queryOutput = & quser 2>$null
        if ($LASTEXITCODE -eq 0 -and $queryOutput) {
            foreach ($line in $queryOutput) {
                if ($line -match '^USERNAME' -or [string]::IsNullOrWhiteSpace($line)) { continue }

                $trimmedLine = $line.Trim()
                if ($trimmedLine -match '^(?<user>[^\s]+)') {
                    $userName = $Matches.user.TrimStart('>')
                    if ($userName -and $userName -notin $users) { $users += $userName }
                }
            }
        }
    } catch {
        # Fall back to the console user's session if quser is unavailable.
    }

    if (-not $users) {
        $cimUser = (Get-CimInstance Win32_ComputerSystem).UserName
        if ($cimUser) {
            $users += if ($cimUser -match '\\') { $cimUser.Split('\')[1] } else { $cimUser }
        }
    }

    if (-not $users) { throw "No logged-in user could be detected." }
    if ($users.Count -eq 1) {
        Write-Host "Detected logged-in user: $($users[0])" -ForegroundColor Cyan
        return $users[0]
    }

    Write-Host "Multiple logged-in users detected:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $users.Count; $i++) { Write-Host "[$i] $($users[$i])" }
    $selection = Read-Host "Select the user by number"
    if ($selection -notmatch '^\d+$' -or [int]$selection -lt 0 -or [int]$selection -ge $users.Count) {
        throw "Invalid user selection."
    }

    return $users[[int]$selection]
}

function InstallNetworkPrinter {
    $printerPath = Read-Host "Enter the network printer UNC path (for example, \\printserver\PrinterName)"
    if ($printerPath -notmatch '^\\\\[^\s\\]+\\[^\s]+$') {
        Write-Host "Invalid printer path. Enter a UNC path such as \\printserver\PrinterName." -ForegroundColor Red
        return
    }

    try {
        $loggedUser = Get-LoggedInUserSelection
        $escapedPath = $printerPath.Replace("'", "''")
        $command = "Add-Printer -ConnectionName '$escapedPath' -ErrorAction Stop"
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -Command `"$command`""
        $principal = New-ScheduledTaskPrincipal -UserId $loggedUser -LogonType Interactive
        $taskName = "InstallNetworkPrinter-$([guid]::NewGuid().ToString('N'))"

        Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Force | Out-Null
        Start-ScheduledTask -TaskName $taskName
        Start-Sleep -Seconds 5
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

        Write-Host "Printer installation queued for ${loggedUser}: $printerPath" -ForegroundColor Green
    } catch {
        if ($taskName) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue }
        Write-Host "Unable to install the network printer: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function CheckSpoolerStatus {
    Write-Host "`n--- Print Spooler Service Status ---" -ForegroundColor Cyan
    $spooler = Get-Service Spooler
    $color = if ($spooler.Status -eq 'Running') { "Green" } else { "Red" }
    
    Write-Host "Service Name: $($spooler.Name)"
    Write-Host "Status: " -NoNewline; Write-Host "$($spooler.Status)" -ForegroundColor $color
    Write-Host "Start Type: $($spooler.StartType)"

    Write-Host "`n--- Physical Spool Files ---" -ForegroundColor Cyan
    $spoolPath = "$env:SystemRoot\system32\spool\printers"
    $spoolFiles = Get-ChildItem $spoolPath -File -ErrorAction SilentlyContinue
    if ($spoolFiles) {
        Write-Host "Found $($spoolFiles.Count) raw spool file(s) waiting on disk."
        $spoolFiles | Select-Object Name, LastWriteTime, @{Name="Size(KB)";Expression={"{0:N2}" -f ($_.Length / 1KB)}} | Format-Table -AutoSize
    } else {
        Write-Host "No raw spool files found in directory."
    }

    Write-Host "`n--- Active Print Jobs (Logical Queue) ---" -ForegroundColor Cyan
    try {
        # Fix: Pipe Get-Printer into Get-PrintJob to avoid the 'Parameter set cannot be resolved' error
        $jobs = Get-Printer | Get-PrintJob -ErrorAction SilentlyContinue
        
        if ($jobs) {
            $jobs | Select-Object PrinterName, Document, JobStatus, SubmittedTime | Format-Table -AutoSize
            Write-Host "Total active jobs in queue: $($jobs.Count)" -ForegroundColor Yellow
        } else {
            Write-Host "No active print jobs reported by Windows." -ForegroundColor Gray
        }
    } catch {
        Write-Host "Error retrieving print jobs: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# --- Main Menu ---
do {
    Write-Host "`n==============================" -ForegroundColor Magenta
    Write-Host "   PRINT MANAGEMENT TOOL" -ForegroundColor Magenta
    Write-Host "==============================" -ForegroundColor Magenta
    Write-Host "1. Check Print Spooler Status and Queue"
    Write-Host "2. Restart Print Spooler Service"
    Write-Host "3. Clean up Print Spooler Queue"
    Write-Host "4. List Installed Printers to Screen"
    Write-Host "5. Export Installed Printers to CSV (Desktop)"
    Write-Host "6. Install Network Printer for Logged-In User"
    Write-Host "7. Exit"
    $choice = Read-Host "`nEnter your choice (1-7)"

    switch ($choice) {
        1 { CheckSpoolerStatus }
        2 { RestartSpooler }
        3 { CleanSpooler }
        4 { ListPrinters }
        5 { ExportPrinters }
        6 { InstallNetworkPrinter }
        7 { break }
        default { Write-Host "Invalid choice. Please try again." -ForegroundColor Red }
    }

    if ($choice -ne 7) {
        $again = Read-Host "`nDo you want to perform another action? (y/n)"
        if ($again -eq 'n') { break }
    }
} while ($true)