<#
(Folder-Permissions-Scanner_V3.ps1) :: (Revision # 3)/Aaron Pleus - (10/15/2025)

   This script, like all scripts developed by Aaron Pleus, unless otherwise explicitly stated, is the copyrighted property of Aaron Pleus.;
   it may not be shared, sold, or distributed whole or in part, even with modifications applied, for any reason. this includes on reddit, on discord, or as part of other RMM tools.
   	
   The moment you edit this script it becomes your own risk and Aaron Pleus will not provide assistance with it.

# Folder-Permissions-Scanner.ps1
# This script checks permissions for a folder and its subfolders up to a specified depth
# or all levels, and saves the results to a CSV file at a specified location

#>

# Function to prompt for folder path with validation
function Get-FolderPath {
    param(
        [string]$Prompt
    )
    
    do {
        $folderPath = Read-Host -Prompt $Prompt
        if (-not (Test-Path -Path $folderPath -PathType Container)) {
            Write-Host "The specified folder '$folderPath' does not exist or is not accessible. Please try again." -ForegroundColor Red
            $isValid = $false
        } else {
            $isValid = $true
        }
    } while (-not $isValid)
    
    return (Resolve-Path $folderPath).Path
}

# Function to prompt for output file path
function Get-OutputFilePath {
    param(
        [string]$DefaultName = "FolderPermissions.csv"
    )
    
    $outputPath = Read-Host -Prompt "Enter the path for the CSV output file (press Enter for current directory)"
    
    if ([string]::IsNullOrWhiteSpace($outputPath)) {
        $outputPath = (Get-Location).Path
    } elseif (-not (Test-Path -Path $outputPath -PathType Container)) {
        Write-Host "The specified directory does not exist. Using current directory instead." -ForegroundColor Yellow
        $outputPath = (Get-Location).Path
    }
    
    $fileName = Read-Host -Prompt "Enter the filename for the CSV (press Enter for '$DefaultName')"
    
    if ([string]::IsNullOrWhiteSpace($fileName)) {
        $fileName = $DefaultName
    }
    
    if (-not $fileName.EndsWith(".csv")) {
        $fileName += ".csv"
    }
    
    return Join-Path -Path $outputPath -ChildPath $fileName
}

# Function to get permissions and owner for a file or folder
function Get-Permissions {
    param (
        [string]$Path,
        [string]$RootFolder
    )
    
    $Item = Get-Item -Path $Path -Force
    # Get the ACL (Access Control List) which contains permissions and owner information
    $Acl = Get-Acl -Path $Path
    # Get the owner from the ACL
    $Owner = $Acl.Owner
    
    foreach ($Access in $Acl.Access) {
        [PSCustomObject]@{
            Path = $Path
            ItemType = if ($Item.PSIsContainer) { "Folder" } else { "File" }
            Owner = $Owner # Add the owner to the output object
            Level = ($Path.Split('\').Count - $RootFolder.Split('\').Count)
            Identity = $Access.IdentityReference
            AccessType = $Access.AccessControlType
            Rights = $Access.FileSystemRights
            Inherited = $Access.IsInherited
        }
    }
}

# Welcome message
Write-Host "`n===== Folder Permissions Scanner =====`n" -ForegroundColor Cyan

# Get the root folder from user input
$RootFolder = Get-FolderPath -Prompt "Enter the path of the root folder to scan"

# Get the subfolder depth from user input
do {
    $depthInput = Read-Host -Prompt "Enter the maximum subfolder depth to scan (1-10, or enter '0' or 'all' for unlimited depth)"
    
    if ($depthInput -match '^(0|[aA][lL][lL])$') {
        $ScanAllLevels = $true
        $MaxDepth = [int]::MaxValue  # Effectively unlimited
        $isValidDepth = $true
    }
    elseif ($depthInput -match '^\d+$' -and [int]$depthInput -ge 1 -and [int]$depthInput -le 10) {
        $ScanAllLevels = $false
        $MaxDepth = [int]$depthInput
        $isValidDepth = $true
    } 
    else {
        Write-Host "Please enter a valid number between 1 and 10, or '0' or 'all' for unlimited depth." -ForegroundColor Red
        $isValidDepth = $false
    }
} while (-not $isValidDepth)

# Get the output file path from user input
$OutputFile = Get-OutputFilePath -DefaultName "FolderPermissions.csv"

# Display scan configuration
Write-Host "`nScan Configuration:" -ForegroundColor Green
Write-Host "- Root Folder: $RootFolder" -ForegroundColor Green
if ($ScanAllLevels) {
    Write-Host "- Depth: All levels (unlimited)" -ForegroundColor Green
} else {
    Write-Host "- Maximum Depth: $MaxDepth levels" -ForegroundColor Green
}
Write-Host "- Output File: $OutputFile" -ForegroundColor Green
Write-Host "`nPress Enter to start scanning or Ctrl+C to cancel..." -ForegroundColor Yellow
Read-Host | Out-Null

# Store results
$Results = @()

# Get permissions for root folder
Write-Host "`nProcessing root folder: $RootFolder"
$Results += Get-Permissions -Path $RootFolder -RootFolder $RootFolder

# Get all items (files and folders) within the root folder up to the specified depth (or all levels)
$GetChildItemParams = @{
    Path = $RootFolder
    Recurse = $true
    Force = $true
    ErrorAction = "SilentlyContinue"  # To handle potential access denied errors
}

Write-Host "Retrieving folder structure..."

if ($ScanAllLevels) {
    $AllItems = Get-ChildItem @GetChildItemParams
} else {
    $AllItems = Get-ChildItem @GetChildItemParams | 
                Where-Object { 
                    ($_.FullName.Split('\').Count - $RootFolder.Split('\').Count) -le $MaxDepth 
                }
}

$TotalItems = $AllItems.Count
Write-Host "Found $TotalItems items to process."

$CurrentItem = 0
$PermissionsCount = 0
$ErrorCount = 0

foreach ($Item in $AllItems) {
    $CurrentItem++
    $PercentComplete = [math]::Round(($CurrentItem / $TotalItems) * 100, 2)
    Write-Progress -Activity "Processing items" -Status "$CurrentItem of $TotalItems ($PercentComplete%)" -PercentComplete $PercentComplete
    
    # Get the current level relative to the root folder
    $Level = ($Item.FullName.Split('\').Count - $RootFolder.Split('\').Count)
    
    # Only display detailed progress periodically to reduce console output
    if ($CurrentItem % 50 -eq 0 -or $CurrentItem -eq 1 -or $CurrentItem -eq $TotalItems) {
        Write-Host "Processing level $Level item: $($Item.FullName)"
    }
    
    try {
        $ItemPermissions = Get-Permissions -Path $Item.FullName -RootFolder $RootFolder
        $Results += $ItemPermissions
        $PermissionsCount += $ItemPermissions.Count
    }
    catch {
        $ErrorCount++
        if ($ErrorCount -le 5) {  # Only show the first few errors to avoid flooding the console
            Write-Host "Error processing $($Item.FullName): $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

Write-Host "`nSaving results to $OutputFile"
$Results | Export-Csv -Path $OutputFile -NoTypeInformation

Write-Host "`nCompleted! Results saved to $OutputFile"
Write-Host "Total items processed: $($TotalItems + 1) (including root folder)"
Write-Host "Total permission entries: $PermissionsCount"
if ($ErrorCount -gt 0) {
    Write-Host "Encountered $ErrorCount errors during processing." -ForegroundColor Yellow
}