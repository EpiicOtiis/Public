<# (Direct_Send_Monitoring_MS_Spam.ps1) :: (Revision #1)/Aaron Pleus, (9/12/2025)

   This script, like all scripts developed by Aaron Pleus, unless otherwise explicitly stated, is the copyrighted property of Aaron Pleus.;
   it may not be shared, sold, or distributed whole or in part, even with modifications applied, for any reason. this includes on reddit, on discord, or as part of other RMM tools.
   	
   The moment you edit this script it becomes your own risk and Aaron Pleus will not provide assistance with it.
   
   

   Post-Creation Monitoring:
   Check hits: Reports > Mail flow > Mail flow rule reports or use PowerShell:
   Get-MessageTrackingLog -EventId Rule -MessageSubject "[MS Audit Direct Delivery]" | Select-Object Timestamp, Source, Sender, Recipients, MessageSubject
   
   #>

# Ensure script is run with administrative privileges
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "This script must be run as an Administrator. Please restart PowerShell with elevated privileges." -ForegroundColor Red
    exit
}

# Prompt user to check/install ExchangeOnlineManagement module
Write-Host "Checking for ExchangeOnlineManagement module..."
$module = Get-Module -ListAvailable -Name ExchangeOnlineManagement

if (-not $module) {
    $installPrompt = Read-Host "ExchangeOnlineManagement module is not installed. Do you want to install it? (Y/N)"
    if ($installPrompt -eq 'Y' -or $installPrompt -eq 'y') {
        Write-Host "Installing ExchangeOnlineManagement module..."
        Install-Module -Name ExchangeOnlineManagement -Force -Scope CurrentUser
        Write-Host "Module installed successfully."
    } else {
        Write-Host "Module installation skipped. Script cannot proceed without ExchangeOnlineManagement."
        exit
    }
} else {
    $latestVersion = (Find-Module -Name ExchangeOnlineManagement).Version
    $installedVersion = $module.Version | Sort-Object -Descending | Select-Object -First 1
    if ($installedVersion -lt $latestVersion) {
        $updatePrompt = Read-Host "A newer version ($latestVersion) of ExchangeOnlineManagement is available (installed: $installedVersion). Update now? (Y/N)"
        if ($updatePrompt -eq 'Y' -or $updatePrompt -eq 'y') {
            Write-Host "Updating ExchangeOnlineManagement module..."
            Install-Module -Name ExchangeOnlineManagement -Force -Scope CurrentUser
            Write-Host "Module updated successfully."
        }
    } else {
        Write-Host "Latest version ($installedVersion) of ExchangeOnlineManagement is already installed."
    }
}

# Prompt for user inputs
$internalDomain = Read-Host "Enter your internal domain (e.g., yourdomain.com)"
$adminEmail = Read-Host "Enter the admin email for notifications (e.g., youradmin@yourdomain.com)"

# Validate inputs
if (-not $internalDomain -or -not $adminEmail) {
    Write-Host "Error: Domain and admin email are required."
    exit
}

# Derive MX endpoint from domain
$mxEndpoint = "$($internalDomain.Split('.')[0])-com.mail.protection.outlook.com"

# Connect to Exchange Online
Connect-ExchangeOnline -UserPrincipalName $adminEmail

# Define parameters for the transport rule
$ruleName = "MS Audit Direct Delivery"
$ruleComments = "Monitors inbound emails with internal sender domain, external IP, and anonymous authentication for Direct Send detection"
$subjectPrefix = "MS Audit Direct Delivery"

# Create the transport rule
New-TransportRule -Name $ruleName `
    -Comments $ruleComments `
    -Mode AuditAndNotify `
    -FromScope NotInOrganization `
    -SentToScope InOrganization `
    -MessageHeaderMatchesPatterns @{ Header = "X-MS-Exchange-Organization-AuthAs"; Patterns = @("Anonymous") } `
    -SenderDomainIs $internalDomain `
    -PrependSubject $subjectPrefix `
    -BccMessage $adminEmail `
    -GenerateIncidentReport $adminEmail `
    -IncidentReportContent @("Sender", "Recipient", "Subject", "Message-Id", "Received", "ClientIP") `
    -Priority 0 `
    -Enabled $true

# Verify the rule was created
Get-TransportRule -Identity $ruleName | Format-List Name, State, Mode, Priority, FromScope, SentToScope, MessageHeaderMatchesPatterns, SenderDomainIs, PrependSubject, BccMessage, GenerateIncidentReport

# Output confirmation
Write-Host "Transport rule '$ruleName' created successfully. Check rule hits in EAC under Mail flow > Rule reports."

# Prompt for sending a test Direct Send email
$testPrompt = Read-Host "Would you like to send a test Direct Send email to verify the rule? (Y/N)"
if ($testPrompt -eq 'Y' -or $testPrompt -eq 'y') {
    Write-Host "Preparing to send a test Direct Send email..."
    Write-Host "This will send an email from '$adminEmail' to '$adminEmail' using the MX endpoint '$mxEndpoint' on port 25."
    Write-Host "Ensure this PowerShell session is running on a machine with external network access and port 25 open."
    
    $testSender = $adminEmail
    $testRecipient = $adminEmail
    $testSubject = "Test Direct Send Email - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $testBody = "This is a test email to verify Direct Send detection. Sent to $mxEndpoint on port 25."

    try {
        Send-MailMessage -From $testSender `
            -To $testRecipient `
            -Subject $testSubject `
            -Body $testBody `
            -SmtpServer $mxEndpoint `
            -Port 25 `
            -ErrorAction Stop
        Write-Host "Test email sent successfully. Check '$adminEmail' for an email with subject '$subjectPrefix $testSubject'."
        Write-Host "Verify in EAC (Mail flow > Message trace) or run: Get-MessageTrackingLog -EventId Rule -MessageSubject '$subjectPrefix $testSubject'"
    } catch {
        Write-Host "Error sending test email: $_"
        Write-Host "Ensure port 25 is open and '$mxEndpoint' is accessible. Check firewall or network restrictions."
    }
} else {
    Write-Host "Test email skipped. You can manually test by sending an email to '$mxEndpoint' on port 25."
}

# Disconnect from Exchange Online
Disconnect-ExchangeOnline -Confirm:$false