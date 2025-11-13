<# (System_Info_Events_24_Hours.ps1) :: (Revision 1)/Aaron Pleus, (10/28/2025)

   This script, like all scripts developed by Aaron Pleus, unless otherwise explicitly stated, is the copyrighted property of Aaron Pleus.;
   it may not be shared, sold, or distributed whole or in part, even with modifications applied, for any reason. this includes on reddit, on discord, or as part of other RMM tools.
   	
   The moment you edit this script it becomes your own risk and Aaron Pleus will not provide assistance with it.#>

function System_Info {

param(
     
     [Parameter(Mandatory=$true)]
     [int]$Search_Time,
     
     [Parameter(Mandatory=$false)]
     [switch]$MSInfo,

     [Parameter(Mandatory=$false)]
     [switch]$OpenLog
 )

$computername = $env:computername
# Disable error alerting
$ErrorActionPreference = "SilentlyContinue"

# Allow full string/variable output
$FormatEnumerationLimit= -1

# Create search_time_hours variable for readability
$Search_Time_Hours=($Search_Time/24)

# create root outfile
$out_file_info = "$env:windir\temp\$computername-system-info-$(((get-date)).ToString("yyyy-MM-dd-HH-mm-ss")).txt"
$out_msinfo32 = "$env:windir\temp\$computername-msinfo-$(((get-date)).ToString("yyyy-MM-dd-HH-mm-ss")).txt"
out-file $out_file_info

# General system info
 function get_general_system_info {
    $Hostname = $env:computername
    $Memory = (Get-CimInstance -ClassName Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum /1GB
    $FreeDiskSpace = [Math]::Round(((Get-CimInstance -ClassName Win32_LogicalDisk | Measure-Object -Property FreeSpace -Sum).Sum / 1GB),1)
    $OperatingSystem = (Get-CimInstance -ClassName Win32_OperatingSystem).Caption
    $Archietecture = (Get-WmiObject -Class Win32_ComputerSystem | Select-Object -Property SystemType).Systemtype
    $CPUName = (Get-WmiObject -Class Win32_Processor | Select-Object -Property Name).name
    $CPUPhysicalCores = (Get-WmiObject -Class Win32_Processor | Select-Object -Property NumberOfCores).NumberofCores
    $CPULogicalCores = (Get-WmiObject -Class Win32_Processor | Select-Object -Property NumberOfLogicalProcessors).NumberoFLogicalProcessors
    
    write-output "
    Hostname: $Hostname
    OS: $OperatingSystem
    CPU archietecture: $Archietecture
    CPU Name: $CPUName
    CPU physical cores: $CPUPhysicalCores
    CPU logical cores: $CPULogicalCores
    Total Memory: $Memory
    Free disk space: $FreeDiskSpace    
    "
    }

# Get user and group membership info
function get_user_and_group_info {
$ErrorActionPreference = "SilentlyContinue"
$Got_Users = get-localuser | select-object name |ft -HideTableHeaders|out-string
$Administrators = try {get-localgroupmember "Administrators" -ErrorAction Stop| select-object name |ft -HideTableHeaders|out-string} catch { get-adgroupmember "Administrators" -ErrorAction Stop| select-object name |ft -HideTableHeaders|out-string}
$Remote_Desktop_Users = try {get-localgroupmember "Remote Desktop Users" -ErrorAction Stop| select-object name |ft -HideTableHeaders|out-string} catch { get-adgroupmember "Remote Desktop Users" -ErrorAction Stop| select-object name |ft -HideTableHeaders|out-string}
$Domain_Admins = try {get-adgroupmember "Domain Admins" -ErrorAction Stop | select-object name |ft -HideTableHeaders|out-string} catch {"Group not found on this system"}
$Schema_Admins = try {get-adgroupmember "Schema Admins" -ErrorAction Stop | select-object name |ft -HideTableHeaders|out-string} catch {"Group not found on this system"}
$Exchange_Admins = try {get-adgroupmember "Exchange Admins"-ErrorAction Stop | select-object name |ft -HideTableHeaders|out-string} catch {"Group not found on this system"}
$Enterprise_Admins = try {get-adgroupmember "Enterprise Admins" -ErrorAction Stop| select-object name |ft -HideTableHeaders|out-string} catch {"Group not found on this system"}


write-output "
Users:
$Got_Users

Administrators group members:
$Administrators

Remote Desktop Users group members:
$Remote_Desktop_Users

Domain Admins group members:
$Domain_Admins

Schema Admins group members:
$Schema_Admins

Exchange Admins group members:
$Exchange_Admins

Enterprise Admins group members:
$Enterprise_Admins
"
}

# Total Memory/CPU usage over 5 samples:
function Get_total_cpu_mem {
$totalRam = (Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property capacity -Sum).Sum
$count = 0
while($count -lt 5) {
    $date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $cpuTime = (Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples.CookedValue
    $availMem = (Get-Counter '\Memory\Available MBytes').CounterSamples.CookedValue
    $date + ' > CPU: ' + $cpuTime.ToString("#,0.000") + '%, Avail. Mem.: ' + $availMem.ToString("N0") + 'MB (' + (104857600 * $availMem / $totalRam).ToString("#,0.0") + '%)'
    Start-Sleep -s 2
    $count++
}
}

# List the boot time and uptime:
function Get_boot_and_uptime {
$bootuptime = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
$CurrentDate = Get-Date
$uptime = $CurrentDate - $bootuptime
write-Output "
Last boot: $bootuptime
System has been online for $($uptime.days) days, $($uptime.hours) hours, and $($uptime.minutes) minutes..."
}

# Top 10 processes based on memory utilization:
function Get_top_process_memory {
Get-WmiObject WIN32_PROCESS | Sort-Object -Property ws -Descending | Select-Object -first 10 ProcessID,Name,WS
        }

# Top processes based on cpu utilization:
function Get_top_process_cpu {
    Get-Counter "\Process(*)\% Processor Time" -ErrorAction SilentlyContinue `
    | Select-Object -ExpandProperty CounterSamples `
    | Where-Object {$_.Status -eq 0 -and $_.instancename -notin "_total", "idle", "" -and $_.CookedValue/$env:NUMBER_OF_PROCESSORS -gt 0} `
    | Sort-Object CookedValue -Descending `
        | Select-Object @{N="Hostname";E={$env:COMPUTERNAME}},
        @{N="ProcessName";E={
            $friendlyName = $_.InstanceName
            try {
                $procId = [System.Diagnostics.Process]::GetProcessesByName($_.InstanceName)[0].Id
                $proc = Get-WmiObject -Query "SELECT ProcessId, ExecutablePath FROM Win32_Process WHERE ProcessId =$procId"
                $procPath = ($proc | where { $_.ExecutablePath } | select -First 1).ExecutablePath
                $friendlyName = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($procPath).FileDescription
            } catch { }
            $friendlyName
        }},
        @{N="CPU_Percent";E={[System.Math]::Round(($_.CookedValue/$env:NUMBER_OF_PROCESSORS), 2)}},
        @{N="TimeStamp";E={Get-Date -Format 'dd/MM/yyyy HH:mm:ss.fff'}} -First 10
        }


function Get-Top-10-Events
{

param(
     [Parameter(Mandatory=$true)]
     [string]$Event_Log,
 
     [Parameter(Mandatory=$true)]
     [int]$Search_Time_Sub,
     
     [Parameter(Mandatory=$false)]
     [string[]]$Event_IDs 
 )

$script:EventsArray = @()
if($PSBoundParameters.ContainsKey('Event_IDs'))
{
$Events = Get-winevent -FilterHashtable @{logname=$Event_Log;StartTime = (Get-Date).AddMinutes(-$Search_Time_Sub);id = $Event_IDs} | select-object -Property Providername, id, message, timecreated, leveldisplayname
}
else
{
$Events = Get-winevent -FilterHashtable @{logname=$Event_Log;StartTime = (Get-Date).AddMinutes(-$Search_Time_Sub)} | Where-Object -FilterScript {($_.Level -eq 1) -or ($_.Level -eq 2) -or ($_.Level -eq 3)} | select-object -Property Providername, id, message, timecreated, leveldisplayname
}
$script:eventcount = 0

Write-Host ""
Write-Host "Retrieving recent notable events from the $Event_Log event log..." -ForegroundColor Yellow
add-content -path $out_file_info -value "`r`n----------------------------------------> $Event_Log events <----------------------------------------`r`n"

foreach ($event in $events)  {
        
        $Message=$event.Message.replace(","," ").replace("`t"," ").replace("'"," ").replace("\","\\").replace("`n"," ").replace("`r`n"," ").replace("`r"," ").replace("    "," ").replace("   "," ").replace("  "," ")
        
        $script:EventsArray += New-Object -TypeName PSObject -Property @{
            
        "Source" = $event[0].Providername
        "LevelDisplayName" = $event.leveldisplayname
        "Message" = $message
        "EventID" = $event.id        
        "TimeCreated" = $event.TimeCreated            
}
      
   $script:eventcount ++       
    }
    
  $GroupedEvents=$script:EventsArray | group message | sort -Descending count | select-object -first 10

foreach ($Event in $GroupedEvents)
    {
                   
        $Source = $Event.Group[0].Source
        $EventID = $Event.Group[0].EventID        
        $Count = $Event.Group.count
        $TimeCreated = $Event.Group[0].TimeCreated      
        $Message = $Event.Group[0].Message
        $LevelDisplayName = $Event.Group[0].LevelDisplayName
 

"--($Source) (ID: $EventID) ($LevelDisplayName) ($TimeCreated) (Count: $Count)--"| out-file $out_file_info -append
$Message | out-file $out_file_info -append
"" | out-file $out_file_info -append

 }
  if($script:eventcount -eq 0)
  {
  "No notable events found in $Event_Log..." | out-file $out_file_info -append
    Write-Host "...done" -ForegroundColor Green
    Write-Host ""
  }
  else
  {
  "Finished scanning the last $Search_Time_Hours hours of $Event_Log events and found $script:eventcount notable events..." | out-file $out_file_info -append
    Write-Host "...done" -ForegroundColor Green
    Write-Host ""
  }
}

Write-Host ""
Write-Host "Beginning info gathering..."

# General system info
Write-Host "Retrieving general system info..." -ForegroundColor Yellow
add-content -path $out_file_info -value "`r`n----------------------------------------> General system info <----------------------------------------"
Get_general_system_info |out-file $out_file_info -append
add-content -path $out_file_info -value "(Uptime)"
Get_boot_and_uptime |out-file $out_file_info -append
add-content -path $out_file_info -value "`r`n(CPU and memory total usage)`r`n"
Get_total_cpu_mem |out-file $out_file_info -append
add-content -path $out_file_info -value "`r`n(Top processes by CPU usage)"
Get_top_process_cpu |out-file $out_file_info -append
add-content -path $out_file_info -value "(Top processes by memory usage)"
Get_top_process_memory |out-file $out_file_info -append
Write-Host "...done" -ForegroundColor Green
Write-Host ""

# Hotfixes
Write-Host "Retrieving hotfix info..." -ForegroundColor Yellow
add-content -path $out_file_info -value "`r`n----------------------------------------> Hotfix info <----------------------------------------`r`n"
Get-WmiObject -Class Win32_QuickFixEngineering | Select-Object -Property Description, HotFixID, InstalledOn |sort-object InstalledOn -Descending|ft -autosize|out-file $out_file_info -append
Get-HotFix |sort-object InstalledOn -Descending|ft -autosize |out-file $out_file_info -append
Write-Host "...done" -ForegroundColor Green
Write-Host ""

# Software info
Write-Host "Retrieving software info..." -ForegroundColor Yellow
add-content -path $out_file_info -value "`r`n----------------------------------------> Software info (x64) <----------------------------------------`r`n"
Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\* |select-object DisplayName, Publisher, DisplayVersion, InstallDate, InstallLocation |sort-object InstallDate -Descending|ft -autosize|out-string -width 4096| out-file $out_file_info -append
add-content -path $out_file_info -value "`r`n----------------------------------------> Software info (x86) <----------------------------------------`r`n"
Get-ItemProperty HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* |select-object DisplayName, Publisher, DisplayVersion, InstallDate, InstallLocation |sort-object InstallDate -Descending|ft -autosize|out-string -width 4096|out-file $out_file_info -append
Write-Host "...done" -ForegroundColor Green
Write-Host ""

# User and group info
Write-Host "Retrieving user and group info..." -ForegroundColor Yellow
add-content -path $out_file_info -value "`r`n----------------------------------------> User and group info <----------------------------------------`r`n"
Get_user_and_group_info |out-file $out_file_info -append
Write-Host "...done" -ForegroundColor Green
Write-Host ""

# Top recent alerts and warnings
Get-Top-10-Events -Event_Log 'System' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Application' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Security' -Search_Time $Search_Time -Event_IDs 4625,1102,4720,4722,4723,4725,4728,4732,4756,4738,4740,4767,4735,4737,4755,4772,4777,4616,4950,5025,5031,5152,5153,5155,5157
Get-Top-10-Events -Event_Log 'Setup' -Search_Time $Search_Time -Event_IDs 1,2,4,8,7,9,10,13,14
Get-Top-10-Events -Event_Log 'Microsoft-Windows-Diagnostics-Performance/Operational' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-Storage-ClassPnP/Operational' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-Storage-Storport/Operational' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-SMBClient/Connectivity' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-SMBServer/Operational' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-Time-Service/Operational' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-User Profile Service/Operational' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-VolumeSnapshot-Driver/Operational' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-Windows Defender/Operational' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-WLAN-AutoConfig/Operational' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-Wired-AutoConfig/Operational' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-GroupPolicy/Operational' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-Kernel-PnP/Device Configuration' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-NetworkProfile/Operational' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-TerminalServices-Gateway/Operational' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-TerminalServices-Gateway/Admin' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-TerminalServices-Licensing/Operational' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-RemoteDesktopServices-RDPCoreTS/Operational' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-RemoteDesktopServices-RemoteFXSynth/Operational' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-RDP-Desktop-Management-Service/Operational' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-RemoteDesktop-Management-Service-Management/Operational' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-RemoteApp-and-Desktop-Connection-Management/Operational' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-RemoteApp-and-Desktop-Connection-Management/Admin' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-RemoteApp-and-Desktop-Connections/Operational' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-RemoteDesktopServices-SessionServices/Operational' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-TerminalServices-ClientActiveXCore/Operational' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-TerminalServices-ClientUSBDevices/Operational' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-TerminalServices-LocalSessionManager/Admin' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-TerminalServices-PnPDevices/Operational' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-TerminalServices-PnPDevices/Admin' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-TerminalServices-Printers/Operational' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-TerminalServices-Printers/Admin' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Admin' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-TerminalServices-RDPClient/Operational' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-TerminalServices-RemoteUSBConnectionManager/Operational' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-TerminalServices-SessionBroker/Operational' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-TerminalServices-SessionBroker/Admin' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-TerminalServices-SessionBroker-Client/Operational' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-TerminalServices-SessionBroker-Client/Admin' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-TerminalServices-TSAppSrvAgent/Operational' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-TerminalServices-TSAppSrvMSI/Operational' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-TerminalServices-TSAppSrvTSM/Operational' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-TerminalServices-TSAppSrvTSVIP/Operational' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-TerminalServices-TSFairShare/Operational' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-TerminalServices-PTP-Provider/Operational' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'DFS Replication' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Directory Service' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'DNS Server' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-DHCP Server Events/Admin' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-DHCP Server Events/Operational' -Search_Time $Search_Time
Get-Top-10-Events -Event_Log 'Microsoft-Windows-Ntfs/Operational' -Search_Time $Search_Time

# Network information
Write-Host "Retrieving network info..." -ForegroundColor Yellow
add-content -path $out_file_info -value "`r`n----------------------------------------> Network info <----------------------------------------`r`n"
ipconfig /all|out-file -append $out_file_info
get-netneighbor|out-file -append $out_file_info
Get-NetAdapter | select-object Name,ifIndex,Status,MacAddress,LinkSpeed,InterfaceDescription |ft -autosize|out-string -width 4096|out-file -append $out_file_info
Get-NetAdapterAdvancedProperty | select-object DisplayName, DisplayValue, ValidDisplayValues |ft -autosize|out-string -width 4096|out-file -append $out_file_info
Write-Host "...done" -ForegroundColor Green
Write-Host ""

# Storage information
Write-Host "Retrieving storage info..." -ForegroundColor Yellow
add-content -path $out_file_info -value "`r`n----------------------------------------> Disk info <----------------------------------------`r`n"
fsutil behavior query DisableDeleteNotify |ft -autosize|out-string -width 4096|out-file -append $out_file_info
Get-PhysicalDisk | Select-Object * |ft -autosize|out-string -width 4096|out-file -append $out_file_info
Get-Disk | Select-Object * |ft -autosize|out-string -width 4096|out-file -append $out_file_info
Get-Volume | Select-Object * |ft -autosize|out-string -width 4096|out-file -append $out_file_info
Get-Partition | Select-Object * |ft -autosize|out-string -width 4096|out-file -append $out_file_info
Write-Host "...done" -ForegroundColor Green
Write-Host ""

# System information
if($MSInfo.IsPresent)
{
Write-Host "Retrieving MSInfo32 info...this may take a few minutes to complete...hold your horses..." -ForegroundColor Yellow
add-content -path $out_file_info -value "`r`n----------------------------------------> System info <----------------------------------------`r`n"
msinfo32 /report $out_msinfo32 | Out-Null
get-content -path $out_msinfo32 | add-content -path $out_file_info
Write-Host "...done" -ForegroundColor Green
Write-host ""
}
else
{
Write-Host "Skipping retrieval of MSInfo32 info since the -MSInfo switch wasn't specified..." -ForegroundColor Yellow
Write-host ""
}

if($OpenLog.IsPresent)
{
notepad $out_file_info
}
else
{
Write-Host "Skipping opening the log file in notepad since the -OpenLog switch wasn't specified..." -ForegroundColor Yellow
Write-host ""
}
Write-Host "Information gathering complete and saved to $out_file_info..."
}