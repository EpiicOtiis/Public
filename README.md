# Public
My public facing repository for scripts

Run Enable_AD_RecycleBin Script:
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $url = 'https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Active%20Directory/Enable_AD_Recycle_Bin.ps1' + '?t=' + [DateTime]::Now.Ticks; iex ((New-Object System.Net.WebClient).DownloadString($url) | Out-String)