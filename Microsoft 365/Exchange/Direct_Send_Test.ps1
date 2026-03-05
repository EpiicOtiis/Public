<#
.SYNOPSIS
    Tests Microsoft 365 Direct Send capability for email delivery verification

.DESCRIPTION
    This script validates that your Microsoft 365 organization can successfully send
    emails via Direct Send without using an authenticated SMTP connection. It connects
    to the Microsoft 365 MX endpoint and sends a test email to verify direct send is
    working properly.

.NOTES
    - The From address must be from a verified domain in your Microsoft 365 tenant
    - Direct Send uses port 25 and does not require authentication
    - This is useful for testing mail flow and diagnosing delivery issues

.EXAMPLE
    .\Direct_Send_Test.ps1
    Runs the script and prompts for all required parameters interactively
#>

# --- Function to Test Network Connectivity ---
function Test-SMTPConnectivity {
    param(
        [string]$SMTPServer,
        [string]$Port
    )
    
    Write-Host "`nTesting network connectivity to $SMTPServer on port $Port..." -ForegroundColor Yellow
    $result = Test-NetConnection -ComputerName $SMTPServer -Port $Port
    $result  # Display full Test-NetConnection output
    
    if ($result.TcpTestSucceeded) {
        Write-Host "Success: Network connection to $SMTPServer`:$Port is available" -ForegroundColor Green
    }
    else {
        Write-Host "Failed: Cannot reach $SMTPServer on port $Port. Check firewall rules and network connectivity." -ForegroundColor Red
    }
}

# --- Configuration ---
$SMTPServer = Read-Host "Enter SMTP Server (e.g., yourdomain-com.mail.protection.outlook.com)"
$Port = Read-Host "Enter Port number (default: 25)"
$From = Read-Host "Enter From address (must be verified domain email)"
$To = Read-Host "Enter To address"
$Subject = Read-Host "Enter Subject line"
$Body = Read-Host "Enter Message body"
 
# --- Execution ---
try {
    Send-MailMessage -SmtpServer $SMTPServer `
                     -Port $Port `
                     -From $From `
                     -To $To `
                     -Subject $Subject `
                     -Body $Body `
                     -ErrorAction Stop
    Write-Host "Success: Message sent to $To" -ForegroundColor Green
}
catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Test-SMTPConnectivity -SMTPServer $SMTPServer -Port $Port
} 