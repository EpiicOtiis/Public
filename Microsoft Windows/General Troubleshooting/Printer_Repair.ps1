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

function ExportPrinters {
    Write-Host "Exporting printer list to C:\Printers.csv..."
    Get-Printer | Select-Object Name, PortName, DriverName | Export-Csv C:\Printers.csv -NoTypeInformation
    Write-Host "Export complete."
}

do {
    Write-Host "`nMenu:"
    Write-Host "1. Restart Print Spooler Service"
    Write-Host "2. Clean up Print Spooler Queue"
    Write-Host "3. List Installed Printers to Screen"
    Write-Host "4. Export Installed Printers to CSV"
    Write-Host "5. Exit"
    $choice = Read-Host "Enter your choice (1-5)"

    switch ($choice) {
        1 { RestartSpooler }
        2 { CleanSpooler }
        3 { ListPrinters }
        4 { ExportPrinters }
        5 { break }
        default { Write-Host "Invalid choice. Please try again." }
    }

    if ($choice -ne 5) {
        $again = Read-Host "Do you want to perform another action? (y/n)"
        if ($again -ne 'y') { break }
    }
} while ($true)