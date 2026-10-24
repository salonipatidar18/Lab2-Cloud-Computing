# ═══════════════════════════════════════════════════════════════
# scripts/acr-build-push.ps1 — PowerShell version for Windows users
# ═══════════════════════════════════════════════════════════════
# Prerequisites: az CLI logged in (az login), Docker Desktop running
# Usage: .\scripts\acr-build-push.ps1
# ═══════════════════════════════════════════════════════════════
param()
$ErrorActionPreference = "Stop"

# ─── Configuration ─────────────────────────────────────────────
$RESOURCE_GROUP = "qrforge-rg"
$LOCATION       = "eastus"
$ACR_SUFFIX     = -join ((97..122) | Get-Random -Count 6 | ForEach-Object { [char]$_ })
$ACR_NAME       = "qrforgeacr$ACR_SUFFIX"   # Must be globally unique
$IMAGE_TAG      = "qrforge-frontend:v1"
# ───────────────────────────────────────────────────────────────

Write-Host "`n=== STUDENT IDENTITY VERIFICATION ===" -ForegroundColor Cyan
az account show --query "{Azure_Email: user.name, Subscription_ID: id}" -o table
Write-Host "OS User  : $($env:USERNAME)"
Write-Host "Hostname : $($env:COMPUTERNAME)"
Write-Host "Date     : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host ("=" * 46)

Write-Host "`n[1/4] Creating resource group: $RESOURCE_GROUP in $LOCATION..." -ForegroundColor Yellow
az group create --name $RESOURCE_GROUP --location $LOCATION --output table

Write-Host "`n[2/4] Creating ACR: $ACR_NAME (Basic SKU)..." -ForegroundColor Yellow
az acr create `
  --resource-group $RESOURCE_GROUP `
  --name $ACR_NAME `
  --sku Basic `
  --admin-enabled false `
  --output table

Write-Host "`n[3/4] Building & pushing via ACR Tasks (az acr build)..." -ForegroundColor Yellow
Write-Host "      *** SCREENSHOT THIS OUTPUT ***" -ForegroundColor Red
az acr build `
  --registry $ACR_NAME `
  --image $IMAGE_TAG `
  .\frontend `
  --file .\frontend\Dockerfile

Write-Host "`n[4/4] Verification — list images in registry:" -ForegroundColor Yellow
az acr repository list --name $ACR_NAME --output table

Write-Host "`n✅ Done!" -ForegroundColor Green
Write-Host "   Registry : $ACR_NAME.azurecr.io"
Write-Host "   Image    : $ACR_NAME.azurecr.io/$IMAGE_TAG"
Write-Host "`nSave these for the AKS deploy step:"
Write-Host "`$ACR_NAME = `"$ACR_NAME`""
Write-Host "`$RESOURCE_GROUP = `"$RESOURCE_GROUP`""
