# Public
My public facing repository for scripts

# Active Directory Scripts

### Run Enable_AD_RecycleBin Script:
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13;`
iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Active%20Directory/Enable_AD_Recycle_Bin.ps1'))

### Run AD_Replication_Troubleshooter Script:
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13;
iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Active%20Directory/AD_Replication_Troubleshooter_v5.ps1'))

### Run DFSR_Clear_Conflict_and_Stale_Data_Multiple_DC Script:
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13;
iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Active%20Directory/DFSR_Clear_Conflict_and_Stale_Data_Multiple_DC.ps1'))

### Run DFSR_Authoritative_Restore_Single_DC Script:
#### This script performs an authoritative restore of the SYSVOL folder on a single Domain Controller. It is designed to fix DFSR errors caused by the server being offline or isolated for longer than the 'MaxOfflineTimeInDays' threshold.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13;
iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Active%20Directory/DFSR_Clear_Conflict_and_Stale_Data_Single_DC.ps1'))

### Get_AD_Domain_Admins.ps1
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Active%20Directory/Get_AD_Domain_Admins.ps1'))

### Get_AD_Domain_Users.ps1 (Exports output to C:\ADUserInfo.csv)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Active%20Directory/Get_AD_Domain_Admins.ps1'))

# Application Scripts

### Remove-Teams.ps1
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Teams/Remove-Teams.ps1'))

### Remove-Zoom.ps1
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Zoom/Remove-Zoom.ps1'))

### Remove-VisualC.ps1
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Visual%20C%2B%2B%20Redistributables/Remove-VisualC.ps1'))

### WinGet_Combined.ps1
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/WinGet/WInGet_Combined_V1.ps1'))

# System Information Scripts

### Get-Drive-Info.ps1
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Microsoft%20Windows/Windows_System_Info/Get-Drive-Info.ps1'))

### Folder-Permissions-Scanner.ps1
#### This version will not include folder owner in the output
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Microsoft%20Windows/Windows_System_Info/Folder-Permissions-Scanner.ps1'))

### Folder-Permissions-Scanner-v3.ps1
#### This version will include folder owner in the output
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Microsoft%20Windows/Windows_System_Info/Folder-Permissions-Scanner_V3.ps1'))

### Time_Sync_Repair.ps1
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13; iex ((New-Object System.Net.WebClient).DownloadString('https://github.com/EpiicOtiis/Public/blob/main/Microsoft%20Windows/General%20Troubleshooting/Time_Sync_Repair.ps1'))

### One_Time_Reboot_Scheduler.ps1
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Microsoft%20Windows/General%20Troubleshooting/One_Time_Reboot_Scheduler.ps1'))

### Windows_Update_Toolbox.ps1
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Microsoft%20Windows/Patching/Windows_Update_Toolbox.ps1'))

# VMWare

## Tools

### VMWare_Tools_Updater.ps1
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/VMWare/VMWare_Tools_Updater.ps1'))

# Microsoft 365

## Exchange
