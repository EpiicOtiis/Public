# Public
My public facing repository for scripts

## Run Enable_AD_RecycleBin Script:
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13;`
iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Active%20Directory/Enable_AD_Recycle_Bin.ps1'))

## Run AD_Replication_Troubleshooter Script:
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13;
iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Active%20Directory/AD_Replication_Troubleshooter_v3.ps1'))

## Remove-Teams.ps1
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Teams/Remove-Teams.ps1'))

## Remove-Zoom.ps1
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Zoom/Remove-Zoom.ps1'))

## Get_AD_Domain_Admins.ps1
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Active%20Directory/Get_AD_Domain_Admins.ps1'))

## Get_AD_Domain_Users.ps1 (Exports output to C:\ADUserInfo.csv)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Active%20Directory/Get_AD_Domain_Admins.ps1'))