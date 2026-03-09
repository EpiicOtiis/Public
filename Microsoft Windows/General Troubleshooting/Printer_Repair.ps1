# Combined Printer Maintenance Script
# Revision 2 / Aaron Pleus, (3/9/26)
#
# This script provides a menu for printer cleanup and listing functionalities.
# Copyright: Aaron Pleus/Integris IT - Do not share or distribute.

function RestartSpooler {
    Write-Host "Stopping Print Spooler service..."
    Get-Service *spool* | Stop-Service -Force -Verbose
    Start-Sleep -Seconds 5

    Write-Host "Starting Print Spooler service..."
    Get-Service Spooler | Start-Service -Verbose
}

function CleanSpooler {
    Write-Host "Stopping Print Spooler service..."
    Get-Service *spool* | Stop-Service -Force -Verbose
    Start-Sleep -Seconds 5

    Write-Host "Removing queued print jobs..."
    $path = $env:SystemRoot + "\system32\spool\printers"
    Get-ChildItem $path -File | Remove-Item -Force -Verbose

    Write-Host "Starting Print Spooler service..."
    Get-Service Spooler | Start-Service -Verbose
}

function ListPrinters {
    Write-Host "`nInstalled Printers:"
    Get-Printer | Select-Object Name, PortName, DriverName | Format-Table -AutoSize
}

function CheckSpoolerStatus {
    Write-Host "`nPrint Spooler Service Status:"
    $spooler = Get-Service Spooler
    Write-Host "Service Name: $($spooler.Name)"
    Write-Host "Display Name: $($spooler.DisplayName)"
    Write-Host "Status: $($spooler.Status)"
    Write-Host "Start Type: $($spooler.StartType)"

    Write-Host "`nPrint Jobs in Queue:"
    try {
        $jobs = Get-Printer | ForEach-Object { Get-PrintJob -PrinterName $_.Name }
        if ($jobs) {
            $jobs | Select-Object Name, Document, JobStatus, SubmittedTime | Format-Table -AutoSize
            Write-Host "Total jobs in queue: $($jobs.Count)"
        } else {
            Write-Host "No print jobs in the queue."
        }
    } catch {
        Write-Host "Unable to retrieve print jobs. Error: $($_.Exception.Message)"
        Write-Host "Note: Retrieving print jobs may require administrative privileges or the Print Spooler service to be running."
    }
}

do {
    Write-Host "`nMenu:"
    Write-Host "1. Check Print Spooler Status and Queue"
    Write-Host "2. Restart Print Spooler Service"
    Write-Host "3. Clean up Print Spooler Queue"
    Write-Host "4. List Installed Printers to Screen"
    Write-Host "5. Export Installed Printers to CSV"
    Write-Host "6. Exit"
    $choice = Read-Host "Enter your choice (1-6)"

    switch ($choice) {
        1 { CheckSpoolerStatus }
        2 { RestartSpooler }
        3 { CleanSpooler }
        4 { ListPrinters }
        5 { ExportPrinters }
        6 { break }
        default { Write-Host "Invalid choice. Please try again." }
    }

    if ($choice -ne 6) {
        $again = Read-Host "Do you want to perform another action? (y/n)"
        if ($again -ne 'y') { break }
    }
} while ($true)