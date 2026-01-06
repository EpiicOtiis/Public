<# (W10_ESU_Checker.ps1) :: (Revision 1)/Aaron Pleus, (1/6/2026)

   This script, like all scripts developed by Aaron Pleus, unless otherwise explicitly stated, is the copyrighted property of Aaron Pleus.;
   it may not be shared, sold, or distributed whole or in part, even with modifications applied, for any reason. this includes on reddit, on discord, or as part of other RMM tools.
   	
   The moment you edit this script it becomes your own risk and Aaron Pleus will not provide assistance with it.

.SYNOPSIS
    Checks the local system for active Extended Security Update (ESU) licenses.

.DESCRIPTION
    Queries the SoftwareLicensingProduct class. Includes a "wait" message for the user,
    handles "No ESU Found" scenarios, and formats long product names so they don't cut off.
#>

# 1. Display the wait message to the user
Write-Host "------------------------------------------------------------------" -ForegroundColor Cyan
Write-Host "Initializing ESU License Check..." -ForegroundColor Cyan
Write-Host "Note: This process typically takes 1-5 minutes depending on system load." -ForegroundColor Yellow
Write-Host "------------------------------------------------------------------" -ForegroundColor Cyan

# 2. Capture the results into a variable
# We filter for names containing ESU and ensure a PartialProductKey exists
$esuLicenses = Get-CimInstance -ClassName SoftwareLicensingProduct | 
    Where-Object { $_.Name -like "*ESU*" -and $_.PartialProductKey }

# 3. Logic to handle "No Return Value"
if ($null -eq $esuLicenses) {
    Write-Host ""
    Write-Host "Result: No ESU Active" -ForegroundColor Red -BackgroundColor Black
    Write-Host ""
}
else {
    Write-Host "`nScan Complete. Results below:`n" -ForegroundColor Green

    # 4. Format the output 
    # Use -Wrap to ensure long names (like the Education/Enterprise string) are fully visible
    $esuLicenses | Select-Object `
        @{Name="Product Name"; Expression={$_.Name}},
        @{Name="Status"; Expression={
            switch ($_.LicenseStatus) {
                0 { "Unlicensed" }
                1 { "Licensed (Active)" }
                2 { "OOB Grace" }
                3 { "OOT Grace" }
                4 { "Non-Genuine" }
                5 { "Notification" }
                6 { "Extended Grace" }
                Default { "Unknown" }
            }
        }},
        @{Name="Partial Key"; Expression={$_.PartialProductKey}},
        @{Name="Description"; Expression={$_.Description}} | 
    Format-Table -AutoSize -Wrap
}