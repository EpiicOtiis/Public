<#
.SYNOPSIS
    Interactive helper to configure the same local registry policy value used by
    Computer Configuration > Administrative Templates > Network > DNS Client >
    Turn off multicast name resolution.

.DESCRIPTION
    This script controls LLMNR by setting or removing:

        HKLM\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient\EnableMulticast

    GPO equivalent behavior:
        - DisableLLMNR   -> GPO setting "Turn off multicast name resolution" = Enabled
                            EnableMulticast = 0
        - EnableLLMNR    -> GPO setting "Turn off multicast name resolution" = Disabled
                            EnableMulticast = 1
        - NotConfigured  -> Remove EnableMulticast value

    By default the script runs interactively. It can also be called with -Action.

.EXAMPLES
    .\Set-LLMNRMulticastPolicy.ps1

    Run the interactive menu.

.EXAMPLES
    .\Set-LLMNRMulticastPolicy.ps1 -Action DisableLLMNR

    Disable LLMNR by setting EnableMulticast to 0.

.EXAMPLES
    .\Set-LLMNRMulticastPolicy.ps1 -Action DisableLLMNR -RunRebootScheduler

    Disable LLMNR, then optionally invoke the external reboot scheduler script.

.NOTES
    Must be run from an elevated PowerShell session.
    A domain GPO that later configures this same value can overwrite this local change.
#>

[CmdletBinding()]
param(
    [ValidateSet('Interactive', 'Status', 'DisableLLMNR', 'EnableLLMNR', 'NotConfigured')]
    [string]$Action = 'Interactive',

    [switch]$RunRebootScheduler,

    [switch]$NoExternalScriptPrompt
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$PolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'
$ValueName = 'EnableMulticast'
$RebootSchedulerUri = 'https://raw.githubusercontent.com/EpiicOtiis/Public/refs/heads/main/Microsoft%20Windows/General%20Troubleshooting/One_Time_Reboot_Scheduler.ps1'

function Test-IsAdministrator {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-IsAdministrator {
    if (-not (Test-IsAdministrator)) {
        throw 'This script must be run from an elevated PowerShell session. Right-click PowerShell and choose Run as administrator.'
    }
}

function Get-LlmnrPolicyState {
    $valueExists = $false
    $value = $null

    if (Test-Path -Path $PolicyPath) {
        $item = Get-ItemProperty -Path $PolicyPath -Name $ValueName -ErrorAction SilentlyContinue
        if ($null -ne $item -and $item.PSObject.Properties.Name -contains $ValueName) {
            $valueExists = $true
            $value = [int]$item.$ValueName
        }
    }

    if (-not $valueExists) {
        $state = 'NotConfigured'
        $meaning = 'Policy value is not present. LLMNR is not disabled by this policy value.'
        $gpoEquivalent = 'Turn off multicast name resolution = Not Configured'
    }
    elseif ($value -eq 0) {
        $state = 'LLMNRDisabled'
        $meaning = 'LLMNR is disabled by policy.'
        $gpoEquivalent = 'Turn off multicast name resolution = Enabled'
    }
    elseif ($value -eq 1) {
        $state = 'LLMNREnabled'
        $meaning = 'LLMNR is explicitly enabled by policy.'
        $gpoEquivalent = 'Turn off multicast name resolution = Disabled'
    }
    else {
        $state = 'Unexpected'
        $meaning = "Unexpected EnableMulticast value: $value"
        $gpoEquivalent = 'Unknown'
    }

    [pscustomobject]@{
        ComputerName  = $env:COMPUTERNAME
        RegistryPath  = $PolicyPath
        ValueName     = $ValueName
        ValuePresent  = $valueExists
        ValueData     = $value
        State         = $state
        Meaning       = $meaning
        GpoEquivalent = $gpoEquivalent
    }
}

function Show-LlmnrPolicyState {
    $state = Get-LlmnrPolicyState

    Write-Host ''
    Write-Host 'Current LLMNR multicast-name-resolution policy state' -ForegroundColor Cyan
    Write-Host '---------------------------------------------------' -ForegroundColor Cyan
    Write-Host "Computer:       $($state.ComputerName)"
    Write-Host "Registry path:  $($state.RegistryPath)"
    Write-Host "Value name:     $($state.ValueName)"
    Write-Host "Value present:  $($state.ValuePresent)"
    Write-Host "Value data:     $($state.ValueData)"
    Write-Host "State:          $($state.State)"
    Write-Host "Meaning:        $($state.Meaning)"
    Write-Host "GPO equivalent: $($state.GpoEquivalent)"
    Write-Host ''
}

function Set-LlmnrPolicyState {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('DisableLLMNR', 'EnableLLMNR', 'NotConfigured')]
        [string]$DesiredState
    )

    switch ($DesiredState) {
        'DisableLLMNR' {
            New-Item -Path $PolicyPath -Force | Out-Null
            New-ItemProperty -Path $PolicyPath -Name $ValueName -Value 0 -PropertyType DWord -Force | Out-Null
            Write-Host 'Applied: LLMNR disabled. GPO equivalent: Turn off multicast name resolution = Enabled.' -ForegroundColor Green
        }
        'EnableLLMNR' {
            New-Item -Path $PolicyPath -Force | Out-Null
            New-ItemProperty -Path $PolicyPath -Name $ValueName -Value 1 -PropertyType DWord -Force | Out-Null
            Write-Host 'Applied: LLMNR explicitly enabled. GPO equivalent: Turn off multicast name resolution = Disabled.' -ForegroundColor Yellow
        }
        'NotConfigured' {
            if (Test-Path -Path $PolicyPath) {
                $item = Get-ItemProperty -Path $PolicyPath -Name $ValueName -ErrorAction SilentlyContinue
                if ($null -ne $item -and $item.PSObject.Properties.Name -contains $ValueName) {
                    Remove-ItemProperty -Path $PolicyPath -Name $ValueName -Force
                    Write-Host 'Applied: policy value removed. GPO equivalent: Turn off multicast name resolution = Not Configured.' -ForegroundColor Yellow
                }
                else {
                    Write-Host 'No change: policy value was already absent.' -ForegroundColor Yellow
                }
            }
            else {
                Write-Host 'No change: policy key was already absent.' -ForegroundColor Yellow
            }
        }
    }

    try {
        Clear-DnsClientCache -ErrorAction Stop
        Write-Host 'DNS client cache cleared.' -ForegroundColor Green
    }
    catch {
        try {
            ipconfig.exe /flushdns | Out-Null
            Write-Host 'DNS client cache flushed with ipconfig.' -ForegroundColor Green
        }
        catch {
            Write-Host 'Could not clear DNS client cache. This does not mean the registry change failed.' -ForegroundColor Yellow
        }
    }
}

function Invoke-ExternalRebootScheduler {
    Write-Host ''
    Write-Host 'External reboot scheduler' -ForegroundColor Cyan
    Write-Host '-------------------------' -ForegroundColor Cyan
    Write-Host "URI: $RebootSchedulerUri"
    Write-Host ''

    if (-not $NoExternalScriptPrompt) {
        Write-Warning 'This will download and execute an external PowerShell script in the current elevated session.'
        Write-Warning 'Only continue if you trust the source and have reviewed the script.'
        $confirmation = Read-Host 'Type RUN to download and execute the reboot scheduler, or press Enter to skip'
        if ($confirmation -ne 'RUN') {
            Write-Host 'Skipped reboot scheduler.' -ForegroundColor Yellow
            return
        }
    }

    Invoke-RestMethod -Uri $RebootSchedulerUri | Invoke-Expression
}

function Prompt-ForRebootScheduler {
    $choice = Read-Host 'Would you like to run the external reboot scheduler now? Type Y to run it, or press Enter to skip'
    if ($choice -match '^[Yy]$') {
        Invoke-ExternalRebootScheduler
    }
    else {
        Write-Host 'Skipped reboot scheduler.' -ForegroundColor Yellow
    }
}

function Show-Menu {
    while ($true) {
        Show-LlmnrPolicyState
        Write-Host 'Choose an action:' -ForegroundColor White
        Write-Host '  1) Disable LLMNR  - GPO equivalent: Turn off multicast name resolution = Enabled'
        Write-Host '  2) Enable LLMNR   - GPO equivalent: Turn off multicast name resolution = Disabled'
        Write-Host '  3) Not Configured - Remove EnableMulticast policy value'
        Write-Host '  4) Run external reboot scheduler'
        Write-Host '  5) Refresh/show status'
        Write-Host '  Q) Quit'
        Write-Host ''

        $selection = Read-Host 'Enter selection'
        switch ($selection.ToUpperInvariant()) {
            '1' {
                Set-LlmnrPolicyState -DesiredState DisableLLMNR
                Show-LlmnrPolicyState
                Prompt-ForRebootScheduler
            }
            '2' {
                Set-LlmnrPolicyState -DesiredState EnableLLMNR
                Show-LlmnrPolicyState
                Prompt-ForRebootScheduler
            }
            '3' {
                Set-LlmnrPolicyState -DesiredState NotConfigured
                Show-LlmnrPolicyState
                Prompt-ForRebootScheduler
            }
            '4' {
                Invoke-ExternalRebootScheduler
            }
            '5' {
                Show-LlmnrPolicyState
            }
            'Q' {
                Write-Host 'Exiting.' -ForegroundColor Cyan
                return
            }
            default {
                Write-Host 'Invalid selection. Please try again.' -ForegroundColor Red
            }
        }
    }
}

Assert-IsAdministrator

switch ($Action) {
    'Interactive' {
        Show-Menu
    }
    'Status' {
        Show-LlmnrPolicyState
    }
    'DisableLLMNR' {
        Show-LlmnrPolicyState
        Set-LlmnrPolicyState -DesiredState DisableLLMNR
        Show-LlmnrPolicyState
        if ($RunRebootScheduler) {
            Invoke-ExternalRebootScheduler
        }
    }
    'EnableLLMNR' {
        Show-LlmnrPolicyState
        Set-LlmnrPolicyState -DesiredState EnableLLMNR
        Show-LlmnrPolicyState
        if ($RunRebootScheduler) {
            Invoke-ExternalRebootScheduler
        }
    }
    'NotConfigured' {
        Show-LlmnrPolicyState
        Set-LlmnrPolicyState -DesiredState NotConfigured
        Show-LlmnrPolicyState
        if ($RunRebootScheduler) {
            Invoke-ExternalRebootScheduler
        }
    }
}
