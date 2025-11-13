<# One_Time_Reboot_Scheduler.ps1 :: (Revision 1)/Aaron Pleus, (11/7/25)

   This script, like all scripts developed by Aaron Pleus, unless otherwise explicitly stated, is the copyrighted property of Aaron Pleus.;
   it may not be shared, sold, or distributed whole or in part, even with modifications applied, for any reason. this includes on reddit, on discord, or as part of other RMM tools.
   	
   The moment you edit this script it becomes your own risk and Aaron Pleus will not provide assistance with it.

.SYNOPSIS
    Interactively schedules a system reboot for a specified time or for immediately.

.DESCRIPTION
    This script provides a user-friendly way to schedule a system reboot. When executed, it presents a list of options: rebooting immediately or scheduling a reboot for a specific hour of the day (0-23).

    To make the selection easier, the script displays the corresponding 12-hour time format (e.g., "14 (2 PM)") next to each 24-hour option, based on the computer's local time zone settings.

    Upon selection, it creates a high-priority Windows Scheduled Task named 'Local-InteractiveReboot' that runs under the SYSTEM account. This task will execute the reboot at the chosen time. If a task with the same name already exists, it will be removed and replaced.

    A key feature is that the task is configured to run as soon as possible if the scheduled time is missed (e.g., if the computer was turned off).

.EXAMPLE
    .\Interactive-Reboot.ps1

    After running the script, you will see a prompt like this:

    Please choose a time to schedule the reboot:
    - Immediately : Reboot the computer now.
    -           0 : Reboot at hour 0 (12 AM)
    -           1 : Reboot at hour 1 (1 AM)
    ...
    -          14 : Reboot at hour 14 (2 PM)
    ...
    -          23 : Reboot at hour 23 (11 PM)

    Enter your choice (e.g., 14 or Immediately): 14

    The script will then confirm that the reboot has been scheduled for 2:00 PM.

- IMPORTANT: This script must be run with administrative privileges to create the scheduled task.
#>


function Schedule-Reboot {
    param(
        [string]$Time
    )

    if ($Time -eq "Immediately") {
        Write-Host "Executing immediate reboot..." -ForegroundColor Green
        try {
            Start-Process 'shutdown.exe' -ArgumentList '/r /f /t 0 /c "Local script immediate reboot."'
            Write-Host "Reboot initiated successfully." -ForegroundColor Green
            return $true
        } catch {
            Write-Host "Error encountered during immediate reboot: $_" -ForegroundColor Red
            return $false
        }
    }

    try {
        # Convert the hour string to an integer
        $RebootHour = [int]$Time
        $scheduledTime = (Get-Date).Date.AddHours($RebootHour)

        # If the time is in the past, schedule for the next day
        if ($scheduledTime -lt (Get-Date)) {
            $scheduledTime = $scheduledTime.AddDays(1)
        }

        # Check if the task already exists and delete it to prevent conflicts
        if (Get-ScheduledTask -TaskName 'Local-InteractiveReboot' -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName 'Local-InteractiveReboot' -Confirm:$false
            Write-Host "Existing Scheduled Task 'Local-InteractiveReboot' removed." -ForegroundColor Yellow
        }

        Write-Host "Scheduling reboot for: $scheduledTime" -ForegroundColor Cyan

        # Create a scheduled task to reboot the system
        $action = New-ScheduledTaskAction -Execute 'shutdown.exe' -Argument '/r /f /t 60 /c "Local script scheduled reboot."'
        $trigger = New-ScheduledTaskTrigger -At $scheduledTime -Once
        
        # Settings to allow the task to run on batteries and to run as soon as possible if the scheduled time was missed
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        
        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        Register-ScheduledTask -TaskName "Local-InteractiveReboot" -Action $action -Trigger $trigger -Settings $settings -Principal $principal

        Write-Host "Task 'Local-InteractiveReboot' created successfully." -ForegroundColor Green
        return $true
    } catch {
        Write-Host "An error occurred: $_" -ForegroundColor Red
        return $false
    }
}

# --- Main script execution starts here ---

# Generate the list of options for the user
$options = @{}
$options["Immediately"] = "Reboot the computer now."

# Generate time options with 12-hour format descriptions
for ($i = 0; $i -lt 24; $i++) {
    $time = (Get-Date).Date.AddHours($i)
    $friendlyTime = $time.ToString("h tt") # Format to 12-hour time like "3 PM"
    $options[$i.ToString()] = "Reboot at hour $i ($friendlyTime)"
}

# Display the options to the user
Write-Host "Please choose a time to schedule the reboot:" -ForegroundColor White
$options.GetEnumerator() | Sort-Object { if ($_.Name -eq 'Immediately') { -1 } else { [int]$_.Name } } | ForEach-Object {
    Write-Host ("- {0,11} : {1}" -f $_.Name, $_.Value)
}

# Loop until a valid choice is made
while ($true) {
    $choice = Read-Host "Enter your choice (e.g., 14 or Immediately)"
    if ($options.ContainsKey($choice)) {
        break # Exit loop if choice is valid
    } else {
        Write-Host "Invalid selection. Please try again." -ForegroundColor Red
    }
}

# Call the function with the user's choice
Schedule-Reboot -Time $choice