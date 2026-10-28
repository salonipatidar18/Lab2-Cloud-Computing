# ===============================================================
# scripts/identity.ps1 - Student Identity Verification (PowerShell)
# Run this BEFORE every screenshot command to prove your identity
# ===============================================================

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "        STUDENT IDENTITY VERIFICATION         " -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
az account show --query "{Azure_Email: user.name, Subscription_ID: id}" -o table
Write-Host ""
Write-Host "OS User  : $($env:USERNAME)"
Write-Host "Hostname : $($env:COMPUTERNAME)"
Write-Host "Date     : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "==============================================" -ForegroundColor Cyan
