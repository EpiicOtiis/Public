<# (Enable_AD_Recycle_Bin.ps1) :: (Revision # 1)/Aaron Pleus, (4/9/2025)

   This script, like all scripts developed by Aaron Pleus, unless otherwise explicitly stated, is the copyrighted property of Aaron Pleus.;
   it may not be shared, sold, or distributed whole or in part, even with modifications applied, for any reason. this includes on reddit, on discord, or as part of other RMM tools.
   	
   The moment you edit this script it becomes your own risk and Aaron Pleus will not provide assistance with it.
#>

# PowerShell Script to Enable Active Directory Recycle Bin
# This script checks if the feature is already enabled before attempting to enable it
# and provides verbose output throughout the process

# Start script and display header
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  ACTIVE DIRECTORY RECYCLE BIN ENABLEMENT SCRIPT" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "Starting script execution at $(Get-Date)" -ForegroundColor Yellow
Write-Host ""

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: This script requires administrative privileges." -ForegroundColor Red
    Write-Host "Please restart PowerShell as an administrator and run the script again." -ForegroundColor Red
    Write-Host ""
    exit
}

# Check if the Active Directory module is installed and import it
Write-Host "Checking for Active Directory PowerShell module..." -ForegroundColor Green
if (Get-Module -ListAvailable -Name ActiveDirectory) {
    Write-Host "Active Directory module found. Importing module..." -ForegroundColor Green
    Import-Module ActiveDirectory
    Write-Host "Active Directory module imported successfully." -ForegroundColor Green
} else {
    Write-Host "ERROR: Active Directory PowerShell module not found." -ForegroundColor Red
    Write-Host "Please install the AD PowerShell module using: Add-WindowsFeature RSAT-AD-PowerShell" -ForegroundColor Red
    Write-Host ""
    exit
}
Write-Host ""

# Get the current Forest information
Write-Host "Retrieving forest information..." -ForegroundColor Green
try {
    $ForestInfo = Get-ADForest
    Write-Host "Forest information retrieved successfully:" -ForegroundColor Green
    Write-Host "  Forest Name: $($ForestInfo.Name)" -ForegroundColor White
    Write-Host "  Forest Functional Level: $($ForestInfo.ForestMode)" -ForegroundColor White
    
    # Check if forest functional level is high enough
    $forestLevel = $ForestInfo.ForestMode.ToString()
    if ($forestLevel -match "2000" -or $forestLevel -match "2003" -or $forestLevel -eq "Windows2008") {
        Write-Host "ERROR: The forest functional level must be at least Windows Server 2008 R2." -ForegroundColor Red
        Write-Host "Current forest functional level: $forestLevel" -ForegroundColor Red
        Write-Host ""
        exit
    }
} catch {
    Write-Host "ERROR: Failed to retrieve forest information." -ForegroundColor Red
    Write-Host "Error details: $_" -ForegroundColor Red
    Write-Host ""
    exit
}
Write-Host ""

# Check if Recycle Bin is already enabled
Write-Host "Checking if AD Recycle Bin is already enabled..." -ForegroundColor Green
try {
    $RecycleBinFeature = Get-ADOptionalFeature -Filter {Name -eq "Recycle Bin Feature"}
    
    if ($RecycleBinFeature.EnabledScopes.Count -gt 0) {
        Write-Host "AD Recycle Bin is ALREADY ENABLED for this forest." -ForegroundColor Yellow
        Write-Host "No action needed. Recycle Bin was enabled on: $($RecycleBinFeature.EnabledScopes[0].EnabledDateTime)" -ForegroundColor Yellow
        Write-Host ""
        
        # Display additional information about the feature
        Write-Host "Current Recycle Bin Status:" -ForegroundColor Cyan
        Write-Host "  Feature Name: $($RecycleBinFeature.Name)" -ForegroundColor White
        Write-Host "  Enabled Scopes: $($RecycleBinFeature.EnabledScopes.Count)" -ForegroundColor White
        Write-Host "  Enabled On: $($RecycleBinFeature.EnabledScopes[0].EnabledDateTime)" -ForegroundColor White
        Write-Host ""
        
        # End script
        Write-Host "Script completed at $(Get-Date)" -ForegroundColor Yellow
        Write-Host "========================================================" -ForegroundColor Cyan
        exit
    } else {
        Write-Host "AD Recycle Bin is currently NOT ENABLED for this forest." -ForegroundColor Yellow
        Write-Host "Proceeding with enablement..." -ForegroundColor Yellow
    }
} catch {
    Write-Host "ERROR: Failed to check AD Recycle Bin status." -ForegroundColor Red
    Write-Host "Error details: $_" -ForegroundColor Red
    Write-Host ""
    exit
}
Write-Host ""

# Enable the AD Recycle Bin
Write-Host "Enabling AD Recycle Bin for forest $($ForestInfo.Name)..." -ForegroundColor Green
try {
    Enable-ADOptionalFeature -Identity "Recycle Bin Feature" -Scope ForestOrConfigurationSet -Target $ForestInfo.Name -Confirm:$false -Verbose
    Write-Host "AD Recycle Bin has been SUCCESSFULLY ENABLED!" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to enable AD Recycle Bin." -ForegroundColor Red
    Write-Host "Error details: $_" -ForegroundColor Red
    Write-Host ""
    exit
}
Write-Host ""

# Verify the Recycle Bin is enabled
Write-Host "Verifying AD Recycle Bin status..." -ForegroundColor Green
try {
    $RecycleBinStatus = Get-ADOptionalFeature -Filter {Name -eq "Recycle Bin Feature"}
    
    if ($RecycleBinStatus.EnabledScopes.Count -gt 0) {
        Write-Host "VERIFICATION SUCCESSFUL: AD Recycle Bin is now enabled." -ForegroundColor Green
        Write-Host "Enabled on: $($RecycleBinStatus.EnabledScopes[0].EnabledDateTime)" -ForegroundColor Green
        
        # Display information about replication
        Write-Host ""
        Write-Host "IMPORTANT REPLICATION INFORMATION:" -ForegroundColor Yellow
        Write-Host "1. The AD Recycle Bin feature has been enabled at the forest level." -ForegroundColor White
        Write-Host "2. This change will replicate to all domain controllers in the forest." -ForegroundColor White
        Write-Host "3. Allow time for AD replication to complete before the feature is available on all DCs." -ForegroundColor White
        Write-Host "4. You can check replication status with: repadmin /replsum" -ForegroundColor White
    } else {
        Write-Host "WARNING: AD Recycle Bin appears to be not enabled despite the command succeeding." -ForegroundColor Red
        Write-Host "Please check manually or try running the script again." -ForegroundColor Red
    }
} catch {
    Write-Host "ERROR: Failed to verify AD Recycle Bin status." -ForegroundColor Red
    Write-Host "Error details: $_" -ForegroundColor Red
}
Write-Host ""

# End script
Write-Host "Script completed at $(Get-Date)" -ForegroundColor Yellow
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""
Read-Host "Press Enter to exit"