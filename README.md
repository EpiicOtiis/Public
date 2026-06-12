# Public
My public-facing repository for PowerShell scripts.

**Active Directory Scripts**

- **Enable_AD_Recycle_Bin.ps1**: Enables the Active Directory Recycle Bin for the forest, verifies status and replication; requires ActiveDirectory module and admin rights.
- irm https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Active%20Directory/Enable_AD_Recycle_Bin.ps1 | iex

- **AD_Replication_Troubleshooter_v5.ps1**: Gathers AD site/DC info, reports FSMO holders, runs repadmin/dcdiag diagnostics, and checks Directory Service event logs for replication issues.
irm https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Active%20Directory/AD_Replication_Troubleshooter_v5.ps1 | iex

<!-- Hiding this block. The efficacy of these two scripts is questionable, while they work, it they do not resolve the issue they were created for.
### Run DFSR_Clear_Conflict_and_Stale_Data_Multiple_DC Script:
irm https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Active%20Directory/DFSR_Clear_Conflict_and_Stale_Data_Multiple_DC.ps1 | iex

### Run DFSR_Clear_Conflict_and_Stale_Data_Single_DC Script:
irm https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Active%20Directory/DFSR_Clear_Conflict_and_Stale_Data_Single_DC.ps1 | iex
-->

- **Get_AD_Domain_Admins.ps1**: Lists members of the `Domain Admins` group and displays detailed user properties; offers an optional CSV export.
irm https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Active%20Directory/Get_AD_Domain_Admins.ps1 | iex


- **AD_User_Cleanup_V2.ps1**: Interactive, menu-driven AD cleanup and management utility (staging/deleting accounts, BitLocker key checks, audits); logs to `C:\Logs` and exports under `C:\ADCleanup_Exports`.
irm https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Active%20Directory/AD_User_Cleanup_V2.ps1 | iex


**Application Scripts**

- **Remove-Teams.ps1**: Stops Teams processes, removes the Machine-Wide Installer, uninstalls per-user Teams installations, and cleans residual folders.
irm https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Teams/Remove-Teams.ps1 | iex

- **Remove-Zoom.ps1**: Removes Zoom installations found in user profiles (AppData), runs available uninstallers, and removes residual Zoom data.
irm https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Zoom/Remove-Zoom.ps1 | iex

- **Remove-VisualC.ps1**: Scans for installed Microsoft Visual C++ Redistributables and provides an interactive uninstall helper.
irm https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Visual%20C%2B%2B%20Redistributables/Remove-VisualC.ps1 | iex

- **WinGet_Combined_V1.ps1**: Wrapper/utility around `winget` to install, update, or uninstall packages and ensure `winget` is present; offers interactive menu.
irm https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/WinGet/WInGet_Combined_V1.ps1 | iex


**System Information & Utilities**

- **Get-Drive-Info.ps1**: Collects disk/volume information including partition style, size, drive letters and cluster sizes.
irm https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Microsoft%20Windows/Windows_System_Info/Get-Drive-Info.ps1 | iex

- **Share_Report.ps1**: Scans non-administrative SMB shares, summarizes file counts and storage used, and can export results to CSV.
irm https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Microsoft%20Windows/Windows_System_Info/Share_Report.ps1 | iex

- **Folder-Permissions-Scanner.ps1**: Scans a folder tree for ACL entries and exports permission records to CSV (no owner column in this version).
irm https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Microsoft%20Windows/Windows_System_Info/Folder-Permissions-Scanner.ps1 | iex

- **Folder-Permissions-Scanner_V3.ps1**: Similar scanner that includes the folder owner in the output.
irm https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Microsoft%20Windows/Windows_System_Info/Folder-Permissions-Scanner_V3.ps1 | iex

- **Time_Sync_Repair.ps1**: Diagnostic and repair tool for system time, timezone, and related policies; checks privileges, GPOs/Intune settings and suggests fixes.
irm https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Microsoft%20Windows/General%20Troubleshooting/Time_Sync_Repair.ps1 | iex

- **One_Time_Reboot_Scheduler.ps1**: Schedules a one-time reboot for the system (helper used by other scripts).
irm https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Microsoft%20Windows/General%20Troubleshooting/One_Time_Reboot_Scheduler.ps1 | iex

- **Printer_Repair.ps1**: Printer/spooler maintenance tool—restart spooler, clean spool folder, list/export printers, and view queue status.
irm https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Microsoft%20Windows/General%20Troubleshooting/Printer_Repair.ps1 | iex

- **W10_ESU_Checker.ps1**: Checks the local system for active Extended Security Update (ESU) licenses and reports status.
irm https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Microsoft%20Windows/Licensing/W10_ESU_Checker.ps1 | iex

- **Windows_Update_Toolbox.ps1**: Comprehensive Windows Update and repair toolbox—reset/update components, run DISM/SFC, schedule reboots and other utilities.
irm https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Microsoft%20Windows/Patching/Windows_Update_Toolbox.ps1 | iex

- **speedtest.ps1**: Downloads/uses the Ookla Speedtest CLI to run network speed tests and list nearby servers via an interactive menu.
irm https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Microsoft%20Windows/Windows_System_Info/speedtest.ps1 | iex

- **RDP_WKST.ps1**: Interactive utility to inspect and manage Remote Desktop settings on a workstation (enable/disable RDP, NLA, firewall rules, and group membership).
irm https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Microsoft%20Windows/General%20Troubleshooting/RDP_WKST.ps1 | iex

**Microsoft Defender**
- **WEDHealth.ps1**: Health and update script for Microsoft Defender—checks services, versions, triggers signature updates, and assists with onboarding.
irm https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Microsoft%20365/Microsoft%20Defender/WEDHealth.ps1 | iex

# VMWare

## Tools

- **VMWare_Tools_Updater.ps1**: Detects installed VMware Tools version, finds latest available, downloads the installer and offers GUI or silent update.
irm https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/VMWare/VMWare_Tools_Updater.ps1 | iex


# Microsoft 365

**Exchange**

- **Direct_Send_Test.ps1**: Validates Microsoft 365 Direct Send by connecting to MX endpoint and attempting to send a test message (uses port 25, no auth).
irm https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Microsoft%20365/Exchange/Direct_Send_Test.ps1 | iex


# Notes:
Originally I used the traditional Invoke-Expression method of downloading and executing scripts. While there is no firm date on removal of this method, it is depreciated and Microsoft recommends alternative's such as Invoke-WebRequest like this:

iex (iwr 'https://raw.githubusercontent.com/yourname/repo/main/script.ps1' -UseBasicParsing).Content

Or the .NET method:

iex ([System.Net.Http.HttpClient]::new().GetStringAsync('https://example.com/script.ps1').GetAwaiter().GetResult())

I have updated my README file to use the "Invoke-RestMethod" which allows for shorter, more concise code and should still allow for code to be run directly in Powershell. 

Below is an example of the original Invoke-Expression method that I used. Should you run into any issues, I suggest copying the raw URL and pasting it into the example below. I specifically call out the TLS versions that are allowed, which is not a requirement, but I find that it allows this method to work more consistently. 

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13; iex ((New-Object System.Net.WebClient).DownloadString('https://example.com/script.ps1'))
