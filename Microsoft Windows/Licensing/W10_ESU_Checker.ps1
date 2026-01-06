<# (W10_ESU_Checker.ps1) :: (Revision 1)/Aaron Pleus, (1/6/2026)

   This script, like all scripts developed by Aaron Pleus, unless otherwise explicitly stated, is the copyrighted property of Aaron Pleus.;
   it may not be shared, sold, or distributed whole or in part, even with modifications applied, for any reason. this includes on reddit, on discord, or as part of other RMM tools.
   	
   The moment you edit this script it becomes your own risk and Aaron Pleus will not provide assistance with it.

.SYNOPSIS
    Checks the local system for active Extended Security Update (ESU) licenses.

.DESCRIPTION
    Queries the SoftwareLicensingProduct class via CIM to find licenses 
    containing "ESU" with an installed product key. Returns a formatted table 
    or a "No ESU Active" message if none are found.
#>

# 1. Capture the results into a variable
$esuLicenses = Get-CimInstance -ClassName SoftwareLicensingProduct | 
    Where-Object { $_.Name -like "*ESU*" -and $_.PartialProductKey }

# 2. Check if the variable is null or empty
if ($null -eq $esuLicenses) {
    Write-Host "------------------------------------"
    Write-Host "Result: No ESU Active" -ForegroundColor Yellow
    Write-Host "------------------------------------"
}
else {
    # 3. Format the output for readability
    $esuLicenses | Select-Object `
        @{Name="Product Name"; Expression={$_.Name}},
        @{Name="Status"; Expression={
            # Convert the integer LicenseStatus into a human-readable string
            switch ($_.LicenseStatus) {
                0 { "Unlicensed" }
                1 { "Licensed (Active)" }
                2 { "OOB Grace Period" }
                3 { "OOT Grace Period" }
                4 { "Non-Genuine Grace" }
                5 { "Notification" }
                6 { "Extended Grace" }
                Default { "Unknown" }
            }
        }},
        @{Name="Partial Key"; Expression={$_.PartialProductKey}},
        Description | 
    Format-Table -AutoSize
}