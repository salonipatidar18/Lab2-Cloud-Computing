# ===============================================================
# scripts/aks-create.ps1 - Create AKS cluster (PowerShell)
# ===============================================================
# Prerequisites: acr-build-push completed; $ACR_NAME provided
# Usage: .\scripts\aks-create.ps1 -AcrName "qrforgeacrhrzsue"
# ===============================================================
param(
    [Parameter(Mandatory=$false)]
    [string]$AcrName = $(if ($env:ACR_NAME) { $env:ACR_NAME } elseif (Test-Path "$PSScriptRoot\..\.acr_name") { (Get-Content "$PSScriptRoot\..\.acr_name").Trim() } else { "qrforgeacrhrzsue" }),
    [string]$ResourceGroup = "qrforge-rg",
    [string]$Location = "koreacentral",
    [string]$ClusterName = "qrforge-aks",
    [int]$NodeCount = 1,
    [string]$NodeVmSize = "Standard_B2s_v2",
    [string]$LogWorkspaceName = "qrforge-logs"
)

$ErrorActionPreference = "Stop"

if (-not $AcrName) {
    Write-Error "AcrName is required. Pass via -AcrName or set `$env:ACR_NAME"
}

Write-Host "Identity verification..." -ForegroundColor Cyan
& "$PSScriptRoot\identity.ps1"

Write-Host "`n[1/6] Ensuring resource group exists: $ResourceGroup in $Location..." -ForegroundColor Yellow
az group create --name $ResourceGroup --location $Location --output table

Write-Host "`n[2/6] Creating Log Analytics workspace for Container Insights..." -ForegroundColor Yellow
$LogWorkspaceId = (az monitor log-analytics workspace create `
    --resource-group $ResourceGroup `
    --workspace-name $LogWorkspaceName `
    --location $Location `
    --query id -o tsv).Trim()

Write-Host "        Workspace ID: $LogWorkspaceId"

Write-Host "`n[3/6] Creating AKS cluster: $ClusterName" -ForegroundColor Yellow
Write-Host "        Node SKU: $NodeVmSize, Count: $NodeCount, Location: $Location"
Write-Host "        *** SCREENSHOT THIS OUTPUT ***" -ForegroundColor Red

az aks create `
    --resource-group $ResourceGroup `
    --name $ClusterName `
    --location $Location `
    --node-count $NodeCount `
    --node-vm-size $NodeVmSize `
    --attach-acr $AcrName `
    --enable-addons monitoring `
    --workspace-resource-id $LogWorkspaceId `
    --enable-managed-identity `
    --generate-ssh-keys `
    --output table

Write-Host "`n[4/6] Getting credentials (merges into ~/.kube/config)..." -ForegroundColor Yellow
az aks get-credentials `
    --resource-group $ResourceGroup `
    --name $ClusterName `
    --overwrite-existing

Write-Host "`n[5/6] Verifying cluster connection..." -ForegroundColor Yellow
kubectl get nodes -o wide

Write-Host "`n[6/6] Verifying metrics server..." -ForegroundColor Yellow
kubectl get deployment metrics-server -n kube-system

Write-Host "`n[OK] AKS cluster ready!" -ForegroundColor Green
Write-Host "   Cluster : $ClusterName"
Write-Host "   RG      : $ResourceGroup"
Write-Host "   Location: $Location"
Write-Host ""
Write-Host "Next: Apply Kubernetes manifests in k8s/ folder."
