# ===============================================================
# scripts/acr-build-push.ps1 - PowerShell version for Windows users
# ===============================================================
# Prerequisites: az CLI logged in (az login), Docker Desktop running
# Usage: .\scripts\acr-build-push.ps1
# ===============================================================
param(
    [string]$Location = "koreacentral",
    [string]$ResourceGroup = "qrforge-rg"
)
$ErrorActionPreference = "Stop"

# --- Configuration ---------------------------------------------
$RESOURCE_GROUP = $ResourceGroup
$LOCATION       = $Location
$ACR_SUFFIX     = -join ((97..122) | Get-Random -Count 6 | ForEach-Object { [char]$_ })
$ACR_NAME       = "qrforgeacr$ACR_SUFFIX"   # Must be globally unique
$IMAGE_TAG      = "qrforge-frontend:v1"
# ---------------------------------------------------------------

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
$buildOutput = az acr build --registry $ACR_NAME --image $IMAGE_TAG .\frontend --file .\frontend\Dockerfile 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Warning "ACR Tasks (az acr build) are disabled on this Azure for Students subscription (TasksOperationsNotAllowed), so the image was built locally with docker build and pushed with docker push."
    Write-Host "Logging into ACR: $ACR_NAME..." -ForegroundColor Cyan
    az acr login --name $ACR_NAME
    Write-Host "Building image locally with docker build..." -ForegroundColor Cyan
    docker build -t $IMAGE_TAG .\frontend -f .\frontend\Dockerfile
    Write-Host "Tagging and pushing image to ACR..." -ForegroundColor Cyan
    docker tag $IMAGE_TAG "$ACR_NAME.azurecr.io/$IMAGE_TAG"
    docker push "$ACR_NAME.azurecr.io/$IMAGE_TAG"
} else {
    Write-Host $buildOutput
}

Write-Host "`n[4/4] Verification - list images in registry:" -ForegroundColor Yellow
az acr repository list --name $ACR_NAME --output table

Write-Host "`n[OK] Done!" -ForegroundColor Green
Write-Host "   Registry : $ACR_NAME.azurecr.io"
Write-Host "   Image    : $ACR_NAME.azurecr.io/$IMAGE_TAG"
Write-Host "`nSave these for the AKS deploy step:"
Write-Host "`$ACR_NAME = '$ACR_NAME'"
Write-Host "`$RESOURCE_GROUP = '$RESOURCE_GROUP'"
