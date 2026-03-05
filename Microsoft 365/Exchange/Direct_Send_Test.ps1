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
} 