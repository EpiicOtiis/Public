#Requires -Module ActiveDirectory

# Get the Domain Admins group members
$domainAdmins = Get-ADGroupMember -Identity "Domain Admins" -Recursive | 
    Where-Object { $_.objectClass -eq 'user' }

# Create an array to store the results
$results = @()

# Gather detailed information for each admin
foreach ($admin in $domainAdmins) {
    $user = Get-ADUser -Identity $admin.SamAccountName -Properties *
    
    $results += [PSCustomObject]@{
        Name              = $user.Name
        SamAccountName    = $user.SamAccountName
        UserPrincipalName = $user.UserPrincipalName
        Enabled           = $user.Enabled
        Created           = $user.whenCreated
        LastLogon         = $user.LastLogonDate
        Email             = $user.EmailAddress
        Description       = $user.Description
        Department        = $user.Department
        Title             = $user.Title
    }
}

# Display results in a formatted table
Write-Host "`nDomain Admins Information:" -ForegroundColor Green
$results | Format-Table -AutoSize

# Prompt to export to CSV
$exportChoice = Read-Host "Would you like to export the results to a CSV file? (Y/N)"

if ($exportChoice -eq 'Y' -or $exportChoice -eq 'y') {
    # Prompt for save location
    Write-Host "Please select a location to save the CSV file..."
    
    # Create a SaveFileDialog
    Add-Type -AssemblyName System.Windows.Forms
    $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
    $saveDialog.Filter = "CSV Files (*.csv)|*.csv"
    $saveDialog.Title = "Save Domain Admins Report"
    $saveDialog.FileName = "DomainAdminsReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    
    if ($saveDialog.ShowDialog() -eq 'OK') {
        try {
            $results | Export-Csv -Path $saveDialog.FileName -NoTypeInformation
            Write-Host "Results successfully exported to $($saveDialog.FileName)" -ForegroundColor Green
        }
        catch {
            Write-Host "Error exporting to CSV: $_" -ForegroundColor Red
        }
    }
    else {
        Write-Host "Export cancelled." -ForegroundColor Yellow
    }
}
else {
    Write-Host "Results not exported." -ForegroundColor Yellow
}