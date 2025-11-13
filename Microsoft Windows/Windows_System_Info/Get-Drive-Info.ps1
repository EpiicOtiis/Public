<# (Get-Drive-Info.ps1) :: (Revision # 1)/Aaron Pleus, (7/15/2025)

   This script, like all scripts developed by Aaron Pleus, unless otherwise explicitly stated, is the copyrighted property of Aaron Pleus.;
   it may not be shared, sold, or distributed whole or in part, even with modifications applied, for any reason. this includes on reddit, on discord, or as part of other RMM tools.
   	
   The moment you edit this script it becomes your own risk and Aaron Pleus will not provide assistance with it.#>

# Pre-gather cluster sizes into a hashtable
$clusterSizes = @{}
Get-CimInstance -ClassName Win32_Volume | Where-Object { $_.DriveLetter -and $_.BlockSize } | ForEach-Object {
    $driveLetter = $_.DriveLetter -replace ":", ""  # Remove colon for matching (e.g., C: -> C)
    $clusterSizes[$driveLetter] = $_.BlockSize
}
Get-Volume | Where-Object { $_.DriveLetter -and -not $clusterSizes.ContainsKey($_.DriveLetter) } | ForEach-Object {
    $driveLetter = $_.DriveLetter
    $fsutilOutput = & fsutil fsinfo ntfsinfo "$($driveLetter):" 2>$null
    if ($fsutilOutput) {
        $clusterLine = $fsutilOutput | Where-Object { $_ -match "Bytes Per Cluster" }
        if ($clusterLine -match "\d+") {
            $clusterSizes[$driveLetter] = [int64]$matches[0]
        }
    }
}

# Main script to gather disk info and match cluster sizes
Get-Disk | ForEach-Object {
    $disk = $_
    $partitions = Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue
    # Debug: Output partition count for each disk
    # Write-Debug "Disk $($disk.Number): Found $($partitions.Count) partitions"
    foreach ($partition in $partitions) {
        $volume = Get-Volume -Partition $partition -ErrorAction SilentlyContinue
        $driveLetter = $partition.DriveLetter
        $clusterSize = if ($driveLetter -and $clusterSizes.ContainsKey($driveLetter)) { $clusterSizes[$driveLetter] } else { $null }
        # Debug: Output partition details
        # Write-Debug "Disk $($disk.Number), Partition $($partition.PartitionNumber): DriveLetter=$driveLetter, Volume=$($volume.FileSystemLabel)"
        [PSCustomObject]@{
            DiskNumber     = $disk.Number
            FriendlyName   = $disk.FriendlyName
            PartitionStyle = $disk.PartitionStyle
            SizeGB         = if ($disk.Size) { [math]::Round($disk.Size / 1GB, 2) } else { "N/A" }
            DriveLetter    = if ($driveLetter) { $driveLetter } else { "N/A" }
            VolumeName     = if ($volume -and $volume.FileSystemLabel) { $volume.FileSystemLabel } else { "N/A" }
            ClusterSizeKB  = if ($clusterSize -and $clusterSize -is [int64]) { [math]::Round($clusterSize / 1KB, 2) } else { "N/A" }
        }
    }
} | Format-Table -AutoSize