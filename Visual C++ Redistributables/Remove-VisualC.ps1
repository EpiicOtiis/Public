<# (Remove-VisualC.ps1) :: (Revision # 1)/Aaron Pleus, (10/24/2025)

   This script, like all scripts developed by Aaron Pleus, unless otherwise explicitly stated, is the copyrighted property of Aaron Pleus.;
   it may not be shared, sold, or distributed whole or in part, even with modifications applied, for any reason. this includes on reddit, on discord, or as part of other RMM tools.
   	
   The moment you edit this script it becomes your own risk and Aaron Pleus will not provide assistance with it.#>


function Get-InstalledCPlusPlus {
    $registryKeys = @(
        "HKLM:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*",
        "HKLM:\\Software\\Wow6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*"
    )

    $installedVersions = Get-ItemProperty $registryKeys | Where-Object { $_.DisplayName -like "Microsoft Visual C++*" } | Select-Object DisplayName, UninstallString
    return $installedVersions
}

function Uninstall-Application {
    param(
        [string]$DisplayName,
        [string]$UninstallString
    )

    Write-Host "Uninstalling $DisplayName..."
    if ($UninstallString) {
        $uninstallArgs = "/uninstall /quiet /norestart"
        $command = "$($UninstallString.Split(' ')[0]) $uninstallArgs"
        try {
            Start-Process -FilePath "cmd.exe" -ArgumentList "/c $UninstallString /quiet /norestart" -Wait -Verb RunAs
            Write-Host "$DisplayName has been uninstalled." -ForegroundColor Green
        }
        catch {
            Write-Host "Error uninstalling $DisplayName. Please try uninstalling it from the Control Panel." -ForegroundColor Red
        }
    }
    else {
        Write-Host "No uninstall string found for $DisplayName." -ForegroundColor Red
    }
}

do {
    Clear-Host
    Write-Host "Scanning for installed C++ Redistributable versions..."
    $cppVersions = Get-InstalledCPlusPlus

    if ($cppVersions.Count -eq 0) {
        Write-Host "No Microsoft Visual C++ Redistributable versions found."
        break
    }

    Write-Host "Installed C++ Redistributable versions:"
    for ($i = 0; $i -lt $cppVersions.Count; $i++) {
        Write-Host "$($i + 1): $($cppVersions[$i].DisplayName)"
    }

    Write-Host "Enter the number of the version to uninstall, or 'q' to quit:"
    $selection = Read-Host

    if ($selection -eq 'q') {
        break
    }

    try {
        $index = [int]$selection - 1
        if ($index -ge 0 -and $index -lt $cppVersions.Count) {
            $versionToUninstall = $cppVersions[$index]
            Uninstall-Application -DisplayName $versionToUninstall.DisplayName -UninstallString $versionToUninstall.UninstallString
            Write-Host "Press Enter to continue..."
            Read-Host
        }
        else {
            Write-Host "Invalid selection. Press Enter to try again." -ForegroundColor Yellow
            Read-Host
        }
    }
    catch {
        Write-Host "Invalid input. Please enter a number or 'q'. Press Enter to try again." -ForegroundColor Yellow
        Read-Host
    }

} while ($true)

Write-Host "Script finished."