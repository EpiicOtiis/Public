<#
 This command does the following:

Get-ADUser -Filter * retrieves all AD users.
-Properties specifies which properties to retrieve.
Select-Object chooses which properties to include in the output.
The @{...} construct formats the LastLogonDate nicely.
Export-Csv saves the results to a CSV file.
To run this command, you'll need:

PowerShell with Active Directory module installed.
Appropriate permissions to query AD.
#>

Get-ADUser -Filter * -Properties Name, SamAccountName, Enabled, LastLogonDate | Select-Object Name, SamAccountName, Enabled, @{Name='LastLogonDate';Expression={if ($_.LastLogonDate) {$_.LastLogonDate.ToString('yyyy-MM-dd HH:mm:ss')} else {'Never logged on'}}} | Export-Csv -Path "C:\ADUserInfo.csv" -NoTypeInformation