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

### Run DFSR_Clear_Conflict_and_Stale_Data_Single_DC Script:
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

### WinGet_Combined.ps1
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/WinGet/WinGet_Combined_V1.ps1'))

# System Information Scripts

### Get-Drive-Info.ps1
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Windows_System_Info/Get-Drive-Info.ps1'))

### Folder-Permissions-Scanner.ps1
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Windows_System_Info/Folder-Permissions-Scanner.ps1'))

# Microsoft 365

## Exchange
