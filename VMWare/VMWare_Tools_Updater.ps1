<# (VMWare_Tools_Updater.ps1) :: (Revision # 1)/Aaron Pleus, (11/13/2025)

   This script, like all scripts developed by Aaron Pleus, unless otherwise explicitly stated, is the copyrighted property of Aaron Pleus.;
   it may not be shared, sold, or distributed whole or in part, even with modifications applied, for any reason. this includes on reddit, on discord, or as part of other RMM tools.
   	
   The moment you edit this script it becomes your own risk and Aaron Pleus will not provide assistance with it.#>

# --- Set modern security protocols for web requests ---
# This is crucial for connecting to modern web servers that have deprecated older protocols.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

# --- 1. Get the installed version of VMware Tools ---
function Get-InstalledVMwareToolsVersion {
    try {
        $installedTools = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" |
                          Where-Object { $_.DisplayName -like "*VMware Tools*" } |
                          Select-Object -First 1

        if ($installedTools) {
            return $installedTools.DisplayVersion
        } else {
            return $null
        }
    }
    catch {
        Write-Warning "Could not retrieve VMware Tools version. Please ensure the script is run with appropriate permissions."
        return $null
    }
}

# --- 2. Get the latest version from VMware's website ---
function Get-LatestVMwareToolsInfo {
    param (
        [string]$MajorVersion
    )

    try {
        $releasesUrl = "https://packages.vmware.com/tools/releases/"
        $response = Invoke-WebRequest -Uri $releasesUrl -UseBasicParsing

        # Parse the collection of hyperlinks from the page. This is more reliable than scraping raw text.
        $versionStrings = $response.Links.href |
                          Where-Object { $_ -match "^$MajorVersion\.\d+\.\d+/" } |
                          ForEach-Object { $_.TrimEnd('/') }

        if (-not $versionStrings) {
            Write-Warning "Could not find any version links for major version $MajorVersion on the releases page."
            return $null
        }
        
        # Sort the strings by casting them to [Version] objects to ensure a proper numeric sort.
        $latestVersionNumber = $versionStrings | Sort-Object -Descending { [System.Version]$_ } | Select-Object -First 1

        if (-not $latestVersionNumber) {
            Write-Warning "Could not determine the latest version for major version $MajorVersion."
            return $null
        }

        # Construct URL to the specific version's download page, accounting for different path structures
        $versionUrlPath = if ($MajorVersion -eq "12") { "x64/" } else { "windows/x64/" }
        $versionUrl = "https://packages.vmware.com/tools/releases/$latestVersionNumber/$versionUrlPath"

        $installerPage = Invoke-WebRequest -Uri $versionUrl -UseBasicParsing
        
        # Find the installer .exe file on the page
        $installerFile = ($installerPage.Content | Select-String -Pattern 'VMware-tools-.*?x64\.exe' -AllMatches).Matches.Value | Select-Object -First 1

        if ($installerFile) {
            return [PSCustomObject]@{
                Url     = "$versionUrl$installerFile"
                Version = $latestVersionNumber
            }
        } else {
             Write-Warning "Could not find the installer file on the release page for version $latestVersionNumber."
             return $null
        }
    }
    catch {
        Write-Warning "Failed to retrieve the latest VMware Tools version from the website. Error: $($_.Exception.Message)"
        return $null
    }
}

# --- Main Script Logic ---
$installedVersion = Get-InstalledVMwareToolsVersion

if (-not $installedVersion) {
    Write-Host "VMware Tools is not installed or could not be detected."
    exit
}

Write-Host "Installed VMware Tools Version: $installedVersion"

$majorInstalledVersion = ($installedVersion -split '\.')[0]

if ($majorInstalledVersion -ne "12" -and $majorInstalledVersion -ne "13") {
    Write-Host "This script only supports updating versions 12.x.x and 13.x.x of VMware Tools."
    exit
}

$latestToolsInfo = Get-LatestVMwareToolsInfo -MajorVersion $majorInstalledVersion

if (-not $latestToolsInfo) {
    exit
}

$latestToolsUrl = $latestToolsInfo.Url
$latestVersion = $latestToolsInfo.Version

Write-Host "Latest available version for major version $majorInstalledVersion is: $latestVersion"

# Using .Trim() to avoid any issues with trailing spaces when comparing versions
if ([version]$installedVersion.Trim() -ge [version]$latestVersion.Trim()) {
    Write-Host "You are already running the latest or a newer version of VMware Tools for this major release."
    exit
}

# --- 3. Prompt for update ---
$updateConfirmation = ""
while ($updateConfirmation -ne 'y' -and $updateConfirmation -ne 'n') {
    $updateConfirmation = Read-Host "An update is available. Do you want to download and install version $latestVersion? (y/n)"
    $updateConfirmation = $updateConfirmation.ToLower()
}

if ($updateConfirmation -ne 'y') {
    Write-Host "Update cancelled by the user."
    exit
}

# --- 4. Download the installer ---
$downloadPath = "$env:TEMP\vmtools.exe"
Write-Host "Downloading VMware Tools version $latestVersion..."
Write-Host "From URL: $latestToolsUrl" # Display the URL for verification
try {
    Invoke-WebRequest -Uri $latestToolsUrl -OutFile $downloadPath
    Write-Host "Download complete. Installer saved to $downloadPath"
}
catch {
    # *** IMPROVED ERROR REPORTING ***
    # This will now display the specific reason for the download failure.
    Write-Warning "Failed to download the VMware Tools installer. Error: $($_.Exception.Message)"
    exit
}

# --- 5. Prompt for installation type ---
$installType = ""
while ($installType -ne "gui" -and $installType -ne "silent") {
    $installType = Read-Host "How would you like to install? (GUI/Silent)"
    $installType = $installType.ToLower()
}

Write-Host "Starting VMware Tools installation..."
try {
    if ($installType -eq 'gui') {
        Start-Process -FilePath $downloadPath -Wait
    }
    elseif ($installType -eq 'silent') {
        Start-Process -FilePath $downloadPath -ArgumentList '/S /v"/qn REBOOT=ReallySuppress"' -Wait
    }
    Write-Host "VMware Tools installation process finished."
}
catch {
    Write-Warning "An error occurred during the installation. Error: $($_.Exception.Message)"
    exit
}

# --- 6. Prompt to schedule a reboot ---
$rebootConfirmation = ""
while ($rebootConfirmation -ne 'y' -and $rebootConfirmation -ne 'n') {
    $rebootConfirmation = Read-Host "Installation is complete. Would you like to schedule a one-time reboot? (y/n)"
    $rebootConfirmation = $rebootConfirmation.ToLower()
}

if ($rebootConfirmation -eq 'y') {
    Write-Host "Scheduling a one-time reboot..."
    try {
        # The SecurityProtocol line is already at the top of the script, so it's not needed here again.
        iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Microsoft%20Windows/General%20Troubleshooting/One_Time_Reboot_Scheduler.ps1'))
    }
    catch {
        Write-Warning "Failed to download and execute the reboot scheduler script. Error: $($_.Exception.Message)"
    }
}
else {
    Write-Host "Reboot not scheduled. Please reboot the machine at your earliest convenience."
}

Write-Host "Script finished."