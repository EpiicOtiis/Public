# Public
My public facing repository for scripts

# Active Directory Scripts

### Run Enable_AD_RecycleBin Script:
irm https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Active%20Directory/Enable_AD_Recycle_Bin.ps1 | iex

### Run AD_Replication_Troubleshooter Script:
irm https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Active%20Directory/AD_Replication_Troubleshooter_v5.ps1 | iex
<!-- Hiding this block. The efficacy of these two scripts is questionable, while they work, it they do not resolve the issue they were created for.
### Run DFSR_Clear_Conflict_and_Stale_Data_Multiple_DC Script:
irm https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Active%20Directory/DFSR_Clear_Conflict_and_Stale_Data_Multiple_DC.ps1 | iex

### Run DFSR_Clear_Conflict_and_Stale_Data_Single_DC Script:
irm https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Active%20Directory/DFSR_Clear_Conflict_and_Stale_Data_Single_DC.ps1 | iex
-->
### Get_AD_Domain_Admins.ps1
irm https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Active%20Directory/Get_AD_Domain_Admins.ps1 | iex

### Get_AD_Domain_Users.ps1 (Exports output to C:\ADUserInfo.csv)
irm https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Active%20Directory/Get_AD_Domain_Admins.ps1 | iex

# Application Scripts

### Remove-Teams.ps1
irm https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Teams/Remove-Teams.ps1 | iex

### Remove-Zoom.ps1
irm https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Zoom/Remove-Zoom.ps1 | iex

### Remove-VisualC.ps1
irm https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Visual%20C%2B%2B%20Redistributables/Remove-VisualC.ps1 | iex

### WinGet_Combined.ps1
irm https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/WinGet/WInGet_Combined_V1.ps1 | iex

# System Information Scripts

### Get-Drive-Info.ps1
irm https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Microsoft%20Windows/Windows_System_Info/Get-Drive-Info.ps1 | iex

### Folder-Permissions-Scanner.ps1
#### This version will not include folder owner in the output
irm https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Microsoft%20Windows/Windows_System_Info/Folder-Permissions-Scanner.ps1 | iex

### Folder-Permissions-Scanner-v3.ps1
#### This version will include folder owner in the output
irm https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Microsoft%20Windows/Windows_System_Info/Folder-Permissions-Scanner_V3.ps1 | iex

### Time_Sync_Repair.ps1
irm https://github.com/EpiicOtiis/Public/blob/main/Microsoft%20Windows/General%20Troubleshooting/Time_Sync_Repair.ps1 | iex

### One_Time_Reboot_Scheduler.ps1
irm https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Microsoft%20Windows/General%20Troubleshooting/One_Time_Reboot_Scheduler.ps1 | iex

### Windows_Update_Toolbox.ps1
irm https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Microsoft%20Windows/Patching/Windows_Update_Toolbox.ps1 | iex

irm https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Microsoft%20Windows/Patching/Windows_Update_Toolbox.ps1 | iex

# VMWare

## Tools

### VMWare_Tools_Updater.ps1
irm https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/VMWare/VMWare_Tools_Updater.ps1 | iex

<!-- 

# Microsoft 365

## Exchange

-->

# Notes:
Originally I used the traditional Invoke-Expression method of downloading and executing scripts. While there is no firm date on removal of this method, it is depreciated and Microsoft recommends alternative's such as Invoke-WebRequest like this:

iex (iwr 'https://raw.githubusercontent.com/yourname/repo/main/script.ps1' -UseBasicParsing).Content

Or the .NET method:

iex ([System.Net.Http.HttpClient]::new().GetStringAsync('https://example.com/script.ps1').GetAwaiter().GetResult())

I have updated my README file to use the "Invoke-RestMethod" which allows for shorter, more concise code and should still allow for code to be run directly in Powershell. 

Below is an example of the original Invoke-Expression method that I used. Should you run into any issues, I suggest copying the raw URL and pasting it into the example below. I specifically call out the TLS versions that are allowed, which is not a requirement, but I find that it allows this method to work more consistently. 

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13; iex ((New-Object System.Net.WebClient).DownloadString('https://example.com/script.ps1'))